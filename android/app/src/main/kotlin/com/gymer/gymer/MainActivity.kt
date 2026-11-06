package com.gymer.gymer

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "gymer/live_timer").setMethodCallHandler { call, result ->
            when (call.method) {
                "show" -> {
                    LiveTimer.show(
                        this,
                        call.argument<Number>("endsAt")!!.toLong(),
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
