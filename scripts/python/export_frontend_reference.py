"""Export reference front-end data for the Swift log-mel port.

Takes the windows that scripts/test_coreml_match.py scores (16 kHz, positives trimmed, the run's
window length, hop HOP_WINDOW_S), computes their log-mel features with train.log_mel, and writes:

    <out>/windows.f32   raw little-endian float32 audio, windows x window_len
    <out>/features.f32  raw little-endian float32 log-mel, windows x N_MELS x frames (row-major)
    <out>/manifest.json shapes, clip names and the source run and take

Usage:
    .venv/bin/python scripts/export_frontend_reference.py <run folder> <take folder> <out folder>

The take is resampled by train.load_clip, so this reference set does not test resampling; the Swift test
starts from these 16 kHz windows.
"""

import argparse
import glob
import json
import os
import sys

import numpy as np
import torch

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import train  # noqa: E402
from export_coreml import window_len_from_run  # noqa: E402


def main():
    ap = argparse.ArgumentParser(description="Export reference log-mel features for the Swift front-end test.")
    ap.add_argument("run_dir", help="run folder whose window_len sets the window size")
    ap.add_argument("take", help="take folder of wav clips")
    ap.add_argument("out", help="output folder")
    args = ap.parse_args()
    run_dir = os.path.abspath(args.run_dir)
    take_dir = os.path.abspath(args.take)
    out_dir = os.path.abspath(args.out)
    os.makedirs(out_dir, exist_ok=True)

    window_len = window_len_from_run(run_dir)
    hop = int(train.HOP_WINDOW_S * train.SR)
    names, windows = [], []
    for path in sorted(glob.glob(os.path.join(take_dir, "*.wav"))):
        name = os.path.splitext(os.path.basename(path))[0]
        x = train.load_clip(path)
        if name.startswith("positive"):
            x = train.trim_speech(x)
        for s in range(0, max(1, len(x) - window_len + 1), hop):
            w = np.pad(x[s:s + window_len], (0, max(0, window_len - len(x[s:s + window_len]))))
            names.append(name)
            windows.append(w)
    audio = np.stack(windows).astype("<f4")
    features = train.log_mel(torch.from_numpy(audio.astype(np.float32))).numpy()[:, 0].astype("<f4")

    audio.tofile(os.path.join(out_dir, "windows.f32"))
    features.tofile(os.path.join(out_dir, "features.f32"))
    manifest = {
        "run": train.repo_relative(run_dir),
        "take": train.repo_relative(take_dir),
        "sample_rate": train.SR,
        "n_fft": train.N_FFT,
        "hop": train.HOP,
        "n_mels": train.N_MELS,
        "window_len": window_len,
        "windows": int(audio.shape[0]),
        "frames": int(features.shape[2]),
        "window_clip": names,
        "frontend_nfhash": train.frontend_nfhash(),
        "source_blob": train.git_blob_id(__file__),
    }
    with open(os.path.join(out_dir, "manifest.json"), "w") as f:
        json.dump(manifest, f, indent=2)
    print(f"windows {audio.shape}  features {features.shape}  saved: {out_dir}")


if __name__ == "__main__":
    main()
