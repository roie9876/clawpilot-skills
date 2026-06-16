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

# --- CRM Tools: clone/link and transpile MCAPS-IQ dependency ---
CRM_TOOLS_DIR="$TARGET_DIR/msx-crm/crm-tools"
MCAPS_IQ_DIR="$CRM_TOOLS_DIR/lib/mcaps-iq"
MCAPS_MSX_DIR="$MCAPS_IQ_DIR/mcp/msx-mcp-server"

if [ -d "$CRM_TOOLS_DIR" ]; then
    if [ -d "$MCAPS_IQ_DIR" ]; then
        echo "  ✓  MCAPS-IQ library already present"
    elif [ -d "$HOME/MCAPS-IQ/.git" ]; then
        mkdir -p "$CRM_TOOLS_DIR/lib"
        ln -sfn "$HOME/MCAPS-IQ" "$MCAPS_IQ_DIR"
        echo "  ✓  MCAPS-IQ library linked from ~/MCAPS-IQ"
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

    if [ -d "$MCAPS_MSX_DIR" ]; then
        if [ -f "$MCAPS_MSX_DIR/dist/auth.js" ] && [ -f "$MCAPS_MSX_DIR/dist/crm.js" ] && [ -f "$MCAPS_MSX_DIR/dist/validation.js" ]; then
            echo "  ✓  MCAPS-IQ MSX modules already built"
        elif command -v esbuild >/dev/null 2>&1; then
            echo "  ⏳ Transpiling MCAPS-IQ MSX modules..."
            (cd "$MCAPS_MSX_DIR" && mkdir -p dist && esbuild src/auth.ts src/crm.ts src/validation.ts --outdir=dist --format=esm --platform=node --target=node22 >/dev/null)
            echo "  ✓  MCAPS-IQ MSX modules transpiled"
        elif [ -x "$MCAPS_IQ_DIR/node_modules/.bin/esbuild" ]; then
            echo "  ⏳ Transpiling MCAPS-IQ MSX modules..."
            (cd "$MCAPS_MSX_DIR" && mkdir -p dist && "$MCAPS_IQ_DIR/node_modules/.bin/esbuild" src/auth.ts src/crm.ts src/validation.ts --outdir=dist --format=esm --platform=node --target=node22 >/dev/null)
            echo "  ✓  MCAPS-IQ MSX modules transpiled"
        else
            echo "  ⚠  MCAPS-IQ found, but MSX modules are not built."
            echo "     Install esbuild or build MCAPS-IQ, then run:"
            echo "     cd $MCAPS_MSX_DIR && esbuild src/auth.ts src/crm.ts src/validation.ts --outdir=dist --format=esm --platform=node --target=node22"
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
