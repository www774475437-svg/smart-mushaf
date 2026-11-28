/// Follows a recitation against the words of the mushaf. Pure Dart (no Flutter), so the same
/// code that runs in the app is measured on real recitations by tool/eval_matcher.dart.

/// Removes tashkeel and unifies letter shapes (same as normalizeAr in data/quran.dart).
String normAr(String s) {
  final b = StringBuffer();
  for (final r in s.runes) {
    if ((r >= 0x064B && r <= 0x065F) || r == 0x0670 || (r >= 0x06D6 && r <= 0x06ED) || r == 0x0640) {
      continue;
    }
    var c = r;
    if (c == 0x0623 || c == 0x0625 || c == 0x0622 || c == 0x0671) {
      c = 0x0627;
    } else if (c == 0x0649 || c == 0x0626) {
      c = 0x064A;
    } else if (c == 0x0629) {
      c = 0x0647;
    } else if (c == 0x0624) {
      c = 0x0648;
    }
    b.writeCharCode(c);
  }
  return b.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

int _lev1(String a, String b) {
  if ((a.length - b.length).abs() > 1) return 9;
  final m = a.length, n = b.length;
  var prev = List<int>.generate(n + 1, (i) => i);
  for (var i = 1; i <= m; i++) {
    final cur = List<int>.filled(n + 1, 0);
    cur[0] = i;
    for (var j = 1; j <= n; j++) {
      final c = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      var v = prev[j - 1] + c;
      if (prev[j] + 1 < v) v = prev[j] + 1;
      if (cur[j - 1] + 1 < v) v = cur[j - 1] + 1;
      cur[j] = v;
    }
    prev = cur;
  }
  return prev[n];
}

int _levFull(String a, String b) {
  var prev = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final cur = List<int>.filled(b.length + 1, 0);
    cur[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final c = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      var v = prev[j - 1] + c;
      if (prev[j] + 1 < v) v = prev[j] + 1;
      if (cur[j - 1] + 1 < v) v = cur[j - 1] + 1;
      cur[j] = v;
    }
    prev = cur;
  }
  return prev[b.length];
}

final RegExp _weak = RegExp('[اويء]');

/// Is the heard word the expected word? (forgiving of how speech engines spell)
bool sameWord(String heard, String expected) {
  if (heard == expected) return true;
  String strip(String w) => (w.startsWith('و') || w.startsWith('ف')) && w.length > 3 ? w.substring(1) : w;
  final h = strip(heard), e = strip(expected);
  if (h == e) return true;
  if (expected.length >= 4 && _lev1(heard, expected) <= 1) return true;
  // the mushaf spelling and the everyday spelling differ mostly in the long vowels
  final a = h.replaceAll(_weak, ''), b = e.replaceAll(_weak, '');
  if (a.length >= 3 && a == b) return true;
  return false;
}

/// A heard word that is near enough to count as an attempt at the expected word.
bool nearWord(String heard, String expected) {
  if (sameWord(heard, expected)) return true;
  final lim = expected.length <= 3 ? 1 : (expected.length <= 6 ? 2 : 3);
  return _levFull(heard, expected) <= lim;
}

/// The strong letters of a word, each with its short vowel (a, u, i) when one is written.
List<List<int>> _vowels(String w) {
  final out = <List<int>>[];
  for (final r in w.runes) {
    var v = 0;
    if (r == 0x064E || r == 0x064B || r == 0x08F0) v = 1;
    if (r == 0x064F || r == 0x064C || r == 0x08F1) v = 2;
    if (r == 0x0650 || r == 0x064D || r == 0x08F2) v = 3;
    if (v != 0) {
      if (out.isNotEmpty && out.last[1] == 0) out.last[1] = v;
      continue;
    }
    if (r < 0x0621 || r > 0x064A || r == 0x0640) {
      // a mark that is not a short vowel; a letter outside the alphabet ends the pairing
      if (r >= 0x0671 && r <= 0x06D3) out.add([0, -1]);
      continue;
    }
    // the weak letters and the hamza are written differently in the mushaf: they are left out
    const weak = [0x0621, 0x0622, 0x0623, 0x0624, 0x0625, 0x0626, 0x0627, 0x0648, 0x0649, 0x064A];
    if (weak.contains(r)) {
      out.add([0, -1]);
      continue;
    }
    out.add([r == 0x0629 ? 0x0647 : r, 0]);
  }
  return out.where((e) => e[0] != 0).toList();
}

/// Was the word said with a short vowel other than the mushaf's? Only what is sure is counted:
/// the same strong letters on both sides, and a written vowel on both that differs.
bool tashkeelDiffers(String heard, String mushaf, {bool skipLast = false}) {
  final h = _vowels(heard), m = _vowels(mushaf);
  if (h.length != m.length || h.isEmpty) return false;
  for (var i = 0; i < h.length; i++) {
    if (h[i][0] != m[i][0]) return false;
  }
  final n = skipLast ? h.length - 1 : h.length;
  for (var i = 0; i < n; i++) {
    if (h[i][1] > 0 && m[i][1] > 0 && h[i][1] != m[i][1]) return true;
  }
  return false;
}

class MWord {
  final String key; // line:index on the page
  final int g;
  final String norm;
  final String text;
  const MWord(this.key, this.g, this.norm, this.text);
}

class MatchOut {
  final int idx;

  /// word key -> 1 read, 2 skipped, 4 read with a wrong vowel
  final Map<String, int> state;
  const MatchOut(this.idx, this.state);
}

/// Matches the whole transcript of a listening session again (a word the engine corrects later
/// is corrected here too). [from], [baseIdx] and [baseState] are where the session started.
/// [quiet]: the last words are still being said and may change.
MatchOut matchRecitation({
  required List<MWord> words,
  required List<String> heard,
  List<String>? raw,
  int from = 0,
  int baseIdx = 0,
  Map<String, int> baseState = const {},
  bool quiet = false,
  int strict = 1,
  bool tashkeel = true,
}) {
  final hs = List<String>.of(heard);
  var i = baseIdx;
  final st = Map<String, int>.of(baseState);
  final missed = <String>[]; // heard words that matched nothing since the last match
  bool m(int hj, int wi) => hj < hs.length && wi < words.length && sameWord(hs[hj], words[wi].norm);
  void ok(int wi) => st[words[wi].key] ??= 1;
  final tk = tashkeel && raw != null && raw.length == hs.length;
  var j = from;
  while (j < hs.length && i < words.length) {
    final h = hs[j];
    final e = words[i].norm;
    if (sameWord(h, e)) {
      // the words still being said may yet change: their vowels are judged once they settle
      if (tk && h == normAr(raw[j]) && (!quiet || j < hs.length - 2) && st[words[i].key] == null &&
          tashkeelDiffers(raw[j], words[i].text, skipLast: i + 1 >= words.length || words[i + 1].g != words[i].g)) {
        st[words[i].key] = 4;
      }
      ok(i);
      i++;
      j++;
      missed.clear();
      continue;
    }
    // the engine glued two words together
    if (e.length >= 2 && h.length > e.length + 1 && h.startsWith(e)) {
      ok(i);
      i++;
      hs[j] = h.substring(e.length);
      missed.clear();
      continue;
    }
    if (e.length >= 3 && h.length > e.length + 1 && h.endsWith(e)) {
      ok(i);
      i++;
      j++;
      missed.clear();
      continue;
    }
    // one word of the mushaf heard as two
    if (j + 1 < hs.length && sameWord(h + hs[j + 1], e)) {
      ok(i);
      i++;
      j += 2;
      missed.clear();
      continue;
    }
    // two words of the mushaf heard as one
    if (i + 1 < words.length && sameWord(h, e + words[i + 1].norm)) {
      ok(i);
      ok(i + 1);
      i += 2;
      j++;
      missed.clear();
      continue;
    }
    // A word counts as skipped only when the words after it are then heard in order.
    var jumped = false;
    for (var k = 1; k <= 4 && !jumped; k++) {
      if (i + k >= words.length) break;
      final need = k + 2;
      var got = 0;
      var end = false;
      for (var r = 0; r < need; r++) {
        if (i + k + r >= words.length) {
          end = true;
          break;
        }
        if (!m(j + r, i + k + r)) break;
        got++;
      }
      if (got == need || (end && got >= 2)) {
        for (var x = 0; x < k; x++) {
          final w = words[i + x];
          // he said something close to it: the engine misheard, not a mistake
          final lvl = strict;
          final tried = lvl == 2
              ? false
              : (missed.any((u) => nearWord(u, w.norm)) || (lvl == 0 && k == 1 && missed.isNotEmpty));
          if (st[w.key] == null || st[w.key] == 2) st[w.key] = tried ? 1 : 2;
        }
        i += k;
        missed.clear();
        jumped = true;
      }
    }
    if (jumped) continue;
    missed.add(h);
    j++;
  }
  return MatchOut(i, st);
}
