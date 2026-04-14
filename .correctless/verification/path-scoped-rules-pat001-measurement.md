# PAT-001 Measurement Gate Evaluation

**Date**: 2026-04-14
**Evaluator**: Manual git archaeology (MG-003 procedure)
**Trigger**: 4 hook-touching PRs post-migration (threshold: 3, overdue by 1)
**Feature A merge commit**: e038bc2
**Evaluation commit**: 587f00a

## Classification

**Result: `prevention_observed` (qualified)**

Confidence: indirect-proxy based. Feature B (InstructionsLoaded hook) has not
shipped; MG-001 was evaluated via the indirect proxy defined in the spec:
"check whether the rule file existed at the time of each hook edit, and whether
a violation was introduced."

## Evidence

### Hook-touching PRs since Feature A merge

| PR | Description | Lines Changed (hooks) | Clause-5 Violations |
|----|-------------|-----------------------|---------------------|
| #55 | Auto Mode Phase 2 | sensitive-file-guard: +4 (protected patterns) | None |
| #58 | QA Olympics (80 fixes) | sensitive-file-guard: +69, workflow-gate: +19 | None |
| #61 | Move installed scripts | Both hooks: +4 each (lib.sh path update) | None |
| #63 | Fix gate path exceptions | workflow-gate: +11 (spec path exception) | None |

### Searches performed

1. `git log -G '|| exit 0'` on both hooks — found 4 PRs touching files containing the pattern; all instances are pre-existing (lines 94, 97 of workflow-gate.sh), documented, and not on parse/error paths.
2. `git log -G 'exit 0.*jq\|jq.*exit 0'` — zero results.
3. `git log -G 'exit [^02]'` — zero results.
4. Manual diff inspection of all 4 PRs — no new fail-open paths, no silent degradation, no `|| exit 0` on error paths.

### PAT-005 and PAT-006 compliance

- PAT-005 (PostToolUse fail-open): Both PostToolUse hooks compliant. No `set -euo pipefail`, no `exit 2` on code paths.
- PAT-006 (metadata headers): All 5 registered hooks have `HOOK_TYPE:` headers. Two utility scripts (statusline.sh, workflow-advance.sh) lack them — pre-existing, not Claude Code hooks.

### Structural drift test

57/57 assertions pass (tests/test-architecture-drift.sh).

## Caveats

### Sample size

Four PRs is a small sample. Zero violations could reflect the rule working, author awareness of the active experiment, change profiles that didn't tempt the failure mode, or chance. With four data points, these are indistinguishable.

### Causation not established

The indirect proxy's structural weakness: "violations would have been introduced without the rule" is unprovable. The counterfactual is unobservable. The data shows correlation (rule present + no violations), not causation (rule caused no violations).

### Confound: author awareness

The experiment was actively discussed in CLAUDE.md and the spec. Authors editing hooks during this window knew the experiment was running. This awareness itself could have prevented violations — making it impossible to attribute the outcome to the rule file vs the experiment's visibility.

### Persistence ceiling vacuously satisfied

MG-002 requires violations that persist across 3+ PRs. No violations exist, so the ceiling is trivially met. MG-002 provides no information in the zero-violation case.

### Enforcement mechanism is layered, not purely advisory

The rule file at `.claude/rules/hooks-pretooluse.md` is **advisory** — loaded into LLM context during hook edits. It does not structurally prevent violations.

Structural enforcement exists independently via CI tests:
- `test_da003_fail_closed_on_jq_failure` in tests/test-workflow-gate.sh
- Corrupt config and malformed stdin tests in both test files
- tests/test-architecture-drift.sh (57 assertions on rule file integrity)

These CI tests predate the rule file migration and would catch clause-5 violations regardless. The rule file's unique contribution is **awareness at edit time** (prevention layer), while CI provides **detection after introduction** (safety net). Whether the advisory layer prevented anything that CI wouldn't have caught is indeterminate.

"Prevention" in `prevention_observed` means "no violation appeared" — not "the rule structurally blocked a violation attempt." The mechanism is awareness, not enforcement.

## Decision

**Accept the feature.** The rule file stays in place. Rationale:

1. Zero violations across 4 PRs including one major bulk edit (PR #58, 87 lines across both hooks) — the exact change profile that produced QA-R1-004/005 pre-migration.
2. The indirect proxy passed: rule existed during all edits, no violations introduced.
3. Continuing to wait for Feature B (direct measurement) offers diminishing returns — the gate's purpose was to force a decision at a defined trigger, not to wait indefinitely for perfect data.
4. The cost of keeping the rule file is near-zero (one file, no runtime overhead). The cost of rolling back (PRH-002) is non-trivial and destroys infrastructure that's working.

## Continued monitoring

- Rule file remains in place. Future hook edits are observed.
- Feature B (InstructionsLoaded hook) upgrades the signal from indirect proxy to direct observation if/when it ships. No longer gating — it's a signal upgrade, not a prerequisite.
- If a clause-5 violation is introduced in a future PR despite the rule being loaded, that's a meaningful negative signal worth recording — it would mean the advisory layer failed and the safety net (CI) caught it.

## Meta: experimental discipline

The measurement gate functioned as designed:

1. Gate was set up at Feature A merge (2026-04-10) with specific trigger (3 PRs), criteria (MG-001/002), and rollback procedure (PRH-002).
2. Trigger fired at 4 PRs (overdue by 1 — within reasonable tolerance).
3. Evaluation was performed with available data (indirect proxy, not ideal but defined in the spec).
4. Decision was recorded with explicit confidence level and caveats.
5. The experiment continues with monitoring rather than being abandoned or left pending.

This is the falsifiable experimental loop functioning correctly. Future measurement gates should cite this evaluation as precedent: gates fire on time, decisions are recorded with appropriate confidence, and "qualified positive" is a valid outcome when the data supports it but doesn't prove causation.
