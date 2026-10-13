#!/usr/bin/env bash
# Запуск утилиты cubic на ПК через CraftOS-PC. Использование:
#   tools/cubic.sh compile файл.cub [вывод.lua] [--minify] [--keep-comments] [--map]
#   tools/cubic.sh check файл.cub
#   tools/cubic.sh run файл.cub
# Пути задаются относительно текущего каталога.
set -e
REPO="$(cd "$(dirname "$0")/.." && pwd)"
EMU="${CRAFTOS_PC:-D:/lin/Projects/MC/CC-Projects/_tools/CraftOS-PC}"
DATA=$(cygpath -w "$EMU")/data
WORK=$(cygpath -w "$PWD")
mkdir -p "$REPO/build"
rm -f "$REPO/build/cli-output.txt"
ARGS=""
for a in "$@"; do
  case "$a" in
    --*) ARGS="$ARGS'$a', " ;;
    compile|check|run) ARGS="$ARGS'$a', " ;;
    *) ARGS="$ARGS'/work/$a', " ;;
  esac
done
ARGS="${ARGS%, }"
timeout 120 "$EMU/CraftOS-PC_console.exe" --headless -d "$DATA" \
  --mount-rw "/repo=$(cygpath -w "$REPO")" --mount-rw "/work=$WORK" \
  --exec "local f = loadfile('/repo/tools/cubic.lua'); f($ARGS)" >/dev/null 2>&1 || true
if [ -f "$REPO/build/cli-output.txt" ]; then
  grep -v '^exit:' "$REPO/build/cli-output.txt"
  grep -q '^exit:0$' "$REPO/build/cli-output.txt"
else
  echo "cubic: no output (the tool crashed)"
  exit 2
fi
