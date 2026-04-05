# Verification: Auto-Format PostToolUse Hooks

## Rule Coverage

| Rule | Test | Status | Notes |
|------|------|--------|-------|
| INV-001 | test_inv001 (7 tool types) | covered | Edit/Write/MultiEdit trigger, Read/Bash/Grep/Glob skip |
| INV-002 | test_inv002 + test_inv002_multiedit | covered | Single file + MultiEdit multi-file |
| INV-003 | test_inv003 (3 scenarios) | covered | Missing formatter, crash, timeout |
| INV-004a | test_inv004a | covered | Stderr notification on success |
| INV-004b | test_inv004b (2 scenarios) | covered | Silent on unmatched extension, disabled |
| INV-005 | test_inv005 | covered | Missing binary graceful exit |
| INV-006 | test_inv006 | covered | .ts→prettier, .py→black, cross-check |
| INV-007 | test_inv007 | covered | Custom formatter from config |
| INV-008 | (doc audit — SKIP) | deferred | csetup SKILL.md changes not yet written |
| INV-009 | (doc audit — SKIP) | deferred | csetup SKILL.md changes not yet written |
| INV-010 | test_inv010 (3 states) | covered | enabled=false, absent, true |
| INV-011 | test_inv011 + QA class fixes | covered | Exact-match allowlist + metacharacter rejection |
| PRH-001 | implicit via INV-002 | covered | Formatter receives single file path |
| PRH-002 | implicit via INV-003 | covered | Always exits 0 |
| PRH-003 | implicit via INV-004b/INV-006 | covered | Extension matching gates eligibility |
| PRH-004 | test_prh004 (6 patterns) | covered | No eval, no unquoted vars, no backtick exec |
| BND-001 | test_bnd001 (3 scenarios) | covered | Spaces, $() injection, backtick injection |
| BND-002 | test_bnd002 | covered | Missing file → exit 0 |
| BND-003 | test_bnd003 | covered | Missing config → exit 0 |
| BND-004 | (documentation only) | N/A | Sequential execution assumption documented |

## QA Class Fixes Verified

| QA Finding | Class Fix | Status |
|------------|-----------|--------|
| QA-001: Missing allowlist | test_qa001 — non-allowlisted command rejected | verified |
| QA-002: Multi-word commands | test_qa002 — npx prettier multi-word works | verified |
| QA-003: & metacharacter | test_qa003 — ampersand rejected | verified |
| QA-NEW-001: npx arbitrary bypass | test_qa_new001 — npx malware rejected | verified |
| QA-NEW-002: Path-prefix bypass | test_qa_new002 — /usr/local/bin/prettier rejected | verified |

## Dependencies

No new dependencies introduced. The hook uses only bash builtins, jq (already required), and timeout (coreutils).

## Architecture Compliance

- Follows existing hook conventions (bulk eval+jq, bash builtins, exit 0 always)
- Performance patterns from perf audit applied (no subshells in loops, single command -v)
- Separate concern from workflow-gate.sh (formatting vs phase gating)
- Config stored in workflow-config.json auto_format section (no new config files)

## Smells

None found. No TODO/FIXME/HACK comments, no debug statements, no hardcoded values.

## Drift

- INV-008/INV-009: csetup SKILL.md changes deferred — will be part of /cdocs phase
- No implementation drift from spec rules

## Spec Updates

- 1 spec update during review: added INV-011 (allowlist), PRH-004 (no eval), BND-004 (concurrency)
- H-1 design decision: hook auto-adds --write/-w flags for prettier/gofmt (not in original spec, added during QA R3)

## Test Results

70 passed, 0 failed across all auto-format tests.
61 passed, 0 failed on existing test suite (no regressions).

## Overall: PASS — 18/20 rules covered, 2 deferred (doc audit for csetup changes), 0 findings
