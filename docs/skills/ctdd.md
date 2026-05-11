---
title: "/ctdd"
parent: "Core Workflow"
grand_parent: Skills
nav_order: 4
---

# /ctdd — Enforced Test-Driven Development

> Orchestrate the full RED-GREEN-QA pipeline with agent separation — different agents write tests, implement code, and review quality.

## When to Use

- After `/creview` approves a spec — this is where code gets written
- When you want tests written before implementation, enforced by the workflow
- **Not for:** bug fixes (use `/cdebug`), refactoring (use `/crefactor`), or features that don't have an approved spec yet

## How It Fits in the Workflow

`/ctdd` is the implementation phase. The full pipeline is: /cspec → /creview → **/ctdd** → /cverify → /cdocs → merge. Inside `/ctdd`, the pipeline is: RED (write failing tests) → test audit → GREEN (implement) → /simplify → QA → mini-audit → done. Every step runs, every time.

## What It Does

1. **RED phase** — spawns a test agent that reads the spec rules and writes failing tests. Each test references a rule ID (`// Tests R-001 [unit]: ...`). The test agent creates structural stubs (marked `STUB:TDD`) but writes zero implementation logic.
2. **Test audit** — a separate agent (not the test writer) reviews test quality before implementation begins. Checks for mock gaps, missing integration tests, and weak assertions. Blocking findings must be fixed before GREEN.
3. **GREEN phase** — spawns an implementation agent that sees the failing tests and spec but did not write the tests. Implements just enough to make tests pass. Any test edits are logged with reasons.
4. **QA phase** — a third independent agent reviews the implementation against the spec. For each rule: is there a test? Does the implementation actually satisfy the rule, or just the test cases? Every blocking finding requires both an instance fix and a class fix (structural prevention).
5. **Fix rounds** — if QA finds blocking issues, the workflow returns to GREEN for a fix round, then re-runs QA. Repeats until clean.
6. **Mini-audit phase** — after QA is clean, spawns six adversarial specialist agents (cross-component interaction, hostile input, resource bounds, upgrade compatibility, UX review, integration depth) to catch issues that the QA agent's rule-satisfaction lens misses. Fixed rounds per intensity level (standard=1, high=2, critical=3). CRITICAL/HIGH findings are blocking; MEDIUM/LOW are advisory. Uses `MA-` prefix for findings to distinguish from QA findings.

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

       Starting mini-audit round 1/2 — spawning 6 specialist agents
       (cross-component, hostile input, resource bounds, upgrade compatibility,
       UX review, integration depth)...
       Cross-component complete — found 0 findings.
       Hostile input complete — found 0 findings.
       Resource bounds complete — found 0 findings.
       Upgrade compatibility complete — found 0 findings.
       UX review complete — found 0 findings.
       Integration depth complete — found 0 findings.
       Mini-audit round 1 clean — no findings across all six lenses.
       Mini-audit round 2 clean — no findings across all six lenses.
       Mini-audit complete — no blocking findings.

       TDD complete. Run /cverify when ready.
```

## What It Reads / Writes

| Reads | Writes |
|-------|--------|
| Approved spec (`.correctless/specs/{slug}.md`) | Test files (project test directory) |
| `AGENT_CONTEXT.md`, `ARCHITECTURE.md` | Source files (implementation) |
| `.correctless/config/workflow-config.json` | `.correctless/artifacts/qa-findings-{slug}.json` |
| `.correctless/antipatterns.md` | `.correctless/artifacts/tdd-test-edits.log` |
| | `.correctless/artifacts/checkpoint-ctdd-{slug}.json` |
| | `.correctless/artifacts/token-log-{slug}.json` |

## Entrypoint-Aware Test Writing

The RED phase test agent reads ARCHITECTURE.md entrypoints before writing integration tests. For each `[integration]` rule, the agent matches the rule's scope to an entrypoint's `scope` globs and writes the test through the entrypoint's `test_via` pattern instead of importing internal packages directly. The agent also reads Key Patterns, Layer Conventions, and Trust Boundaries to respect layer access constraints. When no entrypoints are documented, the agent uses the best available entry point and leaves a `No documented entrypoint` comment for visibility.

## Contract Verification in Test Audit

When specs include Entry/Through/Exit integration test contracts (written by `/cspec`, see ABS-024), the test audit verifies that tests satisfy these contracts using tiered severity:

| Check | Type | Severity |
|-------|------|----------|
| Entry | Mechanical | BLOCKING — test must use the specified entrypoint |
| Through | Semi-mechanical | BLOCKING or UNCERTAIN — test must not mock prohibited components |
| Exit | Semantic | BLOCKING (definite mismatch) or ADVISORY (uncertain) |

For `[integration]` rules without contracts, the audit notes the gap without gating.

## Internal Import Bypass Detection (Check 10)

The test audit detects when an `[integration]` test imports internal packages directly instead of going through a documented entrypoint. For each entrypoint's `scope` globs, the audit checks whether test imports reference paths covered by that scope. This is language-aware (Go, TypeScript/JavaScript, Python, Rust) with ADVISORY skip for unsupported languages. The check does not flag imports of the entrypoint itself — only packages *within* its scope. When check 10 and check 9 (contract verification) both fire on the same test, they are consolidated into a single finding. When no entrypoints are documented, the check is skipped entirely.

## Intensity Levels

Same at all intensity levels for the RED → test audit → GREEN → QA pipeline with agent separation. At high/critical intensity, git commit trailers (`Spec:`, `Rules-covered:`, `Phase:`) are added for traceability, and the workflow transitions to a verify phase before marking done.

## Common Issues

- **Tests won't compile without stubs (`STUB:TDD`)**: This is expected. The test agent creates structural stubs with `STUB:TDD` markers and zero-value returns. The GREEN agent replaces these with real implementations. If compilation fails before GREEN, verify the stubs have correct signatures.
- **Context overflow on large features**: The orchestrator warns at 70% context usage. If you hit overflow, run `/compact` before the next phase. The checkpoint system saves progress, so you can resume after compacting.
- **Test command not found**: The skill verifies the test runner works before starting. If it fails, check that `.correctless/config/workflow-config.json` has the correct `commands.test` entry and that your test runner is installed.
