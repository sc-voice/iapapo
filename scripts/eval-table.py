#!/usr/bin/env python3
"""Print the held-out take scores recorded for one run as a plain table, under a title with its run id.

Usage: scripts/eval-table.py RUN [EVAL ...] [--list] [--threshold T]

RUN is a run folder, or a run id such as 0Q6-ou, found under lab/wakeword/out. Reads the eval-*.json
records that scripts/python/eval_take.py and the Swift eval_take wrote into that folder. For each take and
pipeline the newest record is used, so a Python and a Swift record of the same take both appear. EVAL ids
such as 0Q75u4Y select exact records, whatever their age, one per take and pipeline. --list prints every
record in the folder instead, oldest first, and marks the one the table uses for each take and pipeline.
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


def pipeline_of(rec):
    """Return the pipeline that wrote an eval record: "python" or "swift".

    Records written before the field existed were all written by eval_take.py, so a missing field means "python".

    Args:
        rec: a parsed eval-*.json record.

    Returns:
        The pipeline name.
    """
    return rec.get("pipeline", "python")


def take_of(rec):
    """Return the take folder name an eval record scored."""
    return os.path.basename(rec["take"])


def read_records(run_dir):
    """Return [(path, record)] for every eval-*.json in a run folder, oldest first by modification time.

    Args:
        run_dir: the run folder.

    Returns:
        A list of (path, parsed record) pairs.
    """
    paths = sorted(glob.glob(os.path.join(run_dir, "eval-*.json")), key=os.path.getmtime)
    out = []
    for path in paths:
        with open(path) as f:
            out.append((path, json.load(f)))
    return out


def newest_records(run_dir):
    """Return {(take name, pipeline): record} with the newest eval-*.json per take and pipeline.

    Args:
        run_dir: the run folder.

    Returns:
        A dict keyed by (take folder name, pipeline name).
    """
    newest = {}
    for _, rec in read_records(run_dir):  # later files overwrite earlier ones for the same take and pipeline
        newest[(take_of(rec), pipeline_of(rec))] = rec
    return newest


def print_list(run_dir):
    """Print every eval-*.json in a run folder, oldest first, marking the record the table uses for each take and pipeline.

    Args:
        run_dir: the run folder.
    """
    records = read_records(run_dir)
    newest = {}
    for path, rec in records:  # paths are sorted by time, so the last one per key is the newest
        newest[(take_of(rec), pipeline_of(rec))] = path
    print(f"{'eval':<9} {'take':<17} {'threshold':<9} {'positives':<9} {'false':<7} {'pipeline':<9} shown")
    for path, rec in records:
        s = rec["summary"]
        shown = "yes" if newest[(take_of(rec), pipeline_of(rec))] == path else ""
        pos = f"{s['positives_triggered']}/{s['positives']}"
        neg = f"{s['false_triggers']}/{s['negatives']}"
        print(f"{rec['run_id']:<9} {take_of(rec):<17} {rec['threshold']:<9} {pos:<9} {neg:<7} {pipeline_of(rec):<9} {shown}")


def main():
    ap = argparse.ArgumentParser(description="Held-out take scores for one run, as a plain table.")
    ap.add_argument("run", help="run folder, or a run id such as 0Q6-ou")
    ap.add_argument("evals", nargs="*", metavar="eval", help="eval ids such as 0Q75u4Y: show only those records")
    ap.add_argument("--list", action="store_true", help="list every eval record in the run instead of the table")
    ap.add_argument("--threshold", type=float, default=0.8,
                    help="wake threshold: a clip triggers at or above this score (default 0.8)")
    args = ap.parse_args()
    if args.list and args.evals:
        raise SystemExit("--list and eval ids cannot be used together")
    run_dir = os.path.abspath(args.run) if os.path.isdir(args.run) else find_run(DEFAULT_OUT, args.run)
    if args.list:
        print_list(run_dir)
        return
    if args.evals:
        records = {}
        for eval_id in args.evals:
            path = os.path.join(run_dir, f"eval-{eval_id}.json")
            if not os.path.isfile(path):
                raise SystemExit(f"no eval-{eval_id}.json in {run_dir}")
            with open(path) as f:
                rec = json.load(f)
            key = (take_of(rec), pipeline_of(rec))
            if key in records:
                raise SystemExit(f"evals {records[key]['run_id']} and {eval_id} both record take {key[0]} "
                                 f"with pipeline {key[1]}; give one")
            records[key] = rec
    else:
        records = newest_records(run_dir)
    if not records:
        raise SystemExit(f"no eval-*.json in {run_dir}")
    keys = sorted(records)
    ids = [records[key]["run_id"] for key in keys]
    print(f"./scripts/eval-table.py {' '.join([args.run] + ids)}")
    print()
    print(f"{'take':<17} {'clip':<14} {'python':<7} {'swift':<7} {'py-trig':<8} sw-trig")
    previous_take = None
    for take in sorted({key[0] for key in keys}):
        # One row per clip, with a column per pipeline: a clip is listed in the order of the first record that has it.
        clip_order = []
        by_pipeline = {}
        for key in keys:
            if key[0] != take:
                continue
            by_pipeline[key[1]] = {c["clip"]: c for c in records[key]["clips"]}
            for c in records[key]["clips"]:
                if c["clip"] not in clip_order:
                    clip_order.append(c["clip"])
        for name in clip_order:
            take_cell = f"{take:<17}"
            if take == previous_take and sys.stdout.isatty():
                take_cell = f"\033[2m{take_cell}\033[0m"  # dim: same take as the row above, dark gray in most themes
            previous_take = take
            cells = []
            trig = []
            for p in ("python", "swift"):
                c = by_pipeline.get(p, {}).get(name)
                if c is None:
                    cells.append(f"{'-':<7}")
                    trig.append(f"{'-':<8}")
                    continue
                text = f"{c['max_prob']:<7.4f}"
                if sys.stdout.isatty():
                    text = colored(c["label"], c["max_prob"], text, args.threshold)
                cells.append(text)
                trig.append(f"{('yes' if c['max_prob'] >= args.threshold else 'no'):<8}")
            print(f"{take_cell} {name:<14} {cells[0]} {cells[1]} {trig[0]} {trig[1]}")


if __name__ == "__main__":
    main()
