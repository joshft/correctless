# Fix-Diff Reviewer Historical Commits Fixture

These committed diff files reproduce the PMB-002 fix-round commits from the
2026-04-09 QA Olympics audit. They are rescued from the author's local reflog
because PR #47 squash-merged all three rounds into one commit, leaving the
original SHAs unreachable from `origin/main`. Committed diff content preserves
reproducibility of VP-002 (the functional-equivalence replay in
`.correctless/specs/fix-diff-reviewer-migration.md`).

## Provenance

- **R1**: SHA `9d61920` — "fix(qa-r1): Round 1 audit fixes — 19 findings across 9 files"
  - Date: 2026-04-09
  - Regression layer: R1's 19 fixes introduced 3 R2 regressions (primarily in
    token-tracking and workflow-advance state handling) that round 2 then had to
    catch and repair.
  - File: `fix-diff-reviewer-historical-r1.diff`
  - Pinned hash: r1 sha256 2b0a181c78f08790a7b67e0ad15439ca3739094dac41c5aeb4db352c7c0dc3cb

- **R2**: SHA `2824387` — "fix(qa-r2): Round 2 audit fixes — 7 findings, 3 regressions from R1"
  - Date: 2026-04-09
  - Regression layer: R2's 7 fixes introduced 1 R3 regression (locked_update_state
    --arg passthrough lost a quoting safety check) that round 3 then repaired.
  - File: `fix-diff-reviewer-historical-r2.diff`
  - Pinned hash: r2 sha256 f33569ffcb25b46be31a9eee9c3791e13c3eed80840e7e07b2941f9ea1d57906

- **R3**: SHA `6c0d919` — "fix(qa-r3): Extend locked_update_state for safe --arg passthrough"
  - Date: 2026-04-09
  - Regression layer: R3's single fix did not introduce a PMB-002 regression at
    runtime, but it surfaced a jq 1.7 / 1.8 precedence bug on CI (adjacent to
    PMB-001, not PMB-002 proper).
  - File: `fix-diff-reviewer-historical-r3.diff`
  - Pinned hash: r3 sha256 37975aac77b66e9fecf950cf6e0d89d65969dc65ed99f7915a554365dda80e5a

## SHA reconciliation note

The spec's `EA-004` records a discrepancy: `workflow-effectiveness.json:11` names
R3 as `6b8e821`, but `6b8e821` is actually a post-R3 CI fix belonging to PMB-001
("cmd_spec_update filter precedence issue in jq 1.7"), not PMB-002's R3. The
PMB-002 R3 is `6c0d919`. This fixture uses the correct `6c0d919`. Future audits
of `.correctless/meta/workflow-effectiveness.json` should correct this field.

## Tamper-evidence

The pinned SHA-256 values above are checked by
`tests/test-fix-diff-reviewer-agent.sh` (`check_bnd003`). Tampering with any
`.diff` file invalidates its pinned hash and fails the test. Tampering with a
pinned hash requires also tampering with the diff content — both tamper paths
are visible in git history.
