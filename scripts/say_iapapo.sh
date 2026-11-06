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
HARD_NEG4="Iowa Papa"
HARD_NEG5="Tomorrow"
HARD_NEG6="I am really"
HARD_NEG7="I a peeppee"


NEG_SENT1="Whenever you find yourself on the side of the majority, it is time to pause and reflect."
NEG_SENT2="Age is an issue of mind over matter. If you don't mind, it doesn't matter."
NEG_SENT3="Clothes make the man. Appearances are deceptive, and not all that glitters is gold."

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

FMT="--file-format=m4af --data-format=aac" 

say -v "$VOICE" -o media/iapapo/${FILE}__.m4a $FMT "$IAPAPO1"
say -v "$VOICE" -o media/iapapo/${FILE}_x.m4a $FMT "$IAPAPO2"
if same_audio "media/iapapo/${FILE}__.m4a" "media/iapapo/${FILE}_x.m4a"; then
  rm media/iapapo/${FILE}_x.m4a 
fi
say -v "$VOICE" -o media/iapapo/${FILE}_q.m4a $FMT "$IAPAPO3"
if same_audio "media/iapapo/${FILE}__.m4a" "media/iapapo/${FILE}_q.m4a"; then
  rm media/iapapo/${FILE}_q.m4a 
fi
say -v "$VOICE" -o media/iapapo/${FILE}_p.m4a $FMT "$IAPAPO4"
if same_audio "media/iapapo/${FILE}__.m4a" "media/iapapo/${FILE}_p.m4a"; then
  rm media/iapapo/${FILE}_p.m4a 
fi

say -v "$VOICE" "$FILE $PHONEME"
say -v "$VOICE" -o media/negative/${FILE}_1.m4a $FMT "$NEGATIVE1"
say -v "$VOICE" -o media/negative/${FILE}_2.m4a $FMT "$NEGATIVE2"
say -v "$VOICE" -o media/negative/${FILE}_3.m4a $FMT "$NEGATIVE3"

say -v "$VOICE" "${HARD_NEG4}"
say -v "$VOICE" -o media/negative/${FILE}_4.m4a $FMT "${HARD_NEG4}"
say -v "$VOICE" -o media/negative/${FILE}_4q.m4a $FMT "${HARD_NEG4}?"
say -v "$VOICE" "${HARD_NEG5}"
say -v "$VOICE" -o media/negative/${FILE}_5.m4a $FMT "${HARD_NEG5}"
say -v "$VOICE" -o media/negative/${FILE}_5q.m4a $FMT "${HARD_NEG5}?"
say -v "$VOICE" "${HARD_NEG6}"
say -v "$VOICE" -o media/negative/${FILE}_6.m4a $FMT "${HARD_NEG6}"
say -v "$VOICE" -o media/negative/${FILE}_6q.m4a $FMT "${HARD_NEG6}?"
say -v "$VOICE" "${HARD_NEG7}"
say -v "$VOICE" -o media/negative/${FILE}_7.m4a $FMT "${HARD_NEG7}"
say -v "$VOICE" -o media/negative/${FILE}_7q.m4a $FMT "${HARD_NEG7}?"
say -v "$VOICE" -o media/negative/${FILE}_s1.m4a $FMT "${NEG_SENT1}"
say -v "$VOICE" -o media/negative/${FILE}_s2.m4a $FMT "${NEG_SENT2}"
say -v "$VOICE" -o media/negative/${FILE}_s3.m4a $FMT "${NEG_SENT3}"

for f in media/iapapo/${FILE}*.m4a media/negative/${FILE}_*.m4a; do
  [ -e "$f" ] && normalize "$f"
done

ls -R media | grep "${FILE}"

