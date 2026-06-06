#!/usr/bin/env bash
# macos-ui-probe.sh — drive another-iptv-player macOS app for autonomous testing.
# Requires Terminal to have Accessibility permission (System Settings → Privacy & Security → Accessibility).
#
# Commands:
#   launch              Open app (build needed first)
#   front               Bring to foreground
#   close               Kill app
#   ss [path]           Screenshot (default /tmp/iptv_ss.png), prints path
#   tree                Dump accessibility UI tree of front window
#   click "<text>"      Click first element whose value or name equals text
#   key "<k>" [mod]     Send keystroke; mod = cmd | shift | alt | cmd-shift
#   sleep [seconds]     Pause N seconds (default 1)
set -e

CMD="${1:-help}"
shift || true
PROCESS_NAME="another-iptv-player"
APP_PATH=$(find /Users/ogulcanozcan/Library/Developer/Xcode/DerivedData -type d -name "${PROCESS_NAME}.app" -not -path "*Index.noindex*" -path "*Build/Products/Debug/${PROCESS_NAME}.app" 2>/dev/null | head -1)

ensure_app() {
    if [ -z "$APP_PATH" ]; then
        echo "ERROR: ${PROCESS_NAME}.app not found in DerivedData. Run xcodebuild first." >&2
        exit 1
    fi
}

front_app() {
    osascript -e "tell application \"System Events\" to tell process \"${PROCESS_NAME}\" to set frontmost to true" >/dev/null 2>&1 || true
    sleep 0.3
}

case "$CMD" in
    launch)
        ensure_app
        open -a "$APP_PATH"
        sleep 1.5
        front_app
        ;;
    front)
        front_app
        ;;
    close)
        pkill -f "${PROCESS_NAME}" >/dev/null 2>&1 || true
        ;;
    ss|screenshot)
        OUT="${1:-/tmp/iptv_ss.png}"
        front_app
        screencapture -x -t png "$OUT"
        echo "$OUT"
        ;;
    tree)
        front_app
        osascript <<APPLE
tell application "System Events"
    tell process "${PROCESS_NAME}"
        return entire contents of window 1
    end tell
end tell
APPLE
        ;;
    click)
        TEXT="$1"
        if [ -z "$TEXT" ]; then
            echo "ERROR: click requires a text argument" >&2
            exit 1
        fi
        front_app
        osascript <<APPLE
-- Sidebar rows: tarama yapip eslesen row icin select kullan. Static text click
-- SwiftUI List(selection:) icin guvenilir tetiklenmiyor, row level select gerek.
-- Fallback: window icindeki UI elemanini click et (toolbar/butonlar icin).
tell application "System Events"
    tell process "${PROCESS_NAME}"
        try
            set outlineRows to rows of outline 1 of scroll area 1 of group 1 of splitter group 1 of group 1 of window 1
            repeat with r in outlineRows
                try
                    set sts to entire contents of r
                    set matched to false
                    repeat with elem in sts
                        try
                            -- Match via accessibility identifier (AXIdentifier) or label/value
                            if (description of elem is "${TEXT}") or (value of elem is "${TEXT}") then
                                set matched to true
                                exit repeat
                            end if
                        end try
                        try
                            if name of elem is "${TEXT}" then
                                set matched to true
                                exit repeat
                            end if
                        end try
                        try
                            -- AXIdentifier attribute (set via SwiftUI .accessibilityIdentifier)
                            if value of attribute "AXIdentifier" of elem is "${TEXT}" then
                                set matched to true
                                exit repeat
                            end if
                        end try
                    end repeat
                    if matched then
                        select r
                        return "OK (row select)"
                    end if
                end try
            end repeat
        end try
        set allElems to entire contents of window 1
        repeat with elem in allElems
            try
                if value of elem is "${TEXT}" then
                    click elem
                    return "OK (click)"
                end if
            end try
            try
                if name of elem is "${TEXT}" then
                    click elem
                    return "OK (click)"
                end if
            end try
            try
                if value of attribute "AXIdentifier" of elem is "${TEXT}" then
                    click elem
                    return "OK (click id)"
                end if
            end try
        end repeat
        return "NOT FOUND: ${TEXT}"
    end tell
end tell
APPLE
        ;;
    key)
        K="$1"
        MOD="${2:-}"
        case "$MOD" in
            cmd)       M='using command down' ;;
            shift)     M='using shift down' ;;
            alt|opt)   M='using option down' ;;
            ctrl)      M='using control down' ;;
            cmd-shift) M='using {command down, shift down}' ;;
            *)         M='' ;;
        esac
        front_app
        osascript -e "tell application \"System Events\" to keystroke \"${K}\" ${M}"
        ;;
    sleep)
        sleep "${1:-1}"
        ;;
    help|*)
        awk '/^# / { sub(/^# ?/, ""); print; next } /^set -e/ { exit }' "$0"
        ;;
esac
