#!/bin/sh
# Trains the wake-word CNN (train.py) and writes wakenet.pt and scores.csv.
#
# Runs from any directory. Every argument is passed through to train.py.
# For the full trainer option list, run: .venv/bin/python scripts/train.py --help
#
# What it does on each run:
#   - creates lab/wakeword/{takes,extra,out} if they are missing
#   - on first run only, creates the virtualenv .venv at the repo root with python3.12 and
#     syncs it from pyproject.toml and uv.lock (uv sync --frozen)
#   - trains on media/iapapo (positives) and media/negative (negatives) plus optional
#     extra clips, then scores every clip, scoring the take clips as holdout
#   - writes each run to <out>/<version>/<take>-<run id>/ containing wakenet.pt,
#     scores.csv and run.json
#       version: first 9 chars of the nf hash of train.py (scripts/nfhash.py)
#       run id:  first 6 chars of a fresh nf id
#
# Usage:
#   scripts/train.sh [--take <name>] [--out <dir>] [--extra <dir>] [--no-extra]
#                    [--holdout <clip> ...] [--steps N]
#
#   --take     holdout take, a folder name under lab/wakeword/takes/ or a path containing
#              a slash (default: none, agent holdouts only); never trained on
#   --media    default media/ (positives from media/iapapo, negatives from media/negative)
#   --holdout  clips to exclude from training, reported as holdout in scores.csv
#   --out      output root, default lab/wakeword/out
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

HERE="$(cd "$(dirname "$0")" && pwd)"
WAKEWORD="$HERE/../lab/wakeword"
VENV="$HERE/../.venv"

mkdir -p "$WAKEWORD/takes" "$WAKEWORD/extra" "$WAKEWORD/out"

if [ ! -x "$VENV/bin/python" ]; then
    (cd "$HERE/.." && uv sync --frozen)
fi

# Version is the first 9 characters of the nf hash (SHA-256, nf alphabet) of train.py.
# Run ID is the first 6 characters of a fresh nf id.
TRAIN_VERSION="$("$VENV/bin/python" "$HERE/nfhash.py" "$HERE/python/train.py" | cut -c1-9)"
RUN_ID="$(nf id | cut -c1-6)"

exec "$VENV/bin/python" "$HERE/python/train.py" --version "$TRAIN_VERSION" --run-id "$RUN_ID" "$@"
