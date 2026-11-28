import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
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
  static const Map<String, int> totalBytes = {'base': 161200000, 'tiny': 104300000};

  static bool get supported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// The model the next listening session uses.
  String kind = 'base';

  Future<String> _dir(String k) async {
    final d = Directory('${(await getApplicationSupportDirectory()).path}/${k == 'base' ? 'asr' : 'asr_$k'}');
    if (!await d.exists()) await d.create(recursive: true);
    return d.path;
  }

  Future<bool> installed(String k) async {
    if (!supported) return false;
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
        _iso = await Isolate.spawn(_worker, [from.sendPort, d]);
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
  late so.OfflineRecognizer rec;
  late so.VoiceActivityDetector vad;
  try {
    so.initBindings();
    rec = so.OfflineRecognizer(so.OfflineRecognizerConfig(
      model: so.OfflineModelConfig(
        whisper: so.OfflineWhisperModelConfig(
            encoder: '$dir/encoder.int8.onnx', decoder: '$dir/decoder.int8.onnx', language: 'ar', task: 'transcribe'),
        tokens: '$dir/tokens.txt',
        modelType: 'whisper',
        numThreads: 4,
        debug: false,
      ),
    ));
    vad = so.VoiceActivityDetector(
      config: so.VadModelConfig(
        sileroVad: so.SileroVadModelConfig(
            model: '$dir/silero_vad.onnx', minSilenceDuration: 0.35, minSpeechDuration: 0.25, maxSpeechDuration: 8.0),
        numThreads: 1,
        debug: false,
      ),
      bufferSizeInSeconds: 60,
    );
  } catch (e) {
    out.send(['error', '$e']);
    return;
  }
  const win = 512;
  var pending = Float32List(0);

  // the stretch being said now, kept so it can be written down before it ends
  final cur = <Float32List>[];
  var curLen = 0, lastPartial = 0, step = 9600; // samples
  final pre = <Float32List>[]; // a little sound from before speech was noticed

  String write(Float32List samples) {
    final st = rec.createStream();
    st.acceptWaveform(samples: samples, sampleRate: 16000);
    rec.decode(st);
    final text = rec.getResult(st).text;
    st.free();
    return text;
  }

  void clearCur() {
    cur.clear();
    curLen = 0;
    lastPartial = 0;
  }

  void drain() {
    while (!vad.isEmpty()) {
      final seg = vad.front();
      vad.pop();
      clearCur();
      if (seg.samples.length < 4000) {
        out.send(['f', '']);
        continue;
      }
      out.send(['busy', true]);
      try {
        out.send(['f', write(seg.samples)]);
      } catch (_) {}
      out.send(['busy', false]);
    }
  }

  void partial() {
    if (curLen < 11200 || curLen - lastPartial < step) return;
    lastPartial = curLen;
    final all = Float32List(curLen);
    var o = 0;
    for (final c in cur) {
      all.setAll(o, c);
      o += c.length;
    }
    final t0 = DateTime.now();
    try {
      out.send(['p', write(all)]);
    } catch (_) {}
    // a slow phone writes less often, so it never falls behind the reciter
    final ms = DateTime.now().difference(t0).inMilliseconds;
    step = (ms * 16 * 1.4).round().clamp(9600, 48000);
  }

  final port = ReceivePort();
  port.listen((m) {
    if (m is Float32List) {
      final all = Float32List(pending.length + m.length)
        ..setAll(0, pending)
        ..setAll(pending.length, m);
      var i = 0;
      while (i + win <= all.length) {
        final w = Float32List.fromList(all.sublist(i, i + win));
        vad.acceptWaveform(w);
        if (vad.isDetected()) {
          if (cur.isEmpty) {
            for (final x in pre) {
              cur.add(x);
              curLen += x.length;
            }
            pre.clear();
          }
          cur.add(w);
          curLen += win;
        } else {
          pre.add(w);
          if (pre.length > 10) pre.removeAt(0);
        }
        i += win;
      }
      pending = Float32List.fromList(all.sublist(i));
      drain();
      partial();
    } else if (m == 'reset') {
      try {
        vad.flush();
        drain();
      } catch (_) {}
      pending = Float32List(0);
      clearCur();
      pre.clear();
    } else if (m == 'stop') {
      try {
        vad.free();
        rec.free();
      } catch (_) {}
      port.close();
    }
  });
  out.send(port.sendPort);
}
