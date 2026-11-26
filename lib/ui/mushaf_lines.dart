import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/layout.dart';
import '../data/quran.dart';
import '../data/surah_names.dart';
import '../services/audio.dart';
import '../services/settings.dart';
import '../services/store.dart';
import 'common.dart';

/// A mushaf page drawn line by line exactly as in the Madinah mushaf (15 lines).
class MushafLinesPage extends StatefulWidget {
  final int page;
  final int? selectedG;
  final void Function(int g) onLongPress;

  /// Words marked by a teacher ("line:index"), drawn in red.
  final Set<String>? marks;
  final void Function(String key, LWord word)? onWordTap;
  final bool showInfo;
  const MushafLinesPage(
      {super.key,
      required this.page,
      this.selectedG,
      required this.onLongPress,
      this.marks,
      this.onWordTap,
      this.showInfo = true});
  @override
  State<MushafLinesPage> createState() => _MushafLinesPageState();
}

class _MushafLinesPageState extends State<MushafLinesPage> {
  static final Map<String, List<double>> _widths = {};
  static const _hafs = 'UthmanicHafs';

  @override
  void initState() {
    super.initState();
    _loadFont();
  }

  @override
  void didUpdateWidget(covariant MushafLinesPage old) {
    super.didUpdateWidget(old);
    if (old.page != widget.page) _loadFont();
  }

  void _loadFont() {
    final l = MushafLayout.I;
    if (l.qcf && !l.fontReady(widget.page)) {
      l.ensureFont(widget.page).then((ok) {
        if (ok && mounted) setState(() {});
      });
    }
    l.ensureFont(widget.page + 1);
    l.ensureFont(widget.page - 1);
  }

  /// Natural width of each line at font size 100.
  List<double> _measure(List<LLine> lines, String font, bool glyphs) {
    return _widths.putIfAbsent('$font:${widget.page}', () {
      final out = <double>[];
      for (final l in lines) {
        if (l.kind != 'w') {
          out.add(0);
          continue;
        }
        var sum = 0.0;
        for (final wd in l.words) {
          final tp = TextPainter(
            text: TextSpan(text: glyphs ? wd.c : wd.t, style: TextStyle(fontFamily: font, fontSize: 100)),
            textDirection: TextDirection.rtl,
            maxLines: 1,
          )..layout();
          sum += tp.width;
          tp.dispose();
        }
        out.add(sum);
      }
      return out;
    });
  }

  @override
  Widget build(BuildContext context) {
    final page = widget.page;
    final q = QuranData.I;
    final st = AppSettings.I;
    final col = pageColors(st.theme);
    final lay = MushafLayout.I;
    final lines = lay.pages[page - 1];
    final glyphs = lay.qcf && lay.fontReady(page);
    final font = glyphs ? 'QCF$page' : _hafs;
    final first = q.pageAyahs[page].isEmpty ? q.ayahs[0] : q.ayahs[q.pageAyahs[page].first];
    final audioG = AudioCtl.I.active ? AudioCtl.I.currentG : null;
    final hl = UserStore.I.highlights;
    final small = TextStyle(color: col.accent, fontSize: 15, fontWeight: FontWeight.w500);

    final body = LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      final h = c.maxHeight;
      final ws = _measure(lines, font, glyphs);
      final maxW = ws.fold<double>(1, math.max);
      final full = lines.length >= 15;
      final lineH = full ? h / 15 : math.min(h / 11, 64.0);
      var fs = w * 100 / maxW * 0.995;
      fs = math.min(fs, lineH / (glyphs ? 1.45 : 1.72));
      if (!full) fs = math.min(fs, w / (glyphs ? 13 : 15));
      final rows = <Widget>[];
      for (var i = 0; i < lines.length; i++) {
        final l = lines[i];
        Widget child;
        if (l.kind == 's') {
          child = SurahFrame(s: l.surah, col: col, height: lineH * 0.92);
        } else if (l.kind == 'b') {
          child = Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(lay.basmala,
                  textDirection: TextDirection.rtl,
                  style: TextStyle(fontFamily: _hafs, fontSize: lineH * 0.5, color: col.text, height: 1.5)),
            ),
          );
        } else if (l.kind == 'w') {
          final natural = ws[i] * fs / 100;
          final centered = !full || natural < w * 0.72;
          final n = l.words.length;
          final gap = centered ? fs * (glyphs ? 0.04 : 0.11) : math.max(0.0, (w - natural) / (2 * n));
          final kids = <Widget>[];
          // background of each word, so neighbouring words of one ayah join into one rounded shape
          final bgs = List<Color?>.filled(n, null);
          final fgs = List<Color>.filled(n, col.text);
          for (var k = 0; k < n; k++) {
            final wd = l.words[k];
            if (widget.marks != null && widget.marks!.contains('$i:$k')) {
              bgs[k] = Colors.red.withValues(alpha: 0.16);
              fgs[k] = Colors.red.shade700;
            } else if (wd.g == audioG) {
              bgs[k] = col.accent.withValues(alpha: 0.24);
            } else if (wd.g == widget.selectedG) {
              bgs[k] = col.accent.withValues(alpha: 0.30);
            } else if (hl[wd.g] != null) {
              bgs[k] = kHighlightColors[hl[wd.g]!.clamp(0, kHighlightColors.length - 1)].withValues(alpha: 0.42);
            }
            if (wd.end && !glyphs && fgs[k] == col.text) fgs[k] = col.accent;
          }
          final rad = Radius.circular(lineH * 0.22);
          for (var k = 0; k < n; k++) {
            final wd = l.words[k];
            final key = '$i:$k';
            final bg = bgs[k];
            final startRun = k == 0 || bgs[k - 1] != bg;
            final endRun = k == n - 1 || bgs[k + 1] != bg;
            kids.add(GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onWordTap == null ? null : () => widget.onWordTap!(key, wd),
              onLongPress: () => widget.onLongPress(wd.g),
              child: Container(
                height: lineH * 0.9,
                alignment: Alignment.center,
                padding: EdgeInsets.symmetric(horizontal: gap),
                decoration: bg == null
                    ? null
                    : BoxDecoration(
                        color: bg,
                        // the line reads right to left: a run starts on the right
                        borderRadius: BorderRadius.only(
                          topRight: startRun ? rad : Radius.zero,
                          bottomRight: startRun ? rad : Radius.zero,
                          topLeft: endRun ? rad : Radius.zero,
                          bottomLeft: endRun ? rad : Radius.zero,
                        ),
                      ),
                child: Text(glyphs ? wd.c : wd.t,
                    textDirection: TextDirection.rtl,
                    softWrap: false,
                    overflow: TextOverflow.visible,
                    style: TextStyle(fontFamily: font, fontSize: fs, color: fgs[k], height: glyphs ? 1.3 : 1.6)),
              ),
            ));
          }
          child = FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              textDirection: TextDirection.rtl,
              mainAxisSize: MainAxisSize.min,
              children: kids,
            ),
          );
        } else {
          child = const SizedBox.shrink();
        }
        rows.add(full
            ? Expanded(child: Center(child: child))
            : SizedBox(height: lineH * 1.15, child: Center(child: child)));
      }
      return Column(mainAxisAlignment: MainAxisAlignment.center, children: rows);
    });

    if (!widget.showInfo) return Container(color: col.bg, padding: const EdgeInsets.all(6), child: body);

    return Container(
      color: col.bg,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
          child: Column(
            children: [
              SizedBox(
                height: 30,
                child: Row(
                  children: [
                    Text('الجزء ${first.juz}', style: small),
                    const Spacer(),
                    Text(surahName(first.s), style: small),
                  ],
                ),
              ),
              Expanded(child: body),
              SizedBox(
                height: 34,
                child: Row(
                  children: [
                    Text(hizbLabel(first.hq), style: small),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                      decoration: BoxDecoration(
                        color: col.frame.withValues(alpha: 0.14),
                        border: Border.all(color: col.frame.withValues(alpha: 0.8)),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text('$page',
                          style: TextStyle(color: col.text, fontSize: 15, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ornamental surah title frame, drawn by the app.
class SurahFrame extends StatelessWidget {
  final int s;
  final PageColors col;
  final double height;
  const SurahFrame({super.key, required this.s, required this.col, required this.height});
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _FramePainter(col),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: height * 0.08),
              child: AppFonts.surahNames
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      textDirection: TextDirection.rtl,
                      children: [
                        Text('surah',
                            textDirection: TextDirection.ltr,
                            style: TextStyle(fontFamily: 'SurahNames', fontSize: height * 0.62, color: col.text, height: 1.1)),
                        Text(s.toString().padLeft(3, '0'),
                            textDirection: TextDirection.ltr,
                            style: TextStyle(fontFamily: 'SurahNames', fontSize: height * 0.62, color: col.text, height: 1.1)),
                      ],
                    )
                  : Text('سُورَةُ ${surahName(s)}',
                      style: TextStyle(fontFamily: quranFont(), fontSize: height * 0.5, color: col.text, height: 1.3)),

            ),
          ),
        ),
      ),
    );
  }
}

class _FramePainter extends CustomPainter {
  final PageColors col;
  _FramePainter(this.col);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final fill = Paint()..color = Color.alphaBlend(col.frame.withValues(alpha: 0.30), col.bg);
    final light = Paint()..color = Color.alphaBlend(col.frame.withValues(alpha: 0.12), col.bg);
    final line = Paint()
      ..color = col.frame
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3;
    final thin = Paint()
      ..color = col.bg.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1;
    final outer = RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, h), const Radius.circular(6));
    canvas.drawRRect(outer, fill);
    canvas.drawRRect(outer, line);
    canvas.drawRRect(outer.deflate(3.5), thin);

    // centre cartouche with pointed ends
    final cw = w * 0.34;
    final cx = w / 2;
    final path = Path()
      ..moveTo(cx - cw, 4)
      ..lineTo(cx + cw, 4)
      ..quadraticBezierTo(cx + cw + h * 0.18, h * 0.25, cx + cw + h * 0.36, h / 2)
      ..quadraticBezierTo(cx + cw + h * 0.18, h * 0.75, cx + cw, h - 4)
      ..lineTo(cx - cw, h - 4)
      ..quadraticBezierTo(cx - cw - h * 0.18, h * 0.75, cx - cw - h * 0.36, h / 2)
      ..quadraticBezierTo(cx - cw - h * 0.18, h * 0.25, cx - cw, 4)
      ..close();
    canvas.drawPath(path, light);
    canvas.drawPath(path, line);

    // side rosettes and scrolls
    final sideW = (w - 2 * (cw + h * 0.36)) / 2;
    for (final sx in [sideW / 2, w - sideW / 2]) {
      final c = Offset(sx, h / 2);
      final r = math.min(h * 0.36, sideW * 0.3);
      canvas.drawCircle(c, r, light);
      canvas.drawCircle(c, r, line);
      for (var i = 0; i < 10; i++) {
        final a = i * math.pi / 5;
        final pc = c + Offset(math.cos(a), math.sin(a)) * r * 0.55;
        canvas.drawOval(
            Rect.fromCenter(center: pc, width: r * 0.5, height: r * 0.5), Paint()..color = col.bg.withValues(alpha: 0.85));
        canvas.drawOval(Rect.fromCenter(center: pc, width: r * 0.5, height: r * 0.5), line..strokeWidth = 0.8);
      }
      canvas.drawCircle(c, r * 0.2, Paint()..color = col.frame);
      line.strokeWidth = 1.3;
      // small scrolls either side of the rosette
      for (final d in [-1.0, 1.0]) {
        final o = c + Offset(d * r * 1.75, 0);
        if (o.dx < 8 || o.dx > w - 8) continue;
        final sp = Path();
        for (final v in [-1.0, 1.0]) {
          sp.addArc(Rect.fromCircle(center: o + Offset(0, v * h * 0.17), radius: h * 0.13), 0, math.pi * 2);
        }
        canvas.drawPath(sp, thin);
        canvas.drawPath(sp, line..strokeWidth = 0.7);
        line.strokeWidth = 1.3;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _FramePainter old) => old.col != col;
}
