import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'quran.dart';

class LWord {
  final int g;
  final String t;
  final bool end;

  /// Glyph code in the page font (empty when page fonts are not bundled).
  final String c;
  const LWord(this.g, this.t, this.end, this.c);
}

/// One of the 15 lines of a mushaf page.
class LLine {
  /// 'w' words, 's' surah header, 'b' basmala, '' empty.
  final String kind;
  final int surah;
  final List<LWord> words;
  const LLine(this.kind, {this.surah = 0, this.words = const []});
}

Map<String, dynamic> _decodeLayout(Uint8List b) =>
    jsonDecode(utf8.decode(GZipDecoder().decodeBytes(b))) as Map<String, dynamic>;

/// The Madinah mushaf layout: which words sit on which line of each page.
class MushafLayout {
  MushafLayout._();
  static final MushafLayout I = MushafLayout._();
  bool ready = false;
  bool qcf = false;
  final Set<int> _fontLoaded = {};
  final Map<int, Future<bool>> _fontLoading = {};

  bool fontReady(int page) => _fontLoaded.contains(page);

  /// Loads the printed-mushaf font of one page (each page has its own font).
  Future<bool> ensureFont(int page) {
    if (!qcf || page < 1 || page > 604) return Future.value(false);
    if (_fontLoaded.contains(page)) return Future.value(true);
    return _fontLoading.putIfAbsent(page, () async {
      try {
        final loader = FontLoader('QCF$page')..addFont(rootBundle.load('assets/qcf/p$page.ttf'));
        await loader.load();
        _fontLoaded.add(page);
        return true;
      } catch (_) {
        _fontLoading.remove(page);
        return false;
      }
    });
  }
  String basmala = '';

  /// The calligraphic basmala as glyphs of the page-1 font.
  String basmalaGlyphs = '';
  int qcfVersion = 0;
  final List<List<LLine>> pages = [];

  Future<void> load() async {
    if (ready) return;
    try {
      try {
        final v = jsonDecode(await rootBundle.loadString('assets/data/qcf.json'));
        qcfVersion = v is int ? v : (v == true ? 1 : 0);
      } catch (_) {
        qcfVersion = 0;
      }
      final ci = qcfVersion == 2 ? 3 : 4;
      final data = await rootBundle.load('assets/data/layout2.json.gz');
      final m = await compute(_decodeLayout, data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
      basmala = (m['b'] as String?) ?? '';
      final texts = <int, StringBuffer>{};
      for (final pg in (m['p'] as List)) {
        final lines = <LLine>[];
        for (final l in (pg as List)) {
          if (l == null) {
            lines.add(const LLine(''));
            continue;
          }
          final ll = l as List;
          final k = ll[0] as String;
          if (k == 's') {
            lines.add(LLine('s', surah: (ll[1] as num).toInt()));
          } else if (k == 'b') {
            lines.add(const LLine('b'));
          } else {
            final ws = <LWord>[];
            for (final w in (ll[1] as List)) {
              final wl = w as List;
              final g = (wl[0] as num).toInt();
              final t = wl[1] as String;
              final e = (wl[2] as num) == 1;
              ws.add(LWord(g, t, e, (qcfVersion > 0 && wl.length > ci) ? (wl[ci] as String? ?? '') : ''));
              if (!e) {
                final b = texts[g] ??= StringBuffer();
                if (b.isNotEmpty) b.write(' ');
                b.write(t);
              }
            }
            lines.add(LLine('w', words: ws));
          }
        }
        pages.add(lines);
      }
      if (pages.length == 604) {
        // Use the same King Fahd Complex text everywhere a verse is shown.
        final q = QuranData.I;
        texts.forEach((g, b) {
          if (g >= 0 && g < q.ayahs.length) q.ayahs[g].text = b.toString();
        });
        ready = true;
        qcf = qcfVersion > 0;
        final bg = m['bg'] as List?;
        if (qcf && bg != null && bg.length == 2) {
          basmalaGlyphs = (bg[qcfVersion == 2 ? 0 : 1] as String?) ?? '';
          ensureFont(1);
        }
      }
    } catch (_) {
      ready = false;
    }
  }
}
