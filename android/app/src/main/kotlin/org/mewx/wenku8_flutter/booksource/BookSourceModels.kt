package org.mewx.wenku8_flutter.booksource

import org.json.JSONArray
import org.json.JSONObject

internal data class SearchRule(
    val bookList: String?,
    val name: String?,
    val author: String?,
    val intro: String?,
    val kind: String?,
    val lastChapter: String?,
    val updateTime: String?,
    val wordCount: String?,
    val bookUrl: String?,
    val coverUrl: String?,
    /** 发现页翻页参数名；地址没有 {{page}} 时按它追加页码。 */
    val pageParam: String? = null,
)

internal typealias ExploreRule = SearchRule

internal data class BookInfoRule(
    val init: String?,
    val name: String?,
    val author: String?,
    val intro: String?,
    val kind: String?,
    val lastChapter: String?,
    val updateTime: String?,
    val coverUrl: String?,
    val tocUrl: String?,
    val status: String?,
    val totalChapterNum: String?,
    val downloadUrls: String?,
    val wordCount: String?,
    val canReName: String?,
)

internal data class TocRule(
    val chapterList: String?,
    val chapterName: String?,
    val chapterUrl: String?,
    val isVolume: String?,
    val isVip: String?,
    val isPay: String?,
    val formatJs: String?,
    val preUpdateJs: String?,
    val updateTime: String?,
    val nextTocUrl: String?,
)

internal data class ContentRule(
    val content: String?,
    val subContent: String?,
    val nextContentUrl: String?,
    val title: String?,
    val replaceRegex: String?,
    val imageDecode: String?,
    val imageStyle: String?,
    val sourceRegex: String?,
    val webJs: String?,
    val payAction: String?,
    val callBackJs: String?,
)

internal class BookSource(private val raw: JSONObject) {
    val key: String = raw.optString("bookSourceUrl").trim()
    val name: String = raw.optString("bookSourceName").trim().ifEmpty { key }
    val group: String = raw.optString("bookSourceGroup").trim()
    val type: Int = when (val value = raw.opt("bookSourceType")) {
        is Number -> value.toInt()
        is String -> value.trim().toIntOrNull() ?: 0
        else -> 0
    }
    val supported: Boolean
        get() = type == 0 || type == 3 || (!content.content.isNullOrBlank() &&
            (type == 1 || type == 4 || type == 2))
    val searchUrl: String = raw.optString("searchUrl").trim()
    val exploreUrl: String = raw.optString("exploreUrl").trim()
    val loginUrl: String? = raw.stringOrNull("loginUrl")
    val loginUi: String? = raw.stringOrNull("loginUi")
    val loginCheckJs: String? = raw.stringOrNull("loginCheckJs")
    val enabledCookieJar: Boolean = raw.optBoolean("enabledCookieJar", true)
    val jsLib: String = raw.optString("jsLib")
    val bookUrlPattern: String? = raw.stringOrNull("bookUrlPattern")
    val coverDecodeJs: String? = raw.stringOrNull("coverDecodeJs")
    val concurrentRate: String? = raw.stringOrNull("concurrentRate")
    val variableComment: String? = raw.stringOrNull("variableComment")
    val rawHeader: String? = raw.stringOrNull("header")
    val charset: String? = raw.optString("charset").trim().ifEmpty { null }
        ?: raw.optString("bookSourceCharset").trim().ifEmpty { null }
    val respondTime: Int = raw.optInt("respondTime", 180000)
    val headers: Map<String, String> = parseHeaders(raw)
    val search: SearchRule = parseSearchRule(raw.ruleObject("ruleSearch"))
    val explore: ExploreRule = parseSearchRule(raw.ruleObject("ruleExplore"))
    val bookInfo: BookInfoRule = parseBookInfoRule(raw.ruleObject("ruleBookInfo"))
    val toc: TocRule = parseTocRule(raw.ruleObject("ruleToc"))
    val content: ContentRule = parseContentRule(raw.ruleObject("ruleContent"))

    fun rawMap(): Map<String, Any?> = jsonToKotlin(raw) as? Map<String, Any?> ?: emptyMap()

    companion object {
        fun from(value: Any?): BookSource {
            val json = when (value) {
                is JSONObject -> value
                is Map<*, *> -> toJsonObject(value)
                is String -> JSONObject(value)
                else -> throw IllegalArgumentException("书源必须是 JSON 对象")
            }
            val source = BookSource(json)
            if (source.key.isEmpty()) throw IllegalArgumentException("书源缺少 bookSourceUrl")
            return source
        }

        private fun parseHeaders(raw: JSONObject): Map<String, String> {
            val value = raw.opt("header") ?: return emptyMap()
            if (value == JSONObject.NULL) return emptyMap()
            val json = when (value) {
                is JSONObject -> value
                is Map<*, *> -> toJsonObject(value)
                is String -> {
                    if (value.trim().isEmpty()) return emptyMap()
                    runCatching { JSONObject(value) }.getOrNull() ?: return emptyMap()
                }
                else -> return emptyMap()
            }
            return try {
                buildMap {
                    for (key in json.keys()) {
                        val value = json.opt(key)
                        if (value != null && value != JSONObject.NULL) {
                            put(key, value.toString())
                        }
                    }
                }
            } catch (_: Exception) {
                emptyMap()
            }
        }

        private fun parseSearchRule(raw: JSONObject?): SearchRule = SearchRule(
            bookList = raw.stringOrNull("bookList"),
            name = raw.stringOrNull("name"),
            author = raw.stringOrNull("author"),
            intro = raw.stringOrNull("intro"),
            kind = raw.stringOrNull("kind"),
            lastChapter = raw.stringOrNull("lastChapter"),
            updateTime = raw.stringOrNull("updateTime"),
            wordCount = raw.stringOrNull("wordCount"),
            bookUrl = raw.stringOrNull("bookUrl"),
            coverUrl = raw.stringOrNull("coverUrl"),
            pageParam = raw.stringOrNull("pageParam"),
        )

        private fun parseBookInfoRule(raw: JSONObject?): BookInfoRule = BookInfoRule(
            init = raw.stringOrNull("init"),
            name = raw.stringOrNull("name"),
            author = raw.stringOrNull("author"),
            intro = raw.stringOrNull("intro"),
            kind = raw.stringOrNull("kind"),
            lastChapter = raw.stringOrNull("lastChapter"),
            updateTime = raw.stringOrNull("updateTime"),
            coverUrl = raw.stringOrNull("coverUrl"),
            tocUrl = raw.stringOrNull("tocUrl"),
            status = raw.stringOrNull("status"),
            totalChapterNum = raw.stringOrNull("totalChapterNum"),
            wordCount = raw.stringOrNull("wordCount"),
            downloadUrls = raw.stringOrNull("downloadUrls"),
            canReName = raw.stringOrNull("canReName"),
        )

        private fun parseTocRule(raw: JSONObject?): TocRule = TocRule(
            chapterList = raw.stringOrNull("chapterList"),
            chapterName = raw.stringOrNull("chapterName"),
            chapterUrl = raw.stringOrNull("chapterUrl"),
            isVolume = raw.stringOrNull("isVolume"),
            isVip = raw.stringOrNull("isVip"),
            isPay = raw.stringOrNull("isPay"),
            formatJs = raw.stringOrNull("formatJs"),
            preUpdateJs = raw.stringOrNull("preUpdateJs"),
            updateTime = raw.stringOrNull("updateTime"),
            nextTocUrl = raw.stringOrNull("nextTocUrl"),
        )

        private fun parseContentRule(raw: JSONObject?): ContentRule = ContentRule(
            content = raw.stringOrNull("content"),
            subContent = raw.stringOrNull("subContent"),
            nextContentUrl = raw.stringOrNull("nextContentUrl"),
            // 正文内的章节标题规则，优先用它剥离正文里重复的标题块。
            title = raw.stringOrNull("title"),
            replaceRegex = raw.stringOrNull("replaceRegex"),
            imageDecode = raw.stringOrNull("imageDecode"),
            imageStyle = raw.stringOrNull("imageStyle"),
            sourceRegex = raw.stringOrNull("sourceRegex"),
            webJs = raw.stringOrNull("webJs"),
            payAction = raw.stringOrNull("payAction"),
            callBackJs = raw.stringOrNull("callBackJs"),
        )
    }
}

private fun JSONObject.ruleObject(key: String): JSONObject? {
    val value = opt(key) ?: return null
    if (value == JSONObject.NULL) return null
    if (value is JSONObject) return value
    if (value is Map<*, *>) return toJsonObject(value)
    if (value is String && value.trim().startsWith("{")) {
        return try {
            JSONObject(value)
        } catch (_: Exception) {
            null
        }
    }
    return null
}

private fun JSONObject?.stringOrNull(key: String): String? {
    if (this == null) return null
    val value = opt(key) ?: return null
    if (value == JSONObject.NULL) return null
    return value.toString().trim().ifEmpty { null }
}

internal fun toJsonValue(value: Any?): Any? = when (value) {
    null, JSONObject.NULL -> JSONObject.NULL
    is JSONObject, is JSONArray, is String, is Number, is Boolean -> value
    is Map<*, *> -> toJsonObject(value)
    is Iterable<*> -> JSONArray().also { array ->
        for (item in value) array.put(toJsonValue(item))
    }
    is Array<*> -> JSONArray().also { array ->
        for (item in value) array.put(toJsonValue(item))
    }
    else -> value.toString()
}

internal fun toJsonObject(value: Map<*, *>): JSONObject = JSONObject().also { json ->
    for ((key, item) in value) {
        if (key == null) continue
        json.put(key.toString(), toJsonValue(item))
    }
}

internal fun jsonToKotlin(value: Any?): Any? = when (value) {
    null, JSONObject.NULL -> null
    is JSONObject -> buildMap {
        for (key in value.keys()) put(key, jsonToKotlin(value.opt(key)))
    }
    is JSONArray -> buildList {
        for (index in 0 until value.length()) add(jsonToKotlin(value.opt(index)))
    }
    else -> value
}
