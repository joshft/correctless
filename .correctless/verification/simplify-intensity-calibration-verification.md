# Verification: Simplify Intensity Calibration

## Summary

Simplification feature that removes active/hybrid calibration modes, the `intensity_calibration_mode` config key, and the 200K token auto-raise threshold from `/cspec`. Calibration becomes always-advisory: data is collected by `/cverify` (unchanged) and displayed as read-only context for the human during `/cspec` Step 8. No automated intensity decisions.

**Note**: No formal spec artifact exists at `.correctless/specs/simplify-intensity-calibration.md`. The test file references it but TDD was run without the full /cspec workflow. Rules are documented in the test suite header comments.

## Rule Coverage

| Rule | Test | Status | Notes |
|------|------|--------|-------|
| INV-001 (no auto-raise in /cspec) | test_inv001_no_auto_raise (7 assertions) | covered | Checks absence of auto-raise, active mode, hybrid mode in source + dist |
| INV-002 (no calibration mode config key) | test_inv002_no_calibration_mode_key (4 assertions) | covered | Checks absence of intensity_calibration_mode in source + dist |
| INV-003 (no 200K token threshold) | test_inv003_no_200k_threshold (4 assertions) | covered | Checks absence of 200,000/200000 in source + dist |
| INV-004 (passive advisory display retained) | test_inv004_passive_advisory_display (11 assertions) | covered | Verifies advisory format, QA rounds, BLOCKING findings, override history, token average, no threshold comparisons, no raise recommendations |
| INV-005 (/cverify writer unchanged) | test_inv005_cverify_writer_unchanged (9 assertions) | covered | Verifies all calibration entry fields still present in /cverify |
| INV-006 (graceful absence unchanged) | test_inv006_graceful_absence (2 assertions) | covered | Dormant signal pattern preserved |
| INV-007 (recency window unchanged) | test_inv007_recency_window (2 assertions) | covered | 50-entry limit preserved |
| INV-008 (no mode in /csetup or templates) | test_inv008_no_mode_in_csetup_or_templates (7 assertions) | covered | Checks source, dist, both template variants |
| INV-009 (docs reflect removal) | test_inv009_docs_reflect_removal (7 assertions) | covered | AGENT_CONTEXT.md + FEATURES.md checked for stale references |
| PRH-001 (no automated intensity decisions) | test_prh001_no_automated_decisions (3 assertions) | covered | Step 7b advisory-only enforcement |
| PRH-002 (no removal of data collection) | test_prh002_data_collection_intact (3 assertions) | covered | /cverify calibration writer still present |

Additionally, 3 cross-check test groups verify:
- Preserved test functions in existing test files (12 assertions)
- Removed test functions are gone (3 assertions)
- Updated test assertions are correct (5 assertions)

**All 79 tests pass. 0 uncovered rules.**

## Existing Test Suites

The modified existing test suites also pass:
- `test-intensity-calibration.sh`: 66 passed, 0 failed (removed INV-004/INV-005, updated INV-006/INV-012)
- `test-token-aware-intensity.sh`: 56 passed, 0 failed (removed INV-003, updated INV-004/INV-008i)

## Dependencies

No new dependencies. No package manifest changes.

## Architecture Adherence

- ABS-005 (Cross-skill calibration): **valid** — entry correctly describes cverify as sole writer, cspec as read-only. Entry does not mention active/hybrid/passive modes or thresholds. The invariant ("cverify is the sole writer. cspec is read-only") is still accurate post-simplification.
- ABS-006 (Token-log JSONL contract): **valid** — unchanged by this feature. Token data collection path unaffected.
- ABS-026 (Cost artifact): **valid** — unchanged. `/cverify` still reads cost artifact for `actual_cost_usd`.

No entries have stale `Enforced at` paths. No invariant conflicts detected.

### Drift Debt

No drift-debt.json exists. No new drift items detected.

## Antipattern Scan

58 total findings from the full scan, **0 findings from changed files**. All findings are pre-existing (debug-echo in test files, dead-security-fn in existing scripts).

## QA Class Fixes Verified

No QA findings artifact exists for this feature (no formal workflow state).

## Smells

- `tests/test-intensity-calibration.sh:243,263` — Comments referencing `intensity_calibration_mode` in removed test section headers. These are documentation comments explaining what was removed and why. **Not a defect.**
- `docs/workflow-history.md:75` — Historical feature description mentions "3 modes: passive, active, hybrid". This is historical documentation describing the original feature at time of shipping. **Not a defect** — workflow-history describes what was shipped, not current state.

## Drift

No drift detected. The implementation (removal of auto-raise, mode config, 200K threshold) matches the test suite's documented rules. The advisory display format in `/cspec` SKILL.md matches the test assertions.

## Spec Updates

No formal spec existed for this feature. The test file (`tests/test-simplify-intensity-calibration.sh`) serves as the de facto specification.

## Sync Status

`sync.sh --check` passes. Source and distribution copies are in sync.

## Overall: PASS with 0 findings

All 11 rules covered. All 201 tests pass across 3 test suites. No dependencies added. Architecture entries valid. No antipattern findings in changed files. Sync clean.
