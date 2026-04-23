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
git clone <this-repo-url> ~/customer-skills
cd ~/customer-skills
bash scripts/install.sh
```

The install script symlinks all 6 skill directories into `~/.copilot/skills/` so Clawpilot loads them globally.

### Manual installation

If you prefer to install manually, symlink each skill individually:

```bash
for skill in meeting-prep customer-repo capture-meeting followups azure-answer architecture; do
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
ls -la ~/.copilot/skills/ | grep -E 'meeting-prep|customer-repo|capture-meeting|followups|azure-answer|architecture'
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

## Skill Quick Reference

| Skill | Trigger phrases | What it does |
|---|---|---|
| **`/meeting-prep`** | "prep for my meeting", "meeting brief", "get ready for my meeting" | Aggregates M365 calendar, email, prior notes, and open follow-ups into a preparation brief committed to the customer repo |
| **`/customer-repo`** | "new customer", "scaffold customer", "set up customer" | Scaffolds a local-only customer engagement folder with templates, tracking files, and push-blocking git hooks |
| **`/capture-meeting`** | "capture meeting", "meeting notes", "summarize meeting" | Processes a completed Teams meeting into structured notes with action items appended to `followups.md` |
| **`/followups`** | "followups", "open items", "what's pending", "action items" | Scans all customer repos for open action items and surfaces unresponded customer emails (read-only) |
| **`/azure-answer`** | "azure pricing", "azure service", "compare azure services" | Answers Azure pricing, capability, and SKU questions backed by web search and optional CLI verification |
| **`/architecture`** | "architecture diagram", "draw architecture", "diagram this" | Generates professional `.drawio` diagrams with Azure/AWS icons via the Draw.io MCP server |

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
$skills = @("meeting-prep", "customer-repo", "capture-meeting", "followups", "azure-answer", "architecture")
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
for %s in (meeting-prep customer-repo capture-meeting followups azure-answer architecture) do (
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
