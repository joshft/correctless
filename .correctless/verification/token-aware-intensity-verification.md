# Verification: Token-Aware Intensity Calibration

## Rule Coverage
| Rule | Test | Status | Notes |
|------|------|--------|-------|
| INV-001 | 001a-001h (8 assertions) | covered | actual_tokens field, branch_slug, jq -R summation, malformed skip, missing=0, integer |
| INV-002 | 002a-002d (4 assertions) | covered | Step 7b actual_tokens, average, zero/absent exclusion, QA unchanged |
| INV-003 | 003a-003d (4 assertions) | covered | 200K threshold, linked to actual_tokens, 3 thresholds same clause, disjunctive "or" |
| INV-004 | 004a-004d (4 assertions) | covered | passive display, sum/count/average, 200K comparison, example with tokens |
| INV-005 | 005a-005d (4 assertions) | covered | not skipped, QA/findings participation, token-only exclusion, legacy no error |
| INV-006 | 006a-006l (12 assertions) | covered | section name, 5 category mappings, sort, token-log, skill field, skip-with-note, slug+QA columns |
| INV-007 | 007a-007i (9 assertions) | covered | first/second half, odd→first, 20%, growing/shrinking/stable, insufficient<4, old text replaced |
| INV-008 | 008a-008i (9 assertions) | covered | 8 negative config checks, 1 positive cspec check |
| PRH-001 | 001a-001c (3 assertions) | covered | no uncommitted, staged, or branch diff on hooks/token-tracking.sh |
| PRH-002 | 002a-002e (5 assertions) | covered | Step 7 clean, Step 7b positive, no 5th signal |

**Total: 10/10 rules covered, 63 assertions, 63 passing**

## Dependencies
No new dependencies. Only SKILL.md files modified (LLM instructions).

## Architecture Compliance
- ✓ PAT-001: source-to-dist sync verified for cverify, cspec, cmetrics
- ✓ ABS-005: cverify writes actual_tokens, cspec reads — boundary maintained
- ✓ TB-001: no eval of config values — jq command is hardcoded prose
- ✓ PAT-005: hooks/token-tracking.sh unchanged (PRH-001)
- ✓ CI: test-token-aware-intensity.sh added to ci.yml and commands.test

## QA Class Fixes Verified
- QA-001: jq -s replaced with jq -R try/catch (malformed-line-safe) ✓
- QA-002: Bash(jq*) added to cverify allowed-tools ✓

## Smells
None found. 200,000 threshold is intentionally hardcoded per INV-008.

## Drift
None found across all 10 rules.

## Spec Updates
None — spec unchanged during TDD.

## Overall: PASS with 0 findings
