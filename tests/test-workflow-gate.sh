#!/usr/bin/env bash
# Correctless — Workflow Gate PreToolUse Hook Tests
# Tests phase enforcement logic in hooks/workflow-gate.sh
# Covers: spec, review, tdd-tests (RED), tdd-impl (GREEN), tdd-qa,
#         done/verified/documented, no-state-file, protected files, overrides
# Run from repo root: bash tests/test-workflow-gate.sh

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATE_HOOK="$REPO_DIR/hooks/workflow-gate.sh"
PASS=0
FAIL=0

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

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

# Run the gate hook with a tool_name and file_path, capture exit code and stderr.
# Output format: "EXIT_CODE:STDERR_OUTPUT"
run_gate() {
  local tool_name="$1" file_path="$2"
  local exit_code stderr_output
  stderr_output="$(echo "{\"tool_name\": \"$tool_name\", \"tool_input\": {\"file_path\": \"$file_path\"}}" \
    | bash "$GATE_HOOK" 2>&1 >/dev/null)" && exit_code=0 || exit_code=$?
  echo "${exit_code}:${stderr_output}"
}

# Run the gate hook with a Write tool and content (for STUB:TDD checks on new files).
run_gate_write() {
  local file_path="$1" content="$2"
  local exit_code stderr_output
  stderr_output="$(printf '{"tool_name": "Write", "tool_input": {"file_path": "%s", "content": "%s"}}' "$file_path" "$content" \
    | bash "$GATE_HOOK" 2>&1 >/dev/null)" && exit_code=0 || exit_code=$?
  echo "${exit_code}:${stderr_output}"
}

# Run the gate hook with an Edit tool and new_string (for STUB:TDD checks on existing files).
run_gate_edit() {
  local file_path="$1" new_string="$2"
  local exit_code stderr_output
  stderr_output="$(printf '{"tool_name": "Edit", "tool_input": {"file_path": "%s", "old_string": "placeholder", "new_string": "%s"}}' "$file_path" "$new_string" \
    | bash "$GATE_HOOK" 2>&1 >/dev/null)" && exit_code=0 || exit_code=$?
  echo "${exit_code}:${stderr_output}"
}

# Run the gate hook with a Bash command.
run_gate_bash() {
  local command="$1"
  local exit_code stderr_output
  # Use jq to safely encode the command string to avoid JSON injection
  local json_input
  json_input="$(jq -nc --arg cmd "$command" '{"tool_name": "Bash", "tool_input": {"command": $cmd}}')"
  stderr_output="$(echo "$json_input" \
    | bash "$GATE_HOOK" 2>&1 >/dev/null)" && exit_code=0 || exit_code=$?
  echo "${exit_code}:${stderr_output}"
}

# Run the gate hook with raw JSON input (for custom payloads).
run_gate_raw() {
  local json_input="$1"
  local exit_code stderr_output
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

# ---------------------------------------------------------------------------
# Test environment setup
# ---------------------------------------------------------------------------

TEST_DIR="/tmp/correctless-wfgate-test-$$"
BRANCH_NAME="feature/test-workflow-gate"

setup_test_env() {
  rm -rf "$TEST_DIR"
  mkdir -p "$TEST_DIR"
  cd "$TEST_DIR" || exit 1

  # Initialize a git repo with a feature branch
  git init -q
  git branch -M main
  echo "init" > README.md
  git add -A && git commit -q -m "init"
  git checkout -q -b "$BRANCH_NAME"

  # Copy lib.sh so the hook can source it
  mkdir -p .correctless/scripts
  cp "$REPO_DIR/scripts/lib.sh" .correctless/scripts/lib.sh

  # Create workflow config with test/source patterns
  mkdir -p .correctless/config
  cat > .correctless/config/workflow-config.json <<'WCEOF'
{
  "patterns": {
    "test_file": "*.test.ts|*.spec.ts",
    "source_file": "*.ts|*.js"
  },
  "workflow": {
    "fail_closed_when_no_state": false
  }
}
WCEOF

  # Create artifacts directory
  mkdir -p .correctless/artifacts

  # Compute the branch slug using lib.sh
  source .correctless/scripts/lib.sh
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

remove_state_file() {
  rm -f "$TEST_DIR/$STATE_FILE"
}

cleanup() {
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Test: spec phase — source and test blocked, config and read allowed
# ---------------------------------------------------------------------------

test_spec_phase() {
  echo ""
  echo "=== Spec phase: source and test blocked, config and read allowed ==="

  setup_test_env
  set_phase "spec"

  local result

  # Edit a source file (.ts) -> BLOCKED
  result="$(run_gate "Edit" "src/app.ts")"
  assert_eq "spec: Edit source file blocked" "2" "$(extract_exit "$result")"
  assert_contains "spec: block message mentions spec phase" "spec phase" "$(extract_stderr "$result")"

  # Edit a test file (.test.ts) -> BLOCKED
  result="$(run_gate "Edit" "src/app.test.ts")"
  assert_eq "spec: Edit test file blocked" "2" "$(extract_exit "$result")"

  # Edit a config file (.json, not workflow-config) -> ALLOWED
  result="$(run_gate "Edit" "tsconfig.json")"
  assert_eq "spec: Edit config file allowed" "0" "$(extract_exit "$result")"

  # Read tool -> ALLOWED (not a write tool)
  result="$(run_gate "Read" "src/app.ts")"
  assert_eq "spec: Read tool allowed" "0" "$(extract_exit "$result")"

  # Grep tool -> ALLOWED
  result="$(run_gate "Grep" "src/app.ts")"
  assert_eq "spec: Grep tool allowed" "0" "$(extract_exit "$result")"
}

# ---------------------------------------------------------------------------
# Test: review phase — same as spec
# ---------------------------------------------------------------------------

test_review_phase() {
  echo ""
  echo "=== Review phase: source and test blocked ==="

  setup_test_env
  set_phase "review"

  local result

  # Edit a source file -> BLOCKED
  result="$(run_gate "Edit" "src/handler.ts")"
  assert_eq "review: Edit source file blocked" "2" "$(extract_exit "$result")"

  # Edit a test file -> BLOCKED
  result="$(run_gate "Edit" "src/handler.spec.ts")"
  assert_eq "review: Edit test file blocked" "2" "$(extract_exit "$result")"

  # Edit a markdown file -> ALLOWED (not source or test)
  result="$(run_gate "Edit" "docs/guide.md")"
  assert_eq "review: Edit markdown file allowed" "0" "$(extract_exit "$result")"
}

# ---------------------------------------------------------------------------
# Test: review-spec phase — same blocking as spec/review
# ---------------------------------------------------------------------------

test_review_spec_phase() {
  echo ""
  echo "=== Review-spec phase: source and test blocked ==="

  setup_test_env
  set_phase "review-spec"

  local result

  # Edit a source file -> BLOCKED
  result="$(run_gate "Edit" "lib/utils.js")"
  assert_eq "review-spec: Edit source file blocked" "2" "$(extract_exit "$result")"

  # Write a test file -> BLOCKED
  result="$(run_gate "Write" "lib/utils.test.ts")"
  assert_eq "review-spec: Write test file blocked" "2" "$(extract_exit "$result")"
}

# ---------------------------------------------------------------------------
# Test: model phase — same blocking as spec/review
# ---------------------------------------------------------------------------

test_model_phase() {
  echo ""
  echo "=== Model phase: source and test blocked ==="

  setup_test_env
  set_phase "model"

  local result

  result="$(run_gate "Edit" "src/model.ts")"
  assert_eq "model: Edit source file blocked" "2" "$(extract_exit "$result")"

  result="$(run_gate "Write" "src/model.spec.ts")"
  assert_eq "model: Write test file blocked" "2" "$(extract_exit "$result")"
}

# ---------------------------------------------------------------------------
# Test: tdd-tests (RED) phase — test files allowed, source gated by STUB:TDD
# ---------------------------------------------------------------------------

test_tdd_tests_phase() {
  echo ""
  echo "=== TDD-tests (RED) phase: test allowed, source gated by STUB:TDD ==="

  setup_test_env
  set_phase "tdd-tests"

  local result

  # Edit a test file -> ALLOWED
  result="$(run_gate "Edit" "src/app.test.ts")"
  assert_eq "tdd-tests: Edit test file allowed" "0" "$(extract_exit "$result")"

  # Write a test file -> ALLOWED
  result="$(run_gate "Write" "src/new.spec.ts")"
  assert_eq "tdd-tests: Write test file allowed" "0" "$(extract_exit "$result")"

  # Edit a source file that does NOT exist and has no STUB:TDD -> BLOCKED
  result="$(run_gate_edit "src/feature.ts" "export function foo() { return 42; }")"
  assert_eq "tdd-tests: Edit new source file without STUB:TDD blocked" "2" "$(extract_exit "$result")"

  # Write a NEW source file with STUB:TDD in content -> ALLOWED
  result="$(run_gate_write "src/new.ts" "// STUB:TDD\\nexport function foo() {}")"
  assert_eq "tdd-tests: Write new source file with STUB:TDD allowed" "0" "$(extract_exit "$result")"

  # Edit an existing source file that already has STUB:TDD marker -> ALLOWED
  mkdir -p "$TEST_DIR/src"
  echo "// STUB:TDD" > "$TEST_DIR/src/existing.ts"
  result="$(run_gate "Edit" "src/existing.ts")"
  assert_eq "tdd-tests: Edit existing source file with STUB:TDD allowed" "0" "$(extract_exit "$result")"

  # Edit an existing source file WITHOUT STUB:TDD marker -> BLOCKED
  echo "export const x = 1;" > "$TEST_DIR/src/real-impl.ts"
  result="$(run_gate_edit "src/real-impl.ts" "export const x = 2;")"
  assert_eq "tdd-tests: Edit existing source file without STUB:TDD blocked" "2" "$(extract_exit "$result")"
  assert_contains "tdd-tests: block message mentions RED phase" "RED phase" "$(extract_stderr "$result")"

  # Edit an existing source file WITHOUT STUB:TDD but the edit ADDS it -> ALLOWED
  echo "export const y = 1;" > "$TEST_DIR/src/adding-stub.ts"
  result="$(run_gate_edit "src/adding-stub.ts" "// STUB:TDD\\nexport const y = 1;")"
  assert_eq "tdd-tests: Edit adding STUB:TDD to existing file allowed" "0" "$(extract_exit "$result")"
}

# ---------------------------------------------------------------------------
# Test: tdd-impl (GREEN) phase — source allowed, test edits logged
# ---------------------------------------------------------------------------

test_tdd_impl_phase() {
  echo ""
  echo "=== TDD-impl (GREEN) phase: source allowed, test edits logged ==="

  setup_test_env
  set_phase "tdd-impl"

  local result

  # Edit source file -> ALLOWED
  result="$(run_gate "Edit" "src/service.ts")"
  assert_eq "tdd-impl: Edit source file allowed" "0" "$(extract_exit "$result")"

  # Edit a .js file -> ALLOWED
  result="$(run_gate "Edit" "lib/helper.js")"
  assert_eq "tdd-impl: Edit .js file allowed" "0" "$(extract_exit "$result")"

  # Edit test file -> ALLOWED but LOGGED
  local log_file="$TEST_DIR/.correctless/artifacts/tdd-test-edits.log"
  rm -f "$log_file"
  result="$(run_gate "Edit" "src/service.test.ts")"
  assert_eq "tdd-impl: Edit test file allowed" "0" "$(extract_exit "$result")"
  assert_file_exists "tdd-impl: test edit log created" "$log_file"

  # Edit a config file -> ALLOWED
  result="$(run_gate "Edit" "tsconfig.json")"
  assert_eq "tdd-impl: Edit config file allowed" "0" "$(extract_exit "$result")"
}

# ---------------------------------------------------------------------------
# Test: tdd-qa phase — source and test blocked
# ---------------------------------------------------------------------------

test_tdd_qa_phase() {
  echo ""
  echo "=== TDD-qa phase: source and test blocked ==="

  setup_test_env
  set_phase "tdd-qa"

  local result

  # Edit source file -> BLOCKED
  result="$(run_gate "Edit" "src/main.ts")"
  assert_eq "tdd-qa: Edit source file blocked" "2" "$(extract_exit "$result")"
  assert_contains "tdd-qa: block message mentions QA phase" "QA phase" "$(extract_stderr "$result")"

  # Edit test file -> BLOCKED
  result="$(run_gate "Edit" "src/main.test.ts")"
  assert_eq "tdd-qa: Edit test file blocked" "2" "$(extract_exit "$result")"

  # Edit a config file -> ALLOWED
  result="$(run_gate "Edit" "package.json")"
  assert_eq "tdd-qa: Edit config file allowed" "0" "$(extract_exit "$result")"
}

# ---------------------------------------------------------------------------
# Test: tdd-verify phase — source and test blocked
# ---------------------------------------------------------------------------

test_tdd_verify_phase() {
  echo ""
  echo "=== TDD-verify phase: source and test blocked ==="

  setup_test_env
  set_phase "tdd-verify"

  local result

  result="$(run_gate "Edit" "src/index.ts")"
  assert_eq "tdd-verify: Edit source file blocked" "2" "$(extract_exit "$result")"

  result="$(run_gate "Edit" "src/index.spec.ts")"
  assert_eq "tdd-verify: Edit test file blocked" "2" "$(extract_exit "$result")"
}

# ---------------------------------------------------------------------------
# Test: done/verified/documented phases — everything allowed
# ---------------------------------------------------------------------------

test_post_tdd_phases() {
  echo ""
  echo "=== Done/verified/documented phases: everything allowed ==="

  setup_test_env

  local result

  for phase in "done" verified documented; do
    set_phase "$phase"

    result="$(run_gate "Edit" "src/app.ts")"
    assert_eq "$phase: Edit source file allowed" "0" "$(extract_exit "$result")"

    result="$(run_gate "Edit" "src/app.test.ts")"
    assert_eq "$phase: Edit test file allowed" "0" "$(extract_exit "$result")"

    result="$(run_gate "Write" "src/new-feature.js")"
    assert_eq "$phase: Write source file allowed" "0" "$(extract_exit "$result")"
  done
}

# ---------------------------------------------------------------------------
# Test: No state file — default allow (fail_closed = false)
# ---------------------------------------------------------------------------

test_no_state_file_open() {
  echo ""
  echo "=== No state file (fail_closed=false): everything allowed ==="

  setup_test_env
  remove_state_file

  local result

  result="$(run_gate "Edit" "src/anything.ts")"
  assert_eq "no-state: Edit source file allowed" "0" "$(extract_exit "$result")"

  result="$(run_gate "Edit" "src/anything.test.ts")"
  assert_eq "no-state: Edit test file allowed" "0" "$(extract_exit "$result")"

  result="$(run_gate "Write" "src/new.js")"
  assert_eq "no-state: Write file allowed" "0" "$(extract_exit "$result")"
}

# ---------------------------------------------------------------------------
# Test: No state file with fail_closed = true — source blocked
# ---------------------------------------------------------------------------

test_no_state_file_closed() {
  echo ""
  echo "=== No state file (fail_closed=true): source blocked ==="

  setup_test_env
  remove_state_file

  # Reconfigure with fail_closed = true
  cat > "$TEST_DIR/.correctless/config/workflow-config.json" <<'WCEOF'
{
  "patterns": {
    "test_file": "*.test.ts|*.spec.ts",
    "source_file": "*.ts|*.js"
  },
  "workflow": {
    "fail_closed_when_no_state": true
  }
}
WCEOF

  local result

  # Edit a source file -> BLOCKED
  result="$(run_gate "Edit" "src/app.ts")"
  assert_eq "fail-closed: Edit source file blocked" "2" "$(extract_exit "$result")"
  assert_contains "fail-closed: block message mentions fail-closed" "fail-closed" "$(extract_stderr "$result")"

  # Edit a non-source file -> ALLOWED (fail_closed only blocks source patterns)
  result="$(run_gate "Edit" "README.md")"
  assert_eq "fail-closed: Edit non-source file allowed" "0" "$(extract_exit "$result")"
}

# ---------------------------------------------------------------------------
# Test: Protected files — state and config files blocked regardless of phase
# ---------------------------------------------------------------------------

test_protected_files() {
  echo ""
  echo "=== Protected files: state and config blocked during active workflow ==="

  setup_test_env
  set_phase "tdd-impl"

  local result

  # Edit workflow-state-*.json -> BLOCKED regardless of phase
  result="$(run_gate "Edit" ".correctless/artifacts/workflow-state-some-branch.json")"
  assert_eq "protected: Edit workflow-state file blocked" "2" "$(extract_exit "$result")"
  assert_contains "protected: block message mentions state files" "workflow state files" "$(extract_stderr "$result")"

  # Edit workflow-config.json -> ALLOWED during tdd-impl (test registration)
  result="$(run_gate "Edit" ".correctless/config/workflow-config.json")"
  assert_eq "protected: Edit workflow-config allowed in tdd-impl" "0" "$(extract_exit "$result")"

  # Edit workflow-config.json -> BLOCKED during other phases (e.g., spec)
  set_phase "spec"
  result="$(run_gate "Edit" ".correctless/config/workflow-config.json")"
  assert_eq "protected: Edit workflow-config blocked in spec" "2" "$(extract_exit "$result")"
  assert_contains "protected: block message mentions workflow-config" "workflow-config.json" "$(extract_stderr "$result")"

  # Protected files blocked even in spec phase
  result="$(run_gate "Edit" ".correctless/artifacts/workflow-state-test.json")"
  assert_eq "protected: workflow-state blocked in spec phase" "2" "$(extract_exit "$result")"

  # Done phase exits early (line 207) before the protected file check (line 266).
  # This is expected — done/verified/documented allow everything via early return.
  set_phase "done"
  result="$(run_gate "Edit" ".correctless/artifacts/workflow-state-test.json")"
  assert_eq "protected: done phase allows all (early exit)" "0" "$(extract_exit "$result")"
}

# ---------------------------------------------------------------------------
# Test: Override — allows blocked operations, decrements remaining
# ---------------------------------------------------------------------------

test_override() {
  echo ""
  echo "=== Override: bypasses phase rules, decrements remaining ==="

  setup_test_env
  set_phase_with_override "spec" 2

  local result

  # First call with override active and remaining=2 -> ALLOWED
  result="$(run_gate "Edit" "src/app.ts")"
  assert_eq "override: first call allowed" "0" "$(extract_exit "$result")"

  # Check remaining was decremented to 1
  local remaining
  remaining="$(jq -r '.override.remaining_calls' "$TEST_DIR/$STATE_FILE")"
  assert_eq "override: remaining decremented to 1" "1" "$remaining"

  # Second call -> ALLOWED (remaining was 1)
  result="$(run_gate "Edit" "src/app.ts")"
  assert_eq "override: second call allowed" "0" "$(extract_exit "$result")"

  # Check override is now deactivated
  local active
  active="$(jq -r '.override.active' "$TEST_DIR/$STATE_FILE")"
  assert_eq "override: deactivated after exhaustion" "false" "$active"

  remaining="$(jq -r '.override.remaining_calls' "$TEST_DIR/$STATE_FILE")"
  assert_eq "override: remaining is 0" "0" "$remaining"

  # Third call -> BLOCKED (override exhausted, back to spec phase rules)
  result="$(run_gate "Edit" "src/app.ts")"
  assert_eq "override: third call blocked (exhausted)" "2" "$(extract_exit "$result")"
}

# ---------------------------------------------------------------------------
# Test: Override with remaining=0 — normal phase rules apply
# ---------------------------------------------------------------------------

test_override_exhausted() {
  echo ""
  echo "=== Override with remaining=0: normal phase rules apply ==="

  setup_test_env
  set_phase_with_override "spec" 0

  local result

  # Override active but remaining=0 -> should fall through to phase rules
  result="$(run_gate "Edit" "src/app.ts")"
  assert_eq "override-exhausted: source edit blocked by spec phase" "2" "$(extract_exit "$result")"
}

# ---------------------------------------------------------------------------
# Test: Bash tool with write patterns — detected and gated
# ---------------------------------------------------------------------------

test_bash_write_detection() {
  echo ""
  echo "=== Bash tool: write patterns detected and gated ==="

  setup_test_env
  set_phase "spec"

  local result

  # Bash with cp (write command) targeting a source file -> BLOCKED
  result="$(run_gate_bash "cp src/old.ts src/new.ts")"
  assert_eq "bash: cp source files blocked in spec" "2" "$(extract_exit "$result")"

  # Bash with redirect -> BLOCKED
  result="$(run_gate_bash "echo hello > src/file.ts")"
  assert_eq "bash: redirect to source file blocked in spec" "2" "$(extract_exit "$result")"

  # Bash read command (no write pattern) -> ALLOWED
  result="$(run_gate_bash "cat src/app.ts")"
  assert_eq "bash: cat (read) allowed in spec" "0" "$(extract_exit "$result")"

  # Bash with ls -> ALLOWED (not a write pattern)
  result="$(run_gate_bash "ls -la src/")"
  assert_eq "bash: ls allowed in spec" "0" "$(extract_exit "$result")"

  # Bash with git command -> ALLOWED (not a write pattern)
  result="$(run_gate_bash "git status")"
  assert_eq "bash: git status allowed in spec" "0" "$(extract_exit "$result")"
}

# ---------------------------------------------------------------------------
# Test: Non-write tools always allowed
# ---------------------------------------------------------------------------

test_non_write_tools() {
  echo ""
  echo "=== Non-write tools: always allowed regardless of phase ==="

  setup_test_env
  set_phase "spec"

  local result

  result="$(run_gate "Read" "src/app.ts")"
  assert_eq "non-write: Read allowed in spec" "0" "$(extract_exit "$result")"

  result="$(run_gate "Grep" "src/app.ts")"
  assert_eq "non-write: Grep allowed in spec" "0" "$(extract_exit "$result")"

  result="$(run_gate "Glob" "src/")"
  assert_eq "non-write: Glob allowed in spec" "0" "$(extract_exit "$result")"

  result="$(run_gate "ListDir" "src/")"
  assert_eq "non-write: ListDir allowed in spec" "0" "$(extract_exit "$result")"
}

# ---------------------------------------------------------------------------
# Test: Invalid or corrupt phase — blocked with error message
# ---------------------------------------------------------------------------

test_invalid_phase() {
  echo ""
  echo "=== Invalid phase: blocked with error message ==="

  setup_test_env

  # Write a state file with an unknown phase
  cat > "$TEST_DIR/$STATE_FILE" <<'EOF'
{
  "phase": "banana",
  "override": { "active": false, "remaining_calls": 0 }
}
EOF

  local result
  result="$(run_gate "Edit" "src/app.ts")"
  assert_eq "invalid-phase: edit blocked" "2" "$(extract_exit "$result")"
  assert_contains "invalid-phase: error mentions invalid phase" "Invalid or corrupted" "$(extract_stderr "$result")"
}

# ---------------------------------------------------------------------------
# Test: Corrupt state file — blocked (nonzero exit)
# ---------------------------------------------------------------------------

test_corrupt_state_file() {
  echo ""
  echo "=== Corrupt state file: edit blocked ==="

  setup_test_env

  # Write invalid JSON — jq silently produces empty output (stderr redirected),
  # eval "" succeeds, so the || handler does NOT fire. PHASE stays unset, and
  # set -u (nounset) aborts the script with exit 1 before any case branch runs.
  # The operation is still blocked (nonzero exit), just not with the intended
  # exit 2 code. Verify the gate does NOT allow the operation.
  echo "not json at all" > "$TEST_DIR/$STATE_FILE"

  local result
  result="$(run_gate "Edit" "src/app.ts")"
  local exit_code
  exit_code="$(extract_exit "$result")"
  # The operation must not be allowed (exit 0). The hook exits 1 due to nounset.
  if [ "$exit_code" != "0" ]; then
    echo "  PASS: corrupt-state: edit not allowed (exit $exit_code)"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: corrupt-state: edit was allowed (expected nonzero exit, got 0)"
    FAIL=$((FAIL + 1))
  fi
}

# ---------------------------------------------------------------------------
# Test: audit phase — source edits allowed
# ---------------------------------------------------------------------------

test_audit_phase() {
  echo ""
  echo "=== Audit phase: source edits allowed ==="

  setup_test_env
  set_phase "audit"

  local result

  result="$(run_gate "Edit" "src/fix.ts")"
  assert_eq "audit: Edit source file allowed" "0" "$(extract_exit "$result")"

  result="$(run_gate "Edit" "src/fix.test.ts")"
  assert_eq "audit: Edit test file allowed" "0" "$(extract_exit "$result")"
}

# ---------------------------------------------------------------------------
# Test: File classification — other files always pass through
# ---------------------------------------------------------------------------

test_other_files_allowed() {
  echo ""
  echo "=== Other files: non-source non-test files allowed in all phases ==="

  setup_test_env

  local result

  for phase in spec review tdd-tests tdd-qa tdd-verify; do
    set_phase "$phase"

    # Markdown files are not in the test/source patterns
    result="$(run_gate "Edit" "docs/README.md")"
    assert_eq "$phase: Edit .md file allowed" "0" "$(extract_exit "$result")"

    # YAML files not in patterns
    result="$(run_gate "Edit" ".github/workflows/ci.yml")"
    assert_eq "$phase: Edit .yml file allowed" "0" "$(extract_exit "$result")"
  done
}

# ---------------------------------------------------------------------------
# Test: Empty patterns — fail closed
# ---------------------------------------------------------------------------

test_empty_patterns_blocked() {
  echo ""
  echo "=== Empty patterns: blocked (prevents classification bypass) ==="

  setup_test_env
  set_phase "tdd-impl"

  # Overwrite config with empty patterns
  cat > "$TEST_DIR/.correctless/config/workflow-config.json" <<'WCEOF'
{
  "patterns": {
    "test_file": "",
    "source_file": ""
  }
}
WCEOF

  local result
  result="$(run_gate "Edit" "src/app.ts")"
  assert_eq "empty-patterns: edit blocked" "2" "$(extract_exit "$result")"
  assert_contains "empty-patterns: mentions patterns empty" "patterns are empty" "$(extract_stderr "$result")"
}

# ---------------------------------------------------------------------------
# Run all tests
# ---------------------------------------------------------------------------

test_spec_phase
test_review_phase
test_review_spec_phase
test_model_phase
test_tdd_tests_phase
test_tdd_impl_phase
test_tdd_qa_phase
test_tdd_verify_phase
test_post_tdd_phases
test_no_state_file_open
test_no_state_file_closed
test_protected_files
test_override
test_override_exhausted
test_bash_write_detection
test_non_write_tools
test_invalid_phase
test_corrupt_state_file
test_audit_phase
test_other_files_allowed
test_empty_patterns_blocked

# ---------------------------------------------------------------------------
# INV-013a: workflow-gate.sh consumes the same extended _has_write_pattern
# from .correctless/scripts/lib.sh. Interpreter-chain commands must be treated
# as writes in the RED (tdd-tests) phase. This is the regression test that
# catches a silent local redefinition of _has_write_pattern in workflow-gate.sh.
# ---------------------------------------------------------------------------

test_inv013a_workflow_gate_consumes_extended_pattern() {
  echo ""
  echo "=== INV-013a: workflow-gate consumes extended _has_write_pattern ==="

  setup_test_env
  # 'spec' phase blocks all Bash writes to source files — isolates the
  # extended-pattern question from RED's separate Bash-on-new-source gap.
  set_phase "spec"

  local result
  # Each fixture surfaces the target as a clean bash token; quoted-string
  # forms are covered by the guard's INV-013 tests, not here.
  for cmd in \
    "bash -c 'echo x > src/feature.ts'" \
    "perl -i -pe 's/x/y/' src/feature.ts" \
    "/usr/bin/env perl -i -pe 's/x/y/' src/feature.ts" \
    "python3 src/feature.ts" \
    "ruby src/feature.ts"
  do
    result="$(run_gate_bash "$cmd")"
    local exit_code
    exit_code="$(extract_exit "$result")"
    assert_eq "INV-013a: '$cmd' classified as write in spec phase" "2" "$exit_code"
  done
}

# ---------------------------------------------------------------------------
# INV-013a [structural]: _has_write_pattern is the single shared source —
# no local redefinition in workflow-gate.sh
# ---------------------------------------------------------------------------
test_inv013a_no_local_redefinition() {
  echo ""
  echo "=== INV-013a [structural]: no local _has_write_pattern in workflow-gate.sh ==="

  local gate="$REPO_DIR/hooks/workflow-gate.sh"
  local found="absent"
  if grep -nE '^[[:space:]]*_has_write_pattern[[:space:]]*\(\)' "$gate" | grep -v '^[[:space:]]*#' >/dev/null; then
    found="present"
  fi
  assert_eq "INV-013a-shared: no local _has_write_pattern() in workflow-gate.sh" "absent" "$found"
}

test_inv013a_workflow_gate_consumes_extended_pattern
test_inv013a_no_local_redefinition

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo ""
echo "=== Summary ==="
echo "PASS: $PASS"
echo "FAIL: $FAIL"
TOTAL=$((PASS + FAIL))
echo "TOTAL: $TOTAL"

if [ "$FAIL" -gt 0 ]; then
  echo ""
  echo "RESULT: FAIL ($FAIL failures)"
  exit 1
else
  echo ""
  echo "RESULT: PASS (all $PASS tests passed)"
  exit 0
fi
