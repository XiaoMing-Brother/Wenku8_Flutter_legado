package org.mewx.wenku8_flutter.booksource

import java.io.File
import java.io.InputStream
import java.util.UUID

internal object BookSourceResourceFiles {
    private const val Limit = 128L * 1024 * 1024
    private val formats = mapOf(
        "mp3" to "audio/mpeg", "wav" to "audio/wav", "m4a" to "audio/mp4", "ogg" to "audio/ogg", "flac" to "audio/flac",
        "mp4" to "video/mp4", "webm" to "video/webm", "mkv" to "video/x-matroska",
        "pdf" to "application/pdf", "epub" to "application/epub+zip", "txt" to "text/plain",
    )

    fun mime(file: File): String = formats[file.extension] ?: error("不支持的资源格式")

    @Synchronized fun save(directory: File, kind: Int, mime: String?, suffix: String, length: Long, input: InputStream): File {
        val allowed = formats.filterValues { when (kind) {
            1 -> it.startsWith("audio/")
            4 -> it.startsWith("video/")
            3 -> it.startsWith("application/") || it == "text/plain"
            else -> false
        } }
        val normalized = when (mime) { "audio/x-wav", "audio/wave" -> "audio/wav"; else -> mime }
        val extension = allowed.entries.firstOrNull { it.value == normalized }?.key
            ?: suffix.takeIf { (normalized == null || normalized == "application/octet-stream") && it in allowed }
            ?: error("暂不支持此资源格式，仅支持音视频直链及 PDF、EPUB、TXT 文件")
        require(length != 0L && length <= Limit) { "资源为空或超过 128 MB" }
        check(directory.isDirectory || directory.mkdirs()) { "无法创建资源缓存" }
        val existing = directory.listFiles().orEmpty()
        val cutoff = System.currentTimeMillis() - TimeUnitDay
        existing.filter { it.isFile && it.lastModified() < cutoff }.forEach { it.delete() }
        val available = minOf(Limit, 2 * Limit - directory.listFiles().orEmpty().sumOf { it.length() })
        require(available > 0 && length <= available) { "资源缓存空间不足" }
        val file = File(directory, "${UUID.randomUUID()}.$extension")
        try {
            file.outputStream().buffered().use { output ->
                val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                var total = 0L
                while (true) {
                    val count = input.read(buffer)
                    if (count == -1) break
                    total += count
                    check(total <= available) { "资源超过缓存大小限制" }
                    output.write(buffer, 0, count)
                }
                check(total > 0 && (length < 0 || length == total)) { "资源下载不完整" }
            }
            return file
        } catch (error: Exception) {
            file.delete()
            throw error
        }
    }

    private const val TimeUnitDay = 24L * 60 * 60 * 1000
}
