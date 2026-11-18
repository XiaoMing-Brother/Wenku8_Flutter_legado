package org.mewx.wenku8_flutter.booksource

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.IOException
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import org.json.JSONObject
import org.mozilla.javascript.RhinoException

/**
 * Executes Legado dictionary rules with the same URL/rule engine as book
 * sources. Only an explicit reader lookup reaches this plugin.
 */
class DictRulePlugin : FlutterPlugin {
    private var channel: MethodChannel? = null
    private var executor: ExecutorService? = null
    private val main = Handler(Looper.getMainLooper())
    private val http = BookSourceHttp()
    private val js = BookSourceJs(http)

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val worker = Executors.newFixedThreadPool(4)
        executor = worker
        channel = MethodChannel(binding.binaryMessenger, ChannelName).also {
            it.setMethodCallHandler { call, result ->
                handle(worker, call, result)
            }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        executor?.shutdownNow()
        executor = null
    }

    private fun handle(
        worker: ExecutorService,
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val arguments = call.arguments as? Map<*, *> ?: emptyMap<Any?, Any?>()
        when (call.method) {
            "available" -> result.success(true)
            "lookup" -> worker.execute {
                try {
                    val value = lookup(
                        name = stringArg(arguments, "name"),
                        urlRule = stringArg(arguments, "urlRule"),
                        showRule = arguments["showRule"]?.toString().orEmpty(),
                        key = stringArg(arguments, "key"),
                    )
                    main.post { result.success(value) }
                } catch (error: Throwable) {
                    val message = message(error)
                    main.post { result.error("DICT_RULE_ERROR", message, null) }
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun lookup(
        name: String,
        urlRule: String,
        showRule: String,
        key: String,
    ): String {
        if (name.isBlank() || urlRule.isBlank() || key.isBlank()) {
            throw IllegalArgumentException("字典规则缺少名称、地址或关键词")
        }
        val source = BookSource.from(
            JSONObject()
                .put("bookSourceUrl", "dict://$name")
                .put("bookSourceName", name),
        )
        val analyzer = BookSourceAnalyzer(source, http, js)
        val expanded = analyzer.expand(urlRule, key = key)
        val spec = http.requestSpec(source.key, expanded)
        val response = http.fetch(source, spec)
        if (showRule.isBlank()) return response.text
        return analyzer.getString(
            showRule,
            RuleContext(
                content = response.text,
                baseUrl = response.url,
                key = key,
            ),
        )
    }

    private fun message(error: Throwable): String = when (error) {
        is IllegalArgumentException, is IllegalStateException ->
            error.message ?: "字典规则参数有误"
        is IOException -> "字典网络请求失败：${error.message ?: "请稍后重试"}"
        is RhinoException -> "字典规则脚本执行失败：${error.message ?: "请检查提取规则"}"
        else -> error.message ?: error.javaClass.simpleName
    }

    private fun stringArg(arguments: Map<*, *>, key: String): String =
        arguments[key]?.toString()?.trim().orEmpty()

    companion object {
        const val ChannelName = "org.mewx.wenku8/dict_rules"
    }
}
