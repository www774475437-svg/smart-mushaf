import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../services/store.dart';
import 'common.dart';

/// What was done in the last seven days.
class WeeklyReportScreen extends StatelessWidget {
  const WeeklyReportScreen({super.key});

  static const _days = ['الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('التقرير الأسبوعي')),
      body: ListenableBuilder(
        listenable: UserStore.I,
        builder: (context, _) {
          final st = UserStore.I;
          final now = DateTime.now();
          final days = [for (var i = 6; i >= 0; i--) DateTime(now.year, now.month, now.day - i)];
          final pages = [for (final d in days) st.dayPages[UserStore.dayKey(d)] ?? 0];
          final total = pages.fold<int>(0, (a, b) => a + b);
          final active = pages.where((p) => p > 0).length;
          final top = pages.fold<int>(1, (a, b) => b > a ? b : a);
          var qr = 0, qt = 0, tp = 0, tw = 0;
          for (final d in days) {
            final s = st.statsOf(d);
            qr += s[0];
            qt += s[1];
            tp += s[2];
            tw += s[3];
          }
          final weekAgo = now.subtract(const Duration(days: 7)).millisecondsSinceEpoch;
          final newMistakes = st.mistakes.where((m) => m.time >= weekAgo).length;
          final strong = st.pageStatus.values.where((v) => v == 1).length;
          final weak = st.pageStatus.values.where((v) => v != 1).length;

          final text = StringBuffer()
            ..writeln('تقريري الأسبوعي في «المصحف الذكي»')
            ..writeln('قرأت ${ar(total)} صفحة في ${ar(active)} أيام')
            ..writeln('الأيام المتتالية: ${ar(st.streak)}')
            ..writeln('سمّعت ${ar(tp)} صفحة')
            ..writeln('الاختبارات: ${ar(qr)} صحيحة من ${ar(qt)}')
            ..writeln('السور المحفوظة: ${ar(st.memorized.length)} • الصفحات المتقنة: ${ar(strong)}');

          Widget row(IconData i, Color c, String t, String v) => GroupTile(
              icon: i, color: c, title: t, trailing: Text(v, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)));

          return ListView(
            padding: const EdgeInsets.only(bottom: 30),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
                  decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(22)),
                  child: Column(
                    children: [
                      Text('قرأت ${ar(total)} صفحة هذا الأسبوع', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 14),
                      SizedBox(
                        height: 150,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            for (var i = 0; i < 7; i++)
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    Text(ar(pages[i]), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                                    const SizedBox(height: 4),
                                    Container(
                                      height: 4 + 96 * pages[i] / top,
                                      margin: const EdgeInsets.symmetric(horizontal: 7),
                                      decoration: BoxDecoration(
                                        color: pages[i] > 0 ? kEmerald : Colors.grey.withValues(alpha: 0.3),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(_days[days[i].weekday - 1],
                                        maxLines: 1,
                                        style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: i == 6 ? FontWeight.w700 : FontWeight.w500,
                                            color: i == 6 ? kGoldDeep : null)),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              GroupCard(title: 'القراءة', children: [
                row(Icons.menu_book_rounded, kEmerald, 'صفحات الأسبوع', ar(total)),
                row(Icons.event_available_rounded, const Color(0xFF1565C0), 'أيام قرأت فيها', '${ar(active)} من ${ar(7)}'),
                row(Icons.local_fire_department_rounded, const Color(0xFFE65100), 'أيام متتالية', ar(st.streak)),
              ]),
              GroupCard(title: 'الحفظ والتسميع', children: [
                row(Icons.mic_rounded, const Color(0xFFC62828), 'صفحات سمّعتها', ar(tp)),
                row(Icons.error_outline_rounded, Colors.red, 'كلمات أخطأت فيها', ar(tw)),
                row(Icons.bookmark_remove_rounded, const Color(0xFF6D4C41), 'آيات جديدة في «أخطائي»', ar(newMistakes)),
                row(Icons.quiz_rounded, const Color(0xFF6A4C93), 'أسئلة الاختبارات', qt == 0 ? '—' : '${ar(qr)} من ${ar(qt)}'),
              ]),
              GroupCard(title: 'المجموع', children: [
                row(Icons.verified_rounded, const Color(0xFF2E7D32), 'سور محفوظة', ar(st.memorized.length)),
                row(Icons.grid_view_rounded, const Color(0xFF43A047), 'صفحات متقنة', ar(strong)),
                row(Icons.refresh_rounded, kGoldDeep, 'صفحات تحتاج مراجعة', ar(weak)),
              ]),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                  onPressed: () => Share.share(text.toString()),
                  icon: const Icon(Icons.share_rounded),
                  label: const Text('مشاركة التقرير'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
