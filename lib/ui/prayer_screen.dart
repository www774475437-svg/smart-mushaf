import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/prayer.dart';
import 'common.dart';

class PrayerScreen extends StatefulWidget {
  const PrayerScreen({super.key});
  @override
  State<PrayerScreen> createState() => _PrayerScreenState();
}

class _PrayerScreenState extends State<PrayerScreen> {
  SharedPreferences? p;
  double? lat, lng;
  String method = 'mwl';
  bool hanafi = false;
  bool busy = false;
  String? err;
  Timer? tick;

  @override
  void initState() {
    super.initState();
    _load();
    tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    tick?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    p = await SharedPreferences.getInstance();
    setState(() {
      lat = p!.getDouble('prLat');
      lng = p!.getDouble('prLng');
      method = p!.getString('prMethod') ?? '';
      hanafi = p!.getBool('prHanafi') ?? false;
      if (method.isEmpty) method = (lng != null && lng! < -30) ? 'isna' : 'mwl';
    });
  }

  Future<void> _locate() async {
    setState(() {
      busy = true;
      err = null;
    });
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        throw Exception('denied');
      }
      final pos = await Geolocator.getCurrentPosition().timeout(const Duration(seconds: 25));
      lat = pos.latitude;
      lng = pos.longitude;
      await p?.setDouble('prLat', lat!);
      await p?.setDouble('prLng', lng!);
      if ((p?.getString('prMethod') ?? '').isEmpty) method = lng! < -30 ? 'isna' : 'mwl';
    } catch (_) {
      err = 'تعذّر تحديد الموقع. اسمح للتطبيق بمعرفة موقعك، أو أدخله يدويًّا.';
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _manual() async {
    final a = TextEditingController(text: lat?.toStringAsFixed(4) ?? '');
    final b = TextEditingController(text: lng?.toStringAsFixed(4) ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إدخال الموقع يدويًّا'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: a, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true), decoration: const InputDecoration(labelText: 'خط العرض (مثال: 42.39)')),
            TextField(controller: b, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true), decoration: const InputDecoration(labelText: 'خط الطول (مثال: -83.05)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
        ],
      ),
    );
    final x = double.tryParse(a.text.trim()), y = double.tryParse(b.text.trim());
    if (ok == true && x != null && y != null && x.abs() <= 90 && y.abs() <= 180) {
      await p?.setDouble('prLat', x);
      await p?.setDouble('prLng', y);
      setState(() {
        lat = x;
        lng = y;
      });
    }
  }

  String _hm(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    return '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'ص' : 'م'}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final has = lat != null && lng != null;
    final m = kPrayerMethods.firstWhere((e) => e.id == method, orElse: () => kPrayerMethods[1]);
    final now = DateTime.now();
    PrayerTimes? pt;
    int next = -1;
    DateTime? nextAt;
    if (has) {
      pt = PrayerTimes.compute(now, lat!, lng!, m, hanafiAsr: hanafi);
      next = pt.nextIndex(now);
      if (next >= 0) {
        nextAt = pt.times[next];
      } else {
        final tm = PrayerTimes.compute(now.add(const Duration(days: 1)), lat!, lng!, m, hanafiAsr: hanafi);
        nextAt = tm.times[0];
      }
    }
    String left = '';
    if (nextAt != null) {
      final d = nextAt.difference(now);
      left = '${d.inHours}:${(d.inMinutes % 60).toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
    }
    return Scaffold(
      appBar: AppBar(title: const Text('أوقات الصلاة')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!has)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [kEmeraldDark, kEmerald]),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                children: [
                  const Icon(Icons.location_on_outlined, color: kGold, size: 44),
                  const SizedBox(height: 8),
                  const Text('حدّد موقعك لحساب أوقات الصلاة',
                      textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  const Text('الموقع يبقى على جوالك فقط، والأوقات تُحسب بدون إنترنت.',
                      textAlign: TextAlign.center, style: TextStyle(color: Colors.white70)),
                ],
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [Color(0xFF0B4436), kEmerald, Color(0xFF167A61)]),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                children: [
                  const Text('الصلاة القادمة', style: TextStyle(color: Colors.white70)),
                  const SizedBox(height: 4),
                  Text(next >= 0 ? PrayerTimes.names[next] : 'الفجر',
                      style: const TextStyle(color: kGold, fontSize: 30, fontWeight: FontWeight.w700)),
                  Text(nextAt == null ? '' : _hm(nextAt), style: const TextStyle(color: Colors.white, fontSize: 20)),
                  const SizedBox(height: 6),
                  Text('بعد $left', textDirection: TextDirection.ltr, style: const TextStyle(color: Colors.white, fontSize: 18)),
                ],
              ),
            ),
          const SizedBox(height: 12),
          if (pt != null)
            GroupCard(children: [
              for (var i = 0; i < 6; i++)
                ListTile(
                  leading: Icon(
                      const [Icons.nights_stay_outlined, Icons.wb_twilight_outlined, Icons.wb_sunny_outlined, Icons.wb_cloudy_outlined, Icons.brightness_4_outlined, Icons.dark_mode_outlined][i],
                      color: i == next ? kGoldDeep : cs.primary),
                  title: Text(PrayerTimes.names[i],
                      style: TextStyle(fontWeight: i == next ? FontWeight.w700 : FontWeight.w500, color: i == next ? kGoldDeep : null)),
                  trailing: Text(_hm(pt.times[i]),
                      style: TextStyle(fontSize: 16, fontWeight: i == next ? FontWeight.w700 : FontWeight.w500, color: i == next ? kGoldDeep : null)),
                ),
            ]),
          if (has)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text('اتجاه القبلة: ${PrayerTimes.qibla(lat!, lng!).round()}° من الشمال', textAlign: TextAlign.center, style: const TextStyle(color: kGoldDeep)),
            ),
          if (err != null) Padding(padding: const EdgeInsets.all(10), child: Text(err!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red))),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: busy ? null : _locate,
                  icon: const Icon(Icons.my_location_rounded),
                  label: Text(busy ? 'جارٍ التحديد…' : (has ? 'تحديث موقعي' : 'حدّد موقعي')),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: OutlinedButton(onPressed: _manual, child: const Text('إدخال يدوي'))),
            ],
          ),
          const SizedBox(height: 16),
          const Text('طريقة الحساب', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Pills<String>(
            values: [for (final e in kPrayerMethods) e.id],
            selected: m.id,
            label: (id) => kPrayerMethods.firstWhere((e) => e.id == id).name,
            onChanged: (id) {
              p?.setString('prMethod', id);
              setState(() => method = id);
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('العصر على المذهب الحنفي'),
            value: hanafi,
            onChanged: (v) {
              p?.setBool('prHanafi', v);
              setState(() => hanafi = v);
            },
          ),
          const Text('الأوقات محسوبة فلكيًّا وقد تختلف دقيقة أو دقيقتين عن تقويم مسجدك.', style: TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      ),
    );
  }
}
