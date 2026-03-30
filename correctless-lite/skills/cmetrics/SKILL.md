---
name: cmetrics
description: Project-wide workflow metrics dashboard. Shows total issues caught, bug escape rate, phase effectiveness, antipattern trends, Olympics history, and ROI estimate.
allowed-tools: Read, Grep, Glob, Bash(git*), Bash(wc*), Bash(find*), Bash(cat*), Bash(jq*), Write(.claude/artifacts/metrics-*)
---

# /cmetrics — Workflow Metrics Dashboard

Aggregate all accumulated workflow data into a project health dashboard. Shows the value the workflow has delivered over time.

## When to Run

- Monthly — to track trends
- Before presenting to stakeholders — to justify the workflow investment
- When deciding whether to upgrade from Lite to Full
- When something feels off — metrics reveal which phases are pulling weight and which aren't

## Data Sources

Read everything in the accumulation layer. Skip files that don't exist.

### Primary sources:
1. **QA findings** — `glob .claude/artifacts/qa-findings-*.json` — every QA round from every feature
2. **Verification reports** — `glob docs/verification/*-verification.md` — every verification
3. **Workflow effectiveness** — `.claude/meta/workflow-effectiveness.json` — post-merge bug history
4. **Antipatterns** — `.claude/antipatterns.md` — accumulated bug classes
5. **Drift debt** — `.claude/meta/drift-debt.json` — architectural erosion
6. **Olympics findings** — `glob .claude/artifacts/findings/audit-*-history.md` — all audit runs
7. **Specs** — `glob docs/specs/*.md` — count of features that went through the workflow
8. **Feature summaries** — `glob .claude/artifacts/summary-*.md` — per-feature summaries (from /csummary)
9. **Git log** — commit history to measure feature velocity and branch durations

### Derived metrics:

**Features completed** — count of spec files in `docs/specs/`

**Total issues caught** — sum of:
- Rules added during review (count rules in final spec minus rules in initial draft — approximate by counting total rules per spec)
- QA findings across all `qa-findings-*.json` files
- Verification findings from all verification reports
- Olympics findings from all audit history files

**Issues by phase** — categorize each issue by which phase caught it:
- Spec: rules that reference antipatterns or templates
- Review: rules added after initial draft (higher-numbered rules in the spec)
- Test audit: findings from QA rounds labeled as test-quality issues
- QA: all findings in qa-findings files
- Verify: findings in verification reports
- Audit: findings in Olympics history

**Bug escape rate** — from `workflow-effectiveness.json`:
- `post_merge_bugs` count / total issues caught
- List the escaped bugs with which phase should have caught them

**Phase effectiveness** — from `workflow-effectiveness.json`:
- For each phase: bugs that should have been caught vs bugs actually caught
- Identify weak phases (low catch rate relative to responsibility)

**Antipattern trends** — from `.claude/antipatterns.md`:
- Total entries
- Group by category — which categories keep growing?
- Most frequent (highest `Frequency` field)

**Drift debt health** — from `.claude/meta/drift-debt.json`:
- Open items count
- Oldest open item age
- Items resolved vs items accumulating

**Olympics history** — from audit history files:
- Number of runs by preset (QA, Hacker, Perf)
- Average rounds to convergence
- Total findings across all runs
- Recurring patterns flagged

**Feature velocity** — from git log:
- Average branch duration (first commit to merge)
- Features per month

## Output Format

Print to conversation AND write to `.claude/artifacts/metrics-{date}.md`:

```markdown
# Correctless Metrics — {Project Name}
# Generated: {date}

## Overview
- **Features completed:** {N} (from spec count)
- **Total issues caught:** {N}
- **Bug escape rate:** {N} escaped / {M} caught ({percentage}%)
- **Workflow active since:** {date of first spec file}

## Issues by Phase
| Phase | Issues Caught | % of Total | Notes |
|-------|--------------|------------|-------|
| Review | {N} | {%} | {e.g., "Security checklist added 40% of these"} |
| Test Audit | {N} | {%} | |
| QA | {N} | {%} | {e.g., "3 class fixes added structural tests"} |
| Verify | {N} | {%} | |
| Audit (Olympics) | {N} | {%} | |

## Bug Escapes
{From workflow-effectiveness.json}
| ID | Severity | What | Phase That Missed | Why |
|----|----------|------|-------------------|-----|
| PMB-001 | {sev} | {desc} | {phase} | {reason} |

**Weakest phase:** {phase with most misses relative to responsibility}
**Recommendation:** {what to improve — more templates? higher intensity? more QA rounds?}

## Antipattern Trends
- **Total entries:** {N}
- **Top categories:**
  | Category | Count | Trend |
  |----------|-------|-------|
  | {category} | {N} | {growing/stable/resolved} |

- **Most frequent:** {AP-xxx} — {description} — seen {N} times

{If any category has 3+ entries: "Consider whether this is an architectural issue, not just a code pattern."}

## Drift Debt
- **Open items:** {N}
- **Oldest:** {DRIFT-xxx} — {age} days — {description}
- **Resolved this period:** {N}
- **Accumulating faster than resolving:** {yes/no}

{If oldest > 60 days: "Flag for /cdevadv analysis — this is rotting."}

## Olympics History
| Run | Preset | Date | Rounds | Findings | Fixed |
|-----|--------|------|--------|----------|-------|
| 1 | QA | {date} | {N} | {N} | {N} |
| 2 | Hacker | {date} | {N} | {N} | {N} |

**Average convergence:** {N} rounds
**Recurring patterns:** {patterns that keep appearing across runs}

## Velocity
- **Average feature duration:** {N} days (branch creation to merge)
- **Features per month:** {N}
- **Workflow overhead per feature:** ~{N} min estimated

## ROI Estimate
- **Issues caught:** {N}
- **Estimated fix time if found in production:** {N} × 2 hours avg = {N} hours
- **Workflow time invested:** {features} × {overhead per feature} = {N} hours
- **Net time saved:** {production fix time} - {workflow time} = {N} hours

{This is a rough estimate. Production bugs take 2-10x longer to fix than pre-merge bugs due to debugging, hotfixes, rollbacks, and incident response. The 2-hour average is conservative.}
```

## Trend Tracking

If previous metrics files exist (`.claude/artifacts/metrics-*.md`), compare:
- Is the bug escape rate improving? (should decrease over time)
- Are more issues being caught earlier? (review should catch more as templates improve)
- Is drift debt accumulating or resolving?
- Are Olympics converging faster? (should, as antipatterns grow)

Note trends: "Bug escape rate: 5% → 3% → 1.5% over 3 months. The workflow is getting more effective."

## Claude Code Feature Integration

### Task Lists
Use TaskCreate/TaskUpdate:
- Reading QA findings (N files)
- Reading verification reports (N files)
- Reading workflow effectiveness data
- Reading antipatterns
- Reading drift debt
- Reading Olympics history
- Reading git log
- Calculating metrics
- Generating dashboard

## Constraints

- **Read-only.** This skill aggregates data. It does not modify anything.
- **Be honest about estimates.** The ROI calculation is rough. Say so. Don't oversell.
- **Missing data is normal.** A new project will have sparse metrics. Report what exists and note what will accumulate with more features.
- **Don't compare to other projects.** Each project's metrics only compare to its own history.
- **The "issues caught" number includes deduplication.** If review and QA both caught the same issue, count it once at the earliest phase.
