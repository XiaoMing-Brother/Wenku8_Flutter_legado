package org.mewx.wenku8_flutter.booksource

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.InputStream
import java.nio.ByteBuffer
import java.nio.charset.StandardCharsets
import java.util.zip.ZipEntry
import java.util.zip.ZipInputStream
import me.zhanghai.android.libarchive.Archive
import me.zhanghai.android.libarchive.ArchiveEntry
import okio.Buffer

/**
 * 书源压缩包接口。
 *
 * zip 使用 JDK 实现，rar/7z 使用与上游 Legado 相同的 libarchive。
 * 解压时统一校验目标路径，拒绝压缩包内的目录穿越。
 */
internal object BookSourceArchive {
    private const val BufferSize = 32 * 1024

    fun extract(file: File, destination: File): Boolean {
        if (!file.isFile) return false
        destination.mkdirs()
        return when (file.extension.lowercase()) {
            "rar", "7z" -> extractLibArchive(file, destination)
            else -> extractZip(file, destination)
        }
    }

    fun entryBytes(bytes: ByteArray, path: String, rarOr7z: Boolean): ByteArray? {
        if (rarOr7z) {
            return ByteArrayInputStream(bytes).use { input ->
                libArchiveEntry(input, path)
            }
        }
        return zipEntry(bytes, path)
    }

    private fun extractZip(file: File, destination: File): Boolean {
        val root = destination.canonicalFile.toPath()
        return runCatching {
            ZipInputStream(file.inputStream().buffered()).use { input ->
                var entry: ZipEntry? = input.nextEntry
                while (entry != null) {
                    val target = safeTarget(destination, root, entry.name)
                    if (target != null) {
                        if (entry.isDirectory) {
                            target.mkdirs()
                        } else {
                            target.parentFile?.mkdirs()
                            target.outputStream().buffered().use { output -> input.copyTo(output) }
                        }
                    }
                    input.closeEntry()
                    entry = input.nextEntry
                }
            }
            true
        }.getOrDefault(false)
    }

    private fun safeTarget(destination: File, root: java.nio.file.Path, name: String): File? {
        if (name.isBlank() || name.contains("..")) return null
        val target = File(destination, name).canonicalFile
        if (!target.toPath().startsWith(root)) return null
        return target
    }

    private fun zipEntry(bytes: ByteArray, path: String): ByteArray? {
        ZipInputStream(ByteArrayInputStream(bytes)).use { input ->
            var entry = input.nextEntry
            while (entry != null) {
                if (!entry.isDirectory && entry.name == path) {
                    return input.readBytes()
                }
                input.closeEntry()
                entry = input.nextEntry
            }
        }
        return null
    }

    private fun extractLibArchive(file: File, destination: File): Boolean {
        val archive = openArchive(file.inputStream())
        try {
            val root = destination.canonicalFile.toPath()
            var entry: Long
            while (Archive.readNextHeader(archive).also { entry = it } != 0L) {
                val name = entryName(entry) ?: continue
                val target = safeTarget(destination, root, name) ?: continue
                val stat = ArchiveEntry.stat(entry)
                if (stat.isDir()) {
                    target.mkdirs()
                    continue
                }
                target.parentFile?.mkdirs()
                target.outputStream().buffered().use { output ->
                    val buffer = ByteBuffer.allocateDirect(BufferSize)
                    while (true) {
                        Archive.readData(archive, buffer)
                        buffer.flip()
                        if (!buffer.hasRemaining()) break
                        val chunk = ByteArray(buffer.remaining())
                        buffer.get(chunk)
                        output.write(chunk)
                        buffer.clear()
                    }
                }
            }
            return true
        } catch (_: Throwable) {
            return false
        } finally {
            Archive.free(archive)
        }
    }

    private fun libArchiveEntry(input: InputStream, path: String): ByteArray? {
        val archive = openArchive(input)
        try {
            var entry: Long
            while (Archive.readNextHeader(archive).also { entry = it } != 0L) {
                val name = entryName(entry) ?: continue
                if (ArchiveEntry.stat(entry).isDir() || name != path) continue
                val buffer = ByteBuffer.allocateDirect(BufferSize)
                val result = Buffer()
                while (true) {
                    Archive.readData(archive, buffer)
                    buffer.flip()
                    if (!buffer.hasRemaining()) break
                    result.write(buffer)
                    buffer.clear()
                }
                return result.readByteArray()
            }
        } catch (_: Throwable) {
            return null
        } finally {
            Archive.free(archive)
        }
        return null
    }

    private fun openArchive(input: InputStream): Long {
        val archive = Archive.readNew()
        var successful = false
        try {
            Archive.setCharset(archive, StandardCharsets.UTF_8.name().toByteArray())
            Archive.readSupportFilterAll(archive)
            Archive.readSupportFormatAll(archive)
            Archive.readSetCallbackData(archive, null)
            val buffer = ByteBuffer.allocate(BufferSize)
            Archive.readSetReadCallback<Any?>(archive) { _, _ ->
                buffer.clear()
                val read = input.read(buffer.array())
                if (read == -1) {
                    null
                } else {
                    buffer.limit(read)
                    buffer
                }
            }
            Archive.readSetSkipCallback<Any?>(archive) { _, _, request ->
                input.skip(request)
            }
            Archive.readOpen1(archive)
            successful = true
            return archive
        } finally {
            if (!successful) Archive.free(archive)
        }
    }

    private fun entryName(entry: Long): String? {
        val utf8 = ArchiveEntry.pathnameUtf8(entry)
        if (!utf8.isNullOrBlank()) return utf8
        val raw = ArchiveEntry.pathname(entry) ?: return null
        val charset = BookSourceFiles.detectCharset(raw) ?: StandardCharsets.UTF_8
        return String(raw, charset)
    }

    private fun ArchiveEntry.StructStat.isDir(): Boolean =
        (stMode and 0xF000) == 0x4000
}
