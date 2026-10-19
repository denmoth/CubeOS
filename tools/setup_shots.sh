#!/usr/bin/env bash
# Screenshots of the installer screens: tools/setup_shots.sh -> build/setup_*.png (needs build/packages and Pillow).
set -e
REPO="$(cd "$(dirname "$0")/.." && pwd)"
EMU="${CRAFTOS_PC:-D:/lin/Projects/MC/CC-Projects/_tools/CraftOS-PC}"
ROOT_WIN=$(cygpath -w "$REPO")
cp "$REPO/tools/setup_shots.cub" "$REPO/tests/cases/lib_dbg_sshots.cub"
: > "$REPO/tests/cases/lib_dbg_sshots.loader"
rm -f "$REPO"/build/setup_*.txt "$REPO"/build/setup_*.png
timeout 300 "$EMU/CraftOS-PC_console.exe" --headless -d "$EMU/data" --id 961 --mount-rw "/repo=$ROOT_WIN" \
  --exec "local f = loadfile('/repo/tests/run.lua'); f('dbg_sshots', 'setup-shots-result.txt')" >/dev/null 2>&1 || true
rm -f "$REPO/tests/cases/lib_dbg_sshots.cub" "$REPO/tests/cases/lib_dbg_sshots.loader"
python "$REPO/tools/setup_shots.py"
