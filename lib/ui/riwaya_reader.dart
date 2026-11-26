import 'package:flutter/material.dart';

import '../data/quran.dart';
import '../data/riwaya.dart';
import '../data/surah_names.dart';
import '../services/settings.dart';
import 'common.dart';

class RiwayaReader extends StatefulWidget {
  final String riwayaId;
  final int surah;
  const RiwayaReader({super.key, required this.riwayaId, required this.surah});
  @override
  State<RiwayaReader> createState() => _RiwayaReaderState();
}

class _RiwayaReaderState extends State<RiwayaReader> {
  late int s;
  late Future<Map<int, List<String>>> f;

  @override
  void initState() {
    super.initState();
    s = widget.surah;
    f = RiwayaService.I.load(widget.riwayaId);
  }

  @override
  Widget build(BuildContext context) {
    final col = pageColors(AppSettings.I.theme);
    final rw = riwayaById(widget.riwayaId);
    return Scaffold(
      backgroundColor: col.bg,
      appBar: AppBar(
        backgroundColor: col.bar,
        foregroundColor: col.text,
        title: Column(
          children: [
            Text('سورة ${surahName(s)}', style: TextStyle(color: col.text, fontWeight: FontWeight.w700)),
            Text('رواية ${rw.name}', style: TextStyle(color: col.accent, fontSize: 12)),
          ],
        ),
      ),
      body: FutureBuilder<Map<int, List<String>>>(
        future: f,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (snap.hasError || snap.data == null) {
            return const Center(child: Text('لم تُحمَّل هذه الرواية بعد، حمّلها من الإعدادات.'));
          }
          final verses = snap.data![s] ?? const <String>[];
          final spans = <InlineSpan>[];
          for (var i = 0; i < verses.length; i++) {
            spans.add(TextSpan(text: '${verses[i]} '));
            spans.add(TextSpan(text: '${ayahMark(i + 1)} ', style: TextStyle(color: col.accent)));
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (s != 1 && s != 9)
                Text('بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontFamily: quranFont(), fontSize: AppSettings.I.fontSize, color: col.text, height: 2)),
              Text.rich(
                TextSpan(children: spans),
                textAlign: TextAlign.justify,
                style: TextStyle(fontFamily: quranFont(), fontSize: AppSettings.I.fontSize, height: 2.1, color: col.text),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  if (s > 1)
                    OutlinedButton.icon(
                      onPressed: () => setState(() => s--),
                      icon: const Icon(Icons.chevron_right_rounded),
                      label: Text(surahName(s - 1)),
                    ),
                  const Spacer(),
                  if (s < 114)
                    FilledButton.icon(
                      onPressed: () => setState(() => s++),
                      icon: const Icon(Icons.chevron_left_rounded),
                      label: Text(surahName(s + 1)),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text('عدد الآيات في هذه الرواية: ${ar(verses.length)} (في حفص: ${ar(QuranData.I.surahCount[s])})',
                  textAlign: TextAlign.center, style: TextStyle(color: col.text.withValues(alpha: 0.6), fontSize: 12)),
            ],
          );
        },
      ),
    );
  }
}
