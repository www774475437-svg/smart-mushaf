import 'package:flutter/material.dart';

import '../data/quran.dart';
import '../data/surah_names.dart';
import '../services/store.dart';
import 'common.dart';
import 'hajuri.dart';
import 'hifz_plan.dart';
import 'khatma.dart';
import 'quiz.dart';
import 'report.dart';
import 'prayer_screen.dart';
import 'reciters_screen.dart';
import 'search.dart';
import 'smart_tafsir.dart';
import 'tasmee.dart';

/// Everything that is not on the home page, in tidy groups.
class MoreScreen extends StatelessWidget {
  final ValueChanged<int> onTab;
  const MoreScreen({super.key, required this.onTab});

  @override
  Widget build(BuildContext context) {
    void go(Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
    void tab(int i) {
      Navigator.pop(context);
      onTab(i);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('المزيد')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 30),
        children: [
          GroupCard(title: 'الحفظ', children: [
            GroupTile(
                icon: Icons.grid_view_rounded,
                color: const Color(0xFF2E7D32),
                title: 'خريطة الحفظ',
                subtitle: 'صفحات المصحف كلها ملوّنة بحسب حفظك',
                onTap: () => go(const HifzMapScreen())),
            GroupTile(
                icon: Icons.flag_rounded,
                color: const Color(0xFF1565C0),
                title: 'خطة الحفظ اليومية',
                subtitle: 'ورد كل يوم مع تذكير',
                onTap: () => go(const HifzPlanScreen())),
            GroupTile(
                icon: Icons.mic_rounded,
                color: const Color(0xFFC62828),
                title: 'سمِّع داخل المصحف',
                onTap: () => go(TasmeeScreen(page: UserStore.I.lastPage))),
            GroupTile(
                icon: Icons.hearing_rounded,
                color: const Color(0xFF00838F),
                title: 'القراءة بالمتابعة',
                subtitle: 'اقرأ بصوتك والتظليل يتبعك ويقلّب الصفحة',
                onTap: () => go(TasmeeScreen(page: UserStore.I.lastPage, follow: true))),
            GroupTile(icon: Icons.record_voice_over_rounded, color: kEmerald, title: 'الحفظ والتسميع والمراجعة', onTap: () => tab(3)),
            GroupTile(icon: Icons.groups_rounded, color: kEmeraldDark, title: 'مجلس الحفاظ', onTap: () => tab(2)),
          ]),
          GroupCard(title: 'الاختبارات والمتابعة', children: [
            GroupTile(
                icon: Icons.quiz_rounded,
                color: const Color(0xFF6A4C93),
                title: 'اختبار أكمل الآية',
                subtitle: 'اختر تكملة الآية أو الآية التي بعدها',
                onTap: () => go(const QuizScreen(kind: 0))),
            GroupTile(
                icon: Icons.compare_arrows_rounded,
                color: const Color(0xFF00838F),
                title: 'اختبار المتشابهات',
                subtitle: 'الآيات التي يشتبه بعضها ببعض',
                onTap: () => go(const QuizScreen(kind: 1))),
            GroupTile(
                icon: Icons.insights_rounded,
                color: kGoldDeep,
                title: 'التقرير الأسبوعي',
                subtitle: 'ما قرأته وسمّعته في سبعة أيام',
                onTap: () => go(const WeeklyReportScreen())),
          ]),
          GroupCard(title: 'القراءة والاستماع', children: [
            GroupTile(icon: Icons.mic_external_on_rounded, color: const Color(0xFF6A4C93), title: 'القرّاء', onTap: () => go(const RecitersScreen())),
            GroupTile(icon: Icons.event_available_rounded, color: const Color(0xFF1565C0), title: 'الختمة', onTap: () => go(const KhatmaScreen())),
            GroupTile(icon: Icons.search_rounded, color: const Color(0xFF00838F), title: 'البحث', onTap: () => go(const SearchScreen())),
          ]),
          GroupCard(title: 'التدبّر', children: [
            GroupTile(icon: Icons.lightbulb_rounded, color: kGoldDeep, title: 'التفسير الذكي', onTap: () => go(const SmartTafsirScreen())),
            GroupTile(
                icon: Icons.headphones_rounded,
                color: const Color(0xFF2E7D32),
                title: 'تفسير ابن كثير بصوت الحجوري',
                subtitle: 'دروس مسجَّلة مرتبة على السور',
                onTap: () => go(const HajuriTafsirScreen())),
            GroupTile(icon: Icons.history_edu_rounded, color: const Color(0xFF6D4C41), title: 'أسباب النزول', onTap: () => go(const AsbabScreen())),
          ]),
          GroupCard(title: 'العبادة', children: [
            GroupTile(icon: Icons.access_time_filled_rounded, color: const Color(0xFF6D4C41), title: 'أوقات الصلاة والقبلة', onTap: () => go(const PrayerScreen())),
          ]),
        ],
      ),
    );
  }
}

/// The whole mushaf as 604 small squares coloured by how well each page is memorized.
class HifzMapScreen extends StatelessWidget {
  const HifzMapScreen({super.key});

  static const colors = {1: Color(0xFF43A047), 2: Color(0xFFF2C037), 3: Color(0xFFE05252)};

  @override
  Widget build(BuildContext context) {
    final q = QuranData.I;
    return Scaffold(
      appBar: AppBar(title: const Text('خريطة الحفظ')),
      body: ListenableBuilder(
        listenable: UserStore.I,
        builder: (context, _) {
          final ps = UserStore.I.pageStatus;
          final g = ps.values.where((v) => v == 1).length;
          final y = ps.values.where((v) => v == 2).length;
          final r = ps.values.where((v) => v == 3).length;
          Widget legend(Color c, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 14, height: 14, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(4))),
                const SizedBox(width: 6),
                Text(t, style: const TextStyle(fontSize: 12.5)),
              ]);
          return ListView(
            padding: const EdgeInsets.all(14),
            children: [
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 14,
                runSpacing: 6,
                children: [
                  legend(colors[1]!, 'متقن ${ar(g)}'),
                  legend(colors[2]!, 'يحتاج مراجعة ${ar(y)}'),
                  legend(colors[3]!, 'فيه أخطاء ${ar(r)}'),
                  legend(Colors.grey.withValues(alpha: 0.25), 'لم يُسمَّع ${ar(604 - g - y - r)}'),
                ],
              ),
              const SizedBox(height: 6),
              const Text('اللون يتحدّث بعد كل تسميع للصفحة. اضغط على أي صفحة لتسمّعها.',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 12),
              for (var j = 1; j <= 30; j++) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
                  child: Text('الجزء ${ar(j)}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                ),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    for (var p = q.juzPage(j); p < (j < 30 ? q.juzPage(j + 1) : 605); p++)
                      GestureDetector(
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TasmeeScreen(page: p))),
                        onLongPress: () {
                          UserStore.I.setPageStatus(p, null);
                          toast(context, 'أُزيل لون الصفحة ${ar(p)}');
                        },
                        child: Tooltip(
                          message: 'صفحة $p • ${surahName(q.surahOfPage(p))}',
                          child: Container(
                            width: 26,
                            height: 26,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: colors[ps[p]] ?? Colors.grey.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text('$p',
                                style: TextStyle(fontSize: 8.5, color: ps[p] == null ? Colors.grey : Colors.white, fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
