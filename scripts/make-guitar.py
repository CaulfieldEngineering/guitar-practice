"""Makes the guide guitar for Practice: short muted notes cut from the FreePats Strat (the clean set: a Fender
recorded direct and run through its maker's amp and cabinet; CC0, public domain, so it can ship in the app).

Joe, 2026-11-14: "can we do a better sound for the guided?" The FreePats Strat is his default guitar (2026-11-12).

For thirteen pitches from the low E to the F an octave and a fourth above the open high E: the hard recording and
the soft one (an accent is the hard one), two takes of each (a down stroke and an up stroke are different takes).
Each is cut at the pick attack, shaped to a short muted note (a fast fall, about a third of a second in all), set
to mono at 24 kHz, 16 bit. The app plays the nearest one, tuned to the note asked for (Engine/GuitarBank.swift).

    python scripts/make-guitar.py ["C:\\Users\\Public\\Documents\\FreePats Guitars\\EGuitarFSBS-clean SFZ+WAV-20260807"]

Writes ios/Practice/Resources/Guitar/g<midi>_<h|s><1|2>.wav (52 files, about 0.9 MB).
"""
import os
import sys

import numpy as np
import soundfile as sf
from scipy.signal import resample_poly

SRC = sys.argv[1] if len(sys.argv) > 1 else r"C:\Users\Public\Documents\FreePats Guitars\EGuitarFSBS-clean SFZ+WAV-20260807"
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OUT = os.path.join(ROOT, "ios", "Practice", "Resources", "Guitar")

# midi -> the sample's name in the FreePats set
NOTES = {40: "E2_s1", 45: "A2_s2", 48: "C3_s2", 50: "D3_s3", 52: "E3_s3", 55: "G3_s4", 59: "B3_s5", 61: "C#4_s5",
         64: "E4_s6", 67: "G4_s6", 71: "B4_s6", 74: "D5_s6", 77: "F5_s6"}
RATE = 24000
LENGTH = 0.36      # seconds kept
FALL = 0.085       # seconds: the note falls by 1/e in this long (a muted note)


def cut(path, peak):
    x, sr = sf.read(path, dtype="float64", always_2d=True)
    x = x.mean(axis=1)
    top = np.max(np.abs(x[: sr * 2]))
    onset = int(np.argmax(np.abs(x) > 0.05 * top))
    start = max(0, onset - int(0.002 * sr))
    x = x[start:start + int(LENGTH * sr)]
    t = np.arange(len(x)) / sr
    x = x * np.exp(-t / FALL)
    fade = int(0.012 * sr)
    x[-fade:] *= np.linspace(1, 0, fade)
    x[: int(0.0005 * sr)] *= np.linspace(0, 1, int(0.0005 * sr))
    y = resample_poly(x, RATE, sr)
    y = y / max(1e-9, np.max(np.abs(y))) * peak
    return y


os.makedirs(OUT, exist_ok=True)
total = 0
for midi, name in NOTES.items():
    for layer, suffix, peak in (("h", "", 0.9), ("s", "_soft", 0.55)):
        for take in (1, 2):
            src = os.path.join(SRC, "samples", "bridge", f"{name}{suffix}_0{take}.wav")
            if not os.path.exists(src):
                # No soft recording of this note: the hard one, quieter.
                src = os.path.join(SRC, "samples", "bridge", f"{name}_0{take}.wav")
            y = cut(src, peak)
            dest = os.path.join(OUT, f"g{midi}_{layer}{take}.wav")
            sf.write(dest, y, RATE, subtype="PCM_16")
            total += os.path.getsize(dest)
print(f"{len(NOTES) * 4} notes, {total / 1024 / 1024:.2f} MB, in {OUT}")
