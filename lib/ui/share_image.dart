import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';

import '../data/quran.dart';
import '../data/surah_names.dart';
import 'common.dart';

class ShareImageScreen extends StatefulWidget {
  final int g;
  final String? tafsir;
  const ShareImageScreen({super.key, required this.g, this.tafsir});
  @override
  State<ShareImageScreen> createState() => _ShareImageScreenState();
}

class _ShareImageScreenState extends State<ShareImageScreen> {
  final GlobalKey _key = GlobalKey();
  int bg = 0;
  bool withTafsir = true;
  bool busy = false;

  static const List<List<Color>> _bgs = [
    [Color(0xFF062A22), Color(0xFF0F5C4A)],
    [Color(0xFF0E0E10), Color(0xFF2A2A30)],
    [Color(0xFF1B2A41), Color(0xFF324A6B)],
    [Color(0xFF3B2A12), Color(0xFF7A5A26)],
    [Color(0xFFF7F1E1), Color(0xFFEADDBA)],
  ];

  bool get light => bg == _bgs.length - 1;

  Future<void> _share() async {
    setState(() => busy = true);
    try {
      final boundary = _key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final img = await boundary.toImage(pixelRatio: 3);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      final ay = QuranData.I.ayahs[widget.g];
      final file = XFile.fromData(data!.buffer.asUint8List(),
          mimeType: 'image/png', name: 'ayah_${ay.s}_${ay.a}.png');
      await Share.shareXFiles([file], text: 'سورة ${surahName(ay.s)}: ${ay.a}');
    } catch (_) {
      if (mounted) toast(context, 'تعذّرت المشاركة');
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final ay = QuranData.I.ayahs[widget.g];
    final fg = light ? const Color(0xFF2A2116) : Colors.white;
    final tafsir = widget.tafsir;
    var shortTafsir = tafsir ?? '';
    if (shortTafsir.length > 700) shortTafsir = '${shortTafsir.substring(0, 700)}…';
    return Scaffold(
      appBar: AppBar(title: const Text('مشاركة كصورة')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          RepaintBoundary(
            key: _key,
            child: Container(
              padding: const EdgeInsets.fromLTRB(22, 26, 22, 18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: _bgs[bg],
                ),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(color: kGold.withValues(alpha: 0.7), width: 1.2),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('﴿${ay.text}﴾',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontFamily: quranFont(), fontSize: 24, height: 2.1, color: fg)),
                    const SizedBox(height: 10),
                    Text('سورة ${surahName(ay.s)} • الآية ${ar(ay.a)}',
                        style: const TextStyle(color: kGold, fontWeight: FontWeight.w700)),
                    if (tafsir != null && withTafsir) ...[
                      const SizedBox(height: 14),
                      Container(height: 1, color: kGold.withValues(alpha: 0.4)),
                      const SizedBox(height: 12),
                      Text(shortTafsir,
                          textAlign: TextAlign.justify,
                          style: TextStyle(color: fg.withValues(alpha: 0.9), fontSize: 14.5, height: 1.8)),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.asset('assets/images/logo.png', width: 20, height: 20),
                        ),
                        const SizedBox(width: 6),
                        Text('المصحف الذكي', style: TextStyle(color: fg.withValues(alpha: 0.75), fontSize: 12)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          const Text('الخلفية', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Row(
            children: [
              for (var i = 0; i < _bgs.length; i++)
                GestureDetector(
                  onTap: () => setState(() => bg = i),
                  child: Container(
                    width: 46,
                    height: 46,
                    margin: const EdgeInsetsDirectional.only(end: 10),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: _bgs[i]),
                      shape: BoxShape.circle,
                      border: Border.all(color: i == bg ? kGold : Colors.transparent, width: 3),
                    ),
                  ),
                ),
            ],
          ),
          if (tafsir != null)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('إظهار التفسير في الصورة'),
              value: withTafsir,
              onChanged: (v) => setState(() => withTafsir = v),
            ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: busy ? null : _share,
            icon: const Icon(Icons.share_rounded),
            label: const Text('مشاركة الصورة'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          ),
        ],
      ),
    );
  }
}
