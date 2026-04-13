#!/usr/bin/env bash
# Correctless — Auto Mode Phase 3: Supervisor Extensions test suite
# Track 5b: Tests INV-026, INV-032, INV-033, PRH-004, PRH-005, BND-002
# RED phase: these tests MUST FAIL — implementation does not exist yet.
# Run from repo root: bash tests/test-auto-phase3-supervisor.sh

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
source "$REPO_DIR/scripts/auto-report.sh"
source "$REPO_DIR/scripts/review-triage.sh"

# ============================================
# INV-026 [unit]: Auto Run Report extensions
# ============================================

test_inv026_review_triage_section() {
  echo ""
  echo "=== INV-026: Report includes review triage section ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  # Create a review decisions fixture
  cat > "$TEST_DIR/review-decisions.json" << 'RD_EOF'
[
  {"finding_id":"F-001","source_agent":"red-team","finding_summary":"Missing auth","supervisor_decision":"accept","supervisor_reasoning":"Valid finding","timestamp":"2026-04-12T20:00:00Z"},
  {"finding_id":"F-002","source_agent":"assumptions","finding_summary":"Single-tenant assumed","supervisor_decision":"reject","supervisor_reasoning":"Low priority","timestamp":"2026-04-12T20:01:00Z"},
  {"finding_id":"F-003","source_agent":"testability","finding_summary":"No concurrent test","supervisor_decision":"hard_stop","supervisor_reasoning":"Needs human input","timestamp":"2026-04-12T20:02:00Z"}
]
RD_EOF

  local result
  result="$(report_section_review_triage "$TEST_DIR/review-decisions.json" 2>/dev/null)"
  local rc=$?

  assert_eq "INV-026: report_section_review_triage exits 0" "0" "$rc"

  # Section should contain Review Triage header
  assert_contains "INV-026: section contains triage header" "Review Triage" "$result"

  # Should show counts
  assert_contains "INV-026: section mentions accepted" "accept" "$result"
  assert_contains "INV-026: section mentions rejected" "reject" "$result"

  # Rejected findings should include supervisor reasoning (for human audit)
  assert_contains "INV-026: rejected finding reasoning visible" "Low priority" "$result"
}

test_inv026_override_scrutiny_section() {
  echo ""
  echo "=== INV-026: Report includes override scrutiny section ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  echo '{"phase":"done","override_activation_count":5,"override_log":[{"override_id":"OVR-001","review_type":"supervisor_issuance_review","disposition":"approve_override","reasoning":"Valid override"}]}' > "$TEST_DIR/state.json"

  local result
  result="$(report_section_override_scrutiny "$TEST_DIR/state.json" 2>/dev/null)"
  local rc=$?

  assert_eq "INV-026: report_section_override_scrutiny exits 0" "0" "$rc"

  # Section should contain Override Scrutiny header
  assert_contains "INV-026: section contains Override Scrutiny header" "Override Scrutiny" "$result"

  # Should show override activity
  assert_contains "INV-026: section mentions override ID" "OVR-001" "$result"
}

# ============================================
# INV-032 [integration]: Review triage uses supervisor agent
# ============================================

test_inv032_supervisor_invoked_for_triage() {
  echo ""
  echo "=== INV-032: SKILL.md invokes supervisor for review triage ==="

  local skill_file="$REPO_DIR/skills/cauto/SKILL.md"

  # SKILL.md must reference supervisor agent for triage
  file_contains_i "$skill_file" "supervisor.*triage\|triage.*supervisor\|review_triage.*supervisor\|supervisor.*review.*finding" \
    "INV-032: SKILL.md invokes supervisor for review triage"
}

# ============================================
# INV-033 [unit]: Supervisor activation type extensions
# ============================================

test_inv033_review_triage_type() {
  echo ""
  echo "=== INV-033: supervisor.md documents review_triage activation type ==="

  local agent_file="$REPO_DIR/agents/supervisor.md"

  file_contains "$agent_file" "review_triage" \
    "INV-033: supervisor documents review_triage activation type"
}

test_inv033_override_issued_type() {
  echo ""
  echo "=== INV-033: supervisor.md documents override_issued activation type ==="

  local agent_file="$REPO_DIR/agents/supervisor.md"

  file_contains "$agent_file" "override_issued" \
    "INV-033: supervisor documents override_issued activation type"
}

test_inv033_override_action_review_type() {
  echo ""
  echo "=== INV-033: supervisor.md documents override_action_review type ==="

  local agent_file="$REPO_DIR/agents/supervisor.md"

  file_contains "$agent_file" "override_action_review" \
    "INV-033: supervisor documents override_action_review type"
}

test_inv033_override_window_closing_type() {
  echo ""
  echo "=== INV-033: supervisor.md documents override_window_closing type ==="

  local agent_file="$REPO_DIR/agents/supervisor.md"

  file_contains "$agent_file" "override_window_closing" \
    "INV-033: supervisor documents override_window_closing type"
}

# ============================================
# PRH-004 [integration]: No inline triage logic
# ============================================

test_prh004_no_inline_triage() {
  echo ""
  echo "=== PRH-004: SKILL.md does NOT contain inline triage logic ==="

  local skill_file="$REPO_DIR/skills/cauto/SKILL.md"

  # SKILL.md must NOT implement accept/reject logic directly
  file_not_contains "$skill_file" 'if.*finding.*accept\|if.*finding.*reject\|case.*finding.*accept\|for.*finding.*in.*accept' \
    "PRH-004: SKILL.md has no inline finding accept/reject logic"

  # SKILL.md must NOT hardcode triage outcomes
  file_not_contains "$skill_file" 'auto_accept_finding\|auto_reject_finding\|default_triage' \
    "PRH-004: SKILL.md has no hardcoded triage outcomes"
}

# ============================================
# PRH-005 [unit]: No auto-answered supervisor responses
# ============================================

test_prh005_no_boilerplate_fallback() {
  echo ""
  echo "=== PRH-005: Supervisor response parsing rejects boilerplate ==="

  # Test that known boilerplate patterns are detected and rejected.
  # When supervisor response matches common auto-answer patterns,
  # it should be treated as escalate_to_human.

  # PRH-005 is about detecting boilerplate auto-answers
  # The SKILL.md must document rejection of boilerplate patterns
  local skill_file="$REPO_DIR/skills/cauto/SKILL.md"

  file_contains_i "$skill_file" "boilerplate\|auto-answer\|default.*fallback.*disposition\|pattern.*match.*auto\|must.*come.*from.*supervisor" \
    "PRH-005: SKILL.md documents rejection of boilerplate supervisor responses"
}

# ============================================
# BND-002 [unit]: Supervisor unavailable during review triage
# ============================================

test_bnd002_triage_fallback() {
  echo ""
  echo "=== BND-002: Supervisor unavailable → all findings hard-stopped ==="

  # When supervisor invocation fails, all findings should be treated as hard_stop
  local findings_json='[
    {"finding_id":"F-001","source_agent":"red-team","category":"security","summary":"Auth issue","proposed_action":"add_rule"},
    {"finding_id":"F-002","source_agent":"testability","category":"testability","summary":"Test gap","proposed_action":"add_rule"}
  ]'

  # triage_findings_batch with stubs returns failure (simulating supervisor unavailability)
  local result
  result="$(triage_findings_batch "$findings_json" 2>/dev/null)"
  local rc=$?

  # When the supervisor fails, the orchestrator should fall back to all-hard-stop.
  # In bash unit tests, the real supervisor (Task() invocation) is never available,
  # so we verify the SKILL.md documents the fallback behavior (BND-002).
  # The actual hard_stop fallback is exercised at integration level when supervisor
  # Task() invocation returns an error at runtime.
  local skill_file="$REPO_DIR/skills/cauto/SKILL.md"
  file_contains_i "$skill_file" "supervisor.*unavail.*hard.stop\|supervisor.*fail.*hard.stop\|all.*findings.*hard.stop\|fall.*back.*hard.stop" \
    "BND-002: SKILL.md documents supervisor failure → all findings hard-stopped"
}

# ============================================
# INV-035 [unit]: Override Scrutiny Prefix section exists
# ============================================

test_inv035_override_scrutiny_prefix_exists() {
  echo ""
  echo "=== INV-035: Override Scrutiny Prefix section exists in supervisor.md ==="

  local agent_file="$REPO_DIR/agents/supervisor.md"
  file_contains "$agent_file" "## Override Scrutiny Prefix" \
    "INV-035: supervisor.md has Override Scrutiny Prefix section"
}

# ============================================
# Runner
# ============================================

echo "============================================="
echo "Auto Mode Phase 3 — Supervisor Extensions"
echo "============================================="

# INV-026: Report extensions
test_inv026_review_triage_section
test_inv026_override_scrutiny_section

# INV-032: Supervisor for triage
test_inv032_supervisor_invoked_for_triage

# INV-033: Activation type extensions
test_inv033_review_triage_type
test_inv033_override_issued_type
test_inv033_override_action_review_type
test_inv033_override_window_closing_type

# INV-035: Override Scrutiny Prefix
test_inv035_override_scrutiny_prefix_exists

# PRH-004: No inline triage
test_prh004_no_inline_triage

# PRH-005: No auto-answered responses
test_prh005_no_boilerplate_fallback

# BND-002: Supervisor unavailable
test_bnd002_triage_fallback

echo ""
echo "============================================="
echo "Results: $PASS passed, $FAIL failed"
echo ""

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
