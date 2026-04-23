---
name: daily-activity-log
description: "Scan work repos (git), calendar events, and PG/engineering emails to build a structured daily activity log in customer-engagements. Writes activity-log.md per project as the source of truth for CRM sync and engagement tracking. Triggers include: 'daily activity', 'activity log', 'log my work', 'what did I do', 'sync activity', 'daily sync', 'update activity log', or any request to capture the day's SE work into customer-engagements."
---

# /daily-activity-log — Daily Activity Log Builder

Scan multiple data sources — work repos (git history), M365 calendar, and
PG/engineering emails — to build a structured daily activity summary per
customer project. Writes `activity-log.md` in each project's
customer-engagements folder, making customer-engagements the single source of
truth for downstream consumers like `/crm-activity-sync`.

## Core Principles

- **Evidence-based only.** Every logged activity must trace to a concrete artifact: a git commit, a calendar event, or a sent email. Never infer or fabricate work.
- **Aggregate per day.** All evidence for a single customer + project + date is merged into one daily entry. A day of design commits + a meeting + an engineering email → one entry with sections, not three separate entries.
- **Append, never overwrite.** New daily entries are prepended (most recent first) to `activity-log.md`. Existing entries are never modified or removed.
- **Idempotent.** If the log already contains an entry for the target date + project, skip it. Report: "Activity for {customer}/{project} on {date} already logged."
- **Preserve source language.** Commit messages, email subjects, and meeting titles stay in their original language.
- **Graceful degradation.** Each data source can fail independently. If git is available but calendar isn't, log what you have. Note missing sources.
- **Classify, don't just list.** Each daily entry gets a **Task Category** classification based on the evidence. The category must match one of the 20 CRM `msp_taskcategory` values. The skill auto-classifies using signal keywords, but the user can override to any category during interactive mode or via the `default_activity_type` in `crm-mapping.json`.

### CRM Task Categories (all 20)

These are the valid `msp_taskcategory` values in MSX. The skill can assign any of them:

| Category | Value | Auto-classify signals |
|---|---|---|
| **Architecture Design Session** | `861980004` | "architecture", "design", "topology", "solution review", design commits |
| **PoC/Pilot** | `861980005` | "poc", "pilot", "testing", "lab", "hands-on", poc commits |
| **Workshop** | `861980001` | "workshop", "deep-dive", "training", "enablement", multi-hour events |
| **Customer Engagement** | `861980000` | General customer meetings, sync calls, status updates |
| **Briefing** | `861980008` | "briefing", "ideation", "brainstorm", "explore", "concept" |
| **Blocker Escalation** | `861980006` | Engineering escalation emails, PG coordination on blockers |
| **Demo** | `861980002` | "demo", "demonstration", "showcase", "show and tell" |
| **Internal** | `861980012` | Internal-only meetings with project keyword match, no customer |
| **ACE** | `606820000` | "ace", "azure consumption" |
| **Call Back Requested** | `861980010` | "callback", "call back" |
| **Consumption Plan** | `861980007` | "consumption", "commit", "macc" |
| **Cross Segment** | `606820001` | "cross segment", "cross-segment" |
| **Cross Workload** | `606820002` | "cross workload", "cross-workload" |
| **External (Co-creation of Value)** | `861980013` | "co-creation", "hackathon", "joint development" |
| **Negotiate Pricing** | `861980003` | "pricing", "negotiate", "commercial", "deal terms" |
| **New Partner Request** | `861980011` | "partner", "isv", "si request" |
| **Post Sales** | `606820003` | "post sales", "post-sales", "go-live support" |
| **RFP/RFI** | `861980009` | "rfp", "rfi", "request for proposal" |
| **Tech Support** | `606820004` | "support", "incident", "troubleshoot" |
| **Technical Close/Win Plan** | `606820005` | "close plan", "win plan", "technical close" |

The top 8 are the most common for SE daily work. The remaining 12 are available for
specialized activities. If the auto-classifier can't determine the category, it falls
back to the project's `default_activity_type` in `crm-mapping.json`.

- **Detect unknown customers.** When a calendar event has external attendees whose domain doesn't match any existing `crm-mapping.json` customer, flag it. In interactive mode: ask whether it's a core customer, temp engagement, or not customer work. In automated mode: log the activity anyway (customer-engagements folder is source of truth if it exists) and send a Teams alert asking for classification.

## Prerequisites

### Required Skills

These skills must also be installed in Clawpilot (`~/.copilot/m-skills/`) for the
full pipeline to work:

| Skill | Purpose | Required? |
|---|---|---|
| `/crm-activity-sync` | Downstream — reads `activity-log.md` and pushes to CRM. Also owns the shared `config.json` and setup flow | ✅ For config + CRM sync |
| `/customer-repo` | Scaffolds `customer-engagements/` folder structure per customer | ✅ For initial setup |
| `/msx-crm` | CRM query tools (`run-tool.mjs`) for milestone and opportunity lookups | ⚠️ Only if CRM sync is desired |

### Required Tools & Infrastructure

| Prerequisite | Required? | How to check |
|---|---|---|
| `customer-engagements/` folder | ✅ | `~/customer-engagements/` exists with ≥1 customer |
| M365 signed in | ⚠️ Recommended | `m_m365_status` — needed for calendar + email + Teams chat sources |
| Config file | ✅ | `~/.copilot/crm-activity-sync/config.json` — shared with crm-activity-sync |
| Node.js | ⚠️ Only for CRM | `/opt/homebrew/bin/node --version` |

**Note:** This skill shares its config with `/crm-activity-sync`. If setup hasn't
been run yet, it will trigger the setup flow (see crm-activity-sync Step 1).

## Commands

| Command | Purpose |
|---|---|
| `/daily-activity-log` | Log yesterday's activities (default) |
| `/daily-activity-log today` | Log today's activities (so far) |
| `/daily-activity-log <date>` | Log activities for a specific date (ISO: 2026-04-21) |
| `/daily-activity-log week` | Log the current work week (Sun–Thu) |
| `/daily-activity-log range <start> <end>` | Log a date range |
| `/daily-activity-log add-repo <customer>/<project> <path>` | Register a work repo for a project |
| `/daily-activity-log remove-repo <customer>/<project> <path>` | Unregister a work repo |
| `/daily-activity-log repos` | List all registered work repo mappings |

## File Locations

| File | Purpose |
|---|---|
| `~/.copilot/crm-activity-sync/config.json` | Shared config (user profile, preferences, repo mappings) |
| `~/customer-engagements/{customer}/projects/{project}/activity-log.md` | Per-project daily activity log (output) |
| `~/customer-engagements/{customer}/crm-mapping.json` | Per-customer project-to-CRM mapping (shared with crm-activity-sync) |

## Config: Work Repo Registration

Work repos are stored in `crm-mapping.json` under each project:

```json
{
  "projects": {
    "sase": {
      "display_name": "SASE",
      "work_repos": [
        {
          "path": "/Users/robenhai/SASE",
          "label": "SASE Design & POC",
          "added": "2026-04-23"
        }
      ],
      "subject_keywords": ["sase", "checkpoint", "aks", "dpdk", "srv6"]
    }
  }
}
```

**Registration rules:**
- A repo is registered to exactly one project. If a repo serves multiple projects (rare), ask the user which project it belongs to.
- Repos are registered manually via `/daily-activity-log add-repo` or during setup.
- Not every project has a repo — some are meeting-only engagements.
- The path must be an absolute path to a directory containing `.git/`.
- Validate on registration: `[ -d "<path>/.git" ]`. If not a git repo → reject.

## Config: SSP Chat Mapping

SSP-to-customer mapping comes from `config.core_ssps[]` in
`~/.copilot/crm-activity-sync/config.json`. Each SSP entry lists which customers
they cover. The 1:1 chat ID is resolved at runtime via
`m365_create_chat_by_email(email)` and can optionally be cached in
`crm-mapping.json` for performance:

```json
{
  "ssp_chat_ids": {
    "kobishitrit@microsoft.com": "19:80cb6140-...@unq.gbl.spaces"
  },
  "projects": {
    "sase": {
      "group_chat_ids": [
        {
          "id": "19:5fda07cb...@thread.v2",
          "topic": "HSASE-AZURE-GlobalNetworkBrain",
          "added": "2026-04-23"
        }
      ]
    }
  }
}
```

**SSP chat scanning rules:**
- Only scan chats for SSPs in `config.core_ssps`. Never scan random chats.
- Cache resolved chat IDs in `crm-mapping.json` under `ssp_chat_ids` to avoid
  repeated lookups.
- Group chats are optional — register via `/daily-activity-log add-group-chat`.
- The `group_chat_ids` array is per-project in `crm-mapping.json`.

**New commands for SSP chat management:**

| Command | Purpose |
|---|---|
| `/daily-activity-log add-group-chat <customer>/<project> <chat-id> <topic>` | Register a group chat for scanning |
| `/daily-activity-log remove-group-chat <customer>/<project> <chat-id>` | Unregister a group chat |

---

## Step 0: Determine Target Date(s)

**Default:** Yesterday, adjusted for Israeli work week.
- If today is Sunday → yesterday was Saturday (weekend) → use Thursday.
- If today is Friday → yesterday was Thursday → use Thursday.
- If today is Saturday → yesterday was Friday (weekend) → use Thursday.
- Otherwise → use yesterday.

**Explicit date:** The user can provide a specific date or range.

**Week mode:** Sunday through Thursday of the current week up to yesterday.

Set `target_dates[]` — an array of dates to process. Process each date
independently, in chronological order.

---

## Step 1: Load Config and Mappings

1. Read `~/.copilot/crm-activity-sync/config.json`.
   - If missing → prompt: "Run /crm-activity-sync setup first to configure your profile and customer mappings."
   - Stop.

2. For each customer in `~/customer-engagements/`:
   - Read `~/customer-engagements/{customer}/crm-mapping.json`.
   - If missing → this customer has no CRM mapping yet. Still process it (activity log is useful even without CRM), but warn: "No CRM mapping for {customer}. Activities will be logged but won't sync to CRM."

3. Build a lookup table:
   - `repo_path → { customer, project }` — maps each registered repo to its project.
   - `keyword → { customer, project }` — maps subject keywords to projects.
   - `customer_domains → { customer }` — maps email domains to customers (from stakeholders.md).
   - `ssp_email → { customer[], chat_id }` — maps SSPs to their customers and cached chat IDs.

---

## Step 2: Collect Evidence

For each target date, collect from all sources in parallel.

### 2a. Work Repo Git History

For each registered work repo:

```bash
cd <repo-path> && git --no-pager log \
  --format="%h %s" \
  --since="<target-date>T00:00:00" \
  --until="<target-date+1>T00:00:00" \
  --author="$(git config user.email)" \
  2>/dev/null
```

**Important:** Filter by `--author` to only count the user's own commits, not
collaborators. Use `git config user.email` from the repo, or fall back to the
email in config.

**Extract from commits:**
- Total commit count.
- Commit message prefixes (everything before the first colon: `design:`, `poc:`, `feat:`, `fix:`, `docs:`, `test:`).
- Dominant prefix = most frequent → drives activity type classification.
- Summarize what changed: group by prefix, list the distinct topics.

**Prefix-to-task-category mapping:**

| Git prefix | CRM Task Category |
|---|---|
| `design`, `arch`, `proposal` | Architecture Design Session |
| `poc`, `feat`, `experiment`, `spike`, `test` | PoC/Pilot |
| `workshop`, `lab`, `enable` | Workshop |
| `demo`, `showcase` | Demo |
| `docs`, `readme`, `changelog` | Architecture Design Session (documentation supports design) |
| `fix`, `hotfix`, `patch` | PoC/Pilot (bug fixing during POC) |
| `escalation`, `blocker` | Blocker Escalation |
| `support`, `incident` | Tech Support |
| No prefix / unknown | Use project's `default_activity_type` from crm-mapping.json |

**If a repo has zero commits on the target date** → skip it, no entry for this source.

### 2b. Calendar Events

```
m365_list_events(startDate: "<target-date>T00:00:00Z", endDate: "<target-date>T23:59:59Z", limit: 50)
```

**Filter criteria:**
- ❌ Exclude all-day events.
- ❌ Exclude cancelled events.
- ❌ Exclude recurring 1:1s with manager (match `config.user.manager.email`).
- ❌ Exclude events with zero external attendees AND no project keyword match in subject.
- ✅ Include events where ≥1 attendee has an external (customer) email domain.
- ✅ Include events where the subject matches a project keyword, even if all-internal.

**For each qualifying event, extract:**
- Subject, start time, end time, duration.
- Attendee list (names, classify as internal/external/engineering).
- Whether external attendees are customer or Microsoft Engineering (PG).

**Map to customer/project:**
1. Match external attendee domains against `customer_domains` lookup.
2. Match subject against `keyword` lookup.
3. If both match the same project → confirmed.
4. If domain matches one customer but subject matches another → flag ambiguity, ask user.
5. If no match → skip (not a customer event).

**Classify meeting category:**
- Meeting + "workshop" / "deep-dive" / "hands-on" / "training" → **Workshop**
- Meeting + "architecture" / "design" / "topology" / "solution review" → **Architecture Design Session**
- Meeting + "poc" / "pilot" / "testing" / "lab" → **PoC/Pilot**
- Meeting + "demo" / "showcase" / "demonstration" → **Demo**
- Meeting + "ideation" / "brainstorm" / "explore" / "concept" → **Briefing**
- Meeting + "rfp" / "rfi" / "request for proposal" → **RFP/RFI**
- Meeting + "pricing" / "negotiate" / "commercial" / "deal" → **Negotiate Pricing**
- Meeting + "close plan" / "win plan" / "technical close" → **Technical Close/Win Plan**
- Meeting + "partner" / "isv" / "si" → **New Partner Request**
- Meeting + "consumption" / "commit" / "macc" → **Consumption Plan**
- Meeting + "support" / "incident" / "troubleshoot" → **Tech Support**
- Meeting + "post sales" / "go-live" → **Post Sales**
- Meeting with Microsoft PG/Engineering (no customer) + blocker context → **Blocker Escalation**
- Meeting with Microsoft PG/Engineering (no customer) + project keyword → **Architecture Design Session** or **PoC/Pilot** (internal engineering work)
- Internal-only meeting matching project keyword → **Internal**
- Customer meeting (generic, no keyword match) → **Customer Engagement**

### 2c. Sent Emails (PG/Engineering + Customer Architecture)

```
m365_list_emails(folder: "sent", startDate: "<target-date>", endDate: "<target-date+1>", limit: 50)
```

**Include only emails matching these criteria:**

1. **Product Group / Engineering emails:**
   - Recipient domain is `@microsoft.com` AND
   - Recipient is NOT in your direct team (config.user known team members) AND
   - Subject matches a project keyword from any `crm-mapping.json`

2. **Customer technical emails:**
   - Recipient domain matches a known customer domain AND
   - This is a project-related thread (subject matches keyword)

**Exclude everything else.** No internal team emails, no SSP coordination, no HR/admin.

**For each qualifying email, extract:**
- Subject, recipients (names + emails), date.
- Classify: "Engineering Coordination" or "Customer Communication".
- Map to customer/project via subject keywords and recipient domains.

**If zero qualifying emails on the target date** → skip, no entry for this source.

### 2d. SSP Teams Chat (Ad-hoc Calls & Technical Discussion)

Ad-hoc Teams calls between SE and SSP are a major activity source that doesn't appear
on the calendar. These are captured by scanning 1:1 and relevant group chats with
known SSPs.

**For each SSP in `config.core_ssps`:**

1. **Find chat ID.** Use `m365_create_chat_by_email(email: "<ssp-email>")` to get the
   1:1 chat ID. Cache this — the chat ID is stable.

2. **Pull messages for target date:**
   ```
   m365_list_chat_messages(chatId: "<chat-id>", limit: 50)
   ```
   Filter to messages where `createdDateTime` falls within the target date (in user's
   timezone). Paginate with `skipToken` if needed to cover the full day.

3. **Detect ad-hoc calls.** Messages with `content: "<systemEventMessage/>"` and
   `type: "unknownFutureValue"` are Teams call events (call started/ended). Count
   pairs of consecutive systemEventMessages as one call. Each pair typically has
   timestamps ~seconds apart (start + end).

4. **Extract technical context.** From the non-system text messages on the same date:
   - Filter OUT scheduling chatter: messages that are purely coordination like
     "זמין?", "פנוי?", "available?", "בפגישה", "שניה", "ok", "👍", single emoji,
     or messages shorter than 10 characters with no technical content.
   - KEEP messages that contain technical discussion: questions about architecture,
     infrastructure, pricing, customer requirements, PG coordination, etc.
   - Preserve original language (Hebrew, English, mixed).

5. **Map to customer/project:**
   - Use the SSP → customer mapping from `config.core_ssps[].customers[]`.
   - If the SSP covers multiple customers (rare), match by scanning message content
     against each project's `subject_keywords`.
   - If ambiguous → assign to the SSP's primary customer. Flag in the log.

6. **Summarize topics.** Group the technical messages into topics:
   - Extract the key nouns/concepts discussed (e.g., "SRv6", "NAT GW", "SSD",
     "ephemeral storage", "LB usage").
   - Note if any messages reference forwarded emails, documents, or PG contacts.
   - Count: number of ad-hoc calls, number of substantive messages.

**Also scan relevant group chats** registered in `crm-mapping.json`:
- If a project has a `group_chat_ids[]` array, scan those too.
- Apply the same date filter and technical content extraction.
- Group chats with SSP + PG engineers are especially valuable (e.g., HSASE-AZURE-*).

**If zero calls AND zero technical messages on the target date** → skip, no entry
for this source.

**Important filtering rules:**
- Only scan chats with SSPs mapped to active customers. Don't scan random chats.
- Messages from the SSP AND from the SE (you) both count as evidence.
- A day with calls but no text messages → still log as "ad-hoc call(s)" with
  no topic detail. The call itself is evidence of customer engagement.
- A day with technical text messages but no calls → still log. SSP text coordination
  is also customer work (e.g., answering SSP questions about the design async).

---

## Step 3: Aggregate and Classify

For each `{ customer, project, target_date }` combination that has at least one
piece of evidence:

### 3a. Merge Evidence

Combine all evidence into a single daily entry:

```
evidence = {
  repo_commits: [...],       // from 2a
  calendar_events: [...],    // from 2b
  sent_emails: [...],        // from 2c
  ssp_chat: {                // from 2d
    calls: N,                // count of ad-hoc Teams calls
    topics: [...],           // extracted technical topics
    messages: [...],         // substantive messages (filtered)
    ssp_name: "...",         // SSP name
    chat_sources: [...]      // which chats contributed (1:1, group names)
  }
}
```

### 3b. Determine Task Category

Match evidence against the **auto-classify signals** from the CRM Task Categories
table above. Use the **dominant signal** with this priority:

| Priority | Signal | Category |
|---|---|---|
| 1 | Workshop event (>2 hours, multiple attendees, "workshop" keyword) | Workshop |
| 2 | Customer meeting with "design"/"architecture" keyword | Architecture Design Session |
| 3 | Customer meeting with "poc"/"pilot" keyword | PoC/Pilot |
| 4 | Engineering escalation email (PG coordination on blocker) | Blocker Escalation |
| 5 | SSP chat with "design"/"architecture" topics + calls | Architecture Design Session |
| 6 | SSP chat with "poc"/"pilot"/"testing" topics + calls | PoC/Pilot |
| 7 | "demo"/"showcase" keyword in meeting or commits | Demo |
| 8 | "rfp"/"rfi" keyword | RFP/RFI |
| 9 | "pricing"/"negotiate"/"commercial" keyword | Negotiate Pricing |
| 10 | "partner"/"isv" keyword | New Partner Request |
| 11 | Repo commits dominant prefix → match prefix to category (see 2a table) | Varies |
| 12 | Internal-only meeting matching project keyword (no customer attendees) | Internal |
| 13 | SSP chat (calls or technical messages, no other keyword match) | Customer Engagement |
| 14 | Customer meeting (generic, no keyword match) | Customer Engagement |
| 15 | Engineering emails only (no meeting, no repo) | Architecture Design Session |
| 16 | Project's `default_activity_type` from crm-mapping.json | Fallback |

**If multiple categories are equally strong** (e.g., 10 design commits + a POC meeting),
use the project's `default_activity_type` as tiebreaker.

**The `**Type:**` line in activity-log.md must use the exact CRM label** (e.g.,
"Architecture Design Session", not "Design") so `/crm-activity-sync` can map it
directly to the `msp_taskcategory` value without ambiguity.

### 3c. Generate Summary

Write a concise 2–4 sentence summary combining all evidence:

**Template:**
```
{Activity-type-verb} for {project-display-name} — {main topics from repo commits and/or meetings}.
{If SSP calls: "{N} ad-hoc call(s) with SSP ({name}). Topics: {topic1}, {topic2}."}
{If engineering emails: "Coordinated with {PG-team} on {topic}."}
{If meetings: "{N} meeting(s) with {customer/internal/PG}."}
{Commit count if repo work: "{N} commits."}
```

**Example with SSP calls:**
```
Design work for SASE — SRv6 feasibility analysis, NAT GW topology,
ephemeral storage assessment. 4 ad-hoc calls with SSP (Kobi Shitrit).
Coordinated with Azure Networking PG (Brian Lehr) on SRv6 support.
1 email to PG. 3 commits.
```

---

## Step 4: Idempotency Check

Before writing, check if `activity-log.md` already has an entry for this date:

```bash
grep -c "^## <target-date>" ~/customer-engagements/{customer}/projects/{project}/activity-log.md
```

If found → skip this entry. Report: "Activity for {customer}/{project} on {date} already logged."

**Override:** If the user explicitly says "re-log" or "update", replace the existing
entry for that date (find the `## <date>` header, delete everything until the next
`## ` header or `---` separator, insert the new entry).

---

## Step 5: Write activity-log.md

### File Format

```markdown
# Activity Log — {Customer Display Name} / {Project Display Name}

## 2026-04-23

**Type:** PoC/Pilot
**Sources:** repo (3 commits), ssp-chat (4 calls, 8 messages), email (1 PG thread)

### Repo Work
- 3 commits in ~/SASE: secrets management design (area 12), SKU families recommendation
- Prefix breakdown: design (2), docs (1)

### SSP Coordination
- 4 ad-hoc calls with Kobi Shitrit (SSP)
- Topics discussed:
  - SRv6 feasibility in Azure — official position is it won't happen, need to communicate to CheckPoint
  - NAT GW topology — 2 per tenant (1 mgmt + 1 egress)
  - Ephemeral SSD — 30GB sufficient, no extra SSD needed
  - Load Balancer role — clarification on what it's used for (not E-W, not N-S, not egress)
- Also: coordinated PG outreach to Brian Lehr re SRv6

### Engineering Coordination
- Email to blehr@microsoft.com (Azure Networking PG): SRv6 requirements for SASE

### Summary
Design work for SASE — SRv6 feasibility analysis, NAT GW topology,
ephemeral storage assessment, LB role clarification. 4 ad-hoc calls with SSP
(Kobi Shitrit). Coordinated with Azure Networking PG on SRv6 support. 3 commits.

---

## 2026-04-21

**Type:** Architecture Design Session
**Sources:** repo (21 commits)

### Repo Work
- 21 commits in ~/SASE: PoP topology, traffic flow diagrams (6 scenarios),
  HA/failover, service functions, VPP/DPDK design, inter-PoP connectivity,
  addressing, control plane proposals
- Prefix breakdown: design (18), docs (3)

### Summary
Full design sprint for SASE — 10 architecture areas with draw.io diagrams.
Covered PoP topology (4-subnet model), 6 traffic flow scenarios, HA/failover
model (4 failure domains), service function chain model, VPP/DPDK and SRv6
fabric design. 21 commits.

---
```

### Writing Rules

1. **Create file if missing.** If `activity-log.md` doesn't exist, create it with the header:
   ```markdown
   # Activity Log — {Customer Display Name} / {Project Display Name}
   ```

2. **Prepend new entries.** Insert after the `# Activity Log` header line, before any existing `## ` date entry. Most recent date first.

3. **Separator.** Add `---` between date entries for readability.

4. **Commit to git.** After writing:
   ```bash
   cd ~/customer-engagements/{customer}
   git add projects/{project}/activity-log.md
   git commit -m "activity-log: {date} — {activity-type} ({sources summary})"
   ```

---

## Step 6: Report

After processing all target dates and all customer/projects, present a summary:

```
📋 Daily Activity Log — April 22, 2026

Logged:
  ✅ CheckPoint / SASE — Design (21 repo commits)
  ✅ Clal Insurance / AI Search — Meeting Call (1 meeting, 14:00-15:30)

Skipped (already logged):
  ⏭️ CheckPoint / SASE — April 21 already in activity-log.md

No activity detected:
  ⚪ Sapiens / Digital-AI — no commits, no meetings, no emails

No CRM mapping (logged but won't sync):
  ⚠️ Sapiens — run /crm-activity-sync setup to add CRM mapping
```

---

## Automation

When running as a scheduled automation (e.g., daily at 07:30):

1. Run for yesterday (or last workday).
2. Process all customers/projects.
3. Skip already-logged dates.
4. Send a Teams summary only if new entries were created.
5. No user interaction — fully automated.

**Automation prompt:**
```
Run /daily-activity-log for yesterday.
Process all customers. Skip already-logged dates.
If new entries were created, send a brief Teams summary.
If errors occur, include them in the summary.
```

---

## Edge Cases

| Case | Behavior |
|---|---|
| Repo has commits but project has no crm-mapping.json | Log anyway — activity-log.md is useful even without CRM |
| Calendar returns no events | Fine — log repo work only |
| M365 not signed in | Skip calendar + email. Log repo work only. Warn in report. |
| Multiple repos for one project | Merge all commits into one entry. List each repo path in the "Repo Work" section. |
| Repo has commits by someone else (pair programming) | `--author` filter ensures only user's commits are counted. If zero → skip. |
| Weekend date | Warn: "{date} is a weekend. Log anyway?" In auto mode: skip. |
| Empty day (no evidence from any source) | No entry created. Report as "No activity detected." |
| Very large commit count (>50) | Summarize at topic level, don't list individual commits. Show count only. |
| Commit message has no prefix | Use project's `default_activity_type`. In the entry, list as "general" prefix. |

---

## New User Adoption Guide

When this skill is installed by a new Clawpilot user, the following setup happens
automatically on first run (when `~/.copilot/crm-activity-sync/config.json` is
missing). This skill shares its config with `/crm-activity-sync`.

### First-Run Checklist

 Prompt: "Run `/crm-activity-sync`  it sets up yourfirst 
   profile, customers, and CRM mappings that this skill depends on."

 Guide user through customer discovery:
   - Scan recent calendar for external attendee domains
   - Ask user to confirm which are customers
   - Create `customer-engagements/` folder structure

 Needed for calendar + email + Teams chat scanning.
   Test with `m_m365_status`. Sign in if needed.

 For each customer project with a local
   git repo, register via `/daily-activity-log add-repo`.

 For customer-specific Teams groups
   with SSPs, register via `/daily-activity-log add-group-chat`.

### What Gets Personalized

| Item | Where stored | Notes |
|---|---|---|
| Git author email | Auto-detected from `git config user.email` per repo | No config needed |
| Customer folders | `~/customer-engagements/` | Created during `/crm-activity-sync` setup |
| Work repos | `crm-mapping.json` per customer | Registered manually |
| SSP chat IDs | `crm-mapping.json` per customer | Resolved via `m365_create_chat_by_email` |
| Group chat IDs | `crm-mapping.json` per project | Registered manually |
| Subject keywords | `crm-mapping.json` per project | Set during setup, editable |
| Manager email (for filtering) | `config.json` | Auto-discovered via M365 Graph |
| Work week days | `config.json` | Israel: Sun-Thu, configurable |

### Sharing This Skill

To share with another SE:
1. Give them the `SKILL.md` files for both `/daily-activity-log` and `/crm-activity-sync`
2. They install in their Clawpilot (`~/.copilot/m-skills/`)
3. On first run, the setup flow personalizes everything for their identity, customers,
   and  no manual editing of SKILL.md neededrepos 
4. Examples in this file use "RBH" / "CheckPoint" / " these are illustrativeKobi" 
   only, not hardcoded logic
