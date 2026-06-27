# Changelog

All notable changes to Correctless are documented here.

## [Unreleased]

## [3.1.1] - 2026-06-27

### Fixed
- Corrected the plugin description's skill count in `marketplace.json` (32 → 33).

## [3.1.0] - 2026-06-27

### Changed — Security posture (DOWNGRADE)
- **sensitive-file-guard reduced to the Edit/Write tool-path only — Bash writes are no longer guarded (security downgrade, not a simplification)** — `hooks/sensitive-file-guard.sh` no longer inspects ANY Bash command. The entire Bash write-target detection path was deleted; for `tool_name == "Bash"` the hook now fast-paths `exit 0` before reading any config. **SFG no longer guards ANY Bash write to a protected file** — a direct `echo x > .env`, `tee .env`, `cp x .env`, `sed -i … .env`, an interpreter write (`bash -c '… > .env'`), or a git restore (`git checkout -- .env`) is **allowed**. The guard now catches ONLY the agent's naive Edit/Write tool call (`Edit`/`Write`/`MultiEdit`/`NotebookEdit`/`CreateFile` against `tool_input.file_path`). This is a deliberate, documented security **downgrade**: per PMB-020/AP-040, a cooperative-loop PreToolUse hook is a guardrail/speedbump, the Bash-redirect leg was always trivially evadable via an interpreter, and removing it eliminates ~550 lines of fragile extraction code and its false-positive friction. **Files whose only structural Bash leg this removes (no `cmd_*` content gate behind them): `.correctless/meta/harness-fingerprint.json`, `.correctless/meta/model-baselines.json`, `.correctless/preferences.md`** (plus the wider non-`cmd_*`-gated DEFAULTS set — see ABS-045 Security Residual). **Existing-user note: your `custom_patterns` continue to guard the Edit/Write tool-path; they no longer guard Bash redirects/writer commands.** The protected-file DEFAULTS/`custom_patterns` list is unchanged. See `.correctless/specs/sfg-edit-write-only.md` and ABS-045.

### Added — Skills
- `/cauto` — Semi-auto pipeline orchestrator: runs /ctdd through PR creation with flexible phase resume, tiered decision architecture, and spec-to-PR orchestration
- `/carchitect` — Structured architecture definition: reverse-engineer from existing code or greenfield directed discovery, produces machine-referenceable entrypoints YAML

### Changed — Simplification
- **Intensity calibration** — Removed dead active/hybrid calibration modes and 200K token auto-raise threshold from `/cspec`. Calibration is now always advisory: historical data displayed as read-only context for the human, no automated intensity decisions. Data collection by `/cverify` unchanged. Net -238 LOC

### Changed — Agent Migration
- `/cspec` — Migrated inline research agent prompt to dedicated `agents/cspec-research.md` plugin agent file (M-4). First network-read class agent (WebSearch, WebFetch, Read, Grep). Adds TB-007 (external web content ingestion trust boundary), untrusted data treatment, and network unavailability self-diagnostic. Resolves AP-013 for /cspec
- `/ctdd` — Migrated inline RED and GREEN phase agent prompts to dedicated `agents/ctdd-red.md` and `agents/ctdd-green.md` plugin agent files (M-1, M-2). Agents now have tool pinning and namespaced dispatch. Resolves AP-013 for /ctdd
- `/creview-spec` — Migrated 6 inline adversarial agent prompts to dedicated `agents/*.md` plugin agent files (M-3). Agents now have tool pinning (Read/Grep/Glob only), harness-prior suppression, and namespaced dispatch. Resolves AP-013 for /creview-spec

## [3.0.0] - 2026-04-04

### Changed — Single Distribution with Dynamic Rigor
- Merged Lite and Full distributions into a single 27-skill plugin
- Retired "Lite mode" / "Full mode" terminology in favor of intensity levels (standard, high, critical)
- Intensity gates control which features activate — standard (~10-15 min/feature), high/critical (~1-2 hr/feature)
- Per-feature intensity override via `workflow-advance.sh set-intensity`

### Added — Skills
- `/cquick` — Lightweight TDD without full spec ceremony
- `/crelease` — Versioning, changelog management, and release workflow
- `/cexplain` — Guided codebase exploration with structured question flow

### Added — Dynamic Rigor System
- Intensity detection from spec signals (STRIDE, invariants, compliance keywords)
- Per-feature intensity stored in workflow state, computed as `max(project, feature)` (PAT-005)
- Intensity Configuration tables in all 6 pipeline skills (cspec, creview, ctdd, cverify, cdocs, cstatus)
- Verbatim Effective Intensity section (R-022) across all pipeline skills

### Added — Infrastructure
- 32 test files with ~2,000 assertions (up from 57 in v2.0.0)
- Calm reset prompts in /ctdd and /caudit orchestrators
- Spec template files (spec-lite.md, spec-full.md) for intensity-aware spec generation

### Added — Security Hardening
- Hacker Olympics audit: 22 findings fixed (gate bypass, config protection, CI pinning)
- CODEOWNERS for security-sensitive files (workflow config, CI, pre-commit)
- Pre-commit hooks pinned to commit SHAs (not mutable tags)
- Gitleaks baseline for secret scanning

### Added — Performance
- Performance Olympics audit: 37 findings fixed across 3 convergence rounds
- Hook subprocess spawns reduced from ~18-19 to ~5-6 per invocation (~30-72s saved per session)
- Bulk eval+jq parsing, bash builtin replacements, batched I/O operations

### Fixed
- QA Olympics audit: 24 findings fixed across hooks, gate, statusline, and documentation
- Gate phase enforcement for project source files (pattern delimiter fix)
- Override statusline display (correct state field path)
- Atomic state writes (single write_state per command, trap cleanup for temp files)
- Stale .claude/ path references in skill docs
- Marketplace source path resolution

## [2.0.0] - 2026-03-31

### Added — Skills (23 at v2.0.0: 16 standard-intensity, 7 high+-intensity only)

**Core Workflow (Lite)**
- `/csetup` — Project health check with 17 checks, convention mining, existing project discovery
- `/cspec` — Feature spec with testable rules, research subagent, Socratic brainstorm
- `/creview` — Skeptical review with OWASP security checklist (18 check categories)
- `/ctdd` — Enforced TDD with agent separation (RED/GREEN/QA), test audit, /simplify integration
- `/cverify` — Post-implementation verification with rule coverage, drift detection
- `/cdocs` — Documentation updates from verification report

**Code Quality**
- `/crefactor` — Structured refactoring with characterization tests and behavioral equivalence enforcement
- `/cdebug` — 6-phase bug investigation with git bisect and escalation after 3 failures
- `/cpr-review` — Multi-lens PR review with auto dep-bump detection

**Open Source**
- `/ccontribute` — Learn project conventions first, match patterns, pre-flight checks, generate PR
- `/cmaintain` — Maintainer review with scope check, maintenance burden assessment, pre-written comments

**Observability**
- `/cstatus` — Workflow status with stale detection, empty docs warning, override abuse tracking
- `/chelp` — Quick reference with mode-aware command listing
- `/csummary` — Per-feature "what the workflow caught" report
- `/cmetrics` — Token ROI, session analytics from Claude Code data, Correctless vs Freeform comparison
- `/cwtf` — Workflow accountability: did agents follow instructions? THOROUGH/ADEQUATE/INCOMPLETE/SHORTCUT verdict

**Full Mode Only**
- `/cmodel` — Alloy formal modeling
- `/creview-spec` — 4-agent adversarial spec review
- `/caudit` — Olympics convergence audit (QA/Hacker/Performance presets)
- `/cupdate-arch` — Maintain ARCHITECTURE.md
- `/cpostmortem` — Post-merge bug analysis with class fixes
- `/cdevadv` — Devil's advocate (theme/signals/layers modes)
- `/credteam` — Live red team assessment with isolation verification

### Added — Platform Integration
- **Statusline** — Live workflow phase, cost, context %, lines delta
- **PostToolUse audit trail** — Records every file modification with phase context
- **Real-time adherence feedback** — Phase violation alerts (Lite) + coverage tracking (Full)
- **Session analytics** — Reads Claude Code session-meta + facets for exact tokens and outcome rates
- **CLAUDE.md compounding learning** — Postmortem, convention, and audit learnings auto-appended
- **Git trailers** (opt-in) — Spec, Rules-covered, Verified-by in commit messages
- **Git notes** (opt-in) — Verification summary on commits
- **Git bisect** in /cdebug — Automated regression finding
- **Token tracking** — 12 subagent-spawning skills log per-agent token usage
- **Checkpoint resume** — 4 long-running skills resume after context compaction

### Added — Infrastructure
- **Monorepo support** — Per-package config, longest-prefix-match resolution, cached
- **Compliance hooks** — Custom check scripts at spec/review/verify phases
- **Output redaction** — Paths, credentials, hostnames sanitized for external-facing skills
- **Evidence-before-claims** — ctdd/cverify/crefactor must run commands, not assume results
- **No-auto-invoke** — Skills tell human what comes next, never auto-start the next skill
- **Context enforcement** — 70% warn, 85% stop for long-running skills
- **Defense in depth** — Gate (bash, blocking) → audit trail (bash, observing) → skill instructions (prompt, advisory)

### Added — Documentation
- 23 per-skill documentation pages with examples, reads/writes tables, common issues
- README rewritten with categorized skill tables and Platform Integration section
- SECURITY.md with vulnerability reporting process
- CONTRIBUTING.md with skill creation guide
- Glossary with 12 terms

### Infrastructure
- 4 hooks: workflow-gate.sh, workflow-advance.sh, statusline.sh, audit-trail.sh
- 57 automated tests
- CI with test suite + ShellCheck
- Dependabot for GitHub Actions
- Branch protection on main
- OpenSSF Scorecard badge

## [1.0.0] - 2026-03-29

Initial release. 10 Lite skills, 17 Full skills, setup script, state machine, workflow gate.
