# Spec: Spec Mutation Alerts — Detect Spec Changes After Review Approval

## Metadata
- **Task**: spec-mutation-alerts
- **Recommended-intensity**: standard
- **Intensity**: high
- **Intensity reason**: project floor (workflow.intensity=high); no security signals triggered
- **Override**: none

## What

Hash the spec file when the workflow advances past review (review/review-spec → tdd-tests). Check the hash when the workflow advances to `done` (TDD complete). If the spec was modified between review approval and TDD completion, emit a warning — the implementation may have been built against a modified spec that bypasses the review pipeline's assumptions. Same pattern as intent summary hash (Phase 2 INV-013, scripts/intent-hash.sh) but applied to the spec file.

## Rules

- **R-001** [unit]: When `workflow-advance.sh tests` transitions from `review`/`review-spec` to `tdd-tests`, it computes the SHA-256 hash of the spec file (using `sha256_hash_file` from lib.sh) and writes it to the workflow state file as `spec_hash`. The spec file path is read from the state file's `spec_file` field.
- **R-002** [unit]: When `workflow-advance.sh done` transitions to the `done` phase, it re-hashes the spec file and compares against the stored `spec_hash`. If the hashes match, the transition proceeds silently. If they differ, the transition still proceeds but emits a prominent warning: "WARNING: Spec file was modified after review approval. {N} lines changed. The implementation may not match the reviewed spec. Consider re-running /creview-spec." The warning includes the line count delta (`wc -l` difference or `diff --stat` summary).
- **R-003** [unit]: The `spec-update` flow (spec modified during TDD via `/ctdd` spec-update) updates `spec_hash` in the workflow state file after the spec is modified. This ensures that spec-updates triggered through the legitimate workflow path do not produce false-positive warnings at `done` transition. Detection: when `workflow-advance.sh spec-update` is called, it re-hashes and updates `spec_hash`.
- **R-004** [unit]: If the spec file does not exist at hash-check time (deleted between review and done), the check emits a warning: "WARNING: Spec file not found at {path}. Cannot verify spec integrity." The transition proceeds — this is a warning, not a blocker.
- **R-005** [unit]: The `spec_hash` field is only written by `workflow-advance.sh` (consistent with PAT-004 — workflow-advance.sh is the sole state writer). No other script or skill writes `spec_hash`.

## Won't Do

- **Blocking on spec mutation** — the warning is advisory, not a gate. Blocking would break legitimate workflows where a user edits a spec comment or fixes a typo during TDD. The warning surfaces the risk; the human decides whether to act.
- **Diff content in the warning** — showing what changed in the spec would require embedding diff output in a warning message. The line count delta is sufficient to signal scope of change; the user can run `git diff` themselves.
- **Hashing at every phase transition** — only hash at review→tdd-tests (capture) and at done (verify). Intermediate transitions (tdd-impl, tdd-qa) don't check because the spec is expected to be stable during TDD, and checking at every transition adds noise.
- **Hash verification in /cverify** — /cverify already reads the spec and checks drift. Adding hash verification there would duplicate the done-transition check. The workflow-advance.sh check is the authoritative gate.

## Risks

- **Legitimate spec edits produce warnings**: A user fixes a typo in the spec during TDD. The warning fires at `done`. This is by design — the user sees the warning, recognizes it's a typo fix, and proceeds. The warning is advisory, not blocking.
  1. Accept (recommended) — false-positive warnings on typo fixes are acceptable. The alternative (ignoring all spec changes) is worse.

- **spec-update race with manual edits**: A user manually edits the spec AND /ctdd triggers a spec-update. R-003 updates the hash after spec-update, but the manual edit happened before. The hash reflects the spec-update version, not the manual edit. The warning may or may not fire depending on edit order. Accepted — this is an edge case with no clean solution short of version-controlled spec history.
  1. Accept (recommended) — edge case, manual edits during TDD are already unusual.

## Open Questions

- ~~**OQ-001**~~: Resolved — warning, not blocker. Advisory approach matches intent-hash pattern.
