import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../data/quran.dart';
import '../data/surah_names.dart';
import '../services/audio.dart';
import '../services/store.dart';
import 'common.dart';
import 'reader.dart';

/// Matches the recited words to the expected words (longest common subsequence).
List<bool> matchWords(List<String> expected, List<String> heard) {
  final n = expected.length, m = heard.length;
  final dp = List.generate(n + 1, (_) => List.filled(m + 1, 0));
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      dp[i][j] = expected[i] == heard[j] ? dp[i + 1][j + 1] + 1 : (dp[i + 1][j] > dp[i][j + 1] ? dp[i + 1][j] : dp[i][j + 1]);
    }
  }
  final out = List.filled(n, false);
  var i = 0, j = 0;
  while (i < n && j < m) {
    if (expected[i] == heard[j]) {
      out[i] = true;
      i++;
      j++;
    } else if (dp[i + 1][j] >= dp[i][j + 1]) {
      i++;
    } else {
      j++;
    }
  }
  return out;
}

class MemorizeScreen extends StatefulWidget {
  const MemorizeScreen({super.key});
  @override
  State<MemorizeScreen> createState() => _MemorizeScreenState();
}

class _MemorizeScreenState extends State<MemorizeScreen> {
  int s = 1, from = 1, to = 7;

  void _setSurah(int v) {
    setState(() {
      s = v;
      from = 1;
      to = QuranData.I.surahCount[v];
    });
  }

  @override
  Widget build(BuildContext context) {
    final q = QuranData.I;
    final n = q.surahCount[s];
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('الحفظ والتسميع'),
          bottom: const TabBar(tabs: [
            Tab(text: 'التسميع بالصوت'),
            Tab(text: 'اختبار الإخفاء'),
            Tab(text: 'أخطائي'),
          ]),
        ),
        body: TabBarView(
          children: [
            _withPicker(n, (fromG, toG) => _StartCard(
                  icon: Icons.mic_rounded,
                  title: 'سمّع حفظك بصوتك',
                  text: 'اقرأ الآيات من حفظك، والتطبيق يُظهر الكلمات الصحيحة بالأخضر، وينبّهك على الكلمات التي أخطأت فيها أو نسيتها، ويحفظها في «أخطائي» لتراجعها.',
                  button: 'ابدأ التسميع',
                  onTap: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => VoiceTestScreen(fromG: fromG, toG: toG))),
                )),
            _withPicker(n, (fromG, toG) => _StartCard(
                  icon: Icons.visibility_off_rounded,
                  title: 'اختبار الإخفاء',
                  text: 'تُخفى كلمات الآيات، فتقرأها من حفظك ثم تضغط على الكلمة لتتأكد. ويمكنك تسجيل الآية التي أخطأت فيها.',
                  button: 'ابدأ الاختبار',
                  onTap: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => HideTestScreen(fromG: fromG, toG: toG))),
                )),
            const _MistakesTab(),
          ],
        ),
      ),
    );
  }

  Widget _withPicker(int n, Widget Function(int fromG, int toG) child) {
    final q = QuranData.I;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        GroupCard(children: [
          ListTile(
            leading: const IconSquare(Icons.menu_book_rounded, kEmerald),
            title: const Text('السورة'),
            trailing: DropdownButton<int>(
              value: s,
              underline: const SizedBox.shrink(),
              items: [for (var i = 1; i <= 114; i++) DropdownMenuItem(value: i, child: Text('${ar(i)}. ${surahName(i)}'))],
              onChanged: (v) => _setSurah(v ?? s),
            ),
          ),
          ListTile(
            leading: const IconSquare(Icons.first_page_rounded, kGoldDeep),
            title: const Text('من الآية'),
            trailing: DropdownButton<int>(
              value: from,
              underline: const SizedBox.shrink(),
              items: [for (var i = 1; i <= n; i++) DropdownMenuItem(value: i, child: Text(ar(i)))],
              onChanged: (v) => setState(() {
                from = v ?? from;
                if (to < from) to = from;
              }),
            ),
          ),
          ListTile(
            leading: const IconSquare(Icons.last_page_rounded, kGoldDeep),
            title: const Text('إلى الآية'),
            trailing: DropdownButton<int>(
              value: to,
              underline: const SizedBox.shrink(),
              items: [for (var i = from; i <= n; i++) DropdownMenuItem(value: i, child: Text(ar(i)))],
              onChanged: (v) => setState(() => to = v ?? to),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        child(q.gOf(s, from), q.gOf(s, to)),
        const SizedBox(height: 8),
        ListenableBuilder(
          listenable: UserStore.I,
          builder: (context, _) {
            final mem = UserStore.I.memorized.contains(s);
            return GroupCard(children: [
              SwitchListTile(
                secondary: const IconSquare(Icons.verified_rounded, Color(0xFF2E7D32)),
                title: Text('أتممت حفظ سورة ${surahName(s)}'),
                subtitle: Text('السور المحفوظة: ${ar(UserStore.I.memorized.length)} من ${ar(114)}'),
                value: mem,
                onChanged: (_) => UserStore.I.toggleMemorized(s),
              ),
            ]);
          },
        ),
      ],
    );
  }
}

class _StartCard extends StatelessWidget {
  final IconData icon;
  final String title, text, button;
  final VoidCallback onTap;
  const _StartCard({required this.icon, required this.title, required this.text, required this.button, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [kEmeraldDark, kEmerald]),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, color: kGold, size: 28),
            const SizedBox(width: 10),
            Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 10),
          Text(text, style: const TextStyle(color: Colors.white70, height: 1.7)),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: onTap,
            style: FilledButton.styleFrom(
                backgroundColor: kGold, foregroundColor: Colors.black, minimumSize: const Size.fromHeight(48)),
            child: Text(button, style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

class _MistakesTab extends StatelessWidget {
  const _MistakesTab();
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: UserStore.I,
      builder: (context, _) {
        final list = UserStore.I.mistakes;
        final q = QuranData.I;
        if (list.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(30),
              child: Text('لا توجد أخطاء محفوظة.\nالآيات التي تخطئ فيها في التسميع أو الاختبار تظهر هنا لتراجعها.',
                  textAlign: TextAlign.center, style: TextStyle(height: 1.8)),
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => VoiceTestScreen(fromG: 0, toG: 0, list: list.map((m) => m.g).toList()))),
                    icon: const Icon(Icons.mic_rounded),
                    label: const Text('راجع أخطائي بالتسميع'),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (c) => AlertDialog(
                        content: const Text('مسح كل الأخطاء؟'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('لا')),
                          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('نعم')),
                        ],
                      ),
                    );
                    if (ok == true) UserStore.I.clearMistakes();
                  },
                  child: const Text('مسح الكل'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final m in list)
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: ListTile(
                  title: Text(q.ayahs[m.g].text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontFamily: 'AmiriQuran', fontSize: 17, height: 1.8)),
                  subtitle: Text(
                      '${q.ayahs[m.g].ref} • أخطأت ${ar(m.count)} ${m.count == 1 ? 'مرة' : 'مرات'}'
                      '${m.missing.isEmpty ? '' : '\nكلمات: ${m.missing.take(8).join('، ')}'}',
                      style: const TextStyle(height: 1.6)),
                  onTap: () => MushafScreen.open(context, q.ayahs[m.g].page, flashG: m.g),
                  trailing: IconButton(
                    icon: const Icon(Icons.check_rounded, color: Color(0xFF2E7D32)),
                    tooltip: 'أتقنتها',
                    onPressed: () => UserStore.I.removeMistake(m.g),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Recite from memory; speech recognition checks each word.
class VoiceTestScreen extends StatefulWidget {
  final int fromG, toG;
  final List<int>? list;
  const VoiceTestScreen({super.key, required this.fromG, required this.toG, this.list});
  @override
  State<VoiceTestScreen> createState() => _VoiceTestScreenState();
}

class _VoiceTestScreenState extends State<VoiceTestScreen> {
  final SpeechToText _stt = SpeechToText();
  late List<int> items;
  int idx = 0;
  bool ready = false;
  bool listening = false;
  bool show = false;
  bool finished = false;
  String heard = '';
  List<bool> matched = [];
  String? err;
  int correct = 0, wrong = 0;

  @override
  void initState() {
    super.initState();
    items = widget.list ?? [for (var g = widget.fromG; g <= widget.toG; g++) g];
    if (items.isEmpty) items = [widget.fromG];
    _reset();
  }

  @override
  void dispose() {
    _stt.cancel();
    super.dispose();
  }

  int get g => items[idx];

  void _reset() {
    heard = '';
    finished = false;
    matched = List.filled(QuranData.I.cleanWords(g).length, false);
  }

  void _compare() {
    final exp = QuranData.I.cleanWords(g);
    final h = normalizeAr(heard).split(' ').where((w) => w.isNotEmpty).toList();
    matched = matchWords(exp, h);
  }

  Future<void> _listen() async {
    if (listening) {
      await _stt.stop();
      return;
    }
    if (!ready) {
      ready = await _stt.initialize(
        onError: (e) {
          if (mounted) setState(() => listening = false);
        },
        onStatus: (s) {
          if ((s == 'done' || s == 'notListening') && mounted) {
            setState(() => listening = false);
            if (heard.isNotEmpty && !finished) _finish();
          }
        },
      );
    }
    if (!ready) {
      setState(() => err = 'التعرّف على الصوت غير متاح. تأكد من السماح للتطبيق باستخدام الميكروفون، ومن وجود تطبيق Google في الجوال.');
      return;
    }
    await AudioCtl.I.stop();
    setState(() {
      err = null;
      listening = true;
      _reset();
    });
    await _stt.listen(
      onResult: (r) {
        if (!mounted) return;
        setState(() {
          heard = r.recognizedWords;
          _compare();
        });
        if (r.finalResult) _finish();
      },
      localeId: 'ar_SA',
      listenFor: const Duration(minutes: 2),
      pauseFor: const Duration(seconds: 4),
    );
  }

  void _finish() {
    if (finished) return;
    _compare();
    final exp = QuranData.I.cleanWords(g);
    final missing = <String>[for (var i = 0; i < exp.length; i++) if (!matched[i]) exp[i]];
    setState(() {
      finished = true;
      if (missing.isEmpty) {
        correct++;
      } else {
        wrong++;
      }
    });
    if (missing.isNotEmpty) UserStore.I.addMistake(g, missing);
  }

  void _go(int d) {
    final n = idx + d;
    if (n < 0 || n >= items.length) return;
    _stt.cancel();
    setState(() {
      idx = n;
      listening = false;
      show = false;
      _reset();
    });
  }

  @override
  Widget build(BuildContext context) {
    final q = QuranData.I;
    final ay = q.ayahs[g];
    final words = q.cleanWords(g);
    final display = ay.text.split(' ');
    final useDisplay = display.length == words.length;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text('التسميع • ${surahName(ay.s)}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Text('الآية ${ar(ay.a)}  (${ar(idx + 1)} من ${ar(items.length)})',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const Spacer(),
              Text('صحيحة ${ar(correct)} • خطأ ${ar(wrong)}', style: const TextStyle(fontSize: 13)),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: kGold.withValues(alpha: 0.5)),
            ),
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                for (var i = 0; i < words.length; i++)
                  _word(
                    useDisplay ? display[i] : words[i],
                    ok: i < matched.length && matched[i],
                    missed: finished && i < matched.length && !matched[i],
                    visible: show || finished || (i < matched.length && matched[i]),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton.icon(
                onPressed: () => setState(() => show = !show),
                icon: Icon(show ? Icons.visibility_off_rounded : Icons.visibility_rounded),
                label: Text(show ? 'إخفاء الآية' : 'إظهار الآية'),
              ),
              TextButton.icon(
                onPressed: () => AudioCtl.I.playRange(g, g),
                icon: const Icon(Icons.volume_up_rounded),
                label: const Text('استمع للآية'),
              ),
            ],
          ),
          if (err != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(err!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
            ),
          if (finished)
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (matched.every((e) => e) ? Colors.green : Colors.orange).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                matched.every((e) => e)
                    ? 'أحسنت! قرأت الآية كاملة صحيحة'
                    : 'الكلمات الحمراء لم تُقرأ أو قُرئت خطأ، وحُفظت في «أخطائي»',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          const SizedBox(height: 18),
          Center(
            child: GestureDetector(
              onTap: _listen,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: listening ? 96 : 84,
                height: listening ? 96 : 84,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(colors: listening ? [Colors.red.shade700, Colors.red.shade400] : [kEmeraldDark, kEmerald]),
                  boxShadow: [BoxShadow(color: (listening ? Colors.red : kEmerald).withValues(alpha: 0.4), blurRadius: 20)],
                ),
                child: Icon(listening ? Icons.stop_rounded : Icons.mic_rounded, color: Colors.white, size: 40),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(listening ? 'أسمعك… اقرأ الآية' : 'اضغط على الميكروفون واقرأ الآية من حفظك',
              textAlign: TextAlign.center),
          if (heard.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text('سمعت: $heard', textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: Colors.grey)),
            ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: idx > 0 ? () => _go(-1) : null,
                  icon: const Icon(Icons.chevron_right_rounded),
                  label: const Text('السابقة'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: idx < items.length - 1 ? () => _go(1) : null,
                  icon: const Icon(Icons.chevron_left_rounded),
                  label: const Text('التالية'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _word(String w, {required bool ok, required bool missed, required bool visible}) {
    final color = ok
        ? const Color(0xFF2E7D32)
        : missed
            ? Colors.red.shade700
            : null;
    if (!visible) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 10),
        width: (w.length * 9).clamp(24, 120).toDouble(),
        height: 10,
        decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(6)),
      );
    }
    return Text(w, style: TextStyle(fontFamily: 'AmiriQuran', fontSize: 23, height: 2, color: color));
  }
}

/// Hidden words test.
class HideTestScreen extends StatefulWidget {
  final int fromG, toG;
  const HideTestScreen({super.key, required this.fromG, required this.toG});
  @override
  State<HideTestScreen> createState() => _HideTestScreenState();
}

class _HideTestScreenState extends State<HideTestScreen> {
  double level = 0.5;
  final Set<String> revealed = {};

  bool _hidden(int g, int i) {
    if (level >= 1) return true;
    final h = ((g * 7919 + i * 104729) % 100) / 100.0;
    return h < level;
  }

  @override
  Widget build(BuildContext context) {
    final q = QuranData.I;
    return Scaffold(
      appBar: AppBar(title: const Text('اختبار الإخفاء')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Pills<double>(
              values: const [0.25, 0.5, 0.75, 1.0],
              selected: level,
              label: (v) => v == 1.0 ? 'إخفاء الكل' : 'إخفاء ${ar((v * 100).round())}٪',
              onChanged: (v) => setState(() {
                level = v;
                revealed.clear();
              }),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: widget.toG - widget.fromG + 1,
              itemBuilder: (_, k) {
                final g = widget.fromG + k;
                final ay = q.ayahs[g];
                final words = ay.text.split(' ');
                return Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (var i = 0; i < words.length; i++)
                              GestureDetector(
                                onTap: () => setState(() => revealed.add('$g:$i')),
                                child: _hidden(g, i) && !revealed.contains('$g:$i')
                                    ? Container(
                                        margin: const EdgeInsets.symmetric(vertical: 10),
                                        width: (words[i].length * 8).clamp(24, 110).toDouble(),
                                        height: 12,
                                        decoration: BoxDecoration(
                                          color: kGold.withValues(alpha: 0.45),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                      )
                                    : Text(words[i], style: const TextStyle(fontFamily: 'AmiriQuran', fontSize: 21, height: 2)),
                              ),
                            Text('﴿${ar(ay.a)}﴾', style: const TextStyle(fontFamily: 'AmiriQuran', fontSize: 18, color: kGoldDeep, height: 2)),
                          ],
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () => setState(() {
                                for (var i = 0; i < words.length; i++) {
                                  revealed.add('$g:$i');
                                }
                              }),
                              child: const Text('إظهار'),
                            ),
                            TextButton(
                              onPressed: () {
                                UserStore.I.addMistake(g, []);
                                toast(context, 'حُفظت في «أخطائي»');
                              },
                              child: const Text('أخطأت فيها', style: TextStyle(color: Colors.red)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
