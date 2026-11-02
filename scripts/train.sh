#!/bin/sh
# Trains the wake-word CNN (train.py) and writes wakenet.pt and scores.csv.
#
# Runs from any directory. Every argument is passed through to train.py.
# For the full trainer option list, run: lab/wakeword/.venv/bin/python scripts/train.py --help
#
# What it does on each run:
#   - creates lab/wakeword/{takes,extra,out} if they are missing
#   - on first run only, creates the virtualenv lab/wakeword/.venv and installs
#     numpy, scipy, soundfile and torch into it
#   - trains on one take folder plus optional extra clips, then scores every clip
#
# Usage:
#   scripts/train.sh --take <name> [--out <dir>] [--extra <dir>] [--no-extra]
#                    [--holdout <clip> ...] [--steps N]
#
#   --take     a folder name under lab/wakeword/takes/, or a path containing a slash
#   --holdout  clips to exclude from training, reported as holdout in scores.csv
#   --out      default lab/wakeword/out
#   --extra    default lab/wakeword/extra
#
# Example:
#   scripts/train.sh --take 20261101-183517 --holdout positive-003
set -e

# Print the header comment block, then stop before any setup runs.
print_help() {
    awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"
}

case "${1:-}" in
    -h|--help)
        print_help
        exit 0
        ;;
esac

if [ $# -eq 0 ]; then
    print_help >&2
    exit 2
fi

HERE="$(cd "$(dirname "$0")" && pwd)"
WAKEWORD="$HERE/../lab/wakeword"
VENV="$WAKEWORD/.venv"

mkdir -p "$WAKEWORD/takes" "$WAKEWORD/extra" "$WAKEWORD/out"

if [ ! -x "$VENV/bin/python" ]; then
    python3 -m venv "$VENV"
    "$VENV/bin/pip" install numpy scipy soundfile torch
fi

exec "$VENV/bin/python" "$HERE/train.py" "$@"
