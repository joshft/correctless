# Spec: Infrastructure Hardening

## Metadata
- **Created**: 2026-04-06T22:30:00Z
- **Status**: reviewed
- **Impacts**: none (new test files + targeted changes to existing hooks)
- **Branch**: feature/hardening-tests
- **Research**: null
- **Intensity**: high
- **Intensity reason**: file path signal (hooks/), project floor (workflow.intensity=high)
- **Override**: none

## Context

The three most critical infrastructure components — `scripts/lib.sh`, `hooks/workflow-advance.sh`, and `hooks/workflow-gate.sh` — have gaps in testing, a missing defense-in-depth mechanism, and a self-blocking enforcement failure. lib.sh (7 functions sourced by every hook) has zero unit tests. workflow-advance.sh has no locking on state file writes — while Claude Code likely serializes hook calls (making concurrent writes unlikely in practice), manual CLI invocations and future platform changes could race against hook-initiated writes. workflow-gate.sh blocks its own workflow — spec file writes are blocked during spec phase, and `workflow-advance.sh` invocations are blocked because the gate's extension-based classification catches `.md` and `.sh` files without path-based exceptions. This spec adds unit tests for lib.sh, PID-based state file locking as defense-in-depth, and path exceptions to fix the gate's self-blocking behavior. Behavioral gate tests for phase enforcement already exist in `tests/test-workflow-gate.sh` (86 tests) and are not duplicated here.

## Scope

**Covers:**
- Unit tests for all 7 functions in `scripts/lib.sh`
- State file locking in `scripts/lib.sh` (shared functions) consumed by `hooks/workflow-advance.sh` and `hooks/workflow-gate.sh`
- Path-based exceptions in `hooks/workflow-gate.sh` to fix self-blocking enforcement

**Does NOT cover:**
- Changes to lib.sh function signatures or behavior
- Changes to workflow-gate.sh phase logic beyond the path exceptions (bugs found in existing behavioral tests become findings, not fixes in this spec)
- Monorepo-specific testing (deferred)
- Performance benchmarking of lock overhead

## Section 1: lib.sh Unit Tests

### R-001 [unit]: branch_slug produces filesystem-safe output
`branch_slug()` on a normal branch (e.g., `feature/foo-bar`) returns a string containing only `[a-zA-Z0-9-]` characters, ending with a 6-character hash suffix separated by a hyphen.

### R-002 [unit]: branch_slug replaces non-alphanumeric characters
`branch_slug()` replaces all non-alphanumeric characters in the branch name with hyphens. `feature/foo-bar` and `feature/foo_bar` produce different hashes (the hash is computed from the original branch name, not the slug).

### R-003 [unit]: branch_slug truncates long names
`branch_slug()` on a branch name longer than 80 characters truncates the slug portion to 80 characters before appending the 6-character hash.

### R-004 [unit]: branch_slug fails on detached HEAD
`branch_slug()` on a detached HEAD prints an error to stderr and returns exit code 1.

### R-005 [unit]: repo_root returns git repository root
`repo_root()` returns the absolute path to the git repository root directory. The result is cached — unsetting `_CORRECTLESS_REPO_ROOT` clears the cache.

### R-006 [unit]: config_file returns expected path
`config_file()` returns `{repo_root}/.correctless/config/workflow-config.json`. The result is cached — unsetting `_CORRECTLESS_CONFIG_FILE` clears the cache.

### R-007 [unit]: artifacts_dir returns expected path
`artifacts_dir()` returns `{repo_root}/.correctless/artifacts`. The result is cached — unsetting `_CORRECTLESS_ARTIFACTS_DIR` clears the cache.

### R-008 [unit]: classify_file matches test patterns
`classify_file()` returns "test" when the file matches `TEST_PATTERN`. Basename-only patterns (e.g., `*.test.ts`) match against the filename. Path patterns containing `/` (e.g., `tests/*.rs`) match against the full relative path.

### R-009 [unit]: classify_file matches source patterns
`classify_file()` returns "source" when the file matches `SOURCE_PATTERN` and does not match `TEST_PATTERN`. Test patterns take priority over source patterns.

### R-010 [unit]: classify_file returns other for unmatched files
`classify_file()` returns "other" when the file matches neither `TEST_PATTERN` nor `SOURCE_PATTERN`.

### R-011 [unit]: classify_file is case-insensitive
`classify_file()` normalizes filenames to lowercase before matching. `MyTest.TS` matches pattern `*.ts`.

### R-012 [unit]: classify_file handles pipe-delimited patterns
`classify_file()` correctly splits pipe-delimited patterns (e.g., `*.test.ts|*.spec.ts`) and matches against each.

### R-013 [unit]: read_patterns loads from config
`read_patterns()` reads `.patterns.test_file` and `.patterns.source_file` from a valid workflow-config.json and sets the `TEST_PATTERN` and `SOURCE_PATTERN` globals. Returns 1 if the config file doesn't exist.

### R-014 [unit]: read_intensity returns configured value
`read_intensity()` returns the `workflow.intensity` value from config. Returns "standard" when the config file is missing or the field is absent.

## Section 2: State File Locking

Locking is defense-in-depth against manual CLI invocation and future platform changes. Claude Code likely serializes hook calls, making concurrent writes unlikely in practice — but the locking mechanism costs <1ms and protects against scenarios where `workflow-advance.sh` is run manually while the agent is active. Locking functions live in `scripts/lib.sh` per ABS-001 (single definition, sourced by both `workflow-advance.sh` and `workflow-gate.sh`).

### R-015 [integration]: write_state acquires and releases a lockfile
`write_state()` creates a lockfile (via `mkdir` — atomic on all filesystems) before writing and removes it after. The lockfile contains the holder's PID. A test verifies: (1) the lockfile exists during a write, (2) the lockfile does not exist after write completes. The existing temp-file + `mv` atomic write pattern is preserved — the lock protects the read-modify-write cycle, `mv` protects against partial writes.

### R-016 [integration]: locked_update_state holds lock for entire read-modify-write
`locked_update_state()` creates the lockfile before reading the state file and removes it after the write completes. If the jq transformation fails, the original state file is unchanged and the lockfile is removed. A test verifies: (1) the lockfile is held during the operation, (2) the state file reflects the expected modification after success, (3) the state file is unchanged after a failed jq transformation.

### R-017 [unit]: lock uses PID for stale detection
The lockfile contains the PID of the holder. If the PID is no longer alive (checked via `kill -0`), the lock is considered stale and can be broken by the next caller. Test uses the dead-PID technique: fork a subshell, capture its PID, let it exit, create a lockfile with that PID, verify the next lock acquisition breaks it.

### R-018 [unit]: lock acquisition times out
If the lock cannot be acquired within `$CORRECTLESS_LOCK_TIMEOUT` seconds (default: 5), the operation fails with a clear error message containing "timeout." Tests use `CORRECTLESS_LOCK_TIMEOUT=1` for speed.

### R-019 [unit]: lock is released on success and failure
The lock is released after `write_state` and `locked_update_state` complete, whether the jq transformation succeeds or fails. A failed write must not leave a stale lock. Test verifies both success path (valid JSON) and failure path (invalid jq input) leave no lockfile behind.

### R-020 [integration]: workflow-gate override decrement uses locking
The override decrement path in `hooks/workflow-gate.sh` acquires the state lock before decrementing and releases it after. Uses the same locking functions from `scripts/lib.sh` and the same lockfile convention as workflow-advance.sh.

### R-021 [unit]: lock has no flock dependency
The locking mechanism does not depend on `flock` (not available on macOS by default). Uses `mkdir` for atomic lock creation, `kill -0` for stale detection, and standard utilities available on both macOS and Linux. A test verifies the lock implementation does not call `flock` or `lockfile` (static analysis via grep).

## Section 3: Workflow Gate Path Exceptions

The gate's file classification is too broad — `.md` in `source_file` catches spec files, and `.sh` extraction from Bash commands catches `workflow-advance.sh` invocations. The gate blocks its own workflow: the agent can't write specs during spec phase or run override commands to unblock itself.

### R-022 [integration]: spec phase allows writes to .correctless/specs/
During `spec` phase, writes to files under `.correctless/specs/` are allowed regardless of file extension. The spec phase exists to produce spec files — blocking spec writes is self-defeating.

### R-023 [integration]: .correctless/artifacts/ always writable
Writes to files under `.correctless/artifacts/` are allowed in all phases. State files, token logs, QA findings, and other artifacts must be writable for the workflow to function.

### R-024 [integration]: workflow-advance.sh invocations always allowed via Bash
When the Bash tool command string contains `workflow-advance.sh`, the gate allows the operation regardless of phase, even if the command also contains write patterns (e.g., redirects for logging). Implementation: add an early exit in the Bash handling block before `_has_write_pattern`.

## Won't Do
- Changes to phase transition logic in workflow-advance.sh (that's a separate spec)
- Monorepo-specific gate testing (deferred — no monorepo in this project)
- Performance benchmarks for lock overhead (the lock is sub-millisecond)
- Duplicate behavioral tests for gate phase enforcement — 86 existing tests in `tests/test-workflow-gate.sh` already cover all phases. Verified during adversarial review.
- Fixing gate bugs found by existing tests — unless the bug is a phase enforcement failure (enforcement failures undermine the entire workflow and must be fixed immediately)
- Moving the protected file check before the override check — overrides are emergency, logged, human-initiated, capped at 3 per workflow. If an override is used to edit state files directly, that's visible in the audit trail and /cwtf catches it. Overrides need to be able to fix state corruption, which is one of the main reasons they exist.

## Risks
- **Stale lock blocks all workflow operations**: Mitigated by R-017 (PID-based stale detection) and R-018 (timeout). A crashed process leaves a lock with a dead PID that the next caller breaks automatically.
- **Lock overhead on every state write**: Negligible — mkdir/write-PID/rmdir adds <1ms. The jq transformation is already the bottleneck.
- **Path exceptions could be exploited to bypass gating**: R-022 only applies during spec phase for `.correctless/specs/` — not a general bypass. R-023 covers artifacts which are non-source operational files. R-024 allows `workflow-advance.sh` which is the workflow's own control plane.

## Open Questions
- None — scope is clear from brainstorm and review.
