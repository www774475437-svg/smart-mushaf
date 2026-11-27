import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/reciters.dart';
import '../data/riwaya.dart';
import '../data/tafsir.dart';
import '../services/settings.dart';
import 'common.dart';
import 'reciters_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: ListenableBuilder(
        listenable: Listenable.merge([AppSettings.I, Reciters.I]),
        builder: (context, _) {
          final st = AppSettings.I;
          return ListView(
            padding: const EdgeInsets.only(bottom: 40),
            children: [
              GroupCard(title: 'المظهر', children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(children: [
                        IconSquare(Icons.brightness_6_rounded, Color(0xFF37474F)),
                        SizedBox(width: 14),
                        Text('الوضع', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15.5)),
                      ]),
                      const SizedBox(height: 10),
                      Pills<ReadTheme>(
                        values: ReadTheme.values,
                        selected: st.theme,
                        label: (t) => const {ReadTheme.day: 'نهاري', ReadTheme.paper: 'ورقي', ReadTheme.night: 'ليلي'}[t]!,
                        onChanged: (t) => st.theme = t,
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                  child: Row(
                    children: [
                      const IconSquare(Icons.format_size_rounded, kGoldDeep),
                      const SizedBox(width: 14),
                      Text('حجم خط المصحف: ${ar(st.fontSize.round())}',
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15.5)),
                    ],
                  ),
                ),
                Slider(min: 16, max: 40, divisions: 24, value: st.fontSize, onChanged: (v) => st.fontSize = v),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Text('ٱلْحَمْدُ لِلَّهِ رَبِّ ٱلْعَٰلَمِينَ',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontFamily: quranFont(), fontSize: st.fontSize, height: 1.9)),
                ),
                SwitchListTile(
                  secondary: const IconSquare(Icons.crop_square_rounded, kGold),
                  title: const Text('إطار الصفحة', style: TextStyle(fontWeight: FontWeight.w600)),
                  value: st.showPageFrame,
                  onChanged: (v) => st.showPageFrame = v,
                ),
              ]),
              GroupCard(title: 'القراءة', children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: Row(
                    children: [
                      const IconSquare(Icons.swipe_rounded, kEmerald),
                      const SizedBox(width: 14),
                      const Expanded(child: Text('طريقة القراءة', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15.5))),
                      Pills<bool>(
                        values: const [false, true],
                        selected: st.scrollMode,
                        label: (v) => v ? 'تمرير عمودي' : 'تقليب',
                        onChanged: (v) => st.scrollMode = v,
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: Row(
                    children: [
                      const IconSquare(Icons.slow_motion_video_rounded, Color(0xFF1565C0)),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text('التمرير التلقائي: ${st.scrollMode ? 'الصفحة في' : 'صفحة كل'} ${ar(st.autoSeconds)} ثانية',
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                      ),
                    ],
                  ),
                ),
                Slider(
                  min: 10,
                  max: 300,
                  divisions: 29,
                  value: st.autoSeconds.toDouble().clamp(10.0, 300.0),
                  onChanged: (v) => st.autoSeconds = v.round(),
                ),
                SwitchListTile(
                  secondary: const IconSquare(Icons.light_mode_rounded, Color(0xFFF9A825)),
                  title: const Text('إبقاء الشاشة مضاءة أثناء القراءة', style: TextStyle(fontWeight: FontWeight.w600)),
                  value: st.keepAwake,
                  onChanged: (v) => st.keepAwake = v,
                ),
                SwitchListTile(
                  secondary: const IconSquare(Icons.sync_alt_rounded, Color(0xFF6A4C93)),
                  title: const Text('تقليب الصفحات مع التلاوة', style: TextStyle(fontWeight: FontWeight.w600)),
                  value: st.followAudio,
                  onChanged: (v) => st.followAudio = v,
                ),
              ]),
              GroupCard(title: 'الرواية', children: [
                GroupTile(
                  icon: Icons.auto_stories_rounded,
                  color: const Color(0xFF00838F),
                  title: 'الرواية المختارة',
                  subtitle: riwayaById(st.riwaya).name,
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RiwayatScreen())),
                ),
              ]),
              GroupCard(title: 'الصوت والتلاوة', children: [
                GroupTile(
                  icon: Icons.mic_rounded,
                  color: kEmerald,
                  title: 'القارئ',
                  subtitle: Reciters.I.current.name,
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RecitersScreen())),
                  onLongPress: () =>
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AddReciterScreen())),
                ),
                GroupTile(
                  icon: Icons.person_add_alt_1_rounded,
                  color: const Color(0xFF6A4C93),
                  title: 'إضافة قارئ وصوته',
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AddReciterScreen())),
                ),
                _stepper(context, Icons.speed_rounded, const Color(0xFF1565C0), 'سرعة التلاوة', '${st.speed}×', () {
                  const s = [1.0, 1.25, 1.5];
                  final i = s.indexOf(st.speed);
                  if (i > 0) st.speed = s[i - 1];
                }, () {
                  const s = [1.0, 1.25, 1.5];
                  final i = s.indexOf(st.speed);
                  if (i < s.length - 1) st.speed = s[i < 0 ? 0 : i + 1];
                }),
                _stepper(context, Icons.repeat_one_rounded, const Color(0xFF2E7D32), 'تكرار كل آية',
                    '${ar(st.repeatAyah)} ${st.repeatAyah == 1 ? 'مرة' : 'مرات'}', () {
                  if (st.repeatAyah > 1) st.repeatAyah = st.repeatAyah - 1;
                }, () {
                  if (st.repeatAyah < 20) st.repeatAyah = st.repeatAyah + 1;
                }),
                _stepper(context, Icons.repeat_rounded, const Color(0xFFEF6C00), 'تكرار المقطع',
                    st.repeatRange == 0 ? 'بلا توقف' : '${ar(st.repeatRange)} ${st.repeatRange == 1 ? 'مرة' : 'مرات'}', () {
                  if (st.repeatRange == 0) {
                    st.repeatRange = 20;
                  } else if (st.repeatRange > 1) {
                    st.repeatRange = st.repeatRange - 1;
                  }
                }, () {
                  if (st.repeatRange == 0) return;
                  st.repeatRange = st.repeatRange >= 20 ? 0 : st.repeatRange + 1;
                }),
                SwitchListTile(
                  secondary: const IconSquare(Icons.playlist_play_rounded, Color(0xFF00838F)),
                  title: const Text('المتابعة إلى السورة التالية', style: TextStyle(fontWeight: FontWeight.w600)),
                  value: st.continueNext,
                  onChanged: (v) => st.continueNext = v,
                ),
              ]),
              GroupCard(title: 'الحفظ والمراجعة', children: [
                SwitchListTile(
                  secondary: const IconSquare(Icons.event_repeat_rounded, Color(0xFF2E7D32)),
                  title: const Text('المراجعة الذكية', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('يذكّرك بمراجعة السور التي حفظتها: بعد ٣ أيام، ثم أسبوع، ثم شهر'),
                  value: st.smartReview,
                  onChanged: (v) => st.smartReview = v,
                ),
              ]),
              GroupCard(title: 'التفسير والترجمة', children: [
                GroupTile(
                  icon: Icons.lightbulb_rounded,
                  color: kGoldDeep,
                  title: 'التفسير الافتراضي',
                  subtitle: TafsirService.I.byId(st.tafsirId).name,
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TafsirsScreen())),
                ),
                GroupTile(
                  icon: Icons.download_for_offline_rounded,
                  color: const Color(0xFF37474F),
                  title: 'تحميل التفاسير بدون إنترنت',
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TafsirsScreen())),
                ),
                SwitchListTile(
                  secondary: const IconSquare(Icons.translate_rounded, Color(0xFF1565C0)),
                  title: const Text('إظهار الترجمة الإنجليزية', style: TextStyle(fontWeight: FontWeight.w600)),
                  value: st.showTranslation,
                  onChanged: (v) => st.showTranslation = v,
                ),
                _stepper(context, Icons.record_voice_over_rounded, const Color(0xFF6A4C93), 'سرعة قراءة التفسير',
                    ar((st.ttsRate * 100).round()), () {
                  if (st.ttsRate > 0.25) st.ttsRate = ((st.ttsRate - 0.05) * 100).round() / 100;
                }, () {
                  if (st.ttsRate < 0.8) st.ttsRate = ((st.ttsRate + 0.05) * 100).round() / 100;
                }),
              ]),
              GroupCard(title: 'عن التطبيق', children: [
                const GroupTile(
                  icon: Icons.person_rounded,
                  color: kEmeraldDark,
                  title: 'المطوّر',
                  subtitle: 'أبو عبد الرحمن الأثري',
                ),
                GroupTile(
                  icon: Icons.send_rounded,
                  color: const Color(0xFF229ED9),
                  title: 'تواصل مع المطوّر',
                  subtitle: 'تيليجرام',
                  onTap: () => launchUrl(Uri.parse('https://t.me/alhsaar4'), mode: LaunchMode.externalApplication),
                ),
                const GroupTile(
                  icon: Icons.info_outline_rounded,
                  color: Color(0xFF607D8B),
                  title: 'المصادر',
                  subtitle: 'نص المصحف والتفاسير من مصادر مفتوحة (Tanzil، مجمع الملك فهد، Quran.com)، والتلاوات من EveryAyah و MP3Quran',
                ),
              ]),
            ],
          );
        },
      ),
    );
  }

  Widget _stepper(BuildContext context, IconData icon, Color color, String title, String value, VoidCallback minus,
      VoidCallback plus) {
    return ListTile(
      leading: IconSquare(icon, color),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(onPressed: minus, icon: const Icon(Icons.remove_circle_outline_rounded)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
          IconButton(onPressed: plus, icon: const Icon(Icons.add_circle_outline_rounded)),
        ],
      ),
    );
  }
}

class RiwayatScreen extends StatefulWidget {
  const RiwayatScreen({super.key});
  @override
  State<RiwayatScreen> createState() => _RiwayatScreenState();
}

class _RiwayatScreenState extends State<RiwayatScreen> {
  final Set<String> busy = {};
  final Map<String, bool> have = {};

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    for (final r in kRiwayat) {
      have[r.id] = await RiwayaService.I.isDownloaded(r.id);
    }
    if (mounted) setState(() {});
  }

  Future<void> _tap(Riwaya r) async {
    if (have[r.id] == true) {
      AppSettings.I.riwaya = r.id;
      setState(() {});
      return;
    }
    setState(() => busy.add(r.id));
    try {
      await RiwayaService.I.download(r);
      have[r.id] = true;
      AppSettings.I.riwaya = r.id;
      if (mounted) toast(context, 'حُمّلت رواية ${r.name}');
    } catch (_) {
      if (mounted) toast(context, 'تعذّر تحميل الرواية، تأكد من الإنترنت');
    }
    if (mounted) setState(() => busy.remove(r.id));
  }

  @override
  Widget build(BuildContext context) {
    final cur = AppSettings.I.riwaya;
    return Scaffold(
      appBar: AppBar(title: const Text('الروايات')),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'المصحف بصفحاته يعمل برواية حفص. عند اختيار رواية أخرى تُعرض السور بنص تلك الرواية من الفهرس.',
              style: TextStyle(height: 1.7),
            ),
          ),
          for (final r in kRiwayat)
            ListTile(
              leading: Icon(cur == r.id ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                  color: kEmerald),
              title: Text(r.name, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(have[r.id] == true ? 'جاهزة' : 'تحتاج تحميل (مرة واحدة)'),
              trailing: busy.contains(r.id)
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5))
                  : have[r.id] == true
                      ? null
                      : const Icon(Icons.download_rounded),
              onTap: busy.contains(r.id) ? null : () => _tap(r),
            ),
        ],
      ),
    );
  }
}

class TafsirsScreen extends StatefulWidget {
  const TafsirsScreen({super.key});
  @override
  State<TafsirsScreen> createState() => _TafsirsScreenState();
}

class _TafsirsScreenState extends State<TafsirsScreen> {
  final Map<String, double> prog = {};
  final Map<String, bool> have = {};

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    for (final t in kTafsirs) {
      have[t.id] = await TafsirService.I.isAvailableOffline(t);
    }
    if (mounted) setState(() {});
  }

  Future<void> _download(TafsirSource t) async {
    setState(() => prog[t.id] = 0);
    try {
      await TafsirService.I.download(t, (p) {
        if (mounted) setState(() => prog[t.id] = p);
      });
      have[t.id] = true;
      if (mounted) toast(context, 'حُمّل ${t.name}');
    } catch (_) {
      if (mounted) toast(context, 'تعذّر التحميل، تأكد من الإنترنت');
    }
    if (mounted) setState(() => prog.remove(t.id));
  }

  @override
  Widget build(BuildContext context) {
    final cur = AppSettings.I.tafsirId;
    return Scaffold(
      appBar: AppBar(title: const Text('التفاسير')),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('اختر التفسير الافتراضي، وحمّل ما تريد ليعمل بدون إنترنت.', style: TextStyle(height: 1.7)),
          ),
          for (final t in kTafsirs)
            ListTile(
              leading: Icon(cur == t.id ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                  color: kEmerald),
              title: Text(t.name, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('${t.author} • ${t.bundled ? 'مدمج في التطبيق' : have[t.id] == true ? 'محمّل' : 'يعمل بالإنترنت'}'),
              onTap: () {
                AppSettings.I.tafsirId = t.id;
                setState(() {});
              },
              trailing: t.bundled
                  ? null
                  : prog.containsKey(t.id)
                      ? SizedBox(
                          width: 26,
                          height: 26,
                          child: CircularProgressIndicator(value: prog[t.id], strokeWidth: 3),
                        )
                      : have[t.id] == true
                          ? IconButton(
                              icon: const Icon(Icons.delete_outline_rounded),
                              onPressed: () async {
                                await TafsirService.I.remove(t);
                                have[t.id] = false;
                                if (mounted) setState(() {});
                              },
                            )
                          : IconButton(icon: const Icon(Icons.download_rounded), onPressed: () => _download(t)),
            ),
        ],
      ),
    );
  }
}
