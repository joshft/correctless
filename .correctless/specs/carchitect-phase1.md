# Spec: /carchitect Phase 1 — Entrypoint-Aware TDD

## Metadata
- **Task**: carchitect-phase1
- **Recommended-intensity**: high
- **Intensity**: high
- **Intensity reason**: file path signal (skills/); project floor is high
- **Override**: none

## What

The RED phase test-writing agent in `/ctdd` receives ARCHITECTURE.md entrypoints and key patterns (middleware chains, layer conventions, trust boundaries) as explicit context when writing integration tests. The test audit gains a new check that flags tests importing internal packages directly when a documented entrypoint exists for that path. Together these ensure integration tests are written through documented entrypoints from the start, rather than relying on post-hoc contract verification (PR #70) to catch bypasses.

## Rules

- **R-001** [unit]: The RED phase test agent prompt in `/ctdd` (`skills/ctdd/SKILL.md`, "Phase: RED" section) is updated to explicitly instruct the agent to read and use entrypoints from ARCHITECTURE.md when writing integration tests. The instruction reads: "Before writing integration tests, read the entrypoints section of `.correctless/ARCHITECTURE.md`. For each `[integration]` rule, identify which entrypoint governs the code under test (match the rule's scope to an entrypoint's `scope` globs). Write the integration test through that entrypoint's `test_via` pattern — not by importing internal packages directly. If the rule has an Entry/Through/Exit contract, the Entry field already tells you which entrypoint to use."

- **R-002** [unit]: The RED phase test agent prompt additionally instructs the agent to read key architecture patterns from ARCHITECTURE.md that are relevant to integration tests. The instruction reads: "Also read the Key Patterns, Layer Conventions, and Trust Boundaries sections of ARCHITECTURE.md. When writing integration tests, respect layer conventions — if the architecture says layer A should not be accessed directly by tests (only through an entrypoint), do not import layer A's packages in test files. Use the entrypoint's `test_via` pattern to reach layer A indirectly."

- **R-003** [unit]: The RED phase test agent's "Read" context list is updated to emphasize ARCHITECTURE.md entrypoints. The current list reads: "Read: .correctless/AGENT_CONTEXT.md, the spec, .correctless/ARCHITECTURE.md, .correctless/antipatterns.md." This is updated to: "Read: .correctless/AGENT_CONTEXT.md, the spec, .correctless/ARCHITECTURE.md (especially the Entrypoints section and Key Patterns), .correctless/antipatterns.md."

- **R-004** [unit]: The RED phase test agent prompt includes a graceful fallback when no entrypoints exist: "If ARCHITECTURE.md has no entrypoints section (no `correctless:entrypoints:start` markers), write integration tests using the best available entry point from the codebase — but note in a comment (using the project's comment syntax): `No documented entrypoint — using inferred entry point`. This makes the gap visible for the test audit to flag."

- **R-005** [unit]: The test audit in `/ctdd` (`skills/ctdd/SKILL.md`, "Between RED and GREEN: Test Audit" section) adds a new check (check 10): **Internal import bypass detection**. For each `[integration]` test, the test auditor checks whether the test imports or directly references internal packages/modules that are covered by a documented entrypoint's `scope` globs. If a test imports `pkg/handlers/auth.go` directly, and an entrypoint exists with `scope: ["pkg/handlers/**"]` and `test_via: "httptest.NewServer(handler)"`, then the test is bypassing the entrypoint. This is a BLOCKING finding: "Test for R-xxx imports internal package `pkg/handlers/auth` directly. Entrypoint `api-server` covers this path — use `test_via: httptest.NewServer(handler)` instead." When check 10 and check 9 (Entry contract verification from PR #70) both fire on the same test for the same rule, the test auditor presents one consolidated finding rather than two: "Test for R-xxx bypasses entrypoint `api-server`: imports `pkg/handlers/auth` directly instead of using `httptest.NewServer(handler)`." The checks remain independent (check 9 can fire without check 10 and vice versa), but when they converge on the same test, the user sees one thing to fix.

- **R-006** [unit]: The internal import bypass check (R-005) reads entrypoints from ARCHITECTURE.md (via the fenced YAML block or `scripts/extract-entrypoints.sh`). For each entrypoint, it builds a map of scope globs to entrypoint names. For each `[integration]` test file, it checks whether any import/require/source statement references a path that falls within an entrypoint's scope. The check is language-aware at a basic level: Go `import "pkg/..."`, TypeScript/JavaScript `import ... from '...'` or `require('...')`, Python `from pkg import` or `import pkg`, Rust `use crate::` or `mod`. For languages not in this list, the check is skipped with an ADVISORY note: "Cannot detect internal imports for language {X} — manual review recommended."

- **R-007** [unit]: The internal import bypass check does NOT flag imports of the entrypoint itself (e.g., importing `cmd/server/main.go` when that IS the entrypoint handler). It only flags imports of packages *within* the entrypoint's scope that should be reached *through* the entrypoint, not directly. The test_via pattern indicates how to reach the entrypoint; the scope globs indicate what's behind it.

- **R-008** [unit]: When entrypoints are unavailable (ARCHITECTURE.md missing or no entrypoints markers), the internal import bypass check is skipped entirely. The test audit notes: "No documented entrypoints — internal import bypass check skipped." This is consistent with R-003's fallback in the test agent and R-003 in the integration-test-contracts spec (graceful degradation without entrypoints).

- **R-009** [unit]: Documentation is updated: `docs/skills/ctdd.md` documents the entrypoint-aware test writing and internal import bypass check. `.correctless/AGENT_CONTEXT.md` is updated to reference Phase 1 in the design patterns. CONTRIBUTING.md and README.md test/assertion counts are updated (or the AP-005 drift test catches it).

## Won't Do

- **QA phase entrypoint checking** — the roadmap mentions "QA checks if test actually hits the entrypoint." PR #70's contract verification (check 9 in the test audit) already does this at the test audit stage, which is earlier and cheaper. Adding it again in QA is redundant.
- **Modifying `/cspec`** — PR #70 already handles the spec-side integration (Entry/Through/Exit contracts derived from entrypoints). Phase 1 is the test-writing and test-audit side.
- **Modifying `/carchitect`** — Phase 0 is stable. The entrypoints format is unchanged.
- **Full language-specific import detection** — R-006 covers Go, TypeScript/JavaScript, Python, and Rust. Other languages get an advisory skip. Full coverage is a diminishing-returns effort.

## Risks

- **Internal import detection produces false positives**: A test legitimately imports an internal package for test setup (e.g., creating fixtures) while also testing through the entrypoint. The import is present but not the test's entry path.
  1. Mitigate (recommended) — R-005 makes this a BLOCKING finding presented to the human. False positives are disputable during test audit triage. The finding says "imports internal package" which is factual — the human decides whether the import is for setup vs bypass.

- **RED phase agent ignores the entrypoint context**: The agent reads ARCHITECTURE.md but still writes tests through internal imports because it's easier. The instructions are prompt-level, not structural enforcement.
  1. Accept — this is the fundamental LLM behavioral challenge. The instructions make the right path clear. The test audit (checks 9 and 10) catches violations mechanically. The combination of "tell the agent what to do" (R-001/R-002) and "catch it if it doesn't" (R-005/check 9) is defense in depth.

- **Entrypoint scope globs are too broad for import matching**: If an entrypoint's scope is `**/*.go`, every Go import matches, and every test gets flagged.
  1. Accept — same as the integration-test-contracts spec risk. The fix is better entrypoint scopes in ARCHITECTURE.md (a `/carchitect` quality issue). R-005's findings are presented for human triage, not auto-rejection.

## Open Questions

- **OQ-001**: Should the internal import bypass check also apply to `[unit]` tests? A unit test that imports an internal package is normal — unit tests test units. But if the unit test is for a rule that should be `[integration]` (mistagged), the import pattern is a signal. **Tentative answer**: no, only `[integration]` tests. The test audit's existing check 2 ("Integration required?") already catches mistagged rules.

- **OQ-002**: Should the RED phase agent receive the *extracted* entrypoints YAML (via `extract-entrypoints.sh`) or just read ARCHITECTURE.md directly? The extraction script produces clean YAML; reading the doc directly means the agent parses markdown with fenced YAML. **Tentative answer**: read ARCHITECTURE.md directly. The agent already reads it; adding a script execution adds complexity for marginal benefit. The agent can parse fenced YAML from markdown.
