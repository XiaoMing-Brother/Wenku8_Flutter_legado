package org.mewx.wenku8_flutter.booksource

import java.io.IOException
import java.net.URI
import java.net.URL
import java.nio.charset.Charset
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit
import okhttp3.Call
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import org.mozilla.universalchardet.UniversalDetector

internal data class UrlOption(
    val method: String?,
    val headers: Map<String, String>,
    val body: String?,
    val charset: String?,
    val js: String? = null,
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
    private val cookies = ConcurrentHashMap<String, MutableMap<String, String>>()
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
                storeCookies(source.key, response.headers.values("Set-Cookie"))
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
            storeCookies(source.key, response.headers.values("Set-Cookie"))
            val body = response.body ?: throw IllegalStateException("图片响应为空")
            val length = body.contentLength()
            if (length > MaxImageBytes) throw IllegalStateException("图片超过 8 MB")
            val bytes = body.bytes()
            if (bytes.size > MaxImageBytes) throw IllegalStateException("图片超过 8 MB")
            if (bytes.isEmpty()) throw IllegalStateException("图片响应为空")
            return bytes
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
        val loginHeaders = loginHeaders(source.key)
        for ((key, value) in source.headers) builder.header(key, value)
        for ((key, value) in loginHeaders) builder.header(key, value)
        for ((key, value) in spec.option.headers) builder.header(key, value)
        if (source.headers.keys.none { it.equals("User-Agent", ignoreCase = true) } &&
            loginHeaders.keys.none { it.equals("User-Agent", ignoreCase = true) } &&
            spec.option.headers.keys.none { it.equals("User-Agent", ignoreCase = true) }
        ) {
            builder.header("User-Agent", DefaultUserAgent)
        }
        val hasExplicitCookie =
            source.headers.keys.any { it.equals("Cookie", ignoreCase = true) } ||
                loginHeaders.keys.any { it.equals("Cookie", ignoreCase = true) } ||
                spec.option.headers.keys.any { it.equals("Cookie", ignoreCase = true) }
        if (!hasExplicitCookie) {
            cookieHeader(source.key, spec.url)?.let { builder.header("Cookie", it) }
        }
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

    private fun cookieHeader(sourceKey: String, url: String): String? {
        val values = cookieStore(sourceKey)
        if (!url.startsWith("http")) return null
        if (values.isEmpty()) return null
        return values.entries.joinToString("; ") { "${it.key}=${it.value}" }
    }

    private fun storeCookies(sourceKey: String, values: List<String>) {
        if (values.isEmpty()) return
        val store = cookieStore(sourceKey)
        for (value in values) {
            val pair = value.substringBefore(';').trim()
            val separator = pair.indexOf('=')
            if (separator <= 0) continue
            store[pair.substring(0, separator).trim()] = pair.substring(separator + 1).trim()
        }
        persistCookies(sourceKey, store)
    }

    fun cookie(sourceKey: String, url: String = ""): String {
        if (url.isNotEmpty() && !url.startsWith("http")) return ""
        val values = cookieStore(sourceKey)
        if (values.isEmpty()) return ""
        return values.entries.joinToString("; ") { "${it.key}=${it.value}" }
    }

    fun cookieKey(sourceKey: String, url: String, key: String): String {
        if (url.isNotEmpty() && !url.startsWith("http")) return ""
        return cookieStore(sourceKey)[key].orEmpty()
    }

    fun replaceCookie(sourceKey: String, url: String, cookie: String) {
        if (url.isNotEmpty() && !url.startsWith("http")) return
        val store = cookieStore(sourceKey)
        for ((key, value) in parseCookie(cookie)) store[key] = value
        persistCookies(sourceKey, store)
    }

    fun setCookie(sourceKey: String, url: String, cookie: String) {
        if (url.isNotEmpty() && !url.startsWith("http")) return
        val store = cookieStore(sourceKey)
        store.clear()
        store.putAll(parseCookie(cookie))
        persistCookies(sourceKey, store)
    }

    fun removeCookie(sourceKey: String) {
        cookies.remove(sourceKey)
        variables?.remove(cookieKey(sourceKey))
    }

    fun hasCookie(sourceKey: String): Boolean = cookieStore(sourceKey).isNotEmpty()

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

    private fun loginHeaders(sourceKey: String): Map<String, String> {
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

    private fun cookieStore(sourceKey: String): MutableMap<String, String> =
        cookies.computeIfAbsent(sourceKey) {
            loadCookies(sourceKey)
        }

    private fun loadCookies(sourceKey: String): MutableMap<String, String> {
        val raw = variables?.get(cookieKey(sourceKey)).orEmpty()
        if (raw.isBlank()) return ConcurrentHashMap()
        return runCatching {
            val json = JSONObject(raw)
            ConcurrentHashMap<String, String>().apply {
                for (key in json.keys()) {
                    val value = json.opt(key)
                    if (value != null && value != JSONObject.NULL) {
                        put(key, value.toString())
                    }
                }
            }
        }.getOrDefault(ConcurrentHashMap())
    }

    private fun persistCookies(
        sourceKey: String,
        store: MutableMap<String, String>,
    ) {
        if (store.isEmpty()) {
            variables?.remove(cookieKey(sourceKey))
            return
        }
        val json = JSONObject()
        for ((key, value) in store) json.put(key, value)
        variables?.put(cookieKey(sourceKey), json.toString())
    }

    private fun parseCookie(cookie: String): Map<String, String> {
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
