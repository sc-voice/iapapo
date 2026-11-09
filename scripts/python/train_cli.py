#!/usr/bin/env python3
"""Print the train.json input record for one wake-word training run.

This is the only place training defaults live. The output is the complete input to
scripts/python/train.py: every option, defaults included, with sorted keys and a schema field.
Paths are resolved against the current directory, then written relative to the repo root, so the
same arguments give the same bytes from anywhere. Nothing is written, checked on disk, or launched.

Usage: scripts/python/train_cli.py [options] > train.json
"""

import argparse
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
SCHEMA = 1
TAKES = os.path.join(ROOT, "lab", "wakeword", "takes")
DEFAULT_PATHS = {"media": "media", "extra": "lab/wakeword/extra", "noise": "lab/wakeword/noise"}


def repo_path(text):
    """Resolve a path against the current directory and return it relative to the repo root.

    Args:
        text: a path as typed on the command line.

    Returns:
        The repo-relative path.
    """
    return os.path.relpath(os.path.abspath(text), ROOT)


def take_path(text):
    """Resolve --take: a bare name is a folder under lab/wakeword/takes/, anything else is a path.

    Args:
        text: the --take value as typed.

    Returns:
        The repo-relative take folder.
    """
    return repo_path(os.path.join(TAKES, text) if os.path.basename(text) == text else text)


def seed_value(text):
    """Parse --seed as an integer in the range numpy accepts.

    Args:
        text: the --seed value as typed.

    Returns:
        The seed as an int.

    Raises:
        argparse.ArgumentTypeError: if the value is not an integer in 0 to 4294967295.
    """
    try:
        value = int(text)
    except ValueError:
        raise argparse.ArgumentTypeError(f"invalid integer: {text!r}")
    if not 0 <= value <= 4294967295:
        raise argparse.ArgumentTypeError(f"must be 0 to 4294967295, got {value}")
    return value


def build_parser():
    """Return the parser for every training input. Path options default to None and are filled from DEFAULT_PATHS.

    Returns:
        An argparse.ArgumentParser.
    """
    ap = argparse.ArgumentParser(description="Print the train.json input record for one wake-word training run.")
    ap.add_argument("--media", type=repo_path, default=None,
                    help="folder with <wakeword>/ (positives) and negative/ (negatives) m4a clips (default: media)")
    ap.add_argument("--wakeword", default="iapapo",
                    help="wake word the model detects (default: iapapo)")
    ap.add_argument("--take", type=take_path, default=None,
                    help="iPad take folder, scored as holdout and never trained on; a bare name is looked up in lab/wakeword/takes/ (default: none)")
    ap.add_argument("--holdout", nargs="*", default=[],
                    help="clip names to exclude from training and report as holdout (default: none)")
    ap.add_argument("--steps", type=int, default=6000,
                    help="training steps, one random batch each (default 6000)")
    ap.add_argument("--batch", type=int, default=32,
                    help="samples per step (default 32)")
    ap.add_argument("--lr", type=float, default=1e-3,
                    help="Adam starting learning rate, cosine-decayed to zero over --steps (default 1e-3)")
    ap.add_argument("--threshold", type=float, default=0.5,
                    help="probability at which a clip counts as triggered (default 0.5)")
    ap.add_argument("--seed", type=seed_value, default=0,
                    help="random seed, 0 to 4294967295 (default 0)")
    ap.add_argument("--noise", type=repo_path, default=None,
                    help="folder of background-noise WAVs, required non-empty by train.py (default: lab/wakeword/noise)")
    ap.add_argument("--noise-snr", type=float, nargs=2, metavar=("MIN", "MAX"), default=[3.0, 30.0],
                    help="SNR range in dB for background noise (default 3 30)")
    ap.add_argument("--window-scale", type=float, default=1.0,
                    help="training and scoring window as a multiple of the longest trimmed positive (default 1.0)")
    ap.add_argument("--extra", type=repo_path, default=None,
                    help="extra clips added to training (default: lab/wakeword/extra)")
    ap.add_argument("--no-extra", action="store_true",
                    help="do not use the extra clips")
    return ap


def build(argv):
    """Parse argv and return the complete train.json record as a dict.

    Args:
        argv: command-line arguments, excluding the program name.

    Returns:
        A dict of every input, with paths repo-relative and a schema field.
    """
    values = vars(build_parser().parse_args(argv))
    for key, default in DEFAULT_PATHS.items():
        if values[key] is None:
            values[key] = default
    return {"schema": SCHEMA, **values}


def main(argv):
    """Print the train.json record for argv to stdout.

    Args:
        argv: command-line arguments, excluding the program name.
    """
    sys.stdout.write(json.dumps(build(argv), sort_keys=True, indent=2) + "\n")


if __name__ == "__main__":
    main(sys.argv[1:])
