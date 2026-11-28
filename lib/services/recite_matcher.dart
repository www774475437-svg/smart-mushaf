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
  final String norm; // everyday spelling
  final String text; // as written in the mushaf, with its marks
  MWord(this.key, this.g, this.norm, this.text);

  /// The mushaf's own spelling without marks (السموت): some models write the words this way.
  late final String alt = normAr(text);
}

class MatchOut {
  final int idx;

  /// word key -> 1 read, 2 skipped, 4 read with a wrong vowel
  final Map<String, int> state;

  /// letters heard since the last progress that landed nowhere on the page
  final int junk;
  const MatchOut(this.idx, this.state, [this.junk = 0]);
}

// How the following works. The letters heard since the last settled point are laid along the
// letters of the mushaf from that point on (the cheapest way of turning one into the other), so
// a word the engine garbled, glued to its neighbour or split in two never stops the following.
// The reciter may go back and repeat (the laying may start up to [_back] words earlier) or the
// engine may have missed some words (the laying may start further on, for a small price). A
// result counts only when enough of what was heard lands on the page; a word counts as skipped
// only when nothing was heard where its letters should be and no stray sounds were heard
// before it. The numbers were chosen on whole pages read by 16 reciters (tool/eval_matcher).
const int _back = 14, _far = 80, _jumpWords = 3, _jumpMin = 8, _cap = 12;
const double _goodShare = 0.6, _badShare = 0.67, _accept = 0.5, _acceptJump = 0.7, _tried = 0.5;

String _fold(String w) => w.replaceAll('ء', '');

class _Lay {
  final int cost, start, end, at;
  final List<int> hit; // per mushaf letter: 0 nothing was said, 1 heard, 2 something else heard
  final List<int> by; // per mushaf letter: the heard letter laid on it, or -1
  final List<int> starts, lens;
  _Lay(this.cost, this.start, this.end, this.at, this.hit, this.by, this.starts, this.lens);
}

_Lay _lay(List<int> h, List<int> e, int at, List<int> starts, List<int> lens) {
  final n = h.length, m = e.length, w = m + 1;
  final d = List<int>.filled((n + 1) * w, 0);
  for (var b = 0; b <= m; b++) {
    d[b] = b < at ? 4 : (b == at ? 0 : 4 + (b - at > _cap ? _cap : b - at));
  }
  for (var a = 1; a <= n; a++) {
    final r = a * w, p = r - w, ha = h[a - 1];
    d[r] = d[p] + 4;
    for (var b = 1; b <= m; b++) {
      var v = d[p + b - 1] + (e[b - 1] == ha ? 0 : 4);
      final x = d[p + b] + 4;
      if (x < v) v = x;
      final y = d[r + b - 1] + 4;
      if (y < v) v = y;
      d[r + b] = v;
    }
  }
  var end = 0;
  final last = n * w;
  for (var b = 1; b <= m; b++) {
    if (d[last + b] <= d[last + end]) end = b;
  }
  final hit = List<int>.filled(m, 0), by = List<int>.filled(m, -1);
  var a = n, b = end;
  while (a > 0 && b > 0) {
    final same = h[a - 1] == e[b - 1];
    final v = d[a * w + b];
    if (v == d[(a - 1) * w + b - 1] + (same ? 0 : 4)) {
      hit[b - 1] = same ? 1 : 2;
      by[b - 1] = a - 1;
      a--;
      b--;
    } else if (v == d[(a - 1) * w + b] + 4) {
      a--;
    } else {
      b--;
    }
  }
  return _Lay(d[last + end], b, end, at, hit, by, starts, lens);
}

/// Follows the words heard since [from] (where the last settled result ended: the caller moves
/// [from], [baseIdx], [baseState] and [junk] forward after every settled result).
/// [quiet]: the last words are still being said and may change.
/// [seen]: words that were heard well in an earlier guess of the same stretch.
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
  int junk = 0,
  Set<String> seen = const {},
}) {
  final st = Map<String, int>.of(baseState);
  if (baseIdx >= words.length || from >= heard.length) return MatchOut(baseIdx, st, junk);
  final h = <int>[], tok = <int>[];
  for (var j = from; j < heard.length; j++) {
    for (final c in _fold(heard[j]).codeUnits) {
      h.add(c);
      tok.add(j);
    }
  }
  if (h.isEmpty) return MatchOut(baseIdx, st, junk);
  final wb = baseIdx - _back < 0 ? 0 : baseIdx - _back;
  final b0 = baseIdx - wb;
  _Lay lay(int ahead) {
    var we = baseIdx + (h.length / 2.2).floor() + ahead;
    if (we > words.length) we = words.length;
    _Lay? best;
    for (var sp = 0; sp < 2; sp++) {
      final e = <int>[], s = <int>[], l = <int>[];
      for (var k = wb; k < we; k++) {
        final p = _fold(sp == 0 ? words[k].norm : words[k].alt).codeUnits;
        s.add(e.length);
        l.add(p.length);
        e.addAll(p);
      }
      final x = _lay(h, e, s[b0], s, l);
      if (best == null || x.cost < best.cost) best = x;
    }
    return best!;
  }

  // the word the laying starts in, and whether enough of what was heard landed on the page
  int first(_Lay a) {
    var k = b0;
    while (k + 1 < a.starts.length && a.starts[k + 1] <= a.start) {
      k++;
    }
    return k;
  }

  bool counts(_Lay a) {
    if (a.end <= a.at) return false;
    var got = 0;
    for (var x = a.start; x < a.end; x++) {
      if (a.hit[x] == 1) got++;
    }
    final jump = a.start > a.at ? first(a) - b0 : 0;
    if (jump > _jumpWords && h.length < _jumpMin) return false;
    return got / h.length >= (jump > _jumpWords ? _acceptJump : _accept);
  }

  var a = lay(10);
  var ok = counts(a);
  if (!ok && h.length >= _jumpMin) {
    final f = lay(_far);
    if (counts(f)) {
      a = f;
      ok = true;
    }
  }
  if (!ok) return MatchOut(baseIdx, st, junk + h.length);
  final starts = a.starts, lens = a.lens;
  final k0 = a.start > a.at ? first(a) : b0;
  bool good(int c, int len) => len <= 1 ? true : (len == 2 ? c >= 1 : c / len >= _goodShare);
  bool bad(int c, int len, int z) {
    if (strict == 2) return !good(c, len);
    if (len <= 2) return false;
    if (strict == 0) return z == len;
    return z / len >= _badShare;
  }

  // the words jumped over were said but garbled by the engine, when enough stray letters came
  var over = 0;
  for (var k = b0; k < k0; k++) {
    over += lens[k];
  }
  final tried = k0 > b0 && strict != 2 && junk >= over * _tried;
  // every word the laying reached: [word, letters heard, letters, letters with nothing heard]
  var res = <List<int>>[];
  for (var k = b0; k < starts.length; k++) {
    final s = starts[k], len = lens[k];
    if (s >= a.end) break;
    var c = 0, z = 0;
    for (var x = s; x < s + len; x++) {
      if (a.hit[x] == 1) c++;
      if (a.hit[x] == 0) z++;
    }
    res.add([k + wb, c, len, z]);
  }
  bool red(List<int> r) => !good(r[1], r[2]) && bad(r[1], r[2], r[3]);
  if (quiet) {
    // the last words may still be being said: they wait for the next result
    while (res.isNotEmpty && !good(res.last[1], res.last[2])) {
      res.removeLast();
    }
    // and a word is not called skipped until the words after it have settled
    for (var t = res.length - 2 < 0 ? 0 : res.length - 2; t < res.length; t++) {
      if (red(res[t])) {
        res = res.sublist(0, t);
        break;
      }
    }
  } else {
    while (res.isNotEmpty && res.last[1] == 0) {
      res.removeLast();
    }
  }
  final tk = tashkeel && raw != null && raw.length == heard.length;
  var idx = baseIdx;
  for (final r in res) {
    final w = words[r[0]];
    var v = red(r) ? 2 : 1;
    if (v == 2 && ((tried && r[0] - wb < k0) || (strict != 2 && seen.contains(w.key)))) v = 1;
    if (v == 1 && tk) {
      // the vowels are judged only when the engine wrote this very word, whole, as one word
      final s = starts[r[0] - wb];
      var t = -1, one = r[2] > 0;
      for (var x = s; x < s + r[2] && one; x++) {
        final hb = a.by[x];
        if (hb < 0) continue;
        if (t == -1) t = tok[hb];
        if (tok[hb] != t) one = false;
      }
      if (one && t >= 0 && (!quiet || t < heard.length - 2) && heard[t] == normAr(raw[t]) &&
          (sameWord(heard[t], w.norm) || sameWord(heard[t], w.alt)) &&
          tashkeelDiffers(raw[t], w.text, skipLast: r[0] + 1 >= words.length || words[r[0] + 1].g != w.g)) {
        v = 4;
      }
    }
    st[w.key] = v;
    idx = r[0] + 1;
  }
  // a skipped word that is now read again, whole, is no longer red
  for (var k = 0; k < b0; k++) {
    final s = starts[k], len = lens[k];
    if (st[words[k + wb].key] != 2 || len == 0 || s < a.start || s + len > a.end) continue;
    var all = true;
    for (var x = s; x < s + len; x++) {
      if (a.hit[x] != 1) all = false;
    }
    if (all) st[words[k + wb].key] = 1;
  }
  return MatchOut(idx, st, idx > baseIdx ? 0 : junk);
}
