package org.mewx.wenku8_flutter.booksource

import java.util.concurrent.TimeUnit

internal class BookSourceRateLimiter(
    private val nowMillis: () -> Long = { TimeUnit.NANOSECONDS.toMillis(System.nanoTime()) },
) {
    private data class Rate(val count: Int, val millis: Int)
    private data class Window(var rate: Rate, var start: Long, var used: Int = 0)

    private val lock = Object()
    private val windows = mutableMapOf<String, Window>()

    private fun parse(value: String): Rate? {
        val count = value.substringBefore('/', "1").toIntOrNull() ?: return null
        val millis = value.substringAfter('/').toIntOrNull() ?: return null
        return if (count > 0 && millis > 0) Rate(count, millis) else null
    }

    fun update(key: String, value: String) {
        val rate = parse(value) ?: return
        synchronized(lock) {
            windows.getOrPut(key) { Window(rate, nowMillis()) }.rate = rate
            lock.notifyAll()
        }
    }

    fun clear(key: String) = synchronized(lock) {
        windows.remove(key)
        lock.notifyAll()
    }

    fun wakeWaiters() = synchronized(lock) { lock.notifyAll() }

    fun acquire(source: BookSource, checkActive: () -> Unit) {
        val configured = source.concurrentRate
        if (configured.isNullOrEmpty() || configured == "0") return
        synchronized(lock) {
            while (true) {
                checkActive()
                val now = nowMillis()
                val window = windows.getOrPut(source.key) { Window(parse(configured) ?: return, now) }
                val remaining = window.rate.millis - (now - window.start)
                if (remaining <= 0) {
                    window.start = now
                    window.used = 0
                }
                if (window.used < window.rate.count) {
                    window.used++
                    return
                }
                lock.wait(remaining)
            }
        }
    }
}
