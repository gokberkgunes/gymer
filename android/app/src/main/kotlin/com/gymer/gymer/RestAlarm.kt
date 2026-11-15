package com.gymer.gymer

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

/**
 * The optional "Rest over" alarm: a sounding, vibrating notification posted by Android's alarm clock at the
 * moment rest ends, so it also fires on a locked phone after the app process is gone.
 */
object RestAlarm {
    // The channel the app has always used, so the sound a user chose for it in Android's settings stays.
    private const val CHANNEL = "rest"
    private const val ID = 1

    fun canScheduleExact(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
        return context.getSystemService(AlarmManager::class.java)?.canScheduleExactAlarms() ?: false
    }

    private fun intent(context: Context, title: String = "", text: String = "") = PendingIntent.getBroadcast(
        context,
        ID,
        Intent(context, RestAlarmReceiver::class.java).putExtra("title", title).putExtra("text", text),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )

    /** At the exact second when Android allows it; otherwise as close as Android chooses. */
    fun schedule(context: Context, at: Long, title: String, text: String) {
        val app = context.applicationContext
        val alarms = app.getSystemService(AlarmManager::class.java) ?: return
        val intent = intent(app, title, text)
        if (canScheduleExact(app)) {
            alarms.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, intent)
        } else {
            alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, intent)
        }
    }

    /** Removes both a waiting alarm and one that is already showing. */
    fun cancel(context: Context) {
        val app = context.applicationContext
        app.getSystemService(AlarmManager::class.java)?.cancel(intent(app))
        app.getSystemService(NotificationManager::class.java)?.cancel(ID)
    }

    @Suppress("DEPRECATION")
    fun post(context: Context, title: String, text: String) {
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            if (manager.getNotificationChannel(CHANNEL) == null) {
                manager.createNotificationChannel(
                    NotificationChannel(CHANNEL, "Rest timer", NotificationManager.IMPORTANCE_HIGH).apply {
                        description = "Alerts when a rest period ends"
                        enableVibration(true)
                    },
                )
            }
            Notification.Builder(context, CHANNEL)
        } else {
            Notification.Builder(context).setPriority(Notification.PRIORITY_HIGH).setDefaults(Notification.DEFAULT_ALL)
        }
        val open = PendingIntent.getActivity(
            context,
            0,
            Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        manager.notify(
            ID,
            builder
                // Status-bar icons must be monochrome; the coloured launcher icon would show as a blob.
                .setSmallIcon(R.drawable.ic_stat_timer)
                .setContentTitle(title)
                .setContentText(text)
                .setContentIntent(open)
                .setCategory(Notification.CATEGORY_ALARM)
                .setAutoCancel(true)
                .setShowWhen(true)
                .build(),
        )
    }
}

/** Fires when rest ends, whether or not the app process is still alive. */
class RestAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        RestAlarm.post(
            context,
            intent.getStringExtra("title") ?: "Rest over",
            intent.getStringExtra("text") ?: "",
        )
    }
}
