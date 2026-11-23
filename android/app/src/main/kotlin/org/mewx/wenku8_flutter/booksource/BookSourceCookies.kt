package org.mewx.wenku8_flutter.booksource

import okhttp3.Cookie
import okhttp3.Headers
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import org.json.JSONArray
import org.json.JSONObject

internal fun HttpUrl.origin(): String = newBuilder().encodedPath("/").query(null).fragment(null)
    .username("").password("").build().toString()

internal fun HttpUrl.webCookieTargets(candidates: Iterable<String?>): List<HttpUrl> {
    val root = origin()
    return buildSet {
        add(requireNotNull(root.toHttpUrlOrNull()))
        for (candidate in candidates) {
            val url = candidate?.toHttpUrlOrNull() ?: continue
            if (url.origin() == root) add(url.newBuilder().username("").password("").query(null).fragment(null).build())
        }
    }.toList()
}

internal fun readWebCookieLines(targets: List<HttpUrl>, read: (HttpUrl) -> List<String>): List<String> = buildSet {
    for (target in targets) for (line in read(target)) {
        val cookie = Cookie.parse(target, line) ?: continue
        if (!cookie.matches(target)) continue
        if (target.encodedPath != "/") {
            val path = line.split(';').drop(1).lastOrNull { it.substringBefore('=').trim().equals("path", true) }
            if (cookie.path == "/" || path?.substringAfter('=', "")?.trim() != cookie.path) continue
        }
        add(line)
    }
}.toList()

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
        val url = targets.first()
        val saved = byOrigin[url.origin()].orEmpty().filter { cookie ->
            active && cookie.expiresAt > System.currentTimeMillis() && targets.any(cookie::matches) &&
                !(cookie.path == "/" && cookie.name in explicit)
        }.map { cookie ->
            val hostOnly = cookie.toString().split("; ").filterIndexed { index, part ->
                index == 0 || !part.startsWith("domain=", ignoreCase = true)
            }.joinToString("; ")
            if (url.isHttps && !cookie.secure) "$hostOnly; Secure" else hostOnly
        }
        return saved + explicit.map { (name, value) -> "$name=$value; Path=/" + if (url.isHttps) "; Secure" else "" }
    }

    @Synchronized fun importWebCookies(seededTargets: List<HttpUrl>, completedUrl: String?, lines: List<String>) {
        check(active) { "书源登录会话已失效" }
        val root = seededTargets.first()
        val targets = seededTargets + root.webCookieTargets(listOf(completedUrl))
        byOrigin[root.origin()]?.removeAll { cookie -> seededTargets.any(cookie::matches) }
        for (line in lines) {
            val cookie = Cookie.parse(root, line) ?: continue
            if (targets.any(cookie::matches)) put(root, cookie)
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
