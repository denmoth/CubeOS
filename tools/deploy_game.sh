#!/usr/bin/env bash
# Копирует репозиторий в папку компьютера в мире инстанса CubeOS Dev как /repo, чтобы проверять Cubic в настоящем CC.
# Использование: tools/deploy_game.sh [мир] [id компьютера]
# Результаты проверки читаются обратно из build/ этой же папки.
set -e
REPO="$(cd "$(dirname "$0")/.." && pwd)"
SAVES="${CUBEOS_DEV_SAVES:-D:/PrismLauncher/instances/CubeOS Dev/minecraft/saves}"
WORLD="${1:-Новый мир}"
ID="${2:-0}"
DEST="$SAVES/$WORLD/computercraft/computer/$ID"
mkdir -p "$DEST/repo"
for d in src lib sys tests tools game examples assets; do
  rm -rf "$DEST/repo/$d"
  cp -r "$REPO/$d" "$DEST/repo/$d"
done
mkdir -p "$DEST/repo/build"
rm -f "$DEST/repo/build/progress.txt" "$DEST/repo/build/test-result.txt" "$DEST/repo/build/bench-result.txt"
# Цепочка загрузки уже установлена в игре (game/install_dev.lua): обновляем её файлы тоже, иначе система грузится по старому stage2
# (без рабочего стола и т. д.). Настройки /cubeos/sys/cfg не трогаем.
if [ -d "$DEST/cubeos/sys/boot" ]; then
  cp "$REPO/sys/startup.lua" "$DEST/startup.lua"
  for f in "$REPO"/sys/boot/*; do cp "$f" "$DEST/cubeos/sys/boot/"; done
  mkdir -p "$DEST/cubeos/sys/services"
  for f in "$REPO"/sys/services/*; do cp "$f" "$DEST/cubeos/sys/services/"; done
  echo "boot chain refreshed in $DEST/cubeos/sys (Ctrl+R in the game to apply)"
fi
echo "deployed to: $DEST/repo"
du -sk "$DEST/repo" | cut -f1 | xargs -I{} echo "{} KB"
