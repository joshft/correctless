#!/usr/bin/env bash
# Correctless — Sensitive File Guard PreToolUse Hook Tests
# Tests spec rules from .correctless/specs/sensitive-file-protection.md
# INV-001 through INV-010, PRH-001 through PRH-003, BND-001 through BND-004
# Run from repo root: bash tests/test-sensitive-file-guard.sh

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$REPO_DIR/hooks/sensitive-file-guard.sh"
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

assert_not_contains() {
  local desc="$1" unexpected="$2" actual="$3"
  if ! echo "$actual" | grep -qF "$unexpected"; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (unexpected output containing '$unexpected')"
    FAIL=$((FAIL + 1))
  fi
}

# Run hook with JSON on stdin, capture exit code and stderr separately.
# Output format: "EXIT_CODE<newline>STDERR_OUTPUT"
# The hook script path is $HOOK; the test_dir provides the project root context.
run_hook_capture() {
  local json_input="$1"
  local exit_code
  local stderr_output

  # Run the hook. Redirect stdout to /dev/null (hook should not produce stdout).
  # Capture stderr into a variable.
  stderr_output="$(echo "$json_input" | bash "$HOOK" 2>&1 >/dev/null)" && exit_code=0 || exit_code=$?

  echo "${exit_code}:${stderr_output}"
}

# Extract exit code from run_hook_capture output
extract_exit() {
  echo "$1" | head -1 | cut -d: -f1
}

# Extract stderr from run_hook_capture output
extract_stderr() {
  echo "$1" | cut -d: -f2-
}

# Create a temporary test project directory with optional config
setup_test_env() {
  local test_dir="$1"
  rm -rf "$test_dir"
  mkdir -p "$test_dir/.correctless/config"
}

# Create a workflow-config.json with optional custom_patterns
setup_config_with_patterns() {
  local test_dir="$1"
  shift
  # Remaining args are custom pattern strings
  local patterns_json="[]"
  if [ $# -gt 0 ]; then
    patterns_json="["
    local first=true
    for p in "$@"; do
      if [ "$first" = "true" ]; then
        first=false
      else
        patterns_json+=","
      fi
      patterns_json+="\"$p\""
    done
    patterns_json+="]"
  fi

  cat > "$test_dir/.correctless/config/workflow-config.json" <<EOF
{
  "protected_files": {
    "custom_patterns": $patterns_json
  }
}
EOF
}

# ---------------------------------------------------------------------------
# INV-001: Block Edit, Write, MultiEdit, NotebookEdit, CreateFile targeting
#          sensitive files (.env)
# ---------------------------------------------------------------------------

test_inv001_block_write_tools_on_sensitive_files() {
  echo ""
  echo "=== INV-001: Block write tools targeting sensitive files ==="

  local test_dir="/tmp/correctless-sfg-inv001-$$"
  setup_test_env "$test_dir"
  cd "$test_dir" || return

  # Edit targeting .env -> exit 2
  local result
  result="$(run_hook_capture '{"tool_name":"Edit","tool_input":{"file_path":".env","old_string":"FOO=bar","new_string":"FOO=baz"}}')"
  assert_eq "INV-001: Edit .env blocked" "2" "$(extract_exit "$result")"

  # Write targeting .env -> exit 2
  result="$(run_hook_capture '{"tool_name":"Write","tool_input":{"file_path":".env","content":"SECRET=x"}}')"
  assert_eq "INV-001: Write .env blocked" "2" "$(extract_exit "$result")"

  # MultiEdit targeting .env -> exit 2
  result="$(run_hook_capture '{"tool_name":"MultiEdit","tool_input":{"edits":[{"file_path":".env","old_string":"A","new_string":"B"}]}}')"
  assert_eq "INV-001: MultiEdit .env blocked" "2" "$(extract_exit "$result")"

  # NotebookEdit targeting .env -> exit 2
  result="$(run_hook_capture '{"tool_name":"NotebookEdit","tool_input":{"file_path":".env","cell_index":0}}')"
  assert_eq "INV-001: NotebookEdit .env blocked" "2" "$(extract_exit "$result")"

  # CreateFile targeting .env -> exit 2
  result="$(run_hook_capture '{"tool_name":"CreateFile","tool_input":{"file_path":".env","content":"NEW=val"}}')"
  assert_eq "INV-001: CreateFile .env blocked" "2" "$(extract_exit "$result")"

  # MultiEdit with one sensitive + one normal file -> exit 2 (any match blocks all)
  result="$(run_hook_capture '{"tool_name":"MultiEdit","tool_input":{"edits":[{"file_path":"src/main.ts","old_string":"a","new_string":"b"},{"file_path":".env","old_string":"A","new_string":"B"}]}}')"
  assert_eq "INV-001: MultiEdit mixed sensitive+normal blocked" "2" "$(extract_exit "$result")"

  rm -rf "$test_dir"
}

# ---------------------------------------------------------------------------
# INV-002: Block Bash write commands to sensitive files
# ---------------------------------------------------------------------------

test_inv002_block_bash_writes_to_sensitive_files() {
  echo ""
  echo "=== INV-002: Block Bash write commands to sensitive files ==="

  local test_dir="/tmp/correctless-sfg-inv002-$$"
  setup_test_env "$test_dir"
  cd "$test_dir" || return

  local result

  # cat x > .env -> exit 2
  result="$(run_hook_capture '{"tool_name":"Bash","tool_input":{"command":"cat creds.txt > .env"}}')"
  assert_eq "INV-002: cat redirect to .env blocked" "2" "$(extract_exit "$result")"

  # cp .env backup -> exit 2
  result="$(run_hook_capture '{"tool_name":"Bash","tool_input":{"command":"cp .env backup.txt"}}')"
  assert_eq "INV-002: cp .env (source) blocked" "2" "$(extract_exit "$result")"

  # mv .env .env.bak -> exit 2
  result="$(run_hook_capture '{"tool_name":"Bash","tool_input":{"command":"mv .env .env.bak"}}')"
  assert_eq "INV-002: mv .env blocked" "2" "$(extract_exit "$result")"

  # tee .env -> exit 2
  result="$(run_hook_capture '{"tool_name":"Bash","tool_input":{"command":"echo x | tee .env"}}')"
  assert_eq "INV-002: tee .env blocked" "2" "$(extract_exit "$result")"

  # echo x >> .env -> exit 2
  result="$(run_hook_capture '{"tool_name":"Bash","tool_input":{"command":"echo secret >> .env"}}')"
  assert_eq "INV-002: echo append to .env blocked" "2" "$(extract_exit "$result")"

  # sed -i on .env -> exit 2
  result="$(run_hook_capture '{"tool_name":"Bash","tool_input":{"command":"sed -i s/old/new/ .env"}}')"
  assert_eq "INV-002: sed -i .env blocked" "2" "$(extract_exit "$result")"

  # Negative: Bash write to non-sensitive file -> exit 0
  result="$(run_hook_capture '{"tool_name":"Bash","tool_input":{"command":"cat data > output.txt"}}')"
  assert_eq "INV-002: cat > output.txt allowed (non-sensitive)" "0" "$(extract_exit "$result")"

  # Negative: cp between non-sensitive files -> exit 0
  result="$(run_hook_capture '{"tool_name":"Bash","tool_input":{"command":"cp src/old.ts src/new.ts"}}')"
  assert_eq "INV-002: cp non-sensitive files allowed" "0" "$(extract_exit "$result")"

  # Wildcard-matched sensitive: cat > api.secret -> exit 2
  result="$(run_hook_capture '{"tool_name":"Bash","tool_input":{"command":"cat data > api.secret"}}')"
  assert_eq "INV-002: cat > api.secret blocked (matches *.secret)" "2" "$(extract_exit "$result")"

  rm -rf "$test_dir"
}

# ---------------------------------------------------------------------------
# INV-003: Allow read operations on sensitive files
# ---------------------------------------------------------------------------

test_inv003_allow_read_operations() {
  echo ""
  echo "=== INV-003: Allow read operations on sensitive files ==="

  local test_dir="/tmp/correctless-sfg-inv003-$$"
  setup_test_env "$test_dir"
  cd "$test_dir" || return

  local result

  # Read tool with .env -> exit 0
  result="$(run_hook_capture '{"tool_name":"Read","tool_input":{"file_path":".env"}}')"
  assert_eq "INV-003: Read .env allowed" "0" "$(extract_exit "$result")"

  # Grep tool with .env -> exit 0
  result="$(run_hook_capture '{"tool_name":"Grep","tool_input":{"pattern":"SECRET","path":".env"}}')"
  assert_eq "INV-003: Grep .env allowed" "0" "$(extract_exit "$result")"

  # Glob tool -> exit 0
  result="$(run_hook_capture '{"tool_name":"Glob","tool_input":{"pattern":"*.env"}}')"
  assert_eq "INV-003: Glob allowed" "0" "$(extract_exit "$result")"

  # cat .env (no redirect) -> exit 0
  result="$(run_hook_capture '{"tool_name":"Bash","tool_input":{"command":"cat .env"}}')"
  assert_eq "INV-003: cat .env (no redirect) allowed" "0" "$(extract_exit "$result")"

  # grep SECRET .env -> exit 0
  result="$(run_hook_capture '{"tool_name":"Bash","tool_input":{"command":"grep SECRET .env"}}')"
  assert_eq "INV-003: grep SECRET .env allowed" "0" "$(extract_exit "$result")"

  rm -rf "$test_dir"
}

# ---------------------------------------------------------------------------
# INV-004: Hardcoded defaults work without config
# ---------------------------------------------------------------------------

test_inv004_defaults_without_config() {
  echo ""
  echo "=== INV-004: Hardcoded defaults work without config ==="

  local test_dir="/tmp/correctless-sfg-inv004-$$"
  setup_test_env "$test_dir"
  # Remove config to test defaults only
  rm -rf "$test_dir/.correctless"
  mkdir -p "$test_dir"
  cd "$test_dir" || return

  local result

  # Edit .env without config -> exit 2
  result="$(run_hook_capture '{"tool_name":"Edit","tool_input":{"file_path":".env","old_string":"a","new_string":"b"}}')"
  assert_eq "INV-004: .env blocked without config" "2" "$(extract_exit "$result")"

  # Edit id_rsa without config -> exit 2
  result="$(run_hook_capture '{"tool_name":"Edit","tool_input":{"file_path":"id_rsa","old_string":"a","new_string":"b"}}')"
  assert_eq "INV-004: id_rsa blocked without config" "2" "$(extract_exit "$result")"

  # Edit server.pem without config -> exit 2
  result="$(run_hook_capture '{"tool_name":"Edit","tool_input":{"file_path":"server.pem","old_string":"a","new_string":"b"}}')"
  assert_eq "INV-004: server.pem blocked without config" "2" "$(extract_exit "$result")"

  # Edit credentials.json without config -> exit 2
  result="$(run_hook_capture '{"tool_name":"Edit","tool_input":{"file_path":"credentials.json","old_string":"a","new_string":"b"}}')"
  assert_eq "INV-004: credentials.json blocked without config" "2" "$(extract_exit "$result")"

  # Edit secrets.yaml without config -> exit 2
  result="$(run_hook_capture '{"tool_name":"Edit","tool_input":{"file_path":"secrets.yaml","old_string":"a","new_string":"b"}}')"
  assert_eq "INV-004: secrets.yaml blocked without config" "2" "$(extract_exit "$result")"

  # Edit .env.production without config -> exit 2 (matches .env.*)
  result="$(run_hook_capture '{"tool_name":"Edit","tool_input":{"file_path":".env.production","old_string":"a","new_string":"b"}}')"
  assert_eq "INV-004: .env.production blocked without config" "2" "$(extract_exit "$result")"

  # Edit my-app.keystore without config -> exit 2 (matches *.keystore)
  result="$(run_hook_capture '{"tool_name":"Edit","tool_input":{"file_path":"my-app.keystore","old_string":"a","new_string":"b"}}')"
  assert_eq "INV-004: my-app.keystore blocked without config" "2" "$(extract_exit "$result")"

  rm -rf "$test_dir"
}

# ---------------------------------------------------------------------------
# INV-005: Custom patterns from config
# ---------------------------------------------------------------------------

test_inv005_custom_patterns() {
  echo ""
  echo "=== INV-005: Custom patterns from config ==="

  local test_dir="/tmp/correctless-sfg-inv005-$$"
  setup_test_env "$test_dir"
  setup_config_with_patterns "$test_dir" ".env.local" "config/production.yml" "*.tfvars"
  cd "$test_dir" || return

  local result

  # Custom pattern blocks matching file
  result="$(run_hook_capture '{"tool_name":"Edit","tool_input":{"file_path":".env.local","old_string":"a","new_string":"b"}}')"
  assert_eq "INV-005: Custom pattern .env.local blocked" "2" "$(extract_exit "$result")"

  # Custom pattern with path separator
  result="$(run_hook_capture '{"tool_name":"Edit","tool_input":{"file_path":"src/config/production.yml","old_string":"a","new_string":"b"}}')"
  assert_eq "INV-005: Custom pattern config/production.yml blocked" "2" "$(extract_exit "$result")"

  # Custom glob pattern
  result="$(run_hook_capture '{"tool_name":"Edit","tool_input":{"file_path":"infra/main.tfvars","old_string":"a","new_string":"b"}}')"
  assert_eq "INV-005: Custom pattern *.tfvars blocked" "2" "$(extract_exit "$result")"

  # Defaults still active when custom patterns present
  result="$(run_hook_capture '{"tool_name":"Edit","tool_input":{"file_path":".env","old_string":"a","new_string":"b"}}')"
  assert_eq "INV-005: Default .env still blocked with custom patterns" "2" "$(extract_exit "$result")"

  result="$(run_hook_capture '{"tool_name":"Edit","tool_input":{"file_path":"id_rsa","old_string":"a","new_string":"b"}}')"
  assert_eq "INV-005: Default id_rsa still blocked with custom patterns" "2" "$(extract_exit "$result")"

  rm -rf "$test_dir"
}

# ---------------------------------------------------------------------------
# INV-006: Non-sensitive files pass through
# ---------------------------------------------------------------------------

test_inv006_non_sensitive_files_pass() {
  echo ""
  echo "=== INV-006: Non-sensitive files pass through ==="

  local test_dir="/tmp/correctless-sfg-inv006-$$"
  setup_test_env "$test_dir"
  cd "$test_dir" || return

  local result

  # Edit main.ts -> exit 0
  result="$(run_hook_capture '{"tool_name":"Edit","tool_input":{"file_path":"src/main.ts","old_string":"a","new_string":"b"}}')"
  assert_eq "INV-006: Edit main.ts allowed" "0" "$(extract_exit "$result")"

  # Edit README.md -> exit 0
  result="$(run_hook_capture '{"tool_name":"Edit","tool_input":{"file_path":"README.md","old_string":"a","new_string":"b"}}')"
  assert_eq "INV-006: Edit README.md allowed" "0" "$(extract_exit "$result")"

  # Edit test.py -> exit 0
  result="$(run_hook_capture '{"tool_name":"Edit","tool_input":{"file_path":"test.py","old_string":"a","new_string":"b"}}')"
  assert_eq "INV-006: Edit test.py allowed" "0" "$(extract_exit "$result")"

  # Write to src/utils.go -> exit 0
  result="$(run_hook_capture '{"tool_name":"Write","tool_input":{"file_path":"src/utils.go","content":"package main"}}')"
  assert_eq "INV-006: Write utils.go allowed" "0" "$(extract_exit "$result")"

  # Bash write to normal file -> exit 0
  result="$(run_hook_capture '{"tool_name":"Bash","tool_input":{"command":"echo hello > output.txt"}}')"
  assert_eq "INV-006: Bash write to output.txt allowed" "0" "$(extract_exit "$result")"

  rm -rf "$test_dir"
}

# ---------------------------------------------------------------------------
# INV-007: Basename matching + case-insensitive
# ---------------------------------------------------------------------------

test_inv007_basename_and_case_insensitive() {
  echo ""
  echo "=== INV-007: Basename matching + case-insensitive ==="

  local test_dir="/tmp/correctless-sfg-inv007-$$"
  setup_test_env "$test_dir"
  cd "$test_dir" || return

  local result

  # src/config/.env blocked (basename match at depth)
  result="$(run_hook_capture '{"tool_name":"Edit","tool_input":{"file_path":"src/config/.env","old_string":"a","new_string":"b"}}')"
  assert_eq "INV-007: src/config/.env blocked (basename at depth)" "2" "$(extract_exit "$result")"

  # /absolute/path/.env blocked
  result="$(run_hook_capture '{"tool_name":"Edit","tool_input":{"file_path":"/absolute/path/.env","old_string":"a","new_string":"b"}}')"
  assert_eq "INV-007: /absolute/path/.env blocked" "2" "$(extract_exit "$result")"

  # .ENV blocked (case-insensitive)
  result="$(run_hook_capture '{"tool_name":"Edit","tool_input":{"file_path":".ENV","old_string":"a","new_string":"b"}}')"
  assert_eq "INV-007: .ENV blocked (case-insensitive)" "2" "$(extract_exit "$result")"

  # .Env blocked (case-insensitive)
  result="$(run_hook_capture '{"tool_name":"Edit","tool_input":{"file_path":".Env","old_string":"a","new_string":"b"}}')"
  assert_eq "INV-007: .Env blocked (case-insensitive)" "2" "$(extract_exit "$result")"

  # Full-path pattern: config/prod.yml blocks src/config/prod.yml
  # This requires a custom pattern with / in it
  setup_config_with_patterns "$test_dir" "config/prod.yml"

  result="$(run_hook_capture '{"tool_name":"Edit","tool_input":{"file_path":"src/config/prod.yml","old_string":"a","new_string":"b"}}')"
  assert_eq "INV-007: Full-path pattern config/prod.yml blocks src/config/prod.yml" "2" "$(extract_exit "$result")"

  # Negative: full-path pattern does NOT match wrong path
  result="$(run_hook_capture '{"tool_name":"Edit","tool_input":{"file_path":"src/other/prod.yml","old_string":"a","new_string":"b"}}')"
  assert_eq "INV-007: config/prod.yml does NOT match other/prod.yml" "0" "$(extract_exit "$result")"

  # Case-insensitive on key files
  result="$(run_hook_capture '{"tool_name":"Edit","tool_input":{"file_path":"ID_RSA","old_string":"a","new_string":"b"}}')"
  assert_eq "INV-007: ID_RSA blocked (case-insensitive)" "2" "$(extract_exit "$result")"

  result="$(run_hook_capture '{"tool_name":"Edit","tool_input":{"file_path":"Credentials.JSON","old_string":"a","new_string":"b"}}')"
  assert_eq "INV-007: Credentials.JSON blocked (case-insensitive)" "2" "$(extract_exit "$result")"

  rm -rf "$test_dir"
}

# ---------------------------------------------------------------------------
# INV-008: BLOCKED message format
# ---------------------------------------------------------------------------

test_inv008_blocked_message_format() {
  echo ""
  echo "=== INV-008: BLOCKED message format ==="

  local test_dir="/tmp/correctless-sfg-inv008-$$"
  setup_test_env "$test_dir"
  cd "$test_dir" || return

  local result stderr_out

  result="$(run_hook_capture '{"tool_name":"Edit","tool_input":{"file_path":"src/.env","old_string":"a","new_string":"b"}}')"
  assert_eq "INV-008: Exit code is 2" "2" "$(extract_exit "$result")"

  stderr_out="$(extract_stderr "$result")"

  # Verify message contains the filepath
  assert_contains "INV-008: Message contains filepath" "src/.env" "$stderr_out"

  # Verify message contains the matched pattern
  assert_contains "INV-008: Message contains matched pattern" ".env" "$stderr_out"

  # Verify format: BLOCKED [sensitive-file]:
  assert_contains "INV-008: Message has BLOCKED [sensitive-file] prefix" "BLOCKED [sensitive-file]:" "$stderr_out"

  # Verify message contains "matches protected pattern"
  assert_contains "INV-008: Message contains 'matches protected pattern'" "matches protected pattern" "$stderr_out"

  rm -rf "$test_dir"
}

# ---------------------------------------------------------------------------
# INV-009: Independent of workflow state
# ---------------------------------------------------------------------------

test_inv009_independent_of_workflow_state() {
  echo ""
  echo "=== INV-009: Independent of workflow state ==="

  local test_dir="/tmp/correctless-sfg-inv009-$$"
  setup_test_env "$test_dir"
  cd "$test_dir" || return

  local result

  # Block with no workflow state file -> exit 2
  result="$(run_hook_capture '{"tool_name":"Edit","tool_input":{"file_path":".env","old_string":"a","new_string":"b"}}')"
  assert_eq "INV-009: Blocks with no workflow state" "2" "$(extract_exit "$result")"

  # Create a workflow state file with override active
  mkdir -p "$test_dir/.correctless/artifacts"
  cat > "$test_dir/.correctless/artifacts/workflow-state-test.json" <<'EOF'
{
  "phase": "done",
  "override": {
    "active": true,
    "remaining_calls": 99
  }
}
EOF

  # Block with workflow state showing override active -> exit 2
  result="$(run_hook_capture '{"tool_name":"Edit","tool_input":{"file_path":".env","old_string":"a","new_string":"b"}}')"
  assert_eq "INV-009: Blocks even with workflow override active" "2" "$(extract_exit "$result")"

  # Block in done phase -> exit 2
  cat > "$test_dir/.correctless/artifacts/workflow-state-test.json" <<'EOF'
{
  "phase": "done",
  "override": {
    "active": false,
    "remaining_calls": 0
  }
}
EOF

  result="$(run_hook_capture '{"tool_name":"Edit","tool_input":{"file_path":".env","old_string":"a","new_string":"b"}}')"
  assert_eq "INV-009: Blocks in done phase" "2" "$(extract_exit "$result")"

  rm -rf "$test_dir"
}

# ---------------------------------------------------------------------------
# INV-010: Fast-path for non-write tools (no config loading)
# ---------------------------------------------------------------------------

test_inv010_fast_path_non_write_tools() {
  echo ""
  echo "=== INV-010: Fast-path for non-write tools ==="

  local test_dir="/tmp/correctless-sfg-inv010-$$"
  setup_test_env "$test_dir"
  cd "$test_dir" || return

  # Corrupt the config so it would fail if loaded
  echo "THIS IS NOT VALID JSON {{{" > "$test_dir/.correctless/config/workflow-config.json"

  local result

  # Read tool with corrupted config -> exit 0 (proves config not loaded)
  result="$(run_hook_capture '{"tool_name":"Read","tool_input":{"file_path":".env"}}')"
  assert_eq "INV-010: Read exits 0 with corrupted config" "0" "$(extract_exit "$result")"

  # Grep tool with corrupted config -> exit 0
  result="$(run_hook_capture '{"tool_name":"Grep","tool_input":{"pattern":"SECRET","path":".env"}}')"
  assert_eq "INV-010: Grep exits 0 with corrupted config" "0" "$(extract_exit "$result")"

  # Glob tool with corrupted config -> exit 0
  result="$(run_hook_capture '{"tool_name":"Glob","tool_input":{"pattern":"**/*.env"}}')"
  assert_eq "INV-010: Glob exits 0 with corrupted config" "0" "$(extract_exit "$result")"

  rm -rf "$test_dir"
}

# ---------------------------------------------------------------------------
# PRH-001: No eval on patterns — command injection must not execute
# ---------------------------------------------------------------------------

test_prh001_no_eval_on_patterns() {
  echo ""
  echo "=== PRH-001: No eval on patterns ==="

  local test_dir="/tmp/correctless-sfg-prh001-$$"
  setup_test_env "$test_dir"
  cd "$test_dir" || return

  local canary="/tmp/canary-sfg-test-$$"
  rm -f "$canary"

  # Config pattern containing command injection attempt that WOULD match test files
  # Pattern "$(touch canary)*.ts" — if eval'd, creates canary; if glob-matched, matches .ts files
  cat > "$test_dir/.correctless/config/workflow-config.json" <<EOF
{
  "protected_files": {
    "custom_patterns": ["\$(touch $canary)*.ts"]
  }
}
EOF

  # Trigger the hook with a .ts file — forces pattern matching to run against the injection pattern
  # The hook must try to match "test.ts" against the pattern string literally (as a glob)
  run_hook_capture '{"tool_name":"Edit","tool_input":{"file_path":"test.ts","old_string":"a","new_string":"b"}}' >/dev/null

  # The canary file must NOT exist
  if [ ! -f "$canary" ]; then
    echo "  PASS: PRH-001: Command injection not executed"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: PRH-001: Command injection executed — canary file created at $canary"
    FAIL=$((FAIL + 1))
    rm -f "$canary"
  fi

  rm -rf "$test_dir"
}

# ---------------------------------------------------------------------------
# PRH-002: Never block reads (covered by INV-003)
# ---------------------------------------------------------------------------

test_prh002_never_block_reads() {
  echo ""
  echo "=== PRH-002: Never block reads (additional coverage) ==="

  local test_dir="/tmp/correctless-sfg-prh002-$$"
  setup_test_env "$test_dir"
  cd "$test_dir" || return

  local result

  # Read on every default sensitive pattern type -> all must exit 0
  for sensitive_file in ".env" "server.pem" "id_rsa" "credentials.json" "secrets.yaml" ".secrets"; do
    result="$(run_hook_capture "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$sensitive_file\"}}")"
    assert_eq "PRH-002: Read $sensitive_file allowed" "0" "$(extract_exit "$result")"
  done

  rm -rf "$test_dir"
}

# ---------------------------------------------------------------------------
# PRH-003: No override mechanism (covered by INV-009, additional check)
# ---------------------------------------------------------------------------

test_prh003_no_override_mechanism() {
  echo ""
  echo "=== PRH-003: No override mechanism ==="

  local test_dir="/tmp/correctless-sfg-prh003-$$"
  setup_test_env "$test_dir"
  cd "$test_dir" || return

  # Create config with an "override" field (should be ignored)
  cat > "$test_dir/.correctless/config/workflow-config.json" <<'EOF'
{
  "protected_files": {
    "custom_patterns": [],
    "override": true,
    "override_patterns": [".env"]
  }
}
EOF

  local result
  result="$(run_hook_capture '{"tool_name":"Edit","tool_input":{"file_path":".env","old_string":"a","new_string":"b"}}')"
  assert_eq "PRH-003: Override config field ignored — .env still blocked" "2" "$(extract_exit "$result")"

  rm -rf "$test_dir"
}

# ---------------------------------------------------------------------------
# BND-001: Spaces and special chars in path
# ---------------------------------------------------------------------------

test_bnd001_spaces_and_special_chars() {
  echo ""
  echo "=== BND-001: Spaces and special chars in path ==="

  local test_dir="/tmp/correctless-sfg-bnd001-$$"
  setup_test_env "$test_dir"
  cd "$test_dir" || return

  local result

  # File path with spaces
  result="$(run_hook_capture '{"tool_name":"Edit","tool_input":{"file_path":"src/my dir/.env","old_string":"a","new_string":"b"}}')"
  assert_eq "BND-001: Path with spaces blocked" "2" "$(extract_exit "$result")"

  # File path with special chars
  result="$(run_hook_capture '{"tool_name":"Edit","tool_input":{"file_path":"src/my-project (v2)/.env","old_string":"a","new_string":"b"}}')"
  assert_eq "BND-001: Path with parens blocked" "2" "$(extract_exit "$result")"

  rm -rf "$test_dir"
}

# ---------------------------------------------------------------------------
# BND-002: Empty file_path
# ---------------------------------------------------------------------------

test_bnd002_empty_file_path() {
  echo ""
  echo "=== BND-002: Empty file_path ==="

  local test_dir="/tmp/correctless-sfg-bnd002-$$"
  setup_test_env "$test_dir"
  cd "$test_dir" || return

  local result

  # Edit with empty file_path -> exit 0 (no path to match against)
  result="$(run_hook_capture '{"tool_name":"Edit","tool_input":{"file_path":"","old_string":"a","new_string":"b"}}')"
  assert_eq "BND-002: Empty file_path passes" "0" "$(extract_exit "$result")"

  # Edit with missing file_path key -> exit 0
  result="$(run_hook_capture '{"tool_name":"Edit","tool_input":{"old_string":"a","new_string":"b"}}')"
  assert_eq "BND-002: Missing file_path passes" "0" "$(extract_exit "$result")"

  rm -rf "$test_dir"
}

# ---------------------------------------------------------------------------
# BND-003: Missing/malformed config
# ---------------------------------------------------------------------------

test_bnd003_missing_malformed_config() {
  echo ""
  echo "=== BND-003: Missing/malformed config ==="

  local test_dir="/tmp/correctless-sfg-bnd003-$$"

  # Test 1: Missing config -> defaults still block .env
  setup_test_env "$test_dir"
  rm -f "$test_dir/.correctless/config/workflow-config.json"
  cd "$test_dir" || return

  local result
  result="$(run_hook_capture '{"tool_name":"Edit","tool_input":{"file_path":".env","old_string":"a","new_string":"b"}}')"
  assert_eq "BND-003: Missing config -> .env still blocked" "2" "$(extract_exit "$result")"

  # Test 2: Malformed JSON config -> defaults still block .env
  setup_test_env "$test_dir"
  echo "NOT VALID JSON {{{" > "$test_dir/.correctless/config/workflow-config.json"
  cd "$test_dir" || return

  result="$(run_hook_capture '{"tool_name":"Edit","tool_input":{"file_path":".env","old_string":"a","new_string":"b"}}')"
  assert_eq "BND-003: Malformed JSON config -> .env still blocked" "2" "$(extract_exit "$result")"

  # Test 3: Config with wrong types -> defaults still block
  setup_test_env "$test_dir"
  cat > "$test_dir/.correctless/config/workflow-config.json" <<'EOF'
{
  "protected_files": {
    "custom_patterns": "not-an-array"
  }
}
EOF
  cd "$test_dir" || return

  result="$(run_hook_capture '{"tool_name":"Edit","tool_input":{"file_path":".env","old_string":"a","new_string":"b"}}')"
  assert_eq "BND-003: Wrong type config -> .env still blocked" "2" "$(extract_exit "$result")"

  rm -rf "$test_dir"
}

# ---------------------------------------------------------------------------
# BND-004: Bash with multiple targets
# ---------------------------------------------------------------------------

test_bnd004_bash_multiple_targets() {
  echo ""
  echo "=== BND-004: Bash with multiple targets ==="

  local test_dir="/tmp/correctless-sfg-bnd004-$$"
  setup_test_env "$test_dir"
  cd "$test_dir" || return

  local result

  # cp .env .env.backup -> exit 2 (source is protected)
  result="$(run_hook_capture '{"tool_name":"Bash","tool_input":{"command":"cp .env .env.backup"}}')"
  assert_eq "BND-004: cp .env source blocked" "2" "$(extract_exit "$result")"

  # cat file1 > .env -> exit 2 (destination is protected)
  result="$(run_hook_capture '{"tool_name":"Bash","tool_input":{"command":"cat file1 > .env"}}')"
  assert_eq "BND-004: cat redirect to .env blocked" "2" "$(extract_exit "$result")"

  # cp normal.txt .env -> exit 2 (destination is protected)
  result="$(run_hook_capture '{"tool_name":"Bash","tool_input":{"command":"cp normal.txt .env"}}')"
  assert_eq "BND-004: cp to .env dest blocked" "2" "$(extract_exit "$result")"

  rm -rf "$test_dir"
}

# ---------------------------------------------------------------------------
# QA-001: Chained inline redirects must all be detected
# ---------------------------------------------------------------------------

test_qa001_chained_inline_redirects() {
  echo ""
  echo "=== QA-001: Chained inline redirects ==="

  local test_dir="/tmp/correctless-sfg-qa001-$$"
  setup_test_env "$test_dir"
  cd "$test_dir" || return

  local result

  # echo a>/dev/null; echo secret>.env — second redirect targets .env
  result="$(run_hook_capture '{"tool_name":"Bash","tool_input":{"command":"echo a>/dev/null; echo secret>.env"}}')"
  assert_eq "QA-001: chained inline redirect echo a>/dev/null; echo secret>.env blocked" "2" "$(extract_exit "$result")"

  rm -rf "$test_dir"
}

# ---------------------------------------------------------------------------
# QA-002: Full-path pattern must require path boundary
# ---------------------------------------------------------------------------

test_qa002_fullpath_boundary() {
  echo ""
  echo "=== QA-002: Full-path pattern requires path boundary ==="

  local test_dir="/tmp/correctless-sfg-qa002-$$"
  setup_test_env "$test_dir"
  setup_config_with_patterns "$test_dir" "config/prod.yml"
  cd "$test_dir" || return

  local result

  # myconfig/prod.yml must NOT match pattern config/prod.yml (no / boundary)
  result="$(run_hook_capture '{"tool_name":"Edit","tool_input":{"file_path":"myconfig/prod.yml","old_string":"a","new_string":"b"}}')"
  assert_eq "QA-002: myconfig/prod.yml not blocked by config/prod.yml pattern" "0" "$(extract_exit "$result")"

  # config/prod.yml itself must still match
  result="$(run_hook_capture '{"tool_name":"Edit","tool_input":{"file_path":"config/prod.yml","old_string":"a","new_string":"b"}}')"
  assert_eq "QA-002: config/prod.yml itself is blocked" "2" "$(extract_exit "$result")"

  # src/config/prod.yml must still match (has / before config)
  result="$(run_hook_capture '{"tool_name":"Edit","tool_input":{"file_path":"src/config/prod.yml","old_string":"a","new_string":"b"}}')"
  assert_eq "QA-002: src/config/prod.yml blocked by config/prod.yml pattern" "2" "$(extract_exit "$result")"

  rm -rf "$test_dir"
}

# ---------------------------------------------------------------------------
# QA-003: Bare redirect at command start must be detected
# ---------------------------------------------------------------------------

test_qa003_bare_redirect_at_start() {
  echo ""
  echo "=== QA-003: Bare redirect at command start ==="

  local test_dir="/tmp/correctless-sfg-qa003-$$"
  setup_test_env "$test_dir"
  cd "$test_dir" || return

  local result

  # > .env at command start
  result="$(run_hook_capture '{"tool_name":"Bash","tool_input":{"command":"> .env"}}')"
  assert_eq "QA-003: bare redirect > .env blocked" "2" "$(extract_exit "$result")"

  rm -rf "$test_dir"
}

# ---------------------------------------------------------------------------
# QA-004: Comprehensive default pattern coverage
# ---------------------------------------------------------------------------

test_qa004_all_default_patterns() {
  echo ""
  echo "=== QA-004: All default patterns tested ==="

  local test_dir="/tmp/correctless-sfg-qa004-$$"
  setup_test_env "$test_dir"
  rm -rf "$test_dir/.correctless"
  mkdir -p "$test_dir"
  cd "$test_dir" || return

  local result

  # Test each default pattern with a representative filename
  # Pattern: .env
  # (already tested in INV-004)

  # Pattern: .env.* -> .env.staging
  result="$(run_hook_capture '{"tool_name":"Edit","tool_input":{"file_path":".env.staging","old_string":"a","new_string":"b"}}')"
  assert_eq "QA-004: .env.staging blocked (.env.*)" "2" "$(extract_exit "$result")"

  # Pattern: *.pem -> server.pem
  # (already tested in INV-004)

  # Pattern: *.key -> app.key
  result="$(run_hook_capture '{"tool_name":"Edit","tool_input":{"file_path":"app.key","old_string":"a","new_string":"b"}}')"
  assert_eq "QA-004: app.key blocked (*.key)" "2" "$(extract_exit "$result")"

  # Pattern: *.p12 -> cert.p12
  result="$(run_hook_capture '{"tool_name":"Edit","tool_input":{"file_path":"cert.p12","old_string":"a","new_string":"b"}}')"
  assert_eq "QA-004: cert.p12 blocked (*.p12)" "2" "$(extract_exit "$result")"

  # Pattern: *.pfx -> cert.pfx
  result="$(run_hook_capture '{"tool_name":"Edit","tool_input":{"file_path":"cert.pfx","old_string":"a","new_string":"b"}}')"
  assert_eq "QA-004: cert.pfx blocked (*.pfx)" "2" "$(extract_exit "$result")"

  # Pattern: credentials.json
  # (already tested in INV-004)

  # Pattern: credentials.yml
  result="$(run_hook_capture '{"tool_name":"Edit","tool_input":{"file_path":"credentials.yml","old_string":"a","new_string":"b"}}')"
  assert_eq "QA-004: credentials.yml blocked" "2" "$(extract_exit "$result")"

  # Pattern: service-account*.json -> service-account-prod.json
  result="$(run_hook_capture '{"tool_name":"Edit","tool_input":{"file_path":"service-account-prod.json","old_string":"a","new_string":"b"}}')"
  assert_eq "QA-004: service-account-prod.json blocked (service-account*.json)" "2" "$(extract_exit "$result")"

  # Pattern: *.secret -> api.secret
  result="$(run_hook_capture '{"tool_name":"Edit","tool_input":{"file_path":"api.secret","old_string":"a","new_string":"b"}}')"
  assert_eq "QA-004: api.secret blocked (*.secret)" "2" "$(extract_exit "$result")"

  # Pattern: *.secrets -> db.secrets
  result="$(run_hook_capture '{"tool_name":"Edit","tool_input":{"file_path":"db.secrets","old_string":"a","new_string":"b"}}')"
  assert_eq "QA-004: db.secrets blocked (*.secrets)" "2" "$(extract_exit "$result")"

  # Pattern: secrets.yml
  result="$(run_hook_capture '{"tool_name":"Edit","tool_input":{"file_path":"secrets.yml","old_string":"a","new_string":"b"}}')"
  assert_eq "QA-004: secrets.yml blocked" "2" "$(extract_exit "$result")"

  # Pattern: secrets.yaml
  # (already tested in INV-004)

  # Pattern: secrets.json
  result="$(run_hook_capture '{"tool_name":"Edit","tool_input":{"file_path":"secrets.json","old_string":"a","new_string":"b"}}')"
  assert_eq "QA-004: secrets.json blocked" "2" "$(extract_exit "$result")"

  # Pattern: .secrets
  result="$(run_hook_capture '{"tool_name":"Edit","tool_input":{"file_path":".secrets","old_string":"a","new_string":"b"}}')"
  assert_eq "QA-004: .secrets blocked" "2" "$(extract_exit "$result")"

  # Pattern: id_rsa
  # (already tested in INV-004)

  # Pattern: id_rsa.* -> id_rsa.pub
  result="$(run_hook_capture '{"tool_name":"Edit","tool_input":{"file_path":"id_rsa.pub","old_string":"a","new_string":"b"}}')"
  assert_eq "QA-004: id_rsa.pub blocked (id_rsa.*)" "2" "$(extract_exit "$result")"

  # Pattern: id_ed25519
  result="$(run_hook_capture '{"tool_name":"Edit","tool_input":{"file_path":"id_ed25519","old_string":"a","new_string":"b"}}')"
  assert_eq "QA-004: id_ed25519 blocked" "2" "$(extract_exit "$result")"

  # Pattern: id_ed25519.* -> id_ed25519.pub
  result="$(run_hook_capture '{"tool_name":"Edit","tool_input":{"file_path":"id_ed25519.pub","old_string":"a","new_string":"b"}}')"
  assert_eq "QA-004: id_ed25519.pub blocked (id_ed25519.*)" "2" "$(extract_exit "$result")"

  # Pattern: *.keystore
  # (already tested in INV-004)

  # Pattern: *.jks -> release.jks
  result="$(run_hook_capture '{"tool_name":"Edit","tool_input":{"file_path":"release.jks","old_string":"a","new_string":"b"}}')"
  assert_eq "QA-004: release.jks blocked (*.jks)" "2" "$(extract_exit "$result")"

  rm -rf "$test_dir"
}

# ---------------------------------------------------------------------------
# BND-005: Symlink accepted limitation — symlinks not resolved
# ---------------------------------------------------------------------------

test_bnd005_symlink_accepted_limitation() {
  echo ""
  echo "=== BND-005: Symlink accepted limitation ==="

  # BND-005: The hook checks the literal path string, not the resolved symlink target.
  # A symlink named "settings" pointing to ".env" will NOT be blocked because
  # the hook only sees the name "settings", which matches no protected pattern.
  # This is an accepted limitation documented in the spec.

  local test_dir="/tmp/correctless-sfg-bnd005-$$"
  setup_test_env "$test_dir"
  cd "$test_dir" || return

  # Create a symlink: settings -> .env
  touch "$test_dir/.env"
  ln -s .env "$test_dir/settings"

  local result

  # Edit "settings" (which is a symlink to .env) -> exit 0
  # The hook sees "settings" not ".env", so it passes through
  result="$(run_hook_capture '{"tool_name":"Edit","tool_input":{"file_path":"settings","old_string":"a","new_string":"b"}}')"
  assert_eq "BND-005: symlink 'settings' -> .env passes (accepted limitation)" "0" "$(extract_exit "$result")"

  rm -rf "$test_dir"
}

# ---------------------------------------------------------------------------
# QA-006: Quoted filenames in Bash commands (class fix)
# ---------------------------------------------------------------------------

test_qa006_quoted_filenames_in_bash() {
  echo ""
  echo "=== QA-006: Quoted filenames in Bash commands ==="

  local test_dir="/tmp/correctless-sfg-qa006-$$"
  setup_test_env "$test_dir"
  cd "$test_dir" || return

  local result

  # Double-quoted .env in cp command -> exit 2
  result="$(run_hook_capture '{"tool_name":"Bash","tool_input":{"command":"cp \".env\" backup.txt"}}')"
  assert_eq "QA-006: cp \".env\" blocked (double-quoted)" "2" "$(extract_exit "$result")"

  # Single-quoted .env in redirect -> exit 2
  result="$(run_hook_capture '{"tool_name":"Bash","tool_input":{"command":"echo secret > '"'"'.env'"'"'"}}')"
  assert_eq "QA-006: echo > '.env' blocked (single-quoted)" "2" "$(extract_exit "$result")"

  # Double-quoted inline redirect -> exit 2
  result="$(run_hook_capture '{"tool_name":"Bash","tool_input":{"command":"echo secret>\".env\""}}')"
  assert_eq "QA-006: echo>\".env\" blocked (inline double-quoted)" "2" "$(extract_exit "$result")"

  rm -rf "$test_dir"
}

# ---------------------------------------------------------------------------
# Run all tests
# ---------------------------------------------------------------------------

echo "=== Sensitive File Guard Hook Tests ==="
echo "Hook: $HOOK"
echo ""

test_inv001_block_write_tools_on_sensitive_files
test_inv002_block_bash_writes_to_sensitive_files
test_inv003_allow_read_operations
test_inv004_defaults_without_config
test_inv005_custom_patterns
test_inv006_non_sensitive_files_pass
test_inv007_basename_and_case_insensitive
test_inv008_blocked_message_format
test_inv009_independent_of_workflow_state
test_inv010_fast_path_non_write_tools
test_prh001_no_eval_on_patterns
test_prh002_never_block_reads
test_prh003_no_override_mechanism
test_bnd001_spaces_and_special_chars
test_bnd002_empty_file_path
test_bnd003_missing_malformed_config
test_bnd004_bash_multiple_targets
test_qa001_chained_inline_redirects
test_qa002_fullpath_boundary
test_qa003_bare_redirect_at_start
test_qa004_all_default_patterns
test_bnd005_symlink_accepted_limitation
test_qa006_quoted_filenames_in_bash

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
