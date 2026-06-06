#!/bin/sh
set -eo pipefail
SRC="${SRCROOT}/Vendor/libmpv/LinkStaging/${PLATFORM_NAME}"
DEST="${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}"
if [ ! -d "$SRC" ]; then
  echo "error: run Prepare libmpv link paths first (missing $SRC)" >&2
  exit 1
fi
mkdir -p "$DEST"
for fw in "$SRC"/*.framework; do
  base=$(basename "$fw")
  rm -rf "$DEST/$base"
  cp -RH "$fw" "$DEST/"
done

# macOS Hardened Runtime ile gömülü framework'lerin imzalı olması gerekir.
SIGN="${EXPANDED_CODE_SIGN_IDENTITY:-}"
if [ -z "$SIGN" ]; then
  SIGN="${CODE_SIGN_IDENTITY:--}"
fi
for fw in "$DEST"/*.framework; do
  [ -d "$fw" ] || continue
  /usr/bin/codesign --force --sign "$SIGN" --timestamp=none \
    --options runtime "$fw"
done
