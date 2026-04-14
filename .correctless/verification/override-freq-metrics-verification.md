# Verification: Override Frequency Metrics

- **Spec**: `.correctless/specs/override-freq-metrics.md`
- **Spec hash**: `6d20f660e14c6ffa76ab861a2a759e5330a089a1cf248d1aec293733a039bf2c`
- **Branch**: `feature/override-freq-metrics`
- **HEAD**: `00d0579` (Extract shared timestamp-sort helper, reduce jq calls per file)
- **Intensity**: high
- **QA rounds**: 2

## Rule Coverage

Effective intensity is **high**. All 6 spec rules (R-001 through R-006) are covered by `tests/test-override-freq-metrics.sh` (40 asserts, 0 failures).

| Rule | Test(s) | Status | Notes |
|------|---------|--------|-------|
| R-001 [unit] (preserve override logs) | `test_r001_preserved_file_created`, `test_r001_branch_filtering`, `test_r001_zero_override_case`, `test_r001_date_suffix_prevents_collision`, `test_r001_missing_override_log` | covered | 5 tests covering: metadata wrapper structure, branch filtering, zero-override case, date suffix collision prevention, missing override log graceful handling. `preserve_override_log` in `scripts/override-scrutiny.sh` exercises real function calls. |
| R-002 [unit] (override count in workflow-history.md) | `test_r002_override_count_in_history`, `test_r002_zero_count_omitted`, `test_r002_fallback_chain` | covered | Structural assertions against `skills/cdocs/SKILL.md` — verifies `Overrides:` format, zero-count omission instruction, and fallback chain (preserved file -> ephemeral log -> 0). |
| R-003 [unit] (Override Health section in /cmetrics) | `test_r003_override_health_section`, `test_r003_mean_calculation`, `test_r003_warning_threshold`, `test_r003_empty_directory_message`, `test_r003_cluster_tie_breaking` | covered | Structural assertions against `skills/cmetrics/SKILL.md` — verifies section presence, mean calculation description, 0.5 warning threshold, empty-directory message, and alphabetical tie-breaking by shortest reason. |
| R-004 [integration] (cross-run override detection) | `test_r004_cross_run_escalation`, `test_r004_cross_run_single_no_escalation`, `test_r004_cross_run_zero_preserved`, `test_r004_escalation_message_includes_context`, `test_r004_recent_window` | covered | Integration tests calling `review_override_issuance` and `check_cross_run_overrides` with real temporary directories and JSON fixtures. Tests: 2+ matches escalate, 1 match does not, 0 files does not, message includes task slugs/dates, recent-10 window excludes old matches. |
| R-005 [unit] (gitignored, project-level) | `test_r005_meta_gitignored`, `test_r005_path_not_branch_scoped` | covered | Asserts `.correctless/meta/` in `.gitignore` and verifies override path uses `{task-slug}` (project-level), not `{branch-slug}` (branch-scoped). |
| R-006 [unit] (50-file cap) | `test_r006_cap_triggers_deletion`, `test_r006_malformed_evicted_first`, `test_r006_timestamps_sorted_correctly` | covered | Integration tests calling `preserve_override_log` with 50+ files in temp directory. Tests: cap enforcement (<= 50 after adding 51st), malformed files (missing `completed_at`) evicted first, oldest-by-timestamp evicted correctly. |

**Coverage totals**: 6/6 rules covered. **No uncovered rules.**

## Undocumented Dependencies

No undocumented dependencies found.

- `jq` — already documented (ENV-002).
- `scripts/lib.sh` — sourced at top of `override-scrutiny.sh`, already documented (ABS-001).
- `scripts/workflow-state-ext.sh` — sourced at top of `override-scrutiny.sh`, already established.
- `jaccard_similarity` — pre-existing function in `scripts/override-scrutiny.sh`, used by cross-run check.
- `_list_overrides_by_timestamp` — new helper function in `scripts/override-scrutiny.sh`, internal to the file, no external consumers beyond the file itself.
- No new system tools, no new npm/pip packages, no new external dependencies.

## Architecture Compliance

- **ABS-020 updated**: Added cross-run pre-check documentation, `preserve_override_log`, `check_cross_run_overrides` to enforced-at list, and `test-override-freq-metrics.sh` to test references.
- **ABS-021 added**: Documents `.correctless/meta/overrides/` directory contract — sole writer (`preserve_override_log` via `/cauto`), readers (`/cmetrics`, `/cdocs`, `override-scrutiny.sh`), retention (50-file cap), schema, gitignore policy.
- **Cauto allowed-tools**: `Write(.correctless/meta/overrides/*)` added to frontmatter.
- **Cauto Step 9.5**: Override log preservation step added after PR creation.
- **Cdocs SKILL.md**: Override count source section (R-002) with fallback chain documented.
- **Cmetrics SKILL.md**: Override Health section with data source `glob .correctless/meta/overrides/*.json` added to both primary sources list and output format.

## Spec Hash Integrity

Spec file at `.correctless/specs/override-freq-metrics.md` is unchanged since review approval.

SHA-256: `6d20f660e14c6ffa76ab861a2a759e5330a089a1cf248d1aec293733a039bf2c`

## Smells

None detected. The implementation follows existing patterns:
- `preserve_override_log` mirrors the ephemeral-to-persistent pattern used by intensity calibration (ABS-005).
- The 50-file cap with timestamp-based eviction is consistent with the recency window pattern (PAT-004).
- Cross-run detection reuses the existing `jaccard_similarity` function at the same 0.4 threshold as retry prevention.
- The `_list_overrides_by_timestamp` helper is a clean extraction that `preserve_override_log` and `check_cross_run_overrides` both consume.
