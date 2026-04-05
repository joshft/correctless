# Architecture

## Trust Boundaries

### TB-001: Config-sourced commands and patterns
- **Crosses**: Configuration file → shell execution
- **Identity assertion**: Config written by human via /csetup or manual edit
- **Data sensitivity change**: Trusted config values → shell arguments
- **Invariant**: Config-sourced values must never be passed through eval, $(), or backtick execution. Commands validated via exact-match allowlist (auto-format.sh). Patterns matched via bash `case` glob only (sensitive-file-guard.sh).
- **Violated when**: A config value is interpolated into a shell command string or passed to eval
- **Test**: PRH-001 in sensitive-file-guard tests (canary file injection), INV-011 in auto-format tests (allowlist validation)

## Abstractions

(none yet)

## Patterns

### PAT-001: PreToolUse hook conventions
- **Pattern**: Standard structure for all PreToolUse hooks
- **Rule**: Every PreToolUse hook must: (1) `set -euo pipefail` + `set -f`, (2) check `command -v jq` with fail-closed exit 2, (3) bulk-parse stdin with single `eval` + `jq -r @sh`, (4) fast-path `exit 0` for non-relevant tools BEFORE loading config, (5) exit 0 to allow, exit 2 to block
- **Violated when**: A hook loads config before checking tool_name, uses multiple jq calls for stdin parsing, or exits non-0/non-2
- **Test**: INV-010 in sensitive-file-guard (corrupted config proves fast-path), workflow-gate.sh follows same structure

### PAT-002: Separate concerns in hooks
- **Pattern**: One hook per concern
- **Rule**: Each hook handles exactly one responsibility. workflow-gate.sh = phase gating, sensitive-file-guard.sh = file protection, auto-format.sh = formatting, audit-trail.sh = logging. Never merge hooks — they compose via Claude Code's hook runner.
- **Violated when**: A hook is modified to handle a second unrelated concern, or two hooks share runtime state
- **Test**: PRH-004 in sensitive-file-guard spec (architectural review — verify separate files exist)

## Environment Assumptions

### ENV-001: Bash 4+ required
- **Assumption**: All hooks use `${var,,}` (lowercase), `local -a` (arrays), and `[[ =~ ]]` (regex). Requires Bash 4.0+.
- **Consequence if wrong**: Silent failures — `${var,,}` produces empty string on Bash 3.x
- **Test**: Not runtime-checked. macOS ships Bash 3.2 by default; users must install Bash 4+ via Homebrew.

### ENV-002: jq required
- **Assumption**: `jq` is available on PATH for JSON parsing of hook stdin and config files.
- **Consequence if wrong**: workflow-gate.sh and sensitive-file-guard.sh exit 2 (fail-closed). auto-format.sh exits 0 (advisory).
- **Test**: Each hook checks `command -v jq` at startup.
