#!/usr/bin/env bash
# Сквозная проверка: собрать пакеты (если нет SKIP_BUILD=1), поставить набор stew на чистый компьютер эмулятора, загрузить модули
# установленной системы. Использование: tools/e2e_stew.sh [набор (cubeos.minimal)] [storage (auto|packed|unpacked)]
set -e
cd "$(dirname "$0")/.."
[ "${SKIP_BUILD:-}" = "1" ] || bash tools/build_packages.sh || true
ROOT_WIN=$(cygpath -w "$PWD")
EMU="${CRAFTOS_PC:-D:/lin/Projects/MC/CC-Projects/_tools/CraftOS-PC}"
rm -f build/e2e-stew.txt
timeout 900 "$EMU/CraftOS-PC_console.exe" --headless -d "$(cygpath -w "$EMU")/data" --id 953 --mount-rw "/repo=$ROOT_WIN" \
  --exec "local ok, e = pcall(loadfile('/repo/tools/e2e_stew.lua'), '${1:-cubeos.minimal}', '${2:-auto}', '${3:-}') if not ok then print(e) end os.shutdown()" >/dev/null 2>&1 || true
cat build/e2e-stew.txt
grep -q "E2E OK" build/e2e-stew.txt
