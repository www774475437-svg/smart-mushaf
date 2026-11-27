"""Builds the downloadable library (extra tafsirs and tafsirs in other languages).
Reads a checkout of github.com/spa5k/tafsir_api (path in argv[1]) and writes one
gzipped list of 6236 texts per book into argv[2]; the workflow publishes that folder
on the `library` branch, where the app downloads a book when the user asks for it."""
import gzip, html, json, os, re, sys

src, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
LIB = json.load(open('assets/gharib/library.json', encoding='utf-8'))
COUNTS = json.load(open('tool/surah_counts.json'))
START = [0]
for c in COUNTS:
    START.append(START[-1] + c)

if len(sys.argv) > 3 and sys.argv[3] == 'slugs':
    print(' '.join(f"/tafsir/{b['slug']}/*.json" for b in LIB))
    sys.exit(0)


def clean(t):
    t = re.sub(r'<\s*br\s*/?>', '\n', t or '', flags=re.I)
    t = re.sub(r'</\s*(p|div|h\d)\s*>', '\n', t, flags=re.I)
    t = re.sub(r'<sup[^>]*>.*?</sup>', '', t, flags=re.S | re.I)
    t = html.unescape(re.sub(r'<[^>]*>', '', t))
    t = re.sub(r'[ \t]+', ' ', t)
    return re.sub(r'\n\s*\n+', '\n\n', t).strip()


index = []
for b in LIB:
    d = os.path.join(src, 'tafsir', b['slug'])
    lst = [''] * 6236
    for s in range(1, 115):
        p = os.path.join(d, f'{s}.json')
        if not os.path.exists(p):
            continue
        try:
            j = json.load(open(p, encoding='utf-8'))
        except Exception:
            continue
        items = j.get('ayahs', []) if isinstance(j, dict) else j
        for it in items:
            if not isinstance(it, dict):
                continue
            a = int(it.get('ayah') or it.get('ayah_number') or 0)
            if 1 <= a <= COUNTS[s - 1]:
                lst[START[s - 1] + a - 1] = clean(it.get('text', ''))
    # a lesson that explains several ayahs is repeated on each of them: keep it once
    for i in range(6235, 0, -1):
        if lst[i] and lst[i] == lst[i - 1]:
            lst[i] = ''
    n = sum(1 for x in lst if x)
    if n < 200:
        print('SKIP', b['id'], b['slug'], n)
        continue
    raw = json.dumps(lst, ensure_ascii=False, separators=(',', ':')).encode()
    path = os.path.join(out, b['id'] + '.json.gz')
    with gzip.open(path, 'wb', 9) as f:
        f.write(raw)
    index.append({'id': b['id'], 'ayahs': n, 'size': os.path.getsize(path)})
    print('ok', b['id'], n, round(os.path.getsize(path) / 1e6, 2), 'MB')
json.dump(index, open(os.path.join(out, 'index.json'), 'w'))
print(len(index), 'books')
