"""Export one trained WakeNet run to a Core ML ML Program.

The exported model takes log-mel features, shape (1, 1, N_MELS, frames), not audio.
The front end (log_mel in train.py) stays in Python; the Swift front end is a later step.
Per-clip feature normalization is inside the model, so it matches training.
Output "prob" is the wake-word probability for one window.

Run it with the export venv, which has coremltools:
    .venv/bin/python scripts/export_coreml.py <run folder>

Reads <run folder>/wakenet.pt and run.json. Writes <run folder>/wakenet.mlpackage
and <run folder>/export.json. The window length is the window_len that train.py recorded in run.json.
"""

import argparse
import json
import os
import sys

import coremltools as ct
import torch
import torch.nn as nn

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "..")
sys.path.insert(0, HERE)
import train  # noqa: E402

INPUT_NAME = "logmel"
OUTPUT_NAME = "prob"


class ExportNet(nn.Module):
    """Wraps WakeNet.score_features with the sigmoid, so the exported output is a probability. No logic of its own."""

    def __init__(self, wakenet):
        super().__init__()
        self.wakenet = wakenet

    def forward(self, feats):
        return torch.sigmoid(self.wakenet.score_features(feats))


def window_len_from_run(run_dir):
    """Window length in samples, as train.py recorded it in run.json."""
    with open(os.path.join(run_dir, "run.json")) as f:
        meta = json.load(f)
    if "window_len" not in meta:
        raise SystemExit("run.json has no window_len; this run predates the current train.py. Retrain it.")
    return meta["window_len"]


def run_identity(run_dir):
    """run_id (which training run, and its data) and train_py_nfhash (hash of train.py), as recorded in run.json."""
    with open(os.path.join(run_dir, "run.json")) as f:
        meta = json.load(f)
    return {"run_id": meta["train_args"]["run_id"], "train_py_nfhash": meta["train_py_nfhash"]}


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
    for key, value in run_identity(run_dir).items():
        mlmodel.user_defined_metadata[key] = value
    out_path = os.path.join(run_dir, "wakenet.mlpackage")
    mlmodel.save(out_path)

    meta = {
        "source": os.path.relpath(os.path.join(run_dir, "wakenet.pt"), ROOT),
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
    window_len = window_len_from_run(run_dir)
    out = export(run_dir, window_len)
    print(f"window length: {window_len} samples ({window_len / train.SR:.3f} s), frames {frames_for(window_len)}")
    print(f"saved: {out}")


if __name__ == "__main__":
    main()
