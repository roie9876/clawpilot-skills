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
IN_PROGRESS_GRACE = int(os.environ.get("IN_PROGRESS_GRACE", "180"))
LONG_RUNNING_GRACE = int(os.environ.get("LONG_RUNNING_GRACE", "1800"))
ONLY_MESSAGE_ON_USER_INPUT = os.environ.get("ONLY_MESSAGE_ON_USER_INPUT", "1") != "0"
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
    "waiting for manual",
    "approve a tool",
    "manual input",
    "blocked on",
    "can't proceed",
    "cannot proceed",
    "need input",
)
LONG_RUNNING_PHRASES = (
    "background completion notification",
    "background command",
    "still running",
    "deploy is now running",
    "deployment is still running",
    "creating the dual-stack cluster",
    "cluster creation",
    "progressing normally",
    "will then add",
    "minutes more",
    "min more",
)
RETRYABLE_ERROR_PHRASES = (
    "network error",
    "connection error",
    "connection failed",
    "failed to connect",
    "could not connect",
    "connection reset",
    "connection timed out",
    "timeout",
    "timed out",
    "rate limit",
    "rate-limit",
    "rate limited",
    "too many requests",
    "quota exceeded",
    "request failed",
    "try again",
    "retry",
    "model provider",
    "model_provider",
    "provider error",
    "server error",
    "service unavailable",
    "temporarily unavailable",
    "internal server error",
    "bad gateway",
    "gateway timeout",
    "429",
    "502",
    "503",
    "504",
    "failed to send request",
    "failed to get response",
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

def ensure_list_size(items, index):
    while len(items) <= index:
        items.append({})

def set_nested_value(root, path, value):
    """Apply a VS Code JSONL path update into a dict/list tree."""
    current = root
    for i, part in enumerate(path):
        is_last = i == len(path) - 1
        if isinstance(current, list) and isinstance(part, int):
            ensure_list_size(current, part)
            if is_last:
                current[part] = value
                return
            if not isinstance(current[part], (dict, list)):
                current[part] = [] if isinstance(path[i + 1], int) else {}
            current = current[part]
            continue

        if isinstance(current, dict):
            if is_last:
                current[part] = value
                return
            if part not in current or not isinstance(current[part], (dict, list)):
                current[part] = [] if isinstance(path[i + 1], int) else {}
            current = current[part]
            continue

        return

def reconstruct_session_data(session_file: Path):
    """Read the header plus incremental JSONL updates into current session state."""
    with open(session_file, "r", encoding="utf-8", errors="replace") as f:
        first_line = f.readline().strip()
        if not first_line:
            return {}

        header = json.loads(first_line)
        session_data = header.get("v", {})
        if not isinstance(session_data, dict):
            return {}
        session_data.setdefault("requests", [])

        for line in f:
            if not line.strip():
                continue
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                continue

            path = obj.get("k")
            if not isinstance(path, list):
                continue

            value = obj.get("v")
            if path == ["requests"] and isinstance(value, list):
                session_data.setdefault("requests", [])
                session_data["requests"].extend(
                    req for req in value if isinstance(req, dict)
                )
                continue

            set_nested_value(session_data, path, value)

    return session_data

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
        "request_in_progress": False,
    }

    try:
        session_data = reconstruct_session_data(session_file)
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
                if item_text and kind not in ("thinking", "toolInvocationSerialized"):
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

    except (OSError, json.JSONDecodeError, KeyError, TypeError) as e:
        log(f"Error parsing session: {e}")

    return context

def determine_action(context, stall_duration):
    """Determine what action to take based on the agent's state and context."""
    
    state = context.get("agent_state", "unknown")
    last_msg = context.get("last_user_message") or ""
    tools = context.get("recent_tool_calls", [])
    response_text = "\n".join(context.get("last_response_text", []))
    response_text_lc = response_text.lower()
    error_text_lc = str(context.get("error", "")).lower()
    retryable_text_lc = f"{response_text_lc}\n{error_text_lc}"
    
    # If agent hit an error
    if state == "error":
        if any(phrase in retryable_text_lc for phrase in RETRYABLE_ERROR_PHRASES):
            return {
                "action": "nudge",
                "reason": "Agent hit a retryable network/rate-limit/model-provider error.",
                "suggestion": "Retry the failed step now. If the same network, rate-limit, or model-provider error repeats, wait briefly and retry once before asking for help.",
            }
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

    if any(phrase in retryable_text_lc for phrase in RETRYABLE_ERROR_PHRASES):
        return {
            "action": "nudge",
            "reason": "Agent appears stopped on a retryable network/rate-limit/model-provider error.",
            "suggestion": "Retry the failed step now. If the same network, rate-limit, or model-provider error repeats, wait briefly and retry once before asking for help.",
        }

    if any(phrase in response_text_lc for phrase in LONG_RUNNING_PHRASES):
        if stall_duration < LONG_RUNNING_GRACE:
            return {
                "action": "wait",
                "reason": f"Agent is intentionally waiting for a long-running operation inside {LONG_RUNNING_GRACE}s grace window",
                "suggestion": None,
            }
        if ONLY_MESSAGE_ON_USER_INPUT:
            return {
                "action": "wait",
                "reason": f"Long-running operation has been quiet for {stall_duration}s; user-input-only policy suppresses nudges",
                "suggestion": None,
            }
        return {
            "action": "nudge",
            "reason": f"Long-running operation has been quiet for {stall_duration}s",
            "suggestion": "Check the background command or deployment status and report progress. If it is still running normally, say so and continue waiting for completion.",
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

    if context.get("request_in_progress") and stall_duration < IN_PROGRESS_GRACE:
        return {
            "action": "wait",
            "reason": f"Latest Copilot request still appears in progress inside {IN_PROGRESS_GRACE}s grace window",
            "suggestion": None,
        }

    if ONLY_MESSAGE_ON_USER_INPUT:
        return {
            "action": "wait",
            "reason": f"Agent has been quiet for {stall_duration}s; user-input-only policy suppresses nudges unless Copilot asks for input",
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
    for line in reversed(response_text.splitlines()):
        stripped = line.strip()
        if stripped:
            return f"You appear idle. Continue from your last stated work: {stripped[:180]}"

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

    session_data = reconstruct_session_data(session_file)
    requests = session_data.get("requests", [])

    print(f"Session: {session_data.get('customTitle', 'Untitled')}")
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
                    continue
                text = text_value(item.get("value")).strip()
                if text and item.get("kind") != "thinking":
                    text_parts.append(text)

        if text_parts:
            print(f"🤖 AGENT: {' '.join(text_parts)[:500]}")
        if tool_count:
            print(f"🤖 AGENT: [{tool_count} tool calls]")
        
        result = req.get("result", {})
        if isinstance(result, dict) and result.get("metadata", {}).get("renderedUserMessage"):
            pass  # skip internal
        print("---")

def recent_exchanges(session_data, n=6):
    """Return the last N user/agent exchanges so an LLM can reconstruct the mission."""
    requests = session_data.get("requests", [])
    out = []
    for req in requests[-n:]:
        msg = req.get("message", {})
        user_text = msg.get("text") if isinstance(msg, dict) else None

        resp = req.get("response", [])
        text_parts = []
        tool_msgs = []
        for item in resp:
            if not isinstance(item, dict):
                continue
            kind = item.get("kind", "")
            if kind == "toolInvocationSerialized":
                inv = text_value(item.get("invocationMessage", {})).strip()
                if inv:
                    tool_msgs.append({
                        "message": inv[:160],
                        "complete": item.get("isComplete", False),
                        "needs_confirmation": item.get("isConfirmed") is False,
                    })
                continue
            t = text_value(item.get("value")).strip()
            if t and kind != "thinking":
                text_parts.append(t)

        out.append({
            "user": (user_text or "")[:800],
            "agent_text": " ".join(text_parts)[:1600],
            "tool_calls": tool_msgs[-8:],
            "in_progress": req.get("result") is None,
        })
    return out

def build_llm_context():
    """Emit a rich, LLM-ready snapshot of the active Copilot session.

    This command makes NO decision about whether to nudge. It hands the raw
    conversational context to the caller (the LLM automation), which reasons
    semantically about whether Copilot is done, genuinely working, or stuck.
    """
    session_file, mtime = find_active_session()
    if not session_file:
        print(json.dumps({"status": "no_session"}, indent=2))
        return

    session_data = reconstruct_session_data(session_file)
    context = read_session_context(session_file)
    state = load_state()

    age = time.time() - mtime
    last_nudge = state.get("last_nudge_time", 0)
    recorded_mtime = state.get("last_mtime", 0)
    nudge_count = state.get("nudge_count", 0)

    # If Copilot has written to the session AFTER our last nudge, it reacted —
    # reset the consecutive-nudge counter so the LLM starts fresh.
    if last_nudge and mtime > last_nudge + 2 and nudge_count > 0:
        nudge_count = 0
        save_state({"nudge_count": 0, "last_nudge_time": last_nudge, "last_mtime": mtime})
    elif mtime > recorded_mtime:
        save_state({"nudge_count": nudge_count, "last_nudge_time": last_nudge, "last_mtime": mtime})

    snapshot = {
        "status": "ok",
        "session_file": str(session_file),
        "session_title": context.get("session_title"),
        "idle_seconds": int(age),
        "idle_minutes": round(age / 60, 1),
        "request_in_progress": context.get("request_in_progress"),
        "agent_state": context.get("agent_state"),
        "error": context.get("error"),
        "last_user_message": context.get("last_user_message"),
        "last_agent_response": "\n".join(context.get("last_response_text", [])),
        "recent_tool_calls": context.get("recent_tool_calls", [])[-8:],
        "recent_exchanges": recent_exchanges(session_data, 6),
        "nudge_count": nudge_count,
        "max_nudges": MAX_NUDGES,
        "last_nudge_seconds_ago": int(time.time() - last_nudge) if last_nudge else None,
        # True when we already nudged and Copilot has NOT written anything since —
        # the LLM should wait for a reaction rather than nudging again.
        "nudged_since_last_activity": bool(last_nudge and last_nudge >= mtime),
    }
    print(json.dumps(snapshot, indent=2))

def do_nudge(message, force=False):
    """Send an LLM-authored message to the active Copilot chat and record state."""
    message = (message or "").strip()
    if not message:
        print(json.dumps({"status": "error", "message": "empty nudge message"}, indent=2))
        return

    session_file, current_mtime = find_active_session()
    state = load_state()
    nudge_count = state.get("nudge_count", 0)

    if not force and nudge_count >= MAX_NUDGES:
        print(json.dumps({
            "status": "max_nudges_reached",
            "nudge_count": nudge_count,
            "message": f"Already sent {nudge_count} consecutive nudges (max {MAX_NUDGES}). "
                       "Not sending. Notify the user or run 'reset', or pass --force.",
        }, indent=2))
        return

    path = send_nudge(message)
    nudge_count += 1
    save_state({
        "nudge_count": nudge_count,
        "last_nudge_time": time.time(),
        "last_mtime": current_mtime if current_mtime else state.get("last_mtime", 0),
    })
    print(json.dumps({
        "status": "nudged",
        "nudge_path": path,
        "nudge_count": nudge_count,
        "message_sent": message,
    }, indent=2))

def reset_nudges():
    """Clear the consecutive-nudge counter (e.g. after the user intervenes)."""
    _, current_mtime = find_active_session()
    save_state({"nudge_count": 0, "last_nudge_time": 0, "last_mtime": current_mtime or 0})
    print(json.dumps({"status": "reset", "nudge_count": 0}, indent=2))

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
        # Dump a rich, LLM-ready snapshot. Makes NO nudge decision itself —
        # the LLM automation reasons over this and calls 'nudge' if warranted.
        build_llm_context()
    elif cmd == "nudge":
        # Send an LLM-authored message to Copilot: supervisor.py nudge "message"
        # or pipe the message on stdin. Pass --force to bypass MAX_NUDGES.
        force = "--force" in sys.argv[2:]
        parts = [a for a in sys.argv[2:] if a != "--force"]
        msg = " ".join(parts).strip()
        if not msg and not sys.stdin.isatty():
            msg = sys.stdin.read().strip()
        do_nudge(msg, force=force)
    elif cmd == "reset":
        reset_nudges()
    elif cmd == "once":
        check_once()
    elif cmd == "help":
        print("""Copilot Smart Supervisor

Usage:
  python3 supervisor.py monitor      — Start monitoring (foreground, deterministic)
  python3 supervisor.py once         — One deterministic check + auto-nudge if stalled
  python3 supervisor.py context      — Dump rich LLM-ready session snapshot (no decision)
  python3 supervisor.py nudge "msg"  — Send an LLM-authored message to Copilot chat
  python3 supervisor.py reset        — Clear the consecutive-nudge counter
  python3 supervisor.py status       — Show current session status
  python3 supervisor.py read [N]     — Read last N conversation exchanges
  python3 supervisor.py help         — Show this help

Recommended (semantic) flow for LLM automations:
  1. Call 'context' to get the snapshot.
  2. Reason: is Copilot done, genuinely working, or stuck?
  3. If stuck (and not nudged_since_last_activity), call 'nudge \"<tailored message>\"'.

Environment:
  STALL_THRESHOLD=60   Seconds before considering agent stalled
  CHECK_INTERVAL=15    Seconds between checks
  MAX_NUDGES=5         Max consecutive nudges before backing off
""")
    else:
        print(f"Unknown command: {cmd}")
        sys.exit(1)
