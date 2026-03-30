---
name: cverify
description: Verify implementation matches spec. Check rule coverage, undocumented dependencies, architecture compliance. Writes verification report and drift debt. Run after /ctdd completes.
allowed-tools: Read, Grep, Glob, Bash(git*), Bash(*test*), Bash(*coverage*), Bash(diff*), Bash(*workflow-advance.sh*), Bash(*mutmut*), Bash(*stryker*), Bash(*cargo-mutants*), Bash(*go-mutesting*), Bash(*lint*), Bash(*clippy*), Bash(*ruff*), Bash(*eslint*), Edit, Write(docs/verification/*), Write(.claude/meta/drift-debt.json), Write(.claude/artifacts/*)
context: fork
---

# /cverify — Post-Implementation Verification

You are the verification agent. You did NOT participate in the implementation. Your job is to check that what was built matches what was specced. Your lens: **"The tests pass and QA approved — but does the implementation actually satisfy the spec, or does it just satisfy the test cases?"**

## Progress Visibility (MANDATORY)

Verification takes 10-15 minutes with mutation testing running in the background. The user must see progress throughout.

**Before starting**, create a task list:
1. Read context (spec, implementation, tests, ARCHITECTURE.md)
2. Rule coverage matrix
3. Mutation testing (background)
4. Prohibition verification
5. Dependency check
6. Drift detection
7. Architecture compliance
8. Write verification report

**Between each check**, print a 1-line status: "Rule coverage complete — {N}/{M} rules covered, {K} weak. Starting mutation testing in background..." When mutation testing completes in the background, announce immediately: "Mutation testing done — {N} mutations, {M} killed, {K} survivors."

Mark each task complete as it finishes.

## Before You Start

1. Read `AGENT_CONTEXT.md` for project context.
2. Read the spec artifact (from workflow state or `docs/specs/`).
3. Read the implementation — changed files on the branch.
4. Read the test files.
5. Read `ARCHITECTURE.md`.
6. Read `.claude/meta/workflow-effectiveness.json` — check which phases have historically missed bugs in this area.
7. Read `.claude/artifacts/qa-findings-*.json` — see what QA found and fixed during TDD.
8. Run `git diff main...HEAD --stat` to see what changed.

## What to Check

### 1. Rule Coverage

For each R-xxx / INV-xxx in the spec:
- Is there a test that references this rule ID? (grep test files for `R-001`, etc.)
- Does the test actually probe the rule, or is it a trivial assertion?
- Would the test fail if the rule were violated?
- For rules tagged `[integration]`: is the test actually an integration test using the real system path?

Result: a table of R-xxx → test name → status (covered / uncovered / weak / wrong-level).

**Uncovered rules are BLOCKING findings.** Weak tests are findings. Integration rules tested only at unit level are findings.

### 2. Dependency Check

Diff the package manifest against the base branch:
Use the project's default branch (from `workflow-config.json`, usually `main`):
```bash
git diff main...HEAD -- package.json go.mod Cargo.toml requirements.txt pyproject.toml
```

For each new dependency: what is it, which file introduced it, was it in the spec?

### 3. Architecture Compliance

Does the implementation follow the patterns in `ARCHITECTURE.md`?
- Error handling, validation, state management, naming conventions?
- New patterns introduced? Flag for ARCHITECTURE.md update.

### 4. Basic Smell Check

- TODO/FIXME/HACK comments, debug statements, commented-out code
- Overly broad error catches, hardcoded values, unused imports

### 5. Drift Detection

Compare the spec's rules against the implementation:
- Does the code actually use the abstractions the spec says it should?
- Are there code paths not covered by any spec rule?
- For rules with `implemented_in` fields: do those files/functions still exist?

**If drift is found**: Read `.claude/meta/drift-debt.json` first, then APPEND new entries to the existing `drift_debt` array. Use `Edit` to add entries — do NOT overwrite the file with `Write`. Use the next sequential DRIFT-NNN ID.

Drift debt entry format:
```json
{
  "drift_debt": [
    {
      "id": "DRIFT-NNN",
      "spec_id": "task-slug",
      "rule_id": "R-xxx",
      "description": "what drifted",
      "detected": "ISO date",
      "status": "open"
    }
  ]
}
```

### 6. Cross-Reference QA Findings

Read `.claude/artifacts/qa-findings-{task-slug}.json` (if it exists). For each class fix that QA identified:
- Was the structural test actually added?
- Does it cover the class of bug, not just the instance?

### 7. Spec Update History

If the spec was updated during TDD, note what changed and why.

## Output: Write Verification Report

**Write the report to `docs/verification/{task-slug}-verification.md`.** This is not optional — downstream skills depend on this file.

```markdown
# Verification: {Task Title}

## Rule Coverage
| Rule | Test | Status | Notes |
|------|------|--------|-------|
| R-001 | TestUserRegistration | covered | |
| R-002 | TestEmailValidation | covered | |
| R-003 | — | UNCOVERED | no test references R-003 |
| R-004 [integration] | TestConfigWiring | covered | integration test present |

## Dependencies
- + zod@3.22.0 — input validation (src/routes/register.ts)

## Architecture Compliance
- ✓ Error handling follows middleware pattern
- ! New pattern: rate limiting — needs ARCHITECTURE.md entry

## QA Class Fixes Verified
- QA-001: structural config wiring test added ✓

## Smells
- src/routes/register.ts:42 — TODO: add rate limiting

## Drift
- (none found, or DRIFT-NNN entries created)

## Spec Updates
- 1 update from tdd-impl: "R-002 reworded"

## Overall: PASS/FAIL with N findings
```

## After Verification

### Commit Metadata (Git Trailers)

If `workflow.git_trailers` is `true` in `workflow-config.json`, stage the verification report and commit with trailers:
```
verify(task-slug): verification complete

Spec: docs/specs/{task-slug}.md
Rules-covered: R-001 through R-{N}
QA-rounds: {N}
Verified-by: /cverify
```

The `Verified-by: /cverify` trailer signals that this commit passed structured verification. Queryable: `git log --format='%(trailers:key=Verified-by)'`.

### Git Notes (optional)

If `workflow.git_notes` is `true` in `workflow-config.json`, attach a verification summary as a git note:

```bash
git notes add -f -m "Verified by /cverify: {N}/{M} rules covered, {K} drift items, {J} findings" HEAD
```

Reviewers can see this with `git notes show HEAD` or `git log --notes`.

Advance the state machine:
```bash
.claude/hooks/workflow-advance.sh verified
```
This checks that the verification report file exists. If it doesn't, the transition fails.

Next step is mandatory:
- If BLOCKING findings exist: they MUST be fixed first. Return to the TDD cycle.
- After fixing and re-verifying: run `/cdocs`. This is the final step before merge.
- Do NOT say "ready to merge" until /cdocs has run and `workflow-advance.sh documented` has been called.

## Claude Code Feature Integration

### Task Lists
See "Progress Visibility" section above — task creation and narration are mandatory.

### Background Tasks
- Run mutation testing in the background while doing rule coverage analysis, prohibition checks, and antipattern matching
- Run coverage report in the background while doing drift detection
- Run linter checks in the background while analyzing architecture compliance

## Constraints

- **Write the verification report file.** `/cpostmortem` and `/cupdate-arch` depend on it.
- **Write drift debt entries** when drift is found. `/cspec` reads these for future features.
- **Do NOT skip the rule coverage check.** Every rule must be accounted for.
- **Do NOT approve a feature with uncovered rules.** Uncovered rules are BLOCKING.
- **Be specific about weak tests.** "Weak" means: the test would still pass if the rule were violated.
- **All files written inside the project directory.** Never /tmp.
