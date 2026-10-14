#!/usr/bin/env bash
# Снимки терминала: tools/term_shots.sh -> build/ui_term_*.png (и .ppm). Нужен Python с Pillow.
set -e
REPO="$(cd "$(dirname "$0")/.." && pwd)"
EMU="${CRAFTOS_PC:-D:/lin/Projects/MC/CC-Projects/_tools/CraftOS-PC}"
ROOT_WIN=$(cygpath -w "$REPO")
cp "$REPO/tools/term_shots.cub" "$REPO/tests/cases/lib_dbg_tshots.cub"
: > "$REPO/tests/cases/lib_dbg_tshots.loader"
rm -f "$REPO"/build/ui_term_*.ppm "$REPO"/build/ui_term_*.png
timeout 300 "$EMU/CraftOS-PC_console.exe" --headless -d "$EMU/data" --mount-rw "/repo=$ROOT_WIN" \
  --exec "local f = loadfile('/repo/tests/run.lua'); f('dbg_tshots')" >/dev/null 2>&1 || true
rm -f "$REPO/tests/cases/lib_dbg_tshots.cub" "$REPO/tests/cases/lib_dbg_tshots.loader"
python "$REPO/tools/ppm2png.py"
