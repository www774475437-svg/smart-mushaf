import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

const List<String> kQuizTypes = [
  'كل الأنواع',
  'أكمل الآية',
  'الآية التالية',
  'الآية السابقة',
  'اسم السورة',
  'الكلمة الناقصة',
  'ترتيب الآيات',
  'بداية الصفحة',
  'بداية الجزء',
];

/// Multiple-choice tests that work without a microphone and without the internet.
/// [kind] 0: complete the ayah, 1: similar ayahs (المتشابهات), 2: the full memorization
/// test with every kind of question, 3: questions made from the user's own mistakes.
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
  int _askedG = -1;
  int type = 0; // kind 2: which kind of question, 0 for all

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
    if (widget.kind == 3) {
      pool = [for (final m in UserStore.I.mistakes) m.g];
    } else if (scope == 0) {
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

  String _short(int g) {
    final w = _words(g);
    return w.length <= 9 ? w.join(' ') : '${w.take(9).join(' ')} …';
  }

  _Question? _previous(int g) {
    final q = QuranData.I;
    if (g <= q.surahStart[q.ayahs[g].s]) return null;
    return _make('ما الآية التي قبلها؟', q.ayahs[g].text,
        [q.ayahs[g - 1].text, for (final x in _near(g - 1, 6)) q.ayahs[x].text], g - 1);
  }

  _Question? _whichSurah(int g) {
    final q = QuranData.I;
    final s = q.ayahs[g].s;
    if (_words(g).length < 4) return null;
    final c = <int>[s];
    // the surahs next to it are the ones most easily mixed up with it
    for (final d in [1, -1, 2, -2, 3]) {
      if (s + d >= 1 && s + d <= 114 && c.length < 4 && _rnd.nextBool()) c.add(s + d);
    }
    while (c.length < 4) {
      final r = 1 + _rnd.nextInt(114);
      if (!c.contains(r)) c.add(r);
    }
    return _make('في أي سورة هذه الآية؟', q.ayahs[g].text, [for (final x in c) 'سورة ${surahName(x)}'], g, quran: false);
  }

  _Question? _missing(int g) {
    final w = _words(g);
    if (w.length < 5) return null;
    final i = 1 + _rnd.nextInt(w.length - 2);
    final others = <String>[];
    for (final x in _near(g, 8)) {
      final ww = _words(x);
      if (ww.length > 2) others.add(ww[_rnd.nextInt(ww.length)]);
    }
    final shown = [...w]..[i] = '⋯⋯';
    return _make('ما الكلمة الناقصة؟', shown.join(' '), [w[i], ...others], g);
  }

  _Question? _order(int g) {
    final q = QuranData.I;
    final s = q.ayahs[g].s;
    final from = q.surahStart[s], to = q.surahEndG(s);
    if (to - from < 4) return null;
    final picks = <int>{g};
    for (var i = 0; i < 40 && picks.length < 4; i++) {
      picks.add(from + _rnd.nextInt(to - from + 1));
    }
    if (picks.length < 4) return null;
    final sorted = picks.toList()..sort();
    return _make('أي هذه الآيات تأتي أولًا في سورة ${surahName(s)}؟', 'رتّبها في ذهنك ثم اختر أولها',
        [for (final x in sorted) _short(x)], sorted.first);
  }

  _Question? _pageStart(int g) {
    final q = QuranData.I;
    final page = q.ayahs[g].page;
    final ids = q.pageAyahs[page];
    if (ids.length < 2) return null;
    final first = ids.first;
    return _make('ما أول آية في الصفحة ${ar(page)}؟', 'سورة ${surahName(q.ayahs[first].s)} • الجزء ${ar(q.ayahs[first].juz)}',
        [_short(first), for (final x in ids.skip(1).take(2)) _short(x), if (page > 1) _short(q.pageAyahs[page - 1].first), if (page < 604) _short(q.pageAyahs[page + 1].first)],
        first);
  }

  _Question? _juzStart(int g) {
    final q = QuranData.I;
    final j = q.ayahs[g].juz;
    final first = q.juzStartG[j];
    return _make('بأي آية يبدأ الجزء ${ar(j)}؟', 'اختر الآية الأولى من الجزء',
        [_short(first), if (j > 1) _short(q.juzStartG[j - 1]), if (j < 30) _short(q.juzStartG[j + 1]), _short(first + 1), _short(first + 2)], first);
  }

  _Question? _full(int g) {
    final t = type == 0 ? 1 + _rnd.nextInt(8) : type;
    switch (t) {
      case 1:
        final w = _words(g);
        if (w.length < 6) return null;
        final cut = (w.length / 2).ceil();
        String tail(int x) {
          final ww = _words(x);
          if (ww.length < 3) return '';
          return ww.sublist(ww.length > cut + 1 ? cut : ww.length ~/ 2).join(' ');
        }
        return _make('أكمل الآية', '${w.sublist(0, cut).join(' ')} …',
            [w.sublist(cut).join(' '), for (final x in QuranData.I.similar[g] ?? const <int>[]) tail(x), for (final x in _near(g, 6)) tail(x)], g);
      case 2:
        final q = QuranData.I;
        if (g >= q.surahEndG(q.ayahs[g].s)) return null;
        return _make('ما الآية التي بعدها؟', q.ayahs[g].text,
            [q.ayahs[g + 1].text, for (final x in _near(g + 1, 6)) q.ayahs[x].text], g + 1);
      case 3:
        return _previous(g);
      case 4:
        return _whichSurah(g);
      case 5:
        return _missing(g);
      case 6:
        return _order(g);
      case 7:
        return _pageStart(g);
      default:
        return _juzStart(g);
    }
  }

  /// A question about an ayah the user got wrong before: its second half, or its missed word.
  _Question? _fromMistake(int g) => _rnd.nextBool() ? (_missing(g) ?? _complete(g)) : (_complete(g) ?? _missing(g));

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
        n = switch (widget.kind) {
          0 => _complete(g),
          1 => _similar(g),
          2 => _full(g),
          _ => _fromMistake(g),
        };
        if (n != null) _askedG = g;
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
    if (ok) {
      HapticFeedback.lightImpact();
      SystemSound.play(SystemSoundType.click);
    } else {
      HapticFeedback.heavyImpact();
      HapticFeedback.vibrate();
    }
    if (widget.kind == 3) {
      UserStore.I.mistakeAnswered(_askedG, ok);
    } else if (!ok && cur!.g >= 0) {
      // a wrong answer becomes one of «أسئلة أخطائي»
      UserStore.I.addMistake(cur!.g, const []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = cur;
    final q = QuranData.I;
    return Scaffold(
      appBar: AppBar(
        title: Text(const ['اختبار أكمل الآية', 'اختبار المتشابهات', 'اختبار الحفظ', 'أسئلة أخطائي'][widget.kind]),
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
          if (widget.kind == 3)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('بقي ${ar(UserStore.I.mistakes.length)} موضعًا أخطأت فيه. كل جواب صحيح يقرّبه من الحذف.',
                  style: const TextStyle(color: kGoldDeep, fontWeight: FontWeight.w600)),
            ),
          if (widget.kind == 2)
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (var t = 0; t < kQuizTypes.length; t++)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 8),
                      child: ChoiceChip(
                        label: Text(kQuizTypes[t]),
                        selected: type == t,
                        onSelected: (_) {
                          type = t;
                          _next();
                        },
                      ),
                    ),
                ],
              ),
            ),
          if (widget.kind != 3)
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
                widget.kind == 3
                    ? 'لا أخطاء عندك الآن، بارك الله فيك. ما تخطئ فيه في التسميع أو الاختبارات يظهر هنا أسئلةً حتى تتقنه.'
                    : scope == 0
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
