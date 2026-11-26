import 'package:flutter/material.dart';

import '../data/quran.dart';
import '../data/reciters.dart';
import '../data/surah_names.dart';
import '../services/audio.dart';
import 'common.dart';

class RecitersScreen extends StatefulWidget {
  final bool pick;
  const RecitersScreen({super.key, this.pick = false});
  @override
  State<RecitersScreen> createState() => _RecitersScreenState();
}

class _RecitersScreenState extends State<RecitersScreen> {
  String q = '';

  void _choose(Reciter r) {
    Reciters.I.select(r.id);
    toast(context, 'اخترت: ${r.name}');
    if (widget.pick) Navigator.pop(context);
  }

  bool _match(Reciter r) => q.isEmpty || normalizeAr(r.name).contains(normalizeAr(q));

  Widget _tile(Reciter r) {
    final sel = Reciters.I.currentId == r.id;
    return ListTile(
      onTap: () => _choose(r),
      leading: CircleAvatar(
        backgroundColor: sel ? kEmerald : kEmerald.withValues(alpha: 0.1),
        child: Icon(Icons.mic_rounded, color: sel ? Colors.white : kEmerald),
      ),
      title: Text(r.name, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(r.sub.isEmpty ? (r.perAyah ? 'آية بآية' : 'سورة كاملة') : r.sub, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (sel) const Icon(Icons.check_circle_rounded, color: kEmerald),
          IconButton(
            tooltip: 'السور والتحميل',
            icon: const Icon(Icons.download_for_offline_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReciterSurahsScreen(r: r))),
          ),
          if (r.custom)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () => Reciters.I.removeCustom(r.id),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('القرّاء'),
          actions: [
            IconButton(
              tooltip: 'إضافة قارئ',
              icon: const Icon(Icons.person_add_alt_1_rounded),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AddReciterScreen())),
            ),
          ],
          bottom: const TabBar(tabs: [
            Tab(text: 'مع تظليل الآية'),
            Tab(text: 'جميع القرّاء'),
            Tab(text: 'قرّائي'),
          ]),
        ),
        body: ListenableBuilder(
          listenable: Reciters.I,
          builder: (context, _) {
            final rs = Reciters.I;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'ابحث عن قارئ…',
                      prefixIcon: const Icon(Icons.search_rounded),
                      filled: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    ),
                    onChanged: (v) => setState(() => q = v),
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      ListView(
                        children: [
                          const Padding(
                            padding: EdgeInsets.fromLTRB(20, 4, 20, 4),
                            child: Text('هؤلاء القرّاء تُظلَّل معهم الآية أثناء التلاوة، ويمكن تكرار الآية والمقطع.',
                                style: TextStyle(fontSize: 12.5)),
                          ),
                          if (rs.timed.isNotEmpty) ...[
                            const Padding(
                              padding: EdgeInsets.fromLTRB(20, 10, 20, 2),
                              child: Text('تلاوة متصلة بلا توقف (مع تظليل الآية)',
                                  style: TextStyle(fontWeight: FontWeight.w700, color: kGoldDeep)),
                            ),
                            ...rs.timed.where(_match).map(_tile),
                            const Padding(
                              padding: EdgeInsets.fromLTRB(20, 14, 20, 2),
                              child: Text('آية بآية (تصلح لتكرار الآية للحفظ)',
                                  style: TextStyle(fontWeight: FontWeight.w700, color: kGoldDeep)),
                            ),
                          ] else if (rs.loadingTimed)
                            const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator()),
                          ...rs.perAyah.where(_match).map(_tile),
                        ],
                      ),
                      _AllTab(match: _match, tile: _tile),
                      ListView(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: FilledButton.icon(
                              onPressed: () => Navigator.of(context)
                                  .push(MaterialPageRoute(builder: (_) => const AddReciterScreen())),
                              icon: const Icon(Icons.add_rounded),
                              label: const Text('إضافة قارئ وصوته'),
                              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                            ),
                          ),
                          if (rs.custom.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(24),
                              child: Text('لم تُضف قرّاء بعد.', textAlign: TextAlign.center),
                            ),
                          ...rs.custom.where(_match).map(_tile),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _AllTab extends StatefulWidget {
  final bool Function(Reciter) match;
  final Widget Function(Reciter) tile;
  const _AllTab({required this.match, required this.tile});
  @override
  State<_AllTab> createState() => _AllTabState();
}

class _AllTabState extends State<_AllTab> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => Reciters.I.loadAll());
  }

  @override
  Widget build(BuildContext context) {
    final rs = Reciters.I;
    if (rs.all.isEmpty) {
      if (rs.loadingAll) return const Center(child: CircularProgressIndicator());
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(rs.allError ?? 'جارٍ التحميل…', textAlign: TextAlign.center),
              const SizedBox(height: 10),
              FilledButton(onPressed: () => rs.loadAll(force: true), child: const Text('أعد المحاولة')),
            ],
          ),
        ),
      );
    }
    final list = rs.all.where(widget.match).toList();
    return ListView.builder(
      itemCount: list.length + 1,
      itemBuilder: (_, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
            child: Text('${ar(rs.all.length)} تلاوة (سورة كاملة). اكتب اسم القارئ في البحث.',
                style: const TextStyle(fontSize: 12.5)),
          );
        }
        return widget.tile(list[i - 1]);
      },
    );
  }
}

/// Surahs of one reciter: play or download for offline listening.
class ReciterSurahsScreen extends StatelessWidget {
  final Reciter r;
  const ReciterSurahsScreen({super.key, required this.r});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(r.name)),
      body: ListenableBuilder(
        listenable: AudioCtl.I,
        builder: (context, _) {
          final a = AudioCtl.I;
          return ListView.builder(
            itemCount: 114,
            itemBuilder: (_, i) {
              final s = i + 1;
              final has = r.hasSurah(s);
              final key = '${r.id}|$s';
              final prog = a.downloads[key];
              final done = has && a.isSurahDownloaded(r, s);
              return ListTile(
                enabled: has,
                leading: SurahNumberBadge(s),
                title: Text('سورة ${surahName(s)}'),
                subtitle: Text(has ? (done ? 'محمّلة • تعمل بدون إنترنت' : 'آياتها ${ar(QuranData.I.surahCount[s])}') : 'غير متوفرة'),
                onTap: has
                    ? () {
                        Reciters.I.select(r.id);
                        a.playSurah(s, reciter: r);
                        toast(context, 'تشغيل سورة ${surahName(s)}');
                      }
                    : null,
                trailing: !has
                    ? null
                    : prog != null
                        ? SizedBox(width: 26, height: 26, child: CircularProgressIndicator(value: prog, strokeWidth: 3))
                        : done
                            ? IconButton(
                                icon: const Icon(Icons.delete_outline_rounded),
                                onPressed: () => a.deleteSurah(r, s),
                              )
                            : IconButton(
                                icon: const Icon(Icons.download_rounded),
                                onPressed: () => a.downloadSurah(r, s),
                              ),
              );
            },
          );
        },
      ),
    );
  }
}

class AddReciterScreen extends StatefulWidget {
  const AddReciterScreen({super.key});
  @override
  State<AddReciterScreen> createState() => _AddReciterScreenState();
}

class _AddReciterScreenState extends State<AddReciterScreen> {
  final _name = TextEditingController();
  final _url = TextEditingController();
  RecKind kind = RecKind.surah;

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    var url = _url.text.trim();
    if (name.isEmpty || !url.startsWith('http')) {
      toast(context, 'اكتب اسم القارئ ورابطًا صحيحًا يبدأ بـ http');
      return;
    }
    if (!url.endsWith('/')) url = '$url/';
    final r = Reciter('cu:${DateTime.now().millisecondsSinceEpoch}', name, kind, url,
        sub: kind == RecKind.ayah ? 'آية بآية (مضاف)' : 'سورة كاملة (مضاف)', custom: true);
    Reciters.I.addCustom(r);
    Reciters.I.select(r.id);
    toast(context, 'أُضيف القارئ $name');
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إضافة قارئ')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'اسم القارئ', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 14),
          const Text('نوع الملفات', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Pills<RecKind>(
            values: RecKind.values,
            selected: kind,
            label: (k) => k == RecKind.ayah ? 'آية بآية' : 'سورة كاملة',
            onChanged: (k) => setState(() => kind = k),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _url,
            textDirection: TextDirection.ltr,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(labelText: 'رابط مجلد التلاوات', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 10),
          Text(
            kind == RecKind.surah
                ? 'ضع رابط المجلد الذي فيه السور بأسماء مثل 001.mp3 و 002.mp3\nمثال: https://server8.mp3quran.net/afs/'
                : 'ضع رابط المجلد الذي فيه الآيات بأسماء مثل 001001.mp3 (السورة ثم الآية)\nمثال: https://everyayah.com/data/Alafasy_128kbps/',
            style: const TextStyle(fontSize: 13, height: 1.7),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.check_rounded),
            label: const Text('حفظ القارئ'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          ),
        ],
      ),
    );
  }
}
