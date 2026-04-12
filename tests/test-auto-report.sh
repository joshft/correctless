#!/usr/bin/env bash
# Correctless — Auto Mode Phase 2: Report + Intent test suite
# Track 6: Tests INV-009, INV-013
# RED phase: these tests MUST FAIL — implementation does not exist yet.
# Run from repo root: bash tests/test-auto-report.sh

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
source "$REPO_DIR/scripts/intent-hash.sh"

# INV-009 [integration]: Auto Run Report generated on completion
# ============================================

test_inv009_report_generated() {
  echo ""
  echo "=== INV-009: Auto Run Report generated on completion ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN


  # Generate report — stub should fail (RED phase)
  local _result
  _result="$(report_generate "$TEST_DIR" "test-slug" "COMPLETE" 2>/dev/null)"
  local rc=$?

  # Must succeed (exit 0) when implemented
  assert_eq "INV-009: report_generate exits 0 on success" "0" "$rc"
}

test_inv009_report_required_sections() {
  echo ""
  echo "=== INV-009: Auto Run Report has all required sections ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  # Create minimal artifacts for the report generator
  echo '{"phase":"documented","pipeline_start_time":"2026-04-11T20:00:00Z"}' > "$TEST_DIR/state.json"
  echo "## Decision Record" > "$TEST_DIR/decision-record.md"
  echo "DD-001: test" >> "$TEST_DIR/decision-record.md"


  local report_file="$TEST_DIR/auto-report-test.md"
  report_generate "$TEST_DIR" "test-slug" "COMPLETE" > "$report_file" 2>/dev/null || true

  # Check all 11 required sections from the spec with specific section headers
  # 1. Feature name
  file_contains "$report_file" "## Feature" \
    "B-011/INV-009: report has '## Feature' section header"

  # 2. Branch
  file_contains "$report_file" "## Branch" \
    "B-011/INV-009: report has '## Branch' section header"

  # 3. Start/end timestamps
  file_contains "$report_file" "## Timestamps" \
    "B-011/INV-009: report has '## Timestamps' section header"

  # 4. Duration
  file_contains_i "$report_file" "duration" \
    "B-011/INV-009: report has duration"

  # 5. Token cost
  file_contains_i "$report_file" "token.*cost\|cost.*token\|token.*usage" \
    "B-011/INV-009: report has token cost"

  # 6. Status (COMPLETE | PAUSED | BUDGET_EXCEEDED | TIME_EXCEEDED)
  file_contains "$report_file" "## Status" \
    "B-011/INV-009: report has '## Status' section header"

  # 7. Decision record summary (count per tier)
  file_contains "$report_file" "## Decision Summary" \
    "B-011/INV-009: report has '## Decision Summary' section header"

  # 8. Decisions requiring human review
  file_contains "$report_file" "## Decisions Requiring Human Review" \
    "B-011/INV-009: report has '## Decisions Requiring Human Review' section header"

  # 9. Spec summary
  file_contains "$report_file" "## Spec Summary" \
    "B-011/INV-009: report has '## Spec Summary' section header"

  # 10. Implementation summary
  file_contains "$report_file" "## Implementation Summary" \
    "B-011/INV-009: report has '## Implementation Summary' section header"

  # 11. Verification summary
  file_contains "$report_file" "## Verification Summary" \
    "B-011/INV-009: report has '## Verification Summary' section header"

  # 12. What to Review First (prioritized list)
  file_contains "$report_file" "## What to Review First" \
    "B-011/INV-009: report has '## What to Review First' section header"
}

test_inv009_report_on_pause() {
  echo ""
  echo "=== INV-009: Auto Run Report generated on pause (hard stop) ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN


  # Report should be generated with PAUSED status
  local _result
  _result="$(report_generate "$TEST_DIR" "test-slug" "PAUSED" 2>/dev/null)"
  local rc=$?
  assert_eq "INV-009: report_generate with PAUSED status exits 0" "0" "$rc"
}

test_inv009_report_budget_exceeded_status() {
  echo ""
  echo "=== INV-009: Auto Run Report with BUDGET_EXCEEDED status ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN


  local _result
  _result="$(report_generate "$TEST_DIR" "test-slug" "BUDGET_EXCEEDED" 2>/dev/null)"
  local rc=$?
  assert_eq "INV-009: report_generate with BUDGET_EXCEEDED status exits 0" "0" "$rc"
}

# ============================================
# Source scripts at top level to avoid RETURN trap + source interaction
source "$REPO_DIR/scripts/auto-report.sh"
source "$REPO_DIR/scripts/intent-hash.sh"

# INV-009 [integration]: Decision summary section
# ============================================

test_inv009_decision_summary_by_tier() {
  echo ""
  echo "=== INV-009: Report decision summary counts by tier ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  # Create a decision record with entries at different tiers
  cat > "$TEST_DIR/decision-record.md" << 'REC_EOF'
## Decision Record

### DD-000
- **Tier**: system
- **Category**: intent
- **Summary**: Pipeline intent established

### DD-001
- **Tier**: 0
- **Category**: security
- **Disposition**: fix

### DD-002
- **Tier**: 2
- **Category**: performance
- **Disposition**: tier2_decide

### DD-003
- **Tier**: 0
- **Category**: testability
- **Disposition**: fix
REC_EOF


  local section
  section="$(report_section_decisions "$TEST_DIR/decision-record.md" 2>/dev/null)"
  local rc=$?
  assert_eq "INV-009: report_section_decisions exits 0" "0" "$rc"

  # Section should summarize by tier count
  assert_contains "INV-009: decision summary mentions Tier 0" "0" "$section"
}

# ============================================
# INV-013 [integration]: Intent summary written once, never modified
# ============================================

test_inv013_intent_create_and_hash() {
  echo ""
  echo "=== INV-013: Intent summary — create and hash ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN


  local intent_content="Build a policy engine that routes decisions autonomously. Key constraints: no security relaxation, append-only decision record."
  local hash
  hash="$(intent_create "$TEST_DIR/intent.md" "$intent_content")"
  local rc=$?

  assert_eq "INV-013: intent_create exits 0" "0" "$rc"

  # File should exist
  assert_file_exists "INV-013: intent file created" "$TEST_DIR/intent.md"

  # Hash should be non-empty
  local hash_nonempty="no"
  [ -n "$hash" ] && hash_nonempty="yes"
  assert_eq "INV-013: intent_create returns non-empty hash" "yes" "$hash_nonempty"
}

test_inv013_intent_verify_match() {
  echo ""
  echo "=== INV-013: Intent summary — hash verification match ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN


  local content="Test intent summary content"
  local hash
  hash="$(intent_create "$TEST_DIR/intent.md" "$content")"

  # Verify with correct hash
  intent_verify "$TEST_DIR/intent.md" "$hash"
  local rc=$?
  assert_eq "INV-013: intent_verify succeeds with matching hash" "0" "$rc"
}

test_inv013_intent_verify_mismatch() {
  echo ""
  echo "=== INV-013: Intent summary — hash mismatch triggers hard stop ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN


  local content="Original intent summary"
  intent_create "$TEST_DIR/intent.md" "$content" > /dev/null

  # Tamper with the file
  echo "TAMPERED content" > "$TEST_DIR/intent.md"

  # Verify with original hash (should fail)
  local original_hash
  original_hash="$(echo -n "$content" | sha256sum 2>/dev/null | cut -d' ' -f1 || echo "test_hash")"
  intent_verify "$TEST_DIR/intent.md" "$original_hash"
  local rc=$?
  assert_eq "INV-013: intent_verify fails with mismatched hash → exit 1" "1" "$rc"
}

test_inv013_intent_immutable() {
  echo ""
  echo "=== INV-013: Intent summary — immutability enforcement ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN


  local content="Immutable intent"
  local hash1
  hash1="$(intent_create "$TEST_DIR/intent.md" "$content")"

  # Compute hash again without modifying file
  local hash2
  hash2="$(intent_hash "$TEST_DIR/intent.md")"

  assert_eq "INV-013: intent hash consistent (create vs re-hash)" "$hash1" "$hash2"
}

test_inv013_intent_hash_on_supervisor_activation() {
  echo ""
  echo "=== INV-013: Intent hash checked on supervisor activation ==="

  local skill_file="$REPO_DIR/skills/cauto/SKILL.md"

  # cauto must verify intent hash before each supervisor activation
  file_contains_i "$skill_file" "intent.*hash.*verif\|verify.*intent.*hash\|intent.*mismatch.*hard.stop\|hash.*intent.*supervisor" \
    "INV-013: cauto verifies intent hash on supervisor activation"
}

# ============================================
# QA-005: Intent files in sensitive-file-guard defaults
# ============================================

test_qa005_intent_files_in_sfg() {
  echo ""
  echo "=== QA-005: Intent files in sensitive-file-guard protected defaults ==="

  local guard_hook="$REPO_DIR/hooks/sensitive-file-guard.sh"

  # SFG defaults must include intent-*.md pattern
  file_contains "$guard_hook" "intent-" \
    "QA-005: sensitive-file-guard defaults include intent file pattern"
}

# ============================================
# Runner
# ============================================

echo "============================================="
echo "Auto Mode Phase 2 — Report + Intent"
echo "============================================="

# INV-009: Auto Run Report
test_inv009_report_generated
test_inv009_report_required_sections
test_inv009_report_on_pause
test_inv009_report_budget_exceeded_status
test_inv009_decision_summary_by_tier

# INV-013: Intent summary
test_inv013_intent_create_and_hash
test_inv013_intent_verify_match
test_inv013_intent_verify_mismatch
test_inv013_intent_immutable
test_inv013_intent_hash_on_supervisor_activation

# QA-005: Intent files in SFG
test_qa005_intent_files_in_sfg

echo ""
echo "============================================="
echo "Results: $PASS passed, $FAIL failed"
echo ""

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
