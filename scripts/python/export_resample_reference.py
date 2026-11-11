"""Export reference data for the Swift 48 kHz to 16 kHz resampler.

Resamples clips from one take with scipy's resample_poly, the same call train.load_clip makes
(16000 / 48000, reduced to 1 / 3), and writes:

    <out>/<case>.in.f32    raw little-endian float32 input samples (mono, 48 kHz)
    <out>/<case>.out.f32   raw little-endian float32 output samples (16 kHz)
    <out>/taps.f64         raw little-endian float64 FIR taps (61 values, firwin Kaiser beta 5)
    <out>/manifest.json    cases, lengths and the source take

Before writing, the script checks that the closed form the Swift port uses,
y[n] = sum_j h[j] * x[3n + 30 - j] with x = 0 outside the input, equals resample_poly.

Usage:
    .venv/bin/python scripts/python/export_resample_reference.py <take folder> <out folder>
"""

import argparse
import glob
import json
import os
import sys

import numpy as np
import soundfile as sf
from scipy.signal import firwin, resample_poly

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))  # scripts/, for nfhash
import train  # noqa: E402

UP, DOWN = 1, 3  # 16000 / 48000 reduced by gcd
HALF_LEN = 10 * DOWN  # scipy's half length for max(up, down) = 3
KAISER_BETA = 5.0
ODD_LEN = 100001  # not a multiple of 3, so the last output sample is partial


def taps():
    return firwin(2 * HALF_LEN + 1, 1.0 / DOWN, window=("kaiser", KAISER_BETA))


def closed_form(x, h):
    """The formula the Swift port implements. Matches resample_poly to float64 precision."""
    n_out = -(-len(x) // DOWN)
    xp = np.concatenate([np.zeros(HALF_LEN), x, np.zeros(3 * n_out + len(h))])
    y = np.empty(n_out)
    for n in range(n_out):
        base = HALF_LEN + DOWN * n  # index in xp of x[3n]
        # h[j] multiplies x[3n + 30 - j]; xp[base + k] = x[3n - 30 + k] shifts that by 30
        y[n] = np.dot(h, xp[base + HALF_LEN - np.arange(len(h))])
    return y


def main():
    ap = argparse.ArgumentParser(description="Export reference data for the Swift resampler test.")
    ap.add_argument("take", help="take folder of 48 kHz wav clips")
    ap.add_argument("out", help="output folder")
    args = ap.parse_args()
    take_dir = os.path.abspath(args.take)
    out_dir = os.path.abspath(args.out)
    os.makedirs(out_dir, exist_ok=True)

    path = sorted(glob.glob(os.path.join(take_dir, "*.wav")))[0]
    x_full, sr = sf.read(path, dtype="float32")
    assert sr == 48000 and x_full.ndim == 1, f"expected 48 kHz mono, got {sr} Hz {x_full.ndim}-D"

    h = taps()
    cases = {"full": x_full, "odd": x_full[:ODD_LEN]}
    manifest = {"take": train.repo_relative(take_dir), "clip": os.path.basename(path),
                "up": UP, "down": DOWN, "taps": len(h), "kaiser_beta": KAISER_BETA, "cases": {}}
    for name, x in cases.items():
        y = resample_poly(x, 16000, 48000).astype(np.float32)
        ref = closed_form(x.astype(np.float64), h)
        err = float(np.max(np.abs(ref - y)))
        assert err < 1e-6, f"closed form differs from resample_poly by {err} in case {name}"
        x.astype("<f4").tofile(os.path.join(out_dir, f"{name}.in.f32"))
        y.astype("<f4").tofile(os.path.join(out_dir, f"{name}.out.f32"))
        manifest["cases"][name] = {"in": len(x), "out": len(y), "closed_form_max_diff": err}
        print(f"{name}: in {len(x)} out {len(y)} closed-form max diff {err:.2e}")

    h.astype("<f8").tofile(os.path.join(out_dir, "taps.f64"))
    with open(os.path.join(out_dir, "manifest.json"), "w") as f:
        json.dump(manifest, f, indent=2)
    print(f"saved: {out_dir}")


if __name__ == "__main__":
    main()
