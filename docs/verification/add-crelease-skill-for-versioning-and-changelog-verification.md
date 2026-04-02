# Verification: Add /crelease Skill for Versioning and Changelog

## Rule Coverage
| Rule | Test | Status | Notes |
|------|------|--------|-------|
| R-001 [integration] | test_r001_skill_content (9 assertions) | covered | Spec-based bump, breaking detection patterns, unmapped commits, highest-wins, no-commit-msg |
| R-002 [integration] | test_r002_skill_content (4 assertions) | covered | Confirm, current/proposed version, override |
| R-003 [integration] | test_r003_skill_content (7 assertions) | covered | Changelog groups (4), slug ref, prepend |
| R-004 [integration] | test_r004_r013 + 3 standalone (9 assertions) | covered | Integration: runs setup against package.json, Cargo.toml, pyproject.toml, Go, setup.cfg, CHANGELOG.md |
| R-005 [integration] | test_r005_skill_content (5 assertions) | covered | jq, sed, old version check, skip warning |
| R-006 [integration] | test_r006_skill_content (5 assertions) | covered | Tests, sync, QA findings, tag collision, active workflows |
| R-007 [integration] | test_r007_skill_content (3 assertions) | covered | Annotated tag, v{version} format, changelog message |
| R-008 [integration] | test_r008_skill_content (2 assertions) | covered | Commit before tag, Release v{version} |
| R-009 [integration] | test_r009_skill_content (2 assertions) | covered | Badge detection, shields.io-only scope |
| R-010 [integration] | test_r010_skill_content (3 assertions) | covered | No-spec fallback, user classifies, conventional commits |
| R-011 [integration] | test_r011_skill_content (3 assertions) | covered | Dry-run, preview, default first option |
| R-012 [integration] | test_r012_skill_exists (10 assertions) | covered | SKILL.md exists + not stub, sync.sh x2, docs, README link |
| R-013 [integration] | test_r004_r013 (5 assertions) | covered | Integration: release section exists, version_file/pattern set or null |
| R-014 [unit] | test_r014_skill_content (4 assertions) | covered | Style preserve, heading pattern, create new, date format |
| R-015 [integration] | test_r015_skill_content (5 assertions) | covered | Push options (tag+commit, tag-only, manual), gh release |
| R-016 [unit] | test_r016_skill_content (7 assertions) | covered | Token log path, skill/phase/agent_role/total_tokens/duration_ms/timestamp fields |
| R-017 [integration] | test_r017_skill_content (4 assertions) | covered | Dirty tree check, stash/abort/continue options |
| R-018 [integration] | test_r018_skill_content (4 assertions) | covered | No prior tags, 0.1.0/1.0.0/manual options |
| R-019 [unit] | test_r019_skill_content (2 assertions) | covered | Nothing to release, exits |

**Structural tests**: test_skill_structure (6 assertions) — minimum 80 lines, 6+ section headings, dedicated sections for bump/changelog/sanity/tagging. Prevents keyword-stuffing.

**Total: 99 test assertions across 22 test functions. 19/19 rules covered.**

## Dependencies
- No new dependencies (shell-only project)

## Architecture Compliance
- ✓ PAT-001: Source-to-dist sync clean (`sync.sh --check` passes)
- ✓ PAT-001: `crelease` registered in both Lite and Full skill lists in sync.sh
- ✓ PAT-005: SKILL.md has correct frontmatter (name, description, allowed-tools)
- ✓ Distribution parity: skills/crelease/SKILL.md matches both dist copies
- ✓ No direct edits to distribution targets
- ✓ Portable sed pattern (write to tmpfile + mv) used in setup

## QA Class Fixes Verified
- QA-001: Breaking change confirmation — yes/no branches documented ✓
- QA-002: Section-aware Cargo.toml parsing (sed [package] section) ✓
- QA-003: Timestamp assertion added to R-016 tests ✓
- QA-004: Shields.io-only scope constraint in SKILL.md ✓
- QA-005: Updated skill/test counts (README: 25 skills, 18 Lite/25 Full; ARCHITECTURE: 25 skills, 8 test suites) ✓
- QA-006: Single find invocation for Go version detection ✓
- QA-007: Acknowledged limitation (keyword-based SKILL.md testing) — accepted ✓
- QA-008: Section-aware pyproject.toml parsing (sed [project] section) ✓

## Smells
- (none found — no TODO/FIXME/HACK, no STUB:TDD remnants, no debug statements)

## Drift
- (none found — implementation matches spec for all 19 rules)

## Bonus Fixes (found during /simplify)
- Fixed unsafe JSON sanitizer regex in setup (replaced with graceful skip + warning)
- Fixed root cause: Rust `build_error_pattern` heredoc producing invalid JSON escape (`error\[E` → `error\\[E`)
- Fixed pre-existing test-consolidation.sh false assertion (statusline doesn't read workflow-config.json)

## Spec Updates
- 7 rules added during /creview (R-014 through R-019, plus R-017 dirty tree check)
- No spec changes during TDD

## Overall: PASS — 19/19 rules covered, 0 uncovered, 0 drift items, 8 QA findings fixed
