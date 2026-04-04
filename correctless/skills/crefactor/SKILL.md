---
name: crefactor
description: Structured refactoring with behavioral equivalence enforcement. Tests must pass before AND after. Any test change requires explicit approval. Writes characterization tests for low-coverage code.
allowed-tools: Read, Grep, Glob, Bash(*), Write(.correctless/artifacts/*), Write(.correctless/ARCHITECTURE.md), Write(.correctless/AGENT_CONTEXT.md), Edit(.correctless/ARCHITECTURE.md), Edit(.correctless/AGENT_CONTEXT.md)
context: fork
---

# /crefactor — Structured Refactoring

You are the refactor orchestrator. Refactoring has a fundamentally different risk model than new features. The spec isn't "build X" — it's "same behavior, different structure." The test suite IS the spec. If tests pass before and after, the refactor is correct. If a test had to change, that's a behavioral change disguised as a refactor — flag it.

## Philosophy

Every step exists because agents silently break behavior during refactors. The most dangerous thing an agent does is "fix" a test to match restructured code — this erases the behavioral contract. The gate on test changes is the critical invariant of this workflow.

## Progress Visibility (MANDATORY)

Refactoring can take 15-60+ minutes depending on scope. The user must see progress throughout.

**Before starting**, create a task list:
1. Capture refactor intent
2. Assess test coverage on affected code
3. Write characterization tests (if needed)
4. Snapshot behavioral contract (baseline)
5. Plan refactor phases
6. Execute refactor (per-phase verification)
7. QA review
8. Final verification
9. Architecture update (if applicable)

**Between each phase**, print a 1-line status: "Coverage assessment: {N} tests covering {M}% of refactored files. {Adequate / Characterization tests needed}..." When spawning agents, announce what they're doing. When agents complete, announce results immediately.

Mark each task complete as it finishes.

## Step 1: Capture Refactor Intent

**First-run check**: If `.correctless/ARCHITECTURE.md` contains `{PROJECT_NAME}` or `{PLACEHOLDER}` markers, or if `.correctless/config/workflow-config.json` does not exist, tell the user: "Correctless isn't fully set up yet. I can do a quick scan of your codebase right now to populate .correctless/ARCHITECTURE.md and .correctless/AGENT_CONTEXT.md, or you can run `/csetup` for the full experience." If they want the quick scan: glob for key directories, populate .correctless/ARCHITECTURE.md, then continue. This improves refactor planning and architecture update suggestions.

### Checkpoint Resume

After capturing the refactor intent (below), check for `.correctless/artifacts/checkpoint-crefactor-{slug}.json` (derive slug from the intent filename). If no intent file exists yet, no checkpoint can exist — proceed normally. Also check that the checkpoint branch matches the current branch — ignore checkpoints from other branches.

- **If found and <24 hours old**: Read `completed_phases`. Before skipping, verify each phase:
  - After `coverage-assessed`: refactor intent artifact exists
  - After `characterization-tests`: characterization test files exist and pass
  - After `phase-N` (refactor phases): run test suite — tests must pass
  - After `qa`: `.correctless/artifacts/qa-findings-refactor-{slug}.json` exists
  If verification passes: "Found checkpoint from {timestamp} — {completed phases} already done. Resuming from {next phase}." Skip completed phases. If verification fails (e.g., tests no longer pass after a refactor phase): restart from the phase that failed.
- **If found but >24 hours old**: "Stale checkpoint found (from {date}). Starting fresh."
- **If not found**: Start from the beginning as normal.

After each major phase (`coverage-assessed`, `characterization-tests`, `phase-1`, `phase-2`, ..., `qa`) completes, write/update the checkpoint:
```json
{
  "skill": "crefactor",
  "slug": "{refactor-slug}",
  "branch": "{current-branch}",
  "completed_phases": ["coverage-assessed", "characterization-tests", "phase-1"],
  "current_phase": "phase-2",
  "timestamp": "ISO"
}
```
Clean up the checkpoint file when the refactor completes successfully.

First, check for an active workflow: `.correctless/hooks/workflow-advance.sh status 2>/dev/null`. If a TDD workflow is active on this branch, warn the user: "There's an active workflow on this branch. Running /crefactor here may conflict. Consider finishing the current feature or using a separate branch."

Ask the user:
- **What** are you refactoring? (specific files, modules, layers)
- **Why?** (extract domain layer, reduce duplication, migrate library, improve testability)
- **What should NOT change?** (external behavior, API contracts, database schema)

Write the intent to `.correctless/artifacts/refactor-intent-{slug}.md`:
```markdown
# Refactor Intent: {Title}

## What: {description of structural change}
## Why: {motivation}
## Scope: {files/modules affected}
## Behavioral Contract: All existing tests must pass unchanged.
## Exceptions: {any known intentional behavior changes, if any}
```

Present to user for approval before proceeding.

## Step 2: Assess Test Coverage

Run the test suite with coverage on the files being refactored:
```bash
{coverage command from workflow-config.json} -- {files being refactored}
```

Analyze results:
- **Which functions/modules being refactored have tests?**
- **What's the coverage percentage on those specific files?**
- **Are there integration tests that exercise the code paths being changed?**

### Coverage Decision

- **Adequate coverage** (tests exist for the code being refactored, key paths are exercised): Print "Coverage is adequate — {N} tests cover the refactored code at {M}% coverage. Proceeding with existing tests as the behavioral contract." Skip to Step 4.

- **Low coverage** (<50% on refactored files, or key code paths untested): Print "Coverage is low — {M}% on refactored files. Writing characterization tests to make this refactor safe." Proceed to Step 3.

- **Zero tests**: Print "No tests cover the code being refactored. Characterization tests are mandatory — refactoring without a safety net is not a refactor, it's a rewrite." Proceed to Step 3.

## Step 3: Write Characterization Tests (if needed)

Spawn a **characterization test agent** as a separate forked subagent:

> You are the characterization test agent. Your job is to capture the CURRENT behavior of the code being refactored — including quirks and bugs. Characterization tests assert reality, not intent.
>
> For each function/module being refactored:
> 1. Read the code carefully
> 2. Write tests that exercise: normal inputs, edge cases, error paths, side effects
> 3. Each test asserts what the code CURRENTLY does — even if that behavior looks like a bug
> 4. If a function returns null on empty input and you don't know if that's intentional, write a test asserting it returns null. The refactor will tell us if that behavior changes.
> 5. Run the tests — they MUST pass against the current code (by definition)
>
> Name characterization tests clearly: `describe('characterization: UserService')` or `TestCharacterization_UserService`
>
> The characterization test agent should have `allowed-tools` restricted to: `Read, Grep, Glob, Write(test files matching patterns.test_file), Bash(test and build commands)`

After the agent completes:
- Verify all characterization tests pass
- Present to user: "I wrote {N} characterization tests covering {files}. These capture current behavior — including any bugs. Review before proceeding?"
- User approves. These become the behavioral contract.

## Step 4: Snapshot Behavioral Contract

Run the full test suite (including any new characterization tests):
```bash
{test_verbose command from workflow-config.json}
```

Record:
- Total test count
- All passing test names
- Test file checksums (to detect modifications)

Store in `.correctless/artifacts/refactor-baseline-{slug}.json`:
```json
{
  "test_count": N,
  "all_passing": true,
  "test_names": ["TestA", "TestB", ...],
  "git_commit_before": "abc123",
  "timestamp": "ISO"
}
```

The `git_commit_before` allows the verification agent to detect test file changes via `git diff --name-only {commit_before} HEAD` filtered against test patterns.

Print: "Baseline captured — {N} tests all passing. This is the behavioral contract."

## Step 5: Plan the Refactor

Analyze the scope and create a phased plan:
- **Identify dependencies**: which files depend on each other? What order minimizes breakage?
- **Break into phases**: each phase should leave tests passing. A phase that breaks tests forces you to fix everything in that phase before you can verify the next one.
- **Identify risk points**: which changes are most likely to break behavior? Those go in separate phases with extra verification.

Present the plan:
```
Refactor Plan:
Phase 1: {description} — affects {files}
Phase 2: {description} — affects {files}
Phase 3: {description} — affects {files}

Each phase: restructure → run tests → verify equivalence. Halt on failure.
```

User approves before execution.

## Step 6: Execute with Agent Separation

For each phase, spawn TWO agents:

**Refactor agent** (forked subagent):
> You are the refactor agent. Restructure the code as described in the phase plan. Focus on structure, not behavior. Do NOT modify test files. If you believe a test is wrong, halt and report — do not "fix" it.
>
> The refactor agent should have `allowed-tools` restricted to: `Read, Grep, Glob, Edit(source files only — NOT test files), Write(source files only — NOT test files), Bash(test and build commands)`. Explicitly exclude files matching `patterns.test_file` from Edit and Write. If the agent attempts to edit a test file, the orchestrator must intercept and trigger the test-change gate.

**Verification agent** (forked subagent, spawned AFTER refactor agent completes):
> You are the verification agent. You did NOT write the refactored code. Your job is to verify behavioral equivalence.
>
> 1. Run the full test suite. Compare against baseline ({N} tests, all passing).
> 2. If any test fails: HALT. Report which tests failed and what the refactor agent changed. This is a behavioral change, not a structural one.
> 3. Check for test file modifications: `git diff --name-only` filtered against test file patterns from `workflow-config.json`. If ANY test file was modified: HALT. Report which test files changed.
> 4. If test count decreased: HALT. Tests were removed.
> 5. Run coverage on refactored files — did coverage decrease? Flag if so.
> 6. If all checks pass: "Phase {N} verified — {M} tests passing, behavioral equivalence confirmed."
>
> The verification agent should have `allowed-tools` restricted to: `Read, Grep, Glob, Bash(git diff*, git status*, test and build commands)` — NO Edit or Write. This is a read-only verification role.

**Between phases**, announce: "Phase {N} complete — {M}/{total} tests passing. Starting phase {N+1}..."

### The Critical Gate: Test Changes

If the verification agent detects a test file modification:

1. **HALT** the refactor.
2. Show the diff of the test file.
3. Present: "Test `{file}` was modified during the refactor. This means behavior changed, not just structure. Possible reasons:
   - The test was testing implementation details (e.g., mock internals) rather than behavior — this test should be rewritten, not silently changed
   - The refactor intentionally changes behavior — document why
   - The refactor accidentally broke something — fix it

   Is this test change intentional?"

   Present the options:

   ```
     1. Approve behavioral change (recommended) — the test correctly reflects new behavior
     2. Reject — revert this test change, find another approach
     3. Split into separate PR — this behavioral change deserves its own review

     Or type your own: ___
   ```

4. User must approve with a reason. Log the approval in the refactor intent artifact.
5. Update the baseline with the new test checksums before proceeding.

**Exception**: Characterization tests that captured a known bug may be updated if the refactor intentionally fixes that bug — but the user must state this explicitly.

## Step 7: QA Review

**Context enforcement (mandatory):** Before spawning the QA agent, check context usage. The QA agent runs as a forked subagent (clean context), but the orchestrator must stay coherent to process findings and manage fix rounds. If above 70%: tell the human "Context is at {N}%. The QA agent will run in fresh context, but I need to be coherent to process findings. Run `/compact` before I spawn QA, or I may miss issues in the findings." If above 85%: "Context is critically full ({N}%). I must stop here. Run `/compact` and then re-run `/crefactor` — the checkpoint will resume from this phase."

After all phases complete, spawn a **QA agent** (forked subagent):

> You are the QA agent for this refactor. You did NOT participate in the refactoring. Your job is to find regressions the test suite didn't catch.
>
> 1. Read the refactor intent document
> 2. Read the git diff of all changes
> 3. Check: did the refactor stay within its stated scope? Are there changes outside the declared files?
> 4. Check `.correctless/antipatterns.md` — does the refactored code introduce any known bug patterns?
> 5. Look for behavioral drift: API response shapes, error messages, log formats, config behavior — things that tests might not cover but downstream consumers depend on
> 6. Check for deleted code that was reachable — dead code removal is fine, but removing code that's called from outside the refactored module is a behavioral change
> 7. Present findings
>
> The QA agent should have `allowed-tools` restricted to: `Read, Grep, Glob, Bash(git*, test commands)` — NO Edit or Write.

QA findings follow the same format as `/ctdd` QA — each finding needs an instance fix AND class fix (or N/A with reason). Persist findings to `.correctless/artifacts/qa-findings-refactor-{slug}.json` (the orchestrator writes this, not the QA agent).

## Step 8: Final Verification

Run the full test suite one more time. Compare against baseline:
- Test count: must be >= baseline
- All original tests: must pass
- Coverage: must be >= baseline on refactored files

Print: "Refactor complete — {N} tests passing (baseline was {M}). Behavioral equivalence verified."

## Step 9: Architecture Update

If the refactor changed the project structure significantly:
- Suggest .correctless/ARCHITECTURE.md updates for moved/renamed components
- Suggest .correctless/AGENT_CONTEXT.md updates for changed paths
- If patterns changed (e.g., "repository layer" moved from `src/db/` to `internal/repo/`), update PAT-xxx entries

## Full Mode Additions

Read `.correctless/config/workflow-config.json`. If `workflow.intensity` is set:

- **Mutation testing**: Run mutation testing on the refactored code. Surviving mutants may reveal tests that no longer exercise the refactored paths effectively — the structure change may have moved behavior away from what tests cover.
- **Cross-spec impact**: Read all specs in `.correctless/specs/`. Does the structural change affect how other features' invariants are satisfied?
- **Drift detection**: Did the refactor resolve or introduce architectural drift? Update `.correctless/meta/drift-debt.json` accordingly.

## After Refactoring

Write the refactor summary to `.correctless/artifacts/refactor-summary-{slug}.md`:
```markdown
# Refactor Summary: {Title}

## Intent: {what was refactored and why}
## Baseline: {N} tests passing before refactor
## Result: {N} tests passing after refactor
## Test Changes: {list of approved test changes with reasons, or "none"}
## Characterization Tests: {N written, if applicable}
## QA Findings: {count and summary}
## Coverage: {before}% → {after}% on refactored files
```

Tell the user: "Refactor complete — {N} tests passing, behavioral equivalence verified. Summary written to `.correctless/artifacts/refactor-summary-{slug}.md`."

If the refactor was part of an active feature workflow (check `workflow-advance.sh status`), the user should continue that workflow. If standalone, the refactor is done — suggest updating .correctless/ARCHITECTURE.md and committing.

**Note:** `/crefactor` does NOT use the TDD state machine. It is a standalone workflow. Do not call `workflow-advance.sh done/verified/documented`. The refactor intent document and summary artifact serve as the audit trail instead of a spec + verification report.

## Claude Code Feature Integration

### Task Lists
See "Progress Visibility" section above — task creation and narration are mandatory.

### Token Tracking

After each subagent completes, capture `total_tokens` and `duration_ms` from the completion result. Append an entry to `.correctless/artifacts/token-log-{slug}.json` (derive slug from the refactor intent filename):

```json
{
  "skill": "crefactor",
  "phase": "{characterization-tests|phase-N-refactor|phase-N-verify|qa}",
  "agent_role": "{test-agent|refactor-agent|verification-agent|qa-agent}",
  "total_tokens": N,
  "duration_ms": N,
  "timestamp": "ISO"
}
```

If the file doesn't exist, create it with the first entry. `/cmetrics` aggregates from raw entries — no totals field needed.

### Background Tasks
- Run coverage analysis in the background while the refactor agent works
- Run mutation testing (at high+ intensity) in the background during QA

## Code Analysis (MCP Integration)

If `mcp.serena` is `true` in `workflow-config.json`, use Serena MCP for symbol-level code analysis during refactoring:

- Use `find_symbol` instead of grepping for function/type names
- Use `find_referencing_symbols` to trace callers and dependencies before moving code
- Use `get_symbols_overview` for structural overview of a module
- Use `replace_symbol_body` for precise symbol-level edits during refactor phases
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

### Context7 — Library Documentation

If `mcp.context7` is `true` in `workflow-config.json`, use Context7 when checking whether a dependency migration path exists during refactoring:

- Use `resolve-library-id` + `get-library-docs` to check if the target library version has a migration guide
- Useful when refactoring involves upgrading a dependency (e.g., "does library-x v3 have a codemod for v2 → v3?")

When Context7 is unavailable, fall back to web search. If Context7 was unavailable during this run, notify the user once at the end.

## If Something Goes Wrong

- **Agent crashes mid-refactor**: Re-run `/crefactor`. The refactor intent document (`.correctless/artifacts/refactor-intent-{slug}.md`) and baseline (`.correctless/artifacts/refactor-baseline-{slug}.json`) persist — the skill can pick up context from these. However, partially completed refactor phases may need manual review.
- **Rate limit hit**: Wait 2-3 minutes and re-run.
- **Tests fail after a refactor phase**: This is working as designed — the verification agent caught a behavioral change. Fix the issue or revert the phase.
- **Want to start over**: Revert uncommitted changes with `git checkout .` and re-run from Step 1.

## Constraints

- **The test suite is the primary spec.** Tests passing is necessary but not sufficient — the QA agent checks for behavioral drift that tests don't cover (API shapes, log formats, error messages). Tests failing is always a blocker.
- **Never silently modify tests.** Every test change requires explicit human approval with a stated reason.
- **Characterization tests capture reality, not intent.** A characterization test that asserts a bug is still correct — it tells you the refactor changed behavior.
- **Phase by phase.** Large refactors must be broken into phases that leave tests passing. No "I'll fix the tests after I'm done restructuring."
- **Agent separation is mandatory.** The refactor agent does not verify. The verification agent did not refactor. Same principle as RED/GREEN in TDD.
- **Context is a reliability constraint.** Above 70%, warn and recommend /compact. Above 85%, stop — instruction adherence degrades and the orchestrator cannot be trusted to manage remaining phases correctly.
- **Evidence before claims.** Never say "tests pass" or "checks out" without running the command fresh in this message and showing the output. "Should pass" is not evidence.
- **All files inside the project directory.** Never /tmp.
