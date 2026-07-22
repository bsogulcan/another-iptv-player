#!/usr/bin/env bash
# Package, install and launch on a TV in Developer Mode.
#   TV_IP=192.168.1.20 bash scripts/deploy.sh
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/tizen-env.sh

if [[ -z "${TV_IP:-}" ]]; then
  echo "error: set TV_IP to your TV's IP address (Developer Mode must be enabled)." >&2
  exit 1
fi

bash scripts/package.sh

"$SDB" connect "$TV_IP:26101"
SERIAL="$("$SDB" devices | awk '/26101/ {print $1; exit}')"
if [[ -z "$SERIAL" ]]; then
  echo "error: TV not visible in 'sdb devices' after connect." >&2
  exit 1
fi

WGT="$(ls "$PWD"/out/*.wgt | tail -1)"
"$TIZEN_CLI" install -n "$(basename "$WGT")" -s "$SERIAL" -- "$PWD/out"
"$TIZEN_CLI" run -p AIPTVapp01.AnotherIPTV -s "$SERIAL"
