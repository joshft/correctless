#!/usr/bin/env bash
# Correctless — Auto Mode Phase 3: Override Scrutiny test suite
# Track 3: Tests INV-035, INV-036, INV-037, INV-038, INV-039, PRH-006, BND-006, BND-008
# RED phase: these tests MUST FAIL — implementation does not exist yet.
# Run from repo root: bash tests/test-auto-override.sh

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
source "$REPO_DIR/scripts/override-scrutiny.sh"

# ============================================
# INV-035 [integration]: Override issuance triggers supervisor
# ============================================

test_inv035_issuance_payload() {
  echo ""
  echo "=== INV-035: Override issuance payload contains required fields ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  cat > "$TEST_DIR/decision-record.md" << 'DR_EOF'
## Decision Record

### DD-001
- **Summary**: Fixed auth issue
- **Disposition**: fix

### DD-002
- **Summary**: Added test helper
- **Disposition**: fix
DR_EOF

  local result
  result="$(build_override_issuance_payload "Build fails due to missing stub" "tdd-impl" "Build a policy engine" "$TEST_DIR/decision-record.md" 2>/dev/null)"
  local rc=$?

  assert_eq "INV-035: build_override_issuance_payload exits 0" "0" "$rc"

  # Must be valid JSON
  local is_json="no"
  echo "$result" | jq '.' >/dev/null 2>&1 && is_json="yes"
  assert_eq "INV-035: issuance payload is valid JSON" "yes" "$is_json"

  # Must contain override_reason
  assert_contains "INV-035: payload contains override reason" "Build fails" "$result"

  # Must contain phase
  assert_contains "INV-035: payload contains phase" "tdd-impl" "$result"

  # Must contain intent_summary
  assert_contains "INV-035: payload contains intent_summary" "policy engine" "$result"
}

test_inv035_issuance_with_crosscheck_evidence() {
  echo ""
  echo "=== INV-035: Override issuance review receives cross-check evidence ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  echo '{"phase":"tdd-impl","override":{"active":false}}' > "$TEST_DIR/state.json"
  echo "## Decision Record" > "$TEST_DIR/decision-record.md"

  # Pre-computed cross-check evidence (per fixture contract with Track 4)
  local crosscheck_evidence='{"pre_existing_claimed":true,"base_commit":"abc123","base_build_success":false,"base_build_exit_code":1,"base_build_stderr":"error: missing stub","claim_verified":true,"failure_mode":null}'

  local result
  result="$(review_override_issuance "$TEST_DIR/state.json" "Pre-existing build error" "tdd-impl" "Build a policy engine" "$TEST_DIR/decision-record.md" "$crosscheck_evidence" 2>/dev/null)"
  local rc=$?

  assert_eq "INV-035: review_override_issuance exits 0" "0" "$rc"

  # Must return a valid disposition
  local is_valid_disposition="no"
  case "$result" in
    approve_override|reject_override|escalate_to_human) is_valid_disposition="yes" ;;
  esac
  assert_eq "INV-035: issuance review returns valid disposition" "yes" "$is_valid_disposition"
}

# ============================================
# INV-036 [integration]: Sustained review during override window
# ============================================

test_inv036_action_payload() {
  echo ""
  echo "=== INV-036: Override action payload contains required fields ==="

  local result
  result="$(build_override_action_payload "Commit: fix stub return value" "Build fails due to missing stub" "Build a policy engine" '[{"id":"DD-003","summary":"Added stub"}]' 2>/dev/null)"
  local rc=$?

  assert_eq "INV-036: build_override_action_payload exits 0" "0" "$rc"

  local is_json="no"
  echo "$result" | jq '.' >/dev/null 2>&1 && is_json="yes"
  assert_eq "INV-036: action payload is valid JSON" "yes" "$is_json"

  # Must contain action description
  assert_contains "INV-036: payload contains action" "fix stub" "$result"

  # Must contain override reason
  assert_contains "INV-036: payload contains override reason" "Build fails" "$result"

  # Must contain intent summary
  assert_contains "INV-036: payload contains intent" "policy engine" "$result"
}

test_inv036_action_review_with_drift_evidence() {
  echo ""
  echo "=== INV-036: Override action review receives drift evidence ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  echo '{"phase":"tdd-impl","override":{"active":true}}' > "$TEST_DIR/state.json"

  # Drift evidence (per fixture contract with Track 4)
  local drift_evidence='{"touched_files":["scripts/review-triage.sh"],"in_scope_files":["scripts/review-triage.sh"],"out_of_scope_files":[],"scope_drift_detected":false}'

  local result
  result="$(review_override_action "$TEST_DIR/state.json" "Edit scripts/review-triage.sh" "Build fails due to missing stub" "Build a policy engine" "[]" "$drift_evidence" 2>/dev/null)"
  local rc=$?

  assert_eq "INV-036: review_override_action exits 0" "0" "$rc"

  local is_valid_disposition="no"
  case "$result" in
    approve_action|reject_action|escalate_to_human) is_valid_disposition="yes" ;;
  esac
  assert_eq "INV-036: action review returns valid disposition" "yes" "$is_valid_disposition"
}

# ============================================
# INV-037 [integration]: Closure review with pretext check
# ============================================

test_inv037_closure_review() {
  echo ""
  echo "=== INV-037: Override closure review returns valid disposition ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  echo '{"phase":"tdd-impl","override":{"active":true}}' > "$TEST_DIR/state.json"

  # Completeness evidence (per fixture contract with Track 4)
  local completeness_evidence='{"declared_deliverables":["scripts/review-triage.sh"],"completed_deliverables":["scripts/review-triage.sh"],"missing_deliverables":[],"check_applicable":true,"complete":true}'

  local result
  result="$(review_override_closure "$TEST_DIR/state.json" "Build fails due to missing stub" '["Fixed stub return value","Added error handling"]' "Build a policy engine" '[]' "$completeness_evidence" 2>/dev/null)"
  local rc=$?

  assert_eq "INV-037: review_override_closure exits 0" "0" "$rc"

  local is_valid_disposition="no"
  case "$result" in
    approve_window|reject_window|partial_accept) is_valid_disposition="yes" ;;
  esac
  assert_eq "INV-037: closure review returns valid disposition" "yes" "$is_valid_disposition"
}

test_inv037_closure_pretext_check() {
  echo ""
  echo "=== INV-037: Closure review checks pretext — work must address override reason ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  echo '{"phase":"tdd-impl","override":{"active":true}}' > "$TEST_DIR/state.json"

  # Completeness evidence where deliverables are missing (pretext scenario)
  local completeness_evidence='{"declared_deliverables":["scripts/review-triage.sh","scripts/override-scrutiny.sh"],"completed_deliverables":["scripts/review-triage.sh"],"missing_deliverables":["scripts/override-scrutiny.sh"],"check_applicable":true,"complete":false}'

  local result
  result="$(review_override_closure "$TEST_DIR/state.json" "Build error X requires fixing both files" '["Fixed review-triage.sh only"]' "Build a policy engine" '[]' "$completeness_evidence" 2>/dev/null)"
  local rc=$?

  assert_eq "INV-037: closure review with incomplete deliverables exits 0" "0" "$rc"

  # When deliverables are missing, should not approve_window
  assert_not_contains "INV-037: incomplete deliverables should not produce approve_window" "approve_window" "$result"
}

# ============================================
# INV-038 [unit]: Override activations exempt from 20-cap
# ============================================

test_inv038_separate_counter() {
  echo ""
  echo "=== INV-038: Override activations use separate counter ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  echo '{"phase":"tdd-impl","supervisor_activation_count":15,"override_activation_count":0}' > "$TEST_DIR/state.json"

  local count
  count="$(track_override_activations "$TEST_DIR/state.json" 2>/dev/null)"
  local rc=$?

  assert_eq "INV-038: track_override_activations exits 0" "0" "$rc"
  assert_eq "INV-038: first override activation returns count 1" "1" "$count"

  # Main supervisor count should be unchanged
  local main_count
  main_count="$(jq -r '.supervisor_activation_count' "$TEST_DIR/state.json" 2>/dev/null)" || main_count="0"
  assert_eq "INV-038: main supervisor count unchanged at 15" "15" "$main_count"
}

test_inv038_soft_cap_at_50() {
  echo ""
  echo "=== INV-038: Override soft cap triggers at 50 ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  echo '{"phase":"tdd-impl","override_activation_count":49}' > "$TEST_DIR/state.json"

  local result
  result="$(check_override_soft_cap "$TEST_DIR/state.json" 2>/dev/null)"
  assert_eq "INV-038: count=49 → ok" "ok" "$result"

  echo '{"phase":"tdd-impl","override_activation_count":50}' > "$TEST_DIR/state.json"

  result="$(check_override_soft_cap "$TEST_DIR/state.json" 2>/dev/null)"
  assert_eq "INV-038: count=50 → escalate" "escalate" "$result"
}

# ============================================
# INV-039 [integration]: Override log schema
# ============================================

test_inv039_override_log_fields() {
  echo ""
  echo "=== INV-039: Override log includes supervisor review fields ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  echo '{"phase":"tdd-impl","override_log":[]}' > "$TEST_DIR/state.json"

  # Add issuance review
  update_override_log "$TEST_DIR/state.json" "OVR-001" "supervisor_issuance_review" "approve_override" "Override reason aligns with intent"
  local rc=$?
  assert_eq "INV-039: update_override_log (issuance) exits 0" "0" "$rc"

  # Add action review
  update_override_log "$TEST_DIR/state.json" "OVR-001" "supervisor_action_reviews" "approve_action" "Action within scope"
  rc=$?
  assert_eq "INV-039: update_override_log (action) exits 0" "0" "$rc"

  # Add closure review
  update_override_log "$TEST_DIR/state.json" "OVR-001" "supervisor_closure_review" "approve_window" "Work addresses override reason"
  rc=$?
  assert_eq "INV-039: update_override_log (closure) exits 0" "0" "$rc"

  # Verify log contains all three review types
  local log_json
  log_json="$(jq '.override_log' "$TEST_DIR/state.json" 2>/dev/null)" || log_json="[]"

  local has_issuance="no"
  echo "$log_json" | jq -e '.[] | select(.review_type == "supervisor_issuance_review")' >/dev/null 2>&1 && has_issuance="yes"
  assert_eq "INV-039: log contains supervisor_issuance_review" "yes" "$has_issuance"

  local has_action="no"
  echo "$log_json" | jq -e '.[] | select(.review_type == "supervisor_action_reviews")' >/dev/null 2>&1 && has_action="yes"
  assert_eq "INV-039: log contains supervisor_action_reviews" "yes" "$has_action"

  local has_closure="no"
  echo "$log_json" | jq -e '.[] | select(.review_type == "supervisor_closure_review")' >/dev/null 2>&1 && has_closure="yes"
  assert_eq "INV-039: log contains supervisor_closure_review" "yes" "$has_closure"
}

test_inv039_backward_compat() {
  echo ""
  echo "=== INV-039: Override log backward compatible with legacy entries ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  # State with legacy override log entry (no supervisor fields)
  echo '{"phase":"tdd-impl","override_log":[{"override_id":"OVR-LEGACY","reason":"test","active":false}]}' > "$TEST_DIR/state.json"

  # Adding a new-format entry should not break parsing of the legacy entry
  update_override_log "$TEST_DIR/state.json" "OVR-002" "supervisor_issuance_review" "approve_override" "Valid override"
  local rc=$?
  assert_eq "INV-039: update_override_log with legacy entries exits 0" "0" "$rc"

  # Legacy entry must still be parseable
  local legacy_id
  legacy_id="$(jq -r '.override_log[0].override_id' "$TEST_DIR/state.json" 2>/dev/null)" || legacy_id=""
  assert_eq "INV-039: legacy entry preserved" "OVR-LEGACY" "$legacy_id"
}

# ============================================
# PRH-006 [unit]: Jaccard similarity retry prevention
# ============================================

test_prh006_jaccard_identical() {
  echo ""
  echo "=== PRH-006: Jaccard similarity — identical texts ==="

  local result
  result="$(jaccard_similarity "build fails due to missing stub function" "build fails due to missing stub function" 2>/dev/null)"
  local rc=$?

  assert_eq "PRH-006: jaccard_similarity exits 0" "0" "$rc"

  # Identical texts should have similarity 1.0
  assert_eq "PRH-006: identical texts have similarity 1.0" "1.0" "$result"
}

test_prh006_jaccard_different() {
  echo ""
  echo "=== PRH-006: Jaccard similarity — completely different texts ==="

  local result
  result="$(jaccard_similarity "build fails due to missing stub" "network timeout connecting to database" 2>/dev/null)"
  local rc=$?

  assert_eq "PRH-006: jaccard_similarity exits 0" "0" "$rc"

  # Completely different texts should have low similarity
  local is_low="no"
  if command -v bc >/dev/null 2>&1; then
    [ "$(echo "$result < 0.4" | bc -l 2>/dev/null)" = "1" ] && is_low="yes"
  else
    # Fallback: check it's 0.0 or similar low value
    [ "$result" = "0.0" ] || [ "$result" = "0" ] && is_low="yes"
  fi
  assert_eq "PRH-006: different texts have similarity < 0.4" "yes" "$is_low"
}

test_prh006_jaccard_synonym_reword() {
  echo ""
  echo "=== PRH-006: Jaccard similarity — synonym rewording caught ==="

  # Synonym reword: same meaning, slightly different words
  local result
  result="$(jaccard_similarity "build fails because stub function is missing" "build fails due to missing stub function" 2>/dev/null)"
  local rc=$?

  assert_eq "PRH-006: jaccard_similarity exits 0" "0" "$rc"

  # Synonym rewording should have similarity >= 0.4
  local is_high="no"
  if command -v bc >/dev/null 2>&1; then
    [ "$(echo "$result >= 0.4" | bc -l 2>/dev/null)" = "1" ] && is_high="yes"
  else
    [ "$result" = "1.0" ] && is_high="yes"
  fi
  assert_eq "PRH-006: synonym reword has similarity >= 0.4" "yes" "$is_high"
}

test_prh006_override_retry_rejected() {
  echo ""
  echo "=== PRH-006: Override retry detected and rejected ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  # State with a rejected override reason
  echo '{"phase":"tdd-impl","rejected_overrides":["Build fails due to missing stub function"]}' > "$TEST_DIR/state.json"

  # Try to re-issue with similar reason
  check_override_retry "Build fails because stub function is missing" "$TEST_DIR/state.json"
  local rc=$?
  assert_eq "PRH-006: similar override reason rejected (rc=1)" "1" "$rc"
}

test_prh006_override_distinct_allowed() {
  echo ""
  echo "=== PRH-006: Distinct override reason allowed ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  echo '{"phase":"tdd-impl","rejected_overrides":["Build fails due to missing stub function"]}' > "$TEST_DIR/state.json"

  # Completely different reason
  check_override_retry "Network timeout connecting to remote database" "$TEST_DIR/state.json"
  local rc=$?
  assert_eq "PRH-006: distinct override reason allowed (rc=0)" "0" "$rc"
}

# ============================================
# BND-006 [unit]: Supervisor fails during override
# ============================================

test_bnd006_issuance_failure_escalates() {
  echo ""
  echo "=== BND-006: Issuance failure escalates to human ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  echo '{"phase":"tdd-impl"}' > "$TEST_DIR/state.json"
  echo "## Decision Record" > "$TEST_DIR/decision-record.md"

  # Pass empty/invalid cross-check evidence to simulate failure path
  local result
  result="$(review_override_issuance "$TEST_DIR/state.json" "Build error" "tdd-impl" "Intent" "$TEST_DIR/decision-record.md" "INVALID_JSON" 2>/dev/null)"

  # When supervisor fails for issuance, must escalate to human
  # The stub returns empty string (failure), which the caller treats as escalation
  # When implemented: failure → escalate_to_human
  local is_escalation="no"
  [ "$result" = "escalate_to_human" ] && is_escalation="yes"
  assert_eq "BND-006: issuance failure produces escalate_to_human" "yes" "$is_escalation"
}

test_bnd006_action_failure_rejects() {
  echo ""
  echo "=== BND-006: Action review failure rejects action ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  echo '{"phase":"tdd-impl","override":{"active":true}}' > "$TEST_DIR/state.json"

  # Invalid drift evidence to simulate failure
  local result
  result="$(review_override_action "$TEST_DIR/state.json" "Some action" "Override reason" "Intent" "[]" "INVALID_JSON" 2>/dev/null)"

  # When supervisor fails for action review, must reject action
  local is_rejection="no"
  [ "$result" = "reject_action" ] && is_rejection="yes"
  assert_eq "BND-006: action review failure produces reject_action" "yes" "$is_rejection"
}

test_bnd006_closure_failure_escalates() {
  echo ""
  echo "=== BND-006: Closure failure escalates to human ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  echo '{"phase":"tdd-impl","override":{"active":true}}' > "$TEST_DIR/state.json"

  local result
  result="$(review_override_closure "$TEST_DIR/state.json" "Override reason" "[]" "Intent" "[]" "INVALID_JSON" 2>/dev/null)"

  local is_escalation="no"
  [ "$result" = "escalate_to_human" ] && is_escalation="yes"
  assert_eq "BND-006: closure failure produces escalate_to_human" "yes" "$is_escalation"
}

# ============================================
# BND-008 [unit]: Intent tampered during override
# ============================================

test_bnd008_intent_tampered_hard_stop() {
  echo ""
  echo "=== BND-008: Intent hash mismatch during override triggers hard stop ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  # Create an intent file and compute its hash
  echo "Original intent content" > "$TEST_DIR/intent.md"

  # State with a WRONG intent hash (simulating tamper) and intent_file path
  jq -n --arg ifile "$TEST_DIR/intent.md" \
    '{"phase":"tdd-impl","override":{"active":true},"intent_hash":"wrong_hash_does_not_match","intent_file":$ifile}' \
    > "$TEST_DIR/state.json"

  # Call review_override_action with this state — the implementation must
  # detect the intent hash mismatch and return hard_stop or escalate_to_human
  local drift_evidence='{"touched_files":[],"in_scope_files":[],"out_of_scope_files":[],"scope_drift_detected":false}'

  local result
  result="$(review_override_action "$TEST_DIR/state.json" "Some action" "Build error" "Tampered intent" "[]" "$drift_evidence" 2>/dev/null)"

  # When intent is tampered during override, the function must return
  # hard_stop or escalate_to_human — never approve_action
  local is_safe="no"
  case "$result" in
    hard_stop|escalate_to_human) is_safe="yes" ;;
  esac
  assert_eq "BND-008: intent tampered produces hard_stop or escalate_to_human" "yes" "$is_safe"
}

test_bnd008_intent_hash_matching_proceeds() {
  echo ""
  echo "=== BND-008: Intent hash present AND matching — proceed (not hard_stop) ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  # Create an intent file and compute its real hash
  echo "Original intent content" > "$TEST_DIR/intent.md"
  local real_hash
  real_hash="$(sha256_hash_file "$TEST_DIR/intent.md")"

  # State with CORRECT intent hash and intent_file path
  jq -n --arg ifile "$TEST_DIR/intent.md" --arg ihash "$real_hash" \
    '{"phase":"tdd-impl","override":{"active":true},"intent_hash":$ihash,"intent_file":$ifile}' \
    > "$TEST_DIR/state.json"

  local drift_evidence='{"touched_files":[],"in_scope_files":[],"out_of_scope_files":[],"scope_drift_detected":false}'

  local result
  result="$(review_override_action "$TEST_DIR/state.json" "Some action" "Build reason" "Original intent" "[]" "$drift_evidence" 2>/dev/null)"

  # When intent hash matches, override window should be usable — expect approve_action
  assert_eq "BND-008: matching intent hash produces approve_action" "approve_action" "$result"
}

# ============================================
# INV-035 [integration]: False claim evidence produces rejection
# ============================================

test_inv035_false_claim_produces_reject() {
  echo ""
  echo "=== INV-035: False pre-existing claim evidence produces reject ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  echo '{"phase":"tdd-impl","override":{"active":false}}' > "$TEST_DIR/state.json"
  echo "## Decision Record" > "$TEST_DIR/decision-record.md"

  # Cross-check evidence where the pre-existing claim is FALSE
  local crosscheck_evidence='{"pre_existing_claimed":true,"base_commit":"abc123","base_build_success":true,"base_build_exit_code":0,"base_build_stderr":"","claim_verified":false,"failure_mode":null}'

  local result
  result="$(review_override_issuance "$TEST_DIR/state.json" "Pre-existing build error" "tdd-impl" "Build a policy engine" "$TEST_DIR/decision-record.md" "$crosscheck_evidence" 2>/dev/null)"

  # False claim must NOT produce approve_override
  local is_safe="no"
  case "$result" in
    reject_override|escalate_to_human) is_safe="yes" ;;
  esac
  assert_eq "INV-035: false pre-existing claim → reject_override or escalate_to_human" "yes" "$is_safe"
}

# ============================================
# INV-036 [integration]: Scope drift evidence produces escalation
# ============================================

test_inv036_scope_drift_produces_escalation() {
  echo ""
  echo "=== INV-036: Scope drift evidence produces escalate_to_human ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  echo '{"phase":"tdd-impl","override":{"active":true}}' > "$TEST_DIR/state.json"

  # Drift evidence: scope drift detected with out-of-scope files
  local drift_evidence='{"touched_files":["scripts/review-triage.sh","unrelated/file.sh"],"in_scope_files":["scripts/review-triage.sh"],"out_of_scope_files":["unrelated/file.sh"],"scope_drift_detected":true}'

  local result
  result="$(review_override_action "$TEST_DIR/state.json" "Edit unrelated/file.sh" "Build fails due to missing stub" "Build a policy engine" "[]" "$drift_evidence" 2>/dev/null)"

  # Per INV-041: scope drift triggers escalate_to_human, not reject_action
  assert_eq "INV-036: scope drift produces escalate_to_human" "escalate_to_human" "$result"
}

# ============================================
# INV-037 [integration]: Missing deliverables produces reject_window
# ============================================

test_inv037_missing_deliverables_rejects() {
  echo ""
  echo "=== INV-037: Missing deliverables evidence produces reject_window ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  echo '{"phase":"tdd-impl","override":{"active":true}}' > "$TEST_DIR/state.json"

  # Completeness evidence: deliverables are missing (per INV-042)
  local completeness_evidence='{"declared_deliverables":["scripts/review-triage.sh","scripts/missing.sh"],"completed_deliverables":["scripts/review-triage.sh"],"missing_deliverables":["scripts/missing.sh"],"check_applicable":true,"complete":false}'

  local result
  result="$(review_override_closure "$TEST_DIR/state.json" "Build fails due to missing stub" '["Fixed review-triage.sh only"]' "Build a policy engine" "[]" "$completeness_evidence" 2>/dev/null)"

  # Per INV-042: missing deliverables → reject_window
  assert_eq "INV-037: missing deliverables produces reject_window" "reject_window" "$result"
}

# ============================================
# Runner
# ============================================

echo "============================================="
echo "Auto Mode Phase 3 — Override Scrutiny"
echo "============================================="

# INV-035: Override issuance
test_inv035_issuance_payload
test_inv035_issuance_with_crosscheck_evidence
test_inv035_false_claim_produces_reject

# INV-036: Sustained review
test_inv036_action_payload
test_inv036_action_review_with_drift_evidence
test_inv036_scope_drift_produces_escalation

# INV-037: Closure review
test_inv037_closure_review
test_inv037_closure_pretext_check
test_inv037_missing_deliverables_rejects

# INV-038: Separate override counter
test_inv038_separate_counter
test_inv038_soft_cap_at_50

# INV-039: Override log schema
test_inv039_override_log_fields
test_inv039_backward_compat

# PRH-006: Jaccard retry prevention
test_prh006_jaccard_identical
test_prh006_jaccard_different
test_prh006_jaccard_synonym_reword
test_prh006_override_retry_rejected
test_prh006_override_distinct_allowed

# BND-006: Supervisor failure during override
test_bnd006_issuance_failure_escalates
test_bnd006_action_failure_rejects
test_bnd006_closure_failure_escalates

# BND-008: Intent tampered during override
test_bnd008_intent_tampered_hard_stop
test_bnd008_intent_hash_matching_proceeds

echo ""
echo "============================================="
echo "Results: $PASS passed, $FAIL failed"
echo ""

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
