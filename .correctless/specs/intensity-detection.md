# Spec: Add Per-Feature Intensity Detection to /cspec

## What

Add automatic intensity detection to `/cspec` so that every new spec gets a recommended intensity level (standard/high/critical) based on what the feature touches. The detection uses four signals: file paths, keywords, trust boundaries from ARCHITECTURE.md, and antipattern/QA history for the affected area. The recommendation is stored in a new `## Metadata` section in the spec and cached as `feature_intensity` in the workflow state file. The user always sees the recommendation with reasoning and can override in either direction. No downstream skills change behavior in this stage — the field is written but not consumed. This lets the detection be calibrated across real features before Stage 3 wires it into skill behavior.

## Rules

- **R-001** [unit]: `/cspec` SKILL.md contains an "Intensity Detection" section that describes the four detection signals: file path patterns, keyword matching, trust boundary references from ARCHITECTURE.md, and antipattern/QA finding history for affected files. The section is NOT gated by intensity level — it runs for all projects at all intensity levels.

- **R-002** [unit]: The Intensity Detection section defines the signal-to-intensity mapping. File paths matching hooks/, security-related skills, or setup produce at least `high`. Keywords matching "auth", "credential", "payment", "encrypt", "token", "secret", "session", "certificate", "CSRF", "injection" in the spec or feature description produce at least `high`. Keywords matching "trust boundary", "adversary", "threat model", "penetration" produce `critical`. Trust boundary references (TB-xxx) in the spec produce at least `high` — if ARCHITECTURE.md contains no TB-xxx entries, this signal is dormant (not an error). An antipattern matches if its description references files, modules, or patterns that overlap with the feature's scope; a QA finding matches if its `rule_ref` references a spec in the same area. Two or more antipattern matches or 3+ historical QA findings produce at least `high`. When `antipatterns.md` does not exist, the antipattern signal is dormant. When no `qa-findings-*.json` files exist, the QA history signal is dormant. A dormant signal does not contribute to the recommendation.

- **R-003** [unit]: The detection section specifies that when a project has fewer than 5 completed features (count `###` headers in `docs/workflow-history.md`; if the file does not exist, the count is 0), the recommendation includes an explicit humility qualifier: language indicating low confidence due to limited project history. When the project has 5+ completed features, the recommendation states its confidence without the qualifier.

- **R-004** [unit]: `/cspec` SKILL.md instructs the spec agent to present the intensity recommendation to the user as the first item in the human presentation step (Step 8), before walking through the rules. The presentation includes: the recommended level, the signals that triggered it (with specific file paths or keywords), and options to accept, raise, lower, or override with a custom level. The recommended option is marked "(recommended)".

- **R-005** [unit]: Every spec produced by `/cspec` includes a `## Metadata` section at the top containing at minimum: `Task` (feature name), `Intensity` (the approved level: standard/high/critical), `Intensity reason` (which signals triggered the recommendation, or "user override" if overridden), and `Override` (none, raised, or lowered — indicating whether the user changed the recommendation).

- **R-006** [integration]: After the user approves the spec (including the intensity), `/cspec` writes `feature_intensity` to the workflow state file via a `workflow-advance.sh set-intensity "level"` subcommand. The value matches the approved intensity from the spec's Metadata section. The spec agent does NOT write directly to the state file via jq — `workflow-advance.sh` is the only state file writer (PAT-004).

- **R-007** [integration]: The `workflow-advance.sh` script has a `set-intensity` subcommand that accepts a value of `standard`, `high`, or `critical`, validates it, and writes `feature_intensity` to the state file. Invalid values produce an error and exit non-zero. The `init` command does not set `feature_intensity` (it's set later by /cspec after detection). The `status` command displays `feature_intensity` when present.

- **R-008** [unit]: If `workflow-config.json` contains `workflow.allow_intensity_downgrade: false`, the detection still runs and recommends, but the user cannot lower the intensity below the recommended level. They can still raise it. If the field is absent or `true`, the user can override in both directions. This is a new optional config field — not present in default templates.

- **R-009** [unit]: The Intensity Detection section runs for ALL projects regardless of whether `workflow.intensity` is set in config. When `workflow.intensity` is set, it acts as a floor — the detection can recommend higher but not lower than the configured project-level intensity. When absent, detection runs freely with `standard` as the baseline.

- **R-010** [integration]: The detection signals are configurable via an optional `workflow.intensity_signals` object in `workflow-config.json`. If absent, the built-in defaults from R-002 are used. If present, the object can override signal mappings using this structure: `{"path_patterns": [{"glob": "hooks/*", "intensity": "high"}], "keywords": [{"word": "auth", "intensity": "high"}], "keyword_floor": "high", "path_floor": "high"}`. If `intensity_signals` is present but malformed (missing expected keys, invalid intensity values, non-array where array expected), the detection falls back to built-in defaults from R-002 and logs a one-line warning. Valid intensity values are: standard, high, critical.

- **R-011** [unit]: The existing "Step 7: Recommend Intensity (Full Mode)" section in `/cspec` SKILL.md is replaced by the new Intensity Detection section. The old 4-bullet heuristic and the "(Full Mode)" gate are both removed. The new section runs for all projects at all intensity levels and is referenced from the spec-writing flow as the new Step 7 (after Step 6: Check Drift Debt, before Step 8: Present to Human).

- **R-012** [unit]: Both spec templates are updated with a `## Metadata` section containing placeholder fields for Task, Intensity, Intensity reason, and Override. The Lite template (`templates/spec-lite.md`) gets a new Metadata section at the top. The Full template (`templates/spec-full.md`) has its existing Metadata section extended with the Intensity, Intensity reason, and Override fields (preserving existing fields: Created, Status, Impacts, Branch, Research). Existing specs without Metadata are valid — the section is required for new specs only, not retroactively added.

- **R-013** [unit]: When multiple detection signals fire, the final recommendation is the highest intensity level among all triggered signals. The ordering is: standard < high < critical. If no signals trigger, the recommendation is `standard` (or the project floor from R-009, whichever is higher).

## Won't Do

- Downstream skill behavior changes based on `feature_intensity` (Stage 3)
- Per-file intensity within a single feature (intensity is per-feature, highest-wins)
- Automatic intensity setting without user confirmation
- Changes to `/creview`, `/ctdd`, or any skill other than `/cspec`
- Changes to the gate hook or audit trail based on intensity
- ML or embedding-based detection — signals are simple pattern matching
- Intensity configuration tables in SKILL.md files (Stage 3)

## Risks

- **Detection recommends wrong level too often** — kills trust in the system. Mitigation: humility qualifier for new projects (R-003), user always overrides (R-004), configurable signals (R-010). Stage 2 is explicitly for calibration — the field has no downstream effect yet.

- **Metadata section adds friction to every spec** — 4 lines at the top of every spec. Mitigation: accepted — 4 lines is minimal, and the intensity field is load-bearing for Stage 3. The template handles the formatting.

- **`workflow.intensity_signals` config complexity** — users could break detection with bad config. Mitigation: signals config is optional (R-010), defaults are sensible, bad config falls back to built-in defaults with a warning.

## Open Questions

- None — scope resolved in brainstorm and review.
