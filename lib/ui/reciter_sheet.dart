import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../data/quran.dart';
import '../data/reciters.dart';
import '../data/surah_names.dart';
import '../data/tafsir.dart';
import '../services/audio.dart';
import '../services/tts.dart';
import 'common.dart';
import 'mukhtasar_audio.dart';
import 'settings_screen.dart';
import 'reciters_screen.dart';

/// Recorded (audio) tafsir series from MP3Quran.
class AudioTafsir {
  final int id;
  final String name;
  const AudioTafsir(this.id, this.name);
}

class AudioTafsirService {
  static List<AudioTafsir>? _list;
  static final Map<int, List<Map<String, dynamic>>> _files = {};

  static Future<List<AudioTafsir>> list() async {
    if (_list != null) return _list!;
    final out = <AudioTafsir>[];
    try {
      final r = await http
          .get(Uri.parse('https://mp3quran.net/api/v3/tafasir?language=ar'))
          .timeout(const Duration(seconds: 20));
      if (r.statusCode == 200) {
        final j = jsonDecode(utf8.decode(r.bodyBytes));
        dynamic l = j is Map ? j['tafasir'] : j;
        if (l is Map) l = [l];
        for (final e in (l as List)) {
          final m = e as Map<String, dynamic>;
          final id = (m['id'] as num?)?.toInt();
          final name = (m['name'] as String?)?.trim() ?? '';
          if (id != null && name.isNotEmpty) out.add(AudioTafsir(id, name));
        }
      }
    } catch (_) {}
    if (out.isNotEmpty) _list = out;
    return out;
  }

  /// The audio lessons of one tafsir that belong to a surah.
  static Future<List<Map<String, dynamic>>> lessons(int tafsirId, int surah) async {
    if (!_files.containsKey(tafsirId)) {
      final r = await http
          .get(Uri.parse('https://mp3quran.net/api/v3/tafsir?tafsir=$tafsirId&language=ar'))
          .timeout(const Duration(seconds: 30));
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      dynamic t = j is Map ? (j['tafasir'] ?? j['tafsir'] ?? j) : j;
      dynamic soar = t is Map ? (t['soar'] ?? t['data']) : t;
      final all = <Map<String, dynamic>>[];
      if (soar is Map) {
        for (final v in soar.values) {
          if (v is List) {
            for (final e in v) {
              all.add(Map<String, dynamic>.from(e as Map));
            }
          }
        }
      } else if (soar is List) {
        for (final e in soar) {
          all.add(Map<String, dynamic>.from(e as Map));
        }
      }
      _files[tafsirId] = all;
    }
    return _files[tafsirId]!
        .where((e) => ((e['sura_id'] ?? e['surah_id'] ?? e['sura']) as num?)?.toInt() == surah && e['url'] != null)
        .toList();
  }
}

Color _bg(BuildContext c) => isDark(c) ? const Color(0xFF0E1614) : const Color(0xFFF4F0E8);
Color _card(BuildContext c) => isDark(c) ? const Color(0xFF17211E) : const Color(0xFFFFFCF7);

/// «اختيار التلاوة»: one tidy list to pick the reciter, plus audio tafsir.
Future<void> showReciterSheet(BuildContext context, {int? page}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ReciterSheet(page: page),
  );
}

class _ReciterSheet extends StatefulWidget {
  final int? page;
  const _ReciterSheet({this.page});
  @override
  State<_ReciterSheet> createState() => _ReciterSheetState();
}

class _ReciterSheetState extends State<_ReciterSheet> {
  String q = '';
  late Future<List<AudioTafsir>> tafasir;

  @override
  void initState() {
    super.initState();
    tafasir = AudioTafsirService.list();
    Reciters.I.loadTimed();
  }

  bool _m(String name) => q.isEmpty || normalizeAr(name).contains(normalizeAr(q));

  int get _surah => QuranData.I.surahOfPage(widget.page ?? 1);

  Future<void> _ttsPage() async {
    final qd = QuranData.I;
    final ids = qd.pageAyahs[widget.page ?? 1];
    final parts = <String>[];
    for (final g in ids) {
      try {
        parts.add('الآية ${qd.ayahs[g].a}. ${await TafsirService.I.get('muyassar', g)}');
      } catch (_) {}
    }
    if (parts.isEmpty) return;
    await AudioCtl.I.stop();
    Tts.I.speak(parts.join('\n'), key: 'page:${widget.page}');
    if (mounted) {
      toast(context, 'قراءة التفسير الميسر لهذه الصفحة');
      Navigator.pop(context);
    }
  }

  Future<void> _openTafsir(AudioTafsir t) async {
    final s = _surah;
    toast(context, 'جارٍ التحميل…');
    List<Map<String, dynamic>> ls = [];
    try {
      ls = await AudioTafsirService.lessons(t.id, s);
    } catch (_) {}
    if (!mounted) return;
    if (ls.isEmpty) {
      toast(context, 'لا توجد تسجيلات لسورة ${surahName(s)} في هذا التفسير');
      return;
    }
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      backgroundColor: _bg(context),
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Center(child: Text('${t.name} • سورة ${surahName(s)}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(color: _card(ctx), borderRadius: BorderRadius.circular(16)),
              child: Column(
                children: [
                  for (final l in ls)
                    ListTile(
                      leading: const Icon(Icons.play_circle_outline_rounded, color: kEmerald),
                      title: Text('${l['name'] ?? 'درس'}'),
                      onTap: () {
                        Tts.I.stop();
                        AudioCtl.I.playUrl('${l['url']}', t.name, '${l['name'] ?? surahName(s)}');
                        Navigator.pop(ctx);
                        Navigator.pop(context);
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(6, 20, 6, 10),
        child: Text(t, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
      );

  Widget _group(List<Widget> rows) {
    final items = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      if (i > 0) items.add(const Divider(height: 1, indent: 52));
      items.add(rows[i]);
    }
    return Container(
      decoration: BoxDecoration(color: _card(context), borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: Column(children: items),
    );
  }

  Widget _reciter(Reciter r) {
    final sel = Reciters.I.currentId == r.id;
    final green = Theme.of(context).colorScheme.primary;
    return ListTile(
      leading: Icon(sel ? Icons.play_arrow_rounded : Icons.play_arrow_outlined, color: sel ? green : kGoldDeep.withValues(alpha: 0.6)),
      title: Text(r.name, style: TextStyle(fontWeight: sel ? FontWeight.w700 : FontWeight.w500, fontSize: 16.5, color: sel ? green : null)),
      subtitle: r.id == kMukhtasarId
          ? Text('${r.sub} • تُتلى الآية ثم يُقرأ تفسيرها', style: const TextStyle(color: kGoldDeep))
          : null,
      trailing: IconButton(
        tooltip: 'السور والتحميل',
        icon: Icon(Icons.info_outline_rounded, color: green),
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReciterSurahsScreen(r: r))),
      ),
      onTap: () {
        Reciters.I.select(r.id);
        Navigator.pop(context);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final green = Theme.of(context).colorScheme.primary;
    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.96,
      expand: false,
      builder: (ctx, sc) => Container(
        decoration: BoxDecoration(color: _bg(context), borderRadius: const BorderRadius.vertical(top: Radius.circular(26))),
        child: ListenableBuilder(
          listenable: Reciters.I,
          builder: (context, _) {
            final rs = Reciters.I;
            // one row per reciter: the continuous recording when there is one
            final seen = <String>{};
            final list = <Reciter>[];
            for (final r in [...rs.timed, ...rs.perAyah, ...rs.custom]) {
              final key = normalizeAr(r.name.split('(').first.trim());
              if (r.custom || seen.add(key)) list.add(r);
            }
            list.sort((a, b) => normalizeAr(a.name).compareTo(normalizeAr(b.name)));
            final shown = list.where((r) => _m(r.name)).toList();
            return ListView(
              controller: sc,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 30),
              children: [
                Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AddReciterScreen())),
                      child: Text('إضافة', style: TextStyle(color: green, fontWeight: FontWeight.w600, fontSize: 15)),
                    ),
                    const Expanded(
                      child: Text('اختيار التلاوة',
                          textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: CircleAvatar(
                        radius: 15,
                        backgroundColor: Colors.grey.withValues(alpha: 0.22),
                        child: const Icon(Icons.close_rounded, size: 18, color: kGoldDeep),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  onChanged: (v) => setState(() => q = v.trim()),
                  decoration: InputDecoration(
                    hintText: 'بحث',
                    prefixIcon: const Icon(Icons.search_rounded),
                    filled: true,
                    fillColor: Colors.grey.withValues(alpha: 0.16),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                if (q.isEmpty) ...[
                  _section('التفسير'),
                  FutureBuilder<List<AudioTafsir>>(
                    future: tafasir,
                    builder: (context, snap) => _group([
                      _reciter(rs.mukhtasar),
                      for (final t in snap.data ?? const <AudioTafsir>[])
                        ListTile(
                          leading: Icon(Icons.play_arrow_outlined, color: kGoldDeep.withValues(alpha: 0.6)),
                          title: Text(t.name, style: const TextStyle(fontSize: 16.5)),
                          subtitle: const Text('تفسير مسجَّل بالصوت', style: TextStyle(color: kGoldDeep)),
                          trailing: const Icon(Icons.chevron_left_rounded, color: Colors.grey),
                          onTap: () => _openTafsir(t),
                        ),
                    ]),
                  ),
                ],
                if (q.isEmpty) ...[
                  _section('التفسير بلغات أخرى'),
                  _group([
                    for (final r in rs.spoken)
                      ListTile(
                        leading: Icon(rs.currentId == r.id ? Icons.play_arrow_rounded : Icons.play_arrow_outlined,
                            color: rs.currentId == r.id ? green : kGoldDeep.withValues(alpha: 0.6)),
                        title: Text(r.name,
                            style: TextStyle(
                                fontSize: 16.5,
                                fontWeight: rs.currentId == r.id ? FontWeight.w700 : FontWeight.w500,
                                color: rs.currentId == r.id ? green : null)),
                        subtitle: Text('${r.sub} • يُقرأ معنى كل آية بالصوت', style: const TextStyle(color: kGoldDeep)),
                        onTap: () {
                          Reciters.I.select(r.id);
                          Navigator.pop(context);
                        },
                      ),
                    ListTile(
                      leading: Icon(Icons.translate_rounded, color: green),
                      title: Text('تفاسير مكتوبة بثلاثين لغة', style: TextStyle(color: green, fontWeight: FontWeight.w600)),
                      trailing: const Icon(Icons.chevron_left_rounded, color: Colors.grey),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TafsirsScreen())),
                    ),
                  ]),
                ],
                _section('التلاوات'),
                if (rs.loadingTimed) const Padding(padding: EdgeInsets.only(bottom: 8), child: LinearProgressIndicator()),
                _group([for (final r in shown) _reciter(r)]),
                const SizedBox(height: 12),
                _group([
                  ListTile(
                    leading: Icon(Icons.library_music_outlined, color: green),
                    title: Text('جميع القرّاء (أكثر من مئتي تلاوة)', style: TextStyle(color: green, fontWeight: FontWeight.w600)),
                    trailing: const Icon(Icons.chevron_left_rounded, color: Colors.grey),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RecitersScreen(pick: true))),
                  ),
                ]),
              ],
            );
          },
        ),
      ),
    );
  }
}
