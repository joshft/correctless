#!/usr/bin/env bash
# shellcheck disable=SC2086
# Correctless — QA UNCERTAIN severity structural tests
#
# Verifies the QA agent in /ctdd supports UNCERTAIN severity for
# findings where the agent can't determine if an issue is real.
# Tests are scoped to the QA section of ctdd SKILL.md, not the
# mini-audit section (which already has UNCERTAIN from PR #69).
#
# Run from repo root: bash tests/test-qa-uncertain.sh

source "$(dirname "${BASH_SOURCE[0]}")/test-helpers.sh"

SKILL_FILE="skills/ctdd/SKILL.md"

# Extract the QA section (between "## Phase: QA" and the next "##" heading)
QA_SECTION=$(sed -n '/^## Phase: QA/,/^## /p' "$SKILL_FILE")

echo "=== QA UNCERTAIN Severity Tests ==="

# 1: QA agent severity list includes UNCERTAIN
if echo "$QA_SECTION" | grep -q 'UNCERTAIN'; then
  pass "QU-001" "QA section includes UNCERTAIN severity"
else
  fail "QU-001" "QA section does not include UNCERTAIN severity"
fi

# 2: QA agent output format shows UNCERTAIN as a valid severity value
if echo "$QA_SECTION" | grep -q 'BLOCKING|NON-BLOCKING|UNCERTAIN'; then
  pass "QU-002" "UNCERTAIN in QA output format severity options"
else
  fail "QU-002" "UNCERTAIN not in QA output format severity options"
fi

# 3: QA agent prompt explains when to use UNCERTAIN
if echo "$QA_SECTION" | grep -qi 'uncertain.*cannot.*determine\|uncertain.*not.*confident\|cannot.*confirm.*uncertain\|genuinely.*unsure'; then
  pass "QU-003" "QA prompt explains when to use UNCERTAIN"
else
  fail "QU-003" "QA prompt does not explain when to use UNCERTAIN"
fi

# 4: UNCERTAIN is non-blocking
if echo "$QA_SECTION" | grep -qi 'uncertain.*non-blocking\|uncertain.*advisory\|uncertain.*does.*not.*block'; then
  pass "QU-004" "UNCERTAIN is non-blocking in QA context"
else
  fail "QU-004" "UNCERTAIN blocking behavior not specified in QA section"
fi

# 5: QA findings JSON schema includes UNCERTAIN
if echo "$QA_SECTION" | grep -q '"severity":.*UNCERTAIN\|BLOCKING.*NON-BLOCKING.*UNCERTAIN'; then
  pass "QU-005" "QA findings JSON schema includes UNCERTAIN"
else
  fail "QU-005" "QA findings JSON schema missing UNCERTAIN"
fi

# 6: Instruction not to inflate uncertain issues
if echo "$QA_SECTION" | grep -qi 'do not.*inflate\|never.*inflate\|uncertainty.*valid\|honest.*uncertainty\|not.*silently.*inflate'; then
  pass "QU-006" "QA prompt warns against inflating uncertain findings"
else
  fail "QU-006" "QA prompt missing inflation warning"
fi

echo ""
echo "========================================="
echo "  QA UNCERTAIN Tests: $PASS passed, $FAIL failed"
echo "========================================="
if [ -n "$FAILED_IDS" ]; then
  echo "  Failed: $FAILED_IDS"
fi
[ "$FAIL" -eq 0 ]
