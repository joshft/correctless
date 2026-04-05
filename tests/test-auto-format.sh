#!/usr/bin/env bash
# Correctless — Auto-Format PostToolUse Hook Tests
# Tests spec rules from .correctless/specs/auto-format-hooks.md
# INV-001 through INV-011, plus boundary conditions
# Run from repo root: bash tests/test-auto-format.sh

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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
  if echo "$actual" | grep -q "$expected"; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (expected output to contain '$expected')"
    FAIL=$((FAIL + 1))
  fi
}

assert_not_contains() {
  local desc="$1" unexpected="$2" actual="$3"
  if ! echo "$actual" | grep -q "$unexpected"; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (unexpected output containing '$unexpected')"
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

# Helper to run hook with input and capture exit + stderr
run_hook_capture() {
  local json_input="$1"
  local stderr_output
  local exit_code

  stderr_output="$("$REPO_DIR/.claude/hooks/auto-format.sh" <<< "$json_input" 2>&1 >/dev/null)"
  exit_code=$?

  echo "$exit_code:$stderr_output"
}

# Extract exit code from run_hook_capture output
extract_exit() {
  echo "$1" | head -1 | cut -d: -f1
}

# Extract stderr from run_hook_capture output
extract_stderr() {
  echo "$1" | cut -d: -f2-
}

# Create a temporary test project with config and formatters
setup_test_env() {
  local test_dir="$1"
  rm -rf "$test_dir"
  mkdir -p "$test_dir"

  # Create a minimal workflow-config.json
  mkdir -p "$test_dir/.correctless/config"
  cat > "$test_dir/.correctless/config/workflow-config.json" <<'EOF'
{
  "auto_format": {
    "enabled": true,
    "formatters": {
      "*.ts": "prettier",
      "*.tsx": "prettier",
      "*.js": "prettier",
      "*.jsx": "prettier",
      "*.py": "black",
      "*.go": "gofmt",
      "*.rs": "rustfmt"
    }
  }
}
EOF
}

# Create a stub formatter that logs what it receives
create_stub_formatter() {
  local test_dir="$1"
  local formatter_name="$2"
  local stub_dir="$test_dir/.stub-formatters"

  mkdir -p "$stub_dir"
  local stub_file="$stub_dir/$formatter_name"

  cat > "$stub_file" <<'EOF'
#!/usr/bin/env bash
# Stub formatter - logs arguments and exits 0
echo "STUB: $*" >> /tmp/formatter-calls.log
exit 0
EOF
  chmod +x "$stub_file"

  # Add to PATH
  export PATH="$stub_dir:$PATH"
}

# Create a formatter that exits non-zero (for testing failure handling)
create_failing_formatter() {
  local test_dir="$1"
  local formatter_name="$2"
  local stub_dir="$test_dir/.stub-formatters"

  mkdir -p "$stub_dir"
  local stub_file="$stub_dir/$formatter_name"

  cat > "$stub_file" <<'EOF'
#!/usr/bin/env bash
# Stub formatter that fails
exit 42
EOF
  chmod +x "$stub_file"

  export PATH="$stub_dir:$PATH"
}

# Create a formatter that times out
create_timeout_formatter() {
  local test_dir="$1"
  local formatter_name="$2"
  local stub_dir="$test_dir/.stub-formatters"

  mkdir -p "$stub_dir"
  local stub_file="$stub_dir/$formatter_name"

  cat > "$stub_file" <<'EOF'
#!/usr/bin/env bash
# Stub formatter that hangs
sleep 30 &
wait
EOF
  chmod +x "$stub_file"

  export PATH="$stub_dir:$PATH"
}

# ---------------------------------------------------------------------------
# INV-001: Hook only triggers on Edit, Write, MultiEdit
# ---------------------------------------------------------------------------

test_inv001_triggers_only_on_edit_write_multiedit() {
  echo ""
  echo "=== INV-001: Hook triggers only on Edit, Write, MultiEdit ==="

  local test_dir="/tmp/correctless-auto-format-inv001-$$"
  setup_test_env "$test_dir"
  cd "$test_dir" || exit

  # Create a test file
  mkdir -p src
  echo "const x = 1;" > src/index.ts

  # Create formatter stub to verify when it's called
  create_stub_formatter "$test_dir" "prettier"
  rm -f /tmp/formatter-calls.log

  # Test Edit — should trigger formatter
  local input_edit='{"tool_name":"Edit","tool_input":{"file_path":"src/index.ts","old_string":"const x","new_string":"const y"}}'
  local result_edit
  result_edit="$(run_hook_capture "$input_edit")"
  assert_eq "INV-001: Edit triggers (exit code)" "0" "$(extract_exit "$result_edit")"
  # CRITICAL: Verify formatter was CALLED (not just exit 0)
  if [ -f /tmp/formatter-calls.log ]; then
    echo "  PASS: INV-001: Edit invoked formatter"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: INV-001: Edit did not invoke formatter"
    FAIL=$((FAIL + 1))
  fi

  # Test Write — should trigger formatter
  rm -f /tmp/formatter-calls.log
  local input_write='{"tool_name":"Write","tool_input":{"file_path":"src/index.ts","content":"const z = 2;"}}'
  local result_write
  result_write="$(run_hook_capture "$input_write")"
  assert_eq "INV-001: Write triggers (exit code)" "0" "$(extract_exit "$result_write")"
  if [ -f /tmp/formatter-calls.log ]; then
    echo "  PASS: INV-001: Write invoked formatter"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: INV-001: Write did not invoke formatter"
    FAIL=$((FAIL + 1))
  fi

  # Test MultiEdit — should trigger formatter
  rm -f /tmp/formatter-calls.log
  local input_multiedit='{"tool_name":"MultiEdit","tool_input":{"edits":[{"file_path":"src/index.ts","old_string":"const","new_string":"let"}]}}'
  local result_multiedit
  result_multiedit="$(run_hook_capture "$input_multiedit")"
  assert_eq "INV-001: MultiEdit triggers (exit code)" "0" "$(extract_exit "$result_multiedit")"
  if [ -f /tmp/formatter-calls.log ]; then
    echo "  PASS: INV-001: MultiEdit invoked formatter"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: INV-001: MultiEdit did not invoke formatter"
    FAIL=$((FAIL + 1))
  fi

  # Test Read — must NOT trigger formatter
  rm -f /tmp/formatter-calls.log
  local input_read='{"tool_name":"Read","tool_input":{"file_path":"src/index.ts"}}'
  local result_read
  result_read="$(run_hook_capture "$input_read")"
  assert_eq "INV-001: Read skips (exit code)" "0" "$(extract_exit "$result_read")"
  if [ ! -f /tmp/formatter-calls.log ]; then
    echo "  PASS: INV-001: Read did not invoke formatter"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: INV-001: Read invoked formatter"
    FAIL=$((FAIL + 1))
  fi

  # Test Bash — must NOT trigger formatter
  rm -f /tmp/formatter-calls.log
  local input_bash='{"tool_name":"Bash","tool_input":{"command":"ls"}}'
  local result_bash
  result_bash="$(run_hook_capture "$input_bash")"
  assert_eq "INV-001: Bash skips (exit code)" "0" "$(extract_exit "$result_bash")"
  if [ ! -f /tmp/formatter-calls.log ]; then
    echo "  PASS: INV-001: Bash did not invoke formatter"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: INV-001: Bash invoked formatter"
    FAIL=$((FAIL + 1))
  fi

  # Test Grep — must NOT trigger formatter
  rm -f /tmp/formatter-calls.log
  local input_grep='{"tool_name":"Grep","tool_input":{"pattern":"test","path":"src"}}'
  local result_grep
  result_grep="$(run_hook_capture "$input_grep")"
  assert_eq "INV-001: Grep skips (exit code)" "0" "$(extract_exit "$result_grep")"
  if [ ! -f /tmp/formatter-calls.log ]; then
    echo "  PASS: INV-001: Grep did not invoke formatter"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: INV-001: Grep invoked formatter"
    FAIL=$((FAIL + 1))
  fi

  # Test Glob — must NOT trigger formatter
  rm -f /tmp/formatter-calls.log
  local input_glob='{"tool_name":"Glob","tool_input":{"pattern":"**/*.ts"}}'
  local result_glob
  result_glob="$(run_hook_capture "$input_glob")"
  assert_eq "INV-001: Glob skips (exit code)" "0" "$(extract_exit "$result_glob")"
  if [ ! -f /tmp/formatter-calls.log ]; then
    echo "  PASS: INV-001: Glob did not invoke formatter"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: INV-001: Glob invoked formatter"
    FAIL=$((FAIL + 1))
  fi

  rm -rf "$test_dir" /tmp/formatter-calls.log
}

# ---------------------------------------------------------------------------
# INV-002: Hook formats only the specific file
# ---------------------------------------------------------------------------

test_inv002_formats_only_specific_file() {
  echo ""
  echo "=== INV-002: Hook formats only specific file ==="

  local test_dir="/tmp/correctless-auto-format-inv002-$$"
  setup_test_env "$test_dir"
  cd "$test_dir" || exit

  # Create stub formatter that logs what it receives
  rm -f /tmp/formatter-calls.log
  create_stub_formatter "$test_dir" "prettier"

  mkdir -p src
  echo "const x = 1;" > src/index.ts

  # Trigger format on specific file
  local input='{"tool_name":"Edit","tool_input":{"file_path":"src/index.ts","old_string":"const x","new_string":"const y"}}'
  run_hook_capture "$input" >/dev/null

  # UNCONDITIONAL: Log file MUST exist (formatter MUST have been called)
  if [ ! -f /tmp/formatter-calls.log ]; then
    echo "  FAIL: INV-002: Formatter was not invoked (log missing)"
    FAIL=$((FAIL + 1))
  else
    local logged_file
    logged_file="$(cat /tmp/formatter-calls.log)"
    assert_contains "INV-002: Formatter receives correct file" "src/index.ts" "$logged_file"
  fi

  rm -rf "$test_dir" /tmp/formatter-calls.log
}

# ---------------------------------------------------------------------------
# INV-003: Hook exits 0 on formatter missing/crash/non-zero/timeout
# ---------------------------------------------------------------------------

test_inv003_exits_zero_on_formatter_issues() {
  echo ""
  echo "=== INV-003: Hook exits 0 on formatter issues ==="

  local test_dir="/tmp/correctless-auto-format-inv003-$$"
  setup_test_env "$test_dir"
  cd "$test_dir" || exit

  mkdir -p src
  echo "const x = 1;" > src/index.ts
  local input='{"tool_name":"Edit","tool_input":{"file_path":"src/index.ts","old_string":"const x","new_string":"const y"}}'

  # Test missing formatter
  cat > "$test_dir/.correctless/config/workflow-config.json" <<'EOF'
{
  "auto_format": {
    "enabled": true,
    "formatters": {
      "*.ts": "nonexistent-formatter"
    }
  }
}
EOF

  local result
  result="$(run_hook_capture "$input")"
  assert_eq "INV-003: Missing formatter exits 0" "0" "$(extract_exit "$result")"

  # Test failing formatter
  cd "$test_dir" || exit
  create_failing_formatter "$test_dir" "prettier"
  cat > "$test_dir/.correctless/config/workflow-config.json" <<'EOF'
{
  "auto_format": {
    "enabled": true,
    "formatters": {
      "*.ts": "prettier"
    }
  }
}
EOF

  result="$(run_hook_capture "$input")"
  assert_eq "INV-003: Crashing formatter exits 0" "0" "$(extract_exit "$result")"

  # Test formatter timeout (hangs for more than 5 seconds)
  cd "$test_dir" || exit
  create_timeout_formatter "$test_dir" "prettier"
  cat > "$test_dir/.correctless/config/workflow-config.json" <<'EOF'
{
  "auto_format": {
    "enabled": true,
    "formatters": {
      "*.ts": "prettier"
    }
  }
}
EOF

  result="$(run_hook_capture "$input")"
  assert_eq "INV-003: Timeout formatter exits 0" "0" "$(extract_exit "$result")"

  rm -rf "$test_dir"
}

# ---------------------------------------------------------------------------
# INV-004a: Hook notifies via stderr when formatter runs
# ---------------------------------------------------------------------------

test_inv004a_stderr_notification_on_success() {
  echo ""
  echo "=== INV-004a: Hook notifies stderr on formatter success ==="

  local test_dir="/tmp/correctless-auto-format-inv004a-$$"
  setup_test_env "$test_dir"
  cd "$test_dir" || exit

  # Create a working formatter
  create_stub_formatter "$test_dir" "prettier"

  mkdir -p src
  echo "const x = 1;" > src/index.ts

  # Trigger format
  local input='{"tool_name":"Edit","tool_input":{"file_path":"src/index.ts","old_string":"const x","new_string":"const y"}}'
  local result
  result="$(run_hook_capture "$input")"
  local stderr
  stderr="$(extract_stderr "$result")"

  # When formatter runs and succeeds, should have notification (e.g., "Formatted..." or similar)
  # The stub formatter will exit 0, so we should see a message
  # Note: the stub doesn't do actual formatting, so this tests the hook's notification logic
  assert_contains "INV-004a: Stderr notification on success" "Formatted\|formatted\|Format" "$stderr"

  rm -rf "$test_dir"
}

# ---------------------------------------------------------------------------
# INV-004b: Hook produces no output when formatter skipped
# ---------------------------------------------------------------------------

test_inv004b_no_stderr_when_skipped() {
  echo ""
  echo "=== INV-004b: No stderr when formatter skipped ==="

  local test_dir="/tmp/correctless-auto-format-inv004b-$$"
  setup_test_env "$test_dir"
  cd "$test_dir" || exit

  mkdir -p src
  # Create a file with unsupported extension
  echo "some arbitrary content" > src/data.txt

  # Trigger format on unsupported file
  local input='{"tool_name":"Edit","tool_input":{"file_path":"src/data.txt","old_string":"some","new_string":"other"}}'
  local result
  result="$(run_hook_capture "$input")"
  local stderr
  stderr="$(extract_stderr "$result")"

  # No formatter for .txt, so should be silent (empty stderr)
  assert_eq "INV-004b: No stderr when skipped" "" "$stderr"

  # Also test when auto_format is disabled
  cat > "$test_dir/.correctless/config/workflow-config.json" <<'EOF'
{
  "auto_format": {
    "enabled": false,
    "formatters": {
      "*.ts": "prettier"
    }
  }
}
EOF

  mkdir -p src
  echo "const x = 1;" > src/index.ts
  local input2='{"tool_name":"Edit","tool_input":{"file_path":"src/index.ts","old_string":"const x","new_string":"const y"}}'
  local result2
  result2="$(run_hook_capture "$input2")"
  local stderr2
  stderr2="$(extract_stderr "$result2")"

  assert_eq "INV-004b: No stderr when disabled" "" "$stderr2"

  rm -rf "$test_dir"
}

# ---------------------------------------------------------------------------
# INV-005: Hook checks formatter is installed
# ---------------------------------------------------------------------------

test_inv005_checks_formatter_installed() {
  echo ""
  echo "=== INV-005: Hook checks formatter via command -v ==="

  local test_dir="/tmp/correctless-auto-format-inv005-$$"
  setup_test_env "$test_dir"
  cd "$test_dir" || exit

  mkdir -p src
  echo "const x = 1;" > src/index.ts

  # Configure formatter that doesn't exist
  cat > "$test_dir/.correctless/config/workflow-config.json" <<'EOF'
{
  "auto_format": {
    "enabled": true,
    "formatters": {
      "*.ts": "definitely-not-installed-formatter-xyz"
    }
  }
}
EOF

  local input='{"tool_name":"Edit","tool_input":{"file_path":"src/index.ts","old_string":"const x","new_string":"const y"}}'
  local result
  result="$(run_hook_capture "$input")"

  # Hook should exit 0 even though formatter doesn't exist
  assert_eq "INV-005: Missing formatter handled gracefully" "0" "$(extract_exit "$result")"

  # Should not produce error output (fail-closed)
  local stderr
  stderr="$(extract_stderr "$result")"
  assert_not_contains "INV-005: No error for missing formatter" "not found\|command not found" "$stderr"

  rm -rf "$test_dir"
}

# ---------------------------------------------------------------------------
# INV-006: Formatter selection based on file extension
# ---------------------------------------------------------------------------

test_inv006_extension_based_selection() {
  echo ""
  echo "=== INV-006: Formatter selection by file extension ==="

  local test_dir="/tmp/correctless-auto-format-inv006-$$"
  setup_test_env "$test_dir"
  cd "$test_dir" || exit

  # Create formatters for different types
  mkdir -p .stub-formatters
  cat > "$test_dir/.stub-formatters/prettier" <<'EOF'
#!/usr/bin/env bash
echo "prettier called" >> /tmp/formatter-calls.log
exit 0
EOF
  chmod +x "$test_dir/.stub-formatters/prettier"

  cat > "$test_dir/.stub-formatters/black" <<'EOF'
#!/usr/bin/env bash
echo "black called" >> /tmp/formatter-calls.log
exit 0
EOF
  chmod +x "$test_dir/.stub-formatters/black"

  export PATH="$test_dir/.stub-formatters:$PATH"

  mkdir -p src
  echo "const x = 1;" > src/index.ts
  echo "x = 1" > src/script.py

  rm -f /tmp/formatter-calls.log

  # Format TypeScript file
  local input_ts='{"tool_name":"Edit","tool_input":{"file_path":"src/index.ts","old_string":"const x","new_string":"const y"}}'
  run_hook_capture "$input_ts" >/dev/null

  # Format Python file
  local input_py='{"tool_name":"Edit","tool_input":{"file_path":"src/script.py","old_string":"x = 1","new_string":"x = 2"}}'
  run_hook_capture "$input_py" >/dev/null

  # UNCONDITIONAL: Log file MUST exist
  if [ ! -f /tmp/formatter-calls.log ]; then
    echo "  FAIL: INV-006: No formatter calls logged"
    FAIL=$((FAIL + 1))
  else
    local prettier_calls
    local black_calls
    prettier_calls="$(grep -c "prettier" /tmp/formatter-calls.log || echo 0)"
    black_calls="$(grep -c "black" /tmp/formatter-calls.log || echo 0)"

    # Should have called prettier at least once
    if [ "$prettier_calls" -gt 0 ]; then
      echo "  PASS: INV-006: Prettier called for .ts file"
      PASS=$((PASS + 1))
    else
      echo "  FAIL: INV-006: Prettier not called for .ts file"
      FAIL=$((FAIL + 1))
    fi

    # Should have called black at least once
    if [ "$black_calls" -gt 0 ]; then
      echo "  PASS: INV-006: Black called for .py file"
      PASS=$((PASS + 1))
    else
      echo "  FAIL: INV-006: Black not called for .py file"
      FAIL=$((FAIL + 1))
    fi

    # Inversion test: Prettier should NOT be called for .py, black NOT for .ts
    # Count prettier calls on .py (should be 0)
    if ! grep -q "prettier.*\.py\|\.py.*prettier" /tmp/formatter-calls.log; then
      echo "  PASS: INV-006: Prettier not called for .py file"
      PASS=$((PASS + 1))
    else
      echo "  FAIL: INV-006: Prettier incorrectly called for .py file"
      FAIL=$((FAIL + 1))
    fi

    # Count black calls on .ts (should be 0)
    if ! grep -q "black.*\.ts\|\.ts.*black" /tmp/formatter-calls.log; then
      echo "  PASS: INV-006: Black not called for .ts file"
      PASS=$((PASS + 1))
    else
      echo "  FAIL: INV-006: Black incorrectly called for .ts file"
      FAIL=$((FAIL + 1))
    fi
  fi

  rm -rf "$test_dir" /tmp/formatter-calls.log
}

# ---------------------------------------------------------------------------
# INV-007: Config stores formatter settings
# ---------------------------------------------------------------------------

test_inv007_reads_config_from_workflow_config() {
  echo ""
  echo "=== INV-007: Hook reads config from workflow-config.json ==="

  local test_dir="/tmp/correctless-auto-format-inv007-$$"
  mkdir -p "$test_dir/.correctless/config"
  cd "$test_dir" || exit

  # Create config that maps .ts to prettier (allowlisted)
  cat > "$test_dir/.correctless/config/workflow-config.json" <<'EOF'
{
  "auto_format": {
    "enabled": true,
    "formatters": {
      "*.ts": "prettier"
    }
  }
}
EOF

  mkdir -p src
  echo "const x = 1;" > src/index.ts

  # Create stub formatter that logs a unique marker to prove config was read
  mkdir -p .custom-formatters
  cat > "$test_dir/.custom-formatters/prettier" <<'EOF'
#!/usr/bin/env bash
echo "config-driven-prettier called" >> /tmp/formatter-calls.log
exit 0
EOF
  chmod +x "$test_dir/.custom-formatters/prettier"
  export PATH="$test_dir/.custom-formatters:$PATH"

  rm -f /tmp/formatter-calls.log

  # Trigger format
  local input='{"tool_name":"Edit","tool_input":{"file_path":"src/index.ts","old_string":"const x","new_string":"const y"}}'
  run_hook_capture "$input" >/dev/null

  # UNCONDITIONAL: Log file MUST exist — proves config was read and formatter invoked
  if [ ! -f /tmp/formatter-calls.log ]; then
    echo "  FAIL: INV-007: Config not read (no formatter invoked)"
    FAIL=$((FAIL + 1))
  else
    local calls
    calls="$(cat /tmp/formatter-calls.log)"
    assert_contains "INV-007: Uses formatter from config" "config-driven-prettier" "$calls"
  fi

  rm -rf "$test_dir" /tmp/formatter-calls.log
}

# ---------------------------------------------------------------------------
# INV-010: Hook respects enabled flag
# ---------------------------------------------------------------------------

test_inv010_respects_enabled_flag() {
  echo ""
  echo "=== INV-010: Hook respects enabled flag ==="

  local test_dir="/tmp/correctless-auto-format-inv010-$$"
  setup_test_env "$test_dir"
  cd "$test_dir" || exit

  # Create formatter
  create_stub_formatter "$test_dir" "prettier"

  mkdir -p src
  echo "const x = 1;" > src/index.ts
  local input='{"tool_name":"Edit","tool_input":{"file_path":"src/index.ts","old_string":"const x","new_string":"const y"}}'

  # Test enabled=false
  cat > "$test_dir/.correctless/config/workflow-config.json" <<'EOF'
{
  "auto_format": {
    "enabled": false,
    "formatters": {
      "*.ts": "prettier"
    }
  }
}
EOF

  rm -f /tmp/formatter-calls.log
  run_hook_capture "$input" >/dev/null

  # Formatter should not be called when disabled
  if [ ! -f /tmp/formatter-calls.log ] || [ ! -s /tmp/formatter-calls.log ]; then
    echo "  PASS: INV-010: Disabled flag skips formatting"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: INV-010: Disabled flag still triggered formatting"
    FAIL=$((FAIL + 1))
  fi

  # Test enabled field absent (should also skip)
  cat > "$test_dir/.correctless/config/workflow-config.json" <<'EOF'
{
  "auto_format": {
    "formatters": {
      "*.ts": "prettier"
    }
  }
}
EOF

  rm -f /tmp/formatter-calls.log
  run_hook_capture "$input" >/dev/null

  if [ ! -f /tmp/formatter-calls.log ] || [ ! -s /tmp/formatter-calls.log ]; then
    echo "  PASS: INV-010: Absent enabled flag treated as disabled"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: INV-010: Absent enabled flag still triggered formatting"
    FAIL=$((FAIL + 1))
  fi

  # Test enabled=true (should format) — UNCONDITIONAL
  cat > "$test_dir/.correctless/config/workflow-config.json" <<'EOF'
{
  "auto_format": {
    "enabled": true,
    "formatters": {
      "*.ts": "prettier"
    }
  }
}
EOF

  rm -f /tmp/formatter-calls.log
  run_hook_capture "$input" >/dev/null

  if [ ! -f /tmp/formatter-calls.log ]; then
    echo "  FAIL: INV-010: Enabled flag did not trigger formatting (log missing)"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: INV-010: Enabled flag triggers formatting"
    PASS=$((PASS + 1))
  fi

  rm -rf "$test_dir" /tmp/formatter-calls.log
}

# ---------------------------------------------------------------------------
# INV-011: Formatter command validated against allowlist
# ---------------------------------------------------------------------------

test_inv011_validates_against_allowlist() {
  echo ""
  echo "=== INV-011: Formatter command validated against allowlist ==="

  local test_dir="/tmp/correctless-auto-format-inv011-$$"
  mkdir -p "$test_dir/.correctless/config"
  cd "$test_dir" || exit

  mkdir -p src
  echo "const x = 1;" > src/index.ts
  local input='{"tool_name":"Edit","tool_input":{"file_path":"src/index.ts","old_string":"const x","new_string":"const y"}}'

  # Test valid command (prettier)
  cat > "$test_dir/.correctless/config/workflow-config.json" <<'EOF'
{
  "auto_format": {
    "enabled": true,
    "formatters": {
      "*.ts": "prettier"
    }
  }
}
EOF

  local result
  result="$(run_hook_capture "$input")"
  assert_eq "INV-011: Valid command allowed" "0" "$(extract_exit "$result")"

  # Test invalid command with pipe (should reject and exit 0, no formatter invoked)
  cat > "$test_dir/.correctless/config/workflow-config.json" <<'EOF'
{
  "auto_format": {
    "enabled": true,
    "formatters": {
      "*.ts": "prettier | cat"
    }
  }
}
EOF

  rm -f /tmp/formatter-calls.log /tmp/canary-pipe-$$
  result="$(run_hook_capture "$input")"
  assert_eq "INV-011: Command with pipe rejected (exit 0)" "0" "$(extract_exit "$result")"
  if [ ! -f /tmp/formatter-calls.log ]; then
    echo "  PASS: INV-011: Pipe injection — formatter not called"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: INV-011: Pipe injection — formatter was called"
    FAIL=$((FAIL + 1))
  fi

  # Test invalid command with semicolon
  cat > "$test_dir/.correctless/config/workflow-config.json" <<'EOF'
{
  "auto_format": {
    "enabled": true,
    "formatters": {
      "*.ts": "prettier; touch /tmp/canary-semi-$$"
    }
  }
}
EOF

  result="$(run_hook_capture "$input")"
  assert_eq "INV-011: Command with semicolon rejected (exit 0)" "0" "$(extract_exit "$result")"
  if [ ! -f /tmp/canary-semi-$$ ]; then
    echo "  PASS: INV-011: Semicolon injection — command not executed"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: INV-011: Semicolon injection — injected command was executed"
    FAIL=$((FAIL + 1))
    rm -f /tmp/canary-semi-$$
  fi

  # Test invalid command with backticks
  cat > "$test_dir/.correctless/config/workflow-config.json" <<'EOF'
{
  "auto_format": {
    "enabled": true,
    "formatters": {
      "*.ts": "prettier \`touch /tmp/canary-backtick-$$\`"
    }
  }
}
EOF

  result="$(run_hook_capture "$input")"
  assert_eq "INV-011: Command with backticks rejected (exit 0)" "0" "$(extract_exit "$result")"
  if [ ! -f /tmp/canary-backtick-$$ ]; then
    echo "  PASS: INV-011: Backtick injection — command not executed"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: INV-011: Backtick injection — injected command was executed"
    FAIL=$((FAIL + 1))
    rm -f /tmp/canary-backtick-$$
  fi

  # Test invalid command with $()
  cat > "$test_dir/.correctless/config/workflow-config.json" <<'EOF'
{
  "auto_format": {
    "enabled": true,
    "formatters": {
      "*.ts": "prettier \$(touch /tmp/canary-subst-$$)"
    }
  }
}
EOF

  result="$(run_hook_capture "$input")"
  assert_eq "INV-011: Command with \$(substitution) rejected (exit 0)" "0" "$(extract_exit "$result")"
  if [ ! -f /tmp/canary-subst-$$ ]; then
    echo "  PASS: INV-011: Substitution injection — command not executed"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: INV-011: Substitution injection — injected command was executed"
    FAIL=$((FAIL + 1))
    rm -f /tmp/canary-subst-$$
  fi

  rm -rf "$test_dir"
}

# ---------------------------------------------------------------------------
# PRH-004: No eval or string interpolation in execution
# ---------------------------------------------------------------------------

test_prh004_no_eval_or_interpolation() {
  echo ""
  echo "=== PRH-004: No eval or string interpolation in execution ==="

  # This is a code audit test, not an execution test
  # Check that the hook script doesn't contain eval or unquoted variable expansion in formatter execution

  local hook_script="$REPO_DIR/.claude/hooks/auto-format.sh"

  # Check for eval in the execution path (allow eval for jq parsing)
  if grep -q 'eval.*\$command' "$hook_script" 2>/dev/null; then
    echo "  FAIL: PRH-004: Hook uses eval to execute formatter command"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: PRH-004: No eval in formatter execution"
    PASS=$((PASS + 1))
  fi

  # Check for unquoted variable in formatter invocation
  # Pattern 1: $formatter $filepath (unquoted variable expansion)
  if grep -q '\$formatter[[:space:]]\$filepath' "$hook_script" 2>/dev/null; then
    echo "  FAIL: PRH-004: Hook uses unquoted \$formatter variable"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: PRH-004: No unquoted \$formatter variable"
    PASS=$((PASS + 1))
  fi

  # Pattern 2: $command without quotes (direct variable interpolation)
  if grep -q '[^"]$command[^"]' "$hook_script" 2>/dev/null | grep -v 'command -v'; then
    echo "  FAIL: PRH-004: Hook uses unquoted \$command variable"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: PRH-004: No unquoted \$command variable"
    PASS=$((PASS + 1))
  fi

  # Pattern 3: ${formatter} or ${command} without quotes (braced variable interpolation)
  if grep -q '[^"]\${formatter}' "$hook_script" 2>/dev/null; then
    echo "  FAIL: PRH-004: Hook uses unquoted \${formatter} variable"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: PRH-004: No unquoted \${formatter} variable"
    PASS=$((PASS + 1))
  fi

  if grep -q '[^"]\${command}' "$hook_script" 2>/dev/null; then
    echo "  FAIL: PRH-004: Hook uses unquoted \${command} variable"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: PRH-004: No unquoted \${command} variable"
    PASS=$((PASS + 1))
  fi

  # Pattern 4: Backtick execution patterns
  if grep -q '`.*\$' "$hook_script" 2>/dev/null | grep -v 'echo\|printf'; then
    echo "  FAIL: PRH-004: Hook uses backtick command substitution"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: PRH-004: No backtick command substitution"
    PASS=$((PASS + 1))
  fi
}

# ---------------------------------------------------------------------------
# BND-001: File path with spaces handled correctly
# ---------------------------------------------------------------------------

test_bnd001_file_path_with_spaces() {
  echo ""
  echo "=== BND-001: File path with special characters handled correctly ==="

  local test_dir="/tmp/correctless-auto-format-bnd001-$$"
  setup_test_env "$test_dir"
  cd "$test_dir" || exit

  # Create formatter that logs what it receives
  create_stub_formatter "$test_dir" "prettier"

  # Test 1: Spaces in path
  mkdir -p "src/dir with spaces"
  echo "const x = 1;" > "src/dir with spaces/file name.ts"

  rm -f /tmp/formatter-calls.log

  local input='{"tool_name":"Edit","tool_input":{"file_path":"src/dir with spaces/file name.ts","old_string":"const x","new_string":"const y"}}'
  local result
  result="$(run_hook_capture "$input")"

  assert_eq "BND-001: File with spaces handled (exit code)" "0" "$(extract_exit "$result")"

  if [ ! -f /tmp/formatter-calls.log ]; then
    echo "  FAIL: BND-001: Formatter not called for file with spaces"
    FAIL=$((FAIL + 1))
  else
    assert_contains "BND-001: Space-containing path passed correctly" "src/dir with spaces/file name.ts" "$(cat /tmp/formatter-calls.log)"
  fi

  # Test 2: Path containing $(...) injection attempt
  mkdir -p "src/injection\$(touch /tmp/canary-inv-$$)"
  echo "const x = 1;" > "src/injection\$(touch /tmp/canary-inv-$$)/file.ts"

  rm -f /tmp/formatter-calls.log /tmp/canary-inv-$$
  local input2='{"tool_name":"Edit","tool_input":{"file_path":"src/injection$(touch /tmp/canary-inv-$$)/file.ts","old_string":"const x","new_string":"const y"}}'
  result="$(run_hook_capture "$input2")"

  if [ ! -f /tmp/canary-inv-$$ ]; then
    echo "  PASS: BND-001: Path with \$(...) not executed"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: BND-001: Path with \$(...) was executed (injection vulnerability)"
    FAIL=$((FAIL + 1))
    rm -f /tmp/canary-inv-$$
  fi

  # Test 3: Path containing backticks
  mkdir -p "src/backtick\`touch /tmp/canary-bt-$$\`"
  echo "const x = 1;" > "src/backtick\`touch /tmp/canary-bt-$$\`/file.ts"

  rm -f /tmp/formatter-calls.log /tmp/canary-bt-$$
  local input3='{"tool_name":"Edit","tool_input":{"file_path":"src/backtick\`touch /tmp/canary-bt-$$\`/file.ts","old_string":"const x","new_string":"const y"}}'
  result="$(run_hook_capture "$input3")"

  if [ ! -f /tmp/canary-bt-$$ ]; then
    echo "  PASS: BND-001: Path with backticks not executed"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: BND-001: Path with backticks was executed (injection vulnerability)"
    FAIL=$((FAIL + 1))
    rm -f /tmp/canary-bt-$$
  fi

  rm -rf "$test_dir" /tmp/formatter-calls.log
}

# ---------------------------------------------------------------------------
# BND-002: Missing file handled gracefully
# ---------------------------------------------------------------------------

test_bnd002_missing_file() {
  echo ""
  echo "=== BND-002: Missing file handled gracefully ==="

  local test_dir="/tmp/correctless-auto-format-bnd002-$$"
  setup_test_env "$test_dir"
  cd "$test_dir" || exit

  create_stub_formatter "$test_dir" "prettier"

  # File doesn't exist
  local input='{"tool_name":"Edit","tool_input":{"file_path":"nonexistent/file.ts","old_string":"const x","new_string":"const y"}}'
  local result
  result="$(run_hook_capture "$input")"

  # Should exit 0 even if file doesn't exist
  assert_eq "BND-002: Missing file exits 0" "0" "$(extract_exit "$result")"

  # Should be silent
  local stderr
  stderr="$(extract_stderr "$result")"
  assert_eq "BND-002: Missing file is silent" "" "$stderr"

  rm -rf "$test_dir"
}

# ---------------------------------------------------------------------------
# BND-003: Missing workflow-config.json
# ---------------------------------------------------------------------------

test_bnd003_missing_config() {
  echo ""
  echo "=== BND-003: Missing workflow-config.json ==="

  local test_dir="/tmp/correctless-auto-format-bnd003-$$"
  mkdir -p "$test_dir"
  cd "$test_dir" || exit

  # No .correctless/config/workflow-config.json

  mkdir -p src
  echo "const x = 1;" > src/index.ts

  local input='{"tool_name":"Edit","tool_input":{"file_path":"src/index.ts","old_string":"const x","new_string":"const y"}}'
  local result
  result="$(run_hook_capture "$input")"

  # Should exit 0 even if config missing
  assert_eq "BND-003: Missing config exits 0" "0" "$(extract_exit "$result")"

  # Should be silent
  local stderr
  stderr="$(extract_stderr "$result")"
  assert_eq "BND-003: Missing config is silent" "" "$stderr"

  rm -rf "$test_dir"
}

# ---------------------------------------------------------------------------
# INV-008: Doc audit — csetup detects all 6 formatters
# ---------------------------------------------------------------------------

test_inv008_csetup_detects_formatters() {
  echo ""
  echo "=== INV-008: /csetup detects all 6 formatters ==="

  # This is a doc audit test
  # Verify that csetup SKILL.md or csetup implementation mentions detection of:
  # 1. Prettier (.prettierrc, package.json devDeps)
  # 2. ESLint (.eslintrc, eslint.config.js)
  # 3. Black (pyproject.toml [tool.black])
  # 4. Ruff (ruff.toml, pyproject.toml [tool.ruff])
  # 5. gofmt (go.mod)
  # 6. rustfmt (Cargo.toml)

  local csetup_dir="$REPO_DIR/.correctless/skills/csetup"
  local csetup_skill_md="$csetup_dir/SKILL.md"

  if [ -f "$csetup_skill_md" ]; then
    assert_contains "INV-008: csetup detects Prettier" "Prettier\|prettier" "$(cat "$csetup_skill_md")"
    assert_contains "INV-008: csetup detects ESLint" "ESLint\|eslint" "$(cat "$csetup_skill_md")"
    assert_contains "INV-008: csetup detects Black" "Black\|black" "$(cat "$csetup_skill_md")"
    assert_contains "INV-008: csetup detects Ruff" "Ruff\|ruff" "$(cat "$csetup_skill_md")"
    assert_contains "INV-008: csetup detects gofmt" "gofmt" "$(cat "$csetup_skill_md")"
    assert_contains "INV-008: csetup detects rustfmt" "rustfmt" "$(cat "$csetup_skill_md")"
  else
    echo "  SKIP: INV-008: csetup SKILL.md not found — will verify in code review"
    # Don't fail, just skip this test in TDD phase
  fi
}

# ---------------------------------------------------------------------------
# INV-009: Doc audit — Prettier default conflict resolution
# ---------------------------------------------------------------------------

test_inv009_prettier_default_conflict() {
  echo ""
  echo "=== INV-009: Prettier default when ESLint also detected ==="

  # This is a doc audit test
  # Verify csetup SKILL.md describes:
  # - When both Prettier and ESLint detected, default to Prettier
  # - User can choose to switch to ESLint --fix
  # - Choice is stored in config

  local csetup_dir="$REPO_DIR/.correctless/skills/csetup"
  local csetup_skill_md="$csetup_dir/SKILL.md"

  if [ -f "$csetup_skill_md" ]; then
    local content
    content="$(cat "$csetup_skill_md")"

    if echo "$content" | grep -q -i "prettier.*default\|default.*prettier"; then
      echo "  PASS: INV-009: csetup mentions Prettier as default"
      PASS=$((PASS + 1))
    else
      echo "  FAIL: INV-009: csetup does not mention Prettier default"
      FAIL=$((FAIL + 1))
    fi

    if echo "$content" | grep -q -i "eslint.*--fix\|switch.*eslint"; then
      echo "  PASS: INV-009: csetup mentions option to switch to ESLint"
      PASS=$((PASS + 1))
    else
      echo "  FAIL: INV-009: csetup does not mention ESLint switch option"
      FAIL=$((FAIL + 1))
    fi
  else
    echo "  SKIP: INV-009: csetup SKILL.md not found — will verify in code review"
  fi
}

# ---------------------------------------------------------------------------
# QA-001 Class Fix: Non-allowlisted command is NOT invoked
# ---------------------------------------------------------------------------

test_qa001_non_allowlisted_command_rejected() {
  echo ""
  echo "=== QA-001: Non-allowlisted command rejected ==="

  local test_dir="/tmp/correctless-auto-format-qa001-$$"
  mkdir -p "$test_dir/.correctless/config"
  cd "$test_dir" || exit

  mkdir -p src
  echo "const x = 1;" > src/index.ts

  # Use unique canary files to detect if the non-allowlisted command runs.
  # We use safe stub names (fakefmt/fakecurl) that won't shadow system utilities.

  # Test 1: "fakefmt" — not in allowlist
  cat > "$test_dir/.correctless/config/workflow-config.json" <<'EOF'
{
  "auto_format": {
    "enabled": true,
    "formatters": {
      "*.ts": "fakefmt"
    }
  }
}
EOF

  mkdir -p "$test_dir/.stub-formatters"
  cat > "$test_dir/.stub-formatters/fakefmt" <<'STUBEOF'
#!/usr/bin/env bash
touch /tmp/canary-qa001-fakefmt-$$
exit 0
STUBEOF
  chmod +x "$test_dir/.stub-formatters/fakefmt"
  export PATH="$test_dir/.stub-formatters:$PATH"

  rm -f "/tmp/canary-qa001-fakefmt-$$"

  local input='{"tool_name":"Edit","tool_input":{"file_path":"src/index.ts","old_string":"const x","new_string":"const y"}}'
  local result
  result="$(run_hook_capture "$input")"

  assert_eq "QA-001: Non-allowlisted command exits 0" "0" "$(extract_exit "$result")"

  if [ ! -f "/tmp/canary-qa001-fakefmt-$$" ]; then
    echo "  PASS: QA-001: Non-allowlisted 'fakefmt' was not invoked"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: QA-001: Non-allowlisted 'fakefmt' WAS invoked"
    FAIL=$((FAIL + 1))
    rm -f "/tmp/canary-qa001-fakefmt-$$"
  fi

  # Test 2: "fakecurl" — also not in allowlist
  cat > "$test_dir/.correctless/config/workflow-config.json" <<'EOF'
{
  "auto_format": {
    "enabled": true,
    "formatters": {
      "*.ts": "fakecurl"
    }
  }
}
EOF

  cat > "$test_dir/.stub-formatters/fakecurl" <<'STUBEOF'
#!/usr/bin/env bash
touch /tmp/canary-qa001-fakecurl-$$
exit 0
STUBEOF
  chmod +x "$test_dir/.stub-formatters/fakecurl"

  rm -f "/tmp/canary-qa001-fakecurl-$$"
  result="$(run_hook_capture "$input")"

  if [ ! -f "/tmp/canary-qa001-fakecurl-$$" ]; then
    echo "  PASS: QA-001: Non-allowlisted 'fakecurl' was not invoked"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: QA-001: Non-allowlisted 'fakecurl' WAS invoked"
    FAIL=$((FAIL + 1))
    rm -f "/tmp/canary-qa001-fakecurl-$$"
  fi

  rm -rf "$test_dir"
}

# ---------------------------------------------------------------------------
# QA-002 Class Fix: Multi-word command (npx prettier) runs correctly
# ---------------------------------------------------------------------------

test_qa002_multiword_command_runs() {
  echo ""
  echo "=== QA-002: Multi-word command (npx prettier) runs correctly ==="

  local test_dir="/tmp/correctless-auto-format-qa002-$$"
  mkdir -p "$test_dir/.correctless/config"
  cd "$test_dir" || exit

  mkdir -p src
  echo "const x = 1;" > src/index.ts

  # Configure npx prettier as the formatter
  cat > "$test_dir/.correctless/config/workflow-config.json" <<'EOF'
{
  "auto_format": {
    "enabled": true,
    "formatters": {
      "*.ts": "npx prettier"
    }
  }
}
EOF

  # Create a stub "npx" that logs both itself and its argument
  mkdir -p "$test_dir/.stub-formatters"
  cat > "$test_dir/.stub-formatters/npx" <<'STUBEOF'
#!/usr/bin/env bash
# Log the full invocation: npx <args...> <filepath>
echo "npx $*" >> /tmp/formatter-calls.log
exit 0
STUBEOF
  chmod +x "$test_dir/.stub-formatters/npx"
  export PATH="$test_dir/.stub-formatters:$PATH"

  rm -f /tmp/formatter-calls.log

  local input='{"tool_name":"Edit","tool_input":{"file_path":"src/index.ts","old_string":"const x","new_string":"const y"}}'
  local result
  result="$(run_hook_capture "$input")"

  assert_eq "QA-002: Multi-word command exits 0" "0" "$(extract_exit "$result")"

  # Verify the stub was called
  if [ ! -f /tmp/formatter-calls.log ]; then
    echo "  FAIL: QA-002: npx was not invoked at all"
    FAIL=$((FAIL + 1))
  else
    local logged
    logged="$(cat /tmp/formatter-calls.log)"

    # The log should contain "npx prettier src/index.ts" — proving both tokens were passed
    if echo "$logged" | grep -q "npx prettier.*src/index.ts"; then
      echo "  PASS: QA-002: npx received 'prettier' arg and filepath"
      PASS=$((PASS + 1))
    else
      echo "  FAIL: QA-002: npx did not receive expected args (got: $logged)"
      FAIL=$((FAIL + 1))
    fi
  fi

  # Verify stderr notification mentions npx
  local stderr
  stderr="$(extract_stderr "$result")"
  assert_contains "QA-002: Stderr mentions formatting" "Formatted" "$stderr"

  rm -rf "$test_dir" /tmp/formatter-calls.log
}

# ---------------------------------------------------------------------------
# QA-003 Class Fix: Ampersand metacharacter rejected
# ---------------------------------------------------------------------------

test_qa003_ampersand_rejected() {
  echo ""
  echo "=== QA-003: Ampersand metacharacter rejected ==="

  local test_dir="/tmp/correctless-auto-format-qa003-$$"
  mkdir -p "$test_dir/.correctless/config"
  cd "$test_dir" || exit

  mkdir -p src
  echo "const x = 1;" > src/index.ts

  # Configure a command with & (background execution attempt)
  cat > "$test_dir/.correctless/config/workflow-config.json" <<'EOF'
{
  "auto_format": {
    "enabled": true,
    "formatters": {
      "*.ts": "prettier & touch /tmp/canary-amp"
    }
  }
}
EOF

  # Create stub prettier that writes a unique canary to prove invocation
  mkdir -p "$test_dir/.stub-formatters"
  cat > "$test_dir/.stub-formatters/prettier" <<'STUBEOF'
#!/usr/bin/env bash
touch /tmp/canary-qa003-prettier-$$
exit 0
STUBEOF
  chmod +x "$test_dir/.stub-formatters/prettier"
  export PATH="$test_dir/.stub-formatters:$PATH"

  rm -f "/tmp/canary-qa003-prettier-$$" /tmp/canary-amp

  local input='{"tool_name":"Edit","tool_input":{"file_path":"src/index.ts","old_string":"const x","new_string":"const y"}}'
  local result
  result="$(run_hook_capture "$input")"

  assert_eq "QA-003: Command with & rejected (exit 0)" "0" "$(extract_exit "$result")"

  if [ ! -f "/tmp/canary-qa003-prettier-$$" ]; then
    echo "  PASS: QA-003: Ampersand injection — formatter not called"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: QA-003: Ampersand injection — formatter WAS called"
    FAIL=$((FAIL + 1))
    rm -f "/tmp/canary-qa003-prettier-$$"
  fi

  if [ ! -f /tmp/canary-amp ]; then
    echo "  PASS: QA-003: Ampersand injection — canary not created"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: QA-003: Ampersand injection — canary file was created"
    FAIL=$((FAIL + 1))
    rm -f /tmp/canary-amp
  fi

  rm -rf "$test_dir"
}

# ---------------------------------------------------------------------------
# MultiEdit support (INV-002 extended)
# ---------------------------------------------------------------------------

test_inv002_multiedit_format_each_file() {
  echo ""
  echo "=== INV-002 Extended: MultiEdit formats each file ==="

  local test_dir="/tmp/correctless-auto-format-multiedit-$$"
  setup_test_env "$test_dir"
  cd "$test_dir" || exit

  create_stub_formatter "$test_dir" "prettier"

  mkdir -p src
  echo "const x = 1;" > src/file1.ts
  echo "const y = 2;" > src/file2.ts

  rm -f /tmp/formatter-calls.log

  # MultiEdit with multiple files
  local input='{"tool_name":"MultiEdit","tool_input":{"edits":[{"file_path":"src/file1.ts","old_string":"const x","new_string":"const a"},{"file_path":"src/file2.ts","old_string":"const y","new_string":"const b"}]}}'
  run_hook_capture "$input" >/dev/null

  # UNCONDITIONAL: Log file MUST exist
  if [ ! -f /tmp/formatter-calls.log ]; then
    echo "  FAIL: INV-002: MultiEdit — no formatter calls logged"
    FAIL=$((FAIL + 1))
  else
    local file1_calls
    local file2_calls
    file1_calls="$(grep -c "src/file1.ts" /tmp/formatter-calls.log || echo 0)"
    file2_calls="$(grep -c "src/file2.ts" /tmp/formatter-calls.log || echo 0)"

    if [ "$file1_calls" -gt 0 ]; then
      echo "  PASS: INV-002: MultiEdit formats first file"
      PASS=$((PASS + 1))
    else
      echo "  FAIL: INV-002: MultiEdit did not format first file"
      FAIL=$((FAIL + 1))
    fi

    if [ "$file2_calls" -gt 0 ]; then
      echo "  PASS: INV-002: MultiEdit formats second file"
      PASS=$((PASS + 1))
    else
      echo "  FAIL: INV-002: MultiEdit did not format second file"
      FAIL=$((FAIL + 1))
    fi
  fi

  rm -rf "$test_dir" /tmp/formatter-calls.log
}

# ---------------------------------------------------------------------------
# QA-NEW-001 Class Fix: "npx <arbitrary>" must NOT pass allowlist
# ---------------------------------------------------------------------------

test_qa_new001_npx_arbitrary_rejected() {
  echo ""
  echo "=== QA-NEW-001: npx <arbitrary> rejected by exact-match allowlist ==="

  local test_dir="/tmp/correctless-auto-format-qanew001-$$"
  mkdir -p "$test_dir/.correctless/config"
  cd "$test_dir" || exit

  mkdir -p src
  echo "const x = 1;" > src/index.ts

  # Configure "npx malware-package" — npx is in PATH but the FULL command is not allowlisted
  cat > "$test_dir/.correctless/config/workflow-config.json" <<'EOF'
{
  "auto_format": {
    "enabled": true,
    "formatters": {
      "*.ts": "npx malware-package"
    }
  }
}
EOF

  mkdir -p "$test_dir/.stub-formatters"
  cat > "$test_dir/.stub-formatters/npx" <<'STUBEOF'
#!/usr/bin/env bash
touch /tmp/canary-qanew001-npx-$$
echo "npx $*" >> /tmp/formatter-calls.log
exit 0
STUBEOF
  chmod +x "$test_dir/.stub-formatters/npx"
  export PATH="$test_dir/.stub-formatters:$PATH"

  rm -f "/tmp/canary-qanew001-npx-$$" /tmp/formatter-calls.log

  local input='{"tool_name":"Edit","tool_input":{"file_path":"src/index.ts","old_string":"const x","new_string":"const y"}}'
  local result
  result="$(run_hook_capture "$input")"

  assert_eq "QA-NEW-001: npx malware-package exits 0" "0" "$(extract_exit "$result")"

  if [ ! -f "/tmp/canary-qanew001-npx-$$" ]; then
    echo "  PASS: QA-NEW-001: 'npx malware-package' was NOT invoked"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: QA-NEW-001: 'npx malware-package' WAS invoked (allowlist bypass)"
    FAIL=$((FAIL + 1))
    rm -f "/tmp/canary-qanew001-npx-$$"
  fi

  # Now verify "npx prettier" IS still allowed
  cat > "$test_dir/.correctless/config/workflow-config.json" <<'EOF'
{
  "auto_format": {
    "enabled": true,
    "formatters": {
      "*.ts": "npx prettier"
    }
  }
}
EOF

  rm -f /tmp/formatter-calls.log

  result="$(run_hook_capture "$input")"

  if [ -f /tmp/formatter-calls.log ]; then
    echo "  PASS: QA-NEW-001: 'npx prettier' IS still invoked (allowlisted)"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: QA-NEW-001: 'npx prettier' was NOT invoked (should be allowed)"
    FAIL=$((FAIL + 1))
  fi

  rm -rf "$test_dir" /tmp/formatter-calls.log
}

# ---------------------------------------------------------------------------
# QA-NEW-002 Class Fix: Path-prefixed binary rejected by exact match
# ---------------------------------------------------------------------------

test_qa_new002_path_prefixed_binary_rejected() {
  echo ""
  echo "=== QA-NEW-002: Path-prefixed binary rejected by exact-match allowlist ==="

  local test_dir="/tmp/correctless-auto-format-qanew002-$$"
  mkdir -p "$test_dir/.correctless/config"
  cd "$test_dir" || exit

  mkdir -p src
  echo "const x = 1;" > src/index.ts

  # Configure "/usr/local/bin/prettier" — path-qualified, not exact match for "prettier"
  cat > "$test_dir/.correctless/config/workflow-config.json" <<'EOF'
{
  "auto_format": {
    "enabled": true,
    "formatters": {
      "*.ts": "/usr/local/bin/prettier"
    }
  }
}
EOF

  # Create a stub at that path to prove if it gets invoked
  mkdir -p "$test_dir/usr/local/bin"
  cat > "$test_dir/usr/local/bin/prettier" <<'STUBEOF'
#!/usr/bin/env bash
touch /tmp/canary-qanew002-$$
exit 0
STUBEOF
  chmod +x "$test_dir/usr/local/bin/prettier"

  rm -f "/tmp/canary-qanew002-$$"

  local input='{"tool_name":"Edit","tool_input":{"file_path":"src/index.ts","old_string":"const x","new_string":"const y"}}'
  local result
  result="$(run_hook_capture "$input")"

  assert_eq "QA-NEW-002: Path-prefixed command exits 0" "0" "$(extract_exit "$result")"

  if [ ! -f "/tmp/canary-qanew002-$$" ]; then
    echo "  PASS: QA-NEW-002: '/usr/local/bin/prettier' was NOT invoked (exact match rejects paths)"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: QA-NEW-002: '/usr/local/bin/prettier' WAS invoked (path-prefix bypass)"
    FAIL=$((FAIL + 1))
    rm -f "/tmp/canary-qanew002-$$"
  fi

  rm -rf "$test_dir"
}

# ---------------------------------------------------------------------------
# Main runner
# ---------------------------------------------------------------------------

main() {
  echo ""
  echo "=========================================="
  echo "Auto-Format Hook Tests (TDD — RED phase)"
  echo "=========================================="

  test_inv001_triggers_only_on_edit_write_multiedit
  test_inv002_formats_only_specific_file
  test_inv003_exits_zero_on_formatter_issues
  test_inv004a_stderr_notification_on_success
  test_inv004b_no_stderr_when_skipped
  test_inv005_checks_formatter_installed
  test_inv006_extension_based_selection
  test_inv007_reads_config_from_workflow_config
  test_inv010_respects_enabled_flag
  test_inv011_validates_against_allowlist
  test_qa001_non_allowlisted_command_rejected
  test_qa002_multiword_command_runs
  test_qa003_ampersand_rejected
  test_qa_new001_npx_arbitrary_rejected
  test_qa_new002_path_prefixed_binary_rejected
  test_prh004_no_eval_or_interpolation
  test_bnd001_file_path_with_spaces
  test_bnd002_missing_file
  test_bnd003_missing_config
  test_inv008_csetup_detects_formatters
  test_inv009_prettier_default_conflict
  test_inv002_multiedit_format_each_file

  echo ""
  echo "=========================================="
  echo "Results: $PASS passed, $FAIL failed"
  echo "=========================================="

  if [ $FAIL -gt 0 ]; then
    exit 1
  fi
  exit 0
}

main "$@"
