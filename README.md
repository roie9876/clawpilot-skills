# Customer Skills

Personal [Clawpilot](https://clawpilot.dev) skills for streamlining day-to-day customer engagement work: meeting prep, note capture, follow-up tracking, Azure Q&A, customer repo scaffolding, and architecture diagramming.

These skills bridge the gap between Microsoft 365 (where customer work happens) and VS Code / git repos (where technical work happens), using Clawpilot as the glue layer.

## Prerequisites

| Requirement | Notes |
|---|---|
| **Clawpilot** | Desktop app with WorkIQ (M365 data access) enabled |
| **git** | Any recent version — used for customer engagement repos |
| **macOS or Windows** | See [Windows Notes](#windows-notes) for platform differences |
| **Node.js** | Required for CRM pipeline skills (`/msx-crm`, `/crm-activity-sync`). `brew install node` |
| **cliclick** (macOS) | Required for SSO auto-picker. `brew install cliclick`. See [Troubleshooting](#sso-account-picker-not-auto-handled) |
| **Azure VPN** | Required for CRM access. See [Troubleshooting](#vpn-not-connected) |
| **M365 sign-in** | Required for calendar, email, Teams. Clawpilot handles this |

## Installation

### macOS / Linux (one command)

```bash
git clone https://github.com/roie9876/clawpilot-skills.git ~/customer-skills
cd ~/customer-skills
bash scripts/install.sh
```

### Windows (PowerShell)

```powershell
git clone https://github.com/roie9876/clawpilot-skills.git $HOME\customer-skills
cd $HOME\customer-skills
pwsh scripts\install.ps1
# or, if pwsh isn't installed:
powershell -ExecutionPolicy Bypass -File scripts\install.ps1
```

> Symlink creation on Windows needs Admin or Developer Mode. See [Windows Notes](#windows-notes).

Both scripts symlink all 9 skill directories into `$HOME/.copilot/skills/` so Clawpilot loads them globally.

### Manual installation

If you prefer to install manually, symlink each skill individually:

```bash
for skill in meeting-prep customer-repo capture-meeting followups azure-answer architecture connect daily-activity-log crm-activity-sync msx-crm; do
  ln -sfn ~/customer-skills/$skill ~/.copilot/skills/$skill
done
```

> **Note:** If `~/.copilot/skills/` does not exist yet, create it first:
> ```bash
> mkdir -p ~/.copilot/skills
> ```

### Verify installation

After installing, confirm the symlinks are in place:

```bash
ls -la ~/.copilot/skills/ | grep -E 'meeting-prep|customer-repo|capture-meeting|followups|azure-answer|architecture|connect'
```

You should see 6 symlinks pointing back to your `~/customer-skills/` checkout.

## Draw.io MCP Server Setup

The `/architecture` skill requires the Draw.io MCP server to generate `.drawio` diagrams. This is the **only MCP dependency** for these skills.

1. Open Clawpilot settings → **MCP Servers**
2. Add a new server with URL: `https://mcp.draw.io/mcp`
3. The tool `drawio/create_diagram` should now be available

> **Pre-existing dependency:** If you already have the `drawio-mcp-diagramming` skill installed at `~/.copilot/skills/drawio-mcp-diagramming/`, the architecture skill leverages its icon catalogs and XML templates. No additional setup is needed — the skill inlines all required patterns.

## Azure CLI (Optional)

The `/azure-answer` skill can optionally verify pricing and service data against the Azure CLI. This is not required — the skill works without it using web search alone — but CLI verification improves confidence.

```bash
# Install Azure CLI (if not already installed)
brew install azure-cli    # macOS
# or: curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash  # Linux

# Sign in
az login

# Verify
az account show --query name -o tsv
```

If `az` is not installed or not logged in, `/azure-answer` gracefully degrades to web-search-only mode with a note that CLI verification was skipped.

## Customer Data Repo Setup

Before using most skills, set up your customer engagement repo via the `/customer-repo` skill:

1. Open Clawpilot
2. Type: `/customer-repo Contoso` (or your customer name)
3. The skill scaffolds `~/customer-engagements/<name>/` with:
   - `README.md` — engagement summary
   - `stakeholders.md` — people and roles
   - `followups.md` — action item tracking (`## Open` / `## Closed` tables)
   - `meetings/` — meeting notes directory
   - `decisions/` — decision records
   - `architecture/` — diagrams
   - `artifacts/` — customer-provided files

The customer engagement repo is **local-only** — it is initialized with a `pre-push` hook that blocks all pushes to keep customer data off remote servers.

> **Backup:** Symlink or move `~/customer-engagements/` into your OneDrive for Business folder for NDA-safe cloud backup. The exact OneDrive path varies per user — check your local OneDrive sync folder (typically `~/OneDrive - Microsoft/` or similar). Adjust to match your setup.

## Skills Overview

Seven focused skills that together cover the full customer-engagement lifecycle — from scaffolding a new engagement, through preparing and capturing meetings, tracking follow-ups, answering Azure questions, producing architecture diagrams, and preparing your 1:1 manager check-ins.

### 1. `/customer-repo` — Scaffold a customer engagement workspace

Creates a standardized folder layout at `~/customer-engagements/{customer}/` (or `~/customer-engagements/{customer}/{project}/` for multi-project customers) with README, stakeholders, follow-ups tracker, meetings directory, decisions log, and architecture folder. Initializes a local-only git repo with a `pre-push` hook that blocks any push — keeping customer data off remote servers by construction.

- **Triggers:** "new customer", "customer repo", "scaffold customer", "set up customer", "onboard customer"
- **Example:** `/customer-repo Contoso` or `/customer-repo Contoso/SASE-PoC`
- **Output:** Fully scaffolded local repo with templates, privacy notice, and initial commit

### 2. `/meeting-prep` — Build a meeting preparation brief

Aggregates calendar event details, prior meeting notes, open follow-ups, recent email threads, and attendee information from Microsoft 365 into a share-ready prep brief. Writes both `.html` (RTL-capable, dark-themed, auto-opened in Edge) and `.md` versions to the customer repo and commits to git.

- **Triggers:** "prep for my meeting", "meeting brief", "prepare for meeting", "get ready for my meeting"
- **Data sources:** M365 calendar, email search, facilitator notes, transcripts, people lookup, local customer repo
- **Customer detection:** Attendee email domains → folder match → subject line → ask user
- **Graceful degradation:** Every data source can fail independently; the brief notes gaps explicitly

### 3. `/capture-meeting` — Process a completed meeting into structured notes

Takes a finished Teams meeting and produces structured meeting notes with extracted action items, appended to the customer's `followups.md`. Preserves source language (Hebrew content stays Hebrew, English stays English) and cross-references prior commitments.

- **Triggers:** "capture meeting", "meeting notes", "summarize meeting", "meeting recap", "log meeting"
- **Data sources:** Teams recap, transcript, facilitator notes, meeting body
- **Output:** `meetings/YYYY-MM-DD-{topic}.md` + action items appended to `followups.md`, committed to git

### 4. `/followups` — See what's pending across all customers

Scans every `followups.md` under `~/customer-engagements/` and cross-references with "emails awaiting your reply" from M365 to produce one prioritized view of open work. Read-only — does not modify any file.

- **Triggers:** "followups", "open items", "what's pending", "action items", "what do I need to do"
- **Grouping:** By customer, with age and source (meeting / email / manual)
- **Privacy:** Operates entirely on local files + M365; no external services

### 5. `/azure-answer` — Azure pricing, capability, and SKU questions

Answers factual Azure questions (pricing, service capabilities, SKU comparisons, region availability) backed by verified web sources (learn.microsoft.com, azure.microsoft.com) and optionally cross-checked against Azure CLI output when available. Always cites sources with access dates and notes when data is time-sensitive.

- **Triggers:** "azure pricing", "azure service", "compare azure services", "which azure service", "azure cost"
- **Verification:** Requires at least one authoritative Microsoft source; gracefully degrades to web-search-only if `az` CLI is unavailable
- **Output:** Direct answer + source table + calculator links for pricing

### 6. `/architecture` — Generate `.drawio` architecture diagrams

Produces professional architecture diagrams with correctly-rendered Azure and AWS icons using the Draw.io MCP server. Saves `.drawio` files into the customer's `architecture/` folder with standard node/edge styling.

- **Triggers:** "architecture diagram", "draw architecture", "diagram this", "network topology", "draw this in drawio"
- **Icon libraries:** Azure2, AWS4 (via inlined catalogs — no per-run internet lookups)
- **Dependency:** Requires Draw.io MCP server configured in Clawpilot (see [MCP setup](#drawio-mcp-server-setup))

### 7. `/connect` — Prepare a Microsoft 1:1 Connect check-in

> **Microsoft-internal skill.** This skill targets `v2.msconnect.microsoft.com` (Microsoft's semi-annual 1:1 Connect tool) and is only usable by Microsoft employees. Non-Microsoft users can skip installing it.

Reads past Connect history for tone, aggregates accomplishments from M365 (emails sent, meetings led, Teams activity, CRM, customer repos), drafts content in your voice, and fills the Connect form via browser automation. You always review and submit yourself.

- **Triggers:** "connect", "prepare connect", "fill connect", "manager connect", "1:1 connect"
- **Writes a draft — never submits.** Human-in-the-loop by design.

### 8. `/daily-activity-log` — Automated daily work logging

Scans multiple data sources — git repos, M365 calendar, sent emails, and SSP Teams chats (ad-hoc calls + technical messages) — to build a structured daily activity summary per customer project. Writes `activity-log.md` in each project's folder.

- **Triggers:** "daily activity", "activity log", "log my work", "what did I do"
- **Data sources:** Git commits, calendar events, sent emails, SSP Teams chat (calls + messages)
- **Depends on:** `/customer-repo` (folder structure), `/crm-activity-sync` (shared config)
- **Output:** `activity-log.md` per project, classified by CRM task category

### 9. `/crm-activity-sync` — Push activities to MSX CRM

Reads `activity-log.md` files and creates milestone tasks in MSX (Dynamics 365). Handles deal team membership verification, idempotency, and milestone discovery.

- **Triggers:** "crm activity", "sync activities", "update crm", "log crm"
- **Depends on:** `/daily-activity-log` (upstream data), `/customer-repo` (folder structure), `/msx-crm` (CRM tools)
- **Pipeline:** Runs daily at 08:00, after `/daily-activity-log` runs at 07:30
- **Auto-joins deal teams** if not already a member

### 10. `/msx-crm` — Query MSX CRM data

Direct access to Microsoft Sales Experience (Dynamics 365) — accounts, opportunities, milestones, tasks, and deal teams. Backend for `/crm-activity-sync`.

- **Triggers:** "MSX", "CRM", "milestones", "opportunities", "deal team"
- **Requires:** VPN connected, CRM tools installed (`run-tool.mjs`)

## Skill Quick Reference

| Skill | Trigger phrases | What it does |
|---|---|---|
| **`/customer-repo`** | "new customer", "scaffold customer", "set up customer" | Scaffolds a local-only customer engagement folder with templates, tracking files, and push-blocking git hooks |
| **`/meeting-prep`** | "prep for my meeting", "meeting brief", "get ready for my meeting" | Aggregates M365 calendar, email, prior notes, and open follow-ups into a preparation brief committed to the customer repo |
| **`/capture-meeting`** | "capture meeting", "meeting notes", "summarize meeting" | Processes a completed Teams meeting into structured notes with action items appended to `followups.md` |
| **`/followups`** | "followups", "open items", "what's pending", "action items" | Scans all customer repos for open action items and surfaces unresponded customer emails (read-only) |
| **`/azure-answer`** | "azure pricing", "azure service", "compare azure services" | Answers Azure pricing, capability, and SKU questions backed by verified web search and optional CLI verification |
| **`/architecture`** | "architecture diagram", "draw architecture", "diagram this" | Generates professional `.drawio` diagrams with Azure/AWS icons via the Draw.io MCP server |
| **`/connect`** | "connect", "prepare connect", "1:1 connect" | *(Microsoft-internal)* Drafts and fills a 1:1 Connect check-in on v2.msconnect.microsoft.com — you review and submit |
| **`/daily-activity-log`** | "daily activity", "activity log", "log my work" | Scans git, calendar, email, SSP Teams chats → writes `activity-log.md` per customer project |
| **`/crm-activity-sync`** | "crm activity", "sync activities", "update crm" | Reads activity logs → creates CRM milestone tasks in MSX. Auto-joins deal teams |
| **`/msx-crm`** | "MSX", "CRM", "milestones", "opportunities" | Direct CRM queries — accounts, opportunities, milestones, tasks, deal teams |

## Skill Dependencies

The CRM pipeline skills have a specific dependency order:

```
/customer-repo          (foundation — folder structure)
     ↓
/daily-activity-log     (collects evidence → activity-log.md)
     ↓
/crm-activity-sync      (reads activity-log.md → creates CRM tasks)
     ↓
/msx-crm                (CRM backend — queries and writes)
```

All other skills (`/meeting-prep`, `/capture-meeting`, `/followups`, `/azure-answer`,
`/architecture`, `/connect`) are independent — they only need `/customer-repo` for
the folder structure.

## Known Issues & Troubleshooting

Common problems that new users will encounter when setting up these skills on a
fresh macOS system with Clawpilot.

### SSO Account Picker Not Auto-Handled

**Symptom:** M365 sign-in pops up an account picker dialog. Clawpilot hangs waiting
for user to click. Automated skills fail with `user_canceled`.

**Root cause:** Clawpilot uses an Electron webview for auth. macOS SSO (via Company
Portal / `AppSSOAgent`) presents an account picker that requires a mouse click.
AppleScript `click` commands do **not** register on Electron webviews.

**Solution:** Install a background watcher that uses `cliclick` (real mouse
coordinates) instead of AppleScript `click`:

1. Install cliclick: `brew install cliclick`

2. Create `~/Scripts/watch-sso-picker.sh`:
   - Use AppleScript to **find** the account element position in the Clawpilot window
   - Use `cliclick c:X,Y` to **click** it with real mouse movement
   - Loop: find `robenhai@microsoft.com` → click it → wait → find "Continue" button → click it
   - Poll every 3 seconds

3. Install as a launchd service (`~/Library/LaunchAgents/com.roie.sso-watcher.plist`):
   ```xml
   <key>ProgramArguments</key>
   <array>
     <string>/bin/bash</string>
     <string>/Users/USERNAME/Scripts/watch-sso-picker.sh</string>
   </array>
   <key>RunAtLoad</key>
   <true/>
   <key>KeepAlive</key>
   <true/>
   ```

4. Grant **Accessibility** and **Screen Recording** permissions to `/bin/bash` in
   System Preferences → Privacy & Security.

**Important:** The Mac screen must be **unlocked** for `cliclick` to work. On a
locked screen, the SSO picker cannot be auto-handled.

### VPN Not Connected

**Symptom:** CRM queries fail with timeout or connection errors.

**Root cause:** MSX CRM (Dynamics 365) is behind Microsoft's corporate network.
Requires Azure VPN.

**Solution:** Create a VPN auto-connect script at `~/Scripts/ensure-vpn.sh`:

```bash
#!/bin/bash
# Check if MSFT-AzVPN-Manual is connected
VPN_STATUS=$(scutil --nc status "MSFT-AzVPN-Manual" 2>/dev/null | head -1)
if [[ "$VPN_STATUS" == "Connected" ]]; then
    echo "✅ VPN already connected"
    exit 0
fi
# Try to connect
scutil --nc start "MSFT-AzVPN-Manual"
sleep 5
# Verify
VPN_STATUS=$(scutil --nc status "MSFT-AzVPN-Manual" 2>/dev/null | head -1)
if [[ "$VPN_STATUS" == "Connected" ]]; then
    echo "✅ VPN connected"
    exit 0
fi
echo "❌ VPN failed to connect"
exit 1
```

All CRM-dependent skills call this script before CRM access. The VPN name
(`MSFT-AzVPN-Manual`) may differ per user — check `scutil --nc list` for
the correct name.

### M365 Token Expires During Automation

**Symptom:** Daily automation (07:30) fails because M365 token expired overnight.
Calendar, email, and Teams data not collected.

**Root cause:** M365 tokens have a limited lifetime. When they expire, Clawpilot
triggers re-auth which requires the SSO picker (see above).

**Mitigations:**
1. SSO watcher (see above) handles re-auth automatically **if screen is unlocked**
2. Heartbeat prompt includes relay reconnection check (every 30 min during work hours)
3. Skills degrade gracefully — `/daily-activity-log` logs git commits even without
   M365, and notes which sources were unavailable

**If running overnight/unattended:** Accept that M365 sources may be unavailable.
The next interactive session will trigger re-auth, and you can re-run the daily
log manually: `/daily-activity-log yesterday`

### Teams Relay Disconnects

**Symptom:** Teams notifications stop working. Proactive messages don't arrive.

**Root cause:** Relay disconnects when M365 token expires or when another Clawpilot
client connects (displacement).

**Solution:** Add relay health check to the heartbeat prompt:
```
Check Teams relay status with m_relay_status.
If disconnected, reconnect with m_relay_connect.
```

This is configured in Clawpilot heartbeat settings and runs every 30 minutes
during work hours.

### CRM Task Creation Fails — Not on Deal Team

**Symptom:** `create_task` returns a permissions error for a specific opportunity.

**Root cause:** User is not a member of the deal team for that opportunity in MSX.

**Solution:** `/crm-activity-sync` (Step 5c) now auto-checks deal team membership
before creating tasks. If the user is not on the team, it:
1. Auto-adds the user via CRM API
2. Retries the task creation
3. If auto-add fails (permissions), queues the task and notifies the user to ask
   the SSP to add them manually

### Node.js Not Found

**Symptom:** CRM tool calls fail with "node: command not found".

**Solution:** CRM tools require Node.js. On macOS with Homebrew:
```bash
brew install node
```

When calling CRM tools from scripts/automations, use the full path:
```bash
PATH="/opt/homebrew/bin:$PATH" node ~/Documents/crm-tools/run-tool.mjs ...
```

### `cliclick` Not Installed

**Symptom:** SSO watcher logs show "cliclick: command not found".

**Solution:**
```bash
brew install cliclick
```

Verify: `/opt/homebrew/bin/cliclick -V` should return version info.

## Windows Notes

These skills work on Windows with the following adjustments:

### Paths

Replace `~` with `%USERPROFILE%` in all paths:

| macOS / Linux | Windows |
|---|---|
| `~/customer-skills/` | `%USERPROFILE%\customer-skills\` |
| `~/.copilot/skills/` | `%USERPROFILE%\.copilot\skills\` |
| `~/customer-engagements/` | `%USERPROFILE%\customer-engagements\` |

### Symlinks (PowerShell)

Use the bundled installer:

```powershell
pwsh scripts\install.ps1
# or, on Windows PowerShell 5:
powershell -ExecutionPolicy Bypass -File scripts\install.ps1
```

It symlinks all 9 skills into `$HOME\.copilot\skills\` and prints clear errors if elevation is missing.

Manual equivalent (if you prefer):

```powershell
$skills = @("meeting-prep", "customer-repo", "capture-meeting", "followups", "azure-answer", "architecture", "connect", "crm-activity-sync", "daily-activity-log")
foreach ($skill in $skills) {
    New-Item -ItemType SymbolicLink `
        -Path "$env:USERPROFILE\.copilot\skills\$skill" `
        -Target "$env:USERPROFILE\customer-skills\$skill" `
        -Force
}
```

> **Note:** Creating symlinks on Windows requires either Administrator privileges or Developer Mode enabled (Settings → For developers → Developer Mode → On).

### Alternative: Directory Junctions (no admin required)

```cmd
for %s in (meeting-prep customer-repo capture-meeting followups azure-answer architecture connect crm-activity-sync daily-activity-log) do (
    mklink /D "%USERPROFILE%\.copilot\skills\%s" "%USERPROFILE%\customer-skills\%s"
)
```

## Privacy Notice

**Customer data is local-only.** These skills process customer information (meeting notes, email threads, pricing data, NDA-covered content) that must never leave Microsoft-managed systems.

- **Skills repo** (`~/customer-skills/`) — contains methodology and tooling only. Safe to share and push to a remote.
- **Customer data repo** (`~/customer-engagements/`) — contains customer-specific data. **Never push to any remote.** The `/customer-repo` skill initializes it with a `pre-push` hook that blocks all pushes.
- **Backup** — Use OneDrive for Business folder sync for `~/customer-engagements/`. This is the only approved backup path (Microsoft-managed, NDA-safe). The OneDrive sync path varies per user — adjust to your local setup.
- **No telemetry** — These skills do not send data to any external service. All M365 data access is through Clawpilot's WorkIQ, which operates within the Microsoft tenant boundary.

> **Before sharing this repo:** Verify no customer data has leaked into the skills repo. The `.gitignore` should exclude any customer-specific content. Review staged files before committing.
