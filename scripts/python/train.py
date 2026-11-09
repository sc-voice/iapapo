"""Train a small CNN wake-word recognizer on media/ clips and score an iPad take as holdout.

Positives come from media/iapapo and negatives from media/negative (m4a). Positives are
the trimmed wake-word clips, placed at random offsets inside a window whose length comes
from the trimmed positive duration. Negatives are random crops of the negative clips.
Every training sample is augmented with a random gain and background noise. Clips in
--take are scored only, never trained on.

Run it on a train.json from scripts/python/train_cli.py:
    train.py <run folder>/train.json --run-id ID
scripts/train.sh does that and sets up the environment first.
"""

import argparse
import csv
import glob
import inspect
import hashlib
import json
import os
import random
import re
import subprocess
import sys
import tempfile
from types import SimpleNamespace

import numpy as np
import time

import soundfile as sf
import torch
import torch.nn as nn
import torch.nn.functional as F
from scipy.signal import resample_poly
from audiomentations import AddBackgroundNoise, AddGaussianSNR, Compose, Gain, TimeStretch

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))  # scripts/, for nfhash
from nfhash import nf_hash, nf_hash_file

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "..")
SCHEMA = 1  # train.json schema; must match scripts/python/train_cli.py
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


def git_blob_id(path):
    """Git's blob ID for a file: SHA-1 over "blob <size>\\0" plus the bytes, the same value as `git hash-object <file>`."""
    with open(path, "rb") as f:
        data = f.read()
    return hashlib.sha1(b"blob %d\0" % len(data) + data).hexdigest()


def repo_relative(path):
    """Path relative to the repo root, so run.json reads the same on any machine."""
    return os.path.relpath(os.path.abspath(path), ROOT)


def add_input(inputs, holdout_paths, path, label, holdout=False):
    """Record one clip file for run.json: under input-positives or input-negatives by label, and in holdout_paths if held out."""
    key = "input-positives" if label == "positive" else "input-negatives"
    rel = repo_relative(path)
    inputs[key][rel] = nf_hash_file(path)
    if holdout:
        holdout_paths.append(rel)


def frontend_nfhash():
    """nf hash of the front end: the source of mel_filterbank and log_mel, the audio constants, and the window type.
    It changes only when the features the model sees change. The Swift port records the same value."""
    source = [line for f in (mel_filterbank, log_mel) for line in inspect.getsource(f).splitlines()]
    constants = {"SR": SR, "N_MELS": N_MELS, "FRAME_S": FRAME_S, "HOP_S": HOP_S,
                 "N_FFT": N_FFT, "HOP": HOP, "window": "torch.hann_window(N_FFT), periodic"}
    return nf_hash(json.dumps({"source": source, "constants": constants}, sort_keys=True).encode())


def model_description(model):
    """run.json entry for the network: class, parameter count, and the audio constants it uses."""
    graph = {"class": type(model).__name__,
             "constants": {"SR": SR, "N_MELS": N_MELS, "FRAME_S": FRAME_S, "HOP_S": HOP_S,
                           "N_FFT": N_FFT, "HOP": HOP, "HOP_WINDOW_S": HOP_WINDOW_S}}
    return {"frontend_nfhash": frontend_nfhash(),
            "params": sum(p.numel() for p in model.parameters()), **graph}


def log_mel(wave):
    """(batch, samples) -> (batch, 1, N_MELS, frames) log-mel features."""
    spec = torch.stft(wave, N_FFT, HOP, window=WINDOW, return_complex=True).abs() ** 2
    mel = torch.matmul(MEL, spec)
    return torch.log(mel + 1e-6).unsqueeze(1)


class WakeNet(nn.Module):
    """Three conv blocks over log-mel with frequency kept as channel features, a GRU over 22 time steps, and a per-step logit max-pooled over time."""

    def __init__(self):
        super().__init__()
        # Every PyTorch default is written out, so a change in PyTorch's defaults cannot change this network.
        self.conv = nn.Sequential(
            nn.Conv2d(1, 16, kernel_size=3, stride=1, padding=1, dilation=1, groups=1, bias=True, padding_mode="zeros"),
            nn.BatchNorm2d(16, eps=1e-5, momentum=0.1, affine=True, track_running_stats=True),
            nn.ReLU(inplace=False),
            nn.MaxPool2d(kernel_size=2, stride=2, padding=0, dilation=1, ceil_mode=False),
            nn.Conv2d(16, 32, kernel_size=3, stride=1, padding=1, dilation=1, groups=1, bias=True, padding_mode="zeros"),
            nn.BatchNorm2d(32, eps=1e-5, momentum=0.1, affine=True, track_running_stats=True),
            nn.ReLU(inplace=False),
            nn.MaxPool2d(kernel_size=2, stride=2, padding=0, dilation=1, ceil_mode=False),
            nn.Conv2d(32, 32, kernel_size=3, stride=1, padding=1, dilation=1, groups=1, bias=True, padding_mode="zeros"),
            nn.BatchNorm2d(32, eps=1e-5, momentum=0.1, affine=True, track_running_stats=True),
            nn.ReLU(inplace=False),
            nn.AdaptiveAvgPool2d((10, 22)),
        )
        self.gru = nn.GRU(input_size=320, hidden_size=128, num_layers=1, bias=True, batch_first=True,
                          dropout=0.0, bidirectional=False)
        self.drop = nn.Dropout(p=0.3, inplace=False)
        self.head = nn.Linear(128, 1, bias=True)

    def score_features(self, feats):
        """(batch, 1, N_MELS, frames) log-mel -> (batch,) wake-word logits. Shared by training, scoring and Core ML export."""
        feats = (feats - feats.mean(dim=(2, 3), keepdim=True)) / (
            feats.std(dim=(2, 3), keepdim=True) + 1e-5)
        x = self.conv(feats)                             # [batch, 32, 10, 22]
        x = x.flatten(1, 2).permute(0, 2, 1)             # [batch, 22, 320]: spectral shape kept per step
        out, _ = self.gru(x)                             # [batch, 22, 128]
        logits = self.head(self.drop(out)).squeeze(-1)   # [batch, 22]
        return logits.max(dim=1).values                  # strongest step per window

    def forward(self, wave):
        """(batch, samples) audio -> (batch,) wake-word logits."""
        return self.score_features(log_mel(wave))


def place_in_window(clip, window_len, rng):
    """Put clip at a random offset inside a zero window of window_len samples."""
    out = np.zeros(window_len, dtype=np.float32)
    if len(clip) >= window_len:
        s = rng.integers(0, len(clip) - window_len + 1)
        return clip[s:s + window_len]
    off = rng.integers(0, window_len - len(clip) + 1)
    out[off:off + len(clip)] = clip
    return out


_AUGMENTS = [
    TimeStretch(min_rate=0.9, max_rate=1.1, leave_length_unchanged=True, p=0.5),
    Gain(min_gain_db=-6, max_gain_db=6, p=1.0),
    AddGaussianSNR(min_snr_db=10, max_snr_db=30, p=1.0),
]
def build_augment(noise_dir, noise_snr=(3.0, 30.0)):
    """Return the training augmentation chain. Background noise from noise_dir is added at noise_snr (min, max) dB, p=0.5."""
    augments = list(_AUGMENTS)
    augments.append(AddBackgroundNoise(sounds_path=noise_dir, min_snr_db=noise_snr[0], max_snr_db=noise_snr[1], p=0.5))
    return Compose(augments)


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


def load_train_json(path):
    """Read train.json, the complete input record for one run, and check its keys and types. Never modifies the file.

    Args:
        path: the train.json written by scripts/python/train_cli.py.

    Returns:
        The record as a dict.

    Raises:
        SystemExit: if the schema differs, a key is missing or unknown, or a value has the wrong type.
    """
    with open(path) as f:
        rec = json.load(f)
    if rec.get("schema") != SCHEMA:
        raise SystemExit(f"{path}: schema {rec.get('schema')!r}, expected {SCHEMA}")
    kinds = {"media": str, "wakeword": str, "take": (str, type(None)), "holdout": list, "steps": int,
             "batch": int, "lr": float, "threshold": float, "seed": int, "noise": str,
             "noise_snr": list, "window_scale": float, "extra": str, "no_extra": bool}
    unknown = sorted(set(rec) - set(kinds) - {"schema"})
    missing = sorted(set(kinds) - set(rec))
    if unknown or missing:
        raise SystemExit(f"{path}: unknown keys {unknown}, missing keys {missing}")
    for key, kind in kinds.items():
        bad_bool = kind is int and isinstance(rec[key], bool)
        if bad_bool or not isinstance(rec[key], kind):
            raise SystemExit(f"{path}: {key} has the wrong type: {rec[key]!r}")
    if len(rec["noise_snr"]) != 2 or not all(isinstance(v, float) for v in rec["noise_snr"]):
        raise SystemExit(f"{path}: noise_snr must be two floats")
    return rec


def main():
    ap = argparse.ArgumentParser(
        description="Train a wake-word CNN from a train.json input record. Writes wakenet.pt, scores.csv, run.json and run.log into the folder that holds train.json.")
    ap.add_argument("train_json", help="train.json input record, written by scripts/python/train_cli.py")
    ap.add_argument("--run-id", required=True, help="run identifier, recorded in run.json (set by scripts/train.sh)")
    cli = ap.parse_args()
    rec = load_train_json(cli.train_json)
    out = os.path.dirname(os.path.abspath(cli.train_json))
    if os.path.exists(os.path.join(out, "run.json")):
        raise SystemExit(f"{out} already holds a run; use a new run folder")
    args = SimpleNamespace(**rec, run_id=cli.run_id, out=out, version=nf_hash_file(__file__)[:9])
    args.media = os.path.join(ROOT, args.media)
    args.extra = os.path.join(ROOT, args.extra)
    noise_dir = os.path.join(ROOT, args.noise)
    noise_wavs = sorted(glob.glob(os.path.join(noise_dir, "*.wav")))
    if not noise_wavs:
        raise SystemExit(f"noise folder has no WAVs: {noise_dir}")
    # Hashed on load, so run.json certifies the noise files this run was trained with.
    noise_nfhash = {os.path.basename(p): nf_hash_file(p) for p in noise_wavs}
    global AUGMENT
    AUGMENT = build_augment(noise_dir, tuple(args.noise_snr))
    take = os.path.join(ROOT, args.take) if args.take else None
    if take is not None and not os.path.isdir(take):
        raise SystemExit(f"take directory not found: {take}")
    args.take = take
    TTY = sys.stdout.isatty()
    sys.stdout = Tee(sys.stdout, open(os.path.join(args.out, "run.log"), "w"))

    torch.manual_seed(args.seed)
    rng = np.random.default_rng(args.seed)
    random.seed(args.seed)  # audiomentations draws from the global random and numpy generators
    np.random.seed(args.seed)

    train_clips = {}
    holdout_clips = {}
    inputs = {"input-positives": {}, "input-negatives": {}}  # every clip file that reaches the weights, with its hash, for run.json
    holdout_paths = []
    with tempfile.TemporaryDirectory() as tmp:
        for label, folder in (("positive", args.wakeword), ("negative", "negative")):
            for path in sorted(glob.glob(os.path.join(args.media, folder, "*.m4a"))):
                stem = os.path.splitext(os.path.basename(path))[0]
                clip = load_clip(decode_m4a(path, tmp))
                if label == "negative" and stem.endswith(("_1", "_2", "_3")):
                    holdout_clips[f"{label}-{stem}"] = clip  # microphone (_1), full "Popovers" (_2) and weather (_3) sentences: held out, never trained on
                    add_input(inputs, holdout_paths, path, label, holdout=True)
                else:
                    train_clips[f"{label}-{stem}"] = clip
                    add_input(inputs, holdout_paths, path, label)
    extra = [] if args.no_extra else glob.glob(os.path.join(args.extra, "*.wav"))
    for path in sorted(extra):
        name = os.path.splitext(os.path.basename(path))[0]
        train_clips[name] = load_clip(path)
        add_input(inputs, holdout_paths, path, "positive" if name.startswith("positive") else "negative")
    for path in sorted(glob.glob(os.path.join(take, "*.wav")) if take else []):
        name = os.path.splitext(os.path.basename(path))[0]
        holdout_clips[name] = load_clip(path)
        add_input(inputs, holdout_paths, path, "positive" if name.startswith("positive") else "negative", holdout=True)

    trimmed_pos = {n: trim_speech(x) for n, x in train_clips.items() if n.startswith("positive")}
    if not trimmed_pos:
        raise SystemExit(f"no positive clips found in {args.media}/iapapo ({len(train_clips)} training clips loaded)")
    pos_durs = [len(x) / SR for x in trimmed_pos.values()]
    window_s = float(max(pos_durs)) * args.window_scale  # longest positive, scaled; the wake word always fits whole
    window_len = int(window_s * SR)
    print(f"trimmed positives (s): { {n: round(len(x)/SR, 3) for n, x in trimmed_pos.items()} }")
    print(f"window length: {window_s:.3f} s (longest trimmed positive x {args.window_scale})")

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

    from importlib.metadata import PackageNotFoundError, version as pkg_version
    try:
        coremltools_version = pkg_version("coremltools")
    except PackageNotFoundError:
        coremltools_version = None
    env = {"python": sys.version.split()[0], "torch": torch.__version__, "numpy": np.__version__,
           "coremltools": coremltools_version}
    # train_args is the train.json record plus the run id, which the readers look up.
    run_args = {**rec, "run_id": args.run_id}
    with open(os.path.join(args.out, "run.json"), "w") as f:
        json.dump({"version": args.version, "wakeword": args.wakeword, "env": env,
                   "train_py_nfhash": nf_hash_file(__file__), "wakenet_nfhash": nf_hash_file(os.path.join(args.out, "wakenet.pt")),
                   "model": model_description(model), "window_len": window_len, "inputs_nfhash": inputs,
                   "holdout": holdout_paths, "noise_nfhash": noise_nfhash,
                   "train_json_nfhash": nf_hash_file(os.path.join(args.out, "train.json")), "train_args": run_args}, f, indent=2)

    print(f"\nclips triggered at p>={args.threshold}:")
    print(f"  positives {trig['positive'][0]}/{trig['positive'][1]}")
    print(f"  negatives {trig['negative'][0]}/{trig['negative'][1]}")
    print(f"saved: {os.path.join(args.out, 'wakenet.pt')}, {os.path.join(args.out, 'scores.csv')}")


if __name__ == "__main__":
    main()
