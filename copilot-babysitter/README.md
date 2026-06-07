---
name: copilot-babysitter
description: "Monitor VS Code GitHub Copilot Agent and automatically nudge it to continue when it stalls. Reads agent conversation from session files, detects stalls, understands context, and either nudges the agent or escalates to you via Teams. Triggers include: 'copilot babysitter', 'monitor copilot', 'babysit agent', 'watch copilot', 'copilot stalled', 'keep copilot going', or any request to monitor the VS Code Copilot agent session."
---

# /copilot- VS Code Copilot Agent Supervisorbabysitter 

Smart supervisor for VS Code GitHub Copilot Agent. Monitors the agent session
via its local JSONL state files, detects when it stalls, reads full conversation
context (user messages, tool calls, agent responses), and takes intelligent action:
nudge, wait, or escalate to the user.

## Platform Compatibility

| Platform | Status | Notes |
|----------|--------|-------|
| **macOS Full support | Primary platform. Uses `screencapture`, `osascript`, `sips`, Vision framework OCR |** | 
| ** Partial | Session file reading works. Keystroke injection needs AutoHotkey or PowerShell `SendKeys`. Screenshot fallback needs adaptation. |Windows** | 
| ** Partial | Session file reading works. Keystroke injection needs `xdotool`. Screenshot needs `scrot` or `gnome-screenshot`. |Linux** | 

## Prerequisites

### All platforms
- **VS Code** with GitHub Copilot Chat extension installed
- **Python 3.9+** (for `supervisor.py`)
- **Clawpilot** (for automation and Teams notifications)

### macOS specific
- **Accessibility  Clawpilot (or Terminal) must have Accessibility access:permissions** 
 Add your terminal app
- **Xcode Command Line  for compiling the OCR tool (optional):Tools** 
  ```bash
  xcode-select --install
  ```

### Windows specific (for keyboard injection)
- **AutoHotkey  for sending keystrokes to VS Codev2** 
  ```powershell
  winget install AutoHotkey.AutoHotkey
  ```
- Or use PowerShell `[System.Windows.Forms.SendKeys]`

### Linux specific (for keyboard injection)
- ** for sending keystrokes to VS Codexdotool** 
  ```bash
  sudo apt install xdotool  # Debian/Ubuntu
  ```

## Installation

### 1. Copy files to Clawpilot skills directory

```bash
# macOS / Linux
cp -r copilot-babysitter/ ~/.copilot/skills/copilot-babysitter/
chmod +x ~/.copilot/skills/copilot-babysitter/babysitter.sh

# Windows (PowerShell)
Copy-Item -Recurse copilot-babysitter/ "$HOME/.copilot/skills/copilot-babysitter/"
```

### 2. Compile OCR tool (macOS only,  for screenshot fallback)optional 

```bash
swiftc ~/.copilot/skills/copilot-babysitter/ocr-tool.swift \
  -o ~/.copilot/skills/copilot-babysitter/ocr-tool \
  -framework Vision -framework AppKit
```

### 3. Calibrate panel coordinates (for screenshot fallback)

Run the test command and check the captured image:

```bash
~/.copilot/skills/copilot-babysitter/babysitter.sh test
open ~/.copilot/copilot-babysitter-state/test1.png
```

Adjust `PANEL_X`, `PANEL_Y`, `PANEL_W`, `PANEL_H` in environment if the capture
doesn't show the Copilot Chat panel.

### 4. Calibrate click coordinates (for keyboard injection)

The default click target `{1100, 689}` assumes the Copilot Chat input is at the
bottom-right of a 19201080 display. To find your coordinates:

1. Open VS Code with Copilot Chat panel visible on the right
2. Hover over the "Describe what to build" input field
3. Use `cliclick p` (macOS) or similar tool to get pixel coordinates
4. Update the `click at` coordinates in the automation prompt

## How It Works

### Primary approach: Session file reading

VS Code stores Copilot agent conversations in JSONL files at:

```
# macOS
~/Library/Application Support/Code/User/workspaceStorage/{hash}/chatSessions/{id}.jsonl

# Windows
%APPDATA%/Code/User/workspaceStorage/{hash}/chatSessions/{id}.jsonl

# Linux
~/.config/Code/User/workspaceStorage/{hash}/chatSessions/{id}.jsonl
```

The supervisor:
1. Finds the most recently modified `.jsonl` session file
2. Watches for file modification time changes
 reads the file to understand context
4. Decides: nudge (type into chat), wait (agent thinking), or escalate (Teams msg)

### Session file format

```
Line 1: Full session state JSON (title, all requests with messages + responses)
Lines 2+: Incremental updates (new tool outputs, responses, token counts)
```

Key data accessible:
-  User messages (verbatim)
-  Agent text responses (items with no `kind` field, just `value`)
-  Tool invocations (commands, file reads, search results)
-  Agent state (complete, waiting_confirmation, error)
 Chain of thought (encrypted by GitHub)- 

### Fallback: Screenshot + OCR

If file reading is insufficient (e.g., need to see visual state):
1. `screencapture` captures the Copilot panel region
2. macOS Vision framework OCR extracts text
3. Text is analyzed for agent state

## Usage

```bash
# Show current Copilot agent status
python3 ~/.copilot/skills/copilot-babysitter/supervisor.py status

# Read last N conversation exchanges  
python3 ~/.copilot/skills/copilot-babysitter/supervisor.py read 10

# Dump current context as JSON (for Clawpilot automation)
python3 ~/.copilot/skills/copilot-babysitter/supervisor.py context

# Start monitoring (foreground)
python3 ~/.copilot/skills/copilot-babysitter/supervisor.py monitor

# Screenshot-based babysitter (simpler, macOS only)
~/.copilot/skills/copilot-babysitter/babysitter.sh start|stop|status|test|nudge
```

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `STALL_THRESHOLD` | 60 | Seconds of no change before acting |
| `CHECK_INTERVAL` | 15 | Seconds between checks |
| `MAX_NUDGES` | 5 | Max consecutive nudges before backing off |
| `NUDGE_MESSAGE` | "continue" | Default message (overridden by smart logic) |

## Clawpilot Automation

Best used as a Clawpilot automation (every 2 minutes). The automation:
1. Checks if agent is stalled
2. Reads full conversation context to understand the mission
3. Reads the workspace folder for additional context
4. Sends an intelligent, contextual  not just "continue"message 
5. Notifies user via Teams on progress or blockers

## Logs

- Supervisor: `~/.copilot/copilot-supervisor.log`
- Babysitter (screenshot): `~/.copilot/copilot-babysitter.log`

## Known Limitations

- **Chain of thought is  can't read the agent's reasoning, only its outputsencrypted** 
- **Click coordinates are display- need calibration per monitor setupspecific** 
- **Can't distinguish "needs real answer" from "just  Clawpilot AI reasoning helps but isn't perfectpaused"** 
- **VS Code must not be  for screenshot fallback (file reading works regardless)minimized** 
- **Single active  monitors the most recently modified session onlysession** 

## Future Improvements

- [ ] VS Code extension that exposes agent state via a local file/socket (no scraping needed)
- [ ] Windows AutoHotkey integration for keyboard injection
- [ ] Linux xdotool integration
- [ ] Multi-session support (watch all active sessions)
- [ ] Learn from user behavior (when they say "continue" vs give specific guidance)
