"""Score wake-word positives mixed over agent speech, at each agent level in media/.

Usage: scripts/barge_in.py <run folder>

The run folder must hold wakenet.pt and run.json (written by scripts/train.sh).
Each positive clip is tested in a window as long as the longest positive: a random
section of each agent cue (silence for the baseline) with the positive centred on top.
The window's probability is reported and whether it reaches the run's threshold.
A "cue only" row scores the agent cue alone, as a false-trigger check.
"""

import argparse
import glob
import json
import os
import subprocess
import sys
import tempfile

import numpy as np
import soundfile as sf
import torch

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "..")
sys.path.insert(0, HERE)
import train as T  # noqa: E402

MEDIA = os.path.join(ROOT, "media")


def decode_16k(path, tmp):
    """Decode any media file to mono 16 kHz float32 with ffmpeg."""
    out = os.path.join(tmp, os.path.basename(path) + ".wav")
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", path, "-ac", "1", "-ar", str(T.SR), out], check=True)
    x, _ = sf.read(out, dtype="float32")
    return x


def level_label(path):
    """Names with no dB suffix (agent.m4a, agent02.m4a) are full level; agent-XXdb.m4a is XX dB lower."""
    name = os.path.splitext(os.path.basename(path))[0]
    if "-" not in name:
        return "0 dB"
    return "-" + name.split("-")[1].replace("db", "") + " dB"


def attenuation_db(path):
    """Sort key: 0 for agent.m4a, XX for agent-XXdb.m4a."""
    name = os.path.splitext(os.path.basename(path))[0]
    return 0 if name == "agent" else int(name.split("-")[1][:2])


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("run", help="run folder containing wakenet.pt and run.json")
    ap.add_argument("--take", help="take folder with the positives (default: the take recorded in run.json)")
    ap.add_argument("--cue", nargs="+", help="agent cue files to mix over (default: every media/agent*.m4a)")
    ap.add_argument("--snr", nargs="+", type=float, default=[-6, 0, 6, 12],
                    help="wake-word level in dB over the background window's RMS (default: -6 0 6 12)")
    args = ap.parse_args()

    with open(os.path.join(args.run, "run.json")) as f:
        meta = json.load(f)
    meta = meta.get("train_args") or meta["args"]  # "args" is the key in runs trained before the rename
    model = T.WakeNet()
    model.load_state_dict(torch.load(os.path.join(args.run, "wakenet.pt")))
    model.eval()

    positives = {}
    take = args.take or meta["take"]
    if take is None:
        raise SystemExit("run.json has no take; pass --take")
    for path in sorted(glob.glob(os.path.join(take, "positive-*.wav"))):
        name = os.path.splitext(os.path.basename(path))[0]
        positives[name] = T.trim_speech(T.load_clip(path))
    # test window is the longest positive, so every wake word fits whole
    window_len = max(len(x) for x in positives.values())
    threshold = meta["threshold"]
    rng = np.random.default_rng(0)  # fixed seed: the same background sections every run

    agents = args.cue or sorted(glob.glob(os.path.join(MEDIA, "agent*.m4a")), key=attenuation_db)
    print(f"run {os.path.basename(args.run)}  window {window_len / T.SR:.3f} s (longest positive)  threshold {threshold}")
    print(f"{'agent level':>12}  {'positive':>14}  {'max prob':>8}  triggered")

    rows = []
    with tempfile.TemporaryDirectory() as tmp:
        levels = [("none", None)] + [(level_label(p), decode_16k(p, tmp)) for p in agents]
        for label, cue in levels:
            rng = np.random.default_rng(0)  # same background sections at every level
            if cue is None:
                # silence baseline: no background, so no SNR
                cases = [("none", None)]
            else:
                # false-trigger check: max over the agent cue alone, no wake word
                _, cue_probs = T.sliding_scores(model, cue, window_len)
                cue_max = float(cue_probs.max())
                print(f"{label:>12}  {'cue only':>14}  {cue_max:8.3f}  {cue_max >= threshold}")
                cases = [(f"{label} {snr:+.0f} dB", snr) for snr in args.snr]
            # one background section per positive, reused across SNRs so only the level changes
            offsets = {} if cue is None else {
                name: rng.integers(0, len(cue) - window_len + 1) for name in positives}
            for case_label, snr in cases:
                for name, pos in positives.items():
                    # window = random section of the agent cue (or silence), wake word centred on top
                    if cue is None:
                        window = np.zeros(window_len, dtype=np.float32)
                    else:
                        s = offsets[name]
                        window = cue[s:s + window_len].copy()
                    start = (window_len - len(pos)) // 2
                    if snr is not None:
                        # scale the wake word so its RMS sits snr dB above the window's RMS
                        gain = np.sqrt(np.mean(window ** 2)) * 10 ** (snr / 20) / np.sqrt(np.mean(pos ** 2))
                        pos = pos * gain
                    window[start:start + len(pos)] += pos
                    _, probs = T.sliding_scores(model, window, window_len)
                    mx = float(probs.max())
                    hit = mx >= threshold
                    rows.append((case_label, hit))
                    print(f"{case_label:>18}  {name:>14}  {mx:8.3f}  {hit}")

    print("\ntrigger rate by case (centred wake word in longest-positive window):")
    for label in dict.fromkeys(r[0] for r in rows):
        hits = [h for lbl, h in rows if lbl == label]
        print(f"  {label:>18}  {sum(hits)}/{len(hits)}")


if __name__ == "__main__":
    main()
