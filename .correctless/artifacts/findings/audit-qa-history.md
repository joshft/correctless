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

## Run: 2026-04-05
### Round 1
| ID | Severity | Tier | Title | Status | Fixed in |
|----|----------|------|-------|--------|----------|
| QA-R1-001 | high | confirmed | Numbered fd redirects (1>, 2>) bypass write detection | fixed | 026f31e |
| QA-R1-002 | high | confirmed | workflow-gate.sh bare redirect bypass (regression of QA-003) | fixed | 026f31e |
| QA-R1-003 | high | confirmed | curl/wget/ln missing from sensitive-file-guard | fixed | 026f31e |
| QA-R1-004 | medium | confirmed | statusline COST awk injection via string interpolation | fixed | 026f31e |
| QA-R1-005 | medium | confirmed | Non-JSON stdin causes exit 1 (unbound variable) | fixed | 026f31e |
| QA-R1-006 | medium | confirmed | audit-trail.sh extension list drift from workflow-gate | fixed | 026f31e |
| QA-R1-007 | medium | confirmed | workflow-gate.sh temp files no trap cleanup (3 locations) | fixed | 026f31e |
| QA-R1-008 | medium | confirmed | audit-trail.sh adherence temp file no trap | fixed | 026f31e |
| QA-R1-009 | medium | confirmed | audit trail JSONL grows without bounds | fixed | 026f31e |
| QA-R1-010 | medium | confirmed | TOCTOU override decrement race | deferred | (low impact) |
| QA-R1-011 | low | confirmed | write_state trap references local variable out of scope | fixed | 026f31e |
| QA-R1-012 | low | confirmed | Custom patterns with spaces split into separate tokens | fixed | 026f31e |
| QA-R1-013 | low | probable | CURRENT_TOKENS not validated as numeric | fixed | 026f31e |
| QA-R1-014 | low | confirmed | git rev-parse missing --no-optional-locks | fixed | 026f31e |
| QA-R1-015 | low | confirmed | pkg-cache files not cleaned for non-monorepo | deferred | (minor) |

### Round 2
| ID | Severity | Tier | Title | Status | Fixed in |
|----|----------|------|-------|--------|----------|
| QA-R2-001 | high | confirmed | MultiEdit STUB:TDD bypass via concatenated content | fixed | 76ad68d |
| QA-R2-002 | medium | confirmed | workflow-gate.sh missing variable init before eval | fixed | 76ad68d |
| QA-R2-003 | medium | confirmed | Fail-closed doesn't check Bash command targets | fixed | 76ad68d |
| QA-R2-004 | medium | confirmed | audit-trail classify() missing case normalization | fixed | 76ad68d |
| QA-R2-005 | medium | probable | wget/curl option variants not extracted | fixed | 76ad68d |
| QA-R2-006 | medium | probable | MultiEdit ./ prefix not stripped in classification | fixed | 76ad68d |
| QA-R2-007 | low | confirmed | cmd_reset missing tdd-test-edits.log and coverage-baseline | fixed | 76ad68d |
| QA-R2-008 | low | confirmed | Audit trail truncation temp file no trap | fixed | 76ad68d |
| QA-R2-009 | low | confirmed | pkg-cache temp file no trap | fixed | 76ad68d |
| QA-R2-010 | low | confirmed | coverage-baseline.out not branch-scoped | fixed | 76ad68d |
| QA-R2-011 | low | confirmed | Audit trail truncation drops all on single-line file | fixed | 76ad68d |
| QA-R2-012 | low | probable | override-log.json unbounded growth | fixed | 76ad68d |
| QA-R2-013 | low | confirmed | Redirect regex [0-9]*> false positives on pre-check | deferred | (pre-check only, not blocking) |

### Round 3
| ID | Severity | Tier | Title | Status | Fixed in |
|----|----------|------|-------|--------|----------|
| QA-R3-001 | medium | confirmed | .claude/hooks/ stale copies (all hooks) | fixed | ed74820 |
| QA-R3-002 | medium | confirmed | cmd_diagnose missing case normalization | fixed | ed74820 |
| QA-R3-003 | medium | confirmed | Fail-closed only checks first MultiEdit file | fixed | ed74820 |
| QA-R3-004 | medium | confirmed | Fail-closed basename not case-normalized | fixed | ed74820 |
| QA-R3-005 | low | confirmed | python/python3/node/ruby missing from sensitive-file-guard | fixed | ed74820 |
| QA-R3-006 | low | confirmed | MultiEdit STUB:TDD jq ./ prefix mismatch | fixed | ed74820 |

**Converged.** Round 1: 15 findings → Round 2: 13 → Round 3: 6 (0 HIGH). All fixed except 3 deferred.

### Regression tests added
- R1: curl/wget/ln write detection tests in sensitive-file-guard
- R2: MultiEdit STUB:TDD per-file check
- R3: .claude/hooks/ sync as part of commit workflow

### Deferred for human review
- QA-R1-010: TOCTOU override decrement race — would require flock, low impact
- QA-R1-015: pkg-cache cleanup for non-monorepo — cleanup happens on reset
- QA-R2-013: Redirect regex [0-9]*> false positives — pre-check only, not blocking decisions

## Run: 2026-04-09
### Round 1
| ID | Severity | Tier | Title | Status | Fixed in |
|----|----------|------|-------|--------|----------|
| QA-R1-001 | high | confirmed | Stale hook copies (.claude/hooks/, .correctless/hooks/) — 3rd recurrence | fixed | 9d61920 |
| QA-R1-002 | high | confirmed | workflow-gate.sh bypass via substring match (comment injection) | fixed | 9d61920 |
| QA-R1-003 | high | probable | Shared constraints JSONL schema omits skill field | fixed | 9d61920 |
| QA-R1-004 | medium | probable | Corrupted config silently degrades fail-closed to fail-open | fixed | 9d61920 |
| QA-R1-005 | medium | confirmed | workflow-gate.sh fails open on malformed stdin JSON | fixed | 9d61920 |
| QA-R1-006 | medium | confirmed | audit-trail.sh missing set -f for classify_file | fixed | 9d61920 |
| QA-R1-007 | medium | confirmed | audit-trail.sh HOOK_MATCHER excludes Read/Grep | fixed | 9d61920 |
| QA-R1-008 | medium | confirmed | audit-trail.sh HOOK_MATCHER missing NotebookEdit | fixed | 9d61920 |
| QA-R1-009 | medium | confirmed | setup uses \\s GNU grep extension (AP-001) | fixed | 9d61920 |
| QA-R1-010 | medium | confirmed | test-consolidation.sh uses grep -P (AP-001) | fixed | 9d61920 |
| QA-R1-011 | medium | probable | audit-trail.sh IS_FULL case-sensitive | fixed | 9d61920 |
| QA-R1-012 | medium | probable | update_phase TOCTOU — lock covers only write | fixed | 9d61920 |
| QA-R1-013 | medium | probable | locked_update_state missing EXIT trap | fixed | 9d61920 |
| QA-R1-014 | low | probable | cmd_init spec stub orphaned on write failure | fixed | 9d61920 |
| QA-R1-015 | low | probable | audit-trail.sh empty phase on state corruption | fixed | 9d61920 |
| QA-R1-016 | low | probable | statusline.sh missing jq check | fixed | 9d61920 |
| QA-R1-017 | low | probable | Inconsistent trap quoting | fixed | 9d61920 |
| QA-R1-018 | low | probable | _acquire_state_lock spins on empty lock dir | fixed | 9d61920 |
| QA-R1-019 | low | probable | cmd_verified misleading error on null spec_file | fixed | 9d61920 |

### Round 2
| ID | Severity | Tier | Title | Status | Fixed in |
|----|----------|------|-------|--------|----------|
| QA-R2-001 | high | confirmed | Read events trigger false "modified" warnings (R1 regression) | fixed | 2824387 |
| QA-R2-002 | high | confirmed | Grep tool field mismatch — FILES always empty (R1 regression) | fixed | 2824387 |
| QA-R2-003 | high | confirmed | scripts/lib.sh not overwritten by setup (R1 fix incomplete) | fixed | 2824387 |
| QA-R2-004 | medium | probable | TOCTOU in cmd_qa/cmd_override/cmd_set_intensity/cmd_spec_update | fixed | 2824387 |
| QA-R2-006 | medium | probable | cmd_resolve_drift reports success after failed write | fixed | 2824387 |
| QA-R2-007 | medium | probable | Override log entry silently dropped on corrupt log | fixed | 2824387 |

### Round 3
| ID | Severity | Tier | Title | Status | Fixed in |
|----|----------|------|-------|--------|----------|
| QA-R3-001 | high | confirmed | jq injection via unescaped $reason (R2 regression) | fixed | 6c0d919 |

Zero new findings from Regression Hunter. **Converged.**

### Regression tests added
- R1: Comment-stripping in workflow-gate.sh verified by existing gate tests (86 pass)
- R1: audit-trail HOOK_MATCHER change verified by ci-hook-wiring assertion update
- R3: locked_update_state --arg passthrough verified by manual test with special characters

### Deferred for human review
- QA-R2-005: EXIT trap clobbering in locked_update_state — latent, no current nesting
- QA-R3-002: Override limit TOCTOU — low practical risk, requires architectural change
- QA-R3-003: Grep without explicit path invisible to audit trail — acceptable limitation

## Recurring Patterns
- **Stale path references after migration**: .claude/ → .correctless/ migration left references in 20+ files. Future migrations should include a grep sweep as part of the migration checklist.
- **Skill registration drift**: 3 skills (cquick, crelease, cexplain) were added without updating 5 registration points. CONTRIBUTING.md checklist now includes ARCHITECTURE.md, AGENT_CONTEXT.md, CHANGELOG.md.
- **"low" intensity ghost**: Retired intensity level persisted in 4 files after the standard/high/critical system was established. All references cleaned.
- **Hook allowlist/extension drift**: Write-command lists and extension regexes drift between hooks (workflow-gate, sensitive-file-guard, audit-trail). When adding a command or extension to one hook, grep all hooks for the same pattern. (2026-04-03, 2026-04-05)
- **Case normalization gaps**: Pattern matching in new code paths (fail-closed, classify, diagnose) frequently misses ${var,,} lowercasing that the main code path has. Every path that does case-insensitive matching must normalize. (2026-04-05)
- **.claude/hooks/ stale copies**: sync.sh syncs to correctless/hooks/ but not .claude/hooks/. The installed hooks drift from source. (2026-04-03, 2026-04-05, 2026-04-09). Root cause fixed in 2026-04-09: install_hooks() now always overwrites.
- **HOOK_MATCHER expansion without body update**: Adding tools to HOOK_MATCHER without updating the hook body's tool-specific logic (field extraction, warning exclusions). (2026-04-09)
- **locked_update_state string interpolation**: User-supplied values embedded in jq filter strings via bash interpolation instead of jq --arg. Same class as QA-007 (2026-04-03). Fixed by extending locked_update_state to accept --arg passthrough. (2026-04-09)
- **PRH-003 enforcement fail-open**: Security enforcement function had fail-open fallback. Paired-array cardinality mismatch silently dropped security findings. (2026-04-12)
- **Phase name drift between policy_evaluate and tier2_build_context**: Phase 3 added review-spec and tdd-verify phases but only updated one of the two consumers. (2026-04-12)
- **AP-001 \s/grep -P systemic**: 4th+ recurrence — 49+ occurrences in 5 test files. Needs scanner expansion. (2026-04-12)
- **AP-005 stale counts**: README badge, test count, CONTRIBUTING file count all stale after 16 test files added. (2026-04-12)
- **_has_write_pattern / _extract_bash_targets drift**: Adding write commands to the detection function without matching target extractors creates a false sense of security — command detected but no file targets extracted, so the guard allows it through. (2026-04-12, R5→R6 regression chain)
- **Dead code in security paths**: Functions defined and unit-tested but never called from production code (check_override_retry, review_override_issuance rejected_overrides writer). Tests pass because they test the function in isolation, not through the production call chain. (2026-04-12)
- **Fix-round regressions compound**: R4 introduced 2 regressions (R5), R5 introduced 1 regression (R6). Each fix-round expansion creates a new attack surface that the next round must verify. The _has_write_pattern → _extract_bash_targets drift is the canonical example. (2026-04-12)
- **Error messages as UX**: BLOCKED/die messages are the primary user interface for new users hitting the workflow gate. Cryptic messages ("Expected phase X, current is Y") without recovery guidance cause users to fight the tool instead of working with it. (2026-04-12, UX round)

## Run: 2026-04-12
### Round 1
| ID | Severity | Tier | Title | Status | Fixed in |
|----|----------|------|-------|--------|----------|
| QA-001 | high | confirmed | PRH-003 enforcement fail-open fallback | fixed | adc5235 |
| QA-002 | high | confirmed | policy_evaluate misses review-spec phase | fixed | adc5235 |
| QA-003 | high | confirmed | check_hard_limits categories not in drx_validate | fixed | adc5235 |
| QA-004 | high | confirmed | enforce_prh003 array length mismatch drops findings | fixed | adc5235 |
| QA-005 | medium | confirmed | Git worktree leaked in base_commit_crosscheck | fixed | adc5235 |
| QA-006 | medium | confirmed | rejected_overrides never written (PRH-006 dead) | fixed | adc5235 |
| QA-007 | medium | confirmed | check_spec_completeness fail-open on malformed JSON | fixed | adc5235 |
| QA-008 | medium | confirmed | build_mandate_context _current_category leak | fixed | adc5235 |
| QA-009 | medium | confirmed | ws_set/increment_field missing EXIT trap | fixed | adc5235 |
| QA-010 | medium | confirmed | build_mandate_context awk leaks S-prefixed sections | fixed | adc5235 |
| QA-014 | medium | probable | base_commit_crosscheck timeout = disconfirmed | fixed | adc5235 |
| QA-015 | medium | probable | cauto-lock TOCTOU (file-based) | fixed | adc5235 |
| QA-017 | medium | probable | override_log unbounded growth | fixed | adc5235 |
| QA-018 | medium | confirmed | tier2_build_context temp file no trap | fixed | adc5235 |
| QA-019 | medium | confirmed | REGRESSION: grep -P in test-bugfixes.sh (AP-001) | fixed | adc5235 |
| QA-020 | medium | confirmed | REGRESSION: \s in 4 test files (AP-001) | fixed | adc5235 |
| QA-021 | medium | confirmed | REGRESSION: README badge 26→27 skills (AP-005) | fixed | adc5235 |
| QA-022 | medium | confirmed | REGRESSION: README ~3,060→~3,900 tests (AP-005) | fixed | adc5235 |
| QA-023 | medium | confirmed | REGRESSION: CONTRIBUTING 32→48 files (AP-005) | fixed | adc5235 |
| QA-024 | low | confirmed | cmd_reset missing new artifact cleanup | fixed | adc5235 |
| QA-025 | low | confirmed | budget_check awk interpolation | fixed | adc5235 |
| QA-026 | low | confirmed | build_override_action_payload silent on bad JSON | fixed | adc5235 |

### Round 2
| ID | Severity | Tier | Title | Status | Fixed in |
|----|----------|------|-------|--------|----------|
| R2-001 | high | confirmed | R1 regression: lock_check_stale misses .d dir | fixed | 5aa376d |
| R2-002 | high | confirmed | R1 regression: enforce_prh003 hard_stops all missing | fixed | 5aa376d |
| R2-003 | high | confirmed | R1 incomplete: infrastructure failures still false | fixed | 5aa376d |
| R2-004 | high | confirmed | budget_check division by zero on max_tokens=0 | fixed | 5aa376d |
| R2-005 | medium | confirmed | triage fail-closed double-failure passes raw data | fixed | 5aa376d |
| R2-006 | medium | confirmed | trap quoting uses single-quotes not printf %q | fixed | 5aa376d |
| R2-007 | medium | confirmed | build_mandate_context silent empty output | fixed | 5aa376d |
| R2-008 | low | confirmed | ws_increment_field type inconsistency (number/string) | fixed | 5aa376d |
| R2-009 | low | probable | rejected_overrides unbounded growth | fixed | 5aa376d |
| R2-010 | low | confirmed | dd_entries_since validates JSON not array type | fixed | 5aa376d |

### Round 3
| ID | Severity | Tier | Title | Status | Fixed in |
|----|----------|------|-------|--------|----------|
| R3-001 | medium | confirmed | Supervisor prompt missing null claim_verified doc | fixed | 3430408 |
| R3-002 | medium | probable | Auto-accept missing decisions lacks reasoning | fixed | 3430408 |
| R3-004 | low | confirmed | build_mandate_context fallback masks root cause | fixed | 3430408 |

Zero HIGH findings in Round 3. **Converged (R1-R3).**

Audit reopened for R4-R7 with new specialist lenses.

### Round 4 (new lenses: shell portability, security enforcement, doc-code consistency, test blind spots)
| ID | Severity | Tier | Title | Status | Fixed in |
|----|----------|------|-------|--------|----------|
| R4-S1 | critical | confirmed | check_override_retry never called from cmd_override — PRH-006 dead | fixed | 61db087 |
| R4-S2 | high | confirmed | git write commands bypass both hooks — not in _has_write_pattern | fixed | 61db087 |
| R4-S3 | high | confirmed | workflow-config.json unprotected between workflows | fixed | 61db087 |
| R4-S4 | high | confirmed | review_override_issuance skips intent hash verification | fixed | 61db087 |
| R4-S5 | high | confirmed | Override window allows writes to state/config files | fixed | 61db087 |
| R4-D1 | high | confirmed | CONTRIBUTING.md says bash 3.2, codebase requires 4+ | fixed | 61db087 |
| R4-D2 | medium | confirmed | CONTRIBUTING.md hook style contradicts PAT-005 | fixed | 3e4e27b |
| R4-D3 | medium | confirmed | README/CONTRIBUTING/AGENT_CONTEXT test counts wrong | fixed | 61db087 |
| R4-D4 | medium | confirmed | AGENT_CONTEXT.md missing 2 hooks | fixed | 61db087 |
| R4-D5 | medium | confirmed | README missing /cauto from skills table | deferred | (content) |
| R4-D6 | low | confirmed | README "4 enforcement hooks" stale | fixed | 61db087 |
| R4-D7 | medium | confirmed | CONTRIBUTING.md test command lists 18 of 48 suites | fixed | 3e4e27b |
| R4-P1 | medium | confirmed | sha256sum without fallback in 2 test files | deferred | (portability) |
| R4-P2 | medium | confirmed | md5sum without fallback in test-statusline.sh | fixed | 61db087 |

### Round 5 (regression check on R4 fixes + security deep sweep)
| ID | Severity | Tier | Title | Status | Fixed in |
|----|----------|------|-------|--------|----------|
| R5-001 | critical | confirmed | R4 regression: sensitive-file-guard blocks /csetup from writing workflow-config.json | fixed | 9f233b6 |
| R5-002 | high | confirmed | R4 regression: review_override_issuance missing fail-closed for absent intent file | fixed | 9f233b6 |
| R5-003 | critical | confirmed | _has_write_pattern misses tar, unzip, touch, scp, chmod + 5 git subcommands | fixed | 774f83c |

### Round 6 (regression check on R5 write pattern expansion)
| ID | Severity | Tier | Title | Status | Fixed in |
|----|----------|------|-------|--------|----------|
| R6-001 | critical | confirmed | R5 regression: 12 new write commands have no target extractors in sensitive-file-guard | fixed | 506fa66 |

### Round 7
Zero findings. **Converged (R4-R7).**

### UX Round (new user experience: fresh project, existing codebase, error messages)
| ID | Severity | Tier | Title | Status | Fixed in |
|----|----------|------|-------|--------|----------|
| UX-F01 | high | confirmed | Standard Workflow Guide link points to non-existent GitHub Pages site | fixed | 3e4e27b |
| UX-F02 | high | confirmed | marketplace.json says 26 skills, actual 27 | fixed | 3e4e27b |
| UX-F03 | medium | confirmed | Root AGENT_CONTEXT.md stale counts (21 tests, 26 skills) | fixed | 3e4e27b |
| UX-F04 | medium | confirmed | Prerequisites (jq, bash 4+) not in README Requirements | fixed | 3e4e27b |
| UX-F05 | medium | confirmed | No "opt-in per feature" statement in README | fixed | 3e4e27b |
| UX-F06 | medium | confirmed | No CI interaction guidance in README | fixed | 3e4e27b |
| UX-F07 | medium | confirmed | No post-merge guidance in README | fixed | 3e4e27b |
| UX-F08 | medium | confirmed | csetup doc claims "doesn't modify source code" | fixed | 3e4e27b |
| UX-E01 | high | confirmed | require_phase errors lack actionable guidance | fixed | 3e4e27b |
| UX-E02 | medium | confirmed | Setup continues silently without jq | fixed | 3e4e27b |
| UX-E03 | medium | confirmed | sensitive-file-guard block lacks recovery guidance | fixed | 3e4e27b |
| UX-E04 | medium | confirmed | fail-closed BLOCKED doesn't name blocked file or diagnose cmd | fixed | 3e4e27b |
| UX-E05 | medium | confirmed | Corrupt state message gives dead-end recovery path | fixed | 3e4e27b |
| UX-E06 | medium | confirmed | Main branch error doesn't mention /cquick | fixed | 3e4e27b |
| UX-E07 | low | confirmed | Override Jaccard message uses jargon | fixed | 3e4e27b |
| UX-E08 | low | confirmed | No bash version check in setup | fixed | 3e4e27b |
| UX-E09 | low | confirmed | Setup not-in-git-repo silently uses pwd | fixed | 3e4e27b |
| UX-E10 | low | confirmed | Setup "then run" syntax error in message | fixed | 3e4e27b |
| UX-X01 | high | confirmed | No uninstall instructions anywhere | fixed | 3e4e27b |
| UX-X02 | high | confirmed | No file manifest of what setup creates | deferred | (feature) |
| UX-X03 | high | confirmed | scripts/ namespace collision with user projects | deferred | (architectural) |

### Deferred (all rounds)
- QA-011: setup detect_config heredoc JSON injection (deferred since 2026-04-03)
- QA-016: Adherence state unlocked read-modify-write (deferred since 2026-04-05)
- R4 test blind spots (TB-001 through TB-014): 14 findings about stub-only test coverage for Phase 3 functions — need functional tests with non-default supervisor stubs
- R4 security: python3 -c interpreter bypass, symlink resolution, policy hash at override, CORRECTLESS_TRIAGE_FN env var — architectural decisions needed
- R4 portability: timeout macOS wrapper, sha256sum test fallback
- UX deferred: scripts/ relocation, tutorial, FAQ, team guide, file manifest, JS/TS detection, /cauto docs, test_new docs, before/after comparison

## Run: 2026-05-09
### Round 1
| ID | Severity | Tier | Title | Status | Fixed in |
|----|----------|------|-------|--------|----------|
| QA-R1-001 | high | confirmed | auto-policy.json template missing from sync.sh distribution | fixed | audit branch |
| QA-R1-002 | high | confirmed | Root AGENT_CONTEXT.md and ARCHITECTURE.md stale counts (28 skills/59 tests) | fixed | audit branch |
| QA-R1-003 | medium | confirmed | update_phase() uses jq string interpolation instead of --arg (AP-010) | fixed | audit branch |
| QA-R1-004 | low | confirmed | error_json() in compute-session-cost.sh uses raw string interpolation | fixed | audit branch |

### Round 2
Zero findings. **Converged (R1-R2).**

Scope: full (20+ PRs since last QA audit 2026-04-12). 6 specialist lenses.

### Recurring Patterns
- **AP-024 (hardcoded file list)**: auto-policy.json added to templates/ but never added to the hardcoded template list in sync.sh. Same class as QA-006 (2026-04-03: spec templates missing from distribution). The template sync loop should use a glob instead of an enumerated list.
- **AP-005 (stale counts)**: Root AGENT_CONTEXT.md and ARCHITECTURE.md counts stale again (28→29 skills, 59→78 tests). 5th recurrence across 4 audit runs. Canonical .correctless/ copies were correct; root copies were not updated. The "stale copy" banner helps but doesn't prevent the drift.
- **AP-010 (jq string interpolation)**: update_phase() used $new_phase directly in jq filter string. Same class as QA-R3-001 (2026-04-09). All callers pass hardcoded values so no exploitation path, but inconsistent with the --arg pattern used elsewhere in the same file.
