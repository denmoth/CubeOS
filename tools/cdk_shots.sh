#!/usr/bin/env bash
# Снимки витрины cdk: tools/cdk_shots.sh -> build/ui_cdk_*.png (и .ppm). Нужен Python с Pillow.
set -e
REPO="$(cd "$(dirname "$0")/.." && pwd)"
EMU="${CRAFTOS_PC:-D:/lin/Projects/MC/CC-Projects/_tools/CraftOS-PC}"
ROOT_WIN=$(cygpath -w "$REPO")
cp "$REPO/tools/cdk_shots.cub" "$REPO/tests/cases/lib_dbg_kshots.cub"
: > "$REPO/tests/cases/lib_dbg_kshots.loader"
rm -f "$REPO"/build/ui_cdk_*.ppm "$REPO"/build/ui_cdk_*.png
timeout 300 "$EMU/CraftOS-PC_console.exe" --headless -d "$EMU/data" --mount-rw "/repo=$ROOT_WIN" \
  --exec "local f = loadfile('/repo/tests/run.lua'); f('dbg_kshots')" >/dev/null 2>&1 || true
grep -A20 "dbg_kshots" "$REPO/build/test-result.txt" | head -20 || true
python "$REPO/tools/ppm2png.py"
