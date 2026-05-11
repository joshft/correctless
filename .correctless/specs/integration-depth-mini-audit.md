# Spec: Integration Depth Mini-Audit Lens

## Metadata
- **Created**: 2026-05-10T15:00:00Z
- **Status**: draft
- **Impacts**: ctdd
- **Branch**: feature/integration-depth-mini-audit-lens
- **Research**: null
- **Recommended-intensity**: high
- **Intensity**: high
- **Intensity reason**: file path pattern signal (skills/ctdd/SKILL.md), project floor is high (workflow.intensity = high)
- **Override**: none

## Context

LLMs silently downgrade integration tests to unit-shaped work. The mechanical test audit (checks 5-10) catches structural violations — wrong imports, missing entrypoints, hand-rolled mocks. But subtler downgrades pass the mechanical checks: a test that imports the entrypoint but immediately stubs the middleware chain, or a test that satisfies the Entry contract but mocks everything listed in Through. This lens adds a semantic adversarial review that operates on execution evidence — not just code shape, but proof that Through components actually fired.

## Scope

**Covers**: Adding a 6th mini-audit agent to `/ctdd`'s tdd-audit phase that semantically reviews `[integration]` tests against their Entry/Through/Exit contracts, verifying execution evidence for each Through component.

**Does NOT cover**: Changes to `/creview-spec`, `/creview`, or `/caudit`. Changes to the test audit (checks 1-10). Changes to how contracts are written in `/cspec`. New antipattern entries (AP-016/017/018 already exist).

## Complexity Budget
- **Estimated LOC**: ~80-100 (agent prompt addition + progress/token updates)
- **Files touched**: ~3-4 (skills/ctdd/SKILL.md, tests/test-integration-depth-lens.sh, possibly .correctless/AGENT_CONTEXT.md)
- **New abstractions**: 0
- **Trust boundaries touched**: 0
- **Risk surface delta**: low

## Invariants

### INV-001: Agent prompt exists and fires on [integration] tests with contracts
- **Type**: must
- **Category**: functional
- **Statement**: The integration depth agent prompt must instruct the agent to: (1) read the spec and identify `[integration]` rules with Entry/Through/Exit contracts, (2) correlate rules to test files using R-xxx identifiers in test function names, rule ID comments in test blocks, or file naming conventions (e.g., `test_r003_*`), (3) for each Through component verify the test contains assertions that would fail if that component were removed or stubbed. The correlation mechanism must be explicitly stated in the prompt — the agent should use the mechanical R-xxx mapping, not attempt semantic inference of which tests cover which rules.
- **Boundary**: N/A
- **Violated when**: The agent prompt does not reference Entry/Through/Exit contracts, does not include correlation guidance, or does not instruct verification of execution evidence for Through components
- **Guards against**: null
- **Test approach**: unit (keyword-presence in SKILL.md for correlation mechanism and contract references)
- **Risk**: medium
- **Enforcement**: prompt-level (inherent to agent-prompt specs — same as all other mini-audit lenses)

### INV-002: Execution evidence requirement
- **Type**: must
- **Category**: functional
- **Statement**: The agent must check for execution evidence that Through components actually ran — not just that they were imported or wired. Evidence includes: assertions on Through-component side effects (auth returns 401 on bad token, logger wrote entry, config value appears in response), Through-component error path assertions (proving the component can fail and the test observes it), or Through-component state changes (database row created through the real ORM, not hand-inserted).
- **Boundary**: N/A
- **Violated when**: The agent prompt only checks for import/wiring of Through components without requiring observable proof of execution
- **Guards against**: AP-016, AP-017, AP-018
- **Test approach**: unit (keyword-presence in SKILL.md for execution evidence terminology)
- **Risk**: high
- **Enforcement**: prompt-level

### INV-003: Contracts-only scope with advisory fallback
- **Type**: must
- **Category**: functional
- **Statement**: The agent operates in BLOCKING mode only on `[integration]` tests that have Entry/Through/Exit contracts. For `[integration]` tests without contracts, the agent emits exactly one ADVISORY finding: "R-xxx is [integration] without Entry/Through/Exit — integration depth not auditable. Consider adding a contract via /cspec."
- **Boundary**: N/A
- **Violated when**: The agent attempts semantic analysis of tests without contracts, or emits BLOCKING findings for uncontracted tests, or silently skips uncontracted tests without the advisory
- **Guards against**: null
- **Test approach**: unit (keyword-presence for advisory language and contracts-only scope instruction)
- **Risk**: medium
- **Enforcement**: prompt-level

### INV-004: Through-component checklist approach
- **Type**: must
- **Category**: functional
- **Statement**: For each Through component listed in the contract's "must NOT be mocked" list, the agent must verify at least one test assertion that would fail if that specific component were replaced with a no-op stub. The agent reports per-component: which Through components have execution evidence and which do not.
- **Boundary**: N/A
- **Violated when**: The agent gives a blanket pass/fail on the entire Through field rather than evaluating each component individually
- **Guards against**: null
- **Test approach**: unit (keyword-presence for per-component evaluation language)
- **Risk**: medium
- **Enforcement**: prompt-level

### INV-005: LENS enum value is `integration-depth`
- **Type**: must
- **Category**: functional
- **Statement**: The integration depth agent uses `LENS: integration-depth` in its findings. The LENS enum line in the finding format section of ctdd SKILL.md includes `integration-depth` as a valid value.
- **Boundary**: N/A
- **Violated when**: The LENS value is missing from the enum, or the agent uses a different LENS value
- **Guards against**: null
- **Test approach**: unit (grep for `integration-depth` in LENS enum line)
- **Risk**: low
- **Enforcement**: structural (grep-verifiable in test)

### INV-006: Agent count cascading updates
- **Type**: must
- **Category**: functional
- **Statement**: All references to mini-audit agent count in ctdd SKILL.md must be updated from 5 to 6. Specific strings to update: (1) "spawning 5 specialist agents" → "spawning 6 specialist agents" in progress announcement, (2) "five specialist agents" → "six specialist agents" in the phase description, (3) "five agents" → "six agents" in the zero-findings section ("all five agents in a round"), (4) the `agent_role` token tracking value list must include `integration-depth`, (5) the LENS enum in the finding format must include `integration-depth`.
- **Boundary**: N/A
- **Violated when**: Any text in ctdd SKILL.md still says "5 specialist agents" or "five agents" or lists only 5 agents/lenses after this feature lands
- **Guards against**: AP-005
- **Test approach**: unit (grep for each specific string)
- **Risk**: low
- **Enforcement**: structural (grep-verifiable in test)

### INV-007: Severity calibration included
- **Type**: must
- **Category**: functional
- **Statement**: The agent prompt includes calibration examples specific to integration depth — concrete instances of what constitutes BLOCKING vs ADVISORY. BLOCKING examples: "test imports httptest.NewServer but stubs AuthMiddleware via test double — Through contract says auth middleware must NOT be mocked", "test satisfies Entry but no assertion would fail if ConfigService were a no-op." ADVISORY examples: "test mocks an external HTTP API (not in Through list) — acceptable isolation."
- **Boundary**: N/A
- **Violated when**: The agent prompt has no calibration examples, or uses generic calibration from the shared section without integration-depth-specific instances
- **Guards against**: AP-028 (uncalibrated severity gate — PMB-007)
- **Test approach**: unit (keyword-presence for calibration example markers)
- **Risk**: high
- **Enforcement**: prompt-level

### INV-008: Fail-open on no contracts
- **Type**: must
- **Category**: functional
- **Statement**: When no `[integration]` rules in the spec have Entry/Through/Exit contracts, the agent completes with zero findings and notes: "No integration contracts found — integration depth lens has nothing to audit." The round proceeds normally with findings from the other 5 agents.
- **Boundary**: N/A
- **Violated when**: The agent blocks progression or errors when no contracts exist
- **Guards against**: null
- **Test approach**: unit (keyword-presence for graceful-degradation language)
- **Risk**: low
- **Enforcement**: prompt-level

## Prohibitions

### PRH-001: Must not duplicate mechanical checks
- **Statement**: The integration depth agent must NOT re-check what the test audit already verifies mechanically (Entry grep, internal import bypass, hand-rolled mock detection). It operates at the semantic layer — execution evidence — not the structural layer.
- **Detection**: review of agent prompt for overlap with test audit checks 5-10
- **Consequence**: Duplicate findings confuse the user and waste review time on already-caught issues

### PRH-002: Must not require test execution
- **Statement**: The agent must NOT run tests or require access to test output logs from the current run. It operates on test source code and spec contracts only. Execution evidence is inferred from assertion patterns in the test code (e.g., "asserts 401 status" proves auth middleware would need to fire), not from actual test run output.
- **Detection**: agent prompt must not reference running tests or reading test output files
- **Consequence**: Mini-audit agents are read-only; running tests would violate the tool allowlist and add unpredictable latency

## Boundary Conditions

### BND-001: Mixed contracted and uncontracted integration rules
- **Boundary**: spec contains both `[integration]` rules with and without contracts
- **Input from**: spec file
- **Validation required**: agent must process contracted rules with full depth and emit one advisory per uncontracted rule
- **Failure mode**: fail-open (uncontracted rules get advisory, not silence)

### BND-002: Empty Through field
- **Boundary**: an `[integration]` rule has Entry and Exit but Through says "no mock restrictions" or is empty
- **Input from**: spec file
- **Validation required**: agent notes "R-xxx has empty Through — no mock restrictions to verify" and moves on
- **Failure mode**: fail-open (no findings emittable without a Through checklist)

### BND-003: Language-agnostic assertion detection
- **Boundary**: test files may be in any language
- **Input from**: test source code
- **Validation required**: the agent uses semantic reasoning to identify assertions, not language-specific pattern matching. The prompt must instruct: "Look for assertions, expects, asserts, should-statements, or any test framework construct that would fail if the Through component produced no output or different output."
- **Failure mode**: fail-open (if the agent cannot determine whether evidence exists for a language it doesn't recognize, it reports UNCERTAIN, not BLOCKING)

### BND-004: Non-decomposable Through field
- **Boundary**: a Through field uses a collective description ("full middleware chain", "entire request pipeline") rather than enumerating individual components
- **Input from**: spec file
- **Validation required**: agent emits ADVISORY: "R-xxx Through field is non-decomposable — cannot verify per-component execution evidence. Consider decomposing via /cspec to name each middleware individually." The agent does NOT attempt to infer individual components from a collective description.
- **Failure mode**: fail-open (ADVISORY, not BLOCKING — the contract is valid but not auditable at component granularity)

## Review Findings Applied

- **F-001** (MEDIUM): Added BND-004 for non-decomposable Through fields. Through may be "full middleware chain" without enumerating components — INV-004's per-component checklist can't operate on it. Advisory + decomposition suggestion is the fallback.
- **F-002** (LOW): Added explicit string enumeration to INV-006 (see updated invariant).
- **F-003** (LOW): Added test-to-rule correlation guidance to INV-001 (see updated invariant).

## Open Questions

None — the brainstorm resolved the scope (contracts-only with advisory), the evidence approach (assertion-inferred, not runtime), and the boundary with existing checks (semantic layer above mechanical checks 5-10).
