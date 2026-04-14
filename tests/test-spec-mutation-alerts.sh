#!/usr/bin/env bash
# Correctless — spec mutation alerts tests
# Tests R-001 through R-005 from spec-mutation-alerts spec.
# Verifies spec hashing at review->tests transition, mutation detection
# at done, spec-update re-hash, and missing-file handling.

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="/tmp/correctless-test-spec-mutation-$$"
PASS=0
FAIL=0

# ============================================
# Helpers
# ============================================

setup_test_project() {
  rm -rf "$TEST_DIR"
  mkdir -p "$TEST_DIR"
  cd "$TEST_DIR" || exit
  git init -q
  git branch -M main
  # Start with failing tests (RED gate needs tests to fail for impl transition)
  echo '{"name": "test-app", "scripts": {"test": "echo FAIL && exit 1", "lint": "echo ok", "build": "echo ok"}}' > package.json
  echo 'export function hello() {}' > index.ts
  echo '// test' > foo.test.ts
  git add -A && git commit -q -m "init"

  # Install correctless
  mkdir -p .claude/skills/workflow
  rsync -a --exclude='.git' --exclude='tests' "$REPO_DIR/" .claude/skills/workflow/
}

cleanup() {
  rm -rf "$TEST_DIR"
}

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
  if echo "$actual" | grep -q "$unexpected"; then
    echo "  FAIL: $desc (output should NOT contain '$unexpected')"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  fi
}

ADV() { cd "$TEST_DIR" && .correctless/hooks/workflow-advance.sh "$@"; }

# ============================================
# Helper: advance to review->tests boundary
# ============================================

advance_to_review() {
  git checkout -q -b "$1"
  ADV init "$2" >/dev/null 2>&1
  mkdir -p .correctless/specs
  echo "$3" > ".correctless/specs/${2}.md"
  ADV review >/dev/null 2>&1
}

# ============================================
# Helper: advance through impl->qa (handles RED/GREEN gates)
# ============================================

advance_to_qa() {
  # Tests must fail for impl (RED gate)
  cd "$TEST_DIR" || exit
  echo '{"name": "test-app", "scripts": {"test": "echo FAIL && exit 1"}}' > package.json
  git add foo.test.ts
  ADV impl >/dev/null 2>&1
  # Tests must pass for qa (GREEN gate)
  echo '{"name": "test-app", "scripts": {"test": "echo PASS && exit 0"}}' > package.json
  ADV qa >/dev/null 2>&1
}

# ============================================
# Test: R-001 — spec_hash written on tests transition
# ============================================

test_r001_spec_hash_on_tests() {
  echo ""
  echo "=== R-001: spec_hash written on tests transition ==="

  setup_test_project
  .claude/skills/workflow/setup >/dev/null 2>&1

  advance_to_review "feature/test-r001" "r001-test" "# Spec R001 content"

  # Before tests transition, no spec_hash
  local state_file
  state_file="$(ls .correctless/artifacts/workflow-state-feature-test-r001-*.json 2>/dev/null | head -1)"
  local hash_before
  hash_before="$(jq -r '.spec_hash // "NOT_SET"' "$state_file")"
  assert_eq "R-001: no spec_hash before tests transition" "NOT_SET" "$hash_before"

  # Advance to tests
  ADV tests >/dev/null 2>&1

  # spec_hash should now be set
  local hash_after
  hash_after="$(jq -r '.spec_hash // "NOT_SET"' "$state_file")"
  assert_eq "R-001: spec_hash is set after tests transition" "false" "$([ "$hash_after" = "NOT_SET" ] && echo true || echo false)"

  # spec_hash should be a 64-char hex string (SHA-256)
  local hash_len
  hash_len="${#hash_after}"
  assert_eq "R-001: spec_hash is 64 chars (SHA-256)" "64" "$hash_len"

  # spec_hash should match the actual hash of the spec file
  local expected_hash
  expected_hash="$(sha256sum ".correctless/specs/r001-test.md" | cut -d' ' -f1)"
  assert_eq "R-001: spec_hash matches actual file hash" "$expected_hash" "$hash_after"
}

# ============================================
# Test: R-002 — done warns on spec mutation
# ============================================

test_r002_done_warns_on_mutation() {
  echo ""
  echo "=== R-002: done warns on spec mutation ==="

  setup_test_project
  .claude/skills/workflow/setup >/dev/null 2>&1

  advance_to_review "feature/test-r002" "r002-test" "# Spec R002 content"
  ADV tests >/dev/null 2>&1

  # Advance through TDD to reach done-eligible state
  advance_to_qa

  # Modify the spec file after review approval
  echo "# Spec R002 content - MODIFIED with extra lines" > ".correctless/specs/r002-test.md"
  echo "Added line 2" >> ".correctless/specs/r002-test.md"
  echo "Added line 3" >> ".correctless/specs/r002-test.md"

  # Done should warn about spec mutation
  local done_out
  done_out="$(ADV "done" 2>&1)"
  assert_contains "R-002: done warns about spec mutation" "WARNING" "$done_out"
  assert_contains "R-002: warning mentions spec modification" "modified after review" "$done_out"
  assert_contains "R-002: warning includes line count" "lines changed" "$done_out"

  # Transition should still succeed (advisory, not blocker)
  local phase
  phase="$(ADV status 2>&1 | grep 'Phase:' | awk '{print $2}')"
  assert_eq "R-002: done transition completes despite warning" "done" "$phase"
}

# ============================================
# Test: R-002 — done silent when spec unchanged
# ============================================

test_r002_done_silent_no_mutation() {
  echo ""
  echo "=== R-002: done silent when spec unchanged ==="

  setup_test_project
  .claude/skills/workflow/setup >/dev/null 2>&1

  advance_to_review "feature/test-r002-ok" "r002-ok-test" "# Spec unchanged"
  ADV tests >/dev/null 2>&1

  advance_to_qa

  # Do NOT modify the spec — done should be silent
  local done_out
  done_out="$(ADV "done" 2>&1)"
  assert_not_contains "R-002: no warning when spec unchanged" "WARNING.*spec" "$done_out"

  local phase
  phase="$(ADV status 2>&1 | grep 'Phase:' | awk '{print $2}')"
  assert_eq "R-002: done transition succeeds" "done" "$phase"
}

# ============================================
# Test: R-003 — spec-update re-hashes
# ============================================

test_r003_spec_update_rehashes() {
  echo ""
  echo "=== R-003: spec-update re-hashes spec_hash ==="

  setup_test_project
  .claude/skills/workflow/setup >/dev/null 2>&1

  advance_to_review "feature/test-r003" "r003-test" "# Original spec"
  ADV tests >/dev/null 2>&1

  # Get initial hash
  local state_file
  state_file="$(ls .correctless/artifacts/workflow-state-feature-test-r003-*.json 2>/dev/null | head -1)"
  local initial_hash
  initial_hash="$(jq -r '.spec_hash // "NOT_SET"' "$state_file")"
  assert_eq "R-003: initial hash is set" "false" "$([ "$initial_hash" = "NOT_SET" ] && echo true || echo false)"

  # Modify spec and run spec-update
  echo "# Updated spec with new rules" > ".correctless/specs/r003-test.md"
  ADV spec-update "added new rule" >/dev/null 2>&1

  # Hash should be updated to match new content
  local updated_hash
  updated_hash="$(jq -r '.spec_hash // "NOT_SET"' "$state_file")"
  assert_eq "R-003: hash updated after spec-update" "false" "$([ "$updated_hash" = "$initial_hash" ] && echo true || echo false)"

  # Updated hash should match the new file content
  local expected_hash
  expected_hash="$(sha256sum ".correctless/specs/r003-test.md" | cut -d' ' -f1)"
  assert_eq "R-003: updated hash matches new file content" "$expected_hash" "$updated_hash"

  # Now go through TDD again — done should NOT warn (spec-update was legitimate)
  ADV tests >/dev/null 2>&1
  advance_to_qa

  local done_out
  done_out="$(ADV "done" 2>&1)"
  assert_not_contains "R-003: no warning after legitimate spec-update" "WARNING.*spec" "$done_out"
}

# ============================================
# Test: R-004 — missing spec file at check time
# ============================================

test_r004_missing_spec_at_done() {
  echo ""
  echo "=== R-004: missing spec file at done ==="

  setup_test_project
  .claude/skills/workflow/setup >/dev/null 2>&1

  advance_to_review "feature/test-r004" "r004-test" "# Spec that will be deleted"
  ADV tests >/dev/null 2>&1

  advance_to_qa

  # Delete the spec file
  rm -f ".correctless/specs/r004-test.md"

  # Done should warn about missing spec, not crash
  local done_out
  done_out="$(ADV "done" 2>&1)"
  assert_contains "R-004: warns about missing spec" "WARNING" "$done_out"
  assert_contains "R-004: warning mentions spec not found" "not found" "$done_out"

  # Transition still proceeds
  local phase
  phase="$(ADV status 2>&1 | grep 'Phase:' | awk '{print $2}')"
  assert_eq "R-004: done transition completes despite missing spec" "done" "$phase"
}

# ============================================
# Test: R-005 — only workflow-advance.sh writes spec_hash
# ============================================

test_r005_sole_writer() {
  echo ""
  echo "=== R-005: only workflow-advance.sh writes spec_hash ==="

  # Check that no other script or hook writes spec_hash
  local other_writers
  other_writers="$(grep -rl 'spec_hash' "$REPO_DIR"/hooks/*.sh "$REPO_DIR"/scripts/*.sh 2>/dev/null | grep -v workflow-advance.sh || true)"
  assert_eq "R-005: no other hook/script writes spec_hash" "" "$other_writers"
}

# ============================================
# Test: R-001 — spec_hash from spec→tests (spec-update path)
# ============================================

test_r001_spec_hash_after_spec_update_resume() {
  echo ""
  echo "=== R-001: spec_hash written on tests transition from spec (spec-update resume) ==="

  setup_test_project
  .claude/skills/workflow/setup >/dev/null 2>&1

  advance_to_review "feature/test-r001b" "r001b-test" "# Original spec"
  ADV tests >/dev/null 2>&1

  # Do a spec-update (goes to spec phase)
  echo "# Modified spec" > ".correctless/specs/r001b-test.md"
  ADV spec-update "rule change" >/dev/null 2>&1

  # Verify phase is spec
  local phase
  phase="$(ADV status 2>&1 | grep 'Phase:' | awk '{print $2}')"
  assert_eq "R-001b: in spec phase after spec-update" "spec" "$phase"

  # Advance back to tests — spec_hash should be re-captured
  ADV tests >/dev/null 2>&1

  local state_file
  state_file="$(ls .correctless/artifacts/workflow-state-feature-test-r001b-*.json 2>/dev/null | head -1)"
  local hash
  hash="$(jq -r '.spec_hash // "NOT_SET"' "$state_file")"

  # Hash should match the current (modified) spec content
  local expected_hash
  expected_hash="$(sha256sum ".correctless/specs/r001b-test.md" | cut -d' ' -f1)"
  assert_eq "R-001b: spec_hash matches modified spec after resume" "$expected_hash" "$hash"
}

# ============================================
# Run all tests
# ============================================

trap cleanup EXIT

echo "Spec Mutation Alerts Test Suite"
echo "================================"

test_r001_spec_hash_on_tests
test_r002_done_warns_on_mutation
test_r002_done_silent_no_mutation
test_r003_spec_update_rehashes
test_r004_missing_spec_at_done
test_r005_sole_writer
test_r001_spec_hash_after_spec_update_resume

echo ""
echo "================================"
echo "Results: $PASS passed, $FAIL failed"
echo ""

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
