"""Train a small CNN wake-word recognizer on media/ clips and score an iPad take as holdout.

Positives come from media/iapapo and negatives from media/negative (m4a). Positives are
the trimmed wake-word clips, placed at random offsets inside a window whose length comes
from the trimmed positive duration. Negatives are random crops of the negative clips.
Every training sample is augmented with a random gain and background noise. Clips in
--take are scored only, never trained on.

Run it through scripts/train.sh, which sets up the environment first.
"""

import argparse
import csv
import glob
import json
import os
import random
import re
import subprocess
import sys
import tempfile

import numpy as np
import time

import soundfile as sf
import torch
import torch.nn as nn
import torch.nn.functional as F
from scipy.signal import resample_poly
from audiomentations import AddBackgroundNoise, AddGaussianSNR, Compose, Gain, TimeStretch

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_EXTRA = os.path.join(HERE, "..", "lab", "wakeword", "extra")
DEFAULT_MEDIA = os.path.join(HERE, "..", "media")
DEFAULT_OUT = os.path.join(HERE, "..", "lab", "wakeword", "out")
TAKES = os.path.join(HERE, "..", "lab", "wakeword", "takes")
SR = 16000
HOP_S = 0.010
FRAME_S = 0.025
N_MELS = 40
HOP_WINDOW_S = 0.25


ANSI = re.compile(r"\x1b\[[0-9;]*[mK]")


class Tee:
    """Write to the terminal unchanged and to run.log as plain text (no ANSI codes or carriage returns)."""

    def __init__(self, term, log):
        self.term = term
        self.log = log

    def write(self, s):
        self.term.write(s)
        self.log.write(ANSI.sub("", s).replace("\r", ""))

    def flush(self):
        self.term.flush()
        self.log.flush()


def load_clip(path):
    """Read a WAV at any sample rate, resample to 16 kHz, return float32 mono array."""
    x, sr = sf.read(path, dtype="float32")
    if x.ndim > 1:
        x = x.mean(axis=1)
    return resample_poly(x, SR, sr).astype(np.float32)


def decode_m4a(path, tmp):
    """Decode an m4a to a 16-bit WAV in tmp with macOS afconvert (soundfile cannot read AAC). Returns the WAV path."""
    out = os.path.join(tmp, os.path.splitext(os.path.basename(path))[0] + ".wav")
    subprocess.run(["afconvert", "-f", "WAVE", "-d", "LEI16", path, out], check=True)
    return out


def trim_speech(x, pad_s=0.1, rel_db=-20.0):
    """Trim to first and last frame above (peak RMS + rel_db), with padding."""
    n = int(FRAME_S * SR)
    hop = int(HOP_S * SR)
    frames = [x[i:i + n] for i in range(0, max(1, len(x) - n), hop)]
    rms = np.array([np.sqrt(np.mean(f ** 2)) + 1e-9 for f in frames])
    thresh = rms.max() * 10 ** (rel_db / 20)
    active = np.where(rms > thresh)[0]
    if len(active) == 0:
        return x
    start = max(0, active[0] * hop - int(pad_s * SR))
    end = min(len(x), active[-1] * hop + n + int(pad_s * SR))
    return x[start:end]


def mel_filterbank(n_fft, n_mels, sr):
    """Triangular mel filterbank, shape (n_mels, n_fft // 2 + 1)."""
    def hz_to_mel(f):
        return 2595 * np.log10(1 + f / 700)

    def mel_to_hz(m):
        return 700 * (10 ** (m / 2595) - 1)

    mels = np.linspace(hz_to_mel(0), hz_to_mel(sr / 2), n_mels + 2)
    bins = np.floor((n_fft + 1) * mel_to_hz(mels) / sr).astype(int)
    fb = np.zeros((n_mels, n_fft // 2 + 1), dtype=np.float32)
    for m in range(1, n_mels + 1):
        l, c, r = bins[m - 1], bins[m], bins[m + 1]
        for k in range(l, c):
            fb[m - 1, k] = (k - l) / max(1, c - l)
        for k in range(c, r):
            fb[m - 1, k] = (r - k) / max(1, r - c)
    return torch.from_numpy(fb)


N_FFT = int(FRAME_S * SR)
HOP = int(HOP_S * SR)
MEL = mel_filterbank(N_FFT, N_MELS, SR)
WINDOW = torch.hann_window(N_FFT)


def log_mel(wave):
    """(batch, samples) -> (batch, 1, N_MELS, frames) log-mel features."""
    spec = torch.stft(wave, N_FFT, HOP, window=WINDOW, return_complex=True).abs() ** 2
    mel = torch.matmul(MEL, spec)
    return torch.log(mel + 1e-6).unsqueeze(1)


class WakeNet(nn.Module):
    """Three conv blocks over log-mel, global pooling, one logit."""

    def __init__(self):
        super().__init__()
        self.net = nn.Sequential(
            nn.Conv2d(1, 16, 3, padding=1), nn.BatchNorm2d(16), nn.ReLU(), nn.MaxPool2d(2),
            nn.Conv2d(16, 32, 3, padding=1), nn.BatchNorm2d(32), nn.ReLU(), nn.MaxPool2d(2),
            nn.Conv2d(32, 32, 3, padding=1), nn.BatchNorm2d(32), nn.ReLU(),
            nn.AdaptiveAvgPool2d(1), nn.Flatten(), nn.Dropout(0.3), nn.Linear(32, 1),
        )

    def forward(self, wave):
        feats = log_mel(wave)
        feats = (feats - feats.mean(dim=(2, 3), keepdim=True)) / (
            feats.std(dim=(2, 3), keepdim=True) + 1e-5)
        return self.net(feats).squeeze(1)


def place_in_window(clip, window_len, rng):
    """Put clip at a random offset inside a zero window of window_len samples."""
    out = np.zeros(window_len, dtype=np.float32)
    if len(clip) >= window_len:
        s = rng.integers(0, len(clip) - window_len + 1)
        return clip[s:s + window_len]
    off = rng.integers(0, window_len - len(clip) + 1)
    out[off:off + len(clip)] = clip
    return out


NOISE_DIR = os.path.join(HERE, "..", "lab", "wakeword", "noise")

_AUGMENTS = [
    TimeStretch(min_rate=0.9, max_rate=1.1, leave_length_unchanged=True, p=0.5),
    Gain(min_gain_db=-6, max_gain_db=6, p=1.0),
    AddGaussianSNR(min_snr_db=10, max_snr_db=30, p=1.0),
]
if glob.glob(os.path.join(NOISE_DIR, "*.wav")):
    _AUGMENTS.append(AddBackgroundNoise(sounds_path=NOISE_DIR, min_snr_db=3, max_snr_db=30, p=0.5))
AUGMENT = Compose(_AUGMENTS)


def augment(x):
    """audiomentations: time stretch 0.9-1.1x (p=0.5), gain +-6 dB, Gaussian noise at 10-30 dB SNR. Length is preserved."""
    return AUGMENT(samples=x, sample_rate=SR).astype(np.float32)


def sliding_scores(model, clip, window_len):
    """Score every window of clip at HOP_WINDOW_S spacing. Returns (starts_s, probs)."""
    hop = int(HOP_WINDOW_S * SR)
    starts = list(range(0, max(1, len(clip) - window_len + 1), hop))
    batch = torch.from_numpy(np.stack([
        np.pad(clip[s:s + window_len], (0, max(0, window_len - len(clip[s:s + window_len]))))
        for s in starts]))
    with torch.no_grad():
        probs = torch.sigmoid(model(batch)).numpy()
    return np.array(starts) / SR, probs


def main():
    ap = argparse.ArgumentParser(
        description="Train a small CNN wake-word recognizer on one take. Writes wakenet.pt, scores.csv and run.json to a run folder under --out.")
    ap.add_argument("--media", default=DEFAULT_MEDIA,
                    help="folder with iapapo/ (positives) and negative/ (negatives) m4a clips, used for training (default: media)")
    ap.add_argument("--take", default=None,
                    help="iPad take folder of positive-*.wav and negative-*.wav, scored as holdout and never trained on; a bare name is looked up in lab/wakeword/takes/ (default: none, agent holdouts only)")
    ap.add_argument("--holdout", nargs="*", default=[],
                    help="clip names to exclude from training; they are scored and reported as holdout")
    ap.add_argument("--steps", type=int, default=1500, help="training steps, one random batch each (default 1500)")
    ap.add_argument("--batch", type=int, default=32, help="samples per step (default 32)")
    ap.add_argument("--lr", type=float, default=1e-3, help="Adam starting learning rate, cosine-decayed to zero over --steps (default 1e-3)")
    ap.add_argument("--threshold", type=float, default=0.5, help="probability at which a clip counts as triggered (default 0.5)")
    ap.add_argument("--seed", type=int, default=0, help="random seed for reproducible runs (default 0)")
    ap.add_argument("--extra", default=DEFAULT_EXTRA, help="extra clips added to training (default: lab/wakeword/extra)")
    ap.add_argument("--no-extra", action="store_true", help="do not use the extra clips")
    ap.add_argument("--out", default=DEFAULT_OUT, help="output root; run folder is <out>/<version>/<take>-<run-id>/ (default: lab/wakeword/out)")
    ap.add_argument("--version", required=True, help="version of this script, recorded in run.json (set by scripts/train.sh)")
    ap.add_argument("--run-id", required=True, help="run identifier, appended to the run folder name (set by scripts/train.sh)")
    args = ap.parse_args()
    if args.take is None:
        take = None
    else:
        take = os.path.join(TAKES, args.take) if os.path.basename(args.take) == args.take else args.take
    if take is not None:
        take = os.path.abspath(take)
        if not os.path.isdir(take):
            raise SystemExit(f"take directory not found: {take}")
    args.take = take
    run_name = os.path.basename(take) if take else "no-take"
    args.out = os.path.join(args.out, args.version, f"{run_name}-{args.run_id}")
    os.makedirs(args.out, exist_ok=False)
    TTY = sys.stdout.isatty()
    sys.stdout = Tee(sys.stdout, open(os.path.join(args.out, "run.log"), "w"))

    torch.manual_seed(args.seed)
    rng = np.random.default_rng(args.seed)
    random.seed(args.seed)  # audiomentations draws from the global random and numpy generators
    np.random.seed(args.seed)

    train_clips = {}
    holdout_clips = {}
    with tempfile.TemporaryDirectory() as tmp:
        for label, folder in (("positive", "iapapo"), ("negative", "negative")):
            for path in sorted(glob.glob(os.path.join(args.media, folder, "*.m4a"))):
                stem = os.path.splitext(os.path.basename(path))[0]
                clip = load_clip(decode_m4a(path, tmp))
                if label == "negative" and stem.endswith("_2"):
                    holdout_clips[f"{label}-{stem}"] = clip  # full "Popovers" sentence: held out, never trained on
                else:
                    train_clips[f"{label}-{stem}"] = clip
    extra = [] if args.no_extra else glob.glob(os.path.join(args.extra, "*.wav"))
    for path in sorted(extra):
        train_clips[os.path.splitext(os.path.basename(path))[0]] = load_clip(path)
    for path in sorted(glob.glob(os.path.join(take, "*.wav")) if take else []):
        holdout_clips[os.path.splitext(os.path.basename(path))[0]] = load_clip(path)

    trimmed_pos = {n: trim_speech(x) for n, x in train_clips.items() if n.startswith("positive")}
    if not trimmed_pos:
        raise SystemExit(f"no positive clips found in {args.media}/iapapo ({len(train_clips)} training clips loaded)")
    pos_durs = [len(x) / SR for x in trimmed_pos.values()]
    window_s = float(max(pos_durs))  # longest positive, so every wake word fits whole in a window
    window_len = int(window_s * SR)
    print(f"trimmed positives (s): { {n: round(len(x)/SR, 3) for n, x in trimmed_pos.items()} }")
    print(f"window length: {window_s:.3f} s (longest trimmed positive)")

    train_pos = [x for n, x in trimmed_pos.items() if n not in args.holdout]
    train_neg = [trim_speech(x) for n, x in train_clips.items()
                 if n.startswith("negative") and n not in args.holdout]
    if not train_pos or not train_neg:
        raise SystemExit("nothing to train on after --holdout")
    if args.holdout:
        print(f"holdout (not trained on): {args.holdout}")
    if not holdout_clips and not args.holdout:
        print("WARNING: no holdout. Scores below are on training data, not evaluation.")

    neg_lens = np.array([len(x) for x in train_neg], dtype=float)
    neg_p = neg_lens / neg_lens.sum()

    def make_batch():
        labels = rng.integers(0, 2, args.batch)
        waves = []
        for y in labels:
            if y == 1:
                clip = train_pos[rng.integers(len(train_pos))]
                waves.append(augment(place_in_window(clip, window_len, rng)))
            else:
                clip = train_neg[rng.choice(len(train_neg), p=neg_p)]
                if len(clip) < window_len:
                    clip = np.pad(clip, (0, window_len - len(clip)))
                s = rng.integers(0, len(clip) - window_len + 1)
                waves.append(augment(clip[s:s + window_len]))
        return torch.from_numpy(np.stack(waves)), torch.tensor(labels, dtype=torch.float32)

    model = WakeNet()
    opt = torch.optim.Adam(model.parameters(), lr=args.lr, weight_decay=1e-4)
    sched = torch.optim.lr_scheduler.CosineAnnealingLR(opt, args.steps)
    loss_fn = nn.BCEWithLogitsLoss()

    model.train()
    running = 0.0
    start = time.monotonic()
    print(f"training {args.steps} steps", flush=True)
    for step in range(1, args.steps + 1):
        wave, y = make_batch()
        loss = loss_fn(model(wave), y)
        opt.zero_grad()
        loss.backward()
        opt.step()
        sched.step()
        running = 0.98 * running + 0.02 * loss.item() if step > 1 else loss.item()
        if step == args.steps or (TTY and step % 25 == 0):
            elapsed = time.monotonic() - start
            eta = elapsed / step * (args.steps - step)
            msg = f"step {step:5d}/{args.steps}  loss {running:.4f}  elapsed {elapsed:6.1f}s  eta {eta:6.1f}s"
            if TTY and step != args.steps:
                # in-place progress line: terminal only, never written to run.log
                sys.__stdout__.write(f"\r\033[32m{msg}\033[0m")
                sys.__stdout__.flush()
            elif TTY:
                print(f"\r\033[32m{msg}\033[0m\033[K")
            else:
                print(msg)

    model.eval()
    torch.save(model.state_dict(), os.path.join(args.out, "wakenet.pt"))

    rows = []
    trig = {"positive": [0, 0], "negative": [0, 0]}
    for name, x in {**train_clips, **holdout_clips}.items():
        label = "positive" if name.startswith("positive") else "negative"
        role = "holdout" if name in args.holdout or name in holdout_clips else "train"
        if label == "positive":
            x = trim_speech(x)
        starts, probs = sliding_scores(model, x, window_len)
        for t, p in zip(starts, probs):
            rows.append([name, label, role, round(float(t), 3), round(float(p), 4)])
        hit = bool((probs >= args.threshold).any())
        trig[label][0] += int(hit)
        trig[label][1] += 1
        print(f"{name:14s} {label:8s} {role:8s} max={probs.max():.3f} triggered={hit}")

    with open(os.path.join(args.out, "scores.csv"), "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["clip", "label", "role", "start_s", "prob"])
        w.writerows(rows)

    with open(os.path.join(args.out, "run.json"), "w") as f:
        json.dump({"version": args.version, "args": vars(args)}, f, indent=2)

    print(f"\nclips triggered at p>={args.threshold}:")
    print(f"  positives {trig['positive'][0]}/{trig['positive'][1]}")
    print(f"  negatives {trig['negative'][0]}/{trig['negative'][1]}")
    print(f"saved: {os.path.join(args.out, 'wakenet.pt')}, {os.path.join(args.out, 'scores.csv')}")


if __name__ == "__main__":
    main()
