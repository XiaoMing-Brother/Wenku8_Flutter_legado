package org.mewx.wenku8_flutter.booksource

import java.util.concurrent.ConcurrentHashMap
import java.io.File
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import org.jsoup.Jsoup
import org.jsoup.nodes.Element
import org.json.JSONArray
import org.json.JSONObject

private const val MaxContentPages = 100
private const val MaxTocPages = 20
private val FalseChapterFlags = setOf("", "null", "false", "no", "not", "0", "0.0")
private val BookNameSuffix = Regex("""\s+作\s*者.*|\s+\S+\s+著""")
private val BookAuthorPrefix = Regex("""^\s*作\s*者[:：\s]+|\s+著""")
private val WordCountRegex = Regex("""(\d+(?:\.\d+)?)\s*(亿|万)?""")

private fun formatBookName(value: String): String =
    value.replace(BookNameSuffix, "").trim()

private fun formatBookAuthor(value: String): String =
    value.replace(BookAuthorPrefix, "").trim()

/**
 * Legado 把字数存成 `12.3万字` / `12345` 这类文本，本仓库用整数保存；
 * 这里换算常见中文单位，无法识别时返回 null。
 */
private fun parseWordCount(value: String): Int? {
    val text = value.trim().replace(",", "").replace(" ", "")
    if (text.isEmpty()) return null
    text.toIntOrNull()?.let { return it }
    val match = WordCountRegex.find(text) ?: return null
    val number = match.groupValues[1].toDoubleOrNull() ?: return null
    val multiplier = when (match.groupValues[2]) {
        "亿" -> 100_000_000.0
        "万" -> 10_000.0
        else -> 1.0
    }
    return (number * multiplier).toInt().takeIf { it > 0 }
}

internal data class WebLoginConfig(
    val url: String,
    val title: String,
    val headers: Map<String, String>,
    val cookieTargets: List<HttpUrl>,
    val cookies: List<String>,
    val jar: BookSourceCookies,
) {
    val cookieUrl: HttpUrl get() = cookieTargets.first()
}

private data class ContentPage(
    val body: String,
    val url: String,
    val nextUrls: List<String>,
    val subContent: String = "",
)

internal class BookSourceEngine(
    private val variables: BookSourceVariables? = BookSourceVariables(null),
    private val host: BookSourceHost? = null,
    cacheRoot: File? = null,
    readerConfig: (() -> Map<String, Any?>)? = null,
) {
    private val sources = ConcurrentHashMap<String, BookSource>()
    private val infoMaps = ConcurrentHashMap<String, MutableMap<String, String>>()
    private val http = BookSourceHttp(variables)
    private val loginDefaultsGuard = ThreadLocal<Boolean>()
    private val files = BookSourceFiles(cacheRoot)
    private val js = BookSourceJs(
        http,
        host,
        { sourceKey -> loginDefaults(sourceKey) },
        files,
        readerConfig,
    )

    init {
        // URL 选项里的 js 用当前书源的作用域执行，result 是被替换的地址。
        http.urlTransformer = { source, request, script ->
            val headers = request.option.headers.toMutableMap()
            val value = runCatching {
                js.eval(
                    script,
                    JsEnv(
                        source = source,
                        analyzer = analyzer(source),
                        content = request.url,
                        baseUrl = request.url,
                        key = request.key,
                        page = request.page,
                        book = request.book,
                        chapter = request.chapter,
                        variables = variables,
                        headerMap = headers,
                        infoMap = request.infoMap,
                    ),
                )
            }.getOrNull()
            UrlTransform(
                url = value?.toString()?.trim()?.takeIf { it.isNotEmpty() },
                headers = headers,
            )
        }
        http.responseTransformer = { source, spec, response ->
            val script = spec.option.bodyJs?.trim().orEmpty()
            if (script.isEmpty()) {
                response
            } else {
                val value = js.eval(
                    script,
                    JsEnv(
                        source = source,
                        analyzer = analyzer(source),
                        content = response.text,
                        baseUrl = response.url,
                        key = spec.key,
                        page = spec.page,
                        book = spec.book,
                        chapter = spec.chapter,
                        variables = variables,
                        infoMap = spec.infoMap,
                    ),
                )
                response.copy(text = value?.toString() ?: "null")
            }
        }
        // URL 选项里的 webView=true 表示必须让页面 JS 跑完再取结果。
        http.webViewFetcher = { source, spec, html, pageUrl ->
            val target = pageUrl.toHttpUrlOrNull()
            val headers = if (target != null) {
                http.sourceHeaders(source, target, http.cookieStore(source.key)) +
                    spec.option.headers
            } else {
                spec.option.headers
            }.toMutableMap().apply {
                if (keys.none { it.equals("User-Agent", ignoreCase = true) }) {
                    put("User-Agent", BookSourceHttp.DefaultUserAgent)
                }
            }
            host?.loadWebView(
                sourceKey = source.key,
                html = html,
                url = pageUrl,
                js = spec.option.webJs.orEmpty(),
                sourceRegex = spec.option.sourceRegex.orEmpty(),
                overrideUrlRegex = "",
                cacheFirst = spec.option.cacheFirst,
                delayMs = spec.option.webViewDelayTime,
                headers = headers,
            )
        }
    }

    fun upsert(value: Any?) {
        val source = BookSource.from(value)
        val previous = sources.put(source.key, source)
        if (previous != null && previous.concurrentRate != source.concurrentRate) http.rateLimiter.clear(source.key)
    }

    fun remove(key: String) {
        sources.remove(key)
        http.rateLimiter.clear(key)
        infoMaps.remove(key)
        variables?.remove(loginInfoKey(key))
        variables?.remove(loginHeaderKey(key))
        http.removeCookie(key)
    }

    fun loginInfo(sourceKey: String): Map<String, Any?> = loginState(sourceKey)

    /**
     * Legado 的 source.getLoginInfoMap() 在没有保存登录信息时返回 loginUi
     * 表单项的默认值，并写回登录信息。登录表单脚本常依赖这一步初始化。
     */
    private fun loginDefaults(sourceKey: String): Map<String, String> {
        if (loginDefaultsGuard.get() == true) return emptyMap()
        loginDefaultsGuard.set(true)
        return try {
            val source = sources[sourceKey] ?: return emptyMap()
            val stored = storedLoginInfo(sourceKey)
            if (stored.isNotEmpty()) return stored
            defaultLoginInfo(loginUi(source, emptyMap()))
        } finally {
            loginDefaultsGuard.remove()
        }
    }

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
        val script = extractLoginJs(source.loginUrl)
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
    ): Map<String, Any?> {
        val source = requireSource(sourceKey)
        if (action.isBlank()) return mapOf("openUrl" to null)
        val info = linkedMapOf<String, String>()
        values?.forEach { (key, value) -> info[key] = value }
        val script = buildString {
            val loginJs = extractLoginJs(source.loginUrl)
            if (loginJs.isNotBlank()) {
                append(loginJs)
                append('\n')
            }
            append(action)
        }
        var openUrl: String? = null
        var toast: String? = null
        var refreshUi = false
        val env = loginEnv(source, info).copy(
            onOpenUrl = { openUrl = it },
            onToast = { toast = it },
            // 登录按钮脚本常用 java.open('login') 重新进入书源登录页。
            // 只有 loginUrl 能解析出真正的网页地址时才交给 WebView；
            // function login(){} 这类登录脚本不能被当成 URL 打开。
            onOpenLogin = {
                if (openUrl.isNullOrBlank()) openUrl = webLoginAddress(source)
            },
            abortAfterOpenUrl = true,
            // java.reUiView()/reLoginView() 会按更新后的 loginInfo 重建表单，
            // 条件字段（例如开启“自订模式”后才出现的配色项）依赖这一步。
            onRefresh = { action -> if (action == "login") refreshUi = true },
        )
        try {
            js.eval(script, env)
        } catch (_: BookSourceOpenUrlSignal) {
            // 网页登录已经在应用内打开，剩余脚本需要等登录完成后再执行。
        }
        val updated = env.infoMap ?: emptyMap<String, String>()
        return mapOf(
            "openUrl" to openUrl,
            "toast" to toast,
            // 登录按钮脚本常用 java.upLoginData()/infoMap 回填验证码、令牌等字段，
            // 需要带回去让 Flutter 登录弹层同步刷新。
            "values" to updated,
            "refreshUi" to refreshUi,
            "loginUi" to if (refreshUi) loginUi(source, updated) else emptyList<Map<String, Any?>>(),
        )
    }

    fun logout(sourceKey: String): Map<String, Any?> {
        variables?.remove(loginInfoKey(sourceKey))
        variables?.remove(loginHeaderKey(sourceKey))
        http.removeCookie(sourceKey)
        return loginState(sourceKey)
    }

    fun webLoginConfig(sourceKey: String, urlOverride: String? = null): WebLoginConfig {
        val source = requireSource(sourceKey)
        val raw = urlOverride?.trim().orEmpty().ifEmpty {
            source.loginUrl?.trim().orEmpty()
        }
        if (raw.isEmpty()) throw IllegalArgumentException("书源没有配置登录地址")
        val jar = http.cookieStore(sourceKey)
        val url = resolveWebLoginUrl(source, raw).toHttpUrl()
        val roots = listOfNotNull(sourceKey.toHttpUrlOrNull(), url).distinctBy { it.origin() }
        val targets = webCookieTargets(roots, listOf(sourceKey, url.toString()))
        val headers = http.sourceHeaders(source, url, jar)
        val explicit = http.parseCookie(headers.remove("cookie").orEmpty())
        return WebLoginConfig(url.toString(), source.name, headers, targets, jar.webLoginCookies(targets, explicit), jar)
    }

    fun importWebLoginCookie(
        sourceKey: String,
        config: WebLoginConfig,
        cookies: List<String>,
        scoped: Boolean = false,
        completedUrl: String? = null,
        cookieUrls: List<String>? = null,
    ): Map<String, Any?> {
        val targets = config.cookieTargets
        config.jar.importWebCookies(targets, completedUrl.takeIf { scoped }, cookies, cookieUrls)
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

    fun image(
        sourceKey: String,
        url: String,
        cover: Boolean = false,
        bookUrl: String = "",
    ): ByteArray {
        val source = requireSource(sourceKey)
        val spec = withSourceHeaders(
            source,
            http.requestSpec(source.key, url),
            key = "",
            page = 1,
        )
        val bytes = http.fetchBytes(source, spec)
        val script = (if (cover) source.coverDecodeJs else source.content.imageDecode)
            ?.trim()
            .orEmpty()
        if (script.isEmpty()) return bytes
        val book = BookData(bookUrl = bookUrl)
        return js.decodeImageBytes(
            script = script,
            bytes = bytes,
            src = url,
            book = book,
            analyzer = analyzer(source),
            source = source,
            variables = variables,
        )?.takeIf { it.isNotEmpty() } ?: bytes
    }

    fun verificationImage(sourceKey: String, imageUrl: String): ByteArray? {
        val value = imageUrl.trim()
        if (value.startsWith("data:", true)) {
            val separator = value.indexOf(',')
            if (separator < 0 || !value.substring(0, separator).endsWith(";base64")) return null
            return runCatching {
                java.util.Base64.getMimeDecoder().decode(value.substring(separator + 1))
            }.getOrNull()
        }
        if (!value.startsWith("http", true)) return null
        return runCatching { image(sourceKey, value) }.getOrNull()
    }

    fun cookieValues(sourceKey: String, url: String): Map<String, String> {
        val target = runCatching {
            val value = url.trim()
            if (value.startsWith("http", true)) value else "https://$value/"
        }.getOrNull()?.toHttpUrlOrNull() ?: return emptyMap()
        return http.cookieStore(sourceKey).values(target)
    }

    fun saveWebViewCookies(sourceKey: String, url: String, cookie: String) {
        if (cookie.isBlank()) return
        http.replaceCookie(sourceKey, url, cookie)
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
                response = fetchResponse(
                    source,
                    http.requestSpec(source.key, candidate),
                    key = keyword,
                    page = page,
                )
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
            book = BookData(),
        )
        val rows = analyzer.getObjects(source.search.bookList, context)
        val items = rows.mapNotNull { row ->
            searchItem(source, analyzer, row, context)
        }
        mapOf(
            "items" to items,
            "hasMore" to BookSourceUrlRule.hasNext(template, page, items.isNotEmpty(), jsonIsLastPage(loaded.text)),
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
        val pageParam = source.explore.pageParam?.trim().orEmpty()
        val templateUsesPageParam = pageParam.isNotEmpty() && supportsPageParam(template)
        val expanded = resolveAddress(
            source,
            analyzer,
            if (templateUsesPageParam) withPageParam(template, page, pageParam) else template,
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
                response = fetchResponse(
                    source,
                    http.requestSpec(source.key, candidate),
                    key = keyword,
                    page = page,
                    infoMap = infoMap,
                )
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
            book = BookData(),
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
        mapOf(
            "items" to items,
            "hasMore" to (
                BookSourceUrlRule.hasNext(template, page, items.isNotEmpty(), jsonIsLastPage(loaded.text)) ||
                    (templateUsesPageParam && items.isNotEmpty())
                ),
        )
    }

    /**
     * Legado 的 `ruleExplore.pageParam`：地址本身没有 {{page}}、也没有 JS/选项时，
     * 按参数名追加页码。只有显式声明 pageParam 的源才启用，避免给所有发现地址
     * 加上无意义的 page 参数。
     */
    private fun supportsPageParam(template: String): Boolean =
        template.isNotBlank() &&
            !template.contains("{{") &&
            !template.contains("}}") &&
            !template.contains('<') &&
            !template.contains("@js:", ignoreCase = true) &&
            !template.contains("<js>", ignoreCase = true) &&
            !UrlOptionPattern.containsMatchIn(template)

    private fun withPageParam(template: String, page: Int, param: String): String {
        if (page <= 1) return template
        val hash = template.indexOf('#')
        val base = if (hash >= 0) template.substring(0, hash) else template
        val fragment = if (hash >= 0) template.substring(hash) else ""
        val pattern = Regex("([?&])${Regex.escape(param)}=\\d+")
        val paged = if (pattern.containsMatchIn(base)) {
            pattern.replace(base) { match -> "${match.groupValues[1]}$param=$page" }
        } else {
            base + (if (base.contains('?')) "&" else "?") + "$param=$page"
        }
        return paged + fragment
    }

    /**
     * 读取 JSON 响应里的末页标记。
     * 返回 true 表示已是最后一页，false 表示还有下一页，null 表示没有可用的标记。
     */
    private fun jsonIsLastPage(text: String): Boolean? {
        val trimmed = text.trim().trimStart('\uFEFF')
        if (!trimmed.startsWith("{")) return null
        val root = runCatching { JSONObject(trimmed) }.getOrNull() ?: return null
        val containers = buildList {
            add(root)
            (root.opt("data") as? JSONObject)?.let { add(it) }
        }
        for (container in containers) {
            jsonPageFlag(container.opt("isLast"))?.let { return it }
            for (key in listOf("hasMore", "hasNext")) {
                jsonPageFlag(container.opt(key))?.let { return !it }
            }
        }
        return null
    }

    private fun jsonPageFlag(value: Any?): Boolean? = when (value) {
        is Boolean -> value
        is Number -> value.toInt() != 0
        is String -> when (value.trim().lowercase()) {
            "1", "true" -> true
            "0", "false" -> false
            else -> null
        }
        else -> null
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
        var searchRequested = false
        var openUrl: String? = null
        var refresh = false
        var login = false
        var toast: String? = null
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
                onSearchBook = {
                    searchRequested = true
                    search = it
                },
                onOpenUrl = { openUrl = it },
                onToast = { toast = it },
                onRefreshExplore = { refresh = true },
                onOpenLogin = { login = true },
            ),
        )
        return mapOf(
            "values" to infoMap.toMap(),
            "search" to search,
            "searchRequested" to searchRequested,
            "openUrl" to openUrl,
            "refresh" to refresh,
            "login" to login,
            "toast" to toast,
        )
    }

    fun detail(sourceKey: String, bookUrl: String, includeDownloads: Boolean = false, metadata: BookData = BookData()): Map<String, Any?> {
        val source = requireSource(sourceKey)
        requireTextSource(source)
        val analyzer = analyzer(source)
        var book = metadata.copy(bookUrl = bookUrl)
        val response = applyLoginCheck(
            source,
            fetchResponse(
                source,
                http.requestSpec(source.key, bookUrl),
                book = book,
            ),
            key = "",
            page = 1,
            book = book,
        )
        var content: Any = response.text
        val init = source.bookInfo.init
        if (!init.isNullOrBlank()) {
            // Legado 的 init 用 getElement 只取第一个匹配节点作为后续字段的解析容器。
            val evaluated = analyzer.getObjects(
                init,
                RuleContext(content, response.url, book = book, fromBookInfo = true),
            ).firstOrNull()
            if (evaluated != null) content = evaluated
        }
        fun context() = RuleContext(content, response.url, book = book, fromBookInfo = true)
        fun read(rule: String?) = analyzer.getString(rule, context())
        fun readUrl(rule: String?) = read(rule).lineSequence()
            .map { it.trim() }
            .firstOrNull { it.isNotEmpty() }
            .orEmpty()
        val info = source.bookInfo
        val pageTitle = runCatching { Jsoup.parse(response.text).title() }.getOrDefault("")
        val name = formatBookName(read(info.name)).ifBlank { book.name }
            .ifBlank { pageTitle }
            .ifBlank { bookUrl }
        book = book.copy(name = name)
        book = book.copy(author = formatBookAuthor(read(info.author)).ifBlank { book.author })
        book = book.copy(
            kind = analyzer.getStrings(info.kind, context())
                .joinToString(",")
                .take(1000)
                .ifBlank { book.kind },
        )
        book = book.copy(wordCount = read(info.wordCount).trim().ifBlank { book.wordCount })
        book = book.copy(lastChapter = read(info.lastChapter).ifBlank { book.lastChapter })
        book = book.copy(intro = plainText(read(info.intro)).ifBlank { book.intro })
        book = book.copy(coverUrl = http.resolve(response.url, readUrl(info.coverUrl)).ifBlank { book.coverUrl })
        book = book.copy(updateTime = read(info.updateTime).ifBlank { book.updateTime })
        val tocUrl = http.resolve(
            response.url,
            readUrl(info.tocUrl).ifBlank { bookUrl },
        )
        book = book.copy(tocUrl = tocUrl)
        val totalChapterNum = analyzer
            .getString(info.totalChapterNum, context())
            .trim()
            .toIntOrNull()
        val downloads = if (includeDownloads) analyzer.getStrings(info.downloadUrls, context()).flatMap { it.lines() }
            .filter { it.isNotBlank() }.map { http.resolve(response.url, it) }.distinct() else emptyList()
        return mapOf(
            "name" to name,
            "downloadUrls" to downloads,
            "author" to book.author,
            "coverUrl" to book.coverUrl,
            "intro" to book.intro,
            "kind" to book.kind,
            "lastChapter" to book.lastChapter,
            "lastUpdate" to book.updateTime,
            "updateTime" to book.updateTime,
            "tocUrl" to tocUrl,
            "status" to read(info.status),
            "totalChapterNum" to totalChapterNum,
            "wordCount" to parseWordCount(book.wordCount),
        )
    }

    fun chapters(
        sourceKey: String,
        bookUrl: String,
        tocUrl: String?,
        metadata: BookData = BookData(),
    ): List<Map<String, Any?>> {
        val source = requireSource(sourceKey)
        requireTextSource(source)
        if (source.type == 3 && !source.bookInfo.downloadUrls.isNullOrBlank()) {
            val downloads = detail(sourceKey, bookUrl, includeDownloads = true)["downloadUrls"] as List<*>
            check(downloads.isNotEmpty()) { "文件规则没有返回下载地址" }
            return downloads.indices.map { index -> mapOf("title" to "文件 ${index + 1}", "url" to "wenku-download:$index") }
        }
        val analyzer = analyzer(source)
        var book = metadata.copy(bookUrl = bookUrl, tocUrl = tocUrl ?: metadata.tocUrl)
        var effectiveTocUrl = tocUrl
        val preUpdateJs = source.toc.preUpdateJs
        if (!preUpdateJs.isNullOrBlank()) {
            var refreshToc = false
            runCatching {
                js.eval(
                    preUpdateJs,
                    JsEnv(
                        source = source,
                        analyzer = analyzer,
                        content = bookUrl,
                        baseUrl = bookUrl,
                        key = "",
                        page = 1,
                        book = book,
                        variables = variables,
                        onRefresh = { action -> if (action == "tocUrl") refreshToc = true },
                    ),
                )
            }
            if (refreshToc) {
                // refreshTocUrl() 在 Legado 中会重新抓详情页，让动态目录地址
                // 覆盖旧值；失败时继续使用调用方传进来的地址。
                runCatching {
                    detail(sourceKey, bookUrl, metadata = book)["tocUrl"]?.toString()
                }.getOrNull()?.takeIf { it.isNotBlank() }?.let {
                    effectiveTocUrl = it
                    book = book.copy(tocUrl = it)
                }
            }
        }
        val result = mutableListOf<ChapterData>()
        val visited = mutableSetOf<String>()
        val rawRule = source.toc.chapterList.orEmpty().trim()
        val reverse = rawRule.startsWith('-')
        val listRule = rawRule.removePrefix("-").removePrefix("+")
        var pageCount = 0
        fun loadPage(url: String, readNext: Boolean): List<String> {
            val key = http.pageKey(url)
            if (pageCount >= MaxTocPages || !visited.add(key)) return emptyList()
            pageCount++
            val response = applyLoginCheck(
                source,
                fetchResponse(
                    source,
                    http.requestSpec(source.key, url),
                    book = book,
                ),
                key = "",
                page = 1,
                book = book,
            )
            val finalKey = http.pageKey(url, response.url)
            if (key != finalKey && !visited.add(finalKey)) return emptyList()
            val context = RuleContext(response.text, url, book = book, redirectUrl = response.url)
            val rows = analyzer.getObjects(listRule, context)
            for (row in rows) {
                result.add(chapterRow(source, analyzer, row, response.url, book, result.size))
            }
            if (!readNext) return emptyList()
            return analyzer.nextPageUrls(source.toc.nextTocUrl, context, visited)
        }
        val start = http.resolve(bookUrl, effectiveTocUrl.orEmpty()).ifBlank { bookUrl }
        val pending = loadPage(start, true)
        if (pending.size == 1) {
            var next = pending.firstOrNull()
            while (next != null) next = loadPage(next, true).firstOrNull()
        } else {
            for (url in pending) {
                if (pageCount >= MaxTocPages) break
                loadPage(url, false)
            }
        }
        if (result.isEmpty()) throw IllegalStateException("目录规则没有返回章节")
        val seen = mutableSetOf<String>()
        val ordered = (if (reverse) result else result.asReversed()).filter { chapter ->
            chapter.url.isBlank() || seen.add(http.resolve(chapter.baseUrl, chapter.url))
        }.asReversed()
        return js.formatChapterTitles(source.toc.formatJs, ordered).map { chapter ->
            mapOf(
                "title" to chapter.title,
                "url" to http.resolve(chapter.baseUrl, chapter.url),
                "isVolume" to chapter.isVolume,
                "isVip" to chapter.isVip,
                "isPay" to chapter.isPay,
                "updateTime" to chapter.tag,
            )
        }
    }

    fun content(
        sourceKey: String,
        bookUrl: String,
        chapterUrl: String,
        nextChapterUrl: String?,
        chapterTitle: String?,
        metadata: BookData = BookData(),
        chapterIndex: Int = 0,
    ): String {
        val source = requireSource(sourceKey)
        requireTextSource(source)
        val analyzer = analyzer(source)
        // Legado 的 book 实体在阅读时保存当前进度章节，正文替换规则常用
        // book.durChapterTitle / durChapterIndex 去掉页内重复标题。
        val book = metadata.copy(
            bookUrl = bookUrl,
            durChapterTitle = chapterTitle.orEmpty(),
            durChapterIndex = chapterIndex,
        )
        val currentChapter = ChapterData(
            index = chapterIndex,
            title = chapterTitle.orEmpty(),
            bookUrl = bookUrl,
            url = chapterUrl,
            variableUrl = chapterUrl,
            nextUrl = nextChapterUrl.orEmpty(),
        )
        val parts = mutableListOf<String>()
        val visited = mutableSetOf<String>()
        val nextRule = source.content.nextContentUrl
        val subRule = source.content.subContent
        var pageTitle: String? = null

        var nextChapterKey: String? = null
        var pageCount = 0

        fun loadPage(
            url: String,
            nextUrl: String,
            readSubContent: Boolean = false,
            readNext: Boolean = true,
        ): ContentPage? {
            val key = http.pageKey(url)
            if (key == nextChapterKey || !visited.add(key)) return null
            pageCount++
            val chapter = currentChapter.copy(url = url, nextUrl = nextUrl)
            val baseRequest = http.requestSpec(source.key, url)
            val contentWebJs = source.content.webJs?.trim().orEmpty()
            // 正文级 webJs 依赖 WebView 跑完页面脚本后再取内容；书源把
            // sourceRegex 写在 ruleContent 里，需要一起交给 WebView 嗅探。
            val request = if (contentWebJs.isEmpty()) baseRequest else baseRequest.copy(
                option = baseRequest.option.copy(
                    webView = true,
                    webJs = contentWebJs,
                    sourceRegex = source.content.sourceRegex?.trim().orEmpty(),
                ),
            )
            val response = applyLoginCheck(
                source,
                fetchResponse(
                    source,
                    request,
                    book = book,
                    chapter = chapter,
                ),
                key = "",
                page = 1,
                book = book,
                chapter = chapter,
            )
            val finalKey = http.pageKey(url, response.url)
            if (finalKey == nextChapterKey || (finalKey != key && !visited.add(finalKey))) return null
            val context = RuleContext(
                content = response.text,
                // Legado 的 baseUrl 保持请求前的章节地址，跳转后的地址单独
                // 通过 redirectUrl/url 暴露；部分书源依赖原始地址解析路由。
                baseUrl = url,
                redirectUrl = response.url,
                book = book,
                chapter = chapter,
            )
            val pieces = mutableListOf<String>()
            val extracted = analyzer.getContent(source.content.content, context)
            val body = if (source.type == 2) comicImages(extracted, response.url) else extracted
            if (body.isNotBlank()) pieces.add(body)
            val subContent = if (readSubContent && !subRule.isNullOrBlank()) {
                val extra = analyzer.getContent(subRule, context)
                when {
                    extra.isBlank() -> ""
                    // Legado：subContent 命中一个地址时再抓一次该地址的正文。
                    extra.trim().startsWith("http", ignoreCase = true) -> runCatching {
                        http.fetch(
                            source,
                            http.requestSpec(source.key, extra.trim()),
                            allowUnsuccessful = true,
                        ).text
                    }.getOrDefault("")
                    else -> extra
                }
            } else {
                ""
            }
            // 正文内标题规则比目录标题更贴近页面，优先用它剥离重复标题。
            // 只需在第一页解析一次，后续分页复用，避免重复执行 JS 规则。
            val titleRule = source.content.title
            if (readSubContent && pageTitle == null && !titleRule.isNullOrBlank()) {
                pageTitle = analyzer.getString(titleRule, context)
            }
            val titleForStrip = pageTitle?.takeIf { it.isNotBlank() }
                ?: chapterTitle.orEmpty()
            val content = analyzer.stripLeadingChapterTitle(
                pieces.joinToString("\n\n"),
                titleForStrip,
            )
            val nextUrls = if (!readNext || nextRule.isNullOrBlank()) {
                emptyList()
            } else {
                analyzer.nextPageUrls(nextRule, context, visited)
            }
            return ContentPage(content, response.url, nextUrls, subContent)
        }

        val first = loadPage(
            chapterUrl,
            nextChapterUrl.orEmpty(),
            readSubContent = true,
        ) ?: throw IllegalStateException("正文规则没有返回内容")
        if (first.body.isNotBlank()) parts.add(first.body)
        val nextChapter = if (nextChapterUrl.isNullOrBlank()) {
            ""
        } else {
            http.resolve(first.url, nextChapterUrl)
        }
        nextChapterKey = nextChapter.takeIf { it.isNotBlank() }?.let { http.pageKey(it) }

        val pending = first.nextUrls
        if (pending.size > 1) {
            // Legado：一次返回多个下一页地址时属于并列分页，全部抓取，不再递归。
            for (url in pending) {
                if (pageCount >= MaxContentPages) break
                // 某一页失败不应丢掉已抓到的内容，跳过该页继续。
                val page = runCatching { loadPage(url, nextChapter, readNext = false) }.getOrNull() ?: continue
                if (page.body.isNotBlank()) parts.add(page.body)
            }
        } else if (pending.size == 1) {
            var currentUrl = pending.first()
            while (currentUrl.isNotBlank() && pageCount < MaxContentPages) {
                // 末页偶发网络错误时保留已抓到的部分，而不是整章失败。
                val page = runCatching { loadPage(currentUrl, nextChapter) }.getOrNull() ?: break
                if (page.body.isNotBlank()) parts.add(page.body)
                currentUrl = page.nextUrls.firstOrNull().orEmpty()
            }
        }
        if (first.subContent.isNotBlank()) {
            if (parts.isNotEmpty()) parts.add(first.subContent)
        }
        if (parts.isEmpty()) throw IllegalStateException(if (source.type == 2) "漫画正文规则没有返回可读的 HTTP 图片" else "正文规则没有返回内容")
        // 阅读器按空行切分段落，页与页之间必须保留段落边界。
        var result = parts.joinToString("\n\n")
        // Legado 的全文替换规则：按行去空白后把整章交给 replaceRegex 处理。
        val replaceRegex = source.content.replaceRegex
        if (!replaceRegex.isNullOrBlank()) {
            val normalized = result.split('\n').joinToString("\n") { it.trim() }
            val replaced = runCatching {
                analyzer.getString(
                    replaceRegex,
                    RuleContext(
                        content = normalized,
                        baseUrl = chapterUrl,
                        book = book,
                        chapter = currentChapter,
                    ),
                )
            }.getOrNull()
            if (!replaced.isNullOrBlank()) result = replaced
        }
        return result
    }

    /**
     * 段评抓取：按 rule 的 reviewUrl 请求，contentRule 作为段评列表选择器，
     * 逐条取 avatarRule / postTimeRule。rule 由 Dart 传入（bookSource.ruleReview 各字段），
     * 无需改 BookSource 模型。返回 Dart 侧 ParagraphReviewService 期望的字段。
     */
    fun review(
        sourceKey: String,
        bookUrl: String,
        chapterUrl: String,
        ruleValue: Map<String, Any?>?,
    ): List<Map<String, Any?>> {
        val source = requireSource(sourceKey)
        requireTextSource(source)
        fun rule(key: String): String =
            ruleValue?.get(key)?.toString()?.trim().orEmpty()
        val reviewUrlRule = rule("reviewUrl")
        val contentRule = rule("contentRule")
        if (reviewUrlRule.isBlank() || contentRule.isBlank()) return emptyList()
        val avatarRule = rule("avatarRule")
        val postTimeRule = rule("postTimeRule")
        val quoteRule = rule("reviewQuoteUrl")
        val paraIndexRule = rule("paraIndexRule")

        val analyzer = analyzer(source)
        val book = BookData(bookUrl = bookUrl)
        val chapter = ChapterData(bookUrl = bookUrl, url = chapterUrl, variableUrl = chapterUrl)
        val urlContext = RuleContext(chapterUrl, chapterUrl, book = book, chapter = chapter)
        val reviewUrl = http.resolve(
            chapterUrl,
            analyzer.getString(reviewUrlRule, urlContext),
        )
        if (reviewUrl.isBlank()) return emptyList()

        val response = applyLoginCheck(
            source,
            fetchResponse(
                source,
                http.requestSpec(source.key, reviewUrl),
                book = book,
                chapter = chapter,
            ),
            key = "",
            page = 1,
            book = book,
            chapter = chapter,
        )
        val context = RuleContext(response.text, response.url, book = book, chapter = chapter)
        val rows = analyzer.getObjects(contentRule, context)
        return rows.mapNotNull { row ->
            val rowContext = context.copy(content = row)
            val content = analyzer.stringValue(row).trim()
            if (content.isEmpty()) return@mapNotNull null
            mapOf<String, Any?>(
                "content" to content,
                "avatarUrl" to http.resolve(
                    response.url,
                    analyzer.getString(avatarRule, rowContext),
                ),
                "postTime" to analyzer.getString(postTimeRule, rowContext),
                "quoteUrl" to if (quoteRule.isBlank()) {
                    ""
                } else {
                    http.resolve(response.url, analyzer.getString(quoteRule, rowContext))
                },
                "reviewUrl" to reviewUrl,
                "paraIndex" to analyzer.getString(paraIndexRule, rowContext)
                    .trim()
                    .toIntOrNull(),
            )
        }
    }

    private fun searchItem(
        source: BookSource,
        analyzer: BookSourceAnalyzer,
        row: Any?,
        parent: RuleContext,
        rule: SearchRule = source.search,
    ): Map<String, Any?>? {
        var book = BookData(pendingVariables = parent.book?.pendingVariables.orEmpty().toMutableMap())
        fun read(expression: String?) = analyzer.getString(expression, parent.copy(content = row, book = book))
        fun readUrl(expression: String?) = read(expression).lineSequence()
            .map { it.trim() }
            .firstOrNull { it.isNotEmpty() }
            .orEmpty()
        book = book.copy(name = formatBookName(read(rule.name)).ifBlank {
            when (row) {
                is Element -> row.text()
                is Map<*, *> -> row["name"]?.toString().orEmpty()
                else -> analyzer.stringValue(row)
            }
        })
        book = book.copy(author = formatBookAuthor(read(rule.author)))
        book = book.copy(
            kind = analyzer.getStrings(rule.kind, parent.copy(content = row, book = book))
                .joinToString(",")
                .take(1000),
        )
        book = book.copy(wordCount = read(rule.wordCount).trim())
        book = book.copy(lastChapter = read(rule.lastChapter))
        book = book.copy(intro = plainText(read(rule.intro)))
        book = book.copy(coverUrl = http.resolve(parent.baseUrl, readUrl(rule.coverUrl)))
        book = book.copy(updateTime = read(rule.updateTime))
        val bookUrl = http.resolve(
            parent.baseUrl,
            readUrl(rule.bookUrl).ifBlank {
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
        book = book.copy(bookUrl = bookUrl)
        for ((name, value) in book.pendingVariables) variables?.writeRule(source.key, book, null, name, value)
        return mapOf(
            "name" to book.name,
            "author" to book.author,
            "kind" to book.kind,
            "intro" to book.intro,
            "lastChapter" to book.lastChapter,
            "updateTime" to book.updateTime,
            "wordCount" to parseWordCount(book.wordCount),
            "bookUrl" to bookUrl,
            "coverUrl" to book.coverUrl,
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
        return BookSourceUrlRule.resolve(
            template.trim(), page,
            evaluate = { script, previous ->
                js.eval(script, JsEnv(source, analyzer, previous, source.key, key, page,
                    infoMap = infoMap, variables = variables))?.toString().orEmpty()
            },
            expand = { analyzer.expand(it, key = key, page = page, baseUrl = source.key) },
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
        val stored = storedLoginInfo(sourceKey)
        var rows = loginUi(source, stored)
        var values = defaultLoginInfo(rows).toMutableMap()
        for ((key, value) in stored) if (value.isNotEmpty()) values[key] = value
        // Legado 首次打开表单时先用 loginUi 默认值生成登录信息，再按这些
        // 默认值重新渲染登录表单；依赖开关状态的条件字段（例如“自订模式”
        // 后才出现的颜色、圆角、高度）必须走第二遍才会显示。
        if (rows.isNotEmpty() && values != stored) {
            val rebuilt = loginUi(source, values)
            if (rebuilt.isNotEmpty()) {
                rows = rebuilt
                val rebuiltValues = defaultLoginInfo(rows).toMutableMap()
                for ((key, value) in values) if (value.isNotEmpty()) rebuiltValues[key] = value
                values = rebuiltValues
            }
        }
        if (stored.isEmpty() && values.isNotEmpty()) {
            // 和 Legado getLoginInfoMap() 一样，把默认值写入登录信息，
            // 后续登录脚本与规则可以直接读取。
            variables?.put(loginInfoKey(sourceKey), JSONObject(values).toString())
        }
        return mapOf(
            // 补齐已保存信息中缺失的字段；Legado 会对空的 select/toggle
            // 使用 loginUi 的默认值，否则条件标题和后续字段会判断错误。
            "values" to values,
            "loginUi" to rows,
            "loginUrl" to source.loginUrl.orEmpty(),
            "loginCheckJs" to source.loginCheckJs.orEmpty(),
            "hasLoginHeader" to http.loginHeaders(sourceKey).isNotEmpty(),
            "hasCookie" to http.hasCookie(sourceKey),
        )
    }

    private fun loginUi(source: BookSource, values: Map<String, String>): List<Map<String, Any?>> {
        val raw = source.loginUi?.trim().orEmpty()
        if (raw.isEmpty()) return emptyList()
        val env = loginEnv(source, values)
        val evaluated = when {
            raw.startsWith("@js:", ignoreCase = true) ->
                js.eval(loginUiScript(source, raw.substring(4)), env)
            raw.startsWith("<js>", ignoreCase = true) -> {
                val end = raw.lastIndexOf("</js>")
                val script = if (end > 4) raw.substring(4, end) else raw.substring(4)
                js.eval(loginUiScript(source, script), env)
            }
            else -> raw
        }
        if (evaluated is List<*>) {
            return evaluated.mapNotNull { item ->
                (item as? Map<*, *>)?.let { loginRow(it, source, env) }
            }
        }
        val text = evaluated?.toString().orEmpty()
        val array = parseJsonArray(text) ?: return emptyList()
        return buildList {
            for (index in 0 until array.length()) {
                val map = jsonToKotlin(array.opt(index)) as? Map<*, *> ?: continue
                loginRow(map, source, env)?.let(::add)
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

    private fun loginRow(
        value: Map<*, *>,
        source: BookSource,
        env: JsEnv,
    ): Map<String, Any?>? {
        val name = value["name"]?.toString()?.trim().orEmpty()
        if (name.isEmpty()) return null
        val style = value["style"] as? Map<*, *>
        return mapOf(
            "name" to name,
            "title" to loginRowTitle(name, value["viewName"]?.toString().orEmpty(), source, env),
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

    private fun loginRowTitle(
        name: String,
        rawTitle: String,
        source: BookSource,
        env: JsEnv,
    ): String {
        val title = rawTitle.trim()
        if (title.isEmpty()) return name
        if (title.length < 2) return title
        val first = title.first()
        val last = title.last()
        if ((first == '\'' && last == '\'') || (first == '"' && last == '"')) {
            return title.substring(1, title.length - 1)
        }
        val script = when {
            title.startsWith("@js:", ignoreCase = true) -> title.substring(4)
            title.startsWith("<js>", ignoreCase = true) -> {
                val end = title.lastIndexOf("</js>")
                if (end > 4) title.substring(4, end) else title.substring(4)
            }
            else -> return title
        }
        val login = extractLoginJs(source.loginUrl)
        val code = if (login.isBlank()) script else "$login\n$script"
        return runCatching { js.eval(code, env)?.toString() }
            .getOrNull()
            ?.takeIf { it.isNotBlank() }
            ?: name
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

    private fun webLoginAddress(source: BookSource): String? {
        val raw = source.loginUrl?.trim().orEmpty()
        if (raw.isEmpty()) return null
        if (raw.startsWith("http://", ignoreCase = true) ||
            raw.startsWith("https://", ignoreCase = true)
        ) {
            return raw
        }
        if (!raw.startsWith("@js:", ignoreCase = true) &&
            !raw.startsWith("<js>", ignoreCase = true)
        ) {
            return null
        }
        return runCatching { resolveWebLoginUrl(source, raw) }.getOrNull()
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
                headerMap = response.requestHeaders.toMutableMap(),
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
        info: Map<String, String> = emptyMap(),
    ): JsEnv = JsEnv(
        source = source,
        analyzer = analyzer(source),
        content = info,
        baseUrl = source.key,
        key = "",
        page = 1,
        // 登录表单脚本（含 loginUi 的按钮 action）会读写 infoMap，
        // 例如 java.open('login', ...); saveKeys(infoMap)。
        infoMap = linkedMapOf<String, String>().apply { putAll(info) },
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

    /** http(s) 网页地址交给 WebView 登录；其余（含 @js:/未加前缀的脚本）按登录脚本执行。 */
    private fun extractLoginJs(rule: String?): String {
        val text = rule?.trim().orEmpty()
        return if (
            text.startsWith("http://", ignoreCase = true) ||
            text.startsWith("https://", ignoreCase = true)
        ) {
            ""
        } else {
            extractJs(text)
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
        index: Int = 0,
    ): ChapterData {
        var chapter = ChapterData(index = index, bookUrl = book.bookUrl, baseUrl = baseUrl)
        fun read(expression: String?) = analyzer.getString(expression, RuleContext(row, baseUrl, book = book, chapter = chapter))
        fun readUrl(expression: String?) = read(expression).lineSequence()
            .map { it.trim() }
            .firstOrNull { it.isNotEmpty() }
            .orEmpty()
        fun flag(expression: String?): Boolean = read(expression).trim().lowercase() !in FalseChapterFlags
        val rule = source.toc
        val title = read(rule.chapterName).ifBlank {
            when (row) {
                is Element -> row.text()
                is Map<*, *> -> row["title"]?.toString().orEmpty()
                else -> analyzer.stringValue(row)
            }
        }
        chapter = chapter.copy(title = title)
        val rawUrl = readUrl(rule.chapterUrl).ifBlank {
            when (row) {
                is Element -> row.attr("href")
                is Map<*, *> -> row["url"]?.toString().orEmpty()
                else -> ""
            }
        }
        chapter = chapter.copy(url = rawUrl, variableUrl = http.resolve(baseUrl, rawUrl))
        if (chapter.variableUrl.isNotEmpty()) for ((name, value) in chapter.pendingVariables) {
            variables?.writeRule(source.key, book, chapter, name, value)
        }
        chapter = chapter.copy(tag = read(rule.updateTime))
        chapter = chapter.copy(isVolume = flag(rule.isVolume))
        chapter = chapter.copy(isVip = flag(rule.isVip))
        chapter = chapter.copy(isPay = flag(rule.isPay))
        return chapter
    }

    private fun analyzer(source: BookSource): BookSourceAnalyzer =
        BookSourceAnalyzer(source, http, js, variables)

    private fun fetchResponse(
        source: BookSource,
        spec: RequestSpec,
        key: String = "",
        page: Int = 1,
        book: BookData? = null,
        chapter: ChapterData? = null,
        infoMap: MutableMap<String, String>? = null,
    ): BookSourceResponse {
        val resolved = applyRequestJs(source, spec, key, page, book, chapter, infoMap)
        return http.fetch(
            source,
            withSourceHeaders(source, resolved, key, page, book, chapter, infoMap),
            allowUnsuccessful = source.loginCheckJs?.isNotBlank() == true,
        )
    }

    private fun withSourceHeaders(
        source: BookSource,
        spec: RequestSpec,
        key: String,
        page: Int,
        book: BookData? = null,
        chapter: ChapterData? = null,
        infoMap: MutableMap<String, String>? = null,
    ): RequestSpec {
        val headers = js.evaluatedHeaders(
            JsEnv(
                source = source,
                analyzer = analyzer(source),
                content = spec.url,
                baseUrl = spec.url,
                key = key,
                page = page,
                book = book,
                chapter = chapter,
                variables = variables,
                infoMap = infoMap,
            ),
            spec.url,
        )
        if (headers.isEmpty()) return spec
        return spec.copy(
            option = spec.option.copy(
                headers = headers + spec.option.headers,
            ),
        )
    }

    /**
     * Legado 的 URL 选项允许用 `js` 改写最终请求地址。脚本中的 `result`
     * 是去掉选项后的当前地址，返回值会作为新的地址继续请求。
     */
    private fun applyRequestJs(
        source: BookSource,
        spec: RequestSpec,
        key: String,
        page: Int,
        book: BookData?,
        chapter: ChapterData?,
        infoMap: MutableMap<String, String>?,
    ): RequestSpec {
        val script = spec.option.js?.trim().orEmpty()
        val contextSpec = spec.copy(
            key = key,
            page = page,
            book = book,
            chapter = chapter,
            infoMap = infoMap,
        )
        if (script.isEmpty()) return contextSpec
        val headers = spec.option.headers.toMutableMap()
        val env = JsEnv(
            source = source,
            analyzer = analyzer(source),
            content = spec.url,
            baseUrl = spec.url,
            key = key,
            page = page,
            book = book,
            chapter = chapter,
            variables = variables,
            headerMap = headers,
            infoMap = infoMap,
        )
        val value = js.eval(script, env)
        val option = spec.option.copy(js = null, headers = headers)
        val url = value?.toString()?.trim().orEmpty()
        if (value == null) return contextSpec.copy(option = option)
        if (url.isEmpty()) throw IllegalStateException("书源请求脚本没有返回地址")
        return contextSpec.copy(url = http.resolve(source.key, url), option = option)
    }

    private fun requireSource(key: String): BookSource =
        sources[key] ?: throw IllegalArgumentException("书源不存在，请重新导入")

    private fun requireTextSource(source: BookSource) {
        if (!source.supported) {
            throw IllegalArgumentException(when {
                source.type == 2 && source.content.content.isNullOrBlank() -> "漫画书源缺少正文规则"
                source.type != 2 -> "当前不支持该书源类型"
                else -> "漫画书源缺少正文规则"
            })
        }
    }

    fun downloadResource(key: String, bookUrl: String, chapterUrl: String, title: String, directory: File): File {
        val source = requireSource(key)
        requireTextSource(source)
        val book = BookData(bookUrl = bookUrl)
        val chapter = ChapterData(title = title, bookUrl = bookUrl, url = chapterUrl, variableUrl = chapterUrl)
        val address = when (source.type) {
            1, 4 -> {
                val response = applyLoginCheck(source, fetchResponse(source, http.requestSpec(key, chapterUrl), book = book, chapter = chapter),
                    "", 1, book, chapter)
                val context = RuleContext(response.text, chapterUrl, book = book, chapter = chapter, redirectUrl = response.url)
                val link = analyzer(source).getString(source.content.content, context).trim()
                require(link.isNotBlank() && !link.startsWith('<')) { "媒体规则没有返回直链" }
                http.resolve(response.url, link)
            }
            3 -> {
                require(!source.bookInfo.downloadUrls.isNullOrBlank() && chapterUrl.startsWith("wenku-download:")) { "没有文件下载规则" }
                val links = detail(key, bookUrl, includeDownloads = true)["downloadUrls"] as List<*>
                links.getOrNull(chapterUrl.substringAfter(':').toIntOrNull() ?: -1) as? String ?: error("文件下载地址已失效")
            }
            else -> error("该书源不是音视频或下载型书源")
        }
        val spec = applyRequestJs(source, http.requestSpec(key, address), "", 1, book, chapter, null)
        return http.downloadResource(source, spec, directory)
    }

    private fun comicImages(raw: String, pageUrl: String): String {
        val base = pageUrl.toHttpUrl()
        val html = raw.trimStart().startsWith('<')
        val sources = if (html) {
            Jsoup.parseBodyFragment(raw, pageUrl).select("img").map { image ->
                listOf("data-src", "data-original", "src").firstNotNullOfOrNull { image.attr(it).trim().takeIf(String::isNotEmpty) }.orEmpty()
            }
        } else raw.lineSequence().map(String::trim).filter { line ->
            line.startsWith('/') || line.startsWith("./") || line.startsWith("../") || line.toHttpUrlOrNull() != null ||
                ComicImageFile.containsMatchIn(line)
        }.toList()
        return sources.filter(String::isNotBlank).mapNotNull { base.resolve(it) }.joinToString("\n") { url ->
            Element("img").attr("src", url.toString()).outerHtml()
        }
    }

    private fun plainText(value: String): String {
        if (value.isBlank() || !value.contains('<')) return value.trim()
        return runCatching { Jsoup.parse(value).text() }.getOrDefault(value).trim()
    }

    companion object {
        private val ComicImageFile = Regex("""^[^\s<>]+\.(?:png|jpe?g|gif|webp|avif|bmp)(?:[?#].*)?$""", RegexOption.IGNORE_CASE)
        /** 地址选项 `,{...}` 分隔符；忽略 JSON 字符串内部的逗号。 */
        private val UrlOptionPattern = Regex(""",(?=(?:[^"]*"[^"]*")*[^"]*$)\s*\{""")
        private const val LoginCallScript =
            "if (typeof login === 'function') { login.apply(this); }"
    }
}
