"""Finds, inside a recorded tafsir of a whole surah, the second at which every ayah begins.

The recording («المختصر الصوتي»: the ayah is recited, then its tafsir is read) comes as one
file per surah. A speech recogniser writes down what is said with the time of every word,
and the words of each ayah are then looked for, in order, in that transcript.

usage: align_tafsir.py out_dir surah [surah ...]"""
import json, os, re, subprocess, sys, urllib.request

import numpy as np

from faster_whisper import WhisperModel

out = sys.argv[1]
surahs = [int(x) for x in sys.argv[2:]]
os.makedirs(out, exist_ok=True)
URL = 'https://d1.islamhouse.com/data/ar/ih_sounds/chain_01/mokhtasar-fe-tafceer/ar-%03d-mokhtasar-fe-tafceer.mp3'
TASHKEEL = re.compile('[ً-ٰٟۖ-ۭـ]')


def norm(w):
    w = TASHKEEL.sub('', w)
    w = re.sub('[أإآٱ]', 'ا', w).replace('ى', 'ي').replace('ة', 'ه').replace('ؤ', 'و').replace('ئ', 'ي')
    w = re.sub('[^ء-ي]', '', w)
    # long vowels are what the recogniser most often gets wrong in recitation
    return re.sub('[اويء]', '', w) or w


def fetch(url, tries=4):
    for i in range(tries):
        try:
            req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
            return urllib.request.urlopen(req, timeout=120).read()
        except Exception as e:  # noqa
            err = e
    raise err


def same(a, b):
    if a == b:
        return True
    if len(a) >= 3 and len(b) >= 3 and (a in b or b in a):
        return True
    return False


def score(ay, tw, p):
    """How well the opening words of the ayah sit at place p of the transcript."""
    head = ay[:8]
    j, hit = p, 0
    for w in head:
        for k in range(j, min(j + 3, len(tw))):
            if same(w, tw[k]):
                hit += 1
                j = k + 1
                break
    return hit / len(head)


model = WhisperModel(os.environ.get('WHISPER', 'small'), device='cpu', compute_type='int8')
for s in surahs:
    path = os.path.join(out, '%03d.json' % s)
    if os.path.exists(path):
        continue
    mp3 = '/tmp/%03d.mp3' % s
    open(mp3, 'wb').write(fetch(URL % s))
    q = json.loads(fetch('https://api.alquran.cloud/v1/surah/%d/quran-simple-clean' % s))
    ayahs = [a['text'] for a in q['data']['ayahs']]
    if s not in (1, 9) and ayahs[0].startswith('بسم الله الرحمن الرحيم '):
        ayahs[0] = ayahs[0][len('بسم الله الرحمن الرحيم '):]
    pcm = subprocess.run(['ffmpeg', '-v', 'error', '-i', mp3, '-ar', '16000', '-ac', '1', '-f', 's16le', '-'],
                         capture_output=True, check=True).stdout
    audio = np.frombuffer(pcm, np.int16).astype(np.float32) / 32768.0
    segs, info = model.transcribe(audio, language='ar', word_timestamps=True, vad_filter=True, beam_size=2,
                                  condition_on_previous_text=False)
    tw, tt = [], []
    for sg in segs:
        for w in (sg.words or []):
            n = norm(w.word)
            if n:
                tw.append(n)
                tt.append(w.start)
    starts, cur, found = [], 0, 0
    for i, a in enumerate(ayahs):
        ay = [x for x in (norm(w) for w in a.split()) if x]
        best, bp = 0.0, -1
        need = 0.6 if len(ay) >= 3 else 1.0
        # the ayah is expected soon after the one before it: look ahead a bounded stretch
        for p in range(cur, min(len(tw), cur + 900)):
            sc = score(ay, tw, p)
            if sc >= need and same(ay[0], tw[p]) if len(ay) < 3 else sc >= need:
                best, bp = sc, p
                break
            if sc > best:
                best, bp = sc, p
        if bp >= 0 and best >= need:
            starts.append(round(max(0.0, tt[bp] - 0.35), 2))
            cur = bp + max(1, int(len(ay) * 0.6))
            found += 1
        else:
            starts.append(None)
    json.dump({'s': s, 'd': round(info.duration, 1), 't': starts}, open(path, 'w'))
    print('surah', s, 'duration', round(info.duration), 'words', len(tw), 'ayahs found', found, 'of', len(ayahs), flush=True)
    print('  starts', starts[:40], flush=True)
    os.remove(mp3)
