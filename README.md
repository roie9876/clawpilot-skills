# Customer Skills

Personal [Clawpilot](https://clawpilot.dev) skills for streamlining day-to-day customer engagement work: meeting prep, note capture, follow-up tracking, Azure Q&A, customer repo scaffolding, and architecture diagramming.

These skills bridge the gap between Microsoft 365 (where customer work happens) and VS Code / git repos (where technical work happens), using Clawpilot as the glue layer.

## Prerequisites

| Requirement | Notes |
|---|---|
| **Clawpilot** | Desktop app with WorkIQ (M365 data access) enabled |
| **git** | Any recent version — used for customer engagement repos |
| **macOS or Windows** | See [Windows Notes](#windows-notes) for platform differences |
| **Node.js** (optional) | Not required for the skills themselves, only if developing/testing |

## Installation

### macOS / Linux (one command)

```bash
git clone https://github.com/roie9876/clawpilot-skills.git ~/customer-skills
cd ~/customer-skills
bash scripts/install.sh
```

The install script symlinks all 7 skill directories into `~/.copilot/skills/` so Clawpilot loads them globally.

### Manual installation

If you prefer to install manually, symlink each skill individually:

```bash
for skill in meeting-prep customer-repo capture-meeting followups azure-answer architecture connect; do
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

## Windows Notes

These skills work on Windows with the following adjustments:

### Paths

Replace `~` with `%USERPROFILE%` in all paths:

| macOS / Linux | Windows |
|---|---|
| `~/customer-skills/` | `%USERPROFILE%\customer-skills\` |
| `~/.copilot/skills/` | `%USERPROFILE%\.copilot\skills\` |
| `~/customer-engagements/` | `%USERPROFILE%\customer-engagements\` |

### Symlinks (PowerShell — run as Administrator)

```powershell
$skills = @("meeting-prep", "customer-repo", "capture-meeting", "followups", "azure-answer", "architecture", "connect")
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
for %s in (meeting-prep customer-repo capture-meeting followups azure-answer architecture connect) do (
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
