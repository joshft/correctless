#!/usr/bin/env bash
# Correctless — Auto Mode Phase 2: Workflow State Extensions test suite
# Track 0: Tests the 5 new workflow state fields and their atomic read/write
# via scripts/workflow-state-ext.sh
# RED phase: these tests MUST FAIL — implementation does not exist yet.
# Run from repo root: bash tests/test-auto-state-ext.sh

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
# Track 0: Workflow State Extensions
# Tests the 5 new fields: supervisor_activation_count,
# decision_record_size, intent_hash, policy_hash, pipeline_start_time
# ============================================

# Source once at top level to avoid RETURN trap + source interaction
# (bash fires RETURN trap when 'source' completes inside a function)
source "$REPO_DIR/scripts/workflow-state-ext.sh"

# Tests Track-0 [unit]: ws_set_field and ws_get_field for supervisor_activation_count
test_ws_supervisor_activation_count() {
  echo ""
  echo "=== Track-0: ws_set_field/ws_get_field — supervisor_activation_count ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  # Create a minimal state file
  echo '{"phase":"review","branch":"test"}' > "$TEST_DIR/state.json"

  # Set supervisor_activation_count to 0
  ws_set_field "$TEST_DIR/state.json" "supervisor_activation_count" "0"
  local result
  result="$(ws_get_field "$TEST_DIR/state.json" "supervisor_activation_count")"
  assert_eq "Track-0: supervisor_activation_count set to 0 and read back" "0" "$result"

  # Set to 5 and read back
  ws_set_field "$TEST_DIR/state.json" "supervisor_activation_count" "5"
  result="$(ws_get_field "$TEST_DIR/state.json" "supervisor_activation_count")"
  assert_eq "Track-0: supervisor_activation_count updated to 5" "5" "$result"
}

# Tests Track-0 [unit]: ws_set_field and ws_get_field for decision_record_size
test_ws_decision_record_size() {
  echo ""
  echo "=== Track-0: ws_set_field/ws_get_field — decision_record_size ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  echo '{"phase":"tdd-impl","branch":"test"}' > "$TEST_DIR/state.json"

  ws_set_field "$TEST_DIR/state.json" "decision_record_size" "1024"
  local result
  result="$(ws_get_field "$TEST_DIR/state.json" "decision_record_size")"
  assert_eq "Track-0: decision_record_size set and read back" "1024" "$result"
}

# Tests Track-0 [unit]: ws_set_field and ws_get_field for intent_hash
test_ws_intent_hash() {
  echo ""
  echo "=== Track-0: ws_set_field/ws_get_field — intent_hash ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  echo '{"phase":"review","branch":"test"}' > "$TEST_DIR/state.json"

  local test_hash="abc123def456"
  ws_set_field "$TEST_DIR/state.json" "intent_hash" "$test_hash"
  local result
  result="$(ws_get_field "$TEST_DIR/state.json" "intent_hash")"
  assert_eq "Track-0: intent_hash set and read back" "$test_hash" "$result"
}

# Tests Track-0 [unit]: ws_set_field and ws_get_field for policy_hash
test_ws_policy_hash() {
  echo ""
  echo "=== Track-0: ws_set_field/ws_get_field — policy_hash ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  echo '{"phase":"review","branch":"test"}' > "$TEST_DIR/state.json"

  local test_hash="deadbeef0123"
  ws_set_field "$TEST_DIR/state.json" "policy_hash" "$test_hash"
  local result
  result="$(ws_get_field "$TEST_DIR/state.json" "policy_hash")"
  assert_eq "Track-0: policy_hash set and read back" "$test_hash" "$result"
}

# Tests Track-0 [unit]: ws_set_field and ws_get_field for pipeline_start_time
test_ws_pipeline_start_time() {
  echo ""
  echo "=== Track-0: ws_set_field/ws_get_field — pipeline_start_time ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  echo '{"phase":"review","branch":"test"}' > "$TEST_DIR/state.json"

  local test_time="2026-04-11T22:00:00Z"
  ws_set_field "$TEST_DIR/state.json" "pipeline_start_time" "$test_time"
  local result
  result="$(ws_get_field "$TEST_DIR/state.json" "pipeline_start_time")"
  assert_eq "Track-0: pipeline_start_time set and read back" "$test_time" "$result"
}

# Tests Track-0 [unit]: ws_increment_field atomically increments
test_ws_increment_field() {
  echo ""
  echo "=== Track-0: ws_increment_field — atomic increment ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  echo '{"phase":"review","branch":"test","supervisor_activation_count":3}' > "$TEST_DIR/state.json"

  ws_increment_field "$TEST_DIR/state.json" "supervisor_activation_count"
  local result
  result="$(ws_get_field "$TEST_DIR/state.json" "supervisor_activation_count")"
  assert_eq "Track-0: supervisor_activation_count incremented from 3 to 4" "4" "$result"

  # Increment again
  ws_increment_field "$TEST_DIR/state.json" "supervisor_activation_count"
  result="$(ws_get_field "$TEST_DIR/state.json" "supervisor_activation_count")"
  assert_eq "Track-0: supervisor_activation_count incremented from 4 to 5" "5" "$result"
}

# Tests Track-0 [unit]: Fields persist across crash (write, re-source, read)
test_ws_persistence_across_crash() {
  echo ""
  echo "=== Track-0: Fields persist across crash simulation ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  echo '{"phase":"review","branch":"test"}' > "$TEST_DIR/state.json"

  # Write all 5 fields in one "session"
  (
    source "$REPO_DIR/scripts/workflow-state-ext.sh"
    ws_set_field "$TEST_DIR/state.json" "supervisor_activation_count" "7"
    ws_set_field "$TEST_DIR/state.json" "decision_record_size" "2048"
    ws_set_field "$TEST_DIR/state.json" "intent_hash" "hash_intent_abc"
    ws_set_field "$TEST_DIR/state.json" "policy_hash" "hash_policy_def"
    ws_set_field "$TEST_DIR/state.json" "pipeline_start_time" "2026-04-11T10:00:00Z"
  )

  # Read back in a fresh "session" (simulates crash + restart)
  # Functions already sourced at top level — just call them
  local result

  result="$(ws_get_field "$TEST_DIR/state.json" "supervisor_activation_count")"
  assert_eq "Track-0: supervisor_activation_count persists across crash" "7" "$result"

  result="$(ws_get_field "$TEST_DIR/state.json" "decision_record_size")"
  assert_eq "Track-0: decision_record_size persists across crash" "2048" "$result"

  result="$(ws_get_field "$TEST_DIR/state.json" "intent_hash")"
  assert_eq "Track-0: intent_hash persists across crash" "hash_intent_abc" "$result"

  result="$(ws_get_field "$TEST_DIR/state.json" "policy_hash")"
  assert_eq "Track-0: policy_hash persists across crash" "hash_policy_def" "$result"

  result="$(ws_get_field "$TEST_DIR/state.json" "pipeline_start_time")"
  assert_eq "Track-0: pipeline_start_time persists across crash" "2026-04-11T10:00:00Z" "$result"
}

# Tests Track-0 [unit]: Existing fields are preserved when new fields are set
test_ws_existing_fields_preserved() {
  echo ""
  echo "=== Track-0: Existing state fields preserved ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  echo '{"phase":"tdd-impl","branch":"feature-x","feature_intensity":"high"}' > "$TEST_DIR/state.json"

  ws_set_field "$TEST_DIR/state.json" "supervisor_activation_count" "1"

  # Verify existing fields are still there
  local phase
  phase="$(jq -r '.phase' "$TEST_DIR/state.json" 2>/dev/null)"
  assert_eq "Track-0: existing .phase preserved after setting new field" "tdd-impl" "$phase"

  local branch
  branch="$(jq -r '.branch' "$TEST_DIR/state.json" 2>/dev/null)"
  assert_eq "Track-0: existing .branch preserved after setting new field" "feature-x" "$branch"

  local fi_val
  fi_val="$(jq -r '.feature_intensity' "$TEST_DIR/state.json" 2>/dev/null)"
  assert_eq "Track-0: existing .feature_intensity preserved after setting new field" "high" "$fi_val"
}

# ============================================
# Runner
# ============================================

echo "============================================="
echo "Auto Mode Phase 2 — Workflow State Extensions"
echo "============================================="

test_ws_supervisor_activation_count
test_ws_decision_record_size
test_ws_intent_hash
test_ws_policy_hash
test_ws_pipeline_start_time
test_ws_increment_field
test_ws_persistence_across_crash
test_ws_existing_fields_preserved

echo ""
echo "============================================="
echo "Results: $PASS passed, $FAIL failed"
echo ""

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
