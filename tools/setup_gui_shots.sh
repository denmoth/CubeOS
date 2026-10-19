#!/usr/bin/env bash
# Screenshots of the pixel installer: tools/setup_gui_shots.sh -> build/ui_setup_*.png (needs build/packages and Pillow).
set -e
REPO="$(cd "$(dirname "$0")/.." && pwd)"
EMU="${CRAFTOS_PC:-D:/lin/Projects/MC/CC-Projects/_tools/CraftOS-PC}"
ROOT_WIN=$(cygpath -w "$REPO")
cp "$REPO/tools/setup_gui_shots.cub" "$REPO/tests/cases/lib_dbg_gshots.cub"
: > "$REPO/tests/cases/lib_dbg_gshots.loader"
rm -f "$REPO"/build/ui_setup_*.ppm "$REPO"/build/ui_setup_*.png
timeout 400 "$EMU/CraftOS-PC_console.exe" --headless -d "$EMU/data" --id 962 --mount-rw "/repo=$ROOT_WIN" \
  --exec "local f = loadfile('/repo/tests/run.lua'); f('dbg_gshots', 'setup-gshots-result.txt')" >/dev/null 2>&1 || true
rm -f "$REPO/tests/cases/lib_dbg_gshots.cub" "$REPO/tests/cases/lib_dbg_gshots.loader"
grep -E "shots|runtime|FAIL" "$REPO/build/setup-gshots-result.txt" | head -5 || true
python "$REPO/tools/ppm2png.py" | grep setup || true
