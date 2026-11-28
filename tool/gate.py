"""Finds the stretches of recitation in the microphone's sound by loudness.

The usual voice detector (Silero) was made for talking: on long melodic recitation it goes deaf
for minutes (measured: tool/vad_dbg.py). This one follows loudness against the room's own noise.
The same rules are written in Dart in lib/services/offline_asr.dart (class _Gate).
"""
import numpy as np

FRAME = 512          # 32 ms at 16 kHz
START = 2            # loud frames in a row that open a stretch
STOP = 11            # quiet frames in a row that close it (0.35 s)
PRE = 8              # frames kept from before the stretch opened
MAXF = 280           # a stretch is cut after about 9 s ...
LOOK = 78            # ... at the quietest moment of its last 2.5 s
RATIO = 2.0          # louder than the room by this much = recitation
LOW = 0.0015


class Gate:
    def __init__(self):
        self.floor = None
        self.on = False
        self.run = self.quiet = 0
        self.pre, self.cur, self.lv = [], [], []

    def speaking(self):
        return self.on

    def feed(self, w):
        """Takes one frame; returns the stretches that ended with it (usually none)."""
        e = float(np.sqrt(np.mean(w * w)))
        if self.floor is None:
            self.floor = e
        elif e < self.floor:
            self.floor = self.floor * 0.9 + e * 0.1
        else:
            self.floor *= 1.0005
        loud = e > max(self.floor * RATIO, LOW)
        out = []
        if not self.on:
            self.pre.append(w)
            self.pre = self.pre[-PRE:]
            self.run = self.run + 1 if loud else 0
            if self.run >= START:
                self.on, self.quiet = True, 0
                self.cur, self.lv = list(self.pre), [0.0] * len(self.pre)
                self.pre, self.run = [], 0
            return out
        self.cur.append(w)
        self.lv.append(e)
        self.quiet = 0 if loud else self.quiet + 1
        if self.quiet >= STOP:
            out.append(np.concatenate(self.cur))
            self.on, self.cur, self.lv = False, [], []
        elif len(self.cur) >= MAXF:
            n = len(self.cur)
            k = min(range(n - LOOK, n - 3), key=lambda i: self.lv[i] + self.lv[i + 1] + self.lv[i + 2]) + 1
            out.append(np.concatenate(self.cur[:k]))
            self.cur, self.lv = self.cur[k:], self.lv[k:]
        return out

    def samples(self):
        return np.concatenate(self.cur) if self.cur else np.zeros(0, dtype=np.float32)

    def flush(self):
        out = [np.concatenate(self.cur)] if self.on and self.cur else []
        self.on, self.cur, self.lv = False, [], []
        return out
