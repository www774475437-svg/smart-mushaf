"""Builds the word-meaning data: the root of every word of the Quran, and the entries of
«المفردات في غريب القرآن» للراغب الأصفهاني (تحقيق محمد سيد كيلاني, from the OpenITI corpus).
Run by hand when the sources change; the results are committed in assets/gharib/."""
import gzip, json, re, sys

morph, book = sys.argv[1], sys.argv[2]
TASHKEEL = re.compile('[ً-ٰٟۖ-ۭـ]')

def key(s):
    s = TASHKEEL.sub('', s)
    s = re.sub('[أإآؤئء]', 'ء', s).replace('ى', 'ي').replace('ٱ', 'ا')
    return s.strip()

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

ROOTKEYS = set()
for line in open(morph, encoding='utf-8'):
    m = re.search(r'ROOT:([^|\s]+)', line)
    if m:
        ROOTKEYS.update(variants(m.group(1)))

def subseq(a, b):
    it = iter(b)
    return all(ch in it for ch in a)

# ---- the book ----
ALPHA = 'ابتثجحخدذرزسشصضطظعغفقكلمنوهي'  # the book puts الواو before الهاء
NOT_HEAD = {'قال', 'قيل', 'وقيل', 'وقال', 'قوله', 'وقوله', 'يقال', 'ويقال', 'نحو', 'قلت', 'وقرئ', 'قرئ'}
paras = []
for line in open(book, encoding='utf-8'):
    line = line.rstrip('\n')
    if line.startswith('#META#') or line.startswith('######') or not line.strip():
        continue
    line = re.sub(r'PageV\d+P\d+', '', line)
    line = re.sub(r'ms\d+', '', line)
    if line.startswith('~~'):
        if paras:
            paras[-1] += ' ' + line[2:].strip()
        continue
    if line.startswith('# '):
        paras.append(re.sub(r' +', ' ', line[2:]).strip())
# some entries begin in the middle of a printed paragraph: «… الصلاح . طلع : طلع الشمس…»
split = []
for ptxt in paras:
    ptxt = re.sub(r'(\.|@QE@|\)) (\S{2,5}) : ',
                  lambda m: m.group(1) + '\n' + m.group(2) + ' : '
                  if key(m.group(2)) in ROOTKEYS and m.group(2) not in NOT_HEAD else m.group(0), ptxt)
    split += ptxt.split('\n')
paras = split
entries, order, cur, letter = {}, [], None, 0
for ptxt in paras:
    m = re.match(r'^(\S{2,6}) : ?(.*)$', ptxt)
    if not m:
        # a few entries have no colon after the root: «كفر الكفر في اللغة…»
        t = ptxt.split(' ')
        if len(t) > 3 and 2 <= len(t[0]) <= 4 and key(t[0]) in ROOTKEYS and t[0] not in entries \
                and (subseq(re.sub('[اويء]', '', key(t[0])), key(t[1])) or subseq(re.sub('[اويء]', '', key(t[0])), key(t[2]))) and len(re.sub('[اويء]', '', key(t[0]))) >= 2:
            m = re.match(r'^(\S+) (.*)$', ptxt)
    if m and m.group(1) not in NOT_HEAD:
        h = m.group(1)
        k = key(h).replace('ء', 'ا')
        if h.startswith('و') and len(h) > 2 and ALPHA[letter] != 'و' and k[1] == ALPHA[letter]:
            h, k = h[1:], k[1:]
        li = ALPHA.find(k[0])
        if li == letter or (li == letter + 1 and cur is not None) or (cur is None and li == 0):
            letter = li
            cur = h
            if cur not in entries:
                entries[cur] = []
                order.append(cur)
            ptxt = m.group(2)
    if cur is not None and ptxt:
        entries[cur].append(ptxt)
book_out = {}
for h in order:
    t = '\n'.join(entries[h])
    t = re.sub(r'@QB@\s*', '﴿', t)
    t = re.sub(r'\s*@QE@', '﴾', t)
    t = t.replace(' ~ ', ' ')
    t = re.sub(r'\s*%\s*%\s*', ' … ', t).replace('%', '')
    t = re.sub(r' +([،.:؛])', r'\1', t)
    t = re.sub(r'[ \t]+', ' ', t).strip()
    if t:
        book_out[h] = t
bykey = {}
for h in book_out:
    bykey.setdefault(key(h), h)
# entries titled with a word instead of the bare root: «تراب» for ترب, «خنزير» for خنزر
for h in book_out:
    k = key(h)
    if k.startswith('ال') and len(k) > 4:
        k = k[2:]
    sk = k[0] + re.sub('[اويةه]', '', k[1:]) if len(k) > 3 else k
    if len(sk) >= 3:
        bykey.setdefault(sk, h)

def find(root):
    for x in variants(root):
        if x in bykey:
            return bykey[x]
    return None

# ---- roots of the words ----
words = {}
for line in open(morph, encoding='utf-8'):
    p = line.rstrip('\n').split('\t')
    if len(p) < 4:
        continue
    s, a, w, _ = p[0].split(':')
    m = re.search(r'ROOT:([^|]+)', p[3])
    lem = re.search(r'LEM:([^|]+)', p[3])
    slot = words.setdefault((int(s), int(a)), {}).setdefault(int(w), [None, None])
    if m:
        slot[0] = m.group(1)
    elif lem and 'PREF' not in p[3] and 'SUFF' not in p[3] and slot[1] is None:
        slot[1] = TASHKEEL.sub('', lem.group(1))
heads, hidx, roots, ridx = [], {}, [], {}
out, tot, hit = [], 0, 0
for (s, a) in sorted(words):
    row = []
    for w in sorted(words[(s, a)]):
        root, lem = words[(s, a)][w]
        tot += 1
        h = find(root) if root else (bykey.get(key(lem)) if lem else None)
        if root is None and h is None:
            row.append(-1)
            continue
        label = root or lem
        if label not in ridx:
            ridx[label] = len(roots)
            roots.append([label, hidx.setdefault(h, len(hidx)) if h else -1])
            if h and len(heads) < len(hidx):
                heads.append(h)
        if h:
            hit += 1
        row.append(ridx[label])
    out.append(row)
assert len(out) == 6236, len(out)
with gzip.open('assets/gharib/roots.json.gz', 'wb', 9) as f:
    f.write(json.dumps({'r': roots, 'w': out}, ensure_ascii=False, separators=(',', ':')).encode())
with gzip.open('assets/gharib/mufradat.json.gz', 'wb', 9) as f:
    f.write(json.dumps([[h, book_out[h]] for h in heads], ensure_ascii=False, separators=(',', ':')).encode())
miss = sorted({r[0] for r in roots if r[1] < 0})
print('entries', len(book_out), 'used', len(heads), 'words', tot, 'with entry', hit, 'roots', len(roots), 'missing', len(miss))
print(' '.join(miss[:150]))
print('unused', ' '.join(h for h in book_out if h not in hidx))
