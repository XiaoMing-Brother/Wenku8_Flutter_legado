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
    val wordCount: String = "",
    val durChapterTitle: String = "",
    val durChapterIndex: Int = 0,
    val pendingVariables: MutableMap<String, String> = mutableMapOf(),
)

internal data class ChapterData(
    val index: Int = 0,
    val title: String = "",
    val url: String = "",
    val nextUrl: String = "",
    val bookUrl: String = "",
    val baseUrl: String = "",
    val tag: String = "",
    val isVolume: Boolean = false,
    val isVip: Boolean = false,
    val isPay: Boolean = false,
    val variableUrl: String = "",
    val pendingVariables: MutableMap<String, String> = mutableMapOf(),
)

internal data class RuleContext(
    val content: Any?,
    val baseUrl: String,
    val key: String = "",
    val page: Int = 1,
    val book: BookData? = null,
    val chapter: ChapterData? = null,
    val redirectUrl: String = "",
    val fromBookInfo: Boolean = false,
)
