# /cverify — Post-Implementation Verification

> Verify that the implementation actually matches the spec — not just that tests pass, but that the right things were tested.

## When to Use

- After `/ctdd` completes and the workflow reaches the `done` phase
- Before merging — this is a mandatory step in the pipeline
- **Not for:** reviewing specs (use `/creview`), reviewing pull requests (use `/cpr-review`), or running during active TDD

## How It Fits in the Workflow

`/cverify` sits between TDD completion and documentation. The pipeline is: /cspec → /creview → /ctdd → **/cverify** → /cdocs → merge. Tests passing is necessary but not sufficient — `/cverify` checks whether the tests actually probe the spec rules, whether new dependencies are justified, and whether the implementation follows the project's architecture.

## What It Does

1. **Rule coverage matrix** — for each R-xxx/INV-xxx in the spec, checks whether a test references that rule, whether the test actually probes the rule (not a trivial assertion), and whether integration-tagged rules have real integration tests. Uncovered rules are blocking.
2. **Mutation testing** (runs in background) — kills mutants in the implementation to verify test strength. Surviving mutants reveal tests that would pass even with bugs.
3. **Dependency check** — diffs package manifests against the base branch. Flags new dependencies with which file introduced them and whether they were in the spec.
4. **Architecture compliance** — checks that implementation follows patterns in ARCHITECTURE.md (error handling, validation, naming). Flags new patterns for documentation.
5. **Drift detection** — compares spec rules against actual implementation. Identifies code paths not covered by any spec rule and rules whose `implemented_in` targets no longer exist. Writes drift debt entries.
6. **QA class fix verification** — reads QA findings from TDD and verifies that structural tests were actually added, not just instance fixes.
7. **Writes a verification report** to `docs/verification/{slug}-verification.md` — downstream skills depend on this file.

## Example

```
Agent: Rule coverage complete — 5/5 rules covered, 1 weak.
       Starting mutation testing in background...

       Rule Coverage:
       | Rule    | Test                    | Status  |
       |---------|-------------------------|---------|
       | R-001   | TestLoginLockout        | covered |
       | R-002   | TestLockoutReset        | covered |
       | R-003   | TestConfigurable        | weak    |
       | R-004   | TestPersistAcrossRestart| covered |
       | R-005   | TestNoEmailLeak         | covered |

       R-003 is weak — the test checks that the env var is read but
       doesn't verify the actual lockout duration changes.

       Mutation testing done — 24 mutations, 22 killed, 2 survivors.
       Survivors in: lockout duration boundary check.

       Dependencies: +ioredis@5.4.1 — rate limit storage (not in spec,
       but implied by R-004).

       Architecture: error handling follows middleware pattern. No new
       patterns introduced.

       Overall: PASS with 1 finding (weak test for R-003).
```

## What It Reads / Writes

| Reads | Writes |
|-------|--------|
| Spec (`docs/specs/{slug}.md`) | `docs/verification/{slug}-verification.md` |
| Implementation (changed files on branch) | `.claude/meta/drift-debt.json` (appended if drift found) |
| Test files | `.claude/artifacts/token-log-{slug}.json` |
| `ARCHITECTURE.md` | Workflow state (advances to verified) |
| `.claude/artifacts/qa-findings-{slug}.json` | |
| `.claude/meta/workflow-effectiveness.json` | |
| Package manifests (diff against base branch) | |

## Lite vs Full

Both modes run rule coverage, dependency checks, architecture compliance, and drift detection. Full mode adds mutation testing, cross-spec impact analysis, and checks whether structural changes affect other features' invariants.

## Common Issues

- **Blocking finding for uncovered rule**: Every spec rule must have a corresponding test. If a rule is uncovered, you need to go back to the TDD cycle to add a test before the workflow can advance.
- **Mutation testing takes a long time**: It runs in the background while other checks proceed. For large codebases, consider whether your mutation testing tool supports scope limiting to only the changed files.
