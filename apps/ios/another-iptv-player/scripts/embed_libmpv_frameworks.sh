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
  cp -R "$fw" "$DEST/"
done

# Fiziksel cihaz: gömülü .framework'ler imzasız olunca installd 0xe800801c verir.
SIGN="${EXPANDED_CODE_SIGN_IDENTITY:-}"
if [ -z "$SIGN" ]; then
  SIGN="${CODE_SIGN_IDENTITY:--}"
fi
for fw in "$DEST"/*.framework; do
  [ -d "$fw" ] || continue
  /usr/bin/codesign --force --sign "$SIGN" --timestamp=none \
    --generate-entitlement-der "$fw"
done
