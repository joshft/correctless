# Agent Context — Correctless

> Last updated: 2026-04-09

## What This Project Does

Claude Code plugin framework that enforces a correctness-oriented development workflow. Ships as a single `correctless/` distribution with 26 skills and configurable intensity levels (standard, high, critical). Standard intensity (~10-15 min/feature) covers core TDD workflow; high/critical intensity (~1-2 hr/feature) adds formal modeling, adversarial review, and convergence auditing. The core principle: never let an agent grade its own work — each workflow phase uses a separate agent with a different lens.

## Key Components

| Component | Location | Purpose |
|-----------|----------|---------|
| Skills | `skills/*/SKILL.md` | 26 skill definitions. Each is a slash command with frontmatter contract. |
| Hooks | `hooks/` | workflow-gate.sh (PreToolUse gating), workflow-advance.sh (state machine), statusline.sh, audit-trail.sh, token-tracking.sh (PostToolUse token logging with phase-to-skill mapping) |
| Templates | `templates/` | Scaffolding for new projects: ARCHITECTURE.md, AGENT_CONTEXT.md, antipatterns, configs |
| Helpers | `helpers/` | PBT guides per language (high+ intensity) |
| Distribution | `correctless/` | Single 26-skill distribution target — never edit directly |
| Setup | `setup` | Idempotent install script: detect stack, scaffold, register hooks |
| Tests | `tests/test*.sh` | 31 test files (~2,810 shell tests) covering setup, state machine, gate hook, full mode, MCP integration, bug fixes, QoL, decision UX, statusline, consolidation, crelease, cexplain, calm resets, dynamic rigor, intensity detection, wire-intensity-creview, wire-intensity-pipeline, auto-format, sensitive-file-guard, antipattern-scan, shift-left-review, lib, lib-locking, gate-path-exceptions, token-tracking, token-tracking-setup, ci-hook-wiring, workflow-gate, intensity-calibration, auto-recurring-patterns, token-aware-intensity, allowed-tools-check, token-tracking-skill-field |
| Sync | `sync.sh` | Propagates source edits to the `correctless/` distribution |

## Design Patterns

- **Source-to-dist sync** (PAT-001): edit in `skills/`, `hooks/`, `templates/`, `helpers/` only — run `sync.sh` to propagate to `correctless/`
- **Agent separation** (PAT-002): each TDD phase (RED/GREEN/QA) is a different agent — enforced via `context: fork` and sub-agent spawning
- **Phase-gated writes** (PAT-003): `workflow-gate.sh` blocks file operations that violate the current phase (RED blocks source, QA blocks everything)
- **Branch-scoped state** (PAT-004): state lives in `.correctless/artifacts/workflow-state-{branch-slug}.json` — `workflow-advance.sh` is the only writer
- **Effective intensity** (PAT-005): each pipeline skill and gated skill computes `max(project_intensity, feature_intensity)` using ordering `standard < high < critical`. Project intensity from `workflow.intensity` in config, feature intensity from `workflow-advance.sh status`. Fallback: feature_intensity → workflow.intensity → standard
- **Shift-left review** (PAT-006): `/creview` and `/creview-spec` read historical findings (QA, Olympics audits, Devil's Advocate reports) to detect recurring patterns. Classification is ephemeral — see ABS-002 in ARCHITECTURE.md. 10-file budget (PAT-004)
- **Cross-skill calibration** (ABS-005): `/cverify` writes outcome data (QA rounds, BLOCKING findings, actual_tokens) to `.correctless/meta/intensity-calibration.json`, `/cspec` reads it during intensity detection as a post-signal modifier. Token data (ABS-006) enriches calibration — features exceeding 200K tokens trigger auto-raise alongside QA rounds >= 3 and findings >= 8. cspec is read-only — only cverify writes. 50-entry recency window. Configurable modes: passive (advisory), active (auto-raise), hybrid (passive→active after 5 entries)
- **MCP integration** (optional): Serena for symbol-level code analysis, Context7 for library docs — check `mcp.serena` and `mcp.context7` in workflow-config.json. Falls back to grep/read silently when unavailable

## Common Pitfalls

- **Editing distribution target directly**: changes in `correctless/` will be overwritten by `sync.sh` — **Instead**: edit in root `skills/`, `hooks/`, `templates/`, `helpers/` then run `bash sync.sh`
- **Forgetting to sync after edits**: distribution targets go stale — **Instead**: always run `bash sync.sh` after editing source files, then `bash tests/test.sh` to verify
- **Adding a skill without updating sync.sh**: new skills won't appear in the distribution — **Instead**: add the skill directory to the skill list in `sync.sh`

## Quick Reference

| Need to... | Do this |
|------------|---------|
| Run tests | `bash tests/test.sh && bash tests/test-mcp.sh` (or run all: see workflow-config.json `commands.test`) |
| Lint shell scripts | `shellcheck hooks/*.sh scripts/*.sh tests/test*.sh sync.sh setup` |
| Sync to distribution | `bash sync.sh` |
| Find a skill | `skills/{name}/SKILL.md` |
| Find skill docs | `docs/skills/{name}.md` |
| Check architecture | `.correctless/ARCHITECTURE.md` |
| See known bugs | `.correctless/antipatterns.md` |
| Find a spec | `.correctless/specs/{feature}.md` |
| Verify sync is clean | `bash sync.sh --check` |
| Check MCP status | `jq '.mcp' .correctless/config/workflow-config.json` |
| Set feature intensity | `bash hooks/workflow-advance.sh set-intensity <standard\|high\|critical>` |
| Configure detection signals | Add `workflow.intensity_signals` to `.correctless/config/workflow-config.json` |
