# Copilot Babysitter Skill

## Purpose
Monitor the VS Code GitHub Copilot Agent and automatically nudge it to continue
when it stalls, stops reporting progress, or waits unnecessarily for user input.

## How It Works

1. **Screenshot-based detection**: Takes periodic screenshots of the Copilot Chat panel
2. **Stall detection**: If the panel doesn't change for 45 seconds (configurable), it's stalled
3. **Spinner check**: Before nudging, verifies there's no animation (which means agent is still thinking)
4. **Nudge action**: Sends "continue" to the Copilot Chat input via keyboard shortcuts
5. **Backoff**: After 5 consecutive nudges, backs off for 5 minutes

## Usage

### Start babysitter
```bash
~/.copilot/skills/copilot-babysitter/babysitter.sh start
```

### Stop babysitter
```bash
~/.copilot/skills/copilot-babysitter/babysitter.sh stop
```

### Check status
```bash
~/.copilot/skills/copilot-babysitter/babysitter.sh status
```

### Test detection (without nudging)
```bash
~/.copilot/skills/copilot-babysitter/babysitter.sh test
```

### Manual nudge
```bash
~/.copilot/skills/copilot-babysitter/babysitter.sh nudge "please continue working"
```

## Configuration

Set via environment variables before starting:

| Variable | Default | Description |
|----------|---------|-------------|
| `CHECK_INTERVAL` | 10 | Seconds between screenshot checks |
| `STALL_THRESHOLD` | 45 | Seconds of no change before nudging |
| `NUDGE_MESSAGE` | "continue" | Message sent to Copilot |
| `MAX_NUDGES` | 5 | Max consecutive nudges before backing off |
| `COOLDOWN_AFTER_NUDGE` | 30 | Seconds to wait after each nudge |
| `PANEL_X` | 1020 | X coordinate of panel capture region |
| `PANEL_Y` | 80 | Y coordinate of panel capture region |
| `PANEL_W` | 900 | Width of capture region |
| `PANEL_H` | 600 | Height of capture region |

## Panel Region Calibration

The default coordinates assume the Copilot Chat panel is on the right side of a 1920px wide display.
To calibrate for your setup:

1. Run `babysitter.sh test` — this captures the panel
2. Check `~/.copilot/copilot-babysitter-state/test1.png` to see what's being captured
3. Adjust `PANEL_X`, `PANEL_Y`, `PANEL_W`, `PANEL_H` as needed

## Logs

All activity is logged to `~/.copilot/copilot-babysitter.log`

## Requirements

- macOS (uses `screencapture`, `sips`, `osascript`)
- VS Code with GitHub Copilot extension
- Accessibility permissions for Terminal/Clawpilot (System Settings → Privacy → Accessibility)

## Known Limitations

- Only works when VS Code window is on the screen (can be behind other windows but not minimized)
- Screenshot comparison is pixel-based — changing themes or resizing panels needs recalibration
- The Ctrl+L shortcut must be mapped to "Focus Chat Input" in VS Code (default in Copilot)
- Doesn't distinguish between "agent asking a real question" vs "agent just paused" — it always sends "continue"

## Future Improvements

- [ ] Smart detection: OCR the last message to decide if it's a real question vs idle
- [ ] VS Code extension approach: A tiny extension that exposes agent state via a file/socket
- [ ] Multiple nudge strategies: "continue" for idle, "yes" for confirmations, "skip" for blockers
