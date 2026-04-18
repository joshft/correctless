# Spec: TDD Mini-Audit Phase

## Metadata
- **Task**: tdd-mini-audit
- **Recommended-intensity**: high
- **Intensity**: high
- **Intensity reason**: file path signal (skills/, hooks/); keyword signal (trust boundary in agent-to-agent handoff); project floor is high
- **Override**: none
- **Review findings**: 16 findings (2 CRITICAL, 5 HIGH, 6 MEDIUM, 2 LOW), all accepted except RSR-001 and RSR-005 (rejected — user explicitly decided inline prompts are acceptable with documented tradeoff)

## What

A new `tdd-audit` phase between `tdd-qa` and `done` in the TDD pipeline. While QA asks "does this feature work?", the mini-audit asks "how does this feature break everything else?" — using three adversarial lenses (cross-component interaction, hostile input, resource bounds) that are structurally absent from the QA agent's perspective. Intensity-scaled rounds (standard=1, high=2, critical=3). CRITICAL/HIGH findings are blocking; MEDIUM/LOW are advisory. Architecture-aware: agents read `.correctless/ARCHITECTURE.md` entrypoints and trust boundaries. No convergence loop — fixed rounds per intensity level.

## Rules

- **R-001** [unit]: A new workflow phase `tdd-audit` exists in `hooks/workflow-advance.sh`. The phase sits between `tdd-qa` and `done`. A new transition command `audit-mini` advances from `tdd-qa` or `tdd-impl` to `tdd-audit` (requires tests passing and min QA rounds met — same gate as the existing `done` transition, minus spec integrity checking which stays in `done` only). The `tdd-qa` → `tdd-audit` path is the normal flow; the `tdd-impl` → `tdd-audit` path is the "recheck after fix" flow (R-007). The `done` transition accepts `tdd-audit` in addition to `tdd-qa` and `tdd-verify` as valid source phases. The `fix` transition changes from `require_phase "tdd-qa"` to `require_phase_oneof "tdd-qa" "tdd-audit"` (so findings can trigger a fix round from either phase). The `tdd-audit` phase must be added to `workflow-gate.sh`'s known-phase allowlist AND to the gating case statement (alongside `tdd-qa|tdd-verify`) to receive "code is frozen" blocking. At high+ intensity, `tdd-audit` subsumes `tdd-verify` — the mini-audit IS the final verification before `done`. The `verify-phase` command is NOT required when the mini-audit runs; `/ctdd`'s high+ intensity path changes from `verify-phase` → `done` to `audit-mini` → `done`.

- **R-002** [unit]: The `/ctdd` skill file (`skills/ctdd/SKILL.md`) includes a `## Phase: Mini-Audit (tdd-audit)` section between the QA phase and the "After TDD Completes" section. After QA completes with no BLOCKING findings, `/ctdd` advances to `tdd-audit` via `workflow-advance.sh audit-mini` and spawns the mini-audit agents. At standard intensity, `/ctdd` runs 1 round. At high intensity, 2 rounds. At critical intensity, 3 rounds. These are fixed — no convergence loop.

- **R-003** [unit]: Each mini-audit round spawns three specialist agents as forked subagents, running in parallel:

  1. **Cross-component interaction agent**: "You are testing how this feature interacts with the rest of the system. Read the entrypoints in `.correctless/ARCHITECTURE.md` and the trust boundaries. For each entrypoint whose scope overlaps with the changed files, ask: does this feature change behavior that other components depend on? Does this feature assume invariants that other components could violate? Does this feature introduce state that other components are unaware of?"

  2. **Hostile input agent**: "You are an attacker. The feature implementation is in front of you. For each input this feature accepts (function arguments, config values, file contents, environment variables, network data), find an input that causes incorrect behavior — not just a crash, but a wrong result, a security bypass, or silent data corruption. Constructed test scenarios with clean inputs don't count — find the ugly inputs."

  3. **Resource bounds agent**: "You are a reliability engineer. For each resource this feature allocates, manages, or depends on (memory, file handles, goroutines, connections, disk space, CPU time), find a scenario where the resource is exhausted, leaked, or contended. What happens at 10x the expected load? What happens when the resource is unavailable? What happens on graceful shutdown during an operation?"

- **R-004** [unit]: Each agent receives as context: the spec, `.correctless/ARCHITECTURE.md` (including entrypoints YAML), `.correctless/AGENT_CONTEXT.md`, `.correctless/antipatterns.md`, the source code changed by this feature (from `git diff` against the base branch), and the test files. Agents have read-only tools: `Read, Grep, Glob, Bash(git diff*, git log*, git show*)`. No Write, no Edit.

- **R-005** [unit]: Each agent returns findings using the `MA-` prefix (not `QA-`) to distinguish mini-audit findings from QA findings in conversation, postmortems, and cross-references:
  ```
  FINDING: MA-001
  SEVERITY: CRITICAL|HIGH|MEDIUM|LOW|UNCERTAIN
  LENS: cross-component|hostile-input|resource-bounds
  RULE: R-xxx or null
  DESCRIPTION: [what's wrong]
  INSTANCE_FIX: [fix this specific bug]
  CLASS_FIX: [prevent this category]
  ```
  Mini-audit finding IDs use their own sequence: `MA-001`, `MA-002`, etc., resetting per feature. The orchestrator persists findings to `.correctless/artifacts/qa-findings-{task-slug}.json` (using the task slug from `workflow-advance.sh init`, not the branch slug — consistent with `/ctdd`'s existing QA findings convention) by appending to the existing findings array (from QA rounds). The `LENS` field and the `MA-` prefix distinguish mini-audit findings from QA findings — both in the persisted JSON and in conversation. Someone reading "MA-003 (hostile-input)" six months later knows immediately this came from the mini-audit, not QA. Downstream consumers of `qa-findings` (`/cverify`, `/cspec`, `/cpostmortem`) must treat `MA-xxx` findings with CRITICAL/HIGH severity as BLOCKING, identical to `QA-xxx` BLOCKING findings. No consumer changes are needed if they already count by severity rather than by prefix.

- **R-006** [unit]: CRITICAL and HIGH findings from the mini-audit are blocking — they must be fixed before `done`. The orchestrator presents each CRITICAL/HIGH finding to the user with disposition options:
  ```
    1. Fix now (recommended) — address before proceeding
    2. Accept risk — document why this is tolerable
    3. Dispute — explain why this is not an issue

    Or type your own: ___
  ```
  MEDIUM and LOW findings are advisory — presented to the user but do not block `done`. The user can choose to fix them or acknowledge them.

- **R-007** [unit]: When CRITICAL/HIGH findings are accepted for fixing, `/ctdd` transitions back to `tdd-impl` via `workflow-advance.sh fix`, spawns a fix agent that writes both the fix AND a regression test for the fix, then transitions directly to `tdd-audit` via `workflow-advance.sh audit-mini` (which accepts `tdd-impl` as a source phase per R-001) and re-runs only the mini-audit round that produced the finding — not the full QA cycle, not all completed rounds. The fix agent must add a regression test that would fail if the fix were reverted — this is consistent with QA fix rounds, where every BLOCKING finding gets both an instance fix and a durable test. A fix without a regression test is incomplete. This is a fix-and-recheck loop, not a convergence loop — the recheck runs only the three lenses for a single round, not a fresh QA round. At critical intensity with 3 rounds, a fix in round 1 re-runs only round 1's lenses, not all 3 rounds.

- **R-008** [unit]: At high+ intensity with multiple rounds, round 2+ agents do NOT see previous rounds' findings — they start fresh with a hostile lens, preventing anchoring to previous findings. Deduplication happens at the orchestrator level after collection. Each round after the first also receives a "raise the bar" prompt:
  > "The previous round's agents were sloppy and missed things. The agents were overconfident and under-thorough. Do better."
  This is the same pattern used by `/caudit` (R-003 in caudit spec). Note: the raise-the-bar prompt is aesthetic, not structural. The actual mechanism for round 2 being better than round 1 is the fresh-context anchoring prevention and the orchestrator-level deduplication. The prompt is cheap and may help, but the structural guarantees are R-003's concrete lens definitions and this rule's no-anchoring constraint.

- **R-009** [integration]: The `/cauto` pipeline (`skills/cauto/SKILL.md`) acknowledges the `tdd-audit` phase in its workflow state machine transitions section. A new row is added to the phase-to-step mapping table: `| tdd-audit | Resume from ctdd (handles internal TDD phases) → simplify → cverify → cupdate-arch → cdocs → consolidation → PR |`. The transition sequence is updated to include `tdd-audit` between `tdd-qa` and `done`. `/cauto` does not need to invoke the mini-audit directly — `/ctdd` handles it internally, same as QA. `/cauto` just needs to recognize the phase in its state monitoring.

- **R-010** [unit]: The mini-audit progress is visible to the user. Before each round, announce: "Starting mini-audit round {N}/{total} — spawning 3 specialist agents (cross-component, hostile input, resource bounds)." As each agent completes, announce immediately: "{Agent name} complete — found {N} findings ({C} critical/high, {M} medium/low). {M} agents still running..." After all agents complete: "Round {N} complete — {N} total findings ({C} blocking, {A} advisory)."

- **R-011** [unit]: The `/ctdd` pipeline diagram is updated to show the mini-audit phase:
  ```
    ✓ RED → ✓ audit → ✓ GREEN → ✓ simplify → ✓ QA → ▶ mini-audit → done
  ```
  The "After TDD Completes" section and the Constraints section pipeline description are both updated to include the mini-audit phase.

- **R-012** [unit]: The mini-audit agents are architecture-aware. If `.correctless/ARCHITECTURE.md` contains entrypoints (the `correctless:entrypoints:start` / `correctless:entrypoints:end` markers), the cross-component agent must reference the entrypoints that overlap with the feature's scope. If no entrypoints exist, the cross-component agent falls back to `git diff`-scoped analysis: "What other files import symbols from the changed files? What callers depend on the changed interfaces?" This is language-agnostic via grep/Serena and does not require a per-language pattern library — the fallback is best-effort, not exhaustive. The hostile input agent reads trust boundaries (TB-xxx) to identify which inputs cross trust boundaries. The resource bounds agent reads environment assumptions (ENV-xxx) for resource constraints.

- **R-013** [unit]: The mini-audit does NOT use a convergence loop. Each intensity level has a fixed number of rounds (1/2/3). After the final round, all remaining CRITICAL/HIGH findings must be fixed or explicitly accepted as risk. There is no "keep running until clean" mechanic — that is `/caudit`'s domain. The mini-audit is a fixed-cost addition to the TDD cycle.

- **R-014** [unit]: An honest uncertainty mechanism: when a mini-audit agent cannot determine whether a finding is real (e.g., it can see a potential issue but cannot trace the full code path, or it doesn't understand the system well enough to confirm), it must label the finding as `UNCERTAIN` severity rather than inflating to HIGH or suppressing entirely. `UNCERTAIN` findings are presented to the user as advisory with a note explaining why the agent is unsure. This is non-blocking. The agent must never silently downgrade an issue it doesn't understand — uncertainty is a valid output. If >50% of findings in a round are UNCERTAIN, the round is flagged as low-confidence and the user is warned.

- **R-015** [unit]: Token tracking for the mini-audit follows the shared constraints. Skill-specific values: `skill: "ctdd"`, `phase: "mini-audit-round-N"`, `agent_role: "cross-component|hostile-input|resource-bounds"`. The `tdd-audit` → `ctdd` mapping must be added to `hooks/token-tracking.sh`'s phase-to-skill hardcoded map so token entries are correctly attributed.

- **R-016** [unit]: The intensity configuration table at the top of `/ctdd`'s SKILL.md is updated to include a "Mini-audit rounds" row: standard=1, high=2, critical=3.

- **R-017** [unit]: Documentation files are updated: `docs/skills/ctdd.md` describes the mini-audit phase. Test/assertion counts in CONTRIBUTING.md and README.md are updated (skill count does not change — the mini-audit is a new phase in an existing skill, not a new skill). The AP-005 drift test catches stale counts. The AGENT_CONTEXT.md pipeline description is updated to include the mini-audit phase.

- **R-018** [unit]: Deduplication across rounds is by file + issue category (not function-level — the finding format does not include a structured function field, and extracting function names from descriptions is unreliable). When two findings from different rounds or different lenses describe the same category of issue in the same file, the orchestrator keeps the higher-severity finding and adds a `duplicate_of` field to the lower-severity one in the persisted JSON (e.g., `"duplicate_of": "MA-002"`). Duplicate findings are not presented to the user separately — they appear as a note on the kept finding: "Also identified by {lens} in round {N}." This prevents the user from triaging the same issue twice while preserving the evidence that multiple lenses converged on the same problem.

- **R-019** [unit]: If a mini-audit agent fails (context limit, tool error, malformed output, timeout), the round completes with the remaining agents' findings. The orchestrator logs the failure, presents the successful agents' findings normally, and warns the user which lens was missed: "Warning: {agent name} agent failed ({reason}). Round {N} results are from {remaining lenses} only. The {missing lens} perspective was not evaluated." No automatic retry — retries are expensive and the other two lenses are still valuable. The user can choose to re-run the round manually if the missed lens is critical.

- **R-020** [unit]: When all three agents in a round return zero findings AND all three agents completed successfully (per R-019), the orchestrator announces "Mini-audit round {N} clean — no findings across all three lenses." and waits for the user before advancing. If any agent failed, the round is announced as "incomplete" rather than "clean" per R-019 — zero findings from failed agents is not the same as zero findings from successful agents. At multi-round intensity (high/critical), subsequent rounds still run even if earlier rounds were clean — the fresh-context, no-anchoring design means a later round may find what an earlier one missed. After the final round completes clean, the orchestrator announces "Mini-audit complete — no blocking findings. Ready to advance to done." and waits. It does not auto-transition to `done` — consistent with the shared constraint "never auto-invoke the next skill."

## Won't Do

- **Convergence loop** — fixed rounds per intensity, not run-until-clean. `/caudit` handles convergence.
- **Full QA re-run after mini-audit fixes** — the fix-and-recheck loop re-runs only the mini-audit lenses, not QA.
- **Standalone invocation** — the mini-audit is part of `/ctdd`, not a separate skill. Users wanting standalone adversarial audits use `/caudit`.
- **Fix-diff reviewer integration** — `/caudit` uses the fix-diff reviewer plugin agent for fix verification. The mini-audit's fix round is simpler (re-run the three lenses). Adding fix-diff reviewer to the mini-audit would duplicate `/caudit`'s mechanism for a lighter-weight phase.
- **New plugin agents** — the three lenses are inline subagent prompts spawned by `/ctdd`, not persistent `agents/*.md` definitions. This is a pragmatic choice: the prompts are TDD-context-specific and don't need cross-skill reuse today. This is technically inconsistent with ABS-010 (which was just enforced for `/carchitect`'s architecture-reviewer), but the tradeoff is different — architecture-reviewer is invoked cross-skill and needs a stable contract; mini-audit lenses are internal to `/ctdd`. If `/ctdd`'s SKILL.md becomes too long or a future feature needs these lenses elsewhere, extract to `agents/*.md` then.

## Risks

- **Mini-audit becomes a rubber stamp**: The three agents find nothing because the lenses are too narrow or the prompts are too generic, creating false confidence that /caudit will be clean.
  1. Mitigate (recommended) — R-003 defines concrete, actionable lenses with specific instructions (not "find bugs" but "for each input this feature accepts, find an input that causes incorrect behavior"). R-008's no-anchoring constraint ensures later rounds are independent, not derivative. The benthic data (DA-002) shows these three categories account for most of what /caudit finds that TDD misses.

- **Mini-audit adds 5-10 minutes per feature at standard intensity**: One round with three parallel agents isn't free.
  1. Accept — correctness over velocity. The mini-audit catches issues that would otherwise require a full /caudit cycle (30-60 minutes) or escape to production. Even at standard intensity, one round of three parallel agents is cheaper than one round of /caudit's 4-6 agents.

- **Overlap with QA agent's work**: The QA agent already checks "does the implementation satisfy the rule?" The cross-component lens might duplicate this.
  1. Mitigate (recommended) — R-003 specifically directs each lens AWAY from rule satisfaction ("does this feature break everything else?" vs "does this feature work?"). The QA agent's prompt never asks about cross-component interaction, hostile inputs, or resource bounds. The lenses are orthogonal by design.

- **UNCERTAIN severity becomes a dumping ground**: Agents use UNCERTAIN to avoid committing to a severity, flooding the user with noise.
  1. Mitigate (recommended) — R-014 requires agents to explain WHY they're uncertain. UNCERTAIN without explanation is equivalent to no finding. If >50% of findings in a round are UNCERTAIN, the round is flagged as low-confidence.

- **Fix-and-recheck loop becomes expensive**: Fixing CRITICAL/HIGH findings and re-running three agents could add 15+ minutes per fix cycle.
  1. Accept — CRITICAL/HIGH findings that survive QA are genuine issues. The fix cost is justified. The fixed rounds cap (R-013) prevents unbounded looping.

## Open Questions

- **OQ-001**: Should the mini-audit run at standard intensity at all, or should it be high+ only? **Tentative answer**: run at all intensities. The mini-audit's three lenses catch categorically different things than QA — QA asks "does the feature satisfy its rules?", the mini-audit asks "does the feature break other things, withstand hostile input, and respect resource bounds?" These are not intensity-dependent questions. A standard-intensity CRUD endpoint can still have a resource leak or a cross-component side effect. Intensity gates should control how hard you look (1 round vs 3), not whether you look at all. One round at standard is looking once; zero rounds is choosing not to look. If data shows standard-intensity projects consistently get zero mini-audit findings, gate it behind high+ in a future release.

- **OQ-002**: Should mini-audit findings be persisted separately from QA findings (e.g., `mini-audit-findings-{slug}.json`) or appended to the existing `qa-findings-{slug}.json`? **Tentative answer**: append to `qa-findings` with a `LENS` field to distinguish them. Downstream consumers (`/cverify`, `/cspec`, `/cpostmortem`) already read `qa-findings` — a separate file means they need to be updated. The LENS field provides filtering.

- **OQ-003**: When the mini-audit runs multiple rounds (high/critical), should round 2 agents see round 1's findings to avoid duplicates, or start fresh to prevent anchoring? **Tentative answer**: start fresh (R-008). Anchoring to previous findings makes agents less creative. Deduplication is defined by R-018 (file + issue category, keep higher severity). The cost of duplicate findings is low (orchestrator deduplicates mechanically); the cost of anchoring is high (missed novel issues).

- **OQ-004**: Should the `UNCERTAIN` severity (R-014) back-propagate to QA findings too? The same problem exists there — QA agents inflate ambiguous issues to BLOCKING or suppress them entirely. Adding UNCERTAIN to the QA agent's severity vocabulary would improve QA honesty across the board. **Tentative answer**: yes, but out of scope for this spec. File as a separate `/ctdd` improvement — the QA agent prompt change is small but the finding format change affects downstream consumers (`/cverify`, `/cpostmortem`).
