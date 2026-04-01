# /cquick — Quick Fix with TDD

> Small, focused fixes with TDD — no spec, no review, no verify, no docs. Just branch, test, implement, commit.

## When to Use

- For small bug fixes or minor improvements that don't need the full workflow
- When the change is under 50 lines of code and touches 3 files or fewer
- When there's no active Correctless workflow on the branch
- **Not for:** features that need a spec, changes that touch many files, or mid-workflow shortcuts

## How It Fits in the Workflow

`/cquick` is a standalone skill — it operates outside the main pipeline. It's for small fixes that don't justify the full /cspec → /creview → /ctdd → /cverify → /cdocs pipeline. If the change grows beyond the scope guard (50 LOC, 3 files), it tells you to switch to `/cspec`.

## What It Does

1. **Branch guard** — refuses to run on `main` or `master`; tells you to create a feature branch
2. **Active workflow guard** — refuses if a Correctless workflow is already active on the branch
3. **Scope assessment** — checks that the change fits within 50 LOC and 3 files
4. **Write test** — writes at least one failing test before implementing (TDD)
5. **Implement** — writes the minimal code to make the test pass
6. **Verify** — runs the test suite to confirm nothing broke
7. **Commit** — stages and commits with a clear message

## Example

```
Agent: Checking branch... on fix/typo-in-readme. Good.
       No active workflow. Scope looks small — 5 lines, 1 file.

       Writing test for the fix...
       Test written and confirmed failing (RED).

       Implementing fix...
       All tests passing (GREEN).

       Committed: "Fix typo in configuration example"
```

## Lite vs Full

`/cquick` works the same in both modes. It deliberately skips all ceremony — that's the point.

## Common Issues

- **"This is bigger than a quick fix"**: The scope guard triggered. Your change exceeds 50 LOC or 3 files. Run `/cspec` instead.
- **"You're on the main branch"**: Create a feature branch first with `git checkout -b fix/description`.
- **"Active workflow on this branch"**: Use the workflow skills instead of `/cquick`.
