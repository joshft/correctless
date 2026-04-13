# Spec: Auto Mode Phase 3

## Metadata
- **Created**: 2026-04-12T18:00:00Z
- **Status**: reviewed
- **Impacts**: semi-auto-mode, auto-mode-phase-2
- **Branch**: auto-mode-phase3
- **Research**: null
- **Recommended-intensity**: high
- **Intensity**: high
- **Intensity reason**: touches skills/cauto/SKILL.md (orchestrator skill), agents/supervisor.md (trust boundary extension), hooks/ path signal, keywords: trust boundary (TB-004 orchestrator autonomy expansion)
- **Override**: none

## Context

Auto Mode Phase 3 extends `/cauto` to orchestrate the full workflow from prompt to PR — including spec writing and review — eliminating the requirement for the human to manually invoke `/cspec` and `/creview-spec` before `/cauto`. The human still approves the spec (one mandatory gate), but the machine handles everything else. Simultaneously, the supervisor agent gains a broader mandate: it can handle escalations that Phase 2 hard-stopped, informed by preferences, intent, and past decisions. This reduces the number of hard stops requiring human presence during implementation.

Phase 3 also addresses a failure class observed in a real user case (Andrew's clawker Branch 1, 2026-04-12): an agent issues `workflow-advance.sh override` with self-authored justification, gains autonomy during the override window, produces work that doesn't match the justification or the spec, and completes the workflow with compromised ground truth. No checkpoint catches this because the override was accepted as human judgment and downstream phases trust the gate state. Phase 3 extends the supervisor to scrutinize **all agent actions during weakened-enforcement windows** — the supervisor becomes a sustained hostile reviewer for the window's duration, not just a discrete-event reviewer.

Together, these changes shift the human's role from "drive the process" to "approve the spec and review the output."

## Scope

**In scope:**
- Extended `/cauto` phase gate: accept invocation when no active workflow exists (prompt-driven start)
- Two entry modes: (a) interactive Socratic brainstorm via `/cspec`, (b) human provides a pre-written spec
- Autonomous review via `/creview-spec` (or `/creview` at standard intensity) with supervisor-triaged findings
- Mandatory human spec approval gate before implementation begins
- Supervisor mandate expansion: broader authority to handle escalations autonomously
- Supervisor context enrichment: preferences, intent summary, recent decision patterns
- Clear hard limits on supervisor authority (codified in supervisor agent contract)
- Review decision audit trail: findings the supervisor rejected visible in spec metadata
- Updated Auto Run Report: includes review decision summary and override scrutiny summary
- Override window scrutiny: supervisor reviews override issuance, per-action during window, and window closure
- Override log schema extension: supervisor review status, disposition, reasoning per override
- Base-commit cross-check for "pre-existing" override justifications
- Mechanical file-touch scope drift detection during override windows
- Spec-completeness check at override window closure (with concrete deliverable parsing)
- Override retry prevention (rejected overrides cannot be re-issued same run)
- Configurable supervisor mandate level in preferences.md (`conservative | moderate | aggressive`)

**Not in scope:**
- Factory mode (supervisor on remote machine, worker queue, parallel execution)
- Autonomous spec approval (Factory mode feature — human approves in Phase 3)
- Policy learning / calibration from supervisor decisions
- Notification channels (Telegram, Discord, webhooks)
- Parallel skill execution
- Auto-merge to main
- New Tier 2/3 agent types (uses existing supervisor and decision-agent)
- Generalization to other weakened-enforcement windows (budget exhaustion recovery, BLOCKING-finding acceptance) — same pattern, addressed after override scrutiny ships
- Automated revert of supervisor-rejected changes (escalation to human; revert is human action)
- Override prevention entirely (override remains valid; Phase 3 ensures it's reviewed, not blocked)

## Complexity Budget
- **Estimated LOC**: ~2500-3500
- **Files touched**: ~20-25
- **New abstractions**: ~4 (review-triage artifact ABS-018, supervisor mandate contract ABS-019, override scrutiny lifecycle ABS-020, override log extension)
- **Trust boundaries touched**: 1 (TB-004 orchestrator autonomy — extends scope significantly)
- **Risk surface delta**: high

## Prerequisites

- Phase 2 merged (PR #55) — required for supervisor, decision-routing, budget enforcement
- Supervisor agent (`agents/supervisor.md`) already exists with structured I/O contract
- **Supervisor agent contract update required**: Before GREEN, `agents/supervisor.md` must be updated with: (a) four new `activation_type` values (`review_triage`, `override_issued`, `override_action_review`, `override_window_closing`), (b) response schemas for each new type including override-specific vocabularies (`approve_override`, `reject_override`, `approve_window`, `reject_window`, `partial_accept`, `approve_action`, `reject_action`, `escalate_to_human`), (c) an `## Override Scrutiny Prefix` section containing the hostile prompt injection text for override-window activations, (d) review triage input schema (array of findings) and response schema (array of per-finding decisions). Per ABS-010, the agent file is the sole source of truth — incomplete contracts violate the abstraction.

## Architecture Notes for /cupdate-arch

The following entries are required during `/cupdate-arch` after implementation:
- **ABS-018**: Review-triage artifact contract (schema, lifecycle, locking, tamper detection via PAT-011 hash)
- **ABS-019**: Supervisor mandate contract (input extensions, mandate levels, hard-limit routing rules)
- **ABS-020**: Override scrutiny lifecycle (three-phase activation pattern, state machine, recovery procedures)
- **TB-004a or TB-005**: Supervisor decision authority decomposition (what supervisor can approve vs. what always goes to Tier 4)
- **PAT-014 candidate**: Structural enforcement over prompt-level instruction (9/15 review findings in this class across two consecutive Phase reviews — strong promotion signal)

## Review Finding Schema

The orchestrator must parse review skill prose output into a structured JSON format for batch supervisor triage. The canonical finding schema is:

```json
{
  "finding_id": "F-{sequential}",
  "source_agent": "red-team | assumptions | testability | design-contract",
  "category": "security | assumption | testability | design-contract | historical-pattern",
  "summary": "one-sentence description of the finding",
  "proposed_action": "add_rule | update_invariant | add_prohibition | add_boundary_condition | update_scope | flag_risk"
}
```

The orchestrator extracts findings from review skill output by identifying structured finding blocks in the skill's response. `finding_id` is assigned sequentially by the orchestrator (F-001, F-002, ...). `source_agent` is determined by which review agent produced the finding. `category` uses the controlled vocabulary above. `proposed_action` describes what the finding recommends. Both INV-021 (batch triage) and the review skills reference this schema.

## Cross-Reference Convention

Phase 2 (auto-mode-phase-2.md) defined INV-001 through INV-018. To avoid ambiguity in cross-references, Phase 3 invariants start at **INV-019**. References to Phase 2 invariants use bare `INV-0xx` (no prefix needed since the numbering ranges don't overlap).

## Design Decisions

- **Override scrutiny as sustained review, not discrete activations**: Phase 2's supervisor model is event-driven. Override windows require sustained review because each action during the window potentially compounds the initial weakening. Modeling override scrutiny as a distinct activation pattern (with its own types, its own counter, its own exemption from the main cap) is cleaner than trying to force it into the discrete-event model.

- **Supervisor has authority to block individual actions, not just escalate**: Phase 2's supervisor can approve, reject, or escalate decisions. For override scrutiny, the supervisor needs finer-grained action control — specifically, the ability to reject a single action within an active override without ending the whole window. This requires extending the supervisor response vocabulary with `reject_action`, which is distinct from `reject_override` (initial) and `reject_window` (closure). Three dispositions at three lifecycle points.

- **Base-commit verification is mechanical, not agent judgment**: The cross-check for "pre-existing" claims (INV-040) is deliberately mechanical — run the build on the base commit, diff the error output. This is not a judgment call the supervisor makes; it's a ground truth the supervisor receives as input to its review. This avoids the failure mode where the supervisor itself could be gamed by plausible reasoning.

- **Scope drift uses mechanical file-touch check as primary signal**: INV-041 routes scope drift to human review rather than auto-rejecting the action. The primary signal is mechanical: the orchestrator diffs the action to identify which files are touched, then checks whether those files are mentioned in the override reason, the spec's affected components, or the intent_summary. Files outside this set trigger scope drift. The supervisor's judgment about semantic relatedness is secondary to this file-touch check.

- **Structured deliverables as opt-in check with concrete parsing**: INV-042 only activates when the spec declares concrete deliverables. Detection is pinned to specific section headings and file-path extraction patterns (see INV-042 statement) so that TDD can test against fixtures rather than relying on agent judgment about what constitutes a "deliverable."

- **Retry prevention via rejected-overrides list**: PRH-006 is a structural guard against an agent learning which justifications supervisor accepts and retrying with rewording. The rejected-overrides list persists for the run. This may need refinement if it produces false positives (legitimately distinct overrides flagged as retries) but the default posture is fail-closed.

- **Batch review triage**: The supervisor triages review findings in batch (one activation with all findings) rather than individually (N activations). This is more efficient and provides cross-finding context. Hard-stop findings that need deeper evaluation can fall back to individual activation.

- **Review triage artifact is separate from decision record**: Review decisions go to `review-decisions-{branch_slug}.json`, not the DD-xxx decision record. Different lifecycle — written during review, not during implementation.

- **Configurable mandate level**: `preferences.md` gets a `supervisor_mandate` field with three levels: `conservative` (default — approve only decisions explicitly implied by spec), `moderate` (approve decisions consistent with spec intent), `aggressive` (approve any decision that doesn't violate prohibitions). Default is conservative.

- **Override-window activations use hostile prompt injection**: Override-window activations (`override_issued`, `override_action_review`, `override_window_closing`) use the base supervisor prompt with an injected prefix emphasizing hostility toward agent self-justification. The prefix is defined in `agents/supervisor.md` under a labeled section (e.g., `## Override Scrutiny Prefix`) and is included by the orchestrator when activation_type starts with `override_`. This makes hostility explicit and testable — the prefix exists as text in the agent file, not as an implicit behavioral expectation.

- **Post-override-rejection workflow path**: When the supervisor rejects an override issuance (INV-035, `reject_override`), the blocked action is escalated to the human as a hard stop (PRH-006 prevents retry). The escalation file includes the original gate block, the override reason, and the supervisor's rejection reasoning, giving the human full context to decide whether to manually apply the override, take a different approach, or abandon the action.

## Invariants

### Part A: Spec Pipeline Integration

### INV-019: Phase gate extension — prompt-driven start
- **Type**: must
- **Category**: functional
- **Statement**: `/cauto` must accept invocation when no active workflow exists on the current branch. When invoked without an active workflow, `/cauto` initializes the workflow (via `workflow-advance.sh init`) and enters the spec phase. When invoked with an active workflow in `review` or `review-spec` phase, existing Phase 2 behavior is preserved unchanged.
- **Boundary**: TB-004
- **Violated when**: `/cauto` refuses invocation when no workflow exists, or prompt-driven start bypasses `workflow-advance.sh init`
- **Guards against**: null
- **Test approach**: integration
- **Risk**: low
- **Implemented in**: (filled during GREEN)

### INV-020: Two entry modes — interactive or provided spec
- **Type**: must
- **Category**: functional
- **Statement**: When starting from no workflow, `/cauto` must support two entry modes: (a) interactive — invoke `/cspec` which runs the Socratic brainstorm with the human present, producing a spec; (b) provided — the human supplies a pre-written spec file path, which `/cauto` installs as the workflow spec and skips `/cspec`. In both modes, the spec must exist and be non-empty before review begins.
- **Boundary**: TB-004
- **Violated when**: `/cauto` only supports one entry mode, or review begins without a spec file, or provided spec path is not validated
- **Guards against**: null
- **Test approach**: integration
- **Risk**: low
- **Implemented in**: (filled during GREEN)

### INV-021: Autonomous review with supervisor triage (batch)
- **Type**: must
- **Category**: functional
- **Statement**: After the spec exists (from either entry mode), `/cauto` must invoke the review skill (`/creview-spec` at high+ intensity, `/creview` at standard). Review agents produce findings. Instead of presenting each finding to the human, all findings are passed to the supervisor agent in a single batch activation for triage. The supervisor evaluates each finding against the intent summary and preferences, returning `accept`, `reject`, or `hard_stop` for each. Accepted findings are auto-incorporated into the spec. Rejected findings are logged to a review decisions artifact. `hard_stop` findings trigger the spec approval gate with the finding highlighted.
- **Boundary**: TB-004
- **Violated when**: Review findings are presented to the human one-by-one (Phase 2 behavior), or supervisor-rejected findings are silently dropped without logging, or accepted findings are not incorporated into the spec
- **Guards against**: null
- **Test approach**: integration
- **Risk**: medium
- **Implemented in**: (filled during GREEN)

### INV-022: Review decisions artifact (with hash verification)
- **Type**: must
- **Category**: data-integrity
- **Statement**: All supervisor review triage decisions must be logged to `.correctless/artifacts/review-decisions-{branch_slug}.json`. Each entry contains: finding_id, source_agent (red-team, assumptions, testability, design-contract), finding_summary, supervisor_decision (accept/reject/hard_stop), supervisor_reasoning, timestamp. This artifact is referenced from the spec's metadata section and included in the Auto Run Report. The artifact is hash-verified per PAT-011: SHA-256 hash computed after triage completes, stored in workflow state, re-verified before the spec approval gate and before the Auto Run Report reads it. Hash mismatch (review decisions tampered after triage) triggers hard stop.
- **Boundary**: ABS-018
- **Violated when**: A review finding is triaged without logging, the artifact is missing after review completes, or the hash verification fails
- **Guards against**: null
- **Test approach**: unit
- **Risk**: medium
- **Implemented in**: (filled during GREEN)

### INV-023: Mandatory human spec approval gate
- **Type**: must
- **Category**: functional
- **Statement**: After autonomous review completes and findings are incorporated, `/cauto` must pause and present the spec to the human for approval. The human must explicitly approve before implementation begins. The presentation must include: (a) the final spec with all accepted findings incorporated, (b) a summary of review decisions (N accepted, M rejected, K hard-stopped), (c) a link to the review decisions artifact. The human's approval options are: approve (proceed to implementation), reject (abort pipeline), or revise (human edits spec, then re-approve).
- **Boundary**: TB-004
- **Violated when**: Implementation begins without explicit human approval, or the human cannot see what the review changed
- **Guards against**: null
- **Test approach**: integration
- **Risk**: high
- **Implemented in**: (filled during GREEN)

### INV-024: Workflow state transitions for Phase 3 flow
- **Type**: must
- **Category**: functional
- **Statement**: The Phase 3 flow must use existing workflow-advance.sh transitions in this order: `init` → `spec` phase → (interactive: human + `/cspec` writes spec) or (provided: `/cauto` installs spec) → `review-spec` or `review` (depending on intensity) → autonomous review with supervisor triage → spec approval gate → continue existing Phase 2 pipeline (`tdd-tests` → `tdd-impl` → `tdd-qa` → `done` → `verified` → `documented`). No new phase names are introduced — the existing state machine is reused.
- **Boundary**: PAT-004
- **Violated when**: Phase 3 introduces new phase names, or transitions skip existing phases, or `workflow-advance.sh` is bypassed
- **Guards against**: null
- **Test approach**: integration
- **Risk**: low
- **Implemented in**: (filled during GREEN)

### INV-025: Spec approval gate stores approval in workflow state
- **Type**: must
- **Category**: data-integrity
- **Statement**: When the human approves the spec, `/cauto` must record `spec_approved_by: "human"` and `spec_approved_at: <ISO timestamp>` in the workflow state via `workflow-advance.sh`. These fields are included in the Auto Run Report. When a provided spec is used, the approval still requires explicit human confirmation — providing a spec does not imply approval.
- **Boundary**: PAT-004
- **Violated when**: Spec approval is not recorded in workflow state, or providing a spec bypasses the approval gate
- **Guards against**: null
- **Test approach**: unit
- **Risk**: medium
- **Implemented in**: (filled during GREEN)

### INV-026: Auto Run Report includes review triage and override scrutiny summaries
- **Type**: must
- **Category**: functional
- **Statement**: The Auto Run Report (ABS-013) must be extended with two new sections when Phase 3 flow was used. (a) **"## Review Triage"**: count of findings by source agent, count accepted/rejected/hard-stopped, list of rejected findings with supervisor reasoning (for human audit), and any hard-stop findings escalated to the human during spec approval. (b) **"## Override Scrutiny"**: listed when override windows occurred during the run — each override with its issuance review disposition, per-action review count, closure disposition, any flagged scope drift, and the override-window activation counter. Override activity is high-signal for post-hoc review and must be prominent, not buried.
- **Boundary**: ABS-013
- **Violated when**: Auto Run Report omits either section when Phase 3 flow was used, or rejected findings / override activity are not visible
- **Guards against**: null
- **Test approach**: unit
- **Risk**: low
- **Implemented in**: (filled during GREEN)

### INV-027: Backward compatibility — existing /cauto behavior preserved
- **Type**: must
- **Category**: functional
- **Statement**: When `/cauto` is invoked with an active workflow in `review` or `review-spec` phase (the Phase 2 entry point), all existing behavior must be preserved unchanged. Phase 3 behavior only activates when no workflow exists or when the workflow is in `spec` phase. The Phase 2 test suite (`test-semi-auto-mode.sh`, `test-auto-agents.sh`, `test-auto-budget.sh`, `test-auto-safety.sh`, `test-auto-report.sh`) must continue to pass without modification.
- **Boundary**: null
- **Violated when**: Any existing Phase 2 test fails after Phase 3 changes, or Phase 2 invocation path behavior changes
- **Guards against**: null
- **Test approach**: integration
- **Risk**: medium
- **Implemented in**: (filled during GREEN)

### Part B: Supervisor Mandate Expansion

### INV-028: Supervisor mandate expansion — architectural decisions (with citation requirement)
- **Type**: must
- **Category**: functional
- **Statement**: The supervisor may approve architectural decisions (R-006 heuristics (a): new ABS-xxx or TB-xxx entries) when the decision is within the scope of the approved spec. The supervisor must cite the specific spec section (heading or invariant ID) that authorizes the decision. The orchestrator validates that the cited section exists in the spec — if the citation is missing or references a non-existent section, the decision is treated as out-of-scope and triggers hard stop. The supervisor must include the rationale and citation in its reasoning, and flag the decision for human review in the Auto Run Report. Architectural decisions outside the spec scope still trigger hard stop.
- **Boundary**: TB-004, ABS-019
- **Violated when**: Supervisor approves an architectural decision without citing a specific spec section, or the cited section doesn't exist, or supervisor fails to flag architectural approvals for human review
- **Guards against**: null
- **Test approach**: integration
- **Risk**: high
- **Implemented in**: (filled during GREEN)

### INV-029: Supervisor context enrichment — preferences, patterns, and spec scope
- **Type**: must
- **Category**: functional
- **Statement**: The supervisor input contract must be extended with three new fields: (a) `preferences`: the project preferences from `.correctless/preferences.md` (or built-in defaults), including `supervisor_mandate` level, (b) `decision_patterns`: a JSON object summarizing past decisions from the current run with this schema: `{"categories": {"<category>": {"<disposition>": <count>}}, "total_decisions": <int>, "tier_distribution": {"tier0": <int>, "tier1": <int>, "tier2": <int>, "tier3": <int>}}`, (c) `spec_scope`: the approved spec's scope section text (for mandate boundary checks). These fields provide context for consistent decision-making across the pipeline run.
- **Boundary**: ABS-019
- **Violated when**: Supervisor activations lack preferences, decision pattern context, or spec scope, or preferences are read from a stale source, or decision_patterns does not match the specified schema
- **Guards against**: null
- **Test approach**: unit
- **Risk**: low
- **Implemented in**: (filled during GREEN)

### INV-030: Supervisor hard limits — non-negotiable boundaries
- **Type**: must
- **Category**: security
- **Statement**: The following conditions must always trigger hard stop regardless of supervisor mandate expansion or mandate level: (a) unspecced dependencies — any new dependency not mentioned in the approved spec, (b) security constraint relaxation (Phase 2 PRH-001), (c) budget/time exceeded (Phase 2 INV-008), (d) intent summary tampered (Phase 2 INV-013), (e) policy file tampered (Phase 2 INV-018), (f) CLAUDE.md modifications (R-006(e)), (g) spec fundamental restructure. The supervisor cannot approve any of these — they bypass the supervisor entirely and go directly to Tier 4.
- **Boundary**: TB-004, ABS-019
- **Violated when**: Any of the listed conditions is routed to the supervisor instead of Tier 4, or the supervisor returns `approve` for any of them
- **Guards against**: null
- **Test approach**: unit
- **Risk**: critical
- **Implemented in**: (filled during GREEN)

### INV-031: Supervisor mandate boundary — dependency guard
- **Type**: must
- **Category**: security
- **Statement**: When the orchestrator detects a new dependency (R-006(d) heuristic), it must check whether the dependency is mentioned in the approved spec. If specced: route to supervisor for approval. If not specced: hard stop immediately with reason "unspecced dependency: {name}". The dependency check compares against the spec's scope section, invariants, and any explicit dependency mentions.
- **Boundary**: TB-004
- **Violated when**: An unspecced dependency is routed to the supervisor instead of hard-stopping, or a specced dependency triggers hard stop
- **Guards against**: null
- **Test approach**: integration
- **Risk**: high
- **Implemented in**: (filled during GREEN)

### INV-032: Review triage uses supervisor agent (not inline logic)
- **Type**: must
- **Category**: functional
- **Statement**: Review finding triage must be performed by the supervisor agent via `Task(subagent_type="correctless:supervisor")` with a new activation type `review_triage`. The orchestrator must not implement triage logic inline — it passes findings to the supervisor and acts on the response. This maintains the existing agent separation principle (PAT-002) and the supervisor's structured I/O contract.
- **Boundary**: ABS-010, ABS-019
- **Violated when**: Review triage logic is implemented inline in `/cauto` SKILL.md instead of using the supervisor agent, or a new activation type is not added to the supervisor contract
- **Guards against**: AP-013
- **Test approach**: integration
- **Risk**: medium
- **Implemented in**: (filled during GREEN)

### INV-033: Supervisor activation type extensions
- **Type**: must
- **Category**: functional
- **Statement**: The supervisor input contract must be extended with these new `activation_type` values: `review_triage` (batch review findings), `override_issued` (override issuance review), `override_action_review` (per-action during override window), `override_window_closing` (window closure review). When `activation_type` is `review_triage`, the `decision_request` field contains an array of review findings (not a single DR-xxx). Each finding has: finding_id, source_agent, category, summary, proposed_action. The supervisor returns an array of per-finding decisions. The existing activation types (`escalation`, `phase_transition`, `budget_warning`) are unchanged.
- **Boundary**: ABS-019
- **Violated when**: New activation types use the existing `escalation` type (overloaded semantics), or the supervisor receives data in a non-standard format for any activation type
- **Guards against**: null
- **Test approach**: unit
- **Risk**: low
- **Implemented in**: (filled during GREEN)

### INV-034: Configurable supervisor mandate level (with conservative structural enforcement)
- **Type**: must
- **Category**: functional
- **Statement**: `.correctless/preferences.md` must support a `supervisor_mandate` field with three levels: `conservative` (default — approve only decisions explicitly implied by spec), `moderate` (approve decisions consistent with spec intent), `aggressive` (approve any decision that doesn't violate prohibitions). The supervisor receives this level in its `preferences` input field and adjusts its decision threshold accordingly. When the field is absent, the default is `conservative`. **Structural enforcement at conservative level**: When mandate is `conservative`, the orchestrator applies post-response validation on architectural and scope-expansion decisions — the supervisor's reasoning must cite a specific spec section (heading or invariant ID). The orchestrator validates the citation exists. If the citation is missing or invalid, the orchestrator overrides the decision to `hard_stop`. At `moderate` and `aggressive` levels, no additional orchestrator validation is applied (prompt-level only). This provides structural teeth for the most restrictive level while preserving flexibility at higher levels.
- **Boundary**: ABS-008, ABS-019
- **Violated when**: Mandate level is not passed to the supervisor, or the supervisor ignores the mandate level, or an unrecognized level crashes instead of defaulting to conservative, or conservative-level decisions lack citation and are not overridden to hard_stop
- **Guards against**: null
- **Test approach**: unit
- **Risk**: medium
- **Implemented in**: (filled during GREEN)

### Part C: Override Window Scrutiny

### INV-035: Every override issuance triggers supervisor activation
- **Type**: must
- **Category**: functional
- **Statement**: When `workflow-advance.sh override` is invoked, the orchestrator activates the supervisor with `activation_type: override_issued` before the override takes effect. The supervisor receives the override reason, the current phase, the intent_summary, and the last 10 DD-xxx entries. The supervisor returns one of: `approve_override` (override takes effect), `reject_override` (override is not applied, original gate block remains, and the blocked action is escalated to the human as a hard stop — PRH-006 prevents retry, the escalation file includes the gate block, override reason, and supervisor rejection reasoning), or `escalate_to_human` (hard stop, surface decision to human). No override can take effect without supervisor approval.
- **Boundary**: TB-004
- **Violated when**: An override is applied without supervisor review, or the supervisor's reject/escalate response is ignored, or a rejected override does not escalate to human
- **Guards against**: null
- **Test approach**: integration
- **Risk**: critical
- **Implemented in**: (filled during GREEN)

### INV-036: Override window maintains supervisor as sustained reviewer
- **Type**: must
- **Category**: functional
- **Statement**: When an override is active (override.active == true in workflow state), the supervisor activates on every subsequent action that would normally require gate approval: commits to the feature branch, invocations of tools that would be blocked without the override, phase transitions, and skill completions. Each activation receives: the action being taken, the original override reason, the intent_summary, and the accumulated DD-xxx entries since override issuance. The supervisor returns `approve_action`, `reject_action` (action is not taken), or `escalate_to_human` (hard stop).
- **Boundary**: TB-004
- **Violated when**: Actions occur during an active override window without supervisor review, or the supervisor's reject response is ignored
- **Guards against**: null
- **Test approach**: integration
- **Risk**: critical
- **Implemented in**: (filled during GREEN)

### INV-037: Override window closure requires supervisor final review (with pretext check)
- **Type**: must
- **Category**: functional
- **Statement**: When an override window closes (remaining_calls reaches 0, or override is explicitly cleared, or the workflow transitions past the phase where the override was issued), the supervisor activates with `activation_type: override_window_closing`. The supervisor receives: the original override reason, all actions taken during the window, the intent_summary, and all DD-xxx entries created during the window. The supervisor evaluates two things: (a) **cumulative assessment**: whether the window's work is acceptable as a whole, and (b) **pretext check**: whether the accumulated work actually ADDRESSES the stated override reason, not just whether the files are in scope. Work that is in scope but doesn't address the override reason (e.g., override for "build error X" but the window's work never fixes error X) should trigger `reject_window`. The supervisor returns: `approve_window` (all work during the window is accepted, pipeline proceeds normally), `reject_window` (hard stop, the window's work is flagged for human review, no further pipeline progress until human decides), or `partial_accept` (specific actions flagged for review, pipeline proceeds but the Auto Run Report surfaces the flagged items prominently).
- **Boundary**: TB-004
- **Violated when**: An override window closes without a final supervisor review, or the supervisor's disposition is not applied to pipeline state, or the closure review does not check whether work addresses the stated override reason
- **Guards against**: null
- **Test approach**: integration
- **Risk**: critical
- **Implemented in**: (filled during GREEN)

### INV-038: Override-window supervisor activations exempt from 20-activation cap (with soft cap)
- **Type**: must
- **Category**: resource-lifecycle
- **Statement**: Supervisor activations with activation_type in {override_issued, override_action_review, override_window_closing} do not count against the 20-activation cap defined in Phase 2 INV-007. These activations are operationally required for override scrutiny and rate-limiting them would defeat the purpose. A separate counter tracks override-window activations in workflow state. **Soft cap**: when the override-window activation counter reaches 50, the orchestrator triggers `escalate_to_human` with message "Unusually high override-window activity ({N} activations). Human should review whether the override window is being used appropriately." This is not a hard stop — the human can approve continuation — but it prevents unbounded override-window activity from exhausting token budget silently. The Auto Run Report surfaces this counter.
- **Boundary**: TB-004
- **Violated when**: Override-window activations are counted against the main activation cap, or the separate override-activation counter is not tracked, or the 50-activation soft cap does not trigger escalation
- **Guards against**: null
- **Test approach**: unit
- **Risk**: medium
- **Implemented in**: (filled during GREEN)

### INV-039: Override log records full supervisor review lifecycle
- **Type**: must
- **Category**: data-integrity
- **Statement**: The override log (existing override tracking in workflow state) is extended to include supervisor review fields per override entry: `supervisor_issuance_review` (disposition + reasoning + timestamp for the initial review), `supervisor_action_reviews` (array of per-action reviews with disposition + reasoning + timestamp + action_description), `supervisor_closure_review` (disposition + reasoning + timestamp for the window closure review). All fields are append-only; a supervisor review is recorded once and never modified. The log format must be backward-compatible (old entries without supervisor fields parse correctly as legacy entries).
- **Boundary**: ABS-020
- **Violated when**: Override entries are missing supervisor review fields after Phase 3 ships, or supervisor reviews are modified after recording
- **Guards against**: null
- **Test approach**: integration
- **Risk**: high
- **Implemented in**: (filled during GREEN)

### INV-040: Supervisor cross-checks "pre-existing" override justifications against base commit
- **Type**: must
- **Category**: functional
- **Statement**: When the override reason contains phrases indicating "pre-existing" error or "not caused by this cycle" (controlled vocabulary: "pre-existing", "not caused by", "already present", "existed before", "upstream issue"), the supervisor's issuance review must include a cross-check. The orchestrator performs the cross-check mechanically: (1) obtain the base commit via `git merge-base main HEAD`, (2) create a temporary worktree at the base commit via `git worktree add`, (3) run the project's test/build command (`commands.test` from workflow-config.json) with a timeout configurable via `commands.test_timeout` in workflow-config.json (default: 120 seconds — sufficient for most projects; large Go/Rust codebases with cold dependency resolution may need longer), (4) capture the exit code and stderr, (5) clean up the worktree. If the error is not present on the base commit (build succeeds or fails with a different error), the "pre-existing" claim is false. The supervisor receives the cross-check evidence and treats a false "pre-existing" claim as grounds for `reject_override` or `escalate_to_human`. Detectable failure modes for "cannot be performed": (a) `git merge-base` exits non-zero, (b) `git worktree add` fails, (c) `commands.test` is null or empty in config, (d) build exceeds 120s timeout, (e) worktree checkout fails (disk/permissions). All failure modes → fail-closed per BND-007.
- **Boundary**: TB-004
- **Violated when**: A "pre-existing" justification is accepted without base-commit verification, or any detectable failure mode is silently ignored
- **Guards against**: Andrew's case — agent claimed error was pre-existing when it was caused by the cycle's own stubbing
- **Test approach**: integration
- **Risk**: critical
- **Implemented in**: (filled during GREEN)

### INV-041: Mechanical file-touch scope drift detection during override window
- **Type**: must
- **Category**: functional
- **Statement**: During each override-window action review (INV-036), the orchestrator mechanically identifies which files the action touches (via `git diff --name-only` for commits, or the tool's target path for file operations). Files outside the project directory (paths not under the repo root) and common transient patterns (`/tmp/*`, `*.tmp`, `*.log`) are excluded — only project-directory files are checked. The orchestrator compares touched project files against three sets: (a) files mentioned in the override reason, (b) the spec's affected components (file paths from "In scope", "Files touched", or "Implemented in" sections), (c) files referenced in the intent_summary. If any touched file is not in sets (a), (b), or (c), this constitutes potential scope drift. The mechanical file-touch check is the primary signal — the orchestrator flags drift to the supervisor, which can apply secondary judgment about semantic relatedness. Scope drift triggers `escalate_to_human`, not `reject_action` — the agent may have a valid reason, and the human should decide.
- **Boundary**: TB-004
- **Violated when**: Actions touching project files outside the override's claimed scope proceed without supervisor flagging, or the file-touch check is skipped in favor of pure judgment, or transient artifacts outside the repo root trigger false-positive drift flags
- **Guards against**: Andrew's case — override was for specific build error, agent used the window to write unrelated stub code
- **Test approach**: integration
- **Risk**: high
- **Implemented in**: (filled during GREEN)

### INV-042: Override window closure review verifies spec completeness (concrete detection)
- **Type**: must
- **Category**: functional
- **Statement**: The closure review (INV-037) includes a spec-completeness check. The orchestrator parses the approved spec for declared deliverables using this concrete detection: scan for markdown ATX headings (`#` through `######`) matching `What lands`, `In scope`, or `Deliverables` (case-insensitive). Within those sections (from the heading to the next heading of equal or higher level), extract file paths from bulleted list items (lines starting with `- ` or `* `) by matching the regex `[a-zA-Z0-9_./-]+\.(go|py|ts|js|md|sh|json|yaml|toml|rs)` or the literal `Dockerfile`. Exclude content inside fenced code blocks (between ` ``` ` markers). Markdown links are handled by extracting the link text, not the URL (e.g., from `[src/auth.go](url)`, extract `src/auth.go`). The extracted paths are the declared deliverables. The supervisor receives these paths and the list of files actually created or modified during the override window. If the spec declared deliverables that are missing from the accumulated work, the supervisor returns `reject_window` with reasoning listing the missing deliverables. If the spec has no recognized deliverable sections or no file paths are extracted, this check is skipped — the spec relies on normal invariant coverage instead.
- **Boundary**: TB-004
- **Violated when**: Override window closes with missing declared deliverables and the supervisor approves, or the parser fails to extract paths from a spec that uses the recognized section headings
- **Guards against**: Andrew's case — spec declared multiple deliverables; window closed with only partial work
- **Test approach**: integration
- **Risk**: critical
- **Implemented in**: (filled during GREEN)

## Prohibitions

### PRH-001: Never bypass spec approval gate
- **Statement**: The spec approval gate is non-negotiable in Phase 3. No combination of preferences, supervisor confidence, or pipeline state may skip the human spec approval. This prohibition is relaxed only in Factory mode (separate spec, separate product).
- **Detection**: Structural grep of SKILL.md for the approval gate; integration test that verifies pipeline halts for approval
- **Consequence**: Implementation proceeds on a spec the human never approved — all downstream work may be wrong

### PRH-002: Supervisor must not approve unspecced dependencies
- **Statement**: The supervisor must never approve a new dependency that is not mentioned in the approved spec. The orchestrator enforces this by checking the spec before routing to the supervisor — unspecced dependencies go directly to Tier 4 (hard stop), never reaching the supervisor.
- **Detection**: Integration test: construct a dependency escalation for an unspecced dep, verify it hard-stops without supervisor activation
- **Consequence**: Supply chain expanded without human knowledge

### PRH-003: Source agent category is authoritative for disposition constraints (structural enforcement)
- **Statement**: When triaging review findings, the supervisor's disposition is constrained by the finding's source agent category. Red Team agent findings can only receive `accept` or `hard_stop` — never `reject`. Findings containing security keywords (per Phase 2 PRH-001 keyword list) are subject to the same constraint regardless of source agent. The supervisor may not re-categorize a security finding as non-security to bypass this prohibition. The source agent's categorization is authoritative for disposition constraints, not the supervisor's re-assessment. **Structural enforcement**: After receiving the supervisor's triage response, the orchestrator applies a post-response validation pass. For any finding where `source_agent == "red-team"` or `category` contains security keywords, if the supervisor returned `reject`, the orchestrator overrides to `hard_stop` and logs a PRH-003 violation in the review decisions artifact. This makes enforcement mechanical (testable in bash) rather than relying on supervisor discipline.
- **Detection**: Unit test: construct a supervisor response that rejects a Red Team finding, verify orchestrator overrides to `hard_stop`; unit test: construct a response that rejects a security-keyword finding, verify override
- **Consequence**: Security gaps identified by review agents silently dropped via re-categorization

### PRH-004: No inline review triage logic
- **Statement**: Review finding triage must always go through the supervisor agent — the orchestrator must not implement accept/reject logic directly. This is a structural prohibition per ABS-010 and AP-013.
- **Detection**: Structural grep of `/cauto` SKILL.md for inline triage patterns (decision logic that doesn't invoke the supervisor)
- **Consequence**: Triage decisions made without supervisor's structured reasoning and audit trail

### PRH-005: Supervisor review responses cannot be auto-answered
- **Statement**: When the supervisor's review response requires structured input (approve/reject/escalate dispositions), the response must come from the supervisor agent's actual output — not from fallback logic, not from default values, not from pattern matching that auto-fills. If the supervisor agent returns a malformed response (BND-004 class), the orchestrator treats it as `escalate_to_human`, not as any default disposition. This prevents a failure mode where supervisor activation is technically executed but the response is machine-generated boilerplate.
- **Detection**: Static check — grep orchestrator code for hardcoded dispositions in supervisor response parsing; runtime check — supervisor response validation rejects responses that match known boilerplate patterns
- **Consequence**: Supervisor review becomes ceremonial, defeats the hostile-review purpose

### PRH-006: Override cannot be re-issued within same run after supervisor rejection (Jaccard similarity)
- **Statement**: If the supervisor rejects an override issuance (INV-035) or rejects an override window at closure (INV-037), the same run cannot re-issue an override for the same phase or the same stated reason. This prevents an agent from retrying with reworded justifications until one is accepted. **Similarity algorithm**: Tokenize both the new override reason and each rejected reason into lowercase words, remove English stop words (the, a, an, is, are, was, were, be, been, for, of, to, in, on, at, by, with, from, and, or, but, not, this, that). Compute Jaccard similarity (|intersection| / |union|). If similarity >= 0.4 against any rejected reason, the new override is auto-rejected without supervisor activation. The rejected-overrides list is maintained in workflow state for the duration of the run.
- **Detection**: Orchestrator maintains rejected-overrides list in workflow state; new override attempts check Jaccard similarity against all entries before activation; unit test: verify similarity >= 0.4 catches synonym rewording, similarity < 0.4 allows legitimately distinct overrides
- **Consequence**: Retry attacks on supervisor judgment

## Boundary Conditions

### BND-001: Review produces zero findings
- **Boundary**: TB-004
- **Input from**: Review agents
- **Validation required**: Handle gracefully — skip triage, proceed directly to spec approval gate with original spec unchanged
- **Failure mode**: Fail-safe (proceed without triage)

### BND-002: Supervisor unavailable during review triage
- **Boundary**: ABS-019
- **Input from**: Task() invocation
- **Validation required**: If supervisor invocation fails (Task returns error), fall back to presenting all findings to the human during spec approval gate — treat as "all findings hard-stopped"
- **Failure mode**: Fail-closed (human reviews all findings)

### BND-003: Provided spec file does not exist or is empty
- **Boundary**: INV-020
- **Input from**: Human-provided file path
- **Validation required**: Check file exists and is non-empty before proceeding. If invalid, error message with the path and abort.
- **Failure mode**: Fail-closed (abort with error)

### BND-004: Supervisor returns mixed decisions (some accept, some reject, some hard_stop)
- **Boundary**: ABS-019
- **Input from**: Supervisor review triage response
- **Validation required**: Process each finding independently. Accept findings → incorporate into spec. Reject findings → log to review decisions artifact. Hard_stop findings → escalate to human during spec approval. If the response is not valid JSON or missing required fields, treat all findings as hard-stopped.
- **Failure mode**: Fail-closed (malformed response → all findings to human)

### BND-005: `/cauto` invoked on main branch with no workflow
- **Boundary**: INV-019
- **Input from**: User invocation
- **Validation required**: Refuse invocation on main/master branch — require feature branch. Error message: "Create a feature branch first."
- **Failure mode**: Fail-closed (refuse)

### BND-006: Supervisor activation fails during override review
- **Boundary**: TB-004
- **Input from**: Orchestrator invoking supervisor for override review
- **Validation required**: If the Task invocation for supervisor activation fails (timeout, agent unavailable, malformed response), the orchestrator treats this as `escalate_to_human` for override_issued and override_window_closing activations, and as `reject_action` for override_action_review activations (the action is not taken, original gate state resumes). The workflow does not proceed past a failed supervisor activation during an override window — fail-closed because the override window exists only under supervisor oversight.
- **Failure mode**: Fail-closed (escalate to human on issuance/closure; block action on per-action review)

### BND-007: Base-commit cross-check cannot be performed
- **Boundary**: TB-004
- **Input from**: Orchestrator attempting base-commit verification for INV-040
- **Validation required**: Detectable failure modes: (a) `git merge-base main HEAD` exits non-zero (base commit unreachable), (b) `git worktree add` fails (worktree creation error), (c) `commands.test` is null or empty in workflow-config.json (no build command configured), (d) build/test command exceeds the configured timeout (`commands.test_timeout`, default 120s), (e) worktree checkout fails (disk space, permissions). For all failure modes, the supervisor treats the override justification as unverified and returns `escalate_to_human`. The supervisor does not grant the benefit of the doubt — unverified "pre-existing" claims route to human review. **Timeout-claim-meets-timeout context**: When the override reason specifically claims a timeout/slow-build issue (contains keywords "timeout", "slow", "timed out", "exceeds time") and the cross-check itself times out (failure mode (d)), the orchestrator includes this observation in the escalation context: "Cross-check timed out at {N}s — consistent with the claimed timeout issue. Human should verify." This is not auto-acceptance — it's richer escalation context for the human's decision.
- **Failure mode**: Fail-closed (escalate, never accept unverified "pre-existing" claims; richer context when timeout matches claim)

### BND-008: Intent_summary tampered during override review
- **Boundary**: TB-004
- **Input from**: Supervisor activation during override review, intent hash check per Phase 2 INV-013
- **Validation required**: If the intent hash check fails during any supervisor activation in an override window, the hard stop from Phase 2 INV-013 takes precedence over override scrutiny. The override window ends immediately with a hard stop for "intent summary tampered during override window," which is a more severe signal than the override itself.
- **Failure mode**: Fail-closed (intent tampering during override is treated as compound security event)

## Environment Assumptions

- **EA-001**: Supervisor agent (`agents/supervisor.md`) is available and loadable via `Task(subagent_type="correctless:supervisor")` — refs ABS-010
- **EA-002**: Review skills (`/creview`, `/creview-spec`) produce structured findings that can be passed to the supervisor — existing skill output contract must be compatible
- **EA-003**: Base-commit checkout and build execution are possible in the project environment (for INV-040 cross-check). Requires `git worktree` support and `commands.test` configured in workflow-config.json. When not possible, the check degrades gracefully per BND-007.

## Open Questions

- **OQ-001**: Can the supervisor itself be tricked by plausible override-window action descriptions? The action review requires the supervisor to judge whether an action is related to the override reason. Mitigations: (1) the supervisor sees the actual diff/command, not just the agent's description; (2) the mechanical file-touch check (INV-041) is the primary per-action signal; (3) the intent_summary provides ground truth; (4) the spec-completeness check (INV-042) is the structural backstop at closure — if declared deliverables are missing, `reject_window` fires regardless of whether individual actions seemed justified. The combination of file-touch per action + deliverable check at closure catches the case where drift is distributed across many small individually-justified actions. Residual risk: the supervisor's secondary judgment about semantic relatedness is bias-shared with the orchestrator agent, and specs without declared deliverables lack the INV-042 backstop. Accept residual risk for specs without deliverables.

- **OQ-002**: What about nested overrides or override re-issuance across phases? Design intent: each override is its own window with its own supervisor lifecycle. The rejected-overrides list (PRH-006) prevents re-issuance of rejected overrides, but accepted overrides can recur in subsequent phases. Verify during GREEN that workflow state correctly handles sequential windows without state confusion.
