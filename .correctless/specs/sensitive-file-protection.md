# Spec: Sensitive File Protection Hook

## Metadata
- **Created**: 2026-04-04T23:00:00Z
- **Status**: approved
- **Impacts**: csetup (adds protected_files detection + hook registration)
- **Branch**: feature/sensitive-file-protection
- **Research**: null
- **Intensity**: high
- **Intensity reason**: hooks/ path pattern match, security keywords (credential, secret, token, certificate)
- **Override**: none

## Context

A PreToolUse hook that blocks the agent from modifying sensitive files — `.env`, credentials, private keys, certificates — regardless of workflow phase. The problem is accidental modification: the agent runs `Edit .env` to "fix" a config value and replaces a `${SECRET}` reference with a hardcoded test credential, or copies `.env` to `.env.example` without stripping real values. The gitleaks pre-commit hook catches committed secrets; this hook prevents the modification that creates the problem. If the agent needs to touch a sensitive file, the human does it manually.

## Scope

**Covers:**
- New hook script (`sensitive-file-guard.sh`) registered as PreToolUse on Edit|Write|MultiEdit|NotebookEdit|CreateFile|Bash, registered BEFORE workflow-gate.sh in settings.json
- Hardcoded default patterns for common sensitive files (.env, keys, credentials, etc.)
- Custom patterns via `protected_files.custom_patterns` in `workflow-config.json`
- Bash command interception — blocking `cat > .env`, `cp secrets.json`, etc.
- `/csetup` detection of project-specific sensitive files and custom pattern configuration

**Does NOT cover:**
- Content scanning (detecting secrets inside arbitrary files) — stays in gitleaks pre-commit
- Read blocking — the agent can still read `.env` to understand structure, it just can't write to it
- Git operations — `git checkout .env` or `git restore .env` are not intercepted (these restore, not create)
- Lock files — agents run package managers, they don't hand-edit lock files

## Complexity Budget
- **Estimated LOC**: ~100 (hook script) + ~30 (csetup changes) + ~150 (tests)
- **Files touched**: ~4 (hook script, workflow-config template, settings registration, test file)
- **New abstractions**: 0
- **Trust boundaries touched**: 1 (config-sourced patterns — mitigated by glob-only matching, no eval)
- **Risk surface delta**: low (reduces attack surface — blocks writes to sensitive files)

## Invariants

### INV-001: Hook blocks Edit, Write, MultiEdit, NotebookEdit, and CreateFile targeting sensitive files
- **Type**: must
- **Category**: security
- **Statement**: When tool_name is Edit, Write, MultiEdit, NotebookEdit, or CreateFile and the target file_path matches a protected pattern, the hook must exit 2 with a BLOCKED message on stderr explaining which pattern matched and why. For MultiEdit, every file_path in the edits array must be checked — if any match, the entire operation is blocked.
- **Violated when**: An Edit/Write/MultiEdit/NotebookEdit/CreateFile to a .env file is allowed through
- **Test approach**: integration — feed hook JSON with protected file paths for each tool type, verify exit 2

### INV-002: Hook blocks Bash commands that write to sensitive files
- **Type**: must
- **Category**: security
- **Statement**: When tool_name is Bash and the command contains a write pattern (redirect, cp, mv, tee, sed -i, etc.) targeting a protected file path, the hook must exit 2. Write-pattern detection reuses the same approach as workflow-gate.sh (`_has_write_pattern`). File extraction must handle extensionless files (`.env`, `id_rsa`, etc.) — unlike workflow-gate.sh's extension-based grep, this hook must extract all non-flag tokens after write operators and match them against protected patterns.
  - **Guaranteed detection**: `cat x > .env`, `cp .env backup`, `mv .env .env.bak`, `tee .env`, `sed -i s/x/y/ .env`, `echo x >> .env`, redirects targeting protected paths
  - **Best-effort (gitleaks mitigates)**: variable expansion (`echo x > $FILE`), command substitution (`echo x > "$(cmd)"`), heredocs (`cat <<EOF > .env`)
- **Violated when**: `cat "creds" > .env` or `cp template.env .env` is allowed through Bash
- **Test approach**: integration — feed hook JSON with Bash commands targeting protected files, test both guaranteed and best-effort patterns

### INV-003: Hook allows Read, Grep, Glob, and non-write Bash operations on sensitive files
- **Type**: must
- **Category**: functional
- **Statement**: The hook must not block read-only operations. `cat .env` (no redirect), `grep SECRET .env`, and Read/Grep/Glob tools targeting .env must all be allowed. The agent needs to read sensitive files to understand structure.
- **Violated when**: A Read or non-write Bash command targeting .env is blocked
- **Test approach**: integration — verify Read tool and non-write Bash commands pass through

### INV-004: Hook uses hardcoded default patterns
- **Type**: must
- **Category**: security
- **Statement**: The hook must include a hardcoded set of default patterns that protect common sensitive files without any configuration. Defaults: `.env`, `.env.*`, `*.pem`, `*.key`, `*.p12`, `*.pfx`, `credentials.json`, `credentials.yml`, `service-account*.json`, `*.secret`, `*.secrets`, `secrets.yml`, `secrets.yaml`, `secrets.json`, `.secrets`, `id_rsa`, `id_rsa.*`, `id_ed25519`, `id_ed25519.*`, `*.keystore`, `*.jks`. These defaults apply even when no workflow-config.json exists.
- **Violated when**: A project with no config file allows writing to .env
- **Test approach**: integration — run hook without config, verify .env is blocked

### INV-005: Hook supports custom patterns from config
- **Type**: must
- **Category**: functional
- **Statement**: Custom patterns from `protected_files.custom_patterns` array in workflow-config.json are added to the default patterns. Custom patterns use the same glob syntax as defaults (basename matching with `*` wildcards). Custom patterns extend defaults — they cannot remove defaults.
- **Violated when**: A custom pattern in config is not enforced, or adding custom patterns disables defaults
- **Test approach**: integration — add custom pattern to config, verify it blocks, verify defaults still active

### INV-006: Hook exits 0 for non-sensitive files
- **Type**: must
- **Category**: functional
- **Statement**: Files that do not match any protected pattern must be allowed through (exit 0). The hook must not interfere with normal editing.
- **Violated when**: A regular source file is blocked by the sensitive file hook
- **Test approach**: integration — verify .ts, .py, .sh, .go files pass through

### INV-007: Hook matches on basename, not full path, with case-insensitive comparison
- **Type**: must
- **Category**: security
- **Statement**: Pattern matching uses two rules based on pattern content:
  1. **Basename patterns** (no `/` in pattern): Match against file basename only. Pattern `.env` matches `src/.env`, `config/.env`, `/home/user/.env`.
  2. **Full-path patterns** (contains `/`): Match against the full relative path. Pattern `config/prod.yml` matches `src/config/prod.yml`.
  Both branches use `${basename,,}` lowercase normalization before matching, so `.ENV`, `.Env`, and `.env` all match the `.env` pattern. Patterns themselves are stored lowercase.
- **Violated when**: `/path/to/project/.env` is not caught by the `.env` pattern, or `.ENV` bypasses the `.env` pattern
- **Test approach**: integration — verify .env is blocked regardless of directory depth; verify case-insensitive matching (.ENV, .Env)

### INV-008: Hook message identifies the matched pattern
- **Type**: must
- **Category**: functional
- **Statement**: The BLOCKED message on stderr must include the file path that triggered the block and the pattern that matched, so the human understands why. Format: `BLOCKED [sensitive-file]: {filepath} matches protected pattern '{pattern}'. Edit sensitive files manually.`
- **Violated when**: Block message is generic without identifying which pattern matched
- **Test approach**: integration — capture stderr and verify pattern identification

### INV-009: Hook is independent of workflow state
- **Type**: must
- **Category**: security
- **Statement**: The hook must block sensitive file modifications regardless of whether a workflow is active, which phase it's in, or whether an override is active. There is no override mechanism for this hook — workflow-gate.sh overrides do not apply here.
- **Violated when**: A sensitive file write is allowed because no workflow is active, or because an override is set
- **Test approach**: integration — verify blocking with no state file, with override active, in every phase

### INV-010: Hook exits 0 always for non-write tools without loading config
- **Type**: must
- **Category**: functional
- **Statement**: For tool_name values other than Edit, Write, MultiEdit, NotebookEdit, CreateFile, and Bash, the hook must exit 0 immediately without loading config or performing any pattern matching. This is a fast-path bail for the common case (Read, Grep, Glob, etc.).
- **Violated when**: Hook loads config or does pattern checking for Read or Grep tools
- **Test approach**: integration — feed hook Read/Grep/Glob JSON with a corrupted (invalid JSON) config file; verify exit 0 (proving config was never loaded)

## Prohibitions

### PRH-001: Never use eval on pattern strings
- **Statement**: Protected file patterns from config must never be passed through eval, $(), or backtick execution. Patterns are matched using bash `case` glob matching only. This prevents command injection via malicious config values.
- **Detection**: grep hook script for eval, $(), backtick in pattern-matching code paths
- **Consequence**: A malicious pattern like `$(rm -rf /)` would execute as a command

### PRH-002: Never block read operations
- **Statement**: The hook must never block Read, Grep, or Glob tools, or non-write Bash commands. The agent needs to read sensitive files to understand project structure.
- **Detection**: test with Read tool targeting .env — must exit 0
- **Consequence**: Blocking reads would prevent the agent from understanding config file structure, making it unable to help with related tasks

### PRH-003: Never allow overrides for sensitive file protection
- **Statement**: Unlike workflow-gate.sh, this hook has no override mechanism. The `workflow-advance.sh override` command does not affect this hook. If the agent needs to modify a sensitive file, the human does it manually.
- **Detection**: grep for override-related code in the hook
- **Consequence**: An override mechanism defeats the purpose — the agent should never touch these files

### PRH-004: Never merge into workflow-gate.sh
- **Statement**: This hook must remain a separate script from workflow-gate.sh. Workflow-gate enforces phase restrictions; this hook enforces file restrictions. Separate concerns, separate hooks, independently testable.
- **Detection**: architectural review — verify separate files exist
- **Consequence**: Merged hooks become harder to test, harder to reason about, and harder to disable independently

## Boundary Conditions

### BND-001: File path with spaces or special characters
- **Input from**: Claude Code tool invocation (file_path field)
- **Validation required**: Pattern matching via bash `case` with glob — inherently handles special characters in filenames. No string splitting or eval.
- **Failure mode**: fail-closed — if pattern matching fails for any reason, block the write (exit 2)

### BND-002: Empty or missing file_path in tool input
- **Input from**: Malformed tool invocation
- **Validation required**: Check for empty/missing file_path before matching
- **Failure mode**: exit 0 — a write tool with no file_path will fail independently (Claude Code requires file_path for Edit/Write/CreateFile). The hook doesn't need to catch this case; it has no path to match against.

### BND-003: No workflow-config.json exists or config is malformed
- **Input from**: Projects that haven't run /csetup, or corrupted config
- **Validation required**: Config file check before reading custom patterns. On config read failure (missing file, invalid JSON, missing keys), proceed with hardcoded defaults only — never exit 0 before checking defaults.
- **Failure mode**: fail-closed on defaults — hardcoded defaults always apply regardless of config state. The hook must structure its logic so that defaults are checked even when config parsing fails entirely.

### BND-004: Bash command with multiple file targets
- **Input from**: `cp .env .env.backup` or `cat file1 file2 > .env`
- **Validation required**: Extract all file-like tokens from the Bash command and check each against protected patterns. If any target is protected, block the entire command.
- **Failure mode**: fail-closed — block if any extracted target matches

### BND-005: Symlink to a sensitive file
- **Input from**: Agent edits `config/settings` which is a symlink to `.env`
- **Validation required**: The hook matches on the path as provided, not the resolved symlink target. This means a symlink named `settings` pointing to `.env` would NOT be caught. Accepted limitation — content scanning (gitleaks) catches the committed result.
- **Failure mode**: Not blocked — accepted limitation, documented

## Environment Assumptions

- **EA-001**: PreToolUse hooks receive JSON on stdin: `{"tool_name": "...", "tool_input": {"file_path": "...", "command": "..."}}`. Each hook process receives its own independent stdin pipe.
- **EA-002**: Bash 4+ is available (`#!/usr/bin/env bash`). The `${var,,}` lowercase syntax is used for case-insensitive matching. `set -f` must be active to prevent glob expansion of patterns in `case` statements — critical for safe pattern matching.
- **EA-003**: Both this hook and workflow-gate.sh run as PreToolUse hooks. Claude Code runs all registered PreToolUse hooks for a matching tool — if any exits 2, the operation is blocked. **Execution model**: It is not confirmed whether Claude Code short-circuits on the first exit 2 or runs all hooks regardless. Under either model, the security guarantee holds: (a) if all hooks run, both get their say regardless of order; (b) if short-circuit on exit 2, an exit 0 from one hook still lets the other run — only exit 2 stops the chain, which already blocks the operation. Registration order therefore affects error message ordering, not security. sensitive-file-guard.sh is registered before workflow-gate.sh by convention (sensitive file message shown first), not as a security requirement.
- **EA-004**: `jq` is required for JSON parsing of stdin and config. The hook must check for jq availability and exit 2 (fail-closed) with a descriptive error if missing — same pattern as workflow-gate.sh line 18.

## Config Schema

The `protected_files` section is a top-level key in `workflow-config.json` (same level as `auto_format`, `workflow`, `patterns`):

```json
{
  "protected_files": {
    "custom_patterns": [".env.local", "config/production.yml", "*.tfvars"]
  }
}
```

When `protected_files` is absent or `custom_patterns` is absent/empty, only hardcoded defaults apply. Invalid JSON or wrong types cause config parse failure — hook falls back to hardcoded defaults only (per BND-003).

## Design Decisions

- **Basename matching, not full-path matching**: Sensitive file names like `.env` should be caught at any depth. Full-path patterns (containing `/`) are supported for project-specific overrides like `config/production.yml`.
- **Case-insensitive matching**: All filenames are lowercased via `${var,,}` before matching. `.ENV`, `.Env`, and `.env` all match. Patterns are stored and compared in lowercase.
- **Defaults cannot be removed via config**: Custom patterns extend, they don't replace. A user who removes `.env` from their config still gets the hardcoded defaults. This is intentional — the defaults exist because forgetting to protect `.env` is the most common case.
- **No override mechanism**: Workflow-gate.sh has overrides because phase restrictions are sometimes wrong (the agent legitimately needs to edit a file the phase says it shouldn't). Sensitive file protection has no such case — the agent should never modify `.env`. If needed, the human does it.
- **Bash write detection reuses workflow-gate.sh pattern, file extraction does not**: The `_has_write_pattern` detection from workflow-gate.sh already handles write detection (redirects, cp, mv, tee, sed -i, etc.). This hook reuses the same approach. However, file target extraction is different — workflow-gate.sh's `get_target_file` only matches files with known extensions, which misses extensionless sensitive files like `.env` and `id_rsa`. This hook extracts all non-flag tokens after write operators.
- **Hook registration order is convention, not security**: sensitive-file-guard.sh is registered before workflow-gate.sh by convention so the sensitive file message appears first. The security guarantee does not depend on order — under both execution models (all-hooks-run or short-circuit-on-block), each hook independently evaluates the operation. An exit 0 from workflow-gate.sh in `done` phase does not prevent sensitive-file-guard from running.

## Risks

- **False negatives from specific secret patterns**: The patterns `*.secret`, `secrets.json`, etc. won't catch a file named `my-api-secret-key.txt`. This is intentional — the wildcard `*secret*` would flag too many legitimate files (`test_secret_rotation.go`, `docs/secret-management.md`, `src/utils/secretParser.ts`). Users can add project-specific patterns via `protected_files.custom_patterns`. **Accepted risk** — precision over recall, gitleaks catches the rest.
- **Bash command extraction is heuristic**: The token extraction from Bash commands can miss complex shell constructs (heredocs, subshells, variable expansion). Gitleaks pre-commit catches what this misses. **Accepted risk** — defense in depth with gitleaks.

## Open Questions

None — scope is clear from brainstorm.
