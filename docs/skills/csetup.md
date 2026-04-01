# /csetup — Initialize Correctless

> Detect your project's stack, configure the workflow, bootstrap documentation, and run a health check — all in one adaptive, interactive conversation that scales to your project's maturity.

## When to Use

- First time adding Correctless to a project
- Re-running on an existing project to check health improvements or detect new tooling
- After major infrastructure changes (new CI, new test runner, new dependencies)
- **Not for:** projects that are already set up and healthy — re-running is safe but unnecessary unless something changed

## How It Fits in the Workflow

This is the entry point. Nothing else works well without it. `/csetup` creates the configuration, documentation, and project context that every other skill reads. After setup completes, the next step is `/cspec` to start your first feature.

## What It Does

Setup is adaptive — it classifies your project as **greenfield** (< 10 source files, < 10 commits), **early-stage** (10-100 source files), or **mature** (100+ source files, existing CI/tests/docs) and adjusts the flow accordingly.

### Greenfield (fast, minimal)
1. **Asks what you're building** — "REST API, CLI tool, web app, library?"
2. **Detects language and package manager**, confirms with you
3. **Runs the setup script** — creates directories, registers hooks, generates config
4. **Configures MCP servers** — offers Serena (symbol-level analysis) and Context7 (current library docs) if tooling is available
5. **Bootstraps docs** — writes minimal ARCHITECTURE.md and AGENT_CONTEXT.md (real content, not templates)
6. **Essential checks** — secrets in source, .gitignore coverage, lock file committed
7. **Source control defaults** — writes branching strategy and merge strategy to config
8. **Guides you to your first feature** — suggests `/cspec`

### Early-stage (balanced)
1. **Understands your project** — counts files, detects frameworks, asks if there's anything to know
2. **Runs the setup script** — creates directories, registers hooks, generates config
3. **Configures MCP servers** — offers Serena and Context7 if tooling is available
4. **Confirms config** as a single summary (not field-by-field)
5. **Discovers architecture** — scans and presents findings as observations, not prescriptions
6. **Mines conventions** — filtered by your project's goal (API patterns for APIs, CLI patterns for CLIs)
7. **Bootstraps AGENT_CONTEXT.md** — populated from scan results
8. **Tiered health check** — critical security first, then opt-in full health card (up to 19 items)
9. **Source control setup** — detects remote, commit conventions, branching/merge strategy, offers PR template
10. **First feature guidance** — maturity-appropriate next steps

### Mature (thorough)
1. **Learns your project** — comprehensive scan of 100+ files, existing CI, test infrastructure
2. **Runs the setup script** — creates directories, registers hooks, generates config
3. **Configures MCP servers** — offers Serena and Context7 if tooling is available
4. **Confirms config** as a single summary
5. **Bootstraps or merges docs** — populates ARCHITECTURE.md from scratch if none exists, or adds Correctless sections alongside existing content (never overwrites)
6. **Full convention mining** — all 6 categories, goal-aware filtering, inconsistencies surfaced as findings
7. **Bootstraps AGENT_CONTEXT.md** — populated or merged with existing
8. **Tiered health check** — critical security first, then opt-in full health card (up to 19 items)
9. **Source control configuration** — full detection, branching/merge strategy, statusline activation
10. **First feature guidance** — maturity-appropriate next steps

## Checkpoint Resume

If setup is interrupted (context compaction, user stops), re-running `/csetup` detects the checkpoint and offers to resume from the last completed step instead of starting over. The checkpoint includes the current branch — if you've switched branches, it starts fresh.

## Example

**Greenfield project:**
```
User: /csetup

Agent: [creates task list: 7 items]
       I see a new TypeScript project with 4 files. What are you building?

User: A REST API for a recipe sharing app.

Agent: Got it — REST API project.
       Language: TypeScript, Package manager: pnpm. Looks right?

User: Yes.

Agent: [runs setup, bootstraps minimal docs, quick security check]
       No secrets found, .gitignore looks good. You're set up.
       Start your first feature: git checkout -b feature/my-feature
       then run /cspec.
```

**Mature project:**
```
User: /csetup

Agent: [creates task list: 9 items]
       I see a mature TypeScript project with 247 files, vitest, and GitHub Actions CI.
       I'll learn your existing patterns — this takes a minute.

       [scans codebase, discovers architecture, mines conventions]

       Here's what I detected:
       - Language: TypeScript, Test runner: vitest, Linter: eslint, Build: pnpm build
       Does this look right?

User: Yes.

Agent: Conventions I found:
       - 18/20 files use camelCase. 2 deviate — cleanup candidates?
       - Two different error response formats in API routes. Want to pick one?

       [drafts AGENT_CONTEXT.md from scan results]
       Here's the AGENT_CONTEXT.md I'd write. Look good?

User: Yes.

Agent: Security checks: all clear. Want to see the full health card?

User: Yes.

Agent: Project Health Check — recipe-api (TypeScript/Express)
       Score: 11/15 checks passing (4 items N/A for this stack)
       [full health card with fixes offered]
```

## What It Reads / Writes

| Reads | Writes |
|-------|--------|
| Project manifest files (package.json, go.mod, etc.) | `.claude/workflow-config.json` |
| Existing ARCHITECTURE.md, AGENT_CONTEXT.md | `ARCHITECTURE.md` (populated or minimal stub) |
| `.claude/workflow-config.json` (architecture_state, agent_context_state) | `AGENT_CONTEXT.md` (populated or minimal stub) |
| Source files (convention mining) | `CLAUDE.md` (conventions appended) |
| .env, .gitignore, CI configs | `.claude/artifacts/checkpoint-csetup.json` |
| Git history (commit conventions) | `.pre-commit-config.yaml` (if accepted) |
| | `.github/workflows/ci.yml` (if accepted) |
| | `.github/dependabot.yml` (if accepted) |
| | `.env.example` (if accepted) |
| | `.gitignore` (additions, if accepted) |
| | Linter/formatter config (if accepted) |
| | PR template (if accepted) |
| | `.claude/settings.json` (hook registration) |

## Lite vs Full

Both modes run the same adaptive flow and health check. Full mode additionally surfaces the workflow intensity setting (low/standard/high/critical) during config confirmation and lets you change it. Intensity configures STRIDE analysis, formal modeling, and stricter QA rounds.

## Common Issues

- **Pre-commit hook conflicts with Husky**: Correctless hooks are Claude Code PreToolUse hooks registered in `.claude/settings.json`, not git hooks. They coexist with Husky without conflict. The setup agent will acknowledge existing hook systems.
- **`jq` required**: The setup script uses `jq` for JSON manipulation. If `jq` is not installed, some config detection steps will fall back to manual detection. Install `jq` before running setup for the smoothest experience.
- **Greenfield setup is fast**: Under a minute for projects with < 10 files. The agent skips convention mining and most health checks, but still creates minimal docs (ARCHITECTURE.md, AGENT_CONTEXT.md) so downstream skills work correctly.
- **Mature setup takes longer**: Expect 5-10 minutes for projects with 100+ files. The agent scans your codebase, mines conventions, and runs the full health check. Subsequent runs are faster.
- **Checkpoint interrupted**: If setup gets interrupted, just re-run `/csetup`. It will offer to resume from where it left off (checkpoint valid for 24 hours, branch-scoped).
- **Test pattern mismatch**: If the agent finds test files that don't match your `workflow-config.json` test pattern, it will offer to update the pattern. Fixing this during setup prevents frustration during the first `/ctdd` run.
