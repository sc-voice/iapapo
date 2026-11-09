#!/bin/sh
# Prepares lab/ so an archived run can be rebuilt with train.py. See scripts/python/lab_init.py.
#
# Usage:
#   scripts/lab_init.sh <run id>
#
# Example:
#   scripts/lab_init.sh 0Q6x7T

HERE="$(cd "$(dirname "$0")" && pwd)"

exec "$HERE/../.venv/bin/python" "$HERE/python/lab_init.py" "$@"
