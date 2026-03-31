# Contributing to Correctless

Thanks for your interest in contributing! Correctless is a set of Claude Code skills and bash hooks — contributions can range from fixing a hook bug to adding an entirely new skill.

## Quick Start

```bash
git clone https://github.com/joshft/correctless.git
cd correctless
bash test.sh          # Run the 57-test suite
bash sync.sh          # Propagate source → both plugins
```

## Project Structure

```
skills/               # Source skills (23 SKILL.md files)
hooks/                # Bash hooks (gate, state machine, statusline, audit trail)
templates/            # Config and doc templates
helpers/              # PBT helpers (Full mode only)
setup                 # Install script
test.sh               # Automated test suite
sync.sh               # Copies source → correctless-lite/ and correctless-full/
correctless-lite/     # Lite plugin (16 skills)
correctless-full/     # Full plugin (23 skills)
docs/skills/          # Per-skill documentation pages
```

**Important:** Never edit files in `correctless-lite/` or `correctless-full/` directly. Edit in `skills/`, `hooks/`, or `templates/`, then run `bash sync.sh` to propagate.

## How to Contribute

### Fixing a Bug

1. Fork the repo and create a branch: `git checkout -b fix/description`
2. Read the relevant hook or skill file
3. Make the fix
4. Run `bash test.sh` — all tests must pass
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
   - `sync.sh` — add to both Lite and/or Full loops, update counts
   - `setup` — add to both CLAUDE.md command list blocks
   - `hooks/workflow-advance.sh` — add to help text
   - `skills/cstatus/SKILL.md` — add to available commands
   - `skills/csetup/SKILL.md` — add to Step 9 command list
   - `skills/chelp/SKILL.md` — add to command list + quick reference
   - `README.md` — add to skill table, update counts
   - `.claude-plugin/marketplace.json` — update counts
   - `correctless-lite.md` and `correctless.md` — update evolution notes
4. Run `bash sync.sh && bash test.sh`
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
- **Tests:** Bash assertions in `test.sh`. Each test is a function that prints PASS/FAIL.
- **No emojis in skill files** unless the user explicitly requests them.
- **No model overrides** in skill frontmatter (`model:` field). Removed early to avoid rate limits.

## Testing

```bash
bash test.sh          # 57 tests covering setup, state machine, gate, utilities, Full mode
bash sync.sh          # Must produce no changes (git diff --exit-code)
shellcheck hooks/*.sh # Must pass with -S warning
```

CI runs all three on every PR.

## QA Process

Correctless uses its own QA process on itself. After significant changes:

1. QA subagents are delegated to review all modified files
2. Findings are fixed iteratively until convergence (0 CRITICAL, 0 HIGH)
3. A technical writer reviews documentation changes

You don't need to run QA yourself — the maintainer will run it on your PR.

## Questions?

Open a [GitHub Discussion](https://github.com/joshft/correctless/discussions) for questions, ideas, or show-and-tell. Use issues for bugs and feature requests.
