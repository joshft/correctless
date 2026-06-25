#!/usr/bin/env bash
# Correctless — Sensitive File Guard PreToolUse Hook Tests
# Tests spec rules from .correctless/specs/sensitive-file-protection.md
# INV-001 through INV-010, PRH-001 through PRH-003, BND-001 through BND-004
# Run from repo root: bash tests/test-sensitive-file-guard.sh

source "$(dirname "${BASH_SOURCE[0]}")/test-helpers.sh"

HOOK="$REPO_DIR/hooks/sensitive-file-guard.sh"

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

  # RS-016 (sfg-rescope): cp .env backup -> exit 0. SFG is a WRITE guard, not an
  # egress guard. `.env` here is the SOURCE (a read); the destination is the
  # non-protected backup.txt. redact-secrets.sh owns egress, not SFG (STRIDE
  # Information disclosure / DD-7). Inverted from exit 2.
  result="$(run_hook_capture '{"tool_name":"Bash","tool_input":{"command":"cp .env backup.txt"}}')"
  assert_eq "RS-016: cp .env backup.txt (source read) ALLOWED" "0" "$(extract_exit "$result")"

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

  # RS-016 (sfg-rescope): cp .env .env.backup -> exit 2, but because the
  # DESTINATION `.env.backup` matches `.env.*` (a protected write target), NOT
  # because `.env` is the source. The source `.env` is a read and is no longer a
  # block reason post-rescope. Use a non-protected destination to prove
  # source-read is allowed:
  result="$(run_hook_capture '{"tool_name":"Bash","tool_input":{"command":"cp .env /tmp/plain-backup.txt"}}')"
  assert_eq "RS-016: cp .env <non-protected dest> ALLOWED (source read)" "0" "$(extract_exit "$result")"

  # Destination-is-protected still blocks (cp final positional = destination):
  result="$(run_hook_capture '{"tool_name":"Bash","tool_input":{"command":"cp plain.txt .env.backup"}}')"
  assert_eq "BND-004: cp <src> .env.backup blocked (destination protected)" "2" "$(extract_exit "$result")"

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

  # Double-quoted .env as cp SOURCE -> exit 0 (RS-016/DD-7: SFG is a write guard,
  # not an egress guard; .env is the source read, backup.txt is the destination).
  # Quoted sibling of the test_inv002/test_bnd004 RS-016 inversions.
  result="$(run_hook_capture '{"tool_name":"Bash","tool_input":{"command":"cp \".env\" backup.txt"}}')"
  assert_eq "QA-006: cp \".env\" source-read ALLOWED (double-quoted, RS-016)" "0" "$(extract_exit "$result")"

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

# ===========================================================================
# DA-003: Fail-closed on jq parse failure
# ===========================================================================

test_da003_fail_closed_on_jq_failure() {
  echo ""
  echo "=== DA-003: Fail-closed on jq parse failure ==="

  # Feed invalid JSON to the security hook — must exit 2 (block), not 0 (allow)
  local exit_code
  echo "NOT VALID JSON {{{" | bash "$HOOK" 2>/dev/null
  exit_code=$?
  assert_eq "DA-003: jq parse failure exits 2 (fail-closed)" "2" "$exit_code"
}

# ===========================================================================
# DA-004: Hook allowlist sync — deterministic check
# ===========================================================================

test_da004_hook_allowlist_sync() {
  echo ""
  echo "=== DA-004: Hook command allowlist sync ==="

  local gate="$REPO_DIR/hooks/workflow-gate.sh"
  local guard="$REPO_DIR/hooks/sensitive-file-guard.sh"

  # Extract the shared write-command list from each hook
  # workflow-gate.sh: the case pattern in _has_write_pattern
  local gate_cmds guard_cmds
  gate_cmds="$(grep -A1 '_has_write_pattern' "$gate" | grep -oE 'cp\|mv\|[a-z|]+\) return' | head -1 | sed 's/) return//')"
  guard_cmds="$(grep -A1 '_has_write_pattern' "$guard" | grep -oE 'cp\|mv\|[a-z|]+\) return' | head -1 | sed 's/) return//')"

  # The guard has extra scripted-write commands (python|python3|node|ruby)
  # that the gate doesn't need. Strip those for comparison.
  local guard_shared
  guard_shared="$(echo "$guard_cmds" | sed 's/|python3\?//g; s/|node//g; s/|ruby//g')"

  assert_eq "DA-004: shared write commands match between gate and guard" "$gate_cmds" "$guard_shared"

  # Extension regex sync between workflow-gate.sh and audit-trail.sh
  local gate_ext trail_ext
  gate_ext="$(grep -oE '\.\(go\|ts\|[a-z|]+\)' "$gate" | head -1)"
  trail_ext="$(grep -oE '\.\(go\|ts\|[a-z|]+\)' "$REPO_DIR/hooks/audit-trail.sh" | head -1)"

  assert_eq "DA-004: extension regex matches between gate and audit-trail" "$gate_ext" "$trail_ext"
}

test_da003_fail_closed_on_jq_failure
test_da004_hook_allowlist_sync

# ---------------------------------------------------------------------------
# Harness fingerprint protection (PRH-002 / PRH-006 — harness-fingerprint spec)
# ---------------------------------------------------------------------------
test_hf002_harness_meta_protection() {
  echo ""
  echo "=== HF-002: Harness fingerprint store and baseline file structurally protected ==="

  local test_dir="/tmp/correctless-sfg-hf002-$$"
  setup_test_env "$test_dir"
  cd "$test_dir" || return

  local result

  # Edit on harness-fingerprint.json blocked
  result="$(run_hook_capture '{"tool_name":"Edit","tool_input":{"file_path":".correctless/meta/harness-fingerprint.json","old_string":"a","new_string":"b"}}')"
  assert_eq "HF-002: Edit harness-fingerprint.json blocked" "2" "$(extract_exit "$result")"

  # Write on model-baselines.json blocked
  result="$(run_hook_capture '{"tool_name":"Write","tool_input":{"file_path":".correctless/meta/model-baselines.json","content":"x"}}')"
  assert_eq "HF-002: Write model-baselines.json blocked" "2" "$(extract_exit "$result")"

  # Bash redirect to harness-fingerprint.json blocked
  result="$(run_hook_capture '{"tool_name":"Bash","tool_input":{"command":"echo x > .correctless/meta/harness-fingerprint.json"}}')"
  assert_eq "HF-002: redirect > harness-fingerprint.json blocked" "2" "$(extract_exit "$result")"

  # Bash tee on model-baselines.json blocked
  result="$(run_hook_capture '{"tool_name":"Bash","tool_input":{"command":"echo x | tee .correctless/meta/model-baselines.json"}}')"
  assert_eq "HF-002: tee model-baselines.json blocked" "2" "$(extract_exit "$result")"

  # Append redirect blocked
  result="$(run_hook_capture '{"tool_name":"Bash","tool_input":{"command":"echo x >> .correctless/meta/harness-fingerprint.json"}}')"
  assert_eq "HF-002: append >> harness-fingerprint.json blocked" "2" "$(extract_exit "$result")"

  rm -rf "$test_dir"
}

test_hf006_script_protection() {
  echo ""
  echo "=== HF-006: scripts/harness-fingerprint.sh protected from autonomous edits ==="

  local test_dir="/tmp/correctless-sfg-hf006-$$"
  setup_test_env "$test_dir"
  cd "$test_dir" || return

  local result
  result="$(run_hook_capture '{"tool_name":"Edit","tool_input":{"file_path":"scripts/harness-fingerprint.sh","old_string":"HARNESS_VERSION=1","new_string":"HARNESS_VERSION=2"}}')"
  assert_eq "HF-006: Edit on harness-fingerprint.sh blocked" "2" "$(extract_exit "$result")"

  result="$(run_hook_capture '{"tool_name":"Edit","tool_input":{"file_path":".correctless/scripts/harness-fingerprint.sh","old_string":"HARNESS_VERSION=1","new_string":"HARNESS_VERSION=2"}}')"
  assert_eq "HF-006: Edit on .correctless/scripts/harness-fingerprint.sh blocked" "2" "$(extract_exit "$result")"

  rm -rf "$test_dir"
}

test_hf002_harness_meta_protection
test_hf006_script_protection

# ---------------------------------------------------------------------------
# ABS-030: autonomous-decisions JSONL protection
# ---------------------------------------------------------------------------
test_abs030_autonomous_decisions_protection() {
  echo ""
  echo "=== ABS-030: autonomous-decisions JSONL structurally protected ==="

  local test_dir="/tmp/correctless-sfg-abs030-$$"
  setup_test_env "$test_dir"
  cd "$test_dir" || return

  local result

  # Edit on autonomous-decisions-*.jsonl blocked
  result="$(run_hook_capture '{"tool_name":"Edit","tool_input":{"file_path":".correctless/artifacts/autonomous-decisions-test.jsonl","old_string":"a","new_string":"b"}}')"
  assert_eq "ABS-030: Edit autonomous-decisions-test.jsonl blocked" "2" "$(extract_exit "$result")"

  # Write on autonomous-decisions-*.jsonl blocked
  result="$(run_hook_capture '{"tool_name":"Write","tool_input":{"file_path":".correctless/artifacts/autonomous-decisions-test.jsonl","content":"{}"}}')"
  assert_eq "ABS-030: Write autonomous-decisions-test.jsonl blocked" "2" "$(extract_exit "$result")"

  # Bash redirect to autonomous-decisions-*.jsonl blocked
  result="$(run_hook_capture '{"tool_name":"Bash","tool_input":{"command":"echo x > .correctless/artifacts/autonomous-decisions-test.jsonl"}}')"
  assert_eq "ABS-030: redirect > autonomous-decisions-test.jsonl blocked" "2" "$(extract_exit "$result")"

  # Bash tee on autonomous-decisions-*.jsonl blocked
  result="$(run_hook_capture '{"tool_name":"Bash","tool_input":{"command":"echo x | tee .correctless/artifacts/autonomous-decisions-test.jsonl"}}')"
  assert_eq "ABS-030: tee autonomous-decisions-test.jsonl blocked" "2" "$(extract_exit "$result")"

  # Append redirect blocked
  result="$(run_hook_capture '{"tool_name":"Bash","tool_input":{"command":"echo x >> .correctless/artifacts/autonomous-decisions-test.jsonl"}}')"
  assert_eq "ABS-030: append >> autonomous-decisions-test.jsonl blocked" "2" "$(extract_exit "$result")"

  rm -rf "$test_dir"
}

test_abs030_autonomous_decisions_protection

# ===========================================================================
# R2 Hardening tests — harness-fingerprint-r2-hardening spec
# INV-005, INV-005a, INV-006, INV-006a, INV-007, INV-007a, INV-008, INV-013, PRH-005
# ===========================================================================

# ---------------------------------------------------------------------------
# INV-005 [structural]: canonicalize_path is the sole normalizer at the
# matcher boundary in sensitive-file-guard.sh. Every call site of
# _check_file_against_patterns must be preceded (within 5 lines) by a
# canonicalize_path reference.
# ---------------------------------------------------------------------------
test_inv005_canonical_only_at_matcher() {
  echo ""
  echo "=== INV-005 [structural]: canonical-only at matcher boundary ==="

  local guard="$REPO_DIR/hooks/sensitive-file-guard.sh"
  local violations=0
  # awk: for every line containing _check_file_against_patterns, look back 5 lines
  # for a canonicalize_path token in the same context.
  local report
  # Scan call sites only — skip the function-definition line and any line
  # inside the function body itself (the function precondition documents the
  # contract; the actual canonicalize_path application happens at call sites).
  report="$(awk '
    /^_check_file_against_patterns[[:space:]]*\(\)/ { in_def = 1 }
    in_def && /^\}/ { in_def = 0; next }
    {
      buf[NR % 6] = $0
      if (!in_def && $0 ~ /_check_file_against_patterns/ \
          && $0 !~ /^[[:space:]]*#/ \
          && $0 !~ /_check_file_against_patterns[[:space:]]*\(\)/) {
        seen = 0
        for (i = 1; i <= 5; i++) {
          k = (NR - i) % 6
          if (k < 0) k += 6
          if (buf[k] ~ /canonicalize_path/) { seen = 1; break }
        }
        if (!seen) print NR ":" $0
      }
    }
  ' "$guard")"

  if [ -n "$report" ]; then
    violations=1
    echo "  INV-005 violations:" >&2
    echo "$report" >&2
  fi

  if [ "$violations" -eq 0 ]; then
    pass "INV-005" "every _check_file_against_patterns call site is preceded by canonicalize_path"
  else
    fail "INV-005" "matcher receives non-canonicalized input"
  fi
}

# ---------------------------------------------------------------------------
# INV-005 [integration]: traversal-encoded sensitive paths are blocked
# ---------------------------------------------------------------------------
test_inv005_traversal_encoded_blocks() {
  echo ""
  echo "=== INV-005 [integration]: traversal-encoded blocks ==="

  local test_dir="/tmp/correctless-sfg-inv005-$$"
  setup_test_env "$test_dir"
  cd "$test_dir" || return

  local result
  # Edit on traversal-encoded .env path
  result="$(run_hook_capture '{"tool_name":"Edit","tool_input":{"file_path":"subdir/../.env","old_string":"a","new_string":"b"}}')"
  assert_eq "INV-005: Edit subdir/../.env blocked" "2" "$(extract_exit "$result")"

  result="$(run_hook_capture '{"tool_name":"Edit","tool_input":{"file_path":"./foo/../.env","old_string":"a","new_string":"b"}}')"
  assert_eq "INV-005: Edit ./foo/../.env blocked" "2" "$(extract_exit "$result")"

  result="$(run_hook_capture '{"tool_name":"Edit","tool_input":{"file_path":"subdir//.env","old_string":"a","new_string":"b"}}')"
  assert_eq "INV-005: Edit subdir//.env blocked" "2" "$(extract_exit "$result")"

  # Bash redirect with traversal-encoded target
  result="$(run_hook_capture '{"tool_name":"Bash","tool_input":{"command":"echo secret > subdir/../.env"}}')"
  assert_eq "INV-005: Bash > subdir/../.env blocked" "2" "$(extract_exit "$result")"

  rm -rf "$test_dir"
}

# ---------------------------------------------------------------------------
# INV-005a: sensitive-file-guard verifies canonicalize_path is defined +
# version-probe matches before use. Probe input
# `__canonicalize_path_v1_probe__/foo` must echo back unchanged (idempotent
# on a non-traversal input).
# ---------------------------------------------------------------------------
test_inv005a_canonicalize_version_probe() {
  echo ""
  echo "=== INV-005a: canonicalize_path version probe before use ==="

  local guard="$REPO_DIR/hooks/sensitive-file-guard.sh"

  # Structural: the guard body must contain a probe call against the v1 sentinel
  if ! grep -qF '__canonicalize_path_v1_probe__' "$guard"; then
    fail "INV-005a" "guard does not contain the v1 sentinel probe"
    return
  fi

  # Structural: the failure path must reference the explicit remediation
  if ! grep -qE "canonicalize_path missing or version mismatch" "$guard"; then
    fail "INV-005a" "guard missing the explicit 'canonicalize_path missing or version mismatch' remediation message"
    return
  fi

  if ! grep -qE "bash setup" "$guard"; then
    fail "INV-005a" "guard missing the 'bash setup' remediation hint"
    return
  fi

  # Integration: simulate old-lib-without-canonicalize_path scenario
  local test_dir="/tmp/correctless-sfg-inv005a-$$"
  rm -rf "$test_dir"
  mkdir -p "$test_dir/scripts" "$test_dir/hooks"
  # Copy guard, but write a stub lib.sh that lacks canonicalize_path
  cp "$guard" "$test_dir/hooks/sensitive-file-guard.sh"
  cat > "$test_dir/scripts/lib.sh" <<'STUBLIB'
#!/usr/bin/env bash
# Stub lib.sh WITHOUT canonicalize_path — simulates pre-R2 install.
_has_write_pattern() { return 1; }
_source_lib_sh() { :; }
get_target_file() { :; }
config_file() { :; }
STUBLIB

  local stderr_out exit_code
  stderr_out="$(echo '{"tool_name":"Edit","tool_input":{"file_path":".env","old_string":"a","new_string":"b"}}' \
    | bash "$test_dir/hooks/sensitive-file-guard.sh" 2>&1 >/dev/null)" && exit_code=0 || exit_code=$?

  assert_eq "INV-005a: missing canonicalize_path → exit 2" "2" "$exit_code"
  if echo "$stderr_out" | grep -qE 'canonicalize_path missing or version mismatch'; then
    pass "INV-005a" "guard emits explicit remediation message on missing canonicalize_path"
  else
    fail "INV-005a" "guard exited but did not emit the required remediation message (got: $stderr_out)"
  fi

  rm -rf "$test_dir"
}

# ---------------------------------------------------------------------------
# INV-006 [integration]: over-extract blocks bypass commands
# ---------------------------------------------------------------------------
test_inv006_over_extract_blocks_bypasses() {
  echo ""
  echo "=== INV-005/INV-003 (sfg-rescope) [integration]: SPLIT — eval payloads allow, perl -i writers block ==="

  # MUST-SPLIT per sfg-rescope Test Corpus Migration. The old test asserted the
  # over-extractor blocks every "bypass". Post-rescope the guardrail accepts
  # interpreter/eval-payload writes as non-goals (INV-005), so eval-payload rows
  # INVERT to exit 0; the `perl -i`/`perl -pi` rows are genuine writers (INV-003,
  # RS-001) and STAY exit 2. Do not delete wholesale.

  local test_dir="/tmp/correctless-sfg-inv006-$$"
  setup_test_env "$test_dir"
  cd "$test_dir" || return

  local result tag cmd json

  # Eval-payload / interpreter-mediated forms — now ALLOWED (INV-005 opaque).
  # `ed`/`vim` invocations write via the editor, not a redirect/writer-command
  # destination the extractor parses, and are accepted non-goals -> allow.
  local -a now_allowed=(
    'perl-redir:perl -e "system(q{cat hostname > .env})"'
    'php-redir:php -r "system(\"cat hostname > .env\");"'
    'lua-redir:lua -e "os.execute(\"cat hostname > .env\")"'
    'tclsh-redir:tclsh -c "exec sh -c \"cat hostname > .env\""'
    'Rscript-redir:Rscript -e "system(\"cat hostname > .env\")"'
    'nim-redir:nim e --eval:"discard execShellCmd(\"cat hostname > .env\")"'
    'bash-c-perl:bash -c "perl -i -pe s/x/y/ .env"'
    'ed-positional:printf "%s\n" w .env q | ed -s .env'
    'vim-ex:vim -e -c "w" .env'
  )
  for row in "${now_allowed[@]}"; do
    tag="${row%%:*}"
    cmd="${row#*:}"
    json=$(jq -nc --arg c "$cmd" '{tool_name:"Bash",tool_input:{command:$c}}')
    result="$(run_hook_capture "$json")"
    assert_eq "INV-005/${tag}: eval/interpreter payload -> ALLOWED" "0" "$(extract_exit "$result")"
  done

  # Genuine perl -i / -pi writers — STAY blocked (INV-003, RS-001).
  local -a still_blocked=(
    'perl-i:perl -i -pe "s/foo/bar/" .env'
    'perl-pi:perl -pi -e "s/x/y/" .env'
  )
  for row in "${still_blocked[@]}"; do
    tag="${row%%:*}"
    cmd="${row#*:}"
    json=$(jq -nc --arg c "$cmd" '{tool_name:"Bash",tool_input:{command:$c}}')
    result="$(run_hook_capture "$json")"
    assert_eq "INV-003/${tag}: perl -i writer -> BLOCKED" "2" "$(extract_exit "$result")"
  done

  rm -rf "$test_dir"
}

# ---------------------------------------------------------------------------
# PRH-001 (sfg-rescope) [structural TRIPWIRE] — MUST-REWRITE of the old
# INV-006a disallowed-branches test. INV-003 now REQUIRES cp)/mv)/tee)/sed)/perl)
# writer branches, so the old "ban these case branches" assertion is INVERTED.
#
# Per PRH-001 detection (behavior is the proof): the behavioral corpora
# (INV-001, INV-017 Half-A) are the real guard — they assert exit 0 and would
# over-extract/block if an unconditional token-emit branch existed. This
# structural grep is a LABELED TRIPWIRE only: it extracts the rewritten
# `case "$tok"` block and asserts its `*)` default arm does NOT emit `$tok`
# (no `_strip_quotes "$tok"` / `echo "$tok"` / `printf … "$tok"` in the default
# arm). The whole-corpus behavior is the contract; this is a fast smoke signal.
# ---------------------------------------------------------------------------
test_inv006a_disallowed_branches_enumerated() {
  echo ""
  echo "=== PRH-001 (sfg-rescope) [structural TRIPWIRE]: no extract-every-token default arm ==="

  local guard="$REPO_DIR/hooks/sensitive-file-guard.sh"
  local body
  body="$(awk '
    /^_extract_bash_targets[[:space:]]*\(\)[[:space:]]*\{?$/,/^\}$/
  ' "$guard")"
  if [ -z "$body" ]; then
    fail "PRH-001" "cannot locate _extract_bash_targets body"
    return
  fi

  # TRIPWIRE 1: the abolished PRH-001 over-extractor signature must be gone.
  # The over-extractor's tell is a BARE per-token emit of the loop variable
  # `$tok` (`*) ... _strip_quotes "$tok"`). A destination-driven rewrite emits
  # only redirect/writer destinations (`${tokens[...]}`, `$dest`, `$sub`), never
  # the raw catch-all token. We scan the WHOLE extractor body (not just the `*)`
  # arm, whose nested inner `case` `;;` truncates a naive arm-extractor) for an
  # emit of "$tok" via _strip_quotes / echo / printf.
  local violations=0
  if printf '%s\n' "$body" | grep -v '^[[:space:]]*#' \
       | grep -Eq '(_strip_quotes|echo|printf)[^#]*"\$tok"'; then
    violations=$((violations + 1))
    echo "  PRH-001: bare \$tok emit present (extract-every-token reintroduced)" >&2
  fi

  if [ "$violations" -eq 0 ]; then
    pass "PRH-001" "no unconditional token-emit in the *) default arm (tripwire green; behavior is the proof)"
  else
    fail "PRH-001" "extract-every-token default branch reintroduced ($violations)"
  fi
}

# ---------------------------------------------------------------------------
# INV-007 [integration]: redirect detection covers all 5 operators in both
# whitespace-separated and inline-attached forms.
# ---------------------------------------------------------------------------
test_inv007_redirect_blocks_integration() {
  echo ""
  echo "=== INV-007 [integration]: redirect forms blocked ==="

  local test_dir="/tmp/correctless-sfg-inv007-$$"
  setup_test_env "$test_dir"
  cd "$test_dir" || return

  local result
  for cmd in \
    'cat /etc/hostname > .env' \
    'cat /etc/hostname>.env' \
    'cat /etc/hostname>>.env' \
    'cat /etc/hostname 2> .env' \
    'cat /etc/hostname 2>.env' \
    'cat /etc/hostname &> .env' \
    'cat /etc/hostname &>.env' \
    'cat /etc/hostname 1> .env' \
    'cat /etc/hostname 1>.env'
  do
    local json
    json=$(jq -nc --arg c "$cmd" '{tool_name:"Bash",tool_input:{command:$c}}')
    result="$(run_hook_capture "$json")"
    assert_eq "INV-007: '$cmd' blocked" "2" "$(extract_exit "$result")"
  done

  rm -rf "$test_dir"
}

# ---------------------------------------------------------------------------
# INV-005/CX-002/CX-006 (sfg-rescope) [integration] — INVERTED from the old
# INV-007a "process-sub writes blocked". Process-substitution operands
# (`>(…)`/`<(…)`) are OPAQUE at every level: the single-level sub-tokenization
# (old hook L173-186) MUST be removed, and the `(`/`)` IFS-shatter that would
# expose the inner `.env` token MUST be prevented (CX-006). A process-sub write
# is exotic, not a naive accidental clobber. These INVERT exit 2 -> exit 0.
# ---------------------------------------------------------------------------
test_inv007a_process_substitution_blocks() {
  echo ""
  echo "=== INV-005 (sfg-rescope) [integration]: process substitution operands OPAQUE (allowed) ==="

  local test_dir="/tmp/correctless-sfg-inv007a-$$"
  setup_test_env "$test_dir"
  cd "$test_dir" || return

  local result json
  for cmd in \
    'cat /etc/hostname > >(cat > .env)' \
    'tee >(grep foo > .env) >/dev/null'
  do
    json=$(jq -nc --arg c "$cmd" '{tool_name:"Bash",tool_input:{command:$c}}')
    result="$(run_hook_capture "$json")"
    assert_eq "INV-005: process-sub '$cmd' opaque -> ALLOWED" "0" "$(extract_exit "$result")"
  done

  # CX-006 explicit: the canonical opaque fixture from the spec. The shattered
  # `.env` token (from IFS splitting on `(`/`)`) MUST NOT be independently
  # emitted -> the command must exit 0.
  result="$(run_hook_capture '{"tool_name":"Bash","tool_input":{"command":"echo x > >(tee .env)"}}')"
  assert_eq "INV-005/CX-006: echo x > >(tee .env) opaque -> ALLOWED" "0" "$(extract_exit "$result")"

  rm -rf "$test_dir"
}

# ---------------------------------------------------------------------------
# INV-008 [integration]: pattern matching uses canonical forms on both sides
# ---------------------------------------------------------------------------
test_inv008_canonical_pattern_matching() {
  echo ""
  echo "=== INV-008 [integration]: canonical-on-both-sides matching ==="

  local test_dir="/tmp/correctless-sfg-inv008-$$"
  setup_test_env "$test_dir"
  cd "$test_dir" || return

  local result
  # *.pem must match traversal-encoded forms
  result="$(run_hook_capture '{"tool_name":"Edit","tool_input":{"file_path":"./certs/key.pem","old_string":"a","new_string":"b"}}')"
  assert_eq "INV-008: ./certs/key.pem matches *.pem" "2" "$(extract_exit "$result")"

  result="$(run_hook_capture '{"tool_name":"Edit","tool_input":{"file_path":"certs//key.pem","old_string":"a","new_string":"b"}}')"
  assert_eq "INV-008: certs//key.pem matches *.pem" "2" "$(extract_exit "$result")"

  result="$(run_hook_capture '{"tool_name":"Edit","tool_input":{"file_path":"subdir/../certs/key.pem","old_string":"a","new_string":"b"}}')"
  assert_eq "INV-008: subdir/../certs/key.pem matches *.pem" "2" "$(extract_exit "$result")"

  result="$(run_hook_capture '{"tool_name":"Edit","tool_input":{"file_path":"./.correctless/meta/harness-fingerprint.json","old_string":"a","new_string":"b"}}')"
  assert_eq "INV-008: ./.correctless/meta/harness-fingerprint.json matches" "2" "$(extract_exit "$result")"

  result="$(run_hook_capture '{"tool_name":"Edit","tool_input":{"file_path":"subdir/../.correctless/meta/harness-fingerprint.json","old_string":"a","new_string":"b"}}')"
  assert_eq "INV-008: traversal-encoded harness-fingerprint.json matches" "2" "$(extract_exit "$result")"

  rm -rf "$test_dir"
}

# ---------------------------------------------------------------------------
# INV-013 [integration]  — MUST-INVERT per sfg-rescope Test Corpus Migration.
# INV-005 (sfg-rescope): interpreter+eval-flag chains are OPAQUE. The contents
# of an interpreter's eval/string operand MUST NOT be parsed for redirect or
# writer destinations, so `bash -c "echo x > .env"` etc. now ALLOW (exit 0).
# An agent writing via `python -c "open('.env','w')"` is a perimeter threat the
# guardrail cannot and does not defend against (DD-3 / STRIDE Tampering).
#
# EXCEPTION (RS-001): `perl -i`/`perl -pi` ALWAYS writes its file operand
# regardless of the script body, so it is a WRITER (INV-003), NOT opaque — those
# rows STAY exit 2. Only `perl -e/-pe/-ne` WITHOUT `-i` is opaque.
# ---------------------------------------------------------------------------
test_inv013_interpreter_chains_blocked() {
  echo ""
  echo "=== INV-005 (sfg-rescope) [integration]: interpreter+eval operands are OPAQUE (allowed) ==="

  local test_dir="/tmp/correctless-sfg-inv013-$$"
  setup_test_env "$test_dir"
  cd "$test_dir" || return

  # OPAQUE interpreter+eval chains — redirect/writer INSIDE the eval operand is
  # not parsed. These INVERT from exit 2 -> exit 0 (INV-005).
  local -a opaque=(
    'bash-c:bash -c "echo x > .env"'
    'sh-c:sh -c "echo x > .env"'
    'zsh-c:zsh -c "echo x > .env"'
    'dash-c:dash -c "echo x > .env"'
    'perl-e-redir:perl -e "system(q{cat /etc/hostname > .env})"'
    'python-c-redir:python -c "import os; os.system(\"cat hostname > .env\")"'
    'python3-c-redir:python3 -c "import os; os.system(\"cat hostname > .env\")"'
    'ruby-e-redir:ruby -e "system(\"cat hostname > .env\")"'
    'php-r-redir:php -r "system(\"cat hostname > .env\");"'
    'lua-e-redir:lua -e "os.execute(\"cat hostname > .env\")"'
    'tclsh-c:tclsh -c "exec sh -c \"cat hostname > .env\""'
    'Rscript-redir:Rscript -e "system(\"cat hostname > .env\")"'
    'nim-redir:nim e --eval:"discard execShellCmd(\"cat hostname > .env\")"'
    'node-e-redir:node -e "require(\"child_process\").execSync(\"cat hostname > .env\")"'
    'env-python3-redir:/usr/bin/env python3 -c "import os; os.system(\"cat h > .env\")"'
    'optlocal-ruby-redir:/opt/local/bin/ruby -e "system(\"cat h > .env\")"'
  )
  local result row tag cmd json
  for row in "${opaque[@]}"; do
    tag="${row%%:*}"
    cmd="${row#*:}"
    json=$(jq -nc --arg c "$cmd" '{tool_name:"Bash",tool_input:{command:$c}}')
    result="$(run_hook_capture "$json")"
    assert_eq "INV-005/${tag}: interpreter eval operand opaque -> ALLOWED" "0" "$(extract_exit "$result")"
  done

  # perl -i / perl -pi are WRITERS (RS-001) — STAY blocked (exit 2).
  local -a writers=(
    'perl-pi:perl -pi -e "s/foo/bar/" .env'
    'perl-i:perl -i -e 1 .env'
    'env-perl-pi:/usr/bin/env perl -pi -e "s/x/y/" .env'
  )
  for row in "${writers[@]}"; do
    tag="${row%%:*}"
    cmd="${row#*:}"
    json=$(jq -nc --arg c "$cmd" '{tool_name:"Bash",tool_input:{command:$c}}')
    result="$(run_hook_capture "$json")"
    assert_eq "INV-003/${tag}: perl -i is a writer -> BLOCKED" "2" "$(extract_exit "$result")"
  done

  rm -rf "$test_dir"
}

# ---------------------------------------------------------------------------
# PRH-005 [structural]: no recursion / no eval / no IFS shift inside
# _extract_bash_targets body.
# ---------------------------------------------------------------------------
test_prh005_no_extractor_recursion() {
  echo ""
  echo "=== PRH-005 [structural]: extractor body has no recursion / eval / IFS shift ==="

  local guard="$REPO_DIR/hooks/sensitive-file-guard.sh"
  local body
  body="$(awk '
    /^_extract_bash_targets[[:space:]]*\(\)[[:space:]]*\{?$/,/^\}$/
  ' "$guard")"
  if [ -z "$body" ]; then
    fail "PRH-005" "cannot locate _extract_bash_targets body"
    return
  fi

  local violations=0
  # Recursion: function name appearing inside its own body
  if printf '%s' "$body" | tail -n +2 | head -n -1 | grep -E '^[[:space:]]*[^#]*_extract_bash_targets' >/dev/null; then
    violations=$((violations + 1))
    echo "  PRH-005: recursive call to _extract_bash_targets" >&2
  fi
  # eval
  if printf '%s' "$body" | grep -v '^[[:space:]]*#' | grep -E '\beval\b' >/dev/null; then
    violations=$((violations + 1))
    echo "  PRH-005: eval found in body" >&2
  fi
  # Nested IFS shifts: more than one `local IFS=` or any `IFS=` after the first
  local ifs_count
  ifs_count="$(printf '%s' "$body" | grep -v '^[[:space:]]*#' | grep -cE '(\blocal[[:space:]]+IFS=|^[[:space:]]*IFS=)' || true)"
  if [ "$ifs_count" -gt 1 ]; then
    violations=$((violations + 1))
    echo "  PRH-005: $ifs_count IFS reassignments in body (>1)" >&2
  fi

  if [ "$violations" -eq 0 ]; then
    pass "PRH-005" "no recursion / no eval / single IFS shift in _extract_bash_targets"
  else
    fail "PRH-005" "$violations PRH-005 violations"
  fi
}

# ---------------------------------------------------------------------------
# cross-model-spec-review INV-010: three-form DEFAULTS for BOTH privileged
# writers (external-review-run.sh, config-update.sh), block-both-paths
# (Edit/Write AND Bash redirect), and the RS-016 live-guard:
# SFG allows `Bash(config-update.sh ...)` but blocks direct Edit/redirect to the
# config file.
# ---------------------------------------------------------------------------

test_inv010_three_form_defaults_external_review() {
  echo ""
  echo "=== INV-010 (cross-model-spec-review): three-form DEFAULTS + block-both-paths ==="

  local test_dir="/tmp/correctless-sfg-extrev-inv010-$$"
  setup_test_env "$test_dir"
  cd "$test_dir" || return

  local result script form
  # Both privileged writers must be protected in all THREE path forms (RS-029).
  for script in external-review-run.sh config-update.sh; do
    for form in "scripts/$script" ".correctless/scripts/$script" "$script"; do
      # Edit/Write tool path blocked.
      result="$(run_hook_capture "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$form\",\"old_string\":\"a\",\"new_string\":\"b\"}}")"
      assert_eq "INV-010: Edit $form blocked" "2" "$(extract_exit "$result")"

      # Bash redirect path blocked.
      result="$(run_hook_capture "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"echo x > $form\"}}")"
      assert_eq "INV-010: Bash redirect to $form blocked" "2" "$(extract_exit "$result")"
    done
  done

  rm -rf "$test_dir"
}

test_inv010_config_live_guard() {
  echo ""
  echo "=== INV-010 (cross-model-spec-review): config-update.sh permitted, direct config write blocked (RS-016) ==="

  local test_dir="/tmp/correctless-sfg-extrev-liveguard-$$"
  setup_test_env "$test_dir"
  cd "$test_dir" || return

  local result
  # Direct Edit to workflow-config.json is blocked (it is in SFG DEFAULTS).
  result="$(run_hook_capture '{"tool_name":"Edit","tool_input":{"file_path":".correctless/config/workflow-config.json","old_string":"a","new_string":"b"}}')"
  assert_eq "INV-010: direct Edit to workflow-config.json blocked" "2" "$(extract_exit "$result")"

  # Direct Bash redirect to workflow-config.json is blocked.
  result="$(run_hook_capture '{"tool_name":"Bash","tool_input":{"command":"echo {} > .correctless/config/workflow-config.json"}}')"
  assert_eq "INV-010: redirect to workflow-config.json blocked" "2" "$(extract_exit "$result")"

  # But invoking config-update.sh (no redirect) is ALLOWED (it is the sanctioned
  # writer; the command writes via temp+mv inside the script, not a redirect).
  result="$(run_hook_capture '{"tool_name":"Bash","tool_input":{"command":"bash .correctless/scripts/config-update.sh set-external-model codex model gpt-5.5-codex"}}')"
  assert_eq "INV-010: Bash(config-update.sh ...) allowed (no redirect)" "0" "$(extract_exit "$result")"

  rm -rf "$test_dir"
}

# ---------------------------------------------------------------------------
# cross-model-spec-review INV-020: ABS-041 lift-and-restore generalized to N
# deliverables. With deliverable A lifted (removed from DEFAULTS) and B restored,
# the backstop must STILL FAIL until A is also restored — lifting A while B is
# restored must NOT falsely self-deactivate.
# ---------------------------------------------------------------------------

test_inv020_multi_deliverable_lift_backstop() {
  echo ""
  echo "=== INV-020 (cross-model-spec-review): multi-deliverable lift backstop ==="

  local backstop="$REPO_DIR/scripts/check-no-pending-sfg-lift.sh"
  if [ ! -f "$backstop" ]; then
    echo "  FAIL: INV-020 backstop script missing"
    FAIL=$((FAIL + 1))
    return
  fi

  local test_dir="/tmp/correctless-sfg-inv020-$$"
  rm -rf "$test_dir"; mkdir -p "$test_dir/.correctless/scripts" "$test_dir/hooks"

  # Distinguishing case (forces the GENERALIZATION, not the single-deliverable
  # backstop): lift B (external-review-run.sh — un-restored) WHILE A
  # (agents/fix-diff-reviewer.md) is itself lifted/absent from DEFAULTS. The
  # CURRENT single-deliverable backstop self-deactivates (RS-028) the moment A is
  # absent from DEFAULTS and returns 0 — wrongly passing even though B is still
  # lifted. The GENERALIZED backstop must independently check each path recorded
  # in the sentinel's lifted set and FAIL because B is recorded-lifted yet absent
  # from DEFAULTS.
  cp "$REPO_DIR/hooks/sensitive-file-guard.sh" "$test_dir/hooks/sensitive-file-guard.sh"

  # Sentinel records the SET of lifted paths: BOTH A and B.
  cat > "$test_dir/.correctless/.sfg-lift-active" <<EOF
lift-active: cross-model-spec-review
lifted: agents/fix-diff-reviewer.md
lifted: scripts/external-review-run.sh
EOF

  # Remove BOTH A and B DEFAULTS lines (simulating both lifted, neither restored).
  grep -v 'external-review-run.sh' "$test_dir/hooks/sensitive-file-guard.sh" \
    | grep -v 'agents/fix-diff-reviewer.md' > "$test_dir/hooks/sfg.tmp" \
    && mv "$test_dir/hooks/sfg.tmp" "$test_dir/hooks/sensitive-file-guard.sh"

  # Generalized backstop MUST FAIL: B (and A) are recorded-lifted but un-restored.
  # The single-deliverable backstop WRONGLY passes here (A absent => self-deactivate).
  local rc
  ( cd "$test_dir" && bash "$backstop" >/dev/null 2>&1 ); rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "  PASS: INV-020: generalized backstop FAILS while any recorded deliverable is un-restored"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: INV-020: backstop must independently check EACH lifted path (single-deliverable self-deactivation is a false pass)"
    FAIL=$((FAIL + 1))
  fi

  # ASYMMETRIC sub-case (the true per-path discriminator): restore B
  # (external-review-run.sh) ONLY, while A (agents/fix-diff-reviewer.md) stays
  # ABSENT from DEFAULTS and the sentinel still records BOTH lifted. The CURRENT
  # single-deliverable backstop self-deactivates the instant A is absent from
  # DEFAULTS (RS-028) and returns 0 — but B is still un-restored, so a per-path
  # backstop MUST FAIL. A backstop checking "any sentinel line / A's path only"
  # rather than "EACH recorded path restored" wrongly passes here. (RED until
  # GREEN generalizes; the un-generalized backstop wrongly self-deactivates.)
  printf '\nscripts/external-review-run.sh\n.correctless/scripts/external-review-run.sh\nexternal-review-run.sh\n' \
    >> "$test_dir/hooks/sensitive-file-guard.sh"
  ( cd "$test_dir" && bash "$backstop" >/dev/null 2>&1 ); rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "  PASS: INV-020: restore-B-only still FAILS (A un-restored, per-path check)"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: INV-020: backstop must FAIL while A is recorded-lifted yet un-restored (per-path, not self-deactivate)"
    FAIL=$((FAIL + 1))
  fi

  # Now restore A too (re-add its DEFAULTS line) and clear the sentinel -> passes.
  printf '\nagents/fix-diff-reviewer.md\n' >> "$test_dir/hooks/sensitive-file-guard.sh"
  rm -f "$test_dir/.correctless/.sfg-lift-active"
  ( cd "$test_dir" && bash "$backstop" >/dev/null 2>&1 ); rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "  PASS: INV-020: backstop passes once all deliverables restored + sentinel cleared"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: INV-020: backstop must pass when sentinel cleared (got rc=$rc)"
    FAIL=$((FAIL + 1))
  fi

  rm -rf "$test_dir"
}

# Run cross-model-spec-review INV-010 / INV-020 additions
test_inv010_three_form_defaults_external_review
test_inv010_config_live_guard
test_inv020_multi_deliverable_lift_backstop

# Run R2 hardening tests
test_inv005_canonical_only_at_matcher
test_inv005_traversal_encoded_blocks
test_inv005a_canonicalize_version_probe
test_inv006_over_extract_blocks_bypasses
test_inv006a_disallowed_branches_enumerated
test_inv007_redirect_blocks_integration
test_inv007a_process_substitution_blocks
test_inv008_canonical_pattern_matching
test_inv013_interpreter_chains_blocked
test_prh005_no_extractor_recursion

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
