#!/usr/bin/env bash
# Собирает все системные пакеты (packages/system/*.json5) в build/packages/ через CraftOS-PC без окна. Итог: build/build-packages.txt.
set -e
cd "$(dirname "$0")/.."
ROOT_WIN=$(cygpath -w "$PWD")
EMU="${CRAFTOS_PC:-D:/lin/Projects/MC/CC-Projects/_tools/CraftOS-PC}"
mkdir -p build
rm -f build/build-packages.txt build/build-packages-err.txt
timeout 900 "$EMU/CraftOS-PC_console.exe" --headless -d "$(cygpath -w "$EMU")/data" --id 952 --mount-rw "/repo=$ROOT_WIN" \
  --exec "local ok, e = pcall(loadfile('/repo/tools/build_packages.lua')) if not ok then local f = fs.open('/repo/build/build-packages-err.txt', 'w') f.write(tostring(e)) f.close() end os.shutdown()" >/dev/null 2>&1 || true
cat build/build-packages-err.txt 2>/dev/null || true
tail -n 3 build/build-packages.txt 2>/dev/null
grep -q "build ok" build/build-packages.txt
