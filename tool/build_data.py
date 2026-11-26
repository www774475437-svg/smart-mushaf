"""Downloads the Quran text, tafsirs, translation and fonts used by the app.

Runs in GitHub Actions before the build. Files that already exist are kept
(the workflow caches them), so the sources are only hit once. A tafsir or font
that cannot be downloaded is skipped (the app then reads it online) so the
build never breaks because one source is down.
"""
import concurrent.futures
import gzip
import json
import os
import re
import shutil
import time
import urllib.request

OUT = 'assets/data'
FONTS = 'assets/fonts'
os.makedirs(OUT, exist_ok=True)
os.makedirs(FONTS, exist_ok=True)

UA = {'User-Agent': 'Mozilla/5.0 (smart-mushaf build)'}


def fetch(url, tries=6, quiet=False):
    last = None
    for i in range(tries):
        try:
            req = urllib.request.Request(url, headers=UA)
            with urllib.request.urlopen(req, timeout=180) as r:
                return r.read()
        except Exception as e:  # noqa
            last = e
            if not quiet:
                print('retry', url, e)
            time.sleep(2 + i * 3)
    raise RuntimeError(f'failed to download {url}: {last}')


def fetch_json(url, tries=6, quiet=False):
    return json.loads(fetch(url, tries, quiet).decode('utf-8'))


def edition(name):
    return fetch_json(f'https://api.alquran.cloud/v1/quran/{name}')['data']['surahs']


def flat(surahs):
    return [a['text'] for s in surahs for a in s['ayahs']]


def strip_basmala(text, surah, ayah, uthmani):
    if ayah != 1 or surah in (1, 9):
        return text
    t = text.lstrip('﻿')
    words = t.split(' ')
    first = words[0]
    if (uthmani and 'بِسْمِ' in first) or (not uthmani and first in ('بسم', 'بِسْمِ')):
        return ' '.join(words[4:]).strip()
    return t


def write(name, obj):
    with open(os.path.join(OUT, name), 'w', encoding='utf-8') as f:
        json.dump(obj, f, ensure_ascii=False, separators=(',', ':'))
    print('wrote', name, os.path.getsize(os.path.join(OUT, name)))


def write_gz(name, obj):
    p = os.path.join(OUT, name)
    with gzip.open(p, 'wb', compresslevel=9) as f:
        f.write(json.dumps(obj, ensure_ascii=False, separators=(',', ':')).encode('utf-8'))
    print('wrote', name, os.path.getsize(p))


def clean_html(s):
    s = re.sub(r'<\s*br\s*/?>', '\n', s or '', flags=re.I)
    s = re.sub(r'</\s*p\s*>', '\n', s, flags=re.I)
    s = re.sub(r'<[^>]*>', '', s)
    for a, b in (('&nbsp;', ' '), ('&quot;', '"'), ('&#39;', "'"), ('&lt;', '<'), ('&gt;', '>'), ('&amp;', '&')):
        s = s.replace(a, b)
    s = re.sub(r'[ \t]+', ' ', s)
    s = re.sub(r'\n\s*\n+', '\n\n', s)
    return s.strip()


# ---------------- Quran text ----------------
if not os.path.exists(os.path.join(OUT, 'quran.json')):
    uth = edition('quran-uthmani')
    clean = edition('quran-simple-clean')
    rows, cl, types = [], [], []
    for s, sc in zip(uth, clean):
        types.append(s.get('revelationType', 'Meccan'))
        for a, ac in zip(s['ayahs'], sc['ayahs']):
            sajda = 1 if a.get('sajda') not in (False, None) else 0
            n = s['number']
            k = a['numberInSurah']
            rows.append([n, k, a['page'], a['juz'], a['hizbQuarter'], sajda,
                         strip_basmala(a['text'], n, k, True)])
            cl.append(strip_basmala(ac['text'], n, k, False))
    assert len(rows) == 6236, len(rows)
    write('quran.json', {'a': rows, 'c': cl, 't': types})

meta = json.load(open(os.path.join(OUT, 'quran.json'), encoding='utf-8'))
COUNTS = {}
for r in meta['a']:
    COUNTS[r[0]] = max(COUNTS.get(r[0], 0), r[1])
START = {}
g = 0
for s in range(1, 115):
    START[s] = g
    g += COUNTS[s]

if not os.path.exists(os.path.join(OUT, 'en.json')):
    lst = flat(edition('en.sahih'))
    assert len(lst) == 6236
    write('en.json', lst)

# ---------------- Tafsirs ----------------
# id -> (alquran.cloud edition, spa5k slugs, quran.com id)
TAFSIRS = {
    'muyassar': ('ar.muyassar', ['ar-tafsir-muyassar'], 16),
    'jalalayn': ('ar.jalalayn', [], None),
    'saadi': (None, ['ar-tafseer-al-saddi', 'ar-tafsir-al-saddi', 'ar-tafseer-al-sadi'], 91),
    'ibnkathir': (None, ['ar-tafsir-ibn-kathir'], 14),
    'tabari': (None, ['ar-tafsir-al-tabari'], 15),
    'baghawi': ('ar.baghawi', ['ar-tafsir-al-baghawi'], 94),
    'qurtubi': ('ar.qurtubi', ['ar-tafseer-al-qurtubi'], 90),
    'waseet': ('ar.waseet', ['ar-tafsir-al-wasit'], 93),
}


def from_cloud(ed):
    return [clean_html(x) for x in flat(edition(ed))]


def from_spa5k(slug):
    out = [''] * 6236

    def one(s):
        d = fetch_json(f'https://cdn.jsdelivr.net/gh/spa5k/tafsir_api@main/tafsir/{slug}/{s}.json', tries=3, quiet=True)
        items = d.get('ayahs', d) if isinstance(d, dict) else d
        res = []
        for it in items:
            a = int(it.get('ayah', it.get('ayah_number', 0)))
            if 1 <= a <= COUNTS[s]:
                res.append((START[s] + a - 1, clean_html(it.get('text', ''))))
        return res

    with concurrent.futures.ThreadPoolExecutor(8) as ex:
        for res in ex.map(one, range(1, 115)):
            for gi, t in res:
                out[gi] = t
    return out


def from_qcom(tid):
    out = [''] * 6236

    def one(s):
        res = []
        page = 1
        while True:
            d = fetch_json(f'https://api.quran.com/api/v4/tafsirs/{tid}/by_chapter/{s}?per_page=50&page={page}',
                           tries=4, quiet=True)
            for it in d.get('tafsirs', []):
                key = it.get('verse_key') or ''
                if ':' in key:
                    ss, aa = key.split(':')
                    gi = START[int(ss)] + int(aa) - 1
                elif it.get('verse_id'):
                    gi = int(it['verse_id']) - 1
                else:
                    continue
                if 0 <= gi < 6236:
                    res.append((gi, clean_html(it.get('text', ''))))
            nxt = (d.get('pagination') or {}).get('next_page')
            if not nxt:
                break
            page = int(nxt)
        return res

    with concurrent.futures.ThreadPoolExecutor(6) as ex:
        for res in ex.map(one, range(1, 115)):
            for gi, t in res:
                out[gi] = t
    return out


def good(lst):
    return lst and len(lst) == 6236 and sum(1 for x in lst if x) > 6236 * 0.5


bundled = []
for tid, (cloud, slugs, qcom) in TAFSIRS.items():
    name = f'tafsir_{tid}.json.gz'
    p = os.path.join(OUT, name)
    if os.path.exists(p):
        bundled.append(tid)
        continue
    got = None
    tries = []
    if cloud:
        tries.append(('cloud', lambda c=cloud: from_cloud(c)))
    for sl in slugs:
        tries.append(('spa5k ' + sl, lambda s=sl: from_spa5k(s)))
    if qcom:
        tries.append(('quran.com', lambda q=qcom: from_qcom(q)))
    for label, fn in tries:
        try:
            lst = fn()
            if good(lst):
                got = lst
                print('tafsir', tid, 'from', label, sum(1 for x in lst if x))
                break
            print('tafsir', tid, label, 'incomplete')
        except Exception as e:  # noqa
            print('tafsir', tid, label, 'failed', e)
    if got:
        write_gz(name, got)
        bundled.append(tid)
    else:
        print('WARNING: tafsir', tid, 'not bundled; app will read it online')
write('tafsirs.json', bundled)

# ---------------- Similar ayahs (المتشابهات) ----------------
if not os.path.exists(os.path.join(OUT, 'similar.json')):
    def norm(t):
        t = re.sub(r'[\u064B-\u065F\u0670\u06D6-\u06ED\u0640]', '', t)
        t = re.sub(r'[أإآٱ]', 'ا', t).replace('ى', 'ي').replace('ة', 'ه')
        return t.split()
    words = [norm(t) for t in meta['c']]
    shingles = []
    index = {}
    for gi, w in enumerate(words):
        sh = set(' '.join(w[i:i + 3]) for i in range(max(0, len(w) - 2)))
        if len(w) < 3:
            sh = {' '.join(w)} if w else set()
        shingles.append(sh)
        for x in sh:
            index.setdefault(x, []).append(gi)
    sim = {}
    for gi, sh in enumerate(shingles):
        if not sh:
            continue
        cnt = {}
        for x in sh:
            lst = index[x]
            if len(lst) > 40:  # very common phrase, not useful
                continue
            for o in lst:
                if o != gi:
                    cnt[o] = cnt.get(o, 0) + 1
        best = []
        for o, c in cnt.items():
            score = c / max(1, min(len(sh), len(shingles[o])))
            if c >= 2 and score >= 0.45:
                best.append((score, c, o))
        best.sort(reverse=True)
        if best:
            sim[gi] = [o for _, _, o in best[:6]]
    write('similar.json', {str(k): v for k, v in sim.items()})
    print('similar ayahs for', len(sim))

# ---------------- Asbab al-nuzul ----------------
# Filled from the book «الصحيح المسند من أسباب النزول» (مقبل الوادعي) when its text is provided
# in tool/asbab.json as {"surah:ayah": "text"}.
src = 'tool/asbab.json'
asb = {}
if os.path.exists(src):
    for k, v in json.load(open(src, encoding='utf-8')).items():
        ss, aa = k.split(':')
        asb[str(START[int(ss)] + int(aa) - 1)] = v
write('asbab.json', asb)


# ---------------- Madinah mushaf line layout (15 lines per page) ----------------
if not os.path.exists(os.path.join(OUT, 'layout.json.gz')):
    def page_words(p):
        out = []
        pg = 1
        while True:
            d = fetch_json('https://api.quran.com/api/v4/verses/by_page/%d?words=true&per_page=50&page=%d'
                           '&word_fields=text_qpc_hafs,text_uthmani,line_number,code_v1' % (p, pg), tries=5, quiet=True)
            for v in d.get('verses', []):
                ss, aa = v['verse_key'].split(':')
                gi = START[int(ss)] + int(aa) - 1
                for w in v.get('words', []):
                    t = w.get('text_qpc_hafs') or w.get('text_uthmani') or w.get('text') or ''
                    out.append((int(w.get('line_number') or 0), gi, t, 1 if w.get('char_type_name') == 'end' else 0,
                                int(ss), int(aa), w.get('code_v1') or ''))
            nxt = (d.get('pagination') or {}).get('next_page')
            if not nxt:
                break
            pg = int(nxt)
        return out

    try:
        with concurrent.futures.ThreadPoolExecutor(6) as ex:
            allp = list(ex.map(page_words, range(1, 605)))
        pages = []
        basmala = ''
        for pi, words in enumerate(allp):
            p = pi + 1
            lines = {}
            for ln, gi, t, e, ss, aa, cv in words:
                lines.setdefault(ln, []).append((gi, t, e, ss, aa, cv))
            if p == 1:
                basmala = ' '.join(t for ln, gi, t, e, ss, aa, cv in words if ss == 1 and aa == 1 and not e)
            total = max(lines) if p in (1, 2) else 15
            res = [None] * total
            last_s = words[-1][4] if words else 1
            ln = 1
            while ln <= total:
                if ln in lines:
                    res[ln - 1] = ['w', [[gi, t, e, cv] for gi, t, e, ss, aa, cv in lines[ln]]]
                    ln += 1
                    continue
                run = [ln]
                while run[-1] + 1 <= total and (run[-1] + 1) not in lines:
                    run.append(run[-1] + 1)
                nxt = run[-1] + 1
                if nxt <= total:
                    s_next = lines[nxt][0][3]
                else:
                    s_next = last_s + 1
                if len(run) >= 2:
                    res[run[0] - 1] = ['s', s_next]
                    res[run[1] - 1] = ['b']
                elif s_next in (1, 9) or nxt > total:
                    res[run[0] - 1] = ['s', s_next]
                elif run[0] == 1:
                    res[run[0] - 1] = ['b']
                else:
                    res[run[0] - 1] = ['s', s_next]
                ln = run[-1] + 1
            pages.append(res)
        nwords = sum(len(l[1]) for pg_ in pages for l in pg_ if l and l[0] == 'w')
        assert nwords > 80000, nwords
        write_gz('layout.json.gz', {'b': basmala, 'p': pages})
    except Exception as e:  # noqa
        print('WARNING: mushaf layout not built:', e)


# ---------------- Mushaf page fonts (one font per page, as printed) ----------------
QCF = 'assets/qcf'
os.makedirs(QCF, exist_ok=True)
open(os.path.join(QCF, 'keep.txt'), 'w').write('qcf')
QCF_URLS = [
    'https://raw.githubusercontent.com/quran/quran.com-frontend-next/production/public/fonts/quran/hafs/v1/ttf/p%d.ttf',
    'https://raw.githubusercontent.com/quran/quran.com-frontend-next/master/public/fonts/quran/hafs/v1/ttf/p%d.ttf',
    'https://verses.quran.foundation/fonts/quran/hafs/v1/ttf/p%d.ttf',
    'https://static.qurancdn.com/fonts/quran/hafs/v1/ttf/p%d.ttf',
]


def qcf_one(n):
    p = os.path.join(QCF, 'p%d.ttf' % n)
    if os.path.exists(p) and os.path.getsize(p) > 5000:
        return True
    for u in QCF_URLS:
        try:
            b = fetch(u % n, tries=2, quiet=True)
            if len(b) > 5000 and b[:4] in (b'\x00\x01\x00\x00', b'OTTO', b'true'):
                open(p, 'wb').write(b)
                return True
        except Exception:  # noqa
            pass
    return False


qcf_ok = False
try:
    if qcf_one(1):
        with concurrent.futures.ThreadPoolExecutor(8) as ex:
            qcf_ok = all(ex.map(qcf_one, range(1, 605)))
except Exception as e:  # noqa
    print('qcf failed', e)
try:
    lay = json.loads(gzip.open(os.path.join(OUT, 'layout.json.gz')).read().decode('utf-8'))
    has_codes = all(len(w) > 3 and w[3] for l in lay['p'][2] if l and l[0] == 'w' for w in l[1])
except Exception:  # noqa
    has_codes = False
write('qcf.json', bool(qcf_ok and has_codes))
print('qcf fonts', qcf_ok, 'codes', has_codes,
      sum(os.path.getsize(os.path.join(QCF, f)) for f in os.listdir(QCF)))

# ---------------- Fonts ----------------
FONT_SOURCES = {
    'AmiriQuran-Regular.ttf': ['https://github.com/google/fonts/raw/main/ofl/amiriquran/AmiriQuran-Regular.ttf'],
    'Tajawal-Regular.ttf': ['https://github.com/google/fonts/raw/main/ofl/tajawal/Tajawal-Regular.ttf'],
    'Tajawal-Medium.ttf': ['https://github.com/google/fonts/raw/main/ofl/tajawal/Tajawal-Medium.ttf'],
    'Tajawal-Bold.ttf': ['https://github.com/google/fonts/raw/main/ofl/tajawal/Tajawal-Bold.ttf'],
    'Scheherazade-Regular.ttf': ['https://github.com/google/fonts/raw/main/ofl/scheherazadenew/ScheherazadeNew-Regular.ttf'],
    'Lateef-Regular.ttf': ['https://github.com/google/fonts/raw/main/ofl/lateef/Lateef-Regular.ttf'],
    'NotoNaskh-Regular.ttf': [
        'https://github.com/google/fonts/raw/main/ofl/notonaskharabic/NotoNaskhArabic%5Bwght%5D.ttf',
        'https://github.com/notofonts/notofonts.github.io/raw/main/fonts/NotoNaskhArabic/hinted/ttf/NotoNaskhArabic-Regular.ttf',
    ],
    'UthmanicHafs.ttf': [
        'https://github.com/quran/quran.com-frontend-next/raw/production/public/fonts/quran/hafs/uthmanic_hafs/UthmanicHafs1Ver18.ttf',
        'https://github.com/thetruetruth/quran-data-kfgqpc/raw/main/hafs/font/hafs.18.ttf',
        'https://github.com/mustafa0x/qpc-fonts/raw/master/UthmanicHafs1%20Ver18.ttf',
    ],
}
REQUIRED = {'AmiriQuran-Regular.ttf', 'Tajawal-Regular.ttf', 'Tajawal-Medium.ttf', 'Tajawal-Bold.ttf'}
FAMILY = {
    'AmiriQuran-Regular.ttf': 'AmiriQuran',
    'UthmanicHafs.ttf': 'UthmanicHafs',
    'Scheherazade-Regular.ttf': 'Scheherazade',
    'NotoNaskh-Regular.ttf': 'NotoNaskh',
    'Lateef-Regular.ttf': 'Lateef',
}


def is_font(b):
    return len(b) > 30000 and b[:4] in (b'\x00\x01\x00\x00', b'OTTO', b'true')


fonts_ok = []
marker = os.path.join(FONTS, 'fonts.json')
prev = json.load(open(marker)) if os.path.exists(marker) else None
for fname, urls in FONT_SOURCES.items():
    p = os.path.join(FONTS, fname)
    if os.path.exists(p) and prev is not None:
        if fname in FAMILY and FAMILY[fname] in prev:
            fonts_ok.append(FAMILY[fname])
        continue
    data = None
    for u in urls:
        try:
            b = fetch(u, tries=3, quiet=True)
            if is_font(b):
                data = b
                break
            print('not a font', u)
        except Exception as e:  # noqa
            print('font failed', u, e)
    if data:
        open(p, 'wb').write(data)
        print('font', fname, len(data))
        if fname in FAMILY:
            fonts_ok.append(FAMILY[fname])
    elif fname in REQUIRED:
        raise SystemExit('required font missing: ' + fname)
    else:
        shutil.copy(os.path.join(FONTS, 'AmiriQuran-Regular.ttf'), p)
        print('WARNING: font', fname, 'replaced by Amiri Quran')
# calligraphic surah names (one glyph per surah)
sn = os.path.join(FONTS, 'SurahNames.ttf')
sn_ok = prev is not None and 'SurahNames' in prev and os.path.exists(sn)
if not sn_ok:
    base = 'https://raw.githubusercontent.com/quran/quran.com-frontend-next/%s/public/fonts/quran/surah-names/v1/sura_names.%s'
    for br in ('production', 'master'):
        for ext in ('ttf', 'woff2', 'woff'):
            if sn_ok:
                break
            try:
                b = fetch(base % (br, ext), tries=2, quiet=True)
                if ext == 'ttf' and is_font(b):
                    open(sn, 'wb').write(b)
                    sn_ok = True
                elif ext != 'ttf' and len(b) > 5000:
                    import io
                    import subprocess
                    import sys
                    subprocess.run([sys.executable, '-m', 'pip', 'install', '-q', 'fonttools', 'brotli',
                                    '--break-system-packages'], check=False)
                    from fontTools.ttLib import TTFont
                    f = TTFont(io.BytesIO(b))
                    f.flavor = None
                    f.save(sn)
                    sn_ok = os.path.getsize(sn) > 5000
                    print('surah names glyphs', len(f.getGlyphOrder()), [g for g in f.getGlyphOrder()][:40])
                    try:
                        print('ligatures sample', str(f['GSUB'].table.LookupList.Lookup[0].SubTable[0].ligatures)[:300])
                    except Exception as e:  # noqa
                        print('no gsub info', e)
            except Exception as e:  # noqa
                print('surah names font', br, ext, 'failed', e)
if sn_ok:
    fonts_ok.append('SurahNames')
else:
    shutil.copy(os.path.join(FONTS, 'AmiriQuran-Regular.ttf'), sn)
    print('WARNING: surah names font missing')
json.dump(fonts_ok, open(marker, 'w'))
shutil.copy(marker, os.path.join(OUT, 'fonts.json'))
print('fonts', fonts_ok)
print('data ready')
