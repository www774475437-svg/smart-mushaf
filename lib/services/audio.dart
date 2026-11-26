import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import '../data/quran.dart';
import '../data/reciters.dart';
import 'settings.dart';

class AudioCtl extends ChangeNotifier {
  AudioCtl._();
  static final AudioCtl I = AudioCtl._();

  final AudioPlayer player = AudioPlayer();
  String _docs = '';
  List<int> _queue = [];
  int? currentG;
  int? surahPlaying;
  bool active = false;
  String? error;
  int _lastG = -1;
  bool _continue = false;
  Reciter? playingReciter;

  // Continuous (whole surah) playback with ayah timings.
  List<List<int>>? _timing; // [ayah, startMs, endMs]
  int _timedSurah = 0;
  int? _stopAtMs;
  int? _loopFromMs;
  final Map<String, List<List<int>>> _timingCache = {};

  /// Download progress per key "reciterId|surah" (0..1).
  final Map<String, double> downloads = {};

  bool get playing => player.playing;

  Future<void> init() async {
    try {
      _docs = (await getApplicationDocumentsDirectory()).path;
    } catch (_) {}
    player.currentIndexStream.listen((i) {
      if (i != null && i >= 0 && i < _queue.length) {
        currentG = _queue[i];
        notifyListeners();
      }
    });
    player.positionStream.listen((pos) {
      final t = _timing;
      if (t == null || !active) return;
      final ms = pos.inMilliseconds;
      if (_stopAtMs != null && ms >= _stopAtMs!) {
        if (_loopFromMs != null) {
          player.seek(Duration(milliseconds: _loopFromMs!));
        } else {
          stop();
        }
        return;
      }
      for (final e in t) {
        if (e[0] >= 1 && ms >= e[1] && ms < e[2]) {
          final g = QuranData.I.gOf(_timedSurah, e[0]);
          if (g != currentG) {
            currentG = g;
            notifyListeners();
          }
          break;
        }
      }
    });
    player.playerStateStream.listen((st) {
      if (st.processingState == ProcessingState.completed) {
        _onCompleted();
      }
      notifyListeners();
    });
  }

  String _safe(String id) => id.replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '_');
  String _dir(Reciter r) => '$_docs/audio/${_safe(r.id)}';
  String localAyah(Reciter r, int s, int a) => '${_dir(r)}/${pad3(s)}${pad3(a)}.mp3';
  String localSurah(Reciter r, int s) => '${_dir(r)}/${pad3(s)}.mp3';

  AudioSource _src(String local, String url) {
    if (_docs.isNotEmpty && File(local).existsSync()) return AudioSource.file(local);
    return AudioSource.uri(Uri.parse(url));
  }

  bool isSurahDownloaded(Reciter r, int s) {
    if (_docs.isEmpty) return false;
    if (r.perAyah) {
      final q = QuranData.I;
      return File(localAyah(r, s, q.surahCount[s])).existsSync() && File(localAyah(r, s, 1)).existsSync();
    }
    return File(localSurah(r, s)).existsSync();
  }

  /// Plays ayahs [fromG..toG] with the current reciter.
  Future<void> playRange(int fromG, int toG, {bool continueAfter = false, bool forceAyah = false}) async {
    customTitle = null;
    var r = Reciters.I.current;
    if (!forceAyah && r.perAyah && AppSettings.I.repeatAyah <= 1) {
      // Prefer the continuous recording of the same reciter so the recitation sounds natural.
      final t = Reciters.I.timedFor(r);
      if (t != null) {
        await _playTimed(t, fromG, toG, continueAfter, fallback: true);
        return;
      }
    }
    final q = QuranData.I;
    error = null;
    if (r.timed) {
      if (forceAyah) {
        r = Reciters.I.perAyah.first;
      } else {
        await _playTimed(r, fromG, toG, continueAfter);
        return;
      }
    }
    _timing = null;
    if (!r.perAyah) {
      await playSurah(q.ayahs[fromG].s);
      return;
    }
    final st = AppSettings.I;
    final rep = st.repeatAyah.clamp(1, 50);
    final rng = st.repeatRange;
    final rounds = rng == 0 ? 1 : rng.clamp(1, 50);
    final children = <AudioSource>[];
    final queue = <int>[];
    for (var k = 0; k < rounds; k++) {
      for (var g = fromG; g <= toG; g++) {
        final ay = q.ayahs[g];
        if (ay.a == 1 && ay.s != 1 && ay.s != 9 && k == 0) {
          // basmala before the surah
          children.add(_src(localAyah(r, 1, 1), r.ayahUrl(1, 1)));
          queue.add(g);
        }
        for (var i = 0; i < rep; i++) {
          children.add(_src(localAyah(r, ay.s, ay.a), r.ayahUrl(ay.s, ay.a)));
          queue.add(g);
        }
      }
    }
    _queue = queue;
    _lastG = toG;
    _continue = continueAfter && rng == 1 && st.continueNext;
    surahPlaying = null;
    playingReciter = r;
    active = true;
    currentG = fromG;
    notifyListeners();
    try {
      await player.stop();
      await player.setLoopMode(rng == 0 ? LoopMode.all : LoopMode.off);
      await player.setSpeed(st.speed);
      await player.setAudioSource(ConcatenatingAudioSource(children: children), initialIndex: 0);
      player.play();
    } catch (e) {
      error = 'تعذّر تشغيل التلاوة، تأكد من الاتصال بالإنترنت';
      active = false;
      currentG = null;
      notifyListeners();
    }
  }

  Future<void> playSurah(int s, {Reciter? reciter}) async {
    final r = reciter ?? Reciters.I.current;
    final q = QuranData.I;
    error = null;
    if (r.perAyah || r.timed) {
      if (reciter != null && Reciters.I.currentId != r.id) Reciters.I.select(r.id);
      await playRange(q.surahStart[s], q.surahEndG(s), continueAfter: true);
      return;
    }
    _timing = null;
    if (!r.hasSurah(s)) {
      error = 'هذه السورة غير متوفرة بصوت هذا القارئ';
      notifyListeners();
      return;
    }
    _queue = [];
    currentG = null;
    surahPlaying = s;
    playingReciter = r;
    _continue = AppSettings.I.continueNext;
    active = true;
    notifyListeners();
    try {
      await player.stop();
      await player.setLoopMode(AppSettings.I.repeatRange == 0 ? LoopMode.one : LoopMode.off);
      await player.setSpeed(AppSettings.I.speed);
      await player.setAudioSource(_src(localSurah(r, s), r.surahUrl(s)));
      player.play();
    } catch (e) {
      error = 'تعذّر تشغيل السورة، تأكد من الاتصال بالإنترنت';
      active = false;
      surahPlaying = null;
      notifyListeners();
    }
  }

  Future<List<List<int>>?> _loadTiming(Reciter r, int s) async {
    final key = '${r.id}|$s';
    if (_timingCache.containsKey(key)) return _timingCache[key];
    File? f;
    if (_docs.isNotEmpty) f = File('$_docs/timing_${_safe(r.id)}_$s.json');
    String? body;
    try {
      if (f != null && await f.exists()) body = await f.readAsString();
    } catch (_) {}
    if (body == null) {
      try {
        final res = await http
            .get(Uri.parse('https://mp3quran.net/api/v3/ayat_timing?surah=$s&read=${r.readId}'))
            .timeout(const Duration(seconds: 25));
        if (res.statusCode == 200) {
          body = utf8.decode(res.bodyBytes);
          try {
            await f?.writeAsString(body);
          } catch (_) {}
        }
      } catch (_) {}
    }
    if (body == null) return null;
    try {
      final j = jsonDecode(body);
      final list = j is List ? j : ((j as Map)['data'] ?? j['timing'] ?? []) as List;
      final out = <List<int>>[];
      for (final e in list) {
        final m = e as Map<String, dynamic>;
        out.add([
          (m['ayah'] as num).toInt(),
          (m['start_time'] as num).toInt(),
          (m['end_time'] as num).toInt(),
        ]);
      }
      if (out.isEmpty) return null;
      _timingCache[key] = out;
      return out;
    } catch (_) {
      return null;
    }
  }

  Future<void> _playTimed(Reciter r, int fromG, int toG, bool continueAfter, {bool fallback = false}) async {
    final q = QuranData.I;
    final st = AppSettings.I;
    final s = q.ayahs[fromG].s;
    final a1 = q.ayahs[fromG].a;
    final a2 = q.ayahs[toG].s == s ? q.ayahs[toG].a : q.surahCount[s];
    _queue = [];
    surahPlaying = null;
    playingReciter = r;
    active = true;
    currentG = fromG;
    _lastG = q.gOf(s, a2);
    _continue = continueAfter && st.repeatRange == 1 && st.continueNext;
    notifyListeners();
    final t = await _loadTiming(r, s);
    if (t == null && fallback) {
      await playRange(fromG, toG, continueAfter: continueAfter, forceAyah: true);
      return;
    }
    if (t == null) {
      error = 'تعذّر تحميل توقيت الآيات لهذا القارئ، تأكد من الإنترنت أو اختر قارئًا آخر';
      active = false;
      currentG = null;
      notifyListeners();
      return;
    }
    int startOf(int a) {
      for (final e in t) {
        if (e[0] == a) return e[1];
      }
      return 0;
    }

    int endOf(int a) {
      for (final e in t) {
        if (e[0] == a) return e[2];
      }
      return 1 << 30;
    }

    final whole = a2 >= q.surahCount[s];
    final from = a1 <= 1 ? 0 : startOf(a1);
    try {
      await player.stop();
      _timing = null;
      await player.setLoopMode(st.repeatRange == 0 && whole && a1 <= 1 ? LoopMode.one : LoopMode.off);
      await player.setSpeed(st.speed);
      await player.setAudioSource(_src(localSurah(r, s), r.surahUrl(s)),
          initialPosition: Duration(milliseconds: from));
      _timedSurah = s;
      _stopAtMs = whole ? null : endOf(a2);
      _loopFromMs = st.repeatRange == 0 && !whole ? from : null;
      _timing = t;
      player.play();
    } catch (e) {
      error = 'تعذّر تشغيل التلاوة، تأكد من الاتصال بالإنترنت';
      active = false;
      currentG = null;
      _timing = null;
      notifyListeners();
    }
  }

  Future<void> _seekAyah(int delta) async {
    final t = _timing;
    if (t == null) return;
    final cur = currentG == null ? 1 : QuranData.I.ayahs[currentG!].a;
    final target = cur + delta;
    for (final e in t) {
      if (e[0] == target) {
        await player.seek(Duration(milliseconds: e[1]));
        return;
      }
    }
  }

  void _onCompleted() {
    final cont = _continue;
    final r = playingReciter;
    final q = QuranData.I;
    if (cont && r != null) {
      if (surahPlaying != null) {
        var next = surahPlaying! + 1;
        while (next <= 114 && !r.hasSurah(next)) {
          next++;
        }
        if (next <= 114) {
          playSurah(next, reciter: r);
          return;
        }
      } else if (_lastG >= 0 && _lastG < 6235) {
        final nextG = _lastG + 1;
        final s = q.ayahs[nextG].s;
        playRange(nextG, q.surahEndG(s), continueAfter: true);
        return;
      }
    }
    active = false;
    currentG = null;
    surahPlaying = null;
    player.stop();
    notifyListeners();
  }

  /// Plays any single recording (e.g. a recorded tafsir lesson).
  String? customTitle, customSub;
  Future<void> playUrl(String url, String title, String sub) async {
    error = null;
    _timing = null;
    _queue = [];
    _continue = false;
    currentG = null;
    surahPlaying = null;
    customTitle = title;
    customSub = sub;
    active = true;
    notifyListeners();
    try {
      await player.stop();
      await player.setLoopMode(LoopMode.off);
      await player.setSpeed(AppSettings.I.speed);
      await player.setAudioSource(AudioSource.uri(Uri.parse(url.replaceFirst('http://', 'https://'))));
      player.play();
    } catch (e) {
      error = 'تعذّر تشغيل التسجيل، تأكد من الاتصال بالإنترنت';
      active = false;
      customTitle = null;
      notifyListeners();
    }
  }

  Future<void> toggle() async {
    if (player.playing) {
      await player.pause();
    } else {
      player.play();
    }
    notifyListeners();
  }

  Future<void> stop() async {
    customTitle = null;
    _continue = false;
    _timing = null;
    await player.stop();
    active = false;
    currentG = null;
    surahPlaying = null;
    notifyListeners();
  }

  Future<void> next() async {
    if (_timing != null) {
      await _seekAyah(1);
      return;
    }
    if (surahPlaying != null) {
      if (surahPlaying! < 114) await playSurah(surahPlaying! + 1, reciter: playingReciter);
      return;
    }
    if (player.hasNext) {
      final cur = currentG;
      // skip repeats of the same ayah
      var idx = player.currentIndex ?? 0;
      while (idx < _queue.length - 1 && _queue[idx] == cur) {
        idx++;
      }
      await player.seek(Duration.zero, index: idx);
    }
  }

  Future<void> previous() async {
    if (_timing != null) {
      await _seekAyah(-1);
      return;
    }
    if (surahPlaying != null) {
      if (surahPlaying! > 1) await playSurah(surahPlaying! - 1, reciter: playingReciter);
      return;
    }
    if (_queue.isEmpty) return;
    final cur = currentG;
    var idx = (player.currentIndex ?? 0).clamp(0, _queue.length - 1);
    while (idx > 0 && _queue[idx] == cur) {
      idx--;
    }
    final target = _queue[idx];
    while (idx > 0 && _queue[idx - 1] == target) {
      idx--;
    }
    await player.seek(Duration.zero, index: idx);
  }

  Future<void> setSpeed(double v) async {
    AppSettings.I.speed = v;
    await player.setSpeed(v);
    notifyListeners();
  }

  Future<void> downloadSurah(Reciter r, int s) async {
    final key = '${r.id}|$s';
    if (downloads.containsKey(key) || _docs.isEmpty) return;
    downloads[key] = 0;
    notifyListeners();
    try {
      await Directory(_dir(r)).create(recursive: true);
      if (r.perAyah) {
        final n = QuranData.I.surahCount[s];
        for (var a = 1; a <= n; a++) {
          final f = File(localAyah(r, s, a));
          if (!await f.exists()) {
            final res = await http.get(Uri.parse(r.ayahUrl(s, a))).timeout(const Duration(seconds: 60));
            if (res.statusCode != 200) throw Exception('http');
            await f.writeAsBytes(res.bodyBytes);
          }
          downloads[key] = a / n;
          notifyListeners();
        }
        final b = File(localAyah(r, 1, 1));
        if (!await b.exists()) {
          final res = await http.get(Uri.parse(r.ayahUrl(1, 1))).timeout(const Duration(seconds: 60));
          if (res.statusCode == 200) await b.writeAsBytes(res.bodyBytes);
        }
      } else {
        final f = File(localSurah(r, s));
        if (!await f.exists()) {
          final res = await http.get(Uri.parse(r.surahUrl(s))).timeout(const Duration(minutes: 10));
          if (res.statusCode != 200) throw Exception('http');
          await f.writeAsBytes(res.bodyBytes);
        }
      }
    } catch (_) {
      error = 'تعذّر تحميل السورة';
    }
    downloads.remove(key);
    notifyListeners();
  }

  Future<void> deleteSurah(Reciter r, int s) async {
    try {
      if (r.perAyah) {
        final n = QuranData.I.surahCount[s];
        for (var a = 1; a <= n; a++) {
          final f = File(localAyah(r, s, a));
          if (await f.exists()) await f.delete();
        }
      } else {
        final f = File(localSurah(r, s));
        if (await f.exists()) await f.delete();
      }
    } catch (_) {}
    notifyListeners();
  }
}
