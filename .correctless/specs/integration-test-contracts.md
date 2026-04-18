# Spec: Integration Test Contracts in Specs

## Metadata
- **Task**: integration-test-contracts
- **Recommended-intensity**: high
- **Intensity**: high
- **Intensity reason**: file path signal (skills/); project floor is high
- **Override**: none
- **Review findings**: 8 findings from adversarial review (self-assessment + 4 agents), all accepted

## What

When `/cspec` writes a rule tagged `[integration]`, it must also define Entry/Through/Exit constraints that tell the TDD agent exactly what the integration test must exercise. Entry says which entrypoint to use. Through says which components must be exercised and which must NOT be mocked. Exit says what observable behavior must hold. These constraints are derived from `.correctless/ARCHITECTURE.md` entrypoints YAML — if no entrypoints exist, `/cspec` prompts the user to run `/carchitect` first. The test audit in `/ctdd` mechanically verifies that integration tests satisfy their contracts.

## Rules

- **R-001** [unit]: Prerequisite: update ABS-023 in `.correctless/ARCHITECTURE.md` to list `/cspec` as a consumer (reads entrypoints, matches scope globs, uses `test_via` for Entry derivation) and `/ctdd` as a transitive consumer (test audit verifies Entry fields derived from `test_via`). Add to "Violated when": "the `test_via` or `scope` fields are removed or renamed without updating cspec's contract derivation logic." Prerequisite: add ABS-024 documenting the Entry/Through/Exit contract format as a cross-skill data contract. Writer: `/cspec`. Consumer: `/ctdd` test auditor. Invariant: the three fields and their verification tiers (Entry=mechanical, Through=semi-mechanical, Exit=semantic) are stable; adding a field is additive, changing a verification tier is an architectural decision. Prerequisite: strengthen ABS-023's evolution constraint to include: "Existing field semantics (not just names) are stable. The `scope` field remains a list of glob patterns; changing its type or matching semantics is a breaking change requiring a new field." The `/cspec` skill file (`skills/cspec/SKILL.md`) adds a new step between rule drafting and antipattern checking: "For each rule tagged `[integration]`, define the integration test contract." This step runs after the rules are drafted (Step 3) and before antipatterns (Step 5). For each `[integration]` rule, the spec agent appends an Entry/Through/Exit block:
  ```
  - **R-003** [integration]: Config values reach the runtime handler
    Entry: httptest.NewServer(handler) — real server, real middleware chain
    Through: request passes through auth middleware and config-injection middleware
    Exit: response body contains the config-sourced value; no mock of ConfigService
  ```
  The three fields are:
  - **Entry**: which entrypoint the test must use (derived from ARCHITECTURE.md `test_via` field for the matching entrypoint)
  - **Through**: which components must be exercised on the real path, and which must NOT be mocked
  - **Exit**: what observable behavior must hold at the end of the test

- **R-002** [unit]: The Entry field for each integration test contract is derived from the ARCHITECTURE.md entrypoints YAML. The spec agent reads the entrypoints (via `scripts/extract-entrypoints.sh` or by reading the fenced YAML directly), matches each `[integration]` rule to an entrypoint whose `scope` globs overlap with the rule's affected files, and uses that entrypoint's `test_via` field as the Entry value. The spec agent infers affected files from the rule's description text, the feature scope in the spec's What section, and files referenced by other rules in the same spec. This is LLM judgment, not mechanical matching — the human confirms or corrects during spec review. If a rule's scope matches exactly one entrypoint, use it. If no entrypoint matches, the spec agent flags it: "No matching entrypoint for R-xxx — the Entry field is unresolved. Consider adding an entrypoint via `/carchitect`." If a rule's scope spans multiple entrypoints (e.g., a rule like "audit logging captures all mutations regardless of entry path" touches HTTP, CLI, and queue entrypoints), the spec agent splits the rule into one `[integration]` rule per entrypoint, each with its own Entry/Through/Exit contract sharing the same Exit constraint. A rule that spans three entrypoints becomes three rules with three focused tests — not one rule trying to cover three paths. The spec agent presents the split to the human: "R-003 spans 3 entrypoints — splitting into R-003, R-004, R-005 with separate contracts. Same Exit constraint for all three." Subsequent rules are renumbered. Split rules use sequential IDs (the standard R-NNN format), not suffixed IDs — no new naming convention. A comment on each split rule notes the original: "(split from original R-003 — HTTP path)" so the lineage is traceable without a new format.

- **R-003** [unit]: Before writing integration test contracts, the spec agent checks whether `.correctless/ARCHITECTURE.md` exists and contains entrypoints (the `correctless:entrypoints:start` / `correctless:entrypoints:end` markers exist and the block is non-empty). If the file does not exist or no entrypoints exist, the spec agent tells the user: "ARCHITECTURE.md has no entrypoints defined. Integration test contracts require entrypoints to derive Entry fields. Run `/carchitect` to define them, or skip integration contracts for this spec." If the user chooses to skip, `[integration]` rules are written without Entry/Through/Exit blocks — the existing behavior. The spec agent does NOT attempt to infer entrypoints from the codebase during spec writing.

- **R-004** [unit]: The Through field specifies two things: (a) components that MUST be exercised (the real path the request takes), and (b) components that must NOT be mocked. The "must not mock" list is the critical constraint — it tells the TDD agent what it's not allowed to fake. The cspec skill file contains the phrases "must NOT be mocked" and "must be exercised" (or semantically equivalent) in the integration contract instructions. The spec agent derives the Through field from the rule's description text, the feature scope, and the entrypoint's scope — this is LLM judgment, and the human confirms or corrects during spec review.

- **R-005** [unit]: The Exit field specifies observable behavior, not implementation details. The cspec skill file includes explicit guidance with at least one positive example (observable assertion, e.g., "response body contains X") and one negative example (implementation-detail assertion, e.g., "Function Y was called" — testing implementation, not behavior). The Exit field must be expressible as a test assertion without accessing internal state.

- **R-006** [unit]: Rules tagged `[unit]` do NOT get Entry/Through/Exit blocks. The contract format applies only to `[integration]` rules. Unit rules continue to be written as they are today — a testable statement with no test-shape constraints.

- **R-007** [integration]: The `/ctdd` test audit (`skills/ctdd/SKILL.md`, "Between RED and GREEN: Test Audit" section) adds a new check: for each `[integration]` rule that has an Entry/Through/Exit contract, verify the test satisfies the contract. The three checks operate at different verification tiers:

  | Check | Type | Severity | What it verifies |
  |-------|------|----------|-----------------|
  | Entry | Mechanical | BLOCKING | Test file contains evidence of using the specified entrypoint (e.g., `httptest.NewServer` if Entry says so). A grep can verify this. |
  | Through | Semi-mechanical | BLOCKING or UNCERTAIN | Test does NOT mock/stub components on the "must not mock" list. Language-dependent (Go interface mocks differ from Jest mocks). If the auditor can mechanically confirm a violation: BLOCKING. If the mock pattern is unfamiliar or ambiguous: UNCERTAIN — flag for human review, do not gate. |
  | Exit | Semantic | BLOCKING (definite mismatch) or ADVISORY (uncertain) | Test contains assertions matching the Exit constraint's observable behavior. If the auditor can positively determine the assertion doesn't match (e.g., Exit says "response body contains X" but no assertion references the response body at all): BLOCKING. If the auditor is uncertain whether the assertion satisfies the constraint (e.g., assertion references the response body but checks a different field): ADVISORY. The "definitely wrong" bar must be high — only flag BLOCKING when there is zero overlap between assertion targets and Exit requirements. |

  For `[integration]` rules without contracts (e.g., entrypoints were unavailable per R-003), the test audit notes: "R-xxx has no integration contract — test shape not audited" so the user knows the gap exists.

  Note: these checks verify test *shape* (which entrypoint is used, which components are not mocked, what assertions target), not test *behavior*. This is complementary to PAT-012 (wiring tests over keyword tests), not in conflict — PAT-012 governs what the test exercises at runtime, R-007 governs what the test is structurally allowed to fake.

- **R-008** [unit]: Each integration test contract is framed as a discrete, bounded task for the TDD agent. The test agent's prompt in `/ctdd` is updated to include: "For rules with Entry/Through/Exit contracts, treat each contract as a self-contained task. The Entry tells you where to start. Through tells you what path to exercise and what you cannot mock. Exit tells you what must be true at the end. Write one test per contract that satisfies all three constraints. If you cannot satisfy a constraint, say so explicitly — do not silently downgrade by mocking a prohibited component or testing through a different entry point. If a contract's Entry or Through constraint seems wrong (e.g., the Through constraint prohibits mocking a component you genuinely need to mock for the test to run), flag it as a finding rather than silently complying and producing a bad test. A wrong constraint is a spec issue, not a test issue — raise it so the human can fix the spec." Note: the test agent flagging a contract defect is escalation to the human (TB-004 boundary), not the test agent overriding the auditor (which would violate TB-005).

- **R-009** [unit]: The spec template files (`templates/spec-lite.md` and `templates/spec-full.md`) are updated. The `[integration]` entry in the test level guide now includes the Entry/Through/Exit format as an example. The standard-intensity template shows the format inline with the rule. The high-intensity template uses the same format within the invariant structure.

- **R-010** [unit]: Documentation is updated: `docs/skills/cspec.md` documents the integration test contract format. `docs/skills/ctdd.md` documents the test audit's contract verification check. CONTRIBUTING.md and README.md test/assertion counts are updated (or the AP-005 drift test catches it). AGENT_CONTEXT.md is updated to reference integration test contracts as a design pattern.

## Won't Do

- **Generating test code in the spec** — the spec defines constraints (Entry/Through/Exit), not test implementations. The TDD agent writes the actual test.
- **Enforcing contracts without entrypoints** — if ARCHITECTURE.md has no entrypoints, integration contracts are skipped. No fallback heuristics.
- **Changing the `[unit]` rule format** — unit rules are unaffected. Only `[integration]` rules get contracts.
- **Modifying `/cverify`** — verification checks rule coverage, not test contract satisfaction. The test audit (in `/ctdd`) is the enforcement point.
- **Language-specific contract templates** — the Entry/Through/Exit format is language-agnostic. Language-specific patterns (httptest vs supertest vs pytest) come from the entrypoint's `test_via` field, which is already language-specific by design.

## Risks

- **Spec agent writes bad contracts**: The spec agent derives Entry/Through/Exit from entrypoints and rule descriptions. If the entrypoints are wrong or the derivation is poor, the contracts are wrong. The TDD agent follows them faithfully and produces tests that look correct but don't exercise the real path.
  1. Accept — the spec review is the gate. The human reviews Entry/Through/Exit constraints alongside the rules. This is strictly better than the current state (no constraints at all), even if some contracts are imperfect. Bad contracts are visible and fixable; silent downgrades are invisible.

- **Contract format adds noise to small specs**: A 3-rule spec where one rule is `[integration]` now has a multi-line Entry/Through/Exit block that doubles the rule's visual weight.
  1. Accept — integration rules are the ones that matter most and historically fail most. The extra weight is proportional to the risk. A 3-line contract that prevents a bad integration test is worth the visual cost.

- **Test audit becomes too strict**: The mechanical checks may produce false positives — e.g., a Through check greps for a mock of a prohibited component and matches an unrelated variable name, or an Exit check can't confirm a semantically valid assertion.
  1. Mitigate (recommended) — R-007 splits verification into three tiers with graduated severity. Entry is mechanical and BLOCKING. Through is semi-mechanical — BLOCKING when the auditor can confirm a violation, UNCERTAIN when the mock pattern is ambiguous. Exit is semantic — BLOCKING only for definite mismatches (no assertion targets the right resource at all), ADVISORY for uncertainty. This prevents false-positive gates on judgment calls while still catching definite violations.

- **Entrypoint-to-rule matching is imprecise**: The spec agent matches rules to entrypoints by scope glob overlap. If scopes are broad (e.g., `**/*.go`), every rule matches every entrypoint, and the Entry field is meaningless.
  1. Mitigate (recommended) — R-002 says "pick the most specific (narrowest scope)" and flag unresolved matches. Broad scopes produce warnings, not silent failures. The fix is better entrypoint scopes in ARCHITECTURE.md (a `/carchitect` quality issue, not a spec issue).

## Open Questions

- **OQ-001**: Should the Through field explicitly list components that CAN be mocked (safe to fake), or only components that must NOT be mocked? Listing safe-to-mock components is more permissive but also more verbose. **Tentative answer**: only list must-not-mock. The TDD agent can mock anything not on the prohibition list. This is simpler and puts the burden on the spec to name the critical real-path components.

- **OQ-002**: Should the test audit's contract verification (R-007) run at all intensities or only at high+? At standard intensity, the test audit is already blocking. Adding contract verification doesn't change the cost — it's one more check in the same audit pass. **Tentative answer**: all intensities, since the check is cheap and the value is intensity-independent (a bad integration test at standard intensity is just as harmful as at high intensity).

- **OQ-003**: ~~Should the UNCERTAIN severity apply to contract verification?~~ **Resolved**: R-007 now includes UNCERTAIN for Through checks (when mock pattern is ambiguous) and Exit checks (when assertion intent is unclear). The test auditor's severity vocabulary is extended by this spec for contract verification specifically. The broader question of UNCERTAIN for all test audit findings (not just contract checks) remains deferred alongside OQ-004 from the mini-audit spec.
