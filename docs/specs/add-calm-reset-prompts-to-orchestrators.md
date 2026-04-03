# Spec: Add Calm Reset Prompts to Orchestrators

## What

Add conditional reset prompts to `/ctdd` and `/caudit` orchestrators that fire at known desperation trigger points — after repeated implementation failures, after QA fix rounds with recurring BLOCKING findings, and after audit rounds with higher-than-expected finding counts. Each reset redirects the subagent to re-read source material (spec, test, finding) and offers the human as an escape hatch. The goal is preventing output degradation (test weakening, hacky implementations, thrashing) by interrupting the desperation buildup before it produces bad code.

## Rules

- **R-001** [integration]: The `/ctdd` SKILL.md GREEN phase instructions include a conditional reset prompt that the orchestrator appends to the implementation agent's prompt when the implementation attempt count reaches 3 or more consecutive failures within the GREEN phase. The reset prompt must: (a) instruct the agent to stop building on previous failed approaches, (b) instruct the agent to re-read the spec rule and failing test output fresh, (c) ask "what is the test ACTUALLY checking" to redirect from assumption to observation, (d) state there is no time pressure. The attempt count is tracked by the orchestrator (not a new state file).

- **R-011** [integration]: The `/ctdd` SKILL.md fix-round instructions include a conditional reset prompt that the orchestrator appends to the fix agent's prompt when the fix attempt count reaches 3 or more consecutive failures within a fix phase. The reset prompt must: (a) instruct the agent to stop building on previous failed approaches, (b) instruct the agent to re-read the specific QA finding's `instance_fix` and `class_fix` fields from the findings JSON, (c) ask "what is the finding ACTUALLY describing" to redirect from assumption to observation, (d) state there is no time pressure. This is distinct from R-001 (GREEN) and R-002 (recurring BLOCKINGs across rounds) — R-011 fires on consecutive failures within a single fix round, while R-002 fires on recurring findings across QA rounds.

- **R-002** [integration]: The `/ctdd` SKILL.md QA fix round instructions include a conditional reset prompt that the orchestrator appends to the fix agent's prompt when a QA round returns 2+ BLOCKING findings after a previous fix round already addressed BLOCKING findings (i.e., recurring BLOCKINGs — the fix didn't stick). The reset prompt must: (a) reframe QA findings as descriptions of desired behavior not criticism, (b) instruct the agent to re-read each finding's `instance_fix` and `class_fix` fields from the findings JSON before attempting fixes, (c) instruct the agent not to re-attempt the same approach that failed in the previous round.

- **R-003** [integration]: The `/caudit` SKILL.md (Full-only) convergence loop instructions include a conditional reset prompt that the orchestrator appends to fix-round agent prompts when a round produces more findings than the previous round (diverging instead of converging). The reset prompt must: (a) note that divergence means the fixes are introducing new issues, (b) instruct the agent to re-read the original findings before the fix attempt, (c) instruct the agent to make smaller, more isolated changes.

- **R-004** [unit]: Every reset prompt across all trigger points must include an explicit human escalation option: "If you're still stuck after this attempt, stop and ask the human for guidance rather than trying another approach." This gives the agent permission to escalate instead of spiraling.

- **R-005** [unit]: Every reset prompt must include a concrete re-read action — a specific file or artifact to re-read (the spec rule, the test file, the finding JSON, the error output). No reset prompt consists solely of emotional framing without a redirect to source material. "There's no rush" alone is not a valid reset prompt; "There's no rush — re-read the failing test and describe what the assertion literally checks" is valid.

- **R-006** [unit]: Reset prompts must not contain language that gives the agent permission to simplify, weaken, or skip. Specifically: must not contain "simpler approach", "good enough", "skip", "workaround", "partial", or "approximate" in the reset text. The reset redirects to correctness, not to shortcuts.

- **R-007** [integration]: The trigger for R-001 (GREEN phase) fires on 3+ consecutive failures. The trigger for R-011 (fix round) fires on 3+ consecutive failures within a single fix phase. The trigger for R-002 (QA fix round) fires when the current QA round has 2+ BLOCKING findings AND the previous round also had BLOCKING findings that were marked fixed. The trigger for R-003 (audit convergence) fires when `findings_count[round_N] > findings_count[round_N-1]`. These thresholds are stated in the SKILL.md instruction text — not configurable at runtime.

- **R-008** [unit]: After a reset prompt fires and the subsequent attempt also fails, the orchestrator must escalate to the human with a summary of what was tried and what failed, rather than injecting another reset prompt. Reset prompts fire at most once per trigger point per phase — no stacking. The escalation message must include: (a) how many attempts were made, (b) a summary of the approaches tried, (c) the current error or failing test, (d) an explicit ask for the human's guidance. This escalation is in addition to the existing `/cdebug` suggestion in `/ctdd`. The reset escalation fires based on attempt count; the `/cdebug` suggestion fires based on finding complexity. Both may apply — present the `/cdebug` option within the R-008 escalation message when the failure involves unclear root cause.

- **R-009** [integration]: The reset prompts are additions to the existing subagent prompt text in `/ctdd` and `/caudit` SKILL.md files. They do not create new files, new state fields, new agents, or new checkpoint entries. The orchestrator tracks attempt counts in its own working memory (conversation context), not in persisted state.

- **R-010** [integration]: Both `/ctdd` (Lite and Full) and `/caudit` (Full-only) SKILL.md files are modified. The changes propagate to both distributions via `sync.sh`. No other skill files are modified.

## Won't Do

- Configurable thresholds — hardcoded in SKILL.md instructions for simplicity
- New state files or checkpoint fields — attempt tracking lives in orchestrator context
- Separate "therapist" agent or subagent — resets are injected text, not a new actor
- Reset prompts in RED phase — test writing failures are usually spec ambiguity, not desperation
- Reset prompts in QA phase — QA is read-only, desperation doesn't apply
- Prompt testing (verifying the reset text actually changes model behavior) — out of scope, would require LLM-in-the-loop evaluation

## Risks

- **Reset text gives implicit permission to give up** — Mitigation: R-006 prohibits shortcut language; R-005 requires concrete re-read actions
- **False positive triggers** — 3 failures could be productive narrowing, not desperation — Mitigation: R-008 caps resets at one per trigger point; human escalation is the fallback
- **Increased time on features that are genuinely hard** — accepted; the alternative (desperate hacks that pass QA on attempt 4) costs more time in the long run

## Open Questions

_(none)_
