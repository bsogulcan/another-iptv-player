#!/bin/sh
# FFmpegKit 6.1.4 supplies static macOS binaries inside shallow frameworks.
# Xcode embeds stub bundles after linking the archives. Give those embedded
# copies the versioned structure required by macOS bundle validation.
set -eu
index=0
while [ "$index" -lt "${SCRIPT_INPUT_FILE_COUNT:-0}" ]; do
    framework=$(printenv "SCRIPT_INPUT_FILE_$index")
    index=$((index + 1))
    if [ -d "$framework/Versions" ]; then continue; fi
    name=$(basename "$framework" .framework)
    test -f "$framework/$name"
    test -f "$framework/Info.plist"
    version="$framework/Versions/A"
    mkdir -p "$version/Resources"
    mv "$framework/Info.plist" "$version/Resources/Info.plist"
    mv "$framework/$name" "$version/$name"
    if [ -d "$framework/_CodeSignature" ]; then mv "$framework/_CodeSignature" "$version/"; fi
    ln -s A "$framework/Versions/Current"
    ln -s Versions/Current/Resources "$framework/Resources"
    ln -s "Versions/Current/$name" "$framework/$name"
    if [ "${CODE_SIGNING_ALLOWED:-YES}" != NO ]; then
        /usr/bin/codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" --timestamp=none "$framework"
    fi
done
