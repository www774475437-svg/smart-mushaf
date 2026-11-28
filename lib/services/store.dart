import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Bookmark {
  final int g;
  final int page;
  final int color;
  final int time;
  const Bookmark(this.g, this.page, this.color, this.time);
  Map<String, dynamic> toJson() => {'g': g, 'p': page, 'c': color, 't': time};
  static Bookmark fromJson(Map<String, dynamic> m) =>
      Bookmark(m['g'] as int, m['p'] as int, m['c'] as int, m['t'] as int);
}

class Mistake {
  final int g;
  final List<String> missing;
  final int count;
  final int time;
  const Mistake(this.g, this.missing, this.count, this.time);
  Map<String, dynamic> toJson() => {'g': g, 'm': missing, 'n': count, 't': time};
  static Mistake fromJson(Map<String, dynamic> m) =>
      Mistake(m['g'] as int, List<String>.from(m['m'] as List), m['n'] as int, m['t'] as int);
}

class UserStore extends ChangeNotifier {
  UserStore._();
  static final UserStore I = UserStore._();
  late SharedPreferences _p;

  int lastPage = 1;
  List<Bookmark> bookmarks = [];
  Map<int, int> highlights = {};
  List<Mistake> mistakes = [];
  Set<int> memorized = {};

  /// Smart review of memorized surahs: surah -> [stage, due day number].
  Map<int, List<int>> review = {};

  /// Memorization map: page -> 1 strong (green), 2 weak (yellow), 3 mistakes (red).
  Map<int, int> pageStatus = {};
  static const List<int> reviewSteps = [3, 7, 30, 60];
  static int dayNumber([DateTime? d]) {
    final x = d ?? DateTime.now();
    return DateTime.utc(x.year, x.month, x.day).millisecondsSinceEpoch ~/ 86400000;
  }

  /// Surahs whose review is due today (or overdue).
  List<int> get dueReviews {
    final t = dayNumber();
    final l = review.entries.where((e) => memorized.contains(e.key) && e.value[1] <= t).map((e) => e.key).toList();
    l.sort((a, b) => review[a]![1].compareTo(review[b]![1]));
    return l;
  }

  /// [clean] true: recited without mistakes -> the next review moves further away.
  void reviewed(int s, bool clean) {
    final cur = review[s] ?? [0, dayNumber()];
    if (clean) {
      final st = (cur[0] + 1).clamp(0, reviewSteps.length - 1);
      review[s] = [st, dayNumber() + reviewSteps[st]];
    } else {
      review[s] = [0, dayNumber() + 1];
    }
    _save();
  }
  int khatmaDays = 0;
  int khatmaStart = 0;
  Set<int> khatmaDone = {};
  Map<int, String> notes = {};

  /// Four coloured place-markers (الفواصل): colour -> [ayah index, time].
  Map<int, List<int>> fawasil = {};
  Map<String, int> dayPages = {};

  /// Per-day activity for the weekly report: day -> [quiz right, quiz total, pages recited, wrong words].
  Map<String, List<int>> dayStats = {};

  /// Daily memorization plan, counted in half pages. [planPer] 0 means no plan.
  int planPos = 0, planPer = 0, planDoneDay = 0, planHour = 6, planMin = 0;
  bool planNotify = true;
  Set<int> _todayPages = {};
  String _todayKey = '';

  static String dayKey(DateTime d) => '${d.year}-${d.month}-${d.day}';

  Future<void> init() async {
    _p = await SharedPreferences.getInstance();
    lastPage = _p.getInt('lastPage') ?? 1;
    try {
      final raw = _p.getString('userStore');
      if (raw != null) {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        bookmarks = (m['b'] as List? ?? []).map((e) => Bookmark.fromJson(e as Map<String, dynamic>)).toList();
        final h = m['h'] as Map<String, dynamic>? ?? {};
        highlights = h.map((k, v) => MapEntry(int.parse(k), v as int));
        mistakes = (m['m'] as List? ?? []).map((e) => Mistake.fromJson(e as Map<String, dynamic>)).toList();
        memorized = Set<int>.from((m['mem'] as List? ?? []).map((e) => e as int));
        final ps = m['ps'] as Map<String, dynamic>? ?? {};
        pageStatus = ps.map((k, v) => MapEntry(int.parse(k), v as int));
        final rv = m['rv'] as Map<String, dynamic>? ?? {};
        review = rv.map((k, v) => MapEntry(int.parse(k), List<int>.from(v as List)));
        khatmaDays = m['kd'] as int? ?? 0;
        khatmaStart = m['ks'] as int? ?? 0;
        khatmaDone = Set<int>.from((m['kdn'] as List? ?? []).map((e) => e as int));
        final fw = m['fw'] as Map<String, dynamic>? ?? {};
        fawasil = fw.map((k, v) => MapEntry(int.parse(k), List<int>.from(v as List)));
        final n = m['n'] as Map<String, dynamic>? ?? {};
        notes = n.map((k, v) => MapEntry(int.parse(k), v as String));
        final dp = m['dp'] as Map<String, dynamic>? ?? {};
        dayPages = dp.map((k, v) => MapEntry(k, v as int));
        final ds = m['ds'] as Map<String, dynamic>? ?? {};
        dayStats = ds.map((k, v) => MapEntry(k, List<int>.from(v as List)));
        final pl = List<int>.from(m['pl'] as List? ?? const []);
        if (pl.length >= 6) {
          planPos = pl[0];
          planPer = pl[1];
          planDoneDay = pl[2];
          planHour = pl[3];
          planMin = pl[4];
          planNotify = pl[5] == 1;
        }
        _todayKey = m['tk'] as String? ?? '';
        _todayPages = Set<int>.from((m['tp'] as List? ?? []).map((e) => e as int));
      }
    } catch (_) {}
  }

  void _save() {
    _p.setString(
        'userStore',
        jsonEncode({
          'b': bookmarks.map((e) => e.toJson()).toList(),
          'h': highlights.map((k, v) => MapEntry(k.toString(), v)),
          'm': mistakes.map((e) => e.toJson()).toList(),
          'mem': memorized.toList(),
          'rv': review.map((k, v) => MapEntry(k.toString(), v)),
          'ps': pageStatus.map((k, v) => MapEntry(k.toString(), v)),
          'kd': khatmaDays,
          'ks': khatmaStart,
          'kdn': khatmaDone.toList(),
          'n': notes.map((k, v) => MapEntry(k.toString(), v)),
          'fw': fawasil.map((k, v) => MapEntry(k.toString(), v)),
          'dp': dayPages,
          'ds': dayStats,
          'pl': [planPos, planPer, planDoneDay, planHour, planMin, planNotify ? 1 : 0],
          'tk': _todayKey,
          'tp': _todayPages.toList(),
        }));
    notifyListeners();
  }

  void setLastPage(int p) {
    final k = dayKey(DateTime.now());
    if (k != _todayKey) {
      _todayKey = k;
      _todayPages = {};
    }
    final newPage = _todayPages.add(p);
    if (newPage) dayPages[k] = _todayPages.length;
    if (p != lastPage) {
      lastPage = p;
      _p.setInt('lastPage', p);
    }
    if (newPage) {
      _save();
    } else {
      notifyListeners();
    }
  }

  int get pagesToday => dayPages[dayKey(DateTime.now())] ?? 0;
  int get totalDays => dayPages.values.where((v) => v > 0).length;

  /// Consecutive days with reading, ending today (or yesterday).
  int get streak {
    var d = DateTime.now();
    if ((dayPages[dayKey(d)] ?? 0) == 0) d = d.subtract(const Duration(days: 1));
    var n = 0;
    while ((dayPages[dayKey(d)] ?? 0) > 0) {
      n++;
      d = d.subtract(const Duration(days: 1));
    }
    return n;
  }

  List<int> statsOf(DateTime d) => dayStats[dayKey(d)] ?? const [0, 0, 0, 0];

  void _stat(int i, int add) {
    final k = dayKey(DateTime.now());
    final l = List<int>.from(dayStats[k] ?? const [0, 0, 0, 0]);
    l[i] += add;
    dayStats[k] = l;
    if (dayStats.length > 120) dayStats.remove(dayStats.keys.first);
  }

  void logQuiz(bool right) {
    if (right) _stat(0, 1);
    _stat(1, 1);
    _save();
  }

  void logTasmee(int wrong) {
    _stat(2, 1);
    _stat(3, wrong);
    _save();
  }

  // Daily memorization plan
  bool get hasPlan => planPer > 0;
  bool get planDoneToday => planDoneDay == dayNumber();
  bool get planFinished => planPos >= 1208;
  int get planFromPage => (planPos ~/ 2 + 1).clamp(1, 604);
  int get planToPage => ((planPos + planPer - 1) ~/ 2 + 1).clamp(1, 604);

  void setPlan({required int startPage, required int per}) {
    planPos = (startPage - 1) * 2;
    planPer = per;
    planDoneDay = 0;
    _save();
  }

  void setPlanTime(int h, int m, bool notify) {
    planHour = h;
    planMin = m;
    planNotify = notify;
    _save();
  }

  void planDone() {
    if (!hasPlan || planDoneToday) return;
    planPos += planPer;
    planDoneDay = dayNumber();
    _save();
  }

  void stopPlan() {
    planPer = 0;
    _save();
  }

  void setFasil(int color, int? g) {
    if (g == null) {
      fawasil.remove(color);
    } else {
      fawasil[color] = [g, DateTime.now().millisecondsSinceEpoch];
    }
    _save();
  }

  void setPageStatus(int page, int? st) {
    if (st == null) {
      pageStatus.remove(page);
    } else {
      pageStatus[page] = st;
    }
    _save();
  }

  // Notes
  void setNote(int g, String text) {
    if (text.trim().isEmpty) {
      notes.remove(g);
    } else {
      notes[g] = text.trim();
    }
    _save();
  }

  // Bookmarks
  bool isPageBookmarked(int page) => bookmarks.any((b) => b.page == page && b.g < 0);
  bool isAyahBookmarked(int g) => bookmarks.any((b) => b.g == g);

  void togglePageBookmark(int page) {
    if (isPageBookmarked(page)) {
      bookmarks.removeWhere((b) => b.page == page && b.g < 0);
    } else {
      bookmarks.insert(0, Bookmark(-1, page, 0, DateTime.now().millisecondsSinceEpoch));
    }
    _save();
  }

  void toggleAyahBookmark(int g, int page, {int color = 0}) {
    if (isAyahBookmarked(g)) {
      bookmarks.removeWhere((b) => b.g == g);
    } else {
      bookmarks.insert(0, Bookmark(g, page, color, DateTime.now().millisecondsSinceEpoch));
    }
    _save();
  }

  void removeBookmark(Bookmark b) {
    bookmarks.remove(b);
    _save();
  }

  // Highlights
  void setHighlight(int g, int? color) {
    if (color == null) {
      highlights.remove(g);
    } else {
      highlights[g] = color;
    }
    _save();
  }

  // Mistakes
  void addMistake(int g, List<String> missing) {
    final i = mistakes.indexWhere((m) => m.g == g);
    if (i >= 0) {
      final old = mistakes.removeAt(i);
      final merged = {...old.missing, ...missing}.toList();
      mistakes.insert(0, Mistake(g, merged, old.count + 1, DateTime.now().millisecondsSinceEpoch));
    } else {
      mistakes.insert(0, Mistake(g, missing, 1, DateTime.now().millisecondsSinceEpoch));
    }
    _save();
  }

  /// A question about a past mistake was answered: a right answer wears the mistake down
  /// until it is gone, a wrong one makes it heavier.
  void mistakeAnswered(int g, bool right) {
    final i = mistakes.indexWhere((m) => m.g == g);
    if (i < 0) return;
    final old = mistakes[i];
    final n = right ? old.count - 1 : old.count + 1;
    if (n <= 0) {
      mistakes.removeAt(i);
    } else {
      mistakes[i] = Mistake(g, old.missing, n.clamp(1, 5), old.time);
    }
    _save();
  }

  /// Everything the user saved, as text, to keep a copy outside the phone.
  String exportJson() => jsonEncode({'app': 'smart-mushaf', 'v': 1, 'lastPage': lastPage, 'store': _p.getString('userStore') ?? '{}'});

  /// Puts back a copy made by [exportJson]. False when the text is not such a copy.
  Future<bool> importJson(String text) async {
    try {
      final m = jsonDecode(text.trim()) as Map<String, dynamic>;
      if (m['app'] != 'smart-mushaf') return false;
      final store = m['store'] as String;
      jsonDecode(store) as Map<String, dynamic>;
      await _p.setString('userStore', store);
      await _p.setInt('lastPage', (m['lastPage'] as int? ?? 1).clamp(1, 604));
      await init();
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  void removeMistake(int g) {
    mistakes.removeWhere((m) => m.g == g);
    _save();
  }

  void clearMistakes() {
    mistakes.clear();
    _save();
  }

  // Memorized surahs
  void toggleMemorized(int s) {
    if (!memorized.remove(s)) {
      memorized.add(s);
      review[s] = [0, dayNumber() + reviewSteps[0]];
    } else {
      review.remove(s);
    }
    _save();
  }

  // Khatma
  bool get hasKhatma => khatmaDays > 0;
  int get khatmaToday {
    if (!hasKhatma) return 0;
    final start = DateTime.fromMillisecondsSinceEpoch(khatmaStart);
    final now = DateTime.now();
    final d = DateTime(now.year, now.month, now.day).difference(DateTime(start.year, start.month, start.day)).inDays;
    return (d + 1).clamp(1, khatmaDays);
  }

  int get pagesPerDay => hasKhatma ? (604 / khatmaDays).ceil() : 0;
  int khatmaFrom(int day) => ((day - 1) * pagesPerDay + 1).clamp(1, 604);
  int khatmaTo(int day) => (day * pagesPerDay).clamp(1, 604);

  void startKhatma(int days) {
    khatmaDays = days;
    khatmaStart = DateTime.now().millisecondsSinceEpoch;
    khatmaDone = {};
    _save();
  }

  void toggleKhatmaDay(int day) {
    if (!khatmaDone.remove(day)) khatmaDone.add(day);
    _save();
  }

  void stopKhatma() {
    khatmaDays = 0;
    khatmaDone = {};
    _save();
  }
}
