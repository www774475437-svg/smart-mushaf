import 'package:flutter/material.dart';

import '../data/quran.dart';
import '../data/riwaya.dart';
import '../data/surah_names.dart';
import '../services/audio.dart';
import '../services/settings.dart';
import '../services/store.dart';
import 'ayah_sheet.dart';
import 'common.dart';
import 'reader.dart';
import 'riwaya_reader.dart';

class IndexScreen extends StatefulWidget {
  const IndexScreen({super.key});
  @override
  State<IndexScreen> createState() => _IndexScreenState();
}

class _IndexScreenState extends State<IndexScreen> {
  String filter = '';

  void _openSurah(int s) {
    final rw = AppSettings.I.riwaya;
    if (rw != 'hafs') {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => RiwayaReader(riwayaId: rw, surah: s)));
    } else {
      MushafScreen.open(context, QuranData.I.surahPage(s));
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = QuranData.I;
    final surahs = [
      for (var s = 1; s <= 114; s++)
        if (filter.isEmpty || normalizeAr(surahName(s)).contains(normalizeAr(filter)) || '$s' == filter) s
    ];
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('الفهرس'),
          bottom: const TabBar(tabs: [Tab(text: 'السور'), Tab(text: 'الأجزاء'), Tab(text: 'العلامات')]),
        ),
        body: TabBarView(
          children: [
            Column(
              children: [
                ListenableBuilder(
                  listenable: AppSettings.I,
                  builder: (context, _) {
                    final rw = AppSettings.I.riwaya;
                    if (rw == 'hafs') return const SizedBox.shrink();
                    return Container(
                      width: double.infinity,
                      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: kGold.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
                      child: Text('الرواية المختارة: ${riwayaById(rw).name} — تغييرها من الإعدادات',
                          textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600)),
                    );
                  },
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'ابحث عن سورة…',
                      prefixIcon: const Icon(Icons.search_rounded),
                      filled: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                      contentPadding: EdgeInsets.zero,
                    ),
                    onChanged: (v) => setState(() => filter = v.trim()),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: surahs.length,
                    itemBuilder: (_, i) {
                      final s = surahs[i];
                      return ListTile(
                        leading: SurahNumberBadge(s),
                        title: Text('سورة ${surahName(s)}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                        subtitle: Text(
                            '${q.surahMeccan[s] ? 'مكية' : 'مدنية'} • آياتها ${ar(q.surahCount[s])} • صفحة ${ar(q.surahPage(s))}'),
                        trailing: IconButton(
                          tooltip: 'استمع للسورة',
                          icon: const Icon(Icons.play_circle_outline_rounded, color: kEmerald),
                          onPressed: () {
                            AudioCtl.I.playSurah(s);
                            toast(context, 'تشغيل سورة ${surahName(s)}');
                          },
                        ),
                        onTap: () => _openSurah(s),
                      );
                    },
                  ),
                ),
                const AudioBar(),
              ],
            ),
            ListView.builder(
              itemCount: 30,
              itemBuilder: (_, i) {
                final j = i + 1;
                final g = q.juzStartG[j];
                final ay = q.ayahs[g < 0 ? 0 : g];
                return ListTile(
                  leading: Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: kEmerald.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                    child: Text(ar(j), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  ),
                  title: Text('الجزء ${ar(j)}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('يبدأ من سورة ${surahName(ay.s)} آية ${ar(ay.a)} • صفحة ${ar(ay.page)}'),
                  onTap: () => MushafScreen.open(context, ay.page),
                );
              },
            ),
            ListenableBuilder(
              listenable: UserStore.I,
              builder: (context, _) {
                final bs = UserStore.I.bookmarks;
                final hl = UserStore.I.highlights.keys.toList()..sort();
                if (bs.isEmpty && hl.isEmpty && UserStore.I.notes.isEmpty && UserStore.I.fawasil.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(30),
                      child: Text('لا توجد علامات بعد.\nاضغط مطولاً على أي آية واختر «علامة» أو «تظليل».',
                          textAlign: TextAlign.center, style: TextStyle(height: 1.8)),
                    ),
                  );
                }
                return ListView(
                  children: [
                    for (var i = 0; i < 4; i++)
                      if (UserStore.I.fawasil[i] != null)
                        ListTile(
                          leading: Icon(Icons.bookmark_rounded, color: kFasilColors[i], size: 28),
                          title: Text('الفاصل ${kFasilNames[i]}'),
                          subtitle: Text(q.ayahs[UserStore.I.fawasil[i]![0]].ref),
                          onTap: () => MushafScreen.open(context, q.ayahs[UserStore.I.fawasil[i]![0]].page,
                              flashG: UserStore.I.fawasil[i]![0]),
                        ),
                    for (final b in bs)
                      ListTile(
                        leading: const Icon(Icons.bookmark_rounded, color: kGold),
                        title: Text(b.g >= 0 ? q.ayahs[b.g].ref : 'صفحة ${ar(b.page)}'),
                        subtitle: Text(b.g >= 0
                            ? q.clean[b.g]
                            : 'سورة ${surahName(q.surahOfPage(b.page))} • الجزء ${ar(q.juzOfPage(b.page))}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        onTap: () => MushafScreen.open(context, b.page, flashG: b.g >= 0 ? b.g : null),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline_rounded),
                          onPressed: () => UserStore.I.removeBookmark(b),
                        ),
                      ),
                    if (UserStore.I.notes.isNotEmpty)
                      const Padding(
                        padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
                        child: Text('ملاحظاتي', style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    for (final e in UserStore.I.notes.entries)
                      ListTile(
                        leading: const Icon(Icons.sticky_note_2_outlined, color: kGoldDeep),
                        title: Text(q.ayahs[e.key].ref),
                        subtitle: Text(e.value, maxLines: 2, overflow: TextOverflow.ellipsis),
                        onTap: () => MushafScreen.open(context, q.ayahs[e.key].page, flashG: e.key),
                      ),
                    if (hl.isNotEmpty)
                      const Padding(
                        padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
                        child: Text('الآيات المظلّلة', style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    for (final g in hl)
                      ListTile(
                        leading: CircleAvatar(
                            radius: 10,
                            backgroundColor: kHighlightColors[UserStore.I.highlights[g]!.clamp(0, kHighlightColors.length - 1)]),
                        title: Text(q.ayahs[g].ref),
                        subtitle: Text(q.clean[g], maxLines: 1, overflow: TextOverflow.ellipsis),
                        onTap: () => MushafScreen.open(context, q.ayahs[g].page, flashG: g),
                        trailing: IconButton(
                          icon: const Icon(Icons.format_color_reset_rounded),
                          onPressed: () => UserStore.I.setHighlight(g, null),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
