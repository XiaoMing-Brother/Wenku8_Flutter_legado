package org.mewx.wenku8_flutter.booksource

import java.io.File
import java.nio.charset.Charset
import java.security.MessageDigest
import org.mozilla.universalchardet.UniversalDetector

/**
 * 书源脚本的文件操作目录。
 *
 * Legado 的 java.readTxtFile/downloadFile 等只允许访问阅读缓存目录；
 * 这里把根目录固定在应用 cache/book_sources 下，并拒绝 .. 与越界路径。
 */
internal class BookSourceFiles(private val root: File?) {
    fun resolve(path: String): File? {
        val base = root ?: return null
        val raw = path.trim().replace('\\', '/')
        if (raw.isEmpty()) return null
        val relative = raw.trimStart('/')
        if (relative.split('/').any { it == ".." }) return null
        val file = File(base, relative)
        val rootPath = base.canonicalPath
        val target = file.canonicalPath
        if (target != rootPath && !target.startsWith(rootPath + File.separator)) return null
        return file
    }

    fun relative(file: File): String {
        val base = root ?: return file.path
        return "/" + file.relativeTo(base).path.replace('\\', '/')
    }

    fun write(path: String, bytes: ByteArray): File? {
        val file = resolve(path) ?: return null
        file.parentFile?.mkdirs()
        file.writeBytes(bytes)
        return file
    }

    fun readBytes(path: String): ByteArray? {
        val file = resolve(path) ?: return null
        return if (file.isFile) file.readBytes() else null
    }

    fun readText(path: String, charset: String? = null): String {
        val bytes = readBytes(path) ?: return ""
        val name = charset?.takeIf { it.isNotBlank() }?.let {
            runCatching { Charset.forName(it) }.getOrNull()
        } ?: detectCharset(bytes) ?: Charsets.UTF_8
        return String(bytes, name)
    }

    fun delete(path: String): Boolean {
        val file = resolve(path) ?: return false
        if (!file.exists()) return false
        return if (file.isDirectory) file.deleteRecursively() else file.delete()
    }

    fun textInFolder(path: String): String {
        val folder = resolve(path) ?: return ""
        if (!folder.isDirectory) return ""
        val text = folder.listFiles()
            .orEmpty()
            .sortedBy { it.name }
            .filter { it.isFile }
            .joinToString("\n") { readText(it.path) }
        folder.deleteRecursively()
        return text
    }

    fun tempFolder(name: String): File? {
        val base = root ?: return null
        val folder = File(base, "temp/${md5(name)}")
        folder.mkdirs()
        return folder
    }

    fun tempRelative(name: String): String = "/temp/${md5(name)}"

    fun fileForDownload(url: String, suffix: String): File? {
        val base = root ?: return null
        base.mkdirs()
        val type = suffix.trim().trimStart('.').ifBlank { "bin" }
        return File(base, "${md5(url)}.$type")
    }

    fun downloadRelative(url: String, suffix: String): String {
        val file = fileForDownload(url, suffix) ?: return ""
        return relative(file)
    }

    companion object {
        fun md5(value: String): String =
            MessageDigest.getInstance("MD5")
                .digest(value.toByteArray())
                .joinToString("") { "%02x".format(it) }

        fun detectCharset(bytes: ByteArray): Charset? {
            val detector = UniversalDetector()
            detector.handleData(bytes, 0, bytes.size)
            detector.dataEnd()
            val name = detector.detectedCharset ?: return null
            return runCatching { Charset.forName(name) }.getOrNull()
        }
    }
}
