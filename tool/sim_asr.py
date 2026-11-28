"""Runs the app's offline listening pipeline on real recitations, away from the phone.

Mirrors lib/services/offline_asr.dart (the same loudness gate, the same rule for writing
down a stretch while it is still being said) and writes every text the app would receive, with
the moment it would arrive, so tool/eval_matcher.dart can replay it through the app's matcher.
"""
import gzip, io, json, os, sys, time, urllib.request
import numpy as np, librosa, sherpa_onnx

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gate import Gate

MODEL, OUT = sys.argv[1], sys.argv[2]
SLOW = float(os.environ.get('SLOW', '3'))  # the phone is about this much slower than the build machine
PAGES = [int(x) for x in os.environ.get('PAGES', '2,446,582,604').split(',')]
RECITERS = os.environ.get('RECITERS', 'Husary_64kbps,Alafasy_64kbps,Minshawy_Murattal_128kbps,Abu_Bakr_Ash-Shaatree_128kbps').split(',')
VARIANTS = os.environ.get('VARIANTS', 'clean,room,noisy').split(',')

lay = json.loads(gzip.open('assets/data/layout2.json.gz').read())['p']
q = json.load(open('assets/data/quran.json', encoding='utf-8'))
rows, clean = q['a'], q['c']

CTC = os.path.exists(f'{MODEL}/model.int8.onnx')
if CTC:
    rec = sherpa_onnx.OfflineRecognizer.from_zipformer_ctc(model=f'{MODEL}/model.int8.onnx', tokens=f'{MODEL}/tokens.txt', num_threads=2)
else:
    rec = sherpa_onnx.OfflineRecognizer.from_whisper(
        encoder=f'{MODEL}/encoder.int8.onnx', decoder=f'{MODEL}/decoder.int8.onnx', tokens=f'{MODEL}/tokens.txt',
        language='ar', task='transcribe', num_threads=4)
MIN_STEP = 4800 if CTC else 9600  # the fast model writes what is being said three times a second


def write(samples):
    s = rec.create_stream()
    s.accept_waveform(16000, samples)
    t0 = time.time()
    rec.decode_stream(s)
    return s.result.text.strip(), (time.time() - t0) * SLOW


def page_words(p):
    ws = []
    for l in lay[p - 1]:
        if l and l[0] == 'w':
            ws += [(w[0], w[1]) for w in l[1] if not w[2]]
    return ws


def count_in(p, g):
    return sum(1 for (gg, _) in page_words(p) if gg == g) if 1 <= p <= 604 else 0


def fetch(folder, s, a):
    os.makedirs('aud', exist_ok=True)
    f = f'aud/{folder}_{s:03d}{a:03d}.mp3'
    if not os.path.exists(f):
        req = urllib.request.Request(f'https://everyayah.com/data/{folder}/{s:03d}{a:03d}.mp3', headers={'User-Agent': 'Mozilla/5.0'})
        open(f, 'wb').write(urllib.request.urlopen(req, timeout=60).read())
    return librosa.load(f, sr=16000)[0]


def simulate(audio):
    gate = Gate()
    ev = []
    last_partial = 0
    step = MIN_STEP
    clock = 0.0
    WIN = 512

    def final(seg):
        nonlocal last_partial, clock
        last_partial = 0
        if len(seg) < 4000:
            ev.append([round(clock, 2), 'f', ''])
            return
        t, d = write(seg)
        clock += d
        ev.append([round(clock, 2), 'f', t])

    for i in range(0, len(audio) - WIN + 1, WIN):
        clock = max(clock, (i + WIN) / 16000)
        for seg in gate.feed(audio[i:i + WIN]):
            final(seg)
        n = len(gate.cur) * WIN
        if gate.speaking() and n >= (6400 if CTC else 11200) and n - last_partial >= step:
            last_partial = n
            t, d = write(gate.samples())
            clock += d
            ev.append([round(clock, 2), 'p', t])
            step = int(min(48000, max(MIN_STEP, d * 1000 * 16 * 1.4)))
    for seg in gate.flush():
        final(seg)
    return ev


rng = np.random.default_rng(1)
cases = []
for p in PAGES:
    ws = page_words(p)
    gs = sorted({g for g, _ in ws})
    # only ayahs that sit whole on this page
    keep = [g for g in gs if count_in(p - 1, g) == 0 and count_in(p + 1, g) == 0]
    ws = [(g, t) for g, t in ws if g in keep]
    for folder in RECITERS:
        try:
            parts, ends, pos = [], {}, 0
            for g in keep:
                a = fetch(folder, rows[g][0], rows[g][1])
                parts.append(a)
                pos += len(a)
                ends[str(g)] = round(pos / 16000, 2)
            audio = np.concatenate(parts).astype(np.float32)
        except Exception as e:
            print('skip', p, folder, e)
            continue
        for v in VARIANTS:
            x = audio
            if v == 'room':
                # a phone on the table in a quiet room: softer, with a little hiss
                x = (audio * 0.5 + rng.normal(0, 0.003, len(audio))).astype(np.float32)
            if v == 'noisy':
                # far from the mouth with loud hiss: the hard case
                x = (audio * 0.35 + rng.normal(0, 0.012, len(audio))).astype(np.float32)
            t0 = time.time()
            ev = simulate(x)
            print(f'page {p} {folder} {v}: {len(audio) / 16000:.0f}s audio, {len(ev)} texts, {time.time() - t0:.0f}s')
            cases.append({'name': f'{p} {folder.split("_")[0]} {v}', 'words': [{'g': g, 't': t} for g, t in ws],
                          'clean': {str(g): clean[g] for g in keep}, 'ends': ends, 'events': ev})
json.dump({'model': MODEL, 'cases': cases}, open(OUT, 'w', encoding='utf-8'), ensure_ascii=False)
