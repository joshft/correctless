---
name: PAT-017 — canonicalize_path security invariants
description: Pure-bash path normalizer for the sensitive-file-guard pre-match pipeline. Total over arbitrary byte sequences; no fork/exec; no shell expansion.
paths: [scripts/lib.sh]
---

# PAT-017: canonicalize_path security invariants

## Rule

`canonicalize_path` in `scripts/lib.sh` is a pure-bash segment-stack walker that
normalizes a path string into the canonical form the sensitive-file-guard
pre-match pipeline compares against. Every code change to `scripts/lib.sh`
must preserve every invariant below.

### Mandatory contracts

1. **Totality (INV-001).** Every input — including empty, whitespace-only,
   glob-character-containing, traversal-sequence-containing, and arbitrary
   byte sequences — produces a single line of stdout, exit code 0, within the
   performance bound. The function never hangs, never errors, never produces
   multi-line output.

2. **No empty output on non-empty input (INV-001a).** For any non-empty,
   non-whitespace-only input, `canonicalize_path` MUST NOT emit empty stdout.
   Empty output on non-empty input is a silent fail-open variant of the
   PreToolUse fail-open class (HP-3 in PAT-001).

3. **Output shape (INV-002).** Output never contains `//`, never contains a
   `/./` or `/..` segment on absolute output, and never has a trailing `/`
   except when the entire output is exactly `/`.

4. **ASCII-only dot recognition (INV-002a).** Only the literal byte 0x2E
   (ASCII `.`) is a path-segment dot. Unicode lookalikes — U+2024 ONE DOT
   LEADER, U+FF0E FULLWIDTH FULL STOP, U+2026 HORIZONTAL ELLIPSIS — pass
   through as ordinary path bytes. The function operates on bytes only;
   `LC_ALL=C` is set at function entry (EA-004).

5. **Idempotence (INV-003).** `canonicalize_path(canonicalize_path(x))` ==
   `canonicalize_path(x)` for every input.

6. **No shell expansion (INV-004).** Glob characters (`*`, `?`, `[`, `]`),
   parameter sigils (`$`), command-substitution sigils (`` ` ``, `$(`), and
   brace-expansion sigils (`{`, `}`) appearing in input pass through to
   output as literal bytes. The function never performs pathname expansion,
   command substitution, parameter expansion, or globbing on the input.
   The function never reads filesystem state.

7. **Performance + no fork/exec (INV-012).** A 1024-byte input completes in
   under 50ms on the CI baseline. The function body contains no `$(...)`
   command substitution, no backticks, no pipe operators, no external
   command invocations. Pure parameter expansion only.

## Forbidden idioms

- **PRH-001**: Regex-based path normalization (`s|/[^/]+/\.\./|/|g` and
  variants) is forbidden anywhere in `scripts/lib.sh` or
  `hooks/sensitive-file-guard.sh`. Incomplete in one pass; corrupts paths
  containing glob characters; observed to infinite-loop on bracket-and-`..`
  combinations. The segment-stack design is the only sanctioned normalizer.

- **PRH-004**: `_check_file_against_patterns` MUST receive only output of
  `canonicalize_path` — both target and pattern. Any direct comparison
  between a raw target and a raw pattern is the canonicalization-mismatch
  bypass class.

## Why these are load-bearing

`canonicalize_path` runs upstream of `_check_file_against_patterns` in
`hooks/sensitive-file-guard.sh`. A regression that causes empty output on
non-empty input, or that lets a Unicode dot lookalike collapse into a
traversal, opens the exact bypass class the R2 audit enumerated 32 findings
against. The function is small and cheap; correctness here is non-negotiable
because it gates every Edit/Write tool-path operation
(`Edit`/`Write`/`MultiEdit`/`NotebookEdit`/`CreateFile`) through the
PreToolUse hook. Bash is no longer inspected by `sensitive-file-guard.sh`
(sfg-edit-write-only / AP-040): the hook fast-paths `Bash` to `exit 0` before
`canonicalize_path` runs. The `_has_write_pattern` helper still lives in
`lib.sh` and is used by `workflow-gate.sh`, so this rule's `lib.sh`-load
intent remains correct for that consumer.

The historical pattern — see PAT-001 HP-3 (`workflow-gate.sh fails closed on
malformed stdin JSON`) — is that fail-open variants persist in security
hooks for ≥7 PRs across multiple reviews because reviewers don't read the
function body for clause-5 violations. The function-level invariants here
are intended to load into editing context whenever an agent opens
`scripts/lib.sh`, so a clause-5 fail-open variant of `canonicalize_path`
(empty output on non-empty input) is structurally visible during the edit.

## Tests

- `tests/test-canonicalize-path.sh` — fuzz corpus + property-based + structural.
  The fuzz tests (INV-001/INV-001a/INV-002) call `canonicalize_path` **in-process**
  (sourced once at file top), never via a per-input `timeout … bash -c "source
  lib.sh; …"`. Re-sourcing `lib.sh` per input across ~1000 inputs × 3 tests was
  ~3000 forks and made the suite exceed bounded time, blocking the
  full-`tests/test-*.sh` done-gate (DEP-001). Do **not** reintroduce a per-input
  subprocess: the function is proven total and fork-free/bounded (INV-012), so a
  per-input hang cannot occur by construction; a regression hang surfaces as a
  suite-level timeout. Keep the in-process call.
- `tests/test-sensitive-file-guard.sh` — INV-005 (canonical-only-at-matcher),
  INV-008 (canonical-on-both-sides), INV-005a (version probe before use).
- `tests/test-architecture-drift.sh` — PAT-017 (rule-file presence + paths
  frontmatter + See-link + in-file pointer comment).

## Related

- **PAT-001** (PreToolUse hook conventions) — `canonicalize_path` is consumed
  inside a fail-closed PreToolUse hook; PAT-001's clause-5 discipline applies
  to anything that gates `_check_file_against_patterns`.
- **PAT-016** (Glob over directory contents) — the interpreter list inside
  `_has_write_pattern` (INV-013 detection) is itself an enumerated list
  governed by PAT-016; count-match drift tests live in
  `tests/test-sensitive-file-guard.sh`.
- **ABS-009** (Path-scoped rule files) — this is a Feature B usage of
  ABS-009; PAT-001 was the first dogfood, this is the second.
