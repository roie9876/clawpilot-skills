# Prerequisite Auto-Install (shared reference)

All skills in this repository can auto-install their sibling dependencies when invoked.
This document defines the shared procedure. Each skill's SKILL.md includes a
"Prerequisite Auto-Install" section that references this pattern with skill-specific
dependency lists.

## How It Works

When a user invokes any skill (e.g., `/crm-activity-sync`), the skill's Step 0 checks
whether all required sibling skills are installed. If any are missing, it automatically
clones this repository and runs the install script — which symlinks ALL skills in one go.

This means **any skill can be the entry point**. The user only needs to install one skill
manually; all dependencies are pulled in automatically.

## The Auto-Install Procedure

### 1. Check if sibling skills are installed

Each skill lists its required siblings. Check each one:

**macOS / Linux (bash):**
```bash
REQUIRED_SKILLS="customer-repo daily-activity-log crm-activity-sync msx-crm"
MISSING=""
for skill in $REQUIRED_SKILLS; do
  if [ ! -f "$HOME/.copilot/skills/$skill/SKILL.md" ]; then
    MISSING="$MISSING $skill"
  fi
done
if [ -n "$MISSING" ]; then
  echo "Missing skills:$MISSING"
fi
```

**Windows (PowerShell):**
```powershell
$requiredSkills = @('customer-repo','daily-activity-log','crm-activity-sync','msx-crm')
$missing = $requiredSkills | Where-Object {
    -not (Test-Path "$HOME\.copilot\skills\$_\SKILL.md")
}
if ($missing) { Write-Host "Missing skills: $($missing -join ', ')" }
```

### 2. Clone the repo (if not already cloned)

**macOS / Linux:**
```bash
if [ ! -d "$HOME/customer-skills/.git" ]; then
    git clone https://github.com/roie9876/clawpilot-skills.git "$HOME/customer-skills"
fi
```

**Windows:**
```powershell
if (-not (Test-Path "$HOME\customer-skills\.git")) {
    git clone https://github.com/roie9876/clawpilot-skills.git "$HOME\customer-skills"
}
```

### 3. Run the installer

The installer symlinks all skill directories into `$HOME/.copilot/skills/`. It is
idempotent — safe to run multiple times.

**macOS / Linux:**
```bash
bash "$HOME/customer-skills/scripts/install.sh"
```

**Windows:**
```powershell
pwsh "$HOME\customer-skills\scripts\install.ps1"
```

> **Windows note:** Symlink creation requires either Administrator privileges or
> Developer Mode enabled (Settings → For developers → Developer Mode → On).

### 4. Verify

After installation, re-check that the required skills are present. If any are still
missing, report the error and stop.

## Tool Prerequisites

Skills may also require system tools. The standard checks:

| Tool | Check (POSIX) | Check (Windows) | Install (macOS) | Install (Windows) |
|------|---------------|-----------------|-----------------|-------------------|
| git | `git --version` | `Get-Command git` | `brew install git` | `winget install Git.Git` |
| Node.js | `node --version` | `Get-Command node` | `brew install node` | `winget install OpenJS.NodeJS` |
| Azure CLI | `az version` | `az version` | `brew install azure-cli` | `winget install Microsoft.AzureCLI` |

After installing any tool, verify it works before proceeding.

## CRM Tool Script (`run-tool.mjs`)

CRM-dependent skills require `$HOME/Documents/crm-tools/run-tool.mjs`.

If missing, clone the repository:

```bash
# macOS / Linux
git clone https://github.com/roie9876/crm-tools.git "$HOME/Documents/crm-tools"
cd "$HOME/Documents/crm-tools"
```

```powershell
# Windows
git clone https://github.com/roie9876/crm-tools.git "$HOME\Documents\crm-tools"
Set-Location "$HOME\Documents\crm-tools"; npm install
```

## VPN Connection

CRM is only accessible on Microsoft corpnet.

**macOS / Linux:** Use `$HOME/Scripts/ensure-vpn.sh` if it exists. If not, ask the user
to connect to Azure VPN Client manually.

**Windows:** No automated VPN script. Ask the user to confirm Azure VPN Client is
connected before proceeding.

## M365 Sign-In

Call `m_m365_status`. If not signed in → call `m_m365_sign_in`.

## Skills ↔ Dependencies Map

```
┌──────────────────┐
│  customer-repo   │ ← Foundation (no dependencies)
└────────┬─────────┘
         │
    ┌────┴────────────────────────────────────────┐
    │                                              │
    ▼                                              ▼
┌──────────────────┐                    ┌──────────────────┐
│ meeting-prep     │                    │ daily-activity-log│
│ capture-meeting  │                    │ (+ crm-activity-  │
│ followups        │                    │  sync config)     │
│ architecture     │                    └────────┬─────────┘
│ connect          │                             │
└──────────────────┘                             ▼
                                       ┌──────────────────┐
                                       │ crm-activity-sync│
                                       │ (+ msx-crm)      │
                                       └──────────────────┘
```

Independent skills (no sibling dependencies):
- `azure-answer` — optional `az` CLI
- `msx-crm` — Node.js + CRM tools
