# Antipatterns — correctless

Every item is a bug class caught by QA or audit.
The /cspec and /creview skills check new features against this list.

## How to Add an Entry

When a bug is found (pre-merge by QA, or post-merge by /cpostmortem):
1. Create a new AP-xxx entry (increment the last number)
2. "What went wrong" — describe the bug class as a concrete story
3. "How to catch it" — write the spec rule or test that prevents recurrence
4. "Frequency" — how many features this class appeared in

## Entries

### AP-001: GNU grep extensions in POSIX scripts
- **What went wrong**: Scripts used `grep -P` (Perl regex), `\b` (word boundary), or `\s` (whitespace class) which are GNU extensions. On macOS (BSD grep), these silently fail or produce wrong results. In ci-hook-wiring, `grep -oP` for HOOK_TYPE/HOOK_MATCHER silently returned nothing on macOS — zero hooks registered.
- **How to catch it**: Use `sed -n 's/pattern/replacement/p'` or `grep -E` with POSIX ERE only. Add a CI check that flags `grep -P` in any .sh file. Spec rule: "All grep patterns must use POSIX ERE (`-E`) or basic regex only — no `-P`, `\b`, `\s`."
- **Frequency**: 5 findings across 2 features (antipattern-scan, ci-hook-wiring)

### AP-002: Silent failure in conditional update paths
- **What went wrong**: Code has an update path guarded by a presence check, but the check passes while the update is unreachable. In ci-hook-wiring, `grep -qF` found the hook path in settings.json (in `permissions.allow`), so `needs_update` stayed false, and the matcher drift correction code never ran. In consolidate, the migration updated hook paths but left matchers narrow — no convergence mechanism.
- **How to catch it**: Integration test that: (1) creates the initial state, (2) changes a value that should trigger an update, (3) re-runs the function, (4) verifies the value was actually updated. Spec rule: "Every update path must have a test that exercises it with pre-existing state, not just fresh state."
- **Frequency**: 7 findings across 4 features (consolidate, ci-hook-wiring, statusline, mcp-integration)

### AP-003: Keyword-presence tests instead of wiring tests
- **What went wrong**: Tests grep for keywords in skill files ("check mcp.serena", "find_symbol fallback") but don't verify that the wiring actually works. A skill could contain the right words in a comment and pass the test without implementing the behavior. In cexplain, the skill file was missing the required "optimizer not dependency" statement — the keyword test didn't catch it because it was checking the wrong file.
- **How to catch it**: For integration rules, test the actual behavior path — not keyword presence. If keyword-presence is the only feasible approach (LLM skill files), test multiple required elements together and verify they appear in the right section. Spec rule: "Tests tagged `[integration]` must exercise the real system path, not grep for keywords."
- **Frequency**: 6 findings across 4 features (cexplain, intensity-detection, shift-left, ci-hook-wiring)

### AP-004: Migration/update creates partial state
- **What went wrong**: Setup's migration path handles some components but not others, leaving the system in a partial state. In consolidate, the migration moved hooks and updated paths but didn't update the matcher — old narrow matchers persisted. In statusline, re-running setup duplicated hook entries because the "already exists" check was too narrow. In mcp-integration, partial MCP configuration left one server configured and the other missing.
- **How to catch it**: Integration test that runs setup twice — once to create, once to update. Verify the second run produces identical output to the first (idempotency). Test with partial pre-existing state (some hooks present, some missing). Spec rule: "Every migration/update function must be tested with at least 3 initial states: clean, partial, and full."
- **Frequency**: 7 findings across 4 features (consolidate, mcp-integration, ci-hook-wiring, statusline)

### AP-005: Stale documentation after refactoring
- **What went wrong**: Code was refactored but documentation (AGENT_CONTEXT.md, ARCHITECTURE.md, CONTRIBUTING.md, README.md) still describes the old structure. In merge-lite-full, 3 docs still referenced the deleted "correctless-lite/correctless-full" split after the merge. Agents reading stale docs make wrong assumptions.
- **How to catch it**: Grep all .md files for terms that should have been replaced during the refactoring. Add a test that verifies no documentation references deleted files/directories. Spec rule: "Every refactoring that renames or deletes components must include a doc-update invariant."
- **Frequency**: 6 findings across 4 features (merge-lite-full, consolidate, antipattern-scan, crelease)

### AP-006: Section-unaware config parsing
- **What went wrong**: Parsing reads a value from a structured file (TOML, YAML, JSON) without constraining which section it appears in. In crelease, `version =` was matched at any position in Cargo.toml, not just under `[package]`. In intensity-detection, config paths were ambiguous between root-level and nested positions.
- **How to catch it**: Use a proper parser (jq for JSON, yq for YAML) or anchor grep patterns to section context. Test with files that have the target value in multiple sections — only the correct section should match. Spec rule: "Config value extraction must be section-aware. Test with a file where the value appears in both the correct and incorrect sections."
- **Frequency**: 3 findings across 3 features (crelease, intensity-detection, antipattern-scan)

### AP-007: Test accidentally passes for wrong reason
- **What went wrong**: A test passes but not because the feature works — it passes due to leaked state from a prior test, empty input triggering a fast-path, or post-condition checks that are satisfied by default. In ci-hook-wiring, `setup_test_env` was undefined — the test ran against leaked state from INV-009 and all 4 assertions passed accidentally. In hook-sync, the PostToolUse test passed because FILES was empty (fast-path exit 0), not because the source guard worked.
- **How to catch it**: Every test function must initialize its own state (call setup_test_project or equivalent). Assert preconditions before postconditions. Use `set -u` to catch undefined variables. Spec rule: "Every integration test must create isolated state — never rely on state from prior tests."
- **Frequency**: 3 findings across 3 features (ci-hook-wiring, hook-sync, infrastructure-hardening)

### AP-008: Spec specifies file writes without verifying allowed-tools
- **What went wrong**: A spec requires a skill to write to a file path, but the skill's `allowed-tools` frontmatter doesn't include `Write()` permission for that path. The feature is dead on arrival — the skill can't perform the write it's instructed to do. In intensity-calibration, cverify was instructed to write calibration entries but lacked `Write(.correctless/meta/intensity-calibration.json)`. In auto-recurring-patterns, cpostmortem was instructed to write promoted entries to ARCHITECTURE.md but lacked `Write(.correctless/ARCHITECTURE.md)`.
- **How to catch it**: During /creview-spec, for every file write mentioned in the spec, verify the target skill's `allowed-tools` frontmatter includes a matching `Write()` entry. Spec rule: "Every spec that instructs a skill to write to a file path must verify the skill's allowed-tools includes that path. Missing permission is a BLOCKING review finding."
- **Frequency**: 2 findings across 2 features (intensity-calibration, auto-recurring-patterns)

### AP-009: Spec references artifact by slug without specifying slug convention
- **What went wrong**: A spec references an artifact file path using a slug (e.g., `token-log-{slug}.jsonl`) without specifying which slug convention to use. The project has two: `branch_slug` (derived from branch name with `/` → `-` and MD5 hash suffix) and `task_slug` (the task description from workflow init). These produce different values — `feature-token-aware-intensity-a1b2c3` vs `token-aware-intensity`. In token-aware-intensity, the spec originally said "token-log-{slug}.jsonl" without specifying branch_slug, risking the implementer using task_slug and failing to find the file the hook writes.
- **How to catch it**: During /creview-spec, for every artifact path containing `{slug}`, verify the spec explicitly states which slug convention is used (branch_slug or task_slug) and that it matches the convention used by the producer of that artifact. Spec rule: "Every artifact path with a slug placeholder must specify the slug convention. Mismatched conventions are a BLOCKING review finding."
- **Frequency**: 1 finding across 1 feature (token-aware-intensity)

### AP-010: String interpolation of user input into jq filter strings
- **What went wrong**: User-supplied values (e.g., `$reason` from `workflow-advance.sh override "reason"`) were embedded directly in jq filter strings via bash double-quote interpolation (`\"$reason\"`). Values containing double quotes or backslashes break the jq filter syntax, causing the command to fail. This is the same class as direct SQL parameter interpolation. In the QA Olympics audit (2026-04-09), `cmd_spec_update` and `cmd_override` were converted to `locked_update_state` but used string interpolation instead of `--arg`, reintroducing a bug class that was already fixed once (QA-007, 2026-04-03).
- **How to catch it**: Use `jq --arg key "$value"` and reference `$key` inside the filter. Never use `\"$value\"` in a jq filter string. Static check: grep for `\\"\\$` inside `locked_update_state` call arguments. Spec rule: "All jq filters with user-controlled values must use `--arg`/`--argjson`, never string interpolation."
- **Frequency**: 2 findings across 1 feature (qa-audit-2026-04-09 R2→R3)

### AP-011: Tooling version drift between local dev and CI
- **What went wrong**: Local dev used jq 1.8.1 (Arch Linux rolling), CI uses jq 1.7.1 (Ubuntu 24.04 default). jq 1.8 silently fixed operator precedence for `as $var` bindings after arithmetic — in 1.7, `(.spec_updates // 0) + 1 as $count | rest` parses as `0 + (1 as $count | rest)` yielding a `number + object` runtime error; in 1.8, it parses as `((.spec_updates // 0) + 1) as $count | rest` and works. All 2,948 tests passed locally; CI failed. Two CI cycles wasted before root cause identified. See PMB-001.
- **How to catch it**: (1) CI matrix across jq 1.6 / 1.7.1 / 1.8 — run the test suite on each; (2) static grep for risky `as $var` patterns — any `)[+\-*/%] .* as \$` or `// [^|]+ as \$` without explicit outer parens is suspect; (3) PAT-010 in ARCHITECTURE.md documents the parenthesization rule. Spec rule: "Every feature that adds or modifies a jq filter must be tested against the CI jq version (or the filter must be version-agnostic per PAT-010)."
- **Frequency**: 1 finding across 1 feature (qa-audit-2026-04-09 CI failure)

### AP-012: Fix rounds in audit/QA loops are untested code
- **What went wrong**: The QA Olympics audit (2026-04-09) ran 3 convergence rounds. Each round introduced new regressions: R1's 19 fixes caused 3 R2 regressions; R2's 7 fixes caused 1 R3 regression; R3's 1 fix caused the jq 1.7 CI failure. Each fix commit was treated as "closing the finding" without being subjected to TDD-level scrutiny. The orchestrator batched all fixes per round into one commit without per-fix verification, bypassing the discipline that the main workflow enforces on feature code. The audit's divergence calm reset fires only when finding counts increase, missing the "each round adds ~1 regression per fix batch" pattern. See PMB-002.
- **How to catch it**: Update `/caudit` skill: (1) after each fix round commit, MUST run the full test suite (`commands.test` from workflow-config) before advancing to next round — test failures become blocking findings; (2) MUST spawn a dedicated "fix-diff review" subagent scoped to the fix commit diff before spawning next round's specialists — the agent's sole job is to find new bugs introduced by the fix commits; (3) blocking fix-review findings are added to the current round immediately (not deferred to respawning all specialists, which is expensive). Spec rule: "Every audit fix round must pass the full test suite and a diff-scoped review before the orchestrator advances to the next round."
- **Frequency**: 1 finding across 1 feature (qa-audit-2026-04-09)
- **Status**: Structurally enforced as of 2026-04-11 via `agents/fix-diff-reviewer.md` + `skills/caudit/SKILL.md` step 6a. The inline prompt that originally described this fix is now an invocable plugin agent with pinned tool allowlist `{Read, Grep, Glob}`, UNTRUSTED_DIFF/UNTRUSTED_RULES fences, `jq -e .` parse gate, and PRH-003 canonical fail-closed marker (cardinality = 1). VP-001 + VP-002 pre-merge verification against the three historical fixture diffs confirmed the real plugin agent catches each regression layer. See `.correctless/specs/fix-diff-reviewer-migration.md`.

### AP-013: Inline subagent system prompts in skill files
- **What went wrong**: `/caudit`'s original step 6a defined a fix-diff reviewer as prose inside `skills/caudit/SKILL.md` — "You are the fix-diff reviewer..." as a blockquoted system prompt. The prose was not actually invocable because caudit had no `Task()` call and `Task` was absent from its `allowed-tools` frontmatter. The block was a documentation aspiration, not a structural guarantee. This compounds three existing antipattern classes: AP-008 (spec specifies tool use without verifying allowed-tools), AP-005 (dual source of truth — prose in one file, any real implementation in another), and AP-003 (keyword-presence: grep for the reviewer prose would find it and declare it implemented).
- **How to catch it**: (1) Any subagent described in a skill file MUST have a corresponding `Task(subagent_type=...)` invocation inside the skill body AND a matching entry in the skill's `allowed-tools:` frontmatter. (2) Subagent system prompts live in `agents/{name}.md`, never inline in `skills/*/SKILL.md` — this is ABS-010 in `.correctless/ARCHITECTURE.md`. (3) Structural test: grep `skills/*/SKILL.md` for distinctive subagent-prompt phrases (e.g., "You are the", "Your sole job is") in contexts that aren't the skill's own framing prose — any match without a matching `Task()` call is a violation. See `tests/test-fix-diff-reviewer-agent.sh` `check_inv006` and `check_prh001` for the canonical detection pattern.
- **Frequency**: 1 feature (fix-diff-reviewer-migration, resolved 2026-04-11)

### AP-014: `jq -s` (slurp mode) on JSONL files
- **What went wrong**: `budget_get_token_usage()` and `report_generate()` used `jq -s` to parse JSONL token logs. `jq -s` requires every line to be valid JSON — a single malformed line (truncated write, concurrent append, disk error) causes the entire parse to fail with exit 5, returning 0 tokens. This silently disables budget enforcement (INV-008). The failure is invisible: no error message, no crash, just incorrect data. ABS-006 explicitly requires "Consumers must handle malformed lines (skip, not fail)." The existing token-tracking consumer in cverify used the correct pattern (`jq -R 'try(fromjson)...'`), but the Phase 2 code used the wrong pattern. This is the same class as PMB-001 (jq version drift causing silent failure).
- **How to catch it**: (1) Static scan: `antipattern-scan.sh` detects `jq -s` or `jq --slurp` usage on `.jsonl` files or in scripts that parse JSONL. (2) Convention: JSONL consumers must use `jq -R 'try (fromjson | .field // default) catch default'` — never `jq -s`. (3) ABS-006 in ARCHITECTURE.md documents the consumer contract. Spec rule: "Every JSONL consumer must use `jq -R` with try/catch, never `jq -s`."
- **Frequency**: 2 findings in 1 feature (auto-mode-phase-2, QA-001)

### AP-015: Workflow state writer without advisory lock
- **What went wrong**: `workflow-state-ext.sh` wrote to the workflow state file via `jq ... > tmp && mv tmp state.json` without acquiring the advisory lock from `scripts/lib.sh`. ABS-003 requires all state file modifications to go through locked paths (`write_state()` or `locked_update_state()`). Concurrent operations (hook-driven state writes + manual CLI invocations) could corrupt the state file via interleaved reads and writes. The script header explicitly said "No sourcing of lib.sh" as a design choice, not realizing lib.sh provides the mandatory locking.
- **How to catch it**: (1) Static test: `test-lib-locking.sh` verifies every script that writes to `workflow-state-*.json` files references `_acquire_state_lock`. (2) Convention: any script that modifies a `workflow-state-*.json` file must source `scripts/lib.sh` and use the lock functions. (3) Code review: new scripts touching state files are flagged for lock usage.
- **Frequency**: 1 finding in 1 feature (auto-mode-phase-2, QA-002)

### AP-016: Test-routing around requirements
- **What went wrong**: Agent writes tests for an unauthenticated `/healthz` endpoint instead of the authenticated endpoints that actually need mocks. Tests pass, coverage numbers look good, but the auth path — the one the spec rule actually cites — is completely untested. The agent chose the path of least test resistance, routing around the hard requirement to cover an easy auxiliary path instead.
- **How to catch it**: When a spec rule cites a specific endpoint, method, function, or path (a spec-named resource), the test audit must verify at least one test contains that spec-named resource. Tests that cover auxiliary or simpler paths while avoiding the spec-named path are a BLOCKING finding — the agent is routing around the requirement, not satisfying it.
- **Frequency**: 0 findings in-project (external report, Andrew's clawker)
- **Scanner rule**: Detect test-routing by cross-referencing spec rules with test content. For each spec rule that names a specific endpoint, path, or method, verify at least one test file references that endpoint/path/method. Implementation deferred to language-specific dogfooding. Detection patterns vary by language: route definitions in Go (`http.HandleFunc`), Python (`@app.route`), TypeScript (`app.get`/`router.post`).
- **Source**: Andrew's clawker feedback, 2026-04-13

### AP-017: Hand-rolled permissive mocks
- **What went wrong**: Agent creates mock structs and stub classes from scratch that always return true or success values. No failure mode is ever exercised because the hand-rolled mock has no interface contract — it literally cannot fail. The mock makes the test pass without testing anything meaningful, because the real dependency's failure modes are invisible.
- **How to catch it**: Flag mock struct or class definitions in test files that lack a corresponding mock generator or mock framework directive. Hand-rolled mocks that return success by default without referencing a mock generator framework (e.g., `go:generate mockgen`, `unittest.mock.patch(spec=)`, `jest.mock`) are a BLOCKING finding when generated alternatives exist for the language. Generated mocks enforce the interface contract; hand-rolled mocks can silently drift.
- **Frequency**: 0 findings in-project (external report, Andrew's clawker)
- **Scanner rule**: Detect hand-rolled mocks by scanning test files for mock/stub struct or class definitions without a nearby generator directive. Language-specific patterns: Go (`go:generate mockgen`, `moq`), Python (`unittest.mock`, `@patch(spec=)`), TypeScript/JavaScript (`jest.mock`, `vi.mock`). Flag test files that define mock types without any of these directives. Implementation deferred to language-specific dogfooding.
- **Source**: Andrew's clawker feedback, 2026-04-13

### AP-018: Phantom e2e execution
- **What went wrong**: Agent rationalizes skipping e2e tests ("requires docker, not in scope") or writes an integration test that only compiles without actually running against real dependencies. The test file exists, the import compiles, but the test was never executed with real services. A `TestIntegration` function that calls `t.Skip("requires docker")` on every CI run provides zero confidence.
- **How to catch it**: Integration and e2e tests must produce execution evidence: logs with real timestamps progressing through test steps, actual command output from stderr/stdout, and reasonable test durations. Compilation-only is not execution. A test that only verifies imports or type-checks without producing timestamps and command output is a BLOCKING finding.
- **Frequency**: 0 findings in-project (external report, Andrew's clawker)
- **Scanner rule**: Detect phantom execution by checking for execution evidence in test output. Look for timestamp progression, execution log entries, actual test output with durations, and docker/service startup logs for integration-tagged tests. Flag tests that contain `t.Skip`, `@pytest.mark.skip`, or `xit(`/`describe(` in integration/e2e suites. Implementation deferred to language-specific dogfooding.
- **Source**: Andrew's clawker feedback, 2026-04-13
