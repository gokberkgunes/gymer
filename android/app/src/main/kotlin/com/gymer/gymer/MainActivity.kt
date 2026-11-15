package com.gymer.gymer

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var keepScreenAwake = false

    override fun onCreate(savedInstanceState: Bundle?) {
        keepScreenAwake = savedInstanceState?.getBoolean(KEEP_AWAKE_STATE) ?: false
        super.onCreate(savedInstanceState)
        applyKeepScreenAwake()
    }

    override fun onSaveInstanceState(outState: Bundle) {
        outState.putBoolean(KEEP_AWAKE_STATE, keepScreenAwake)
        super.onSaveInstanceState(outState)
    }

    private fun applyKeepScreenAwake() {
        if (keepScreenAwake) {
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "gymer/share").setMethodCallHandler { call, result ->
            if (call.method != "image") {
                result.notImplemented()
            } else {
                val png = call.argument<ByteArray>("png")
                if (png == null || png.isEmpty()) {
                    result.error("share_image", "No workout image was provided.", null)
                } else {
                    WorkoutSharing.share(this, png, call.argument<String>("title") ?: "Workout", result)
                }
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "gymer/live_timer").setMethodCallHandler { call, result ->
            when (call.method) {
                "keepAwake" -> {
                    keepScreenAwake = call.arguments == true
                    applyKeepScreenAwake()
                    result.success(null)
                }
                "show" -> {
                    val endsAt = call.argument<Number>("endsAt")?.toLong()
                    if (endsAt == null) {
                        result.error("live_timer", "No end time was provided.", null)
                        return@setMethodCallHandler
                    }
                    LiveTimer.show(
                        this,
                        endsAt,
                        call.argument<String>("title") ?: "Rest",
                        call.argument<String>("text") ?: "",
                        call.argument<Boolean>("endAtZero") ?: false,
                        call.argument<String>("icon") ?: "muscle",
                        call.argument<String>("overtimeIcon") ?: "warning",
                        call.argument<String>("chipText") ?: "",
                        call.argument<Boolean>("vibrate") ?: false,
                    )
                    result.success(null)
                }
                "clear" -> {
                    LiveTimer.clear(this)
                    result.success(null)
                }
                "filesDir" -> result.success(filesDir.path)
                "todayWidget" -> {
                    TodayWidget.store(this, call.arguments as? String ?: "{}")
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    companion object {
        private const val KEEP_AWAKE_STATE = "gymer.keep_screen_awake"
    }
}
