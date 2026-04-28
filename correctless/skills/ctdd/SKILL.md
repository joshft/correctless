---
name: ctdd
description: Enforced TDD workflow. Write failing tests from spec rules, then implement. Use after /creview approves a spec.
allowed-tools: Read, Grep, Glob, Bash(*), Write(.correctless/artifacts/*), Write(.correctless/specs/*), Edit
context: fork
---

# /ctdd — Enforced Test-Driven Development

> **EXECUTE IMMEDIATELY.** This skill being loaded into your context IS the user's instruction. The user invoked `/ctdd` — that is the request. Do not ask "what would you like me to do?" Do not wait for further instruction. Read the workflow state via `.correctless/hooks/workflow-advance.sh status`, locate the spec, and begin the phase indicated by that state. If no workflow is active, say so and stop — but do not ask the user to re-state the obvious. (Counter-instruction added 2026-04-26 for Opus 4.7 skill-invocation regression — see OPUS_4_7_MIGRATION.md S-0-06.)

> **Shared constraints apply.** Before executing, read `_shared/constraints.md` from the parent of this skill's base directory. All constraints there apply to this skill.

You are the TDD orchestrator. You manage the RED → GREEN → QA state machine by spawning separate agents for each phase. **You do not write tests or code yourself.**

## Intensity Configuration

| | Standard | High | Critical |
|---|---|---|---|
| Test audit | Blocking | Strict | Strict + PBT recommendations |
| QA rounds | 2 max | 3 max | 5 max (convergence, capped) |
| Mini-audit rounds | 1 | 2 | 3 |
| Mutation testing | No | Yes | Yes |
| Calm resets | After 3 failures | After 2 failures | After 2 + supervisor notified |

## Effective Intensity

Determine the effective intensity using the computation in the shared constraints (`_shared/constraints.md`).

## Philosophy

This workflow optimizes for correctness, not speed. Every step exists because skipping it has caused production bugs. You do not get to decide which steps are worth running — they all are. Do not abbreviate the pipeline. Do not combine steps. Do not skip steps because the feature looks simple. Run every phase, every time, in order.

### Intensity-Aware TDD Behavior

- At standard intensity: QA runs 2 max rounds. Test audit is blocking (must pass before GREEN).
- At high intensity: QA runs 3 max rounds. Mutation testing is required. Calm resets trigger after 2 failures.
- At critical intensity: QA runs 5 max rounds (convergence, capped). PBT (property-based testing) recommendations are included in the test audit. Mutation testing is required. Calm resets trigger after 2 failures with supervisor notified.

The full pipeline: **RED → test audit → GREEN → /simplify → QA → mini-audit → done → /cverify → /cdocs → merge.**

## Progress Visibility (MANDATORY)

The TDD workflow can take 15-30+ minutes. The user must see what's happening at all times. Silence is not acceptable.

**Before starting any work**, create a task list showing the full pipeline:
1. RED: Write failing tests from spec
2. Test audit: Check test quality before implementation
3. GREEN: Implement to make tests pass
4. /simplify: Clean up code quality
5. QA: Independent review of tests + implementation
6. (If QA finds issues: Fix round N → re-QA)
7. Mini-audit: Adversarial specialist review (cross-component, hostile input, resource bounds)

**Between every phase**, print a mini pipeline diagram showing progress. Mark completed phases with `✓` and the current phase with `▶`:

```
  ✓ RED → ✓ audit → ▶ GREEN → simplify → QA → mini-audit → done
```

Update the diagram each time a phase completes. After QA with fix rounds:

```
  ✓ RED → ✓ audit → ✓ GREEN → ✓ simplify → ✓ QA:R1 → ✓ fix → ▶ QA:R2
```

**Also print a 1-line status update:**
- "Spawning test-writing agent — reading spec ({N} rules), .correctless/ARCHITECTURE.md, antipatterns..."
- "RED complete — {N} test files, {M} test cases, all failing as expected. Running test audit..."
- "Test audit passed — {N} suggestions applied. Spawning implementation agent..."
- "GREEN complete — all {M} tests passing. Running /simplify..."
- "/simplify done. Spawning QA agent..."
- "QA found {N} issues ({C} critical, {H} high). Starting fix round 1..."

**When spawning a subagent**, tell the user what it's doing. When it completes, immediately announce results before moving to the next step.

Mark each task complete as it finishes. The user should watch the pipeline progress in real time.

## Core Principle: Agent Separation

The RED phase (test writing) and GREEN phase (implementation) MUST be executed by **different agents**. If the same agent writes both, it will write tests that are easy to satisfy, or implement code that games the specific test cases.

- **Test agent** (RED): sees the spec rules but no implementation plan. Careful test design — separate agent from implementation.
- **Implementation agent** (GREEN): sees the failing tests and the spec but didn't write the tests. Separate agent — never sees the test-writing context.
- **QA agent**: independent of both. Reviews the implementation against the spec with a hostile lens.

## Before You Start

**First-run check**: If `.correctless/config/workflow-config.json` does not exist, tell the user: "Correctless isn't set up yet. Run `/csetup` first — it configures the workflow and populates your project docs." If the config exists but `.correctless/ARCHITECTURE.md` contains `{PROJECT_NAME}` or `{PLACEHOLDER}` markers, offer: ".correctless/ARCHITECTURE.md is still the template. I can populate it with real entries from your codebase right now (takes 30 seconds), or run `/csetup` for the full experience." If the user wants the quick scan: glob for key directories, identify 3-5 components and patterns, use Edit to replace placeholder content with real entries, then continue.

### Checkpoint Resume

After reading the workflow state (step 6 below), check for `.correctless/artifacts/checkpoint-ctdd-{slug}.json` (derive slug from the workflow state file's spec_file basename). Also check that the checkpoint branch matches the current branch — ignore checkpoints from other branches.

- **If found and <24 hours old**: Read `completed_phases`. Before skipping, verify the current phase:
  - After `red`: test files exist and fail when run
  - After `test-audit`: test files exist (audit feedback already applied)
  - After `green`: run test suite — tests must pass
  - After `simplify`: run test suite — tests must still pass
  - After `qa`: `.correctless/artifacts/qa-findings-{slug}.json` exists
  If verification passes: "Found checkpoint from {timestamp} — {completed phases} already done. Resuming from {next phase}." Skip completed phases. If verification fails: restart from the phase that failed verification.
- **If found but >24 hours old**: "Stale checkpoint found (from {date}). Starting fresh."
- **If not found**: Start from the beginning as normal.

After each major phase (`red`, `test-audit`, `green`, `simplify`, `qa`) completes, write/update the checkpoint:
```json
{
  "skill": "ctdd",
  "slug": "{task-slug}",
  "branch": "{current-branch}",
  "completed_phases": ["red", "test-audit"],
  "current_phase": "green",
  "timestamp": "ISO"
}
```
Clean up the checkpoint file when the skill completes successfully.

1. Read `.correctless/AGENT_CONTEXT.md` for project context.
2. Read the approved spec (path from workflow state).
3. Read `.correctless/config/workflow-config.json` for test commands and patterns.
4. **Verify required config fields exist**:
   - If `commands.test` is null, absent, or empty: "No test command is configured in `.correctless/config/workflow-config.json`. Add a `commands.test` field (e.g., `\"npm test\"`) or re-run `/csetup` to detect your test runner." Do not proceed.
   - If `patterns.test_file` is null, absent, or empty: "No test file pattern is configured in `.correctless/config/workflow-config.json`. Add a `patterns.test_file` field (e.g., `\"*.test.ts\"`) or re-run `/csetup` to detect your test patterns." Do not proceed. This pattern is used by the workflow gate to distinguish test files from source files during phase enforcement.
5. **Verify the test runner works**: Run `commands.test` from the config. If it fails with "command not found" or exits immediately: "Test command `{cmd}` is not available. Check `.correctless/config/workflow-config.json` and make sure your test runner is installed." Do not proceed until the test command is functional.
6. Check current phase: `.correctless/hooks/workflow-advance.sh status`

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

Invoke the RED test writer via plugin sub-agent (M-1 migration, 2026-04-26 — extracted to counter Opus 4.7 over-deliberation defaults observed in OPUS_4_7_MIGRATION.md S-0-02):

```
Task(subagent_type="correctless:ctdd-red",
     description="Write failing tests for spec rules",
     prompt="<spec path from workflow-advance.sh status>
             <pointer to .correctless/AGENT_CONTEXT.md, .correctless/ARCHITECTURE.md, .correctless/antipatterns.md>
             <test_file pattern + commands.test from workflow-config.json>")
```

The agent definition lives at `agents/ctdd-red.md` and has `tools: Read, Grep, Glob, Write, Edit, Bash` with `context: fork`. The system prompt body in that file contains the behavioral discipline (no task graphs, no approval-seeking, write tests immediately) and the same content-level instructions previously inlined here (rule coverage, integration test contracts, entrypoint awareness, structural stubs with STUB:TDD markers, file location constraints).

Do NOT inline the prompt here. Per ABS-010 / AP-013, the agent file is the single source of truth.

After the test agent completes and returns, verify tests exist and fail before advancing:

```bash
bash .correctless/hooks/workflow-advance.sh status  # confirm phase still tdd-tests
# Run commands.test to confirm tests fail (expected RED state)
```

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
> 5. **Test-routing (AP-016)**: For each spec rule that cites a specific endpoint, method, function, or path (a spec-named resource), verify at least one test actually calls or references that spec-named resource. Tests that cover auxiliary or simpler paths while avoiding the spec-named resource are a BLOCKING finding — the agent is routing around the requirement.
>
> 6. **Hand-rolled mocks (AP-017)**: Flag tests that define mock structs, stub classes, or hand-rolled test doubles that always return success without referencing a mock generator framework (e.g., `go:generate mockgen`, `unittest.mock.patch(spec=)`, `jest.mock`). A hand-rolled mock that can't fail makes failure-mode testing impossible. This is a BLOCKING finding when generated alternatives exist for the language.
>
> 7. **Execution evidence (AP-018)**: For tests tagged `[integration]` or `[e2e]`, verify the test was actually executed — not just compiled or listed. Look for execution evidence: real timestamps progressing in test output, actual command stderr/stdout, reasonable test durations. A test that only checks compilation or imports without running is a BLOCKING finding.
> 8. **Production call chain (dead-code-in-security-paths)**: For each security-critical invariant (PRH-xxx, INV-xxx with security category), the spec statement should name the production entry point (e.g., "enforced via `check_override_retry` called from `cmd_override`"). Verify the test exercises the full entry-point to guard chain, not just the guard function in isolation. A test that calls the guard function directly without going through the named entry point is a BLOCKING finding for invariants that specify the call chain. Detection: grep the spec for "called from" or "invoked by" patterns and verify the named entry point appears in the test's call path. Note: this check pairs with `dead-security-fn` in `scripts/antipattern-scan.sh` — the scanner catches the mechanical case (zero production callers), this check catches the semantic case (called but from the wrong entry point).
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
> 9. **Integration test contract verification**: For each `[integration]` rule that has an Entry/Through/Exit contract, verify the test satisfies the contract. The three checks operate at different verification tiers:
>
>   | Check | Type | Severity | What it verifies |
>   |-------|------|----------|-----------------|
>   | Entry | Mechanical | BLOCKING | Test file contains evidence of using the specified entrypoint (e.g., `httptest.NewServer` if Entry says so). A grep can verify this. |
>   | Through | Semi-mechanical | BLOCKING or UNCERTAIN | Test does NOT mock/stub components on the "must not mock" list. Language-dependent. If the auditor can mechanically confirm a violation: BLOCKING. If the mock pattern is unfamiliar or ambiguous: UNCERTAIN — flag for human review, do not gate. |
>   | Exit | Semantic | BLOCKING (definite mismatch) or ADVISORY (uncertain) | Test contains assertions matching the Exit constraint's observable behavior. If the auditor can positively determine the assertion doesn't match: BLOCKING. If uncertain: ADVISORY. The "definitely wrong" bar must be high. |
>
>   For `[integration]` rules without contracts (e.g., entrypoints were unavailable), the test audit notes: "R-xxx has no integration contract — test shape not audited" so the user knows the gap exists.
>
>   Note: these checks verify test *shape*, not test *behavior*. This is complementary to PAT-012 (wiring tests over keyword tests), not in conflict — PAT-012 governs what the test exercises at runtime, contract verification governs what the test is structurally allowed to fake.
>
> 10. **Internal import bypass detection**: For each `[integration]` test, check whether the test imports or directly references internal packages/modules that are covered by a documented entrypoint's `scope` globs. Read entrypoints from `.correctless/ARCHITECTURE.md` (via the fenced YAML block or `scripts/extract-entrypoints.sh`). For each entrypoint, build a map of scope globs to entrypoint names. For each `[integration]` test file, check whether any import/require/source statement references a path that falls within an entrypoint's scope. The check is language-aware at a basic level: Go `import "pkg/..."`, TypeScript/JavaScript `import ... from '...'` or `require('...')`, Python `from pkg import` or `import pkg`, Rust `use crate::` or `mod`. For languages not in this list, the check is skipped with an ADVISORY note: "Cannot detect internal imports for language {X} — manual review recommended."
>
>     If a test imports `pkg/handlers/auth.go` directly, and an entrypoint exists with `scope: ["pkg/handlers/**"]` and `test_via: "httptest.NewServer(handler)"`, then the test is bypassing the entrypoint. This is a **BLOCKING** finding: "Test for R-xxx imports internal package `pkg/handlers/auth` directly. Entrypoint `api-server` covers this path — use `test_via: httptest.NewServer(handler)` instead."
>
>     The check does NOT flag imports of the entrypoint itself (e.g., importing `cmd/server/main.go` when that IS the entrypoint handler). It only flags imports of packages *within* the entrypoint's scope that should be reached *through* the entrypoint, not directly. The `test_via` pattern indicates how to reach the entrypoint; the `scope` globs indicate what's behind it.
>
>     When check 10 and check 9 (Entry contract verification) both fire on the same test for the same rule, present one consolidated finding rather than two: "Test for R-xxx bypasses entrypoint `api-server`: imports `pkg/handlers/auth` directly instead of using `httptest.NewServer(handler)`." The checks remain independent (check 9 can fire without check 10 and vice versa), but when they converge on the same test, the user sees one thing to fix.
>
>     When entrypoints are unavailable (`.correctless/ARCHITECTURE.md` missing or no `correctless:entrypoints:start` markers), the internal import bypass check is skipped entirely. The test audit notes: "No documented entrypoints — internal import bypass check skipped."
>
> Read: .correctless/AGENT_CONTEXT.md, the spec, the test files, .correctless/ARCHITECTURE.md (especially the Entrypoints section and Key Patterns), `.correctless/antipatterns.md`.
> Write: NOTHING. Return findings as your final text response.

**If BLOCKING findings exist**: present each finding to the human with disposition options:

```
  1. Fix now (recommended) — implement instance fix + class fix
  2. Accept risk — document why this finding is acceptable
  3. Dispute — explain why this is not actually an issue

  Or type your own: ___
```

The test agent must fix the approved findings (add integration tests, strengthen assertions, remove mock gaps) before advancing. Re-run the test auditor after fixes.

**If no BLOCKING findings**: advance to GREEN:

```bash
.correctless/hooks/workflow-advance.sh impl
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
> When the implementation agent edits a test file, present the edit to the user:
>
>   1. Approve change (recommended) — the edit is a legitimate fix
>   2. Reject — revert the test edit, find another implementation approach
>   3. Modify — adjust the test edit before accepting
>
>   Or type your own: ___
>
> Before advancing, all tests must pass.
>
> **All files MUST be created inside the project directory** — never in /tmp, never in external paths.
>
> Read: .correctless/AGENT_CONTEXT.md, the spec, .correctless/ARCHITECTURE.md, the failing tests.
> Write: source files, test files (logged). All files within the project root.
> Log all test edits to `.correctless/artifacts/tdd-test-edits.log` with timestamp and reason.
>
> The implementation agent should have `allowed-tools` restricted to: `Read, Grep, Glob, Edit, Write(source and test files inside project root), Write(.correctless/artifacts/tdd-test-edits.log), Bash(test and build commands)`

### GREEN Phase Calm Reset Prompt (R-001)

The orchestrator tracks the implementation agent's consecutive failure count in its own conversation context (working memory). When the attempt count reaches 3 or more consecutive failures within the GREEN phase, the orchestrator appends this calm reset prompt to the implementation agent's next prompt:

> **Reset — stop building on previous failed approaches.**
> You have had 3 consecutive failed attempts. Stop. Do not continue iterating on the approach that has failed — abandon previous failed approaches entirely.
>
> Re-read the spec rule and the failing test output fresh. Read them as if for the first time. Then ask yourself: what is the test ACTUALLY checking? Describe the assertion literally — not what you assume it checks, but what the code on the line does.
>
> There is no time pressure. There is no rush. Correctness matters more than speed. Re-read the test file fresh before writing any code.
>
> If you're still stuck after this attempt, stop and ask the human for guidance rather than trying another approach.

This reset prompt fires at most once per trigger point per phase — no stacking. If the subsequent attempt after the reset also fails, the orchestrator escalates to the human instead of injecting another reset (see Reset Escalation below).

After the implementation agent completes and tests pass, run `/simplify` to clean up code quality issues before QA. If `/simplify` is not available (it is a built-in Claude Code skill, not part of Correctless), omit this step and proceed to QA.

### Commit Metadata (Git Trailers)

Read `.correctless/config/workflow-config.json`. If `workflow.git_trailers` is `true`, include structured trailers in all commits during TDD. If the field is absent or `false`, commit normally without trailers.

**Format for test commits (RED phase):**
```
test(task-slug): write failing tests for R-001, R-002

Spec: .correctless/specs/{task-slug}.md
Rules-covered: R-001, R-002
Phase: RED
```

**Format for implementation commits (GREEN phase):**
```
feat(task-slug): implement rules R-001, R-002

Spec: .correctless/specs/{task-slug}.md
Rules-covered: R-001, R-002
```

**Format for QA fix-round commits:**
```
fix(task-slug): address QA finding QA-001

Spec: .correctless/specs/{task-slug}.md
QA-rounds: {N}
QA-finding: QA-001
```

Read the spec path from workflow state (`.spec_file`). Read the QA round from `.qa_rounds`. Determine covered rules by matching test assertions to spec rule IDs.

Trailers go after a blank line at the end of the commit message. They are queryable: `git log --format='%(trailers:key=Spec)'` shows which specs produced which commits.

Then advance:

**Context enforcement (mandatory):** Before spawning the QA agent, check context usage. The QA agent ALWAYS runs as a forked subagent (`context: fork`) which gives it clean context. But if the orchestrator's context exceeds 70%, it may not correctly process the QA agent's findings or manage fix rounds. If above 70%: tell the human "Context is at {N}%. The QA agent will run in fresh context, but I need to be coherent to process findings. Run `/compact` before I spawn QA, or I may miss issues in the findings." If above 85%: "Context is critically full ({N}%). I must stop here. Run `/compact` and then re-run `/ctdd` — the checkpoint will resume from this phase."

```bash
.correctless/hooks/workflow-advance.sh qa
```

## Pre-QA: Antipattern Scan

Before spawning the QA agent, run the deterministic antipattern scanner:

```bash
bash .correctless/scripts/antipattern-scan.sh {default_branch}
```

where `{default_branch}` is read from `workflow.default_branch` in `workflow-config.json`, falling back to `main` if absent.

Validate that stdout is non-empty valid JSON with a `.findings` key before treating it as findings. Empty or invalid output means the scanner itself failed and must be reported as an error, not "zero findings." Also check if the JSON contains an `errors` array with entries — if so, report these scanner errors to the user rather than silently discarding them.

If the JSON output includes a `summaries` array (present when files exceed the 20-finding cap), include these in the report.

Pass the scanner's findings to the QA agent as context: "Deterministic scan found {N} antipatterns. These are already identified — focus on semantic issues. Note: these findings are heuristic (grep-based), not authoritative — verify before citing." The QA agent should also review the semantic ai-antipatterns checklist at `.correctless/checklists/ai-antipatterns.md` for patterns not detectable by grep.

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
> - Review `.correctless/artifacts/tdd-test-edits.log` — did the implementation agent weaken any tests?
> - Unclosed resources, missing error handling, hardcoded values
> - Known antipatterns from `.correctless/antipatterns.md`
> - **Mock gap analysis**: for every test that uses mocks or hand-constructed inputs, ask: "If the wiring between components were broken, would this test still pass?" If yes, that's a BLOCKING finding.
>
> Report findings as a structured list:
> - BLOCKING: issues that must be fixed before merge
> - NON-BLOCKING: issues to be aware of
> - UNCERTAIN: issues where you cannot confidently determine whether the problem is real. Use this when you can see a potential issue but cannot trace the full code path, don't understand the system well enough to confirm, or the evidence is ambiguous. UNCERTAIN findings are non-blocking and advisory — they are presented to the user with your reasoning about why you're unsure. Do not inflate uncertain issues to BLOCKING — honest uncertainty is a valid output. Do not silently suppress uncertain issues either — flag them so the human can investigate.
>
> **For every BLOCKING finding, classify the corrective action:**
> - **Instance fix**: fixes this specific bug (e.g., "add the missing SetFooConfig call")
> - **Class fix**: prevents this category of bug from recurring (e.g., "add a structural test that fails when any new config sub-struct lacks wiring")
>
> **Every BLOCKING finding MUST have a class fix, not just an instance fix.** If you find a missing wiring call, the fix is not "add the wiring call" — it's "add a structural test that catches missing wiring automatically for all current and future sub-structs." The instance fix happens too, but the class fix is what prevents recurrence. If no class fix exists (one-off config error, third-party dependency bug, unique circumstance), set `class_fix: "N/A — [reason]"` in the finding. This is a valid option, not a failure. The human and /cpostmortem will review.
>
> Read: .correctless/AGENT_CONTEXT.md, the spec, the source code, the test files, antipatterns.
> Write: NOTHING. Return your findings as your final text response. The orchestrator reads your response.
>
> **Output format** — use this exact structure so the orchestrator can persist findings:
> ```
> FINDING: QA-001
> SEVERITY: BLOCKING|NON-BLOCKING|UNCERTAIN
> RULE: R-003
> DESCRIPTION: [what's wrong]
> INSTANCE_FIX: [fix this specific bug]
> CLASS_FIX: [prevent this category]
> ---
> FINDING: QA-002
> ...
> ```

The QA agent has `allowed-tools` restricted to: `Read, Grep, Glob, Bash(test commands)`

**After the QA agent reports findings, YOU (the orchestrator) MUST persist them** by writing to `.correctless/artifacts/qa-findings-{task-slug}.json`:

```json
{
  "task": "task-slug",
  "round": 1,
  "findings": [
    {
      "id": "QA-NNN",  // Use next sequential number from existing findings
      "severity": "BLOCKING|NON-BLOCKING|UNCERTAIN",
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
- **If BLOCKING findings exist**: present to human. Each finding must include both the instance fix AND the class fix. Then `workflow-advance.sh fix` to return to GREEN for a fix round. Spawn a **fix agent** with these additional instructions:

  > After fixing each finding, the fix agent must update `.correctless/artifacts/qa-findings-{task-slug}.json`: set `"status": "fixed"` on the findings you addressed. This ensures the findings artifact stays current as fixes land.

  The fix round implements BOTH instance and class fixes. Then re-run QA. After each fix round, the orchestrator must verify the findings JSON: any finding whose instance_fix was applied but still shows `"status": "open"` should be updated to `"fixed"` by you (the orchestrator). This catches cases where the fix agent forgot to update the status.

### Fix Round Calm Reset Prompt (R-011)

The orchestrator tracks the fix agent's consecutive failure count separately from the GREEN phase count. When the fix phase reaches 3 consecutive failures within a single fix round, the orchestrator appends this fix reset prompt to the fix agent's next prompt:

> **Fix phase reset — stop building on previous failed approaches.**
> You have had 3 consecutive failed attempts in the fix phase. Stop. Do not continue the approach that has failed — fix attempts must abandon previous failed strategies.
>
> Re-read the specific QA finding's `instance_fix` and `class_fix` fields from the findings JSON. Read each field literally. Then ask yourself: what is the finding ACTUALLY describing? Describe the desired behavior change, not what you assume it means.
>
> Fix phase: there is no rush. There is no time pressure. Take the time to understand the finding before writing any code. Re-read the finding fresh.
>
> If you're still stuck after this attempt, stop and ask the human for guidance rather than trying another approach.

This is distinct from the GREEN phase reset (R-001) — R-011 fires on consecutive failures within a single fix round, not during initial implementation. It is also distinct from R-002 (recurring BLOCKINGs across QA rounds).

### QA Fix Round Calm Reset — Recurring BLOCKINGs (R-002)

When a QA round returns 2 or more BLOCKING findings after a previous fix round already addressed BLOCKING findings (i.e., recurring BLOCKING findings — the fix didn't stick), the orchestrator appends this reset prompt to the fix agent for the next fix round. This reset fires when 2+ BLOCKING findings recur across QA rounds, which means the previous fix approach was insufficient:

> **Reset for recurring BLOCKING findings.**
> QA findings are descriptions of desired behavior, not criticism. Each finding describes a concrete gap between the current code and the spec.
>
> Re-read each finding's `instance_fix` and `class_fix` fields from the findings JSON before attempting any fixes. Do not re-attempt the same approach that failed in the previous round — the recurring BLOCKINGs prove that approach was wrong.
>
> Re-read the findings fresh. Understand what each finding is actually asking for before writing code.
>
> If you're still stuck after this attempt, stop and ask the human for guidance rather than trying another approach.

### Reset Escalation (R-008)

Reset prompts fire at most once per trigger per phase — no stacking. After a calm reset prompt fires and the subsequent attempt also fails, the orchestrator MUST escalate to the human rather than injecting another reset prompt. The escalation message includes:

1. How many attempts were made across the phase
2. A summary of the approaches tried and what was changed
3. The escalation's current error or failing test output
4. An explicit ask for the human's guidance: "Please provide guidance on how to proceed."

When the failure involves an unclear root cause (hard-to-understand bug), include the `/cdebug` option in the escalation: "Consider running `/cdebug` for structured root cause analysis before the next attempt — failed attempts suggest the root cause may not be obvious."

### Attempt Tracking (R-009)

The orchestrator tracks attempt counts for all calm reset triggers in its own conversation context (working memory), not in persisted state. Attempt counts live entirely in orchestrator memory and clear when a new phase begins. No additional files, state fields, or checkpoint entries are needed — the orchestrator simply observes its own conversation history to determine how many attempts have been made.
- **If no BLOCKING findings**:
  - **At standard intensity**: `workflow-advance.sh audit-mini` (mini-audit runs at all intensities)
  - **At high+ intensity**: `workflow-advance.sh audit-mini` (mini-audit subsumes verify-phase at high+ intensity)

## Phase: Mini-Audit (tdd-audit)

After QA completes with no BLOCKING findings, advance to `tdd-audit` via `workflow-advance.sh audit-mini` and spawn the mini-audit agents. The mini-audit asks "how does this feature break everything else?" — using four adversarial lenses that are structurally absent from the QA agent's perspective. No convergence loop — fixed rounds per intensity level (standard=1, high=2, critical=3).

### Agent Prompts

Each mini-audit round spawns four specialist agents as forked subagents, running in parallel:

1. **Cross-component interaction agent**: "You are testing how this feature interacts with the rest of the system. Read the entrypoints in `.correctless/ARCHITECTURE.md` (look for `correctless:entrypoints:start` / `correctless:entrypoints:end` markers) and the trust boundaries. For each entrypoint whose scope overlaps with the changed files, ask: does this feature change behavior that other components depend on? Does this feature assume invariants that other components could violate? Does this feature introduce state that other components are unaware of? If no entrypoints exist, fall back to `git diff`-scoped analysis: what other files import symbols from the changed files? What callers depend on the changed interfaces?"

2. **Hostile input agent**: "You are an attacker. The feature implementation is in front of you. Read the trust boundaries (TB-xxx) in `.correctless/ARCHITECTURE.md` to identify which inputs cross trust boundaries. For each input this feature accepts (function arguments, config values, file contents, environment variables, network data), find an input that causes incorrect behavior — not just a crash, but a wrong result, a security bypass, or silent data corruption. Constructed test scenarios with clean inputs don't count — find the ugly inputs."

3. **Resource bounds agent**: "You are a reliability engineer. Read the environment assumptions (ENV-xxx) in `.correctless/ARCHITECTURE.md` for resource constraints. For each resource this feature allocates, manages, or depends on (memory, file handles, goroutines, connections, disk space, CPU time), find a scenario where the resource is exhausted, leaked, or contended. What happens at 10x the expected load? What happens when the resource is unavailable? What happens on graceful shutdown during an operation?"

4. **Upgrade compatibility agent**: "An existing user has this project's tooling installed from a prior version. They update to the version with these changes. Your job is to mechanically check the implementation (git diff against base branch) against the 5-item checklist below — do not hallucinate what the project looked like before; work from what the diff adds, changes, or removes. (1) Does the install/setup mechanism install all new files? Verify glob patterns, not hardcoded lists (AP-024/PMB-003). (2) Do new config keys have fallback defaults in the code that reads them? (3) Do new artifact schemas include version markers or graceful parsing for old formats? (4) Do removed or renamed files have migration paths? (5) Do new features that depend on artifacts from other new features degrade gracefully when those artifacts don't exist yet? For each issue, report it as a finding with the MA- prefix and LENS: upgrade-compatibility."

### Agent Context and Tools

Each agent receives as context: the spec, `.correctless/ARCHITECTURE.md` (including entrypoints YAML), `.correctless/AGENT_CONTEXT.md`, `.correctless/antipatterns.md`, the source code changed by this feature (from `git diff` against the base branch), and the test files. Agents have read-only tools: `Read, Grep, Glob, Bash(git diff*, git log*, git show*)`. Agents must not use Edit or file-writing tools.

### Finding Format

Each agent returns findings using the `MA-` prefix (not `QA-`) to distinguish mini-audit findings from QA findings:

```
FINDING: MA-001
SEVERITY: CRITICAL|HIGH|MEDIUM|LOW|UNCERTAIN
LENS: cross-component|hostile-input|resource-bounds|upgrade-compatibility
RULE: R-xxx or null
DESCRIPTION: [what's wrong]
INSTANCE_FIX: [fix this specific bug]
CLASS_FIX: [prevent this category]
```

The orchestrator persists findings to `.correctless/artifacts/qa-findings-{task-slug}.json` by appending to the existing findings array. The `LENS` field and the `MA-` prefix distinguish mini-audit findings from QA findings.

### UNCERTAIN Severity

When a mini-audit agent cannot determine whether a finding is real, it must label the finding as `UNCERTAIN` severity rather than inflating to HIGH or suppressing entirely. `UNCERTAIN` findings are presented to the user as advisory with a note explaining why the agent is unsure. This is non-blocking. If >50% of findings in a round are UNCERTAIN, the round is flagged as low-confidence and the user is warned.

### Disposition Options

CRITICAL and HIGH findings from the mini-audit are blocking — they must be fixed before `done`. Present each CRITICAL/HIGH finding to the user with disposition options:

```
  1. Fix now (recommended) — address before proceeding
  2. Accept risk — document why this is tolerable
  3. Dispute — explain why this is not an issue

  Or type your own: ___
```

MEDIUM and LOW findings are advisory — presented to the user but do not block `done`.

### Fix Loop

When CRITICAL/HIGH findings are accepted for fixing, transition back to `tdd-impl` via `workflow-advance.sh fix`, spawn a fix agent that writes both the fix AND a regression test for the fix, then transition directly to `tdd-audit` via `workflow-advance.sh audit-mini` (which accepts `tdd-impl` as a source phase) and re-run only the mini-audit round that produced the finding. A fix without a regression test is incomplete.

### Multi-Round Behavior

At high+ intensity with multiple rounds, round 2+ agents do NOT see previous rounds' findings — they start fresh, preventing anchoring to previous findings. Deduplication happens at the orchestrator level after collection, using file + issue category (not function-level). When two findings describe the same category of issue in the same file, the orchestrator keeps the higher-severity finding and adds a `duplicate_of` field to the lower-severity one.

Each round after the first receives a "raise the bar" prompt:
> "The previous round's agents were sloppy and missed things. The agents were overconfident and under-thorough. Do better."

### Progress Announcements

Before each round, announce: "Starting mini-audit round {N}/{total} — spawning 4 specialist agents (cross-component, hostile input, resource bounds, upgrade compatibility)."

As each agent completes, announce immediately: "{Agent name} complete — found {N} findings ({C} critical/high, {M} medium/low). {M} agents still running..."

After all agents complete: "Round {N} complete — {N} total findings ({C} blocking, {A} advisory)."

### Agent Failure Handling

If a mini-audit agent fails (context limit, tool error, malformed output, timeout), the round completes with the remaining agents' findings. The orchestrator logs the failure and warns the user which lens was missed: "Warning: {agent name} agent failed ({reason}). Round {N} results are from {remaining lenses} only. The {missing lens} perspective was not evaluated." No automatic retry — retries are expensive and the other three lenses are still valuable.

### Zero Findings / Clean Round

When all four agents in a round return zero findings AND all four agents completed successfully, the orchestrator announces "Mini-audit round {N} clean — no findings across all four lenses." If any agent failed, the round is announced as "incomplete" rather than "clean" — zero findings from failed agents is not the same as zero findings from successful agents.

At multi-round intensity (high/critical), subsequent rounds still run even if earlier rounds were clean — the fresh-context, no-anchoring design means a later round may find what an earlier one missed.

After the final round completes clean, the orchestrator announces "Mini-audit complete — no blocking findings. Ready to advance to done." and waits for the user. It does not auto-transition to `done` — consistent with the shared constraint "never auto-invoke the next skill."

### No Convergence

The mini-audit does NOT use a convergence loop. Each intensity level has a fixed number of rounds (1/2/3). After the final round, all remaining CRITICAL/HIGH findings must be fixed or explicitly accepted as risk. This is a fixed-cost addition to the TDD cycle — `/caudit` handles convergence.

### Token Tracking

Token tracking for the mini-audit follows the shared constraints. Skill-specific values: `skill: "ctdd"`, `phase: "mini-audit-round-N"`, `agent_role: "cross-component|hostile-input|resource-bounds|upgrade-compatibility"`. The `tdd-audit` → `ctdd` mapping is in `hooks/token-tracking.sh`.

## After TDD Completes: Next Steps

After `workflow-advance.sh done`, tell the human the mandatory remaining steps:

"TDD complete. The workflow requires two more steps before merge:
1. `/cverify` — verifies implementation matches spec, checks rule coverage and architecture compliance
2. `/cdocs` — updates documentation

Run `/cverify` when ready."

**Do NOT auto-invoke /cverify or /cdocs.** Tell the human what comes next and let them decide when to run it. Do NOT say "ready to merge" until the human confirms both have completed — the state machine enforces this (it won't advance to `documented` without both steps).

## Spec Updates

If during any phase you discover a spec rule is wrong or impossible to implement:
```bash
.correctless/hooks/workflow-advance.sh spec-update "reason"
```
Edit the spec, then `workflow-advance.sh tests` to resume from RED.

## Claude Code Feature Integration

### Task Lists
See "Progress Visibility" section above — task creation and narration are mandatory.

### Background Tasks
- Run mutation testing as a background task during QA — continue with rule coverage, antipattern checks, and test-edit log review while mutations run
- Run race detector (`-race` flag) in the background while preparing for QA transition
- Run coverage report generation in the background while composing the QA summary

### Token Tracking

Log token usage following the shared constraints (`_shared/constraints.md`). Skill-specific values:
- `skill`: "ctdd"
- `phase`: "{red|test-audit|green|qa|fix-round-N|mini-audit-round-N}"
- `agent_role`: "{test-writer|test-auditor|implementation|qa-agent|fix-agent|cross-component|hostile-input|resource-bounds|upgrade-compatibility}"

### /btw Reminder
When presenting QA findings for the human to review, mention: "If you need to check something about the codebase without interrupting this review, use /btw."

### /export
After workflow completes (done phase), suggest: "Consider exporting this conversation as a decision record: `/export .correctless/decisions/{task-slug}-tdd.md`"

## Code Analysis (MCP Integration)

If `mcp.serena` is `true` in `workflow-config.json`, use Serena MCP for symbol-level code analysis during test writing and implementation:

- Use `find_symbol` instead of grepping for function/type names
- Use `find_referencing_symbols` to trace callers and dependencies
- Use `get_symbols_overview` for structural overview of a module
- Use `replace_symbol_body` for precise symbol-level edits during implementation
- Use `search_for_pattern` for regex searches with symbol context

**Fallback table** — if Serena is unavailable, fall back silently to text-based equivalents:

| Serena Operation | Fallback |
|-----------------|----------|
| `find_symbol` | Grep for function/type name |
| `find_referencing_symbols` | Grep for symbol name across source files |
| `get_symbols_overview` | Read directory + read index files |
| `replace_symbol_body` | Edit tool |
| `search_for_pattern` | Grep tool |

### Context7 — Library Documentation

If `mcp.context7` is `true` in `workflow-config.json`, the test agent (RED phase) can use Context7 to understand a library's test utilities and assertion patterns:

- Use `resolve-library-id` + `get-library-docs` to fetch testing docs for the libraries under test
- Useful when the test agent needs to know how a library's test helpers work (e.g., testing hooks in React, test fixtures in pytest)

## If Something Goes Wrong

- **Agent crashes or context overflow**: The state machine remembers your phase. Re-run this skill — it will resume from the current phase.
- **Rate limit hit**: Wait 2-3 minutes and re-run. The workflow state persists between sessions.
- **Stuck in a phase**: Run `/cstatus` to see where you are and what to do next. If truly stuck: `workflow-advance.sh override "reason"` bypasses the gate for 10 tool calls.
- **Want to start over**: `workflow-advance.sh reset` clears all state on this branch. Also delete the checkpoint file: `rm -f .correctless/artifacts/checkpoint-ctdd-*.json`

## Constraints

- **You are the orchestrator, not a coder.** Spawn subagents for each phase.
- **Never let the same agent handle two phases.** RED, GREEN, and QA are separate agents.
- **Test edits during GREEN are logged, not blocked.** But weakening assertions is a QA finding.
- **The hook enforces phase gating.** Even if you forget, the gate blocks violations.
- **If `workflow-advance.sh` fails**, read the error message and present it to the human. Common causes: wrong phase, missing precondition, not on a feature branch.
- **All files created by any agent must be inside the project directory.** Never write to /tmp or external paths.
- **Never skip workflow steps.** The full pipeline is: RED → test audit → GREEN → /simplify → QA → mini-audit → done → /cverify → /cdocs → merge. Every step runs, every time. No exceptions. "This feature is small" is not a reason to skip. Time is not the constraint — correctness is.
