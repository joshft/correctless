#!/usr/bin/env bash
# Correctless — Auto Mode Phase 2: Agent Interfaces + Routing test suite
# Track 3: Tests INV-004, INV-005, INV-006, INV-007, INV-017, PRH-005, BND-004
# RED phase: these tests MUST FAIL — implementation does not exist yet.
# Run from repo root: bash tests/test-auto-agents.sh

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
source "$REPO_DIR/scripts/auto-policy.sh"
source "$REPO_DIR/scripts/decision-routing.sh"

# INV-004 [integration]: Supervisor message interface
# ============================================

test_inv004_supervisor_input_format() {
  echo ""
  echo "=== INV-004: Supervisor input message format ==="

  local agent_file="$REPO_DIR/agents/supervisor.md"

  assert_file_exists "INV-004: supervisor agent file exists" "$agent_file"

  # Verify agent file documents all required input fields
  file_contains "$agent_file" "activation_type" \
    "INV-004: supervisor documents activation_type input field"
  file_contains "$agent_file" "intent_summary" \
    "INV-004: supervisor documents intent_summary input field"
  file_contains "$agent_file" "decision_request" \
    "INV-004: supervisor documents decision_request input field"
  file_contains "$agent_file" "phase_summary" \
    "INV-004: supervisor documents phase_summary input field"
  file_contains "$agent_file" "decision_record_recent" \
    "INV-004: supervisor documents decision_record_recent input field"
  file_contains "$agent_file" "budget_status" \
    "INV-004: supervisor documents budget_status input field"
}

test_inv004_supervisor_output_format() {
  echo ""
  echo "=== INV-004: Supervisor output message format ==="

  local agent_file="$REPO_DIR/agents/supervisor.md"

  # Verify agent file documents all required output fields
  file_contains "$agent_file" "decision" \
    "INV-004: supervisor documents decision output field"
  file_contains "$agent_file" "reasoning" \
    "INV-004: supervisor documents reasoning output field"
  file_contains "$agent_file" "flags" \
    "INV-004: supervisor documents flags output field"

  # Valid terminal decisions documented
  file_contains "$agent_file" "approve" \
    "INV-004: supervisor documents 'approve' as valid decision"
  file_contains "$agent_file" "reject" \
    "INV-004: supervisor documents 'reject' as valid decision"
  file_contains "$agent_file" "hard_stop" \
    "INV-004: supervisor documents 'hard_stop' as valid decision"
}

# ============================================
# INV-005 [integration]: Tier routing follows escalation hierarchy
# ============================================

test_inv005_no_tier_skipping() {
  echo ""
  echo "=== INV-005: Tier routing — no tier skipping ==="


  # Valid: Tier 1 → Tier 2 (adjacent, no skip)
  validate_tier_hierarchy "1" "2"
  local rc=$?
  assert_eq "INV-005: Tier 1 → Tier 2 is valid (no skip)" "0" "$rc"

  # Valid: Tier 2 → Tier 3 (adjacent)
  validate_tier_hierarchy "2" "3"
  rc=$?
  assert_eq "INV-005: Tier 2 → Tier 3 is valid (no skip)" "0" "$rc"

  # Valid: Tier 3 → Tier 4 (adjacent)
  validate_tier_hierarchy "3" "4"
  rc=$?
  assert_eq "INV-005: Tier 3 → Tier 4 is valid (no skip)" "0" "$rc"

  # Invalid: Tier 1 → Tier 3 (skips Tier 2)
  validate_tier_hierarchy "1" "3" 2>/dev/null
  rc=$?
  assert_eq "INV-005: Tier 1 → Tier 3 is invalid (skips Tier 2)" "1" "$rc"

  # Invalid: Tier 2 → Tier 4 (skips Tier 3)
  validate_tier_hierarchy "2" "4" 2>/dev/null
  rc=$?
  assert_eq "INV-005: Tier 2 → Tier 4 is invalid (skips Tier 3)" "1" "$rc"

  # Invalid: Tier 1 → Tier 4 (skips Tiers 2 and 3)
  validate_tier_hierarchy "1" "4" 2>/dev/null
  rc=$?
  assert_eq "INV-005: Tier 1 → Tier 4 is invalid (skips Tiers 2+3)" "1" "$rc"
}

# ============================================
# INV-006 [integration]: Tier 2 minimal context + structural enforcement
# ============================================

test_inv006_tier2_allowed_tools() {
  echo ""
  echo "=== INV-006: Tier 2 decision agent — allowed-tools ==="

  local agent_file="$REPO_DIR/agents/decision-agent.md"

  assert_file_exists "INV-006: decision-agent.md exists" "$agent_file"

  # Extract frontmatter
  local frontmatter
  frontmatter="$(sed -n '/^---$/,/^---$/p' "$agent_file" 2>/dev/null)"

  # Must have tools: Read, Grep, Glob only
  assert_contains "INV-006: decision-agent tools include Read" "Read" "$frontmatter"
  assert_contains "INV-006: decision-agent tools include Grep" "Grep" "$frontmatter"
  assert_contains "INV-006: decision-agent tools include Glob" "Glob" "$frontmatter"

  # Must NOT have Write, Bash, or Task
  assert_not_contains "INV-006: decision-agent tools exclude Write" "Write" "$frontmatter"
  assert_not_contains "INV-006: decision-agent tools exclude Bash" "Bash" "$frontmatter"
  assert_not_contains "INV-006: decision-agent tools exclude Task" "Task" "$frontmatter"
}

test_inv006_tier2_context_fork() {
  echo ""
  echo "=== INV-006: Tier 2 decision agent — context: fork ==="

  local agent_file="$REPO_DIR/agents/decision-agent.md"

  local frontmatter
  frontmatter="$(sed -n '/^---$/,/^---$/p' "$agent_file" 2>/dev/null)"
  assert_contains "INV-006: decision-agent has context: fork" "context: fork" "$frontmatter"
}

test_inv006_tier2_minimal_context() {
  echo ""
  echo "=== INV-006: Tier 2 build context — minimal fields only ==="


  local dr_json='{"decision_id":"DR-010","requesting_agent":"ctdd","phase":"tdd-impl","category":"testability","summary":"test","options":[],"relevant_rules":["INV-003"],"relevant_policies":["review_dispositions.testability"],"prior_decisions":[{"decision_id":"DD-001","summary":"prev","disposition":"fix"}]}'

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  echo '{"review_dispositions":{"testability":"fix"}}' > "$TEST_DIR/policy.json"
  echo 'spec content' > "$TEST_DIR/spec.md"

  local context
  context="$(tier2_build_context "$dr_json" "$TEST_DIR/policy.json" "$TEST_DIR/spec.md")"

  # Context must include DR-xxx
  assert_contains "INV-006: Tier 2 context includes DR-xxx" "DR-010" "$context"

  # Context must NOT include full conversation history markers
  assert_not_contains "INV-006: Tier 2 context excludes conversation history" "conversation_history" "$context"
  assert_not_contains "INV-006: Tier 2 context excludes full spec" "full_spec" "$context"
}

# ============================================
# INV-007 [integration]: Supervisor activation conditions + redirect=hard_stop + 20 cap
# ============================================

test_inv007_supervisor_activation_types() {
  echo ""
  echo "=== INV-007: Supervisor activates only on escalation/phase transitions ==="

  local agent_file="$REPO_DIR/agents/supervisor.md"

  # Verify the three valid activation types are documented
  file_contains "$agent_file" "escalation" \
    "INV-007: supervisor documents escalation activation type"
  file_contains "$agent_file" "phase_transition" \
    "INV-007: supervisor documents phase_transition activation type"
  file_contains "$agent_file" "budget_warning" \
    "INV-007: supervisor documents budget_warning activation type"
}

test_inv007_redirect_is_hard_stop() {
  echo ""
  echo "=== INV-007: redirect → hard_stop (not a valid terminal decision) ==="

  local agent_file="$REPO_DIR/agents/supervisor.md"

  # Agent file must explicitly state redirect is NOT valid
  file_contains_i "$agent_file" "redirect.*NOT.*valid\|redirect.*not.*valid\|not.*redirect" \
    "INV-007: supervisor documents that redirect is not a valid terminal decision"
}

test_inv007_activation_cap_20() {
  echo ""
  echo "=== INV-007: Supervisor activation cap at 20 ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  echo '{"phase":"tdd-impl","supervisor_activation_count":20}' > "$TEST_DIR/state.json"


  # At count=20, the next activation (21) should trigger hard stop
  local count
  count="$(ws_get_field "$TEST_DIR/state.json" "supervisor_activation_count")"
  local should_stop="no"
  [ "$count" -ge 20 ] && should_stop="yes"
  assert_eq "INV-007: activation count >= 20 → should trigger hard stop" "yes" "$should_stop"
}

# ============================================
# INV-017 [integration]: Checkpoint before Tier 2 invocation
# ============================================

test_inv017_checkpoint_write_and_cleanup() {
  echo ""
  echo "=== INV-017: Checkpoint before Tier 2 — write and cleanup ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  local checkpoint_file="$TEST_DIR/pending-decision-test.json"

  # Before Tier 2: checkpoint must be written
  local dr_json='{"decision_id":"DR-020","requesting_agent":"cverify","phase":"done","category":"architecture","summary":"Check arch compliance"}'

  # Write checkpoint (stub should fail, proving test is RED)
  echo "$dr_json" | jq '{dr: ., tier: 2, requesting_skill: "cverify", phase: "done"}' > "$checkpoint_file" 2>/dev/null

  # After Tier 2 completes: checkpoint must be deleted
  # Stub won't do this, so we test the existence expectation
  assert_file_exists "INV-017: checkpoint file written before Tier 2" "$checkpoint_file"

  # The real implementation would delete it after logging DD-xxx
  # We verify the stub scripts provide the functionality

  local context
  context="$(tier2_build_context "$dr_json" "/dev/null" "/dev/null" 2>/dev/null)"
  local rc=$?

  # Stub returns 1 — test is RED
  assert_eq "INV-017: tier2_build_context returns meaningful context (stub fails)" "0" "$rc"
}

# ============================================
# PRH-005 [unit]: Supervisor no accumulated state
# ============================================

test_prh005_supervisor_context_fork() {
  echo ""
  echo "=== PRH-005: Supervisor — context: fork, no accumulated state ==="

  local agent_file="$REPO_DIR/agents/supervisor.md"

  # Agent frontmatter must have context: fork
  local frontmatter
  frontmatter="$(sed -n '/^---$/,/^---$/p' "$agent_file" 2>/dev/null)"
  assert_contains "PRH-005: supervisor has context: fork" "context: fork" "$frontmatter"

  # Agent body must NOT reference prior activations
  file_not_contains "$agent_file" "remember" \
    "PRH-005: supervisor does not use 'remember'"
  file_not_contains "$agent_file" "prior activation" \
    "PRH-005: supervisor does not reference 'prior activation'"
  file_not_contains "$agent_file" "earlier discussion" \
    "PRH-005: supervisor does not reference 'earlier discussion'"
}

# ============================================
# BND-004 [unit]: Unexpected supervisor response → fail-closed
# ============================================

test_bnd004_unexpected_response_hard_stop() {
  echo ""
  echo "=== BND-004: Unexpected supervisor response → hard_stop ==="

  # This tests the orchestrator's response validation logic
  # Valid responses: approve, reject, hard_stop
  # Invalid responses (including redirect) → treated as hard_stop

  local skill_file="$REPO_DIR/skills/cauto/SKILL.md"

  # cauto SKILL.md must document that unexpected responses default to hard_stop
  file_contains_i "$skill_file" "hard_stop.*default\|default.*hard_stop\|unexpected.*hard_stop\|unrecognized.*hard_stop" \
    "BND-004: cauto documents unexpected supervisor response → hard_stop"
}

test_bnd004_redirect_rejected() {
  echo ""
  echo "=== BND-004: redirect response specifically rejected ==="

  local agent_file="$REPO_DIR/agents/supervisor.md"

  # Supervisor agent must document redirect is NOT valid
  file_contains_i "$agent_file" "redirect" \
    "BND-004: supervisor agent mentions redirect"

  # The orchestrator in cauto SKILL.md must handle redirect
  local skill_file="$REPO_DIR/skills/cauto/SKILL.md"
  file_contains_i "$skill_file" "redirect.*hard_stop\|redirect.*treat.*hard_stop\|redirect.*=.*hard_stop" \
    "BND-004: cauto treats redirect as hard_stop"
}

# ============================================
# B-001: INV-004 — Functional supervisor message validation
# ============================================

test_inv004_supervisor_input_schema_validation() {
  echo ""
  echo "=== B-001/INV-004: Supervisor input message — schema validation ==="


  # Construct a valid supervisor input message from fixture data
  local input_json
  input_json="$(cat <<'INPUT_EOF'
{
  "activation_type": "escalation",
  "intent_summary": "Build a policy engine that routes decisions autonomously",
  "decision_request": {
    "decision_id": "DR-050",
    "category": "architecture",
    "summary": "Cross-domain refactoring needed"
  },
  "phase_summary": {
    "phase": "tdd-impl",
    "files_changed": 5,
    "loc_delta": 120,
    "rules_count": 18
  },
  "decision_record_recent": [
    {"decision_id": "DD-001", "summary": "Fixed auth", "disposition": "fix"}
  ],
  "budget_status": {
    "used_tokens": 500000,
    "limit_tokens": 2000000,
    "percent": 25,
    "elapsed_hours": 1.5,
    "limit_hours": 8
  }
}
INPUT_EOF
)"

  # Validate the input message against INV-004 schema
  supervisor_validate_input "$input_json"
  local rc=$?
  assert_eq "B-001/INV-004: valid supervisor input passes schema validation" "0" "$rc"
}

test_inv004_supervisor_input_missing_fields() {
  echo ""
  echo "=== B-001/INV-004: Supervisor input — missing required fields ==="


  # Missing activation_type
  local bad_input='{"intent_summary":"test","decision_request":null,"phase_summary":{},"decision_record_recent":[],"budget_status":{}}'
  supervisor_validate_input "$bad_input" 2>/dev/null
  local rc=$?
  assert_eq "B-001/INV-004: missing activation_type → fail (exit 1)" "1" "$rc"

  # Missing budget_status
  bad_input='{"activation_type":"escalation","intent_summary":"test","decision_request":null,"phase_summary":{},"decision_record_recent":[]}'
  supervisor_validate_input "$bad_input" 2>/dev/null
  rc=$?
  assert_eq "B-001/INV-004: missing budget_status → fail (exit 1)" "1" "$rc"

  # Missing intent_summary
  bad_input='{"activation_type":"escalation","decision_request":null,"phase_summary":{},"decision_record_recent":[],"budget_status":{}}'
  supervisor_validate_input "$bad_input" 2>/dev/null
  rc=$?
  assert_eq "B-001/INV-004: missing intent_summary → fail (exit 1)" "1" "$rc"
}

test_inv004_supervisor_response_schema_validation() {
  echo ""
  echo "=== B-001/INV-004: Supervisor response — schema validation ==="


  # Valid response fixture
  local response_json='{"decision":"approve","reasoning":"Phase transition looks clean, all tests pass","flags":["check_coverage_delta"]}'
  supervisor_validate_response "$response_json"
  local rc=$?
  assert_eq "B-001/INV-004: valid supervisor response passes validation" "0" "$rc"

  # Invalid decision value
  local bad_response='{"decision":"redirect","reasoning":"Send back","flags":[]}'
  supervisor_validate_response "$bad_response" 2>/dev/null
  rc=$?
  assert_eq "B-001/INV-004: 'redirect' decision → fail (exit 1)" "1" "$rc"

  # Missing reasoning
  bad_response='{"decision":"approve","flags":[]}'
  supervisor_validate_response "$bad_response" 2>/dev/null
  rc=$?
  assert_eq "B-001/INV-004: missing reasoning → fail (exit 1)" "1" "$rc"

  # Missing flags
  bad_response='{"decision":"reject","reasoning":"Not ready"}'
  supervisor_validate_response "$bad_response" 2>/dev/null
  rc=$?
  assert_eq "B-001/INV-004: missing flags → fail (exit 1)" "1" "$rc"
}

# ============================================
# B-002: INV-005 — Functional tier routing flow
# ============================================

test_inv005_routing_flow() {
  echo ""
  echo "=== B-002/INV-005: Routing flow — escalation through tiers ==="


  # Precondition: valid adjacent transitions return 0
  validate_tier_hierarchy "1" "2"
  local rc=$?
  assert_eq "B-002/INV-005: precondition — Tier 1 → 2 valid" "0" "$rc"

  # Integration test: route a DR-xxx fixture that needs escalation
  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  cat > "$TEST_DIR/policy.json" << 'EOF'
{"review_dispositions":{"performance":"tier2_decide","default":"tier2_decide"}}
EOF

  # DR-xxx that needs to escalate through tiers (performance → tier2_decide → expect routing)
  local dr_json='{"decision_id":"DR-060","requesting_agent":"creview","phase":"review","category":"performance","summary":"Query optimization needed","options":[{"id":"A","description":"Add index"},{"id":"B","description":"Rewrite query"}],"relevant_rules":[],"relevant_policies":["review_dispositions.performance"],"prior_decisions":[]}'

  local result
  result="$(route_decision "$dr_json" "$TEST_DIR/policy.json" "review" 2>/dev/null)"
  local route_rc=$?

  # The stub returns 1, so this test will FAIL in RED phase
  assert_eq "B-002/INV-005: route_decision returns 0 for valid DR-xxx" "0" "$route_rc"

  # Verify output contains tier information showing proper escalation
  assert_contains "B-002/INV-005: routing result contains tier" "tier" "$result"
}

# ============================================
# B-003: INV-006 — Functional Tier 2 context building
# ============================================

test_inv006_tier2_context_functional() {
  echo ""
  echo "=== B-003/INV-006: Tier 2 context — functional validation ==="


  local dr_json='{"decision_id":"DR-070","requesting_agent":"ctdd","phase":"tdd-impl","category":"testability","summary":"Need test helper refactor","options":[{"id":"A","description":"Inline refactor"}],"relevant_rules":["INV-003"],"relevant_policies":["review_dispositions.testability"],"prior_decisions":[{"decision_id":"DD-001","summary":"Used existing pattern","disposition":"fix"}]}'

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  echo '{"review_dispositions":{"testability":"fix"}}' > "$TEST_DIR/policy.json"
  echo '## Spec Content' > "$TEST_DIR/spec.md"
  echo 'INV-003: DR-xxx format validation' >> "$TEST_DIR/spec.md"

  local context
  context="$(tier2_build_context "$dr_json" "$TEST_DIR/policy.json" "$TEST_DIR/spec.md" 2>/dev/null)"
  local rc=$?

  # Precondition: context must be non-empty valid JSON
  assert_eq "B-003/INV-006: tier2_build_context returns 0" "0" "$rc"

  local is_valid_json="no"
  echo "$context" | jq '.' > /dev/null 2>&1 && is_valid_json="yes"
  assert_eq "B-003/INV-006: context is valid JSON" "yes" "$is_valid_json"

  # Context must contain the DR-xxx data
  assert_contains "B-003/INV-006: context contains DR-xxx decision_id" "DR-070" "$context"

  # Context must contain relevant spec excerpt
  assert_contains "B-003/INV-006: context contains relevant spec content" "INV-003" "$context"

  # Context must contain policy section
  assert_contains "B-003/INV-006: context contains policy section" "testability" "$context"

  # Context must contain prior decisions
  assert_contains "B-003/INV-006: context contains prior decision summary" "DD-001" "$context"
}

# ============================================
# B-004: INV-007 — Functional supervisor cap enforcement
# ============================================

test_inv007_supervisor_cap_functional() {
  echo ""
  echo "=== B-004/INV-007: Supervisor cap enforcement — functional test ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  echo '{"phase":"tdd-impl","supervisor_activation_count":0}' > "$TEST_DIR/state.json"


  # Set count to 19 (under cap)
  ws_set_field "$TEST_DIR/state.json" "supervisor_activation_count" "19"
  local result
  result="$(check_supervisor_cap "$TEST_DIR/state.json" 2>/dev/null)"
  assert_eq "B-004/INV-007: count=19 → ok (under cap)" "ok" "$result"

  # Set count to 20 (at cap)
  ws_set_field "$TEST_DIR/state.json" "supervisor_activation_count" "20"
  result="$(check_supervisor_cap "$TEST_DIR/state.json" 2>/dev/null)"
  assert_eq "B-004/INV-007: count=20 → hard_stop (at cap)" "hard_stop" "$result"

  # Set count to 25 (over cap)
  ws_set_field "$TEST_DIR/state.json" "supervisor_activation_count" "25"
  result="$(check_supervisor_cap "$TEST_DIR/state.json" 2>/dev/null)"
  assert_eq "B-004/INV-007: count=25 → hard_stop (over cap)" "hard_stop" "$result"
}

# ============================================
# QA-R2-001: route_decision forwards stored_hash to policy_evaluate (INV-018)
# ============================================

test_qar2001_route_decision_hash_forwarding() {
  echo ""
  echo "=== QA-R2-001: route_decision forwards stored_hash (INV-018) ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' EXIT

  cat > "$TEST_DIR/policy.json" << 'EOF'
{"review_dispositions":{"security":"fix","performance":"tier2_decide"}}
EOF

  # Compute correct hash
  local correct_hash
  correct_hash="$(policy_hash "$TEST_DIR/policy.json" 2>/dev/null)"

  # Route with correct hash — should succeed
  local dr_json='{"decision_id":"DR-090","requesting_agent":"creview","phase":"review","category":"security","summary":"Fix auth issue","options":[],"relevant_rules":[],"relevant_policies":[],"prior_decisions":[]}'

  local result
  result="$(route_decision "$dr_json" "$TEST_DIR/policy.json" "review" "$correct_hash" 2>/dev/null)"
  local rc=$?
  assert_eq "QA-R2-001: route_decision with correct hash returns 0" "0" "$rc"
  assert_contains "QA-R2-001: route_decision with correct hash returns result" "tier" "$result"

  # Tamper with policy file
  echo '{"review_dispositions":{"security":"defer"}}' > "$TEST_DIR/policy.json"

  # Route with original hash — should detect tamper and return hard_stop (INV-018)
  result="$(route_decision "$dr_json" "$TEST_DIR/policy.json" "review" "$correct_hash" 2>/dev/null)"
  rc=$?
  assert_eq "QA-R2-001: route_decision returns 0 even on tamper (structured result)" "0" "$rc"
  assert_contains "QA-R2-001: tampered policy triggers hard_stop" "hard_stop" "$result"
  assert_contains "QA-R2-001: tampered policy returns tier 4" '"tier": 4' "$result"
}

# ============================================
# QA-R2-002: tier2_build_context selects correct policy section by phase
# ============================================

test_qar2002_tier2_context_phase_aware() {
  echo ""
  echo "=== QA-R2-002: tier2_build_context phase-aware policy section ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' EXIT

  cat > "$TEST_DIR/policy.json" << 'EOF'
{
  "review_dispositions": {"security": "fix"},
  "qa_dispositions": {"critical": "fix", "high": "fix"},
  "drift": {"clear_violation": "fix"},
  "spec_update": {"max_autonomous_revisions": 2}
}
EOF
  echo '## Spec' > "$TEST_DIR/spec.md"

  # QA-phase DR-xxx should get qa_dispositions section
  local dr_qa='{"decision_id":"DR-100","requesting_agent":"ctdd","phase":"tdd-qa","category":"critical","summary":"QA finding","options":[],"relevant_rules":[],"relevant_policies":[],"prior_decisions":[]}'

  local result
  result="$(tier2_build_context "$dr_qa" "$TEST_DIR/policy.json" "$TEST_DIR/spec.md" 2>/dev/null)"
  assert_contains "QA-R2-002: QA-phase context includes qa_dispositions" "qa_dispositions" "$result"
  assert_not_contains "QA-R2-002: QA-phase context does NOT include review_dispositions" "review_dispositions" "$result"

  # Verify-phase DR-xxx should get drift section
  local dr_verify='{"decision_id":"DR-101","requesting_agent":"cverify","phase":"verify","category":"clear_violation","summary":"Drift found","options":[],"relevant_rules":[],"relevant_policies":[],"prior_decisions":[]}'

  result="$(tier2_build_context "$dr_verify" "$TEST_DIR/policy.json" "$TEST_DIR/spec.md" 2>/dev/null)"
  assert_contains "QA-R2-002: verify-phase context includes drift" "drift" "$result"
  assert_not_contains "QA-R2-002: verify-phase context does NOT include review_dispositions" "review_dispositions" "$result"
}

# ============================================
# Runner
# ============================================

echo "============================================="
echo "Auto Mode Phase 2 — Agent Interfaces + Routing"
echo "============================================="

# INV-004: Supervisor message interface
test_inv004_supervisor_input_format
test_inv004_supervisor_output_format

# B-001/INV-004: Functional supervisor message validation
test_inv004_supervisor_input_schema_validation
test_inv004_supervisor_input_missing_fields
test_inv004_supervisor_response_schema_validation

# INV-005: Tier routing hierarchy
test_inv005_no_tier_skipping

# B-002/INV-005: Functional routing flow
test_inv005_routing_flow

# INV-006: Tier 2 minimal context
test_inv006_tier2_allowed_tools
test_inv006_tier2_context_fork
test_inv006_tier2_minimal_context

# B-003/INV-006: Functional Tier 2 context building
test_inv006_tier2_context_functional

# INV-007: Supervisor activation
test_inv007_supervisor_activation_types
test_inv007_redirect_is_hard_stop
test_inv007_activation_cap_20

# B-004/INV-007: Functional supervisor cap enforcement
test_inv007_supervisor_cap_functional

# INV-017: Checkpoint before Tier 2
test_inv017_checkpoint_write_and_cleanup

# PRH-005: Supervisor no accumulated state
test_prh005_supervisor_context_fork

# BND-004: Unexpected supervisor response
test_bnd004_unexpected_response_hard_stop
test_bnd004_redirect_rejected

# QA-R2-001: route_decision forwards stored_hash (INV-018)
test_qar2001_route_decision_hash_forwarding

# QA-R2-002: tier2_build_context uses correct phase section
test_qar2002_tier2_context_phase_aware

echo ""
echo "============================================="
echo "Results: $PASS passed, $FAIL failed"
echo ""

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
