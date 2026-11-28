import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../data/layout.dart';
import '../data/quran.dart';
import '../data/surah_names.dart';
import '../services/settings.dart';
import '../services/offline_asr.dart';
import '../services/recite_matcher.dart';
import '../services/store.dart';
import 'common.dart';
import 'mushaf_lines.dart';

typedef _W = MWord;

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

  // recognition inside the phone, with no internet
  final Set<String> _have = {}; // the models that are on the phone
  bool get _model => _have.isNotEmpty;
  String get _kind => _have.contains(AppSettings.I.tasModel) ? AppSettings.I.tasModel : (_have.contains('ctc') || _have.isEmpty ? 'ctc' : _have.first);
  bool get _offline => _model && AppSettings.I.tasOffline;
  String? _dlKind;
  String _mName(String k) => k == 'ctc' ? 'الفوري' : (k == 'tiny' ? 'المدقِّق السريع' : 'المدقِّق الدقيق');
  bool _askedModel = false;
  String _done = ''; // what was written down for good in this listening session
  bool _quiet = false; // a guess made while the words are still being said
  Timer? _tick;
  DateTime _lastProg = DateTime.now();
  double? _dl; // download progress

  @override
  void initState() {
    super.initState();
    page = widget.page.clamp(1, 604);
    _build();
    for (final k in const ['ctc', 'base', 'tiny']) {
      OfflineAsr.I.installed(k).then((v) {
        if (mounted && v) setState(() => _have.add(k));
      });
    }
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      final n = AppSettings.I.tasAutoHint;
      if (n <= 0 || !on || widget.follow || !mounted || idx >= words.length) return;
      if (DateTime.now().difference(_lastProg).inSeconds >= n) {
        _lastProg = DateTime.now();
        _hint();
      }
    });
  }

  Future<void> _getModel(String k) async {
    if (_dl != null) return;
    setState(() {
      _dl = 0;
      _dlKind = k;
    });
    try {
      await OfflineAsr.I.download(k, (p) {
        if (mounted) setState(() => _dl = p);
      });
      if (mounted) {
        setState(() => _have.add(k));
        AppSettings.I.tasModel = k;
        toast(context, 'صار التسميع يعمل بلا إنترنت');
      }
    } catch (_) {
      if (mounted) toast(context, 'تعذّر التحميل، تأكد من الإنترنت وأعد المحاولة (يكمل من حيث توقف)');
    }
    if (mounted) setState(() => _dl = null);
  }

  @override
  void dispose() {
    on = false;
    _tick?.cancel();
    _stt.cancel();
    OfflineAsr.I.close();
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
      if (_offline) {
        await OfflineAsr.I.pause();
      } else {
        await _stt.stop();
      }
      _saveMistakes();
      if (mounted) setState(() => listening = false);
      return;
    }
    if (_offline) {
      on = true;
      setState(() => err = null);
      _listen();
      return;
    }
    // The phone's own recognizer hears everyday Arabic, not recitation, and stops at every pause:
    // offer the Quran model before falling back to it.
    if (OfflineAsr.supported && !_askedModel && _dl == null) {
      _askedModel = true;
      final pick = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (c) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(_model ? 'التسميع بنموذج القرآن أدق' : 'حمّل نموذج القرآن للتسميع المتقن',
                    textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                const Text(
                    'التسميع بالإنترنت يستعمل تعرّف الجوال على الكلام العادي: يخطئ في التلاوة ويتوقف عند كل وقفة.\n'
                    'نموذج القرآن مدرَّب على التلاوة، يعمل بلا إنترنت، لا يتوقف عند الوقف، ويدقق التشكيل.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13.5, height: 1.7)),
                const SizedBox(height: 14),
                if (_model)
                  FilledButton(onPressed: () => Navigator.pop(c, 'use'), child: const Text('استعمل نموذج القرآن'))
                else ...[
                  FilledButton(onPressed: () => Navigator.pop(c, 'ctc'), child: const Text('حمّل النموذج الفوري (١٩ م.ب)')),
                ],
                TextButton(onPressed: () => Navigator.pop(c, 'online'), child: const Text('أكمل بالإنترنت')),
              ],
            ),
          ),
        ),
      );
      if (!mounted) return;
      if (pick == 'use') {
        AppSettings.I.tasOffline = true;
        on = true;
        setState(() => err = null);
        _listen();
        return;
      }
      if (pick == 'ctc') {
        AppSettings.I.tasOffline = true;
        _getModel(pick!);
        return;
      }
      if (pick == null) return;
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
    on = true;
    _from = 0;
    _lastLen = 0;
    _rebase();
    _lastProg = DateTime.now();
    if (mounted) setState(() => listening = true);
    if (_offline) {
      heard = '';
      _done = '';
      if (OfflineAsr.I.running) return; // the microphone is already open: go on with the new page
      await OfflineAsr.I.use(_kind);
      final e = await OfflineAsr.I.start((t, fin) {
        if (!mounted || !on) return;
        heard = '$_done $t'.trim();
        if (fin) _done = heard;
        _quiet = !fin;
        final raw = heard.split(' ').where((w) => normalizeAr(w).isNotEmpty).toList();
        _consume(raw.map(normalizeAr).toList(), raw);
        _quiet = false;
      });
      if (e != null && mounted) {
        on = false;
        setState(() {
          err = e;
          listening = false;
        });
      }
      return;
    }
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
  void _consume(List<String> heardWords, [List<String>? raw]) {
    if (heardWords.length < _from) {
      // the engine started a new transcript
      _from = 0;
      _rebase();
    }
    _lastLen = heardWords.length;
    final out = matchRecitation(
      words: words,
      heard: heardWords,
      raw: raw,
      from: _from,
      baseIdx: _baseIdx,
      baseState: _baseState,
      quiet: _quiet,
      strict: AppSettings.I.tasStrict,
      tashkeel: AppSettings.I.tasTashkeel && !widget.follow,
    );
    final i = out.idx;
    final st = out.state;
    // what has settled is not matched again: the next words are followed from here
    final settle = !_quiet && (raw != null || heardWords.length - _from > 30);
    if (i < idx) {
      // never step back
      if (settle) {
        _from = heardWords.length;
        _rebase();
      }
      return;
    }
    if (i > idx) _lastProg = DateTime.now();
    idx = i;
    state
      ..clear()
      ..addAll(st);
    final red = st.values.where((v) => v == 2).length;
    if (!_quiet) {
      if (red > _redSeen && !widget.follow && AppSettings.I.tasVibrate) HapticFeedback.heavyImpact();
      _redSeen = red;
    }
    if (settle) {
      _from = heardWords.length;
      _rebase();
    }
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
      if (st == 2 || st == 3 || st == 4) (by[w.g] ??= []).add(w.norm);
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
    final wrong = state.values.where((v) => v == 2 || v == 3 || v == 4).length;
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
    if (AppSettings.I.tasAutoNext && on && page < 604) {
      _go(1);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _listen();
      });
    }
  }

  Widget _dlRow(Color green) => _dl != null
      ? Column(
          children: [
            Text('تحميل النموذج ${_mName(_dlKind ?? 'ctc')} ${ar((_dl! * 100).round())}٪', style: TextStyle(fontSize: 12, color: green)),
            const SizedBox(height: 4),
            LinearProgressIndicator(value: _dl, minHeight: 4, color: green),
          ],
        )
      : TextButton.icon(
          onPressed: () => _getModel('ctc'),
          icon: Icon(Icons.download_for_offline_rounded, size: 18, color: green),
          label: Text('حمّل نموذج القرآن للتسميع بلا إنترنت (١٩ م.ب)', style: TextStyle(color: green, fontSize: 12.5)),
        );

  Future<void> _stopAll() async {
    on = false;
    await _stt.stop();
    await OfflineAsr.I.pause();
    if (mounted) setState(() => listening = false);
  }

  void _options() {
    final a = AppSettings.I;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(
        builder: (c, set) {
          Widget head(String t) => Padding(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 2),
                child: Align(alignment: AlignmentDirectional.centerStart, child: Text(t, style: const TextStyle(fontWeight: FontWeight.w800, color: kGoldDeep, fontSize: 13))),
              );
          Widget chips(List<String> names, int sel, void Function(int) pick) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Wrap(
                  spacing: 8,
                  children: [
                    for (var i = 0; i < names.length; i++)
                      ChoiceChip(label: Text(names[i]), selected: sel == i, onSelected: (_) => set(() => pick(i))),
                  ],
                ),
              );
          const hints = [0, 4, 7, 10, 15];
          return SafeArea(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('خيارات التسميع', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  head('طريقة التعرّف على الصوت'),
                  if (!OfflineAsr.supported)
                    const Padding(padding: EdgeInsets.symmetric(horizontal: 18), child: Text('بالإنترنت (التسميع بلا إنترنت في التطبيق، لا في الموقع)', style: TextStyle(fontSize: 13)))
                  else if (!_model)
                    const Padding(padding: EdgeInsets.symmetric(horizontal: 18), child: Text('بالإنترنت • اختر نموذجًا من الأسفل ليعمل بلا إنترنت', style: TextStyle(fontSize: 13)))
                  else
                    chips(const ['بلا إنترنت (نموذج القرآن)', 'بالإنترنت'], a.tasOffline ? 0 : 1, (i) {
                      _stopAll();
                      a.tasOffline = i == 0;
                      setState(() {});
                    }),
                  if (OfflineAsr.supported && a.tasOffline) ...[
                    head('نموذج الصوت'),
                    chips([
                      'الفوري (داخل التطبيق)',
                      _have.contains('tiny') ? 'المدقِّق السريع' : 'المدقِّق السريع (تحميل ١٠٤ م.ب)',
                      _have.contains('base') ? 'المدقِّق الدقيق' : 'المدقِّق الدقيق (تحميل ١٦٠ م.ب)',
                    ], const ['ctc', 'tiny', 'base'].indexOf(_kind), (i) {
                      final k = const ['ctc', 'tiny', 'base'][i];
                      _stopAll();
                      if (_have.contains(k)) {
                        a.tasModel = k;
                        setState(() {});
                      } else {
                        Navigator.pop(c);
                        _getModel(k);
                      }
                    }),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(18, 2, 18, 0),
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Text('الفوري يتابعك كلمة بكلمة لحظة النطق. المدقِّقان أبطأ ويدققان التشكيل أيضًا.',
                            style: TextStyle(fontSize: 12, color: Colors.grey)),
                      ),
                    ),
                  ],
                  head('دقة الحساب'),
                  chips(const ['متسامح', 'متوسط', 'دقيق'], a.tasStrict, (i) => a.tasStrict = i),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 2, 18, 0),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(const ['يتجاوز عن الكلمة إذا نطقت شيئًا مكانها', 'يتجاوز عن الكلمة إذا نطقت قريبًا منها', 'كل كلمة لم تُسمع كما هي تُحسب خطأ'][a.tasStrict],
                          style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    ),
                  ),
                  head('التذكير التلقائي عند التوقف'),
                  chips([for (final h in hints) h == 0 ? 'بدون' : '${ar(h)} ثوانٍ'], hints.indexOf(a.tasAutoHint).clamp(0, hints.length - 1), (i) => a.tasAutoHint = hints[i]),
                  const SizedBox(height: 6),
                  SwitchListTile(
                      dense: true,
                      title: const Text('تدقيق التشكيل (تجريبي)'),
                      subtitle: const Text('الكلمة التي نُطقت بحركة مخالفة تظهر بالأزرق • مع النموذجين المدقِّقين', style: TextStyle(fontSize: 11.5)),
                      value: a.tasTashkeel,
                      onChanged: (v) => set(() => a.tasTashkeel = v)),
                  SwitchListTile(dense: true, title: const Text('الاهتزاز عند الخطأ'), value: a.tasVibrate, onChanged: (v) => set(() => a.tasVibrate = v)),
                  SwitchListTile(dense: true, title: const Text('الانتقال للصفحة التالية تلقائيًا'), value: a.tasAutoNext, onChanged: (v) => set(() => a.tasAutoNext = v)),
                  SwitchListTile(dense: true, title: const Text('إظهار ما يسمعه التطبيق'), value: a.tasShowHeard, onChanged: (v) {
                    set(() => a.tasShowHeard = v);
                    setState(() {});
                  }),
                  SwitchListTile(dense: true, title: const Text('إبقاء الشاشة مضاءة'), value: a.keepAwake, onChanged: (v) => set(() => a.keepAwake = v)),
                  for (final k in _have.where((k) => k != 'ctc').toList())
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.delete_outline_rounded),
                      title: Text('حذف النموذج ${_mName(k)} من الجوال'),
                      onTap: () async {
                        Navigator.pop(c);
                        await _stopAll();
                        await OfflineAsr.I.remove(k);
                        if (mounted) setState(() => _have.remove(k));
                      },
                    ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _go(int d) {
    final n = page + d;
    if (n < 1 || n > 604) return;
    _stt.cancel();
    final auto = _offline && on && (widget.follow || widget.toG != null || AppSettings.I.tasAutoNext);
    if (_offline && !auto) OfflineAsr.I.pause();
    on = auto;
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
    final tkN = state.values.where((v) => v == 4).length;
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
            Text(widget.follow ? 'سورة ${surahName(q.surahOfPage(page))} • قرأت ${ar(okN + badN)} كلمة' : 'سورة ${surahName(q.surahOfPage(page))} • صحيح ${ar(okN)} • خطأ ${ar(badN)}${tkN > 0 ? ' • تشكيل ${ar(tkN)}' : ''}',
                style: const TextStyle(fontSize: 11.5, color: kGoldDeep)),
          ],
        ),
        actions: [
          IconButton(tooltip: 'خيارات التسميع', icon: const Icon(Icons.tune_rounded), onPressed: _options),
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
          if (heard.isNotEmpty && on && AppSettings.I.tasShowHeard)
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
                        if (_offline) OfflineAsr.I.pause();
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
          if (OfflineAsr.supported)
            Container(
              color: col.soft,
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
              child: !_model
                  ? _dlRow(green)
                  : !_offline
                  ? Text('التسميع بالإنترنت', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: green, fontWeight: FontWeight.w600))
                  : ValueListenableBuilder<bool>(
                      valueListenable: OfflineAsr.I.busy,
                      builder: (_, b, __) => Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.offline_bolt_rounded, size: 16, color: green),
                          const SizedBox(width: 6),
                          Text('بلا إنترنت • النموذج ${_mName(_kind)} • تظهر الكلمات وأنت تقرأ',
                              style: TextStyle(fontSize: 12, color: green, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
            ),
          Container(color: col.soft, width: double.infinity, height: 6),
        ],
      ),
    );
  }
}
