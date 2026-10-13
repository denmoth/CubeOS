#!/usr/bin/env bash
# Запуск тестов Cubic в CraftOS-PC (без окна). Использование: tools/test.sh [фильтр]
set -e
cd "$(dirname "$0")/.."
ROOT_WIN=$(cygpath -w "$PWD")
EMU="${CRAFTOS_PC:-D:/lin/Projects/MC/CC-Projects/_tools/CraftOS-PC}"
DATA=$(cygpath -w "$EMU")/data
mkdir -p build
rm -f build/test-result.txt
FILTER="${1:-}"
"$EMU/CraftOS-PC_console.exe" --headless -d "$DATA" --mount-rw "/repo=$ROOT_WIN" \
  --exec "local f = loadfile('/repo/tests/run.lua'); f('$FILTER')" >/dev/null 2>&1 || true
if [ -f build/test-result.txt ]; then
  cat build/test-result.txt
  tail -n 1 build/test-result.txt | grep -q " 0 failed" || exit 1
else
  echo "no result file: the test runner crashed (try running without --headless)"
  exit 2
fi
