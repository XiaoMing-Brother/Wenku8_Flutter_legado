package org.mewx.wenku8_flutter

import android.annotation.SuppressLint
import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.res.ColorStateList
import android.content.res.Configuration
import android.graphics.Color
import android.net.Uri
import android.net.http.SslError
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.RenderProcessGoneDetail
import android.webkit.SslErrorHandler
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView
import android.widget.Toast
import androidx.webkit.CookieManagerCompat
import androidx.webkit.WebViewFeature
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrl
import org.mewx.wenku8_flutter.booksource.readWebCookieLines
import org.mewx.wenku8_flutter.booksource.webCookieTargets

/**
 * 独立的网页登录页。登录完成后只回传 Cookie，账号密码不离开网页本身。
 * 每次登录前后都会清理 WebView Cookie，避免不同书源之间串登录状态。
 */
class WebLoginActivity : Activity() {
    private var webView: WebView? = null
    private var progress: ProgressBar? = null
    private var titleView: TextView? = null
    private lateinit var cookieTargets: List<HttpUrl>
    private var cookiesReady = false
    private var finished = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val url = intent.getStringExtra(EXTRA_URL).orEmpty().trim()
        if (url.isEmpty()) {
            finish()
            return
        }
        val title = intent.getStringExtra(EXTRA_TITLE).orEmpty().trim()
            .ifEmpty { "网页登录" }
        val headers = readHeaders()
        val targets = checkNotNull(intent.getStringArrayListExtra(EXTRA_COOKIE_TARGETS))
        cookieTargets = targets.first().toHttpUrl().webCookieTargets(targets)
        val initialCookies = intent.getStringArrayListExtra(EXTRA_COOKIES).orEmpty()
        val userAgent = intent.getStringExtra(EXTRA_USER_AGENT).orEmpty().trim()
        val dark = (resources.configuration.uiMode and
            Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES
        val background = if (dark) Color.rgb(22, 23, 25) else Color.rgb(250, 248, 244)
        val foreground = if (dark) Color.rgb(238, 238, 238) else Color.rgb(28, 28, 30)
        val muted = if (dark) Color.rgb(158, 160, 166) else Color.rgb(104, 105, 110)
        val accent = if (dark) Color.rgb(142, 204, 255) else Color.rgb(20, 92, 160)

        window.statusBarColor = background
        window.navigationBarColor = background
        @Suppress("DEPRECATION")
        window.decorView.systemUiVisibility = if (dark) {
            0
        } else {
            View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR or
                View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR
        }
        window.setSoftInputMode(
            android.view.WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE,
        )

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(background)
        }
        val header = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(8), 0, dp(8), 0)
            setBackgroundColor(background)
        }
        val back = TextView(this).apply {
            text = "‹"
            textSize = 30f
            gravity = Gravity.CENTER
            setTextColor(foreground)
            setPadding(dp(10), 0, dp(10), dp(2))
            isClickable = true
            isFocusable = true
            setOnClickListener { goBackOrCancel() }
        }
        titleView = TextView(this).apply {
            text = title
            textSize = 17f
            setTextColor(foreground)
            maxLines = 1
            ellipsize = android.text.TextUtils.TruncateAt.END
            setPadding(dp(4), 0, dp(8), 0)
        }
        val refresh = TextView(this).apply {
            text = "刷新"
            textSize = 14f
            gravity = Gravity.CENTER
            setTextColor(muted)
            setPadding(dp(10), 0, dp(10), 0)
            isClickable = true
            isFocusable = true
            setOnClickListener { webView?.reload() }
        }
        val done = TextView(this).apply {
            text = "完成"
            textSize = 15f
            gravity = Gravity.CENTER
            setTextColor(accent)
            setPadding(dp(12), 0, dp(10), 0)
            isClickable = true
            isFocusable = true
            setOnClickListener { finishWithCookies() }
        }
        header.addView(
            back,
            LinearLayout.LayoutParams(dp(48), ViewGroup.LayoutParams.MATCH_PARENT),
        )
        header.addView(
            titleView,
            LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f),
        )
        header.addView(
            refresh,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            ),
        )
        header.addView(
            done,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            ),
        )
        root.addView(
            header,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                dp(56),
            ),
        )
        root.addView(
            View(this).apply { setBackgroundColor(if (dark) 0xFF303236.toInt() else 0xFFE3E0DA.toInt()) },
            LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(1)),
        )
        progress = ProgressBar(
            this,
            null,
            android.R.attr.progressBarStyleHorizontal,
        ).apply {
            max = 100
            progress = 0
            progressTintList = ColorStateList.valueOf(accent)
            visibility = View.GONE
        }
        root.addView(
            progress,
            LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(2)),
        )
        val web = WebView(this).apply {
            setBackgroundColor(background)
        }
        webView = web
        root.addView(
            web,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                0,
                1f,
            ),
        )
        setContentView(root)

        configureWebView(web, userAgent)
        prepareCookies(initialCookies) {
            if (!finished && !isFinishing && !isDestroyed) {
                cookiesReady = true
                web.loadUrl(url, headers)
            }
        }
    }

    @SuppressLint("SetJavaScriptEnabled")
    private fun configureWebView(web: WebView, userAgent: String) {
        web.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            databaseEnabled = true
            loadsImagesAutomatically = true
            cacheMode = WebSettings.LOAD_DEFAULT
            mixedContentMode = WebSettings.MIXED_CONTENT_COMPATIBILITY_MODE
            allowFileAccess = false
            allowContentAccess = false
            displayZoomControls = false
            builtInZoomControls = false
            mediaPlaybackRequiresUserGesture = true
            if (userAgent.isNotBlank()) userAgentString = userAgent
        }
        CookieManager.getInstance().apply {
            setAcceptCookie(true)
            setAcceptThirdPartyCookies(web, true)
        }
        web.webChromeClient = object : WebChromeClient() {
            override fun onProgressChanged(view: WebView, newProgress: Int) {
                progress?.apply {
                    progress = newProgress
                    visibility = if (newProgress in 1..99) View.VISIBLE else View.GONE
                }
            }
        }
        web.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(
                view: WebView,
                request: WebResourceRequest,
            ): Boolean = handleUrl(request.url)

            override fun onPageFinished(view: WebView, url: String?) {
                progress?.visibility = View.GONE
                view.evaluateJavascript("document.title") { value ->
                    val pageTitle = value
                        ?.trim()
                        ?.removeSurrounding("\"")
                        ?.replace("\\\"", "\"")
                        .orEmpty()
                    if (pageTitle.isNotBlank() && pageTitle != "null") {
                        titleView?.text = pageTitle
                    }
                }
            }

            override fun onReceivedError(
                view: WebView,
                request: WebResourceRequest,
                error: android.webkit.WebResourceError,
            ) {
                if (request.isForMainFrame) {
                    progress?.visibility = View.GONE
                    Toast.makeText(
                        this@WebLoginActivity,
                        "网页加载失败，请检查网络后重试",
                        Toast.LENGTH_SHORT,
                    ).show()
                }
            }

            override fun onReceivedSslError(
                view: WebView,
                handler: SslErrorHandler,
                error: SslError,
            ) {
                handler.cancel()
                Toast.makeText(
                    this@WebLoginActivity,
                    "登录页证书无效，已停止加载",
                    Toast.LENGTH_SHORT,
                ).show()
            }

            override fun onRenderProcessGone(
                view: WebView,
                detail: RenderProcessGoneDetail,
            ): Boolean {
                Toast.makeText(
                    this@WebLoginActivity,
                    "登录页已中断，请重新打开",
                    Toast.LENGTH_SHORT,
                ).show()
                cancelLogin()
                return true
            }
        }
    }

    private fun handleUrl(uri: Uri): Boolean {
        val scheme = uri.scheme?.lowercase().orEmpty()
        if (scheme == "http" || scheme == "https") return false
        runCatching {
            startActivity(Intent(Intent.ACTION_VIEW, uri))
        }.onFailure { error ->
            if (error is ActivityNotFoundException) {
                Toast.makeText(this, "没有可打开该链接的应用", Toast.LENGTH_SHORT).show()
            }
        }
        return true
    }

    private fun prepareCookies(
        initialCookies: List<String>,
        action: () -> Unit,
    ) {
        val manager = CookieManager.getInstance()
        manager.setAcceptCookie(true)
        manager.removeAllCookies {
            if (finished || isDestroyed) return@removeAllCookies
            var remaining = initialCookies.size
            if (remaining == 0) action()
            for (cookie in initialCookies) manager.setCookie(cookieTargets.first().toString(), cookie) {
                if (--remaining == 0) action()
            }
        }
    }

    private fun finishWithCookies() {
        if (finished || !cookiesReady) return
        val manager = CookieManager.getInstance()
        val root = cookieTargets.first()
        val scoped = WebViewFeature.isFeatureSupported(WebViewFeature.GET_COOKIE_INFO)
        val completed = if (scoped) root.webCookieTargets(listOf(webView?.url)).last() else root
        val cookies = try {
            if (scoped) {
                readWebCookieLines((cookieTargets + completed).distinct()) { target ->
                    CookieManagerCompat.getCookieInfo(manager, target.toString())
                }
            } else {
                manager.getCookie(root.toString()).orEmpty().split(';').map { it.trim() }
                    .filter { it.indexOf('=') > 0 }.map { "$it; Path=/; HttpOnly" + if (root.isHttps) "; Secure" else "" }
            }
        } catch (_: RuntimeException) {
            Toast.makeText(this, "无法读取网页登录状态，请重试", Toast.LENGTH_SHORT).show()
            return
        }
        finished = true
        setResult(
            RESULT_OK,
            Intent().putStringArrayListExtra(EXTRA_COOKIES_RESULT, ArrayList(cookies))
                .putExtra(EXTRA_SCOPED, scoped).putExtra(EXTRA_COMPLETED_URL, completed.toString()),
        )
        clearCookiesAndFinish()
    }

    private fun cancelLogin() {
        if (finished) return
        finished = true
        setResult(RESULT_CANCELED)
        clearCookiesAndFinish()
    }

    private fun clearCookiesAndFinish() {
        webView?.stopLoading()
        CookieManager.getInstance().removeAllCookies { finish() }
    }

    private fun goBackOrCancel() {
        val web = webView
        if (web != null && web.canGoBack()) {
            web.goBack()
        } else {
            cancelLogin()
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        goBackOrCancel()
    }

    override fun onDestroy() {
        webView?.apply {
            stopLoading()
            loadUrl("about:blank")
            destroy()
        }
        webView = null
        if (!finished) CookieManager.getInstance().removeAllCookies(null)
        super.onDestroy()
    }

    @Suppress("DEPRECATION")
    private fun readHeaders(): Map<String, String> {
        val raw = intent.getSerializableExtra(EXTRA_HEADERS) as? HashMap<*, *>
            ?: return emptyMap()
        return buildMap {
            for ((key, value) in raw) {
                if (key is String && value != null &&
                    !key.equals("Cookie", ignoreCase = true)
                ) {
                    put(key, value.toString())
                }
            }
        }
    }

    private fun dp(value: Int): Int =
        (value * resources.displayMetrics.density).toInt()

    companion object {
        const val EXTRA_URL = "webLoginUrl"
        const val EXTRA_TITLE = "webLoginTitle"
        const val EXTRA_HEADERS = "webLoginHeaders"
        const val EXTRA_COOKIE_TARGETS = "webLoginCookieTargets"
        const val EXTRA_SCOPED = "webLoginScopedCookies"
        const val EXTRA_COMPLETED_URL = "webLoginCompletedUrl"
        const val EXTRA_COOKIES = "webLoginCookieList"
        const val EXTRA_USER_AGENT = "webLoginUserAgent"
        const val EXTRA_COOKIES_RESULT = "webLoginCookies"
    }
}
