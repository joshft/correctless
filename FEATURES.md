# Correctless — Comprehensive Feature Catalog

> Complete inventory of every feature, capability, and component in Correctless.
> Generated from source code, git history (165+ commits), and documentation.

---

## Table of Contents

1. [Core Workflow Skills](#1-core-workflow-skills)
2. [Adversarial & Quality Skills](#2-adversarial--quality-skills)
3. [Architecture & Modeling Skills](#3-architecture--modeling-skills)
4. [Observability & Analytics Skills](#4-observability--analytics-skills)
5. [Utility & Convenience Skills](#5-utility--convenience-skills)
6. [Open Source & Collaboration Skills](#6-open-source--collaboration-skills)
7. [Automation & Orchestration](#7-automation--orchestration)
8. [Hook System](#8-hook-system)
9. [Plugin Agents](#9-plugin-agents)
10. [Script Library](#10-script-library)
11. [Dynamic Rigor System](#11-dynamic-rigor-system)
12. [Security Infrastructure](#12-security-infrastructure)
13. [Developer Experience](#13-developer-experience)
14. [Testing Infrastructure](#14-testing-infrastructure)
15. [Documentation System](#15-documentation-system)
16. [Distribution & Installation](#16-distribution--installation)
17. [CI/CD & Project Health](#17-cicd--project-health)
18. [MCP Integrations](#18-mcp-integrations)
19. [Cross-Cutting Capabilities](#19-cross-cutting-capabilities)

---

## 1. Core Workflow Skills

The primary pipeline that every feature passes through. Each phase is executed by a separate agent to prevent self-confirmation bias.

### `/cspec` — Structured Specification

Creates a structured specification with testable invariants before any code is written. Begins with a Socratic brainstorm to explore the problem space, then researches current best practices via web search before writing rules. Produces a spec artifact (`.correctless/specs/{feature}.md`) containing:

- Numbered rules (R-xxx) with testable acceptance criteria
- Invariants (INV-xxx) — properties that must always hold
- Prohibitions (PRH-xxx) — things the implementation must never do
- Boundary conditions (BND-xxx) — edge case behavior
- STRIDE threat analysis (standard+) or full STRIDE matrix (high+)
- Integration test contracts with Entry/Through/Exit constraints derived from ARCHITECTURE.md entrypoints (when available)

Intensity-aware: standard produces a compact spec; high adds formal invariants and STRIDE; critical adds Alloy model candidates. Triggers harness fingerprinting at Step 0 (records model + harness version for regression detection). Reads cross-skill calibration data from `/cverify` to adjust intensity recommendations based on historical outcomes.

### `/creview` — Skeptical Spec Review

Single-agent adversarial review of a spec. Reads the spec cold (without the author's context) and checks for:

- Unstated assumptions that could break the implementation
- Untestable rules (vague language, unmeasurable criteria)
- Missing edge cases and boundary conditions
- Security gaps (OWASP-informed, 18 check categories)
- Antipattern recurrence (reads `.correctless/antipatterns.md`)
- Historical pattern detection via shift-left review (reads prior QA and audit findings)

Produces a review artifact with BLOCKING/NON-BLOCKING findings. BLOCKING findings must be resolved before advancing to TDD. Includes an upgrade compatibility lens that checks for existing-user impact.

### `/creview-spec` — Multi-Agent Adversarial Spec Review

Spawns four parallel specialist agents for deep spec scrutiny (high+ intensity only):

1. **Red Team** — attack vectors, exploitation paths, adversarial inputs
2. **Assumptions Auditor** — unfounded assumptions, implicit dependencies
3. **Testability Auditor** — edge cases, ambiguous language, unmeasurable criteria
4. **Design Contract Checker** — API/config correctness, contract consistency

Each agent reviews independently and produces findings. Findings are triaged by severity. Includes upgrade compatibility lens and historical pattern matching. Discovers spec artifact paths via workflow state (not conversation context).

### `/ctdd` — Enforced Test-Driven Development

The core implementation skill. Enforces strict TDD through mechanically-gated phases:

**RED Phase** — A separate agent (`ctdd-red`) reads the spec and writes failing tests that encode every rule, invariant, and prohibition. The test writer doesn't know the implementation plan. Reads ARCHITECTURE.md entrypoints to write integration tests through documented entry points (not internal imports). The test audit (check 10) catches internal import bypass violations with language-aware detection for Go, TS/JS, Python, and Rust.

**Test Audit** — Before GREEN begins, an adversarial mini-audit evaluates whether the tests would actually catch bugs. Three lenses: completeness (do tests cover all spec rules?), quality (would tests catch real defects or just pass against mocks?), independence (do tests verify behavior or implementation details?). Integration test contract verification with tiered severity (Entry=mechanical BLOCKING, Through=semi-mechanical, Exit=semantic).

**GREEN Phase** — A different agent implements just enough code to make the tests pass. The PreToolUse hook (`workflow-gate.sh`) blocks source file edits until tests exist — this is enforced by bash, not by prompt.

**QA Phase** — An independent QA agent reads the implementation (not the tests) and hunts for bugs: logic errors, edge cases, off-by-ones, missing guards, broken invariants, wrong operator precedence, feature interactions. Produces a prioritized list (CRITICAL/HIGH/MEDIUM/LOW) with file:line references. Issues found loop back to GREEN.

**Mini-Audit Phase** — Adversarial specialist review (added after the QA Olympics found that QA agents miss certain bug classes). Provides a final check before phase advancement.

Supports `/simplify` integration between GREEN and QA. Manages RED→GREEN→QA loops with calm reset prompts to prevent context exhaustion.

### `/cverify` — Implementation Verification

Post-implementation verification that checks spec-to-code correspondence without insider knowledge:

- **Rule coverage**: every spec rule (R-xxx) mapped to tests and implementation
- **Undocumented dependencies**: new imports/packages not mentioned in spec
- **Architecture compliance**: checks against ARCHITECTURE.md patterns
- **Drift detection**: identifies where implementation deviated from spec

Writes outcome data (QA rounds, BLOCKING findings, actual tokens, actual cost) to `.correctless/meta/intensity-calibration.json` for cross-skill calibration. This data feeds back into `/cspec` to improve future intensity recommendations. Supports mutation testing (mutmut, stryker, cargo-mutants, go-mutesting) and coverage analysis.

### `/cdocs` — Documentation Updates

Updates project documentation after a feature lands:

- `.correctless/AGENT_CONTEXT.md` — component table, design patterns, pitfalls, quick reference
- `.correctless/ARCHITECTURE.md` — trust boundaries, abstractions, patterns, environment assumptions
- `CLAUDE.md` — convention learnings, postmortem citations
- `README.md` — feature descriptions, skill tables
- `docs/features/{feature}.md` — per-feature documentation
- Dev journal entries (`docs/dev-journal.md`) — captures "why" knowledge lost after conversation ends
- Workflow history entries (`docs/workflow-history.md`) — rules, QA rounds, findings, overrides, cost

Invokes `scripts/compute-session-cost.sh` to generate cost artifacts from Claude Code session transcripts. Intensity-aware: standard updates AGENT_CONTEXT + docs; high adds diagrams; critical adds fact-check subagent.

---

## 2. Adversarial & Quality Skills

Skills focused on finding bugs, challenging assumptions, and strengthening the workflow.

### `/caudit` — Olympics Convergence Audit

Cross-codebase quality audit with parallel specialist agents and convergence-based iteration. Three presets:

- **QA** — concurrency bugs, error handling gaps, resource lifecycle issues
- **Hacker** — encoding attacks, protocol abuse, auth/authz weaknesses, config vulnerabilities, injection vectors
- **Performance** — unnecessary allocations, algorithmic complexity, I/O inefficiency, concurrency bottlenecks

Each round spawns 4-6 parallel specialist agents. Findings are triaged, fixes applied, and a fix-diff reviewer agent (`correctless:fix-diff-reviewer`) checks each fix for regressions before the next round begins. Full test suite runs between rounds. Converges when no new CRITICAL/HIGH findings emerge (5-round cap). Writes findings to `.correctless/artifacts/findings/` via `scripts/audit-record.sh` (gate-enforced persistence per ABS-029). Requires high+ intensity.

### `/cdevadv` — Devil's Advocate

10th Man / Devil's Advocate that challenges the assumptions, architecture, and strategies that every other agent accepts as true. Three modes:

- **Theme** — challenge a specific thesis ("our auth model is sound")
- **Signals** — explorer scan + deep-dive on concerning signals
- **Layers** — systematic passes through dependency, architecture, strategy, and code layers

Reads drift debt, audit findings, and antipatterns for context. Produces structured findings with severity and recommended actions. Available at all intensity levels.

### `/cwtf` — Workflow Accountability

Audits the workflow itself. Investigates whether agents actually followed their instructions or took shortcuts. Traces failures back to root cause in agent behavior:

- Phase execution quality (did each agent do its job?)
- Rule coverage (were spec rules actually tested?)
- Agent thoroughness (did QA find real bugs or rubber-stamp?)

Produces a verdict: THOROUGH / ADEQUATE / INCOMPLETE / SHORTCUT.

### `/cpostmortem` — Post-Merge Bug Analysis

When a bug escapes to production, traces which workflow phase missed it and strengthens the workflow:

1. Gather facts (bug description, affected code, timeline)
2. Trace to spec/review/QA gap (which phase should have caught it?)
3. Determine class fix (not just this instance — the entire bug class)
4. Write PMB entry to antipatterns.md
5. Update phase effectiveness data
6. Present corrective actions

Produces PMB-xxx entries that feed back into `/creview` and `/creview-spec` shift-left detection.

### `/credteam` — Live Red Team Assessment

Goal-directed adversarial penetration testing against a running system with source code access. Requires an isolated environment (Docker/VM). Generates test artifacts and spec updates from discovered vulnerabilities. Requires critical+ intensity.

---

## 3. Architecture & Modeling Skills

### `/carchitect` — Structured Architecture Definition

Two modes:

- **Reverse-engineer** — analyzes existing code to produce a structured architecture document
- **Greenfield** — guided discovery for new projects

Produces `.correctless/ARCHITECTURE.md` with:
- Machine-referenceable entrypoints YAML (between marker comments, extracted by `scripts/extract-entrypoints.sh`)
- Trust boundaries, abstractions, patterns, environment assumptions
- Human-readable prose sections

The entrypoints YAML feeds into `/cspec` (integration test contract derivation) and `/ctdd` (entrypoint-aware test writing, internal import bypass detection). Spawns a read-only `correctless:architecture-reviewer` agent for adversarial second-pass review.

### `/cupdate-arch` — Architecture Maintenance

Updates `.correctless/ARCHITECTURE.md` after features land. Applies feature-level deltas to the architecture document, adding new trust boundaries, abstractions, patterns, and environment assumptions as needed. Requires high+ intensity.

### `/cmodel` — Alloy Formal Modeling

Generates Alloy formal models of security-relevant behavior and runs the Alloy Analyzer. For features with state machines, protocol handling, or trust boundary crossings. Auto-retries on Alloy syntax errors. Spawns a separate interpreter subagent for counterexample translation (explaining Alloy output in developer terms). Requires critical+ intensity.

### `/cmodelupgrade` — Harness Regression Report

Compares per-feature metrics (QA rounds, total tokens, total cost, phase count) between the current `{model}+{HARNESS_VERSION}` combination and stored baselines. Three-tier bootstrap: exact-match pool, pre-fingerprint pool, no-baseline fallback. Strictly advisory — never blocks any skill. Helps detect when a model upgrade causes quality regression.

---

## 4. Observability & Analytics Skills

### `/cmetrics` — Project Health Dashboard

Aggregates workflow data across all features into a health and ROI dashboard:

- Escape rate (bugs that bypass the workflow)
- QA round trends (are rounds declining over time?)
- Token cost analysis with real USD from session transcripts
- Override frequency and health (gate misclassification detection)
- Antipattern recurrence tracking
- Audit staleness (multi-signal: history.md mtime + round-JSON mtime)
- Decision record summary
- Override health (mean per run, reason clusters, elevated rate warnings)

Uses two independent freshness signals for audit staleness. Reads session transcripts, token logs, override history, and calibration data.

### `/csummary` — Feature Summary

Generates a "what the workflow caught" report for the current feature. Aggregates findings from all phases (spec review, QA, audit, verification) into a single view. Useful after `/cdocs` to see workflow value, or mid-feature to check progress.

### `/cstatus` — Workflow Status

Real-time view of current workflow state:
- Current phase and next steps
- Stale detection (feature stuck too long in one phase)
- Empty docs warning
- Override abuse tracking
- Harness fingerprint version-bump advisories
- Intensity level display
- ASCII workflow diagrams with current-phase highlighting

### `/chelp` — Quick Reference

Shows the workflow pipeline, all 29 available commands with intensity gates annotated, and current status. Intensity-aware display. Keeps output under 50 lines.

---

## 5. Utility & Convenience Skills

### `/cquick` — Quick Fix with TDD

Lightweight TDD for small, well-understood changes that don't warrant the full spec ceremony. Branch, write a failing test, implement, commit. Fast path for bug fixes and minor enhancements.

### `/cdebug` — Structured Bug Investigation

Six-phase investigation workflow:
1. Reproduce the bug
2. Root cause analysis (code path tracing, git blame, antipattern matching)
3. Automated `git bisect` for regressions (optional)
4. Hypothesis testing (max 3 hypotheses)
5. TDD fix with agent separation
6. Class fix assessment (is this a one-off or a bug class?)

Escalates after 3 failed hypotheses with structured context for human assistance.

### `/crefactor` — Structured Refactoring

Behavioral equivalence enforcement:
- Tests must pass before AND after refactoring
- Any test change requires explicit human approval
- Writes characterization tests for low-coverage code before refactoring
- Updates ARCHITECTURE.md and AGENT_CONTEXT.md

### `/crelease` — Version & Changelog Management

Automates version bumping, changelog generation, and release tagging. Derives version increments and changelog entries from feature specs. Supports semver with language-specific version file detection (package.json, Cargo.toml, pyproject.toml, etc.).

### `/cexplain` — Guided Codebase Exploration

Read-only interactive codebase analysis with:
- Mermaid diagram generation
- Structural signal detection
- Deep-dive walkthroughs with prose
- Confidence markers on analysis claims
- Two output modes: terminal (code blocks) or HTML export

---

## 6. Open Source & Collaboration Skills

### `/ccontribute` — Contribution Workflow

Learns the target project's conventions, patterns, and CI requirements before writing code:
1. Learn project (read CONTRIBUTING.md, analyze recent PRs, study test patterns)
2. Understand the change request
3. Plan implementation (match existing patterns — "match, don't improve")
4. Implement with convention compliance
5. Pre-flight checks (lint, test, format)
6. Generate PR matching maintainer expectations
7. Prepare reviewer context

### `/cmaintain` — Maintainer Review

Maintainer-lens review for incoming PRs (distinct from code review):
- Scope check (does this PR belong in this project?)
- Convention compliance (does it match existing patterns?)
- Quality assessment (tests, docs, error handling)
- Maintenance burden (will this increase ongoing maintenance cost?)
- Security check
- Pre-written review comments for common issues

### `/cpr-review` — Multi-Lens PR Review

Reviews incoming PRs on architecture, security, tests, and antipatterns. Auto-detects dependency bump PRs and switches to a specialized dep-specific review:
- Test verification (do tests still pass?)
- Usage analysis (how is this dependency used?)
- Changelog review
- CVE check
- Breaking changes assessment
- Transitive dependency impact

Supports GitHub CLI (`gh`) and GitLab CLI (`glab`).

---

## 7. Automation & Orchestration

### `/cauto` — Semi-Auto Pipeline Orchestrator

Orchestrates the full implementation pipeline after human-approved spec review. Three phases of increasing autonomy:

**Phase 1 (Semi-Auto)**: Runs `ctdd → simplify → cverify → cupdate-arch → cdocs → consolidation → PR` with human escalation on architectural decisions, persistent failures, or spec contradictions. Flexible phase entry (resumes from any active workflow phase). Scoped commit-and-push consolidation before PR creation. Structured end-of-pipeline summary.

**Phase 2 (Policy-Driven Decisions)**: Tiered decision architecture:
- **Tier 0**: Deterministic policy engine (`scripts/auto-policy.sh`) — same input = same output, SHA-256 hash-verified
- **Tier 1**: Worker self-resolution within domain
- **Tier 2**: Ephemeral decision agents (spawn, decide, terminate — no state)
- **Tier 3**: Lightweight supervisor with configurable mandate levels
- **Tier 4**: Hard stop (budget exceeded, security, intent tampering)

Decision records (DD-xxx) in append-only format with size-regression detection. Intent summary (immutable, SHA-256 verified). Auto Run Report on completion/pause.

**Phase 3 (Spec-to-PR)**: Extends orchestration to include spec writing and autonomous review:
- Supervisor triage of review findings with citation enforcement
- Mandatory human spec approval gate
- Override window scrutiny (3-phase supervisor review)
- Cross-run override pattern detection (Jaccard similarity ≥ 0.4)
- 7 hard-limit conditions that bypass supervisor to Tier 4

Budget enforcement (token + time) with warn/hard-stop thresholds. Pipeline lockfile prevents concurrent runs on same branch. Override logs preserved across runs in `.correctless/meta/overrides/`.

**Autonomous Skill Dispatch**: Every skill declares an `interaction_mode` (autonomous/interactive/hybrid) in its YAML frontmatter. When `/cauto` dispatches a skill, it passes `mode: autonomous` in the task prompt. Skills use their documented `## Autonomous Defaults` instead of pausing for human input. Decisions are returned as structured output and logged to `.correctless/artifacts/autonomous-decisions-{branch_slug}.jsonl` (ABS-030, sole-writer contract via `scripts/autonomous-decision-writer.sh`). At pipeline end, decisions are summarized — normal decisions are informational, deferred escalations require human confirmation before PR creation. Skills with `context: fork` and `escalate: always` decisions use deferred escalation (apply default, flag for review).

---

## 8. Hook System

Mechanical enforcement via Claude Code's hook runner. Hooks compose — each handles exactly one responsibility.

### PreToolUse Hooks (Fail-Closed)

**workflow-gate.sh** — Phase-gated write enforcement. Blocks file operations that violate the current phase:
- RED phase: blocks source code edits (only test files allowed)
- QA phase: blocks all file writes
- Done/verified: blocks implementation changes

Uses `classify_file()` from lib.sh to distinguish source, test, config, and doc files. Override mechanism with activation counter. Exit 2 = block, exit 0 = allow.

**sensitive-file-guard.sh** — Protects security-critical files from LLM writes:
- `.correctless/config/workflow-config.json`, `auto-policy.json`, `preferences.md`
- `hooks/workflow-advance.sh`, `scripts/harness-fingerprint.sh`, `scripts/audit-record.sh`
- `.env`, credentials, secrets
- `CLAUDE.md`, `.claude/settings.json`

Over-extracting Bash target extraction (every non-flag token is a candidate, canonical-path matcher filters). Covers redirect operators (`>`, `>>`, `1>`, `2>`, `&>`), interpreter+eval-flag chains, and Unicode-lookalike traversal attacks. Uses `canonicalize_path` for path normalization (PAT-017).

**import-guard.json** — Agent hook (JSON config, not bash) that denies test writes bypassing documented entrypoints. Enforces that integration tests exercise the system through its documented API surface.

### PostToolUse Hooks (Fail-Open)

**auto-format.sh** — Auto-formats changed files after writes. Detects and runs the project's formatter (prettier, gofmt, black, rustfmt, etc.) from workflow-config.json. Best-effort — never blocks operations.

**audit-trail.sh** — Structured event logging to `.correctless/artifacts/audit-trail-{branch}.jsonl`. Records every file modification with phase context, skill context, and timestamps. Used by `/cwtf` for accountability analysis.

**token-tracking.sh** — Logs token usage on every Agent tool completion. Records phase, skill (via phase-to-skill mapping), feature, agent description/type, input/output/total tokens, cost, and duration. Feeds `/cmetrics` and `/cverify` calibration.

### State Machine & Helpers

**workflow-advance.sh** — The workflow state machine. Manages phase transitions: `spec → review → tdd-tests → tdd-impl → tdd-qa → tdd-audit → done → verified → documented`. Validates gate conditions before advancing. Maintains spec integrity fields (spec_hash, spec_line_count) for detecting post-review spec mutations. Sole writer of workflow state files. Gate-enforces audit findings persistence (ABS-029).

**statusline.sh** — Workflow-aware statusline for Claude Code. Shows current phase, cost (live feature cost from session transcript cache), context percentage, lines delta. Background refresh with lock file and staleness detection.

---

## 9. Plugin Agents

Narrow-scope sub-agents with pinned tool allowlists. The tool allowlist serves dual purposes: limiting blast radius AND shaping response style toward the output contract.

### `correctless:ctdd-red` — TDD Test Writer

Mechanical test writer for the RED phase. Reads spec, writes failing tests encoding every rule/invariant/prohibition. Tools: Read, Grep, Glob, Write, Edit, Bash. Behavioral discipline prevents over-deliberation. Reads ARCHITECTURE.md entrypoints for integration test writing.

### `correctless:architecture-reviewer` — Architecture Reviewer

Read-only adversarial reviewer for `.correctless/ARCHITECTURE.md` drafts. Finds patterns the document claims but the codebase violates, missing entrypoints, and smoothed-over inconsistencies. Tools: Read, Grep, Glob. Returns JSON findings.

### `correctless:fix-diff-reviewer` — Fix-Diff Reviewer

Read-only reviewer scoped to audit fix-round commits. Catches new bugs, broken invariants, and regressions introduced by fix attempts. Tools: Read, Grep, Glob. Uses UNTRUSTED_DIFF/UNTRUSTED_RULES fences. `jq -e .` parse gate on output. Validated via VP-001/VP-002 pre-merge verification.

### `correctless:supervisor` — Lightweight Supervisor

Activates on escalation, phase transitions, budget warnings, review triage, and override scenarios. Makes terminal decisions (approve/reject/hard_stop). No accumulated state across activations. Configurable mandate levels (conservative/moderate/aggressive). Conservative mandate enforces spec citation validation. Tools: Read, Grep, Glob.

### `correctless:decision-agent` — Ephemeral Decision Agent

Tier 2 decision resolver for Auto Mode Phase 2. Receives minimal context (DR-xxx, spec excerpt, policy section, prior decision summaries). Returns a structured decision and terminates. No state persists between invocations. Tools: Read, Grep, Glob.

---

## 10. Script Library

Shared bash scripts sourced by hooks and skills. All follow PAT-003 conventions (CLI arguments, stdout output, exit 0, source lib.sh).

### Core

- **lib.sh** — Foundation library. Provides `branch_slug()`, `canonicalize_path()` (pure-bash segment-stack path normalizer with security invariants), `classify_file()`, `_has_write_pattern()`, `get_target_file()`, state file locking (`_acquire_state_lock`/`_release_state_lock`/`locked_update_state`), `sha256_hash_file()`, `check_install_freshness()` for stale hook detection, `get_current_session_id()`, `locked_update_file()` for cross-platform session dedup.
- **workflow-state-ext.sh** — Extended state fields and spec approval tracking.

### Auto Mode

- **auto-policy.sh** — Tier 0 deterministic policy engine. First-match-wins evaluation with controlled category/disposition vocabularies. SHA-256 hash verification.
- **decision-routing.sh** — Routes decisions through the Tier 0→1→2→3 hierarchy.
- **decision-record.sh** — Append-only DD-xxx entries with size-regression detection and cardinality verification.
- **intent-hash.sh** — Creates and verifies immutable intent summaries via SHA-256.
- **budget-check.sh** — Token + time budget enforcement with warn (75%) and hard-stop (100%) thresholds.
- **cauto-lock.sh** — Pipeline lockfile. PID-based stale detection. Corrupted locks = fail-closed.
- **auto-report.sh** — Auto Run Report generator (12 required sections).
- **review-triage.sh** — Phase 3 review finding triage + PRH-003 enforcement.
- **supervisor-mandate.sh** — Phase 3 mandate validation + hard limits + citation check.
- **override-scrutiny.sh** — Phase 3 override lifecycle. Three-phase supervisor review (issuance → per-action → closure). Cross-run pattern detection with Jaccard similarity. Override log preservation (50-file cap).
- **override-crosscheck.sh** — Phase 3 base-commit verification + file-touch drift + spec completeness.
- **autonomous-decision-writer.sh** — Sole writer of autonomous decisions JSONL (ABS-030). SFG-bypass pattern matching audit-record.sh. Subcommands: `append`, `read`, `path`.

### Analysis & Reporting

- **antipattern-scan.sh** — Deterministic scanner with grep portability checks and dead-security-function detection. Supports `# scanner:` tag convention (PAT-014).
- **security-scan.sh** — 3-layer security scanning (PRH-001).
- **audit-record.sh** — Sole writer of audit findings artifacts. Sensitive-file-guard protected. Subcommands: `write-round`, `append-history`.
- **compute-session-cost.sh** — Reads Claude Code session transcripts (~/.claude/projects/) and computes real USD cost. Message.id deduplication. Phase attribution. Subagent cost tracking. Multi-session support. `--cache` mode for statusline (lightweight subset to stdout). `--phase` mode for current-phase cost.
- **generate-dashboard.sh** — HTML dashboard generator for longitudinal quality visualization.
- **extract-entrypoints.sh** — Extracts YAML entrypoints from ARCHITECTURE.md. Fallback chain: yq → python3 with PyYAML.
- **harness-fingerprint.sh** — Writes `{model}|{HARNESS_VERSION}` fingerprint. HARNESS_VERSION is a manually-bumped integer constant (sensitive-file-guard protected).

---

## 11. Dynamic Rigor System

Single plugin with three intensity levels. Skills check intensity at startup and adapt behavior.

### Intensity Levels

| Level | Overhead | Available Skills | When To Use |
|-------|----------|-----------------|-------------|
| **standard** | ~10-15 min | 19 core skills | SaaS, APIs, CLI tools |
| **high** | ~30-60 min | + /creview-spec, /caudit, /cupdate-arch | Auth, payments, sensitive data |
| **critical** | ~1-2 hours | + /cmodel, /credteam | Security infrastructure, crypto |

### Effective Intensity Computation (PAT-005)

Each skill computes `max(project_intensity, feature_intensity)`:
- Project intensity from `workflow.intensity` in workflow-config.json
- Feature intensity from `workflow-advance.sh status`
- Fallback chain: feature → project → standard

### Per-Feature Override

`workflow-advance.sh set-intensity <standard|high|critical>` stores feature-level intensity in workflow state. A critical project can have a standard feature; a standard project can escalate a single sensitive feature to critical.

### Cross-Skill Calibration (ABS-005)

`/cverify` writes outcome data to `.correctless/meta/intensity-calibration.json`. `/cspec` reads this data as a post-signal modifier. Features exceeding 200K tokens or ≥3 QA rounds or ≥8 findings trigger auto-raise. Configurable modes: passive (advisory), active (auto-raise), hybrid (passive→active after 5 entries). 50-entry recency window.

### Intensity Detection Signals

`/cspec` detects intensity from spec content: STRIDE keywords, invariant density, compliance language, security terminology. Signals are configurable in workflow-config.json.

---

## 12. Security Infrastructure

### Sensitive File Protection

`sensitive-file-guard.sh` (PreToolUse, fail-closed) blocks LLM writes to security-critical files. Over-extracting Bash target extraction: every non-flag token is a candidate; the canonical-path matcher filters false positives. Covers:
- Direct tool writes (Write, Edit)
- Bash redirects (`>`, `>>`, `1>`, `2>`, `&>`) in whitespace-separated and inline-attached forms
- Interpreter + eval-flag chains (`bash -c`, `python -c`, etc.)
- Path canonicalization via `canonicalize_path` (PAT-017) — closes traversal attacks (`subdir/../.env` vs `.env`)
- Unicode-lookalike traversal (ASCII-only `.` recognition per INV-002a)

### Spec Integrity Verification

`workflow-advance.sh` stores `spec_hash` and `spec_line_count` at review completion. Detects post-review spec mutations (silently changing the spec after review approved it). Spec mutation alerts surface in workflow status.

### Intent Verification (Auto Mode)

Immutable intent summary created at pipeline startup. SHA-256 hash stored in workflow state. Verified on every supervisor activation and on `/cauto resume`. Mismatch = hard stop.

### Policy Integrity (Auto Mode)

Auto-policy.json SHA-256 hash verified on every Tier 0 evaluation. Tampering = all decisions route to higher tiers.

### Harness Fingerprint

Records `{model}|{HARNESS_VERSION}` at spec time. HARNESS_VERSION is manually-bumped (sensitive-file-guard protected from autonomous edits). Enables regression detection across model/harness upgrades. Advisory only.

### Antipattern-Driven Prevention

26+ cataloged antipattern classes (AP-001 through AP-026+) derived from QA Olympics, hacker audits, postmortems, and Devil's Advocate runs. `/cspec` and `/creview` check new features against this list. `scripts/antipattern-scan.sh` mechanically enforces detectable patterns (grep portability, dead security functions, etc.).

### Trust Boundaries

Six documented trust boundaries (TB-001 through TB-006) with invariants, violation conditions, and tests:
- TB-001: Config → shell execution (eval allowlist)
- TB-002: Script output → LLM context (no content interpolation)
- TB-003: Historical findings → review context (advisory, not instructions)
- TB-004: Human spec → LLM execution (escalation on architectural decisions)
- TB-005: Intra-skill agent handoff (read-only reviewer tools)
- TB-006: Session transcript reads (numeric fields only)

---

## 13. Developer Experience

### Statusline

Live workflow dashboard in Claude Code's status bar:
```
correctless/  feature/auth  Opus  34%  RED  QA:R0  $0.42  +87/-12
```
Shows: phase, QA round, live feature cost (from session transcript cache), context percentage, lines changed. Background refresh with lock file for cost computation. Staleness detection.

### Structured Decision UX

Every interactive decision presented as numbered options with a recommended default. No open-ended questions. Wizard-style flow for review/triage skills — one finding at a time, wait for response.

### Pipeline Progress Diagrams

ASCII workflow diagrams on phase transitions showing current position in the pipeline. Rendered in `/cstatus`, `/chelp`, and `/ctdd`.

### Calm Reset Prompts

In `/ctdd` and `/caudit` orchestrators, when context is growing long, prompts guide the agent to focus and avoid repetitive patterns.

### Checkpoint Resume

Long-running skills (ctdd, caudit, cauto, creview-spec) support resumption after context compaction. State preserved in workflow state files.

### Auto-Format on Save

PostToolUse hook auto-formats files after writes using the project's configured formatter. Zero configuration — detects formatter from workflow-config.json.

### Stale Hook Detection

Install manifest (`.correctless/.install-manifest.json`) records SHA-256 checksums of installed hooks and scripts. `check_install_freshness()` in lib.sh detects when installed files drift from source (plugin updated but setup not re-run).

---

## 14. Testing Infrastructure

### Test Suite

75 test files with ~5,000+ assertions covering all hooks, scripts, skills, agents, and cross-component integration:

- Hook behavior tests (workflow-gate, sensitive-file-guard, auto-format, token-tracking, audit-trail)
- Script unit tests (lib.sh, antipattern-scan, auto-policy, decision-record, budget-check, etc.)
- Skill contract tests (frontmatter validation, allowed-tools verification, constraint presence)
- Agent structural tests (frontmatter parity, tool allowlist, distribution sync, inline-prompt denial)
- Integration tests (setup registration, sync propagation, phase transitions)
- Architecture drift tests (rule file ↔ ARCHITECTURE.md sync, content-pairing)
- Antipattern enforcement tests (test-evasion detection, scanner coverage)

### Shared Test Harness

`tests/test-helpers.sh` provides `pass()`, `fail()`, `section()`, `skip()`, `summary()`. Sourced by all test files. Eliminates boilerplate duplication (extracted from 14 files that originally copied the same helpers).

### Test Registration Guard

Architecture drift tests verify all `test-*.sh` files are registered in workflow-config.json, ci.yml, AND test.sh. Prevents new test files from being silently skipped.

### jq Version Matrix

CI tests against jq 1.7.1 and 1.8.1 to catch operator precedence bugs (PAT-010 / AP-011).

### Property-Based Testing Helpers

Language-specific PBT guides in `helpers/` for Go, Python, Rust, and TypeScript. Available at high+ intensity.

---

## 15. Documentation System

### GitHub Pages Site

Jekyll-based documentation site with:
- Project overview and quick start
- Standard workflow guide with state machine diagrams
- Per-skill documentation pages (23+)
- Design decision rationale
- Mermaid diagram rendering
- Light/dark mode toggle

### Per-Feature Documentation

`docs/features/{feature}.md` — one file per significant feature. References spec (doesn't duplicate it). Generated by `/cdocs`.

### Dev Journal

`docs/dev-journal.md` — append-only journal capturing implementation context ("why" knowledge) that is lost after conversation ends. Written by `/cdocs`.

### Workflow History

`docs/workflow-history.md` — append-only summary per feature. Records spec rules count, QA rounds, findings fixed, overrides used, branch info, and cost.

### CLAUDE.md Learning

`/cpostmortem`, `/cdocs`, and `/caudit` append learnings to CLAUDE.md. Convention confirmations, postmortem citations, and audit patterns compound over time. Each entry includes date, source, and specific finding IDs.

---

## 16. Distribution & Installation

### Setup Script

Idempotent installer that:
1. Detects project language (Go, TypeScript, Rust, Python, Java, Ruby, other)
2. Auto-detects test runner, build tool, formatter, linter per language
3. Prompts for intensity level
4. Installs hooks to `.claude/` (glob-based — PAT-016, never hardcoded lists)
5. Installs scripts to `.correctless/scripts/` (glob-based)
6. Registers PreToolUse and PostToolUse hooks via metadata headers (ABS-004)
7. Creates `.correctless/config/workflow-config.json`
8. Scaffolds templates (ARCHITECTURE.md, AGENT_CONTEXT.md, preferences.md, antipatterns.md, auto-policy.json, baseline feature)
9. Writes install manifest with SHA-256 checksums
10. Runs security/quality hygiene checks (17 checks)
11. Adapts to project maturity (greenfield, early-stage, mature)

Re-running never overwrites user-edited files. Supports upgrade from older versions (scripts namespace migration from `scripts/` to `.correctless/scripts/`).

### Sync Script

`sync.sh` propagates source edits to the `correctless/` distribution directory:
- Skills, hooks, templates, helpers, agents, scripts
- Strips dogfood-only annotations
- JSON hook propagation with JSON-specific staleness detection
- `--check` mode for CI verification
- Stale file detection in both directions

### Plugin Marketplace

Available via Claude Code plugin marketplace:
```
/plugin marketplace add joshft/correctless
/plugin install correctless
```

Also installable via git clone for development.

---

## 17. CI/CD & Project Health

### GitHub Actions CI

- Full test suite execution (`bash tests/test.sh`)
- ShellCheck linting on all `.sh` files
- jq version matrix (1.7.1 + 1.8.1)
- Sync verification (`bash sync.sh --check`)

### Dependabot

Automated dependency updates for GitHub Actions with pinned commit SHAs.

### OpenSSF Scorecard

Security best practices badge. SECURITY.md with vulnerability reporting process. CODEOWNERS for security-sensitive files. Gitleaks baseline for secret scanning.

### Project Dashboard

HTML dashboard (`dashboard.html`) for longitudinal quality visualization. Generated by `scripts/generate-dashboard.sh`. Sections include:
- Feature timeline
- QA convergence trends
- Cost by phase
- Quality trajectory with real severity counts
- Workflow history

Supports light/dark mode. Trend insights overlay.

---

## 18. MCP Integrations

### Serena (Optional)

Symbol-level code analysis via MCP. Every skill with Serena integration:
1. Checks `mcp.serena` config flag
2. Includes standard 6-tool fallback table
3. States "optimizer, not a dependency"
4. Falls back silently (no abort, no retry, no mid-operation warnings)
5. Notifies once at session end if unavailable

### Context7 (Optional)

Library documentation lookup via MCP. Falls back to web search when unavailable. Single end-of-session notification.

---

## 19. Cross-Cutting Capabilities

### Agent Separation (PAT-002)

Each TDD phase (RED/GREEN/QA/mini-audit) is a different agent. Enforced via `context: fork` and sub-agent spawning. The test writer doesn't know the implementation plan. The QA agent didn't write the tests.

### Shared Constraints

Universal constraints applied to every skill via `skills/_shared/constraints.md`:
- **No auto-invoke**: skills tell the human what comes next, never auto-start
- **Evidence before claims**: must run commands and show output, not assume results
- **Context management**: 70% warn, 85% stop
- **Effective intensity computation**: `max(project, feature)` with fallback chain
- **Token tracking**: mechanical logging of subagent costs
- **MCP degradation**: silent fallback, end-of-session notification
- **Project preferences**: read and respect `.correctless/preferences.md`

### Branch-Scoped State (PAT-004)

Workflow state in `.correctless/artifacts/workflow-state-{branch-slug}.json`. Each feature branch has independent state. `workflow-advance.sh` is the sole writer with advisory locking (ABS-003).

### Shift-Left Review (PAT-006)

`/creview` and `/creview-spec` read historical findings from QA Olympics, Devil's Advocate reports, and audit artifacts to detect recurring patterns. Classification is ephemeral (in-context only, not persisted). 10-file budget cap.

### Sole-Writer Contracts

Security-critical files have documented sole-writer contracts enforced by sensitive-file-guard:
- `workflow-advance.sh` → workflow state files
- `audit-record.sh` → audit findings artifacts
- `harness-fingerprint.sh` → harness fingerprint store
- `compute-session-cost.sh` → cost artifacts
- `/cmodelupgrade` → model baselines
- `autonomous-decision-writer.sh` → autonomous decisions JSONL

### Path-Scoped Rules (ABS-009)

Rule files under `.claude/rules/*.md` load into agent context when editing scoped files:
- `hooks-pretooluse.md` — PreToolUse hook conventions (scoped to all PreToolUse hooks)
- `canonicalize-path.md` — Path normalizer security invariants (scoped to lib.sh)

Structural drift enforced by `tests/test-architecture-drift.sh`.

### Monorepo Support

Per-package configuration with longest-prefix-match resolution. Cached lookups.

### Output Redaction

Paths, credentials, and hostnames sanitized for external-facing skills. Redaction rules in `templates/redaction-rules.md`.

### Git Integration

- Git trailers (opt-in): Spec, Rules-covered, Verified-by in commit messages
- Git notes (opt-in): Verification summary on commits
- Git bisect in `/cdebug`: Automated regression finding
- Workflow state is branch-scoped
- Post-merge routine documented in CLAUDE.md
