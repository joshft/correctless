# Changelog

All notable changes to Correctless are documented here.

## [2.0.0] - 2026-03-31

### Added — Skills (23 total: 16 Lite, 23 Full)

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
- Glossary with 11 terms

### Infrastructure
- 4 hooks: workflow-gate.sh, workflow-advance.sh, statusline.sh, audit-trail.sh
- 57 automated tests
- CI with test suite + ShellCheck
- Dependabot for GitHub Actions
- Branch protection on main
- OpenSSF Scorecard badge

## [1.0.0] - 2026-03-29

Initial release. 10 Lite skills, 17 Full skills, setup script, state machine, workflow gate.
