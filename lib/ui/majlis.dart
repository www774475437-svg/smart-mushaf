import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/layout.dart';
import '../data/quran.dart';
import '../data/surah_names.dart';
import '../services/store.dart';
import 'common.dart';
import 'mushaf_lines.dart';

class Member {
  String number, name;
  bool muted;
  Member(this.number, this.name, {this.muted = false});
  Map<String, dynamic> toJson() => {'n': number, 'm': name, 'x': muted};
  static Member fromJson(Map<String, dynamic> j) =>
      Member(j['n'] as String, j['m'] as String, muted: (j['x'] as bool?) ?? false);
}

class Mahfaza {
  String id, name, sheikh;
  int branch; // 0 men, 1 women
  int capacity;
  double price;
  List<String> times;
  List<Member> members;
  List<Map<String, dynamic>> chat;
  List<Map<String, dynamic>> reports;
  bool requested;
  Mahfaza(this.id, this.name, this.sheikh, this.branch,
      {this.capacity = 50,
      this.price = 5,
      List<String>? times,
      List<Member>? members,
      List<Map<String, dynamic>>? chat,
      List<Map<String, dynamic>>? reports,
      this.requested = false})
      : times = times ?? [],
        members = members ?? [],
        chat = chat ?? [],
        reports = reports ?? [];
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'sheikh': sheikh,
        'branch': branch,
        'cap': capacity,
        'price': price,
        'times': times,
        'members': members.map((e) => e.toJson()).toList(),
        'chat': chat,
        'reports': reports,
        'req': requested,
      };
  static Mahfaza fromJson(Map<String, dynamic> j) => Mahfaza(
        j['id'] as String,
        j['name'] as String,
        j['sheikh'] as String,
        (j['branch'] as num).toInt(),
        capacity: (j['cap'] as num?)?.toInt() ?? 50,
        price: (j['price'] as num?)?.toDouble() ?? 5,
        times: List<String>.from(j['times'] as List? ?? []),
        members: (j['members'] as List? ?? []).map((e) => Member.fromJson(e as Map<String, dynamic>)).toList(),
        chat: (j['chat'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList(),
        reports: (j['reports'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList(),
        requested: (j['req'] as bool?) ?? false,
      );
}

/// Local (on this phone) store for «مجلس الحفاظ» until accounts are connected.
class MajlisStore extends ChangeNotifier {
  MajlisStore._();
  static final MajlisStore I = MajlisStore._();
  SharedPreferences? _p;
  List<Mahfaza> list = [];
  String myNumber = '';
  bool loaded = false;

  Future<void> load() async {
    if (loaded) return;
    _p = await SharedPreferences.getInstance();
    myNumber = _p!.getString('myNumber') ?? '';
    if (myNumber.isEmpty) {
      myNumber = (1000000 + math.Random().nextInt(8999999)).toString();
      _p!.setString('myNumber', myNumber);
    }
    try {
      final raw = _p!.getString('majlis');
      if (raw != null) {
        list = (jsonDecode(raw) as List).map((e) => Mahfaza.fromJson(e as Map<String, dynamic>)).toList();
      }
    } catch (_) {}
    if (list.isEmpty) list = _samples();
    loaded = true;
    notifyListeners();
  }

  List<Mahfaza> _samples() => [
        Mahfaza('s1', 'محفظة النور', 'الشيخ (مثال)', 0,
            times: ['كل يوم بعد الفجر • ٦:٠٠ ص', 'السبت والثلاثاء • ٩:٠٠ م'],
            members: [Member('4821730', 'طالب (مثال) ١'), Member('7350912', 'طالب (مثال) ٢'), Member('2194468', 'طالب (مثال) ٣')],
            chat: [
              {'from': 'الشيخ', 'text': 'حيّاكم الله، ورد اليوم من صفحة ١٠٥ إلى ١٠٧.'},
            ]),
        Mahfaza('s2', 'محفظة الهدى', 'الشيخ (مثال)', 0,
            times: ['كل يوم بعد العصر • ٤:٣٠ م'], members: [Member('5567201', 'طالب (مثال)')]),
        Mahfaza('s3', 'محفظة أسماء', 'المعلّمة (مثال)', 1,
            times: ['كل يوم • ١٠:٠٠ ص'],
            members: [Member('3312075', 'طالبة (مثال) ١'), Member('9046617', 'طالبة (مثال) ٢')]),
        Mahfaza('s4', 'محفظة عائشة', 'المعلّمة (مثال)', 1, times: ['الأحد والأربعاء • ٨:٠٠ م']),
      ];

  void save() {
    _p?.setString('majlis', jsonEncode(list.map((e) => e.toJson()).toList()));
    notifyListeners();
  }

  void add(Mahfaza m) {
    list.insert(0, m);
    save();
  }

  void remove(Mahfaza m) {
    list.remove(m);
    save();
  }
}

class MajlisScreen extends StatefulWidget {
  const MajlisScreen({super.key});
  @override
  State<MajlisScreen> createState() => _MajlisScreenState();
}

class _MajlisScreenState extends State<MajlisScreen> {
  int branch = 0;

  @override
  void initState() {
    super.initState();
    MajlisStore.I.load();
  }

  Future<void> _create() async {
    final name = TextEditingController();
    final sheikh = TextEditingController();
    var b = branch;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('إنشاء محفظة'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: name, decoration: const InputDecoration(labelText: 'اسم المحفظة (مثل: محفظة النور)')),
                TextField(controller: sheikh, decoration: const InputDecoration(labelText: 'اسم الشيخ أو المعلّمة')),
                const SizedBox(height: 14),
                Pills<int>(
                  values: const [0, 1],
                  selected: b,
                  label: (v) => v == 0 ? 'فرع الرجال' : 'فرع النساء',
                  onChanged: (v) => setD(() => b = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('إنشاء')),
          ],
        ),
      ),
    );
    if (ok == true && name.text.trim().isNotEmpty) {
      MajlisStore.I.add(Mahfaza('m${DateTime.now().millisecondsSinceEpoch}', name.text.trim(),
          sheikh.text.trim().isEmpty ? 'الشيخ' : sheikh.text.trim(), b));
      setState(() => branch = b);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('مجلس الحفاظ')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        backgroundColor: kEmerald,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('إنشاء محفظة'),
      ),
      body: ListenableBuilder(
        listenable: MajlisStore.I,
        builder: (context, _) {
          final st = MajlisStore.I;
          final items = st.list.where((m) => m.branch == branch).toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [kEmeraldDark, kEmerald]),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(children: [
                      Icon(Icons.groups_rounded, color: kGold, size: 30),
                      SizedBox(width: 10),
                      Text('سمِّع على شيخ متقن',
                          style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w700)),
                    ]),
                    const SizedBox(height: 8),
                    const Text(
                      'انضم إلى محفظة، واحضر الحلقة الصوتية في موعدها. تُفتح الصفحة أمام الجميع، والشيخ يحدّد مواضع الخطأ ثم تصلك ملاحظاته لتراجعها.',
                      style: TextStyle(color: Colors.white70, height: 1.7),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(20)),
                      child: Text('رقمك: ${st.myNumber}', style: const TextStyle(color: kGold, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: kGold.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(14)),
                child: const Text(
                  'نموذج تجريبي: المحافظ هنا أمثلة محفوظة على جوالك. الاتصال الصوتي والحسابات والاشتراك تُفعَّل لاحقًا.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, height: 1.6),
                ),
              ),
              const SizedBox(height: 14),
              Center(
                child: Pills<int>(
                  values: const [0, 1],
                  selected: branch,
                  label: (v) => v == 0 ? 'فرع الرجال' : 'فرع النساء',
                  onChanged: (v) => setState(() => branch = v),
                ),
              ),
              const SizedBox(height: 10),
              if (items.isEmpty)
                const Padding(padding: EdgeInsets.all(30), child: Text('لا توجد محافظ في هذا الفرع بعد.', textAlign: TextAlign.center)),
              for (final m in items) _card(m),
            ],
          );
        },
      ),
    );
  }

  Widget _card(Mahfaza m) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => MahfazaScreen(m: m))),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(color: kEmerald.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(16)),
                  child: Icon(m.branch == 0 ? Icons.mosque_rounded : Icons.local_library_rounded, color: kEmerald, size: 28),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(m.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16.5)),
                      Text(m.sheikh, style: const TextStyle(fontSize: 13)),
                      const SizedBox(height: 4),
                      Text(
                          '${ar(m.members.length)} من ${ar(m.capacity)} • ${m.times.isEmpty ? 'لم يُحدَّد موعد' : m.times.first}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: kGoldDeep)),
                    ],
                  ),
                ),
                Column(
                  children: [
                    Text('\$${m.price.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    const Text('شهريًّا', style: TextStyle(fontSize: 11)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MahfazaScreen extends StatefulWidget {
  final Mahfaza m;
  const MahfazaScreen({super.key, required this.m});
  @override
  State<MahfazaScreen> createState() => _MahfazaScreenState();
}

class _MahfazaScreenState extends State<MahfazaScreen> {
  final _msg = TextEditingController();
  Mahfaza get m => widget.m;

  void _save() {
    MajlisStore.I.save();
    setState(() {});
  }

  Future<String?> _ask(String title, {String hint = '', TextInputType? type}) async {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(controller: c, autofocus: true, keyboardType: type, decoration: InputDecoration(hintText: hint)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('حفظ')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(m.name),
          actions: [
            PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'name') {
                  final n = await _ask('اسم المحفظة', hint: m.name);
                  if (n != null && n.isNotEmpty) {
                    m.name = n;
                    _save();
                  }
                } else if (v == 'del') {
                  MajlisStore.I.remove(m);
                  if (mounted) Navigator.pop(context);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'name', child: Text('تعديل الاسم')),
                PopupMenuItem(value: 'del', child: Text('حذف المحفظة')),
              ],
            ),
          ],
          bottom: const TabBar(tabs: [Tab(text: 'الحلقة'), Tab(text: 'المواعيد'), Tab(text: 'الأعضاء'), Tab(text: 'المحادثة')]),
        ),
        body: TabBarView(children: [_session(), _times(), _members(), _chat()]),
      ),
    );
  }

  Widget _session() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        GroupCard(children: [
          GroupTile(icon: Icons.person_rounded, color: kEmeraldDark, title: m.sheikh, subtitle: m.branch == 0 ? 'فرع الرجال' : 'فرع النساء'),
          GroupTile(
              icon: Icons.groups_rounded,
              color: const Color(0xFF1565C0),
              title: 'الأعضاء',
              subtitle: '${ar(m.members.length)} من ${ar(m.capacity)}'),
          GroupTile(
              icon: Icons.schedule_rounded,
              color: kGoldDeep,
              title: 'الموعد القادم',
              subtitle: m.times.isEmpty ? 'لم يُحدَّد' : m.times.first),
        ]),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54), backgroundColor: kEmerald),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SessionScreen(m: m))),
            icon: const Icon(Icons.headset_mic_rounded),
            label: const Text('ادخل الحلقة (نموذج)'),
          ),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    m.requested = !m.requested;
                    _save();
                    toast(context, m.requested ? 'أُرسل طلب الانضمام (نموذج)' : 'أُلغي الطلب');
                  },
                  child: Text(m.requested ? 'طلبك قيد المراجعة' : 'طلب انضمام'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: kGold, foregroundColor: Colors.black),
                  onPressed: () => showSoon(context, title: 'الاشتراك الشهري'),
                  child: Text('اشترك \$${m.price.toStringAsFixed(0)} شهريًّا'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (m.reports.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Text('ملاحظات الشيخ السابقة', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          for (final r in m.reports.reversed.take(10))
            Card(
              elevation: 0,
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: ListTile(
                leading: const Icon(Icons.assignment_turned_in_rounded, color: kEmerald),
                title: Text('صفحة ${ar((r['page'] as num).toInt())} • ${ar((r['items'] as List).length)} ملاحظة'),
                subtitle: Text((r['items'] as List).map((e) => (e as Map)['w']).join(' ، '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontFamily: quranFont(), fontSize: 16, color: Colors.red.shade700)),
                onTap: () => showReport(context, r),
              ),
            ),
        ],
      ],
    );
  }

  Widget _times() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (var i = 0; i < m.times.length; i++)
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: ListTile(
              leading: const IconSquare(Icons.notifications_active_rounded, kGoldDeep),
              title: Text(m.times[i]),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: () {
                  m.times.removeAt(i);
                  _save();
                },
              ),
            ),
          ),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: () async {
            final t = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 6, minute: 0));
            if (t == null || !mounted) return;
            final d = await _ask('أيام الموعد', hint: 'مثال: كل يوم، أو السبت والثلاثاء');
            if (d == null) return;
            if (!mounted) return;
            m.times.add('${d.isEmpty ? 'كل يوم' : d} • ${t.format(context)}');
            _save();
          },
          icon: const Icon(Icons.add_alarm_rounded),
          label: const Text('إضافة موعد'),
        ),
        const SizedBox(height: 10),
        const Text('إشعارات المواعيد على الجوال تُفعَّل مع ربط الحسابات.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5)),
      ],
    );
  }

  Widget _members() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        FilledButton.icon(
          onPressed: () async {
            if (m.members.length >= m.capacity) {
              toast(context, 'اكتمل العدد');
              return;
            }
            final numb = await _ask('رقم الطالب (سبعة أرقام)', hint: '0000000', type: TextInputType.number);
            if (numb == null || numb.length != 7 || int.tryParse(numb) == null) {
              if (numb != null && mounted) toast(context, 'الرقم يجب أن يكون سبعة أرقام');
              return;
            }
            final name = await _ask('اسم الطالب');
            m.members.add(Member(numb, (name == null || name.isEmpty) ? 'طالب' : name));
            _save();
          },
          icon: const Icon(Icons.person_add_alt_1_rounded),
          label: const Text('إضافة طالب برقمه'),
        ),
        const SizedBox(height: 8),
        for (final mem in m.members)
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: ListTile(
              leading: CircleAvatar(
                  backgroundColor: kEmerald.withValues(alpha: 0.12), child: const Icon(Icons.person_rounded, color: kEmerald)),
              title: Text(mem.name),
              subtitle: Text('رقم ${mem.number}${mem.muted ? ' • مكتوم' : ''}'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'كتم',
                    icon: Icon(mem.muted ? Icons.mic_off_rounded : Icons.mic_rounded, color: mem.muted ? Colors.red : null),
                    onPressed: () {
                      mem.muted = !mem.muted;
                      _save();
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.person_remove_alt_1_outlined),
                    onPressed: () {
                      m.members.remove(mem);
                      _save();
                    },
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _chat() {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(14),
            children: [
              for (final c in m.chat)
                Align(
                  alignment: c['from'] == 'أنا' ? AlignmentDirectional.centerStart : AlignmentDirectional.centerEnd,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    constraints: const BoxConstraints(maxWidth: 300),
                    decoration: BoxDecoration(
                      color: c['from'] == 'أنا' ? kEmerald.withValues(alpha: 0.14) : cs.surface,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${c['from']}', style: const TextStyle(fontSize: 11.5, color: kGoldDeep, fontWeight: FontWeight.w700)),
                        Text('${c['text']}', style: const TextStyle(height: 1.6)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _msg,
                    decoration: InputDecoration(
                      hintText: 'اكتب رسالة…',
                      filled: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: () {
                    final t = _msg.text.trim();
                    if (t.isEmpty) return;
                    m.chat.add({'from': 'أنا', 'text': t});
                    _msg.clear();
                    _save();
                  },
                  icon: const Icon(Icons.send_rounded),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

void showReport(BuildContext context, Map<String, dynamic> r) {
  final items = (r['items'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        children: [
          Text('ملاحظات الشيخ • صفحة ${ar((r['page'] as num).toInt())}',
              textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
          const SizedBox(height: 10),
          for (final it in items)
            ListTile(
              leading: const Icon(Icons.error_outline_rounded, color: Colors.red),
              title: Text('${it['w']}', style: TextStyle(fontFamily: quranFont(), fontSize: 20, color: Colors.red.shade700)),
              subtitle: Text('${it['ref']}${(it['note'] as String? ?? '').isEmpty ? '' : '\n${it['note']}'}'),
            ),
        ],
      ),
    ),
  );
}

/// The live circle: the page opens for everyone, the teacher marks mistakes.
class SessionScreen extends StatefulWidget {
  final Mahfaza m;
  const SessionScreen({super.key, required this.m});
  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  int page = UserStore.I.lastPage;
  final Map<String, Map<String, dynamic>> marks = {};

  Future<void> _tapWord(String key, LWord w) async {
    if (w.end) return;
    if (marks.containsKey(key)) {
      setState(() => marks.remove(key));
      return;
    }
    final c = TextEditingController();
    final note = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(w.t, textAlign: TextAlign.center, style: TextStyle(fontFamily: quranFont(), fontSize: 26, color: Colors.red.shade700)),
        content: TextField(
          controller: c,
          decoration: const InputDecoration(hintText: 'ملاحظة للطالب (اختياري): مثل خطأ في التشكيل'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('حدِّد الخطأ')),
        ],
      ),
    );
    if (note == null) return;
    setState(() => marks[key] = {'w': w.t, 'ref': QuranData.I.ayahs[w.g].ref, 'note': note});
  }

  void _send() {
    if (marks.isEmpty) {
      toast(context, 'لم تُحدَّد أخطاء. اضغط على الكلمة التي أخطأ فيها الطالب');
      return;
    }
    final r = {'page': page, 'items': marks.values.toList(), 't': DateTime.now().millisecondsSinceEpoch};
    widget.m.reports.add(r);
    MajlisStore.I.save();
    showReport(context, r);
    setState(marks.clear);
    toast(context, 'حُفظت الملاحظات لتُرسل إلى الطالب');
  }

  @override
  Widget build(BuildContext context) {
    final q = QuranData.I;
    final ready = MushafLayout.I.ready;
    return Scaffold(
      appBar: AppBar(
        title: Text('حلقة ${widget.m.name}'),
        actions: [
          IconButton(
            tooltip: 'الاتصال الصوتي',
            icon: const Icon(Icons.mic_none_rounded),
            onPressed: () => showSoon(context, title: 'الاتصال الصوتي المباشر'),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(18)),
            child: Row(
              children: [
                IconButton(
                    onPressed: page > 1 ? () => setState(() { page--; marks.clear(); }) : null,
                    icon: const Icon(Icons.chevron_right_rounded)),
                Expanded(
                  child: GestureDetector(
                    onTap: () async {
                      final c = TextEditingController();
                      final v = await showDialog<String>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('افتح صفحة'),
                          content: TextField(controller: c, autofocus: true, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: 'رقم الصفحة من 1 إلى 604')),
                          actions: [FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('افتح'))],
                        ),
                      );
                      final n = int.tryParse(v ?? '');
                      if (n != null && n >= 1 && n <= 604) setState(() { page = n; marks.clear(); });
                    },
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('صفحة ${ar(page)} • سورة ${surahName(q.surahOfPage(page))}', style: const TextStyle(fontWeight: FontWeight.w700)),
                        Text('الصفحة مفتوحة أمام الجميع • اضغط على الكلمة لتحديد الخطأ', style: const TextStyle(fontSize: 11.5)),
                      ],
                    ),
                  ),
                ),
                IconButton(
                    onPressed: page < 604 ? () => setState(() { page++; marks.clear(); }) : null,
                    icon: const Icon(Icons.chevron_left_rounded)),
              ],
            ),
          ),
          Expanded(
            child: ready
                ? MushafLinesPage(
                    key: ValueKey('s$page'),
                    page: page,
                    showInfo: false,
                    marks: marks.keys.toSet(),
                    onWordTap: _tapWord,
                    onLongPress: (_) {},
                  )
                : const Center(child: Text('صفحات المصحف غير متوفرة في هذه النسخة')),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50), backgroundColor: kEmerald),
                onPressed: _send,
                icon: const Icon(Icons.send_rounded),
                label: Text('أرسل الملاحظات للطالب (${ar(marks.length)})'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
