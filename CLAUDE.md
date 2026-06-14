
## Correctless

This project uses Correctless for structured development.
Read .correctless/AGENT_CONTEXT.md before starting any work.
Do NOT Read AGENT_CONTEXT.md from the project root — it may be stale or absent.
Available commands: /csetup, /cspec, /creview, /cmodel, /creview-spec, /ctdd, /cverify, /caudit, /cupdate-arch, /cdocs, /cpostmortem, /cdevadv, /credteam, /crefactor, /cpr-review, /ccontribute, /cmaintain, /cstatus, /csummary, /cmetrics, /cdebug, /chelp, /cwtf, /cquick, /crelease, /cexplain, /cauto, /carchitect, /cmodelupgrade, /cdashboard, /ctriage, /cprune

## GitHub Operations

Use `gh` for GitHub operations (PRs, issues, checks).

## Commit Messages

Imperative mood, capitalized, no conventional commits prefix. Explain *why* when non-obvious.
Examples: "Add mermaid diagrams to README for visual comprehension", "Fix shellcheck directive placement — must be before first statement"

## Script Comments

When writing bash scripts, make section headers visually distinct from inline comments.

**For saved scripts** — use banner comments so the human can scan the flow:
```bash
# ============================================
# STEP 1: Backup current state before migration
# ============================================
cp -r src/auth src/auth.bak
git stash

# ============================================
# STEP 2: Run schema migration
# ============================================
cd packages/api && npx prisma migrate deploy

# skip if no pending migrations
if [ $? -eq 0 ]; then
  echo "Migration complete"
fi
```

**For interactive scripts** — use echo prefixes so the terminal output is the summary:
```bash
echo ">>> Step 1: Backup current state before migration"
cp -r src/auth src/auth.bak
git stash

echo ">>> Step 2: Run schema migration"
cd packages/api && npx prisma migrate deploy
```

Banner comments for scripts reviewed as files. Echo prefixes for scripts watched in real time. Inline `#` comments stay normal — only section headers get the visual treatment.

## Post-Merge Routine

After a PR is merged on GitHub, run this sequence to sync local state:

```bash
git checkout main
git fetch --prune
git reset --hard origin/main
git branch -d <merged-branch>        # delete local branch
```

GitHub squash-merges PRs, so the local branch history will diverge from main. `reset --hard origin/main` is safe here because the PR was just merged — origin/main has everything. Do not attempt `git pull --rebase` after a squash merge; it creates conflicts with the pre-squash commits.

## Correctless Learnings

### 2026-04-02 — Convention confirmed: Serena MCP silent fallback
- Observed in 5+ features — treat as established project convention
- Every skill with Serena integration must: (1) check `mcp.serena` config flag, (2) include the standard 6-tool fallback table, (3) state "optimizer, not a dependency", (4) fall back silently (no abort, no retry, no mid-operation warnings), (5) notify once at session end if unavailable
- Source: /cdocs after add-cexplain-skill-for-guided-codebase-exploration

### 2026-04-05 — Convention confirmed: PreToolUse hook structure
- Observed in 3 features (workflow-gate.sh, sensitive-file-guard.sh, auto-format.sh uses PostToolUse variant) — treat as established project convention
- Every PreToolUse hook must: (1) `set -euo pipefail` + `set -f`, (2) check `command -v jq` with fail-closed exit 2, (3) bulk-parse stdin with single `eval` + `jq -r @sh`, (4) fast-path `exit 0` for non-relevant tools BEFORE loading config, (5) exit 0 to allow, exit 2 to block. See `.claude/rules/hooks-pretooluse.md`.
- Source: /cdocs after sensitive-file-protection

### 2026-04-07 — Convention confirmed: PostToolUse hook structure (PAT-005)
- Observed in 3 features (audit-trail.sh, auto-format.sh, token-tracking.sh) — treat as established project convention
- Every PostToolUse hook must: (1) NO `set -euo pipefail` (fail-open, not fail-closed), (2) `command -v jq` with `exit 0` if missing (NOT exit 2), (3) bulk-parse stdin with `eval` + `jq -r @sh`, (4) fast-path `exit 0` for non-relevant tools BEFORE any I/O, (5) guard each operation with `|| exit 0`, (6) ALWAYS exit 0 — advisory, never gating. Contrast with PAT-001 (PreToolUse: fail-closed, exit 2 to block — See `.claude/rules/hooks-pretooluse.md`).
- Source: /cdocs after token-tracking

### 2026-04-05 — Audit pattern: Hook allowlist/extension drift (RESOLVED)
- **Structurally resolved** by feature/hook-sync-enforcement (2026-04-08): `_has_write_pattern()` and `get_target_file()` extracted into scripts/lib.sh (ABS-001). All consuming hooks source the shared functions — drift is structurally impossible.
- Original issue: write-command lists and file extension regexes duplicated across workflow-gate.sh, sensitive-file-guard.sh, and audit-trail.sh. Caught by 3 consecutive audits.
- Source: /caudit qa, resolved by /cdocs after hook-sync-enforcement

### 2026-04-10 — Postmortem: jq 1.7 vs 1.8 operator precedence for `as` bindings
- jq 1.8 silently fixed `(EXPR // 0) + 1 as $count | rest` precedence; jq 1.7 still parses it as `0 + (1 as $count | rest)` and fails at runtime. Local dev (jq 1.8) passes, CI (Ubuntu 24.04, jq 1.7) fails. When writing jq filters, always wrap the expression being bound in explicit parens: `((EXPR OP VAL)) as $var | rest`. See PAT-010 in .correctless/ARCHITECTURE.md and AP-011 in antipatterns.md. Fix: CI matrix across jq versions.
- Source: PMB-001

### 2026-04-10 — Postmortem: Audit fix rounds are untested code
- QA Olympics audit ran 3 rounds where each round introduced at least one regression that the next round had to catch. Fix commits bypass the TDD discipline of the main workflow — they're batched into one commit per round without test suite verification or diff-focused review. The convergence loop works eventually but wastes rounds. Class fix: /caudit must run the full test suite and spawn a fix-diff review agent after each fix round commit, before advancing. See AP-012.
- Source: PMB-002

### 2026-04-10 — Convention introduced: rules-canonical / ARCHITECTURE.md index
- **Provisional convention under measurement.** First dogfood prototype: PAT-001 was migrated from its full-body form in the architecture doc to a path-scoped rule file at `.claude/rules/hooks-pretooluse.md`.
- Post-migration, `.correctless/ARCHITECTURE.md` contains only a 2-line index entry (heading + See-link) for the migrated pattern. The rule body loads into agent context when Claude Code opens `hooks/workflow-gate.sh` or `hooks/sensitive-file-guard.sh`.
- **Why**: duplication invites drift (AP-005 has recurred repeatedly); a single canonical location enforced by a structural drift test (`tests/test-architecture-drift.sh`) makes drift structurally impossible rather than merely unlikely. The migration is also a prevention bet — the rule body is now loaded into editing context for the exact files it governs, which should reduce the persistence window of fail-closed violations observed in the ≥7-PR baseline (QA-R1-004/005).
- **Measurement gate**: this is an experiment, not a settled convention. The gate (MG-001 prevention signal + MG-002 safety-net persistence ceiling) evaluates after 3 hook-touching PRs via `.correctless/meta/pat001-measurement-due.json` and the dormant `/cstatus` check. If the gate fails, execute PRH-002 rollback (restore full PAT-001 body to ARCHITECTURE.md, delete rule file, revert CLAUDE.md/README changes, drop ABS-009/ENV-005/ENV-006, remove this learning entry) — leaving `tests/test-architecture-drift.sh` in place as inert infrastructure for a future retry.
- **Scope discipline**: only PAT-001 was migrated in this feature. PAT-002..PAT-010 remain full-body in ARCHITECTURE.md (PRH-004). New PAT entries default to ARCHITECTURE.md full-body form until the measurement gate passes (see OQ-005 in the spec). Future PAT migrations (PAT-005 is the next candidate) reuse the drift test verbatim under FUTURE-002. The `InstructionsLoaded` hook that would give MG-001 a direct runtime signal is Feature B (FUTURE-001), deferred.
- Source: /cspec after path-scoped-rules-pat001

### 2026-04-11 — Postmortem: Plugin-agent tool allowlist + strict JSON parse gate are load-bearing together
- Observed during VP-001/VP-002 for fix-diff-reviewer-migration. A simulation run of the fix-diff reviewer via `Task(subagent_type="general-purpose")` — same system prompt, same fixtures — produced prose-wrapped JSON on r1 ("Key observations: ... [JSON array]"). A real `/caudit` invocation would have hit `jq -e .` parse failure and triggered PRH-003 fail-closed. The real plugin agent invoked via `Task(subagent_type="correctless:fix-diff-reviewer")` — same system prompt but with tools pinned to `{Read, Grep, Glob}` — produced pure JSON across all three fixture replays.
- **Inference**: INV-017 (`jq -e .` parse gate) and PRH-002 (pinned tool allowlist) are load-bearing *together*, not independently. A reviewer with a broad tool set is more likely to "explain" its findings in prose because the broader tool surface invites more elaborate reasoning patterns; a reviewer with Read/Grep/Glob only stays inside its narrow output contract.
- **Design implication for future plugin agents**: narrow tool allowlist is part of the output-contract enforcement story, not just a security/least-privilege concern. When writing a new plugin agent in `agents/*.md`, the tool pinning is doing two jobs — it limits blast radius AND it shapes the agent's response style toward the pinned contract. Don't broaden the allowlist just for convenience.
- Source: /cdocs after fix-diff-reviewer-migration (evidence in `.correctless/verification/fix-diff-reviewer-migration-replay-simulation.md`)

### 2026-04-21 — Postmortem: Hardcoded file list in setup silently skips new scripts
- Setup installs hooks via glob (correct) but scripts via a hardcoded 2-file list (incorrect). 16 of 18 scripts were never installed on user projects. The list was correct when written (PR #30, only 2 scripts existed) but silently went stale across 5 PRs that added scripts. Silent failure: hooks work (source lib.sh), but features needing other scripts degrade with no error. Class fix: glob all `scripts/*.sh` (matching hook pattern), add structural test verifying installed count matches source count. See AP-024.
- Source: PMB-003

### 2026-04-22 — Postmortem: Skill says "Read the spec artifact" without path discovery
- `/creview-spec` step 2 says "Read the spec artifact" with no path and no `workflow-advance.sh status` call. Works on correctless (conversation context has the path from /cspec). Fails on other projects in fresh sessions — agent hallucinates wrong paths. `/creview` and `/ctdd` both say "path from workflow state" — /creview-spec missed this pattern. Class: skills must discover artifact paths via workflow state, not assume conversation context. See AP-025.
- Source: PMB-004

### 2026-04-26 — Convention confirmed: Structurally-enforced sole-writer for meta files
- Observed in 8 features (auto-mode-phase-2, carchitect-phase0, override-freq-metrics, semi-auto-mode, session-cost-analysis, stale-hook-detection, harness-fingerprint, plus carchitect-phase0-2) — treat as established project convention. Directly mitigates AP-022 (dead-code-in-security-paths).
- Every new spec that introduces a `.correctless/meta/` JSON file or a sensitive `scripts/*.sh` writer must: (1) name the sole writer in an ABS-xxx entry's Invariant, (2) add the file path to `hooks/sensitive-file-guard.sh` protected paths, (3) verify the hook blocks BOTH Edit/Write AND Bash redirects (`>`, `>>`, `tee`) via `_has_write_pattern` from `lib.sh`, (4) include a structural test in `tests/test-sensitive-file-guard.sh` covering both block paths. Advisory "sole writer" claims are not enough — the v1 spec for harness-fingerprint claimed sole-writer but the v2 spec hardened it after /creview-spec round 2 caught the AP-022 pattern.
- Source: /cdocs after harness-fingerprint

### 2026-04-28 — Postmortem: Enumeration-based extractors are class-incomplete by construction
- Concrete instance of the "Audit fix rounds are untested code" lesson (2026-04-10 / PMB-002). The R2 audit of harness-fingerprint R1 had a 71% defect rate because each R1 patch was instance-level: "this command leaks → add `cp)` branch", "this redirect bypasses → handle `>>`", "this interpreter chain skips → add `bash -c)` branch". Every R2 round routed around the previous patch by finding a missing branch.
- Class fix shipped in R2 hardening (PR #86): `_extract_bash_targets` deletes the per-command dispatch entirely. Default branch over-extracts every non-flag token; the canonical-form matcher filters. PRH-002 enumerates 28 disallowed tokens as a structural ban list — adding any per-command `case` branch in a future PR fails the structural test. Path normalization via `canonicalize_path` (PAT-017) closes the canonicalization-mismatch class (`subdir/../.env` vs `.env`). Unicode-lookalike traversal closed via INV-002a (ASCII-only `.` recognition).
- Generalization for future security extractors: when an extractor's job is "find the dangerous thing", the safe default is to over-extract candidates and let a canonical-form matcher reject false positives — never enumerate the dangerous thing. The enumeration is what makes the extractor class-incomplete.
- Source: /cdocs after harness-fingerprint-r2-hardening

### 2026-04-27 — Postmortem: /caudit findings persistence is advisory prose, not gate-enforced
- 2026-04-26 hacker R1 ran, produced ~22 findings, fixed them, transitioned to 'done' — but never wrote `audit-hacker-2026-04-26-round-N.json` or appended to `audit-hacker-history.md`. Findings existed only as commit-message prose on the squash-deleted audit branch. /cmetrics derived "16 days stale" from history.md mtime; the audit had run 1 day prior. Same shape as silent-telemetry-failure: the artifact-write step looks completed in the orchestrator's mental model but isn't tool-enforced.
- Root cause: /caudit's "After Convergence" persistence step is prose. `cmd_audit_done` in `workflow-advance.sh` transitions phase to 'done' with zero precondition that any artifact for the current run exists. /cmetrics consumer derives staleness from a single mtime with no cross-check.
- Class fix shipped 2026-04-30 by feature/audit-findings-persistence-contract: ABS-029 (sole-writer contract), `scripts/audit-record.sh` (PAT-003 phase-transition CLI), `cmd_audit_done` content-based gate (string equality on `started_at` — robust to ENV-003 mtime drift), `/cmetrics` two-signal `max(history.md mtime, latest round-JSON mtime)` with explicit "no data" label, sensitive-file-guard protection of the writer script (AP-022 mitigation), audit-done-specific override counter (AP-023 routine-bypass detection). 22 rules, 43 tests, 0 BLOCKING findings outstanding. Two-signal cap (history + round-JSON, not three including PMB references) per Q3 brainstorm: PMB references are sparse, max-of-two satisfies multi-signal, third signal is defensive bloat.
- Generalization: any artifact whose absence silently corrupts a downstream consumer must have its persistence enforced at a phase-transition gate — never described only in skill prose. The `cmd_*` phase-transition CLI in `workflow-advance.sh` is the natural enforcement point.
- Source: PMB-005

### 2026-04-30 — Convention introduced: gate-enforced phase-transition artifact contract
- First instance: ABS-029 (audit findings persistence contract, 2026-04-30). Generalizes the AP-026 / PMB-005 / silent-telemetry-failure class.
- Every new spec that introduces a sole-writer artifact whose absence silently corrupts a downstream consumer must: (1) name the artifact paths and writer in an ABS-xxx Invariant, (2) gate-enforce existence at the phase-transition CLI command (`cmd_*` in `hooks/workflow-advance.sh`) — refuse the transition with a clear remediation message naming the missing path, (3) match content-based, not mtime-based — string equality on a stable identity field (e.g., `started_at`), robust to ENV-003 git-op timestamp drift, (4) cover the gate with structural AND behavioral tests, (5) cross-check at least two independent freshness signals in every consumer (`max(...)` of mtimes; explicit "no data" label when both absent). The advisory "the skill writes the file" claim is not enough — silent omission has now manifested 3 times (token tracking 2026-04-14, AP-022 dead-code-in-security-paths 2026-04-26, /caudit findings 2026-04-26). Future ABS entries with sole-writer + downstream-consumer shape should default to this 5-step pattern.
- Source: /cdocs after audit-findings-persistence-contract

### 2026-05-04 — Postmortem: context: fork incompatible with multi-turn skills (PMB-006)
- Skills with `context: fork` in SKILL.md frontmatter run as sub-agents. Sub-agents complete after producing output — the user's follow-up response routes to the main conversation, not back to the fork. Skills that present proposals and wait for user approval (`/cdocs`, `/cupdate-arch`, `/carchitect` and 9 others) never receive the approval, so the write phase never executes. Discovered on overcorrect project (new machine, 2026-05-04) after working on the old machine for weeks — likely a Claude Code version change in fork lifecycle semantics.
- Root cause: `context: fork` was added to pipeline sub-skills in PR #45 (semi-auto mode) for `/cauto` pipeline isolation. But `/cauto` spawns sub-skills via Task (which provides its own fresh context), making the SKILL.md `context: fork` redundant for the pipeline use case and harmful for direct user invocation. No spec/review/QA phase tests interaction-model compatibility with dispatch mechanism.
- Class fix: removed `context: fork` from all 12 multi-turn forked skills; kept it on 4 single-turn skills (cdevadv, cpostmortem, credteam, cverify). Added AP-027 (fork-declared multi-turn skill). Structural test PRE-002 now asserts multi-turn skills do NOT have fork. Rule: `context: fork` is only safe for skills that run to completion without user input.
- Source: PMB-006, GitHub issue #90

### 2026-05-05 — Postmortem: Uncalibrated severity gate makes fix-round loop dead code (PMB-007)
- The QA agent and mini-audit agents in `/ctdd` defined severity levels but provided no calibration examples or boundary definitions. Across 5 features on an external project, agents rated all 15 findings as NON-BLOCKING or MEDIUM/LOW — including silent data corruption bugs. The fix-round loop never triggered. The severity gate was dead code because agents defaulted to the least-friction rating with no calibration pressure toward BLOCKING/CRITICAL.
- Root cause: severity levels were defined as abstract labels ("issues that must be fixed") without concrete examples of what belongs in each level. LLM agents under context pressure default to the rating that ends the conversation fastest (NON-BLOCKING/LOW), not the rating that catches bugs.
- Class fix: (1) concrete calibration examples for each severity level in QA and mini-audit prompts, (2) aggressive-default directive ("when in doubt, rate BLOCKING/HIGH"), (3) secondary keyword-based severity floor check (tripwire, not primary fix), (4) `fix_rounds_triggered` tracking in intensity-calibration.json with `/cmetrics` warning when 0 across 3+ high+ features (AP-028).
- Source: PMB-007, GitHub issue #93

### 2026-05-05 — Postmortem: Skill findings lost when not persisted before presenting (PMB-008)
- `/creview-spec` spawned 5 adversarial agents, synthesized 7 findings, presented them inline — findings disappeared from the terminal before the user could read them. No artifact file was written. Re-running the review cost ~$5-10 in tokens. Prior successful persistence (`review-spec-findings-harness-fingerprint-r2-hardening.md`) was ad-hoc, not structural. Audit found 2 of 13 finding-producing skills had the gap: `/creview-spec` and `/creview`. The other 11 already persist before presenting.
- Root cause: conversation output is ephemeral — long outputs scroll away, context compaction clears them, terminal rendering can displace them. Skills that only present findings inline have no recovery path when the display fails. No spec ever required persist-before-present as a structural contract for review skills.
- Class fix: (1) `/creview-spec` must write to `.correctless/artifacts/review-spec-findings-{slug}.md` before presenting, (2) `/creview` must write to `.correctless/artifacts/review-findings-{slug}.md` before presenting, (3) AP-029 antipattern entry, (4) structural test verifying all finding-producing skills reference an artifact write path.
- Source: PMB-008, GitHub issue #94

### 2026-05-08 — Postmortem: Pipeline orchestrator without completeness verification silently truncates
- `/cauto` pipeline stopped after simplify (2 of 7 steps) when run via the Skill tool's forked execution. The Skill tool reported "completed" — no error, no warning, no truncation artifact. The fork context exhausted its capacity during the long pipeline (ctdd spawns 4+ sub-agents, then simplify). Workflow state showed `done` instead of `documented`. Pipeline is resumable on re-invocation, so no data loss, but silent truncation breaks the "run to completion" assumption.
- Root cause: no spec ever required pipeline completeness verification. The autonomous-skill-contract spec (R-009) models `context: fork` as a SKILL.md frontmatter attribute but never modeled the Skill tool's independent forked execution mechanism. PMB-006 fixed multi-turn fork stalls but didn't address context exhaustion during long single-turn pipelines. `/cauto` writes `skill_started`/`skill_completed` audit entries per step, but only IF the step runs — no upfront manifest, no end-of-pipeline assertion.
- Class fix: two-layer. (1) Pipeline manifest artifact at start with expected_steps + expected_end_phase, updated per step, checked on re-invocation or by `/cstatus`. (2) Post-return phase assertion — after `/cauto` returns, verify workflow state matches expected end state. See AP-030.
- Source: PMB-009, GitHub issue #108

### 2026-05-15 — Convention introduced: Re-derivation backstop for prompt-level write contracts
- First instance: ABS-033 (deferred findings backlog, 2026-05-15). Addresses the prompt-level write drift class from PMB-005 / AP-026 without the overhead of sole-writer + gate-enforcement.
- When a feature introduces a prompt-level write contract (LLM-instructed to write to a file), and the data can be reconstructed from committed artifacts, the spec must include a re-derivation backstop script that reconstructs the file from source-of-truth artifacts. The script serves dual purpose: initial seed on fresh machines and ongoing re-sync when prompt-level writes drift. `/cstatus` detects drift between artifacts and the derived file and suggests running the sync script. This is the lightweight alternative to gate-enforcement (ABS-029 pattern) for advisory data where last-write-wins is acceptable.
- Source: /cdocs after deferred-findings-backlog

### 2026-05-15 — Postmortem: Test fixtures must match real producer output format (PMB-010)
- `sync-deferred-backlog.sh` heading regex `^##[[:space:]]+[A-Z]+-[0-9]+:` expected `## RS-001:` but `/creview-spec` outputs `## Finding RS-001:` (with `Finding` prefix per its SKILL.md template). All 65 tests passed against hand-written fixtures using the wrong format. Script silently imported 0 of 25 pending findings. When a script parses another skill's output, at least one test must use a real artifact from the repo (or verbatim copy) — not a hand-written fixture. The spec should pin the exact format being parsed, cross-referenced against the producer's SKILL.md template. See AP-031.
- Source: PMB-010

### 2026-05-24 — Postmortem: Scanner resolution logic and fixture divergence are distinct bug classes (PMB-011)
- `/cprune` scanner shipped with 4 bugs found on first interactive run. Three are AP-031 instances (test fixtures diverge from real data): (1) INV-003 real-entry fixture used ABS-001 (full-path refs) but TB-001 uses bare basenames — `file_exists("lib.sh")` returns false when the file lives at `scripts/lib.sh`, producing 17 false positives. (2) INV-006 count regex `[0-9]+ script` matches `PAT-003 script` before the actual count — would corrupt AGENT_CONTEXT.md in autonomous mode. (3) INV-014 drift-debt fixtures used bare arrays but real format wraps in `{"drift_debt": [...]}`. Fourth bug is a spec coverage gap: INV-011's class-indicator keyword list (`interpolation|injection|drift|silent|phantom`) missed "persist" for AP-029.
- AP-032 added for the basename resolution class (distinct from AP-031 — extraction was correct, resolution was incomplete). AP-031 frequency updated to 2 features; if it recurs once more, promote to PAT-020. Keyword-based class detection requires coverage validation against the full corpus, not just examples available at design time.
- Source: PMB-011

### 2026-05-06 — Convention confirmed: Structural enforcement over prompt-level instruction
- Observed in 6+ features (auto-mode-phase-2, auto-mode-phase-3, carchitect-phase1, test-evasion-antipatterns, audit-findings-persistence-contract, structural-enforcement-pat) — treat as established project convention
- Every spec invariant at high+ intensity must include an `Enforcement:` field (PAT-018 mechanisms: allowed-tools, sensitive-file-guard, gate preconditions, hash verification, CI test assertions, agent tool-pinning); the Design Contract Checker in `/creview-spec` flags missing or prompt-level-only enforcement
- Source: /cdocs after structural-enforcement-pat

### 2026-06-14 — Postmortem: Semantic spec invariants without implementation-level pinning leak through every phase (PMB-013)
- `prune-scan.sh` shipped with parallel arrays (`stale_workflow_state_files` + `stale_task_slugs`) that diverged across three fail-closed error-paths (L825/L833/L842 reset one alone), causing `unbound variable` at the INV-018 atomic-group consumer (L1146). The spec pinned INV-018 *semantically* ("workflow-state and dependents are atomic") and tested it via three scenarios, but never pinned the *implementation-level* invariant that the two arrays backing the live/stale sets must have identical length at every reset/append site. The bug fell into the gap between 'spec rules' and 'implementation properties needed to satisfy spec rules'. /creview-spec, RED-phase test design, GREEN-phase implementation (fixes spread across F-001, F-002, INV-004a rounds — no diff scope covered all 6 related sites), QA round 1, mini-audit rounds 2+3, and /cverify rule coverage all passed cleanly. Same class shape as AP-033/PMB-012 — advisory-prose antipattern that lived as text for months while the bug class kept landing in code.
- Class fix: (1) `scripts/antipattern-scan.sh check_shell()` gains a `paired-array-no-cardinality` rule detecting 2+ `local -a` arrays with shared name root, appended together, reset in different paths, without a `${#a[@]} -eq ${#b[@]}` consumer assertion. (2) /creview-spec Design Contract Checker flags specs whose invariants describe "parallel arrays", "lockstep", or "atomic group" semantics over array-of-X + array-of-Y without a cardinality enforcement clause. (3) Preferred refactor: single associative array eliminates the bug class structurally at that site. AP-020 frequency updated 1→2; 3rd instance promotes to PAT-xxx.
- Generalization: when a semantic invariant ("X and Y are atomic", "set A equals set B", "outputs are aligned with inputs") is implemented across multiple arrays/maps/data structures maintained at different code sites by different fix rounds, the spec must pin the *implementation-level* cardinality/alignment invariant — not just the semantic outcome. Spec rules whose mental model is "is/should-be" without a "concretely-stays-true-by-construction" enforcement leak through every review and audit lens, because no agent's checklist names the implementation property.
- Source: PMB-013, GitHub issue #160

### 2026-06-14 — Postmortem: Prose-pinned tool surfaces on concurrent adversarial subagents against a shared mutable tree (PMB-014)
- The /ctdd mini-audit phase spawns 6 default lens agents (cross-component, hostile-input, resource-bounds, upgrade-compatibility, ux-review, integration-depth) plus up to 2 custom recommended lenses in parallel against the live working tree containing uncommitted feature work. skills/ctdd/SKILL.md describes the lens tool surface as `Read, Grep, Glob, Bash(git diff*, git log*, git show*)` in prose — but no `agents/mini-audit-*.md` file pins that tool list. Orchestrators spawn the lenses ad hoc or via general-purpose, inheriting the project's broad Bash allowlist. A lens agent ran `git stash` / `git worktree` / `git stash drop` to investigate a baseline, transiently reverting the shared tree. Two sibling lens agents read the half-reverted state and reported spurious "fix missing" findings; the stashing agent had to manually recover the dropped stash to avoid losing uncommitted implementation. The probe round (high+ intensity) had recognized the hazard and uses `isolation: "worktree"` via the Agent tool — the mini-audit round didn't apply the same model.
- Class fix: (1) Pin all 6 default mini-audit lenses to `agents/mini-audit-{lens}.md` with `tools: Read, Grep, Glob` — drop Bash entirely; orchestrator pre-fetches git diffs and passes them as labeled prompt input (the same pattern test-audit uses today). (2) Custom recommended lenses MUST invoke a shared `agents/mini-audit-custom.md` (same pinned tools) rather than ad-hoc general-purpose. (3) Worktree isolation: mini-audit lenses read from a detached worktree pinned to HEAD-of-feature-branch (extending the probe-round pattern) so a stray mutation can't propagate. (4) New AP-034 names the broader class — "shared mutable working tree across parallel adversarial subagents" — distinct from AP-013 (inline prompts): AP-013 is about WHERE the prompt lives, AP-034 is about HOW concurrent agents share substrate. (5) AP-013 frequency updated 4→5 migrations with a new "tool-surface enforcement clause" requiring agent files even for non-output-producing agents. (6) /creview-spec Design Contract Checker addition: prose-only tool-surface claims and concurrent-agents-on-shared-mutable-substrate without isolation invariants are BLOCKING review findings.
- Generalization: when N≥2 subagents run concurrently, the substrate they read MUST be pinned to a read-only snapshot for the round — prose-level read-only-by-intent doesn't survive an LLM's investigative reasoning ("let me check what main looks like" → `git checkout`). Concurrent + shared mutable substrate + read-only-by-prose is structurally racy. Apply isolation as you would for probes, even when the agents only intend to read.
- Source: PMB-014, GitHub issue #157
