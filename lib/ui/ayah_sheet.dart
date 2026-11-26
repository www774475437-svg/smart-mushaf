import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../data/quran.dart';
import '../data/reciters.dart';
import '../data/surah_names.dart';
import '../data/tafsir.dart';
import '../services/audio.dart';
import '../services/settings.dart';
import '../services/store.dart';
import '../services/tts.dart';
import 'common.dart';
import 'memorize.dart';
import 'reciters_screen.dart';
import 'share_image.dart';

Future<void> showAyahSheet(BuildContext context, int g) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => AyahSheet(g: g),
  );
}

class AyahSheet extends StatefulWidget {
  final int g;
  const AyahSheet({super.key, required this.g});
  @override
  State<AyahSheet> createState() => _AyahSheetState();
}

class _AyahSheetState extends State<AyahSheet> {
  late int g;
  late String tafsirId;
  late Future<String> tf;
  Future<List<String>>? tr;

  @override
  void initState() {
    super.initState();
    g = widget.g;
    tafsirId = AppSettings.I.tafsirId;
    _load();
  }

  @override
  void dispose() {
    Tts.I.stop();
    super.dispose();
  }

  void _load() {
    tf = TafsirService.I.get(tafsirId, g);
    if (AppSettings.I.showTranslation) tr = QuranData.I.translation();
  }

  void _move(int d) {
    final n = g + d;
    if (n < 0 || n > 6235) return;
    Tts.I.stop();
    setState(() {
      g = n;
      _load();
    });
  }

  Ayah get ay => QuranData.I.ayahs[g];
  String get refText => '[سورة ${surahName(ay.s)}: ${ar(ay.a)}]';

  void _copy(String text, String msg) {
    Clipboard.setData(ClipboardData(text: text));
    toast(context, msg);
  }

  Future<void> _pickRange() async {
    final q = QuranData.I;
    final n = q.surahCount[ay.s];
    var from = ay.a;
    var to = n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text('تشغيل من آية إلى آية\nسورة ${surahName(ay.s)}', textAlign: TextAlign.center),
          content: Row(
            children: [
              const Text('من '),
              DropdownButton<int>(
                value: from,
                items: [for (var i = 1; i <= n; i++) DropdownMenuItem(value: i, child: Text(ar(i)))],
                onChanged: (v) => setD(() {
                  from = v ?? from;
                  if (to < from) to = from;
                }),
              ),
              const Spacer(),
              const Text('إلى '),
              DropdownButton<int>(
                value: to,
                items: [for (var i = from; i <= n; i++) DropdownMenuItem(value: i, child: Text(ar(i)))],
                onChanged: (v) => setD(() => to = v ?? to),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تشغيل')),
          ],
        ),
      ),
    );
    if (ok == true) {
      AudioCtl.I.playRange(q.gOf(ay.s, from), q.gOf(ay.s, to));
      if (mounted) Navigator.pop(context);
    }
  }

  void _highlight() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('تظليل الآية', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (var i = 0; i < kHighlightColors.length; i++)
                    GestureDetector(
                      onTap: () {
                        UserStore.I.setHighlight(g, i);
                        Navigator.pop(ctx);
                      },
                      child: CircleAvatar(radius: 22, backgroundColor: kHighlightColors[i]),
                    ),
                  GestureDetector(
                    onTap: () {
                      UserStore.I.setHighlight(g, null);
                      Navigator.pop(ctx);
                    },
                    child: const CircleAvatar(radius: 22, child: Icon(Icons.format_color_reset_rounded)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = isDark(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.96,
      expand: false,
      builder: (ctx, sc) => Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        ),
        child: ListView(
          controller: sc,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 30),
          children: [
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(3)),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                IconButton(onPressed: () => _move(-1), icon: const Icon(Icons.chevron_right_rounded), tooltip: 'الآية السابقة'),
                Expanded(
                  child: Text('سورة ${surahName(ay.s)} • الآية ${ar(ay.a)}',
                      textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                ),
                IconButton(onPressed: () => _move(1), icon: const Icon(Icons.chevron_left_rounded), tooltip: 'الآية التالية'),
              ],
            ),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: kGold.withValues(alpha: dark ? 0.08 : 0.10),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: kGold.withValues(alpha: 0.4)),
              ),
              child: Text('${ay.text} ﴿${ar(ay.a)}﴾',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontFamily: 'AmiriQuran', fontSize: 22, height: 2)),
            ),
            const SizedBox(height: 14),
            ListenableBuilder(
              listenable: UserStore.I,
              builder: (context, _) {
                final marked = UserStore.I.isAyahBookmarked(g);
                return Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 10,
                  children: [
                    _Act(Icons.play_arrow_rounded, 'تشغيل من هنا', () {
                      AudioCtl.I.playRange(g, QuranData.I.surahEndG(ay.s), continueAfter: true);
                      Navigator.pop(context);
                    }),
                    _Act(Icons.repeat_one_rounded, 'تشغيل الآية', () {
                      AudioCtl.I.playRange(g, g);
                    }),
                    _Act(Icons.linear_scale_rounded, 'من آية إلى آية', _pickRange),
                    _Act(marked ? Icons.bookmark_rounded : Icons.bookmark_add_outlined, marked ? 'إزالة العلامة' : 'علامة', () {
                      UserStore.I.toggleAyahBookmark(g, ay.page);
                      toast(context, marked ? 'أُزيلت العلامة' : 'حُفظت الآية في العلامات');
                    }),
                    _Act(Icons.format_color_fill_rounded, 'تظليل', _highlight),
                    _Act(Icons.copy_rounded, 'نسخ', () => _copy('﴿${ay.text}﴾ $refText', 'نُسخت الآية')),
                    _Act(Icons.content_copy_rounded, 'نسخ بلا تشكيل',
                        () => _copy('﴿${QuranData.I.clean[g]}﴾ [سورة ${surahName(ay.s)}: ${ay.a}]', 'نُسخت الآية بلا تشكيل')),
                    _Act(Icons.share_rounded, 'مشاركة', () => Share.share('﴿${ay.text}﴾ $refText')),
                    _Act(Icons.image_outlined, 'صورة', () {
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => ShareImageScreen(g: g)));
                    }),
                    _Act(Icons.record_voice_over_rounded, 'تسميع', () {
                      Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => VoiceTestScreen(fromG: g, toG: QuranData.I.surahEndG(ay.s))));
                    }),
                  ],
                );
              },
            ),
            const SizedBox(height: 14),
            ListenableBuilder(
              listenable: Reciters.I,
              builder: (context, _) => Card(
                elevation: 0,
                color: cs.primary.withValues(alpha: 0.07),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: ListTile(
                  leading: const IconSquare(Icons.mic_rounded, kEmerald),
                  title: Text('القارئ: ${Reciters.I.current.name}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: const Text('اضغط للتغيير • اضغط مطولاً لإضافة قارئ'),
                  trailing: const Icon(Icons.chevron_left_rounded),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RecitersScreen(pick: true))),
                  onLongPress: () =>
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AddReciterScreen())),
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Text('التفسير', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 8),
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
                          setState(() {
                            tafsirId = t.id;
                            AppSettings.I.tafsirId = t.id;
                            _load();
                          });
                        },
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            FutureBuilder<String>(
              future: tf,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snap.hasError) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        const Text('هذا التفسير يحتاج إلى الإنترنت، أو حمّله من الإعدادات ليعمل بدون إنترنت.',
                            textAlign: TextAlign.center),
                        TextButton(onPressed: () => setState(_load), child: const Text('أعد المحاولة')),
                      ],
                    ),
                  );
                }
                final text = snap.data ?? '';
                final name = TafsirService.I.byId(tafsirId).name;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: SelectableText(text, style: const TextStyle(fontSize: 16.5, height: 1.85)),
                    ),
                    const SizedBox(height: 8),
                    ListenableBuilder(
                      listenable: Tts.I,
                      builder: (context, _) {
                        final key = '$tafsirId:$g';
                        final speaking = Tts.I.speaking && Tts.I.key == key;
                        return Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _Act(speaking ? Icons.stop_rounded : Icons.volume_up_rounded, speaking ? 'إيقاف' : 'استمع للتفسير',
                                () {
                              if (speaking) {
                                Tts.I.stop();
                              } else {
                                Tts.I.speak(text, key: key);
                              }
                            }),
                            _Act(Icons.copy_rounded, 'نسخ التفسير', () {
                              _copy('$name ${refText}:\n${stripTashkeel(text)}', 'نُسخ التفسير بلا تشكيل');
                            }),
                            _Act(Icons.share_rounded, 'مشاركة التفسير', () {
                              Share.share('﴿${QuranData.I.clean[g]}﴾ $refText\n\n$name:\n${stripTashkeel(text)}');
                            }),
                            _Act(Icons.image_outlined, 'صورة مع التفسير', () {
                              Navigator.of(context).push(MaterialPageRoute(
                                  builder: (_) => ShareImageScreen(g: g, tafsir: stripTashkeel(text))));
                            }),
                          ],
                        );
                      },
                    ),
                  ],
                );
              },
            ),
            if (tr != null) ...[
              const SizedBox(height: 14),
              const Text('الترجمة (English)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 6),
              FutureBuilder<List<String>>(
                future: tr,
                builder: (context, snap) => snap.hasData
                    ? Directionality(
                        textDirection: TextDirection.ltr,
                        child: Text(snap.data![g], style: const TextStyle(fontSize: 15, height: 1.6)),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Act extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _Act(this.icon, this.label, this.onTap);
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 84,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: BoxDecoration(
          color: cs.primary.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: cs.primary),
            const SizedBox(height: 4),
            Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
