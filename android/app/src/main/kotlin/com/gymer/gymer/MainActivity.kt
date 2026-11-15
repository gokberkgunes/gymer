package com.gymer.gymer

import android.Manifest
import android.app.NotificationManager
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var keepScreenAwake = false

    // The one file dialog that is open, if any: who to answer, and what a save dialog is to write.
    private var filesResult: MethodChannel.Result? = null
    private var saveBytes: ByteArray? = null

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
        // Android's own document picker (lib/services/files.dart). "pick" answers with the file's name and
        // content, "save" writes the given bytes where the user chose; both answer null when cancelled.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "gymer/files").setMethodCallHandler { call, result ->
            if (filesResult != null) {
                result.error("files", "Another file dialog is already open.", null)
                return@setMethodCallHandler
            }
            when (call.method) {
                "pick" -> {
                    val image = call.argument<Boolean>("image") == true
                    openFileDialog(
                        Intent(if (image) Intent.ACTION_GET_CONTENT else Intent.ACTION_OPEN_DOCUMENT)
                            .addCategory(Intent.CATEGORY_OPENABLE)
                            .setType(if (image) "image/*" else "*/*"),
                        PICK_FILE,
                        result,
                    )
                }
                "save" -> {
                    saveBytes = call.argument<ByteArray>("bytes")
                    openFileDialog(
                        Intent(Intent.ACTION_CREATE_DOCUMENT)
                            .addCategory(Intent.CATEGORY_OPENABLE)
                            .setType(call.argument<String>("mime") ?: "application/octet-stream")
                            .putExtra(Intent.EXTRA_TITLE, call.argument<String>("name") ?: "gymer"),
                        SAVE_FILE,
                        result,
                    )
                }
                else -> result.notImplemented()
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

    private fun openFileDialog(intent: Intent, request: Int, result: MethodChannel.Result) {
        filesResult = result
        try {
            startActivityForResult(intent, request)
        } catch (_: ActivityNotFoundException) {
            filesResult = null
            saveBytes = null
            result.error("files", "No app on this phone can choose files.", null)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != PICK_FILE && requestCode != SAVE_FILE) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }
        val result = filesResult ?: return
        val bytes = saveBytes
        filesResult = null
        saveBytes = null
        val uri = data?.data
        if (resultCode != RESULT_OK || uri == null) {
            result.success(null)
            return
        }
        // Off the main thread: a photo or a long history takes a moment to copy.
        Thread {
            try {
                val answer: Any = if (requestCode == PICK_FILE) {
                    val content = contentResolver.openInputStream(uri)?.use { it.readBytes() }
                        ?: throw java.io.IOException("The file could not be opened.")
                    mapOf("name" to displayName(uri), "bytes" to content)
                } else {
                    (contentResolver.openOutputStream(uri) ?: throw java.io.IOException("The file could not be created."))
                        .use { it.write(bytes ?: ByteArray(0)) }
                    true
                }
                runOnUiThread { result.success(answer) }
            } catch (e: Exception) {
                // Do not leave an empty file behind where a save failed.
                if (requestCode == SAVE_FILE) {
                    try {
                        DocumentsContract.deleteDocument(contentResolver, uri)
                    } catch (_: Exception) {
                    }
                }
                runOnUiThread { result.error("files", e.message ?: "The file could not be used.", null) }
            }
        }.start()
    }

    private fun displayName(uri: Uri): String {
        try {
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
                if (c.moveToFirst() && !c.isNull(0)) return c.getString(0)
            }
        } catch (_: Exception) {
        }
        return uri.lastPathSegment ?: ""
    }

    private fun openSettings(intent: Intent) {
        try {
            startActivity(intent)
        } catch (_: ActivityNotFoundException) {
            // Some Android builds lack the page; there is nothing else to open.
        }
    }

    companion object {
        private const val PICK_FILE = 4101
        private const val SAVE_FILE = 4102
        private const val KEEP_AWAKE_STATE = "gymer.keep_screen_awake"
    }
}
