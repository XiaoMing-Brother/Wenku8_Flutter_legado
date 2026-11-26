package org.mewx.wenku8_flutter.booksource

import java.io.InputStream
import java.security.KeyFactory
import java.security.KeyPairGenerator
import java.security.PrivateKey
import java.security.PublicKey
import java.security.Signature
import java.security.interfaces.RSAKey
import java.security.spec.PKCS8EncodedKeySpec
import java.security.spec.X509EncodedKeySpec
import javax.crypto.Cipher
import org.mozilla.javascript.Context

internal class BookSourceAsymmetricCrypto(private val algorithm: String) {
    private val keyAlgorithm = algorithm.substringBefore('/').let { name ->
        val separator = name.lowercase().lastIndexOf("with")
        if (separator >= 0) name.substring(separator + 4) else name
    }.let { if (it.equals("ECDSA", ignoreCase = true)) "EC" else it }
    private var publicKey: PublicKey
    private var privateKey: PrivateKey

    init {
        val pair = KeyPairGenerator.getInstance(keyAlgorithm).generateKeyPair()
        publicKey = pair.public
        privateKey = pair.private
    }

    fun setPrivateKey(key: ByteArray): BookSourceAsymmetricCrypto {
        privateKey = KeyFactory.getInstance(keyAlgorithm)
            .generatePrivate(PKCS8EncodedKeySpec(key))
        return this
    }

    fun setPrivateKey(key: String): BookSourceAsymmetricCrypto = setPrivateKey(key.toByteArray())

    fun setPublicKey(key: ByteArray): BookSourceAsymmetricCrypto {
        publicKey = KeyFactory.getInstance(keyAlgorithm)
            .generatePublic(X509EncodedKeySpec(key))
        return this
    }

    fun setPublicKey(key: String): BookSourceAsymmetricCrypto = setPublicKey(key.toByteArray())

    @JvmOverloads
    fun decrypt(data: Any?, usePublicKey: Boolean? = true): ByteArray =
        crypt(decryptBytes(data), usePublicKey, Cipher.DECRYPT_MODE)

    @JvmOverloads
    fun decryptStr(data: Any?, usePublicKey: Boolean? = true): String =
        String(decrypt(data, usePublicKey), Charsets.UTF_8)

    @JvmOverloads
    fun encrypt(data: Any?, usePublicKey: Boolean? = true): ByteArray =
        crypt(rawBytes(data), usePublicKey, Cipher.ENCRYPT_MODE)

    @JvmOverloads
    fun encryptHex(data: Any?, usePublicKey: Boolean? = true): String =
        encrypt(data, usePublicKey).toHex()

    @JvmOverloads
    fun encryptBase64(data: Any?, usePublicKey: Boolean? = true): String =
        java.util.Base64.getEncoder().encodeToString(encrypt(data, usePublicKey))

    @JvmOverloads
    fun decryptHex(data: String, usePublicKey: Boolean? = true): ByteArray =
        crypt(decodeHex(data), usePublicKey, Cipher.DECRYPT_MODE)

    @JvmOverloads
    fun decryptBase64(data: String, usePublicKey: Boolean? = true): ByteArray =
        crypt(java.util.Base64.getMimeDecoder().decode(data), usePublicKey, Cipher.DECRYPT_MODE)

    private fun crypt(data: ByteArray, usePublicKey: Boolean?, mode: Int): ByteArray {
        val key = if (usePublicKey == true) publicKey else privateKey
        val cipher = Cipher.getInstance(algorithm)
        cipher.init(mode, key)
        if (key !is RSAKey) return cipher.doFinal(data)
        val keySize = (key.modulus.bitLength() + 7) / 8
        val blockSize = if (mode == Cipher.DECRYPT_MODE) keySize else rsaEncryptBlockSize(keySize)
        if (data.size <= blockSize) return cipher.doFinal(data)
        return buildList<Byte> {
            var offset = 0
            while (offset < data.size) {
                addAll(
                    cipher.doFinal(data, offset, minOf(blockSize, data.size - offset)).toList(),
                )
                offset += blockSize
            }
        }.toByteArray()
    }

    private fun rsaEncryptBlockSize(keySize: Int): Int = when {
        algorithm.contains("OAEPWithSHA-512", ignoreCase = true) -> keySize - 2 * 64 - 2
        algorithm.contains("OAEPWithSHA-384", ignoreCase = true) -> keySize - 2 * 48 - 2
        algorithm.contains("OAEPWithSHA-256", ignoreCase = true) -> keySize - 2 * 32 - 2
        algorithm.contains("OAEPWithSHA-224", ignoreCase = true) -> keySize - 2 * 28 - 2
        algorithm.contains("OAEPWithSHA-1", ignoreCase = true) ||
            algorithm.contains("OAEPPadding", ignoreCase = true) -> keySize - 42
        algorithm.contains("NoPadding", ignoreCase = true) -> keySize
        else -> keySize - 11
    }

    private fun decryptBytes(value: Any?): ByteArray = when (value) {
        is String -> if (value.isHex()) decodeHex(value) else decodeBase64(value)
        else -> rawBytes(value)
    }

    private fun rawBytes(value: Any?): ByteArray = when (value) {
        is ByteArray -> value
        is String -> value.toByteArray()
        is InputStream -> value.use { it.readBytes() }
        null -> throw IllegalArgumentException("Unexpected input type")
        else -> runCatching { Context.jsToJava(value, ByteArray::class.java) as ByteArray }
            .getOrElse { throw IllegalArgumentException("Unexpected input type") }
    }

    private fun decodeBase64(value: String): ByteArray =
        java.util.Base64.getMimeDecoder().decode(value)

    private fun String.isHex(): Boolean =
        length % 2 == 0 && all { it.isDigit() || it.lowercaseChar() in 'a'..'f' }

    private fun decodeHex(value: String): ByteArray = ByteArray(value.length / 2) { index ->
        value.substring(index * 2, index * 2 + 2).toInt(16).toByte()
    }

    private fun ByteArray.toHex(): String = joinToString("") { "%02x".format(it) }
}

internal class BookSourceSign(private val algorithm: String) {
    private val keyAlgorithm = algorithm.substringBefore('/').let { name ->
        val separator = name.lowercase().lastIndexOf("with")
        val keyName = if (separator >= 0) name.substring(separator + 4) else name
        if (keyName.equals("ECDSA", ignoreCase = true)) "EC" else keyName
    }
    private var privateKey: PrivateKey? = null
    private var publicKey: PublicKey? = null

    fun setPrivateKey(key: ByteArray): BookSourceSign {
        privateKey = KeyFactory.getInstance(keyAlgorithm)
            .generatePrivate(PKCS8EncodedKeySpec(key))
        return this
    }

    fun setPrivateKey(key: String): BookSourceSign = setPrivateKey(key.toByteArray())

    fun setPublicKey(key: ByteArray): BookSourceSign {
        publicKey = KeyFactory.getInstance(keyAlgorithm)
            .generatePublic(X509EncodedKeySpec(key))
        return this
    }

    fun setPublicKey(key: String): BookSourceSign = setPublicKey(key.toByteArray())

    fun sign(data: Any?): ByteArray = Signature.getInstance(algorithm).run {
        initSign(requireNotNull(privateKey) { "Private key is required for signing" })
        update(bytes(data))
        sign()
    }

    fun signHex(data: Any?): String = sign(data).toHex()

    fun verify(data: Any?, signature: Any?): Boolean =
        Signature.getInstance(algorithm).run {
            initVerify(requireNotNull(publicKey) { "Public key is required for verification" })
            update(bytes(data))
            verify(bytes(signature))
        }

    private fun bytes(value: Any?): ByteArray = when (value) {
        is ByteArray -> value
        is String -> value.toByteArray()
        is InputStream -> value.use { it.readBytes() }
        null -> throw IllegalArgumentException("Unexpected input type")
        else -> runCatching { Context.jsToJava(value, ByteArray::class.java) as ByteArray }
            .getOrElse { throw IllegalArgumentException("Unexpected input type") }
    }

    private fun ByteArray.toHex(): String = joinToString("") { "%02x".format(it) }
}
