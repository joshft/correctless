# Verification Report: cspec-agent-migration

## Metadata
- **Feature**: Migrate /cspec Research Agent to Plugin Agent File (M-4)
- **Branch**: feature/cspec-agent-migration
- **Spec**: .correctless/specs/cspec-agent-migration.md
- **Verified**: 2026-05-12
- **Phase at verification**: done
- **Intensity**: high
- **Test suite**: 74/74 passed, 0 failed
- **Feature-specific tests**: 57/57 passed (test-cspec-research-agent.sh)

## Invariant Verification

| INV | Status | Evidence |
|-----|--------|----------|
| INV-001 | PASS | `agents/cspec-research.md` exists with valid YAML frontmatter: `name: cspec-research`, non-empty `description`, non-empty `tools` |
| INV-002 | PASS | Tools field is exactly `WebSearch, WebFetch, Read, Grep` (4 tools, no Write/Edit/Bash/Task) |
| INV-003 | PASS | SKILL.md Step 2 contains `subagent_type="correctless:cspec-research"`; no `general-purpose` reference |
| INV-004 | PASS | No denylist signatures ("You are a research agent...", "Produce a structured brief", "Search for:") in SKILL.md Step 2; no stale "(forked context)" annotation; no large blockquoted prompt blocks |
| INV-005 | PASS | Agent file contains `{topic}`, `{feature_description}` placeholders and `AGENT_CONTEXT.md` reference |
| INV-006 | PASS | Agent file contains "Current official documentation" and "Dependency Health" |
| INV-007 | PASS | Agent file contains "BE SKEPTICAL" directive |
| INV-008 | PASS | All 7 output format sections present: Current State, Key Findings, Recommended Patterns, Things to Avoid, Version Pins, Dependency Health, Open Questions |
| INV-009 | PASS | `agents/cspec-research.md` and `correctless/agents/cspec-research.md` are byte-equal; `sync.sh --check` clean |
| INV-010 | PASS | ABS-010 in ARCHITECTURE.md lists cspec-research, references `skills/cspec/SKILL.md` as consumer, distinguishes network-read tool class, references `test-cspec-research-agent.sh` |
| INV-011 | PASS | `/cspec` SKILL.md `allowed-tools` includes `Task` |
| INV-012 | PASS | SKILL.md Step 2 retains orchestrator spawn logic ("Spawn the research subagent when"); agent file does not contain orchestrator denylist patterns ("research signals", "Spawn the research subagent when", "Inferred signals") |
| INV-013 | PASS | AGENT_CONTEXT.md agents table lists cspec-research with consumer `skills/cspec/SKILL.md` and network-read tool class |
| INV-014 | PASS | Agent file contains "do not summarize" and "exhaustive" harness-prior suppression phrases |
| INV-015 | PASS | Agent file contains "advisory and untrusted" data-treatment directive; SKILL.md Step 2 contains "advisory and untrusted" near research brief consumption |
| INV-016 | PASS | Agent file contains "DO NOT substitute training data" network unavailability self-diagnostic directive |

## Prohibition Verification

| PRH | Status | Evidence |
|-----|--------|----------|
| PRH-001 | PASS | No inline blockquoted research agent prompt in SKILL.md Step 2 |
| PRH-002 | PASS | Agent tools field does not include Write, Edit, Bash, or Task |

## Boundary Condition Verification

| BND | Status | Evidence |
|-----|--------|----------|
| BND-001 | PASS | Agent file contains only research instructions and behavioral directives; orchestrator logic (signal detection, conditional spawn) remains in SKILL.md |

## Additional Checks

| Check | Status | Evidence |
|-------|--------|----------|
| VP-001 | PASS | Frontmatter `name: cspec-research` matches filename basename `cspec-research` |
| WIRING | PASS | `test-cspec-research-agent.sh` registered in both `tests/test.sh` and `workflow-config.json` |
| SYNC | PASS | `sync.sh` uses `agents/*.md` glob; `sync.sh --check` reports clean |
| SKILL-FM | PASS | `/cspec` `allowed-tools` includes `Task` |

## Architecture Compliance

- **ABS-010 updated**: cspec-research listed in agent registry with consumer mapping to `skills/cspec/SKILL.md`
- **Network-read class**: New tool class (WebSearch, WebFetch, Read, Grep) documented alongside existing write-tools and local-read-only classes
- **AGENT_CONTEXT.md**: Agents table updated with cspec-research entry including network-read class annotation

## Summary

All 16 invariants, 2 prohibitions, and 1 boundary condition pass. The full test suite (74/74 tests) passes with 0 failures, including 57 feature-specific structural tests covering every spec requirement. Distribution parity is clean. No outstanding issues.

## VP-002 Note

VP-002 (agent functional smoke test — first-ever WebSearch/WebFetch in a plugin agent) is a post-merge validation. It requires invoking the research agent in a fresh session to verify WebSearch and WebFetch tool availability. This is deferred to after merge per the spec's verification procedure.
