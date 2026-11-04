"""Check that a run's Core ML model matches its PyTorch model.

Builds the same windows train.py scores (positives trimmed, negatives raw, hop HOP_WINDOW_S),
computes log-mel features in Python, and runs each window through PyTorch and through
wakenet.mlpackage. Fails if any probability differs by more than --tol, or if a window
triggers in one model and not the other at --threshold.

Run it with the export venv, after export_coreml.py:
    lab/wakeword/.venv-export/bin/python scripts/test_coreml_parity.py <run folder>

Writes <run folder>/parity.json. Exits 1 on failure. Needs macOS: predictions use the
Core ML runtime.
"""

import argparse
import glob
import json
import os
import sys

import coremltools as ct
import numpy as np
import torch

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import train  # noqa: E402
from export_coreml import INPUT_NAME, OUTPUT_NAME, load_wakenet, take_window_len  # noqa: E402


def windows_for_run(take, extra_dir, use_extra, window_len):
    """Return (names, labels, windows) built the way train.py scores clips."""
    paths = sorted(glob.glob(os.path.join(take, "*.wav")))
    if use_extra:
        paths += sorted(glob.glob(os.path.join(extra_dir, "*.wav")))
    hop = int(train.HOP_WINDOW_S * train.SR)
    names, labels, windows = [], [], []
    for path in paths:
        name = os.path.splitext(os.path.basename(path))[0]
        x = train.load_clip(path)
        if name.startswith("positive"):
            x = train.trim_speech(x)
        label = "positive" if name.startswith("positive") else "negative"
        for s in range(0, max(1, len(x) - window_len + 1), hop):
            w = x[s:s + window_len]
            w = np.pad(w, (0, window_len - len(w)))
            names.append(name)
            labels.append(label)
            windows.append(w)
    return names, labels, np.stack(windows).astype(np.float32)


def main():
    ap = argparse.ArgumentParser(description="Compare a run's PyTorch and Core ML wake-word probabilities.")
    ap.add_argument("run_dir", help="run folder with wakenet.pt, wakenet.mlpackage and run.json")
    ap.add_argument("--tol", type=float, default=1e-3, help="max allowed probability difference (default 1e-3)")
    ap.add_argument("--threshold", type=float, default=0.5, help="trigger threshold (default 0.5)")
    args = ap.parse_args()
    run_dir = os.path.abspath(args.run_dir)

    with open(os.path.join(run_dir, "run.json")) as f:
        run_args = json.load(f)["args"]
    take = run_args["take"]
    window_len = take_window_len(take)
    names, labels, windows = windows_for_run(
        take, train.DEFAULT_EXTRA, not run_args.get("no_extra", False), window_len)

    wake = load_wakenet(run_dir)
    feats = train.log_mel(torch.from_numpy(windows))
    with torch.no_grad():
        torch_probs = torch.sigmoid(wake(torch.from_numpy(windows))).numpy()

    mlmodel = ct.models.MLModel(os.path.join(run_dir, "wakenet.mlpackage"),
                                compute_units=ct.ComputeUnit.CPU_ONLY)
    feats_np = feats.numpy()
    ml_probs = np.array([
        float(mlmodel.predict({INPUT_NAME: feats_np[i:i + 1]})[OUTPUT_NAME].reshape(-1)[0])
        for i in range(len(windows))])

    diff = np.abs(torch_probs - ml_probs)
    trig_torch = torch_probs >= args.threshold
    trig_ml = ml_probs >= args.threshold
    disagree = int((trig_torch != trig_ml).sum())
    max_diff = float(diff.max())
    passed = max_diff <= args.tol and disagree == 0

    print(f"{'clip':14s} {'label':9s} {'windows':>7s} {'max torch':>10s} {'max coreml':>11s} {'max |diff|':>11s}")
    for name in sorted(set(names)):
        idx = [i for i, n in enumerate(names) if n == name]
        print(f"{name:14s} {labels[idx[0]]:9s} {len(idx):7d} {torch_probs[idx].max():10.5f} "
              f"{ml_probs[idx].max():11.5f} {diff[idx].max():11.2e}")
    print(f"\nwindows: {len(windows)}  max |diff|: {max_diff:.2e}  tol: {args.tol:g}")
    print(f"trigger disagreements at p>={args.threshold}: {disagree}")
    print("PASS" if passed else "FAIL")

    report = {
        "passed": passed,
        "windows": len(windows),
        "max_abs_diff": max_diff,
        "tol": args.tol,
        "threshold": args.threshold,
        "trigger_disagreements": disagree,
    }
    with open(os.path.join(run_dir, "parity.json"), "w") as f:
        json.dump(report, f, indent=2)
    sys.exit(0 if passed else 1)


if __name__ == "__main__":
    main()
