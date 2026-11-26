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
json.dump(fonts_ok, open(marker, 'w'))
shutil.copy(marker, os.path.join(OUT, 'fonts.json'))
print('fonts', fonts_ok)
print('data ready')
