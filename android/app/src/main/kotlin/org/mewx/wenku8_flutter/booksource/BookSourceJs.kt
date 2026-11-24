package org.mewx.wenku8_flutter.booksource

import android.util.Base64
import android.util.Log
import java.net.URLEncoder
import java.security.MessageDigest
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.ConcurrentHashMap
import okio.ByteString.Companion.decodeHex
import org.json.JSONArray
import org.json.JSONObject
import org.jsoup.nodes.Element
import org.mozilla.javascript.BaseFunction
import org.mozilla.javascript.Context
import org.mozilla.javascript.NativeArray
import org.mozilla.javascript.NativeJSON
import org.mozilla.javascript.NativeJavaObject
import org.mozilla.javascript.NativeObject
import org.mozilla.javascript.RhinoException
import org.mozilla.javascript.Scriptable
import org.mozilla.javascript.ScriptableObject
import org.mozilla.javascript.Undefined
import org.mozilla.javascript.WrappedException

internal class BookSourceJs(private val http: BookSourceHttp) {
    private val ruleVariableName = Regex("[A-Za-z_][A-Za-z0-9_]*")
    private val cache = JsCache()
    private val ephemeralVariables = BookSourceVariables(null)
    private val remoteLibs = ConcurrentHashMap<String, String>()

    fun formatChapterTitles(script: String?, chapters: List<ChapterData>): List<ChapterData> {
        if (script.isNullOrBlank()) return chapters
        val cx = Context.enter()
        try {
            cx.optimizationLevel = -1
            cx.languageVersion = Context.VERSION_ES6
            val scope = cx.initSafeStandardObjects()
            val compiled = try {
                cx.compileString(script, "ruleToc.formatJs", 1, null)
            } catch (_: RhinoException) {
                return chapters
            }
            ScriptableObject.putProperty(scope, "gInt", 0)
            return chapters.mapIndexed { index, chapter ->
                val value = toJs(cx, scope, chapter.toMap()) as Scriptable
                ScriptableObject.putProperty(value, "index", index)
                ScriptableObject.putProperty(scope, "chapter", value)
                ScriptableObject.putProperty(scope, "index", index + 1)
                ScriptableObject.putProperty(scope, "title", chapter.title)
                try {
                    val title = compiled.exec(cx, scope)
                    if (title == null || title is Undefined) chapter else chapter.copy(title = Context.toString(title))
                } catch (_: RhinoException) {
                    chapter
                }
            }
        } finally {
            Context.exit()
        }
    }

    fun eval(script: String, env: JsEnv, followup: String? = null): Any? {
        val cx = Context.enter()
        try {
            cx.optimizationLevel = -1
            cx.languageVersion = Context.VERSION_ES6
            val scope = cx.initStandardObjects()
            // Rhino 的 Packages/java/org 等是懒加载的；脚本里一旦访问
            // org.jsoup 之类的包，内置的 java 会覆盖下面安装的自定义 java，
            // 导致后续 java.ajax 等全部失效。先主动触发初始化。
            ScriptableObject.getProperty(scope, "Packages")
            val variables = mutableMapOf<String, Any?>()
            bind(cx, scope, "result", env.content, variables)
            bind(cx, scope, "src", env.content, variables)
            bind(cx, scope, "baseUrl", env.baseUrl, variables)
            bind(
                cx,
                scope,
                "url",
                env.redirectUrl.takeIf { it.isNotBlank() }
                    ?: env.response?.url?.takeIf { it.isNotBlank() }
                    ?: env.baseUrl,
                variables,
            )
            bind(cx, scope, "key", env.key, variables)
            bind(cx, scope, "page", env.page, variables)
            bind(cx, scope, "title", env.chapter?.title.orEmpty(), variables)
            bind(cx, scope, "book", env.book?.toMap() ?: emptyMap<String, Any?>(), variables)
            bind(cx, scope, "chapter", env.chapter?.toMap() ?: emptyMap<String, Any?>(), variables)
            bind(cx, scope, "isLongClick", env.isLongClick, variables)
            bind(cx, scope, "cache", cacheObject(cx, scope), variables)
            env.response?.let { response ->
                val responseJs = responseObject(cx, scope, response)
                variables["result"] = response
                ScriptableObject.putProperty(scope, "result", responseJs)
                variables["src"] = response
                ScriptableObject.putProperty(scope, "src", responseJs)
            }
            val infoObject = bindInfoMap(cx, scope, env, variables)
            bindSource(cx, scope, env, variables)
            installJava(cx, scope, env, variables)
            bindCookie(cx, scope, env)
            val source = env.source
            if (source.jsLib.isNotBlank()) {
                evaluateJsLib(cx, scope, source.jsLib.trim())
            }
            val value = cx.evaluateString(scope, script, "rule", 1, null)
            if (infoObject != null) {
                copyInfoMap(infoObject, env.infoMap)
            }
            if (followup != null) {
                val followed = cx.evaluateString(scope, followup, "login", 1, null)
                val result = jsToKotlin(cx, followed)
                if (result != null) return result
            }
            return jsToKotlin(cx, value)
        } catch (error: WrappedException) {
            throw error.wrappedException
        } finally {
            Context.exit()
        }
    }

    private fun evaluateJsLib(cx: Context, scope: Scriptable, jsLib: String) {
        // Legado 允许 jsLib 写成 {"名称": "远程 JS 地址"}，按出现顺序加载。
        val remote = if (jsLib.startsWith("{")) {
            runCatching { JSONObject(jsLib) }.getOrNull()
        } else {
            null
        }
        if (remote == null) {
            evaluateLibScript(cx, scope, jsLib, "jsLib")
            return
        }
        for (key in remote.keys()) {
            val url = remote.opt(key)?.toString()?.trim().orEmpty()
            if (!url.startsWith("http://") && !url.startsWith("https://")) continue
            val code = remoteLibs.getOrPut(url) { http.fetchText(url) }
            evaluateLibScript(cx, scope, code, "jsLib-$key")
        }
    }

    private fun evaluateLibScript(
        cx: Context,
        scope: Scriptable,
        code: String,
        name: String,
    ) {
        try {
            cx.evaluateString(scope, code, name, 1, null)
        } catch (error: RhinoException) {
            val line = error.lineNumber()
            val snippet = if (line > 0) {
                code.lineSequence()
                    .drop(line - 1)
                    .firstOrNull()
                    ?.trim()
                    ?.take(160)
            } else {
                null
            }
            val detail = error.details().ifBlank { error.message.orEmpty() }
            throw IllegalStateException(
                buildString {
                    append("书源 $name 第 $line 行加载失败：$detail")
                    if (!snippet.isNullOrBlank()) append(" → $snippet")
                },
                error,
            )
        }
    }

    private fun bindInfoMap(
        cx: Context,
        scope: Scriptable,
        env: JsEnv,
        variables: MutableMap<String, Any?>,
    ): Scriptable? {
        val values = env.infoMap ?: return null
        val result = cx.newObject(scope)
        for ((key, value) in values) {
            ScriptableObject.putProperty(result, key, value)
        }
        fun method(name: String, arity: Int, body: (Array<out Any?>) -> Any?) {
            val function = JsFunction(name, arity, body)
            function.parentScope = scope
            function.prototype = ScriptableObject.getFunctionPrototype(scope)
            ScriptableObject.putProperty(result, name, function)
        }
        method("get", 1) { args ->
            ScriptableObject.getProperty(result, stringArg(args, 0))
        }
        method("put", 2) { args ->
            ScriptableObject.putProperty(result, stringArg(args, 0), args.getOrNull(1))
            null
        }
        method("saveNow", 0) { null }
        variables["infoMap"] = values.toMap()
        ScriptableObject.putProperty(scope, "infoMap", result)
        return result
    }

    private fun copyInfoMap(source: Scriptable, target: MutableMap<String, String>?) {
        if (target == null) return
        for (id in source.ids) {
            val key = Context.toString(id)
            if (key == "get" || key == "put" || key == "saveNow") continue
            val value = ScriptableObject.getProperty(source, key)
            if (value == Scriptable.NOT_FOUND || value == null || value is Undefined) {
                target.remove(key)
            } else {
                target[key] = Context.toString(value)
            }
        }
    }

    private fun bindSource(
        cx: Context,
        scope: Scriptable,
        env: JsEnv,
        variables: MutableMap<String, Any?>,
    ) {
        val result = (toJs(cx, scope, env.source.rawMap()) as? Scriptable)
            ?: cx.newObject(scope)
        fun method(name: String, arity: Int, body: (Array<out Any?>) -> Any?) {
            val function = JsFunction(name, arity, body)
            function.parentScope = scope
            function.prototype = ScriptableObject.getFunctionPrototype(scope)
            ScriptableObject.putProperty(result, name, function)
        }
        method("getVariable", 0) { env.variables?.get(env.source.key).orEmpty() }
        method("putVariable", 1) { args ->
            env.variables?.put(env.source.key, stringArg(args, 0))
            null
        }
        method("setVariable", 1) { args ->
            env.variables?.put(env.source.key, stringArg(args, 0))
            null
        }
        method("getKey", 0) { env.source.key }
        method("getBookSourceName", 0) { env.source.name }
        method("getLoginInfo", 0) {
            env.variables?.get(loginInfoKey(env.source.key))?.ifBlank { null }
        }
        method("getLoginInfoMap", 0) {
            jsonObjectValue(cx, scope, env.variables?.get(loginInfoKey(env.source.key)))
                ?: toJs(cx, scope, emptyMap<String, String>())
        }
        method("getLoginHeader", 0) {
            env.variables?.get(loginHeaderKey(env.source.key))?.ifBlank { null }
        }
        method("getLoginHeaderMap", 0) {
            jsonObjectValue(cx, scope, env.variables?.get(loginHeaderKey(env.source.key)))
        }
        method("putLoginInfo", 1) { args ->
            env.variables?.put(loginInfoKey(env.source.key), stringArg(args, 0))
            true
        }
        method("putLoginInfoMap", 1) { args ->
            val value = jsToKotlin(cx, args.getOrNull(0))
            val text = when (value) {
                is Map<*, *> -> JSONObject(value).toString()
                null -> "{}"
                else -> Context.toString(value)
            }
            env.variables?.put(loginInfoKey(env.source.key), text)
            true
        }
        method("removeLoginInfo", 0) {
            env.variables?.remove(loginInfoKey(env.source.key))
            null
        }
        method("putLoginHeader", 1) { args ->
            val header = loginHeaderText(cx, args.getOrNull(0))
            if (header == null) {
                env.variables?.remove(loginHeaderKey(env.source.key))
            } else {
                env.variables?.put(loginHeaderKey(env.source.key), header)
                http.applyLoginHeaderCookie(env.source.key, header)
            }
            null
        }
        method("removeLoginHeader", 0) {
            env.variables?.remove(loginHeaderKey(env.source.key))
            http.removeCookie(env.source.key)
            null
        }
        method("getJava", 0) { ScriptableObject.getProperty(scope, "java") }
        method("refreshJSLib", 0) { null }
        method("putConcurrent", 1) { null }
        method("getHeaderMap", 0) {
            jsonObjectValue(cx, scope, env.source.rawMap()["header"]?.toString())
        }
        method("refreshExplore", 0) {
            env.onRefreshExplore?.invoke()
            null
        }
        variables["source"] = env.source.rawMap()
        ScriptableObject.putProperty(scope, "source", result)
    }

    private fun loginHeaderText(cx: Context, value: Any?): String? {
        val text = when (val converted = jsToKotlin(cx, value)) {
            null -> return null
            is Map<*, *> -> toJsonObject(converted).toString()
            else -> converted.toString().trim()
        }
        if (!text.startsWith("{")) return null
        val json = runCatching { JSONObject(text) }.getOrNull() ?: return null
        return json.takeIf { it.length() > 0 }?.toString()
    }

    private fun jsonObjectValue(
        cx: Context,
        scope: Scriptable,
        raw: String?,
    ): Any? {
        if (raw.isNullOrBlank()) return null
        return runCatching {
            toJs(cx, scope, jsonValue(JSONObject(raw)))
        }.getOrNull()
    }

    private fun jsonValue(value: Any?): Any? = when (value) {
        is JSONObject -> buildMap {
            for (key in value.keys()) put(key, jsonValue(value.opt(key)))
        }
        is JSONArray -> (0 until value.length()).map { jsonValue(value.opt(it)) }
        JSONObject.NULL -> null
        else -> value
    }

    private fun cacheObject(cx: Context, scope: Scriptable): Scriptable =
        cx.newObject(scope).also { result ->
            fun method(name: String, arity: Int, body: (Array<out Any?>) -> Any?) {
                val function = JsFunction(name, arity, body)
                function.parentScope = scope
                function.prototype = ScriptableObject.getFunctionPrototype(scope)
                ScriptableObject.putProperty(result, name, function)
            }
            method("get", 1) { args -> cache.get(stringArg(args, 0)) }
            method("getFromMemory", 1) { args -> cache.get(stringArg(args, 0)) }
            method("putMemory", 2) { args ->
                cache.put(stringArg(args, 0), stringArg(args, 1), 0L)
                null
            }
            method("put", 3) { args ->
                val ttl = stringArg(args, 2).toLongOrNull() ?: 0L
                cache.put(stringArg(args, 0), stringArg(args, 1), ttl)
                null
            }
            method("remove", 1) { args ->
                cache.remove(stringArg(args, 0))
                null
            }
        }

    private fun bind(
        cx: Context,
        scope: Scriptable,
        name: String,
        value: Any?,
        variables: MutableMap<String, Any?>,
    ) {
        variables[name] = value
        ScriptableObject.putProperty(scope, name, toJs(cx, scope, value))
    }

    private fun installJava(
        cx: Context,
        scope: Scriptable,
        env: JsEnv,
        variables: MutableMap<String, Any?>,
    ) {
        val javaObject = cx.newObject(scope)
        fun fn(name: String, arity: Int, body: (Array<out Any?>) -> Any?) {
            val function = JsFunction(name, arity, body)
            function.parentScope = scope
            function.prototype = ScriptableObject.getFunctionPrototype(scope)
            ScriptableObject.putProperty(javaObject, name, function)
        }
        fn("ajax", 2) { args ->
            fetch(
                env,
                firstUrl(args.getOrNull(0)),
                args.getOrNull(1),
                cx,
                scope,
            )
        }
        fn("get", 2) { args ->
            val url = stringArg(args, 0)
            if (args.size == 1 && ruleVariableName.matches(url)) {
                return@fn when (url) {
                    "bookName" -> env.book?.name.orEmpty()
                    "title" -> env.chapter?.title.orEmpty()
                    else -> variables[url]?.toString().orEmpty()
                }
            }
            val headers = headerMap(args.getOrNull(1))
            val spec = RequestSpec(
                http.resolve(env.source.key, url),
                UrlOption("GET", headers, null, null),
            )
            responseObject(
                cx,
                scope,
                http.fetch(env.source, spec, allowUnsuccessful = true),
            )
        }
        fn("post", 3) { args ->
            val url = stringArg(args, 0)
            val body = stringArg(args, 1)
            val headers = headerMap(args.getOrNull(2))
            val spec = RequestSpec(
                http.resolve(env.source.key, url),
                UrlOption("POST", headers, body, null),
            )
            responseObject(
                cx,
                scope,
                http.fetch(env.source, spec, allowUnsuccessful = true),
            )
        }
        fn("getCookie", 2) { args ->
            // Legado 的签名是 getCookie(tag) / getCookie(tag, key)，
            // 第二个参数为 key 时只取对应 Cookie 值。
            val tag = stringArg(args, 0)
            val key = stringArg(args, 1)
            if (key.isBlank()) {
                http.cookie(env.source.key, tag)
            } else {
                http.cookieKey(env.source.key, tag, key)
            }
        }
        fn("getKey", 3) { args ->
            val first = stringArg(args, 0)
            val second = stringArg(args, 1)
            val third = stringArg(args, 2)
            if (third.isNotBlank()) {
                http.cookieKey(env.source.key, second, third)
            } else {
                http.cookieKey(env.source.key, first, second)
            }
        }
        fn("connect", 2) { args ->
            val request = http.requestSpec(env.source.key, stringArg(args, 0))
            val headers = headerMap(args.getOrNull(1))
            // connect() in Legado accepts a URL followed by the usual
            // `,{ "method": "POST", "body": {...} }` request options. Merge
            // the separate header argument without losing those options.
            val spec = RequestSpec(
                request.url,
                request.option.copy(headers = request.option.headers + headers),
            )
            responseObject(
                cx,
                scope,
                http.fetch(env.source, spec, allowUnsuccessful = true),
            )
        }
        fn("getString", 1) { args ->
            env.analyzer.getString(stringArg(args, 0), env.toRuleContext())
        }
        fn("getStringList", 1) { args ->
            toJs(
                cx,
                scope,
                env.analyzer.getStrings(stringArg(args, 0), env.toRuleContext()),
            )
        }
        fn("getElements", 1) { args ->
            toJs(
                cx,
                scope,
                env.analyzer.getObjects(stringArg(args, 0), env.toRuleContext()),
            )
        }
        fn("put", 2) { args ->
            variables[stringArg(args, 0)] = args.getOrNull(1)
            null
        }
        fn("base64Encode", 1) { args ->
            Base64.encodeToString(stringArg(args, 0).toByteArray(), Base64.NO_WRAP)
        }
        fn("base64Decode", 1) { args ->
            String(Base64.decode(stringArg(args, 0), Base64.DEFAULT))
        }
        fn("hexDecodeToString", 1) { args ->
            stringArg(args, 0).decodeHex().utf8()
        }
        fn("androidId", 0) { _ ->
            (env.variables ?: ephemeralVariables).deviceId(env.source.key)
        }
        fn("md5Encode", 1) { args ->
            MessageDigest.getInstance("MD5")
                .digest(stringArg(args, 0).toByteArray())
                .joinToString("") { "%02x".format(it) }
        }
        fn("urlEncode", 1) { args ->
            URLEncoder.encode(stringArg(args, 0), "UTF-8")
        }
        fn("timeFormat", 2) { args ->
            val time = stringArg(args, 0).toLongOrNull() ?: 0L
            val format = stringArg(args, 1).ifEmpty { "yyyy-MM-dd HH:mm" }
            SimpleDateFormat(format, Locale.getDefault()).format(Date(time))
        }
        fn("htmlFormat", 1) { args -> stringArg(args, 0) }
        fn("log", 1) { args ->
            Log.d("BookSource", stringArg(args, 0))
            null
        }
        fn("toast", 1) { args ->
            val text = stringArg(args, 0)
            if (text.isNotBlank()) env.onToast?.invoke(text)
            null
        }
        fn("longToast", 1) { args ->
            val text = stringArg(args, 0)
            if (text.isNotBlank()) env.onToast?.invoke(text)
            null
        }
        fn("t2s", 1) { args ->
            val text = stringArg(args, 0)
            runCatching {
                android.icu.text.Transliterator
                    .getInstance("Traditional-Simplified")
                    .transliterate(text)
            }.getOrDefault(text)
        }
        fn("s2t", 1) { args ->
            val text = stringArg(args, 0)
            runCatching {
                android.icu.text.Transliterator
                    .getInstance("Simplified-Traditional")
                    .transliterate(text)
            }.getOrDefault(text)
        }
        fn("webView", 3) { args ->
            val html = stringArg(args, 0)
            val url = stringArg(args, 1)
            val js = stringArg(args, 2)
            when {
                html.isNotBlank() -> html
                url.isBlank() -> ""
                js.contains("document.cookie", ignoreCase = true) ->
                    http.cookie(env.source.key, url)
                else -> runCatching { fetch(env, url) }.getOrDefault("")
            }
        }
        fn("startBrowserAwait", 3) { args ->
            val url = if (env.onOpenUrl == null) {
                stringArg(args, 0)
            } else {
                http.resolve(env.source.key, stringArg(args, 0))
            }
            if (env.onOpenUrl != null) {
                if (url.isNotBlank()) env.onOpenUrl.invoke(url)
                // Legado 的 startBrowserAwait 会阻塞到网页登录结束再返回。
                // 应用内网页登录无法同步阻塞，继续执行只会用尚未写入的
                // Cookie 检查登录状态，因此在这里中止脚本。
                if (env.abortAfterOpenUrl) throw BookSourceOpenUrlSignal()
                return@fn responseObject(
                    cx,
                    scope,
                    BookSourceResponse("", "", 0, emptyMap()),
                )
            }
            val response = if (url.isBlank()) {
                null
            } else {
                runCatching {
                    http.fetch(env.source, http.requestSpec(env.source.key, url))
                }.getOrNull()
            }
            responseObject(
                cx,
                scope,
                response ?: BookSourceResponse("", "", 0, emptyMap()),
            )
        }
        fn("startBrowser", 3) { args ->
            val url = http.resolve(env.source.key, stringArg(args, 0))
            if (url.isNotBlank()) env.onOpenUrl?.invoke(url)
            if (env.abortAfterOpenUrl) throw BookSourceOpenUrlSignal()
            null
        }
        fn("openUrl", 1) { args ->
            val url = http.resolve(env.source.key, stringArg(args, 0))
            if (url.isNotBlank()) env.onOpenUrl?.invoke(url)
            if (env.abortAfterOpenUrl) throw BookSourceOpenUrlSignal()
            null
        }
        fn("searchBook", 2) { args ->
            env.onSearchBook?.invoke(stringArg(args, 0))
            true
        }
        fn("refreshExplore", 0) {
            env.onRefreshExplore?.invoke()
            null
        }
        fn("open", 3) { args ->
            val name = stringArg(args, 0)
            val target = stringArg(args, 1)
            when {
                name.equals("login", ignoreCase = true) -> {
                    if (target.startsWith("http://", ignoreCase = true) ||
                        target.startsWith("https://", ignoreCase = true)
                    ) {
                        env.onOpenUrl?.invoke(target)
                    }
                    env.onOpenLogin?.invoke()
                    if (env.abortAfterOpenUrl) throw BookSourceOpenUrlSignal()
                }
                target.startsWith("http://", ignoreCase = true) ||
                    target.startsWith("https://", ignoreCase = true) ->
                    run {
                        env.onOpenUrl?.invoke(target)
                        if (env.abortAfterOpenUrl) throw BookSourceOpenUrlSignal()
                    }
            }
            null
        }
        fn("reLoginView", 0) {
            env.onOpenLogin?.invoke()
            if (env.abortAfterOpenUrl) throw BookSourceOpenUrlSignal()
            null
        }
        ScriptableObject.putProperty(scope, "java", javaObject)
    }

    private fun bindCookie(cx: Context, scope: Scriptable, env: JsEnv) {
        val result = cx.newObject(scope)
        fun method(name: String, arity: Int, body: (Array<out Any?>) -> Any?) {
            val function = JsFunction(name, arity, body)
            function.parentScope = scope
            function.prototype = ScriptableObject.getFunctionPrototype(scope)
            ScriptableObject.putProperty(result, name, function)
        }
        method("getCookie", 1) { args ->
            http.cookie(env.source.key, stringArg(args, 0))
        }
        method("getKey", 2) { args ->
            http.cookieKey(env.source.key, stringArg(args, 0), stringArg(args, 1))
        }
        method("replaceCookie", 2) { args ->
            http.replaceCookie(env.source.key, stringArg(args, 0), stringArg(args, 1))
            null
        }
        method("setCookie", 2) { args ->
            http.setCookie(env.source.key, stringArg(args, 0), stringArg(args, 1))
            null
        }
        method("removeCookie", 1) { args ->
            http.setCookie(env.source.key, stringArg(args, 0), "")
            null
        }
        method("cookieToMap", 1) { args ->
            toJs(cx, scope, parseCookieMap(stringArg(args, 0)))
        }
        method("mapToCookie", 1) { args ->
            val map = jsToKotlin(cx, args.getOrNull(0)) as? Map<*, *> ?: emptyMap<Any?, Any?>()
            map.entries.joinToString("; ") { (key, value) -> "$key=$value" }
        }
        ScriptableObject.putProperty(scope, "cookie", result)
    }

    private class JsCache {
        private data class Entry(val value: String, val expiresAt: Long)

        private val values = ConcurrentHashMap<String, Entry>()

        fun get(key: String): String? {
            val entry = values[key] ?: return null
            if (entry.expiresAt > 0 && entry.expiresAt < System.currentTimeMillis()) {
                values.remove(key)
                return null
            }
            return entry.value
        }

        fun put(key: String, value: String, ttlSeconds: Long) {
            val expiresAt = if (ttlSeconds > 0) {
                System.currentTimeMillis() + ttlSeconds * 1000
            } else {
                0L
            }
            values[key] = Entry(value, expiresAt)
        }

        fun remove(key: String) {
            values.remove(key)
        }
    }

    private fun fetch(
        env: JsEnv,
        rawUrl: String,
        options: Any? = null,
        cx: Context? = null,
        scope: Scriptable? = null,
    ): String {
        val trimmed = rawUrl.trim()
        val resolved = if (
            trimmed.startsWith("http", ignoreCase = true) ||
            trimmed.startsWith("//") ||
            trimmed.startsWith("data:", ignoreCase = true)
        ) {
            trimmed
        } else {
            http.resolve(env.baseUrl, trimmed)
        }
        val optionJson = ajaxOptionJson(options, cx, scope)
        val spec = if (optionJson.isNullOrBlank()) resolved else "$resolved,$optionJson"
        return http.fetch(
            env.source,
            http.requestSpec(env.source.key, spec),
            allowUnsuccessful = true,
        ).text
    }

    /**
     * Legado 的 `java.ajax(url, options)` 第二参数在多数书源里是超时时间，
     * 也有书源传请求选项对象。数字按超时忽略，对象/JSON 字符串当请求选项。
     */
    private fun ajaxOptionJson(
        value: Any?,
        cx: Context?,
        scope: Scriptable?,
    ): String? {
        val raw = if (value is NativeJavaObject) value.unwrap() else value
        return when {
            raw == null ||
                raw is Number ||
                raw is Boolean ||
                raw is Undefined -> null
            raw is String -> raw.trim().takeIf { it.startsWith("{") }
            cx != null && scope != null &&
                (raw is Scriptable || raw is NativeJavaObject) -> {
                val text = NativeJSON.stringify(cx, scope, raw, null, null)
                    ?.toString()
                    ?.trim()
                text?.takeIf { it.startsWith("{") }
            }
            else -> null
        }
    }

    private fun responseObject(
        cx: Context,
        scope: Scriptable,
        response: BookSourceResponse,
    ): JsResponseObject {
        val result = JsResponseObject(response)
        result.parentScope = scope
        result.prototype = ScriptableObject.getObjectPrototype(scope)
        fun property(name: String, value: Any?) {
            ScriptableObject.putProperty(result, name, value)
        }
        fun method(name: String, body: () -> Any?) {
            val function = JsFunction(name, 0) { body() }
            function.parentScope = scope
            function.prototype = ScriptableObject.getFunctionPrototype(scope)
            ScriptableObject.putProperty(result, name, function)
        }
        method("body") { response.text }
        method("html") { response.text }
        // Legado 的 StrResponse 把 url/code/message/isSuccessful 暴露为方法，
        // 书源普遍使用 response.code()、response.url() 这种写法。
        method("url") { response.url }
        method("code") { response.statusCode }
        method("message") { "" }
        method("isSuccessful") { response.statusCode in 200..299 }
        property("statusCode", response.statusCode)
        method("errorBody") { null }
        method("headers") { toJs(cx, scope, response.headers) }
        return result
    }

    private class JsResponseObject(val response: BookSourceResponse) : NativeObject()

    private fun firstUrl(value: Any?): String = when (value) {
        is NativeArray -> if (value.length > 0) {
            Context.toString(value.get(0, value))
        } else {
            ""
        }
        is NativeJavaObject -> firstUrl(value.unwrap())
        is List<*> -> value.firstOrNull()?.toString().orEmpty()
        else -> stringArg(arrayOf(value), 0)
    }

    private fun toJs(cx: Context, scope: Scriptable, value: Any?): Any? = when (value) {
        null -> null
        // Rhino 的 NativeObject 同时实现 java.util.Map，必须优先原样返回，
        // 否则会被按 Map 复制并覆盖 get/put 等方法（cache.get 会变成按属性取值）。
        is Scriptable -> value
        is BookSourceResponse -> responseObject(cx, scope, value)
        is Map<*, *> -> cx.newObject(scope).also { objectValue ->
            for ((key, item) in value) {
                if (key == null) continue
                ScriptableObject.putProperty(
                    objectValue,
                    key.toString(),
                    toJs(cx, scope, item),
                )
            }
            val getter = JsFunction("get", 1) { args ->
                val key = stringArg(args, 0)
                toJs(cx, scope, value[key])
            }
            getter.parentScope = scope
            getter.prototype = ScriptableObject.getFunctionPrototype(scope)
            ScriptableObject.putProperty(objectValue, "get", getter)
        }
        is Element -> Context.javaToJS(value, scope)
        is Iterable<*> -> cx.newArray(
            scope,
            value.map { toJs(cx, scope, it) }.toTypedArray(),
        )
        is Array<*> -> cx.newArray(
            scope,
            value.map { toJs(cx, scope, it) }.toTypedArray(),
        )
        else -> Context.javaToJS(value, scope)
    }

    private fun jsToKotlin(cx: Context, value: Any?): Any? = when (value) {
        null, is Undefined -> null
        is WrappedException -> throw value.wrappedException
        is NativeJavaObject -> value.unwrap()
        is JsResponseObject -> value.response
        is NativeArray -> (0 until value.length.toInt()).map { index ->
            jsToKotlin(cx, value.get(index, value))
        }
        is NativeObject -> buildMap {
            for (id in value.ids) {
                val key = Context.toString(id)
                put(key, jsToKotlin(cx, value.get(key, value)))
            }
        }
        is String, is Number, is Boolean -> value
        is Scriptable -> Context.toString(value)
        else -> Context.toString(value)
    }

    private fun stringArg(args: Array<out Any?>, index: Int): String =
        Context.toString(args.getOrNull(index) ?: "")

    private fun headerMap(value: Any?): Map<String, String> = when (value) {
        null, is Undefined -> emptyMap()
        is String -> {
            val text = value.trim()
            if (text.isEmpty()) {
                emptyMap()
            } else {
                runCatching {
                    val json = JSONObject(text)
                    buildMap {
                        for (key in json.keys()) {
                            val item = json.opt(key)
                            if (item != null && item != JSONObject.NULL) {
                                put(key, item.toString())
                            }
                        }
                    }
                }.getOrElse { emptyMap() }
            }
        }
        else -> stringMap(value)
    }

    private fun stringMap(value: Any?): Map<String, String> {
        if (value is NativeJavaObject) return stringMap(value.unwrap())
        if (value is Map<*, *>) {
            return buildMap {
                for ((key, item) in value) {
                    if (key != null && item != null) put(key.toString(), item.toString())
                }
            }
        }
        if (value !is Scriptable) return emptyMap()
        val result = mutableMapOf<String, String>()
        for (id in value.ids) {
            val key = Context.toString(id)
            val item = ScriptableObject.getProperty(value, key)
            if (item == Scriptable.NOT_FOUND || item == null || item is Undefined) continue
            result[key] = Context.toString(item)
        }
        return result
    }

    private fun parseCookieMap(cookie: String): Map<String, String> {
        if (cookie.isBlank()) return emptyMap()
        return buildMap {
            for (part in cookie.split(';')) {
                val pair = part.trim()
                val separator = pair.indexOf('=')
                if (separator <= 0) continue
                put(
                    pair.substring(0, separator).trim(),
                    pair.substring(separator + 1).trim(),
                )
            }
        }
    }

    private class JsFunction(
        private val name: String,
        private val arity: Int,
        private val body: (Array<out Any?>) -> Any?,
    ) : BaseFunction() {
        override fun getFunctionName(): String = name
        override fun getArity(): Int = arity
        override fun call(
            cx: Context,
            scope: Scriptable,
            thisObj: Scriptable?,
            args: Array<out Any?>,
        ): Any? = try {
            body(args)
        } catch (error: WrappedException) {
            throw error
        } catch (error: RuntimeException) {
            throw error
        } catch (error: Error) {
            throw error
        } catch (error: Throwable) {
            // Rhino 解释器只接受 RuntimeException/Error；受检异常需要先包装，
            // 否则会被强转成 Error 并报 "cannot be cast to java.lang.Error"。
            throw WrappedException(error)
        }
    }
}

/**
 * 网页登录在执行脚本中途打开后用于中止剩余脚本。
 *
 * Legado 的 `java.startBrowserAwait()` 会阻塞到网页关闭，脚本随后才能读取
 * 新 Cookie。应用内网页登录无法阻塞，如果不中止，脚本会立即用旧 Cookie
 * 检查登录状态并弹出“暂时无法检查账号”这类误导提示。
 */
internal class BookSourceOpenUrlSignal :
    RuntimeException(null, null, false, false)

internal data class JsEnv(
    val source: BookSource,
    val analyzer: BookSourceAnalyzer,
    val content: Any?,
    val baseUrl: String,
    val key: String,
    val page: Int,
    val book: BookData? = null,
    val chapter: ChapterData? = null,
    val infoMap: MutableMap<String, String>? = null,
    val variables: BookSourceVariables? = null,
    val onSearchBook: ((String) -> Unit)? = null,
    val onOpenUrl: ((String) -> Unit)? = null,
    val onToast: ((String) -> Unit)? = null,
    val onRefreshExplore: (() -> Unit)? = null,
    val onOpenLogin: (() -> Unit)? = null,
    val abortAfterOpenUrl: Boolean = false,
    val isLongClick: Boolean = false,
    val response: BookSourceResponse? = null,
    val redirectUrl: String = "",
) {
    fun toRuleContext(): RuleContext = RuleContext(
        content = content,
        baseUrl = baseUrl,
        key = key,
        page = page,
        book = book,
        chapter = chapter,
        redirectUrl = redirectUrl,
    )
}

private fun BookData.toMap(): Map<String, Any?> = mapOf(
    "name" to name,
    "author" to author,
    "bookUrl" to bookUrl,
    "coverUrl" to coverUrl,
    "intro" to intro,
    "kind" to kind,
    "lastChapter" to lastChapter,
    "updateTime" to updateTime,
    "tocUrl" to tocUrl,
)

private fun ChapterData.toMap(): Map<String, Any?> = mapOf(
    "title" to title,
    "url" to url,
    "nextUrl" to nextUrl,
    "bookUrl" to bookUrl,
    "baseUrl" to baseUrl,
    "tag" to tag,
    "isVolume" to isVolume,
    "isVip" to isVip,
    "isPay" to isPay,
)
