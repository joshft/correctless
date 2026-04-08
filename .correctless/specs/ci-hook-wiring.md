# Spec: CI Completeness and Hook Auto-Registration

## Metadata
- **Created**: 2026-04-08T12:00:00Z
- **Status**: approved
- **Impacts**: none
- **Branch**: feature/ci-hook-wiring
- **Research**: null
- **Intensity**: high
- **Intensity reason**: file path signal (hooks/, setup, .github/workflows/)
- **Override**: none

## Context

CI runs 6 of 25 test suites (76% coverage gap). Features merged against incomplete test gates — regressions in sensitive-file-guard, antipattern scanning, locking, and hook-sync bypass all CI checks. Additionally, `commands.test` in workflow-config.json only lists 20 of 25 test files on disk — 5 suites escape both CI and the config. Separately, setup's `register_hooks()` hardcodes hook names and matchers, missing sensitive-file-guard.sh and auto-format.sh entirely. New hooks require manual edits in multiple places. This feature closes all three gaps: CI runs all tests, config lists all tests, and setup auto-discovers hooks via metadata headers.

## Scope

**Covers:**
- Add all test suites to CI workflow
- Update `commands.test` to include all 25 test files on disk (currently missing 5), clear `commands.test_new`
- Add hook metadata headers (`HOOK_TYPE`, `HOOK_MATCHER`) to every hook
- Refactor `register_hooks()` to auto-discover hooks from metadata headers; remove matcher convergence block (lines 402-423) — matchers are now authoritative from HOOK_MATCHER headers
- Refactor `install_hooks()` to auto-discover hooks via glob (matching sync.sh pattern)
- Move auto-format.sh from `.claude/hooks/` to `hooks/` source directory; delete old copy at `.claude/hooks/auto-format.sh`
- ShellCheck CI job scans `scripts/` directory in addition to `hooks/`

**Does NOT cover:**
- Writing tests for untested hooks (workflow-advance.sh, audit-trail.sh) — separate feature
- Changing hook behavior — this is wiring only
- Auto-discovering scripts in setup (scripts/ install list) — separate concern, lower priority

## Complexity Budget
- **Estimated LOC**: ~80 net change
- **Files touched**: ~11 (ci.yml, setup, 7 hooks for metadata headers, auto-format.sh move, sync.sh for auto-format inclusion)
- **New abstractions**: 1 (hook metadata headers for auto-registration — ABS-004 and PAT-006 to be documented via /cupdate-arch)
- **Trust boundaries touched**: 0
- **Risk surface delta**: low (wiring changes, no new logic)

## Invariants

### INV-001: CI runs all test suites
- **Type**: must
- **Category**: functional
- **Statement**: `.github/workflows/ci.yml` runs every test file listed in the `commands.test` field of `workflow-config.json`. As a prerequisite, `commands.test` must include all `tests/test*.sh` files on disk (currently missing 5: test-hook-sync.sh, test-shift-left-review.sh, test-token-tracking.sh, test-token-tracking-setup.sh, test-workflow-gate.sh). `commands.test_new` must be empty after this feature merges — its contents are folded into `commands.test`.
- **Violated when**: A test file on disk matching `tests/test*.sh` is absent from `commands.test`, or a test file in `commands.test` is not run by CI
- **Test approach**: unit — parse ci.yml and workflow-config.json, compare test file lists; also verify every `tests/test*.sh` on disk appears in `commands.test`

### INV-002: Hook metadata headers present
- **Type**: must
- **Category**: functional
- **Statement**: Every hook in `hooks/` that is registered as a PreToolUse or PostToolUse hook contains `# HOOK_TYPE:` and `# HOOK_MATCHER:` comment headers in the first 10 lines. HOOK_TYPE is `PreToolUse` or `PostToolUse` only — no other values. HOOK_MATCHER is the pipe-separated tool list (e.g., `Edit|Write|Bash`). Files without these headers (workflow-advance.sh, statusline.sh) are excluded from auto-registration per INV-006/INV-007.
- **Violated when**: A hook file is missing either header, or the header value doesn't match `PreToolUse` or `PostToolUse`
- **Test approach**: unit — grep each hook for metadata headers, validate format

### INV-003: setup install_hooks() auto-discovers hooks
- **Type**: must
- **Category**: functional
- **Statement**: setup's `install_hooks()` discovers hooks by globbing `$SCRIPT_DIR/hooks/*.sh` instead of maintaining a hardcoded list. Adding a new hook file to hooks/ requires no setup code change.
- **Violated when**: install_hooks() contains hardcoded hook filenames
- **Test approach**: integration — create temp dirs, add a new .sh file to hooks/, run install_hooks(), verify the file was copied to .correctless/hooks/

### INV-004: setup register_hooks() reads metadata headers
- **Type**: must
- **Category**: functional
- **Statement**: setup's `register_hooks()` reads `HOOK_TYPE` and `HOOK_MATCHER` from each hook's metadata headers to generate the correct settings.json entries. No hardcoded hook-to-type/matcher mapping in setup. Timeout values use type-based defaults: PreToolUse=5000ms, PostToolUse=1000ms — this is a convention keyed on HOOK_TYPE, not a per-hook hardcoded mapping. The existing matcher convergence block (setup lines 402-423) is removed — matchers are now authoritative from HOOK_MATCHER headers.
- **Violated when**: register_hooks() contains hardcoded matcher strings for specific hook filenames, or timeout values are hardcoded per-hook rather than per-type
- **Test approach**: integration — run setup in a temp directory, verify settings.json contains entries for ALL hooks with correct types, matchers matching their metadata headers, and timeout values matching the type-based convention

### INV-005: auto-format.sh lives in hooks/ source directory
- **Type**: must
- **Category**: functional
- **Statement**: auto-format.sh exists in `hooks/` (source directory), is synced to `correctless/hooks/` via sync.sh, and has valid HOOK_TYPE/HOOK_MATCHER metadata headers. The old copy at `.claude/hooks/auto-format.sh` must be deleted to prevent duplicate hook execution. Test file path references in `tests/test-auto-format.sh` must be updated to the new location.
- **Violated when**: auto-format.sh only exists in `.claude/hooks/` or `correctless/hooks/` without a source copy in `hooks/`, or the old `.claude/hooks/auto-format.sh` still exists
- **Test approach**: unit — verify file exists in hooks/, verify `.claude/hooks/auto-format.sh` does not exist, verify sync.sh --check passes

### INV-006: Non-hook files excluded from registration
- **Type**: must
- **Category**: functional
- **Statement**: Files in `hooks/` that are NOT hooks (no HOOK_TYPE header) are installed (copied) but not registered in settings.json. This applies to scripts/lib.sh sourced files and any future non-hook utilities.
- **Violated when**: A non-hook file (e.g., a sourced library) appears as a hook entry in settings.json
- **Test approach**: integration — place a non-hook .sh file in hooks/ (no metadata), run setup, verify it's copied but not in settings.json

### INV-007: workflow-advance.sh and statusline.sh stay hardcoded
- **Type**: must
- **Category**: functional
- **Statement**: workflow-advance.sh (Bash permission) and statusline.sh (statusLine command) have NO HOOK_TYPE metadata header. They are excluded from auto-discovery by INV-006 (no header = not registered as a hook). Their settings.json entries (permission and statusLine) remain hardcoded in register_hooks() — they are structurally different from hooks, there are exactly two of them, and they won't drift.
- **Violated when**: workflow-advance.sh or statusline.sh gets a HOOK_TYPE header and is auto-registered as a PreToolUse/PostToolUse hook
- **Test approach**: integration — run setup, verify settings.json has permission entry for workflow-advance, statusLine entry for statusline, and neither appears as a PreToolUse/PostToolUse hook entry

### INV-008: ShellCheck CI scans scripts/ directory
- **Type**: must
- **Category**: functional
- **Statement**: The ShellCheck CI job scans both `hooks/` and `scripts/` directories, plus `sync.sh` and `setup`. Implementation note: `ludeeus/action-shellcheck`'s `scandir` accepts one directory — use `additional_files` to list `scripts/*.sh` individually, or change `scandir` to `.` with ignore patterns.
- **Violated when**: scripts/lib.sh or scripts/antipattern-scan.sh are not linted in CI
- **Test approach**: unit — verify ci.yml shellcheck config includes scripts/ directory

### INV-009: Existing setup behavior preserved
- **Type**: must
- **Category**: functional
- **Statement**: After refactoring, setup produces identical settings.json content for existing hooks (same matchers, same types, same timeout values). The only additions are sensitive-file-guard.sh and auto-format.sh entries that were previously missing.
- **Violated when**: An existing hook's matcher, type, or timeout changes after the refactoring
- **Test approach**: integration — capture settings.json before and after, verify existing entries unchanged

## Prohibitions

### PRH-001: No hardcoded hook filenames in setup for PreToolUse/PostToolUse hooks
- **Statement**: setup's install_hooks() and register_hooks() must not contain hardcoded hook filenames for PreToolUse/PostToolUse hooks. Discovery uses globs and metadata headers. **Exception**: workflow-advance.sh (permission entry) and statusline.sh (statusLine entry) remain hardcoded per INV-007 — they are structurally different from hooks and there are exactly two of them.
- **Detection**: grep setup for specific hook filenames inside install/register functions (excluding the INV-007 exceptions)
- **Consequence**: Adding a hook requires a setup code change, perpetuating the same drift pattern sync.sh just eliminated

### PRH-002: No test suites missing from CI
- **Statement**: Every `tests/test*.sh` file on disk must appear in `commands.test`, and every entry in `commands.test` must appear in ci.yml. CI must not silently skip test suites.
- **Detection**: compare test file lists between disk, config, and CI
- **Consequence**: Regressions bypass CI gates — the 76% gap that motivated this feature

## Open Questions

None.
