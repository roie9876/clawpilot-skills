#!/usr/bin/env bash
# verify-capture-meeting.sh — Validate capture-meeting/SKILL.md against tool registry,
# requirement specs, anti-patterns, and structural correctness.
# Exit 0 only if ALL checks pass.

set -uo pipefail

SKILL="capture-meeting/SKILL.md"
TOOL_DIR="$HOME/m/electron/m365"
PASS=0
FAIL=0

pass() { ((PASS++)); echo "  ✅ $1"; }
fail() { ((FAIL++)); echo "  ❌ $1"; }

echo "=== 1. Structural validity ==="

# 1a. File exists
if [[ -f "$SKILL" ]]; then
  pass "File exists at $SKILL"
else
  fail "File missing: $SKILL"
  echo "RESULT: $PASS passed, $FAIL failed"
  exit 1
fi

# 1b. YAML frontmatter present (starts and ends with ---)
if head -1 "$SKILL" | grep -q '^---$'; then
  if awk 'NR>1 && /^---$/{found=1; exit} END{exit !found}' "$SKILL"; then
    pass "YAML frontmatter delimiters present"
  else
    fail "YAML frontmatter missing closing ---"
  fi
else
  fail "File does not start with YAML frontmatter (---)"
fi

# 1c. name field
if grep -q '^name: capture-meeting' "$SKILL"; then
  pass "'name: capture-meeting' field present"
else
  fail "'name' field missing or wrong value"
fi

# 1d. description field
if grep -q '^description:' "$SKILL"; then
  pass "'description' field present"
else
  fail "'description' field missing"
fi

echo ""
echo "=== 2. Tool name accuracy ==="

# Extract all m365_* references from SKILL.md
SKILL_TOOLS=$(grep -oE 'm365_[a-z_]+' "$SKILL" | sort -u)

# Extract canonical tool names from registry
if [[ -d "$TOOL_DIR" ]]; then
  REGISTRY_TOOLS=$(grep -rh 'name: "m365_' "$TOOL_DIR"/*.ts 2>/dev/null \
    | sed 's/.*name: "//;s/".*//' | sort -u)
  REG_COUNT=$(echo "$REGISTRY_TOOLS" | wc -l | tr -d ' ')

  if [[ $REG_COUNT -eq 0 ]]; then
    fail "No m365_* tools found in $TOOL_DIR — cannot verify"
  else
    pass "Tool registry loaded: $REG_COUNT tools found"

    # Check each SKILL.md tool reference against the registry
    while IFS= read -r tool; do
      [[ -z "$tool" ]] && continue
      if echo "$REGISTRY_TOOLS" | grep -qx "$tool"; then
        pass "Tool '$tool' exists in registry"
      else
        fail "Tool '$tool' referenced in SKILL.md but NOT in registry"
      fi
    done <<< "$SKILL_TOOLS"
  fi
else
  echo "  ⚠️  Tool directory $TOOL_DIR not found — skipping registry cross-check"
  echo "     (tools referenced: $(echo "$SKILL_TOOLS" | tr '\n' ', '))"
fi

echo ""
echo "=== 3. Requirement coverage ==="

# R001/R003: Complete flow (identify past meeting → pull transcript/notes → generate notes → extract action items → write followups.md → commit)
r001_checks=0
grep -qi 'Identify the Target Meeting\|Identify.*Meeting\|Step 1' "$SKILL" && ((r001_checks++)) || true
grep -qi 'Pull Meeting Data\|transcript\|facilitator.*notes' "$SKILL" && ((r001_checks++)) || true
grep -qi 'Generate.*Notes\|Structured Meeting Notes\|Step 4' "$SKILL" && ((r001_checks++)) || true
grep -qi 'Action Item\|action item' "$SKILL" && ((r001_checks++)) || true
grep -qi 'followups\.md\|followups' "$SKILL" && ((r001_checks++)) || true
grep -qi 'git commit\|Commit' "$SKILL" && ((r001_checks++)) || true
if [[ $r001_checks -ge 6 ]]; then
  pass "R001/R003: Complete flow present (identify → pull → generate → extract → followups → commit) [$r001_checks/6]"
else
  fail "R001/R003: Incomplete flow ($r001_checks/6 steps found)"
fi

# R007: Bilingual instructions (Hebrew mention, English headings, preserve language)
r007_checks=0
grep -qi 'hebrew' "$SKILL" && ((r007_checks++)) || true
grep -qi 'english.*heading\|heading.*english\|Section headings.*English\|headings.*always English' "$SKILL" && ((r007_checks++)) || true
grep -qi 'preserve.*language\|source.*language\|do not translate\|original language' "$SKILL" && ((r007_checks++)) || true
if [[ $r007_checks -ge 3 ]]; then
  pass "R007: Bilingual instructions present (Hebrew + English headings + preserve language) [$r007_checks/3]"
else
  fail "R007: Incomplete bilingual instructions ($r007_checks/3 aspects found)"
fi

# R009: 4-tier customer detection (domains, folder scan, ask-when-unknown)
r009_checks=0
grep -qi 'attendee.*domain\|email domain\|external domain' "$SKILL" && ((r009_checks++)) || true
grep -qi 'folder scan\|customer-engagements\|folder name' "$SKILL" && ((r009_checks++)) || true
grep -qi 'meeting subject\|subject.*keyword\|subject.*company\|subject line' "$SKILL" && ((r009_checks++)) || true
grep -qi 'ask.*user\|ask when unknown\|never guess\|never fabricate' "$SKILL" && ((r009_checks++)) || true
if [[ $r009_checks -ge 3 ]]; then
  pass "R009: Customer detection chain present ($r009_checks/4 tiers found)"
else
  fail "R009: Incomplete customer detection ($r009_checks/4 tiers found)"
fi

# R011: Error handling table with ≥5 tool-specific entries
error_table_entries=$(grep -c '| `m365_' "$SKILL" 2>/dev/null || echo 0)
if [[ $error_table_entries -ge 5 ]]; then
  pass "R011: Error handling table present with $error_table_entries tool-specific entries (≥5 required)"
else
  fail "R011: Error handling table incomplete ($error_table_entries entries, need ≥5)"
fi

echo ""
echo "=== 4. Anti-pattern checks ==="

# Must NOT instruct fabrication of data (filter out negated forms like "do not invent")
fabricate_lines=$(grep -i 'make up\|invent\|generate fake\|fabricate data\|create fictional' "$SKILL" || true)
if [[ -n "$fabricate_lines" ]]; then
  bad_fab=$(echo "$fabricate_lines" | grep -iv 'do not\|don.t\|never\|must not\|should not\|never fabricate' || true)
  if [[ -n "$bad_fab" ]]; then
    fail "Anti-pattern: Skill instructs fabrication of data"
  else
    pass "Fabrication language correctly negated (do not invent/fabricate)"
  fi
else
  pass "No fabrication references found"
fi

# Must NOT instruct translating Hebrew to English (negations are OK — MEM009 gotcha)
translate_lines=$(grep -i 'translate hebrew to english\|translate.*hebrew.*into.*english\|convert hebrew to english' "$SKILL" || true)
if [[ -n "$translate_lines" ]]; then
  # Filter out lines that contain negation
  bad_lines=$(echo "$translate_lines" | grep -iv 'do not\|don.t\|never\|must not\|should not' || true)
  if [[ -n "$bad_lines" ]]; then
    fail "Anti-pattern: Skill instructs translating Hebrew to English"
  else
    pass "Hebrew-to-English translation correctly negated (do not translate)"
  fi
else
  pass "No Hebrew-to-English translation references found"
fi

# Must NOT skip all steps on error
if grep -qi 'skip all remaining\|abort the entire\|stop all steps' "$SKILL"; then
  fail "Anti-pattern: Skill instructs skipping all steps on error"
else
  pass "No skip-all-on-error instructions found"
fi

# Positive check: graceful degradation language present
if grep -qi 'continue\|graceful\|still be useful\|note.*missing\|note.*unavailable' "$SKILL"; then
  pass "Graceful degradation language present"
else
  fail "Missing graceful degradation instructions"
fi

echo ""
echo "=== 5. Template completeness ==="

# Required sections for capture-meeting output template
required_sections=(
  "Meeting Info|Meeting Notes|Date.*Customer|Date.*Attendees|meeting info"
  "Attendees"
  "Discussion Summary"
  "Key Decisions"
  "Action Items"
)
section_labels=(
  "Meeting Info / header"
  "Attendees"
  "Discussion Summary"
  "Key Decisions"
  "Action Items"
)

for i in "${!required_sections[@]}"; do
  if grep -qiE "${required_sections[$i]}" "$SKILL"; then
    pass "Template section '${section_labels[$i]}' present"
  else
    fail "Template section '${section_labels[$i]}' MISSING"
  fi
done

# followups.md append instructions
if grep -qi 'append.*followups\|followups\.md' "$SKILL"; then
  pass "followups.md append instructions present"
else
  fail "followups.md append instructions MISSING"
fi

# ## Open table format reference
if grep -q '## Open' "$SKILL"; then
  pass "'## Open' table format referenced"
else
  fail "'## Open' table format reference MISSING"
fi

# Past-meeting date range (backward, not forward)
if grep -qi 'past.*days\|backward\|past 7 days\|past meetings' "$SKILL"; then
  pass "Past-meeting date range (backward lookback) present"
else
  fail "Past-meeting date range direction not specified"
fi

echo ""
echo "=============================="
echo "RESULT: $PASS passed, $FAIL failed"

if [[ $FAIL -gt 0 ]]; then
  exit 1
else
  exit 0
fi
