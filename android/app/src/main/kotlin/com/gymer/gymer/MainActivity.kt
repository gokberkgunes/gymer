package com.gymer.gymer

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
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
                else -> result.notImplemented()
            }
        }
    }
}
