#!/usr/bin/env python3
"""
Copilot Smart Supervisor - reads VS Code Copilot agent sessions,
detects stalls, and provides intelligent responses via Clawpilot.

Architecture:
1. Watches the active JSONL session file for modifications
2. When no new writes for STALL_THRESHOLD seconds → reads session state
3. Analyzes: what was the user's mission? what did the agent last do? why might it be stuck?
4. Outputs a recommendation for Clawpilot to act on (or sends directly via keyboard)

The session file location:
~/Library/Application Support/Code/User/workspaceStorage/{workspace-hash}/chatSessions/{session-id}.jsonl
"""

import json
import os
import sys
import time
import subprocess
import urllib.error
import urllib.request
from pathlib import Path
from datetime import datetime

# --- Configuration ---
STALL_THRESHOLD = int(os.environ.get("STALL_THRESHOLD", "60"))  # seconds
CHECK_INTERVAL = int(os.environ.get("CHECK_INTERVAL", "15"))    # seconds
MAX_NUDGES = int(os.environ.get("MAX_NUDGES", "5"))
NUDGE_PORTS = [int(p) for p in os.environ.get("NUDGE_PORTS", "19876,19877").split(",") if p.strip()]
WORKSPACE_STORAGE = Path.home() / "Library/Application Support/Code/User/workspaceStorage"
LOG_FILE = Path.home() / ".copilot/copilot-supervisor.log"
STATE_FILE = Path.home() / ".copilot/copilot-supervisor-state.json"
NUDGE_QUEUE_FILE = Path.home() / ".copilot/nudge-queue.txt"
BLOCKER_PHRASES = (
    "before editing, let me confirm",
    "please confirm",
    "need your confirmation",
    "waiting for your confirmation",
    "waiting for approval",
    "approve a tool",
    "manual input",
)

def text_value(value):
    if isinstance(value, dict):
        return str(value.get("value") or "")
    return str(value or "")

def log(msg):
    ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    line = f"[{ts}] {msg}"
    print(line)
    with open(LOG_FILE, "a") as f:
        f.write(line + "\n")

def find_active_session():
    """Find the most recently modified .jsonl session file across all workspaces."""
    best = None
    best_mtime = 0
    
    for ws_dir in WORKSPACE_STORAGE.iterdir():
        sessions_dir = ws_dir / "chatSessions"
        if not sessions_dir.exists():
            continue
        for f in sessions_dir.glob("*.jsonl"):
            mtime = f.stat().st_mtime
            if mtime > best_mtime:
                best_mtime = mtime
                best = f
    
    return best, best_mtime

def read_session_context(session_file: Path):
    """Read the session file and extract the current context."""
    context = {
        "session_title": None,
        "total_requests": 0,
        "last_user_message": None,
        "last_user_message_idx": None,
        "recent_tool_calls": [],
        "agent_state": "unknown",  # working, stalled, waiting_confirmation, blocked
        "last_response_text": [],
    }
    
    # Read the header (first line) which contains the full session state
    with open(session_file, "r") as f:
        first_line = f.readline().strip()
    
    if not first_line:
        return context
    
    try:
        header = json.loads(first_line)
        session_data = header.get("v", {})
        context["session_title"] = session_data.get("customTitle", "Untitled")
        requests = session_data.get("requests", [])
        context["total_requests"] = len(requests)
        
        # Find last user message
        for i in range(len(requests) - 1, -1, -1):
            req = requests[i]
            msg = req.get("message", {})
            if isinstance(msg, dict) and msg.get("text"):
                context["last_user_message"] = msg["text"]
                context["last_user_message_idx"] = i
                break
        
        # Get the latest request's response
        if requests:
            last_req = requests[-1]
            resp = last_req.get("response", [])
            context["request_in_progress"] = last_req.get("result") is None
            
            for item in resp:
                if not isinstance(item, dict):
                    continue
                kind = item.get("kind", "")

                item_text = text_value(item.get("value"))
                if item_text:
                    context["last_response_text"].append(item_text)
                
                if kind == "toolInvocationSerialized":
                    inv_msg_obj = item.get("invocationMessage", {})
                    inv_msg = text_value(inv_msg_obj)
                    is_complete = item.get("isComplete", False)
                    is_confirmed = item.get("isConfirmed")
                    
                    tool_info = {
                        "message": inv_msg[:200],
                        "complete": is_complete,
                        "needs_confirmation": is_confirmed is False,
                    }
                    context["recent_tool_calls"].append(tool_info)
            
            # Check result for the last request
            result = last_req.get("result", {})
            if isinstance(result, dict):
                # Check for error
                if result.get("errorDetails"):
                    context["agent_state"] = "error"
                    context["error"] = str(result["errorDetails"])[:500]
    
    except (json.JSONDecodeError, KeyError, TypeError) as e:
        log(f"Error parsing session: {e}")
    
    # Also read the tail of the file for incremental updates
    try:
        result = subprocess.run(
            ["tail", "-50", str(session_file)],
            capture_output=True, text=True
        )
        for line in result.stdout.strip().split("\n"):
            if not line.strip():
                continue
            try:
                obj = json.loads(line)
                k = obj.get("k", [])
                v = obj.get("v")
                
                # Check for tool confirmations needed
                if isinstance(v, list):
                    for item in v:
                        if isinstance(item, dict) and item.get("kind") == "toolInvocationSerialized":
                            if item.get("isConfirmed") is False:
                                context["agent_state"] = "waiting_confirmation"
            except json.JSONDecodeError:
                continue
    except Exception:
        pass
    
    return context

def determine_action(context, stall_duration):
    """Determine what action to take based on the agent's state and context."""
    
    state = context.get("agent_state", "unknown")
    last_msg = context.get("last_user_message") or ""
    tools = context.get("recent_tool_calls", [])
    response_text = "\n".join(context.get("last_response_text", []))
    response_text_lc = response_text.lower()
    
    # If agent hit an error
    if state == "error":
        return {
            "action": "escalate",
            "reason": f"Agent hit an error: {context.get('error', 'unknown')[:200]}",
            "suggestion": None,
        }
    
    # If waiting for tool confirmation
    if state == "waiting_confirmation":
        pending = [t for t in tools if t.get("needs_confirmation")]
        if pending:
            return {
                "action": "approve",
                "reason": f"Agent needs tool approval: {pending[-1]['message'][:100]}",
                "suggestion": "The agent is waiting for you to approve a tool execution.",
            }

    if any(phrase in response_text_lc for phrase in BLOCKER_PHRASES):
        return {
            "action": "approve",
            "reason": "Agent appears to be asking for user input or confirmation.",
            "suggestion": summarize_blocker(response_text),
        }
    
    # Agent seems stalled (no activity for STALL_THRESHOLD)
    # Analyze the context to determine best response
    if tools:
        last_tool = tools[-1]
        if not last_tool.get("complete"):
            return {
                "action": "wait",
                "reason": "Last tool call may still be running",
                "suggestion": None,
            }

    if context.get("request_in_progress"):
        return {
            "action": "wait",
            "reason": "Latest Copilot request is still in progress",
            "suggestion": None,
        }
    
    # Agent finished its work and is idle — check if it completed the user's mission
    # or if it stopped midway
    return {
        "action": "nudge",
        "reason": f"Agent stalled for {stall_duration}s after user asked: '{last_msg[:100]}'",
        "suggestion": generate_nudge_message(context),
    }

def generate_nudge_message(context):
    """Generate an intelligent nudge message based on context."""
    last_msg = context.get("last_user_message") or ""
    title = context.get("session_title", "")
    tools = context.get("recent_tool_calls", [])
    
    response_text = "\n".join(context.get("last_response_text", []))
    for line in response_text.splitlines():
        stripped = line.strip()
        if stripped:
            return f"Continue from your last step: {stripped[:180]}"

    # If agent ran commands, likely it's done with a step and needs to continue
    if tools and all(t.get("complete") for t in tools[-3:]):
        return "continue with the next step"
    
    # Generic but contextual
    return "continue"

def summarize_blocker(response_text):
    for line in response_text.splitlines():
        stripped = line.strip()
        if stripped:
            return f"Agent may need input: {stripped[:180]}"
    return "Agent is waiting for manual input or confirmation."

def send_http_nudge(message):
    """Send a nudge through the VS Code extension HTTP server."""
    payload = json.dumps({"message": message}).encode("utf-8")
    headers = {"Content-Type": "application/json"}
    last_error = None

    for port in NUDGE_PORTS:
        request = urllib.request.Request(
            f"http://127.0.0.1:{port}/nudge",
            data=payload,
            headers=headers,
            method="POST",
        )
        try:
            with urllib.request.urlopen(request, timeout=3) as response:
                body = response.read().decode("utf-8", errors="replace")
                log(f"HTTP NUDGE SENT on port {port}: {body[:200]}")
                return True
        except (OSError, urllib.error.URLError, urllib.error.HTTPError) as e:
            last_error = e

    log(f"HTTP NUDGE FAILED: {last_error}")
    return False

def queue_file_nudge(message):
    """Queue a nudge for the VS Code extension's file watcher."""
    NUDGE_QUEUE_FILE.write_text(message, encoding="utf-8")
    log(f"FILE NUDGE QUEUED: {NUDGE_QUEUE_FILE}")

def is_screen_locked():
    result = subprocess.run(
        ["ioreg", "-n", "Root", "-d1", "-w0"],
        capture_output=True,
        text=True,
    )
    return '"IOConsoleLocked" = Yes' in result.stdout

def send_ui_nudge(message):
    """Send a message to VS Code Copilot chat via Command Palette (layout-independent)."""
    escaped_message = message.replace("\\", "\\\\").replace('"', '\\"')
    script = f'''
tell application "Code" to activate
delay 0.5
tell application "System Events"
    tell process "Code"
        -- Open Command Palette (Cmd+Shift+P)
        key code 35 using {{command down, shift down}}
        delay 0.5
        -- Type command to focus chat input
        keystroke "chat focus input"
        delay 0.3
        keystroke return
        delay 0.4
        -- Type message and send
        keystroke "{escaped_message}"
        delay 0.2
        keystroke return
    end tell
end tell
'''
    subprocess.run(["osascript", "-e", script], capture_output=True)
    log(f"UI NUDGE SENT: '{message}'")

def send_nudge(message):
    """Send a nudge using the most reliable available path."""
    if send_http_nudge(message):
        return "http"

    queue_file_nudge(message)

    if is_screen_locked():
        log("Screen is locked; queued file nudge and skipped UI fallback")
        return "file"

    send_ui_nudge(message)
    return "ui"

def save_state(state):
    with open(STATE_FILE, "w") as f:
        json.dump(state, f, indent=2)

def load_state():
    if STATE_FILE.exists():
        with open(STATE_FILE) as f:
            return json.load(f)
    return {"nudge_count": 0, "last_nudge_time": 0, "last_mtime": 0}

def monitor():
    """Main monitoring loop."""
    log("=== Copilot Smart Supervisor started ===")
    log(f"Config: stall_threshold={STALL_THRESHOLD}s, check_interval={CHECK_INTERVAL}s")
    
    state = load_state()
    last_activity_time = time.time()
    last_mtime = state.get("last_mtime", 0)
    nudge_count = state.get("nudge_count", 0)
    
    while True:
        time.sleep(CHECK_INTERVAL)
        
        # Find active session
        session_file, current_mtime = find_active_session()
        if not session_file:
            continue
        
        # Check if file has been modified
        if current_mtime > last_mtime:
            # Activity detected
            last_activity_time = time.time()
            last_mtime = current_mtime
            nudge_count = 0  # Reset nudge count on new activity
            save_state({"nudge_count": 0, "last_nudge_time": 0, "last_mtime": current_mtime})
            continue
        
        # No change — calculate stall duration
        stall_duration = time.time() - last_activity_time
        
        if stall_duration >= STALL_THRESHOLD:
            if nudge_count >= MAX_NUDGES:
                log(f"Max nudges ({MAX_NUDGES}) reached. Backing off 5 min.")
                time.sleep(300)
                nudge_count = 0
                last_activity_time = time.time()
                continue
            
            # Read context and decide
            log(f"STALL detected ({stall_duration:.0f}s). Reading session context...")
            context = read_session_context(session_file)
            action = determine_action(context, stall_duration)
            
            log(f"  Session: {context.get('session_title')}")
            log(f"  Last user msg: {(context.get('last_user_message') or 'N/A')[:100]}")
            log(f"  Agent state: {context.get('agent_state')}")
            log(f"  Decision: {action['action']} — {action['reason'][:150]}")
            
            if action["action"] == "nudge" and action.get("suggestion"):
                nudge_count += 1
                send_nudge(action["suggestion"])
                last_activity_time = time.time()
                save_state({"nudge_count": nudge_count, "last_nudge_time": time.time(), "last_mtime": last_mtime})
                # Cooldown
                time.sleep(30)
            elif action["action"] == "approve":
                log(f"  ⚠️ NEEDS HUMAN: {action['suggestion']}")
                # TODO: Send notification to Clawpilot/Teams
            elif action["action"] == "escalate":
                log(f"  🛑 ESCALATION: {action['reason']}")
                # TODO: Send notification
            elif action["action"] == "wait":
                log(f"  ⏳ Waiting — tool still running")
                last_activity_time = time.time()  # Give it more time

def check_once():
    """Run one monitor check for scheduled automation."""
    session_file, current_mtime = find_active_session()
    if not session_file:
        print(json.dumps({"status": "no_session"}, indent=2))
        return

    state = load_state()
    last_mtime = state.get("last_mtime", 0)
    nudge_count = state.get("nudge_count", 0)
    age = time.time() - current_mtime
    context = read_session_context(session_file)
    action = determine_action(context, int(age))

    result = {
        "status": "stalled",
        "session_file": str(session_file),
        "last_modified_ago_seconds": age,
        "session_title": context.get("session_title"),
        "last_user_message": context.get("last_user_message"),
        "agent_state": context.get("agent_state"),
        "action": action,
        "nudge_count": nudge_count,
    }

    # VS Code can update the session file when it renders Copilot's "Continue?"
    # gate. Treat that gate as actionable even when the file is still fresh.
    if context.get("agent_state") == "waiting_confirmation":
        if action["action"] == "nudge" and action.get("suggestion"):
            if nudge_count >= MAX_NUDGES:
                result["status"] = "max_nudges_reached"
                result["message"] = "Manual intervention required."
            else:
                path = send_nudge(action["suggestion"])
                nudge_count += 1
                save_state({
                    "nudge_count": nudge_count,
                    "last_nudge_time": time.time(),
                    "last_mtime": current_mtime,
                })
                result["status"] = "nudged"
                result["nudge_path"] = path
                result["nudge_count"] = nudge_count
                if nudge_count >= 3:
                    result["status"] = "repeated_nudges"
                    result["message"] = "Agent has been nudged repeatedly without confirmed progress."
            print(json.dumps(result, indent=2))
            return

        if action["action"] == "approve":
            result["status"] = "needs_approval"
            result["message"] = action.get("suggestion") or "Agent is waiting for manual approval."
            print(json.dumps(result, indent=2))
            return

    if age < STALL_THRESHOLD and current_mtime > last_mtime:
        save_state({"nudge_count": 0, "last_nudge_time": 0, "last_mtime": current_mtime})
        print(json.dumps({
            "status": "active",
            "session_file": str(session_file),
            "last_modified_ago_seconds": age,
        }, indent=2))
        return

    if age < STALL_THRESHOLD:
        print(json.dumps({
            "status": "recent",
            "session_file": str(session_file),
            "last_modified_ago_seconds": age,
            "nudge_count": nudge_count,
        }, indent=2))
        return

    if action["action"] == "nudge" and action.get("suggestion"):
        if nudge_count >= MAX_NUDGES:
            result["status"] = "max_nudges_reached"
            result["message"] = "Manual intervention required."
        else:
            path = send_nudge(action["suggestion"])
            nudge_count += 1
            save_state({
                "nudge_count": nudge_count,
                "last_nudge_time": time.time(),
                "last_mtime": current_mtime,
            })
            result["status"] = "nudged"
            result["nudge_path"] = path
            result["nudge_count"] = nudge_count
            if nudge_count >= 3:
                result["status"] = "repeated_nudges"
                result["message"] = "Agent has been nudged repeatedly without confirmed progress."
    elif action["action"] == "approve":
        result["status"] = "needs_approval"
        result["message"] = action.get("suggestion") or "Agent is waiting for manual approval."
    elif action["action"] == "escalate":
        result["status"] = "error"
        result["message"] = action.get("reason") or "Agent requires manual intervention."
    elif action["action"] == "wait":
        save_state({"nudge_count": nudge_count, "last_nudge_time": state.get("last_nudge_time", 0), "last_mtime": current_mtime})
        result["status"] = "wait"

    print(json.dumps(result, indent=2))

def status():
    """Show current status."""
    session_file, mtime = find_active_session()
    if not session_file:
        print("No active Copilot session found")
        return
    
    age = time.time() - mtime
    context = read_session_context(session_file)
    
    print(f"📁 Active session: {session_file.name}")
    print(f"📋 Title: {context.get('session_title')}")
    print(f"📊 Requests: {context.get('total_requests')}")
    print(f"⏱️  Last modified: {age:.0f}s ago")
    print(f"💬 Last user msg: {(context.get('last_user_message') or 'N/A')[:100]}")
    print(f"🔧 Recent tools: {len(context.get('recent_tool_calls', []))}")
    print(f"🔄 Agent state: {context.get('agent_state')}")
    
    state = load_state()
    print(f"🔔 Nudge count: {state.get('nudge_count', 0)}")

def read_conversation(n=10):
    """Read the last N exchanges from the active session."""
    session_file, _ = find_active_session()
    if not session_file:
        print("No active session found")
        return
    
    with open(session_file, "r") as f:
        first_line = f.readline().strip()
    
    header = json.loads(first_line)
    requests = header.get("v", {}).get("requests", [])
    
    print(f"Session: {header['v'].get('customTitle', 'Untitled')}")
    print(f"Total exchanges: {len(requests)}")
    print(f"Showing last {min(n, len(requests))}:\n")
    
    for req in requests[-n:]:
        msg = req.get("message", {})
        if isinstance(msg, dict) and msg.get("text"):
            print(f"👤 USER: {msg['text'][:500]}")
        
        # Show response summary
        resp = req.get("response", [])
        text_parts = []
        tool_count = 0
        for item in resp:
            if isinstance(item, dict):
                if item.get("kind") == "toolInvocationSerialized":
                    tool_count += 1
                # Other text content could be here
        
        if tool_count:
            print(f"🤖 AGENT: [{tool_count} tool calls]")
        
        result = req.get("result", {})
        if isinstance(result, dict) and result.get("metadata", {}).get("renderedUserMessage"):
            pass  # skip internal
        print("---")

if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "help"
    
    if cmd == "monitor":
        monitor()
    elif cmd == "status":
        status()
    elif cmd == "read":
        n = int(sys.argv[2]) if len(sys.argv) > 2 else 10
        read_conversation(n)
    elif cmd == "context":
        # Dump full context for the current session (used by Clawpilot)
        session_file, mtime = find_active_session()
        if session_file:
            context = read_session_context(session_file)
            context["file"] = str(session_file)
            context["last_modified_ago_seconds"] = time.time() - mtime
            print(json.dumps(context, indent=2))
    elif cmd == "once":
        check_once()
    elif cmd == "help":
        print("""Copilot Smart Supervisor

Usage:
  python3 supervisor.py monitor   — Start monitoring (foreground)
  python3 supervisor.py once      — Run one scheduled check and nudge if stalled
  python3 supervisor.py status    — Show current session status
  python3 supervisor.py read [N]  — Read last N conversation exchanges
  python3 supervisor.py context   — Dump current session context as JSON
  python3 supervisor.py help      — Show this help

Environment:
  STALL_THRESHOLD=60   Seconds before considering agent stalled
  CHECK_INTERVAL=15    Seconds between checks
  MAX_NUDGES=5         Max nudges before backing off
""")
    else:
        print(f"Unknown command: {cmd}")
        sys.exit(1)
