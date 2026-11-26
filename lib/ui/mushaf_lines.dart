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
class MushafLinesPage extends StatelessWidget {
  final int page;
  final int? selectedG;
  final void Function(int g) onLongPress;
  const MushafLinesPage({super.key, required this.page, this.selectedG, required this.onLongPress});

  static final Map<int, List<double>> _widths = {};
  static const _font = 'UthmanicHafs';

  /// Natural width of each line at font size 100.
  List<double> _measure(List<LLine> lines) {
    return _widths.putIfAbsent(page, () {
      final out = <double>[];
      for (final l in lines) {
        if (l.kind != 'w') {
          out.add(0);
          continue;
        }
        final tp = TextPainter(
          text: TextSpan(
              text: l.words.map((w) => w.t).join(' '), style: const TextStyle(fontFamily: _font, fontSize: 100)),
          textDirection: TextDirection.rtl,
          maxLines: 1,
        )..layout();
        out.add(tp.width);
        tp.dispose();
      }
      return out;
    });
  }

  @override
  Widget build(BuildContext context) {
    final q = QuranData.I;
    final st = AppSettings.I;
    final col = pageColors(st.theme);
    final lines = MushafLayout.I.pages[page - 1];
    final first = q.pageAyahs[page].isEmpty ? q.ayahs[0] : q.ayahs[q.pageAyahs[page].first];
    final audioG = AudioCtl.I.active ? AudioCtl.I.currentG : null;
    final hl = UserStore.I.highlights;
    final small = TextStyle(color: col.accent, fontSize: 15, fontWeight: FontWeight.w500);

    return Container(
      color: col.bg,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
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
              Expanded(
                child: LayoutBuilder(builder: (context, c) {
                  final w = c.maxWidth;
                  final h = c.maxHeight;
                  final ws = _measure(lines);
                  final maxW = ws.fold<double>(1, math.max);
                  final full = lines.length >= 15;
                  final lineH = full ? h / 15 : math.min(h / 11, 64.0);
                  var fs = w * 100 / maxW * 0.99;
                  fs = math.min(fs, lineH / 1.72);
                  if (!full) fs = math.min(fs, w / 15);
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
                          child: Text(MushafLayout.I.basmala,
                              textDirection: TextDirection.rtl,
                              style: TextStyle(fontFamily: _font, fontSize: fs * 1.02, color: col.text, height: 1.5)),
                        ),
                      );
                    } else if (l.kind == 'w') {
                      final natural = ws[i] * fs / 100;
                      final centered = !full || natural < w * 0.72;
                      final kids = <Widget>[];
                      for (var k = 0; k < l.words.length; k++) {
                        final wd = l.words[k];
                        Color? bg;
                        var color = col.text;
                        if (wd.g == audioG) {
                          bg = col.accent.withValues(alpha: 0.22);
                        } else if (wd.g == selectedG) {
                          bg = kEmerald.withValues(alpha: 0.16);
                        } else if (hl[wd.g] != null) {
                          bg = kHighlightColors[hl[wd.g]!.clamp(0, kHighlightColors.length - 1)].withValues(alpha: 0.4);
                        }
                        if (wd.end) color = col.accent;
                        if (centered && k > 0) kids.add(SizedBox(width: fs * 0.22));
                        kids.add(GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onLongPress: () => onLongPress(wd.g),
                          child: Container(
                            color: bg,
                            child: Text(wd.t,
                                textDirection: TextDirection.rtl,
                                softWrap: false,
                                style: TextStyle(fontFamily: _font, fontSize: fs, color: color, height: 1.6)),
                          ),
                        ));
                      }
                      child = FittedBox(
                        fit: BoxFit.scaleDown,
                        child: SizedBox(
                          width: centered ? null : w,
                          child: Row(
                            textDirection: TextDirection.rtl,
                            mainAxisSize: centered ? MainAxisSize.min : MainAxisSize.max,
                            mainAxisAlignment: centered ? MainAxisAlignment.center : MainAxisAlignment.spaceBetween,
                            children: kids,
                          ),
                        ),
                      );
                    } else {
                      child = const SizedBox.shrink();
                    }
                    rows.add(full
                        ? Expanded(child: Center(child: child))
                        : SizedBox(height: lineH * 1.15, child: Center(child: child)));
                  }
                  return Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: rows,
                  );
                }),
              ),
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
              child: Text('سُورَةُ ${surahName(s)}',
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
