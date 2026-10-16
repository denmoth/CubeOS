#!/usr/bin/env bash
# Кадры анимаций CDE: tools/anim_shots.sh -> build/ui_anim_*.gif. Нужен Python с Pillow.
set -e
REPO="$(cd "$(dirname "$0")/.." && pwd)"
EMU="${CRAFTOS_PC:-D:/lin/Projects/MC/CC-Projects/_tools/CraftOS-PC}"
ROOT_WIN=$(cygpath -w "$REPO")
cp "$REPO/tools/anim_shots.cub" "$REPO/tests/cases/lib_dbg_ashots.cub"
: > "$REPO/tests/cases/lib_dbg_ashots.loader"
cp "$REPO/examples/cde_demo.cub" "$REPO/tests/modules/cde_demo.cub"
rm -f "$REPO"/build/anim_*.ppm "$REPO"/build/anim_*.png
timeout 590 "$EMU/CraftOS-PC_console.exe" --headless -d "$EMU/data" --mount-rw "/repo=$ROOT_WIN" \
  --exec "local f = loadfile('/repo/tests/run.lua'); f('dbg_ashots')" >/dev/null 2>&1 || true
rm -f "$REPO/tests/cases/lib_dbg_ashots.cub" "$REPO/tests/cases/lib_dbg_ashots.loader" "$REPO/tests/modules/cde_demo.cub"
grep -A20 "dbg_ashots" "$REPO/build/test-result.txt" | head -20 || true
python "$REPO/tools/frames2gif.py"
