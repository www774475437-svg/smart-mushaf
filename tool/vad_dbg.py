"""Why does the listener go deaf in some recitations? Prints what the voice detector does."""
import os, sys, json, gzip
import numpy as np, librosa, sherpa_onnx

lay = json.loads(gzip.open('assets/data/layout2.json.gz').read())['p']
q = json.load(open('assets/data/quran.json', encoding='utf-8'))
rows = q['a']


def page_audio(p, folder):
    gs = []
    for l in lay[p - 1]:
        if l and l[0] == 'w':
            gs += [w[0] for w in l[1] if not w[2]]
    gs = sorted(set(gs))
    parts = []
    for g in gs:
        f = f'aud/{folder}_{rows[g][0]:03d}{rows[g][1]:03d}.mp3'
        if not os.path.exists(f):
            print('  missing', f)
            continue
        a = librosa.load(f, sr=16000)[0]
        print(f'  {f} {len(a) / 16000:.1f}s rms {np.sqrt(np.mean(a * a)):.4f} peak {np.abs(a).max():.3f}')
        parts.append(a)
    return np.concatenate(parts).astype(np.float32)


def run(audio, max_speech, min_sil, thr, buf):
    c = sherpa_onnx.VadModelConfig()
    c.silero_vad.model = 'vad/silero_vad.onnx'
    c.silero_vad.min_silence_duration = min_sil
    c.silero_vad.min_speech_duration = 0.25
    c.silero_vad.max_speech_duration = max_speech
    c.silero_vad.threshold = thr
    c.sample_rate = 16000
    vad = sherpa_onnx.VoiceActivityDetector(c, buffer_size_in_seconds=buf)
    line, segs, on = [], [], 0
    for i in range(0, len(audio) - 511, 512):
        vad.accept_waveform(audio[i:i + 512])
        d = vad.is_speech_detected()
        on += d
        if i % 16000 < 512:
            line.append('#' if d else '.')
        while not vad.empty():
            segs.append((vad.front.start / 16000, len(vad.front.samples) / 16000))
            vad.pop()
    tot = sum(s[1] for s in segs)
    print(f' max {max_speech} sil {min_sil} thr {thr} buf {buf}: speech frames {on * 512 / 16000:.0f}s of {len(audio) / 16000:.0f}s, {len(segs)} segments holding {tot:.0f}s, longest {max([s[1] for s in segs] or [0]):.1f}s')
    print('  ' + ''.join(line))
    print('  ' + ' '.join(f'{s[0]:.0f}+{s[1]:.0f}' for s in segs))


for p, folder in [(293, 'Abu_Bakr_Ash-Shaatree_128kbps'), (2, 'Abdurrahmaan_As-Sudais_192kbps'), (604, 'Hani_Rifai_192kbps'), (2, 'Husary_64kbps')]:
    print(p, folder)
    a = page_audio(p, folder)
    for cfg in [(8, 0.35, 0.5, 60), (8, 0.35, 0.5, 20), (20, 0.35, 0.5, 60), (8, 0.35, 0.3, 60), (8, 0.2, 0.5, 60), (4, 0.35, 0.5, 60)]:
        run(a, *cfg)
    run(a / max(1e-6, np.abs(a).max()) * 0.9, 8, 0.35, 0.5, 60)
