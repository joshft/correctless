# Spec: Wire Intensity into /creview

## Metadata
- **Task**: wire-intensity-creview
- **Intensity**: standard
- **Intensity reason**: LLM instruction file changes only, no security-sensitive code
- **Override**: none

## What

Add an Intensity Configuration table to `/creview` SKILL.md so it scales review thoroughness based on the feature's effective intensity. The effective intensity is `max(project_intensity, feature_intensity)` — whichever is higher wins. Three levels: standard (current behavior), high (routes to /creview-spec), critical (routes to /creview-spec + zero-unresolved threshold). This also establishes the Intensity Configuration table pattern used by the other pipeline skills in subsequent work, and updates the gated skill gate check to use effective intensity instead of project-only.

## Rules

- **R-001** [unit]: `/creview` SKILL.md contains an "## Intensity Configuration" section near the top (after the frontmatter and title, before "Progress Visibility") with a markdown table. The table has columns: empty header, Standard, High, Critical. Rows: Agents, Finding threshold. The table values match: Standard = "1 + security checklist" / "Disposition required", High = "Routes to /creview-spec" / "All addressed", Critical = "Routes to /creview-spec + external model" / "Zero unresolved".

- **R-002** [unit]: `/creview` SKILL.md contains an "## Effective Intensity" section that instructs the agent to determine effective intensity as `max(project_intensity, feature_intensity)`. The section instructs reading `workflow.intensity` from `.correctless/config/workflow-config.json` for project intensity (defaulting to `standard` if absent), and `feature_intensity` from the workflow state file via `workflow-advance.sh status`. The max is computed using the ordering: standard < high < critical. If `feature_intensity` is absent (not yet set by /cspec), use project intensity alone.

- **R-003** [unit]: When effective intensity is `standard`, the review body matches current behavior: all 8 checks run, security checklist fires automatically, findings require disposition. No behavioral change from the current SKILL.md at standard.

- **R-004** [unit]: When effective intensity is `high`, `/creview` SKILL.md instructs the agent to tell the user: "This feature's effective intensity is high. Run `/creview-spec` instead for the 4-agent adversarial review. To proceed with single-pass review anyway, confirm below." The agent presents numbered options: (1) Switch to /creview-spec (recommended), (2) Proceed with single-pass review. If the user chooses single-pass, the review runs with all checks at standard behavior. The routing is a recommendation, not a block.

- **R-005** [unit]: When effective intensity is `critical`, `/creview` SKILL.md instructs the agent to tell the user: "This feature's effective intensity is critical. Run `/creview-spec` instead — it includes 4-agent adversarial review plus external model verification." The same numbered options as R-004 are presented. If the user proceeds with single-pass, findings have zero-unresolved threshold: the agent does not advance workflow state until every finding has a disposition (accept, reject, modify, or defer). The agent states this requirement before presenting findings.

- **R-006** [integration]: The `workflow-advance.sh status` command outputs `feature_intensity` when present in the state file. The `/creview` SKILL.md instructs reading this value from the status output, not by parsing the state file directly (consistent with PAT-004 — `workflow-advance.sh` is the interface to state). If the status output contains no Intensity line, treat `feature_intensity` as absent and apply the fallback chain from R-011.

- **R-007** [unit]: The "When to use" line at the top of `/creview` SKILL.md is updated to reference effective intensity instead of the current hardcoded "standard intensity" / "high+ intensity" language. It should say the skill adapts based on effective intensity rather than telling the user to manually choose between /creview and /creview-spec.

- **R-008** [unit]: The 7 gated skills (caudit, cdevadv, cmodel, cpostmortem, credteam, creview-spec, cupdate-arch) have their Intensity Gate sections updated to check effective intensity (`max(project, feature)`) instead of only `workflow.intensity`. The gate reads both `workflow.intensity` from config and `feature_intensity` from workflow state, computes the max, and compares against the skill's threshold. This means a standard-intensity project with a critical-intensity feature unlocks `/caudit` for that feature. For skills whose threshold is `standard` (cdevadv, cpostmortem), the effective intensity rewrite still applies for correctness and future-proofing, but the gate will pass at all current intensity levels.

- **R-009** [unit]: The effective intensity computation (`max(project, feature)`) is documented in the SKILL.md instructions clearly enough that every skill computes it the same way. The computation is NOT in workflow-advance.sh (it's an LLM instruction, not a bash function) — but the ordering (standard < high < critical) and the max logic must be identical across all skills that use it. Each of the 7 gated skills and `/creview` must contain the string `max(project_intensity, feature_intensity)` and the ordering `standard < high < critical`. The test checks for these strings in each file.

- **R-010** [unit]: The Intensity Configuration table and Effective Intensity section are positioned in `/creview` SKILL.md after the skill title/description and before "Progress Visibility". This establishes the pattern: intensity configuration is the first behavioral section a skill reads, before it does any work.

- **R-011** [unit]: When `feature_intensity` is absent from the workflow state (e.g., running `/creview` on a spec that was written before Stage 2, or after a manual `workflow-advance.sh init` without running `/cspec`), the effective intensity falls back to `workflow.intensity` from config. If that is also absent, the default is `standard`. The fallback chain is: `feature_intensity` → `workflow.intensity` → `standard`. If `workflow-advance.sh status` indicates no active workflow (no state file), effective intensity falls back to `workflow.intensity` from config, then to `standard`. The review still runs — it does not require active workflow state.

## Won't Do

- Intensity tables for the other 5 pipeline skills (/cspec, /ctdd, /cverify, /cdocs, /cstatus) — separate subsequent work after this pattern is validated
- A fourth "light" intensity level — standard is already light enough for low-risk changes; `/cquick` serves the "less than standard" use case as a separate workflow
- Changes to `/creview-spec` SKILL.md behavior — it already has its own gate and full behavior
- Adding `effective_intensity` as a field in the workflow state file — it's computed on read, not stored
- CLI flag to override effective intensity per-skill — users override via `/cspec` intensity approval
- Changing the detection logic from Stage 2 — that's stable and not touched here

## Risks

- **Routing friction at high/critical**: Users who always run `/creview` now get redirected to `/creview-spec`. Mitigation: routing is a recommendation with override, not a block (R-004, R-005).

- **Inconsistent effective intensity computation across skills**: If the max logic is copy-pasted into 8 SKILL.md files with slight variations, they'll drift. Mitigation: R-009 requires specific strings present in each file; /cverify can grep for consistency.

- **Gated skill gate change (R-008) has broad scope**: Touching 7 gated skills in one PR. Mitigation: the change is mechanical (same pattern applied 7 times) and the gate is a soft warning, not a hard block — the user can always `--force`.

## Open Questions

- None — scope resolved in brainstorm and review.
