#!/bin/bash
# Copilot Babysitter - monitors VS Code Copilot Agent and nudges it to continue
# when it stalls or waits for user input.
#
# Detection: Takes periodic screenshots of the Copilot panel area,
# compares pixel diffs. If no change for STALL_THRESHOLD seconds = stalled.
# Action: Sends "continue" to the Copilot chat input via keyboard.
#
# Dependencies: screencapture (macOS built-in), sips (macOS built-in)
# Usage: ./babysitter.sh [start|stop|status|nudge|test]

set -euo pipefail

# Configuration (override via environment)
CHECK_INTERVAL=${CHECK_INTERVAL:-10}          # seconds between checks
STALL_THRESHOLD=${STALL_THRESHOLD:-45}        # seconds of no change = stalled
NUDGE_MESSAGE=${NUDGE_MESSAGE:-"continue"}    # what to type when stalled
MAX_NUDGES=${MAX_NUDGES:-5}                   # max consecutive nudges before backing off
COOLDOWN_AFTER_NUDGE=${COOLDOWN_AFTER_NUDGE:-30}  # wait after nudging before rechecking
LOG_FILE="${HOME}/.copilot/copilot-babysitter.log"
PID_FILE="${HOME}/.copilot/copilot-babysitter.pid"
STATE_DIR="${HOME}/.copilot/copilot-babysitter-state"

# Panel capture region — right side where Copilot Chat panel lives
# Override these based on your monitor layout
PANEL_X=${PANEL_X:-1270}
PANEL_Y=${PANEL_Y:-80}
PANEL_W=${PANEL_W:-650}
PANEL_H=${PANEL_H:-650}

mkdir -p "$STATE_DIR" "$(dirname "$LOG_FILE")"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

is_vscode_running() {
    pgrep -x "Code" > /dev/null 2>&1
}

capture_panel() {
    local output="$1"
    screencapture -x -R "${PANEL_X},${PANEL_Y},${PANEL_W},${PANEL_H}" "$output" 2>/dev/null
}

# Compare two images — returns 0 if same (stalled), 1 if different (active)
images_are_same() {
    local img1="$1" img2="$2"
    [[ -f "$img1" ]] && [[ -f "$img2" ]] || return 1
    
    # Downscale for fast comparison
    local thumb1="${STATE_DIR}/thumb1.png" thumb2="${STATE_DIR}/thumb2.png"
    sips -z 100 150 "$img1" --out "$thumb1" > /dev/null 2>&1
    sips -z 100 150 "$img2" --out "$thumb2" > /dev/null 2>&1
    
    local hash1 hash2
    hash1=$(md5 -q "$thumb1" 2>/dev/null)
    hash2=$(md5 -q "$thumb2" 2>/dev/null)
    [[ "$hash1" == "$hash2" ]]
}

# Detect animation (spinner) by taking 2 rapid captures
detect_spinner() {
    local cap1="${STATE_DIR}/spin1.png" cap2="${STATE_DIR}/spin2.png"
    capture_panel "$cap1"
    sleep 1.5
    capture_panel "$cap2"
    ! images_are_same "$cap1" "$cap2"
}

# Send message to Copilot Chat via Command Palette (layout-independent)
nudge_copilot() {
    local message="${1:-$NUDGE_MESSAGE}"
    log "NUDGE: Sending '$message' to Copilot Chat"
    
    osascript <<EOF
tell application "Code" to activate
delay 0.5
tell application "System Events"
    tell process "Code"
        -- Open Command Palette (Cmd+Shift+P)
        key code 35 using {command down, shift down}
        delay 0.5
        -- Type command to focus chat input
        keystroke "chat focus input"
        delay 0.3
        keystroke return
        delay 0.4
        -- Type our message and send
        keystroke "${message}"
        delay 0.2
        keystroke return
    end tell
end tell
EOF
    log "NUDGE: Sent"
}

# Main loop
monitor_loop() {
    local consecutive_same=0
    local nudge_count=0
    local last_capture="${STATE_DIR}/last.png"
    local current_capture="${STATE_DIR}/current.png"
    
    log "=== Copilot Babysitter started (interval=${CHECK_INTERVAL}s, threshold=${STALL_THRESHOLD}s) ==="
    
    is_vscode_running && capture_panel "$last_capture"
    
    while true; do
        sleep "$CHECK_INTERVAL"
        
        if ! is_vscode_running; then
            consecutive_same=0; nudge_count=0; continue
        fi
        
        capture_panel "$current_capture"
        
        if images_are_same "$last_capture" "$current_capture"; then
            consecutive_same=$((consecutive_same + CHECK_INTERVAL))
            
            if [[ $consecutive_same -ge $STALL_THRESHOLD ]]; then
                # Double-check: is there a spinner animation?
                if detect_spinner; then
                    log "Animation detected — agent still working, resetting"
                    consecutive_same=0
                else
                    if [[ $nudge_count -lt $MAX_NUDGES ]]; then
                        nudge_count=$((nudge_count + 1))
                        log "⚠️  STALL (${consecutive_same}s static, nudge #${nudge_count}/${MAX_NUDGES})"
                        nudge_copilot
                        consecutive_same=0
                        sleep "$COOLDOWN_AFTER_NUDGE"
                        capture_panel "$last_capture"
                    else
                        log "🛑 Max nudges reached. Backing off 5 minutes."
                        sleep 300
                        nudge_count=0; consecutive_same=0
                        capture_panel "$last_capture"
                    fi
                fi
            fi
        else
            # Activity! Reset everything.
            consecutive_same=0; nudge_count=0
            cp "$current_capture" "$last_capture"
        fi
    done
}

# --- Commands ---
case "${1:-help}" in
    start)
        if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
            echo "Already running (PID: $(cat "$PID_FILE"))"
            exit 0
        fi
        monitor_loop &
        echo $! > "$PID_FILE"
        echo "✅ Copilot Babysitter started (PID: $!)"
        ;;
    stop)
        if [[ -f "$PID_FILE" ]]; then
            pid=$(cat "$PID_FILE")
            kill "$pid" 2>/dev/null && log "Stopped (PID: $pid)" && echo "⏹️  Stopped"
            rm -f "$PID_FILE"
        else
            echo "Not running"
        fi
        ;;
    status)
        if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
            echo "✅ Running (PID: $(cat "$PID_FILE"))"
            tail -5 "$LOG_FILE" 2>/dev/null
        else
            echo "⏹️  Not running"
        fi
        ;;
    nudge)
        nudge_copilot "${2:-continue}"
        ;;
    test)
        echo "Testing Copilot Babysitter..."
        is_vscode_running && echo "✅ VS Code running" || { echo "❌ VS Code not running"; exit 1; }
        
        echo "Capturing panel..."
        capture_panel "${STATE_DIR}/test1.png"
        sleep 3
        capture_panel "${STATE_DIR}/test2.png"
        
        if images_are_same "${STATE_DIR}/test1.png" "${STATE_DIR}/test2.png"; then
            echo "📸 Panel is STATIC (potential stall)"
        else
            echo "📸 Panel is ACTIVE (agent working)"
        fi
        
        if detect_spinner; then
            echo "🔄 Animation detected — agent is thinking"
        else
            echo "⏸️  No animation — agent may be idle"
        fi
        ;;
    help|*)
        echo "Copilot Babysitter — nudges stalled VS Code Copilot agents"
        echo ""
        echo "Usage: $(basename "$0") {start|stop|status|nudge [msg]|test}"
        echo ""
        echo "Config (env vars):"
        echo "  CHECK_INTERVAL=$CHECK_INTERVAL    (seconds between checks)"
        echo "  STALL_THRESHOLD=$STALL_THRESHOLD   (seconds before nudging)"
        echo "  NUDGE_MESSAGE=$NUDGE_MESSAGE  (message to send)"
        echo "  MAX_NUDGES=$MAX_NUDGES         (max before backing off)"
        echo "  PANEL_X=$PANEL_X PANEL_Y=$PANEL_Y PANEL_W=$PANEL_W PANEL_H=$PANEL_H (capture region)"
        ;;
esac
