import 'package:flutter/material.dart';

import '../data/quran.dart';
import '../data/surah_names.dart';
import '../services/store.dart';
import 'common.dart';
import 'khatma.dart';
import 'prayer_screen.dart';
import 'tasmee.dart';
import 'reader.dart';
import 'reciters_screen.dart';
import 'search.dart';
import 'share_image.dart';
import 'smart_tafsir.dart';

class HomeScreen extends StatelessWidget {
  final ValueChanged<int> onTab;
  const HomeScreen({super.key, required this.onTab});

  @override
  Widget build(BuildContext context) {
    final dark = isDark(context);
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: UserStore.I,
          builder: (context, _) {
            final st = UserStore.I;
            final q = QuranData.I;
            final lp = st.lastPage;
            return ListView(
              padding: const EdgeInsets.only(bottom: 90),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.asset('assets/images/logo.png', width: 44, height: 44),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('المصحف الذكي', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                            Text('اقرأ • استمع • تدبّر • احفظ', style: TextStyle(fontSize: 12.5)),
                          ],
                        ),
                      ),
                      IconButton.filledTonal(
                        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SearchScreen())),
                        icon: const Icon(Icons.search_rounded),
                      ),
                    ],
                  ),
                ),
                // Continue reading
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(26),
                    onTap: () => MushafScreen.open(context, lp),
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(26),
                        gradient: const LinearGradient(
                          begin: Alignment.topRight,
                          end: Alignment.bottomLeft,
                          colors: [Color(0xFF0B4436), kEmerald, Color(0xFF167A61)],
                        ),
                        boxShadow: [BoxShadow(color: kEmerald.withValues(alpha: 0.35), blurRadius: 18, offset: const Offset(0, 8))],
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('متابعة القراءة', style: TextStyle(color: Colors.white70, fontSize: 13)),
                                const SizedBox(height: 6),
                                Text('سورة ${surahName(q.surahOfPage(lp))}',
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700, fontFamily: 'AmiriQuran', height: 1.6)),
                                Text('صفحة ${ar(lp)} • الجزء ${ar(q.juzOfPage(lp))}',
                                    style: const TextStyle(color: kGold, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 10),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: LinearProgressIndicator(
                                    value: lp / 604,
                                    minHeight: 6,
                                    backgroundColor: Colors.white12,
                                    color: kGold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 14),
                          Container(
                            width: 58,
                            height: 58,
                            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: kGold, width: 1.5)),
                            child: const Icon(Icons.auto_stories_rounded, color: kGold, size: 30),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (DateTime.now().weekday == DateTime.friday)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                    child: Material(
                      color: kGold.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(18),
                      child: ListTile(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                        leading: const Icon(Icons.wb_sunny_rounded, color: kGoldDeep),
                        title: const Text('يوم الجمعة', style: TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: const Text('اقرأ سورة الكهف'),
                        trailing: const Icon(Icons.chevron_left_rounded),
                        onTap: () => MushafScreen.open(context, q.surahPage(18)),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
                  child: Row(
                    children: [
                      _Stat(Icons.menu_book_rounded, ar(st.pagesToday), 'صفحة اليوم'),
                      const SizedBox(width: 8),
                      _Stat(Icons.local_fire_department_rounded, ar(st.streak), 'أيام متتالية'),
                      const SizedBox(width: 8),
                      _Stat(Icons.verified_rounded, ar(st.memorized.length), 'سورة محفوظة'),
                    ],
                  ),
                ),
                const _AyahOfDay(),
                if (st.hasKhatma)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                    child: _KhatmaMini(),
                  ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 14, 20, 8),
                  child: Text('الأقسام', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 3,
                    childAspectRatio: 0.98,
                    children: [
                      _Feature(Icons.menu_book_rounded, 'الفهرس', kEmerald, () => onTab(1)),
                      _Feature(Icons.mic_external_on_rounded, 'القرّاء', const Color(0xFF6A4C93),
                          () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RecitersScreen()))),
                      _Feature(Icons.lightbulb_rounded, 'التفسير الذكي', kGoldDeep,
                          () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SmartTafsirScreen()))),
                      _Feature(Icons.record_voice_over_rounded, 'الحفظ والتسميع', const Color(0xFF2E7D32), () => onTab(3)),
                      _Feature(Icons.event_available_rounded, 'الختمة', const Color(0xFF1565C0),
                          () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const KhatmaScreen()))),
                      _Feature(Icons.access_time_filled_rounded, 'أوقات الصلاة', const Color(0xFF6D4C41),
                          () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PrayerScreen()))),
                      _Feature(Icons.groups_rounded, 'مجلس الحفاظ', kEmeraldDark, () => onTab(2)),
                      _Feature(Icons.mic_rounded, 'سمِّع الصفحة', const Color(0xFFC62828),
                          () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TasmeeScreen(page: lp)))),
                      _Feature(Icons.search_rounded, 'البحث', const Color(0xFF00838F),
                          () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SearchScreen()))),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 14, 20, 8),
                  child: Text('سور تُقرأ كثيرًا', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
                SizedBox(
                  height: 48,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    children: [
                      for (final s in const [18, 36, 67, 56, 55, 32, 2, 112])
                        Padding(
                          padding: const EdgeInsetsDirectional.only(end: 8),
                          child: ActionChip(
                            label: Text('سورة ${surahName(s)}'),
                            onPressed: () => MushafScreen.open(context, q.surahPage(s)),
                          ),
                        ),
                    ],
                  ),
                ),
                if (st.bookmarks.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
                    child: Text('آخر العلامات', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                  for (final b in st.bookmarks.take(3))
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
                      child: Material(
                        color: dark ? const Color(0xFF131D1A) : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        child: ListTile(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          leading: const Icon(Icons.bookmark_rounded, color: kGold),
                          title: Text(b.g >= 0 ? q.ayahs[b.g].ref : 'صفحة ${ar(b.page)} • سورة ${surahName(q.surahOfPage(b.page))}'),
                          onTap: () => MushafScreen.open(context, b.page, flashG: b.g >= 0 ? b.g : null),
                        ),
                      ),
                    ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _KhatmaMini extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final st = UserStore.I;
    final day = st.khatmaToday;
    final done = st.khatmaDone.contains(day);
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(20),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        leading: IconSquare(done ? Icons.check_rounded : Icons.event_note_rounded, done ? const Color(0xFF2E7D32) : const Color(0xFF1565C0)),
        title: Text('ورد اليوم ${ar(day)} من ${ar(st.khatmaDays)}', style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text('من صفحة ${ar(st.khatmaFrom(day))} إلى ${ar(st.khatmaTo(day))}${done ? ' • تمّ' : ''}'),
        trailing: const Icon(Icons.chevron_left_rounded),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const KhatmaScreen())),
      ),
    );
  }
}

class _Feature extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _Feature(this.icon, this.label, this.color, this.onTap);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(5),
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(16)),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(height: 8),
              Text(label, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final IconData icon;
  final String value, label;
  const _Stat(this.icon, this.value, this.label);
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          children: [
            Icon(icon, color: kGoldDeep, size: 22),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            Text(label, style: const TextStyle(fontSize: 11.5)),
          ],
        ),
      ),
    );
  }
}

class _AyahOfDay extends StatelessWidget {
  const _AyahOfDay();

  static int pick() {
    final q = QuranData.I;
    final now = DateTime.now();
    final days = DateTime(now.year, now.month, now.day).difference(DateTime(2024, 1, 1)).inDays;
    var g = (days * 7919 + 13) % 6236;
    var tries = 0;
    while ((q.ayahs[g].text.length > 170 || q.ayahs[g].text.length < 40) && tries < 400) {
      g = (g + 97) % 6236;
      tries++;
    }
    return g;
  }

  @override
  Widget build(BuildContext context) {
    final q = QuranData.I;
    final g = pick();
    final ay = q.ayahs[g];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: () => MushafScreen.open(context, ay.page, flashG: g),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(Icons.wb_sunny_outlined, color: kGoldDeep),
                    const SizedBox(width: 8),
                    const Text('آية اليوم', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    const Spacer(),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.share_rounded, size: 20),
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ShareImageScreen(g: g))),
                    ),
                  ],
                ),
                Text('${ay.text} ${ayahMark(ay.a)}',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontFamily: quranFont(), fontSize: 21, height: 2)),
                const SizedBox(height: 4),
                Text('سورة ${surahName(ay.s)}', style: const TextStyle(color: kGoldDeep, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
