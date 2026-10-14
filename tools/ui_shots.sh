#!/usr/bin/env bash
# Снимки интерфейса: tools/ui_shots.sh -> build/ui_*.png (и .ppm). Нужен Python с Pillow.
set -e
REPO="$(cd "$(dirname "$0")/.." && pwd)"
EMU="${CRAFTOS_PC:-D:/lin/Projects/MC/CC-Projects/_tools/CraftOS-PC}"
ROOT_WIN=$(cygpath -w "$REPO")
cp "$REPO/tools/ui_shots.cub" "$REPO/tests/cases/lib_dbg_shots.cub"
: > "$REPO/tests/cases/lib_dbg_shots.loader"
rm -f "$REPO"/build/ui_*.ppm "$REPO"/build/ui_*.png
timeout 300 "$EMU/CraftOS-PC_console.exe" --headless -d "$EMU/data" --mount-rw "/repo=$ROOT_WIN" \
  --exec "local f = loadfile('/repo/tests/run.lua'); f('dbg_shots')" >/dev/null 2>&1 || true
rm -f "$REPO/tests/cases/lib_dbg_shots.cub" "$REPO/tests/cases/lib_dbg_shots.loader"
python "$REPO/tools/ppm2png.py"
