# install.ps1 — Symlink all customer skills into $HOME\.copilot\skills\
#
# Usage (PowerShell on Windows):
#   pwsh scripts\install.ps1
#   # or:
#   powershell -ExecutionPolicy Bypass -File scripts\install.ps1
#
# Idempotent — safe to run multiple times.
#
# NOTE: Creating symlinks on Windows requires either:
#   1. Running PowerShell as Administrator, OR
#   2. Enabling Developer Mode (Settings → For developers → Developer Mode → On)
# This script will detect the failure and print a clear error if neither is set.

$ErrorActionPreference = 'Stop'

$SkillsDir = Resolve-Path (Join-Path $PSScriptRoot '..')
$TargetDir = Join-Path $HOME '.copilot\skills'
$Skills = @(
    'meeting-prep',
    'customer-repo',
    'capture-meeting',
    'followups',
    'azure-answer',
    'architecture',
    'connect',
    'crm-activity-sync',
    'daily-activity-log',
    'msx-crm'
)

Write-Host "Customer Skills Installer (Windows)"
Write-Host "===================================="
Write-Host ""
Write-Host "Source: $SkillsDir"
Write-Host "Target: $TargetDir"
Write-Host ""

if (-not (Test-Path $TargetDir)) {
    Write-Host "Creating $TargetDir ..."
    New-Item -ItemType Directory -Force -Path $TargetDir | Out-Null
}

$installed = 0
$skipped = 0
$updated = 0
$failed = 0

foreach ($skill in $Skills) {
    $src = Join-Path $SkillsDir $skill
    $dest = Join-Path $TargetDir $skill

    if (-not (Test-Path $src -PathType Container)) {
        Write-Host "  !  $skill - source directory not found, skipping"
        $skipped++
        continue
    }

    if (Test-Path $dest) {
        $item = Get-Item $dest -Force
        if ($item.LinkType -eq 'SymbolicLink') {
            if ($item.Target -eq $src -or $item.Target -contains $src) {
                Write-Host "  =  $skill - already linked"
                $skipped++
                continue
            } else {
                Write-Host "  ~  $skill - updating symlink (was: $($item.Target))"
                Remove-Item $dest -Force
                # fall through to create
            }
        } else {
            Write-Host "  !  $skill - $dest exists but is not a symlink, skipping"
            $skipped++
            continue
        }
    }

    try {
        New-Item -ItemType SymbolicLink -Path $dest -Target $src -ErrorAction Stop | Out-Null
        if (Test-Path $dest) {
            Write-Host "  +  $skill - linked"
            $installed++
        }
    } catch {
        Write-Host "  X  $skill - failed to create symlink: $($_.Exception.Message)" -ForegroundColor Red
        $failed++
    }
}

Write-Host ""
Write-Host "Done: $installed installed, $updated updated, $skipped skipped, $failed failed"
Write-Host ""

if ($failed -gt 0) {
    Write-Host "Symlink creation failed. On Windows, you need ONE of:" -ForegroundColor Yellow
    Write-Host "  1. Run PowerShell as Administrator and re-run this script, OR"
    Write-Host "  2. Enable Developer Mode: Settings -> For developers -> Developer Mode -> On"
    Write-Host ""
    Write-Host "Alternative: use 'mklink /D' from an Administrator cmd.exe shell."
    exit 1
}

Write-Host "Next steps:"
Write-Host "  1. Add the Draw.io MCP server in Clawpilot settings:"
Write-Host "     URL: https://mcp.draw.io/mcp"
Write-Host "  2. (Optional) Install Azure CLI for /azure-answer:"
Write-Host "     winget install Microsoft.AzureCLI && az login"
Write-Host "  3. Run '/customer-repo <name>' in Clawpilot to set up your first customer folder"
