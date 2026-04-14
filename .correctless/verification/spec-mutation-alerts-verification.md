# Verification: Spec Mutation Alerts

## Rule Coverage

| Rule | Test | Status | Notes |
|------|------|--------|-------|
| R-001 [unit] | test_r001_spec_hash_on_tests, test_r001_spec_hash_after_spec_update_resume | covered | 6 assertions: hash not set before transition, set after, 64-char SHA-256, matches actual file hash, plus spec-update resume path |
| R-002 [unit] | test_r002_done_warns_on_mutation, test_r002_done_silent_no_mutation | covered | 6 assertions: WARNING emitted, mentions "modified after review", includes "lines changed", transition completes; silent when unchanged, transition succeeds |
| R-003 [unit] | test_r003_spec_update_rehashes | covered | 5 assertions: initial hash set, hash changed after spec-update, updated hash matches new file content, done does not warn after legitimate spec-update |
| R-004 [unit] | test_r004_missing_spec_at_done | covered | 3 assertions: WARNING emitted, mentions "not found", transition completes despite missing spec |
| R-005 [unit] | test_r005_sole_writer | covered | 1 assertion: grep confirms no other hook/script in hooks/*.sh or scripts/*.sh references spec_hash |

**All 5 rules covered. 20 assertions pass, 0 fail.**

## Dependencies

No new dependencies added. Uses `sha256_hash_file` from scripts/lib.sh (already available). No new external tools or libraries.

## Architecture Compliance

- **ABS-001 (shared script library)**: Compliant. The `_read_spec_hash()` helper sources `sha256_hash_file` from lib.sh. No function duplication.
- **ABS-003 (state file locking)**: Compliant. R-001 uses `locked_update_state()` for the atomic state update that writes `spec_hash`. R-003 (spec-update) similarly uses `locked_update_state()`.
- **PAT-001 (source-to-dist sync)**: Compliant. `hooks/workflow-advance.sh` and `correctless/hooks/workflow-advance.sh` are identical. `sync.sh --check` passes clean.
- **PAT-004 (branch-scoped state)**: Compliant. `spec_hash` and `spec_line_count` are written to the per-branch workflow state file by `workflow-advance.sh` only (R-005).
- **PAT-010 (jq as-binding parens)**: Compliant. The `($lines | tonumber)` in the locked_update_state jq filter is properly structured — no bare `as $var` after arithmetic operators.
- **PAT-011 (SHA-256 hash verification chain)**: Compliant. Uses `sha256_hash_file` from lib.sh which has the sha256sum/shasum/openssl fallback chain. Hash stored at review->tests, verified at done.

## Prohibition Check

No prohibited imports or constructs detected in changed files. No eval of user input, no unquoted variables in jq filters (R-003 uses `--arg` for all dynamic values).

## QA Class Fixes Verified

No BLOCKING findings during QA. 1 QA round with 0 findings requiring class fixes.

## Antipattern Scan

**Manual smell check:**
- No TODO/FIXME/HACK comments in changed files
- No debug statements or hardcoded credentials
- No commented-out code
- No overly broad error catches
- No unused imports

**Semantic antipattern checklist:**
- disconnected middleware: N/A — no new hooks
- scope creep: No. Changes are strictly scoped to workflow-advance.sh
- over-abstraction: No. `_read_spec_hash()` is a minimal helper (14 lines) that avoids duplicating hash+path resolution between 3 call sites (R-001, R-002, R-003)
- mock-testing-the-mock: No. Tests use real setup invocations against real temp repos with real git branches
- happy-path-only: No. Tests cover: hash capture, mutation detection, no-mutation silence, spec-update re-hash, missing file, sole-writer enforcement, spec-update resume path
- silently removed safety guards: No. All existing workflow-advance.sh guards preserved; spec integrity checking is additive

## Drift

No drift detected. The implementation matches the spec on all 5 rules:
- R-001: spec_hash written at review->tests transition via sha256_hash_file from lib.sh, stored in workflow state. spec_file path read from state. (confirmed)
- R-002: At done transition, re-hashes spec and compares to stored spec_hash. Warning includes line count delta. Transition proceeds regardless. (confirmed)
- R-003: spec-update re-hashes and updates spec_hash in workflow state. Done transition does not warn after legitimate spec-update. (confirmed)
- R-004: Missing spec file at done emits "not found" warning. Transition proceeds. (confirmed)
- R-005: Static analysis confirms only workflow-advance.sh references spec_hash in hooks/ and scripts/. (confirmed)

## Spec Updates

0 spec updates during TDD.

## Overall: PASS with 0 BLOCKING findings

20 test assertions pass. 5/5 rules covered. 0 drift items. 0 BLOCKING findings. 1 QA round completed with no findings.
