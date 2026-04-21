# Spec: Test Harness Extraction

## Metadata
- **Task**: test-harness-extraction
- **Recommended-intensity**: standard
- **Intensity**: high
- **Intensity reason**: no signals triggered; project floor (workflow.intensity=high) enforces high
- **Override**: none

## What

Extract the duplicated test boilerplate from 14 test files into a shared `tests/test-helpers.sh`. Every file with inline `pass()/fail()/section()/skip()` definitions sources the shared file instead. The 45 older test files that use inline `PASS=$((PASS + 1))` counting are out of scope — they can adopt the harness incrementally.

## Rules

- **R-001** [unit]: A new file `tests/test-helpers.sh` exists and provides: `pass()`, `fail()`, `section()`, `skip()` functions (2-arg signature: `pass "id" "desc"`), counter variables (`PASS`, `FAIL`, `SKIPPED`, `FAILED_IDS`), color definitions (`GREEN`, `RED`, `YELLOW`, `RESET`), the standard preamble (`set -uo pipefail`, cd to repo root, `REPO_DIR="$(pwd)"`), and a `summary()` function that prints the final tally and exits non-zero if any tests failed. Note: test-allowed-tools-check.sh has a 1-arg `pass "desc"` variant — it must be updated to the 2-arg signature or keep its own helpers.

- **R-002** [unit]: `summary()` accepts a test suite name as its first argument and prints a consistent format: `"{name}: {PASS} passed, {FAIL} failed"` (plus `", {SKIPPED} skipped"` if SKIPPED > 0). If `FAILED_IDS` is non-empty, prints the list. Exits 1 if FAIL > 0, exits 0 otherwise.

- **R-003** [unit]: All 14 listed test files are migrated to source `tests/test-helpers.sh`. Each file adds a `source` line near the top. The migration scope varies by file variant:
  - **Variant A** (test-agent-hooks, test-carchitect, test-carchitect-phase1, test-fix-diff-reviewer-agent, test-integration-test-contracts, test-tdd-mini-audit, test-session-cost, test-project-dashboard): Full extraction — inline definitions of `pass()`, `fail()`, `section()`, `skip()`, counter variables, color definitions, and preamble boilerplate are removed.
  - **Variant B** (test-dev-journal, test-qa-uncertain): One-liner `pass()`/`fail()` definitions and counter variables are removed. These files gain color output and section()/skip() from the harness (previously absent).
  - **Variant C** (test-sensitive-file-guard, test-auto-policy, test-allowed-tools-check): These files do NOT define pass()/fail()/section()/skip(). They use assert_eq/assert_contains/file_contains helpers that directly increment PASS/FAIL. They source test-helpers.sh for the preamble and counter variables only. Their file-specific assert helpers remain per R-008.
  - **Variable normalization**: test-architecture-drift.sh uses `FAILED_INVS` — its fail() and summary must be updated to use the harness-provided `FAILED_IDS` instead.
  The files are: test-agent-hooks.sh, test-allowed-tools-check.sh, test-architecture-drift.sh, test-auto-policy.sh, test-carchitect-phase1.sh, test-carchitect.sh, test-dev-journal.sh, test-fix-diff-reviewer-agent.sh, test-integration-test-contracts.sh, test-project-dashboard.sh, test-qa-uncertain.sh, test-sensitive-file-guard.sh, test-session-cost.sh, test-tdd-mini-audit.sh.

- **R-004** [unit]: After migration, every migrated test file produces the same number of test results (PASS + FAIL + SKIPPED) as before migration. Verification: count lines matching the pass/fail/skip output patterns in each file's stdout before and after migration. Output FORMAT may change (standardized by harness), but COUNTS must be identical. No test is lost or duplicated by the extraction.

- **R-005** [unit]: `test-helpers.sh` is NOT added to `sync.sh` or the `correctless/` distribution. It is test infrastructure, not a shipped artifact. It stays in `tests/` only.

- **R-006** [unit]: Files that set additional shell options beyond `set -uo pipefail` (e.g., `set -f` for noglob) retain those options in the file after the `source` line. The harness provides only the common baseline.

- **R-007** [unit]: The `source` line uses a path relative to the test file's location: `source "$(dirname "${BASH_SOURCE[0]}")/test-helpers.sh"`. This works regardless of the caller's working directory.

- **R-008** [unit]: File-specific variables (e.g., `SCRIPT`, `LIB_SH`, `HOOKS_DIR`) remain in each test file. The harness provides only the universal boilerplate that is identical across all 14 files.

## Won't Do

- **Migrating the 45 inline test files** — they use `PASS=$((PASS + 1))` directly instead of `pass()`. Converting them changes test behavior and is a separate concern.
- **Adding assert helpers** (assert_eq, assert_contains, etc.) — useful but out of scope. The harness provides pass/fail, not assertion DSL.
- **Changing test output format** — the summary format is standardized but individual test output (`PASS: id — desc`) stays as-is.

## Risks

- **Behavioral regression from sourcing order** — if a file sets variables before sourcing the harness, the harness's preamble (cd to repo root) could overwrite them.
  1. Mitigate — R-007 sources early, before file-specific setup. R-006 preserves file-specific options after the source line.

- **ShellCheck warnings on non-constant source** — `source "$(dirname ...)/test-helpers.sh"` triggers SC1090.
  1. Mitigate — add `# shellcheck disable=SC1090` to test-helpers.sh or to each consumer's existing shellcheck directive line.

## Open Questions

None — this is a mechanical extraction with no design ambiguity.
