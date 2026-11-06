package com.gymer.gymer

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.VibrationAttributes
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager

/**
 * The rest timer shown outside the app: an ongoing notification whose chronometer is ticked by Android
 * itself, so it keeps running when the app is backgrounded. On Android 16+ it asks to be promoted to a
 * Live Update, which shows the time as a chip in the status bar next to the clock.
 *
 * The status-bar chip does not display negative time, so when rest ends the notification is re-posted as
 * a count-up of the overtime. That switch is triggered by a handler while the app process is alive
 * (exact) and by an alarm as a backup if Android has stopped the process. The timer's details are kept
 * in SharedPreferences so the alarm can rebuild the notification without the app.
 */
object LiveTimer {
    // Channel settings are fixed once created, so a changed channel needs a new id.
    private const val CHANNEL = "rest_live_v2"
    private const val ID = 2
    private const val PREFS = "live_timer"
    private const val OVERTIME_LIMIT = 30 * 60 * 1000L

    // Android 16 extras, by name so older compile SDKs still build: EXTRA_REQUEST_PROMOTED_ONGOING, and
    // EXTRA_SHORT_CRITICAL_TEXT, a short label the status-bar chip shows instead of the time.
    private const val EXTRA_REQUEST_PROMOTED_ONGOING = "android.requestPromotedOngoing"
    private const val EXTRA_SHORT_CRITICAL_TEXT = "android.shortCriticalText"

    private val handler = Handler(Looper.getMainLooper())

    /**
     * [endAtZero]: remove the timer the moment rest ends, because the "Rest over" alarm notification takes
     * its place (one notification at a time). Otherwise it switches to counting the overtime.
     */
    fun show(
        context: Context,
        endsAt: Long,
        title: String,
        text: String,
        endAtZero: Boolean,
        icon: String,
        overtimeIcon: String,
        chipText: String,
        vibrate: Boolean,
    ) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val app = context.applicationContext
        app.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putLong("endsAt", endsAt)
            .putString("title", title)
            .putString("text", text)
            .putString("icon", icon)
            .putString("overtimeIcon", overtimeIcon)
            .putString("chipText", chipText)
            .putBoolean("vibrate", vibrate)
            .apply()
        val now = System.currentTimeMillis()
        cancelOvertimeSwitch(app)
        if (endAtZero) {
            post(app, endsAt, title, text, restIcon(app, icon), overtime = false, timeout = maxOf(1L, endsAt - now))
        } else if (now >= endsAt) {
            switchToOvertime(app, endsAt, buzz = false) // rest already ended earlier; no late buzz
        } else {
            post(app, endsAt, title, text, restIcon(app, icon), overtime = false, timeout = endsAt - now + OVERTIME_LIMIT)
            scheduleOvertimeSwitch(app, endsAt)
        }
    }

    fun clear(context: Context) {
        val app = context.applicationContext
        cancelOvertimeSwitch(app)
        app.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().clear().apply()
        app.getSystemService(NotificationManager::class.java)?.cancel(ID)
    }

    /**
     * Re-post as a count-up from the end of rest, if this rest is still the current one. With [buzz] (the
     * moment rest ends) the phone also vibrates if the user enabled rest haptics: the timer's channel is
     * silent, and the app's own haptics need the screen on, so a locked phone would otherwise stay still.
     */
    fun switchToOvertime(context: Context, endsAt: Long, buzz: Boolean = true) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (prefs.getLong("endsAt", -1) != endsAt) return // cleared or replaced by a newer rest
        if (prefs.getString("overtimeAt", null) == endsAt.toString()) return // the handler and alarm both fire
        prefs.edit().putString("overtimeAt", endsAt.toString()).apply()
        // A backup alarm delivered late (Doze) must not buzz long after rest ended.
        if (buzz && prefs.getBoolean("vibrate", false) && System.currentTimeMillis() - endsAt < 10_000) vibrate(context)
        val left = endsAt + OVERTIME_LIMIT - System.currentTimeMillis()
        if (left <= 0) return
        val icon = drawable(context, "ic_over_" + (prefs.getString("overtimeIcon", null) ?: "warning"), R.drawable.ic_over_warning)
        post(context, endsAt, "Rest over", prefs.getString("text", "") ?: "", icon, overtime = true, timeout = left)
    }

    /** Three short pulses, like the in-app rest haptics. Alarm usage is allowed to vibrate in the background. */
    @Suppress("DEPRECATION")
    private fun vibrate(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            context.getSystemService(VibratorManager::class.java)?.defaultVibrator
        } else {
            context.getSystemService(Vibrator::class.java)
        }
        if (vibrator == null || !vibrator.hasVibrator()) return
        val effect = VibrationEffect.createWaveform(longArrayOf(0, 180, 120, 180, 120, 180), -1)
        if (Build.VERSION.SDK_INT >= 33) {
            vibrator.vibrate(effect, VibrationAttributes.createForUsage(VibrationAttributes.USAGE_ALARM))
        } else {
            vibrator.vibrate(effect, AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ALARM).build())
        }
    }

    private fun restIcon(context: Context, key: String) = drawable(context, "ic_rest_$key", R.drawable.ic_rest_muscle)

    /** Icon by name (kept in release builds by res/raw/keep.xml), falling back to a default. */
    private fun drawable(context: Context, name: String, fallback: Int): Int {
        val id = context.resources.getIdentifier(name, "drawable", context.packageName)
        return if (id != 0) id else fallback
    }

    private fun overtimeIntent(context: Context, endsAt: Long) = PendingIntent.getBroadcast(
        context,
        0,
        Intent(context, OvertimeReceiver::class.java).putExtra("endsAt", endsAt),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )

    private fun scheduleOvertimeSwitch(context: Context, endsAt: Long) {
        handler.postDelayed({ switchToOvertime(context, endsAt) }, endsAt - System.currentTimeMillis())
        val alarms = context.getSystemService(AlarmManager::class.java) ?: return
        val exact = Build.VERSION.SDK_INT < Build.VERSION_CODES.S || alarms.canScheduleExactAlarms()
        val intent = overtimeIntent(context, endsAt)
        if (exact) {
            alarms.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, endsAt, intent)
        } else {
            alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, endsAt, intent)
        }
    }

    private fun cancelOvertimeSwitch(context: Context) {
        handler.removeCallbacksAndMessages(null)
        context.getSystemService(AlarmManager::class.java)?.cancel(overtimeIntent(context, 0))
    }

    private fun post(
        context: Context,
        endsAt: Long,
        title: String,
        text: String,
        icon: Int,
        overtime: Boolean,
        timeout: Long,
    ) {
        val manager = context.getSystemService(NotificationManager::class.java)
        if (manager.getNotificationChannel(CHANNEL) == null) {
            // Default importance: low-importance notifications are hidden from the status bar and are not
            // promoted to Live Updates. Sound and vibration are off, so it still never makes a noise.
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL, "Live rest timer", NotificationManager.IMPORTANCE_DEFAULT).apply {
                    description = "Rest countdown in the status bar while a workout runs"
                    setSound(null, null)
                    enableVibration(false)
                    setShowBadge(false)
                },
            )
        }
        val open = PendingIntent.getActivity(
            context,
            0,
            Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val builder = Notification.Builder(context, CHANNEL)
            .setSmallIcon(icon)
            .setContentTitle(title)
            .setContentText(text)
            .setContentIntent(open)
            .setCategory(Notification.CATEGORY_STOPWATCH)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(true)
            // Countdown to the end of rest, or (overtime) counting up from it.
            .setWhen(endsAt)
            .setUsesChronometer(true)
            .setChronometerCountDown(!overtime)
            // Drops itself if the app is killed and never clears it.
            .setTimeoutAfter(timeout)
        if (Build.VERSION.SDK_INT >= 36) {
            builder.extras.putBoolean(EXTRA_REQUEST_PROMOTED_ONGOING, true)
            // Optional user text (up to 7 characters) in place of the time in the chip.
            val chipText = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString("chipText", "")
            if (!chipText.isNullOrBlank()) builder.extras.putString(EXTRA_SHORT_CRITICAL_TEXT, chipText)
        }
        manager.notify(ID, builder.build())
    }
}

/** Fires when rest ends while the app process may be gone; switches the timer to overtime. */
class OvertimeReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        LiveTimer.switchToOvertime(context, intent.getLongExtra("endsAt", -1))
    }
}
