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
