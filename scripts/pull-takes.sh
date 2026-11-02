#!/bin/sh
# Copies wake-word takes off an iPad running VA, into lab/wakeword/takes/.
#
# What it does:
#   Finds the iPad by name in `xcrun devicectl list devices`, then replaces
#   lab/wakeword/takes/<device name>/ with a fresh copy of the app's
#   Documents/WakeWord folder (one folder per take). The folder then matches
#   the iPad.
#
# Usage:
#   scripts/pull-takes.sh <device name>   copy takes from the named device
#   scripts/pull-takes.sh --list          list devices Xcode can see
#   scripts/pull-takes.sh --help          show this text
#
# Before you run it:
#   - Connect the iPad by cable and unlock it.
#   - Select the iPad in Xcode's device menu, so the list shows it as "connected"
#     and not "connected (no DDI)". Xcode mounts the developer disk image then.
#   - The device name is matched without regard to case, for example: turtlepro.
#     Quote names with spaces: scripts/pull-takes.sh "Karl's iPad".
#
# After the pull:
#   Train on a take with: scripts/train.sh --take takes/<device name>/<take name>.
set -e

HERE="$(cd "$(dirname "$0")" && pwd)"
TAKES="$HERE/../lab/wakeword/takes"
BUNDLE_ID="net.sc-voice.VA"
UUID_PATTERN='[0-9A-Fa-f]\{8\}-[0-9A-Fa-f]\{4\}-[0-9A-Fa-f]\{4\}-[0-9A-Fa-f]\{4\}-[0-9A-Fa-f]\{12\}'

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

if [ "$1" = "--list" ]; then
    # Skip the two header lines of devicectl's table, and drop its hostname column.
    xcrun devicectl list devices | tail -n +3 | sed -E 's/[^ ]+\.coredevice\.local +//'
    exit 0
fi

NAME="$1"
LINE="$(xcrun devicectl list devices | tail -n +3 | grep -i "^$NAME  " || true)"
if [ -z "$LINE" ]; then
    echo "no device named '$NAME'. Run scripts/pull-takes.sh --list to see the names." >&2
    exit 1
fi
DEVICE_ID="$(printf '%s\n' "$LINE" | grep -o "$UUID_PATTERN" | head -1)"
if [ -z "$DEVICE_ID" ]; then
    echo "could not read the identifier for '$NAME' from devicectl output." >&2
    exit 1
fi

DEST="$TAKES/$NAME"
rm -rf "$DEST"
mkdir -p "$DEST"
echo "copying $BUNDLE_ID Documents/WakeWord from $NAME to $DEST"
xcrun devicectl device copy from \
    --device "$DEVICE_ID" \
    --domain-type appDataContainer \
    --domain-identifier "$BUNDLE_ID" \
    --source Documents/WakeWord \
    --destination "$DEST"
echo "done: $DEST"
