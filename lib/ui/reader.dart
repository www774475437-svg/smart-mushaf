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
import '../data/layout.dart';
import 'common.dart';
import 'mushaf_lines.dart';
import 'reciter_sheet.dart';
import 'search.dart';

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

  @override
  void initState() {
    super.initState();
    page = widget.page.clamp(1, 604);
    selectedG = widget.flashG;
    _pc = PageController(initialPage: page - 1);
    _ipl.itemPositions.addListener(_onPos);
    AudioCtl.I.addListener(_onAudio);
    WidgetsBinding.instance.addPostFrameCallback((_) => UserStore.I.setLastPage(page));
    if (AppSettings.I.keepAwake) WakelockPlus.enable();
    Timer(const Duration(seconds: 3), () {
      if (mounted && bars && !autoOn) setState(() => bars = false);
    });
    if (widget.flashG != null) {
      Timer(const Duration(seconds: 3), () {
        if (mounted && selectedG == widget.flashG) setState(() => selectedG = null);
      });
    }
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _ipl.itemPositions.removeListener(_onPos);
    AudioCtl.I.removeListener(_onAudio);
    WakelockPlus.disable();
    _pc.dispose();
    super.dispose();
  }

  void _setPage(int p) {
    if (p == page) return;
    setState(() => page = p);
    UserStore.I.setLastPage(p);
  }

  void _onPos() {
    if (!AppSettings.I.scrollMode || !mounted) return;
    final pos = _ipl.itemPositions.value.where((p) => p.itemTrailingEdge > 0.3).toList();
    if (pos.isEmpty) return;
    pos.sort((a, b) => a.index.compareTo(b.index));
    final p = pos.first.index + 1;
    if (p != page) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _setPage(p);
      });
    }
  }

  void _onAudio() {
    final g = AudioCtl.I.currentG;
    if (g == null || g == _lastAudioG) return;
    _lastAudioG = g;
    if (!AppSettings.I.followAudio) return;
    final p = QuranData.I.ayahs[g].page;
    if (p != page) _goTo(p);
  }

  void _goTo(int p, {bool animate = true}) {
    p = p.clamp(1, 604);
    if (AppSettings.I.scrollMode) {
      if (_isc.isAttached) {
        if (animate && (p - page).abs() <= 3) {
          _isc.scrollTo(index: p - 1, duration: const Duration(milliseconds: 450), curve: Curves.easeInOut);
        } else {
          _isc.jumpTo(index: p - 1);
        }
      }
    } else if (_pc.hasClients) {
      if (animate && (p - page).abs() <= 3) {
        _pc.animateToPage(p - 1, duration: const Duration(milliseconds: 420), curve: Curves.easeInOut);
      } else {
        _pc.jumpToPage(p - 1);
      }
    }
    _setPage(p);
  }

  // ---------- auto scroll ----------
  void _startAuto() {
    setState(() {
      autoOn = true;
      autoPaused = false;
    });
    WakelockPlus.enable();
    _schedule();
  }

  void _schedule() {
    _autoTimer?.cancel();
    final secs = AppSettings.I.autoSeconds;
    if (AppSettings.I.scrollMode) {
      final h = MediaQuery.of(context).size.height;
      final perSec = h * 1.1 / secs;
      _autoTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!autoPaused && mounted) {
          _soc.animateScroll(offset: perSec, duration: const Duration(milliseconds: 1000), curve: Curves.linear);
        }
      });
    } else {
      _autoTimer = Timer.periodic(Duration(seconds: secs), (_) {
        if (!autoPaused && mounted && _pc.hasClients && page < 604) {
          _pc.nextPage(duration: const Duration(milliseconds: 650), curve: Curves.easeInOut);
        }
      });
    }
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
          body: Stack(
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
        );
      },
    );
  }

  Widget _pageView() {
    return PageView.builder(
      key: const ValueKey('pages'),
      controller: _pc,
      itemCount: 604,
      onPageChanged: (i) => _setPage(i + 1),
      itemBuilder: (_, i) => MushafPage(page: i + 1, expand: true, selectedG: selectedG, onLongPress: _openAyah),
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
      itemBuilder: (_, i) => MushafPage(page: i + 1, expand: false, selectedG: selectedG, onLongPress: _openAyah),
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
            AudioBar(page: page, onPlay: _playPage),
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
  const MushafPage({super.key, required this.page, required this.expand, this.selectedG, required this.onLongPress});
  @override
  State<MushafPage> createState() => _MushafPageState();
}

class _MushafPageState extends State<MushafPage> {
  final Map<int, LongPressGestureRecognizer> _recs = {};

  LongPressGestureRecognizer _rec(int g) =>
      _recs.putIfAbsent(g, () => LongPressGestureRecognizer()..onLongPress = () => widget.onLongPress(g));

  @override
  void dispose() {
    for (final r in _recs.values) {
      r.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([AppSettings.I, AudioCtl.I, UserStore.I]),
      builder: (context, _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    if (widget.expand && MushafLayout.I.ready && quranFont() == 'UthmanicHafs') {
      return MushafLinesPage(page: widget.page, selectedG: widget.selectedG, onLongPress: widget.onLongPress);
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
  const AudioBar({super.key, this.page, this.onPlay});
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
                    const speeds = [0.75, 1.0, 1.25, 1.5, 2.0];
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
