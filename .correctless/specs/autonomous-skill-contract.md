# Spec: Autonomous Skill Contract

## Metadata
- **Task**: autonomous skill contract
- **Recommended-intensity**: high
- **Intensity**: high
- **Intensity reason**: adds ABS-030 artifact with sole-writer contract, modifies all 29 skill files, changes /cauto pipeline dispatch model, touches TB-004 orchestrator autonomy boundary
- **Override**: raised (was standard, raised per RS-010)

## What

Skills currently block the `/cauto` pipeline at every human decision point — doc approval, architecture entry triage, refactoring confirmation, etc. Each pause breaks the pipeline's `context: fork` execution model and causes PMB-006-class stalls. This feature adds an `interaction_mode` frontmatter field to every skill, defining whether it runs interactively (pausing for human input) or autonomously (providing sensible defaults and logging decisions). When `/cauto` dispatches a skill, it passes `mode: autonomous` via the Task prompt text; the skill uses its declared defaults instead of pausing, and the orchestrator logs every autonomous decision to a reviewable artifact presented at the end of the pipeline.

The `interaction_mode` field is documentation-only — it is not consumed by the Claude Code plugin loader (ENV-007 documents that the loader parses only `name`, `description`, `tools`, and `model`). It is consumed by structural tests and by `/cauto` via `Read` tool when determining dispatch behavior.

## Rules

- **R-001** [unit]: Every SKILL.md file in the distribution (`skills/*/SKILL.md`) must have an `interaction_mode` field in its YAML frontmatter with value `autonomous`, `interactive`, or `hybrid`. The field is documentation-only (not parsed by the Claude Code plugin loader per ENV-007).

- **R-002** [unit]: Skills with `interaction_mode: autonomous` must have a `## Autonomous Defaults` section listing every known decision point with its default choice and rationale. Each default entry must have a unique ID (AD-001, AD-002, ...) for log referencing.

- **R-003** [unit]: Skills with `interaction_mode: interactive` must NOT have an `## Autonomous Defaults` section.

- **R-004** [unit]: Skills with `interaction_mode: hybrid` must have an `## Autonomous Defaults` section AND at least one decision point marked `escalate: always` (decisions that always require human input regardless of mode).

- **R-005** [integration]: When `/cauto` dispatches a skill via Task, the task prompt must include the literal string `mode: autonomous` in its first 10 lines. The skill detects this by checking its prompt context for the string. When `mode: autonomous` is present, the skill uses defaults from its `## Autonomous Defaults` section instead of pausing for human input. When absent, the skill runs interactively (fail-open). Fail-open is correct: the failure mode "pipeline stalls waiting for input" is annoying but safe; fail-closed "skill silently applies defaults when user expected to be asked" is worse.
  Entry: `/cauto` pipeline invocation (Task sub-agent spawn)
  Through: skill dispatch → skill reads mode flag from prompt context → skill executes with defaults
  Exit: skill completes without pausing for human input; decisions returned as structured output

- **R-006** [unit]: `/cauto` is the sole writer of `.correctless/artifacts/autonomous-decisions-{branch_slug}.jsonl` (ABS-030). Skills do not write to this file directly. Instead, each skill returns its autonomous decisions as structured output in its response. After each skill completes, `/cauto` parses the decisions from the skill's output and appends them to the JSONL. Each entry has fields: `skill` (string), `decision_id` (AD-xxx or AD-UNLISTED-N), `default_applied` (string), `rationale` (string), `timestamp` (ISO 8601), `escalation_deferred` (boolean, default false), `original_escalation_reason` (string, null unless escalation_deferred is true).
  Enforcement: `/cauto` verifies JSONL growth after each skill invocation. For skills with `interaction_mode: autonomous` or `hybrid`, if the skill's response contains no parseable decisions and the skill has known decision points in its `## Autonomous Defaults` section, `/cauto` logs a warning in the pipeline summary (advisory, not blocking — first iteration).

- **R-007** [integration]: At the end of the `/cauto` pipeline (before PR creation), the orchestrator must read the autonomous decisions JSONL and present a summary to the human. The summary groups decisions by skill and shows each default that was applied. Normal autonomous decisions are informational (not a gate). Deferred escalations (R-011) are presented under a separate "Deferred Escalations" heading with a confirmation prompt — the human must acknowledge deferred escalations before PR creation proceeds (see R-013).
  Entry: `/cauto` pipeline completion (post-/cdocs, pre-PR)
  Through: orchestrator reads decisions JSONL → formats summary → presents deferred escalations for confirmation
  Exit: summary presented; deferred escalations acknowledged; PR creation proceeds

- **R-008** [unit]: In interactive mode (when `mode: autonomous` is not present in prompt context), skills must show their defaults as `(default)` annotations alongside decision options. Example: `1. Add entry (default) 2. Skip 3. Defer`. The human can accept the default or choose an alternative.
  Enforcement: prompt-level (no structural mechanism available — the default annotation is a UX convention in LLM output, not a file artifact).

- **R-009** [unit]: The `interaction_mode` field must be consistent with `context: fork`. Skills with `context: fork` must NOT have `interaction_mode: interactive` (this is AP-027 — fork-declared skills cannot receive follow-up input). Skills with `context: fork` and `interaction_mode: hybrid` are permitted but must implement R-011 deferred-escalation machinery.

- **R-010** [unit]: A structural test must verify ALL SKILL.md files in the distribution (discovered via glob `skills/*/SKILL.md`, not a hardcoded count) have a valid `interaction_mode` field. The test must fail if any distribution skill is missing the field or has an invalid value. The test must NOT hardcode the expected skill count (AP-024). User-created custom skills outside the distribution are not covered by this test.

- **R-011** [unit]: When a `hybrid` skill runs in a forked context (`context: fork`) and hits an `escalate: always` decision point, it must not attempt human interaction. Instead, it applies the default and returns the decision in its structured output with `escalation_deferred: true` and `original_escalation_reason` (string). `/cauto` writes this to the JSONL per R-006. The deferred escalation is surfaced in the end-of-pipeline summary (R-007) under the "Deferred Escalations" heading.

- **R-012** [unit]: The structural test (R-010) must additionally verify that skills with `context: fork` and `interaction_mode: hybrid` have deferred-escalation markers in their `## Autonomous Defaults` section (at least one `escalate: always` entry with a documented default). This prevents a skill author from declaring `hybrid` + `fork` without implementing the R-011 machinery.

- **R-013** [integration]: When the end-of-pipeline summary (R-007) contains deferred escalations, `/cauto` must present them as a confirmation prompt before PR creation. The prompt lists each deferred escalation with its default and original escalation reason, then asks: "N deferred escalations were made autonomously. Review above and confirm to proceed with PR creation, or request re-run of specific skills interactively." The human must confirm before the PR is created. Normal autonomous decisions (non-deferred) remain informational and do not gate PR creation.
  Entry: `/cauto` post-summary, pre-PR
  Through: orchestrator filters deferred escalations → presents confirmation prompt
  Exit: human confirms → PR creation proceeds; human requests re-run → pipeline pauses

- **R-014** [unit]: When a skill running in autonomous mode encounters a decision point not listed in its `## Autonomous Defaults` section, it must apply a universal fallback: choose the first option (the recommended default per the Decision Points convention) and return it in its structured output with `decision_id: AD-UNLISTED-{N}` and `escalation_deferred: true`. The end-of-pipeline summary (R-007) must highlight unlisted decisions separately under the "Deferred Escalations" heading so incomplete defaults sections are visible.

## Won't Do

- **Per-decision override at pipeline end**: The human sees what was decided autonomously but cannot retroactively change individual decisions from the summary. To change a decision, re-run the skill interactively.
- **preferences.md integration**: Autonomous defaults are defined in skill SKILL.md sections, not in preferences.md. preferences.md remains for project-level preferences (QA triage, commit granularity, etc.), not skill-level decision defaults.
- **Autonomous spec creation**: `/cspec` remains interactive — the Socratic brainstorm requires human input. `/cauto` Phase 3 already handles this correctly by running `/cspec` interactively before the pipeline.
- **Autonomous spec approval**: The mandatory spec approval gate (INV-023, PRH-001 in /cauto) is untouched. Human approval of the spec before implementation is non-negotiable.
- **Harness-level interaction_mode parsing**: The `interaction_mode` field is documentation-only. It is not added to the Claude Code plugin loader contract (ENV-007). `/cauto` reads it via the Read tool.

## Risks

- **Default quality degrades over time**: Autonomous defaults may become stale as the project evolves. Mitigation: defaults are visible in interactive mode too (R-008), so users see them regularly and can flag bad defaults.
- **Decision log noise**: If skills have many decision points, the end-of-pipeline summary could be long. Mitigation: group by skill, show count + details only for non-obvious decisions. Accepted — verbosity is better than opacity.
- **Skill authors forget to add defaults**: New skills added without `## Autonomous Defaults` will stall the pipeline. Mitigation: R-010 structural test catches missing `interaction_mode`; R-002 catches missing defaults section for autonomous skills. R-014 AD-UNLISTED fallback handles incomplete defaults sections at runtime.
- **Deferred escalation masks bad defaults**: A hybrid skill's `escalate: always` decision running in fork context applies the default silently (R-011). If the default is wrong, the damage is done before the human sees the deferred escalation summary. Mitigation: deferred escalations gate PR creation via R-013; the human reviews before the PR exists. Accepted residual risk for non-architectural deferred decisions.
- **AD-UNLISTED accumulation signals stale defaults**: If many decisions hit the AD-UNLISTED fallback (R-014), the `## Autonomous Defaults` sections are incomplete. Mitigation: unlisted decisions are surfaced prominently in the deferred escalation summary; patterns of unlisted decisions should trigger updating the skill's defaults section.

## Architecture Updates

- **ABS-030**: Autonomous decisions JSONL (`.correctless/artifacts/autonomous-decisions-{branch_slug}.jsonl`). Sole writer: `/cauto` orchestrator. Consumers: R-007 pipeline summary, `/cwtf` accountability. Enforcement: `/cauto` verifies JSONL growth after each skill invocation (R-006). Deferred escalations gate PR creation (R-013).

## Decision Points

When presenting choices to the user:

1. Present numbered options with the recommended option first
2. Mark the recommended option with "(recommended)"
3. Include 2-4 options maximum
4. Always end with: "Or type your own: ___"
5. Accept the number, the option name, or a typed response

## Open Questions

None — all resolved during spec review.

### Resolved

- **OQ-001** (resolved): Per-decision marking, not severity threshold. Severity assessment is a runtime judgment call that varies by context. Per-decision marking is static, testable, and reviewable in the skill file. "This decision always needs a human" is a property of the decision, not the situation.
- **OQ-002** (resolved): Persist the decisions log after PR merge. `/cwtf` needs it to answer "why did the pipeline make this choice?" Storage cost is negligible (JSONL).

### Review Findings Incorporated

All 12 findings from `/creview-spec` accepted and incorporated:
- **RS-001**: Clarified `interaction_mode` as documentation-only (R-001, What section)
- **RS-002**: Added ABS-030 entry (Architecture Updates section)
- **RS-003**: Made `/cauto` sole writer (R-006 rewrite)
- **RS-004**: Specified mode delivery mechanism — literal string in Task prompt, fail-open (R-005 rewrite)
- **RS-005**: Added AD-UNLISTED fallback (R-014)
- **RS-006**: Extended structural test for hybrid+fork (R-012)
- **RS-007**: Added enforcement to R-006 — `/cauto` verifies JSONL growth
- **RS-008**: Glob discovery, no hardcoded count (R-010 rewrite)
- **RS-009**: Deferred escalation confirmation gate before PR creation (R-013)
- **RS-010**: Raised intensity to high (Metadata)
- **RS-011**: Scoped R-010 to distribution skills only
- **RS-012**: Explicit prompt-level enforcement label on R-008
