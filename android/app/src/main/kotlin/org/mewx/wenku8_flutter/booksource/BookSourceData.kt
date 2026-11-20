package org.mewx.wenku8_flutter.booksource

internal data class BookData(
    val name: String = "",
    val author: String = "",
    val bookUrl: String = "",
    val coverUrl: String = "",
    val intro: String = "",
    val kind: String = "",
    val lastChapter: String = "",
    val updateTime: String = "",
    val tocUrl: String = "",
)

internal data class ChapterData(
    val title: String = "",
    val url: String = "",
    val nextUrl: String = "",
)

internal data class RuleContext(
    val content: Any?,
    val baseUrl: String,
    val key: String = "",
    val page: Int = 1,
    val book: BookData? = null,
    val chapter: ChapterData? = null,
    val redirectUrl: String = "",
)
