# Customer Skills — Overview

Personal Clawpilot skills for a customer-facing Solution Architect to streamline
day-to-day customer engagement work: meeting prep, note capture, follow-up tracking,
Azure Q&A, and customer repo scaffolding.

## Goal

Reduce the friction between Teams/Outlook/OneNote (where customer work happens) and
VS Code / git repos (where technical work happens) by using Clawpilot skills as the
glue. Clawpilot already has WorkIQ (M365 data) + filesystem + shell + Playwright —
this project adds the workflow layer on top.

## Architecture decisions

| # | Decision | Status |
|---|----------|--------|
| 1 | Skills live here (`~/customer-skills/`) as a git repo, symlinked into `~/.copilot/skills/` so Clawpilot loads them globally | ✅ decided |
| 2 | NOT contributing back to `first-party-skills/` in the Clawpilot repo — these are personal | ✅ decided |
| 3 | Build a **set of focused skills** (5–6), not one mega-skill | ✅ decided |
| 4 | Use Clawpilot **Automations** (not skills) for anything scheduled/recurring | ✅ decided |
| 5 | Shared convention: every customer repo has a `followups.md` with `## Open` / `## Closed` sections — this is the glue between skills | ✅ decided |
| 6 | Development methodology: **GSD** (Getting Stuff Done) — use `/gsd-new-project` to create roadmap, then `/gsd-plan-phase` + `/gsd-execute-plan` per skill | ✅ decided |

## Planned skills (V1 scope)

| Skill | Trigger | Purpose |
|-------|---------|---------|
| `/customer-repo` | "start a repo for Contoso" | Scaffold a customer repo with standard folder layout |
| `/meeting-prep` | "prep for my 3pm with Contoso" | Pull calendar + prior notes + follow-ups → produce prep brief |
| `/capture-meeting` | "capture notes from the Contoso meeting" | Pull Teams recap/transcript → append to meeting file + extract action items |
| `/followups` | "what do I owe customers?" | Grep `followups.md` across all customer repos + WorkIQ "emails awaiting reply" |
| `/azure-answer` | "Cosmos DB vCore cost in West Europe?" | Route through Azure MCP + verified pricing before answering |
| `/architecture` | "draw the ingestion arch for Contoso" | Generate diagram via `drawio-mcp-diagramming` or `excalidraw` into the repo |

### Deferred to V2
- Live meeting capture (Clawpilot can't join Teams live — post-meeting only)
- Automatic link-collection to SharePoint docs
- Cross-customer pattern detection ("you've answered this before for Acme")
- OneNote/Outlook **write-back** (reading is easy via WorkIQ; writing needs heavier automation)

## Customer data storage — PRIVACY-CRITICAL

Customer data (NDA'd content, PII, pricing, internal Microsoft data) **must never leave
Microsoft-managed systems**. Decision:

- **Single local-only monorepo**: `~/customer-engagements/`
- **Never pushed to any remote** (no `git remote add`, and a `pre-push` hook blocks push)
- **Backup** via OneDrive-for-Business folder sync (Microsoft-managed, NDA-safe) + Time Machine
- **Separation of concerns**:
  - `~/customer-skills/` (this repo) → public-shareable methodology/tooling
  - `~/customer-engagements/` (separate) → private customer data
- **Monorepo > per-customer-repos** because skills can search across customers
  (e.g., `/followups` greps all `*/followups.md`, `/azure-answer` can see prior answers)

## Customer repo layout (the glue)

Every customer folder inside `~/customer-engagements/` follows this layout.
Skills read/write these paths by convention:

```
~/customer-engagements/                    ← local-only git repo
├── README.md                              # Index of customers
├── _playbooks/                            # Cross-customer reference material
│   └── *.md
├── contoso/
│   ├── README.md                          # Engagement summary, goals
│   ├── stakeholders.md                    # People + roles + contact info
│   ├── followups.md                       # ## Open / ## Closed — action items
│   ├── meetings/2026-04-22-architecture-review.md
│   ├── decisions/2026-04-15-vector-store-choice.md
│   ├── architecture/*.drawio, *.excalidraw, *.md
│   ├── pricing/*.md
│   └── artifacts/                         # Customer-provided files
└── fabrikam/
    └── ...
```

**Safety belt** (set up when initializing `~/customer-engagements/`):
1. No remote configured (verify with `git remote` → empty)
2. `.git/hooks/pre-push` that exits 1 with "local-only" message
3. ~~Customer repo location~~ → **decided**: `~/customer-engagements/` (local-only monorepo)
2. ~~One repo per customer vs monorepo~~ → **decided**: monorepo with folders per customer
3. **Prep brief**: committed to git immediately, or scratch file until after the meeting?
4. **WorkIQ reality check** — `workiq` CLI returned `command not found` (exit 127) in terminal. It's only available from inside Clawpilot's session context (via the shim in `electron/sessions.ts`). **Next session must test WorkIQ from inside a Clawpilot chat**, not from a terminal. Gates the whole project.
5. **Language**: English only, or bilingual EN/HE?
6. **OneDrive sync path**: which OneDrive-for-Business folder should `~/customer-engagements/` live under (or be symlinked into) for cloud backup
## Open
- [ ] 2026-04-15 | Cosmos DB pricing for 1M docs/mo | promised {stakeholder}
- [ ] 2026-04-10 | FedRAMP status of Foundry WE | promised {stakeholder}

## Closed
- [x] 2026-04-05 | Sample Bicep for hub-spoke | sent Apr 8
```

## Meeting-prep skill (most detailed — see session notes)

**Inputs**: Outlook calendar (via WorkIQ), customer repo (filesystem), recent emails (WorkIQ)
**Output**: Prep brief written to `meetings/YYYY-MM-DD-{topic}.md` + chat summary
**Customer detection**: attendee email domain → slug lookup; fallback to ask
**Fallback**: if no repo exists, offer to chain into `/customer-repo`

See `skills/meeting-prep/DESIGN.md` (to be created) for full design.

## Open questions (need answers before V1)

1. **Customer repo location** — `~/Documents/customers/`, `~/GitHub/customers/`, or other?
2. **One repo per customer, or one monorepo with folders per customer?** Affects how skills search.
3. **Prep brief**: committed to git, or scratch file until after the meeting?
4. **WorkIQ reality check** — run `workiq ask -q "what's on my calendar today"` and confirm it returns attendees + meeting body (not just subject + time). This gates the whole project.
5. **Language**: English only, or bilingual EN/HE?

## Risks / constraints

- **WorkIQ data quality is the ceiling.** If WorkIQ can't pull transcripts/email threads, skills degrade to "paste it in."
- **Internal-only meetings** (all attendees from your own organization's domain) should be skipped by `/meeting-prep`.
- **Privacy**: briefs contain PII — never publish these skills to the Clawpilot marketplace.
- **Recurring syncs** create many meeting files — filename convention matters.

## Development workflow (GSD)

```
/gsd-new-project          # Create roadmap from this OVERVIEW.md
  └─ produces .planning/roadmap.md with phases

/gsd-plan-phase meeting-prep
  └─ researches + plans phase 1 (the riskiest skill)

/gsd-execute-plan
  └─ implements skill, writes tests, commits atomically
```

Each skill = one GSD phase. Start with `/meeting-prep` (highest value, highest risk —
validates WorkIQ is usable). Then `/customer-repo`, `/capture-meeting`, etc.

## Installation (once skills exist)

```bash
# Symlink each skill into the global Clawpilot skills folder
for skill in meeting-prep customer-repo capture-meeting followups azure-answer architecture; do
  ln -sfn ~/customer-skills/$skill ~/.copilot/skills/$skill
done
```

Or add a `scripts/install.sh` once the pattern stabilizes.

## References

- Clawpilot skills architecture: `~/m/docs/architecture/09-skills-and-marketplace.md`
- Skill format examples: `~/m/first-party-skills/loop/SKILL.md`, `~/m/first-party-skills/expense-report/SKILL.md`
- WorkIQ shim: `~/m/electron/sessions.ts` → `writeWorkIQShim()`
- GSD agents available: `gsd-roadmapper`, `gsd-planner`, `gsd-phase-researcher`, `gsd-executor`, `gsd-verifier`
