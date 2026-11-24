package org.mewx.wenku8_flutter.booksource

import okhttp3.Cookie
import okhttp3.Headers
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import org.json.JSONArray
import org.json.JSONObject

internal fun HttpUrl.origin(): String = newBuilder().encodedPath("/").query(null).fragment(null)
    .username("").password("").build().toString()

internal data class WebCookieLine(
    val target: HttpUrl,
    val value: String,
)

/**
 * 网页登录同时可能落在书源域名和独立的登录页域名上。
 * 这里只接受调用方明确给出的根域名，避免把第三方统计、OAuth 回调域名
 * 的 Cookie 一并带入书源会话。
 */
internal fun webCookieTargets(
    roots: Iterable<HttpUrl>,
    candidates: Iterable<String?> = emptyList(),
): List<HttpUrl> {
    val explicit = roots.mapNotNull {
        it.newBuilder().username("").password("").query(null).fragment(null).build()
    }.distinct()
    val allowed = buildList {
        explicit.mapNotNullTo(this) { it.origin().toHttpUrlOrNull() }
        addAll(explicit)
    }.distinct()
    fun related(url: HttpUrl): Boolean = explicit.any { root ->
        url.scheme == root.scheme &&
            url.port == root.port &&
            (url.host == root.host || url.host.endsWith(".${root.host}"))
    }
    return buildSet {
        addAll(allowed)
        for (candidate in candidates) {
            val url = candidate?.toHttpUrlOrNull() ?: continue
            if (!related(url)) continue
            add(url.newBuilder().username("").password("").query(null).fragment(null).build())
        }
    }.toList()
}

internal fun HttpUrl.webCookieTargets(candidates: Iterable<String?>): List<HttpUrl> {
    return webCookieTargets(listOf(this), candidates)
}

internal fun readWebCookieDetails(
    targets: List<HttpUrl>,
    read: (HttpUrl) -> List<String>,
): List<WebCookieLine> = buildList {
    val seen = mutableSetOf<Pair<String, String>>()
    for (target in targets) for (line in read(target)) {
        val cookie = Cookie.parse(target, line) ?: continue
        if (!cookie.matches(target)) continue
        if (target.encodedPath != "/") {
            val path = line.split(';').drop(1).lastOrNull { it.substringBefore('=').trim().equals("path", true) }
            if (cookie.path == "/" || path?.substringAfter('=', "")?.trim() != cookie.path) continue
        }
        val value = line.trim()
        if (seen.add(target.origin() to value)) add(WebCookieLine(target, value))
    }
}

internal fun readWebCookieLines(targets: List<HttpUrl>, read: (HttpUrl) -> List<String>): List<String> =
    readWebCookieDetails(targets, read).map { it.value }.distinct()

internal class BookSourceCookies(private val key: String, private val variables: BookSourceVariables?) {
    private val byOrigin = mutableMapOf<String, MutableList<Cookie>>()
    private var active = true

    init {
        val raw = variables?.get(cookieKey(key)).orEmpty()
        if (raw.isNotBlank()) runCatching {
            if (raw.startsWith('[')) {
                val saved = JSONArray(raw)
                for (index in 0 until saved.length()) {
                    val pair = saved.getJSONArray(index)
                    val url = pair.getString(0).toHttpUrlOrNull() ?: continue
                    Cookie.parse(url, pair.getString(1))?.let { put(url, it) }
                }
            } else {
                val url = key.toHttpUrlOrNull()
                val legacy = JSONObject(raw)
                if (url != null) for (name in legacy.keys()) manual(url, name, legacy.getString(name))
            }
        }
    }

    @Synchronized fun values(url: HttpUrl): Map<String, String> = buildMap {
        if (!active) return@buildMap
        byOrigin[url.origin()].orEmpty().filter { it.expiresAt > System.currentTimeMillis() && it.matches(url) }
            .sortedByDescending { it.path.length }.forEach { if (it.name !in this) put(it.name, it.value) }
    }

    @Synchronized fun hasCookies() = active && byOrigin.values.any { jar -> jar.any { it.expiresAt > System.currentTimeMillis() } }

    @Synchronized fun webLoginCookies(targets: List<HttpUrl>, explicit: Map<String, String>): List<String> {
        val urls = targets.distinctBy { it.origin() }
        val seen = mutableSetOf<Triple<String, String, String>>()
        val saved = buildList {
            for (url in urls) {
                val originTargets = targets.filter { it.origin() == url.origin() }
                byOrigin[url.origin()].orEmpty().filter { cookie ->
                    active && cookie.expiresAt > System.currentTimeMillis() &&
                        originTargets.any(cookie::matches) &&
                        !(cookie.path == "/" && url == urls.first() && cookie.name in explicit)
                }.forEach { cookie ->
                    if (!seen.add(Triple(cookie.domain, cookie.path, cookie.name))) return@forEach
                    val hostOnly = cookie.toString().split("; ").filterIndexed { index, part ->
                        index == 0 || !part.startsWith("domain=", ignoreCase = true)
                    }.joinToString("; ")
                    add(if (url.isHttps && !cookie.secure) "$hostOnly; Secure" else hostOnly)
                }
            }
        }
        val url = urls.first()
        return saved + explicit.map { (name, value) -> "$name=$value; Path=/" + if (url.isHttps) "; Secure" else "" }
    }

    @Synchronized fun importWebCookies(
        seededTargets: List<HttpUrl>,
        completedUrl: String?,
        lines: List<String>,
        targetUrls: List<String>? = null,
    ) {
        check(active) { "书源登录会话已失效" }
        val targets = webCookieTargets(
            seededTargets,
            listOf(completedUrl) + targetUrls.orEmpty(),
        )
        // 网页登录完成时清理旧会话；增量导入（如登录脚本回填的 Cookie）只覆盖同名 Cookie。
        if (completedUrl != null) {
            for (target in seededTargets) {
                byOrigin[target.origin()]?.removeAll { cookie -> cookie.matches(target) }
            }
        }
        for ((index, line) in lines.withIndex()) {
            val sourceTarget = targetUrls
                ?.getOrNull(index)
                ?.toHttpUrlOrNull()
                ?.takeIf { candidate -> targets.any { it.origin() == candidate.origin() } }
            val parsed = if (sourceTarget != null) {
                Cookie.parse(sourceTarget, line)
                    ?.takeIf { it.matches(sourceTarget) }
                    ?.let { sourceTarget to it }
            } else {
                targets.firstNotNullOfOrNull { target ->
                    Cookie.parse(target, line)
                        ?.takeIf { it.matches(target) }
                        ?.let { target to it }
                }
            } ?: continue
            put(parsed.first, parsed.second)
        }
        persist()
    }

    @Synchronized fun saveResponse(url: HttpUrl, headers: Headers) {
        if (!active) return
        val cookies = Cookie.parseAll(url, headers)
        if (cookies.isEmpty()) return
        for (cookie in cookies) put(url, cookie)
        persist()
    }

    @Synchronized fun write(url: HttpUrl, values: Map<String, String>, replaceAll: Boolean) {
        if (!active) return
        if (replaceAll) byOrigin.remove(url.origin())
        for ((name, value) in values) manual(url, name, value)
        persist()
    }

    @Synchronized fun clear() {
        active = false
        byOrigin.clear()
        variables?.remove(cookieKey(key))
    }

    /** 书源 key 可能是占位域名，脚本按 key 查询 Cookie 时回退到该来源已保存的会话。 */
    @Synchronized fun anyValues(): Map<String, String> = buildMap {
        if (!active) return@buildMap
        for (jar in byOrigin.values) {
            jar.filter { it.expiresAt > System.currentTimeMillis() }
                .sortedByDescending { it.path.length }
                .forEach { if (it.name !in this) put(it.name, it.value) }
        }
    }

    private fun manual(url: HttpUrl, name: String, value: String) {
        val cookie = runCatching { Cookie.Builder().name(name).value(value).hostOnlyDomain(url.host).path("/").build() }.getOrNull()
        if (cookie != null) put(url, cookie)
    }

    private fun put(url: HttpUrl, cookie: Cookie) {
        val jar = byOrigin.getOrPut(url.origin()) { mutableListOf() }
        jar.removeAll { it.expiresAt <= System.currentTimeMillis() || (it.name == cookie.name && it.path == cookie.path && it.domain == cookie.domain) }
        if (cookie.expiresAt > System.currentTimeMillis()) jar.add(cookie)
    }

    private fun persist() {
        val saved = JSONArray()
        for ((origin, jar) in byOrigin) for (cookie in jar) {
            if (cookie.expiresAt > System.currentTimeMillis()) saved.put(JSONArray().put(origin).put(cookie.toString()))
        }
        if (saved.length() == 0) variables?.remove(cookieKey(key)) else variables?.put(cookieKey(key), saved.toString())
    }
}
