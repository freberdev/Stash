#!/bin/bash
# Runs the test suite and prints only failures and the summary.
set -uo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
swift test "$@" > build/test.log 2>&1
STATUS=$?
grep -E "error:|warning: (var|unused|result)|✘|recorded an issue|Test run with" build/test.log | grep -v "^$" | head -40
exit $STATUS
