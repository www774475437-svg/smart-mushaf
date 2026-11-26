import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

String pad3(int n) => n.toString().padLeft(3, '0');

enum RecKind { ayah, surah }

class Reciter {
  final String id, name, sub;
  final RecKind kind;
  final String base;
  final List<int>? surahs;
  final bool custom;
  const Reciter(this.id, this.name, this.kind, this.base, {this.sub = '', this.surahs, this.custom = false});

  String ayahUrl(int s, int a) => '$base${pad3(s)}${pad3(a)}.mp3';
  String surahUrl(int s) => '$base${pad3(s)}.mp3';
  bool hasSurah(int s) => surahs == null || surahs!.contains(s);
  bool get perAyah => kind == RecKind.ayah;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'sub': sub,
        'kind': kind.index,
        'base': base,
        'surahs': surahs,
        'custom': custom,
      };

  static Reciter fromJson(Map<String, dynamic> m) => Reciter(
        m['id'] as String,
        m['name'] as String,
        RecKind.values[(m['kind'] as int? ?? 0).clamp(0, 1)],
        m['base'] as String,
        sub: (m['sub'] as String?) ?? '',
        surahs: (m['surahs'] as List?)?.map((e) => (e as num).toInt()).toList(),
        custom: (m['custom'] as bool?) ?? false,
      );
}

const List<List<String>> _everyAyah = [
  ['Maher_AlMuaiqly_64kbps', 'ماهر المعيقلي'],
  ['Alafasy_128kbps', 'مشاري راشد العفاسي'],
  ['Abdurrahmaan_As-Sudais_192kbps', 'عبد الرحمن السديس'],
  ['Saood_ash-Shuraym_128kbps', 'سعود الشريم'],
  ['Yasser_Ad-Dussary_128kbps', 'ياسر الدوسري'],
  ['Fares_Abbad_64kbps', 'فارس عباد'],
  ['Nasser_Alqatami_128kbps', 'ناصر القطامي'],
  ['Abdullaah_3awwaad_Al-Juhaynee_128kbps', 'عبد الله الجهني'],
  ['Khaalid_Abdullaah_al-Qahtaanee_192kbps', 'خالد القحطاني'],
  ['Abdul_Basit_Murattal_192kbps', 'عبد الباسط عبد الصمد (مرتل)'],
  ['Abdul_Basit_Mujawwad_128kbps', 'عبد الباسط عبد الصمد (مجود)'],
  ['Husary_128kbps', 'محمود خليل الحصري'],
  ['Husary_128kbps_Mujawwad', 'محمود خليل الحصري (مجود)'],
  ['Minshawy_Murattal_128kbps', 'محمد صديق المنشاوي'],
  ['Abu_Bakr_Ash-Shaatree_128kbps', 'أبو بكر الشاطري'],
  ['Ahmed_ibn_Ali_al-Ajamy_128kbps_ketaballah.net', 'أحمد بن علي العجمي'],
  ['Ghamadi_40kbps', 'سعد الغامدي'],
  ['Hani_Rifai_192kbps', 'هاني الرفاعي'],
  ['Hudhaify_128kbps', 'علي الحذيفي'],
  ['Muhammad_Ayyoub_128kbps', 'محمد أيوب'],
  ['Muhammad_Jibreel_128kbps', 'محمد جبريل'],
  ['Abdullah_Basfar_192kbps', 'عبد الله بصفر'],
  ['Ali_Jaber_64kbps', 'علي جابر'],
  ['Akram_AlAlaqimy_128kbps', 'أكرم العلاقمي'],
  ['Muhsin_Al_Qasim_192kbps', 'محسن القاسم'],
  ['Salaah_AbdulRahmaan_Bukhatir_128kbps', 'صلاح بو خاطر'],
  ['Mohammad_al_Tablaway_128kbps', 'محمد محمود الطبلاوي'],
  ['Mustafa_Ismail_48kbps', 'مصطفى إسماعيل'],
  ['Ibrahim_Akhdar_32kbps', 'إبراهيم الأخضر'],
  ['Ayman_Sowaid_64kbps', 'أيمن سويد'],
  ['Yaser_Salamah_128kbps', 'ياسر سلامة'],
  ['Abdullah_Matroud_128kbps', 'عبد الله المطرود'],
  ['Mahmoud_Ali_Al_Banna_32kbps', 'محمود علي البنا'],
  ['aziz_alili_128kbps', 'عزيز عليلي'],
  ['Sahl_Yassin_128kbps', 'سهل ياسين'],
];

dynamic _decode(String s) => jsonDecode(s);

class Reciters extends ChangeNotifier {
  Reciters._();
  static final Reciters I = Reciters._();

  late SharedPreferences _p;
  final List<Reciter> perAyah = [
    for (final r in _everyAyah)
      Reciter('ea:${r[0]}', r[1], RecKind.ayah, 'https://everyayah.com/data/${r[0]}/', sub: 'آية بآية'),
  ];
  List<Reciter> all = [];
  List<Reciter> custom = [];
  String _currentId = 'ea:Maher_AlMuaiqly_64kbps';
  bool loadingAll = false;
  String? allError;

  Future<void> init() async {
    _p = await SharedPreferences.getInstance();
    _currentId = _p.getString('reciter') ?? _currentId;
    try {
      final raw = _p.getString('customReciters');
      if (raw != null) {
        custom = (jsonDecode(raw) as List).map((e) => Reciter.fromJson(e as Map<String, dynamic>)).toList();
      }
    } catch (_) {}
    try {
      final dir = await getApplicationDocumentsDirectory();
      final f = File('${dir.path}/mp3quran_reciters.json');
      if (await f.exists()) {
        all = _parseAll((await compute(_decode, await f.readAsString())) as Map<String, dynamic>);
      }
    } catch (_) {}
  }

  List<Reciter> get everything => [...perAyah, ...custom, ...all];

  Reciter? byId(String id) {
    for (final r in everything) {
      if (r.id == id) return r;
    }
    return null;
  }

  Reciter get current => byId(_currentId) ?? perAyah.first;
  String get currentId => current.id;

  void select(String id) {
    _currentId = id;
    _p.setString('reciter', id);
    notifyListeners();
  }

  void addCustom(Reciter r) {
    custom.add(r);
    _saveCustom();
    notifyListeners();
  }

  void removeCustom(String id) {
    custom.removeWhere((r) => r.id == id);
    if (_currentId == id) _currentId = perAyah.first.id;
    _saveCustom();
    notifyListeners();
  }

  void _saveCustom() => _p.setString('customReciters', jsonEncode(custom.map((r) => r.toJson()).toList()));

  List<Reciter> _parseAll(Map<String, dynamic> m) {
    final out = <Reciter>[];
    for (final rec in (m['reciters'] as List? ?? const [])) {
      final rm = rec as Map<String, dynamic>;
      final name = (rm['name'] as String? ?? '').trim();
      for (final mo in (rm['moshaf'] as List? ?? const [])) {
        final mm = mo as Map<String, dynamic>;
        var server = (mm['server'] as String? ?? '').trim();
        if (server.isEmpty) continue;
        if (!server.endsWith('/')) server = '$server/';
        if (server.startsWith('http://')) server = server.replaceFirst('http://', 'https://');
        final list = (mm['surah_list'] as String? ?? '')
            .split(',')
            .map((e) => int.tryParse(e.trim()) ?? 0)
            .where((e) => e > 0)
            .toList();
        out.add(Reciter('mq:${mm['id']}', name, RecKind.surah, server,
            sub: (mm['name'] as String? ?? '').trim(), surahs: list));
      }
    }
    return out;
  }

  Future<void> loadAll({bool force = false}) async {
    if (loadingAll) return;
    if (all.isNotEmpty && !force) return;
    loadingAll = true;
    allError = null;
    notifyListeners();
    try {
      final r = await http
          .get(Uri.parse('https://mp3quran.net/api/v3/reciters?language=ar'))
          .timeout(const Duration(seconds: 40));
      if (r.statusCode != 200) throw Exception('http ${r.statusCode}');
      final body = utf8.decode(r.bodyBytes);
      final parsed = _parseAll((await compute(_decode, body)) as Map<String, dynamic>);
      if (parsed.isEmpty) throw Exception('empty');
      all = parsed;
      try {
        final dir = await getApplicationDocumentsDirectory();
        await File('${dir.path}/mp3quran_reciters.json').writeAsString(body);
      } catch (_) {}
    } catch (_) {
      allError = 'تعذّر تحميل قائمة القرّاء، تأكد من الاتصال بالإنترنت ثم أعد المحاولة';
    }
    loadingAll = false;
    notifyListeners();
  }
}
