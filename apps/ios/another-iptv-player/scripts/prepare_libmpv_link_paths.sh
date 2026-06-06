#!/bin/sh
set -euo pipefail
ROOT="${SRCROOT}/Vendor/libmpv/Frameworks"
OUT="${SRCROOT}/Vendor/libmpv/LinkStaging/${PLATFORM_NAME}"
if [ ! -d "$ROOT" ]; then
  echo "error: libmpv frameworks missing. Run: cd \"\${SRCROOT}/Vendor/libmpv\" && make" >&2
  exit 1
fi
rm -rf "$OUT"
mkdir -p "$OUT"
if [ "${PLATFORM_NAME}" = "iphonesimulator" ]; then
  SLICE="ios-arm64_x86_64-simulator"
else
  SLICE="ios-arm64"
fi
for xcf in "$ROOT"/*.xcframework; do
  base=$(basename "$xcf" .xcframework)
  fw="$xcf/$SLICE/${base}.framework"
  if [ ! -d "$fw" ]; then
    echo "error: missing $fw" >&2
    exit 1
  fi
  cp -R "$fw" "$OUT/"
done
