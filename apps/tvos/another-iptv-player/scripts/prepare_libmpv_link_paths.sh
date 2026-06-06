#!/bin/sh
# Copies per-platform libmpv dylibs from Vendor/libmpv/Dylibs into
# Vendor/libmpv/LinkStaging/$PLATFORM_NAME/ for linking + embedding.
#
# Layout:
#   Vendor/libmpv/Dylibs/<platform>/<arch>/lib*.dylib       (Makefile output)
#   Vendor/libmpv/LinkStaging/<platform>/lib*.dylib         (prepared here)

set -euo pipefail

ROOT="${SRCROOT}/Vendor/libmpv/Dylibs"
OUT="${SRCROOT}/Vendor/libmpv/LinkStaging/${PLATFORM_NAME}"

if [ ! -d "$ROOT/$PLATFORM_NAME" ]; then
  echo "error: Vendor/libmpv/Dylibs/$PLATFORM_NAME missing. Run: cd \"\${SRCROOT}/Vendor/libmpv\" && make" >&2
  exit 1
fi

rm -rf "$OUT"
mkdir -p "$OUT"

case "$PLATFORM_NAME" in
  appletvos)
    ARCH_DIR="$ROOT/appletvos/arm64"
    cp "$ARCH_DIR"/*.dylib "$OUT/"
    ;;
  appletvsimulator)
    ARM="$ROOT/appletvsimulator/arm64"
    X86="$ROOT/appletvsimulator/x86_64"
    if [ ! -d "$ARM" ] || [ ! -d "$X86" ]; then
      echo "error: missing simulator slice(s) under $ROOT/appletvsimulator" >&2
      exit 1
    fi
    for lib in "$ARM"/*.dylib; do
      name=$(basename "$lib")
      if [ -f "$X86/$name" ]; then
        lipo -create "$lib" "$X86/$name" -output "$OUT/$name"
      else
        cp "$lib" "$OUT/$name"
      fi
    done
    ;;
  *)
    echo "error: unsupported PLATFORM_NAME=$PLATFORM_NAME" >&2
    exit 1
    ;;
esac

echo "==> staged $(ls -1 "$OUT"/*.dylib 2>/dev/null | wc -l | tr -d ' ') dylibs into $OUT"
