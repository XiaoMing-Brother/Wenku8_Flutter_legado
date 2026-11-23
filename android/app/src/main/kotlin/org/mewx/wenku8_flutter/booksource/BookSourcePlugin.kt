package org.mewx.wenku8_flutter.booksource

import android.app.Activity
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.io.IOException
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import org.mozilla.javascript.RhinoException
import org.mewx.wenku8_flutter.WebLoginActivity

class BookSourcePlugin :
    FlutterPlugin,
    ActivityAware,
    PluginRegistry.ActivityResultListener {
    private var channel: MethodChannel? = null
    private var engine: BookSourceEngine? = null
    private var executor: ExecutorService? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var pendingWebLogin: PendingWebLogin? = null
    private val main = Handler(Looper.getMainLooper())

    private data class PendingWebLogin(
        val sourceKey: String,
        val result: MethodChannel.Result,
        var config: WebLoginConfig? = null,
    )

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val bookSourceEngine = BookSourceEngine(
            variables = BookSourceVariables(binding.applicationContext),
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
        detachActivity(keepPending = false)
        channel?.setMethodCallHandler(null)
        channel = null
        engine = null
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
                        sourceKey = stringArg(arguments, "sourceKey"),
                        bookUrl = stringArg(arguments, "bookUrl"),
                    )
                }
                "chapters" -> runAsync(worker, result) {
                    engine.chapters(
                        sourceKey = stringArg(arguments, "sourceKey"),
                        bookUrl = stringArg(arguments, "bookUrl"),
                        tocUrl = stringArg(arguments, "tocUrl").ifBlank { null },
                    )
                }
                "content" -> runAsync(worker, result) {
                    engine.content(
                        sourceKey = stringArg(arguments, "sourceKey"),
                        bookUrl = stringArg(arguments, "bookUrl"),
                        chapterUrl = stringArg(arguments, "chapterUrl"),
                        nextChapterUrl = stringArg(arguments, "nextChapterUrl")
                            .ifBlank { null },
                        chapterTitle = stringArg(arguments, "chapterTitle")
                            .ifBlank { null },
                    )
                }
                "fetchImage" -> runAsync(worker, result) {
                    engine.image(
                        sourceKey = stringArg(arguments, "sourceKey"),
                        url = stringArg(arguments, "url"),
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
                    null
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
                engine.webLoginConfig(sourceKey)
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
                    completedUrl = data.getStringExtra(WebLoginActivity.EXTRA_COMPLETED_URL)),
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
        }
    }

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

    companion object {
        const val ChannelName = "org.mewx.wenku8/book_sources"
        private const val WebLoginRequestCode = 7301
    }
}
