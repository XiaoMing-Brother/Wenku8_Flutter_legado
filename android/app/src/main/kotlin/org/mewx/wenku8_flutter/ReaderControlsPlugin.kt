package org.mewx.wenku8_flutter

import android.app.Activity
import android.view.KeyEvent
import android.view.View
import android.provider.Settings
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import androidx.core.content.ContextCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel

class ReaderControlsPlugin : FlutterPlugin, ActivityAware {
    private var channel: MethodChannel? = null
    private var activity: Activity? = null
    private var volumePaging = false
    private var previousKeys = emptySet<Int>()
    private var nextKeys = emptySet<Int>()
    private var capture: MethodChannel.Result? = null
    private var captureCode: Int? = null

    private fun finishCapture(code: Int? = null) {
        val result = capture
        capture = null
        captureCode = null
        result?.success(code)
    }

    private fun bindable(code: Int) = code > 0 && !KeyEvent.isModifierKey(code) && code !in setOf(
        KeyEvent.KEYCODE_BACK, KeyEvent.KEYCODE_HOME, KeyEvent.KEYCODE_POWER, KeyEvent.KEYCODE_APP_SWITCH,
        KeyEvent.KEYCODE_DEL, KeyEvent.KEYCODE_ESCAPE, KeyEvent.KEYCODE_CALL, KeyEvent.KEYCODE_ENDCALL
    )
    private var lastPage = 0L
    private var statusEvents: EventChannel? = null
    private var statusReceiver: BroadcastReceiver? = null
    private var applicationContext: Context? = null
    private fun stopStatusEvents() {
        statusReceiver?.let { applicationContext?.unregisterReceiver(it) }
        statusReceiver = null
    }
    private fun status(context: Context): Map<String, Any?> {
        val battery = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val level = battery?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = battery?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
        val state = battery?.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
        return mapOf("time" to System.currentTimeMillis(), "battery" to if (level >= 0 && scale > 0) level * 100 / scale else null,
            "charging" to (state == BatteryManager.BATTERY_STATUS_CHARGING || state == BatteryManager.BATTERY_STATUS_FULL))
    }
    private fun hideStatusBar(hidden: Boolean) {
        activity?.window?.let { window ->
            ReaderWindowLayout.apply(window)
            val controller = WindowCompat.getInsetsController(window, window.decorView)
            controller.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            if (hidden) controller.hide(WindowInsetsCompat.Type.statusBars())
            else controller.show(WindowInsetsCompat.Type.statusBars())
        }
    }
    private fun hideNavigationBar(hidden: Boolean) {
        activity?.window?.let { window ->
            val controller = WindowCompat.getInsetsController(window, window.decorView)
            controller.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            if (hidden) controller.hide(WindowInsetsCompat.Type.navigationBars())
            else controller.show(WindowInsetsCompat.Type.navigationBars())
        }
    }
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = binding.applicationContext
        statusEvents = EventChannel(binding.binaryMessenger, "org.mewx.wenku8/reader_status").also { events ->
            events.setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
                    stopStatusEvents()
                    val context = binding.applicationContext
                    statusReceiver = object : BroadcastReceiver() {
                        override fun onReceive(context: Context, intent: Intent?) { sink.success(status(context)) }
                    }.also { receiver ->
                        ContextCompat.registerReceiver(context, receiver, IntentFilter().apply {
                            addAction(Intent.ACTION_BATTERY_CHANGED); addAction(Intent.ACTION_TIME_TICK)
                            addAction(Intent.ACTION_TIME_CHANGED); addAction(Intent.ACTION_TIMEZONE_CHANGED)
                        }, ContextCompat.RECEIVER_NOT_EXPORTED)
                    }
                    sink.success(status(context))
                }
                override fun onCancel(arguments: Any?) = stopStatusEvents()
            })
        }
        channel = MethodChannel(binding.binaryMessenger, "org.mewx.wenku8/reader_controls").also {
            it.setMethodCallHandler { call, result ->
                if (call.method == "navigationCapabilities") {
                    result.success(mapOf("systemFloatingNavigation" to android.os.Build.MANUFACTURER.equals("HUAWEI", true)))
                    return@setMethodCallHandler
                }
                if (call.method == "navigationSettings") {
                    try {
                        val context = activity ?: applicationContext ?: error("No context")
                        context.startActivity(Intent(Settings.ACTION_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                        result.success(null)
                    } catch (_: Exception) { result.error("SETTINGS", "请在手机设置中搜索悬浮导航", null) }
                    return@setMethodCallHandler
                }
                if (call.method == "windowInsets") {
                    val view = activity?.findViewById<View>(FlutterActivity.FLUTTER_VIEW_ID)
                    result.success(view?.let(CaptionBarInsets::read))
                    return@setMethodCallHandler
                }
                if (call.method == "brightness") {
                    val current = activity
                    if (current == null) { result.error("NO_ACTIVITY", "阅读页面未显示", null); return@setMethodCallHandler }
                    val windowValue = current.window.attributes.screenBrightness
                    val value = if (windowValue >= 0f) windowValue else
                        Settings.System.getInt(current.contentResolver, Settings.System.SCREEN_BRIGHTNESS, 128) / 255f
                    result.success(value.coerceIn(0f, 1f).toDouble()); return@setMethodCallHandler
                }
                if (call.method == "capturePageKey") {
                    finishCapture()
                    if (activity?.hasWindowFocus() == true) capture = result else result.success(null)
                    return@setMethodCallHandler
                }
                if (call.method == "cancelPageKeyCapture") {
                    finishCapture(); result.success(null); return@setMethodCallHandler
                }
                if (call.method != "apply") { result.notImplemented(); return@setMethodCallHandler }
                volumePaging = call.argument<Boolean>("volumePaging") == true
                previousKeys = call.argument<List<Int>>("previousKeys").orEmpty().filter(::bindable).toSet()
                nextKeys = call.argument<List<Int>>("nextKeys").orEmpty().filter(::bindable).toSet()
                val brightness = call.argument<Number>("brightness")?.toFloat() ?: -1f
                if (brightness != -1f && brightness !in 0f..1f) {
                    result.error("brightness", "阅读亮度超出范围", null); return@setMethodCallHandler
                }
                activity?.window?.let { window -> val attrs = window.attributes; attrs.screenBrightness = brightness; window.attributes = attrs }
                hideStatusBar(call.argument<Boolean>("hideStatusBar") == true)
                hideNavigationBar(call.argument<Boolean>("hideNavigation") ?: true)
                result.success(null)
            }
        }
    }
    fun dispatch(event: KeyEvent): Boolean {
        if (activity?.hasWindowFocus() != true || !bindable(event.keyCode) || !event.hasNoModifiers()) return false
        if (capture != null) {
            if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) captureCode = event.keyCode
            if (event.action == KeyEvent.ACTION_UP && captureCode == event.keyCode) finishCapture(event.keyCode)
            return true
        }
        val direction = when {
            event.keyCode in previousKeys -> -1
            event.keyCode in nextKeys -> 1
            volumePaging && event.keyCode == KeyEvent.KEYCODE_VOLUME_UP -> -1
            volumePaging && event.keyCode == KeyEvent.KEYCODE_VOLUME_DOWN -> 1
            else -> return false
        }
        if (event.action == KeyEvent.ACTION_DOWN && (event.repeatCount == 0 || event.eventTime - lastPage >= 160)) {
            lastPage = event.eventTime
            channel?.invokeMethod("page", direction)
        }
        return true
    }
    fun suspend() {
        finishCapture()
        previousKeys = emptySet()
        nextKeys = emptySet()
        volumePaging = false
        hideStatusBar(false)
        hideNavigationBar(false)
        activity?.window?.let { window -> val attrs = window.attributes; attrs.screenBrightness = -1f; window.attributes = attrs }
    }
    override fun onAttachedToActivity(binding: ActivityPluginBinding) { activity = binding.activity }
    override fun onDetachedFromActivity() { suspend(); activity = null }
    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) { suspend(); stopStatusEvents(); statusEvents?.setStreamHandler(null); statusEvents = null; applicationContext = null; channel?.setMethodCallHandler(null); channel = null }
}
