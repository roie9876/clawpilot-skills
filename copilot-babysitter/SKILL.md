# Copilot Babysitter Skill

## Purpose
Monitor the VS Code GitHub Copilot Agent and automatically nudge it to continue
when it stalls, stops reporting progress, or waits unnecessarily for user input.

**Key capability**: Works through macOS screen  no need to keep the screen unlocked.lock 

## Setup (One-Time)

### Prerequisites
- macOS
- VS Code with GitHub Copilot extension
- Clawpilot (for automation scheduling)

### Install the copilot-nudge-server Extension

The babysitter relies on a small VS Code extension that runs an HTTP server inside VS Code's
extension host process. This allows sending messages to Copilot Chat  evenprogrammatically 
when the screen is locked.

**Install steps:**

1. Copy the extension to VS Code's extensions folder:
   ```bash
   mkdir -p ~/.vscode/extensions/copilot-nudge-server-0.0.1
   cp extension/extension.js ~/.vscode/extensions/copilot-nudge-server-0.0.1/
   cp extension/package.json ~/.vscode/extensions/copilot-nudge-server-0.0.1/
   ```

 "Developer: Reload Window")

3. Verify the extension is running:
   ```bash
   curl -s http://127.0.0.1:19876/health
   # Expected: {"status":"ok","port":19876,"version":2}
   ```

**Why this works through screen lock:**
- The extension runs as a Node.js HTTP server inside VS Code's extension host process
- It uses internal VS Code commands (`workbench.action.chat. no keyboard/UI injectionopen`) 
- The HTTP server stays active regardless of display sleep or screen lock state
- Messages are queued by Copilot when the agent is busy; processed in order when ready

### Register the Automation in Clawpilot

Create a Clawpilot automation that runs every 2 minutes:
- Name: "Copilot Agent Monitor"
- Schedule: "every 2 minutes"
- Prompt: (see the automation prompt template in this skill)

## Architecture (Clawpilot Automation Mode)

The babysitter runs as a Clawpilot automation (every 2 minutes). Each run:

1. **Check  `stat -f "%m"` on the session file vs current timestaleness** 
2. **If active (< no action needed, report OK90s)** 
3. **If stalled (> diagnose and nudge:90s)** 
   a. Try HTTP nudge first (works through screen lock)
   b. If HTTP fails, check screen lock status
   c. Read session context for what agent was doing
   d. Determine if agent needs nudge or hit real blocker
   e. Send contextual nudge OR alert Roie via Teams
4. **Post-nudge  60s after nudge, re-check timestamp changedverification** 

## Screen Lock Handling

**Problem**: When macOS screen is locked, all UI automation (osascript keystrokes) silently
 text goes to the lock screen password field. osascript still returns exit 0.fails 

**Solution**: The HTTP nudge bypasses this entirely. The decision tree is:

```
1. Try HTTP nudge (curl POST to :19876)
 done (works through screen lock!)

      2. Check screen lock (ioreg)
 Teams alert only, cannot nudge via UI
 try UI nudge (osascript fallback)
```

**Screen lock detection:**
```bash
ioreg -n Root -d1 -w0 | grep -q '"IOConsoleLocked" = Yes'
# Exit 0 = screen IS locked, Exit 1 = screen is unlocked
```

## Nudge Methods

### PRIMARY: HTTP (Non-UI, Works Through Screen Lock)

```bash
curl -s -X POST http://127.0.0.1:19876/nudge \
  -H "Content-Type: application/json" \
  -d '{"message": "YOUR_MESSAGE"}'
```

**Health check** (verify extension is running):
```bash
curl -s http://127.0.0.1:19876/health
# Returns: {"status":"ok","port":19876,"version":2}
```

**File-based alternative** (if HTTP unreachable):
```bash
echo 'YOUR_MESSAGE' > ~/.copilot/nudge-queue.txt
```
The extension polls this file every 2 seconds.

### FALLBACK: UI (Only When HTTP Fails AND Screen Unlocked)

```applescript
tell application "Code" to activate
delay 0.5
tell application "System Events"
    tell process "Code"
        key code 35 using {command down, shift down}  -- Cmd+Shift+P
        delay 0.5
        keystroke "chat focus input"
        delay 0.3
        keystroke return
        delay 0.4
        keystroke "YOUR_MESSAGE_HERE"
        delay 0.2
        keystroke return
    end tell
end tell
```

## Session File Monitoring

**Target session** (update these for your workspace):
- Workspace hash: `680f52b117f3c92a8c4998a69b70dacc`
- Session ID: `3df56667-99c5-4383-ac30-7acb02f89aa9`
- Full path: `~/Library/Application Support/Code/User/workspaceStorage/{hash}/chatSessions/{sessionId}.jsonl`

**Staleness check**:
```bash
stat -f "%m" "$SESSION_FILE" && date +%s
 stalled
```

## Auto-Nudge Policy

1. **First stall detection**: Read context, send contextual nudge
2. **Second consecutive stall** (nudge didn't work): Try again with different message
3. **Third consecutive stall**: Alert Roie via  "Agent not responding to nudges"Teams 
4. **After 5 failed nudges**: Stop trying, send Teams alert, wait for manual intervention

If the agent says a deploy, test, or background command is still running, do not
blindly nudge it. Wait for `LONG_RUNNING_GRACE` (default 30 minutes), then ask it
to check progress and continue waiting if the operation is still healthy.

**Nudge messages should be  read what the agent was doing and tell it what to do next. Examples:contextual** 
- "The 99.1% pass rate is acceptable. Continue with lifecycle tests."
- "Continue with the next  node drain."test 
- "Yes, proceed with that approach."

Do NOT just send " the agent responds better to specific instructions.continue" 

## Teams Status Updates

Send Roie a brief status update every 3rd run (~6 minutes):
- 1-2 lines max
- What the agent is currently doing
- Any issues detected

## Helper Tools

### supervisor.py (status/read)
```bash
python3 ~/.copilot/skills/copilot-babysitter/supervisor.py status
python3 ~/.copilot/skills/copilot-babysitter/supervisor.py read 3
```

**Known issues**:
- Can crash on NoneType (line 323) if context  handle gracefullyempty 
- The session file may be very  use the header for quick readslarge 

## Requirements

| Component | Purpose | Required? |
|-----------|---------|-----------|
| copilot-nudge-server extension | HTTP nudge (primary) | **Yes** |
| Accessibility permissions | UI fallback only | No (if HTTP works) |
| macOS `ioreg` | Screen lock detection | Yes |
| Clawpilot automation | Scheduling | Yes |

## Known Limitations

- If VS Code crashes or reloads, extension reactivates automatically on next startup
- Session file can be very large ( too big to parse last line efficiently300MB+) 
- osascript returns exit 0 even when keystrokes fail (UI fallback only)
- Extension uses port 19876; if port is taken it tries 19877

## Extension Source

The extension source is in `extension/` in this repo. See `extension/extension.js` and
`extension/package.json`.
