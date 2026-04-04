# /crefactor — Structured Refactoring

> Restructure code with behavioral equivalence enforcement — tests must pass before and after, and any test change requires explicit approval.

## When to Use

- Extracting a domain layer, reducing duplication, migrating a library, or improving testability
- When you need to change structure without changing behavior
- When existing code has low test coverage and you want characterization tests before restructuring
- **Not for:** adding new features (use `/cspec` + `/ctdd`), fixing bugs (use `/cdebug`), or changes that intentionally alter behavior

## How It Fits in the Workflow

`/crefactor` is a standalone workflow — it does not use the TDD state machine. It can run alongside an active feature workflow (on a separate branch) or independently. The test suite IS the spec: if tests pass before and after, the refactor is correct.

## What It Does

1. **Captures refactor intent** — asks what you are refactoring, why, and what should NOT change. Writes an intent document for the audit trail.
2. **Assesses test coverage** — runs coverage on the files being refactored. If coverage is adequate, existing tests become the behavioral contract. If coverage is low or zero, proceeds to characterization tests.
3. **Writes characterization tests** (when needed) — spawns a separate agent that captures the current behavior of the code, including quirks and bugs. These tests assert reality, not intent.
4. **Snapshots the behavioral contract** — records total test count, all passing test names, and test file checksums. This baseline is the standard everything is measured against.
5. **Plans and executes in phases** — breaks the refactor into phases where tests pass after each one. Each phase uses two separate agents: a refactor agent (restructures code, cannot touch tests) and a verification agent (confirms behavioral equivalence, read-only).
6. **Gates all test changes** — if the verification agent detects a test file was modified, the refactor halts. You must approve the change with a stated reason. This is the critical invariant: silent test changes erase the behavioral contract.
7. **QA review** — an independent agent checks for behavioral drift the test suite might not cover (API response shapes, error messages, log formats).

## Example

```
User: /crefactor — extract domain layer from HTTP handlers

Agent: What are you refactoring?

User: The business logic in src/handlers/ is mixed with HTTP concerns.
      I want to extract it into src/domain/.

Agent: Coverage is 62% on handler files. Adequate — using existing
       tests as the behavioral contract.

       Baseline captured — 47 tests all passing.

       Refactor Plan:
       Phase 1: Create domain interfaces in src/domain/
       Phase 2: Move validation logic from handlers to domain
       Phase 3: Move database calls from handlers to domain services
       Phase 4: Reduce handlers to HTTP parsing + domain call + response

       Each phase: restructure → run tests → verify equivalence.

User: Go ahead.

Agent: Phase 1 complete — 47/47 tests passing.
       Phase 2 complete — 47/47 tests passing.
       Phase 3 HALT — test `TestUserHandler_Create` was modified.

       The test was importing `handlers.CreateUser()` directly.
       After the move, the function is at `domain.CreateUser()`.
       This test was testing implementation details (import path),
       not behavior. Is this change intentional?

User: Yes, update the import path.

Agent: Approved. Resuming...
       Phase 3 complete — 47/47 tests passing.
       Phase 4 complete — 47/47 tests passing.

       Refactor complete — 47 tests passing, behavioral equivalence
       verified.
```

## What It Reads / Writes

| Reads | Writes |
|-------|--------|
| Source files being refactored | `.correctless/artifacts/refactor-intent-{slug}.md` |
| Test files (behavioral contract) | `.correctless/artifacts/refactor-baseline-{slug}.json` |
| `ARCHITECTURE.md` | `.correctless/artifacts/refactor-summary-{slug}.md` |
| `.correctless/antipatterns.md` | `.correctless/artifacts/qa-findings-refactor-{slug}.json` |
| `.correctless/config/workflow-config.json` | Characterization test files (if needed) |
| | `ARCHITECTURE.md` (if patterns changed, with approval) |

## Lite vs Full

Both modes run the full behavioral equivalence pipeline with agent separation and test-change gating. Full mode adds mutation testing on refactored code, cross-spec impact analysis (checks whether structural changes affect other features' invariants), and drift debt updates.

## Common Issues

- **Tests fail after a phase**: This is working as designed — the verification agent caught a behavioral change. Fix the issue within that phase or revert it before proceeding. The refactor proceeds phase by phase, never "fix tests later."
- **Active workflow conflict**: If a TDD workflow is active on the same branch, `/crefactor` warns you. Use a separate branch or finish the current feature first.
- **Characterization tests assert bugs**: That is intentional. A characterization test that asserts a bug tells you the refactor changed behavior. If the refactor intentionally fixes a known bug, state that explicitly when approving the test change.
