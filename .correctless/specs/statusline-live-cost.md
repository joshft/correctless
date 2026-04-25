# Spec: Statusline Live Cost

## Metadata
- **Task**: statusline-live-cost
- **Recommended-intensity**: high
- **Intensity**: high
- **Intensity reason**: file path signal (hooks/statusline.sh) triggers high; project floor enforces high
- **Override**: none

## What

Add per-feature cost tracking to the Correctless statusline. The statusline already shows session cost from Claude Code (`.cost.total_cost_usd`) and the workflow phase/task. This feature adds three cost data points to the workflow section: total feature cost, per-phase cost, and cost since the current phase started. Uses a background-refresh cache so the statusline stays fast — `compute-session-cost.sh` takes ~2 seconds, far too slow for inline rendering.

## Rules

- **R-001** [unit]: The statusline's workflow section (Section 4) adds a cost display after the existing phase/QA/time content. Format: `$X.XX` for the feature total. When no cost data is available OR `total_cost_usd` is 0, the cost display is omitted entirely. Omission covers both "no data yet" (missing cache) and "measured zero" (failed computation or fresh workflow). The distinction is not useful in a statusline context — users see the full cost artifact for precise data.

- **R-002** [unit]: Cost data is read from a cache file at `.correctless/artifacts/cost-cache-{branch-slug}.json`. The cache file is a subset of the full cost artifact: `{"total_cost_usd": N, "by_phase": [{"phase": "...", "cost_usd": N}], "computed_at": "ISO", "current_phase_cost_usd": N}`. The `current_phase_cost_usd` field is the cost attributed to the current workflow phase (from `by_phase` matching the active phase). If the cache file doesn't exist or is older than 30 seconds, the statusline reads stale data (or omits cost) and spawns a background refresh. Staleness is determined by comparing the file's modification time against the current epoch: `$(date +%s)` minus `stat -c %Y` (Linux) or `stat -f %m` (macOS). If neither `stat` variant works, fall back to parsing `computed_at` from the cache JSON. The cache read uses a single jq call that extracts all needed fields (`total_cost_usd`, `current_phase_cost_usd`), consistent with the existing bulk-parse pattern.

- **R-003** [unit]: Background refresh: when the cache is stale (>30 seconds old or missing), the statusline spawns `compute-session-cost.sh --cache --phase "$PHASE"` in the background (`& disown`). The background process writes output to a temp file in `.correctless/artifacts/` and atomically renames it to the cache path (`mv`). Direct stdout redirection to the cache file is not permitted — partial writes corrupt the JSON for concurrent readers. The lock file (`.correctless/artifacts/cost-cache.lock`) is created by the statusline *before* the background spawn, containing `$!` (the background PID). This prevents the TOCTOU gap where a second render could spawn before the background process creates its own lock. The background process deletes the lock file on completion (via `trap`). Only one background computation runs at a time — if the lock file exists and the PID in it is still running (`kill -0`), skip the refresh. Stale locks (PID not running) are auto-cleaned. If the background process exits abnormally, the trap ensures lock cleanup.

- **R-004** [unit]: The cost display in the statusline uses this format within Section 4:
  ```
  ⚙ task-name · GREEN R1 · 3m · $47.23 ($12.50 in GREEN)
  ```
  The feature total (`$47.23`) is from `total_cost_usd`. The phase cost (`$12.50 in GREEN`) is from `current_phase_cost_usd` with the phase name. If `current_phase_cost_usd` is 0 or null, only the total is shown: `$47.23`. If both are unavailable, cost is omitted entirely.

- **R-005** [unit]: The statusline's existing session cost in Section 3 (`$X.XX` from `.cost.total_cost_usd`) is unchanged. The new feature cost in Section 4 is additive — both are visible simultaneously. Section 3 shows session-level cost (Claude Code's number), Section 4 shows feature-level cost (Correctless's number from transcript analysis).

- **R-006** [unit]: The cache file is gitignored (lives under `.correctless/artifacts/` which is already gitignored). The lock file is also under `.correctless/artifacts/`. Neither is committed or synced.

- **R-007** [unit]: `compute-session-cost.sh` is extended with a `--cache` flag that writes a lightweight cache JSON (just total + by_phase + current_phase_cost) instead of the full cost artifact. The `--cache` flag also accepts a `--phase` argument to compute `current_phase_cost_usd` from the by_phase breakdown. The `--phase` argument accepts the raw workflow phase name (e.g., `tdd-impl`, `tdd-qa`), matching the phase names used in `by_phase` entries of the cost artifact. Usage: `compute-session-cost.sh --cache --phase tdd-impl`. When `--cache` is specified, the script writes output to stdout (the caller handles atomic file placement per R-003). Without `--cache`, behavior is unchanged (full artifact written directly).

- **R-008** [unit]: The statusline performs at most one additional file read (the cache file) and one additional jq field extraction compared to the pre-feature statusline. No synchronous subprocess spawns for cost computation. The combined synchronous overhead must remain under 100ms (the existing 50ms target is relaxed slightly to accommodate the cache read). When spawning the background refresh, the spawn itself (`& disown`) adds negligible time. The background computation takes ~2 seconds but does not block the statusline render.

- **R-009** [unit]: When no active workflow exists (no state file), the cost display is omitted. Cost tracking only shows during active Correctless workflows.

- **R-010** [unit]: The cache refresh interval (30 seconds) is not configurable in v1. It's hardcoded in the statusline hook. A future version could read it from workflow-config.json.

## Won't Do

- **Configurable refresh interval** — hardcoded 30 seconds is fine for v1.
- **Cost breakdown in the statusline** — per-subagent or per-model cost would clutter the statusline. The full breakdown is in the cost artifact and dashboard.
- **Cumulative cross-session cost** — the cache recomputes from transcripts on each refresh, so it naturally includes all sessions. No incremental tracking needed.
- **Cost alerts/thresholds** — budget enforcement is a separate feature (deferred in the roadmap).

## Risks

- **Background process orphaning** — the `& disown` computation could outlive the statusline.
  1. Mitigate — lock file with PID prevents concurrent runs. Stale locks auto-cleaned.

- **Cache file corruption** — partial write if the background process is killed mid-write.
  1. Mitigate — atomic write via temp file + mv (same pattern as install manifest).

- **Cost computation fails silently** — `compute-session-cost.sh` exits 0 on all errors (R-011 from session-cost-analysis spec). A failed computation writes `{"total_cost_usd": 0}` to the cache.
  1. Accept — showing no cost is better than blocking the statusline. R-001 omits cost display when `total_cost_usd` is 0, so failed computations result in no cost display, not wrong cost display.

## Open Questions

None.
