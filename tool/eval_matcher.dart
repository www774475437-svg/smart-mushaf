// Replays what the offline listener heard (tool/sim_asr.py) through the app's own matcher and
// counts what a correct recitation would be wrongly blamed for.
import 'dart:convert';
import 'dart:io';

import '../lib/services/recite_matcher.dart';

void main(List<String> args) {
  final data = jsonDecode(File(args[0]).readAsStringSync()) as Map<String, dynamic>;
  final strict = args.length > 1 ? int.parse(args[1]) : 1;
  var tw = 0, tRed = 0, tBlue = 0, tLeft = 0, tFlick = 0;
  final lags = <double>[];
  print('model ${data['model']}  strict $strict');
  print('case | words | not reached | red | blue | lag after ayah (avg / worst, s)');
  for (final c in data['cases'] as List) {
    final ws = (c['words'] as List).cast<Map<String, dynamic>>();
    final clean = (c['clean'] as Map).cast<String, dynamic>();
    final count = <int, int>{}, pos = <int, int>{};
    for (final w in ws) {
      count[w['g'] as int] = (count[w['g'] as int] ?? 0) + 1;
    }
    final words = <MWord>[];
    for (var k = 0; k < ws.length; k++) {
      final g = ws[k]['g'] as int, t = ws[k]['t'] as String;
      final cl = normAr(clean['$g'] as String).split(' ').where((x) => x.isNotEmpty).toList();
      final p = pos[g] ?? 0;
      pos[g] = p + 1;
      words.add(MWord('$k', g, (cl.length == count[g] && p < cl.length) ? cl[p] : normAr(t), t));
    }
    final lastOf = <int, int>{};
    for (var k = 0; k < words.length; k++) {
      lastOf[words[k].g] = k;
    }
    final ends = (c['ends'] as Map).cast<String, dynamic>();
    final doneAt = <int, double>{};
    var idx = 0, done = '', from = 0, baseIdx = 0;
    var state = <String, int>{}, baseState = <String, int>{};
    var lastRaw = <String>[];
    final everRed = <String>{};
    for (final e in c['events'] as List) {
      final at = (e[0] as num).toDouble();
      final fin = e[1] == 'f';
      final heard = '$done ${e[2]}'.trim();
      if (fin) done = heard;
      final raw = heard.split(' ').where((w) => normAr(w).isNotEmpty).toList();
      lastRaw = raw;
      final out = matchRecitation(
          words: words, heard: raw.map(normAr).toList(), raw: raw, from: from, baseIdx: baseIdx, baseState: baseState, quiet: !fin, strict: strict);
      if (out.idx >= idx) {
        idx = out.idx;
        state = out.state;
      }
      if (fin) {
        // the same as the app: what is settled is never matched again
        from = raw.length;
        baseIdx = idx;
        baseState = Map.of(state);
      }
      state.forEach((k, v) {
        if (v == 2) everRed.add(k);
      });
      lastOf.forEach((g, k) {
        if (idx > k) doneAt.putIfAbsent(g, () => at);
      });
    }
    tFlick += everRed.where((k) => state[k] != 2).length;
    final red = [for (final w in words) if (state[w.key] == 2) w];
    final blue = [for (final w in words) if (state[w.key] == 4) w];
    final cl = <double>[];
    doneAt.forEach((g, at) => cl.add(at - (ends['$g'] as num).toDouble()));
    lags.addAll(cl);
    final avg = cl.isEmpty ? 0 : cl.reduce((a, b) => a + b) / cl.length;
    final worst = cl.isEmpty ? 0 : cl.reduce((a, b) => a > b ? a : b);
    print('${c['name']} | ${words.length} | ${words.length - idx} | ${red.length} | ${blue.length} | '
        '${avg.toStringAsFixed(1)} / ${worst.toStringAsFixed(1)}');
    if (red.isNotEmpty) print('   red: ${red.map((w) => w.norm).join('، ')}');
    if (blue.isNotEmpty) print('   blue: ${blue.map((w) => w.text).join('، ')}');
    if (idx < words.length) print('   stopped before: ${words[idx].norm}');
    if (red.isNotEmpty || blue.isNotEmpty || idx < words.length) print('   heard: ${lastRaw.join(' ')}');
    tw += words.length;
    tRed += red.length;
    tBlue += blue.length;
    tLeft += words.length - idx;
  }
  lags.sort();
  final med = lags.isEmpty ? 0 : lags[lags.length ~/ 2];
  final p90 = lags.isEmpty ? 0 : lags[(lags.length * 0.9).floor().clamp(0, lags.length - 1)];
  print('TOTAL words $tw | not reached $tLeft (${(100 * tLeft / tw).toStringAsFixed(2)}%) | red that came and went $tFlick | wrongly red $tRed (${(100 * tRed / tw).toStringAsFixed(2)}%) | '
      'wrongly blue $tBlue (${(100 * tBlue / tw).toStringAsFixed(2)}%) | lag median ${med.toStringAsFixed(1)}s, 90% under ${p90.toStringAsFixed(1)}s');
}
