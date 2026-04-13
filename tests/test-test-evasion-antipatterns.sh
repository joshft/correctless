#!/usr/bin/env bash
# Correctless — Test Evasion Antipatterns test suite
# Tests AP-016/017/018 corpus entries and ctdd audit prompt checks 5/6/7.
# RED phase: these tests MUST FAIL — entries and checks don't exist yet.
# Run from repo root: bash tests/test-test-evasion-antipatterns.sh

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

ANTIPATTERNS="$REPO_DIR/.correctless/antipatterns.md"
CTDD_SKILL="$REPO_DIR/skills/ctdd/SKILL.md"

# ============================================
# R-001 [unit]: AP-016 entry exists
# ============================================

test_r001_ap016_entry() {
  echo ""
  echo "=== R-001: AP-016 entry exists ==="

  file_contains "$ANTIPATTERNS" \
    "### AP-016: Test-routing around requirements" \
    "R-001: AP-016 heading exists"

  file_contains "$ANTIPATTERNS" \
    "AP-016.*What went wrong\|### AP-016" \
    "R-001: AP-016 has What went wrong field (structural check)"

  # Grep a range after AP-016 heading for the required fields
  local ap016_block
  ap016_block="$(sed -n '/### AP-016/,/### AP-0/p' "$ANTIPATTERNS" 2>/dev/null)"

  local has_what_went_wrong="no"
  echo "$ap016_block" | grep -q '\*\*What went wrong\*\*:' && has_what_went_wrong="yes"
  assert_eq "R-001: AP-016 has **What went wrong**: field" "yes" "$has_what_went_wrong"

  local has_how_to_catch="no"
  echo "$ap016_block" | grep -q '\*\*How to catch it\*\*:' && has_how_to_catch="yes"
  assert_eq "R-001: AP-016 has **How to catch it**: field" "yes" "$has_how_to_catch"

  # How to catch it must mention spec-named resources
  local catch_has_anchor="no"
  echo "$ap016_block" | grep -qi 'spec-named\|endpoint\|method\|path' && catch_has_anchor="yes"
  assert_eq "R-001: AP-016 How-to-catch-it mentions spec-named/endpoint/method/path" "yes" "$catch_has_anchor"

  local has_frequency="no"
  echo "$ap016_block" | grep -q '\*\*Frequency\*\*:' && has_frequency="yes"
  assert_eq "R-001: AP-016 has **Frequency**: field" "yes" "$has_frequency"

  local has_scanner="no"
  echo "$ap016_block" | grep -q '\*\*Scanner rule\*\*:' && has_scanner="yes"
  assert_eq "R-001: AP-016 has **Scanner rule**: field" "yes" "$has_scanner"

  local has_source="no"
  echo "$ap016_block" | grep -q '\*\*Source\*\*:' && has_source="yes"
  assert_eq "R-001: AP-016 has **Source**: field" "yes" "$has_source"
}

# ============================================
# R-002 [unit]: AP-017 entry exists
# ============================================

test_r002_ap017_entry() {
  echo ""
  echo "=== R-002: AP-017 entry exists ==="

  file_contains "$ANTIPATTERNS" \
    "### AP-017: Hand-rolled permissive mocks" \
    "R-002: AP-017 heading exists"

  local ap017_block
  ap017_block="$(sed -n '/### AP-017/,/### AP-0/p' "$ANTIPATTERNS" 2>/dev/null)"

  local has_what_went_wrong="no"
  echo "$ap017_block" | grep -q '\*\*What went wrong\*\*:' && has_what_went_wrong="yes"
  assert_eq "R-002: AP-017 has **What went wrong**: field" "yes" "$has_what_went_wrong"

  local has_how_to_catch="no"
  echo "$ap017_block" | grep -q '\*\*How to catch it\*\*:' && has_how_to_catch="yes"
  assert_eq "R-002: AP-017 has **How to catch it**: field" "yes" "$has_how_to_catch"

  # How to catch it must mention mock generator or go:generate or mock framework
  local catch_has_anchor="no"
  echo "$ap017_block" | grep -qi 'mock generator\|go:generate\|mock framework' && catch_has_anchor="yes"
  assert_eq "R-002: AP-017 How-to-catch-it mentions mock generator/go:generate/mock framework" "yes" "$catch_has_anchor"

  local has_frequency="no"
  echo "$ap017_block" | grep -q '\*\*Frequency\*\*:' && has_frequency="yes"
  assert_eq "R-002: AP-017 has **Frequency**: field" "yes" "$has_frequency"

  local has_scanner="no"
  echo "$ap017_block" | grep -q '\*\*Scanner rule\*\*:' && has_scanner="yes"
  assert_eq "R-002: AP-017 has **Scanner rule**: field" "yes" "$has_scanner"

  local has_source="no"
  echo "$ap017_block" | grep -q '\*\*Source\*\*:' && has_source="yes"
  assert_eq "R-002: AP-017 has **Source**: field" "yes" "$has_source"
}

# ============================================
# R-003 [unit]: AP-018 entry exists
# ============================================

test_r003_ap018_entry() {
  echo ""
  echo "=== R-003: AP-018 entry exists ==="

  file_contains "$ANTIPATTERNS" \
    "### AP-018: Phantom e2e execution" \
    "R-003: AP-018 heading exists"

  # AP-018 is the last entry, so we extract from heading to end of file
  local ap018_block
  ap018_block="$(sed -n '/### AP-018/,$ p' "$ANTIPATTERNS" 2>/dev/null)"

  local has_what_went_wrong="no"
  echo "$ap018_block" | grep -q '\*\*What went wrong\*\*:' && has_what_went_wrong="yes"
  assert_eq "R-003: AP-018 has **What went wrong**: field" "yes" "$has_what_went_wrong"

  local has_how_to_catch="no"
  echo "$ap018_block" | grep -q '\*\*How to catch it\*\*:' && has_how_to_catch="yes"
  assert_eq "R-003: AP-018 has **How to catch it**: field" "yes" "$has_how_to_catch"

  # How to catch it must mention execution evidence or timestamps or command output
  local catch_has_anchor="no"
  echo "$ap018_block" | grep -qi 'execution evidence\|timestamps\|command output' && catch_has_anchor="yes"
  assert_eq "R-003: AP-018 How-to-catch-it mentions execution evidence/timestamps/command output" "yes" "$catch_has_anchor"

  local has_frequency="no"
  echo "$ap018_block" | grep -q '\*\*Frequency\*\*:' && has_frequency="yes"
  assert_eq "R-003: AP-018 has **Frequency**: field" "yes" "$has_frequency"

  local has_scanner="no"
  echo "$ap018_block" | grep -q '\*\*Scanner rule\*\*:' && has_scanner="yes"
  assert_eq "R-003: AP-018 has **Scanner rule**: field" "yes" "$has_scanner"

  local has_source="no"
  echo "$ap018_block" | grep -q '\*\*Source\*\*:' && has_source="yes"
  assert_eq "R-003: AP-018 has **Source**: field" "yes" "$has_source"
}

# ============================================
# R-004 [integration]: ctdd audit check 5 exists with anchor
# ============================================

test_r004_ctdd_check5() {
  echo ""
  echo "=== R-004: ctdd audit check 5 exists with 'spec-named' anchor ==="

  # Look for a line starting with "> 5." in the test auditor blockquote
  file_contains "$CTDD_SKILL" \
    '^> 5\.' \
    "R-004: ctdd SKILL.md has numbered check '> 5.'"

  # The check 5 text must contain "spec-named"
  local check5_line
  check5_line="$(grep -A 2 '^> 5\.' "$CTDD_SKILL" 2>/dev/null)"

  local has_anchor="no"
  echo "$check5_line" | grep -qi 'spec-named' && has_anchor="yes"
  assert_eq "R-004: check 5 contains 'spec-named' anchor" "yes" "$has_anchor"
}

# ============================================
# R-005 [integration]: ctdd audit check 6 exists with anchor
# ============================================

test_r005_ctdd_check6() {
  echo ""
  echo "=== R-005: ctdd audit check 6 exists with 'hand-rolled mock/stub' anchor ==="

  file_contains "$CTDD_SKILL" \
    '^> 6\.' \
    "R-005: ctdd SKILL.md has numbered check '> 6.'"

  local check6_line
  check6_line="$(grep -A 2 '^> 6\.' "$CTDD_SKILL" 2>/dev/null)"

  local has_anchor="no"
  echo "$check6_line" | grep -qi 'hand-rolled mock\|hand-rolled stub' && has_anchor="yes"
  assert_eq "R-005: check 6 contains 'hand-rolled mock' or 'hand-rolled stub' anchor" "yes" "$has_anchor"
}

# ============================================
# R-006 [integration]: ctdd audit check 7 exists with anchor
# ============================================

test_r006_ctdd_check7() {
  echo ""
  echo "=== R-006: ctdd audit check 7 exists with 'execution evidence' anchor ==="

  file_contains "$CTDD_SKILL" \
    '^> 7\.' \
    "R-006: ctdd SKILL.md has numbered check '> 7.'"

  local check7_line
  check7_line="$(grep -A 2 '^> 7\.' "$CTDD_SKILL" 2>/dev/null)"

  local has_anchor="no"
  echo "$check7_line" | grep -qi 'execution evidence' && has_anchor="yes"
  assert_eq "R-006: check 7 contains 'execution evidence' anchor" "yes" "$has_anchor"
}

# ============================================
# R-007 [unit]: Scanner rule subsections exist
# ============================================

test_r007_scanner_rules() {
  echo ""
  echo "=== R-007: Scanner rule fields with deferred + language patterns ==="

  # Extract each AP block and check Scanner rule content
  local ap016_block ap017_block ap018_block

  ap016_block="$(sed -n '/### AP-016/,/### AP-0/p' "$ANTIPATTERNS" 2>/dev/null)"
  ap017_block="$(sed -n '/### AP-017/,/### AP-0/p' "$ANTIPATTERNS" 2>/dev/null)"
  ap018_block="$(sed -n '/### AP-018/,$ p' "$ANTIPATTERNS" 2>/dev/null)"

  # Each Scanner rule must contain "deferred"
  local ap016_deferred="no"
  echo "$ap016_block" | grep -A 3 '\*\*Scanner rule\*\*:' | grep -qi 'deferred' && ap016_deferred="yes"
  assert_eq "R-007: AP-016 Scanner rule mentions 'deferred'" "yes" "$ap016_deferred"

  local ap017_deferred="no"
  echo "$ap017_block" | grep -A 3 '\*\*Scanner rule\*\*:' | grep -qi 'deferred' && ap017_deferred="yes"
  assert_eq "R-007: AP-017 Scanner rule mentions 'deferred'" "yes" "$ap017_deferred"

  local ap018_deferred="no"
  echo "$ap018_block" | grep -A 3 '\*\*Scanner rule\*\*:' | grep -qi 'deferred' && ap018_deferred="yes"
  assert_eq "R-007: AP-018 Scanner rule mentions 'deferred'" "yes" "$ap018_deferred"

  # Each entry's scanner rule must mention at least one language-specific pattern
  # relevant to its detection (not pooled across all three)
  local ap016_scanner
  ap016_scanner="$(echo "$ap016_block" | sed -n '/\*\*Scanner rule\*\*/,/\*\*[A-Z]/p' 2>/dev/null)"
  local ap016_has_lang="no"
  echo "$ap016_scanner" | grep -qiE 'endpoint|path|method|route' && ap016_has_lang="yes"
  assert_eq "R-007: AP-016 Scanner rule mentions endpoint/path/method detection" "yes" "$ap016_has_lang"

  local ap017_scanner
  ap017_scanner="$(echo "$ap017_block" | sed -n '/\*\*Scanner rule\*\*/,/\*\*[A-Z]/p' 2>/dev/null)"
  local ap017_has_lang="no"
  echo "$ap017_scanner" | grep -qiE 'go:generate|mockgen|moq|unittest\.mock|mock.framework|jest\.mock' && ap017_has_lang="yes"
  assert_eq "R-007: AP-017 Scanner rule mentions mock generator patterns" "yes" "$ap017_has_lang"

  local ap018_scanner
  ap018_scanner="$(echo "$ap018_block" | sed -n '/\*\*Scanner rule\*\*/,/\*\*[A-Z]/p' 2>/dev/null)"
  local ap018_has_lang="no"
  echo "$ap018_scanner" | grep -qiE 'timestamp|execution.log|test.output|duration|docker' && ap018_has_lang="yes"
  assert_eq "R-007: AP-018 Scanner rule mentions execution evidence patterns" "yes" "$ap018_has_lang"
}

# ============================================
# R-008 [unit]: Source and Frequency fields
# ============================================

test_r008_source_frequency() {
  echo ""
  echo "=== R-008: Source fields cite Andrew/clawker; Frequency fields use external format ==="

  local ap016_block ap017_block ap018_block

  ap016_block="$(sed -n '/### AP-016/,/### AP-0/p' "$ANTIPATTERNS" 2>/dev/null)"
  ap017_block="$(sed -n '/### AP-017/,/### AP-0/p' "$ANTIPATTERNS" 2>/dev/null)"
  ap018_block="$(sed -n '/### AP-018/,$ p' "$ANTIPATTERNS" 2>/dev/null)"

  # Source fields must contain "Andrew" and "clawker"
  for entry_id in "AP-016" "AP-017" "AP-018"; do
    local block
    case "$entry_id" in
      AP-016) block="$ap016_block" ;;
      AP-017) block="$ap017_block" ;;
      AP-018) block="$ap018_block" ;;
    esac

    local source_has_andrew="no"
    echo "$block" | grep -A 1 '\*\*Source\*\*:' | grep -qi 'Andrew' && source_has_andrew="yes"
    assert_eq "R-008: $entry_id Source cites 'Andrew'" "yes" "$source_has_andrew"

    local source_has_clawker="no"
    echo "$block" | grep -A 1 '\*\*Source\*\*:' | grep -qi 'clawker' && source_has_clawker="yes"
    assert_eq "R-008: $entry_id Source cites 'clawker'" "yes" "$source_has_clawker"

    local freq_has_zero="no"
    echo "$block" | grep -A 1 '\*\*Frequency\*\*:' | grep -qi '0 findings in-project' && freq_has_zero="yes"
    assert_eq "R-008: $entry_id Frequency says '0 findings in-project'" "yes" "$freq_has_zero"

    local freq_has_external="no"
    echo "$block" | grep -A 1 '\*\*Frequency\*\*:' | grep -qi 'external report' && freq_has_external="yes"
    assert_eq "R-008: $entry_id Frequency says 'external report'" "yes" "$freq_has_external"
  done
}

# ============================================
# R-009 [unit]: Drift test — corpus ↔ audit prompt correspondence
# ============================================

test_r009_corpus_audit_drift() {
  echo ""
  echo "=== R-009: Drift test — AP-016/017/018 ↔ ctdd checks 5/6/7 ==="

  # Count AP-016/017/018 headings in antipatterns.md
  local corpus_count
  corpus_count="$(grep -c '### AP-01[678]:' "$ANTIPATTERNS" 2>/dev/null)" || corpus_count=0

  # Count numbered checks 5/6/7 in ctdd SKILL.md audit blockquote
  local audit_count
  audit_count="$(grep -c '^> [567]\.' "$CTDD_SKILL" 2>/dev/null)" || audit_count=0

  assert_eq "R-009: corpus has 3 entries (AP-016/017/018)" "3" "$corpus_count"
  assert_eq "R-009: audit prompt has 3 checks (5/6/7)" "3" "$audit_count"

  # Only check correspondence if both counts are non-zero (prevent vacuous pass)
  if [ "$corpus_count" -eq 0 ] && [ "$audit_count" -eq 0 ]; then
    echo "  FAIL: R-009: corpus count matches audit count (both 0 — vacuously equal, not meaningful)"
    FAIL=$((FAIL + 1))
  else
    assert_eq "R-009: corpus count matches audit count (1:1)" "$corpus_count" "$audit_count"
  fi

  # Content-pairing: verify each AP entry's anchor appears in its corresponding check
  # AP-016 ↔ check 5 (anchor: "spec-named")
  local check5_has_anchor="no"
  grep '^> 5\.' "$CTDD_SKILL" 2>/dev/null | grep -qi 'spec-named' && check5_has_anchor="yes"
  assert_eq "R-009: check 5 pairs with AP-016 (contains 'spec-named')" "yes" "$check5_has_anchor"

  # AP-017 ↔ check 6 (anchor: "hand-rolled mock")
  local check6_has_anchor="no"
  grep '^> 6\.' "$CTDD_SKILL" 2>/dev/null | grep -qi 'hand-rolled mock\|hand-rolled stub' && check6_has_anchor="yes"
  assert_eq "R-009: check 6 pairs with AP-017 (contains 'hand-rolled mock')" "yes" "$check6_has_anchor"

  # AP-018 ↔ check 7 (anchor: "execution evidence")
  local check7_has_anchor="no"
  grep '^> 7\.' "$CTDD_SKILL" 2>/dev/null | grep -qi 'execution evidence' && check7_has_anchor="yes"
  assert_eq "R-009: check 7 pairs with AP-018 (contains 'execution evidence')" "yes" "$check7_has_anchor"
}

# ============================================
# Runner
# ============================================

echo "============================================="
echo "Test Evasion Antipatterns — AP-016/017/018"
echo "============================================="

# R-001: AP-016 entry
test_r001_ap016_entry

# R-002: AP-017 entry
test_r002_ap017_entry

# R-003: AP-018 entry
test_r003_ap018_entry

# R-004: ctdd check 5
test_r004_ctdd_check5

# R-005: ctdd check 6
test_r005_ctdd_check6

# R-006: ctdd check 7
test_r006_ctdd_check7

# R-007: Scanner rules
test_r007_scanner_rules

# R-008: Source/Frequency fields
test_r008_source_frequency

# R-009: Drift test
test_r009_corpus_audit_drift

echo ""
echo "============================================="
echo "Results: $PASS passed, $FAIL failed"
echo ""

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
