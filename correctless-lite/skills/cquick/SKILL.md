---
name: cquick
description: Quick fix with TDD — no spec/review for small changes. Branch, test, implement, commit.
allowed-tools: Read, Grep, Glob, Edit, Write, Bash(*)
---

# /cquick — Quick Fix with TDD

You are the quick-fix agent. Your job is to implement a small, focused change using TDD without the full Correctless ceremony. No spec, no review, no verify, no docs — just branch, write test, implement, verify tests pass, and commit.

## Before You Start

### Branch Guard

Check the current branch:
```bash
git branch --show-current
```

If on `main` or `master`, stop immediately and tell the user: "You're on the main branch. Create a feature branch first: `git checkout -b fix/short-description`." Do not auto-create branches — the human decides the branch name.

### Active Workflow Guard

Check if a workflow is already active on this branch:
```bash
.correctless/hooks/workflow-advance.sh status 2>/dev/null
```

If a workflow is active, stop and tell the user: "There's an active Correctless workflow on this branch. Use the workflow skills (`/ctdd`, `/cverify`, etc.) instead of `/cquick`. This skill is for standalone small fixes outside of an active workflow."

## Scope Guard

Before writing any code, assess the change:
- If the change will exceed 50 LOC (lines of code) or touch more than 3 files, stop and say: "This is bigger than a quick fix — run `/cspec` to start the full workflow."
- Re-evaluate during implementation. If you realize mid-way that the change is growing beyond 50 LOC or 3 files, stop and escalate to `/cspec`.

## TDD Workflow

Follow strict TDD — write at least one test before implementing the change.

### 1. Write Test First

Write at least one test that describes the expected behavior of the fix. The test must fail before implementation (RED phase). Run the test command and display the failure output. Do NOT proceed to implementation until the failing test output is shown to the user. This is the RED phase — the user must see the test fail before any implementation begins.

```bash
# Run the relevant test suite and show the failure output
```

### 2. Implement

Write the minimal code to make the test pass (GREEN phase). Do not write more code than necessary.

### 3. Verify

Run the full relevant test suite to confirm:
- The new test passes
- No existing tests broke

```bash
# Run tests and verify all pass
```

### 4. Measure Scope

Before committing, verify the change stayed within quick-fix limits:
```bash
git diff --stat
```

Count the actual LOC changed and files touched from the diff output. If the change exceeds 50 LOC or 3 files, stop and tell the user: "This grew beyond a quick fix ({N} LOC, {N} files). Consider running `/cspec` to formalize." Do not commit until the user acknowledges.

### 5. Commit

Stage and commit the change with a clear message explaining what was fixed and why:
```bash
git add <changed files>
git commit -m "Fix: <description>"
```

## Constraints

- **TDD is mandatory.** You must write test before implementing — no exceptions. This is TDD without the ceremony, not no-TDD.
- **No spec, no review, no verify, no docs.** This is for small, obvious fixes.
- **Scope limit:** 50 LOC, 3 files max. If the change grows beyond this, stop and tell the user to run `/cspec`.
- **No workflow state.** This skill does not use `workflow-advance.sh` or create workflow state files.
- **Never auto-invoke other skills.** If the change needs escalation, tell the user and stop.

## Decision Points

When presenting choices to the user:

1. Present numbered options with the recommended option first
2. Mark the recommended option with "(recommended)"
3. Include 2-4 options maximum
4. Always end with: "Or type your own: ___"
5. Accept the number, the option name, or a typed response

## If Something Goes Wrong

- Tests fail after implementation: debug and fix. If you can't fix within 3 attempts, suggest `/cdebug`.
- Scope creep: stop and escalate to `/cspec`. Don't try to force a large change through `/cquick`.
- On wrong branch: tell the user to create a feature branch.
