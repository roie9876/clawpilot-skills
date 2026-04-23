---
name: followups
description: "Surface open action items and unresponded customer emails across all customer engagements. Triggers include: 'followups', 'open items', 'what's pending', 'action items', 'follow up', 'what do I need to do', 'pending actions', 'unresponded emails', or any request to see outstanding work across customers."
---

# /followups — Cross-Customer Follow-up Tracker

Scan all customer engagement repos for open action items and identify unresponded
customer emails via Microsoft 365. Presents a unified view grouped by customer so
nothing falls through the cracks.

## Core Principles

- **Never fabricate content.** Only include action items found in followups.md files and emails retrieved from M365 tools. If a source is unavailable, say so explicitly — do not invent action items or email threads.
- **Preserve source language.** Section headings are always English. Content (action item text, email subjects) stays in its original language — do not translate Hebrew to English or vice versa. Preserve Hebrew text as-is. Extract action items from both English and Hebrew text.
- **Graceful degradation.** Every data source can fail independently. The report must still be useful even when some sources return nothing. Note what's missing so the user knows what to check manually.
- **Read-only operation.** This skill never writes to any file. It reads followups.md, stakeholders.md, and queries M365 — but modifies nothing on disk. No git operations.
- **Cross-platform paths.** All paths use `~` prefix (e.g., `~/customer-engagements/`) for portability across environments.

## Step 1: Determine Scope

Decide whether to scan all customers or a specific one.

**Default: ALL customers**

If the user did not name a specific customer (e.g., just "/followups"):

1. Run `ls ~/customer-engagements/` to list all customer folders.
2. Set `{slugs}` to the full list of folder names.
3. If the directory is empty or does not exist → report "No customer engagement folders found at ~/customer-engagements/. Run /customer-repo to create one." and stop.

**Single customer mode:**

If the user names a specific customer (e.g., "/followups Contoso"), use the 4-tier detection chain to resolve the customer:

1. **Folder name match** — Check if the user's input (lowercased, hyphenated) matches an existing folder in `~/customer-engagements/` exactly.
2. **Folder scan** — Run `ls ~/customer-engagements/` and fuzzy-match the user's input against folder names (case-insensitive, partial match, with/without hyphens).
3. **Meeting subject** — If no folder match, check recent meeting subjects for the customer name to confirm they exist.
4. **User prompt** — If still ambiguous, present the closest matches and ask the user to pick, or confirm the intended customer.

If the customer folder is not found → report "No folder found for '{customer}' in ~/customer-engagements/. Did you mean one of these: {closest matches}?" and stop.

Set `{slugs}` to the single matched folder name.

## Step 2: Scan followups.md Files

For each `{slug}` in `{slugs}`:

1. **Read the file:** `~/customer-engagements/{slug}/followups.md`
2. **Locate the `## Open` section** and parse the markdown table rows.
3. **Collect rows where Status is `🔴 Open`.** Extract the Action, Owner, and Due columns.
4. **Attribute each item** with the customer name derived from `{slug}` (convert hyphens to spaces, title-case).

**Edge cases:**

- **File missing** → Skip this customer. Record: "{customer}: followups.md not found."
- **File contains only placeholder HTML comments** (e.g., `<!-- Describe the action item -->`) → Treat as empty. Record: "{customer}: no open action items."
- **No `## Open` section** → Skip this customer. Record: "{customer}: no Open section in followups.md."
- **`## Open` section exists but table is empty or has only the header** → Record: "{customer}: no open action items."

## Step 3: Find Unresponded Customer Emails

For each `{slug}` in `{slugs}`:

1. **Extract the customer email domain:** Read `~/customer-engagements/{slug}/stakeholders.md`. Parse the stakeholder table and extract email addresses from the Email column. Identify the external domain (e.g., `contoso.com` from `alice@contoso.com`). Use the first non-internal domain found.

2. **Search for recent inbound emails from the customer:**

   ```
   m365_search_emails(query: "from:{customer-domain}", folder: "inbox", startDate: "{14-days-ago}", limit: 20)
   ```

   This returns recent emails received from the customer domain.

3. **Load recent sent emails:**

   ```
   m365_list_emails(folder: "sent", startDate: "{14-days-ago}", limit: 50)
   ```

4. **Cross-reference to find unresponded emails:**
   - For each inbound email, check if there is a sent email with a matching `conversationId`.
   - If no matching `conversationId` is found, fall back to subject-line matching (case-insensitive, ignoring `Re:` / `Fwd:` prefixes).
   - Emails that have no matching sent reply are flagged as **unresponded**.

   > **Note:** This is a heuristic approach. There is no direct "unreplied" API in Microsoft Graph. Responses sent from other clients, shared mailboxes, or delegated accounts may not be detected. The results are best-effort.

5. **Collect unresponded emails** with: sender name, subject, received date.

**Edge cases:**

- **stakeholders.md missing** → Skip email check for this customer. Record: "{customer}: stakeholders.md not found — skipped email check."
- **stakeholders.md has no email addresses or only placeholder comments** → Skip email check. Record: "{customer}: no stakeholder emails found — skipped email check."
- **m365_search_emails fails** → Skip email check for this customer. Record: "{customer}: email search failed — {error}."
- **m365_list_emails fails** → Cannot cross-reference replies. Report inbound emails without reply status. Record: "{customer}: sent email lookup failed — showing all recent inbound emails."
- **No inbound emails found** → Record: "{customer}: no recent inbound emails."

## Step 4: Present Results

Assemble the collected data into a unified report grouped by customer.

**Summary counts first:**

Show a quick overview at the top so the user can see the big picture at a glance.

**Then detail per customer:**

For each customer that has at least one open action item or unresponded email, show:
1. Open action items table
2. Unresponded emails list

Customers with neither open items nor unresponded emails are omitted from the detail section but counted in the summary.

### Content Language Rules

- All section headings → English.
- Action item text, email subjects → preserve in original language (English or Hebrew). Do not translate.
- Customer names → use the display name derived from the folder slug.

## Error Handling

| Failure Mode | Behavior |
|-------------|----------|
| `~/customer-engagements/` directory missing or empty | Report "No customer engagement folders found at ~/customer-engagements/." Stop. |
| `followups.md` missing for a customer | Skip that customer's action items. Note "{customer}: followups.md not found" in the report. |
| `followups.md` has no `## Open` section or is placeholder-only | Treat as zero open items. Note in report. |
| `stakeholders.md` missing for a customer | Skip email check for that customer. Note "{customer}: skipped email check — no stakeholders.md." |
| `stakeholders.md` has no parseable email addresses | Skip email check for that customer. Note "{customer}: no stakeholder emails found." |
| `m365_search_emails` fails or returns error | Skip email check for that customer. Note "{customer}: email search failed." Continue with other customers. |
| `m365_list_emails` fails or returns error | Cannot determine reply status. Show inbound emails without unresponded filtering. Note the limitation. |
| Single customer not found in `~/customer-engagements/` | Report "No folder found for '{name}'." Suggest closest matches if available. Stop. |
| All customers scanned but none have open items or emails | Report "🎉 All clear — no open action items or unresponded emails found across {N} customers." |

## Output Template

```markdown
# 📋 Follow-up Report

**Generated:** {timestamp}
**Scope:** {All customers | {customer-name}}
**Customers scanned:** {N}

## Summary

- **Open action items:** {total-count} across {customer-count} customers
- **Unresponded emails:** {total-count} across {customer-count} customers
- **Customers with no pending items:** {count}

{If any customers had errors, list them here:}
- ⚠️ {customer}: {error-note}

---

## {Customer Name}

### Open Action Items

| Action | Owner | Due | Status |
|--------|-------|-----|--------|
| {action text} | {owner} | {due date} | 🔴 Open |
| {action text} | {owner} | {due date} | 🔴 Open |

### Unresponded Emails (Last 14 Days)

- **{sender-name}** — "{email-subject}" — received {YYYY-MM-DD}
- **{sender-name}** — "{email-subject}" — received {YYYY-MM-DD}

---

## {Customer Name 2}

### Open Action Items

{same format as above}

### Unresponded Emails (Last 14 Days)

{same format as above}

---

{Repeat for each customer with open items or unresponded emails.}

*Generated by /followups on {timestamp}*
```
