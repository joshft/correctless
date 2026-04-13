#!/usr/bin/env bash
# Correctless — Auto Mode Phase 3: Pipeline + State Extension test suite
# Track 5a: Tests INV-019, INV-020, INV-023, INV-024, INV-025, INV-027, PRH-001, BND-003, BND-005
# RED phase: these tests MUST FAIL — implementation does not exist yet.
# Run from repo root: bash tests/test-auto-phase3-pipeline.sh

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0

# ============================================
# Helpers (matching project test conventions)
# ============================================

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

assert_contains() {
  local desc="$1" expected="$2" actual="$3"
  if echo "$actual" | grep -qF "$expected"; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (expected output to contain '$expected')"
    FAIL=$((FAIL + 1))
  fi
}

assert_not_contains() {
  local desc="$1" unexpected="$2" actual="$3"
  if ! echo "$actual" | grep -qF "$unexpected"; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (expected output NOT to contain '$unexpected')"
    FAIL=$((FAIL + 1))
  fi
}

file_contains() {
  local file="$1" pattern="$2" desc="$3"
  if grep -q "$pattern" "$file" 2>/dev/null; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (pattern '$pattern' not found in $file)"
    FAIL=$((FAIL + 1))
  fi
}

file_not_contains() {
  local file="$1" pattern="$2" desc="$3"
  if grep -q "$pattern" "$file" 2>/dev/null; then
    echo "  FAIL: $desc (pattern '$pattern' should NOT be in $file)"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  fi
}

file_contains_i() {
  local file="$1" pattern="$2" desc="$3"
  if grep -qi "$pattern" "$file" 2>/dev/null; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (pattern '$pattern' not found case-insensitively in $file)"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_exists() {
  local desc="$1" path="$2"
  if [ -f "$path" ]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (file '$path' does not exist)"
    FAIL=$((FAIL + 1))
  fi
}

# ============================================
# Source scripts at top level to avoid RETURN trap + source interaction
source "$REPO_DIR/scripts/workflow-state-ext.sh"

# ============================================
# INV-019 [integration]: Phase gate extension — no workflow invocation
# ============================================

test_inv019_no_workflow_documented() {
  echo ""
  echo "=== INV-019: SKILL.md documents handling no-workflow invocation ==="

  local skill_file="$REPO_DIR/skills/cauto/SKILL.md"

  # Phase 3: cauto must accept invocation when no active workflow exists
  # Must document prompt-driven start (accepting invocation when no workflow exists)
  file_contains_i "$skill_file" "no active workflow\|no.*workflow.*exists\|prompt-driven\|invoked.*without.*workflow\|no.*existing.*workflow" \
    "INV-019: SKILL.md documents no-workflow handling"
}

test_inv019_init_on_no_workflow() {
  echo ""
  echo "=== INV-019: SKILL.md calls workflow-advance.sh init ==="

  local skill_file="$REPO_DIR/skills/cauto/SKILL.md"

  # When no workflow exists, must initialize via workflow-advance.sh init
  file_contains "$skill_file" "workflow-advance.sh init" \
    "INV-019: SKILL.md calls workflow-advance.sh init for prompt-driven start"
}

# ============================================
# INV-020 [integration]: Two entry modes
# ============================================

test_inv020_interactive_mode() {
  echo ""
  echo "=== INV-020: SKILL.md documents interactive entry mode ==="

  local skill_file="$REPO_DIR/skills/cauto/SKILL.md"

  # Interactive mode: invoke /cspec for Socratic brainstorm
  # Must document the interactive entry mode specifically for Phase 3 spec creation
  file_contains_i "$skill_file" "interactive entry\|entry mode.*interactive\|socratic brainstorm\|interactive.*brainstorm\|invoke.*/cspec.*to.*write" \
    "INV-020: SKILL.md documents interactive entry mode"
}

test_inv020_provided_spec_mode() {
  echo ""
  echo "=== INV-020: SKILL.md documents provided spec mode ==="

  local skill_file="$REPO_DIR/skills/cauto/SKILL.md"

  # Provided mode: human supplies a pre-written spec file path
  file_contains_i "$skill_file" "provided.*spec\|pre-written.*spec\|spec.*file.*path\|supply.*spec" \
    "INV-020: SKILL.md documents provided spec entry mode"
}

# ============================================
# INV-023 [integration]: Spec approval gate
# ============================================

test_inv023_approval_gate_documented() {
  echo ""
  echo "=== INV-023: SKILL.md documents mandatory spec approval gate ==="

  local skill_file="$REPO_DIR/skills/cauto/SKILL.md"

  # Mandatory human approval gate — Phase 3 specific (pause pipeline for approval)
  file_contains_i "$skill_file" "spec approval gate\|pause.*spec.*approv\|approval.*gate.*spec\|mandatory.*spec.*approval" \
    "INV-023: SKILL.md documents mandatory spec approval gate"
}

test_inv023_approval_options_documented() {
  echo ""
  echo "=== INV-023: SKILL.md documents approval options ==="

  local skill_file="$REPO_DIR/skills/cauto/SKILL.md"

  # Approval options: approve, reject, revise (Phase 3 spec approval gate options)
  file_contains_i "$skill_file" "approve.*reject.*revise\|revise.*spec.*re-approve\|human.*approve.*reject.*revise" \
    "INV-023: SKILL.md documents approve/reject/revise options"
}

# ============================================
# INV-024 [integration]: Workflow state transitions use existing phases
# ============================================

test_inv024_existing_phases_only() {
  echo ""
  echo "=== INV-024: SKILL.md uses existing phase names ==="

  local skill_file="$REPO_DIR/skills/cauto/SKILL.md"

  # Phase 3 must not introduce new phase names
  # Existing phases: spec, review, review-spec, tdd-tests, tdd-impl, tdd-qa, done, verified, documented
  # Check that SKILL.md doesn't introduce novel phase names
  file_not_contains "$skill_file" "phase.*:.*spec-approval\|phase.*:.*pre-impl\|phase.*:.*auto-review" \
    "INV-024: SKILL.md does not introduce new phase names"
}

# ============================================
# INV-025 [unit]: Spec approval stored in state
# ============================================

test_inv025_set_spec_approval() {
  echo ""
  echo "=== INV-025: ws_set_spec_approval writes to state ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  echo '{"phase":"review-spec"}' > "$TEST_DIR/state.json"

  ws_set_spec_approval "$TEST_DIR/state.json" "human" "2026-04-12T20:00:00Z"
  local rc=$?

  assert_eq "INV-025: ws_set_spec_approval exits 0" "0" "$rc"

  # Verify fields were written
  local approver
  approver="$(jq -r '.spec_approved_by' "$TEST_DIR/state.json" 2>/dev/null)" || approver=""
  assert_eq "INV-025: spec_approved_by is 'human'" "human" "$approver"

  local timestamp
  timestamp="$(jq -r '.spec_approved_at' "$TEST_DIR/state.json" 2>/dev/null)" || timestamp=""
  assert_eq "INV-025: spec_approved_at is correct" "2026-04-12T20:00:00Z" "$timestamp"
}

test_inv025_get_spec_approval() {
  echo ""
  echo "=== INV-025: ws_get_spec_approval reads from state ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  echo '{"phase":"tdd-tests","spec_approved_by":"human","spec_approved_at":"2026-04-12T20:00:00Z"}' > "$TEST_DIR/state.json"

  local result
  result="$(ws_get_spec_approval "$TEST_DIR/state.json" 2>/dev/null)"
  local rc=$?

  assert_eq "INV-025: ws_get_spec_approval exits 0" "0" "$rc"

  # Should return JSON with approver and timestamp
  local approver
  approver="$(echo "$result" | jq -r '.approver' 2>/dev/null)" || approver=""
  assert_eq "INV-025: approval approver is 'human'" "human" "$approver"

  local timestamp
  timestamp="$(echo "$result" | jq -r '.timestamp' 2>/dev/null)" || timestamp=""
  assert_eq "INV-025: approval timestamp correct" "2026-04-12T20:00:00Z" "$timestamp"
}

# ============================================
# INV-027 [integration]: Backward compatibility
# ============================================

test_inv027_phase2_tests_listed() {
  echo ""
  echo "=== INV-027: Phase 2 test files listed in commands.test ==="

  # Verify the Phase 2 test files exist and would be run
  local phase2_tests=(
    "tests/test-auto-agents.sh"
    "tests/test-auto-budget.sh"
    "tests/test-auto-safety.sh"
    "tests/test-auto-report.sh"
  )

  for test_file in "${phase2_tests[@]}"; do
    assert_file_exists "INV-027: Phase 2 test $test_file exists" "$REPO_DIR/$test_file"
  done
}

# ============================================
# PRH-001 [integration]: Never bypass spec approval
# ============================================

test_prh001_approval_gate_present() {
  echo ""
  echo "=== PRH-001: Structural grep — spec approval gate in SKILL.md ==="

  local skill_file="$REPO_DIR/skills/cauto/SKILL.md"

  # cauto must have a Phase 3 spec approval gate that cannot be bypassed
  file_contains_i "$skill_file" "spec approval gate\|mandatory.*spec.*approval\|never.*bypass.*spec.*approval\|spec.*approval.*non-negotiable" \
    "PRH-001: SKILL.md contains spec approval gate"
}

test_prh001_no_auto_approval() {
  echo ""
  echo "=== PRH-001: No auto-approval mechanism in SKILL.md ==="

  local skill_file="$REPO_DIR/skills/cauto/SKILL.md"

  # Must NOT auto-approve based on supervisor confidence or preferences
  file_not_contains "$skill_file" "auto-approve\|auto_approve\|skip.*approval.*gate\|bypass.*approval" \
    "PRH-001: SKILL.md does not contain auto-approval bypass"
}

# ============================================
# BND-003 [unit]: Provided spec validation
# ============================================

test_bnd003_spec_exists_check() {
  echo ""
  echo "=== BND-003: Provided spec file existence validation ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  # Non-existent spec path should be caught — Phase 3 provided-spec validation
  local skill_file="$REPO_DIR/skills/cauto/SKILL.md"

  file_contains_i "$skill_file" "provided.*spec.*exist\|provided.*spec.*non-empty\|spec.*path.*valid\|validate.*provided.*spec\|provided.*file.*exist" \
    "BND-003: SKILL.md validates provided spec file exists and is non-empty"
}

# ============================================
# BND-005 [unit]: Main branch check
# ============================================

test_bnd005_main_branch_refused() {
  echo ""
  echo "=== BND-005: SKILL.md documents main/master branch refusal ==="

  local skill_file="$REPO_DIR/skills/cauto/SKILL.md"

  file_contains_i "$skill_file" "main branch.*refus\|refuse.*main branch\|master branch.*refus\|feature branch first\|create a feature branch\|not.*on main\|not.*on master" \
    "BND-005: SKILL.md documents refusing invocation on main/master"
}

# ============================================
# Runner
# ============================================

echo "============================================="
echo "Auto Mode Phase 3 — Pipeline + State"
echo "============================================="

# INV-019: Phase gate extension
test_inv019_no_workflow_documented
test_inv019_init_on_no_workflow

# INV-020: Two entry modes
test_inv020_interactive_mode
test_inv020_provided_spec_mode

# INV-023: Spec approval gate
test_inv023_approval_gate_documented
test_inv023_approval_options_documented

# INV-024: Existing phase names
test_inv024_existing_phases_only

# INV-025: Spec approval in state
test_inv025_set_spec_approval
test_inv025_get_spec_approval

# INV-027: Backward compat
test_inv027_phase2_tests_listed

# PRH-001: Never bypass spec approval
test_prh001_approval_gate_present
test_prh001_no_auto_approval

# BND-003: Provided spec validation
test_bnd003_spec_exists_check

# BND-005: Main branch refusal
test_bnd005_main_branch_refused

echo ""
echo "============================================="
echo "Results: $PASS passed, $FAIL failed"
echo ""

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
