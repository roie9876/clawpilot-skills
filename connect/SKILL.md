---
name: connect
description: "Prepare and fill your Microsoft 1:1 Connect with your manager. Reads past Connect history for tone, gathers accomplishments from M365 (emails, meetings, Teams, CRM, customer repos), drafts content, and fills the form on v2.msconnect.microsoft.com via browser automation. You review and submit. Triggers include: 'connect', 'prepare connect', 'fill connect', 'manager connect', '1:1 connect', 'performance review', 'write my connect', or any request to prepare the semi-annual Connect check-in."
---

# /connect — Microsoft 1:1 Manager Connect

Prepare and fill your semi-annual Microsoft Connect (employee-manager check-in) on
v2.msconnect.microsoft.com. The skill gathers your accomplishments from multiple
data sources, reads your past Connects for tone and style, drafts all sections, and
fills the form via browser automation. You review and submit.

## Core Principles

- **Never fabricate accomplishments.** Only include information retrieved from M365 tools, CRM, customer repos, or the Kanban board. If a source is unavailable, note the gap — do not invent achievements.
- **Preserve source language.** Section headings follow the Connect form's English. Content (meeting notes, email excerpts, CRM descriptions) stays in its original language — do not translate Hebrew to English or vice versa.
- **Match the user's voice.** Read past Connects to learn the user's writing style, tone, and level of detail. The draft should sound like the user wrote it, not like an AI.
- **Graceful degradation.** Every data source can fail independently. The draft must still be useful even when some sources return nothing.
- **Never submit.** Fill the form and stop. The user always reviews and submits manually.
- **Default lookback: 6 months.** The reflection period defaults to the last 6 months from today. The user can override with a custom date range (e.g., "/connect from 2025-06-01 to 2025-11-30").

## URLs

| Page | URL |
|------|-----|
| Dashboard | `https://msconnect.microsoft.com/` |
| View History | `https://msconnect.microsoft.com/viewhistory/` |
| Current Connect (v2) | `https://v2.msconnect.microsoft.com/` |
| Past Connect (v2) | `https://v2.msconnect.microsoft.com/historygsmorag?connectid={id}&pernr={pernr}` |

## Connect Form Structure (v2 — 4 questions)

The current Connect form has these sections:

### Section 1: Reflect on the past
**Question:** "What results did you deliver, and how did you do it?"
- Covers both WHAT (results/impact) and HOW (behaviors/collaboration)
- Rich text editor — supports bold, bullets, paragraphs

### Section 2: Reflect on recent setbacks
**Question:** "Reflect on recent setbacks - what did you learn and how did you grow?"
- Growth mindset reflection
- Rich text editor

### Section 3: Plan for the future
**Question:** "What are your goals for the upcoming period?"
- Multiple numbered goals (Goal #1 through #N), each with a title and description
- Goals may carry over from the previous Connect with "Modified" labels
- Rich text editor per goal

### Section 4: Conversation starters (optional)
**Question:** "Choose any of these optional prompts to continue great conversations with your manager."
- Brief 1-15 word responses
- Skip this section unless the user asks for it

### Status lifecycle
Draft → In Review → Posted

**Important:** Only Draft status Connects are editable. If the current Connect is "In review" or "Posted", inform the user and offer to draft content to a file instead.

## Step 1: Read Past Connect History

Use browser-harness to read the user's past Connect for style reference.

1. **Navigate to history page:**
   ```
   browser-harness: goto("https://msconnect.microsoft.com/viewhistory/")
   ```

2. **Extract history links:**
   ```javascript
   // Get all Connect history links pointing to v2.msconnect
   Array.from(document.querySelectorAll('a'))
     .filter(a => a.href.includes('v2.msconnect'))
     .map(a => ({ text: a.textContent.trim(), href: a.href }))
   ```

3. **Read the most recent past Connect** — Navigate to the most recent history link and extract the full content:
   ```javascript
   // Extract all section headings and content
   document.querySelectorAll('h2, p, li, div.display-item')
   ```

4. **Store the past content** — Save the extracted text to use as style/tone reference when drafting. Pay attention to:
   - How achievements are phrased (bullet points vs. paragraphs)
   - Level of specificity (metrics, customer names, project names)
   - Use of bold for emphasis
   - Balance of WHAT (results) vs. HOW (behaviors)
   - How setbacks/learnings are framed (growth mindset language)
   - Goal structure (title + description pattern)

## Step 2: Check Current Connect Status

1. **Navigate to current Connect:**
   ```
   browser-harness: goto("https://v2.msconnect.microsoft.com/")
   ```

2. **Check status** — Look for the status indicator at the top of the page (Draft / In review / Posted).

3. **If not Draft:**
   - Inform the user: "Your current Connect is '{status}'. It's not editable."
   - Offer to draft the content as a markdown file instead, which the user can paste manually later.
   - If the user agrees, skip to Step 5 and output to file instead of browser.

4. **If Draft:** Read any existing content already filled in (the user may have started).

5. **Extract the reflection period dates** from the Connect header (e.g., "Reflection Period: Nov 11, 2024 - May 4, 2025"). Use these as the lookback window instead of the default 6 months.

## Step 3: Gather Accomplishment Data

Run these data collection steps in parallel where possible. Each source is independent — if one fails, continue with the rest.

### 3a. Calendar — Key Meetings & Engagements

```
m365_list_events(startDate: "{period_start}", endDate: "{period_end}", limit: 50)
```

- Identify recurring customer engagements, architecture sessions, POCs, hackathons
- Group by customer/theme
- Note significant one-off events (executive briefings, partner meetings, team offsites)
- If the API limits results, paginate or narrow by month

### 3b. Email — Customer Interactions & Milestones

```
m365_search_emails(query: "architecture OR POC OR migration OR deployment OR pilot", startDate: "{period_start}", endDate: "{period_end}", limit: 20)
```

Also search for:
- Emails with external domains (customer interactions)
- Sent emails with attachments (deliverables)
- Key project milestone keywords

Extract: customer names, project milestones, key decisions, deliverables sent.

### 3c. Customer Engagement Repos

```bash
ls ~/customer-engagements/
```

For each customer with a repo:
- Read `README.md` for engagement context
- List projects under `projects/`
- Read recent meeting notes from `meetings/`
- Check `followups.md` for completed items (evidence of delivery)
- Check `decisions/` for architectural decisions made

### 3d. CRM / MSX Data

Use the CRM tool to pull opportunities and milestones:

```bash
node ~/Documents/se-kanban-tracker/crm/run-tool.mjs list-milestones --status active
```

Also check:
```bash
node ~/Documents/se-kanban-tracker/crm/run-tool.mjs list-opportunities
```

Extract: deals progressed, milestones achieved, customer wins, pipeline contribution.

### 3e. Kanban Board — Completed Tasks

```bash
curl -s http://localhost:3456/api/tasks | jq '[.[] | select(.status == "done")]'
```

Extract: completed tasks with their descriptions and dates — evidence of execution.

### 3f. Teams Messages — Key Discussions

Search for significant contributions in Teams channels:

```
m365_search_chats(query: "architecture OR POC OR customer OR demo", limit: 20)
```

Look for: knowledge sharing, helping colleagues, cross-team collaboration evidence.

### 3g. Feedback Received

Check if there's feedback on the MS Connect feedback page:
```
browser-harness: goto("https://msconnect.microsoft.com/perspective/view")
```

Extract any feedback received during the period — useful for both "Reflect" and "Setbacks" sections.

## Step 4: Draft the Content

Using the gathered data and the past Connect as style reference, draft each section.

### Section 1: Reflect on the past

Structure the reflection as:
1. **Opening paragraph** — High-level summary of role and key impact theme (1-2 sentences)
2. **Key achievements** — Bullet points with bold lead-ins, each covering:
   - WHAT was delivered (specific result, customer, project)
   - HOW it was done (collaboration, innovation, technical depth)
3. **Closing paragraph** — Broader impact or role evolution narrative

**Style guidelines from past Connects:**
- Use bold for key phrases/achievements
- Be specific: name customers, projects, technologies
- Balance technical depth with business impact
- Show cross-team collaboration (ATU, STU, CSU, partners)
- 200-400 words typical length

### Section 2: Reflect on recent setbacks

Structure as:
1. **Challenge faced** — Honest description of a difficulty or gap
2. **Learning/growth** — What was learned and how it changed approach
3. **Bold key insight** — One-line takeaway in bold

**Guidelines:**
- Frame setbacks through a growth mindset lens
- Connect the learning to a concrete action or change
- Keep it authentic — not everything needs to be a hidden strength
- 50-150 words typical length

### Section 3: Plan for the future (goal tweaks)

For each existing goal:
1. Read the current goal title and description
2. Based on gathered data, suggest specific tweaks:
   - Update descriptions to reflect current priorities
   - Add new customer engagements or projects as examples
   - Adjust targets based on what's been achieved
3. If a goal is no longer relevant, flag it for the user

If new goals are needed (based on current work patterns), suggest them.

**Guidelines:**
- Keep goal titles concise and measurable
- Descriptions should have 3-5 bullet points
- Include specific customer names, technologies, certifications
- Align with SE North Star focus areas (AKS, AI Engineering, GitHub, Low-Code)

## Step 5: Fill the Form via Browser

**IMPORTANT:** Only fill if the Connect status is Draft.

1. **Navigate to the Connect form:**
   ```
   browser-harness: goto("https://v2.msconnect.microsoft.com/")
   ```

2. **Wait for the page to fully load** — the v2 app is a React SPA:
   ```python
   wait_for_load()
   import time
   time.sleep(5)  # Extra wait for React hydration
   ```

3. **Identify the rich text editors** — The Connect form uses rich text editors (likely contenteditable divs or a framework like Quill/ProseMirror/TipTap). Locate them:
   ```javascript
   // Find editable areas within each section
   document.querySelectorAll('[contenteditable="true"], [role="textbox"], textarea, .ql-editor, .ProseMirror, [class*="editor"]')
   ```

4. **For each section, click into the editor and type the content:**
   - Click on the editor area to focus it
   - Clear existing content if the user confirmed overwrite (otherwise append)
   - Type the drafted content using `type_text()` from browser-harness
   - For bold text, use Ctrl+B before and after the bold segment
   - For bullet points, use the toolbar button or keyboard shortcut

5. **After filling all sections, take a screenshot** and inform the user:
   ```
   screenshot("/Users/robenhai/Documents/Clawpilot/connect-draft.png")
   ```

6. **Do NOT click Submit/Save.** Tell the user: "Draft filled. Please review and submit when ready."

### Fallback: Output to File

If the Connect is not in Draft status, or browser automation fails:

1. Write the draft to a markdown file:
   ```
   ~/Documents/Clawpilot/connect-draft-{YYYY-MM}.md
   ```

2. Open it in Edge for the user to copy-paste:
   ```bash
   open -a "Microsoft Edge" ~/Documents/Clawpilot/connect-draft-{YYYY-MM}.md
   ```

3. Also display the content in the chat for easy copy-paste.

## Step 6: Present to User

After filling the form (or writing the file), summarize what was done:

```
✅ Connect draft filled for {Connect period name}

**Sources used:**
- Calendar: {N} meetings analyzed
- Email: {N} threads reviewed
- Customer repos: {list of customers}
- CRM: {N} opportunities / {N} milestones
- Kanban: {N} completed tasks

**Sections filled:**
1. Reflect on the past — {word count} words
2. Reflect on setbacks — {word count} words
3. Goals — {N} goals updated

⚠️ Please review the content before submitting.
The form is open at: https://v2.msconnect.microsoft.com/
```

## Error Handling

| Source | Failure Behavior |
|--------|-----------------|
| Browser can't reach msconnect | Inform user, offer to draft to file only |
| Connect is not in Draft status | Inform user, draft to file instead |
| Past Connect history empty | Skip style matching, use default professional tone |
| `m365_list_events` fails | Note "Calendar data unavailable" — continue with other sources |
| `m365_search_emails` fails | Note "Email data unavailable" — continue |
| Customer repos don't exist | Skip — note "No customer engagement repos found" |
| CRM tool fails | Skip — note "CRM data unavailable" |
| Kanban server not running | Skip — note "Kanban data unavailable" |
| Rich text editor not found | Fall back to file output, inform user |
| Form has changed structure | Take screenshot, show user, ask for guidance |

## Notes

- **Manager:** Ido Katz (idokatz@microsoft.com)
- **Previous managers:** Eli Cohen (ELCOHE), Shay Shahak (SHAYS), Avi Yoshi (AVIYOSHI)
- **Role:** SR SOLUTION ENGINEER CLOUD & A
- **pernr:** 1424046 (used in history URLs)
- **Browser automation:** Uses browser-harness (`~/.local/bin/browser-harness`), NOT Playwright MCP tools. Read `~/browser-harness/SKILL.md` and `helpers.py` for API.
- **Navigation:** Use `goto(url)` for in-tab navigation, `new_tab(url)` for new tabs. Always `wait_for_load()` after navigation.
