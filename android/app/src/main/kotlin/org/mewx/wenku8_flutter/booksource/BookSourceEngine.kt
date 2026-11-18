package org.mewx.wenku8_flutter.booksource

import java.util.concurrent.ConcurrentHashMap
import org.jsoup.Jsoup
import org.jsoup.nodes.Element
import org.json.JSONArray
import org.json.JSONObject

internal class BookSourceEngine(
    private val variables: BookSourceVariables? = null,
) {
    private val sources = ConcurrentHashMap<String, BookSource>()
    private val infoMaps = ConcurrentHashMap<String, MutableMap<String, String>>()
    private val http = BookSourceHttp(variables)
    private val js = BookSourceJs(http)

    fun upsert(value: Any?) {
        val source = BookSource.from(value)
        sources[source.key] = source
    }

    fun remove(key: String) {
        sources.remove(key)
        infoMaps.remove(key)
        variables?.remove(loginInfoKey(key))
        variables?.remove(loginHeaderKey(key))
        http.removeCookie(key)
    }

    fun loginInfo(sourceKey: String): Map<String, Any?> = loginState(sourceKey)

    fun login(
        sourceKey: String,
        values: Map<String, String>?,
    ): Map<String, Any?> {
        val source = requireSource(sourceKey)
        val info = linkedMapOf<String, String>()
        values?.forEach { (key, value) -> info[key] = value }
        if (info.isEmpty()) {
            variables?.remove(loginInfoKey(sourceKey))
        } else {
            variables?.put(loginInfoKey(sourceKey), toJsonObject(info).toString())
        }
        val script = extractJs(source.loginUrl)
        if (script.isNotBlank()) {
            val result = js.eval(
                script,
                loginEnv(source, info),
                LoginCallScript,
            )
            val header = loginHeaderFromResult(result)
            if (header != null) {
                variables?.put(loginHeaderKey(sourceKey), header)
                http.applyLoginHeaderCookie(sourceKey, header)
            }
        }
        return loginState(sourceKey)
    }

    fun loginAction(
        sourceKey: String,
        action: String,
        values: Map<String, String>?,
    ) {
        val source = requireSource(sourceKey)
        if (action.isBlank()) return
        val info = linkedMapOf<String, String>()
        values?.forEach { (key, value) -> info[key] = value }
        val script = buildString {
            val loginJs = extractJs(source.loginUrl)
            if (loginJs.isNotBlank()) {
                append(loginJs)
                append('\n')
            }
            append(action)
        }
        js.eval(script, loginEnv(source, info))
    }

    fun logout(sourceKey: String): Map<String, Any?> {
        variables?.remove(loginInfoKey(sourceKey))
        variables?.remove(loginHeaderKey(sourceKey))
        http.removeCookie(sourceKey)
        return loginState(sourceKey)
    }

    fun webLoginConfig(sourceKey: String): Map<String, Any?> {
        val source = requireSource(sourceKey)
        val raw = source.loginUrl?.trim().orEmpty()
        if (raw.isEmpty()) throw IllegalArgumentException("书源没有配置登录地址")
        val url = resolveWebLoginUrl(source, raw)
        val headers = linkedMapOf<String, String>()
        headers.putAll(source.headers)
        headers.putAll(loginHeaders(sourceKey))
        val headerCookie = headers.entries
            .firstOrNull { it.key.equals("Cookie", ignoreCase = true) }
            ?.value
            .orEmpty()
        val storedCookie = http.cookie(sourceKey, url)
        val cookie = listOf(headerCookie, storedCookie)
            .filter { it.isNotBlank() }
            .distinct()
            .joinToString("; ")
        if (cookie.isNotBlank() &&
            headers.keys.none { it.equals("Cookie", ignoreCase = true) }
        ) {
            headers["Cookie"] = cookie
        }
        return mapOf(
            "url" to url,
            "title" to source.name,
            "headers" to headers,
            "cookie" to cookie,
            "userAgent" to headers.entries
                .firstOrNull { it.key.equals("User-Agent", ignoreCase = true) }
                ?.value
                .orEmpty(),
        )
    }

    fun importWebLoginCookie(
        sourceKey: String,
        cookie: String,
    ): Map<String, Any?> {
        http.setCookie(sourceKey, "", cookie)
        return loginState(sourceKey)
    }

    fun checkLogin(
        sourceKey: String,
        url: String? = null,
    ): Map<String, Any?> {
        val source = requireSource(sourceKey)
        val target = url?.trim().takeUnless { it.isNullOrEmpty() } ?: source.key
        val response = fetchResponse(source, http.requestSpec(source.key, target))
        val checked = applyLoginCheck(source, response, key = "", page = 1)
        return loginState(sourceKey) + mapOf(
            "checked" to (source.loginCheckJs?.isNotBlank() == true),
            "checkedUrl" to checked.url,
        )
    }

    fun available(): Boolean = true

    fun cancelSearches() {
        http.cancelSearches()
    }

    fun image(sourceKey: String, url: String): ByteArray {
        val source = requireSource(sourceKey)
        return http.fetchBytes(source, http.requestSpec(source.key, url))
    }

    fun search(
        sourceKey: String,
        keyword: String,
        page: Int,
    ): Map<String, Any?> = http.asSearch {
        val source = requireSource(sourceKey)
        requireTextSource(source)
        val template = source.searchUrl
        if (template.isBlank()) throw IllegalArgumentException("书源没有配置搜索地址")
        val analyzer = analyzer(source)
        val expanded = resolveAddress(
            source,
            analyzer,
            template,
            keyword,
            page,
            null,
        )
        val candidates = expanded.lineSequence()
            .map { it.trim() }
            .filter { it.isNotEmpty() }
            .toList()
        if (candidates.isEmpty()) throw IllegalArgumentException("书源搜索地址为空")
        var response: BookSourceResponse? = null
        var lastError: Throwable? = null
        for (candidate in candidates) {
            try {
                response = fetchResponse(source, http.requestSpec(source.key, candidate))
                break
            } catch (error: Throwable) {
                lastError = error
            }
        }
        val fetched = response ?: throw lastError ?: IllegalStateException("书源搜索失败")
        val loaded = applyLoginCheck(source, fetched, keyword, page)
        val context = RuleContext(
            content = loaded.text,
            baseUrl = loaded.url,
            key = keyword,
            page = page,
        )
        val rows = analyzer.getObjects(source.search.bookList, context)
        val items = rows.mapNotNull { row ->
            searchItem(source, analyzer, row, context)
        }
        val supportsPage = template.contains("{{page}}")
        mapOf(
            "items" to items,
            "hasMore" to (supportsPage && items.size >= 10),
        )
    }

    fun exploreKinds(
        sourceKey: String,
        values: Map<String, String>? = null,
    ): List<Map<String, Any?>> {
        val source = requireSource(sourceKey)
        val raw = source.exploreUrl
        if (raw.isBlank()) return emptyList()
        val analyzer = analyzer(source)
        val infoMap = infoMap(sourceKey, values)
        val evaluated = when {
            raw.startsWith("@js:", ignoreCase = true) ->
                js.eval(
                    raw.substring(4),
                    JsEnv(
                        source = source,
                        analyzer = analyzer,
                        content = null,
                        baseUrl = source.key,
                        key = "",
                        page = 1,
                        infoMap = infoMap,
                        variables = variables,
                    ),
                )
            raw.startsWith("<js>", ignoreCase = true) -> {
                val end = raw.lastIndexOf("</js>")
                val script = if (end > 4) raw.substring(4, end) else raw.substring(4)
                js.eval(
                    script,
                    JsEnv(
                        source = source,
                        analyzer = analyzer,
                        content = null,
                        baseUrl = source.key,
                        key = "",
                        page = 1,
                        infoMap = infoMap,
                        variables = variables,
                    ),
                )
            }
            else -> raw
        }
        if (evaluated is List<*>) {
            return evaluated.mapNotNull(::exploreKind)
        }
        val text = evaluated?.toString()?.trim()?.removePrefix("\uFEFF")?.trim().orEmpty()
        if (text.isBlank() || text.startsWith("<useweb>", ignoreCase = true)) {
            return emptyList()
        }
        if (text.startsWith("[")) {
            val array = parseJsonArray(text) ?: return emptyList()
            return buildList {
                for (index in 0 until array.length()) {
                    val map = jsonToKotlin(array.opt(index)) as? Map<*, *>
                    if (map != null) exploreKind(map)?.let(::add)
                }
            }
        }
        return text.split(Regex("(&&|\\r?\\n)+"))
            .map { it.trim() }
            .filter { it.isNotEmpty() }
            .mapNotNull { line ->
                val columns = line.split("::")
                val title = columns.firstOrNull()?.trim().orEmpty()
                if (title.isEmpty()) {
                    null
                } else {
                    mapOf(
                        "title" to title,
                        "url" to columns.getOrNull(1)?.trim().orEmpty(),
                        "type" to "",
                        "action" to "",
                    )
                }
            }
    }

    fun explore(
        sourceKey: String,
        url: String,
        page: Int,
        keyword: String,
        values: Map<String, String>? = null,
    ): Map<String, Any?> = http.asSearch {
        val source = requireSource(sourceKey)
        requireTextSource(source)
        val template = url.trim().ifBlank { source.exploreUrl }
        if (template.isBlank()) throw IllegalArgumentException("书源没有配置发现地址")
        val analyzer = analyzer(source)
        val infoMap = infoMap(sourceKey, values)
        val expanded = resolveAddress(
            source,
            analyzer,
            template,
            keyword,
            page,
            infoMap,
        )
        val candidates = expanded.lineSequence()
            .map { it.trim() }
            .filter { it.isNotEmpty() }
            .toList()
        if (candidates.isEmpty()) throw IllegalArgumentException("书源发现地址为空")
        var response: BookSourceResponse? = null
        var lastError: Throwable? = null
        for (candidate in candidates) {
            try {
                response = fetchResponse(source, http.requestSpec(source.key, candidate))
                break
            } catch (error: Throwable) {
                lastError = error
            }
        }
        val fetched = response ?: throw lastError ?: IllegalStateException("书源发现请求失败")
        val loaded = applyLoginCheck(source, fetched, keyword, page)
        val context = RuleContext(
            content = loaded.text,
            baseUrl = loaded.url,
            key = keyword,
            page = page,
        )
        val rule = if (source.explore.bookList.isNullOrBlank()) {
            source.search
        } else {
            source.explore
        }
        if (rule.bookList.isNullOrBlank()) {
            throw IllegalArgumentException("书源没有配置发现或搜索列表规则")
        }
        val rows = analyzer.getObjects(rule.bookList, context)
        val items = rows.mapNotNull { row ->
            searchItem(source, analyzer, row, context, rule)
        }
        val supportsPage = Regex("\\{\\{\\s*page\\s*\\}\\}").containsMatchIn(template)
        mapOf(
            "items" to items,
            "hasMore" to (supportsPage && items.size >= 10),
        )
    }

    fun exploreAction(
        sourceKey: String,
        script: String,
        values: Map<String, String>? = null,
    ): Map<String, Any?> {
        val source = requireSource(sourceKey)
        if (script.isBlank()) return mapOf("values" to infoMap(sourceKey, values).toMap())
        val analyzer = analyzer(source)
        val infoMap = infoMap(sourceKey, values)
        var search: String? = null
        js.eval(
            script,
            JsEnv(
                source = source,
                analyzer = analyzer,
                content = null,
                baseUrl = source.key,
                key = "",
                page = 1,
                infoMap = infoMap,
                variables = variables,
                onSearchBook = { search = it },
            ),
        )
        return mapOf(
            "values" to infoMap.toMap(),
            "search" to search,
        )
    }

    fun detail(sourceKey: String, bookUrl: String): Map<String, Any?> {
        val source = requireSource(sourceKey)
        requireTextSource(source)
        val analyzer = analyzer(source)
        val book = BookData(bookUrl = bookUrl)
        val response = applyLoginCheck(
            source,
            fetchResponse(source, http.requestSpec(source.key, bookUrl)),
            key = "",
            page = 1,
            book = book,
        )
        var content: Any = response.text
        val init = source.bookInfo.init
        if (!init.isNullOrBlank()) {
            val evaluated = analyzer.getObjects(
                init,
                RuleContext(content, response.url, book = book),
            )
            if (evaluated.size == 1) {
                content = evaluated.first() ?: content
            } else if (evaluated.size > 1) {
                content = evaluated
            }
        }
        val context = RuleContext(content, response.url, book = book)
        val info = source.bookInfo
        val pageTitle = runCatching { Jsoup.parse(response.text).title() }.getOrDefault("")
        val name = analyzer.getString(info.name, context)
            .ifBlank { pageTitle }
            .ifBlank { bookUrl }
        val tocUrl = http.resolve(
            response.url,
            analyzer.getString(info.tocUrl, context).ifBlank { bookUrl },
        )
        return mapOf(
            "name" to name,
            "author" to analyzer.getString(info.author, context),
            "coverUrl" to http.resolve(
                response.url,
                analyzer.getString(info.coverUrl, context),
            ),
            "intro" to plainText(analyzer.getString(info.intro, context)),
            "kind" to analyzer.getString(info.kind, context),
            "lastUpdate" to analyzer.getString(info.updateTime, context),
            "updateTime" to analyzer.getString(info.updateTime, context),
            "tocUrl" to tocUrl,
            "totalChapterNum" to 0,
        )
    }

    fun chapters(
        sourceKey: String,
        bookUrl: String,
        tocUrl: String?,
    ): List<Map<String, Any?>> {
        val source = requireSource(sourceKey)
        requireTextSource(source)
        val analyzer = analyzer(source)
        val book = BookData(bookUrl = bookUrl, tocUrl = tocUrl.orEmpty())
        val result = mutableListOf<Map<String, Any?>>()
        val visited = mutableSetOf<String>()
        val requestedToc = tocUrl.orEmpty().trim()
        var nextUrl = if (requestedToc.isEmpty()) {
            bookUrl
        } else {
            http.resolve(source.key, requestedToc)
        }
        while (nextUrl.isNotBlank() && visited.add(nextUrl) && visited.size <= 20) {
            val response = applyLoginCheck(
                source,
                fetchResponse(source, http.requestSpec(source.key, nextUrl)),
                key = "",
                page = 1,
                book = book,
            )
            val context = RuleContext(response.text, response.url, book = book)
            val rows = analyzer.getObjects(source.toc.chapterList, context)
            if (rows.isEmpty() && result.isEmpty()) {
                throw IllegalStateException("目录规则没有返回章节")
            }
            for (row in rows) {
                result.add(chapterRow(source, analyzer, row, response.url, book))
            }
            val nextRule = source.toc.nextTocUrl
            nextUrl = if (nextRule.isNullOrBlank()) {
                ""
            } else {
                http.resolve(
                    response.url,
                    analyzer.getString(nextRule, context),
                )
            }
        }
        return result
    }

    fun content(
        sourceKey: String,
        bookUrl: String,
        chapterUrl: String,
        nextChapterUrl: String?,
    ): String {
        val source = requireSource(sourceKey)
        requireTextSource(source)
        val analyzer = analyzer(source)
        val book = BookData(bookUrl = bookUrl)
        val parts = mutableListOf<String>()
        val visited = mutableSetOf<String>()
        var currentUrl = chapterUrl
        var pageCount = 0
        while (currentUrl.isNotBlank() && visited.add(currentUrl) && pageCount < 20) {
            pageCount++
            val chapter = ChapterData(
                url = currentUrl,
                nextUrl = if (pageCount == 1) nextChapterUrl.orEmpty() else "",
            )
            val response = applyLoginCheck(
                source,
                fetchResponse(source, http.requestSpec(source.key, currentUrl)),
                key = "",
                page = 1,
                book = book,
                chapter = chapter,
            )
            val context = RuleContext(
                content = response.text,
                baseUrl = response.url,
                book = book,
                chapter = chapter,
            )
            val body = analyzer.getString(source.content.content, context)
            if (body.isNotBlank()) parts.add(body)
            val sub = source.content.subContent
            if (!sub.isNullOrBlank()) {
                val extra = analyzer.getString(sub, context)
                if (extra.isNotBlank()) parts.add(extra)
            }
            val nextRule = source.content.nextContentUrl
            currentUrl = if (nextRule.isNullOrBlank()) {
                ""
            } else {
                http.resolve(
                    response.url,
                    analyzer.getString(nextRule, context),
                )
            }
        }
        if (parts.isEmpty()) throw IllegalStateException("正文规则没有返回内容")
        return parts.joinToString("\n\n")
    }

    private fun searchItem(
        source: BookSource,
        analyzer: BookSourceAnalyzer,
        row: Any?,
        parent: RuleContext,
        rule: SearchRule = source.search,
    ): Map<String, Any?>? {
        val context = parent.copy(content = row)
        val bookUrl = http.resolve(
            parent.baseUrl,
            analyzer.getString(rule.bookUrl, context).ifBlank {
                when (row) {
                    is Element -> row.absUrl("href")
                    is Map<*, *> -> row["bookUrl"]?.toString()
                        ?: row["url"]?.toString().orEmpty()
                    else -> ""
                }
            },
        )
        if (!bookUrl.startsWith("http://") && !bookUrl.startsWith("https://")) {
            return null
        }
        val fallbackName = when (row) {
            is Element -> row.text()
            is Map<*, *> -> row["name"]?.toString().orEmpty()
            else -> analyzer.stringValue(row)
        }
        return mapOf(
            "name" to analyzer.getString(rule.name, context).ifBlank { fallbackName },
            "author" to analyzer.getString(rule.author, context),
            "kind" to analyzer.getString(rule.kind, context),
            "intro" to plainText(analyzer.getString(rule.intro, context)),
            "lastChapter" to analyzer.getString(rule.lastChapter, context),
            "updateTime" to analyzer.getString(rule.updateTime, context),
            "bookUrl" to bookUrl,
            "coverUrl" to http.resolve(
                parent.baseUrl,
                analyzer.getString(rule.coverUrl, context),
            ),
        )
    }

    private fun resolveAddress(
        source: BookSource,
        analyzer: BookSourceAnalyzer,
        template: String,
        key: String,
        page: Int,
        infoMap: MutableMap<String, String>?,
    ): String {
        val value = template.trim()
        val resolved = when {
            value.startsWith("@js:", ignoreCase = true) ->
                js.eval(
                    value.substring(4),
                    JsEnv(
                        source = source,
                        analyzer = analyzer,
                        content = null,
                        baseUrl = source.key,
                        key = key,
                        page = page,
                        infoMap = infoMap,
                        variables = variables,
                    ),
                )?.toString().orEmpty()
            value.startsWith("<js>", ignoreCase = true) -> {
                val end = value.lastIndexOf("</js>")
                val script = if (end > 4) value.substring(4, end) else value.substring(4)
                js.eval(
                    script,
                    JsEnv(
                        source = source,
                        analyzer = analyzer,
                        content = null,
                        baseUrl = source.key,
                        key = key,
                        page = page,
                        infoMap = infoMap,
                        variables = variables,
                    ),
                )?.toString().orEmpty()
            }
            else -> value
        }
        return analyzer.expand(
            resolved,
            key = key,
            page = page,
            baseUrl = source.key,
        )
    }

    private fun parseJsonArray(text: String): JSONArray? {
        runCatching { JSONArray(text) }.getOrNull()?.let { return it }
        val lenient = text.replace(Regex(",\\s*([\\]}])"), "\$1")
        return runCatching { JSONArray(lenient) }.getOrNull()
    }

    private fun exploreKind(value: Any?): Map<String, Any?>? {
        if (value !is Map<*, *>) return null
        val title = (value["title"] ?: value["name"])
            ?.toString()
            ?.trim()
            .orEmpty()
        if (title.isEmpty()) return null
        val style = value["style"] as? Map<*, *>
        val chars = (value["chars"] as? List<*>)
            ?.mapNotNull { it?.toString() }
            .orEmpty()
        return mapOf(
            "title" to title,
            "url" to value["url"]?.toString()?.trim().orEmpty(),
            "type" to value["type"]?.toString()?.trim().orEmpty(),
            "action" to value["action"]?.toString()?.trim().orEmpty(),
            "viewName" to unquote(value["viewName"]?.toString().orEmpty()),
            "chars" to chars,
            "default" to value["default"]?.toString().orEmpty(),
            "basisPercent" to (
                (style?.get("layout_flexBasisPercent") as? Number)?.toDouble() ?: -1.0
                ),
            "flexGrow" to (
                (style?.get("layout_flexGrow") as? Number)?.toDouble() ?: 0.0
                ),
            "wrapBefore" to (style?.get("layout_wrapBefore") == true),
        )
    }

    private fun infoMap(
        sourceKey: String,
        values: Map<String, String>?,
    ): MutableMap<String, String> {
        val info = infoMaps.getOrPut(sourceKey) { ConcurrentHashMap() }
        if (values != null) info.putAll(values)
        return info
    }

    private fun loginState(sourceKey: String): Map<String, Any?> {
        val source = requireSource(sourceKey)
        val rows = loginUi(sourceKey)
        val stored = storedLoginInfo(sourceKey)
        return mapOf(
            "values" to if (stored.isEmpty()) defaultLoginInfo(rows) else stored,
            "loginUi" to rows,
            "loginUrl" to source.loginUrl.orEmpty(),
            "loginCheckJs" to source.loginCheckJs.orEmpty(),
            "hasLoginHeader" to loginHeaders(sourceKey).isNotEmpty(),
            "hasCookie" to http.hasCookie(sourceKey),
        )
    }

    private fun loginUi(sourceKey: String): List<Map<String, Any?>> {
        val source = requireSource(sourceKey)
        val raw = source.loginUi?.trim().orEmpty()
        if (raw.isEmpty()) return emptyList()
        val evaluated = when {
            raw.startsWith("@js:", ignoreCase = true) ->
                js.eval(loginUiScript(source, raw.substring(4)), loginEnv(source))
            raw.startsWith("<js>", ignoreCase = true) -> {
                val end = raw.lastIndexOf("</js>")
                val script = if (end > 4) raw.substring(4, end) else raw.substring(4)
                js.eval(loginUiScript(source, script), loginEnv(source))
            }
            else -> raw
        }
        if (evaluated is List<*>) {
            return evaluated.mapNotNull { item ->
                (item as? Map<*, *>)?.let { loginRow(it) }
            }
        }
        val text = evaluated?.toString().orEmpty()
        val array = parseJsonArray(text) ?: return emptyList()
        return buildList {
            for (index in 0 until array.length()) {
                val map = jsonToKotlin(array.opt(index)) as? Map<*, *> ?: continue
                loginRow(map)?.let(::add)
            }
        }
    }

    // Legado 的动态登录表单可以直接复用 loginUrl 中定义的函数。
    private fun loginUiScript(source: BookSource, script: String): String {
        val login = extractJs(source.loginUrl)
        if (login.isBlank() ||
            login.startsWith("http://", ignoreCase = true) ||
            login.startsWith("https://", ignoreCase = true)
        ) {
            return script
        }
        return "$login\n$script"
    }

    private fun loginRow(value: Map<*, *>): Map<String, Any?>? {
        val name = value["name"]?.toString()?.trim().orEmpty()
        if (name.isEmpty()) return null
        val style = value["style"] as? Map<*, *>
        return mapOf(
            "name" to name,
            "title" to loginRowTitle(name, value["viewName"]?.toString().orEmpty()),
            "type" to (value["type"]?.toString()?.trim()?.ifEmpty { "text" } ?: "text"),
            "action" to value["action"]?.toString()?.trim().orEmpty(),
            "chars" to (value["chars"] as? List<*>)
                ?.mapNotNull { it?.toString() }
                .orEmpty(),
            "default" to value["default"]?.toString().orEmpty(),
            "basisPercent" to (
                (style?.get("layout_flexBasisPercent") as? Number)?.toDouble() ?: -1.0
                ),
            "flexGrow" to (
                (style?.get("layout_flexGrow") as? Number)?.toDouble() ?: 0.0
                ),
            "wrapBefore" to (style?.get("layout_wrapBefore") == true),
        )
    }

    private fun loginRowTitle(name: String, rawTitle: String): String {
        val title = rawTitle.trim()
        if (title.isEmpty()) return name
        if (title.startsWith("@js:", ignoreCase = true)) {
            return name
        }
        if (title.length < 2) return title
        val first = title.first()
        val last = title.last()
        return if ((first == '\'' && last == '\'') || (first == '"' && last == '"')) {
            title.substring(1, title.length - 1)
        } else {
            title
        }
    }

    private fun storedLoginInfo(sourceKey: String): Map<String, String> {
        val raw = variables?.get(loginInfoKey(sourceKey)).orEmpty()
        if (raw.isBlank()) return emptyMap()
        val json = runCatching { JSONObject(raw) }.getOrNull() ?: return emptyMap()
        return buildMap {
            for (key in json.keys()) {
                val value = json.opt(key)
                if (value != null && value != JSONObject.NULL) put(key, value.toString())
            }
        }
    }

    private fun defaultLoginInfo(rows: List<Map<String, Any?>>): Map<String, String> = buildMap {
        for (row in rows) {
            if (row["type"] == "button") continue
            val name = row["name"]?.toString().orEmpty()
            if (name.isEmpty()) continue
            val fallback = (row["chars"] as? List<*>)
                ?.firstOrNull()
                ?.toString()
                .orEmpty()
            put(
                name,
                row["default"]?.toString().orEmpty().ifEmpty { fallback },
            )
        }
    }

    private fun loginHeaders(sourceKey: String): Map<String, String> {
        val raw = variables?.get(loginHeaderKey(sourceKey)).orEmpty()
        if (raw.isBlank()) return emptyMap()
        val json = runCatching { JSONObject(raw) }.getOrNull() ?: return emptyMap()
        return buildMap {
            for (key in json.keys()) {
                val value = json.opt(key)
                if (value != null && value != JSONObject.NULL) put(key, value.toString())
            }
        }
    }

    private fun loginHeaderFromResult(value: Any?): String? {
        val json = when (value) {
            is Map<*, *> -> toJsonObject(value)
            is String -> {
                val text = value.trim()
                if (!text.startsWith("{")) return null
                runCatching { JSONObject(text) }.getOrNull() ?: return null
            }
            else -> return null
        }
        return json.takeIf { it.length() > 0 }?.toString()
    }

    private fun resolveWebLoginUrl(source: BookSource, raw: String): String {
        val value = when {
            raw.startsWith("@js:", ignoreCase = true) ->
                js.eval(raw.substring(4), loginEnv(source))?.toString().orEmpty()
            raw.startsWith("<js>", ignoreCase = true) -> {
                val end = raw.lastIndexOf("</js>")
                val script = if (end > 4) raw.substring(4, end) else raw.substring(4)
                js.eval(script, loginEnv(source))?.toString().orEmpty()
            }
            else -> raw
        }.trim()
        if (value.isEmpty()) throw IllegalArgumentException("书源登录地址为空")
        val url = http.resolve(source.key, value)
        if (!url.startsWith("http://", ignoreCase = true) &&
            !url.startsWith("https://", ignoreCase = true)
        ) {
            throw IllegalArgumentException("书源登录地址不是网页链接")
        }
        return url
    }

    private fun applyLoginCheck(
        source: BookSource,
        response: BookSourceResponse,
        key: String,
        page: Int,
        book: BookData? = null,
        chapter: ChapterData? = null,
    ): BookSourceResponse {
        val script = source.loginCheckJs?.trim().orEmpty()
        if (script.isEmpty()) return response
        val checked = js.eval(
            script,
            JsEnv(
                source = source,
                analyzer = analyzer(source),
                content = response.text,
                baseUrl = response.url,
                key = key,
                page = page,
                book = book,
                chapter = chapter,
                variables = variables,
                response = response,
            ),
        )
        return responseFromCheck(checked, response)
    }

    private fun responseFromCheck(
        value: Any?,
        original: BookSourceResponse,
    ): BookSourceResponse = when (value) {
        null -> original
        is BookSourceResponse -> value
        is String -> original.copy(text = value)
        is Map<*, *> -> {
            val headers = (value["headers"] as? Map<*, *>)
                ?.entries
                ?.mapNotNull { (key, item) ->
                    if (key == null || item == null) null
                    else key.toString() to item.toString()
                }
                ?.toMap()
                .orEmpty()
            original.copy(
                url = value["url"]?.toString()?.takeIf { it.isNotBlank() }
                    ?: original.url,
                text = (value["body"] ?: value["text"] ?: value["html"])
                    ?.toString()
                    ?: original.text,
                statusCode = (value["statusCode"] as? Number)?.toInt()
                    ?: original.statusCode,
                headers = headers.ifEmpty { original.headers },
            )
        }
        else -> original.copy(text = value.toString())
    }

    private fun loginEnv(
        source: BookSource,
        info: MutableMap<String, String> = mutableMapOf(),
    ): JsEnv = JsEnv(
        source = source,
        analyzer = analyzer(source),
        content = info,
        baseUrl = source.key,
        key = "",
        page = 1,
        variables = variables,
    )

    private fun extractJs(rule: String?): String {
        val text = rule?.trim().orEmpty()
        if (text.isEmpty()) return ""
        return when {
            text.startsWith("@js:", ignoreCase = true) -> text.substring(4)
            text.startsWith("<js>", ignoreCase = true) -> {
                val end = text.lastIndexOf("</js>")
                if (end > 4) text.substring(4, end) else text.substring(4)
            }
            else -> text
        }
    }

    private fun unquote(value: String): String {
        val text = value.trim()
        if (text.length < 2) return text
        val first = text.first()
        val last = text.last()
        return if ((first == '\'' && last == '\'') || (first == '"' && last == '"')) {
            text.substring(1, text.length - 1)
        } else {
            text
        }
    }

    private fun chapterRow(
        source: BookSource,
        analyzer: BookSourceAnalyzer,
        row: Any?,
        baseUrl: String,
        book: BookData,
    ): Map<String, Any?> {
        val context = RuleContext(row, baseUrl, book = book)
        val rule = source.toc
        val rawUrl = analyzer.getString(rule.chapterUrl, context).ifBlank {
            when (row) {
                is Element -> row.attr("href")
                is Map<*, *> -> row["url"]?.toString().orEmpty()
                else -> ""
            }
        }
        val title = analyzer.getString(rule.chapterName, context).ifBlank {
            when (row) {
                is Element -> row.text()
                is Map<*, *> -> row["title"]?.toString().orEmpty()
                else -> analyzer.stringValue(row)
            }
        }
        val isVolume = analyzer.getString(rule.isVolume, context)
            .lowercase()
            .let { it == "true" || it == "1" || it == "是" || it == "yes" }
        return mapOf(
            "title" to title,
            "url" to if (rawUrl.isBlank()) "" else http.resolve(baseUrl, rawUrl),
            "isVolume" to isVolume,
            "updateTime" to analyzer.getString(rule.updateTime, context),
        )
    }

    private fun analyzer(source: BookSource): BookSourceAnalyzer =
        BookSourceAnalyzer(source, http, js)

    private fun fetchResponse(source: BookSource, spec: RequestSpec): BookSourceResponse =
        http.fetch(
            source,
            spec,
            allowUnsuccessful = source.loginCheckJs?.isNotBlank() == true,
        )

    private fun requireSource(key: String): BookSource =
        sources[key] ?: throw IllegalArgumentException("书源不存在，请重新导入")

    private fun requireTextSource(source: BookSource) {
        if (!source.supported) {
            throw IllegalArgumentException("当前只支持文字和文件类型书源")
        }
    }

    private fun plainText(value: String): String {
        if (value.isBlank() || !value.contains('<')) return value.trim()
        return runCatching { Jsoup.parse(value).text() }.getOrDefault(value).trim()
    }

    companion object {
        private const val LoginCallScript =
            "if (typeof login === 'function') { login.apply(this); }"
    }
}
