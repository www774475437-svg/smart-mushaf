import 'dart:math' as math;

/// Prayer times computed on the phone (no internet), standard astronomical method.
class PrayerMethod {
  final String id, name;
  final double fajr, isha;
  final int ishaMinutes; // if > 0: isha = maghrib + minutes
  const PrayerMethod(this.id, this.name, this.fajr, this.isha, {this.ishaMinutes = 0});
}

const List<PrayerMethod> kPrayerMethods = [
  PrayerMethod('makkah', 'أم القرى', 18.5, 0, ishaMinutes: 90),
  PrayerMethod('mwl', 'رابطة العالم الإسلامي', 18, 17),
  PrayerMethod('isna', 'أمريكا الشمالية (ISNA)', 15, 15),
  PrayerMethod('egypt', 'الهيئة المصرية', 19.5, 17.5),
  PrayerMethod('karachi', 'كراتشي', 18, 18),
];

double _rad(double d) => d * math.pi / 180;
double _deg(double r) => r * 180 / math.pi;
double _fix(double a, double b) {
  a = a - b * (a / b).floorToDouble();
  return a < 0 ? a + b : a;
}

class PrayerTimes {
  /// fajr, sunrise, dhuhr, asr, maghrib, isha
  final List<DateTime> times;
  const PrayerTimes(this.times);
  static const names = ['الفجر', 'الشروق', 'الظهر', 'العصر', 'المغرب', 'العشاء'];

  static double _julian(int y, int m, int d) {
    if (m <= 2) {
      y -= 1;
      m += 12;
    }
    final a = (y / 100).floorToDouble();
    final b = 2 - a + (a / 4).floorToDouble();
    return (365.25 * (y + 4716)).floorToDouble() + (30.6001 * (m + 1)).floorToDouble() + d + b - 1524.5;
  }

  static List<double> _sun(double jd) {
    final dd = jd - 2451545.0;
    final g = _fix(357.529 + 0.98560028 * dd, 360);
    final q = _fix(280.459 + 0.98564736 * dd, 360);
    final l = _fix(q + 1.915 * math.sin(_rad(g)) + 0.020 * math.sin(_rad(2 * g)), 360);
    final e = 23.439 - 0.00000036 * dd;
    final ra = _deg(math.atan2(math.cos(_rad(e)) * math.sin(_rad(l)), math.cos(_rad(l)))) / 15;
    final eqt = q / 15 - _fix(ra, 24);
    final decl = _deg(math.asin(math.sin(_rad(e)) * math.sin(_rad(l))));
    return [decl, eqt];
  }

  static PrayerTimes compute(DateTime date, double lat, double lng, PrayerMethod m, {bool hanafiAsr = false}) {
    final tz = date.timeZoneOffset.inMinutes / 60.0;
    final jd = _julian(date.year, date.month, date.day) - lng / (15 * 24);

    double midDay(double t) => _fix(12 - _sun(jd + t)[1], 24);
    double angleTime(double angle, double t, bool before) {
      final decl = _sun(jd + t)[0];
      final noon = midDay(t);
      var x = (-math.sin(_rad(angle)) - math.sin(_rad(decl)) * math.sin(_rad(lat))) /
          (math.cos(_rad(decl)) * math.cos(_rad(lat)));
      x = x.clamp(-1.0, 1.0);
      final v = _deg(math.acos(x)) / 15;
      return noon + (before ? -v : v);
    }

    double asr(double factor, double t) {
      final decl = _sun(jd + t)[0];
      final angle = -_deg(math.atan(1 / (factor + math.tan(_rad((lat - decl).abs())))));
      return angleTime(angle, t, false);
    }

    var fajr = angleTime(m.fajr, 5 / 24, true);
    var sunrise = angleTime(0.833, 6 / 24, true);
    var dhuhr = midDay(12 / 24);
    var asrT = asr(hanafiAsr ? 2 : 1, 13 / 24);
    var maghrib = angleTime(0.833, 18 / 24, false);
    var isha = m.ishaMinutes > 0 ? maghrib + m.ishaMinutes / 60 : angleTime(m.isha, 18 / 24, false);

    final adj = tz - lng / 15;
    DateTime at(double h) {
      h = _fix(h + adj, 24);
      final mins = (h * 60).round();
      return DateTime(date.year, date.month, date.day, mins ~/ 60, mins % 60);
    }

    dhuhr += 1 / 60; // one minute after the zenith
    return PrayerTimes([at(fajr), at(sunrise), at(dhuhr), at(asrT), at(maghrib), at(isha)]);
  }

  /// Index of the next prayer (skipping sunrise), or -1 if all passed today.
  int nextIndex(DateTime now) {
    for (final i in const [0, 2, 3, 4, 5]) {
      if (times[i].isAfter(now)) return i;
    }
    return -1;
  }

  /// Direction of the Kaaba in degrees from north.
  static double qibla(double lat, double lng) {
    const kLat = 21.4225, kLng = 39.8262;
    final dl = _rad(kLng - lng);
    final y = math.sin(dl);
    final x = math.cos(_rad(lat)) * math.tan(_rad(kLat)) - math.sin(_rad(lat)) * math.cos(dl);
    return _fix(_deg(math.atan2(y, x)), 360);
  }
}
