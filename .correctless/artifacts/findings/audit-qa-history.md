# QA Olympics Findings — Correctless

## Run: 2026-04-03
### Round 1
| ID | Severity | Tier | Title | Status | Fixed in |
|----|----------|------|-------|--------|----------|
| QA-001 | high | confirmed | source_file comma delimiter breaks gate | fixed | 5dea27e |
| QA-002 | high | confirmed | cpr-review triggers high+ at standard intensity | fixed | 5dea27e |
| QA-003 | high | confirmed | workflow-gate.sh branch_slug() fails open detached HEAD | fixed | 5dea27e |
| QA-004 | high | confirmed | write_state() orphans temp files on jq failure | fixed | 5dea27e |
| QA-005 | high | confirmed | test R-003 expects stale ./correctless | fixed | 5dea27e |
| QA-006 | high | confirmed | spec templates missing from distribution | fixed | 5dea27e |
| QA-007 | high | probable | jq injection via package key in gate | fixed | 5dea27e |
| QA-008 | medium | confirmed | run_tests() dead code | fixed | 5dea27e |
| QA-009 | medium | confirmed | cmd_qa double-write race | fixed | 5dea27e |
| QA-010 | medium | confirmed | cmd_spec_update double-write race | fixed | 5dea27e |
| QA-011 | medium | confirmed | statusline wrong override field path | fixed | 5dea27e |
| QA-012 | medium | confirmed | corrupt JSON gate fails open | fixed | 5dea27e |
| QA-013 | medium | confirmed | 3 test suites missing trap cleanup | fixed | 5dea27e |
| QA-014 | medium | confirmed | ARCHITECTURE.md wrong config path | fixed | 5dea27e |
| QA-015 | medium | confirmed | test-cexplain.sh missing from test command | fixed | 5dea27e |
| QA-016 | medium | confirmed | test-cexplain.sh wrong assertion count | fixed | 5dea27e |
| QA-017 | medium | confirmed | PAT-005 duplicate ID across docs | fixed | 5dea27e |
| QA-018 | medium | probable | gate undocumented exit on mv fail | fixed | 5dea27e |
| QA-019 | medium | probable | grep regex metachar in package path | fixed | 5dea27e (regressed, re-fixed in R2) |
| QA-020 | medium | probable | pkg-cache files accumulate without bound | fixed | 5dea27e |
| QA-021 | medium | probable | stale paths in .correctless/config | fixed | 5dea27e |
| QA-022 | low | probable | audit-trail temp file orphaned on mv fail | fixed | 5dea27e |
| QA-024 | low | suspicious | fmt_tokens integer guard | fixed | 5dea27e |
| QA-025 | low | suspicious | ARCHITECTURE.md test suite count stale | fixed | 5dea27e |

### Round 2
| ID | Severity | Tier | Title | Status | Fixed in |
|----|----------|------|-------|--------|----------|
| R2-REG-1 | high | confirmed | R1 "no-branch" sentinel creates unresettable state | fixed | 7ca5cd0 |
| R2-REG-2 | medium | confirmed | grep -qF drops anchor — false-positive package match | fixed | 7ca5cd0 |
| R2-REG-3 | medium | confirmed | override decrement silently drops on mv failure | fixed | 7ca5cd0 |
| R2-001 | medium | confirmed | PACKAGE_SCOPE direct interpolation in jq reads | fixed | 7ca5cd0 |
| R2-002 | medium | confirmed | is_full_mode() accepts any non-null intensity | fixed | 7ca5cd0 |
| R2-003 | medium | confirmed | cache writes missing || true in gate | fixed | 7ca5cd0 |
| R2-004 | high | confirmed | 17/26 docs/skills wrong .claude/ prefix | fixed | 7ca5cd0 |
| R2-005 | high | confirmed | docs show wrong spec path | fixed | 7ca5cd0 |
| R2-006 | high | confirmed | README says 1,024 tests (actual 1,518) | fixed | 7ca5cd0 |
| R2-007 | high | confirmed | CONTRIBUTING 10 suites/923 assertions stale | fixed | 7ca5cd0 |
| R2-008 | high | confirmed | No CHANGELOG 3.0.0 entry | fixed | 7ca5cd0 |
| R2-009 | medium | confirmed | README 17 vs 19 health checks | fixed | 7ca5cd0 |
| R2-010 | medium | confirmed | csetup/cspec "low" intensity references | fixed | 7ca5cd0 |
| R2-011 | medium | confirmed | CONTRIBUTING "Full mode only" stale terminology | fixed | 7ca5cd0 |
| R2-012 | high | confirmed | workflow-advance.sh help text missing 3 skills | fixed | 7ca5cd0 |
| R2-013 | high | confirmed | csetup Mature output missing 3 skills | fixed | 7ca5cd0 |
| R2-014 | medium | confirmed | cstatus missing 3 skills | fixed | 7ca5cd0 |
| R2-015 | high | confirmed | PAT-006 documents prohibited model field | fixed | 7ca5cd0 |
| R2-016 | medium | confirmed | statusline 2>/dev/null, fmt_duration guard | fixed | 7ca5cd0 |
| R2-017 | low | confirmed | min_qa_rounds integer validation | fixed | 7ca5cd0 |

### Round 3
| ID | Severity | Tier | Title | Status | Fixed in |
|----|----------|------|-------|--------|----------|
| R3-001 | medium | confirmed | state_file() die propagation in nested substitution | fixed | 58ac8b7 |
| R3-002 | high | confirmed | Stale runtime hooks in .claude/hooks/ | fixed | 58ac8b7 |

Zero findings from Regression Hunter. **Converged.**

### Regression tests added
- R1 override statusline: test-statusline.sh R-011a fixture updated to use .override.remaining_calls
- R1 marketplace path: test-dynamic-rigor.sh R-003 updated to ../correctless
- test-cexplain.sh added to commands.test (15th suite in CI)

### Deferred for human review
- All 26 docs/skills "Lite vs Full" section renaming (systematic terminology change)
- setup heredoc JSON generation with jq -n (install path change)
- Protected branch config field addition (new config schema)

## Recurring Patterns
- **Stale path references after migration**: .claude/ → .correctless/ migration left references in 20+ files. Future migrations should include a grep sweep as part of the migration checklist.
- **Skill registration drift**: 3 skills (cquick, crelease, cexplain) were added without updating 5 registration points. CONTRIBUTING.md checklist now includes ARCHITECTURE.md, AGENT_CONTEXT.md, CHANGELOG.md.
- **"low" intensity ghost**: Retired intensity level persisted in 4 files after the standard/high/critical system was established. All references cleaned.
