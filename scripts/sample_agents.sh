#!/bin/bash
# Generates the wake-word samples for every agent voice by calling say_iapapo.sh once per voice.
#
# Each line of the table below is "<say voice>|<file name>":
#   the voice is the exact name `say -v` accepts on this Mac,
#   the file name is passed to say_iapapo.sh as its FILE argument.
#
# Usage:
#   scripts/sample_agents.sh
#
# Note: say_iapapo.sh speaks each phrase aloud as it runs, so this takes a while.

set -e

HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."

while IFS='|' read -r voice file; do
    echo "== $voice -> $file"
    "$HERE/say_iapapo.sh" "$voice" "$file"
done <<'EOF'
Allison (Enhanced)|Allison_enhanced
Ava (Premium)|Ava_premium
Daniel (Enhanced)|Daniel_enhanced
Evan (Enhanced)|Evan_enhanced
Fiona (Enhanced)|Fiona_enhanced
Isha (Premium)|Isha_premium
Jamie (Premium)|Jamie_premium
Joelle (Enhanced)|Joelle_enhanced
Lee (Premium)|Lee_premium
Matilda (Premium)|Matilda_premium
Moira (Enhanced)|Moira_enhanced
Nathan (Enhanced)|Nathan_enhanced
Rishi (Enhanced)|Rishi_enhanced
Sangeeta (Enhanced)|Sangeeta_enhanced
Serena (Premium)|Serena_premium
Stephanie (Enhanced)|Stephanie_enhanced
Tessa (Enhanced)|Tessa_enhanced
Tom (Enhanced)|Tom_enhanced
Veena (Enhanced)|Veena_enhanced
Zoe (Premium)|Zoe_premium
Aman (English (India))|Aman
Tara (English (India))|Tara
Voice 1|Voice_1_en_US
EOF

rm media/iapapo/Isha*.m4a
rm media/iapapo/Fiona*.m4a
rm media/iapapo/Sangeeta*.m4a
rm media/iapapo/Tara*.m4a
rm media/iapapo/Joelle*.m4a
