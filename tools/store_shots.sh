#!/usr/bin/env bash
# Снимки магазина пакетов: tools/store_shots.sh -> build/ui_store_*.png (и .ppm). Нужен Python с Pillow.
# Свой компьютер эмулятора (--id) и свой файл результата, чтобы не мешать тестам, которые идут одновременно.
set -e
REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"
EMU="${CRAFTOS_PC:-D:/lin/Projects/MC/CC-Projects/_tools/CraftOS-PC}"
ROOT_WIN=$(cygpath -w "$REPO")
cp "$REPO/tools/store_shots.cub" "$REPO/tests/cases/lib_dbg_storeshots.cub"
: > "$REPO/tests/cases/lib_dbg_storeshots.loader"
rm -f "$REPO"/build/ui_store_*.ppm "$REPO"/build/ui_store_*.png "$REPO/build/dbg.txt"
timeout 300 "$EMU/CraftOS-PC_console.exe" --headless -d "$EMU/data" --id 977 --mount-rw "/repo=$ROOT_WIN" \
  --exec "local f = loadfile('/repo/tests/run.lua'); f('dbg_storeshots', 'test-result-storeshots.txt')" >/dev/null 2>&1 || true
rm -f "$REPO/tests/cases/lib_dbg_storeshots.cub" "$REPO/tests/cases/lib_dbg_storeshots.loader"
grep -A20 "dbg_storeshots" "$REPO/build/test-result-storeshots.txt" | head -20 || true
[ -f "$REPO/build/dbg.txt" ] && cat "$REPO/build/dbg.txt"
python - <<'EOF'
import glob
from PIL import Image
for f in sorted(glob.glob('build/ui_store_*.ppm')):
    im = Image.open(f)
    im = im.resize((im.width * 3, im.height * 3), Image.NEAREST)
    im.save(f.replace('.ppm', '.png'))
    print(f.replace('.ppm', '.png'))
EOF
