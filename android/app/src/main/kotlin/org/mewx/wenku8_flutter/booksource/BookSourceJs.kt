package org.mewx.wenku8_flutter.booksource

import android.util.Base64
import android.util.Log
import java.io.File
import java.net.URI
import java.net.URL
import java.net.URLEncoder
import java.nio.charset.Charset
import java.security.MessageDigest
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.SimpleTimeZone
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.Mac
import javax.crypto.spec.IvParameterSpec
import javax.crypto.spec.SecretKeySpec
import okio.ByteString.Companion.decodeHex
import org.json.JSONArray
import org.json.JSONObject
import org.jsoup.nodes.Element
import org.jsoup.select.Elements
import org.mozilla.javascript.BaseFunction
import org.mozilla.javascript.Context
import org.mozilla.javascript.Function
import org.mozilla.javascript.NativeArray
import org.mozilla.javascript.NativeJSON
import org.mozilla.javascript.NativeJavaArray
import org.mozilla.javascript.NativeJavaObject
import org.mozilla.javascript.NativeObject
import org.mozilla.javascript.RhinoException
import org.mozilla.javascript.Scriptable
import org.mozilla.javascript.ScriptableObject
import org.mozilla.javascript.Undefined
import org.mozilla.javascript.WrappedException

internal class BookSourceJs(
    private val http: BookSourceHttp,
    private val host: BookSourceHost? = null,
    private val loginDefaults: ((String) -> Map<String, String>)? = null,
    private val files: BookSourceFiles? = null,
    private val readerConfig: (() -> Map<String, Any?>)? = null,
) {
    private val ruleVariableName = Regex("[A-Za-z_][A-Za-z0-9_]*")
    private val cache = JsCache()
    private val ephemeralVariables = BookSourceVariables(null)
    private val remoteLibs = ConcurrentHashMap<String, String>()
    private val fontCache = ConcurrentHashMap<String, QueryTTF>()
    private val tempVariables = ConcurrentHashMap<String, String>()
    private val resolvingHeaders = ThreadLocal<Boolean>()

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
            // 图片解密时 result 是输入流，src 才是图片地址，不能用 result 覆盖。
            bind(cx, scope, "src", env.contentSrc ?: env.content, variables)
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
            bindEntity(
                cx, scope, "book",
                env.book?.toMap() ?: emptyMap<String, Any?>(),
                env, variables, isChapter = false,
            )
            bindEntity(
                cx, scope, "chapter",
                env.chapter?.toMap() ?: emptyMap<String, Any?>(),
                env, variables, isChapter = true,
            )
            bind(cx, scope, "nextChapterUrl", env.chapter?.nextUrl.orEmpty(), variables)
            bind(cx, scope, "fromBookInfo", env.fromBookInfo, variables)
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

    /**
     * Legado 的 `@webjs:`：把当前页面内容放进后台 WebView 执行脚本，
     * 脚本里的 `result` 是前一段规则的结果。没有宿主时退回 Rhino，
     * 至少保证规则不会直接失效。
     */
    fun evalWebJs(script: String, env: JsEnv, result: Any?): Any? {
        val host = host ?: return eval(script, env.copy(content = result))
        val html = when (val content = env.content) {
            null -> ""
            is String -> content
            is Element -> content.outerHtml()
            is org.jsoup.nodes.Document -> content.outerHtml()
            else -> content.toString()
        }
        if (html.isBlank() && env.baseUrl.isBlank()) {
            return eval(script, env.copy(content = result))
        }
        val pageScript = if (result == null) {
            script
        } else {
            "window.result=${jsLiteral(result)};\n$script"
        }
        val body = runCatching {
            host.loadWebView(
                sourceKey = env.source.key,
                html = html,
                url = env.baseUrl.takeIf { it.startsWith("http", true) }.orEmpty(),
                js = pageScript,
                sourceRegex = "",
                overrideUrlRegex = "",
                cacheFirst = true,
                delayMs = 0,
                headers = evaluatedHeaders(env, env.baseUrl),
            )
        }.getOrNull()
        return body?.takeIf { it.isNotBlank() } ?: eval(script, env.copy(content = result))
    }

    /**
     * Legado 的 `coverDecodeJs` / `imageDecode`：脚本里的 `result` 是图片输入流，
     * `src` 是图片地址，`book` 是当前书籍，返回值是解密后的字节数组。
     * 脚本失败或没有返回字节时保留原图。
     */
    fun decodeImageBytes(
        script: String,
        bytes: ByteArray,
        src: String,
        book: BookData?,
        analyzer: BookSourceAnalyzer,
        source: BookSource,
        variables: BookSourceVariables?,
    ): ByteArray? {
        val stream = java.io.ByteArrayInputStream(bytes)
        val value = runCatching {
            eval(
                script,
                JsEnv(
                    source = source,
                    analyzer = analyzer,
                    content = stream,
                    contentSrc = src,
                    baseUrl = src,
                    key = "",
                    page = 1,
                    book = book,
                    variables = variables,
                ),
            )
        }.getOrNull() ?: return null
        // 部分脚本直接 return result（输入流），这种情况按原图处理。
        val raw = (value as? java.io.InputStream)?.use { it.readBytes() } ?: value
        return byteArrayValue(raw)
    }

    private fun jsLiteral(value: Any?): String = when (value) {
        null -> "null"
        is Number, is Boolean -> value.toString()
        is NativeArray -> JSONArray(
            (0 until value.length.toInt()).map { index -> value.get(index, value)?.toString().orEmpty() },
        ).toString()
        is Iterable<*> -> JSONArray(value.map { it?.toString().orEmpty() }).toString()
        else -> JSONObject.quote(value.toString())
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

    /**
     * 书源级 `header` 可以是 `@js:` / `<js>` 脚本。Legado 每次请求都会
     * 重新执行它，因为脚本常用时间、Cookie、缓存变量生成签名。
     */
    fun evaluatedHeaders(env: JsEnv, url: String): Map<String, String> {
        if (resolvingHeaders.get() == true) return emptyMap()
        val raw = env.source.rawHeader?.trim().orEmpty()
        if (raw.isEmpty()) return emptyMap()
        if (!raw.startsWith("@js:", ignoreCase = true) &&
            !raw.startsWith("<js>", ignoreCase = true)
        ) return headerMap(raw)
        val script = when {
            raw.startsWith("@js:", ignoreCase = true) -> raw.substring(4)
            else -> {
                val end = raw.lastIndexOf("</js>")
                if (end > 4) raw.substring(4, end) else raw.substring(4)
            }
        }.trim()
        if (script.isEmpty()) return emptyMap()
        resolvingHeaders.set(true)
        return try {
            val value = eval(
                script,
                env.copy(
                    content = url,
                    baseUrl = url,
                    response = null,
                    redirectUrl = url,
                ),
            )
            when (value) {
                null -> emptyMap()
                is Map<*, *> -> stringMap(value)
                else -> headerMap(value.toString())
            }
        } catch (error: Throwable) {
            Log.w("BookSource", "请求头规则执行失败：${error.message}", error)
            emptyMap()
        } finally {
            resolvingHeaders.remove()
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
        method("getVariable", 0) {
            tempVariables[env.source.key] ?: env.variables?.get(env.source.key).orEmpty()
        }
        method("getTemporaryVariable", 0) { tempVariables[env.source.key] }
        method("setTemporaryVariable", 1) { args ->
            val value = stringArg(args, 0)
            if (value.isEmpty()) tempVariables.remove(env.source.key)
            else tempVariables[env.source.key] = value
            null
        }
        method("putVariable", 1) { args ->
            val value = stringArg(args, 0)
            if (value.isEmpty()) {
                env.variables?.remove(env.source.key)
            } else {
                env.variables?.put(env.source.key, value)
            }
            null
        }
        method("setVariable", 1) { args ->
            val value = stringArg(args, 0)
            if (value.isEmpty()) {
                env.variables?.remove(env.source.key)
            } else {
                env.variables?.put(env.source.key, value)
            }
            null
        }
        method("put", 2) { args ->
            val key = stringArg(args, 0)
            val value = stringArg(args, 1)
            env.variables?.putSourceValue(env.source.key, key, value)
            value
        }
        method("get", 1) { args ->
            env.variables?.getSourceValue(env.source.key, stringArg(args, 0)).orEmpty()
        }
        method("getKey", 0) { env.source.key }
        method("getTag", 0) { env.source.name }
        method("getSource", 0) { result }
        method("getBookSourceName", 0) { env.source.name }
        method("getBookSourceUrl", 0) { env.source.key }
        method("getBookSourceType", 0) { env.source.type }
        method("getBookSourceComment", 0) {
            env.source.rawMap()["bookSourceComment"]?.toString().orEmpty()
        }
        method("getLoginUiJs", 0) { env.source.loginUi.orEmpty() }
        method("getLoginJs", 0) { loginScript(env.source) }
        method("login", 0) {
            val login = loginScript(env.source)
            if (login.isNullOrBlank()) return@method null
            cx.evaluateString(
                scope,
                "$login\nif(typeof login=='function'){login.apply(this);}else{throw 'Function login not implements!!!'}",
                "source.login",
                1,
                null,
            )
            null
        }
        method("getLoginInfo", 0) {
            env.variables?.get(loginInfoKey(env.source.key))?.ifBlank { null }
        }
        method("getLoginInfoMap", 0) {
            val stored = env.variables?.get(loginInfoKey(env.source.key))
            jsonObjectValue(cx, scope, stored) ?: run {
                val defaults = loginDefaults?.invoke(env.source.key).orEmpty()
                if (defaults.isNotEmpty()) {
                    env.variables?.put(loginInfoKey(env.source.key), JSONObject(defaults).toString())
                }
                toJs(cx, scope, defaults)
            }
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
        method("refreshJSLib", 0) {
            remoteLibs.clear()
            null
        }
        method("putConcurrent", 1) { args ->
            http.rateLimiter.update(env.source.key, stringArg(args, 0))
            null
        }
        method("getHeaderMap", 0) {
            // Legado 的 getHeaderMap 会把登录 Header 一并合并进来。
            val merged = linkedMapOf<String, String>()
            merged.putAll(evaluatedHeaders(env, env.baseUrl))
            merged.putAll(http.loginHeaders(env.source.key))
            toJs(cx, scope, merged)
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
            method("delete", 1) { args ->
                cache.remove(stringArg(args, 0))
                null
            }
            method("deleteMemory", 1) { args ->
                cache.remove(stringArg(args, 0))
                null
            }
            method("putFile", 3) { args ->
                val ttl = stringArg(args, 2).toLongOrNull() ?: 0L
                cache.put(stringArg(args, 0), stringArg(args, 1), ttl)
                null
            }
            method("getFile", 1) { args -> cache.get(stringArg(args, 0)) }
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

    /**
     * Legado 的 `book` / `chapter` 是实体对象，脚本除了读字段还会调用
     * `getVariable/putVariable/deleteVariable`（例如按变量过滤目录、
     * 在章节地址规则里暂存下一页选择器）。
     */
    private fun bindEntity(
        cx: Context,
        scope: Scriptable,
        name: String,
        fields: Map<String, Any?>,
        env: JsEnv,
        variables: MutableMap<String, Any?>,
        isChapter: Boolean,
    ) {
        val target = (toJs(cx, scope, fields) as? Scriptable) ?: cx.newObject(scope)
        fun method(methodName: String, arity: Int, body: (Array<out Any?>) -> Any?) {
            val function = JsFunction(methodName, arity, body)
            function.parentScope = scope
            function.prototype = ScriptableObject.getFunctionPrototype(scope)
            ScriptableObject.putProperty(target, methodName, function)
        }
        val chapter = if (isChapter) env.chapter else null
        method("getVariable", 1) { args ->
            env.variables?.readRule(
                env.source.key,
                env.book,
                chapter,
                stringArg(args, 0),
            ).orEmpty()
        }
        method("putVariable", 2) { args ->
            val value = stringArg(args, 1)
            env.variables?.writeRule(
                env.source.key,
                env.book,
                chapter,
                stringArg(args, 0),
                value,
            )
            // Legado 的 putVariable 返回 Boolean，规则末尾直接调用时会得到 true。
            true
        }
        method("deleteVariable", 1) { args ->
            env.variables?.removeRule(
                env.source.key,
                env.book,
                chapter,
                stringArg(args, 0),
            )
            null
        }
        if (!isChapter) {
            ScriptableObject.putProperty(target, "origin", env.source.key)
            ScriptableObject.putProperty(target, "originName", env.source.name)
            ScriptableObject.putProperty(target, "type", env.source.type)
            ScriptableObject.putProperty(target, "group", 0)
            ScriptableObject.putProperty(target, "canUpdate", true)
        }
        variables[name] = fields
        ScriptableObject.putProperty(scope, name, target)
    }

    private fun installJava(
        cx: Context,
        scope: Scriptable,
        env: JsEnv,
        variables: MutableMap<String, Any?>,
    ) {
        val javaObject = cx.newObject(scope)
        var activeContent = env.content
        fun fn(name: String, arity: Int, body: (Array<out Any?>) -> Any?) {
            val function = JsFunction(name, arity, body)
            function.parentScope = scope
            function.prototype = ScriptableObject.getFunctionPrototype(scope)
            ScriptableObject.putProperty(javaObject, name, function)
        }
        fn("ajax", 2) { args ->
            val timeout = timeoutMillis(args.getOrNull(1))
            try {
                fetch(
                    env,
                    firstUrl(args.getOrNull(0)),
                    args.getOrNull(1),
                    cx,
                    scope,
                    timeout,
                )
            } catch (error: Throwable) {
                // Legado 的 java.ajax 把网络异常作为响应正文返回，脚本里常用
                // result.indexOf('Exception') 判断线路是否可用。
                error.rethrowIfCancelled()
                error.stackTraceToString()
            }
        }
        fn("get", 2) { args ->
            val url = stringArg(args, 0)
            if (args.size <= 1) {
                return@fn (env.variables ?: ephemeralVariables).readRule(env.source.key, env.book, env.chapter, url)
            }
            val headers = headerMap(args.getOrNull(1))
            val spec = RequestSpec(
                http.resolve(env.source.key, url),
                UrlOption("GET", headers, null, null, followRedirects = false),
            )
            responseObject(
                cx,
                scope,
                http.fetch(
                    env.source,
                    withHeaders(env, spec),
                    allowUnsuccessful = true,
                    timeoutMillis = timeoutMillis(args.getOrNull(2)),
                ),
            )
        }
        fn("post", 3) { args ->
            val url = stringArg(args, 0)
            val body = stringArg(args, 1)
            val headers = headerMap(args.getOrNull(2))
            val spec = RequestSpec(
                http.resolve(env.source.key, url),
                UrlOption("POST", headers, body, null, followRedirects = false),
            )
            responseObject(
                cx,
                scope,
                http.fetch(
                    env.source,
                    withHeaders(env, spec),
                    allowUnsuccessful = true,
                    timeoutMillis = timeoutMillis(args.getOrNull(3)),
                ),
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
            val response = try {
                http.fetch(
                    env.source,
                    withHeaders(env, spec),
                    allowUnsuccessful = true,
                    timeoutMillis = timeoutMillis(args.getOrNull(2)),
                )
            } catch (error: Throwable) {
                error.rethrowIfCancelled()
                BookSourceResponse(
                    url = request.url,
                    text = error.stackTraceToString(),
                    statusCode = 0,
                    headers = emptyMap(),
                    requestUrl = request.url,
                    requestMethod = spec.option.method?.uppercase() ?: "GET",
                    requestHeaders = spec.option.headers,
                    requestBody = spec.option.body,
                )
            }
            responseObject(cx, scope, response)
        }
        fn("getString", 2) { args ->
            val target = args.getOrNull(1)
                ?.takeUnless { it == null || it is Undefined }
                ?.let { jsToKotlin(cx, it) }
                ?: activeContent
            env.analyzer.getString(
                stringArg(args, 0),
                env.toRuleContext().copy(content = target),
            )
        }
        fn("getStringList", 2) { args ->
            val target = args.getOrNull(1)
                ?.takeUnless { it == null || it is Undefined }
                ?.let { jsToKotlin(cx, it) }
                ?: activeContent
            toJs(
                cx,
                scope,
                env.analyzer.getStrings(
                    stringArg(args, 0),
                    env.toRuleContext().copy(content = target),
                ),
            )
        }
        fn("getElements", 2) { args ->
            val target = args.getOrNull(1)
                ?.takeUnless { it == null || it is Undefined }
                ?.let { jsToKotlin(cx, it) }
                ?: activeContent
            val values = env.analyzer.getObjects(
                    stringArg(args, 0),
                    env.toRuleContext().copy(content = target),
                )
            toJs(cx, scope, jsElements(values))
        }
        fn("setContent", 1) { args ->
            activeContent = jsToKotlin(cx, args.getOrNull(0))
            // Legado 的 setContent 返回 AnalyzeRule 本身，支持
            // java.setContent(html).getString(rule) 连续调用。
            javaObject
        }
        fn("getElement", 2) { args ->
            val target = args.getOrNull(1)
                ?.takeUnless { it == null || it is Undefined }
                ?.let { jsToKotlin(cx, it) }
                ?: activeContent
            val values = env.analyzer.getObjects(
                    stringArg(args, 0),
                    env.toRuleContext().copy(content = target),
                )
            toJs(cx, scope, values.firstOrNull() as? Element)
        }
        fn("put", 2) { args ->
            val name = stringArg(args, 0)
            val value = Context.toString(args.getOrNull(1) ?: "")
            val target = env.variables ?: ephemeralVariables
            target.writeRule(env.source.key, env.book, env.chapter, name, value)
            value
        }
        fn("base64Encode", 2) { args ->
            val flags = args.getOrNull(1)?.toString()?.toIntOrNull() ?: Base64.NO_WRAP
            Base64.encodeToString(stringArg(args, 0).toByteArray(), flags)
        }
        fn("base64Decode", 2) { args ->
            val decoder = when (val flag = args.getOrNull(1)) {
                is Number -> Charsets.UTF_8 to Base64.decode(stringArg(args, 0), flag.toInt())
                is String -> {
                    val charset = runCatching { Charset.forName(flag) }.getOrDefault(Charsets.UTF_8)
                    charset to Base64.decode(stringArg(args, 0), Base64.DEFAULT)
                }
                else -> Charsets.UTF_8 to Base64.decode(stringArg(args, 0), Base64.DEFAULT)
            }
            String(decoder.second, decoder.first)
        }
        fn("base64DecodeToByteArray", 2) { args ->
            val text = stringArg(args, 0)
            if (text.isBlank()) {
                null
            } else {
                val flags = stringArg(args, 1).toIntOrNull() ?: Base64.DEFAULT
                Base64.decode(text, flags)
            }
        }
        fn("hexDecodeToString", 1) { args ->
            stringArg(args, 0).decodeHex().utf8()
        }
        fn("hexDecodeToByteArray", 1) { args ->
            stringArg(args, 0).decodeHex().toByteArray()
        }
        fn("hexEncodeToString", 1) { args ->
            stringArg(args, 0).toByteArray().joinToString("") { "%02x".format(it) }
        }
        fn("strToBytes", 2) { args ->
            val charset = stringArg(args, 1).ifBlank { "UTF-8" }
            stringArg(args, 0).toByteArray(Charset.forName(charset))
        }
        fn("bytesToStr", 2) { args ->
            val charset = stringArg(args, 1).ifBlank { "UTF-8" }
            String(
                byteArrayValue(args.getOrNull(0)) ?: ByteArray(0),
                Charset.forName(charset),
            )
        }
        fn("androidId", 0) { _ ->
            (env.variables ?: ephemeralVariables).deviceId(env.source.key)
        }
        fn("randomUUID", 0) { _ -> UUID.randomUUID().toString() }
        fn("getWebViewUA", 0) { _ -> BookSourceHttp.DefaultUserAgent }
        fn("getUserAgent", 0) { _ -> BookSourceHttp.DefaultUserAgent }
        fn("getThemeMode", 0) { _ ->
            // Legado 用 0/1 区分日/夜；书源常拿它决定弹窗配色。
            appConfig()["themeMode"]?.toString() ?: "0"
        }
        fn("md5Encode", 1) { args ->
            MessageDigest.getInstance("MD5")
                .digest(stringArg(args, 0).toByteArray())
                .joinToString("") { "%02x".format(it) }
        }
        fn("md5Encode16", 1) { args ->
            val hex = MessageDigest.getInstance("MD5")
                .digest(stringArg(args, 0).toByteArray())
                .joinToString("") { "%02x".format(it) }
            hex.substring(8, 24)
        }
        fn("urlEncode", 1) { args ->
            URLEncoder.encode(stringArg(args, 0), "UTF-8")
        }
        fn("encodeURI", 2) { args ->
            val encoding = stringArg(args, 1).ifBlank { "UTF-8" }
            runCatching { URLEncoder.encode(stringArg(args, 0), encoding) }.getOrDefault("")
        }
        fn("timeFormat", 2) { args ->
            val time = stringArg(args, 0).toLongOrNull() ?: 0L
            val format = stringArg(args, 1).ifEmpty { "yyyy/MM/dd HH:mm" }
            SimpleDateFormat(format, Locale.getDefault()).format(Date(time))
        }
        fn("timeFormatUTC", 3) { args ->
            val time = stringArg(args, 0).toLongOrNull() ?: 0L
            val format = stringArg(args, 1).ifEmpty { "yyyy/MM/dd HH:mm" }
            val offset = stringArg(args, 2).toIntOrNull() ?: 0
            SimpleDateFormat(format, Locale.getDefault()).apply {
                timeZone = SimpleTimeZone(offset * 60 * 60 * 1000, "UTC")
            }.format(Date(time))
        }
        fn("toNumChapter", 1) { args ->
            toNumChapter(stringArg(args, 0))
        }
        fn("toURL", 2) { args ->
            val raw = stringArg(args, 0)
            val base = stringArg(args, 1)
            val value = if (base.isBlank()) {
                http.resolve(env.source.key, raw)
            } else {
                http.resolve(base, raw)
            }
            jsUrl(cx, scope, value)
        }
        fn("digestHex", 2) { args ->
            MessageDigest.getInstance(stringArg(args, 1))
                .digest(stringArg(args, 0).toByteArray())
                .joinToString("") { "%02x".format(it) }
        }
        fn("digestBase64Str", 2) { args ->
            Base64.encodeToString(
                MessageDigest.getInstance(stringArg(args, 1))
                    .digest(stringArg(args, 0).toByteArray()),
                Base64.NO_WRAP,
            )
        }
        fn("HMacHex", 3) { args ->
            hmac(args).joinToString("") { "%02x".format(it) }
        }
        fn("HMacBase64", 3) { args ->
            Base64.encodeToString(hmac(args), Base64.NO_WRAP)
        }
        fn("createSymmetricCrypto", 3) { args ->
            val cipher = BookSourceCipher(
                algorithm = stringArg(args, 0),
                key = byteArrayValue(args.getOrNull(1)),
                iv = byteArrayValue(args.getOrNull(2)),
            )
            Context.javaToJS(cipher, scope)
        }
        fn("createAsymmetricCrypto", 1) { args ->
            Context.javaToJS(BookSourceAsymmetricCrypto(stringArg(args, 0)), scope)
        }
        fn("createSign", 1) { args ->
            Context.javaToJS(BookSourceSign(stringArg(args, 0)), scope)
        }
        fn("aesBase64DecodeToString", 4) { args ->
            cipherString(
                args,
                decrypt = true,
                base64Input = true,
            )
        }
        fn("aesDecodeToString", 4) { args ->
            cipherString(args, decrypt = true, base64Input = false)
        }
        fn("aesDecodeToByteArray", 4) { args ->
            cipher(args).decrypt(stringArg(args, 0))
        }
        fn("aesDecodeArgsBase64Str", 5) { args ->
            BookSourceCipher(
                "AES/${stringArg(args, 2)}/${stringArg(args, 3)}",
                base64Bytes(args, 1),
                base64Bytes(args, 4),
            ).decryptStr(stringArg(args, 0))
        }
        fn("aesBase64DecodeToByteArray", 4) { args ->
            cipher(args).decrypt(stringArg(args, 0))
        }
        fn("aesEncodeToByteArray", 4) { args ->
            cipher(args).encrypt(stringArg(args, 0))
        }
        fn("aesEncodeToString", 4) { args ->
            // Legado 的这个旧接口实现为 decryptStr，保持同样行为。
            cipher(args).decryptStr(stringArg(args, 0))
        }
        fn("aesEncodeToBase64ByteArray", 4) { args ->
            cipher(args).encryptBase64(stringArg(args, 0)).toByteArray()
        }
        fn("aesEncodeToBase64String", 4) { args ->
            cipher(args).encryptBase64(stringArg(args, 0))
        }
        fn("aesEncodeArgsBase64Str", 5) { args ->
            BookSourceCipher(
                "AES/${stringArg(args, 2)}/${stringArg(args, 3)}",
                stringArg(args, 1).toByteArray(),
                stringArg(args, 4).toByteArray(),
            ).encryptBase64(stringArg(args, 0))
        }
        fn("desDecodeToString", 4) { args ->
            cipher(args).decryptStr(stringArg(args, 0))
        }
        fn("desBase64DecodeToString", 4) { args ->
            cipher(args).decryptStr(stringArg(args, 0))
        }
        fn("desEncodeToString", 4) { args ->
            String(cipher(args).encrypt(stringArg(args, 0)), Charsets.UTF_8)
        }
        fn("desEncodeToBase64String", 4) { args ->
            cipherString(args, decrypt = false, base64Input = true)
        }
        fn("tripleDESDecodeStr", 5) { args ->
            BookSourceCipher(
                "DESede/${stringArg(args, 2)}/${stringArg(args, 3)}",
                stringArg(args, 1).toByteArray(),
                stringArg(args, 4).toByteArray(),
            ).decryptStr(stringArg(args, 0))
        }
        fn("tripleDESDecodeArgsBase64Str", 5) { args ->
            BookSourceCipher(
                "DESede/${stringArg(args, 2)}/${stringArg(args, 3)}",
                base64Bytes(args, 1),
                stringArg(args, 4).toByteArray(),
            ).decryptStr(stringArg(args, 0))
        }
        fn("tripleDESEncodeBase64Str", 5) { args ->
            val transformation = "DESede/${stringArg(args, 2)}/${stringArg(args, 3)}"
            BookSourceCipher(
                transformation,
                stringArg(args, 1).toByteArray(),
                stringArg(args, 4).toByteArray(),
            ).encryptBase64(stringArg(args, 0))
        }
        fn("tripleDESEncodeArgsBase64Str", 5) { args ->
            BookSourceCipher(
                "DESede/${stringArg(args, 2)}/${stringArg(args, 3)}",
                base64Bytes(args, 1),
                stringArg(args, 4).toByteArray(),
            ).encryptBase64(stringArg(args, 0))
        }
        fn("head", 2) { args ->
            val headers = headerMap(args.getOrNull(1))
            val spec = RequestSpec(
                http.resolve(env.source.key, stringArg(args, 0)),
                UrlOption("HEAD", headers, null, null, followRedirects = false),
            )
            responseObject(
                cx,
                scope,
                http.fetch(
                    env.source,
                    withHeaders(env, spec),
                    allowUnsuccessful = true,
                    timeoutMillis = timeoutMillis(args.getOrNull(2)),
                ),
            )
        }
        fn("ajaxAll", 2) { args ->
            val urls = stringList(args.getOrNull(0))
            val skipRateLimit = args.getOrNull(1) == true
            val specs = urls.asSequence().map { url ->
                withHeaders(env, http.requestSpec(env.source.key, url))
            }
            toJs(cx, scope, http.fetchAll(env.source, specs, skipRateLimit))
        }
        fun ajaxTest(args: Array<out Any?>): Any? {
            // Legado 的 ajaxTestAll(urlList, timeout[, skipRateLimit])：并发测速，
            // 失败不抛出，而是把负错误码写进 callTime() 供书源判断线路。
            val urls = stringList(args.getOrNull(0))
            val timeout = stringArg(args, 1).toIntOrNull()?.takeIf { it > 0 }?.toLong()
            val skipRateLimit = args.getOrNull(2) == true
            val specs = urls.asSequence().map { url ->
                withHeaders(env, http.requestSpec(env.source.key, url))
            }
            return toJs(
                cx,
                scope,
                http.fetchAll(
                    env.source,
                    specs,
                    skipRateLimit,
                    timeoutMillis = timeout,
                    tolerateErrors = true,
                ),
            )
        }
        fn("ajaxTestAll", 3) { args -> ajaxTest(args) }
        fn("ajaxTest", 3) { args -> ajaxTest(args) }
        fn("htmlFormat", 1) { args -> htmlFormat(stringArg(args, 0)) }
        fn("log", 1) { args ->
            val value = args.getOrNull(0)
            Log.d("BookSource", Context.toString(value ?: ""))
            value
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
        fun loadWebView(
            args: Array<out Any?>,
            sourceRegex: String = "",
            overrideUrlRegex: String = "",
            cacheFirstIndex: Int = 3,
            delayIndex: Int = 4,
        ): String {
            val html = stringArg(args, 0)
            val url = stringArg(args, 1)
            val js = stringArg(args, 2)
            val cacheFirst = cacheFirstIndex >= 0 && args.getOrNull(cacheFirstIndex) == true
            val delay = if (delayIndex >= 0) {
                args.getOrNull(delayIndex)?.toString()?.toLongOrNull() ?: 0L
            } else {
                0L
            }
            if (host != null && (html.isNotBlank() || url.isNotBlank())) {
                return host.loadWebView(
                    sourceKey = env.source.key,
                    html = html,
                    url = if (url.startsWith("http", true)) url
                    else if (url.isNotBlank()) http.resolve(env.source.key, url) else "",
                    js = js,
                    sourceRegex = sourceRegex,
                    overrideUrlRegex = overrideUrlRegex,
                    cacheFirst = cacheFirst,
                    delayMs = delay,
                    headers = evaluatedHeaders(env, url),
                )
            }
            return when {
                html.isNotBlank() -> html
                url.isBlank() -> ""
                js.contains("document.cookie", ignoreCase = true) ->
                    http.cookie(env.source.key, url)
                else -> runCatching { fetch(env, url) }.getOrDefault("")
            }
        }
        fn("webView", 4) { args ->
            loadWebView(args, delayIndex = -1)
        }
        fn("webViewGetSource", 6) { args ->
            loadWebView(
                args,
                sourceRegex = stringArg(args, 3),
                cacheFirstIndex = 4,
                delayIndex = 5,
            )
        }
        fn("webViewGetOverrideUrl", 6) { args ->
            loadWebView(
                args,
                overrideUrlRegex = stringArg(args, 3),
                cacheFirstIndex = 4,
                delayIndex = 5,
            )
        }
        fun startBrowserAwait(args: Array<out Any?>): Any? {
            val rawUrl = stringArg(args, 0)
            val title = stringArg(args, 1)
            val refetch = args.getOrNull(2)?.let { it != false && it.toString() != "false" } ?: true
            val html = stringArg(args, 3)
            if (env.onOpenUrl != null) {
                val url = http.resolve(env.source.key, rawUrl)
                if (url.isNotBlank()) env.onOpenUrl.invoke(url)
                // Legado 的 startBrowserAwait 会阻塞到网页登录结束再返回。
                // 应用内网页登录无法同步阻塞，继续执行只会用尚未写入的
                // Cookie 检查登录状态，因此在这里中止脚本。
                if (env.abortAfterOpenUrl) throw BookSourceOpenUrlSignal()
                return responseObject(
                    cx,
                    scope,
                    BookSourceResponse("", "", 0, emptyMap()),
                )
            }
            if (host != null) {
                if (rawUrl.isBlank() && html.isBlank()) {
                    return responseObject(
                        cx,
                        scope,
                        BookSourceResponse("", "", 0, emptyMap()),
                    )
                }
                val url = http.resolve(env.source.key, rawUrl)
                val browser = host.awaitWebLogin(env.source.key, url, title, refetch)
                    ?: return responseObject(
                        cx,
                        scope,
                        BookSourceResponse("", "", 0, emptyMap()),
                    )
                val fetched = if (refetch && url.isNotBlank()) {
                    runCatching { http.fetch(env.source, withHeaders(env, http.requestSpec(env.source.key, url)), allowUnsuccessful = true) }
                        .getOrNull()
                } else {
                    null
                }
                return responseObject(
                    cx,
                    scope,
                    fetched ?: BookSourceResponse(
                        url = browser.url.ifBlank { url },
                        text = browser.html,
                        statusCode = if (browser.html.isBlank()) 0 else 200,
                        headers = emptyMap(),
                    ),
                )
            }
            val url = if (rawUrl.isBlank()) "" else http.resolve(env.source.key, rawUrl)
            val response = if (url.isBlank()) {
                null
            } else {
                runCatching {
                    http.fetch(
                        env.source,
                        withHeaders(env, http.requestSpec(env.source.key, url)),
                    )
                }.getOrNull()
            }
            return responseObject(
                cx,
                scope,
                response ?: BookSourceResponse("", "", 0, emptyMap()),
            )
        }
        fn("startBrowserAwait", 4) { args -> startBrowserAwait(args) }
        // Sigma 检测脚本会调用这个扩展名；保持为 startBrowserAwait 的同义入口。
        fn("startBrowserAwaitAwait", 4) { args -> startBrowserAwait(args) }
        fn("startBrowser", 3) { args ->
            val rawUrl = stringArg(args, 0)
            val url = http.resolve(env.source.key, rawUrl)
            val html = stringArg(args, 2).ifBlank { null }
            if (env.onOpenUrl != null) {
                if (url.isNotBlank()) env.onOpenUrl.invoke(url)
                if (env.abortAfterOpenUrl) throw BookSourceOpenUrlSignal()
            } else if (url.isNotBlank()) {
                host?.showBrowser(url, stringArg(args, 1), html)
            }
            null
        }
        fn("showBrowser", 4) { args ->
            val url = http.resolve(env.source.key, stringArg(args, 0))
            if (url.isNotBlank()) {
                if (env.onOpenUrl != null) {
                    env.onOpenUrl.invoke(url)
                } else {
                    host?.showBrowser(url, "", stringArg(args, 1).ifBlank { null })
                }
            }
            null
        }
        fn("showReadingBrowser", 3) { args ->
            val url = http.resolve(env.source.key, stringArg(args, 0))
            if (url.isNotBlank()) host?.showReadingBrowser(url, stringArg(args, 1))
            null
        }
        fn("openWeb", 3) { args ->
            val url = http.resolve(env.source.key, stringArg(args, 0))
            if (url.isNotBlank()) host?.showBrowser(url, stringArg(args, 1), null)
            null
        }
        fn("openVideoPlayer", 3) { args ->
            val url = http.resolve(env.source.key, stringArg(args, 0))
            if (url.isNotBlank()) {
                host?.openVideoPlayer(url, stringArg(args, 1), args.getOrNull(2) == true)
            }
            null
        }
        fn("openBook", 2) { args ->
            host?.openBook(stringArg(args, 0), stringArg(args, 1))
            null
        }
        fn("copyText", 1) { args ->
            val text = stringArg(args, 0)
            if (text.isNotBlank()) host?.copyText(text)
            null
        }
        fn("getVerificationCode", 1) { args ->
            val imageUrl = stringArg(args, 0)
            if (imageUrl.isBlank()) return@fn ""
            host?.getVerificationCode(env.source.key, env.source.name, imageUrl) ?: ""
        }
        fun fileStore(): BookSourceFiles = files
            ?: throw IllegalStateException("书源缓存目录不可用")

        fun refetchResponse(jsStr: String, sourceRegex: String): Any? {
            val target = env.response?.requestUrl?.takeIf { it.isNotBlank() }
                ?: env.baseUrl.takeIf { it.isNotBlank() }
                ?: return null
            if (jsStr.isNotBlank() && host != null) {
                val html = host.loadWebView(
                    sourceKey = env.source.key,
                    html = "",
                    url = http.resolve(env.source.key, target),
                    js = jsStr,
                    sourceRegex = sourceRegex,
                    overrideUrlRegex = "",
                    cacheFirst = false,
                    delayMs = 0,
                    headers = (env.headerMap ?: emptyMap()).toMap(),
                )
                return responseObject(
                    cx,
                    scope,
                    BookSourceResponse(
                        url = target,
                        text = html,
                        statusCode = if (html.isBlank()) 0 else 200,
                        headers = emptyMap(),
                        requestUrl = target,
                    ),
                )
            }
            val spec = http.requestSpec(env.source.key, target)
            val headers = spec.option.headers + (env.headerMap ?: emptyMap())
            val response = http.fetch(
                env.source,
                withHeaders(env, spec.copy(option = spec.option.copy(headers = headers))),
                allowUnsuccessful = true,
            )
            return responseObject(cx, scope, response)
        }

        fun downloadFile(url: String, content: String? = null): String {
            if (url.isBlank()) return ""
            val spec = http.requestSpec(env.source.key, url)
            val suffix = spec.option.type
                ?: url.substringBefore('?').substringAfterLast('.', "").takeIf { it.length in 1..12 }
                ?: "bin"
            val bytes = if (content != null) {
                content.trim().decodeHex().toByteArray()
            } else {
                http.fetchFileBytes(env.source, withHeaders(env, spec))
            }
            val store = fileStore()
            val file = store.fileForDownload(url, suffix) ?: return ""
            file.delete()
            file.writeBytes(bytes)
            return store.relative(file)
        }

        fun cacheFile(url: String, saveTime: Int): String {
            val key = "file:$url"
            val cachedPath = cache.get(key)
            if (cachedPath != null) {
                val text = runCatching { fileStore().readText(cachedPath) }.getOrDefault("")
                if (text.isNotEmpty() || fileStore().readBytes(cachedPath) != null) return text
            }
            val path = downloadFile(url)
            if (path.isBlank()) return ""
            cache.put(key, path, saveTime.toLong())
            return fileStore().readText(path)
        }

        fun unArchive(path: String): String {
            if (path.isBlank()) return ""
            val file = fileStore().resolve(path) ?: return ""
            if (!file.isFile) return ""
            val folder = fileStore().tempFolder(file.name) ?: return ""
            return if (BookSourceArchive.extract(file, folder)) {
                fileStore().tempRelative(file.name)
            } else {
                ""
            }
        }

        fun archiveBytes(
            args: Array<out Any?>,
            rarOr7z: Boolean,
        ): ByteArray? {
            val url = stringArg(args, 0)
            val path = stringArg(args, 1)
            if (url.isBlank() || path.isBlank()) return null
            val bytes = if (url.startsWith("http", true)) {
                http.fetchFileBytes(
                    env.source,
                    withHeaders(env, http.requestSpec(env.source.key, url)),
                )
            } else {
                runCatching { url.decodeHex().toByteArray() }.getOrNull() ?: return null
            }
            return BookSourceArchive.entryBytes(bytes, path, rarOr7z)
        }

        fun archiveString(
            args: Array<out Any?>,
            rarOr7z: Boolean,
        ): String {
            val bytes = archiveBytes(args, rarOr7z) ?: return ""
            val charset = stringArg(args, 2).ifBlank { null }
            return runCatching {
                val target = charset?.let { Charset.forName(it) }
                    ?: BookSourceFiles.detectCharset(bytes)
                    ?: Charsets.UTF_8
                String(bytes, target)
            }.getOrDefault("")
        }

        fun queryFont(value: Any?, useCache: Boolean): QueryTTF? {
            val raw = when (value) {
                is NativeJavaObject -> value.unwrap()
                is NativeJavaArray -> value.unwrap()
                else -> value
            }
            val bytes = when (raw) {
                is ByteArray -> raw
                is String -> {
                    if (raw.isBlank()) {
                        null
                    } else if (raw.startsWith("http", true)) {
                        runCatching {
                            http.fetchFileBytes(
                                env.source,
                                withHeaders(env, http.requestSpec(env.source.key, raw)),
                            )
                        }.getOrNull()
                    } else {
                        runCatching { Base64.decode(raw, Base64.DEFAULT) }.getOrNull()
                    }
                }
                else -> null
            } ?: return null
            if (bytes.isEmpty()) return null
            if (!useCache) return QueryTTF(bytes)
            val key = MessageDigest.getInstance("SHA-256")
                .digest(bytes)
                .joinToString("") { "%02x".format(it) }
            return fontCache.getOrPut(key) { QueryTTF(bytes) }
        }

        fun fontArg(value: Any?): QueryTTF? {
            val raw = if (value is NativeJavaObject) value.unwrap() else value
            return raw as? QueryTTF
        }

        fun replaceFont(
            text: String,
            errorFont: QueryTTF?,
            correctFont: QueryTTF?,
            filter: Boolean,
        ): String {
            if (errorFont == null || correctFont == null) return text
            val chars = splitCodePoints(text)
            val output = StringBuilder(text.length)
            for (char in chars) {
                val code = char.codePointAt(0)
                if (errorFont.isBlankUnicode(code)) {
                    output.append(char)
                    continue
                }
                var glyph = errorFont.getGlyfByUnicode(code)
                if (errorFont.getGlyfIdByUnicode(code) == 0) glyph = null
                if (filter && glyph == null) continue
                val fixed = correctFont.getUnicodeByGlyf(glyph)
                if (fixed != 0) {
                    output.appendCodePoint(fixed)
                } else {
                    output.append(char)
                }
            }
            return output.toString()
        }

        fn("downloadFile", 2) { args ->
            val first = stringArg(args, 0)
            val second = stringArg(args, 1)
            if (second.isNotBlank()) {
                // 已废弃的 downloadFile(hexContent, url)
                downloadFile(second, first)
            } else {
                downloadFile(first)
            }
        }
        fn("readFile", 1) { args ->
            runCatching { fileStore().readBytes(stringArg(args, 0)) }.getOrNull()
        }
        fn("readTxtFile", 2) { args ->
            runCatching {
                fileStore().readText(stringArg(args, 0), stringArg(args, 1).ifBlank { null })
            }.getOrDefault("")
        }
        fn("deleteFile", 1) { args ->
            runCatching { fileStore().delete(stringArg(args, 0)) }.getOrDefault(false)
        }
        fn("getFile", 1) { args ->
            runCatching { fileStore().resolve(stringArg(args, 0)) }.getOrNull()
        }
        fn("getTxtInFolder", 1) { args ->
            runCatching { fileStore().textInFolder(stringArg(args, 0)) }.getOrDefault("")
        }
        fn("importScript", 1) { args ->
            val path = stringArg(args, 0)
            val script = if (path.startsWith("http", true)) {
                cacheFile(path, 0)
            } else {
                fileStore().readText(path)
            }
            if (script.isBlank()) {
                throw IllegalStateException("$path 内容获取失败或者为空")
            }
            script
        }
        fn("cacheFile", 2) { args ->
            val saveTime = stringArg(args, 1).toIntOrNull() ?: 0
            cacheFile(stringArg(args, 0), saveTime)
        }
        fn("unzipFile", 1) { args -> unArchive(stringArg(args, 0)) }
        fn("unrarFile", 1) { args -> unArchive(stringArg(args, 0)) }
        fn("un7zFile", 1) { args -> unArchive(stringArg(args, 0)) }
        fn("unArchiveFile", 1) { args -> unArchive(stringArg(args, 0)) }
        fn("getZipByteArrayContent", 2) { args ->
            archiveBytes(args, rarOr7z = false)
        }
        fn("getRarByteArrayContent", 2) { args ->
            archiveBytes(args, rarOr7z = true)
        }
        fn("get7zByteArrayContent", 2) { args ->
            archiveBytes(args, rarOr7z = true)
        }
        fn("getZipStringContent", 3) { args ->
            archiveString(args, rarOr7z = false)
        }
        fn("getRarStringContent", 3) { args ->
            archiveString(args, rarOr7z = true)
        }
        fn("get7zStringContent", 3) { args ->
            archiveString(args, rarOr7z = true)
        }
        fn("queryBase64TTF", 1) { args ->
            queryFont(args.getOrNull(0), useCache = true)
        }
        fn("queryTTF", 2) { args ->
            val useCache = args.getOrNull(1)?.let { it != false && it.toString() != "false" } ?: true
            queryFont(args.getOrNull(0), useCache)
        }
        fn("replaceFont", 4) { args ->
            val text = stringArg(args, 0)
            val errorFont = fontArg(args.getOrNull(1))
            val correctFont = fontArg(args.getOrNull(2))
            val filter = args.getOrNull(3) == true
            replaceFont(text, errorFont, correctFont, filter)
        }
        fn("getReadBookConfig", 0) { JSONObject(appConfig()).toString() }
        fn("getReadBookConfigMap", 0) { toJs(cx, scope, appConfig()) }
        fn("getThemeConfig", 0) { JSONObject(themeConfig()).toString() }
        fn("getThemeConfigMap", 0) { toJs(cx, scope, themeConfig()) }
        fn("getSource", 0) { ScriptableObject.getProperty(scope, "source") }
        fn("getTag", 0) { env.source.name }
        fn("logType", 1) { args ->
            val value = args.getOrNull(0)
            Log.d("BookSource", value?.javaClass?.name ?: "null")
            null
        }
        fn("reUiView", 1) { _ ->
            // 登录表单的刷新由 loginAction 返回的 values 驱动；
            // 这里保留方法本身，避免脚本因方法不存在而中断。
            env.onRefresh?.invoke("login")
            null
        }
        fn("reGetBook", 0) {
            env.onRefresh?.invoke("bookInfo")
            env.onRefresh?.invoke("tocUrl")
            null
        }
        fn("qread", 0) {
            // 书源用 try/catch 探测轻阅读；包装后 Rhino 才能捕获并回退。
            throw WrappedException(IllegalStateException("当前客户端不支持 qread"))
        }
        fn("stoast", 1) { args ->
            val text = stringArg(args, 0)
            if (text.isNotBlank()) env.onToast?.invoke(text)
            null
        }
        fn("openUrl", 2) { args ->
            val url = http.resolve(env.source.key, stringArg(args, 0))
            if (url.isNotBlank()) {
                if (env.onOpenUrl != null) {
                    env.onOpenUrl.invoke(url)
                    if (env.abortAfterOpenUrl) throw BookSourceOpenUrlSignal()
                } else {
                    host?.showBrowser(url, "", null)
                }
            }
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
        fn("refreshTocUrl", 0) {
            env.onRefresh?.invoke("tocUrl")
            null
        }
        fn("refreshBookUrl", 0) {
            env.onRefresh?.invoke("bookUrl")
            env.book?.bookUrl?.takeIf { it.isNotBlank() }
                ?: env.response?.url?.takeIf { it.isNotBlank() }
                ?: env.baseUrl
        }
        fn("refreshBookInfo", 0) {
            env.onRefresh?.invoke("bookInfo")
            null
        }
        fn("refreshBookToc", 0) {
            env.onRefresh?.invoke("bookToc")
            null
        }
        fn("refreshContent", 0) {
            env.onRefresh?.invoke("content")
            null
        }
        fn("initUrl", 0) {
            // 重新执行地址规则在纯 JS 环境无法完全复现；这里恢复当前
            // 请求的原始地址，后续 getStrResponse() 会按它重新请求。
            ScriptableObject.putProperty(
                javaObject,
                "url",
                env.response?.requestUrl?.takeIf { it.isNotBlank() } ?: env.baseUrl,
            )
            null
        }
        fn("getStrResponse", 2) { args ->
            refetchResponse(stringArg(args, 0), stringArg(args, 1))
        }
        fn("getResponse", 2) { args ->
            refetchResponse(stringArg(args, 0), stringArg(args, 1))
        }
        fn("upLoginData", 1) { args ->
            val info = env.infoMap
            val value = jsToKotlin(cx, args.getOrNull(0)) as? Map<*, *>
            if (info != null && value != null) {
                for ((key, item) in value) {
                    val name = key?.toString()?.trim().orEmpty()
                    if (name.isNotEmpty()) info[name] = item?.toString().orEmpty()
                }
            }
            null
        }
        fn("setCookie", 2) { args ->
            http.setCookie(env.source.key, stringArg(args, 0), stringArg(args, 1))
            null
        }
        fn("removeCookie", 1) { args ->
            http.removeCookie(env.source.key, stringArg(args, 0))
            null
        }
        fn("clearCookie", 1) { args ->
            http.removeCookie(env.source.key, stringArg(args, 0))
            host?.clearWebCookies(stringArg(args, 0))
            null
        }
        fn("getHeaderMap", 0) {
            toJs(cx, scope, evaluatedHeaders(env, env.baseUrl))
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
            // Legado 的 reLoginView 是重建 loginUi，不是打开网页登录。
            env.onRefresh?.invoke("login")
            null
        }
        fn("clearTtsCache", 0) { null }
        ScriptableObject.putProperty(
            javaObject,
            "url",
            env.response?.requestUrl?.takeIf { it.isNotBlank() }
                ?: env.baseUrl.takeIf { it.isNotBlank() }
                ?: env.redirectUrl,
        )
        // Legado 的 AnalyzeUrl.key 是搜索关键字，书源常写成 java.key。
        ScriptableObject.putProperty(javaObject, "key", env.key)
        env.headerMap?.let { headers ->
            ScriptableObject.putProperty(javaObject, "headerMap", headerMapObject(cx, scope, headers))
        }
        ScriptableObject.putProperty(
            javaObject,
            "ruleUrl",
            env.response?.url?.takeIf { it.isNotBlank() } ?: env.baseUrl,
        )
        ScriptableObject.putProperty(scope, "java", javaObject)
    }

    /**
     * Legado 的 java.headerMap 是可变的请求头映射，脚本会在 URL 选项的
     * js 里写入 Cookie 等值，再让本次请求使用。这里保持 get/put/remove
     * 与属性读取两种写法。
     */
    private fun headerMapObject(
        cx: Context,
        scope: Scriptable,
        values: MutableMap<String, String>,
    ): Scriptable = cx.newObject(scope).also { result ->
        fun refresh() {
            for ((key, value) in values) ScriptableObject.putProperty(result, key, value)
        }
        fun method(name: String, arity: Int, body: (Array<out Any?>) -> Any?) {
            val function = JsFunction(name, arity, body)
            function.parentScope = scope
            function.prototype = ScriptableObject.getFunctionPrototype(scope)
            ScriptableObject.putProperty(result, name, function)
        }
        refresh()
        method("get", 1) { args ->
            values[stringArg(args, 0)]
        }
        method("put", 2) { args ->
            val key = stringArg(args, 0)
            val value = stringArg(args, 1)
            values[key] = value
            ScriptableObject.putProperty(result, key, value)
            value
        }
        method("remove", 1) { args ->
            val key = stringArg(args, 0)
            values.remove(key)
            ScriptableObject.deleteProperty(result, key)
            null
        }
        method("containsKey", 1) { args ->
            values.containsKey(stringArg(args, 0))
        }
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
        method("setWebCookie", 2) { args ->
            http.setCookie(env.source.key, stringArg(args, 0), stringArg(args, 1))
            null
        }
        method("removeCookie", 1) { args ->
            http.removeCookie(env.source.key, stringArg(args, 0))
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
        timeoutMillis: Long? = null,
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
            withHeaders(env, http.requestSpec(env.source.key, spec)),
            allowUnsuccessful = true,
            timeoutMillis = timeoutMillis,
        ).text
    }

    private fun timeoutMillis(value: Any?): Long? {
        val raw = if (value is NativeJavaObject) value.unwrap() else value
        val number = when (raw) {
            is Number -> raw.toLong()
            is String -> raw.trim().toLongOrNull()
            else -> null
        } ?: return null
        return number.takeIf { it > 0 }
    }

    private fun Throwable.rethrowIfCancelled() {
        if (this is BookSourceOpenUrlSignal ||
            this is InterruptedException ||
            this is java.util.concurrent.CancellationException
        ) {
            throw this
        }
        val text = message.orEmpty()
        if (text.contains("搜索已取消") || text.contains("批量请求已取消")) throw this
    }

    private fun withHeaders(env: JsEnv, spec: RequestSpec): RequestSpec {
        val headers = evaluatedHeaders(env, spec.url)
        if (headers.isEmpty()) return spec
        return spec.copy(
            option = spec.option.copy(
                headers = headers + spec.option.headers,
            ),
        )
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
        fun method(name: String, arity: Int, body: (Array<out Any?>) -> Any?) {
            val function = JsFunction(name, arity, body)
            function.parentScope = scope
            function.prototype = ScriptableObject.getFunctionPrototype(scope)
            ScriptableObject.putProperty(result, name, function)
        }
        method("body") { response.text }
        method("html") { response.text }
        method("bytes") { response.text.toByteArray() }
        method("byteArray") { response.text.toByteArray() }
        // Legado 的 StrResponse 把 url/code/message/isSuccessful 暴露为方法，
        // 书源普遍使用 response.code()、response.url() 这种写法。
        method("url") { response.url }
        method("code") { response.statusCode }
        method("statusCode") { response.statusCode }
        method("statusMessage") { "" }
        method("message") { "" }
        method("isSuccessful") { response.statusCode in 200..299 }
        method("errorBody") { null }
        method("headers") { toJs(cx, scope, response.headers) }
        method("header", 1) { args ->
            val name = stringArg(args, 0)
            response.headers.entries
                .firstOrNull { it.key.equals(name, ignoreCase = true) }
                ?.value
        }
        method("contentType") {
            response.headers.entries
                .firstOrNull { it.key.equals("Content-Type", ignoreCase = true) }
                ?.value
                ?.substringBefore(';')
                ?.trim()
        }
        method("charset") {
            val contentType = response.headers.entries
                .firstOrNull { it.key.equals("Content-Type", ignoreCase = true) }
                ?.value
                .orEmpty()
            val name = contentType.split(';')
                .map { it.trim() }
                .firstOrNull { it.startsWith("charset=", ignoreCase = true) }
                ?.substringAfter('=')
                ?.trim('"', '\'')
                .orEmpty()
            if (name.isEmpty()) null else runCatching { Charset.forName(name).name() }.getOrNull()
        }
        method("callTime") { response.callTimeMs }
        method("raw") { rawResponseObject(cx, scope, response) }
        // 登录脚本常用 java.post(...).cookies().token 直接读取 Set-Cookie。
        method("cookies") { toJs(cx, scope, responseCookies(response.headers)) }
        return result
    }

    /**
     * Legado 的 StrResponse.raw() 暴露 OkHttp Response。书源常用
     * raw().request().url() 把相对搜索地址补成绝对地址，也会读取
     * request().body() 和 raw().headers("Set-Cookie")。
     */
    private fun rawResponseObject(
        cx: Context,
        scope: Scriptable,
        response: BookSourceResponse,
    ): Scriptable {
        val result = cx.newObject(scope)
        fun method(name: String, arity: Int, body: (Array<out Any?>) -> Any?) {
            val function = JsFunction(name, arity, body)
            function.parentScope = scope
            function.prototype = ScriptableObject.getFunctionPrototype(scope)
            ScriptableObject.putProperty(result, name, function)
        }
        method("code", 0) { response.statusCode }
        method("message", 0) { "" }
        method("url", 0) { response.url }
        method("body", 0) { response.text }
        method("toString", 0) { response.url }
        method("headers", 0) { toJs(cx, scope, response.headers) }
        method("headers", 1) { args ->
            val name = stringArg(args, 0)
            val values = response.headers
                .filterKeys { it.equals(name, ignoreCase = true) }
                .values
                .flatMap { it.split('\n') }
                .toTypedArray()
            cx.newArray(scope, values)
        }
        method("request", 0) {
            val request = cx.newObject(scope)
            fun requestMethod(name: String, arity: Int, body: (Array<out Any?>) -> Any?) {
                val function = JsFunction(name, arity, body)
                function.parentScope = scope
                function.prototype = ScriptableObject.getFunctionPrototype(scope)
                ScriptableObject.putProperty(request, name, function)
            }
            requestMethod("url", 0) {
                (response.requestUrl.ifBlank { response.url }).let { uri ->
                    runCatching { URL(uri) }.getOrNull()?.let { Context.javaToJS(it, scope) }
                        ?: uri
                }
            }
            requestMethod("method", 0) { response.requestMethod }
            requestMethod("headers", 0) { toJs(cx, scope, response.requestHeaders) }
            requestMethod("body", 0) {
                val text = response.requestBody ?: return@requestMethod null
                val bodyObject = cx.newObject(scope)
                val writeTo = JsFunction("writeTo", 1) { args ->
                    val buffer = args.getOrNull(0) as? Scriptable
                    if (buffer != null) {
                        val function = ScriptableObject.getProperty(buffer, "writeUtf8") as? Function
                        function?.call(cx, scope, buffer, arrayOf(text))
                    }
                    null
                }
                writeTo.parentScope = scope
                writeTo.prototype = ScriptableObject.getFunctionPrototype(scope)
                ScriptableObject.putProperty(bodyObject, "writeTo", writeTo)
                ScriptableObject.putProperty(bodyObject, "toString", JsFunction("toString", 0) { text }.also {
                    it.parentScope = scope
                    it.prototype = ScriptableObject.getFunctionPrototype(scope)
                })
                bodyObject
            }
            request
        }
        return result
    }

    private fun responseCookies(headers: Map<String, String>): Map<String, String> {
        val result = linkedMapOf<String, String>()
        for ((name, value) in headers) {
            if (!name.equals("set-cookie", ignoreCase = true)) continue
            for (line in value.split('\n', '\r')) {
                val pair = line.substringBefore(';').trim()
                val separator = pair.indexOf('=')
                if (separator > 0) {
                    result[pair.substring(0, separator).trim()] = pair.substring(separator + 1).trim()
                }
            }
        }
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
        // Elements 继承自 ArrayList，若落到 Iterable 分支会被转成 JS 数组，
        // 书源里的 els.size()/els.attr() 会失效；这里保持 jsoup Java 对象语义。
        is Elements -> Context.javaToJS(value, scope)
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

    private fun byteArrayValue(value: Any?): ByteArray? {
        val raw = when (value) {
            null, is Undefined -> return null
            is NativeJavaObject -> value.unwrap()
            is NativeJavaArray -> value.unwrap()
            else -> value
        }
        return when (raw) {
            null -> null
            is ByteArray -> raw
            is Array<*> -> raw.map { Context.toNumber(it).toInt().toByte() }
                .toByteArray()
            is Iterable<*> -> raw.map { Context.toNumber(it).toInt().toByte() }
                .toByteArray()
            is String -> raw.toByteArray()
            else -> Context.toString(raw).toByteArray()
        }
    }

    private fun stringList(value: Any?): List<String> {
        val raw = if (value is NativeJavaObject) value.unwrap() else value
        return when (raw) {
            null, is Undefined -> emptyList()
            is NativeArray -> (0 until raw.length.toInt()).mapNotNull { index ->
                val item = raw.get(index, raw)
                if (item == Scriptable.NOT_FOUND || item == null || item is Undefined) {
                    null
                } else {
                    Context.toString(item).trim().ifEmpty { null }
                }
            }
            is Array<*> -> raw.mapNotNull { it?.toString()?.trim()?.ifEmpty { null } }
            is Iterable<*> -> raw.mapNotNull { it?.toString()?.trim()?.ifEmpty { null } }
            else -> listOfNotNull(Context.toString(raw).trim().ifEmpty { null })
        }
    }

    private fun jsElements(values: List<Any?>): Any {
        val elements = Elements()
        for (value in values) {
            val element = value as? Element ?: return values
            elements.add(element)
        }
        return elements
    }

    private fun hmac(args: Array<out Any?>): ByteArray {
        val algorithm = stringArg(args, 1)
        val key = stringArg(args, 2).toByteArray()
        val mac = Mac.getInstance(algorithm)
        mac.init(SecretKeySpec(key, algorithm))
        return mac.doFinal(stringArg(args, 0).toByteArray())
    }

    private fun cipherString(
        args: Array<out Any?>,
        decrypt: Boolean,
        base64Input: Boolean,
    ): String? {
        val transformation = stringArg(args, 2)
        if (transformation.isBlank()) return null
        val cipher = BookSourceCipher(
            algorithm = transformation,
            key = byteArrayValue(args.getOrNull(1)),
            iv = byteArrayValue(args.getOrNull(3)),
        )
        val data = stringArg(args, 0)
        return if (decrypt) {
            cipher.decryptStr(data)
        } else if (base64Input) {
            cipher.encryptBase64(data)
        } else {
            cipher.encryptStr(data)
        }
    }

    private fun cipher(args: Array<out Any?>): BookSourceCipher = BookSourceCipher(
        algorithm = stringArg(args, 2),
        key = stringArg(args, 1).toByteArray(),
        iv = stringArg(args, 3).toByteArray(),
    )

    private fun base64Bytes(args: Array<out Any?>, index: Int): ByteArray =
        java.util.Base64.getMimeDecoder().decode(stringArg(args, index))

    private fun jsUrl(cx: Context, scope: Scriptable, value: String): Scriptable {
        val uri = runCatching { URI(value) }.getOrNull()
        val scheme = uri?.scheme.orEmpty()
        val host = uri?.host.orEmpty()
        val authority = uri?.rawAuthority.orEmpty()
        val port = uri?.port ?: -1
        val origin = when {
            scheme.isEmpty() || authority.isEmpty() -> ""
            port > 0 -> "$scheme://${host}:$port"
            else -> "$scheme://$host"
        }
        val searchParams = linkedMapOf<String, String>()
        uri?.rawQuery?.split('&')?.forEach { part ->
            if (part.isEmpty()) return@forEach
            val separator = part.indexOf('=')
            val name = if (separator < 0) part else part.substring(0, separator)
            val value = if (separator < 0) "" else part.substring(separator + 1)
            searchParams.putIfAbsent(
                runCatching { java.net.URLDecoder.decode(name, "UTF-8") }.getOrDefault(name),
                runCatching { java.net.URLDecoder.decode(value, "UTF-8") }.getOrDefault(value),
            )
        }
        return cx.newObject(scope).also { result ->
            fun property(name: String, value: Any?) {
                ScriptableObject.putProperty(result, name, value)
            }
            property("href", value)
            property("protocol", if (scheme.isEmpty()) "" else "$scheme:")
            property("host", host)
            property("hostname", host)
            property("hostPort", authority)
            property("port", if (port > 0) port.toString() else "")
            property("origin", origin)
            property("pathname", uri?.rawPath.orEmpty())
            property("search", uri?.rawQuery?.let { "?$it" }.orEmpty())
            property("hash", uri?.rawFragment?.let { "#$it" }.orEmpty())
            property("searchParams", toJs(cx, scope, searchParams))
        }
    }

    private fun toNumChapter(value: String): String {
        val match = ChapterNumberPattern.find(value) ?: return value
        val number = chineseNumberToInt(match.groupValues[2])
        if (number < 0) return value
        return "${match.groupValues[1]}$number${match.groupValues[3]}"
    }

    private fun appConfig(): Map<String, Any?> {
        val provided = runCatching { readerConfig?.invoke() }.getOrNull().orEmpty()
        val night = provided["nightTheme"] as? Boolean
            ?: (provided["isNightTheme"] as? Boolean)
            ?: false
        val background = provided["bgColor"]?.toString()
            ?: provided["backgroundColor"]?.toString()
            ?: if (night) "#1B1B1B" else "#FFFFFF"
        val foreground = provided["textColor"]?.toString()
            ?: provided["textColorStr"]?.toString()
            ?: if (night) "#CCCCCC" else "#262626"
        return buildMap {
            put("nightTheme", night)
            // Legado: 0 跟随系统、1 日间、2 夜间。
            put("themeMode", if (night) "2" else "1")
            put("textSize", 19)
            put("textFont", "")
            put("paragraphIndent", 2)
            put("paragraphSpacing", 12)
            put("lineSpacing", 1.5)
            put("padding", 24)
            put("readStyle", 0)
            put("bgColor", background)
            put("backgroundColor", background)
            put("textColor", foreground)
            put("textColorStr", foreground)
            put("paper", "system")
            put("name", "system")
            putAll(provided)
        }
    }

    private fun themeConfig(): Map<String, Any?> {
        val config = appConfig()
        val night = config["nightTheme"] as? Boolean ?: false
        val background = config["bgColor"]?.toString()
            ?: if (night) "#1B1B1B" else "#FFFFFF"
        val foreground = config["textColor"]?.toString()
            ?: if (night) "#CCCCCC" else "#262626"
        return mapOf(
            "name" to (config["paper"] ?: "system"),
            "dark" to night,
            "isNightTheme" to night,
            "nightTheme" to night,
            "bgColor" to background,
            "backgroundColor" to background,
            "textColor" to foreground,
            "textColorStr" to foreground,
            "accentColor" to (config["accentColor"] ?: foreground),
            "highlightColor" to (config["highlightColor"] ?: (if (night) "#33FFFFFF" else "#1A000000")),
        )
    }

    /**
     * Legado 的 java.htmlFormat 不是简单去标签：保留 img，块级标签转段落，
     * 清理注释和不可见实体，并统一段首缩进。书源常用它把 HTML 正文转成
     * 阅读器可直接显示的文本。
     */
    private fun htmlFormat(html: String): String {
        if (html.isEmpty()) return html
        var text = html
            .replace(Regex("(&nbsp;)+"), " ")
            .replace(Regex("(&ensp;|&emsp;)"), " ")
            .replace(Regex("(&thinsp;|&zwnj;|&zwj;|\u2009|\u200C|\u200D)"), "")
            .replace(
                Regex("</?(?:div|p|br|hr|h\\d|article|dd|dl)[^>]*>", RegexOption.IGNORE_CASE),
                "\n",
            )
            .replace(Regex("<!--[^>]*-->"), "")
            .replace(
                Regex("</?(?!img)[a-zA-Z]+(?=[ >])[^<>]*>", RegexOption.IGNORE_CASE),
                "",
            )
        val indent = "\u3000\u3000"
        text = text.replace(Regex("[\\s\u3000]*\\n+[\\s\u3000]*"), "\n$indent")
        text = text.replace(Regex("^[\\n\\s\u3000]+"), indent)
        text = text.replace(Regex("[\\n\\s\u3000]+$"), "")
        return text
    }

    private fun splitCodePoints(text: String): List<String> {
        if (text.isEmpty()) return emptyList()
        val result = ArrayList<String>(text.length)
        var index = 0
        while (index < text.length) {
            val count = Character.charCount(text.codePointAt(index))
            result.add(text.substring(index, index + count))
            index += count
        }
        return result
    }

    private fun loginScript(source: BookSource): String? {
        val raw = source.loginUrl?.trim().orEmpty()
        if (raw.isEmpty()) return null
        return when {
            raw.startsWith("@js:", ignoreCase = true) -> raw.substring(4)
            raw.startsWith("<js>", ignoreCase = true) -> {
                val end = raw.lastIndexOf("</js>")
                if (end > 4) raw.substring(4, end) else raw.substring(4)
            }
            else -> raw
        }
    }

    private fun chineseNumberToInt(input: String): Int {
        val text = input.replace(Regex("\\s+"), "")
        if (text.isEmpty()) return -1
        text.toIntOrNull()?.let { return it }
        var result = 0
        var tmp = 0
        var billion = 0
        for ((index, char) in text.withIndex()) {
            val number = ChineseNumbers[char] ?: return -1
            when {
                number == 100_000_000 -> {
                    result += tmp
                    result *= number
                    billion = billion * 100_000_000 + result
                    result = 0
                    tmp = 0
                }
                number == 10_000 -> {
                    result += tmp
                    result *= number
                    tmp = 0
                }
                number >= 10 -> {
                    if (tmp == 0) tmp = 1
                    result += number * tmp
                    tmp = 0
                }
                else -> {
                    tmp = if (index >= 2 &&
                        index == text.lastIndex &&
                        (ChineseNumbers[text[index - 1]] ?: 0) > 10
                    ) {
                        number * (ChineseNumbers[text[index - 1]] ?: 1) / 10
                    } else {
                        tmp * 10 + number
                    }
                }
            }
        }
        return result + tmp + billion
    }

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

    private companion object {
        private val ChapterNumberPattern = Regex("(第)(.+?)(章)")
        private val ChineseNumbers = mapOf(
            '〇' to 0, '零' to 0, '一' to 1, '二' to 2, '两' to 2, '三' to 3,
            '四' to 4, '五' to 5, '六' to 6, '七' to 7, '八' to 8, '九' to 9,
            '壹' to 1, '贰' to 2, '叁' to 3, '肆' to 4, '伍' to 5, '陆' to 6,
            '柒' to 7, '捌' to 8, '玖' to 9,
            '十' to 10, '拾' to 10, '百' to 100, '佰' to 100, '千' to 1000,
            '仟' to 1000, '万' to 10_000, '萬' to 10_000, '亿' to 100_000_000,
            '億' to 100_000_000,
        )
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
    val onRefresh: ((String) -> Unit)? = null,
    val onOpenLogin: (() -> Unit)? = null,
    val abortAfterOpenUrl: Boolean = false,
    val isLongClick: Boolean = false,
    val response: BookSourceResponse? = null,
    val redirectUrl: String = "",
    val headerMap: MutableMap<String, String>? = null,
    val fromBookInfo: Boolean = false,
    /** 脚本里 `src` 的独立取值；为空时沿用 content（Legado 的普通规则语义）。 */
    val contentSrc: String? = null,
) {
    fun toRuleContext(): RuleContext = RuleContext(
        content = content,
        baseUrl = baseUrl,
        key = key,
        page = page,
        book = book,
        chapter = chapter,
        redirectUrl = redirectUrl,
        fromBookInfo = fromBookInfo,
    )
}

/**
 * Legado 的 `java.createSymmetricCrypto(...)` 返回对象。这里保持同名方法和
 * 默认转换规则，覆盖 AES/DES/DESede 的 Hex、Base64 与 UTF-8 往返。
 */
internal class BookSourceCipher(
    algorithm: String,
    key: ByteArray?,
    private var iv: ByteArray? = null,
) {
    private val transformation = if (algorithm.contains('/')) {
        algorithm
    } else {
        "$algorithm/ECB/PKCS5Padding"
    }
    private val keyAlgorithm = algorithm.substringBefore('/')
    private val secretKey = key?.let {
        SecretKeySpec(normalizeKey(it), keyAlgorithm)
    } ?: KeyGenerator.getInstance(keyAlgorithm).generateKey()

    fun setIv(value: ByteArray): BookSourceCipher {
        iv = value.copyOf()
        return this
    }

    fun encrypt(data: ByteArray): ByteArray = cipher(Cipher.ENCRYPT_MODE).doFinal(data)

    fun encrypt(data: String): ByteArray = encrypt(data.toByteArray())

    fun encryptBase64(data: ByteArray): String =
        java.util.Base64.getEncoder().encodeToString(encrypt(data))

    fun encryptBase64(data: String): String = encryptBase64(data.toByteArray())

    fun encryptHex(data: ByteArray): String = encrypt(data).toHex()

    fun encryptHex(data: String): String = encryptHex(data.toByteArray())

    fun encryptStr(data: ByteArray): String = String(encrypt(data), Charsets.UTF_8)

    fun encryptStr(data: String): String = encryptStr(data.toByteArray())

    fun decrypt(data: ByteArray): ByteArray = cipher(Cipher.DECRYPT_MODE).doFinal(data)

    fun decrypt(data: String): ByteArray {
        val bytes = if (HexPattern.matches(data) && data.length % 2 == 0) {
            data.decodeHex().toByteArray()
        } else {
            // minSdk 26 起可直接使用 JDK 实现，避免单测环境缺少 android.util.Base64。
            java.util.Base64.getMimeDecoder().decode(data)
        }
        return decrypt(bytes)
    }

    fun decryptStr(data: ByteArray): String = String(decrypt(data), Charsets.UTF_8)

    fun decryptStr(data: String): String = String(decrypt(data), Charsets.UTF_8)

    fun decryptHex(data: String): ByteArray =
        decrypt(data.decodeHex().toByteArray())

    fun decryptBase64(data: String): ByteArray =
        decrypt(java.util.Base64.getMimeDecoder().decode(data))

    private fun cipher(mode: Int): Cipher = Cipher.getInstance(transformation).apply {
        // 注意：Cipher 自身有 getIV() 合成的 iv 属性，这里必须显式取外层字段，
        // 否则会读到尚未初始化的 Cipher.iv（null），导致解密缺少 IV。
        val currentIv = this@BookSourceCipher.iv
        if (currentIv == null || transformation.contains("/ECB/", ignoreCase = true)) {
            init(mode, secretKey)
        } else {
            init(mode, secretKey, IvParameterSpec(currentIv))
        }
    }

    private fun normalizeKey(value: ByteArray): ByteArray = when {
        keyAlgorithm.equals("DES", ignoreCase = true) && value.size > 8 -> value.copyOf(8)
        keyAlgorithm.equals("DESede", ignoreCase = true) && value.size > 24 -> value.copyOf(24)
        else -> value
    }

    private fun ByteArray.toHex(): String =
        joinToString("") { "%02x".format(it) }

    private companion object {
        private val HexPattern = Regex("[0-9a-fA-F]+")
    }
}

private fun BookData.toMap(): Map<String, Any?> = mapOf(
    "name" to name,
    "author" to author,
    "bookUrl" to bookUrl,
    "coverUrl" to coverUrl,
    "intro" to intro,
    "kind" to kind,
    "lastChapter" to lastChapter,
    "latestChapterTitle" to lastChapter,
    "wordCount" to wordCount,
    "updateTime" to updateTime,
    "tocUrl" to tocUrl,
    "durChapterTitle" to durChapterTitle,
    "durChapterIndex" to durChapterIndex,
)

private fun ChapterData.toMap(): Map<String, Any?> = mapOf(
    "index" to index,
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
