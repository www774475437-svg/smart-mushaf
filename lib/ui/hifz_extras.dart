import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../data/quran.dart';
import '../data/surah_names.dart';
import '../services/store.dart';
import 'common.dart';
import 'tasmee.dart';

/// Choose a whole surah or a whole juz to recite from memory, page after page.
void showTasmeeRangeSheet(BuildContext context) {
  var bySurah = true;
  var surah = QuranData.I.surahOfPage(UserStore.I.lastPage);
  var juz = QuranData.I.juzOfPage(UserStore.I.lastPage);
  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) {
        final q = QuranData.I;
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('تسميع سورة أو جزء كامل',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 14),
              Center(
                child: Pills<bool>(
                  values: const [true, false],
                  selected: bySurah,
                  label: (v) => v ? 'سورة' : 'جزء',
                  onChanged: (v) => set(() => bySurah = v),
                ),
              ),
              const SizedBox(height: 10),
              Center(
                child: bySurah
                    ? DropdownButton<int>(
                        value: surah,
                        items: [for (var i = 1; i <= 114; i++) DropdownMenuItem(value: i, child: Text('${ar(i)}. ${surahName(i)}'))],
                        onChanged: (v) => set(() => surah = v ?? surah),
                      )
                    : DropdownButton<int>(
                        value: juz,
                        items: [for (var j = 1; j <= 30; j++) DropdownMenuItem(value: j, child: Text('الجزء ${ar(j)}'))],
                        onChanged: (v) => set(() => juz = v ?? juz),
                      ),
              ),
              const SizedBox(height: 6),
              const Text('تبدأ من أول آية، وتنتقل الصفحات وحدها حتى آخر آية، ثم يظهر لك مجموع الأخطاء.',
                  textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 13, height: 1.7)),
              const SizedBox(height: 14),
              FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54), backgroundColor: kEmerald),
                onPressed: () {
                  final from = bySurah ? q.surahStart[surah] : q.juzStartG[juz];
                  final to = bySurah ? q.surahEndG(surah) : (juz < 30 ? q.juzStartG[juz + 1] - 1 : q.ayahs.length - 1);
                  Navigator.pop(ctx);
                  Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => TasmeeScreen(
                          page: q.ayahs[from].page,
                          fromG: from,
                          toG: to,
                          rangeName: bySurah ? 'سورة ${surahName(surah)}' : 'الجزء ${ar(juz)}')));
                },
                icon: const Icon(Icons.mic_rounded),
                label: const Text('ابدأ التسميع'),
              ),
            ],
          ),
        );
      },
    ),
  );
}

class _Badge {
  final String name, how;
  final IconData icon;
  final int have, need;
  const _Badge(this.name, this.how, this.icon, this.have, this.need);
  bool get done => have >= need;
}

/// Goals and badges, counted from what the user really did in the app.
class AchievementsScreen extends StatelessWidget {
  const AchievementsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('الأهداف والأوسمة')),
      body: ListenableBuilder(
        listenable: UserStore.I,
        builder: (context, _) {
          final st = UserStore.I;
          final strong = st.pageStatus.values.where((v) => v == 1).length;
          final read = st.dayPages.values.fold<int>(0, (a, b) => a + b);
          var qr = 0, tp = 0;
          for (final v in st.dayStats.values) {
            qr += v[0];
            tp += v[2];
          }
          final groups = <String, List<_Badge>>{
            'المداومة': [
              _Badge('ثلاثة أيام متتالية', 'اقرأ ثلاثة أيام بلا انقطاع', Icons.local_fire_department_rounded, st.streak, 3),
              _Badge('أسبوع متصل', 'سبعة أيام بلا انقطاع', Icons.local_fire_department_rounded, st.streak, 7),
              _Badge('شهر متصل', 'ثلاثون يومًا بلا انقطاع', Icons.local_fire_department_rounded, st.streak, 30),
            ],
            'القراءة': [
              _Badge('جزء كامل', 'اقرأ عشرين صفحة', Icons.menu_book_rounded, read, 20),
              _Badge('مئة صفحة', 'اقرأ مئة صفحة', Icons.menu_book_rounded, read, 100),
              _Badge('ختمة', 'اقرأ ست مئة وأربع صفحات', Icons.auto_stories_rounded, read, 604),
            ],
            'الحفظ والتسميع': [
              _Badge('أول صفحة متقنة', 'سمِّع صفحة بلا أخطاء', Icons.verified_rounded, strong, 1),
              _Badge('جزء متقن', 'عشرون صفحة بلا أخطاء', Icons.verified_rounded, strong, 20),
              _Badge('خمسة أجزاء', 'مئة صفحة بلا أخطاء', Icons.workspace_premium_rounded, strong, 100),
              _Badge('حافظ', 'المصحف كله بلا أخطاء', Icons.workspace_premium_rounded, strong, 604),
              _Badge('خمسون تسميعًا', 'سمِّع خمسين صفحة', Icons.mic_rounded, tp, 50),
            ],
            'الاختبارات': [
              _Badge('خمسون جوابًا صحيحًا', 'في أي اختبار', Icons.quiz_rounded, qr, 50),
              _Badge('خمس مئة جواب صحيح', 'في أي اختبار', Icons.quiz_rounded, qr, 500),
              _Badge('بلا أخطاء', 'أجب عن كل «أسئلة أخطائي»', Icons.task_alt_rounded, st.mistakes.isEmpty && qr > 0 ? 1 : 0, 1),
            ],
          };
          final all = groups.values.expand((e) => e).toList();
          return ListView(
            padding: const EdgeInsets.only(bottom: 30),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 4),
                child: Text('نلت ${ar(all.where((b) => b.done).length)} من ${ar(all.length)} وسامًا',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ),
              for (final e in groups.entries)
                GroupCard(title: e.key, children: [
                  for (final b in e.value)
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: b.done ? kGold.withValues(alpha: 0.25) : Colors.grey.withValues(alpha: 0.15),
                        child: Icon(b.icon, color: b.done ? kGoldDeep : Colors.grey),
                      ),
                      title: Text(b.name, style: TextStyle(fontWeight: FontWeight.w700, color: b.done ? null : cs.onSurface.withValues(alpha: 0.7))),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(b.how, style: const TextStyle(fontSize: 12.5)),
                          const SizedBox(height: 5),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                                value: (b.have / b.need).clamp(0.0, 1.0),
                                minHeight: 5,
                                color: b.done ? kGoldDeep : kEmerald,
                                backgroundColor: Colors.grey.withValues(alpha: 0.2)),
                          ),
                        ],
                      ),
                      trailing: b.done
                          ? const Icon(Icons.check_circle_rounded, color: kGoldDeep)
                          : Text('${ar(b.have.clamp(0, b.need))}/${ar(b.need)}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    ),
                ]),
            ],
          );
        },
      ),
    );
  }
}

/// A copy of the user's data kept outside the phone, and putting it back.
class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});
  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _share() async {
    final text = UserStore.I.exportJson();
    try {
      final d = DateTime.now();
      await Share.shareXFiles([
        XFile.fromData(Uint8List.fromList(utf8.encode(text)),
            name: 'smart-mushaf-${d.year}-${d.month}-${d.day}.json', mimeType: 'application/json')
      ], text: 'نسخة احتياطية من المصحف الذكي');
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) toast(context, 'نُسخت النسخة الاحتياطية، ألصقها في مكان تحفظه');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('النسخ الاحتياطي')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 30),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 16, 24, 4),
            child: Text(
                'تحفظ النسخة: العلامات والتمييز والملاحظات، وخريطة الحفظ والأخطاء والمراجعة، والختمة وخطة الحفظ والإحصاءات.',
                style: TextStyle(height: 1.8)),
          ),
          GroupCard(title: 'حفظ نسخة', children: [
            GroupTile(
                icon: Icons.ios_share_rounded,
                color: kEmerald,
                title: 'حفظ ملف النسخة أو إرساله',
                subtitle: 'احفظه في ملفاتك أو أرسله إلى نفسك',
                onTap: _share),
            GroupTile(
                icon: Icons.copy_rounded,
                color: const Color(0xFF1565C0),
                title: 'نسخ النسخة نصًّا',
                onTap: () async {
                  await Clipboard.setData(ClipboardData(text: UserStore.I.exportJson()));
                  if (context.mounted) toast(context, 'نُسخت النسخة الاحتياطية');
                }),
          ]),
          GroupCard(title: 'استرجاع نسخة', children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
              child: TextField(
                controller: _c,
                maxLines: 4,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(
                    hintText: 'افتح ملف النسخة وانسخ ما فيه ثم ألصقه هنا', border: OutlineInputBorder()),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final d = await Clipboard.getData('text/plain');
                        if (d?.text != null) _c.text = d!.text!;
                      },
                      icon: const Icon(Icons.paste_rounded),
                      label: const Text('لصق'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: kEmerald),
                      onPressed: () async {
                        if (_c.text.trim().isEmpty) return;
                        final ok = await UserStore.I.importJson(_c.text);
                        if (!context.mounted) return;
                        toast(context, ok ? 'استُرجعت بياناتك' : 'هذا النص ليس نسخة احتياطية من المصحف الذكي');
                        if (ok) _c.clear();
                      },
                      icon: const Icon(Icons.restore_rounded),
                      label: const Text('استرجاع'),
                    ),
                  ),
                ],
              ),
            ),
          ]),
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 6, 24, 0),
            child: Text('الاسترجاع يضع بيانات النسخة مكان بياناتك الحالية في هذا الجهاز.',
                style: TextStyle(color: Colors.red, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
