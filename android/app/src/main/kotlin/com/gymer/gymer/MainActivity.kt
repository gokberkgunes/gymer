package com.gymer.gymer

import android.Manifest
import android.app.NotificationManager
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
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
                "alarm" -> {
                    val at = call.argument<Number>("at")?.toLong()
                    if (at == null) {
                        result.error("rest_alarm", "No alarm time was provided.", null)
                        return@setMethodCallHandler
                    }
                    RestAlarm.schedule(this, at, call.argument<String>("title") ?: "Rest over", call.argument<String>("text") ?: "")
                    result.success(null)
                }
                "cancelAlarm" -> {
                    RestAlarm.cancel(this)
                    result.success(null)
                }
                "exactAllowed" -> result.success(RestAlarm.canScheduleExact(this))
                "requestExact" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        openSettings(Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, Uri.parse("package:$packageName")))
                    }
                    result.success(null)
                }
                "notificationsEnabled" ->
                    result.success(getSystemService(NotificationManager::class.java)?.areNotificationsEnabled() ?: false)
                "notificationSettings" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        openSettings(
                            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, packageName),
                        )
                    }
                    result.success(null)
                }
                "askNotifications" -> {
                    // Android shows its prompt at most twice; afterwards this does nothing.
                    if (Build.VERSION.SDK_INT >= 33 &&
                        checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
                    ) {
                        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1)
                    }
                    result.success(null)
                }
                "todayWidget" -> {
                    TodayWidget.store(this, call.arguments as? String ?: "{}")
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun openSettings(intent: Intent) {
        try {
            startActivity(intent)
        } catch (_: ActivityNotFoundException) {
            // Some Android builds lack the page; there is nothing else to open.
        }
    }

    companion object {
        private const val KEEP_AWAKE_STATE = "gymer.keep_screen_awake"
    }
}
