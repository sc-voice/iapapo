"""Check that a run's Core ML model matches its PyTorch model.

Builds the same windows train.py scores (positives trimmed, negatives raw, hop HOP_WINDOW_S) from one
take folder, computes log-mel features in Python, and runs each window through PyTorch and through
wakenet.mlpackage. Fails if any probability differs by more than --tol, or if a window triggers in one
model and not the other at --threshold. The window length is the one train.py recorded in run.json.

Run it with the export venv, after export_coreml.py:
    .venv/bin/python scripts/test_coreml_match.py <run folder> <take folder>

Writes <run folder>/match-<run_id>.json, where run_id is the match check's own ID (from nf id), with
model_run_id: the run_id of the model tested, and compute_units: the Core ML units it ran on
(--compute-units: CPU_ONLY (default), CPU_AND_GPU, CPU_AND_NE or ALL). Exits 1 on failure. Needs macOS:
predictions use the Core ML runtime.
"""

import argparse
import glob
import json
import os
import subprocess
import sys

import coremltools as ct
import numpy as np
import torch

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import wakeword_matcher as matcher  # noqa: E402
import train  # noqa: E402
from export_coreml import INPUT_NAME, OUTPUT_NAME, load_wakenet, window_len_from_run  # noqa: E402

# Core ML compute units by name: CPU_ONLY; CPU_AND_GPU; CPU_AND_NE (Neural Engine); ALL (Core ML chooses).
COMPUTE_UNITS = {name: getattr(ct.ComputeUnit, name) for name in ("CPU_ONLY", "CPU_AND_GPU", "CPU_AND_NE", "ALL")}


def windows_for_run(take, window_len):
    """Return (names, labels, windows) for the clips in take, built the way train.py scores clips."""
    paths = sorted(glob.glob(os.path.join(take, "*.wav")))
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
    ap.add_argument("take", help="take folder whose clips are scored by both models")
    ap.add_argument("--tol", type=float, default=1e-3, help="max allowed probability difference (default 1e-3)")
    ap.add_argument("--threshold", type=float, default=0.5, help="trigger threshold (default 0.5)")
    ap.add_argument("--compute-units", choices=sorted(COMPUTE_UNITS), default="CPU_ONLY",
                    help="Core ML compute units to run the model on (default CPU_ONLY)")
    args = ap.parse_args()
    run_dir = os.path.abspath(args.run_dir)
    take_dir = os.path.abspath(args.take)

    with open(os.path.join(run_dir, "run.json")) as f:
        run_meta = json.load(f)
    model_run_id = run_meta["args"]["run_id"]
    graph_id = run_meta.get("model", {}).get("graph_id")
    window_len = window_len_from_run(run_dir)
    names, labels, windows = windows_for_run(take_dir, window_len)

    wake = load_wakenet(run_dir)
    feats = train.log_mel(torch.from_numpy(windows))
    with torch.no_grad():
        torch_probs = torch.sigmoid(wake(torch.from_numpy(windows))).numpy()

    mlmodel = ct.models.MLModel(os.path.join(run_dir, "wakenet.mlpackage"),
                                compute_units=COMPUTE_UNITS[args.compute_units])
    feats_np = feats.numpy()
    ml_probs = np.array([
        float(mlmodel.predict({INPUT_NAME: feats_np[i:i + 1]})[OUTPUT_NAME].reshape(-1)[0])
        for i in range(len(windows))])

    diff = np.abs(torch_probs - ml_probs)
    trig_torch = matcher.triggers(torch_probs, args.threshold)
    trig_ml = matcher.triggers(ml_probs, args.threshold)
    disagree = int((trig_torch != trig_ml).sum())
    max_diff = float(diff.max())
    passed = max_diff <= args.tol and disagree == 0

    print(f"\nMax scores for model {model_run_id} (Python vs Swift)")
    print(f"{'clip':14s} {'label':9s} {'windows':>7s} {'Python':>9s} {'Swift':>9s} {'Error':>9s}")
    for name in sorted(set(names)):
        idx = [i for i, n in enumerate(names) if n == name]
        print(f"{name:14s} {labels[idx[0]]:9s} {len(idx):7d} {torch_probs[idx].max():9.5f} "
              f"{ml_probs[idx].max():9.5f} {diff[idx].max():9.2e}")
    print(f"\nwindows: {len(windows)}  max |diff|: {max_diff:.2e}  tol: {args.tol:g}")
    matching = len(windows) - disagree
    print(f"window match, Swift/Python (score >= {args.threshold} matches threshold): "
          f"{matching} of {len(windows)} ({100 * matching / len(windows):.0f}%)")
    print("PASS" if passed else "FAIL")

    # Own run ID for this check, from the same nf id source as training and evaluation (first 6 characters).
    match_id = subprocess.run(["nf", "id"], capture_output=True, text=True, check=True).stdout.strip()[:6]
    report = {
        "run_id": match_id,
        "model_run_id": model_run_id,
        "graph_id": graph_id,
        "take": train.repo_relative(take_dir),
        "window_len": window_len,
        "passed": passed,
        "windows": len(windows),
        "max_abs_diff": max_diff,
        "tol": args.tol,
        "threshold": args.threshold,
        "compute_units": args.compute_units,
        "window_match_percent": round(100 * matching / len(windows), 1),
        "script_blob": train.git_blob_id(__file__),
    }
    with open(os.path.join(run_dir, f"match-{match_id}.json"), "w") as f:
        json.dump(report, f, indent=2)
    sys.exit(0 if passed else 1)


if __name__ == "__main__":
    main()
