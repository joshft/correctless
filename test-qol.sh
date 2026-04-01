#!/usr/bin/env bash
# Correctless — QoL improvement tests
# Tests spec rules R-001 through R-015
# Run from repo root: bash test-qol.sh

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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

file_exists() {
  [ -f "$1" ]
}

file_contains() {
  grep -q "$2" "$1" 2>/dev/null
}

file_contains_i() {
  grep -qi "$2" "$1" 2>/dev/null
}

# ===========================================================================
echo "=== /cquick — Lightweight Mode ==="
# ===========================================================================

# R-001: skills/cquick/SKILL.md exists with frontmatter containing name: cquick
echo "--- R-001: /cquick skill file exists with correct frontmatter ---"
CQUICK="$REPO_DIR/skills/cquick/SKILL.md"

if file_exists "$CQUICK"; then
  assert_eq "R-001a: skills/cquick/SKILL.md exists" "yes" "yes"
else
  assert_eq "R-001a: skills/cquick/SKILL.md exists" "yes" "no"
fi

if file_contains "$CQUICK" "^name: cquick"; then
  assert_eq "R-001b: frontmatter contains name: cquick" "yes" "yes"
else
  assert_eq "R-001b: frontmatter contains name: cquick" "yes" "no"
fi

# R-002: SKILL.md contains TDD instruction and main/master branch guard
echo "--- R-002: TDD instruction and branch guard ---"

if file_contains "$CQUICK" "test.*implement.*verify\|write test.*implement"; then
  assert_eq "R-002a: contains TDD instruction (test -> implement -> verify)" "yes" "yes"
else
  assert_eq "R-002a: contains TDD instruction (test -> implement -> verify)" "yes" "no"
fi

if file_contains "$CQUICK" "main\|master"; then
  has_branch_guard="yes"
else
  has_branch_guard="no"
fi
if file_contains "$CQUICK" "branch"; then
  : # additional check
else
  has_branch_guard="no"
fi
assert_eq "R-002b: contains main/master branch guard" "yes" "$has_branch_guard"

# R-003: SKILL.md contains scope guard with 50 LOC and 3 files thresholds
echo "--- R-003: Scope guard thresholds ---"

if file_contains "$CQUICK" "50.*LOC\|50 LOC\|50 lines"; then
  assert_eq "R-003a: contains 50 LOC threshold" "yes" "yes"
else
  assert_eq "R-003a: contains 50 LOC threshold" "yes" "no"
fi

if file_contains "$CQUICK" "3 files\|3.*files"; then
  assert_eq "R-003b: contains 3 files threshold" "yes" "yes"
else
  assert_eq "R-003b: contains 3 files threshold" "yes" "no"
fi

if file_contains_i "$CQUICK" "cspec"; then
  assert_eq "R-003c: scope guard references /cspec escalation" "yes" "yes"
else
  assert_eq "R-003c: scope guard references /cspec escalation" "yes" "no"
fi

# R-004: SKILL.md requires tests before implementing
echo "--- R-004: Tests required before implementing ---"

if file_contains_i "$CQUICK" "write.*test.*before\|test.*before.*implement\|at least one test"; then
  assert_eq "R-004: requires writing tests before implementing" "yes" "yes"
else
  assert_eq "R-004: requires writing tests before implementing" "yes" "no"
fi

# R-005: sync.sh Lite and Full skill lists contain "cquick"
echo "--- R-005: cquick in sync.sh skill lists ---"
SYNC="$REPO_DIR/sync.sh"

# Check Lite list (the first for-loop listing skills — does not contain cmodel)
lite_line=$(grep "^for skill in" "$SYNC" | grep -v "cmodel" | head -1)
if echo "$lite_line" | grep -q "cquick"; then
  assert_eq "R-005a: cquick in Lite skill list" "yes" "yes"
else
  assert_eq "R-005a: cquick in Lite skill list" "yes" "no"
fi

# Check Full list (the for-loop listing skills — contains cmodel)
full_line=$(grep "^for skill in.*cmodel" "$SYNC" | head -1)
if echo "$full_line" | grep -q "cquick"; then
  assert_eq "R-005b: cquick in Full skill list" "yes" "yes"
else
  assert_eq "R-005b: cquick in Full skill list" "yes" "no"
fi

# R-006: chelp SKILL.md lists /cquick in commands section
echo "--- R-006: /cquick listed in /chelp ---"
CHELP="$REPO_DIR/skills/chelp/SKILL.md"

if file_contains "$CHELP" "/cquick"; then
  assert_eq "R-006: /chelp lists /cquick command" "yes" "yes"
else
  assert_eq "R-006: /chelp lists /cquick command" "yes" "no"
fi

# ===========================================================================
echo ""
echo "=== Workflow History ==="
# ===========================================================================

# R-007: cdocs SKILL.md contains workflow-history instruction
echo "--- R-007: /cdocs appends to workflow-history.md ---"
CDOCS="$REPO_DIR/skills/cdocs/SKILL.md"

if file_contains "$CDOCS" "workflow-history"; then
  assert_eq "R-007a: /cdocs references workflow-history.md" "yes" "yes"
else
  assert_eq "R-007a: /cdocs references workflow-history.md" "yes" "no"
fi

# Check for required fields in the workflow history instruction
r007_fields_found=0
for field in "date" "feature name" "branch" "rules count" "QA rounds" "findings fixed"; do
  if file_contains_i "$CDOCS" "$field"; then
    r007_fields_found=$((r007_fields_found + 1))
  fi
done
if [ "$r007_fields_found" -ge 5 ]; then
  assert_eq "R-007b: workflow history includes required fields (date, feature, branch, rules, QA, findings)" "yes" "yes"
else
  assert_eq "R-007b: workflow history includes required fields (date, feature, branch, rules, QA, findings)" "yes" "no (found $r007_fields_found/6)"
fi

# R-008: cdocs SKILL.md contains append-only instruction
echo "--- R-008: workflow history is append-only ---"

if file_contains_i "$CDOCS" "append-only\|append only\|never rewrite\|never delete"; then
  assert_eq "R-008: /cdocs has append-only instruction for workflow history" "yes" "yes"
else
  assert_eq "R-008: /cdocs has append-only instruction for workflow history" "yes" "no"
fi

# R-009: .gitignore does NOT contain workflow-history
echo "--- R-009: workflow-history.md is not gitignored ---"
GITIGNORE="$REPO_DIR/.gitignore"

if file_contains "$GITIGNORE" "workflow-history"; then
  assert_eq "R-009: workflow-history.md is NOT gitignored" "yes" "no"
else
  assert_eq "R-009: workflow-history.md is NOT gitignored" "yes" "yes"
fi

# ===========================================================================
echo ""
echo "=== Time-in-Phase Display ==="
# ===========================================================================

# R-010: cstatus SKILL.md contains duration calculation instruction
echo "--- R-010: /cstatus calculates time in current phase ---"
CSTATUS="$REPO_DIR/skills/cstatus/SKILL.md"

# The spec requires display format: "Phase: {phase} ({duration})"
if file_contains "$CSTATUS" 'Phase:.*{phase}.*{duration}\|Phase:.*({duration})'; then
  assert_eq "R-010a: /cstatus shows phase with duration format" "yes" "yes"
else
  assert_eq "R-010a: /cstatus shows phase with duration format" "yes" "no"
fi

# Check for human-readable duration examples
if file_contains_i "$CSTATUS" "minutes.*hours\|human-readable.*duration\|12 minutes\|2 hours\|1 day"; then
  assert_eq "R-010b: /cstatus uses human-readable duration format" "yes" "yes"
else
  assert_eq "R-010b: /cstatus uses human-readable duration format" "yes" "no"
fi

# R-011: cstatus SKILL.md contains threshold warnings
echo "--- R-011: /cstatus warns at time thresholds ---"

# Check for >1 hour threshold
if file_contains_i "$CSTATUS" '>.*1 hour\|more than.*1 hour\|exceeds.*1 hour\|1 hour.*re-run\|1 hour.*suggest'; then
  assert_eq "R-011a: /cstatus warns at >1 hour threshold" "yes" "yes"
else
  assert_eq "R-011a: /cstatus warns at >1 hour threshold" "yes" "no"
fi

# Check for >24 hours threshold (already exists for stale, but spec wants it in new format)
if file_contains_i "$CSTATUS" '>.*24 hour.*stall\|24 hour.*stalled\|workflow may be stalled'; then
  assert_eq "R-011b: /cstatus warns at >24 hours (stalled)" "yes" "yes"
else
  assert_eq "R-011b: /cstatus warns at >24 hours (stalled)" "yes" "no"
fi

# ===========================================================================
echo ""
echo "=== Spec Templates ==="
# ===========================================================================

# R-012: templates/spec-lite.md exists with required sections
echo "--- R-012: Lite spec template ---"
SPEC_LITE="$REPO_DIR/templates/spec-lite.md"

if file_exists "$SPEC_LITE"; then
  assert_eq "R-012a: templates/spec-lite.md exists" "yes" "yes"
else
  assert_eq "R-012a: templates/spec-lite.md exists" "yes" "no"
fi

r012_sections=0
for section in "What" "Rules" "Won't Do" "Risks" "Open Questions"; do
  if file_contains "$SPEC_LITE" "^## *$section"; then
    r012_sections=$((r012_sections + 1))
  fi
done
if [ "$r012_sections" -ge 5 ]; then
  assert_eq "R-012b: spec-lite.md has all 5 section headers" "yes" "yes"
else
  assert_eq "R-012b: spec-lite.md has all 5 section headers" "yes" "no (found $r012_sections/5)"
fi

# R-013: templates/spec-full.md exists with required sections
echo "--- R-013: Full spec template ---"
SPEC_FULL="$REPO_DIR/templates/spec-full.md"

if file_exists "$SPEC_FULL"; then
  assert_eq "R-013a: templates/spec-full.md exists" "yes" "yes"
else
  assert_eq "R-013a: templates/spec-full.md exists" "yes" "no"
fi

r013_sections=0
for section in "Metadata" "Context" "Scope" "Invariants" "Prohibitions" "Open Questions"; do
  if file_contains "$SPEC_FULL" "^## *$section"; then
    r013_sections=$((r013_sections + 1))
  fi
done
if [ "$r013_sections" -ge 6 ]; then
  assert_eq "R-013b: spec-full.md has all 6 required section headers" "yes" "yes"
else
  assert_eq "R-013b: spec-full.md has all 6 required section headers" "yes" "no (found $r013_sections/6)"
fi

# R-014: cspec SKILL.md references template file
echo "--- R-014: /cspec reads template file ---"
CSPEC="$REPO_DIR/skills/cspec/SKILL.md"

if file_contains "$CSPEC" "templates/spec-lite\|templates/spec-full\|template.*file\|read.*template"; then
  assert_eq "R-014: /cspec references template file" "yes" "yes"
else
  assert_eq "R-014: /cspec references template file" "yes" "no"
fi

# ===========================================================================
echo ""
echo "=== Skill Registration ==="
# ===========================================================================

# R-015: docs/skills/cquick.md exists
echo "--- R-015: /cquick documentation page ---"
CQUICK_DOC="$REPO_DIR/docs/skills/cquick.md"

if file_exists "$CQUICK_DOC"; then
  assert_eq "R-015: docs/skills/cquick.md exists" "yes" "yes"
else
  assert_eq "R-015: docs/skills/cquick.md exists" "yes" "no"
fi

# ===========================================================================
echo ""
echo "==========================================="
echo "  Results: $PASS passed, $FAIL failed"
echo "==========================================="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
