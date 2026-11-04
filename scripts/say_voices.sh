#!/bin/sh
# Generates one WAV per voice with macOS `say`, from a list of voices and phrases.
#
# Each line of the list is:  <voice name> <locale>    # <phrase>
# Lines starting with # and blank lines are skipped. Voice names may contain spaces
# and parentheses, for example "Eddy (English (UK))".
#
# Output: one 48 kHz float32 WAV per voice, named after the voice (non-alphanumeric
# characters become _), written to the output folder. The folder is created if needed.
# Existing files are overwritten.
#
# Usage:
#   scripts/say_voices.sh [--list <file>] [--out <dir>]
#   --list  voice list (default lab/voices_en.txt)
#   --out   output folder (default lab/voices)
#
# Example:
#   scripts/say_voices.sh
set -e

HERE="$(cd "$(dirname "$0")" && pwd)"
LIST="$HERE/../lab/voices_en.txt"
OUT="$HERE/../lab/voices"

print_help() {
    awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"
}

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help) print_help; exit 0 ;;
        --list) LIST="$2"; shift 2 ;;
        --out) OUT="$2"; shift 2 ;;
        *) echo "unknown argument: $1" >&2; print_help >&2; exit 2 ;;
    esac
done

[ -f "$LIST" ] || { echo "voice list not found: $LIST" >&2; exit 1; }
mkdir -p "$OUT"

count=0
while IFS= read -r line; do
    case "$line" in
        ''|\#*) continue ;;
    esac
    left="${line%%#*}"
    phrase="$(printf '%s' "${line#*#}" | sed -E 's/^ +//; s/ +$//')"
    left="$(printf '%s' "$left" | sed -E 's/[[:space:]]+$//')"
    voice="$(printf '%s' "$left" | sed -E 's/[[:space:]]+[^[:space:]]+$//')"
    if [ -z "$voice" ] || [ -z "$phrase" ]; then
        echo "skipping line without voice or phrase: $line" >&2
        continue
    fi
    file="$(printf '%s' "$voice" | tr -cs 'A-Za-z0-9' '_' | sed -E 's/_$//')"
    say -v "$voice" --file-format=WAVE --data-format=LEF32@48000 -o "$OUT/$file.wav" "$phrase"
    echo "$voice -> $OUT/$file.wav"
    count=$((count + 1))
done < "$LIST"

echo "done: $count voices in $OUT"
