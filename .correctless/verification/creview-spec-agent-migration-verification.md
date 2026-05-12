# Verification: Migrate /creview-spec Adversarial Agents to Plugin Agent Files

## Rule Coverage
| Rule | Test | Status | Notes |
|------|------|--------|-------|
| INV-001 | check_inv001 (exist/fm/name/desc/tools × 6) | covered | All 6 agent files exist with valid YAML frontmatter, name matches basename, description non-empty, tools present |
| INV-002 | check_inv002 (exact/count/deny × 6) | covered | Tools exactly {Read, Grep, Glob} for all 6 agents; Write/Edit/Bash/Task denied |
| INV-003 | check_inv003 (per-agent + no-general) | covered | SKILL.md dispatches via subagent_type="correctless:{name}" for all 6; no general-purpose in Step 1 |
| INV-004 | check_inv004 (no-inline + block-1..6) | covered | No blockquoted agent identity patterns; no large blockquoted prompt blocks in agent sections 1-6 |
| INV-005 | check_inv005 (3 fixed refs + spec-path × 6) | covered | Each agent references AGENT_CONTEXT.md, ARCHITECTURE.md, antipatterns.md, and spec path placeholder |
| INV-006 | check_inv006 (AND-logic keywords × 6) | covered | Each agent contains its unique lens keywords (red-team: attack paths AND bypass vectors, etc.) |
| INV-007 | check_inv007 (byte-equal × 6) | covered | Source agents/ and distribution correctless/agents/ are byte-equal for all 6 |
| INV-008 | check_inv008 (6 agents + test-ref) | covered | ABS-010 in ARCHITECTURE.md lists all 6 agents plus test-creview-spec-agents reference |
| INV-009 | check_inv009 | covered | /creview-spec allowed-tools includes Task |
| INV-010 | check_inv010 (skill + denylist × 6) | covered | SKILL.md contains intensity refs; no agent contains intensity conditionals, spawn/select, or count-gating |
| INV-011 | check_inv011 (per-agent phrase × 6) | covered | Each agent contains its required exhaustive-output phrase (harness-prior suppression) |
| INV-012 | check_inv012 (format + markdown × 6) | covered | Each agent specifies output format with category/finding reference and markdown list format |
| PRH-001 | check_prh001 (6 signatures) | covered | No inline agent prompts remain in SKILL.md Step 1 for any of the 6 migrated agents |
| PRH-002 | check_prh002 (deny Write/Edit/Bash/Task × 6) | covered | No write-capable tools in any review-spec agent |
| BND-001 | check_bnd001 (× 6) | covered | No orchestrator logic (checkpoint/synthesis/spawn/workflow-advance) in any agent file |
| BND-002 | check_bnd002 (sha256 preamble drift) | covered | All 6 agent preambles are byte-equal (sha256 hash comparison) |

All 12 invariants, 2 prohibitions, and 2 boundary conditions have dedicated tests. 194 test assertions, all passing.

Additional structural checks beyond spec rules:
- VP-001: Agent name matches filename basename for all 6 agents
- WIRING: test-creview-spec-agents registered in both tests/test.sh and workflow-config.json
- SYNC: sync.sh uses agents/*.md glob (covers review-spec agents automatically)

## Dependencies
- No new dependencies introduced. No changes to package.json, go.mod, Cargo.toml, requirements.txt, or pyproject.toml.

## Architecture Adherence

- ABS-010: valid — consumer list updated with creview-spec/SKILL.md Step 1 (6 agents), invariant updated listing all 6 as read-only roles, Test line includes `tests/test-creview-spec-agents.sh`. All enforcement paths verified on disk.

1 entry checked, 0 stale, 0 drift-debt items related to this feature.

## Full Test Suite
73 tests passed, 0 failed (including all pre-existing tests plus the new 194-assertion creview-spec-agents test).
