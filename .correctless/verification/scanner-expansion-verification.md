# Verification: Scanner Expansion

## Rule Coverage

| Rule | Level | Test Function | Status | Assertions | Notes |
|------|-------|---------------|--------|------------|-------|
| R-001 | unit | test_se_r001_grep_p_detection | covered | 7 | grep -P, grep -oP, grep -E negative, non-.sh negative |
| R-002 | unit | test_se_r002_gnu_grep_ext_detection | covered | 13 | \s/\w/\d medium, \b low, POSIX exclusion suppression (4 cases), sed negative |
| R-003 | unit | test_se_r003_pattern_meta_entries | covered | 9 | All 4 new PATTERN_META entries, severity/category verification |
| R-004 | unit | test_se_r004_dead_security_calls | covered | 13 | Dead fn detected, live fn negative, tagged security, library exclusion, orphan library, hooks exclusion, function-syntax variant, description check |
| R-005 | unit | test_se_r005_pluggable_exclusion | covered | 6 | _default_ prefix, pluggable comment, callback comment, non-pluggable still flagged |
| R-006 | — | (merged into R-003) | N/A | — | PATTERN_META entries for dead-security-fn covered in R-003 |
| R-007 | integration | test_se_r007_integration_all_patterns | covered | 6 | Full scanner run producing all 3 new pattern IDs in single fixture |
| R-008 | unit | test_se_r008_ctdd_check8 | covered | 6 | Check 8 exists in audit blockquote, production call chain anchor, dead-code-in-security-paths mention, "called from"/"invoked by" detection |
| R-009 | unit | test_se_r009_dead_security_fn_drift + test_se_r009 (evasion tests) | covered | 5 + 6 | Content-pairing drift: audit blockquote anchor, PATTERN_META key, literal string in ctdd |
| R-010 | unit | test_se_r010_ap001_updated | covered | 4 | AP-001 Frequency updated with 2026-04-12 data, How-to-catch references scanner enforcement |
| R-011 | unit | test_se_r011_ap022_entry | covered | 10 | AP-022 heading, check_override_retry example, scanner enforcement reference, all required fields, PRH-006 mention, advisory backstop |

**11/11 rules covered (R-006 merged into R-003). 85 scanner-expansion assertions across 2 test files, 0 failures.**

Total test counts:
- `tests/test-antipattern-scan.sh`: 287 tests (85 new for scanner-expansion + 202 pre-existing), all passing
- `tests/test-test-evasion-antipatterns.sh`: 55 tests (6 new for SE-R-009 drift test + 49 pre-existing), all passing

## Mutation Testing

Not applicable for this feature. The scanner-expansion changes are primarily:
1. New grep-based pattern detection (sections e/f) -- tested via fixture repos with known patterns
2. New function `check_dead_security_calls()` -- tested via fixture repos with dead/live functions
3. Metadata entries (PATTERN_META) -- tested by direct assertion
4. Documentation updates (antipatterns.md, ctdd SKILL.md) -- tested by content assertions

The integration test (SE-R-007) is the strongest mutation barrier: it runs the full scanner against a fixture repo containing all three new pattern types and asserts all three findings appear.

## Dependencies

- **External tools**: bash 4+, git, grep, sed, head, find, jq, standard coreutils. No new dependencies beyond what the scanner already requires.
- **Internal dependencies**: `scripts/lib.sh` (branch_slug, sourced at startup). No new internal dependencies.
- **Sync**: `correctless/scripts/antipattern-scan.sh` and `correctless/skills/ctdd/SKILL.md` synced via `sync.sh --check` (verified clean).

## Architecture Compliance

- **TB-002** (no file content in JSON): PASS -- descriptions hardcoded in PATTERN_META per pattern ID. Dead function names are NOT included in finding descriptions (verified by SE-R-004i test).
- **PAT-003** (phase-transition scripts): PASS -- `check_dead_security_calls()` runs inside the existing scanner, which is already PAT-003 compliant.
- **ENV-001** (Bash 4+): PASS -- uses `declare -A`, `local -a`, process substitution.
- **ENV-002** (jq required): PASS -- inherits scanner's existing jq check at startup.
- **ENV-004** (POSIX grep only): PASS -- `check_dead_security_calls()` uses `grep -rnF` and `grep -qE` with POSIX ERE only. No `-P`, no `\b`/`\s`/`\w` in scanner's own patterns. Self-consistency verified: the scanner's own portability checks (sections e/f) use `grep -qF` and `grep -qE` with POSIX patterns only, built via `printf` to avoid literal non-POSIX sequences in the source.

## Antipattern Scan Results

The antipattern scan (`bash scripts/antipattern-scan.sh main`) exits with code 1 due to a **pre-existing bug** in `is_test_file()` (not introduced by this feature): the configured `TEST_FILE_PATTERN=tests/test*.sh|tests/**/*` is matched against `basename` only, so `test-antipattern-scan.sh` doesn't match the `tests/test*.sh` pattern (which includes a directory prefix). This causes the 3000+ line test file to be processed as a non-test shell file, and the echo-scanning section (b) crashes on a `pipefail` failure during line-by-line processing.

This is tracked as a pre-existing issue. The scanner's test suite passes all 287 tests because tests use isolated fixture repos where the `is_test_file()` pattern is not set (empty TEST_FILE_PATTERN hits the fallback path check `tests/*` which works correctly).

## Spec-Implementation Drift

No drift detected between spec and implementation:

1. **R-001 spec says**: `check_shell()` section (e) detects `grep -P` with pattern ID `gnu-grep-p`, severity `high`. **Implementation**: Lines 451-456 match `grep -P` and `--perl-regexp` using POSIX ERE.
2. **R-002 spec says**: section (f) detects `\s`/`\w`/`\d`/`\b` with line-scoped POSIX exclusions. **Implementation**: Lines 464-498, uses printf-built patterns to avoid literal non-POSIX sequences in the scanner itself. \b gets `gnu-grep-ext-low` (low severity); others get `gnu-grep-ext` (medium).
3. **R-003 spec says**: PATTERN_META entries with correct severity/category. **Implementation**: Lines 52-56 in PATTERN_META.
4. **R-004 spec says**: `check_dead_security_calls()` runs after per-file loop, scans all security scripts. **Implementation**: Lines 700-791, called at line 858.
5. **R-005 spec says**: excludes `_default_*` and `pluggable`/`callback` comments. **Implementation**: `_is_pluggable_function()` at lines 683-698.
6. **R-007 spec says**: integration test with all three pattern IDs. **Implementation**: `test_se_r007_integration_all_patterns` in test file.
7. **R-008 spec says**: ctdd check 8 for "production call chain". **Implementation**: Check 8 added to ctdd SKILL.md audit blockquote.
8. **R-009 spec says**: content-pairing drift test. **Implementation**: `test_se_r009_dead_security_fn_drift` in both test files.
9. **R-010 spec says**: AP-001 entry updated with 2026-04-12 data and scanner enforcement. **Implementation**: AP-001 entry in antipatterns.md updated.
10. **R-011 spec says**: AP-022 entry for dead code in security paths. **Implementation**: AP-022 entry in antipatterns.md with all required fields.

## QA Class Fixes Verified

QA Round 1 produced 1 NON-BLOCKING finding:
- **QA-001** (R-004): `check_dead_security_calls()` uses `find scripts/` assuming cwd is repo root. Accepted as-is -- consistent with all other scanner functions that use relative paths. Status: open (non-blocking).

No BLOCKING findings. No class fixes required.

## Pre-existing Issues Noted

1. **is_test_file() pattern mismatch**: The `TEST_FILE_PATTERN=tests/test*.sh|tests/**/*` from workflow-config.json includes directory prefixes, but `is_test_file()` matches against `basename` only. This causes test files to be processed as non-test files by the scanner's echo-detection section. Pre-existing, not introduced by scanner-expansion. Does not affect test suite results (fixture repos use empty pattern, hitting the fallback path). Recommend fixing in a separate feature.

## Verification Outcome

**PASS** -- All 11 spec rules covered by tests. 342 assertions across 2 test files, 0 failures. No BLOCKING findings. Architecture compliant. Sync clean. No spec-implementation drift.
