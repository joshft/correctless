# Spec: Merge Lite and Full into Single Plugin Distribution

## What

Merge the two separate plugin distributions (correctless-lite with 19 skills, correctless-full with 26 skills) into a single `correctless` plugin with all 26 skills. sync.sh copies to one distribution directory instead of two. Full-only skills (caudit, cmodel, creview-spec, cupdate-arch, cpostmortem, cdevadv, credteam) are visible but gated — they check the project's intensity level and warn if invoked below their minimum threshold. Existing users experience zero behavioral change: Lite users see the same skills behaving the same way plus 7 new gated skills, Full users see identical behavior. This is Stage 1 of the dynamic rigor system — structural change only, no new detection logic.

## Rules

- **R-001** [integration]: sync.sh copies all 26 skills, hooks, templates, helpers, and the setup script to a single `correctless/` distribution directory. The `correctless-lite/` and `correctless-full/` directories no longer exist in the repository.

- **R-002** [integration]: sync.sh `--check` exits 0 when the single `correctless/` distribution matches source files, and exits non-zero when they differ.

- **R-003** [integration]: The `.claude-plugin/marketplace.json` file contains exactly one plugin entry named `correctless` with source `./correctless`.

- **R-004** [integration]: For a project with no `workflow.intensity` configured, the setup script produces: workflow-config.json (without `workflow.intensity` field), hooks (gate, advance, statusline, audit trail), and common templates (ARCHITECTURE.md, AGENT_CONTEXT.md, antipatterns.md). It does NOT produce Full-only meta files (workflow-effectiveness.json, drift-debt.json).

- **R-005** [integration]: For a project with `workflow.intensity` configured, the setup script produces everything in R-004 plus: Full-only meta files (workflow-effectiveness.json, drift-debt.json, external-review-history.json) and invariant templates. The `workflow.intensity` field is preserved in the generated config.

- **R-006** [unit]: Each of the 7 Full-only skills (caudit, cmodel, creview-spec, cupdate-arch, cpostmortem, cdevadv, credteam) contains an intensity gate that reads the project's intensity from `workflow-config.json`. The gate checks `workflow.intensity` — if present, use it; if absent, default to `standard`.

- **R-007** [unit]: The intensity gate in each Full-only skill defines a minimum intensity threshold: `caudit` requires `high`, `cmodel` requires `critical`, `creview-spec` requires `high`, `cupdate-arch` requires `high`, `cpostmortem` requires `standard` (available to all), `cdevadv` requires `standard` (available to all), `credteam` requires `critical`.

- **R-008** [unit]: When a gated skill is invoked below its minimum intensity, it does not execute the skill body. Instead it prints: the skill name, the required minimum intensity, the current project intensity, and instructions to override (either `--force` flag or setting intensity in the spec). The message is informational, not an error — the user chose a lower intensity deliberately.

- **R-009** [unit]: When a gated skill is invoked with the `--force` override or at/above its minimum intensity, it executes normally with no gate message.

- **R-010** [integration]: All Full-only templates (invariant templates, workflow-config-full.json, workflow-effectiveness.json, drift-debt.json, external-review-history.json) and helpers (PBT guides) are included in the single `correctless/` distribution.

- **R-011** [integration]: The `/chelp` skill lists all 26 skills. Skills that require a minimum intensity above standard are annotated with their minimum (e.g., "high+" or "critical+") in the help output.

- **R-012** [integration]: Skills that previously detected Lite vs Full mode by checking for `workflow.intensity` in config continue to work. If `workflow.intensity` is absent, the skill behaves as it did in Lite mode (standard intensity). If present, it behaves as it did in Full mode at the configured intensity.

- **R-013** [unit]: The README.md no longer describes two separate plugins. It describes one plugin with intensity levels. The install instructions show a single `plugin install correctless` command. The comparison table is replaced by an intensity level table. The README includes explicit migration commands for both paths (users who had `correctless-lite` installed and users who had `correctless` Full installed).

- **R-014** [unit]: The `docs/design/correctless.md` and `docs/design/correctless-lite.md` files are merged into a single `docs/design/correctless.md` that covers all intensity levels.

- **R-015** [integration]: The pre-commit hook `correctless-sync-check` validates the single `correctless/` distribution directory instead of two.

- **R-016** [integration]: All existing tests that reference `correctless-lite/` or `correctless-full/` paths are updated to reference `correctless/`. Tests that verified "Lite has N skills, Full has M skills" are replaced by "correctless has 26 skills." Tests that compared content between Lite and Full are replaced by source-to-distribution comparison.

- **R-017** [integration]: The setup script detects old Lite/Full distribution directories (`.claude/skills/workflow/correctless-lite/` or `.claude/skills/workflow/correctless-full/`) in the consuming project and cleans them up during installation. It prints: "Detected old Lite/Full directories. Migrating to unified plugin." This ensures `git pull && ./setup` handles the migration transparently for git-clone users.

- **R-018** [unit]: All skills that reference "Lite mode", "Full mode", "Lite", or "Full" as mode identifiers in their instruction text are updated to use intensity-level terminology instead (e.g., "at standard intensity" vs "at high+ intensity"). The `workflow.intensity` config check remains unchanged — only the user-facing language changes. Priority targets: `/cstatus` and `/chelp` (most frequently invoked, user-facing entry points).

## Won't Do

- Dynamic intensity detection based on file paths, keywords, or trust boundaries (Stage 2)
- Per-feature intensity stored in spec metadata (Stage 2)
- Intensity configuration tables in each SKILL.md (Stage 3)
- Changes to skill behavior based on intensity level (Stage 3)
- Auto mode or supervisor architecture (future)
- Changes to workflow-gate.sh or workflow-advance.sh phase logic
- Changes to the state machine transitions

## Risks

- **Breaking existing installs** — Users who have `correctless-lite` or `correctless` (full) installed via the marketplace will need to uninstall and reinstall. Mitigation: document the migration in README and CHANGELOG. The marketplace update itself is seamless; the user just needs `/plugin uninstall` + `/plugin install correctless`.

- **Merge of design spec documents (R-014) is large** — `correctless.md` is 155KB and `correctless-lite.md` is 30KB. Merging these into one coherent document is significant editorial work. Mitigation: accept risk — these are historical design docs, not actively referenced by skills. A light merge (combine with clear section headers) is sufficient.

- **Test suite rewrite scope** — Many tests reference distribution paths. Mitigation: the changes are mechanical (find/replace paths) but the volume is high. Run full suite after each test file change.

## Open Questions

- None — scope was fully resolved in the Socratic brainstorm.
