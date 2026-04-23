---
name: customer-repo
description: "Scaffold a new customer engagement folder at ~/customer-engagements/<name>/ with README, stakeholder tracking, follow-up tracking, meeting notes, decisions, and architecture directories. Initializes a local-only git repo with push-blocking hooks. Triggers include: 'new customer', 'customer repo', 'scaffold customer', 'create customer folder', 'set up customer', 'onboard customer', or any request to create a new customer engagement workspace."
---

# /customer-repo — Customer Engagement Folder Scaffolding

Create a complete, local-only customer engagement folder with standardized
templates, tracking files, and a git repo that blocks pushes to keep customer
data off remote servers.

## Core Principles

- **Local-only data.** Customer engagement data never leaves the local machine via git. The repo is initialized with a pre-push hook that blocks all pushes. No remote is ever configured.
- **Idempotent.** If the customer folder already exists, report what's there and offer to fill any gaps (missing files or directories) rather than overwriting.
- **OneDrive backup.** Remind the user to back up the folder via their OneDrive for Business sync folder (typically `~/OneDrive - <YourCompany>/` on macOS/Linux or `%USERPROFILE%\OneDrive - <YourCompany>\` on Windows — exact path varies per tenant). This keeps customer data on a managed, NDA-safe location.
- **Customer name from input.** Accept the customer name from the user's prompt (e.g., "/customer-repo Contoso") or ask for it if not provided. Never guess or fabricate a customer name.

## Step 1: Collect Customer Name

Accept the customer name from the prompt or ask the user directly.

**If provided in the prompt:**
- Extract the customer name from the user's message (e.g., "/customer-repo Contoso" → "Contoso").

**If not provided:**
- Ask: "What is the customer name for this engagement?"

**Slugify the name for the folder:**
- Lowercase
- Replace spaces with hyphens
- Remove special characters (keep only `a-z`, `0-9`, `-`)
- Example: "Contoso Ltd." → `contoso-ltd`

Set `{name}` to the display name (e.g., "Contoso Ltd.") and `{slug}` to the folder name (e.g., `contoso-ltd`).

## Step 2: Create Folder Structure

**First, check if the base directory exists:**

```bash
mkdir -p ~/customer-engagements
```

**Then check if the customer folder already exists:**

```bash
ls ~/customer-engagements/{slug}/ 2>/dev/null
```

**If the folder already exists:**
- List the existing files and directories.
- Report to the user: "Customer folder already exists at ~/customer-engagements/{slug}/ with these files: ..."
- Identify any missing files or directories from the standard structure below.
- Ask: "Want me to fill in the missing items, or leave it as-is?"
- If the user wants to fill gaps, only create what's missing. Do not overwrite existing files.

**If the folder does not exist, create the full structure:**

```bash
mkdir -p ~/customer-engagements/{slug}/meetings
mkdir -p ~/customer-engagements/{slug}/decisions
mkdir -p ~/customer-engagements/{slug}/architecture
```

The target structure is:

```
~/customer-engagements/{slug}/
├── README.md
├── stakeholders.md
├── followups.md
├── meetings/
├── decisions/
└── architecture/
```

## Step 3: Populate Template Files

Write each template file using the `write` tool. Only create files that don't already exist (idempotency).

### README.md

```markdown
# {name}

**Engagement start:** {YYYY-MM-DD}
**Account folder:** ~/customer-engagements/{slug}/

## Overview

<!-- Brief description of the engagement, project scope, and objectives. -->

## Key Links

<!-- Add links to relevant resources: Teams channels, SharePoint sites, project boards, etc. -->

## Backup

Back up this folder regularly via your OneDrive for Business sync folder
(typically `~/OneDrive - <YourCompany>/` — adjust to your local sync path).

> **⚠️ Privacy Notice:** This folder contains customer-specific engagement data.
> Do not push to any remote git repository. Do not share outside the engagement team.
> All data must remain local or within the approved OneDrive backup path.
```

### stakeholders.md

```markdown
# Stakeholders — {name}

| Name | Role | Email | Notes |
|------|------|-------|-------|
| <!-- Add stakeholder --> | <!-- Role --> | <!-- email@example.com --> | <!-- Notes --> |

## Internal Team

| Name | Role | Email | Notes |
|------|------|-------|-------|
| <!-- Add team member --> | <!-- Role --> | <!-- email@example.com --> | <!-- Notes --> |
```

### followups.md

```markdown
# Follow-ups — {name}

## Open

| Action | Owner | Due | Status |
|--------|-------|-----|--------|
| <!-- Describe the action item --> | <!-- Who owns it --> | <!-- YYYY-MM-DD --> | 🔴 Open |

## Closed

| Action | Owner | Due | Status | Closed |
|--------|-------|-----|--------|--------|
| <!-- Completed items move here --> | <!-- Owner --> | <!-- Due --> | ✅ Done | <!-- YYYY-MM-DD --> |
```

## Step 4: Initialize Git Repo with Push-Blocking Hook

**Initialize git:**

```bash
cd ~/customer-engagements/{slug}
git init
```

**Create the pre-push hook** that blocks all pushes:

Write the following to `.git/hooks/pre-push`:

```bash
#!/bin/sh
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  PUSH BLOCKED: Customer data must remain local.            ║"
echo "║                                                            ║"
echo "║  This repository contains customer engagement data that    ║"
echo "║  must not be pushed to any remote repository.              ║"
echo "║                                                            ║"
echo "║  Back up via your OneDrive for Business sync folder        ║"
echo "║  instead (e.g. ~/OneDrive - <YourCompany>/).               ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
exit 1
```

**Make the hook executable:**

```bash
chmod +x ~/customer-engagements/{slug}/.git/hooks/pre-push
```

**Create initial commit:**

```bash
cd ~/customer-engagements/{slug}
git add -A
git commit -m "Initial scaffold for {name} engagement"
```

## Step 5: Print Summary

After successful scaffolding, present a summary to the user:

```
✅ Customer engagement folder created

📁 Path: ~/customer-engagements/{slug}/
📄 Files created:
   - README.md (engagement overview + privacy notice)
   - stakeholders.md (contact tracking table)
   - followups.md (open/closed action items)
📂 Directories:
   - meetings/ (meeting prep briefs and notes)
   - decisions/ (architectural and project decisions)
   - architecture/ (diagrams and technical docs)
🔒 Git: Initialized with push-blocking pre-push hook
📦 Commit: "Initial scaffold for {name} engagement"

💡 Reminder: Back up this folder via your OneDrive for Business sync folder
   (typically ~/OneDrive - <YourCompany>/ — adjust to your local path).
```

## Error Handling

| Scenario | Behavior |
|----------|----------|
| `~/customer-engagements/` does not exist | Create it with `mkdir -p`. Continue. |
| Customer folder already exists | List contents. Offer to fill gaps only. Do not overwrite. |
| Customer folder exists and is complete | Report "Folder already fully scaffolded." Show the file listing. Stop. |
| `git init` fails | Warn the user but continue — the folder and files are still usable without git. |
| `git commit` fails | Inform the user. The files are written; only versioning is missing. |
| User provides empty or invalid customer name | Ask again. Do not proceed with an empty slug. |
| Disk space or permission error on write | Report the error and stop. Do not partially scaffold. |
