#!/usr/bin/env bash
# install.sh — Symlink all customer skills into ~/.copilot/skills/
#
# Usage:
#   bash scripts/install.sh
#   # or from the repo root:
#   bash scripts/install.sh
#
# This script is idempotent — safe to run multiple times.

set -euo pipefail

# OS guard: warn if running on Windows native (cmd/PowerShell). Git Bash and WSL
# report 'msys'/'cygwin'/'linux' which work fine here.
case "${OSTYPE:-unknown}" in
    darwin*|linux*|msys*|cygwin*)
        ;;
    *)
        echo "Warning: unrecognized OS ($OSTYPE)."
        echo "On Windows native, use 'pwsh scripts/install.ps1' instead."
        ;;
esac

SKILLS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TARGET_DIR="$HOME/.copilot/skills"
SKILLS=(meeting-prep customer-repo capture-meeting followups azure-answer architecture connect crm-activity-sync daily-activity-log msx-crm sso-watcher)

echo "Customer Skills Installer"
echo "========================="
echo ""
echo "Source: $SKILLS_DIR"
echo "Target: $TARGET_DIR"
echo ""

# Create target directory if it doesn't exist
if [ ! -d "$TARGET_DIR" ]; then
    echo "Creating $TARGET_DIR ..."
    mkdir -p "$TARGET_DIR"
fi

installed=0
skipped=0
updated=0

for skill in "${SKILLS[@]}"; do
    src="$SKILLS_DIR/$skill"
    dest="$TARGET_DIR/$skill"

    if [ ! -d "$src" ]; then
        echo "  ⚠  $skill — source directory not found, skipping"
        skipped=$((skipped + 1))
        continue
    fi

    if [ -L "$dest" ]; then
        current_target="$(readlink "$dest")"
        if [ "$current_target" = "$src" ]; then
            echo "  ✓  $skill — already linked"
            skipped=$((skipped + 1))
            continue
        else
            echo "  ↻  $skill — updating symlink (was: $current_target)"
            ln -sfn "$src" "$dest"
            updated=$((updated + 1))
            continue
        fi
    elif [ -e "$dest" ]; then
        echo "  ⚠  $skill — $dest exists but is not a symlink, skipping"
        skipped=$((skipped + 1))
        continue
    fi

    ln -sfn "$src" "$dest"
    echo "  ✓  $skill — linked"
    installed=$((installed + 1))
done

echo ""
echo "Done: $installed installed, $updated updated, $skipped skipped"
echo ""

# --- CRM Tools: clone MCAPS-IQ dependency ---
CRM_TOOLS_DIR="$TARGET_DIR/msx-crm/crm-tools"
MCAPS_IQ_DIR="$CRM_TOOLS_DIR/lib/mcaps-iq"

if [ -d "$CRM_TOOLS_DIR" ]; then
    if [ -d "$MCAPS_IQ_DIR" ]; then
        echo "  ✓  MCAPS-IQ library already present"
    else
        echo "  ⏳ Cloning MCAPS-IQ library for CRM tools..."
        mkdir -p "$CRM_TOOLS_DIR/lib"
        if git clone --quiet https://github.com/yingding/MCAPS-IQ.git "$MCAPS_IQ_DIR" 2>/dev/null; then
            echo "  ✓  MCAPS-IQ library cloned"
        else
            echo "  ⚠  Failed to clone MCAPS-IQ. CRM tools will not work until you run:"
            echo "     git clone https://github.com/yingding/MCAPS-IQ.git $MCAPS_IQ_DIR"
        fi
    fi
fi

echo ""
echo "Next steps:"
echo "  1. Add the Draw.io MCP server in Clawpilot settings:"
echo "     URL: https://mcp.draw.io/mcp"
echo "  2. (Optional) Install Azure CLI and run 'az login' for /azure-answer"
echo "  3. Run '/customer-repo <name>' to set up your first customer folder"
echo "  4. Connect to VPN and run: node ~/.copilot/skills/msx-crm/crm-tools/run-tool.mjs crm_whoami"
