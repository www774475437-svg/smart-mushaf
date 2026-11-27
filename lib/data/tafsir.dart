import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'quran.dart';

class TafsirSource {
  final String id, name, author;
  final String? cloud;
  final int? qcom;

  /// Books of the downloadable library live in the repository's `library` branch.
  final bool remote;
  final String lang, langName, group;
  const TafsirSource(this.id, this.name, this.author,
      {this.cloud, this.qcom, this.remote = false, this.lang = 'ar', this.langName = 'العربية', this.group = 'tafsir'});
  bool get rtl => const {'ar', 'ur', 'fa', 'ps', 'ug', 'ku'}.contains(lang);
  String get title => lang == 'ar' ? name : '$name — $langName';
  bool get bundled => TafsirService.I.bundledIds.contains(id);
}

const List<TafsirSource> kTafsirs = [
  TafsirSource('muyassar', 'التفسير الميسر', 'نخبة من العلماء - مجمع الملك فهد', cloud: 'ar.muyassar', qcom: 16),
  TafsirSource('saadi', 'تفسير السعدي', 'عبد الرحمن بن ناصر السعدي', qcom: 91),
  TafsirSource('ibnkathir', 'تفسير ابن كثير', 'إسماعيل بن عمر بن كثير', qcom: 14),
  TafsirSource('tabari', 'تفسير الطبري', 'محمد بن جرير الطبري', qcom: 15),
  TafsirSource('baghawi', 'تفسير البغوي', 'الحسين بن مسعود البغوي', cloud: 'ar.baghawi', qcom: 94),
  TafsirSource('qurtubi', 'تفسير القرطبي', 'محمد بن أحمد القرطبي', cloud: 'ar.qurtubi', qcom: 90),
  TafsirSource('jalalayn', 'تفسير الجلالين', 'المحلي والسيوطي', cloud: 'ar.jalalayn'),
  TafsirSource('waseet', 'التفسير الوسيط', 'محمد سيد طنطاوي', cloud: 'ar.waseet', qcom: 93),
];

const String kLibraryUrl = 'https://raw.githubusercontent.com/www774475437-svg/smart-mushaf/library';

const String kGroupedNote = 'تفسير هذه الآية مذكور مع الآيات التي قبلها في هذا التفسير.';

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

List<String> _decodeGz(Uint8List b) {
  final bytes = GZipDecoder().decodeBytes(b);
  return List<String>.from(jsonDecode(utf8.decode(bytes)) as List);
}

class TafsirService {
  TafsirService._();
  static final TafsirService I = TafsirService._();

  Set<String> bundledIds = {};
  final Map<String, List<String>> _full = {};
  final Map<String, Map<int, String>> _part = {};
  final Map<String, List<String>> _normFull = {};
  String _docs = '';

  /// Extra tafsirs, word-meaning books and tafsirs in other languages, downloaded on request.
  List<TafsirSource> library = [];
  Set<String> downloaded = {};

  Future<void> init() async {
    try {
      final raw = await rootBundle.loadString('assets/data/tafsirs.json');
      bundledIds = Set<String>.from(jsonDecode(raw) as List);
    } catch (_) {
      bundledIds = {};
    }
    try {
      final raw = await rootBundle.loadString('assets/gharib/library.json');
      library = [
        for (final e in (jsonDecode(raw) as List).cast<Map<String, dynamic>>())
          TafsirSource(e['id'] as String, e['name'] as String, e['author'] as String,
              remote: true, lang: e['lang'] as String, langName: e['langName'] as String, group: e['group'] as String),
      ];
    } catch (_) {}
    try {
      final p = await SharedPreferences.getInstance();
      downloaded = (p.getStringList('libDownloaded') ?? const []).toSet();
    } catch (_) {}
  }

  Future<void> _saveDownloaded() async {
    try {
      (await SharedPreferences.getInstance()).setStringList('libDownloaded', downloaded.toList());
    } catch (_) {}
  }

  TafsirSource byId(String id) {
    for (final t in kTafsirs) {
      if (t.id == id) return t;
    }
    for (final t in library) {
      if (t.id == id) return t;
    }
    return kTafsirs.first;
  }

  /// The tafsirs shown under an ayah: the ones inside the app, then the downloaded ones.
  List<TafsirSource> get active => [...kTafsirs, ...library.where((t) => downloaded.contains(t.id))];

  Future<File> _libFile(TafsirSource t) async => File('${await _dir()}/lib_${t.id}.json.gz');

  Future<List<String>> _fetchLib(TafsirSource t) async {
    final r = await http.get(Uri.parse('$kLibraryUrl/${t.id}.json.gz')).timeout(const Duration(minutes: 4));
    if (r.statusCode != 200) throw Exception('http ${r.statusCode}');
    final l = await compute(_decodeGz, r.bodyBytes);
    try {
      await (await _libFile(t)).writeAsBytes(r.bodyBytes);
    } catch (_) {}
    return l;
  }

  Future<String> _dir() async {
    if (kIsWeb) throw UnsupportedError('web');
    if (_docs.isEmpty) _docs = (await getApplicationDocumentsDirectory()).path;
    return _docs;
  }

  Future<File> _fullFile(TafsirSource t) async => File('${await _dir()}/tafsir_${t.id}_full.json');
  Future<File> _partFile(TafsirSource t) async => File('${await _dir()}/tafsir_${t.id}_part.json');

  Future<bool> isAvailableOffline(TafsirSource t) async {
    if (t.remote) return downloaded.contains(t.id);
    if (t.bundled || _full.containsKey(t.id)) return true;
    try {
      return await (await _fullFile(t)).exists();
    } catch (_) {
      return false;
    }
  }

  Future<List<String>?> fullList(TafsirSource t) async {
    if (_full.containsKey(t.id)) return _full[t.id];
    if (t.remote) {
      if (!downloaded.contains(t.id)) return null;
      try {
        final f = await _libFile(t);
        if (await f.exists()) {
          return _full[t.id] = await compute(_decodeGz, await f.readAsBytes());
        }
      } catch (_) {}
      // the website keeps no files: read the book again from the library
      try {
        return _full[t.id] = await _fetchLib(t);
      } catch (_) {
        return null;
      }
    }
    if (t.bundled) {
      try {
        final data = await rootBundle.load('assets/data/tafsir_${t.id}.json.gz');
        final l = await compute(_decodeGz, data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
        _full[t.id] = l;
        return l;
      } catch (_) {}
    }
    try {
      final f = await _fullFile(t);
      if (await f.exists()) {
        final l = List<String>.from((await compute(decodeJson, await f.readAsString())) as List);
        _full[t.id] = l;
        return l;
      }
    } catch (_) {}
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

  /// When a tafsir explains several ayahs together, the later ones are empty:
  /// show the text of the ayah the group starts with.
  String _resolve(List<String> full, int g) {
    final t = full[g];
    if (t.trim().isNotEmpty && t != kGroupedNote) return t;
    final s = QuranData.I.ayahs[g].s;
    for (var k = g - 1; k >= 0 && k >= g - 40; k--) {
      if (QuranData.I.ayahs[k].s != s) break;
      final p = full[k];
      if (p.trim().isNotEmpty && p != kGroupedNote) {
        return '(هذه الآية مفسَّرة مع الآية ${QuranData.I.ayahs[k].a})\n\n$p';
      }
    }
    return kGroupedNote;
  }

  Future<String> get(String id, int g) async {
    final t = byId(id);
    final full = await fullList(t);
    if (full != null && g < full.length) return _resolve(full, g);
    if (t.remote) throw Exception('not downloaded');
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
    if (text == null) throw Exception('offline');
    if (text.isEmpty) text = kGroupedNote;
    part[g] = text;
    await _savePart(t);
    return text;
  }

  /// Downloads a whole tafsir so it works without internet (for ones not inside the app).
  Future<void> download(TafsirSource t, void Function(double p) onProgress) async {
    if (t.bundled) return;
    if (t.remote) {
      onProgress(0.2);
      _full[t.id] = await _fetchLib(t);
      downloaded.add(t.id);
      await _saveDownloaded();
      onProgress(1);
      return;
    }
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
    _full[t.id] = out;
    try {
      final f = await _fullFile(t);
      await f.writeAsString(jsonEncode(out));
    } catch (_) {}
    onProgress(1);
  }

  Future<void> remove(TafsirSource t) async {
    if (t.bundled) return;
    if (t.remote) {
      downloaded.remove(t.id);
      await _saveDownloaded();
      try {
        final f = await _libFile(t);
        if (await f.exists()) await f.delete();
      } catch (_) {}
      _full.remove(t.id);
      _normFull.remove(t.id);
      return;
    }
    try {
      final f = await _fullFile(t);
      if (await f.exists()) await f.delete();
    } catch (_) {}
    _full.remove(t.id);
    _normFull.remove(t.id);
  }

  Future<List<int>> search(TafsirSource t, String query, {int limit = 300}) async {
    final full = await fullList(t);
    if (full == null) return [];
    final n = _normFull[t.id] ??= await compute(_normAll, full);
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

List<String> _normAll(List<String> l) => l.map(normalizeAr).toList();
