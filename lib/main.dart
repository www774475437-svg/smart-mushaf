import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'data/layout.dart';
import 'data/quran.dart';
import 'data/reciters.dart';
import 'data/tafsir.dart';
import 'services/audio.dart';
import 'services/settings.dart';
import 'services/store.dart';
import 'ui/common.dart';
import 'ui/home.dart';
import 'ui/index_screen.dart';
import 'ui/majlis.dart';
import 'ui/memorize.dart';
import 'ui/settings_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppSettings.I.init();
  await UserStore.I.init();
  await Reciters.I.init();
  await AudioCtl.I.init();
  await TafsirService.I.init();
  await AppFonts.init();
  runApp(const SmartMushafApp());
}

class SmartMushafApp extends StatelessWidget {
  const SmartMushafApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppSettings.I,
      builder: (context, _) {
        final night = AppSettings.I.theme == ReadTheme.night;
        return MaterialApp(
          title: 'المصحف الذكي',
          debugShowCheckedModeBanner: false,
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: buildTheme(false),
          darkTheme: buildTheme(true),
          themeMode: night ? ThemeMode.dark : ThemeMode.light,
          home: const Boot(),
        );
      },
    );
  }
}

class Boot extends StatefulWidget {
  const Boot({super.key});
  @override
  State<Boot> createState() => _BootState();
}

class _BootState extends State<Boot> {
  late Future<void> _f;
  @override
  void initState() {
    super.initState();
    _f = QuranData.I.load().then((_) => MushafLayout.I.load());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _f,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.done && !snap.hasError) {
          return const RootNav();
        }
        return Scaffold(
          backgroundColor: kEmeraldDark,
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: Image.asset('assets/images/logo.png', width: 120, height: 120),
                ),
                const SizedBox(height: 18),
                const Text('المصحف الذكي',
                    style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w700)),
                const SizedBox(height: 18),
                if (snap.hasError)
                  const Text('حدث خطأ في تحميل المصحف', style: TextStyle(color: Colors.white70))
                else
                  const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(color: kGold, strokeWidth: 2.4)),
              ],
            ),
          ),
        );
      },
    );
  }
}

class RootNav extends StatefulWidget {
  const RootNav({super.key});
  @override
  State<RootNav> createState() => _RootNavState();
}

class _RootNavState extends State<RootNav> {
  int _i = 0;

  Widget _item(int i, IconData icon, IconData sel, String label) {
    final cs = Theme.of(context).colorScheme;
    final on = _i == i;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => setState(() => _i = i),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: on ? cs.primary.withValues(alpha: 0.14) : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(on ? sel : icon, color: on ? cs.primary : Colors.grey, size: 24),
            ),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(
                    fontSize: 11.5, fontWeight: on ? FontWeight.w700 : FontWeight.w500, color: on ? cs.primary : Colors.grey)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pages = <Widget>[
      HomeScreen(onTab: (i) => setState(() => _i = i)),
      const IndexScreen(),
      const MajlisScreen(),
      const MemorizeScreen(),
      const SettingsScreen(),
    ];
    final on = _i == 2;
    return Scaffold(
      body: IndexedStack(index: _i, children: pages),
      bottomNavigationBar: SafeArea(
        child: Container(
          height: 68,
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 16, offset: const Offset(0, 4))],
          ),
          child: Row(
            children: [
              _item(0, Icons.home_outlined, Icons.home_rounded, 'الرئيسية'),
              _item(1, Icons.menu_book_outlined, Icons.menu_book_rounded, 'الفهرس'),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _i = 2),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 46,
                        height: 38,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: on ? [kGoldDeep, kGold] : [kEmeraldDark, kEmerald]),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [BoxShadow(color: kEmerald.withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 3))],
                        ),
                        child: const Icon(Icons.groups_rounded, color: Colors.white, size: 26),
                      ),
                      const SizedBox(height: 2),
                      Text('مجلس الحفاظ',
                          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: on ? kGoldDeep : cs.primary)),
                    ],
                  ),
                ),
              ),
              _item(3, Icons.record_voice_over_outlined, Icons.record_voice_over_rounded, 'التسميع'),
              _item(4, Icons.settings_outlined, Icons.settings_rounded, 'الإعدادات'),
            ],
          ),
        ),
      ),
    );
  }
}
