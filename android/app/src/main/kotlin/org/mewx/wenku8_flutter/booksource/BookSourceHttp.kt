package org.mewx.wenku8_flutter.booksource

import java.io.IOException
import java.io.File
import java.net.URI
import java.net.URL
import java.nio.charset.Charset
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit
import okhttp3.Call
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
)

internal data class RequestSpec(val url: String, val option: UrlOption)

internal data class BookSourceResponse(
    val url: String,
    val text: String,
    val statusCode: Int,
    val headers: Map<String, String>,
)

internal class BookSourceHttp(
    private val variables: BookSourceVariables? = null,
) {
    private val cookies = ConcurrentHashMap<String, BookSourceCookies>()
    private data class SessionRequest(val source: BookSource, val initial: HttpUrl, val jar: BookSourceCookies, val headers: Map<String, String>)
    private val searchCalls = ConcurrentHashMap.newKeySet<Call>()
    private val searching = ThreadLocal<Int>()
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
        searchGeneration++
        val calls = searchCalls.toList()
        searchCalls.clear()
        for (call in calls) call.cancel()
    }

    fun fetch(
        source: BookSource,
        spec: RequestSpec,
        allowUnsuccessful: Boolean = false,
    ): BookSourceResponse {
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
            )
        }
        val request = buildRequest(source, spec)
        val call = client.newCall(request)
        val generation = searching.get()
        if (generation != null && generation != searchGeneration) {
            throw IOException("搜索已取消")
        }
        val cancelable = generation != null
        if (cancelable) searchCalls.add(call)
        if (generation != null && generation != searchGeneration) {
            searchCalls.remove(call)
            call.cancel()
            throw IOException("搜索已取消")
        }
        try {
            call.execute().use { response ->
                if (!response.isSuccessful && !allowUnsuccessful) {
                    throw IllegalStateException("来源返回 HTTP ${response.code}")
                }
                val body = response.body ?: throw IllegalStateException("来源响应为空")
                val length = body.contentLength()
                if (length > MaxResponseBytes) throw IllegalStateException("来源响应超过 16 MB")
                val bytes = body.bytes()
                if (bytes.size > MaxResponseBytes) throw IllegalStateException("来源响应超过 16 MB")
                val charset = optionCharset(spec.option)
                    ?: responseCharset(response.header("Content-Type"))
                    ?: source.charset?.let {
                        runCatching { Charset.forName(it) }.getOrNull()
                    }
                    ?: htmlCharset(bytes)
                    ?: detectCharset(bytes)
                return BookSourceResponse(
                    url = response.request.url.toString(),
                    text = String(bytes, charset ?: Charsets.UTF_8),
                    statusCode = response.code,
                    headers = response.headers.toMultimap()
                        .mapValues { entry -> entry.value.joinToString(", ") },
                )
            }
        } finally {
            if (cancelable) searchCalls.remove(call)
        }
    }

    fun fetchBytes(source: BookSource, spec: RequestSpec): ByteArray {
        val request = buildRequest(source, spec)
        client.newCall(request).execute().use { response ->
            if (!response.isSuccessful) {
                throw IllegalStateException("来源返回 HTTP ${response.code}")
            }
            val body = response.body ?: throw IllegalStateException("图片响应为空")
            val length = body.contentLength()
            if (length > MaxImageBytes) throw IllegalStateException("图片超过 8 MB")
            val bytes = body.bytes()
            if (bytes.size > MaxImageBytes) throw IllegalStateException("图片超过 8 MB")
            if (bytes.isEmpty()) throw IllegalStateException("图片响应为空")
            return bytes
        }
    }

    fun downloadResource(source: BookSource, spec: RequestSpec, directory: File): File {
        val call = client.newCall(buildRequest(source, spec))
        call.timeout().timeout(120, TimeUnit.SECONDS)
        return call.execute().use { response ->
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
        return RequestSpec(resolve(sourceKey, urlText), option)
    }

    fun pageKey(address: String, responseUrl: String? = null): String {
        val split = OptionStartRegex.find(address)?.range?.first ?: address.length
        return (responseUrl ?: address.substring(0, split)).substringBefore('#').trim() + address.substring(split)
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
        return UrlOption(
            method = json.optString("method").trim().ifEmpty { null },
            headers = headers,
            body = json.opt("body")?.takeUnless { it == JSONObject.NULL }?.toString(),
            charset = json.optString("charset").trim().ifEmpty { null },
            js = json.optString("js").trim().ifEmpty { null },
            type = json.optString("type").trim().ifEmpty { null },
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
        val target = url.ifEmpty { sourceKey }.toHttpUrlOrNull() ?: return ""
        val values = cookieStore(sourceKey).values(target)
        return values.entries.joinToString("; ") { "${it.key}=${it.value}" }
    }

    fun cookieKey(sourceKey: String, url: String, key: String): String {
        val target = url.ifEmpty { sourceKey }.toHttpUrlOrNull() ?: return ""
        return cookieStore(sourceKey).values(target)[key].orEmpty()
    }

    fun replaceCookie(sourceKey: String, url: String, cookie: String) {
        val target = url.ifEmpty { sourceKey }.toHttpUrlOrNull() ?: return
        cookieStore(sourceKey).write(target, parseCookie(cookie), false)
    }

    fun setCookie(sourceKey: String, url: String, cookie: String) {
        val target = url.ifEmpty { sourceKey }.toHttpUrlOrNull() ?: return
        cookieStore(sourceKey).write(target, parseCookie(cookie), true)
    }

    @Synchronized fun removeCookie(sourceKey: String) {
        cookieStore(sourceKey).clear()
        cookies.remove(sourceKey)
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

    private fun optionCharset(option: UrlOption): Charset? =
        option.charset?.let { runCatching { Charset.forName(it) }.getOrNull() }

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
        private val PublicSourceHeaders = setOf("accept", "accept-language", "user-agent", "referer", "origin")
        private val TransportHeaders = setOf("host", "content-length", "transfer-encoding", "connection")
        private const val MaxResponseBytes = 16 * 1024 * 1024
        private const val MaxImageBytes = 8 * 1024 * 1024
        private const val MaxLibBytes = 2 * 1024 * 1024
        private const val DefaultUserAgent =
            "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 " +
                "(KHTML, like Gecko) Chrome/120.0 Mobile Safari/537.36"
        private val OptionStartRegex = Regex("""\s*,\s*(?=\{)""")
        private val CharsetRegex = Regex("""charset\s*=\s*["']?([\w-]+)""", RegexOption.IGNORE_CASE)
        private val MetaCharsetRegex = Regex(
            """<meta[^>]+charset\s*=\s*["']?([\w-]+)""",
            setOf(RegexOption.IGNORE_CASE, RegexOption.DOT_MATCHES_ALL),
        )
        private val EmptyOption = UrlOption(null, emptyMap(), null, null)
    }
}
