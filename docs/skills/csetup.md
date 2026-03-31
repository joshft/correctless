# /csetup — Initialize Correctless

> Detect your project's stack, configure the workflow, bootstrap documentation, and run a 17-item health check — all in one interactive conversation.

## When to Use

- First time adding Correctless to a project
- Re-running on an existing project to check health improvements or detect new tooling
- After major infrastructure changes (new CI, new test runner, new dependencies)
- **Not for:** projects that are already set up and healthy — re-running is safe but unnecessary unless something changed

## How It Fits in the Workflow

This is the entry point. Nothing else works well without it. `/csetup` creates the configuration, documentation, and project context that every other skill reads. After setup completes, the next step is `/cspec` to start your first feature.

## What It Does

1. **Detects your project** — language, test runner, package manager, existing tooling — and confirms findings with you before proceeding
2. **Runs the setup script** — creates directories, registers hooks, generates the workflow config template
3. **Walks through config interactively** — verifies test commands, lint commands, coverage commands, and intensity level (Full mode)
4. **Discovers and populates ARCHITECTURE.md** — scans your codebase for components, patterns, conventions, and test infrastructure; merges with existing docs if present
5. **Mines conventions from code** — samples files for naming patterns, error handling styles, import conventions, git commit formats, and surfaces inconsistencies as findings
6. **Bootstraps AGENT_CONTEXT.md** — the briefing document every fresh agent reads first
7. **Runs a 17-item health check** — covers security (secrets in source, dependency scanning, gitignore), code quality (linter, formatter, type checking, pre-commit hooks), testing (runner, coverage), CI/CD (pipeline, branch protection), documentation (README, .env.example), and git hygiene (artifacts, lock files)
8. **Configures source control** — detects remote, CLI tools, commit conventions, and offers to generate PR templates

## Example

```
User: /csetup

Agent: I see a TypeScript project using pnpm with vitest. Does that look right?

User: Yes, that's correct.

Agent: Test command is set to `pnpm test` — is that correct?

User: Use `pnpm run test:unit` instead.

Agent: [scans codebase]
       I found these conventions:
       - 18/20 files use camelCase. 2 deviate: old-utils.ts, legacy-helper.ts.
         Is camelCase the convention?
       - Two different error response formats in your API routes. Want to pick one?

       Project Health Check — my-app (TypeScript/Express)
       Security:
         ✓ No secrets in source: clean
         ✗ Secret scanning: Missing
       Code Quality:
         ✓ Linter: Found (eslint)
         ✗ Pre-commit hooks: Missing
       Testing:
         ✓ Test runner: Found (vitest, 47 tests)
       Score: 11/15 checks passing

       I can generate a pre-commit config with gitleaks + biome. Want me to?
```

## What It Reads / Writes

| Reads | Writes |
|-------|--------|
| Project manifest files (package.json, go.mod, etc.) | `.claude/workflow-config.json` |
| Existing ARCHITECTURE.md, AGENT_CONTEXT.md | `ARCHITECTURE.md` (populated) |
| Source files (convention mining) | `AGENT_CONTEXT.md` (populated) |
| .env, .gitignore, CI configs | `CLAUDE.md` (conventions appended) |
| Git history (commit conventions) | `.pre-commit-config.yaml` (if accepted) |
| | `.github/workflows/ci.yml` (if accepted) |
| | `.github/dependabot.yml` (if accepted) |
| | PR template (if accepted) |

## Lite vs Full

Both modes run the same health check and convention mining. Full mode additionally asks about workflow intensity level (low/standard/high/critical) and configures STRIDE analysis, formal modeling, and stricter QA rounds based on the chosen intensity.

## Common Issues

- **Pre-commit hook conflicts with Husky**: Correctless hooks are Claude Code PreToolUse hooks registered in `.claude/settings.json`, not git hooks. They coexist with Husky without conflict. The setup agent will acknowledge existing hook systems.
- **`jq` required**: The setup script uses `jq` for JSON manipulation. If `jq` is not installed, some config detection steps will fall back to manual detection. Install `jq` before running setup for the smoothest experience.
- **First-time setup takes longer**: Expect 5-10 minutes for an existing project. The agent scans your codebase, mines conventions, and runs 17 health checks. Subsequent runs are faster because they skip already-configured steps.
