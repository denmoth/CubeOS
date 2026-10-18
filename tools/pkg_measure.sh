#!/usr/bin/env bash
# Замеры для .cpk (docs/packages, шаг 0): выпускная сборка lib, сжатие по файлам и блокам нашими lzfast/deflate в CraftOS-PC,
# затем zlib на ПК для варианта «целиком». Итог: build/pkg-measure.txt.
set -e
cd "$(dirname "$0")/.."
ROOT_WIN=$(cygpath -w "$PWD")
EMU="${CRAFTOS_PC:-D:/lin/Projects/MC/CC-Projects/_tools/CraftOS-PC}"
mkdir -p build
rm -rf build/dist build/pkg-measure.txt
timeout 900 "$EMU/CraftOS-PC_console.exe" --headless -d "$(cygpath -w "$EMU")/data" --id 950 --mount-rw "/repo=$ROOT_WIN" \
  --exec "local ok, e = pcall(loadfile('/repo/tools/pkg_measure.lua')) if not ok then local f = fs.open('/repo/build/pkg-measure-err.txt', 'w') f.write(tostring(e)) f.close() end os.shutdown()" >/dev/null 2>&1 || true
python tools/pkg_measure.py >> build/pkg-measure.txt
cat build/pkg-measure.txt
