# Verification: Cross-Feature Intelligence Layer

## Rule Coverage
| Rule | Test | Status | Notes |
|------|------|--------|-------|
| INV-001 | INV-001a..d | covered | Script exists, references all 6 sources, handles missing sources, produces all 6 sections |
| INV-002 | INV-002a..d | covered | Scope filtering: matching refs included, no-refs included unconditionally, unfiltered mode, non-overlapping excluded |
| INV-003 | INV-003a..b | covered | 90-day staleness exclusion, newest-first sort |
| INV-004 | INV-004a..b | covered | 30-entry cap enforced, per-section minimum preserved |
| INV-005 | INV-005a..e | covered | Top-level fields, entry fields, 200-char truncation, 6 section keys, warnings array |
| INV-006 | INV-006a..f | covered | cspec references script, --scope argument, allowed-tools pattern, no stderr suppression, context framing, truncation note |
| INV-007 | INV-007a..c | covered | Anti-anchoring directive present, calibration examples (weight/dismiss), positioned before Step 1 |
| INV-008 | INV-008a..b | covered | Only open findings extracted, field mapping correct |
| INV-009 | INV-009a..e | covered | DA-NNN extraction from both formats, inline severity, subsection severity, date from filename, empty file_refs |
| INV-010 | INV-010a..d | covered | Override entries extracted, duplicates collapsed with count, 8-char hex hash id, empty file_refs |
| INV-011 | INV-011a..d | covered | Lens recommendations extracted, collapsed by name, promotion_candidate >= 3, not flagged < 3 |
| INV-012 | INV-012a..d | covered | Debug investigation extracted, slug id, Root Cause summary, file_refs from Fix/Class Fix |
| INV-013 | INV-013a..e | covered | scripts/ location, sources lib.sh, exits 0, CLI arguments, proper shebang |
| INV-014 | INV-014a..d | covered | cstatus references intelligence, staleness threshold, no-data messaging, remediation for stale |
| INV-015 | INV-015a..c | covered | Setup glob covers scripts/*.sh, script exists, sync.sh handles scripts/ |
| INV-016 | INV-016a..e | covered | Phase effectiveness extracted, collapsed by phase, summary format, real field names (AP-031), audit entry |
| PRH-001 | PRH-001a..b | covered | workflow-advance.sh and scripts/wf/ do not reference cross-feature-intel |
| PRH-002 | PRH-002a | covered | cspec SKILL.md does not write to brief |
| PRH-003 | PRH-003a | covered | Anti-anchoring directive prevents interpolation |
| BND-001 | BND-001a..c | covered | Valid JSON with zero sources, all sections empty, no warnings |
| BND-002 | BND-002 | covered | Non-matching scope excludes entries |
| BND-003 | BND-003a..d | covered | No crash on malformed, warning added, other sources processed, descriptive warning text |

22/22 rules covered. 0 uncovered. 0 weak.

## Dependencies
- No new dependencies added (pure bash script, uses only jq which is an existing EA assumption)

## Architecture Adherence

- ABS-037: valid -- new entry added, enforced-at paths verified (scripts/cross-feature-intel.sh, skills/cspec/SKILL.md, skills/cstatus/SKILL.md all exist on disk), test file exists. ABS-037 ID not referenced in test assertions (tests cover the behavioral claims via PRH-001a/b and PRH-002a but not by entry ID).
- ABS-001: valid -- script sources lib.sh per convention
- ABS-005: valid -- cross-feature-intel follows same ABS-005 pattern (script writes, skill reads, advisory only)
- TB-003: valid -- anti-anchoring directive addresses TB-003 (LLM-generated historical findings -> spec agent context); DD-004 documents the asymmetry with TB-007 UNTRUSTED fences

### Drift Debt
No new drift-debt items. All existing items resolved or wont-fix.

0 entries checked stale, 0 drift-debt items.

## QA Class Fixes Verified
- QA-001 (stdout vs disk write gap): accepted as NON-BLOCKING design gap. Script outputs to stdout per PAT-003; cstatus reads from disk. /cspec captures stdout directly; /cstatus degrades via PAT-019 dormant. No structural fix needed -- the brief regenerates from source artifacts.
- QA-002 (sha256sum/shasum both missing): accepted as NON-BLOCKING. sha256sum or shasum is present on all supported platforms (Linux GNU coreutils, macOS BSD shasum).

## Antipattern Scan
- Source script (`scripts/cross-feature-intel.sh`): 0 findings
- Distribution script (`correctless/scripts/cross-feature-intel.sh`): multiple debug-echo false positives due to sync drift (the distribution copy has diverged from source -- see Findings below)
- Test file: no findings specific to this feature

## Smells
- No TODO/FIXME/HACK comments in source files (mktemp `XXXXXX` pattern is a false positive)
- No debug statements, commented-out code, or unused imports

## Drift

### BLOCKING: Distribution sync drift (PAT-001 violation)

`correctless/scripts/cross-feature-intel.sh` (944 lines) has diverged from `scripts/cross-feature-intel.sh` (876 lines) -- 148 lines of diff. The distribution copy contains:
- An extra `_is_within_90_days()` function not in source
- Missing `_epoch_to_date()` helper (inlined at each call site)
- Different override hash computation approach (`@base64` in jq vs `sha256sum` in shell)
- Expanded loop bodies (explicit if/else vs ternary)
- Split recency filter into separate `_filter_by_recency()`, `_shell_recency_filter()`, and `_sort_by_recency()` functions
- Expanded scope filter loop (explicit per-variable calls vs `for`/`eval`)

**Root cause**: The distribution copy was likely edited directly or `sync.sh` was run on an intermediate version. The tests run against the source script and all pass. The distribution copy may have different behavior on edge cases.

**Remediation**: Run `bash sync.sh` to propagate the source to the distribution. Verify the distribution tests still pass after sync.

## Spec Updates
- 0 spec updates during TDD (spec hash unchanged)

## Overall: FAIL with 1 BLOCKING finding

1 BLOCKING finding:
1. Distribution sync drift -- `correctless/scripts/cross-feature-intel.sh` has diverged from `scripts/cross-feature-intel.sh`. Must run `bash sync.sh` and verify before merge.
