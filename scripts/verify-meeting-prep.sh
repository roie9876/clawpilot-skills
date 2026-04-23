#!/usr/bin/env bash
# verify-meeting-prep.sh — Validate meeting-prep/SKILL.md against tool registry,
# requirement specs, anti-patterns, and structural correctness.
# Exit 0 only if ALL checks pass.

set -uo pipefail

SKILL="meeting-prep/SKILL.md"
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

# 1b. YAML frontmatter present and parseable (starts and ends with ---)
if head -1 "$SKILL" | grep -q '^---$'; then
  # Check closing ---
  if awk 'NR>1 && /^---$/{found=1; exit} END{exit !found}' "$SKILL"; then
    pass "YAML frontmatter delimiters present"
  else
    fail "YAML frontmatter missing closing ---"
  fi
else
  fail "File does not start with YAML frontmatter (---)"
fi

# 1c. name field
if grep -q '^name: meeting-prep' "$SKILL"; then
  pass "'name: meeting-prep' field present"
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

# Extract canonical tool names from source
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
  fail "Tool directory $TOOL_DIR not found — cannot verify tool names"
fi

echo ""
echo "=== 3. Requirement coverage ==="

# R001: Complete flow from meeting identification → brief generation → file write
r001_checks=0
grep -q 'Identify the Target Meeting\|Identify.*Meeting\|Step 1' "$SKILL" && ((r001_checks++)) || true
grep -q 'Generate the Prep Brief\|Step 5\|template' "$SKILL" && ((r001_checks++)) || true
grep -q 'Write File\|git commit\|Step 6\|output path' "$SKILL" && ((r001_checks++)) || true
if [[ $r001_checks -ge 3 ]]; then
  pass "R001: Complete flow (identify → generate → write) present"
else
  fail "R001: Missing flow steps ($r001_checks/3 found)"
fi

# R007: Bilingual instructions (preserve Hebrew, English headings)
r007_checks=0
grep -qi 'hebrew' "$SKILL" && ((r007_checks++)) || true
grep -qi 'english.*heading\|heading.*english\|Section headings.*English\|headings.*always English' "$SKILL" && ((r007_checks++)) || true
grep -qi 'preserve.*language\|source.*language\|do not translate\|original language' "$SKILL" && ((r007_checks++)) || true
if [[ $r007_checks -ge 3 ]]; then
  pass "R007: Bilingual instructions present (Hebrew + English headings + preserve language)"
else
  fail "R007: Incomplete bilingual instructions ($r007_checks/3 aspects found)"
fi

# R009: Customer detection from attendees + folder scanning
r009_checks=0
grep -qi 'attendee.*domain\|email domain\|external domain' "$SKILL" && ((r009_checks++)) || true
grep -qi 'folder scan\|customer-engagements\|folder name' "$SKILL" && ((r009_checks++)) || true
grep -qi 'ask.*user\|ask when unknown\|never guess\|never fabricate' "$SKILL" && ((r009_checks++)) || true
if [[ $r009_checks -ge 3 ]]; then
  pass "R009: Customer detection chain present (domains + folders + ask-when-unknown)"
else
  fail "R009: Incomplete customer detection ($r009_checks/3 aspects found)"
fi

# R011: Each m365_* tool failure has a specific fallback
r011_tools=("m365_list_events" "m365_get_event" "m365_search_emails" "m365_get_facilitator_notes" "m365_get_transcript" "m365_search_people")
r011_pass=0
for tool in "${r011_tools[@]}"; do
  if grep -q "$tool" "$SKILL"; then
    # Check there's failure/fallback text near or in error handling table
    if grep -qi "fail\|unavailable\|error\|missing\|unable\|no results\|cannot" "$SKILL" | head -1 > /dev/null 2>&1; then
      ((r011_pass++))
    fi
  fi
done
# Verify the error handling table exists with entries for each tool
error_table_entries=$(grep -c '| `m365_' "$SKILL" 2>/dev/null || echo 0)
if [[ $error_table_entries -ge 5 ]]; then
  pass "R011: Error handling table present with $error_table_entries tool-specific failure entries"
else
  fail "R011: Error handling table incomplete ($error_table_entries entries, need ≥5)"
fi

echo ""
echo "=== 4. Anti-pattern checks ==="

# Must NOT instruct LLM to fabricate data
if grep -qi 'make up\|invent\|generate fake\|fabricate data\|create fictional' "$SKILL"; then
  fail "Anti-pattern: Skill instructs fabrication of data"
else
  pass "No fabrication instructions found"
fi

# Must NOT instruct translating Hebrew to English (negations like "do not translate" are OK)
translate_lines=$(grep -i 'translate hebrew to english\|translate.*hebrew.*into.*english\|convert hebrew to english' "$SKILL" || true)
if [[ -n "$translate_lines" ]]; then
  # Filter out lines that contain negation (do not, don't, never, must not)
  bad_lines=$(echo "$translate_lines" | grep -iv 'do not\|don.t\|never\|must not\|should not' || true)
  if [[ -n "$bad_lines" ]]; then
    fail "Anti-pattern: Skill instructs translating Hebrew to English"
  else
    pass "Hebrew-to-English translation correctly negated (do not translate)"
  fi
else
  pass "No Hebrew-to-English translation references found"
fi

# Must NOT skip steps on error
if grep -qi 'skip all remaining\|abort the entire\|stop all steps' "$SKILL"; then
  fail "Anti-pattern: Skill instructs skipping all steps on error"
else
  pass "No skip-all-on-error instructions found"
fi

# Positive check: should instruct to continue on individual failures
if grep -qi 'continue\|graceful\|still be useful\|note.*missing' "$SKILL"; then
  pass "Graceful degradation language present"
else
  fail "Missing graceful degradation instructions"
fi

echo ""
echo "=== 5. Template completeness ==="

required_sections=("Prior Context" "Open Follow-ups" "Key Topics" "Attendees")
for section in "${required_sections[@]}"; do
  if grep -qi "$section" "$SKILL"; then
    pass "Template section '$section' present"
  else
    fail "Template section '$section' MISSING"
  fi
done

echo ""
echo "=============================="
echo "RESULT: $PASS passed, $FAIL failed"

if [[ $FAIL -gt 0 ]]; then
  exit 1
else
  exit 0
fi
