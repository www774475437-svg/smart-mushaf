import 'dart:async';

import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../data/quran.dart';
import '../data/surah_names.dart';
import '../data/tafsir.dart';
import 'common.dart';
import 'reader.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _c = TextEditingController();
  Timer? _deb;
  int mode = 0; // 0 quran, 1 tafsir
  List<int> results = [];
  List<int> surahs = [];
  bool busy = false;
  final SpeechToText _stt = SpeechToText();
  bool _sttReady = false, listening = false;

  Future<void> _voice() async {
    if (listening) {
      await _stt.stop();
      return;
    }
    if (!_sttReady) {
      try {
        _sttReady = await _stt.initialize(
          onError: (e) {
            if (mounted) setState(() => listening = false);
          },
          onStatus: (s) {
            if ((s == 'done' || s == 'notListening') && mounted) setState(() => listening = false);
          },
        );
      } catch (_) {}
    }
    if (!mounted) return;
    if (!_sttReady) {
      toast(context, 'البحث بالصوت غير متاح هنا. جرّبه في تطبيق الأندرويد واسمح بالميكروفون.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      listening = true;
      mode = 0;
    });
    try {
      await _stt.listen(
        onResult: (r) {
          if (!mounted) return;
          _c.text = r.recognizedWords;
          _run();
        },
        localeId: 'ar_SA',
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 3),
      );
    } catch (_) {
      if (mounted) setState(() => listening = false);
    }
  }

  @override
  void dispose() {
    _deb?.cancel();
    _stt.cancel();
    _c.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _deb?.cancel();
    _deb = Timer(const Duration(milliseconds: 300), _run);
  }

  Future<void> _run() async {
    final v = _c.text.trim();
    if (v.isEmpty) {
      setState(() {
        results = [];
        surahs = [];
      });
      return;
    }
    setState(() => busy = true);
    final n = normalizeAr(v);
    final ss = [for (var s = 1; s <= 114; s++) if (normalizeAr(surahName(s)).contains(n)) s];
    List<int> r;
    if (mode == 0) {
      r = QuranData.I.search(v);
      if (r.isEmpty) r = QuranData.I.looseSearch(v);
    } else {
      r = await TafsirService.I.search(TafsirService.I.byId('muyassar'), v);
    }
    if (!mounted) return;
    setState(() {
      results = r;
      surahs = ss;
      busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final q = QuranData.I;
    return Scaffold(
      appBar: AppBar(title: const Text('البحث')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
            child: TextField(
              controller: _c,
              autofocus: true,
              onChanged: _onChanged,
              decoration: InputDecoration(
                hintText: mode == 0 ? 'اكتب كلمة أو جزءًا من آية…' : 'ابحث في التفسير الميسر…',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: IconButton(
                  tooltip: 'البحث بالصوت',
                  onPressed: _voice,
                  icon: Icon(listening ? Icons.stop_circle_rounded : Icons.mic_rounded,
                      color: listening ? Colors.red : kEmerald),
                ),
                filled: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Pills<int>(
                values: const [0, 1],
                selected: mode,
                label: (m) => m == 0 ? 'في القرآن' : 'في التفسير',
                onChanged: (m) {
                  setState(() => mode = m);
                  _run();
                },
              ),
            ),
          ),
          if (listening)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('أستمع إليك… اقرأ جزءًا من الآية', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
            ),
          if (busy) const LinearProgressIndicator(),
          if (_c.text.trim().isNotEmpty && !busy)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text('${ar(results.length)}${results.length >= 300 ? '+' : ''} نتيجة',
                    style: const TextStyle(fontSize: 13)),
              ),
            ),
          Expanded(
            child: ListView(
              children: [
                for (final s in surahs)
                  ListTile(
                    leading: SurahNumberBadge(s),
                    title: Text('سورة ${surahName(s)}'),
                    onTap: () => MushafScreen.open(context, q.surahPage(s)),
                  ),
                for (final g in results)
                  ListTile(
                    title: Text(q.ayahs[g].text,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontFamily: quranFont(), fontSize: 18, height: 1.9)),
                    subtitle: Text('${q.ayahs[g].ref} • صفحة ${ar(q.ayahs[g].page)}',
                        style: const TextStyle(color: kGoldDeep, fontWeight: FontWeight.w600)),
                    onTap: () => MushafScreen.open(context, q.ayahs[g].page, flashG: g),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
