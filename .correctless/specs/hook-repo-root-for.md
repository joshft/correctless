# Spec: audit-trail file-repo attribution (narrowed #244)

## Metadata
- **Created**: 2026-07-05T02:24:00Z
- **Revised**: 2026-07-05T05:10:00Z — **RE-SCOPED to audit-trail attribution only** (see "Scope history") + 2026-07-05T05:30:00Z (codex pass on the narrow spec: no architectural blocker; fixed the R-002 `ADHERENCE` omission, formalized R-008, replaced the R-1 cwd heuristic with resolve-first+cache, tightened R-006 memoization wording)
- **Status**: reviewed (re-scoped; the narrow surface needs a light re-review, not the full 6-lens pass the v5 protection spec got)
- **Impacts**: none
- **Branch**: feature/hook-repo-root-for-artifact
- **Research**: null
- **Intensity**: high (workflow config) — but the feature is deliberately small and fail-open; artifact weight is proportionate, not the v5 sprawl
- **Issue**: #244 (attribution instance only)

## Scope history (why this spec is small)

The original #244 named three instances of the cwd-vs-artifact bug: **workflow-gate** (already fixed by #242/PR #243), **audit-trail** (wrong-repo attribution — a silent-telemetry correctness bug), and **sensitive-file-guard** (`custom_patterns` from the wrong repo — the issue itself rated this mild: "core SFG protection is intact").

An earlier version of this spec (v5) tried to "properly" migrate the two **protection** hooks (gate, SFG) and grew a security-perimeter edifice: authority sets, lexical+realpath topology, "block if any blocks", `git -c core.hooksPath=/dev/null -c safe.directory=* … timeout` hardening, `GIT_CEILING_DIRECTORIES`, version-probe sentinels. A 7-lens re-review (incl. an adversarial Red Team) concluded that edifice is the **PMB-020 category error**: SFG and workflow-gate are cooperative-loop **guardrails, not security perimeters** (AP-040). Every "bypass" the hardening defends against (planted nested `.git`, leaf-symlink, hardlink, auto-format config-exec) requires the agent to run Bash — and a Bash-capable agent already writes files directly, past the guardrail. The Red Team's own verdict: the protection guarantees "exceed what the resolution layer actually delivers."

**Decision (2026-07-05):** narrow to the **audit-trail attribution fix** — the one instance that is a genuine correctness bug (silent telemetry), is fail-open (PostToolUse, no security dimension), and needs no hardening. Leave workflow-gate (#242 already fixed) and SFG untouched. The protection-semantics work is dropped; if the nested-repo guardrail concern is ever worth revisiting, it is a separate, honestly-scoped guardrail note (not a perimeter). The dropped-scope findings are archived in `.correctless/artifacts/review-spec-findings-hook-repo-root-for.md` and are moot for this narrow feature.

## Context

`hooks/audit-trail.sh` (PostToolUse) records every file modification into a per-workflow trail. It derives everything — the artifacts-dir fast-path, the branch slug, the state file, the trail file, the config, and the `branch` field written into every record — from the hook's **cwd**, not from the edited file's repo. When the harness edits a file in a sibling git repo/worktree while cwd is a different repo, the event is either logged under the **wrong** repo's trail or (if cwd has no artifacts dir) **dropped entirely**. This is the silent-telemetry-failure class: `/cmetrics`, token tracking, and adherence records silently attribute work to the wrong repo, and the substrate looks healthy while measuring nothing for the edited file's actual repo.

## What it does

`audit-trail.sh` attributes each event to the **edited file's own repo** F. It resolves F from the file path (a small local resolver), and derives the slug / state file / trail / config / record-branch from F. If the file is not in any git repo, or F has no active workflow state, the hook **no-ops** (exit 0) — it never misattributes to cwd. PostToolUse fail-open posture is fully preserved: any resolution miss, missing helper, or absent `git` degrades to a clean exit 0.

## Rules

### R-001 — Local file-repo resolver, no security hardening
Add a small resolver **local to `audit-trail.sh`** (NOT `lib.sh` — see R-008): `_resolve_file_repo <path>` walks up from the path's nearest existing ancestor directory and runs `git --no-optional-locks -C <dir> rev-parse --show-toplevel`. It prints the repo root + returns 0 when the path is in a git repo; prints nothing + returns 1 when it is not (the distinction attribution needs, to no-op vs. misattribute). The upward walk is bounded by path-component count.

**Deliberately NO** `safe.directory` / `GIT_CEILING_DIRECTORIES` / `-c core.*` / `timeout` hardening: this is fail-open telemetry, not a security decision, and that hardening is what created the macOS/`timeout`/`realpath`/git-version landmines the v5 review flagged. A planted-repo threat against telemetry attribution is not worth breaking macOS support.
- **Enforcement**: `tests/test-audit-trail.sh` — two real `git init` repos; `_resolve_file_repo "$B/f"` prints B while cwd is A; a `/tmp/nogit/f` path prints nothing + rc 1; a nonexistent leaf under B resolves via nearest existing ancestor.

### R-002 — Attribute to the file's repo F; no-op when there is no honored repo or no workflow
Every repo-scoped derivation in `audit-trail.sh` resolves from F, not cwd: the artifacts-dir fast-path (currently the cwd-relative `[ -d ".correctless/artifacts" ] || exit 0` at `:12`), the slug (`:66-67`), STATE_FILE (`:73`), CONFIG_FILE (`:82`), TRAIL (`:86`), the `_audit_branch` value written into every record's `branch` field (`:104`), **and the full-mode `ADHERENCE` state file (`adherence-state-${slug}.json`, `:173`)** — every `.correctless/artifacts/` path in the hook, with no cwd-relative survivor. A file in sibling B while cwd is A logs under **B's** trail; a file in no git repo, or in a repo with no `workflow-state` file, is a clean **no-op (exit 0)** — never logged under A.
- **Enforcement**: `tests/test-audit-trail.sh` — 3-cell matrix over real repos: (A-has-artifacts, B-none) → no-op, A's trail unchanged (before/after line-count); (A-none, B-has) → lands under B (this is the case today's `:12` cwd bail silently drops); (A-has, B-has) → under B, A untouched. Plus: the record's `branch` field carries B's branch (not A's).

### R-003 — Branch resolved from F, guarded against the empty→cwd leak
The record branch comes from `git --no-optional-locks -C <F> branch --show-current`. It MUST be guarded so an empty result (detached HEAD / non-repo) is treated as "no attribution" (no-op), NOT passed bare into `branch_slug` — `branch_slug` (`lib.sh:105`) treats an empty argument identically to no argument and silently falls back to the **cwd** branch, which would re-introduce the exact cross-repo leak this fix removes.
- **Enforcement**: `tests/test-audit-trail.sh` — a detached-HEAD B file does not attribute under cwd/A's slug (asserts the guard, not just the branch value).

### R-004 — Same-target guarantee for the common (cwd==F) case
When cwd IS the edited file's repo (the overwhelmingly common single-repo case), the resolved STATE_FILE / TRAIL / CONFIG point at the **same files** as today. (Note: they may be spelled **absolute** `<F>/.correctless/artifacts/…` where today they are **relative** `.correctless/artifacts/…` — that is the same target file / same inode, not a byte-identical string. The guarantee is same-*target*, not same-*string*; do not assert string equality.) This prevents orphaning an existing in-flight workflow's state/trail.
- **Enforcement**: `tests/test-audit-trail.sh` — in a single repo with cwd==repo-root, the migrated hook writes to the same trail/state file an unmigrated run would (assert the file path resolves to the same inode / same existing artifact, not string equality).

### R-005 — PostToolUse fail-open preserved; no sentinel
The hook stays fail-open on every path: `git` absent, file outside any repo, resolver returns rc 1, or (version skew) the resolver somehow undefined → **exit 0**. No fail-closed sentinel is added (that is a PreToolUse concept; audit-trail is advisory PostToolUse). Because the resolver is local to `audit-trail.sh` (R-008), there is no cross-file version-skew surface to guard.
- **Enforcement**: `tests/test-audit-trail.sh` — corrupt/absent state → exit 0; a `PATH` without `git` → exit 0 (degrades, never errors).

### R-006 — Cross-repo MultiEdit attributes per target
A MultiEdit spanning repos resolves `_resolve_file_repo` **per target file** and appends each target's record to its own repo's trail (grouped by repo); no target's record lands in another repo's trail. Memoize resolution — cache by the resolved repo root (prefix cache) so cost is `O(unique nearest-existing dirs)`, not one git fork per target when targets share a repo. Preserve per-trail input order.
- **Enforcement**: `tests/test-audit-trail.sh` — a MultiEdit with 2 A-targets + 1 B-target → A-trail gains exactly 2 records, B-trail exactly 1, order preserved.

### R-007 — Bash-target attribution is consistent with Edit-target
For a Bash write whose target file (`get_target_file`) resolves into a sibling repo, attribution uses that target's repo F, same as an Edit — so Edit-tool and Bash-tool writes to the same file attribute consistently.
- **Enforcement**: `tests/test-audit-trail.sh` — a `Bash` write to `$B/f` attributes under B, matching an Edit to `$B/f`.

### R-008 — Resolver lives in `audit-trail.sh`, not `lib.sh` (avoids AP-037; ABS-001 deferral)
`_resolve_file_repo` is defined **local to `audit-trail.sh`**, which is NOT in the SFG DEFAULTS protected list — so the feature edits exactly one unprotected file and sidesteps the AP-037 self-guard problem (`lib.sh` IS SFG-protected; editing it would require the lift-and-restore dance). This **duplicates** the walk idiom #242 put in `workflow-gate.sh` (which has different, gate-specific fail-closed semantics) — an **accepted, documented ABS-001 deferral** for this narrow scope. Follow-up (tracked separately, deferred per the re-scope decision): extract a shared `try_repo_root_for` into `lib.sh` and dedup both call sites.
- **Enforcement**: a source-grep in `tests/test-audit-trail.sh` asserting `_resolve_file_repo` is defined in `audit-trail.sh` and that `audit-trail.sh` is absent from `hooks/sensitive-file-guard.sh`'s DEFAULTS (so the single-file-edit property holds); the ABS-001 duplication is the accepted deferral, not a drift-test failure.

## Won't do (explicit)
- **No `lib.sh` change** — see **R-008** (resolver is local to `audit-trail.sh` to avoid the AP-037 self-guard; ABS-001 dedup deferred to a follow-up).
- **No workflow-gate change** — #242 already resolves the gate's repo from the edited file; leave it.
- **No sensitive-file-guard change** — the `custom_patterns` cross-repo issue is mild (DEFAULTS intact) and dragging SFG in reopens the whole protection-semantics can of worms. Left as-is; note the residual in the issue.
- **No auto-format change** — it has no lib.sh/sentinel infra and migrating it added a config→exec trust crossing (Red Team). Out of scope.
- **No protection semantics, git-config-exec hardening, sentinels, authority sets, or observability/diagnose changes.**
- **No retroactive repair** of historical misattributed trails.

## Risks
- **R-1**: reordering the cwd fast-path (`:12`) to resolve F first changes the early-exit profile — every PostToolUse event now reads stdin + resolves before it can bail. *Mitigation*: **resolve first, then cache** — do NOT use a "file plausibly in cwd" heuristic to skip resolution (it misattributes nested repos/submodules, contradicting R-002). Instead, keep the cheapest possible pre-parse guard only for the tool cases audit-trail already ignores, and for the file cases always resolve F (memoized per R-006) then bail if F has no artifacts dir / no workflow state. Audit-trail is fail-open, so the worst case is a small per-event latency bump (one `git rev-parse` on the edited file's dir), not a correctness issue. Covered by the R-002 matrix.
- **R-2**: the local resolver duplicates #242's walk (ABS-001 deferral). *Mitigation*: documented accepted deferral + follow-up to extract to lib.sh; the two walks are small and the follow-up dedups them.
- **R-3 (AP-031)**: fixtures must be real `git init` repos, not hand-rolled `.git`. *Mitigation*: R-001..R-007 enforcement all use real repos.

## Open questions
- **OQ-1**: keep the resolver local to `audit-trail.sh` (this spec's choice — avoids AP-037, defers ABS-001) vs. put it in `lib.sh` now (ABS-001-clean but triggers the lib.sh lift-and-restore). Leaning local + follow-up. Confirm before implementation.
