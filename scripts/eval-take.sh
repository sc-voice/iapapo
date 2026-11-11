#!/bin/bash
# Scores one held-out take with the Python and/or Swift pipeline and writes eval-<id>.json records into the run folder.
#
# Usage: scripts/eval-take.sh RUN TAKE [--pipeline python|swift|both] [--threshold T]
#   RUN   a run folder, or a run id such as 0Q6-ou found under lab/wakeword/out
#   TAKE  a take folder, or a take name such as 20261104-075505 found under lab/wakeword/takes
# --pipeline defaults to both. The Python pipeline needs .venv; the Swift one needs the release build of
# eval_take (swift build -c release --package-path VACore --product eval_take). Stops at the first failure.
# Prints the eval ids it wrote and the eval-table.py command that shows them.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PIPELINE=both
THRESHOLD=""
RUN=""
TAKE=""

fail() {
    echo "eval-take: $*" >&2
    exit 1
}

while [ $# -gt 0 ]; do
    case "$1" in
        --pipeline) [ $# -ge 2 ] || fail "--pipeline needs a value"; PIPELINE="$2"; shift 2 ;;
        --threshold) [ $# -ge 2 ] || fail "--threshold needs a value"; THRESHOLD="$2"; shift 2 ;;
        -*) fail "unknown option $1" ;;
        *)
            if [ -z "$RUN" ]; then RUN="$1"
            elif [ -z "$TAKE" ]; then TAKE="$1"
            else fail "too many arguments"
            fi
            shift ;;
    esac
done

[ -n "$RUN" ] && [ -n "$TAKE" ] || fail "usage: scripts/eval-take.sh RUN TAKE [--pipeline python|swift|both] [--threshold T]"
case "$PIPELINE" in
    python|swift|both) ;;
    *) fail "--pipeline must be python, swift or both" ;;
esac

# Run folder: a path, or a run id found under lab/wakeword/out.
if [ -d "$RUN" ]; then
    RUN_DIR="$(cd "$RUN" && pwd)"
else
    matches="$(ls -d "$ROOT"/lab/wakeword/out/*/*-"$RUN" 2>/dev/null || true)"
    count="$(printf '%s\n' "$matches" | grep -c . || true)"
    [ "$count" -eq 1 ] || fail "$count run folders under lab/wakeword/out match run id $RUN"
    RUN_DIR="$matches"
fi

# Take folder: a path, or a take name found under lab/wakeword/takes.
if [ -d "$TAKE" ]; then
    TAKE_DIR="$(cd "$TAKE" && pwd)"
elif [ -d "$ROOT/lab/wakeword/takes/$TAKE" ]; then
    TAKE_DIR="$ROOT/lab/wakeword/takes/$TAKE"
else
    fail "no take folder $TAKE"
fi

EXTRA=""
if [ -n "$THRESHOLD" ]; then EXTRA="--threshold $THRESHOLD"; fi

IDS=""
run_pipeline() {
    local name="$1"
    shift
    echo "== $name"
    local out
    out="$("$@" $EXTRA)"
    echo "$out"
    IDS="$IDS $(echo "$out" | sed -n 's/^saved: .*eval-\(.*\)\.json$/\1/p')"
}

if [ "$PIPELINE" = python ] || [ "$PIPELINE" = both ]; then
    PY="$ROOT/.venv/bin/python"
    [ -x "$PY" ] || fail "no Python environment at $ROOT/.venv"
    run_pipeline python "$PY" "$ROOT/scripts/python/eval_take.py" "$RUN_DIR" "$TAKE_DIR"
fi
if [ "$PIPELINE" = swift ] || [ "$PIPELINE" = both ]; then
    SWIFT="$ROOT/VACore/.build/release/eval_take"
    [ -x "$SWIFT" ] || fail "no release build at $SWIFT: run swift build -c release --package-path VACore --product eval_take"
    run_pipeline swift "$SWIFT" "$RUN_DIR" "$TAKE_DIR"
fi

echo
echo "wrote:$IDS"
echo "table: scripts/eval-table.py $RUN_DIR$IDS"
