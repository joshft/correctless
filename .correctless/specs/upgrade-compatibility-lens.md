# Spec: Upgrade Compatibility Lens

## Metadata
- **Task**: upgrade-compatibility-lens
- **Recommended-intensity**: high
- **Intensity**: high
- **Intensity reason**: file path signal (skills/creview-spec, skills/ctdd) matches security-adjacent skills; project floor enforces high
- **Override**: none

## What

Add a 5th adversarial agent to `/creview-spec` and a 4th lens to the `/ctdd` mini-audit, both asking: "what happens to an existing user running an older version of correctless who upgrades?" PMB-003 proved this gap — setup silently skipped 16 scripts across 5 PRs because no phase asked the upgrade question. Full redundancy: both phases ask the same questions, the spec lens catching design omissions and the mini-audit lens catching implementation omissions.

## Rules

- **R-001** [unit]: `/creview-spec` SKILL.md spawns a 5th adversarial agent — the **Upgrade Compatibility Auditor** — alongside the existing 4 agents at high+ intensity. At standard intensity (which only spawns 3 agents), the upgrade agent is not spawned. This asymmetry with R-002 is intentional: standard intensity runs 3 review agents; the upgrade lens is lower marginal value at spec-review time because upgrade issues are implementation-level (PMB-003 was "setup didn't install files," not "spec forgot to mention installation"), caught more reliably by the mini-audit's code-level check in R-002. The agent prompt is:
  > "An existing user has this project's tooling installed from a prior version. A new version ships with the changes described in this spec. Your job is to mechanically check the spec against the 5-item checklist below — do not hallucinate what the project looked like before; work from what the spec adds, changes, or removes. (1) New scripts or hooks that setup/install must propagate — does the spec account for installation? Is the installation mechanism complete (glob vs hardcoded list, see AP-024/PMB-003)? (2) New config keys — does the spec require defaults so old configs still work? (3) Schema changes in state files, artifacts, or config — does the spec address backward compatibility for old consumers? (4) Removed or renamed files — does the spec include a migration path? (5) New features that depend on artifacts old versions don't produce — does the spec require graceful degradation? For each finding, state what the upgrade user experiences (error, silent degradation, or crash) and what the spec should add to prevent it."

- **R-002** [unit]: `/ctdd` SKILL.md adds a 4th mini-audit specialist — the **upgrade compatibility agent** — alongside cross-component, hostile-input, and resource-bounds. This agent runs at all intensity levels (unlike R-001 which gates behind high+), because upgrade issues are primarily implementation-level bugs caught by reading code. The agent prompt is:
  > "An existing user has this project's tooling installed from a prior version. They update to the version with these changes. Your job is to mechanically check the implementation (git diff against base branch) against the 5-item checklist below — do not hallucinate what the project looked like before; work from what the diff adds, changes, or removes. (1) Does the install/setup mechanism install all new files? Verify glob patterns, not hardcoded lists (AP-024/PMB-003). (2) Do new config keys have fallback defaults in the code that reads them? (3) Do new artifact schemas include version markers or graceful parsing for old formats? (4) Do removed or renamed files have migration paths? (5) Do new features that depend on artifacts from other new features degrade gracefully when those artifacts don't exist yet? For each issue, report it as a finding with the MA- prefix and LENS: upgrade-compatibility."

- **R-003** [unit]: The upgrade compatibility agent in mini-audit uses LENS value `upgrade-compatibility` in its findings (MA- prefix, same format as the other 3 lenses). This value must appear in the LENS enum alongside `cross-component`, `hostile-input`, and `resource-bounds`.

- **R-004** [unit]: Both prompts (review and mini-audit) reference AP-024 (hardcoded file lists) and PMB-003 as concrete examples of the bug class this lens catches. The prompts must contain the literal strings "AP-024" and "PMB-003" so the agent has historical context for what upgrade failures look like.

- **R-005** [unit]: The mini-audit progress announcement updates from "3 specialist agents" to "4 specialist agents" (or the count must reflect the actual number spawned). All mini-audit round announcements, token tracking agent_role values, and agent count references in the skill are updated.

- **R-006** [unit]: All count references in `/creview-spec` SKILL.md are updated from 4 to 5 at high+ intensity. This includes: progress announcements ("Spawns N adversarial agents", "Spawning N adversarial agents in parallel"), the intensity tier description ("spawn all four" becomes "spawn all five"), the task list (adds a 6th item for the Upgrade Compatibility Auditor between Design Contract Checker and Synthesis), the "Present to Human" category list (adds a 7th category for upgrade compatibility findings), the checkpoint phase list and `completed_phases` JSON example (adds `upgrade-compatibility` as a checkpoint phase), and the token tracking `agent_role` enum (adds `upgrade-compatibility`). The agent count at standard intensity remains 3 (upgrade agent not spawned at standard).

- **R-007** [unit]: Token tracking for the new agents follows existing conventions. Mini-audit: `agent_role: "upgrade-compatibility"`. Review-spec: logged as a 5th agent in the review team, no special token tracking changes needed.

- **R-008** [unit]: The mini-audit intensity table row for rounds (standard=1, high=2, critical=3) is unchanged — the upgrade lens runs in the same rounds as the other 3 lenses, not as additional rounds. Each round spawns 4 agents instead of 3.

## Won't Do

- **Automated upgrade testing** — actually running setup in a sandbox with an old version and comparing outputs. That's a test infrastructure feature, not a prompt change.
- **Version markers in artifacts** — adding schema versions to JSON artifacts. Useful but a separate spec per artifact.
- **Backward compatibility guarantees** — promising old versions work with new data. This lens catches issues; fixing them is the feature author's job.

## Risks

- **False positive rate** — the upgrade lens may flag things that degrade gracefully by design (e.g., "new cost artifact doesn't exist for old features" — correct, that's the graceful degradation path).
  1. Mitigate — the prompt explicitly says "degrade gracefully" is acceptable; the agent should flag missing degradation, not missing features.

- **Agent cost** — one more agent per mini-audit round and per review. At high intensity with 2 mini-audit rounds, that's 2 extra agent calls.
  1. Accept — marginal cost, high value. PMB-003 cost a week of stale benthic data.

## Open Questions

None.
