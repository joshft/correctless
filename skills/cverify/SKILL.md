---
name: cverify
description: Verify implementation matches spec. Check rule coverage, undocumented dependencies, architecture compliance. Writes verification report and drift debt. Run after /ctdd completes.
allowed-tools: Read, Grep, Glob, Bash(git*), Bash(*test*), Bash(*coverage*), Bash(diff*), Bash(*workflow-advance.sh*), Bash(jq*), Bash(*mutmut*), Bash(*stryker*), Bash(*cargo-mutants*), Bash(*go-mutesting*), Bash(*lint*), Bash(*clippy*), Bash(*ruff*), Bash(*eslint*), Edit, Write(.correctless/verification/*), Write(.correctless/meta/drift-debt.json), Write(.correctless/meta/intensity-calibration.json), Write(.correctless/artifacts/*)
context: fork
---

# /cverify — Post-Implementation Verification

> **Shared constraints apply.** Before executing, read `_shared/constraints.md` from the parent of this skill's base directory. All constraints there apply to this skill.

You are the verification agent. You did NOT participate in the implementation. Your job is to check that what was built matches what was specced. Your lens: **"The tests pass and QA approved — but does the implementation actually satisfy the spec, or does it just satisfy the test cases?"**

## Intensity Configuration

| | Standard | High | Critical |
|---|---|---|---|
| Rule coverage | Exists + weak detection | Full matrix + Serena trace | Full + mutation survivor analysis |
| Dependencies | List + license | List + CVE + maintenance | Full audit |
| Architecture | Basic compliance | Full + drift detection | Full + cross-spec + prohibitions |

## Effective Intensity

Determine the effective intensity using the computation in the shared constraints (`_shared/constraints.md`).

## Progress Visibility (MANDATORY)

### Intensity-Aware Verification Behavior

- At standard intensity: rule coverage checks for existence and weak detection. Dependencies get list + license check. Architecture gets basic compliance review.
- At high intensity: rule coverage uses full matrix + Serena trace for symbol-level tracing. Dependencies include CVE scanning and maintenance status. Architecture gets full review with drift detection.
- At critical intensity: rule coverage includes full matrix plus mutation survivor analysis. Dependencies undergo full audit. Architecture review includes cross-spec consistency checks and prohibition enforcement.

Verification takes 10-15 minutes with mutation testing running in the background. The user must see progress throughout.

**Before starting**, create a task list:
1. Read context (spec, implementation, tests, .correctless/ARCHITECTURE.md)
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

**First-run check**: If `.correctless/config/workflow-config.json` does not exist, tell the user: "Correctless isn't set up yet. Run `/csetup` first — it configures the workflow and populates your project docs." If the config exists but `.correctless/ARCHITECTURE.md` contains `{PROJECT_NAME}` or `{PLACEHOLDER}` markers, offer: ".correctless/ARCHITECTURE.md is still the template. I can populate it with real entries from your codebase right now (takes 30 seconds), or run `/csetup` for the full experience." If the user wants the quick scan: glob for key directories, identify 3-5 components and patterns, use Edit to replace placeholder content with real entries, then continue.

1. Read `.correctless/AGENT_CONTEXT.md` for project context.
2. Read the spec artifact (path from `workflow-advance.sh status` output, `Spec:` line).
3. Read the implementation — changed files on the branch.
4. Read the test files.
5. Read `.correctless/ARCHITECTURE.md`.
6. Read `.correctless/meta/workflow-effectiveness.json` — check which phases have historically missed bugs in this area.
7. Read `.correctless/artifacts/qa-findings-*.json` — see what QA found and fixed during TDD.
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

Does the implementation follow the patterns in `.correctless/ARCHITECTURE.md`?
- Error handling, validation, state management, naming conventions?
- New patterns introduced? Flag for .correctless/ARCHITECTURE.md update.
- **Prohibition check**: For each prohibition in .correctless/ARCHITECTURE.md, grep the changed files for prohibited imports, patterns, or constructs. Flag any violations.

### Compliance Checks (if configured)
Read `workflow.compliance_checks` from `workflow-config.json`. For each check where `phase` is `"verify"`:
1. Run the command
2. Report results: pass/fail with output
3. If `blocking: true` and the check fails: this is a BLOCKING finding — verification cannot pass

Compliance checks are custom scripts written by the team. Correctless runs them at the right time and reports results. Example config:
```json
"compliance_checks": [{"name": "audit-logging", "command": "./scripts/check-audit-logging.sh", "phase": "verify", "blocking": true}]
```

### 4. Antipattern Scan and Basic Smell Check

Run the deterministic antipattern-scan script to detect mechanical code smells:

```bash
bash .correctless/scripts/antipattern-scan.sh {default_branch}
```

where `{default_branch}` is read from `workflow.default_branch` in `workflow-config.json`, falling back to `main` if absent.

Validate that stdout is non-empty valid JSON with a `.findings` key before treating it as findings. Empty or invalid output means the scanner itself failed and must be reported as an error, not "zero findings." Also check if the JSON contains an `errors` array with entries — if so, report these scanner errors to the user rather than silently discarding them.

If the JSON output includes a `summaries` array (present when files exceed the 20-finding cap), include these in the report.

Include the results in the verification report under an "## Antipattern Scan" section with a table of findings. Also review the semantic ai-antipatterns checklist at `.correctless/checklists/ai-antipatterns.md` for patterns not detectable by grep.

Additionally check for:
- TODO/FIXME/HACK comments, debug statements, commented-out code
- Overly broad error catches, hardcoded values, unused imports

### 5. Drift Detection

Compare the spec's rules against the implementation:
- Does the code actually use the abstractions the spec says it should?
- Are there code paths not covered by any spec rule?
- For rules with `implemented_in` fields: do those files/functions still exist?

**If drift is found**, present each drift item to the human with options:

```
  1. Fix (recommended) — update code or spec to resolve drift
  2. Log as debt — create DRIFT-NNN entry for future resolution
  3. Accept as intentional — document why the drift is correct

  Or type your own: ___
```

For items where the user chooses "Log as debt": Read `.correctless/meta/drift-debt.json` first, then APPEND new entries to the existing `drift_debt` array. Use `Edit` to add entries — do NOT overwrite the file with `Write`. Use the next sequential DRIFT-NNN ID.

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

Read `.correctless/artifacts/qa-findings-{task-slug}.json` (if it exists). For each class fix that QA identified:
- Was the structural test actually added?
- Does it cover the class of bug, not just the instance?

### 7. Spec Update History

If the spec was updated during TDD, note what changed and why.

## Output: Write Verification Report

**Write the report to `.correctless/verification/{task-slug}-verification.md`.** This is not optional — downstream skills depend on this file.

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
- ! New pattern: rate limiting — needs .correctless/ARCHITECTURE.md entry

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

Spec: .correctless/specs/{task-slug}.md
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

### Write Calibration Entry

Before advancing the workflow state, write a calibration entry to `.correctless/meta/intensity-calibration.json`. This records outcome data that `/cspec` reads to improve future intensity recommendations.

If `.correctless/meta/` does not exist, create it (`mkdir -p .correctless/meta`). If the file does not exist, create it with an empty `calibration_entries` array. Append a new entry to the `calibration_entries` array with this schema:

```json
{
  "calibration_entries": [
    {
      "feature_slug": "task-slug from spec/workflow state",
      "recommended_intensity": "standard|high|critical — read from the spec's Recommended-intensity metadata field (the system's pre-override suggestion)",
      "actual_intensity": "standard|high|critical — read from the spec's Intensity metadata field (the approved post-override level)",
      "actual_qa_rounds": "number — read from the workflow state file (qa_rounds field)",
      "actual_findings_count": "number — count of BLOCKING findings only from qa-findings-{slug}.json (not MEDIUM/LOW)",
      "actual_tokens": "integer — sum of total_tokens from the token log JSONL file (see below)",
      "actual_cost_usd": "number or absent — read from cost artifact if it exists (see below)",
      "actual_spec_updates": "number — read from the workflow state file (spec_updates field)",
      "harness_version": "integer or absent — current HARNESS_VERSION constant from scripts/harness-fingerprint.sh (BND-005 of harness-fingerprint spec)",
      "fix_rounds_triggered": "integer — derived: max(0, qa_rounds - 1) + mini_audit_fix_rounds (see below)",
      "file_paths_touched": ["array of file paths from git diff against the default branch"],
      "timestamp": "ISO 8601 string"
    }
  ]
}
```

**`harness_version` field (BND-005 of harness-fingerprint spec)**: extract the current `HARNESS_VERSION` constant from `scripts/harness-fingerprint.sh` (or `.correctless/scripts/harness-fingerprint.sh` in installed projects). Read with: `grep -E '^HARNESS_VERSION=' scripts/harness-fingerprint.sh | head -1 | sed 's/HARNESS_VERSION=//'`. Include the integer in every new calibration entry so `/cmodelupgrade`'s three-tier bootstrap lookup (exact-match pool / pre-fingerprint pool / no-baseline) can distinguish entries by harness generation. If the script is missing, omit the field — do not error.

**Field sources:**
- `recommended_intensity`: Read from the spec's `Recommended-intensity` metadata field. This is the pre-override system suggestion written by `/cspec`.
- `actual_intensity`: Read from the spec's `Intensity` metadata field. This is the approved post-override level.
- `actual_qa_rounds`: Read from the workflow state file (`qa_rounds` field).
- `actual_spec_updates`: Read from the workflow state file (`spec_updates` field).
- `actual_findings_count`: Count only BLOCKING findings from `qa-findings-{slug}.json`. MEDIUM and LOW findings indicate thorough QA, not insufficient intensity.
- `actual_tokens`: Sum of `total_tokens` from the token log JSONL file for this branch. See "Token Summation for actual_tokens" below.
- `actual_cost_usd`: Read `total_cost_usd` from the cost artifact at `.correctless/artifacts/cost-{branch-slug}.json` if it exists. If the cost artifact does not exist (e.g., /cdocs hasn't run yet), omit `actual_cost_usd` from the calibration entry entirely — do not set it to 0, just leave it absent. The cost artifact is the canonical source of USD cost data (ABS-026).
- `fix_rounds_triggered`: Derived value: `max(0, qa_rounds - 1) + mini_audit_fix_rounds`. `qa_rounds` is read from the workflow state — QA round 1 is the initial QA, rounds 2+ are fix rounds (so `qa_rounds - 1` = fix rounds from QA). `mini_audit_fix_rounds` is the count of fix-loop re-entries during the mini-audit phase, derived from qa-findings JSON round entries with `MA-` prefix that triggered fix loops. Default to 0 when not determinable.
- `file_paths_touched`: Collect from `git diff {default_branch}...HEAD --name-only`.
- `timestamp`: Current ISO 8601 timestamp.

#### Token Summation for actual_tokens

The `actual_tokens` field in the calibration entry is an integer representing total token usage for this feature. Read the branch name from the workflow state file's `.branch` field, then derive the branch_slug by passing that branch name to `branch_slug()` in scripts/lib.sh. Use the resulting slug to locate the token log file at `.correctless/artifacts/token-log-{branch-slug}.jsonl`.

**Compute the slug and sum tokens with these deterministic commands** — do NOT use LLM arithmetic or hand-construct the slug:

```bash
# Step 1: Read the branch name from the workflow state file
FEATURE_BRANCH="$(jq -r '.branch // empty' .correctless/artifacts/workflow-state-*.json 2>/dev/null | head -1)"

# Step 2: Derive the slug using branch_slug() with the branch name parameter
source scripts/lib.sh
SLUG="$(branch_slug "$FEATURE_BRANCH")"

# Step 3: Sum total_tokens from the token log
jq -R 'try (fromjson | .total_tokens // 0) catch 0' ".correctless/artifacts/token-log-${SLUG}.jsonl" | jq -s 'add // 0'
```

This reads each line as raw text (`-R`), attempts to parse it as JSON (`fromjson`), extracts `total_tokens` (defaulting to 0), and catches parse errors on malformed lines (outputting 0). The second jq sums all values.

**Missing or empty token log:** If the token log file does not exist or is empty, set `actual_tokens` to 0.

Write `actual_tokens` as an integer in the calibration entry alongside the other fields.

Write this calibration entry before advancing the workflow state — calibration data must be persisted even if the advance step fails.

Advance the state machine:
```bash
.correctless/hooks/workflow-advance.sh verified
```
This checks that the verification report file exists. If it doesn't, the transition fails.

After advancing, print the pipeline diagram:

At standard intensity:
```
  ✓ spec → ✓ review → ✓ tdd → ✓ verify → ▶ docs → merge
```

At high+ intensity:
```
  ✓ spec → ✓ review → ✓ tdd → ✓ verify → ▶ arch → docs → audit → merge
```

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

Log token usage following the shared constraints (`_shared/constraints.md`). Skill-specific values:
- `skill`: "cverify"
- `phase`: "verification"
- `agent_role`: "verification-agent"

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
