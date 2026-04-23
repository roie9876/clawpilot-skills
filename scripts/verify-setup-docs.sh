#!/usr/bin/env bash
# verify-setup-docs.sh — Validate README.md and install.sh against setup documentation requirements
#
# Usage:
#   bash scripts/verify-setup-docs.sh
#
# Checks:
#   1.  README.md exists and is non-empty
#   2.  Has all required sections: Prerequisites, Installation, MCP, Skills table, Cross-Platform, Privacy
#   3.  All 6 skill names mentioned
#   4.  Cross-platform section mentions Windows, %USERPROFILE%, mklink
#   5.  Privacy notice present (local-only, pre-push, OneDrive)
#   6.  drawio MCP server URL documented
#   7.  az login mentioned as optional
#   8.  install.sh exists and references all 6 skill directories
#   9.  No hardcoded /Users/robenhai paths in README.md (R010 portability)
#  10.  ~/customer-engagements/ path convention documented

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
README="$REPO_ROOT/README.md"
INSTALL="$REPO_ROOT/scripts/install.sh"

pass=0
fail=0
total=0

check() {
    local description="$1"
    local result="$2"
    total=$((total + 1))
    if [ "$result" = "0" ]; then
        echo "  ✅ [$total] $description"
        pass=$((pass + 1))
    else
        echo "  ❌ [$total] $description"
        fail=$((fail + 1))
    fi
}

echo "Setup Documentation Verification"
echo "================================="
echo ""

# ---------------------------------------------------------------------------
# 1. README.md exists and is non-empty
# ---------------------------------------------------------------------------
result=1
if [ -f "$README" ] && [ -s "$README" ]; then result=0; fi
check "README.md exists and is non-empty" "$result"

# ---------------------------------------------------------------------------
# 2. Has all required sections
# ---------------------------------------------------------------------------
missing_sections=""
for section in "Prerequisites" "Installation" "MCP" "Quick Reference" "Windows" "Privacy"; do
    if ! grep -qi "$section" "$README" 2>/dev/null; then
        missing_sections="$missing_sections $section"
    fi
done
result=0
if [ -n "$missing_sections" ]; then
    result=1
    echo "       Missing sections:$missing_sections"
fi
check "Has required sections (Prerequisites, Installation, MCP, Skills table, Cross-Platform, Privacy)" "$result"

# ---------------------------------------------------------------------------
# 3. All 6 skill names mentioned
# ---------------------------------------------------------------------------
missing_skills=""
for skill in meeting-prep customer-repo capture-meeting followups azure-answer architecture; do
    if ! grep -q "$skill" "$README" 2>/dev/null; then
        missing_skills="$missing_skills $skill"
    fi
done
result=0
if [ -n "$missing_skills" ]; then
    result=1
    echo "       Missing skills:$missing_skills"
fi
check "All 6 skill names referenced in README.md" "$result"

# ---------------------------------------------------------------------------
# 4. Cross-platform section mentions Windows, %USERPROFILE%, mklink
# ---------------------------------------------------------------------------
result=0
for term in "Windows" "%USERPROFILE%" "mklink"; do
    if ! grep -q "$term" "$README" 2>/dev/null; then
        result=1
        echo "       Missing cross-platform term: $term"
    fi
done
check "Cross-platform section mentions Windows, %USERPROFILE%, mklink" "$result"

# ---------------------------------------------------------------------------
# 5. Privacy notice present (local-only, pre-push, OneDrive)
# ---------------------------------------------------------------------------
result=0
for term in "local-only" "pre-push" "OneDrive"; do
    if ! grep -qi "$term" "$README" 2>/dev/null; then
        result=1
        echo "       Missing privacy term: $term"
    fi
done
check "Privacy notice present (local-only, pre-push, OneDrive)" "$result"

# ---------------------------------------------------------------------------
# 6. drawio MCP server URL documented
# ---------------------------------------------------------------------------
result=1
if grep -q "https://mcp.draw.io/mcp" "$README" 2>/dev/null; then result=0; fi
check "Draw.io MCP server URL (https://mcp.draw.io/mcp) documented" "$result"

# ---------------------------------------------------------------------------
# 7. az login mentioned as optional
# ---------------------------------------------------------------------------
result=1
if grep -q "az login" "$README" 2>/dev/null; then
    if grep -qi "optional" "$README" 2>/dev/null; then
        result=0
    fi
fi
check "az login mentioned as optional" "$result"

# ---------------------------------------------------------------------------
# 8. install.sh exists and references all 6 skill directories
# ---------------------------------------------------------------------------
result=0
if [ ! -f "$INSTALL" ]; then
    result=1
    echo "       install.sh not found"
else
    for skill in meeting-prep customer-repo capture-meeting followups azure-answer architecture; do
        if ! grep -q "$skill" "$INSTALL" 2>/dev/null; then
            result=1
            echo "       install.sh missing reference to: $skill"
        fi
    done
fi
check "install.sh exists and references all 6 skill directories" "$result"

# ---------------------------------------------------------------------------
# 9. No hardcoded /Users/robenhai paths in README.md (R010 portability)
# ---------------------------------------------------------------------------
result=0
if grep -q "/Users/robenhai" "$README" 2>/dev/null; then
    result=1
    echo "       Found hardcoded /Users/robenhai path in README.md"
fi
check "No hardcoded /Users/robenhai paths in README.md (R010 portability)" "$result"

# ---------------------------------------------------------------------------
# 10. ~/customer-engagements/ path convention documented
# ---------------------------------------------------------------------------
result=1
if grep -q "customer-engagements" "$README" 2>/dev/null; then result=0; fi
check "~/customer-engagements/ path convention documented" "$result"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "Results: $pass/$total passed, $fail failed"
echo ""
if [ "$fail" -gt 0 ]; then
    echo "FAIL — $fail check(s) did not pass"
    exit 1
else
    echo "ALL CHECKS PASSED"
    exit 0
fi
