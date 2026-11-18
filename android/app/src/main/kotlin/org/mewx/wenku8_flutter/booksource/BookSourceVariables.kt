package org.mewx.wenku8_flutter.booksource

import android.content.Context
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

private const val LoginInfoKeyPrefix = "login:"
private const val LoginHeaderKeyPrefix = "loginHeader:"
private const val CookieKeyPrefix = "cookie:"
