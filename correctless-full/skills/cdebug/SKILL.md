---
name: cdebug
description: Structured bug investigation workflow. Root cause analysis, hypothesis testing, TDD fix with agent separation, escalation after 3 failed attempts. Use when stuck on a bug.
allowed-tools: Read, Grep, Glob, Bash(*), Write(.claude/antipatterns.md), Write(.claude/artifacts/debug-*), Edit
context: fork
---

# /cdebug — Structured Bug Investigation

You are the debugging agent. Your job is to investigate a bug systematically — trace the root cause, form and test hypotheses, fix with TDD discipline, and escalate if the bug resists fixing.

**Do not guess-and-patch.** Understand the bug before touching code. A fix without root cause understanding is a new bug waiting to happen.

## Progress Visibility (MANDATORY)

Bug investigation takes 5-15 minutes depending on complexity. The user must see progress throughout.

**Before starting**, create a task list:
1. Reproduce the bug
2. Root cause investigation (code path, git blame, tests, antipatterns)
3. (Optional) Automated bisect — if regression with reliable test
4. Hypothesis 1
5. Fix: write failing test
6. Fix: spawn implementation agent
7. Fix: verify all tests pass
8. Class fix assessment

**Between each phase**, print a 1-line status: "Reproduction confirmed — bug triggers on {condition}. Tracing code path..." For hypotheses: "Hypothesis 1: {statement} — {confirmed/denied}." When the implementation subagent completes: "Implementation agent done — running tests..."

Add hypothesis tasks dynamically as needed. Mark each task complete as it finishes.

## Artifact Output

Write the investigation results to `.claude/artifacts/debug-investigation-{slug}.md`:

```markdown
# Debug Investigation: {bug description}
## Reproduction: {steps or test}
## Hypotheses Tested:
1. {hypothesis} — {confirmed/denied} — {evidence}
2. ...
## Root Cause: {confirmed cause}
## Fix: {what was changed}
## Class Fix: {structural test added / antipattern / N/A}
```

This artifact is consumed by `/cpostmortem` (traces whether bugs were investigated) and future `/cdebug` runs (reads previous investigations for the same code area).

## Phase 1: Reproduce

Before investigating, get a concrete reproduction:

1. Ask the human: "What's the bug? What did you expect vs what happened?"
2. Get a reproduction: a failing test, a curl command, a sequence of UI actions, or at minimum a stack trace
3. If no reproduction exists, **that's the first problem to solve.** Write a test that demonstrates the expected behavior — if it passes, the bug report may be wrong. If it fails, you have your reproduction.
4. Run the reproduction and confirm you can trigger the bug

**If you can't reproduce it:** ask about environment differences (OS, versions, data), timing (intermittent?), and whether it happens in tests or only in production. An intermittent bug that only manifests under load suggests a concurrency issue.

## Phase 2: Root Cause Investigation

Trace the code path from trigger to failure. Do not guess.

1. **Read the code path**: starting from the entry point (the API endpoint, the function call, the event handler), trace the execution path to where the bug manifests. Read every function in the chain.
2. **Check git blame**: when did the behavior change? Was it an intentional change or a side effect? Who changed it and what was the commit message?

### Automated Bisect (optional)

If the bug has a reliable failing test from Phase 1, offer:

> "I have a failing test that reproduces this bug. I can run `git bisect` to find the exact commit that introduced it — takes 1-3 minutes. Want me to?"

**Only offer if:** the test is fast (<30 seconds), the bug is a regression (not a new feature), and the user agrees.

**If yes:**
1. Find the known-good commit: `git merge-base HEAD main`. If debugging on main (merge-base equals HEAD), ask the user: "You're on main — when did this last work? Provide a commit hash or tag." If no good commit can be identified, skip bisect.
2. Write the bisect test script to `.claude/artifacts/debug-bisect-test.sh`.
3. Run the entire bisect as a **single bash call** (variables must survive across steps):
   ```bash
   # Stash if dirty
   STASHED=false
   if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
     git stash && STASHED=true
   fi
   # Run bisect
   git bisect start HEAD {good-commit} && git bisect run bash .claude/artifacts/debug-bisect-test.sh
   RESULT=$?
   # Clean up (all steps run regardless)
   git bisect reset
   [ "$STASHED" = "true" ] && git stash pop
   rm -f .claude/artifacts/debug-bisect-test.sh
   exit $RESULT
   ```
4. Capture the first bad commit from the output. If bisect is inconclusive (exit non-zero, all bad/good/skipped), report: "Bisect could not isolate the commit — proceeding with manual investigation."
5. If successful, report: "Bisect found commit `{sha}`: `{message}`. Changed: {files}."

Feed the bisect result into Phase 3 — the identified commit narrows the hypothesis dramatically.

3. **Read the tests**: what IS tested for this code path? What's NOT tested? The gap between "tested" and "failing" is often where the bug lives.
4. **Check antipatterns** (`.claude/antipatterns.md`): is this a known bug class? If AP-003 is "config wiring missing" and this looks like a config wiring issue, you may already know the pattern.
5. **Check QA findings** (`.claude/artifacts/qa-findings-*.json`): has this code area had issues before? What were they? Is this a recurrence?
6. **Check drift debt** (`.claude/meta/drift-debt.json`): is this code area architecturally eroded? A bug in drifted code may be a symptom of the drift, not an independent issue.

## Phase 3: Hypothesis

State a specific hypothesis:

> "The bug is caused by [X] because [Y]. I can verify this by [Z]."

Example: "The bug is caused by the webhook handler not validating the Stripe signature because the validation middleware is registered after the route handler. I can verify this by checking middleware ordering in the route file and adding a test that sends a webhook with an invalid signature."

Design a test that confirms or denies the hypothesis. This test is separate from the fix — it validates your understanding of the cause.

## Phase 3.5: Fix Design (if non-trivial)

If the root cause is understood but the fix is non-trivial (spans multiple components, requires architectural changes, or has multiple valid approaches):

1. Document the fix approach: what will change, which files, which tests
2. If the fix requires architectural changes, present to the human before proceeding
3. If multiple approaches exist, present the tradeoffs and let the human choose

For simple fixes (one-liner guard, missing check, wrong value), skip this step and go directly to Phase 4.

## Phase 4: Fix (TDD)

Fix the bug using TDD discipline with agent separation:

1. **Write a failing test** that reproduces the bug. This test should pass when the bug is fixed and fail when it isn't. Reference the bug description in the test comment.
2. **Spawn a separate implementation agent** (forked context) to write the fix. The fix agent sees the failing test and the root cause analysis but did NOT write the test.
3. **Verify**: the reproduction test passes, all existing tests still pass, race detector passes (if applicable).

This maintains the same agent separation principle as `/ctdd` — the agent that understands the bug writes the test, a different agent writes the fix.

## Phase 5: Class Fix Assessment

Ask: does this bug represent a class?

- **If yes** (the same pattern could occur elsewhere): add a structural test that catches all instances, and add an antipattern entry to `.claude/antipatterns.md`. The structural test should fail if anyone introduces the same bug in a new location.
- **If no** (genuinely one-off — typo, unique edge case): the instance fix is sufficient. Set `class_fix: "N/A — one-off [reason]"`.

## Phase 6: Escalation (After 3 Failed Hypotheses)

If 3 hypotheses have been tested and none explain the bug:

1. **Stop fixing.** Three wrong hypotheses means you don't understand the problem.
2. **Summarize**: what you've tried, what you've ruled out, what you still don't understand.
3. **Escalate**: spawn a fresh agent (forked context) with a `/cdevadv`-style analysis scoped to this code area. The bug may be a symptom of a deeper design problem that incremental hypothesis testing won't find.

The escalation agent receives:
> You are investigating a bug that has resisted 3 fix attempts. The previous agent's hypotheses were all wrong. Read the code area, the failed hypotheses, and determine: is this a code bug or a design bug? If the architecture of this code area is fundamentally wrong, no amount of patching will fix it.

Present the escalation analysis to the human. The fix may require a spec revision or architectural change, not just a code patch.

## When to Use

- **Outside an active workflow**: for bugs found in production, reported by users, or discovered ad-hoc. Run on a `fix/{slug}` branch.
- **During QA phase**: if QA finds a complex bug that needs investigation beyond a simple fix round. The QA agent flags it, the human invokes `/cdebug`.
- **After a failed fix round**: if a `/ctdd` fix round doesn't resolve the issue, `/cdebug` provides structured investigation.

`/cdebug` does NOT interact with the workflow state machine. Its fixes should go through `/ctdd` (create a fix branch, write test, implement) or be committed directly on a fix branch with manual verification.

## Before You Start

1. Read `AGENT_CONTEXT.md` for project context.
2. Read `ARCHITECTURE.md` for design patterns in this area.
3. Read `.claude/antipatterns.md` for known bug classes.
4. Read `.claude/artifacts/qa-findings-*.json` for previous issues in this code area.
5. Read `.claude/meta/drift-debt.json` for architectural erosion in this area.

## Claude Code Feature Integration

### Task Lists
See "Progress Visibility" section above — task creation and narration are mandatory.

### Background Tasks
Run the test suite in the background while investigating the code path. Run git blame in the background while reading the code.

### /btw
When presenting the root cause analysis: "Use /btw if you need to check something about the codebase without interrupting this investigation."

## If Something Goes Wrong

- **Skill interrupted**: Re-run the skill. It reads the current state and resumes where possible.
- **Rate limit hit**: Wait 2-3 minutes and re-run. Workflow state persists between sessions.
- **Wrong output**: This skill doesn't modify workflow state until the final advance step. Re-run from scratch safely.
- **Stuck in a phase**: Run `/cstatus` to see where you are. Use `workflow-advance.sh override "reason"` if the gate is blocking legitimate work.

## Constraints

- **Do not guess-and-patch.** Understand before fixing. A fix without root cause understanding is a future bug.
- **Do not modify code during Phases 1-3.** Investigation is read-only. Only Phase 4 writes code.
- **Maintain agent separation.** The investigator writes the test. A separate agent writes the fix.
- **Escalate honestly.** Three failed hypotheses is not a failure — it's information. The bug is harder than expected. Escalation is the right move.
- **Every fix goes through TDD.** No "just change this one line" patches. Write the failing test first.
- **All files inside the project directory.** Never /tmp.
