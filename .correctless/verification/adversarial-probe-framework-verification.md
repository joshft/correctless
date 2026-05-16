# Verification Report: adversarial-probe-framework

**Date**: 2026-05-16
**Spec**: `.correctless/specs/adversarial-probe-framework.md`
**Branch**: feature/adversarial-probe-framework
**Intensity**: high
**Verdict**: PASS

## Test Results

53 tests passed, 0 failed. Full suite at `tests/test-adversarial-probes.sh`. Full project suite (74 test files) passes with 0 failures.

## Invariant Verification

### INV-001: Probe round intensity gate [PASS]
- High intensity requirement stated (line 561: "High intensity: Only mutation and config-fuzz probe types activate")
- Standard intensity exclusion stated (line 563: "Standard intensity: Probe round MUST NOT run")
- High intensity probe types enumerated: mutation, config-fuzz
- Critical intensity all five types enumerated (lines 561-603)

### INV-002: Worktree isolation [PASS]
- `isolation: "worktree"` keyword present in probe dispatch section (line 585)
- Agent tool specifically referenced as the dispatch mechanism (line 557, 585)
- Explicit statement: "probes MUST NEVER modify the main working tree" (line 585)

### INV-003: Time budget controls probe count [PASS]
- Interactive mode: prompts user for budget in minutes (line 567)
- Autonomous mode: 15 min high, 30 min critical (line 567)
- Formula: `floor(budget_minutes * 60 / duration_estimate)` with `test_duration_estimate` / `test_timeout / 3` / 100s fallback chain (line 569)
- Boundary conditions: 0 probes = skip, 1 probe = warn (lines 572-573)

### INV-004: Mutation probe semantics [PASS]
- "Apply exactly one semantically meaningful modification per worktree" (line 595)
- Mutation types listed: operator swaps, guard removal, boundary condition changes, return value changes (line 595)
- Uses `commands.test` from workflow-config.json in worktree (line 595)

### INV-005: Config/input fuzz probe semantics [PASS]
- Targets input surfaces in changed files (line 597)
- Edge-case types enumerated: empty strings, nulls, extreme numbers, malformed structure, missing fields, unicode edge cases, paths with spaces (line 597)

### INV-006: Critical-only probes gate [PASS]
- All three critical-only probes defined with explicit "Critical only — MUST NOT activate at high intensity" (lines 601-603)
- Dependency sabotage semantics: modify version pins or remove dependencies
- Permission stripping semantics: remove file permissions, env vars, or tool access
- Rollback simulation semantics: revert individual commits from feature branch

### INV-007: Surviving-probe test generation [PASS]
- Test generation for survivors from high-intensity probe types (line 614)
- Agent receives: spec, probe description, target file path (lines 615-617)
- "MUST NOT receive the worktree path or the mutated code" (line 619)
- One attempt, no convergence loop (line 621)
- Critical-only survivors: findings only, no test generation (line 623)
- Interactive mode requires user approval (line 625)
- Autonomous mode auto-commits per TB-004 (line 626)

### INV-008: Probe results artifact [PASS]
- Path: `.correctless/artifacts/probe-results-{branch-slug}.json` (line 632)
- `schema_version: 1` in schema (line 636)
- Incremental writes: "as each probe completes" (line 632)
- Outcome enum: killed/survived/timed_out/error (line 648)
- Summary fields computed at end from probes array (line 662)

### INV-009: Pipeline position and test-gen phase [PASS]
- Probe section positioned between QA completion (line 551) and Mini-Audit heading (line 668) — structurally verified by test
- "internal orchestration — it does NOT trigger a workflow-advance.sh phase transition, does NOT appear in the pipeline manifest expected_steps" (line 555)
- Test-gen commits deferred to tdd-audit phase (line 628)

### INV-010: Parallel probe dispatch [PASS]
- "Dispatch all probes in a single message (parallel)" (line 585)
- Acknowledged untestable (runtime behavioral property)

### INV-011: Probe targets from feature diff [PASS]
- Base branch derived via `git symbolic-ref refs/remotes/origin/HEAD | sed 's|refs/remotes/origin/||'` (line 579)
- "Probe targets MUST be files changed on the current feature branch" (line 581)
- "Probes MUST NOT target files outside the feature's diff scope" (line 581)

### INV-012: Progress visibility [PASS]
- Start: "Spawning N probes in parallel worktrees..." (line 608)
- Per-probe: "Probe 3/8 complete — mutant killed (operator swap in lib.sh:47)" (line 609)
- Summary: "Probe round complete: 6 killed, 2 survived. Generating tests for survivors..." (line 610)

### INV-013: ABS-010 exception [PASS]
- Exception documented in blockquote (line 557)
- Rationale present: "Agent tool required for isolation: worktree which Task does not support" (line 557)

### INV-014: TB-004c allowlist modification [PASS]
- `cauto` Step 8.1 explicit path list includes `.correctless/artifacts/probe-results-{branch-slug}.json` (line 293)
- Step 8.2 excludes probe-results from unstaging: `grep -v 'probe-results'` (line 303)
- TB-004c documented in surrounding context

## Prohibition Verification

### PRH-001: No probe modifications in main working tree [PASS]
- "probes MUST NEVER modify the main working tree" (line 585)
- "exclusively in isolated worktrees" (line 585)
- "The main tree remains untouched after probe completion" (line 585)

### PRH-002: No probe round at standard intensity [PASS]
- "Probe round MUST NOT run" at standard intensity (line 563)
- "Skip directly to workflow-advance.sh audit-mini" (line 563)
- Additional flow guard at line 550: standard intensity skips probe round

### PRH-003: Probe round must not block pipeline on failure [PASS]
- "The probe round is advisory" (line 666)
- "never gates pipeline progression" (line 666)
- Worktree failure: "Report the failure and continue to mini-audit" (line 589)
- Non-Blocking Fallback section (lines 664-666) explicitly handles all failure modes

## Boundary Condition Verification

### BND-001: Empty diff [PASS]
- "No changed files — probe round skipped" (line 587)
- Skip to mini-audit on empty diff

### BND-002: Budget yields zero or one probe [PASS]
- Zero: "Budget too small for even one probe — probe round skipped" (line 572)
- One: "Budget yields 1 probe — consider increasing for statistically useful results" (line 573)

### BND-003: Worktree creation failure [PASS]
- "Worktree creation failed — probe round skipped" (line 589)
- Continue to mini-audit (PRH-003 fallback)

## Additional Checks

### Autonomous Defaults (AD-004/005/006) [PASS]
- AD-004: 15 min high, 30 min critical (line 943)
- AD-005: Probe failure continues to mini-audit (line 944)
- AD-006: Auto-commit per TB-004 (line 945)
- All three in the canonical `## Autonomous Defaults` section

### Distribution Sync [PASS]
- `skills/ctdd/SKILL.md` == `correctless/skills/ctdd/SKILL.md`
- `skills/cauto/SKILL.md` == `correctless/skills/cauto/SKILL.md`

### CI Registration [PASS]
- `tests/test-adversarial-probes.sh` registered in `.github/workflows/ci.yml` (line 135)
- Test file registered in `commands.test` in workflow-config.json

### Pipeline Diagram [PASS]
- Full pipeline string updated: "RED → test audit → GREEN → /simplify → QA → probe round (high+) → mini-audit → done" (line 40)

## Drift Debt

### DRIFT-001: ABS-034 not in ARCHITECTURE.md
- Spec defines ABS-034 (Probe Results Artifact Contract) but it is not yet in `.correctless/ARCHITECTURE.md`
- This is expected — ARCHITECTURE.md updates are handled by `/cupdate-arch` (next pipeline step)
- The spec declares this in its "Files touched" list; implementation defers to `/cupdate-arch`

### DRIFT-002: ENV-010 not in ARCHITECTURE.md
- Spec references ENV-010 (Agent tool worktree isolation contract) as a needed entry
- EA-001 notes "needs ENV-010 entry" — not yet added
- Same disposition as DRIFT-001: deferred to `/cupdate-arch`

## Verdict

**PASS**. All 14 invariants, 3 prohibitions, and 3 boundary conditions are structurally verified in the SKILL.md implementation with passing tests. Distribution copies are in sync. Two architecture documentation updates (ABS-034, ENV-010) are correctly deferred to `/cupdate-arch`.
