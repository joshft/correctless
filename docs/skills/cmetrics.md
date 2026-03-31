# /cmetrics — Workflow Metrics Dashboard

> Aggregate all workflow data into a project health and ROI dashboard showing bugs caught, token cost, and trends.

## When to Use

- Monthly, to track how the workflow is performing over time.
- Before presenting to stakeholders, to justify the workflow investment with data.
- When deciding whether to upgrade from Lite to Full mode.
- When something feels off — metrics reveal which phases are pulling weight and which are not.
- **Not for:** Single-feature summaries (use `/csummary`), or checking current workflow state (use `/cstatus`).

## How It Fits in the Workflow

This skill is standalone and project-wide. It reads accumulated data from every feature that has gone through the Correctless workflow — QA findings, verification reports, antipatterns, drift debt, audit history, token logs, and git history. It produces a comprehensive dashboard with actionable health analysis. Run it periodically to spot trends.

## What It Does

- Counts features completed, total issues caught (deduplicated across phases), and bug escape rate.
- Breaks down issues by phase (Review, Test Audit, QA, Verify, Audit) to show where value concentrates.
- Tracks antipattern growth by category, flagging systemic issues that may need architectural fixes.
- Monitors drift debt health: open items, staleness, accumulation vs. resolution rate.
- **Token ROI Analysis**: Reads `.claude/artifacts/token-log-*.json` to compute cost per bug caught, tokens per feature by phase, tokens per LOC, and estimated production fix cost avoided. Shows whether token spend is efficient (e.g., "65% of tokens go to TDD, which catches 60% of bugs").
- **Session Analytics**: Reads Claude Code `session-meta` and `facets` data from `~/.claude/usage-data/`, filtered to the current project. Reports exact token cost (ground truth), tool distribution, friction rate, user engagement, and outcome rate.
- **Correctless vs Freeform comparison**: Identifies which sessions used Correctless (by checking artifact timestamps and tool patterns) vs. freeform coding, then compares outcome rate, friction, duration, and token usage between the two groups.
- Cross-metric correlation analysis: flags patterns like "specs revised mid-TDD frequently AND antipattern growth accelerating in the same category."

## Example

```
User: /cmetrics

# Correctless Metrics — my-project
# Generated: 2026-03-29

## Overview
- Features completed: 8
- Total issues caught: 47
- Bug escape rate: 2 escaped / 47 caught (4.1%)
- Workflow active since: 2026-01-15

## Issues by Phase
| Phase        | Issues | % of Total | Notes                              |
|--------------|--------|------------|------------------------------------|
| Review       | 12     | 25%        | Security checklist added 40% of these |
| QA           | 22     | 47%        | 5 class fixes added structural tests  |
| Verify       | 8      | 17%        |                                    |
| Audit        | 5      | 11%        |                                    |

## Token ROI Analysis
- Total tokens tracked: 2.4M across 8 features
- Cost per bug caught: ~51k tokens (47 bugs)
- Estimated production fix cost avoided: 47 bugs x 2-10 hrs = 94-470 hrs

## Session Analytics
- Correctless sessions: 62% fully achieved outcome
- Freeform sessions: 41% fully achieved outcome

## Health Analysis
- QA rounds trending down (3.1 -> 2.3 avg) — workflow getting more effective.
- Error handling antipatterns growing fastest (+4 in 3 months). Consider architectural pattern.
- Spec revision rate: 25% of features — acceptable.
```

## What It Reads / Writes

| Reads | Writes |
|-------|--------|
| `.claude/artifacts/qa-findings-*.json` | `.claude/artifacts/metrics-{date}.md` |
| `docs/verification/*-verification.md` | |
| `.claude/meta/workflow-effectiveness.json` | |
| `.claude/antipatterns.md` | |
| `.claude/meta/drift-debt.json` | |
| `.claude/artifacts/findings/audit-*-history.md` | |
| `docs/specs/*.md` | |
| `.claude/artifacts/summary-*.md` | |
| `.claude/artifacts/token-log-*.json` | |
| `.claude/artifacts/audit-trail-*.jsonl` | |
| `~/.claude/usage-data/session-meta/*.json` | |
| `~/.claude/usage-data/facets/*.json` | |
| `docs/decisions/*.md` | |
| Git log | |

## Lite vs Full

- **Lite mode**: Omits Olympics convergence analysis and Olympics history table (those features are Full-only).
- **Full mode**: Adds Olympics history, convergence speed analysis, and audit-specific metrics.

## Common Issues

- **Sparse data on new projects**: This is expected. Data accumulates with each feature. The dashboard reports what exists and notes what will appear after more features run.
- **Session-meta not found**: Claude Code session data may not exist for the project yet. Session analytics will appear after a few sessions.
- **Token logs vs. session-meta divergence**: If the numbers differ significantly, the dashboard notes it: the gap is orchestrator overhead not captured by subagent tracking.
