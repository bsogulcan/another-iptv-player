#!/usr/bin/env bash
# Build the app and package it as a signed .wgt for Samsung TVs.
#   TIZEN_PROFILE=aiptv bash scripts/package.sh
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/tizen-env.sh

npm run build
cp tizen/config.xml tizen/icon.png dist/

mkdir -p out
# Absolute paths: the tizen CLI resolves relative -o/-- against its own bin dir.
"$TIZEN_CLI" package -t wgt -s "${TIZEN_PROFILE:-aiptv}" -- "$PWD/dist" -o "$PWD/out"
# The TV-side installer chokes on spaces in the wgt filename (config.xml <name>).
if [[ -f "$PWD/out/Another IPTV Player.wgt" ]]; then
  mv "$PWD/out/Another IPTV Player.wgt" "$PWD/out/AnotherIPTVPlayer.wgt"
fi
echo "Packaged: $(ls "$PWD"/out/*.wgt | tail -1)"
