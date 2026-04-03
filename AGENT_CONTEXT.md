# Agent Context — Correctless

> Last updated: 2026-04-02

## What This Project Does

Claude Code plugin framework that enforces a correctness-oriented development workflow. Ships as two distributions: Correctless Lite (19 skills, ~10-15 min/feature) and Correctless Full (26 skills, ~1-2 hr/feature with formal modeling and convergence auditing). The core principle: never let an agent grade its own work — each workflow phase uses a separate agent with a different lens.

## Key Components

| Component | Location | Purpose |
|-----------|----------|---------|
| Skills | `skills/*/SKILL.md` | 26 skill definitions. Each is a slash command with frontmatter contract. |
| Hooks | `hooks/` | workflow-gate.sh (PreToolUse gating), workflow-advance.sh (state machine), statusline.sh, audit-trail.sh |
| Templates | `templates/` | Scaffolding for new projects: ARCHITECTURE.md, AGENT_CONTEXT.md, antipatterns, configs |
| Helpers | `helpers/` | PBT guides per language (Full-only) |
| Lite dist | `correctless-lite/` | 19-skill distribution target — never edit directly |
| Full dist | `correctless-full/` | 26-skill distribution target — never edit directly |
| Setup | `setup` | Idempotent install script: detect stack, scaffold, register hooks |
| Tests | `tests/test*.sh` | 10 test suites, 923 shell tests covering setup, state machine, gate hook, full mode, MCP integration, bug fixes, QoL, decision UX, statusline, consolidation, crelease, cexplain, calm resets |
| Sync | `sync.sh` | Propagates source edits to both distribution targets |

## Design Patterns

- **Source-to-dist sync** (PAT-001): edit in `skills/`, `hooks/`, `templates/`, `helpers/` only — run `sync.sh` to propagate to `correctless-lite/` and `correctless-full/`
- **Agent separation** (PAT-002): each TDD phase (RED/GREEN/QA) is a different agent — enforced via `context: fork` and sub-agent spawning
- **Phase-gated writes** (PAT-003): `workflow-gate.sh` blocks file operations that violate the current phase (RED blocks source, QA blocks everything)
- **Branch-scoped state** (PAT-004): state lives in `.correctless/artifacts/workflow-state-{branch-slug}.json` — `workflow-advance.sh` is the only writer
- **MCP integration** (optional): Serena for symbol-level code analysis, Context7 for library docs — check `mcp.serena` and `mcp.context7` in workflow-config.json. Falls back to grep/read silently when unavailable

## Common Pitfalls

- **Editing distribution targets directly**: changes in `correctless-lite/` or `correctless-full/` will be overwritten by `sync.sh` — **Instead**: edit in root `skills/`, `hooks/`, `templates/`, `helpers/` then run `bash sync.sh`
- **Forgetting to sync after edits**: distribution targets go stale — **Instead**: always run `bash sync.sh` after editing source files, then `bash tests/test.sh` to verify
- **Adding a skill without updating sync.sh**: new skills won't appear in distributions — **Instead**: add the skill directory to the appropriate list in `sync.sh` (Lite list and/or Full list)

## Quick Reference

| Need to... | Do this |
|------------|---------|
| Run tests | `bash tests/test.sh && bash tests/test-mcp.sh` (or run all: see workflow-config.json `commands.test`) |
| Lint shell scripts | `shellcheck hooks/*.sh tests/test*.sh sync.sh setup` |
| Sync to distributions | `bash sync.sh` |
| Find a skill | `skills/{name}/SKILL.md` |
| Find skill docs | `docs/skills/{name}.md` |
| Check architecture | `.correctless/ARCHITECTURE.md` |
| See known bugs | `.correctless/antipatterns.md` |
| Find a spec | `.correctless/specs/{feature}.md` |
| Verify sync is clean | `bash sync.sh --check` |
| Check MCP status | `jq '.mcp' .correctless/config/workflow-config.json` |
