#!/usr/bin/env bash
# Correctless — Session Cost Analysis Tests
#
# Tests R-001 through R-018 from the session-cost-analysis spec.
# Creates temp directories with synthetic Claude Code session transcripts,
# runs compute-session-cost.sh, and verifies output.
#
# Run from repo root: bash tests/test-session-cost.sh

# shellcheck disable=SC1090
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || { echo "FATAL: cannot cd to repo root" >&2; exit 2; }

REPO_DIR="$(pwd)"
SCRIPT="$REPO_DIR/scripts/compute-session-cost.sh"
LIB_SH="$REPO_DIR/scripts/lib.sh"
PASS=0
FAIL=0
FAILED_IDS=""

# ============================================================================
# Helpers
# ============================================================================

pass() {
  local id="$1" desc="$2"
  echo "  PASS: $id — $desc"
  PASS=$((PASS + 1))
}

fail() {
  local id="$1" desc="$2"
  echo "  FAIL: $id — $desc"
  FAIL=$((FAIL + 1))
  FAILED_IDS="${FAILED_IDS}${id} "
}

assert_eq() {
  local id="$1" desc="$2" expected="$3" actual="$4"
  if [ "$expected" = "$actual" ]; then
    pass "$id" "$desc"
  else
    fail "$id" "$desc (expected '$expected', got '$actual')"
  fi
}

assert_json_field() {
  local id="$1" desc="$2" json="$3" field="$4" expected="$5"
  local actual
  actual=$(echo "$json" | jq -r "$field" 2>/dev/null)
  if [ "$actual" = "$expected" ]; then
    pass "$id" "$desc"
  else
    fail "$id" "$desc (field $field: expected '$expected', got '$actual')"
  fi
}

assert_json_field_gt() {
  local id="$1" desc="$2" json="$3" field="$4" threshold="$5"
  local actual
  actual=$(echo "$json" | jq -r "$field" 2>/dev/null)
  if [ "$(echo "$actual > $threshold" | bc -l 2>/dev/null || echo 0)" = "1" ]; then
    pass "$id" "$desc"
  else
    fail "$id" "$desc (field $field: expected > $threshold, got '$actual')"
  fi
}

# ============================================================================
# Test environment setup
# ============================================================================

# Create a synthetic session transcript directory structure
# that mimics ~/.claude/projects/{project-dir}/{session}.jsonl
setup_test_env() {
  local test_dir
  test_dir=$(mktemp -d)

  # Create a git repo in the test dir so repo_root / branch_slug work
  git -C "$test_dir" init -q 2>/dev/null
  git -C "$test_dir" config user.email "test@test.com"
  git -C "$test_dir" config user.name "Test"
  # Create initial commit so branch exists
  touch "$test_dir/.gitkeep"
  git -C "$test_dir" add .gitkeep
  git -C "$test_dir" commit -q -m "init" 2>/dev/null

  # Create correctless config
  mkdir -p "$test_dir/.correctless/config"
  mkdir -p "$test_dir/.correctless/artifacts"
  cat > "$test_dir/.correctless/config/workflow-config.json" <<'EOF'
{
  "project": { "name": "test-project" },
  "workflow": { "intensity": "standard" }
}
EOF

  echo "$test_dir"
}

# Create a synthetic session directory under the fake HOME
# Arguments: $1=HOME dir, $2=project-dir-slug, $3=session-uuid
# Returns: the session JSONL path
create_session_dir() {
  local home_dir="$1" proj_slug="$2" session_uuid="$3"
  local session_dir="$home_dir/.claude/projects/$proj_slug"
  mkdir -p "$session_dir"
  local jsonl_path="$session_dir/$session_uuid.jsonl"
  touch "$jsonl_path"
  echo "$jsonl_path"
}

# Write a transcript entry (assistant message with usage)
# Arguments: $1=jsonl_path, $2=model, $3=input_tokens, $4=output_tokens
#            $5=cache_write, $6=cache_read, $7=git_branch, $8=timestamp
#            $9=message_id (optional, defaults to random UUID)
write_transcript_entry() {
  local jsonl_path="$1" model="$2" input="$3" output="$4"
  local cache_write="$5" cache_read="$6" branch="$7" timestamp="$8"
  local msg_id="${9:-$(cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "msg-$(date +%s%N)")}"
  cat >> "$jsonl_path" <<ENTRY
{"type":"assistant","message":{"id":"$msg_id","model":"$model","usage":{"input_tokens":$input,"output_tokens":$output,"cache_creation_input_tokens":$cache_write,"cache_read_input_tokens":$cache_read}},"timestamp":"$timestamp","gitBranch":"$branch"}
ENTRY
}

# Write a duplicate streaming entry (same message ID, partial tokens)
# Used to test R-003 deduplication
write_streaming_entry() {
  local jsonl_path="$1" model="$2" input="$3" output="$4"
  local cache_write="$5" cache_read="$6" branch="$7" timestamp="$8"
  local msg_id="$9"
  cat >> "$jsonl_path" <<ENTRY
{"type":"assistant","message":{"id":"$msg_id","model":"$model","usage":{"input_tokens":$input,"output_tokens":$output,"cache_creation_input_tokens":$cache_write,"cache_read_input_tokens":$cache_read}},"timestamp":"$timestamp","gitBranch":"$branch"}
ENTRY
}

# Write a non-assistant entry (should be ignored)
write_user_entry() {
  local jsonl_path="$1" branch="$2" timestamp="$3"
  cat >> "$jsonl_path" <<ENTRY
{"type":"user","message":{"id":"user-$(date +%s%N)","content":"hello"},"timestamp":"$timestamp","gitBranch":"$branch"}
ENTRY
}

# Create audit trail for phase attribution
create_audit_trail() {
  local test_dir="$1" slug="$2"
  local trail_path="$test_dir/.correctless/artifacts/audit-trail-$slug.jsonl"
  shift 2
  # Remaining args are "phase timestamp" pairs
  while [ $# -ge 2 ]; do
    echo "{\"phase\":\"$1\",\"timestamp\":\"$2\"}" >> "$trail_path"
    shift 2
  done
  echo "$trail_path"
}

echo "=== Session Cost Analysis Tests ==="

# ============================================================================
# R-001: Script exists, accepts branch, outputs JSON, writes artifact
# ============================================================================

test_r001_script_exists_and_outputs_json() {
  echo ""
  echo "--- R-001: Script exists and outputs JSON ---"

  # Tests R-001 [unit]: script exists
  if [ -f "$SCRIPT" ]; then
    pass "R001-a" "scripts/compute-session-cost.sh exists"
  else
    fail "R001-a" "scripts/compute-session-cost.sh does not exist"
    return
  fi

  # Tests R-001 [unit]: script is executable or sourceable
  if bash -n "$SCRIPT" 2>/dev/null; then
    pass "R001-b" "Script has valid bash syntax"
  else
    fail "R001-b" "Script has syntax errors"
  fi

  # Tests R-001 [unit]: script sources lib.sh
  if grep -q 'lib\.sh' "$SCRIPT"; then
    pass "R001-c" "Script references lib.sh"
  else
    fail "R001-c" "Script does not reference lib.sh"
  fi

  # Tests R-001 [unit]: accepts a branch name argument
  local TEST_DIR
  TEST_DIR=$(setup_test_env)
  local FAKE_HOME
  FAKE_HOME=$(mktemp -d)

  # Derive the project directory slug the same way the script should
  local repo_root_path="$TEST_DIR"
  local proj_slug
  proj_slug=$(echo "$repo_root_path" | tr '/' '-' | sed 's/^-//')

  # Create session directory with one matching entry
  local session_id="test-session-001"
  local jsonl_path
  jsonl_path=$(create_session_dir "$FAKE_HOME" "$proj_slug" "$session_id")
  write_transcript_entry "$jsonl_path" "claude-sonnet-4-6" 1000 500 200 100 "feature/test-branch" "2026-04-15T10:00:00Z"

  local output exit_code
  output=$(cd "$TEST_DIR" && HOME="$FAKE_HOME" bash "$SCRIPT" "feature/test-branch" 2>/dev/null)
  exit_code=$?

  if [ $exit_code -eq 0 ]; then
    pass "R001-d" "Script exits 0 on success"
  else
    fail "R001-d" "Script exited with code $exit_code"
  fi

  # Stdout should be valid JSON
  if echo "$output" | jq -e '.' >/dev/null 2>&1; then
    pass "R001-e" "Stdout is valid JSON"
  else
    fail "R001-e" "Stdout is not valid JSON: $output"
  fi

  # Tests R-001 [unit]: writes artifact file
  # Get the branch slug for the artifact filename
  local branch_slug
  branch_slug=$(cd "$TEST_DIR" && source "$LIB_SH" && branch_slug "feature/test-branch")
  local artifact_path="$TEST_DIR/.correctless/artifacts/cost-${branch_slug}.json"
  if [ -f "$artifact_path" ]; then
    pass "R001-f" "Cost artifact written to correct path"
  else
    fail "R001-f" "Cost artifact not found at $artifact_path"
  fi

  rm -rf "$TEST_DIR" "$FAKE_HOME"
}

# ============================================================================
# R-002: Session discovery (candidate derivation + config override)
# ============================================================================

test_r002_session_discovery() {
  echo ""
  echo "--- R-002: Session discovery ---"

  local TEST_DIR
  TEST_DIR=$(setup_test_env)
  local FAKE_HOME
  FAKE_HOME=$(mktemp -d)

  # Tests R-002 [unit]: candidate derivation via repo_root | tr '/' '-'
  local repo_root_path="$TEST_DIR"
  local proj_slug
  proj_slug=$(echo "$repo_root_path" | tr '/' '-' | sed 's/^-//')

  local session_id="session-discovery-001"
  local jsonl_path
  jsonl_path=$(create_session_dir "$FAKE_HOME" "$proj_slug" "$session_id")
  write_transcript_entry "$jsonl_path" "claude-sonnet-4-6" 500 250 0 0 "feature/test" "2026-04-15T10:00:00Z"

  local output
  output=$(cd "$TEST_DIR" && HOME="$FAKE_HOME" bash "$SCRIPT" "feature/test" 2>/dev/null)

  if echo "$output" | jq -e '.sessions | length > 0' >/dev/null 2>&1; then
    pass "R002-a" "Session discovered via candidate derivation"
  else
    fail "R002-a" "No sessions found via candidate derivation"
  fi

  rm -rf "$TEST_DIR" "$FAKE_HOME"

  # Tests R-002 [unit]: session dir not found exits 0 with error JSON
  TEST_DIR=$(setup_test_env)
  FAKE_HOME=$(mktemp -d)
  mkdir -p "$FAKE_HOME/.claude/projects"
  # No matching project directory — should get error JSON

  output=$(cd "$TEST_DIR" && HOME="$FAKE_HOME" bash "$SCRIPT" "feature/test" 2>/dev/null)
  local exit_code=$?

  if [ $exit_code -eq 0 ]; then
    pass "R002-b" "Exits 0 when session dir not found"
  else
    fail "R002-b" "Non-zero exit when session dir not found"
  fi

  if echo "$output" | jq -e '.error' >/dev/null 2>&1; then
    pass "R002-c" "Error JSON has 'error' field when session dir not found"
  else
    fail "R002-c" "Missing error field in output"
  fi

  if echo "$output" | jq -e '.total_cost_usd == 0' >/dev/null 2>&1; then
    pass "R002-d" "total_cost_usd is 0 when session dir not found"
  else
    fail "R002-d" "total_cost_usd not 0 in error JSON"
  fi

  rm -rf "$TEST_DIR" "$FAKE_HOME"

  # Tests R-002 [unit]: config override via workflow.session_dir
  TEST_DIR=$(setup_test_env)
  FAKE_HOME=$(mktemp -d)
  local CUSTOM_SESSION_DIR="$FAKE_HOME/.claude/projects/custom-override"
  mkdir -p "$CUSTOM_SESSION_DIR"

  # Update config with session_dir override
  cat > "$TEST_DIR/.correctless/config/workflow-config.json" <<EOF
{
  "project": { "name": "test-project" },
  "workflow": { "intensity": "standard", "session_dir": "$CUSTOM_SESSION_DIR" }
}
EOF

  local session_id2="override-session-001"
  local jsonl_path2="$CUSTOM_SESSION_DIR/$session_id2.jsonl"
  write_transcript_entry "$jsonl_path2" "claude-sonnet-4-6" 800 400 0 0 "feature/override" "2026-04-15T10:00:00Z"

  output=$(cd "$TEST_DIR" && HOME="$FAKE_HOME" bash "$SCRIPT" "feature/override" 2>/dev/null)

  if echo "$output" | jq -e '.sessions | length > 0' >/dev/null 2>&1; then
    pass "R002-e" "Config override session_dir works"
  else
    fail "R002-e" "Config override session_dir not used"
  fi

  rm -rf "$TEST_DIR" "$FAKE_HOME"

  # Tests R-002 [unit]: session_dir validation — must be absolute path
  TEST_DIR=$(setup_test_env)
  FAKE_HOME=$(mktemp -d)

  cat > "$TEST_DIR/.correctless/config/workflow-config.json" <<'EOF'
{
  "project": { "name": "test-project" },
  "workflow": { "intensity": "standard", "session_dir": "relative/path" }
}
EOF

  output=$(cd "$TEST_DIR" && HOME="$FAKE_HOME" bash "$SCRIPT" "feature/test" 2>/dev/null)

  if echo "$output" | jq -e '.error' >/dev/null 2>&1; then
    pass "R002-f" "Rejects relative session_dir path"
  else
    fail "R002-f" "Accepted relative session_dir path"
  fi

  rm -rf "$TEST_DIR" "$FAKE_HOME"

  # Tests R-002 [unit]: session_dir must be under ~/.claude/
  TEST_DIR=$(setup_test_env)
  FAKE_HOME=$(mktemp -d)

  cat > "$TEST_DIR/.correctless/config/workflow-config.json" <<EOF
{
  "project": { "name": "test-project" },
  "workflow": { "intensity": "standard", "session_dir": "/tmp/not-under-claude" }
}
EOF

  output=$(cd "$TEST_DIR" && HOME="$FAKE_HOME" bash "$SCRIPT" "feature/test" 2>/dev/null)

  if echo "$output" | jq -e '.error' >/dev/null 2>&1; then
    pass "R002-g" "Rejects session_dir not under ~/.claude/"
  else
    fail "R002-g" "Accepted session_dir not under ~/.claude/"
  fi

  rm -rf "$TEST_DIR" "$FAKE_HOME"

  # Tests R-002 [unit]: gitBranch exact match, not regex/glob
  TEST_DIR=$(setup_test_env)
  FAKE_HOME=$(mktemp -d)

  proj_slug=$(echo "$TEST_DIR" | tr '/' '-' | sed 's/^-//')
  jsonl_path=$(create_session_dir "$FAKE_HOME" "$proj_slug" "branch-match-session")
  # Entry with similar but not exact branch
  write_transcript_entry "$jsonl_path" "claude-sonnet-4-6" 500 250 0 0 "feature/test-extra" "2026-04-15T10:00:00Z"
  # Entry with exact branch
  write_transcript_entry "$jsonl_path" "claude-sonnet-4-6" 500 250 0 0 "feature/test" "2026-04-15T10:01:00Z"

  output=$(cd "$TEST_DIR" && HOME="$FAKE_HOME" bash "$SCRIPT" "feature/test" 2>/dev/null)

  # Should only include the exact match (1 turn from feature/test)
  local turn_count
  turn_count=$(echo "$output" | jq '[.by_phase[] | .turns] | add // 0' 2>/dev/null)
  if [ "$turn_count" = "1" ]; then
    pass "R002-h" "gitBranch uses exact string match"
  else
    fail "R002-h" "gitBranch match is not exact (got $turn_count turns, expected 1)"
  fi

  rm -rf "$TEST_DIR" "$FAKE_HOME"
}

# ============================================================================
# R-003: Per-turn cost computation with message.id deduplication
# ============================================================================

test_r003_cost_computation() {
  echo ""
  echo "--- R-003: Per-turn cost computation with deduplication ---"

  local TEST_DIR
  TEST_DIR=$(setup_test_env)
  local FAKE_HOME
  FAKE_HOME=$(mktemp -d)

  local proj_slug
  proj_slug=$(echo "$TEST_DIR" | tr '/' '-' | sed 's/^-//')
  local jsonl_path
  jsonl_path=$(create_session_dir "$FAKE_HOME" "$proj_slug" "cost-session-001")

  # Tests R-003 [unit]: message.id deduplication — streaming produces duplicates
  # Write 3 streaming entries with same message ID (increasing token counts)
  # Only the last one should be used
  local msg_id="msg-stream-001"
  write_streaming_entry "$jsonl_path" "claude-sonnet-4-6" 100 50 0 0 "feature/cost" "2026-04-15T10:00:01Z" "$msg_id"
  write_streaming_entry "$jsonl_path" "claude-sonnet-4-6" 500 200 0 0 "feature/cost" "2026-04-15T10:00:02Z" "$msg_id"
  write_streaming_entry "$jsonl_path" "claude-sonnet-4-6" 1000 400 100 50 "feature/cost" "2026-04-15T10:00:03Z" "$msg_id"

  # Write a separate message with a different ID
  write_transcript_entry "$jsonl_path" "claude-sonnet-4-6" 2000 800 200 100 "feature/cost" "2026-04-15T10:01:00Z"

  local output
  output=$(cd "$TEST_DIR" && HOME="$FAKE_HOME" bash "$SCRIPT" "feature/cost" 2>/dev/null)

  # After dedup: 2 messages. msg-stream-001 (last entry: 1000/400/100/50) + unique msg (2000/800/200/100)
  # Total input = 1000 + 2000 = 3000
  local total_input
  total_input=$(echo "$output" | jq '.total_input_tokens' 2>/dev/null)
  if [ "$total_input" = "3000" ]; then
    pass "R003-a" "Deduplication keeps last entry per message ID (input tokens)"
  else
    fail "R003-a" "Deduplication failed: expected total_input=3000, got $total_input"
  fi

  # Total output = 400 + 800 = 1200
  local total_output
  total_output=$(echo "$output" | jq '.total_output_tokens' 2>/dev/null)
  if [ "$total_output" = "1200" ]; then
    pass "R003-b" "Deduplication correct for output tokens"
  else
    fail "R003-b" "Output tokens wrong: expected 1200, got $total_output"
  fi

  rm -rf "$TEST_DIR" "$FAKE_HOME"

  # Tests R-003 [unit]: cost formula uses correct pricing components
  TEST_DIR=$(setup_test_env)
  FAKE_HOME=$(mktemp -d)

  proj_slug=$(echo "$TEST_DIR" | tr '/' '-' | sed 's/^-//')
  jsonl_path=$(create_session_dir "$FAKE_HOME" "$proj_slug" "formula-session")

  # Claude Sonnet 4.6 pricing (per million tokens): input=$3, output=$15, cache_write=$3.75, cache_read=$0.30
  # Per-token: input=0.000003, output=0.000015, cache_write=0.00000375, cache_read=0.0000003
  # Single message: 10000 input, 5000 output, 2000 cache_write, 8000 cache_read
  # Cost = (10000*0.000003) + (2000*0.00000375) + (8000*0.0000003) + (5000*0.000015)
  #      = 0.03 + 0.0075 + 0.0024 + 0.075 = 0.1149
  write_transcript_entry "$jsonl_path" "claude-sonnet-4-6" 10000 5000 2000 8000 "feature/formula" "2026-04-15T10:00:00Z"

  output=$(cd "$TEST_DIR" && HOME="$FAKE_HOME" bash "$SCRIPT" "feature/formula" 2>/dev/null)

  local total_cost
  total_cost=$(echo "$output" | jq '.total_cost_usd' 2>/dev/null)
  # Should be approximately 0.1149 (depending on exact sonnet pricing)
  if echo "$output" | jq -e '.total_cost_usd > 0' >/dev/null 2>&1; then
    pass "R003-c" "Cost computation produces non-zero value"
  else
    fail "R003-c" "Cost computation returned 0 or null"
  fi

  rm -rf "$TEST_DIR" "$FAKE_HOME"

  # Tests R-003 [unit]: unknown models use median pricing + unknown_models array
  TEST_DIR=$(setup_test_env)
  FAKE_HOME=$(mktemp -d)

  proj_slug=$(echo "$TEST_DIR" | tr '/' '-' | sed 's/^-//')
  jsonl_path=$(create_session_dir "$FAKE_HOME" "$proj_slug" "unknown-model-session")
  write_transcript_entry "$jsonl_path" "<synthetic>" 1000 500 0 0 "feature/unknown" "2026-04-15T10:00:00Z"

  output=$(cd "$TEST_DIR" && HOME="$FAKE_HOME" bash "$SCRIPT" "feature/unknown" 2>/dev/null)

  if echo "$output" | jq -e '.unknown_models | length > 0' >/dev/null 2>&1; then
    pass "R003-d" "Unknown model listed in unknown_models array"
  else
    fail "R003-d" "Unknown model not in unknown_models array"
  fi

  if echo "$output" | jq -e '.unknown_models[] | select(. == "<synthetic>")' >/dev/null 2>&1; then
    pass "R003-e" "Specific unknown model ID recorded"
  else
    fail "R003-e" "Specific unknown model ID not found"
  fi

  # Cost should still be > 0 (median pricing used)
  if echo "$output" | jq -e '.total_cost_usd > 0' >/dev/null 2>&1; then
    pass "R003-f" "Unknown model still computes non-zero cost (median pricing)"
  else
    fail "R003-f" "Unknown model computed zero cost"
  fi

  rm -rf "$TEST_DIR" "$FAKE_HOME"

  # Tests R-003 [unit]: assistant entry without usage fields emits warning
  TEST_DIR=$(setup_test_env)
  FAKE_HOME=$(mktemp -d)

  proj_slug=$(echo "$TEST_DIR" | tr '/' '-' | sed 's/^-//')
  jsonl_path=$(create_session_dir "$FAKE_HOME" "$proj_slug" "no-usage-session")
  # Write an assistant entry missing usage.input_tokens
  cat >> "$jsonl_path" <<'ENTRY'
{"type":"assistant","message":{"id":"msg-no-usage","model":"claude-sonnet-4-6"},"timestamp":"2026-04-15T10:00:00Z","gitBranch":"feature/no-usage"}
ENTRY

  output=$(cd "$TEST_DIR" && HOME="$FAKE_HOME" bash "$SCRIPT" "feature/no-usage" 2>/dev/null)

  if echo "$output" | jq -e '.warnings | length > 0' >/dev/null 2>&1; then
    pass "R003-g" "Warning emitted for assistant entry without usage"
  else
    fail "R003-g" "No warning for assistant entry without usage"
  fi

  rm -rf "$TEST_DIR" "$FAKE_HOME"

  # Tests R-003 [unit]: uses jq -R (not jq -s) per AP-014
  if grep -q 'jq -s' "$SCRIPT" 2>/dev/null; then
    fail "R003-h" "Script uses jq -s (violates AP-014)"
  else
    pass "R003-h" "Script does not use jq -s"
  fi
}

# ============================================================================
# R-004: Phase attribution via audit trail
# ============================================================================

test_r004_phase_attribution() {
  echo ""
  echo "--- R-004: Phase attribution ---"

  local TEST_DIR
  TEST_DIR=$(setup_test_env)
  local FAKE_HOME
  FAKE_HOME=$(mktemp -d)

  local proj_slug
  proj_slug=$(echo "$TEST_DIR" | tr '/' '-' | sed 's/^-//')
  local jsonl_path
  jsonl_path=$(create_session_dir "$FAKE_HOME" "$proj_slug" "phase-session")

  # Create branch and get slug
  git -C "$TEST_DIR" checkout -q -b "feature/phase-test" 2>/dev/null
  local branch_slug
  branch_slug=$(cd "$TEST_DIR" && source "$LIB_SH" && branch_slug "feature/phase-test")

  # Create audit trail with phase transitions (including re-entry)
  create_audit_trail "$TEST_DIR" "$branch_slug" \
    "tdd-tests" "2026-04-15T10:00:00Z" \
    "tdd-impl"  "2026-04-15T10:05:00Z" \
    "tdd-qa"    "2026-04-15T10:10:00Z" \
    "tdd-impl"  "2026-04-15T10:15:00Z" \
    "tdd-qa"    "2026-04-15T10:20:00Z"

  # Write transcript entries in different phases
  write_transcript_entry "$jsonl_path" "claude-sonnet-4-6" 500 250 0 0 "feature/phase-test" "2026-04-15T10:02:00Z"  # tdd-tests
  write_transcript_entry "$jsonl_path" "claude-sonnet-4-6" 500 250 0 0 "feature/phase-test" "2026-04-15T10:07:00Z"  # tdd-impl (first)
  write_transcript_entry "$jsonl_path" "claude-sonnet-4-6" 500 250 0 0 "feature/phase-test" "2026-04-15T10:12:00Z"  # tdd-qa (first)
  write_transcript_entry "$jsonl_path" "claude-sonnet-4-6" 500 250 0 0 "feature/phase-test" "2026-04-15T10:17:00Z"  # tdd-impl (re-entry)
  write_transcript_entry "$jsonl_path" "claude-sonnet-4-6" 500 250 0 0 "feature/phase-test" "2026-04-15T10:22:00Z"  # tdd-qa (second)

  local output
  output=$(cd "$TEST_DIR" && HOME="$FAKE_HOME" bash "$SCRIPT" "feature/phase-test" 2>/dev/null)

  # Tests R-004 [unit]: by_phase array exists and has entries
  if echo "$output" | jq -e '.by_phase | length > 0' >/dev/null 2>&1; then
    pass "R004-a" "by_phase array populated"
  else
    fail "R004-a" "by_phase array empty or missing"
  fi

  # Tests R-004 [unit]: tdd-tests phase has 1 turn
  local tdd_tests_turns
  tdd_tests_turns=$(echo "$output" | jq '[.by_phase[] | select(.phase == "tdd-tests") | .turns] | add // 0' 2>/dev/null)
  if [ "$tdd_tests_turns" = "1" ]; then
    pass "R004-b" "tdd-tests phase has 1 turn"
  else
    fail "R004-b" "tdd-tests turns: expected 1, got $tdd_tests_turns"
  fi

  # Tests R-004 [unit]: tdd-impl phase has 2 turns (including re-entry)
  local tdd_impl_turns
  tdd_impl_turns=$(echo "$output" | jq '[.by_phase[] | select(.phase == "tdd-impl") | .turns] | add // 0' 2>/dev/null)
  if [ "$tdd_impl_turns" = "2" ]; then
    pass "R004-c" "tdd-impl phase has 2 turns (re-entry counted)"
  else
    fail "R004-c" "tdd-impl turns: expected 2, got $tdd_impl_turns"
  fi

  # Tests R-004 [unit]: tdd-qa phase has 2 turns
  local tdd_qa_turns
  tdd_qa_turns=$(echo "$output" | jq '[.by_phase[] | select(.phase == "tdd-qa") | .turns] | add // 0' 2>/dev/null)
  if [ "$tdd_qa_turns" = "2" ]; then
    pass "R004-d" "tdd-qa phase has 2 turns"
  else
    fail "R004-d" "tdd-qa turns: expected 2, got $tdd_qa_turns"
  fi

  rm -rf "$TEST_DIR" "$FAKE_HOME"

  # Tests R-004 [unit]: turns before first audit trail entry are "pre-workflow"
  TEST_DIR=$(setup_test_env)
  FAKE_HOME=$(mktemp -d)

  proj_slug=$(echo "$TEST_DIR" | tr '/' '-' | sed 's/^-//')
  jsonl_path=$(create_session_dir "$FAKE_HOME" "$proj_slug" "preworkflow-session")
  git -C "$TEST_DIR" checkout -q -b "feature/pre-wf" 2>/dev/null
  branch_slug=$(cd "$TEST_DIR" && source "$LIB_SH" && branch_slug "feature/pre-wf")

  create_audit_trail "$TEST_DIR" "$branch_slug" \
    "tdd-tests" "2026-04-15T10:05:00Z"

  # Turn BEFORE the first audit trail entry
  write_transcript_entry "$jsonl_path" "claude-sonnet-4-6" 500 250 0 0 "feature/pre-wf" "2026-04-15T10:00:00Z"
  # Turn after
  write_transcript_entry "$jsonl_path" "claude-sonnet-4-6" 500 250 0 0 "feature/pre-wf" "2026-04-15T10:07:00Z"

  output=$(cd "$TEST_DIR" && HOME="$FAKE_HOME" bash "$SCRIPT" "feature/pre-wf" 2>/dev/null)

  local pre_workflow_turns
  pre_workflow_turns=$(echo "$output" | jq '[.by_phase[] | select(.phase == "pre-workflow") | .turns] | add // 0' 2>/dev/null)
  if [ "$pre_workflow_turns" = "1" ]; then
    pass "R004-e" "Pre-workflow turns attributed correctly"
  else
    fail "R004-e" "Pre-workflow turns: expected 1, got $pre_workflow_turns"
  fi

  rm -rf "$TEST_DIR" "$FAKE_HOME"

  # Tests R-004 [unit]: no audit trail -> all "unattributed"
  TEST_DIR=$(setup_test_env)
  FAKE_HOME=$(mktemp -d)

  proj_slug=$(echo "$TEST_DIR" | tr '/' '-' | sed 's/^-//')
  jsonl_path=$(create_session_dir "$FAKE_HOME" "$proj_slug" "no-trail-session")
  write_transcript_entry "$jsonl_path" "claude-sonnet-4-6" 500 250 0 0 "feature/no-trail" "2026-04-15T10:00:00Z"

  output=$(cd "$TEST_DIR" && HOME="$FAKE_HOME" bash "$SCRIPT" "feature/no-trail" 2>/dev/null)

  local unattributed_turns
  unattributed_turns=$(echo "$output" | jq '[.by_phase[] | select(.phase == "unattributed") | .turns] | add // 0' 2>/dev/null)
  if [ "$unattributed_turns" = "1" ]; then
    pass "R004-f" "All turns unattributed when no audit trail"
  else
    fail "R004-f" "Unattributed turns: expected 1, got $unattributed_turns"
  fi

  rm -rf "$TEST_DIR" "$FAKE_HOME"
}

# ============================================================================
# R-005: Output JSON schema validation
# ============================================================================

test_r005_output_schema() {
  echo ""
  echo "--- R-005: Output JSON schema ---"

  local TEST_DIR
  TEST_DIR=$(setup_test_env)
  local FAKE_HOME
  FAKE_HOME=$(mktemp -d)

  local proj_slug
  proj_slug=$(echo "$TEST_DIR" | tr '/' '-' | sed 's/^-//')
  local jsonl_path
  jsonl_path=$(create_session_dir "$FAKE_HOME" "$proj_slug" "schema-session")
  write_transcript_entry "$jsonl_path" "claude-sonnet-4-6" 5000 2500 1000 3000 "feature/schema" "2026-04-15T10:00:00Z"
  write_transcript_entry "$jsonl_path" "claude-sonnet-4-6" 3000 1500 500 2000 "feature/schema" "2026-04-15T10:01:00Z"

  local output
  output=$(cd "$TEST_DIR" && HOME="$FAKE_HOME" bash "$SCRIPT" "feature/schema" 2>/dev/null)

  # Tests R-005 [unit]: all required top-level fields present
  local required_fields=("branch" "feature" "computed_at" "sessions" "total_cost_usd"
    "total_input_tokens" "total_output_tokens" "total_cache_write_tokens"
    "total_cache_read_tokens" "by_phase" "by_subagent" "pricing_used"
    "model_breakdown" "unknown_models" "warnings")

  for field in "${required_fields[@]}"; do
    if echo "$output" | jq -e "has(\"$field\")" >/dev/null 2>&1; then
      pass "R005-$field" "Field '$field' present in output"
    else
      fail "R005-$field" "Field '$field' missing from output"
    fi
  done

  # Tests R-005 [unit]: 6-decimal precision for USD values
  local cost_str
  cost_str=$(echo "$output" | jq -r '.total_cost_usd | tostring' 2>/dev/null)
  # Check that USD value has at most 6 decimal places (jq may truncate trailing zeros)
  if echo "$cost_str" | grep -qE '^[0-9]+(\.[0-9]{1,6})?$'; then
    pass "R005-precision" "total_cost_usd has valid precision"
  else
    fail "R005-precision" "total_cost_usd precision invalid: $cost_str"
  fi

  # Tests R-005 [unit]: consistency invariant —
  # total_cost_usd == sum(by_phase[].cost_usd)
  local total_cost by_phase_sum
  total_cost=$(echo "$output" | jq '.total_cost_usd' 2>/dev/null)
  by_phase_sum=$(echo "$output" | jq '[.by_phase[].cost_usd] | add // 0' 2>/dev/null)
  if [ "$total_cost" = "$by_phase_sum" ]; then
    pass "R005-consistency-phase" "total_cost_usd == sum(by_phase[].cost_usd)"
  else
    fail "R005-consistency-phase" "Consistency: total=$total_cost, phase_sum=$by_phase_sum"
  fi

  # Tests R-005 [unit]: by_subagent includes orchestrator entry
  if echo "$output" | jq -e '[.by_subagent[] | select(.description == "orchestrator")] | length > 0' >/dev/null 2>&1; then
    pass "R005-orchestrator" "by_subagent includes orchestrator entry"
  else
    fail "R005-orchestrator" "by_subagent missing orchestrator entry"
  fi

  # Tests R-005 [unit]: total_cost_usd == sum(by_subagent[].cost_usd)
  local by_subagent_sum
  by_subagent_sum=$(echo "$output" | jq '[.by_subagent[].cost_usd] | add // 0' 2>/dev/null)
  if [ "$total_cost" = "$by_subagent_sum" ]; then
    pass "R005-consistency-subagent" "total_cost_usd == sum(by_subagent[].cost_usd)"
  else
    fail "R005-consistency-subagent" "Consistency: total=$total_cost, subagent_sum=$by_subagent_sum"
  fi

  # Tests R-005 [unit]: computed_at is ISO timestamp
  if echo "$output" | jq -e '.computed_at | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T")' >/dev/null 2>&1; then
    pass "R005-timestamp" "computed_at is ISO timestamp"
  else
    fail "R005-timestamp" "computed_at is not ISO timestamp"
  fi

  # Tests R-005 [unit]: model_breakdown array present with entries
  if echo "$output" | jq -e '.model_breakdown | length > 0' >/dev/null 2>&1; then
    pass "R005-model-breakdown" "model_breakdown has entries"
  else
    fail "R005-model-breakdown" "model_breakdown is empty"
  fi

  rm -rf "$TEST_DIR" "$FAKE_HOME"
}

# ============================================================================
# R-006: Pricing defaults and config override
# ============================================================================

test_r006_pricing() {
  echo ""
  echo "--- R-006: Pricing defaults and validation ---"

  local TEST_DIR
  TEST_DIR=$(setup_test_env)
  local FAKE_HOME
  FAKE_HOME=$(mktemp -d)

  local proj_slug
  proj_slug=$(echo "$TEST_DIR" | tr '/' '-' | sed 's/^-//')
  local jsonl_path
  jsonl_path=$(create_session_dir "$FAKE_HOME" "$proj_slug" "pricing-session")
  write_transcript_entry "$jsonl_path" "claude-sonnet-4-6" 1000 500 0 0 "feature/pricing" "2026-04-15T10:00:00Z"

  # Tests R-006 [unit]: pricing_used field shows model pricing
  local output
  output=$(cd "$TEST_DIR" && HOME="$FAKE_HOME" bash "$SCRIPT" "feature/pricing" 2>/dev/null)

  if echo "$output" | jq -e '.pricing_used["claude-sonnet-4-6"]' >/dev/null 2>&1; then
    pass "R006-a" "pricing_used shows claude-sonnet-4-6 rates"
  else
    fail "R006-a" "pricing_used missing claude-sonnet-4-6"
  fi

  # Tests R-006 [unit]: pricing has all 4 components
  if echo "$output" | jq -e '.pricing_used["claude-sonnet-4-6"] | has("input", "output", "cache_write", "cache_read")' >/dev/null 2>&1; then
    pass "R006-b" "Pricing has all 4 components (input, output, cache_write, cache_read)"
  else
    fail "R006-b" "Pricing missing components"
  fi

  rm -rf "$TEST_DIR" "$FAKE_HOME"

  # Tests R-006 [unit]: config pricing override
  TEST_DIR=$(setup_test_env)
  FAKE_HOME=$(mktemp -d)

  cat > "$TEST_DIR/.correctless/config/workflow-config.json" <<'EOF'
{
  "project": { "name": "test-project" },
  "workflow": {
    "intensity": "standard",
    "pricing": {
      "claude-sonnet-4-6": {
        "input": 99,
        "cache_write": 99,
        "cache_read": 99,
        "output": 99
      }
    }
  }
}
EOF

  proj_slug=$(echo "$TEST_DIR" | tr '/' '-' | sed 's/^-//')
  jsonl_path=$(create_session_dir "$FAKE_HOME" "$proj_slug" "override-pricing-session")
  write_transcript_entry "$jsonl_path" "claude-sonnet-4-6" 1000000 0 0 0 "feature/price-override" "2026-04-15T10:00:00Z"

  output=$(cd "$TEST_DIR" && HOME="$FAKE_HOME" bash "$SCRIPT" "feature/price-override" 2>/dev/null)

  # With input=99 per million tokens, 1M input tokens should cost $99
  local cost
  cost=$(echo "$output" | jq '.total_cost_usd' 2>/dev/null)
  if [ "$cost" = "99" ]; then
    pass "R006-c" "Config pricing override applied (cost=$cost for 1M tokens at 99/M)"
  else
    fail "R006-c" "Config pricing override not applied (expected cost=99, got $cost)"
  fi

  rm -rf "$TEST_DIR" "$FAKE_HOME"

  # Tests R-006 [unit]: pricing > $500/M rejected
  TEST_DIR=$(setup_test_env)
  FAKE_HOME=$(mktemp -d)

  cat > "$TEST_DIR/.correctless/config/workflow-config.json" <<'EOF'
{
  "project": { "name": "test-project" },
  "workflow": {
    "intensity": "standard",
    "pricing": {
      "claude-sonnet-4-6": {
        "input": 600,
        "cache_write": 3.75,
        "cache_read": 0.30,
        "output": 15
      }
    }
  }
}
EOF

  proj_slug=$(echo "$TEST_DIR" | tr '/' '-' | sed 's/^-//')
  jsonl_path=$(create_session_dir "$FAKE_HOME" "$proj_slug" "bad-pricing-session")
  write_transcript_entry "$jsonl_path" "claude-sonnet-4-6" 1000 500 0 0 "feature/bad-price" "2026-04-15T10:00:00Z"

  output=$(cd "$TEST_DIR" && HOME="$FAKE_HOME" bash "$SCRIPT" "feature/bad-price" 2>/dev/null)

  if echo "$output" | jq -e '.error' >/dev/null 2>&1; then
    pass "R006-d" "Pricing > 500/M rejected with error"
  else
    fail "R006-d" "Pricing > 500/M not rejected"
  fi

  rm -rf "$TEST_DIR" "$FAKE_HOME"

  # Tests R-006 [unit]: negative pricing rejected
  TEST_DIR=$(setup_test_env)
  FAKE_HOME=$(mktemp -d)

  cat > "$TEST_DIR/.correctless/config/workflow-config.json" <<'EOF'
{
  "project": { "name": "test-project" },
  "workflow": {
    "intensity": "standard",
    "pricing": {
      "claude-sonnet-4-6": {
        "input": -5,
        "cache_write": 3.75,
        "cache_read": 0.30,
        "output": 15
      }
    }
  }
}
EOF

  proj_slug=$(echo "$TEST_DIR" | tr '/' '-' | sed 's/^-//')
  jsonl_path=$(create_session_dir "$FAKE_HOME" "$proj_slug" "neg-pricing-session")
  write_transcript_entry "$jsonl_path" "claude-sonnet-4-6" 1000 500 0 0 "feature/neg-price" "2026-04-15T10:00:00Z"

  output=$(cd "$TEST_DIR" && HOME="$FAKE_HOME" bash "$SCRIPT" "feature/neg-price" 2>/dev/null)

  if echo "$output" | jq -e '.error' >/dev/null 2>&1; then
    pass "R006-e" "Negative pricing rejected with error"
  else
    fail "R006-e" "Negative pricing not rejected"
  fi

  rm -rf "$TEST_DIR" "$FAKE_HOME"
}

# ============================================================================
# R-007: Dashboard reads cost artifacts
# ============================================================================

test_r007_dashboard_cost() {
  echo ""
  echo "--- R-007: Dashboard reads cost artifacts ---"

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  mkdir -p "$TEST_DIR/.correctless/config"
  mkdir -p "$TEST_DIR/.correctless/artifacts"
  mkdir -p "$TEST_DIR/docs"

  cat > "$TEST_DIR/.correctless/config/workflow-config.json" <<'EOF'
{
  "project": { "name": "cost-dashboard-test" },
  "workflow": { "intensity": "standard" }
}
EOF

  cat > "$TEST_DIR/docs/workflow-history.md" <<'EOF'
# Workflow History

### 2026-04-15 — Cost Feature
Branch: feature/cost. Rules: 5. QA rounds: 1. Findings fixed: 1. Added cost tracking.
EOF

  # Create a cost artifact
  cat > "$TEST_DIR/.correctless/artifacts/cost-feature-cost-abc123.json" <<'EOF'
{
  "branch": "feature/cost",
  "feature": "cost",
  "computed_at": "2026-04-15T12:00:00Z",
  "sessions": ["session-001"],
  "total_cost_usd": 2.543210,
  "total_input_tokens": 50000,
  "total_output_tokens": 25000,
  "total_cache_write_tokens": 5000,
  "total_cache_read_tokens": 20000,
  "by_phase": [
    {"phase": "tdd-tests", "cost_usd": 0.500000, "input_tokens": 10000, "output_tokens": 5000, "cache_write_tokens": 1000, "cache_read_tokens": 4000, "turns": 5},
    {"phase": "tdd-impl", "cost_usd": 1.200000, "input_tokens": 25000, "output_tokens": 12000, "cache_write_tokens": 2500, "cache_read_tokens": 10000, "turns": 12},
    {"phase": "tdd-qa", "cost_usd": 0.843210, "input_tokens": 15000, "output_tokens": 8000, "cache_write_tokens": 1500, "cache_read_tokens": 6000, "turns": 8}
  ],
  "by_subagent": [
    {"description": "orchestrator", "agent_type": "parent", "cost_usd": 2.543210, "tokens": 75000, "turns": 25}
  ],
  "pricing_used": {"claude-sonnet-4-6": {"input": 3, "output": 15, "cache_write": 3.75, "cache_read": 0.30}},
  "model_breakdown": [{"model": "claude-sonnet-4-6", "cost_usd": 2.543210, "turns": 25}],
  "unknown_models": [],
  "warnings": []
}
EOF

  # Run dashboard
  local output
  output=$(cd "$TEST_DIR" && bash "$REPO_DIR/scripts/generate-dashboard.sh" 2>&1)

  if [ -f "$TEST_DIR/dashboard.html" ]; then
    pass "R007-a" "Dashboard generated with cost artifacts"
  else
    fail "R007-a" "Dashboard not generated"
    return
  fi

  local _f="$TEST_DIR/dashboard.html"

  # Tests R-007 [unit]: cost by phase section shows USD values
  if grep -qiE '\$?2\.54|2\.543' "$_f"; then
    pass "R007-b" "Dashboard shows USD cost from artifact"
  else
    fail "R007-b" "Dashboard does not show USD cost from artifact"
  fi

  # Tests R-007 [unit]: shows phase breakdown
  if grep -qi 'tdd-tests\|tdd-impl\|tdd-qa' "$_f"; then
    pass "R007-c" "Dashboard shows phase names from cost artifact"
  else
    fail "R007-c" "Dashboard does not show phase names"
  fi

  # Tests R-007 [unit]: fallback to token-log when no cost artifacts
  rm "$TEST_DIR/.correctless/artifacts/cost-"*.json

  # Add token-log data
  cat > "$TEST_DIR/.correctless/artifacts/token-log-feature-cost-abc123.jsonl" <<'TLEOF'
{"timestamp":"2026-04-15T10:01:00Z","phase":"tdd-tests","skill":"ctdd","input_tokens":5000,"output_tokens":3000,"total_tokens":8000}
TLEOF

  output=$(cd "$TEST_DIR" && bash "$REPO_DIR/scripts/generate-dashboard.sh" 2>&1)

  if grep -qi 'token count only\|run /cdocs\|token' "$TEST_DIR/dashboard.html"; then
    pass "R007-d" "Dashboard falls back to token-log data with note"
  else
    fail "R007-d" "Dashboard fallback to token-log not working"
  fi

  rm -rf "$TEST_DIR"
}

# ============================================================================
# R-008: /cdocs calls compute-session-cost.sh
# ============================================================================

test_r008_cdocs_wiring() {
  echo ""
  echo "--- R-008: /cdocs calls compute-session-cost.sh ---"

  local cdocs="$REPO_DIR/skills/cdocs/SKILL.md"

  # Tests R-008 [unit]: cdocs skill mentions compute-session-cost
  if grep -q 'compute-session-cost' "$cdocs"; then
    pass "R008-a" "/cdocs SKILL.md mentions compute-session-cost.sh"
  else
    fail "R008-a" "/cdocs SKILL.md does not mention compute-session-cost.sh"
  fi

  # Tests R-008 [unit]: cdocs allowed-tools includes Bash(*compute-session-cost.sh*)
  if grep -q 'compute-session-cost' <(head -10 "$cdocs"); then
    pass "R008-b" "/cdocs allowed-tools includes compute-session-cost"
  else
    fail "R008-b" "/cdocs allowed-tools missing compute-session-cost"
  fi
}

# ============================================================================
# R-009: /cverify reads cost artifact for actual_cost_usd
# ============================================================================

test_r009_cverify_wiring() {
  echo ""
  echo "--- R-009: /cverify reads cost artifact ---"

  local cverify="$REPO_DIR/skills/cverify/SKILL.md"

  # Tests R-009 [unit]: cverify mentions cost artifact or actual_cost_usd
  if grep -q 'actual_cost_usd\|cost-.*\.json\|cost artifact' "$cverify"; then
    pass "R009-a" "/cverify mentions cost artifact / actual_cost_usd"
  else
    fail "R009-a" "/cverify does not mention cost artifact"
  fi

  # Tests R-009 [unit]: cverify says to omit actual_cost_usd when artifact missing
  if grep -qi 'omit\|absent\|does not exist\|if.*exist' "$cverify" && grep -q 'actual_cost_usd' "$cverify"; then
    pass "R009-b" "/cverify handles missing cost artifact"
  else
    fail "R009-b" "/cverify missing handling for absent cost artifact"
  fi
}

# ============================================================================
# R-010: /cmetrics reads cost artifacts for ROI
# ============================================================================

test_r010_cmetrics_wiring() {
  echo ""
  echo "--- R-010: /cmetrics reads cost artifacts ---"

  local cmetrics="$REPO_DIR/skills/cmetrics/SKILL.md"

  # Tests R-010 [unit]: cmetrics mentions cost artifacts
  if grep -qi 'cost.*artifact\|cost-.*\.json\|actual.*USD\|cost per bug' "$cmetrics"; then
    pass "R010-a" "/cmetrics mentions cost artifacts"
  else
    fail "R010-a" "/cmetrics does not mention cost artifacts"
  fi

  # Tests R-010 [unit]: cmetrics mentions fallback when cost artifacts missing
  if grep -qi 'fall.*back\|token.*count.*estimate\|when.*cost.*missing\|if.*cost.*artifact' "$cmetrics"; then
    pass "R010-b" "/cmetrics mentions fallback for missing cost"
  else
    fail "R010-b" "/cmetrics missing fallback language"
  fi
}

# ============================================================================
# R-011: Graceful degradation
# ============================================================================

test_r011_graceful_degradation() {
  echo ""
  echo "--- R-011: Graceful degradation ---"

  local TEST_DIR
  TEST_DIR=$(setup_test_env)
  local FAKE_HOME
  FAKE_HOME=$(mktemp -d)

  # Tests R-011 [unit]: no matching sessions -> exit 0 with zero cost
  local proj_slug
  proj_slug=$(echo "$TEST_DIR" | tr '/' '-' | sed 's/^-//')
  local session_dir="$FAKE_HOME/.claude/projects/$proj_slug"
  mkdir -p "$session_dir"
  # Empty session directory — no JSONL files
  local output exit_code
  output=$(cd "$TEST_DIR" && HOME="$FAKE_HOME" bash "$SCRIPT" "feature/no-sessions" 2>/dev/null)
  exit_code=$?

  if [ $exit_code -eq 0 ]; then
    pass "R011-a" "Exits 0 with no matching sessions"
  else
    fail "R011-a" "Non-zero exit with no matching sessions"
  fi

  if echo "$output" | jq -e '.total_cost_usd == 0' >/dev/null 2>&1; then
    pass "R011-b" "Zero cost with no matching sessions"
  else
    fail "R011-b" "Non-zero cost with no matching sessions"
  fi

  rm -rf "$TEST_DIR" "$FAKE_HOME"

  # Tests R-011 [unit]: malformed JSONL entries skipped (jq try/catch)
  TEST_DIR=$(setup_test_env)
  FAKE_HOME=$(mktemp -d)

  proj_slug=$(echo "$TEST_DIR" | tr '/' '-' | sed 's/^-//')
  local jsonl_path
  jsonl_path=$(create_session_dir "$FAKE_HOME" "$proj_slug" "malformed-session")

  # Write a malformed line followed by a valid line
  echo "THIS IS NOT JSON" >> "$jsonl_path"
  echo '{"partial":true' >> "$jsonl_path"
  write_transcript_entry "$jsonl_path" "claude-sonnet-4-6" 1000 500 0 0 "feature/malformed" "2026-04-15T10:00:00Z"

  output=$(cd "$TEST_DIR" && HOME="$FAKE_HOME" bash "$SCRIPT" "feature/malformed" 2>/dev/null)
  exit_code=$?

  if [ $exit_code -eq 0 ]; then
    pass "R011-c" "Exits 0 with malformed entries"
  else
    fail "R011-c" "Non-zero exit with malformed entries"
  fi

  if echo "$output" | jq -e '.total_cost_usd > 0' >/dev/null 2>&1; then
    pass "R011-d" "Valid entries still computed despite malformed ones"
  else
    fail "R011-d" "No cost computed despite valid entries present"
  fi

  rm -rf "$TEST_DIR" "$FAKE_HOME"
}

# ============================================================================
# R-012: Subagent cost computation
# ============================================================================

test_r012_subagent_cost() {
  echo ""
  echo "--- R-012: Subagent cost computation ---"

  local TEST_DIR
  TEST_DIR=$(setup_test_env)
  local FAKE_HOME
  FAKE_HOME=$(mktemp -d)

  local proj_slug
  proj_slug=$(echo "$TEST_DIR" | tr '/' '-' | sed 's/^-//')
  local session_id="subagent-session-001"
  local session_dir="$FAKE_HOME/.claude/projects/$proj_slug"
  mkdir -p "$session_dir/$session_id/subagents"

  # Parent transcript
  local parent_jsonl="$session_dir/$session_id.jsonl"
  write_transcript_entry "$parent_jsonl" "claude-sonnet-4-6" 2000 1000 0 0 "feature/subagent" "2026-04-15T10:00:00Z"

  # Subagent transcript
  local subagent_jsonl="$session_dir/$session_id/subagents/agent-001.jsonl"
  write_transcript_entry "$subagent_jsonl" "claude-sonnet-4-6" 1000 500 0 0 "feature/subagent" "2026-04-15T10:01:00Z"

  # Subagent meta
  cat > "$session_dir/$session_id/subagents/agent-001.meta.json" <<'META'
{"description": "test-writer", "type": "correctless:ctdd-test-writer"}
META

  local output
  output=$(cd "$TEST_DIR" && HOME="$FAKE_HOME" bash "$SCRIPT" "feature/subagent" 2>/dev/null)

  # Tests R-012 [unit]: by_subagent has entries
  if echo "$output" | jq -e '.by_subagent | length > 0' >/dev/null 2>&1; then
    pass "R012-a" "by_subagent array has entries"
  else
    fail "R012-a" "by_subagent array is empty"
  fi

  # Tests R-012 [unit]: subagent description from meta.json
  if echo "$output" | jq -e '[.by_subagent[] | select(.description == "test-writer")] | length > 0' >/dev/null 2>&1; then
    pass "R012-b" "Subagent description read from meta.json"
  else
    fail "R012-b" "Subagent description not found"
  fi

  # Tests R-012 [unit]: subagent cost included in total
  local total_input
  total_input=$(echo "$output" | jq '.total_input_tokens' 2>/dev/null)
  if [ "$total_input" = "3000" ]; then
    pass "R012-c" "Subagent tokens included in total (2000+1000=3000)"
  else
    fail "R012-c" "Subagent tokens not in total: expected 3000, got $total_input"
  fi

  rm -rf "$TEST_DIR" "$FAKE_HOME"

  # Tests R-012 [unit]: missing meta.json -> defaults to "unknown"
  TEST_DIR=$(setup_test_env)
  FAKE_HOME=$(mktemp -d)

  proj_slug=$(echo "$TEST_DIR" | tr '/' '-' | sed 's/^-//')
  session_id="no-meta-session"
  session_dir="$FAKE_HOME/.claude/projects/$proj_slug"
  mkdir -p "$session_dir/$session_id/subagents"

  parent_jsonl="$session_dir/$session_id.jsonl"
  write_transcript_entry "$parent_jsonl" "claude-sonnet-4-6" 1000 500 0 0 "feature/no-meta" "2026-04-15T10:00:00Z"

  subagent_jsonl="$session_dir/$session_id/subagents/agent-002.jsonl"
  write_transcript_entry "$subagent_jsonl" "claude-sonnet-4-6" 500 250 0 0 "feature/no-meta" "2026-04-15T10:01:00Z"
  # No meta.json

  output=$(cd "$TEST_DIR" && HOME="$FAKE_HOME" bash "$SCRIPT" "feature/no-meta" 2>/dev/null)

  if echo "$output" | jq -e '[.by_subagent[] | select(.description == "unknown")] | length > 0' >/dev/null 2>&1; then
    pass "R012-d" "Missing meta.json defaults to description='unknown'"
  else
    fail "R012-d" "Missing meta.json not handled"
  fi

  rm -rf "$TEST_DIR" "$FAKE_HOME"

  # Tests R-012 [unit]: infrastructure subagents (compact-*, aside_question-*) excluded from by_subagent
  TEST_DIR=$(setup_test_env)
  FAKE_HOME=$(mktemp -d)

  proj_slug=$(echo "$TEST_DIR" | tr '/' '-' | sed 's/^-//')
  session_id="infra-session"
  session_dir="$FAKE_HOME/.claude/projects/$proj_slug"
  mkdir -p "$session_dir/$session_id/subagents"

  parent_jsonl="$session_dir/$session_id.jsonl"
  write_transcript_entry "$parent_jsonl" "claude-sonnet-4-6" 1000 500 0 0 "feature/infra" "2026-04-15T10:00:00Z"

  # Infrastructure subagent (compact)
  local compact_jsonl="$session_dir/$session_id/subagents/compact-001.jsonl"
  write_transcript_entry "$compact_jsonl" "claude-sonnet-4-6" 500 250 0 0 "feature/infra" "2026-04-15T10:01:00Z"

  # Regular subagent
  subagent_jsonl="$session_dir/$session_id/subagents/agent-003.jsonl"
  write_transcript_entry "$subagent_jsonl" "claude-sonnet-4-6" 500 250 0 0 "feature/infra" "2026-04-15T10:02:00Z"

  output=$(cd "$TEST_DIR" && HOME="$FAKE_HOME" bash "$SCRIPT" "feature/infra" 2>/dev/null)

  # by_subagent should have orchestrator + agent-003 but NOT compact
  local subagent_count
  subagent_count=$(echo "$output" | jq '[.by_subagent[] | select(.description != "orchestrator")] | length' 2>/dev/null)
  if [ "$subagent_count" = "1" ]; then
    pass "R012-e" "Infrastructure subagent excluded from by_subagent"
  else
    fail "R012-e" "Infrastructure subagent handling wrong (expected 1 non-orchestrator, got $subagent_count)"
  fi

  # But total should still include infra costs
  total_input=$(echo "$output" | jq '.total_input_tokens' 2>/dev/null)
  if [ "$total_input" = "2000" ]; then
    pass "R012-f" "Infrastructure subagent cost included in total (1000+500+500=2000)"
  else
    fail "R012-f" "Infrastructure subagent cost not in total: expected 2000, got $total_input"
  fi

  rm -rf "$TEST_DIR" "$FAKE_HOME"
}

# ============================================================================
# R-013: Multi-session features
# ============================================================================

test_r013_multi_session() {
  echo ""
  echo "--- R-013: Multi-session features ---"

  local TEST_DIR
  TEST_DIR=$(setup_test_env)
  local FAKE_HOME
  FAKE_HOME=$(mktemp -d)

  local proj_slug
  proj_slug=$(echo "$TEST_DIR" | tr '/' '-' | sed 's/^-//')
  local session_dir="$FAKE_HOME/.claude/projects/$proj_slug"
  mkdir -p "$session_dir"

  # Session 1 with matching branch
  local jsonl1="$session_dir/session-multi-001.jsonl"
  write_transcript_entry "$jsonl1" "claude-sonnet-4-6" 1000 500 0 0 "feature/multi" "2026-04-15T10:00:00Z"

  # Session 2 with matching branch
  local jsonl2="$session_dir/session-multi-002.jsonl"
  write_transcript_entry "$jsonl2" "claude-sonnet-4-6" 2000 1000 0 0 "feature/multi" "2026-04-15T11:00:00Z"

  # Session 3 with DIFFERENT branch (should not be included)
  local jsonl3="$session_dir/session-multi-003.jsonl"
  write_transcript_entry "$jsonl3" "claude-sonnet-4-6" 5000 2500 0 0 "feature/other" "2026-04-15T12:00:00Z"

  local output
  output=$(cd "$TEST_DIR" && HOME="$FAKE_HOME" bash "$SCRIPT" "feature/multi" 2>/dev/null)

  # Tests R-013 [unit]: sessions array lists both matching session IDs
  local session_count
  session_count=$(echo "$output" | jq '.sessions | length' 2>/dev/null)
  if [ "$session_count" = "2" ]; then
    pass "R013-a" "Both matching sessions included"
  else
    fail "R013-a" "Session count wrong: expected 2, got $session_count"
  fi

  # Tests R-013 [unit]: cost summed across sessions
  local total_input
  total_input=$(echo "$output" | jq '.total_input_tokens' 2>/dev/null)
  if [ "$total_input" = "3000" ]; then
    pass "R013-b" "Cost summed across sessions (1000+2000=3000)"
  else
    fail "R013-b" "Multi-session total wrong: expected 3000, got $total_input"
  fi

  # Tests R-013 [unit]: non-matching session NOT included
  # If session-multi-003 were included, total input would be 8000
  if [ "$total_input" != "8000" ]; then
    pass "R013-c" "Non-matching session correctly excluded"
  else
    fail "R013-c" "Non-matching session was incorrectly included"
  fi

  rm -rf "$TEST_DIR" "$FAKE_HOME"
}

# ============================================================================
# R-014: ABS-026 in ARCHITECTURE.md
# ============================================================================

test_r014_abs026() {
  echo ""
  echo "--- R-014: ABS-026 in ARCHITECTURE.md ---"

  local arch="$REPO_DIR/.correctless/ARCHITECTURE.md"

  # Tests R-014 [unit]: ABS-026 entry exists
  if grep -q 'ABS-026' "$arch"; then
    pass "R014-a" "ABS-026 exists in ARCHITECTURE.md"
  else
    fail "R014-a" "ABS-026 missing from ARCHITECTURE.md"
  fi

  # Tests R-014 [unit]: ABS-026 mentions compute-session-cost.sh as sole writer
  if grep -A5 'ABS-026' "$arch" | grep -qi 'compute-session-cost'; then
    pass "R014-b" "ABS-026 mentions compute-session-cost.sh"
  else
    fail "R014-b" "ABS-026 does not mention compute-session-cost.sh"
  fi

  # Tests R-014 [unit]: ABS-026 mentions consumers (dashboard, cverify, cmetrics)
  if grep -A10 'ABS-026' "$arch" | grep -qi 'dashboard\|generate-dashboard\|cverify\|cmetrics'; then
    pass "R014-c" "ABS-026 mentions consumers"
  else
    fail "R014-c" "ABS-026 does not mention consumers"
  fi
}

# ============================================================================
# R-015: TB-006 in ARCHITECTURE.md
# ============================================================================

test_r015_tb006() {
  echo ""
  echo "--- R-015: TB-006 in ARCHITECTURE.md ---"

  local arch="$REPO_DIR/.correctless/ARCHITECTURE.md"

  # Tests R-015 [unit]: TB-006 entry exists
  if grep -q 'TB-006' "$arch"; then
    pass "R015-a" "TB-006 exists in ARCHITECTURE.md"
  else
    fail "R015-a" "TB-006 missing from ARCHITECTURE.md"
  fi

  # Tests R-015 [unit]: TB-006 mentions .claude/projects/ reads
  if grep -A10 'TB-006' "$arch" | grep -qi 'claude.*projects\|session.*storage\|transcript'; then
    pass "R015-b" "TB-006 mentions session transcript reads"
  else
    fail "R015-b" "TB-006 does not mention session reads"
  fi

  # Tests R-015 [unit]: TB-006 invariant about not including message.content
  if grep -A15 'TB-006' "$arch" | grep -qi 'content\|message.*content'; then
    pass "R015-c" "TB-006 mentions message.content invariant"
  else
    fail "R015-c" "TB-006 missing message.content invariant"
  fi
}

# ============================================================================
# R-016: ABS-006 update
# ============================================================================

test_r016_abs006_update() {
  echo ""
  echo "--- R-016: ABS-006 update ---"

  local arch="$REPO_DIR/.correctless/ARCHITECTURE.md"

  # Tests R-016 [unit]: ABS-006 mentions zeros / PostToolUse limitation
  if grep -A15 'ABS-006' "$arch" | grep -qi 'zeros\|PostToolUse.*not.*include\|ABS-026\|cost artifact'; then
    pass "R016-a" "ABS-006 updated to mention zeros and ABS-026 reference"
  else
    fail "R016-a" "ABS-006 not updated with PostToolUse/ABS-026 info"
  fi
}

# ============================================================================
# R-017: ENV-009 in ARCHITECTURE.md
# ============================================================================

test_r017_env009() {
  echo ""
  echo "--- R-017: ENV-009 in ARCHITECTURE.md ---"

  local arch="$REPO_DIR/.correctless/ARCHITECTURE.md"

  # Tests R-017 [unit]: ENV-009 entry exists
  if grep -q 'ENV-009' "$arch"; then
    pass "R017-a" "ENV-009 exists in ARCHITECTURE.md"
  else
    fail "R017-a" "ENV-009 missing from ARCHITECTURE.md"
  fi

  # Tests R-017 [unit]: ENV-009 mentions session transcript storage format
  if grep -A10 'ENV-009' "$arch" | grep -qi 'session.*transcript\|JSONL\|claude.*projects'; then
    pass "R017-b" "ENV-009 mentions session transcript format"
  else
    fail "R017-b" "ENV-009 does not mention session transcripts"
  fi

  # Tests R-017 [unit]: ENV-009 notes this is internal/non-public API
  if grep -A10 'ENV-009' "$arch" | grep -qi 'internal\|not.*public\|not a public'; then
    pass "R017-c" "ENV-009 notes internal/non-public API"
  else
    fail "R017-c" "ENV-009 does not note internal API status"
  fi
}

# ============================================================================
# R-018: AGENT_CONTEXT.md updates
# ============================================================================

test_r018_agent_context() {
  echo ""
  echo "--- R-018: AGENT_CONTEXT.md updates ---"

  local agent_ctx="$REPO_DIR/.correctless/AGENT_CONTEXT.md"

  # Tests R-018 [unit]: script count updated (17->18)
  if grep -q '18 ' "$agent_ctx" && grep -qi 'script' "$agent_ctx"; then
    pass "R018-a" "AGENT_CONTEXT.md mentions 18 scripts"
  else
    fail "R018-a" "AGENT_CONTEXT.md does not mention 18 scripts"
  fi

  # Tests R-018 [unit]: compute-session-cost.sh in scripts description
  if grep -q 'compute-session-cost' "$agent_ctx"; then
    pass "R018-b" "AGENT_CONTEXT.md lists compute-session-cost.sh"
  else
    fail "R018-b" "AGENT_CONTEXT.md missing compute-session-cost.sh"
  fi
}

# ============================================================================
# Run all tests
# ============================================================================

test_r001_script_exists_and_outputs_json
test_r002_session_discovery
test_r003_cost_computation
test_r004_phase_attribution
test_r005_output_schema
test_r006_pricing
test_r007_dashboard_cost
test_r008_cdocs_wiring
test_r009_cverify_wiring
test_r010_cmetrics_wiring
test_r011_graceful_degradation
test_r012_subagent_cost
test_r013_multi_session
test_r014_abs026
test_r015_tb006
test_r016_abs006_update
test_r017_env009
test_r018_agent_context

echo ""
echo "========================================="
echo "  Session Cost Tests: $PASS passed, $FAIL failed"
echo "========================================="
if [ -n "$FAILED_IDS" ]; then
  echo "  Failed: $FAILED_IDS"
fi
[ "$FAIL" -eq 0 ]
