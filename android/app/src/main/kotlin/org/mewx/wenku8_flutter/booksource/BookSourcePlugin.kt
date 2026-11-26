package org.mewx.wenku8_flutter.booksource

import android.app.Activity
import android.app.Dialog
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.text.InputType
import android.util.Log
import android.view.Gravity
import android.view.ViewGroup
import android.widget.Button
import android.widget.EditText
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.io.IOException
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.mozilla.javascript.RhinoException
import org.json.JSONObject
import org.mewx.wenku8_flutter.WebLoginActivity
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull

class BookSourcePlugin :
    FlutterPlugin,
    ActivityAware,
    PluginRegistry.ActivityResultListener,
    BookSourceHost {
    private var channel: MethodChannel? = null
    private var engine: BookSourceEngine? = null
    private var executor: ExecutorService? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var appContext: Context? = null
    private var pendingWebLogin: PendingWebLogin? = null
    private var pendingHostLogin: PendingHostLogin? = null
    private val main = Handler(Looper.getMainLooper())

    private data class PendingWebLogin(
        val sourceKey: String,
        val result: MethodChannel.Result,
        var config: WebLoginConfig? = null,
    )

    private data class PendingHostLogin(
        val sourceKey: String,
        val url: String,
        val config: WebLoginConfig,
        val latch: CountDownLatch,
        var completedUrl: String? = null,
        var html: String = "",
        var canceled: Boolean = true,
    )

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        val bookSourceEngine = BookSourceEngine(
            variables = BookSourceVariables(binding.applicationContext),
            host = this,
            cacheRoot = File(binding.applicationContext.cacheDir, "book_sources"),
            readerConfig = { flutterReaderConfig() },
        )
        // Search fans out over the whole source library. A small pool makes a
        // slow source hold every later request for its full HTTP timeout.
        val worker = Executors.newFixedThreadPool(24)
        engine = bookSourceEngine
        executor = worker
        channel = MethodChannel(binding.binaryMessenger, ChannelName).also {
            it.setMethodCallHandler { call, result ->
                handle(bookSourceEngine, worker, call, result)
            }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        pendingWebLogin?.result?.error("NO_ENGINE", "书源引擎已关闭", null)
        pendingWebLogin = null
        pendingHostLogin?.canceled = true
        pendingHostLogin?.latch?.countDown()
        pendingHostLogin = null
        detachActivity(keepPending = false)
        channel?.setMethodCallHandler(null)
        channel = null
        engine = null
        appContext = null
        executor?.shutdownNow()
        executor = null
    }

    private fun handle(
        engine: BookSourceEngine,
        worker: ExecutorService,
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val arguments = call.arguments as? Map<*, *> ?: emptyMap<Any?, Any?>()
        try {
            when (call.method) {
                "available" -> result.success(engine.available())
                "upsertSource" -> {
                    engine.upsert(arguments["source"])
                    result.success(null)
                }
                "removeSource" -> {
                    engine.remove(stringArg(arguments, "sourceKey"))
                    result.success(null)
                }
                "cancelSearches" -> {
                    engine.cancelSearches()
                    result.success(null)
                }
                "search" -> runAsync(worker, result) {
                    engine.search(
                        sourceKey = stringArg(arguments, "sourceKey"),
                        keyword = stringArg(arguments, "keyword"),
                        page = intArg(arguments, "page", 1),
                    )
                }
                "exploreKinds" -> runAsync(worker, result) {
                    engine.exploreKinds(
                        sourceKey = stringArg(arguments, "sourceKey"),
                        values = stringArgs(arguments, "values"),
                    )
                }
                "explore" -> runAsync(worker, result) {
                    engine.explore(
                        sourceKey = stringArg(arguments, "sourceKey"),
                        url = stringArg(arguments, "url"),
                        page = intArg(arguments, "page", 1),
                        keyword = stringArg(arguments, "keyword"),
                        values = stringArgs(arguments, "values"),
                    )
                }
                "exploreAction" -> runAsync(worker, result) {
                    engine.exploreAction(
                        sourceKey = stringArg(arguments, "sourceKey"),
                        script = stringArg(arguments, "action"),
                        values = stringArgs(arguments, "values"),
                    )
                }
                "detail" -> runAsync(worker, result) {
                    engine.detail(
                        metadata = bookMetadata(arguments),
                        sourceKey = stringArg(arguments, "sourceKey"),
                        bookUrl = stringArg(arguments, "bookUrl"),
                    )
                }
                "chapters" -> runAsync(worker, result) {
                    engine.chapters(
                        metadata = bookMetadata(arguments),
                        sourceKey = stringArg(arguments, "sourceKey"),
                        bookUrl = stringArg(arguments, "bookUrl"),
                        tocUrl = stringArg(arguments, "tocUrl").ifBlank { null },
                    )
                }
                "content" -> runAsync(worker, result) {
                    engine.content(
                        metadata = bookMetadata(arguments),
                        sourceKey = stringArg(arguments, "sourceKey"),
                        bookUrl = stringArg(arguments, "bookUrl"),
                        chapterUrl = stringArg(arguments, "chapterUrl"),
                        nextChapterUrl = stringArg(arguments, "nextChapterUrl")
                            .ifBlank { null },
                        chapterTitle = stringArg(arguments, "chapterTitle")
                            .ifBlank { null },
                        chapterIndex = (arguments["chapterIndex"] as? Number)?.toInt() ?: 0,
                    )
                }
                "fetchImage" -> runAsync(worker, result) {
                    engine.image(
                        sourceKey = stringArg(arguments, "sourceKey"),
                        url = stringArg(arguments, "url"),
                        cover = arguments["cover"] as? Boolean ?: false,
                        bookUrl = stringArg(arguments, "bookUrl"),
                    )
                }
                "loginInfo" -> runAsync(worker, result) {
                    engine.loginInfo(stringArg(arguments, "sourceKey"))
                }
                "login" -> runAsync(worker, result) {
                    engine.login(
                        sourceKey = stringArg(arguments, "sourceKey"),
                        values = stringArgs(arguments, "values"),
                    )
                }
                "loginAction" -> runAsync(worker, result) {
                    engine.loginAction(
                        sourceKey = stringArg(arguments, "sourceKey"),
                        action = stringArg(arguments, "action"),
                        values = stringArgs(arguments, "values"),
                    )
                }
                "logout" -> runAsync(worker, result) {
                    engine.logout(stringArg(arguments, "sourceKey"))
                }
                "webLogin" -> startWebLogin(engine, arguments, result)
                "checkLogin" -> runAsync(worker, result) {
                    engine.checkLogin(stringArg(arguments, "sourceKey"))
                }
                "review" -> runAsync(worker, result) {
                    engine.review(
                        sourceKey = stringArg(arguments, "sourceKey"),
                        bookUrl = stringArg(arguments, "bookUrl"),
                        chapterUrl = stringArg(arguments, "chapterUrl"),
                        ruleValue = (arguments["rule"] as? Map<*, *>)
                            ?.entries
                            ?.associate { it.key.toString() to it.value },
                    )
                }
                else -> result.notImplemented()
            }
        } catch (error: Throwable) {
            Log.e("WenkuBookSource", "${call.method} failed: ${message(error)}", error)
            result.error("BOOK_SOURCE_ERROR", message(error), null)
        }
    }

    private fun startWebLogin(
        engine: BookSourceEngine,
        arguments: Map<*, *>,
        result: MethodChannel.Result,
    ) {
        val activity = activityBinding?.activity
        if (activity == null) {
            result.error("NO_ACTIVITY", "请在文库页面执行网页登录", null)
            return
        }
        if (pendingWebLogin != null) {
            result.error("WEB_LOGIN_BUSY", "已有网页登录正在进行", null)
            return
        }
        val sourceKey = stringArg(arguments, "sourceKey")
        val worker = executor
        if (worker == null) {
            result.error("NO_ENGINE", "书源引擎不可用", null)
            return
        }
        val request = PendingWebLogin(sourceKey, result)
        pendingWebLogin = request
        // loginUrl 可能是 @js:，脚本里可能发网络请求，不能在主线程解析。
        worker.execute {
            val config = try {
                engine.webLoginConfig(
                    sourceKey,
                    stringArg(arguments, "url").ifBlank { null },
                )
            } catch (error: Throwable) {
                main.post {
                    if (pendingWebLogin === request) {
                        pendingWebLogin = null
                        result.error("BOOK_SOURCE_ERROR", message(error), null)
                    }
                }
                return@execute
            }
            main.post {
                if (pendingWebLogin !== request) return@post
                val current = activityBinding?.activity
                if (current == null || current.isFinishing || current.isDestroyed) {
                    pendingWebLogin = null
                    result.error("NO_ACTIVITY", "请在文库页面执行网页登录", null)
                    return@post
                }
                request.config = config
                val intent = Intent(current, WebLoginActivity::class.java).apply {
                    putExtra(WebLoginActivity.EXTRA_URL, config.url)
                    putExtra(WebLoginActivity.EXTRA_TITLE, config.title)
                    putStringArrayListExtra(WebLoginActivity.EXTRA_COOKIE_TARGETS, ArrayList(config.cookieTargets.map { it.toString() }))
                    putStringArrayListExtra(WebLoginActivity.EXTRA_COOKIES, ArrayList(config.cookies))
                    putExtra(WebLoginActivity.EXTRA_USER_AGENT, config.headers["user-agent"])
                    putExtra(WebLoginActivity.EXTRA_HEADERS, HashMap(config.headers))
                }
                try {
                    current.startActivityForResult(intent, WebLoginRequestCode)
                } catch (error: Throwable) {
                    pendingWebLogin = null
                    result.error("BOOK_SOURCE_ERROR", message(error), null)
                }
            }
        }
    }

    override fun onActivityResult(
        requestCode: Int,
        resultCode: Int,
        data: Intent?,
    ): Boolean {
        if (requestCode == HostLoginRequestCode) {
            val pending = pendingHostLogin ?: return true
            pendingHostLogin = null
            if (resultCode != Activity.RESULT_OK) {
                pending.canceled = true
                pending.latch.countDown()
                return true
            }
            val engine = engine
            if (engine == null) {
                pending.canceled = true
                pending.latch.countDown()
                return true
            }
            try {
                engine.importWebLoginCookie(
                    pending.sourceKey,
                    pending.config,
                    data?.getStringArrayListExtra(WebLoginActivity.EXTRA_COOKIES_RESULT).orEmpty(),
                    scoped = data?.getBooleanExtra(WebLoginActivity.EXTRA_SCOPED, false) == true,
                    completedUrl = data?.getStringExtra(WebLoginActivity.EXTRA_COMPLETED_URL),
                    cookieUrls = data?.getStringArrayListExtra(
                        WebLoginActivity.EXTRA_COOKIE_TARGETS_RESULT,
                    ),
                )
                pending.completedUrl = data?.getStringExtra(WebLoginActivity.EXTRA_COMPLETED_URL)
                    ?.takeIf { it.isNotBlank() }
                    ?: pending.url
                pending.html = data?.getStringExtra(WebLoginActivity.EXTRA_HTML_RESULT).orEmpty()
                pending.canceled = false
            } catch (error: Throwable) {
                Log.e("WenkuBookSource", "网页验证结果导入失败", error)
                pending.canceled = true
            } finally {
                pending.latch.countDown()
            }
            return true
        }
        if (requestCode != WebLoginRequestCode) return false
        val pending = pendingWebLogin ?: return true
        pendingWebLogin = null
        if (resultCode != Activity.RESULT_OK) {
            pending.result.success(null)
            return true
        }
        val engine = engine
        if (engine == null) {
            pending.result.error("NO_ENGINE", "书源引擎不可用", null)
            return true
        }
        try {
            pending.result.success(
                engine.importWebLoginCookie(pending.sourceKey, checkNotNull(pending.config),
                    checkNotNull(data?.getStringArrayListExtra(WebLoginActivity.EXTRA_COOKIES_RESULT)),
                    scoped = data.getBooleanExtra(WebLoginActivity.EXTRA_SCOPED, false),
                    completedUrl = data.getStringExtra(WebLoginActivity.EXTRA_COMPLETED_URL),
                    cookieUrls = data.getStringArrayListExtra(
                        WebLoginActivity.EXTRA_COOKIE_TARGETS_RESULT,
                    ),
                ),
            )
        } catch (error: Throwable) {
            pending.result.error("BOOK_SOURCE_ERROR", message(error), null)
        }
        return true
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivity() {
        detachActivity(keepPending = false)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        detachActivity(keepPending = true)
    }

    override fun onReattachedToActivityForConfigChanges(
        binding: ActivityPluginBinding,
    ) {
        onAttachedToActivity(binding)
    }

    private fun detachActivity(keepPending: Boolean) {
        activityBinding?.removeActivityResultListener(this)
        activityBinding = null
        if (!keepPending) {
            pendingWebLogin?.result?.error(
                "NO_ACTIVITY",
                "网页登录已取消",
                null,
            )
            pendingWebLogin = null
            pendingHostLogin?.canceled = true
            pendingHostLogin?.latch?.countDown()
            pendingHostLogin = null
        }
    }

    override fun copyText(text: String) {
        if (text.isBlank()) return
        main.post {
            val manager = getContext()?.getSystemService(Context.CLIPBOARD_SERVICE)
                as? ClipboardManager ?: return@post
            manager.setPrimaryClip(ClipData.newPlainText("书源", text))
        }
    }

    override fun getVerificationCode(
        sourceKey: String,
        sourceName: String,
        imageUrl: String,
    ): String {
        check(Looper.myLooper() != Looper.getMainLooper()) {
            "验证码弹窗不能在主线程等待"
        }
        val activity = activityBinding?.activity ?: return ""
        val bytes = engine?.verificationImage(sourceKey, imageUrl)
        val latch = CountDownLatch(1)
        val answer = arrayOf("")
        main.post {
            val dialog = Dialog(activity)
            val root = LinearLayout(activity).apply {
                orientation = LinearLayout.VERTICAL
                setPadding(dp(activity, 20), dp(activity, 18), dp(activity, 20), dp(activity, 14))
            }
            root.addView(TextView(activity).apply {
                text = if (sourceName.isBlank()) "输入验证码" else "$sourceName · 验证码"
                textSize = 17f
                gravity = Gravity.CENTER_HORIZONTAL
                setPadding(0, 0, 0, dp(activity, 12))
            })
            val bitmap = bytes?.let { BitmapFactory.decodeByteArray(it, 0, it.size) }
            if (bitmap != null) {
                root.addView(ImageView(activity).apply {
                    setImageBitmap(bitmap)
                    adjustViewBounds = true
                    scaleType = ImageView.ScaleType.FIT_CENTER
                    layoutParams = LinearLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT,
                        dp(activity, 130),
                    )
                })
            } else {
                root.addView(TextView(activity).apply {
                    text = "验证码图片加载失败，请检查书源网络"
                    textSize = 13f
                    gravity = Gravity.CENTER
                    setPadding(0, dp(activity, 12), 0, dp(activity, 12))
                })
            }
            val input = EditText(activity).apply {
                hint = "请输入图中字符"
                inputType = InputType.TYPE_CLASS_TEXT
                setSingleLine(true)
                setPadding(dp(activity, 12), dp(activity, 8), dp(activity, 12), dp(activity, 8))
            }
            root.addView(input, LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ).apply { topMargin = dp(activity, 10) })
            val actions = LinearLayout(activity).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.END
                setPadding(0, dp(activity, 10), 0, 0)
            }
            val cancel = Button(activity).apply {
                text = "取消"
                setOnClickListener {
                    dialog.dismiss()
                    latch.countDown()
                }
            }
            val confirm = Button(activity).apply {
                text = "确定"
                setOnClickListener {
                    answer[0] = input.text?.toString()?.trim().orEmpty()
                    dialog.dismiss()
                    latch.countDown()
                }
            }
            actions.addView(cancel)
            actions.addView(confirm)
            root.addView(actions)
            dialog.setOnCancelListener {
                latch.countDown()
            }
            dialog.setContentView(root)
            runCatching { dialog.show() }.onFailure { latch.countDown() }
        }
        latch.await(10, TimeUnit.MINUTES)
        return answer[0]
    }

    override fun awaitWebLogin(
        sourceKey: String,
        url: String,
        title: String,
        refetchAfterSuccess: Boolean,
    ): BookSourceBrowserResult? {
        check(Looper.myLooper() != Looper.getMainLooper()) {
            "startBrowserAwait 不能在主线程等待"
        }
        val engine = engine ?: return null
        val activity = activityBinding?.activity ?: return null
        if (pendingWebLogin != null || pendingHostLogin != null) return null
        val config = engine.webLoginConfig(sourceKey, url)
        val pending = PendingHostLogin(sourceKey, config.url, config, CountDownLatch(1))
        pendingHostLogin = pending
        main.post {
            val current = activityBinding?.activity
            if (current == null || current.isFinishing || current.isDestroyed) {
                pendingHostLogin = null
                pending.latch.countDown()
                return@post
            }
            val intent = webLoginIntent(
                current,
                config,
                title.ifBlank { "网页验证" },
                returnHtml = !refetchAfterSuccess,
                allowEmpty = true,
            )
            try {
                current.startActivityForResult(intent, HostLoginRequestCode)
            } catch (error: Throwable) {
                pendingHostLogin = null
                pending.latch.countDown()
            }
        }
        if (!pending.latch.await(10, TimeUnit.MINUTES)) {
            pendingHostLogin = null
            return null
        }
        if (pending.canceled) return null
        return BookSourceBrowserResult(
            url = pending.completedUrl ?: pending.url,
            html = pending.html,
        )
    }

    override fun showBrowser(url: String, title: String, html: String?) {
        val activity = activityBinding?.activity ?: return
        main.post {
            runCatching {
                val config = genericWebConfig(url)
                activity.startActivity(
                    webLoginIntent(
                        activity,
                        config,
                        title.ifBlank { "浏览网页" },
                        allowEmpty = true,
                    )
                        .putExtra(WebLoginActivity.EXTRA_HTML, html.orEmpty()),
                )
            }
        }
    }

    override fun showReadingBrowser(url: String, title: String) {
        showBrowser(url, title, null)
    }

    override fun openVideoPlayer(url: String, title: String, float: Boolean) {
        val activity = activityBinding?.activity ?: return
        main.post {
            runCatching {
                val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
                activity.startActivity(Intent.createChooser(intent, title.ifBlank { "播放视频" }))
            }.onFailure {
                Toast.makeText(activity, "没有可播放该链接的应用", Toast.LENGTH_SHORT).show()
            }
        }
    }

    override fun openBook(url: String, title: String) {
        if (url.startsWith("http://", true) || url.startsWith("https://", true)) {
            showBrowser(url, title, null)
        } else {
            toast("当前客户端无法从脚本直接打开该书籍")
        }
    }

    override fun loadWebView(
        sourceKey: String,
        html: String,
        url: String,
        js: String,
        sourceRegex: String,
        overrideUrlRegex: String,
        cacheFirst: Boolean,
        delayMs: Long,
        headers: Map<String, String>,
    ): String {
        val engine = engine ?: return ""
        val context = getContext() ?: return ""
        val cookies = runCatching { engine.cookieValues(sourceKey, url) }.getOrDefault(emptyMap())
        return BookSourceWebView(
            context = context,
            html = html,
            url = url,
            javaScript = js,
            sourceRegex = sourceRegex,
            overrideUrlRegex = overrideUrlRegex,
            cacheFirst = cacheFirst,
            delayMs = delayMs,
            headers = headers,
            initialCookies = cookies,
            onCookies = { value ->
                runCatching { engine.saveWebViewCookies(sourceKey, url, value) }
            },
        ).load()
    }

    override fun clearWebCookies(url: String) {
        if (url.isBlank()) return
        main.post {
            runCatching {
                val manager = android.webkit.CookieManager.getInstance()
                val header = manager.getCookie(url).orEmpty()
                for (pair in header.split(';')) {
                    val name = pair.substringBefore('=', "").trim()
                    if (name.isNotEmpty()) manager.setCookie(url, "$name=; Max-Age=0; Path=/")
                }
                manager.flush()
            }
        }
    }

    private fun getContext(): Context? = activityBinding?.activity?.applicationContext ?: appContext

    private fun genericWebConfig(url: String): WebLoginConfig {
        val target = requireNotNull(url.toHttpUrlOrNull())
        val targets = listOf(target.origin().let { requireNotNull(it.toHttpUrlOrNull()) })
        return WebLoginConfig(
            url = url,
            title = "",
            headers = emptyMap(),
            cookieTargets = targets,
            cookies = emptyList(),
            jar = BookSourceCookies(url, null),
        )
    }

    private fun webLoginIntent(
        activity: Activity,
        config: WebLoginConfig,
        title: String,
        returnHtml: Boolean = false,
        allowEmpty: Boolean = false,
    ): Intent = Intent(activity, WebLoginActivity::class.java).apply {
        putExtra(WebLoginActivity.EXTRA_URL, config.url)
        putExtra(WebLoginActivity.EXTRA_TITLE, title)
        putStringArrayListExtra(
            WebLoginActivity.EXTRA_COOKIE_TARGETS,
            ArrayList(config.cookieTargets.map { it.toString() }),
        )
        putStringArrayListExtra(WebLoginActivity.EXTRA_COOKIES, ArrayList(config.cookies))
        putExtra(WebLoginActivity.EXTRA_USER_AGENT, config.headers["user-agent"])
        putExtra(WebLoginActivity.EXTRA_HEADERS, HashMap(config.headers))
        putExtra(WebLoginActivity.EXTRA_RETURN_HTML, returnHtml)
        putExtra(WebLoginActivity.EXTRA_ALLOW_EMPTY, allowEmpty)
    }

    private fun toast(message: String) {
        val context = getContext() ?: return
        main.post { Toast.makeText(context, message, Toast.LENGTH_SHORT).show() }
    }

    private fun dp(context: Context, value: Int): Int =
        (value * context.resources.displayMetrics.density).toInt()

    private fun runAsync(
        worker: ExecutorService,
        result: MethodChannel.Result,
        block: () -> Any?,
    ) {
        worker.execute {
            try {
                val value = block()
                main.post { result.success(value) }
            } catch (error: Throwable) {
                val message = message(error)
                main.post { result.error("BOOK_SOURCE_ERROR", message, null) }
            }
        }
    }

    private fun message(error: Throwable): String = when (error) {
        is IllegalArgumentException, is IllegalStateException ->
            error.message ?: "书源操作失败"
        is IOException -> "网络请求失败：${error.message ?: "请稍后重试"}"
        is RhinoException -> "书源脚本执行失败：${error.message ?: "请检查规则"}"
        else -> error.message ?: error.javaClass.simpleName
    }

    private fun bookMetadata(arguments: Map<*, *>): BookData {
        val fields = stringArgs(arguments, "book")
        return BookData(name = fields["name"].orEmpty(), author = fields["author"].orEmpty(),
            coverUrl = fields["coverUrl"].orEmpty(), intro = fields["intro"].orEmpty(), kind = fields["kind"].orEmpty(),
            tocUrl = fields["tocUrl"].orEmpty(), lastChapter = fields["lastChapter"].orEmpty(),
            updateTime = fields["updateTime"].orEmpty(), wordCount = fields["wordCount"].orEmpty())
    }

    private fun stringArg(arguments: Map<*, *>, key: String): String =
        arguments[key]?.toString()?.trim().orEmpty()

    private fun intArg(arguments: Map<*, *>, key: String, fallback: Int): Int =
        when (val value = arguments[key]) {
            is Number -> value.toInt()
            is String -> value.toIntOrNull() ?: fallback
            else -> fallback
        }

    private fun stringArgs(arguments: Map<*, *>, key: String): Map<String, String> {
        val value = arguments[key] as? Map<*, *> ?: return emptyMap()
        return buildMap {
            for ((name, item) in value) {
                if (name != null && item != null) put(name.toString(), item.toString())
            }
        }
    }

    /**
     * 书源脚本里的 getReadBookConfig()/getThemeConfig() 用于跟随阅读主题。
     * 阅读偏好由 Flutter 的 shared_preferences 保存，这里读取同一份记录，
     * 避免脚本拿到空对象后退回固定配色。
     */
    private fun flutterReaderConfig(): Map<String, Any?> {
        val context = appContext ?: return emptyMap()
        val prefs = runCatching {
            context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        }.getOrNull() ?: return emptyMap()
        val record = prefs.getString("flutter.readerPreferences", null)
        val json = runCatching { JSONObject(record ?: "{}") }.getOrDefault(JSONObject())
        val mode = json.optString("themeMode")
        val night = when (mode) {
            "night" -> true
            "day" -> false
            else -> (context.resources.configuration.uiMode and
                Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES
        }
        val legadoThemeMode = when (mode) {
            "night" -> "2"
            "day" -> "1"
            else -> "0"
        }
        val paper = json.optString("paper").ifEmpty { "system" }
        val (background, foreground) = when (paper) {
            "milk" -> "#F6F5EF" to "#262626"
            "parchment" -> "#EDE2CA" to "#262626"
            "sage" -> "#E4EBDD" to "#262626"
            "night" -> "#000000" to "#ADADAD"
            else -> if (night) "#1B1B1B" to "#CCCCCC" else "#FFFFFF" to "#262626"
        }
        return buildMap {
            put("paper", paper)
            put("name", paper)
            put("nightTheme", night)
            put("isNightTheme", night)
            put("themeMode", legadoThemeMode)
            put("bgColor", background)
            put("backgroundColor", background)
            put("textColor", foreground)
            put("textColorStr", foreground)
            put("margin", json.opt("margin") ?: 24)
            put("paragraphGap", json.opt("paragraphGap") ?: 12)
            put("indent", json.opt("indent") ?: true)
            put("indentCount", json.opt("indentCount") ?: 2)
            put("titleScale", json.opt("titleScale") ?: 1.2)
            put("lineSpacing", 1.5)
        }
    }

    companion object {
        const val ChannelName = "org.mewx.wenku8/book_sources"
        private const val WebLoginRequestCode = 7301
        private const val HostLoginRequestCode = 7302
    }
}
