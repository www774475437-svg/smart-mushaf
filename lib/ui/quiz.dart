import 'dart:math';

import 'package:flutter/material.dart';

import '../data/quran.dart';
import '../data/surah_names.dart';
import '../services/store.dart';
import 'common.dart';
import 'reader.dart';

class _Question {
  final String title, prompt;
  final List<String> options;
  final int correct, g;
  final bool quranOptions;
  const _Question(this.title, this.prompt, this.options, this.correct, this.g, {this.quranOptions = true});
}

/// Multiple-choice tests that work without a microphone.
/// [kind] 0: complete the ayah, 1: similar ayahs (المتشابهات).
class QuizScreen extends StatefulWidget {
  final int kind;
  const QuizScreen({super.key, required this.kind});
  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  final _rnd = Random();
  int scope = 1; // 0 my memorized, 1 a juz, 2 whole Quran
  int juz = 30;
  List<int> pool = [];
  _Question? cur;
  int? chosen;
  int right = 0, total = 0;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    if (_myPool().length >= 8) scope = 0;
    _rebuild();
    _started = true;
  }

  List<int> _myPool() {
    final q = QuranData.I;
    final st = UserStore.I;
    final out = <int>{};
    for (final s in st.memorized) {
      for (var g = q.surahStart[s]; g <= q.surahEndG(s); g++) {
        out.add(g);
      }
    }
    for (final p in st.pageStatus.keys) {
      if (p >= 1 && p <= 604) out.addAll(q.pageAyahs[p]);
    }
    return out.toList()..sort();
  }

  void _rebuild() {
    final q = QuranData.I;
    if (scope == 0) {
      pool = _myPool();
    } else if (scope == 1) {
      final from = q.juzStartG[juz];
      final to = juz < 30 ? q.juzStartG[juz + 1] - 1 : q.ayahs.length - 1;
      pool = [for (var g = from; g <= to; g++) g];
    } else {
      pool = [for (var g = 0; g < q.ayahs.length; g++) g];
    }
    right = 0;
    total = 0;
    _next();
  }

  List<String> _words(int g) => QuranData.I.ayahs[g].text.split(' ').where((w) => w.isNotEmpty).toList();

  /// Shuffles the candidates (first one is the right answer) and drops repeated texts.
  _Question? _make(String title, String prompt, List<String> cands, int g, {bool quran = true}) {
    final seen = <String>{};
    final opts = <String>[];
    for (final c in cands) {
      final k = normalizeAr(c);
      if (k.isEmpty || !seen.add(k)) continue;
      opts.add(c);
      if (opts.length == 4) break;
    }
    if (opts.length < 2 || normalizeAr(cands.first) != normalizeAr(opts.first)) return null;
    final answer = opts.first;
    opts.shuffle(_rnd);
    return _Question(title, prompt, opts, opts.indexOf(answer), g, quranOptions: quran);
  }

  List<int> _near(int g, int n) {
    final q = QuranData.I;
    final s = q.ayahs[g].s;
    final c = <int>[
      for (var x = max(q.surahStart[s], g - 12); x <= min(q.surahEndG(s), g + 12); x++)
        if ((x - g).abs() > 1) x
    ]..shuffle(_rnd);
    while (c.length < n) {
      c.add(_rnd.nextInt(q.ayahs.length));
    }
    return c.take(n).toList();
  }

  _Question? _complete(int g) {
    final q = QuranData.I;
    final w = _words(g);
    final sim = q.similar[g] ?? const <int>[];
    if (w.length >= 6 && _rnd.nextInt(3) > 0) {
      final cut = (w.length / 2).ceil();
      String tail(int x) {
        final ww = _words(x);
        if (ww.length < 3) return '';
        final c = ww.length > cut + 1 ? cut : ww.length ~/ 2;
        return ww.sublist(c).join(' ');
      }

      return _make('أكمل الآية', '${w.sublist(0, cut).join(' ')} …',
          [w.sublist(cut).join(' '), for (final x in sim) tail(x), for (final x in _near(g, 6)) tail(x)], g);
    }
    if (g >= q.surahEndG(q.ayahs[g].s)) return null;
    return _make('ما الآية التي بعدها؟', q.ayahs[g].text,
        [q.ayahs[g + 1].text, for (final x in sim) if (x + 1 < q.ayahs.length) q.ayahs[x + 1].text, for (final x in _near(g + 1, 6)) q.ayahs[x].text], g + 1);
  }

  _Question? _similar(int g) {
    final q = QuranData.I;
    final me = q.norm[g];
    final sim = [for (final x in q.similar[g] ?? const <int>[]) if (q.norm[x] != me) x];
    if (sim.isEmpty) return null;
    final s = q.ayahs[g].s;
    final type = _rnd.nextInt(3);
    if (type == 0) {
      final others = <int>{for (final x in sim) if (q.ayahs[x].s != s) q.ayahs[x].s};
      if (others.isEmpty) return null;
      final c = [s, ...others];
      while (c.length < 4) {
        final r = 1 + _rnd.nextInt(114);
        if (!c.contains(r)) c.add(r);
      }
      return _make('في أي سورة وردت هذه الآية؟', q.ayahs[g].text, [for (final x in c) 'سورة ${surahName(x)}'], g, quran: false);
    }
    if (type == 1) {
      // The words where this ayah parts from its look-alike.
      final w = _words(g);
      final o = _words(sim.first);
      var cut = 0;
      while (cut < w.length && cut < o.length && normalizeAr(w[cut]) == normalizeAr(o[cut])) {
        cut++;
      }
      if (cut < 2 || cut >= w.length) return null;
      String tail(int x) {
        final ww = _words(x);
        return ww.length > cut ? ww.sublist(cut).join(' ') : '';
      }

      return _make('أكمل الآية كما في سورة ${surahName(s)}', '${w.sublist(0, cut).join(' ')} …',
          [tail(g), for (final x in sim) tail(x)], g);
    }
    if (g >= q.surahEndG(s)) return null;
    return _make('ما الآية التي بعدها في سورة ${surahName(s)}؟', q.ayahs[g].text,
        [q.ayahs[g + 1].text, for (final x in sim) if (x + 1 < q.ayahs.length) q.ayahs[x + 1].text, for (final x in _near(g + 1, 3)) q.ayahs[x].text], g + 1);
  }

  void _next() {
    _Question? n;
    if (pool.isNotEmpty) {
      for (var i = 0; i < 300 && n == null; i++) {
        final g = pool[_rnd.nextInt(pool.length)];
        n = widget.kind == 0 ? _complete(g) : _similar(g);
      }
    }
    cur = n;
    chosen = null;
    if (_started && mounted) setState(() {});
  }

  void _pick(int i) {
    if (chosen != null || cur == null) return;
    final ok = i == cur!.correct;
    setState(() {
      chosen = i;
      total++;
      if (ok) right++;
    });
    UserStore.I.logQuiz(ok);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = cur;
    final q = QuranData.I;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.kind == 0 ? 'اختبار أكمل الآية' : 'اختبار المتشابهات'),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsetsDirectional.only(end: 16),
              child: Text('${ar(right)} من ${ar(total)}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
        children: [
          Row(
            children: [
              Expanded(
                child: Pills<int>(
                  values: const [0, 1, 2],
                  selected: scope,
                  label: (v) => v == 0 ? 'محفوظي' : (v == 1 ? 'جزء' : 'القرآن كله'),
                  onChanged: (v) {
                    scope = v;
                    _rebuild();
                  },
                ),
              ),
              if (scope == 1)
                DropdownButton<int>(
                  value: juz,
                  underline: const SizedBox.shrink(),
                  items: [for (var j = 1; j <= 30; j++) DropdownMenuItem(value: j, child: Text('الجزء ${ar(j)}'))],
                  onChanged: (v) {
                    juz = v ?? juz;
                    _rebuild();
                  },
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (c == null)
            Padding(
              padding: const EdgeInsets.all(30),
              child: Text(
                scope == 0
                    ? 'لم تسجّل محفوظًا بعد. علّم السور التي حفظتها في «التسميع»، أو اختر جزءًا من الأعلى.'
                    : 'لا توجد أسئلة في هذا الموضع. اختر جزءًا آخر.',
                textAlign: TextAlign.center,
                style: const TextStyle(height: 1.8),
              ),
            )
          else ...[
            Text(c.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: kGoldDeep)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: kGold.withValues(alpha: 0.5)),
              ),
              child: Text(c.prompt,
                  textAlign: TextAlign.center, style: TextStyle(fontFamily: quranFont(), fontSize: 22, height: 2.0)),
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < c.options.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: chosen == null
                      ? cs.surface
                      : (i == c.correct
                          ? const Color(0xFF43A047).withValues(alpha: 0.22)
                          : (i == chosen ? Colors.red.withValues(alpha: 0.2) : cs.surface)),
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => _pick(i),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: chosen != null && i == c.correct ? const Color(0xFF43A047) : Colors.grey.withValues(alpha: 0.3)),
                      ),
                      child: Text(c.options[i],
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: c.quranOptions
                              ? TextStyle(fontFamily: quranFont(), fontSize: 19, height: 1.9)
                              : const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ),
              ),
            if (chosen != null) ...[
              const SizedBox(height: 4),
              Text(
                '${chosen == c.correct ? 'أحسنت' : 'الجواب الصحيح ملوّن بالأخضر'} • ${q.ayahs[c.g].ref}',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontWeight: FontWeight.w700, color: chosen == c.correct ? const Color(0xFF2E7D32) : Colors.red),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                      onPressed: () => MushafScreen.open(context, q.ayahs[c.g].page, flashG: c.g),
                      icon: const Icon(Icons.menu_book_rounded),
                      label: const Text('افتح في المصحف'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50), backgroundColor: kEmerald),
                      onPressed: _next,
                      icon: const Icon(Icons.arrow_back_rounded),
                      label: const Text('السؤال التالي'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}
