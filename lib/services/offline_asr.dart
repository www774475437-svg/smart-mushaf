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
/// The model is Whisper «base» trained on Quran recitation by Tarteel
/// (tarteel-ai/whisper-base-ar-quran, Apache-2.0), run by sherpa-onnx. It is downloaded once
/// (about 160 MB) from the app's store and kept on the phone. The microphone is cut into
/// stretches of speech; each stretch is written down a moment after the reciter pauses.
class OfflineAsr {
  OfflineAsr._();
  static final OfflineAsr I = OfflineAsr._();

  static const String _base = 'https://github.com/www774475437-svg/smart-mushaf-store/releases/download/asr-quran-base';

  /// file name -> smallest size that counts as a complete download
  static const Map<String, int> files = {
    'encoder.int8.onnx': 25000000,
    'decoder.int8.onnx': 120000000,
    'tokens.txt': 500000,
    'silero_vad.onnx': 500000,
  };
  static const int totalBytes = 161200000;

  static bool get supported => !kIsWeb && Platform.isAndroid;

  Future<String> _dir() async {
    final d = Directory('${(await getApplicationSupportDirectory()).path}/asr');
    if (!await d.exists()) await d.create(recursive: true);
    return d.path;
  }

  Future<bool> installed() async {
    if (!supported) return false;
    try {
      final d = await _dir();
      for (final e in files.entries) {
        final f = File('$d/${e.key}');
        if (!await f.exists() || await f.length() < e.value) return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> download(void Function(double) onProgress) async {
    final d = await _dir();
    var done = 0;
    final client = http.Client();
    try {
      for (final e in files.entries) {
        final f = File('$d/${e.key}');
        if (await f.exists() && await f.length() >= e.value) {
          done += await f.length();
          onProgress((done / totalBytes).clamp(0.0, 1.0));
          continue;
        }
        final tmp = File('${f.path}.part');
        final r = await client.send(http.Request('GET', Uri.parse('$_base/${e.key}')));
        if (r.statusCode != 200) throw Exception('http ${r.statusCode}');
        final sink = tmp.openWrite();
        var last = 0;
        await for (final chunk in r.stream) {
          sink.add(chunk);
          done += chunk.length;
          if (done - last > 400000) {
            last = done;
            onProgress((done / totalBytes).clamp(0.0, 1.0));
          }
        }
        await sink.close();
        if (await tmp.length() < e.value) throw Exception('short file');
        await tmp.rename(f.path);
      }
      onProgress(1);
    } finally {
      client.close();
    }
  }

  Future<void> remove() async {
    await close();
    try {
      await Directory(await _dir()).delete(recursive: true);
    } catch (_) {}
  }

  // ---------------- a listening session ----------------
  Isolate? _iso;
  SendPort? _to;
  ReceivePort? _from;
  final AudioRecorder _rec = AudioRecorder();
  StreamSubscription<Uint8List>? _mic;
  void Function(String)? _onText;
  bool running = false;

  /// True while a stretch of speech is being written down.
  final ValueNotifier<bool> busy = ValueNotifier<bool>(false);

  /// Loads the model (once) and opens the microphone. Each recognised stretch goes to [onText].
  /// Returns a message when it cannot start, null when it started.
  Future<String?> start(void Function(String) onText) async {
    if (!supported) return 'التسميع بلا إنترنت يعمل في تطبيق الأندرويد فقط.';
    if (!await installed()) return 'حمّل نموذج الصوت أولًا.';
    if (!await _rec.hasPermission()) return 'اسمح للتطبيق باستخدام الميكروفون.';
    _onText = onText;
    if (_iso == null) {
      final d = await _dir();
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
        } else if (m is String) {
          if (running && m.trim().isNotEmpty) _onText?.call(m.trim());
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
            model: '$dir/silero_vad.onnx', minSilenceDuration: 0.4, minSpeechDuration: 0.3, maxSpeechDuration: 10.0),
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

  void drain() {
    while (!vad.isEmpty()) {
      final seg = vad.front();
      vad.pop();
      if (seg.samples.length < 4000) continue;
      out.send(['busy', true]);
      try {
        final st = rec.createStream();
        st.acceptWaveform(samples: seg.samples, sampleRate: 16000);
        rec.decode(st);
        final text = rec.getResult(st).text;
        st.free();
        out.send(text);
      } catch (_) {}
      out.send(['busy', false]);
    }
  }

  final port = ReceivePort();
  port.listen((m) {
    if (m is Float32List) {
      final all = Float32List(pending.length + m.length)
        ..setAll(0, pending)
        ..setAll(pending.length, m);
      var i = 0;
      while (i + win <= all.length) {
        vad.acceptWaveform(Float32List.sublistView(all, i, i + win));
        i += win;
      }
      pending = Float32List.fromList(all.sublist(i));
      drain();
    } else if (m == 'reset') {
      try {
        vad.flush();
        drain();
      } catch (_) {}
      pending = Float32List(0);
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
