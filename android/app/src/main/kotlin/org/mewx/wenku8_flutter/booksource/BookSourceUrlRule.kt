package org.mewx.wenku8_flutter.booksource

import org.mozilla.javascript.CompilerEnvirons
import org.mozilla.javascript.Context
import org.mozilla.javascript.EvaluatorException
import org.mozilla.javascript.Parser
import org.mozilla.javascript.ast.Name
import org.mozilla.javascript.ast.ObjectProperty
import org.mozilla.javascript.ast.PropertyGet

internal object BookSourceUrlRule {
    val expression = Regex("""\{\{(.*?)\}\}""", RegexOption.DOT_MATCHES_ALL)
    private val script = Regex("""<js>(.*?)</js>|@js:(.*)""", setOf(RegexOption.IGNORE_CASE, RegexOption.DOT_MATCHES_ALL))
    private val choices = Regex("<(.*?)>")

    fun resolve(rule: String, page: Int, evaluate: (String, String) -> String, expand: (String) -> String): String {
        var result = rule
        var start = 0
        for (match in script.findAll(rule)) {
            val prefix = rule.substring(start, match.range.first).trim()
            if (prefix.isNotEmpty()) result = prefix.replace("@result", result)
            result = evaluate(match.groups[1]?.value ?: match.groupValues[2], result)
            start = match.range.last + 1
        }
        if (start > 0) {
            val suffix = rule.substring(start).trim()
            if (suffix.isNotEmpty()) result = suffix.replace("@result", result)
        }
        return choices.replace(expand(result)) { match ->
            val options = match.groupValues[1].split(',')
            options[page.coerceIn(1, options.size) - 1].trim()
        }
    }

    fun hasNext(rule: String, page: Int, hasItems: Boolean, isLast: Boolean?): Boolean {
        if (!hasItems || isLast == true) return false
        var usesPage = false
        val outsideScripts = script.replace(rule) { match ->
            usesPage = usesPage || referencesPage(match.groups[1]?.value ?: match.groupValues[2])
            ""
        }
        val outsideExpressions = expression.replace(outsideScripts) { match ->
            usesPage = usesPage || referencesPage(match.groupValues[1])
            ""
        }
        return usesPage || choices.findAll(outsideExpressions).any { match ->
            match.groupValues[1].count { it == ',' } >= page.coerceAtLeast(1)
        }
    }

    private fun referencesPage(code: String): Boolean {
        if (!code.contains("page")) return false
        if (code.trim() == "page") return true
        val environment = CompilerEnvirons().apply { languageVersion = Context.VERSION_ES6 }
        val root = try {
            Parser(environment).parse(code, "page-selection", 1)
        } catch (_: EvaluatorException) {
            return false
        }
        var found = false
        root.visit { node ->
            if (!found && node is Name && node.identifier == "page" && node.definingScope == null) {
                val parent = node.parent
                found = !(parent is PropertyGet && parent.property === node || parent is ObjectProperty && parent.left === node)
            }
            !found
        }
        return found
    }
}
