#!/usr/bin/env bash
# End-to-end check of the installer on a clean CraftOS-PC computer (id 960): tools/setup_e2e.sh. Builds the packages first unless
# SKIP_BUILD=1. Result: build/setup-e2e.txt.
set -e
cd "$(dirname "$0")/.."
[ "${SKIP_BUILD:-}" = "1" ] || bash tools/build_packages.sh || true
ROOT_WIN=$(cygpath -w "$PWD")
EMU="${CRAFTOS_PC:-D:/lin/Projects/MC/CC-Projects/_tools/CraftOS-PC}"
rm -f build/setup-e2e.txt build/e2e-net
[ "${NET:-}" = "1" ] && : > build/e2e-net
timeout 600 "$EMU/CraftOS-PC_console.exe" --headless -d "$(cygpath -w "$EMU")/data" --id 960 --mount-rw "/repo=$ROOT_WIN" \
  --exec "local ok, e = pcall(loadfile('/repo/tools/setup_e2e.lua', nil, _ENV)) if not ok then local f = fs.open('/repo/build/setup-e2e.txt', 'a') f.write(tostring(e)) f.close() end os.shutdown()" >/dev/null 2>&1 || true
cat build/setup-e2e.txt
grep -q "SETUP E2E OK" build/setup-e2e.txt
