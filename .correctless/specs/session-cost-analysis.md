# Spec: Session Cost Analysis

## Metadata
- **Task**: session-cost-analysis
- **Recommended-intensity**: standard
- **Intensity**: high
- **Intensity reason**: no signals triggered; user explicitly requested high
- **Override**: raised

## What

Replace the phantom cost data in Correctless with real USD cost computed from Claude Code session transcripts. The current token-tracking.sh hook extracts `tool_response.usage.*` and `tool_response.total_cost_usd` from PostToolUse payloads, but these fields don't exist in the PostToolUse contract — every entry is zeros. The real per-turn usage data (model, input/output tokens, cache breakdown) lives in Claude Code's session transcript JSONL files and their associated subagent transcripts. A new script reads these transcripts, correlates with audit trail phase transitions, computes cost using model-specific pricing, and stores a per-feature cost artifact. The dashboard, /cmetrics, and /cverify consume this artifact for real cost visibility.

The cost artifact is the canonical source of USD cost data. Token-log JSONL (ABS-006) is retained for phase timing and skill metadata only. Consumers must never derive USD cost from token-log fields.

## Rules

- **R-001** [unit]: A new script `scripts/compute-session-cost.sh` accepts a branch name (or derives it from the current git branch), discovers matching session transcript JSONL files, reads parent + subagent transcripts, and outputs a JSON cost summary to stdout. The script also writes the result to `.correctless/artifacts/cost-{branch-slug}.json` (branch_slug from `scripts/lib.sh`). The script sources `scripts/lib.sh` for `branch_slug()` and `artifacts_dir()`. Must be compatible with jq 1.7+ per ENV-002. Follow PAT-010 parenthesization rules for `as` bindings (AP-011).

- **R-002** [unit]: Session discovery uses a two-step approach. First, derive a candidate project directory via `$(repo_root | tr '/' '-')` and check if `~/.claude/projects/{candidate}/` exists. If it does, scan `*.jsonl` files there. If it doesn't (the path convention doesn't match), exit 0 with a JSON containing `"error": "session directory not found — set workflow.session_dir in workflow-config.json"` and all numeric fields set to 0. Users can set `workflow.session_dir` in `workflow-config.json` to an absolute path, which bypasses the derivation. Validation for `workflow.session_dir`: must be an absolute path, must exist, must be a directory, must be under `~/.claude/` — reject with an error JSON if any check fails. Within the matched session directory, scan `*.jsonl` files for assistant-type entries whose `gitBranch` field matches the target branch (exact string equality, not regex/glob). All matching session files (and their `subagents/` subdirectories) are included. Tests MUST override HOME to create a synthetic `~/.claude/projects/` hierarchy — the script must never read from the real user's home directory during tests.

- **R-003** [unit]: Per-turn cost computation. First, deduplicate transcript entries by `.message.id` — take the last entry per unique message ID (the final streaming response with complete token counts). Streaming produces multiple entries per API call (~3.14x inflation observed in real transcripts). Then for each deduplicated assistant message, compute cost as `(input_tokens * input_price) + (cache_creation_input_tokens * cache_write_price) + (cache_read_input_tokens * cache_read_price) + (output_tokens * output_price)`. Prices are per-token (not per-million). The model is read from each message's `.message.model` field. Unrecognized models (including `<synthetic>`) use median pricing (the middle model's rates among known models — currently Sonnet). The output JSON includes an `"unknown_models": ["model-id"]` array listing any models that used estimated pricing. If a transcript entry has `.type == "assistant"` but lacks `.message.usage.input_tokens`, add a warning to the output JSON `"warnings": ["unrecognized transcript format in session {id}"]` rather than silently computing 0. Process transcript JSONL with `jq -R 'try (fromjson | ...) catch empty'` per ABS-006 convention. Never use `jq -s` (AP-014).

- **R-004** [unit]: Phase attribution: the script reads the audit trail (`.correctless/artifacts/audit-trail-{slug}.jsonl`) and extracts phase transition timestamps — each entry where the phase value differs from the previous entry, chronologically. This correctly handles phase re-entry (e.g., `tdd-impl → tdd-qa → tdd-impl → tdd-qa` cycling during QA rounds). The turn timestamp is the top-level `.timestamp` field of each transcript JSONL entry. Both audit trail and transcript timestamps must be compared as ISO 8601 strings in UTC with `Z` suffix. Each transcript turn is attributed to the phase that was active at its timestamp. Turns before the first audit trail entry are attributed to `"pre-workflow"`. Turns with no matching audit trail (no audit trail file exists) are all attributed to `"unattributed"`. Note: subagent turns are attributed by their transcript timestamp, which is completion time, not spawn time. A subagent spawned during GREEN that completes during QA will be attributed to QA. This is an accepted imprecision — spawn-time attribution would require correlating parent tool_use IDs with subagent IDs, which adds complexity for marginal accuracy gain.

- **R-005** [unit]: The output JSON schema is:
  ```json
  {
    "branch": "string",
    "feature": "string",
    "computed_at": "ISO timestamp",
    "sessions": ["session-id-1"],
    "total_cost_usd": 0.00,
    "total_input_tokens": 0,
    "total_output_tokens": 0,
    "total_cache_write_tokens": 0,
    "total_cache_read_tokens": 0,
    "by_phase": [
      {"phase": "string", "cost_usd": 0.00, "input_tokens": 0, "output_tokens": 0, "cache_write_tokens": 0, "cache_read_tokens": 0, "turns": 0}
    ],
    "by_subagent": [
      {"description": "string", "agent_type": "string", "cost_usd": 0.00, "tokens": 0, "turns": 0}
    ],
    "pricing_used": {"model-id": {"input": 0, "output": 0, "cache_write": 0, "cache_read": 0}},
    "model_breakdown": [
      {"model": "string", "cost_usd": 0.00, "turns": 0}
    ],
    "unknown_models": [],
    "warnings": []
  }
  ```
  All USD values are rounded to 6 decimal places. Consistency invariant (holds at 6-decimal precision): `total_cost_usd == sum(by_phase[].cost_usd) == sum(by_subagent[].cost_usd)`. The `by_subagent` array includes an `{"description": "orchestrator", "agent_type": "parent", ...}` entry for non-subagent turns, ensuring both breakdowns account for 100% of cost. Consumers must never sum both breakdowns — they are orthogonal views of the same total. The cost artifact always undercounts by the invoking /cdocs session's cost (accepted).

- **R-006** [unit]: Pricing defaults are hardcoded in the script for models observed in actual session transcripts. Overrides are configurable via `workflow.pricing` in `workflow-config.json`:
  ```json
  {"workflow": {"pricing": {"claude-opus-4-6": {"input": 15, "cache_write": 18.75, "cache_read": 1.50, "output": 75}}}}
  ```
  Values are USD per million tokens. The script converts to per-token internally. Config pricing overrides defaults for matching model IDs. Missing models fall back to hardcoded defaults, then to median pricing per R-003. Hardcoded defaults use exact model ID strings from transcripts: `claude-opus-4-6`, `claude-sonnet-4-6`, `claude-haiku-4-5-20251001`. Additional model IDs can be added to defaults as they appear in real transcripts. Validation: all pricing values must be positive numbers. Values exceeding $500 per million tokens are rejected as likely per-token/per-million confusion. Non-numeric or negative values produce an error JSON, not silent fallback.

- **R-007** [unit]: Dashboard's "Cost by Phase" section reads cost artifacts (`cost-*.json`) instead of token-log JSONL files. Shows per-phase USD cost, percentage of total, and turn count. If any cost artifacts contain non-empty `unknown_models`, the section shows an asterisk note: "* includes estimated pricing for unrecognized models." If `warnings` is non-empty, surface those too. Falls back to token-log data with a note "(token count only — run /cdocs to compute USD cost)" when no cost artifacts exist.

- **R-008** [unit]: `/cdocs` calls `scripts/compute-session-cost.sh` as its last step (after writing workflow-history.md and all other documentation). The script computes cost for the current feature and writes the artifact to `.correctless/artifacts/cost-{branch-slug}.json`. This timing means the artifact captures all pipeline phases except the /cdocs invocation itself — an accepted small undercount. `/cdocs` then reads the artifact to append a cost summary line to the workflow-history.md entry: "Cost: ${total} (phase breakdown)". Prerequisite: add `Bash(*compute-session-cost.sh*)` to cdocs's allowed-tools frontmatter (AP-008).

- **R-009** [unit]: `/cverify` writes `actual_cost_usd` to the calibration entry by reading the cost artifact (`.correctless/artifacts/cost-{branch-slug}.json`) if it exists. If the artifact doesn't exist (e.g., /cdocs hasn't run yet), `actual_cost_usd` is omitted from the calibration entry — not set to 0, just absent. The `actual_tokens` field continues to be summed from token-log JSONL (existing behavior) for backward compatibility.

- **R-010** [unit]: `/cmetrics` reads cost artifacts for ROI calculations. "Cost per bug caught" shows actual USD: "Across {N} features, you spent ${X} and caught {B} bugs — ${X/B} per bug caught pre-merge." Falls back to token-count-based estimates when cost artifacts are missing.

- **R-011** [unit]: All consumers degrade gracefully when cost data is missing. The script itself exits 0 on all error paths (session dir not found, no matching sessions, no audit trail, malformed entries). Dashboard and /cmetrics show informative fallback messages, never errors.

- **R-012** [unit]: Subagent cost is computed by reading `{session-dir}/{session-uuid}/subagents/agent-*.jsonl` and `agent-*.meta.json`. Each subagent's description and type come from meta.json. Token usage is summed from the subagent's transcript. Subagent cost is included in the parent session's total and in the `by_subagent` breakdown. If subagent transcripts exist but meta.json is missing, description defaults to `"unknown"` and type defaults to `"unknown"`. Infrastructure subagents (transcripts not matching `agent-*.jsonl`, e.g., `compact-*.jsonl`, `aside_question-*.jsonl`) are internal Claude Code housekeeping — their cost is included in `total_cost_usd` and `by_phase` but excluded from `by_subagent`. This keeps the subagent breakdown focused on pipeline work, not Claude Code overhead.

- **R-013** [unit]: The script handles multi-session features (features that span multiple Claude Code sessions). All sessions whose transcripts contain entries with `gitBranch` matching the target branch are included. Cost is summed across all matching sessions. The `sessions` array in the output lists all contributing session IDs.

- **R-014** [unit]: Add ABS-026 to `.correctless/ARCHITECTURE.md` for the cost artifact contract. Sole writer: `scripts/compute-session-cost.sh` (invoked by `/cdocs`). Consumers: `scripts/generate-dashboard.sh` (R-007), `/cverify` (R-009), `/cmetrics` (R-010). Schema: R-005. Degradation: all consumers handle missing artifacts gracefully (R-011). The cost artifact always undercounts by the invoking /cdocs session's cost.

- **R-015** [unit]: Add TB-006 to `.correctless/ARCHITECTURE.md` for `~/.claude/projects/` filesystem reads. Crosses: Claude Code internal session storage → Correctless artifact pipeline. Identity assertion: files generated by Claude Code runtime on the local machine. Invariant: the script reads only structured fields (model, usage tokens, gitBranch, timestamps) — never includes `.message.content` in output JSON. Violated when: raw message text is included in cost artifacts or passed to agent context. This TB also covers `/cmetrics`'s existing `~/.claude/usage-data/` reads.

- **R-016** [unit]: Update ABS-006 in `.correctless/ARCHITECTURE.md` to note: "As of session-cost-analysis, the `total_cost_usd` and token usage fields produced by the PostToolUse hook are zeros because PostToolUse payloads do not include these fields (see Claude Code issue #11008). The hook's metadata (phase, skill, timestamps, agent descriptions) remains useful. For real cost data, see ABS-026 (cost artifact computed from session transcripts). The cost artifact is the canonical source of USD cost. Token-log is retained for phase timing and skill metadata only."

- **R-017** [unit]: Add ENV-009 to `.correctless/ARCHITECTURE.md`: "Claude Code stores session transcripts as JSONL files under `~/.claude/projects/{project-dir}/`. The directory structure (`{project-dir}/{session-uuid}.jsonl`, `{session-uuid}/subagents/agent-*.jsonl`) and JSONL schema are Claude Code internal — not a public API. If Claude Code changes its storage layout, `scripts/compute-session-cost.sh` degrades gracefully (exit 0 with error JSON per R-011) but produces no cost data."

- **R-018** [unit]: `/cdocs` updates AGENT_CONTEXT.md script count (17→18) and adds `compute-session-cost.sh` to the scripts description list.

## Won't Do

- **Real-time cost tracking via PostToolUse hooks** — PostToolUse hooks don't receive token/cost data. Claude Code feature request [#11008](https://github.com/anthropics/claude-code/issues/11008) tracks this. If/when Claude Code adds these fields, the hook can be updated and the transcript-based approach becomes a validation fallback.
- **Modifying token-tracking.sh** — The hook continues as-is. Its metadata (phase, skill, agent descriptions, timestamps) is still useful even though its token counts are zeros. Replacing or removing it is a separate concern.
- **Budget enforcement (stop pipeline at $X)** — Guardrail feature, not visibility. Deferred.
- **Cross-project cost aggregation** — /cmetrics concern, reads multiple artifacts.
- **Cache optimization recommendations** — Data will show cache rates, but recommendations are out of scope.
- **Spawn-time phase attribution for subagents** — Would require correlating parent tool_use IDs with subagent transcript IDs. Completion-time attribution is accepted (R-004 note).
- **Server tool use pricing** — `server_tool_use.web_search_requests` and `web_fetch_requests` fields exist in transcripts but are currently all zeros. If Anthropic introduces billable server tool use, the cost formula will undercount. Accepted simplification.
- **Cache tier pricing** — `cache_creation.ephemeral_5m_input_tokens` and `ephemeral_1h_input_tokens` sub-breakdowns exist but are priced identically today. If Anthropic introduces tiered cache pricing, the flat aggregation will be wrong. Accepted simplification.
- **Cross-project fallback scan** — Removed during review (F-02). Scanning all `~/.claude/projects/` directories for cwd matches creates cross-project information leakage. Two discovery paths only: candidate derivation + config override.

## Risks

- **Session transcript format is Claude Code internal** — could change without notice.
  1. Accept — the user is a Correctless developer and will see breakage immediately. The script is isolated and easy to update. R-003 emits warnings for unrecognized transcript formats.

- **Pricing changes** — model pricing may change after defaults are hardcoded.
  1. Mitigate — configurable via `workflow.pricing` in workflow-config.json. R-006 validates pricing values.

- **Multi-session discovery may be slow** — scanning all JSONL files for matching gitBranch requires reading entry headers.
  1. Mitigate — read only the first matching entry per file (early exit). 191 session files is manageable.

- **Large session transcripts** — a long session (100MB+) may be slow to process with jq. Aggregate subagent transcripts can reach 400MB+.
  1. Accept — runs once per feature at /cdocs time, not interactively. Uses `jq -R` streaming, not `jq -s` (AP-014).

- **Session directory discovery convention** — `repo_root | tr '/' '-'` may not match Claude Code's internal path derivation on all systems (spaces, symlinks, trailing slashes).
  1. Mitigate — R-002 provides a config override (`workflow.session_dir`) with validation. No cross-project fallback scan.

## Open Questions

- **OQ-001**: Should the calibration system eventually use `actual_cost_usd` as a signal alongside `actual_tokens`? The existing 200K-token auto-raise threshold in ABS-005 is effectively dead — `actual_tokens` from the token-log PostToolUse hook has always been zero (the premise of this feature). This feature creates the data for a dollar-based threshold (e.g., "features averaging $30+ at standard intensity → consider high"), which is more meaningful than token counts. Deferred to a follow-up spec where the right dollar threshold can be determined from accumulated cost data. The 200K-token threshold should be acknowledged as non-functional in ABS-005 documentation.
