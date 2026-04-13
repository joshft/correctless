#!/usr/bin/env bash
# Correctless — Auto Mode Phase 3: Supervisor Mandate test suite
# Track 2: Tests INV-028, INV-029, INV-030, INV-031, INV-034, PRH-002
# RED phase: these tests MUST FAIL — implementation does not exist yet.
# Run from repo root: bash tests/test-auto-mandate.sh

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
source "$REPO_DIR/scripts/supervisor-mandate.sh"

# ============================================
# INV-028 [integration]: Architectural decisions with citation
# ============================================

test_inv028_citation_valid() {
  echo ""
  echo "=== INV-028: Valid spec citation passes validation ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  # Create a spec fixture with known section headings
  cat > "$TEST_DIR/spec.md" << 'SPEC_EOF'
# Spec: Test Feature

## Scope

In scope: review triage, override scrutiny

## Invariants

### INV-021: Autonomous review with supervisor triage
- Statement: Review findings triaged in batch

### INV-022: Review decisions artifact
- Statement: Decisions logged with hash verification
SPEC_EOF

  # Citation to an existing section
  validate_spec_citation "$TEST_DIR/spec.md" "INV-021"
  local rc=$?
  assert_eq "INV-028: citation 'INV-021' found in spec" "0" "$rc"

  # Citation to a heading
  validate_spec_citation "$TEST_DIR/spec.md" "## Scope"
  rc=$?
  assert_eq "INV-028: citation '## Scope' found in spec" "0" "$rc"
}

test_inv028_citation_missing() {
  echo ""
  echo "=== INV-028: Missing spec citation fails validation ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  cat > "$TEST_DIR/spec.md" << 'SPEC_EOF'
# Spec: Test Feature

## Scope

In scope: review triage
SPEC_EOF

  # Citation to non-existent invariant
  validate_spec_citation "$TEST_DIR/spec.md" "INV-999"
  local rc=$?
  assert_eq "INV-028: citation 'INV-999' not found in spec" "1" "$rc"

  # Citation to non-existent heading
  validate_spec_citation "$TEST_DIR/spec.md" "## Nonexistent Section"
  rc=$?
  assert_eq "INV-028: citation '## Nonexistent Section' not found" "1" "$rc"
}

# ============================================
# INV-029 [unit]: Supervisor context enrichment
# ============================================

test_inv029_mandate_context_schema() {
  echo ""
  echo "=== INV-029: Mandate context has required fields ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  # Create fixture files
  cat > "$TEST_DIR/preferences.md" << 'PREF_EOF'
# Preferences
- supervisor_mandate: conservative
PREF_EOF

  cat > "$TEST_DIR/decision-record.md" << 'DR_EOF'
## Decision Record

### DD-001
- **Tier**: 0
- **Category**: security
- **Disposition**: fix

### DD-002
- **Tier**: 2
- **Category**: performance
- **Disposition**: tier2_decide
DR_EOF

  cat > "$TEST_DIR/spec.md" << 'SPEC_EOF'
# Spec

## Scope
In scope: review triage, override scrutiny

## Invariants
### INV-021: Review triage
SPEC_EOF

  echo '{"phase":"tdd-impl","supervisor_activation_count":3}' > "$TEST_DIR/state.json"

  local result
  result="$(build_mandate_context "$TEST_DIR/preferences.md" "$TEST_DIR/decision-record.md" "$TEST_DIR/spec.md" "$TEST_DIR/state.json" 2>/dev/null)"
  local rc=$?

  assert_eq "INV-029: build_mandate_context exits 0" "0" "$rc"

  # Result must be valid JSON
  local is_json="no"
  echo "$result" | jq '.' >/dev/null 2>&1 && is_json="yes"
  assert_eq "INV-029: mandate context is valid JSON" "yes" "$is_json"

  # Must contain preferences field
  local has_preferences="no"
  echo "$result" | jq -e '.preferences' >/dev/null 2>&1 && has_preferences="yes"
  assert_eq "INV-029: mandate context has preferences" "yes" "$has_preferences"

  # Must contain decision_patterns field
  local has_patterns="no"
  echo "$result" | jq -e '.decision_patterns' >/dev/null 2>&1 && has_patterns="yes"
  assert_eq "INV-029: mandate context has decision_patterns" "yes" "$has_patterns"

  # Must contain spec_scope field
  local has_scope="no"
  echo "$result" | jq -e '.spec_scope' >/dev/null 2>&1 && has_scope="yes"
  assert_eq "INV-029: mandate context has spec_scope" "yes" "$has_scope"
}

test_inv029_decision_patterns_schema() {
  echo ""
  echo "=== INV-029: Decision patterns matches required schema ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  cat > "$TEST_DIR/preferences.md" << 'PREF_EOF'
# Preferences
- supervisor_mandate: conservative
PREF_EOF

  cat > "$TEST_DIR/decision-record.md" << 'DR_EOF'
## Decision Record

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
DR_EOF

  echo '## Scope' > "$TEST_DIR/spec.md"
  echo '{"phase":"tdd-impl"}' > "$TEST_DIR/state.json"

  local result
  result="$(build_mandate_context "$TEST_DIR/preferences.md" "$TEST_DIR/decision-record.md" "$TEST_DIR/spec.md" "$TEST_DIR/state.json" 2>/dev/null)"

  # decision_patterns must have categories, total_decisions, tier_distribution
  local has_categories="no"
  echo "$result" | jq -e '.decision_patterns.categories' >/dev/null 2>&1 && has_categories="yes"
  assert_eq "INV-029: decision_patterns has categories" "yes" "$has_categories"

  local has_total="no"
  echo "$result" | jq -e '.decision_patterns.total_decisions' >/dev/null 2>&1 && has_total="yes"
  assert_eq "INV-029: decision_patterns has total_decisions" "yes" "$has_total"

  local has_tier_dist="no"
  echo "$result" | jq -e '.decision_patterns.tier_distribution' >/dev/null 2>&1 && has_tier_dist="yes"
  assert_eq "INV-029: decision_patterns has tier_distribution" "yes" "$has_tier_dist"

  # B-03: Value assertions — verify actual counts match fixture data
  local total
  total="$(echo "$result" | jq -r '.decision_patterns.total_decisions' 2>/dev/null)" || total="0"
  assert_eq "INV-029: total_decisions is 3" "3" "$total"

  local tier0
  tier0="$(echo "$result" | jq -r '.decision_patterns.tier_distribution.tier0 // 0' 2>/dev/null)" || tier0="0"
  assert_eq "INV-029: tier0 count is 2" "2" "$tier0"

  local tier2
  tier2="$(echo "$result" | jq -r '.decision_patterns.tier_distribution.tier2 // 0' 2>/dev/null)" || tier2="0"
  assert_eq "INV-029: tier2 count is 1" "1" "$tier2"
}

# ============================================
# INV-030 [unit]: Hard limits
# ============================================

test_inv030_unspecced_deps_hard_stop() {
  echo ""
  echo "=== INV-030: Unspecced dependency triggers hard_stop ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  echo '## Scope' > "$TEST_DIR/spec.md"

  # DR-xxx for a new dependency not in spec
  local dr_json='{"decision_id":"DR-100","category":"dependency","summary":"Add lodash dependency","options":[]}'

  local result
  result="$(check_hard_limits "$dr_json" "$TEST_DIR/spec.md" 2>/dev/null)"

  assert_eq "INV-030: unspecced dependency triggers hard_stop" "hard_stop" "$result"
}

test_inv030_security_relaxation_hard_stop() {
  echo ""
  echo "=== INV-030: Security constraint relaxation triggers hard_stop ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  echo '## Scope' > "$TEST_DIR/spec.md"

  local dr_json='{"decision_id":"DR-101","category":"security","summary":"Remove auth check for performance"}'

  local result
  result="$(check_hard_limits "$dr_json" "$TEST_DIR/spec.md" 2>/dev/null)"

  assert_eq "INV-030: security relaxation triggers hard_stop" "hard_stop" "$result"
}

test_inv030_budget_exceeded_hard_stop() {
  echo ""
  echo "=== INV-030: Budget exceeded triggers hard_stop ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  echo '## Scope' > "$TEST_DIR/spec.md"

  local dr_json='{"decision_id":"DR-102","category":"budget","summary":"Budget limit exceeded"}'

  local result
  result="$(check_hard_limits "$dr_json" "$TEST_DIR/spec.md" 2>/dev/null)"

  assert_eq "INV-030: budget exceeded triggers hard_stop" "hard_stop" "$result"
}

test_inv030_intent_tampered_hard_stop() {
  echo ""
  echo "=== INV-030: Intent summary tampered triggers hard_stop ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  echo '## Scope' > "$TEST_DIR/spec.md"

  local dr_json='{"decision_id":"DR-103","category":"intent","summary":"Intent summary tampered"}'

  local result
  result="$(check_hard_limits "$dr_json" "$TEST_DIR/spec.md" 2>/dev/null)"

  assert_eq "INV-030: intent tampered triggers hard_stop" "hard_stop" "$result"
}

test_inv030_policy_tampered_hard_stop() {
  echo ""
  echo "=== INV-030: Policy file tampered triggers hard_stop ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  echo '## Scope' > "$TEST_DIR/spec.md"

  local dr_json='{"decision_id":"DR-104","category":"policy","summary":"Policy file tampered"}'

  local result
  result="$(check_hard_limits "$dr_json" "$TEST_DIR/spec.md" 2>/dev/null)"

  assert_eq "INV-030: policy tampered triggers hard_stop" "hard_stop" "$result"
}

test_inv030_claude_md_modification_hard_stop() {
  echo ""
  echo "=== INV-030: CLAUDE.md modification triggers hard_stop ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  echo '## Scope' > "$TEST_DIR/spec.md"

  local dr_json='{"decision_id":"DR-105","category":"configuration","summary":"Modify CLAUDE.md"}'

  local result
  result="$(check_hard_limits "$dr_json" "$TEST_DIR/spec.md" 2>/dev/null)"

  assert_eq "INV-030: CLAUDE.md modification triggers hard_stop" "hard_stop" "$result"
}

test_inv030_spec_restructure_hard_stop() {
  echo ""
  echo "=== INV-030: Spec fundamental restructure triggers hard_stop ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  echo '## Scope' > "$TEST_DIR/spec.md"

  local dr_json='{"decision_id":"DR-106","category":"spec-restructure","summary":"Fundamentally restructure the spec"}'

  local result
  result="$(check_hard_limits "$dr_json" "$TEST_DIR/spec.md" 2>/dev/null)"

  assert_eq "INV-030: spec restructure triggers hard_stop" "hard_stop" "$result"
}

test_inv030_normal_decision_routes() {
  echo ""
  echo "=== INV-030: Normal decision routes to supervisor ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  echo '## Scope' > "$TEST_DIR/spec.md"

  # Normal architecture decision — should route, not hard_stop
  local dr_json='{"decision_id":"DR-107","category":"architecture","summary":"Add new utility module"}'

  local result
  result="$(check_hard_limits "$dr_json" "$TEST_DIR/spec.md" 2>/dev/null)"

  assert_eq "INV-030: normal architecture decision routes (not hard_stop)" "route" "$result"
}

# ============================================
# INV-031 [integration]: Dependency guard
# ============================================

test_inv031_specced_dependency() {
  echo ""
  echo "=== INV-031: Specced dependency returns 'specced' ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  cat > "$TEST_DIR/spec.md" << 'SPEC_EOF'
# Spec

## Scope

In scope: jq dependency, shellcheck integration

## Invariants

### INV-040: Base-commit cross-check
- Uses jq for JSON processing
SPEC_EOF

  local result
  result="$(check_dependency_specced "jq" "$TEST_DIR/spec.md" 2>/dev/null)"

  assert_eq "INV-031: 'jq' mentioned in spec returns 'specced'" "specced" "$result"
}

test_inv031_unspecced_dependency() {
  echo ""
  echo "=== INV-031: Unspecced dependency returns 'unspecced' ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  cat > "$TEST_DIR/spec.md" << 'SPEC_EOF'
# Spec

## Scope

In scope: review triage

## Invariants

### INV-021: Review triage
SPEC_EOF

  local result
  result="$(check_dependency_specced "lodash" "$TEST_DIR/spec.md" 2>/dev/null)"

  assert_eq "INV-031: 'lodash' not in spec returns 'unspecced'" "unspecced" "$result"
}

test_inv031_regex_metachar_dep() {
  echo ""
  echo "=== INV-031: Dep name with regex metacharacters matched literally ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  cat > "$TEST_DIR/spec.md" << 'SPEC_EOF'
# Spec

## Scope

In scope: c++ compiler integration, node.js runtime

## Invariants

### INV-050: Build system
- Uses c++ for native modules
SPEC_EOF

  # "c++" contains regex metacharacters — must match literally via -F
  local result
  result="$(check_dependency_specced "c++" "$TEST_DIR/spec.md" 2>/dev/null)"
  assert_eq "INV-031: 'c++' (regex metachar) found literally in spec" "specced" "$result"

  # "node.js" — the dot is a regex metachar
  result="$(check_dependency_specced "node.js" "$TEST_DIR/spec.md" 2>/dev/null)"
  assert_eq "INV-031: 'node.js' (dot is regex metachar) found literally in spec" "specced" "$result"

  # ".*" should NOT match everything — it should be treated as literal
  result="$(check_dependency_specced ".*" "$TEST_DIR/spec.md" 2>/dev/null)"
  assert_eq "INV-031: '.*' treated literally, not as wildcard" "unspecced" "$result"
}

# ============================================
# INV-034 [unit]: Configurable mandate level
# ============================================

test_inv034_default_conservative() {
  echo ""
  echo "=== INV-034: Default mandate level is conservative ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  # No preferences file
  local result
  result="$(get_mandate_level "$TEST_DIR/nonexistent.md" 2>/dev/null)"

  assert_eq "INV-034: missing preferences defaults to conservative" "conservative" "$result"
}

test_inv034_read_from_preferences() {
  echo ""
  echo "=== INV-034: Mandate level read from preferences ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  cat > "$TEST_DIR/preferences.md" << 'PREF_EOF'
# Preferences
- supervisor_mandate: moderate
PREF_EOF

  local result
  result="$(get_mandate_level "$TEST_DIR/preferences.md" 2>/dev/null)"

  assert_eq "INV-034: preferences 'moderate' read correctly" "moderate" "$result"
}

test_inv034_aggressive_level() {
  echo ""
  echo "=== INV-034: Aggressive mandate level read correctly ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  cat > "$TEST_DIR/preferences.md" << 'PREF_EOF'
# Preferences
- supervisor_mandate: aggressive
PREF_EOF

  local result
  result="$(get_mandate_level "$TEST_DIR/preferences.md" 2>/dev/null)"

  assert_eq "INV-034: preferences 'aggressive' read correctly" "aggressive" "$result"
}

test_inv034_conservative_citation_enforcement() {
  echo ""
  echo "=== INV-034: Conservative level enforces citation ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  cat > "$TEST_DIR/spec.md" << 'SPEC_EOF'
# Spec

## Scope
In scope: review triage

## Invariants
### INV-021: Review triage
SPEC_EOF

  # Supervisor response approving an architectural decision without citation
  local supervisor_response='{"decision":"approve","reasoning":"Looks fine to me","flags":[]}'

  validate_mandate_decision "$supervisor_response" "conservative" "$TEST_DIR/spec.md"
  local rc=$?
  assert_eq "INV-034: conservative approve without citation → override to hard_stop (rc=1)" "1" "$rc"
}

test_inv034_conservative_with_valid_citation() {
  echo ""
  echo "=== INV-034: Conservative level with valid citation passes ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  cat > "$TEST_DIR/spec.md" << 'SPEC_EOF'
# Spec

## Scope
In scope: review triage

## Invariants
### INV-021: Review triage
SPEC_EOF

  # Supervisor response with valid citation
  local supervisor_response='{"decision":"approve","reasoning":"Per INV-021, this is within scope of review triage","flags":[]}'

  validate_mandate_decision "$supervisor_response" "conservative" "$TEST_DIR/spec.md"
  local rc=$?
  assert_eq "INV-034: conservative approve with valid citation passes (rc=0)" "0" "$rc"
}

# ============================================
# PRH-002 [unit]: Supervisor must not approve unspecced deps
# ============================================

test_prh002_unspecced_dep_hard_stop() {
  echo ""
  echo "=== PRH-002: Unspecced dependency hard-stops without reaching supervisor ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  cat > "$TEST_DIR/spec.md" << 'SPEC_EOF'
# Spec

## Scope
In scope: bash scripts only
SPEC_EOF

  # check_hard_limits must catch unspecced deps before supervisor
  local dr_json='{"decision_id":"DR-200","category":"dependency","summary":"Add python-requests dependency"}'

  local result
  result="$(check_hard_limits "$dr_json" "$TEST_DIR/spec.md" 2>/dev/null)"
  assert_eq "PRH-002: unspecced dep triggers hard_stop (bypasses supervisor)" "hard_stop" "$result"
}

# ============================================
# INV-030 [unit]: Content-based detection — security improvement vs relaxation
# ============================================

test_inv030_security_improvement_routes() {
  echo ""
  echo "=== INV-030: Security improvement routes (not hard_stop) ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  echo '## Scope' > "$TEST_DIR/spec.md"

  # Security improvement (adding validation) — NOT a relaxation
  local dr_json='{"decision_id":"DR-110","category":"security","summary":"Add additional input validation to prevent injection"}'

  local result
  result="$(check_hard_limits "$dr_json" "$TEST_DIR/spec.md" 2>/dev/null)"

  assert_eq "INV-030: security improvement routes (not hard_stop)" "route" "$result"
}

test_inv030_config_without_claude_md_routes() {
  echo ""
  echo "=== INV-030: Config change without CLAUDE.md routes normally ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  echo '## Scope' > "$TEST_DIR/spec.md"

  # Configuration change that does NOT mention CLAUDE.md
  local dr_json='{"decision_id":"DR-111","category":"configuration","summary":"Update database connection pool settings"}'

  local result
  result="$(check_hard_limits "$dr_json" "$TEST_DIR/spec.md" 2>/dev/null)"

  assert_eq "INV-030: config without CLAUDE.md routes normally" "route" "$result"
}

# ============================================
# INV-034 [unit]: Moderate/aggressive levels — no citation enforcement
# ============================================

test_inv034_moderate_no_citation_ok() {
  echo ""
  echo "=== INV-034: Moderate level — no citation still passes ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  cat > "$TEST_DIR/spec.md" << 'SPEC_EOF'
# Spec

## Scope
In scope: review triage

## Invariants
### INV-021: Review triage
SPEC_EOF

  # Supervisor response with NO citation — at moderate level, citation is not enforced
  local supervisor_response='{"decision":"approve","reasoning":"This looks reasonable","flags":[]}'

  validate_mandate_decision "$supervisor_response" "moderate" "$TEST_DIR/spec.md"
  local rc=$?
  assert_eq "INV-034: moderate approve without citation passes (rc=0)" "0" "$rc"
}

test_inv034_aggressive_no_citation_ok() {
  echo ""
  echo "=== INV-034: Aggressive level — no citation still passes ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  cat > "$TEST_DIR/spec.md" << 'SPEC_EOF'
# Spec

## Scope
In scope: review triage

## Invariants
### INV-021: Review triage
SPEC_EOF

  # Supervisor response with NO citation — at aggressive level, citation is not enforced
  local supervisor_response='{"decision":"approve","reasoning":"Approved without specific citation","flags":[]}'

  validate_mandate_decision "$supervisor_response" "aggressive" "$TEST_DIR/spec.md"
  local rc=$?
  assert_eq "INV-034: aggressive approve without citation passes (rc=0)" "0" "$rc"
}

# ============================================
# Runner
# ============================================

echo "============================================="
echo "Auto Mode Phase 3 — Supervisor Mandate"
echo "============================================="

# INV-028: Citation validation
test_inv028_citation_valid
test_inv028_citation_missing

# INV-029: Context enrichment
test_inv029_mandate_context_schema
test_inv029_decision_patterns_schema

# INV-030: Hard limits
test_inv030_unspecced_deps_hard_stop
test_inv030_security_relaxation_hard_stop
test_inv030_budget_exceeded_hard_stop
test_inv030_intent_tampered_hard_stop
test_inv030_policy_tampered_hard_stop
test_inv030_claude_md_modification_hard_stop
test_inv030_spec_restructure_hard_stop
test_inv030_normal_decision_routes
test_inv030_security_improvement_routes
test_inv030_config_without_claude_md_routes

# INV-031: Dependency guard
test_inv031_specced_dependency
test_inv031_unspecced_dependency
test_inv031_regex_metachar_dep

# INV-034: Configurable mandate level
test_inv034_default_conservative
test_inv034_read_from_preferences
test_inv034_aggressive_level
test_inv034_conservative_citation_enforcement
test_inv034_conservative_with_valid_citation
test_inv034_moderate_no_citation_ok
test_inv034_aggressive_no_citation_ok

# PRH-002: Unspecced dep prohibition
test_prh002_unspecced_dep_hard_stop

echo ""
echo "============================================="
echo "Results: $PASS passed, $FAIL failed"
echo ""

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
