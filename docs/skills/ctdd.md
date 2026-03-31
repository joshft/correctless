# /ctdd — Enforced Test-Driven Development

> Orchestrate the full RED-GREEN-QA pipeline with agent separation — different agents write tests, implement code, and review quality.

## When to Use

- After `/creview` approves a spec — this is where code gets written
- When you want tests written before implementation, enforced by the workflow
- **Not for:** bug fixes (use `/cdebug`), refactoring (use `/crefactor`), or features that don't have an approved spec yet

## How It Fits in the Workflow

`/ctdd` is the implementation phase. The full pipeline is: /cspec → /creview → **/ctdd** → /cverify → /cdocs → merge. Inside `/ctdd`, the pipeline is: RED (write failing tests) → test audit → GREEN (implement) → /simplify → QA → done. Every step runs, every time.

## What It Does

1. **RED phase** — spawns a test agent that reads the spec rules and writes failing tests. Each test references a rule ID (`// Tests R-001 [unit]: ...`). The test agent creates structural stubs (marked `STUB:TDD`) but writes zero implementation logic.
2. **Test audit** — a separate agent (not the test writer) reviews test quality before implementation begins. Checks for mock gaps, missing integration tests, and weak assertions. Blocking findings must be fixed before GREEN.
3. **GREEN phase** — spawns an implementation agent that sees the failing tests and spec but did not write the tests. Implements just enough to make tests pass. Any test edits are logged with reasons.
4. **QA phase** — a third independent agent reviews the implementation against the spec. For each rule: is there a test? Does the implementation actually satisfy the rule, or just the test cases? Every blocking finding requires both an instance fix and a class fix (structural prevention).
5. **Fix rounds** — if QA finds blocking issues, the workflow returns to GREEN for a fix round, then re-runs QA. Repeats until clean.

For features with 5+ rules, the orchestrator builds a task graph to identify independent tracks that can run RED and GREEN in parallel.

## Example

```
Agent: Spawning test-writing agent — reading spec (5 rules),
       ARCHITECTURE.md, antipatterns...

       RED complete — 2 test files, 8 test cases, all failing as expected.
       Running test audit...

       Test audit passed — 1 advisory (R-004 assertion could be stronger).
       Spawning implementation agent...

       GREEN complete — all 8 tests passing.
       Running /simplify... done.
       Spawning QA agent...

       QA found 1 issue (0 critical, 1 high):
       FINDING: QA-001
       SEVERITY: BLOCKING
       RULE: R-004
       DESCRIPTION: Rate limit counter uses in-memory Map —
                    spec requires persistence across restarts
       INSTANCE_FIX: Move counter to Redis
       CLASS_FIX: Add integration test that restarts the server
                  mid-test and verifies counter survives

       Starting fix round 1...
       Fix round complete — all 9 tests passing. Re-running QA...
       QA clean. No blocking findings.

       TDD complete. Run /cverify when ready.
```

## What It Reads / Writes

| Reads | Writes |
|-------|--------|
| Approved spec (`docs/specs/{slug}.md`) | Test files (project test directory) |
| `AGENT_CONTEXT.md`, `ARCHITECTURE.md` | Source files (implementation) |
| `.claude/workflow-config.json` | `.claude/artifacts/qa-findings-{slug}.json` |
| `.claude/antipatterns.md` | `.claude/artifacts/tdd-test-edits.log` |
| | `.claude/artifacts/checkpoint-ctdd-{slug}.json` |
| | `.claude/artifacts/token-log-{slug}.json` |

## Lite vs Full

Both modes run the full RED → test audit → GREEN → QA pipeline with agent separation. Full mode adds git commit trailers (`Spec:`, `Rules-covered:`, `Phase:`) for traceability, and transitions to a verify phase before marking done.

## Common Issues

- **Tests won't compile without stubs (`STUB:TDD`)**: This is expected. The test agent creates structural stubs with `STUB:TDD` markers and zero-value returns. The GREEN agent replaces these with real implementations. If compilation fails before GREEN, verify the stubs have correct signatures.
- **Context overflow on large features**: The orchestrator warns at 70% context usage. If you hit overflow, run `/compact` before the next phase. The checkpoint system saves progress, so you can resume after compacting.
- **Test command not found**: The skill verifies the test runner works before starting. If it fails, check that `.claude/workflow-config.json` has the correct `commands.test` entry and that your test runner is installed.
