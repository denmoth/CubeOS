#!/usr/bin/env bash
# Снимки рабочего стола CDE: tools/login_shots.sh [term] -> build/ui_login_*.png (и .ppm). Нужен Python с Pillow.
set -e
REPO="$(cd "$(dirname "$0")/.." && pwd)"
EMU="${CRAFTOS_PC:-D:/lin/Projects/MC/CC-Projects/_tools/CraftOS-PC}"
ROOT_WIN=$(cygpath -w "$REPO")
cp "$REPO/tools/login_shots.cub" "$REPO/tests/cases/lib_dbg_lshots.cub"
: > "$REPO/tests/cases/lib_dbg_lshots.loader"
rm -f "$REPO/build/login_shots_term_only"
[ "${1:-}" = "term" ] && : > "$REPO/build/login_shots_term_only"
rm -f "$REPO"/build/ui_login_*.ppm "$REPO"/build/ui_login_*.png
timeout 300 "$EMU/CraftOS-PC_console.exe" --headless -d "$EMU/data" --mount-rw "/repo=$ROOT_WIN" \
  --exec "local f = loadfile('/repo/tests/run.lua'); f('dbg_lshots')" >/dev/null 2>&1 || true
grep -A20 "dbg_lshots" "$REPO/build/test-result.txt" | head -20 || true
python "$REPO/tools/ppm2png.py"
