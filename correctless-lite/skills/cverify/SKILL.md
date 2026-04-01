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
4. Dependency check
5. Basic smell check
6. Drift detection
7. Architecture compliance and prohibitions
8. Write verification report

**Between each check**, print a 1-line status: "Rule coverage complete — {N}/{M} rules covered, {K} weak. Starting mutation testing in background..." When mutation testing completes in the background, announce immediately: "Mutation testing done — {N} mutations, {M} killed, {K} survivors."

Mark each task complete as it finishes.

## Before You Start

**First-run check**: If `.claude/workflow-config.json` does not exist, tell the user: "Correctless isn't set up yet. Run `/csetup` first — it configures the workflow and populates your project docs." If the config exists but `ARCHITECTURE.md` contains `{PROJECT_NAME}` or `{PLACEHOLDER}` markers, offer: "ARCHITECTURE.md is still the template. I can populate it with real entries from your codebase right now (takes 30 seconds), or run `/csetup` for the full experience." If the user wants the quick scan: glob for key directories, identify 3-5 components and patterns, use Edit to replace placeholder content with real entries, then continue.

1. Read `AGENT_CONTEXT.md` for project context.
2. Read the spec artifact (from workflow state or `docs/specs/`).
3. Read the implementation — changed files on the branch.
4. Read the test files.
5. Read `ARCHITECTURE.md`.
6. Read `.claude/meta/workflow-effectiveness.json` — check which phases have historically missed bugs in this area.
7. Read `.claude/artifacts/qa-findings-*.json` — see what QA found and fixed during TDD.
8. Determine the default branch (check `workflow-config.json` for `workflow.default_branch`, fall back to `main`). Run `git diff {default_branch}...HEAD --stat` to see what changed.

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
git diff {default_branch}...HEAD -- package.json go.mod Cargo.toml requirements.txt pyproject.toml
```

For each new dependency: what is it, which file introduced it, was it in the spec?

### Monorepo: Multi-Package Verification
If `workflow-config.json` has `is_monorepo: true` and the spec lists "Packages Affected", run tests in ALL listed packages — not just the one where most code changed. Use the per-package test commands from `workflow-config.json`. Report per-package: "Package `api`: all tests pass. Package `web`: 2 tests fail."

### 3. Architecture Compliance and Prohibitions

Does the implementation follow the patterns in `ARCHITECTURE.md`?
- Error handling, validation, state management, naming conventions?
- New patterns introduced? Flag for ARCHITECTURE.md update.
- **Prohibition check**: For each prohibition in ARCHITECTURE.md, grep the changed files for prohibited imports, patterns, or constructs. Flag any violations.

### Compliance Checks (if configured)
Read `workflow.compliance_checks` from `workflow-config.json`. For each check where `phase` is `"verify"`:
1. Run the command
2. Report results: pass/fail with output
3. If `blocking: true` and the check fails: this is a BLOCKING finding — verification cannot pass

Compliance checks are custom scripts written by the team. Correctless runs them at the right time and reports results. Example config:
```json
"compliance_checks": [{"name": "audit-logging", "command": "./scripts/check-audit-logging.sh", "phase": "verify", "blocking": true}]
```

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
Rules-covered: R-001, R-002, R-003, ...
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
- After fixing and re-verifying: tell the human to run `/cdocs`. This is the final step before merge.
- Do NOT say "ready to merge" until /cdocs has run and `workflow-advance.sh documented` has been called.

## Claude Code Feature Integration

### Task Lists
See "Progress Visibility" section above — task creation and narration are mandatory.

### Context Enforcement
**Context enforcement (mandatory):** Before starting mutation testing, check context usage. Verification reads many files and the orchestrator must stay coherent to write an accurate report. If above 70%: "Context at {N}%. Run `/compact` before I continue — remaining checks may produce incomplete results." If above 85%: "Context is critically full ({N}%). I must stop here. Run `/compact` and then re-run `/cverify` — verification will restart but reads from existing artifacts."

### Token Tracking

After the verification agent completes, capture `total_tokens` and `duration_ms` from the completion result. Append an entry to `.claude/artifacts/token-log-{slug}.json` (derive slug from the spec file basename):

```json
{
  "skill": "cverify",
  "phase": "verification",
  "agent_role": "verification-agent",
  "total_tokens": N,
  "duration_ms": N,
  "timestamp": "ISO"
}
```

If the file doesn't exist, create it with the first entry. `/cmetrics` aggregates from raw entries — no totals field needed.

### Background Tasks
- Run mutation testing in the background while doing rule coverage analysis, prohibition checks, and antipattern matching
- Run coverage report in the background while doing drift detection
- Run linter checks in the background while analyzing architecture compliance

## Code Analysis (MCP Integration)

If `mcp.serena` is `true` in `workflow-config.json`, use Serena MCP for symbol-level code analysis during verification. Serena enables a traced coverage matrix — use `find_referencing_symbols` to trace rule to test to implementation to entry point, producing a Serena traced coverage matrix that is more precise than grep-based tracing. When Serena is available, augment the Rule Coverage table with a "Trace" column showing the symbol chain: `rule_id -> test_fn -> impl_fn -> entry_point`. If a link in the chain cannot be traced, mark it "?".

- Use `find_symbol` instead of grepping for function/type names
- Use `find_referencing_symbols` to trace callers and dependencies
- Use `get_symbols_overview` for structural overview of a module
- Use `replace_symbol_body` for precise edits (not used in this skill — verification is read-only)
- Use `search_for_pattern` for regex searches with symbol context

**Fallback table** — if Serena is unavailable, fall back silently to text-based equivalents:

| Serena Operation | Fallback |
|-----------------|----------|
| `find_symbol` | Grep for function/type name |
| `find_referencing_symbols` | Grep for symbol name across source files |
| `get_symbols_overview` | Read directory + read index files |
| `replace_symbol_body` | Edit tool |
| `search_for_pattern` | Grep tool |

**Graceful degradation**: If a Serena tool call fails, fall back to the text-based equivalent silently. Do not abort, do not retry, do not warn the user mid-operation. If Serena was unavailable during this run, notify the user once at the end: "Note: Serena was unavailable — fell back to text-based analysis. If this persists, check that the Serena MCP server is running (`uvx serena-mcp-server`)." Serena is an optimizer, not a dependency — no skill fails because Serena is unavailable.

## If Something Goes Wrong

- **Skill interrupted**: Re-run the skill. It reads the current state and resumes where possible.
- **Rate limit hit**: Wait 2-3 minutes and re-run. Workflow state persists between sessions.
- **Wrong output**: This skill doesn't modify workflow state until the final advance step. Re-run from scratch safely.
- **Stuck in a phase**: Run `/cstatus` to see where you are. Use `workflow-advance.sh override "reason"` if the gate is blocking legitimate work.

## Constraints

- **Write the verification report file.** `/cpostmortem` and `/cupdate-arch` depend on it.
- **Write drift debt entries** when drift is found. `/cspec` reads these for future features.
- **Do NOT skip the rule coverage check.** Every rule must be accounted for.
- **Do NOT approve a feature with uncovered rules.** Uncovered rules are BLOCKING.
- **Be specific about weak tests.** "Weak" means: the test would still pass if the rule were violated.
- **Context is a reliability constraint.** Above 70%, warn and recommend /compact. Above 85%, stop — instruction adherence degrades and the orchestrator cannot be trusted to produce accurate verification results.
- **Evidence before claims.** Never say "tests pass" or "checks out" without running the command fresh in this message and showing the output. "Should pass" is not evidence.
- **All files written inside the project directory.** Never /tmp.
- **Never auto-invoke the next skill.** Tell the human what comes next and let them decide when to run it. The boundary between skills is the human's decision point.
