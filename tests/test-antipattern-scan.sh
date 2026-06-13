#!/usr/bin/env bash
# Correctless — Antipattern Scanner Tests
# Tests spec rules from .correctless/specs/antipattern-scan.md
# R-001 through R-019
# Run from repo root: bash tests/test-antipattern-scan.sh

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCANNER="$REPO_DIR/scripts/antipattern-scan.sh"
LIB="$REPO_DIR/scripts/lib.sh"
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
  if ! grep -qF "$unexpected" <<< "$actual"; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (unexpected output containing '$unexpected')"
    FAIL=$((FAIL + 1))
  fi
}

assert_json_valid() {
  local desc="$1" json_str="$2"
  if echo "$json_str" | jq . >/dev/null 2>&1; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (invalid JSON)"
    FAIL=$((FAIL + 1))
  fi
}

assert_json_field() {
  local desc="$1" field="$2" json_str="$3"
  if echo "$json_str" | jq -e "$field" >/dev/null 2>&1; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (field '$field' not found or null in JSON)"
    FAIL=$((FAIL + 1))
  fi
}

assert_finding_count() {
  local desc="$1" expected="$2" json_str="$3"
  local actual
  actual="$(echo "$json_str" | jq '.findings | length' 2>/dev/null || echo "-1")"
  assert_eq "$desc" "$expected" "$actual"
}

assert_finding_with_pattern() {
  local desc="$1" pattern="$2" json_str="$3"
  local match
  match="$(echo "$json_str" | jq -r ".findings[] | select(.pattern == \"$pattern\") | .pattern" 2>/dev/null | head -1)"
  if [ "$match" = "$pattern" ]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (no finding with pattern '$pattern')"
    FAIL=$((FAIL + 1))
  fi
}

assert_no_finding_with_pattern() {
  local desc="$1" pattern="$2" json_str="$3"
  local match
  match="$(echo "$json_str" | jq -r ".findings[] | select(.pattern == \"$pattern\") | .pattern" 2>/dev/null | head -1)"
  if [ -z "$match" ]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (unexpected finding with pattern '$pattern')"
    FAIL=$((FAIL + 1))
  fi
}

assert_finding_severity() {
  local desc="$1" pattern="$2" expected_severity="$3" json_str="$4"
  local actual_severity
  actual_severity="$(echo "$json_str" | jq -r ".findings[] | select(.pattern == \"$pattern\") | .severity" 2>/dev/null | head -1)"
  assert_eq "$desc" "$expected_severity" "$actual_severity"
}

TMPDIR="$(mktemp -d /tmp/correctless-antipattern-test-$$-XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

# Create a fresh git repo in a temp directory with a feature branch and changed files.
# Usage: setup_git_repo <dir> [files...]
# Each file arg is "path:content" — the file is created on the feature branch.
setup_git_repo() {
  local dir="$1"
  shift
  rm -rf "$dir"
  mkdir -p "$dir"
  cd "$dir" || return 1

  git init -q
  git checkout -q -b main
  # Initial commit so main exists
  echo "init" > .gitkeep
  git add .gitkeep
  git commit -q -m "init"

  # Create feature branch
  git checkout -q -b feature/test-branch

  # Add requested files
  for file_spec in "$@"; do
    local fpath="${file_spec%%:*}"
    local content="${file_spec#*:}"
    mkdir -p "$(dirname "$fpath")"
    printf '%s\n' "$content" > "$fpath"
    git add "$fpath"
  done

  if [ $# -gt 0 ]; then
    git commit -q -m "add test files"
  fi

  cd - >/dev/null || return 1
}

# Run the scanner in a given directory and capture stdout
run_scanner() {
  local dir="$1"
  shift
  local output
  output="$(cd "$dir" && bash "$SCANNER" "$@" 2>/dev/null)" || true
  echo "$output"
}

# Run the scanner and capture stderr separately.
# Sets two global variables: SCANNER_STDOUT and SCANNER_STDERR
run_scanner_with_stderr() {
  local dir="$1"
  shift
  local stderr_file
  stderr_file="$(mktemp "$TMPDIR/stderr-XXXXXX")"
  SCANNER_STDOUT="$(cd "$dir" && bash "$SCANNER" "$@" 2>"$stderr_file")" || true
  SCANNER_STDERR="$(cat "$stderr_file")"
  rm -f "$stderr_file"
}

# Run the scanner capturing exit code
run_scanner_exit_code() {
  local dir="$1"
  shift
  local ec
  (cd "$dir" && bash "$SCANNER" "$@" >/dev/null 2>&1) && ec=0 || ec=$?
  echo "$ec"
}

echo "=== Antipattern Scanner Tests ==="
echo "Scanner: $SCANNER"
echo ""

# ===========================================================================
# R-001 [integration]: Git diff file detection
# ===========================================================================

test_r001_git_diff_file_detection() {
  echo ""
  echo "=== R-001: Git diff file detection ==="

  local test_dir="$TMPDIR/r001"

  # (a) Normal: files on feature branch are detected
  setup_git_repo "$test_dir/normal" \
    "src/main.ts:console.log('debug')" \
    "src/utils.py:print('debug')"

  local output
  output="$(run_scanner "$test_dir/normal" main)"
  assert_json_valid "R-001a: Output is valid JSON" "$output"
  # Scanner should find these files and produce findings for debug logging
  assert_contains "R-001a: Finds main.ts changes" "main.ts" "$output"

  # (b) Detached HEAD fallback — scanner should still work (fallback to all tracked files)
  setup_git_repo "$test_dir/detached" \
    "src/app.ts:console.log('test')"
  cd "$test_dir/detached" || return
  local head_sha
  head_sha="$(git rev-parse HEAD)"
  git checkout -q "$head_sha" 2>/dev/null  # detached HEAD
  cd - >/dev/null || return

  output="$(run_scanner "$test_dir/detached" main)"
  local exit_code
  exit_code="$(run_scanner_exit_code "$test_dir/detached" main)"
  assert_eq "R-001b: Detached HEAD exits 0" "0" "$exit_code"
  assert_json_valid "R-001b: Detached HEAD output is valid JSON" "$output"

  # (c) On main — early exit with empty findings
  setup_git_repo "$test_dir/on-main" \
    "src/main.ts:console.log('debug')"
  cd "$test_dir/on-main" || return
  git checkout -q main
  cd - >/dev/null || return

  output="$(run_scanner "$test_dir/on-main" main)"
  assert_json_valid "R-001c: On-main output is valid JSON" "$output"
  assert_finding_count "R-001c: On-main produces zero findings" "0" "$output"

  # (d) Missing base branch fallback
  setup_git_repo "$test_dir/no-base" \
    "src/main.ts:console.log('debug')"

  output="$(run_scanner "$test_dir/no-base" nonexistent-base)"
  exit_code="$(run_scanner_exit_code "$test_dir/no-base" nonexistent-base)"
  assert_eq "R-001d: Missing base branch exits 0" "0" "$exit_code"
  assert_json_valid "R-001d: Missing base branch output is valid JSON" "$output"

  # --- B-01: Shallow clone fallback ---
  # Create a repo, clone it with --depth 1, verify scanner falls back
  setup_git_repo "$test_dir/shallow-origin" \
    "src/main.ts:console.log('shallow test')"
  # Clone the repo with --depth 1 so merge-base is unavailable
  git clone --depth 1 "file://$test_dir/shallow-origin" "$test_dir/shallow-clone" -q 2>/dev/null
  cd "$test_dir/shallow-clone" || return
  git checkout -q -b feature/shallow-test 2>/dev/null
  mkdir -p src
  echo "console.log('shallow finding')" > src/shallow.ts
  git add src/shallow.ts
  git commit -q -m "add shallow file"
  cd - >/dev/null || return

  output="$(run_scanner "$test_dir/shallow-clone" main)"
  exit_code="$(run_scanner_exit_code "$test_dir/shallow-clone" main)"
  assert_eq "B-01: Shallow clone exits 0" "0" "$exit_code"
  assert_json_valid "B-01: Shallow clone output is valid JSON" "$output"

  # --- B-02: Stderr warning on all fallback tests ---

  # Detached HEAD stderr warning
  run_scanner_with_stderr "$test_dir/detached" main
  assert_contains "B-02: Detached HEAD stderr contains warning" "warning" "$SCANNER_STDERR"

  # Shallow clone stderr warning
  run_scanner_with_stderr "$test_dir/shallow-clone" main
  assert_contains "B-02: Shallow clone stderr contains warning" "warning" "$SCANNER_STDERR"

  # Missing base branch stderr warning
  run_scanner_with_stderr "$test_dir/no-base" nonexistent-base
  assert_contains "B-02: Missing base stderr contains warning" "warning" "$SCANNER_STDERR"

  # --- B-03: On-main stderr note ---
  run_scanner_with_stderr "$test_dir/on-main" main
  assert_contains "B-03: On-main stderr contains note" "note" "$SCANNER_STDERR"

  # --- B-04: "master" branch early exit ---
  local test_dir_master="$test_dir/master-branch"
  rm -rf "$test_dir_master"
  mkdir -p "$test_dir_master"
  cd "$test_dir_master" || return
  git init -q
  # Create initial commit on master (not main)
  git checkout -q -b master
  echo "init" > .gitkeep
  git add .gitkeep
  git commit -q -m "init on master"
  # Add a file with an antipattern (should not be flagged since we're on master)
  mkdir -p src
  echo "console.log('debug')" > src/main.ts
  git add src/main.ts
  git commit -q -m "add file on master"
  cd - >/dev/null || return

  output="$(run_scanner "$test_dir_master" master)"
  assert_json_valid "B-04: On-master output is valid JSON" "$output"
  assert_finding_count "B-04: On-master produces zero findings" "0" "$output"

  # --- B-05: Fallback scans actually produce findings from tracked files ---

  # Detached HEAD fallback should find antipatterns in tracked files
  output="$(run_scanner "$test_dir/detached" main)"
  assert_finding_with_pattern "B-05: Detached HEAD fallback finds console-debug" "console-debug" "$output"

  # Missing base branch fallback should find antipatterns in tracked files
  output="$(run_scanner "$test_dir/no-base" nonexistent-base)"
  assert_finding_with_pattern "B-05: Missing base fallback finds console-debug" "console-debug" "$output"
}

# ===========================================================================
# R-002 [unit]: Extension routing
# ===========================================================================

test_r002_extension_routing() {
  echo ""
  echo "=== R-002: Extension routing ==="

  local test_dir="$TMPDIR/r002"

  # Create files with each supported extension, each containing a detectable pattern
  setup_git_repo "$test_dir" \
    "src/a.js:console.log('x')" \
    "src/b.ts:console.log('x')" \
    "src/c.tsx:console.log('x')" \
    "src/d.jsx:console.log('x')" \
    "src/e.mjs:console.log('x')" \
    "src/f.cjs:console.log('x')" \
    "src/g.mts:console.log('x')" \
    "src/h.cts:console.log('x')" \
    "src/i.py:print('x')" \
    "src/j.go:fmt.Println(\"x\")" \
    "src/k.rs:println!(\"x\")" \
    "src/l.sh:echo \"debug\""

  local output
  output="$(run_scanner "$test_dir" main)"
  assert_json_valid "R-002: Output is valid JSON" "$output"

  # Each supported extension should produce at least one finding
  for ext in js ts tsx jsx mjs cjs mts cts py go rs sh; do
    local file_match
    file_match="$(echo "$output" | jq -r ".findings[] | select(.file | endswith(\".$ext\")) | .file" 2>/dev/null | head -1)"
    if [ -n "$file_match" ]; then
      echo "  PASS: R-002: .$ext routed to checks"
      PASS=$((PASS + 1))
    else
      echo "  FAIL: R-002: .$ext not routed to checks"
      FAIL=$((FAIL + 1))
    fi
  done

  # Case-insensitive: .JS and .Py should also route
  local test_dir_case="$TMPDIR/r002-case"
  setup_git_repo "$test_dir_case" \
    "src/upper.JS:console.log('x')" \
    "src/mixed.Py:print('x')"

  output="$(run_scanner "$test_dir_case" main)"
  assert_contains "R-002: .JS routes (case-insensitive)" "upper.JS" "$output"
  assert_contains "R-002: .Py routes (case-insensitive)" "mixed.Py" "$output"

  # --- A-01: .sh routing produces a shell-specific finding, not just any generic finding ---
  local test_dir_sh_route="$TMPDIR/r002-sh-route"
  setup_git_repo "$test_dir_sh_route" \
    "src/deploy.sh:some_command || true"

  output="$(run_scanner "$test_dir_sh_route" main)"
  # The finding must come from the shell check set specifically (error-suppression or debug-echo),
  # not a generic pattern like placeholder or todo-comment
  local sh_pattern
  sh_pattern="$(echo "$output" | jq -r '.findings[] | select(.file | endswith(".sh")) | .pattern' 2>/dev/null | head -1)"
  if [ "$sh_pattern" = "error-suppression" ] || [ "$sh_pattern" = "debug-echo" ]; then
    echo "  PASS: A-01: .sh file routed to shell-specific check (pattern=$sh_pattern)"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: A-01: .sh file not routed to shell-specific check (got pattern='$sh_pattern', expected 'error-suppression' or 'debug-echo')"
    FAIL=$((FAIL + 1))
  fi

  # Unsupported extensions are skipped silently
  local test_dir_skip="$TMPDIR/r002-skip"
  setup_git_repo "$test_dir_skip" \
    "src/a.java:System.out.println(\"x\")" \
    "src/b.kt:println(\"x\")" \
    "src/c.xyz:random content"

  output="$(run_scanner "$test_dir_skip" main)"
  assert_json_valid "R-002: Skipped extensions produce valid JSON" "$output"
  assert_not_contains "R-002: .java skipped" ".java" "$output"
  assert_not_contains "R-002: .kt skipped" ".kt" "$output"
  assert_not_contains "R-002: .xyz skipped" ".xyz" "$output"
}

# ===========================================================================
# R-003 [integration]: JSON output format
# ===========================================================================

test_r003_json_output_format() {
  echo ""
  echo "=== R-003: JSON output format ==="

  local test_dir="$TMPDIR/r003"

  # (a) Non-empty findings: validate all required fields
  setup_git_repo "$test_dir/fields" \
    "src/main.ts:console.log('debug')"

  local output
  output="$(run_scanner "$test_dir/fields" main)"
  assert_json_valid "R-003a: Output is valid JSON" "$output"
  assert_json_field "R-003a: Has .findings array" ".findings" "$output"

  # Check each finding has required fields
  local first_finding
  first_finding="$(echo "$output" | jq '.findings[0]' 2>/dev/null)"
  if [ "$first_finding" != "null" ] && [ -n "$first_finding" ]; then
    assert_json_field "R-003a: Finding has .id" ".findings[0].id" "$output"
    assert_json_field "R-003a: Finding has .severity" ".findings[0].severity" "$output"
    assert_json_field "R-003a: Finding has .pattern" ".findings[0].pattern" "$output"
    assert_json_field "R-003a: Finding has .file" ".findings[0].file" "$output"
    assert_json_field "R-003a: Finding has .line" ".findings[0].line" "$output"
    assert_json_field "R-003a: Finding has .description" ".findings[0].description" "$output"
    assert_json_field "R-003a: Finding has .category" ".findings[0].category" "$output"
  else
    echo "  FAIL: R-003a: No findings produced for console.log in .ts file"
    FAIL=$((FAIL + 1))
  fi

  # (b) Empty findings: no changed files
  setup_git_repo "$test_dir/empty"
  output="$(run_scanner "$test_dir/empty" main)"
  assert_json_valid "R-003b: Empty findings is valid JSON" "$output"
  assert_eq "R-003b: Empty findings format" '{"findings":[]}' "$(echo "$output" | jq -c '.' 2>/dev/null)"

  # (c) Descriptions are hardcoded, not file content
  setup_git_repo "$test_dir/hardcoded" \
    'src/evil.ts:console.log("INJECTED_DESCRIPTION_VALUE")'

  output="$(run_scanner "$test_dir/hardcoded" main)"
  assert_not_contains "R-003c: Description is not file content" "INJECTED_DESCRIPTION_VALUE" \
    "$(echo "$output" | jq -r '.findings[].description' 2>/dev/null)"

  # --- B-20: JSON constructed via jq, not string concatenation ---
  # Static analysis: grep the scanner script for non-jq JSON construction patterns
  if [ -f "$SCANNER" ]; then

    # Check for echo '{"findings"' — string concatenation pattern
    # Exclude the jq-unavailable fallback (that's the one acceptable case of hardcoded JSON)
    local echo_json_count
    echo_json_count=$(grep -cE "echo[[:space:]]+['\"]\\{\"findings\"" "$SCANNER" 2>/dev/null || true)
    echo_json_count=${echo_json_count:-0}
    if [ "$echo_json_count" -gt 1 ]; then
      echo "  FAIL: B-20: Scanner uses echo for JSON construction in $echo_json_count places (only jq-unavailable fallback is allowed)"
      FAIL=$((FAIL + 1))
    else
      echo "  PASS: B-20: No excess echo-based JSON construction found (jq-unavailable fallback permitted)"
      PASS=$((PASS + 1))
    fi

    # Check for printf.*findings — printf-based JSON construction
    if grep -qE "printf.*findings" "$SCANNER"; then
      echo "  FAIL: B-20: Scanner uses printf for JSON construction (should use jq)"
      FAIL=$((FAIL + 1))
    else
      echo "  PASS: B-20: No printf-based JSON construction found"
      PASS=$((PASS + 1))
    fi

    # Check for string concat patterns like: result+= or result="$result
    if grep -qE '(findings=.*\+|findings=".*\$|"\{.*findings.*\}")' "$SCANNER"; then
      echo "  FAIL: B-20: Scanner uses string concatenation for JSON (should use jq)"
      FAIL=$((FAIL + 1))
    else
      echo "  PASS: B-20: No string concatenation JSON patterns found"
      PASS=$((PASS + 1))
    fi

    # Check for single-quoted JSON string assignments like ='{"findings"
    if grep -qE "='\{" "$SCANNER"; then
      echo "  FAIL: B-20: Scanner uses single-quoted JSON string assignment (should use jq)"
      FAIL=$((FAIL + 1))
    else
      echo "  PASS: B-20: No single-quoted JSON string assignments found"
      PASS=$((PASS + 1))
    fi
  else
    echo "  FAIL: B-20: Scanner script not found"
    FAIL=$((FAIL + 1))
  fi
}

# ===========================================================================
# R-004 [unit]: JS/TS checks
# ===========================================================================

test_r004_js_ts_checks() {
  echo ""
  echo "=== R-004: JS/TS checks ==="

  local test_dir="$TMPDIR/r004"

  # (a) Empty catch block
  setup_git_repo "$test_dir/catch" \
    'src/a.ts:try { foo() } catch(e) { }'

  local output
  output="$(run_scanner "$test_dir/catch" main)"
  assert_finding_with_pattern "R-004a: Empty catch block detected" "empty-catch" "$output"

  # Also test catch { } (no param)
  setup_git_repo "$test_dir/catch2" \
    'src/a.ts:try { foo() } catch { }'

  output="$(run_scanner "$test_dir/catch2" main)"
  assert_finding_with_pattern "R-004a: Empty catch (no param) detected" "empty-catch" "$output"

  # --- A-02: Multi-line empty catch block (v1 limitation test) ---
  # Known v1 limitation — multi-line catch may not be detected (see spec Risks section).
  # We test that the scanner at least doesn't crash on this input and produces valid JSON.
  # If the implementation uses grep -A1 post-processing, it may detect this; if not, that's OK.
  setup_git_repo "$test_dir/catch-multiline"
  cd "$test_dir/catch-multiline" || return
  mkdir -p src
  cat > src/handler.ts <<'MLEOF'
try {
  something()
} catch(e) {
}
MLEOF
  git add src/handler.ts
  git commit -q -m "add multi-line catch"
  cd - >/dev/null || return

  output="$(run_scanner "$test_dir/catch-multiline" main)"
  local exit_code_ml
  exit_code_ml="$(run_scanner_exit_code "$test_dir/catch-multiline" main)"
  assert_eq "A-02: Multi-line catch exits 0" "0" "$exit_code_ml"
  assert_json_valid "A-02: Multi-line catch produces valid JSON" "$output"
  # Bonus: check if it IS detected (optional for v1)
  local ml_catch_detected
  ml_catch_detected="$(echo "$output" | jq -r '.findings[] | select(.pattern == "empty-catch") | .pattern' 2>/dev/null | head -1)"
  if [ "$ml_catch_detected" = "empty-catch" ]; then
    echo "  PASS: A-02: Multi-line empty catch detected (grep -A1 working)"
    PASS=$((PASS + 1))
  else
    # Known v1 limitation — multi-line catch may not be detected
    echo "  FAIL: A-02: Multi-line empty catch not detected (known v1 limitation — grep -A1 post-processing needed)"
    FAIL=$((FAIL + 1))
  fi

  # --- QA-005 class fix: Non-empty multi-line catch block should NOT be flagged ---
  setup_git_repo "$test_dir/catch-nonempty"
  cd "$test_dir/catch-nonempty" || return
  mkdir -p src
  cat > src/handler.ts <<'NEEOF'
try {
  something()
} catch(e) {
  console.error(e)
}
NEEOF
  git add src/handler.ts
  git commit -q -m "add non-empty catch"
  cd - >/dev/null || return

  output="$(run_scanner "$test_dir/catch-nonempty" main)"
  assert_no_finding_with_pattern "QA-005: Non-empty multi-line catch not flagged" "empty-catch" "$output"

  # (b) console.log in non-test file
  setup_git_repo "$test_dir/console" \
    "src/main.ts:console.log('debug info')"

  output="$(run_scanner "$test_dir/console" main)"
  assert_finding_with_pattern "R-004b: console.log detected in non-test" "console-debug" "$output"

  # console.debug also flagged
  setup_git_repo "$test_dir/console-debug" \
    "src/main.ts:console.debug('debug info')"

  output="$(run_scanner "$test_dir/console-debug" main)"
  assert_finding_with_pattern "R-004b: console.debug detected" "console-debug" "$output"

  # (c) as any 4+ times per file
  setup_git_repo "$test_dir/any" \
    "src/main.ts:const a = x as any; const b = y as any; const c = z as any; const d = w as any;"

  output="$(run_scanner "$test_dir/any" main)"
  assert_finding_with_pattern "R-004c: Excessive 'as any' detected (4+)" "excessive-any" "$output"

  # as any 3 times should NOT trigger
  setup_git_repo "$test_dir/any-ok" \
    "src/main.ts:const a = x as any; const b = y as any; const c = z as any;"

  output="$(run_scanner "$test_dir/any-ok" main)"
  assert_no_finding_with_pattern "R-004c: 3x 'as any' not flagged" "excessive-any" "$output"

  # --- A-03: ': any' type annotation variant (R-004c) ---
  setup_git_repo "$test_dir/colon-any"
  cd "$test_dir/colon-any" || return
  mkdir -p src
  cat > src/loose-types.ts <<'ANYEOF'
function process(param: any, data: any) {
  const result: any = transform(data);
  return result as any;
}
ANYEOF
  git add src/loose-types.ts
  git commit -q -m "add colon-any file"
  cd - >/dev/null || return

  output="$(run_scanner "$test_dir/colon-any" main)"
  assert_finding_with_pattern "A-03: ': any' type annotations (4+) trigger excessive-any" "excessive-any" "$output"

  # --- QA-002 class fix: No stderr pollution when zero as-any occurrences ---
  setup_git_repo "$test_dir/zero-any" \
    "src/clean.ts:const x: string = 'hello';"

  run_scanner_with_stderr "$test_dir/zero-any" main
  assert_not_contains "QA-002: No 'integer expression' in stderr for zero as-any" "integer expression" "$SCANNER_STDERR"

  # (d) expect(true) trivial assertion in test file
  setup_git_repo "$test_dir/trivial" \
    "src/main.test.ts:expect(true).toBe(true)"

  output="$(run_scanner "$test_dir/trivial" main)"
  assert_finding_with_pattern "R-004d: Trivial expect(true) detected" "trivial-assertion" "$output"

  # expect(1).toBe(1) also flagged
  setup_git_repo "$test_dir/trivial2" \
    "src/main.test.ts:expect(1).toBe(1)"

  output="$(run_scanner "$test_dir/trivial2" main)"
  assert_finding_with_pattern "R-004d: Trivial expect(1).toBe(1) detected" "trivial-assertion" "$output"

  # (e) Placeholder strings in non-test, non-comment lines
  setup_git_repo "$test_dir/placeholder" \
    "src/config.ts:const key = 'your-api-key'"

  output="$(run_scanner "$test_dir/placeholder" main)"
  assert_finding_with_pattern "R-004e: Placeholder 'your-api-key' detected" "placeholder" "$output"

  # changeme
  setup_git_repo "$test_dir/placeholder2" \
    "src/config.ts:const password = 'changeme'"

  output="$(run_scanner "$test_dir/placeholder2" main)"
  assert_finding_with_pattern "R-004e: Placeholder 'changeme' detected" "placeholder" "$output"

  # --- A-04: Missing placeholder patterns (REPLACE_ME, yourdomain.com, localhost:3000) ---
  setup_git_repo "$test_dir/placeholder-replace-me" \
    "src/config.ts:const token = 'REPLACE_ME'"

  output="$(run_scanner "$test_dir/placeholder-replace-me" main)"
  assert_finding_with_pattern "A-04: Placeholder 'REPLACE_ME' detected in .ts" "placeholder" "$output"

  setup_git_repo "$test_dir/placeholder-yourdomain" \
    "src/config.ts:const host = 'yourdomain.com'"

  output="$(run_scanner "$test_dir/placeholder-yourdomain" main)"
  assert_finding_with_pattern "A-04: Placeholder 'yourdomain.com' detected in .ts" "placeholder" "$output"

  setup_git_repo "$test_dir/placeholder-localhost" \
    "src/config.ts:const url = 'http://localhost: /api'"

  output="$(run_scanner "$test_dir/placeholder-localhost" main)"
  assert_finding_with_pattern "A-04: Placeholder 'localhost:' (non-port) detected in .ts" "placeholder" "$output"

  # localhost:3000 should NOT be flagged — legitimate port config
  setup_git_repo "$test_dir/placeholder-localhost-port" \
    "src/config.ts:const url = 'http://localhost:3000/api'"

  output="$(run_scanner "$test_dir/placeholder-localhost-port" main)"
  assert_no_finding_with_pattern "A-04: 'localhost:3000' not flagged (legitimate port)" "placeholder" "$output"

  # --- QA-017 class fix: JS/TS comment without space should NOT produce placeholder finding ---
  setup_git_repo "$test_dir/placeholder-comment-nospace" \
    "src/config.ts://your-api-key"

  output="$(run_scanner "$test_dir/placeholder-comment-nospace" main)"
  assert_no_finding_with_pattern "QA-017: //your-api-key (comment, no space) not flagged as placeholder" "placeholder" "$output"
}

# ===========================================================================
# R-005 [unit]: Python checks
# ===========================================================================

test_r005_python_checks() {
  echo ""
  echo "=== R-005: Python checks ==="

  local test_dir="$TMPDIR/r005"

  # (a) Bare except:
  setup_git_repo "$test_dir/except" \
    "src/main.py:except:"

  local output
  output="$(run_scanner "$test_dir/except" main)"
  assert_finding_with_pattern "R-005a: Bare 'except:' detected" "bare-except" "$output"

  # except Exception: pass
  setup_git_repo "$test_dir/except-pass" \
    "src/main.py:except Exception: pass"

  output="$(run_scanner "$test_dir/except-pass" main)"
  assert_finding_with_pattern "R-005a: 'except Exception: pass' detected" "bare-except" "$output"

  # --- A-05: 'except Exception as e: pass' variant ---
  setup_git_repo "$test_dir/except-as-e-pass" \
    "src/main.py:except Exception as e: pass"

  output="$(run_scanner "$test_dir/except-as-e-pass" main)"
  assert_finding_with_pattern "A-05: 'except Exception as e: pass' detected" "bare-except" "$output"

  # (b) print() in non-test
  setup_git_repo "$test_dir/print" \
    "src/main.py:print('debug')"

  output="$(run_scanner "$test_dir/print" main)"
  assert_finding_with_pattern "R-005b: print() in non-test detected" "debug-print" "$output"

  # (c) TODO comment
  setup_git_repo "$test_dir/todo" \
    "src/main.py:# TODO fix this later"

  output="$(run_scanner "$test_dir/todo" main)"
  assert_finding_with_pattern "R-005c: # TODO detected" "todo-comment" "$output"

  # FIXME comment
  setup_git_repo "$test_dir/fixme" \
    "src/main.py:# FIXME broken logic"

  output="$(run_scanner "$test_dir/fixme" main)"
  assert_finding_with_pattern "R-005c: # FIXME detected" "todo-comment" "$output"

  # HACK comment
  setup_git_repo "$test_dir/hack" \
    "src/main.py:# HACK workaround"

  output="$(run_scanner "$test_dir/hack" main)"
  assert_finding_with_pattern "R-005c: # HACK detected" "todo-comment" "$output"

  # (d) Placeholder string
  setup_git_repo "$test_dir/placeholder" \
    "src/config.py:API_KEY = 'REPLACE_ME'"

  output="$(run_scanner "$test_dir/placeholder" main)"
  assert_finding_with_pattern "R-005d: Placeholder REPLACE_ME detected" "placeholder" "$output"
}

# ===========================================================================
# R-006 [unit]: Go checks
# ===========================================================================

test_r006_go_checks() {
  echo ""
  echo "=== R-006: Go checks ==="

  local test_dir="$TMPDIR/r006"

  # (a) Empty error handling
  setup_git_repo "$test_dir/err" \
    "src/main.go:if err != nil { }"

  local output
  output="$(run_scanner "$test_dir/err" main)"
  assert_finding_with_pattern "R-006a: Empty error handling detected" "empty-error-handle" "$output"

  # --- A-06: Multi-line Go error handling (v1 limitation test) ---
  # Known v1 limitation — multi-line patterns may not be detected (see spec Risks section).
  # We test that the scanner at least doesn't crash and produces valid JSON.
  setup_git_repo "$test_dir/err-multiline"
  cd "$test_dir/err-multiline" || return
  mkdir -p src
  cat > src/handler.go <<'GOEOF'
func handle() error {
	val, err := doSomething()
	if err != nil {
	}
	return val
}
GOEOF
  git add src/handler.go
  git commit -q -m "add multi-line go error"
  cd - >/dev/null || return

  output="$(run_scanner "$test_dir/err-multiline" main)"
  local exit_code_go_ml
  exit_code_go_ml="$(run_scanner_exit_code "$test_dir/err-multiline" main)"
  assert_eq "A-06: Multi-line Go error exits 0" "0" "$exit_code_go_ml"
  assert_json_valid "A-06: Multi-line Go error produces valid JSON" "$output"
  # Bonus: check if it IS detected (optional for v1)
  local go_ml_detected
  go_ml_detected="$(echo "$output" | jq -r '.findings[] | select(.pattern == "empty-error-handle") | .pattern' 2>/dev/null | head -1)"
  if [ "$go_ml_detected" = "empty-error-handle" ]; then
    echo "  PASS: A-06: Multi-line empty error handling detected (grep -A1 working)"
    PASS=$((PASS + 1))
  else
    # Known v1 limitation — multi-line error handling may not be detected
    echo "  FAIL: A-06: Multi-line empty error handling not detected (known v1 limitation — grep -A1 post-processing needed)"
    FAIL=$((FAIL + 1))
  fi

  # (b) fmt.Println in non-test
  setup_git_repo "$test_dir/fmt" \
    "src/main.go:fmt.Println(\"debug\")"

  output="$(run_scanner "$test_dir/fmt" main)"
  assert_finding_with_pattern "R-006b: fmt.Println detected in non-test" "debug-print" "$output"

  # fmt.Printf also flagged
  setup_git_repo "$test_dir/printf" \
    "src/main.go:fmt.Printf(\"debug %s\", x)"

  output="$(run_scanner "$test_dir/printf" main)"
  assert_finding_with_pattern "R-006b: fmt.Printf detected in non-test" "debug-print" "$output"

  # (c) TODO comment
  setup_git_repo "$test_dir/todo" \
    "src/main.go:// TODO implement this"

  output="$(run_scanner "$test_dir/todo" main)"
  assert_finding_with_pattern "R-006c: // TODO detected" "todo-comment" "$output"

  # (d) Placeholder
  setup_git_repo "$test_dir/placeholder" \
    "src/config.go:var host = \"yourdomain.com\""

  output="$(run_scanner "$test_dir/placeholder" main)"
  assert_finding_with_pattern "R-006d: Placeholder yourdomain.com detected" "placeholder" "$output"
}

# ===========================================================================
# R-007 [unit]: Shell checks
# ===========================================================================

test_r007_shell_checks() {
  echo ""
  echo "=== R-007: Shell checks ==="

  local test_dir="$TMPDIR/r007"

  # (a) || true after non-allowlisted command -> flagged
  setup_git_repo "$test_dir/or-true" \
    "src/deploy.sh:some_command || true"

  local output
  output="$(run_scanner "$test_dir/or-true" main)"
  assert_finding_with_pattern "R-007a: 'some_command || true' detected" "error-suppression" "$output"

  # cd /tmp || true -> NOT flagged (allowlist)
  setup_git_repo "$test_dir/or-true-allowed" \
    "src/deploy.sh:cd /tmp || true"

  output="$(run_scanner "$test_dir/or-true-allowed" main)"
  assert_no_finding_with_pattern "R-007a: 'cd ... || true' not flagged (allowlist)" "error-suppression" "$output"

  # command -v foo || true -> NOT flagged (allowlist)
  setup_git_repo "$test_dir/or-true-cmdv" \
    "src/deploy.sh:command -v jq || true"

  output="$(run_scanner "$test_dir/or-true-cmdv" main)"
  assert_no_finding_with_pattern "R-007a: 'command -v || true' not flagged" "error-suppression" "$output"

  # --- B-06: Missing allowlist tests for which, pushd, popd ---
  setup_git_repo "$test_dir/which-allowed" \
    "src/deploy.sh:which foo || true"

  output="$(run_scanner "$test_dir/which-allowed" main)"
  assert_no_finding_with_pattern "B-06: 'which foo || true' not flagged (allowlist)" "error-suppression" "$output"

  setup_git_repo "$test_dir/pushd-allowed" \
    "src/deploy.sh:pushd /tmp || true"

  output="$(run_scanner "$test_dir/pushd-allowed" main)"
  assert_no_finding_with_pattern "B-06: 'pushd /tmp || true' not flagged (allowlist)" "error-suppression" "$output"

  setup_git_repo "$test_dir/popd-allowed" \
    "src/deploy.sh:popd || true"

  output="$(run_scanner "$test_dir/popd-allowed" main)"
  assert_no_finding_with_pattern "B-06: 'popd || true' not flagged (allowlist)" "error-suppression" "$output"

  # --- B-07: || : variant tested ---
  setup_git_repo "$test_dir/or-colon-flagged" \
    "src/deploy.sh:some_command || :"

  output="$(run_scanner "$test_dir/or-colon-flagged" main)"
  assert_finding_with_pattern "B-07: 'some_command || :' flagged" "error-suppression" "$output"

  setup_git_repo "$test_dir/or-colon-allowed" \
    "src/deploy.sh:cd /tmp || :"

  output="$(run_scanner "$test_dir/or-colon-allowed" main)"
  assert_no_finding_with_pattern "B-07: 'cd /tmp || :' not flagged (allowlist)" "error-suppression" "$output"

  # --- B-08: Pipeline tail exemptions ---
  setup_git_repo "$test_dir/pipe-wc" \
    "src/deploy.sh:some_cmd | wc -l || true"

  output="$(run_scanner "$test_dir/pipe-wc" main)"
  assert_no_finding_with_pattern "B-08: 'some_cmd | wc -l || true' not flagged (pipeline tail)" "error-suppression" "$output"

  setup_git_repo "$test_dir/pipe-grep-c" \
    "src/deploy.sh:some_cmd | grep -c pattern || true"

  output="$(run_scanner "$test_dir/pipe-grep-c" main)"
  assert_no_finding_with_pattern "B-08: 'some_cmd | grep -c pattern || true' not flagged (pipeline tail)" "error-suppression" "$output"

  setup_git_repo "$test_dir/pipe-grep-q" \
    "src/deploy.sh:some_cmd | grep -q pattern || true"

  output="$(run_scanner "$test_dir/pipe-grep-q" main)"
  assert_no_finding_with_pattern "B-08: 'some_cmd | grep -q pattern || true' not flagged (pipeline tail)" "error-suppression" "$output"

  # (b) echo in non-test file -> flagged
  setup_git_repo "$test_dir/echo" \
    'src/deploy.sh:echo "$var"'

  output="$(run_scanner "$test_dir/echo" main)"
  assert_finding_with_pattern "R-007b: 'echo' debug statement detected" "debug-echo" "$output"

  # echo ">>> Step 1" -> NOT flagged (exempt: step prefix)
  setup_git_repo "$test_dir/echo-step" \
    'src/deploy.sh:echo ">>> Step 1: Deploy"'

  output="$(run_scanner "$test_dir/echo-step" main)"
  assert_no_finding_with_pattern "R-007b: 'echo >>> ...' not flagged (exempt)" "debug-echo" "$output"

  # echo "=== Section ===" -> NOT flagged (exempt: section header)
  setup_git_repo "$test_dir/echo-section" \
    'src/deploy.sh:echo "=== Build phase ==="'

  output="$(run_scanner "$test_dir/echo-section" main)"
  assert_no_finding_with_pattern "R-007b: 'echo === ...' not flagged (exempt)" "debug-echo" "$output"

  # --- QA-008 class fix: Single-quoted echo exemptions ---
  setup_git_repo "$test_dir/echo-step-sq"
  cd "$test_dir/echo-step-sq" || return
  mkdir -p src
  printf "%s\n" "echo '>>> Step 1: Deploy'" > src/deploy.sh
  git add src/deploy.sh
  git commit -q -m "add single-quoted step echo"
  cd - >/dev/null || return

  output="$(run_scanner "$test_dir/echo-step-sq" main)"
  assert_no_finding_with_pattern "QA-008: Single-quoted 'echo >>> ...' not flagged (exempt)" "debug-echo" "$output"

  # --- B-09: Missing echo exemption tests ---

  # echo "  PASS: ..." -> NOT flagged (test output)
  setup_git_repo "$test_dir/echo-pass" \
    'src/deploy.sh:echo "  PASS: test passed"'

  output="$(run_scanner "$test_dir/echo-pass" main)"
  assert_no_finding_with_pattern "B-09: 'echo PASS:' not flagged (exempt)" "debug-echo" "$output"

  # echo "  FAIL: ..." -> NOT flagged (test output)
  setup_git_repo "$test_dir/echo-fail" \
    'src/deploy.sh:echo "  FAIL: test failed"'

  output="$(run_scanner "$test_dir/echo-fail" main)"
  assert_no_finding_with_pattern "B-09: 'echo FAIL:' not flagged (exempt)" "debug-echo" "$output"

  # echo "" -> NOT flagged (blank line)
  setup_git_repo "$test_dir/echo-blank" \
    'src/deploy.sh:echo ""'

  output="$(run_scanner "$test_dir/echo-blank" main)"
  assert_no_finding_with_pattern "B-09: 'echo \"\"' not flagged (exempt)" "debug-echo" "$output"

  # echo inside info() function -> NOT flagged
  setup_git_repo "$test_dir/echo-info-fn"
  cd "$test_dir/echo-info-fn" || return
  mkdir -p src
  cat > src/deploy.sh <<'FNEOF'
info() {
  echo "message"
}
FNEOF
  git add src/deploy.sh
  git commit -q -m "add info fn"
  cd - >/dev/null || return

  output="$(run_scanner "$test_dir/echo-info-fn" main)"
  assert_no_finding_with_pattern "B-09: echo inside info() not flagged (exempt)" "debug-echo" "$output"

  # echo inside die() function -> NOT flagged
  setup_git_repo "$test_dir/echo-die-fn"
  cd "$test_dir/echo-die-fn" || return
  mkdir -p src
  cat > src/deploy.sh <<'FNEOF'
die() {
  echo "fatal"
}
FNEOF
  git add src/deploy.sh
  git commit -q -m "add die fn"
  cd - >/dev/null || return

  output="$(run_scanner "$test_dir/echo-die-fn" main)"
  assert_no_finding_with_pattern "B-09: echo inside die() not flagged (exempt)" "debug-echo" "$output"

  # --- QA-009 class fix: Exempt function with nested control flow braces ---
  setup_git_repo "$test_dir/echo-nested-fn"
  cd "$test_dir/echo-nested-fn" || return
  mkdir -p src
  cat > src/deploy.sh <<'FNEOF'
info() {
  {
    echo "grouped output"
  }
  echo "more output"
}
FNEOF
  git add src/deploy.sh
  git commit -q -m "add nested fn"
  cd - >/dev/null || return

  output="$(run_scanner "$test_dir/echo-nested-fn" main)"
  assert_no_finding_with_pattern "QA-009: echo inside nested-brace exempt function not flagged" "debug-echo" "$output"

  # (c) TODO comment
  setup_git_repo "$test_dir/todo" \
    "src/deploy.sh:# TODO wire up deployment"

  output="$(run_scanner "$test_dir/todo" main)"
  assert_finding_with_pattern "R-007c: # TODO detected in .sh" "todo-comment" "$output"

  # (d) Placeholder
  setup_git_repo "$test_dir/placeholder" \
    "src/config.sh:API_KEY='changeme'"

  output="$(run_scanner "$test_dir/placeholder" main)"
  assert_finding_with_pattern "R-007d: Placeholder changeme in .sh detected" "placeholder" "$output"
}

# ===========================================================================
# R-008 [unit]: Rust checks
# ===========================================================================

test_r008_rust_checks() {
  echo ""
  echo "=== R-008: Rust checks ==="

  local test_dir="$TMPDIR/r008"

  # (a) unwrap() 4+ times in non-test -> flagged
  setup_git_repo "$test_dir/unwrap" \
    "src/main.rs:let a = x.unwrap(); let b = y.unwrap(); let c = z.unwrap(); let d = w.unwrap();"

  local output
  output="$(run_scanner "$test_dir/unwrap" main)"
  assert_finding_with_pattern "R-008a: Excessive unwrap() (4+) detected" "excessive-unwrap" "$output"

  # 3 unwrap() calls should NOT trigger
  setup_git_repo "$test_dir/unwrap-ok" \
    "src/main.rs:let a = x.unwrap(); let b = y.unwrap(); let c = z.unwrap();"

  output="$(run_scanner "$test_dir/unwrap-ok" main)"
  assert_no_finding_with_pattern "R-008a: 3x unwrap() not flagged" "excessive-unwrap" "$output"

  # (b) println! in non-test
  setup_git_repo "$test_dir/println" \
    'src/main.rs:println!("debug info");'

  output="$(run_scanner "$test_dir/println" main)"
  assert_finding_with_pattern "R-008b: println! detected in non-test" "debug-print" "$output"

  # dbg! in non-test
  setup_git_repo "$test_dir/dbg" \
    "src/main.rs:dbg!(value);"

  output="$(run_scanner "$test_dir/dbg" main)"
  assert_finding_with_pattern "R-008b: dbg! detected in non-test" "debug-print" "$output"

  # (c) todo!() macro
  setup_git_repo "$test_dir/todo" \
    "src/main.rs:todo!()"

  output="$(run_scanner "$test_dir/todo" main)"
  assert_finding_with_pattern "R-008c: todo!() macro detected" "todo-macro" "$output"

  # (d) Placeholder — localhost: followed by non-port
  setup_git_repo "$test_dir/placeholder" \
    'src/config.rs:let url = "localhost: something";'

  output="$(run_scanner "$test_dir/placeholder" main)"
  assert_finding_with_pattern "R-008d: Placeholder localhost: detected" "placeholder" "$output"

  # localhost:3000 should NOT be flagged — legitimate port config
  setup_git_repo "$test_dir/placeholder-port" \
    'src/config.rs:let url = "localhost:3000";'

  output="$(run_scanner "$test_dir/placeholder-port" main)"
  assert_no_finding_with_pattern "R-008d: localhost:3000 not flagged (legitimate port)" "placeholder" "$output"
}

# ===========================================================================
# R-009 [integration]: Robustness
# ===========================================================================

test_r009_robustness() {
  echo ""
  echo "=== R-009: Robustness ==="

  local test_dir="$TMPDIR/r009"

  # (a) Empty change set (no files added on feature branch)
  setup_git_repo "$test_dir/empty"
  local output exit_code
  output="$(run_scanner "$test_dir/empty" main)"
  exit_code="$(run_scanner_exit_code "$test_dir/empty" main)"
  assert_eq "R-009a: Empty change set exits 0" "0" "$exit_code"
  assert_json_valid "R-009a: Empty change set produces valid JSON" "$output"

  # (b) Binary file in change set
  setup_git_repo "$test_dir/binary"
  cd "$test_dir/binary" || return
  mkdir -p src
  # Create a binary file
  printf '\x00\x01\x02\x03\x04\x05' > src/image.ts
  git add src/image.ts
  git commit -q -m "add binary"
  cd - >/dev/null || return

  output="$(run_scanner "$test_dir/binary" main)"
  exit_code="$(run_scanner_exit_code "$test_dir/binary" main)"
  assert_eq "R-009b: Binary file exits 0" "0" "$exit_code"
  assert_json_valid "R-009b: Binary file produces valid JSON" "$output"

  # (c) Empty file
  setup_git_repo "$test_dir/empty-file" \
    "src/empty.ts:"

  output="$(run_scanner "$test_dir/empty-file" main)"
  exit_code="$(run_scanner_exit_code "$test_dir/empty-file" main)"
  assert_eq "R-009c: Empty file exits 0" "0" "$exit_code"
  assert_json_valid "R-009c: Empty file produces valid JSON" "$output"

  # --- QA-001 class fix: Truly zero-byte file not misclassified as binary ---
  setup_git_repo "$test_dir/zero-byte"
  cd "$test_dir/zero-byte" || return
  mkdir -p src
  printf '' > src/zero.ts
  git add src/zero.ts
  git commit -q --allow-empty-message -m "add zero-byte file"
  cd - >/dev/null || return

  output="$(run_scanner "$test_dir/zero-byte" main)"
  exit_code="$(run_scanner_exit_code "$test_dir/zero-byte" main)"
  assert_eq "QA-001: Zero-byte file exits 0" "0" "$exit_code"
  assert_json_valid "QA-001: Zero-byte file produces valid JSON" "$output"
  local zero_errors
  zero_errors="$(echo "$output" | jq -r '.errors[]? // empty' 2>/dev/null || echo "")"
  assert_not_contains "QA-001: Zero-byte file not reported as binary" "binary" "$zero_errors"

  # (d) File with spaces in name
  setup_git_repo "$test_dir/spaces"
  cd "$test_dir/spaces" || return
  mkdir -p "src/my dir"
  echo "console.log('debug')" > "src/my dir/file name.ts"
  git add "src/my dir/file name.ts"
  git commit -q -m "add spaced file"
  cd - >/dev/null || return

  output="$(run_scanner "$test_dir/spaces" main)"
  exit_code="$(run_scanner_exit_code "$test_dir/spaces" main)"
  assert_eq "R-009d: File with spaces exits 0" "0" "$exit_code"
  assert_json_valid "R-009d: File with spaces produces valid JSON" "$output"

  # (e) Errors array exists when files are unreadable — B-12: strengthen assertion
  # Re-run binary test to get fresh output for this assertion
  output="$(run_scanner "$test_dir/binary" main)"
  local has_errors_key
  has_errors_key="$(echo "$output" | jq 'has("errors")' 2>/dev/null || echo "false")"
  assert_eq "R-009e: JSON structure supports errors array" "true" "$has_errors_key"

  # B-12: Errors array is non-empty AND contains the binary file path
  local errors_len
  errors_len="$(echo "$output" | jq '.errors | length' 2>/dev/null || echo "0")"
  if [ "$errors_len" -gt 0 ]; then
    echo "  PASS: B-12: Errors array is non-empty for binary file"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: B-12: Errors array is empty for binary file (expected non-empty)"
    FAIL=$((FAIL + 1))
  fi
  assert_contains "B-12: Errors array mentions binary file" "image.ts" \
    "$(echo "$output" | jq -r '.errors[]' 2>/dev/null)"

  # --- B-10: Deleted file between diff and scan ---
  setup_git_repo "$test_dir/deleted-file" \
    "src/will-delete.ts:console.log('before delete')"
  # Now delete the file from disk (but it's still in git diff)
  rm -f "$test_dir/deleted-file/src/will-delete.ts"

  output="$(run_scanner "$test_dir/deleted-file" main)"
  exit_code="$(run_scanner_exit_code "$test_dir/deleted-file" main)"
  assert_eq "B-10: Deleted file exits 0" "0" "$exit_code"
  assert_json_valid "B-10: Deleted file output is valid JSON" "$output"
  # Errors array should mention the deleted file
  local deleted_errors
  deleted_errors="$(echo "$output" | jq -r '.errors[]' 2>/dev/null || echo "")"
  assert_contains "B-10: Errors array mentions deleted file" "will-delete.ts" "$deleted_errors"

  # --- B-11: Broken symlinks ---
  setup_git_repo "$test_dir/broken-symlink"
  cd "$test_dir/broken-symlink" || return
  mkdir -p src
  ln -s /nonexistent/target/file.ts src/broken-link.ts
  git add src/broken-link.ts
  git commit -q -m "add broken symlink"
  cd - >/dev/null || return

  output="$(run_scanner "$test_dir/broken-symlink" main)"
  exit_code="$(run_scanner_exit_code "$test_dir/broken-symlink" main)"
  assert_eq "B-11: Broken symlink exits 0" "0" "$exit_code"
  assert_json_valid "B-11: Broken symlink output is valid JSON" "$output"
  local symlink_errors
  symlink_errors="$(echo "$output" | jq -r '.errors[]' 2>/dev/null || echo "")"
  assert_contains "B-11: Errors array mentions broken symlink" "broken-link.ts" "$symlink_errors"

  # --- QA-007 class fix: Scanner outputs valid JSON when jq is unavailable ---
  # Create a restricted PATH that has core tools but not jq
  setup_git_repo "$test_dir/no-jq" \
    "src/main.ts:console.log('debug')"
  local no_jq_bin="$TMPDIR/no-jq-bin"
  mkdir -p "$no_jq_bin"
  for cmd in bash git grep sed wc cat printf mkdir dirname basename head cut tr rm ln; do
    local cmd_path
    cmd_path="$(command -v "$cmd" 2>/dev/null || true)"
    [ -n "$cmd_path" ] && ln -sf "$cmd_path" "$no_jq_bin/$cmd"
  done
  local no_jq_output
  no_jq_output="$(cd "$test_dir/no-jq" && PATH="$no_jq_bin" bash "$SCANNER" main 2>/dev/null)" || true
  if echo "$no_jq_output" | jq . >/dev/null 2>&1; then
    echo "  PASS: QA-007: Scanner outputs valid JSON when jq unavailable"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: QA-007: Scanner does not output valid JSON when jq unavailable (got: '$no_jq_output')"
    FAIL=$((FAIL + 1))
  fi

  # --- QA-015/QA-016 class fix: Tab in filename produces valid JSON ---
  # A tab in a filename must not corrupt the unit-separator-delimited finding records
  setup_git_repo "$test_dir/tab-fname"
  cd "$test_dir/tab-fname" || return
  mkdir -p src
  printf '%s\n' "console.log('debug')" > "$(printf 'src/tab\there.ts')"
  git add -A
  git commit -q -m "add tab-in-filename"
  cd - >/dev/null || return

  local tab_output
  tab_output="$(run_scanner "$test_dir/tab-fname" main)"
  local tab_exit
  tab_exit="$(run_scanner_exit_code "$test_dir/tab-fname" main)"
  assert_eq "QA-015: Tab-in-filename exits 0" "0" "$tab_exit"
  assert_json_valid "QA-015: Tab-in-filename produces valid JSON" "$tab_output"

  # --- B-13: Consumer validation — empty stdout detection ---
  # Verify that empty/missing scanner output can be detected as failure by consumers.
  # The spec says: "consuming skill must validate that stdout is non-empty valid JSON
  # before treating it as findings — empty or invalid output means the scanner failed."

  # Empty string must NOT have a .findings key — consumers should check for .findings
  local empty_has_findings
  empty_has_findings="$(printf '' | jq -e '.findings' 2>/dev/null && echo "yes" || echo "no")"
  assert_eq "B-13: Empty input has no .findings key" "no" "$empty_has_findings"

  # Valid empty findings JSON must have .findings key
  local valid_has_findings
  valid_has_findings="$(printf '%s' '{"findings": []}' | jq -e '.findings' >/dev/null 2>&1&& echo "yes" || echo "no")"
  assert_eq "B-13: Valid empty findings has .findings key" "yes" "$valid_has_findings"

  # Junk output (simulating scanner crash) must NOT have .findings key
  local junk_has_findings
  junk_has_findings="$(printf '%s' 'bash: line 42: syntax error' | jq -e '.findings' 2>/dev/null && echo "yes" || echo "no")"
  assert_eq "B-13: Junk output has no .findings key" "no" "$junk_has_findings"

  # Verify ctdd SKILL.md contains validation instructions for scanner output
  local ctdd_skill_path="$REPO_DIR/skills/ctdd/SKILL.md"
  if [ -f "$ctdd_skill_path" ]; then
    if grep -qF "valid" "$ctdd_skill_path"; then
      echo "  PASS: B-13: ctdd SKILL.md mentions stdout validation"
      PASS=$((PASS + 1))
    else
      echo "  FAIL: B-13: ctdd SKILL.md mentions stdout validation (expected output to contain 'valid')"
      FAIL=$((FAIL + 1))
    fi
  else
    echo "  FAIL: B-13: ctdd SKILL.md missing — cannot verify consumer validation"
    FAIL=$((FAIL + 1))
  fi
}

# ===========================================================================
# R-010 [integration]: ctdd integration
# ===========================================================================

test_r010_ctdd_integration() {
  echo ""
  echo "=== R-010: ctdd integration ==="

  local test_dir="$TMPDIR/r010"

  # (a) Artifact file written to correct path with slug
  setup_git_repo "$test_dir/artifact"
  mkdir -p "$test_dir/artifact/.correctless/artifacts"
  mkdir -p "$test_dir/artifact/.correctless/config"
  cat > "$test_dir/artifact/.correctless/config/workflow-config.json" <<'WEOF'
{"project":{"name":"test"},"workflow":{"intensity":"high"}}
WEOF

  # Add a file with detectable patterns
  cd "$test_dir/artifact" || return
  mkdir -p src
  echo "console.log('debug')" > src/main.ts
  git add src/main.ts
  git commit -q -m "add file"
  cd - >/dev/null || return

  local output
  output="$(run_scanner "$test_dir/artifact" main)"

  # Check that artifact file would be created at slug-based path
  # The branch is feature/test-branch, slug should contain feature-test-branch
  local artifact_dir="$test_dir/artifact/.correctless/artifacts"
  local found_artifact=false
  local artifact_name=""
  for f in "$artifact_dir"/antipattern-findings-*.json; do
    if [ -f "$f" ]; then
      found_artifact=true
      artifact_name="$(basename "$f")"
      break
    fi
  done
  assert_eq "R-010a: Artifact file written with branch slug" "true" "$found_artifact"

  # --- A-08: Assert specific slug in artifact filename ---
  # Branch is feature/test-branch -> slug should be feature-test-branch (with non-alnum replaced by -)
  if [ "$found_artifact" = "true" ]; then
    if echo "$artifact_name" | grep -qF "feature-test-branch"; then
      echo "  PASS: A-08: Artifact filename contains correct slug 'feature-test-branch' ($artifact_name)"
      PASS=$((PASS + 1))
    else
      echo "  FAIL: A-08: Artifact filename missing expected slug 'feature-test-branch' (got '$artifact_name')"
      FAIL=$((FAIL + 1))
    fi
  else
    echo "  FAIL: A-08: Cannot verify slug — no artifact file found"
    FAIL=$((FAIL + 1))
  fi

  # (b) 20-findings-per-file cap
  # Create a file with many detectable patterns (25+ console.log lines)
  setup_git_repo "$test_dir/cap"
  mkdir -p "$test_dir/cap/.correctless/artifacts"
  cd "$test_dir/cap" || return
  mkdir -p src
  {
    for i in $(seq 1 25); do
      echo "console.log('debug $i')"
    done
  } > src/spammy.ts
  git add src/spammy.ts
  git commit -q -m "add spammy file"
  cd - >/dev/null || return

  output="$(run_scanner "$test_dir/cap" main)"
  local spammy_count
  spammy_count="$(echo "$output" | jq '[.findings[] | select(.file | endswith("spammy.ts"))] | length' 2>/dev/null || echo "0")"
  if [ "$spammy_count" -le 20 ]; then
    echo "  PASS: R-010b: 20-findings-per-file cap enforced ($spammy_count findings)"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: R-010b: 20-findings-per-file cap exceeded ($spammy_count findings, expected <=20)"
    FAIL=$((FAIL + 1))
  fi

  # (c) Exclude paths: vendor/, node_modules/
  setup_git_repo "$test_dir/exclude"
  cd "$test_dir/exclude" || return
  mkdir -p vendor node_modules src
  echo "console.log('debug')" > vendor/lib.js
  echo "console.log('debug')" > node_modules/pkg.js
  echo "console.log('debug')" > src/main.js
  git add vendor/lib.js node_modules/pkg.js src/main.js
  git commit -q -m "add excluded files"
  cd - >/dev/null || return

  output="$(run_scanner "$test_dir/exclude" main)"
  assert_not_contains "R-010c: vendor/ excluded" "vendor/" "$output"
  assert_not_contains "R-010c: node_modules/ excluded" "node_modules/" "$output"
  assert_contains "R-010c: src/ not excluded" "src/main.js" "$output"

  # --- B-14: generated/ and dist/ exclusion paths ---
  setup_git_repo "$test_dir/exclude-gen-dist"
  cd "$test_dir/exclude-gen-dist" || return
  mkdir -p generated dist src
  echo "console.log('debug')" > generated/foo.js
  echo "console.log('debug')" > dist/bundle.js
  echo "console.log('debug')" > src/app.js
  git add generated/foo.js dist/bundle.js src/app.js
  git commit -q -m "add generated and dist files"
  cd - >/dev/null || return

  output="$(run_scanner "$test_dir/exclude-gen-dist" main)"
  assert_not_contains "B-14: generated/ excluded" "generated/" "$output"
  assert_not_contains "B-14: dist/ excluded" "dist/" "$output"
  assert_contains "B-14: src/ not excluded" "src/app.js" "$output"

  # B-14: antipattern_scan.exclude_paths from config
  setup_git_repo "$test_dir/exclude-config"
  cd "$test_dir/exclude-config" || return
  mkdir -p .correctless/config src custom-vendor
  cat > .correctless/config/workflow-config.json <<'CFGEOF'
{"project":{"name":"test"},"workflow":{"intensity":"high"},"antipattern_scan":{"exclude_paths":["custom-vendor/"]}}
CFGEOF
  echo "console.log('debug')" > custom-vendor/lib.js
  echo "console.log('debug')" > src/app.js
  git add .correctless/config/workflow-config.json custom-vendor/lib.js src/app.js
  git commit -q -m "add config-excluded files"
  cd - >/dev/null || return

  output="$(run_scanner "$test_dir/exclude-config" main)"
  assert_not_contains "B-14: custom-vendor/ excluded via config" "custom-vendor/" "$output"
  assert_contains "B-14: src/ not excluded with config" "src/app.js" "$output"

  # --- B-15: Finding count announcement ---
  setup_git_repo "$test_dir/announcement"
  cd "$test_dir/announcement" || return
  mkdir -p src
  echo "console.log('debug')" > src/main.ts
  git add src/main.ts
  git commit -q -m "add file for announcement"
  cd - >/dev/null || return

  run_scanner_with_stderr "$test_dir/announcement" main
  # The announcement "Deterministic scan found {N} antipatterns" should appear
  # It could be on stdout or stderr — check the combined output
  local combined_output="$SCANNER_STDOUT $SCANNER_STDERR"
  assert_contains "B-15: Announcement contains 'Deterministic scan found'" \
    "Deterministic scan found" "$combined_output"

  # --- B-16: "+N more" summary message ---
  # Reuse the spammy file from R-010b (25 console.log lines)
  output="$(run_scanner "$test_dir/cap" main)"
  assert_contains "B-16: Output contains '+N more in' summary" "more in" "$output"
}

# ===========================================================================
# R-011 [integration]: cverify SKILL.md references antipattern scan
# ===========================================================================

test_r011_cverify_skill_reference() {
  echo ""
  echo "=== R-011: cverify SKILL.md contains antipattern scan instructions ==="

  local cverify_skill="$REPO_DIR/skills/cverify/SKILL.md"

  if [ ! -f "$cverify_skill" ]; then
    echo "  FAIL: R-011: cverify SKILL.md does not exist at $cverify_skill"
    FAIL=$((FAIL + 1))
    return
  fi

  # Must contain instructions to invoke the scanner
  if grep -qF "antipattern-scan" "$cverify_skill"; then
    echo "  PASS: R-011: cverify references antipattern-scan.sh"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: R-011: cverify references antipattern-scan.sh (expected output to contain 'antipattern-scan')"
    FAIL=$((FAIL + 1))
  fi

  # Must contain instructions for "Antipattern Scan" section
  if grep -qF "Antipattern Scan" "$cverify_skill"; then
    echo "  PASS: R-011: cverify references 'Antipattern Scan' section"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: R-011: cverify references 'Antipattern Scan' section (expected output to contain 'Antipattern Scan')"
    FAIL=$((FAIL + 1))
  fi
}

# ===========================================================================
# R-012 [unit]: Test file identification
# ===========================================================================

test_r012_test_file_identification() {
  echo ""
  echo "=== R-012: Test file identification ==="

  local test_dir="$TMPDIR/r012"

  # Test files should skip debug checks — console.log in test file should NOT be flagged
  setup_git_repo "$test_dir/test-skip-debug" \
    "src/main.test.ts:console.log('test helper output')"

  local output
  output="$(run_scanner "$test_dir/test-skip-debug" main)"
  assert_no_finding_with_pattern "R-012: console.log in .test.ts not flagged" "console-debug" "$output"

  # Non-test files should skip assertion checks — expect(true) in non-test should NOT be flagged
  setup_git_repo "$test_dir/non-test-skip-assert" \
    "src/main.ts:expect(true).toBe(true)"

  output="$(run_scanner "$test_dir/non-test-skip-assert" main)"
  assert_no_finding_with_pattern "R-012: expect(true) in non-test not flagged" "trivial-assertion" "$output"

  # Test fallback patterns: *.spec.js
  setup_git_repo "$test_dir/spec-js" \
    "src/main.spec.js:console.log('spec helper')"

  output="$(run_scanner "$test_dir/spec-js" main)"
  assert_no_finding_with_pattern "R-012: console.log in .spec.js not flagged" "console-debug" "$output"

  # Test fallback patterns: test_*.py
  setup_git_repo "$test_dir/test-py" \
    "src/test_main.py:print('test output')"

  output="$(run_scanner "$test_dir/test-py" main)"
  assert_no_finding_with_pattern "R-012: print() in test_*.py not flagged" "debug-print" "$output"

  # Test fallback patterns: *_test.go
  setup_git_repo "$test_dir/test-go" \
    "src/main_test.go:fmt.Println(\"test output\")"

  output="$(run_scanner "$test_dir/test-go" main)"
  assert_no_finding_with_pattern "R-012: fmt.Println in *_test.go not flagged" "debug-print" "$output"

  # Trivial assertion ONLY flagged in test files
  setup_git_repo "$test_dir/trivial-in-test" \
    "src/main.test.ts:expect(true).toBe(true)"

  output="$(run_scanner "$test_dir/trivial-in-test" main)"
  assert_finding_with_pattern "R-012: expect(true) flagged in .test.ts" "trivial-assertion" "$output"

  # --- B-17: Missing test file patterns ---

  # *_test.rs (Rust test file) — debug print should not be flagged
  setup_git_repo "$test_dir/test-rs" \
    'src/main_test.rs:println!("test output");'

  output="$(run_scanner "$test_dir/test-rs" main)"
  assert_no_finding_with_pattern "B-17: println! in *_test.rs not flagged" "debug-print" "$output"

  # __tests__/foo.js (directory pattern) — console.log should not be flagged
  setup_git_repo "$test_dir/tests-dir-js"
  cd "$test_dir/tests-dir-js" || return
  mkdir -p src/__tests__
  echo "console.log('test helper')" > src/__tests__/foo.js
  git add src/__tests__/foo.js
  git commit -q -m "add __tests__ file"
  cd - >/dev/null || return

  output="$(run_scanner "$test_dir/tests-dir-js" main)"
  assert_no_finding_with_pattern "B-17: console.log in __tests__/foo.js not flagged" "console-debug" "$output"

  # tests/foo.py (directory pattern) — print should not be flagged
  setup_git_repo "$test_dir/tests-dir-py"
  cd "$test_dir/tests-dir-py" || return
  mkdir -p tests
  echo "print('test output')" > tests/foo.py
  git add tests/foo.py
  git commit -q -m "add tests/ file"
  cd - >/dev/null || return

  output="$(run_scanner "$test_dir/tests-dir-py" main)"
  assert_no_finding_with_pattern "B-17: print() in tests/foo.py not flagged" "debug-print" "$output"

  # --- B-18: patterns.test_file config integration ---
  setup_git_repo "$test_dir/custom-test-pattern"
  cd "$test_dir/custom-test-pattern" || return
  mkdir -p .correctless/config src
  # Configure a custom test file pattern
  cat > .correctless/config/workflow-config.json <<'CFGEOF'
{"project":{"name":"test"},"workflow":{"intensity":"high"},"patterns":{"test_file":"*_check.ts"}}
CFGEOF
  echo "console.log('helper')" > src/main_check.ts
  git add .correctless/config/workflow-config.json src/main_check.ts
  git commit -q -m "add custom test pattern"
  cd - >/dev/null || return

  output="$(run_scanner "$test_dir/custom-test-pattern" main)"
  # main_check.ts matches the custom pattern — console.log should NOT be flagged
  assert_no_finding_with_pattern "B-18: Custom patterns.test_file skips debug check" "console-debug" "$output"
}

# ===========================================================================
# R-013 [unit]: Severity mapping
# ===========================================================================

test_r013_severity_mapping() {
  echo ""
  echo "=== R-013: Severity mapping ==="

  local test_dir="$TMPDIR/r013"

  # Empty catch -> HIGH
  setup_git_repo "$test_dir/high" \
    "src/main.ts:try { foo() } catch(e) { }"

  local output
  output="$(run_scanner "$test_dir/high" main)"
  assert_finding_severity "R-013: empty-catch is high severity" "empty-catch" "high" "$output"

  # console.log -> MEDIUM
  setup_git_repo "$test_dir/medium" \
    "src/main.ts:console.log('debug')"

  output="$(run_scanner "$test_dir/medium" main)"
  assert_finding_severity "R-013: console-debug is medium severity" "console-debug" "medium" "$output"

  # TODO -> LOW
  setup_git_repo "$test_dir/low" \
    "src/main.py:# TODO fix this"

  output="$(run_scanner "$test_dir/low" main)"
  assert_finding_severity "R-013: todo-comment is low severity" "todo-comment" "low" "$output"

  # Placeholder -> HIGH
  setup_git_repo "$test_dir/placeholder" \
    "src/config.ts:const key = 'changeme'"

  output="$(run_scanner "$test_dir/placeholder" main)"
  assert_finding_severity "R-013: placeholder is high severity" "placeholder" "high" "$output"

  # Trivial assertion -> LOW
  setup_git_repo "$test_dir/trivial" \
    "src/main.test.ts:expect(true).toBe(true)"

  output="$(run_scanner "$test_dir/trivial" main)"
  assert_finding_severity "R-013: trivial-assertion is low severity" "trivial-assertion" "low" "$output"

  # Excessive any -> MEDIUM
  setup_git_repo "$test_dir/any" \
    "src/main.ts:const a = x as any; const b = y as any; const c = z as any; const d = w as any;"

  output="$(run_scanner "$test_dir/any" main)"
  assert_finding_severity "R-013: excessive-any is medium severity" "excessive-any" "medium" "$output"

  # Excessive unwrap -> MEDIUM
  setup_git_repo "$test_dir/unwrap" \
    "src/main.rs:let a = x.unwrap(); let b = y.unwrap(); let c = z.unwrap(); let d = w.unwrap();"

  output="$(run_scanner "$test_dir/unwrap" main)"
  assert_finding_severity "R-013: excessive-unwrap is medium severity" "excessive-unwrap" "medium" "$output"

  # --- A-09: Missing severity tests for R-007a (error-suppression) and R-008c (todo!()) ---

  # R-007a: error-suppression in .sh -> HIGH
  setup_git_repo "$test_dir/shell-err-supp" \
    "src/deploy.sh:some_command || true"

  output="$(run_scanner "$test_dir/shell-err-supp" main)"
  assert_finding_severity "A-09: error-suppression is high severity (R-007a)" "error-suppression" "high" "$output"

  # R-008c: todo!() macro in .rs -> LOW
  setup_git_repo "$test_dir/rust-todo" \
    "src/main.rs:todo!()"

  output="$(run_scanner "$test_dir/rust-todo" main)"
  assert_finding_severity "A-09: todo!() macro is low severity (R-008c)" "todo-macro" "low" "$output"

  # --- QA-013 class fix: debug-echo severity is LOW (R-007b) ---
  setup_git_repo "$test_dir/debug-echo-sev" \
    "src/run.sh:echo \"some debug output\""

  output="$(run_scanner "$test_dir/debug-echo-sev" main)"
  assert_finding_severity "QA-013: debug-echo is low severity (R-007b)" "debug-echo" "low" "$output"
}

# ===========================================================================
# R-014 [integration]: Checklist file and skill references
# ===========================================================================

test_r014_checklist_and_references() {
  echo ""
  echo "=== R-014: Checklist file and skill references ==="

  # (a) Checklist file must exist
  local checklist="$REPO_DIR/.correctless/checklists/ai-antipatterns.md"
  if [ -f "$checklist" ]; then
    echo "  PASS: R-014a: ai-antipatterns.md exists"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: R-014a: ai-antipatterns.md does not exist at $checklist"
    FAIL=$((FAIL + 1))
  fi

  # (b) Checklist contains required semantic patterns
  if [ -f "$checklist" ]; then
    # A-10: Tightened checklist content assertions — match specific pattern names, not loose substrings
    local -a required_patterns=("disconnected middleware" "scope creep" "over-abstraction" "mock-testing-the-mock" "happy-path-only" "silently removed safety guards")
    for pattern in "${required_patterns[@]}"; do
      if grep -qF "$pattern" "$checklist"; then
        echo "  PASS: R-014b: Checklist mentions $pattern"
        PASS=$((PASS + 1))
      else
        echo "  FAIL: R-014b: Checklist mentions $pattern (expected output to contain '$pattern')"
        FAIL=$((FAIL + 1))
      fi
    done
  else
    # Skip sub-tests if file missing — already counted as FAIL above
    for _ in 1 2 3 4 5 6; do
      echo "  FAIL: R-014b: (skipped — checklist file missing)"
      FAIL=$((FAIL + 1))
    done
  fi

  # (c) ctdd SKILL.md references the checklist
  local ctdd_skill="$REPO_DIR/skills/ctdd/SKILL.md"
  if [ -f "$ctdd_skill" ]; then
    if grep -qF "ai-antipatterns" "$ctdd_skill"; then
      echo "  PASS: R-014c: ctdd references checklist"
      PASS=$((PASS + 1))
    else
      echo "  FAIL: R-014c: ctdd references checklist (expected output to contain 'ai-antipatterns')"
      FAIL=$((FAIL + 1))
    fi
  else
    echo "  FAIL: R-014c: ctdd SKILL.md missing"
    FAIL=$((FAIL + 1))
  fi

  # (d) creview SKILL.md references the checklist
  local creview_skill="$REPO_DIR/skills/creview/SKILL.md"
  if [ -f "$creview_skill" ]; then
    if grep -qF "ai-antipatterns" "$creview_skill"; then
      echo "  PASS: R-014d: creview references checklist"
      PASS=$((PASS + 1))
    else
      echo "  FAIL: R-014d: creview references checklist (expected output to contain 'ai-antipatterns')"
      FAIL=$((FAIL + 1))
    fi
  else
    echo "  FAIL: R-014d: creview SKILL.md missing"
    FAIL=$((FAIL + 1))
  fi

  # (e) cverify SKILL.md references the checklist
  local cverify_skill="$REPO_DIR/skills/cverify/SKILL.md"
  if [ -f "$cverify_skill" ]; then
    if grep -qF "ai-antipatterns" "$cverify_skill"; then
      echo "  PASS: R-014e: cverify references checklist"
      PASS=$((PASS + 1))
    else
      echo "  FAIL: R-014e: cverify references checklist (expected output to contain 'ai-antipatterns')"
      FAIL=$((FAIL + 1))
    fi
  else
    echo "  FAIL: R-014e: cverify SKILL.md missing"
    FAIL=$((FAIL + 1))
  fi
}

# ===========================================================================
# R-015 [unit]: No grep -P or grep -z in script
# ===========================================================================

test_r015_posix_grep_only() {
  echo ""
  echo "=== R-015: No grep -P or grep -z in scanner script ==="

  if [ ! -f "$SCANNER" ]; then
    echo "  FAIL: R-015: Scanner script does not exist at $SCANNER"
    FAIL=$((FAIL + 1))
    return
  fi

  # Check no grep -P (use grep directly on file, not echo+pipe)
  if grep -qE 'grep\s+.*-[a-zA-Z]*P' "$SCANNER"; then
    echo "  FAIL: R-015: Scanner uses grep -P (PCRE) — prohibited"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: R-015: No grep -P found"
    PASS=$((PASS + 1))
  fi

  # Check no grep -z
  if grep -qE 'grep\s+.*-[a-zA-Z]*z' "$SCANNER"; then
    echo "  FAIL: R-015: Scanner uses grep -z (NUL delimiter) — prohibited"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: R-015: No grep -z found"
    PASS=$((PASS + 1))
  fi

  # --- A-11: Additional prohibited grep variants ---

  # grep --perl-regexp (long form of -P)
  if grep -qF 'grep --perl-regexp' "$SCANNER"; then
    echo "  FAIL: A-11: Scanner uses grep --perl-regexp — prohibited"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: A-11: No grep --perl-regexp found"
    PASS=$((PASS + 1))
  fi

  # grep --null-data (long form of -z)
  if grep -qF 'grep --null-data' "$SCANNER"; then
    echo "  FAIL: A-11: Scanner uses grep --null-data — prohibited"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: A-11: No grep --null-data found"
    PASS=$((PASS + 1))
  fi

  # --- QA-003/QA-012 class fix: No non-POSIX ERE sequences in grep patterns ---
  # Check for \s, \b, \w, \d, \B, \W, \D — all GNU extensions, not POSIX ERE
  local non_posix_found=false
  for seq in '\\s' '\\b' '\\w' '\\d' '\\B' '\\W' '\\D'; do
    if grep -E "grep.*$seq" "$SCANNER" | grep -vq '^[[:space:]]*#'; then
      echo "  FAIL: QA-012: Scanner uses $seq in grep patterns (not POSIX ERE)"
      FAIL=$((FAIL + 1))
      non_posix_found=true
    fi
  done
  if [ "$non_posix_found" = false ]; then
    echo "  PASS: QA-012: No non-POSIX ERE sequences (\\s \\b \\w \\d \\B \\W \\D) in grep patterns"
    PASS=$((PASS + 1))
  fi
}

# ===========================================================================
# R-016 [integration]: Script location and sync.sh inclusion
# ===========================================================================

test_r016_script_location_and_sync() {
  echo ""
  echo "=== R-016: Script location and sync.sh inclusion ==="

  # (a) Script lives at scripts/antipattern-scan.sh, NOT in hooks/
  if [ -f "$REPO_DIR/scripts/antipattern-scan.sh" ]; then
    echo "  PASS: R-016a: Script at scripts/antipattern-scan.sh"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: R-016a: Script NOT at scripts/antipattern-scan.sh"
    FAIL=$((FAIL + 1))
  fi

  if [ -f "$REPO_DIR/hooks/antipattern-scan.sh" ]; then
    echo "  FAIL: R-016a: Script incorrectly placed in hooks/"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: R-016a: Script not in hooks/ (correct)"
    PASS=$((PASS + 1))
  fi

  # (b) sync.sh includes scripts/ directory
  local sync_file="$REPO_DIR/sync.sh"
  if [ -f "$sync_file" ]; then
    if grep -qF "scripts/" "$sync_file"; then
      echo "  PASS: R-016b: sync.sh includes scripts/ directory"
      PASS=$((PASS + 1))
    else
      echo "  FAIL: R-016b: sync.sh includes scripts/ directory (expected output to contain 'scripts/')"
      FAIL=$((FAIL + 1))
    fi
  else
    echo "  FAIL: R-016b: sync.sh does not exist"
    FAIL=$((FAIL + 1))
  fi
}

# ===========================================================================
# R-017 [integration]: JSON injection resistance
# ===========================================================================

test_r017_json_injection_resistance() {
  echo ""
  echo "=== R-017: JSON injection resistance ==="

  local test_dir="$TMPDIR/r017"

  # Create a file with content that tries to inject into JSON
  local injection_payload='console.log("debug"); // "}, {"severity": "critical", "description": "INJECTED"'
  setup_git_repo "$test_dir/inject" \
    "src/evil.ts:$injection_payload"

  local output
  output="$(run_scanner "$test_dir/inject" main)"

  # Output must be valid JSON
  assert_json_valid "R-017: Output is valid JSON despite injection attempt" "$output"

  # Must not contain injected finding
  assert_not_contains "R-017: No injected severity=critical" '"severity": "critical"' "$output"
  assert_not_contains "R-017: No INJECTED description" "INJECTED" "$output"

  # More aggressive injection: file content as a valid JSON fragment
  local injection2='}, {"id": "EVIL", "severity": "critical", "pattern": "pwned", "file": "/etc/passwd", "line": 1, "description": "HACKED", "category": "rce"'
  setup_git_repo "$test_dir/inject2"
  cd "$test_dir/inject2" || return
  mkdir -p src
  printf 'const x = "%s";\nconsole.log(x);\n' "$injection2" > src/pwn.ts
  git add src/pwn.ts
  git commit -q -m "add injection"
  cd - >/dev/null || return

  output="$(run_scanner "$test_dir/inject2" main)"
  assert_json_valid "R-017: Output valid JSON despite aggressive injection" "$output"
  assert_not_contains "R-017: No EVIL id injected" '"id": "EVIL"' "$output"
  assert_not_contains "R-017: No HACKED description injected" "HACKED" "$output"

  # --- B-19: JSON injection via filenames ---
  setup_git_repo "$test_dir/evil-filename"
  cd "$test_dir/evil-filename" || return
  mkdir -p src
  # Create a file with JSON metacharacters in the name
  # Use a double-quote in the filename to try to break JSON
  local evil_name='src/evil"name.js'
  echo "console.log('debug')" > "$evil_name"
  git add "$evil_name"
  git commit -q -m "add evil filename"
  cd - >/dev/null || return

  output="$(run_scanner "$test_dir/evil-filename" main)"
  assert_json_valid "B-19: Output JSON valid despite metachar filename" "$output"
  # The filename should appear correctly escaped in the JSON
  local file_field
  file_field="$(echo "$output" | jq -r '.findings[0].file // .errors[0] // empty' 2>/dev/null)"
  if [ -n "$file_field" ]; then
    echo "  PASS: B-19: Filename with metacharacters handled in JSON"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: B-19: Filename with metacharacters not found in output"
    FAIL=$((FAIL + 1))
  fi
}

# ===========================================================================
# R-018 [unit]: Universal placeholder detection (non-code files)
# ===========================================================================

test_r018_universal_placeholder_detection() {
  echo ""
  echo "=== R-018: Universal placeholder detection ==="

  local test_dir="$TMPDIR/r018"

  # .yml with changeme
  setup_git_repo "$test_dir/yml" \
    "config/app.yml:api_key: changeme"

  local output
  output="$(run_scanner "$test_dir/yml" main)"
  assert_finding_with_pattern "R-018: changeme in .yml detected" "placeholder" "$output"

  # .json with changeme
  setup_git_repo "$test_dir/json"
  cd "$test_dir/json" || return
  mkdir -p config
  printf '{"api_key": "changeme"}\n' > config/settings.json
  git add config/settings.json
  git commit -q -m "add json config"
  cd - >/dev/null || return

  output="$(run_scanner "$test_dir/json" main)"
  assert_finding_with_pattern "R-018: changeme in .json detected" "placeholder" "$output"

  # .env with changeme
  setup_git_repo "$test_dir/env" \
    ".env.example:SECRET_KEY=changeme"

  output="$(run_scanner "$test_dir/env" main)"
  assert_finding_with_pattern "R-018: changeme in .env detected" "placeholder" "$output"

  # .toml with REPLACE_ME
  setup_git_repo "$test_dir/toml" \
    "config/app.toml:api_key = \"REPLACE_ME\""

  output="$(run_scanner "$test_dir/toml" main)"
  assert_finding_with_pattern "R-018: REPLACE_ME in .toml detected" "placeholder" "$output"

  # .xml with your-api-key
  setup_git_repo "$test_dir/xml" \
    "config/app.xml:<api-key>your-api-key</api-key>"

  output="$(run_scanner "$test_dir/xml" main)"
  assert_finding_with_pattern "R-018: your-api-key in .xml detected" "placeholder" "$output"

  # --- A-12: Missing config extension tests (.cfg, .ini, .yaml) ---

  # .cfg with changeme
  setup_git_repo "$test_dir/cfg" \
    "config/app.cfg:password = changeme"

  output="$(run_scanner "$test_dir/cfg" main)"
  assert_finding_with_pattern "A-12: changeme in .cfg detected" "placeholder" "$output"

  # .ini with REPLACE_ME
  setup_git_repo "$test_dir/ini" \
    "config/app.ini:api_token = REPLACE_ME"

  output="$(run_scanner "$test_dir/ini" main)"
  assert_finding_with_pattern "A-12: REPLACE_ME in .ini detected" "placeholder" "$output"

  # .yaml with your-api-key
  setup_git_repo "$test_dir/yaml" \
    "config/app.yaml:api_key: your-api-key"

  output="$(run_scanner "$test_dir/yaml" main)"
  assert_finding_with_pattern "A-12: your-api-key in .yaml detected" "placeholder" "$output"
}

# ===========================================================================
# R-019 [unit]: Shared lib.sh with branch_slug()
# ===========================================================================

test_r019_shared_lib() {
  echo ""
  echo "=== R-019: Shared lib.sh with branch_slug() ==="

  # (a) scripts/lib.sh exists
  if [ -f "$LIB" ]; then
    echo "  PASS: R-019a: scripts/lib.sh exists"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: R-019a: scripts/lib.sh does not exist"
    FAIL=$((FAIL + 1))
  fi

  # (b) lib.sh contains branch_slug()
  if [ -f "$LIB" ]; then
    if grep -qF "branch_slug" "$LIB"; then
      echo "  PASS: R-019b: lib.sh contains branch_slug()"
      PASS=$((PASS + 1))
    else
      echo "  FAIL: R-019b: lib.sh contains branch_slug() (expected output to contain 'branch_slug')"
      FAIL=$((FAIL + 1))
    fi
  else
    echo "  FAIL: R-019b: (skipped — lib.sh missing)"
    FAIL=$((FAIL + 1))
  fi

  # (c) hooks/workflow-advance.sh sources lib.sh
  local wf_advance="$REPO_DIR/hooks/workflow-advance.sh"
  if [ -f "$wf_advance" ]; then
    if grep -qF "lib.sh" "$wf_advance"; then
      echo "  PASS: R-019c: workflow-advance.sh sources lib.sh"
      PASS=$((PASS + 1))
    else
      echo "  FAIL: R-019c: workflow-advance.sh sources lib.sh (expected output to contain 'lib.sh')"
      FAIL=$((FAIL + 1))
    fi
  else
    echo "  FAIL: R-019c: workflow-advance.sh does not exist"
    FAIL=$((FAIL + 1))
  fi

  # (d) antipattern-scan.sh sources lib.sh
  if [ -f "$SCANNER" ]; then
    if grep -qF "lib.sh" "$SCANNER"; then
      echo "  PASS: R-019d: antipattern-scan.sh sources lib.sh"
      PASS=$((PASS + 1))
    else
      echo "  FAIL: R-019d: antipattern-scan.sh sources lib.sh (expected output to contain 'lib.sh')"
      FAIL=$((FAIL + 1))
    fi
  else
    echo "  FAIL: R-019d: antipattern-scan.sh does not exist"
    FAIL=$((FAIL + 1))
  fi

  # --- A-13: branch_slug() behavior test ---
  # Source lib.sh and call branch_slug() directly to verify slug computation
  if [ -f "$LIB" ]; then
    # Test 1: feature/my-cool-feature -> feature-my-cool-feature
    local slug_result
    slug_result="$(bash -c "source '$LIB' && echo 'feature/my-cool-feature' | { read -r b; branch=\$b; echo \"\${branch//[^a-zA-Z0-9]/-}\"; }" 2>/dev/null || echo "")"
    # We can't call branch_slug() directly since it reads git branch, so test the function
    # by checking if lib.sh defines it and verifying the transformation logic
    # Actually source and override git to test the function:
    slug_result="$(bash -c "
      git() { echo 'feature/my-cool-feature'; }
      export -f git
      source '$LIB'
      branch_slug
    " 2>/dev/null || echo "")"
    if echo "$slug_result" | grep -qF "feature-my-cool-feature"; then
      echo "  PASS: A-13: branch_slug('feature/my-cool-feature') contains 'feature-my-cool-feature'"
      PASS=$((PASS + 1))
    else
      echo "  FAIL: A-13: branch_slug('feature/my-cool-feature') expected to contain 'feature-my-cool-feature' (got '$slug_result')"
      FAIL=$((FAIL + 1))
    fi

    # Test 2: fix/bug#123 -> special chars replaced
    slug_result="$(bash -c "
      git() { echo 'fix/bug#123'; }
      export -f git
      source '$LIB'
      branch_slug
    " 2>/dev/null || echo "")"
    if echo "$slug_result" | grep -qE '^fix-bug-123'; then
      echo "  PASS: A-13: branch_slug('fix/bug#123') has special chars replaced"
      PASS=$((PASS + 1))
    else
      echo "  FAIL: A-13: branch_slug('fix/bug#123') expected special chars replaced (got '$slug_result')"
      FAIL=$((FAIL + 1))
    fi
  else
    echo "  FAIL: A-13: lib.sh missing — cannot test branch_slug() behavior"
    FAIL=$((FAIL + 1))
    echo "  FAIL: A-13: lib.sh missing — cannot test branch_slug() behavior (test 2)"
    FAIL=$((FAIL + 1))
  fi

  # (e) branch_slug() is NOT duplicated — workflow-advance.sh should NOT define its own
  # After extraction, workflow-advance.sh should source lib.sh, not define branch_slug locally
  if [ -f "$wf_advance" ]; then
    local slug_def_count
    slug_def_count="$(grep -c 'branch_slug()' "$wf_advance" 2>/dev/null)" || slug_def_count=0
    # After refactoring, it should source lib.sh and NOT define branch_slug() locally
    # It currently defines it — this test ensures the extraction happens
    if grep -q 'source.*lib\.sh' "$wf_advance" && [ "$slug_def_count" -le 0 ]; then
      echo "  PASS: R-019e: branch_slug() not duplicated in workflow-advance.sh"
      PASS=$((PASS + 1))
    else
      echo "  FAIL: R-019e: branch_slug() still defined locally in workflow-advance.sh (expected source from lib.sh)"
      FAIL=$((FAIL + 1))
    fi
  else
    echo "  FAIL: R-019e: (skipped — workflow-advance.sh missing)"
    FAIL=$((FAIL + 1))
  fi
}

# ---------------------------------------------------------------------------
# Run all tests
# ---------------------------------------------------------------------------

echo "=== Running all antipattern scanner tests ==="

test_r001_git_diff_file_detection
test_r002_extension_routing
test_r003_json_output_format
test_r004_js_ts_checks
test_r005_python_checks
test_r006_go_checks
test_r007_shell_checks
test_r008_rust_checks
test_r009_robustness
test_r010_ctdd_integration
test_r011_cverify_skill_reference
test_r012_test_file_identification
test_r013_severity_mapping
test_r014_checklist_and_references
test_r015_posix_grep_only
test_r016_script_location_and_sync
test_r017_json_injection_resistance
test_r018_universal_placeholder_detection
test_r019_shared_lib

# ---------------------------------------------------------------------------
# AP-014: jq -s on JSONL detection
# ---------------------------------------------------------------------------

test_ap014_jq_slurp_jsonl() {
  echo ""
  echo "=== AP-014: jq -s on JSONL detection ==="

  # (a) Pattern metadata exists in scanner
  local has_pattern="no"
  if grep -q 'jq-slurp-jsonl' "$SCANNER" 2>/dev/null; then
    has_pattern="yes"
  fi
  assert_eq "AP-014(a): jq-slurp-jsonl pattern registered in scanner" "yes" "$has_pattern"

  # (b) The grep pattern in check_shell() catches jq -s usage
  local test_content='usage=$(jq -s "[.[] | .total_tokens] | add" "$LOG_FILE")'
  local matches_slurp="no"
  if echo "$test_content" | grep -qE 'jq[[:space:]]+(--slurp|-s[[:space:]])'; then
    matches_slurp="yes"
  fi
  assert_eq "AP-014(b): grep pattern catches 'jq -s' usage" "yes" "$matches_slurp"

  # (b2) Pattern also catches --slurp form
  local test_content2='usage=$(jq --slurp "[.[] | .total_tokens]" "$LOG_FILE")'
  local matches_longform="no"
  if echo "$test_content2" | grep -qE 'jq[[:space:]]+(--slurp|-s[[:space:]])'; then
    matches_longform="yes"
  fi
  assert_eq "AP-014(b2): grep pattern catches 'jq --slurp' usage" "yes" "$matches_longform"

  # (b3) Pattern does NOT match jq -r (safe pattern)
  local test_safe='usage=$(jq -R "try (fromjson)" "$LOG_FILE")'
  local false_positive="no"
  if echo "$test_safe" | grep -qE 'jq[[:space:]]+(--slurp|-s[[:space:]])'; then
    false_positive="yes"
  fi
  assert_eq "AP-014(b3): grep pattern does not match 'jq -R' (safe)" "no" "$false_positive"

  # (c) Antipatterns.md has AP-014 entry
  local has_entry="no"
  if grep -q 'AP-014' "$REPO_DIR/.correctless/antipatterns.md" 2>/dev/null; then
    has_entry="yes"
  fi
  assert_eq "AP-014(c): AP-014 entry exists in antipatterns.md" "yes" "$has_entry"
}
test_ap014_jq_slurp_jsonl

# ===========================================================================
# Scanner-Expansion Spec Tests
# Tests R-001 through R-011 from .correctless/specs/scanner-expansion.md
# ===========================================================================

# ===========================================================================
# SE-R-001 [unit]: check_shell() detects grep -P in .sh files
# ===========================================================================

test_se_r001_grep_p_detection() {
  echo ""
  echo "=== SE-R-001: check_shell() detects grep -P ==="

  local test_dir="$TMPDIR/se-r001"

  # (a) grep -P in a .sh file -> produces gnu-grep-p finding with high severity
  setup_git_repo "$test_dir/grep-p"
  cd "$test_dir/grep-p" || return
  mkdir -p src
  cat > src/scanner.sh <<'EOF'
#!/usr/bin/env bash
result=$(grep -P '\d+' somefile.txt)
EOF
  git add src/scanner.sh
  git commit -q -m "add grep -P script"
  cd - >/dev/null || return

  local output
  output="$(run_scanner "$test_dir/grep-p" main)"
  assert_finding_with_pattern "SE-R-001a: grep -P detected" "gnu-grep-p" "$output"
  assert_finding_severity "SE-R-001a: gnu-grep-p severity is high" "gnu-grep-p" "high" "$output"

  # (b) grep -oP variant
  setup_git_repo "$test_dir/grep-op"
  cd "$test_dir/grep-op" || return
  mkdir -p src
  cat > src/extract.sh <<'EOF'
#!/usr/bin/env bash
val=$(grep -oP 'HOOK_TYPE=\K.*' settings.json)
EOF
  git add src/extract.sh
  git commit -q -m "add grep -oP script"
  cd - >/dev/null || return

  output="$(run_scanner "$test_dir/grep-op" main)"
  assert_finding_with_pattern "SE-R-001b: grep -oP detected" "gnu-grep-p" "$output"

  # (c) grep -E (POSIX ERE) should NOT be flagged
  setup_git_repo "$test_dir/grep-e"
  cd "$test_dir/grep-e" || return
  mkdir -p src
  cat > src/safe.sh <<'EOF'
#!/usr/bin/env bash
result=$(grep -E '[[:digit:]]+' somefile.txt)
EOF
  git add src/safe.sh
  git commit -q -m "add grep -E script"
  cd - >/dev/null || return

  output="$(run_scanner "$test_dir/grep-e" main)"
  assert_no_finding_with_pattern "SE-R-001c: grep -E not flagged" "gnu-grep-p" "$output"

  # (d) Non-.sh files should not be scanned for grep -P
  setup_git_repo "$test_dir/grep-p-py"
  cd "$test_dir/grep-p-py" || return
  mkdir -p src
  cat > src/script.py <<'EOF'
import subprocess
result = subprocess.run(["grep", "-P", "\\d+", "file.txt"])
EOF
  git add src/script.py
  git commit -q -m "add python file with grep -P"
  cd - >/dev/null || return

  output="$(run_scanner "$test_dir/grep-p-py" main)"
  assert_no_finding_with_pattern "SE-R-001d: grep -P in .py not flagged as gnu-grep-p" "gnu-grep-p" "$output"
}

# ===========================================================================
# SE-R-002 [unit]: check_shell() detects \s, \w, \d, \b in grep patterns
# ===========================================================================

test_se_r002_gnu_grep_ext_detection() {
  echo ""
  echo "=== SE-R-002: check_shell() detects GNU grep extensions ==="

  local test_dir="$TMPDIR/se-r002"

  # (a) \s in grep pattern -> gnu-grep-ext, medium severity
  setup_git_repo "$test_dir/backslash-s"
  cd "$test_dir/backslash-s" || return
  mkdir -p src
  cat > 'src/check.sh' <<'SEOF'
#!/usr/bin/env bash
grep -E '\s+' somefile.txt
SEOF
  git add src/check.sh
  git commit -q -m "add backslash-s script"
  cd - >/dev/null || return

  local output
  output="$(run_scanner "$test_dir/backslash-s" main)"
  assert_finding_with_pattern "SE-R-002a: \\s in grep detected" "gnu-grep-ext" "$output"
  assert_finding_severity "SE-R-002a: gnu-grep-ext severity is medium" "gnu-grep-ext" "medium" "$output"

  # (b) \w in grep pattern -> gnu-grep-ext, medium severity
  setup_git_repo "$test_dir/backslash-w"
  cd "$test_dir/backslash-w" || return
  mkdir -p src
  cat > 'src/check.sh' <<'WEOF'
#!/usr/bin/env bash
grep -E '\w+' somefile.txt
WEOF
  git add src/check.sh
  git commit -q -m "add backslash-w script"
  cd - >/dev/null || return

  output="$(run_scanner "$test_dir/backslash-w" main)"
  assert_finding_with_pattern "SE-R-002b: \\w in grep detected" "gnu-grep-ext" "$output"

  # (c) \d in grep pattern -> gnu-grep-ext, medium severity
  setup_git_repo "$test_dir/backslash-d"
  cd "$test_dir/backslash-d" || return
  mkdir -p src
  cat > 'src/check.sh' <<'DEOF'
#!/usr/bin/env bash
grep -E '\d+' somefile.txt
DEOF
  git add src/check.sh
  git commit -q -m "add backslash-d script"
  cd - >/dev/null || return

  output="$(run_scanner "$test_dir/backslash-d" main)"
  assert_finding_with_pattern "SE-R-002c: \\d in grep detected" "gnu-grep-ext" "$output"

  # (d) \b in grep pattern -> gnu-grep-ext-low, low severity
  setup_git_repo "$test_dir/backslash-b"
  cd "$test_dir/backslash-b" || return
  mkdir -p src
  cat > 'src/check.sh' <<'BEOF'
#!/usr/bin/env bash
grep -E '\bword\b' somefile.txt
BEOF
  git add src/check.sh
  git commit -q -m "add backslash-b script"
  cd - >/dev/null || return

  output="$(run_scanner "$test_dir/backslash-b" main)"
  assert_finding_with_pattern "SE-R-002d: \\b in grep detected" "gnu-grep-ext-low" "$output"
  assert_finding_severity "SE-R-002d: gnu-grep-ext-low severity is low" "gnu-grep-ext-low" "low" "$output"

  # (e) Line-scoped POSIX exclusion: \s with [[:space:]] on same line -> suppressed
  setup_git_repo "$test_dir/posix-exclusion"
  cd "$test_dir/posix-exclusion" || return
  mkdir -p src
  cat > 'src/safe.sh' <<'PEEOF'
#!/usr/bin/env bash
# Uses both \s and its POSIX equivalent on the same line
grep -E '\s[[:space:]]' somefile.txt
PEEOF
  git add src/safe.sh
  git commit -q -m "add posix exclusion script"
  cd - >/dev/null || return

  output="$(run_scanner "$test_dir/posix-exclusion" main)"
  assert_no_finding_with_pattern "SE-R-002e: \\s suppressed when [[:space:]] on same line" "gnu-grep-ext" "$output"

  # (f) \w with [[:alnum:]] on same line -> suppressed
  setup_git_repo "$test_dir/alnum-exclusion"
  cd "$test_dir/alnum-exclusion" || return
  mkdir -p src
  cat > 'src/safe.sh' <<'AEEOF'
#!/usr/bin/env bash
grep -E '\w[[:alnum:]]' somefile.txt
AEEOF
  git add src/safe.sh
  git commit -q -m "add alnum exclusion script"
  cd - >/dev/null || return

  output="$(run_scanner "$test_dir/alnum-exclusion" main)"
  assert_no_finding_with_pattern "SE-R-002f: \\w suppressed when [[:alnum:]] on same line" "gnu-grep-ext" "$output"

  # (g) \d with [[:digit:]] on same line -> suppressed
  setup_git_repo "$test_dir/digit-exclusion"
  cd "$test_dir/digit-exclusion" || return
  mkdir -p src
  cat > 'src/safe.sh' <<'DGEOF'
#!/usr/bin/env bash
grep -E '\d[[:digit:]]' somefile.txt
DGEOF
  git add src/safe.sh
  git commit -q -m "add digit exclusion script"
  cd - >/dev/null || return

  output="$(run_scanner "$test_dir/digit-exclusion" main)"
  assert_no_finding_with_pattern "SE-R-002g: \\d suppressed when [[:digit:]] on same line" "gnu-grep-ext" "$output"

  # (h) \b with grep -w on same line -> suppressed
  setup_git_repo "$test_dir/w-exclusion"
  cd "$test_dir/w-exclusion" || return
  mkdir -p src
  cat > 'src/safe.sh' <<'GWEOF'
#!/usr/bin/env bash
grep -w '\bword' somefile.txt
GWEOF
  git add src/safe.sh
  git commit -q -m "add grep -w exclusion script"
  cd - >/dev/null || return

  output="$(run_scanner "$test_dir/w-exclusion" main)"
  assert_no_finding_with_pattern "SE-R-002h: \\b suppressed when grep -w on same line" "gnu-grep-ext-low" "$output"

  # (i) \s in sed/awk context -> NOT flagged (out of scope per R-002)
  setup_git_repo "$test_dir/sed-context"
  cd "$test_dir/sed-context" || return
  mkdir -p src
  cat > 'src/transform.sh' <<'SDEOF'
#!/usr/bin/env bash
sed 's/\s\+/ /g' somefile.txt
SDEOF
  git add src/transform.sh
  git commit -q -m "add sed script"
  cd - >/dev/null || return

  output="$(run_scanner "$test_dir/sed-context" main)"
  assert_no_finding_with_pattern "SE-R-002i: \\s in sed not flagged" "gnu-grep-ext" "$output"
}

# ===========================================================================
# SE-R-003 [unit]: PATTERN_META entries for new pattern IDs
# ===========================================================================

test_se_r003_pattern_meta_entries() {
  echo ""
  echo "=== SE-R-003: PATTERN_META entries for new pattern IDs ==="

  # Check that PATTERN_META contains entries for all new pattern IDs.
  # Uses quoted form "pattern-id" to avoid substring false positives (e.g., gnu-grep-ext vs gnu-grep-ext-low).
  local has_grep_p="no"
  grep -qF '"gnu-grep-p"' "$SCANNER" 2>/dev/null && has_grep_p="yes"
  assert_eq "SE-R-003a: PATTERN_META has gnu-grep-p" "yes" "$has_grep_p"

  local has_grep_ext="no"
  grep -qF '"gnu-grep-ext"' "$SCANNER" 2>/dev/null && has_grep_ext="yes"
  assert_eq "SE-R-003b: PATTERN_META has gnu-grep-ext" "yes" "$has_grep_ext"

  local has_grep_ext_low="no"
  grep -qF '"gnu-grep-ext-low"' "$SCANNER" 2>/dev/null && has_grep_ext_low="yes"
  assert_eq "SE-R-003c: PATTERN_META has gnu-grep-ext-low" "yes" "$has_grep_ext_low"

  local has_dead_fn="no"
  grep -qF '"dead-security-fn"' "$SCANNER" 2>/dev/null && has_dead_fn="yes"
  assert_eq "SE-R-003d: PATTERN_META has dead-security-fn" "yes" "$has_dead_fn"

  # Verify severity values via running the scanner with fixtures
  local test_dir="$TMPDIR/se-r003"

  # gnu-grep-p severity = high
  setup_git_repo "$test_dir/meta-grep-p"
  cd "$test_dir/meta-grep-p" || return
  mkdir -p src
  cat > src/test.sh <<'EOF'
#!/usr/bin/env bash
grep -P '\d+' file.txt
EOF
  git add src/test.sh
  git commit -q -m "add"
  cd - >/dev/null || return

  local output
  output="$(run_scanner "$test_dir/meta-grep-p" main)"
  assert_finding_severity "SE-R-003a: gnu-grep-p severity is high" "gnu-grep-p" "high" "$output"

  # Verify category for gnu-grep-p is portability
  local grep_p_cat
  grep_p_cat="$(echo "$output" | jq -r '.findings[] | select(.pattern == "gnu-grep-p") | .category' 2>/dev/null | head -1)"
  assert_eq "SE-R-003a: gnu-grep-p category is portability" "portability" "$grep_p_cat"

  # Verify PATTERN_META entry for dead-security-fn contains security-enforcement category
  local dead_fn_has_cat="no"
  grep -q 'dead-security-fn.*security-enforcement' "$SCANNER" 2>/dev/null && dead_fn_has_cat="yes"
  assert_eq "SE-R-003d: dead-security-fn category contains security-enforcement" "yes" "$dead_fn_has_cat"
}

# ===========================================================================
# SE-R-004 [unit]: check_dead_security_calls() function exists and detects dead fns
# ===========================================================================

test_se_r004_dead_security_calls() {
  echo ""
  echo "=== SE-R-004: check_dead_security_calls() detects dead security functions ==="

  # (a) Function exists in scanner
  local has_fn="no"
  grep -q 'check_dead_security_calls' "$SCANNER" 2>/dev/null && has_fn="yes"
  assert_eq "SE-R-004a: check_dead_security_calls() exists in scanner" "yes" "$has_fn"

  # (b) Functional test: security script with dead function
  local test_dir="$TMPDIR/se-r004"
  setup_git_repo "$test_dir/dead-fn"
  cd "$test_dir/dead-fn" || return

  # Create a security script matching R-004 path patterns (override-*.sh)
  mkdir -p scripts hooks
  cat > scripts/override-scrutiny.sh <<'EOF'
#!/usr/bin/env bash
# A security script with a dead function

check_override_retry() {
  echo "checking override retry"
  return 0
}

cmd_override() {
  echo "override command"
  # Note: check_override_retry is NOT called here
}

cmd_override "$@"
EOF

  # Create a test file that calls the dead function (but NOT a production file)
  mkdir -p tests
  cat > tests/test-override.sh <<'EOF'
#!/usr/bin/env bash
source scripts/override-scrutiny.sh
check_override_retry  # called from test, not production
EOF

  # Create a production hook that does NOT call check_override_retry
  cat > hooks/workflow-gate.sh <<'EOF'
#!/usr/bin/env bash
source scripts/override-scrutiny.sh
cmd_override "$@"
EOF

  git add scripts/override-scrutiny.sh tests/test-override.sh hooks/workflow-gate.sh
  git commit -q -m "add security script with dead function"
  cd - >/dev/null || return

  local output
  output="$(run_scanner "$test_dir/dead-fn" main)"
  assert_finding_with_pattern "SE-R-004b: dead security function detected" "dead-security-fn" "$output"
  assert_finding_severity "SE-R-004b: dead-security-fn severity is high" "dead-security-fn" "high" "$output"

  # (c) Function that IS called from production -> NOT flagged
  setup_git_repo "$test_dir/live-fn"
  cd "$test_dir/live-fn" || return

  mkdir -p scripts hooks
  cat > scripts/override-scrutiny.sh <<'EOF'
#!/usr/bin/env bash
check_override_retry() {
  echo "checking override retry"
  return 0
}

cmd_override() {
  check_override_retry
  echo "override command"
}
EOF

  cat > hooks/workflow-gate.sh <<'EOF'
#!/usr/bin/env bash
source scripts/override-scrutiny.sh
cmd_override "$@"
EOF

  git add scripts/override-scrutiny.sh hooks/workflow-gate.sh
  git commit -q -m "add security script with live function"
  cd - >/dev/null || return

  output="$(run_scanner "$test_dir/live-fn" main)"
  assert_no_finding_with_pattern "SE-R-004c: live security function not flagged" "dead-security-fn" "$output"

  # (d) Script tagged with "# scanner: security" -> scanned for dead functions
  setup_git_repo "$test_dir/tagged-security"
  cd "$test_dir/tagged-security" || return

  mkdir -p scripts
  cat > scripts/custom-check.sh <<'EOF'
#!/usr/bin/env bash
# scanner: security
# Custom security check

dead_guard() {
  echo "I'm never called from production"
}

active_guard() {
  echo "I'm called from production"
}
EOF

  # Production caller for active_guard only
  cat > scripts/auto-policy.sh <<'EOF'
#!/usr/bin/env bash
source scripts/custom-check.sh
active_guard
EOF

  git add scripts/custom-check.sh scripts/auto-policy.sh
  git commit -q -m "add tagged security script"
  cd - >/dev/null || return

  output="$(run_scanner "$test_dir/tagged-security" main)"
  assert_finding_with_pattern "SE-R-004d: dead fn in tagged security script detected" "dead-security-fn" "$output"

  # (e) Script tagged with "# scanner: library" -> excluded from dead-call scanning
  setup_git_repo "$test_dir/tagged-library"
  cd "$test_dir/tagged-library" || return

  mkdir -p scripts
  cat > scripts/lib-utils.sh <<'EOF'
#!/usr/bin/env bash
# scanner: library
# Library functions called by LLM skill orchestrators

helper_fn() {
  echo "called by skills, not bash scripts"
}
EOF

  # Create a skill file that references this library
  mkdir -p skills/ctdd
  cat > skills/ctdd/SKILL.md <<'EOF'
---
name: ctdd
---
Source lib-utils.sh for helper functions.
EOF

  git add scripts/lib-utils.sh skills/ctdd/SKILL.md
  git commit -q -m "add library-tagged script"
  cd - >/dev/null || return

  output="$(run_scanner "$test_dir/tagged-library" main)"
  assert_no_finding_with_pattern "SE-R-004e: library-tagged script excluded" "dead-security-fn" "$output"

  # (f) Library-tagged script NOT referenced by any skill -> still flagged
  setup_git_repo "$test_dir/orphan-library"
  cd "$test_dir/orphan-library" || return

  mkdir -p scripts
  cat > scripts/orphan-lib.sh <<'EOF'
#!/usr/bin/env bash
# scanner: library
# Library with no skill reference

orphan_fn() {
  echo "nobody references this library"
}
EOF

  git add scripts/orphan-lib.sh
  git commit -q -m "add orphan library script"
  cd - >/dev/null || return

  output="$(run_scanner "$test_dir/orphan-library" main)"
  assert_finding_with_pattern "SE-R-004f: orphan library script flagged" "dead-security-fn" "$output"

  # (g) Hooks/ excluded from security-script scanning
  setup_git_repo "$test_dir/hooks-excluded"
  cd "$test_dir/hooks-excluded" || return

  mkdir -p hooks
  cat > hooks/workflow-gate.sh <<'EOF'
#!/usr/bin/env bash
internal_check() {
  echo "this is a hook-internal function"
}
EOF

  git add hooks/workflow-gate.sh
  git commit -q -m "add hook with internal function"
  cd - >/dev/null || return

  output="$(run_scanner "$test_dir/hooks-excluded" main)"
  assert_no_finding_with_pattern "SE-R-004g: hooks/ internal functions not flagged" "dead-security-fn" "$output"

  # (h) function name { } syntax (not just name() { })
  setup_git_repo "$test_dir/function-keyword"
  cd "$test_dir/function-keyword" || return

  mkdir -p scripts
  cat > scripts/workflow-gate.sh <<'EOF'
#!/usr/bin/env bash
function dead_function {
  echo "dead"
}

function live_function {
  echo "live"
}
EOF

  cat > scripts/auto-policy.sh <<'EOF'
#!/usr/bin/env bash
source scripts/workflow-gate.sh
live_function
EOF

  git add scripts/workflow-gate.sh scripts/auto-policy.sh
  git commit -q -m "add function keyword syntax"
  cd - >/dev/null || return

  output="$(run_scanner "$test_dir/function-keyword" main)"
  assert_finding_with_pattern "SE-R-004h: dead 'function name {' syntax detected" "dead-security-fn" "$output"

  # (i) Finding description is from PATTERN_META, NOT includes function name (TB-002)
  output="$(run_scanner "$test_dir/dead-fn" main)"
  local desc
  desc="$(echo "$output" | jq -r '.findings[] | select(.pattern == "dead-security-fn") | .description' 2>/dev/null | head -1)"
  if [ -n "$desc" ]; then
    # Description should NOT contain the actual function name (TB-002)
    assert_not_contains "SE-R-004i: finding description does not contain function name" "check_override_retry" "$desc"
  else
    echo "  FAIL: SE-R-004i: no dead-security-fn finding to check description"
    FAIL=$((FAIL + 1))
  fi
}

# ===========================================================================
# SE-R-005 [unit]: check_dead_security_calls() excludes pluggable/callback functions
# ===========================================================================

test_se_r005_pluggable_exclusion() {
  echo ""
  echo "=== SE-R-005: Pluggable/callback functions excluded ==="

  local test_dir="$TMPDIR/se-r005"

  # (a) _default_ prefix excluded
  setup_git_repo "$test_dir/default-prefix"
  cd "$test_dir/default-prefix" || return

  mkdir -p scripts
  cat > scripts/workflow-gate.sh <<'EOF'
#!/usr/bin/env bash
_default_handler() {
  echo "pluggable default handler"
}
EOF

  git add scripts/workflow-gate.sh
  git commit -q -m "add default prefix function"
  cd - >/dev/null || return

  local output
  output="$(run_scanner "$test_dir/default-prefix" main)"
  assert_no_finding_with_pattern "SE-R-005a: _default_ prefix function excluded" "dead-security-fn" "$output"

  # (b) "pluggable" comment on definition line excluded
  setup_git_repo "$test_dir/pluggable-comment"
  cd "$test_dir/pluggable-comment" || return

  mkdir -p scripts
  cat > scripts/workflow-gate.sh <<'EOF'
#!/usr/bin/env bash
custom_handler() { # pluggable
  echo "pluggable handler"
}
EOF

  git add scripts/workflow-gate.sh
  git commit -q -m "add pluggable comment function"
  cd - >/dev/null || return

  output="$(run_scanner "$test_dir/pluggable-comment" main)"
  assert_no_finding_with_pattern "SE-R-005b: pluggable-comment function excluded" "dead-security-fn" "$output"

  # (c) "callback" comment on definition line excluded
  setup_git_repo "$test_dir/callback-comment"
  cd "$test_dir/callback-comment" || return

  mkdir -p scripts
  cat > scripts/workflow-gate.sh <<'EOF'
#!/usr/bin/env bash
on_complete() { # callback
  echo "callback handler"
}
EOF

  git add scripts/workflow-gate.sh
  git commit -q -m "add callback comment function"
  cd - >/dev/null || return

  output="$(run_scanner "$test_dir/callback-comment" main)"
  assert_no_finding_with_pattern "SE-R-005c: callback-comment function excluded" "dead-security-fn" "$output"

  # (d) Non-pluggable dead function IS still flagged (control case)
  setup_git_repo "$test_dir/not-pluggable"
  cd "$test_dir/not-pluggable" || return

  mkdir -p scripts
  cat > scripts/workflow-gate.sh <<'EOF'
#!/usr/bin/env bash
normal_dead_fn() {
  echo "I have no pluggable/callback marker"
}
EOF

  git add scripts/workflow-gate.sh
  git commit -q -m "add normal dead function"
  cd - >/dev/null || return

  output="$(run_scanner "$test_dir/not-pluggable" main)"
  assert_finding_with_pattern "SE-R-005d: non-pluggable dead function still flagged" "dead-security-fn" "$output"
}

# ===========================================================================
# SE-R-007 [integration]: Full scanner run with all three new pattern IDs
# ===========================================================================

test_se_r007_integration_all_patterns() {
  echo ""
  echo "=== SE-R-007: Integration test with all three new pattern IDs ==="

  local test_dir="$TMPDIR/se-r007"

  setup_git_repo "$test_dir/all-patterns"
  cd "$test_dir/all-patterns" || return

  # (a) File with grep -P -> gnu-grep-p
  mkdir -p src scripts hooks tests
  cat > src/grep-p-file.sh <<'EOF'
#!/usr/bin/env bash
grep -P '\d+' somefile.txt
EOF

  # (b) File with \s in grep pattern -> gnu-grep-ext
  cat > src/grep-ext-file.sh <<'EOF'
#!/usr/bin/env bash
grep -E '\s+' somefile.txt
EOF

  # (c) Security script with dead function called only from test -> dead-security-fn
  cat > scripts/review-triage.sh <<'EOF'
#!/usr/bin/env bash
dead_enforce_fn() {
  echo "this function is never called from production"
}

active_fn() {
  echo "this function is called"
}
EOF

  # Test file calls dead_enforce_fn (but tests don't count as production)
  cat > tests/test-review.sh <<'EOF'
#!/usr/bin/env bash
source scripts/review-triage.sh
dead_enforce_fn  # called from test, not production
active_fn
EOF

  # Production file only calls active_fn
  cat > scripts/auto-policy.sh <<'EOF'
#!/usr/bin/env bash
source scripts/review-triage.sh
active_fn
EOF

  git add src/ scripts/ tests/
  git commit -q -m "add all pattern fixtures"
  cd - >/dev/null || return

  local output
  output="$(run_scanner "$test_dir/all-patterns" main)"
  assert_json_valid "SE-R-007: Output is valid JSON" "$output"

  # All three new pattern IDs should appear
  assert_finding_with_pattern "SE-R-007a: gnu-grep-p found" "gnu-grep-p" "$output"
  assert_finding_with_pattern "SE-R-007b: gnu-grep-ext found" "gnu-grep-ext" "$output"
  assert_finding_with_pattern "SE-R-007c: dead-security-fn found" "dead-security-fn" "$output"
}

# ===========================================================================
# SE-R-008 [unit]: ctdd SKILL.md test audit check 8 (production call chain)
# ===========================================================================

test_se_r008_ctdd_check8() {
  echo ""
  echo "=== SE-R-008: ctdd SKILL.md audit check 8 (production call chain) ==="

  local ctdd_skill="$REPO_DIR/skills/ctdd/SKILL.md"

  # (a) Check 8 exists as a numbered item in the test auditor blockquote
  local has_check8="no"
  grep -q '^> 8\.' "$ctdd_skill" 2>/dev/null && has_check8="yes"
  assert_eq "SE-R-008a: ctdd SKILL.md has numbered check '> 8.'" "yes" "$has_check8"

  # (b) Check 8 text contains "production call chain"
  local check8_line
  check8_line="$(grep -A 3 '^> 8\.' "$ctdd_skill" 2>/dev/null)"

  local has_anchor="no"
  echo "$check8_line" | grep -qi 'production call chain' && has_anchor="yes"
  assert_eq "SE-R-008b: check 8 contains 'production call chain' anchor" "yes" "$has_anchor"

  # (c) Check 8 text mentions dead-code-in-security-paths
  local has_dead_code="no"
  echo "$check8_line" | grep -qi 'dead-code-in-security\|dead.code.in.security' && has_dead_code="yes"
  assert_eq "SE-R-008c: check 8 mentions dead-code-in-security-paths" "yes" "$has_dead_code"

  # (d) Check 8 mentions "called from" or "invoked by" detection
  local has_detection="no"
  echo "$check8_line" | grep -qi 'called from\|invoked by' && has_detection="yes"
  assert_eq "SE-R-008d: check 8 mentions 'called from' or 'invoked by'" "yes" "$has_detection"
}

# ===========================================================================
# SE-R-009 [unit]: Content-pairing drift test for dead-security-fn
# (in tests/test-test-evasion-antipatterns.sh — tested separately)
# We verify here that the three assertions listed in R-009 hold:
# ===========================================================================

test_se_r009_drift_test() {
  echo ""
  echo "=== SE-R-009: Drift test for dead-security-fn pairing ==="

  local ctdd_skill="$REPO_DIR/skills/ctdd/SKILL.md"

  # (1) ctdd audit blockquote has a numbered check with anchor phrase "production call chain"
  # Pipe-into-grep-q is SIGPIPE-prone under `set -uo pipefail` (this file): the
  # first grep emits multiple lines; grep -qi exits on first match and SIGPIPEs
  # the first grep; pipeline exits 141; && silently doesn't fire. Use herestring
  # to avoid the pipe entirely. (AP-031 deferred follow-up #3 / PR #151.)
  local has_prod_chain="no"
  local numbered_blockquote_lines
  numbered_blockquote_lines="$(grep -E '^> [0-9]+\.' "$ctdd_skill" 2>/dev/null || true)"
  grep -qi 'production call chain' <<< "$numbered_blockquote_lines" && has_prod_chain="yes"
  assert_eq "SE-R-009(1): audit check with 'production call chain' exists" "yes" "$has_prod_chain"

  # (2) PATTERN_META contains key dead-security-fn
  local has_pattern="no"
  grep -q 'dead-security-fn' "$SCANNER" 2>/dev/null && has_pattern="yes"
  assert_eq "SE-R-009(2): PATTERN_META has dead-security-fn" "yes" "$has_pattern"

  # (3) ctdd audit blockquote contains literal string "dead-security-fn"
  local has_literal="no"
  grep -q 'dead-security-fn' "$ctdd_skill" 2>/dev/null && has_literal="yes"
  assert_eq "SE-R-009(3): ctdd audit contains 'dead-security-fn'" "yes" "$has_literal"
}

# ===========================================================================
# SE-R-010 [unit]: AP-001 entry in antipatterns.md updated
# ===========================================================================

test_se_r010_ap001_update() {
  echo ""
  echo "=== SE-R-010: AP-001 antipatterns.md entry updated ==="

  local antipatterns="$REPO_DIR/.correctless/antipatterns.md"

  # (a) Frequency field references 2026-04-12 audit
  local ap001_block
  ap001_block="$(sed -n '/### AP-001/,/### AP-002/p' "$antipatterns" 2>/dev/null)"

  local has_audit_ref="no"
  echo "$ap001_block" | grep -qi '2026-04-12\|49.*occurrences\|49+\|5 test files' && has_audit_ref="yes"
  assert_eq "SE-R-010a: AP-001 Frequency references 2026-04-12 audit data" "yes" "$has_audit_ref"

  # (b) How to catch it references scanner enforcement
  local has_scanner_ref="no"
  echo "$ap001_block" | grep -qi 'antipattern-scan\|check_shell\|gnu-grep-p\|gnu-grep-ext' && has_scanner_ref="yes"
  assert_eq "SE-R-010b: AP-001 How-to-catch references scanner enforcement" "yes" "$has_scanner_ref"
}

# ===========================================================================
# SE-R-011 [unit]: AP-022 (or next slot) entry for dead code in security paths
# ===========================================================================

test_se_r011_ap022_entry() {
  echo ""
  echo "=== SE-R-011: AP-022 entry for dead code in security paths ==="

  local antipatterns="$REPO_DIR/.correctless/antipatterns.md"

  # (a) A new AP entry for "Dead code in security paths" exists
  local has_heading="no"
  grep -qi 'AP-0[0-9][0-9]:.*[Dd]ead.*code.*security\|AP-0[0-9][0-9]:.*[Dd]ead.*security.*path' "$antipatterns" 2>/dev/null && has_heading="yes"
  assert_eq "SE-R-011a: AP entry for dead code in security paths exists" "yes" "$has_heading"

  # (b) Entry mentions check_override_retry as the canonical example
  local entry_block
  # Find the block — try AP-022 first, fall back to scanning for the heading
  entry_block="$(sed -n '/[Dd]ead.*code.*security\|[Dd]ead.*security.*path/,/### AP-/p' "$antipatterns" 2>/dev/null)"
  if [ -z "$entry_block" ]; then
    entry_block="$(sed -n '/[Dd]ead.*code.*security\|[Dd]ead.*security.*path/,$ p' "$antipatterns" 2>/dev/null)"
  fi

  local has_example="no"
  echo "$entry_block" | grep -q 'check_override_retry' && has_example="yes"
  assert_eq "SE-R-011b: Entry mentions check_override_retry" "yes" "$has_example"

  # (c) Entry references the scanner enforcement
  local has_scanner="no"
  echo "$entry_block" | grep -qi 'antipattern-scan\|check_dead_security_calls\|dead-security-fn' && has_scanner="yes"
  assert_eq "SE-R-011c: Entry references scanner enforcement" "yes" "$has_scanner"

  # (d) Entry has standard fields
  local has_what="no"
  echo "$entry_block" | grep -q '\*\*What went wrong\*\*' && has_what="yes"
  assert_eq "SE-R-011d: Entry has What went wrong field" "yes" "$has_what"

  local has_how="no"
  echo "$entry_block" | grep -q '\*\*How to catch it\*\*' && has_how="yes"
  assert_eq "SE-R-011d: Entry has How to catch it field" "yes" "$has_how"

  local has_freq="no"
  echo "$entry_block" | grep -q '\*\*Frequency\*\*' && has_freq="yes"
  assert_eq "SE-R-011d: Entry has Frequency field" "yes" "$has_freq"

  # (e) Entry mentions PRH-006
  local has_prh="no"
  echo "$entry_block" | grep -q 'PRH-006' && has_prh="yes"
  assert_eq "SE-R-011e: Entry mentions PRH-006" "yes" "$has_prh"

  # (f) Entry mentions ctdd check 8 as advisory
  local has_advisory="no"
  echo "$entry_block" | grep -qi 'check 8\|audit.*production call chain\|advisory' && has_advisory="yes"
  assert_eq "SE-R-011f: Entry mentions advisory backstop" "yes" "$has_advisory"
}

# Run all scanner-expansion tests
test_se_r001_grep_p_detection
test_se_r002_gnu_grep_ext_detection
test_se_r003_pattern_meta_entries
test_se_r004_dead_security_calls
test_se_r005_pluggable_exclusion
test_se_r007_integration_all_patterns
test_se_r008_ctdd_check8
test_se_r009_drift_test
test_se_r010_ap001_update
test_se_r011_ap022_entry

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
