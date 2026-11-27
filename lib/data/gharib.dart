import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'layout.dart';
import 'quran.dart';

/// What one book says about a word at its ayah.
class GharibRef {
  final String book, author, edition, title;
  final List<String> paragraphs;

  /// The paragraph that quotes the ayah (root dictionaries); 0 for the others.
  final int at;

  /// Where, inside that paragraph, the book quotes this very ayah (start == end: nowhere).
  final int start, end;
  const GharibRef(this.book, this.author, this.edition, this.title, this.paragraphs, this.at, this.start, this.end);
}

dynamic _decode(Uint8List b) => jsonDecode(utf8.decode(GZipDecoder().decodeBytes(b)));

/// A word that the reader pressed and that has no meaning in the books:
/// the pages that show its ayah colour their explained words for a moment.
final ValueNotifier<int> gharibFlash = ValueNotifier<int>(-1);

/// Meanings of the uncommon words (غريب القرآن), taken only from printed books:
/// المفردات للراغب (تحقيق الداودي)، عمدة الحفاظ للسمين الحلبي، التبيان لابن الهائم.
class Gharib {
  Gharib._();
  static final Gharib I = Gharib._();
  List<dynamic> _books = const [], _entries = const [], _words = const [], _counts = const [];
  Future<void>? _f;
  bool ready = false;

  Future<void> load() => _f ??= _load();

  Future<void> _load() async {
    try {
      final d = await rootBundle.load('assets/gharib/gharib.json.gz');
      final m = await compute(_decode, d.buffer.asUint8List(d.offsetInBytes, d.lengthInBytes)) as Map<String, dynamic>;
      _books = m['books'] as List;
      _entries = m['e'] as List;
      _words = m['w'] as List;
      _counts = m['n'] as List;
      ready = true;
    } catch (_) {}
  }

  int _before(int g, int page) {
    // words of the ayah printed on the pages before [page]
    final lay = MushafLayout.I;
    var n = 0;
    for (var p = QuranData.I.ayahs[g].page; p < page && p <= lay.pages.length; p++) {
      for (final l in lay.pages[p - 1]) {
        for (final x in l.words) {
          if (x.g == g && !x.end) n++;
        }
      }
    }
    return n;
  }

  bool _sameSplit(int g) {
    // the page layout and the books' word list must cut the ayah into the same words
    final lay = MushafLayout.I;
    final start = QuranData.I.ayahs[g].page;
    var n = 0;
    for (var p = start; p <= start + 2 && p <= lay.pages.length; p++) {
      for (final l in lay.pages[p - 1]) {
        for (final x in l.words) {
          if (x.g == g && !x.end) n++;
        }
      }
    }
    return g < _counts.length && n == _counts[g];
  }

  /// The place of every explained word of the page: 'line:index' keys.
  Set<String> pageKeys(int page) {
    final out = <String>{};
    if (!ready || !MushafLayout.I.ready) return out;
    final lines = MushafLayout.I.pages[page - 1];
    final pos = <int, int>{};
    final ok = <int, bool>{};
    for (var i = 0; i < lines.length; i++) {
      for (var k = 0; k < lines[i].words.length; k++) {
        final w = lines[i].words[k];
        if (w.end || w.g < 0 || w.g >= _words.length) continue;
        final idx = pos[w.g] ??= _before(w.g, page);
        pos[w.g] = idx + 1;
        if (!(ok[w.g] ??= _sameSplit(w.g))) continue;
        if ((_words[w.g] as Map).containsKey('$idx')) out.add('$i:$k');
      }
    }
    return out;
  }

  /// What the books say about this word of the page.
  List<GharibRef> refs(LWord w) {
    if (!ready || w.end || w.g < 0 || w.g >= _words.length || !_sameSplit(w.g)) return const [];
    final lay = MushafLayout.I;
    final start = QuranData.I.ayahs[w.g].page;
    var idx = -1, n = 0;
    for (var p = start; p <= start + 2 && p <= lay.pages.length && idx < 0; p++) {
      for (final l in lay.pages[p - 1]) {
        for (final x in l.words) {
          if (x.g != w.g || x.end) continue;
          if (identical(x, w)) idx = n;
          n++;
        }
      }
    }
    if (idx < 0) return const [];
    final l = (_words[w.g] as Map)['$idx'] as List?;
    if (l == null) return const [];
    final out = <GharibRef>[];
    for (final r in l) {
      final e = _entries[(r as List)[0] as int] as List;
      final b = _books[e[0] as int] as Map;
      out.add(GharibRef(b['name'] as String, b['author'] as String, b['ed'] as String, e[1] as String,
          (e[2] as String).split('\n'), r[1] as int, r.length > 3 ? r[2] as int : 0, r.length > 3 ? r[3] as int : 0));
    }
    out.sort((a, b) => _order(a.book).compareTo(_order(b.book)));
    return out;
  }

  int _order(String book) {
    for (var i = 0; i < _books.length; i++) {
      if ((_books[i] as Map)['name'] == book) return i;
    }
    return 99;
  }
}
