#!/usr/bin/env bash
# verify-followups.sh — Validate followups/SKILL.md against tool registry,
# requirement specs, anti-patterns, and structural correctness.
# Exit 0 only if ALL checks pass.

set -uo pipefail

SKILL="followups/SKILL.md"
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
if grep -q '^name: followups' "$SKILL"; then
  pass "'name: followups' field present"
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

# R004: Cross-customer scan + unresponded emails
r004_checks=0
grep -qi 'customer-engagements\|all customer' "$SKILL" && ((r004_checks++)) || true
grep -qi 'followups\.md' "$SKILL" && ((r004_checks++)) || true
grep -qi 'unresponded\|unreplied' "$SKILL" && ((r004_checks++)) || true
if [[ $r004_checks -ge 3 ]]; then
  pass "R004: Cross-customer scan + unresponded emails present [$r004_checks/3]"
else
  fail "R004: Incomplete cross-customer/unresponded coverage ($r004_checks/3 found)"
fi

# R007: Bilingual (English headings + source-language preservation + do-not-translate)
r007_checks=0
grep -qi 'hebrew' "$SKILL" && ((r007_checks++)) || true
grep -qi 'english.*heading\|heading.*english\|Section headings.*English\|headings.*always English' "$SKILL" && ((r007_checks++)) || true
grep -qi 'do not translate\|preserve.*language\|original language\|source.*language' "$SKILL" && ((r007_checks++)) || true
if [[ $r007_checks -ge 3 ]]; then
  pass "R007: Bilingual instructions present (Hebrew + English headings + preserve language) [$r007_checks/3]"
else
  fail "R007: Incomplete bilingual instructions ($r007_checks/3 aspects found)"
fi

# R009: Customer detection (folder iteration for all-mode + 4-tier chain for specific-mode)
r009_checks=0
grep -qi 'ls ~/customer-engagements\|list.*customer.*folder\|folder.*name' "$SKILL" && ((r009_checks++)) || true
grep -qi 'folder.*match\|folder name match\|Folder name match' "$SKILL" && ((r009_checks++)) || true
grep -qi 'folder scan\|fuzzy.*match\|Folder scan' "$SKILL" && ((r009_checks++)) || true
grep -qi 'meeting subject\|subject.*keyword\|Meeting subject' "$SKILL" && ((r009_checks++)) || true
grep -qi 'ask.*user\|user.*prompt\|User prompt' "$SKILL" && ((r009_checks++)) || true
if [[ $r009_checks -ge 4 ]]; then
  pass "R009: Customer detection chain present ($r009_checks/5 tiers found)"
else
  fail "R009: Incomplete customer detection ($r009_checks/5 tiers found, need ≥4)"
fi

# R011: Error handling table with ≥6 entries
error_table_entries=$(grep -cE '^\| .+\| .+\|' "$SKILL" 2>/dev/null || echo 0)
# Subtract header and separator rows — count only rows with pipe-delimited content
# that are NOT the header (Failure Mode | Behavior) or separator (---|---)
error_rows=$(awk '
  /^\| Failure Mode/ { in_table=1; next }
  /^\|[-]+/ { next }
  in_table && /^\| / { count++ }
  in_table && !/^\|/ { in_table=0 }
  END { print count+0 }
' "$SKILL")
if [[ $error_rows -ge 6 ]]; then
  pass "R011: Error handling table present with $error_rows entries (≥6 required)"
else
  fail "R011: Error handling table incomplete ($error_rows entries, need ≥6)"
fi

echo ""
echo "=== 4. Anti-pattern checks ==="

# Must NOT instruct fabrication of data (filter out negated forms — MEM009/MEM013)
fabricate_lines=$(grep -i 'fabricat\|invent\|make up\|generate fake\|create fictional' "$SKILL" || true)
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

# Must NOT instruct translating Hebrew to English (negations are OK — MEM009/MEM013)
translate_lines=$(grep -i 'translate.*hebrew\|hebrew.*translat\|convert hebrew' "$SKILL" || true)
if [[ -n "$translate_lines" ]]; then
  bad_lines=$(echo "$translate_lines" | grep -iv 'do not\|don.t\|never\|must not\|should not' || true)
  if [[ -n "$bad_lines" ]]; then
    fail "Anti-pattern: Skill instructs translating Hebrew content"
  else
    pass "Hebrew translation language correctly negated (do not translate)"
  fi
else
  pass "No Hebrew translation references found"
fi

# Must NOT skip all steps on error
if grep -qi 'skip all remaining\|abort the entire\|stop all steps' "$SKILL"; then
  fail "Anti-pattern: Skill instructs skipping all steps on error"
else
  pass "No skip-all-on-error instructions found"
fi

# Positive check: graceful degradation language present
if grep -qi 'graceful degradation\|still be useful\|continue.*other customers\|note.*missing\|note.*unavailable' "$SKILL"; then
  pass "Graceful degradation language present"
else
  fail "Missing graceful degradation instructions"
fi

echo ""
echo "=== 5. Template completeness ==="

# Output template present
if grep -q '## Output Template\|# 📋 Follow-up Report\|Output Template' "$SKILL"; then
  pass "Output template section present"
else
  fail "Output template section MISSING"
fi

# Customer grouping in output
if grep -qi '{Customer Name}\|grouped by customer\|group.*customer\|per customer' "$SKILL"; then
  pass "Customer grouping in output template"
else
  fail "Customer grouping MISSING from output"
fi

# Action items section in template
if grep -qi 'Open Action Items\|action item' "$SKILL"; then
  pass "Action items section present in template"
else
  fail "Action items section MISSING from template"
fi

# Unresponded emails section in template
if grep -qi 'Unresponded Emails\|unresponded email' "$SKILL"; then
  pass "Unresponded emails section present in template"
else
  fail "Unresponded emails section MISSING from template"
fi

# Summary counts in template
if grep -qi 'Summary\|Open action items.*count\|total.*count\|Customers scanned' "$SKILL"; then
  pass "Summary counts section present in template"
else
  fail "Summary counts MISSING from template"
fi

echo ""
echo "=============================="
echo "RESULT: $PASS passed, $FAIL failed"

if [[ $FAIL -gt 0 ]]; then
  exit 1
else
  exit 0
fi
