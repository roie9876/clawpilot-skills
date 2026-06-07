# Copilot Babysitter

Smart supervisor for VS Code GitHub Copilot Agent. Monitors the agent session, detects stalls, reads conversation context, and sends intelligent nudges.

## Setup

1. Copy files to `~/.copilot/skills/copilot-babysitter/`
2. Compile the OCR tool (optional, for screenshot fallback):
   ```bash
   swiftc ocr-tool.swift -o ~/.copilot/skills/copilot-babysitter/ocr-tool -framework Vision -framework AppKit
   ```
3. Register in Clawpilot as `/copilot-babysitter`

## Files

- `supervisor. Smart Python supervisor (primary approach, reads session JSONL)py` 
- `babysitter. Simple screenshot-based fallbacksh` 
- `SKILL. Clawpilot skill instructionsmd` 
- `ocr-tool. Source for macOS Vision OCR tool (compile locally)swift` 

## How it works

See SKILL.md for full details.
