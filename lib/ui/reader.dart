import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../data/quran.dart';
import '../data/reciters.dart';
import '../data/surah_names.dart';
import '../services/audio.dart';
import '../services/settings.dart';
import '../services/store.dart';
import 'ayah_sheet.dart';
import '../data/gharib.dart';
import '../data/layout.dart';
import 'common.dart';
import 'mushaf_lines.dart';
import 'reciter_sheet.dart';
import 'search.dart';
import 'tasmee.dart';
import '../data/tafsir.dart';

const _basmala = 'بِسۡمِ ٱللَّهِ ٱلرَّحۡمَٰنِ ٱلرَّحِيمِ';

class MushafScreen extends StatefulWidget {
  final int page;
  final int? flashG;
  const MushafScreen({super.key, required this.page, this.flashG});

  static Future<void> open(BuildContext c, int page, {int? flashG}) {
    return Navigator.of(c).push(MaterialPageRoute(builder: (_) => MushafScreen(page: page, flashG: flashG)));
  }

  @override
  State<MushafScreen> createState() => _MushafScreenState();
}

class _MushafScreenState extends State<MushafScreen> {
  late PageController _pc;
  final ItemScrollController _isc = ItemScrollController();
  final ItemPositionsListener _ipl = ItemPositionsListener.create();
  final ScrollOffsetController _soc = ScrollOffsetController();

  int page = 1;
  bool bars = true;
  int? selectedG;
  bool? _builtScroll;
  Timer? _autoTimer;
  bool autoOn = false;
  bool autoPaused = false;
  int? _lastAudioG;
  Timer? _saveTimer;
  final Map<int, Widget> _pageCache = {};
  int? _cacheSel;

  @override
  void initState() {
    super.initState();
    page = widget.page.clamp(1, 604);
    MushafLayout.I.preload(page);
    selectedG = widget.flashG;
    _pc = PageController(initialPage: page - 1);
    _ipl.itemPositions.addListener(_onPos);
    AudioCtl.I.addListener(_onAudio);
    WidgetsBinding.instance.addPostFrameCallback((_) => UserStore.I.setLastPage(page));
    if (AppSettings.I.keepAwake) WakelockPlus.enable();
    _armHide();
    if (widget.flashG != null) {
      Timer(const Duration(seconds: 3), () {
        if (mounted && selectedG == widget.flashG) setState(() => selectedG = null);
      });
    }
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _hideTimer?.cancel();
    if (_saveTimer?.isActive ?? false) {
      _saveTimer!.cancel();
      final p = page;
      Future.microtask(() => UserStore.I.setLastPage(p));
    }
    _ipl.itemPositions.removeListener(_onPos);
    AudioCtl.I.removeListener(_onAudio);
    WakelockPlus.disable();
    _pc.dispose();
    super.dispose();
  }

  Timer? _hideTimer;

  /// The bars and the player leave by themselves after five quiet seconds.
  void _armHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && bars) setState(() => bars = false);
    });
  }

  void _wordMeaning(LWord w) {
    final ay = QuranData.I.ayahs[w.g];
    final meaning = Gharib.I.of(w);
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.92,
        minChildSize: 0.3,
        builder: (ctx, sc) => ListView(
          controller: sc,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Text(w.t, textAlign: TextAlign.center, style: const TextStyle(fontFamily: 'UthmanicHafs', fontSize: 34, height: 1.8)),
            Text(ay.ref, textAlign: TextAlign.center, style: const TextStyle(color: kGoldDeep)),
            const SizedBox(height: 12),
            FutureBuilder<WordMeaning?>(
              future: meaning,
              builder: (c, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator()));
                }
                final m = snap.data;
                if (m == null || m.text == null) {
                  return Text(
                      m == null
                          ? 'هذه الكلمة من الحروف والأدوات، وليس لها مادة في كتاب المفردات.'
                          : 'مادة «${m.root}» ليست في كتاب المفردات.',
                      style: const TextStyle(color: Colors.grey));
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('معنى الكلمة • مادة «${m.head}»', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    const SizedBox(height: 6),
                    SelectableText(m.text!, style: const TextStyle(fontSize: 16.5, height: 1.9)),
                    const SizedBox(height: 6),
                    const Text('المصدر: «المفردات في غريب القرآن» للراغب الأصفهاني رَحِمَهُ الله',
                        style: TextStyle(fontSize: 12.5, color: kGoldDeep, fontWeight: FontWeight.w600)),
                  ],
                );
              },
            ),
            const Divider(height: 28),
            const Text('معنى الآية (التفسير الميسر)', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            FutureBuilder<String>(
              future: TafsirService.I.get('muyassar', w.g),
              builder: (c, snap) => Text(snap.data ?? '…', style: const TextStyle(fontSize: 16, height: 1.85)),
            ),
          ],
        ),
      ),
    );
  }

  void _stopAuto() {
    _autoTimer?.cancel();
    _autoTimer = null;
    if (!AppSettings.I.keepAwake) WakelockPlus.disable();
    if (mounted) setState(() => autoOn = false);
  }

  void _changeAutoSpeed(bool faster) {
    const steps = [10, 15, 20, 30, 45, 60, 90, 120, 180, 240, 300];
    final cur = AppSettings.I.autoSeconds;
    var i = steps.indexWhere((s) => s >= cur);
    if (i < 0) i = steps.length - 1;
    i = faster ? (i - 1).clamp(0, steps.length - 1) : (i + 1).clamp(0, steps.length - 1);
    AppSettings.I.autoSeconds = steps[i];
    _schedule();
    setState(() {});
  }

  // ---------- actions ----------
  Future<void> _openAyah(int g) async {
    setState(() => selectedG = g);
    await showAyahSheet(context, g);
    if (mounted) setState(() => selectedG = null);
  }

  void _playPage() {
    final a = AudioCtl.I;
    if (a.active) {
      a.toggle();
      return;
    }
    final ids = QuranData.I.pageAyahs[page];
    if (ids.isEmpty) return;
    final first = ids.first;
    a.playRange(first, QuranData.I.surahEndG(QuranData.I.ayahs[first].s), continueAfter: true);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppSettings.I,
      builder: (context, _) {
        final st = AppSettings.I;
        final col = pageColors(st.theme);
        final scroll = st.scrollMode;
        if (_builtScroll != null && _builtScroll != scroll) {
          _autoTimer?.cancel();
          autoOn = false;
          if (!scroll) {
            final old = _pc;
            _pc = PageController(initialPage: page - 1);
            WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
          }
        }
        _builtScroll = scroll;
        return Scaffold(
          backgroundColor: col.bg,
          body: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) => _armHide(),
            child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => bars = !bars),
                  child: scroll ? _scrollView() : _pageView(),
                ),
              ),
              _topBar(col),
              Positioned(left: 0, right: 0, bottom: 0, child: _bottomArea(col)),
            ],
          ),
          ),
        );
      },
    );
  }

  Widget _pageView() {
    // The same page widget is handed back while nothing in it changed, so showing the bars
    // or moving to the next page does not rebuild the pages on screen.
    if (_cacheSel != selectedG) {
      _pageCache.clear();
      _cacheSel = selectedG;
    }
    _pageCache.removeWhere((k, _) => (k + 1 - page).abs() > 3);
    return PageView.builder(
      key: const ValueKey('pages'),
      controller: _pc,
      itemCount: 604,
      onPageChanged: (i) => _setPage(i + 1),
      allowImplicitScrolling: true,
      physics: const PageScrollPhysics(parent: BouncingScrollPhysics()),
      itemBuilder: (_, i) => _pageCache.putIfAbsent(
          i,
          () => RepaintBoundary(
              child: MushafPage(
                  page: i + 1, expand: true, selectedG: selectedG, onLongPress: _openAyah, onWordDoubleTap: _wordMeaning))),
    );
  }

  Widget _scrollView() {
    return ScrollablePositionedList.builder(
      key: const ValueKey('scroll'),
      itemCount: 604,
      initialScrollIndex: page - 1,
      itemScrollController: _isc,
      itemPositionsListener: _ipl,
      scrollOffsetController: _soc,
      itemBuilder: (_, i) => MushafPage(page: i + 1, expand: false, selectedG: selectedG, onLongPress: _openAyah, onWordDoubleTap: _wordMeaning),
    );
  }

  Widget _topBar(PageColors col) {
    const green = kEmerald;
    final ic = st_night ? const Color(0xFF7BCBB0) : green;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: IgnorePointer(
        ignoring: !bars,
        child: AnimatedOpacity(
          opacity: bars ? 1 : 0,
          duration: const Duration(milliseconds: 200),
          child: Container(
            decoration: BoxDecoration(
              color: col.soft,
              border: Border(bottom: BorderSide(color: Colors.black.withValues(alpha: 0.08))),
            ),
            child: SafeArea(
              bottom: false,
              child: SizedBox(
                height: 54,
                child: ListenableBuilder(
                  listenable: UserStore.I,
                  builder: (context, _) {
                    final marked = UserStore.I.isPageBookmarked(page);
                    return Row(
                      children: [
                        const SizedBox(width: 6),
                        IconButton(
                          tooltip: 'الفهرس',
                          icon: const Icon(Icons.format_list_bulleted_rounded),
                          color: ic,
                          onPressed: () => Navigator.pop(context),
                        ),
                        IconButton(
                          tooltip: 'البحث',
                          icon: const Icon(Icons.search_rounded),
                          color: ic,
                          onPressed: () =>
                              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SearchScreen())),
                        ),
                        IconButton(
                          tooltip: 'سمِّع هذه الصفحة',
                          icon: const Icon(Icons.mic_none_rounded),
                          color: ic,
                          onPressed: () {
                            AudioCtl.I.stop();
                            Navigator.of(context).push(MaterialPageRoute(builder: (_) => TasmeeScreen(page: page)));
                          },
                        ),
                        const Spacer(),
                        IconButton(
                          tooltip: 'تمرير تلقائي',
                          icon: Icon(autoOn ? Icons.pause_circle_outline_rounded : Icons.swipe_vertical_rounded),
                          color: autoOn ? col.accent : ic,
                          onPressed: autoOn ? _stopAuto : _startAuto,
                        ),
                        IconButton(
                          tooltip: 'علامة الصفحة',
                          icon: Icon(marked ? Icons.bookmark_rounded : Icons.bookmark_border_rounded),
                          color: marked ? col.accent : ic,
                          onPressed: () {
                            UserStore.I.togglePageBookmark(page);
                            toast(context, marked ? 'أُزيلت العلامة' : 'حُفظت علامة على الصفحة ${ar(page)}');
                          },
                        ),
                        IconButton(
                          tooltip: 'خيارات القراءة',
                          icon: const Icon(Icons.settings_outlined),
                          color: ic,
                          onPressed: () => showReadingOptions(context, onAutoChanged: () {
                            if (autoOn) _schedule();
                          }),
                        ),
                        const SizedBox(width: 6),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool get st_night => AppSettings.I.theme == ReadTheme.night;

  Widget _bottomArea(PageColors col) {
    final ic = st_night ? const Color(0xFF7BCBB0) : kEmerald;
    return IgnorePointer(
      ignoring: !bars,
      child: AnimatedOpacity(
        opacity: bars ? 1 : 0,
        duration: const Duration(milliseconds: 200),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (autoOn) _autoPill(col),
            AudioBar(
              page: page,
              onPlay: _playPage,
              onLocate: () {
                final g = AudioCtl.I.currentG;
                if (g != null) _goTo(QuranData.I.ayahs[g].page);
              },
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: col.soft,
                border: Border(top: BorderSide(color: Colors.black.withValues(alpha: 0.08))),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 2, 14, 2),
                  child: Row(
                    children: [
                      Text('${604}', style: TextStyle(color: ic, fontSize: 12, fontWeight: FontWeight.w700)),
                      Expanded(
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 10,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
                            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                          ),
                          child: Slider(
                            min: 1,
                            max: 604,
                            value: page.toDouble(),
                            activeColor: ic,
                            inactiveColor: Colors.grey.withValues(alpha: 0.25),
                            onChanged: (v) => setState(() => page = v.round()),
                            onChangeEnd: (v) => _goTo(v.round(), animate: false),
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                        decoration: BoxDecoration(color: ic, borderRadius: BorderRadius.circular(12)),
                        child: Text('$page',
                            style: TextStyle(
                                color: st_night ? Colors.black : Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _autoPill(PageColors col) {
    final secs = AppSettings.I.autoSeconds;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: kEmeraldDark.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(40),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 12)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'أبطأ',
            icon: const Icon(Icons.remove_rounded, color: Colors.white),
            onPressed: () => _changeAutoSpeed(false),
          ),
          Text(AppSettings.I.scrollMode ? 'الصفحة في ${ar(secs)} ث' : 'صفحة كل ${ar(secs)} ث',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          IconButton(
            tooltip: 'أسرع',
            icon: const Icon(Icons.add_rounded, color: Colors.white),
            onPressed: () => _changeAutoSpeed(true),
          ),
          IconButton(
            icon: Icon(autoPaused ? Icons.play_arrow_rounded : Icons.pause_rounded, color: kGold),
            onPressed: () => setState(() => autoPaused = !autoPaused),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.white70),
            onPressed: _stopAuto,
          ),
        ],
      ),
    );
  }
}

/// One page of the mushaf.
class MushafPage extends StatefulWidget {
  final int page;
  final bool expand;
  final int? selectedG;
  final void Function(int g) onLongPress;
  final void Function(LWord w)? onWordDoubleTap;
  const MushafPage(
      {super.key, required this.page, required this.expand, this.selectedG, required this.onLongPress, this.onWordDoubleTap});
  @override
  State<MushafPage> createState() => _MushafPageState();
}

class _MushafPageState extends State<MushafPage> {
  final Map<int, LongPressGestureRecognizer> _recs = {};

  LongPressGestureRecognizer _rec(int g) =>
      _recs.putIfAbsent(g, () => LongPressGestureRecognizer()..onLongPress = () => widget.onLongPress(g));

  @override
  void dispose() {
    AppSettings.I.removeListener(_all);
    AudioCtl.I.removeListener(_maybe);
    UserStore.I.removeListener(_maybe);
    for (final r in _recs.values) {
      r.dispose();
    }
    super.dispose();
  }

  String _last = '';

  /// What this page shows from the audio and the user's marks. The page is rebuilt only
  /// when this changes, not on every tick of the player or every save.
  String _sig() {
    final ids = QuranData.I.pageAyahs[widget.page];
    final a = AudioCtl.I;
    final g = a.active ? a.currentG : null;
    final st = UserStore.I;
    final b = StringBuffer(g != null && ids.contains(g) ? '$g' : '-');
    for (final id in ids) {
      final h = st.highlights[id];
      if (h != null) b.write('|$id:$h');
      if (st.isAyahBookmarked(id)) b.write('|b$id');
      if (st.notes.containsKey(id)) b.write('|n$id');
    }
    if (st.isPageBookmarked(widget.page)) b.write('|pb');
    return b.toString();
  }

  void _all() {
    if (mounted) setState(() {});
  }

  void _maybe() {
    final s = _sig();
    if (s == _last) return;
    _last = s;
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _last = _sig();
    AppSettings.I.addListener(_all);
    AudioCtl.I.addListener(_maybe);
    UserStore.I.addListener(_maybe);
  }

  @override
  void didUpdateWidget(covariant MushafPage old) {
    super.didUpdateWidget(old);
    _last = _sig();
  }

  @override
  Widget build(BuildContext context) => _build(context);

  Widget _build(BuildContext context) {
    if (MushafLayout.I.ready && quranFont() == 'UthmanicHafs') {
      final pg = MushafLinesPage(
          page: widget.page,
          selectedG: widget.selectedG,
          onLongPress: widget.onLongPress,
          onWordDoubleTap: widget.onWordDoubleTap);
      if (widget.expand) return pg;
      // vertical scrolling: the very same page, one screen tall
      final mq = MediaQuery.of(context);
      return SizedBox(height: mq.size.height, child: pg);
    }
    final q = QuranData.I;
    final st = AppSettings.I;
    final col = pageColors(st.theme);
    final ids = q.pageAyahs[widget.page];
    final fs = st.fontSize;
    final audioG = AudioCtl.I.active ? AudioCtl.I.currentG : null;
    final hl = UserStore.I.highlights;

    final blocks = <Widget>[];
    var spans = <InlineSpan>[];
    final base = TextStyle(fontFamily: quranFont(), fontSize: fs, height: 2.05, color: col.text);

    void flush() {
      if (spans.isEmpty) return;
      blocks.add(Text.rich(
        TextSpan(children: spans),
        textAlign: TextAlign.justify,
        textDirection: TextDirection.rtl,
        style: base,
      ));
      spans = <InlineSpan>[];
    }

    for (final g in ids) {
      final ay = q.ayahs[g];
      if (ay.a == 1) {
        flush();
        blocks.add(_SurahBanner(s: ay.s, col: col));
        if (ay.s != 1 && ay.s != 9) {
          blocks.add(Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(_basmala,
                textAlign: TextAlign.center,
                style: base.copyWith(fontSize: fs * 0.95, height: 1.9)),
          ));
        }
      }
      Color? bg;
      if (g == audioG) {
        bg = col.accent.withValues(alpha: 0.26);
      } else if (g == widget.selectedG) {
        bg = kEmerald.withValues(alpha: 0.18);
      } else if (hl[g] != null) {
        bg = kHighlightColors[hl[g]!.clamp(0, kHighlightColors.length - 1)].withValues(alpha: 0.42);
      }
      final rec = _rec(g);
      spans.add(TextSpan(text: '${ay.text} ', style: TextStyle(backgroundColor: bg), recognizer: rec));
      if (ay.sajda) {
        spans.add(TextSpan(text: '۩ ', style: TextStyle(color: col.accent, backgroundColor: bg), recognizer: rec));
      }
      spans.add(TextSpan(
        text: '${ayahMark(ay.a)} ',
        style: TextStyle(color: col.accent, backgroundColor: bg, fontSize: fs * 0.82),
        recognizer: rec,
      ));
    }
    flush();

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
      child: Row(
        children: [
          Text('سورة ${surahName(q.surahOfPage(widget.page))}',
              style: TextStyle(color: col.accent, fontWeight: FontWeight.w700, fontSize: 13.5)),
          const Spacer(),
          Text('الجزء ${ar(q.juzOfPage(widget.page))}',
              style: TextStyle(color: col.accent, fontWeight: FontWeight.w700, fontSize: 13.5)),
        ],
      ),
    );
    final footer = Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          decoration: BoxDecoration(
            border: Border.all(color: col.frame.withValues(alpha: 0.6)),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(ar(widget.page), style: TextStyle(color: col.text, fontSize: 13)),
        ),
      ),
    );

    final frame = st.showPageFrame
        ? BoxDecoration(
            border: Border.all(color: col.frame.withValues(alpha: 0.55), width: 1.2),
            borderRadius: BorderRadius.circular(10),
          )
        : null;

    if (widget.expand) {
      return Container(
        color: col.bg,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 62, 10, 70),
            child: Container(
              decoration: frame,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Column(
                children: [
                  header,
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, c) => SingleChildScrollView(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minHeight: c.maxHeight),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: blocks,
                          ),
                        ),
                      ),
                    ),
                  ),
                  footer,
                ],
              ),
            ),
          ),
        ),
      );
    }
    return Container(
      color: col.bg,
      padding: EdgeInsets.fromLTRB(10, widget.page == 1 ? MediaQuery.of(context).padding.top + 66 : 8, 10, 8),
      child: Container(
        decoration: frame,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [header, ...blocks, footer, if (widget.page == 604) const SizedBox(height: 120)],
        ),
      ),
    );
  }
}

class _SurahBanner extends StatelessWidget {
  final int s;
  final PageColors col;
  const _SurahBanner({required this.s, required this.col});
  @override
  Widget build(BuildContext context) {
    final q = QuranData.I;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          col.frame.withValues(alpha: 0.10),
          col.frame.withValues(alpha: 0.26),
          col.frame.withValues(alpha: 0.10),
        ]),
        border: Border.all(color: col.frame, width: 1.4),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Text(q.surahMeccan[s] ? 'مكية' : 'مدنية', style: TextStyle(color: col.accent, fontSize: 12)),
          Expanded(
            child: Text('سورة ${surahName(s)}',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: quranFont(), fontSize: 22, color: col.text, height: 1.6)),
          ),
          Text('آياتها ${ar(q.surahCount[s])}', style: TextStyle(color: col.accent, fontSize: 12)),
        ],
      ),
    );
  }
}

/// The small pill player: reciter name and play button (like a quiet mushaf).
class AudioBar extends StatelessWidget {
  final int? page;
  final VoidCallback? onPlay;

  /// Jumps back to the page of the ayah being recited.
  final VoidCallback? onLocate;
  const AudioBar({super.key, this.page, this.onPlay, this.onLocate});
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([AudioCtl.I, Reciters.I, AppSettings.I]),
      builder: (context, _) {
        final a = AudioCtl.I;
        final dark = AppSettings.I.theme == ReadTheme.night;
        final green = dark ? const Color(0xFF7BCBB0) : kEmerald;
        final bg = dark ? const Color(0xFF1B2623) : const Color(0xFFF4F0E8);
        if (a.error != null && !a.active) {
          return Container(
            margin: const EdgeInsets.fromLTRB(40, 0, 40, 0),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(color: Colors.red.shade700, borderRadius: BorderRadius.circular(22)),
            child: Row(children: [
              Expanded(child: Text(a.error!, style: const TextStyle(color: Colors.white, fontSize: 13))),
              GestureDetector(
                onTap: () {
                  a.error = null;
                  a.stop();
                },
                child: const Icon(Icons.close, color: Colors.white),
              ),
            ]),
          );
        }
        if (!a.active && onPlay == null) return const SizedBox.shrink();
        if (a.active) return _BigPlayer(page: page, green: green, bg: bg, onLocate: onLocate);
        final q = QuranData.I;
        final r = a.playingReciter ?? Reciters.I.current;
        String title = a.active ? (a.customTitle ?? r.name) : Reciters.I.current.name;
        String? where;
        if (a.active) {
          if (a.customTitle != null) {
            where = a.customSub;
          } else if (a.surahPlaying != null) {
            where = 'سورة ${surahName(a.surahPlaying!)}';
          } else if (a.currentG != null) {
            final ay = q.ayahs[a.currentG!];
            where = '${surahName(ay.s)}: ${ay.a}';
          }
        }
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 40),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Colors.black.withValues(alpha: 0.10)),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.10), blurRadius: 10)],
          ),
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(24),
                  onTap: () => showReciterSheet(context, page: page),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Row(
                      children: [
                        Flexible(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: green, fontWeight: FontWeight.w600, fontSize: 16)),
                              if (where != null)
                                Text(where, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: kGoldDeep)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        CircleAvatar(
                          radius: 10,
                          backgroundColor: Colors.grey.withValues(alpha: 0.22),
                          child: Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: green),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (a.active) ...[
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'السرعة',
                  onPressed: () {
                    const speeds = [1.0, 1.25, 1.5];
                    final i = speeds.indexOf(AppSettings.I.speed);
                    a.setSpeed(speeds[(i + 1) % speeds.length]);
                  },
                  icon: Text('${AppSettings.I.speed}×', style: TextStyle(color: green, fontWeight: FontWeight.w700, fontSize: 12)),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'إيقاف',
                  icon: Icon(Icons.stop_rounded, color: green),
                  onPressed: a.stop,
                ),
              ],
              IconButton(
                icon: Icon(a.active && a.playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: green, size: 32),
                onPressed: a.active ? a.toggle : onPlay,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Quick options sheet for reading.
Future<void> showReadingOptions(BuildContext context, {VoidCallback? onAutoChanged}) {
  return showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (ctx) => ListenableBuilder(
      listenable: AppSettings.I,
      builder: (ctx, _) {
        final st = AppSettings.I;
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('الوضع', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Pills<ReadTheme>(
                  values: ReadTheme.values,
                  selected: st.theme,
                  label: (t) => const {ReadTheme.day: 'نهاري', ReadTheme.paper: 'ورقي', ReadTheme.night: 'ليلي'}[t]!,
                  onChanged: (t) => st.theme = t,
                ),
                const SizedBox(height: 16),
                const Text('طريقة القراءة', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Pills<bool>(
                  values: const [false, true],
                  selected: st.scrollMode,
                  label: (v) => v ? 'تمرير عمودي' : 'تقليب الصفحات',
                  onChanged: (v) => st.scrollMode = v,
                ),
                const SizedBox(height: 16),
                Text('حجم الخط: ${ar(st.fontSize.round())}', style: const TextStyle(fontWeight: FontWeight.w700)),
                Slider(min: 16, max: 40, divisions: 24, value: st.fontSize, onChanged: (v) => st.fontSize = v),
                Text('سرعة التمرير التلقائي: ${st.scrollMode ? 'الصفحة في' : 'صفحة كل'} ${ar(st.autoSeconds)} ثانية',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                Slider(
                  min: 10,
                  max: 300,
                  divisions: 29,
                  value: st.autoSeconds.toDouble().clamp(10.0, 300.0),
                  onChanged: (v) {
                    st.autoSeconds = v.round();
                    onAutoChanged?.call();
                  },
                ),
                const Text('مؤقّت النوم (إيقاف التلاوة بعد)', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                ListenableBuilder(
                  listenable: AudioCtl.I,
                  builder: (c, _) {
                    final at = AudioCtl.I.sleepAt;
                    final left = at == null ? 0 : at.difference(DateTime.now()).inMinutes + 1;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Pills<int>(
                          values: const [0, 15, 30, 60],
                          selected: at == null ? 0 : -1,
                          label: (m) => m == 0 ? 'بلا مؤقّت' : '${ar(m)} دقيقة',
                          onChanged: (m) => AudioCtl.I.setSleep(m),
                        ),
                        if (at != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text('تتوقف التلاوة بعد ${ar(left)} دقيقة', style: const TextStyle(color: kGoldDeep)),
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('إطار الصفحة'),
                  value: st.showPageFrame,
                  onChanged: (v) => st.showPageFrame = v,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('تقليب الصفحات مع التلاوة'),
                  value: st.followAudio,
                  onChanged: (v) => st.followAudio = v,
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}


String _mmss(Duration d) {
  final m = d.inMinutes;
  final s = d.inSeconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// The full player shown while a recitation is playing.
class _BigPlayer extends StatelessWidget {
  final int? page;
  final Color green, bg;
  final VoidCallback? onLocate;
  const _BigPlayer({this.page, required this.green, required this.bg, this.onLocate});
  @override
  Widget build(BuildContext context) {
    final a = AudioCtl.I;
    final q = QuranData.I;
    final r = a.playingReciter ?? Reciters.I.current;
    final title = a.customTitle ?? r.name;
    String where = '';
    if (a.customTitle != null) {
      where = a.customSub ?? '';
    } else if (a.surahPlaying != null) {
      where = 'سورة ${surahName(a.surahPlaying!)}';
    } else if (a.currentG != null) {
      final ay = q.ayahs[a.currentG!];
      where = '${surahName(ay.s)}: ${ay.a}';
    }
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.black.withValues(alpha: 0.10)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 12)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: a.stop,
                child: CircleAvatar(
                  radius: 13,
                  backgroundColor: Colors.grey.withValues(alpha: 0.22),
                  child: const Icon(Icons.close_rounded, size: 16, color: kGoldDeep),
                ),
              ),
              Expanded(
                child: InkWell(
                  onTap: () => showReciterSheet(context, page: page),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Flexible(
                            child: Text(title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: green, fontWeight: FontWeight.w600, fontSize: 15.5)),
                          ),
                          Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: green),
                        ],
                      ),
                      if (where.isNotEmpty) Text(where, style: const TextStyle(fontSize: 12, color: kGoldDeep)),
                    ],
                  ),
                ),
              ),
              if (onLocate != null &&
                  a.currentG != null &&
                  page != null &&
                  q.ayahs[a.currentG!].page != page)
                GestureDetector(
                  onTap: onLocate,
                  child: CircleAvatar(
                    radius: 13,
                    backgroundColor: green,
                    child: const Icon(Icons.replay_rounded, size: 17, color: Colors.white),
                  ),
                )
              else
                const SizedBox(width: 26),
            ],
          ),
          StreamBuilder<Duration>(
            stream: a.player.positionStream,
            builder: (context, snap) {
              final pos = snap.data ?? Duration.zero;
              final dur = a.player.duration ?? Duration.zero;
              final max = dur.inMilliseconds <= 0 ? 1.0 : dur.inMilliseconds.toDouble();
              final v = pos.inMilliseconds.toDouble().clamp(0.0, max);
              return Row(
                children: [
                  SizedBox(width: 38, child: Text(_mmss(pos), style: const TextStyle(fontSize: 11, color: Colors.grey))),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                      ),
                      child: Slider(
                        min: 0,
                        max: max,
                        value: v,
                        activeColor: green,
                        inactiveColor: Colors.grey.withValues(alpha: 0.3),
                        onChanged: (x) => a.player.seek(Duration(milliseconds: x.round())),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 38,
                    child: Text(dur == Duration.zero ? '' : '-${_mmss(dur - pos)}',
                        textAlign: TextAlign.end, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  ),
                ],
              );
            },
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                tooltip: 'تكرار',
                icon: Icon(a.looping ? Icons.repeat_on_rounded : Icons.repeat_rounded, color: green),
                onPressed: a.toggleLoop,
              ),
              IconButton(
                tooltip: 'الآية السابقة',
                icon: Icon(Icons.fast_forward_rounded, color: green, size: 30),
                onPressed: a.previous,
              ),
              IconButton(
                icon: Icon(a.playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: green, size: 40),
                onPressed: a.toggle,
              ),
              IconButton(
                tooltip: 'الآية التالية',
                icon: Icon(Icons.fast_rewind_rounded, color: green, size: 30),
                onPressed: a.next,
              ),
              TextButton(
                onPressed: () {
                  const speeds = [1.0, 1.25, 1.5];
                  final i = speeds.indexOf(AppSettings.I.speed);
                  a.setSpeed(speeds[(i + 1) % speeds.length]);
                },
                child: Text('${AppSettings.I.speed == 1.0 ? '1' : AppSettings.I.speed}×',
                    style: TextStyle(color: green, fontWeight: FontWeight.w700, fontSize: 15)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
