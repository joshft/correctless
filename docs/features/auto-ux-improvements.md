---
title: Auto UX Improvements
parent: Features
---

# Auto UX Improvements

Three usability improvements to `/cauto` based on the first real pipeline run (scanner-expansion, 2026-04-13): flexible phase entry, scoped commit consolidation, and a structured pipeline summary.

## Flexible Phase Entry (R-001)

`/cauto` now accepts any active workflow phase, not just `review`/`review-spec`. Given the current phase, it computes the remaining pipeline steps using a fixed mapping:

| Current Phase | Remaining Steps |
|---|---|
| `review` / `review-spec` | Full pipeline |
| `tdd-tests` / `tdd-impl` / `tdd-qa` | Resume from `/ctdd` onward |
| `done` | `/simplify` onward |
| `verified` | `/cupdate-arch` (high+) onward |
| `documented` | Consolidation + PR only |

Phases `spec` and `model` are rejected -- the spec must be reviewed first.

### Artifact Validation (R-002)

Before skipping a completed phase, `/cauto` validates its artifacts exist:
- **ctdd**: test suite passes (configurable timeout via `commands.test_timeout`)
- **cverify**: verification report exists
- **simplify/cupdate-arch/cdocs**: no validation needed (optional/advisory)

If validation fails twice consecutively, the phase is re-run rather than skipped indefinitely.

## Scoped Commit Consolidation (R-003)

Between `/cdocs` and PR creation, `/cauto` runs a consolidation step that stages only known pipeline output paths (verification report, ARCHITECTURE.md, AGENT_CONTEXT.md, README.md, CONTRIBUTING.md, workflow history, feature docs). Unknown untracked files are never staged. A belt-and-suspenders guard unstages anything under `.correctless/artifacts/`.

Protected branch guard prevents pushes to `main`, `master`, `develop`, or `release/*`.

See TB-004c in `.correctless/ARCHITECTURE.md` for the trust boundary analysis.

## Pipeline Summary (R-004)

After PR creation, `/cauto` prints a structured summary with three sections:

1. **Findings & Decisions** -- every QA finding, verification finding, review decision, and override with dispositions. Truncation at >20 severity-bearing items shows HIGH/CRITICAL + deferred inline, with a count-and-reference for the rest.

2. **Phase Breakdown** -- a table showing skill name, duration, token count, and result per pipeline step. Duration uses `elapsed_ms` from the audit trail. Token counts from the token-log JSONL.

3. **Artifacts** -- file paths for spec, verification report, QA findings, audit trail, and PR URL.

## New Audit Trail Event (R-005)

`artifact_validation_failed` event type added (total: 8 event types). Includes `phase`, `expected_artifact`, and `validation_error` fields.

## Spec Reference

Full spec: `.correctless/specs/auto-ux-improvements.md` (7 rules)
