#!/usr/bin/env bash
# Correctless — DA-002 Debt Sprint: Workflow-Advance Decomposition Tests
#
# Tests for the decomposition of hooks/workflow-advance.sh into a thin
# dispatcher + 3 sourced modules in scripts/wf/.
#
# Covers INV-001 through INV-017, PRH-001 through PRH-003.

source "$(dirname "${BASH_SOURCE[0]}")/test-helpers.sh"

DISPATCHER="$REPO_DIR/hooks/workflow-advance.sh"
WF_DIR="$REPO_DIR/scripts/wf"
TRANSITIONS="$WF_DIR/transitions.sh"
UTILITY="$WF_DIR/utility.sh"
METADATA="$WF_DIR/metadata.sh"
WORKFLOW_CONFIG="$REPO_DIR/.correctless/config/workflow-config.json"
CI_YML="$REPO_DIR/.github/workflows/ci.yml"
SETUP_SCRIPT="$REPO_DIR/setup"
SYNC_SCRIPT="$REPO_DIR/sync.sh"
SFG_HOOK="$REPO_DIR/hooks/sensitive-file-guard.sh"
CSPEC_SKILL="$REPO_DIR/skills/cspec/SKILL.md"
DRIFT_DEBT="$REPO_DIR/.correctless/meta/drift-debt.json"

# ============================================================================
# INV-002: Module sourcing structure
# ============================================================================

section "INV-002" "Module sourcing structure"

# INV-002(1): scripts/wf/ directory exists
if [ -d "$WF_DIR" ]; then
  pass "INV-002(1)" "scripts/wf/ directory exists"
else
  fail "INV-002(1)" "scripts/wf/ directory does not exist"
fi

# INV-002(2): All three module files exist
for mod in transitions.sh utility.sh metadata.sh; do
  if [ -f "$WF_DIR/$mod" ]; then
    pass "INV-002(2a)" "Module file $mod exists"
  else
    fail "INV-002(2a)" "Module file $mod does not exist"
  fi
done

# INV-002(3): Dispatcher sources all three modules
# The dispatcher uses a for loop that iterates over module names and sources them.
# Check: either explicit source lines per module, or a for loop over the module list.
if grep -qE 'for.*transitions\.sh.*utility\.sh.*metadata\.sh|source.*\$_WF_MODULE_DIR/\$_module|source.*wf/' "$DISPATCHER"; then
  pass "INV-002(3)" "Dispatcher sources modules (via loop or explicit)"
else
  fail "INV-002(3)" "Dispatcher does not source modules"
fi
# Also verify the loop includes all three module names
for mod in transitions.sh utility.sh metadata.sh; do
  if grep -q "$mod" "$DISPATCHER"; then
    pass "INV-002(3)" "Dispatcher references $mod"
  else
    fail "INV-002(3)" "Dispatcher does not reference $mod"
  fi
done

# INV-002(4): Dispatcher contains no cmd_* function bodies (only calls)
# A function body looks like: cmd_xxx() { ... } (multi-line)
# We check: if cmd_xxx() appears, the next non-blank line should NOT be function body code
cmd_body_count=0
while IFS= read -r line; do
  if [[ "$line" =~ ^cmd_[a-z_]+\(\) ]]; then
    cmd_body_count=$((cmd_body_count + 1))
  fi
done < "$DISPATCHER"

if [ "$cmd_body_count" -eq 0 ]; then
  pass "INV-002(4)" "Dispatcher has no cmd_* function bodies"
else
  fail "INV-002(4)" "Dispatcher has $cmd_body_count cmd_* function definitions (should be 0)"
fi

# ============================================================================
# INV-003: Module grouping
# ============================================================================

section "INV-003" "Module grouping"

# INV-003(1): transitions.sh contains phase transition command functions
TRANSITION_CMDS="cmd_review cmd_model cmd_review_spec cmd_tests cmd_impl cmd_qa cmd_fix cmd_verify cmd_audit_mini cmd_done cmd_verified cmd_documented cmd_audit_start cmd_audit_done"
for cmd in $TRANSITION_CMDS; do
  if [ -f "$TRANSITIONS" ] && grep -q "${cmd}()" "$TRANSITIONS"; then
    pass "INV-003(1)" "$cmd is in transitions.sh"
  else
    fail "INV-003(1)" "$cmd is NOT in transitions.sh"
  fi
done

# INV-003(2): utility.sh contains operational command functions
UTILITY_CMDS="cmd_init cmd_reset cmd_override cmd_status cmd_status_all cmd_diagnose"
for cmd in $UTILITY_CMDS; do
  if [ -f "$UTILITY" ] && grep -q "${cmd}()" "$UTILITY"; then
    pass "INV-003(2)" "$cmd is in utility.sh"
  else
    fail "INV-003(2)" "$cmd is NOT in utility.sh"
  fi
done

# INV-003(3): metadata.sh contains state modification command functions
METADATA_CMDS="cmd_set_intensity cmd_resolve_drift cmd_spec_update"
for cmd in $METADATA_CMDS; do
  if [ -f "$METADATA" ] && grep -q "${cmd}()" "$METADATA"; then
    pass "INV-003(3)" "$cmd is in metadata.sh"
  else
    fail "INV-003(3)" "$cmd is NOT in metadata.sh"
  fi
done

# INV-003(4): No function in the wrong module
# transitions.sh should NOT contain utility or metadata commands
for cmd in $UTILITY_CMDS $METADATA_CMDS; do
  if [ -f "$TRANSITIONS" ] && grep -q "${cmd}()" "$TRANSITIONS"; then
    fail "INV-003(4)" "$cmd incorrectly appears in transitions.sh"
  else
    pass "INV-003(4)" "$cmd correctly absent from transitions.sh"
  fi
done

# utility.sh should NOT contain transitions or metadata commands
for cmd in $TRANSITION_CMDS $METADATA_CMDS; do
  if [ -f "$UTILITY" ] && grep -q "${cmd}()" "$UTILITY"; then
    fail "INV-003(4)" "$cmd incorrectly appears in utility.sh"
  else
    pass "INV-003(4)" "$cmd correctly absent from utility.sh"
  fi
done

# metadata.sh should NOT contain transitions or utility commands
for cmd in $TRANSITION_CMDS $UTILITY_CMDS; do
  if [ -f "$METADATA" ] && grep -q "${cmd}()" "$METADATA"; then
    fail "INV-003(4)" "$cmd incorrectly appears in metadata.sh"
  else
    pass "INV-003(4)" "$cmd correctly absent from metadata.sh"
  fi
done

# ============================================================================
# INV-004: Shared helpers remain in dispatcher
# ============================================================================

section "INV-004" "Shared helpers remain in dispatcher"

SHARED_HELPERS="die info require_jq state_file read_state read_phase write_state update_phase now_iso _read_spec_hash current_branch check_branch_match require_phase require_phase_oneof read_config_field is_full_mode is_monorepo read_package_config detect_affected_packages is_fail_closed has_formal_model tests_fail_not_build_error tests_pass test_files_exist spec_file_exists _require_min_qa_rounds _log_audit_done_override"

for helper in $SHARED_HELPERS; do
  # Helper should NOT be defined in any module file
  for mod in "$TRANSITIONS" "$UTILITY" "$METADATA"; do
    mod_name="$(basename "$mod" 2>/dev/null || echo "$mod")"
    if [ -f "$mod" ] && grep -qE "^${helper}\(\)|^function ${helper}" "$mod"; then
      fail "INV-004(1)" "Helper $helper is defined in module $mod_name (should be in dispatcher or lib.sh)"
    else
      pass "INV-004(1)" "Helper $helper correctly absent from $mod_name"
    fi
  done
done

# ============================================================================
# INV-011: SCRIPT_DIR for path resolution in modules
# ============================================================================

section "INV-011" "SCRIPT_DIR for path resolution in modules"

# INV-011(1): Dispatcher sets SCRIPT_DIR before sourcing modules
# Look for SCRIPT_DIR= appearing before any source statement for modules
if grep -qE '^SCRIPT_DIR=' "$DISPATCHER"; then
  pass "INV-011(1)" "Dispatcher sets SCRIPT_DIR"
else
  fail "INV-011(1)" "Dispatcher does not set SCRIPT_DIR"
fi

# INV-011(2): SCRIPT_DIR is set using BASH_SOURCE[0] of the dispatcher
if grep -qE 'SCRIPT_DIR=.*dirname.*BASH_SOURCE\[0\]' "$DISPATCHER"; then
  pass "INV-011(2)" "SCRIPT_DIR uses BASH_SOURCE[0] of dispatcher"
else
  fail "INV-011(2)" "SCRIPT_DIR does not use BASH_SOURCE[0] of dispatcher"
fi

# INV-011(3): No module file uses BASH_SOURCE[0] for path resolution in code
# Only check non-comment lines (lines not starting with #)
for mod in "$TRANSITIONS" "$UTILITY" "$METADATA"; do
  mod_name="$(basename "$mod" 2>/dev/null || echo "$mod")"
  if [ -f "$mod" ] && grep -v '^\s*#' "$mod" | grep -qE 'BASH_SOURCE\[0\]|\$\{BASH_SOURCE\[0\]\}'; then
    fail "INV-011(3)" "Module $mod_name uses BASH_SOURCE[0] in code (should use \$SCRIPT_DIR)"
  else
    pass "INV-011(3)" "Module $mod_name does not use BASH_SOURCE[0] in code"
  fi
done

# ============================================================================
# INV-012: Graceful error on missing module files
# ============================================================================

section "INV-012" "Graceful error on missing module files"

# INV-012(1): Dispatcher checks module existence before sourcing
# The dispatcher uses a for loop with a generic file existence check for each module.
# Check for the pattern: [ -f "..." ] || die "Module not found..."
if grep -qE '\[ -f.*\|\|.*die.*Module not found|Module not found.*run setup' "$DISPATCHER"; then
  pass "INV-012(1)" "Dispatcher checks module existence before sourcing"
else
  fail "INV-012(1)" "Dispatcher does not check module existence before sourcing"
fi

# INV-012(2): Error message suggests running setup
if grep -q "run setup to install\|run setup\|run .*/setup" "$DISPATCHER"; then
  pass "INV-012(2)" "Missing module error suggests running setup"
else
  fail "INV-012(2)" "Missing module error does not suggest running setup"
fi

# ============================================================================
# INV-001: CLI contract unchanged (integration test)
# ============================================================================

section "INV-001" "CLI contract unchanged"

# Set up a test project to exercise the dispatcher
TEST_DIR_001="/tmp/correctless-decomp-test-$$"
cleanup_001() { rm -rf "$TEST_DIR_001"; }
trap cleanup_001 EXIT

mkdir -p "$TEST_DIR_001"
cd "$TEST_DIR_001" || { fail "INV-001(0)" "Cannot create test dir"; }
git init -q
git branch -M main
echo '{}' > package.json
git add -A && git commit -q -m "init"

# Install correctless
mkdir -p .claude/skills/workflow
rsync -a --exclude='.git' --exclude='tests' "$REPO_DIR/" .claude/skills/workflow/
.claude/skills/workflow/setup >/dev/null 2>&1

# Create a feature branch and init workflow
git checkout -q -b feature/test-decomp
.correctless/hooks/workflow-advance.sh init "test-decomp" >/dev/null 2>&1

# INV-001(1): All commands from the dispatch table exist and respond
# Commands that need args get dummy args to avoid usage errors from the function itself
DISPATCH_COMMANDS_NOARG="review model review-spec tests impl qa fix verify-phase audit-mini done verified documented audit-done reset status status-all"
DISPATCH_COMMANDS_ARG="init:test-task spec-update:reason set-intensity:high resolve-drift:DRIFT-001:reason override:reason diagnose:file.sh audit-start:qa"

for cmd in $DISPATCH_COMMANDS_NOARG; do
  output="$(.correctless/hooks/workflow-advance.sh "$cmd" 2>&1)" || true
  # The catch-all prints "Usage: workflow-advance.sh <command>" — distinguish from cmd-specific errors
  if echo "$output" | grep -q "^Usage: workflow-advance.sh"; then
    fail "INV-001(1)" "Command '$cmd' is not recognized (hit catch-all)"
  else
    pass "INV-001(1)" "Command '$cmd' is recognized by dispatcher"
  fi
done

for entry in $DISPATCH_COMMANDS_ARG; do
  cmd="${entry%%:*}"
  args="${entry#*:}"
  # Split args on : for multi-arg commands
  arg_array=()
  IFS=: read -ra arg_array <<< "$args"
  output="$(.correctless/hooks/workflow-advance.sh "$cmd" "${arg_array[@]}" 2>&1)" || true
  if echo "$output" | grep -q "^Usage: workflow-advance.sh"; then
    fail "INV-001(1)" "Command '$cmd' is not recognized (hit catch-all)"
  else
    pass "INV-001(1)" "Command '$cmd' is recognized by dispatcher"
  fi
done

# INV-001(2): Unknown command hits catch-all with usage text and exit 1
output="$(.correctless/hooks/workflow-advance.sh nonexistent-cmd 2>&1)" && exit_code=0 || exit_code=$?
if [ "$exit_code" -eq 1 ] && echo "$output" | grep -q "Usage:"; then
  pass "INV-001(2)" "Unknown command exits 1 with usage text"
else
  fail "INV-001(2)" "Unknown command exit=$exit_code (expected 1 with Usage text)"
fi

# INV-001(3): help (no args) hits catch-all
output="$(.correctless/hooks/workflow-advance.sh 2>&1)" && exit_code=0 || exit_code=$?
if [ "$exit_code" -eq 1 ] && echo "$output" | grep -q "Usage:"; then
  pass "INV-001(3)" "No args exits 1 with usage text"
else
  fail "INV-001(3)" "No args exit=$exit_code (expected 1 with Usage text)"
fi

# INV-001(4): status produces expected output format
status_out="$(.correctless/hooks/workflow-advance.sh status 2>&1)"
if echo "$status_out" | grep -q "Phase:\|Branch:\|=== Workflow Status ==="; then
  pass "INV-001(4)" "status command produces expected output"
else
  fail "INV-001(4)" "status command does not produce expected output"
fi

cd "$REPO_DIR" || exit

# ============================================================================
# INV-005: Glob-based test discovery
# ============================================================================

section "INV-005" "Glob-based test discovery"

# INV-005(1): commands.test uses glob pattern
test_cmd="$(jq -r '.commands.test' "$WORKFLOW_CONFIG")"
if echo "$test_cmd" | grep -q 'tests/test-\*\.sh'; then
  pass "INV-005(1)" "commands.test uses glob pattern tests/test-*.sh"
else
  fail "INV-005(1)" "commands.test does not use glob pattern tests/test-*.sh"
fi

# INV-005(2): commands.test does NOT contain hardcoded test filenames
# Check for literal test-*.sh filenames (not the glob).
# Exclude test-helpers.sh — it appears in the exclusion pattern, not as a test to run.
hardcoded_count=0
while IFS= read -r test_file; do
  basename_file="$(basename "$test_file")"
  # test-helpers.sh is excluded by the glob command (not a test runner) — skip it
  [ "$basename_file" = "test-helpers.sh" ] && continue
  if echo "$test_cmd" | grep -qF "$basename_file"; then
    hardcoded_count=$((hardcoded_count + 1))
  fi
done < <(find "$REPO_DIR/tests" -name 'test-*.sh' -type f 2>/dev/null)

if [ "$hardcoded_count" -eq 0 ]; then
  pass "INV-005(2)" "commands.test has no hardcoded test filenames"
else
  fail "INV-005(2)" "commands.test has $hardcoded_count hardcoded test filenames"
fi

# INV-005(3): commands.test excludes test-helpers.sh
if echo "$test_cmd" | grep -q 'test-helpers\.sh.*continue\|test-helpers'; then
  pass "INV-005(3)" "commands.test excludes test-helpers.sh"
else
  fail "INV-005(3)" "commands.test does not exclude test-helpers.sh"
fi

# INV-005(4): commands.test fails on any test failure (exit non-zero)
if echo "$test_cmd" | grep -qE '\|\| exit 1|\|\| exit|\&\&|set -e'; then
  pass "INV-005(4)" "commands.test fails on test failure"
else
  fail "INV-005(4)" "commands.test may not fail on individual test failure"
fi

# ============================================================================
# INV-006: New test files auto-discovered (integration)
# ============================================================================

section "INV-006" "New test files auto-discovered"

# Create a temporary test file and verify the glob would find it
TEMP_TEST="$REPO_DIR/tests/test-da002-temp-discovery-$$.sh"
cat > "$TEMP_TEST" << 'DISCOVERYEOF'
#!/usr/bin/env bash
echo "DISCOVERY_MARKER_DA002"
exit 0
DISCOVERYEOF
chmod +x "$TEMP_TEST"

# Run the glob pattern from commands.test and check if our file is included
glob_output=""
for f in "$REPO_DIR"/tests/test-*.sh; do
  [[ "$f" == */test-helpers.sh ]] && continue
  glob_output="$glob_output $f"
done

if echo "$glob_output" | grep -q "test-da002-temp-discovery-$$"; then
  pass "INV-006(1)" "New test file auto-discovered by glob"
else
  fail "INV-006(1)" "New test file NOT discovered by glob"
fi

rm -f "$TEMP_TEST"

# ============================================================================
# INV-007: Drift debt cadence check in /cspec
# ============================================================================

section "INV-007" "Drift debt cadence check in /cspec"

# INV-007(1): cspec SKILL.md mentions drift-debt check during Step 0 or before brainstorm
if grep -q 'drift.debt' "$CSPEC_SKILL"; then
  pass "INV-007(1a)" "cspec SKILL.md references drift-debt"
else
  fail "INV-007(1a)" "cspec SKILL.md does not reference drift-debt"
fi

# INV-007(2): The check is advisory (does not block spec creation)
if grep -qi 'advisory\|does not block\|non.blocking\|warning' "$CSPEC_SKILL" && grep -q 'drift.debt' "$CSPEC_SKILL"; then
  pass "INV-007(2)" "drift-debt check is advisory"
else
  fail "INV-007(2)" "drift-debt check may not be advisory"
fi

# INV-007(3): Check mentions the threshold (2 or more open items)
if grep -qE '2.*open|two.*open|>= *2|>=2|open.*2' "$CSPEC_SKILL"; then
  pass "INV-007(3)" "cspec mentions 2+ open items threshold"
else
  fail "INV-007(3)" "cspec does not mention 2+ open items threshold for drift-debt"
fi

# ============================================================================
# INV-008: Drift debt items resolved
# ============================================================================

section "INV-008" "Drift debt items resolved"

# INV-008(1): drift-debt.json exists (force-added to git despite meta/ gitignore)
if [ -f "$DRIFT_DEBT" ]; then
  pass "INV-008(1)" "drift-debt.json exists"
else
  fail "INV-008(1)" "drift-debt.json does not exist"
fi

# INV-008(2): Zero open items in drift-debt.json
if [ -f "$DRIFT_DEBT" ]; then
  open_count="$(jq '[.drift_debt[] | select(.status == "open")] | length' "$DRIFT_DEBT" 2>/dev/null)" || open_count="unknown"
  if [ "$open_count" = "0" ]; then
    pass "INV-008(2)" "Zero open drift debt items"
  else
    fail "INV-008(2)" "Found $open_count open drift debt items (expected 0)"
  fi
else
  fail "INV-008(2)" "Cannot check — drift-debt.json missing"
fi

# INV-008(3): DRIFT-001, DRIFT-003, DRIFT-004, DRIFT-008 are each resolved or wont-fix
for drift_id in DRIFT-001 DRIFT-003 DRIFT-004 DRIFT-008; do
  if [ -f "$DRIFT_DEBT" ]; then
    status="$(jq -r --arg id "$drift_id" '.drift_debt[] | select(.id == $id) | .status' "$DRIFT_DEBT" 2>/dev/null)"
    if [ "$status" = "resolved" ] || [ "$status" = "wont-fix" ]; then
      pass "INV-008(3)" "$drift_id has status '$status'"
    else
      fail "INV-008(3)" "$drift_id has status '$status' (expected resolved or wont-fix)"
    fi
  else
    fail "INV-008(3)" "Cannot check $drift_id — drift-debt.json missing"
  fi
done

# ============================================================================
# INV-010: CI test command updated
# ============================================================================

section "INV-010" "CI test command updated"

# INV-010(1): CI workflow uses glob-based test command
if grep -qE 'tests/test-\*\.sh|test-\*\.sh' "$CI_YML" || grep -q 'workflow-config' "$CI_YML"; then
  pass "INV-010(1)" "CI uses glob-based or config-referenced test command"
else
  fail "INV-010(1)" "CI does not use glob-based test command"
fi

# INV-010(2): CI does NOT contain hardcoded test filenames
# Count lines that reference specific test files (bash tests/test-*.sh)
hardcoded_ci_lines="$(grep -cE 'bash tests/test-[a-z]' "$CI_YML" 2>/dev/null)" || hardcoded_ci_lines=0
if [ "$hardcoded_ci_lines" -eq 0 ]; then
  pass "INV-010(2)" "CI has no hardcoded test filenames"
else
  fail "INV-010(2)" "CI has $hardcoded_ci_lines hardcoded test file references"
fi

# ============================================================================
# INV-013: Rename test.sh to test-core.sh
# ============================================================================

section "INV-013" "Rename test.sh to test-core.sh"

# INV-013(1): tests/test.sh should NOT exist
if [ -f "$REPO_DIR/tests/test.sh" ]; then
  fail "INV-013(1)" "tests/test.sh still exists (should be renamed to test-core.sh)"
else
  pass "INV-013(1)" "tests/test.sh does not exist"
fi

# INV-013(2): tests/test-core.sh SHOULD exist
if [ -f "$REPO_DIR/tests/test-core.sh" ]; then
  pass "INV-013(2)" "tests/test-core.sh exists"
else
  fail "INV-013(2)" "tests/test-core.sh does not exist"
fi

# INV-013(3): test-core.sh has NO inline invocations of other test files
if [ -f "$REPO_DIR/tests/test-core.sh" ]; then
  inline_invocations="$(grep -cE 'bash tests/test-|bash \$.*tests/test-|\./tests/test-' "$REPO_DIR/tests/test-core.sh" 2>/dev/null)" || inline_invocations=0
  if [ "$inline_invocations" -eq 0 ]; then
    pass "INV-013(3)" "test-core.sh has no inline invocations of other test files"
  else
    fail "INV-013(3)" "test-core.sh has $inline_invocations inline invocations of other test files"
  fi
else
  fail "INV-013(3)" "Cannot check — test-core.sh does not exist"
fi

# ============================================================================
# INV-014: Setup installs scripts/wf/ subdirectory
# ============================================================================

section "INV-014" "Setup installs scripts/wf/ subdirectory"

# INV-014(1): Setup script handles scripts/wf/ files
if grep -qE 'scripts/wf/|wf/' "$SETUP_SCRIPT"; then
  pass "INV-014(1)" "Setup script references scripts/wf/"
else
  fail "INV-014(1)" "Setup script does not reference scripts/wf/"
fi

# INV-014(2): Integration test — run setup and check wf/ installed
cd "$TEST_DIR_001" || { fail "INV-014(2)" "Cannot cd to test dir"; }

# Re-install with latest setup
rsync -a --exclude='.git' --exclude='tests' "$REPO_DIR/" .claude/skills/workflow/
.claude/skills/workflow/setup >/dev/null 2>&1

if [ -d ".correctless/scripts/wf" ]; then
  pass "INV-014(2)" "Setup creates .correctless/scripts/wf/ directory"
else
  fail "INV-014(2)" "Setup does not create .correctless/scripts/wf/ directory"
fi

# INV-014(3): Module files are installed
for mod in transitions.sh utility.sh metadata.sh; do
  if [ -f ".correctless/scripts/wf/$mod" ]; then
    pass "INV-014(3)" "$mod installed to .correctless/scripts/wf/"
  else
    fail "INV-014(3)" "$mod NOT installed to .correctless/scripts/wf/"
  fi
done

# INV-014(4): Install manifest includes wf/ files
if [ -f ".correctless/.install-manifest.json" ]; then
  if jq -e '.files | keys[] | select(startswith("scripts/wf/"))' ".correctless/.install-manifest.json" >/dev/null 2>&1; then
    pass "INV-014(4)" "Install manifest includes scripts/wf/ entries"
  else
    fail "INV-014(4)" "Install manifest does NOT include scripts/wf/ entries"
  fi
else
  fail "INV-014(4)" "Install manifest does not exist"
fi

cd "$REPO_DIR" || exit

# ============================================================================
# INV-015: sync.sh propagates scripts/wf/ subdirectory
# ============================================================================

section "INV-015" "sync.sh propagates scripts/wf/ subdirectory"

# INV-015(1): sync.sh handles scripts/wf/ subdirectory
if grep -qE 'scripts/wf/|wf/' "$SYNC_SCRIPT"; then
  pass "INV-015(1)" "sync.sh references scripts/wf/"
else
  fail "INV-015(1)" "sync.sh does not reference scripts/wf/"
fi

# INV-015(2): Distribution target has scripts/wf/ after sync
if [ -d "$REPO_DIR/correctless/scripts/wf" ]; then
  pass "INV-015(2)" "correctless/scripts/wf/ exists in distribution"
else
  fail "INV-015(2)" "correctless/scripts/wf/ does not exist in distribution"
fi

# INV-015(3): Distribution copies match source
for mod in transitions.sh utility.sh metadata.sh; do
  if [ -f "$REPO_DIR/correctless/scripts/wf/$mod" ]; then
    if diff -q "$WF_DIR/$mod" "$REPO_DIR/correctless/scripts/wf/$mod" >/dev/null 2>&1; then
      pass "INV-015(3)" "correctless/scripts/wf/$mod matches source"
    else
      fail "INV-015(3)" "correctless/scripts/wf/$mod differs from source"
    fi
  else
    fail "INV-015(3)" "correctless/scripts/wf/$mod not found in distribution"
  fi
done

# ============================================================================
# INV-016: Module files protected by sensitive-file-guard
# ============================================================================

section "INV-016" "Module files protected by sensitive-file-guard"

# INV-016(1): SFG DEFAULTS include scripts/wf/ pattern
if grep -q 'scripts/wf/' "$SFG_HOOK"; then
  pass "INV-016(1)" "SFG DEFAULTS include scripts/wf/ pattern"
else
  fail "INV-016(1)" "SFG DEFAULTS do not include scripts/wf/ pattern"
fi

# INV-016(2): The pattern covers .sh files in the wf/ directory
if grep -qE 'scripts/wf/\*\.sh|scripts/wf/' "$SFG_HOOK"; then
  pass "INV-016(2)" "SFG pattern covers scripts/wf/*.sh files"
else
  fail "INV-016(2)" "SFG pattern does not cover scripts/wf/*.sh files"
fi

# ============================================================================
# INV-017: Glob command echoes filename before execution
# ============================================================================

section "INV-017" "Glob command echoes filename before execution"

# INV-017(1): commands.test contains echo before bash invocation
test_cmd_017="$(jq -r '.commands.test' "$WORKFLOW_CONFIG")"
if echo "$test_cmd_017" | grep -qE 'echo.*\$f|echo.*>>>'; then
  pass "INV-017(1)" "Glob command echoes filename before execution"
else
  fail "INV-017(1)" "Glob command does not echo filename before execution"
fi

# ============================================================================
# PRH-001: No CLI interface changes
# ============================================================================

section "PRH-001" "No CLI interface changes"

# PRH-001(1): Dispatch table has all expected commands
EXPECTED_DISPATCH="init start review model review-spec tests impl qa fix verify-phase audit-mini done verified documented audit-start audit-done spec-update set-intensity resolve-drift reset override diagnose status status-all"
for cmd in $EXPECTED_DISPATCH; do
  # Handle both forms: "cmd)" and "cmd|other)" or "other|cmd)"
  if grep -qE "^\s*${cmd}\)" "$DISPATCHER" \
    || grep -qE "^\s*${cmd}\|" "$DISPATCHER" \
    || grep -qE "\|${cmd}\)" "$DISPATCHER"; then
    pass "PRH-001(1)" "Dispatch table includes '$cmd'"
  else
    fail "PRH-001(1)" "Dispatch table missing '$cmd'"
  fi
done

# PRH-001(2): Catch-all (*) exists with exit 1
if grep -qE '^\s*\*\)' "$DISPATCHER" && grep -q 'exit 1' "$DISPATCHER"; then
  pass "PRH-001(2)" "Catch-all exists with exit 1"
else
  fail "PRH-001(2)" "Catch-all or exit 1 missing"
fi

# ============================================================================
# PRH-002: No function duplication across modules
# ============================================================================

section "PRH-002" "No function duplication across modules"

# PRH-002(1): No function name appears in more than one module
if [ -f "$TRANSITIONS" ] && [ -f "$UTILITY" ] && [ -f "$METADATA" ]; then
  # Extract all function names from each module
  trans_funcs="$(grep -oE '^[a-zA-Z_][a-zA-Z_0-9]*\(\)' "$TRANSITIONS" 2>/dev/null | sort)"
  util_funcs="$(grep -oE '^[a-zA-Z_][a-zA-Z_0-9]*\(\)' "$UTILITY" 2>/dev/null | sort)"
  meta_funcs="$(grep -oE '^[a-zA-Z_][a-zA-Z_0-9]*\(\)' "$METADATA" 2>/dev/null | sort)"

  # Check for duplicates across modules
  all_funcs="$(printf '%s\n%s\n%s' "$trans_funcs" "$util_funcs" "$meta_funcs" | sort)"
  unique_funcs="$(printf '%s\n%s\n%s' "$trans_funcs" "$util_funcs" "$meta_funcs" | sort -u)"
  dup_count="$(diff <(echo "$all_funcs") <(echo "$unique_funcs") | grep -c '^<' 2>/dev/null)" || dup_count=0

  if [ "$dup_count" -eq 0 ]; then
    pass "PRH-002(1)" "No function duplicated across modules"
  else
    fail "PRH-002(1)" "$dup_count function(s) duplicated across modules"
  fi
else
  fail "PRH-002(1)" "Cannot check — module files do not exist"
fi

# ============================================================================
# PRH-003: No hardcoded test filenames in test command
# ============================================================================

section "PRH-003" "No hardcoded test filenames in test command"

# PRH-003(1): commands.test does not contain any literal test-*.sh filename
test_cmd_prh="$(jq -r '.commands.test' "$WORKFLOW_CONFIG")"

# Extract all test file basenames and check none appear literally in the command
prh003_violations=0
while IFS= read -r test_file; do
  bn="$(basename "$test_file")"
  # Skip the glob pattern itself and test-helpers.sh (appears in exclusion, not as test)
  [ "$bn" = "test-*.sh" ] && continue
  [ "$bn" = "test-helpers.sh" ] && continue
  if echo "$test_cmd_prh" | grep -qF "$bn"; then
    prh003_violations=$((prh003_violations + 1))
  fi
done < <(find "$REPO_DIR/tests" -name 'test-*.sh' -type f 2>/dev/null)

if [ "$prh003_violations" -eq 0 ]; then
  pass "PRH-003(1)" "No hardcoded test filenames in commands.test"
else
  fail "PRH-003(1)" "$prh003_violations hardcoded test filenames found in commands.test"
fi

# ============================================================================
# INV-014 supplement: check_install_freshness covers scripts/wf/
# ============================================================================

section "INV-014-sup" "check_install_freshness covers scripts/wf/"

# The freshness check in lib.sh scans manifest entries which the setup script
# now includes scripts/wf/ files in. The setup manifest scan dir list includes
# scripts/wf. Check that the setup manifest scan covers scripts/wf.
if grep -qE 'scripts/wf' "$SETUP_SCRIPT"; then
  pass "INV-014-sup(1)" "Setup manifest scan covers scripts/wf/"
else
  fail "INV-014-sup(1)" "Setup manifest scan may not cover scripts/wf/"
fi

# ============================================================================
# Summary
# ============================================================================

summary "DA-002 Workflow Advance Decomposition"
