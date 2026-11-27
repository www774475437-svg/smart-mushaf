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
import 'settings_screen.dart';
import 'tasmee.dart';
import 'reciter_sheet.dart';
import 'reciters_screen.dart';
import 'share_image.dart';

const List<Color> kFasilColors = [Color(0xFFB3352E), Color(0xFFC9A227), Color(0xFF3F8F3A), Color(0xFF2F68C4)];
const List<String> kFasilNames = ['الأحمر', 'الأصفر', 'الأخضر', 'الأزرق'];

Color _sheetBg(BuildContext c) => isDark(c) ? const Color(0xFF0E1614) : const Color(0xFFF4F0E8);
Color _cardBg(BuildContext c) => isDark(c) ? const Color(0xFF17211E) : const Color(0xFFFFFCF7);

Future<void> showAyahSheet(BuildContext context, int g) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black26,
    builder: (_) => AyahSheet(g: g),
  );
}

class _Title extends StatelessWidget {
  final String t;
  const _Title(this.t);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(6, 18, 6, 10),
        child: Text(t, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
      );
}

/// A soft rounded card button used across the sheet.
class _Tile extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final EdgeInsets padding;
  const _Tile({required this.child, this.onTap, this.onLongPress, this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 16)});
  @override
  Widget build(BuildContext context) {
    return Material(
      color: _cardBg(context),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class AyahSheet extends StatefulWidget {
  final int g;
  const AyahSheet({super.key, required this.g});
  @override
  State<AyahSheet> createState() => _AyahSheetState();
}

class _AyahSheetState extends State<AyahSheet> {
  late int g;
  late Future<String> tf;

  @override
  void initState() {
    super.initState();
    g = widget.g;
    tf = TafsirService.I.get(AppSettings.I.tafsirId, g);
  }

  Ayah get ay => QuranData.I.ayahs[g];
  String get refText => '[سورة ${surahName(ay.s)}: ${ar(ay.a)}]';

  void _copy(String text, String msg) {
    Clipboard.setData(ClipboardData(text: text));
    toast(context, msg);
  }

  void _play(int toG, {bool cont = false}) {
    AudioCtl.I.playRange(g, toG, continueAfter: cont);
    Navigator.pop(context);
  }

  void _playTo() {
    final q = QuranData.I;
    final pageEnd = q.pageAyahs[ay.page].where((x) => q.ayahs[x].s == ay.s).fold<int>(g, (a, b) => b > a ? b : a);
    final surahEnd = q.surahEndG(ay.s);
    Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (ctx) => Scaffold(
        backgroundColor: _sheetBg(ctx),
        appBar: AppBar(backgroundColor: _sheetBg(ctx), title: const Text('تشغيل إلى')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              decoration: BoxDecoration(color: _cardBg(ctx), borderRadius: BorderRadius.circular(16)),
              child: Column(
                children: [
                  ListTile(
                    title: const Text('هذه الآية فقط'),
                    trailing: Text('${surahName(ay.s)}: ${ay.a}', style: const TextStyle(color: kGoldDeep)),
                    onTap: () {
                      Navigator.pop(ctx);
                      _play(g);
                    },
                  ),
                  const Divider(height: 1, indent: 16),
                  ListTile(
                    title: const Text('نهاية الصفحة'),
                    trailing: Text('الصفحة ${ay.page}', style: const TextStyle(color: kGoldDeep)),
                    onTap: () {
                      Navigator.pop(ctx);
                      _play(pageEnd);
                    },
                  ),
                  const Divider(height: 1, indent: 16),
                  ListTile(
                    title: const Text('نهاية السورة'),
                    trailing: Text(surahName(ay.s), style: const TextStyle(color: kGoldDeep)),
                    onTap: () {
                      Navigator.pop(ctx);
                      _play(surahEnd);
                    },
                  ),
                  const Divider(height: 1, indent: 16),
                  ListTile(
                    title: const Text('تشغيل مستمر'),
                    trailing: const Text('∞', style: TextStyle(color: kGoldDeep, fontSize: 22)),
                    onTap: () {
                      Navigator.pop(ctx);
                      _play(surahEnd, cont: true);
                    },
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(6, 18, 6, 8),
              child: Text('أو اختر الآية التي تقف عندها', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            Container(
              decoration: BoxDecoration(color: _cardBg(ctx), borderRadius: BorderRadius.circular(16)),
              child: Column(
                children: [
                  for (var x = g; x <= surahEnd && x < g + 300; x++) ...[
                    if (x > g) const Divider(height: 1, indent: 16),
                    ListTile(
                      title: Text('${surahName(ay.s)}: ${q.ayahs[x].a}', style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(q.ayahs[x].text,
                          maxLines: 1,
                          overflow: TextOverflow.fade,
                          softWrap: false,
                          style: TextStyle(fontFamily: quranFont(), fontSize: 18, color: kGoldDeep, height: 1.9)),
                      trailing: Text('${q.ayahs[x].page}', style: const TextStyle(color: Colors.grey)),
                      onTap: () {
                        Navigator.pop(ctx);
                        _play(x);
                      },
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    ));
  }

  void _openLibrary() {
    Navigator.of(context).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => LibraryScreen(g: g)));
  }

  Future<void> _editNote() async {
    final c = TextEditingController(text: UserStore.I.notes[g] ?? '');
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('ملاحظة على ${ay.ref}', style: const TextStyle(fontSize: 16)),
        content: TextField(
          controller: c,
          autofocus: true,
          minLines: 3,
          maxLines: 8,
          decoration: const InputDecoration(hintText: 'اكتب فائدة أو تدبّرًا…', border: OutlineInputBorder()),
        ),
        actions: [
          if (UserStore.I.notes.containsKey(g))
            TextButton(onPressed: () => Navigator.pop(ctx, ''), child: const Text('حذف', style: TextStyle(color: Colors.red))),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('حفظ')),
        ],
      ),
    );
    if (res != null) {
      UserStore.I.setNote(g, res);
      if (mounted) toast(context, res.trim().isEmpty ? 'حُذفت الملاحظة' : 'حُفظت الملاحظة');
    }
  }

  void _more() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      backgroundColor: _sheetBg(context),
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Container(
              decoration: BoxDecoration(color: _cardBg(ctx), borderRadius: BorderRadius.circular(16)),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.record_voice_over_rounded, color: kEmerald),
                    title: const Text('سمِّع هذه الصفحة'),
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => TasmeeScreen(page: ay.page)));
                    },
                  ),
                  const Divider(height: 1, indent: 56),
                  ListTile(
                    leading: const Icon(Icons.sticky_note_2_outlined, color: kEmerald),
                    title: Text(UserStore.I.notes.containsKey(g) ? 'تعديل الملاحظة' : 'كتابة ملاحظة'),
                    onTap: () {
                      Navigator.pop(ctx);
                      _editNote();
                    },
                  ),
                  const Divider(height: 1, indent: 56),
                  ListTile(
                    leading: const Icon(Icons.image_outlined, color: kEmerald),
                    title: const Text('مشاركة الآية كصورة'),
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => ShareImageScreen(g: g)));
                    },
                  ),
                  const Divider(height: 1, indent: 56),
                  ListTile(
                    leading: const Icon(Icons.repeat_one_rounded, color: kEmerald),
                    title: const Text('كرّر الآية للحفظ'),
                    subtitle: Text('عدد التكرار من الإعدادات: ${ar(AppSettings.I.repeatAyah)}'),
                    onTap: () {
                      Navigator.pop(ctx);
                      if (AppSettings.I.repeatAyah < 2) AppSettings.I.repeatAyah = 3;
                      AudioCtl.I.playRange(g, g, forceAyah: true);
                      Navigator.pop(context);
                    },
                  ),
                  const Divider(height: 1, indent: 56),
                  ListTile(
                    leading: const Icon(Icons.lightbulb_outline_rounded, color: kEmerald),
                    title: const Text('اسأل الذكاء الاصطناعي'),
                    onTap: () {
                      Navigator.pop(ctx);
                      showSoon(context);
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

  void _fawasil() {
    final q = QuranData.I;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      backgroundColor: _sheetBg(context),
      builder: (ctx) => SafeArea(
        child: ListenableBuilder(
          listenable: UserStore.I,
          builder: (ctx, _) => ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              const Center(child: Text('الفواصل', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18))),
              const SizedBox(height: 4),
              const Center(child: Text('اضغط على اللون لتضع فاصله عند هذه الآية', style: TextStyle(fontSize: 12.5))),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(color: _cardBg(ctx), borderRadius: BorderRadius.circular(16)),
                child: Column(
                  children: [
                    for (var i = 0; i < 4; i++) ...[
                      if (i > 0) const Divider(height: 1, indent: 56),
                      ListTile(
                        leading: Icon(UserStore.I.fawasil[i] != null ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                            color: kFasilColors[i], size: 30),
                        title: Text(kFasilNames[i]),
                        subtitle: UserStore.I.fawasil[i] == null
                            ? null
                            : Text(
                                '${_date(UserStore.I.fawasil[i]![1])}  ${surahName(q.ayahs[UserStore.I.fawasil[i]![0]].s)}: ${q.ayahs[UserStore.I.fawasil[i]![0]].a}',
                                style: const TextStyle(color: kGoldDeep)),
                        trailing: UserStore.I.fawasil[i] == null
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.close_rounded, size: 20),
                                onPressed: () => UserStore.I.setFasil(i, null),
                              ),
                        onTap: () {
                          UserStore.I.setFasil(i, g);
                          toast(context, 'وُضع الفاصل ${kFasilNames[i]} عند ${ay.ref}');
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _date(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${d.day}/${d.month}/${d.year % 100}';
  }

  @override
  Widget build(BuildContext context) {
    final green = Theme.of(context).colorScheme.primary;
    return DraggableScrollableSheet(
      initialChildSize: 0.62,
      minChildSize: 0.35,
      maxChildSize: 0.96,
      expand: false,
      builder: (ctx, sc) => Container(
        decoration: BoxDecoration(
          color: _sheetBg(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        ),
        child: ListenableBuilder(
          listenable: Listenable.merge([UserStore.I, Reciters.I]),
          builder: (context, _) {
            final st = UserStore.I;
            final q = QuranData.I;
            final cur = st.highlights[g];
            // the first set marker (to show like a summary)
            int? firstColor;
            for (var i = 0; i < 4; i++) {
              if (st.fawasil[i] != null) {
                firstColor = i;
                break;
              }
            }
            return ListView(
              controller: sc,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 30),
              children: [
                Row(
                  children: [
                    GestureDetector(
                      onTap: _more,
                      child: Text('المزيد', style: TextStyle(color: green, fontWeight: FontWeight.w600, fontSize: 15)),
                    ),
                    Expanded(
                      child: Text('${surahName(ay.s)}: ${ay.a}',
                          textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
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
                if (st.notes[g] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: _Tile(
                      onTap: _editNote,
                      padding: const EdgeInsets.all(12),
                      child: Row(children: [
                        const Icon(Icons.sticky_note_2_outlined, size: 20, color: kGoldDeep),
                        const SizedBox(width: 8),
                        Expanded(child: Text(st.notes[g]!, style: const TextStyle(height: 1.6))),
                      ]),
                    ),
                  ),
                const _Title('الفواصل'),
                Row(
                  children: [
                    Expanded(
                      child: _Tile(
                        onTap: _fawasil,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        child: Row(
                          children: [
                            Icon(firstColor != null ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                                color: kFasilColors[firstColor ?? 0], size: 28),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(kFasilNames[firstColor ?? 0], style: const TextStyle(fontWeight: FontWeight.w600)),
                                  Text(
                                      firstColor == null
                                          ? 'ضع فاصلًا هنا'
                                          : '${surahName(q.ayahs[st.fawasil[firstColor]![0]].s)}: ${q.ayahs[st.fawasil[firstColor]![0]].a}',
                                      style: const TextStyle(color: kGoldDeep, fontSize: 13)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _Tile(
                        onTap: _fawasil,
                        child: Row(
                          children: [
                            Icon(Icons.format_list_bulleted_rounded, color: green),
                            const SizedBox(width: 10),
                            Text('الكل', style: TextStyle(color: green, fontWeight: FontWeight.w600, fontSize: 16)),
                            const Spacer(),
                            const Icon(Icons.chevron_left_rounded, color: Colors.grey),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const _Title('التلاوة'),
                Row(
                  children: [
                    Expanded(
                      child: _Tile(
                        onTap: () => _play(q.surahEndG(ay.s), cont: true),
                        child: Row(children: [
                          Icon(Icons.play_arrow_rounded, color: green, size: 28),
                          const SizedBox(width: 8),
                          Text('تشغيل', style: TextStyle(color: green, fontWeight: FontWeight.w600, fontSize: 16)),
                        ]),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _Tile(
                        onTap: _playTo,
                        child: Row(children: [
                          Icon(Icons.play_arrow_rounded, color: green, size: 28),
                          const SizedBox(width: 8),
                          Text('تشغيل إلى', style: TextStyle(color: green, fontWeight: FontWeight.w600, fontSize: 16)),
                          const Spacer(),
                          const Icon(Icons.chevron_left_rounded, color: Colors.grey),
                        ]),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _Tile(
                  onTap: () => showReciterSheet(context, page: ay.page),
                  onLongPress: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AddReciterScreen())),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                  child: Row(children: [
                    Icon(Icons.mic_none_rounded, color: green),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(Reciters.I.current.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: green, fontWeight: FontWeight.w600, fontSize: 16)),
                    ),
                    const Icon(Icons.chevron_left_rounded, color: Colors.grey),
                  ]),
                ),
                const _Title('التفسير'),
                _Tile(
                  onTap: _openLibrary,
                  child: FutureBuilder<String>(
                    future: tf,
                    builder: (context, snap) {
                      if (snap.connectionState != ConnectionState.done) {
                        return const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator());
                      }
                      final t = snap.hasError ? 'افتح المكتبة لقراءة التفاسير' : (snap.data ?? '');
                      final short = t.length > 150 ? '${t.substring(0, 150)} … ' : '$t ';
                      return Text.rich(
                        TextSpan(children: [
                          TextSpan(text: short),
                          TextSpan(text: 'متابعة القراءة', style: TextStyle(color: green, fontWeight: FontWeight.w600)),
                        ]),
                        style: const TextStyle(fontSize: 16, height: 1.8),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 10),
                _Tile(
                  onTap: _openLibrary,
                  child: Row(children: [
                    Icon(Icons.local_library_rounded, color: green),
                    const SizedBox(width: 10),
                    Text('المكتبة', style: TextStyle(color: green, fontWeight: FontWeight.w600, fontSize: 16)),
                    const Spacer(),
                    const Icon(Icons.chevron_left_rounded, color: Colors.grey),
                  ]),
                ),
                const _Title('المشاركة'),
                Row(
                  children: [
                    Expanded(
                      child: _Tile(
                        onTap: () => _copy('﴿${ay.text}﴾ $refText', 'نُسخت الآية'),
                        onLongPress: () => _copy('﴿${q.clean[g]}﴾ [سورة ${surahName(ay.s)}: ${ay.a}]', 'نُسخت بلا تشكيل'),
                        child: Icon(Icons.copy_rounded, color: green),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _Tile(
                        onTap: () => _copy('﴿${q.clean[g]}﴾ [سورة ${surahName(ay.s)}: ${ay.a}]', 'نُسخت بلا تشكيل'),
                        child: Icon(Icons.text_fields_rounded, color: green),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: _Tile(
                        onTap: () => Share.share('﴿${ay.text}﴾ $refText'),
                        onLongPress: () =>
                            Navigator.of(context).push(MaterialPageRoute(builder: (_) => ShareImageScreen(g: g))),
                        child: Row(children: [
                          Icon(Icons.ios_share_rounded, color: green),
                          const SizedBox(width: 10),
                          Text('مشاركة', style: TextStyle(color: green, fontWeight: FontWeight.w600, fontSize: 16)),
                          const Spacer(),
                          const Icon(Icons.chevron_left_rounded, color: Colors.grey),
                        ]),
                      ),
                    ),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(6, 6, 6, 0),
                  child: Text('نسخ • نسخ بلا تشكيل • مشاركة (اضغط مطولًا للمشاركة كصورة)', style: TextStyle(fontSize: 11.5, color: Colors.grey)),
                ),
                const _Title('التمييز'),
                _Tile(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      GestureDetector(
                        onTap: () => st.setHighlight(g, null),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: cur == null ? green : Colors.grey, width: cur == null ? 2.5 : 1.2),
                          ),
                          child: Icon(Icons.block_rounded, size: 20, color: Colors.grey.withValues(alpha: 0.7)),
                        ),
                      ),
                      for (var i = 0; i < kHighlightColors.length; i++)
                        GestureDetector(
                          onTap: () => st.setHighlight(g, i),
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: kHighlightColors[i],
                              border: Border.all(color: cur == i ? green : Colors.transparent, width: 2.5),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// «المكتبة»: every tafsir of the ayah, one under the other.
class LibraryScreen extends StatefulWidget {
  final int g;
  const LibraryScreen({super.key, required this.g});
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  late int g;
  double scale = 1;

  @override
  void initState() {
    super.initState();
    g = widget.g;
  }

  @override
  void dispose() {
    Tts.I.stop();
    super.dispose();
  }

  void _move(int d) {
    final n = g + d;
    if (n < 0 || n > 6235) return;
    Tts.I.stop();
    setState(() => g = n);
  }

  @override
  Widget build(BuildContext context) {
    final q = QuranData.I;
    final ay = q.ayahs[g];
    final green = Theme.of(context).colorScheme.primary;
    final ref = '[سورة ${surahName(ay.s)}: ${ar(ay.a)}]';
    final order = [...TafsirService.I.active]..sort((a, b) => (a.id == AppSettings.I.tafsirId ? 0 : 1).compareTo(b.id == AppSettings.I.tafsirId ? 0 : 1));
    return Scaffold(
      backgroundColor: _sheetBg(context),
      appBar: AppBar(backgroundColor: _sheetBg(context), title: const Text('المكتبة')),
      body: ListView(
        key: ValueKey(g),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text('${ay.text} ${ayahMark(ay.a)}',
                textAlign: TextAlign.center, style: TextStyle(fontFamily: quranFont(), fontSize: 23, height: 2.1)),
          ),
          if (q.asbab[g] != null) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(6, 10, 6, 6),
              child: Text('سبب النزول — الصحيح المسند (مقبل الوادعي)', style: TextStyle(color: kGoldDeep, fontSize: 15)),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: _cardBg(context), borderRadius: BorderRadius.circular(16)),
              child: SelectableText(q.asbab[g]!, style: TextStyle(fontSize: 17 * scale, height: 1.9)),
            ),
          ],
          for (final t in order) _TafsirBlock(key: ValueKey('${t.id}:$g'), t: t, g: g, scale: scale, refText: ref),
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              onPressed: () async {
                await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TafsirsScreen()));
                if (mounted) setState(() {});
              },
              icon: const Icon(Icons.library_add_rounded),
              label: const Text('أضف تفاسير أخرى أو تفسيرًا بلغة أخرى'),
            ),
          ),
          if ((q.similar[g] ?? const <int>[]).isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(6, 18, 6, 6),
              child: Text('آيات متشابهة', style: TextStyle(color: kGoldDeep, fontSize: 15)),
            ),
            Container(
              decoration: BoxDecoration(color: _cardBg(context), borderRadius: BorderRadius.circular(16)),
              child: Column(
                children: [
                  for (final o in q.similar[g]!)
                    ListTile(
                      title: Text(q.ayahs[o].text, style: TextStyle(fontFamily: quranFont(), fontSize: 18, height: 1.9)),
                      subtitle: Text(q.ayahs[o].ref, style: const TextStyle(color: kGoldDeep)),
                      onTap: () => setState(() => g = o),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: Row(
            children: [
              IconButton(
                tooltip: 'حجم الخط',
                onPressed: () => setState(() => scale = scale >= 1.4 ? 0.9 : scale + 0.15),
                icon: Icon(Icons.format_size_rounded, color: green),
              ),
              _navBtn(Icons.chevron_right_rounded, () => _move(-1)),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(12)),
                  child: Text('${surahName(ay.s)}: ${ay.a}', style: TextStyle(color: green, fontWeight: FontWeight.w600, fontSize: 16)),
                ),
              ),
              const SizedBox(width: 8),
              _navBtn(Icons.chevron_left_rounded, () => _move(1)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navBtn(IconData i, VoidCallback f) => InkWell(
        onTap: f,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 50,
          height: 44,
          decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(12)),
          child: Icon(i, color: Theme.of(context).colorScheme.primary),
        ),
      );
}

class _TafsirBlock extends StatefulWidget {
  final TafsirSource t;
  final int g;
  final double scale;
  final String refText;
  const _TafsirBlock({super.key, required this.t, required this.g, required this.scale, required this.refText});
  @override
  State<_TafsirBlock> createState() => _TafsirBlockState();
}

class _TafsirBlockState extends State<_TafsirBlock> {
  late Future<String> f;
  bool open = false;

  Widget _act(IconData icon, String label, VoidCallback onTap) {
    final green = Theme.of(context).colorScheme.primary;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: green, size: 22),
            const SizedBox(height: 3),
            Text(label, style: TextStyle(fontSize: 11, color: green, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    f = TafsirService.I.get(widget.t.id, widget.g);
    open = widget.t.id == AppSettings.I.tafsirId;
  }

  @override
  Widget build(BuildContext context) {
    final green = Theme.of(context).colorScheme.primary;
    return FutureBuilder<String>(
      future: f,
      builder: (context, snap) {
        final text = snap.data ?? '';
        final long = text.length > 420;
        final shown = (!open && long) ? '${text.substring(0, 420)} …' : text;
        final first = widget.t.id == AppSettings.I.tafsirId;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 18, 6, 6),
              child: Row(
                children: [
                  Container(width: 4, height: 18, decoration: BoxDecoration(color: kGold, borderRadius: BorderRadius.circular(3))),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(widget.t.title,
                          style: const TextStyle(color: kGoldDeep, fontSize: 16, fontWeight: FontWeight.w700))),
                  if (first)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(color: green.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                      child: Text('الأول', style: TextStyle(color: green, fontSize: 12, fontWeight: FontWeight.w700)),
                    ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: _cardBg(context), borderRadius: BorderRadius.circular(16)),
              child: snap.connectionState != ConnectionState.done
                  ? const LinearProgressIndicator()
                  : snap.hasError
                      ? const Text('هذا التفسير يحتاج إلى الإنترنت.')
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SelectableText(shown,
                                textDirection: widget.t.rtl ? TextDirection.rtl : TextDirection.ltr,
                                textAlign: widget.t.rtl ? TextAlign.right : TextAlign.left,
                                style: TextStyle(fontSize: 17 * widget.scale, height: 1.9)),
                            if (long)
                              Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: TextButton(
                                  onPressed: () => setState(() => open = !open),
                                  child: Text(open ? 'إخفاء' : 'متابعة القراءة'),
                                ),
                              ),
                            const Divider(height: 18),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                _act(Icons.volume_up_rounded, 'استماع', () => Tts.I.speak(text, key: '${widget.t.id}:${widget.g}')),
                                _act(Icons.stop_circle_outlined, 'إيقاف', () => Tts.I.stop()),
                                _act(Icons.copy_rounded, 'نسخ', () {
                                  Clipboard.setData(ClipboardData(text: '${widget.t.title} ${widget.refText}:\n${stripTashkeel(text)}'));
                                  toast(context, 'نُسخ التفسير');
                                }),
                                _act(Icons.ios_share_rounded, 'مشاركة', () {
                                  Share.share(
                                      '﴿${QuranData.I.clean[widget.g]}﴾ ${widget.refText}\n\n${widget.t.title}:\n${stripTashkeel(text)}');
                                }),
                                _act(Icons.image_outlined, 'صورة', () {
                                  Navigator.of(context).push(MaterialPageRoute(
                                      builder: (_) => ShareImageScreen(g: widget.g, tafsir: stripTashkeel(text))));
                                }),
                                if (!first)
                                  _act(Icons.push_pin_outlined, 'الأول', () {
                                    AppSettings.I.tafsirId = widget.t.id;
                                    toast(context, 'صار ${widget.t.title} هو التفسير الأول');
                                  }),
                              ],
                            ),
                          ],
                        ),
            ),
          ],
        );
      },
    );
  }
}
