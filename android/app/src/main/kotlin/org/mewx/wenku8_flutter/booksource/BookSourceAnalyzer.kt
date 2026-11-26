package org.mewx.wenku8_flutter.booksource

import com.jayway.jsonpath.JsonPath
import java.io.StringWriter
import java.util.Locale
import javax.xml.transform.OutputKeys
import javax.xml.transform.TransformerFactory
import javax.xml.transform.dom.DOMSource
import javax.xml.transform.stream.StreamResult
import javax.xml.xpath.XPathConstants
import javax.xml.xpath.XPathFactory
import org.jsoup.Jsoup
import org.jsoup.helper.W3CDom
import org.jsoup.nodes.Document
import org.jsoup.nodes.Element
import org.jsoup.parser.Parser
import org.mozilla.javascript.Context
import org.mozilla.javascript.NativeArray
import org.mozilla.javascript.Scriptable
import org.w3c.dom.Node
import org.w3c.dom.NodeList

internal class BookSourceAnalyzer(
    private val source: BookSource,
    private val http: BookSourceHttp,
    private val js: BookSourceJs,
    private val variables: BookSourceVariables? = null,
) {
    fun expand(
        template: String,
        key: String = "",
        page: Int = 1,
        baseUrl: String = source.key,
        content: Any? = null,
        book: BookData? = null,
        chapter: ChapterData? = null,
    ): String {
        if (!template.contains("{{")) return template
        return BookSourceUrlRule.expression.replace(template) { match ->
            val expression = match.groupValues[1].trim()
            when (expression) {
                "key" -> key
                "page" -> page.toString()
                "baseUrl" -> baseUrl
                "" -> ""
                // Legado also allows rule expressions inside {{...}}, such as
                // {{$.book_id}}, not only JavaScript.
                else -> if (isRuleExpression(expression)) {
                    getString(
                        expression,
                        RuleContext(
                            content = content,
                            baseUrl = baseUrl,
                            key = key,
                            page = page,
                            book = book,
                            chapter = chapter,
                        ),
                    )
                } else {
                    js.eval(
                        expression,
                        JsEnv(source, this, content, baseUrl, key, page, book, chapter, variables = variables),
                    ).let { value ->
                        if (value is Number) Context.toString(value) else value?.toString().orEmpty()
                    }
                }
            }
        }
    }

    /**
     * Legado 的 getString 会把 CSS/XPath/JSONPath 命中的多条结果用换行拼接
     * （简介、作者、标签常常是多段），只有 JS 规则保留单值语义。
     */
    fun getString(rule: String?, context: RuleContext): String {
        if (rule.isNullOrBlank()) return ""
        val values = getStrings(rule, context).filter { it.isNotBlank() }
        if (values.isEmpty()) return ""
        val text = if (containsScript(rule)) values.first() else values.joinToString("\n")
        // Legado 的 getString 默认做 HTML4 反转义（&amp;、&#39; 等），
        // 书名/作者/地址规则经常直接从属性或 JSON 里取到转义文本。
        return if (text.indexOf('&') >= 0) {
            org.jsoup.parser.Parser.unescapeEntities(text, false)
        } else {
            text
        }
    }

    private fun containsScript(rule: String): Boolean =
        rule.contains("@js:", ignoreCase = true) ||
            rule.contains("@webjs:", ignoreCase = true) ||
            rule.contains("<js>", ignoreCase = true)

    fun getStrings(rule: String?, context: RuleContext): List<String> {
        if (rule.isNullOrBlank()) return emptyList()
        return flatten(evaluate(rule, context)).map(::stringValue)
    }

    fun nextPageUrls(rule: String?, context: RuleContext, visited: Set<String>): List<String> =
        getStrings(rule, context).asSequence()
            .flatMap { it.lineSequence() }
            .map { http.resolve(context.redirectUrl.ifBlank { context.baseUrl }, it) }
            .filter { it.isNotBlank() && http.pageKey(it) !in visited }
            .distinctBy { http.pageKey(it) }
            .toList()

    /**
     * 正文规则可能返回单个容器、若干段落节点或文本节点。像
     * `//div[@id=content]/p`、`//div[@id=content]/text()` 这类规则会产生多条
     * 结果，只取第一条会让章节只剩开头一段。这里拼接全部非空结果：元素保留
     * 外层 HTML（段落由 <p>/<div> 等标签自身表达，避免丢标签后段落粘连），
     * 纯文本节点按段落用空行分隔。Dart 侧再统一还原段落、<br> 和 <img>。
     */
    fun getContent(rule: String?, context: RuleContext): String {
        if (rule.isNullOrBlank()) return ""
        val parts = flatten(evaluate(rule, context)).mapNotNull { value ->
            when (value) {
                null -> null
                is Element -> ContentPart(
                    value.outerHtml().ifBlank { value.text() }.trim(),
                    plain = false,
                    block = isBlockElement(value.tagName()),
                )
                is Document -> ContentPart(
                    value.body()?.html()?.trim().orEmpty(),
                    plain = false,
                    block = true,
                )
                is String -> ContentPart(value.trim(), plain = true, block = false)
                else -> ContentPart(
                    stringValue(value).trim(),
                    plain = true,
                    block = false,
                )
            }?.takeIf { it.text.isNotEmpty() }
        }
        if (parts.isEmpty()) return ""
        val out = StringBuilder(parts.first().text)
        for (index in 1 until parts.size) {
            val part = parts[index]
            val previous = parts[index - 1]
            // 文本节点各成一段；块级元素自身的标签已经提供段落边界。
            out.append(
                when {
                    part.plain || previous.plain -> "\n\n"
                    part.block || previous.block -> ""
                    else -> "\n"
                },
            )
            out.append(part.text)
        }
        return out.toString()
    }

    private data class ContentPart(
        val text: String,
        val plain: Boolean,
        val block: Boolean,
    )

    /**
     * 有些书源的正文规则会把章节标题一起匹配进来。阅读器已经用目录标题单独
     * 渲染章节头，这里把正文开头重复的标题块剥掉，避免标题在正文里再出现一次。
     * 只处理与目录标题能对上的开头块，匹配不上时原样返回。
     */
    fun stripLeadingChapterTitle(content: String, title: String): String {
        val wanted = titleKey(title)
        if (wanted.isEmpty() || content.isBlank()) return content
        val fragment = Jsoup.parseBodyFragment(content)
        val body = fragment.body()
        val top = body.children().filter { it.text().isNotBlank() }
        if (top.isEmpty()) return stripPlainTextTitle(content, wanted)
        // 正文容器常把标题包在内部（<div id="content"><h1>第12章 …</h1>…），
        // 顶层只有一个容器时改为检查容器内的块。
        val blocks = if (top.size == 1) {
            top[0].children().filter { it.text().isNotBlank() }.ifEmpty { top }
        } else {
            top
        }

        // 部分页面把书名、站点名放在标题之前，只看第一块会漏掉重复标题。
        var removed: List<Element> = emptyList()
        for (index in 0 until minOf(blocks.size, 3)) {
            val block = blocks[index]
            val text = titleKey(block.text())
            if (isChapterNumber(block.text())) {
                val next = blocks.getOrNull(index + 1)
                if (next != null &&
                    titleKey(block.text() + next.text()) == wanted
                ) {
                    removed = listOf(block, next)
                    break
                }
            }
            if (text == wanted ||
                (isHeading(block) && matchesHeading(text, wanted))
            ) {
                removed = listOf(block)
                break
            }
        }
        if (removed.isEmpty()) return content
        for (element in removed) element.remove()
        // 正文只有标题时保持原样，避免整章被判为空。
        if (body.text().isBlank()) return content
        return body.html().trim()
    }

    private fun stripPlainTextTitle(content: String, wanted: String): String {
        val lines = content.split('\n')
        val index = lines.indexOfFirst { it.isNotBlank() }
        if (index < 0) return content
        val first = titleKey(lines[index])
        if (first == wanted) {
            return lines.drop(index + 1)
                .joinToString("\n")
                .trim()
                .ifEmpty { content }
        }
        if (isChapterNumber(lines[index])) {
            val next = (index + 1 until lines.size).firstOrNull {
                lines[it].isNotBlank()
            }
            if (next != null &&
                titleKey(lines[index] + lines[next]) == wanted
            ) {
                return lines.drop(next + 1)
                    .joinToString("\n")
                    .trim()
                    .ifEmpty { content }
            }
        }
        return content
    }

    /** 标题标签是结构化的章节头，允许目录标题多带书名、求票等后缀。 */
    private fun matchesHeading(candidate: String, wanted: String): Boolean {
        if (candidate.isEmpty() || wanted.isEmpty()) return false
        if (candidate == wanted) return true
        if (wanted.startsWith(candidate)) return candidate.length >= 2
        return candidate.startsWith(wanted) && candidate.length - wanted.length <= 8
    }

    private fun isHeading(element: Element): Boolean =
        element.tagName().lowercase(Locale.ROOT) in HeadingTags

    private fun isBlockElement(tagName: String): Boolean =
        tagName.lowercase(Locale.ROOT) in BlockTags

    private fun isChapterNumber(value: String): Boolean =
        ChapterNumberRegex.matches(value.trim())

    private fun titleKey(value: String): String =
        value.replace(TitleWhitespace, "").lowercase(Locale.ROOT)

    fun getObjects(rule: String?, context: RuleContext): List<Any?> {
        if (rule.isNullOrBlank()) return emptyList()
        return flatten(evaluate(rule, context, elements = true))
    }

    fun stringValue(value: Any?): String = when (value) {
        null -> ""
        is Element -> value.text()
        is Document -> value.text()
        is String -> value
        is Number, is Boolean -> value.toString()
        is Map<*, *> -> value["text"]?.toString() ?: ""
        is Iterable<*> -> value.joinToString(" ") { stringValue(it) }
        else -> value.toString()
    }

    private fun evaluate(rule: String, context: RuleContext, elements: Boolean = false): List<Any?> {
        val trimmedRule = rule.trimStart()
        val isScript = trimmedRule.startsWith("@js:") ||
            trimmedRule.startsWith("@webjs:", ignoreCase = true) ||
            trimmedRule.startsWith("<js>", ignoreCase = true)
        var expanded = expand(
            rule,
            key = context.key,
            page = context.page,
            baseUrl = context.baseUrl,
            content = context.content,
            book = context.book,
            chapter = context.chapter,
        )
        // Legado 的 @put/@get 在 JS 规则里同样会先做文本替换，不能因为
        // 规则以 @js: 开头就跳过。
        expanded = applyPutRules(expanded, context)
        // @get 独占整条规则（## 之前没有其它提取规则）时，Legado 把存储值
        // 当普通文本返回，而不是再按 CSS/JSONPath 解析一次。
        val literalGet = !isScript && treatsGetAsLiteral(expanded)
        expanded = applyGetRules(expanded, context)
        if (literalGet) {
            return listOf(applyReplacementRule(expanded))
        }
        if (!isScript) {
            // 链式 JS（`规则@js:...`）里的 || / && 属于脚本本身，不能当规则回退符拆分。
            if (splitChainedJs(expanded) == null) {
                val fallback = splitTopLevel(expanded, "||")
                if (fallback.size > 1) {
                    for (part in fallback) {
                        val result = evaluatePart(part, context, elements)
                        if (result.any { stringValue(it).isNotBlank() }) return result
                    }
                    return emptyList()
                }
                val sequence = splitTopLevel(expanded, "&&")
                if (sequence.size > 1) {
                    return sequence.flatMap { evaluatePart(it, context, elements) }
                }
                if (!expanded.trimStart().startsWith("@regex:", ignoreCase = true)) {
                    val alternating = splitTopLevel(expanded, "%%")
                    if (alternating.size > 1) {
                        val lists = alternating.map { evaluatePart(it, context, elements) }
                            .filter { elements || it.isNotEmpty() }
                        return buildList {
                            for (row in 0 until (lists.firstOrNull()?.size ?: 0)) {
                                for (list in lists) if (row < list.size) add(list[row])
                            }
                        }
                    }
                }
            }
        }
        return evaluatePart(expanded, context, elements)
    }

    /**
     * JS 规则经常返回数组（正文分段、多下一页地址）。Rhino 的数组不是
     * kotlin List，如果不展开会被整体当成一个字符串，导致只拿到第一页
     * 或只拿到 "[object Object]"。
     */
    private fun flatten(values: List<Any?>): List<Any?> = values.flatMap { value ->
        when (value) {
            // Jsoup 的 Element/Node 实现了 Iterable（遍历子孙节点），
            // 必须先按单个节点返回，否则只命中一个容器时会被拆成子元素。
            is Element -> listOf(value)
            is List<*> -> value
            // 用 for 循环而非嵌套 lambda：lambda 参数在再嵌一层 lambda 时
            // 会丢失 NativeArray 的智能转换，导致 value.get(index, value)
            // 第二参退化成 Any? 而无法匹配 get(Int, Scriptable)。
            is NativeArray -> {
                val items = ArrayList<Any?>()
                for (index in 0 until value.length.toInt()) {
                    val item = value.get(index, value)
                    if (item != Scriptable.NOT_FOUND) items.add(item)
                }
                items
            }
            is Array<*> -> value.toList()
            is Iterable<*> -> value.toList()
            else -> listOf(value)
        }
    }

    private fun evaluatePart(rule: String, context: RuleContext, elements: Boolean = false): List<Any?> {
        val trimmed = rule.trim()
        if (trimmed.isEmpty()) return emptyList()
        // Legado 允许在任意规则后追加 @js: / <js> 对结果二次处理，
        // 例如 `.chapter-text@html@js:...` 用来还原被拆字保护的正文。
        splitChainedJs(trimmed)?.let { chained ->
            val baseValues = if (chained.base.isEmpty()) emptyList() else evaluatePart(chained.base, context)
            val previous = if (chained.base.isEmpty()) {
                context.content
            } else {
                when (baseValues.size) {
                    0 -> null
                    1 -> baseValues[0]
                    else -> baseValues
                }
            }
            // 脚本失败时保留原始提取结果，至少让本章能显示。
            val evaluated = runCatching {
                if (chained.web) {
                    // Legado 的 @webjs: 把整页内容交给 WebView，result 是前一段结果。
                    js.evalWebJs(chained.script, env(context), previous)
                } else {
                    js.eval(chained.script, env(context.copy(content = previous)))
                }
            }.getOrNull()
            if (evaluated != null) return listOf(evaluated)
            return baseValues
        }
        val replacement = splitTopLevel(trimmed, "##")
        if (replacement.size >= 2) {
            // 正文 replaceRegex 常写成以 ## 开头的纯替换规则，此时输入是当前正文。
            val values = if (replacement[0].isBlank()) {
                listOf(stringValue(context.content))
            } else {
                evaluatePart(replacement[0], context).map(::stringValue)
            }
            val pattern = replacement[1]
            if (pattern.isEmpty()) return values
            return values.map { applyReplacement(it, pattern, replacement.getOrElse(2) { "" }, replacement.size >= 4) }
        }
        return when {
            trimmed.startsWith("@js:", ignoreCase = true) ->
                listOf(js.eval(trimmed.substring(4), env(context)))
            trimmed.startsWith("@webjs:", ignoreCase = true) ->
                listOf(js.evalWebJs(trimmed.substring(7), env(context), context.content))
            trimmed.startsWith("<js>", ignoreCase = true) -> {
                val end = trimmed.lastIndexOf("</js>")
                val script = if (end > 4) trimmed.substring(4, end) else trimmed.substring(4)
                listOf(js.eval(script, env(context)))
            }
            trimmed.startsWith("@css:", ignoreCase = true) ->
                css(trimmed.substring(5), context, elementIndices = false, elements = elements)
            trimmed.startsWith("@@") ->
                evaluatePart(trimmed.substring(2), context, elements)
            trimmed.startsWith("@json:", ignoreCase = true) ->
                json(trimmed.substring(6), context)
            trimmed.startsWith("@xpath:", ignoreCase = true) ->
                xpathChain(trimmed.substring(7), context)
            trimmed.startsWith("@regex:", ignoreCase = true) ->
                regex(trimmed.substring(7), context)
            // Legado 把任何以 `/` 开头的规则都按 XPath 处理（含绝对路径）。
            trimmed.startsWith("/") ->
                xpathChain(trimmed, context)
            trimmed.startsWith("$.") || trimmed.startsWith("$[") ->
                json(trimmed, context)
            // Legado 在 setContent 时按内容判断 isJSON：JSON 字符串或
            // Map/List 上的普通字段规则（如 `data.name`）走 JsonPath，
            // 不是按 HTML 选择器解析。这里保持同样判定。
            context.content is Map<*, *> || context.content is List<*> ->
                json(trimmed, context)
            isJsonText(context.content) ->
                json(trimmed, context)
            else ->
                css(trimmed, context, elements = elements)
        }
    }

    private fun isJsonText(content: Any?): Boolean {
        val text = (content as? String)?.trimStart('\uFEFF', ' ', '\t', '\r', '\n') ?: return false
        return text.startsWith("{") || text.startsWith("[")
    }

    /**
     * Legado 用 `<?xml` 判定 XML：走 xmlParser 才能保住 `<item><title>` 这类
     * 同名标签，否则 HTML 解析器会把 title 提升到 head。表格片段同样需要补外层。
     */
    private fun parseMarkup(text: String, baseUrl: String): Document {
        var html = text
        if (html.endsWith("</td>")) html = "<tr>$html</tr>"
        if (html.endsWith("</tr>") || html.endsWith("</tbody>")) html = "<table>$html</table>"
        return if (html.trimStart('\uFEFF', ' ', '\t', '\r', '\n')
                .startsWith("<?xml", ignoreCase = true)
        ) {
            Jsoup.parse(html, baseUrl, Parser.xmlParser())
        } else {
            Jsoup.parse(html, baseUrl)
        }
    }

    /**
     * Legado 的 `@put:{...}` 把当前规则组解析出的值写入书源变量，后面的
     * `@get:{key}` 才能复用。它不属于 CSS/JSONPath，必须在拆分规则前移除。
     */
    private fun applyPutRules(rule: String, context: RuleContext): String {
        if (!PutRuleRegex.containsMatchIn(rule)) return rule
        for (match in PutRuleRegex.findAll(rule)) {
            val body = match.value.substringAfter(':').trim()
            val values = parsePutValues(body, context)
            for ((key, value) in values) {
                val target = variables ?: continue
                // Legado 在 @put 出现的位置立即求值，后续 @get 只读取结果；
                // 延迟到 @get 再求值会重复执行随机数/时间签名等 JS 规则。
                target.writeRule(source.key, context.book, context.chapter, key, getString(value, context))
            }
        }
        return PutRuleRegex.replace(rule, "")
    }

    private fun parsePutValues(body: String, context: RuleContext): Map<String, String> {
        if (!body.startsWith("{")) return emptyMap()
        val json = runCatching { org.json.JSONObject(body) }.getOrNull()
        if (json != null) {
            return buildMap {
                for (key in json.keys()) {
                    val value = json.opt(key)
                    if (value != null && value != org.json.JSONObject.NULL) {
                        put(key, value.toString())
                    }
                }
            }
        }
        // 大量书源写成 {@put:{book:id}} 或单引号键；Rhino 会把 id 当变量，
        // 这里按 Legado 的宽松 JSON 语义直接拆键值，避免整组变量丢失。
        val content = body.removePrefix("{").removeSuffix("}").trim()
        if (content.isEmpty()) return emptyMap()
        return buildMap {
            for (entry in splitTopLevel(content, ",")) {
                val colon = topLevelIndex(entry, ':')
                if (colon <= 0) continue
                val name = unquotePutText(entry.substring(0, colon)).trim()
                if (name.isEmpty()) continue
                put(name, unquotePutText(entry.substring(colon + 1)).trim())
            }
        }
    }

    private fun unquotePutText(value: String): String {
        val text = value.trim()
        if (text.length < 2) return text
        val quote = text.first()
        if ((quote != '"' && quote != '\'') || text.last() != quote) return text
        val body = text.substring(1, text.length - 1)
        val out = StringBuilder(body.length)
        var index = 0
        while (index < body.length) {
            val char = body[index]
            if (char != '\\' || index == body.lastIndex) {
                out.append(char)
                index++
                continue
            }
            when (val next = body[index + 1]) {
                'n' -> out.append('\n')
                'r' -> out.append('\r')
                't' -> out.append('\t')
                'b' -> out.append('\b')
                'f' -> out.append('\u000C')
                'u' -> {
                    val hex = body.substring(index + 2, minOf(index + 6, body.length))
                    val code = hex.toIntOrNull(16)
                    if (code != null) {
                        out.append(code.toChar())
                        index += 4
                    } else {
                        out.append(next)
                    }
                }
                else -> out.append(next)
            }
            index += 2
        }
        return out.toString()
    }

    private fun topLevelIndex(value: String, target: Char): Int {
        var round = 0
        var square = 0
        var curly = 0
        var quote: Char? = null
        var escaped = false
        for (index in value.indices) {
            val char = value[index]
            if (escaped) {
                escaped = false
                continue
            }
            if (char == '\\') {
                escaped = true
                continue
            }
            if (quote != null) {
                if (char == quote) quote = null
                continue
            }
            if (char == '"' || char == '\'') {
                quote = char
                continue
            }
            when (char) {
                '(' -> round++
                ')' -> if (round > 0) round--
                '[' -> square++
                ']' -> if (square > 0) square--
                '{' -> curly++
                '}' -> if (curly > 0) curly--
            }
            if (char == target && round == 0 && square == 0 && curly == 0) return index
        }
        return -1
    }

    /**
     * Legado 的 @get 位于 ## 之前且规则不属于 JS/JSON/XPath 时，会把结果
     * 当成普通文本返回。这里保持同样的判定，避免把书名、作者再次当选择器。
     */
    private fun treatsGetAsLiteral(rule: String): Boolean {
        val trimmed = rule.trimStart()
        if (trimmed.startsWith("@js:", ignoreCase = true) ||
            trimmed.startsWith("<js>", ignoreCase = true) ||
            trimmed.startsWith("@json:", ignoreCase = true) ||
            trimmed.startsWith("@xpath:", ignoreCase = true) ||
            trimmed.startsWith("@css:", ignoreCase = true) ||
            trimmed.startsWith("@regex:", ignoreCase = true) ||
            trimmed.startsWith("/") ||
            trimmed.startsWith("$.") ||
            trimmed.startsWith("$[")
        ) return false
        val match = GetRuleRegex.find(rule) ?: return false
        return !rule.substring(0, match.range.first).contains("##")
    }

    private fun applyReplacementRule(value: String): String {
        val replacement = splitTopLevel(value, "##")
        if (replacement.size < 2) return value
        val pattern = replacement[1]
        if (pattern.isEmpty()) return replacement[0]
        return applyReplacement(
            replacement[0],
            pattern,
            replacement.getOrElse(2) { "" },
            replacement.size >= 4,
        )
    }

    private fun applyReplacement(value: String, pattern: String, target: String, firstOnly: Boolean): String {
        if (!firstOnly) {
            val expression = runCatching { Regex(pattern) }.getOrNull()
                ?: return value.replace(pattern, target)
            // `##match##replace##` 使用 Java 的替换语义：$1/$2 是正则分组，
            // 书源的封面、章节地址大量依赖这种写法。
            return runCatching { expression.replace(value, target) }
                .getOrElse { value.replace(pattern, target) }
        }
        // `##match##replace###` 只取第一个匹配，和 Legado 一样返回被替换的匹配片段。
        val expression = runCatching { Regex(pattern) }.getOrNull() ?: return target
        val found = runCatching { expression.find(value) }
        if (found.isFailure) return target
        val match = found.getOrNull() ?: return ""
        return runCatching { match.value.replaceFirst(expression, target) }.getOrDefault(target)
    }

    private fun applyGetRules(rule: String, context: RuleContext): String {
        if (!GetRuleRegex.containsMatchIn(rule)) return rule
        return GetRuleRegex.replace(rule) { match ->
            val key = match.groupValues[1].trim()
            variables?.readRule(source.key, context.book, context.chapter, key).orEmpty()
        }
    }

    /**
     * 拆分规则末尾的 JS 处理段。`@js:` 之后的全部内容都是脚本；
     * `<js>...</js>` 作为后缀时同样处理。脚本在规则最前面时由调用方直接执行。
     */
    private data class ChainedScript(val base: String, val script: String, val web: Boolean)

    private fun splitChainedJs(rule: String): ChainedScript? {
        // 整条规则就是脚本时交给常规 @js:/@webjs:/<js> 分支，
        // 避免把脚本内的 "@js:" 当分隔符。
        if (rule.startsWith("@js:", ignoreCase = true) ||
            rule.startsWith("@webjs:", ignoreCase = true) ||
            rule.startsWith("<js>", ignoreCase = true)
        ) {
            return null
        }
        JsTagRegex.find(rule)?.let { match ->
            if (match.range.first > 0) {
                return ChainedScript(
                    rule.substring(0, match.range.first).trim(),
                    match.groupValues[1],
                    web = false,
                )
            }
        }
        val webJs = rule.indexOf("@webjs:", startIndex = 1, ignoreCase = true)
        val at = rule.indexOf("@js:", startIndex = 1, ignoreCase = true)
        if (webJs > 0 && (at < 0 || webJs < at)) {
            return ChainedScript(rule.substring(0, webJs).trim(), rule.substring(webJs + 7), web = true)
        }
        if (at > 0) {
            return ChainedScript(rule.substring(0, at).trim(), rule.substring(at + 4), web = false)
        }
        return null
    }

    /** XPath 规则后接 @text / @html / @href 等时，按 Legado 逐段套用。 */
    private fun xpathChain(rule: String, context: RuleContext): List<Any?> {
        val segments = splitXpathChain(rule.trim())
        if (segments.size <= 1) return xpath(rule, context)
        return applyXpathChain(xpath(segments.first(), context), segments)
    }

    /**
     * 只解析 XPath 末尾真正的链式段。`//a/@href` 里的 `@` 是属性轴，
     * XPath 谓词 `[@id=...]` 里的 `@` 也不能当分隔符。
     */
    private fun splitXpathChain(rule: String): List<String> {
        val segments = mutableListOf<String>()
        var rest = rule
        while (true) {
            val at = lastChainSeparator(rest)
            if (at <= 0) break
            val segment = rest.substring(at + 1).trim()
            if (!isXpathChainSegment(segment)) break
            segments.add(0, segment)
            rest = rest.substring(0, at).trim()
        }
        segments.add(0, rest)
        return segments
    }

    /** 返回不在引号/方括号/圆括号里的最后一个 `@` 位置；属性轴 `@` 跳过。 */
    private fun lastChainSeparator(value: String): Int {
        var quote: Char? = null
        var escaped = false
        var square = 0
        var round = 0
        var result = -1
        for (index in value.indices) {
            val char = value[index]
            if (escaped) {
                escaped = false
                continue
            }
            if (char == '\\') {
                escaped = true
                continue
            }
            if (quote != null) {
                if (char == quote) quote = null
                continue
            }
            when (char) {
                '"', '\'' -> quote = char
                '[' -> square++
                ']' -> if (square > 0) square--
                '(' -> round++
                ')' -> if (round > 0) round--
                '@' -> if (square == 0 && round == 0) {
                    val previous = value.getOrNull(index - 1)
                    if (previous != '/' && previous != '@') result = index
                }
            }
        }
        return result
    }

    private fun isXpathChainSegment(segment: String): Boolean {
        if (segment.isEmpty()) return false
        val (selector, range) = splitIndex(segment)
        if (range != null && selector.isEmpty()) return true
        val lower = selector.lowercase(Locale.ROOT)
        if (lower in setOf("text", "owntext", "textnodes", "html", "outerhtml", "all")) {
            return true
        }
        if (lower.startsWith("abs:")) return lower.length > 4
        return ATTRIBUTE_NAME.matches(selector)
    }

    private fun applyXpathChain(values: List<Any?>, parts: List<String>): List<Any?> {
        var current = values
        for (index in 1 until parts.size) {
            val segment = parts[index].trim()
            if (segment.isEmpty()) continue
            val (selector, range) = splitIndex(segment)
            if (range != null) current = applyIndex(current, range)
            current = when (selector.lowercase(Locale.ROOT)) {
                "text" -> current.map(::stringValue)
                "owntext" -> current.mapNotNull { (it as? Element)?.ownText() }
                "textnodes" -> current.flatMap { item ->
                    (item as? Element)?.textNodes()?.map { it.text() } ?: emptyList()
                }
                "html" -> current.mapNotNull { (it as? Element)?.html() }
                "outerhtml", "all" -> current.mapNotNull {
                    (it as? Element)?.outerHtml()
                }
                else -> if (isAttribute(selector) || ATTRIBUTE_NAME.matches(selector)) {
                    current.mapNotNull { attributeValue(it, selector) }
                } else {
                    emptyList()
                }
            }
        }
        return current
    }

    private fun env(context: RuleContext): JsEnv = JsEnv(
        analyzer = this,
        source = source,
        content = context.content,
        baseUrl = context.baseUrl,
        key = context.key,
        page = context.page,
        book = context.book,
        chapter = context.chapter,
        redirectUrl = context.redirectUrl,
        fromBookInfo = context.fromBookInfo,
        variables = variables,
    )

    private fun css(rule: String, context: RuleContext, elementIndices: Boolean = true, elements: Boolean = false): List<Any?> {
        val roots = when (val content = context.content) {
            is Element -> listOf(content)
            is Document -> listOf(content)
            is String -> listOf(parseMarkup(content, context.baseUrl))
            else -> return emptyList()
        }
        var current: List<Any?> = roots
        val segments = splitTopLevel(rule, "@")
        for ((position, rawSegment) in segments.withIndex()) {
            val segment = rawSegment.trim()
            if (segment.isEmpty()) continue
            val indexed = if (elementIndices) elementIndex(segment) else null
            if (indexed != null) {
                val (base, filter) = indexed
                val extractionSuffix = filter.exclude && !segment.endsWith(']') &&
                    (isAttribute(base) || base.lowercase(Locale.ROOT) in ExtractionNames)
                if (!extractionSuffix) {
                    current = current.flatMap { parent -> filter.apply(select(parent, base.ifEmpty { "children" })) }
                    continue
                }
            }
            val (selector, index) = splitIndex(segment)
            val values = if (index == null) current else applyIndex(current, index)
            when (selector.lowercase(Locale.ROOT)) {
                "text" -> return values.map(::stringValue).filter { it.isNotEmpty() }
                "owntext" -> return values.mapNotNull { (it as? Element)?.ownText()?.takeIf(String::isNotEmpty) }
                "textnodes" -> return values.mapNotNull { item ->
                    (item as? Element)?.textNodes()?.map { it.text().trim() }?.filter(String::isNotEmpty)
                        ?.joinToString("\n")?.takeIf(String::isNotEmpty)
                }
                "html" -> return values.mapNotNull { (it as? Element)?.html() }
                "outerhtml", "all" -> return values.mapNotNull {
                    (it as? Element)?.outerHtml()
                }
                else -> if (isAttribute(selector) || (!elements && position == segments.lastIndex &&
                        ATTRIBUTE_NAME.matches(selector) && values.any { it is Element && it.hasAttr(selector) })) {
                    return values.mapNotNull { attributeValue(it, selector) }.filter(String::isNotBlank).distinct()
                } else if (selector.isNotEmpty()) {
                    current = values.flatMap { item -> select(item, selector) }
                } else {
                    current = values
                }
            }
        }
        return current
    }

    private fun select(item: Any?, selector: String): List<Any?> {
        when (selector) {
            "parent" -> return (item as? Element)?.parent()?.let { listOf(it) }
                ?: emptyList()
            "sibling" -> return (item as? Element)?.siblingElements()
                ?.map { it as Any? } ?: emptyList()
            "next" -> return (item as? Element)?.nextElementSibling()
                ?.let { listOf(it) } ?: emptyList()
            "children" -> return (item as? Element)?.children()
                ?.map { it as Any? } ?: emptyList()
        }
        val translated = translateSelector(selector)
        return try {
            when (item) {
                is Element -> item.select(translated)
                is Document -> item.select(translated)
                else -> return emptyList()
            }.map { it as Any? }
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun translateSelector(selector: String): String {
        val value = selector.trim()
        return when {
            value.startsWith("tag.") -> value.substring(4)
            value.startsWith("class.") -> ".${value.substring(6)}"
            value.startsWith("id.") -> "#${value.substring(3)}"
            value.startsWith("text.") -> ":containsOwn(${value.substring(5)})"
            else -> value
        }
    }

    private fun isAttribute(segment: String): Boolean {
        val value = segment.lowercase(Locale.ROOT)
        return value.startsWith("abs:") ||
            value in setOf(
                "href",
                "src",
                "content",
                "title",
                "alt",
                "value",
                "datetime",
                "data-src",
                "data-original",
            ) ||
            value.startsWith("data-") ||
            value.startsWith("aria-")
    }

    private fun attributeValue(item: Any?, segment: String): String? {
        val element = item as? Element ?: return null
        if (segment.startsWith("abs:", ignoreCase = true)) {
            return element.absUrl(segment.substring(4))
        }
        return element.attr(segment)
    }

    private data class IndexSpan(val start: Int?, val end: Int?, val step: Int)

    private data class ElementIndex(val exclude: Boolean, val spans: List<IndexSpan>) {
        fun apply(values: List<Any?>): List<Any?> {
            if (values.isEmpty()) return emptyList()
            val size = values.size
            val positions = linkedSetOf<Int>()
            fun absolute(index: Int) = if (index < 0) size + index else index
            for (span in spans) {
                val start = absolute(span.start ?: 0)
                val end = absolute(span.end ?: values.lastIndex)
                if ((start < 0 && end < 0) || (start >= size && end >= size)) continue
                val first = start.coerceIn(values.indices)
                val last = end.coerceIn(values.indices)
                val stride = when {
                    span.step > 0 -> span.step
                    span.step > -size -> size + span.step
                    else -> 1
                }
                val range = if (first <= last) first..last else first downTo last
                for (position in range step stride) positions.add(position)
            }
            return if (exclude) values.filterIndexed { index, _ -> index !in positions } else positions.map(values::get)
        }
    }

    private fun elementIndex(segment: String): Pair<String, ElementIndex>? {
        val bracket = segment.endsWith(']')
        val split = if (bracket) segment.lastIndexOf('[') else segment.lastIndexOfAny(charArrayOf('.', '!'))
        if (split < 0 || (split > 0 && segment[split - 1] == '\\')) return null
        val suffix = if (bracket) segment.substring(split + 1, segment.lastIndex).trim() else segment.substring(split + 1)
        if (suffix.none { it == ':' || it in '0'..'9' }) return null
        val exclude = if (bracket) suffix.startsWith('!') else segment[split] == '!'
        val expression = if (bracket && exclude) suffix.drop(1) else suffix
        val spans = expression.split(if (bracket) ',' else ':').map { token ->
            val fields = token.trim().split(':')
            if (fields.size > 3) return null
            val numbers = fields.map { field ->
                val number = field.trim()
                if (number.isEmpty()) null else number.toIntOrNull() ?: return null
            }
            if (numbers.size == 1) {
                val single = numbers.first() ?: return null
                IndexSpan(single, single, 1)
            } else IndexSpan(numbers[0], numbers[1], numbers.getOrNull(2) ?: 1)
        }
        return segment.substring(0, split).trimEnd() to ElementIndex(exclude, spans)
    }

    private fun splitIndex(segment: String): Pair<String, String?> {
        val match = IndexRegex.find(segment) ?: return segment to null
        return match.groupValues[1] to match.groupValues[2]
    }

    private fun applyIndex(values: List<Any?>, index: String): List<Any?> {
        val range = index.split(':')
        return if (range.size == 2) {
            val start = range[0].toIntOrNull() ?: return emptyList()
            val end = range[1].toIntOrNull() ?: return emptyList()
            val from = if (start < 0) values.size + start else start
            val to = if (end < 0) values.size + end else end
            if (from < 0 || to < from || from >= values.size) {
                emptyList()
            } else {
                values.subList(from, minOf(to + 1, values.size))
            }
        } else {
            val at = index.toIntOrNull() ?: return emptyList()
            val position = if (at < 0) values.size + at else at
            if (position !in values.indices) emptyList() else listOf(values[position])
        }
    }

    private fun json(rule: String, context: RuleContext): List<Any?> {
        val input = context.content
        val parsed = try {
            when (input) {
                is String -> {
                    val text = input.trim().trimStart('\uFEFF')
                    if (!text.startsWith("{") && !text.startsWith("[")) {
                        return emptyList()
                    }
                    JsonPath.parse(text)
                }
                is Map<*, *>, is List<*> -> JsonPath.parse(input)
                else -> return emptyList()
            }
        } catch (_: Exception) {
            return emptyList()
        }
        val path = if (rule.trim().startsWith("$")) rule.trim() else "$.${rule.trim()}"
        val result = try {
            parsed.read<Any?>(path)
        } catch (_: Exception) {
            return emptyList()
        }
        return if (result is List<*>) result else listOf(result)
    }

    private fun xpath(rule: String, context: RuleContext): List<Any?> {
        val document = when (val content = context.content) {
            is String -> parseMarkup(content, context.baseUrl)
            is Element -> parseMarkup(content.outerHtml(), context.baseUrl)
            is Document -> content
            else -> return emptyList()
        }
        return try {
            // Jsoup 1.15+ 默认给 HTML 元素加 XHTML 命名空间，普通 `//div`
            // 会匹配不到；Legado 的 XPath 语义不带命名空间。
            val dom = W3CDom().namespaceAware(false).fromJsoup(document)
            val expression = XPathFactory.newInstance().newXPath().compile(rule)
            val nodes = expression.evaluate(dom, XPathConstants.NODESET) as NodeList
            (0 until nodes.length).mapNotNull { index ->
                nodeValue(nodes.item(index))
            }
        } catch (_: Exception) {
            try {
                val dom = W3CDom().namespaceAware(false).fromJsoup(document)
                val value = XPathFactory.newInstance().newXPath().evaluate(rule, dom)
                if (value.isBlank()) emptyList() else listOf(value)
            } catch (_: Exception) {
                emptyList()
            }
        }
    }

    private fun nodeValue(node: Node): Any? = when (node.nodeType) {
        Node.ATTRIBUTE_NODE, Node.TEXT_NODE, Node.CDATA_SECTION_NODE ->
            node.nodeValue
        Node.ELEMENT_NODE -> {
            val html = serialize(node)
            Jsoup.parseBodyFragment(html).body().children().firstOrNull() ?: html
        }
        else -> node.textContent
    }

    private fun serialize(node: Node): String {
        val writer = StringWriter()
        val transformer = TransformerFactory.newInstance().newTransformer()
        transformer.setOutputProperty(OutputKeys.OMIT_XML_DECLARATION, "yes")
        transformer.transform(DOMSource(node), StreamResult(writer))
        return writer.toString()
    }

    private fun regex(rule: String, context: RuleContext): List<Any?> {
        val expression = runCatching { Regex(rule) }.getOrNull() ?: return emptyList()
        val input = when (val content = context.content) {
            is String -> content
            else -> stringValue(content)
        }
        return expression.findAll(input).map { it.value }.toList()
    }

    companion object {
        private val ExtractionNames = setOf("text", "owntext", "textnodes", "html", "outerhtml", "all")
        private val IndexRegex = Regex("""^(.*?)!(-?\d+(?::-?\d+)?)$""")
        private val ATTRIBUTE_NAME = Regex("""^[A-Za-z_][A-Za-z0-9_.:-]*$""")
        private val TitleWhitespace = Regex("""[\s\u00A0\u3000\uFEFF]+""")
        private val ChapterNumberRegex = Regex(
            """^(?:第\s*[〇零一二三四五六七八九十百千万两0-9０-９]+\s*[章节節卷部篇回]|(?:chapter|volume|part|book)\s+[0-9ivxlcdm]+)$""",
            RegexOption.IGNORE_CASE,
        )
        private val JsTagRegex = Regex(
            """<js>([\s\S]*?)</js>\s*$""",
            RegexOption.IGNORE_CASE,
        )
        private val PutRuleRegex = Regex(
            """@put:\{[^}]*\}""",
            setOf(RegexOption.IGNORE_CASE, RegexOption.DOT_MATCHES_ALL),
        )
        private val GetRuleRegex = Regex(
            """@get:\{\s*([^}]+?)\s*\}""",
            RegexOption.IGNORE_CASE,
        )
        private val HeadingTags = setOf("h1", "h2", "h3", "h4", "h5", "h6")
        private val BlockTags = setOf(
            "p", "div", "section", "article", "li", "ul", "ol", "dl", "dt", "dd",
            "table", "tr", "td", "th", "blockquote", "pre", "figure", "figcaption",
            "h1", "h2", "h3", "h4", "h5", "h6",
        )

        private fun isRuleExpression(value: String): Boolean =
            value.startsWith("@") ||
                value.startsWith("$.") ||
                value.startsWith("$[") ||
                value.startsWith("//")

        private fun splitTopLevel(value: String, delimiter: String): List<String> {
            val result = mutableListOf<String>()
            var start = 0
            var round = 0
            var square = 0
            var curly = 0
            var quote: Char? = null
            var escaped = false
            var index = 0
            while (index < value.length) {
                val char = value[index]
                if (escaped) {
                    escaped = false
                    index++
                    continue
                }
                if (char == '\\') {
                    escaped = true
                    index++
                    continue
                }
                if (quote != null) {
                    if (char == quote) quote = null
                    index++
                    continue
                }
                if (char == '"' || char == '\'') {
                    quote = char
                    index++
                    continue
                }
                when (char) {
                    '(' -> round++
                    ')' -> if (round > 0) round--
                    '[' -> square++
                    ']' -> if (square > 0) square--
                    '{' -> curly++
                    '}' -> if (curly > 0) curly--
                }
                if (round == 0 &&
                    square == 0 &&
                    curly == 0 &&
                    value.startsWith(delimiter, index)
                ) {
                    result.add(value.substring(start, index))
                    index += delimiter.length
                    start = index
                    continue
                }
                index++
            }
            result.add(value.substring(start))
            return result
        }
    }
}
