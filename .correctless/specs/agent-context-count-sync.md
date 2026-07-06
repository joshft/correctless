# Spec: Decouple the test-count invariant from the INV-010-protected doc (#219, Option 2)

## Metadata
(keep in sync with templates/spec-lite.md and templates/spec-full.md)
- **Created**: 2026-07-06
- **Status**: reviewed
- **Impacts**: cchores (INV-010 — explicitly UNCHANGED; TB-009 touched-not-weakened), ap031-fixture-divergence (R-006(c)), ctdd/cdocs (regeneration wiring)
- **Branch**: feature/agent-context-count-sync-affordance
- **Research**: null (design informed by a codex/GPT-5.5 cross-model review of the SUPERSEDED Option 1 — `.correctless/artifacts/codex-review-agent-context-count-sync.md` — and a 6-agent /creview-spec pass — `.correctless/artifacts/review-spec-findings-agent-context-count-sync.md`)
- **Intensity**: high
- **Recommended-intensity**: high
- **Intensity reason**: touches the security invariant INV-010's surrounding logic, `/cchores`, and a suite gate; project floor `high`
- **Override**: none
- **Review**: /creview-spec 2026-07-06 — 6-agent pass (18 findings RS-001..018, all accepted; RS-001..017 incorporated, RS-018 a follow-up) PLUS a manual codex/GPT-5.5 Option 2 cross-model pass (10 findings EXT-001..010, all accepted; incorporated). codex caught the RS-003/RS-007 self-contradiction (EXT-001/002/003) — the /cchores sequencing is corrected below (stage tests → regen → stage artifact → commit; index-based count; generator-side consumer guard). See the findings artifact + Disposition Log.

## Context
GitHub #219: `/cchores`'s INV-010 forbids the chore diff from touching shared prose docs
(`AGENT_CONTEXT.md`, `ARCHITECTURE.md`, `CLAUDE.md`, `README.md`), but
`tests/test-ap031-fixture-divergence.sh` **R-006(c)** requires `AGENT_CONTEXT.md` to document a
test-file count `>= actual` (`find tests -maxdepth 1 -name 'test*.sh' | wc -l`). A `/cchores`
fix whose TDD repro is a **net-new** test file bumps actual, the documented count goes stale, and
the one edit that clears it (bumping the number in `AGENT_CONTEXT.md`) is INV-010-forbidden — so a
verified fix aborts (observed: PR #218, and #252 this session; verified #252 fix retained on
branch `chore/issue-252-…`, commit `3486f49`).

The root cause is a **derivable fact (the test count) hard-coded in a hand-maintained,
edit-restricted prose doc**, with a blocking suite gate enforcing their agreement. This spec
**decouples** (#219 Option 2): the authoritative count (**for the R-006(c) gate and the
`AGENT_CONTEXT.md` figure**) moves to a small **tracked, unprotected, generated** artifact that
any actor — `/cchores`, `/cdocs`, `/ctdd`, a human, CI — can regenerate freely; R-006(c) checks
that artifact against actual (freshness guard preserved, exactly); and the `AGENT_CONTEXT.md`
figure becomes informational. **INV-010 is left completely unchanged** — no narrow exception, no
diff-forensics, no count-sync writer, no SFG affordance. This eliminates the whole class of hazards
a cross-model review (codex/GPT-5.5) flagged against the affordance approach (Option 1): the
worktree-vs-branch-diff bug, the gameable unlock precondition, and patch-parsing brittleness all
become moot because there is no exception to bound.

**Scope-honesty note (RS-012):** this feature does NOT make `tests/test-inventory.json` the
project-wide single source of truth for "number of tests." Two other count gates exist and are
**out of scope, left as-is**: (a) `CONTRIBUTING.md` carries a parallel `[0-9]+ test files` figure
enforced by `tests/test-architecture-drift.sh` (AP-005) and read by `build-dashboard.sh` /
`test-agent-hooks.sh`, asserted against a different glob (`find tests -name 'test-*.sh'`,
recursive) — this is NOT a deadlock (`CONTRIBUTING.md` is not an INV-010 doc, so `/cchores` may
edit it); (b) `scripts/prune-scan.sh scan_counts` reads the `AGENT_CONTEXT.md` Tests-row figure.
The claim this spec makes is narrow and true: the **R-006(c) gate** and the **`AGENT_CONTEXT.md`
figure** are decoupled from the hand-maintained prose onto the generated artifact. INV-007 records
the `prune-scan` interaction explicitly.

## Scope
**In scope**
- New tracked, unprotected count artifact **`tests/test-inventory.json`**
  (`{"schema_version": 1, "test_file_count": N}` — deterministic, no timestamp → idempotent regen).
- New generator `scripts/gen-test-inventory.sh` (+ mirror `correctless/scripts/…`) exposing a
  **single shared count command** with an explicitly-pinned repo-root resolution (INV-002) and a
  `write` (regenerate) + `count` (print) subcommand.
- Repoint `tests/test-ap031-fixture-divergence.sh` **R-006(c)** to read the artifact and assert
  `test_file_count == actual`, using the generator's shared count command for `actual` (parity).
  R-006(a)/(b) (the AP-031 reference checks on `AGENT_CONTEXT.md`) are unchanged.
- **Consumer-scoped** regeneration wiring at the points where test files change, with the corrected
  index-based staging order (INV-006 / EXT-001/002): `/ctdd` (after RED **stages** its tests, before
  the suite), `/cchores` (after GREEN — **stage the fix's test files → regen → stage the artifact →**
  the single scoped commit), `/cdocs` (docs phase). Each runs the generator and stages
  `tests/test-inventory.json` **only when the R-006(c) consumer is present** (backed by a
  generator-side no-op guard, INV-003/EXT-006) and no-ops gracefully otherwise (INV-006 / RS-001).
  Callers surface a generator failure (INV-006 / RS-006).
- `allowed-tools` updates for `/cchores`, `/ctdd`, `/cdocs` (AP-008). `/cchores` `disallowed-tools`
  baseline is UNCHANGED (full Group B, INV-009 / RS-014).
- Mark the `AGENT_CONTEXT.md` Tests-row figure informational (`~N test scripts`) with an
  authoritative-source pointer to `tests/test-inventory.json`, since R-006(c) no longer reads it
  (INV-007 / RS-017).
- New ABS-048 architecture entry (deliverable spec below) recording the generated-artifact
  abstraction with its explicit sole-writer / SFG deviation note (RS-008).
- Any **new test script** added by this feature MUST be named `tests/test-*.sh` so it is picked up
  by `commands.test` and CI's existing `tests/test-*.sh` glob — no manual registration list edit is
  needed (RS-015).
- Distribution mirror + `sync.sh --check` parity; structural + behavioral tests.

**Out of scope (Won't Do)**
- **Any change to `/cchores` INV-010.** No shared-doc exception, no relaxation. INV-010 stays absolute.
- A surgical `AGENT_CONTEXT.md` count-sync writer, byte-identical diff-bounding, or an SFG/AP-037
  affordance (all were Option 1; deleted by this pivot).
- Adding the count artifact to SFG DEFAULTS (it is intentionally unprotected so every actor can regenerate it).
- Placing the artifact under `.correctless/meta/` or `.correctless/artifacts/` (both gitignored /
  PR-stripped — it would never reach CI). See PRH-001.
- A git pre-commit auto-regeneration hook (full automation) — attractive but deferred (OQ-001); v1
  relies on skill wiring + R-006(c) as the enforcement/backstop.
- **Unifying the CONTRIBUTING.md / prune-scan.sh parallel count gates** (RS-012) — pre-existing,
  separate, non-deadlocking; a future cleanup, not this feature.
- **Adding a test-deletion or net-new-test legitimacy control to `/cchores`** (RS-013) — R-006(c) is
  a consistency gate, not a tamper control; test-deletion is `security-scan.sh`'s domain. Accepted risk.
- **Fixing the external-review producer's bare-`codex` bin config** (RS-018) — a real but separate
  producer/config defect; re-verify machine-specific details before filing.
- Re-running / landing #252 itself (a follow-up once this ships).

## Complexity Budget
- **Estimated LOC**: ~160 (generator ~70 with pinned resolution + hardened atomic write, R-006(c)
  rewire ~30, skill prose ~40, artifact trivial, ABS entry ~10)
- **Files touched**: ~11 (generator + mirror; R-006(c); 3 skills + mirrors; AGENT_CONTEXT.md figure;
  new artifact; new test(s); ARCHITECTURE.md ABS-048)
- **New abstractions**: 1 — **ABS-048** (generated count artifact + shared count command;
  deliberately NOT a sole-writer, NOT SFG-protected — see the ABS-048 deliverable).
- **Trust boundaries touched**: 1 **touched, 0 weakened** (RS-016). `/cchores`'s **TB-009**
  (untrusted issue → autonomous orchestrator → outward push/PR) is *touched* — the feature adds a
  new tracked file to the chore PR's staged set and a `Bash(…gen-test-inventory.sh*)` capability —
  but NOT *weakened*: the artifact is deterministic filesystem-derived content, never issue-text
  derived, so TB-009's INV-001 positive-gate provenance is preserved. INV-010 is a `/cchores` **skill
  invariant**, not a registered architecture TB.
- **Risk surface delta**: low (no security invariant is weakened; a derived fact moves to an
  unprotected generated file). Residual risk concentrated in **wiring + distribution boundary**, not security.

## Invariants

### INV-001: Authoritative, deterministic, idempotent count artifact
- **Type**: must
- **Category**: data-integrity
- **Statement**: the authoritative test-file count lives in `tests/test-inventory.json` as
  `{"schema_version": 1, "test_file_count": N}` with **no timestamp or other nondeterministic
  field**. The serialization is **byte-pinned** — the generator emits the JSON via a fixed
  `printf` template (a single canonical form with a fixed trailing newline), NOT via `jq`
  pretty-printing, so the bytes are identical across jq 1.7/1.8 and across platforms (RS-004 /
  codex-adjacent AP-011). Regenerating it when the count is unchanged is a **byte-identical no-op
  that rewrites no bytes** (idempotent — no churn; the #252 lesson). It is a tracked, git-committed file.
- **Boundary**: ABS-048 (generated count artifact)
- **Violated when**: the artifact carries a nondeterministic field; a no-op regen rewrites bytes
  (new inode/mtime); or serialization differs across jq versions/platforms.
- **Enforcement**: schema + serialization pinned here; behavioral test (INV-001 Test approach)
  runs `write` twice and asserts (a) sha256 identical, (b) **inode + mtime unchanged** on the 2nd
  run, and (c) the 2nd run prints the `no change` token — content equality alone is INSUFFICIENT
  (a `mktemp && mv`-every-call writer passes content equality yet churns; RS-004/Testability F3).
- **Guards against**: AP-024/#252 non-idempotent-generation churn
- **Test approach**: unit
- **Risk**: medium

### INV-002: Single shared count command — pinned repo-root, pinned universe, writer/consumer parity
- **Type**: must
- **Category**: parity
- **Statement**: exactly one command computes "actual", exposed as `gen-test-inventory.sh count`.
  Three properties are pinned so writer and consumer can never disagree:
  1. **Command shape** — the index-based command in property 3, counting NUL-delimited direct-child
     `test*.sh` entries (the SAME `test*.sh` basename glob R-006(c) has always used, which includes
     `test-helpers.sh`). The generator MUST force `LC_ALL=C` internally (not rely on the caller); any
     `wc -l` used in the count path is normalized with `tr -d ' '` to defuse BSD-vs-GNU leading
     whitespace (RS-004 / Assumptions F7). Counting NUL-delimited entries (e.g. `grep -zc .` or
     `tr '\0' '\n' | grep -c .`) avoids miscounting filenames containing newlines.
  2. **Repo-root resolution — pinned two-layout resolver (RS-002 / EXT-007 / Assumptions F1-F5)** —
     `<repo>` is resolved from the generator's own `${BASH_SOURCE[0]}` script directory by an
     **explicit two-layout case split**, NOT from `$PWD` (incidental) and NOT from
     `git rev-parse --show-toplevel` (breaks in `/ctdd` probe worktrees, submodule vendoring, and
     under `GIT_DIR`/`GIT_WORK_TREE`): the **source** form `scripts/gen-test-inventory.sh` resolves
     root = `<scriptdir>/..`; the **installed** form `.correctless/scripts/gen-test-inventory.sh`
     resolves root = `<scriptdir>/../..` (so it targets the **project** `tests/`, never
     `.correctless/tests/`). The generator then verifies the **consumer marker**
     `<root>/tests/test-ap031-fixture-divergence.sh` exists and, if absent, no-ops (see INV-003
     generator-side consumer guard / EXT-006). The resolver must be verified by test against four
     contexts: normal CWD, a non-repo CWD (`/tmp`), a `/ctdd` probe worktree, and the installed
     `.correctless/scripts/` path.
  3. **Count universe — index-based, direct-children (RS-003 / EXT-004 / EXT-005 / Assumptions F10)** —
     "actual" is computed over the **committed/staged index**, not the working tree, so an untracked
     scratch `tests/test-*.sh` cannot perturb it and a clean CI checkout computes the same value.
     The pinned command is `git ls-files --cached -z -- 'tests/test*.sh'` (the index already
     includes staged additions — do NOT union with a separate "staged-adds" list or the new test is
     double-counted, EXT-004), **post-filtered to direct children of `tests/`** (reject any path
     with a second `/` — preserving the historical `-maxdepth 1` semantics, EXT-005), then counted.
     See INV-004 for how `/cchores`/`/ctdd` staging ordering keeps this consistent with the committed tree.
  R-006(c) obtains "actual" from `gen-test-inventory.sh count` (never its own `find|wc`), so the two
  can never drift.
- **Boundary**: ABS-048 shared-command (codex review #8)
- **Violated when**: the generator and R-006(c) compute "actual" via different command shapes, via
  a different resolved `tests/` directory, or over a different file universe.
- **Enforcement**: R-006(c) invokes the generator's `count` subcommand; structural test asserts
  R-006(c) does not re-implement ANY counting primitive (`find`, `wc -l`, `grep -c`, `ls`-pipe,
  bash array length) computing "actual" (positive: it DOES call `count`; negative: it contains no
  other counter — RS-004/Testability F4); behavioral parity test (mutate the tree, assert the value
  R-006(c) uses equals `count` output). Resolution-context tests per property 2 above.
- **Guards against**: AP-032 (extraction/command drift), Assumptions F1-F7/F10 (resolution + universe drift)
- **Test approach**: unit + integration
- **Risk**: high

### INV-003: Generator contract — atomic write (glob-safe temp), tri-state, fail-loud, deviation-documented
- **Type**: must
- **Category**: functional
- **Statement**: **Generator-side consumer guard (EXT-006 / RS-001):** both `write` and `count`
  first resolve `<root>` (INV-002 two-layout resolver) and verify the consumer marker
  `<root>/tests/test-ap031-fixture-divergence.sh` exists. If it is absent, the generator **no-ops**
  (exit 0, emits `gen-test-inventory: no consumer — skipped`, writes nothing) — this executable,
  in-the-generator guard is the structural backstop for RS-001, so a downstream
  `.correctless/scripts/gen-test-inventory.sh write` run directly on a host project (even one with a
  `tests/` dir) cannot create or stage an orphan artifact. Skill-wiring scope (INV-006) is
  defense-in-depth on top of this, not the sole guard.
  When the marker IS present, `gen-test-inventory.sh write` recomputes actual (INV-002) and writes the artifact
  **atomically**: `mktemp` **in `tests/` itself** (same filesystem, so `mv` is a rename not a
  cross-device copy — RS-011/Assumptions F14) with a temp name that **cannot match the `test*.sh`
  count glob** (e.g. a dotfile `.test-inventory.json.tmp.$$`), a `trap` that removes the temp on any
  exit path (no orphan temp survives a failed write — RS-011/UX-006), then `mv` onto the target. It
  emits `0` + a success line on change, `0` + `no change` when already current (no bytes rewritten),
  and non-zero + a mechanical `gen-test-inventory: FAILED <reason>` token on **stdout** on any
  IO/tool failure (never exit 0 after an unlanded write; never leave a truncated target).
  `gen-test-inventory.sh count` prints the integer to **stdout only** and nothing else.
- **Boundary**: mirrors the sanctioned-writer **exit discipline** (`meta-record.sh`) — the tri-state
  and `FAILED <reason>` token — but is **deliberately NOT a sanctioned sole-writer**: no lock
  (single-file, last-write-wins acceptable), **NOT in SFG DEFAULTS**, and **any actor may write it**
  (`/ctdd`, `/cchores`, `/cdocs`, humans, CI). This full deviation is load-bearing and MUST be
  stated so a future SFG-hardening reflex does not protect it and re-create #219 (RS-008 / Design
  Contract #2). See ABS-048.
- **Violated when**: a partial/failed write returns 0; `count` prints extra text; the temp file
  matches `test*.sh` or lands on a different filesystem; a failed write leaves an orphan temp or a
  truncated target.
- **Enforcement**: unit tests over all three exit states + the atomic-write path; structural test
  that the script uses `mktemp`+`mv` (not a `>` redirect onto the target) and a non-`test*.sh` temp
  name; behavioral test that a forced write failure (unwritable dir / `jq` absent) yields non-zero +
  the FAILED token + an **unchanged** target + **no surviving temp**.
- **Guards against**: silent-telemetry-failure (PMB-005), #252 non-atomic write, RS-011 self-inflating temp
- **Test approach**: unit
- **Risk**: medium

### INV-004: R-006(c) checks the artifact against actual over the PR-reaching universe (exact, fail-closed, legible)
- **Type**: must
- **Category**: functional
- **Statement**: `tests/test-ap031-fixture-divergence.sh` R-006(c) reads `test_file_count` from
  `tests/test-inventory.json` and asserts it **equals** actual (INV-002).
  - **Count universe (RS-003 / EXT-004 / EXT-005):** "actual" and the committed artifact are both
    defined over the **index** (`git ls-files --cached`, direct children of `tests/` — INV-002
    property 3), NOT the working tree, so an untracked scratch `tests/test-scratch.sh` does not
    perturb it and a clean CI checkout computes the same value. **Staging order (corrected — EXT-001/002):**
    the generator must run **after** the fix's test files are staged (so they are in the index at
    count time) and the artifact must then **itself be staged** into the same commit. The prior
    "regen before the stage-set snapshot" wording (RS-007 v1) was WRONG: at pre-stage time a net-new
    `tests/test-foo.sh` is unstaged, so the index count returns the OLD value, the generator writes
    it, the later `git add` stages the new test, and CI sees N+1 tests vs an artifact of N → the
    deadlock reappears at the artifact. See INV-006 for the pinned `/cchores` sequence
    (stage tests → regen → stage artifact → commit).
  - **No band fallback (EXT-003):** the legacy `>= actual, <= actual+2` band is NOT a valid fallback
    for this failure — it tolerates over-count (doc ahead of reality) but the net-new-test case is
    artifact-stale-LOW (undercount), which the band rejects. Exact `==` over the index universe with
    the corrected staging order is the mechanism; there is no band retreat. (OQ-005 closed.)
  - **Failure legibility (RS-009):** a missing, malformed, OR **stale/mismatched** artifact → FAIL
    with a **copy-pasteable** remediation string naming the exact command `bash
    scripts/gen-test-inventory.sh write` (the source-repo form, since R-006(c) only runs there). The
    remediation is pinned for the count-mismatch branch too (the highest-frequency case), not only
    for missing/malformed.
  - R-006(a)/(b) (AP-031 reference checks on `AGENT_CONTEXT.md`) are unchanged. R-006(c) no longer
    reads any figure from `AGENT_CONTEXT.md`.
- **Boundary**: the freshness guard #219 must preserve (do NOT weaken/remove it)
- **Violated when**: R-006(c) passes with a stale/wrong artifact count; still couples to
  `AGENT_CONTEXT.md`; or an untracked working-tree file makes a green local run fail in CI.
- **Enforcement**: the assertion itself; behavioral tests over the full matrix (RS-010): current →
  PASS (using a **generator-produced** pass fixture, not hand-authored — kills PMB-010 divergence);
  stale → FAIL; missing → FAIL; and ≥4 malformed shapes each FAIL fail-closed with remediation —
  (i) invalid JSON, (ii) missing `test_file_count`, (iii) string-typed count `"5"` AND non-integer
  number `3.5` (validate with `jq -e '.test_file_count | (type=="number" and . >= 0 and floor == .)'`
  — a bare `| numbers` accepts `3.5`, EXT-009), (iv) `schema_version` absent or `!= 1`; plus
  (v) `jq`/parse-tool absent → fail-closed like PAT-001, never a silent bash integer-expr error
  (RS-010/Red Team #9). Each failure message asserted to contain the copy-pasteable remediation.
  Universe test: an untracked scratch `tests/test-*.sh` does NOT change `count` (RS-003).
- **Guards against**: AP-031 (format drift), the #219 deadlock, RS-003 CI-vs-local skew, RS-010 malformed gaps
- **Test approach**: unit (generator-produced + malformed fixtures) + integration
- **Risk**: high

### INV-005: INV-010 is unchanged; the artifact is unprotected and PR-staged (TB-009 touched-not-weakened)
- **Type**: must-not (regression guard)
- **Category**: security
- **Statement**: this feature makes **no** change to `/cchores` INV-010 and adds **no** shared-doc
  exception. `tests/test-inventory.json` is NOT one of the four INV-010 prose docs, is NOT in SFG
  DEFAULTS, and is NOT under `.correctless/meta/` or `.correctless/artifacts/` (which `/cchores`
  strips from staging), so `/cchores` stages it in the chore PR through the normal diff-based
  `git add` path with no special-casing.
- **Boundary**: the **`/cchores` INV-010 skill invariant** (a skill-level rule, NOT a registered
  architecture TB — RS-016). Cross-reference: `/cchores`'s registered boundary **TB-009** is
  *touched* (a new tracked artifact enters the chore PR's staged set; a new `Bash(…)` capability is
  added) but *not weakened* — the artifact is deterministic filesystem-derived content, never
  issue-text derived, so TB-009 INV-001 positive-gate provenance holds.
- **Violated when**: any INV-010 text is relaxed, or the artifact lands in a
  protected/stripped/gitignored path.
- **Enforcement**: structural test asserting (a) `skills/cchores/SKILL.md` INV-010 shared-doc ban is
  unchanged, (b) `tests/test-inventory.json` does not match the **resolved effective SFG protected
  set** — not just absence from the DEFAULTS list, but that running the SFG hook against an
  Edit/Write to the artifact path does NOT block (covers DEFAULTS, `custom_patterns`, and any
  path-expansion/wrapper — EXT-010), (c) it is tracked and not gitignored.
- **Guards against**: scope-creep that would re-introduce Option 1's relaxation; PRH-001
- **Test approach**: integration
- **Risk**: high

### INV-006: Consumer-scoped, ordered, exit-checked regeneration wiring
- **Type**: must
- **Category**: parity / robustness
- **Statement**: the skills that add/remove test files regenerate + stage the artifact so R-006(c)
  stays green — **but only in a repo where the R-006(c) consumer exists**, and with the ordering and
  exit-handling pinned:
  - **Consumer scope (RS-001, backed by the generator-side guard INV-003/EXT-006):** each skill runs
    the generator ONLY when the consumer marker `tests/test-ap031-fixture-divergence.sh` is present;
    the generator ALSO self-guards (INV-003), so this is defense-in-depth, not the sole guard. On a
    downstream install with no consumer the wiring is a **graceful no-op** — nothing is created or
    staged in the user's tree and the host skill never aborts (Upgrade #1-3 / Assumptions F12-13 /
    Red Team #1 / EXT-006).
  - **Ordering — corrected (EXT-001/002/008, supersedes RS-007 v1):** because "actual" is the
    **index** universe (INV-002/INV-004), the generator must run **after** the relevant test files
    are staged and the artifact must then be staged into the SAME commit. Pinned sequences:
    - `/ctdd`: RED writes **and stages** its test files → run the generator → **stage
      `tests/test-inventory.json`** → the suite (incl. R-006(c)) runs against the staged index.
    - `/cchores`: after GREEN, compute the fix's changed paths → `git add` those (incl. the net-new
      test) → run the generator (now the new test is in the index, so it counts it) → `git add
      tests/test-inventory.json` → the single scoped commit includes both. The earlier
      "regen **before** the stage-set snapshot" wording was WRONG: pre-stage, the index count returns
      the old N, so the commit would carry N+1 tests vs an artifact of N and CI's R-006(c) would fail
      — the deadlock at the artifact (EXT-001/002). The generator run and the artifact `git add` are
      simply added to `/cchores`'s existing curated staging, not a second commit.
    - `/cdocs`: docs phase, same stage-then-regen-then-stage-artifact shape.
    - The prior conditional ("only when the diff changed the `test*.sh` set") is **dropped** — regen
      is unconditional where the consumer is present (idempotent + O(files), so a no-op is free, and
      the untested set-change branch disappears — Testability F2).
  - **Post-final-stage consistency (EXT-008):** `/cchores`'s pre-push CI-superset gate re-runs
    R-006(c) against the FINAL staged/committed universe (not just the GREEN working tree), so an
    index-vs-artifact mismatch is caught locally before push, not only in CI.
  - **Exit handling (RS-006):** each caller MUST inspect the generator's exit status and, on
    non-zero, **surface the `gen-test-inventory: FAILED` token verbatim** and fail the step rather
    than proceeding — matching the ABS-047 consumer-echo discipline that closed #189. A FAILED write
    must never be silently committed/pushed as success (silent-telemetry class, PMB-005/PMB-008).
    (The `no consumer — skipped` no-op is exit 0 and is NOT a failure.)
- **Boundary**: functional wiring across skills; ABS-048 consumer contract
- **Violated when**: a skill runs the generator on a non-consumer repo (should no-op); a skill adds
  a test file but leaves the artifact stale; `/cchores` runs the generator **before** staging the
  net-new test (index count stale — EXT-001) or fails to stage the artifact into the commit; or a
  caller ignores a non-zero generator exit.
- **Enforcement**: **behavioral mechanism test (not keyword-presence — RS-005/Testability F1):**
  mechanically reproduce #219 in a temp git fixture WITHOUT the LLM — committed artifact count N + a
  `tests/` tree → **stage** a net-new `test-zzz.sh` → run the actual `gen-test-inventory.sh write` →
  **stage the artifact** → assert R-006(c) (index universe) PASS; negative arm: run the generator
  BEFORE staging `test-zzz.sh` → assert R-006(c) FAIL (proves the ordering is load-bearing, EXT-001).
  Plus **block-scoped ordering assertions** (extract the /cchores staging section as the R-003 tests
  do) that the fix's test paths are `git add`-ed before the generator runs and the artifact is
  `git add`-ed after, and that `/ctdd`'s stage→regen→stage sits between RED and the suite. Plus a
  consumer-absent test (marker removed → generator no-ops, nothing staged — exercises the INV-003
  generator guard, EXT-006). The spec states plainly that `/ctdd`//`cdocs` regen is prompt-level and
  the mechanical guarantee is R-006(c) firing in CI.
- **Guards against**: the deadlock recurring silently; PMB-005 wiring-omission; RS-001 orphan; RS-006 silent-fail; RS-007 unstaged-stale
- **Test approach**: integration + unit (mechanism repro)
- **Risk**: high

### INV-007: AGENT_CONTEXT.md figure is informational, pointered, and structurally un-scraped
- **Type**: must
- **Category**: functional
- **Statement**: because R-006(c) no longer reads `AGENT_CONTEXT.md`, the Tests-row count is marked
  explicitly approximate as **`~N test scripts`** (RS-017: "scripts" not "files", since the glob
  counts `test-helpers.sh` too) with an inline **authoritative-source pointer** naming
  `tests/test-inventory.json`, so a human who wants the exact number has a discovery path. It is
  maintained free-form by `/cdocs` (not INV-010-constrained) and its drift is harmless.
  **prune-scan interaction (RS-012):** `scripts/prune-scan.sh scan_counts` reads this row and its
  digit-anchored extractor will no longer match the `~`-prefixed figure, so `/cprune` **silently
  skips** the tests-count drift candidate for this row — this is acceptable and intended (R-006(c)
  is authoritative), but is recorded here so a future edit that drops the `~` (restoring a parseable
  exact figure) and thereby revives a spurious `/cprune` `tests-count` candidate is understood, not
  surprising.
- **Boundary**: docs hygiene
- **Violated when**: the doc presents an exact-looking number that silently diverges from actual; or
  a test hard-couples to the row.
- **Enforcement**: this feature edits the Tests row to `~N test scripts` + pointer; **structural
  test** that no file under `tests/` greps/extracts the `AGENT_CONTEXT.md` Tests-row count (makes
  "no test hard-couples to it" mechanically true rather than aspirational — RS-017/Design Contract #5).
- **Test approach**: unit (structural no-scrape)
- **Risk**: low

### INV-008: Distribution parity (producer mirrored; consumer + artifact stay under tests/)
- **Type**: must
- **Category**: parity
- **Statement**: `scripts/gen-test-inventory.sh` is mirrored to `correctless/scripts/…` and the
  modified `skills/*/SKILL.md` to `correctless/skills/…`, kept in lockstep by `sync.sh`; `sync.sh
  --check` is green (CI + pre-commit gate). `tests/` is NOT mirrored, so the artifact and R-006(c)
  live only under `tests/` — and there is NO `correctless/tests/test-inventory.json`. Because the
  producer mirrors downstream while the consumer does not, INV-006's consumer-scope guard is what
  keeps the mirrored producer from acting on non-consumer repos (RS-001 dependency).
- **Boundary**: PAT distribution mirror
- **Violated when**: source/mirror diverge; `sync.sh --check` non-zero; or a `correctless/tests/…`
  copy of the artifact/consumer appears.
- **Enforcement**: `sync.sh --check` CI + `correctless-sync-check` pre-commit; drift test asserting
  the artifact + R-006(c) exist only under `tests/` and not under `correctless/tests/`.
- **Test approach**: integration
- **Risk**: medium

### INV-009: allowed-tools coverage (AP-008) + unchanged Group B disallowed-tools + new-test naming
- **Type**: must
- **Category**: parity
- **Statement**: `/cchores`, `/ctdd`, `/cdocs` `allowed-tools` include the generator invocation —
  both the installed form `Bash(bash .correctless/scripts/gen-test-inventory.sh*)` AND the
  `Bash(bash scripts/gen-test-inventory.sh*)` source form where a skill may run it pre-install — and
  the enforcement verifies each **invocation string in the skill prose is covered by at least one
  `allowed-tools` glob** (not merely that some entry exists — RS-010/Testability F10). `/cchores`
  keeps its **full** `disallowed-tools` baseline **UNCHANGED**: `Edit, MultiEdit, NotebookEdit,
  CreateFile` (Group B — RS-014/Design Contract #3); the artifact is written by the Bash generator
  and staged with the existing diff-based `git add`, so Group B is fully compatible. Any new test
  script this feature adds MUST be named `tests/test-*.sh` (matches `commands.test` + CI globs; no
  manual registration — RS-015).
- **Boundary**: AP-008 allowed-tools cross-check
- **Violated when**: a skill invokes the generator without a matching `Bash(...)` glob; `/cchores`'s
  disallowed-tools is narrowed below Group B; or a new test script does not match `tests/test-*.sh`.
- **Enforcement**: `tests/test-allowed-tools-check.sh`-style assertion (glob-covers-invocation, not
  presence-only); structural assertion that `/cchores` disallowed-tools == the 4-item Group B set;
  new-test naming checked by the existing `tests/test-*.sh` glob.
- **Test approach**: unit
- **Risk**: medium

## Prohibitions

### PRH-001: Artifact must be tracked + PR-reaching
- **Statement**: `tests/test-inventory.json` must be tracked and must NOT live under any gitignored or
  `/cchores`-stripped path (`.correctless/meta/`, `.correctless/artifacts/`, `.correctless/scripts/`,
  `.correctless/hooks/`). Otherwise CI's R-006(c) can't see it and the chore's own update never reaches the PR.
- **Detection**: structural test — `git ls-files --error-unmatch tests/test-inventory.json` (tracked)
  AND `git check-ignore -q tests/test-inventory.json` returns non-zero (not ignored) AND the path is
  not under any of the four stripped prefixes.
- **Consequence**: silent CI failure / the fix never actually lands the count.

### PRH-002: No INV-010 relaxation
- **Statement**: this feature never adds a shared-doc exception to `/cchores` INV-010, and never adds
  `AGENT_CONTEXT.md` (or the artifact) to a state that weakens the ban.
- **Detection**: INV-005 structural test (INV-010 text unchanged) PLUS a behavioral exercise of the
  INV-010 diff-allowlist — a stage set containing `.correctless/AGENT_CONTEXT.md` must still abort;
  a stage set containing `tests/test-inventory.json` must NOT abort (exercises the boundary, not just
  prose stasis — RS-005/Testability F12).
- **Consequence**: re-introduces every hazard the pivot away from Option 1 eliminated.

### PRH-003: No divergent count command
- **Statement**: the generator and R-006(c) must obtain "actual" from the one shared command; neither
  re-implements its own counting primitive, and both resolve the same `tests/` directory over the
  same PR-reaching universe (INV-002).
- **Detection**: INV-002 structural test (positive: R-006(c) calls `count`; negative: no other
  counting primitive) + behavioral parity + resolution-context tests.
- **Consequence**: writer/consumer drift (codex #8) → false pass/fail.

### PRH-004: Deterministic artifact
- **Statement**: the artifact carries no timestamp or nondeterministic content; regen is idempotent
  and rewrites no bytes when the count is unchanged; serialization is byte-pinned (not jq-formatted).
- **Detection**: INV-001 double-run test (sha256 + inode/mtime + `no change` token).
- **Consequence**: perpetual churn (the #252 non-idempotency class).

## Boundary Conditions

### BND-001: Artifact absent (fresh checkout / first run)
- **Boundary**: R-006(c) reads the artifact
- **Input from**: the tracked file (committed by this feature; regenerated thereafter)
- **Validation required**: since the artifact is committed, it is present on checkout. If absent
  (or unreadable), R-006(c) FAILS with the copy-pasteable `bash scripts/gen-test-inventory.sh write`
  remediation (RS-009), never silently passes.
- **Failure mode**: fail-closed.

### BND-002: Artifact malformed (enumerated)
- **Boundary**: R-006(c) parses JSON
- **Input from**: the file (could be hand-edited)
- **Validation required**: each of — invalid JSON / missing `test_file_count` / non-integer
  (string-typed `"5"` OR fractional `3.5`) count / `schema_version` absent or `!= 1` / parse-tool
  (`jq`) absent — FAILS fail-closed with the copy-pasteable remediation (RS-010). Validate the count
  with `jq -e '.test_file_count | (type=="number" and . >= 0 and floor == .)'` (a bare `| numbers`
  accepts `3.5` — EXT-009); validate `schema_version == 1`.
- **Failure mode**: fail-closed.

### BND-003: Count decrement (test file deleted)
- **Boundary**: generator input
- **Input from**: filesystem (PR-reaching universe)
- **Validation required**: the generator writes the exact actual regardless of direction — a deletion
  syncs the count down. Unlike Option 1 there is no net-new-only asymmetry: any actor regenerates the
  unprotected artifact freely, so decrements are handled uniformly (resolves codex #15). **Note
  (RS-013):** this consistency behavior means a chore that deletes a real test passes R-006(c)
  cleanly — R-006(c) is NOT a test-deletion tamper control; that is `security-scan.sh`'s domain.
- **Failure mode**: exact write (tested — a deletion yields `test_file_count == N-1` and R-006(c) PASS).

## STRIDE Analysis
### STRIDE for the /cchores chore-diff shared-doc boundary (UNCHANGED by this feature)
- The boundary is not relaxed. The only new write target is `tests/test-inventory.json`, an
  unprotected tracked data file outside the four INV-010 prose docs.
- **Tampering (scoped claim — RS-013):** R-006(c) enforces **count/reality consistency only**
  (`artifact == actual`, recomputing actual independently) — a wrong count in the artifact is caught.
  R-006(c) is **explicitly NOT a tamper-detection control**: it does not detect a chore that deletes
  a real test (BND-003 syncs the count down to a consistent lower value), and its own test file is
  not SFG-protected. Test-deletion detection is out of scope and belongs to
  `scripts/security-scan.sh check_test_deletion`.
- **Autonomous-surface note (RS-013 / Red Team #2):** removing the #219 deadlock also removes an
  *incidental* interlock that blocked `/cchores` from autonomously landing any net-new-test chore
  (including a junk `tests/test-smuggle.sh` from a hostile issue body). This is an **accepted risk**:
  `/cchores`'s existing INV-009 nonce-fence (issue content is data, never instructions), regression
  oracle, and INV-010 diff allowlist remain the compensating controls; this feature adds no new
  net-new-test legitimacy gate.
- **Elevation of privilege**: no new doc-write capability is granted; `/cchores` still cannot touch any
  of the four prose docs (INV-010 intact — INV-005 guards this).
- **Repudiation / DoS / Info-disclosure / Spoofing**: n/a (public count, bounded O(files), no argv-transit).

## Environment Assumptions
- **EA-001**: `find`, `wc`, `jq`, `mv`, `mktemp` (coreutils + jq) available; generator fails loud if missing.
- **EA-002**: `tests/` is a tracked directory **in the correctless source repo**; `tests/test-inventory.json`
  is committed and reaches CI. Downstream installs are NOT assumed to have `tests/` or the consumer —
  INV-006's consumer-scope guard handles that (RS-001).
- **EA-003**: `LC_ALL=C` is **forced by the generator internally** for the count command so
  locale/whitespace cannot perturb it; combined with `tr -d ' '` for `wc -l` whitespace (RS-004).
- **EA-004 (RS-002):** the generator's repo-root resolution mechanism (INV-002 property 2) is a
  stated environment assumption — it resolves the correctless project root from its source-tree
  location, and is verified against normal/`/tmp`/probe-worktree/installed-path contexts. If the
  chosen mechanism uses `git`, `git`-on-PATH-inside-a-work-tree becomes an assumption; the pinned
  mechanism should avoid depending on `git rev-parse --show-toplevel` (breaks in worktree/submodule).

## Design Decisions

### ABS-048 (deliverable) — Generated test-count artifact (deliberately NOT a sole-writer)
This feature introduces one abstraction; `/cupdate-arch` (or this feature's ARCHITECTURE.md edit)
MUST add an ABS-048 entry with the following content (RS-008 / Design Contract #1):
- **What**: `tests/test-inventory.json` (`{schema_version, test_file_count}`) — the authoritative
  test-count for the R-006(c) gate and the `AGENT_CONTEXT.md` figure — plus its writer/reader
  `scripts/gen-test-inventory.sh` (`write`/`count`) and the single shared count command (INV-002).
- **Writers**: `/ctdd`, `/cchores`, `/cdocs`, humans, CI — **any actor** (multi-writer, last-write-wins).
- **Consumer**: `tests/test-ap031-fixture-divergence.sh` R-006(c).
- **Determinism**: byte-pinned serialization, no timestamp, idempotent (INV-001).
- **Deviation note (mandatory):** this abstraction **deliberately diverges** from the sanctioned
  sole-writer family (ABS-029/030/042/047). It is **NOT a sole-writer** and is **deliberately NOT in
  SFG DEFAULTS** — it must stay unprotected so every actor can regenerate it. **Adding SFG
  protection or sole-writer enforcement re-introduces the #219 deadlock** (see INV-005). It borrows
  only the tri-state `FAILED`-token exit discipline from `meta-record.sh`, not the lock or the
  protection. A future audit must NOT "correct" the missing protection.

### OQ resolutions
- **OQ-002 (resolved):** artifact location `tests/test-inventory.json` — unambiguously tracked,
  co-located, never stripped, not matched by the `test*.sh` count (basename glob is `test*.sh`; the
  artifact is `.json`) or the runner.
- **OQ-003 (resolved — RS-003, corrected by EXT-001/002/003):** keep exact `==` with "actual"
  defined over the **index** universe (`git ls-files --cached`, direct children — INV-002 property 3),
  and **stage the new test files before regenerating, then stage the artifact into the same commit**
  (INV-006 corrected sequencing). This makes exact `==` robust to untracked scratch files and
  clean-checkout CI. The `>= actual, <= actual+2` band is **NOT** a fallback — it only tolerates
  overcount, not the undercount the net-new-test case produces (EXT-003). OQ-005 closed.

## Open Questions
- **OQ-001** (deferred): add a git pre-commit hook that auto-runs `gen-test-inventory.sh write` +
  stages the artifact, making the count fully self-maintaining with no per-skill wiring? Attractive,
  but pre-commit hooks that modify+stage files interact awkwardly with `/cchores`'s single
  programmatic commit; v1 uses explicit consumer-scoped skill wiring (INV-006) + R-006(c) as the
  backstop. Revisit as a follow-up.
- **OQ-004** (follow-up, RS-018): the external-review producer (`external-review-run.sh`) rejects the
  bare `bin: "codex"` config via its RS-006 realpath validation, so the sanctioned cross-model review
  cannot run on some machines. Separate producer/config defect — re-verify the machine-specific
  resolution detail before filing an issue; NOT part of this feature.
- **OQ-005** (CLOSED by EXT-001..005): the count algorithm is pinned — `git ls-files --cached -z --
  'tests/test*.sh'`, post-filtered to direct children (no second `/`), NUL-counted (INV-002). The
  ordering is pinned — stage tests → regen → stage artifact → commit (INV-006). No band fallback
  (EXT-003). Remaining for TDD: implement + prove the four resolver contexts (INV-002 property 2)
  and the stage-order mechanism test (INV-006 Enforcement).
