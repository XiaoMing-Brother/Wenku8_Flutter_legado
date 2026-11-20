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
import org.mozilla.javascript.NativeArray
import org.mozilla.javascript.Scriptable
import org.w3c.dom.Node
import org.w3c.dom.NodeList

internal class BookSourceAnalyzer(
    private val source: BookSource,
    private val http: BookSourceHttp,
    private val js: BookSourceJs,
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
        return TemplateRegex.replace(template) { match ->
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
                        JsEnv(source, this, content, baseUrl, key, page, book, chapter),
                    )?.toString() ?: ""
                }
            }
        }
    }

    fun getString(rule: String?, context: RuleContext): String =
        getStrings(rule, context).firstOrNull { it.isNotBlank() } ?: ""

    fun getStrings(rule: String?, context: RuleContext): List<String> {
        if (rule.isNullOrBlank()) return emptyList()
        return flatten(evaluate(rule, context)).map(::stringValue)
    }

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
        return flatten(evaluate(rule, context))
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

    private fun evaluate(rule: String, context: RuleContext): List<Any?> {
        val trimmedRule = rule.trimStart()
        val isScript = trimmedRule.startsWith("@js:") ||
            trimmedRule.startsWith("<js>", ignoreCase = true)
        val expanded = if (isScript) {
            rule
        } else {
            expand(
                rule,
                key = context.key,
                page = context.page,
                baseUrl = context.baseUrl,
                content = context.content,
                book = context.book,
                chapter = context.chapter,
            )
        }
        if (!isScript) {
            // 链式 JS（`规则@js:...`）里的 || / && 属于脚本本身，不能当规则回退符拆分。
            if (splitChainedJs(expanded) == null) {
                val fallback = splitTopLevel(expanded, "||")
                if (fallback.size > 1) {
                    for (part in fallback) {
                        val result = evaluatePart(part, context)
                        if (result.any { stringValue(it).isNotBlank() }) return result
                    }
                    return emptyList()
                }
                val sequence = splitTopLevel(expanded, "&&")
                if (sequence.size > 1) {
                    return sequence.flatMap { evaluatePart(it, context) }
                }
            }
        }
        return evaluatePart(expanded, context)
    }

    /**
     * JS 规则经常返回数组（正文分段、多下一页地址）。Rhino 的数组不是
     * kotlin List，如果不展开会被整体当成一个字符串，导致只拿到第一页
     * 或只拿到 "[object Object]"。
     */
    private fun flatten(values: List<Any?>): List<Any?> = values.flatMap { value ->
        when (value) {
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

    private fun evaluatePart(rule: String, context: RuleContext): List<Any?> {
        val trimmed = rule.trim()
        if (trimmed.isEmpty()) return emptyList()
        // Legado 允许在任意规则后追加 @js: / <js> 对结果二次处理，
        // 例如 `.chapter-text@html@js:...` 用来还原被拆字保护的正文。
        splitChainedJs(trimmed)?.let { (base, script) ->
            val baseValues = if (base.isEmpty()) emptyList() else evaluatePart(base, context)
            val previous = if (base.isEmpty()) {
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
                js.eval(script, env(context.copy(content = previous)))
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
            val expression = runCatching { Regex(pattern) }.getOrNull() ?: return values
            val target = replacement.getOrElse(2) { "" }
            return values.map { expression.replace(it, target) }
        }
        return when {
            trimmed.startsWith("@js:", ignoreCase = true) ->
                listOf(js.eval(trimmed.substring(4), env(context)))
            trimmed.startsWith("<js>", ignoreCase = true) -> {
                val end = trimmed.lastIndexOf("</js>")
                val script = if (end > 4) trimmed.substring(4, end) else trimmed.substring(4)
                listOf(js.eval(script, env(context)))
            }
            trimmed.startsWith("@css:", ignoreCase = true) ->
                css(trimmed.substring(5), context)
            trimmed.startsWith("@json:", ignoreCase = true) ->
                json(trimmed.substring(6), context)
            trimmed.startsWith("@xpath:", ignoreCase = true) ->
                xpathChain(trimmed.substring(7), context)
            trimmed.startsWith("@regex:", ignoreCase = true) ->
                regex(trimmed.substring(7), context)
            trimmed.startsWith("//") ->
                xpathChain(trimmed, context)
            trimmed.startsWith("$.") || trimmed.startsWith("$[") ->
                json(trimmed, context)
            context.content is Map<*, *> ->
                jsonField(trimmed, context.content)
            else ->
                css(trimmed, context)
        }
    }

    /**
     * 拆分规则末尾的 JS 处理段。`@js:` 之后的全部内容都是脚本；
     * `<js>...</js>` 作为后缀时同样处理。脚本在规则最前面时由调用方直接执行。
     */
    private fun splitChainedJs(rule: String): Pair<String, String>? {
        // 整条规则就是脚本时交给常规 @js:/<js> 分支，避免把脚本内的 "@js:" 当分隔符。
        if (rule.startsWith("@js:", ignoreCase = true) ||
            rule.startsWith("<js>", ignoreCase = true)
        ) {
            return null
        }
        JsTagRegex.find(rule)?.let { match ->
            if (match.range.first > 0) {
                return rule.substring(0, match.range.first).trim() to match.groupValues[1]
            }
        }
        val at = rule.indexOf("@js:", startIndex = 1, ignoreCase = true)
        if (at > 0) {
            return rule.substring(0, at).trim() to rule.substring(at + 4)
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
    )

    private fun css(rule: String, context: RuleContext): List<Any?> {
        val roots = when (val content = context.content) {
            is Element -> listOf(content)
            is Document -> listOf(content)
            is String -> listOf(Jsoup.parse(content, context.baseUrl))
            else -> return emptyList()
        }
        var current: List<Any?> = roots
        for (rawSegment in splitTopLevel(rule, "@")) {
            val segment = rawSegment.trim()
            if (segment.isEmpty()) continue
            val (selector, index) = splitIndex(segment)
            val values = if (index == null) current else applyIndex(current, index)
            when (selector.lowercase(Locale.ROOT)) {
                "text" -> return values.map(::stringValue)
                "owntext" -> return values.mapNotNull { (it as? Element)?.ownText() }
                "textnodes" -> return values.flatMap { item ->
                    (item as? Element)?.textNodes()?.map { it.text() } ?: emptyList()
                }
                "html" -> return values.mapNotNull { (it as? Element)?.html() }
                "outerhtml", "all" -> return values.mapNotNull {
                    (it as? Element)?.outerHtml()
                }
                else -> if (isAttribute(selector)) {
                    return values.mapNotNull { attributeValue(it, selector) }
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

    private fun jsonField(rule: String, content: Any?): List<Any?> {
        var current: Any? = content
        for (part in rule.split('.')) {
            if (part.isEmpty()) continue
            current = when (current) {
                is Map<*, *> -> current[part]
                is List<*> -> current.mapNotNull { item ->
                    (item as? Map<*, *>)?.get(part)
                }
                else -> return emptyList()
            }
        }
        return when (val value = current) {
            null -> emptyList()
            is List<*> -> value
            else -> listOf(value)
        }
    }

    private fun xpath(rule: String, context: RuleContext): List<Any?> {
        val document = when (val content = context.content) {
            is String -> Jsoup.parse(content, context.baseUrl)
            is Element -> Jsoup.parse(content.outerHtml(), context.baseUrl)
            is Document -> content
            else -> return emptyList()
        }
        return try {
            val dom = W3CDom().fromJsoup(document)
            val expression = XPathFactory.newInstance().newXPath().compile(rule)
            val nodes = expression.evaluate(dom, XPathConstants.NODESET) as NodeList
            (0 until nodes.length).mapNotNull { index ->
                nodeValue(nodes.item(index))
            }
        } catch (_: Exception) {
            try {
                val dom = W3CDom().fromJsoup(document)
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
        private val TemplateRegex = Regex("""\{\{(.*?)\}\}""", RegexOption.DOT_MATCHES_ALL)
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
