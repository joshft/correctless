# Verification: Token Tracking

## Rule Coverage

| Rule | Test File | Status | Notes |
|------|-----------|--------|-------|
| R-001 [unit] | test-token-tracking.sh | covered | 10 assertions: 7 non-Agent tools exit 0, no log created, Agent exit 0, Agent creates log |
| R-002 [unit] | test-token-tracking.sh | covered | 8 assertions: 4 known values, 4 missing-defaults-to-0 |
| R-003 [unit] | test-token-tracking.sh | covered | 4 assertions: description, type, missing-desc, missing-type |
| R-004 [integration] | test-token-tracking.sh | covered | 4 assertions: phase from state, different phase, missing→"none", canary slug wiring |
| R-005 [unit] | test-token-tracking.sh | covered | 5 assertions: 2 lines after 2 runs, valid JSON per line, 3 after 3, jq -s consumable |
| R-006 [unit] | test-token-tracking.sh | covered | 19 assertions: 11 field presence, total_tokens=450 (hardcoded), ISO 8601, branch, phase, feature, desc, type, feature-default-unknown |
| R-007 [static] | test-token-tracking.sh | covered | 3 assertions: max 2 jq invocations, no $() in loops, no disallowed commands |
| R-008 [integration] | test-token-tracking-setup.sh | covered | 8 assertions: PostToolUse entry exists, matcher=Agent, path contains token-tracking.sh, preserves audit-trail, preserves gate, fresh install |
| R-009 [static] | test-token-tracking.sh | covered | 6 assertions: no set -e, || exit 0 guards, command -v jq check, no exit 2, eval+jq @sh, ends with exit 0 |
| R-010 [unit] | test-token-tracking.sh | covered | 5 assertions: broken JSON, unreadable state, unwritable dir, empty stdin, no exit [1-9] |
| R-011 [unit] | test-token-tracking.sh | covered | 4 assertions: sources lib.sh, no local branch_slug, calls branch_slug in code, exits 0 when lib.sh missing |
| R-012 [integration] | test-token-tracking-setup.sh | covered | 9 assertions: idempotent (1 entry after 2 runs), no duplicate audit-trail, coexistence, different matchers |
| PRH-001 | test-token-tracking.sh | covered | via R-010e: no exit [1-9] in source |
| PRH-002 | test-token-tracking.sh | covered | 2 assertions: no stdout for Agent tool, no stdout for non-Agent tool |
| PRH-003 | test-token-tracking.sh | covered | 3 assertions: no .result in jq, no result/RESULT variable, TB-003 comment present |

**Coverage: 12/12 rules + 3/3 prohibitions covered, 0 uncovered, 0 weak.**

## Dependencies

No new dependencies introduced. Pure bash implementation using jq (already required by ENV-002), date, cat, mkdir — standard POSIX utilities.

## Architecture Compliance

- ✓ **ABS-001**: Hook sources scripts/lib.sh for branch_slug() and artifacts_dir(). No local function duplication.
- ✓ **ABS-003**: State file read is read-only (no modification) — locking not required per ABS-003 invariant.
- ✓ **TB-003**: tool_response.result never extracted. No .result in jq paths. No result/RESULT variables. Comment documents trust boundary asymmetry between .result and .description.
- ✓ **PAT-002**: Token tracking is a separate hook from audit-trail, workflow-gate, etc.
- ! **PAT-005**: PostToolUse conventions implemented correctly but PAT-005 not yet defined in ARCHITECTURE.md — needs entry via /cupdate-arch.

## QA Class Fixes Verified

- **QA-001**: Class fix implemented — jq handles all JSON construction (no manual escaping). Eliminates "forgot to escape X" class. ✓
- **QA-002**: R-007c test allowlist tightened ✓
- **QA-006**: Automatically fixed by QA-001 (jq handles numeric types) ✓

## Antipattern Scan

0 findings in changed files. No TODOs, FIXMEs, debug statements, or commented-out code.

## Smells

None found in changed production files.

## Drift

Two items — both in the spec's explicit scope but not yet implemented:

1. **DRIFT-001**: `/cmetrics` SKILL.md (lines 35, 205) still references `token-log-*.json` instead of `token-log-*.jsonl`. The spec scope says: "Update `/cmetrics` SKILL.md glob from `token-log-*.json` to `token-log-*.jsonl`".
2. **DRIFT-002**: Shared constraints (`_shared/constraints.md` line 30) still references `token-log-{slug}.json` instead of `.jsonl`. The spec scope says: "Update shared constraints token tracking section to reference the new JSONL format".

## Spec Updates

No spec updates during TDD. Spec was finalized during /creview-spec.

## Overall: PASS with 2 drift items — 92 tests pass (75 + 17). 12/12 rules + 3/3 prohibitions covered. No new dependencies. Architecture compliant except PAT-005 entry needed.
