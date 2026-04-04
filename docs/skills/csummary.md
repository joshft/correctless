# /csummary — Feature Workflow Summary

> Generate a one-page report of everything the Correctless workflow caught during a feature.

## When to Use

- After `/cdocs` completes (end of a feature) to see the full picture of what the workflow caught.
- Mid-feature to check progress so far.
- Before creating a PR, to include the summary in the PR description.
- **Not for:** Project-wide metrics over time (use `/cmetrics`), or checking current phase (use `/cstatus`).

## How It Fits in the Workflow

This skill typically runs after `/cdocs` as the final step before merging. It aggregates findings from every earlier phase — review, test audit, QA, and verification — into a single report. The summary can be exported and included in a PR description to show reviewers what the workflow already caught.

## What It Does

- Reads the spec file and identifies rules added during review (rules the original author did not think of).
- Reads QA findings, verification reports, test edit logs, and audit trails to gather every issue caught.
- Calculates stats: total issues, issues by phase, QA rounds, spec updates, and branch duration.
- **Classifies impact**: For each issue, assesses whether it "would have shipped" to production without the workflow, "might have been caught" by a careful developer, or was "cosmetic." The "would have shipped" count is the headline number.
- Writes the summary to `.correctless/artifacts/summary-{task-slug}.md` and prints it to the conversation.

## Example

```
User: /csummary

# Workflow Summary: Rate Limiting for Login

Branch: feature/rate-limiting
Duration: 2 days
Spec: .correctless/specs/rate-limiting.md

## What the Workflow Caught

### Review found (3 issues):
- Added R-006: CSRF protection on rate-limit reset endpoint (security checklist)
- Added R-007: Rate limit counter must survive deploys (antipattern AP-012)
- Flagged missing test for concurrent login attempts

### /ctdd QA found (5 issues, 2 rounds):
- Mock gap: Redis client was mocked, hiding a serialization bug
- Missing edge case: rate limit window boundary (off-by-one)
- Assertion weakness: test checked status code but not response body
- Integration test missing for middleware chain ordering
- Error path: Redis connection failure returned 500 instead of fallback

### /cverify found (1 issue):
- R-004 (audit logging) had a test but the assertion was too weak to fail on regression

## Stats
- Total issues caught: 9
- Would have shipped without workflow: 6 (67%)
- QA rounds: 2
- Spec updates: 0
```

## What It Reads / Writes

| Reads | Writes |
|-------|--------|
| `.correctless/specs/{task-slug}.md` | `.correctless/artifacts/summary-{task-slug}.md` |
| `.correctless/artifacts/qa-findings-{task-slug}.json` | |
| `docs/verification/{task-slug}-verification.md` | |
| `.correctless/artifacts/tdd-test-edits.log` | |
| `.correctless/artifacts/audit-trail-*.jsonl` | |
| Workflow state file | |
| Git log (branch duration, commit count) | |

## Lite vs Full

Same in both modes. The summary reports whatever phases actually ran. Full mode features that ran (model, audit) will appear in the summary if their artifacts exist.

## Common Issues

- **Missing artifacts**: If a phase has not run yet, the summary skips that section. Run `/csummary` after more phases complete for a fuller report.
- **"Would have shipped" numbers seem high**: The classification is intentionally conservative. Only issues where a developer clearly would not have caught them without the workflow are counted. When in doubt, the skill classifies as "might have been caught."
- **Duplicate findings across phases**: The skill deduplicates. If review and QA both caught the same issue, it is counted once at the earliest phase.
