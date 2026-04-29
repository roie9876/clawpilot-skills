# Platform Compatibility Guide (shared)

All customer skills must work on **macOS**, **Linux**, and **Windows**. This file is
the single source of truth for cross-platform shell-command translation.

## OS detection (do this first)

Before running any shell command, detect the operating system:

- **From a tool / Node / Python**: read the `process.platform` (`darwin`, `linux`, `win32`)
  or `os.name` value.
- **From a terminal**:
  - In **bash / zsh** (macOS, Linux, WSL, Git Bash): `echo "$OSTYPE"` →
    `darwin*`, `linux*`, `msys`/`cygwin` (Git Bash on Windows).
  - In **PowerShell** (Windows native): `$IsWindows` is `$true`. Also `$PSVersionTable.Platform`.
- **Quick heuristic**: if `uname` succeeds → POSIX (macOS / Linux / WSL / Git Bash).
  If it returns "command not found" or fails → likely Windows cmd / PowerShell.

If the OS cannot be determined, default to POSIX commands and fall back to
PowerShell on failure.

## Command translation table

| Purpose | macOS / Linux / WSL / Git Bash (bash) | Windows PowerShell |
|---------|---------------------------------------|--------------------|
| Home dir | `~` or `$HOME` | `$HOME` (PowerShell) or `$env:USERPROFILE` |
| Make dir (recursive, idempotent) | `mkdir -p X` | `New-Item -ItemType Directory -Force -Path X \| Out-Null` |
| List dir | `ls X` | `Get-ChildItem X` |
| Copy recursively | `cp -r A B` | `Copy-Item -Recurse A B` |
| Move / rename | `mv A B` | `Move-Item A B` |
| Delete recursively | `rm -rf X` | `Remove-Item -Recurse -Force X` |
| Make file executable | `chmod +x file` | (no-op on Windows; skip) |
| Find executable on PATH | `which X` | `Get-Command X` |
| Open file in default app | `open file` | `Invoke-Item file` |
| Open file in specific app | `open -a "App" file` | `Start-Process "App" file` |
| Open URL in browser | `open https://x` | `Start-Process https://x` |
| Read env var | `$VAR` | `$env:VAR` |
| Conditional test | `[ -f file ]` | `Test-Path file` |
| Pipe to clipboard | `pbcopy` | `Set-Clipboard` |
| Read from clipboard | `pbpaste` | `Get-Clipboard` |
| Run script | `bash scripts/x.sh` | `pwsh scripts/x.ps1` (or `powershell` on Windows PowerShell 5) |

## Path conventions

- **Always prefer `$HOME` over `~`** in scripts that may run on Windows PowerShell —
  `~` is supported in PowerShell but `$HOME` is unambiguous.
- Use **forward slashes `/`** in paths when possible. Both bash and PowerShell
  accept them. Avoid hard-coded backslashes.
- Avoid hard-coded macOS paths like `/opt/homebrew/bin/...` or
  `/Users/<name>/...`. Instead resolve via `which` / `Get-Command`, or use
  `$HOME`.

## Browser-opening (specific to skills that auto-open output)

Skills that open generated HTML in a browser (e.g. `meeting-prep`,
`capture-meeting`) should use this pattern:

**macOS / Linux**:
```bash
# macOS — open in Microsoft Edge if installed, else default browser
if [ "$(uname)" = "Darwin" ]; then
  open -a "Microsoft Edge" "$file" 2>/dev/null || open "$file"
else
  xdg-open "$file" 2>/dev/null || true
fi
```

**Windows (PowerShell)**:
```powershell
# Try Edge by name; fall back to default browser
try {
    Start-Process "msedge.exe" $file -ErrorAction Stop
} catch {
    Invoke-Item $file
}
```

## App-specific binaries

| App | macOS | Linux | Windows |
|-----|-------|-------|---------|
| Microsoft Edge | `open -a "Microsoft Edge"` | `microsoft-edge` (if installed) | `msedge.exe` (on PATH after install) |
| Node.js | `node` (PATH) or `/opt/homebrew/bin/node` (Homebrew) | `node` (PATH) | `node.exe` (PATH after `winget install OpenJS.NodeJS`) |
| Git | `git` | `git` | `git.exe` (PATH after Git for Windows install) |

**Rule**: never hard-code `/opt/homebrew/bin/node`. Always resolve via `which node`
(POSIX) or `Get-Command node` (PowerShell), and only fall back to absolute paths
when the user has explicitly told the skill where the binary is.

## Installer scripts

The repo provides two installer scripts that do the same job:

- `scripts/install.sh` — bash (macOS / Linux / WSL / Git Bash)
- `scripts/install.ps1` — PowerShell (Windows native)

On Windows, symlink creation requires either Administrator privileges or
Developer Mode enabled (Settings → For developers → Developer Mode). The
PowerShell installer detects this and prints clear instructions if it cannot
create symlinks.

## Skill-author checklist

When adding shell commands to a SKILL.md:

1. ☐ Show the bash version in a `bash` code block.
2. ☐ If the command differs on Windows, show the PowerShell version in a
   `powershell` code block immediately after.
3. ☐ Use `$HOME` not `~` whenever the command might run in PowerShell.
4. ☐ Never hard-code `/opt/homebrew/...`, `/usr/local/...`, or
   `C:\Users\...` — resolve dynamically.
5. ☐ For "open in browser" steps, use the `try-Edge-then-fall-back` pattern
   above.
