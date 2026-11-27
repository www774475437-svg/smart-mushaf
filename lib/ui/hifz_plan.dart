import 'package:flutter/material.dart';

import '../data/quran.dart';
import '../data/surah_names.dart';
import '../services/notify.dart';
import '../services/store.dart';
import 'common.dart';
import 'reader.dart';
import 'tasmee.dart';

const Map<int, String> kPlanAmounts = {1: 'نصف صفحة', 2: 'صفحة', 4: 'صفحتان', 6: 'ثلاث صفحات'};

/// Words that describe today's portion of the memorization plan.
String planText() {
  final st = UserStore.I;
  if (st.planFinished) return 'أتممت الخطة، بارك الله لك';
  final from = st.planFromPage, to = st.planToPage;
  if (st.planPer == 1) return 'النصف ${st.planPos.isEven ? 'الأول' : 'الثاني'} من صفحة ${ar(from)}';
  return from == to ? 'صفحة ${ar(from)}' : 'من صفحة ${ar(from)} إلى صفحة ${ar(to)}';
}

class HifzPlanScreen extends StatefulWidget {
  const HifzPlanScreen({super.key});
  @override
  State<HifzPlanScreen> createState() => _HifzPlanScreenState();
}

class _HifzPlanScreenState extends State<HifzPlanScreen> {
  int surah = 78;
  int per = 2;

  String _time(int h, int m) {
    final pm = h >= 12;
    final hh = h % 12 == 0 ? 12 : h % 12;
    return '${ar(hh)}:${m < 10 ? ar(0) : ''}${ar(m)} ${pm ? 'مساءً' : 'صباحًا'}';
  }

  Future<void> _pickTime() async {
    final st = UserStore.I;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: st.planHour, minute: st.planMin));
    if (t == null) return;
    st.setPlanTime(t.hour, t.minute, st.planNotify);
    await Notify.syncPlan();
  }

  @override
  Widget build(BuildContext context) {
    final q = QuranData.I;
    return Scaffold(
      appBar: AppBar(title: const Text('خطة الحفظ اليومية')),
      body: ListenableBuilder(
        listenable: UserStore.I,
        builder: (context, _) {
          final st = UserStore.I;
          if (!st.hasPlan) {
            return ListView(
              padding: const EdgeInsets.only(bottom: 30),
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(24, 16, 24, 6),
                  child: Text('اختر من أين تبدأ وكم تحفظ كل يوم، والتطبيق يعطيك ورد كل يوم ويذكّرك به.',
                      style: TextStyle(height: 1.8)),
                ),
                GroupCard(title: 'بداية الحفظ', children: [
                  ListTile(
                    leading: const IconSquare(Icons.menu_book_rounded, kEmerald),
                    title: const Text('من سورة'),
                    subtitle: Text('صفحة ${ar(q.surahPage(surah))}'),
                    trailing: DropdownButton<int>(
                      value: surah,
                      underline: const SizedBox.shrink(),
                      items: [for (var i = 1; i <= 114; i++) DropdownMenuItem(value: i, child: Text('${ar(i)}. ${surahName(i)}'))],
                      onChanged: (v) => setState(() => surah = v ?? surah),
                    ),
                  ),
                ]),
                GroupCard(title: 'مقدار الحفظ كل يوم', children: [
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Pills<int>(
                        values: kPlanAmounts.keys.toList(),
                        selected: per,
                        label: (v) => kPlanAmounts[v]!,
                        onChanged: (v) => setState(() => per = v),
                      ),
                    ),
                  ),
                ]),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
                  child: Text(
                      'بهذا المقدار تتمّ من هذه السورة إلى آخر المصحف في ${ar((((605 - q.surahPage(surah)) * 2) / per).ceil())} يومًا تقريبًا.',
                      style: const TextStyle(color: Colors.grey, fontSize: 13)),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54), backgroundColor: kEmerald),
                    onPressed: () async {
                      st.setPlan(startPage: q.surahPage(surah), per: per);
                      await Notify.ask();
                      await Notify.syncPlan();
                    },
                    icon: const Icon(Icons.flag_rounded),
                    label: const Text('ابدأ الخطة'),
                  ),
                ),
              ],
            );
          }
          final done = st.planDoneToday;
          final page = st.planFromPage;
          final pct = (st.planPos / 1208).clamp(0.0, 1.0);
          return ListView(
            padding: const EdgeInsets.only(bottom: 30),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    gradient: const LinearGradient(colors: [Color(0xFF0B4436), kEmerald, Color(0xFF167A61)]),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(done ? 'أتممت ورد اليوم • ورد الغد' : 'ورد اليوم',
                          style: const TextStyle(color: Colors.white70, fontSize: 13)),
                      const SizedBox(height: 6),
                      Text(planText(), style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
                      if (!st.planFinished)
                        Text('سورة ${surahName(q.surahOfPage(page))} • الجزء ${ar(q.juzOfPage(page))}',
                            style: const TextStyle(color: kGold, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(value: pct, minHeight: 6, backgroundColor: Colors.white12, color: kGold),
                      ),
                    ],
                  ),
                ),
              ),
              if (!st.planFinished)
                GroupCard(children: [
                  GroupTile(
                      icon: Icons.auto_stories_rounded,
                      color: kEmerald,
                      title: 'افتح الورد في المصحف',
                      onTap: () => MushafScreen.open(context, page)),
                  GroupTile(
                      icon: Icons.mic_rounded,
                      color: const Color(0xFFC62828),
                      title: 'سمِّع الورد',
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TasmeeScreen(page: page)))),
                  if (!done)
                    GroupTile(
                        icon: Icons.check_circle_rounded,
                        color: const Color(0xFF2E7D32),
                        title: 'أتممت ورد اليوم',
                        subtitle: 'ينتقل الورد إلى ما بعده',
                        onTap: () async {
                          st.planDone();
                          await Notify.syncPlan();
                          if (context.mounted) toast(context, 'بارك الله فيك، سُجّل ورد اليوم');
                        }),
                ]),
              GroupCard(title: 'التذكير', children: [
                SwitchListTile(
                  secondary: const IconSquare(Icons.notifications_active_rounded, kGoldDeep),
                  title: const Text('إشعار يومي بالورد'),
                  subtitle: const Text('يعمل في تطبيق الأندرويد'),
                  value: st.planNotify,
                  onChanged: (v) async {
                    st.setPlanTime(st.planHour, st.planMin, v);
                    if (v) await Notify.ask();
                    await Notify.syncPlan();
                  },
                ),
                GroupTile(
                    icon: Icons.schedule_rounded,
                    color: const Color(0xFF1565C0),
                    title: 'وقت التذكير',
                    subtitle: _time(st.planHour, st.planMin),
                    onTap: _pickTime),
              ]),
              GroupCard(title: 'الخطة', children: [
                GroupTile(
                    icon: Icons.speed_rounded,
                    color: const Color(0xFF6A4C93),
                    title: 'المقدار اليومي',
                    subtitle: kPlanAmounts[st.planPer] ?? ''),
                GroupTile(
                    icon: Icons.restart_alt_rounded,
                    color: Colors.red,
                    title: 'إلغاء الخطة وبدء خطة جديدة',
                    onTap: () async {
                      st.stopPlan();
                      await Notify.syncPlan();
                    }),
              ]),
            ],
          );
        },
      ),
    );
  }
}
