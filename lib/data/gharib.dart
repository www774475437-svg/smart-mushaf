import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';

import 'layout.dart';
import 'quran.dart';

class WordMeaning {
  final String root;
  final String? head, text;
  const WordMeaning(this.root, this.head, this.text);
}

/// The root of every word of the Quran, and its entry in
/// «المفردات في غريب القرآن» للراغب الأصفهاني.
class Gharib {
  Gharib._();
  static final Gharib I = Gharib._();
  List<dynamic> _roots = const [];
  List<dynamic> _words = const [];
  List<dynamic> _book = const [];
  Future<void>? _f;

  Future<void> load() => _f ??= _load();

  Future<dynamic> _gz(String path) async {
    final d = await rootBundle.load(path);
    return jsonDecode(utf8.decode(GZipDecoder().decodeBytes(d.buffer.asUint8List(d.offsetInBytes, d.lengthInBytes))));
  }

  Future<void> _load() async {
    try {
      final r = await _gz('assets/gharib/roots.json.gz') as Map<String, dynamic>;
      _roots = r['r'] as List;
      _words = r['w'] as List;
      _book = await _gz('assets/gharib/mufradat.json.gz') as List;
    } catch (_) {}
  }

  List<dynamic>? _short;

  /// The hard words of the ayah from «الميسر في غريب القرآن» (مجمع الملك فهد).
  Future<String> ayahGharib(int g) async {
    try {
      _short ??= await _gz('assets/gharib/muyassar_gharib.json.gz') as List;
      return g < _short!.length ? _short![g] as String : '';
    } catch (_) {
      return '';
    }
  }

  /// The place of a word of the page inside its ayah (0 for the first word).
  int indexOf(LWord w) {
    final lay = MushafLayout.I;
    final start = QuranData.I.ayahs[w.g].page;
    var n = 0;
    for (var p = start; p <= start + 2 && p <= lay.pages.length; p++) {
      for (final l in lay.pages[p - 1]) {
        for (final x in l.words) {
          if (x.g != w.g || x.end) continue;
          if (identical(x, w)) return n;
          n++;
        }
      }
    }
    return -1;
  }

  Future<WordMeaning?> of(LWord w) async {
    await load();
    final i = indexOf(w);
    if (i < 0 || w.g >= _words.length) return null;
    final row = _words[w.g] as List;
    // the layout and the roots list must split the ayah into the same words
    var count = 0;
    final lay = MushafLayout.I;
    final start = QuranData.I.ayahs[w.g].page;
    for (var p = start; p <= start + 2 && p <= lay.pages.length; p++) {
      for (final l in lay.pages[p - 1]) {
        for (final x in l.words) {
          if (x.g == w.g && !x.end) count++;
        }
      }
    }
    if (count != row.length || i >= row.length) return null;
    final ri = row[i] as int;
    if (ri < 0 || ri >= _roots.length) return null;
    final r = _roots[ri] as List;
    final hi = r[1] as int;
    if (hi < 0 || hi >= _book.length) return WordMeaning(r[0] as String, null, null);
    final e = _book[hi] as List;
    return WordMeaning(r[0] as String, e[0] as String, e[1] as String);
  }
}
