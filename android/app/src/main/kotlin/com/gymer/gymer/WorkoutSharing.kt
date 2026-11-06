package com.gymer.gymer

import android.app.Activity
import android.content.ClipData
import android.content.Intent
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

class WorkoutShareProvider : FileProvider()

/** Shares an app-cache image through Android's chooser, without a gallery copy or storage permission. */
object WorkoutSharing {
    private val writer = Executors.newSingleThreadExecutor()

    fun share(activity: Activity, png: ByteArray, title: String, result: MethodChannel.Result) {
        writer.execute {
            try {
                val directory = File(activity.cacheDir, "workout-shares")
                check(directory.isDirectory || directory.mkdirs()) { "Could not prepare sharing." }
                val cutoff = System.currentTimeMillis() - 24 * 60 * 60 * 1000L
                directory.listFiles()?.filter { it.isFile && it.name.endsWith(".png") && it.lastModified() < cutoff }
                    ?.forEach { it.delete() }
                // A fresh file for every share: a receiving app may still be reading an earlier image.
                val image = File.createTempFile("gymer-", ".png", directory)
                image.writeBytes(png)
                val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.workout_share", image)
                val send = Intent(Intent.ACTION_SEND).apply {
                    type = "image/png"
                    putExtra(Intent.EXTRA_STREAM, uri)
                    putExtra(Intent.EXTRA_TITLE, title)
                    clipData = ClipData.newUri(activity.contentResolver, title, uri)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
                activity.runOnUiThread {
                    try {
                        check(!activity.isFinishing && !activity.isDestroyed) { "Sharing was canceled." }
                        activity.startActivity(Intent.createChooser(send, "Share workout"))
                        result.success(null)
                    } catch (_: Exception) {
                        result.error("share_unavailable", "Could not open the share sheet.", null)
                    }
                }
            } catch (_: Exception) {
                activity.runOnUiThread { result.error("share_image", "Could not prepare the workout image.", null) }
            }
        }
    }
}
