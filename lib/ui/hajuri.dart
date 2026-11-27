import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../data/surah_names.dart';
import '../services/audio.dart';
import 'common.dart';

const String kStore = 'https://github.com/www774475437-svg/smart-mushaf-store/releases/download';
const String _indexUrl = 'https://raw.githubusercontent.com/www774475437-svg/smart-mushaf-store/main/hajuri/tafsir.json';

/// The recorded lessons of تفسير ابن كثير by الشيخ يحيى الحجوري, series by series.
class HajuriTafsir {
  static List<dynamic>? _data;

  static Future<List<dynamic>> load() async {
    if (_data != null) return _data!;
    final p = await SharedPreferences.getInstance();
    try {
      final r = await http.get(Uri.parse(_indexUrl)).timeout(const Duration(seconds: 40));
      if (r.statusCode == 200) {
        final body = utf8.decode(r.bodyBytes);
        _data = jsonDecode(body) as List;
        try {
          await p.setString('hajuriTafsir', body);
        } catch (_) {}
        return _data!;
      }
    } catch (_) {}
    final saved = p.getString('hajuriTafsir');
    if (saved != null) return _data = jsonDecode(saved) as List;
    throw Exception('offline');
  }
}

class HajuriTafsirScreen extends StatefulWidget {
  /// Opens straight on the lessons of this surah when it has some.
  final int? surah;
  const HajuriTafsirScreen({super.key, this.surah});
  @override
  State<HajuriTafsirScreen> createState() => _HajuriTafsirScreenState();
}

class _HajuriTafsirScreenState extends State<HajuriTafsirScreen> {
  late Future<List<dynamic>> f;
  bool _jumped = false;

  @override
  void initState() {
    super.initState();
    f = HajuriTafsir.load();
  }

  String _name(Map e) {
    final s = e['surah'] as int;
    return s == 0 ? e['title'] as String : 'سورة ${surahName(s)}';
  }

  void _open(Map e) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => _LessonsScreen(e: e, name: _name(e))));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تفسير ابن كثير — الحجوري')),
      body: FutureBuilder<List<dynamic>>(
        future: f,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (snap.hasError) {
            return const Center(child: Padding(padding: EdgeInsets.all(30), child: Text('تعذّر تحميل قائمة الدروس، تأكد من الإنترنت.')));
          }
          final all = snap.data!.cast<Map<String, dynamic>>();
          if (!_jumped && widget.surah != null) {
            _jumped = true;
            final m = all.where((e) => e['surah'] == widget.surah).toList();
            if (m.isNotEmpty) WidgetsBinding.instance.addPostFrameCallback((_) => _open(m.first));
          }
          final intro = all.where((e) => e['surah'] == 0).toList();
          final rest = all.where((e) => e['surah'] != 0).toList();
          return ListView(
            padding: const EdgeInsets.only(bottom: 30),
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(24, 14, 24, 6),
                child: Text('دروس الشيخ يحيى بن علي الحجوري في شرح «تفسير القرآن العظيم» لابن كثير رَحِمَهُ الله، من موقع الشيخ.',
                    textAlign: TextAlign.center, style: TextStyle(color: kGoldDeep, height: 1.8)),
              ),
              if (intro.isNotEmpty)
                GroupCard(title: 'المقدمات', children: [
                  for (final e in intro)
                    GroupTile(
                        icon: Icons.menu_book_rounded,
                        color: kGoldDeep,
                        title: e['title'] as String,
                        subtitle: '${ar((e['lessons'] as List).length)} درسًا',
                        onTap: () => _open(e)),
                ]),
              GroupCard(title: 'السور', children: [
                for (final e in rest)
                  ListTile(
                    leading: SurahNumberBadge(e['surah'] as int),
                    title: Text(_name(e), style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('${ar((e['lessons'] as List).length)} درسًا', style: const TextStyle(fontSize: 12.5)),
                    trailing: const Icon(Icons.chevron_left_rounded),
                    onTap: () => _open(e),
                  ),
              ]),
            ],
          );
        },
      ),
    );
  }
}

class _LessonsScreen extends StatelessWidget {
  final Map e;
  final String name;
  const _LessonsScreen({required this.e, required this.name});

  @override
  Widget build(BuildContext context) {
    final ls = (e['lessons'] as List).cast<Map<String, dynamic>>();
    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: ListView.separated(
        padding: const EdgeInsets.only(bottom: 30),
        itemCount: ls.length,
        separatorBuilder: (_, __) => const Divider(height: 1, indent: 60),
        itemBuilder: (context, i) {
          final l = ls[i];
          final mb = ((l['z'] as num? ?? 0) / 1048576).round();
          return ListTile(
            leading: CircleAvatar(
                radius: 17,
                backgroundColor: kEmerald.withValues(alpha: 0.12),
                child: Text(ar(i + 1), style: const TextStyle(color: kEmerald, fontWeight: FontWeight.w700, fontSize: 13))),
            title: Text(l['t'] as String, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(height: 1.6)),
            subtitle: mb > 0 ? Text('${ar(mb)} ميجابايت', style: const TextStyle(fontSize: 12)) : null,
            trailing: const Icon(Icons.play_circle_outline_rounded, color: kEmerald),
            onTap: () {
              // the sheikh's site first; if it does not answer, the copy kept in the app's store
              AudioCtl.I.playUrl(l['u'] as String, 'تفسير ابن كثير — الحجوري', '$name • الدرس ${ar(i + 1)}',
                  backup: '$kStore/hajuri-tafsir-${(e['surah'] as int).toString().padLeft(3, '0')}/${l['id']}.mp3');
              toast(context, 'تشغيل الدرس ${ar(i + 1)}');
            },
          );
        },
      ),
    );
  }
}
