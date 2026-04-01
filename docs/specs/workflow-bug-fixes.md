# Spec: Workflow Bug Fixes

## What

Fix four active friction bugs discovered during the MCP integration feature: absurdly long auto-generated spec slugs, separate test files breaking the RED gate, QA findings status never getting updated by fix agents, and no local sync check before commit.

## Rules

### Bug 1: Slug Truncation

- **R-001** [unit]: `workflow-advance.sh` `cmd_init` truncates the slug to the first 4 hyphen-separated tokens after slugification (lowercase, non-alphanumeric replaced with hyphens, deduped). Max 50 characters. Example: "MCP integration: Serena + Context7 for symbol-level code analysis" → `mcp-integration-serena-context7`.

- **R-002** [unit]: `/cspec` SKILL.md contains an instruction to ask the user "Short name for this feature? (used in filenames)" before calling `workflow-advance.sh init`. If the user provides a name, that becomes the init argument. If the user declines or says "auto", the skill uses the first 3-4 words of the feature description. Test: grep SKILL.md for the prompt text.

### Bug 2: RED Gate with Separate Test Files

- **R-003** [integration]: `workflow-advance.sh` supports a `commands.test_new` field in `workflow-config.json`. When present, `tests_fail_not_build_error` runs `commands.test_new` instead of `commands.test` to check the RED gate. This allows the main test suite (`commands.test`) to keep passing while new tests in a separate file fail as expected.

- **R-004** [integration]: `tests_pass` (GREEN gate) continues to use `commands.test` — ALL tests including the new ones must pass before advancing to QA.

- **R-005** [integration]: If `commands.test_new` is absent, empty, or null, `tests_fail_not_build_error` falls back to `commands.test` (current behavior preserved).

### Bug 3: QA Findings Status Update

- **R-006** [unit]: `/ctdd` SKILL.md contains an instruction for the fix agent to update `qa-findings-{task-slug}.json` after each fix: set `"status": "fixed"` on findings it addressed. Test: grep ctdd SKILL.md for "status.*fixed" or "mark.*fixed" instruction.

- **R-007** [unit]: `/ctdd` SKILL.md contains an instruction for the orchestrator to verify findings statuses after each fix round and update any finding that was fixed but still shows `"status": "open"`. Test: grep ctdd SKILL.md for orchestrator verification instruction.

### Bug 4: Local Sync Check

- **R-008** [integration]: `sync.sh` supports a `--check` flag that runs sync in dry-run mode: compare source files against distribution copies and exit 1 if any differ, exit 0 if clean. No files are modified, no temp files created when `--check` is passed.

- **R-009** [integration]: `.pre-commit-config.yaml` includes a local hook that runs `bash sync.sh --check` on commits that touch files in `skills/`, `hooks/`, `templates/`, or `helpers/`.

- **R-010** [unit]: Both `templates/workflow-config.json` and `templates/workflow-config-full.json` include `commands.test_new` as an empty string field so new installs have it present.

### Slug Collision

- **R-011** [integration]: If a spec file already exists at `docs/specs/{slug}.md` or a state file with the same slug exists, `cmd_init` appends `-2` (or the next available number) to the slug before creating the state file.

## Won't Do

- Changing the state file naming convention (it uses the branch slug, not the spec slug — that's fine).
- Adding `--check` to CI — CI already runs `sync.sh && git diff --exit-code` which is equivalent.
- Retroactively fixing existing spec files with long slugs.

## Risks

- **R-001 slug truncation could collide** — two features starting with the same 4 tokens get the same slug. Mitigation: R-011 checks for existing files and appends a number.
- **R-003 `test_new` adds config complexity** — another field for users to understand. Mitigation: the field is optional and unused by default. `/cspec` or `/ctdd` could auto-populate it when creating a new test file.

## Open Questions

- None.
