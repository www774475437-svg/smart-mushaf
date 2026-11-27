import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../data/layout.dart';
import '../data/quran.dart';
import '../data/surah_names.dart';
import '../services/settings.dart';
import '../services/store.dart';
import 'common.dart';
import 'mushaf_lines.dart';

int _lev(String a, String b) {
  if ((a.length - b.length).abs() > 1) return 9;
  final m = a.length, n = b.length;
  var prev = List<int>.generate(n + 1, (i) => i);
  for (var i = 1; i <= m; i++) {
    final cur = List<int>.filled(n + 1, 0);
    cur[0] = i;
    for (var j = 1; j <= n; j++) {
      final c = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      var v = prev[j - 1] + c;
      if (prev[j] + 1 < v) v = prev[j] + 1;
      if (cur[j - 1] + 1 < v) v = cur[j - 1] + 1;
      cur[j] = v;
    }
    prev = cur;
  }
  return prev[n];
}

/// Is the heard word the expected word? (forgiving of how speech engines spell)
bool sameWord(String heard, String expected) {
  if (heard == expected) return true;
  String strip(String w) => w.startsWith('و') && w.length > 3 ? w.substring(1) : w;
  if (strip(heard) == strip(expected)) return true;
  if (expected.length >= 4 && _lev(heard, expected) <= 1) return true;
  return false;
}

class _W {
  final String key; // line:index on the page
  final int g;
  final String norm;
  final String text;
  const _W(this.key, this.g, this.norm, this.text);
}

/// Recite inside the mushaf page: words are hidden and appear as you read them.
class TasmeeScreen extends StatefulWidget {
  final int page;
  const TasmeeScreen({super.key, required this.page});
  @override
  State<TasmeeScreen> createState() => _TasmeeScreenState();
}

class _TasmeeScreenState extends State<TasmeeScreen> {
  final SpeechToText _stt = SpeechToText();
  late int page;
  List<_W> words = [];
  final Map<String, int> state = {};
  int idx = 0;
  bool ready = false;
  bool on = false; // the user wants listening
  bool listening = false;
  int _done = 0; // heard words already handled in this listening session
  String heard = '';
  String? err;
  bool peekAll = false;

  @override
  void initState() {
    super.initState();
    page = widget.page.clamp(1, 604);
    _build();
  }

  @override
  void dispose() {
    on = false;
    _stt.cancel();
    super.dispose();
  }

  void _build() {
    words = [];
    state.clear();
    idx = 0;
    _done = 0;
    heard = '';
    peekAll = false;
    if (!MushafLayout.I.ready) return;
    final q = QuranData.I;
    final lines = MushafLayout.I.pages[page - 1];
    // the place of every word inside its ayah, to pair it with the plain spelling
    final pos = <int, int>{};
    final firstOnPage = <int, int>{};
    for (final l in lines) {
      for (final w in l.words) {
        if (!w.end) firstOnPage.putIfAbsent(w.g, () => 0);
      }
    }
    // words of an ayah that started on the previous page
    for (final g in firstOnPage.keys) {
      if (page > 1) {
        var before = 0;
        for (final l in MushafLayout.I.pages[page - 2]) {
          for (final w in l.words) {
            if (w.g == g && !w.end) before++;
          }
        }
        pos[g] = before;
      } else {
        pos[g] = 0;
      }
    }
    final total = <int, int>{};
    for (var i = 0; i < lines.length; i++) {
      final l = lines[i];
      for (var k = 0; k < l.words.length; k++) {
        final w = l.words[k];
        if (w.end) continue;
        final p = pos[w.g] ?? 0;
        pos[w.g] = p + 1;
        final clean = q.cleanWords(w.g);
        total[w.g] ??= _ayahWordCount(w.g);
        final norm = (clean.length == total[w.g] && p < clean.length) ? clean[p] : normalizeAr(w.t);
        words.add(_W('$i:$k', w.g, norm, w.t));
      }
    }
  }

  int _ayahWordCount(int g) {
    var n = 0;
    final p = QuranData.I.ayahs[g].page;
    for (final pg in [p - 1, p, p + 1]) {
      if (pg < 1 || pg > 604) continue;
      for (final l in MushafLayout.I.pages[pg - 1]) {
        for (final w in l.words) {
          if (w.g == g && !w.end) n++;
        }
      }
    }
    return n;
  }

  Future<void> _toggle() async {
    if (on) {
      on = false;
      await _stt.stop();
      _saveMistakes();
      if (mounted) setState(() => listening = false);
      return;
    }
    if (!ready) {
      ready = await _stt.initialize(
        onError: (e) {
          if (mounted) setState(() => listening = false);
          _relisten();
        },
        onStatus: (s) {
          if (s == 'done' || s == 'notListening') {
            if (mounted) setState(() => listening = false);
            _relisten();
          }
        },
      );
    }
    if (!ready) {
      setState(() => err = 'التعرّف على الصوت غير متاح هنا. جرّب تطبيق الأندرويد، واسمح له باستخدام الميكروفون.');
      return;
    }
    on = true;
    setState(() => err = null);
    _listen();
  }

  void _relisten() {
    if (!on || !mounted) return;
    Future.delayed(const Duration(milliseconds: 350), () {
      if (on && mounted && !_stt.isListening) _listen();
    });
  }

  Future<void> _listen() async {
    _done = 0;
    if (mounted) setState(() => listening = true);
    try {
      await _stt.listen(
        onResult: (r) {
          if (!mounted) return;
          heard = r.recognizedWords;
          _consume(normalizeAr(heard).split(' ').where((w) => w.isNotEmpty).toList());
        },
        localeId: 'ar_SA',
        listenFor: const Duration(minutes: 5),
        pauseFor: const Duration(seconds: 6),
      );
    } catch (_) {
      if (mounted) setState(() => listening = false);
    }
  }

  void _consume(List<String> hs) {
    if (hs.length < _done) _done = 0;
    for (var i = _done; i < hs.length; i++) {
      if (idx >= words.length) break;
      final h = hs[i];
      if (sameWord(h, words[idx].norm)) {
        state[words[idx].key] ??= 1;
        idx++;
      } else if (idx + 1 < words.length && sameWord(h, words[idx + 1].norm)) {
        state[words[idx].key] = 2; // skipped a word
        state[words[idx + 1].key] ??= 1;
        idx += 2;
      } else if (idx + 2 < words.length && sameWord(h, words[idx + 2].norm)) {
        state[words[idx].key] = 2;
        state[words[idx + 1].key] = 2;
        state[words[idx + 2].key] ??= 1;
        idx += 3;
      }
    }
    // keep the last heard word open: the engine may still correct it
    _done = hs.isEmpty ? 0 : hs.length - 1;
    setState(() {});
    if (idx >= words.length && words.isNotEmpty) _pageDone();
  }

  void _hint() {
    if (idx >= words.length) return;
    setState(() {
      state[words[idx].key] = 3;
      idx++;
    });
    if (idx >= words.length) _pageDone();
  }

  void _saveMistakes() {
    final by = <int, List<String>>{};
    for (final w in words) {
      final st = state[w.key];
      if (st == 2 || st == 3) (by[w.g] ??= []).add(w.norm);
    }
    by.forEach((g, l) => UserStore.I.addMistake(g, l));
  }

  void _pageDone() {
    final wrong = state.values.where((v) => v == 2 || v == 3).length;
    _saveMistakes();
    UserStore.I.setPageStatus(page, wrong == 0 ? 1 : (wrong <= 3 ? 2 : 3));
    UserStore.I.logTasmee(wrong);
    toast(context, wrong == 0 ? 'أحسنت! أتممت الصفحة بلا أخطاء' : 'أتممت الصفحة • ${ar(wrong)} كلمة تحتاج مراجعة');
  }

  void _go(int d) {
    final n = page + d;
    if (n < 1 || n > 604) return;
    _stt.cancel();
    on = false;
    setState(() {
      page = n;
      listening = false;
      _build();
    });
  }

  @override
  Widget build(BuildContext context) {
    final q = QuranData.I;
    final col = pageColors(AppSettings.I.theme);
    final green = AppSettings.I.theme == ReadTheme.night ? const Color(0xFF7BCBB0) : kEmerald;
    final okN = state.values.where((v) => v == 1).length;
    final badN = state.values.where((v) => v == 2 || v == 3).length;
    if (!MushafLayout.I.ready) {
      return Scaffold(appBar: AppBar(title: const Text('التسميع')), body: const Center(child: Text('صفحات المصحف غير متوفرة')));
    }
    return Scaffold(
      backgroundColor: col.bg,
      appBar: AppBar(
        backgroundColor: col.soft,
        title: Column(
          children: [
            Text('تسميع صفحة ${ar(page)}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            Text('سورة ${surahName(q.surahOfPage(page))} • صحيح ${ar(okN)} • خطأ ${ar(badN)}',
                style: const TextStyle(fontSize: 11.5, color: kGoldDeep)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'إظهار الصفحة',
            icon: Icon(peekAll ? Icons.visibility_off_outlined : Icons.visibility_outlined),
            onPressed: () => setState(() => peekAll = !peekAll),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: MushafLinesPage(
              key: ValueKey('t$page'),
              page: page,
              showInfo: false,
              recite: peekAll ? null : state,
              onLongPress: (_) {},
            ),
          ),
          if (err != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(err!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red, fontSize: 13)),
            ),
          if (heard.isNotEmpty && on)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(heard, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ),
          Container(
            decoration: BoxDecoration(
              color: col.soft,
              border: Border(top: BorderSide(color: Colors.black.withValues(alpha: 0.08))),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(tooltip: 'الصفحة السابقة', onPressed: () => _go(-1), icon: Icon(Icons.chevron_right_rounded, color: green)),
                    TextButton.icon(
                      onPressed: () => setState(() {
                        _stt.cancel();
                        on = false;
                        listening = false;
                        _build();
                      }),
                      icon: Icon(Icons.restart_alt_rounded, color: green, size: 20),
                      label: Text('إعادة', style: TextStyle(color: green)),
                    ),
                    GestureDetector(
                      onTap: _toggle,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        width: on ? 64 : 58,
                        height: on ? 64 : 58,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: on ? Colors.red.shade600 : green,
                          boxShadow: [BoxShadow(color: (on ? Colors.red : green).withValues(alpha: 0.4), blurRadius: listening ? 18 : 8)],
                        ),
                        child: Icon(on ? Icons.stop_rounded : Icons.mic_rounded, color: Colors.white, size: 30),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _hint,
                      icon: Icon(Icons.lightbulb_outline_rounded, color: green, size: 20),
                      label: Text('ذكّرني', style: TextStyle(color: green)),
                    ),
                    IconButton(tooltip: 'الصفحة التالية', onPressed: () => _go(1), icon: Icon(Icons.chevron_left_rounded, color: green)),
                  ],
                ),
              ),
            ),
          ),
          Container(
            color: col.soft,
            width: double.infinity,
            padding: const EdgeInsets.only(bottom: 6),
            child: Center(
              child: TextButton.icon(
                onPressed: () => showSoon(context, title: 'تدقيق التشكيل بالذكاء الاصطناعي'),
                icon: const Icon(Icons.lightbulb_rounded, size: 18, color: kGoldDeep),
                label: const Text('تدقيق التشكيل بالذكاء الاصطناعي (اشتراك)', style: TextStyle(color: kGoldDeep, fontSize: 12.5)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
