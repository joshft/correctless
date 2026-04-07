# Spec: Mechanical Token Tracking via PostToolUse Hook

## Metadata
- **Created**: 2026-04-07T10:00:00Z
- **Status**: reviewed
- **Impacts**: skills/_shared/constraints.md (format change), skills/cmetrics/SKILL.md (glob update)
- **Branch**: feature/token-tracking
- **Research**: null
- **Intensity**: high
- **Intensity reason**: file path signal (hooks/), project floor (workflow.intensity=high)
- **Override**: none

## Context

The shared constraints instruct orchestrator skills to log subagent token usage after each spawn, but no skill actually does it — it's a prompt instruction competing for attention with the actual task. This spec replaces the prompt-based approach with a mechanical PostToolUse hook that fires on every Agent tool completion and appends token data to a per-branch log file. The hook extracts usage fields from the Agent tool's `tool_response` (input_tokens, output_tokens, total_cost_usd, duration_ms) and tags each entry with the subagent's description, type, current workflow phase, and branch. `/cmetrics` consumes this log for cost-per-feature and phase-distribution analysis.

## Scope

**Covers:**
- A PostToolUse hook that captures Agent tool token usage
- Per-branch log file at `.correctless/artifacts/token-log-{branch-slug}.jsonl`
- Integration with existing workflow state (phase tagging)
- Setup script wiring the hook into `.claude/settings.json`
- Update `/cmetrics` SKILL.md glob from `token-log-*.json` to `token-log-*.jsonl`
- Update shared constraints token tracking section to reference the new JSONL format

**Does NOT cover:**
- Token budgets or cost alerts (future feature)
- Non-Agent tool token tracking (the hook only fires on Agent completions)

## Environment Assumptions

### EA-002: PostToolUse hook stdin includes tool_response for Agent tool
PostToolUse hooks for the Agent tool receive stdin JSON containing both `tool_input` and `tool_response`. Expected `tool_response` fields: `usage.input_tokens` (int), `usage.output_tokens` (int), `total_cost_usd` (float), `duration_ms` (int), `result` (string — MUST NOT be extracted, see PRH-003). If this assumption is false, the hook logs all-zero metrics and is inert. Validate once via smoke test during development: after wiring the hook, trigger one Agent tool invocation and check the log for non-zero values.

## Invariants

### R-001 [unit]: hook fires only on Agent tool completions
The hook checks `tool_name` and exits 0 immediately for any tool that is not `Agent`. No processing, no file I/O for non-Agent tools.

### R-002 [unit]: hook extracts all token fields from tool_response
The hook extracts `tool_response.usage.input_tokens`, `tool_response.usage.output_tokens`, `tool_response.total_cost_usd`, and `tool_response.duration_ms` from stdin JSON. Missing fields default to 0.

### R-003 [unit]: hook extracts subagent metadata from tool_input
The hook extracts `tool_input.description` and `tool_input.subagent_type` from stdin JSON. Missing fields default to empty string.

### R-004 [integration]: hook reads current workflow phase from state file
The hook reads the current phase from the workflow state file (`.correctless/artifacts/workflow-state-{branch-slug}.json`). If no state file exists (no active workflow), phase defaults to `"none"`.

### R-005 [unit]: hook appends a JSONL entry to the token log file
Each Agent completion appends one JSON object as a single line to `.correctless/artifacts/token-log-{branch-slug}.jsonl` (JSONL format — one JSON object per line, `>>` append). No need to read or parse the existing file. Write path is O(1) regardless of file size. `/cmetrics` reads the file with `jq -s '.' < file.jsonl` when it needs the array.

### R-006 [unit]: log entry contains all required fields
Each log entry contains: `timestamp` (ISO 8601), `branch`, `phase`, `feature` (derived from context — the current workflow task name, or "unknown" if no active workflow), `agent_description`, `agent_type`, `input_tokens`, `output_tokens`, `total_tokens` (computed: input + output), `total_cost_usd`, `duration_ms`.

### R-007 [static]: hook spawns at most two jq processes and zero subshells in loops
The hook must contain at most two `jq` invocations (one for stdin parse, one for state file read). No command substitutions (`$()`) inside `while` or `for` loops. No external commands beyond `jq`, `date`, `cat`, and file redirects. This structural constraint bounds runtime to <100ms empirically. A non-gating benchmark in the test suite logs actual timing for regression tracking.

### R-008 [integration]: hook is wired by setup script
The `setup` script adds the PostToolUse hook entry to `.claude/settings.json` with matcher `Agent` and the correct path to the hook script.

### R-009 [unit]: hook follows PAT-005 PostToolUse conventions
No `set -euo pipefail` (would cause early abort on any failure, violating fail-open). Bulk-parse stdin with `eval + jq -r @sh`, `|| exit 0` on parse failure. Fast-path `exit 0` for non-Agent tools before any I/O. `command -v jq` check with `exit 0` (fail-open). Must always `exit 0`. Guard each operation with `|| exit 0` or `|| true` rather than relying on `set -e`.

### R-010 [unit]: hook is fail-open
If any step fails (jq parse error, state file unreadable, log file write failure), the hook exits 0. Token tracking must never block agent operations. Errors are silent — the hook is advisory, not gating.

### R-011 [unit]: hook sources lib.sh for branch_slug
The hook uses `branch_slug()` from `scripts/lib.sh` per ABS-001 (single definition). If lib.sh is not found, the hook exits 0 (fail-open).

### R-012 [integration]: setup script is idempotent for PostToolUse hooks
Running setup when the token-tracking hook is already registered does not duplicate the entry. The setup script checks for the specific hook command path within the PostToolUse array, independent of other PostToolUse entries (e.g., audit-trail).

## Prohibitions

### PRH-001: hook must never exit non-zero
PostToolUse hooks that exit non-zero could disrupt the agent's operation. The hook must always exit 0, even on internal errors.

### PRH-002: hook must never modify tool behavior
The hook is observational only. It must not write to stdout (which could be interpreted as feedback to the agent) or modify any files other than the token log.

### PRH-003: no eval of tool_response.result, document description trust boundary
The subagent's `result` field contains arbitrary LLM-generated text — potentially pages of content with embedded shell metacharacters. If the hook eval'd or interpolated that content, a prompt injection in the subagent's output could execute arbitrary commands (TB-003). The hook must never eval, interpolate, or process `tool_response.result`. The jq extraction must not reference any path containing `.result`. The hook must not declare any shell variable named `result` or `RESULT`. The hook source must include a comment containing `TB-003` explaining why `result` is untouched.

`tool_input.description` is also LLM-generated but is a short task description (3-5 words) that flows through `jq @sh` safe quoting. The risk is lower because: (1) it's a controlled-length field authored by the orchestrator, not arbitrary subagent output, (2) `@sh` produces POSIX-quoted strings that neutralize shell metacharacters. The treatment differs because the risk differs. The hook source must document this asymmetry.

## Won't Do
- Token budgets or cost caps (separate spec — this just collects data)
- Capturing non-Agent tool tokens (Read, Edit, Bash don't have meaningful token data in PostToolUse)

## Risks
- **Hook adds latency to every Agent call**: Mitigated by R-007 (structural constraint: 2 jq calls max). The jq parse + file append is comparable to the existing audit-trail hook.
- **Log file grows unbounded**: A typical feature spawns 10-20 subagents. At ~200 bytes per entry, a feature produces ~4KB. Acceptable. `/cmetrics` can prune old logs if needed (future feature).
- **State file read during concurrent write**: The state file is written via `mv` (atomic rename on POSIX), so reads either see the old content or the new content, never partial. jq read of a missing or invalid file returns empty, phase defaults to "none". No lock needed for reads.
- **EA-002 assumption is wrong**: If `tool_response` is not in PostToolUse stdin, the hook silently logs zeros. The smoke test catches this during development, not in CI.

## Open Questions
- None — scope is clear from brainstorm and review.
