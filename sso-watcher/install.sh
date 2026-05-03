#!/usr/bin/env bash
# install.sh — Install the Hammerspoon SSO auto-picker on macOS
#
# Usage:
#   bash install.sh                           # interactive — prompts for email
#   bash install.sh user@microsoft.com        # non-interactive
#   bash install.sh user@microsoft.com MyApp  # custom app name (default: Clawpilot)
#
# What it does:
#   1. Installs Hammerspoon via Homebrew (if missing)
#   2. Copies sso-watcher.lua to ~/.hammerspoon/
#   3. Creates/updates config (~/.hammerspoon/sso-watcher-config.lua)
#   4. Adds require("sso-watcher") to ~/.hammerspoon/init.lua
#   5. Enables IPC in init.lua (for `hs` CLI)
#   6. Enables Hammerspoon auto-launch at login
#   7. Reloads Hammerspoon config
#   8. Prints TCC permission instructions
#
# Idempotent — safe to run multiple times.

set -euo pipefail

# ─── macOS guard ─────────────────────────────────────────────────────
if [ "$(uname)" != "Darwin" ]; then
    echo "❌ This skill is macOS-only (Hammerspoon requires macOS)."
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HS_DIR="$HOME/.hammerspoon"
LUA_MODULE="sso-watcher.lua"
CONFIG_FILE="sso-watcher-config.lua"
INIT_FILE="$HS_DIR/init.lua"
LOG_DIR="$HOME/Scripts"

# ─── Parse arguments ─────────────────────────────────────────────────
ACCOUNT="${1:-}"
APP_NAME="${2:-Clawpilot}"

if [ -z "$ACCOUNT" ]; then
    # Try to read from existing config
    if [ -f "$HS_DIR/$CONFIG_FILE" ]; then
        EXISTING=$(grep 'account' "$HS_DIR/$CONFIG_FILE" | head -1 | sed 's/.*"\(.*\)".*/\1/')
        if [ -n "$EXISTING" ]; then
            echo "Found existing account: $EXISTING"
            read -r -p "Use this account? [Y/n] " yn
            case "$yn" in
                [nN]*) ;;
                *) ACCOUNT="$EXISTING" ;;
            esac
        fi
    fi
fi

if [ -z "$ACCOUNT" ]; then
    read -r -p "Enter your Microsoft account email (e.g. alias@microsoft.com): " ACCOUNT
fi

if [ -z "$ACCOUNT" ]; then
    echo "❌ Account email is required."
    exit 1
fi

echo ""
echo "SSO Watcher Installer"
echo "====================="
echo "  Account:  $ACCOUNT"
echo "  App:      $APP_NAME"
echo "  Target:   $HS_DIR"
echo ""

# ─── Step 1: Install Hammerspoon ─────────────────────────────────────
if [ -d "/Applications/Hammerspoon.app" ] || [ -d "$HOME/Applications/Hammerspoon.app" ]; then
    echo "✅ Hammerspoon already installed"
else
    echo "⏳ Installing Hammerspoon via Homebrew..."
    if ! command -v brew &>/dev/null; then
        echo "❌ Homebrew not found. Install Hammerspoon manually from https://www.hammerspoon.org/"
        echo "   Or install Homebrew first: https://brew.sh"
        exit 1
    fi
    brew install --cask hammerspoon
    echo "✅ Hammerspoon installed"
fi

# ─── Step 2: Create ~/.hammerspoon/ ──────────────────────────────────
mkdir -p "$HS_DIR"
mkdir -p "$LOG_DIR"

# ─── Step 3: Copy Lua module ─────────────────────────────────────────
cp "$SCRIPT_DIR/$LUA_MODULE" "$HS_DIR/$LUA_MODULE"
echo "✅ Copied $LUA_MODULE → $HS_DIR/"

# ─── Step 4: Write config ────────────────────────────────────────────
cat > "$HS_DIR/$CONFIG_FILE" << EOF
-- SSO Watcher Configuration
-- Edit this file to change the target account or app.
return {
    account       = "$ACCOUNT",
    app_name      = "$APP_NAME",
    poll_interval = 3,
    cooldown      = 15,
    log_file      = os.getenv("HOME") .. "/Scripts/sso-watcher-hammerspoon.log",
}
EOF
echo "✅ Config written → $HS_DIR/$CONFIG_FILE"

# ─── Step 5: Update init.lua ─────────────────────────────────────────
touch "$INIT_FILE"

# Ensure IPC is required (needed for `hs` CLI)
if ! grep -q 'require("hs.ipc")' "$INIT_FILE" 2>/dev/null; then
    # Prepend IPC require
    TEMP=$(mktemp)
    echo 'require("hs.ipc")' > "$TEMP"
    echo '' >> "$TEMP"
    cat "$INIT_FILE" >> "$TEMP"
    mv "$TEMP" "$INIT_FILE"
    echo "✅ Added hs.ipc to init.lua"
else
    echo "✅ hs.ipc already in init.lua"
fi

# Ensure sso-watcher is required
if ! grep -q 'require("sso-watcher")' "$INIT_FILE" 2>/dev/null; then
    echo '' >> "$INIT_FILE"
    echo '-- SSO auto-picker (installed by sso-watcher skill)' >> "$INIT_FILE"
    echo 'require("sso-watcher")' >> "$INIT_FILE"
    echo "✅ Added require(\"sso-watcher\") to init.lua"
else
    echo "✅ sso-watcher already required in init.lua"
fi

# ─── Step 6: Enable auto-launch at login ─────────────────────────────
HS_APP=""
if [ -d "/Applications/Hammerspoon.app" ]; then
    HS_APP="/Applications/Hammerspoon.app"
elif [ -d "$HOME/Applications/Hammerspoon.app" ]; then
    HS_APP="$HOME/Applications/Hammerspoon.app"
fi

if [ -n "$HS_APP" ]; then
    # Use osascript to add login item (works on macOS 13+)
    osascript -e "
        tell application \"System Events\"
            if not (exists login item \"Hammerspoon\") then
                make login item at end with properties {path:\"$HS_APP\", hidden:false}
            end if
        end tell
    " 2>/dev/null && echo "✅ Hammerspoon set to auto-launch at login" \
                  || echo "⚠️  Could not set auto-launch — add Hammerspoon manually in System Settings → General → Login Items"
fi

# ─── Step 7: Launch / Reload Hammerspoon ──────────────────────────────
if pgrep -x "Hammerspoon" >/dev/null 2>&1; then
    echo "⏳ Reloading Hammerspoon config..."
    # Try IPC first, fall back to AppleScript
    if command -v hs &>/dev/null; then
        hs -c "hs.reload()" 2>/dev/null || true
    else
        osascript -e 'tell application "Hammerspoon" to execute lua code "hs.reload()"' 2>/dev/null || true
    fi
    sleep 2
    echo "✅ Hammerspoon reloaded"
else
    echo "⏳ Launching Hammerspoon..."
    open -a Hammerspoon
    sleep 3
    echo "✅ Hammerspoon launched"
fi

# ─── Step 8: Verify ──────────────────────────────────────────────────
echo ""
if pgrep -x "Hammerspoon" >/dev/null 2>&1; then
    echo "✅ Hammerspoon is running (PID $(pgrep -x Hammerspoon))"
else
    echo "⚠️  Hammerspoon does not appear to be running"
fi

if [ -f "$HOME/Scripts/sso-watcher-hammerspoon.log" ]; then
    LAST_LOG=$(tail -1 "$HOME/Scripts/sso-watcher-hammerspoon.log" 2>/dev/null || true)
    echo "✅ Log active: $LAST_LOG"
fi

# ─── Step 9: TCC permissions guidance ────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "⚠️  IMPORTANT: macOS Permissions Required"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Hammerspoon needs Accessibility access to detect and click"
echo "the SSO dialog. Grant it in:"
echo ""
echo "  System Settings → Privacy & Security → Accessibility"
echo "  → Toggle ON: Hammerspoon"
echo ""
echo "If you see a prompt from macOS, click 'Open System Settings'"
echo "and enable it there."
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Done! The SSO picker will be auto-dismissed for: $ACCOUNT"
echo "Log: ~/Scripts/sso-watcher-hammerspoon.log"
