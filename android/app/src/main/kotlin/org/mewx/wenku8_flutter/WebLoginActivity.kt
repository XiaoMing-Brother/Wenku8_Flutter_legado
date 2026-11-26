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
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.webkit.CookieManagerCompat
import androidx.webkit.WebViewFeature
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import org.mewx.wenku8_flutter.booksource.origin
import org.mewx.wenku8_flutter.booksource.readWebCookieDetails
import org.mewx.wenku8_flutter.booksource.webCookieTargets
import org.mewx.wenku8_flutter.booksource.WebCookieLine
import org.json.JSONTokener

/**
 * 独立的网页登录页。登录完成后只回传 Cookie，账号密码不离开网页本身。
 * 每次登录前后都会清理 WebView Cookie，避免不同书源之间串登录状态。
 */
class WebLoginActivity : Activity() {
    private var webView: WebView? = null
    private var progress: ProgressBar? = null
    private var titleView: TextView? = null
    private lateinit var cookieTargets: List<HttpUrl>
    private val visitedUrls = linkedSetOf<String>()
    private val capturedCookies = linkedSetOf<WebCookieLine>()
    private var cookiesReady = false
    private var finished = false
    private var returnHtml = false
    private var allowEmpty = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val url = intent.getStringExtra(EXTRA_URL).orEmpty().trim()
        val html = intent.getStringExtra(EXTRA_HTML).orEmpty()
        returnHtml = intent.getBooleanExtra(EXTRA_RETURN_HTML, false)
        allowEmpty = intent.getBooleanExtra(EXTRA_ALLOW_EMPTY, false) || returnHtml
        if (url.isEmpty() && html.isBlank()) {
            finish()
            return
        }
        val title = intent.getStringExtra(EXTRA_TITLE).orEmpty().trim()
            .ifEmpty { "网页登录" }
        val headers = readHeaders()
        val targets = checkNotNull(intent.getStringArrayListExtra(EXTRA_COOKIE_TARGETS))
        cookieTargets = webCookieTargets(
            targets.mapNotNull { it.toHttpUrlOrNull() },
            targets,
        ).ifEmpty {
            listOf(targets.first().toHttpUrl().origin().toHttpUrl())
        }
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
        ViewCompat.setOnApplyWindowInsetsListener(root) { view, insets ->
            val bars = insets.getInsets(
                WindowInsetsCompat.Type.systemBars() or
                    WindowInsetsCompat.Type.displayCutout(),
            )
            view.setPadding(0, bars.top, 0, bars.bottom)
            insets
        }
        ViewCompat.requestApplyInsets(root)

        configureWebView(web, userAgent)
        prepareCookies(initialCookies) {
            if (!finished && !isFinishing && !isDestroyed) {
                cookiesReady = true
                if (html.isNotBlank()) {
                    web.loadDataWithBaseURL(
                        url.ifBlank { "about:blank" },
                        html,
                        "text/html",
                        "UTF-8",
                        url.ifBlank { "about:blank" },
                    )
                } else {
                    web.loadUrl(url, headers)
                }
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
            override fun onPageStarted(view: WebView, url: String?, favicon: android.graphics.Bitmap?) {
                rememberUrl(url)
            }

            override fun shouldOverrideUrlLoading(
                view: WebView,
                request: WebResourceRequest,
            ): Boolean = handleUrl(request.url)

            override fun onPageFinished(view: WebView, url: String?) {
                rememberUrl(url)
                capturedCookies.addAll(captureCookies())
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

    /** 登录页常会跳到 passport、会员等子域名，记录页面地址用于补读 Cookie。 */
    private fun rememberUrl(url: String?) {
        val value = url?.trim().orEmpty()
        if (!value.startsWith("http://", ignoreCase = true) &&
            !value.startsWith("https://", ignoreCase = true)
        ) {
            return
        }
        if (visitedUrls.size >= 16) return
        visitedUrls.add(value)
    }

    private fun observedTargets(): List<HttpUrl> = webCookieTargets(
        cookieTargets,
        cookieTargets.map { it.toString() } +
            visitedUrls +
            listOfNotNull(webView?.url),
    )

    /** 与 Legado 一样在页面结束时就读取一次，避免登录成功后跳转又清掉中间态 Cookie。 */
    private fun captureCookies(): List<WebCookieLine> {
        if (!cookiesReady) return emptyList()
        val manager = CookieManager.getInstance()
        val targets = observedTargets()
        val scoped = WebViewFeature.isFeatureSupported(WebViewFeature.GET_COOKIE_INFO)
        return runCatching {
            if (scoped) {
                readWebCookieDetails(targets) { target ->
                    CookieManagerCompat.getCookieInfo(manager, target.toString())
                }
            } else {
                buildList {
                    for (target in targets) {
                        manager.getCookie(target.toString()).orEmpty().split(';').map { it.trim() }
                            .filter { it.indexOf('=') > 0 }
                            .forEach {
                                add(
                                    WebCookieLine(
                                        target,
                                        "$it; Path=/; HttpOnly" + if (target.isHttps) "; Secure" else "",
                                    ),
                                )
                            }
                    }
                }
            }
        }.getOrDefault(emptyList())
    }

    private fun prepareCookies(
        initialCookies: List<String>,
        action: () -> Unit,
    ) {
        val manager = CookieManager.getInstance()
        manager.setAcceptCookie(true)
        manager.removeAllCookies {
            if (finished || isDestroyed) return@removeAllCookies
            val writes = initialCookies.sumOf { cookie -> cookieTargets.size }
            if (writes == 0) {
                action()
                return@removeAllCookies
            }
            var remaining = writes
            for (cookie in initialCookies) {
                for (target in cookieTargets) {
                    manager.setCookie(target.toString(), cookie) {
                        if (--remaining == 0 && !finished && !isDestroyed) action()
                    }
                }
            }
        }
    }

    private fun finishWithCookies() {
        if (finished || !cookiesReady) return
        val web = webView
        if (returnHtml && web != null) {
            web.evaluateJavascript("document.documentElement.outerHTML") { value ->
                val html = runCatching {
                    JSONTokener(value.orEmpty()).nextValue() as? String
                }.getOrNull().orEmpty()
                finishWithCookies(html)
            }
            return
        }
        finishWithCookies("")
    }

    private fun finishWithCookies(html: String) {
        if (finished || !cookiesReady) return
        val targets = observedTargets()
        val root = targets.first()
        val scoped = WebViewFeature.isFeatureSupported(WebViewFeature.GET_COOKIE_INFO)
        val completed = webView?.url?.let { it.toHttpUrlOrNull() } ?: root
        capturedCookies.addAll(captureCookies())
        val lines = capturedCookies.toList()
        if (lines.isEmpty() && !allowEmpty) {
            Toast.makeText(this, "无法读取网页登录状态，请重试", Toast.LENGTH_SHORT).show()
            return
        }
        val cookies = lines.map { it.value }
        val cookieUrls = lines.map { it.target.toString() }
        finished = true
        setResult(
            RESULT_OK,
            Intent().putStringArrayListExtra(EXTRA_COOKIES_RESULT, ArrayList(cookies))
                .putStringArrayListExtra(EXTRA_COOKIE_TARGETS_RESULT, ArrayList(cookieUrls))
                .putExtra(EXTRA_SCOPED, scoped).putExtra(EXTRA_COMPLETED_URL, completed.toString())
                .putExtra(EXTRA_HTML_RESULT, html),
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
        const val EXTRA_HTML = "webLoginHtml"
        const val EXTRA_RETURN_HTML = "webLoginReturnHtml"
        const val EXTRA_ALLOW_EMPTY = "webLoginAllowEmpty"
        const val EXTRA_HTML_RESULT = "webLoginHtmlResult"
        const val EXTRA_TITLE = "webLoginTitle"
        const val EXTRA_HEADERS = "webLoginHeaders"
        const val EXTRA_COOKIE_TARGETS = "webLoginCookieTargets"
        const val EXTRA_SCOPED = "webLoginScopedCookies"
        const val EXTRA_COMPLETED_URL = "webLoginCompletedUrl"
        const val EXTRA_COOKIES = "webLoginCookieList"
        const val EXTRA_USER_AGENT = "webLoginUserAgent"
        const val EXTRA_COOKIES_RESULT = "webLoginCookies"
        const val EXTRA_COOKIE_TARGETS_RESULT = "webLoginCookieOrigins"
    }
}
