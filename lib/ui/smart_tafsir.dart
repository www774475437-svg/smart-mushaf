import 'dart:async';

import 'package:flutter/material.dart';

import '../data/quran.dart';
import '../data/surah_names.dart';
import '../data/tafsir.dart';
import '../services/settings.dart';
import '../services/store.dart';
import '../services/tts.dart';
import 'common.dart';
import 'reader.dart';

/// «التفسير الذكي»: browse a page's tafsir, listen to it, search inside tafsir.
class SmartTafsirScreen extends StatefulWidget {
  const SmartTafsirScreen({super.key});
  @override
  State<SmartTafsirScreen> createState() => _SmartTafsirScreenState();
}

class _SmartTafsirScreenState extends State<SmartTafsirScreen> {
  int page = UserStore.I.lastPage;
  String tafsirId = AppSettings.I.tafsirId;
  final _search = TextEditingController();
  List<int>? results;
  bool searching = false;

  @override
  void dispose() {
    Tts.I.stop();
    _search.dispose();
    super.dispose();
  }

  Future<void> _doSearch() async {
    final v = _search.text.trim();
    if (v.isEmpty) {
      setState(() => results = null);
      return;
    }
    setState(() => searching = true);
    var t = TafsirService.I.byId(tafsirId);
    if (!await TafsirService.I.isAvailableOffline(t)) t = TafsirService.I.byId('muyassar');
    final r = await TafsirService.I.search(t, v);
    if (mounted) {
      setState(() {
        results = r;
        searching = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = QuranData.I;
    final ids = q.pageAyahs[page];
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('التفسير الذكي')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 30),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF3B2A12), kGoldDeep]),
              borderRadius: BorderRadius.circular(22),
            ),
            child: const Row(
              children: [
                Icon(Icons.lightbulb_rounded, color: Colors.white, size: 34),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'اقرأ تفسير الصفحة كاملة، واستمع إليه بصوت مقروء، وابحث عن أي معنى داخل التفاسير.',
                    style: TextStyle(color: Colors.white, height: 1.7),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _search,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _doSearch(),
            decoration: InputDecoration(
              hintText: 'ابحث عن معنى في التفسير… (مثال: الصبر)',
              prefixIcon: const Icon(Icons.manage_search_rounded),
              suffixIcon: IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: _doSearch),
              filled: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
            ),
          ),
          if (searching) const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator()),
          if (results != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Text('${ar(results!.length)} نتيجة', style: const TextStyle(fontWeight: FontWeight.w700)),
                  const Spacer(),
                  TextButton(
                    onPressed: () => setState(() {
                      results = null;
                      _search.clear();
                    }),
                    child: const Text('إغلاق البحث'),
                  ),
                ],
              ),
            ),
            for (final g in results!.take(100))
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: ListTile(
                  title: Text(q.ayahs[g].text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontFamily: 'AmiriQuran', fontSize: 17, height: 1.8)),
                  subtitle: Text(q.ayahs[g].ref),
                  onTap: () => setState(() {
                    page = q.ayahs[g].page;
                    results = null;
                  }),
                ),
              ),
          ],
          if (results == null) ...[
            const SizedBox(height: 14),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final t in kTafsirs)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 8),
                      child: ChoiceChip(
                        label: Text(t.name),
                        selected: t.id == tafsirId,
                        onSelected: (_) {
                          Tts.I.stop();
                          setState(() => tafsirId = t.id);
                        },
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                IconButton.filledTonal(
                  onPressed: page > 1 ? () => setState(() => page--) : null,
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
                Expanded(
                  child: Column(
                    children: [
                      Text('صفحة ${ar(page)}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                      Text('سورة ${surahName(q.surahOfPage(page))} • الجزء ${ar(q.juzOfPage(page))}',
                          style: const TextStyle(fontSize: 12.5)),
                    ],
                  ),
                ),
                IconButton.filledTonal(
                  onPressed: page < 604 ? () => setState(() => page++) : null,
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton.icon(
                  onPressed: () => MushafScreen.open(context, page),
                  icon: const Icon(Icons.menu_book_rounded),
                  label: const Text('افتح الصفحة في المصحف'),
                ),
                ListenableBuilder(
                  listenable: Tts.I,
                  builder: (context, _) {
                    final key = 'page:$tafsirId:$page';
                    final on = Tts.I.speaking && Tts.I.key == key;
                    return TextButton.icon(
                      onPressed: () async {
                        if (on) {
                          Tts.I.stop();
                          return;
                        }
                        final parts = <String>[];
                        for (final g in ids) {
                          try {
                            final t = await TafsirService.I.get(tafsirId, g);
                            parts.add('الآية ${q.ayahs[g].a}. $t');
                          } catch (_) {}
                        }
                        if (parts.isEmpty) {
                          if (context.mounted) toast(context, 'هذا التفسير يحتاج إلى الإنترنت');
                          return;
                        }
                        Tts.I.speak(parts.join('\n'), key: key);
                      },
                      icon: Icon(on ? Icons.stop_rounded : Icons.volume_up_rounded),
                      label: Text(on ? 'إيقاف' : 'استمع لتفسير الصفحة'),
                    );
                  },
                ),
              ],
            ),
            for (final g in ids)
              _AyahTafsir(key: ValueKey('$tafsirId:$g'), g: g, tafsirId: tafsirId, cs: cs),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                border: Border.all(color: kGold.withValues(alpha: 0.5)),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Text(
                'تفسير ابن عثيمين رحمه الله وصوته في التفسير سيُضافان في تحديث قادم بإذن الله، بنقل كلامه بنصّه مع ذكر المصدر.',
                textAlign: TextAlign.center,
                style: TextStyle(height: 1.7),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AyahTafsir extends StatefulWidget {
  final int g;
  final String tafsirId;
  final ColorScheme cs;
  const _AyahTafsir({super.key, required this.g, required this.tafsirId, required this.cs});
  @override
  State<_AyahTafsir> createState() => _AyahTafsirState();
}

class _AyahTafsirState extends State<_AyahTafsir> {
  late Future<String> f;
  @override
  void initState() {
    super.initState();
    f = TafsirService.I.get(widget.tafsirId, widget.g);
  }

  @override
  Widget build(BuildContext context) {
    final ay = QuranData.I.ayahs[widget.g];
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: widget.cs.surface, borderRadius: BorderRadius.circular(18)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('${ay.text} ﴿${ar(ay.a)}﴾',
              textAlign: TextAlign.center, style: const TextStyle(fontFamily: 'AmiriQuran', fontSize: 19, height: 1.9)),
          const Divider(),
          FutureBuilder<String>(
            future: f,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Padding(padding: EdgeInsets.all(10), child: LinearProgressIndicator());
              }
              if (snap.hasError) {
                return const Text('هذا التفسير يحتاج إلى الإنترنت، أو حمّله من الإعدادات.', textAlign: TextAlign.center);
              }
              return SelectableText(snap.data ?? '', style: const TextStyle(fontSize: 15.5, height: 1.85));
            },
          ),
        ],
      ),
    );
  }
}
