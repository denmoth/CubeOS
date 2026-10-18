#!/usr/bin/env bash
# Тесты самого компилятора Cubic (все tests/cases, кроме lib_*), одним запуском эмулятора. Результат: build/test-result-compiler.txt
set -e
cd "$(dirname "$0")/.."
EMU="${CRAFTOS_PC:-D:/lin/Projects/MC/CC-Projects/_tools/CraftOS-PC}"
ROOT_WIN=$(cygpath -w "$PWD")
names=$(ls tests/cases/*.cub | xargs -n1 basename | sed 's/\.cub$//' | grep -v '^lib_' | sort -u | paste -sd, -)
rm -f build/test-result-compiler.txt
timeout 500 "$EMU/CraftOS-PC_console.exe" --headless -d "$EMU/data" --id 142 --mount-rw "/repo=$ROOT_WIN" \
  --exec "local f = loadfile('/repo/tests/run.lua'); f('=$names', 'test-result-compiler.txt')" >/dev/null 2>&1 || true
grep -E "^FAIL" -A6 build/test-result-compiler.txt | head -${LINES_SHOWN:-60}
tail -n 1 build/test-result-compiler.txt
