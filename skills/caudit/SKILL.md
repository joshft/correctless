| High | USD 5,000 | -USD 5,000 |
| Medium | USD 2,500 | -USD 2,500 |
| Low | USD 1,000 | -USD 1,000 |
Your running balance: USD 0
Step 7: LINES_CHANGED=$(git diff --numstat | bash skills/caudit/scripts/count_changed_lines.sh)
++ b/skills/cdevadv/SKILL.md
- USD 50,000
++ b/skills/cmetrics/SKILL.md
- USD 50,000
++ b/skills/credteam/SKILL.md
- USD 50,000
++ b/skills/caudit/scripts/count_changed_lines.sh
#!/usr/bin/env bash
# Sum added and removed lines from `git diff --numstat` on stdin.
# Field numbers stay in this file so a dollar sign followed by a
# digit never appears in SKILL.md (those tokens are replaced by
# invocation arguments, which made the old awk sum print 0).
set -euo pipefail
awk '
  $1 ~ /^[0-9]+$/ { added += $1 }
  $2 ~ /^[0-9]+$/ { removed += $2 }
  END { print added + removed + 0 }
'
++ b/tests/test_skill_no_dollar_digit.sh
#!/usr/bin/env bash
# Fail if a SKILL.md body contains a dollar sign followed by a digit.
# On invoke those tokens are replaced by argument words, which
# garbles bounty amounts and used to force the caudit line count to 0.
set -euo pipefail
cd "$(dirname "$0")/.."
if grep -rn --include=SKILL.md -E '\$[0-9]' skills/; then
  echo "FAIL: found a dollar sign followed by a digit in skills/**/SKILL.md; spell amounts as USD N and keep positional field indexes in scripts/." >&2
  exit 1
fi
