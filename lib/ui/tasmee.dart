import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

int _levFull(String a, String b) {
  var prev = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final cur = List<int>.filled(b.length + 1, 0);
    cur[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final c = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      var v = prev[j - 1] + c;
      if (prev[j] + 1 < v) v = prev[j] + 1;
      if (cur[j - 1] + 1 < v) v = cur[j - 1] + 1;
      cur[j] = v;
    }
    prev = cur;
  }
  return prev[b.length];
}

final RegExp _weak = RegExp('[اويء]');

/// Is the heard word the expected word? (forgiving of how speech engines spell)
bool sameWord(String heard, String expected) {
  if (heard == expected) return true;
  String strip(String w) => (w.startsWith('و') || w.startsWith('ف')) && w.length > 3 ? w.substring(1) : w;
  final h = strip(heard), e = strip(expected);
  if (h == e) return true;
  if (expected.length >= 4 && _lev(heard, expected) <= 1) return true;
  // the mushaf spelling and the everyday spelling differ mostly in the long vowels
  final a = h.replaceAll(_weak, ''), b = e.replaceAll(_weak, '');
  if (a.length >= 3 && a == b) return true;
  return false;
}

/// A heard word that is near enough to count as an attempt at the expected word.
bool nearWord(String heard, String expected) {
  if (sameWord(heard, expected)) return true;
  final lim = expected.length <= 3 ? 1 : (expected.length <= 6 ? 2 : 3);
  return _levFull(heard, expected) <= lim;
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

  /// Reading along: the page stays visible, the words turn green as they are read aloud,
  /// and the next page opens by itself. Nothing is counted as a mistake.
  final bool follow;

  /// Reciting a whole surah or juz: from this ayah to that one, page after page.
  final int? fromG, toG;
  final String? rangeName;
  const TasmeeScreen({super.key, required this.page, this.follow = false, this.fromG, this.toG, this.rangeName});
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
  int _from = 0, _lastLen = 0, _baseIdx = 0;
  Map<String, int> _baseState = {};
  String heard = '';
  String? err;
  bool peekAll = false;
  int _rangeWrong = 0, _redSeen = 0;

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
    _from = 0;
    _lastLen = 0;
    _baseIdx = 0;
    _baseState = {};
    heard = '';
    peekAll = false;
    _redSeen = 0;
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
        if (widget.toG != null && w.g > widget.toG!) continue; // past the end of the surah or juz
        words.add(_W('$i:$k', w.g, norm, w.t));
      }
    }
    // what comes before the start of the surah or juz is not asked for
    if (widget.fromG != null) {
      while (idx < words.length && words[idx].g < widget.fromG!) {
        state[words[idx].key] = 1;
        idx++;
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
    _from = 0;
    _lastLen = 0;
    _rebase();
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

  /// Follows the recitation. The whole transcript of this listening session is matched
  /// again on every result, so a word the engine corrects later is corrected here too.
  void _consume(List<String> heardWords) {
    if (heardWords.length < _from) {
      // the engine started a new transcript
      _from = 0;
      _rebase();
    }
    _lastLen = heardWords.length;
    final hs = List<String>.of(heardWords);
    var i = _baseIdx;
    final st = Map<String, int>.of(_baseState);
    final missed = <String>[]; // heard words that matched nothing since the last match
    bool m(int hj, int wi) => hj < hs.length && wi < words.length && sameWord(hs[hj], words[wi].norm);
    void ok(int wi) => st[words[wi].key] ??= 1;
    var j = _from;
    while (j < hs.length && i < words.length) {
      final h = hs[j];
      final e = words[i].norm;
      if (sameWord(h, e)) {
        ok(i);
        i++;
        j++;
        missed.clear();
        continue;
      }
      // the engine glued two words together
      if (e.length >= 2 && h.length > e.length + 1 && h.startsWith(e)) {
        ok(i);
        i++;
        hs[j] = h.substring(e.length);
        missed.clear();
        continue;
      }
      if (e.length >= 3 && h.length > e.length + 1 && h.endsWith(e)) {
        ok(i);
        i++;
        j++;
        missed.clear();
        continue;
      }
      // one word of the mushaf heard as two
      if (j + 1 < hs.length && sameWord(h + hs[j + 1], e)) {
        ok(i);
        i++;
        j += 2;
        missed.clear();
        continue;
      }
      // two words of the mushaf heard as one
      if (i + 1 < words.length && sameWord(h, e + words[i + 1].norm)) {
        ok(i);
        ok(i + 1);
        i += 2;
        j++;
        missed.clear();
        continue;
      }
      // A word counts as skipped only when the words after it are then heard in order.
      var jumped = false;
      for (var k = 1; k <= 4 && !jumped; k++) {
        if (i + k >= words.length) break;
        final need = k + 2;
        var got = 0;
        var end = false;
        for (var r = 0; r < need; r++) {
          if (i + k + r >= words.length) {
            end = true;
            break;
          }
          if (!m(j + r, i + k + r)) break;
          got++;
        }
        if (got == need || (end && got >= 2)) {
          for (var x = 0; x < k; x++) {
            final w = words[i + x];
            // he said something close to it: the engine misheard, not a mistake
            final tried = missed.any((u) => nearWord(u, w.norm));
            if (st[w.key] == null || st[w.key] == 2) st[w.key] = tried ? 1 : 2;
          }
          i += k;
          missed.clear();
          jumped = true;
        }
      }
      if (jumped) continue;
      missed.add(h);
      j++;
    }
    if (i < idx) return; // never step back
    idx = i;
    state
      ..clear()
      ..addAll(st);
    final red = st.values.where((v) => v == 2).length;
    if (red > _redSeen && !widget.follow) HapticFeedback.heavyImpact();
    _redSeen = red;
    setState(() {});
    if (idx >= words.length && words.isNotEmpty) _pageDone();
  }

  void _rebase() {
    _baseIdx = idx;
    _baseState = Map<String, int>.of(state);
  }

  void _hint() {
    if (idx >= words.length) return;
    setState(() {
      state[words[idx].key] = 3;
      idx++;
    });
    _from = _lastLen;
    _rebase();
    if (idx >= words.length) _pageDone();
  }

  void _saveMistakes() {
    if (widget.follow) return;
    final by = <int, List<String>>{};
    for (final w in words) {
      final st = state[w.key];
      if (st == 2 || st == 3) (by[w.g] ??= []).add(w.norm);
    }
    by.forEach((g, l) => UserStore.I.addMistake(g, l));
  }

  void _pageDone() {
    if (widget.follow) {
      UserStore.I.setLastPage(page);
      if (page >= 604) return;
      _go(1);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _listen();
      });
      return;
    }
    final wrong = state.values.where((v) => v == 2 || v == 3).length;
    _saveMistakes();
    UserStore.I.setPageStatus(page, wrong == 0 ? 1 : (wrong <= 3 ? 2 : 3));
    UserStore.I.logTasmee(wrong);
    _rangeWrong += wrong;
    if (wrong == 0) SystemSound.play(SystemSoundType.click);
    if (widget.toG != null) {
      final more = page < 604 && QuranData.I.pageAyahs[page + 1].isNotEmpty && QuranData.I.pageAyahs[page + 1].first <= widget.toG!;
      if (more) {
        _go(1);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _listen();
        });
        return;
      }
      toast(context, _rangeWrong == 0
          ? 'أحسنت! أتممت ${widget.rangeName ?? 'التسميع'} بلا أخطاء'
          : 'أتممت ${widget.rangeName ?? 'التسميع'} • ${ar(_rangeWrong)} كلمة تحتاج مراجعة');
      return;
    }
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
            Text(widget.follow ? 'القراءة بالمتابعة • صفحة ${ar(page)}' : widget.rangeName != null ? 'تسميع ${widget.rangeName} • صفحة ${ar(page)}' : 'تسميع صفحة ${ar(page)}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            Text(widget.follow ? 'سورة ${surahName(q.surahOfPage(page))} • قرأت ${ar(okN + badN)} كلمة' : 'سورة ${surahName(q.surahOfPage(page))} • صحيح ${ar(okN)} • خطأ ${ar(badN)}',
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
              reciteOpen: widget.follow,
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
