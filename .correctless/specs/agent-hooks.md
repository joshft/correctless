# Spec: Agent Hook for Internal Import Enforcement

## Metadata
- **Task**: agent-hooks
- **Recommended-intensity**: high
- **Intensity**: high
- **Intensity reason**: file path signal (hooks/); keyword signal (trust boundary — TB-001 config-sourced commands); project floor is high
- **Override**: none

## What

A PreToolUse agent hook that denies test file writes when the test imports internal packages covered by a documented entrypoint. This moves the internal import bypass check (carchitect Phase 1's R-005, currently a post-hoc test audit finding) to write-time enforcement. The hook reads entrypoints from ARCHITECTURE.md, checks whether the file being written is a test, checks whether the test content imports packages within an entrypoint's scope, and denies the write with a reason explaining which entrypoint to use instead. This is the first agent hook in Correctless — it establishes the pattern for future hooks.

## Rules

- **R-001** [unit]: A new hook file `hooks/import-guard.json` defines the agent hook configuration. The hook is a PreToolUse hook that fires on Write and Edit tool calls. The configuration uses `type: "agent"` with a prompt that instructs the agent to check for internal import bypass. The hook uses `"if": "Write|Edit"` to scope to file-writing operations only.

- **R-002** [unit]: The agent hook's prompt instructs the agent to perform these steps in order:
  1. Check if the file being written/edited is a test file (matches the project's `patterns.test_file` from workflow-config.json, or falls back to common patterns: `*_test.go`, `*.test.ts`, `*.test.js`, `test_*.py`, `*_test.rs`).
  2. If not a test file, return `{"ok": true}` immediately — the hook only applies to test files.
  3. Check if `.correctless/ARCHITECTURE.md` exists and contains entrypoints (the `correctless:entrypoints:start` markers). If no entrypoints, return `{"ok": true}` — graceful degradation. Read only the entrypoints block (between the markers), not the entire ARCHITECTURE.md — the document may be large on mature projects.
  4. Read the `test_helpers` allow-list from `.correctless/config/workflow-config.json` (under `workflow.test_helpers`, a list of glob patterns). If the field is absent, treat as empty (no allow-listed packages).
  5. Read the entrypoints YAML. For each entrypoint, check whether the test file's content imports any package within that entrypoint's `scope` globs that is NOT the entrypoint handler itself AND is NOT matched by any `test_helpers` glob pattern.
  6. If an internal import is found: return `{"ok": false, "reason": "Test imports internal package 'pkg/handlers/auth' directly. Entrypoint 'api-server' covers this path — use test_via: httptest.NewServer(handler) instead. If this import is for test fixtures, add the package to workflow.test_helpers in workflow-config.json."}`.
  7. If no internal imports found: return `{"ok": true}`.

- **R-003** [unit]: The import detection is language-aware. The agent checks for import patterns matching the languages documented in carchitect Phase 1 R-006: Go (`import "pkg/..."`), TypeScript/JavaScript (`import ... from '...'` or `require('...')`), Python (`from pkg import` or `import pkg`), Rust (`use crate::` or `mod`). For languages not in this list, the hook returns `{"ok": true}` — it does not block writes for unsupported languages.

- **R-004** [unit]: The hook excludes imports of the entrypoint handler itself (consistent with carchitect Phase 1 R-007). Importing `cmd/server/main.go` when that IS the entrypoint is legitimate. The hook only flags imports of packages *within* the entrypoint's scope that should be reached *through* the entrypoint.

- **R-005** [unit]: The hook configuration specifies `"timeout": 30` (seconds). The agent needs to read ARCHITECTURE.md, parse entrypoints, read the test file content from the tool input, and check imports — this should complete well within 30 seconds. The `model` field is omitted (defaults to Haiku, which is sufficient for this deterministic check).

- **R-006** [integration]: The `setup` script is updated to register the agent hook in `.claude/settings.json` during installation. The hook is registered alongside existing command hooks (workflow-gate.sh, sensitive-file-guard.sh, etc.). The hook registration follows the same pattern as existing hooks — metadata headers in the JSON config file, not inline in the hook file (agent hooks are JSON config, not bash scripts).

- **R-007** [unit]: The hook is conditional on entrypoints existing. If a project has not run `/carchitect` or has no entrypoints in ARCHITECTURE.md, the hook fires (it's registered) but immediately returns `{"ok": true}` without blocking anything. Zero cost when not applicable — the agent reads ARCHITECTURE.md, sees no markers, and exits. This is consistent with the graceful degradation pattern used across all entrypoint consumers (R-003 in integration-test-contracts, R-008 in carchitect-phase1).

- **R-008** [unit]: The hook file includes a comment block explaining what it does, when it fires, and how to disable it. The comment references the entrypoint documentation and the test audit check 10 (which is the post-hoc version of the same check). This helps users who encounter a deny understand why it happened.

- **R-009** [unit]: Documentation is updated: `docs/skills/setup.md` or equivalent documents the new hook. `.correctless/AGENT_CONTEXT.md` references the agent hook pattern. CONTRIBUTING.md test counts updated. The hook is described in the project's hook documentation alongside workflow-gate.sh, sensitive-file-guard.sh, etc.

- **R-010** [unit]: The hook's deny reason includes actionable guidance: the specific entrypoint name, the `test_via` pattern to use instead, and which internal package was detected. The deny reason also includes the escape hatch: "If this import is for test fixtures, add the package to `workflow.test_helpers` in workflow-config.json." The developer sees exactly what to change, or how to allow-list the import if it's legitimate.

- **R-011** [unit]: A `workflow.test_helpers` field in `.correctless/config/workflow-config.json` contains a list of glob patterns for packages that are always allowed to be imported in test files, even when they fall within an entrypoint's scope. Common entries: `["*/testutil/**", "*/fixtures/**", "*_test.go"]`. The hook checks imports against this allow-list before blocking (R-002 step 5). This handles the common case of test helper packages that live alongside the code they help test (e.g., `pkg/handlers/testutil/` containing fixture builders). The field is optional — if absent, no packages are allow-listed.

- **R-012** [unit]: If the agent hook denies a write and the main agent retries 3 consecutive times on the same file, the hook's deny reason includes escalation guidance: "If you cannot write this test through the entrypoint, ask the user for guidance." This breaks the retry loop — the agent escalates instead of looping on denials indefinitely.

## Won't Do

- **Spec-scope enforcement** — requires judgment about whether an edit is "in scope" for a spec. Not deterministic, not safe for a hard-block hook. Stays as a prompt instruction or post-hoc audit finding.
- **additionalContext or updatedInput** — agent hooks can only return ok/reason. No context injection or input modification. Those are command hook features.
- **Override mechanism** — agent hooks are binary (allow/deny). No workflow-advance.sh override equivalent. This is why the hook must have zero false positives — see Risk 1.
- **Prompt hook type** — a prompt hook can't read files (no tools). The import check requires reading ARCHITECTURE.md and the test file content. Agent hook is the only viable type.
- **Custom model selection** — the hook uses the default model (Haiku). Haiku is sufficient for this deterministic check. Making the model configurable adds complexity for no benefit.
- **Replacing the test audit check** — the agent hook and test audit check 10 are defense in depth, not redundant. The hook catches violations at write time; the test audit catches violations the hook missed (e.g., the test was written before the hook was installed, or the hook was temporarily disabled). Both remain.
- **Extracting shared language import patterns** — the same import pattern list (Go, TS/JS, Python, Rust) now lives in three places: Phase 1 test audit (R-006), integration-test-contracts (Through check), and this hook (R-003). When a language is added, three files update. Worth extracting to a shared reference (helper script or AGENT_CONTEXT.md list) in a future cleanup sprint. Not blocking for this spec.

## Risks

- **False positives block development with no escape hatch**: An agent hook returning `{ok: false}` is a hard wall — no override, no bypass. A test that legitimately imports an internal package for fixture setup (e.g., `pkg/handlers/testutil`) while also testing through the entrypoint gets blocked. The scope is correct, the test is correct, the hook is wrong. This is a real pattern — test helper packages that live alongside the code they test are common in Go, Python, and TypeScript.
  1. Mitigate (recommended) — R-011 adds a `workflow.test_helpers` allow-list in workflow-config.json. Packages matching the allow-list globs are never blocked. The deny reason (R-010) tells the developer how to add the package to the allow-list. Two classes of false positive remain after the allow-list: (a) incorrect entrypoint scope globs (too broad), fixable via `/carchitect`, and (b) a legitimate import pattern not covered by the allow-list, fixable by adding the pattern. Both are configuration fixes, not settings.json edits.

- **Hook adds latency to every Write/Edit call**: The agent hook spawns a Haiku subagent on every Write/Edit. Most writes are not test files and exit immediately at step 2. Test file writes require reading ARCHITECTURE.md and checking imports.
  1. Accept — correctness over speed. The hook catches violations at write time instead of 10-20 minutes later during the test audit. Users chose Correctless for correctness. A few seconds per write is a rounding error in a 30-minute TDD cycle.

- **Haiku's reasoning may be insufficient**: The check requires reading YAML, matching glob patterns against import paths, and distinguishing entrypoint handler imports from internal package imports. This is non-trivial pattern matching.
  1. Mitigate (recommended) — the prompt decomposes the task into explicit steps (R-002). Each step is a simple check (is this a test file? do entrypoints exist? does this import match a scope glob?). Haiku handles sequential checklist reasoning well. If Haiku proves unreliable in practice, the `model` field can be added to the hook config to upgrade to Sonnet.

- **Entrypoint YAML parsing in the agent hook**: The agent reads ARCHITECTURE.md and must parse the entrypoints YAML within a markdown document. If the YAML is malformed or the markers are missing, the hook must fail open (return ok).
  1. Mitigate (recommended) — R-007 specifies graceful degradation. Missing markers = ok. R-002 step 3 checks for markers before attempting to parse. If the YAML is present but malformed, the agent can't parse it and returns ok (fail-open, not fail-closed for parse errors — the test audit catches it post-hoc).

## Open Questions

- **OQ-001**: Should the hook fire on ALL Write/Edit calls or only during specific workflow phases (e.g., tdd-tests)? **Tentative answer**: fire on all phases. The violation is phase-independent — a test that bypasses an entrypoint is wrong whether written during RED, edited during a QA fix round, or modified during a mini-audit fix. The step 2 fast path (not a test file → ok) makes the latency argument moot for non-test writes.

- **OQ-002**: Should this be the first agent hook, or should we start with a simpler prompt hook to validate the hook infrastructure? A prompt hook for something trivial (e.g., "does this commit message follow the project's format?") would test the registration, timeout, and ok/reason contract without the complexity of entrypoint parsing. **Tentative answer**: start with the agent hook directly. The import check is the motivating use case. A throwaway prompt hook teaches us about infrastructure but doesn't deliver value.

- **OQ-003**: How should the hook interact with the existing test audit check 10? When the hook blocks a write, the developer fixes the import and rewrites. The test audit later runs and check 10 finds no violations (because the hook already prevented them). Is the test audit check redundant? **Tentative answer**: no, keep both. Defense in depth. The hook catches violations in real time. The test audit catches violations from before the hook was installed, from manual edits outside Claude Code, or from a temporarily disabled hook. The test audit's "no violations found" is confirmation, not redundancy.
