#!/bin/sh
# Trains the wake-word CNN. One run writes one folder holding train.json (the complete input
# record), wakenet.pt, scores.csv, run.json and run.log.
#
# Runs from any directory. The options are parsed by scripts/python/train_cli.py, which prints the
# input record with every default included. To see that record without training, run:
#   .venv/bin/python scripts/python/train_cli.py [options]
#
# What it does on each run:
#   - creates lab/wakeword/{takes,extra,out} if they are missing
#   - on first run only, creates the virtualenv .venv at the repo root with python3.12 and
#     syncs it from pyproject.toml and uv.lock (uv sync --frozen)
#   - writes the run to <out>/<version>/<take>-<run id>/
#       version: first 9 chars of the nf hash of train.py (scripts/nfhash.py)
#       run id:  first 6 chars of a fresh nf id
#   - stops without creating a folder if the options are invalid
#
# Usage:
#   scripts/train.sh [--take <name>] [--out <dir>] [--extra <dir>] [--no-extra]
#                    [--holdout <clip> ...] [--steps N] [--seed N] [--noise <dir>]
#
#   --take     holdout take, a folder name under lab/wakeword/takes/ or a path containing
#              a slash (default: none, agent holdouts only); never trained on
#   --media    default media/ (positives from media/iapapo, negatives from media/negative)
#   --holdout  clips to exclude from training, reported as holdout in scores.csv
#   --noise    folder of background-noise WAVs, required non-empty (default lab/wakeword/noise)
#   --out      output root, default lab/wakeword/out (handled here, not by train_cli.py)
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

# Pull --out out of the arguments; everything else goes to train_cli.py unchanged.
# Each pass moves the first argument to the end, so values containing spaces stay whole.
OUT="$WAKEWORD/out"
n=$#
while [ "$n" -gt 0 ]; do
    arg="$1"
    shift
    n=$((n - 1))
    if [ "$arg" = "--out" ]; then
        OUT="$1"
        shift
        n=$((n - 1))
    else
        set -- "$@" "$arg"
    fi
done
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"

# The complete input record. Bad options stop here, before any folder is created.
RECORD="$("$VENV/bin/python" "$HERE/python/train_cli.py" "$@")"
RUN_NAME="$(printf '%s' "$RECORD" | "$VENV/bin/python" -c 'import json, os, sys; take = json.load(sys.stdin)["take"]; print(os.path.basename(take) if take else "no-take")')"

# Version is the first 9 characters of the nf hash (SHA-256, nf alphabet) of train.py.
# Run ID is the first 6 characters of a fresh nf id.
TRAIN_VERSION="$("$VENV/bin/python" "$HERE/nfhash.py" "$HERE/python/train.py" | cut -c1-9)"
RUN_ID="$(nf id | cut -c1-6)"

RUN="$OUT/$TRAIN_VERSION/$RUN_NAME-$RUN_ID"
mkdir -p "$OUT/$TRAIN_VERSION"
mkdir "$RUN"
printf '%s\n' "$RECORD" > "$RUN/train.json"

exec "$VENV/bin/python" "$HERE/python/train.py" "$RUN/train.json" --run-id "$RUN_ID"
