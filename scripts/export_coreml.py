"""Export one trained WakeNet run to a Core ML ML Program.

The exported model takes log-mel features, shape (1, 1, N_MELS, frames), not audio.
The front end (log_mel in train.py) stays in Python; the Swift front end is a later step.
Per-clip feature normalization is inside the model, so it matches training.
Output "prob" is the wake-word probability for one window.

Run it with the export venv, which has coremltools:
    lab/wakeword/.venv-export/bin/python scripts/export_coreml.py <run folder>

Reads <run folder>/wakenet.pt and run.json. Writes <run folder>/wakenet.mlpackage
and <run folder>/export.json. The window length comes from the take named in run.json,
computed the same way train.py does.
"""

import argparse
import glob
import json
import os
import sys

import coremltools as ct
import torch
import torch.nn as nn

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import train  # noqa: E402

INPUT_NAME = "logmel"
OUTPUT_NAME = "prob"


class ExportNet(nn.Module):
    """WakeNet from log-mel input: per-clip normalization, conv net, sigmoid."""

    def __init__(self, wakenet):
        super().__init__()
        self.net = wakenet.net

    def forward(self, feats):
        feats = (feats - feats.mean(dim=(2, 3), keepdim=True)) / (
            feats.std(dim=(2, 3), keepdim=True) + 1e-5)
        return torch.sigmoid(self.net(feats).squeeze(1))


def take_window_len(take):
    """Window length in samples: longest trimmed positive, as in train.py."""
    paths = sorted(glob.glob(os.path.join(take, "positive*.wav")))
    if not paths:
        raise SystemExit(f"no positive-*.wav clips in {take}")
    durs = [len(train.trim_speech(train.load_clip(p))) / train.SR for p in paths]
    return int(max(durs) * train.SR)


def frames_for(window_len):
    """Frame count log_mel produces for a window (torch.stft with center=True)."""
    return 1 + window_len // train.HOP


def load_wakenet(run_dir):
    model = train.WakeNet()
    state = torch.load(os.path.join(run_dir, "wakenet.pt"), map_location="cpu")
    model.load_state_dict(state)
    model.eval()
    return model


def export(run_dir, window_len):
    """Trace and convert the model. Returns the path of the written .mlpackage."""
    wake = load_wakenet(run_dir)
    wrapper = ExportNet(wake).eval()
    frames = frames_for(window_len)
    example = torch.zeros(1, 1, train.N_MELS, frames)

    check = train.log_mel(torch.zeros(1, window_len))
    assert tuple(check.shape) == tuple(example.shape), (check.shape, example.shape)

    with torch.no_grad():
        traced = torch.jit.trace(wrapper, example)
    mlmodel = ct.convert(
        traced,
        inputs=[ct.TensorType(name=INPUT_NAME, shape=example.shape)],
        outputs=[ct.TensorType(name=OUTPUT_NAME)],
        convert_to="mlprogram",
        compute_precision=ct.precision.FLOAT32,
    )
    out_path = os.path.join(run_dir, "wakenet.mlpackage")
    mlmodel.save(out_path)

    meta = {
        "source": os.path.join(run_dir, "wakenet.pt"),
        "window_len": window_len,
        "window_s": window_len / train.SR,
        "sample_rate": train.SR,
        "hop_s": train.HOP_S,
        "frame_s": train.FRAME_S,
        "n_mels": train.N_MELS,
        "input": {"name": INPUT_NAME, "shape": list(example.shape)},
        "output": {"name": OUTPUT_NAME},
        "compute_precision": "float32",
        "coremltools": ct.__version__,
        "torch": torch.__version__,
    }
    with open(os.path.join(run_dir, "export.json"), "w") as f:
        json.dump(meta, f, indent=2)
    return out_path


def main():
    ap = argparse.ArgumentParser(description="Export a WakeNet run folder to Core ML (wakenet.mlpackage).")
    ap.add_argument("run_dir", help="run folder containing wakenet.pt and run.json")
    args = ap.parse_args()
    run_dir = os.path.abspath(args.run_dir)
    with open(os.path.join(run_dir, "run.json")) as f:
        take = json.load(f)["args"]["take"]
    window_len = take_window_len(take)
    out = export(run_dir, window_len)
    print(f"window length: {window_len} samples ({window_len / train.SR:.3f} s), frames {frames_for(window_len)}")
    print(f"saved: {out}")


if __name__ == "__main__":
    main()
