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

SKILLS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TARGET_DIR="$HOME/.copilot/skills"
SKILLS=(meeting-prep customer-repo capture-meeting followups azure-answer architecture)

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

# Reminder about MCP server
echo "Next steps:"
echo "  1. Add the Draw.io MCP server in Clawpilot settings:"
echo "     URL: https://mcp.draw.io/mcp"
echo "  2. (Optional) Install Azure CLI and run 'az login' for /azure-answer"
echo "  3. Run '/customer-repo <name>' to set up your first customer folder"
