#!/usr/bin/env python3
"""Print the held-out take scores recorded for one run as a plain table, under a title with its run id.

Usage: scripts/eval-table.py RUN

RUN is a run folder, or a run id such as 0Q6-ou, found under lab/wakeword/out. Reads the eval-*.json
records that scripts/python/evaluate.py wrote into that folder. If a take has more than one record,
the newest one is used.
"""

import argparse
import glob
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_OUT = os.path.join(HERE, "..", "lab", "wakeword", "out")


def find_run(root, run_id):
    """Return the run folder under root whose name ends with -<run_id> and that holds an eval record.

    Args:
        root: the output root, lab/wakeword/out.
        run_id: a run id such as 0Q6-ou.

    Returns:
        The run folder path.

    Raises:
        SystemExit: if zero or several run folders match.
    """
    matches = [d for d in glob.glob(os.path.join(root, "*", "*"))
               if os.path.basename(d).endswith("-" + run_id) and glob.glob(os.path.join(d, "eval-*.json"))]
    if len(matches) != 1:
        raise SystemExit(f"{len(matches)} runs under {root} with eval records match run id {run_id!r}: {sorted(matches)}")
    return matches[0]


MARGIN = 0.05  # a right answer this close to the threshold is yellow: it could flip with small changes


def colored(label, p, text, threshold):
    """Color a score for a terminal: red when the answer is wrong, yellow when it is right but within MARGIN
    of the threshold, green otherwise.

    Positives are right at or above the threshold (a miss is red). Negatives are right below it (a false trigger is red).

    Args:
        label: "positive" or "negative".
        p: the clip's max probability.
        text: the padded score text to color.
        threshold: the wake threshold.

    Returns:
        The text wrapped in ANSI color codes.
    """
    right = (p >= threshold) if label == "positive" else (p < threshold)
    if not right:
        code = "31"
    elif abs(p - threshold) < MARGIN:
        code = "33"
    else:
        code = "32"
    return f"\033[{code}m{text}\033[0m"


def newest_records(run_dir):
    """Return {take name: record} with the newest eval-*.json per take.

    Args:
        run_dir: the run folder.

    Returns:
        A dict from take folder name to the parsed record.
    """
    newest = {}
    for path in sorted(glob.glob(os.path.join(run_dir, "eval-*.json")), key=os.path.getmtime):
        with open(path) as f:
            rec = json.load(f)
        newest[os.path.basename(rec["take"])] = rec  # later files overwrite earlier ones for the same take
    return newest


def main():
    ap = argparse.ArgumentParser(description="Held-out take scores for one run, as a plain table.")
    ap.add_argument("run", help="run folder, or a run id such as 0Q6-ou")
    ap.add_argument("--threshold", type=float, default=0.8,
                    help="wake threshold: a clip triggers at or above this score (default 0.8)")
    args = ap.parse_args()
    run_dir = os.path.abspath(args.run) if os.path.isdir(args.run) else find_run(DEFAULT_OUT, args.run)
    records = newest_records(run_dir)
    if not records:
        raise SystemExit(f"no eval-*.json in {run_dir}")
    print(f"./scripts/eval-table.py {args.run}")
    print()
    print(f"{'take':<17} {'clip':<14} {'label':<5} {'score':<7} triggered")
    for take in sorted(records):
        for n, c in enumerate(records[take]["clips"]):
            take_cell = f"{take:<17}"
            if n > 0 and sys.stdout.isatty():
                take_cell = f"\033[2m{take_cell}\033[0m"  # dim: same take as the row above, dark gray in most themes
            label = c["label"][:3]
            score = f"{c['max_prob']:<7.4f}"
            if sys.stdout.isatty():
                score = colored(c["label"], c["max_prob"], score, args.threshold)
            triggered = c["max_prob"] >= args.threshold
            print(f"{take_cell} {c['clip']:<14} {label:<5} {score} {'yes' if triggered else 'no'}")


if __name__ == "__main__":
    main()
