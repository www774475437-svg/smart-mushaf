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
  int khatmaDays = 0;
  int khatmaStart = 0;
  Set<int> khatmaDone = {};
  Map<int, String> notes = {};
  Map<String, int> dayPages = {};
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
        khatmaDays = m['kd'] as int? ?? 0;
        khatmaStart = m['ks'] as int? ?? 0;
        khatmaDone = Set<int>.from((m['kdn'] as List? ?? []).map((e) => e as int));
        final n = m['n'] as Map<String, dynamic>? ?? {};
        notes = n.map((k, v) => MapEntry(int.parse(k), v as String));
        final dp = m['dp'] as Map<String, dynamic>? ?? {};
        dayPages = dp.map((k, v) => MapEntry(k, v as int));
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
          'kd': khatmaDays,
          'ks': khatmaStart,
          'kdn': khatmaDone.toList(),
          'n': notes.map((k, v) => MapEntry(k.toString(), v)),
          'dp': dayPages,
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
    if (!memorized.remove(s)) memorized.add(s);
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
