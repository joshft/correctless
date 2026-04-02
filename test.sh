#!/usr/bin/env bash
# Correctless — automated test suite
# Tests the setup script, state machine, and gate hook.
# Run from the repo root: ./test.sh

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_DIR="/tmp/correctless-test-$$"
PASS=0
FAIL=0

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

setup_test_project() {
  rm -rf "$TEST_DIR"
  mkdir -p "$TEST_DIR"
  cd "$TEST_DIR" || exit
  git init -q
  git branch -M main
  echo '{"name": "test-app", "scripts": {"test": "echo FAIL && exit 1", "lint": "echo ok", "build": "echo ok"}}' > package.json
  echo 'export function hello() {}' > index.ts
  git add -A && git commit -q -m "init"

  # Install correctless (exclude .git to avoid nested repo confusion)
  mkdir -p .claude/skills/workflow
  rsync -a --exclude='.git' "$REPO_DIR/" .claude/skills/workflow/
}

cleanup() {
  rm -rf "$TEST_DIR"
}

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
  if echo "$actual" | grep -q "$expected"; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (expected output to contain '$expected')"
    FAIL=$((FAIL + 1))
  fi
}

assert_exit() {
  local desc="$1" expected_exit="$2"
  shift 2
  local actual_exit
  "$@" >/dev/null 2>&1 && actual_exit=0 || actual_exit=$?
  assert_eq "$desc" "$expected_exit" "$actual_exit"
}

ADV() { cd "$TEST_DIR" && .claude/hooks/workflow-advance.sh "$@"; }
GATE_INPUT() { cd "$TEST_DIR" && echo "$1" | .claude/hooks/workflow-gate.sh 2>&1; }
GATE_EXIT() { cd "$TEST_DIR" && echo "$1" | .claude/hooks/workflow-gate.sh >/dev/null 2>&1; echo $?; }

# ---------------------------------------------------------------------------
# Test: Setup Script
# ---------------------------------------------------------------------------

test_setup() {
  echo ""
  echo "=== Setup Script ==="

  setup_test_project
  local output
  output="$(.claude/skills/workflow/setup 2>&1)"

  assert_contains "detects TypeScript" "typescript" "$output"
  assert_eq "creates workflow-config.json" "true" "$([ -f .claude/workflow-config.json ] && echo true || echo false)"
  assert_eq "creates ARCHITECTURE.md" "true" "$([ -f ARCHITECTURE.md ] && echo true || echo false)"
  assert_eq "creates AGENT_CONTEXT.md" "true" "$([ -f AGENT_CONTEXT.md ] && echo true || echo false)"
  assert_eq "creates antipatterns.md" "true" "$([ -f .claude/antipatterns.md ] && echo true || echo false)"
  assert_eq "creates settings.json" "true" "$([ -f .claude/settings.json ] && echo true || echo false)"
  assert_eq "creates hooks dir" "true" "$([ -f .claude/hooks/workflow-gate.sh ] && echo true || echo false)"
  assert_contains "hooks reference .claude/hooks/" ".claude/hooks/workflow-gate.sh" "$(cat .claude/settings.json)"
  assert_contains "settings has hooks array format" '"hooks"' "$(cat .claude/settings.json)"
  assert_contains "settings has audit-trail hook" "audit-trail" "$(cat .claude/settings.json)"
  assert_eq "creates docs/specs" "true" "$([ -d docs/specs ] && echo true || echo false)"
  assert_eq "creates .claude/artifacts" "true" "$([ -d .claude/artifacts ] && echo true || echo false)"

  # Idempotency
  local output2
  output2="$(.claude/skills/workflow/setup 2>&1)"
  assert_contains "idempotent — skips existing config" "already exists" "$output2"

  # Partial settings — gate exists but audit-trail missing (bug regression test)
  local partial_settings='{"hooks":{"PreToolUse":[{"matcher":"Edit","hooks":[{"type":"command","command":".claude/hooks/workflow-gate.sh"}]}]}}'
  echo "$partial_settings" > .claude/settings.json
  .claude/skills/workflow/setup >/dev/null 2>&1
  assert_contains "partial settings: adds audit-trail" "audit-trail" "$(cat .claude/settings.json)"
  assert_contains "partial settings: adds permissions" "workflow-advance" "$(cat .claude/settings.json)"
}

# ---------------------------------------------------------------------------
# Test: State Machine Transitions
# ---------------------------------------------------------------------------

test_state_machine() {
  echo ""
  echo "=== State Machine ==="

  setup_test_project
  .claude/skills/workflow/setup >/dev/null 2>&1

  # Init refuses on main
  local out
  out="$(ADV init "test" 2>&1)" && true
  assert_contains "init refuses on main" "Cannot init workflow on" "$out"

  # Init on feature branch
  git checkout -q -b feature/test-sm
  ADV init "test feature" >/dev/null 2>&1
  assert_eq "init sets phase to spec" "spec" "$(ADV status 2>&1 | grep 'Phase:' | awk '{print $2}')"

  # Can't skip to impl from spec
  out="$(ADV impl 2>&1)" && true
  assert_contains "can't skip spec→impl" "Expected phase" "$out"

  # spec → review
  mkdir -p docs/specs
  echo "# Spec" > docs/specs/test-feature.md
  ADV review >/dev/null 2>&1
  assert_eq "review phase" "review" "$(ADV status 2>&1 | grep 'Phase:' | awk '{print $2}')"

  # review → tdd-tests
  ADV tests >/dev/null 2>&1
  assert_eq "tdd-tests phase" "tdd-tests" "$(ADV status 2>&1 | grep 'Phase:' | awk '{print $2}')"

  # Can't advance to impl without test files
  out="$(ADV impl 2>&1)" && true
  assert_contains "impl needs test files" "No test files found" "$out"

  # Create test file, advance to impl
  echo '// test' > foo.test.ts
  git add foo.test.ts
  ADV impl >/dev/null 2>&1
  assert_eq "tdd-impl phase" "tdd-impl" "$(ADV status 2>&1 | grep 'Phase:' | awk '{print $2}')"

  # Can't advance to qa with failing tests
  out="$(ADV qa 2>&1)" && true
  assert_contains "qa needs passing tests" "Tests do not pass" "$out"

  # Make tests pass, advance to qa
  echo '{"name": "test-app", "scripts": {"test": "echo PASS && exit 0"}}' > package.json
  ADV qa >/dev/null 2>&1
  assert_eq "tdd-qa phase" "tdd-qa" "$(ADV status 2>&1 | grep 'Phase:' | awk '{print $2}')"
  assert_eq "qa_rounds is 1" "1" "$(ADV status 2>&1 | grep 'QA rounds:' | awk '{print $3}')"

  # done
  ADV "done" >/dev/null 2>&1
  assert_eq "done phase" "done" "$(ADV status 2>&1 | grep 'Phase:' | awk '{print $2}')"

  # verified requires report file
  local ver_out
  ver_out="$(ADV verified 2>&1)" && true
  assert_contains "verified needs report" "Verification report not found" "$ver_out"

  # Create report and advance
  mkdir -p docs/verification
  echo "# Verification" > docs/verification/test-feature-verification.md
  ADV verified >/dev/null 2>&1
  assert_eq "verified phase" "verified" "$(ADV status 2>&1 | grep 'Phase:' | awk '{print $2}')"

  # documented
  ADV documented >/dev/null 2>&1
  assert_eq "documented phase" "documented" "$(ADV status 2>&1 | grep 'Phase:' | awk '{print $2}')"

  # State file persists
  assert_eq "state file persists" "true" "$(ls .claude/artifacts/workflow-state-feature-test-sm-*.json >/dev/null 2>&1 && echo true || echo false)"
}

# ---------------------------------------------------------------------------
# Test: Gate Hook
# ---------------------------------------------------------------------------

test_gate() {
  echo ""
  echo "=== Gate Hook ==="

  setup_test_project
  .claude/skills/workflow/setup >/dev/null 2>&1
  git checkout -q -b feature/test-gate
  ADV init "gate test" >/dev/null 2>&1
  mkdir -p docs/specs
  echo "# Spec" > docs/specs/gate-test.md
  ADV review >/dev/null 2>&1
  ADV tests >/dev/null 2>&1

  # RED phase: block source without STUB:TDD
  local exit_code
  exit_code="$(GATE_EXIT '{"tool_name": "Write", "tool_input": {"file_path": "'"$TEST_DIR"'/index.ts", "content": "function hello() { return 1; }"}}')"
  assert_eq "RED: blocks source without STUB:TDD" "2" "$exit_code"

  # RED phase: allow source with STUB:TDD
  exit_code="$(GATE_EXIT '{"tool_name": "Write", "tool_input": {"file_path": "'"$TEST_DIR"'/stub.ts", "content": "function hello() {\n  // STUB:TDD\n  return null;\n}"}}')"
  assert_eq "RED: allows source with STUB:TDD" "0" "$exit_code"

  # RED phase: allow test files
  exit_code="$(GATE_EXIT '{"tool_name": "Edit", "tool_input": {"file_path": "'"$TEST_DIR"'/foo.test.ts"}}')"
  assert_eq "RED: allows test files" "0" "$exit_code"

  # RED phase: allow non-source files
  exit_code="$(GATE_EXIT '{"tool_name": "Write", "tool_input": {"file_path": "'"$TEST_DIR"'/README.md", "content": "hello"}}')"
  assert_eq "RED: allows markdown" "0" "$exit_code"

  # Block state file edits
  exit_code="$(GATE_EXIT '{"tool_name": "Edit", "tool_input": {"file_path": "'"$TEST_DIR"'/.claude/artifacts/workflow-state-feature-test-gate.json"}}')"
  assert_eq "blocks state file edits" "2" "$exit_code"

  # Advance to impl then qa
  echo '{"name": "test-app", "scripts": {"test": "echo FAIL && exit 1"}}' > package.json
  echo '// test' > bar.test.ts && git add bar.test.ts
  local impl_out qa_out
  impl_out="$(ADV impl 2>&1)" || true
  echo '{"name": "test-app", "scripts": {"test": "echo PASS && exit 0"}}' > package.json
  qa_out="$(ADV qa 2>&1)" || true

  # Verify we're actually in QA before testing the gate
  cd "$TEST_DIR" || exit
  local gate_phase
  gate_phase="$(cat .claude/artifacts/workflow-state-feature-test-gate-*.json 2>/dev/null | jq -r '.phase' 2>/dev/null)"
  assert_eq "gate test: in QA phase" "tdd-qa" "$gate_phase"
  if [ "$gate_phase" != "tdd-qa" ]; then
    echo "    IMPL output: $impl_out"
    echo "    QA output: $qa_out"
  fi

  # QA phase: block source
  exit_code="$(GATE_EXIT '{"tool_name": "Edit", "tool_input": {"file_path": "'"$TEST_DIR"'/index.ts"}}')"
  assert_eq "QA: blocks source" "2" "$exit_code"

  # QA phase: block test
  cd "$TEST_DIR" || exit
  local test_gate_exit
  echo '{"tool_name": "Edit", "tool_input": {"file_path": "'"$TEST_DIR"'/bar.test.ts"}}' | .claude/hooks/workflow-gate.sh >/dev/null 2>&1 && test_gate_exit=0 || test_gate_exit=$?
  assert_eq "QA: blocks test" "2" "$test_gate_exit"

  # QA phase: allow markdown
  exit_code="$(GATE_EXIT '{"tool_name": "Write", "tool_input": {"file_path": "'"$TEST_DIR"'/notes.md", "content": "findings"}}')"
  assert_eq "QA: allows markdown" "0" "$exit_code"

  # QA error message is actionable
  local msg
  msg="$(GATE_INPUT '{"tool_name": "Edit", "tool_input": {"file_path": "'"$TEST_DIR"'/index.ts"}}')"
  assert_contains "QA message mentions fix command" "workflow-advance.sh fix" "$msg"
  assert_contains "QA message mentions done command" "workflow-advance.sh done" "$msg"
}

# ---------------------------------------------------------------------------
# Test: Override and Diagnose
# ---------------------------------------------------------------------------

test_utilities() {
  echo ""
  echo "=== Utilities ==="

  setup_test_project
  .claude/skills/workflow/setup >/dev/null 2>&1
  git checkout -q -b feature/test-util
  ADV init "util test" >/dev/null 2>&1
  mkdir -p docs/specs
  echo "# Spec" > docs/specs/util-test.md
  ADV review >/dev/null 2>&1
  ADV tests >/dev/null 2>&1
  echo '{"name": "test-app", "scripts": {"test": "echo FAIL && exit 1"}}' > package.json
  echo '// test' > x.test.ts && git add x.test.ts
  ADV impl >/dev/null 2>&1
  echo '{"name": "test-app", "scripts": {"test": "echo PASS && exit 0"}}' > package.json
  ADV qa >/dev/null 2>&1

  # Override allows blocked edits
  ADV override "testing override" >/dev/null 2>&1
  local exit_code
  exit_code="$(GATE_EXIT '{"tool_name": "Edit", "tool_input": {"file_path": "'"$TEST_DIR"'/index.ts"}}')"
  assert_eq "override allows blocked edit" "0" "$exit_code"

  # Override log exists
  assert_eq "override log created" "true" "$([ -f .claude/artifacts/override-log.json ] && echo true || echo false)"

  # Diagnose shows info
  local diag
  diag="$(ADV diagnose "index.ts" 2>&1)"
  assert_contains "diagnose shows phase" "Current phase" "$diag"
  assert_contains "diagnose shows classification" "File classification" "$diag"
  assert_contains "diagnose shows decision" "Decision" "$diag"

  # Spec-update
  ADV reset >/dev/null 2>&1
  git checkout -q -b feature/test-specupdate
  ADV init "specupdate test" >/dev/null 2>&1
  mkdir -p docs/specs
  echo "# Spec" > docs/specs/specupdate-test.md
  ADV review >/dev/null 2>&1
  ADV tests >/dev/null 2>&1
  ADV spec-update "rule was wrong" >/dev/null 2>&1
  assert_eq "spec-update returns to spec" "spec" "$(ADV status 2>&1 | grep 'Phase:' | awk '{print $2}')"
  assert_contains "spec-update records history" "Spec updates: 1" "$(ADV status 2>&1)"

  # Status-all
  local status_all
  status_all="$(ADV status-all 2>&1)"
  assert_contains "status-all shows branch" "feature/test-specupdate" "$status_all"
}

# ---------------------------------------------------------------------------
# Test: Full Mode Features
# ---------------------------------------------------------------------------

test_full_mode() {
  echo ""
  echo "=== Full Mode ==="

  setup_test_project
  .claude/skills/workflow/setup >/dev/null 2>&1

  # Enable full mode
  jq '.workflow += {"intensity": "high", "min_qa_rounds": 2, "fail_closed_when_no_state": true}' .claude/workflow-config.json > "$TEST_DIR/fc.$$.json"
  mv "$TEST_DIR/fc.$$.json" .claude/workflow-config.json

  # Fail-closed: no state file blocks source edits
  git checkout -q -b feature/test-full
  local exit_code
  exit_code="$(GATE_EXIT '{"tool_name": "Edit", "tool_input": {"file_path": "'"$TEST_DIR"'/index.ts"}}')"
  assert_eq "fail-closed blocks without state" "2" "$exit_code"

  # Init and test model/review-spec transitions
  ADV init "full test" >/dev/null 2>&1
  mkdir -p docs/specs
  echo "# Spec" > docs/specs/full-test.md

  # Model transition (should fail without formal_model)
  local out
  out="$(ADV model 2>&1)" && true
  # It may succeed or fail depending on formal_model setting — just check it doesn't crash

  # review-spec transition
  ADV review-spec >/dev/null 2>&1 || ADV review >/dev/null 2>&1  # one will work
  ADV tests >/dev/null 2>&1

  echo '{"name": "test-app", "scripts": {"test": "echo FAIL && exit 1"}}' > package.json
  echo '// test' > y.test.ts && git add y.test.ts
  ADV impl >/dev/null 2>&1
  echo '{"name": "test-app", "scripts": {"test": "echo PASS && exit 0"}}' > package.json
  ADV qa >/dev/null 2>&1

  # min_qa_rounds=2: can't go to done after 1 round
  out="$(ADV "done" 2>&1)" && true
  assert_contains "enforces min_qa_rounds" "Only 1 QA round" "$out"

  # Fix round + second QA
  ADV fix >/dev/null 2>&1
  ADV qa >/dev/null 2>&1

  # Now verify-phase should work
  ADV verify-phase >/dev/null 2>&1
  assert_eq "tdd-verify phase" "tdd-verify" "$(ADV status 2>&1 | grep 'Phase:' | awk '{print $2}')"

  # tdd-verify blocks edits
  exit_code="$(GATE_EXIT '{"tool_name": "Edit", "tool_input": {"file_path": "'"$TEST_DIR"'/index.ts"}}')"
  assert_eq "tdd-verify blocks source" "2" "$exit_code"

  # Done from tdd-verify
  ADV "done" >/dev/null 2>&1
  assert_eq "done from tdd-verify" "done" "$(ADV status 2>&1 | grep 'Phase:' | awk '{print $2}')"
}

# ---------------------------------------------------------------------------
# Test: Additional Coverage (from QA audit findings)
# ---------------------------------------------------------------------------

test_additional_coverage() {
  echo ""
  echo "=== Additional Coverage ==="

  setup_test_project
  .claude/skills/workflow/setup >/dev/null 2>&1

  # N11: Test spec→tests rejection when spec_updates=0
  git checkout -q -b feature/test-review-skip
  ADV init "review skip test" >/dev/null 2>&1
  mkdir -p docs/specs
  echo "# Spec" > docs/specs/review-skip-test.md
  local out
  out="$(ADV tests 2>&1)" && true
  assert_contains "blocks spec→tests without review" "Cannot skip review" "$out"

  # After review, tests should work
  ADV review >/dev/null 2>&1
  ADV tests >/dev/null 2>&1
  assert_eq "tests after review" "tdd-tests" "$(ADV status 2>&1 | grep 'Phase:' | awk '{print $2}')"

  # N14: Test fix transition
  echo '// test' > z.test.ts && git add z.test.ts
  echo '{"name": "test-app", "scripts": {"test": "echo FAIL && exit 1"}}' > package.json
  ADV impl >/dev/null 2>&1
  echo '{"name": "test-app", "scripts": {"test": "echo PASS && exit 0"}}' > package.json
  ADV qa >/dev/null 2>&1
  ADV fix >/dev/null 2>&1
  assert_eq "fix returns to impl" "tdd-impl" "$(ADV status 2>&1 | grep 'Phase:' | awk '{print $2}')"

  # N15: Test GREEN phase gate allows source edits
  cd "$TEST_DIR" || exit
  echo '{"tool_name": "Edit", "tool_input": {"file_path": "'"$TEST_DIR"'/index.ts"}}' | .claude/hooks/workflow-gate.sh >/dev/null 2>&1 && green_exit=0 || green_exit=$?
  assert_eq "GREEN allows source edits" "0" "$green_exit"

  # N15: Test GREEN phase gate allows test edits (logged)
  echo '{"tool_name": "Edit", "tool_input": {"file_path": "'"$TEST_DIR"'/z.test.ts"}}' | .claude/hooks/workflow-gate.sh >/dev/null 2>&1 && green_test_exit=0 || green_test_exit=$?
  assert_eq "GREEN allows test edits" "0" "$green_test_exit"

  # B10: Test override expiry
  ADV qa >/dev/null 2>&1
  ADV override "expiry test" >/dev/null 2>&1
  # Burn through 10 calls
  for _i in $(seq 1 10); do
    echo '{"tool_name": "Edit", "tool_input": {"file_path": "'"$TEST_DIR"'/index.ts"}}' | .claude/hooks/workflow-gate.sh >/dev/null 2>&1 || true
  done
  # 11th call should be blocked (override expired)
  echo '{"tool_name": "Edit", "tool_input": {"file_path": "'"$TEST_DIR"'/index.ts"}}' | .claude/hooks/workflow-gate.sh >/dev/null 2>&1 && override_exit=0 || override_exit=$?
  assert_eq "override expires after 10 calls" "2" "$override_exit"

  # N12: Test verify-phase rejected in Lite mode
  setup_test_project
  .claude/skills/workflow/setup >/dev/null 2>&1
  git checkout -q -b feature/test-lite-verify
  ADV init "lite verify test" >/dev/null 2>&1
  mkdir -p docs/specs && echo "# S" > docs/specs/lite-verify-test.md
  ADV review >/dev/null 2>&1
  ADV tests >/dev/null 2>&1
  echo '// t' > a.test.ts && git add a.test.ts
  ADV impl >/dev/null 2>&1
  echo '{"name": "test-app", "scripts": {"test": "echo PASS && exit 0"}}' > package.json
  ADV qa >/dev/null 2>&1
  out="$(ADV verify-phase 2>&1)" && true
  assert_contains "verify-phase rejected in Lite" "Full mode" "$out"
}

# ---------------------------------------------------------------------------
# Run all tests
# ---------------------------------------------------------------------------

trap cleanup EXIT

echo "Correctless Test Suite"
echo "======================"

test_setup
test_state_machine
test_gate
test_utilities
test_full_mode
test_additional_coverage

echo ""
echo "======================"
echo "Results: $PASS passed, $FAIL failed"
echo ""

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
