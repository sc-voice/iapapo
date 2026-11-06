#!/bin/sh
# Prints lines of tracked code by area and language.
# Counts only code: Swift, Python, shell, TOML and Makefiles. Excludes generated and data files.
set -e
cd "$(dirname "$0")/.."

git ls-files \
  | grep -E '\.(swift|py|sh|toml)$|(^|/)Makefile$' \
  | while IFS= read -r f; do
      [ -f "$f" ] || continue
      printf '%s\t%s\n' "$(wc -l < "$f" | tr -d ' ')" "$f"
    done \
  | awk -F'\t' '
    function area(p) {
      if (p ~ /^scripts\//) return "scripts"
      if (p ~ /^VA\/VA(UI)?Tests\//) return "VA tests and UI tests"
      if (p ~ /^VA\/VA\//) return "VA app"
      if (p ~ /^VACore\/Sources\//) return "VACore sources"
      if (p ~ /^VACore\/Tests\//) return "VACore tests"
      if (p == "VACore/Package.swift") return "VACore package"
      if (p == "Makefile") return "Makefile"
      if (p == "pyproject.toml") return "pyproject"
      return "other"
    }
    function lang(p) {
      if (p ~ /\.swift$/) return "Swift"
      if (p ~ /\.py$/) return "Python"
      if (p ~ /\.sh$/) return "shell"
      if (p ~ /\.toml$/) return "TOML"
      return "Make"
    }
    { a[area($2) "\t" lang($2)] += $1 }
    END { for (k in a) print k "\t" a[k] }
  ' \
  | sort -t "$(printf '\t')" -k1,1 -k2,2 \
  | awk -F'\t' '
    BEGIN {
      printf "%-22s %-8s %6s\n", "Area", "Language", "Lines"
      printf "%-22s %-8s %6s\n", "----------------------", "--------", "-----"
    }
    { printf "%-22s %-8s %6d\n", $1, $2, $3; t += $3 }
    END {
      printf "%-22s %-8s %6s\n", "----------------------", "--------", "-----"
      printf "%-22s %-8s %6d\n", "Total", "", t
    }
  '
