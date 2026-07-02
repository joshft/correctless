# Architecture — Environment Assumptions

> Fragment of [.correctless/ARCHITECTURE.md](../../.correctless/ARCHITECTURE.md). Entry headings are indexed in the root document; full bodies live here.

### ENV-001: Bash 4+ required
- **Assumption**: All hooks use `${var,,}` (lowercase), `local -a` (arrays), and `[[ =~ ]]` (regex). Requires Bash 4.0+.
- **Consequence if wrong**: Silent failures — `${var,,}` produces empty string on Bash 3.x
- **Test**: Not runtime-checked. macOS ships Bash 3.2 by default; users must install Bash 4+ via Homebrew.

### ENV-002: jq 1.7+ required
- **Assumption**: `jq` version 1.7 or later is available on PATH for JSON parsing of hook stdin and config files. jq 1.6 has known incompatibilities (setup and many hooks fail) and is not supported.
- **Consequence if wrong**: workflow-gate.sh and sensitive-file-guard.sh exit 2 (fail-closed). auto-format.sh exits 0 (advisory). On jq 1.6, setup itself fails to configure the project.
- **Test**: Each hook checks `command -v jq` at startup. CI tests against jq 1.7.1 and jq 1.8.1 via matrix (AP-011) to catch version-portability bugs. Note: jq 1.8 silently fixed operator precedence for `as $var` bindings after arithmetic — see PAT-010.

### ENV-003: Filesystem modification timestamps unreliable for recency
- **Assumption**: File modification times may not reflect authoring order after git clone, checkout, or rebase. Budget selection (PAT-004) uses filename sort (which embeds the feature slug) rather than mtime.
- **Consequence if wrong**: Recency sort based on mtime reads wrong files after git operations
- **Test**: Not runtime-checked. Filename sort is preferred over mtime sort.

### ENV-004: gh CLI as optional dependency
- **Assumption**: `gh` (GitHub CLI) is available on PATH when `pr_creation: gh` (the default) is configured in preferences.md.
- **Consequence if wrong**: Pipeline completes all implementation, verification, and documentation phases successfully, but PR creation fails at the final step. R-018 mitigates this with an upfront `command -v gh` check at pipeline startup — failing fast before any skill invocation.
- **Test**: R-018 in semi-auto-mode tests (upfront gh availability check)

### ENV-005: Claude Code path-scoped rule loading
- **Assumption**: Claude Code loads rule content from `.claude/rules/*.md` files whose YAML `paths:` frontmatter matches a file being opened (read, edited, or written) in the session. The matched rule body is injected into the agent's editing context. Exact-path matches (e.g., `hooks/workflow-gate.sh`) are supported; glob semantics are not assumed by Feature A and are out of scope.
- **Consequence if wrong**: the rule file becomes inert documentation — agents editing scoped hook files would not see the rule in context, and PAT-001's migration from ARCHITECTURE.md to `.claude/rules/hooks-pretooluse.md` would silently remove the rule from agent awareness. The feature must be rolled back per PRH-002 in the path-scoped-rules-pat001 spec.
- **Test**: verified manually pre-merge via the INV-015 canary procedure (create a canary rule file with a unique UUID marker, open a scoped hook in a fresh session, verify the UUID is observable in the agent's context). Evidence recorded in `.correctless/verification/path-scoped-rules-pat001-canary.md`. **Direct-observation upgrade (2026-07-01)**: the assumption is now *directly observable at runtime* via the `InstructionsLoaded` hook (ENV-012) — `path_glob_match` load events are recorded to `.correctless/meta/instructions-loaded.jsonl` and surfaced by `/cwtf`. This upgrades the signal from the indirect canary to direct observation; it does not change ENV-005's underlying assumption.

### ENV-006: POSIX-portable external tools (grep, sed, awk)
- **Assumption**: All hook code, phase-transition scripts, and tests use `grep`, `sed`, and `awk` in POSIX-compatible mode only. No GNU-only extensions: no `grep -P` (Perl regex), no `\b` / `\s` outside bracket expressions, no `sed -i` without a backup argument (BSD requires `sed -i ''` or explicit backup), no `gawk` extensions (`gensub`, `PROCINFO`, `length(array)`). Bash 4+ constructs (EA-001 / ENV-001) are permitted as a separate assumption.
- **Consequence if wrong**: silent test failures on macOS BSD tools — GNU extensions that pass on Linux CI fail with cryptic error messages or produce subtly wrong results on developer macOS machines. The drift test's own self-scan (INV-010) catches this class inside `tests/test-architecture-drift.sh`; the broader rule is enforced by code review and by `tests/test-antipattern-scan.sh`.
- **Test**: INV-010 in `tests/test-architecture-drift.sh` (self-scan); `tests/test-antipattern-scan.sh` for broader coverage.

### ENV-008: python3 with PyYAML (or yq) for entrypoints extraction
- **Assumption**: The entrypoints extraction script (`scripts/extract-entrypoints.sh`) requires a YAML parser to validate extracted content. The fallback chain is: `yq` (preferred) → `python3` with PyYAML (`python3 -c 'import yaml; yaml.safe_load(...)'`) → exit 1 with error message "Neither yq nor python3 with PyYAML available." At least one of `yq` or `python3` with PyYAML must be available on any machine running the extraction script.
- **Consequence if wrong**: `scripts/extract-entrypoints.sh` exits 1 with a clear error message. No silent failure — the script refuses to output unvalidated YAML. Phase 1+ consumers that call this script will fail loudly.
- **Test**: test-carchitect.sh — R-005 (fallback chain references in script body)

### ENV-007: Plugin-agent loader contract
- **Assumption**: Claude Code's plugin loader parses `agents/*.md` files with YAML frontmatter supporting `name`, `description`, `tools`, and `model` fields. The `tools:` field is a comma-separated bare-tool list; Bash sub-pattern scoping (`Bash(git*)` style) is NOT supported at the agent level, in contrast to skill `allowed-tools:` which does support sub-patterns. Agents are invocable from skills via `Task(subagent_type="{plugin}:{name}")` (for Correctless, `Task(subagent_type="correctless:fix-diff-reviewer")`). Plugin-agent file discovery requires plugin reinstall AND a Claude Code session restart — mid-session edits to `agents/*.md` are NOT visible to the current session's Task tool.
- **Consequence if wrong**: agent files ship but are not discoverable at runtime; runtime tool-allowlist enforcement may differ from file-level specification; the caudit step 6a Task call would fail or load the wrong prompt. The VP-001 fingerprint smoke test catches drift between file content and runtime behavior.
- **Test**: Manual pre-merge via VP-001 (fingerprint smoke test) and VP-002 (functional-equivalence replay) recorded in `.correctless/verification/fix-diff-reviewer-migration-replay.md`; structural drift via `tests/test-fix-diff-reviewer-agent.sh`, `tests/test-ctdd-green-agent.sh`.

### ENV-009: Claude Code session transcript storage format
- **Assumption**: Claude Code stores session transcripts as JSONL files under `~/.claude/projects/{project-dir}/`. The directory structure (`{project-dir}/{session-uuid}.jsonl`, `{session-uuid}/subagents/agent-*.jsonl`, `{session-uuid}/subagents/agent-*.meta.json`) and JSONL schema (`.type`, `.message.id`, `.message.model`, `.message.usage.*`, `.gitBranch`, `.timestamp`) are Claude Code internal — not a public API.
- **Consequence if wrong**: If Claude Code changes its storage layout, `scripts/compute-session-cost.sh` degrades gracefully (exit 0 with error JSON per R-011) but produces no cost data. The dashboard, /cverify, and /cmetrics fall back to token-log or token-count-based estimates. No data loss or failure — the cost pipeline becomes inert until the script is updated.
- **Test**: test-session-cost.sh — R-002 (session discovery), R-011 (graceful degradation)

### ENV-010: Agent tool worktree isolation contract
- **Assumption**: The Agent tool's `isolation: "worktree"` mode creates a git worktree at `.claude/worktrees/agent-{id}` and runs the agent on branch `worktree-agent-{id}`. Hooks registered in `.claude/settings.json` do NOT run inside worktrees — the agent operates without workflow-gate, sensitive-file-guard, or audit-trail enforcement. The main working tree is untouched during agent execution. On completion: if the agent made no changes, the worktree is auto-cleaned; if the agent made changes, the worktree persists for the orchestrator to inspect and merge.
- **Consequence if wrong**: If Claude Code changes worktree lifecycle semantics, agents may: (1) pollute the main tree with intermediate state, (2) trigger hooks inside the worktree causing phase-gate failures on a non-existent workflow branch, (3) leave orphaned worktrees consuming disk. The adversarial probe round in `/ctdd` depends on worktree isolation to safely attempt invariant violations without corrupting the implementation branch.
- **Test**: Structural — `/ctdd` probe round uses worktree isolation; manual verification that hooks do not fire inside `.claude/worktrees/`

### ENV-011: Claude Code v2.1.150+ for `disallowed-tools` skill frontmatter
- **Assumption**: Claude Code v2.1.150+ supports `disallowed-tools` in skill YAML frontmatter, structurally removing listed tools from the model while the skill is active. 12 skills use this for defense-in-depth alongside `allowed-tools` (PAT-018 application): Group A (write-nothing: chelp, cstatus, cdashboard) disallows Edit, Write, MultiEdit, NotebookEdit, CreateFile; Group B (artifact-only: cexplain, cwtf, cmetrics, csummary, cpr-review, cmaintain, cmodel, cmodelupgrade, ctriage) disallows Edit, MultiEdit, NotebookEdit, CreateFile.
- **Consequence if wrong**: On older Claude Code versions, the `disallowed-tools` frontmatter key is silently ignored — no crash, no error, no enforcement. The existing `allowed-tools` whitelist remains the sole enforcement layer. The defense-in-depth intent is still documented in frontmatter for human readers.
- **Test**: tests/test-disallowed-tools.sh — R-001 through R-007 (frontmatter presence, group classification, disjointness with allowed-tools, distribution sync, structural drift)

### ENV-012: Claude Code InstructionsLoaded hook event
- **Assumption**: Claude Code emits an `InstructionsLoaded` hook event when instruction/rule content is loaded into the agent's context, available since v2.1.69 (verified empirically on v2.1.185, 2026-07-01 via a temporary stdin-dump hook). The payload carries `session_id`, `file_path` (the loaded rule file), `load_reason` (e.g. `path_glob_match`, `session_start`, `compact`), and for `path_glob_match` a `trigger_file_path` (the opened file whose glob matched). **Firing model (confirmed): per-open, first-load** — opening a `.claude/rules/`-scoped file mid-session emits a *fresh* `path_glob_match` event the first time that rule enters context (a rule already resident at session start does not re-fire). The harness **ignores the hook's exit code** for this event, so a fail-open (always exit 0) posture is correct.
- **Consequence if wrong**: if the event does not fire (older harness, or a load_reason rename on upgrade), `hooks/instructions-loaded.sh` simply never appends and the `/cwtf` rule-load presentation stays dormant (INV-009) — graceful degradation, no error. If the firing model were session-batched instead of per-open, the log would still show a rule was in context for the session but couldn't tie a load to a specific later edit; the human interprets accordingly (advisory, non-breaking).
- **Test**: tests/test-instructions-loaded.sh (real captured payload fixture round-trip, INV-012a), `.correctless/verification/instructionsloaded-hook-verification.md` (INV-012b harness-origin + firing-model attestation), tests/test-architecture-drift.sh (ENV-012 coverage)
