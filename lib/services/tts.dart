import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'settings.dart';

/// Reads tafsir text aloud with the phone's Arabic voice.
class Tts extends ChangeNotifier {
  Tts._();
  static final Tts I = Tts._();
  final FlutterTts _t = FlutterTts();
  bool speaking = false;
  String? key;
  bool _ready = false;

  List<String> _chunks(String text) {
    final parts = text.split(RegExp(r'(?<=[\.\!\?؟\n])'));
    final out = <String>[];
    var cur = StringBuffer();
    for (final p in parts) {
      if (cur.length + p.length > 2500 && cur.isNotEmpty) {
        out.add(cur.toString());
        cur = StringBuffer();
      }
      cur.write(p);
    }
    if (cur.isNotEmpty) out.add(cur.toString());
    return out.where((e) => e.trim().isNotEmpty).toList();
  }

  Future<void> speak(String text, {String? key}) async {
    await stop();
    speaking = true;
    this.key = key;
    notifyListeners();
    try {
      if (!_ready) {
        await _t.awaitSpeakCompletion(true);
        _ready = true;
      }
      await _t.setLanguage('ar');
      await _t.setSpeechRate(AppSettings.I.ttsRate);
      for (final c in _chunks(text)) {
        if (!speaking) break;
        await _t.speak(c);
      }
    } catch (_) {}
    speaking = false;
    this.key = null;
    notifyListeners();
  }

  Future<void> stop() async {
    speaking = false;
    key = null;
    try {
      await _t.stop();
    } catch (_) {}
    notifyListeners();
  }
}
