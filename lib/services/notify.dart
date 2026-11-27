import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'store.dart';

/// The daily reminder of the memorization plan.
class Notify {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;
  static const _planId = 71;

  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<void> init() async {
    if (!supported || _ready) return;
    try {
      tzdata.initializeTimeZones();
      await _plugin.initialize(const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')));
      _ready = true;
      await syncPlan();
    } catch (_) {}
  }

  /// Asks for the notification permission (needed on Android 13 and later).
  static Future<void> ask() async {
    if (!supported) return;
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } catch (_) {}
  }

  /// Sets or removes the daily reminder to match the saved plan.
  static Future<void> syncPlan() async {
    if (!supported || !_ready) return;
    try {
      await _plugin.cancel(_planId);
      final st = UserStore.I;
      if (!st.hasPlan || !st.planNotify || st.planFinished) return;
      final now = DateTime.now();
      var at = DateTime(now.year, now.month, now.day, st.planHour, st.planMin);
      if (!at.isAfter(now)) at = at.add(const Duration(days: 1));
      final from = st.planFromPage, to = st.planToPage;
      await _plugin.zonedSchedule(
        _planId,
        'حان وقت ورد الحفظ',
        from == to ? 'ورد اليوم: صفحة $from' : 'ورد اليوم: من صفحة $from إلى صفحة $to',
        tz.TZDateTime.from(at.toUtc(), tz.UTC),
        const NotificationDetails(
          android: AndroidNotificationDetails('hifz_plan', 'ورد الحفظ اليومي',
              channelDescription: 'تذكير يومي بورد الحفظ', importance: Importance.high, priority: Priority.high),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } catch (_) {}
  }
}
