"""Score a take with one trained run and record the result in that run's folder.

Usage:
    .venv/bin/python scripts/evaluate.py <run folder> <take folder> [--threshold T]

A clip triggers when any of its windows reaches the threshold (default: the run's threshold).
Positive clips are trimmed to speech before scoring, as in training. Negative clips are scored
raw, so a trigger on a negative is a false trigger.

Writes <run folder>/eval-<eval run_id>.json. The evaluation has its own run_id (from nf id, like a
training run), and records model_run_id: the run_id of the trained model it tested, from that model's
run.json. Also recorded: the take's file hashes, the weights hash, the window length and threshold, the
environment, the summary and the per-clip results. Needs a run.json with window_len, which train.py
writes from this version on.
"""

import argparse
import glob
import json
import os
import subprocess
import sys

import torch

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import wakeword_matcher as matcher  # noqa: E402
import train  # noqa: E402


def main():
    ap = argparse.ArgumentParser(description="Score a take with a trained run and record the result in the run folder.")
    ap.add_argument("run", help="run folder with wakenet.pt and run.json")
    ap.add_argument("take", help="take folder with positive-*.wav and negative-*.wav clips")
    ap.add_argument("--threshold", type=float, default=None, help="trigger threshold (default: the run's threshold)")
    args = ap.parse_args()
    run_dir = os.path.abspath(args.run)
    take_dir = os.path.abspath(args.take)

    with open(os.path.join(run_dir, "run.json")) as f:
        meta = json.load(f)
    if "window_len" not in meta:
        raise SystemExit("run.json has no window_len; this run predates the current train.py. Retrain to evaluate it.")
    window_len = meta["window_len"]
    train_args = meta.get("train_args") or meta["args"]  # "args" is the key in runs trained before the rename
    threshold = args.threshold if args.threshold is not None else train_args["threshold"]

    # Own run ID for this evaluation, from the same nf id source as scripts/train.sh (first 6 characters).
    eval_id = subprocess.run(["nf", "id"], capture_output=True, text=True, check=True).stdout.strip()[:6]

    weights = os.path.join(run_dir, "wakenet.pt")
    model = train.WakeNet().eval()
    model.load_state_dict(torch.load(weights, map_location="cpu"))

    take_files = sorted(glob.glob(os.path.join(take_dir, "*.wav")))
    clips = []
    for path in take_files:
        name = os.path.splitext(os.path.basename(path))[0]
        label = "positive" if name.startswith("positive") else "negative"
        x = train.load_clip(path)
        if label == "positive":
            x = train.trim_speech(x)
        _, probs = train.sliding_scores(model, x, window_len)
        peak = float(probs.max())
        clips.append({"clip": name, "label": label, "max_prob": round(peak, 4),
                      "triggered": matcher.clip_triggers(probs, threshold)})

    pos = [c for c in clips if c["label"] == "positive"]
    neg = [c for c in clips if c["label"] == "negative"]
    summary = {
        "positives_triggered": sum(c["triggered"] for c in pos), "positives": len(pos),
        "false_triggers": sum(c["triggered"] for c in neg), "negatives": len(neg),
    }
    record = {
        "run_id": eval_id,
        "model_run_id": train_args["run_id"],
        "model_run": train.repo_relative(run_dir),
        "take": train.repo_relative(take_dir),
        "take_inputs": {train.repo_relative(p): train.git_blob_id(p) for p in take_files},
        "weights_blob": train.git_blob_id(weights),
        "window_len": window_len,
        "threshold": threshold,
        "script_blob": train.git_blob_id(__file__),
        "env": {"python": sys.version.split()[0], "torch": torch.__version__},
        "summary": summary,
        "clips": clips,
    }
    out = os.path.join(run_dir, f"eval-{eval_id}.json")
    with open(out, "w") as f:
        json.dump(record, f, indent=2)

    print(f"take {os.path.basename(take_dir)} with run {os.path.basename(run_dir)}  threshold {threshold}")
    print(f"positives triggered: {summary['positives_triggered']}/{summary['positives']}")
    print(f"false triggers:      {summary['false_triggers']}/{summary['negatives']}")
    print(f"saved: {out}")


if __name__ == "__main__":
    main()
