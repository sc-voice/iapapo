"""Check that the Swift eval of a run matches its Python eval on each take.

For every take, reads the newest Python and Swift eval records that the run folder holds for it
(written by scripts/eval-take.sh --pipeline both), compares each clip's max_prob, and prints the
trigger counts at 0.5 and 0.8. Exits 1 if a take has no record from either pipeline, the clip lists
differ, or any clip's max_prob differs by more than --tol.

Usage:
    .venv/bin/python scripts/python/verify_export.py <run folder> <take folder>... [--tol 1e-3]
"""

import argparse
import glob
import json
import os
import sys

THRESHOLDS = (0.5, 0.8)


def newest_record(run_dir, take_name, pipeline):
    """Return the newest eval record for a take and pipeline, or None."""
    best = None
    for path in glob.glob(os.path.join(run_dir, "eval-*.json")):
        with open(path) as f:
            rec = json.load(f)
        if rec.get("pipeline") != pipeline or os.path.basename(rec.get("take", "")) != take_name:
            continue
        if best is None or os.path.getmtime(path) > os.path.getmtime(best[0]):
            best = (path, rec)
    return best[1] if best else None


def triggers(prob, threshold):
    return prob >= threshold


def verify_take(run_dir, take_dir, tol):
    """Return a list of failure messages for one take; empty means it passed."""
    take_name = os.path.basename(os.path.normpath(take_dir))
    py = newest_record(run_dir, take_name, "python")
    sw = newest_record(run_dir, take_name, "swift")
    if py is None or sw is None:
        return [f"{take_name}: missing {'python' if py is None else 'swift'} eval record in {run_dir}"]

    py_clips = {c["clip"]: c for c in py["clips"]}
    sw_clips = {c["clip"]: c for c in sw["clips"]}
    if set(py_clips) != set(sw_clips):
        return [f"{take_name}: clip lists differ: {sorted(set(py_clips) ^ set(sw_clips))}"]

    failures = []
    print(f"take {take_name}")
    print(f"  {'clip':<14} {'label':<9} {'python':>8} {'swift':>8} {'diff':>10}  "
          + "  ".join(f"py/sw@{t}" for t in THRESHOLDS))
    for name in sorted(py_clips):
        p, s = py_clips[name], sw_clips[name]
        diff = abs(p["max_prob"] - s["max_prob"])
        flags = "  ".join(
            f"{'yes' if triggers(p['max_prob'], t) else 'no '}/{'yes' if triggers(s['max_prob'], t) else 'no '}"
            .ljust(len(f"py/sw@{t}"))
            for t in THRESHOLDS)
        print(f"  {name:<14} {p['label']:<9} {p['max_prob']:>8.4f} {s['max_prob']:>8.4f} {diff:>10.2e}  {flags}")
        if diff > tol:
            failures.append(f"{take_name}/{name}: |python - swift| = {diff:.2e} > {tol}")
    for t in THRESHOLDS:
        pos = [c for c in py_clips.values() if c["label"] == "positive"]
        neg = [c for c in py_clips.values() if c["label"] == "negative"]
        hit = sum(triggers(c["max_prob"], t) for c in pos)
        false = sum(triggers(c["max_prob"], t) for c in neg)
        print(f"  at {t}: positives {hit}/{len(pos)}, negatives triggered {false}/{len(neg)}")
    print()
    return failures


def main():
    ap = argparse.ArgumentParser(description="Compare the Swift and Python eval of a run on each take.")
    ap.add_argument("run_dir", help="run folder holding the eval-*.json records")
    ap.add_argument("takes", nargs="+", help="take folders that were evaluated")
    ap.add_argument("--tol", type=float, default=1e-3, help="max allowed max_prob difference (default 1e-3)")
    args = ap.parse_args()

    run_dir = os.path.abspath(args.run_dir)
    failures = []
    for take in args.takes:
        failures += verify_take(run_dir, take, args.tol)

    if failures:
        print("FAIL")
        for msg in failures:
            print(f"  {msg}")
        sys.exit(1)
    print("PASS: Swift and Python eval agree on every take")


if __name__ == "__main__":
    main()
