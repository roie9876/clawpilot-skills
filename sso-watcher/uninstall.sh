#!/usr/bin/env bash
# uninstall.sh — Remove the SSO auto-picker from Hammerspoon
#
# Usage:
#   bash uninstall.sh
#
# What it does:
#   1. Removes sso-watcher.lua and config from ~/.hammerspoon/
#   2. Removes the require("sso-watcher") line from init.lua
#   3. Removes the log file
#   4. Reloads Hammerspoon (does NOT uninstall Hammerspoon itself)

set -euo pipefail

if [ "$(uname)" != "Darwin" ]; then
    echo "❌ This script is macOS-only."
    exit 1
fi

HS_DIR="$HOME/.hammerspoon"

echo "SSO Watcher Uninstaller"
echo "======================="
echo ""

# Remove Lua files
for f in sso-watcher.lua sso-watcher-config.lua; do
    if [ -f "$HS_DIR/$f" ]; then
        rm "$HS_DIR/$f"
        echo "✅ Removed $HS_DIR/$f"
    fi
done

# Remove require line from init.lua
if [ -f "$HS_DIR/init.lua" ]; then
    if grep -q 'require("sso-watcher")' "$HS_DIR/init.lua"; then
        # Remove the require line and its comment
        sed -i '' '/-- SSO auto-picker (installed by sso-watcher skill)/d' "$HS_DIR/init.lua"
        sed -i '' '/require("sso-watcher")/d' "$HS_DIR/init.lua"
        echo "✅ Removed sso-watcher from init.lua"
    fi
fi

# Remove log
LOG="$HOME/Scripts/sso-watcher-hammerspoon.log"
if [ -f "$LOG" ]; then
    rm "$LOG"
    echo "✅ Removed log: $LOG"
fi

# Reload Hammerspoon
if pgrep -x "Hammerspoon" >/dev/null 2>&1; then
    echo "⏳ Reloading Hammerspoon..."
    if command -v hs &>/dev/null; then
        hs -c "hs.reload()" 2>/dev/null || true
    else
        osascript -e 'tell application "Hammerspoon" to execute lua code "hs.reload()"' 2>/dev/null || true
    fi
    echo "✅ Hammerspoon reloaded"
fi

echo ""
echo "Done. SSO watcher removed. Hammerspoon itself was not uninstalled."
