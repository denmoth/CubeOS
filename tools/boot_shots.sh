#!/usr/bin/env bash
# Снимки экрана загрузки: tools/boot_shots.sh -> build/ui_boot_*.png (и .ppm). Нужен Python с Pillow.
set -e
REPO="$(cd "$(dirname "$0")/.." && pwd)"
EMU="${CRAFTOS_PC:-D:/lin/Projects/MC/CC-Projects/_tools/CraftOS-PC}"
ROOT_WIN=$(cygpath -w "$REPO")
cp "$REPO/tools/boot_shots.cub" "$REPO/tests/cases/lib_dbg_bshots.cub"
: > "$REPO/tests/cases/lib_dbg_bshots.loader"
rm -f "$REPO"/build/ui_boot_*.ppm "$REPO"/build/ui_boot_*.png
timeout 300 "$EMU/CraftOS-PC_console.exe" --headless -d "$EMU/data" --mount-rw "/repo=$ROOT_WIN" \
  --exec "local f = loadfile('/repo/tests/run.lua'); f('dbg_bshots')" >/dev/null 2>&1 || true
rm -f "$REPO/tests/cases/lib_dbg_bshots.cub" "$REPO/tests/cases/lib_dbg_bshots.loader"
python "$REPO/tools/ppm2png.py"
