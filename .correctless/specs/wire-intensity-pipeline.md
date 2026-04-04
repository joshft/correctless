# Spec: Wire Intensity into Remaining Pipeline Skills

## Metadata
- **Task**: wire-intensity-pipeline
- **Intensity**: standard
- **Intensity reason**: LLM instruction file changes only, no security-sensitive code
- **Override**: none

## What

Add Intensity Configuration tables and verbatim Effective Intensity sections to the 5 remaining pipeline skills (/cspec, /ctdd, /cverify, /cdocs, /cstatus) so each adapts behavior based on effective intensity. The Effective Intensity section text is copied verbatim from `/creview` (established in Stage 3). Each skill's table defines what changes at standard/high/critical. The R-009 consistency rule from Stage 3 already requires `max(project_intensity, feature_intensity)` and `standard < high < critical` in all skills that use it — this spec extends that to the 5 new skills.

## Rules

### /cspec — Intensity Configuration

- **R-001** [unit]: `skills/cspec/SKILL.md` contains an "## Intensity Configuration" section with a markdown table. Columns: empty header, Standard, High, Critical. Rows: Sections, Research agent, STRIDE, Question depth. Values match: Standard = "5 + typed rules" / "If needed" / "No" / "Socratic", High = "12 + invariants" / "Always (security)" / "Yes" / "Adversarial", Critical = "12 + all templates" / "Always" / "Yes" / "Exhaustive".

- **R-002** [unit]: `skills/cspec/SKILL.md` contains a verbatim copy of the Effective Intensity section from `/creview`. The section includes: `max(project_intensity, feature_intensity)`, ordering `standard < high < critical`, the 3-step process (read project intensity, read feature intensity, compute max), the fallback chain, and the no-active-workflow handling.

- **R-003** [unit]: `/cspec` SKILL.md references the Intensity Configuration table in its body to vary behavior. The body must contain these testable phrases conditioned on effective intensity: "spec-lite.md" for standard, "spec-full.md" for high+, "STRIDE" for high+, "research agent" conditioned on intensity, and "exhaustive" or "refuse vague" for critical. At standard: use `templates/spec-lite.md`, 5-section format, Socratic brainstorm. At high: use `templates/spec-full.md`, 12 sections including invariants, research agent always runs for security-relevant topics, STRIDE analysis required. At critical: all templates loaded, exhaustive question depth (refuse vague answers), research agent always runs.

- **R-004** [unit]: The Intensity Configuration section and Effective Intensity section are positioned in `/cspec` SKILL.md after the skill title/description and before "Progress Visibility". The existing "## Detect Intensity" section (line ~11, which reads `workflow.intensity` for template selection) is REPLACED by the new Effective Intensity section — there must not be two separate sections that both read intensity from config. The template selection logic (standard → `spec-lite.md`, high+ → `spec-full.md`) moves into R-003's body references, conditioned on effective intensity instead of `workflow.intensity` alone. The "## Intensity Detection" section (line ~462, Stage 2's per-feature signal detection) is left unchanged — it is a separate concern (detection runs during spec writing, not during intensity reading).

### /ctdd — Intensity Configuration

- **R-005** [unit]: `skills/ctdd/SKILL.md` contains an "## Intensity Configuration" section with a markdown table. Columns: empty header, Standard, High, Critical. Rows: Test audit, QA rounds, Mutation testing, Calm resets. Values match: Standard = "Blocking" / "2 max" / "No" / "After 3 failures", High = "Strict" / "3 max" / "Yes" / "After 2 failures", Critical = "Strict + PBT recommendations" / "5 max (convergence, capped)" / "Yes" / "After 2 + supervisor notified".

- **R-006** [unit]: `skills/ctdd/SKILL.md` contains a verbatim copy of the Effective Intensity section from `/creview`.

- **R-007** [unit]: `/ctdd` SKILL.md references the Intensity Configuration table in its body to vary behavior. The body must contain these testable phrases conditioned on effective intensity: "2 max" or "2 rounds" for standard QA rounds, "mutation testing" conditioned on high+, "PBT" for critical test audit. The QA round maximum, test audit strictness, mutation testing requirement, and calm reset threshold are conditioned on effective intensity. The body must reference the table values, not hardcode separate intensity branches.

- **R-008** [unit]: The Intensity Configuration and Effective Intensity sections are positioned after the skill title and before "Philosophy" or "Progress Visibility" (whichever comes first in /ctdd).

### /cverify — Intensity Configuration

- **R-009** [unit]: `skills/cverify/SKILL.md` contains an "## Intensity Configuration" section with a markdown table. Columns: empty header, Standard, High, Critical. Rows: Rule coverage, Dependencies, Architecture. Values match: Standard = "Exists + weak detection" / "List + license" / "Basic compliance", High = "Full matrix + Serena trace" / "List + CVE + maintenance" / "Full + drift detection", Critical = "Full + mutation survivor analysis" / "Full audit" / "Full + cross-spec + prohibitions".

- **R-010** [unit]: `skills/cverify/SKILL.md` contains a verbatim copy of the Effective Intensity section from `/creview`.

- **R-011** [unit]: `/cverify` SKILL.md references the table to vary verification depth. The body must contain these testable phrases conditioned on effective intensity: "Serena trace" for high+ rule coverage, "CVE" for high+ dependency checks, "mutation survivor" for critical, "cross-spec" for critical. At standard: exists check + weak test detection for rule coverage, list new dependencies. At high: full coverage matrix, CVE and maintenance checks on dependencies, drift detection. At critical: mutation survivor analysis, full dependency audit, cross-spec consistency and prohibition checks.

- **R-012** [unit]: The Intensity Configuration and Effective Intensity sections are positioned after the skill title and before "Progress Visibility".

### /cdocs — Intensity Configuration

- **R-013** [unit]: `skills/cdocs/SKILL.md` contains an "## Intensity Configuration" section with a markdown table. Columns: empty header, Standard, High, Critical. Rows: Scope, Post-merge. Values match: Standard = "AGENT_CONTEXT + feature docs" / "Suggest /cmetrics", High = "add Mermaid diagrams" / "Suggest /caudit", Critical = "add fact-checking subagent" / "Require /caudit".

- **R-014** [unit]: `skills/cdocs/SKILL.md` contains a verbatim copy of the Effective Intensity section from `/creview`.

- **R-015** [unit]: `/cdocs` SKILL.md references the table to vary documentation scope. The body must contain these testable phrases conditioned on effective intensity: "Mermaid" for high+, "fact-checking subagent" for critical, "/caudit" for high+ post-merge, "Require /caudit" for critical. At standard: update AGENT_CONTEXT.md and feature docs, suggest /cmetrics after merge. At high: also generate Mermaid diagrams, suggest /caudit. At critical: spawn a fact-checking subagent for doc accuracy, require /caudit after merge.

- **R-016** [unit]: The Intensity Configuration and Effective Intensity sections are positioned after the skill title and before "Progress Visibility".

### /cstatus — Intensity Configuration

- **R-017** [unit]: `skills/cstatus/SKILL.md` contains an "## Intensity Configuration" section with a markdown table. Columns: empty header, Standard, High, Critical. Rows: Display. Values match: Standard = "Phase + next step + time in phase" / High = "add stale workflow warning", Critical = "add token budget warning".

- **R-018** [unit]: `skills/cstatus/SKILL.md` contains a verbatim copy of the Effective Intensity section from `/creview`.

- **R-019** [unit]: `/cstatus` SKILL.md references the table to vary display detail. The body must contain these testable phrases conditioned on effective intensity: "stale workflow" for high+, "token budget" for critical. At standard: show phase, next step, and time in phase. At high: add stale workflow detection and warning. At critical: add token budget tracking and warning.

- **R-020** [unit]: The Intensity Configuration and Effective Intensity sections are positioned after the skill title and before "Behavior" (the first content section in /cstatus).

### Cross-Cutting

- **R-021** [integration]: All 5 newly updated skills plus `/creview` (6 total pipeline skills) contain the string `max(project_intensity, feature_intensity)` and the ordering `standard < high < critical`. This extends the Stage 3 R-009 consistency requirement to the full pipeline.

- **R-022** [integration]: The Effective Intensity section in all 5 skills is character-for-character identical to the Effective Intensity section in `/creview` SKILL.md. The test extracts the text between `## Effective Intensity` and the next `##`-level heading in each file, normalizes trailing whitespace, and diffs them against the `/creview` canonical copy. The `/creview` Effective Intensity section includes a comment noting it is canonical and copied to cspec, ctdd, cverify, cdocs, cstatus.

## Won't Do

- Behavioral changes inside /creview — that was Stage 3, already done
- Changes to the 7 gated skills — their gates were updated in Stage 3
- Changes to workflow-advance.sh — effective intensity is computed in SKILL.md instructions, not bash
- New config options — uses existing `workflow.intensity` and `feature_intensity`
- Intensity detection changes — Stage 2, stable

## Risks

- **Large spec (22 rules) but mechanical**: All 5 skills get the same pattern. Mitigation: the pattern is validated from Stage 3. Tests are structural (grep for sections, tables, strings). Implementation is copy-paste of the Effective Intensity section + adding tables and body references.

- **Verbatim copy drift**: If someone edits the Effective Intensity section in one skill, the others go stale. Mitigation: R-022 tests for character-for-character identity. Any edit to one will fail tests for the others, forcing a coordinated update.

## Open Questions

- None — scope resolved in brainstorm.
