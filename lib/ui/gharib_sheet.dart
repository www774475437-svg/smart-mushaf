import 'package:flutter/material.dart';

import '../data/gharib.dart';
import '../data/layout.dart';
import '../data/quran.dart';
import 'common.dart';

/// «غريب القرآن»: what the books say about one word, and nothing else.
Future<void> showGharibSheet(BuildContext context, LWord w, List<GharibRef> refs) {
  return showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.62,
      maxChildSize: 0.94,
      minChildSize: 0.3,
      builder: (ctx, sc) => ListView(
        controller: sc,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
        children: [
          const Text('❖ غَرِيبُ القُرْآنِ 📖',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: kGoldDeep)),
          Text(w.t, textAlign: TextAlign.center, style: const TextStyle(fontFamily: 'UthmanicHafs', fontSize: 34, height: 1.8)),
          Text(QuranData.I.ayahs[w.g].ref, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 10),
          for (final r in refs) _BookCard(r: r),
        ],
      ),
    ),
  );
}

class _BookCard extends StatefulWidget {
  final GharibRef r;
  const _BookCard({required this.r});
  @override
  State<_BookCard> createState() => _BookCardState();
}

class _BookCardState extends State<_BookCard> {
  final _mark = GlobalKey();

  @override
  void initState() {
    super.initState();
    // bring the place of this ayah into view
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = _mark.currentContext;
      if (c != null && (widget.r.at > 0 || widget.r.start > 200)) {
        Scrollable.ensureVisible(c, alignment: 0.25, duration: const Duration(milliseconds: 450));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.r;
    final cs = Theme.of(context).colorScheme;
    final ps = r.paragraphs;
    final base = TextStyle(fontSize: 16.5, height: 1.95, color: cs.onSurface, fontFamily: 'Tajawal');
    final red = base.copyWith(
        color: Colors.red.shade700, fontWeight: FontWeight.w700, backgroundColor: Colors.red.withValues(alpha: 0.08));
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kGold.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(width: 4, height: 34, decoration: BoxDecoration(color: kGold, borderRadius: BorderRadius.circular(3))),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.book, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5, color: kGoldDeep)),
                    Text('${r.author} • ${r.edition}', style: const TextStyle(fontSize: 11.5, color: Colors.grey)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
                child: Text(r.title, style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700, fontSize: 13)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // the whole entry as the book has it; what it says at this ayah is in red
          for (var i = 0; i < ps.length; i++)
            if (i == r.at && r.end > r.start && r.end <= ps[i].length)
              SelectableText.rich(
                key: _mark,
                TextSpan(style: base, children: [
                  TextSpan(text: ps[i].substring(0, r.start)),
                  TextSpan(text: ps[i].substring(r.start, r.end), style: red),
                  TextSpan(text: ps[i].substring(r.end)),
                ]),
              )
            else
              SelectableText(ps[i], style: base),
        ],
      ),
    );
  }
}
