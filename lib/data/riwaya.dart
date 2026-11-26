import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'quran.dart';

class Riwaya {
  final String id, name;
  final String? edition;
  const Riwaya(this.id, this.name, this.edition);
}

const List<Riwaya> kRiwayat = [
  Riwaya('hafs', 'حفص عن عاصم', null),
  Riwaya('warsh', 'ورش عن نافع', 'ara-quranwarsh'),
  Riwaya('qaloon', 'قالون عن نافع', 'ara-quranqaloon'),
  Riwaya('shouba', 'شعبة عن عاصم', 'ara-quranshouba'),
  Riwaya('doori', 'الدوري عن أبي عمرو', 'ara-qurandoori'),
  Riwaya('soosi', 'السوسي عن أبي عمرو', 'ara-quransoosi'),
  Riwaya('bazzi', 'البزي عن ابن كثير', 'ara-quranbazzi'),
  Riwaya('qumbul', 'قنبل عن ابن كثير', 'ara-quranqumbul'),
];

Riwaya riwayaById(String id) => kRiwayat.firstWhere((r) => r.id == id, orElse: () => kRiwayat.first);

class RiwayaService {
  RiwayaService._();
  static final RiwayaService I = RiwayaService._();
  final Map<String, Map<int, List<String>>> _cache = {};

  Future<File> _file(String id) async {
    final d = await getApplicationDocumentsDirectory();
    return File('${d.path}/riwaya_$id.json');
  }

  Future<bool> isDownloaded(String id) async {
    if (id == 'hafs') return true;
    return (await _file(id)).exists();
  }

  Future<void> download(Riwaya r) async {
    if (r.edition == null) return;
    final urls = [
      'https://cdn.jsdelivr.net/gh/fawazahmed0/quran-api@1/editions/${r.edition}.min.json',
      'https://cdn.jsdelivr.net/gh/fawazahmed0/quran-api@1/editions/${r.edition}.json',
      'https://raw.githubusercontent.com/fawazahmed0/quran-api/1/editions/${r.edition}.json',
    ];
    Object? last;
    for (final u in urls) {
      try {
        final res = await http.get(Uri.parse(u)).timeout(const Duration(minutes: 2));
        if (res.statusCode != 200) {
          last = 'http ${res.statusCode}';
          continue;
        }
        final m = (await compute(decodeJson, utf8.decode(res.bodyBytes))) as Map<String, dynamic>;
        final out = <String, List<String>>{};
        for (final v in (m['quran'] as List)) {
          final vm = v as Map<String, dynamic>;
          final ch = (vm['chapter'] as num).toInt().toString();
          (out[ch] ??= []).add((vm['text'] as String? ?? '').trim());
        }
        if (out.length < 114) {
          last = 'incomplete';
          continue;
        }
        await (await _file(r.id)).writeAsString(jsonEncode(out));
        _cache.remove(r.id);
        return;
      } catch (e) {
        last = e;
      }
    }
    throw Exception('download failed: $last');
  }

  Future<Map<int, List<String>>> load(String id) async {
    if (_cache.containsKey(id)) return _cache[id]!;
    final f = await _file(id);
    final m = (await compute(decodeJson, await f.readAsString())) as Map<String, dynamic>;
    final out = <int, List<String>>{};
    m.forEach((k, v) => out[int.parse(k)] = List<String>.from(v as List));
    _cache[id] = out;
    return out;
  }
}
