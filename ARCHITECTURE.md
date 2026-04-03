# Architecture — Correctless

## Key Components

| Component | Location | Purpose |
|-----------|----------|---------|
| Skills | `skills/*/SKILL.md` | 26 skill definitions (Markdown with frontmatter). Each defines one slash command's behavior, tools, and constraints. |
| Hooks | `hooks/` | 4 bash scripts: workflow gate (PreToolUse), state machine (workflow-advance), statusline, audit trail. These enforce the workflow. |
| Templates | `templates/` | Scaffolding templates for ARCHITECTURE.md, AGENT_CONTEXT.md, antipatterns, invariant templates (Full-only), workflow configs. |
| Helpers | `helpers/` | Property-based testing guides per language (Go, Python, TypeScript, Rust). High+ intensity. |
| Distribution | `correctless/` | Single 26-skill distribution. Intensity gates control which skills activate at each level. |
| Docs | `docs/` | Per-skill user-facing documentation and feature docs. |
| Design Specs | `docs/design/correctless.md` | Design specification covering all intensity levels. |
| Setup | `setup` | Bash script: detects stack, scaffolds config/hooks/templates, registers Claude Code hooks. Idempotent. |
| Tests | `tests/test*.sh` | 11 shell test suites: setup, state machine, gate, full mode, MCP, bug fixes, QoL, decision UX, statusline, consolidation, crelease, cexplain, calm resets, dynamic rigor. |
| Sync | `sync.sh` | Copies source files into the `correctless/` distribution target. |

## Design Patterns

### PAT-001: Source → Distribution Sync
- All development happens in root-level `skills/`, `hooks/`, `templates/`, `helpers/`
- `sync.sh` copies to `correctless/` — this directory is never edited directly
- All 26 skills are included; intensity gates control which activate at each level

### PAT-002: Agent Separation (The Lens Principle)
- Never let an agent grade its own work
- Each TDD phase (RED/GREEN/QA) uses a separate agent with a different framing
- Spec author vs reviewer, test writer vs implementer — incompatible lenses in the same agent
- Enforced via `context: fork` frontmatter and orchestrator spawning sub-agents

### PAT-003: Phase-Gated File Operations
- `workflow-gate.sh` (PreToolUse hook) blocks file writes based on current phase
- RED: blocks source edits unless `STUB:TDD` present; allows test files
- QA: blocks all source and test edits
- Verify (Full): blocks all edits
- State files are always blocked from direct edits

### PAT-004: Branch-Scoped State Machine
- Workflow state lives in `.correctless/artifacts/workflow-state-{branch-slug}.json`
- `workflow-advance.sh` is the only writer — validates transitions, enforces gates
- State includes phase, task, spec_file, qa_rounds, timestamps
- `override` allows temporary bypass (10 tool calls, logged)

### PAT-005: Skill Frontmatter Contract
- Each `SKILL.md` starts with YAML frontmatter: `name`, `description`, `allowed-tools`
- Optional: `model` (which Claude model), `context: fork` (agent separation), `agent` type
- The frontmatter is the skill's API contract with Claude Code

## Conventions

- Shell scripts use `set -euo pipefail` (strict mode)
- State machine transitions validated before execution — invalid transitions error with actionable message
- Config read via `jq` from `.claude/workflow-config.json`
- Test assertions use `assert_eq`, `assert_contains`, `assert_exit` helpers
- Skills check `workflow.intensity` in config to determine which features activate (absent = standard)

## Known Limitations

- `workflow-gate.sh` is an accidental-violation catcher, not a security boundary — a determined agent can bypass it
- ShellCheck is the only code linter; no Markdown linter configured
- No coverage tooling for shell scripts
- `sync.sh` is manual — no CI enforcement that distributions stay in sync
