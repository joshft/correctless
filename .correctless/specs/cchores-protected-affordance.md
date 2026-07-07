# Spec: /cchores Protected-File Affordance (PRH-003 v2)

## Metadata
- **Task**: cchores-protected-affordance
- **Created**: 2026-07-06T10:57:10Z
- **Status**: draft (revised after /creview-spec round 1 [6-agent] + round 2 [3-agent focused] adversarial review, 2026-07-06; affordance-eligible set = conservative/non-security-infra per user disposition)
- **Impacts**: cchores (PRH-003, AD-005, INV-010 pre/post-cdebug SFG checks, allowed-tools), sensitive-file-guard (DEFAULTS, new conditional-allow allowlist logic), ABS-045 (capability boundary — semantic change), `.claude/rules/hooks-pretooluse.md` (second carve-out), new ABS entry (branch+file-scoped allowlist + authorization marker)
- **Branch**: feature/cchores-protected-affordance
- **Research**: null
- **Intensity**: high
- **Recommended-intensity**: high
- **Intensity reason**: file-path signal (`hooks/sensitive-file-guard.sh`, `skills/cchores/*`), keyword signal (injection, trust boundary, authorization), TB overlap (untrusted issue ingestion; SFG guardrail). Project floor is high.
- **Override**: none

## Context

`/cchores` is fail-closed against SFG-protected files (PRH-003 / AD-005): any issue whose fix targets a file in the `sensitive-file-guard.sh` DEFAULTS list aborts at pre-selection, and any post-`/cdebug` diff touching a protected path aborts before PR. This was correct for v1 (a fully-autonomous, injection-exposed pipeline should never touch protected infra). But it makes a large share of the repo's own bug backlog unreachable: a 2026-07-06 no-op run found **13 of 53** candidate bugs blocked by `/cchores`'s protected-set guard. Two distinct protected sets are at play and MUST NOT be conflated (RS-019):
- **SFG DEFAULTS** — the patterns `hooks/sensitive-file-guard.sh` matches against `tool_input.file_path`. The blocked fixes that live here are files like `scripts/lib.sh`, `scripts/prune-scan.sh`, `scripts/external-review-run.sh`, `scripts/harness-fingerprint.sh`. These are what the INV-002 allowlist and INV-008 partition operate on.
- **`/cchores`'s pre-selection protected set** — a *superset*: SFG DEFAULTS **∪** `{hooks/sensitive-file-guard.sh}` **∪** shared project docs. `sensitive-file-guard.sh` itself is **not** in DEFAULTS (verified — it is blocked by `/cchores` PRH-003 prose, not by the SFG hook); a chore fixing the hook is gated by the orchestrator, and the INV-008 partition test structurally *cannot* classify it. INV-010 (guard-edit banner) is the control for that file, not the allowlist.

PRH-003/AD-005 were explicitly worded "in v1 … unblocked later by #176/#187" — this feature is that v2.

This feature lets `/cchores` fix SFG-protected files **only when a human explicitly invokes it with an issue number** (`/cchores <N>`), treating that explicit invocation as tacit authorization. No-arg auto-select mode — which is injection-exposed via the untrusted-issue *selection* path — keeps v1 behaviour unchanged. Even in authorized mode, a **secret-class hard floor** (keys, credentials, `.env`) is never reachable **via a naive Edit/Write** (Bash-mediated writes remain the accepted AP-040 residual), and the write is enabled through a **branch- and file-scoped SFG allowlist** so protection is never globally lifted.

**Mechanism honesty (per PMB-020 / AP-040).** The enforcement layer is a Claude Code PreToolUse hook in a cooperative-agent loop. It is a **guardrail, not a security boundary**: it is already Bash-evadable (it inspects only the Edit/Write tool-path, never Bash — AP-040), and this feature does **not** make it more evadable. The affordance's guarantees hold against the cooperative agent's *naive Edit/Write*, gated by (a) a human explicitly naming the issue and (b) `/cchores` never merging (PRH-004) so a human reviews every resulting PR. No claim is made that this stops a motivated prompt injection; that residual is pre-existing and unchanged.

## Scope

**In scope**
- A mode-aware relaxation of `/cchores`'s two SFG gates (pre-selection, post-cdebug diff), active only in explicit-issue mode.
- A **branch- AND file-scoped** allowlist in `hooks/sensitive-file-guard.sh`: allow Edit/Write to a *non-secret-floor, non-custom-pattern* protected path when an authorization marker binds the current branch AND names that specific path (`marker.allowed_paths`, RS-007). This is a **conditional-allow** carve-out — a documented, deliberately-narrow relaxation of the guardrail, NOT a security boundary (RS-001; see Mechanism honesty).
- A `SECRET_FLOOR` partition of the DEFAULTS list with a **deny-by-default runtime** posture: only patterns on an explicit affordance-eligible allowlist are writable under a marker; everything else in DEFAULTS (including unclassified additions and all `custom_patterns`) is treated as floor and BLOCKED (RS-005, RS-021). Prefer a single-source classification (inline `# floor`/`# affordance` tags on the DEFAULTS block, or a sourceable `is_secret_floor()`), not a third duplicated list (RS-012).
- A sanctioned marker writer (`scripts/chores-authorize.sh`) with `write`/`clear`/`check` subcommands; `write` **refuses unless invoked with an explicit `--issue <N>`** that matches the current chore branch (relocates INV-001/INV-004's enforceable leg into tested bash — RS-010). Full marker lifecycle in `skills/cchores/SKILL.md`, bound to a **per-run nonce/run_id** and cleared unconditionally at run start (RS-009).
- **DEFAULTS additions** (sole-writer + self-authorization hardening, RS-002/RS-011): add `scripts/chores-authorize.sh` (three-form) AND the marker path `.correctless/artifacts/chores-protected-authorized.json` to SFG DEFAULTS, the marker classified **never-affordance-eligible**; register the writer in `scripts/sanctioned-*-writers.tsv`. Narrow `/cchores`'s `Write(.correctless/artifacts/*)` so `chores-authorize.sh` is the only cooperative write path to the marker.
- **Documentation obligations** (RS-004, tightened per R2-M/N + DC-3/6/10):
  - Rewrite **ABS-045** — touch its **Capability** ("exits 2 on a match" → conditional-allow), **Posture** (now TWO non-strict behaviors, not one), and **Violated-when** fields (a partial edit leaves it self-contradictory). **List the specific See-linking ABS entries** that gain the chore-branch exception — the sole-writer *script* entries **ABS-029** (`audit-record.sh`), **ABS-030** (`autonomous-decision-writer.sh`), **ABS-042** (`external-review-run.sh`/`config-update.sh`), **ABS-047** (`meta-record.sh`, currently MISSING from ABS-045's See-linker list — add it), and the relevant parts of **ABS-027**/**ABS-035** — with a one-line note on each that its Edit/Write protection is conditionally relaxed on a chore branch under INV-002/010/007. Under the **conservative eligible set**, these sole-writer scripts are tagged `# other-floor` (NOT affordance-eligible), so in practice their exception is "none" — state that explicitly (the exception applies only to `# affordance` infra). State-file entries (ABS-012/016/038/040/041) gain NO exception.
  - Amend **`.claude/rules/hooks-pretooluse.md`** with the second carve-out, worded so the conditional-allow exit-0 is gated on a **fully-verified marker predicate** and **every failure/ambiguity path (no marker, parse error, git/manifest failure, non-numeric issue, run_id mismatch, out-of-scope path) stays exit-2** — i.e. it does NOT loosen clause 5 (R2-N); cross-link INV-011.
  - Add **`scripts/chores-authorize.sh`** (three DEFAULTS forms) to **`.claude/rules/sfg-deliverable.md`**'s "When this rule applies" enumeration (R2-L — it is a new AP-037 deliverable per EA-004; the generalized `lift-active:<path>` sentinel already handles the mechanism, but the prose enumeration must not go stale). Correct the Scope's earlier "sfg-deliverable.md is unchanged" claim below.
  - Update the SFG header comment block (L8 "no phase exceptions", L13-19 "exits 2 on a match").
  - Add the new abstraction as **ABS-049** (ABS-048 is current max) for the branch+file-scoped conditional-allow allowlist + per-run marker.
- **Version handshake** (RS-006): a capability sentinel in the hook (e.g. `# SFG_AFFORDANCE_VERSION: 1`), which explicit-issue mode verifies (and confirms `.correctless/scripts/chores-authorize.sh` exists) BEFORE writing the marker; absent → degrade to v1 with a `bash setup` remediation message.
- Structural + behavioral tests (incl. a real-marker fixture per RS-020 and a no-arg golden-output regression per RS-025); sync-mirror parity for SECRET_FLOOR/allowlist; AP-024 source-vs-installed script count-parity test.

**Prerequisite (AP-008 allowed-tools cross-check)**: add `Bash(bash .correctless/scripts/chores-authorize.sh*)` and the source-form `Bash(bash scripts/chores-authorize.sh*)` to `skills/cchores/SKILL.md` `allowed-tools`, AND narrow the marker out of the retained `Write(.correctless/artifacts/*)` grant (RS-011).

**Out of scope**
- No-arg auto-select mode behavior (unchanged — still PRH-003 abort on any protected target; byte-identity asserted by a golden-output regression test per RS-025).
- The shared-project-doc scope guard (`ARCHITECTURE.md`, `AGENT_CONTEXT.md`, `CLAUDE.md`, `README.md`, `antipatterns.md`) — it **stays** to keep chore PRs focused; it is a `/cchores` scope concern, not an SFG concern, and is not relaxed.
- Any change to `/cchores`'s never-merge / ≤1-comment / redaction contracts.
- Making SFG a security boundary, or closing the AP-040 Bash-evasion residual (explicit non-goal — see Mechanism honesty and the accepted-residual note in INV-002/BND-001).
- The interactive human lift-and-restore *mechanism* (`.claude/rules/sfg-deliverable.md`'s procedure + `check-no-pending-sfg-lift.sh`) is unchanged; this feature is a separate, autonomous-mode mechanism. Its *deliverable enumeration* does grow: adding `scripts/chores-authorize.sh` to DEFAULTS makes IT a new AP-037 deliverable (EA-004), so the rule's "When this rule applies" list gains `chores-authorize.sh` (three-form) — see Documentation obligations (R2-L). Developing `chores-authorize.sh` uses the existing generalized `lift-active:<path>` sentinel; no procedure change.

**Alternatives Considered** (RS-026): gating authorization entirely at the `/cchores` layer via the existing autonomous lift-and-restore machinery (`.claude/rules/sfg-deliverable.md` + `check-no-pending-sfg-lift.sh` + the `cmd_done` gate) — a scoped, marker-audited lift of the specific target file from DEFAULTS for the run, restored before push — was considered. It would keep SFG a dumb guardrail (no new branch, no `git` call on the hot path, file-scoped by construction) and dissolve several findings. **Decision: retain the in-hook allowlist** (per the 2026-07-06 review disposition), accepting the added hook complexity in exchange for enforcement that does not depend on the orchestrator correctly restoring state before push. **Honest tradeoff note (DC-8)**: the lift-and-restore alternative's "orchestrator might not restore" risk is already partly backstopped structurally — `.claude/rules/sfg-deliverable.md`'s `cmd_done` gate refuses the `done` transition while `.sfg-lift-active` is present, and CI runs the `sfg-lift-check` job — so the marginal safety of the in-hook branch is smaller than a naive reading suggests; the in-hook choice is justified more by per-run/per-file scoping and testability-in-isolation than by restore-safety alone. The added complexity is bounded against the AP-040 re-scope by: gating every new branch behind an existing DEFAULTS match (cost only paid on a protected target), keeping the git/marker reads fail-closed, and downgrading all security framing to guardrail (INV-001/002/003/004/009).

## Complexity Budget
- **Estimated LOC**: ~380 (≈150 hook incl. guarded git + marker verify + deny-by-default partition + version sentinel, ≈110 SKILL.md prose, ≈80 marker writer w/ `--issue` contract + nonce, plus tests)
- **Files touched**: ~8 source (`hooks/sensitive-file-guard.sh`, `skills/cchores/SKILL.md`, `scripts/chores-authorize.sh` new, `scripts/sanctioned-*-writers.tsv`, `.correctless/ARCHITECTURE.md`/abstractions body [ABS-045 + new ABS], `.claude/rules/hooks-pretooluse.md`, sync mirror ×2) + ~4 test files
- **New abstractions**: 1 (branch- + file-scoped SFG conditional-allow allowlist + per-run authorization marker; documented as a new ABS entry with sole-writer/partition/lifecycle per RS-004/RS-011)
- **Trust boundaries touched**: 3 (TB-009 untrusted GitHub issue ingestion; TB-004d autonomous issue-selection authority; the SFG guardrail boundary / ABS-045)
- **Risk surface delta**: high (adds a conditional-allow branch + `git` subprocess + marker file-read to the Edit/Write hot path of the repo's most security-relevant hook, 2 weeks after the AP-040 re-scope deliberately minimized it; must be provably narrow AND fail-closed on every new path — see INV-002/003/008/009 and the PAT-001 clause-5 obligation)

## Invariants

> **Framing note (RS-001, AP-040 mechanism-capability-mismatch).** The enforcement layer for every in-hook invariant below is a Claude Code PreToolUse hook in the cooperative-agent loop — it inspects ONLY the Edit/Write tool-path (`tool_input.file_path`) and NEVER any Bash command (AP-040 / ABS-045). These invariants are **guardrails, not a perimeter**. Each `Guards against:` line names only the *naive Edit/Write* threat the layer can actually stop; each carries an explicit **Does NOT guard against** clause for the Bash-evasion residual (a motivated injection driving `/cdebug`'s Bash to `cat > .env` / `tee` / `python -c` / `git checkout -- <file>`). The authoritative defenses against injection-grade exfiltration are **INV-007** (post-cdebug diff), **INV-013 of cchores** (outbound redaction), and **PRH-003** (never-merge + mandatory human PR review) — all outside SFG. No in-hook invariant is tagged `critical`; the honest ceiling is `high`/guardrail.

### INV-001: Mode-gated activation (guardrail)
- **Type**: must
- **Category**: security (guardrail)
- **Statement**: The protected-file affordance is active **only** when `/cchores` is invoked with an explicit issue number. In no-arg auto-select mode, `/cchores` never invokes `chores-authorize.sh write` and any SFG-protected fix target aborts at pre-selection exactly as in v1 (PRH-003).
- **Boundary**: TB-004d (autonomous issue-selection authority) / TB-009 (untrusted issue ingestion)
- **Violated when**: an auto-selected (no-arg) run mints a marker via the sanctioned writer, or reaches `/cdebug` with a protected fix target without aborting.
- **Enforcement**: **structural leg (RS-010)** — `scripts/chores-authorize.sh write` REFUSES to write unless invoked with an explicit `--issue <N>` argument AND `<N>` matches the current `chore/issue-<N>-*` branch (writer reads `git rev-parse`, fails closed on mismatch/absence); this is a real unit test (write with no `--issue` → non-zero, no marker; `write --issue 5` on `chore/issue-9-*` → non-zero, no marker). **Prompt-level residual (acknowledged, NOT claimed test-covered)** — that `/cchores` calls the writer only in explicit-issue mode is cooperative; a grep over `skills/cchores/SKILL.md` for a marker-write on the no-arg path is a *tripwire*, not the guarantee.
- **Guards against**: an honest no-arg run auto-selecting a protected-touching issue and minting an authorization for it.
- **Does NOT guard against**: an injected `/cdebug` self-writing the marker via Bash on its own legitimate chore branch (RS-002) — that residual is contained only by INV-007 + never-merge + redaction, not by this invariant.
- **Test approach**: unit (writer `--issue` contract) + acknowledged prompt-level residual
- **Risk**: high

### INV-002: Branch- and file-scoped SFG allowlist (guardrail)
- **Type**: must
- **Category**: security (guardrail)
- **Statement**: `sensitive-file-guard.sh` allows an Edit/Write to a protected path **iff ALL hold**: (1) `is_affordance_eligible(canonical_target)` is true (the matching DEFAULTS pattern carries the `# affordance` tag, INV-008) AND `is_secret_floor(canonical_target)` is false AND the target is NOT a `custom_patterns` match (RS-021); (2) the authorization marker exists and parses (INV-011); (3) `marker.branch` **byte-exactly** equals the branch of the git working tree **that contains the Edit/Write target**, and that branch matches `chore/issue-<marker.issue>-*` where `marker.issue` is validated `^[0-9]+$` (RS-016); (4) the canonicalized target is a member of `marker.allowed_paths` (RS-007); (5) `marker.run_id` equals the current run's manifest `run_id` (INV-005). In every other case BLOCKED. **Target-tree resolution (R2-I, closes the RS-008 remainder)**: the target tree root is `git -C "$(dirname "$canonical_target")" rev-parse --show-toplevel`; the marker AND the run manifest are read relative to THAT root (never the hook cwd), and the branch is `git -C "$(dirname "$canonical_target")" rev-parse --abbrev-ref HEAD` — so marker, manifest, and branch all come from the target's tree. A bare-basename target (`dirname == "."`) whose resolved tree differs from cwd is handled by using the resolved toplevel, not cwd. The allowlist consumes the SAME `canonicalize_path` output and matcher primitive as the main STEP-9 match (RS-014). **Side-effect-free classification (R2-J)**: `is_affordance_eligible()`/`is_secret_floor()` MUST be callable without executing the hook's policy body — pinned via a `main`-guard on `sensitive-file-guard.sh` (source-time no-op when sourced) so `/cchores`'s INV-006/INV-007 checks can source them without triggering `set -euo pipefail`, the canonicalize probe, or the STEP-9 loop.
- **Boundary**: SFG guardrail boundary / ABS-045
- **Violated when**: a protected write is allowed with no/unparseable marker, on a non-matching branch, on a branch whose name does not match the (numeric) marker issue, for a path not in `marker.allowed_paths`, for a `custom_patterns` or `SECRET_FLOOR` path, or when the target's tree branch differs from the hook's cwd branch and the check keyed on cwd.
- **Enforcement**: `hooks/sensitive-file-guard.sh` allowlist check runs after the DEFAULTS pattern match, before BLOCK; the `git` read is guarded (`2>/dev/null || true`; empty/`HEAD`/failure → no match → BLOCK; exits only 0 or 2 per PAT-001 clause 5 — RS-003). Behavioral tests over a real `git init` fixture (RS-020): allow-on-full-match; block with no marker; block on mismatched branch; block when branch name ≠ marker issue; block when target ∉ `allowed_paths`; block for a `custom_patterns` path with a valid marker; block when the target's worktree branch ≠ cwd branch (AP-035); negative cell (valid marker + matching branch + non-DEFAULTS path → normal exit-0, allowlist irrelevant).
- **Guards against**: a naive Edit/Write leaking outside the one authorized chore branch AND the specific scoped file(s).
- **Does NOT guard against**: a Bash-mediated write to the same path (AP-040 residual, accepted).
- **Test approach**: integration
- **Risk**: high

### INV-003: Secret-class hard floor (deny-first, guardrail)
- **Type**: must-not
- **Category**: security (guardrail)
- **Statement**: `sensitive-file-guard.sh` NEVER allows an Edit/Write to a `# secret-floor` pattern — the DEFAULTS lines tagged `# secret-floor` (INV-008 single source): `.env`, `.env.*`, `*.pem`, `*.key`, `*.p12`, `*.pfx`, `credentials.json`, `credentials.yml`, `service-account*.json`, `*.secret`, `*.secrets`, `secrets.yml`, `secrets.yaml`, `secrets.json`, `.secrets`, `id_rsa`, `id_rsa.*`, `id_ed25519`, `id_ed25519.*`, `*.keystore`, `*.jks` (this list is **documentation of which patterns carry the `# secret-floor` tag**, not a second code enumeration — `is_secret_floor()` derives from the tags per RS-012) — regardless of marker, branch, or mode. Membership is evaluated against the **canonicalized** target using the same matcher primitive as the main pipeline (RS-014), so canonicalization-edge forms (`secrets/../.env`, `./credentials.json`, uppercase `ID_RSA`) are caught.
- **Boundary**: SFG guardrail boundary
- **Violated when**: a marker/branch match causes a secret-floor path (in any canonicalization form) to be allowed.
- **Enforcement**: the `SECRET_FLOOR` check runs **first**; on a floor match the hook BLOCKS before the allowlist is consulted. Tests assert `credentials.json`, `id_rsa`, `secrets/../.env`, `foo/../id_rsa`, uppercase `ID_RSA` are each blocked *with a valid marker on the matching branch*.
- **Guards against**: a naive Edit/Write planting/overwriting a key or credential.
- **Does NOT guard against**: injection-driven exfiltration/planting of a secret via Bash (`cat > .env`), which SFG cannot see — the accepted AP-040 residual; the real exfil defenses are redaction (INV-013 of cchores) + never-merge + human review.
- **Test approach**: integration
- **Risk**: high

### INV-004: Marker provenance (structural writer contract)
- **Type**: must
- **Category**: security (guardrail)
- **Statement**: The authorization marker is written only through the sanctioned `scripts/chores-authorize.sh write --issue <N>`, only after the suitability classifier (INV-003 of cchores) and idempotency re-check pass — never by `/cdebug`, never derived from issue content.
- **Boundary**: TB-009 (untrusted issue ingestion)
- **Violated when**: the marker is written before suitability/idempotency pass, by a writer invocation lacking `--issue`, or by any agent whose allowed-tools grant the writer/marker.
- **Enforcement**: **structural** — (a) the writer's `--issue` + branch-match contract (INV-001); (b) a structural test parses `agents/cdebug-fix.md`'s `tools:` list and asserts (i) no entry matches `Bash(*chores-authorize.sh*)` and (ii) no `Write(...)` entry whose glob **matches** (evaluated by glob-coverage, e.g. `[[ ==`, NOT substring search — R2-O) `.correctless/artifacts/chores-protected-authorized.json`; a RED-proof fixture asserts the test FAILS when a covering `Write(.correctless/artifacts/*)` grant is present; (c) the marker path + writer are in SFG DEFAULTS so a naive `/cdebug` Edit/Write to the marker is blocked (RS-002/RS-011). **Prompt-level residual (acknowledged)** — the classify-then-idempotency-then-write ordering is SKILL.md sequencing; a Bash-redirect forge by an injected `/cdebug` remains the accepted AP-040 residual.
- **Guards against**: widening the authorization window; naive self-authorization.
- **Does NOT guard against**: a Bash-redirect marker forge (AP-040 residual).
- **Test approach**: integration + structural (agent frontmatter allowlist)
- **Risk**: high

### INV-005: Marker lifecycle — per-run identity, clear-at-start, cleanup under lock
- **Type**: must
- **Category**: security (lifecycle)
- **Statement**: The marker carries a **per-run identity** (`run_id`/nonce, sourced from the chore-run manifest — RS-009); SFG honors the marker only when `marker.run_id` equals the current run's manifest `run_id`. `/cchores` **unconditionally clears any pre-existing marker at run start** (before writing its own), performs marker write and clear **while holding the INV-015 worktree lock**, and clears on **every** terminal path (PR opened, abort, no-op).
- **Boundary**: SFG guardrail boundary
- **Violated when**: SFG honors a marker whose `run_id` ≠ the current run; a pre-existing marker is not cleared at run start; a terminal path returns without clearing; or write/clear occurs outside the lock.
- **Enforcement**: `chores-authorize.sh clear` is idempotent (unit-tested: clear → marker absent). The run-start unconditional clear and `run_id` binding are the **structural** backstop replacing cooperative-cleanup reliance — a leaked marker from a crashed run is inert **against a later /cchores run** because its `run_id` cannot match the later run's freshly-minted id (RS-009 closes the deterministic-branch-reuse hole UX-007). **Honest scope (MA-011, AP-040/PMB-020)**: the run_id nonce does NOT close the **crash-window** case — a manual/injected Edit on the SAME branch after `write` and before the next run's `clear`, while marker and manifest still share a `run_id`, is allowed. That is an **accepted residual** alongside the OQ-005 in-tree-write residual: SFG is a cooperative-loop guardrail (not a perimeter), affordance paths are non-security infra, and any resulting PR is never-merged + human-reviewed. A TTL bound (OQ-003) remains deferred, not delivered. Terminal-path clears remain SKILL.md discipline (prompt-level fast-path).
- **Guards against**: a stale/leaked marker silently authorizing a later run or manual session on the same (deterministic) chore branch name.
- **Test approach**: integration (run_id mismatch → BLOCK) + unit (idempotent clear)
- **Risk**: high

### INV-006: Mode-aware pre-selection SFG check (advisory early-abort)
- **Type**: should
- **Category**: security (advisory — RS-022)
- **Statement**: In explicit-issue mode the pre-selection SFG check does NOT abort when the *inferred* fix target is an infra-protected path, but DOES abort when the inferred target is a `SECRET_FLOOR` path. In no-arg mode any protected target aborts (v1). This is a **best-effort early abort**; its target is inferred from untrusted issue content before any diff exists, so **INV-007 (diff-based) is the authoritative SECRET_FLOOR/scope gate** — a benign-looking issue whose fix actually touches a floor path MUST be caught by INV-007, never relied on being caught here.
- **Boundary**: SFG guardrail boundary
- **Violated when**: a no-arg run proceeds on any protected target; or the suite relies on INV-006 (not INV-007) to catch a floor-touching fix from a benign-looking issue.
- **Enforcement**: the SECRET_FLOOR-classification axis is coded and unit-tested via the hook's side-effect-free `is_secret_floor()` (INV-008 tags — no re-enumeration, RS-012). The **mode axis** is routed through the same coded `cchores-diff-check.sh --mode` helper as INV-007 (R2-Q) so all four cells (mode × {infra, secret}) are real unit tests; if the mode branch instead stays SKILL.md prose, the invariant is honestly labeled "SECRET_FLOOR axis unit-tested; mode branch prompt-level (advisory, backstopped by INV-007)" and does NOT claim four testable cells. Plus a test proving INV-007 (not INV-006) catches a floor fix from a benign-looking issue.
- **Guards against**: v1 over-blocking (infra) and *early* affordance over-reach (secrets) — advisory only.
- **Test approach**: integration
- **Risk**: medium

### INV-007: Mode-aware post-cdebug diff check (authoritative scope/floor gate)
- **Type**: must
- **Category**: security
- **Statement**: In explicit-issue mode the post-`/cdebug` diff may touch `# affordance` infra paths, but the run MUST still abort if the diff touches (a) any `# secret-floor` path, OR (b) any shared-project-doc surface (`.correctless/ARCHITECTURE.md`, `.correctless/AGENT_CONTEXT.md`, `CLAUDE.md`, `README.md`, `.correctless/antipatterns.md`), OR (c) any protected path NOT in this run's `marker.allowed_paths` (RS-007). In no-arg mode any protected path in the diff aborts (v1). **Authority split (R2-D)**: legs (a) and (b) are **marker-independent → authoritative** (they derive from the DEFAULTS `# secret-floor` tags and a fixed doc list, not from the forgeable marker). Leg (c) reads `marker.allowed_paths`, which the spec accepts is Bash-forgeable (RS-002 residual), so leg (c) is a **guardrail against naive Edit/Write scope-creep only**, NOT authoritative against injection — an injected /cdebug that forges a wider `allowed_paths` defeats both INV-002(4) and this leg together. The authoritative confinement is (a)+(b)+never-merge+human review.
- **Boundary**: `/cchores` scope + SFG guardrail
- **Violated when**: an explicit-issue run opens a PR whose diff touches a secret-floor path or a shared-project-doc (authoritative legs); or leg (c) is described as authoritative against injection.
- **Enforcement**: coded `cchores-diff-check.sh` takes the changed-file list on **stdin** AND `--mode explicit|no-arg` AND `--allowed-paths <file>` as **explicit arguments** (R2-H — mode and scope are inputs, never inferred from ambient orchestrator state, so all cells are deterministically testable); it emits `abort:<reason>` / `ok`. The `# secret-floor` check reuses the hook's side-effect-free `is_secret_floor()` (INV-008 tags, RS-012). Tests feed real `git diff --name-only`-format fixtures (RS-020) across `{explicit, no-arg} × {in-scope # affordance, out-of-scope infra, # secret-floor, shared-doc}`, plus the RS-022 cross-check cell (benign-looking issue whose fix touches a floor path → caught HERE, not at INV-006). **Note**: the shared-doc leg has NO SFG runtime backstop (those docs aren't in DEFAULTS), so this coded diff check is its sole guard (inherited v1 behavior).
- **Guards against**: scope creep into shared docs / out-of-scope infra; secret writes reaching a PR.
- **Test approach**: integration
- **Risk**: high

### INV-008: DEFAULTS 3-way classification — deny-by-default, single-source, conservative eligible set
- **Type**: must
- **Category**: security
- **Statement**: Every line of the SFG `DEFAULTS` block carries exactly one inline classification tag — `# affordance` / `# secret-floor` / `# other-floor` (R2-C, single source of truth; replaces the duplicated `SECRET_FLOOR` list). Both `is_affordance_eligible()` and `is_secret_floor()` are **derived from these tags** (never re-enumerated). A protected path is affordance-eligible **iff** its matching DEFAULTS pattern is `# affordance`. Everything else — `# secret-floor`, `# other-floor`, any `custom_patterns` match (RS-021), and any untagged/newly-added DEFAULTS line — is **floor → BLOCKED** at runtime (deny-by-default). **Conservative eligible set (R2-A/B, user-selected 2026-07-06)**: `# affordance` is limited to **non-security infra scripts** — `scripts/prune-scan.sh`, `scripts/harness-fingerprint.sh`, `scripts/build-dashboard.sh`, `scripts/gen-test-inventory.sh`, `scripts/cross-feature-intel.sh`, `scripts/compute-session-cost.sh`, and peers of that kind. **Never `# affordance`** (→ `# other-floor` or `# secret-floor`): the security/sole-writer guards (`scripts/override-scrutiny.sh`, `scripts/audit-record.sh`, `scripts/meta-record.sh`, `scripts/config-update.sh`, `scripts/autonomous-decision-writer.sh`, `scripts/supervisor-mandate.sh`, `scripts/review-triage.sh`, `scripts/security-scan.sh`, `scripts/wf/*.sh`), `scripts/lib.sh` (SFG's own trust dependency), all runtime-state artifacts (`workflow-state-*.json`, `intent-*.md`, `auto-policy.json`, the marker), the sanctioned writers (`scripts/chores-authorize.sh`), and all `# secret-floor` patterns. **Inclusion rule**: a DEFAULTS pattern may be tagged `# affordance` only if a fix to it cannot weaken a security control, a sole-writer contract, SFG's own matching, or run state — otherwise `# other-floor`.
- **Boundary**: SFG guardrail boundary
- **Violated when**: a security/sole-writer script, `lib.sh`, a state artifact, the marker, a `custom_patterns` match, a `# secret-floor` pattern, or any untagged DEFAULTS line is treated as affordance-eligible; or `is_secret_floor()`/`is_affordance_eligible()` is defined by a separate enumeration instead of the tags; or the classification test hardcodes its own copy of DEFAULTS.
- **Enforcement**: **runtime deny-by-default** in the hook (membership requires an explicit `# affordance` tag). `tests/` structural test parses the DEFAULTS block from the actual `hooks/sensitive-file-guard.sh` between the anchored delimiters `^DEFAULTS="` … `^"$` (AP-032 parse-anchor pinning, RS-012) and asserts every line is tagged exactly once; a keyword heuristic (`key|secret|credential|token|password|pem|rsa|ed25519|keystore`) flags any `# affordance` line that looks secret-adjacent; source↔mirror parity asserted for the tagged block. **Behavioral tests (prove not-a-no-op AND not-over-reach, R2-A/B)**: a real backlog path (`scripts/prune-scan.sh`) with a valid marker on the matching branch → ALLOWED; a security guard (`scripts/override-scrutiny.sh`) and `scripts/lib.sh` with the same valid marker → BLOCKED; a fixture-injected untagged DEFAULTS line → BLOCKED at runtime (proves deny-by-default has a runtime instance, not only a CI check — R2-P).
- **Guards against**: silent drift making a security guard, secret, or state artifact writable under a marker; a duplicated secret list drifting from the tags.
- **Test approach**: unit (structural, anchored parse) + integration (runtime allow/deny cells)
- **Risk**: high

### INV-009: Floor-immutability under the affordance (fail-closed, set-equality, trust-dep closure)
- **Type**: must-not
- **Category**: security (guardrail)
- **Statement**: Two legs, now cleanly separated by the conservative eligible set (R2-E). **(a) Hook classified-region immutability** — the `sensitive-file-guard.sh` file is NOT in DEFAULTS (freely Edit/Writable, EA-004), so a chore fix produced under the affordance MUST NOT alter the DEFAULTS `# affordance`/`# secret-floor`/`# other-floor` tag classification, the allowlist logic, or the marker-verification code; any such change aborts and defers to human review (a legitimate fix to a *different* hook region, e.g. #215 heredoc extraction, is allowed). **(b) Trust-dependency closure** — `scripts/lib.sh` (`canonicalize_path`/`config_file`) and everything the hook `source`s are classified **`# other-floor`** (never affordance-eligible, INV-008), so INV-002 **already blocks** any Edit/Write to them under the affordance. No function-body-hash comparison is needed (R2-E): the immutability of the trust dependencies is a corollary of their ineligibility, not a separate check. A chore that genuinely needs to fix `lib.sh` defers to human (the AP-037 lift-and-restore / manual path), which is the correct outcome for SFG's own trust root.
- **Boundary**: SFG guardrail boundary
- **Violated when**: an explicit-issue run's diff changes the DEFAULTS tag classification, the allowlist/marker-check logic (leg a); OR the leg-(a) immutability check fails open on a moved/deleted sentinel; OR `lib.sh`/a source dependency is ever tagged `# affordance` (which would break leg b's ineligibility — caught by INV-008's inclusion rule).
- **Enforcement**: leg (a) — the post-cdebug check re-extracts the tag classification (the `# affordance`/`# secret-floor`/`# other-floor` sets) from both base-branch and head versions via the **same INV-008 anchored parser** and asserts set-equality (tests the property, not a byte region — RS-013); **fails closed** if the anchor delimiters are absent/moved/duplicated in either version. Leg (b) — no runtime check; enforced structurally by INV-008 classifying `lib.sh`/source-deps as `# other-floor` (a test asserts they are never `# affordance`). Tests: a fix changing a tag → abort; a fix moving/deleting the DEFAULTS anchor → abort; a fix to an unrelated hook function → ok; an attempt to Edit `lib.sh` under a valid marker → BLOCKED by INV-002. **Scope note**: leg (a) protects PR-reachability; the in-tree write window during the run is an accepted residual (OQ-005).
- **Guards against**: in-run self-weakening of the affordance's own guards or their trust dependencies, then exploiting the weakened floor in a later PR.
- **Test approach**: integration
- **Risk**: high

### INV-010: Affordance-mode PR review banner (broadened)
- **Type**: must
- **Category**: functional
- **Statement**: **Any** PR produced under the affordance (explicit-issue mode, marker was minted) MUST carry a prominent banner naming the protected path(s) edited under authorization and the authorizing issue number (RS-017). When the diff touches `hooks/sensitive-file-guard.sh` or an SFG trust dependency (`scripts/lib.sh`), the banner escalates to the guard-self-edit form (`⚠ This chore edits sensitive-file-guard.sh / its trust dependency — the guard that authorized this run. Review with extra care.`). The INV-016 run report also records that the affordance was exercised and on which paths (RS-017 runtime visibility of the v1→v2 grant).
- **Boundary**: `/cchores` scope
- **Violated when**: an affordance-mode PR omits the banner, or a guard/trust-dep edit omits the escalated form.
- **Enforcement**: banner injection lives in the coded egress chokepoint `cchores-emit.sh` (behind a `--guard-touched`/`--affordance-paths` input derived from the changed-file list — RS-010/RS-017), unit-testable against the real emitter (banner present with the flag/paths, absent without). Test asserts the base banner on any affordance PR and the escalated banner when the diff includes the hook or `lib.sh`.
- **Guards against**: an affordance-mode protected-infra change (the human backstop the PMB-020 honesty argument depends on) landing without an elevated-review signal.
- **Test approach**: integration
- **Risk**: medium

### INV-011: Marker parse fails closed (PAT-001 clause 5)
- **Type**: must
- **Category**: security
- **Statement**: Any error reading or parsing the marker **OR the run manifest** — file present but unparseable/truncated, missing `branch`/`issue`/`run_id`/`allowed_paths`, non-numeric `issue`, or a manifest whose `run_id` cannot be read (R2-J) — yields **no authorization → the protected write is BLOCKED** (fail-closed). The marker/manifest reads MUST NOT adopt the `custom_patterns` degrade-to-DEFAULTS fail-*open* carve-out, and both are resolved against the **target tree** (INV-002), not cwd. All new marker/branch/manifest variables are initialized before use (`set -u` safety), and every new code path exits the hook with exactly 0 or 2 (never 128/1) — RS-003/RS-015.
- **Boundary**: SFG guardrail boundary / PAT-001 clause 5
- **Violated when**: a corrupt/partial marker or manifest, or any non-0/non-2 exit, allows a protected write.
- **Enforcement**: guarded `jq` parse (`|| BLOCK`), guarded `git` read (`2>/dev/null || true`), guarded manifest read (`|| BLOCK`), initialized vars. The "no path emits 128/1" claim is **not statically decidable** (R2-G), so it is split into (i) **behavioral enumeration** — drive `run_hook_capture` with a protected target + present marker under EACH failure trigger and assert exit ∈ {0,2}: `git` binary absent (PATH-stripped), non-repo cwd, detached-HEAD fixture, bare-repo, mid-rebase, corrupt/truncated marker, marker missing each required field, missing/corrupt manifest; and (ii) a **guard-pattern lint tripwire** — assert every `git`/`jq` invocation on the affordance path is guard-suffixed (`2>/dev/null || …`) and no new bare command sits under `set -e` unguarded. Relabel from "structural test that no path emits 128/1" to "behavioral coverage of all git/marker/manifest failure triggers + guard-pattern lint."
- **Guards against**: guard inversion via a crash/parse-error path.
- **Test approach**: integration (behavioral trigger enumeration) + structural (guard-pattern lint)
- **Risk**: high

### INV-012: Skill↔hook capability handshake (version skew)
- **Type**: must
- **Category**: upgrade-compat
- **Statement**: Before writing the marker or relaxing its pre-selection gate, explicit-issue `/cchores` runs a **coded behavioral capability probe** against the *installed* hook and confirms `.correctless/scripts/chores-authorize.sh` exists. If the hook is not affordance-capable or the script is absent, `/cchores` **degrades to v1** (abort on any protected target) with a message naming `bash setup` as remediation — never a mid-run SFG wall or a raw `No such file` crash (RS-006).
- **Boundary**: `/cchores` scope (install-vs-source freshness layer)
- **Violated when**: explicit-issue mode mints a marker / relaxes its gate against an installed hook whose allowlist code is absent or stubbed, or dispatches the writer when the script is absent.
- **Enforcement**: **coded probe (R2-F, not a comment-grep)** — `chores-authorize.sh check-capability <installed-hook-path>` FEEDS the installed hook a known-good marker+branch fixture and asserts it actually **allows** an affordance-eligible write (behavioral, mirroring the STEP-4a `canonicalize_path` v1 sentinel probe); a hook that carries the `# SFG_AFFORDANCE_VERSION: 1` comment but a stubbed/merge-broken allowlist FAILS the probe (closes the comment-vs-code TOCTOU gap R2-F/DC-7 flagged). Returns 0 (capable) / non-zero + degrade-reason. This composes with (and is more precise than) `check_install_freshness()` (ABS-022 — the correct citation, replacing the stale "DRIFT-008") whose `source_ahead`/`modified` signal is routed into the degradation message. Unit tests: sentinel-less hook fixture → degrade + `bash setup`; sentinel-present-but-stubbed-allowlist fixture → degrade; script deleted → clean v1 abort.
- **Guards against**: a plugin-ahead-of-setup upgrade (or a partial hook) silently wedging the feature mid-run.
- **Test approach**: integration (behavioral probe) + unit (degrade cells)
- **Risk**: high

### INV-013: Legible affordance-failure messages (recovery UX)
- **Type**: must
- **Category**: functional (UX — RS-018)
- **Statement**: When SFG blocks a write because a marker exists but the allowlist predicate fails, it emits a **distinct, affordance-aware** block message naming which leg failed (`marker.branch=<X>` vs `current=<Y>`; "branch name ≠ chore/issue-<N>-*"; "secret-floor path — never affordance-eligible"; "path not in this run's authorized scope"; "marker run_id mismatch") and the **correct** remediation (`re-run /cchores <N>` on the chore branch), NOT the interactive lift-and-restore text that the current generic block message points at (which the Scope excludes for autonomous mode). `/cchores` verifies the marker persisted and binds the current run immediately after `write` and before `/cdebug` dispatch, aborting legibly if not. Secret-floor and pre-selection aborts carry a legible reason in the INV-011-of-cchores abort comment + the run report, with a pointer to the affordance contract.
- **Boundary**: `/cchores` scope + SFG block-message surface
- **Violated when**: an affordance predicate failure emits the generic AP-037 lift-and-restore wall, or a silent block with no reason.
- **Enforcement**: block-message content covered in the INV-002/INV-003 behavioral tests (assert the message, not just the exit code); post-write marker verification step in SKILL.md before dispatch.
- **Guards against**: silent-failure that resurrects the AP-037 friction the feature exists to remove, with a misleading signpost.
- **Test approach**: integration
- **Risk**: medium

### INV-014: Marker sole-writer + never-in-commit
- **Type**: must
- **Category**: security (sole-writer, ABS-029/047 family)
- **Statement**: `scripts/chores-authorize.sh` is the sole cooperative write path to the marker. The **real structural block** on a naive marker Edit/Write is **SFG DEFAULTS membership** — the marker path + the writer (three-form) are in DEFAULTS, marker classified `# other-floor` (never-affordance-eligible, so INV-002 blocks even a marker that lists itself in `allowed_paths`), the writer registered in `scripts/sanctioned-*-writers.tsv`. **Defense-in-depth (R2-K)**: because allowed-tools globs have NO exclusion syntax (`Write(.correctless/artifacts/*)` cannot be narrowed to "except the marker"), the grant is left intact and the marker is excluded via a `disallowed-tools: Write(.correctless/artifacts/chores-protected-authorized.json)` entry in `skills/cchores/SKILL.md` (idiomatic — /cchores already carries `disallowed-tools`; precedence makes disallow win). The marker **never enters a commit** — pinned to the existing `git restore --staged .correctless/artifacts/` step, not to any project's `.gitignore` shape (RS-024). (Write-*provenance* contract, not an ABS-029 existence-gate — marker *absence* is the safe state.)
- **Boundary**: SFG guardrail boundary / `/cchores` egress
- **Violated when**: the marker/writer are absent from DEFAULTS; the `disallowed-tools` marker entry is missing; or a staged marker reaches a commit.
- **Enforcement**: DEFAULTS membership (three-form) + registry entry (structural tests, mirroring ABS-047/042) + a structural test asserting the `disallowed-tools` marker entry is present; a test that a staged marker is stripped by `git restore --staged` before commit. (No test asserts a non-expressible allow-glob narrowing — R2-K.)
- **Guards against**: naive self-authorization by editing the marker; marker leaking into a PR.
- **Does NOT guard against**: a Bash-redirect write to the marker (AP-040 residual).
- **Test approach**: structural + integration
- **Risk**: high

### INV-015: Test-substrate fidelity (real fixtures, no-arg parity, install parity)
- **Type**: must
- **Category**: testability (AP-031/AP-024)
- **Statement**: At least one INV-002 test pipes the **real** `chores-authorize.sh write --issue N` output into the **real** hook over a `git init` fixture (writer↔reader format coupling, RS-020/AP-031/PMB-010) — the marker schema (`{branch, issue, run_id, allowed_paths, authorized_at}`) is format-pinned and cross-referenced to the writer's actual output. A **no-arg golden-output regression** compares the v1 pre-selection abort output — emitted by the **coded** producer `cchores-emit.sh` (or the coded pre-selection classifier), not free-form SKILL.md prose (R2-R) — byte-for-byte against a committed golden file. A source-vs-installed **count-parity** test asserts `count(scripts/*.sh) == count(correctless/scripts/*.sh)` (AP-024/RS-025). All git-based cells across INV-002/003/009/011/012/015 use a **single shared `setup_git_test_env` helper** (git init + `chore/issue-<N>-*` branch + commit + optional second worktree for the AP-035 cell), borrowed from `tests/test-cchores-infra.sh`, so no test re-rolls a divergent fixture (F9).
- **Boundary**: test infrastructure
- **Violated when**: marker tests hand-synthesize the marker; the no-arg golden compares free-form prose with no coded producer; no script count-parity test exists; git cells re-roll ad-hoc fixtures.
- **Enforcement**: `# Source:` citation on the real-marker fixture; the shared `setup_git_test_env` helper; the three tests above.
- **Guards against**: writer↔reader divergence (PMB-010), silent no-arg behavior change, silent script-install drift (PMB-003).
- **Test approach**: unit + integration
- **Risk**: medium

## Prohibitions

### PRH-001: No affordance in no-arg mode
- **Statement**: Auto-select (no-arg) `/cchores` never writes the marker and never lifts SFG protection; any protected fix target aborts at pre-selection (v1 PRH-003 unchanged).
- **Detection**: structural test (no marker-write on the no-arg path) + behavioral test (no-arg run with a protected target aborts).
- **Consequence**: an injection-exposed auto-select could touch protected infra.

### PRH-002: The affordance never relaxes the secret floor, custom_patterns, or its own guards
- **Statement**: No marker, branch, mode, or unclassified-drift ever makes a `SECRET_FLOOR` pattern, a downstream `custom_patterns` pattern, or an unclassified DEFAULTS pattern writable (INV-003 + INV-008 deny-by-default); no chore fix may weaken the SECRET_FLOOR/affordance-eligible classification, the allowlist/marker-check logic, or SFG's trust-dependency closure `scripts/lib.sh canonicalize_path` (INV-009); the marker itself cannot be edited to self-authorize (INV-014). **Honest scope (AP-040)**: these are naive-Edit/Write guardrails, not a perimeter — a Bash-mediated write to a floor path is the accepted residual, contained by redaction + never-merge + human review, not by SFG.
- **Detection**: INV-003 behavioral test (floor + canonicalization-edge blocked with valid marker); INV-008 deny-by-default + custom_patterns test; INV-009 set-equality/trust-dep diff test; INV-014 marker-in-DEFAULTS test.
- **Consequence**: naive key/credential planting, downstream-protection weakening, or in-run guard-weakening.

### PRH-003: Never merge; ≤1 comment (inherited, restated)
- **Statement**: The affordance changes nothing about `/cchores` never merging (PRH-004 of cchores), the ≤1-comment rule, or outbound redaction. The human PR review is the load-bearing backstop for every affordance-mode fix.
- **Detection**: inherited cchores tests (no merge subcommand in `allowed-tools`).
- **Consequence**: an unreviewed protected-infra change lands.

## Boundary Conditions

### BND-001: Untrusted issue body under a branch+file-scoped affordance
- **Boundary**: TB-009 — untrusted GitHub issue content → autonomous orchestrator (BND-001 of cchores). The affordance widens what a selected issue may *reach* (opt-in infra) inside TB-009's "no human checkpoint" envelope; TB-004d's "if extended … MUST be revisited" trigger is thereby engaged and this spec is that revisit.
- **Input from**: untrusted issue author (title/body flow into `/cdebug` via the cchores nonce fence) AND the marker file + `git rev-parse` output, which become new local inputs to a security ALLOW decision — the allow-path is only as trustworthy as the (Bash-forgeable) marker.
- **Validation required**: the body stays nonce-fenced data-not-instructions; the affordance's structural bounds are deny-by-default eligibility (INV-008), the secret floor (INV-003), branch+file+run_id binding (INV-002/005), fail-closed marker parse (INV-011), floor+trust-dep immutability (INV-009), the writer `--issue` contract (INV-001/004), never-merge review + banner (PRH-003/INV-010), and outbound redaction (INV-013 of cchores). The residual — a motivated injection Bash-evading SFG (incl. self-writing the marker, RS-002) — is the pre-existing AP-040 limitation and is explicitly NOT closed here.
- **Failure mode**: fail-closed (any ambiguity, parse error, or non-0/non-2 hook exit → block the write / abort the run — INV-011).

## STRIDE Analysis

### STRIDE for TB-009 (untrusted GitHub issue ingestion) / TB-004d (issue-selection authority), under the affordance
- **Spoofing**: a hostile issue tries to look "authorized." Mitigation: authorization is the human's explicit `/cchores <N>` + the writer's `--issue` contract (INV-001), not any issue content. **Residual**: an injected `/cdebug` can Bash-forge the marker on its own legit chore branch (RS-002) — contained not by INV-001 but by INV-007 + never-merge + redaction.
- **Tampering**: injected body drives `/cdebug` to edit an unrelated protected file. Mitigation: allowed only for opt-in affordance-eligible infra (INV-008 deny-by-default), only on the branch (INV-002), only for the scoped `allowed_paths` (INV-007/RS-007), floor-immutable incl. trust deps (INV-009), surfaced in the never-merged PR banner (INV-010/PRH-003). **Residual**: a Bash-mediated write (AP-040) — accepted.
- **Repudiation**: `/cchores` logs the authorization decision (autonomous-decision-writer, INV-012 of cchores); the marker records `issue`/`branch`/`run_id`/`allowed_paths`/`authorized_at`; the PR banner (INV-010) + run report record the affordance was exercised and on which paths.
- **Information disclosure**: the SECRET_FLOOR (INV-003) blocks a **naive Edit/Write** to a key/credential; it does **NOT** stop reads (SFG gates neither reads nor Bash) nor a Bash-mediated write — so it is a speedbump, not an exfil control. The authoritative exfiltration defense is **outbound redaction (INV-013 of cchores) + never-merge + human review**, unchanged.
- **DoS**: n/a (single-issue, fail-closed).
- **Elevation of privilege**: in-run weakening of SECRET_FLOOR/allowlist or an SFG trust dependency (`lib.sh canonicalize_path`) then exploiting it. Mitigation: INV-009 fail-closed set-equality immutability over the classified block + trust-dep closure; SECRET_FLOOR checked first and deny-by-default each invocation; self-authorization by marker-edit blocked by INV-014 (marker in DEFAULTS). **Residual**: in-tree write window (OQ-005) + Bash forge (AP-040).

### STRIDE for TB: SFG guardrail boundary (ABS-045)
- **Tampering / EoP**: forging the marker to authorize a non-chore branch or a broader scope. Mitigation: SFG binds the marker to byte-exact target-tree branch AND numeric `chore/issue-<N>-*` name AND `run_id` AND `allowed_paths` (INV-002/005); a forged marker for another branch/run is inert; a naive Edit/Write to the marker itself is blocked (INV-014). Cooperative-model Bash-forge residual acknowledged (BND-001/AP-040).
- **EoP via guard inversion**: a git/parse failure exiting non-0/non-2 would be treated as ALLOW. Mitigation: INV-011 exit-code discipline (guarded git/jq, initialized vars, structural test that no path emits 128/1).

## Environment Assumptions
- **EA-001**: SFG runs as a Claude Code PreToolUse hook in the cooperative agent loop — a guardrail, not a perimeter (refs PMB-020/AP-040). Consequence if wrong: none; the spec already assumes this. It inspects only the Edit/Write tool-path, never Bash.
- **EA-002**: `git rev-parse --abbrev-ref HEAD`, run **against the git working tree that contains the Edit/Write target** (`git -C "$(dirname "$canonical_target")" ...`, RS-008), yields that tree's branch. The call is **guarded** (`2>/dev/null || true`) so failure/absence/`HEAD`/non-repo → empty → no marker match → BLOCK (exits only 0 or 2 per PAT-001 clause 5 — RS-003). Consequence if the guard is omitted: `set -e` aborts the hook with exit 128, which the harness treats as ALLOW — the guard is load-bearing.
- **EA-003**: the marker lives under `.correctless/artifacts/` (gitignored at `.gitignore:42`, so the earlier "add gitignore for the marker" scope item was redundant and is dropped — RS-024). Marker-never-in-commit is pinned to the `git restore --staged .correctless/artifacts/` step (INV-014), NOT to each project's `.gitignore` shape, so an upgraded project with a pattern-based gitignore is still safe.
- **EA-004** (CORRECTED — RS-019): `hooks/sensitive-file-guard.sh` is **NOT** in its own DEFAULTS list (verified against L156-234) and `.claude/rules/sfg-deliverable.md` lists only `agents/fix-diff-reviewer.md` + `scripts/meta-record.sh`. Editing the hook triggers **no** SFG block, so **no lift-and-restore is required to develop the hook** — the earlier claim was false. (This is also *why* INV-009/INV-010 exist as the `/cchores`-side guards: the hook is freely Edit/Writable.) **However**, adding `scripts/chores-authorize.sh` to DEFAULTS (INV-014) makes THAT script a new AP-037 deliverable — developing it needs the lift-and-restore affordance for its own file.
- **EA-005** (NEW — RS-008): the affordance requires the editing agent to **share the orchestrator's working tree on the chore branch**. `/cchores` uses a shared working-tree lock (INV-015 of cchores), not worktree isolation, so the normal `/cchores → /cdebug` flow satisfies this. If `/cdebug` or any editing agent ever runs under `isolation:worktree` (base-ref = default branch, per project convention) or detached HEAD, the branch won't match and the affordance fails closed (BLOCK) — legibly, per INV-013.
- **EA-006** (NEW — RS-007-class): the hook gains a `git` binary dependency it did not have before. If `git` is absent, the guarded read yields empty → BLOCK (safe), but the affordance silently never works; the version handshake / a one-time diagnostic (INV-012) surfaces this rather than leaving it as an opaque wall. `git` absence must NOT change SFG's baseline blocking behavior for the 99% non-affordance path.

## Open Questions
- **OQ-001** (RESOLVED, schema expanded): Marker is a **single fixed path** `.correctless/artifacts/chores-protected-authorized.json` with schema `{branch, issue, run_id, allowed_paths, authorized_at}` (expanded per RS-007 `allowed_paths` and RS-009 `run_id`). SFG checks byte-exact `marker.branch == target-tree branch`, numeric `issue`, `run_id == current manifest run_id`, and `canonical_target ∈ allowed_paths`.
- **OQ-002** (RESOLVED): The marker is minted only after suitability + idempotency pass — encoded in INV-004; the enforceable leg (writer `--issue` contract) is in INV-001, RED must assert both.
- **OQ-003** (RESOLVED — RS-009): Marker staleness is closed by the **per-run `run_id` binding** (INV-005) + unconditional clear-at-start, NOT by cleanup + branch-binding alone (which UX-007 showed is defeatable under deterministic `chore/issue-N` reuse). An `authorized_at` TTL remains optional additional hardening but is no longer the only bound.
- **OQ-004** (RESOLVED): Affordance-mode PRs carry a review banner, escalated for guard/trust-dep edits — encoded as INV-010 (broadened per RS-017).
- **OQ-005** (NEW, deferred): should the in-tree write window during a run (INV-009 protects PR-reachability, not the live working tree) be closed by resetting SFG + `scripts/lib.sh` to the base version before `/cdebug` dispatch? Recommendation: accept the in-tree residual for v2 (the write is caught before any PR by INV-007/INV-009 and never merges per PRH-003); revisit if a concrete exploit against the in-tree window is demonstrated.
