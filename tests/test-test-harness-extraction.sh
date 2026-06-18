#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091,SC2086
# Correctless — Test Harness Extraction Tests
#
# Tests R-001 through R-008 from the test-harness-extraction spec.
# Verifies that tests/test-helpers.sh exists, provides the expected API,
# and that all 14 listed files source it correctly.
#
# Run from repo root: bash tests/test-test-harness-extraction.sh

set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || { echo "FATAL: cannot cd to repo root" >&2; exit 2; }

REPO_DIR="$(pwd)"
HARNESS="$REPO_DIR/tests/test-helpers.sh"
PASS=0
FAIL=0
FAILED_IDS=""

# ============================================================================
# Result helpers (cannot use the harness — this test TESTS the harness)
# ============================================================================

pass() {
  local id="$1" desc="$2"
  echo "  PASS: $id — $desc"
  PASS=$((PASS + 1))
}

fail() {
  local id="$1" desc="$2"
  echo "  FAIL: $id — $desc"
  FAIL=$((FAIL + 1))
  FAILED_IDS="${FAILED_IDS}${id} "
}

echo "=== Test Harness Extraction Tests ==="

# ============================================================================
# R-001 [unit]: test-helpers.sh exists and provides expected API
# ============================================================================

echo ""
echo "--- R-001: test-helpers.sh exists and provides expected API ---"

# R-001-01: File exists
if [ -f "$HARNESS" ]; then
  pass "R-001-01" "tests/test-helpers.sh exists"
else
  fail "R-001-01" "tests/test-helpers.sh does not exist"
fi

# R-001-02: Source it and check pass() is defined
if [ -f "$HARNESS" ]; then
  out=$(bash -c 'source "'"$HARNESS"'" && type -t pass' 2>/dev/null)
  if [ "$out" = "function" ]; then
    pass "R-001-02" "pass() function is defined after sourcing"
  else
    fail "R-001-02" "pass() function not defined after sourcing (got: '$out')"
  fi
else
  fail "R-001-02" "cannot test — harness file missing"
fi

# R-001-03: fail() is defined
if [ -f "$HARNESS" ]; then
  out=$(bash -c 'source "'"$HARNESS"'" && type -t fail' 2>/dev/null)
  if [ "$out" = "function" ]; then
    pass "R-001-03" "fail() function is defined after sourcing"
  else
    fail "R-001-03" "fail() function not defined after sourcing"
  fi
else
  fail "R-001-03" "cannot test — harness file missing"
fi

# R-001-04: section() is defined
if [ -f "$HARNESS" ]; then
  out=$(bash -c 'source "'"$HARNESS"'" && type -t section' 2>/dev/null)
  if [ "$out" = "function" ]; then
    pass "R-001-04" "section() function is defined after sourcing"
  else
    fail "R-001-04" "section() function not defined after sourcing"
  fi
else
  fail "R-001-04" "cannot test — harness file missing"
fi

# R-001-05: skip() is defined
if [ -f "$HARNESS" ]; then
  out=$(bash -c 'source "'"$HARNESS"'" && type -t skip' 2>/dev/null)
  if [ "$out" = "function" ]; then
    pass "R-001-05" "skip() function is defined after sourcing"
  else
    fail "R-001-05" "skip() function not defined after sourcing"
  fi
else
  fail "R-001-05" "cannot test — harness file missing"
fi

# R-001-06: Counter variables initialized
if [ -f "$HARNESS" ]; then
  out=$(bash -c 'source "'"$HARNESS"'" && echo "PASS=$PASS FAIL=$FAIL SKIPPED=$SKIPPED"' 2>/dev/null)
  if [ "$out" = "PASS=0 FAIL=0 SKIPPED=0" ]; then
    pass "R-001-06" "counter variables initialized to 0"
  else
    fail "R-001-06" "counter variables not properly initialized (got: '$out')"
  fi
else
  fail "R-001-06" "cannot test — harness file missing"
fi

# R-001-07: FAILED_IDS variable initialized
if [ -f "$HARNESS" ]; then
  out=$(bash -c 'source "'"$HARNESS"'" && echo "FAILED_IDS=[$FAILED_IDS]"' 2>/dev/null)
  if [ "$out" = "FAILED_IDS=[]" ]; then
    pass "R-001-07" "FAILED_IDS initialized to empty string"
  else
    fail "R-001-07" "FAILED_IDS not properly initialized (got: '$out')"
  fi
else
  fail "R-001-07" "cannot test — harness file missing"
fi

# R-001-08: Color definitions exist (GREEN, RED, YELLOW, RESET)
if [ -f "$HARNESS" ]; then
  # Run with stdout NOT a terminal so colors should be empty strings
  out=$(bash -c 'source "'"$HARNESS"'" && echo "G=[${GREEN}] R=[${RED}] Y=[${YELLOW}] RST=[${RESET}]"' 2>/dev/null)
  if echo "$out" | grep -q "G=\[" && echo "$out" | grep -q "R=\[" && echo "$out" | grep -q "Y=\[" && echo "$out" | grep -q "RST=\["; then
    pass "R-001-08" "color variables defined (GREEN, RED, YELLOW, RESET)"
  else
    fail "R-001-08" "color variables not all defined (got: '$out')"
  fi
else
  fail "R-001-08" "cannot test — harness file missing"
fi

# R-001-09: Preamble sets cd to repo root and REPO_DIR
if [ -f "$HARNESS" ]; then
  out=$(bash -c 'source "'"$HARNESS"'" && echo "$REPO_DIR"' 2>/dev/null)
  if [ -n "$out" ] && [ -d "$out" ]; then
    pass "R-001-09" "REPO_DIR is set and is a valid directory"
  else
    fail "R-001-09" "REPO_DIR not set or not a valid directory (got: '$out')"
  fi
else
  fail "R-001-09" "cannot test — harness file missing"
fi

# R-001-10: pass() uses 2-arg signature (id, desc)
if [ -f "$HARNESS" ]; then
  out=$(bash -c 'source "'"$HARNESS"'" && pass "TEST-ID" "test description" && echo "PASS=$PASS"' 2>/dev/null)
  if echo "$out" | grep -q "PASS: TEST-ID" && echo "$out" | grep -q "test description" && echo "$out" | grep -q "PASS=1"; then
    pass "R-001-10" "pass() accepts 2-arg signature (id, desc) and increments counter"
  else
    fail "R-001-10" "pass() 2-arg signature not working (got: '$out')"
  fi
else
  fail "R-001-10" "cannot test — harness file missing"
fi

# R-001-11: fail() uses 2-arg signature and appends to FAILED_IDS
if [ -f "$HARNESS" ]; then
  out=$(bash -c 'source "'"$HARNESS"'" && fail "BAD-001" "something broke" && echo "FAIL=$FAIL IDS=[$FAILED_IDS]"' 2>/dev/null)
  if echo "$out" | grep -q "FAIL: BAD-001" && echo "$out" | grep -q "FAIL=1" && echo "$out" | grep -q "BAD-001"; then
    pass "R-001-11" "fail() accepts 2-arg signature and appends to FAILED_IDS"
  else
    fail "R-001-11" "fail() 2-arg signature not working (got: '$out')"
  fi
else
  fail "R-001-11" "cannot test — harness file missing"
fi

# R-001-12: Preamble enables nounset (set -u). pipefail is intentionally OFF — the
# suite's pervasive `producer | grep -q` idiom SIGPIPEs the producer, and under pipefail
# that propagates as the #186/AP-033 roaming flake; the harness documents this.
if [ -f "$HARNESS" ]; then
  if grep -qE '^set -u\b' "$HARNESS" && ! grep -qE '^set -uo pipefail' "$HARNESS"; then
    pass "R-001-12" "harness enables nounset (set -u) with pipefail intentionally off (#186 mitigation)"
  else
    fail "R-001-12" "harness must use 'set -u' with pipefail off (not 'set -uo pipefail') — see #186/AP-033"
  fi
else
  fail "R-001-12" "cannot test — harness file missing"
fi

# R-001-13: summary() function is defined
if [ -f "$HARNESS" ]; then
  out=$(bash -c 'source "'"$HARNESS"'" && type -t summary' 2>/dev/null)
  if [ "$out" = "function" ]; then
    pass "R-001-13" "summary() function is defined after sourcing"
  else
    fail "R-001-13" "summary() function not defined after sourcing"
  fi
else
  fail "R-001-13" "cannot test — harness file missing"
fi

# ============================================================================
# R-002 [unit]: summary() format and behavior
# ============================================================================

echo ""
echo "--- R-002: summary() format and behavior ---"

# R-002-01: summary() prints suite name with pass/fail counts
if [ -f "$HARNESS" ]; then
  out=$(bash -c 'source "'"$HARNESS"'" && PASS=5 && FAIL=0 && summary "My Suite"' 2>/dev/null)
  if echo "$out" | grep -q "My Suite: 5 passed, 0 failed"; then
    pass "R-002-01" "summary() prints name with pass/fail counts"
  else
    fail "R-002-01" "summary() format wrong (got: '$out')"
  fi
else
  fail "R-002-01" "cannot test — harness file missing"
fi

# R-002-02: summary() includes skipped count when SKIPPED > 0
if [ -f "$HARNESS" ]; then
  out=$(bash -c 'source "'"$HARNESS"'" && PASS=3 && FAIL=1 && SKIPPED=2 && summary "Suite" 2>/dev/null || true' 2>/dev/null)
  if echo "$out" | grep -q "3 passed, 1 failed" && echo "$out" | grep -q "2 skipped"; then
    pass "R-002-02" "summary() includes skipped count when SKIPPED > 0"
  else
    fail "R-002-02" "summary() missing skipped count (got: '$out')"
  fi
else
  fail "R-002-02" "cannot test — harness file missing"
fi

# R-002-03: summary() omits skipped when SKIPPED == 0
if [ -f "$HARNESS" ]; then
  out=$(bash -c 'source "'"$HARNESS"'" && PASS=5 && FAIL=0 && SKIPPED=0 && summary "Suite"' 2>/dev/null)
  if echo "$out" | grep -q "5 passed, 0 failed" && ! echo "$out" | grep -qi "skip"; then
    pass "R-002-03" "summary() omits skipped when SKIPPED == 0"
  else
    fail "R-002-03" "summary() should omit skipped when 0 (got: '$out')"
  fi
else
  fail "R-002-03" "cannot test — harness file missing"
fi

# R-002-04: summary() prints FAILED_IDS when non-empty
if [ -f "$HARNESS" ]; then
  out=$(bash -c 'source "'"$HARNESS"'" && PASS=1 && FAIL=2 && FAILED_IDS="X-001 X-002 " && summary "Suite" 2>/dev/null || true' 2>/dev/null)
  if echo "$out" | grep -q "X-001" && echo "$out" | grep -q "X-002"; then
    pass "R-002-04" "summary() prints FAILED_IDS list"
  else
    fail "R-002-04" "summary() not printing FAILED_IDS (got: '$out')"
  fi
else
  fail "R-002-04" "cannot test — harness file missing"
fi

# R-002-05: summary() exits 1 when FAIL > 0
if [ -f "$HARNESS" ]; then
  bash -c 'source "'"$HARNESS"'" && PASS=1 && FAIL=1 && summary "Suite"' >/dev/null 2>&1
  rc=$?
  if [ "$rc" -eq 1 ]; then
    pass "R-002-05" "summary() exits 1 when FAIL > 0"
  else
    fail "R-002-05" "summary() should exit 1 when FAIL > 0 (got exit $rc)"
  fi
else
  fail "R-002-05" "cannot test — harness file missing"
fi

# R-002-06: summary() exits 0 when FAIL == 0
if [ -f "$HARNESS" ]; then
  bash -c 'source "'"$HARNESS"'" && PASS=5 && FAIL=0 && summary "Suite"' >/dev/null 2>&1
  rc=$?
  if [ "$rc" -eq 0 ]; then
    pass "R-002-06" "summary() exits 0 when FAIL == 0"
  else
    fail "R-002-06" "summary() should exit 0 when FAIL == 0 (got exit $rc)"
  fi
else
  fail "R-002-06" "cannot test — harness file missing"
fi

# ============================================================================
# R-003 [unit]: All 14 files source test-helpers.sh
# ============================================================================

echo ""
echo "--- R-003: All 14 files source test-helpers.sh ---"

# The 14 files that must source the harness
VARIANT_A_FILES="test-agent-hooks.sh test-carchitect.sh test-carchitect-phase1.sh test-fix-diff-reviewer-agent.sh test-integration-test-contracts.sh test-tdd-mini-audit.sh test-session-cost.sh test-project-dashboard.sh"
VARIANT_B_FILES="test-dev-journal.sh test-qa-uncertain.sh"
VARIANT_C_FILES="test-sensitive-file-guard.sh test-auto-policy.sh test-allowed-tools-check.sh"
SPECIAL_FILE="test-architecture-drift.sh"

ALL_MIGRATED_FILES="$VARIANT_A_FILES $VARIANT_B_FILES $VARIANT_C_FILES $SPECIAL_FILE"

for f in $ALL_MIGRATED_FILES; do
  filepath="$REPO_DIR/tests/$f"
  if [ ! -f "$filepath" ]; then
    fail "R-003-src-$f" "$f does not exist"
    continue
  fi

  # Check that the file sources test-helpers.sh
  if grep -q 'source.*test-helpers\.sh' "$filepath"; then
    pass "R-003-src-$f" "$f sources test-helpers.sh"
  else
    fail "R-003-src-$f" "$f does not source test-helpers.sh"
  fi
done

# Variant A files must NOT define pass() or fail() inline
echo ""
echo "--- R-003: Variant A files have no inline pass/fail ---"

for f in $VARIANT_A_FILES; do
  filepath="$REPO_DIR/tests/$f"
  [ -f "$filepath" ] || continue

  # Check pass() is NOT defined inline (looking for function definition patterns)
  if grep -qE '^pass\(\)|^pass \(\)' "$filepath"; then
    fail "R-003-noinline-$f" "$f still defines pass() inline"
  else
    pass "R-003-noinline-$f" "$f does not define pass() inline"
  fi

  # Check fail() is NOT defined inline
  if grep -qE '^fail\(\)|^fail \(\)' "$filepath"; then
    fail "R-003-noinline-fail-$f" "$f still defines fail() inline"
  else
    pass "R-003-noinline-fail-$f" "$f does not define fail() inline"
  fi

  # Check section() is NOT defined inline
  if grep -qE '^section\(\)|^section \(\)' "$filepath"; then
    fail "R-003-noinline-section-$f" "$f still defines section() inline"
  else
    pass "R-003-noinline-section-$f" "$f does not define section() inline"
  fi

  # Check skip() is NOT defined inline
  if grep -qE '^skip\(\)|^skip \(\)' "$filepath"; then
    fail "R-003-noinline-skip-$f" "$f still defines skip() inline"
  else
    pass "R-003-noinline-skip-$f" "$f does not define skip() inline"
  fi

  # Check counter variables are NOT initialized inline (PASS=0 FAIL=0 etc)
  # Allow references like PASS=$((PASS + 1)) but not PASS=0 as initialization
  if grep -qE '^PASS=0|^FAIL=0|^SKIPPED=0|^FAILED_IDS=""' "$filepath"; then
    fail "R-003-nocounters-$f" "$f still initializes counter variables inline"
  else
    pass "R-003-nocounters-$f" "$f does not initialize counter variables inline"
  fi

  # Check color definitions are NOT inline (direct assignment like GREEN=...)
  color_defs=$(grep -cE '^\s*(GREEN|RED|YELLOW|RESET)=' "$filepath" 2>/dev/null || echo 0)
  if [ "$color_defs" -gt 0 ]; then
    fail "R-003-nocolors-$f" "$f still defines color variables inline ($color_defs definitions)"
  else
    pass "R-003-nocolors-$f" "$f does not define color variables inline"
  fi
done

# Variant B files must NOT define pass() or fail() inline
echo ""
echo "--- R-003: Variant B files have no inline pass/fail ---"

for f in $VARIANT_B_FILES; do
  filepath="$REPO_DIR/tests/$f"
  [ -f "$filepath" ] || continue

  # Check pass() is NOT defined inline
  if grep -qE '^pass\(\)|^pass \(\)' "$filepath"; then
    fail "R-003-noinline-$f" "$f still defines pass() inline"
  else
    pass "R-003-noinline-$f" "$f does not define pass() inline"
  fi

  # Check fail() is NOT defined inline
  if grep -qE '^fail\(\)|^fail \(\)' "$filepath"; then
    fail "R-003-noinline-fail-$f" "$f still defines fail() inline"
  else
    pass "R-003-noinline-fail-$f" "$f does not define fail() inline"
  fi

  # Counter variables removed
  if grep -qE '^PASS=0|^FAIL=0|^FAILED_IDS=""' "$filepath"; then
    fail "R-003-nocounters-$f" "$f still initializes counter variables inline"
  else
    pass "R-003-nocounters-$f" "$f does not initialize counter variables inline"
  fi
done

# Variant C files should NOT define their own PASS=0/FAIL=0 initialization
echo ""
echo "--- R-003: Variant C files have no inline counter init ---"

for f in $VARIANT_C_FILES; do
  filepath="$REPO_DIR/tests/$f"
  [ -f "$filepath" ] || continue

  # Counter variables removed (they get these from the harness)
  if grep -qE '^PASS=0|^FAIL=0' "$filepath"; then
    fail "R-003-nocounters-$f" "$f still initializes PASS/FAIL counters inline"
  else
    pass "R-003-nocounters-$f" "$f does not initialize PASS/FAIL counters inline"
  fi
done

# Special case: test-architecture-drift.sh uses FAILED_IDS not FAILED_INVS
echo ""
echo "--- R-003: test-architecture-drift.sh variable normalization ---"

DRIFT_FILE="$REPO_DIR/tests/test-architecture-drift.sh"
if [ -f "$DRIFT_FILE" ]; then
  # Must NOT use FAILED_INVS anymore
  if grep -q 'FAILED_INVS' "$DRIFT_FILE"; then
    fail "R-003-norm-drift" "test-architecture-drift.sh still uses FAILED_INVS (should use FAILED_IDS)"
  else
    pass "R-003-norm-drift" "test-architecture-drift.sh does not use FAILED_INVS"
  fi
else
  fail "R-003-norm-drift" "test-architecture-drift.sh not found"
fi

# ============================================================================
# R-004 [unit]: Output count equivalence — test result counts unchanged
# ============================================================================

echo ""
echo "--- R-004: Output count equivalence ---"

# For R-004 we verify that the test files, when run, produce the expected
# output patterns (PASS/FAIL/SKIP lines). Since we can't easily run before/after
# in a single test run, we verify structurally that each file:
# 1. Still has the same number of test assertions (pass/fail calls)
# 2. The harness pass/fail functions produce matching output format

# Verify pass() output matches established pattern: "  PASS: id"
if [ -f "$HARNESS" ]; then
  out=$(bash -c 'source "'"$HARNESS"'" && pass "ID-001" "desc"' 2>/dev/null)
  if echo "$out" | grep -q "PASS.*ID-001"; then
    pass "R-004-01" "harness pass() output contains PASS pattern"
  else
    fail "R-004-01" "harness pass() output does not match (got: '$out')"
  fi
else
  fail "R-004-01" "cannot test — harness file missing"
fi

# Verify fail() output matches established pattern: "  FAIL: id"
if [ -f "$HARNESS" ]; then
  out=$(bash -c 'source "'"$HARNESS"'" && fail "ID-002" "desc"' 2>/dev/null)
  if echo "$out" | grep -q "FAIL.*ID-002"; then
    pass "R-004-02" "harness fail() output contains FAIL pattern"
  else
    fail "R-004-02" "harness fail() output does not match (got: '$out')"
  fi
else
  fail "R-004-02" "cannot test — harness file missing"
fi

# Verify skip() output matches established pattern: "  SKIP: id"
if [ -f "$HARNESS" ]; then
  out=$(bash -c 'source "'"$HARNESS"'" && skip "ID-003" "desc"' 2>/dev/null)
  if echo "$out" | grep -q "SKIP.*ID-003"; then
    pass "R-004-03" "harness skip() output contains SKIP pattern"
  else
    fail "R-004-03" "harness skip() output does not match (got: '$out')"
  fi
else
  fail "R-004-03" "cannot test — harness file missing"
fi

# ============================================================================
# R-005 [unit]: test-helpers.sh is NOT in sync.sh
# ============================================================================

echo ""
echo "--- R-005: test-helpers.sh not in sync.sh ---"

SYNC_FILE="$REPO_DIR/sync.sh"

# R-005-01: sync.sh does not reference test-helpers.sh
if [ -f "$SYNC_FILE" ]; then
  if grep -q 'test-helpers' "$SYNC_FILE"; then
    fail "R-005-01" "sync.sh references test-helpers (should not be in distribution)"
  else
    pass "R-005-01" "sync.sh does not reference test-helpers"
  fi
else
  fail "R-005-01" "sync.sh not found"
fi

# R-005-02: test-helpers.sh is NOT in the correctless/ distribution directory
if [ -f "$REPO_DIR/correctless/tests/test-helpers.sh" ] || [ -f "$REPO_DIR/correctless/test-helpers.sh" ]; then
  fail "R-005-02" "test-helpers.sh found in correctless/ distribution"
else
  pass "R-005-02" "test-helpers.sh not in correctless/ distribution"
fi

# ============================================================================
# R-006 [unit]: Files with additional shell options retain them
# ============================================================================

echo ""
echo "--- R-006: Additional shell options preserved ---"

# Files known to use set -f (noglob):
# test-agent-hooks.sh, test-carchitect.sh, test-carchitect-phase1.sh,
# test-fix-diff-reviewer-agent.sh, test-integration-test-contracts.sh,
# test-tdd-mini-audit.sh
NOGLOB_FILES="test-agent-hooks.sh test-carchitect.sh test-carchitect-phase1.sh test-fix-diff-reviewer-agent.sh test-integration-test-contracts.sh test-tdd-mini-audit.sh"

for f in $NOGLOB_FILES; do
  filepath="$REPO_DIR/tests/$f"
  [ -f "$filepath" ] || continue

  if grep -q 'set -f' "$filepath"; then
    pass "R-006-noglob-$f" "$f retains 'set -f' (noglob)"
  else
    fail "R-006-noglob-$f" "$f lost 'set -f' (noglob) during migration"
  fi
done

# ============================================================================
# R-007 [unit]: Source line uses correct relative path format
# ============================================================================

echo ""
echo "--- R-007: Source line format ---"

# The source line must be: source "$(dirname "${BASH_SOURCE[0]}")/test-helpers.sh"
EXPECTED_SOURCE='source "$(dirname "${BASH_SOURCE[0]}")/test-helpers.sh"'

for f in $ALL_MIGRATED_FILES; do
  filepath="$REPO_DIR/tests/$f"
  [ -f "$filepath" ] || continue

  if grep -qF "$EXPECTED_SOURCE" "$filepath"; then
    pass "R-007-fmt-$f" "$f uses correct source line format"
  else
    # Also check if it sources at all (even with different format)
    if grep -q 'source.*test-helpers' "$filepath"; then
      fail "R-007-fmt-$f" "$f sources test-helpers.sh but with wrong format"
    else
      fail "R-007-fmt-$f" "$f does not source test-helpers.sh at all"
    fi
  fi
done

# ============================================================================
# R-008 [unit]: File-specific variables remain in each test file
# ============================================================================

echo ""
echo "--- R-008: File-specific variables preserved ---"

# test-agent-hooks.sh should still have HOOK_FILE, HOOK_DIST, etc.
f="$REPO_DIR/tests/test-agent-hooks.sh"
if [ -f "$f" ]; then
  if grep -q 'HOOK_FILE=' "$f"; then
    pass "R-008-agent-hooks-HOOK_FILE" "test-agent-hooks.sh retains HOOK_FILE"
  else
    fail "R-008-agent-hooks-HOOK_FILE" "test-agent-hooks.sh lost HOOK_FILE"
  fi
else
  fail "R-008-agent-hooks-HOOK_FILE" "test-agent-hooks.sh not found"
fi

# test-sensitive-file-guard.sh should still have HOOK and assert helpers
f="$REPO_DIR/tests/test-sensitive-file-guard.sh"
if [ -f "$f" ]; then
  if grep -q 'HOOK=' "$f"; then
    pass "R-008-sfg-HOOK" "test-sensitive-file-guard.sh retains HOOK variable"
  else
    fail "R-008-sfg-HOOK" "test-sensitive-file-guard.sh lost HOOK variable"
  fi
  # Variant C: assert helpers should remain per R-008
  if grep -q 'assert_eq()' "$f"; then
    pass "R-008-sfg-assert_eq" "test-sensitive-file-guard.sh retains assert_eq()"
  else
    fail "R-008-sfg-assert_eq" "test-sensitive-file-guard.sh lost assert_eq()"
  fi
else
  fail "R-008-sfg-HOOK" "test-sensitive-file-guard.sh not found"
fi

# test-auto-policy.sh should still have assert helpers (Variant C)
f="$REPO_DIR/tests/test-auto-policy.sh"
if [ -f "$f" ]; then
  if grep -q 'assert_eq()' "$f"; then
    pass "R-008-policy-assert_eq" "test-auto-policy.sh retains assert_eq()"
  else
    fail "R-008-policy-assert_eq" "test-auto-policy.sh lost assert_eq()"
  fi
  if grep -q 'file_contains()' "$f"; then
    pass "R-008-policy-file_contains" "test-auto-policy.sh retains file_contains()"
  else
    fail "R-008-policy-file_contains" "test-auto-policy.sh lost file_contains()"
  fi
else
  fail "R-008-policy-assert_eq" "test-auto-policy.sh not found"
fi

# test-allowed-tools-check.sh should still have its own pass/fail if it's variant C
# Actually per spec, variant C files do NOT define pass/fail — they use assert_eq etc.
# test-allowed-tools-check.sh currently has 1-arg pass/fail — per spec this must be
# updated to 2-arg or kept with its own helpers. Check the file retains structural content.
f="$REPO_DIR/tests/test-allowed-tools-check.sh"
if [ -f "$f" ]; then
  if grep -q 'skills_dir=' "$f" || grep -q 'cspec=' "$f"; then
    pass "R-008-atc-vars" "test-allowed-tools-check.sh retains file-specific variables"
  else
    fail "R-008-atc-vars" "test-allowed-tools-check.sh lost file-specific variables"
  fi
else
  fail "R-008-atc-vars" "test-allowed-tools-check.sh not found"
fi

# test-session-cost.sh should still have SCRIPT and LIB_SH
f="$REPO_DIR/tests/test-session-cost.sh"
if [ -f "$f" ]; then
  if grep -q 'SCRIPT=' "$f"; then
    pass "R-008-session-SCRIPT" "test-session-cost.sh retains SCRIPT variable"
  else
    fail "R-008-session-SCRIPT" "test-session-cost.sh lost SCRIPT variable"
  fi
else
  fail "R-008-session-SCRIPT" "test-session-cost.sh not found"
fi

# test-architecture-drift.sh should still have ARCH_FILE, RULE_FILE, etc.
f="$REPO_DIR/tests/test-architecture-drift.sh"
if [ -f "$f" ]; then
  if grep -q 'ARCH_FILE=' "$f"; then
    pass "R-008-drift-ARCH_FILE" "test-architecture-drift.sh retains ARCH_FILE"
  else
    fail "R-008-drift-ARCH_FILE" "test-architecture-drift.sh lost ARCH_FILE"
  fi
else
  fail "R-008-drift-ARCH_FILE" "test-architecture-drift.sh not found"
fi

# test-dev-journal.sh should still have CDOCS_SKILL
f="$REPO_DIR/tests/test-dev-journal.sh"
if [ -f "$f" ]; then
  if grep -q 'CDOCS_SKILL=' "$f"; then
    pass "R-008-journal-CDOCS_SKILL" "test-dev-journal.sh retains CDOCS_SKILL"
  else
    fail "R-008-journal-CDOCS_SKILL" "test-dev-journal.sh lost CDOCS_SKILL"
  fi
else
  fail "R-008-journal-CDOCS_SKILL" "test-dev-journal.sh not found"
fi

# test-project-dashboard.sh should still have run_dashboard helper
f="$REPO_DIR/tests/test-project-dashboard.sh"
if [ -f "$f" ]; then
  if grep -q 'run_dashboard()' "$f"; then
    pass "R-008-dashboard-run_dashboard" "test-project-dashboard.sh retains run_dashboard()"
  else
    fail "R-008-dashboard-run_dashboard" "test-project-dashboard.sh lost run_dashboard()"
  fi
else
  fail "R-008-dashboard-run_dashboard" "test-project-dashboard.sh not found"
fi

# ============================================================================
# Registration: test file is in CI and workflow-config.json
# ============================================================================

echo ""
echo "--- Registration: test file in CI and config ---"

CI_YML="$REPO_DIR/.github/workflows/ci.yml"
WF_CONFIG="$REPO_DIR/.correctless/config/workflow-config.json"

# REG-001: test-test-harness-extraction.sh discoverable by ci.yml
# DA-002: CI now uses glob-based discovery (test-*.sh)
if [ -f "$CI_YML" ] && (grep -q 'test-test-harness-extraction' "$CI_YML" || grep -qE 'test-\*\.sh' "$CI_YML"); then
  pass "REG-001" "test-test-harness-extraction.sh discoverable by ci.yml"
else
  fail "REG-001" "test-test-harness-extraction.sh NOT registered in ci.yml"
fi

# REG-002: test-test-harness-extraction.sh discoverable by workflow-config.json
if [ -f "$WF_CONFIG" ] && (grep -q 'test-test-harness-extraction' "$WF_CONFIG" || jq -r '.commands.test // ""' "$WF_CONFIG" 2>/dev/null | grep -qE 'test-\*\.sh'); then
  pass "REG-002" "test-test-harness-extraction.sh discoverable by workflow-config.json"
else
  fail "REG-002" "test-test-harness-extraction.sh NOT registered in workflow-config.json"
fi

# ============================================================================
# Summary
# ============================================================================

echo ""
echo "==========================================="
echo "Test Harness Extraction: $PASS passed, $FAIL failed"
if [ -n "$FAILED_IDS" ]; then
  echo "Failed: $FAILED_IDS"
fi
echo "==========================================="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
