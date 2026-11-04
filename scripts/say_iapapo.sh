#!/bin/bash

VOICE=$1
FILE=$2

if [ "$VOICE" = "" ]; then 
  VOICE="Voice 1"; 
  FILE="Siri_en_US";
fi

if [ "$FILE" = "" ]; then 
  FILE="$VOICE"
fi

mkdir -p media/iapapo
mkdir -p media/negative

PHONEME="iapapo"
IAPAPO1="$PHONEME"
IAPAPO2="$PHONEME!"
IAPAPO3="$PHONEME?"
IAPAPO4="$PHONEME."
NEGATIVE1="We are testing the microphone"
NEGATIVE2="I love Iowa Popovers. Do you have a recipe?"
NEGATIVE3="I am really worried about the weather tomorrow. What's the forecast?"
NEGATIVE4="Iowa Popovers"

# Returns 0 when two m4a files decode to identical PCM audio.
same_audio() {
  local tmp status
  tmp=$(mktemp -d)
  afconvert -f WAVE -d LEI16 "$1" "$tmp/a.wav" && afconvert -f WAVE -d LEI16 "$2" "$tmp/b.wav"
  status=$?
  if [ $status -eq 0 ]; then
    cmp -s "$tmp/a.wav" "$tmp/b.wav"
    status=$?
  fi
  rm -rf "$tmp"
  return $status
}

# Rewrites an m4a with its creation timestamp removed, so repeated runs of the same audio give identical bytes.
normalize() {
  local tmp="$1.tmp.m4a"
  ffmpeg -hide_banner -loglevel error -y -i "$1" -map_metadata -1 -fflags +bitexact -c copy -metadata creation_time= -movflags +faststart "$tmp" && mv "$tmp" "$1"
}

say -v "$VOICE" "$IAPAPO1" 
say -v "$VOICE" -o media/iapapo/${FILE}__.m4a --file-format=m4af --data-format=aac "$IAPAPO1"
say -v "$VOICE" "$IAPAPO2" 
say -v "$VOICE" -o media/iapapo/${FILE}_x.m4a --file-format=m4af --data-format=aac "$IAPAPO2"
if same_audio "media/iapapo/${FILE}__.m4a" "media/iapapo/${FILE}_x.m4a"; then
  rm media/iapapo/${FILE}_x.m4a 
fi
say -v "$VOICE" "$IAPAPO3" 
say -v "$VOICE" -o media/iapapo/${FILE}_q.m4a --file-format=m4af --data-format=aac "$IAPAPO3"
if same_audio "media/iapapo/${FILE}__.m4a" "media/iapapo/${FILE}_q.m4a"; then
  rm media/iapapo/${FILE}_q.m4a 
fi
say -v "$VOICE" "$IAPAPO4" 
say -v "$VOICE" -o media/iapapo/${FILE}_p.m4a --file-format=m4af --data-format=aac "$IAPAPO4"
if same_audio "media/iapapo/${FILE}__.m4a" "media/iapapo/${FILE}_p.m4a"; then
  rm media/iapapo/${FILE}_p.m4a 
fi

say -v "$VOICE" -o media/negative/${FILE}_1.m4a --file-format=m4af --data-format=aac "$NEGATIVE1"
say -v "$VOICE" -o media/negative/${FILE}_2.m4a --file-format=m4af --data-format=aac "$NEGATIVE2"
say -v "$VOICE" -o media/negative/${FILE}_3.m4a --file-format=m4af --data-format=aac "$NEGATIVE3"
say -v "$VOICE" -o media/negative/${FILE}_4.m4a --file-format=m4af --data-format=aac "$NEGATIVE4"

for f in media/iapapo/${FILE}*.m4a media/negative/${FILE}_*.m4a; do
  [ -e "$f" ] && normalize "$f"
done

ls -R media | grep "${FILE}"

