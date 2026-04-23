---
name: capture-meeting
description: "Process a completed Teams meeting into structured notes with action items appended to followups.md. Triggers include: 'capture meeting', 'meeting notes', 'what happened in my meeting', 'summarize meeting', 'meeting recap', 'log meeting', 'capture last meeting', or any request to document what was discussed in a past customer meeting."
---

# /capture-meeting — Post-Meeting Capture

Process a completed Microsoft Teams meeting into structured notes with discussion
summary, key decisions, and action items. Action items are appended to the
customer's followups.md. Notes and updated follow-ups are committed to the
customer engagement repo.

## Core Principles

- **Never fabricate content.** Only include information retrieved from M365 tools or the local customer repo. If a source returned nothing, say so explicitly — do not invent discussion points, decisions, or action items.
- **Preserve source language.** Section headings are always English. Content (meeting notes, transcript excerpts, action items) stays in its original language — do not translate Hebrew to English or vice versa. Preserve Hebrew text as-is.
- **Graceful degradation.** Every data source can fail independently. The notes must still be useful even when some sources return nothing. Note what's missing so the user knows what to check manually.
- **Best-effort customer detection.** Use attendee email domains as the primary signal, then folder scanning, then meeting subject. Suggest when ambiguous, ask when unknown — never guess a customer name.
- **Action item extraction priority.** Prefer facilitator notes `actionItems[]` (structured, high-confidence) over transcript-extracted items (inferred, lower-confidence). When both sources produce the same action item, keep the facilitator notes version.
- **Append, not overwrite.** When writing action items to followups.md, preserve the existing header row and separator. Append new rows after the last existing row in the `## Open` table. Never truncate or replace existing content.
- **Commit immediately.** After writing notes and updating followups.md, commit to git so changes are versioned and findable.

## Step 1: Identify the Target Meeting

Look **backward** at past meetings (past 7 days). The user can name a specific meeting or say "my last meeting."

**If the user names a specific meeting:**

1. Call `m365_list_meetings(startDate: "{7-days-ago}", endDate: "{now}", limit: 15)`.
2. Match the user's description against meeting subjects (case-insensitive, partial match).
3. If multiple matches, present a numbered list and ask the user to pick.

**If the user says "my last meeting" or similar:**

1. Call `m365_list_meetings(startDate: "{7-days-ago}", endDate: "{now}", limit: 5)`.
2. Sort by end time descending and present the most recent meeting.
3. Confirm with the user before proceeding.

**If no meetings are found:**

- Report: "No meetings found in the past 7 days. Try specifying a broader date range or a meeting subject."
- Stop and wait for user input.

Once confirmed, extract the meeting's `id`, `subject`, `start`, `end`, `joinUrl`, and `organizer`.

**If the meeting has no `joinUrl`:**

- Warn the user: "This meeting has no Teams join URL. Transcript and facilitator notes are unavailable — capture will be limited to event details and attendees only."
- Continue with event-only capture (skip Steps 3a and 3b, proceed to Step 3c).

## Step 2: Detect the Customer

Extract the customer from the meeting context using this priority chain:

1. **Attendee email domains** — From the event attendees, identify email domains that are NOT your organization's internal domain (configure your own internal domain, e.g. `@yourcompany.com`). External domains are the strongest customer signal.
2. **Folder scanning** — Run `ls ~/customer-engagements/` and match external domains or company names against existing folder names.
3. **Meeting subject** — Look for company names in the meeting subject line.
4. **User prompt** — If the user mentioned a customer name in their request, use that.

**Resolution rules:**

- If exactly one external domain matches a folder → use that customer.
- If multiple external domains → present the options and ask the user.
- If no external domain but the subject contains a known folder name → use that, confirm with the user.
- If no match at all → ask the user for the customer name.
- If the customer has no folder in `~/customer-engagements/` → offer to chain `/customer-repo` to scaffold one, then continue.

Set `{slug}` to the customer folder name (lowercase, hyphenated).

## Step 3: Pull Meeting Data

Gather data from three sources. Each call is independent — a failure in one does not block the others.

### 3a. Facilitator Notes (Copilot)

```
m365_get_facilitator_notes(joinUrl: "{meeting-join-url}")
```

- Extract `meetingNotes[]` (title, text, subpoints) and `actionItems[]` (title, text, owner).
- The `actionItems[]` array is the **primary** source for action items — it is structured and high-confidence.
- If unavailable → note "Facilitator notes unavailable" in the meeting notes. Continue with transcript only.

### 3b. Meeting Transcript

```
m365_get_transcript(joinUrl: "{meeting-join-url}")
```

- Returns `entries[]` with `{ start, speaker, text }` for each utterance.
- Used for: building the discussion summary, extracting action items as a fallback when facilitator notes are unavailable, and preserving speaker attribution.
- If unavailable → note "No transcript available" in the meeting notes. Continue with facilitator notes only.
- If both transcript and facilitator notes are unavailable → produce event-only notes (attendees, meeting info) and inform the user that content-rich capture requires at least one source.

**Transcript quality note:** Hebrew-language transcript segments may have lower accuracy. Preserve them as-is — do not attempt to correct, paraphrase, or hallucinate corrections for unclear segments. If quality is visibly poor, add a note: "⚠️ Transcript quality may be reduced for Hebrew segments."

### 3c. Event Details and Attendees

```
m365_get_event(eventId: "{meeting-id}")
```

- Extract attendees list (name, email, response status).
- This is the **required** data source — if it fails, stop and report: "Could not load meeting details for event {id}. Cannot proceed without the base event."

For external attendees, optionally enrich with organizational context:

```
m365_search_people(query: "{attendee-name-or-email}")
```

- Extract job title, department, and company for each attendee.
- If lookup fails for an attendee → list them with email only, no role.

## Step 4: Generate Structured Meeting Notes

Assemble the captured data into structured notes using the template below.

**Discussion summary rules:**

- If transcript is available: summarize into 5–10 key discussion points, preserving speaker attribution (e.g., "Alice raised the topic of…").
- If only facilitator notes are available: use `meetingNotes[]` as the discussion summary.
- If neither is available: note "No meeting content captured — transcript and facilitator notes were both unavailable."
- Do **not** fabricate discussion points. Every summary point must trace to a specific transcript entry or facilitator note.

**Action item extraction rules:**

- **Source 1 (preferred):** `actionItems[]` from facilitator notes — already structured with title, text, and owner.
- **Source 2 (fallback):** Scan transcript entries for commitments, promises, and assigned tasks. Look for phrases like "I'll do…", "Can you…", "Action item:", "Let's follow up on…", "We need to…".
- **Deduplication:** If an action item appears in both sources, keep the facilitator notes version (more structured).
- Extract action items from both English and Hebrew text. Do not translate — preserve the original language.

### Content Language Rules

- All section headings (`## Discussion Summary`, `## Action Items`, etc.) → English.
- Content within sections → preserve the original language as-is.
- Action items → extract from both English and Hebrew text. Do not translate.
- Attendee names → preserve original form.

## Step 5: Append Action Items to followups.md

1. **Compute the path:** `~/customer-engagements/{slug}/followups.md`

2. **If the file exists:**
   - Read the file contents.
   - Locate the `## Open` section and its markdown table.
   - Preserve the existing header row (`| Action | Owner | Due | Status |`) and separator row (`|--------|-------|-----|--------|`).
   - Append new action item rows **after the last existing row** in the `## Open` table.
   - Each new row: `| {action} | {owner} | {due or TBD} | 🔴 Open |`

3. **If the file does not exist:**
   - Create it using the canonical format:

   ```markdown
   # Follow-ups — {customer-name}

   ## Open

   | Action | Owner | Due | Status |
   |--------|-------|-----|--------|
   | {action} | {owner} | {due or TBD} | 🔴 Open |

   ## Closed

   | Action | Owner | Due | Status |
   |--------|-------|-----|--------|
   ```

4. **Deduplication:** Before appending, scan existing `## Open` rows. If a new action item matches an existing row's Action text (fuzzy, case-insensitive), skip it to avoid duplicates.

5. **If no action items were found in either source:** Skip this step. Do not modify followups.md. Note in the meeting notes: "No action items identified."

## Step 6: Write Files and Commit

1. **Compute the notes output path:**
   ```
   ~/customer-engagements/{slug}/meetings/{YYYY-MM-DD}-{subject-slug}.md
   ```
   Where `{YYYY-MM-DD}` is the meeting date, and `{subject-slug}` is the meeting subject lowercased, spaces replaced with hyphens, special characters removed, truncated to 60 characters.

2. **Check if the notes file exists** — If it does, read it and ask the user:
   - "Meeting notes already exist for this meeting. Overwrite, append, or skip?"

3. **Create the meetings directory if needed:**
   ```bash
   mkdir -p ~/customer-engagements/{slug}/meetings
   ```

4. **Write the meeting notes** using the `write` tool.

5. **Write the updated followups.md** (if action items were appended in Step 5).

6. **Commit to git:**
   ```bash
   cd ~/customer-engagements/{slug}
   git add meetings/{YYYY-MM-DD}-{subject-slug}.md followups.md
   git commit -m "capture-meeting: {customer-name} — {meeting-subject}"
   ```

   If the repo is not a git repo or the commit fails, inform the user but do not fail the skill — the files are still written.

## Error Handling

Every m365_* tool call can fail. Handle each failure individually so a single unavailable source doesn't block the entire capture.

| Tool Call | Failure Behavior |
|-----------|-----------------|
| `m365_list_meetings` returns no meetings | Report "No meetings found in the past 7 days." Stop and ask user for clarification. |
| `m365_get_event` fails | Report "Could not load meeting details for event {id}." Stop — cannot proceed without the base event. |
| `m365_get_transcript` fails | Note "No transcript available" in the Discussion Summary section. Continue with facilitator notes or event-only capture. |
| `m365_get_facilitator_notes` fails | Note "Facilitator notes unavailable" in the notes. Continue with transcript only. |
| `m365_search_people` fails for an attendee | List the attendee with email only, no role/title. Continue. |
| `m365_search_emails` fails or returns empty | Note "Email context unavailable" in the notes. Continue. |
| Customer folder not found in `~/customer-engagements/` | Offer to run `/customer-repo` to scaffold the folder. If user declines, ask where to write the notes. |
| `git commit` fails | Inform the user the notes were written but not committed. Do not fail the skill. |
| Meeting has no `joinUrl` | Cannot retrieve transcript or facilitator notes. Degrade to event-only capture: attendees, meeting info, and any content from the event body. Warn the user about the limitation. |
| Transcript quality poor for Hebrew | Preserve content as-is. Add note: "⚠️ Transcript quality may be reduced for Hebrew segments." Do not hallucinate corrections. |
| Both transcript and facilitator notes unavailable | Produce event-only notes (meeting info, attendees). Note: "No meeting content captured — both sources were unavailable." |

## Output Template

```markdown
# Meeting Notes: {subject}

**Date:** {YYYY-MM-DD} {HH:MM}–{HH:MM} ({timezone})
**Customer:** {customer-name}
**Attendees:**
- {name} ({email}) — {role/title, if known}
- {name} ({email}) — {role/title, if known}

## Discussion Summary

{5–10 key discussion points summarized from transcript and/or facilitator notes.
Each point preserves speaker attribution where available.}

1. {Speaker} discussed {topic}…
2. {Speaker} raised {concern/update}…
…

{If no transcript or facilitator notes: "No meeting content captured — transcript and facilitator notes were both unavailable."}

## Key Decisions

{Decisions made during the meeting. Each decision includes who made it and any
conditions or caveats.}

- {Decision description} (decided by {who})

{If no decisions identified: "No key decisions identified."}

## Action Items

| Action | Owner | Due | Source |
|--------|-------|-----|--------|
| {action description} | {owner} | {date or TBD} | {Facilitator Notes / Transcript} |

{If no action items: "No action items identified."}

---
*Generated by /capture-meeting on {timestamp}*
```
