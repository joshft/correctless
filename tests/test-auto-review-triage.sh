#!/usr/bin/env bash
# Correctless — Auto Mode Phase 3: Review Triage test suite
# Track 1: Tests INV-021, INV-022, PRH-003, BND-001, BND-004
# RED phase: these tests MUST FAIL — implementation does not exist yet.
# Run from repo root: bash tests/test-auto-review-triage.sh

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
source "$REPO_DIR/scripts/review-triage.sh"
source "$REPO_DIR/scripts/security-scan.sh"

# ============================================
# INV-021 [integration]: Autonomous review with supervisor triage (batch)
# ============================================

test_inv021_triage_batch_all_findings() {
  echo ""
  echo "=== INV-021: Batch triage passes all findings to supervisor ==="

  # Fixture: array of review findings per spec schema
  local findings_json
  findings_json='[
    {"finding_id":"F-001","source_agent":"red-team","category":"security","summary":"Missing auth on /api/admin","proposed_action":"add_rule"},
    {"finding_id":"F-002","source_agent":"assumptions","category":"assumption","summary":"Assumes single-tenant deployment","proposed_action":"flag_risk"},
    {"finding_id":"F-003","source_agent":"testability","category":"testability","summary":"No test for concurrent access","proposed_action":"add_rule"}
  ]'

  local result
  result="$(triage_findings_batch "$findings_json" 2>/dev/null)"
  local rc=$?

  # Must succeed when implemented
  assert_eq "INV-021: triage_findings_batch exits 0" "0" "$rc"

  # Result must be valid JSON array
  local is_array="no"
  echo "$result" | jq -e 'type == "array"' >/dev/null 2>&1 && is_array="yes"
  assert_eq "INV-021: triage result is JSON array" "yes" "$is_array"

  # Result must have one decision per finding
  local count
  count="$(echo "$result" | jq 'length' 2>/dev/null)" || count="0"
  assert_eq "INV-021: triage result has 3 decisions (one per finding)" "3" "$count"
}

test_inv021_triage_decisions_per_finding() {
  echo ""
  echo "=== INV-021: Each finding gets accept/reject/hard_stop ==="

  local findings_json='[
    {"finding_id":"F-010","source_agent":"design-contract","category":"design-contract","summary":"Missing error handler","proposed_action":"add_rule"}
  ]'

  local result
  result="$(triage_findings_batch "$findings_json" 2>/dev/null)"
  local rc=$?

  assert_eq "INV-021: triage exits 0" "0" "$rc"

  # Each decision must have finding_id and decision fields
  local has_finding_id="no"
  echo "$result" | jq -e '.[0].finding_id' >/dev/null 2>&1 && has_finding_id="yes"
  assert_eq "INV-021: triage decision contains finding_id" "yes" "$has_finding_id"

  local has_decision="no"
  echo "$result" | jq -e '.[0].decision' >/dev/null 2>&1 && has_decision="yes"
  assert_eq "INV-021: triage decision contains decision field" "yes" "$has_decision"
}

# ============================================
# INV-022 [unit]: Review decisions artifact with hash
# ============================================

test_inv022_create_review_decisions() {
  echo ""
  echo "=== INV-022: Create review decisions artifact ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  local decisions_json='[{"finding_id":"F-001","source_agent":"red-team","finding_summary":"Missing auth","supervisor_decision":"accept","supervisor_reasoning":"Valid finding","timestamp":"2026-04-12T20:00:00Z"}]'

  create_review_decisions "$TEST_DIR" "test-branch-abc123" "$decisions_json"
  local rc=$?

  assert_eq "INV-022: create_review_decisions exits 0" "0" "$rc"

  local artifact_file="$TEST_DIR/review-decisions-test-branch-abc123.json"
  assert_file_exists "INV-022: review decisions artifact created" "$artifact_file"
}

test_inv022_hash_review_decisions() {
  echo ""
  echo "=== INV-022: Hash review decisions artifact ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  local artifact_file="$TEST_DIR/review-decisions-test.json"
  echo '[{"finding_id":"F-001","supervisor_decision":"accept"}]' > "$artifact_file"

  local hash
  hash="$(hash_review_decisions "$artifact_file")"
  local rc=$?

  assert_eq "INV-022: hash_review_decisions exits 0" "0" "$rc"

  # Hash must be non-empty and look like SHA-256 (64 hex chars)
  local hash_len="${#hash}"
  assert_eq "INV-022: hash is 64 characters (SHA-256)" "64" "$hash_len"
}

test_inv022_verify_hash_match() {
  echo ""
  echo "=== INV-022: Verify hash — match ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  local artifact_file="$TEST_DIR/review-decisions-test.json"
  echo '[{"finding_id":"F-001","supervisor_decision":"accept"}]' > "$artifact_file"

  local hash
  hash="$(hash_review_decisions "$artifact_file")"

  verify_review_decisions_hash "$artifact_file" "$hash"
  local rc=$?
  assert_eq "INV-022: verify succeeds with matching hash" "0" "$rc"
}

test_inv022_verify_hash_tampered() {
  echo ""
  echo "=== INV-022: Verify hash — tampered (mismatch) ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  local artifact_file="$TEST_DIR/review-decisions-test.json"
  echo '[{"finding_id":"F-001","supervisor_decision":"accept"}]' > "$artifact_file"

  local hash
  hash="$(hash_review_decisions "$artifact_file")"

  # Tamper with the file
  echo '[{"finding_id":"F-001","supervisor_decision":"reject"}]' > "$artifact_file"

  verify_review_decisions_hash "$artifact_file" "$hash"
  local rc=$?
  assert_eq "INV-022: verify fails with tampered file" "1" "$rc"
}

# ============================================
# PRH-003 [unit]: Source agent category authoritative
# ============================================

test_prh003_redteam_reject_overridden() {
  echo ""
  echo "=== PRH-003: Red Team finding rejected by supervisor overridden to hard_stop ==="

  # Supervisor returned reject for a Red Team finding — must be overridden
  local supervisor_response='[{"finding_id":"F-001","decision":"reject","reasoning":"Not relevant"}]'
  local findings_json='[{"finding_id":"F-001","source_agent":"red-team","category":"security","summary":"SQL injection vector","proposed_action":"add_rule"}]'

  local result
  result="$(enforce_prh003 "$supervisor_response" "$findings_json" 2>/dev/null)"
  local rc=$?

  assert_eq "PRH-003: enforce_prh003 exits 0" "0" "$rc"

  # The decision for F-001 must now be hard_stop, not reject
  local corrected_decision
  corrected_decision="$(echo "$result" | jq -r '.[0].decision' 2>/dev/null)" || corrected_decision=""
  assert_eq "PRH-003: Red Team reject overridden to hard_stop" "hard_stop" "$corrected_decision"
}

test_prh003_redteam_accept_preserved() {
  echo ""
  echo "=== PRH-003: Red Team finding accepted by supervisor — preserved ==="

  local supervisor_response='[{"finding_id":"F-002","decision":"accept","reasoning":"Valid finding, incorporate"}]'
  local findings_json='[{"finding_id":"F-002","source_agent":"red-team","category":"security","summary":"Auth bypass","proposed_action":"add_rule"}]'

  local result
  result="$(enforce_prh003 "$supervisor_response" "$findings_json" 2>/dev/null)"
  local rc=$?

  assert_eq "PRH-003: enforce_prh003 exits 0" "0" "$rc"

  local decision
  decision="$(echo "$result" | jq -r '.[0].decision' 2>/dev/null)" || decision=""
  assert_eq "PRH-003: Red Team accept preserved" "accept" "$decision"
}

test_prh003_security_keyword_reject_overridden() {
  echo ""
  echo "=== PRH-003: Security-keyword finding rejected overridden to hard_stop ==="

  # Non-red-team finding but contains security keyword (credential)
  local supervisor_response='[{"finding_id":"F-003","decision":"reject","reasoning":"Minor concern"}]'
  local findings_json='[{"finding_id":"F-003","source_agent":"assumptions","category":"security","summary":"Credential storage assumption untested","proposed_action":"flag_risk"}]'

  local result
  result="$(enforce_prh003 "$supervisor_response" "$findings_json" 2>/dev/null)"
  local rc=$?

  assert_eq "PRH-003: enforce_prh003 exits 0 for security keyword" "0" "$rc"

  local corrected_decision
  corrected_decision="$(echo "$result" | jq -r '.[0].decision' 2>/dev/null)" || corrected_decision=""
  assert_eq "PRH-003: security-keyword reject overridden to hard_stop" "hard_stop" "$corrected_decision"
}

test_prh003_nonsecurity_reject_preserved() {
  echo ""
  echo "=== PRH-003: Non-security finding rejected — preserved ==="

  local supervisor_response='[{"finding_id":"F-004","decision":"reject","reasoning":"Not actionable"}]'
  local findings_json='[{"finding_id":"F-004","source_agent":"testability","category":"testability","summary":"Test naming inconsistency","proposed_action":"update_invariant"}]'

  local result
  result="$(enforce_prh003 "$supervisor_response" "$findings_json" 2>/dev/null)"
  local rc=$?

  assert_eq "PRH-003: enforce_prh003 exits 0" "0" "$rc"

  local decision
  decision="$(echo "$result" | jq -r '.[0].decision' 2>/dev/null)" || decision=""
  assert_eq "PRH-003: non-security reject preserved" "reject" "$decision"
}

# ============================================
# BND-001 [unit]: Review produces zero findings
# ============================================

test_bnd001_empty_findings() {
  echo ""
  echo "=== BND-001: Triage with zero findings ==="

  local result
  result="$(triage_findings_batch "[]" 2>/dev/null)"
  local rc=$?

  assert_eq "BND-001: triage_findings_batch with empty array exits 0" "0" "$rc"

  # Result should be empty array
  local count
  count="$(echo "$result" | jq 'length' 2>/dev/null)" || count="-1"
  assert_eq "BND-001: empty findings produces empty decisions array" "0" "$count"
}

# ============================================
# BND-004 [unit]: Supervisor mixed decisions
# ============================================

test_bnd004_mixed_decisions_independent() {
  echo ""
  echo "=== BND-004: Mixed accept/reject/hard_stop processed independently ==="

  # Simulate a supervisor response with mixed decisions
  local findings_json='[
    {"finding_id":"F-010","source_agent":"testability","category":"testability","summary":"Missing edge case test","proposed_action":"add_rule"},
    {"finding_id":"F-011","source_agent":"assumptions","category":"assumption","summary":"Assumes UTF-8","proposed_action":"flag_risk"},
    {"finding_id":"F-012","source_agent":"design-contract","category":"design-contract","summary":"API contract incomplete","proposed_action":"update_invariant"}
  ]'

  # This tests that when a real supervisor returns mixed decisions,
  # each is processed independently. Since we can't invoke the real supervisor
  # in unit tests, we test enforce_prh003 with a simulated mixed response.
  local supervisor_response='[
    {"finding_id":"F-010","decision":"accept","reasoning":"Good catch"},
    {"finding_id":"F-011","decision":"reject","reasoning":"Low priority"},
    {"finding_id":"F-012","decision":"hard_stop","reasoning":"Needs human review"}
  ]'

  local result
  result="$(enforce_prh003 "$supervisor_response" "$findings_json" 2>/dev/null)"
  local rc=$?

  assert_eq "BND-004: enforce_prh003 with mixed decisions exits 0" "0" "$rc"

  # Each finding should retain its original decision (none are red-team/security)
  local d1 d2 d3
  d1="$(echo "$result" | jq -r '.[0].decision' 2>/dev/null)" || d1=""
  d2="$(echo "$result" | jq -r '.[1].decision' 2>/dev/null)" || d2=""
  d3="$(echo "$result" | jq -r '.[2].decision' 2>/dev/null)" || d3=""

  assert_eq "BND-004: F-010 accept preserved" "accept" "$d1"
  assert_eq "BND-004: F-011 reject preserved" "reject" "$d2"
  assert_eq "BND-004: F-012 hard_stop preserved" "hard_stop" "$d3"
}

# ============================================
# INV-021 [structural]: Triage function references supervisor
# ============================================

test_inv021_triage_calls_supervisor() {
  echo ""
  echo "=== INV-021: triage_findings_batch references supervisor invocation ==="

  # Structural test: the triage_findings_batch function body must reference
  # the supervisor (via "supervisor" or "Task(") to ensure it delegates to the
  # supervisor agent rather than implementing inline triage logic (PRH-004).
  local has_supervisor_ref="no"
  declare -f triage_findings_batch 2>/dev/null | grep -qi "supervisor\|task(" && has_supervisor_ref="yes"
  assert_eq "INV-021: triage_findings_batch references supervisor" "yes" "$has_supervisor_ref"
}

# ============================================
# PRH-003 [unit]: Security keyword in non-security category
# ============================================

test_prh003_security_keyword_in_nonsecurity_category() {
  echo ""
  echo "=== PRH-003: Security keyword in non-security category overridden to hard_stop ==="

  # Finding from assumptions agent with category "assumption" but summary
  # contains a security keyword ("credential") from PRH-001 keyword list
  local supervisor_response='[{"finding_id":"F-050","decision":"reject","reasoning":"Not a real security issue"}]'
  local findings_json='[{"finding_id":"F-050","source_agent":"assumptions","category":"assumption","summary":"Credential storage format assumed to be plaintext","proposed_action":"flag_risk"}]'

  local result
  result="$(enforce_prh003 "$supervisor_response" "$findings_json" 2>/dev/null)"
  local rc=$?

  assert_eq "PRH-003: enforce_prh003 exits 0 for keyword mismatch" "0" "$rc"

  # The decision must be overridden to hard_stop because "credential" is a
  # security keyword (from PRH-001 in security-scan.sh) appearing in a
  # non-security category
  local corrected_decision
  corrected_decision="$(echo "$result" | jq -r '.[0].decision' 2>/dev/null)" || corrected_decision=""
  assert_eq "PRH-003: non-security category with security keyword → hard_stop" "hard_stop" "$corrected_decision"
}

# ============================================
# Runner
# ============================================

echo "============================================="
echo "Auto Mode Phase 3 — Review Triage"
echo "============================================="

# INV-021: Batch triage
test_inv021_triage_batch_all_findings
test_inv021_triage_decisions_per_finding
test_inv021_triage_calls_supervisor

# INV-022: Review decisions artifact + hash
test_inv022_create_review_decisions
test_inv022_hash_review_decisions
test_inv022_verify_hash_match
test_inv022_verify_hash_tampered

# PRH-003: Source agent category enforcement
test_prh003_redteam_reject_overridden
test_prh003_redteam_accept_preserved
test_prh003_security_keyword_reject_overridden
test_prh003_nonsecurity_reject_preserved
test_prh003_security_keyword_in_nonsecurity_category

# BND-001: Zero findings
test_bnd001_empty_findings

# BND-004: Mixed decisions
test_bnd004_mixed_decisions_independent

echo ""
echo "============================================="
echo "Results: $PASS passed, $FAIL failed"
echo ""

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
