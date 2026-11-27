package com.abualathari.smart_mushaf

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import com.ryanheise.audioservice.AudioServiceActivity
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/** A simple card widget: small title, big line, small line. Data is saved by the Flutter side. */
abstract class CardWidget : HomeWidgetProvider() {
    abstract val kind: String
    abstract val defTitle: String
    open val defMain: String = "افتح التطبيق"

    open fun texts(d: SharedPreferences): Array<String> = arrayOf(
        d.getString(kind + "_t", defTitle) ?: defTitle,
        d.getString(kind + "_m", defMain) ?: defMain,
        d.getString(kind + "_s", "") ?: ""
    )

    open fun uri(d: SharedPreferences): String =
        d.getString(kind + "_u", "smartmushaf://open?to=$kind") ?: "smartmushaf://open?to=$kind"

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        for (id in appWidgetIds) {
            val v = RemoteViews(context.packageName, R.layout.widget_card)
            val t = texts(widgetData)
            v.setTextViewText(R.id.w_title, t[0])
            v.setTextViewText(R.id.w_main, t[1])
            v.setTextViewText(R.id.w_sub, t[2])
            val pi = HomeWidgetLaunchIntent.getActivity(
                context, AudioServiceActivity::class.java, Uri.parse(uri(widgetData))
            )
            v.setOnClickPendingIntent(R.id.w_root, pi)
            appWidgetManager.updateAppWidget(id, v)
        }
    }
}

class PrayerWidget : CardWidget() {
    override val kind = "pr"
    override val defTitle = "أوقات الصلاة"
    override val defMain = "افتح التطبيق وحدّد موقعك"

    override fun texts(d: SharedPreferences): Array<String> {
        val raw = d.getString("pr_times", "") ?: ""
        val parts = raw.split(",").mapNotNull { it.trim().toLongOrNull() }
        if (parts.size < 7) return super.texts(d)
        val names = arrayOf("الفجر", "الشروق", "الظهر", "العصر", "المغرب", "العشاء", "الفجر")
        val now = System.currentTimeMillis()
        val f = SimpleDateFormat("h:mm", Locale.US)
        fun hm(ms: Long): String {
            val dt = Date(ms)
            val pm = SimpleDateFormat("a", Locale.US).format(dt) == "PM"
            return f.format(dt) + (if (pm) " م" else " ص")
        }
        var next = -1
        for (i in intArrayOf(0, 2, 3, 4, 5, 6)) {
            if (parts[i] > now) { next = i; break }
        }
        if (next < 0) return arrayOf(defTitle, "افتح التطبيق لتحديث الأوقات", "")
        val left = (parts[next] - now) / 60000
        val sub = StringBuilder()
        for (i in intArrayOf(0, 2, 3, 4, 5)) {
            if (sub.isNotEmpty()) sub.append("   ")
            sub.append(names[i]).append(" ").append(f.format(Date(parts[i])))
        }
        val leftTxt = if (left >= 60) "بعد ${left / 60} س ${left % 60} د" else "بعد $left د"
        return arrayOf("الصلاة القادمة • $leftTxt", names[next] + "  " + hm(parts[next]), sub.toString())
    }
}

class ContinueWidget : CardWidget() { override val kind = "co"; override val defTitle = "متابعة القراءة" }
class KhatmaWidget : CardWidget() { override val kind = "kh"; override val defTitle = "ورد الختمة"; override val defMain = "ابدأ ختمة من التطبيق" }
class AyahWidget : CardWidget() { override val kind = "ay"; override val defTitle = "آية اليوم" }
class ReviewWidget : CardWidget() { override val kind = "rv"; override val defTitle = "مراجعة اليوم"; override val defMain = "لا مراجعة اليوم" }
class StreakWidget : CardWidget() { override val kind = "st"; override val defTitle = "أيام متتالية"; override val defMain = "٠" }
class TasmeeWidget : CardWidget() { override val kind = "ts"; override val defTitle = "تسميع سريع"; override val defMain = "اضغط لتسمّع" }
class PlayerWidget : CardWidget() { override val kind = "pl"; override val defTitle = "تشغيل التلاوة"; override val defMain = "اضغط للتشغيل" }
class MajlisWidget : CardWidget() { override val kind = "mj"; override val defTitle = "مجلس الحفاظ"; override val defMain = "لا حلقة الآن" }

/** The four coloured place-markers; each one opens its page. */
class FawasilWidget : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        val ids = intArrayOf(R.id.f0, R.id.f1, R.id.f2, R.id.f3)
        val names = arrayOf("الأحمر", "الأصفر", "الأخضر", "الأزرق")
        for (id in appWidgetIds) {
            val v = RemoteViews(context.packageName, R.layout.widget_fawasil)
            for (i in 0..3) {
                val txt = widgetData.getString("fw${i}_m", "") ?: ""
                v.setTextViewText(ids[i], names[i] + "\n" + (if (txt.isEmpty()) "—" else txt))
                val u = widgetData.getString("fw${i}_u", "smartmushaf://open?to=fw") ?: "smartmushaf://open?to=fw"
                val pi = HomeWidgetLaunchIntent.getActivity(context, AudioServiceActivity::class.java, Uri.parse(u))
                v.setOnClickPendingIntent(ids[i], pi)
            }
            appWidgetManager.updateAppWidget(id, v)
        }
    }
}
