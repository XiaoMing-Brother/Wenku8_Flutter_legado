package org.mewx.wenku8_flutter.booksource

import android.annotation.SuppressLint
import android.content.Context
import android.net.http.SslError
import android.os.Handler
import android.os.Looper
import android.webkit.CookieManager
import android.webkit.RenderProcessGoneDetail
import android.webkit.SslErrorHandler
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import org.json.JSONTokener

/**
 * 书源 `java.webView()` 的后台 WebView。
 *
 * 和 Legado 的 BackstageWebView 一样在应用上下文里创建，页面 JS 执行和
 * 资源嗅探都在主线程完成；调用脚本的 worker 线程通过 CountDownLatch 等待。
 */
internal class BookSourceWebView(
    private val context: Context,
    private val html: String,
    private val url: String,
    private val javaScript: String,
    private val sourceRegex: String,
    private val overrideUrlRegex: String,
    private val cacheFirst: Boolean,
    private val delayMs: Long,
    private val headers: Map<String, String>,
    private val initialCookies: Map<String, String>,
    private val onCookies: (String) -> Unit,
) {
    private val main = Handler(Looper.getMainLooper())
    private val finished = AtomicBoolean(false)
    private val latch = CountDownLatch(1)
    @Volatile private var result: String = ""
    private var webView: WebView? = null

    fun load(): String {
        check(Looper.myLooper() != Looper.getMainLooper()) {
            "java.webView 不能在主线程调用"
        }
        main.post { createAndLoad() }
        val timeout = 65_000L + delayMs.coerceIn(0L, 20_000L)
        latch.await(timeout, TimeUnit.MILLISECONDS)
        main.post { destroy() }
        return result
    }

    @SuppressLint("SetJavaScriptEnabled")
    private fun createAndLoad() {
        try {
            val view = WebView(context)
            webView = view
            val settings = view.settings
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true
            settings.blockNetworkImage = true
            settings.mixedContentMode = WebSettings.MIXED_CONTENT_ALWAYS_ALLOW
            settings.cacheMode = if (cacheFirst) {
                WebSettings.LOAD_CACHE_ELSE_NETWORK
            } else {
                WebSettings.LOAD_DEFAULT
            }
            headers["User-Agent"]?.let { settings.userAgentString = it }
            val cookies = CookieManager.getInstance()
            cookies.setAcceptCookie(true)
            cookies.setAcceptThirdPartyCookies(view, true)
            val cookieUrl = url.takeIf { it.startsWith("http", true) }
            if (cookieUrl != null) {
                for ((name, value) in initialCookies) {
                    cookies.setCookie(cookieUrl, "$name=$value; Path=/")
                }
            }
            view.webChromeClient = WebChromeClient()
            view.webViewClient = object : WebViewClient() {
                override fun shouldOverrideUrlLoading(
                    view: WebView,
                    request: WebResourceRequest,
                ): Boolean {
                    if (matches(overrideUrlRegex, request.url.toString())) {
                        complete(request.url.toString(), "")
                        return true
                    }
                    return false
                }

                @Deprecated("Deprecated in Java")
                override fun shouldOverrideUrlLoading(view: WebView, target: String): Boolean {
                    if (matches(overrideUrlRegex, target)) {
                        complete(target, "")
                        return true
                    }
                    return false
                }

                override fun onLoadResource(view: WebView, resourceUrl: String) {
                    if (matches(sourceRegex, resourceUrl)) {
                        complete(resourceUrl, "")
                    }
                }

                override fun onPageFinished(view: WebView, pageUrl: String) {
                    if (finished.get()) return
                    if (sourceRegex.isNotBlank() || overrideUrlRegex.isNotBlank()) {
                        // 嗅探模式由资源/跳转命中结束；页面正常结束只保存 Cookie。
                        saveCookies(pageUrl)
                        if (javaScript.isBlank()) return
                    }
                    main.postDelayed({
                        if (finished.get()) return@postDelayed
                        evaluate(view, pageUrl)
                    }, 1_000L + delayMs.coerceAtLeast(0L))
                }

                override fun onReceivedSslError(
                    view: WebView?,
                    handler: SslErrorHandler?,
                    error: SslError?,
                ) {
                    handler?.proceed()
                }

                override fun onRenderProcessGone(
                    view: WebView,
                    detail: RenderProcessGoneDetail,
                ): Boolean {
                    complete(view.url.orEmpty(), "")
                    return true
                }
            }
            val base = url.ifBlank { "about:blank" }
            if (html.isNotBlank()) {
                view.loadDataWithBaseURL(base, html, "text/html", "UTF-8", base)
            } else if (url.isNotBlank()) {
                view.loadUrl(url, headers)
            } else {
                complete("", "")
            }
        } catch (error: Throwable) {
            complete("", "")
        }
    }

    private fun evaluate(view: WebView, pageUrl: String) {
        val script = javaScript.trim().ifEmpty { "document.documentElement.outerHTML" }
        view.evaluateJavascript(script) { value ->
            if (finished.get()) return@evaluateJavascript
            complete(pageUrl.ifBlank { view.url.orEmpty() }, decodeJsValue(value))
        }
    }

    private fun decodeJsValue(value: String?): String {
        val text = value?.trim().orEmpty()
        if (text.isEmpty() || text == "null") return ""
        val decoded = runCatching { JSONTokener(text).nextValue() }.getOrNull()
        return when (decoded) {
            null -> ""
            is String -> decoded
            else -> decoded.toString()
        }
    }

    private fun matches(pattern: String, value: String): Boolean {
        if (pattern.isBlank()) return false
        return runCatching { value.matches(pattern.toRegex()) }.getOrDefault(false)
    }

    private fun saveCookies(pageUrl: String) {
        val target = pageUrl.takeIf { it.startsWith("http", true) }
            ?: url.takeIf { it.startsWith("http", true) }
            ?: return
        val value = CookieManager.getInstance().getCookie(target).orEmpty()
        if (value.isNotBlank()) onCookies(value)
    }

    private fun complete(pageUrl: String, body: String) {
        if (!finished.compareAndSet(false, true)) return
        result = body
        saveCookies(pageUrl.ifBlank { url })
        latch.countDown()
    }

    private fun destroy() {
        webView?.apply {
            stopLoading()
            loadUrl("about:blank")
            destroy()
        }
        webView = null
    }
}
