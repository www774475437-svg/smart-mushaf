import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'quran.dart';

class TafsirSource {
  final String id, name, author;
  final String? asset;
  final String? cloud;
  final int? qcom;
  const TafsirSource(this.id, this.name, this.author, {this.asset, this.cloud, this.qcom});
  bool get bundled => asset != null;
}

const List<TafsirSource> kTafsirs = [
  TafsirSource('muyassar', 'التفسير الميسر', 'مجمع الملك فهد', asset: 'assets/data/muyassar.json'),
  TafsirSource('saadi', 'تفسير السعدي', 'عبد الرحمن السعدي', qcom: 91),
  TafsirSource('ibnkathir', 'تفسير ابن كثير', 'ابن كثير', qcom: 14),
  TafsirSource('tabari', 'تفسير الطبري', 'ابن جرير الطبري', qcom: 15),
  TafsirSource('baghawi', 'تفسير البغوي', 'البغوي', cloud: 'ar.baghawi', qcom: 94),
  TafsirSource('qurtubi', 'تفسير القرطبي', 'القرطبي', cloud: 'ar.qurtubi', qcom: 90),
  TafsirSource('jalalayn', 'تفسير الجلالين', 'المحلي والسيوطي', asset: 'assets/data/jalalayn.json'),
  TafsirSource('waseet', 'التفسير الوسيط', 'محمد سيد طنطاوي', cloud: 'ar.waseet', qcom: 93),
];

String cleanHtml(String s) {
  var t = s
      .replaceAll(RegExp(r'<\s*br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</\s*p\s*>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]*>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&amp;', '&');
  t = t.replaceAll(RegExp(r'[ \t]+'), ' ').replaceAll(RegExp(r'\n\s*\n+'), '\n\n');
  return t.trim();
}

class TafsirService {
  TafsirService._();
  static final TafsirService I = TafsirService._();

  final Map<String, List<String>> _full = {};
  final Map<String, Map<int, String>> _part = {};
  final Map<String, List<String>> _normFull = {};
  String _docs = '';

  TafsirSource byId(String id) => kTafsirs.firstWhere((t) => t.id == id, orElse: () => kTafsirs.first);

  Future<String> _dir() async {
    if (_docs.isEmpty) _docs = (await getApplicationDocumentsDirectory()).path;
    return _docs;
  }

  Future<File> _fullFile(TafsirSource t) async => File('${await _dir()}/tafsir_${t.id}_full.json');
  Future<File> _partFile(TafsirSource t) async => File('${await _dir()}/tafsir_${t.id}_part.json');

  Future<bool> isAvailableOffline(TafsirSource t) async {
    if (t.bundled) return true;
    return (await _fullFile(t)).exists();
  }

  Future<List<String>?> fullList(TafsirSource t) async {
    if (_full.containsKey(t.id)) return _full[t.id];
    if (t.asset != null) {
      final raw = await rootBundle.loadString(t.asset!);
      final l = List<String>.from((await compute(decodeJson, raw)) as List);
      _full[t.id] = l;
      return l;
    }
    final f = await _fullFile(t);
    if (await f.exists()) {
      try {
        final l = List<String>.from((await compute(decodeJson, await f.readAsString())) as List);
        _full[t.id] = l;
        return l;
      } catch (_) {}
    }
    return null;
  }

  Future<Map<int, String>> _loadPart(TafsirSource t) async {
    if (_part.containsKey(t.id)) return _part[t.id]!;
    final m = <int, String>{};
    try {
      final f = await _partFile(t);
      if (await f.exists()) {
        final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        j.forEach((k, v) => m[int.parse(k)] = v as String);
      }
    } catch (_) {}
    _part[t.id] = m;
    return m;
  }

  Future<void> _savePart(TafsirSource t) async {
    try {
      final m = _part[t.id] ?? {};
      final f = await _partFile(t);
      await f.writeAsString(jsonEncode(m.map((k, v) => MapEntry(k.toString(), v))));
    } catch (_) {}
  }

  Future<String> get(String id, int g) async {
    final t = byId(id);
    final full = await fullList(t);
    if (full != null && g < full.length) return full[g];
    final part = await _loadPart(t);
    if (part.containsKey(g)) return part[g]!;
    final ay = QuranData.I.ayahs[g];
    String? text;
    if (t.qcom != null) {
      try {
        final r = await http
            .get(Uri.parse('https://api.quran.com/api/v4/tafsirs/${t.qcom}/by_ayah/${ay.s}:${ay.a}'))
            .timeout(const Duration(seconds: 25));
        if (r.statusCode == 200) {
          final m = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
          final tf = m['tafsir'] as Map<String, dynamic>?;
          text = cleanHtml((tf?['text'] as String?) ?? '');
        }
      } catch (_) {}
    }
    if ((text == null || text.isEmpty) && t.cloud != null) {
      try {
        final r = await http
            .get(Uri.parse('https://api.alquran.cloud/v1/ayah/${g + 1}/${t.cloud}'))
            .timeout(const Duration(seconds: 25));
        if (r.statusCode == 200) {
          final m = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
          text = cleanHtml(((m['data'] as Map<String, dynamic>)['text'] as String?) ?? '');
        }
      } catch (_) {}
    }
    if (text == null) {
      throw Exception('offline');
    }
    if (text.isEmpty) {
      text = 'تفسير هذه الآية مذكور مع الآيات التي قبلها في هذا التفسير.';
    }
    part[g] = text;
    await _savePart(t);
    return text;
  }

  /// Downloads a whole tafsir so it works without internet.
  Future<void> download(TafsirSource t, void Function(double p) onProgress) async {
    if (t.bundled) return;
    final out = List<String>.filled(6236, '');
    if (t.cloud != null) {
      onProgress(0.1);
      final r = await http
          .get(Uri.parse('https://api.alquran.cloud/v1/quran/${t.cloud}'))
          .timeout(const Duration(minutes: 3));
      if (r.statusCode != 200) throw Exception('http ${r.statusCode}');
      onProgress(0.7);
      final m = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      var i = 0;
      for (final s in ((m['data'] as Map<String, dynamic>)['surahs'] as List)) {
        for (final a in ((s as Map<String, dynamic>)['ayahs'] as List)) {
          if (i < 6236) out[i] = cleanHtml(((a as Map<String, dynamic>)['text'] as String?) ?? '');
          i++;
        }
      }
    } else if (t.qcom != null) {
      final q = QuranData.I;
      for (var ch = 1; ch <= 114; ch++) {
        var page = 1;
        while (true) {
          final r = await http
              .get(Uri.parse(
                  'https://api.quran.com/api/v4/tafsirs/${t.qcom}/by_chapter/$ch?per_page=50&page=$page'))
              .timeout(const Duration(seconds: 40));
          if (r.statusCode != 200) throw Exception('http ${r.statusCode}');
          final m = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
          for (final it in (m['tafsirs'] as List? ?? const [])) {
            final mm = it as Map<String, dynamic>;
            final key = (mm['verse_key'] as String?) ?? '';
            final parts = key.split(':');
            if (parts.length == 2) {
              final s = int.tryParse(parts[0]) ?? 0;
              final a = int.tryParse(parts[1]) ?? 0;
              if (s >= 1 && s <= 114 && a >= 1 && a <= q.surahCount[s]) {
                out[q.gOf(s, a)] = cleanHtml((mm['text'] as String?) ?? '');
              }
            }
          }
          final pg = m['pagination'] as Map<String, dynamic>?;
          final next = pg?['next_page'];
          if (next == null) break;
          page = (next as num).toInt();
        }
        onProgress(ch / 114);
      }
    }
    for (var i = 0; i < out.length; i++) {
      if (out[i].isEmpty) out[i] = 'تفسير هذه الآية مذكور مع الآيات التي قبلها في هذا التفسير.';
    }
    final f = await _fullFile(t);
    await f.writeAsString(jsonEncode(out));
    _full[t.id] = out;
    onProgress(1);
  }

  Future<void> remove(TafsirSource t) async {
    if (t.bundled) return;
    final f = await _fullFile(t);
    if (await f.exists()) await f.delete();
    _full.remove(t.id);
    _normFull.remove(t.id);
  }

  Future<List<int>> search(TafsirSource t, String query, {int limit = 300}) async {
    final full = await fullList(t);
    if (full == null) return [];
    final n = _normFull[t.id] ??= full.map(normalizeAr).toList();
    final q = normalizeAr(query);
    if (q.isEmpty) return [];
    final out = <int>[];
    for (var i = 0; i < n.length; i++) {
      if (n[i].contains(q)) {
        out.add(i);
        if (out.length >= limit) break;
      }
    }
    return out;
  }
}
