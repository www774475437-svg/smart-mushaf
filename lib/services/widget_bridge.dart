import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/prayer.dart';
import '../data/quran.dart';
import '../data/reciters.dart';
import '../data/surah_names.dart';
import 'settings.dart';
import 'store.dart';

/// Sends the app's data to the Android home-screen widgets.
class WidgetBridge {
  static Timer? _deb;
  static const _names = [
    'PrayerWidget', 'ContinueWidget', 'KhatmaWidget', 'AyahWidget', 'ReviewWidget',
    'StreakWidget', 'TasmeeWidget', 'PlayerWidget', 'MajlisWidget', 'FawasilWidget',
  ];

  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static void init() {
    if (!supported) return;
    UserStore.I.addListener(schedule);
    Reciters.I.addListener(schedule);
    schedule();
  }

  static void schedule() {
    if (!supported) return;
    _deb?.cancel();
    _deb = Timer(const Duration(seconds: 2), update);
  }

  static int ayahOfDay() {
    final q = QuranData.I;
    final now = DateTime.now();
    final days = DateTime(now.year, now.month, now.day).difference(DateTime(2024, 1, 1)).inDays;
    var g = (days * 7919 + 13) % 6236;
    var tries = 0;
    while ((q.ayahs[g].text.length > 170 || q.ayahs[g].text.length < 40) && tries < 400) {
      g = (g + 97) % 6236;
      tries++;
    }
    return g;
  }

  static Future<void> _set(String k, String v) => HomeWidget.saveWidgetData<String>(k, v);

  static Future<void> update() async {
    if (!supported || !QuranData.I.loaded) return;
    try {
      final q = QuranData.I;
      final st = UserStore.I;
      final lp = st.lastPage;
      await _set('co_m', 'سورة ${surahName(q.surahOfPage(lp))}');
      await _set('co_s', 'صفحة $lp • الجزء ${q.juzOfPage(lp)} • اضغط لتكمل');
      await _set('co_u', 'smartmushaf://page?n=$lp');

      if (st.hasKhatma) {
        final d = st.khatmaToday;
        await _set('kh_m', 'ورد اليوم $d من ${st.khatmaDays}');
        await _set('kh_s', 'من صفحة ${st.khatmaFrom(d)} إلى ${st.khatmaTo(d)}${st.khatmaDone.contains(d) ? ' • تمّ' : ''}');
        await _set('kh_u', 'smartmushaf://page?n=${st.khatmaFrom(d)}');
      } else {
        await _set('kh_m', 'ابدأ ختمة من التطبيق');
        await _set('kh_s', '');
        await _set('kh_u', 'smartmushaf://open?to=kh');
      }

      final g = ayahOfDay();
      await _set('ay_m', q.clean[g]);
      await _set('ay_s', q.ayahs[g].ref);
      await _set('ay_u', 'smartmushaf://page?n=${q.ayahs[g].page}&g=$g');

      final due = AppSettings.I.smartReview ? st.dueReviews : <int>[];
      await _set('rv_m', due.isEmpty ? 'لا مراجعة اليوم' : 'راجع سورة ${surahName(due.first)}');
      await _set('rv_s', due.length > 1 ? 'ومعها ${due.length - 1} سورة أخرى' : '');

      await _set('st_m', '${st.streak}');
      await _set('st_s', 'قرأت اليوم ${st.pagesToday} صفحة');

      await _set('ts_m', 'سمِّع صفحة $lp');
      await _set('ts_s', 'سورة ${surahName(q.surahOfPage(lp))}');
      await _set('pl_m', Reciters.I.current.name);
      await _set('pl_s', 'اضغط للتشغيل من صفحة $lp');
      await _set('mj_m', 'لا حلقة الآن');
      await _set('mj_s', 'يظهر هنا موعد الحلقة وبدء الشيخ بعد ربط الحسابات');

      for (var i = 0; i < 4; i++) {
        final f = st.fawasil[i];
        if (f == null) {
          await _set('fw${i}_m', '');
          await _set('fw${i}_u', 'smartmushaf://open?to=fw');
        } else {
          final ay = q.ayahs[f[0]];
          await _set('fw${i}_m', '${surahName(ay.s)}: ${ay.a}');
          await _set('fw${i}_u', 'smartmushaf://page?n=${ay.page}&g=${f[0]}');
        }
      }

      final p = await SharedPreferences.getInstance();
      final lat = p.getDouble('prLat'), lng = p.getDouble('prLng');
      if (lat != null && lng != null) {
        var mid = p.getString('prMethod') ?? '';
        if (mid.isEmpty) mid = lng < -30 ? 'isna' : 'mwl';
        final m = kPrayerMethods.firstWhere((e) => e.id == mid, orElse: () => kPrayerMethods[1]);
        final h = p.getBool('prHanafi') ?? false;
        final now = DateTime.now();
        final t = PrayerTimes.compute(now, lat, lng, m, hanafiAsr: h);
        final t2 = PrayerTimes.compute(now.add(const Duration(days: 1)), lat, lng, m, hanafiAsr: h);
        await _set('pr_times', [...t.times, t2.times[0]].map((e) => e.millisecondsSinceEpoch).join(','));
      }

      for (final n in _names) {
        await HomeWidget.updateWidget(name: n, androidName: n);
      }
    } catch (_) {}
  }
}
