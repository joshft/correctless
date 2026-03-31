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
9. **Decision records** — `glob docs/decisions/*.md` — for staleness checks (revisit-when/revisit-by markers)
10. **Workflow state files** — `glob .claude/artifacts/workflow-state-*.json` — for spec_updates counts per feature
11. **Token logs** — `glob .claude/artifacts/token-log-*.json` — per-feature token usage from subagent spawns
12. **Git log** — commit history to measure feature velocity and branch durations
13. **Session meta** — `glob ~/.claude/usage-data/session-meta/*.json` — filter by `project_path` matching the current project root. Contains exact token counts, tool usage, duration, error rates per session.
14. **Session facets** — `glob ~/.claude/usage-data/facets/*.json` — match by `session_id` to session-meta entries for this project. Contains AI-analyzed session quality: outcome, friction, satisfaction.

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
- `post_merge_bugs` count / (total issues caught + post_merge_bugs)
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

## Health Analysis
- **QA Round Trend:** {e.g., "Averaging 2.3 rounds — trending down from 3.1 last quarter."}
- **Antipattern Growth:** {e.g., "Error handling category growing fastest (+4 in 3 months). Consider architectural pattern."}
- **Drift Staleness:** {e.g., "3 drift items older than 90 days. Schedule /cdevadv layers analysis."}
- **Olympics Convergence (Full only):** {e.g., "Last 5 runs converged in ≤2 rounds — consider rotating presets." Omit this bullet in Lite mode.}
- **Decision Record Staleness:** {e.g., "2 decisions have expired revisit-by dates."}
- **Spec Revision Rate:** {e.g., "Specs revised mid-TDD in 60% of features — spec phase may need more brainstorm time."}
- **Cross-Metric Correlations:** {e.g., "Spec revision rate is high AND antipattern growth is accelerating in error handling — spec phase isn't learning from antipatterns."}
```

## Health Analysis

After computing the raw metrics above, analyze them for actionable insights. This is the interpretive layer — raw numbers without analysis are useless.

**QA Round Trends:**
- Calculate average QA rounds across all features. If trending up across recent features: "QA is finding more issues — check whether specs are getting less thorough or code quality is degrading."
- If trending down: "QA rounds are decreasing — the workflow is getting more effective."
- If suspiciously low (every feature passes in 1 round): "Every feature passes QA in 1 round. Either code quality is exceptional or QA intensity is too low. Consider increasing min_qa_rounds or adding more hostile QA lenses."

**Antipattern Growth:**
- Group antipatterns by category. Flag the fastest-growing: "Error handling antipatterns are growing fastest (4 new in last 3 months). This may indicate an architectural gap, not just individual bugs."
- If any category has 5+ entries: "Consider whether '{category}' is a systemic issue that needs an ARCHITECTURE.md pattern, not just more antipattern entries."

**Drift Debt Staleness:**
- Flag items older than 90 days: "{N} drift items are older than 90 days. Stale drift becomes invisible — schedule a `/cdevadv layers` analysis."
- Compare accumulation vs resolution rate: "Drift is accumulating {N}x faster than it's being resolved."

**Olympics Convergence Speed (Full only):**
- If last 5 runs all converged in ≤2 rounds: "Olympics are converging suspiciously fast. Possible causes: (1) lenses are stale, (2) codebase is genuinely clean, (3) agent presets need rotation. Try a custom preset."
- If convergence is getting slower: "Olympics are taking more rounds — new code may be introducing complexity the current lenses don't cover well."

**Decision Record Staleness:**
- Scan `docs/decisions/` for files with `revisit-when` or `revisit-by` markers. Flag expired conditions.

**Spec Revision Rate:**
- If specs are frequently revised during TDD (high spec_updates counts across features): "Specs are being revised mid-TDD frequently. The spec phase may not be thorough enough — consider more Socratic brainstorm time or research steps."

**Cross-Metric Correlations (the most valuable insights):**
- "Spec revision rate is high AND antipattern growth is accelerating in the same category" → spec phase isn't learning from antipatterns
- "QA rounds are low BUT post-merge bugs are increasing" → QA is too lenient
- "Drift debt is growing AND Olympics convergence is fast" → drift may be in areas Olympics don't cover
- "Review phase catches fewer issues over time BUT antipattern count is growing" → review isn't reading antipatterns effectively

## Token ROI Analysis

Read all `.claude/artifacts/token-log-*.json` files. Correlate token spend with findings data from QA, verification, and audit artifacts.

### Metrics to Compute

**1. Cost per bug caught**: Total tokens across all features / total distinct findings. "Across {N} features, you spent {T} tokens and caught {B} bugs — {T/B} tokens per bug caught pre-merge."

**2. Tokens per feature by phase**: Group all token log entries by the `skill` field and sum `total_tokens` per skill. Show as a table:

| Phase | Tokens | % of Total | Findings | Tokens/Finding |
|-------|--------|-----------|----------|----------------|
| TDD (ctdd) | {N} | {%} | {N} | {N} |
| Review (creview/creview-spec) | {N} | {%} | {N} | {N} |
| Verification (cverify) | {N} | {%} | {N} | {N} |
| Audit (caudit) | {N} | {%} | {N} | {N} |
| Other (all remaining: cspec, cdebug, crefactor, cmodel, credteam, cdevadv, cpostmortem) | {N} | {%} | {N} | {N} |

This shows where the budget goes. If 65% goes to TDD and TDD catches 60% of bugs, the allocation is efficient. If 40% goes to audit and it catches 5% of bugs, consider reducing audit intensity.

**3. Bug escape rate**: From `workflow-effectiveness.json`: `post_merge_bugs` count / (total caught + escaped). "Escape rate: {N}%. {M} caught pre-merge, {K} escaped."

**4. Estimated production fix cost avoided**: Each caught bug saves an estimated 2-10 hours of production debugging, hotfixes, rollbacks, and incident response. "{N} bugs caught × 2-10 hours = {range} hours saved. At $150/hr developer cost, that's ${range} saved." This is a rough estimate — say so. But even the conservative end usually exceeds the token cost.

**5. Tokens per LOC**: Total tokens / total lines added (from git diff --stat across features). Track over time — should be stable if overhead scales linearly.

**6. Olympics efficiency** (Full only): Tokens per finding per round. "Round 1: {N} findings at {T} tokens. Round {M}: {N} findings at {T} tokens." Shows diminishing returns.

**7. Token trend**: Compare with previous metrics. "Token cost per feature: {stable/growing/shrinking}. Cost per bug: {improving/degrading}."

### Output

Add to the dashboard after the existing ROI Estimate section:

```markdown
## Token ROI Analysis

### Cost Summary
- **Total tokens tracked:** {N} across {M} features
- **Average tokens per feature:** {N}
- **Cost per bug caught:** {N} tokens ({M} bugs caught)

### Phase Distribution
| Phase | Tokens | % of Total | Findings | Tokens/Finding |
|-------|--------|-----------|----------|----------------|
| TDD (ctdd) | {N} | {%} | {N} | {N} |
| Review (creview, creview-spec) | {N} | {%} | {N} | {N} |
| Verification (cverify) | {N} | {%} | {N} | {N} |
| Audit (caudit) | {N} | {%} | {N} | {N} |
| Other (cspec, cdebug, crefactor, cmodel, credteam, cdevadv, cpostmortem) | {N} | {%} | {N} | {N} |

### Bug Escape Rate
- **Pre-merge bugs caught:** {N}
- **Post-merge bugs escaped:** {M}
- **Escape rate:** {%}
- **Estimated production fix cost avoided:** {N bugs} × 2-10 hours = {range} hours (~${range} at $150/hr)

### Efficiency
- **Tokens per LOC:** {N} (total tokens / lines added across features)
- **Olympics efficiency (Full only):** Round 1: {N} findings at {T}k tokens → Round {M}: {N} findings at {T}k tokens

### Token Trend
- Token cost per feature: {stable/growing/shrinking}
- Cost per bug caught: {improving/degrading}
```

If no token logs exist, skip this section with: "No token usage data yet. Token tracking starts automatically when skills run — data will appear after the next feature."

## Session Analytics (from Claude Code data)

Determine the current project root: `git rev-parse --show-toplevel`. Then use `find ~/.claude/usage-data/session-meta/ -name '*.json'` to list all session-meta files (do NOT use Glob with `~` — use find or Bash for tilde expansion). Filter to sessions where `project_path` matches the project root (exact string match on the absolute path). For each matching session, look up the corresponding facets file at `~/.claude/usage-data/facets/{session_id}.json` (the facets filename IS the session_id).

Note: Not all sessions have facets files (~26% coverage is typical). When computing facets-based metrics, note the sample size: "Outcome data available for {N} of {M} sessions ({%})."

### Metrics to Compute

**From session-meta:**

- **Exact token cost**: Sum `input_tokens + output_tokens` across all project sessions. This is ground truth — cross-check against manual token logs. If they diverge significantly, note: "Session-meta shows {N} tokens total. Token logs show {M}. The difference ({D}) is orchestrator overhead not captured by subagent tracking."
- **Average session duration**: `mean(duration_minutes)` across sessions.
- **Tool distribution**: Aggregate `tool_counts` across sessions. Show top 6 tools by call count.
- **Friction rate**: `sum(tool_errors) / sum(all tool calls)`. Break down by `tool_error_categories`.
- **User engagement**: Average `user_response_times`. Long times (>60s) suggest confusion. Short times (<15s) suggest flow.

**From facets:**

- **Outcome rate**: % of sessions with `outcome: "fully_achieved"`.
- **Satisfaction**: Distribution of `claude_helpfulness` values.
- **Top friction categories**: Aggregate `friction_counts` across sessions. Flag growing categories.

**Correctless vs Freeform comparison:**

Identify Correctless sessions by checking whether Correctless artifacts were modified during the session's time window. A session is "Correctless" if:
- Workflow state files (`.claude/artifacts/workflow-state-*.json`) have `phase_entered_at` timestamps within the session's `start_time` to `start_time + duration_minutes` range, OR
- The session's `tool_counts` includes calls to tools that only Correctless uses (the `Task` tool with high counts suggests orchestrated workflow), OR
- QA findings, verification reports, or spec files were modified during the session window (check git log timestamps)

If none of these signals are present, the session is "freeform." Note: this heuristic is approximate — some Correctless sessions (e.g., `/cstatus` or `/chelp`) may look freeform. Err on the side of undercounting Correctless sessions rather than overcounting.

**Important:** Slash commands like `/cspec` are intercepted by Claude Code before reaching the conversation — they do NOT appear in `first_prompt`. Do not use `first_prompt` to identify Correctless sessions.

### Output

```markdown
## Session Analytics

### Overview
- **Sessions tracked:** {N} (from {date} to {date})
- **Average session duration:** {N} minutes
- **Total tokens (ground truth):** {N} input + {N} output

### Tool Distribution
| Tool | Calls | % of Total |
|------|-------|-----------|
| {tool} | {N} | {%} |

### Quality Signals
- **Outcome rate:** {N}% fully achieved
- **Helpfulness:** {distribution}
- **Friction rate:** {N}% tool errors
- **Top friction:** {category from facets friction_counts} ({N} occurrences)
- **User engagement:** avg response time {N}s ({<15s: flowing | 15-60s: normal | >60s: confused})

### Correctless vs Freeform
| Metric | Correctless Sessions | Freeform Sessions |
|--------|---------------------|-------------------|
| Outcome rate | {%} | {%} |
| Friction rate | {%} | {%} |
| Avg duration | {N} min | {N} min |
| Avg tokens | {N} | {N} |
```

If no session-meta data exists for this project, skip with: "No Claude Code session data found for this project. Session analytics will appear after running a few sessions."

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
- Reading decision records
- Reading session analytics data
- Analyzing health indicators
- Reading token logs and computing ROI
- Generating dashboard

## If Something Goes Wrong

- `/cmetrics` writes a dashboard artifact but does not modify workflow state or source code. Re-run anytime safely.
- If metrics are sparse, that's normal for new projects — data accumulates with each feature. Key sources: QA findings from `/ctdd`, verification reports from `/cverify`, antipatterns from `/cpostmortem`.

## Constraints

- **Read-only.** This skill aggregates data. It does not modify anything.
- **Be honest about estimates.** The ROI calculation is rough. Say so. Don't oversell.
- **Missing data is normal.** A new project will have sparse metrics. Report what exists and note what will accumulate with more features.
- **Don't compare to other projects.** Each project's metrics only compare to its own history.
- **The "issues caught" number includes deduplication.** If review and QA both caught the same issue, count it once at the earliest phase.
