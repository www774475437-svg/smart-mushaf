import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'surah_names.dart';

dynamic decodeJson(String s) => jsonDecode(s);

/// Removes tashkeel and unifies letter shapes so that searching and
/// comparing recitation is forgiving.
String normalizeAr(String s) {
  final b = StringBuffer();
  for (final r in s.runes) {
    if ((r >= 0x064B && r <= 0x065F) || r == 0x0670 || (r >= 0x06D6 && r <= 0x06ED) || r == 0x0640) {
      continue;
    }
    var c = r;
    if (c == 0x0623 || c == 0x0625 || c == 0x0622 || c == 0x0671) {
      c = 0x0627;
    } else if (c == 0x0649 || c == 0x0626) {
      c = 0x064A;
    } else if (c == 0x0629) {
      c = 0x0647;
    } else if (c == 0x0624) {
      c = 0x0648;
    }
    b.writeCharCode(c);
  }
  return b.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Removes tashkeel only (for copying text without diacritics).
String stripTashkeel(String s) {
  final b = StringBuffer();
  for (final r in s.runes) {
    if ((r >= 0x064B && r <= 0x065F) || r == 0x0670 || (r >= 0x06D6 && r <= 0x06ED) || r == 0x0640) {
      continue;
    }
    b.writeCharCode(r == 0x0671 ? 0x0627 : r);
  }
  return b.toString();
}

class Ayah {
  final int g, s, a, page, juz, hq;
  final bool sajda;
  final String text;
  const Ayah(this.g, this.s, this.a, this.page, this.juz, this.hq, this.sajda, this.text);
  int get hizb => ((hq - 1) ~/ 4) + 1;
  String get ref => 'سورة ${surahName(s)}: $a';
}

class QuranData {
  QuranData._();
  static final QuranData I = QuranData._();

  final List<Ayah> ayahs = [];
  List<String> clean = [];
  List<String>? _norm;
  List<String>? _translation;
  final List<List<int>> pageAyahs = List.generate(605, (_) => <int>[]);
  final List<int> surahStart = List.filled(115, 0);
  final List<int> surahCount = List.filled(115, 0);
  final List<bool> surahMeccan = List.filled(115, true);
  final List<int> juzStartG = List.filled(31, -1);
  bool loaded = false;
  Map<int, List<int>> similar = {};
  Map<int, String> asbab = {};

  Future<void> load() async {
    if (loaded) return;
    final raw = await rootBundle.loadString('assets/data/quran.json');
    final m = (await compute(decodeJson, raw)) as Map<String, dynamic>;
    final a = m['a'] as List;
    final c = m['c'] as List;
    final t = m['t'] as List;
    for (var i = 0; i < a.length; i++) {
      final r = a[i] as List;
      final ay = Ayah(i, r[0] as int, r[1] as int, r[2] as int, r[3] as int, r[4] as int, (r[5] as int) == 1,
          r[6] as String);
      ayahs.add(ay);
      if (ay.page >= 1 && ay.page <= 604) pageAyahs[ay.page].add(i);
      if (ay.a == 1) surahStart[ay.s] = i;
      surahCount[ay.s] = ay.a;
      if (ay.juz >= 1 && ay.juz <= 30 && juzStartG[ay.juz] == -1) juzStartG[ay.juz] = i;
    }
    clean = List<String>.from(c);
    for (var i = 0; i < t.length && i < 114; i++) {
      surahMeccan[i + 1] = t[i] == 'Meccan';
    }
    try {
      final sm = (await compute(decodeJson, await rootBundle.loadString('assets/data/similar.json'))) as Map<String, dynamic>;
      similar = sm.map((k, v) => MapEntry(int.parse(k), List<int>.from(v as List)));
    } catch (_) {}
    try {
      final ab = jsonDecode(await rootBundle.loadString('assets/data/asbab.json')) as Map<String, dynamic>;
      asbab = ab.map((k, v) => MapEntry(int.parse(k), v as String));
    } catch (_) {}
    loaded = true;
  }

  List<String> get norm => _norm ??= clean.map(normalizeAr).toList();

  Future<List<String>> translation() async {
    if (_translation != null) return _translation!;
    final raw = await rootBundle.loadString('assets/data/en.json');
    _translation = List<String>.from((await compute(decodeJson, raw)) as List);
    return _translation!;
  }

  Ayah at(int s, int a) => ayahs[surahStart[s] + a - 1];
  int gOf(int s, int a) => surahStart[s] + a - 1;
  int surahEndG(int s) => surahStart[s] + surahCount[s] - 1;
  int surahPage(int s) => ayahs[surahStart[s]].page;
  int surahOfPage(int p) => pageAyahs[p].isEmpty ? 1 : ayahs[pageAyahs[p].first].s;
  int juzOfPage(int p) => pageAyahs[p].isEmpty ? 1 : ayahs[pageAyahs[p].first].juz;
  int hizbOfPage(int p) => pageAyahs[p].isEmpty ? 1 : ayahs[pageAyahs[p].first].hizb;
  int juzPage(int j) => ayahs[juzStartG[j]].page;

  /// Words of the ayah without tashkeel, for comparing a recitation.
  List<String> cleanWords(int g) =>
      normalizeAr(clean[g]).split(' ').where((w) => w.isNotEmpty).toList();

  List<int> search(String query, {int limit = 400}) {
    final q = normalizeAr(query);
    if (q.isEmpty) return [];
    final out = <int>[];
    final n = norm;
    for (var i = 0; i < n.length; i++) {
      if (n[i].contains(q)) {
        out.add(i);
        if (out.length >= limit) break;
      }
    }
    return out;
  }
}
