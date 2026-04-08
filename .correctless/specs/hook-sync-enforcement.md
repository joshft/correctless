# Spec: Deterministic Hook Synchronization

## Metadata
- **Created**: 2026-04-07T22:00:00Z
- **Status**: approved
- **Impacts**: none
- **Branch**: feature/hook-sync-enforcement
- **Research**: null
- **Intensity**: high
- **Intensity reason**: file path signal (hooks/)
- **Override**: none

## Context

sync.sh hardcodes hook and script filenames in its sync loops. Every time a hook or script is added, someone forgets to update the list — the audit has caught this drift 3 times. Separately, write-command patterns and file extension regexes are duplicated across workflow-gate.sh, sensitive-file-guard.sh, and audit-trail.sh with prompt-based enforcement to keep them synchronized. This feature replaces both hardcoded lists and duplicated patterns with structural solutions: glob-based auto-discovery in sync.sh, and shared functions in scripts/lib.sh (extending ABS-001).

## Scope

**Covers:**
- sync.sh hook and script auto-discovery via shell globs
- Extraction of `_has_write_pattern()` and `get_target_file()` into `scripts/lib.sh`
- Refactoring consuming hooks to use lib.sh shared functions (lib.sh already sourced by these hooks)
- sync.sh `--check` stale file detection for hooks and scripts
- Consolidation note: `python|python3|node|ruby` were already detected by workflow-gate.sh (separate case line). Moving them into the shared `_has_write_pattern()` preserves existing behavior, not a behavioral change.

**Does NOT cover:**
- Template auto-discovery (templates have specific destination mappings, different structure)
- Skill auto-discovery (already has stale-detection code in sync.sh lines 99-114)
- Patterns used by only one hook (e.g., sensitive-file-guard.sh's path-matching patterns are unique to that hook)
- Case normalization — `${var,,}` is bash syntax used consistently across all hooks; there's no data to extract
- Interpreter flag detection (`python -c` vs `python script.py`) — overrides already handle edge cases

## Complexity Budget
- **Estimated LOC**: ~60 net change (most is refactoring existing code)
- **Files touched**: ~6 (sync.sh, scripts/lib.sh, hooks/workflow-gate.sh, hooks/sensitive-file-guard.sh, hooks/audit-trail.sh, tests)
- **New abstractions**: 0 (extends ABS-001 lib.sh)
- **Trust boundaries touched**: 0
- **Risk surface delta**: low (refactoring, no new capabilities; lib.sh is already a dependency of all consuming hooks)

## Invariants

### INV-001: sync.sh hook auto-discovery
- **Type**: must
- **Category**: functional
- **Statement**: sync.sh discovers hooks by globbing `hooks/*.sh` instead of maintaining a hardcoded list. Adding a new .sh file to hooks/ and running sync.sh copies it to correctless/hooks/ without any code change to sync.sh.
- **Violated when**: sync.sh requires a code edit to sync a new hook file
- **Test approach**: integration — create temp .sh file in hooks/, run sync.sh, verify it appears in correctless/hooks/

### INV-002: sync.sh script auto-discovery
- **Type**: must
- **Category**: functional
- **Statement**: sync.sh discovers scripts by globbing `scripts/*.sh` instead of maintaining a hardcoded list. Adding a new .sh file to scripts/ and running sync.sh copies it to correctless/scripts/ without any code change to sync.sh.
- **Violated when**: sync.sh requires a code edit to sync a new script file
- **Test approach**: integration — create temp .sh file in scripts/, run sync.sh, verify it appears in correctless/scripts/

### INV-003: lib.sh defines canonical write-detection patterns
- **Type**: must
- **Category**: functional
- **Statement**: scripts/lib.sh defines `_has_write_pattern()` function containing the union of all write-command tokens from workflow-gate.sh and sensitive-file-guard.sh: redirect regex `>>|[0-9]*>`, token list (`cp|mv|tee|install|rm|rmdir|unlink|dd|curl|wget|rsync|patch|truncate|shred|ln|python|python3|node|ruby`), and `sed -i`/`perl -i` checks. Every individual token must be tested.
- **Violated when**: Any write-command token from either hook's current implementation is missing from the shared function
- **Test approach**: unit — source lib.sh, call `_has_write_pattern` with every token in the list (positive cases) and known non-write commands (negative cases: cat, ls, git, grep)

### INV-004: lib.sh defines canonical file extraction function
- **Type**: must
- **Category**: functional
- **Statement**: scripts/lib.sh defines `get_target_file()` function that wraps the `grep -oE` call with the 25-extension regex pattern currently duplicated across hooks. Callers use `FILES="$(get_target_file "$COMMAND")"` instead of inline grep. The function encapsulates both the regex and the grep invocation.
- **Violated when**: The function is missing, returns different results than the current inline grep, or the regex doesn't match all 25 extensions (go, ts, tsx, js, jsx, py, rs, java, rb, cpp, c, h, sh, json, md, yaml, yml, toml, cfg, ini, sql, css, html, vue, svelte)
- **Test approach**: unit — call `get_target_file` with commands containing each extension, verify matches; call with non-matching extensions (.lock, .png, .wasm), verify no match

### INV-005: Consuming hooks use lib.sh shared functions
- **Type**: must
- **Category**: functional
- **Statement**: workflow-gate.sh and sensitive-file-guard.sh use `_has_write_pattern()` from lib.sh. workflow-gate.sh and audit-trail.sh use `get_target_file()` from lib.sh. These hooks already source lib.sh — no additional source statement needed. The Bash command fast-path in PreToolUse hooks checks tool_name before lib.sh is sourced; `_has_write_pattern()` is called only after lib.sh sourcing for Bash tool inputs.
- **Violated when**: A consuming hook calls `_has_write_pattern()` or extracts files with inline regex instead of using the lib.sh functions
- **Test approach**: unit — grep each consuming hook for the function calls; verify no inline `_has_write_pattern` definition or file-extension regex. Integration — craft a Bash write-command JSON payload, feed to each hook, verify write detection works through the lib.sh path

### INV-006: Source guard tests exercise the actual guard path
- **Type**: must
- **Category**: functional
- **Statement**: Tests for lib.sh source failure must supply JSON payloads that navigate past all fast-path exits (valid JSON, Bash tool_name with write command for PreToolUse, valid tool input for PostToolUse) to reach the code path that calls `_has_write_pattern()` or `get_target_file()`. PreToolUse hooks exit 2 when lib.sh is missing (fail-closed per PAT-001). PostToolUse hooks exit 0 (fail-open per PAT-005).
- **Violated when**: A test passes by hitting an early exit 0 instead of exercising the source guard path
- **Test approach**: integration — for workflow-gate.sh: provide `{"tool_name":"Bash","tool_input":{"command":"cp a b"}}` with valid state file in a blocking phase, remove lib.sh, verify exit 2. For audit-trail.sh: provide `{"tool_name":"Bash","tool_input":{"command":"cp a.ts b.ts"}}`, remove lib.sh, verify exit 0

### INV-007: Existing behavior unchanged plus characterization coverage
- **Type**: must
- **Category**: functional
- **Statement**: All existing tests for workflow-gate.sh, sensitive-file-guard.sh, and audit-trail.sh continue to pass. Additionally, characterization tests verify that `_has_write_pattern()` produces identical results to the current inline definitions for every command in both hooks' token lists, and `get_target_file()` matches the same extensions as the current inline regex.
- **Violated when**: Any existing test fails, or a characterization test shows behavioral divergence between the shared function and the original inline code
- **Test approach**: integration — run full existing test suite. Unit — characterization test calling `_has_write_pattern` with all tokens from workflow-gate.sh:59 and sensitive-file-guard.sh:76, asserting identical results. Note: python/python3/node/ruby were already present in workflow-gate.sh (separate case line) — consolidation preserves existing behavior.

### INV-008: sync.sh --check detects stale distribution files
- **Type**: must
- **Category**: functional
- **Statement**: sync.sh --check mode detects stale files — if correctless/hooks/ contains a .sh file that doesn't exist in hooks/, or correctless/scripts/ contains a .sh file that doesn't exist in scripts/, --check exits 1 (dirty). Requires new stale-detection loops for hooks/ and scripts/, following the existing skills stale-detection pattern (sync.sh lines 100-113).
- **Violated when**: A deleted source file's distribution copy is not flagged by --check
- **Test approach**: integration — add orphan file to correctless/hooks/ with no source counterpart, run sync.sh --check, verify exit 1. Same for correctless/scripts/. Also test clean case (no stale files, exit 0).

## Prohibitions

### PRH-001: No hardcoded filenames in sync loops
- **Statement**: sync.sh hook and script sync loops must not contain hardcoded filenames. They must use shell globs exclusively.
- **Detection**: grep sync.sh for `for hook in` and `for script in` patterns, verify the loop variable comes from a glob not a string list
- **Consequence**: Adding a hook or script requires a sync.sh code change, perpetuating the drift that caused 3 audit findings

### PRH-002: No local pattern definitions in consuming hooks
- **Statement**: No hook may define `_has_write_pattern()` locally or hardcode the file extension regex inline. All write-detection patterns must come from scripts/lib.sh.
- **Detection**: grep hooks/*.sh for `_has_write_pattern()` function definitions and the 25-extension regex pattern, verify no matches outside scripts/lib.sh
- **Consequence**: Pattern drift between hooks — the exact problem this feature eliminates

## Open Questions

None — scope is well-defined from brainstorm and review.
