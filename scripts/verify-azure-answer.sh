#!/usr/bin/env bash
# verify-azure-answer.sh — Validate azure-answer/SKILL.md against structural
# requirements, tool references, anti-patterns, and R005 requirement coverage.
# Exit 0 only if ALL checks pass.

set -uo pipefail

SKILL="azure-answer/SKILL.md"
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
if grep -q '^name: azure-answer' "$SKILL"; then
  pass "'name: azure-answer' field present"
else
  fail "'name' field missing or wrong value"
fi

# 1d. description field with trigger phrases
if grep -q '^description:' "$SKILL"; then
  desc_line=$(grep '^description:' "$SKILL")
  trigger_count=0
  for phrase in "azure" "pricing" "service"; do
    echo "$desc_line" | grep -qi "$phrase" && ((trigger_count++)) || true
  done
  if [[ $trigger_count -ge 2 ]]; then
    pass "'description' field present with trigger phrases ($trigger_count/3)"
  else
    fail "'description' field present but missing trigger phrases ($trigger_count/3)"
  fi
else
  fail "'description' field missing"
fi

echo ""
echo "=== 2. Required sections ==="

# 2a. Core Principles section
if grep -q '## Core Principles' "$SKILL"; then
  pass "Core Principles section present"
else
  fail "Core Principles section missing"
fi

# 2b. At least 3 numbered steps
step_count=0
for step_num in 1 2 3 4 5; do
  grep -q "## Step $step_num" "$SKILL" && ((step_count++)) || true
done
if [[ $step_count -ge 3 ]]; then
  pass "Numbered steps present ($step_count found)"
else
  fail "Insufficient numbered steps ($step_count found, need ≥3)"
fi

# 2c. Error handling content
if grep -qi 'Error Handling\|Failure Mode\|error.*behavior' "$SKILL"; then
  pass "Error handling content present"
else
  fail "Error handling content missing"
fi

# 2d. Sources/citation section in output format
if grep -qi 'Sources\|citation\|source.*required\|cited source' "$SKILL"; then
  pass "Sources/citation section present"
else
  fail "Sources/citation section missing"
fi

echo ""
echo "=== 3. Tool references ==="

# 3a. References web search tools (primary data source)
if grep -q 'search-the-web\|google_search' "$SKILL"; then
  pass "Web search tool reference present (search-the-web / google_search)"
else
  fail "No web search tool reference found — web search is the primary data source"
fi

# 3b. References az CLI commands (fallback data source)
if grep -q '`az ' "$SKILL" || grep -q 'az version\|az vm\|az account\|az provider\|az cognitiveservices\|az functionapp\|az webapp' "$SKILL"; then
  pass "Azure CLI (az) command references present"
else
  fail "No Azure CLI (az) command references found"
fi

# 3c. Must NOT reference azure__ MCP tools as available
if grep -qi 'azure__[a-z]\|azure_mcp\|azure MCP tool' "$SKILL"; then
  fail "Anti-pattern: References Azure MCP tools (no Azure MCP server exists)"
else
  pass "No false Azure MCP tool references"
fi

echo ""
echo "=== 4. Anti-pattern checks ==="

# 4a. No unguarded 'fabricate' (MEM009/MEM013: filter negated forms)
fab_lines=$(grep -i 'fabricate\|invent data\|make up.*data\|generate fake' "$SKILL" || true)
if [[ -n "$fab_lines" ]]; then
  bad_fab=$(echo "$fab_lines" | grep -iv 'do not\|don.t\|never\|must not\|should not' || true)
  if [[ -n "$bad_fab" ]]; then
    fail "Anti-pattern: Unguarded fabrication language found"
  else
    pass "Fabrication language correctly negated (never/do not)"
  fi
else
  pass "No fabrication language found"
fi

# 4b. No unguarded 'translate Hebrew' (MEM009/MEM013)
translate_lines=$(grep -i 'translate.*hebrew\|hebrew.*translat' "$SKILL" || true)
if [[ -n "$translate_lines" ]]; then
  bad_translate=$(echo "$translate_lines" | grep -iv 'do not\|don.t\|never\|must not\|should not\|preserve' || true)
  if [[ -n "$bad_translate" ]]; then
    fail "Anti-pattern: Unguarded Hebrew translation instruction"
  else
    pass "Hebrew translation correctly negated"
  fi
else
  pass "No Hebrew translation references (OK — not all skills need it)"
fi

# 4c. No claims of Azure MCP availability
if grep -qi 'Azure MCP.*available\|Azure MCP.*tool\|use the azure MCP' "$SKILL"; then
  fail "Anti-pattern: Claims Azure MCP tools are available"
else
  pass "No false Azure MCP availability claims"
fi

echo ""
echo "=== 5. R005 requirement checks ==="

# 5a. Citation/source requirement
if grep -qi 'cited source\|cite.*source\|source.*required\|backed by.*source\|Sources Section' "$SKILL"; then
  pass "R005: Citation/source requirement present"
else
  fail "R005: Citation/source requirement missing"
fi

# 5b. Verification-before-answering instruction
if grep -qi 'verify before\|search.*before.*composing\|always search\|verify.*answering' "$SKILL"; then
  pass "R005: Verification-before-answering instruction present"
else
  fail "R005: Verification-before-answering instruction missing"
fi

# 5c. Refusal pattern for unverifiable data
if grep -qi 'do not guess\|refuse gracefully\|couldn.t verify\|could not verify\|NOT guess' "$SKILL"; then
  pass "R005: Refusal pattern for unverifiable data present"
else
  fail "R005: Refusal pattern for unverifiable data missing"
fi

# 5d. Freshness disclaimer or date-stamp instruction
if grep -qi 'Verified on\|freshness\|date.*stamp\|YYYY-MM-DD\|pricing.*change\|may be outdated' "$SKILL"; then
  pass "R005: Freshness disclaimer / date-stamp present"
else
  fail "R005: Freshness disclaimer / date-stamp missing"
fi

echo ""
echo "=============================="
echo "RESULT: $PASS passed, $FAIL failed"

if [[ $FAIL -gt 0 ]]; then
  exit 1
else
  exit 0
fi
