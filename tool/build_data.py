"""Downloads the Quran text, tafsirs, translation and fonts used by the app.

Runs in GitHub Actions before the build. Files that already exist are kept
(the workflow caches them), so the sources are only hit once.
"""
import json
import os
import time
import urllib.request

OUT = 'assets/data'
FONTS = 'assets/fonts'
os.makedirs(OUT, exist_ok=True)
os.makedirs(FONTS, exist_ok=True)

UA = {'User-Agent': 'Mozilla/5.0 (smart-mushaf build)'}


def fetch(url):
    last = None
    for i in range(6):
        try:
            req = urllib.request.Request(url, headers=UA)
            with urllib.request.urlopen(req, timeout=180) as r:
                return r.read()
        except Exception as e:  # noqa
            last = e
            print('retry', url, e)
            time.sleep(5 + i * 5)
    raise SystemExit(f'failed to download {url}: {last}')


def edition(name):
    data = json.loads(fetch(f'https://api.alquran.cloud/v1/quran/{name}').decode('utf-8'))
    return data['data']['surahs']


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

for fname, ed in [('muyassar.json', 'ar.muyassar'), ('jalalayn.json', 'ar.jalalayn'), ('en.json', 'en.sahih')]:
    if not os.path.exists(os.path.join(OUT, fname)):
        lst = flat(edition(ed))
        assert len(lst) == 6236, (fname, len(lst))
        write(fname, lst)

for fname, url in [
    ('AmiriQuran-Regular.ttf', 'https://github.com/google/fonts/raw/main/ofl/amiriquran/AmiriQuran-Regular.ttf'),
    ('Tajawal-Regular.ttf', 'https://github.com/google/fonts/raw/main/ofl/tajawal/Tajawal-Regular.ttf'),
    ('Tajawal-Medium.ttf', 'https://github.com/google/fonts/raw/main/ofl/tajawal/Tajawal-Medium.ttf'),
    ('Tajawal-Bold.ttf', 'https://github.com/google/fonts/raw/main/ofl/tajawal/Tajawal-Bold.ttf'),
]:
    p = os.path.join(FONTS, fname)
    if not os.path.exists(p):
        b = fetch(url)
        assert len(b) > 10000, fname
        open(p, 'wb').write(b)
        print('font', fname, len(b))

print('data ready')
