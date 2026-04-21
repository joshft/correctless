#!/usr/bin/env bash
# shellcheck disable=SC2086
# Correctless — Dev Journal structural tests
#
# Verifies that /cdocs includes a dev journal step that appends
# implementation context to docs/dev-journal.md.
#
# Run from repo root: bash tests/test-dev-journal.sh

source "$(dirname "${BASH_SOURCE[0]}")/test-helpers.sh"

CDOCS_SKILL="skills/cdocs/SKILL.md"

echo "=== Dev Journal Tests ==="

# 1: cdocs SKILL.md mentions dev journal
if grep -qi 'dev.*journal\|development.*journal' "$CDOCS_SKILL"; then
  pass "DJ-001" "cdocs SKILL.md mentions dev journal"
else
  fail "DJ-001" "cdocs SKILL.md does not mention dev journal"
fi

# 2: cdocs SKILL.md has a journal section or step
if grep -qi 'journal' "$CDOCS_SKILL" && grep -qi 'append\|entry' "$CDOCS_SKILL"; then
  pass "DJ-002" "cdocs SKILL.md has journal append instructions"
else
  fail "DJ-002" "cdocs SKILL.md missing journal append instructions"
fi

# 3: journal step mentions docs/dev-journal.md as target
if grep -q 'docs/dev-journal.md' "$CDOCS_SKILL"; then
  pass "DJ-003" "cdocs SKILL.md references docs/dev-journal.md"
else
  fail "DJ-003" "cdocs SKILL.md does not reference docs/dev-journal.md"
fi

# 4: journal step mentions what to include (files, patterns, implementation)
if grep -qi 'files.*touched\|files.*changed\|patterns.*used\|how.*implemented\|what.*was.*built\|implementation.*context' "$CDOCS_SKILL"; then
  pass "DJ-004" "cdocs SKILL.md describes journal entry content"
else
  fail "DJ-004" "cdocs SKILL.md does not describe what journal entries contain"
fi

# 5: journal step specifies date/time in entries
if grep -qi 'date\|timestamp' "$CDOCS_SKILL" && grep -qi 'journal' "$CDOCS_SKILL"; then
  pass "DJ-005" "cdocs SKILL.md specifies date in journal entries"
else
  fail "DJ-005" "cdocs SKILL.md does not specify date in journal entries"
fi

# 6: journal step is append-only (consistent with workflow-history)
if grep -qi 'append.*journal\|journal.*append' "$CDOCS_SKILL"; then
  pass "DJ-006" "cdocs SKILL.md specifies append-only journal"
else
  fail "DJ-006" "cdocs SKILL.md does not specify append-only journal"
fi

# 7: cdocs allowed-tools includes Write(docs/*) — already covers docs/dev-journal.md
if head -5 "$CDOCS_SKILL" | grep -q 'Write(docs/\*)'; then
  pass "DJ-007" "cdocs allowed-tools covers docs/dev-journal.md"
else
  fail "DJ-007" "cdocs allowed-tools may not cover docs/dev-journal.md"
fi

echo ""
echo "========================================="
echo "  Dev Journal Tests: $PASS passed, $FAIL failed"
echo "========================================="
if [ -n "$FAILED_IDS" ]; then
  echo "  Failed: $FAILED_IDS"
fi
[ "$FAIL" -eq 0 ]
