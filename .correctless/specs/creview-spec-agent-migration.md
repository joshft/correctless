# Spec: Migrate /creview-spec Adversarial Agents to Plugin Agent Files

## Metadata
- **Created**: 2026-05-11T20:30:00Z
- **Status**: reviewed
- **Impacts**: autonomous-skill-contract (ABS-010 agent registry)
- **Branch**: feature/creview-spec-agent-migration
- **Research**: null
- **Intensity**: high
- **Recommended-intensity**: high
- **Intensity reason**: project floor is high (workflow-config.json)
- **Override**: none

## Context
The `/creview-spec` skill currently defines 6 adversarial review agent prompts as inline blockquotes in `skills/creview-spec/SKILL.md`. This is AP-013 (inline subagent system prompts): the prompts lack tool pinning, harness-prior suppression, and behavioral overrides that dedicated `agents/*.md` files provide structurally. This is the third migration (M-3) in the general-purpose → agents/*.md plan, after ctdd-red (M-1) and ctdd-green (M-2).

## Scope
**In scope**: Extract 6 inline adversarial agent prompts into dedicated plugin agent files under `agents/`. Update `/creview-spec` SKILL.md to dispatch via `Task(subagent_type="correctless:<agent-name>")`. Add `Task` to the skill's allowed-tools. Update ABS-010 agent registry in ARCHITECTURE.md.

**Out of scope**: The self-assessment agent (Step 0) — different shape (bootstrapping, output consumed by agents not user). The /ctdd upgrade-compat lens — reviews implementation not specs, different behavioral needs, separate migration item. Changing the intensity-gated agent selection logic (stays in SKILL.md as orchestrator logic). Checkpoint resume logic. External review integration.

## Complexity Budget
- **Estimated LOC**: ~400 (6 agent files × ~50 lines + SKILL.md edits + test file)
- **Files touched**: ~10 (6 new agent files, 1 SKILL.md edit, 1 test file, 1 ARCHITECTURE.md update, sync.sh propagation)
- **New abstractions**: 0 (reuses ABS-010 pattern)
- **Trust boundaries touched**: 1 (ref: TB-005 intra-skill agent handoff — review agents must be read-only)
- **Risk surface delta**: low (extracting existing prompts, not creating new behavior)

## Invariants

### INV-001: Agent files exist with correct frontmatter
- **Type**: must
- **Category**: functional
- **Statement**: Each of the 6 agents must exist as a file under `agents/` with valid YAML frontmatter containing `name`, `description`, and `tools` fields
- **Boundary**: ABS-010
- **Violated when**: An agent file is missing, has no frontmatter, or is missing required fields
- **Enforcement**: CI test assertion (structural test verifies file existence and frontmatter fields)
- **Guards against**: AP-013
- **Test approach**: unit
- **Risk**: medium
- **Implemented in**: _(filled during GREEN phase)_

Agent filenames:
1. `review-spec-red-team.md`
2. `review-spec-assumptions.md`
3. `review-spec-testability.md`
4. `review-spec-design-contract.md`
5. `review-spec-upgrade-compat.md`
6. `review-spec-ux.md`

### INV-002: Read-only tool allowlist
- **Type**: must
- **Category**: security
- **Statement**: Every review-spec agent must have `tools: Read, Grep, Glob` in its frontmatter — no Write, Edit, Bash, or Task
- **Boundary**: TB-005 (intra-skill agent handoff — reviewers must not modify the artifact they review)
- **Violated when**: Any review-spec agent's tools field includes a write-capable tool
- **Enforcement**: CI test assertion (structural test parses tools field and asserts exact set)
- **Guards against**: null
- **Test approach**: unit
- **Risk**: high
- **Implemented in**: _(filled during GREEN phase)_

### INV-003: Namespaced subagent_type dispatch
- **Type**: must
- **Category**: functional
- **Statement**: SKILL.md must dispatch each agent via `Task(subagent_type="correctless:<agent-name>")` where `<agent-name>` matches the agent file's `name` field, not via `Task(subagent_type="general-purpose")`
- **Boundary**: ABS-010
- **Violated when**: SKILL.md uses `general-purpose` or bare agent names without the `correctless:` prefix for any of the 6 agents
- **Enforcement**: CI test assertion (grep SKILL.md for dispatch patterns)
- **Guards against**: AP-013
- **Test approach**: unit
- **Risk**: medium
- **Implemented in**: _(filled during GREEN phase)_

### INV-004: No inline agent prompts remain
- **Type**: must-not
- **Category**: functional
- **Statement**: After migration, SKILL.md must not contain the original inline blockquoted agent prompts for the 6 migrated agents
- **Boundary**: null
- **Violated when**: SKILL.md still contains inline `> You are a security-focused adversary` or similar blockquoted system prompts for any of the 6 agents
- **Enforcement**: CI test assertion (grep for known inline prompt signatures)
- **Guards against**: AP-013
- **Test approach**: unit
- **Risk**: low
- **Implemented in**: _(filled during GREEN phase)_

### INV-005: Shared preamble in each agent
- **Type**: must
- **Category**: functional
- **Statement**: Each of the 6 agent files must contain file-reading instructions for 4 files: AGENT_CONTEXT.md, ARCHITECTURE.md, antipatterns.md, and the spec artifact (referenced as a placeholder path that the orchestrator fills at spawn time). The self-assessment brief is injected into the Task prompt by the orchestrator, not read from disk by the agent.
- **Boundary**: null
- **Violated when**: Any agent file is missing one or more of the 4 preamble file references
- **Enforcement**: CI test assertion (grep each agent file for 3 fixed paths: AGENT_CONTEXT.md, ARCHITECTURE.md, antipatterns.md; plus a spec-path placeholder token such as "spec artifact" or "{spec_path}")
- **Guards against**: AP-025 (PMB-004 — spec path discovery)
- **Test approach**: unit
- **Risk**: low
- **Implemented in**: _(filled during GREEN phase)_

Note: The orchestrator (SKILL.md) discovers the spec path via `workflow-advance.sh status` and injects it into each agent's Task prompt alongside the self-assessment brief. This follows the established pattern from the current inline preamble (SKILL.md line 114: "The spec artifact at {spec_path}").

### INV-006: Unique adversarial lens preserved
- **Type**: must
- **Category**: functional
- **Statement**: Each agent file must contain its unique adversarial lens content — the specialized instructions that distinguish it from the other 5 agents
- **Boundary**: null
- **Violated when**: An agent file contains only the shared preamble without its specialized adversarial instructions, or contains a different agent's lens content
- **Enforcement**: CI test assertion (grep for lens-specific keywords per agent)
- **Guards against**: null
- **Test approach**: unit
- **Risk**: medium
- **Implemented in**: _(filled during GREEN phase)_

Lens-specific keywords (use AND logic where multiple keywords listed — both must appear):
- Red Team: "attack paths" AND "bypass vectors"
- Assumptions: "unstated assumption"
- Testability: "test engineering" AND "vague invariants"
- Design Contract: "design contract" AND "Enforcement:"
- Upgrade Compat: "upgrade compatibility" AND "backward compatibility"
- UX: "sub-lens" AND "new-user"

### INV-007: Distribution parity
- **Type**: must
- **Category**: functional
- **Statement**: Agent files must exist in both source (`agents/`) and distribution (`correctless/agents/`) directories, kept in sync by `sync.sh`
- **Boundary**: ABS-010
- **Violated when**: An agent file exists in source but not distribution, or vice versa, or content differs
- **Enforcement**: CI test assertion (sync.sh --check)
- **Guards against**: null
- **Test approach**: integration
- **Risk**: low
- **Implemented in**: _(filled during GREEN phase)_

### INV-008: ABS-010 registry updated
- **Type**: must
- **Category**: functional
- **Statement**: The ABS-010 entry in `.correctless/ARCHITECTURE.md` must list all 6 new agents in its agent registry
- **Boundary**: ABS-010
- **Violated when**: ABS-010 does not reference one or more of the 6 new agent files
- **Enforcement**: CI test assertion (grep ARCHITECTURE.md for agent names)
- **Guards against**: null
- **Test approach**: unit
- **Risk**: low
- **Implemented in**: _(filled during GREEN phase)_

### INV-009: Task in SKILL.md allowed-tools
- **Type**: must
- **Category**: functional
- **Statement**: The `allowed-tools` field in SKILL.md frontmatter must include `Task` to enable agent dispatch
- **Boundary**: null
- **Violated when**: SKILL.md allowed-tools does not include `Task`
- **Enforcement**: CI test assertion (parse frontmatter)
- **Guards against**: null
- **Test approach**: unit
- **Risk**: medium
- **Implemented in**: _(filled during GREEN phase)_

### INV-010: Intensity-gated selection stays in SKILL.md
- **Type**: must
- **Category**: functional
- **Statement**: The orchestrator logic that selects which agents to spawn based on intensity level (low: 2, standard: 3, high/critical: 6) must remain in SKILL.md, not be moved into agent files
- **Boundary**: BND-001 (agent vs orchestrator separation)
- **Violated when**: Agent files contain intensity-gating logic, or SKILL.md no longer contains the intensity-based agent selection
- **Enforcement**: CI test assertion (grep SKILL.md for intensity references, grep agent files for absence using denylist)
- **Guards against**: null
- **Test approach**: unit
- **Risk**: low
- **Implemented in**: _(filled during GREEN phase)_

Denylist patterns for agent files (must NOT contain any of these):
- "intensity" in conditional context (e.g., "if.*intensity", "intensity.*standard")
- "spawn.*agents" or "select.*agents" in conditional context
- Agent-count gating patterns (e.g., "low.*2.*standard.*3")

### INV-011: Harness-prior suppression
- **Type**: must
- **Category**: functional
- **Statement**: Each agent file must include an explicit behavioral override directing exhaustive output to counteract the Claude 4.7 terseness prior that truncates assumption lists and attack paths
- **Boundary**: null
- **Violated when**: An agent file lacks its required exhaustive-output phrase from the per-agent keyword table below
- **Enforcement**: CI test assertion (grep for per-agent exhaustive-output keyword)
- **Guards against**: null
- **Test approach**: unit
- **Risk**: medium
- **Implemented in**: _(filled during GREEN phase)_

Per-agent exhaustive-output keyword table (each agent file must contain its required phrase):
- Red Team: "enumerate ALL attack paths"
- Assumptions: "List EVERY assumption"
- Testability: "evaluate ALL invariants"
- Design Contract: "check EVERY INV-xxx"
- Upgrade Compat: "check ALL 5 items"
- UX: "evaluate through EVERY sub-lens"

### INV-012: Output format contract
- **Type**: must
- **Category**: functional
- **Statement**: Each agent file must specify its output format. All 6 review-spec agents use the same format: a markdown list where each finding starts with a category label (e.g., `**Security**:`, `**Testability**:`) followed by description. This matches the current inline prose behavior and enables deterministic orchestrator synthesis.
- **Boundary**: null
- **Violated when**: An agent file lacks an output format specification, or specifies a format inconsistent with the markdown-list-with-category-label contract
- **Enforcement**: CI test assertion (grep each agent file for output format instruction containing "category" or "finding")
- **Guards against**: null
- **Test approach**: unit
- **Risk**: medium
- **Implemented in**: _(filled during GREEN phase)_

## Prohibitions

### PRH-001: No inline agent prompts for migrated agents
- **Statement**: After migration, the 6 adversarial agent prompts must not exist as inline blockquotes in SKILL.md
- **Detection**: structural test grepping for known inline prompt signatures
- **Consequence**: Agents dispatch via general-purpose without tool pinning or harness-prior suppression, defeating the migration purpose

### PRH-002: No write tools in review agents
- **Statement**: Review-spec agents must never have Write, Edit, Bash, or Task in their tools field
- **Detection**: structural test parsing tools field
- **Consequence**: Reviewer agents could modify the spec they're reviewing, violating TB-005

## Boundary Conditions

### BND-001: Agent vs orchestrator separation
- **Boundary**: TB-005
- **Input from**: SKILL.md orchestrator logic
- **Validation required**: Agent files contain only their review lens and behavioral directives; orchestrator logic (intensity gating, agent selection, synthesis, checkpoint resume) stays in SKILL.md
- **Failure mode**: fail-closed — if an agent file contains orchestrator logic, it's a spec violation caught by tests

### BND-002: Shared preamble is intentional instruction duplication
- **Boundary**: null
- **Input from**: Each agent file
- **Validation required**: The shared preamble (read AGENT_CONTEXT.md, ARCHITECTURE.md, antipatterns.md, spec artifact at injected path) is duplicated across all 6 agent files. This is accepted as low-risk instruction duplication, not logic duplication per AP-005
- **Failure mode**: N/A — intentional design decision, not a boundary to enforce
- **Drift guard**: A structural test must extract the preamble section from each of the 6 agent files and assert they are identical (byte-equal after stripping agent-specific lens content). This catches the scenario where a future edit updates 5 of 6 files, leaving one agent with a stale preamble.

## STRIDE Analysis

### STRIDE for TB-005: Intra-skill agent handoff
- **Spoofing**: Low risk — agents are invoked by SKILL.md, not by external input
- **Tampering**: Mitigated by INV-002 (read-only tools) — agents cannot modify spec artifacts
- **Repudiation**: Low risk — agent findings are persisted to artifacts by the orchestrator
- **Information Disclosure**: Low risk — agents read project files that are already accessible
- **Denial of Service**: Low risk — agent spawning is bounded by SKILL.md intensity gating (max 6)
- **Elevation of Privilege**: Mitigated by INV-002 — agents cannot escalate from read-only to write via tool allowlist

## Environment Assumptions
- **EA-001**: Plugin agent dispatch — refs ABS-010 — `Task(subagent_type="correctless:<name>")` resolves to `agents/<name>.md` per the plugin agent contract. If the dispatch mechanism changes, agents may not load. If dispatch fails for any agent (plugin not found, version mismatch, context exhaustion), the orchestrator proceeds with available agents and notes the absence — same fallback pattern as the existing UX auditor fail-open behavior in SKILL.md.

## Design Decisions
- **DD-001**: 6 independent files (not 1 parameterized agent) — each lens has distinct behavioral directives, keyword signatures, and output format expectations. A parameterized agent would need conditional blocks that obscure the lens-specific content.
- **DD-002**: Self-assessment stays inline — it bootstraps the review process (its output feeds into the 6 agents as input), has a different shape (not an adversarial lens), and its output is consumed by agents not presented to the user. The orchestrator (SKILL.md) injects the self-assessment output into each agent's Task prompt as ephemeral context, not as a persisted artifact. Agents receive it as part of their spawn prompt, not by reading a file from disk.
- **DD-003**: Shared preamble duplicated — analyzed 5 composition alternatives (includes, runtime instructions, build-time concat, SKILL.md passthrough, parameterized single agent); all are worse than ~5-line instruction duplication across 6 files.

## Open Questions
- **OQ-001**: Should the UX agent's calibration examples (PMB-004, PMB-006, PMB-008, PMB-009) be kept verbatim or summarized? They're ~15 lines — keeping them preserves calibration fidelity but makes the agent file longer than the others. **Recommendation**: keep verbatim — calibration examples are the primary UX fix from PMB-007.

## Verification Procedure
- **VP-001**: Agent discoverability smoke test — after creating agent files, verify `Task(subagent_type="correctless:review-spec-red-team")` resolves correctly by checking that the agent file exists at the expected path with valid frontmatter.
