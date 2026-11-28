import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:home_widget/home_widget.dart';
import 'package:just_audio_background/just_audio_background.dart';

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
import 'ui/hifz_plan.dart';
import 'ui/khatma.dart';
import 'services/notify.dart';
import 'ui/majlis.dart';
import 'ui/prayer_screen.dart';
import 'ui/reader.dart';
import 'ui/search.dart';
import 'ui/tasmee.dart';
import 'services/widget_bridge.dart';
import 'ui/memorize.dart';
import 'ui/settings_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppSettings.I.init();
  await UserStore.I.init();
  await Reciters.I.init();
  try {
    await JustAudioBackground.init(
      androidNotificationChannelId: 'com.abualathari.smart_mushaf.audio',
      androidNotificationChannelName: 'التلاوة',
      androidNotificationOngoing: true,
    );
  } catch (_) {}
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
  StreamSubscription<Uri?>? _sub;

  @override
  void initState() {
    super.initState();
    navRequest.addListener(_onNav);
    if (WidgetBridge.supported) {
      WidgetBridge.init();
      Notify.init();
      HomeWidget.initiallyLaunchedFromHomeWidget().then((u) {
        if (u != null) {
          _fromWidget(u);
        } else {
          _openMushaf();
        }
      }).catchError((_) => _openMushaf());
      _sub = HomeWidget.widgetClicked.listen(_fromWidget, onError: (_) {});
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openMushaf());
    }
  }

  bool _opened = false;

  /// The app starts inside the mushaf, at the page where the reader stopped.
  void _openMushaf() {
    if (_opened || !mounted || !AppSettings.I.openMushaf) return;
    _opened = true;
    MushafScreen.open(context, UserStore.I.lastPage.clamp(1, 604));
  }

  void _onNav() {
    final i = navRequest.value;
    if (i == null || !mounted) return;
    navRequest.value = null;
    setState(() => _i = i);
  }

  @override
  void dispose() {
    navRequest.removeListener(_onNav);
    _sub?.cancel();
    super.dispose();
  }

  /// A tap on a home-screen widget opens the matching place in the app.
  void _fromWidget(Uri? u) {
    if (u == null || !mounted) return;
    void go(Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
    final lp = UserStore.I.lastPage;
    if (u.host == 'page') {
      final n = int.tryParse(u.queryParameters['n'] ?? '') ?? lp;
      final g = int.tryParse(u.queryParameters['g'] ?? '');
      MushafScreen.open(context, n.clamp(1, 604), flashG: g);
      return;
    }
    switch (u.queryParameters['to']) {
      case 'pr':
        go(const PrayerScreen());
        break;
      case 'kh':
        go(const KhatmaScreen());
        break;
      case 'hf':
        go(const HifzPlanScreen());
        break;
      case 'ts':
        go(TasmeeScreen(page: lp));
        break;
      case 'rv':
        setState(() => _i = 3);
        break;
      case 'mj':
        setState(() => _i = 2);
        break;
      case 'pl':
        final ids = QuranData.I.pageAyahs[lp];
        if (ids.isNotEmpty) {
          AudioCtl.I.playRange(ids.first, QuranData.I.surahEndG(QuranData.I.ayahs[ids.first].s), continueAfter: true);
        }
        MushafScreen.open(context, lp);
        break;
      default:
        MushafScreen.open(context, lp);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      HomeScreen(onTab: (i) => setState(() => _i = i)),
      const IndexScreen(),
      const MajlisScreen(),
      const MemorizeScreen(),
      const SettingsScreen(),
    ];
    return Scaffold(
      body: IndexedStack(index: _i, children: pages),
      bottomNavigationBar: SafeArea(
        child: NavPill(
          selected: _i,
          onTap: (i) => setState(() => _i = i),
          onSearch: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SearchScreen())),
        ),
      ),
    );
  }
}
