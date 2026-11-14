package com.gymer.gymer

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Home-screen widget with today's planned workout and the cycle week. The app hands over the plan for the
 * coming days as JSON whenever it is left (see MainActivity "todayWidget"); the widget only looks up today's
 * entry, so it stays right across midnight without the app running. Tapping it opens Gymer.
 */
class TodayWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        for (id in ids) manager.updateAppWidget(id, views(context))
    }

    companion object {
        private const val PREFS = "today_widget"

        /** Stores the plan and redraws every placed widget. */
        fun store(context: Context, json: String) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString("plan", json).apply()
            val manager = AppWidgetManager.getInstance(context) ?: return
            val ids = manager.getAppWidgetIds(ComponentName(context, TodayWidget::class.java))
            if (ids.isNotEmpty()) manager.updateAppWidget(ids, views(context))
        }

        private fun views(context: Context): RemoteViews {
            var title = "Gymer"
            var subtitle = "No workout planned today"
            try {
                val plan = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString("plan", null)
                if (plan != null) {
                    val today = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())
                    val day = JSONObject(plan).optJSONObject("days")?.optJSONObject(today)
                    if (day != null) {
                        val workout = day.optString("workout")
                        val week = day.optString("week")
                        if (workout.isNotEmpty()) {
                            title = workout
                            subtitle = week
                        } else if (week.isNotEmpty()) {
                            title = "Rest day"
                            subtitle = week
                        }
                    }
                }
            } catch (_: Exception) {
                // A damaged plan shows the neutral text instead of breaking the home screen.
            }
            val open = PendingIntent.getActivity(
                context,
                1,
                Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            return RemoteViews(context.packageName, R.layout.today_widget).apply {
                setTextViewText(R.id.today_widget_title, title)
                setTextViewText(R.id.today_widget_subtitle, subtitle)
                setOnClickPendingIntent(R.id.today_widget, open)
            }
        }
    }
}
