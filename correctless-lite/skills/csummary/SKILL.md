---
name: csummary
description: Feature summary. Use after /cdocs to see what the workflow caught, or mid-feature to check progress.
allowed-tools: Read, Grep, Glob, Bash(git*), Write(.claude/artifacts/summary-*)
---

# /csummary — Feature Workflow Summary

Generate a one-page summary of everything the Correctless workflow caught during this feature. This is the "look what I saved you" report.

## When to Run

- After `/cdocs` completes (end of a feature) — full summary
- During a feature — partial summary of what's been caught so far
- Before a PR — include the summary in the PR description

## Data Sources

Read these files to build the summary. Skip any that don't exist.

1. **The spec** (`docs/specs/{task-slug}.md`) — check for rules added during review (rules not in the original draft)
2. **QA findings** (`.claude/artifacts/qa-findings-{task-slug}.json`) — issues caught during TDD QA
3. **Verification report** (`docs/verification/{task-slug}-verification.md`) — issues caught during verification
4. **Git log** on the current branch — count commits, measure duration
5. **Workflow state file** — QA rounds, spec updates
6. **Test edit log** (`.claude/artifacts/tdd-test-edits.log`) — tests modified during implementation
7. **Audit trail** (`.claude/artifacts/audit-trail-{branch-slug}.jsonl`) — every file modification with workflow phase and timestamp. Shows exactly which files were touched in which phases, without manual instrumentation.

## How to Build the Summary

### Step 1: Identify the Feature

Read the workflow state file to get the task name, spec path, and branch. If no active workflow, ask the human which feature to summarize and look for the spec and artifacts by slug.

### Step 2: Gather Review Findings

Read the spec file. Look for rules that were added during the review phase — these are rules the spec author didn't think of. Indicators:
- Rules with higher numbers than the original set (e.g., if the draft had R-001 through R-005 and the final has R-001 through R-009, the review added 4 rules)
- Rules referencing antipatterns (`guards_against: AP-xxx`)
- Security-related rules (auth, validation, CSRF, etc.) — likely added by the security checklist

If a research brief exists (`.claude/artifacts/research/{task-slug}-research.md`), note what the research agent found (stale APIs, CVEs, deprecated patterns).

### Step 3: Gather Test Audit Findings

The test audit runs between RED and GREEN. Its findings are verbal (returned to the orchestrator) and may not be persisted as a file. Check:
- QA findings JSON for early-round entries that mention "test strengthened" or "integration test added"
- The test edit log for tests modified during GREEN (may indicate test audit feedback)
- The audit trail JSONL for file modifications during GREEN — this supplements the test edit log with precise timestamps and phase tags for detecting test changes during implementation

### Step 4: Gather QA Findings

Read `.claude/artifacts/qa-findings-{task-slug}.json`. For each finding:
- What was found (description)
- Instance fix applied
- Class fix applied (structural test added)
- Whether it was a mock gap, assertion weakness, or missing coverage

### Step 5: Gather Verification Findings

Read `docs/verification/{task-slug}-verification.md`. Extract:
- Uncovered rules
- Weak tests
- Undocumented dependencies
- Architecture compliance issues
- Drift findings

### Step 6: Calculate Stats

- Total issues caught (review + test audit + QA + verification)
- Issues by phase
- QA rounds needed
- Spec updates (if any — indicates the spec was wrong mid-TDD)
- Branch duration (first commit to last commit on this branch)

### Step 7: Classify Impact

For each issue caught, assess: **would this have shipped to production without the workflow?**

- **Would have shipped**: issues that a developer coding without specs/review/TDD would not catch — missing CSRF, untested edge cases, missing validation, mock gaps hiding wiring bugs
- **Might have been caught**: issues that a careful developer might spot in self-review — obvious bugs, typos, missing error handling
- **Cosmetic**: code quality issues that don't affect correctness — naming, formatting, dead code

Count the "would have shipped" items. This is the headline number.

## Output Format

Print the summary to the conversation AND write it to `.claude/artifacts/summary-{task-slug}.md`:

```markdown
# Workflow Summary: {Feature Name}

**Branch:** {branch name}
**Duration:** {time from first to last commit}
**Spec:** {docs/specs/slug.md}

## What the Workflow Caught

### Review found ({N} issues):  <!-- /creview (Lite) or /creview-spec (Full) -->
- {description of each issue added during review}
- {security checklist findings}

### Test Audit found ({N} issues):
- {test quality issues caught before implementation started}

### /ctdd QA found ({N} issues, {M} rounds):
- {each QA finding with instance + class fix}

### /cverify found ({N} issues):
- {verification findings}

## Research Insights (if research agent ran):
- {current best practices found, stale patterns avoided, CVEs dodged}

## Spec Updates During TDD:
- {if spec was revised mid-implementation, what changed and why}

## Stats
- **Total issues caught:** {N}
- **Would have shipped without workflow:** {M} ({percentage}%)
- **QA rounds:** {count}
- **Spec updates:** {count}

## What This Means
{1-2 sentences: "Without this workflow, {M} issues including {most critical} would have shipped to production."}
```

## Claude Code Feature Integration

### Task Lists
Use TaskCreate/TaskUpdate to show progress:
- Reading spec and identifying review additions
- Reading QA findings
- Reading verification report
- Calculating stats
- Generating summary

### /export
After generating: "Export this summary to include in your PR description: `/export .claude/artifacts/summary-{task-slug}.md`"

## If Something Goes Wrong

- These skills are read-only — they don't modify workflow state or source code. Re-run anytime safely.
- If data is missing or incomplete, check that the prerequisite skills have run (e.g., `/csummary` needs QA findings from `/ctdd`).

## Constraints

- **Read-only.** This skill reads artifacts and produces a report. It does not modify anything.
- **Don't inflate numbers.** Only count issues that are genuinely distinct. Deduplicating overlapping findings across phases is more honest than double-counting.
- **Be specific.** "3 security issues" is less useful than "missing CSRF protection, no rate limiting on login, bcrypt cost factor not specified."
- **The "would have shipped" classification is a judgment call.** Be conservative — only count issues where the developer clearly would not have caught them without the workflow. When in doubt, classify as "might have been caught."
- **Redact if sharing.** If this output will be shared externally, apply redaction rules from `templates/redaction-rules.md` first.
