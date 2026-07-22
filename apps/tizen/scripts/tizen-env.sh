# Locates Tizen SDK tools across known install layouts:
#  - VS Code Tizen Extension: ~/.tizen-extension-platform/server/sdktools/data/tools
#  - Tizen Studio:            ~/tizen-studio/tools
# Sourced by package.sh / deploy.sh. Override with TIZEN_CLI / SDB env vars.

VSCODE_TOOLS="$HOME/.tizen-extension-platform/server/sdktools/data/tools"
STUDIO_TOOLS="$HOME/tizen-studio/tools"

if [[ -z "${TIZEN_CLI:-}" ]]; then
  if command -v tizen >/dev/null 2>&1; then
    TIZEN_CLI="$(command -v tizen)"
  elif [[ -x "$VSCODE_TOOLS/ide/bin/tizen" ]]; then
    TIZEN_CLI="$VSCODE_TOOLS/ide/bin/tizen"
  elif [[ -x "$STUDIO_TOOLS/ide/bin/tizen" ]]; then
    TIZEN_CLI="$STUDIO_TOOLS/ide/bin/tizen"
  else
    echo "error: tizen CLI not found. Install the VS Code Tizen Extension CLI or Tizen Studio, or set TIZEN_CLI." >&2
    exit 1
  fi
fi

if [[ -z "${SDB:-}" ]]; then
  if command -v sdb >/dev/null 2>&1; then
    SDB="$(command -v sdb)"
  elif [[ -x "$VSCODE_TOOLS/sdb" ]]; then
    SDB="$VSCODE_TOOLS/sdb"
  elif [[ -x "$STUDIO_TOOLS/sdb" ]]; then
    SDB="$STUDIO_TOOLS/sdb"
  else
    echo "error: sdb not found. Install the VS Code Tizen Extension CLI or Tizen Studio, or set SDB." >&2
    exit 1
  fi
fi

export TIZEN_CLI SDB
