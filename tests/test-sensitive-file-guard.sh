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
# INV-001 (sfg-edit-write-only): Bash commands are NEVER inspected or blocked.
# Every former-must-block Bash redirect/writer-command envelope now exits 0.
# Inverted wholesale from the old "INV-002: Block Bash write commands" test —
# SFG is now a pure Edit/Write tool-path guard; the Bash extraction path is
# deleted. RED precondition: each command exits 2 against the #205 hook.
# ---------------------------------------------------------------------------

test_inv001_bash_never_blocked_to_sensitive_files() {
  echo ""
  echo "=== INV-001 (sfg-edit-write-only): Bash write commands to sensitive files now ALLOWED ==="

  local test_dir="/tmp/correctless-sfg-inv001bash-$$"
  setup_test_env "$test_dir"
  cd "$test_dir" || return

  local result

  # cat x > .env -> now exit 0 (Bash never inspected)
  result="$(run_hook_capture '{"tool_name":"Bash","tool_input":{"command":"cat creds.txt > .env"}}')"
  assert_eq "INV-001: cat redirect to .env ALLOWED (Bash never inspected)" "0" "$(extract_exit "$result")"

  # cp .env backup -> exit 0 (source read; always was allowed post-#205)
  result="$(run_hook_capture '{"tool_name":"Bash","tool_input":{"command":"cp .env backup.txt"}}')"
  assert_eq "INV-001: cp .env backup.txt ALLOWED" "0" "$(extract_exit "$result")"

  # mv .env .env.bak -> now exit 0
  result="$(run_hook_capture '{"tool_name":"Bash","tool_input":{"command":"mv .env .env.bak"}}')"
  assert_eq "INV-001: mv .env ALLOWED" "0" "$(extract_exit "$result")"

  # tee .env -> now exit 0
  result="$(run_hook_capture '{"tool_name":"Bash","tool_input":{"command":"echo x | tee .env"}}')"
  assert_eq "INV-001: tee .env ALLOWED" "0" "$(extract_exit "$result")"

  # echo x >> .env -> now exit 0
  result="$(run_hook_capture '{"tool_name":"Bash","tool_input":{"command":"echo secret >> .env"}}')"
  assert_eq "INV-001: echo append to .env ALLOWED" "0" "$(extract_exit "$result")"

  # sed -i on .env -> now exit 0
  result="$(run_hook_capture '{"tool_name":"Bash","tool_input":{"command":"sed -i s/old/new/ .env"}}')"
  assert_eq "INV-001: sed -i .env ALLOWED" "0" "$(extract_exit "$result")"

  # Non-sensitive Bash write -> exit 0 (unchanged)
  result="$(run_hook_capture '{"tool_name":"Bash","tool_input":{"command":"cat data > output.txt"}}')"
  assert_eq "INV-001: cat > output.txt allowed (non-sensitive)" "0" "$(extract_exit "$result")"

  # cp between non-sensitive files -> exit 0 (unchanged)
  result="$(run_hook_capture '{"tool_name":"Bash","tool_input":{"command":"cp src/old.ts src/new.ts"}}')"
  assert_eq "INV-001: cp non-sensitive files allowed" "0" "$(extract_exit "$result")"

  # Wildcard-matched sensitive via Bash: cat > api.secret -> now exit 0
  result="$(run_hook_capture '{"tool_name":"Bash","tool_input":{"command":"cat data > api.secret"}}')"
  assert_eq "INV-001: cat > api.secret ALLOWED (Bash never inspected)" "0" "$(extract_exit "$result")"

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

  # INV-001 (sfg-edit-write-only): Bash is never inspected. A protected source
  # OR a protected destination in a Bash command both now exit 0. Inverted from
  # the old destination-protected exit-2 assertions.
  result="$(run_hook_capture '{"tool_name":"Bash","tool_input":{"command":"cp .env /tmp/plain-backup.txt"}}')"
  assert_eq "INV-001: cp .env <non-protected dest> ALLOWED (source read)" "0" "$(extract_exit "$result")"

  # Destination-is-protected: now ALLOWED (Bash never inspected).
  result="$(run_hook_capture '{"tool_name":"Bash","tool_input":{"command":"cp plain.txt .env.backup"}}')"
  assert_eq "INV-001: cp <src> .env.backup ALLOWED (Bash never inspected)" "0" "$(extract_exit "$result")"

  # cat file1 > .env -> now exit 0 (Bash never inspected)
  result="$(run_hook_capture '{"tool_name":"Bash","tool_input":{"command":"cat file1 > .env"}}')"
  assert_eq "INV-001: cat redirect to .env ALLOWED" "0" "$(extract_exit "$result")"

  # cp normal.txt .env -> now exit 0 (Bash never inspected)
  result="$(run_hook_capture '{"tool_name":"Bash","tool_input":{"command":"cp normal.txt .env"}}')"
  assert_eq "INV-001: cp to .env dest ALLOWED" "0" "$(extract_exit "$result")"

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

  # INV-001 (sfg-edit-write-only): chained inline redirect to .env now ALLOWED
  # (Bash never inspected). Inverted from exit 2.
  result="$(run_hook_capture '{"tool_name":"Bash","tool_input":{"command":"echo a>/dev/null; echo secret>.env"}}')"
  assert_eq "INV-001: chained inline redirect echo a>/dev/null; echo secret>.env ALLOWED" "0" "$(extract_exit "$result")"

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

  # INV-001 (sfg-edit-write-only): bare redirect to .env now ALLOWED (Bash never
  # inspected). Inverted from exit 2.
  result="$(run_hook_capture '{"tool_name":"Bash","tool_input":{"command":"> .env"}}')"
  assert_eq "INV-001: bare redirect > .env ALLOWED" "0" "$(extract_exit "$result")"

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

  # INV-001 (sfg-edit-write-only): single-quoted .env redirect now ALLOWED.
  result="$(run_hook_capture '{"tool_name":"Bash","tool_input":{"command":"echo secret > '"'"'.env'"'"'"}}')"
  assert_eq "INV-001: echo > '.env' ALLOWED (single-quoted, Bash never inspected)" "0" "$(extract_exit "$result")"

  # INV-001: double-quoted inline redirect now ALLOWED.
  result="$(run_hook_capture '{"tool_name":"Bash","tool_input":{"command":"echo secret>\".env\""}}')"
  assert_eq "INV-001: echo>\".env\" ALLOWED (inline double-quoted, Bash never inspected)" "0" "$(extract_exit "$result")"

  rm -rf "$test_dir"
}

# ---------------------------------------------------------------------------
# Run all tests
# ---------------------------------------------------------------------------

echo "=== Sensitive File Guard Hook Tests ==="
echo "Hook: $HOOK"
echo ""

test_inv001_block_write_tools_on_sensitive_files
test_inv001_bash_never_blocked_to_sensitive_files
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
# MA-R2-H1: Fail-closed on non-string / absent tool_name
#
# A non-scalar-string tool_name (array/object/number/null) or an ABSENT
# tool_name is unexpected input. The hook's jq filter raises error("non-string
# tool_name"), $_PARSED is empty, and the STEP-2 fail-closed guard exits 2
# (INV-006 / PAT-001 clause 5: on unexpected input, exit 2 — never exit 0, and
# never crash with exit 127 from `eval` running an @sh-rendered multi-token
# array as a command). file_path is likewise coerced to a scalar; an
# array-valued file_path must not crash the hook.
# ===========================================================================

test_ma_r2_h1_fail_closed_on_non_string_tool_name() {
  echo ""
  echo "=== MA-R2-H1: Fail-closed (exit 2) on non-string / absent tool_name (INV-006 / PAT-001 clause 5) ==="

  local result

  # tool_name as ARRAY — must NOT exit 0, must NOT crash (127); exit 2.
  result="$(run_hook_capture '{"tool_name":["foo","Edit"],"tool_input":{"file_path":".env"}}')"
  assert_eq "MA-R2-H1: array tool_name fail-closes (exit 2)" "2" "$(extract_exit "$result")"

  # tool_name as OBJECT.
  result="$(run_hook_capture '{"tool_name":{"x":"Edit"},"tool_input":{"file_path":".env"}}')"
  assert_eq "MA-R2-H1: object tool_name fail-closes (exit 2)" "2" "$(extract_exit "$result")"

  # tool_name as NUMBER.
  result="$(run_hook_capture '{"tool_name":123,"tool_input":{"file_path":".env"}}')"
  assert_eq "MA-R2-H1: number tool_name fail-closes (exit 2)" "2" "$(extract_exit "$result")"

  # tool_name as NULL.
  result="$(run_hook_capture '{"tool_name":null,"tool_input":{"file_path":".env"}}')"
  assert_eq "MA-R2-H1: null tool_name fail-closes (exit 2)" "2" "$(extract_exit "$result")"

  # tool_name ABSENT (no key at all).
  result="$(run_hook_capture '{"tool_input":{"file_path":".env"}}')"
  assert_eq "MA-R2-H1: absent tool_name fail-closes (exit 2)" "2" "$(extract_exit "$result")"

  # A Write with an ARRAY-valued file_path must NOT crash (exit 0 or 2, never
  # 127). tool_name is a valid string, so the array file_path is coerced to ""
  # by the jq guard and yields no protected match → allowed (exit 0). The
  # critical assertion is "not 127".
  result="$(run_hook_capture '{"tool_name":"Write","tool_input":{"file_path":[".env"]}}')"
  local fp_exit
  fp_exit="$(extract_exit "$result")"
  if [ "$fp_exit" = "0" ] || [ "$fp_exit" = "2" ]; then
    echo "  PASS: MA-R2-H1: array file_path does not crash (exit $fp_exit, never 127)"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: MA-R2-H1: array file_path crashed or misbehaved (expected 0 or 2, got '$fp_exit')"
    FAIL=$((FAIL + 1))
  fi
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
test_ma_r2_h1_fail_closed_on_non_string_tool_name
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

  # INV-001/ABS-027 (sfg-edit-write-only): the Bash-redirect leg for the meta
  # files is REMOVED — accepted residual downgrade (Tier 3, no cmd_* gate).
  # These INVERT exit 2 -> exit 0. The Edit/Write arms above remain the only
  # structural protection.
  result="$(run_hook_capture '{"tool_name":"Bash","tool_input":{"command":"echo x > .correctless/meta/harness-fingerprint.json"}}')"
  assert_eq "INV-001: redirect > harness-fingerprint.json ALLOWED (Bash never inspected)" "0" "$(extract_exit "$result")"

  result="$(run_hook_capture '{"tool_name":"Bash","tool_input":{"command":"echo x | tee .correctless/meta/model-baselines.json"}}')"
  assert_eq "INV-001: tee model-baselines.json ALLOWED (Bash never inspected)" "0" "$(extract_exit "$result")"

  result="$(run_hook_capture '{"tool_name":"Bash","tool_input":{"command":"echo x >> .correctless/meta/harness-fingerprint.json"}}')"
  assert_eq "INV-001: append >> harness-fingerprint.json ALLOWED (Bash never inspected)" "0" "$(extract_exit "$result")"

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

  # INV-001/ABS-030 (sfg-edit-write-only): the Bash-redirect leg for the JSONL
  # is REMOVED — accepted residual downgrade (Tier 2, no cmd_* gate; surviving
  # leg is the advisory R-013 growth check). These INVERT exit 2 -> exit 0.
  result="$(run_hook_capture '{"tool_name":"Bash","tool_input":{"command":"echo x > .correctless/artifacts/autonomous-decisions-test.jsonl"}}')"
  assert_eq "INV-001: redirect > autonomous-decisions-test.jsonl ALLOWED (Bash never inspected)" "0" "$(extract_exit "$result")"

  result="$(run_hook_capture '{"tool_name":"Bash","tool_input":{"command":"echo x | tee .correctless/artifacts/autonomous-decisions-test.jsonl"}}')"
  assert_eq "INV-001: tee autonomous-decisions-test.jsonl ALLOWED (Bash never inspected)" "0" "$(extract_exit "$result")"

  result="$(run_hook_capture '{"tool_name":"Bash","tool_input":{"command":"echo x >> .correctless/artifacts/autonomous-decisions-test.jsonl"}}')"
  assert_eq "INV-001: append >> autonomous-decisions-test.jsonl ALLOWED (Bash never inspected)" "0" "$(extract_exit "$result")"

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

  # INV-001 (sfg-edit-write-only): Bash redirect with a traversal-encoded
  # protected target now ALLOWED (Bash never inspected). Inverted from exit 2.
  # The Edit traversal cases above remain blocked (canonical matching preserved).
  result="$(run_hook_capture '{"tool_name":"Bash","tool_input":{"command":"echo secret > subdir/../.env"}}')"
  assert_eq "INV-001: Bash > subdir/../.env ALLOWED (Bash never inspected)" "0" "$(extract_exit "$result")"

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

  # INV-001 (sfg-edit-write-only): the former perl -i / -pi "still-blocked"
  # writers now ALLOW — Bash is never inspected at all. Inverted exit 2 -> 0.
  local -a now_allowed_writers=(
    'perl-i:perl -i -pe "s/foo/bar/" .env'
    'perl-pi:perl -pi -e "s/x/y/" .env'
  )
  for row in "${now_allowed_writers[@]}"; do
    tag="${row%%:*}"
    cmd="${row#*:}"
    json=$(jq -nc --arg c "$cmd" '{tool_name:"Bash",tool_input:{command:$c}}')
    result="$(run_hook_capture "$json")"
    assert_eq "INV-001/${tag}: perl -i writer -> ALLOWED (Bash never inspected)" "0" "$(extract_exit "$result")"
  done

  rm -rf "$test_dir"
}

# ---------------------------------------------------------------------------
# (sfg-edit-write-only) DELETED: the old INV-006a `_extract_bash_targets`
# body-awk tripwire (`test_inv006a_disallowed_branches_enumerated`). The
# function it inspected is deleted (INV-005), so a test that awks its body and
# hard-fails when absent cannot be inverted — it is removed. INV-005's "no
# helper defined" structural grep (test_inv005_extraction_path_removed)
# replaces it.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# INV-001 (sfg-edit-write-only) [integration] — INVERTED from the old INV-007
# "redirect forms blocked". Every redirect operator form against a protected
# path now ALLOWS (exit 0) because Bash is never inspected. The whole-operator
# corpus is retained as a regression guard that no redirect form re-introduces
# a block.
# ---------------------------------------------------------------------------
test_inv007_redirect_blocks_integration() {
  echo ""
  echo "=== INV-001 (sfg-edit-write-only) [integration]: redirect forms now ALLOWED ==="

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
    assert_eq "INV-001: '$cmd' ALLOWED (Bash never inspected)" "0" "$(extract_exit "$result")"
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

  # INV-001 (sfg-edit-write-only): the former perl -i / perl -pi "writer" rows
  # now ALLOW too — Bash is never inspected. Inverted exit 2 -> 0.
  local -a now_allowed=(
    'perl-pi:perl -pi -e "s/foo/bar/" .env'
    'perl-i:perl -i -e 1 .env'
    'env-perl-pi:/usr/bin/env perl -pi -e "s/x/y/" .env'
  )
  for row in "${now_allowed[@]}"; do
    tag="${row%%:*}"
    cmd="${row#*:}"
    json=$(jq -nc --arg c "$cmd" '{tool_name:"Bash",tool_input:{command:$c}}')
    result="$(run_hook_capture "$json")"
    assert_eq "INV-001/${tag}: perl -i ALLOWED (Bash never inspected)" "0" "$(extract_exit "$result")"
  done

  rm -rf "$test_dir"
}

# ---------------------------------------------------------------------------
# (sfg-edit-write-only) DELETED: the old PRH-005 `_extract_bash_targets`
# body-awk structural test (`test_prh005_no_extractor_recursion`). The
# extractor is deleted (INV-005); a body-awk test that hard-fails when the
# function is absent cannot be inverted — it is removed.
# ---------------------------------------------------------------------------

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
      # Edit/Write tool path STILL blocked (retained leg, INV-002).
      result="$(run_hook_capture "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$form\",\"old_string\":\"a\",\"new_string\":\"b\"}}")"
      assert_eq "INV-010: Edit $form blocked" "2" "$(extract_exit "$result")"

      # INV-001 (sfg-edit-write-only): the Bash redirect path is now ALLOWED
      # (Bash never inspected). Inverted exit 2 -> 0.
      result="$(run_hook_capture "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"echo x > $form\"}}")"
      assert_eq "INV-001: Bash redirect to $form ALLOWED (Bash never inspected)" "0" "$(extract_exit "$result")"
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

  # INV-001 (sfg-edit-write-only): direct Bash redirect to workflow-config.json
  # now ALLOWED (Bash never inspected). Inverted exit 2 -> 0.
  result="$(run_hook_capture '{"tool_name":"Bash","tool_input":{"command":"echo {} > .correctless/config/workflow-config.json"}}')"
  assert_eq "INV-001: redirect to workflow-config.json ALLOWED (Bash never inspected)" "0" "$(extract_exit "$result")"

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

# ===========================================================================
# sfg-edit-write-only NEW TESTS (RED): INV-005 structural, INV-001 corpus,
# INV-010 BLOCKED-message body.
# ===========================================================================

# ---------------------------------------------------------------------------
# INV-005 [structural]: the entire Bash extraction path is DELETED from the
# hook (no dead code; AP-022). The hook MUST define NONE of the 10 extraction
# helpers, MUST contain no _SFG_LENGTH_CAP, no COMMAND=/${#COMMAND} Bash-length
# logic, and no `if [ "$TOOL_NAME" = "Bash" ]` extraction branch.
# RED: the #205 hook still defines all of these, so this currently FAILS.
# ---------------------------------------------------------------------------
test_inv005_extraction_path_removed() {
  echo ""
  echo "=== INV-005 [structural]: Bash extraction path fully removed from hook ==="

  local guard="$REPO_DIR/hooks/sensitive-file-guard.sh"
  local violations=0

  # The 10 deleted helpers must not be DEFINED in the hook.
  local fn
  for fn in \
    _extract_bash_targets \
    _strip_quotes \
    _excise_process_subs \
    _mask_quoted_operators \
    _mask_opaque_operands \
    _segment_command \
    _extract_writer_dests \
    _extract_inplace_operand \
    _redirect_op_suffix \
    _emit_dest
  do
    if grep -qE "^[[:space:]]*${fn}[[:space:]]*\(\)" "$guard"; then
      violations=$((violations + 1))
      echo "  INV-005: hook still defines deleted helper ${fn}()" >&2
    fi
  done

  # No length-cap sentinel.
  if grep -qF '_SFG_LENGTH_CAP' "$guard"; then
    violations=$((violations + 1))
    echo "  INV-005: hook still references _SFG_LENGTH_CAP" >&2
  fi

  # No Bash command-length logic (COMMAND= assignment or ${#COMMAND} length).
  if grep -qE '\$\{#COMMAND\}' "$guard"; then
    violations=$((violations + 1))
    echo "  INV-005: hook still computes \${#COMMAND} Bash-length" >&2
  fi
  if grep -qE '^[[:space:]]*(local[[:space:]]+)?COMMAND=' "$guard"; then
    violations=$((violations + 1))
    echo "  INV-005: hook still assigns COMMAND= (Bash command capture)" >&2
  fi

  # No Bash extraction branch (the case/if that routed Bash into extraction).
  if grep -qE 'if[[:space:]]+\[[[:space:]]+"\$TOOL_NAME"[[:space:]]*=[[:space:]]*"Bash"[[:space:]]+\]' "$guard"; then
    violations=$((violations + 1))
    echo "  INV-005: hook still has an 'if [ \"\$TOOL_NAME\" = \"Bash\" ]' extraction branch" >&2
  fi
  # The collect_targets Bash arm that dispatched to the extractor must be gone.
  if grep -qE 'Bash\)[[:space:]]*_extract_bash_targets' "$guard"; then
    violations=$((violations + 1))
    echo "  INV-005: hook still has a 'Bash) _extract_bash_targets' arm" >&2
  fi

  if [ "$violations" -eq 0 ]; then
    pass "INV-005" "hook defines none of the deleted extraction helpers / caps / Bash branch"
  else
    fail "INV-005" "$violations extraction-path remnants still present in the hook"
  fi
}

# ---------------------------------------------------------------------------
# INV-001 [integration]: representative corpus of former-must-block Bash
# envelopes — all now exit 0. Driven through the real hook via run_hook_capture.
# RED: each of these exits 2 against the #205 hook (verified out-of-band).
# ---------------------------------------------------------------------------
test_inv001_bash_corpus_never_blocked() {
  echo ""
  echo "=== INV-001 [integration]: former-must-block Bash corpus all ALLOWED ==="

  local test_dir="/tmp/correctless-sfg-inv001corpus-$$"
  setup_test_env "$test_dir"
  cd "$test_dir" || return

  local result row tag cmd json
  local -a corpus=(
    'echo-redir:echo x > .env'
    'tee:echo x | tee .env'
    'cp-dest:cp x .env'
    'mv-dest:mv x .env'
    'sed-i:sed -i s/a/b/ .env'
    'append:echo x >> .env'
    'pem-redir:cat key > server.pem'
    'meta-redir:echo x > .correctless/meta/harness-fingerprint.json'
    'prefs-redir:cat data > .correctless/preferences.md'
  )
  for row in "${corpus[@]}"; do
    tag="${row%%:*}"
    cmd="${row#*:}"
    json=$(jq -nc --arg c "$cmd" '{tool_name:"Bash",tool_input:{command:$c}}')
    result="$(run_hook_capture "$json")"
    assert_eq "INV-001/${tag}: Bash '$cmd' -> ALLOWED (exit 0)" "0" "$(extract_exit "$result")"
  done

  rm -rf "$test_dir"
}

# ---------------------------------------------------------------------------
# INV-010 [integration]: when an Edit to a protected path is blocked, the
# emitted BLOCKED message MUST use Edit/Write tool-target framing and MUST NOT
# contain the word "command" (it only ever fires on an Edit/Write tool target).
# RED: the #205 message references "command" framing -> currently FAILS.
# ---------------------------------------------------------------------------
test_inv010_blocked_message_edit_framing() {
  echo ""
  echo "=== INV-010 [integration]: BLOCKED message uses Edit/Write framing, no 'command' ==="

  local test_dir="/tmp/correctless-sfg-inv010msg-$$"
  setup_test_env "$test_dir"
  cd "$test_dir" || return

  local result stderr
  result="$(run_hook_capture '{"tool_name":"Edit","tool_input":{"file_path":".env","old_string":"a","new_string":"b"}}')"
  assert_eq "INV-010: Edit .env still blocked (exit 2)" "2" "$(extract_exit "$result")"
  stderr="$(extract_stderr "$result")"

  # Must NOT contain the word "command" (the old Bash-write framing).
  assert_not_contains "INV-010: BLOCKED message does not say 'command'" "command" "$stderr"

  # A-1: the message must RETAIN an actionable recovery path — a least-resistance
  # GREEN must not satisfy the "no 'command'" assertion by deleting the whole
  # recovery sentence. The current hook cites the sanctioned lift-and-restore
  # procedure at `.claude/rules/sfg-deliverable.md`; assert that pointer persists.
  # (Mutually satisfiable with test_inv008_blocked_message_format, which pins the
  # `BLOCKED [sensitive-file]:` prefix + `matches protected pattern` + filepath.)
  assert_contains "INV-010: BLOCKED message retains recovery pointer to sfg-deliverable.md" ".claude/rules/sfg-deliverable.md" "$stderr"

  rm -rf "$test_dir"
}

# Run cross-model-spec-review INV-010 / INV-020 additions
test_inv010_three_form_defaults_external_review
test_inv010_config_live_guard
test_inv020_multi_deliverable_lift_backstop

# Run sfg-edit-write-only new tests
test_inv001_bash_corpus_never_blocked
test_inv010_blocked_message_edit_framing

# Run R2 hardening tests
test_inv005_canonical_only_at_matcher
test_inv005_traversal_encoded_blocks
test_inv005a_canonicalize_version_probe
test_inv006_over_extract_blocks_bypasses
test_inv007_redirect_blocks_integration
test_inv007a_process_substitution_blocks
test_inv008_canonical_pattern_matching
test_inv013_interpreter_chains_blocked
# (sfg-edit-write-only) test_inv006a_disallowed_branches_enumerated and
# test_prh005_no_extractor_recursion deleted — they awk the deleted
# _extract_bash_targets body (INV-005). Replaced by test_inv005_extraction_path_removed.
test_inv005_extraction_path_removed

# ---------------------------------------------------------------------------
# calibration-writer (.correctless/specs/calibration-writer.md)
#   INV-005: scripts/meta-record.sh (source, mirror, basename) is in SFG
#            DEFAULTS — an agent Edit/Write to the writer is blocked (exit 2).
#   PRH-003: the three TARGET meta files (intensity-calibration.json,
#            pat001-measurement-due.json, model-baselines.json) STAY
#            Edit/Write-blocked — this feature only ADDS the writer path.
# ---------------------------------------------------------------------------

SFG_SENTINEL="$REPO_DIR/.correctless/.sfg-lift-active"

test_metarecord_inv005_writer_edit_write_blocked() {
  echo ""
  echo "=== INV-005 (calibration-writer): meta-record.sh Edit/Write blocked ==="

  # MA-M7 / AP-037 lift-and-restore: if meta-record.sh is currently LIFTED from
  # SFG DEFAULTS (the sentinel is present and names meta-record.sh), these
  # protection assertions would spuriously fail mid-iteration because the writer
  # path has been temporarily removed from DEFAULTS. SKIP them — mirroring the
  # fix-diff-reviewer lift SKIP — so `commands.test` and /cauto consolidation are
  # not blocked while iterating. The non-skippable pre-push backstop
  # (scripts/check-no-pending-sfg-lift.sh) still gates the restore before push.
  # See .claude/rules/sfg-deliverable.md.
  if [ -f "$SFG_SENTINEL" ] && grep -qF 'meta-record.sh' "$SFG_SENTINEL" 2>/dev/null; then
    skip "INV-005-lift" "meta-record.sh lifted (sentinel names it): SFG Edit/Write-block assertion skipped. Restore meta-record.sh to DEFAULTS and remove the sentinel before push (AP-037)."
    return
  fi

  # Source, .correctless/ mirror, and bare basename must all block Edit/Write.
  local p
  for p in "scripts/meta-record.sh" ".correctless/scripts/meta-record.sh" "meta-record.sh"; do
    local result
    result="$(run_hook_capture "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$p\",\"old_string\":\"a\",\"new_string\":\"b\"}}")"
    assert_eq "INV-005: Edit $p blocked (exit 2)" "2" "$(extract_exit "$result")"
    result="$(run_hook_capture "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$p\",\"content\":\"x\"}}")"
    assert_eq "INV-005: Write $p blocked (exit 2)" "2" "$(extract_exit "$result")"
  done

  # The writer path must actually be present in the hook's DEFAULTS (structural).
  # QA-001: DEFAULTS lines carry an inline ` # <tag>` classification suffix (single
  # source of truth — the untagged _SFG_LEGACY_EXACT_LINE_MIRROR was deleted), so
  # strip the tag before the whole-line-exact match. Intent unchanged: assert all
  # three meta-record.sh forms are present in the authoritative DEFAULTS block.
  local _hook_bare; _hook_bare="$(sed -E 's/[[:space:]]+#.*$//' "$HOOK" 2>/dev/null)"
  if printf '%s\n' "$_hook_bare" | grep -qxF 'scripts/meta-record.sh' \
     && printf '%s\n' "$_hook_bare" | grep -qxF '.correctless/scripts/meta-record.sh' \
     && printf '%s\n' "$_hook_bare" | grep -qxF 'meta-record.sh'; then
    assert_eq "INV-005: all three meta-record.sh forms in DEFAULTS" "yes" "yes"
  else
    assert_eq "INV-005: all three meta-record.sh forms in DEFAULTS" "yes" "no"
  fi

  # AP-040 honesty: Bash writes to the writer are NOT inspected (guardrail, not
  # a security boundary). A Bash redirect to meta-record.sh is ALLOWED (exit 0).
  local result
  result="$(run_hook_capture '{"tool_name":"Bash","tool_input":{"command":"echo x > scripts/meta-record.sh"}}')"
  assert_eq "INV-005: Bash write to meta-record.sh ALLOWED (Bash never inspected, AP-040)" "0" "$(extract_exit "$result")"
}
test_metarecord_inv005_writer_edit_write_blocked

test_metarecord_prh003_target_meta_stay_blocked() {
  echo ""
  echo "=== PRH-003 (calibration-writer): target meta files stay Edit/Write-blocked ==="

  local p
  for p in \
    ".correctless/meta/intensity-calibration.json" \
    ".correctless/meta/pat001-measurement-due.json" \
    ".correctless/meta/model-baselines.json"; do
    local result
    result="$(run_hook_capture "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$p\",\"old_string\":\"a\",\"new_string\":\"b\"}}")"
    assert_eq "PRH-003: Edit $p still blocked" "2" "$(extract_exit "$result")"
    result="$(run_hook_capture "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$p\",\"content\":\"x\"}}")"
    assert_eq "PRH-003: Write $p still blocked" "2" "$(extract_exit "$result")"

    # protection line remains in DEFAULTS. QA-001: strip the inline ` # <tag>`
    # classification suffix before the whole-line-exact match (single source of
    # truth = the tagged DEFAULTS block).
    if sed -E 's/[[:space:]]+#.*$//' "$HOOK" 2>/dev/null | grep -qxF "$p"; then
      assert_eq "PRH-003: $p remains in DEFAULTS" "yes" "yes"
    else
      assert_eq "PRH-003: $p remains in DEFAULTS" "yes" "no"
    fi
  done
}
test_metarecord_prh003_target_meta_stay_blocked

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
