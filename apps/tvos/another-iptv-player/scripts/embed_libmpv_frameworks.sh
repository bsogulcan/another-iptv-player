#!/bin/sh
# Copies prepared dylibs from LinkStaging into the app's Frameworks folder
# so dyld can resolve @rpath/lib*.dylib at runtime. Signs each dylib.

set -eo pipefail

SRC="${SRCROOT}/Vendor/libmpv/LinkStaging/${PLATFORM_NAME}"
DEST="${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}"

if [ ! -d "$SRC" ]; then
  echo "error: run 'Prepare libmpv link paths' first (missing $SRC)" >&2
  exit 1
fi

mkdir -p "$DEST"
for lib in "$SRC"/*.dylib; do
  [ -f "$lib" ] || continue
  name=$(basename "$lib")
  rm -f "$DEST/$name"
  cp "$lib" "$DEST/$name"
done

SIGN="${EXPANDED_CODE_SIGN_IDENTITY:-}"
if [ -z "$SIGN" ]; then
  SIGN="${CODE_SIGN_IDENTITY:--}"
fi
for lib in "$DEST"/*.dylib; do
  [ -f "$lib" ] || continue
  /usr/bin/codesign --force --sign "$SIGN" --timestamp=none \
    --generate-entitlement-der "$lib"
done
