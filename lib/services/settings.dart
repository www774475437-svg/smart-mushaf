import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ReadTheme { day, paper, night }

class AppSettings extends ChangeNotifier {
  AppSettings._();
  static final AppSettings I = AppSettings._();
  late SharedPreferences _p;

  Future<void> init() async {
    _p = await SharedPreferences.getInstance();
  }

  void _set(String k, Object v) {
    if (v is bool) _p.setBool(k, v);
    if (v is int) _p.setInt(k, v);
    if (v is double) _p.setDouble(k, v);
    if (v is String) _p.setString(k, v);
    notifyListeners();
  }

  ReadTheme get theme => ReadTheme.values[(_p.getInt('theme') ?? 0).clamp(0, 2)];
  set theme(ReadTheme v) => _set('theme', v.index);

  // ---- tasmee ----
  bool get tasOffline => _p.getBool('tasOffline') ?? true;
  set tasOffline(bool v) => _set('tasOffline', v);

  /// 'base' hears best, 'tiny' is faster
  String get tasModel => _p.getString('tasModel') ?? 'base';
  set tasModel(String v) => _set('tasModel', v);

  bool get tasTashkeel => _p.getBool('tasTashkeel') ?? true;
  set tasTashkeel(bool v) => _set('tasTashkeel', v);

  bool get tasVibrate => _p.getBool('tasVibrate') ?? true;
  set tasVibrate(bool v) => _set('tasVibrate', v);

  bool get tasShowHeard => _p.getBool('tasShowHeard') ?? true;
  set tasShowHeard(bool v) => _set('tasShowHeard', v);

  /// 0 forgiving, 1 normal, 2 exact
  int get tasStrict => (_p.getInt('tasStrict') ?? 1).clamp(0, 2);
  set tasStrict(int v) => _set('tasStrict', v);

  /// seconds of silence before the next word is shown by itself; 0 = never
  int get tasAutoHint => _p.getInt('tasAutoHint') ?? 0;
  set tasAutoHint(int v) => _set('tasAutoHint', v);

  bool get tasAutoNext => _p.getBool('tasAutoNext') ?? false;
  set tasAutoNext(bool v) => _set('tasAutoNext', v);

  bool get scrollMode => _p.getBool('scrollMode') ?? false;
  set scrollMode(bool v) => _set('scrollMode', v);

  double get fontSize => _p.getDouble('fontSize') ?? 23;
  set fontSize(double v) => _set('fontSize', v);

  int get autoSeconds => _p.getInt('autoSeconds') ?? 60;
  set autoSeconds(int v) => _set('autoSeconds', v);

  bool get keepAwake => _p.getBool('keepAwake') ?? true;
  set keepAwake(bool v) => _set('keepAwake', v);

  bool get followAudio => _p.getBool('followAudio') ?? true;
  set followAudio(bool v) => _set('followAudio', v);

  String get riwaya => _p.getString('riwaya') ?? 'hafs';
  set riwaya(String v) => _set('riwaya', v);

  double get speed {
    final v = _p.getDouble('speed') ?? 1.0;
    return (v == 1.25 || v == 1.5) ? v : 1.0;
  }
  set speed(double v) => _set('speed', v);

  int get repeatAyah => _p.getInt('repeatAyah') ?? 1;
  set repeatAyah(int v) => _set('repeatAyah', v);

  /// 0 means repeat without end.
  int get repeatRange => _p.getInt('repeatRange') ?? 1;
  set repeatRange(int v) => _set('repeatRange', v);

  bool get continueNext => _p.getBool('continueNext') ?? true;
  set continueNext(bool v) => _set('continueNext', v);

  String get tafsirId => _p.getString('tafsirId') ?? 'muyassar';
  set tafsirId(String v) => _set('tafsirId', v);

  bool get showTranslation => _p.getBool('showTranslation') ?? false;
  set showTranslation(bool v) => _set('showTranslation', v);

  bool get showPageFrame => _p.getBool('showPageFrame') ?? true;
  set showPageFrame(bool v) => _set('showPageFrame', v);

  String get quranFont => _p.getString('quranFont') ?? 'AmiriQuran';
  set quranFont(String v) => _set('quranFont', v);

  bool get smartReview => _p.getBool('smartReview') ?? true;
  set smartReview(bool v) => _set('smartReview', v);

  double get ttsRate => _p.getDouble('ttsRate') ?? 0.45;
  set ttsRate(double v) => _set('ttsRate', v);
}
