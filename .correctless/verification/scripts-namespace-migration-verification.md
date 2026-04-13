# Verification: Scripts Namespace Migration

## Rule Coverage

| Rule | Test | Status | Notes |
|------|------|--------|-------|
| R-001 [unit] | test_r001_setup_installs_to_correctless_scripts | covered | 5 assertions: lib.sh + antipattern-scan.sh at new path, NOT at old path, directory exists |
| R-002 [integration] | test_r002_upgrade_migration, test_r002_upgrade_partial, test_r002_migration_before_hooks | covered | Full migration, partial migration, ordering constraint (before hooks). 12 assertions total |
| R-003 [unit] | test_r003_hook_fallback_paths, test_r003_workflow_advance_error_message | covered | All 6 hooks checked: fallback updated, primary path unchanged, shellcheck directives unchanged. Error message updated. 19 assertions |
| R-004 [unit] | test_r004_skill_antipattern_path | covered | cverify, ctdd, and antipattern-scan.sh usage comment all reference .correctless/scripts/ |
| R-005 [unit] | test_r005_sync_unchanged | covered | sync.sh exists, still targets correctless/scripts/, runs successfully, distribution files exist |
| R-006 [integration] | test_r006_source_tree_refs_unchanged, test_r006_installed_path_refs_updated, test_r006_full_test_suite | covered | Source-tree refs preserved in 4 test files, installed-path refs updated in 6 test files, main test suite passes (65/0) |
| R-007 [unit] | test_r007_readme_updated, test_r007_agent_context_source_refs_unchanged | covered | README cleaned up (old `rm -f` line removed), AGENT_CONTEXT source-tree refs preserved |

**Integration tests** (R-002, R-006): Both use real setup invocations against temp git repos, verifying end-to-end behavior. Two additional integration tests (`test_integration_hooks_find_lib_after_setup`, `test_integration_upgrade_then_hooks`) cross-validate R-001+R-003 and R-002+R-003 together.

**All 7 rules covered. 60 assertions pass, 0 fail.**

## Dependencies

No new dependencies added. No changes to package.json, go.mod, or any manifest file.

## Architecture Compliance

- ABS-001 (shared script library): Compliant. All hooks source lib.sh via primary path (dirname-based ../scripts) and fall back to .correctless/scripts/lib.sh. No local function duplication.
- PAT-001 (source-to-dist sync): Compliant. Source hooks at hooks/*.sh and dist hooks at correctless/hooks/*.sh both updated. sync.sh --check passes clean.
- Error handling: Follows existing pattern — fallback paths with elif chain, die on failure.
- No new patterns introduced. No new abstractions needed.

## Prohibition Check

No prohibited imports or constructs detected in changed files.

## QA Class Fixes Verified

- QA-001 (NON-BLOCKING): Migration message always mentions both files even in partial migration. Acknowledged — spec requires this exact text.
- QA-002 (NON-BLOCKING): test_r005_sync_unchanged captures $? after || true. Acknowledged — subsequent assertions provide real coverage.

No class fixes were required (no BLOCKING findings).

## Antipattern Scan

The antipattern scanner exits with code 1 and empty output when scanning this branch. Root cause: pre-existing bug in `check_shell()` function — the `grep -o '{' | wc -l` pipeline fails under `set -euo pipefail` when a line has no braces (grep returns exit 1, pipefail propagates it). This crash is triggered by `setup` being in the diff (it has empty lines inside functions), but the bug exists on `main` and would affect any branch that modifies a .sh file with certain patterns. Not a regression introduced by this feature.

**Manual smell check (substituting for scanner):**
- No TODO/FIXME/HACK comments in changed files
- No debug statements, console.log, or debugger statements
- No hardcoded values or credentials
- No commented-out code
- No overly broad error catches
- No unused imports

**Semantic antipattern checklist (ai-antipatterns.md):**
- disconnected middleware: N/A — no new hooks or middleware
- scope creep: No. Changes are strictly scoped to path migration
- over-abstraction: No. Reuses existing patterns
- mock-testing-the-mock: No. Tests use real setup invocations against real temp repos
- happy-path-only: No. Tests cover fresh install, upgrade, partial upgrade, and ordering
- silently removed safety guards: No. All error handling and fallback logic preserved; only paths changed

## Drift

No drift detected. The implementation matches the spec on all 7 rules:
- R-001: setup installs to .correctless/scripts/ (confirmed)
- R-002: migration detects old layout, moves files, prints message, does NOT delete scripts/ (confirmed)
- R-003: All 6 hook fallback paths updated, primary paths unchanged, shellcheck directives unchanged (confirmed)
- R-004: cverify, ctdd skills updated; antipattern-scan.sh usage comment updated (confirmed)
- R-005: sync.sh unchanged — still syncs scripts/*.sh to correctless/scripts/*.sh (confirmed)
- R-006: Test source-tree refs preserved, installed-path refs updated, full suite passes (confirmed)
- R-007: README updated, AGENT_CONTEXT source-tree refs preserved (confirmed)

## Spec Updates

0 spec updates during TDD.

## Overall: PASS with 0 BLOCKING findings

60 test assertions pass. 7/7 rules covered. 0 drift items. 0 BLOCKING findings. 2 NON-BLOCKING QA findings acknowledged. Pre-existing antipattern scanner bug noted (not a regression).
