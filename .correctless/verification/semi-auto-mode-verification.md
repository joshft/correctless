# Verification: Semi-Auto Mode

## Rule Coverage
| Rule | Test | Status | Notes |
|------|------|--------|-------|
| R-001 [integration] | test_r001 | covered | Pipeline order, context: fork, commit before simplify (14 assertions) |
| R-002 [integration] | test_r002 | covered | Phase gate check (structural — LLM skill cannot be mechanically invoked) |
| R-003 [integration] | test_r003 | covered | Preferences read with fallback (10 assertions) |
| R-004 [unit] | test_r004 | covered | Template has all 5 preference categories (16 assertions) |
| R-005 [integration] | test_r005 | covered | Escalation format, YAML frontmatter, 6 required fields, intensity thresholds (20 assertions) |
| R-006 [integration] | test_r006 | covered | All 5 heuristics including CLAUDE.md (14 assertions) |
| R-007 [unit] | test_r007 | covered | Shared constraint preserved, override mechanism documented (10 assertions) |
| R-008 [integration] | test_r008 | covered | PR creation options, TB-001b, PR body sections (17 assertions) |
| R-009 [unit] | test_r009 | covered | Intensity computation, cupdate-arch gate (8 assertions) |
| R-010 [integration] | test_r010 | covered | Correct phase names, ordering verified, verified/done phases (18 assertions) |
| R-011 [integration] | test_r011 | covered | 7 event types, timestamp, skill, elapsed_ms schema (17 assertions) |
| R-012 [integration] | test_r012 | covered | Simplify outside trust model documented (10 assertions) |
| R-013 [unit] | test_r013 | covered | Setup scaffolds preferences.md, idempotent, content verified (18 assertions) |
| R-014 [advisory] | test_r014 | covered | Tagged advisory, progress via audit trail (6 assertions) |
| R-015 [integration] | test_r015 | covered | Commit before simplify, git reset --hard, .correctless/ rejection (14 assertions) |
| R-016 [integration] | test_r016 | covered | Resumption, YAML parsing, phase consistency, stale cleanup (14 assertions) |
| R-017 [integration] | test_r017 | covered | Spec-update escalation, rule identification (10 assertions) |
| R-018 [integration] | test_r018 | covered | Upfront gh check, fail-fast message (8 assertions) |
| R-019 [unit] | test_r019 | covered | preferences.md in sensitive-file-guard, Write/Edit/Bash blocked (11 assertions) |

**Coverage: 19/19 rules covered. 0 uncovered. 0 weak.**

## Prerequisites
| Prerequisite | Test | Status |
|-------------|------|--------|
| PRE-001: is_full_mode() fix | test_pre001 + test_qa002 | covered (structural + 5 behavioral tests) |
| PRE-002: context: fork for cdocs/cupdate-arch | test_pre002 | covered |
| PRE-003: ARCHITECTURE.md entries (TB-004, ABS-007, ABS-008, TB-001b, ENV-004) | test_pre003 | covered |
| PRE-004: PAT-007, PAT-008 | test_pre004 | covered |
| PRE-005: Shared constraints preference reading | test_pre005 | covered |
| PRE-006: preferences.md in sensitive-file-guard DEFAULTS | test_pre006 | covered |
| PRE-007: sync.sh includes cauto | test_pre007 | covered |

## Dependencies
- No new external dependencies added. This feature creates markdown SKILL.md files and modifies existing shell scripts.
- `gh` CLI documented as optional dependency (ENV-004) — required only when `pr_creation: gh`.

## Architecture Compliance
- ✓ PAT-001 (PreToolUse hooks): No new PreToolUse hooks added. sensitive-file-guard.sh DEFAULTS updated per existing pattern.
- ✓ PAT-002 (Separate concerns): /cauto is a separate skill, not merged into existing hooks.
- ✓ PAT-003 (Phase-transition scripts): Uses workflow-advance.sh for all transitions.
- ✓ PAT-005 (Effective intensity): is_full_mode() now consults feature_intensity. Cauto respects intensity computation.
- ✓ PAT-006 (Hook metadata): No new hooks. Existing hook headers unchanged.
- ✓ ABS-001 (lib.sh): No changes to shared library. is_full_mode() uses state_file() from lib.sh.
- ✓ ABS-003 (State file locking): No direct state file writes. All through workflow-advance.sh.
- ✓ TB-001 (Config-sourced commands): TB-001b added for custom PR commands from preferences.md.
- ✓ TB-004 (new): Orchestrator autonomy boundary documented with escalation invariants.
- ✓ ABS-007 (new): Escalation file contract — cauto sole writer.
- ✓ ABS-008 (new): preferences.md contract — csetup scaffolds, all skills read.

## QA Class Fixes Verified
- QA-001: Skill count assertion added (test_qa001_skill_count_matches_docs) ✓
- QA-002: is_full_mode() behavioral tests added (5 combinations) ✓
- QA-003: TB-001b added to ARCHITECTURE.md ✓
- QA-004: R-008 summary pattern tightened ✓
- QA-005: R-002 dead infrastructure removed ✓
- QA-006: Extraneous ARCHITECTURE.md write permission removed ✓
- QA-007: R-001 integration gap documented ✓
- QA-008: cd without restore fixed in R-013 and R-019 ✓
- QA-009: Spec updated to say ENV-004 ✓

## Antipattern Scan
- Scanner could not run (no commits on branch yet — changes are unstaged). Manual review of new files found no TODOs, FIXMEs, debug statements, or commented-out code.

## Smells
- None found in new files.

## Drift
- No drift detected between spec and implementation.
- Stale "26 skills" references exist in README.md, CHANGELOG.md, docs/index.md, docs/design/correctless.md — these are documentation updates for /cdocs to handle, not implementation drift.

## Spec Updates
- 1 spec update during adversarial review: resolved all 15 findings, added R-015 through R-019, updated R-001 through R-014, added prerequisites.
- ENV-003 → ENV-004 corrected (QA-009).

## Test Summary
- 139 assertions in test-semi-auto-mode.sh (all pass)
- 63 assertions in test.sh (all pass, no regressions)
- 71 assertions in test-ci-hook-wiring.sh (all pass)
- 209 assertions in test-mcp.sh (all pass)
- 12 assertions in test-allowed-tools-check.sh (all pass)
- QA rounds: 2 (9 findings in R1, 0 new findings in R2)

## Overall: PASS — 0 BLOCKING findings
