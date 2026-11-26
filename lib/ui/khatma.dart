import 'package:flutter/material.dart';

import '../data/quran.dart';
import '../data/surah_names.dart';
import '../services/store.dart';
import 'common.dart';
import 'reader.dart';

class KhatmaScreen extends StatelessWidget {
  const KhatmaScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الختمة')),
      body: ListenableBuilder(
        listenable: UserStore.I,
        builder: (context, _) {
          final st = UserStore.I;
          if (!st.hasKhatma) return const _NewKhatma();
          final q = QuranData.I;
          final today = st.khatmaToday;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF0D3B66), Color(0xFF1565C0)]),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('ختمة في ${ar(st.khatmaDays)} يومًا • ${ar(st.pagesPerDay)} صفحة في اليوم',
                        style: const TextStyle(color: Colors.white70)),
                    const SizedBox(height: 8),
                    Text('ورد اليوم ${ar(today)}',
                        style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
                    Text(
                        'من صفحة ${ar(st.khatmaFrom(today))} (سورة ${surahName(q.surahOfPage(st.khatmaFrom(today)))}) إلى صفحة ${ar(st.khatmaTo(today))}',
                        style: const TextStyle(color: kGold, height: 1.7)),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: st.khatmaDone.length / st.khatmaDays,
                        minHeight: 8,
                        backgroundColor: Colors.white12,
                        color: kGold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text('أتممت ${ar(st.khatmaDone.length)} من ${ar(st.khatmaDays)} وردًا',
                        style: const TextStyle(color: Colors.white70, fontSize: 13)),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton(
                            style: FilledButton.styleFrom(backgroundColor: kGold, foregroundColor: Colors.black),
                            onPressed: () => MushafScreen.open(context, st.khatmaFrom(today)),
                            child: const Text('اقرأ ورد اليوم'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white54)),
                            onPressed: () => st.toggleKhatmaDay(today),
                            child: Text(st.khatmaDone.contains(today) ? 'تمّ ✓' : 'أتممت الورد'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text('الأيام', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var d = 1; d <= st.khatmaDays; d++)
                    GestureDetector(
                      onTap: () => MushafScreen.open(context, st.khatmaFrom(d)),
                      onLongPress: () => st.toggleKhatmaDay(d),
                      child: Container(
                        width: 48,
                        height: 48,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: st.khatmaDone.contains(d)
                              ? const Color(0xFF2E7D32)
                              : d == today
                                  ? kGold.withValues(alpha: 0.3)
                                  : Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: d == today ? kGold : Colors.grey.withValues(alpha: 0.3)),
                        ),
                        child: Text(ar(d),
                            style: TextStyle(
                                fontWeight: FontWeight.w700, color: st.khatmaDone.contains(d) ? Colors.white : null)),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              const Text('اضغط على اليوم لقراءته، واضغط مطولاً لتعليمه.', style: TextStyle(fontSize: 12.5)),
              const SizedBox(height: 20),
              TextButton.icon(
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (c) => AlertDialog(
                      content: const Text('إنهاء هذه الختمة والبدء من جديد؟'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('لا')),
                        TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('نعم')),
                      ],
                    ),
                  );
                  if (ok == true) st.stopKhatma();
                },
                icon: const Icon(Icons.restart_alt_rounded),
                label: const Text('ختمة جديدة'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _NewKhatma extends StatefulWidget {
  const _NewKhatma();
  @override
  State<_NewKhatma> createState() => _NewKhatmaState();
}

class _NewKhatmaState extends State<_NewKhatma> {
  int days = 30;
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Icon(Icons.event_available_rounded, size: 64, color: Color(0xFF1565C0)),
        const SizedBox(height: 10),
        const Text('ابدأ ختمة جديدة', textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        const Text('اختر عدد الأيام، ويقسم التطبيق المصحف إلى ورد يومي.', textAlign: TextAlign.center),
        const SizedBox(height: 20),
        Center(
          child: Pills<int>(
            values: const [3, 7, 10, 15, 20, 30, 40, 60, 90],
            selected: days,
            label: (d) => '${ar(d)} يومًا',
            onChanged: (d) => setState(() => days = d),
          ),
        ),
        const SizedBox(height: 16),
        Text('الورد اليومي: ${ar((604 / days).ceil())} صفحة تقريبًا', textAlign: TextAlign.center),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () => UserStore.I.startKhatma(days),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          child: const Text('ابدأ الختمة'),
        ),
      ],
    );
  }
}
