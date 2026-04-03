# Verification: Add Calm Reset Prompts to Orchestrators

## Rule Coverage

| Rule | Test Function | Status | Notes |
|------|--------------|--------|-------|
| R-001 [integration] | test_r001_green_phase_reset | covered | 7 assertions: stop/re-read/ACTUALLY checking/no pressure/threshold/tracking/GREEN discriminator |
| R-002 [integration] | test_r002_qa_fix_round_reset | covered | 4 assertions: reframe/re-read instance_fix+class_fix/no re-attempt/recurring trigger |
| R-003 [integration] | test_r003_caudit_divergence_reset | covered | 4 assertions: divergence prompt/re-read original/smaller changes/trigger threshold |
| R-004 [unit] | test_r004_human_escalation | covered | 8 assertions: existence + exact phrasing + count-based (>=3 ctdd, >=1 caudit) |
| R-005 [unit] | test_r005_concrete_reread | covered | 8 assertions: existence + specific artifacts + count-based (>=3 ctdd, >=1 caudit) |
| R-006 [unit] | test_r006_no_shortcuts | covered | 14 assertions: 6 prohibited words (3 whole-file, 3 section-scoped) x 2 files + 2 positive checks |
| R-007 [integration] | test_r007_trigger_thresholds | covered | 6 assertions: GREEN/fix/QA thresholds + caudit divergence + not configurable + literal numbers |
| R-008 [unit] | test_r008_reset_cap_and_escalation | covered | 7 assertions: once-per-trigger cap + 4 escalation components + /cdebug + caudit cap and escalation |
| R-009 [integration] | test_r009_no_new_state | covered | 4 assertions: ctdd/caudit working memory + no new state file references |
| R-010 [integration] | test_r010_sync_propagation | covered | 10 assertions: file existence + keywords + sync.sh --check + negative (other skills clean) |
| R-011 [integration] | test_r011_fix_round_reset | covered | 6 assertions: fix context/stop/re-read findings/ACTUALLY describing/no pressure/distinct from R-001 |

**Coverage: 11/11 rules covered, 82 total assertions, 0 uncovered, 0 weak.**

## Dependencies

No new dependencies. This feature modifies only SKILL.md instruction text and adds a bash test file.

## Architecture Compliance

- ✓ PAT-001: All edits in source `skills/` — distributions synced via `sync.sh` (verified clean)
- ✓ PAT-002: Reset prompts work within agent separation — prompts injected by orchestrator, not a new agent
- ✓ PAT-003: No new gating rules needed — resets are instruction text, not file operations
- ✓ PAT-004: No new state files or fields — attempt tracking in orchestrator working memory (R-009)
- ✓ PAT-005: No SKILL.md frontmatter changes — reset sections are additions to existing skill body

## QA Class Fixes Verified

- QA-001 ✓: `extract_reset_sections` + `reset_section_not_contains` helpers for section-scoped negative assertions
- QA-002 ✓: Count-based assertions for R-004 (>=3 ctdd, >=1 caudit)
- QA-003 ✓: Count-based assertions for R-005 (>=3 ctdd, >=1 caudit)
- QA-004 ✓: caudit assertions added to R-008 test
- QA-005 ✓: `sync.sh --check` + negative assertion for other skills
- QA-006 ✓: GREEN-context discriminator (section header check)
- QA-007 ✓: Self-referential metadata removed from implementation

## Smells

None found. No TODO/FIXME/HACK/debug statements in changed files.

## Drift

None found. All 11 spec rules accurately reflected in implementation text.

## Spec Updates

- R-011 added during review phase (split from R-001 to distinguish fix-round reset from GREEN reset)
- /cdebug escalation integration added to R-008 during review phase

## Overall: PASS — 11/11 rules covered, 82 assertions, 0 findings
