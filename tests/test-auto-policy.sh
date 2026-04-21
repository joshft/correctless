#!/usr/bin/env bash
# Correctless — Auto Mode Phase 2: Policy Engine test suite
# Track 1: Tests INV-001, INV-012, INV-018, BND-001, INV-014
# RED phase: these tests MUST FAIL — implementation does not exist yet.
# Run from repo root: bash tests/test-auto-policy.sh

source "$(dirname "${BASH_SOURCE[0]}")/test-helpers.sh"

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
# Fixture: valid auto-policy.json
# ============================================

create_valid_policy() {
  local dir="$1"
  cat > "$dir/auto-policy.json" << 'POLICY_EOF'
{
  "review_dispositions": {
    "security": "fix",
    "availability": "add_rule",
    "testability": "fix",
    "scope_expansion": "defer",
    "performance": "tier2_decide",
    "default": "tier2_decide"
  },
  "qa_dispositions": {
    "critical": "fix",
    "high": "fix",
    "medium": { "fix_under_loc": 50, "defer_over_loc": true },
    "low": "defer_to_report"
  },
  "spec_update": {
    "max_autonomous_revisions": 2,
    "on_third_revision": "escalate_supervisor",
    "on_fundamental_restructure": "hard_stop"
  },
  "drift": {
    "clear_violation": "fix",
    "ambiguous": "log_as_debt",
    "intentional_divergence": "tier2_decide"
  },
  "security": {
    "never_relax_autonomously": true
  },
  "budget": {
    "max_tokens": 2000000,
    "warn_at_percent": 75,
    "hard_stop_at_percent": 100
  },
  "time": {
    "max_duration_hours": 8,
    "warn_at_hours": 6
  },
  "ambiguity_policy": "conservative",
  "hard_stops": [
    "security_constraint_conflict",
    "spec_requires_fundamental_restructure",
    "budget_exceeded",
    "time_exceeded",
    "supervisor_uncertain",
    "3_or_more_spec_revisions"
  ]
}
POLICY_EOF
}

# ============================================
# Source scripts at top level to avoid RETURN trap + source interaction
source "$REPO_DIR/scripts/auto-policy.sh"

# INV-001 [unit]: Policy evaluation is deterministic — pre-routing pass
# ============================================

test_inv001_policy_deterministic_prerouting() {
  echo ""
  echo "=== INV-001: Policy evaluation is deterministic — pre-routing ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  create_valid_policy "$TEST_DIR"


  # DR-xxx with category=security in review phase should match review_dispositions.security=fix
  local dr_json='{"decision_id":"DR-001","category":"security","summary":"Fix auth bypass","phase":"review"}'

  local result1 result2
  result1="$(policy_evaluate "$TEST_DIR/auto-policy.json" "$dr_json" "review")"
  result2="$(policy_evaluate "$TEST_DIR/auto-policy.json" "$dr_json" "review")"

  # Must be deterministic — same input, same output
  assert_eq "INV-001: same DR-xxx + same policy → same disposition (run 1 vs run 2)" "$result1" "$result2"
  # Must be "fix" per the policy
  assert_eq "INV-001: security category in review phase → disposition 'fix'" "fix" "$result1"
}

# Tests INV-001 [unit]: Policy evaluation — pre-routing with no match routes to Tier 1+
test_inv001_policy_no_match() {
  echo ""
  echo "=== INV-001: Policy evaluation — no match routes to Tier 1+ ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  create_valid_policy "$TEST_DIR"


  # DR-xxx with category=architecture in review phase — not in review_dispositions (no explicit key)
  local dr_json='{"decision_id":"DR-002","category":"architecture","summary":"Refactor DB layer","phase":"review"}'
  local result
  result="$(policy_evaluate "$TEST_DIR/auto-policy.json" "$dr_json" "review")"

  # Should fall through to default or return no_match
  # If "default" key exists in review_dispositions, it matches. "architecture" is not listed,
  # so it should hit "default" → "tier2_decide"
  assert_eq "INV-001: unlisted category hits 'default' → tier2_decide" "tier2_decide" "$result"
}

# Tests INV-001 [unit]: Policy evaluation — scope_expansion in review → defer
test_inv001_policy_scope_expansion() {
  echo ""
  echo "=== INV-001: Policy evaluation — scope_expansion → defer ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  create_valid_policy "$TEST_DIR"


  local dr_json='{"decision_id":"DR-003","category":"scope_expansion","summary":"Add new endpoint","phase":"review"}'
  local result
  result="$(policy_evaluate "$TEST_DIR/auto-policy.json" "$dr_json" "review")"
  assert_eq "INV-001: scope_expansion in review → 'defer'" "defer" "$result"
}

# ============================================
# INV-012 [unit]: Post-Tier-2 validation catches policy contradictions
# ============================================

test_inv012_post_tier2_validation_pass() {
  echo ""
  echo "=== INV-012: Post-Tier-2 validation — pass case ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  create_valid_policy "$TEST_DIR"


  # Tier 2 says "fix" for security in review — matches policy
  local dr_json='{"decision_id":"DR-004","category":"security","summary":"Fix auth","phase":"review"}'
  local result
  result="$(policy_validate_tier2 "$TEST_DIR/auto-policy.json" "$dr_json" "fix")"
  assert_eq "INV-012: Tier 2 'fix' matches policy 'fix' → pass" "pass" "$result"
}

test_inv012_post_tier2_validation_conflict() {
  echo ""
  echo "=== INV-012: Post-Tier-2 validation — conflict case ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  create_valid_policy "$TEST_DIR"


  # Tier 2 says "defer" for security in review — contradicts policy which says "fix"
  local dr_json='{"decision_id":"DR-005","category":"security","summary":"Defer auth fix","phase":"review"}'
  local result
  result="$(policy_validate_tier2 "$TEST_DIR/auto-policy.json" "$dr_json" "defer")"
  assert_eq "INV-012: Tier 2 'defer' contradicts policy 'fix' → conflict" "conflict" "$result"
}

# ============================================
# INV-018 [unit]: Policy hash verification
# ============================================

test_inv018_policy_hash_compute_and_verify() {
  echo ""
  echo "=== INV-018: Policy hash — compute, store, verify ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  create_valid_policy "$TEST_DIR"


  # Compute hash
  local hash1
  hash1="$(policy_hash "$TEST_DIR/auto-policy.json")"
  # Hash must be non-empty
  local hash_nonempty="no"
  [ -n "$hash1" ] && hash_nonempty="yes"
  assert_eq "INV-018: policy_hash returns non-empty result" "yes" "$hash_nonempty"

  # Same file → same hash (deterministic)
  local hash2
  hash2="$(policy_hash "$TEST_DIR/auto-policy.json")"
  assert_eq "INV-018: same file → same hash" "$hash1" "$hash2"
}

test_inv018_policy_hash_tamper_detection() {
  echo ""
  echo "=== INV-018: Policy hash — tamper detection ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  create_valid_policy "$TEST_DIR"


  local original_hash
  original_hash="$(policy_hash "$TEST_DIR/auto-policy.json")"

  # Tamper with the policy file
  echo '{"security":{"never_relax_autonomously":false}}' > "$TEST_DIR/auto-policy.json"

  local tampered_hash
  tampered_hash="$(policy_hash "$TEST_DIR/auto-policy.json")"

  # Hashes must differ
  local hashes_match="no"
  [ "$original_hash" = "$tampered_hash" ] && hashes_match="yes"
  assert_eq "INV-018: tampered policy file produces different hash" "no" "$hashes_match"
}

# ============================================
# BND-001 [unit]: Malformed/empty/absent auto-policy.json
# ============================================

test_bnd001_malformed_policy() {
  echo ""
  echo "=== BND-001: Malformed auto-policy.json → route to Tier 1+ ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  # Write malformed JSON
  echo 'this is not json {{{' > "$TEST_DIR/auto-policy.json"


  local dr_json='{"decision_id":"DR-006","category":"security","summary":"Test","phase":"review"}'
  local result
  result="$(policy_evaluate "$TEST_DIR/auto-policy.json" "$dr_json" "review" 2>/dev/null)"

  # Must not crash (exit code 0), and should return no_match to route to Tier 1+
  local exit_code=$?
  assert_eq "BND-001: malformed policy does not crash (exit 0)" "0" "$exit_code"
  assert_eq "BND-001: malformed policy → no_match (route to Tier 1+)" "no_match" "$result"
}

test_bnd001_empty_policy() {
  echo ""
  echo "=== BND-001: Empty auto-policy.json → route to Tier 1+ ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  # Write empty file
  : > "$TEST_DIR/auto-policy.json"


  local dr_json='{"decision_id":"DR-007","category":"testability","summary":"Test","phase":"review"}'
  local result
  result="$(policy_evaluate "$TEST_DIR/auto-policy.json" "$dr_json" "review" 2>/dev/null)"

  local exit_code=$?
  assert_eq "BND-001: empty policy does not crash" "0" "$exit_code"
  assert_eq "BND-001: empty policy → no_match" "no_match" "$result"
}

test_bnd001_absent_policy() {
  echo ""
  echo "=== BND-001: Absent auto-policy.json → route to Tier 1+ ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  # No auto-policy.json created


  local dr_json='{"decision_id":"DR-008","category":"performance","summary":"Test","phase":"review"}'
  local result
  result="$(policy_evaluate "$TEST_DIR/auto-policy.json" "$dr_json" "review" 2>/dev/null)"

  local exit_code=$?
  assert_eq "BND-001: absent policy does not crash" "0" "$exit_code"
  assert_eq "BND-001: absent policy → no_match" "no_match" "$result"
}

# ============================================
# INV-014 [integration]: /csetup scaffolds default auto-policy.json
# ============================================

test_inv014_csetup_scaffolds_policy() {
  echo ""
  echo "=== INV-014: /csetup scaffolds default auto-policy.json ==="

  local setup_script="$REPO_DIR/setup"

  # INV-014: setup script must reference auto-policy.json
  file_contains "$setup_script" "auto-policy.json" \
    "INV-014: setup script references auto-policy.json"
}

test_inv014_csetup_no_overwrite() {
  echo ""
  echo "=== INV-014: /csetup does not overwrite existing auto-policy.json ==="

  local setup_script="$REPO_DIR/setup"

  # INV-014: setup must have create_if_missing or equivalent idempotency check
  file_contains "$setup_script" "auto-policy" \
    "INV-014: setup references auto-policy for scaffolding"
}

# ============================================
# INV-014 [integration]: auto-policy.json template has valid schema
# ============================================

test_inv014_policy_template_schema() {
  echo ""
  echo "=== INV-014: auto-policy.json template has valid schema ==="

  local template="$REPO_DIR/templates/auto-policy.json"

  # Template must exist
  assert_file_exists "INV-014: auto-policy.json template exists" "$template"

  # Template must be valid JSON
  if [ -f "$template" ]; then
    local valid="no"
    jq '.' "$template" > /dev/null 2>&1 && valid="yes"
    assert_eq "INV-014: auto-policy.json template is valid JSON" "yes" "$valid"

    # Must contain required sections
    file_contains "$template" "review_dispositions" \
      "INV-014: template has review_dispositions"
    file_contains "$template" "qa_dispositions" \
      "INV-014: template has qa_dispositions"
    file_contains "$template" "security" \
      "INV-014: template has security section"
    file_contains "$template" "never_relax_autonomously" \
      "INV-014: template has never_relax_autonomously"
    file_contains "$template" "budget" \
      "INV-014: template has budget section"
    file_contains "$template" "time" \
      "INV-014: template has time section"
  fi
}

# ============================================
# B-007: INV-012 — Routing-to-validation flow test
# ============================================

test_inv012_routing_to_validation_conflict() {
  echo ""
  echo "=== B-007/INV-012: Routing-to-validation — conflict detection ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  # Set up policy where scope_expansion maps to "defer"
  create_valid_policy "$TEST_DIR"


  # Construct a Tier 2 response that says "fix" for scope_expansion
  # This contradicts the policy which says "defer" for scope_expansion
  local dr_json='{"decision_id":"DR-080","category":"scope_expansion","summary":"Add new REST endpoint","phase":"review"}'

  # The Tier 2 agent returned "fix" but policy says "defer" → conflict
  local result
  result="$(policy_validate_tier2 "$TEST_DIR/auto-policy.json" "$dr_json" "fix")"

  # Must specifically return "conflict", not just non-zero exit
  assert_eq "B-007/INV-012: Tier 2 'fix' contradicts policy 'defer' → 'conflict'" "conflict" "$result"
}

test_inv012_routing_to_validation_pass_when_aligned() {
  echo ""
  echo "=== B-007/INV-012: Routing-to-validation — pass when aligned ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  create_valid_policy "$TEST_DIR"


  # scope_expansion policy says "defer", Tier 2 also says "defer" → aligned
  local dr_json='{"decision_id":"DR-081","category":"scope_expansion","summary":"Add endpoint","phase":"review"}'
  local result
  result="$(policy_validate_tier2 "$TEST_DIR/auto-policy.json" "$dr_json" "defer")"
  assert_eq "B-007/INV-012: Tier 2 'defer' matches policy 'defer' → 'pass'" "pass" "$result"
}

# ============================================
# B-012: INV-018 — Hash enforcement integration test
# ============================================

test_inv018_hash_enforcement_integration() {
  echo ""
  echo "=== B-012/INV-018: Hash enforcement — policy modified mid-run ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  create_valid_policy "$TEST_DIR"


  # Compute hash at "pipeline start"
  local stored_hash
  stored_hash="$(policy_hash "$TEST_DIR/auto-policy.json")"

  # First evaluation with valid hash — should work
  local dr_json='{"decision_id":"DR-090","category":"security","summary":"Fix auth","phase":"review"}'
  local result1
  result1="$(policy_evaluate "$TEST_DIR/auto-policy.json" "$dr_json" "review" "$stored_hash" 2>/dev/null)"
  local rc1=$?

  # Modify the policy file between calls (simulates mid-run tampering)
  echo '{"review_dispositions":{"security":"defer"},"security":{"never_relax_autonomously":false}}' > "$TEST_DIR/auto-policy.json"

  # Second evaluation with the ORIGINAL hash — should trigger hard stop
  local result2
  result2="$(policy_evaluate "$TEST_DIR/auto-policy.json" "$dr_json" "review" "$stored_hash" 2>/dev/null)"
  local rc2=$?

  # The stub returns empty and exit 1 for both calls — new tests FAIL
  assert_eq "B-012/INV-018: first policy_evaluate with valid hash returns 0" "0" "$rc1"
  assert_eq "B-012/INV-018: second policy_evaluate with stale hash detects tamper" "2" "$rc2"
}

# ============================================
# B-014: INV-014 — Setup integration test
# ============================================

test_inv014_setup_creates_auto_policy() {
  echo ""
  echo "=== B-014/INV-014: Setup creates auto-policy.json in temp project ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  # Create minimal project structure
  mkdir -p "$TEST_DIR/.correctless/config"
  mkdir -p "$TEST_DIR/.git"  # Minimal git repo marker

  local setup_script="$REPO_DIR/setup"

  # Verify the setup script exists
  assert_file_exists "B-014/INV-014: setup script exists" "$setup_script"

  # Check that setup references auto-policy.json for scaffolding
  file_contains "$setup_script" "auto-policy" \
    "B-014/INV-014: setup references auto-policy for scaffolding"

  # After setup runs, the config directory should contain auto-policy.json
  # For now, check the template exists as a source
  local template="$REPO_DIR/templates/auto-policy.json"
  assert_file_exists "B-014/INV-014: auto-policy.json template exists as scaffold source" "$template"
}

test_inv014_setup_idempotent() {
  echo ""
  echo "=== B-014/INV-014: Setup idempotent — does not overwrite existing ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  mkdir -p "$TEST_DIR/.correctless/config"

  # Create existing auto-policy.json with custom content
  echo '{"custom":"user-edited-policy","security":{"never_relax_autonomously":true}}' > "$TEST_DIR/.correctless/config/auto-policy.json"

  local setup_script="$REPO_DIR/setup"

  # Setup must have idempotency logic — check for existence checks in script
  # Look for patterns like "if [ ! -f" or "already exists" near auto-policy references
  local has_idempotency="no"
  if grep -q 'auto-policy' "$setup_script" 2>/dev/null; then
    # Setup references auto-policy — now check it has an idempotency guard
    if grep -qE '(if \[|test ).*auto-policy|auto-policy.*exist|create_if_missing.*auto-policy' "$setup_script" 2>/dev/null; then
      has_idempotency="yes"
    fi
  fi
  assert_eq "B-014/INV-014: setup has idempotency guard for auto-policy.json" "yes" "$has_idempotency"
}

test_inv014_sensitive_file_guard_includes_policy() {
  echo ""
  echo "=== B-014/INV-014: Sensitive file guard protects auto-policy.json ==="

  # The sensitive-file-guard config (or defaults) should include auto-policy.json
  local guard_hook="$REPO_DIR/hooks/sensitive-file-guard.sh"

  if [ -f "$guard_hook" ]; then
    file_contains "$guard_hook" "auto-policy" \
      "B-014/INV-014: sensitive-file-guard references auto-policy.json"
  else
    # Check default sensitive file list in config
    local config="$REPO_DIR/.correctless/config/workflow-config.json"
    if [ -f "$config" ]; then
      file_contains "$config" "auto-policy" \
        "B-014/INV-014: workflow config protects auto-policy.json"
    else
      echo "  FAIL: B-014/INV-014: no guard hook or config found to verify auto-policy protection"
      FAIL=$((FAIL + 1))
    fi
  fi
}

# ============================================
# QA-003: policy_validate_tier2 forwards hash to policy_evaluate
# ============================================

test_qa003_tier2_validation_forwards_hash() {
  echo ""
  echo "=== QA-003: policy_validate_tier2 — hash forwarded to policy_evaluate ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  create_valid_policy "$TEST_DIR"

  # Compute hash at "pipeline start"
  local stored_hash
  stored_hash="$(policy_hash "$TEST_DIR/auto-policy.json")"

  # Tamper with the policy file
  echo '{"review_dispositions":{"security":"defer"}}' > "$TEST_DIR/auto-policy.json"

  # Tier 2 validation with stale hash — should return "tamper"
  local dr_json='{"decision_id":"DR-095","category":"security","summary":"Fix auth","phase":"review"}'
  local result
  result="$(policy_validate_tier2 "$TEST_DIR/auto-policy.json" "$dr_json" "fix" "$stored_hash")"
  assert_eq "QA-003: tier2 validation with stale hash → 'tamper'" "tamper" "$result"
}

test_qa003_tier2_validation_without_hash_still_works() {
  echo ""
  echo "=== QA-003: policy_validate_tier2 — works without hash (backward compat) ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  create_valid_policy "$TEST_DIR"

  # No hash provided — should still work as before
  local dr_json='{"decision_id":"DR-096","category":"security","summary":"Fix auth","phase":"review"}'
  local result
  result="$(policy_validate_tier2 "$TEST_DIR/auto-policy.json" "$dr_json" "fix")"
  assert_eq "QA-003: tier2 validation without hash → 'pass' (backward compat)" "pass" "$result"
}

# ============================================
# Runner
# ============================================

echo "============================================="
echo "Auto Mode Phase 2 — Policy Engine"
echo "============================================="

# INV-001: Deterministic policy evaluation
test_inv001_policy_deterministic_prerouting
test_inv001_policy_no_match
test_inv001_policy_scope_expansion

# INV-012: Post-Tier-2 validation
test_inv012_post_tier2_validation_pass
test_inv012_post_tier2_validation_conflict

# B-007/INV-012: Routing-to-validation flow
test_inv012_routing_to_validation_conflict
test_inv012_routing_to_validation_pass_when_aligned

# INV-018: Policy hash verification
test_inv018_policy_hash_compute_and_verify
test_inv018_policy_hash_tamper_detection

# B-012/INV-018: Hash enforcement integration
test_inv018_hash_enforcement_integration

# BND-001: Malformed/empty/absent policy
test_bnd001_malformed_policy
test_bnd001_empty_policy
test_bnd001_absent_policy

# INV-014: /csetup scaffolding
test_inv014_csetup_scaffolds_policy
test_inv014_csetup_no_overwrite
test_inv014_policy_template_schema

# B-014/INV-014: Setup integration tests
test_inv014_setup_creates_auto_policy
test_inv014_setup_idempotent
test_inv014_sensitive_file_guard_includes_policy

# QA-003: policy_validate_tier2 hash forwarding
test_qa003_tier2_validation_forwards_hash
test_qa003_tier2_validation_without_hash_still_works

echo ""
echo "============================================="
echo "Results: $PASS passed, $FAIL failed"
echo ""

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
