"""Builds the word-meaning (غريب القرآن) data of the app from three printed books, taken
from the OpenITI corpus (github.com/OpenITI):

  1. المفردات في غريب القرآن — الراغب الأصفهاني، تحقيق صفوان عدنان الداودي (دار القلم)
  2. عمدة الحفاظ في تفسير أشرف الألفاظ — السمين الحلبي، تحقيق محمد باسل عيون السود
  3. التبيان في تفسير غريب القرآن — ابن الهائم، تحقيق ضاحي عبد الباقي محمد

A word of the mushaf gets a meaning only when a book really speaks about it at that ayah:
the two root dictionaries must quote the ayah inside the entry of the word's root, and
ابن الهائم must list the word under its ayah. Nothing is written by hand.

usage: build_gharib.py morphology.txt mufradat.txt umda.txt tibyan.txt mufradat_kilani.txt
(the last file, another printing of المفردات, is only used to tell the real entry titles
of the first from words that its digital copy marks in bold; no text is taken from it)
Results are committed in assets/gharib/gharib.json.gz."""
import gzip, json, re, sys

morph, f_raghib, f_umda, f_tibyan, f_jk = sys.argv[1:6]
TASHKEEL = re.compile('[ً-ٰٟۖ-ۭـ]')
WEAK = re.compile('[اويء]')


def key(s):
    s = TASHKEEL.sub('', s)
    s = re.sub('[أإآؤئء]', 'ء', s).replace('ى', 'ي').replace('ٱ', 'ا').replace('ة', 'ه')
    return s.strip()


def skel(s):
    return WEAK.sub('', key(s))


def variants(root):
    k = key(root)
    c = [k]
    if len(k) == 3 and k[1] == k[2]:
        c.append(k[:2])
    if len(k) == 3 and k[2] in 'وي':
        c += [k[:2] + 'ا', k[:2] + 'ي', k[:2] + 'اء', k[:2] + 'و', k[:2]]
    if len(k) == 3 and k[2] == 'ء':
        c += [k[:2] + 'ا', k[:2] + 'ي']
    if len(k) == 3 and k[1] in 'وي':
        c += [k[0] + 'ا' + k[2], k[0] + 'و' + k[2], k[0] + 'ي' + k[2]]
    if len(k) == 3 and k[0] == 'ء':
        c += ['ا' + k[1:]]
    if len(k) == 4 and k[:2] == k[2:]:
        c.append(k[:2])
    return c


def subseq(a, b):
    it = iter(b)
    return all(ch in it for ch in a)


# ---------------- the words of the Quran and their roots ----------------
ayahs = {}
for line in open(morph, encoding='utf-8'):
    p = line.rstrip('\n').split('\t')
    if len(p) < 4:
        continue
    s, a, w, _ = (int(x) for x in p[0].split(':'))
    slot = ayahs.setdefault((s, a), {}).setdefault(w, ['', None])
    slot[0] += p[1]
    m = re.search(r'ROOT:([^|]+)', p[3])
    if m:
        slot[1] = m.group(1)
ORDER = sorted(ayahs)
G = {sa: i for i, sa in enumerate(ORDER)}
assert len(ORDER) == 6236
WORDS = [[ayahs[sa][w] for w in sorted(ayahs[sa])] for sa in ORDER]   # g -> [[uthmani, root]]
ROOTKEYS = set()
for row in WORDS:
    for _, r in row:
        if r:
            ROOTKEYS.update(variants(r))

ROOTKEYS_H = {('ء' + k[1:] if k[:1] == 'ا' else k) for k in ROOTKEYS}

names = re.findall(r"'([^']+)'", open('lib/data/surah_names.dart', encoding='utf-8').read())[:114]
SURAH = {}
for i, n in enumerate(names):
    SURAH[key(n)] = i + 1
    if n.startswith('ال'):
        SURAH.setdefault(key(n[2:]), i + 1)
for alt, n in {'الاسراء': 17, 'بني اسراءيل': 17, 'المءمن': 40, 'غافر': 40, 'السجده': 32, 'حم السجده': 41, 'فصلت': 41,
               'القتال': 47, 'الانسان': 76, 'الدهر': 76, 'المسد': 111, 'تبت': 111, 'الشرح': 94, 'الانشراح': 94,
               'الم نشرح': 94, 'التوبه': 9, 'براءه': 9, 'الملاءكه': 35, 'الملك': 67, 'تبارك': 67, 'النبا': 78, 'عم': 78,
               'البينه': 98, 'لم يكن': 98, 'الاخلاص': 112, 'المطففين': 83, 'التطفيف': 83, 'سبا': 34, 'الجاثيه': 45,
               'المعارج': 70, 'سال': 70, 'الماعون': 107, 'المومنون': 23, 'المءمنون': 23, 'المومن': 40, 'الزلزله': 99,
               'يونس': 10, 'ال عمران': 3, 'عمران': 3, 'الشوري': 42, 'ن': 68, 'القلم': 68, 'المدثر': 74, 'المزمل': 73,
               'الطلاق': 65, 'عبس': 80, 'النصر': 110, 'قريش': 106, 'التكاثر': 102, 'الضحي': 93, 'الليل': 92,
               'اقرا': 96, 'العلق': 96, 'القيامه': 75, 'الحجر': 15, 'ص': 38, 'ق': 50, 'طه': 20, 'يس': 36}.items():
    SURAH.setdefault(key(alt), n)


def cites(text, sep):
    """Places where a text quotes an ayah, e.g. [الكهف/ 81] or [التوبة: 25]: (g, start, end).
    The span runs from the end of the quotation before it to the end of the reference,
    so it covers the words of the ayah and their reference."""
    out = []
    last = 0
    for m in re.finditer(r'\[\[?([^\]\[%s]{1,20}?)\s*%s\s*(\d+)(?:\s*[-–]\s*\d+)?\s*\]' % (sep, sep), text):
        s = SURAH.get(key(m.group(1)))
        st = last
        while st < m.start() and text[st] in ' ،.؛:':
            st += 1
        if s and (s, int(m.group(2))) in G:
            out.append((G[(s, int(m.group(2)))], st, m.end()))
        last = m.end()
    return out


def tidy(t):
    t = re.sub(r'PageV\d+P\d+', '', t)
    t = re.sub(r'ms\d+', '', t)
    t = re.sub(r'\s*«\d+»\s*', ' ', t)
    t = re.sub(r'\s*\(\d+\)\s*', ' ', t)
    t = re.sub(r' +([،.:؛])', r'\1', t)
    return re.sub(r'[ \t]+', ' ', t).strip()


def paragraphs(path):
    """The OpenITI file as a list of ('h', heading) and ('p', paragraph)."""
    out = []
    for line in open(path, encoding='utf-8'):
        line = line.rstrip('\n')
        if line.startswith('#META#') or line.startswith('######') or not line.strip():
            continue
        if line.startswith('### '):
            out.append(['h', line[4:].strip()])
        elif line.startswith('~~'):
            if out and out[-1][0] == 'p':
                out[-1][1] += ' ' + line[2:].strip()
        elif line.startswith('# '):
            out.append(['p', line[2:].strip()])
    return out


ENTRIES = []      # [book, title, [paragraphs]]
ROOT_ENTRY = [{}, {}]   # book -> key of title -> entry index

# ---------------- 1. المفردات (الداودي) ----------------
def hk(h):
    k = key(h)
    return 'ء' + k[1:] if k[:1] == 'ا' else k


# the order of the entries, read from the other printing
ALPHA = 'ءبتثجحخدذرزسشصضطظعغفقكلمنوهي'
NOT_HEAD = {'قال', 'قيل', 'وقيل', 'وقال', 'قوله', 'وقوله', 'يقال', 'ويقال', 'نحو', 'قلت', 'وقرئ', 'قرئ'}
JK, li = [], 0
for kind, txt in paragraphs(f_jk):
    if kind != 'p':
        continue
    txt = re.sub(r' +', ' ', re.sub(r'ms\d+|PageV\d+P\d+', '', txt))
    for m in re.finditer(r'(?:^|\. |@QE@ |\) )(\S{2,6}) : ', txt):
        h = m.group(1)
        if h in NOT_HEAD:
            continue
        k = hk(h)
        x = ALPHA.find(k[0])
        if x == li or (x == li + 1 and JK):
            li = x
            JK.append(k)

raw = paragraphs(f_raghib)
items = []
for kind, txt in raw:
    txt = re.sub(r'ms\d+', '', txt).strip()
    m = re.match(r'^(\S{1,4})</span>$', txt)
    if kind == 'p' and m and items and items[-1][0] == 'h':
        items[-1][1] += m.group(1)          # a title cut in two by the markup
        continue
    txt = txt.replace('</span>', '').replace('<span>', '')
    if kind == 'p' and re.match(r'^[\u0621-\u064A]{2,7}$', txt):
        kind, txt = 'h', '| ' + txt         # a title left as a plain line
    if txt or kind == 'h':
        items.append([kind, txt])
letter, cur, started = None, None, False
i = 0
n_false = 0
ptr = 0
while i < len(items):
    kind, txt = items[i]
    if kind == 'h':
        h = re.sub(r'ms\d+', '', txt.split('|')[-1]).strip()
        if h.startswith('كتاب ') and len(h) < 14:
            started = True
            nm = key(h[5:])
            letter = 'ء' if nm.startswith('الالف') else nm[2]
            cur = None
        elif not started or 'الفهارس' in h:
            if 'الفهارس' in h and started:
                break
        elif re.match(r'^\d+\s*-?$', h) or not h:
            pass            # the number of a line of poetry: the entry goes on
        else:
            k = hk(h)
            nxt = items[i + 1][1] if i + 1 < len(items) and items[i + 1][0] == 'p' else ''
            toks = [key(t) for t in re.sub(r'[،:.؛«»()\[\]]', ' ', nxt).split()[:2]]
            sk = skel(h)
            prev = ENTRIES[cur][2][-1] if cur is not None and ENTRIES[cur][2] else ''
            finished = cur is None or not prev or bool(re.search(r'[.؟!»\])]\s*$', tidy(prev)))
            opens = bool(toks) and len(toks[0]) >= 3 and (len(sk) < 2 or any(subseq(sk, t) for t in toks))
            win = JK[ptr:ptr + 10]
            real = len(h) <= 9 and ' ' not in h and k[0] == letter and (finished or opens)
            if real and k in win:
                ptr += win.index(k) + 1
            elif real:
                # not where the other printing has it: accept only a clear opening of a root of the Quran
                real = finished and opens and k in ROOTKEYS_H
            if real:
                cur = len(ENTRIES)
                ENTRIES.append([0, h, []])
                ROOT_ENTRY[0].setdefault(key(h), cur)
            elif cur is not None:
                # a word that the digital copy set in bold inside the entry
                n_false += 1
                if nxt:
                    t0 = re.sub(r'[،:.؛]', '', nxt.split(' ')[0])
                    joined = h + ('' if len(t0) <= 2 else ' ') + nxt
                    ps = ENTRIES[cur][2]
                    if ps and not finished:
                        ps[-1] += ' ' + joined
                    else:
                        ps.append(joined)
                    i += 1
    elif started and cur is not None:
        ENTRIES[cur][2].append(txt)
    i += 1
n_raghib = len(ENTRIES)

# ---------------- 2. عمدة الحفاظ ----------------
cur = None
for kind, txt in paragraphs(f_umda):
    if kind == 'h':
        continue
    m = re.match(r'^((?:[ء-ي] ){1,4}[ء-ي])\s*:?\s*$', tidy(txt))
    if m:
        root = m.group(1).replace(' ', '')
        cur = len(ENTRIES)
        ENTRIES.append([1, root, []])
        ROOT_ENTRY[1].setdefault(key(root), cur)
        continue
    if cur is not None:
        t = txt.replace('[[', '[').replace(' # ', ' ')
        # the source has the quotation marks of the ayahs in no fixed direction: pair them in order
        parts = re.split(r'[{}]', t)
        t = ''.join(x + ('' if j == len(parts) - 1 else ('﴿' if j % 2 == 0 else '﴾')) for j, x in enumerate(parts))
        ENTRIES[cur][2].append(t)
n_umda = len(ENTRIES) - n_raghib

for e in ENTRIES:
    ps = []
    for p in (tidy(x) for x in e[2]):
        if not p:
            continue
        # the digital copy puts the reference of an ayah on a line of its own: join it to its ayah
        if ps and (p.startswith('[') or re.search(r'[:،]$', ps[-1]) or not re.search(r'[.؟!»\])…]$', ps[-1])) \
                and not re.match(r'^\d+ ?-', p) and '...' not in ps[-1] and '...' not in p:
            ps[-1] += ' ' + p
        else:
            ps.append(p)
    e[2] = ps

# words -> root entries that quote their ayah
REFS = [dict() for _ in range(6236)]     # g -> {word index: [[entry, paragraph]]}
for book, sep in ((0, '/'), (1, ':')):
    cited = {}    # entry -> {g: first paragraph}
    for ei, e in enumerate(ENTRIES):
        if e[0] != book:
            continue
        for pi, p in enumerate(e[2]):
            for g, st, en in cites(p, sep):
                cited.setdefault(ei, {}).setdefault(g, [pi, st, en])
    for g, row in enumerate(WORDS):
        for wi, (_, root) in enumerate(row):
            if not root:
                continue
            ei = next((ROOT_ENTRY[book][v] for v in variants(root) if v in ROOT_ENTRY[book]), None)
            if ei is not None and g in cited.get(ei, {}):
                REFS[g].setdefault(wi, []).append([ei] + cited[ei][g])

# ---------------- 3. التبيان لابن الهائم ----------------
surah, cur = 0, None
n_tib = n_tib_hit = 0
for kind, txt in paragraphs(f_tibyan):
    if kind == 'h':
        m = re.search(r'(\d+)\s*-\s*سورة', txt)
        if '$' in txt and m:
            surah = int(m.group(1))
        cur = None
        continue
    if not surah:
        continue
    t = tidy(txt)
    m = re.match(r'^(.{1,80}?)\s*\[(\d+)\]\s*:?\s*(.*)$', t)
    if m and (surah, int(m.group(2))) in G and m.group(3):
        g = G[(surah, int(m.group(2)))]
        phrase = m.group(1).strip()
        cur = len(ENTRIES)
        ENTRIES.append([2, phrase, [m.group(3)]])
        n_tib += 1
        # find the words of the phrase inside the ayah
        ws = [skel(w) for w in phrase.split()]
        ay = [skel(w[0]) for w in WORDS[g]]
        hit = []
        for st in range(len(ay) - len(ws) + 1):
            if all(ay[st + j] == ws[j] or (len(ws[j]) >= 3 and (ay[st + j].endswith(ws[j]) or ws[j].endswith(ay[st + j]) and len(ay[st + j]) >= 3))
                   for j in range(len(ws))):
                hit = list(range(st, st + len(ws)))
                break
        if not hit:
            for j, w in enumerate(ws):
                if len(w) < 3:
                    continue
                for wi, a in enumerate(ay):
                    if a == w or (len(a) >= 3 and (a.endswith(w) or w.endswith(a))):
                        hit.append(wi)
                        break
        if hit:
            n_tib_hit += 1
        for wi in hit:
            REFS[g].setdefault(wi, []).append([cur, 0, 0, 0])
    elif cur is not None:
        ENTRIES[cur][2].append(t)

# keep only the entries that some word points to
used = sorted({r[0] for d in REFS for l in d.values() for r in l})

remap = {e: i for i, e in enumerate(used)}
out_entries = [[ENTRIES[e][0], ENTRIES[e][1], '\n'.join(ENTRIES[e][2])] for e in used]
out_refs = [{str(wi): [[remap[r[0]]] + r[1:] for r in l] for wi, l in d.items()} for d in REFS]
books = [
    {'name': 'المفردات في غريب القرآن', 'author': 'الراغب الأصفهاني', 'ed': 'تحقيق صفوان عدنان الداودي — دار القلم'},
    {'name': 'عمدة الحفاظ في تفسير أشرف الألفاظ', 'author': 'السمين الحلبي', 'ed': 'تحقيق محمد باسل عيون السود — دار الكتب العلمية'},
    {'name': 'التبيان في تفسير غريب القرآن', 'author': 'ابن الهائم', 'ed': 'تحقيق ضاحي عبد الباقي محمد — دار الغرب الإسلامي'},
]
with gzip.open('assets/gharib/gharib.json.gz', 'wb', 9) as f:
    f.write(json.dumps({'books': books, 'e': out_entries, 'w': out_refs, 'n': [len(r) for r in WORDS]},
                       ensure_ascii=False, separators=(',', ':')).encode())
words_with = sum(len(d) for d in REFS)
per = [sum(1 for d in REFS for l in d.values() if any(ENTRIES[r[0]][0] == b for r in l)) for b in range(3)]
print('raghib entries', n_raghib, '(bold fragments joined', n_false, ') umda entries', n_umda,
      'tibyan entries', n_tib, 'matched', n_tib_hit)
print('words with a meaning', words_with, 'of', sum(len(r) for r in WORDS), 'per book', per, 'entries kept', len(used))
