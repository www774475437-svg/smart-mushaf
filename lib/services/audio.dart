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
  Future<void> playRange(int fromG, int toG, {bool continueAfter = false}) async {
    final r = Reciters.I.current;
    final q = QuranData.I;
    error = null;
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
    if (r.perAyah) {
      await playRange(q.surahStart[s], q.surahEndG(s), continueAfter: true);
      return;
    }
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

  Future<void> toggle() async {
    if (player.playing) {
      await player.pause();
    } else {
      player.play();
    }
    notifyListeners();
  }

  Future<void> stop() async {
    _continue = false;
    await player.stop();
    active = false;
    currentG = null;
    surahPlaying = null;
    notifyListeners();
  }

  Future<void> next() async {
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
