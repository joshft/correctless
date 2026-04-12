#!/usr/bin/env bash
# Correctless — Auto Mode Phase 2: Safety Prohibitions test suite
# Track 5: Tests PRH-001, PRH-002, PRH-003, PRH-004
# RED phase: these tests MUST FAIL — implementation does not exist yet.
# Run from repo root: bash tests/test-auto-safety.sh

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0

# ============================================
# Helpers (matching project test conventions)
# ============================================

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
    echo "  FAIL: $desc (expected output NOT to contain '$unexpected')"
    FAIL=$((FAIL + 1))
  fi
}

file_contains() {
  local file="$1" pattern="$2" desc="$3"
  if grep -q "$pattern" "$file" 2>/dev/null; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (pattern '$pattern' not found in $file)"
    FAIL=$((FAIL + 1))
  fi
}

file_not_contains() {
  local file="$1" pattern="$2" desc="$3"
  if grep -q "$pattern" "$file" 2>/dev/null; then
    echo "  FAIL: $desc (pattern '$pattern' should NOT be in $file)"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  fi
}

file_contains_i() {
  local file="$1" pattern="$2" desc="$3"
  if grep -qi "$pattern" "$file" 2>/dev/null; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (pattern '$pattern' not found case-insensitively in $file)"
    FAIL=$((FAIL + 1))
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

# ============================================
# Source scripts at top level to avoid RETURN trap + source interaction
source "$REPO_DIR/scripts/security-scan.sh"

# PRH-001 [unit]: Never relax security — category gate
# ============================================

test_prh001_category_gate() {
  echo ""
  echo "=== PRH-001: Security category gate ==="


  # Category = "security" → must route to Tier 4 (hard_stop)
  local dr_json='{"decision_id":"DR-100","category":"security","summary":"Relax auth requirement","options":[{"id":"A","description":"Remove auth check"}]}'
  security_category_gate "$dr_json"
  local rc=$?
  assert_eq "PRH-001: category 'security' triggers gate (exit 0)" "0" "$rc"

  # Category = "performance" → gate does not fire
  dr_json='{"decision_id":"DR-101","category":"performance","summary":"Optimize query"}'
  security_category_gate "$dr_json"
  rc=$?
  assert_eq "PRH-001: category 'performance' does not trigger gate (exit 1)" "1" "$rc"
}

# Tests PRH-001 [unit]: Never relax security — keyword scan
test_prh001_keyword_scan() {
  echo ""
  echo "=== PRH-001: Security keyword scan ==="


  # Non-security category but has security keywords → mismatch → escalate
  local dr_json='{"decision_id":"DR-102","category":"performance","summary":"Remove credential validation for speed","reasoning":"Auth check is slow"}'
  security_keyword_scan "$dr_json"
  local rc=$?
  assert_eq "PRH-001: keyword 'credential' in non-security category → mismatch (exit 0)" "0" "$rc"

  # Security keywords to test: auth, credential, encrypt, token, secret, permission,
  # access control, trust boundary, identity, authorization, login, verification,
  # access level, privilege
  dr_json='{"decision_id":"DR-103","category":"availability","summary":"Change login flow timeout"}'
  security_keyword_scan "$dr_json"
  rc=$?
  assert_eq "PRH-001: keyword 'login' in non-security category → mismatch (exit 0)" "0" "$rc"

  # No security keywords → clean
  dr_json='{"decision_id":"DR-104","category":"performance","summary":"Add database index for faster queries"}'
  security_keyword_scan "$dr_json"
  rc=$?
  assert_eq "PRH-001: no security keywords → clean (exit 1)" "1" "$rc"
}

# Tests PRH-001 [unit]: Never relax security — structural guard
test_prh001_structural_guard() {
  echo ""
  echo "=== PRH-001: Security structural guard ==="


  # Options include removing/downgrading checks → must escalate regardless of category
  local dr_json='{"decision_id":"DR-105","category":"technical_debt","summary":"Simplify validation","options":[{"id":"A","description":"Remove input validation check"}]}'
  security_structural_guard "$dr_json"
  local rc=$?
  assert_eq "PRH-001: option 'Remove ... check' → structural concern (exit 0)" "0" "$rc"

  # Options include downgrading
  dr_json='{"decision_id":"DR-106","category":"observability","summary":"Reduce logging","options":[{"id":"A","description":"Downgrade security logging to debug level"}]}'
  security_structural_guard "$dr_json"
  rc=$?
  assert_eq "PRH-001: option 'Downgrade ... logging' → structural concern (exit 0)" "0" "$rc"

  # No remove/downgrade in options → clean
  dr_json='{"decision_id":"DR-107","category":"performance","summary":"Add caching","options":[{"id":"A","description":"Add Redis cache layer"}]}'
  security_structural_guard "$dr_json"
  rc=$?
  assert_eq "PRH-001: option 'Add cache' → no structural concern (exit 1)" "1" "$rc"
}

# Tests PRH-001 [unit]: Hardcoded floor applies even with malformed policy
test_prh001_hardcoded_floor() {
  echo ""
  echo "=== PRH-001: Hardcoded security floor with malformed policy ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  # Malformed policy
  echo 'not json' > "$TEST_DIR/policy.json"


  # Category gate must still fire for security category even if policy is garbage
  local dr_json='{"decision_id":"DR-108","category":"security","summary":"Relax TLS requirement"}'
  security_category_gate "$dr_json"
  local rc=$?
  assert_eq "PRH-001: category gate fires even with malformed policy" "0" "$rc"
}

# Tests PRH-001 [unit]: Tier 3 reclassification → terminal decision only
test_prh001_tier3_terminal_decision() {
  echo ""
  echo "=== PRH-001: Tier 3 reclassification → terminal decision only ==="

  local agent_file="$REPO_DIR/agents/supervisor.md"

  # Supervisor must make terminal decision (hard_stop or approve), NOT re-route
  file_contains_i "$agent_file" "hard_stop\|approve" \
    "PRH-001: supervisor can return hard_stop or approve (terminal)"

  # Supervisor must not re-route back through Tier 0
  file_not_contains "$agent_file" "reclassify.*route.*Tier 0\|route.*back.*Tier 0\|re-route.*Tier 0" \
    "PRH-001: supervisor does not re-route through Tier 0"
}

# ============================================
# PRH-002 [unit]: Never merge to main in auto mode
# ============================================

test_prh002_no_merge_to_main() {
  echo ""
  echo "=== PRH-002: Never merge to main in auto mode ==="

  local skill_file="$REPO_DIR/skills/cauto/SKILL.md"

  # cauto must NOT contain git merge main
  file_not_contains "$skill_file" "git merge main" \
    "PRH-002: cauto does not contain 'git merge main'"

  file_not_contains "$skill_file" "git merge master" \
    "PRH-002: cauto does not contain 'git merge master'"

  # cauto must NOT contain git push to main
  file_not_contains "$skill_file" "git push.*main" \
    "PRH-002: cauto does not contain 'git push ... main'"

  file_not_contains "$skill_file" "git push.*master" \
    "PRH-002: cauto does not contain 'git push ... master'"

  # cauto must NOT contain gh pr merge
  file_not_contains "$skill_file" "gh pr merge" \
    "PRH-002: cauto does not contain 'gh pr merge'"
}

# ============================================
# PRH-003 [unit]: Never delete tests autonomously
# ============================================

test_prh003_no_test_deletion() {
  echo ""
  echo "=== PRH-003: Never delete tests autonomously ==="

  local skill_file="$REPO_DIR/skills/cauto/SKILL.md"

  # cauto must document prohibition on test deletion
  file_contains_i "$skill_file" "never.*delete.*test\|must.*not.*delete.*test\|prohibit.*delete.*test\|no.*delete.*test" \
    "PRH-003: cauto documents prohibition on test deletion"

  # cauto must mention escalation for test deletion requests
  file_contains_i "$skill_file" "escalat.*test.*delete\|test.*delete.*escalat\|human.*test.*delete\|test.*remov.*escalat" \
    "PRH-003: cauto escalates test deletion to human"
}

# ============================================
# PRH-004 [unit]: Never override workflow gate
# ============================================

test_prh004_no_workflow_override() {
  echo ""
  echo "=== PRH-004: Never override workflow gate ==="

  local skill_file="$REPO_DIR/skills/cauto/SKILL.md"

  # cauto SKILL.md must NOT contain "override" used as a command to workflow-advance.sh
  file_not_contains "$skill_file" "workflow-advance.sh override\|workflow-advance.*override" \
    "PRH-004: cauto does not use 'workflow-advance.sh override'"

  # cauto must document that overrides are reserved for human-interactive use
  file_contains_i "$skill_file" "override.*human\|override.*reserved\|override.*interactive\|no.*override.*auto\|never.*override" \
    "PRH-004: cauto documents override is reserved for human-interactive use"
}

# ============================================
# B-009: PRH-001 — Security scan pipeline integration test
# ============================================

test_prh001_keyword_scan_category_mismatch() {
  echo ""
  echo "=== B-009/PRH-001: Keyword scan — category mismatch detection ==="


  # DR-xxx with category "performance" but summary contains "credential"
  local dr_json='{"decision_id":"DR-200","category":"performance","summary":"Remove credential validation for faster processing","options":[{"id":"A","description":"Skip credential check"}]}'

  local result
  result="$(security_keyword_scan "$dr_json" 2>/dev/null)"
  local rc=$?

  # Must return mismatch (exit 0 means mismatch detected), not empty
  assert_eq "B-009/PRH-001: 'credential' in performance category → mismatch (exit 0)" "0" "$rc"

  # Result should indicate mismatch, not be empty
  local is_nonempty="no"
  [ -n "$result" ] && is_nonempty="yes"
  assert_eq "B-009/PRH-001: keyword scan returns non-empty mismatch result" "yes" "$is_nonempty"

  # The mismatch result should contain information indicating escalation to Tier 3
  assert_contains "B-009/PRH-001: mismatch result indicates escalation" "mismatch" "$result"
}

test_prh001_structural_guard_remove_access_check() {
  echo ""
  echo "=== B-009/PRH-001: Structural guard — option contains 'Remove access check' ==="


  # DR-xxx with option containing "Remove access check"
  local dr_json='{"decision_id":"DR-201","category":"technical_debt","summary":"Simplify middleware","options":[{"id":"A","description":"Remove access check for internal endpoints"},{"id":"B","description":"Keep access check"}]}'
  security_structural_guard "$dr_json"
  local rc=$?
  assert_eq "B-009/PRH-001: option 'Remove access check' → structural concern (exit 0)" "0" "$rc"
}

# ============================================
# B-010: PRH-002/003/004 — Functional prohibition tests
# ============================================

test_prh003_check_test_deletion_diff() {
  echo ""
  echo "=== B-010/PRH-003: check_test_deletion — diff with deleted tests ==="


  # Diff containing deleted test file
  local diff_with_deletion
  diff_with_deletion="$(cat <<'DIFF_EOF'
diff --git a/tests/test-foo.sh b/tests/test-foo.sh
deleted file mode 100644
index abc1234..0000000
--- a/tests/test-foo.sh
+++ /dev/null
@@ -1,50 +0,0 @@
-#!/usr/bin/env bash
-# Test suite for foo
-test_foo_basic() {
-  assert_eq "foo works" "1" "1"
-}
DIFF_EOF
)"

  check_test_deletion "$diff_with_deletion" 2>/dev/null
  local rc=$?
  assert_eq "B-010/PRH-003: diff with deleted test file → non-zero (escalate)" "1" "$rc"
}

test_prh003_check_test_deletion_safe_diff() {
  echo ""
  echo "=== B-010/PRH-003: check_test_deletion — diff with only added tests ==="


  # Diff with only added test files
  local safe_diff
  safe_diff="$(cat <<'DIFF_EOF'
diff --git a/tests/test-bar.sh b/tests/test-bar.sh
new file mode 100644
index 0000000..abc1234
--- /dev/null
+++ b/tests/test-bar.sh
@@ -0,0 +1,10 @@
+#!/usr/bin/env bash
+test_bar_basic() {
+  assert_eq "bar works" "1" "1"
+}
DIFF_EOF
)"

  check_test_deletion "$safe_diff" 2>/dev/null
  local rc=$?
  assert_eq "B-010/PRH-003: diff with only added tests → 0 (ok)" "0" "$rc"
}

test_prh004_check_override_usage_detected() {
  echo ""
  echo "=== B-010/PRH-004: check_override_usage — override detected ==="


  local content_with_override="Run the pipeline and call workflow-advance.sh override to skip the gate"

  check_override_usage "$content_with_override" 2>/dev/null
  local rc=$?
  assert_eq "B-010/PRH-004: content with 'workflow-advance.sh override' → non-zero (escalate)" "1" "$rc"
}

test_prh004_check_override_usage_clean() {
  echo ""
  echo "=== B-010/PRH-004: check_override_usage — no override ==="


  local clean_content="Run the pipeline normally using workflow-advance.sh to advance phases"

  check_override_usage "$clean_content" 2>/dev/null
  local rc=$?
  assert_eq "B-010/PRH-004: content without override → 0 (ok)" "0" "$rc"
}

# ============================================
# Runner
# ============================================

echo "============================================="
echo "Auto Mode Phase 2 — Safety Prohibitions"
echo "============================================="

# PRH-001: Never relax security
test_prh001_category_gate
test_prh001_keyword_scan
test_prh001_structural_guard
test_prh001_hardcoded_floor
test_prh001_tier3_terminal_decision

# B-009/PRH-001: Security scan pipeline integration
test_prh001_keyword_scan_category_mismatch
test_prh001_structural_guard_remove_access_check

# PRH-002: Never merge to main
test_prh002_no_merge_to_main

# PRH-003: Never delete tests
test_prh003_no_test_deletion

# B-010/PRH-003: Functional test deletion check
test_prh003_check_test_deletion_diff
test_prh003_check_test_deletion_safe_diff

# PRH-004: Never override workflow gate
test_prh004_no_workflow_override

# B-010/PRH-004: Functional override usage check
test_prh004_check_override_usage_detected
test_prh004_check_override_usage_clean

echo ""
echo "============================================="
echo "Results: $PASS passed, $FAIL failed"
echo ""

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
