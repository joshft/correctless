#!/usr/bin/env bash
# Correctless — skill bodies must not contain a dollar sign followed by a digit
#
# When a skill is invoked with arguments, the host replaces positional
# placeholders ($1, $2, ...) in the skill body before the model sees it.
# Literal amounts like "$5,000" and awk fields like "$1" then turn into
# argument words (see #315). Spell amounts as "USD N" and write awk
# fields as "$(N)".
#
# Run from repo root: bash tests/test-skill-no-dollar-digit.sh

source "$(dirname "${BASH_SOURCE[0]}")/test-helpers.sh"

echo "=== Skill \$<digit> Placeholder Tests ==="

HITS="$(grep -rn --include=SKILL.md -E '\$[0-9]' skills/ correctless/skills/ 2>/dev/null || true)"
if [ -z "$HITS" ]; then
  pass "SDD-001" "no SKILL.md contains a dollar sign followed by a digit"
else
  fail "SDD-001" "dollar sign followed by a digit found in SKILL.md: $HITS"
fi

# The caudit Step 7 line count must still sum both numstat columns.
if grep -qF "awk '{added+=\$(1); removed+=\$(2)} END {print added+removed+0}'" skills/caudit/SKILL.md; then
  pass "SDD-002" "caudit LINES_CHANGED awk uses \$(1)/\$(2) field syntax"
else
  fail "SDD-002" "caudit LINES_CHANGED awk program not found in expected form"
fi

# And that awk program actually counts lines.
COUNT="$(printf '10\t5\tfile_a\n3\t0\tfile_b\n-\t-\tbin\n' | awk '{added+=$(1); removed+=$(2)} END {print added+removed+0}')"
if [ "$COUNT" = "18" ]; then
  pass "SDD-003" "awk field syntax sums numstat columns (got 18)"
else
  fail "SDD-003" "awk field syntax returned '$COUNT', expected 18"
fi

echo ""
echo "========================================="
echo "  Skill \$<digit> Tests: $PASS passed, $FAIL failed"
echo "========================================="
if [ -n "$FAILED_IDS" ]; then
  echo "  Failed: $FAILED_IDS"
fi
[ "$FAIL" -eq 0 ]
