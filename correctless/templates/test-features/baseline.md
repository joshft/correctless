# Spec: Baseline Reference Feature (for /cmodelupgrade --capture-baseline)

## Metadata

- **Created**: scaffolded by /csetup
- **Status**: template
- **Recommended-intensity**: standard
- **Intensity**: standard

## Context

This is a small reference feature intended to be run end-to-end through `/cauto` so `/cmodelupgrade --capture-baseline` can record per-feature metrics (qa_rounds, total_tokens, total_cost_usd, phase_count) at the current `{model}+{HARNESS_VERSION}` combination. The baseline becomes the comparison reference for future regression reports.

The feature is deliberately small (so a baseline run completes in <20 minutes), but exercises every required pipeline phase.

## Scope

**In scope:**
- Add a new module-level constant `GREETING_VERSION` initialized to `1` in a small source file (e.g., `src/greeting.ts` for TS projects, `greeting.py` for Python, `greeting.go` for Go).
- Add a function `format_greeting(name: string) -> string` that returns `"Hello, {name}! (v{GREETING_VERSION})"`.
- Add a unit test that asserts the function returns the expected string for at least three inputs (empty string, normal name, name with unicode).
- Add an integration test that invokes the function through the project's standard entry point (e.g., a CLI subcommand if the project has one, or via the project's HTTP handler).

**Out of scope:**
- Internationalization
- Persistence
- Authentication

## Invariants

### INV-001: format_greeting returns the expected literal string
- **Type**: must
- **Category**: functional
- **Statement**: `format_greeting("name")` returns `"Hello, name! (v1)"` exactly. Whitespace, punctuation, and version literal are part of the contract.
- **Test approach**: unit
- **Risk**: low

### INV-002: GREETING_VERSION is a module-level integer constant
- **Type**: must
- **Category**: data-integrity
- **Statement**: `GREETING_VERSION` is exported from the module as an integer (not a string, not a function). Used by `format_greeting` to construct the version suffix.
- **Test approach**: unit — assert type and value
- **Risk**: low

### INV-003: format_greeting reachable through standard entry point [integration]
- **Type**: must
- **Category**: functional
- **Statement**: The function is callable via the project's standard entry point (CLI subcommand, HTTP handler, or library import per the project's `test_via` convention).
- **Test approach**: integration
- **Risk**: low

## Prohibitions

### PRH-001: Must not allocate per-call
- **Statement**: `format_greeting` must not allocate a heap-backed structure on each call beyond the returned string. No global mutable state.
- **Detection**: code review during /cverify

## Boundary Conditions

### BND-001: Empty name input
- **Validation required**: `format_greeting("")` returns `"Hello, ! (v1)"` — empty interpolation is allowed
- **Failure mode**: never throws

## Environment Assumptions

### EA-001: The project has a standard test runner configured
- **Assumption**: `commands.test` in `.correctless/config/workflow-config.json` is non-empty and the test runner is installed.

## Notes for the Maintainer

This template intentionally produces a tiny diff. Its purpose is calibration — running it through `/cauto` should take ~10-15 minutes and produce one or two QA rounds at standard intensity. The resulting per-feature metrics serve as the baseline for `/cmodelupgrade` regression comparison.

If your project's structure makes the example function hard to add (e.g., you don't have a `src/` directory, or your language doesn't use the suggested file extensions), adapt the file paths but keep the spec's invariant structure intact.
