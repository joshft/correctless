# Spec: Auto-Format PostToolUse Hooks

## Metadata
- **Created**: 2026-04-04T22:00:00Z
- **Status**: reviewed
- **Impacts**: csetup (adds formatter detection + hook registration)
- **Branch**: feature/auto-format-hooks
- **Research**: null
- **Intensity**: high
- **Intensity reason**: hooks/ path pattern match, existing hook infrastructure
- **Override**: none

## Context

A PostToolUse hook that runs the project's formatter after every Edit/Write/MultiEdit tool invocation. Eliminates formatting-related QA findings — the most common low-value finding category — by making formatting automatic and invisible. The agent is notified via stderr that formatting occurred, preventing confusion when file contents change between write and next read.

## Scope

**Covers:**
- New hook script (`auto-format.sh`) registered as PostToolUse on Edit|Write|MultiEdit
- `/csetup` detection of 6 formatters (Prettier, ESLint, Black, Ruff, gofmt, rustfmt)
- Conflict resolution when both Prettier and ESLint are detected (default Prettier, user can switch)
- `workflow-config.json` config section for auto-format settings
- stderr notification to agent after formatting
- This is the first PostToolUse hook entry in settings.json — /csetup must create the PostToolUse array

**Does NOT cover:**
- Linting (ESLint without --fix, pylint, etc.) — separate concern
- Pre-commit formatting — already handled by pre-commit hooks
- Formatting on Bash tool output — only Edit/Write/MultiEdit triggers the hook
- Custom formatter support beyond the 6 detected — user can configure manually via the command field
- Sandboxing formatter plugins (e.g., Prettier's plugin system) — supply chain attacks on the formatter itself are out of scope

## Complexity Budget
- **Estimated LOC**: ~80 (hook script) + ~40 (csetup changes) + ~120 (tests)
- **Files touched**: ~5 (hook, csetup SKILL.md, workflow-config template, settings template, test file)
- **New abstractions**: 0
- **Trust boundaries touched**: 1 (config-sourced commands — mitigated by allowlist)
- **Risk surface delta**: low-medium

## Invariants

### INV-001: Hook only triggers on Edit, Write, and MultiEdit tools
- **Type**: must
- **Category**: functional
- **Statement**: The auto-format hook must only execute when the tool_name is Edit, Write, or MultiEdit. It must not trigger on Read, Grep, Glob, Bash, or any other tool.
- **Violated when**: Hook runs formatting on a non-Edit/Write/MultiEdit tool invocation
- **Test approach**: integration — feed hook JSON with various tool_name values, verify exit behavior

### INV-002: Hook formats only the specific file that was edited
- **Type**: must
- **Category**: functional
- **Statement**: The hook must extract the file_path from the tool invocation and pass only that single file to the formatter using array-based execution (`"$formatter" "$filepath"`). It must never run a project-wide format. For MultiEdit, format each file_path from the edits array individually.
- **Violated when**: Formatter receives a directory or glob instead of a single file path
- **Test approach**: integration — verify the formatter command receives exactly the file_path from stdin

### INV-003: Hook exits 0 regardless of formatter outcome
- **Type**: must
- **Category**: functional
- **Statement**: The hook must exit 0 even if the formatter is not installed, crashes, or returns a non-zero exit code. The hook wraps the formatter invocation with `timeout 5` to prevent hangs. Formatting failure must never block the edit.
- **Violated when**: Hook exits non-zero, causing Claude Code to report a hook failure
- **Test approach**: integration — test with missing formatter binary, crashing formatter, non-zero exit, timeout

### INV-004a: Hook notifies agent via stderr when formatter runs
- **Type**: must
- **Category**: functional
- **Statement**: When the formatter is invoked and exits 0, the hook must write a short notification to stderr (e.g., "Formatted {filename} with {formatter}").
- **Violated when**: Formatter runs successfully but no stderr notification is produced
- **Test approach**: integration — capture stderr after successful formatter invocation

### INV-004b: Hook produces no output when formatter is skipped
- **Type**: must
- **Category**: functional
- **Statement**: When the formatter is not configured, not installed, or the file type doesn't match any configured extension, no stderr output is produced.
- **Violated when**: stderr output appears when no formatting occurred
- **Test approach**: integration — verify silent exit for unmatched extensions and missing formatters

### INV-005: Hook checks formatter is installed before running
- **Type**: must
- **Category**: functional
- **Statement**: The hook must verify the formatter binary exists in PATH (via `command -v`) before attempting to run it. If the binary is not found, the hook exits silently with 0.
- **Violated when**: Hook attempts to run a formatter that isn't installed, producing error output
- **Test approach**: integration — test with formatter not in PATH

### INV-006: Formatter selection is file-extension based
- **Type**: must
- **Category**: functional
- **Statement**: The hook must determine which formatter to run based on the edited file's extension, not a global setting. A project with both Prettier and Black configured must format .ts files with Prettier and .py files with Black.
- **Violated when**: A Python file is formatted with Prettier or a TypeScript file with Black
- **Test approach**: integration — temp project with workflow-config.json mapping .ts to prettier-stub and .py to black-stub; verify correct stub called per extension

### INV-007: Config stores formatter settings
- **Type**: must
- **Category**: functional
- **Statement**: `workflow-config.json` must contain an `auto_format` section with `enabled` (boolean), and `formatters` (object mapping extension patterns to commands). The hook reads this config to determine what to run.
- **Violated when**: Hook uses hardcoded formatter commands instead of reading config
- **Test approach**: integration — verify hook reads from config, test with various config shapes

### INV-008: /csetup detects all 6 formatters
- **Type**: must
- **Category**: functional
- **Statement**: `/csetup` must detect Prettier (.prettierrc, package.json devDeps), ESLint (.eslintrc, eslint.config.js), Black (pyproject.toml [tool.black]), Ruff (ruff.toml, pyproject.toml [tool.ruff]), gofmt (go.mod), and rustfmt (Cargo.toml) by checking for their config files.
- **Violated when**: A formatter with its config file present is not detected
- **Test approach**: doc audit — verify csetup SKILL.md contains detection instructions for all 6

### INV-009: Prettier is default when both Prettier and ESLint detected
- **Type**: must
- **Category**: functional
- **Statement**: When both Prettier and ESLint are detected for JS/TS files, `/csetup` must default to Prettier for formatting and present the user with the option to switch to ESLint --fix. The user's choice is stored in config and can be changed later.
- **Violated when**: ESLint is selected by default without user action, or no choice is presented
- **Test approach**: doc audit — verify csetup SKILL.md describes the conflict resolution with Prettier default

### INV-010: Hook respects enabled flag
- **Type**: must
- **Category**: functional
- **Statement**: When `auto_format.enabled` is `false` in workflow-config.json, the hook must exit immediately without running any formatter. When the field is absent, the hook must treat it as disabled (not enabled by default).
- **Violated when**: Hook formats files when auto_format.enabled is false or absent
- **Test approach**: integration — test with enabled=false, enabled=true, field absent

### INV-011: Formatter command validated against allowlist
- **Type**: must
- **Category**: security
- **Statement**: The hook must validate the formatter command from config against an allowlist of known formatter binaries: `prettier`, `npx prettier`, `eslint`, `npx eslint`, `black`, `ruff`, `gofmt`, `rustfmt`. Commands containing `|`, `;`, `$()`, backticks, or any shell metacharacters must be rejected. When validation fails, the hook exits silently with 0 and does not execute the command.
- **Violated when**: A command not in the allowlist is executed, or a command with shell metacharacters is executed
- **Test approach**: integration — test with valid commands, injected commands, commands with pipes/semicolons

## Prohibitions

### PRH-001: Never run project-wide formatting
- **Statement**: The hook must never run a formatter without a specific file path argument (e.g., `prettier .` or `black .`). Only the single edited file is formatted.
- **Detection**: grep hook script for formatter invocations without $FILEPATH
- **Consequence**: Reformatting the entire project on every edit would be catastrophically slow and produce massive diffs

### PRH-002: Never block the edit
- **Statement**: The hook must never return a non-zero exit code or a `{"decision": "block"}` response. Auto-formatting is advisory, not gating.
- **Detection**: grep for exit codes != 0 in non-error paths
- **Consequence**: Blocking edits due to formatter issues would halt the agent's work

### PRH-003: Never format files the formatter doesn't understand
- **Statement**: The hook must not pass files with unrecognized extensions to a formatter. A .sh file must not be sent to Prettier. Extension matching determines eligibility.
- **Detection**: test with unsupported file extensions
- **Consequence**: Formatters may corrupt files with unfamiliar syntax (e.g., Prettier mangling a shell script)

### PRH-004: Never use string interpolation for formatter execution
- **Statement**: The hook must never construct the formatter command via string interpolation (e.g., `eval "$command $filepath"` or `$command $filepath`). All formatter invocations must use array-based execution to prevent shell injection via file paths.
- **Detection**: grep for eval, unquoted $command, or string concatenation patterns in the execution path
- **Consequence**: Shell injection via crafted file paths

## Boundary Conditions

### BND-001: File path with spaces or special characters
- **Input from**: Claude Code tool invocation (file_path field)
- **Validation required**: File path passed to formatter via array-based execution (`"$formatter" "$filepath"`) — no string interpolation. This prevents injection regardless of path content.
- **Failure mode**: fail-closed — if file does not exist at the path, skip formatting

### BND-002: File deleted between edit and format
- **Input from**: Filesystem race condition
- **Validation required**: Check file exists before running formatter
- **Failure mode**: fail-closed — exit 0 silently

### BND-003: No workflow-config.json exists
- **Input from**: Projects that haven't run /csetup
- **Validation required**: Check config file exists
- **Failure mode**: fail-closed — exit 0, no formatting without config

### BND-004: Formatter modifies file during concurrent edit
- **Input from**: Theoretical race between PostToolUse formatter and next tool call
- **Validation required**: None — Claude Code's tool execution is linear. The next tool call does not start until the PostToolUse hook (including the formatter) completes. This is safe by design.
- **Failure mode**: N/A — non-issue in practice. Documented to prevent someone making the hook async later and breaking the sequential execution assumption.

## Environment Assumptions

- **EA-001**: PostToolUse hooks receive the same JSON shape as PreToolUse: `{"tool_name": "...", "tool_input": {"file_path": "...", ...}}` on stdin. Each hook process receives its own independent stdin pipe — no contention between multiple PostToolUse hooks.
- **EA-002**: Bash 4+ is available (`#!/usr/bin/env bash`). No Windows/PowerShell support.
- **EA-003**: `command -v` correctly identifies formatter binaries in PATH. Broken symlinks or wrapper scripts may pass detection but fail at runtime — handled by INV-003 (exit 0 on failure).

## Risks

- **Prettier plugin RCE**: Prettier loads plugins from `.prettierrc`. A malicious plugin achieves code execution when the hook invokes Prettier. This is a supply chain attack on the formatter, not on the hook. The hook cannot sandbox formatter internals. **Accepted risk** — document in antipatterns as a known limitation of auto-formatting.
- **Config file false positives**: Presence of `go.mod` does not guarantee gofmt is the desired formatter. `/csetup` uses config files as a detection heuristic, confirmed by user during setup. **Mitigated** — user confirms during `/csetup`.

## Open Questions

None — scope is clear from brainstorm and review.
