# Spec: QA Severity Calibration

## Metadata
- **Created**: 2026-05-05T19:00:00Z
- **Status**: draft
- **Impacts**: none
- **Branch**: feature/qa-severity-calibration
- **Research**: null
- **Recommended-intensity**: high
- **Intensity**: high
- **Intensity reason**: file path signal (skills/ctdd/SKILL.md), keyword signal (security), antipattern history (AP-022 dead-code-in-security-paths shape)
- **Override**: none

## Context

The QA agent and mini-audit agents in `/ctdd` define severity levels (BLOCKING/NON-BLOCKING for QA; CRITICAL/HIGH/MEDIUM/LOW for mini-audit) but provide no calibration examples or boundary definitions. Across 5 features on an external project, agents rated all 15 findings as NON-BLOCKING or MEDIUM/LOW — including silent data corruption bugs that should be BLOCKING/CRITICAL. The fix-round loop has never triggered. Real bugs ship unfixed because the severity gate has an undefined decision boundary. Discovered via `/cwtf` + `/cmetrics` on Overcorrect. GitHub issue #93.

## Scope

**In scope:**
- Add severity calibration examples to QA agent prompt in `/ctdd` SKILL.md
- Add severity calibration examples to mini-audit agent prompts in `/ctdd` SKILL.md
- Add orchestrator severity floor check (keyword-based secondary tripwire) after QA and mini-audit finding collection
- Add non-blocking finding disposition flow (present to user, require explicit accept/fix/upgrade)
- Extend qa-findings JSON `status` field from `"open|fixed"` to `"open|fixed|accepted"`
- Add `fix_rounds_triggered` field to intensity-calibration.json schema + `/cmetrics` warning when 0 across 3+ high+ features
- Add `/cmetrics` as consumer of ABS-005 in `.correctless/ARCHITECTURE.md`
- Add AP-028 antipattern entry for "uncalibrated severity gate"
- Add PMB-007 learning entry to CLAUDE.md
- Sync all modified skills to distribution via `sync.sh`

**Out of scope:**
- Changing the severity taxonomy itself (BLOCKING/NON-BLOCKING stays for QA, CRITICAL/HIGH/MEDIUM/LOW stays for mini-audit)
- Modifying `/caudit` severity calibration (separate skill, separate prompts)
- Automated severity re-rating (agents rate, orchestrator tripwires, human decides)
- Changes to the fix-round loop mechanics (the loop is correct, it just never fires)

## Complexity Budget
- **Estimated LOC**: ~160 (prompt additions + orchestrator logic in SKILL.md + calibration schema + metrics warning)
- **Files touched**: ~9 (skills/ctdd/SKILL.md, correctless/skills/ctdd/SKILL.md, skills/cverify/SKILL.md, correctless/skills/cverify/SKILL.md, skills/cmetrics/SKILL.md, correctless/skills/cmetrics/SKILL.md, .correctless/antipatterns.md, CLAUDE.md, tests/)
- **New abstractions**: 0
- **Trust boundaries touched**: 0
- **Risk surface delta**: low

## Invariants

### INV-001: QA prompt contains severity calibration examples [unit]
- **Type**: must
- **Category**: functional
- **Statement**: The QA agent prompt in `skills/ctdd/SKILL.md` must contain concrete calibration examples for BLOCKING severity that include at minimum: silent data corruption, security bypass, resource leak, mock gap hiding wiring failure, and test-routing (AP-016). It must also contain calibration examples for NON-BLOCKING: missing docs, suboptimal error messages, style inconsistency.
- **Violated when**: The QA prompt's severity section contains only abstract definitions ("issues that must be fixed") without concrete examples
- **Test approach**: unit — grep for calibration keywords in the QA prompt section

### INV-002: QA prompt includes aggressive default directive [unit]
- **Type**: must
- **Category**: functional
- **Statement**: The QA agent prompt must include the directive: "When in doubt, rate BLOCKING." with rationale that a disputed BLOCKING costs one conversation turn while a shipped bug costs a postmortem. This directive must be visually prominent — set apart from surrounding text (e.g., blockquote, bold, or its own paragraph), not buried in a paragraph where it can be lost under context pressure. This is the highest-leverage line in the spec: it inverts the agent's default from "NON-BLOCKING is the path of least resistance" to "BLOCKING is the path of least resistance."
- **Violated when**: The QA prompt does not contain an explicit aggressive-default directive, or the directive is embedded in a paragraph rather than visually separated
- **Test approach**: unit — grep for the directive text

### INV-003: Mini-audit prompts contain severity calibration examples [unit]
- **Type**: must
- **Category**: functional
- **Statement**: The mini-audit agent prompts in `skills/ctdd/SKILL.md` must contain concrete calibration examples for CRITICAL/HIGH severity that include at minimum: silent data corruption, security bypass, resource leak, trust boundary violation, and data loss. They must also contain calibration for MEDIUM/LOW: missing docs, suboptimal naming, minor performance inefficiency.
- **Violated when**: The mini-audit severity section references CRITICAL/HIGH/MEDIUM/LOW without concrete boundary examples
- **Test approach**: unit — grep for calibration keywords in the mini-audit section

### INV-004: Mini-audit prompts include aggressive default directive [unit]
- **Type**: must
- **Category**: functional
- **Statement**: The mini-audit agent prompts must include the directive: "When in doubt, rate HIGH." with the same cost-asymmetry rationale and visual prominence requirement as INV-002.
- **Violated when**: The mini-audit prompts lack an explicit aggressive-default directive, or the directive is not visually prominent
- **Test approach**: unit — grep for the directive text

### INV-005: Orchestrator severity floor check after QA [unit]
- **Type**: must
- **Category**: functional
- **Statement**: After persisting QA findings, the orchestrator instructions must include a severity floor check. The check uses the **canonical severity floor keyword list** (defined once in the QA section, referenced by name in the mini-audit section — never duplicated): `corrupt, silent, bypass, leak, security, data loss, zero value, uninitialized`. Matching is **case-insensitive**. If ALL findings are NON-BLOCKING but any finding description contains a keyword from this list, warn the user and present re-rating options (upgrade to BLOCKING / confirm NON-BLOCKING / dispute). **This is a secondary safety net, not the primary fix.** The calibration examples (INV-001 through INV-004) do 90% of the work by shaping the agent's initial rating. This tripwire catches agents that describe the bug correctly but rate it wrong — it does NOT catch agents that describe the bug softly ("the default value is used when the field is empty" instead of "uninitialized field leads to zero-value bypass"). The keyword list will have false negatives on day one.
- **Violated when**: The orchestrator section between "persist findings" and "decide next step" lacks a severity floor check
- **Test approach**: unit — grep for severity floor check instructions; placement ordering (after persist, before decide) verified by code review, not grep
- **Guards against**: AP-028

### INV-006: Orchestrator severity floor check after mini-audit [unit]
- **Type**: must
- **Category**: functional
- **Statement**: After collecting mini-audit findings, the orchestrator instructions must include a severity floor check referencing the **same canonical keyword list defined in INV-005** (by name, not by re-listing the keywords). If ALL findings are MEDIUM/LOW but descriptions match any keyword from the canonical list (case-insensitive), warn the user and present re-rating options (upgrade to CRITICAL/HIGH / confirm current rating / dispute). Same secondary-safety-net framing as INV-005 — calibration examples are the primary fix.
- **Violated when**: The mini-audit orchestrator section lacks a severity floor check before advancing to done, or defines its own keyword list instead of referencing the canonical list
- **Test approach**: unit — grep for severity floor check in the mini-audit section; verify it references the QA-defined list rather than duplicating it

### INV-007: Severity floor check is documented as brittle [unit]
- **Type**: must
- **Category**: functional
- **Statement**: The severity floor check instructions must include an explicit limitation note covering both failure modes: (1) **false negatives** — agents that avoid the trigger words will evade it, and agents that describe bugs softly ("the default value is used" instead of "silent data corruption") will not trigger it; (2) **false positives** — keywords like "leak" and "security" can appear in positive contexts ("leak mitigation is working", "security configuration is properly validated") and trigger the check incorrectly. The calibration examples (INV-001 through INV-004) are the primary fix; this check is a cheap safety net only. If the floor check fires frequently on false positives, users will learn to always click "confirm" and the check becomes meaningless — this is an accepted risk of the keyword approach.
- **Violated when**: The floor check is presented as reliable without caveats about both evasion and false positives
- **Test approach**: unit — grep for limitation/caveat text near the floor check

### INV-008: Non-blocking finding disposition flow [unit]
- **Type**: must
- **Category**: functional
- **Statement**: After all BLOCKING findings are resolved (or if none exist), the orchestrator must present each NON-BLOCKING finding to the user with disposition options: (1) Fix now, (2) Accept — known issue, (3) Upgrade to BLOCKING. No finding may remain with `status: open` when advancing past QA. This is the accountability mechanism: the user cannot claim ignorance of a NON-BLOCKING issue that later becomes a production bug, because every finding received an explicit human disposition. The finding's status in the JSON artifact must reflect the disposition: `fixed`, `accepted`, or upgraded to BLOCKING and re-entered into the fix loop. The qa-findings JSON schema's `status` field must be extended from `"open|fixed"` to `"open|fixed|accepted"`. The `accepted` value is additive — consumers should treat unknown status values as `open` for backward compatibility with existing artifacts.
- **Violated when**: The orchestrator advances past QA with NON-BLOCKING findings at `status: open` without presenting them to the user
- **Test approach**: unit — grep for disposition flow in the post-QA section; grep for `accepted` in the status enum documentation

### INV-009: Non-blocking mini-audit finding disposition flow [unit]
- **Type**: must
- **Category**: functional
- **Statement**: After all CRITICAL/HIGH mini-audit findings are resolved, the orchestrator must present MEDIUM/LOW findings to the user with disposition options: (1) Fix now, (2) Accept, (3) Upgrade to HIGH. No finding may remain with `status: open` when advancing past mini-audit. Same accountability mechanism and `accepted` status extension as INV-008: explicit human disposition on every finding.
- **Violated when**: The orchestrator advances to done with MEDIUM/LOW findings at `status: open` without presenting them
- **Test approach**: unit — grep for disposition flow in the post-mini-audit section

### INV-010: AP-028 antipattern entry exists [unit]
- **Type**: must
- **Category**: functional
- **Statement**: `.correctless/antipatterns.md` must contain an AP-028 entry titled "Uncalibrated severity gate" documenting the bug class: a severity gate that defines levels without calibration examples, causing agents to default to the least-friction rating, making the gate dead code.
- **Violated when**: AP-028 is missing from antipatterns.md or lacks the required fields (What went wrong, How to catch it, Frequency)
- **Test approach**: unit — grep for AP-028 in antipatterns.md

### INV-011: PMB-007 learning entry exists [unit]
- **Type**: must
- **Category**: functional
- **Statement**: CLAUDE.md must contain a PMB-007 postmortem learning entry documenting the uncalibrated severity gate failure, root cause, and class fix.
- **Violated when**: PMB-007 is missing from CLAUDE.md's Correctless Learnings section
- **Test approach**: unit — grep for PMB-007 in CLAUDE.md

### INV-012: Calibration examples match across source and distribution [unit]
- **Type**: must
- **Category**: functional
- **Statement**: All modified skill files (ctdd, cverify, cmetrics) must match their distribution counterparts after sync. `sync.sh` covers all skills globally — this invariant is satisfied by running sync and verifying with `sync.sh --check`. The existing sync drift test already covers this.
- **Violated when**: Source and distribution copies diverge for any modified skill
- **Test approach**: unit — `sync.sh --check` (existing infrastructure)

### INV-013: Fix-round loop activation tracking [unit]
- **Type**: must
- **Category**: functional
- **Statement**: The intensity-calibration.json schema must include a `fix_rounds_triggered` field (integer, default 0) written by `/cverify` alongside existing calibration fields. **Derivation formula**: `fix_rounds_triggered = max(0, qa_rounds - 1) + mini_audit_fix_rounds`, where `qa_rounds` is read from the workflow state (QA round 1 is the initial QA; rounds 2+ are fix rounds) and `mini_audit_fix_rounds` is the count of fix-loop re-entries during the mini-audit phase (derived from workflow state or qa-findings JSON round entries with `MA-` prefix that triggered fix loops). `/cverify` already reads the workflow state and qa-findings for other calibration fields — it derives this value from the same sources. `/cmetrics` must check: if `fix_rounds_triggered` is 0 across 3 or more consecutive features at high+ intensity, emit a warning: "Fix-round loop has not fired in {N} consecutive high+ features — severity calibration may be insufficient." `/cmetrics` must be documented as a consumer of ABS-005 (intensity-calibration.json) in `.correctless/ARCHITECTURE.md`. This is the regression test for this entire spec: the point is to make the fix-round loop stop being dead code.
- **Violated when**: intensity-calibration.json has no `fix_rounds_triggered` field, or `/cmetrics` does not warn when the field is 0 across 3+ high+ features, or `/cmetrics` is not listed as an ABS-005 consumer
- **Test approach**: unit — verify calibration schema includes the field; verify /cmetrics warning logic; verify ABS-005 consumer list

## Prohibitions

### PRH-001: No severity taxonomy changes
- **Statement**: The severity levels themselves (BLOCKING/NON-BLOCKING for QA, CRITICAL/HIGH/MEDIUM/LOW/UNCERTAIN for mini-audit) must not be changed. This spec adds calibration to the existing taxonomy, not a new one.
- **Detection**: grep for severity enum changes in the diff
- **Consequence**: Changing the taxonomy would break all existing QA findings artifacts and any consuming tools

### PRH-002: No automated severity override
- **Statement**: The orchestrator must never automatically upgrade a finding's severity. The severity floor check warns and presents options — the human decides. The "when in doubt, rate BLOCKING/HIGH" directive applies to the QA/mini-audit agents' initial rating, not to the orchestrator post-hoc.
- **Detection**: grep for automatic severity mutation in orchestrator instructions
- **Consequence**: Automated override would undermine agent accountability and create false attribution in findings artifacts

## Boundary Conditions

### BND-001: All findings are NON-BLOCKING with no keyword matches
- **Boundary**: Severity floor check
- **Input from**: QA agent findings
- **Validation required**: When all findings are NON-BLOCKING AND no descriptions contain floor-check keywords, the floor check passes silently — no warning, no user interaction
- **Failure mode**: Fail-open (no floor check warning = advance normally)

### BND-002: Zero findings from QA
- **Boundary**: Non-blocking disposition flow
- **Input from**: QA agent findings
- **Validation required**: When QA returns zero findings, skip the disposition flow entirely — there's nothing to present
- **Failure mode**: N/A (no findings = nothing to do)

### BND-003: Mixed BLOCKING and NON-BLOCKING findings
- **Boundary**: Disposition flow ordering
- **Input from**: QA agent findings
- **Validation required**: BLOCKING findings are presented and resolved first (fix rounds). Only after all BLOCKING findings are resolved does the NON-BLOCKING disposition flow run.
- **Failure mode**: N/A (sequential processing)

### BND-004: `/cauto` semi-auto mode disposition
- **Boundary**: Autonomous pipeline interaction with disposition flow
- **Input from**: `/cauto` orchestrator invoking `/ctdd`
- **Validation required**: In `/cauto` context, NON-BLOCKING and MEDIUM/LOW findings are auto-accepted with disposition `auto-accepted-pipeline` and status `accepted` in the findings JSON. This is not a severity override (PRH-002 is not violated) — it is an acceptance disposition made by the autonomous orchestrator, consistent with the pipeline's existing behavior of escalating only BLOCKING/CRITICAL/HIGH findings to the human. The auto-acceptance is logged in the findings artifact so `/cmetrics` and `/cpostmortem` can distinguish human-accepted from pipeline-accepted findings.
- **Failure mode**: Without this, the first `/cauto` run after this feature would stall waiting for human input on low-severity findings, defeating the purpose of semi-auto mode.

## Open Questions

- **OQ-001**: ~~Should the severity floor check keywords be configurable via workflow-config.json?~~ **Resolved: hardcode.** The keyword list is a cheap tripwire that fires rarely. Making it configurable invites users to weaken it ("I keep getting false positives on 'leak' so I removed it"). If keyword drift becomes a real problem, it'll show up in the PMB registry and warrant its own spec.

- **OQ-002**: ~~Should `/caudit` get the same calibration treatment?~~ **Resolved: defer, but filed.** See Deferred Items below.

## Deferred Items

- **DEF-001: `/caudit` severity calibration** — Same bug class (AP-028), same fix shape (calibration examples + aggressive default directive + disposition flow). The `/caudit` skill has its own severity system (Olympics tiers with bounties) in a separate prompt. Apply the same pattern: calibration examples for tier boundaries, aggressive-default directive, disposition flow for non-blocking findings. File as a follow-up spec after this one lands and the `/ctdd` calibration is validated across 2-3 features.

- **DEF-002: Escalation to structural approach if prompt calibration fails** — This spec is an experiment in whether prompt-level interventions can fix a behavioral problem (agent severity under-rating). If `fix_rounds_triggered` remains 0 after 5 features at high+ intensity (measured via INV-013's `/cmetrics` warning), the experiment has failed and a structural approach is needed — e.g., severity classification moved from inline agent prose to a separate classification step with structured output parsing, or a mandatory second-opinion agent that independently rates severity. The INV-013 warning is the trigger; this deferred item is the response plan.
