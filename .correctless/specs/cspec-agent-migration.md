# Spec: Migrate /cspec Research Agent to Plugin Agent File

## Metadata
- **Created**: 2026-05-12T04:00:00Z
- **Status**: reviewed
- **Impacts**: autonomous-skill-contract (ABS-010 agent registry)
- **Branch**: feature/cspec-agent-migration
- **Research**: null
- **Recommended-intensity**: high
- **Intensity**: high
- **Intensity reason**: project floor is high (workflow-config.json)
- **Override**: none

## Context
The `/cspec` skill defines a research subagent as an inline blockquoted prompt in `skills/cspec/SKILL.md` (Step 2, lines 176-233). This is AP-013 (inline subagent system prompts): the prompt lacks tool pinning, harness-prior suppression, and behavioral overrides that dedicated `agents/*.md` files provide structurally. This is the fourth migration (M-4) in the general-purpose → agents/*.md plan, after ctdd-red (M-1), ctdd-green (M-2), and creview-spec adversarials (M-3).

## Scope
**In scope**: Extract the inline research subagent prompt into a dedicated plugin agent file at `agents/cspec-research.md`. Update `/cspec` SKILL.md to dispatch via `Task(subagent_type="correctless:cspec-research")` and remove the stale "(forked context)" annotation. Add `Task` to the skill's allowed-tools. Update ABS-010 agent registry in ARCHITECTURE.md (including network-read tool class). Update AGENT_CONTEXT.md agents table.

**Out of scope**: Removing WebSearch/WebFetch from cspec SKILL.md allowed-tools (separate cleanup — the orchestrator's tool set is orthogonal to the agent's). Changing the conditional spawn logic (stays in SKILL.md as orchestrator logic). Other inline prompts in other skills (future M-5+). Changing the research brief format or search topic list.

## Complexity Budget
- **Estimated LOC**: ~180 (1 agent file × ~80 lines + SKILL.md edits + test file with 16 invariants)
- **Files touched**: ~8 (1 new agent file, 1 SKILL.md edit, 1 test file, 1 ARCHITECTURE.md update, 1 AGENT_CONTEXT.md update, sync.sh propagation, cascading test updates if any)
- **New abstractions**: 0 (reuses ABS-010 pattern)
- **Trust boundaries touched**: 1 (ref: TB-007 external web content ingestion — research agent must not write files, web content must be treated as untrusted)
- **Risk surface delta**: low (extracting existing prompt, not creating new behavior)

## Invariants

### INV-001: Agent file exists with correct frontmatter
- **Type**: must
- **Category**: functional
- **Statement**: The agent must exist as `agents/cspec-research.md` with valid YAML frontmatter containing `name`, `description`, and `tools` fields
- **Boundary**: ABS-010
- **Violated when**: The agent file is missing, has no frontmatter, or is missing required fields
- **Enforcement**: CI test assertion (structural test verifies file existence and frontmatter fields)
- **Guards against**: AP-013
- **Test approach**: unit
- **Risk**: medium
- **Implemented in**: _(filled during GREEN phase)_

### INV-002: Network-capable write-free tool allowlist
- **Type**: must
- **Category**: security
- **Statement**: The research agent must have `tools: WebSearch, WebFetch, Read, Grep` in its frontmatter — no Write, Edit, Bash, Glob, or Task
- **Boundary**: TB-007 (external web content ingestion — the research agent fetches untrusted web content and returns it to the orchestrator; the agent must not write files directly; the orchestrator writes the research brief to disk and treats it as untrusted data)
- **Violated when**: The agent's tools field includes a write-capable tool (Write, Edit, Bash) or an escalation tool (Task)
- **Enforcement**: CI test assertion (structural test parses tools field and asserts exact set)
- **Guards against**: null
- **Test approach**: unit
- **Risk**: high
- **Implemented in**: _(filled during GREEN phase)_

Note: The tool set differs from the M-3 review agents (Read, Grep, Glob). The research agent needs WebSearch and WebFetch for external documentation lookups but does NOT need Glob (it searches the web, not the local filesystem for file patterns). The orchestrator (cspec SKILL.md) writes the research brief to `.correctless/artifacts/research/`.

### INV-003: Namespaced subagent_type dispatch
- **Type**: must
- **Category**: functional
- **Statement**: SKILL.md must dispatch the research agent via `Task(subagent_type="correctless:cspec-research")`, not via `Task(subagent_type="general-purpose")`
- **Boundary**: ABS-010
- **Violated when**: SKILL.md uses `general-purpose` or a bare agent name without the `correctless:` prefix for the research agent
- **Enforcement**: CI test assertion (grep SKILL.md for dispatch pattern)
- **Guards against**: AP-013
- **Test approach**: unit
- **Risk**: medium
- **Implemented in**: _(filled during GREEN phase)_

### INV-004: No inline research agent prompt remains
- **Type**: must-not
- **Category**: functional
- **Statement**: After migration, SKILL.md must not contain the original inline blockquoted research agent prompt
- **Boundary**: null
- **Violated when**: SKILL.md still contains inline `> You are a research agent supporting the spec phase` or the full blockquoted system prompt
- **Enforcement**: CI test assertion (grep for known inline prompt signatures)
- **Guards against**: AP-013
- **Test approach**: unit
- **Risk**: low
- **Implemented in**: _(filled during GREEN phase)_

Denylist signatures (any of these in SKILL.md = violation):
- "You are a research agent supporting the spec phase"
- "Produce a structured brief"
- "Search for:" (mid-body anchor from search topics list)

Additionally, the stale "(forked context)" annotation on the dispatch instruction must be removed or replaced with "(via Task)" — Task dispatch is not the same as `context: fork` (ref AP-027/PMB-006).

### INV-005: Orchestrator-injected dynamic context
- **Type**: must
- **Category**: functional
- **Statement**: The agent file must contain placeholder references for the dynamic context that the orchestrator injects at spawn time: research topic and feature description. The agent file must also contain instructions to read `.correctless/AGENT_CONTEXT.md` directly (for project context that doesn't change per-spawn)
- **Boundary**: null
- **Violated when**: The agent file has no placeholder tokens for research topic or feature description, or lacks a reference to AGENT_CONTEXT.md
- **Enforcement**: CI test assertion (grep agent file for placeholder tokens and AGENT_CONTEXT.md reference)
- **Guards against**: AP-025 (PMB-004 — artifact path discovery)
- **Test approach**: unit
- **Risk**: low
- **Implemented in**: _(filled during GREEN phase)_

Placeholder tokens the agent file must contain (the orchestrator fills these when spawning via the Task prompt parameter — see EA-003):
- `{topic}` — research topic placeholder (matching the existing inline prompt's `RESEARCH TOPIC:` label)
- `{feature_description}` — feature context placeholder (matching the existing inline prompt's `CONTEXT:` label)

File reference the agent file must contain:
- `AGENT_CONTEXT.md`

### INV-006: Research-specific content preserved
- **Type**: must
- **Category**: functional
- **Statement**: The agent file must contain the core research instructions that distinguish it from other agents — the search topics list and the structured brief output format
- **Boundary**: null
- **Violated when**: The agent file lacks the search topics or the brief format specification
- **Enforcement**: CI test assertion (grep for research-specific keywords)
- **Guards against**: null
- **Test approach**: unit
- **Risk**: medium
- **Implemented in**: _(filled during GREEN phase)_

Research-specific keywords (AND logic — both must appear):
- "Current official documentation" (from search topics list)
- "Dependency Health" (from structured brief format)

### INV-007: Skepticism behavioral override
- **Type**: must
- **Category**: functional
- **Statement**: The agent file must include an explicit behavioral override directing skeptical, evidence-based output to counteract training-data staleness and confirmation bias
- **Boundary**: null
- **Violated when**: The agent file lacks the required skepticism phrase
- **Enforcement**: CI test assertion (grep for skepticism keyword)
- **Guards against**: null
- **Test approach**: unit
- **Risk**: medium
- **Implemented in**: _(filled during GREEN phase)_

Required skepticism phrase: "BE SKEPTICAL"

### INV-008: Output format contract
- **Type**: must
- **Category**: functional
- **Statement**: The agent file must specify its output format — a structured markdown research brief with required sections (Current State, Key Findings, Recommended Patterns, Things to Avoid, Version Pins, Dependency Health, Open Questions)
- **Boundary**: null
- **Violated when**: The agent file lacks an output format specification, or specifies a format inconsistent with the structured research brief contract
- **Enforcement**: CI test assertion (grep agent file for output format section headers)
- **Guards against**: null
- **Test approach**: unit
- **Risk**: medium
- **Implemented in**: _(filled during GREEN phase)_

Required section headers in the agent's output format specification (AND logic — all 7 must appear):
- "Current State"
- "Key Findings"
- "Recommended Patterns"
- "Things to Avoid"
- "Version Pins"
- "Dependency Health"
- "Open Questions"

### INV-009: Distribution parity
- **Type**: must
- **Category**: functional
- **Statement**: The agent file must exist in both source (`agents/`) and distribution (`correctless/agents/`) directories, kept in sync by `sync.sh`
- **Boundary**: ABS-010
- **Violated when**: The agent file exists in source but not distribution, or vice versa, or content differs
- **Enforcement**: CI test assertion (sync.sh --check)
- **Guards against**: null
- **Test approach**: integration
- **Risk**: low
- **Implemented in**: _(filled during GREEN phase)_

### INV-010: ABS-010 registry updated with network-read class
- **Type**: must
- **Category**: functional
- **Statement**: The ABS-010 entry in `.correctless/ARCHITECTURE.md` must (a) list cspec-research in its agent registry with `skills/cspec/SKILL.md` as its consumer, and (b) introduce a network-read tool class (WebSearch, WebFetch) alongside the existing write-tools and read-only classifications. Network-read agents can fetch external data but cannot modify project files.
- **Boundary**: ABS-010
- **Violated when**: ABS-010 does not reference cspec-research, or lacks consumer mapping to skills/cspec/SKILL.md, or does not distinguish network-read from local-read-only agents
- **Enforcement**: CI test assertion (grep ARCHITECTURE.md for agent name, consumer skill, and network-read classification)
- **Guards against**: null
- **Test approach**: unit
- **Risk**: low
- **Implemented in**: _(filled during GREEN phase)_

### INV-011: Task in SKILL.md allowed-tools
- **Type**: must
- **Category**: functional
- **Statement**: The `allowed-tools` field in SKILL.md frontmatter must include `Task` to enable agent dispatch
- **Boundary**: null
- **Violated when**: SKILL.md allowed-tools does not include `Task`
- **Enforcement**: CI test assertion (parse frontmatter)
- **Guards against**: AP-008
- **Test approach**: unit
- **Risk**: medium
- **Implemented in**: _(filled during GREEN phase)_

### INV-012: Conditional spawn logic stays in SKILL.md
- **Type**: must
- **Category**: functional
- **Statement**: The orchestrator logic that determines when to spawn the research agent (signal detection — explicit signals, inferred signals) must remain in SKILL.md, not be moved into the agent file
- **Boundary**: BND-001 (agent vs orchestrator separation)
- **Violated when**: The agent file contains signal-detection logic, or SKILL.md no longer contains the research-signal conditions
- **Enforcement**: CI test assertion (grep SKILL.md for signal references, grep agent file for absence using denylist)
- **Guards against**: null
- **Test approach**: unit
- **Risk**: low
- **Implemented in**: _(filled during GREEN phase)_

Denylist patterns for agent file (must NOT contain any of these):
- "research signals" (conditional spawn logic)
- "Spawn the research subagent when" (orchestrator dispatch instruction)
- "Inferred signals" (signal detection logic)

SKILL.md must still contain (at least one):
- "research signals" or "Spawn the research subagent when"

Note: BND-001 lists 4 orchestrator concerns (signal detection, conditional spawn, brief-writing-to-disk, token tracking). The denylist covers signal detection and conditional spawn. Brief-writing-to-disk and token tracking are not denylisted because INV-002 (no Write tool) makes brief-writing structurally impossible from the agent, and token tracking leaking into the agent file is unlikely given the clear separation of concerns. Accepted gap.

### INV-013: AGENT_CONTEXT.md agents table updated
- **Type**: must
- **Category**: functional
- **Statement**: The Agents table in `.correctless/AGENT_CONTEXT.md` must list cspec-research with its consumer skill (skills/cspec/SKILL.md)
- **Boundary**: null
- **Violated when**: AGENT_CONTEXT.md agents table does not include cspec-research
- **Enforcement**: CI test assertion (grep AGENT_CONTEXT.md for cspec-research)
- **Guards against**: AP-005 (stale documentation after refactoring)
- **Test approach**: unit
- **Risk**: low
- **Implemented in**: _(filled during GREEN phase)_

### INV-014: Harness-prior suppression
- **Type**: must
- **Category**: functional
- **Statement**: The agent file must include an explicit behavioral override directing exhaustive, unsummarized output to counteract the parent harness's brevity defaults — matching the pattern established in M-3 review-spec agents
- **Boundary**: null
- **Violated when**: The agent file lacks a harness-prior suppression phrase
- **Enforcement**: CI test assertion (grep for exhaustive-output keyword)
- **Guards against**: null
- **Test approach**: unit
- **Risk**: medium
- **Implemented in**: _(filled during GREEN phase)_

Required harness-prior suppression phrase (at least one must appear): "do not summarize" or "exhaustive"

### INV-015: Data-treatment directive for untrusted web content
- **Type**: must
- **Category**: security
- **Statement**: The agent file must include an explicit data-treatment directive stating that web-fetched content is advisory and untrusted — not to be treated as instructions. The orchestrator (cspec SKILL.md) must treat the research brief as untrusted context when reading it for spec drafting.
- **Boundary**: TB-007
- **Violated when**: The agent file lacks a data-treatment directive for web content, or the orchestrator treats the research brief as trusted input
- **Enforcement**: CI test assertion (grep agent file for untrusted-data directive; grep SKILL.md for untrusted treatment of research brief)
- **Guards against**: null
- **Test approach**: unit
- **Risk**: high
- **Implemented in**: _(filled during GREEN phase)_

Agent file must contain: "advisory" AND ("untrusted" OR "not instructions")
SKILL.md must contain (in the research brief consumption section): "untrusted" or "advisory" adjacent to "research brief" or "research findings"

### INV-016: Network unavailability self-diagnostic
- **Type**: must
- **Category**: functional
- **Statement**: The agent file must include an instruction to explicitly report when web search tools fail or produce no results, rather than silently substituting training data as if it were current research
- **Boundary**: null
- **Violated when**: The agent file lacks a self-diagnostic instruction for web tool failure
- **Enforcement**: CI test assertion (grep agent file for failure-reporting directive)
- **Guards against**: null
- **Test approach**: unit
- **Risk**: medium
- **Implemented in**: _(filled during GREEN phase)_

Required directive keyword: "DO NOT substitute training data" or equivalent explicit instruction against silent degradation

## Prohibitions

### PRH-001: No inline research agent prompt for migrated agent
- **Statement**: After migration, the research agent system prompt must not exist as an inline blockquote in SKILL.md
- **Detection**: structural test grepping for known inline prompt signatures (INV-004 denylist)
- **Consequence**: Agent dispatches via general-purpose without tool pinning, defeating the migration purpose

### PRH-002: No write tools in research agent
- **Statement**: The research agent must never have Write, Edit, Bash, or Task in its tools field
- **Detection**: structural test parsing tools field (INV-002)
- **Consequence**: Research agent could modify project files instead of just gathering information, violating TB-007

## Boundary Conditions

### BND-001: Agent vs orchestrator separation
- **Boundary**: TB-007
- **Input from**: SKILL.md orchestrator logic
- **Validation required**: The agent file contains only research instructions and behavioral directives; orchestrator logic (signal detection, conditional spawn, brief-writing-to-disk, token tracking) stays in SKILL.md
- **Failure mode**: fail-closed — if the agent file contains orchestrator logic, it's a spec violation caught by tests

## STRIDE Analysis

### STRIDE for TB-007: External web content ingestion via research agent
- **Spoofing**: Low risk — agent is invoked by SKILL.md, not by external input
- **Tampering**: MEDIUM risk — the agent fetches content from arbitrary external URLs via WebFetch. Adversarial web content (prompt injection, adversarial SEO, supply-chain disinformation) could influence the research brief, which the orchestrator reads and uses to draft spec invariants. Multi-hop injection path: web content → research brief → spec → implementation agent. Mitigations: (a) INV-002 (no write tools) prevents the agent from directly modifying project files, (b) INV-015 (data-treatment directive) requires the agent to treat web content as advisory/untrusted, (c) INV-007 (BE SKEPTICAL) directs evidence-based output, (d) the orchestrator writes the brief to disk for human review. **Acknowledged gap**: in `/cauto` autonomous mode, there is no human checkpoint between research brief and spec draft — the orchestrator may incorporate adversarial recommendations before human review. TB-002 (script-generated content → LLM context) overlaps in pattern — TB-002's specific concern (JSON interpolation) doesn't directly apply to markdown briefs, but the general boundary (machine-generated content entering LLM reasoning) is relevant.
- **Repudiation**: Low risk — research brief is persisted to `.correctless/artifacts/research/` by the orchestrator
- **Information Disclosure**: Low risk — agent reads project files and web content that are already accessible to the skill. Note: the Read tool gives the agent access to the entire local filesystem including any secrets; this is pre-existing behavior from the inline prompt, not new attack surface. ENV-007 does not support path-scoped Read at the agent level.
- **Denial of Service**: Low risk — agent spawning is bounded by SKILL.md conditional logic (max 1 research agent per spec). Web requests could hang or timeout but this affects only the research phase, which is conditional and advisory.
- **Elevation of Privilege**: Mitigated by INV-002 — agent cannot escalate from read/search to write via tool allowlist

## Environment Assumptions
- **EA-001**: Plugin agent dispatch — refs ABS-010 — `Task(subagent_type="correctless:cspec-research")` resolves to `agents/cspec-research.md` per the plugin agent contract. If dispatch fails (plugin not found, version mismatch, context exhaustion), the orchestrator proceeds without research findings and notes the absence — research is conditional and advisory.
- **EA-002**: WebSearch and WebFetch tool availability in plugin agents — `WebSearch` and `WebFetch` specified in the agent's `tools:` frontmatter field are valid tool names that the Claude Code plugin-agent loader recognizes, resolves, and grants to the spawned agent. This is the first plugin agent to use network tools; all 13 prior agents use only {Read, Grep, Glob, Write, Edit, Bash, Task}. If the loader silently ignores WebSearch/WebFetch, the agent degrades to training-data-only answers — defeating its purpose. VP-002 validates this assumption.
- **EA-003**: Task prompt injection mechanism — when the orchestrator calls `Task(subagent_type="correctless:cspec-research", prompt="...")`, the `prompt` parameter content is delivered to the agent alongside its static system prompt from the `.md` file. This is how the orchestrator injects dynamic per-invocation context (research topic, feature description) into the agent. Prior migrations (M-1 ctdd-red, M-2 ctdd-green, M-3 review-spec agents) all use this mechanism — the Task prompt parameter is the established pattern for orchestrator-to-agent context injection.

## Design Decisions
- **DD-001**: Separate agent file (not merged with review agents) — the research agent has a different tool set (WebSearch, WebFetch vs Read, Grep, Glob), different purpose (information gathering vs adversarial review), and different output format (structured brief vs finding list). Merging would obscure these distinctions.
- **DD-002**: No Glob in research agent tools — the agent searches the web and reads specific files, not local filesystem patterns. Glob is relevant for review agents scanning the codebase; the research agent doesn't need it.
- **DD-003**: WebSearch/WebFetch retained in cspec SKILL.md allowed-tools after migration — removing is a separate cleanup. The orchestrator's tool set is orthogonal to the agent's; the migration extracts the prompt without changing the parent skill's capabilities.
- **DD-004**: No shared preamble or drift guard needed — unlike M-3 (6 agents with identical preambles), M-4 has a single agent file. Preamble consistency enforcement (BND-002 in M-3) is unnecessary with one file.
- **DD-005**: Version Pins section preserved — the original inline prompt includes a "Version Pins" section in the structured brief format. The migration preserves all 7 sections (Current State, Key Findings, Recommended Patterns, Things to Avoid, Version Pins, Dependency Health, Open Questions). Dropping a section without justification would silently reduce research brief quality.
- **DD-006**: Task in allowed-tools is an accepted scope expansion — adding Task to cspec's allowed-tools enables spawning any Task-based sub-agent, not just the research agent. The SKILL.md prompt instructions constrain use to the research agent only, but the tool-level permission is broader. This matches the M-3 pattern (Task added to creview-spec's allowed-tools for 6 agents). The alternative (no Task, keep inline prompt) defeats the migration purpose.

## Verification Procedure
- **VP-001**: Agent structural smoke test — after creating the agent file, verify the file exists at `agents/cspec-research.md` with valid YAML frontmatter containing `name`, `description`, and `tools` fields. This is structurally identical to INV-001 and runs as part of the CI test suite.
- **VP-002**: Agent functional smoke test — after merge and sync.sh, invoke `Task(subagent_type="correctless:cspec-research")` in a fresh session with a test topic. Verify: (1) agent spawns successfully, (2) WebSearch and WebFetch are available and produce results, (3) Write/Edit/Bash are NOT available to the agent. Record evidence in `.correctless/verification/cspec-agent-migration-smoke.md`. This validates EA-002 (first-ever WebSearch/WebFetch in a plugin agent).

## Open Questions
- ~~**OQ-001**~~: Resolved — keep Dependency Health as a required section. "N/A" is a valid answer; missing section header is a structural test gap.
