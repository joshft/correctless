#!/usr/bin/env bash
# Correctless — Auto Mode Phase 2: Decision Record test suite
# Track 2: Tests INV-002, INV-003, INV-011, INV-016, BND-003
# RED phase: these tests MUST FAIL — implementation does not exist yet.
# Run from repo root: bash tests/test-decision-record.sh

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
# Fixture: valid DR-xxx JSON
# ============================================

valid_drx_json() {
  cat << 'DR_EOF'
{
  "decision_id": "DR-001",
  "requesting_agent": "ctdd",
  "phase": "tdd-impl",
  "category": "testability",
  "summary": "Test helper needs refactoring to support new assertion type",
  "severity": "medium",
  "options": [
    {"id": "A", "description": "Refactor helper inline", "loc_estimate": 20},
    {"id": "B", "description": "Create new helper function", "loc_estimate": 35}
  ],
  "relevant_rules": ["INV-003", "R-007"],
  "relevant_policies": ["review_dispositions.testability"],
  "prior_decisions": [
    {"decision_id": "DD-001", "summary": "Used existing pattern", "disposition": "fix"}
  ]
}
DR_EOF
}

# Fixture: valid DD-xxx entry
valid_dd_entry() {
  local id="${1:-DD-001}" tier="${2:-0}" category="${3:-testability}"
  cat << DD_EOF
{
  "decision_id": "$id",
  "tier": "$tier",
  "category": "$category",
  "summary": "Resolved via policy match",
  "disposition": "fix",
  "reasoning": "Policy review_dispositions.testability = fix",
  "timestamp": "2026-04-11T22:00:00Z"
}
DD_EOF
}

# ============================================
# Source scripts at top level to avoid RETURN trap + source interaction
source "$REPO_DIR/scripts/decision-record.sh"

# INV-002 [integration]: Every tier invocation → DD-xxx entry
# ============================================

test_inv002_dd_entry_per_tier() {
  echo ""
  echo "=== INV-002: Every tier invocation → DD-xxx entry ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  local record_file="$TEST_DIR/decision-record.md"
  : > "$record_file"


  # Append a DD-xxx entry for Tier 0 match
  local entry
  entry="$(valid_dd_entry "DD-001" "0" "security")"
  dr_append "$record_file" "$entry"
  local count
  count="$(dr_count_entries "$record_file")"
  assert_eq "INV-002: 1 DD-xxx entry after Tier 0 append" "1" "$count"

  # Append entry for Tier 1
  entry="$(valid_dd_entry "DD-002" "1" "testability")"
  dr_append "$record_file" "$entry"
  count="$(dr_count_entries "$record_file")"
  assert_eq "INV-002: 2 DD-xxx entries after Tier 1 append" "2" "$count"

  # Append entry for Tier 2
  entry="$(valid_dd_entry "DD-003" "2" "performance")"
  dr_append "$record_file" "$entry"
  count="$(dr_count_entries "$record_file")"
  assert_eq "INV-002: 3 DD-xxx entries after Tier 2 append" "3" "$count"
}

# Tests INV-002 [integration]: DD-xxx entry has all required fields
test_inv002_dd_required_fields() {
  echo ""
  echo "=== INV-002: DD-xxx entry has all required fields ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  local record_file="$TEST_DIR/decision-record.md"
  : > "$record_file"


  local entry
  entry="$(valid_dd_entry "DD-010" "2" "architecture")"
  dr_append "$record_file" "$entry"

  # Verify the record contains required fields
  file_contains "$record_file" "DD-010" \
    "INV-002: decision record contains decision_id DD-010"
  file_contains "$record_file" "architecture" \
    "INV-002: decision record contains category"
  file_contains "$record_file" "fix" \
    "INV-002: decision record contains disposition"
  file_contains "$record_file" "2026-04-11" \
    "INV-002: decision record contains timestamp"
}

# ============================================
# INV-003 [unit]: DR-xxx format validation
# ============================================

test_inv003_drx_valid_format() {
  echo ""
  echo "=== INV-003: DR-xxx valid format accepted ==="


  local dr_json
  dr_json="$(valid_drx_json)"
  drx_validate "$dr_json"
  local rc=$?
  assert_eq "INV-003: valid DR-xxx passes validation" "0" "$rc"
}

test_inv003_drx_missing_fields() {
  echo ""
  echo "=== INV-003: DR-xxx missing required fields → fail-closed ==="


  # Missing category (QA-004: all other required fields present to isolate test)
  local dr_json='{"decision_id":"DR-002","requesting_agent":"ctdd","phase":"review","summary":"test","options":[],"relevant_rules":[],"relevant_policies":[],"prior_decisions":[]}'
  drx_validate "$dr_json" 2>/dev/null
  local rc=$?
  assert_eq "INV-003: DR-xxx missing category → fail (exit 1)" "1" "$rc"

  # Missing decision_id
  dr_json='{"requesting_agent":"ctdd","phase":"review","category":"security","summary":"test","options":[],"relevant_rules":[],"relevant_policies":[],"prior_decisions":[]}'
  drx_validate "$dr_json" 2>/dev/null
  local rc2=$?
  assert_eq "INV-003: DR-xxx missing decision_id → fail" "1" "$rc2"

  # Missing summary
  dr_json='{"decision_id":"DR-003","requesting_agent":"ctdd","phase":"review","category":"security","options":[],"relevant_rules":[],"relevant_policies":[],"prior_decisions":[]}'
  drx_validate "$dr_json" 2>/dev/null
  local rc3=$?
  assert_eq "INV-003: DR-xxx missing summary → fail" "1" "$rc3"

  # Missing requesting_agent (QA-004: new field validation)
  dr_json='{"decision_id":"DR-004","phase":"review","category":"security","summary":"test","options":[],"relevant_rules":[],"relevant_policies":[],"prior_decisions":[]}'
  drx_validate "$dr_json" 2>/dev/null
  local rc4=$?
  assert_eq "INV-003: DR-xxx missing requesting_agent → fail" "1" "$rc4"

  # Missing options array (QA-004: new field validation)
  dr_json='{"decision_id":"DR-005","requesting_agent":"ctdd","phase":"review","category":"security","summary":"test","relevant_rules":[],"relevant_policies":[],"prior_decisions":[]}'
  drx_validate "$dr_json" 2>/dev/null
  local rc5=$?
  assert_eq "INV-003: DR-xxx missing options → fail" "1" "$rc5"
}

test_inv003_drx_invalid_category() {
  echo ""
  echo "=== INV-003: DR-xxx invalid category vocabulary → fail-closed ==="


  # Invalid category — not in controlled vocabulary
  local dr_json
  dr_json='{"decision_id":"DR-004","requesting_agent":"ctdd","phase":"review","category":"banana","summary":"test","options":[],"relevant_rules":[],"relevant_policies":[],"prior_decisions":[]}'
  drx_validate "$dr_json" 2>/dev/null
  local rc=$?
  assert_eq "INV-003: DR-xxx invalid category 'banana' → fail" "1" "$rc"
}

test_inv003_drx_valid_categories() {
  echo ""
  echo "=== INV-003: DR-xxx all valid categories accepted ==="


  local categories="security availability testability scope_expansion performance architecture observability technical_debt"
  for cat in $categories; do
    local dr_json
    dr_json="{\"decision_id\":\"DR-100\",\"requesting_agent\":\"ctdd\",\"phase\":\"review\",\"category\":\"$cat\",\"summary\":\"test\",\"options\":[],\"relevant_rules\":[],\"relevant_policies\":[],\"prior_decisions\":[]}"
    drx_validate "$dr_json" 2>/dev/null
    local rc=$?
    assert_eq "INV-003: category '$cat' is accepted" "0" "$rc"
  done
}

# ============================================
# INV-011 [unit]: ASSUMPTION tag on ambiguous decisions
# ============================================

test_inv011_assumption_tag() {
  echo ""
  echo "=== INV-011: ASSUMPTION tag on ambiguous decisions ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  local record_file="$TEST_DIR/decision-record.md"
  : > "$record_file"


  # Append an entry with ASSUMPTION tag
  local entry='{"decision_id":"DD-020","tier":"1","category":"architecture","summary":"ASSUMPTION: Database supports concurrent writes","disposition":"fix","reasoning":"Conservative assumption per ambiguity_policy","timestamp":"2026-04-11T22:00:00Z"}'
  dr_append "$record_file" "$entry"

  file_contains "$record_file" "ASSUMPTION" \
    "INV-011: ASSUMPTION tag present in decision record entry"
}

test_inv011_hedging_scan() {
  echo ""
  echo "=== INV-011: Post-pipeline hedging scan ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  local record_file="$TEST_DIR/decision-record.md"


  # Create record with entries — one has hedging language without ASSUMPTION tag
  : > "$record_file"
  dr_append "$record_file" '{"decision_id":"DD-030","tier":"1","category":"performance","summary":"We assume the cache is warm","disposition":"fix","reasoning":"Likely safe to proceed","timestamp":"2026-04-11T22:00:00Z"}'
  dr_append "$record_file" '{"decision_id":"DD-031","tier":"1","category":"security","summary":"ASSUMPTION: Auth tokens expire in 24h","disposition":"fix","reasoning":"Conservative default","timestamp":"2026-04-11T22:01:00Z"}'

  # Hedging scan should find DD-030 (has "assume", "likely" but no ASSUMPTION tag)
  local scan_result
  scan_result="$(dr_hedging_scan "$record_file")"
  assert_contains "INV-011: hedging scan finds untagged entry with 'assume'" "DD-030" "$scan_result"

  # DD-031 has ASSUMPTION tag — should NOT be flagged
  assert_not_contains "INV-011: hedging scan skips ASSUMPTION-tagged entries" "DD-031" "$scan_result"
}

# ============================================
# INV-016 [unit]: Append-only with size-regression detection
# ============================================

test_inv016_append_only_size_grows() {
  echo ""
  echo "=== INV-016: Append-only — size grows after each append ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  local record_file="$TEST_DIR/decision-record.md"
  : > "$record_file"


  # Get initial size
  local size_before
  size_before=$(wc -c < "$record_file")

  # Append an entry
  local entry
  entry="$(valid_dd_entry "DD-040" "0" "security")"
  dr_append "$record_file" "$entry"

  local size_after
  size_after=$(wc -c < "$record_file")

  local grew="no"
  [ "$size_after" -gt "$size_before" ] && grew="yes"
  assert_eq "INV-016: file size grew after append" "yes" "$grew"
}

test_inv016_size_regression_detected() {
  echo ""
  echo "=== INV-016: Size regression detected ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  local record_file="$TEST_DIR/decision-record.md"


  # Write some content
  echo "## Decision Record" > "$record_file"
  echo "DD-001: test entry with substantial content here for size baseline" >> "$record_file"

  local recorded_size
  recorded_size=$(wc -c < "$record_file")

  # Simulate truncation
  echo "DD-001" > "$record_file"

  # Verify size check detects the regression
  dr_verify_size "$record_file" "$recorded_size"
  local rc=$?
  assert_eq "INV-016: size regression (truncation) detected → exit 1" "1" "$rc"
}

test_inv016_size_ok_when_equal_or_larger() {
  echo ""
  echo "=== INV-016: Size OK when equal or larger ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  local record_file="$TEST_DIR/decision-record.md"
  echo "baseline content" > "$record_file"


  local baseline_size
  baseline_size=$(wc -c < "$record_file")

  # Size equals recorded → ok
  dr_verify_size "$record_file" "$baseline_size"
  local rc=$?
  assert_eq "INV-016: size equal to baseline → exit 0" "0" "$rc"

  # Grow the file
  echo "more content" >> "$record_file"
  dr_verify_size "$record_file" "$baseline_size"
  rc=$?
  assert_eq "INV-016: size larger than baseline → exit 0" "0" "$rc"
}

# ============================================
# BND-003 [unit]: Malformed DR-xxx → log error, escalate to Tier 3
# ============================================

test_bnd003_malformed_drx_not_dropped() {
  echo ""
  echo "=== BND-003: Malformed DR-xxx → escalate, never drop ==="


  # Completely invalid JSON
  local bad_json="not json at all {{"
  drx_validate "$bad_json" 2>/dev/null
  local rc=$?
  assert_eq "BND-003: invalid JSON → fail-closed (exit 1)" "1" "$rc"

  # Empty string
  drx_validate "" 2>/dev/null
  rc=$?
  assert_eq "BND-003: empty string → fail-closed (exit 1)" "1" "$rc"

  # Valid JSON but missing all required DR-xxx fields
  drx_validate '{"foo":"bar"}' 2>/dev/null
  rc=$?
  assert_eq "BND-003: JSON without DR-xxx fields → fail-closed (exit 1)" "1" "$rc"
}

# ============================================
# B-005: INV-002 — Cardinality verification integration test
# ============================================

test_inv002_cardinality_verification_match() {
  echo ""
  echo "=== B-005/INV-002: Cardinality verification — counts match ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  local record_file="$TEST_DIR/decision-record.md"
  local audit_file="$TEST_DIR/audit-trail.jsonl"
  : > "$record_file"
  : > "$audit_file"


  # Append DD-000 (intent creation — system tier, no audit counterpart)
  dr_append "$record_file" '{"decision_id":"DD-000","tier":"system","category":"intent","summary":"Pipeline intent established","disposition":"logged","reasoning":"Intent file created","timestamp":"2026-04-11T22:00:00Z"}'

  # Append DD-001 with matching audit event
  dr_append "$record_file" '{"decision_id":"DD-001","tier":"0","category":"security","summary":"Fix auth","disposition":"fix","reasoning":"Policy match","timestamp":"2026-04-11T22:01:00Z"}'
  echo '{"event":"decision_routed","tier":0,"decision_id":"DR-001","timestamp":"2026-04-11T22:01:00Z"}' >> "$audit_file"

  # Append DD-002 with matching audit event
  dr_append "$record_file" '{"decision_id":"DD-002","tier":"2","category":"performance","summary":"Optimize query","disposition":"fix","reasoning":"Tier 2 decision","timestamp":"2026-04-11T22:02:00Z"}'
  echo '{"event":"decision_routed","tier":2,"decision_id":"DR-002","timestamp":"2026-04-11T22:02:00Z"}' >> "$audit_file"

  # Append DD-003 with matching supervisor activation event
  dr_append "$record_file" '{"decision_id":"DD-003","tier":"3","category":"architecture","summary":"Approve phase transition","disposition":"approve","reasoning":"Supervisor approval","timestamp":"2026-04-11T22:03:00Z"}'
  echo '{"event":"supervisor_activated","activation_type":"phase_transition","activation_count":1,"timestamp":"2026-04-11T22:03:00Z"}' >> "$audit_file"

  # Cardinality check: DD count = decision_routed + supervisor_activated + 1 (DD-000)
  # 4 DD entries = 2 (decision_routed) + 1 (supervisor_activated) + 1 (DD-000)
  dr_verify_cardinality "$record_file" "$audit_file"
  local rc=$?
  assert_eq "B-005/INV-002: cardinality matches (4 = 2+1+1) → pass" "0" "$rc"
}

test_inv002_cardinality_verification_mismatch() {
  echo ""
  echo "=== B-005/INV-002: Cardinality verification — count mismatch ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  local record_file="$TEST_DIR/decision-record.md"
  local audit_file="$TEST_DIR/audit-trail.jsonl"
  : > "$record_file"
  : > "$audit_file"


  # DD-000 (system)
  dr_append "$record_file" '{"decision_id":"DD-000","tier":"system","category":"intent","summary":"Intent","disposition":"logged","reasoning":"Intent created","timestamp":"2026-04-11T22:00:00Z"}'

  # DD-001 with matching audit event
  dr_append "$record_file" '{"decision_id":"DD-001","tier":"0","category":"security","summary":"Fix","disposition":"fix","reasoning":"Policy","timestamp":"2026-04-11T22:01:00Z"}'
  echo '{"event":"decision_routed","tier":0,"decision_id":"DR-001","timestamp":"2026-04-11T22:01:00Z"}' >> "$audit_file"

  # DD-002 WITHOUT a corresponding audit event — this is the mismatch
  dr_append "$record_file" '{"decision_id":"DD-002","tier":"1","category":"testability","summary":"Self-resolved","disposition":"fix","reasoning":"Worker self-resolution","timestamp":"2026-04-11T22:02:00Z"}'

  # Cardinality check: 3 DD entries but only 1 decision_routed + 0 supervisor_activated + 1 DD-000 = 2
  # 3 != 2 → should fail
  dr_verify_cardinality "$record_file" "$audit_file" 2>/dev/null
  local rc=$?
  assert_eq "B-005/INV-002: cardinality mismatch (3 != 2) → fail (exit 1)" "1" "$rc"
}

# ============================================
# QA-007/QA-008: Cardinality with human_decision and system_event types
# ============================================

test_qa007_cardinality_with_human_decision() {
  echo ""
  echo "=== QA-007: Cardinality with human_decision event ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  local record_file="$TEST_DIR/decision-record.md"
  local audit_file="$TEST_DIR/audit-trail.jsonl"
  : > "$record_file"
  : > "$audit_file"

  # DD-000 (system, no audit counterpart)
  dr_append "$record_file" '{"decision_id":"DD-000","tier":"system","category":"intent","summary":"Intent","disposition":"logged","reasoning":"Intent created","timestamp":"2026-04-11T22:00:00Z"}'

  # DD-001 with decision_routed
  dr_append "$record_file" '{"decision_id":"DD-001","tier":"0","category":"security","summary":"Fix","disposition":"fix","reasoning":"Policy","timestamp":"2026-04-11T22:01:00Z"}'
  echo '{"event":"decision_routed","tier":0,"decision_id":"DR-001","timestamp":"2026-04-11T22:01:00Z"}' >> "$audit_file"

  # DD-002 with human_decision (from /cauto resume)
  dr_append "$record_file" '{"decision_id":"DD-002","tier":"human","category":"hard_stop_multiplex","summary":"Human chose option 1","disposition":"continue","reasoning":"Human decision","timestamp":"2026-04-11T22:02:00Z"}'
  echo '{"event":"human_decision","decision_id":"DR-002","timestamp":"2026-04-11T22:02:00Z"}' >> "$audit_file"

  # DD count = 3, expected = 1 (routed) + 0 (supervisor) + 1 (human) + 0 (system) + 1 (DD-000) = 3
  dr_verify_cardinality "$record_file" "$audit_file"
  local rc=$?
  assert_eq "QA-007: cardinality matches with human_decision event (3 = 1+0+1+0+1)" "0" "$rc"
}

test_qa007_cardinality_missing_human_event_fails() {
  echo ""
  echo "=== QA-007: Cardinality fails when human_decision audit event missing ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  local record_file="$TEST_DIR/decision-record.md"
  local audit_file="$TEST_DIR/audit-trail.jsonl"
  : > "$record_file"
  : > "$audit_file"

  # DD-000
  dr_append "$record_file" '{"decision_id":"DD-000","tier":"system","category":"intent","summary":"Intent","disposition":"logged","reasoning":"Intent created","timestamp":"2026-04-11T22:00:00Z"}'

  # DD-001 with decision_routed
  dr_append "$record_file" '{"decision_id":"DD-001","tier":"0","category":"security","summary":"Fix","disposition":"fix","reasoning":"Policy","timestamp":"2026-04-11T22:01:00Z"}'
  echo '{"event":"decision_routed","tier":0,"decision_id":"DR-001","timestamp":"2026-04-11T22:01:00Z"}' >> "$audit_file"

  # DD-002 human entry WITHOUT corresponding audit event — mismatch
  dr_append "$record_file" '{"decision_id":"DD-002","tier":"human","category":"hard_stop_multiplex","summary":"Human chose option 1","disposition":"continue","reasoning":"Human decision","timestamp":"2026-04-11T22:02:00Z"}'

  # DD count = 3, expected = 1 (routed) + 0 + 0 + 0 + 1 = 2 → mismatch
  dr_verify_cardinality "$record_file" "$audit_file" 2>/dev/null
  local rc=$?
  assert_eq "QA-007: cardinality mismatch without human_decision event (3 != 2)" "1" "$rc"
}

test_qa008_cardinality_with_system_event() {
  echo ""
  echo "=== QA-008: Cardinality with system_event type ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  local record_file="$TEST_DIR/decision-record.md"
  local audit_file="$TEST_DIR/audit-trail.jsonl"
  : > "$record_file"
  : > "$audit_file"

  # DD-000
  dr_append "$record_file" '{"decision_id":"DD-000","tier":"system","category":"intent","summary":"Intent","disposition":"logged","reasoning":"Intent created","timestamp":"2026-04-11T22:00:00Z"}'

  # DD-001 with decision_routed
  dr_append "$record_file" '{"decision_id":"DD-001","tier":"0","category":"security","summary":"Fix","disposition":"fix","reasoning":"Policy","timestamp":"2026-04-11T22:01:00Z"}'
  echo '{"event":"decision_routed","tier":0,"decision_id":"DR-001","timestamp":"2026-04-11T22:01:00Z"}' >> "$audit_file"

  # DD-002 system event (hard_stop_multiplex)
  dr_append "$record_file" '{"decision_id":"DD-002","tier":"system","category":"hard_stop_multiplex","summary":"Budget + time both exceeded","disposition":"hard_stop","reasoning":"System","timestamp":"2026-04-11T22:03:00Z"}'
  echo '{"event":"system_event","type":"hard_stop_multiplex","timestamp":"2026-04-11T22:03:00Z"}' >> "$audit_file"

  # DD count = 3, expected = 1 (routed) + 0 (supervisor) + 0 (human) + 1 (system) + 1 (DD-000) = 3
  dr_verify_cardinality "$record_file" "$audit_file"
  local rc=$?
  assert_eq "QA-008: cardinality matches with system_event (3 = 1+0+0+1+1)" "0" "$rc"
}

# ============================================
# Runner
# ============================================

echo "============================================="
echo "Auto Mode Phase 2 — Decision Record"
echo "============================================="

# INV-002: DD-xxx entries
test_inv002_dd_entry_per_tier
test_inv002_dd_required_fields

# B-005/INV-002: Cardinality verification
test_inv002_cardinality_verification_match
test_inv002_cardinality_verification_mismatch

# INV-003: DR-xxx format
test_inv003_drx_valid_format
test_inv003_drx_missing_fields
test_inv003_drx_invalid_category
test_inv003_drx_valid_categories

# INV-011: ASSUMPTION tagging + hedging scan
test_inv011_assumption_tag
test_inv011_hedging_scan

# INV-016: Append-only + size regression
test_inv016_append_only_size_grows
test_inv016_size_regression_detected
test_inv016_size_ok_when_equal_or_larger

# BND-003: Malformed DR-xxx
test_bnd003_malformed_drx_not_dropped

# QA-007/QA-008: Cardinality with all event types
test_qa007_cardinality_with_human_decision
test_qa007_cardinality_missing_human_event_fails
test_qa008_cardinality_with_system_event

echo ""
echo "============================================="
echo "Results: $PASS passed, $FAIL failed"
echo ""

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
