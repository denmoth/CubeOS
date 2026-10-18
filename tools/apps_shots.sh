#!/usr/bin/env bash
# Снимки файлового менеджера Axo: tools/apps_shots.sh -> build/ui_app_*.png (и .ppm). Нужен Python с Pillow.
set -e
REPO="$(cd "$(dirname "$0")/.." && pwd)"
EMU="${CRAFTOS_PC:-D:/lin/Projects/MC/CC-Projects/_tools/CraftOS-PC}"
ROOT_WIN=$(cygpath -w "$REPO")
cp "$REPO/tools/apps_shots.cub" "$REPO/tests/cases/lib_dbg_apshots.cub"
: > "$REPO/tests/cases/lib_dbg_apshots.loader"
rm -f "$REPO"/build/ui_app_*.ppm "$REPO"/build/ui_app_*.png
timeout 300 "$EMU/CraftOS-PC_console.exe" --headless -d "$EMU/data" --mount-rw "/repo=$ROOT_WIN" \
  --exec "local f = loadfile('/repo/tests/run.lua'); f('dbg_apshots')" >/dev/null 2>&1 || true
rm -f "$REPO/tests/cases/lib_dbg_apshots.cub" "$REPO/tests/cases/lib_dbg_apshots.loader"
grep -A20 "dbg_apshots" "$REPO/build/test-result.txt" | head -20 || true
python "$REPO/tools/ppm2png.py"
