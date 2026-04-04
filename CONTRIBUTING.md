# Contributing to Correctless

Thanks for your interest in contributing! Correctless is a set of Claude Code skills and bash hooks — contributions can range from fixing a hook bug to adding an entirely new skill.

## Quick Start

```bash
git clone https://github.com/joshft/correctless.git
cd correctless
bash tests/test.sh        # Infrastructure tests
bash tests/test-mcp.sh    # MCP integration tests
bash sync.sh              # Propagate source → correctless/ distribution
bash sync.sh --check      # Verify distributions are in sync (exit 0 = clean)
```

## Project Structure

```
skills/               # Source skills (26 SKILL.md files)
hooks/                # Bash hooks (gate, state machine, statusline, audit trail)
templates/            # Config, doc, and spec templates
helpers/              # PBT guides per language (high+ intensity)
tests/                # 14 test files (~1,518 assertions)
setup                 # Install script
sync.sh               # Copies source → correctless/ distribution
correctless/          # Single distribution (26 skills, intensity-gated)
docs/skills/          # Per-skill documentation pages
docs/design/          # Design specification
```

**Important:** Never edit files in `correctless/` directly. Edit in `skills/`, `hooks/`, or `templates/`, then run `bash sync.sh` to propagate.

## How to Contribute

### Fixing a Bug

1. Fork the repo and create a branch: `git checkout -b fix/description`
2. Read the relevant hook or skill file
3. Make the fix
4. Run `bash tests/test.sh` — all tests must pass
5. Run `bash sync.sh` — plugins must be in sync
6. Open a PR with: what was broken, why, and how you fixed it

### Adding a New Skill

1. Create `skills/myskill/SKILL.md` following the existing pattern:
   - YAML frontmatter: `name`, `description` (trigger condition, not capability), `allowed-tools`
   - Progress Visibility section (mandatory for skills >2 min)
   - "If Something Goes Wrong" section
   - Constraints section with: `evidence-before-claims`, `no-auto-invoke` (if applicable), `redaction` (if external-facing)
2. Create `docs/skills/myskill.md` documentation page following the template (see any existing page)
3. Register the skill in ALL of these files:
   - `sync.sh` — add to the skill list, update count
   - `setup` — add to both CLAUDE.md command list blocks
   - `hooks/workflow-advance.sh` — add to help text
   - `skills/cstatus/SKILL.md` — add to available commands
   - `skills/csetup/SKILL.md` — add to Step 9 command list
   - `skills/chelp/SKILL.md` — add to command list + quick reference
   - `README.md` — add to skill table, update counts
   - `.claude-plugin/marketplace.json` — update counts
   - `docs/design/correctless.md` — update evolution notes
   - `ARCHITECTURE.md` — update skill count if changed
   - `AGENT_CONTEXT.md` — update skill count and test count if changed
   - `CHANGELOG.md` — add entry in current version section
4. Run `bash sync.sh && bash tests/test.sh`
5. Open a PR

### Modifying a Hook

The hooks (`hooks/workflow-gate.sh`, `hooks/workflow-advance.sh`, `hooks/audit-trail.sh`, `hooks/statusline.sh`) are performance-critical and security-critical:

- **Gate must be <5s.** It runs before every file edit.
- **Audit trail must be <100ms.** It runs after every tool call.
- **Statusline must be <50ms.** It renders continuously.
- **All hooks must be macOS + Linux portable.** Test with: `md5sum || md5`, `stat -c || stat -f`, no bashisms beyond what bash 3.2 supports.
- **Gate must never fail open.** If something goes wrong, block (exit 2), don't allow (exit 0). Exception: the no-state-file path.

Run ShellCheck before submitting: `shellcheck hooks/*.sh`

## Code Style

- **Skills:** Markdown with YAML frontmatter. Keep descriptions as trigger conditions ("Use when X"), not capability summaries.
- **Hooks:** Bash with `set -euo pipefail`. Portable to macOS bash 3.2 + BSD tools.
- **Tests:** Bash assertions in `tests/test*.sh`. Each test is a function that prints PASS/FAIL.
- **No emojis in skill files** unless the user explicitly requests them.
- **No model overrides** in skill frontmatter (`model:` field). Removed early to avoid rate limits.

## Testing

```bash
# Run all 14 test suites (canonical command from workflow-config.json):
bash tests/test.sh && bash tests/test-mcp.sh && bash tests/test-bugfixes.sh && bash tests/test-qol.sh && bash tests/test-decisions.sh && bash tests/test-statusline.sh && bash tests/test-consolidation.sh && bash tests/test-crelease.sh && bash tests/test-calm-resets.sh && bash tests/test-dynamic-rigor.sh && bash tests/test-intensity-detection.sh && bash tests/test-wire-intensity-creview.sh && bash tests/test-wire-intensity-pipeline.sh && bash tests/test-cexplain.sh

# Quick smoke test (2 suites):
bash tests/test.sh && bash tests/test-mcp.sh

# Other checks:
bash sync.sh --check      # Distributions must be in sync
shellcheck hooks/*.sh     # Must pass with -S warning
```

CI runs tests + sync check + ShellCheck on every PR.

## Pre-commit Hooks

Install pre-commit hooks for local checks before commits:

```bash
pip install pre-commit   # or: pipx install pre-commit
pre-commit install
```

Hooks: gitleaks (secret scanning), typos, shellcheck, trailing whitespace, sync check.

## Quick Fixes

For small changes (< 50 LOC, < 3 files), use `/cquick` instead of the full workflow. It enforces TDD but skips spec/review/verify/docs.

## QA Process

Correctless uses its own QA process on itself. After significant changes:

1. QA subagents are delegated to review all modified files
2. Findings are fixed iteratively until convergence (0 CRITICAL, 0 HIGH)
3. A technical writer reviews documentation changes

You don't need to run QA yourself — the maintainer will run it on your PR.

## Questions?

Open a [GitHub Discussion](https://github.com/joshft/correctless/discussions) for questions, ideas, or show-and-tell. Use issues for bugs and feature requests.
