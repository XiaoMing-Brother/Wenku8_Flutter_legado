package org.mewx.wenku8_flutter.booksource

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/// 登录信息和 Cookie 使用 Android Keystore 加密后落盘。书源变量本身
/// 可能包含筛选条件，仍保留在普通 SharedPreferences 中。
internal class BookSourceSecretStore(context: Context) {
    private val preferences = context.getSharedPreferences(
        "wenku8-book-source-secrets",
        Context.MODE_PRIVATE,
    )

    fun get(key: String): String? {
        val encoded = preferences.getString(storageKey(key), null) ?: return null
        return runCatching {
            val data = Base64.decode(encoded, Base64.NO_WRAP)
            if (data.size <= IvBytes) return@runCatching null
            val iv = data.copyOfRange(0, IvBytes)
            val encrypted = data.copyOfRange(IvBytes, data.size)
            val cipher = Cipher.getInstance(Transformation)
            cipher.init(
                Cipher.DECRYPT_MODE,
                secretKey(),
                GCMParameterSpec(TagBits, iv),
            )
            String(cipher.doFinal(encrypted), Charsets.UTF_8)
        }.getOrNull()
    }

    fun put(key: String, value: String) {
        if (value.isBlank()) {
            remove(key)
            return
        }
        val cipher = Cipher.getInstance(Transformation)
        cipher.init(Cipher.ENCRYPT_MODE, secretKey())
        val encrypted = cipher.doFinal(value.toByteArray(Charsets.UTF_8))
        val data = cipher.iv + encrypted
        preferences.edit()
            .putString(
                storageKey(key),
                Base64.encodeToString(data, Base64.NO_WRAP),
            )
            .apply()
    }

    fun remove(key: String) {
        preferences.edit().remove(storageKey(key)).apply()
    }

    private fun secretKey(): SecretKey = synchronized(this) {
        val keyStore = KeyStore.getInstance(AndroidKeyStore).apply {
            load(null)
        }
        (keyStore.getKey(KeyAlias, null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES,
            AndroidKeyStore,
        )
        generator.init(
            KeyGenParameterSpec.Builder(
                KeyAlias,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .build(),
        )
        generator.generateKey()
    }

    private fun storageKey(key: String): String =
        "${Integer.toHexString(key.hashCode())}:${key.takeLast(64)}"

    companion object {
        private const val AndroidKeyStore = "AndroidKeyStore"
        private const val KeyAlias = "wenku-book-source-secrets-v1"
        private const val Transformation = "AES/GCM/NoPadding"
        private const val IvBytes = 12
        private const val TagBits = 128
    }
}
