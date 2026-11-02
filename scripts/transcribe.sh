#!/bin/sh
# Transcribes one audio file on the device, using the same speech engine as the app.
#
# Builds the transcribe tool in VACore if needed, then runs it. Runs from any directory.
#
# Usage:
#   scripts/transcribe.sh <audio file>
#
# Prints each speech log line, then the transcript and the elapsed time.
set -e

HERE="$(cd "$(dirname "$0")" && pwd)"
PACKAGE="$HERE/../VACore"

if [ $# -eq 0 ]; then
    awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0" >&2
    exit 2
fi

swift build --package-path "$PACKAGE" --product transcribe >&2
exec "$PACKAGE/.build/debug/transcribe" "$@"
