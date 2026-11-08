#!/usr/bin/env python3
"""Print a per-voice table of negative max scores for a train.py run, holdouts (_1-_3) included.

The _s1-_s3 columns are sentence negatives used for training, so a high score there is a fit failure, not
generalization; the holdouts are _1-_3.

Usage: scripts/train-summary.py [RUN_DIR]

RUN_DIR is a run folder holding scores.csv. Omit it to use the run whose scores.csv is newest under lab/wakeword/out.
Each cell is the highest probability over all sliding windows of that clip. Scores below 0.1 print as --, and
columns where every score is below 0.1 are dropped.
"""

import argparse
import ast
import collections
import csv
import glob
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_OUT = os.path.join(HERE, "..", "lab", "wakeword", "out")
SUFFIXES = ["1", "2", "3", "4", "4q", "5", "5q", "6", "6q", "7", "7q", "s1", "s2", "s3"]
CLIP = re.compile(r"^negative-(.+)_(s?[1-7]q?)$")
POSITIVE = re.compile(r"^positive-(.+?)_(_|[a-z])$")
MIN_SHOWN = 0.1
POSITIVE_THRESHOLD = 0.5  # the train.py --threshold default: a clip counts as triggered at or above this
COL_WIDTH = 7


def latest_run(root):
    """Return the run folder holding the newest scores.csv under root."""
    found = glob.glob(os.path.join(root, "*", "*", "scores.csv"))
    if not found:
        raise SystemExit(f"no scores.csv under {root}")
    return os.path.dirname(max(found, key=os.path.getmtime))


def max_scores(run_dir):
    """Return {clip: highest probability over all windows} read from run_dir/scores.csv."""
    best = collections.defaultdict(float)
    with open(os.path.join(run_dir, "scores.csv"), newline="") as f:
        for row in csv.DictReader(f):
            best[row["clip"]] = max(best[row["clip"]], float(row["prob"]))
    return best


def positive_lengths(run_dir):
    """Return {voice: trimmed length in seconds of its first positive}, read from the run's run.log."""
    prefix = "trimmed positives (s): "
    with open(os.path.join(run_dir, "run.log")) as f:
        for line in f:
            if line.startswith(prefix):
                trimmed = ast.literal_eval(line[len(prefix):])
                break
        else:
            return {}
    first = {}
    for name in sorted(trimmed):
        m = POSITIVE.match(name)
        if m and m.group(1) not in first:
            first[m.group(1)] = trimmed[name]
    return first


def hard_neg_table(scores):
    """Return (sorted voice names, {voice: {suffix: score}}) for the negative clips, holdouts (_1-_3) included."""
    table = collections.defaultdict(dict)
    for clip, p in scores.items():
        m = CLIP.match(clip)
        if m:
            table[m.group(1)][m.group(2)] = p
    return sorted(table), table


def render(voices, table, lengths):
    """Print the table: one row per voice, its first positive's length, then one column per suffix with a score >= MIN_SHOWN."""
    cols = [s for s in SUFFIXES if any(table[v].get(s, 0.0) >= MIN_SHOWN for v in voices)]
    if not cols:
        print("no negative scores at or above 0.1")
        return
    width = max(len(v) for v in voices)
    print("voice".ljust(width) + f"{'Tclip':>{COL_WIDTH}s}" + "".join(f"{'_' + s:>{COL_WIDTH}s}" for s in cols))
    for v in voices:
        length = f"{lengths[v]:{COL_WIDTH}.2f}" if v in lengths else f"{'--':>{COL_WIDTH}s}"
        cells = []
        for s in cols:
            p = table[v].get(s, 0.0)
            if p < MIN_SHOWN:
                cells.append(f"{'--':>{COL_WIDTH}s}")
            elif p >= POSITIVE_THRESHOLD and sys.stdout.isatty():
                cells.append(f"\033[31m{p:{COL_WIDTH}.2f}\033[0m")  # red: at or above the trigger threshold
            else:
                cells.append(f"{p:{COL_WIDTH}.2f}")
        print(v.ljust(width) + length + "".join(cells))


def positive_table(scores):
    """Return (sorted voice names, {voice: {suffix: score}}) for the positive clips, one score per clip."""
    table = collections.defaultdict(dict)
    for clip, p in scores.items():
        m = POSITIVE.match(clip)
        if m:
            table[m.group(1)][m.group(2)] = p
    return sorted(table), table


def render_positives(voices, table):
    """Print the positive table: one row per voice, one column per positive suffix. A voice with no clip of that
    suffix prints ∅. Scores below POSITIVE_THRESHOLD print in red on a terminal."""
    cols = sorted({s for v in voices for s in table[v]})
    if not cols:
        print("no positive clips")
        return
    width = max(len(v) for v in voices)
    print("voice".ljust(width) + "".join(f"{'_' + s:>{COL_WIDTH}s}" for s in cols))
    for v in voices:
        cells = []
        for s in cols:
            if s not in table[v]:
                cells.append(f"{'∅':>{COL_WIDTH}s}")
                continue
            text = f"{table[v][s]:>{COL_WIDTH}.2f}"
            if table[v][s] < POSITIVE_THRESHOLD and sys.stdout.isatty():
                text = f"\033[31m{text}\033[0m"  # red: below the trigger threshold
            cells.append(text)
        print(v.ljust(width) + "".join(cells))


def main():
    ap = argparse.ArgumentParser(description="Per-voice hard-negative score table for one train.py run.")
    ap.add_argument("run_dir", nargs="?", default=None,
                    help="run folder containing scores.csv (default: newest run under lab/wakeword/out)")
    args = ap.parse_args()
    run_dir = os.path.abspath(args.run_dir) if args.run_dir else latest_run(DEFAULT_OUT)
    print(f"run: {os.path.relpath(run_dir, os.path.join(HERE, '..'))}")
    lengths = positive_lengths(run_dir)
    scores = max_scores(run_dir)
    voices, table = hard_neg_table(scores)
    # longest first positive first; voices without a positive go last; ties stay alphabetical
    voices.sort(key=lambda v: (v not in lengths, -lengths.get(v, 0.0)))
    render(voices, table, lengths)
    print()
    print("positives (highest window score per clip)")
    pos_voices, pos_table = positive_table(scores)
    render_positives(pos_voices, pos_table)


if __name__ == "__main__":
    main()
