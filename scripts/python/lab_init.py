#!/usr/bin/env python3
"""Prepare lab/ so an archived run can be rebuilt with train.py.

Usage: scripts/lab_init.sh <run id>

Finds the one archive record models/wakeword/<version>/<run id>/run.json and checks that every
training input under media/ still has the hash recorded in it. It then fills lab/wakeword/noise/
with the noise clips that run used, copied from media/noise/, and checks each copy's hash.
It first creates the empty lab/ folders that the tests read, if they are missing.

Nothing is copied unless every check passes. The script stops with a message if a file is missing,
a hash differs, or lab/wakeword/noise/ holds a WAV that the run did not use, since train.py would
then add noise the run never had.
"""

import glob
import json
import os
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(HERE, ".."))
from nfhash import nf_hash_file  # noqa: E402


def find_record(run_id):
    """Return the path of the single archived run.json for run_id.

    Args:
        run_id: run ID, the run folder name without its prefix, such as 0Q6x7T.

    Returns:
        The path to models/wakeword/<version>/<run id>/run.json.
    """
    matches = glob.glob(os.path.join(ROOT, "models", "wakeword", "*", run_id, "run.json"))
    if len(matches) != 1:
        sys.exit(f"lab_init: expected one archive record for {run_id}, found {len(matches)}")
    return matches[0]


def check(record):
    """Check inputs and noise against the record.

    Args:
        record: parsed run.json.

    Returns:
        A list of problem strings. Empty when everything matches.
    """
    problems = []
    for group, files in record["inputs_nfhash"].items():
        for rel, expected in files.items():
            path = os.path.join(ROOT, rel)
            if not os.path.isfile(path):
                problems.append(f"missing input {rel}")
            elif nf_hash_file(path) != expected:
                problems.append(f"hash differs for input {rel}")
    for name, expected in record["noise_nfhash"].items():
        path = os.path.join(ROOT, "media", "noise", name)
        if not os.path.isfile(path):
            problems.append(f"missing noise media/noise/{name}")
        elif nf_hash_file(path) != expected:
            problems.append(f"hash differs for noise {name}")
    lab_noise = os.path.join(ROOT, "lab", "wakeword", "noise")
    if os.path.isdir(lab_noise):
        for name in sorted(os.listdir(lab_noise)):
            if name.lower().endswith(".wav") and name not in record["noise_nfhash"]:
                problems.append(f"lab/wakeword/noise has {name}, which the run did not use")
    return problems


LAB_FOLDERS = [
    ("lab", "wakeword", "noise"),
    ("lab", "wakeword", "takes"),
    ("lab", "wakeword", "reference", "frontend"),
    ("lab", "wakeword", "reference", "resample"),
    ("lab", "wakeword", "monitor"),
]


def ensure_folders():
    """Create the lab folders the tests and scripts read, if they are missing.

    Empty folders are not copies, so this runs before the checks.
    """
    for parts in LAB_FOLDERS:
        os.makedirs(os.path.join(ROOT, *parts), exist_ok=True)


def fill_noise(record):
    """Copy the run's noise clips from media/noise/ into lab/wakeword/noise/ and verify each copy.

    Args:
        record: parsed run.json.
    """
    dest_dir = os.path.join(ROOT, "lab", "wakeword", "noise")
    for name, expected in record["noise_nfhash"].items():
        dest = os.path.join(dest_dir, name)
        shutil.copyfile(os.path.join(ROOT, "media", "noise", name), dest)
        if nf_hash_file(dest) != expected:
            sys.exit(f"lab_init: copy of {name} does not match its hash")
        print(f"noise: {name}")


def main(argv):
    """Run the checks, then fill the noise folder if they pass.

    Args:
        argv: command-line arguments, excluding the program name.
    """
    ensure_folders()
    if len(argv) != 1:
        sys.exit("usage: scripts/lab_init.sh <run id>")
    path = find_record(argv[0])
    record = json.load(open(path))
    problems = check(record)
    if problems:
        print("lab_init: stopped, nothing copied:")
        for p in problems:
            print(f"  {p}")
        sys.exit(1)
    fill_noise(record)
    print(f"lab_init: ready to rebuild {argv[0]} from {os.path.relpath(path, ROOT)}")


if __name__ == "__main__":
    main(sys.argv[1:])
