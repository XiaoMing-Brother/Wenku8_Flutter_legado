package org.mewx.wenku8_flutter.booksource

/**
 * 书源脚本需要跳出纯网络层、和 Android 宿主交互的入口。
 *
 * 所有方法都可能从书源 worker 线程调用；实现方负责切到主线程处理 UI。
 * 需要脚本等待结果的接口会阻塞调用线程，不能返回“稍后再看”的空结果。
 */
internal interface BookSourceHost {
    fun copyText(text: String)

    fun getVerificationCode(
        sourceKey: String,
        sourceName: String,
        imageUrl: String,
    ): String

    /** 打开内置浏览器并等待用户完成，用户取消时返回 null。 */
    fun awaitWebLogin(
        sourceKey: String,
        url: String,
        title: String,
        refetchAfterSuccess: Boolean,
    ): BookSourceBrowserResult?

    fun showBrowser(url: String, title: String, html: String?)

    fun showReadingBrowser(url: String, title: String)

    fun openVideoPlayer(url: String, title: String, float: Boolean)

    fun openBook(url: String, title: String)

    fun loadWebView(
        sourceKey: String,
        html: String,
        url: String,
        js: String,
        sourceRegex: String,
        overrideUrlRegex: String,
        cacheFirst: Boolean,
        delayMs: Long,
        headers: Map<String, String>,
    ): String

    fun clearWebCookies(url: String)
}

data class BookSourceBrowserResult(
    val url: String,
    val html: String = "",
)
