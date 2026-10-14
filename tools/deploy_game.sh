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
for d in src lib tests tools game examples assets; do
  rm -rf "$DEST/repo/$d"
  cp -r "$REPO/$d" "$DEST/repo/$d"
done
mkdir -p "$DEST/repo/build"
rm -f "$DEST/repo/build/progress.txt" "$DEST/repo/build/test-result.txt" "$DEST/repo/build/bench-result.txt"
echo "deployed to: $DEST/repo"
du -sk "$DEST/repo" | cut -f1 | xargs -I{} echo "{} KB"
