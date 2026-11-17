#!/bin/sh
# Archives one verified wake-word run under models/wakeword/<version>/<run id>/:
#   - wakenet.mlpackage: the Core ML model that verification checked
#   - run.json, scores.csv, run.log, train.json: training record
#   - export.json: export settings, plus export_coreml_nfhash and git_commit
# wakenet.pt is not archived. Copy it by hand only for production candidates.
#
# Refuses to overwrite an archive that records a commit. Run only after make wake-export passes.
#
# Usage:
#   scripts/archive-export.sh <run folder>

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
    echo "refusing: $DEST already holds an export made from a commit; delete that folder to re-archive" >&2
    exit 1
fi

mkdir -p "$DEST/wakenet.mlpackage"
cp -R "$RUN/wakenet.mlpackage/." "$DEST/wakenet.mlpackage/" || exit $?
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
