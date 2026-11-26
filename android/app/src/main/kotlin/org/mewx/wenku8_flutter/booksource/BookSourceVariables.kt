package org.mewx.wenku8_flutter.booksource

import android.content.Context
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

/// Legado 书源用 `source.getVariable()/putVariable()` 保存发现页筛选、
/// 账号状态等设置。这里按书源地址持久化原始 JSON，规则本身仍由 JS 解释。
internal class BookSourceVariables(context: Context?) {
    private val preferences = context?.getSharedPreferences(
        "wenku8-book-source-variables",
        Context.MODE_PRIVATE,
    )
    private val secrets = context?.let(::BookSourceSecretStore)
    private val memory = ConcurrentHashMap<String, String>()

    fun get(key: String): String {
        if (!isSecret(key)) {
            return preferences?.getString(preferenceKey(key), null)
                ?: memory[key].orEmpty()
        }
        secrets?.get(key)?.let { return it }
        val legacy = preferences?.getString(preferenceKey(key), null)
        if (!legacy.isNullOrBlank()) {
            runCatching { secrets?.put(key, legacy) }
            preferences?.edit()?.remove(preferenceKey(key))?.apply()
            return legacy
        }
        return memory[key].orEmpty()
    }

    fun put(key: String, value: String) {
        memory[key] = value
        if (isSecret(key)) {
            if (value.isBlank()) {
                secrets?.remove(key)
            } else {
                runCatching { secrets?.put(key, value) }
                    .onSuccess {
                        preferences?.edit()?.remove(preferenceKey(key))?.apply()
                    }
            }
        } else {
            preferences?.edit()?.putString(preferenceKey(key), value)?.apply()
        }
    }

    fun remove(key: String) {
        memory.remove(key)
        if (isSecret(key)) {
            secrets?.remove(key)
        }
        preferences?.edit()?.remove(preferenceKey(key))?.apply()
    }

    fun getSourceValue(sourceKey: String, key: String): String =
        get(sourceValueKey(sourceKey, key))

    fun putSourceValue(sourceKey: String, key: String, value: String) {
        put(sourceValueKey(sourceKey, key), value)
    }

    private fun scopedKey(vararg parts: String) = parts.joinToString("", prefix = "rule:") { "${it.length}:$it" }

    fun readRule(source: String, book: BookData?, chapter: ChapterData?, key: String): String {
        if (key == "bookName" && book != null) return book.name
        if (key == "title" && chapter != null) return chapter.title
        if (chapter != null) {
            val value = if (chapter.variableUrl.isEmpty()) chapter.pendingVariables[key] else
                get(scopedKey(source, book?.bookUrl.orEmpty(), chapter.variableUrl, key))
            if (!value.isNullOrEmpty()) return value
        }
        if (book != null) {
            val value = if (book.bookUrl.isEmpty()) book.pendingVariables[key] else get(scopedKey(source, book.bookUrl, key))
            if (!value.isNullOrEmpty()) return value
        }
        return getSourceValue(source, key)
    }

    fun writeRule(source: String, book: BookData?, chapter: ChapterData?, key: String, value: String) {
        when {
            chapter != null && chapter.variableUrl.isEmpty() -> chapter.pendingVariables[key] = value
            chapter != null -> put(scopedKey(source, book?.bookUrl.orEmpty(), chapter.variableUrl, key), value)
            book != null && book.bookUrl.isEmpty() -> book.pendingVariables[key] = value
            book != null -> put(scopedKey(source, book.bookUrl, key), value)
            else -> putSourceValue(source, key, value)
        }
    }

    fun removeRule(source: String, book: BookData?, chapter: ChapterData?, key: String) {
        when {
            chapter != null && chapter.variableUrl.isEmpty() -> chapter.pendingVariables.remove(key)
            chapter != null -> remove(scopedKey(source, book?.bookUrl.orEmpty(), chapter.variableUrl, key))
            book != null && book.bookUrl.isEmpty() -> book.pendingVariables.remove(key)
            book != null -> remove(scopedKey(source, book.bookUrl, key))
            else -> remove(sourceValueKey(source, key))
        }
    }

    @Synchronized
    fun deviceId(sourceKey: String): String {
        val key = "scriptDeviceId:$sourceKey"
        return get(key).ifEmpty {
            UUID.randomUUID().toString().replace("-", "").take(16).also { put(key, it) }
        }
    }

    private fun preferenceKey(key: String): String =
        "v:${Integer.toHexString(key.hashCode())}:${key.takeLast(64)}"

    private fun isSecret(key: String): Boolean =
        key.startsWith(LoginInfoKeyPrefix) ||
            key.startsWith(LoginHeaderKeyPrefix) ||
            key.startsWith(CookieKeyPrefix)
}

internal fun loginInfoKey(sourceKey: String): String = "$LoginInfoKeyPrefix$sourceKey"

internal fun loginHeaderKey(sourceKey: String): String = "$LoginHeaderKeyPrefix$sourceKey"

internal fun cookieKey(sourceKey: String): String = "$CookieKeyPrefix$sourceKey"

internal fun sourceValueKey(sourceKey: String, key: String): String =
    "sourceValue:$sourceKey:$key"

private const val LoginInfoKeyPrefix = "login:"
private const val LoginHeaderKeyPrefix = "loginHeader:"
private const val CookieKeyPrefix = "cookie:"
