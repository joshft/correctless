#!/usr/bin/env bash
# Correctless — Structured Decision UX tests
# Tests spec rules R-001 through R-012 from docs/specs/structured-decision-ux.md
# Run from repo root: bash test-decisions.sh

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASS=0
FAIL=0

# ---------------------------------------------------------------------------
# Helpers (matching test.sh style)
# ---------------------------------------------------------------------------

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (expected '$expected', got '$actual')"
    FAIL=$((FAIL + 1))
  fi
}

# Check if a file contains a pattern (returns 0 if found)
file_contains() {
  grep -q "$2" "$1" 2>/dev/null
}

# Check if a file contains a pattern (case-insensitive, returns 0 if found)
file_contains_i() {
  grep -qi "$2" "$1" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Test: R-001 — Templates have Decision Points section
# ---------------------------------------------------------------------------

test_r001() {
  echo ""
  echo "=== R-001: Templates have Decision Points section ==="

  local lite="$REPO_DIR/templates/spec-lite.md"
  local full="$REPO_DIR/templates/spec-full.md"

  file_contains_i "$lite" "Decision Points" && local lite_dp="true" || local lite_dp="false"
  assert_eq "R-001: spec-lite.md has Decision Points section" "true" "$lite_dp"

  file_contains_i "$full" "Decision Points" && local full_dp="true" || local full_dp="false"
  assert_eq "R-001: spec-full.md has Decision Points section" "true" "$full_dp"

  file_contains_i "$full" "recommended)" && local full_rec="true" || local full_rec="false"
  assert_eq "R-001: spec-full.md has recommended pattern" "true" "$full_rec"

  file_contains_i "$full" "Or type your own" && local full_esc="true" || local full_esc="false"
  assert_eq "R-001: spec-full.md has escape hatch" "true" "$full_esc"

  file_contains_i "$lite" "recommended)" && local lite_rec="true" || local lite_rec="false"
  assert_eq "R-001: spec-lite.md has recommended pattern" "true" "$lite_rec"

  file_contains_i "$lite" "Or type your own" && local lite_esc="true" || local lite_esc="false"
  assert_eq "R-001: spec-lite.md has escape hatch" "true" "$lite_esc"
}

# ---------------------------------------------------------------------------
# Test: R-002 — /cquick has Decision Points
# ---------------------------------------------------------------------------

test_r002() {
  echo ""
  echo "=== R-002: /cquick has Decision Points ==="

  local skill="$REPO_DIR/skills/cquick/SKILL.md"

  file_contains_i "$skill" "Decision Points" && local found="true" || local found="false"
  assert_eq "R-002: cquick SKILL.md has Decision Points section" "true" "$found"
}

# ---------------------------------------------------------------------------
# Test: R-003 — /csetup has structured options for 3 decisions
# ---------------------------------------------------------------------------

test_r003() {
  echo ""
  echo "=== R-003: /csetup has structured options for 3 decisions ==="

  local skill="$REPO_DIR/skills/csetup/SKILL.md"

  # MCP selection: must have numbered options with (recommended) near MCP context
  file_contains_i "$skill" "1\..*both.*(recommended)" && local mcp="true" || local mcp="false"
  assert_eq "R-003: csetup has numbered MCP selection options" "true" "$mcp"

  # Branching strategy: must have numbered options with (recommended) near branching context
  file_contains_i "$skill" "1\..*feature.branch.*(recommended)\|1\..*trunk.based.*(recommended)" && local branch="true" || local branch="false"
  assert_eq "R-003: csetup has numbered branching strategy options" "true" "$branch"

  # Merge strategy: must have numbered options with (recommended) near merge context
  file_contains_i "$skill" "1\..*squash.*(recommended)\|1\..*rebase.*(recommended)" && local merge="true" || local merge="false"
  assert_eq "R-003: csetup has numbered merge strategy options" "true" "$merge"
}

# ---------------------------------------------------------------------------
# Test: R-004 — /cspec has failure mode + risk options
# ---------------------------------------------------------------------------

test_r004() {
  echo ""
  echo "=== R-004: /cspec has failure mode + risk options ==="

  local skill="$REPO_DIR/skills/cspec/SKILL.md"

  # Must have numbered options with (recommended) for failure mode decision
  file_contains_i "$skill" "1\..*fail.open.*(recommended)\|1\..*fail.closed.*(recommended)" && local found="true" || local found="false"
  assert_eq "R-004: cspec has numbered failure mode options" "true" "$found"

  # Must have risk acceptance options (mitigate/accept/defer)
  file_contains_i "$skill" "mitigate.*(recommended)\|accept.*mitigate" && local risk="true" || local risk="false"
  assert_eq "R-004: cspec has risk acceptance options" "true" "$risk"
}

# ---------------------------------------------------------------------------
# Test: R-005 — /creview has finding disposition options
# ---------------------------------------------------------------------------

test_r005() {
  echo ""
  echo "=== R-005: /creview has finding disposition options ==="

  local skill="$REPO_DIR/skills/creview/SKILL.md"

  file_contains_i "$skill" "accept.*reject.*modify.*defer\|accept finding\|reject.*modify.*defer" && local found="true" || local found="false"
  assert_eq "R-005: creview has finding disposition options" "true" "$found"
}

# ---------------------------------------------------------------------------
# Test: R-006 — /ctdd has QA finding + test edit options
# ---------------------------------------------------------------------------

test_r006() {
  echo ""
  echo "=== R-006: /ctdd has QA finding + test edit options ==="

  local skill="$REPO_DIR/skills/ctdd/SKILL.md"

  file_contains_i "$skill" "fix now\|accept risk\|dispute" && local qa="true" || local qa="false"
  assert_eq "R-006: ctdd has QA finding response options" "true" "$qa"

  # Must have test edit approval options (approve/reject)
  file_contains_i "$skill" "approve change.*(recommended)\|approve.*(recommended).*reject" && local testedit="true" || local testedit="false"
  assert_eq "R-006: ctdd has test edit approval options" "true" "$testedit"
}

# ---------------------------------------------------------------------------
# Test: R-007 — /cverify has drift options
# ---------------------------------------------------------------------------

test_r007() {
  echo ""
  echo "=== R-007: /cverify has drift options ==="

  local skill="$REPO_DIR/skills/cverify/SKILL.md"

  file_contains_i "$skill" "drift.*fix\|log as debt\|accept as intentional" && local found="true" || local found="false"
  assert_eq "R-007: cverify has drift handling options" "true" "$found"
}

# ---------------------------------------------------------------------------
# Test: R-008 — /cdocs has architecture + post-merge options
# ---------------------------------------------------------------------------

test_r008() {
  echo ""
  echo "=== R-008: /cdocs has architecture + post-merge options ==="

  local skill="$REPO_DIR/skills/cdocs/SKILL.md"

  # Must have numbered options with (recommended) for architecture entry
  file_contains_i "$skill" "1\..*add.*(recommended)\|1\..*skip.*(recommended)" && local arch="true" || local arch="false"
  assert_eq "R-008: cdocs has numbered architecture entry options" "true" "$arch"

  # Must have post-merge options with (recommended)
  file_contains_i "$skill" "Create a PR.*(recommended)\|1\..*PR.*(recommended)" && local postmerge="true" || local postmerge="false"
  assert_eq "R-008: cdocs has post-merge options with recommended" "true" "$postmerge"
}

# ---------------------------------------------------------------------------
# Test: R-009 — /crefactor has test change options
# ---------------------------------------------------------------------------

test_r009() {
  echo ""
  echo "=== R-009: /crefactor has test change options ==="

  local skill="$REPO_DIR/skills/crefactor/SKILL.md"

  file_contains_i "$skill" "approve behavioral\|reject.*split\|separate PR" && local found="true" || local found="false"
  assert_eq "R-009: crefactor has test change approval options" "true" "$found"
}

# ---------------------------------------------------------------------------
# Test: R-010 — /caudit has finding triage + convergence options
# ---------------------------------------------------------------------------

test_r010() {
  echo ""
  echo "=== R-010: /caudit has finding triage + convergence options ==="

  local skill="$REPO_DIR/skills/caudit/SKILL.md"

  # Must have numbered options with (recommended) for finding triage
  file_contains_i "$skill" "1\..*fix now.*(recommended)\|1\..*fix.*(recommended).*triage" && local triage="true" || local triage="false"
  assert_eq "R-010: caudit has numbered finding triage options" "true" "$triage"

  # Must have convergence decision options (continue/stop)
  file_contains_i "$skill" "continue to next round.*(recommended)\|continue.*(recommended).*stop" && local conv="true" || local conv="false"
  assert_eq "R-010: caudit has convergence decision options" "true" "$conv"
}

# ---------------------------------------------------------------------------
# Test: R-011 — Read-only skills do NOT have decision blocks
# ---------------------------------------------------------------------------

test_r011() {
  echo ""
  echo "=== R-011: Read-only skills do NOT have decision blocks ==="

  local readonly_skills="chelp cstatus csummary cmetrics cwtf"

  for skill_name in $readonly_skills; do
    local skill_file="$REPO_DIR/skills/$skill_name/SKILL.md"
    if [ -f "$skill_file" ]; then
      file_contains "$skill_file" "recommended)" && local found="true" || local found="false"
      assert_eq "R-011: $skill_name does NOT have decision options" "false" "$found"
    else
      echo "  SKIP: $skill_name SKILL.md not found"
    fi
  done
}

# ---------------------------------------------------------------------------
# Test: R-012 — /creview-spec has finding disposition options
# ---------------------------------------------------------------------------

test_r012() {
  echo ""
  echo "=== R-012: /creview-spec has finding disposition options ==="

  local skill="$REPO_DIR/skills/creview-spec/SKILL.md"

  file_contains_i "$skill" "accept.*reject.*modify.*defer\|accept finding\|reject.*modify.*defer" && local found="true" || local found="false"
  assert_eq "R-012: creview-spec has finding disposition options" "true" "$found"
}

# ---------------------------------------------------------------------------
# Run all tests
# ---------------------------------------------------------------------------

echo "Correctless Structured Decision UX Tests"
echo "========================================="

test_r001
test_r002
test_r003
test_r004
test_r005
test_r006
test_r007
test_r008
test_r009
test_r010
test_r011
test_r012

echo ""
echo "========================================="
echo "Results: $PASS passed, $FAIL failed"
echo ""

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
