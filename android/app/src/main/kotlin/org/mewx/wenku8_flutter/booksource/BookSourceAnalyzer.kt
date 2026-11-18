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
        return evaluatePart(expanded, context)
    }

    private fun flatten(values: List<Any?>): List<Any?> = values.flatMap {
        if (it is List<*>) it else listOf(it)
    }

    private fun evaluatePart(rule: String, context: RuleContext): List<Any?> {
        val trimmed = rule.trim()
        if (trimmed.isEmpty()) return emptyList()
        val replacement = splitTopLevel(trimmed, "##")
        if (replacement.size >= 2) {
            val values = evaluatePart(replacement[0], context).map(::stringValue)
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
                xpath(trimmed.substring(7), context)
            trimmed.startsWith("@regex:", ignoreCase = true) ->
                regex(trimmed.substring(7), context)
            trimmed.startsWith("//") ->
                xpath(trimmed, context)
            trimmed.startsWith("$.") || trimmed.startsWith("$[") ->
                json(trimmed, context)
            context.content is Map<*, *> ->
                jsonField(trimmed, context.content)
            else ->
                css(trimmed, context)
        }
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
