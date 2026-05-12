# Spec: Migrate /ctdd GREEN Implementation Agent to Plugin Agent

## Metadata
- **Created**: 2026-05-11T18:00:00Z
- **Status**: approved
- **Impacts**: none
- **Branch**: feature/ctdd-green-agent-migration
- **Research**: null
- **Recommended-intensity**: high
- **Intensity**: high
- **Intensity reason**: project floor (workflow.intensity=high)
- **Override**: none

## Context

The `/ctdd` GREEN phase currently spawns a general-purpose `Task()` agent with an inline blockquoted prompt (AP-013 pattern). This agent inherits the parent harness's behavioral defaults, which shift between Claude model versions — notably, 4.7's "don't add validation for scenarios that can't happen" prior suppresses defensive guards the spec intends. The ctdd-red migration (M-1, 2026-04-26) proved that extracting to a dedicated plugin agent with a pinned tool allowlist and explicit behavioral overrides eliminates this drift class. This spec applies the same pattern to GREEN.

## Scope

**In scope:**
- Create `agents/ctdd-green.md` with frontmatter + system prompt
- Update `skills/ctdd/SKILL.md` GREEN phase to use `Task(subagent_type="correctless:ctdd-green")`
- Remove the inline blockquoted prompt from SKILL.md GREEN phase
- Update ABS-010 consumer list and write-permission parenthetical in `.correctless/ARCHITECTURE.md`
- Update `sync.sh` if needed to propagate the new agent file (note: sync.sh already globs `agents/*.md` — no change expected)
- Add `Task` to `/ctdd` skill frontmatter `allowed-tools`
- Update QA agent instructions to make `tdd-test-edits.log` review conditional on the log existing
- Update SKILL.md constraint line 847 to reflect the new test-edit prohibition policy
- Structural tests for the new agent file
- Update AGENT_CONTEXT.md, CONTRIBUTING.md, docs

**Out of scope:**
- Changing the workflow gate to block test edits during tdd-impl (DRIFT-003 — separate feature)
- Migrating the QA agent or mini-audit agents (future migration items)
- Changing the calm reset prompt logic (stays in SKILL.md as orchestrator behavior)
- Changing the GREEN phase workflow (phase gates, state transitions)

## Complexity Budget
- **Estimated LOC**: ~120 (agent file ~90, SKILL.md edits ~30)
- **Files touched**: ~8
- **New abstractions**: 0 (reuses ABS-010 plugin-agent contract)
- **Trust boundaries touched**: 1 (BND-002 introduces agent-to-orchestrator test-bug escalation data flow)
- **Risk surface delta**: low-medium

## Invariants

### INV-001: Agent file exists with correct frontmatter
- **Type**: must
- **Category**: functional
- **Statement**: `agents/ctdd-green.md` must exist with YAML frontmatter containing `name: ctdd-green`, `tools:` listing the pinned tool allowlist, and `model: inherit`.
- **Boundary**: ABS-010
- **Violated when**: the agent file is missing, the `name:` field doesn't match the filename basename, or the `model:` field is absent
- **Enforcement**: CI test assertion
- **Guards against**: null
- **Test approach**: unit
- **Risk**: low
- **Implemented in**: {filled during GREEN phase}

### INV-002: Tool allowlist pinned
- **Type**: must
- **Category**: functional
- **Statement**: `agents/ctdd-green.md` frontmatter `tools:` must be exactly `Read, Grep, Glob, Write, Edit, Bash` — same surface as ctdd-red. The agent needs Write/Edit for source files and Bash for running tests.
- **Boundary**: ABS-010
- **Violated when**: the tools list includes additional tools (e.g., Task, Agent) or omits required tools
- **Enforcement**: CI test assertion
- **Guards against**: null
- **Test approach**: unit
- **Risk**: low
- **Implemented in**: {filled during GREEN phase}

### INV-003: SKILL.md uses namespaced subagent_type
- **Type**: must
- **Category**: functional
- **Statement**: The GREEN phase section of `skills/ctdd/SKILL.md` must invoke the implementation agent via `Task(subagent_type="correctless:ctdd-green")`, not `Task(subagent_type="general-purpose")` or any other type.
- **Boundary**: ABS-010
- **Violated when**: SKILL.md GREEN phase uses a non-namespaced or wrong subagent_type
- **Enforcement**: CI test assertion
- **Guards against**: AP-013
- **Test approach**: unit
- **Risk**: medium
- **Implemented in**: {filled during GREEN phase}

### INV-004: No inline prompt in SKILL.md
- **Type**: must-not
- **Category**: functional
- **Statement**: The GREEN phase section of `skills/ctdd/SKILL.md` must not contain an inline blockquoted system prompt for the implementation agent. The agent's system prompt lives solely in `agents/ctdd-green.md`. SKILL.md may contain orchestrator instructions (calm reset prompt, context enforcement, phase transition) but not the agent's identity/behavioral prompt.
- **Boundary**: ABS-010
- **Violated when**: SKILL.md GREEN phase section (from `## Phase: GREEN` to `### GREEN Phase Calm Reset Prompt`) contains blockquoted lines (`> `) defining agent identity, behavioral rules, or tool restrictions — detected by presence of any of: "You are the implementation agent", "your job is to", "allowed-tools", "Log all test edits" as blockquoted text
- **Enforcement**: CI test assertion (multi-phrase denylist grep)
- **Guards against**: AP-013
- **Test approach**: unit
- **Risk**: medium
- **Implemented in**: {filled during GREEN phase}

### INV-005: Defensive code override
- **Type**: must
- **Category**: functional
- **Statement**: The agent prompt in `agents/ctdd-green.md` must explicitly override the harness prior that suppresses defensive code. The prompt must instruct the agent to write guards, validation, and error handling wherever the spec's rules/invariants require them — not to skip them because "they can't happen."
- **Boundary**: null
- **Violated when**: the agent prompt contains no explicit override of defensive-code suppression, or defers to the harness's "don't add validation for impossible scenarios" prior
- **Enforcement**: prompt-level (CI keyword-presence verification — grep for defensive-code instruction)
- **Guards against**: null
- **Test approach**: unit
- **Risk**: medium
- **Implemented in**: {filled during GREEN phase}

### INV-006: Test file edit prohibition
- **Type**: must-not
- **Category**: functional
- **Statement**: The agent prompt in `agents/ctdd-green.md` must contain an explicit prohibition against editing test files. The agent must not Write or Edit files matching the project's `patterns.test_file` pattern. If a test has a bug, the agent must stop and report the issue to the orchestrator rather than fixing the test itself.
- **Boundary**: null
- **Violated when**: the agent prompt allows test edits (even with logging), or lacks an explicit prohibition
- **Enforcement**: prompt-level (the workflow gate logs but does not block test edits during tdd-impl; DRIFT-003 proposes structural enforcement as a future feature)
- **Guards against**: null
- **Test approach**: unit
- **Risk**: medium
- **Implemented in**: {filled during GREEN phase}

### INV-007: Config-derived test command
- **Type**: must
- **Category**: functional
- **Statement**: The agent prompt must instruct the agent to read `commands.test` from `.correctless/config/workflow-config.json` and use that command to run tests, rather than enumerating test runners (npm test, go test, pytest, etc.).
- **Boundary**: TB-001a (commands.test is eval'd config — agent invokes via Bash tool, not eval, so sandboxed)
- **Violated when**: the agent prompt hardcodes or enumerates test runner commands instead of referencing workflow-config.json
- **Enforcement**: prompt-level (CI keyword-presence verification — grep for `commands.test` reference)
- **Guards against**: null
- **Test approach**: unit
- **Risk**: low
- **Implemented in**: {filled during GREEN phase}

### INV-008: Distribution parity
- **Type**: must
- **Category**: data-integrity
- **Statement**: `agents/ctdd-green.md` and `correctless/agents/ctdd-green.md` must be byte-equal after `sync.sh` runs.
- **Boundary**: ABS-010
- **Violated when**: the source and distribution copies diverge
- **Enforcement**: CI test assertion (sync.sh --check)
- **Guards against**: null
- **Test approach**: unit
- **Risk**: low
- **Implemented in**: {filled during GREEN phase}

### INV-009: ABS-010 consumer list and write-permission updated
- **Type**: must
- **Category**: functional
- **Statement**: The ABS-010 entry in `.correctless/ARCHITECTURE.md` must list `skills/ctdd/SKILL.md` GREEN phase (ctdd-green) as a consumer, alongside the existing ctdd-red entry. The write-tool permission parenthetical must also be updated to name ctdd-green alongside ctdd-red (e.g., "ctdd-red writes test files, ctdd-green writes source files").
- **Boundary**: ABS-010
- **Violated when**: ABS-010's consumer list does not reference ctdd-green, or the write-tool permission example does not name ctdd-green as a write-permitted agent
- **Enforcement**: CI test assertion
- **Guards against**: AP-005
- **Test approach**: unit
- **Risk**: low
- **Implemented in**: {filled during GREEN phase}

## Prohibitions

### PRH-001: No inline agent prompt
- **Statement**: The GREEN phase section of `skills/ctdd/SKILL.md` must not contain a blockquoted system prompt defining the implementation agent's identity or behavioral rules. Per ABS-010 / AP-013, agent prompts live in `agents/*.md`.
- **Detection**: grep SKILL.md GREEN phase section for blockquoted agent-identity patterns
- **Consequence**: dual source of truth — prompt drift between SKILL.md and agent file causes inconsistent behavior

### PRH-002: No test runner enumeration in agent prompt
- **Statement**: The agent prompt must not enumerate specific test runners (npm test, go test, pytest, cargo test, etc.). It must reference `commands.test` from workflow-config.json exclusively.
- **Detection**: grep agent file for known test runner command strings
- **Consequence**: test command breaks on projects using different runners; violates config-driven convention

## Boundary Conditions

### BND-001: Calm reset prompt stays in SKILL.md
- **Boundary**: orchestrator vs agent responsibility
- **Input from**: orchestrator's failure tracking (consecutive failure count)
- **Validation required**: the calm reset prompt is orchestrator behavior (it fires at the orchestrator's discretion based on retry count), not agent self-regulation. It must remain in SKILL.md and be appended to the agent's prompt by the orchestrator, not baked into the agent file. The orchestrator passes the calm reset via the `prompt` parameter of `Task()`, which supplements (does not replace) the agent's system prompt — same mechanism used by ctdd-red, where dynamic context (spec path, architecture pointers, test patterns) is passed via `prompt` without overwriting the agent file's behavioral overrides.
- **Failure mode**: if the calm reset is in the agent file, it fires on every invocation instead of only after 3 failures. If Task(prompt=...) replaced rather than supplemented the agent system prompt, the calm reset would overwrite INV-005/INV-006 on retry — losing behavioral overrides when the agent is struggling most.

### BND-002: Test edit bug escalation
- **Boundary**: agent vs orchestrator responsibility (new agent-to-orchestrator data flow — the agent reads test files, which may contain adversarial content, and produces a report the orchestrator acts on)
- **Input from**: agent encounters a test with a bug during implementation
- **Validation required**: the agent must report the test bug to the orchestrator using a structured format: `TEST_BUG: {test_file}:{line} — {description}`. The orchestrator must: (1) detect the TEST_BUG sentinel in the agent's output, (2) surface the test bug details to the user with actionable options (re-run test audit, fix manually, override), (3) in `/cauto` pipeline context, treat as `escalation_deferred: true` and surface in the end-of-pipeline summary. The orchestrator must not blindly apply the agent's suggested fix (the agent could misidentify a correct test as buggy).
- **Failure mode**: fail-closed — agent stops and reports rather than silently editing tests. Without the structured format, the orchestrator treats the stop as a generic failure, retries 3 times, hits calm reset, and escalates with "I'm stuck" — never surfacing that the root cause is a test bug.

### BND-003: Agent file scope — what goes in vs stays in SKILL.md
- **Boundary**: agent system prompt vs orchestrator instructions
- **Input from**: feature design
- **Validation required**: the agent file contains the agent's identity, behavioral overrides, input/output contract, and prohibitions. SKILL.md retains orchestrator-level concerns: calm reset prompt, phase transitions, context enforcement, commit metadata, /simplify invocation, antipattern scan.
- **Failure mode**: if orchestrator concerns leak into the agent file, they execute on every invocation regardless of orchestrator state

## Breaking Changes

### BC-001: Test-edit policy changes from allow-with-logging to prohibit-with-escalation
The current GREEN phase inline prompt (SKILL.md line 284) explicitly allows test edits with logging and a 3-option user approval flow (Approve/Reject/Modify). INV-006 prohibits test edits entirely and replaces the flow with a structured escalation (BND-002: `TEST_BUG` report to orchestrator). This is a behavioral change, not a migration detail. Downstream impacts:
- `.correctless/artifacts/tdd-test-edits.log` can never be written during GREEN post-migration. The QA agent's instruction to review this log (SKILL.md line 392) must become conditional on the log existing.
- The SKILL.md constraint at line 847 ("Test edits during GREEN are logged, not blocked") must be updated to reflect the new prohibition policy.
- The workflow gate (line 538-543) continues to log test edits during tdd-impl as a safety net — if the prompt-level prohibition fails, the gate still captures evidence. This infrastructure remains active intentionally.
- `/cauto` pipeline behavior changes: test bugs become pipeline stalls (agent stops with TEST_BUG report) instead of logged edits with autonomous approval. The `/cauto` autonomous skill contract handles this via `escalation_deferred: true` with test bug details surfaced in the end-of-pipeline summary.

## Environment Assumptions

- **EA-001**: Claude Code resolves `Task(subagent_type="correctless:ctdd-green")` to `agents/ctdd-green.md` via the plugin agent mechanism — refs ABS-010 — consequence if wrong: agent invocation fails silently, falling back to general-purpose. Per ENV-007, plugin-agent file discovery requires plugin reinstall AND a Claude Code session restart — mid-session edits to `agents/*.md` are NOT visible to the current session's Task tool. Users upgrading to this version must restart their Claude Code session for the GREEN agent to resolve.

## Verification Procedures

### VP-001: Agent discoverability smoke test
After creating `agents/ctdd-green.md` and running `sync.sh`, verify that the agent is resolvable by confirming: (1) `correctless/agents/ctdd-green.md` exists and is byte-equal to the source (INV-008), (2) the frontmatter `name:` field matches the `subagent_type` basename `ctdd-green` (INV-001), (3) after a plugin reinstall + session restart, `Task(subagent_type="correctless:ctdd-green")` does not fall back to general-purpose. Step (3) is a manual verification — the agent's output should include behavioral markers from the agent prompt (e.g., the defensive-code override instruction or the test-edit prohibition) that a general-purpose agent would not produce.

## Open Questions

- ~~**OQ-001**~~: RESOLVED — DRIFT-003 deferred. Prompt-level prohibition (INV-006) is the speedbump for this feature. DRIFT-003 (structural enforcement via workflow gate) changes hook behavior, not agent behavior — different scope, independently testable and revertable.
