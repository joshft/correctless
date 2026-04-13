#!/usr/bin/env bash
# Correctless — Token Tracking PostToolUse Hook Tests
# Tests R-001 through R-007, R-009, R-010, R-011 from the token-tracking spec.
# Run from repo root: bash tests/test-token-tracking.sh

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$REPO_DIR/hooks/token-tracking.sh"
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
  if echo "$actual" | grep -qF "$unexpected"; then
    echo "  FAIL: $desc (output should NOT contain '$unexpected')"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  fi
}

assert_match() {
  local desc="$1" pattern="$2" actual="$3"
  if printf '%s\n' "$actual" | grep -qE -- "$pattern"; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (expected output to match pattern '$pattern', got '$actual')"
    FAIL=$((FAIL + 1))
  fi
}

assert_not_match() {
  local desc="$1" pattern="$2" actual="$3"
  if printf '%s\n' "$actual" | grep -qE -- "$pattern"; then
    echo "  FAIL: $desc (expected output NOT to match '$pattern', got '$actual')"
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
    echo "  FAIL: $desc (file '$path' should not exist but does)"
    FAIL=$((FAIL + 1))
  fi
}

# ============================================================================
# Test environment setup
# ============================================================================

TEST_DIR="/tmp/correctless-test-token-tracking-$$"
BRANCH_NAME="feature/test-token-tracking"

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
  cp "$LIB_SH" .correctless/scripts/lib.sh

  # Copy the hook under test
  mkdir -p hooks
  cp "$HOOK" hooks/token-tracking.sh
  chmod +x hooks/token-tracking.sh

  # Create artifacts directory
  mkdir -p .correctless/artifacts

  # Compute the branch slug using lib.sh
  source .correctless/scripts/lib.sh
  SLUG="$(branch_slug)"
  TOKEN_LOG=".correctless/artifacts/token-log-${SLUG}.jsonl"
  STATE_FILE=".correctless/artifacts/workflow-state-${SLUG}.json"
}

cleanup() {
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

# Helper: build Agent tool stdin JSON with all fields
build_agent_stdin() {
  local input_tokens="${1:-100}"
  local output_tokens="${2:-50}"
  local total_cost="${3:-0.005}"
  local duration="${4:-1200}"
  local description="${5:-run tests}"
  local subagent_type="${6:-qa-expert}"

  cat <<EOF
{
  "tool_name": "Agent",
  "tool_input": {
    "description": "$description",
    "subagent_type": "$subagent_type"
  },
  "tool_response": {
    "usage": {
      "input_tokens": $input_tokens,
      "output_tokens": $output_tokens
    },
    "total_cost_usd": $total_cost,
    "duration_ms": $duration,
    "result": "This is the subagent result with shell metacharacters: \$(echo pwned) && rm -rf /"
  }
}
EOF
}

# Helper: run the hook with stdin, capture exit code
run_hook() {
  local stdin_data="$1"
  local exit_code
  echo "$stdin_data" | bash hooks/token-tracking.sh >/dev/null 2>/dev/null && exit_code=0 || exit_code=$?
  echo "$exit_code"
}

echo "Correctless Token Tracking PostToolUse Hook Tests"
echo "=================================================="

# ============================================================================
# R-001 [unit]: hook fires only on Agent tool completions
# ============================================================================

test_r001_agent_only() {
  echo ""
  echo "=== R-001: hook fires only on Agent tool completions ==="

  setup_test_env

  # Feed non-Agent tool names — should exit 0 and NOT create any log file
  for tool in Read Edit Write Bash Grep Glob MultiEdit; do
    local stdin_data
    stdin_data="$(cat <<EOF
{
  "tool_name": "$tool",
  "tool_input": {"file_path": "test.txt"},
  "tool_response": {"usage": {"input_tokens": 100, "output_tokens": 50}}
}
EOF
)"
    local exit_code
    exit_code="$(run_hook "$stdin_data")"
    assert_eq "R-001a: exit 0 for $tool tool" "0" "$exit_code"
  done

  # No log file should have been created for non-Agent tools
  assert_file_not_exists "R-001b: no log file created for non-Agent tools" "$TEST_DIR/$TOKEN_LOG"

  # Feed Agent tool — should process and create log file
  local agent_stdin
  agent_stdin="$(build_agent_stdin)"
  local exit_code
  exit_code="$(run_hook "$agent_stdin")"
  assert_eq "R-001c: exit 0 for Agent tool" "0" "$exit_code"
  assert_file_exists "R-001d: log file created for Agent tool" "$TEST_DIR/$TOKEN_LOG"
}

# ============================================================================
# R-002 [unit]: hook extracts token fields from tool_response
# ============================================================================

test_r002_token_extraction() {
  echo ""
  echo "=== R-002: hook extracts all token fields from tool_response ==="

  setup_test_env

  # Feed Agent tool with known token values
  local agent_stdin
  agent_stdin="$(build_agent_stdin 500 200 0.0123 3400)"
  run_hook "$agent_stdin" >/dev/null

  # Parse the log entry
  local log_entry
  log_entry="$(head -1 "$TEST_DIR/$TOKEN_LOG" 2>/dev/null || echo "")"

  local input_tokens output_tokens total_cost duration
  input_tokens="$(echo "$log_entry" | jq -r '.input_tokens' 2>/dev/null || echo "")"
  output_tokens="$(echo "$log_entry" | jq -r '.output_tokens' 2>/dev/null || echo "")"
  total_cost="$(echo "$log_entry" | jq -r '.total_cost_usd' 2>/dev/null || echo "")"
  duration="$(echo "$log_entry" | jq -r '.duration_ms' 2>/dev/null || echo "")"

  assert_eq "R-002a: input_tokens extracted" "500" "$input_tokens"
  assert_eq "R-002b: output_tokens extracted" "200" "$output_tokens"
  assert_eq "R-002c: total_cost_usd extracted" "0.0123" "$total_cost"
  assert_eq "R-002d: duration_ms extracted" "3400" "$duration"

  # Test missing fields default to 0
  rm -f "$TEST_DIR/$TOKEN_LOG"
  local minimal_stdin
  minimal_stdin='{"tool_name":"Agent","tool_input":{"description":"test"},"tool_response":{}}'
  run_hook "$minimal_stdin" >/dev/null

  log_entry="$(head -1 "$TEST_DIR/$TOKEN_LOG" 2>/dev/null || echo "")"
  input_tokens="$(echo "$log_entry" | jq -r '.input_tokens' 2>/dev/null || echo "")"
  output_tokens="$(echo "$log_entry" | jq -r '.output_tokens' 2>/dev/null || echo "")"
  total_cost="$(echo "$log_entry" | jq -r '.total_cost_usd' 2>/dev/null || echo "")"
  duration="$(echo "$log_entry" | jq -r '.duration_ms' 2>/dev/null || echo "")"

  assert_eq "R-002e: missing input_tokens defaults to 0" "0" "$input_tokens"
  assert_eq "R-002f: missing output_tokens defaults to 0" "0" "$output_tokens"
  assert_eq "R-002g: missing total_cost_usd defaults to 0" "0" "$total_cost"
  assert_eq "R-002h: missing duration_ms defaults to 0" "0" "$duration"
}

# ============================================================================
# R-003 [unit]: hook extracts subagent metadata from tool_input
# ============================================================================

test_r003_subagent_metadata() {
  echo ""
  echo "=== R-003: hook extracts subagent metadata from tool_input ==="

  setup_test_env

  # Feed Agent tool with known description and subagent_type
  local agent_stdin
  agent_stdin="$(build_agent_stdin 100 50 0.005 1200 "analyze code quality" "qa-expert")"
  run_hook "$agent_stdin" >/dev/null

  local log_entry
  log_entry="$(head -1 "$TEST_DIR/$TOKEN_LOG" 2>/dev/null || echo "")"

  local description agent_type
  description="$(echo "$log_entry" | jq -r '.agent_description' 2>/dev/null || echo "")"
  agent_type="$(echo "$log_entry" | jq -r '.agent_type' 2>/dev/null || echo "")"

  assert_eq "R-003a: agent_description extracted" "analyze code quality" "$description"
  assert_eq "R-003b: agent_type extracted" "qa-expert" "$agent_type"

  # Test missing fields default to empty string
  rm -f "$TEST_DIR/$TOKEN_LOG"
  local minimal_stdin
  minimal_stdin='{"tool_name":"Agent","tool_input":{},"tool_response":{"usage":{"input_tokens":10,"output_tokens":5}}}'
  run_hook "$minimal_stdin" >/dev/null

  if [ ! -f "$TEST_DIR/$TOKEN_LOG" ]; then
    echo "  FAIL: R-003c: missing description defaults to empty string (no log file created)"
    FAIL=$((FAIL + 1))
    echo "  FAIL: R-003d: missing subagent_type defaults to empty string (no log file created)"
    FAIL=$((FAIL + 1))
  else
    log_entry="$(head -1 "$TEST_DIR/$TOKEN_LOG")"
    description="$(echo "$log_entry" | jq -r '.agent_description' 2>/dev/null || echo "__MISSING__")"
    agent_type="$(echo "$log_entry" | jq -r '.agent_type' 2>/dev/null || echo "__MISSING__")"
    assert_eq "R-003c: missing description defaults to empty string" "" "$description"
    assert_eq "R-003d: missing subagent_type defaults to empty string" "" "$agent_type"
  fi
}

# ============================================================================
# R-004 [integration]: hook reads current workflow phase from state file
# ============================================================================

test_r004_workflow_phase() {
  echo ""
  echo "=== R-004: hook reads current workflow phase from state file ==="

  setup_test_env

  # Create a workflow state file with a known phase
  cat > "$TEST_DIR/$STATE_FILE" <<'EOF'
{
  "phase": "tdd-impl",
  "override": {"active": false, "remaining_calls": 0}
}
EOF

  local agent_stdin
  agent_stdin="$(build_agent_stdin)"
  run_hook "$agent_stdin" >/dev/null

  local log_entry phase
  log_entry="$(head -1 "$TEST_DIR/$TOKEN_LOG" 2>/dev/null || echo "")"
  phase="$(echo "$log_entry" | jq -r '.phase' 2>/dev/null || echo "")"

  assert_eq "R-004a: phase read from state file" "tdd-impl" "$phase"

  # Test with different phase
  rm -f "$TEST_DIR/$TOKEN_LOG"
  cat > "$TEST_DIR/$STATE_FILE" <<'EOF'
{
  "phase": "tdd-qa",
  "override": {"active": false, "remaining_calls": 0}
}
EOF

  run_hook "$agent_stdin" >/dev/null
  log_entry="$(head -1 "$TEST_DIR/$TOKEN_LOG" 2>/dev/null || echo "")"
  phase="$(echo "$log_entry" | jq -r '.phase' 2>/dev/null || echo "")"
  assert_eq "R-004b: phase updated to tdd-qa" "tdd-qa" "$phase"

  # Test missing state file — phase defaults to "none"
  rm -f "$TEST_DIR/$TOKEN_LOG"
  rm -f "$TEST_DIR/$STATE_FILE"
  run_hook "$agent_stdin" >/dev/null
  log_entry="$(head -1 "$TEST_DIR/$TOKEN_LOG" 2>/dev/null || echo "")"
  phase="$(echo "$log_entry" | jq -r '.phase' 2>/dev/null || echo "")"
  assert_eq "R-004c: missing state file defaults phase to none" "none" "$phase"
}

# ============================================================================
# R-005 [unit]: hook appends a JSONL entry to the token log file
# ============================================================================

test_r005_jsonl_append() {
  echo ""
  echo "=== R-005: hook appends JSONL entries (one JSON per line) ==="

  setup_test_env

  local agent_stdin
  agent_stdin="$(build_agent_stdin)"

  # Run the hook twice
  run_hook "$agent_stdin" >/dev/null
  run_hook "$agent_stdin" >/dev/null

  # Check the log file has exactly 2 lines
  if [ ! -f "$TEST_DIR/$TOKEN_LOG" ]; then
    echo "  FAIL: R-005a: log file does not exist after 2 invocations"
    FAIL=$((FAIL + 1))
    echo "  FAIL: R-005b: line 1 is valid JSON (no log file)"
    FAIL=$((FAIL + 1))
    echo "  FAIL: R-005c: line 2 is valid JSON (no log file)"
    FAIL=$((FAIL + 1))
    echo "  FAIL: R-005d: log file has 3 lines after 3 invocations (no log file)"
    FAIL=$((FAIL + 1))
    echo "  FAIL: R-005e: entire file consumable by jq -s (no log file)"
    FAIL=$((FAIL + 1))
    return
  fi

  local line_count
  line_count="$(wc -l < "$TEST_DIR/$TOKEN_LOG" | tr -d ' ')"
  assert_eq "R-005a: log file has 2 lines after 2 invocations" "2" "$line_count"

  # Each line should be valid JSON
  local line1_valid line2_valid
  line1_valid="$(sed -n '1p' "$TEST_DIR/$TOKEN_LOG" | jq '.' >/dev/null 2>&1 && echo "yes" || echo "no")"
  line2_valid="$(sed -n '2p' "$TEST_DIR/$TOKEN_LOG" | jq '.' >/dev/null 2>&1 && echo "yes" || echo "no")"
  assert_eq "R-005b: line 1 is valid JSON" "yes" "$line1_valid"
  assert_eq "R-005c: line 2 is valid JSON" "yes" "$line2_valid"

  # Run a third time — should now have 3 lines (append, not overwrite)
  run_hook "$agent_stdin" >/dev/null
  line_count="$(wc -l < "$TEST_DIR/$TOKEN_LOG" | tr -d ' ')"
  assert_eq "R-005d: log file has 3 lines after 3 invocations" "3" "$line_count"

  # The entire file should be consumable by jq -s
  local slurp_valid
  slurp_valid="$(jq -s '.' < "$TEST_DIR/$TOKEN_LOG" >/dev/null 2>&1 && echo "yes" || echo "no")"
  assert_eq "R-005e: entire file consumable by jq -s" "yes" "$slurp_valid"
}

# ============================================================================
# R-006 [unit]: log entry contains all required fields
# ============================================================================

test_r006_required_fields() {
  echo ""
  echo "=== R-006: log entry contains all required fields ==="

  setup_test_env

  # Create state file for phase AND task (used to verify feature field)
  cat > "$TEST_DIR/$STATE_FILE" <<'EOF'
{
  "phase": "spec",
  "task": "token-tracking",
  "override": {"active": false, "remaining_calls": 0}
}
EOF

  local agent_stdin
  agent_stdin="$(build_agent_stdin 300 150 0.009 2500 "write tests" "test-writer")"
  run_hook "$agent_stdin" >/dev/null

  local log_entry
  log_entry="$(head -1 "$TEST_DIR/$TOKEN_LOG" 2>/dev/null || echo "")"

  # Check every required field exists and is non-null
  local required_fields=(
    "timestamp"
    "branch"
    "phase"
    "feature"
    "agent_description"
    "agent_type"
    "input_tokens"
    "output_tokens"
    "total_tokens"
    "total_cost_usd"
    "duration_ms"
  )

  if [ -z "$log_entry" ]; then
    # All R-006 sub-tests fail when no log entry exists (stub produces nothing)
    echo "  FAIL: R-006: no log entry found (stub produces no output)"
    # 11 field checks + 7 value checks = 18 failures
    FAIL=$((FAIL + 18))
    return
  fi

  for field in "${required_fields[@]}"; do
    local val
    val="$(echo "$log_entry" | jq -r ".$field // \"__MISSING__\"" 2>/dev/null || echo "__MISSING__")"
    if [ "$val" != "__MISSING__" ] && [ "$val" != "null" ] && [ -n "$val" ]; then
      echo "  PASS: R-006a: field '$field' present (value: $val)"
      PASS=$((PASS + 1))
    else
      echo "  FAIL: R-006a: field '$field' missing from log entry"
      FAIL=$((FAIL + 1))
    fi
  done

  # Check computed total_tokens = input + output using KNOWN INPUT VALUES
  # We fed input_tokens=300, output_tokens=150 via build_agent_stdin above
  # Assert against those hardcoded values, NOT values read back from the log
  local total_tokens
  total_tokens="$(echo "$log_entry" | jq -r '.total_tokens' 2>/dev/null || echo "0")"
  assert_eq "R-006b: total_tokens = 300 + 150 = 450" "450" "$total_tokens"

  # Check timestamp is ISO 8601 format
  local timestamp
  timestamp="$(echo "$log_entry" | jq -r '.timestamp' 2>/dev/null || echo "")"
  assert_match "R-006c: timestamp is ISO 8601" '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}' "$timestamp"

  # Check branch matches the current branch slug
  local branch
  branch="$(echo "$log_entry" | jq -r '.branch' 2>/dev/null || echo "")"
  assert_eq "R-006d: branch matches branch_slug" "$SLUG" "$branch"

  # Check phase matches state file
  local phase
  phase="$(echo "$log_entry" | jq -r '.phase' 2>/dev/null || echo "")"
  assert_eq "R-006e: phase matches state file" "spec" "$phase"

  # Check feature matches task from state file
  local skill
  skill="$(echo "$log_entry" | jq -r '.feature' 2>/dev/null || echo "")"
  assert_eq "R-006f: feature matches state file task" "token-tracking" "$skill"

  # Check agent_description and agent_type
  local desc atype
  desc="$(echo "$log_entry" | jq -r '.agent_description' 2>/dev/null || echo "")"
  atype="$(echo "$log_entry" | jq -r '.agent_type' 2>/dev/null || echo "")"
  assert_eq "R-006g: agent_description correct" "write tests" "$desc"
  assert_eq "R-006h: agent_type correct" "test-writer" "$atype"
}

# ============================================================================
# R-006 [unit]: feature defaults to "unknown" when no state file exists
# ============================================================================

test_r006_feature_defaults_to_unknown() {
  echo ""
  echo "=== R-006: feature defaults to unknown when no state file ==="

  setup_test_env

  # Ensure no state file exists
  rm -f "$TEST_DIR/$STATE_FILE"

  local agent_stdin
  agent_stdin="$(build_agent_stdin 100 50 0.005 1200)"
  run_hook "$agent_stdin" >/dev/null

  local log_entry skill
  log_entry="$(head -1 "$TEST_DIR/$TOKEN_LOG" 2>/dev/null || echo "")"

  if [ -z "$log_entry" ]; then
    echo "  FAIL: R-006-feature-default: no log entry (stub not implemented)"
    FAIL=$((FAIL + 1))
    return
  fi

  skill="$(echo "$log_entry" | jq -r '.feature' 2>/dev/null || echo "")"
  assert_eq "R-006-feature-default: feature is unknown when no state file" "unknown" "$skill"
}

# ============================================================================
# R-004 [integration]: canary test — hook uses branch_slug() for file paths
# ============================================================================

test_r004_branch_slug_canary() {
  echo ""
  echo "=== R-004-canary: hook uses branch_slug() for state and log paths ==="

  setup_test_env

  # Create a lib.sh override that stubs branch_slug() to return a canary value
  cat > "$TEST_DIR/.correctless/scripts/lib.sh" <<'CANARY_LIB'
branch_slug() { echo "CANARY-TEST-SLUG"; }
repo_root() { pwd; }
artifacts_dir() { echo "$(repo_root)/.correctless/artifacts"; }
CANARY_LIB

  # Create a state file at the CANARY path
  local canary_state="$TEST_DIR/.correctless/artifacts/workflow-state-CANARY-TEST-SLUG.json"
  cat > "$canary_state" <<'EOF'
{
  "phase": "canary-phase",
  "task": "canary-task",
  "override": {"active": false, "remaining_calls": 0}
}
EOF

  local agent_stdin
  agent_stdin="$(build_agent_stdin 100 50 0.005 1200)"
  run_hook "$agent_stdin" >/dev/null

  # The hook should have written to the CANARY log path
  local canary_log="$TEST_DIR/.correctless/artifacts/token-log-CANARY-TEST-SLUG.jsonl"

  assert_file_exists "R-004-canary-a: log written to canary slug path" "$canary_log"

  if [ -f "$canary_log" ]; then
    local log_entry phase
    log_entry="$(head -1 "$canary_log")"
    phase="$(echo "$log_entry" | jq -r '.phase' 2>/dev/null || echo "")"
    assert_eq "R-004-canary-b: phase read from canary state file" "canary-phase" "$phase"
  else
    echo "  FAIL: R-004-canary-b: phase read from canary state file (no log file)"
    FAIL=$((FAIL + 1))
  fi
}

# ============================================================================
# R-007 [static]: hook spawns at most two jq processes and zero subshells
#   in loops
# ============================================================================

test_r007_structural_constraints() {
  echo ""
  echo "=== R-007: structural constraints — max 2 jq, no subshells in loops ==="

  # Count jq invocations in the hook source (exclude comments)
  local jq_count
  jq_count="$(grep -vE '^[[:space:]]*#' "$HOOK" | grep -cE '\bjq\b' || true)"
  jq_count="${jq_count:-0}"
  jq_count="$(echo "$jq_count" | tr -d '[:space:]')"
  if [ "$jq_count" -le 2 ]; then
    echo "  PASS: R-007a: hook has $jq_count jq invocations (max 2)"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: R-007a: hook has $jq_count jq invocations (max 2 allowed)"
    FAIL=$((FAIL + 1))
  fi

  # Count $() inside while or for loops (no command substitutions in loops)
  # Look for while/for blocks containing $()
  local subshell_in_loop
  subshell_in_loop="$(awk '
    /^[[:space:]]*(while|for)\b/ { in_loop=1 }
    /^[[:space:]]*done\b/ { in_loop=0 }
    in_loop && /\$\(/ { found=1 }
    END { print (found ? "yes" : "no") }
  ' "$HOOK")"
  assert_eq "R-007b: no command substitutions inside loops" "no" "$subshell_in_loop"

  # Check only allowed external commands: jq, date, cat, and file redirects
  # Extract non-comment lines that invoke external commands (exclude builtins)
  local disallowed_cmds
  disallowed_cmds="$(grep -vE '^[[:space:]]*#' "$HOOK" \
    | grep -vE '^[[:space:]]*$' \
    | grep -vE '^[[:space:]]*@sh\b' \
    | grep -vE '^[[:space:]]*(if|then|else|elif|fi|local|echo|exit|eval|source|return|set|\.|export|read|shift|case|esac|while|for|do|done|function|true|declare|unset|\[\[|test|printf|\{|\})' \
    | grep -vE '\b(jq|date|cat|command|mkdir|cd|pwd)\b' \
    | grep -vE '(>>|>|<|/dev/null|\|\|)' \
    | grep -vE '^[A-Z_]+=' \
    | grep -vE '^[[:space:]]*--arg(json)?\b' \
    | grep -vE "^[[:space:]]*['\"\{]" \
    | grep -vE '^[[:space:]]*\w+:' \
    | grep -vE '^[[:space:]]*[a-z|*-]+\)' \
    | grep -vE '^[[:space:]]*[A-Z_]+="[^"]*"[[:space:]]*;;' \
    || echo "")"
  # This is advisory — we just log what we find for manual review
  if [ -z "$disallowed_cmds" ]; then
    echo "  PASS: R-007c: no unexpected external commands found"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: R-007c: unexpected external commands found in hook"
    FAIL=$((FAIL + 1))
  fi
}

# ============================================================================
# R-009 [static]: hook follows PAT-005 PostToolUse conventions
# ============================================================================

test_r009_pat005_conventions() {
  echo ""
  echo "=== R-009: hook follows PAT-005 PostToolUse conventions ==="

  # Must NOT contain "set -euo pipefail" (that is PAT-001 for PreToolUse)
  local has_set_euo="no"
  if grep -qE 'set[[:space:]]+-[a-z]*e[a-z]*' "$HOOK"; then
    has_set_euo="yes"
  fi
  assert_eq "R-009a: hook does NOT use set -e (or set -euo pipefail)" "no" "$has_set_euo"

  # Must have || exit 0 guards (fail-open pattern)
  local has_exit_0_guard="no"
  if grep -qE '\|\|[[:space:]]*exit[[:space:]]+0' "$HOOK"; then
    has_exit_0_guard="yes"
  fi
  assert_eq "R-009b: hook has || exit 0 guards" "yes" "$has_exit_0_guard"

  # Must have command -v jq check with exit 0 (not exit 2 like PreToolUse)
  local has_jq_check="no"
  if grep -qE 'command[[:space:]]+-v[[:space:]]+jq' "$HOOK"; then
    has_jq_check="yes"
  fi
  assert_eq "R-009c: hook checks command -v jq" "yes" "$has_jq_check"

  # The jq check must NOT exit 2 (that would be fail-closed like PreToolUse)
  local jq_exits_2="no"
  if grep -A2 'command.*-v.*jq' "$HOOK" | grep -qE 'exit[[:space:]]+2'; then
    jq_exits_2="yes"
  fi
  assert_eq "R-009d: jq check does NOT exit 2 (fail-open)" "no" "$jq_exits_2"

  # Must have eval + jq -r @sh for stdin parsing (may span multiple lines)
  local has_eval_jq="no"
  local _has_eval _has_jq_r _has_at_sh
  _has_eval="$(grep -vE '^[[:space:]]*#' "$HOOK" | grep -cE '\beval\b' || echo 0)"
  _has_jq_r="$(grep -vE '^[[:space:]]*#' "$HOOK" | grep -cE 'jq[[:space:]]+-r' || echo 0)"
  _has_at_sh="$(grep -vE '^[[:space:]]*#' "$HOOK" | grep -cE '@sh' || echo 0)"
  if [ "$_has_eval" -gt 0 ] && [ "$_has_jq_r" -gt 0 ] && [ "$_has_at_sh" -gt 0 ]; then
    has_eval_jq="yes"
  fi
  assert_eq "R-009e: hook uses eval + jq -r @sh for stdin parsing" "yes" "$has_eval_jq"

  # Hook must always exit 0 — check the last line (excluding empty/comments)
  local last_meaningful_line
  last_meaningful_line="$(grep -vE '^[[:space:]]*$|^[[:space:]]*#' "$HOOK" | tail -1)"
  assert_contains "R-009f: hook ends with exit 0" "exit 0" "$last_meaningful_line"
}

# ============================================================================
# R-010 [unit]: hook is fail-open (always exit 0 on any failure)
# ============================================================================

test_r010_fail_open() {
  echo ""
  echo "=== R-010: hook is fail-open — always exits 0 on failure ==="

  setup_test_env

  # Test 1: Feed broken/invalid JSON stdin — should exit 0
  local exit_code
  exit_code="$(echo "not json at all {{{" | bash hooks/token-tracking.sh >/dev/null 2>/dev/null && echo 0 || echo $?)"
  assert_eq "R-010a: broken JSON stdin exits 0" "0" "$exit_code"

  # Test 2: Make state file unreadable — should still exit 0
  cat > "$TEST_DIR/$STATE_FILE" <<'EOF'
{"phase": "spec"}
EOF
  chmod 000 "$TEST_DIR/$STATE_FILE" 2>/dev/null || true

  local agent_stdin
  agent_stdin="$(build_agent_stdin)"
  exit_code="$(echo "$agent_stdin" | bash hooks/token-tracking.sh >/dev/null 2>/dev/null && echo 0 || echo $?)"
  assert_eq "R-010b: unreadable state file exits 0" "0" "$exit_code"
  chmod 644 "$TEST_DIR/$STATE_FILE" 2>/dev/null || true

  # Test 3: Make log directory unwritable — should still exit 0
  chmod 555 "$TEST_DIR/.correctless/artifacts" 2>/dev/null || true
  exit_code="$(echo "$agent_stdin" | bash hooks/token-tracking.sh >/dev/null 2>/dev/null && echo 0 || echo $?)"
  assert_eq "R-010c: unwritable log dir exits 0" "0" "$exit_code"
  chmod 755 "$TEST_DIR/.correctless/artifacts" 2>/dev/null || true

  # Test 4: Empty stdin — should exit 0
  exit_code="$(echo "" | bash hooks/token-tracking.sh >/dev/null 2>/dev/null && echo 0 || echo $?)"
  assert_eq "R-010d: empty stdin exits 0" "0" "$exit_code"

  # Test 5: Hook must never exit non-zero (PRH-001)
  # Search the hook source for any exit statement with non-zero value
  local has_nonzero_exit="no"
  if grep -vE '^[[:space:]]*#' "$HOOK" | grep -qE 'exit[[:space:]]+[1-9]'; then
    has_nonzero_exit="yes"
  fi
  assert_eq "R-010e: hook source has no exit [1-9] statements" "no" "$has_nonzero_exit"
}

# ============================================================================
# R-011 [unit]: hook sources lib.sh for branch_slug
# ============================================================================

test_r011_sources_lib() {
  echo ""
  echo "=== R-011: hook sources lib.sh for branch_slug ==="

  # Check that the hook sources lib.sh
  local sources_lib="no"
  if grep -qE '(source|\.).*scripts/lib\.sh|lib\.sh' "$HOOK"; then
    sources_lib="yes"
  fi
  assert_eq "R-011a: hook sources lib.sh" "yes" "$sources_lib"

  # Check that the hook does NOT define branch_slug locally (ABS-001 violation)
  local defines_branch_slug="no"
  if grep -qE '^branch_slug[[:space:]]*\(\)|^function[[:space:]]+branch_slug' "$HOOK"; then
    defines_branch_slug="yes"
  fi
  assert_eq "R-011b: hook does NOT define branch_slug locally" "no" "$defines_branch_slug"

  # Check that branch_slug is CALLED in executable code (not just sourced)
  local calls_branch_slug="no"
  if grep -vE '^[[:space:]]*#' "$HOOK" | grep -qE 'branch_slug'; then
    calls_branch_slug="yes"
  fi
  assert_eq "R-011b2: hook calls branch_slug in executable code" "yes" "$calls_branch_slug"

  # Test that if lib.sh is not found, hook exits 0 (fail-open)
  setup_test_env
  rm -f "$TEST_DIR/.correctless/scripts/lib.sh"

  local agent_stdin
  agent_stdin="$(build_agent_stdin)"
  local exit_code
  exit_code="$(echo "$agent_stdin" | bash hooks/token-tracking.sh >/dev/null 2>/dev/null && echo 0 || echo $?)"
  assert_eq "R-011c: hook exits 0 when lib.sh not found" "0" "$exit_code"
}

# ============================================================================
# PRH-003 [static]: no eval of tool_response.result
# ============================================================================

test_prh003_no_result_processing() {
  echo ""
  echo "=== PRH-003: hook never processes tool_response.result ==="

  # Hook must not reference .result in jq expressions (non-comment lines)
  local refs_result_jq="no"
  if grep -vE '^[[:space:]]*#' "$HOOK" | grep -qE '\.result'; then
    refs_result_jq="yes"
  fi
  assert_eq "PRH-003a: no .result in jq expressions" "no" "$refs_result_jq"

  # Hook must not declare a variable named result or RESULT
  local has_result_var="no"
  if grep -vE '^[[:space:]]*#' "$HOOK" | grep -qE '\b(result|RESULT)[[:space:]]*='; then
    has_result_var="yes"
  fi
  assert_eq "PRH-003b: no shell variable named result/RESULT" "no" "$has_result_var"

  # Hook source must include TB-003 comment
  local has_tb003="no"
  if grep -q 'TB-003' "$HOOK"; then
    has_tb003="yes"
  fi
  assert_eq "PRH-003c: hook contains TB-003 comment" "yes" "$has_tb003"
}

# ============================================================================
# PRH-002 [static]: hook must not write to stdout
# ============================================================================

test_prh002_no_stdout() {
  echo ""
  echo "=== PRH-002: hook must not write to stdout ==="

  setup_test_env

  local agent_stdin
  agent_stdin="$(build_agent_stdin)"

  # Capture stdout for Agent tool — should be empty
  local stdout_output
  stdout_output="$(echo "$agent_stdin" | bash hooks/token-tracking.sh 2>/dev/null)"
  assert_eq "PRH-002a: hook produces no stdout for Agent tool" "" "$stdout_output"

  # Capture stdout for non-Agent tool — should also be empty
  local read_stdin
  read_stdin='{"tool_name":"Read","tool_input":{"file_path":"test.txt"},"tool_response":{"content":"hello"}}'
  local non_agent_stdout
  non_agent_stdout="$(echo "$read_stdin" | bash hooks/token-tracking.sh 2>/dev/null)"
  assert_eq "PRH-002b: hook produces no stdout for non-Agent tool" "" "$non_agent_stdout"
}

# ============================================================================
# Benchmark: hook execution time (non-gating — informational per R-007)
# ============================================================================

test_benchmark() {
  echo ""
  echo "=== Benchmark: hook execution time (non-gating) ==="

  setup_test_env

  cat > "$TEST_DIR/$STATE_FILE" <<'EOF'
{"phase": "tdd-impl"}
EOF

  local agent_stdin
  agent_stdin="$(build_agent_stdin)"

  # Time the hook execution
  local start_ms end_ms duration_ms
  start_ms="$(date +%s%3N 2>/dev/null || echo 0)"
  run_hook "$agent_stdin" >/dev/null
  end_ms="$(date +%s%3N 2>/dev/null || echo 0)"

  if [ "$start_ms" != "0" ] && [ "$end_ms" != "0" ]; then
    duration_ms=$((end_ms - start_ms))
    echo "  INFO: hook execution took ${duration_ms}ms (target: <100ms)"
    # Non-gating — just log for regression tracking
  else
    echo "  INFO: benchmark skipped (date +%s%3N not available)"
  fi
  # Always passes — this is informational
  PASS=$((PASS + 1))
}

# ============================================================================
# Run all tests
# ============================================================================

test_r001_agent_only
test_r002_token_extraction
test_r003_subagent_metadata
test_r004_workflow_phase
test_r005_jsonl_append
test_r006_required_fields
test_r006_feature_defaults_to_unknown
test_r004_branch_slug_canary
test_r007_structural_constraints
test_r009_pat005_conventions
test_r010_fail_open
test_r011_sources_lib
test_prh003_no_result_processing
test_prh002_no_stdout
test_benchmark

# ============================================================================
# Summary
# ============================================================================

echo ""
echo "=============================="
echo "  PASS: $PASS"
echo "  FAIL: $FAIL"
echo "=============================="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
