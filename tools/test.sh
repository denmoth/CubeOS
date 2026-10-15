#!/usr/bin/env bash
# Запуск тестов Cubic в CraftOS-PC (без окна). Использование: tools/test.sh [фильтр]
#   с фильтром (подстрока имени теста; unit-тесты Lua это слово unit): один запуск эмулятора;
#   без фильтра: все тесты порциями по CHUNK (20) в свежих запусках эмулятора и отдельно unit. Полный прогон одним запуском со временем
#   сильно замедляется (причина не найдена, накапливается состояние эмулятора), порции этого избегают.
# Результат пишется в build/test-result.txt, самые медленные тесты в build/test-timing.txt.
set -e
cd "$(dirname "$0")/.."
ROOT_WIN=$(cygpath -w "$PWD")
EMU="${CRAFTOS_PC:-D:/lin/Projects/MC/CC-Projects/_tools/CraftOS-PC}"
DATA=$(cygpath -w "$EMU")/data
CHUNK="${CHUNK:-20}"
mkdir -p build

# один запуск эмулятора с аргументом раннера; кладёт результат в build/test-result.txt
run_one() {
  rm -f build/test-result.txt
  timeout 600 "$EMU/CraftOS-PC_console.exe" --headless -d "$DATA" --mount-rw "/repo=$ROOT_WIN" \
    --exec "local f = loadfile('/repo/tests/run.lua'); f('$1')" >/dev/null 2>&1 || true
}

if [ -n "${1:-}" ]; then
  run_one "$1"
  if [ -f build/test-result.txt ]; then
    cat build/test-result.txt
    tail -n 1 build/test-result.txt | grep -q " 0 failed" || exit 1
    exit 0
  fi
  echo "no result file: the test runner crashed (try running without --headless)"
  exit 2
fi

names=($(ls tests/cases/*.cub | xargs -n1 basename | sed 's/\.cub$//' | sort -u))
: > build/test-all.txt
passed=0
failed=0
crashed=0
i=0
while [ $i -lt ${#names[@]} ]; do
  list=$(IFS=,; echo "${names[*]:$i:$CHUNK}")
  run_one "=$list"
  if [ -f build/test-result.txt ]; then
    cat build/test-result.txt >> build/test-all.txt
    read -r p f < <(tail -n 1 build/test-result.txt | sed -E 's/^([0-9]+) passed, ([0-9]+) failed.*/\1 \2/')
    passed=$((passed + p)); failed=$((failed + f))
  else
    crashed=$((crashed + 1))
    echo "chunk starting at ${names[$i]}: the runner crashed" >> build/test-all.txt
  fi
  i=$((i + CHUNK))
done
run_one "=unit"
if [ -f build/test-result.txt ]; then
  cat build/test-result.txt >> build/test-all.txt
  read -r p f < <(tail -n 1 build/test-result.txt | sed -E 's/^([0-9]+) passed, ([0-9]+) failed.*/\1 \2/')
  passed=$((passed + p)); failed=$((failed + f))
else
  crashed=$((crashed + 1))
  echo "unit: the runner crashed" >> build/test-all.txt
fi
grep -v "^ok" build/test-all.txt | grep -v "^[0-9]* passed" | grep -v '^$' || true
echo "$passed passed, $failed failed"
[ "$crashed" -eq 0 ] && [ "$failed" -eq 0 ] || exit 1
