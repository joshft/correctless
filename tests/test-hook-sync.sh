#!/usr/bin/env bash
# shellcheck disable=SC1090  # Dynamic source path (LIB_SH) always resolves to scripts/lib.sh
# Correctless — Hook Sync Enforcement Tests
# Tests all 10 rules from the hook-sync-enforcement spec:
#   INV-001 through INV-008, PRH-001, PRH-002
# RED phase: these tests MUST FAIL against stubs/current code.
# Run from repo root: bash tests/test-hook-sync.sh

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB_SH="$REPO_DIR/scripts/lib.sh"
PASS=0
FAIL=0

# ============================================================================
# Helpers (same pattern as test-lib.sh)
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
    echo "  FAIL: $desc (expected output to contain '$expected', got '$actual')"
    FAIL=$((FAIL + 1))
  fi
}

assert_not_contains() {
  local desc="$1" unexpected="$2" actual="$3"
  if echo "$actual" | grep -qF "$unexpected"; then
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

assert_exit_code() {
  local desc="$1" expected="$2" actual="$3"
  assert_eq "$desc" "$expected" "$actual"
}

# ============================================================================
# Test environment setup
# ============================================================================

TEST_DIR="/tmp/correctless-test-hook-sync-$$"

cleanup() {
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

echo "Correctless Hook Sync Enforcement Tests"
echo "========================================"

# ============================================================================
# INV-001 [integration]: sync.sh hook auto-discovery
# Adding a new .sh file to hooks/ and running sync.sh copies it to
# correctless/hooks/ without any code change to sync.sh.
# ============================================================================

test_inv001_hook_auto_discovery() {
  echo ""
  echo "=== INV-001: sync.sh hook auto-discovery ==="

  # Create a temporary hook file
  local temp_hook="hooks/_test-temp-hook-$$.sh"
  echo '#!/usr/bin/env bash' > "$REPO_DIR/$temp_hook"
  echo '# Temporary test hook for INV-001' >> "$REPO_DIR/$temp_hook"

  # Run sync.sh
  (cd "$REPO_DIR" && bash sync.sh 2>/dev/null)

  # Verify the file was copied to correctless/hooks/
  assert_file_exists \
    "INV-001: temp hook synced to correctless/hooks/" \
    "$REPO_DIR/correctless/hooks/_test-temp-hook-$$.sh"

  # Cleanup
  rm -f "$REPO_DIR/$temp_hook"
  rm -f "$REPO_DIR/correctless/hooks/_test-temp-hook-$$.sh"
}

# ============================================================================
# INV-002 [integration]: sync.sh script auto-discovery
# Adding a new .sh file to scripts/ and running sync.sh copies it to
# correctless/scripts/ without any code change to sync.sh.
# ============================================================================

test_inv002_script_auto_discovery() {
  echo ""
  echo "=== INV-002: sync.sh script auto-discovery ==="

  # Create a temporary script file
  local temp_script="scripts/_test-temp-script-$$.sh"
  echo '#!/usr/bin/env bash' > "$REPO_DIR/$temp_script"
  echo '# Temporary test script for INV-002' >> "$REPO_DIR/$temp_script"

  # Run sync.sh
  (cd "$REPO_DIR" && bash sync.sh 2>/dev/null)

  # Verify the file was copied to correctless/scripts/
  assert_file_exists \
    "INV-002: temp script synced to correctless/scripts/" \
    "$REPO_DIR/correctless/scripts/_test-temp-script-$$.sh"

  # Cleanup
  rm -f "$REPO_DIR/$temp_script"
  rm -f "$REPO_DIR/correctless/scripts/_test-temp-script-$$.sh"
}

# ============================================================================
# INV-003 [unit]: lib.sh defines canonical write-detection patterns
# _has_write_pattern() must detect ALL write tokens from the union of
# workflow-gate.sh and sensitive-file-guard.sh.
# ============================================================================

test_inv003_has_write_pattern() {
  echo ""
  echo "=== INV-003: _has_write_pattern detects all write tokens ==="

  source "$LIB_SH"

  local rc

  # --- Positive cases: each write token must return 0 ---

  # Core file-manipulation tokens
  _has_write_pattern "cp src/a.ts src/b.ts" && rc=0 || rc=$?
  assert_eq "INV-003: cp detected" "0" "$rc"

  _has_write_pattern "mv old.ts new.ts" && rc=0 || rc=$?
  assert_eq "INV-003: mv detected" "0" "$rc"

  _has_write_pattern "tee output.log" && rc=0 || rc=$?
  assert_eq "INV-003: tee detected" "0" "$rc"

  _has_write_pattern "install -m 755 bin/app /usr/local/bin/app" && rc=0 || rc=$?
  assert_eq "INV-003: install detected" "0" "$rc"

  _has_write_pattern "rm -rf dist/" && rc=0 || rc=$?
  assert_eq "INV-003: rm detected" "0" "$rc"

  _has_write_pattern "rmdir empty/" && rc=0 || rc=$?
  assert_eq "INV-003: rmdir detected" "0" "$rc"

  _has_write_pattern "unlink tmp.lock" && rc=0 || rc=$?
  assert_eq "INV-003: unlink detected" "0" "$rc"

  _has_write_pattern "dd if=/dev/zero of=disk.img bs=1M count=1" && rc=0 || rc=$?
  assert_eq "INV-003: dd detected" "0" "$rc"

  _has_write_pattern "curl -o file.tar.gz https://example.com/file" && rc=0 || rc=$?
  assert_eq "INV-003: curl detected" "0" "$rc"

  _has_write_pattern "wget https://example.com/file.tar.gz" && rc=0 || rc=$?
  assert_eq "INV-003: wget detected" "0" "$rc"

  _has_write_pattern "rsync -av src/ dst/" && rc=0 || rc=$?
  assert_eq "INV-003: rsync detected" "0" "$rc"

  _has_write_pattern "patch -p1 < diff.patch" && rc=0 || rc=$?
  assert_eq "INV-003: patch detected" "0" "$rc"

  _has_write_pattern "truncate -s 0 logfile" && rc=0 || rc=$?
  assert_eq "INV-003: truncate detected" "0" "$rc"

  _has_write_pattern "shred -u secret.key" && rc=0 || rc=$?
  assert_eq "INV-003: shred detected" "0" "$rc"

  _has_write_pattern "ln -s /usr/lib/foo /usr/local/lib/foo" && rc=0 || rc=$?
  assert_eq "INV-003: ln detected" "0" "$rc"

  # Interpreter tokens (union from both hooks)
  _has_write_pattern "python script.py" && rc=0 || rc=$?
  assert_eq "INV-003: python detected" "0" "$rc"

  _has_write_pattern "python3 script.py" && rc=0 || rc=$?
  assert_eq "INV-003: python3 detected" "0" "$rc"

  _has_write_pattern "node script.js" && rc=0 || rc=$?
  assert_eq "INV-003: node detected" "0" "$rc"

  _has_write_pattern "ruby script.rb" && rc=0 || rc=$?
  assert_eq "INV-003: ruby detected" "0" "$rc"

  # Redirect operators
  _has_write_pattern "echo hello > output.txt" && rc=0 || rc=$?
  assert_eq "INV-003: > redirect detected" "0" "$rc"

  _has_write_pattern "echo hello >> output.txt" && rc=0 || rc=$?
  assert_eq "INV-003: >> redirect detected" "0" "$rc"

  _has_write_pattern "cmd 2> error.log" && rc=0 || rc=$?
  assert_eq "INV-003: 2> redirect detected" "0" "$rc"

  # sed -i and perl -i
  _has_write_pattern "sed -i 's/foo/bar/' file.txt" && rc=0 || rc=$?
  assert_eq "INV-003: sed -i detected" "0" "$rc"

  _has_write_pattern "perl -i -pe 's/foo/bar/' file.txt" && rc=0 || rc=$?
  assert_eq "INV-003: perl -i detected" "0" "$rc"

  # --- Negative cases: non-write commands must return 1 ---

  _has_write_pattern "cat src/app.ts" && rc=0 || rc=$?
  assert_eq "INV-003: cat not detected as write" "1" "$rc"

  _has_write_pattern "ls -la src/" && rc=0 || rc=$?
  assert_eq "INV-003: ls not detected as write" "1" "$rc"

  _has_write_pattern "git status" && rc=0 || rc=$?
  assert_eq "INV-003: git not detected as write" "1" "$rc"

  _has_write_pattern "grep -r pattern src/" && rc=0 || rc=$?
  assert_eq "INV-003: grep not detected as write" "1" "$rc"

  _has_write_pattern "echo hello" && rc=0 || rc=$?
  assert_eq "INV-003: echo (no redirect) not detected as write" "1" "$rc"

  # sed without -i (read-only)
  _has_write_pattern "sed 's/foo/bar/' file.txt" && rc=0 || rc=$?
  assert_eq "INV-003: sed without -i not detected as write" "1" "$rc"

  # perl without -i (read-only)
  _has_write_pattern "perl -ne 'print' file.txt" && rc=0 || rc=$?
  assert_eq "INV-003: perl without -i not detected as write" "1" "$rc"
}

# ============================================================================
# INV-004 [unit]: lib.sh defines canonical file extraction function
# get_target_file() must match all 25 extensions and reject non-matching ones.
# ============================================================================

test_inv004_get_target_file() {
  echo ""
  echo "=== INV-004: get_target_file extracts files with 25 extensions ==="

  source "$LIB_SH"

  local result

  # --- Positive cases: each of the 25 extensions ---

  result="$(get_target_file "cp src/main.go dst/")"
  assert_contains "INV-004: .go matched" "main.go" "$result"

  result="$(get_target_file "cp src/app.ts dst/")"
  assert_contains "INV-004: .ts matched" "app.ts" "$result"

  result="$(get_target_file "cp src/App.tsx dst/")"
  assert_contains "INV-004: .tsx matched" "App.tsx" "$result"

  result="$(get_target_file "cp src/index.js dst/")"
  assert_contains "INV-004: .js matched" "index.js" "$result"

  result="$(get_target_file "cp src/Component.jsx dst/")"
  assert_contains "INV-004: .jsx matched" "Component.jsx" "$result"

  result="$(get_target_file "cp src/main.py dst/")"
  assert_contains "INV-004: .py matched" "main.py" "$result"

  result="$(get_target_file "cp src/lib.rs dst/")"
  assert_contains "INV-004: .rs matched" "lib.rs" "$result"

  result="$(get_target_file "cp src/Main.java dst/")"
  assert_contains "INV-004: .java matched" "Main.java" "$result"

  result="$(get_target_file "cp src/app.rb dst/")"
  assert_contains "INV-004: .rb matched" "app.rb" "$result"

  result="$(get_target_file "cp src/main.cpp dst/")"
  assert_contains "INV-004: .cpp matched" "main.cpp" "$result"

  result="$(get_target_file "cp src/main.c dst/")"
  assert_contains "INV-004: .c matched" "main.c" "$result"

  result="$(get_target_file "cp src/header.h dst/")"
  assert_contains "INV-004: .h matched" "header.h" "$result"

  result="$(get_target_file "cp scripts/run.sh dst/")"
  assert_contains "INV-004: .sh matched" "run.sh" "$result"

  result="$(get_target_file "cp config/settings.json dst/")"
  assert_contains "INV-004: .json matched" "settings.json" "$result"

  result="$(get_target_file "cp docs/README.md dst/")"
  assert_contains "INV-004: .md matched" "README.md" "$result"

  result="$(get_target_file "cp config/app.yaml dst/")"
  assert_contains "INV-004: .yaml matched" "app.yaml" "$result"

  result="$(get_target_file "cp config/app.yml dst/")"
  assert_contains "INV-004: .yml matched" "app.yml" "$result"

  result="$(get_target_file "cp config/Cargo.toml dst/")"
  assert_contains "INV-004: .toml matched" "Cargo.toml" "$result"

  result="$(get_target_file "cp config/setup.cfg dst/")"
  assert_contains "INV-004: .cfg matched" "setup.cfg" "$result"

  result="$(get_target_file "cp config/settings.ini dst/")"
  assert_contains "INV-004: .ini matched" "settings.ini" "$result"

  result="$(get_target_file "cp db/schema.sql dst/")"
  assert_contains "INV-004: .sql matched" "schema.sql" "$result"

  result="$(get_target_file "cp styles/main.css dst/")"
  assert_contains "INV-004: .css matched" "main.css" "$result"

  result="$(get_target_file "cp public/index.html dst/")"
  assert_contains "INV-004: .html matched" "index.html" "$result"

  result="$(get_target_file "cp src/App.vue dst/")"
  assert_contains "INV-004: .vue matched" "App.vue" "$result"

  result="$(get_target_file "cp src/App.svelte dst/")"
  assert_contains "INV-004: .svelte matched" "App.svelte" "$result"

  # --- Negative cases: non-matching extensions ---

  result="$(get_target_file "cp package-lock.json yarn.lock dst/")"
  # .lock should NOT match (even though .json does match, .lock must not)
  assert_not_contains "INV-004: .lock not matched" ".lock" "$result"

  result="$(get_target_file "cp images/logo.png dst/")"
  assert_eq "INV-004: .png not matched" "" "$result"

  result="$(get_target_file "cp build/module.wasm dst/")"
  assert_eq "INV-004: .wasm not matched" "" "$result"

  # --- Multi-file extraction (QA-001: get_target_file returns ALL matches) ---

  result="$(get_target_file "cp src/app.ts src/config.json dst/")"
  assert_contains "INV-004: multi-file — first file extracted" "src/app.ts" "$result"
  assert_contains "INV-004: multi-file — second file extracted" "src/config.json" "$result"

  # Count: should return exactly 2 files
  local line_count
  line_count="$(echo "$result" | wc -l)"
  line_count="${line_count// /}"  # trim whitespace
  assert_eq "INV-004: multi-file — returns 2 lines" "2" "$line_count"

  # Single file still works (regression guard)
  result="$(get_target_file "cp src/app.ts dst/")"
  line_count="$(echo "$result" | wc -l)"
  line_count="${line_count// /}"
  assert_eq "INV-004: single-file — returns 1 line" "1" "$line_count"

  # --- Verify the function returns the file PATH, not just the extension ---

  result="$(get_target_file "cp src/deep/nested/app.ts dst/")"
  assert_contains "INV-004: returns file path not just extension" "src/deep/nested/app.ts" "$result"
}

# ============================================================================
# INV-005 [unit]: Consuming hooks use lib.sh shared functions
# Static analysis: verify hooks do NOT define _has_write_pattern() locally
# and do NOT contain the hardcoded file extension regex inline.
# ============================================================================

test_inv005_hooks_use_shared_functions() {
  echo ""
  echo "=== INV-005: Consuming hooks use lib.sh shared functions ==="

  # workflow-gate.sh must NOT define _has_write_pattern() locally
  local wg_local_def
  wg_local_def="$(grep -c '_has_write_pattern()' "$REPO_DIR/hooks/workflow-gate.sh" 2>/dev/null)" || wg_local_def="0"
  assert_eq "INV-005: workflow-gate.sh has no local _has_write_pattern def" "0" "$wg_local_def"

  # sensitive-file-guard.sh must NOT define _has_write_pattern() locally
  local sfg_local_def
  sfg_local_def="$(grep -c '_has_write_pattern()' "$REPO_DIR/hooks/sensitive-file-guard.sh" 2>/dev/null)" || sfg_local_def="0"
  assert_eq "INV-005: sensitive-file-guard.sh has no local _has_write_pattern def" "0" "$sfg_local_def"

  # audit-trail.sh must NOT have the 25-extension regex inline
  local at_inline_regex
  at_inline_regex="$(grep -c 'go|ts|tsx|js|jsx|py|rs|java|rb|cpp|c|h|sh|json|md|yaml|yml|toml|cfg|ini|sql|css|html|vue|svelte' "$REPO_DIR/hooks/audit-trail.sh" 2>/dev/null)" || at_inline_regex="0"
  assert_eq "INV-005: audit-trail.sh has no inline 25-extension regex" "0" "$at_inline_regex"

  # workflow-gate.sh must NOT have the 25-extension regex inline
  local wg_inline_regex
  wg_inline_regex="$(grep -c 'go|ts|tsx|js|jsx|py|rs|java|rb|cpp|c|h|sh|json|md|yaml|yml|toml|cfg|ini|sql|css|html|vue|svelte' "$REPO_DIR/hooks/workflow-gate.sh" 2>/dev/null)" || wg_inline_regex="0"
  assert_eq "INV-005: workflow-gate.sh has no inline 25-extension regex" "0" "$wg_inline_regex"

  # Each consuming hook should call the shared functions instead
  # workflow-gate.sh and sensitive-file-guard.sh should call _has_write_pattern (not define it)
  local wg_calls_fn
  wg_calls_fn="$(grep -c '_has_write_pattern ' "$REPO_DIR/hooks/workflow-gate.sh" 2>/dev/null)" || wg_calls_fn="0"
  if [ "$wg_calls_fn" -gt 0 ]; then
    echo "  PASS: INV-005: workflow-gate.sh calls _has_write_pattern"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: INV-005: workflow-gate.sh does not call _has_write_pattern"
    FAIL=$((FAIL + 1))
  fi

  local sfg_calls_fn
  sfg_calls_fn="$(grep -c '_has_write_pattern ' "$REPO_DIR/hooks/sensitive-file-guard.sh" 2>/dev/null)" || sfg_calls_fn="0"
  if [ "$sfg_calls_fn" -gt 0 ]; then
    echo "  PASS: INV-005: sensitive-file-guard.sh calls _has_write_pattern"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: INV-005: sensitive-file-guard.sh does not call _has_write_pattern"
    FAIL=$((FAIL + 1))
  fi

  # workflow-gate.sh and audit-trail.sh should call get_target_file (not inline regex)
  local wg_calls_gtf
  wg_calls_gtf="$(grep -c 'get_target_file' "$REPO_DIR/hooks/workflow-gate.sh" 2>/dev/null)" || wg_calls_gtf="0"
  if [ "$wg_calls_gtf" -gt 0 ]; then
    echo "  PASS: INV-005: workflow-gate.sh calls get_target_file"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: INV-005: workflow-gate.sh does not call get_target_file"
    FAIL=$((FAIL + 1))
  fi

  local at_calls_gtf
  at_calls_gtf="$(grep -c 'get_target_file' "$REPO_DIR/hooks/audit-trail.sh" 2>/dev/null)" || at_calls_gtf="0"
  if [ "$at_calls_gtf" -gt 0 ]; then
    echo "  PASS: INV-005: audit-trail.sh calls get_target_file"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: INV-005: audit-trail.sh does not call get_target_file"
    FAIL=$((FAIL + 1))
  fi
}

# ============================================================================
# INV-005 [integration]: Runtime wiring — write detection through lib.sh
# Feeds real JSON through hooks to verify _has_write_pattern() works via lib.sh.
# Combined with the static analysis above (no local defs), this proves the
# lib.sh call chain is wired correctly.
# ============================================================================

test_inv005_integration_wiring() {
  echo ""
  echo "=== INV-005 [integration]: Write detection works through lib.sh ==="

  rm -rf "$TEST_DIR"
  mkdir -p "$TEST_DIR"
  cd "$TEST_DIR" || exit 1

  git init -q
  git branch -M main
  echo "init" > README.md
  git add -A && git commit -q -m "init"
  git checkout -q -b feature/test-inv005

  # Copy hook + lib.sh (lib.sh must be present for wiring to work)
  mkdir -p hooks scripts .correctless/config .correctless/artifacts
  cp "$REPO_DIR/hooks/workflow-gate.sh" hooks/workflow-gate.sh
  cp "$REPO_DIR/scripts/lib.sh" scripts/lib.sh
  source scripts/lib.sh
  local slug
  slug="$(branch_slug)"

  # Config with source file patterns
  cat > .correctless/config/workflow-config.json <<'EOF'
{
  "patterns": { "test_file": "*.test.ts", "source_file": "*.ts|*.js" },
  "workflow": { "fail_closed_when_no_state": false }
}
EOF

  # State file in "spec" phase — source file writes should be blocked
  cat > ".correctless/artifacts/workflow-state-${slug}.json" <<'EOF'
{
  "phase": "spec",
  "override": { "active": false, "remaining_calls": 0 }
}
EOF

  # Feed a Bash write command targeting a source file.
  # After refactoring, _has_write_pattern comes from lib.sh.
  # If the wiring works, the hook detects "cp" as a write and blocks it.
  local json_input='{"tool_name":"Bash","tool_input":{"command":"cp src/app.ts dist/"}}'
  local exit_code
  echo "$json_input" | bash hooks/workflow-gate.sh >/dev/null 2>&1 && exit_code=0 || exit_code=$?

  # Exit 2 = blocked (write detected during restricted phase)
  assert_exit_code "INV-005 [integration]: workflow-gate.sh detects write via lib.sh" "2" "$exit_code"

  cd "$REPO_DIR" || exit 1
}

# ============================================================================
# INV-006 [integration]: Source guard tests exercise the actual guard path
# Tests must craft inputs that navigate past ALL fast-path exits to reach
# the code path that calls _has_write_pattern() or get_target_file().
# PreToolUse hooks exit 2 when lib.sh is missing (fail-closed per PAT-001).
# PostToolUse hooks exit 0 (fail-open per PAT-005).
# ============================================================================

test_inv006_source_guard_pretooluse() {
  echo ""
  echo "=== INV-006: PreToolUse source guard — fail-closed without lib.sh ==="

  # Set up a minimal test environment where workflow-gate.sh can run
  rm -rf "$TEST_DIR"
  mkdir -p "$TEST_DIR"
  cd "$TEST_DIR" || exit 1

  git init -q
  git branch -M main
  echo "init" > README.md
  git add -A && git commit -q -m "init"
  git checkout -q -b feature/test-inv006

  # Copy the hook
  mkdir -p hooks
  cp "$REPO_DIR/hooks/workflow-gate.sh" hooks/workflow-gate.sh

  # Create config
  mkdir -p .correctless/config .correctless/artifacts
  cat > .correctless/config/workflow-config.json <<'EOF'
{
  "patterns": {
    "test_file": "*.test.ts",
    "source_file": "*.ts|*.js"
  },
  "workflow": {
    "fail_closed_when_no_state": false
  }
}
EOF

  # Copy lib.sh temporarily to compute the slug, then remove it
  mkdir -p scripts
  cp "$REPO_DIR/scripts/lib.sh" scripts/lib.sh
  source scripts/lib.sh
  local slug
  slug="$(branch_slug)"

  # Create a valid state file in a blocking phase (spec blocks source edits)
  local state_file=".correctless/artifacts/workflow-state-${slug}.json"
  cat > "$state_file" <<'EOF'
{
  "phase": "spec",
  "override": { "active": false, "remaining_calls": 0 }
}
EOF

  # NOW remove lib.sh to test the source guard
  rm -f scripts/lib.sh

  # Provide a Bash write command that targets a source file.
  # This JSON navigates past:
  #   - tool_name check (Bash is a write tool)
  #   - empty command check (command is "cp a b")
  #   - _has_write_pattern check (cp is a write token — but this is defined locally in current code)
  # After write detection, the hook sources lib.sh for branch_slug.
  # Without lib.sh, the current code does fail-open (exit 0) because
  # branch_slug isn't available. After refactoring, the hook should still
  # use _has_write_pattern from lib.sh. If lib.sh is missing and the hook
  # relies on lib.sh for _has_write_pattern, it must exit 2 (fail-closed).
  local json_input='{"tool_name":"Bash","tool_input":{"command":"cp a.ts b.ts"}}'
  local exit_code stderr_output
  stderr_output="$(echo "$json_input" | bash hooks/workflow-gate.sh 2>&1 >/dev/null)" && exit_code=0 || exit_code=$?

  # After refactoring: _has_write_pattern comes from lib.sh.
  # If lib.sh is missing, the hook can't call _has_write_pattern.
  # PreToolUse hooks must fail-closed (exit 2) per PAT-001.
  assert_exit_code "INV-006: workflow-gate.sh exits 2 without lib.sh" "2" "$exit_code"

  # BLOCKING fix: verify stderr mentions lib.sh — ensures exit 2 is from
  # the source guard, not an unrelated error
  assert_contains "INV-006: stderr mentions lib.sh on source failure" "lib.sh" "$stderr_output"
}

test_inv006_source_guard_posttooluse() {
  echo ""
  echo "=== INV-006: PostToolUse source guard — fail-open without lib.sh ==="

  rm -rf "$TEST_DIR"
  mkdir -p "$TEST_DIR"
  cd "$TEST_DIR" || exit 1

  git init -q
  git branch -M main
  echo "init" > README.md
  git add -A && git commit -q -m "init"
  git checkout -q -b feature/test-inv006-post

  # Copy the hook
  mkdir -p hooks
  cp "$REPO_DIR/hooks/audit-trail.sh" hooks/audit-trail.sh

  # Create artifacts dir (audit-trail.sh bails early without it)
  mkdir -p .correctless/artifacts .correctless/config

  # Create config
  cat > .correctless/config/workflow-config.json <<'EOF'
{
  "patterns": { "test_file": "*.test.ts", "source_file": "*.ts" },
  "workflow": { "intensity": "high" }
}
EOF

  # Copy lib.sh temporarily to compute slug, then remove it
  mkdir -p scripts
  cp "$REPO_DIR/scripts/lib.sh" scripts/lib.sh
  source scripts/lib.sh
  local slug
  slug="$(branch_slug)"

  # Create a valid state file
  cat > ".correctless/artifacts/workflow-state-${slug}.json" <<'EOF'
{
  "phase": "tdd-impl",
  "override": { "active": false, "remaining_calls": 0 }
}
EOF

  # Remove lib.sh
  rm -f scripts/lib.sh

  # Provide a Bash command with a known extension file.
  # After refactoring, audit-trail.sh will use get_target_file from lib.sh.
  # Without lib.sh, PostToolUse hooks must fail-open (exit 0) per PAT-005.
  local json_input='{"tool_name":"Bash","tool_input":{"command":"cp a.ts b.ts"}}'
  local exit_code
  echo "$json_input" | bash hooks/audit-trail.sh >/dev/null 2>&1 && exit_code=0 || exit_code=$?

  assert_exit_code "INV-006: audit-trail.sh exits 0 without lib.sh" "0" "$exit_code"
}

# ============================================================================
# QA-002 [integration]: sensitive-file-guard.sh Edit works without lib.sh
# Non-Bash write tools (Edit/Write/MultiEdit) must not be blocked when lib.sh
# is missing. Only Bash tools require _has_write_pattern() from lib.sh.
# ============================================================================

test_qa002_sensitive_guard_edit_without_lib() {
  echo ""
  echo "=== QA-002: sensitive-file-guard.sh Edit works without lib.sh ==="

  rm -rf "$TEST_DIR"
  mkdir -p "$TEST_DIR"
  cd "$TEST_DIR" || exit 1

  git init -q
  git branch -M main
  echo "init" > README.md
  git add -A && git commit -q -m "init"
  git checkout -q -b feature/test-qa002

  # Copy the hook — but do NOT copy lib.sh
  mkdir -p hooks .correctless/config .correctless/artifacts
  cp "$REPO_DIR/hooks/sensitive-file-guard.sh" hooks/sensitive-file-guard.sh

  # Config with no sensitive patterns matching our test file
  cat > .correctless/config/workflow-config.json <<'EOF'
{
  "patterns": { "test_file": "*.test.ts", "source_file": "*.ts" },
  "protected_files": { "custom_patterns": [] }
}
EOF

  # Edit operation targeting a non-sensitive file — should be allowed (exit 0)
  local json_input='{"tool_name":"Edit","tool_input":{"file_path":"src/app.ts","old_string":"old","new_string":"new"}}'
  local exit_code
  echo "$json_input" | bash hooks/sensitive-file-guard.sh >/dev/null 2>&1 && exit_code=0 || exit_code=$?
  assert_exit_code "QA-002: Edit exits 0 without lib.sh (non-sensitive file)" "0" "$exit_code"

  # Write operation targeting a non-sensitive file — should also be allowed
  json_input='{"tool_name":"Write","tool_input":{"file_path":"src/utils.ts","content":"export {}"}}'
  echo "$json_input" | bash hooks/sensitive-file-guard.sh >/dev/null 2>&1 && exit_code=0 || exit_code=$?
  assert_exit_code "QA-002: Write exits 0 without lib.sh (non-sensitive file)" "0" "$exit_code"

  # Edit operation targeting a sensitive file — should still be blocked
  json_input='{"tool_name":"Edit","tool_input":{"file_path":".env","old_string":"old","new_string":"new"}}'
  echo "$json_input" | bash hooks/sensitive-file-guard.sh >/dev/null 2>&1 && exit_code=0 || exit_code=$?
  assert_exit_code "QA-002: Edit exits 2 without lib.sh (sensitive .env)" "2" "$exit_code"

  # Bash write command without lib.sh — should be blocked (fail-closed)
  json_input='{"tool_name":"Bash","tool_input":{"command":"cp a.ts b.ts"}}'
  echo "$json_input" | bash hooks/sensitive-file-guard.sh >/dev/null 2>&1 && exit_code=0 || exit_code=$?
  assert_exit_code "QA-002: Bash exits 2 without lib.sh (fail-closed)" "2" "$exit_code"

  cd "$REPO_DIR" || exit 1
}

# ============================================================================
# INV-007 [unit]: Characterization tests — _has_write_pattern()
# Every token from workflow-gate.sh:59 and sensitive-file-guard.sh:76
# must produce identical results through the shared function.
# Note: python/python3/node/ruby were already present in workflow-gate.sh
# (separate case line). Consolidation into _has_write_pattern() is not a
# behavioral change — it preserves the existing detection behavior.
# ============================================================================

test_inv007_characterization_write_patterns() {
  echo ""
  echo "=== INV-007: Characterization — _has_write_pattern results match originals ==="

  source "$LIB_SH"

  local rc

  # Tokens from workflow-gate.sh:59 (the original case line):
  # cp|mv|tee|install|rm|rmdir|unlink|dd|curl|wget|rsync|patch|truncate|shred|ln
  # Plus: python|python3|node|ruby (line 62)
  # Plus: sed -i, perl -i (lines 60-61)
  # Plus: redirect operators (line 53)

  # Tokens from sensitive-file-guard.sh:76 (the original case line):
  # cp|mv|tee|install|rm|rmdir|unlink|dd|rsync|patch|truncate|shred|curl|wget|ln|python|python3|node|ruby
  # Plus: sed -i, perl -i (lines 77-78)
  # Plus: redirect operators (line 70)

  # The union is: cp, mv, tee, install, rm, rmdir, unlink, dd, curl, wget,
  # rsync, patch, truncate, shred, ln, python, python3, node, ruby
  # + sed -i, perl -i, redirect operators

  # Each token from the UNION of both hooks — all must return 0:

  local -a write_tokens=(
    "cp file1 file2"
    "mv old new"
    "tee output.log"
    "install -m 755 app /usr/local/bin/"
    "rm -f temp"
    "rmdir empty"
    "unlink symlink"
    "dd if=/dev/zero of=disk.img"
    "curl -o out.tgz https://example.com"
    "wget https://example.com"
    "rsync -av src/ dst/"
    "patch -p1 < fix.patch"
    "truncate -s 0 log"
    "shred -u secret"
    "ln -s target link"
    "python script.py"
    "python3 script.py"
    "node script.js"
    "ruby script.rb"
  )

  for cmd in "${write_tokens[@]}"; do
    local token="${cmd%% *}"
    _has_write_pattern "$cmd" && rc=0 || rc=$?
    assert_eq "INV-007: token '$token' returns 0" "0" "$rc"
  done

  # sed -i and perl -i
  _has_write_pattern "sed -i 's/foo/bar/' file" && rc=0 || rc=$?
  assert_eq "INV-007: sed -i returns 0" "0" "$rc"

  _has_write_pattern "perl -i -pe 's/foo/bar/' file" && rc=0 || rc=$?
  assert_eq "INV-007: perl -i returns 0" "0" "$rc"

  # Redirect operators
  _has_write_pattern "echo x > file" && rc=0 || rc=$?
  assert_eq "INV-007: > redirect returns 0" "0" "$rc"

  _has_write_pattern "echo x >> file" && rc=0 || rc=$?
  assert_eq "INV-007: >> redirect returns 0" "0" "$rc"

  # python/python3/node/ruby were already present in workflow-gate.sh
  # (separate case line at line 62). Consolidation into _has_write_pattern()
  # preserves existing behavior — not an intentional behavioral change.
  _has_write_pattern "python -c 'import os; os.remove(\"f\")'" && rc=0 || rc=$?
  assert_eq "INV-007: python detected (already present in workflow-gate)" "0" "$rc"

  _has_write_pattern "node -e 'require(\"fs\").writeFileSync(\"f\",\"x\")'" && rc=0 || rc=$?
  assert_eq "INV-007: node detected (already present in workflow-gate)" "0" "$rc"
}

# ============================================================================
# INV-008 [integration]: sync.sh --check detects stale distribution files
# If correctless/hooks/ or correctless/scripts/ contains a .sh file that
# doesn't exist in the source directory, --check exits 1.
# ============================================================================

test_inv008_stale_hooks_detected() {
  echo ""
  echo "=== INV-008: sync.sh --check detects stale hook files ==="

  # First run a normal sync to ensure everything is clean
  (cd "$REPO_DIR" && bash sync.sh 2>/dev/null)

  # Add an orphan file to correctless/hooks/ with no source counterpart
  local orphan_hook="correctless/hooks/_orphan-test-$$.sh"
  echo '#!/usr/bin/env bash' > "$REPO_DIR/$orphan_hook"

  # Run --check — should detect the stale file and exit 1
  local exit_code
  (cd "$REPO_DIR" && bash sync.sh --check 2>/dev/null) && exit_code=0 || exit_code=$?
  assert_exit_code "INV-008: --check detects stale hook (exit 1)" "1" "$exit_code"

  # Cleanup
  rm -f "$REPO_DIR/$orphan_hook"
}

test_inv008_stale_scripts_detected() {
  echo ""
  echo "=== INV-008: sync.sh --check detects stale script files ==="

  # First run a normal sync to ensure everything is clean
  (cd "$REPO_DIR" && bash sync.sh 2>/dev/null)

  # Add an orphan file to correctless/scripts/ with no source counterpart
  local orphan_script="correctless/scripts/_orphan-test-$$.sh"
  echo '#!/usr/bin/env bash' > "$REPO_DIR/$orphan_script"

  # Run --check — should detect the stale file and exit 1
  local exit_code
  (cd "$REPO_DIR" && bash sync.sh --check 2>/dev/null) && exit_code=0 || exit_code=$?
  assert_exit_code "INV-008: --check detects stale script (exit 1)" "1" "$exit_code"

  # Cleanup
  rm -f "$REPO_DIR/$orphan_script"
}

test_inv008_clean_state() {
  echo ""
  echo "=== INV-008: sync.sh --check passes on clean state ==="

  # Run a normal sync first
  (cd "$REPO_DIR" && bash sync.sh 2>/dev/null)

  # --check should exit 0 when everything is in sync
  local exit_code
  (cd "$REPO_DIR" && bash sync.sh --check 2>/dev/null) && exit_code=0 || exit_code=$?
  assert_exit_code "INV-008: --check exits 0 on clean state" "0" "$exit_code"
}

# ============================================================================
# PRH-001 [unit]: No hardcoded filenames in sync loops
# sync.sh hook and script sync loops must use shell globs, not string lists.
# ============================================================================

test_prh001_no_hardcoded_filenames() {
  echo ""
  echo "=== PRH-001: No hardcoded filenames in sync.sh hook/script loops ==="

  # The hook sync loop currently looks like:
  #   for hook in workflow-gate.sh workflow-advance.sh ...; do
  # After implementation it should look like:
  #   for hook in hooks/*.sh; do
  # or similar glob pattern.

  # Check that the hook loop uses a glob pattern, not a hardcoded list.
  # A hardcoded list would have quoted filenames like "workflow-gate.sh" in the for line.
  # A glob would reference the hooks/ directory path with *.sh.

  # Look for "for hook in" lines that contain literal .sh filenames (hardcoded list)
  local hook_hardcoded
  hook_hardcoded="$(grep -E 'for hook in [a-zA-Z].*\.sh' "$REPO_DIR/sync.sh" 2>/dev/null | grep -v '\*' | wc -l)" || hook_hardcoded="0"
  assert_eq "PRH-001: hook loop has no hardcoded filenames" "0" "$hook_hardcoded"

  # Look for "for script in" lines that contain literal .sh filenames (hardcoded list)
  local script_hardcoded
  script_hardcoded="$(grep -E 'for script in [a-zA-Z].*\.sh' "$REPO_DIR/sync.sh" 2>/dev/null | grep -v '\*' | wc -l)" || script_hardcoded="0"
  assert_eq "PRH-001: script loop has no hardcoded filenames" "0" "$script_hardcoded"

  # Verify the hook loop uses a glob pattern (hooks/*.sh or similar)
  local hook_glob
  hook_glob="$(grep -cE 'for [a-z_]+ in hooks/\*\.sh' "$REPO_DIR/sync.sh" 2>/dev/null)" || hook_glob="0"
  if [ "$hook_glob" -gt 0 ]; then
    echo "  PASS: PRH-001: hook loop uses glob pattern"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: PRH-001: hook loop does not use glob pattern (expected hooks/*.sh)"
    FAIL=$((FAIL + 1))
  fi

  # Verify the script loop uses a glob pattern (scripts/*.sh or similar)
  local script_glob
  script_glob="$(grep -cE 'for [a-z_]+ in scripts/\*\.sh' "$REPO_DIR/sync.sh" 2>/dev/null)" || script_glob="0"
  if [ "$script_glob" -gt 0 ]; then
    echo "  PASS: PRH-001: script loop uses glob pattern"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: PRH-001: script loop does not use glob pattern (expected scripts/*.sh)"
    FAIL=$((FAIL + 1))
  fi
}

# ============================================================================
# PRH-002 [unit]: No local pattern definitions in consuming hooks
# No hook may define _has_write_pattern() locally or hardcode the file
# extension regex inline. All write-detection patterns must come from lib.sh.
# ============================================================================

test_prh002_no_local_patterns() {
  echo ""
  echo "=== PRH-002: No local pattern definitions in consuming hooks ==="

  # Check ALL hook files for _has_write_pattern() function definitions
  # Only scripts/lib.sh should define it.
  local hook_files
  hook_files="$(ls "$REPO_DIR"/hooks/*.sh 2>/dev/null)"

  local total_hook_defs=0
  for hf in $hook_files; do
    local count
    count="$(grep -c '_has_write_pattern()' "$hf" 2>/dev/null)" || count="0"
    total_hook_defs=$((total_hook_defs + count))
  done
  assert_eq "PRH-002: no hook defines _has_write_pattern() locally" "0" "$total_hook_defs"

  # Check that _has_write_pattern IS defined in scripts/lib.sh
  local lib_def
  lib_def="$(grep -c '_has_write_pattern()' "$REPO_DIR/scripts/lib.sh" 2>/dev/null)" || lib_def="0"
  if [ "$lib_def" -gt 0 ]; then
    echo "  PASS: PRH-002: _has_write_pattern defined in scripts/lib.sh"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: PRH-002: _has_write_pattern NOT defined in scripts/lib.sh"
    FAIL=$((FAIL + 1))
  fi

  # Check ALL hook files for the 25-extension regex pattern
  local total_hook_regex=0
  for hf in $hook_files; do
    local count
    count="$(grep -c 'go|ts|tsx|js|jsx|py|rs|java|rb|cpp|c|h|sh|json|md|yaml|yml|toml|cfg|ini|sql|css|html|vue|svelte' "$hf" 2>/dev/null)" || count="0"
    total_hook_regex=$((total_hook_regex + count))
  done
  assert_eq "PRH-002: no hook has inline 25-extension regex" "0" "$total_hook_regex"
}

# ============================================================================
# Run all tests
# ============================================================================

test_inv003_has_write_pattern
test_inv004_get_target_file
test_inv005_hooks_use_shared_functions
test_inv005_integration_wiring
test_inv006_source_guard_pretooluse
test_inv006_source_guard_posttooluse
test_qa002_sensitive_guard_edit_without_lib
test_inv007_characterization_write_patterns
test_inv001_hook_auto_discovery
test_inv002_script_auto_discovery
test_inv008_stale_hooks_detected
test_inv008_stale_scripts_detected
test_inv008_clean_state
test_prh001_no_hardcoded_filenames
test_prh002_no_local_patterns

# ============================================================================
# Summary
# ============================================================================

echo ""
echo "=============================="
echo "  PASS: $PASS"
echo "  FAIL: $FAIL"
echo "=============================="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
