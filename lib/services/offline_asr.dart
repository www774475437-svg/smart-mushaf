import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as so;

/// Speech recognition that runs inside the phone, with no internet.
///
/// The models are Whisper «base» and «tiny» trained on Quran recitation by Tarteel
/// (tarteel-ai/whisper-base-ar-quran and whisper-tiny-ar-quran, Apache-2.0), run by sherpa-onnx.
/// A model is downloaded once from the app's store and kept on the phone. They write the
/// words with their tashkeel, which is how tashkeel mistakes are noticed. The microphone is cut into
/// stretches of speech; while a stretch is still being said it is written down again and again
/// (about once a second), so the words appear while the reciter is reading.
class OfflineAsr {
  OfflineAsr._();
  static final OfflineAsr I = OfflineAsr._();

  static const String _store = 'https://github.com/www774475437-svg/smart-mushaf-store/releases/download';

  /// The two models: «base» hears best, «tiny» is about twice as fast (for older phones).
  /// file name -> [release, smallest size that counts as a complete download]
  static const Map<String, Map<String, List<Object>>> models = {
    // «ctc» is Abdou/quran-asr-tiny (MIT): small and many times faster than real time. It comes
    // inside the app, so reciting works with no download and no internet from the first minute.
    'ctc': {
      'model.int8.onnx': ['asr-quran-ctc', 18000000],
      'tokens.txt': ['asr-quran-ctc', 100],
      'silero_vad.onnx': ['asr-quran-base', 500000],
    },
    'base': {
      'encoder.int8.onnx': ['asr-quran-base', 25000000],
      'decoder.int8.onnx': ['asr-quran-base', 120000000],
      'tokens.txt': ['asr-quran-base', 500000],
      'silero_vad.onnx': ['asr-quran-base', 500000],
    },
    'tiny': {
      'encoder.int8.onnx': ['asr-quran-tiny', 11000000],
      'decoder.int8.onnx': ['asr-quran-tiny', 80000000],
      'tokens.txt': ['asr-quran-tiny', 500000],
      'silero_vad.onnx': ['asr-quran-base', 500000],
    },
  };
  static const Map<String, int> totalBytes = {'ctc': 19500000, 'base': 161200000, 'tiny': 104300000};

  static bool get supported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// The model the next listening session uses.
  String kind = 'ctc';

  Future<String> _dir(String k) async {
    final d = Directory('${(await getApplicationSupportDirectory()).path}/${k == 'base' ? 'asr' : 'asr_$k'}');
    if (!await d.exists()) await d.create(recursive: true);
    return d.path;
  }

  /// Copies the model that ships inside the app to where the engine can read it (once).
  Future<void> _unpack() async {
    try {
      final d = await _dir('ctc');
      for (final e in models['ctc']!.entries) {
        final f = File('$d/${e.key}');
        if (await f.exists() && await f.length() >= (e.value[1] as int)) continue;
        final b = await rootBundle.load('assets/asr/${e.key}');
        await f.writeAsBytes(b.buffer.asUint8List(b.offsetInBytes, b.lengthInBytes), flush: true);
      }
    } catch (_) {}
  }

  Future<bool> installed(String k) async {
    if (!supported) return false;
    if (k == 'ctc') await _unpack();
    try {
      final d = await _dir(k);
      for (final e in models[k]!.entries) {
        final f = File('$d/${e.key}');
        if (!await f.exists() || await f.length() < (e.value[1] as int)) return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> download(String k, void Function(double) onProgress) async {
    final d = await _dir(k);
    final total = totalBytes[k]!;
    var done = 0;
    final client = http.Client();
    try {
      for (final e in models[k]!.entries) {
        final need = e.value[1] as int;
        final f = File('$d/${e.key}');
        if (await f.exists() && await f.length() >= need) {
          done += await f.length();
          onProgress((done / total).clamp(0.0, 1.0));
          continue;
        }
        final tmp = File('${f.path}.part');
        final r = await client.send(http.Request('GET', Uri.parse('$_store/${e.value[0]}/${e.key}')));
        if (r.statusCode != 200) throw Exception('http ${r.statusCode}');
        final sink = tmp.openWrite();
        var last = 0;
        await for (final chunk in r.stream) {
          sink.add(chunk);
          done += chunk.length;
          if (done - last > 400000) {
            last = done;
            onProgress((done / total).clamp(0.0, 1.0));
          }
        }
        await sink.close();
        if (await tmp.length() < need) throw Exception('short file');
        await tmp.rename(f.path);
      }
      onProgress(1);
    } finally {
      client.close();
    }
  }

  Future<void> remove(String k) async {
    await close();
    try {
      await Directory(await _dir(k)).delete(recursive: true);
    } catch (_) {}
  }

  /// Chooses the model; a loaded one of the other kind is let go.
  Future<void> use(String k) async {
    if (k == kind) return;
    await close();
    kind = k;
  }

  // ---------------- a listening session ----------------
  Isolate? _iso;
  SendPort? _to;
  ReceivePort? _from;
  final AudioRecorder _rec = AudioRecorder();
  StreamSubscription<Uint8List>? _mic;
  void Function(String text, bool isFinal)? _onText;
  bool running = false;

  /// True while a stretch of speech is being written down.
  final ValueNotifier<bool> busy = ValueNotifier<bool>(false);

  /// Loads the model (once) and opens the microphone. Each recognised stretch goes to [onText].
  /// Returns a message when it cannot start, null when it started.
  Future<String?> start(void Function(String text, bool isFinal) onText) async {
    if (!supported) return 'التسميع بلا إنترنت يعمل في التطبيق، لا في الموقع.';
    if (!await installed(kind)) return 'حمّل نموذج الصوت أولًا.';
    if (!await _rec.hasPermission()) return 'اسمح للتطبيق باستخدام الميكروفون.';
    _onText = onText;
    if (_iso == null) {
      final d = await _dir(kind);
      final from = ReceivePort();
      _from = from;
      final ready = Completer<String?>();
      from.listen((m) {
        if (m is SendPort) {
          _to = m;
          if (!ready.isCompleted) ready.complete(null);
        } else if (m is List && m[0] == 'error') {
          if (!ready.isCompleted) ready.complete('تعذّر تشغيل نموذج الصوت على هذا الجهاز.');
        } else if (m is List && m[0] == 'busy') {
          busy.value = m[1] as bool;
        } else if (m is List && (m[0] == 'p' || m[0] == 'f')) {
          final t = (m[1] as String).trim();
          if (running && (t.isNotEmpty || m[0] == 'f')) _onText?.call(t, m[0] == 'f');
        }
      });
      try {
        _iso = await Isolate.spawn(_worker, [from.sendPort, d, kind]);
      } catch (_) {
        return 'تعذّر تشغيل نموذج الصوت على هذا الجهاز.';
      }
      final e = await ready.future.timeout(const Duration(seconds: 60), onTimeout: () => 'تأخّر تحميل نموذج الصوت.');
      if (e != null) {
        await close();
        return e;
      }
    }
    try {
      final s = await _rec.startStream(const RecordConfig(encoder: AudioEncoder.pcm16bits, sampleRate: 16000, numChannels: 1));
      _mic = s.listen((bytes) {
        final n = bytes.length ~/ 2;
        final bd = ByteData.sublistView(bytes);
        final f = Float32List(n);
        for (var i = 0; i < n; i++) {
          f[i] = bd.getInt16(i * 2, Endian.little) / 32768.0;
        }
        _to?.send(f);
      });
    } catch (_) {
      return 'تعذّر فتح الميكروفون.';
    }
    running = true;
    return null;
  }

  /// Closes the microphone; what was said last is still written down. The model stays loaded.
  Future<void> pause() async {
    running = false;
    await _mic?.cancel();
    _mic = null;
    try {
      await _rec.stop();
    } catch (_) {}
    _to?.send('reset');
    busy.value = false;
  }

  /// Frees the model.
  Future<void> close() async {
    await pause();
    _to?.send('stop');
    _to = null;
    _from?.close();
    _from = null;
    _iso?.kill(priority: Isolate.beforeNextEvent);
    _iso = null;
  }
}

/// Runs away from the screen's thread: cuts the sound into stretches of speech and writes each down.
void _worker(List<dynamic> args) {
  final out = args[0] as SendPort;
  final dir = args[1] as String;
  final ctc = args[2] == 'ctc';
  // the fast model writes what is being said three times a second
  final minStep = ctc ? 4800 : 9600, minLen = ctc ? 6400 : 11200;
  late so.OfflineRecognizer rec;
  try {
    so.initBindings();
    rec = so.OfflineRecognizer(so.OfflineRecognizerConfig(
      model: ctc
          ? so.OfflineModelConfig(
              zipformerCtc: so.OfflineZipformerCtcModelConfig(model: '$dir/model.int8.onnx'),
              tokens: '$dir/tokens.txt',
              numThreads: 2,
              debug: false,
            )
          : so.OfflineModelConfig(
              whisper: so.OfflineWhisperModelConfig(
                  encoder: '$dir/encoder.int8.onnx', decoder: '$dir/decoder.int8.onnx', language: 'ar', task: 'transcribe'),
              tokens: '$dir/tokens.txt',
              modelType: 'whisper',
              numThreads: 4,
              debug: false,
            ),
    ));
  } catch (e) {
    out.send(['error', '$e']);
    return;
  }
  const win = 512;
  var pending = Float32List(0);
  final gate = _Gate();
  var lastPartial = 0, step = minStep; // samples

  String write(Float32List samples) {
    final st = rec.createStream();
    st.acceptWaveform(samples: samples, sampleRate: 16000);
    rec.decode(st);
    final text = rec.getResult(st).text;
    st.free();
    return text;
  }

  void finish(Float32List seg) {
    lastPartial = 0;
    if (seg.length < 4000) {
      out.send(['f', '']);
      return;
    }
    out.send(['busy', true]);
    try {
      out.send(['f', write(seg)]);
    } catch (_) {}
    out.send(['busy', false]);
  }

  // the stretch being said now is written down before it ends
  void partial() {
    final n = gate.cur.length * win;
    if (!gate.on || n < minLen || n - lastPartial < step) return;
    lastPartial = n;
    final t0 = DateTime.now();
    try {
      out.send(['p', write(gate.samples())]);
    } catch (_) {}
    // a slow phone writes less often, so it never falls behind the reciter
    final ms = DateTime.now().difference(t0).inMilliseconds;
    step = (ms * 16 * 1.4).round().clamp(minStep, 48000);
  }

  final port = ReceivePort();
  port.listen((m) {
    if (m is Float32List) {
      final all = Float32List(pending.length + m.length)
        ..setAll(0, pending)
        ..setAll(pending.length, m);
      var i = 0;
      while (i + win <= all.length) {
        for (final seg in gate.feed(Float32List.fromList(all.sublist(i, i + win)))) {
          finish(seg);
        }
        i += win;
      }
      pending = Float32List.fromList(all.sublist(i));
      partial();
    } else if (m == 'reset') {
      for (final seg in gate.flush()) {
        finish(seg);
      }
      pending = Float32List(0);
    } else if (m == 'stop') {
      try {
        rec.free();
      } catch (_) {}
      port.close();
    }
  });
  out.send(port.sendPort);
}

/// Finds the stretches of recitation in the microphone's sound by loudness. The usual voice
/// detector (Silero) was made for talking: on long melodic recitation it went deaf for minutes
/// (measured on whole pages by 16 reciters). The same rules are in tool/gate.py, which the
/// measurements run on.
class _Gate {
  static const start = 2, stop = 11, preN = 8, maxF = 280, look = 78;
  static const ratio = 2.0, low = 0.0015, under = 0.05;
  double? floor;
  double peak = 0;
  bool on = false;
  int run = 0, quiet = 0;
  List<Float32List> pre = [], cur = [];
  List<double> lv = [];

  Float32List _join(List<Float32List> parts) {
    final all = Float32List(parts.fold<int>(0, (a, b) => a + b.length));
    var o = 0;
    for (final c in parts) {
      all.setAll(o, c);
      o += c.length;
    }
    return all;
  }

  Float32List samples() => _join(cur);

  /// Takes one frame of 512 samples; returns the stretches that ended with it (usually none).
  List<Float32List> feed(Float32List w) {
    var sum = 0.0;
    for (final x in w) {
      sum += x * x;
    }
    final e = sqrt(sum / w.length);
    final f = floor;
    if (f == null) {
      floor = e;
    } else if (e < f) {
      floor = f * 0.9 + e * 0.1;
    } else {
      floor = f * 1.0005;
    }
    peak = max(e, peak * 0.9995);
    final loud = e > max(max(floor! * ratio, low), peak * under);
    final out = <Float32List>[];
    if (!on) {
      pre.add(w);
      if (pre.length > preN) pre.removeAt(0);
      run = loud ? run + 1 : 0;
      if (run >= start) {
        on = true;
        quiet = 0;
        cur = List.of(pre);
        lv = List.filled(pre.length, 0.0, growable: true);
        pre = [];
        run = 0;
      }
      return out;
    }
    cur.add(w);
    lv.add(e);
    quiet = loud ? 0 : quiet + 1;
    if (quiet >= stop) {
      out.add(_join(cur));
      on = false;
      cur = [];
      lv = [];
    } else if (cur.length >= maxF) {
      // a long stretch is cut at the quietest moment of its last 2.5 seconds
      final n = cur.length;
      var k = n - look;
      var best = double.infinity;
      for (var i = n - look; i < n - 3; i++) {
        final v = lv[i] + lv[i + 1] + lv[i + 2];
        if (v < best) {
          best = v;
          k = i;
        }
      }
      k++;
      out.add(_join(cur.sublist(0, k)));
      cur = cur.sublist(k);
      lv = lv.sublist(k);
    }
    return out;
  }

  List<Float32List> flush() {
    final out = on && cur.isNotEmpty ? [_join(cur)] : <Float32List>[];
    on = false;
    cur = [];
    lv = [];
    return out;
  }
}
