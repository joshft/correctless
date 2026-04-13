# Spec: Test Evasion Antipatterns

## Metadata
- **Task**: test-evasion-antipatterns
- **Status**: reviewed
- **Recommended-intensity**: standard
- **Intensity**: high
- **Intensity reason**: no signals fired; user raised to match project floor
- **Override**: raised

## What

Adds three antipatterns to the corpus based on Andrew's external dogfooding feedback from clawker. Each describes a distinct way agents satisfy surface-level test checks without doing real work: (1) test-routing around requirements, (2) hand-rolled permissive mocks, (3) phantom e2e execution. The test audit prompt in `/ctdd` is updated to explicitly check for these patterns. Scanner implementation is deferred to language-specific dogfooding (Go/Python/TypeScript).

## Rules

- **R-001** [unit]: `.correctless/antipatterns.md` must contain an AP-016 entry titled "Test-routing around requirements" with `**What went wrong**:`, `**How to catch it**:`, `**Frequency**:`, `**Scanner rule**:`, and `**Source**:` fields. The How-to-catch-it field must describe spec-rule-to-test-content matching: when a spec rule cites a specific endpoint/method/function/path, at least one test must contain that named resource.

- **R-002** [unit]: `.correctless/antipatterns.md` must contain an AP-017 entry titled "Hand-rolled permissive mocks" with `**What went wrong**:`, `**How to catch it**:`, `**Frequency**:`, `**Scanner rule**:`, and `**Source**:` fields. The How-to-catch-it field must describe mock-generator detection: flag mock struct/class definitions in test files that lack a corresponding generator directive (`go:generate`, `@patch(spec=)`, etc.).

- **R-003** [unit]: `.correctless/antipatterns.md` must contain an AP-018 entry titled "Phantom e2e execution" with `**What went wrong**:`, `**How to catch it**:`, `**Frequency**:`, `**Scanner rule**:`, and `**Source**:` fields. The How-to-catch-it field must describe execution evidence verification: integration tests must produce logs with real timestamps and command output, not just compilation success.

- **R-004** [integration]: The test audit prompt in `skills/ctdd/SKILL.md` (the "You are the test auditor" blockquote) must contain a numbered check `5.` whose text includes the anchor phrase "spec-named" (as in spec-named endpoints, spec-named paths, or spec-named resources). The check must instruct the auditor to verify tests exercise the specific resources named in the spec rules they claim to cover. Tests that cover auxiliary paths while avoiding spec-named resources are a BLOCKING finding.

- **R-005** [integration]: The test audit prompt must contain a numbered check `6.` whose text includes the anchor phrase "hand-rolled mock" or "hand-rolled stub". The check must instruct the auditor to flag tests with mock/stub definitions that lack a mock generator framework reference. Hand-rolled mocks that always return success are a BLOCKING finding.

- **R-006** [integration]: The test audit prompt must contain a numbered check `7.` whose text includes the anchor phrase "execution evidence". The check must instruct the auditor to flag integration-tagged tests that only verify compilation/existence without execution evidence (real timestamps, command output, test durations). This check is documentation-only for bash projects where tests inherently produce command output — it has value when Correctless runs on non-bash projects.

- **R-007** [unit]: Each new AP entry (AP-016, AP-017, AP-018) must include a `**Scanner rule**:` field describing the mechanical detection pattern in grep-compatible prose. The field must note "Implementation deferred to language-specific dogfooding" and reference the language-specific patterns (Go: `go:generate`, Python: `unittest.mock`, TypeScript: class stubs).

- **R-008** [unit]: Each new AP entry must include a `**Source**:` field citing "Andrew's clawker feedback, 2026-04-13" to trace the antipattern to its origin. The `**Frequency**:` field must use the format "0 findings in-project (external report, Andrew's clawker)" to distinguish external-reported from internal-observed patterns.

- **R-009** [unit]: A structural drift test must verify that each AP-016/017/018 entry in `antipatterns.md` has a corresponding numbered check (5/6/7) in the ctdd test audit prompt, and vice versa. Detection: grep antipatterns.md for AP-016/017/018 headings, grep ctdd SKILL.md for numbered checks 5/6/7, verify 1:1 correspondence. This prevents the dual-source-of-truth drift that AP-005 documents.

## Won't Do

- Scanner implementation for Go/Python/TypeScript — deferred to first dogfooding on those languages. Scanner rules become actionable during the first Go/Python/TS dogfooding feature. If no such feature ships within 6 months of this spec's merge date, revisit whether the rules should be dropped from the corpus entries.
- Synthetic test fixtures in non-bash languages — can't validate detection rules without real code
- Corpus entry schema standardization — separate concern; new fields (Scanner rule, Source) are additive and optional for existing entries
- Antipattern scanner code changes (`scripts/antipattern-scan.sh`)
- Generic deferred-items tracking mechanism (`.correctless/meta/deferred-items.md`) — valuable but separate from this spec

## Risks

- **Test audit prompt length**: Adding 3 checks increases the audit prompt. Mitigated by keeping each check to 2-3 sentences.

- **Detection rules untested until Go dogfooding**: Scanner rules are documented but not exercised. Accepted — the test audit prompt catches these patterns via LLM judgment today; scanner rules become mechanical enforcement during language-specific dogfooding.

- **R-004/005/006 are AP-003 territory (F-001)**: These rules test LLM prompt prose via keyword grep — the same pattern AP-003 warns against and PAT-012 governs. Mitigated by pinning to specific numbered checks (5/6/7) with mandatory anchor phrases ("spec-named", "hand-rolled mock", "execution evidence"), making accidental satisfaction much harder than free-floating keyword grep. Residual risk: the check text could appear in the right format but be ignored by the LLM auditor. This is accepted as inherent to prompt-based enforcement — structural enforcement comes via scanner rules when language-specific dogfooding begins.

- **R-006 vacuously true on bash (F-004)**: Bash tests inherently produce command output. The phantom e2e check is documentation-only for this project. The check has value when Correctless runs on non-bash projects where tests can compile without running. No rule change; scope honestly acknowledged.

## Open Questions

- ~~OQ-001~~: Resolved — no QA prompt change needed. QA agent reads antipatterns.md directly.
