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
    'msx-crm',
    'sso-watcher'
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

# --- CRM Tools: clone/link and transpile MCAPS-IQ dependency ---
$CrmToolsDir = Join-Path $TargetDir 'msx-crm\crm-tools'
$McapsIqDir = Join-Path $CrmToolsDir 'lib\mcaps-iq'
$McapsMsxDir = Join-Path $McapsIqDir 'mcp\msx-mcp-server'

if (Test-Path $CrmToolsDir -PathType Container) {
    if (Test-Path $McapsIqDir -PathType Container) {
        Write-Host "  =  MCAPS-IQ library already present"
    } elseif (Test-Path "$HOME\MCAPS-IQ") {
        New-Item -ItemType Directory -Force -Path (Join-Path $CrmToolsDir 'lib') | Out-Null
        New-Item -ItemType SymbolicLink -Path $McapsIqDir -Target "$HOME\MCAPS-IQ" -Force | Out-Null
        Write-Host "  +  MCAPS-IQ library linked from ~/MCAPS-IQ"
    } elseif ($env:MCAPS_IQ_REPO_URL) {
        Write-Host "  ... Cloning MCAPS-IQ library for CRM tools from MCAPS_IQ_REPO_URL..."
        New-Item -ItemType Directory -Force -Path (Join-Path $CrmToolsDir 'lib') | Out-Null
        try {
            git clone --quiet $env:MCAPS_IQ_REPO_URL $McapsIqDir 2>$null
            Write-Host "  +  MCAPS-IQ library cloned"
        } catch {
            Write-Host "  !  Failed to clone MCAPS-IQ from MCAPS_IQ_REPO_URL." -ForegroundColor Yellow
            Write-Host "     Check access, or place MCAPS-IQ at ~/MCAPS-IQ and rerun this installer."
        }
    } else {
        Write-Host "  !  MCAPS-IQ not found. CRM tools won't work until you either:" -ForegroundColor Yellow
        Write-Host "     1. Place MCAPS-IQ at ~/MCAPS-IQ and rerun this installer, or"
        Write-Host "     2. Set MCAPS_IQ_REPO_URL to an authorized MCAPS-IQ repo URL and rerun."
    }

    if (Test-Path $McapsMsxDir -PathType Container) {
        $AuthJs = Join-Path $McapsMsxDir 'dist\auth.js'
        $CrmJs = Join-Path $McapsMsxDir 'dist\crm.js'
        $ValidationJs = Join-Path $McapsMsxDir 'dist\validation.js'
        if ((Test-Path $AuthJs) -and (Test-Path $CrmJs) -and (Test-Path $ValidationJs)) {
            Write-Host "  =  MCAPS-IQ MSX modules already built"
        } else {
            $Esbuild = Get-Command esbuild -ErrorAction SilentlyContinue
            $LocalEsbuild = Join-Path $McapsIqDir 'node_modules\.bin\esbuild.cmd'
            if ($Esbuild) {
                Write-Host "  ... Transpiling MCAPS-IQ MSX modules..."
                Push-Location $McapsMsxDir
                esbuild src/auth.ts src/crm.ts src/validation.ts --outdir=dist --format=esm --platform=node --target=node22 | Out-Null
                Pop-Location
                Write-Host "  +  MCAPS-IQ MSX modules transpiled"
            } elseif (Test-Path $LocalEsbuild) {
                Write-Host "  ... Transpiling MCAPS-IQ MSX modules..."
                Push-Location $McapsMsxDir
                & $LocalEsbuild src/auth.ts src/crm.ts src/validation.ts --outdir=dist --format=esm --platform=node --target=node22 | Out-Null
                Pop-Location
                Write-Host "  +  MCAPS-IQ MSX modules transpiled"
            } else {
                Write-Host "  !  MCAPS-IQ found, but MSX modules are not built." -ForegroundColor Yellow
                Write-Host "     Install esbuild or build MCAPS-IQ, then run:"
                Write-Host "     cd $McapsMsxDir; esbuild src/auth.ts src/crm.ts src/validation.ts --outdir=dist --format=esm --platform=node --target=node22"
            }
        }
    }
}

Write-Host ""
Write-Host "Next steps:"
Write-Host "  1. Add the Draw.io MCP server in Clawpilot settings:"
Write-Host "     URL: https://mcp.draw.io/mcp"
Write-Host "  2. (Optional) Install Azure CLI for /azure-answer:"
Write-Host "     winget install Microsoft.AzureCLI && az login"
Write-Host "  3. Run '/customer-repo <name>' in Clawpilot to set up your first customer folder"
Write-Host "  4. Connect to VPN and run: node $HOME\.copilot\skills\msx-crm\crm-tools\run-tool.mjs crm_whoami"
