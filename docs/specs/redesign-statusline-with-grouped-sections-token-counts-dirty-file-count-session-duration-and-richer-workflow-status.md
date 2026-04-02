# Spec: Statusline Redesign

## What

Rewrite `hooks/statusline.sh` to show richer, grouped information with `│` separators. Four sections: repo state, model/context/tokens, session stats, and workflow status. Every element is optional — if the data isn't available, that element (or entire section) is omitted. Ships to all Correctless users via sync.

Target layout (all data available, workflow active):

```
correctless/ main 3 dirty │ Opus 4.6 4% 19.7k : 2.1k (in:out) │ 23m $0.51 +4/-0 │ ⚙ add-auth · GREEN R2 · 12m
```

## Rules

- **R-001** [unit]: Cost is formatted to 2 decimal places (e.g., `$0.51` not `$0.5133767499999999`). If cost is `null` or `0`, the cost element is omitted.
- **R-002** [unit]: Token counts are formatted as integers below 1000 (e.g., `847`), one decimal with `k` suffix for 1000-999999 (e.g., `19.7k`), one decimal with `M` suffix for 1000000+ (e.g., `1.2M`). Format is `{in} : {out} (in:out)` where `in` = `context_window.total_input_tokens` and `out` = `context_window.total_output_tokens`. If either token field is `null`, the entire token element is omitted.
- **R-003** [unit]: Context window percentage is color-coded: green below 40%, yellow 40-69%, red 70%+. If usage data is `null`, the context element is omitted.
- **R-004** [integration]: Dirty file count is computed from `git status --porcelain` line count. Shown as `N dirty` after the branch name. If count is 0 or git is unavailable, the dirty element is omitted.
- **R-005** [unit]: Session duration is computed from `total_duration_ms` and formatted as `Nm` (under 60 min) or `Nh Nm` (60 min+). If duration is `null` or `0`, the duration element is omitted.
- **R-006** [integration]: Workflow section shows task name, phase, QA rounds (if non-zero), and time in phase. Format: `⚙ {task} · {PHASE} R{n} · {time}`. QA rounds element omitted when 0. Entire section omitted when no workflow is active.
- **R-007** [unit]: Workflow phase is color-coded: cyan for spec/review/model phases, red for RED (tdd-tests), green for GREEN (tdd-impl), yellow for QA/VERIFY, gray for done/verified/documented, orange for AUDIT.
- **R-008** [integration]: Workflow time-in-phase is computed from `phase_entered_at` in the state file. If `phase_entered_at` is missing or unparsable, the time element is omitted. Formatted same as R-005.
- **R-009** [unit]: Task name in workflow section is truncated to 20 characters max. If longer, truncate and append `…`.
- **R-010** [integration]: Sections are separated by ` │ ` (space-pipe-space). A section is omitted entirely (including its separator) if all elements within it are empty.
- **R-011** [integration]: Override warning `⚠override({N})` is appended to the workflow section when an override is active, showing remaining calls.
- **R-012** [integration]: Spec-update warning `⚠spec×{N}` is appended to the workflow section when `spec_updates` is >= 2.
- **R-013** [integration]: The script must be synced to both `correctless-lite/hooks/statusline.sh` and `correctless-full/hooks/statusline.sh` via `sync.sh`. The source of truth is `hooks/statusline.sh`.
- **R-014** [unit]: Lines delta shows `+N/-N` with green/red coloring. If both added and removed are 0 or `null`, the element is omitted.
- **R-015** [integration]: The statusline is registered in `.claude/settings.json` (project-level) as `statusLine.command` pointing to `.claude/hooks/statusline.sh`. The setup script must handle three cases: (a) no settings.json — include statusLine in the fresh template, (b) settings.json exists without statusLine — add it via jq merge, (c) settings.json exists with a different statusLine — overwrite it with the Correctless statusline.
- **R-016** [integration]: The `git status` call uses `--no-optional-locks` to avoid lock conflicts with other git operations.
- **R-017** [unit]: If `context_window.context_window_size` is `null`, `0`, or missing, the context percentage element is omitted (avoids division by zero).
- **R-018** [unit]: If token counts are both `0`, the token element is omitted.

## Won't Do

- Cache hit ratio (adds complexity, not clearly actionable at a glance)
- CCS account indicator (niche — only relevant for multi-account users, already in system statusline)
- Vim mode indicator (already handled by system statusline)
- Ahead/behind remote (requires `git rev-list` to remote which may not exist)

## Risks

- Shell portability: `date` arithmetic for time-in-phase differs between GNU and BSD — mitigation: use portable approach or test on both
- Token formatting edge cases: very large or very small numbers — mitigation: test boundary values (0, 999, 1000, 999999, 1000000)
- Task name may contain special characters that break printf — mitigation: sanitize before display

## Open Questions

_(all resolved)_

## Resolved

- **OQ-001**: Dirty count includes untracked files (default `--porcelain`, no `-uno`). Rationale: surfaces stray docs/plan/notes files that need cleanup or gitignore.
