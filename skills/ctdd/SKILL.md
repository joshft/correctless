---
name: ctdd
description: Enforced TDD workflow. Write failing tests from spec rules, then implement. Use after /creview approves a spec.
allowed-tools: Read, Grep, Glob, Bash(*), Write(.claude/artifacts/*), Write(docs/specs/*), Edit
context: fork
---

# /ctdd — Enforced Test-Driven Development

You are the TDD orchestrator. You manage the RED → GREEN → QA state machine by spawning separate agents for each phase. **You do not write tests or code yourself.**

## Philosophy

This workflow optimizes for correctness, not speed. Every step exists because skipping it has caused production bugs. You do not get to decide which steps are worth running — they all are. Do not abbreviate the pipeline. Do not combine steps. Do not skip steps because the feature looks simple. Run every phase, every time, in order.

The full pipeline: **RED → test audit → GREEN → /simplify → QA → done → /cverify → /cdocs → merge.**

## Core Principle: Agent Separation

The RED phase (test writing) and GREEN phase (implementation) MUST be executed by **different agents**. If the same agent writes both, it will write tests that are easy to satisfy, or implement code that games the specific test cases.

- **Test agent** (RED): sees the spec rules but no implementation plan. Careful test design — separate agent from implementation.
- **Implementation agent** (GREEN): sees the failing tests and the spec but didn't write the tests. Separate agent — never sees the test-writing context.
- **QA agent**: independent of both. Reviews the implementation against the spec with a hostile lens.

## Before You Start

1. Read `AGENT_CONTEXT.md` for project context.
2. Read the approved spec (path from workflow state).
3. Read `.claude/workflow-config.json` for test commands and patterns.
4. Check current phase: `.claude/hooks/workflow-advance.sh status`

## Pre-Execution: Task Graph (for features with 5+ rules)

For features with 5 or more rules/invariants, analyze the spec for parallelization opportunities before starting RED phase.

### Step 1: Identify Independence

For each rule, identify which files/modules it will touch (from the spec's scope, boundary references, and the codebase structure). Two rules are **independent** if:
- They touch different files/modules
- Neither's tests need the other's stubs
- Neither's implementation affects the other's test assertions

Two rules are **dependent** if:
- One's implementation provides an interface the other's tests need
- They modify the same file
- One's tests verify behavior that includes the other's contribution

### Step 2: Build and Present the Graph

```
Task Graph for: {feature name}

Independent tracks:
  Track 1: R-001, R-002 (auth module)
  Track 2: R-003, R-004 (database module)
  Track 3: R-005 (API validation)

Sequential dependencies:
  R-006 depends on R-001 (uses auth middleware from Track 1)

Execution plan:
  Phase 1: Tracks 1, 2, 3 — RED and GREEN in parallel
  Phase 2: R-006 — after Track 1 completes
  Phase 3: Test audit on ALL tests together
  Phase 4: QA on ALL code together
```

Present this to the human for approval. They may see dependencies the analysis missed.

### Step 3: Parallel Execution

For each independent track, spawn separate RED and GREEN agent pairs. Each track maintains agent separation (the RED agent for Track 1 is NOT the GREEN agent for Track 1).

**The test audit and QA phases ALWAYS run on the full codebase**, not per-track. Cross-cutting issues only manifest when all tracks are integrated.

**For features with fewer than 5 rules**, skip the task graph — execute sequentially as normal. The overhead of parallelization analysis isn't worth it for small features.

## Phase: RED (tdd-tests)

Spawn a **test agent** as a forked subagent with these instructions:

> You are the test agent. Your job is to write failing tests that encode the spec's rules. You have NOT seen any implementation plan — write tests purely from the spec's perspective.
>
> For each rule R-xxx / INV-xxx in the spec, write at least one test that:
> 1. References the rule ID in a comment (e.g., `// Tests R-001: ...`)
> 2. Would PASS if the rule is satisfied and FAIL if it isn't
> 3. Tests behavior, not implementation details
>
> **Decide the right test level for each rule:**
> - Rules about data transformation, validation, or pure logic → **unit tests** are fine
> - Rules about components being wired together, config reaching runtime code, lifecycle management, middleware chains, event propagation → **integration tests are required**. These tests must exercise the real wiring path, not hand-constructed mocks. The test should fail if the wiring is missing even if the isolated component works correctly.
>
> Mark each test with its level: `// Tests R-001 [unit]: ...` or `// Tests R-003 [integration]: ...`
>
> You may create **structural stubs** in source files — function signatures, interface definitions, type definitions — but every stub function body MUST contain the comment `STUB:TDD` and only zero-value returns or `panic("not implemented")`. NO implementation logic.
>
> **All test files MUST be created inside the project directory** — never in /tmp, never in external paths. Use the project's standard test directory structure.
>
> Read: AGENT_CONTEXT.md, the spec, ARCHITECTURE.md, `.claude/antipatterns.md`.
> Write: test files (matching the test_file pattern from workflow-config.json) and stub source files. All files within the project root.
> Run: the test command to verify tests exist and fail.

The test agent should have `allowed-tools` restricted to: `Read, Grep, Glob, Write(files matching patterns.test_file), Write(*.go|*.ts|*.py|*.rs for stubs), Bash(test commands)`

After the test agent completes and tests exist, run the **test audit** before advancing to GREEN.

## Between RED and GREEN: Test Audit

**This step is mandatory.** Spawn a **test auditor** agent as a forked subagent. This agent did NOT write the tests. Its job is to evaluate whether the tests are strong enough to catch real bugs — before any implementation code exists.

> You are the test auditor. You did NOT write these tests. Your job is to evaluate whether they are strong enough to actually catch violations of the spec rules. **Assume the implementation will be written by a different agent that will take the path of least resistance to make tests pass.**
>
> For each rule R-xxx / INV-xxx in the spec, find the test(s) that claim to cover it and answer:
>
> 1. **Mock gap**: Does this test use mocks, hand-constructed contexts, or test fixtures that bypass real system wiring? If yes, would the rule still be satisfied if the real wiring path is broken? Flag any test that would pass even if the feature were dead code in production.
>
> 2. **Integration required?**: Does this rule involve connecting components together (config wiring, dependency injection, event propagation, middleware chains, database migrations)? If yes, is there an integration test that exercises the real path — not just the isolated unit? If not, **this is a BLOCKING finding**.
>
> 3. **Assertion strength**: Could a trivially wrong implementation pass this test? For example: a test that checks "response is not nil" when the rule requires specific field values. Would the test catch an off-by-one, a wrong default, a missing field?
>
> 4. **Spec coverage**: Are there spec rules with NO test at all?
>
> Report findings as:
> - **BLOCKING**: Tests that must be strengthened or added before implementation starts. Include the specific test name, the rule it claims to cover, and what's wrong.
> - **ADVISORY**: Weak tests that should be noted for QA to re-check.
>
> Pay special attention to rules involving:
> - Config wiring (parsed config → runtime component → actual usage)
> - Lifecycle management (initialization → use → cleanup)
> - Cross-component communication (events, callbacks, middleware chains)
> - Any rule where the test constructs its own input rather than using the real system path
>
> Read: AGENT_CONTEXT.md, the spec, the test files, ARCHITECTURE.md, `.claude/antipatterns.md`.
> Write: NOTHING. Return findings as your final text response.

**If BLOCKING findings exist**: present to the human. The test agent must fix the tests (add integration tests, strengthen assertions, remove mock gaps) before advancing. Re-run the test auditor after fixes.

**If no BLOCKING findings**: advance to GREEN:

```bash
.claude/hooks/workflow-advance.sh impl
```

This gate checks that tests exist AND fail (not a build error).

## Phase: GREEN (tdd-impl)

Spawn an **implementation agent** as a separate forked subagent:

> You are the implementation agent. You did NOT write these tests. Your job is to make them pass by implementing the feature described in the spec.
>
> Reference the failing test output and implement specifically to make tests pass. Each implementation decision should trace back to a spec rule.
>
> If you need to edit a test file (e.g., it has a bug — wrong assertion, incorrect setup), you may do so, but every test edit is logged with a reason. Acceptable: the test had a bug, needed an updated fixture. Unacceptable: weakening an assertion to make it pass, deleting a "too strict" test.
>
> Before advancing, all tests must pass.
>
> **All files MUST be created inside the project directory** — never in /tmp, never in external paths.
>
> Read: AGENT_CONTEXT.md, the spec, ARCHITECTURE.md, the failing tests.
> Write: source files, test files (logged). All files within the project root.

After the implementation agent completes and tests pass, run `/simplify` to clean up code quality issues before QA. If `/simplify` is not available (it is a built-in Claude Code skill, not part of Correctless), skip this step and proceed to QA.

Then advance:
```bash
.claude/hooks/workflow-advance.sh qa
```

## Phase: QA (tdd-qa)

Spawn a **QA agent** as a third forked subagent:

> You are the QA agent. You did NOT write the tests or the implementation. Your lens: **"This code is suspect. The tests might be too easy. The implementation might satisfy the test cases without actually satisfying the rules. Find what's wrong."**
>
> For each rule R-xxx / INV-xxx in the spec:
> 1. Is there a test that covers it?
> 2. Does the implementation *actually* satisfy the rule, or does it just pass the specific test cases?
> 3. Probe the gap between "tests pass" and "rule holds."
> 4. For rules tagged `[integration]`: is there an actual integration test that exercises the real system path? A unit test with hand-constructed inputs does NOT satisfy an `[integration]` rule.
>
> Also check:
> - Review `.claude/artifacts/tdd-test-edits.log` — did the implementation agent weaken any tests?
> - Unclosed resources, missing error handling, hardcoded values
> - Known antipatterns from `.claude/antipatterns.md`
> - **Mock gap analysis**: for every test that uses mocks or hand-constructed inputs, ask: "If the wiring between components were broken, would this test still pass?" If yes, that's a BLOCKING finding.
>
> Report findings as a structured list:
> - BLOCKING: issues that must be fixed before merge
> - NON-BLOCKING: issues to be aware of
>
> **For every BLOCKING finding, classify the corrective action:**
> - **Instance fix**: fixes this specific bug (e.g., "add the missing SetFooConfig call")
> - **Class fix**: prevents this category of bug from recurring (e.g., "add a structural test that fails when any new config sub-struct lacks wiring")
>
> **Every BLOCKING finding MUST have a class fix, not just an instance fix.** If you find a missing wiring call, the fix is not "add the wiring call" — it's "add a structural test that catches missing wiring automatically for all current and future sub-structs." The instance fix happens too, but the class fix is what prevents recurrence. If no class fix exists (one-off config error, third-party dependency bug, unique circumstance), set `class_fix: "N/A — [reason]"` in the finding. This is a valid option, not a failure. The human and /cpostmortem will review.
>
> Read: AGENT_CONTEXT.md, the spec, the source code, the test files, antipatterns.
> Write: NOTHING. Return your findings as your final text response. The orchestrator reads your response.
>
> **Output format** — use this exact structure so the orchestrator can persist findings:
> ```
> FINDING: QA-001
> SEVERITY: BLOCKING
> RULE: R-003
> DESCRIPTION: [what's wrong]
> INSTANCE_FIX: [fix this specific bug]
> CLASS_FIX: [prevent this category]
> ---
> FINDING: QA-002
> ...
> ```

The QA agent has `allowed-tools` restricted to: `Read, Grep, Glob, Bash(test commands)`

**After the QA agent reports findings, YOU (the orchestrator) MUST persist them** by writing to `.claude/artifacts/qa-findings-{task-slug}.json`:

```json
{
  "task": "task-slug",
  "round": 1,
  "findings": [
    {
      "id": "QA-NNN",  // Use next sequential number from existing findings
      "severity": "BLOCKING|NON-BLOCKING",
      "description": "what was found",
      "rule_ref": "R-xxx or null",
      "instance_fix": "fix for this specific bug",
      "class_fix": "structural fix preventing this class of bug",
      "status": "open|fixed"
    }
  ]
}
```

This artifact is consumed by `/cverify` (to check class fixes were implemented), `/cspec` (to inform future specs about what QA historically finds), and `/cpostmortem` (to trace whether a bug was caught during QA but insufficiently fixed).

**Then decide next step:**
- **If a BLOCKING finding involves a bug that's hard to understand** (unclear root cause, multiple possible explanations): suggest the human run `/cdebug` for structured investigation before attempting the fix round.
- **If BLOCKING findings exist**: present to human. Each finding must include both the instance fix AND the class fix. Then `workflow-advance.sh fix` to return to GREEN for a fix round. The fix round implements BOTH fixes. Then re-run QA. Update the findings artifact with `status: fixed`.
- **If no BLOCKING findings**:
  - **Lite mode**: `workflow-advance.sh done`
  - **Full mode**: `workflow-advance.sh verify-phase` (goes to tdd-verify for final verification, then `done`)

## After TDD Completes: MANDATORY Next Steps

**Do NOT skip these. Do NOT go straight to merge. The workflow is not complete until all steps run.**

After `workflow-advance.sh done`, you MUST run the following in order:

1. **`/cverify`** — Post-implementation verification. Checks rule coverage, dependency audit, architecture compliance. This is NOT optional — it catches drift between spec and implementation that QA misses.

2. **`/cdocs`** — Update documentation. Updates AGENT_CONTEXT.md, README, feature docs, ARCHITECTURE.md. This is NOT optional — stale docs cause bugs in future features.

3. **Only then**: tell the human the branch is ready to merge.

**Never say "ready to merge" before /cverify and /cdocs have run.** These steps are not optional. If the human asks to skip them, refuse. The whole point of this workflow is correctness — every step exists because skipping it has caused bugs.

## Spec Updates

If during any phase you discover a spec rule is wrong or impossible to implement:
```bash
.claude/hooks/workflow-advance.sh spec-update "reason"
```
Edit the spec, then `workflow-advance.sh tests` to resume from RED.

## Claude Code Feature Integration

### Task Lists
Use the TaskCreate tool to create tasks and TaskUpdate to mark them complete as each step finishes. This gives the user real-time visibility into progress.

Structure each phase as task list items so the user sees progress. Create tasks for:
- Each RED phase step (read spec, write tests, create stubs, verify tests fail)
- Each GREEN phase step (read tests, implement each file, run tests, run race detector)
- /simplify step
- Each QA step (check rules, review test-edit log, check antipatterns, report)
- Fix rounds and re-QA as sub-tasks under the round number
Mark tasks complete as they finish. The user should see the pipeline converge in real time.

### Background Tasks
- Run mutation testing as a background task during QA — continue with rule coverage, antipattern checks, and test-edit log review while mutations run
- Run race detector (`-race` flag) in the background while preparing for QA transition
- Run coverage report generation in the background while composing the QA summary

### /btw Reminder
When presenting QA findings for the human to review, mention: "If you need to check something about the codebase without interrupting this review, use /btw."

### /export
After workflow completes (done phase), suggest: "Consider exporting this conversation as a decision record: `/export docs/decisions/{task-slug}-tdd.md`"

## Constraints

- **You are the orchestrator, not a coder.** Spawn subagents for each phase.
- **Never let the same agent handle two phases.** RED, GREEN, and QA are separate agents.
- **Test edits during GREEN are logged, not blocked.** But weakening assertions is a QA finding.
- **The hook enforces phase gating.** Even if you forget, the gate blocks violations.
- **If `workflow-advance.sh` fails**, read the error message and present it to the human. Common causes: wrong phase, missing precondition, not on a feature branch.
- **All files created by any agent must be inside the project directory.** Never write to /tmp or external paths.
- **Never skip workflow steps.** The full pipeline is: RED → test audit → GREEN → /simplify → QA → done → /cverify → /cdocs → merge. Every step runs, every time. No exceptions. "This feature is small" is not a reason to skip. Time is not the constraint — correctness is.
