#!/bin/sh
# Runs before Compile Sources on every Xcode build. Sets marketingVersion (YY.MM) and
# buildVersion (YY.MM.patch) in VA/Version.swift, using the scv-app scheme:
# the month is the month two weeks from now; patch resets to 0 when YY.MM changes,
# and otherwise increments by one.
set -eu

FILE="${SRCROOT}/VA/Version.swift"
MARKETING="$(date +%y).$(date -v+14d +%m)"
CURRENT=$(sed -n 's/^public let buildVersion = "\(.*\)"$/\1/p' "$FILE")
OLD_MARKETING="${CURRENT%.*}"
OLD_PATCH="${CURRENT##*.}"
if [ "$OLD_MARKETING" = "$MARKETING" ]; then
  PATCH=$((OLD_PATCH + 1))
else
  PATCH=0
fi
NEW="${MARKETING}.${PATCH}"
sed -i '' \
  -e "s/^public let marketingVersion = \".*\"$/public let marketingVersion = \"${MARKETING}\"/" \
  -e "s/^public let buildVersion = \".*\"$/public let buildVersion = \"${NEW}\"/" "$FILE"
echo "marketingVersion ${MARKETING} buildVersion ${NEW}"
