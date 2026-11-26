import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/layout.dart';
import '../services/settings.dart';

const kEmerald = Color(0xFF0F5C4A);
const kEmeraldDark = Color(0xFF0A3D31);
const kGold = Color(0xFFC9A24A);
const kGoldDeep = Color(0xFFA8832F);

const List<Color> kHighlightColors = [
  Color(0xFFFFD970),
  Color(0xFF8FD6A9),
  Color(0xFF93C2F0),
  Color(0xFFF2A0A0),
];

String ar(int n) {
  const d = '٠١٢٣٤٥٦٧٨٩';
  final s = n.toString();
  final b = StringBuffer();
  for (final c in s.codeUnits) {
    final i = c - 48;
    b.write(i >= 0 && i <= 9 ? d[i] : String.fromCharCode(c));
  }
  return b.toString();
}

class PageColors {
  final Color bg, text, accent, frame, bar, soft;
  const PageColors(this.bg, this.text, this.accent, this.frame, this.bar, this.soft);
}

PageColors pageColors(ReadTheme t) {
  switch (t) {
    case ReadTheme.day:
      return const PageColors(Color(0xFFFFFDF7), Color(0xFF1C1810), Color(0xFFA8832F), Color(0xFFC9A24A),
          Color(0xFFFFFFFF), Color(0xFFF3EEDF));
    case ReadTheme.paper:
      return const PageColors(Color(0xFFF4EAD2), Color(0xFF2D2316), Color(0xFF94701F), Color(0xFFB8913F),
          Color(0xFFF1E5C8), Color(0xFFE9DCBC));
    case ReadTheme.night:
      return const PageColors(Color(0xFF0C1210), Color(0xFFE9E3D2), Color(0xFFD6B55E), Color(0xFF7D6731),
          Color(0xFF131C19), Color(0xFF18221E));
  }
}

bool isDark(BuildContext c) => Theme.of(c).brightness == Brightness.dark;

ThemeData buildTheme(bool dark) {
  final bg = dark ? const Color(0xFF0B1311) : const Color(0xFFF6F3EA);
  final scheme = ColorScheme.fromSeed(
    seedColor: kEmerald,
    brightness: dark ? Brightness.dark : Brightness.light,
  ).copyWith(
    primary: dark ? const Color(0xFF7BCBB0) : kEmerald,
    secondary: kGold,
    surface: dark ? const Color(0xFF131D1A) : Colors.white,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: 'Tajawal',
    scaffoldBackgroundColor: bg,
    appBarTheme: AppBarTheme(
      backgroundColor: bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      foregroundColor: dark ? Colors.white : kEmeraldDark,
      titleTextStyle: TextStyle(
          fontFamily: 'Tajawal', fontSize: 19, fontWeight: FontWeight.w700, color: dark ? Colors.white : kEmeraldDark),
    ),
  );
}

void toast(BuildContext c, String m) {
  ScaffoldMessenger.of(c)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(m, style: const TextStyle(fontFamily: 'Tajawal')),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ));
}

/// Rounded square with an icon, like grouped iOS settings.
class IconSquare extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  const IconSquare(this.icon, this.color, {super.key, this.size = 34});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(size * 0.28)),
      child: Icon(icon, color: Colors.white, size: size * 0.58),
    );
  }
}

class GroupCard extends StatelessWidget {
  final String? title;
  final List<Widget> children;
  const GroupCard({super.key, this.title, required this.children});
  @override
  Widget build(BuildContext context) {
    final dark = isDark(context);
    final items = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      items.add(children[i]);
      if (i < children.length - 1) {
        items.add(Divider(height: 1, indent: 60, color: dark ? Colors.white10 : Colors.black12));
      }
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
              child: Text(title!,
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: dark ? Colors.white60 : Colors.black54)),
            ),
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: dark ? Colors.white10 : const Color(0x14000000)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(children: items),
          ),
        ],
      ),
    );
  }
}

class GroupTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  const GroupTile(
      {super.key,
      required this.icon,
      required this.color,
      required this.title,
      this.subtitle,
      this.trailing,
      this.onTap,
      this.onLongPress});
  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      onLongPress: onLongPress,
      leading: IconSquare(icon, color),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15.5)),
      subtitle: subtitle == null ? null : Text(subtitle!, style: const TextStyle(fontSize: 12.5)),
      trailing: trailing ?? (onTap != null ? const Icon(Icons.chevron_left_rounded) : null),
    );
  }
}

/// A row of selectable pills.
class Pills<T> extends StatelessWidget {
  final List<T> values;
  final T selected;
  final String Function(T) label;
  final ValueChanged<T> onChanged;
  const Pills({super.key, required this.values, required this.selected, required this.label, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final v in values)
          GestureDetector(
            onTap: () => onChanged(v),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: v == selected ? cs.primary : cs.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(30),
              ),
              child: Text(label(v),
                  style: TextStyle(
                      color: v == selected ? (isDark(context) ? Colors.black : Colors.white) : cs.primary,
                      fontWeight: FontWeight.w600)),
            ),
          ),
      ],
    );
  }
}

class SurahNumberBadge extends StatelessWidget {
  final int n;
  const SurahNumberBadge(this.n, {super.key});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: kGold, width: 1.6),
        color: kGold.withValues(alpha: 0.08),
      ),
      child: Text(ar(n), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
    );
  }
}

const Map<String, String> kQuranFonts = {
  'AmiriQuran': 'أميري قرآن',
  'UthmanicHafs': 'العثماني (مجمع الملك فهد)',
  'Scheherazade': 'شهرزاد',
  'NotoNaskh': 'النسخ',
  'Lateef': 'لطيف',
};

class AppFonts {
  static List<String> available = ['AmiriQuran'];
  static bool surahNames = false;
  static Future<void> init() async {
    try {
      final l = List<String>.from(jsonDecode(await rootBundle.loadString('assets/data/fonts.json')) as List);
      available = [for (final f in kQuranFonts.keys) if (f == 'AmiriQuran' || l.contains(f)) f];
      surahNames = l.contains('SurahNames');
    } catch (_) {}
  }
}

/// One fixed mushaf font: the King Fahd Complex Uthmani script (Amiri Quran if missing).
String quranFont() => AppFonts.available.contains('UthmanicHafs') ? 'UthmanicHafs' : 'AmiriQuran';

/// Placeholder for features that will be switched on later.
Future<void> showSoon(BuildContext context, {String? title}) {
  return showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.lightbulb_rounded, color: kGold, size: 40),
      title: Text(title ?? 'الذكاء الاصطناعي'),
      content: const Text('هذه الميزة قريبًا بإذن الله.', textAlign: TextAlign.center),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('حسنًا'))],
    ),
  );
}

/// End-of-ayah mark: the mushaf font draws the number inside its ornament.
String ayahMark(int a) => (MushafLayout.I.ready && quranFont() == 'UthmanicHafs') ? ar(a) : '﴿${ar(a)}﴾';

String hizbLabel(int hq) {
  final h = ((hq - 1) ~/ 4) + 1;
  switch ((hq - 1) % 4) {
    case 1:
      return 'ربع الحزب $h';
    case 2:
      return 'نصف الحزب $h';
    case 3:
      return 'ثلاثة أرباع الحزب $h';
    default:
      return 'الحزب $h';
  }
}
