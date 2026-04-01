# Spec: QoL Improvements

## What

Four quality-of-life improvements to the Correctless workflow: a `/cquick` lightweight mode for small changes that don't need the full pipeline, persistent workflow history that survives merge, time-in-phase display in `/cstatus`, and spec templates for consistent formatting.

## Rules

### Item 1: /cquick — Lightweight Mode

- **R-001** [unit]: A new skill `skills/cquick/SKILL.md` exists with frontmatter defining the `/cquick` slash command.

- **R-002** [unit]: `/cquick` SKILL.md instructs the agent to: implement the change with TDD (write test → implement → verify tests pass) and commit. No spec, no review, no verify, no docs steps. If on main/master, tell the user to create a feature branch first (same guard as `/cspec`) — do not auto-create branches.

- **R-003** [unit]: `/cquick` SKILL.md includes a scope guard: if the change exceeds 50 LOC or touches more than 3 files, the skill stops and says "This is bigger than a quick fix — run `/cspec` to start the full workflow."

- **R-004** [unit]: `/cquick` SKILL.md requires tests — it's TDD without the ceremony, not no-TDD. The agent must write at least one test before implementing.

- **R-005** [integration]: `/cquick` is included in the Lite skill list in `sync.sh` so it syncs to `correctless-lite/`. It is also included in Full.

- **R-006** [unit]: `/chelp` SKILL.md lists `/cquick` in the "Other" commands section with description "Quick fix with TDD — no spec/review for small changes".

### Item 2: Workflow History

- **R-007** [unit]: `/cdocs` SKILL.md contains an instruction to append a workflow summary to `docs/workflow-history.md` before advancing to `documented`. The summary includes: date, feature name, branch, rules count, QA rounds, findings fixed, and a one-line description.

- **R-008** [unit]: The workflow history entry is append-only — `/cdocs` never rewrites or deletes existing entries in `docs/workflow-history.md`. If the file doesn't exist, create it with a header.

- **R-009** [unit]: `docs/workflow-history.md` is NOT gitignored — it persists across merges as a committed file.

### Item 3: Time-in-Phase Display

- **R-010** [unit]: `/cstatus` SKILL.md contains an instruction to calculate and display time in the current phase using `phase_entered_at` from the state file. Format: "Phase: {phase} ({duration})" where duration is human-readable (e.g., "12 minutes", "2 hours", "1 day").

- **R-011** [unit]: `/cstatus` SKILL.md contains an instruction to warn proactively at thresholds: >1 hour suggests re-running the skill for the current phase, >24 hours suggests the workflow may be stalled (existing stale detection, but now surfaced earlier).

### Item 4: Spec Templates

- **R-012** [unit]: A template file `templates/spec-lite.md` exists containing the Lite spec skeleton (What, Rules, Won't Do, Risks, Open Questions sections with placeholder markers).

- **R-013** [unit]: A template file `templates/spec-full.md` exists containing the Full spec skeleton (all sections scaled to standard intensity with placeholder markers).

- **R-014** [unit]: `/cspec` SKILL.md contains an instruction to read the appropriate template file and use it as the skeleton when drafting, rather than reconstructing the format from the skill instructions.

### Item 5: Skill Registration

- **R-015** [unit]: A documentation page `docs/skills/cquick.md` exists describing the `/cquick` skill.

## Won't Do

- `/cquick` does NOT bypass the workflow gate — if a workflow is already active on the branch, `/cquick` refuses. It's for standalone small fixes, not mid-workflow shortcuts.
- Workflow history does NOT include token cost — that requires session-meta data which is deferred.
- Spec templates do NOT auto-fill any content — they're skeletons with section headers and placeholder markers that the agent fills in.

## Risks

- `/cquick` scope guard (R-003) relies on the agent counting LOC and files — LLMs are bad at counting. Mitigation: the guard is a prompt instruction, not enforcement. If the agent miscounts, the user still sees the change growing and can switch to `/cspec` manually.
- Workflow history could grow unbounded. Mitigation: one paragraph per feature, append-only. At 50 features it's ~50 lines. Acceptable for years.

## Open Questions

- None.
