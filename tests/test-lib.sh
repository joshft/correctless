#!/usr/bin/env bash
# shellcheck disable=SC1090  # Dynamic source path (LIB_SH) always resolves to scripts/lib.sh
# Correctless — lib.sh Unit Tests
# Tests R-001 through R-014 from the lib.sh decomposition spec.
# These test EXISTING functions that should work correctly against current code.
# Run from repo root: bash tests/test-lib.sh

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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
    echo "  FAIL: $desc (expected output NOT to match pattern '$pattern', got '$actual')"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  fi
}

assert_exit() {
  local desc="$1" expected_exit="$2"
  shift 2
  local actual_exit
  "$@" >/dev/null 2>&1 && actual_exit=0 || actual_exit=$?
  assert_eq "$desc" "$expected_exit" "$actual_exit"
}

# ============================================================================
# Test environment setup — temp git repo for branch_slug and repo_root tests
# ============================================================================

TEST_DIR="/tmp/correctless-test-lib-$$"

setup_git_repo() {
  rm -rf "$TEST_DIR"
  mkdir -p "$TEST_DIR"
  cd "$TEST_DIR" || exit 1
  git init -q
  git branch -M main
  echo "init" > README.md
  git add -A && git commit -q -m "init"

  # Copy lib.sh into the test project so repo_root resolves correctly
  mkdir -p scripts
  cp "$LIB_SH" scripts/lib.sh
}

cleanup() {
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

echo "Correctless lib.sh Unit Tests"
echo "=============================="

# ============================================================================
# R-001 [unit]: branch_slug on normal branch — filesystem-safe, hash suffix
# ============================================================================

test_branch_slug_normal() {
  echo ""
  echo "=== R-001: branch_slug produces filesystem-safe output ==="

  setup_git_repo
  git checkout -q -b feature/foo-bar

  source scripts/lib.sh
  local result
  result="$(branch_slug)"

  # Must contain only [a-zA-Z0-9-]
  assert_match "R-001a: only contains safe chars" '^[a-zA-Z0-9-]+$' "$result"

  # Must end with a 6-character hash suffix separated by hyphen
  # Pattern: anything-6alphanum at end
  assert_match "R-001b: ends with 6-char hash suffix" '-[a-f0-9]{6}$' "$result"

  # Sanity: result is non-empty
  if [ -n "$result" ]; then
    echo "  PASS: R-001c: branch_slug returned non-empty: $result"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: R-001c: branch_slug returned empty string"
    FAIL=$((FAIL + 1))
  fi
}

# ============================================================================
# R-002 [unit]: branch_slug replaces non-alphanumeric with hyphens,
#   different original names produce different hashes
# ============================================================================

test_branch_slug_hash_from_original() {
  echo ""
  echo "=== R-002: branch_slug hashes from original branch name ==="

  setup_git_repo

  # Get slug for feature/foo-bar
  git checkout -q -b feature/foo-bar
  source scripts/lib.sh
  unset _CORRECTLESS_REPO_ROOT _CORRECTLESS_CONFIG_FILE _CORRECTLESS_ARTIFACTS_DIR
  local slug1
  slug1="$(branch_slug)"

  # Get slug for feature/foo_bar (different original, same after naive slug)
  git checkout -q -b feature/foo_bar
  local slug2
  slug2="$(branch_slug)"

  # Both should have non-alphanumeric replaced by hyphens
  assert_match "R-002a: feature/foo-bar slug has hyphens" '^feature-foo-bar-' "$slug1"
  assert_match "R-002b: feature/foo_bar slug has hyphens" '^feature-foo-bar-' "$slug2"

  # But the hash suffixes must differ (hash is from original name)
  local hash1 hash2
  hash1="${slug1##*-}"
  hash2="${slug2##*-}"
  if [ "$hash1" != "$hash2" ]; then
    echo "  PASS: R-002c: different original names produce different hashes ($hash1 vs $hash2)"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: R-002c: expected different hashes for feature/foo-bar vs feature/foo_bar (both got $hash1)"
    FAIL=$((FAIL + 1))
  fi
}

# ============================================================================
# R-003 [unit]: branch_slug truncates at 80 characters
# ============================================================================

test_branch_slug_truncation() {
  echo ""
  echo "=== R-003: branch_slug truncates long branch names ==="

  setup_git_repo

  # Create a very long branch name (>80 chars when slugified)
  local long_branch
  long_branch="feature/$(printf 'a%.0s' {1..100})"
  git checkout -q -b "$long_branch"

  source scripts/lib.sh
  unset _CORRECTLESS_REPO_ROOT _CORRECTLESS_CONFIG_FILE _CORRECTLESS_ARTIFACTS_DIR
  local result
  result="$(branch_slug)"

  # The slug portion (before the final -hash) should be at most 80 chars
  # Total format: slug-hash where hash is 6 chars
  # So total length should be at most 80 + 1 (hyphen) + 6 (hash) = 87
  local total_len=${#result}
  if [ "$total_len" -le 87 ]; then
    echo "  PASS: R-003a: total length $total_len is within limit (max 87 = 80 slug + 1 hyphen + 6 hash)"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: R-003a: total length $total_len exceeds limit of 87 (got: $result)"
    FAIL=$((FAIL + 1))
  fi

  # The slug portion specifically is at most 80 chars
  # Extract everything except the trailing -hash (last 7 chars: hyphen + 6 hex)
  local slug_part="${result:0:$((${#result} - 7))}"
  local slug_len=${#slug_part}
  if [ "$slug_len" -le 80 ]; then
    echo "  PASS: R-003b: slug portion length $slug_len is <= 80"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: R-003b: slug portion length $slug_len exceeds 80"
    FAIL=$((FAIL + 1))
  fi
}

# ============================================================================
# R-004 [unit]: branch_slug on detached HEAD prints error and returns 1
# ============================================================================

test_branch_slug_detached_head() {
  echo ""
  echo "=== R-004: branch_slug fails on detached HEAD ==="

  setup_git_repo

  # Detach HEAD
  git checkout -q --detach HEAD

  source scripts/lib.sh
  unset _CORRECTLESS_REPO_ROOT _CORRECTLESS_CONFIG_FILE _CORRECTLESS_ARTIFACTS_DIR

  local exit_code stderr_output
  stderr_output="$(branch_slug 2>&1 >/dev/null)" && exit_code=0 || exit_code=$?

  assert_eq "R-004a: exit code is 1" "1" "$exit_code"
  assert_contains "R-004b: error message on stderr" "error" "$stderr_output"
}

# ============================================================================
# R-005 [unit]: repo_root returns absolute path, cached
# ============================================================================

test_repo_root() {
  echo ""
  echo "=== R-005: repo_root returns absolute path and caches ==="

  setup_git_repo
  source scripts/lib.sh
  unset _CORRECTLESS_REPO_ROOT

  local result
  result="$(repo_root)"

  # Must be an absolute path
  assert_match "R-005a: repo_root returns absolute path" '^/' "$result"

  # Should point to our test dir (the git root)
  assert_eq "R-005b: repo_root matches test dir" "$TEST_DIR" "$result"

  # Cache: calling again should return same result
  local result2
  result2="$(repo_root)"
  assert_eq "R-005c: repo_root is consistent" "$result" "$result2"

  # Unsetting cache variable clears it
  unset _CORRECTLESS_REPO_ROOT
  local result3
  result3="$(repo_root)"
  assert_eq "R-005d: repo_root after cache clear matches" "$result" "$result3"
}

# ============================================================================
# R-006 [unit]: config_file returns correct path, cached
# ============================================================================

test_config_file() {
  echo ""
  echo "=== R-006: config_file returns correct path and caches ==="

  setup_git_repo
  source scripts/lib.sh
  unset _CORRECTLESS_REPO_ROOT _CORRECTLESS_CONFIG_FILE

  local result expected
  result="$(config_file)"
  expected="$TEST_DIR/.correctless/config/workflow-config.json"

  assert_eq "R-006a: config_file returns correct path" "$expected" "$result"

  # Cache: unsetting clears
  unset _CORRECTLESS_CONFIG_FILE
  local result2
  result2="$(config_file)"
  assert_eq "R-006b: config_file after cache clear" "$expected" "$result2"
}

# ============================================================================
# R-007 [unit]: artifacts_dir returns correct path, cached
# ============================================================================

test_artifacts_dir() {
  echo ""
  echo "=== R-007: artifacts_dir returns correct path and caches ==="

  setup_git_repo
  source scripts/lib.sh
  unset _CORRECTLESS_REPO_ROOT _CORRECTLESS_ARTIFACTS_DIR

  local result expected
  result="$(artifacts_dir)"
  expected="$TEST_DIR/.correctless/artifacts"

  assert_eq "R-007a: artifacts_dir returns correct path" "$expected" "$result"

  # Cache: unsetting clears
  unset _CORRECTLESS_ARTIFACTS_DIR
  local result2
  result2="$(artifacts_dir)"
  assert_eq "R-007b: artifacts_dir after cache clear" "$expected" "$result2"
}

# ============================================================================
# R-008 [unit]: classify_file returns "test" for test pattern matches
#   basename patterns match filename, path patterns match full path
# ============================================================================

test_classify_file_test() {
  echo ""
  echo "=== R-008: classify_file returns test for test patterns ==="

  source "$LIB_SH"

  # Basename-only pattern (no /)
  TEST_PATTERN="*.test.ts|*.spec.ts"
  SOURCE_PATTERN="*.ts|*.js"

  local result

  # Basename match
  result="$(classify_file "src/app.test.ts")"
  assert_eq "R-008a: basename test pattern matches" "test" "$result"

  result="$(classify_file "src/deep/nested/thing.spec.ts")"
  assert_eq "R-008b: basename test pattern matches nested" "test" "$result"

  # Path pattern with /
  TEST_PATTERN="tests/*.sh|*.test.ts"
  SOURCE_PATTERN="*.sh|*.ts"

  result="$(classify_file "tests/run.sh")"
  assert_eq "R-008c: path test pattern matches full path" "test" "$result"

  # Path pattern should NOT match if path does not match
  result="$(classify_file "src/run.sh")"
  # src/run.sh does NOT match tests/*.sh but DOES match *.sh source pattern
  assert_eq "R-008d: path test pattern does not match wrong dir" "source" "$result"
}

# ============================================================================
# R-009 [unit]: classify_file returns "source" when matching source but not test
#   test patterns take priority
# ============================================================================

test_classify_file_source_priority() {
  echo ""
  echo "=== R-009: classify_file test priority over source ==="

  source "$LIB_SH"

  TEST_PATTERN="*.test.ts|*.spec.ts"
  SOURCE_PATTERN="*.ts|*.js"

  # A .ts file that is not a test
  local result
  result="$(classify_file "src/service.ts")"
  assert_eq "R-009a: source file classified as source" "source" "$result"

  # A .test.ts file matches BOTH test and source — test wins
  result="$(classify_file "src/service.test.ts")"
  assert_eq "R-009b: test takes priority over source" "test" "$result"

  # A .js file matches source only
  result="$(classify_file "lib/helper.js")"
  assert_eq "R-009c: .js file classified as source" "source" "$result"
}

# ============================================================================
# R-010 [unit]: classify_file returns "other" for non-matching files
# ============================================================================

test_classify_file_other() {
  echo ""
  echo "=== R-010: classify_file returns other for non-matching files ==="

  source "$LIB_SH"

  TEST_PATTERN="*.test.ts|*.spec.ts"
  SOURCE_PATTERN="*.ts|*.js"

  local result

  result="$(classify_file "README.md")"
  assert_eq "R-010a: markdown classified as other" "other" "$result"

  result="$(classify_file ".github/workflows/ci.yml")"
  assert_eq "R-010b: YAML classified as other" "other" "$result"

  result="$(classify_file "Dockerfile")"
  assert_eq "R-010c: Dockerfile classified as other" "other" "$result"
}

# ============================================================================
# R-011 [unit]: classify_file normalizes to lowercase before matching
# ============================================================================

test_classify_file_case_insensitive() {
  echo ""
  echo "=== R-011: classify_file normalizes case ==="

  source "$LIB_SH"

  TEST_PATTERN="*.test.ts"
  SOURCE_PATTERN="*.ts"

  local result

  # Mixed case filename should still match lowercase pattern
  result="$(classify_file "MyTest.TS")"
  assert_eq "R-011a: MyTest.TS matches *.ts pattern" "source" "$result"

  result="$(classify_file "App.Test.TS")"
  assert_eq "R-011b: App.Test.TS matches *.test.ts pattern" "test" "$result"

  result="$(classify_file "UTILS.JS")"
  # *.js is not in source pattern above, but *.ts is
  SOURCE_PATTERN="*.ts|*.js"
  result="$(classify_file "UTILS.JS")"
  assert_eq "R-011c: UTILS.JS matches *.js pattern" "source" "$result"
}

# ============================================================================
# R-012 [unit]: classify_file splits pipe-delimited patterns
# ============================================================================

test_classify_file_pipe_patterns() {
  echo ""
  echo "=== R-012: classify_file splits pipe-delimited patterns ==="

  source "$LIB_SH"

  TEST_PATTERN="*.test.ts|*.spec.ts|*.test.js"
  SOURCE_PATTERN="*.ts|*.js|*.go"

  local result

  # Each sub-pattern should work
  result="$(classify_file "a.test.ts")"
  assert_eq "R-012a: first pipe segment matches" "test" "$result"

  result="$(classify_file "b.spec.ts")"
  assert_eq "R-012b: second pipe segment matches" "test" "$result"

  result="$(classify_file "c.test.js")"
  assert_eq "R-012c: third pipe segment matches" "test" "$result"

  result="$(classify_file "main.go")"
  assert_eq "R-012d: source pipe segment matches" "source" "$result"
}

# ============================================================================
# R-013 [unit]: read_patterns loads from config, returns 1 if missing
# ============================================================================

test_read_patterns() {
  echo ""
  echo "=== R-013: read_patterns loads from config ==="

  setup_git_repo
  source scripts/lib.sh

  # Create a valid config
  mkdir -p .correctless/config
  cat > .correctless/config/workflow-config.json <<'EOF'
{
  "patterns": {
    "test_file": "*.test.ts|*.spec.ts",
    "source_file": "*.ts|*.js"
  }
}
EOF

  # Clear any previous values
  TEST_PATTERN=""
  SOURCE_PATTERN=""

  read_patterns "$TEST_DIR/.correctless/config/workflow-config.json"
  assert_eq "R-013a: TEST_PATTERN loaded" "*.test.ts|*.spec.ts" "$TEST_PATTERN"
  assert_eq "R-013b: SOURCE_PATTERN loaded" "*.ts|*.js" "$SOURCE_PATTERN"

  # Missing config returns 1
  local exit_code
  read_patterns "/tmp/nonexistent-config-$$" >/dev/null 2>&1 && exit_code=0 || exit_code=$?
  assert_eq "R-013c: returns 1 for missing config" "1" "$exit_code"
}

# ============================================================================
# R-014 [unit]: read_intensity returns value from config, defaults to standard
# ============================================================================

test_read_intensity() {
  echo ""
  echo "=== R-014: read_intensity returns intensity or default ==="

  setup_git_repo
  source scripts/lib.sh

  # Config with intensity set
  mkdir -p .correctless/config
  cat > .correctless/config/workflow-config.json <<'EOF'
{
  "workflow": {
    "intensity": "high"
  }
}
EOF

  local result
  result="$(read_intensity "$TEST_DIR/.correctless/config/workflow-config.json")"
  assert_eq "R-014a: reads intensity from config" "high" "$result"

  # Config without intensity field
  cat > .correctless/config/workflow-config.json <<'EOF'
{
  "workflow": {}
}
EOF

  result="$(read_intensity "$TEST_DIR/.correctless/config/workflow-config.json")"
  assert_eq "R-014b: defaults to standard when field absent" "standard" "$result"

  # Missing config file
  result="$(read_intensity "/tmp/nonexistent-config-$$")"
  assert_eq "R-014c: defaults to standard when config missing" "standard" "$result"
}

# ============================================================================
# Run all tests
# ============================================================================

test_branch_slug_normal
test_branch_slug_hash_from_original
test_branch_slug_truncation
test_branch_slug_detached_head
test_repo_root
test_config_file
test_artifacts_dir
test_classify_file_test
test_classify_file_source_priority
test_classify_file_other
test_classify_file_case_insensitive
test_classify_file_pipe_patterns
test_read_patterns
test_read_intensity

# ============================================================================
# Summary
# ============================================================================

echo ""
echo "=============================="
echo "  PASS: $PASS"
echo "  FAIL: $FAIL"
echo "=============================="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
