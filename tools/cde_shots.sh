#!/usr/bin/env bash
# Снимки рабочего стола CDE: tools/cde_shots.sh [term] -> build/ui_cde_*.png (и .ppm). Нужен Python с Pillow.
set -e
REPO="$(cd "$(dirname "$0")/.." && pwd)"
EMU="${CRAFTOS_PC:-D:/lin/Projects/MC/CC-Projects/_tools/CraftOS-PC}"
ROOT_WIN=$(cygpath -w "$REPO")
cp "$REPO/tools/cde_shots.cub" "$REPO/tests/cases/lib_dbg_cshots.cub"
: > "$REPO/tests/cases/lib_dbg_cshots.loader"
cp "$REPO/examples/cde_demo.cub" "$REPO/tests/modules/cde_demo.cub"
rm -f "$REPO/build/cde_shots_term_only"
[ "${1:-}" = "term" ] && : > "$REPO/build/cde_shots_term_only"
rm -f "$REPO"/build/ui_cde_*.ppm "$REPO"/build/ui_cde_*.png
timeout 300 "$EMU/CraftOS-PC_console.exe" --headless -d "$EMU/data" --mount-rw "/repo=$ROOT_WIN" \
  --exec "local f = loadfile('/repo/tests/run.lua'); f('dbg_cshots')" >/dev/null 2>&1 || true
rm -f "$REPO/tests/cases/lib_dbg_cshots.cub" "$REPO/tests/cases/lib_dbg_cshots.loader" "$REPO/tests/modules/cde_demo.cub"
grep -A20 "dbg_cshots" "$REPO/build/test-result.txt" | head -20 || true
python "$REPO/tools/ppm2png.py"
