package com.moneytrack.moneytrack

import android.Manifest
import android.app.*
import android.content.*
import android.content.pm.PackageManager
import android.os.Build
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar
import java.util.GregorianCalendar
import java.util.Locale

internal object LocalReminders {
    private const val channel = "moneytrack_reminders"
    private fun prefs(c: Context) = c.getSharedPreferences("moneytrack_reminders", Context.MODE_PRIVATE)
    fun allowed(c: Context): Boolean {
        if (Build.VERSION.SDK_INT >= 33 && c.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return false
        return Build.VERSION.SDK_INT < 24 || (c.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).areNotificationsEnabled()
    }
    private fun alarmIntent(c: Context, id: Int) = PendingIntent.getBroadcast(c, id,
        Intent(c, ReminderReceiver::class.java).setAction("moneytrack.reminder.$id"),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    fun replace(c: Context, items: JSONArray) {
        val old = JSONArray(prefs(c).getString("items", "[]") ?: "[]")
        val alarms = c.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val manager = c.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val keep = (0 until items.length()).map { items.getJSONObject(it).getInt("id") }.toSet()
        for (i in 0 until old.length()) {
            val id = old.getJSONObject(i).getInt("id")
            alarms.cancel(alarmIntent(c, id))
            if (!keep.contains(id)) manager.cancel(id)
        }
        prefs(c).edit().putString("items", items.toString()).apply()
        reschedule(c)
    }
    fun reschedule(c: Context) {
        if (!allowed(c)) return
        val items = JSONArray(prefs(c).getString("items", "[]") ?: "[]")
        val alarms = c.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        for (i in 0 until items.length()) {
            val item = items.getJSONObject(i)
            val id = item.getInt("id")
            if (prefs(c).getString("delivered_$id", null) == item.getString("key")) continue
            val parts = item.getString("date").split("-").map { it.toInt() }
            val date = GregorianCalendar().apply {
                isLenient = false
                set(parts[0], parts[1] - 1, parts[2], 9, 0, 0)
                set(Calendar.MILLISECOND, 0)
            }
            val at = maxOf(date.timeInMillis, System.currentTimeMillis() + 1000)
            val intent = alarmIntent(c, id)
            if (Build.VERSION.SDK_INT >= 23) alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, intent)
            else alarms.set(AlarmManager.RTC_WAKEUP, at, intent)
        }
    }
    fun deliver(c: Context, id: Int) {
        if (!allowed(c)) return
        val items = JSONArray(prefs(c).getString("items", "[]") ?: "[]")
        val item: JSONObject = (0 until items.length()).map { items.getJSONObject(it) }.firstOrNull { it.getInt("id") == id } ?: return
        if (prefs(c).getString("delivered_$id", null) == item.getString("key")) return
        val manager = c.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(NotificationChannel(channel, "Financial reminders", NotificationManager.IMPORTANCE_DEFAULT))
        val launch = c.packageManager.getLaunchIntentForPackage(c.packageName) ?: return
        val open = PendingIntent.getActivity(c, id, launch, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(c, channel) else Notification.Builder(c)
        manager.notify(id, builder.setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(item.getString("title")).setContentText(item.getString("body"))
            .setStyle(Notification.BigTextStyle().bigText(item.getString("body")))
            .setContentIntent(open).setAutoCancel(true).build())
        prefs(c).edit().putString("delivered_$id", item.getString("key")).apply()
        // Native reminders can repeat without running Flutter. Only reminder
        // dates advance here; financial occurrences are reconciled by the app.
        if (item.has("frequency")) {
            var index = item.getInt("next_index") + 1
            val today = GregorianCalendar()
            val todayKey = civilKey(today)
            var next = nextDate(item, index)
            while (next <= todayKey) { index++; next = nextDate(item, index) }
            if (item.has("end_date") && next > item.getString("end_date")) {
                val kept = JSONArray()
                for (i in 0 until items.length()) if (items.getJSONObject(i).getInt("id") != id) kept.put(items.getJSONObject(i))
                prefs(c).edit().putString("items", kept.toString()).apply()
            } else {
                item.put("next_index", index).put("date", next).put("key", "${item.getString("key_base")}:$next")
                prefs(c).edit().putString("items", items.toString()).apply()
            }
            reschedule(c)
        }
    }
    private fun civilKey(date: Calendar): String = String.format(Locale.US, "%04d-%02d-%02d",
        date.get(Calendar.YEAR), date.get(Calendar.MONTH) + 1, date.get(Calendar.DAY_OF_MONTH))
    private fun nextDate(item: JSONObject, index: Int): String {
        val parts = item.getString("start_date").split("-").map { it.toInt() }
        val date = GregorianCalendar().apply { clear(); set(parts[0], parts[1] - 1, 1, 9, 0, 0) }
        when (item.getString("frequency")) {
            "daily", "weekly" -> {
                date.set(Calendar.DAY_OF_MONTH, parts[2])
                date.add(Calendar.DAY_OF_MONTH, index * if (item.getString("frequency") == "weekly") 7 else 1)
            }
            "monthly" -> { date.add(Calendar.MONTH, index); date.set(Calendar.DAY_OF_MONTH, minOf(parts[2], date.getActualMaximum(Calendar.DAY_OF_MONTH))) }
            "yearly" -> { date.add(Calendar.YEAR, index); date.set(Calendar.DAY_OF_MONTH, minOf(parts[2], date.getActualMaximum(Calendar.DAY_OF_MONTH))) }
            else -> throw IllegalArgumentException("Invalid reminder frequency")
        }
        return civilKey(date)
    }
}

class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        try {
            val action = intent.action ?: return
            if (action.startsWith("moneytrack.reminder.")) LocalReminders.deliver(context, action.substringAfterLast('.').toInt())
            else LocalReminders.reschedule(context)
        } catch (_: Exception) { /* Malformed or obsolete reminders never alter financial records. */ }
    }
}
