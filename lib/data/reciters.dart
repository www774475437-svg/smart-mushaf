import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

String pad3(int n) => n.toString().padLeft(3, '0');

enum RecKind { ayah, surah, timed }

class Reciter {
  final String id, name, sub;
  final RecKind kind;
  final String base;
  final List<int>? surahs;
  final bool custom;

  /// MP3Quran read id (for whole-surah recitations that come with ayah timings).
  final int? readId;
  const Reciter(this.id, this.name, this.kind, this.base,
      {this.sub = '', this.surahs, this.custom = false, this.readId});
  bool get timed => kind == RecKind.timed;

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
        'readId': readId,
      };

  static Reciter fromJson(Map<String, dynamic> m) => Reciter(
        m['id'] as String,
        m['name'] as String,
        RecKind.values[(m['kind'] as int? ?? 0).clamp(0, 2)],
        m['base'] as String,
        sub: (m['sub'] as String?) ?? '',
        surahs: (m['surahs'] as List?)?.map((e) => (e as num).toInt()).toList(),
        custom: (m['custom'] as bool?) ?? false,
        readId: (m['readId'] as num?)?.toInt(),
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

/// Spoken translations of the meanings, ayah by ayah (EveryAyah): folder, language, reader.
const List<List<String>> _spoken = [
  ['English/Sahih_Intnl_Ibrahim_Walk_192kbps', 'الإنجليزية', 'إبراهيم ووك'],
  ['translations/urdu_shamshad_ali_khan_46kbps', 'الأردية', 'شمشاد علي خان'],
  ['translations/besim_korkut_ajet_po_ajet', 'البوسنية', 'بسيم كوركوت'],
  ['translations/azerbaijani/balayev', 'الأذرية', 'بالاييف'],
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
  /// The meanings read aloud in other languages.
  final List<Reciter> spoken = [
    for (final r in _spoken)
      Reciter('tr:${r[0]}', 'معاني القرآن ب${r[1]}', RecKind.ayah, 'https://everyayah.com/data/${r[0]}/', sub: r[2]),
  ];
  List<Reciter> all = [];
  List<Reciter> custom = [];

  /// Whole-surah recitations with ayah timings: continuous sound + ayah highlight.
  List<Reciter> timed = [];
  bool loadingTimed = false;
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
      final raw = _p.getString('timedReciters');
      if (raw != null) {
        timed = (jsonDecode(raw) as List).map((e) => Reciter.fromJson(e as Map<String, dynamic>)).toList();
      }
    } catch (_) {}
    loadTimed();
    try {
      if (kIsWeb) throw UnsupportedError('web');
      final dir = await getApplicationDocumentsDirectory();
      final f = File('${dir.path}/mp3quran_reciters.json');
      if (await f.exists()) {
        all = _parseAll((await compute(_decode, await f.readAsString())) as Map<String, dynamic>);
      }
    } catch (_) {}
  }

  List<Reciter> get everything => [...timed, ...perAyah, ...spoken, ...custom, ...all];

  Reciter? byId(String id) {
    for (final r in everything) {
      if (r.id == id) return r;
    }
    return null;
  }

  /// The continuous (whole-surah, timed) recitation of the same reciter, if there is one.
  Reciter? timedFor(Reciter r) {
    if (r.timed) return r;
    final name = r.name.split('(').first.trim();
    final parts = name.split(' ').where((e) => e.length > 2).toList();
    if (parts.isEmpty) return null;
    final murattalOnly = !r.name.contains('مجود');
    for (final t in timed) {
      if (parts.every((p) => t.name.contains(p)) && (murattalOnly ? !t.sub.contains('مجود') : true)) return t;
    }
    final last = parts.last;
    for (final t in timed) {
      if (t.name.contains(last) && t.name.contains(parts.first) && !t.sub.contains('مجود')) return t;
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

  Future<void> loadTimed({bool force = false}) async {
    if (loadingTimed || (timed.isNotEmpty && !force)) return;
    loadingTimed = true;
    try {
      final r = await http
          .get(Uri.parse('https://mp3quran.net/api/v3/ayat_timing/reads'))
          .timeout(const Duration(seconds: 30));
      if (r.statusCode == 200) {
        final j = jsonDecode(utf8.decode(r.bodyBytes));
        final list = j is List ? j : ((j as Map)['reads'] ?? j['data'] ?? []) as List;
        final out = <Reciter>[];
        for (final e in list) {
          final m = e as Map<String, dynamic>;
          var base = ((m['folder_url'] ?? m['server'] ?? '') as String).trim();
          final id = (m['id'] as num?)?.toInt();
          if (base.isEmpty || id == null) continue;
          if (!base.endsWith('/')) base = '$base/';
          if (base.startsWith('http://')) base = base.replaceFirst('http://', 'https://');
          out.add(Reciter('tm:$id', ((m['name'] ?? '') as String).trim(), RecKind.timed, base,
              sub: 'تلاوة متصلة • ${((m['rewaya'] ?? '') as String).trim()}', readId: id));
        }
        if (out.isNotEmpty) {
          timed = out;
          _p.setString('timedReciters', jsonEncode(out.map((e) => e.toJson()).toList()));
          // First run: prefer a continuous recitation.
          if (_p.getString('reciter') == null) {
            final pick = out.firstWhere((e) => e.name.contains('المعيقلي'), orElse: () => out.first);
            _currentId = pick.id;
          }
        }
      }
    } catch (_) {}
    loadingTimed = false;
    notifyListeners();
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
        if (!kIsWeb) {
          final dir = await getApplicationDocumentsDirectory();
          await File('${dir.path}/mp3quran_reciters.json').writeAsString(body);
        }
      } catch (_) {}
    } catch (_) {
      allError = 'تعذّر تحميل قائمة القرّاء، تأكد من الاتصال بالإنترنت ثم أعد المحاولة';
    }
    loadingAll = false;
    notifyListeners();
  }
}
