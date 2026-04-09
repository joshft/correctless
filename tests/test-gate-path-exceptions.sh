#!/usr/bin/env bash
# Correctless — Gate Path Exception Tests
# Tests R-020, R-022 through R-024 from the infrastructure hardening spec.
# Run from repo root: bash tests/test-gate-path-exceptions.sh

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATE_HOOK="$REPO_DIR/hooks/workflow-gate.sh"
LIB_SH="$REPO_DIR/scripts/lib.sh"
PASS=0
FAIL=0

# ============================================================================
# Helpers
# ============================================================================

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
  if grep -qF "$expected" <<< "$actual"; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (expected output to contain '$expected')"
    FAIL=$((FAIL + 1))
  fi
}

assert_not_exists() {
  local desc="$1" path="$2"
  if [ ! -e "$path" ]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (path '$path' should not exist but does)"
    FAIL=$((FAIL + 1))
  fi
}

# Run the gate hook with a tool_name and file_path, return "EXIT_CODE:STDERR"
run_gate() {
  local tool_name="$1" file_path="$2"
  local exit_code stderr_output
  stderr_output="$(echo "{\"tool_name\": \"$tool_name\", \"tool_input\": {\"file_path\": \"$file_path\"}}" \
    | bash "$GATE_HOOK" 2>&1 >/dev/null)" && exit_code=0 || exit_code=$?
  echo "${exit_code}:${stderr_output}"
}

# Run the gate hook with a Write tool and content
run_gate_write() {
  local file_path="$1" content="$2"
  local exit_code stderr_output
  stderr_output="$(printf '{"tool_name": "Write", "tool_input": {"file_path": "%s", "content": "%s"}}' "$file_path" "$content" \
    | bash "$GATE_HOOK" 2>&1 >/dev/null)" && exit_code=0 || exit_code=$?
  echo "${exit_code}:${stderr_output}"
}

# Run the gate hook with a Bash command
run_gate_bash() {
  local command="$1"
  local exit_code stderr_output
  local json_input
  json_input="$(jq -nc --arg cmd "$command" '{"tool_name": "Bash", "tool_input": {"command": $cmd}}')"
  stderr_output="$(echo "$json_input" \
    | bash "$GATE_HOOK" 2>&1 >/dev/null)" && exit_code=0 || exit_code=$?
  echo "${exit_code}:${stderr_output}"
}

extract_exit() {
  echo "$1" | head -1 | cut -d: -f1
}

extract_stderr() {
  echo "$1" | cut -d: -f2-
}

# ============================================================================
# Test environment
# ============================================================================

TEST_DIR="/tmp/correctless-test-gate-paths-$$"
BRANCH_NAME="feature/test-gate-paths"

setup_test_env() {
  rm -rf "$TEST_DIR"
  mkdir -p "$TEST_DIR"
  cd "$TEST_DIR" || exit 1

  # Initialize git repo with feature branch
  git init -q
  git branch -M main
  echo "init" > README.md
  git add -A && git commit -q -m "init"
  git checkout -q -b "$BRANCH_NAME"

  # Copy lib.sh
  mkdir -p scripts
  cp "$LIB_SH" scripts/lib.sh

  # Create workflow config
  mkdir -p .correctless/config
  cat > .correctless/config/workflow-config.json <<'WCEOF'
{
  "patterns": {
    "test_file": "*.test.ts|*.spec.ts",
    "source_file": "*.ts|*.js|*.sh|*.md"
  },
  "workflow": {
    "fail_closed_when_no_state": false
  }
}
WCEOF

  # Create artifacts directory
  mkdir -p .correctless/artifacts .correctless/specs

  # Compute branch slug for state file path
  source scripts/lib.sh
  SLUG="$(branch_slug)"
  STATE_FILE=".correctless/artifacts/workflow-state-${SLUG}.json"
}

set_phase() {
  local phase="$1"
  cat > "$TEST_DIR/$STATE_FILE" <<EOF
{
  "phase": "$phase",
  "override": {
    "active": false,
    "remaining_calls": 0
  }
}
EOF
}

set_phase_with_override() {
  local phase="$1" remaining="$2"
  cat > "$TEST_DIR/$STATE_FILE" <<EOF
{
  "phase": "$phase",
  "override": {
    "active": true,
    "remaining_calls": $remaining
  }
}
EOF
}

cleanup() {
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

echo "Correctless Gate Path Exception Tests"
echo "======================================="

# ============================================================================
# R-020 [integration]: Override decrement acquires state lock
# ============================================================================

test_override_uses_locking() {
  echo ""
  echo "=== R-020: Override decrement uses state lock ==="

  setup_test_env
  set_phase_with_override "tdd-qa" 5

  source scripts/lib.sh

  # The override decrement in workflow-gate.sh should acquire the state lock
  # before reading/writing the state file. We verify this by checking that:
  # 1. The override decrement path uses locking functions from lib.sh
  # 2. After an override call, the lockfile is not left behind (lock released)

  local lock_dir="${TEST_DIR}/${STATE_FILE}.lock"

  # Make a gate call that triggers the override decrement
  local result
  result="$(run_gate "Edit" "src/app.ts")"
  local exit_code
  exit_code="$(extract_exit "$result")"

  # Override should allow the operation
  assert_eq "R-020a: override allows the operation" "0" "$exit_code"

  # Lockfile must NOT be left behind
  assert_not_exists "R-020b: no stale lock after override decrement" "$lock_dir"

  # Verify remaining was actually decremented
  local remaining
  remaining="$(jq -r '.override.remaining_calls' "$TEST_DIR/$STATE_FILE" 2>/dev/null)"
  assert_eq "R-020c: override remaining decremented" "4" "$remaining"

  # Static analysis: the gate hook should reference locking functions
  # (This will fail until the gate is updated to use _acquire_state_lock)
  local gate_uses_lock="no"
  if grep -qE '_acquire_state_lock|locked_update_state' "$GATE_HOOK" 2>/dev/null; then
    gate_uses_lock="yes"
  fi
  assert_eq "R-020d: gate hook uses locking functions" "yes" "$gate_uses_lock"

  # Static analysis: workflow-advance.sh should also reference locking functions (AUDIT-003 fix)
  local adv_uses_lock="no"
  if grep -qE '_acquire_state_lock|locked_update_state' "$REPO_DIR/hooks/workflow-advance.sh" 2>/dev/null; then
    adv_uses_lock="yes"
  fi
  assert_eq "R-020e: workflow-advance.sh uses locking functions" "yes" "$adv_uses_lock"
}

# ============================================================================
# R-022 [integration]: Spec phase allows writes to .correctless/specs/
# ============================================================================

test_spec_phase_allows_spec_writes() {
  echo ""
  echo "=== R-022: Spec phase allows writes to .correctless/specs/ ==="

  setup_test_env
  set_phase "spec"

  local result

  # Write a spec file — should be ALLOWED even though .md matches source pattern
  result="$(run_gate_write ".correctless/specs/my-feature.md" "# Spec for my feature")"
  assert_eq "R-022a: spec phase allows Write to .correctless/specs/*.md" "0" "$(extract_exit "$result")"

  # Edit a spec file
  result="$(run_gate "Edit" ".correctless/specs/my-feature.md")"
  assert_eq "R-022b: spec phase allows Edit to .correctless/specs/*.md" "0" "$(extract_exit "$result")"

  # Write a non-.md spec file with source-matching extension (AUDIT-002 fix)
  result="$(run_gate_write ".correctless/specs/constraints.sh" "#!/bin/bash")"
  assert_eq "R-022c: spec phase allows Write to .correctless/specs/*.sh" "0" "$(extract_exit "$result")"

  # Verify that normal source files are STILL blocked in spec phase
  result="$(run_gate "Edit" "src/app.ts")"
  assert_eq "R-022d: spec phase still blocks source files" "2" "$(extract_exit "$result")"

  # Spec file under a subdirectory of specs/
  result="$(run_gate_write ".correctless/specs/subsystem/auth.md" "# Auth spec")"
  assert_eq "R-022e: spec phase allows Write to .correctless/specs/ subdirectory" "0" "$(extract_exit "$result")"
}

# ============================================================================
# R-023 [integration]: Artifacts directory writable in all phases
# ============================================================================

test_artifacts_always_writable() {
  echo ""
  echo "=== R-023: .correctless/artifacts/ writable in all phases ==="

  setup_test_env

  local result

  # Test in multiple restrictive phases
  for phase in spec review tdd-tests tdd-qa tdd-verify; do
    set_phase "$phase"

    # Write to artifact files using extensions that MATCH source_file pattern
    # (.sh, .md) so they'd be blocked by phase gating without the path exception.
    # Using .json would classify as "other" and pass trivially (AUDIT-001 fix).
    result="$(run_gate_write ".correctless/artifacts/qa-findings.sh" "#!/bin/bash")"
    assert_eq "R-023a-$phase: Write to artifacts/*.sh allowed in $phase" "0" "$(extract_exit "$result")"

    result="$(run_gate_write ".correctless/artifacts/token-log.md" "# Token log")"
    assert_eq "R-023b-$phase: Write to artifacts/*.md allowed in $phase" "0" "$(extract_exit "$result")"

    # Edit an artifact with source-matching extension
    result="$(run_gate "Edit" ".correctless/artifacts/override-log.sh")"
    assert_eq "R-023c-$phase: Edit artifacts/*.sh allowed in $phase" "0" "$(extract_exit "$result")"
  done
}

# ============================================================================
# QA-003: MultiEdit with mixed excepted and non-excepted paths
# ============================================================================

test_multiedit_mixed_paths() {
  echo ""
  echo "=== QA-003: MultiEdit with mixed excepted/non-excepted paths ==="

  setup_test_env
  set_phase "tdd-tests"

  local result exit_code

  # MultiEdit with an artifact .sh file (excepted) + a test file (allowed in tdd-tests)
  # The artifact .sh file should NOT poison classification to "source" and block the operation.
  local json_input
  json_input='{"tool_name": "MultiEdit", "tool_input": {"edits": [
    {"file_path": ".correctless/artifacts/qa-findings.sh", "old_string": "a", "new_string": "b"},
    {"file_path": "tests/my.test.ts", "old_string": "x", "new_string": "y"}
  ]}}'
  exit_code="$(echo "$json_input" | bash "$GATE_HOOK" >/dev/null 2>&1; echo $?)"
  assert_eq "QA-003a: MultiEdit artifact + test file allowed in tdd-tests" "0" "$exit_code"

  # MultiEdit with artifact .sh (excepted) + source file (blocked in tdd-tests without STUB:TDD)
  # Should block because source file is not excepted
  json_input='{"tool_name": "MultiEdit", "tool_input": {"edits": [
    {"file_path": ".correctless/artifacts/qa-findings.sh", "old_string": "a", "new_string": "b"},
    {"file_path": "src/app.ts", "old_string": "x", "new_string": "y"}
  ]}}'
  exit_code="$(echo "$json_input" | bash "$GATE_HOOK" >/dev/null 2>&1; echo $?)"
  assert_eq "QA-003b: MultiEdit artifact + source file blocked in tdd-tests" "2" "$exit_code"

  # Spec phase: MultiEdit with spec file (excepted) + source file (blocked)
  set_phase "spec"
  json_input='{"tool_name": "MultiEdit", "tool_input": {"edits": [
    {"file_path": ".correctless/specs/my-spec.md", "old_string": "a", "new_string": "b"},
    {"file_path": "src/app.ts", "old_string": "x", "new_string": "y"}
  ]}}'
  exit_code="$(echo "$json_input" | bash "$GATE_HOOK" >/dev/null 2>&1; echo $?)"
  assert_eq "QA-003c: MultiEdit spec + source file blocked in spec phase" "2" "$exit_code"

  # Spec phase: MultiEdit with all-excepted files should be allowed
  json_input='{"tool_name": "MultiEdit", "tool_input": {"edits": [
    {"file_path": ".correctless/specs/spec-a.md", "old_string": "a", "new_string": "b"},
    {"file_path": ".correctless/artifacts/log.sh", "old_string": "x", "new_string": "y"}
  ]}}'
  exit_code="$(echo "$json_input" | bash "$GATE_HOOK" >/dev/null 2>&1; echo $?)"
  assert_eq "QA-003d: MultiEdit all-excepted files allowed in spec phase" "0" "$exit_code"
}

# ============================================================================
# R-024 [integration]: Bash command containing workflow-advance.sh is allowed
# ============================================================================

test_workflow_advance_bash_allowed() {
  echo ""
  echo "=== R-024: Bash with workflow-advance.sh allowed in all phases ==="

  setup_test_env

  local result

  for phase in spec review tdd-tests tdd-qa tdd-verify; do
    set_phase "$phase"

    # All commands include write patterns so _has_write_pattern returns true
    # and the gate falls through to phase checking (AUDIT-004 fix).
    # Without the workflow-advance.sh exception, these would be BLOCKED.

    # workflow-advance.sh status with redirect (triggers write detection via >)
    result="$(run_gate_bash ".correctless/hooks/workflow-advance.sh status 2>&1 | tee /tmp/status.log")"
    assert_eq "R-024a-$phase: workflow-advance.sh status with redirect allowed in $phase" "0" "$(extract_exit "$result")"

    # workflow-advance.sh with logging redirect
    result="$(run_gate_bash ".correctless/hooks/workflow-advance.sh review 2>&1 | tee advance.log")"
    assert_eq "R-024b-$phase: workflow-advance.sh with tee allowed in $phase" "0" "$(extract_exit "$result")"

    # workflow-advance.sh init with redirect
    result="$(run_gate_bash ".correctless/hooks/workflow-advance.sh init \"my feature\" 2>&1 | tee init.log")"
    assert_eq "R-024c-$phase: workflow-advance.sh init with redirect allowed in $phase" "0" "$(extract_exit "$result")"
  done
}

# ============================================================================
# Run all tests
# ============================================================================

test_override_uses_locking
test_spec_phase_allows_spec_writes
test_artifacts_always_writable
test_multiedit_mixed_paths
test_workflow_advance_bash_allowed

# ============================================================================
# Summary
# ============================================================================

echo ""
echo "=============================="
echo "  PASS: $PASS"
echo "  FAIL: $FAIL"
echo "=============================="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
