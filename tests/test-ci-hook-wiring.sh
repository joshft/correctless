#!/usr/bin/env bash
# shellcheck disable=SC1090  # Dynamic source path (SETUP) always resolves to setup
# Correctless — CI Completeness and Hook Auto-Registration Tests
# Tests all 9 invariants + 2 prohibitions from:
#   .correctless/specs/ci-hook-wiring.md
# RED phase: these tests MUST FAIL against current code.
# Run from repo root: bash tests/test-ci-hook-wiring.sh

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0

# ============================================================================
# Helpers (same pattern as test-hook-sync.sh / test-lib.sh)
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

assert_not_contains() {
  local desc="$1" unexpected="$2" actual="$3"
  if grep -qF "$unexpected" <<< "$actual"; then
    echo "  FAIL: $desc (expected output NOT to contain '$unexpected')"
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
    echo "  FAIL: $desc (file '$path' should not exist)"
    FAIL=$((FAIL + 1))
  fi
}

assert_match() {
  local desc="$1" pattern="$2" actual="$3"
  if printf '%s\n' "$actual" | grep -qE -- "$pattern"; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (expected output to match pattern '$pattern')"
    FAIL=$((FAIL + 1))
  fi
}

# ============================================================================
# Test environment setup
# ============================================================================

TEST_DIR="/tmp/correctless-test-ci-hook-wiring-$$"

cleanup() {
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

setup_test_project() {
  rm -rf "$TEST_DIR"
  mkdir -p "$TEST_DIR"
  cd "$TEST_DIR" || exit 1
  git init -q
  git branch -M main
  echo "init" > README.md
  git add -A && git commit -q -m "init"

  # Install correctless (exclude .git to avoid nested repo confusion)
  mkdir -p .claude/skills/workflow
  rsync -a --exclude='.git' --exclude='tests' "$REPO_DIR/" .claude/skills/workflow/
}

echo "Correctless CI Completeness and Hook Auto-Registration Tests"
echo "============================================================="

# ============================================================================
# INV-001 [unit]: CI runs all test suites
# Every tests/test*.sh on disk must appear in commands.test.
# Every file in commands.test must appear in ci.yml.
# commands.test_new must be empty string "" after this feature merges.
# ============================================================================

test_inv001_ci_runs_all_test_suites() {
  echo ""
  echo "=== INV-001: CI runs all test suites ==="

  local ci_file="$REPO_DIR/.github/workflows/ci.yml"
  local config_file="$REPO_DIR/.correctless/config/workflow-config.json"

  # Collect all test files on disk (skip test-helpers.sh — shared harness, not a standalone test)
  local -a disk_tests=()
  while IFS= read -r f; do
    local _bn; _bn="$(basename "$f")"
    [ "$_bn" = "test-helpers.sh" ] && continue
    disk_tests+=("$_bn")
  done < <(find "$REPO_DIR/tests" -maxdepth 1 -name 'test*.sh' -type f | sort)

  # Parse commands.test from config — extract individual "bash tests/test-xxx.sh" entries
  local test_cmd
  test_cmd="$(jq -r '.commands.test' "$config_file")"

  # DA-002: commands.test may use glob-based discovery (test-*.sh).
  # If glob is used, all test-*.sh files are automatically discovered.
  local missing_from_config=0
  if echo "$test_cmd" | grep -qE 'test-\*\.sh'; then
    missing_from_config=0  # glob discovers all files
  else
    for t in "${disk_tests[@]}"; do
      if ! echo "$test_cmd" | grep -qF "tests/$t"; then
        echo "    missing from commands.test: $t"
        missing_from_config=1
      fi
    done
  fi
  assert_eq "INV-001: all disk test files in commands.test" "0" "$missing_from_config"

  # Parse CI file — extract lines that run test files
  local ci_content
  ci_content="$(cat "$ci_file")"

  # Check each file in commands.test appears in CI
  local missing_from_ci=0
  # Extract individual test file references from commands.test
  local -a config_tests=()
  while IFS= read -r entry; do
    config_tests+=("$entry")
  done < <(echo "$test_cmd" | grep -oE 'tests/test[^ ]*\.sh')

  for ct in "${config_tests[@]}"; do
    if ! echo "$ci_content" | grep -qF "$ct"; then
      echo "    missing from ci.yml: $ct"
      missing_from_ci=1
    fi
  done
  assert_eq "INV-001: all commands.test entries in ci.yml" "0" "$missing_from_ci"

  # commands.test_new must be empty (empty string, null, or absent)
  local test_new
  test_new="$(jq -r '.commands.test_new // ""' "$config_file")"
  assert_eq "INV-001: commands.test_new is empty" "" "$test_new"
}

# ============================================================================
# INV-002 [unit]: Hook metadata headers present
# Each auto-registered hook must have HOOK_TYPE and HOOK_MATCHER in first 10 lines.
# workflow-advance.sh and statusline.sh must NOT have HOOK_TYPE headers.
# ============================================================================

test_inv002_hook_metadata_headers() {
  echo ""
  echo "=== INV-002: Hook metadata headers present ==="

  # Hooks that should have metadata headers (auto-registered as PreToolUse/PostToolUse)
  local -a auto_hooks=(workflow-gate.sh sensitive-file-guard.sh audit-trail.sh token-tracking.sh auto-format.sh)
  # Hooks that must NOT have metadata headers
  local -a excluded_hooks=(workflow-advance.sh statusline.sh)

  for hook in "${auto_hooks[@]}"; do
    local hook_path="$REPO_DIR/hooks/$hook"
    if [ ! -f "$hook_path" ]; then
      echo "  FAIL: INV-002: $hook not found in hooks/ (may need to be moved there first)"
      FAIL=$((FAIL + 1))
      continue
    fi

    # Check HOOK_TYPE header in first 10 lines
    local first10
    first10="$(head -10 "$hook_path")"

    local has_type="false"
    if echo "$first10" | grep -qE '^# HOOK_TYPE:[[:space:]]*(PreToolUse|PostToolUse)[[:space:]]*$'; then
      has_type="true"
    fi
    assert_eq "INV-002: $hook has valid HOOK_TYPE header" "true" "$has_type"

    # Check HOOK_TYPE value is exactly PreToolUse or PostToolUse
    local type_val
    type_val="$(echo "$first10" | sed -n 's/^# HOOK_TYPE:[[:space:]]*\([^ ]*\).*/\1/p')"
    if [ -n "$type_val" ]; then
      local valid_type="false"
      if [ "$type_val" = "PreToolUse" ] || [ "$type_val" = "PostToolUse" ]; then
        valid_type="true"
      fi
      assert_eq "INV-002: $hook HOOK_TYPE is PreToolUse or PostToolUse" "true" "$valid_type"
    fi

    # Check HOOK_MATCHER header in first 10 lines
    local has_matcher="false"
    if echo "$first10" | grep -qE '^# HOOK_MATCHER:[[:space:]]*.+$'; then
      has_matcher="true"
    fi
    assert_eq "INV-002: $hook has HOOK_MATCHER header" "true" "$has_matcher"

    # Check HOOK_MATCHER value is non-empty pipe-separated list
    local matcher_val
    matcher_val="$(echo "$first10" | sed -n 's/^# HOOK_MATCHER:[[:space:]]*//p')"
    local valid_matcher="false"
    if [ -n "$matcher_val" ] && echo "$matcher_val" | grep -qE '^[A-Za-z]+(\|[A-Za-z]+)*$'; then
      valid_matcher="true"
    fi
    assert_eq "INV-002: $hook HOOK_MATCHER is non-empty pipe-separated list" "true" "$valid_matcher"
  done

  # Verify excluded hooks do NOT have HOOK_TYPE headers
  for hook in "${excluded_hooks[@]}"; do
    local hook_path="$REPO_DIR/hooks/$hook"
    if [ ! -f "$hook_path" ]; then
      echo "  FAIL: INV-002: $hook not found in hooks/"
      FAIL=$((FAIL + 1))
      continue
    fi

    local first10
    first10="$(head -10 "$hook_path")"
    local has_type="false"
    if echo "$first10" | grep -qE '^# HOOK_TYPE:'; then
      has_type="true"
    fi
    assert_eq "INV-002: $hook does NOT have HOOK_TYPE header" "false" "$has_type"
  done
}

# ============================================================================
# INV-003 [integration]: install_hooks() auto-discovers hooks
# Adding a new .sh file to hooks/ and running install_hooks() copies it
# to .correctless/hooks/ without any code change to setup.
# ============================================================================

test_inv003_install_hooks_auto_discovers() {
  echo ""
  echo "=== INV-003: install_hooks() auto-discovers hooks ==="

  setup_test_project

  # Add a new test hook file to the source hooks directory
  cat > .claude/skills/workflow/hooks/test-new-hook.sh <<'EOF'
#!/usr/bin/env bash
# HOOK_TYPE: PreToolUse
# HOOK_MATCHER: Edit|Write
echo "test hook"
exit 0
EOF
  chmod +x .claude/skills/workflow/hooks/test-new-hook.sh

  # Run setup (which calls install_hooks internally)
  .claude/skills/workflow/setup >/dev/null 2>&1

  # Verify the new hook was copied to .correctless/hooks/
  assert_eq "INV-003: new hook auto-discovered and installed" "true" \
    "$([ -f .correctless/hooks/test-new-hook.sh ] && echo true || echo false)"
}

# ============================================================================
# INV-004 [integration]: register_hooks() reads metadata headers
# Hooks are registered in settings.json using HOOK_TYPE and HOOK_MATCHER
# from their metadata headers. Timeouts: PreToolUse=5000, PostToolUse=1000.
# No hardcoded matcher strings in register_hooks() function body.
# ============================================================================

test_inv004_register_hooks_reads_metadata() {
  echo ""
  echo "=== INV-004: register_hooks() reads metadata headers ==="

  setup_test_project

  # Create hooks with known metadata headers
  mkdir -p .claude/skills/workflow/hooks
  cat > .claude/skills/workflow/hooks/test-pre-hook.sh <<'EOF'
#!/usr/bin/env bash
# HOOK_TYPE: PreToolUse
# HOOK_MATCHER: Edit|Write|Bash
exit 0
EOF
  cat > .claude/skills/workflow/hooks/test-post-hook.sh <<'EOF'
#!/usr/bin/env bash
# HOOK_TYPE: PostToolUse
# HOOK_MATCHER: Agent|Bash
exit 0
EOF
  chmod +x .claude/skills/workflow/hooks/test-pre-hook.sh
  chmod +x .claude/skills/workflow/hooks/test-post-hook.sh

  # Run setup
  .claude/skills/workflow/setup >/dev/null 2>&1

  local settings=".claude/settings.json"
  if [ ! -f "$settings" ]; then
    echo "  FAIL: INV-004: settings.json not created"
    FAIL=$((FAIL + 1))
    return
  fi

  # Verify test-pre-hook appears as PreToolUse with correct matcher and timeout
  local pre_entry
  pre_entry="$(jq -r '.hooks.PreToolUse[]? | select(.hooks[]?.command | test("test-pre-hook"))' "$settings" 2>/dev/null || echo "")"

  local pre_matcher
  pre_matcher="$(echo "$pre_entry" | jq -r '.matcher // ""' 2>/dev/null || echo "")"
  assert_eq "INV-004: test-pre-hook matcher from header" "Edit|Write|Bash" "$pre_matcher"

  local pre_timeout
  pre_timeout="$(echo "$pre_entry" | jq -r '.hooks[0].timeout_ms // 0' 2>/dev/null || echo "0")"
  assert_eq "INV-004: PreToolUse timeout is 5000" "5000" "$pre_timeout"

  # Verify test-post-hook appears as PostToolUse with correct matcher and timeout
  local post_entry
  post_entry="$(jq -r '.hooks.PostToolUse[]? | select(.hooks[]?.command | test("test-post-hook"))' "$settings" 2>/dev/null || echo "")"

  local post_matcher
  post_matcher="$(echo "$post_entry" | jq -r '.matcher // ""' 2>/dev/null || echo "")"
  assert_eq "INV-004: test-post-hook matcher from header" "Agent|Bash" "$post_matcher"

  local post_timeout
  post_timeout="$(echo "$post_entry" | jq -r '.hooks[0].timeout_ms // 0' 2>/dev/null || echo "0")"
  assert_eq "INV-004: PostToolUse timeout is 1000" "1000" "$post_timeout"

  # Verify no hardcoded matcher strings for specific hook filenames in register_hooks()
  # Extract register_hooks function body from setup
  local setup_file=".claude/skills/workflow/setup"
  local func_body
  func_body="$(sed -n '/^register_hooks()/,/^}/p' "$setup_file")"

  # Check for hardcoded hook-to-matcher mappings (excluding workflow-advance.sh and statusline.sh per INV-007)
  local has_hardcoded="false"
  for hookname in workflow-gate audit-trail token-tracking sensitive-file-guard auto-format; do
    # Look for the hook filename appearing near a matcher string assignment
    if echo "$func_body" | grep -q "\"$hookname" 2>/dev/null; then
      # Only flag if it's in a matcher context (not just a variable path reference)
      if echo "$func_body" | grep -E "(matcher.*$hookname|$hookname.*matcher)" 2>/dev/null | grep -qv "^#"; then
        has_hardcoded="true"
      fi
    fi
  done
  # Alternative: the function should not contain hardcoded matcher strings at all for specific hooks
  # Check that register_hooks doesn't contain explicit matcher strings like "Edit|Write|MultiEdit..."
  # associated with specific hook filenames
  if echo "$func_body" | grep -qE '"Edit\|Write\|MultiEdit' 2>/dev/null; then
    has_hardcoded="true"
  fi
  assert_eq "INV-004: no hardcoded matchers in register_hooks" "false" "$has_hardcoded"
}

# ============================================================================
# INV-005 [unit]: auto-format.sh lives in hooks/ source directory
# hooks/auto-format.sh must exist (source), .claude/hooks/auto-format.sh must not.
# auto-format.sh must have valid HOOK_TYPE/HOOK_MATCHER headers.
# sync.sh --check must pass (auto-format.sh synced correctly).
# ============================================================================

test_inv005_auto_format_in_hooks() {
  echo ""
  echo "=== INV-005: auto-format.sh lives in hooks/ ==="

  # Verify hooks/auto-format.sh exists (source directory)
  assert_file_exists "INV-005: hooks/auto-format.sh exists" "$REPO_DIR/hooks/auto-format.sh"

  # Verify .claude/hooks/auto-format.sh does NOT exist (old location deleted)
  assert_file_not_exists "INV-005: .claude/hooks/auto-format.sh deleted" "$REPO_DIR/.claude/hooks/auto-format.sh"

  # If hooks/auto-format.sh exists, verify it has valid metadata headers
  if [ -f "$REPO_DIR/hooks/auto-format.sh" ]; then
    local first10
    first10="$(head -10 "$REPO_DIR/hooks/auto-format.sh")"

    local has_type="false"
    if echo "$first10" | grep -qE '^# HOOK_TYPE:[[:space:]]*(PreToolUse|PostToolUse)[[:space:]]*$'; then
      has_type="true"
    fi
    assert_eq "INV-005: auto-format.sh has valid HOOK_TYPE" "true" "$has_type"

    local has_matcher="false"
    if echo "$first10" | grep -qE '^# HOOK_MATCHER:[[:space:]]*.+$'; then
      has_matcher="true"
    fi
    assert_eq "INV-005: auto-format.sh has HOOK_MATCHER" "true" "$has_matcher"
  fi

  # Verify sync.sh --check passes (auto-format.sh synced)
  local sync_exit
  cd "$REPO_DIR" && bash sync.sh --check >/dev/null 2>&1 && sync_exit=0 || sync_exit=$?
  assert_eq "INV-005: sync.sh --check passes" "0" "$sync_exit"
}

# ============================================================================
# INV-006 [integration]: Non-hook files excluded from registration
# A .sh file in hooks/ without HOOK_TYPE header is installed (copied) but
# NOT registered in settings.json as a hook entry.
# ============================================================================

test_inv006_non_hook_files_excluded() {
  echo ""
  echo "=== INV-006: Non-hook files excluded from registration ==="

  setup_test_project

  # Add a non-hook utility file (no HOOK_TYPE header) to hooks/
  cat > .claude/skills/workflow/hooks/helper-utils.sh <<'EOF'
#!/usr/bin/env bash
# A shared utility file — not a hook
# No HOOK_TYPE header here

useful_function() {
  echo "I am a utility, not a hook"
}
EOF
  chmod +x .claude/skills/workflow/hooks/helper-utils.sh

  # Run setup
  .claude/skills/workflow/setup >/dev/null 2>&1

  # Verify the file was copied (installed) to .correctless/hooks/
  assert_eq "INV-006: non-hook file installed to .correctless/hooks/" "true" \
    "$([ -f .correctless/hooks/helper-utils.sh ] && echo true || echo false)"

  # Verify it does NOT appear in settings.json hook entries
  local settings=".claude/settings.json"
  if [ -f "$settings" ]; then
    local in_pre in_post
    in_pre="$(jq -r '[.hooks.PreToolUse[]? | .hooks[]?.command] | any(test("helper-utils"))' "$settings" 2>/dev/null || echo "false")"
    in_post="$(jq -r '[.hooks.PostToolUse[]? | .hooks[]?.command] | any(test("helper-utils"))' "$settings" 2>/dev/null || echo "false")"
    assert_eq "INV-006: non-hook file NOT in PreToolUse entries" "false" "$in_pre"
    assert_eq "INV-006: non-hook file NOT in PostToolUse entries" "false" "$in_post"
  else
    echo "  FAIL: INV-006: settings.json not found"
    FAIL=$((FAIL + 1))
  fi
}

# ============================================================================
# INV-007 [integration]: workflow-advance.sh and statusline.sh stay hardcoded
# settings.json has permissions.allow entry for workflow-advance,
# statusLine entry for statusline. Neither appears as PreToolUse/PostToolUse hook.
# ============================================================================

test_inv007_hardcoded_entries_preserved() {
  echo ""
  echo "=== INV-007: workflow-advance.sh and statusline.sh stay hardcoded ==="

  setup_test_project
  .claude/skills/workflow/setup >/dev/null 2>&1

  local settings=".claude/settings.json"
  if [ ! -f "$settings" ]; then
    echo "  FAIL: INV-007: settings.json not created"
    FAIL=$((FAIL + 1))
    return
  fi

  # Verify permissions.allow has workflow-advance entry
  local has_perm
  has_perm="$(jq -r '.permissions.allow // [] | any(test("workflow-advance"))' "$settings" 2>/dev/null || echo "false")"
  assert_eq "INV-007: workflow-advance in permissions.allow" "true" "$has_perm"

  # Verify statusLine entry exists for statusline
  local has_statusline
  has_statusline="$(jq -r '.statusLine.command // "" | test("statusline")' "$settings" 2>/dev/null || echo "false")"
  assert_eq "INV-007: statusline in statusLine.command" "true" "$has_statusline"

  # Verify workflow-advance does NOT appear in PreToolUse or PostToolUse hooks
  local advance_in_pre advance_in_post
  advance_in_pre="$(jq -r '[.hooks.PreToolUse[]? | .hooks[]?.command] | any(test("workflow-advance"))' "$settings" 2>/dev/null || echo "false")"
  advance_in_post="$(jq -r '[.hooks.PostToolUse[]? | .hooks[]?.command] | any(test("workflow-advance"))' "$settings" 2>/dev/null || echo "false")"
  assert_eq "INV-007: workflow-advance NOT in PreToolUse hooks" "false" "$advance_in_pre"
  assert_eq "INV-007: workflow-advance NOT in PostToolUse hooks" "false" "$advance_in_post"

  # Verify statusline does NOT appear in PreToolUse or PostToolUse hooks
  local sl_in_pre sl_in_post
  sl_in_pre="$(jq -r '[.hooks.PreToolUse[]? | .hooks[]?.command] | any(test("statusline"))' "$settings" 2>/dev/null || echo "false")"
  sl_in_post="$(jq -r '[.hooks.PostToolUse[]? | .hooks[]?.command] | any(test("statusline"))' "$settings" 2>/dev/null || echo "false")"
  assert_eq "INV-007: statusline NOT in PreToolUse hooks" "false" "$sl_in_pre"
  assert_eq "INV-007: statusline NOT in PostToolUse hooks" "false" "$sl_in_post"
}

# ============================================================================
# INV-008 [unit]: ShellCheck CI scans scripts/ directory
# ci.yml shellcheck config must include scripts/ directory.
# scripts/lib.sh and scripts/antipattern-scan.sh must be covered.
# ============================================================================

test_inv008_shellcheck_scans_scripts() {
  echo ""
  echo "=== INV-008: ShellCheck CI scans scripts/ directory ==="

  local ci_file="$REPO_DIR/.github/workflows/ci.yml"
  local ci_content
  ci_content="$(cat "$ci_file")"

  # Check that scripts/ directory is covered by ShellCheck
  # Either via scandir change or additional_files listing scripts/*.sh
  local covers_scripts="false"

  # Option A: scandir changed to include scripts/ (e.g., scandir: . with ignores)
  if echo "$ci_content" | grep -qE 'scandir:.*scripts'; then
    covers_scripts="true"
  fi

  # Option B: additional_files includes scripts/*.sh files
  if echo "$ci_content" | grep -q 'scripts/lib.sh'; then
    covers_scripts="true"
  fi
  if echo "$ci_content" | grep -q 'scripts/antipattern-scan.sh'; then
    covers_scripts="true"
  fi

  # Option C: scandir is . (scans everything)
  if echo "$ci_content" | grep -qE 'scandir:[[:space:]]*\.[[:space:]]*$'; then
    covers_scripts="true"
  fi

  assert_eq "INV-008: CI shellcheck covers scripts/ directory" "true" "$covers_scripts"

  # Specifically verify scripts/lib.sh would be scanned
  # This is a secondary check — if scandir covers scripts/, this passes implicitly
  local lib_covered="false"
  if echo "$ci_content" | grep -qE '(scripts/lib\.sh|scandir:[[:space:]]*\./?[[:space:]]*$|scandir:.*scripts)'; then
    lib_covered="true"
  fi
  assert_eq "INV-008: scripts/lib.sh covered by shellcheck" "true" "$lib_covered"

  # Verify scripts/antipattern-scan.sh would be scanned
  local scan_covered="false"
  if echo "$ci_content" | grep -qE '(scripts/antipattern-scan\.sh|scandir:[[:space:]]*\./?[[:space:]]*$|scandir:.*scripts)'; then
    scan_covered="true"
  fi
  assert_eq "INV-008: scripts/antipattern-scan.sh covered by shellcheck" "true" "$scan_covered"
}

# ============================================================================
# INV-009 [integration]: Existing setup behavior preserved
# After refactoring, settings.json contains identical entries for existing hooks.
# Verify specific expected matchers, types, and timeouts.
# ============================================================================

test_inv009_existing_behavior_preserved() {
  echo ""
  echo "=== INV-009: Existing setup behavior preserved ==="

  setup_test_project
  .claude/skills/workflow/setup >/dev/null 2>&1

  local settings=".claude/settings.json"
  if [ ! -f "$settings" ]; then
    echo "  FAIL: INV-009: settings.json not created"
    FAIL=$((FAIL + 1))
    return
  fi

  # workflow-gate.sh: PreToolUse, Edit|Write|MultiEdit|NotebookEdit|CreateFile|Bash, timeout 5000
  local gate_entry
  gate_entry="$(jq -r '.hooks.PreToolUse[]? | select(.hooks[]?.command | test("workflow-gate"))' "$settings" 2>/dev/null || echo "")"

  local gate_matcher
  gate_matcher="$(echo "$gate_entry" | jq -r '.matcher // ""' 2>/dev/null || echo "")"
  assert_eq "INV-009: workflow-gate matcher" "Edit|Write|MultiEdit|NotebookEdit|CreateFile|Bash" "$gate_matcher"

  local gate_timeout
  gate_timeout="$(echo "$gate_entry" | jq -r '.hooks[0].timeout_ms // 0' 2>/dev/null || echo "0")"
  assert_eq "INV-009: workflow-gate timeout" "5000" "$gate_timeout"

  # audit-trail.sh: PostToolUse, Edit|Write|MultiEdit|CreateFile|Bash, timeout 1000
  local audit_entry
  audit_entry="$(jq -r '.hooks.PostToolUse[]? | select(.hooks[]?.command | test("audit-trail"))' "$settings" 2>/dev/null || echo "")"

  local audit_matcher
  audit_matcher="$(echo "$audit_entry" | jq -r '.matcher // ""' 2>/dev/null || echo "")"
  assert_eq "INV-009: audit-trail matcher" "Edit|Write|MultiEdit|NotebookEdit|CreateFile|Bash|Read|Grep" "$audit_matcher"

  local audit_timeout
  audit_timeout="$(echo "$audit_entry" | jq -r '.hooks[0].timeout_ms // 0' 2>/dev/null || echo "0")"
  assert_eq "INV-009: audit-trail timeout" "1000" "$audit_timeout"

  # token-tracking.sh: PostToolUse, Agent, timeout 1000
  local tt_entry
  tt_entry="$(jq -r '.hooks.PostToolUse[]? | select(.hooks[]?.command | test("token-tracking"))' "$settings" 2>/dev/null || echo "")"

  local tt_matcher
  tt_matcher="$(echo "$tt_entry" | jq -r '.matcher // ""' 2>/dev/null || echo "")"
  assert_eq "INV-009: token-tracking matcher" "Agent" "$tt_matcher"

  local tt_timeout
  tt_timeout="$(echo "$tt_entry" | jq -r '.hooks[0].timeout_ms // 0' 2>/dev/null || echo "0")"
  assert_eq "INV-009: token-tracking timeout" "1000" "$tt_timeout"

  # sensitive-file-guard.sh: must be registered as PreToolUse with correct matcher and timeout
  local sfg_entry
  sfg_entry="$(jq -r '.hooks.PreToolUse[]? | select(.hooks[]?.command | test("sensitive-file-guard"))' "$settings" 2>/dev/null || echo "")"
  local sfg_present="false"
  if [ -n "$sfg_entry" ]; then
    sfg_present="true"
  fi
  assert_eq "INV-009: sensitive-file-guard registered as PreToolUse" "true" "$sfg_present"

  local sfg_matcher
  sfg_matcher="$(echo "$sfg_entry" | jq -r '.matcher // ""' 2>/dev/null || echo "")"
  assert_eq "INV-009: sensitive-file-guard matcher matches HOOK_MATCHER" "Edit|Write|MultiEdit|NotebookEdit|CreateFile|Bash" "$sfg_matcher"

  local sfg_timeout
  sfg_timeout="$(echo "$sfg_entry" | jq -r '.hooks[0].timeout_ms // 0' 2>/dev/null || echo "0")"
  assert_eq "INV-009: sensitive-file-guard timeout (PreToolUse=5000)" "5000" "$sfg_timeout"

  # auto-format.sh: must be registered as PostToolUse with correct matcher and timeout
  local af_entry
  af_entry="$(jq -r '.hooks.PostToolUse[]? | select(.hooks[]?.command | test("auto-format"))' "$settings" 2>/dev/null || echo "")"
  local af_present="false"
  if [ -n "$af_entry" ]; then
    af_present="true"
  fi
  assert_eq "INV-009: auto-format registered as PostToolUse" "true" "$af_present"

  local af_matcher
  af_matcher="$(echo "$af_entry" | jq -r '.matcher // ""' 2>/dev/null || echo "")"
  assert_eq "INV-009: auto-format matcher matches HOOK_MATCHER" "Edit|Write|MultiEdit" "$af_matcher"

  local af_timeout
  af_timeout="$(echo "$af_entry" | jq -r '.hooks[0].timeout_ms // 0' 2>/dev/null || echo "0")"
  assert_eq "INV-009: auto-format timeout (PostToolUse=1000)" "1000" "$af_timeout"
}

# ============================================================================
# QA-002/QA-004 [integration]: Existing settings.json update path
# Verifies that re-running setup with existing settings.json:
# (a) appends newly discovered hooks, (b) updates stale matchers,
# (c) preserves custom entries.
# ============================================================================

test_qa_existing_settings_update() {
  echo ""
  echo "=== QA-002/QA-004: Existing settings.json update path ==="

  setup_test_project

  # Step 1: Run setup to create fresh settings.json
  (cd "$TEST_DIR" && REPO_ROOT="$TEST_DIR" SCRIPT_DIR="$TEST_DIR/.claude/skills/workflow" \
    bash "$TEST_DIR/.claude/skills/workflow/setup" >/dev/null 2>&1)

  local settings="$TEST_DIR/.claude/settings.json"
  assert_eq "QA-004: settings.json created on first run" "true" \
    "$([ -f "$settings" ] && echo true || echo false)"

  # Step 2: Verify workflow-gate matcher is correct (full matcher from header)
  local wg_matcher
  wg_matcher="$(jq -r '(.hooks.PreToolUse // [] | .[] | select(.hooks[]?.command | test("workflow-gate")) | .matcher) // ""' "$settings" 2>/dev/null || echo "")"
  assert_eq "QA-004: workflow-gate has correct initial matcher" "Edit|Write|MultiEdit|NotebookEdit|CreateFile|Bash" "$wg_matcher"

  # Step 3: Manually narrow the matcher (simulate drift/old install)
  jq '(.hooks.PreToolUse[] | select(.hooks[]?.command | test("workflow-gate")) | .matcher) = "Edit|Write"' "$settings" > "$settings.tmp" \
    && mv "$settings.tmp" "$settings"

  # Step 4: Re-run setup — should detect matcher drift and update
  (cd "$TEST_DIR" && REPO_ROOT="$TEST_DIR" SCRIPT_DIR="$TEST_DIR/.claude/skills/workflow" \
    bash "$TEST_DIR/.claude/skills/workflow/setup" >/dev/null 2>&1)

  # Step 5: Verify matcher was updated from HOOK_MATCHER header
  local updated_matcher
  updated_matcher="$(jq -r '(.hooks.PreToolUse // [] | .[] | select(.hooks[]?.command | test("workflow-gate")) | .matcher) // ""' "$settings" 2>/dev/null || echo "")"
  assert_eq "QA-002: stale matcher updated from HOOK_MATCHER header" "Edit|Write|MultiEdit|NotebookEdit|CreateFile|Bash" "$updated_matcher"

  # Step 6: Add a custom hook entry and verify it's preserved on re-run
  jq '.hooks.PreToolUse += [{ matcher: "Bash", hooks: [{ type: "command", command: "my-custom-hook.sh" }] }]' "$settings" > "$settings.tmp" \
    && mv "$settings.tmp" "$settings"

  (cd "$TEST_DIR" && REPO_ROOT="$TEST_DIR" SCRIPT_DIR="$TEST_DIR/.claude/skills/workflow" \
    bash "$TEST_DIR/.claude/skills/workflow/setup" >/dev/null 2>&1)

  local custom_preserved
  custom_preserved="$(jq -r '(.hooks.PreToolUse // [] | .[] | select(.hooks[]?.command == "my-custom-hook.sh") | .matcher) // ""' "$settings" 2>/dev/null || echo "")"
  assert_eq "QA-004: custom hook entry preserved on re-run" "Bash" "$custom_preserved"
}

# ============================================================================
# R2-001/R2-002 [integration]: Invalid/empty settings.json recovery
# Verifies that register_hooks() recovers from corrupted or empty settings.json.
# ============================================================================

test_invalid_json_recovery() {
  echo ""
  echo "=== R2-001/R2-002: Invalid JSON recovery ==="

  setup_test_project

  # Step 1: Create broken settings.json
  mkdir -p "$TEST_DIR/.claude"
  echo '{broken' > "$TEST_DIR/.claude/settings.json"

  # Step 2: Run setup — should recover and generate valid settings.json
  (cd "$TEST_DIR" && REPO_ROOT="$TEST_DIR" SCRIPT_DIR="$TEST_DIR/.claude/skills/workflow" \
    bash "$TEST_DIR/.claude/skills/workflow/setup" >/dev/null 2>&1)

  local settings="$TEST_DIR/.claude/settings.json"
  local is_valid="false"
  if [ -f "$settings" ] && jq empty "$settings" 2>/dev/null; then
    is_valid="true"
  fi
  assert_eq "R2-001: broken settings.json recovered to valid JSON" "true" "$is_valid"

  # Step 3: Test empty file recovery
  : > "$settings"

  (cd "$TEST_DIR" && REPO_ROOT="$TEST_DIR" SCRIPT_DIR="$TEST_DIR/.claude/skills/workflow" \
    bash "$TEST_DIR/.claude/skills/workflow/setup" >/dev/null 2>&1)

  local is_valid2="false"
  if [ -s "$settings" ] && jq empty "$settings" 2>/dev/null; then
    is_valid2="true"
  fi
  assert_eq "R2-001: empty settings.json recovered to valid JSON" "true" "$is_valid2"
}

# ============================================================================
# PRH-001 [unit]: No hardcoded hook filenames in setup for PreToolUse/PostToolUse
# install_hooks() and register_hooks() must not contain hardcoded hook filenames
# for PreToolUse/PostToolUse hooks. Exception: workflow-advance.sh, statusline.sh.
# ============================================================================

test_prh001_no_hardcoded_hook_filenames() {
  echo ""
  echo "=== PRH-001: No hardcoded hook filenames in setup ==="

  local setup_file="$REPO_DIR/setup"

  # Hook filenames that should NOT be hardcoded (PreToolUse/PostToolUse hooks)
  local -a prohibited_hooks=(workflow-gate.sh audit-trail.sh token-tracking.sh sensitive-file-guard.sh auto-format.sh)

  # Grep the entire setup file for prohibited hook filenames in non-comment code lines.
  # This avoids the fragile sed function-body extraction that stops at inner braces.
  # Exclude: comment lines, the INV-007 exemptions (workflow-advance, statusline)
  # Strip full-line comments and inline comments (after #) to avoid false positives
  local setup_code
  setup_code="$(grep -v '^[[:space:]]*#' "$setup_file" | sed 's/#[^"]*$//')"

  local register_hardcoded="false"
  for hookname in "${prohibited_hooks[@]}"; do
    if echo "$setup_code" | grep -qF "$hookname"; then
      echo "    setup contains hardcoded: $hookname"
      register_hardcoded="true"
    fi
  done
  assert_eq "PRH-001: setup has no hardcoded PreToolUse/PostToolUse hook filenames" "false" "$register_hardcoded"

  # Verify the exempted files (workflow-advance.sh, statusline.sh) ARE still present
  # (they should remain hardcoded per INV-007)
  local has_advance has_statusline
  has_advance="$(echo "$setup_code" | grep -c "workflow-advance" || echo "0")"
  has_statusline="$(echo "$setup_code" | grep -c "statusline" || echo "0")"
  assert_match "PRH-001: workflow-advance.sh remains in setup (exempt)" "^[1-9]" "$has_advance"
  assert_match "PRH-001: statusline.sh remains in setup (exempt)" "^[1-9]" "$has_statusline"
}

# ============================================================================
# PRH-002 [unit]: No test suites missing from CI
# Same completeness check as INV-001 — disk to config to CI.
# ============================================================================

test_prh002_no_missing_test_suites() {
  echo ""
  echo "=== PRH-002: No test suites missing from CI ==="

  local ci_file="$REPO_DIR/.github/workflows/ci.yml"
  local config_file="$REPO_DIR/.correctless/config/workflow-config.json"

  # Collect all test files on disk (skip test-helpers.sh — shared harness, not a standalone test)
  local -a disk_tests=()
  while IFS= read -r f; do
    local _bn; _bn="$(basename "$f")"
    [ "$_bn" = "test-helpers.sh" ] && continue
    disk_tests+=("$_bn")
  done < <(find "$REPO_DIR/tests" -maxdepth 1 -name 'test*.sh' -type f | sort)

  # Parse commands.test from config
  local test_cmd
  test_cmd="$(jq -r '.commands.test' "$config_file")"

  # Also include test_new if non-empty (should be folded into test after this feature)
  local test_new
  test_new="$(jq -r '.commands.test_new // ""' "$config_file")"
  local all_tests="$test_cmd"
  if [ -n "$test_new" ]; then
    all_tests="$test_cmd && $test_new"
  fi

  # Parse CI run test lines
  local ci_content
  ci_content="$(cat "$ci_file")"

  # DA-002: commands.test may use glob-based discovery (test-*.sh).
  # If the command uses a glob pattern, all disk test files are automatically
  # discovered — the disk→config completeness check passes trivially.
  local config_uses_glob=false
  if echo "$all_tests" | grep -qE 'test-\*\.sh'; then
    config_uses_glob=true
  fi

  # Check disk → config completeness
  local disk_to_config_complete="true"
  if [ "$config_uses_glob" = true ]; then
    disk_to_config_complete="true"  # glob discovers all test-*.sh files
  else
    for t in "${disk_tests[@]}"; do
      if ! echo "$all_tests" | grep -qF "tests/$t"; then
        echo "    PRH-002 disk→config gap: $t"
        disk_to_config_complete="false"
      fi
    done
  fi
  assert_eq "PRH-002: all disk test files in config" "true" "$disk_to_config_complete"

  # Check config → CI completeness
  # DA-002: If CI also uses glob, the check passes trivially.
  local ci_uses_glob=false
  if echo "$ci_content" | grep -qE 'test-\*\.sh'; then
    ci_uses_glob=true
  fi

  local config_to_ci_complete="true"
  if [ "$config_uses_glob" = true ] && [ "$ci_uses_glob" = true ]; then
    config_to_ci_complete="true"  # both use globs — inherently in sync
  elif [ "$config_uses_glob" = false ]; then
    local -a config_entries=()
    while IFS= read -r entry; do
      config_entries+=("$entry")
    done < <(echo "$all_tests" | grep -oE 'tests/test[^ ]*\.sh')

    for ct in "${config_entries[@]}"; do
      if ! echo "$ci_content" | grep -qF "$ct"; then
        echo "    PRH-002 config→CI gap: $ct"
        config_to_ci_complete="false"
      fi
    done
  fi
  assert_eq "PRH-002: all config test files in CI" "true" "$config_to_ci_complete"
}

# ============================================================================
# Run all tests
# ============================================================================

test_inv001_ci_runs_all_test_suites
test_inv002_hook_metadata_headers
test_inv003_install_hooks_auto_discovers
test_inv004_register_hooks_reads_metadata
test_inv005_auto_format_in_hooks
test_inv006_non_hook_files_excluded
test_inv007_hardcoded_entries_preserved
test_inv008_shellcheck_scans_scripts
test_inv009_existing_behavior_preserved
test_qa_existing_settings_update
test_invalid_json_recovery
test_prh001_no_hardcoded_hook_filenames
test_prh002_no_missing_test_suites

# ============================================================================
# Summary
# ============================================================================

echo ""
echo "============================================"
echo "Results: $PASS passed, $FAIL failed"
echo "============================================"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
