# Verification: Intensity Calibration Loop

## Rule Coverage

| Rule | Test Function | Status | Notes |
|------|--------------|--------|-------|
| INV-001 | test_inv001_cverify_writes_calibration | covered | 17 assertions: file ref, field names, sources, BLOCKING-only, write scope |
| INV-002 | test_inv002_calibration_schema | covered | 7 assertions: schema fields, types, source artifacts |
| INV-003 | test_inv003_cspec_reads_calibration | covered | 5 assertions: file ref, overlap, arithmetic mean, post-signal |
| INV-004 | test_inv004_csetup_calibration_mode | covered | 9 assertions: 3 modes, default passive, config field, write-to-config |
| INV-005 | test_inv005_mode_behaviors | covered | 11 assertions: mode config, thresholds, recommended_intensity eval, hybrid |
| INV-006 | test_inv006_config_templates | covered | 4 assertions: both templates, passive default |
| INV-007 | test_inv007_cspec_read_only | covered | 3 assertions: no write/modify/delete, positive read check |
| INV-008 | test_inv008_no_calibration_graceful | covered | 3 assertions: missing file, dormant signal, no error |
| INV-009 | test_inv009_recommended_intensity_field | covered | 8 assertions: both templates, cspec ref, Step 8, pre/post distinction, Metadata section |
| INV-010 | test_inv010_recency_window | covered | 3 assertions: window of 50, timestamp sort, ignore beyond |
| INV-011 | test_inv011_post_signal_modifier | covered | 4 assertions: not 5th signal, post-signal modifier, after 4-signal, never lowers |
| INV-012 | test_inv012_show_arithmetic | covered | 7 assertions: list entries, sum/count/average, threshold, intermediate calc, Consider phrasing |
| PRH-001 | test_prh001_no_calibration_in_state | covered | 5 assertions: no calibration fields in workflow-advance.sh |
| PRH-002 | test_prh002_no_thresholds_in_config | covered | 6 assertions: no threshold fields in either config template |

**Coverage: 14/14 rules covered, 91 total assertions, 0 uncovered**

## Dependencies

No new dependencies. Feature modifies only .md and .json files (LLM instruction files and templates).

## Architecture Compliance

- ✓ Source-to-dist sync pattern (PAT-001): edits in source skills/, templates/ — sync.sh propagates
- ✓ Effective intensity pattern (PAT-005): no new intensity computation — extends existing detection
- ✓ Calibration section positioned after Step 7 (existing intensity detection) as Step 7b
- ✓ Recommended-intensity field added to Metadata section of both spec templates
- ✓ `Write(.correctless/meta/intensity-calibration.json)` added to cverify allowed-tools frontmatter
- ✓ Structured decision format in csetup matches existing pattern (numbered options with "Or type your own")
- ✓ Config templates both include `intensity_calibration_mode: passive` in workflow section

## QA Class Fixes Verified

- QA-001 (INV-009): Inline spec skeletons updated with Recommended-intensity ✓
- QA-002 (INV-005): Explicit recommended_intensity filtering added to overlap computation ✓
- QA-003 (INV-012): Test pattern tightened with calibration anchoring ✓
- QA-004 (INV-005): "Consider higher intensity" test assertion added ✓

## Smells

None found. All TODO/FIXME matches are template examples in cverify SKILL.md, not actual smells.

## Drift

- Distribution sync needed: `sync.sh` updated correctless/ distribution targets (expected — source edits during GREEN phase)
- No spec-implementation drift detected — all 14 rules accurately reflected in implementation

## Spec Updates

- 0 spec updates during TDD (spec_updates: 0 in workflow state)
- Spec remained stable throughout implementation

## Overall: PASS — 14/14 rules covered, 0 findings, 0 drift items
