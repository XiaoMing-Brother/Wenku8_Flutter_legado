package org.mewx.wenku8_flutter.booksource

import java.io.IOException
import java.io.File
import java.net.InetAddress
import java.net.URI
import java.net.URL
import java.nio.charset.Charset
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ExecutionException
import java.util.concurrent.ExecutorCompletionService
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import okhttp3.Call
import okhttp3.Dns
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okio.ByteString.Companion.decodeBase64
import org.json.JSONObject
import org.mozilla.universalchardet.UniversalDetector

internal data class UrlOption(
    val method: String?,
    val headers: Map<String, String>,
    val body: String?,
    val charset: String?,
    val js: String? = null,
    val type: String? = null,
    val webView: Boolean = false,
    val webJs: String? = null,
    val cacheFirst: Boolean = false,
    val webViewDelayTime: Long = 0,
    val bodyJs: String? = null,
    val followRedirects: Boolean = true,
    val retry: Int = 0,
    val dnsIp: String? = null,
    /** 正文规则级 sourceRegex，交给 WebView 嗅探真正的内容资源。 */
    val sourceRegex: String? = null,
)

internal data class RequestSpec(
    val url: String,
    val option: UrlOption,
    /** 触发本次请求的搜索关键字 / 发现地址关键字，供 URL 选项 js、bodyJs 读取。 */
    val key: String = "",
    val page: Int = 1,
    val book: BookData? = null,
    val chapter: ChapterData? = null,
    val infoMap: MutableMap<String, String>? = null,
)

internal data class UrlTransform(
    val url: String? = null,
    val headers: Map<String, String>? = null,
)

internal data class BookSourceResponse(
    val url: String,
    val text: String,
    val statusCode: Int,
    val headers: Map<String, String>,
    val requestUrl: String = url,
    val requestMethod: String = "GET",
    val requestHeaders: Map<String, String> = emptyMap(),
    val requestBody: String? = null,
    val callTimeMs: Long = 0,
)

internal class BookSourceHttp(
    private val variables: BookSourceVariables? = null,
    val rateLimiter: BookSourceRateLimiter = BookSourceRateLimiter(),
) {
    /** URL 选项 webView=true 时由宿主 WebView 执行页面 JS；null 时回退 HTTP。 */
    var webViewFetcher: ((BookSource, RequestSpec, String, String) -> String?)? = null
    /** URL 选项 bodyJs 对响应正文做二次处理。 */
    var responseTransformer: ((BookSource, RequestSpec, BookSourceResponse) -> BookSourceResponse)? = null
    /** URL 选项 js 在地址解析完成后执行，返回值替换 URL。 */
    var urlTransformer: ((BookSource, RequestSpec, String) -> UrlTransform?)? = null
    private val cookies = ConcurrentHashMap<String, BookSourceCookies>()
    private val dnsClients = ConcurrentHashMap<String, OkHttpClient>()
    private data class SessionRequest(val source: BookSource, val initial: HttpUrl, val jar: BookSourceCookies, val headers: Map<String, String>)
    private val searchCalls = ConcurrentHashMap.newKeySet<Call>()
    private val searching = ThreadLocal<Int>()
    private val batchCalls = ThreadLocal<MutableSet<Call>>()
    @Volatile private var searchGeneration = 0
    private val client = OkHttpClient.Builder()
        .connectTimeout(12, TimeUnit.SECONDS)
        .readTimeout(25, TimeUnit.SECONDS)
        .writeTimeout(25, TimeUnit.SECONDS)
        .callTimeout(15, TimeUnit.SECONDS)
        .followRedirects(true)
        .followSslRedirects(true)
        .addNetworkInterceptor { chain ->
            val request = chain.request()
            val session = request.tag(SessionRequest::class.java) ?: return@addNetworkInterceptor chain.proceed(request)
            val url = request.url
            val builder = request.newBuilder()
            val sameTarget = url.origin() == session.initial.origin()
            val headers = sourceHeaders(session.source, url, session.jar)
            if (sameTarget) for ((name, value) in session.headers) headers[name.lowercase()] = value
            val merged = session.jar.values(url) + parseCookie(headers.remove("cookie").orEmpty())
            if (merged.isNotEmpty()) builder.header("Cookie", merged.entries.joinToString("; ") { "${it.key}=${it.value}" })
            for ((name, value) in headers) {
                if (name !in TransportHeaders && (name != "content-type" || request.body != null)) builder.header(name, value)
            }
            val response = chain.proceed(builder.build())
            if (session.source.enabledCookieJar) session.jar.saveResponse(url, response.headers)
            response
        }
        .build()
    private val noRedirectClient by lazy {
        client.newBuilder()
            .followRedirects(false)
            .followSslRedirects(false)
            .build()
    }

    fun <T> asSearch(block: () -> T): T {
        val previous = searching.get()
        searching.set(searchGeneration)
        return try {
            block()
        } finally {
            if (previous == null) searching.remove() else searching.set(previous)
        }
    }

    fun cancelSearches() {
        val calls = synchronized(searchCalls) {
            searchGeneration++
            searchCalls.toList().also { searchCalls.clear() }
        }
        rateLimiter.wakeWaiters()
        for (call in calls) call.cancel()
    }

    fun fetchAll(
        source: BookSource,
        specs: Sequence<RequestSpec>,
        skipRateLimit: Boolean,
        timeoutMillis: Long? = null,
        tolerateErrors: Boolean = false,
    ): List<BookSourceResponse> {
        val requests = specs.iterator()
        if (!requests.hasNext()) return emptyList()
        val generation = searching.get()
        val calls = mutableSetOf<Call>()
        val workers = Executors.newFixedThreadPool(BatchParallelism)
        val completed = ExecutorCompletionService<Pair<Int, BookSourceResponse>>(workers)
        val results = mutableListOf<BookSourceResponse?>()
        var pending = 0
        try {
            while (true) {
                while (pending < BatchParallelism && requests.hasNext()) {
                    if (generation != null && generation != searchGeneration) throw IOException("搜索已取消")
                    val spec = requests.next()
                    val index = results.size
                    results.add(null)
                    completed.submit {
                        searching.set(generation)
                        batchCalls.set(calls)
                        try {
                            index to try {
                                fetch(
                                    source,
                                    spec,
                                    allowUnsuccessful = true,
                                    skipRateLimit = skipRateLimit,
                                    timeoutMillis = timeoutMillis,
                                )
                            } catch (error: Throwable) {
                                error.rethrowIfCancelled()
                                if (!tolerateErrors) throw error
                                // Legado 的测速接口把错误码写进 callTime，书源用它
                                // 判断线路是否可用；异常本身不向外抛。
                                BookSourceResponse(
                                    url = spec.url,
                                    text = error.message.orEmpty(),
                                    statusCode = 0,
                                    headers = emptyMap(),
                                    requestUrl = spec.url,
                                    requestMethod = spec.option.method?.uppercase() ?: "GET",
                                    requestHeaders = spec.option.headers,
                                    requestBody = spec.option.body,
                                    callTimeMs = errorCode(error),
                                )
                            }
                        } finally {
                            batchCalls.remove()
                            searching.remove()
                        }
                    }
                    pending++
                }
                if (pending == 0) return results.requireNoNulls()
                val (index, response) = completed.take().get()
                results[index] = response
                pending--
            }
        } catch (failure: ExecutionException) {
            throw failure.cause ?: failure
        } finally {
            synchronized(calls) {
                workers.shutdownNow()
                for (call in calls) call.cancel()
            }
        }
    }

    fun fetch(
        source: BookSource,
        request: RequestSpec,
        allowUnsuccessful: Boolean = false,
        skipRateLimit: Boolean = false,
        timeoutMillis: Long? = null,
    ): BookSourceResponse {
        val spec = prepareSpec(source, request)
        if (spec.url.startsWith("data:")) {
            val separator = spec.url.indexOf(',')
            require(separator >= 0 && spec.url.substring(0, separator).endsWith(";base64")) {
                "书源 data 地址格式无效"
            }
            require(spec.url.length - separator - 1 <= (MaxResponseBytes + 2) / 3 * 4) {
                "来源响应超过 16 MB"
            }
            val bytes = requireNotNull(spec.url.substring(separator + 1).decodeBase64()) {
                "书源 data 地址 Base64 无效"
            }
            require(bytes.size <= MaxResponseBytes) { "来源响应超过 16 MB" }
            return BookSourceResponse(
                url = spec.url,
                text = if (spec.option.type != null) bytes.hex() else bytes.utf8(),
                statusCode = 200,
                headers = emptyMap(),
                requestUrl = spec.url,
                requestMethod = spec.option.method?.uppercase() ?: "GET",
                requestHeaders = spec.option.headers,
                requestBody = spec.option.body,
            ).let { response ->
                transformResponse(source, spec, response)
            }
        }
        if (spec.option.webView) {
            val started = System.currentTimeMillis()
            var html: String? = null
            var pageUrl = spec.url
            val method = spec.option.method?.uppercase() ?: "GET"
            if (method != "GET" && method != "HEAD") {
                // Legado 在 webView 模式下先按原方法发一次请求，再把响应
                // HTML 交给 WebView；否则 POST 型书源会退化成 GET。
                val prefetched = fetch(
                    source,
                    spec.copy(option = spec.option.copy(webView = false, bodyJs = null)),
                    allowUnsuccessful = true,
                    skipRateLimit = skipRateLimit,
                    timeoutMillis = timeoutMillis,
                )
                html = prefetched.text
                pageUrl = prefetched.url.ifBlank { spec.url }
            }
            val rendered = webViewFetcher?.invoke(source, spec, html.orEmpty(), pageUrl)
            if (rendered != null) {
                return transformResponse(source, spec, BookSourceResponse(
                    url = pageUrl,
                    text = rendered,
                    statusCode = if (rendered.isBlank()) 0 else 200,
                    headers = emptyMap(),
                    requestUrl = spec.url,
                    requestMethod = method,
                    requestHeaders = spec.option.headers,
                    requestBody = spec.option.body,
                    callTimeMs = System.currentTimeMillis() - started,
                ))
            }
        }
        val started = System.currentTimeMillis()
        val response = executeSourceCall(
            source,
            spec,
            skipRateLimit = skipRateLimit,
            timeoutMillis = timeoutMillis,
        ) { response ->
            if (!response.isSuccessful && !allowUnsuccessful) {
                throw IllegalStateException("来源返回 HTTP ${response.code}")
            }
            val body = response.body ?: throw IllegalStateException("来源响应为空")
            val length = body.contentLength()
            if (length > MaxResponseBytes) throw IllegalStateException("来源响应超过 16 MB")
            val bytes = body.bytes()
            if (bytes.size > MaxResponseBytes) throw IllegalStateException("来源响应超过 16 MB")
            val charset = responseCharset(response.header("Content-Type"))
                ?: source.charset?.let {
                    runCatching { Charset.forName(it) }.getOrNull()
                }
                ?: htmlCharset(bytes)
                ?: detectCharset(bytes)
            val text = String(bytes, charset ?: Charsets.UTF_8)
            // Legado：XML 接口的正文没有声明时补上，XPath/XML 解析才稳定。
            val decoded = if (XmlContentType.matches(response.header("Content-Type").orEmpty()) &&
                !text.trimStart().startsWith("<?xml", ignoreCase = true)
            ) {
                "<?xml version=\"1.0\"?>" + text
            } else {
                text
            }
            BookSourceResponse(
                url = response.request.url.toString(),
                text = decoded,
                statusCode = response.code,
                headers = response.headers.toMultimap()
                    // Set-Cookie 用逗号拼接会与 Expires 里的逗号混淆；
                    // 这里保留多行，供 java.post(...).cookies() 正确拆分。
                    .mapValues { entry ->
                        entry.value.joinToString(
                            if (entry.key.equals("Set-Cookie", ignoreCase = true)) "\n" else ", ",
                        )
                    },
                requestUrl = spec.url,
                requestMethod = spec.option.method?.uppercase() ?: "GET",
                requestHeaders = spec.option.headers,
                requestBody = spec.option.body,
                callTimeMs = System.currentTimeMillis() - started,
            )
        }
        return transformResponse(source, spec, response)
    }

    private fun transformResponse(
        source: BookSource,
        spec: RequestSpec,
        response: BookSourceResponse,
    ): BookSourceResponse {
        if (spec.option.bodyJs.isNullOrBlank()) return response
        // Legado 对 XML 响应只补声明，不执行 bodyJs，避免二次处理破坏结构。
        val contentType = response.headers.entries
            .firstOrNull { it.key.equals("Content-Type", ignoreCase = true) }
            ?.value
            .orEmpty()
        if (XmlContentType.matches(contentType)) return response
        val transformer = responseTransformer ?: return response
        return transformer(source, spec, response)
    }

    private fun errorCode(error: Throwable): Long = when (error) {
        is java.net.SocketTimeoutException -> -2L
        is java.net.UnknownHostException -> -3L
        is java.net.ConnectException -> -4L
        is java.net.SocketException -> -5L
        is javax.net.ssl.SSLException -> -6L
        is java.io.InterruptedIOException ->
            if (error.message?.contains("timeout") == true) -1L else -7L
        else -> -7L
    }

    private fun Throwable.rethrowIfCancelled() {
        if (this is InterruptedException ||
            this is java.util.concurrent.CancellationException
        ) {
            throw this
        }
    }

    private fun <T> executeSourceCall(
        source: BookSource, spec: RequestSpec, skipRateLimit: Boolean = false,
        timeoutMillis: Long? = null, read: (okhttp3.Response) -> T,
    ): T {
        val activeClient = clientFor(spec.option)
        val generation = searching.get()
        val batch = batchCalls.get()
        fun checkActive() {
            if (generation != null && generation != searchGeneration) throw IOException("搜索已取消")
        }
        if (!skipRateLimit) rateLimiter.acquire(source, ::checkActive)
        val attempts = spec.option.retry.coerceIn(0, 10) + 1
        var attempt = 0
        while (true) {
            checkActive()
            val call = activeClient.newCall(buildRequest(source, spec))
            if (timeoutMillis != null && timeoutMillis > 0) {
                call.timeout().timeout(timeoutMillis, TimeUnit.MILLISECONDS)
            }
            if (generation != null) synchronized(searchCalls) {
                checkActive()
                searchCalls.add(call)
            }
            try {
                if (batch != null) synchronized(batch) {
                    if (Thread.currentThread().isInterrupted) throw IOException("批量请求已取消")
                    batch.add(call)
                }
                val response = call.execute()
                // Legado 的 retry 语义：只对非 2xx 响应重试，网络异常直接抛出。
                if (!response.isSuccessful && attempt < attempts - 1) {
                    response.close()
                    attempt++
                    continue
                }
                return response.use(read)
            } finally {
                if (batch != null) synchronized(batch) { batch.remove(call) }
                if (generation != null) searchCalls.remove(call)
            }
        }
    }

    fun fetchBytes(source: BookSource, spec: RequestSpec): ByteArray {
        val prepared = prepareSpec(source, spec)
        return executeSourceCall(source, prepared) { response ->
            if (!response.isSuccessful) {
                throw IllegalStateException("来源返回 HTTP ${response.code}")
            }
            val body = response.body ?: throw IllegalStateException("图片响应为空")
            val length = body.contentLength()
            if (length > MaxImageBytes) throw IllegalStateException("图片超过 8 MB")
            val bytes = body.bytes()
            if (bytes.size > MaxImageBytes) throw IllegalStateException("图片超过 8 MB")
            if (bytes.isEmpty()) throw IllegalStateException("图片响应为空")
            bytes
        }
    }

    fun fetchFileBytes(source: BookSource, spec: RequestSpec): ByteArray {
        val prepared = prepareSpec(source, spec)
        return executeSourceCall(source, prepared, timeoutMillis = 120_000) { response ->
            if (!response.isSuccessful) {
                throw IllegalStateException("来源返回 HTTP ${response.code}")
            }
            val body = response.body ?: throw IllegalStateException("文件响应为空")
            val length = body.contentLength()
            if (length > MaxFileBytes) throw IllegalStateException("文件超过 32 MB")
            val bytes = body.bytes()
            if (bytes.size > MaxFileBytes) throw IllegalStateException("文件超过 32 MB")
            if (bytes.isEmpty()) throw IllegalStateException("文件响应为空")
            bytes
        }
    }

    fun downloadResource(source: BookSource, spec: RequestSpec, directory: File): File {
        val prepared = prepareSpec(source, spec)
        return executeSourceCall(source, prepared, timeoutMillis = 120_000) { response ->
            check(response.isSuccessful) { "资源返回 HTTP ${response.code}" }
            val body = response.body ?: error("资源响应为空")
            val type = body.contentType()?.let { "${it.type}/${it.subtype}" }
            val suffix = response.request.url.pathSegments.last().substringAfterLast('.', "").lowercase()
            BookSourceResourceFiles.save(directory, source.type, type, suffix, body.contentLength(), body.byteStream())
        }
    }

    fun fetchText(url: String): String {
        val request = Request.Builder()
            .url(url)
            .header("User-Agent", DefaultUserAgent)
            .get()
            .build()
        client.newCall(request).execute().use { response ->
            if (!response.isSuccessful) {
                throw IllegalStateException("jsLib 下载失败：HTTP ${response.code}")
            }
            val body = response.body ?: throw IllegalStateException("jsLib 下载失败：响应为空")
            val bytes = body.bytes()
            if (bytes.isEmpty()) throw IllegalStateException("jsLib 下载失败：内容为空")
            if (bytes.size > MaxLibBytes) throw IllegalStateException("jsLib 超过 2 MB")
            val charset = responseCharset(response.header("Content-Type"))
                ?: detectCharset(bytes)
                ?: Charsets.UTF_8
            return String(bytes, charset).removePrefix("\uFEFF")
        }
    }

    fun requestSpec(sourceKey: String, spec: String): RequestSpec {
        val trimmed = spec.trim()
        if (trimmed.isEmpty()) throw IllegalArgumentException("书源地址为空")
        // Legado treats the first comma followed by a JSON object as the
        // request-option separator. Using the last comma misparses URLs whose
        // JSON body itself contains an object, e.g. ...,{"body":{"items":[...]}}
        val optionMatch = OptionStartRegex.find(trimmed)
        val urlText: String
        val option: UrlOption
        if (optionMatch != null && optionMatch.range.first > 0) {
            val parsed = runCatching {
                JSONObject(trimmed.substring(optionMatch.range.last + 1))
            }.getOrNull()
            if (parsed != null) {
                urlText = trimmed.substring(0, optionMatch.range.first).trim()
                option = parseOption(parsed)
            } else {
                urlText = trimmed
                option = EmptyOption
            }
        } else {
            urlText = trimmed
            option = EmptyOption
        }
        return encodeRequest(RequestSpec(resolve(sourceKey, urlText), option))
    }

    /**
     * Legado 的 URL 选项 charset 不是响应解码字符集，而是用来重新编码
     * GET 查询参数和 POST 表单正文。中文搜索词必须按目标站点编码提交，
     * 否则会出现“地址能打开但搜索无结果”。
     */
    private fun encodeRequest(spec: RequestSpec): RequestSpec {
        val method = spec.option.method?.uppercase() ?: "GET"
        val charsetName = spec.option.charset?.trim().orEmpty()
        if (method == "GET") {
            return spec.copy(url = encodeQuery(spec.url, charsetName))
        }
        val body = spec.option.body ?: return spec
        if (method != "POST") return spec
        if (spec.option.headers.keys.any { it.equals("Content-Type", ignoreCase = true) }) return spec
        val text = body.trim()
        if (text.startsWith("{") || text.startsWith("[") || text.startsWith("<")) return spec
        if (!text.contains('=') && !text.contains('&')) return spec
        return spec.copy(option = spec.option.copy(body = encodeForm(body, charsetName)))
    }

    private fun encodeQuery(url: String, charsetName: String): String {
        val separator = url.indexOf('?')
        if (separator < 0) return url
        val queryStart = separator + 1
        val fragment = url.indexOf('#', queryStart).takeIf { it >= 0 } ?: url.length
        val query = url.substring(queryStart, fragment)
        if (query.isEmpty()) return url
        val charset = charsetOf(charsetName)
        return buildString {
            append(url.substring(0, queryStart))
            append(encodeQueryPart(query, charset, charsetName))
            append(url.substring(fragment))
        }
    }

    private fun encodeQueryPart(query: String, charset: Charset?, charsetName: String): String {
        if (isEncoded(query)) return query
        if (charsetName.equals("escape", ignoreCase = true)) return escape(query)
        if (charset == null) return query
        val builder = StringBuilder(query.length)
        for (char in query) {
            if (char.code < 128 && QuerySafeChars[char.code]) {
                builder.append(char)
            } else {
                for (byte in char.toString().toByteArray(charset)) {
                    val value = byte.toInt() and 0xFF
                    builder.append('%')
                    builder.append(HexUpper[value ushr 4])
                    builder.append(HexUpper[value and 0x0F])
                }
            }
        }
        return builder.toString()
    }

    private fun encodeForm(body: String, charsetName: String): String {
        val charset = charsetOf(charsetName)
        return body.split('&').joinToString("&") { part ->
            if (part.isEmpty()) return@joinToString part
            val separator = part.indexOf('=')
            val key = if (separator < 0) part else part.substring(0, separator)
            val value = if (separator < 0) "" else part.substring(separator + 1)
            val encodedKey = encodeFormComponent(key, charset, charsetName)
            if (separator < 0) encodedKey else "$encodedKey=${encodeFormComponent(value, charset, charsetName)}"
        }
    }

    private fun encodeFormComponent(value: String, charset: Charset?, charsetName: String): String {
        if (isEncoded(value)) return value
        if (charsetName.equals("escape", ignoreCase = true)) return escape(value)
        return runCatching {
            java.net.URLEncoder.encode(value, charset ?: Charsets.UTF_8)
        }.getOrDefault(value)
    }

    private fun isEncoded(value: String): Boolean {
        var index = 0
        while (index < value.length) {
            val char = value[index]
            if (char == '%') {
                if (index + 2 >= value.length) return false
                if (!value[index + 1].isHex() || !value[index + 2].isHex()) return false
                index += 3
                continue
            }
            if (char.code >= 128 || char == ' ') return false
            index++
        }
        return true
    }

    private fun Char.isHex(): Boolean =
        this in '0'..'9' || this in 'a'..'f' || this in 'A'..'F'

    private fun charsetOf(name: String): Charset? {
        // Legado 在未声明 charset 时仍按 UTF-8 重新编码查询串/表单，
        // 只有 "escape" 表示不做 URL 编码而是走 %uXXXX 转义。
        if (name.equals("escape", ignoreCase = true)) return null
        if (name.isEmpty()) return Charsets.UTF_8
        return runCatching { Charset.forName(name) }.getOrDefault(Charsets.UTF_8)
    }

    private fun escape(value: String): String = buildString {
        for (char in value) {
            val code = char.code
            if (code in 48..57 || code in 65..90 || code in 97..122) {
                append(char)
            } else {
                val prefix = if (code < 16) "%0" else if (code < 256) "%" else "%u"
                append(prefix)
                append(code.toString(16))
            }
        }
    }

    fun pageKey(address: String, responseUrl: String? = null): String {
        val split = OptionStartRegex.find(address)?.range?.first ?: address.length
        return (responseUrl ?: address.substring(0, split)).substringBefore('#').trim() + address.substring(split)
    }

    /**
     * Legado 的 URL 选项 `js` 在地址解析完成后执行，脚本里的 `result`
     * 是当前 URL，返回值替换 URL。只执行一次，避免重试时重复签名。
     */
    private fun prepareSpec(source: BookSource, spec: RequestSpec): RequestSpec {
        val script = spec.option.js?.trim().orEmpty()
        if (script.isEmpty()) return spec
        val transform = runCatching {
            urlTransformer?.invoke(source, spec, script)
        }.getOrNull()
        val url = transform?.url?.trim()?.takeIf { it.isNotEmpty() }
        val headers = transform?.headers
        return RequestSpec(
            url ?: spec.url,
            spec.option.copy(
                js = null,
                headers = headers ?: spec.option.headers,
            ),
        )
    }

    private fun clientFor(option: UrlOption): OkHttpClient {
        val base = if (option.followRedirects) client else noRedirectClient
        val ip = option.dnsIp?.trim().orEmpty()
        if (ip.isEmpty()) return base
        return dnsClients.getOrPut("$ip|${option.followRedirects}") {
            val addresses = ip.split(',')
                .mapNotNull { runCatching { InetAddress.getByName(it.trim()) }.getOrNull() }
                .takeIf { it.isNotEmpty() }
            if (addresses == null) {
                base
            } else {
                base.newBuilder()
                    .dns(object : Dns {
                        override fun lookup(hostname: String) = addresses
                    })
                    .build()
            }
        }
    }

    fun resolve(base: String, value: String): String {
        val text = value.trim()
        if (text.isEmpty()) return ""
        if (text.startsWith("http://") ||
            text.startsWith("https://") ||
            text.startsWith("data:")
        ) {
            return text
        }
        if (text.startsWith("//")) {
            val scheme = runCatching { URI(base).scheme }.getOrNull() ?: "https"
            return "$scheme:$text"
        }
        return try {
            URL(URL(base), text).toString()
        } catch (_: Exception) {
            text
        }
    }

    private fun buildRequest(source: BookSource, spec: RequestSpec): Request {
        val builder = Request.Builder().url(spec.url)
        val initial = requireNotNull(spec.url.toHttpUrlOrNull())
        builder.tag(SessionRequest::class.java, SessionRequest(source, initial, cookieStore(source.key), spec.option.headers))
        builder.header("User-Agent", DefaultUserAgent)
        val method = spec.option.method?.uppercase() ?: "GET"
        val mediaType = spec.option.headers.entries
            .firstOrNull { it.key.equals("Content-Type", ignoreCase = true) }
            ?.value
            ?.toMediaTypeOrNull()
            ?: defaultMediaType(spec.option.body)
        val body = spec.option.body
        when (method) {
            "GET" -> {
                if (!body.isNullOrEmpty()) {
                    val separator = if (spec.url.contains('?')) '&' else '?'
                    builder.url(spec.url + separator + body)
                }
                builder.get()
            }
            "HEAD" -> builder.head()
            "POST" -> builder.post((body ?: "").toRequestBody(mediaType))
            "PUT" -> builder.put((body ?: "").toRequestBody(mediaType))
            "PATCH" -> builder.patch((body ?: "").toRequestBody(mediaType))
            "DELETE" -> {
                if (body == null) builder.delete()
                else builder.delete(body.toRequestBody(mediaType))
            }
            else -> throw IllegalArgumentException("不支持的书源请求方法 $method")
        }
        return builder.build()
    }

    private fun parseOption(json: JSONObject): UrlOption {
        val headers = mutableMapOf<String, String>()
        val rawHeaders = json.opt("headers")
        val headerObject = when (rawHeaders) {
            is JSONObject -> rawHeaders
            is String -> runCatching { JSONObject(rawHeaders) }.getOrNull()
            else -> null
        }
        if (headerObject != null) {
            for (key in headerObject.keys()) {
                val value = headerObject.opt(key)
                if (value != null && value != JSONObject.NULL) {
                    headers[key] = value.toString()
                }
            }
        }
        val webView = when (val raw = json.opt("webView")) {
            is Boolean -> raw
            is Number -> raw.toInt() != 0
            is String -> raw.isNotBlank() && !raw.equals("false", ignoreCase = true)
            else -> false
        }
        return UrlOption(
            method = json.optString("method").trim().ifEmpty { null },
            headers = headers,
            body = json.opt("body")?.takeUnless { it == JSONObject.NULL }?.toString(),
            charset = json.optString("charset").trim().ifEmpty { null },
            js = json.optString("js").trim().ifEmpty { null },
            type = json.optString("type").trim().ifEmpty { null },
            webView = webView,
            webJs = json.optString("webJs").trim().ifEmpty { null },
            cacheFirst = json.optBoolean("cacheFirst", false),
            webViewDelayTime = json.optLong("webViewDelayTime", 0L),
            bodyJs = json.optString("bodyJs").trim().ifEmpty { null },
            followRedirects = json.optBoolean("followRedirects", true),
            retry = json.optString("retry").trim().toIntOrNull()
                ?: runCatching { json.optInt("retry", 0) }.getOrDefault(0),
            dnsIp = json.optString("dnsIp").trim().ifEmpty { null },
            sourceRegex = json.optString("sourceRegex").trim().ifEmpty { null },
        )
    }

    private fun defaultMediaType(body: String?): okhttp3.MediaType? {
        val text = body?.trim().orEmpty()
        return if (text.startsWith("{") || text.startsWith("[")) {
            "application/json; charset=UTF-8".toMediaTypeOrNull()
        } else {
            "application/x-www-form-urlencoded; charset=UTF-8".toMediaTypeOrNull()
        }
    }

    fun cookie(sourceKey: String, url: String = ""): String {
        val jar = cookieStore(sourceKey)
        val values = cookieUrl(sourceKey, url)?.let { jar.values(it) }.orEmpty()
            .ifEmpty { jar.anyValues() }
        return values.entries.joinToString("; ") { "${it.key}=${it.value}" }
    }

    fun cookieKey(sourceKey: String, url: String, key: String): String {
        val jar = cookieStore(sourceKey)
        val values = cookieUrl(sourceKey, url)?.let { jar.values(it) }.orEmpty()
        return values[key].orEmpty().ifEmpty { jar.anyValues()[key].orEmpty() }
    }

    /**
     * 书源里的 java.getCookie 常直接传二级域名（如 "snssdk.com"），
     * 这里补全协议后再按域名读取，读不到时回退到该书源的全部 Cookie。
     */
    private fun cookieUrl(sourceKey: String, url: String): HttpUrl? {
        val raw = url.trim().ifEmpty { sourceKey.trim() }
        raw.toHttpUrlOrNull()?.let { return it }
        if (raw.isEmpty() || raw.contains(' ')) return null
        val host = raw.substringBefore('/').substringBefore('?').substringBefore('#')
        return "https://$host/".toHttpUrlOrNull()
    }

    fun replaceCookie(sourceKey: String, url: String, cookie: String) {
        val target = cookieUrl(sourceKey, url) ?: return
        cookieStore(sourceKey).write(target, parseCookie(cookie), false)
    }

    fun setCookie(sourceKey: String, url: String, cookie: String) {
        val target = cookieUrl(sourceKey, url) ?: return
        cookieStore(sourceKey).write(target, parseCookie(cookie), true)
    }

    @Synchronized fun removeCookie(sourceKey: String) {
        cookieStore(sourceKey).clear()
        cookies.remove(sourceKey)
    }

    /**
     * Legado 的 removeCookie(url) 只清除该域名下的会话；书源可能同时登录
     * 主站和图片站，不能因为删一个域名的 Cookie 就丢掉整本书源登录态。
     */
    fun removeCookie(sourceKey: String, url: String) {
        val target = cookieUrl(sourceKey, url) ?: return
        cookieStore(sourceKey).remove(target)
    }

    fun hasCookie(sourceKey: String): Boolean = cookieStore(sourceKey).hasCookies()

    fun applyLoginHeaderCookie(sourceKey: String, header: String) {
        val json = runCatching { JSONObject(header) }.getOrNull() ?: return
        for (key in json.keys()) {
            if (!key.equals("Cookie", ignoreCase = true)) continue
            val value = json.opt(key)
            if (value == null || value == JSONObject.NULL) return
            replaceCookie(sourceKey, "", value.toString())
            return
        }
    }

    fun loginHeaders(sourceKey: String): Map<String, String> {
        val raw = variables?.get(loginHeaderKey(sourceKey)).orEmpty()
        if (raw.isBlank()) return emptyMap()
        return runCatching {
            val json = JSONObject(raw)
            buildMap {
                for (key in json.keys()) {
                    val value = json.opt(key)
                    if (value != null && value != JSONObject.NULL) {
                        put(key, value.toString())
                    }
                }
            }
        }.getOrDefault(emptyMap())
    }

    fun sourceHeaders(source: BookSource, url: HttpUrl, jar: BookSourceCookies): MutableMap<String, String> {
        val sameSource = url.origin() == source.key.toHttpUrlOrNull()?.origin()
        val headers = mutableMapOf<String, String>()
        for ((name, value) in source.headers) {
            if (sameSource || name.lowercase() in PublicSourceHeaders) headers[name.lowercase()] = value
        }
        if (sameSource && cookies[source.key] === jar) {
            for ((name, value) in loginHeaders(source.key)) {
                if (!name.equals("cookie", true)) headers[name.lowercase()] = value
            }
        }
        return headers
    }

    @Synchronized fun cookieStore(sourceKey: String): BookSourceCookies =
        cookies.getOrPut(sourceKey) { BookSourceCookies(sourceKey, variables) }

    fun parseCookie(cookie: String): Map<String, String> {
        if (cookie.isBlank()) return emptyMap()
        return buildMap {
            for (part in cookie.split(';')) {
                val pair = part.trim()
                val separator = pair.indexOf('=')
                if (separator <= 0) continue
                val name = pair.substring(0, separator).trim()
                if (name.isEmpty() ||
                    name.equals("path", ignoreCase = true) ||
                    name.equals("domain", ignoreCase = true) ||
                    name.equals("expires", ignoreCase = true) ||
                    name.equals("max-age", ignoreCase = true)
                ) {
                    continue
                }
                put(name, pair.substring(separator + 1).trim())
            }
        }
    }

    private fun responseCharset(contentType: String?): Charset? {
        if (contentType == null) return null
        val match = CharsetRegex.find(contentType) ?: return null
        return runCatching { Charset.forName(match.groupValues[1]) }.getOrNull()
    }

    private fun htmlCharset(bytes: ByteArray): Charset? {
        val sample = String(bytes, 0, minOf(bytes.size, 4096), Charsets.ISO_8859_1)
        val match = MetaCharsetRegex.find(sample) ?: return null
        return runCatching { Charset.forName(match.groupValues[1]) }.getOrNull()
    }

    private fun detectCharset(bytes: ByteArray): Charset? {
        if (bytes.isEmpty()) return null
        return try {
            val detector = UniversalDetector(null)
            detector.handleData(bytes, 0, bytes.size)
            detector.dataEnd()
            detector.detectedCharset?.let {
                runCatching { Charset.forName(it) }.getOrNull()
            }
        } catch (_: Exception) {
            null
        }
    }

    companion object {
        private const val BatchParallelism = 4
        private val PublicSourceHeaders = setOf("accept", "accept-language", "user-agent", "referer", "origin")
        private val TransportHeaders = setOf("host", "content-length", "transfer-encoding", "connection")
        private const val MaxResponseBytes = 16 * 1024 * 1024
        private const val MaxImageBytes = 8 * 1024 * 1024
        private const val MaxFileBytes = 32 * 1024 * 1024
        private const val MaxLibBytes = 2 * 1024 * 1024
        internal const val DefaultUserAgent =
            "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 " +
                "(KHTML, like Gecko) Chrome/120.0 Mobile Safari/537.36"
        private val OptionStartRegex = Regex("""\s*,\s*(?=\{)""")
        private val CharsetRegex = Regex("""charset\s*=\s*["']?([\w-]+)""", RegexOption.IGNORE_CASE)
        private val MetaCharsetRegex = Regex(
            """<meta[^>]+charset\s*=\s*["']?([\w-]+)""",
            setOf(RegexOption.IGNORE_CASE, RegexOption.DOT_MATCHES_ALL),
        )
        private const val HexUpper = "0123456789ABCDEF"
        private val QuerySafeChars = BooleanArray(128).apply {
            for (char in "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_.-~!\$%&()*+,/:;=?@[\\]^`{|}") {
                this[char.code] = true
            }
        }
        private val XmlContentType = Regex("(application|text)/\\w*\\+?xml.*", RegexOption.IGNORE_CASE)
        private val EmptyOption = UrlOption(null, emptyMap(), null, null)
    }
}
