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
  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      HomeScreen(onTab: (i) => setState(() => _i = i)),
      const IndexScreen(),
      const MemorizeScreen(),
      const SettingsScreen(),
    ];
    return Scaffold(
      body: IndexedStack(index: _i, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _i,
        height: 66,
        onDestinationSelected: (i) => setState(() => _i = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'الرئيسية'),
          NavigationDestination(icon: Icon(Icons.menu_book_outlined), selectedIcon: Icon(Icons.menu_book_rounded), label: 'الفهرس'),
          NavigationDestination(icon: Icon(Icons.record_voice_over_outlined), selectedIcon: Icon(Icons.record_voice_over_rounded), label: 'الحفظ والتسميع'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings_rounded), label: 'الإعدادات'),
        ],
      ),
    );
  }
}
