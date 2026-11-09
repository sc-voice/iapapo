#!/bin/sh
# Exports one wake-word run to Core ML: writes wakenet.mlpackage and export.json into the run folder.
# Then archives the minimal record needed to rebuild the export under models/wakeword/<version>/<run id>/:
#   - run.json: training provenance (seed, args, train.py hash, data hashes, environment)
#   - scores.csv: per-window scores of every clip, as train.py wrote them
#   - run.log: the training log, which train-summary reads for positive clip lengths
#   - train.json: the complete input record the engine ran on
#   - export.json: export settings and library versions
#   - export_coreml_nfhash: nf hash of scripts/python/export_coreml.py, the code that made the export
# wakenet.pt is not archived here. Archive it only for production candidates.
#
# Runs from any directory. Runs export_coreml.py with the project's venv, found relative to this script.
#
# Usage:
#   scripts/export.sh <run folder>
#
# Example:
#   scripts/export.sh lab/wakeword/out/<version>/<run>

HERE="$(cd "$(dirname "$0")" && pwd)"
VENV="$HERE/../.venv"
ROOT="$HERE/.."
RUN="$1"

DEST=$("$VENV/bin/python" -c '
import json, sys, os
run = sys.argv[1]
d = json.load(open(os.path.join(run, "run.json")))
print(os.path.join(sys.argv[2], "models", "wakeword", d["version"], d["train_args"]["run_id"]))
' "$RUN" "$ROOT") || exit $?

# An archive that records a commit is a record of a past export. Refuse before anything is written.
if [ -f "$DEST/export.json" ] && "$VENV/bin/python" -c '
import json, sys
commit = json.load(open(sys.argv[1])).get("git_commit")
sys.exit(0 if commit not in (None, "UNCOMMITTED") else 1)
' "$DEST/export.json"; then
    echo "refusing: $DEST already holds an export made from a commit; delete that folder to re-export" >&2
    exit 1
fi

"$VENV/bin/python" "$HERE/python/export_coreml.py" "$@" || exit $?

mkdir -p "$DEST"
cp "$RUN/run.json" "$DEST/run.json" || exit $?
cp "$RUN/scores.csv" "$DEST/scores.csv" || exit $?
cp "$RUN/run.log" "$DEST/run.log" || exit $?
cp "$RUN/train.json" "$DEST/train.json" || exit $?
NFHASH=$("$VENV/bin/python" "$HERE/nfhash.py" "$HERE/python/export_coreml.py") || exit $?
# The commit the export code came from, or UNCOMMITTED if scripts/ has changes not in HEAD.
GIT_COMMIT=$(cd "$ROOT" && git status --porcelain -- scripts | grep -q . && echo UNCOMMITTED || git rev-parse HEAD 2>/dev/null || echo UNCOMMITTED)
"$VENV/bin/python" -c '
import json, sys
src, dst, nfhash, commit = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
d = json.load(open(src))
d["export_coreml_nfhash"] = nfhash
d["git_commit"] = commit
json.dump(d, open(dst, "w"), indent=2)
' "$RUN/export.json" "$DEST/export.json" "$NFHASH" "$GIT_COMMIT" || exit $?
echo "archived: $DEST"
