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

    fun webLoginConfig(sourceKey: String): WebLoginConfig {
        val source = requireSource(sourceKey)
        val raw = source.loginUrl?.trim().orEmpty()
        if (raw.isEmpty()) throw IllegalArgumentException("书源没有配置登录地址")
        val jar = http.cookieStore(sourceKey)
        val url = resolveWebLoginUrl(source, raw).toHttpUrl()
        val targets = (sourceKey.toHttpUrlOrNull() ?: url).webCookieTargets(listOf(sourceKey, url.toString()))
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
    ): Map<String, Any?> {
        val targets = if (scoped) config.cookieTargets else listOf(config.cookieUrl)
        config.jar.importWebCookies(targets, completedUrl.takeIf { scoped }, cookies)
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
        mapOf(
            "items" to items,
            "hasMore" to BookSourceUrlRule.hasNext(template, page, items.isNotEmpty(), jsonIsLastPage(loaded.text)),
        )
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

    fun detail(sourceKey: String, bookUrl: String, includeDownloads: Boolean = false): Map<String, Any?> {
        val source = requireSource(sourceKey)
        requireTextSource(source)
        val analyzer = analyzer(source)
        val book = BookData(bookUrl = bookUrl)
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
        val totalChapterNum = analyzer
            .getString(info.totalChapterNum, context)
            .trim()
            .toIntOrNull()
        val wordCount = analyzer
            .getString(info.wordCount, context)
            .trim()
            .toIntOrNull()
        val downloads = if (includeDownloads) analyzer.getStrings(info.downloadUrls, context).flatMap { it.lines() }
            .filter { it.isNotBlank() }.map { http.resolve(response.url, it) }.distinct() else emptyList()
        return mapOf(
            "name" to name,
            "downloadUrls" to downloads,
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
            "status" to analyzer.getString(info.status, context),
            "totalChapterNum" to totalChapterNum,
            "wordCount" to wordCount,
        )
    }

    fun chapters(
        sourceKey: String,
        bookUrl: String,
        tocUrl: String?,
    ): List<Map<String, Any?>> {
        val source = requireSource(sourceKey)
        requireTextSource(source)
        if (source.type == 3 && !source.bookInfo.downloadUrls.isNullOrBlank()) {
            val downloads = detail(sourceKey, bookUrl, includeDownloads = true)["downloadUrls"] as List<*>
            check(downloads.isNotEmpty()) { "文件规则没有返回下载地址" }
            return downloads.indices.map { index -> mapOf("title" to "文件 ${index + 1}", "url" to "wenku-download:$index") }
        }
        val analyzer = analyzer(source)
        val book = BookData(bookUrl = bookUrl, tocUrl = tocUrl.orEmpty())
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
                result.add(chapterRow(source, analyzer, row, response.url, book))
            }
            if (!readNext) return emptyList()
            return analyzer.nextPageUrls(source.toc.nextTocUrl, context, visited)
        }
        val start = http.resolve(bookUrl, tocUrl.orEmpty()).ifBlank { bookUrl }
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
    ): String {
        val source = requireSource(sourceKey)
        requireTextSource(source)
        val analyzer = analyzer(source)
        val book = BookData(bookUrl = bookUrl)
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
            val chapter = ChapterData(
                title = chapterTitle.orEmpty(),
                url = url,
                nextUrl = nextUrl,
            )
            val response = applyLoginCheck(
                source,
                fetchResponse(
                    source,
                    http.requestSpec(source.key, url),
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
                        chapter = ChapterData(url = chapterUrl),
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
        val chapter = ChapterData(url = chapterUrl)
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
        val rows = loginUi(source, stored)
        return mapOf(
            "values" to if (stored.isEmpty()) defaultLoginInfo(rows) else stored,
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
        info: Map<String, String> = emptyMap(),
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
    ): ChapterData {
        var chapter = ChapterData(bookUrl = book.bookUrl, baseUrl = baseUrl)
        fun read(expression: String?) = analyzer.getString(expression, RuleContext(row, baseUrl, book = book, chapter = chapter))
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
        val rawUrl = read(rule.chapterUrl).ifBlank {
            when (row) {
                is Element -> row.attr("href")
                is Map<*, *> -> row["url"]?.toString().orEmpty()
                else -> ""
            }
        }
        chapter = chapter.copy(url = rawUrl)
        chapter = chapter.copy(tag = read(rule.updateTime))
        chapter = chapter.copy(isVolume = flag(rule.isVolume))
        chapter = chapter.copy(isVip = flag(rule.isVip))
        return chapter.copy(isPay = flag(rule.isPay))
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
    ): BookSourceResponse {
        val resolved = applyRequestJs(source, spec, key, page, book, chapter)
        return http.fetch(
            source,
            resolved,
            allowUnsuccessful = source.loginCheckJs?.isNotBlank() == true,
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
    ): RequestSpec {
        val script = spec.option.js?.trim().orEmpty()
        if (script.isEmpty()) return spec
        val value = js.eval(
            script,
            JsEnv(
                source = source,
                analyzer = analyzer(source),
                content = spec.url,
                baseUrl = source.key,
                key = key,
                page = page,
                book = book,
                chapter = chapter,
                variables = variables,
            ),
        )
        val option = spec.option.copy(js = null)
        val url = value?.toString()?.trim().orEmpty()
        if (value == null) return spec.copy(option = option)
        if (url.isEmpty()) throw IllegalStateException("书源请求脚本没有返回地址")
        return spec.copy(url = http.resolve(source.key, url), option = option)
    }

    private fun requireSource(key: String): BookSource =
        sources[key] ?: throw IllegalArgumentException("书源不存在，请重新导入")

    private fun requireTextSource(source: BookSource) {
        if (!source.supported) {
            throw IllegalArgumentException(when {
                source.type != 2 -> "当前不支持该书源类型"
                !source.content.imageDecode.isNullOrBlank() -> "暂不支持带 imageDecode 的漫画书源"
                else -> "漫画书源缺少正文规则"
            })
        }
    }

    fun downloadResource(key: String, bookUrl: String, chapterUrl: String, title: String, directory: File): File {
        val source = requireSource(key)
        requireTextSource(source)
        val book = BookData(bookUrl = bookUrl)
        val chapter = ChapterData(title = title, url = chapterUrl)
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
        val spec = applyRequestJs(source, http.requestSpec(key, address), "", 1, book, chapter)
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
        private const val LoginCallScript =
            "if (typeof login === 'function') { login.apply(this); }"
    }
}
