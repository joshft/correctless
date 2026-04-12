#!/usr/bin/env bash
# Correctless — Auto Mode Phase 2: Budget + Hard Stop + Resume test suite
# Track 4: Tests INV-008, INV-010, BND-002, BND-005, BND-006, INV-015
# RED phase: these tests MUST FAIL — implementation does not exist yet.
# Run from repo root: bash tests/test-auto-budget.sh

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

assert_file_not_exists() {
  local desc="$1" path="$2"
  if [ ! -f "$path" ]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (file '$path' should not exist)"
    FAIL=$((FAIL + 1))
  fi
}

# ============================================
# Source scripts at top level to avoid RETURN trap + source interaction
source "$REPO_DIR/scripts/budget-check.sh"
source "$REPO_DIR/scripts/cauto-lock.sh"
source "$REPO_DIR/scripts/intent-hash.sh"
source "$REPO_DIR/scripts/auto-policy.sh"
source "$REPO_DIR/scripts/decision-record.sh"

# INV-008 [unit]: Budget enforcement — token + time
# ============================================

test_inv008_budget_ok_under_threshold() {
  echo ""
  echo "=== INV-008: Budget OK when under threshold ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  # Create a token log with moderate usage
  echo '{"total_tokens":100000,"timestamp":"2026-04-11T22:00:00Z"}' > "$TEST_DIR/token-log.jsonl"
  echo '{"total_tokens":100000,"timestamp":"2026-04-11T22:01:00Z"}' >> "$TEST_DIR/token-log.jsonl"

  # Create policy with budget limits
  cat > "$TEST_DIR/policy.json" << 'EOF'
{"budget":{"max_tokens":2000000,"warn_at_percent":75,"hard_stop_at_percent":100},"time":{"max_duration_hours":8,"warn_at_hours":6}}
EOF

  # Create state file with pipeline start time (recent)
  echo '{"pipeline_start_time":"'"$(date -u +%FT%TZ)"'"}' > "$TEST_DIR/state.json"


  local result
  result="$(budget_check "$TEST_DIR/token-log.jsonl" "$TEST_DIR/policy.json" "$TEST_DIR/state.json")"
  assert_contains "INV-008: budget under threshold → status ok" "ok" "$result"
}

test_inv008_budget_warn_at_75_percent() {
  echo ""
  echo "=== INV-008: Budget warning at 75% ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  # Create token log totaling ~1,600,000 tokens (80% of 2M)
  for i in $(seq 1 16); do
    echo "{\"total_tokens\":100000,\"timestamp\":\"2026-04-11T22:0${i}:00Z\"}" >> "$TEST_DIR/token-log.jsonl"
  done

  cat > "$TEST_DIR/policy.json" << 'EOF'
{"budget":{"max_tokens":2000000,"warn_at_percent":75,"hard_stop_at_percent":100},"time":{"max_duration_hours":8,"warn_at_hours":6}}
EOF

  echo '{"pipeline_start_time":"'"$(date -u +%FT%TZ)"'"}' > "$TEST_DIR/state.json"


  local result
  result="$(budget_check "$TEST_DIR/token-log.jsonl" "$TEST_DIR/policy.json" "$TEST_DIR/state.json")"
  assert_contains "INV-008: budget at 80% → status warn" "warn" "$result"
}

test_inv008_budget_hard_stop_at_100_percent() {
  echo ""
  echo "=== INV-008: Budget hard stop at 100% — non-negotiable ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  # Create token log totaling 2,100,000 tokens (105% of 2M)
  for i in $(seq 1 21); do
    echo "{\"total_tokens\":100000,\"timestamp\":\"2026-04-11T22:0${i}:00Z\"}" >> "$TEST_DIR/token-log.jsonl"
  done

  cat > "$TEST_DIR/policy.json" << 'EOF'
{"budget":{"max_tokens":2000000,"warn_at_percent":75,"hard_stop_at_percent":100},"time":{"max_duration_hours":8,"warn_at_hours":6}}
EOF

  echo '{"pipeline_start_time":"'"$(date -u +%FT%TZ)"'"}' > "$TEST_DIR/state.json"


  local result
  result="$(budget_check "$TEST_DIR/token-log.jsonl" "$TEST_DIR/policy.json" "$TEST_DIR/state.json")"
  assert_contains "INV-008: budget at 105% → status hard_stop" "hard_stop" "$result"
}

test_inv008_tier2_5_percent_threshold() {
  echo ""
  echo "=== INV-008: Tier 2 blocked when < 5% budget remaining ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  # 1,920,000 tokens used = 96% of 2M → only 4% remaining (< 5%)
  for i in $(seq 1 192); do
    echo "{\"total_tokens\":10000}" >> "$TEST_DIR/token-log.jsonl"
  done

  cat > "$TEST_DIR/policy.json" << 'EOF'
{"budget":{"max_tokens":2000000,"warn_at_percent":75,"hard_stop_at_percent":100}}
EOF

  echo '{"pipeline_start_time":"'"$(date -u +%FT%TZ)"'"}' > "$TEST_DIR/state.json"


  local token_usage
  token_usage="$(budget_get_token_usage "$TEST_DIR/token-log.jsonl")"

  # Calculate remaining percentage
  local remaining_pct
  if [ -n "$token_usage" ] && [ "$token_usage" != "unknown" ]; then
    remaining_pct=$(( (2000000 - token_usage) * 100 / 2000000 ))
    local should_block_tier2="no"
    [ "$remaining_pct" -lt 5 ] && should_block_tier2="yes"
    assert_eq "INV-008: < 5% budget remaining → should block Tier 2" "yes" "$should_block_tier2"
  else
    echo "  FAIL: INV-008: budget_get_token_usage returned empty/unknown (stub)"
    FAIL=$((FAIL + 1))
  fi
}

# ============================================
# INV-010 [integration]: Hard stop produces structured escalation file
# ============================================

test_inv010_escalation_file_structure() {
  echo ""
  echo "=== INV-010: Hard stop → structured escalation file ==="

  local skill_file="$REPO_DIR/skills/cauto/SKILL.md"

  # Escalation file must include resume command
  file_contains_i "$skill_file" "cauto resume\|/cauto resume" \
    "INV-010: escalation file includes resume command"

  # Escalation file must include numbered options
  file_contains_i "$skill_file" "numbered.*option\|option.*number\|options.*recommendation" \
    "INV-010: escalation file includes numbered options"
}

test_inv010_priority_ordering() {
  echo ""
  echo "=== INV-010: Hard stop priority ordering for multiple conditions ==="

  local skill_file="$REPO_DIR/skills/cauto/SKILL.md"

  # Must document priority ordering: integrity > security > budget > supervisor cap > other
  file_contains_i "$skill_file" "integrity.*security.*budget\|priority.*order\|highest.*priority" \
    "INV-010: cauto documents hard stop priority ordering"

  # Must log all active conditions as DD-xxx with tier "system"
  file_contains_i "$skill_file" "hard_stop_multiplex\|multiple.*hard.*stop\|simultaneous.*condition" \
    "INV-010: cauto logs all simultaneous hard stop conditions"
}

# ============================================
# BND-002 [unit]: Missing token log → token budget disabled, time active
# ============================================

test_bnd002_missing_token_log() {
  echo ""
  echo "=== BND-002: Missing token log → token budget disabled ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  # No token log created


  local token_usage
  token_usage="$(budget_get_token_usage "$TEST_DIR/nonexistent-token-log.jsonl" 2>/dev/null)"
  assert_eq "BND-002: missing token log → 'unknown'" "unknown" "$token_usage"
}

test_bnd002_time_budget_still_active() {
  echo ""
  echo "=== BND-002: Time budget still active when token log missing ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  # State file with start time 10 hours ago (exceeds 8h limit)
  # Use a fixed old timestamp
  echo '{"pipeline_start_time":"2026-04-11T10:00:00Z"}' > "$TEST_DIR/state.json"

  cat > "$TEST_DIR/policy.json" << 'EOF'
{"budget":{"max_tokens":2000000,"warn_at_percent":75,"hard_stop_at_percent":100},"time":{"max_duration_hours":8,"warn_at_hours":6}}
EOF


  # Even without token log, time budget should still enforce
  local elapsed
  elapsed="$(budget_get_elapsed "$TEST_DIR/state.json")"

  # elapsed must be a numeric value, not empty
  local is_numeric="no"
  [[ "$elapsed" =~ ^[0-9]+(\.[0-9]+)?$ ]] && is_numeric="yes"
  assert_eq "BND-002: elapsed time is numeric even without token log" "yes" "$is_numeric"
}

# ============================================
# BND-005 [unit]: Large decision record — supervisor reads only last 5
# ============================================

test_bnd005_supervisor_last_5_entries() {
  echo ""
  echo "=== BND-005: Supervisor reads only last 5 DD-xxx entries ==="

  local agent_file="$REPO_DIR/agents/supervisor.md"

  # Supervisor input docs must reference "last 5" or "recent"
  file_contains_i "$agent_file" "last 5\|recent.*5\|5.*recent\|decision_record_recent" \
    "BND-005: supervisor documents receiving last 5 entries"
}

# ============================================
# BND-006 [unit]: Concurrent invocations — lockfile
# ============================================

test_bnd006_lock_acquire_release() {
  echo ""
  echo "=== BND-006: Lock acquire and release ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  local lock_file="$TEST_DIR/cauto-lock-test"


  # Acquire lock
  lock_acquire "$lock_file"
  local rc=$?
  assert_eq "BND-006: lock_acquire succeeds" "0" "$rc"

  # Lock file should exist
  assert_file_exists "BND-006: lock file created" "$lock_file"

  # Release lock
  lock_release "$lock_file"
  rc=$?
  assert_eq "BND-006: lock_release succeeds" "0" "$rc"
}

test_bnd006_lock_prevents_concurrent() {
  echo ""
  echo "=== B-013/BND-006: Lock prevents concurrent — acquire/verify/re-acquire ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  local lock_file="$TEST_DIR/cauto-lock-test"


  # Step 1: Acquire lock via the function (not manual pre-population)
  lock_acquire "$lock_file"
  local rc=$?
  assert_eq "B-013/BND-006: first lock_acquire succeeds" "0" "$rc"

  # Step 2: Verify lockfile exists AND contains a PID
  assert_file_exists "B-013/BND-006: lockfile created by lock_acquire" "$lock_file"
  local pid_content
  pid_content="$(cat "$lock_file" 2>/dev/null)"
  local has_pid="no"
  [[ "$pid_content" =~ ^[0-9]+$ ]] && has_pid="yes"
  assert_eq "B-013/BND-006: lockfile contains numeric PID" "yes" "$has_pid"

  # Step 3: Second acquire should fail (locked)
  lock_acquire "$lock_file" 2>/dev/null
  rc=$?
  assert_eq "B-013/BND-006: second lock_acquire fails (already locked)" "1" "$rc"

  # Step 4: Release, then acquire again (should succeed)
  lock_release "$lock_file"
  lock_acquire "$lock_file"
  rc=$?
  assert_eq "B-013/BND-006: lock_acquire succeeds after release" "0" "$rc"

  # Cleanup
  lock_release "$lock_file"
}

test_bnd006_stale_lock_cleanup() {
  echo ""
  echo "=== BND-006: Stale lockfile cleanup ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  local lock_file="$TEST_DIR/cauto-lock-test"


  # Write a PID that doesn't exist (stale)
  echo "99999999" > "$lock_file"

  lock_check_stale "$lock_file"
  local rc=$?
  assert_eq "BND-006: stale lock detected (PID not running)" "0" "$rc"
}

test_bnd006_corrupted_lockfile_refuse() {
  echo ""
  echo "=== BND-006: Corrupted lockfile → refuse to start ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  local lock_file="$TEST_DIR/cauto-lock-test"


  # Write garbage (not a parseable PID)
  echo "not_a_pid_value" > "$lock_file"

  lock_check_stale "$lock_file"
  local rc=$?
  assert_eq "BND-006: corrupted lockfile → exit 2 (refuse)" "2" "$rc"
}

# ============================================
# INV-015 [integration]: Resume from hard stop
# ============================================

test_inv015_resume_integration() {
  echo ""
  echo "=== INV-015: Resume from hard stop — integration ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  # Set up all the artifacts that a real hard stop would leave behind

  # 1. Intent file with known hash
  local intent_content="Build feature X with constraints Y and Z"
  echo "$intent_content" > "$TEST_DIR/intent.md"

  local stored_hash
  stored_hash="$(intent_hash "$TEST_DIR/intent.md")"

  # 2. Policy file with known hash
  echo '{"security":{"never_relax_autonomously":true}}' > "$TEST_DIR/policy.json"

  local policy_stored_hash
  policy_stored_hash="$(policy_hash "$TEST_DIR/policy.json")"

  # 3. State file with hashes and phase
  cat > "$TEST_DIR/state.json" << STATE_EOF
{
  "phase": "tdd-qa",
  "intent_hash": "$stored_hash",
  "policy_hash": "$policy_stored_hash",
  "supervisor_activation_count": 3,
  "decision_record_size": 500,
  "pipeline_start_time": "2026-04-11T20:00:00Z"
}
STATE_EOF

  # 4. Decision record (must be >= decision_record_size stored in state)
  echo "## Decision Record" > "$TEST_DIR/decision-record.md"
  # Pad the file to be >= 500 bytes to match the stored decision_record_size
  for i in $(seq 1 20); do
    echo "DD-001: initial intent line $i with padding to reach stored size baseline" >> "$TEST_DIR/decision-record.md"
  done

  # 5. Escalation file
  cat > "$TEST_DIR/escalation.md" << 'ESC_EOF'
---
failed_at_phase: tdd-qa
completed_skills: [ctdd, simplify]
---

## Hard Stop: Budget exceeded

Options:
1. Continue with reduced scope (recommended)
2. Abort and start fresh
3. Increase budget limit

Resume: `/cauto resume "1"`
ESC_EOF

  # Verify: intent hash still matches (no tamper)
  intent_verify "$TEST_DIR/intent.md" "$stored_hash"
  local intent_rc=$?
  assert_eq "INV-015: intent hash verification passes on resume" "0" "$intent_rc"

  # Verify: policy hash still matches (no tamper)
  local current_policy_hash
  current_policy_hash="$(policy_hash "$TEST_DIR/policy.json")"
  assert_eq "INV-015: policy hash matches on resume" "$policy_stored_hash" "$current_policy_hash"

  # Verify: state file has required resume fields
  local phase
  phase="$(jq -r '.phase' "$TEST_DIR/state.json" 2>/dev/null)"
  assert_eq "INV-015: state file has correct paused phase" "tdd-qa" "$phase"

  # Verify: decision record size check
  local actual_size
  actual_size=$(wc -c < "$TEST_DIR/decision-record.md")
  dr_verify_size "$TEST_DIR/decision-record.md" "500"
  local size_rc=$?
  # Record should be >= 500 bytes (what was stored)
  # The actual file may be smaller since we just created a minimal one
  # This test verifies the stub fails (RED phase)
  assert_eq "INV-015: decision record size verification works" "0" "$size_rc"
}

test_inv015_resume_human_decision_logged() {
  echo ""
  echo "=== INV-015: Human decision logged as DD-xxx with tier 'human' ==="

  local skill_file="$REPO_DIR/skills/cauto/SKILL.md"

  # cauto must document logging human decisions
  file_contains_i "$skill_file" "tier.*human\|human.*tier\|DD-.*human" \
    "INV-015: cauto logs human decisions with tier 'human'"
}

test_inv015_stale_escalation_fresh_start() {
  echo ""
  echo "=== INV-015: Stale escalation file → fresh pipeline start ==="

  local skill_file="$REPO_DIR/skills/cauto/SKILL.md"

  # cauto must handle stale escalation (phase mismatch)
  file_contains_i "$skill_file" "stale.*escalation\|phase.*mismatch.*fresh\|fresh.*start\|start.*fresh" \
    "INV-015: cauto handles stale escalation with fresh start"
}

# ============================================
# B-006: INV-010 — Functional escalation file test
# ============================================

test_inv010_escalation_write_structure() {
  echo ""
  echo "=== B-006/INV-010: Escalation write — structured output ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  local escalation_file="$TEST_DIR/escalation.md"


  # Write escalation with hard stop details
  escalation_write "$escalation_file" \
    "tdd-qa" \
    "budget_exceeded" \
    '[{"id":"1","description":"Continue with reduced scope"},{"id":"2","description":"Abort and start fresh"},{"id":"3","description":"Increase budget limit"}]' \
    "budget"
  local rc=$?
  assert_eq "B-006/INV-010: escalation_write exits 0" "0" "$rc"

  # Verify output file contains required elements
  file_contains "$escalation_file" "tdd-qa" \
    "B-006/INV-010: escalation file contains phase where work stopped"

  # Verify numbered options present
  file_contains "$escalation_file" "1" \
    "B-006/INV-010: escalation file contains option 1"
  file_contains "$escalation_file" "2" \
    "B-006/INV-010: escalation file contains option 2"

  # Verify resume command
  file_contains "$escalation_file" "/cauto resume" \
    "B-006/INV-010: escalation file contains /cauto resume command"
}

test_inv010_escalation_priority_ordering() {
  echo ""
  echo "=== B-006/INV-010: Escalation priority ordering ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  local escalation_file="$TEST_DIR/escalation-priority.md"


  # Provide multiple conditions — integrity should be written first
  escalation_write "$escalation_file" \
    "review" \
    "multiple_conditions" \
    '[{"id":"1","description":"Fix integrity and retry"}]' \
    "integrity,security,budget"
  local rc=$?
  assert_eq "B-006/INV-010: escalation_write with multiple conditions exits 0" "0" "$rc"

  # The file should show the highest-priority reason first (integrity > security > budget)
  # Verify integrity appears before security in the file
  if [ -f "$escalation_file" ]; then
    local integrity_line security_line
    integrity_line="$(grep -n -i "integrity" "$escalation_file" 2>/dev/null | head -1 | cut -d: -f1)"
    security_line="$(grep -n -i "security" "$escalation_file" 2>/dev/null | head -1 | cut -d: -f1)"
    if [ -n "$integrity_line" ] && [ -n "$security_line" ]; then
      local order_correct="no"
      [ "$integrity_line" -lt "$security_line" ] && order_correct="yes"
      assert_eq "B-006/INV-010: integrity appears before security (priority order)" "yes" "$order_correct"
    else
      echo "  FAIL: B-006/INV-010: escalation file missing integrity or security mention (stub)"
      FAIL=$((FAIL + 1))
    fi
  else
    echo "  FAIL: B-006/INV-010: escalation file not created (stub)"
    FAIL=$((FAIL + 1))
  fi
}

# ============================================
# B-008: INV-015 — Resume option parsing test
# ============================================

test_inv015_resume_parse_numeric_option() {
  echo ""
  echo "=== B-008/INV-015: Resume parse — numeric option ==="


  local result
  result="$(resume_parse_decision "1" 2>/dev/null)"
  local rc=$?
  assert_eq "B-008/INV-015: resume_parse_decision '1' returns 0" "0" "$rc"

  # Result should contain the option number
  assert_contains "B-008/INV-015: parsed decision contains option 1" "1" "$result"
}

test_inv015_resume_parse_text_fallback() {
  echo ""
  echo "=== B-008/INV-015: Resume parse — text fallback (LLM interpretation) ==="


  local result
  result="$(resume_parse_decision "continue with reduced scope" 2>/dev/null)"
  local rc=$?
  assert_eq "B-008/INV-015: resume_parse_decision text returns 0" "0" "$rc"

  # Result should contain the text
  assert_contains "B-008/INV-015: parsed decision contains text" "continue with reduced scope" "$result"
}

test_inv015_resume_parse_becomes_dd_entry() {
  echo ""
  echo "=== B-008/INV-015: Resume parsed decision → DD-xxx with tier 'human' ==="


  local result
  result="$(resume_parse_decision "2" 2>/dev/null)"
  local rc=$?
  assert_eq "B-008/INV-015: resume_parse_decision exits 0" "0" "$rc"

  # The parsed result should be structured for DD-xxx creation with tier: "human"
  assert_contains "B-008/INV-015: parsed result includes tier human" "human" "$result"
}

# ============================================
# Runner
# ============================================

echo "============================================="
echo "Auto Mode Phase 2 — Budget + Hard Stop + Resume"
echo "============================================="

# INV-008: Budget enforcement
test_inv008_budget_ok_under_threshold
test_inv008_budget_warn_at_75_percent
test_inv008_budget_hard_stop_at_100_percent
test_inv008_tier2_5_percent_threshold

# INV-010: Hard stop escalation file
test_inv010_escalation_file_structure
test_inv010_priority_ordering

# B-006/INV-010: Functional escalation file tests
test_inv010_escalation_write_structure
test_inv010_escalation_priority_ordering

# BND-002: Missing token log
test_bnd002_missing_token_log
test_bnd002_time_budget_still_active

# BND-005: Large decision record
test_bnd005_supervisor_last_5_entries

# BND-006: Concurrent invocations
test_bnd006_lock_acquire_release
test_bnd006_lock_prevents_concurrent
test_bnd006_stale_lock_cleanup
test_bnd006_corrupted_lockfile_refuse

# INV-015: Resume integration
test_inv015_resume_integration
test_inv015_resume_human_decision_logged
test_inv015_stale_escalation_fresh_start

# B-008/INV-015: Resume option parsing
test_inv015_resume_parse_numeric_option
test_inv015_resume_parse_text_fallback
test_inv015_resume_parse_becomes_dd_entry

echo ""
echo "============================================="
echo "Results: $PASS passed, $FAIL failed"
echo ""

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
