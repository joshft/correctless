# Spec: Sanctioned sole-writer for SFG-protected meta artifacts (closes AP-037 class)

## Metadata
- **Created**: 2026-07-04
- **Status**: reviewed
- **Impacts**: audit-findings-persistence-contract (ABS-029 sibling), autonomous-skill-contract (ABS-030 sibling), harness-fingerprint (ABS-045 SFG boundary, ABS-027 model-baselines sole-writer), cross-skill-calibration (ABS-005 cverify sole-writer), cdocs meta back-fill
- **Branch**: feature/calibration-sanctioned-writer
- **Research**: null
- **Cross-model review**: codex (gpt-5.5) adversarial spec review — two rounds. Round 1 (during /cspec): 24 findings folded into the draft. Round 2 (during /creview-spec, 2026-07-04): confirmed RS-001..007/RS-021 and added EXT-001..005 (lock-helper reuse, baselines key-merge, /cmodelupgrade test/ABS ripple, /cdocs absent-file guard, symlink creation-order). See `.correctless/artifacts/review-spec-findings-calibration-writer.md`.
- **Intensity**: high
- **Recommended-intensity**: high
- **Intensity reason**: file-path signal (touches `hooks/sensitive-file-guard.sh`) + antipattern signal (AP-037, AP-022, silent-telemetry-failure overlap ≥2) + project floor `high`
- **Override**: none
- **Resolves**: GitHub #189, #192, #226 (and closes the `/cmodelupgrade` → `model-baselines.json` AP-037 instance surfaced by /creview-spec RS-002)

## Context

**Three** SFG-protected `.correctless/meta/*.json` artifacts have **no sanctioned writer**, so the documented skill that must write them is silently blocked (AP-037 — "protected asset is the deliverable, the guard has no legitimate-write affordance"):

1. **`intensity-calibration.json`** (#189): `/cverify` is told to append a per-feature calibration row (SKILL.md "Write Calibration Entry") and even holds a `Write(...calibration.json)` grant, but SFG's Edit/Write guard blocks it → the append silently no-ops. The calibration dataset feeding `/cspec` intensity recommendations, `/cmetrics`, and the dashboard is frozen while consumers read stale data and look healthy (silent-telemetry-failure).
2. **`pat001-measurement-due.json`** (#192/#226): `/cdocs`'s "Back-fill Deferred Meta Fields" step sets `created_at_commit` via Edit — also SFG-blocked. Worse, the back-fill uses a `jq '.created_at_commit == null'` test that matches **absent** fields (jq returns `null` for missing keys), and blanket-scans **all** `.correctless/meta/*.json`, so a run for feature A pollutes features B/C baselines with A's merge-base (#226) and adds spurious `created_at_commit` to files that never had it (#192).
3. **`model-baselines.json`** (RS-002, surfaced by /creview-spec): `/cmodelupgrade` holds `Write(.correctless/meta/model-baselines.json)` and writes it at Step 5 — SFG blocks that Write today (the skill self-documents the residual). It is a live, already-broken AP-037 instance of exactly the #189 shape. Omitting it would make the class-closure test (this feature's headline deliverable) either fail honestly or pass on a lie — so it is scoped in.

This feature adds a **general sanctioned sole-writer** for these artifacts (invoked via Bash, which SFG permits post-`sfg-edit-write-only`), modeled on the sole-writer family (ABS-029 `audit-record.sh`, ABS-030 `autonomous-decision-writer.sh`, ABS-042 `external-review-run.sh`). Each artifact gets a registered operation; `/cverify`, `/cdocs`, and `/cmodelupgrade` are rewired onto it. It then **closes the AP-037 class structurally** for `.correctless/meta/*.json`: a completeness test asserts every SFG-protected meta json maps to a registered sanctioned writer.

### Writer construction (bespoke tri-state body over REUSED lock helpers — RS-001 / EXT-001)

The reused primitive `locked_update_file` is **two-state** (rc 0/1, swallows jq stderr, `mv`s unconditionally on jq success) and cannot express this spec's three-state exit contract. Therefore `meta-record.sh` does **not** call `locked_update_file`. It also does **not** re-derive locking. It **reuses the ABS-003 lock helpers directly** — `_acquire_state_lock "$dest"` / `_release_state_lock "$dest"` (lib.sh:273-323: `${dest}.lock`, stale-claim via `mv`, missing-pid-is-stale, PID-owned release) — and hand-rolls **only** the tri-state body inside that lock:

```
_acquire_state_lock "$dest"        # reuse — never a bespoke lock, never rm -rf lock_dir
  read $dest (under lock)          # decision read is INSIDE the lock (closes the TOCTOU)
  validate / compute no-op vs write
  if no-op:   emit "no change: <reason>"; rc 0; NO file write   (EXT-001: no mv on no-op)
  else:       write transformed JSON to "$dest.$$.tmp" (SAME dir)
              validate the temp is valid JSON
              mv "$dest.$$.tmp" "$dest"   ONLY after the temp validates (crash-safe)
              emit success line; rc 0
  on any attempted-but-unlanded write: rc non-zero + stderr diagnostic naming $dest
_release_state_lock "$dest"
```

Do **not** wrap `locked_update_file` inside a pre-lock on the same `${dest}.lock` — the inner call re-acquires the self-held lock and deadlocks (EXT-001).

### Mechanism capability (honesty note — PMB-020 / AP-040)

SFG is a **cooperative-loop guardrail, not a security perimeter** (ABS-045, AP-040, PMB-020). It blocks the *naive agent Edit/Write* to a protected path; it does **not** and cannot stop a motivated Bash write — EA-001 states SFG does not inspect Bash. "Sole writer" means **the sanctioned/expected write path in the cooperative agent loop**, enforced against agent Edit/Write by SFG and against wrong *content* by the append-only + validation tests. Bash-mediated out-of-band writes are an **accepted non-goal** (AP-040). The symlink/realpath guards (INV-010) are **writer robustness inside the AP-040 boundary**, not a security perimeter. No invariant claims a strength the cooperative-loop layer cannot deliver.

## Scope

**In scope**
- New general sanctioned sole-writer `scripts/meta-record.sh` (+ synced `.correctless/scripts/` mirror) that **reuses `_acquire_state_lock`/`_release_state_lock`** and hand-rolls the tri-state body (above), with three registered, per-artifact operations, each with a **hardcoded destination** (PRH-005):
  - `calibration-append` — append one object to `intensity-calibration.json`'s `calibration_entries[]` (stdin JSON).
  - `pat001-set-created-at <sha>` — set `created_at_commit` on `pat001-measurement-due.json` **only when the field is present and literally `null`**.
  - `baselines-write` — **key-merge** one baseline into `model-baselines.json`: set/replace exactly one `baselines["<model>|<HARNESS_VERSION>"]` entry, **preserving all other keys and top-level `schema_version`** (EXT-002). Never a whole-file overwrite. Rejects a `schema_version` mismatch (fail-loud) rather than clobbering.
- An explicit **writer registry** — a **CI/test-only data file** the writer does NOT runtime-read (RS-004/EXT / DD-007), located OUTSIDE `.correctless/meta/`, mapping each SFG-protected meta file → `(writer-script, operation)`; consumed only by the class-closure test.
- Rewire `/cverify` (calibration append), `/cdocs` (pat001 created_at set), and `/cmodelupgrade` (baselines-write) to invoke the writer via Bash instead of Write/Edit; surface writer failures loudly via a **mechanical stdout token** (RS-005). Update each skill's `allowed-tools` (drop the `Write(...meta...json)` grants, add the `Bash(*meta-record.sh*)` grant). `/cdocs` stops blanket-scanning `*.json` and only invokes pat001 when the file **exists and carries a present-null field** (EXT-004).
- Add `scripts/meta-record.sh` to SFG DEFAULTS with a documented lift-and-restore affordance (`.claude/rules/sfg-deliverable.md`, AP-037 amendment).
- **Class closure**: structural test asserting every `.correctless/meta/*.json` in SFG DEFAULTS maps to a registered writer.
- **Pollution detector** (RS-013): a re-derivation/detection helper (2026-05-15 backstop convention) that flags `pat001`/baseline meta files whose `created_at_commit` diverges from their own feature's merge-base, surfaced in `/cstatus`. (Detection only; repair is advisory.)
- Update **ABS-005** (cverify → meta-record sole-writer) and **ABS-027** (cmodelupgrade → meta-record baselines-write) invariants + the drift test in lockstep (RS-015/EXT-003). Update `tests/test-allowed-tools-check.sh` and `tests/test-harness-fingerprint.sh` assertions that currently expect the direct `/cmodelupgrade` Write grant (EXT-003).
- New abstraction **ABS-047** documenting the sanctioned-meta-writer contract; sync + CI.

**Out of scope (Won't Do)**
- A **hard `cmd_*` phase-transition gate** refusing a transition when a write didn't happen (DD-001): the reads are dormant-tolerant; a hard gate is disproportionate and conflicts with the no-auto-advance preference. Fail-loud on the writer + mechanical-token surfacing, not a transition gate.
- Changing **what fields** `/cverify` computes for a calibration entry, the `created_at_commit` **semantics**, or **what metrics** `/cmodelupgrade` captures. Only the write *mechanism* and the null-vs-absent/blanket-scan/whole-file-overwrite *bugs* change.
- **Retroactive repair** of existing `#226/#192` pollution — the helper *detects* and surfaces it; a repair sweep is a follow-up (gitignored local state, last-write-wins acceptable).
- Migrating/canonicalizing existing `intensity-calibration.json` entries (writer is append-compatible) or existing `model-baselines.json` baselines (writer is key-merge, preserves them).
- Generalizing to non-meta SFG-protected artifacts (scripts, agents, config). Scope is `.correctless/meta/*.json` only.
- **Tamper-proofing against arbitrary Bash writes** to the meta files or the writer script (AP-040 accepted non-goal).

## Complexity Budget
- **Estimated LOC**: ~560 (writer ~230 for three ops + reused-lock tri-state body + realpath/size guards; registry ~10; structural + behavioral tests ~200; cverify/cdocs/cmodelupgrade prose + frontmatter edits; test-allowed-tools-check + test-harness-fingerprint assertion flips ~40; SFG DEFAULTS +3; pollution-detector ~50; ABS-047/ABS-005/ABS-027)
- **Files touched**: ~14 (`scripts/meta-record.sh`, `scripts/sanctioned-meta-writers.tsv`, `hooks/sensitive-file-guard.sh` + mirror, `skills/cverify/SKILL.md`, `skills/cdocs/SKILL.md`, `skills/cmodelupgrade/SKILL.md`, `tests/test-meta-record.sh`, `tests/test-sensitive-file-guard.sh`, `tests/test-allowed-tools-check.sh`, `tests/test-harness-fingerprint.sh`, `docs/architecture/abstractions.md` (ABS-047/005/027) + `.correctless/ARCHITECTURE.md` index, pollution-detector script, `sync.sh`/`setup` mirrors)
- **New abstractions**: 1 (ABS-047); 2 amended (ABS-005, ABS-027)
- **Trust boundaries touched**: 2 (SFG write-protection boundary — ABS-045; structured-input→argv no-eval — TB-001)
- **Risk surface delta**: medium-high (edits SFG DEFAULTS — only ADDS a protected path, PRH-003-safe; rewires three skills; hand-rolls a tri-state body over reused lock helpers)

## Exit-code semantics (all operations — governs INV-003/PRH-004)

| Exit | Signal | Meaning |
|------|--------|---------|
| `0` + success line on stdout | write applied | the intended mutation landed and the file is valid JSON afterward |
| `0` + explicit `no change: <reason>` line | **intended no-op** | INV-009-class guarded no-op — a correct outcome, **not** an attempted write, and **no file bytes are rewritten** (EXT-001) |
| non-zero + `meta-record: FAILED <file>: <reason>` on stdout AND stderr diagnostic | rejected / failed | invalid input (schema/SHA/schema_version-mismatch) OR an *attempted* write that could not complete (lock/corrupt/unwritable) |

The **forbidden state (PRH-004)** is: exit `0` after a write was *attempted* but did not land. An intended no-op is distinct and is not forbidden. The `meta-record: FAILED <file>: <reason>` stdout token (RS-005) is the mechanical seam skills echo verbatim so failures are provably surfaced.

## Invariants

### INV-001: Sole append-only writer for calibration (deep-equal preservation)
- **Type**: must
- **Category**: data-integrity
- **Statement**: `meta-record.sh calibration-append` is the sanctioned write path for `intensity-calibration.json`; it appends one object to `calibration_entries[]`. Every pre-existing entry is **unchanged as a JSON value (deep-equal)** and the **relative order of prior entries is preserved** — NOT byte-identical (jq reformats). Duplicate `feature_slug` entries are permitted (pure append — DD-004).
- **Boundary**: ABS-047
- **Violated when**: an append reorders/drops/rewrites a prior entry's JSON value.
- **Enforcement**: SFG DEFAULTS blocks the naive agent Edit/Write (guardrail); the *structural* leg is a test asserting deep-equal (`jq --sort-keys` value-equality on the `[:-1]` prior slice) + order preservation across an append on a real multi-entry fixture.
- **Guards against**: AP-037
- **Test approach**: unit + integration
- **Risk**: high

### INV-002: Schema validation under the lock, permissive unknown fields, fail-closed (pinned fields)
- **Type**: must
- **Category**: data-integrity
- **Statement**: `calibration-append` validates the incoming entry **inside the same `_acquire_state_lock` critical section as the decision read and write** (no TOCTOU window). Required fields (pinned from `skills/cverify/SKILL.md` "Write Calibration Entry"): `feature_slug` (string), `recommended_intensity` + `actual_intensity` (enum `standard|high|critical`), `actual_qa_rounds` + `actual_findings_count` + `actual_spec_updates` (integer ≥0), `actual_tokens` (integer ≥0), `file_paths_touched` (array of strings), `timestamp` (ISO-8601 string). Optional (validated for type only when present): `actual_cost_usd` (number), `harness_version` (integer), `fix_rounds_triggered` (integer). The unknown-field policy is **PERMISSIVE** (RS-007/EXT): unknown extra fields are accepted and preserved — never a rejection reason — so forward-compatible producer schema growth cannot cause silent data loss. A missing required field / wrong type / non-JSON entry is rejected with non-zero exit + FAILED token, no write, file unchanged.
- **Boundary**: BND-001
- **Violated when**: the writer appends an entry missing a required field or of wrong type, rejects on an unknown extra field, validates outside the lock, or writes anything on invalid input.
- **Enforcement**: `jq -e` required-field/type check inside the locked body; test feeds each malformed shape (assert non-zero + unchanged file) AND an entry with an unknown extra field (assert accepted + preserved).
- **Guards against**: silent corruption, silent-telemetry (forward-compat data loss), AP-031
- **Test approach**: unit
- **Risk**: high

### INV-003: Fail-loud via mechanical stdout token, never silent no-op
- **Type**: must-not
- **Category**: functional
- **Statement**: when the writer *attempts* a write it cannot complete (lock unobtainable, unparsable existing file, unwritable path, invalid JSON post-transform, schema_version mismatch for baselines), it exits non-zero, prints `meta-record: FAILED <file>: <reason>` on **stdout**, and a diagnostic to stderr naming the file. It NEVER exits 0 after an attempted-but-unlanded write. (A guarded INV-009 no-op is a distinct intended outcome.)
- **Boundary**: ABS-047
- **Violated when**: an attempted write that failed results in exit 0, or a "success" message with no file change, or a failure with no FAILED token.
- **Enforcement**: explicit rc propagation + the FAILED stdout token (the mechanical seam — not prose); failure-injection test asserts non-zero + the exact token. **The `/cverify` / `/cdocs` / `/cmodelupgrade` integration tests assert the skill echoes the `meta-record: FAILED` token verbatim in captured output** (RS-005/codex #23 — otherwise fail-loud is unproven and prompt-level).
- **Guards against**: silent-telemetry-failure (the root of #189)
- **Test approach**: unit + integration
- **Risk**: critical

### INV-004: Skills write via the sanctioned Bash path, shell-safe, surface failure + detect absence
- **Type**: must
- **Category**: functional
- **Statement**: `/cverify` (calibration), `/cdocs` (pat001), and `/cmodelupgrade` (baselines) perform their meta writes ONLY by invoking `bash .correctless/scripts/meta-record.sh` (Bash tool), never via Write/Edit on the target. Arguments (pat001 `<sha>`, calibration/baselines JSON on stdin) are passed as **discrete argv / piped stdin, never interpolated into a `bash -c` string** (TB-001). A non-zero writer exit — including **script-absent (exit 127)** on an un-re-`setup` install (RS-014/EXT) — is surfaced to the user via the `meta-record: FAILED` token (or a "run `/csetup` to install meta-record.sh" remediation for 127) and does not block the skill's primary output.
- **Boundary**: ABS-045 (SFG boundary), TB-001
- **Violated when**: any skill uses `Write`/`Edit` on the meta file, interpolates input into a shell string, or discards a non-zero writer exit silently.
- **Enforcement**: SKILL.md prose in all three skills + `allowed-tools` change (remove `Write(...meta...json)`, add `Bash(*meta-record.sh*)`) + Step-5a allowed-tools cross-check (AP-008-limited tripwire — acceptable, not sole leg) + integration test invoking each documented command and asserting the FAILED-token echo (INV-003).
- **Guards against**: AP-037, AP-008 (allowed-tools drift)
- **Test approach**: integration
- **Risk**: high

### INV-005: Writer script protected by SFG at the agent-Edit/Write layer (guardrail, not a boundary)
- **Type**: must
- **Category**: functional (guardrail-level; NOT a security boundary — PMB-020)
- **Statement**: `scripts/meta-record.sh` (source, `.correctless/scripts/` mirror, basename) are in SFG DEFAULTS, so an agent **Edit/Write** to the writer is blocked (exit 2). Cooperative-loop guardrail against accidental agent modification — explicitly **not** protection against a Bash rewrite (AP-040 non-goal). Legitimate-edit affordance = lift-and-restore per `.claude/rules/sfg-deliverable.md`.
- **Boundary**: ABS-041 (lift-and-restore), ABS-045
- **Violated when**: the writer path is absent from DEFAULTS, added without a documented edit affordance, or an invariant claims it is tamper-proof against Bash.
- **Enforcement**: SFG DEFAULTS + `tests/test-sensitive-file-guard.sh` Edit/Write-block case; AP-037 amendment names the affordance.
- **Guards against**: AP-022, AP-037
- **Test approach**: unit
- **Risk**: medium

### INV-006: Class closure — every protected meta file maps to a registered sanctioned writer
- **Type**: must
- **Category**: parity
- **Statement**: every `.correctless/meta/*.json` path in SFG DEFAULTS maps to exactly one registry entry `(writer-script, operation)`. After this feature the full DEFAULTS-meta set (five files) is: `intensity-calibration.json`→`meta-record.sh calibration-append`, `pat001-measurement-due.json`→`meta-record.sh pat001-set-created-at`, `model-baselines.json`→`meta-record.sh baselines-write`, `harness-fingerprint.json`→`harness-fingerprint.sh`, `prune-pattern-baseline.json`→`prune-scan.sh --update-baseline`. **All five are script-writers → zero exemptions → class fully closed** (DD-002). A protected meta file matching no registry entry fails the structural test.
- **Boundary**: ABS-047
- **Violated when**: a SFG-DEFAULTS meta file has no registry entry.
- **Enforcement**: structural test that extracts the DEFAULTS meta set with an anchored regex `^\.correctless/meta/[^/]+\.json$` (NOT a bare `.json` substring — must REJECT adversarial siblings like `credentials.json`/`service-account*.json` per AP-032/PMB-016) and requires each to match a registry row; over-enumerate + require match, never a hardcoded pass-list. The DEFAULTS-parse test uses a verbatim real fixture of the heredoc (AP-031).
- **Guards against**: AP-037 (the whole class), AP-032
- **Test approach**: integration
- **Risk**: high

### INV-007: Concurrent-safe atomic write via REUSED lock helpers (lock keyed on destination string)
- **Type**: must
- **Category**: concurrency
- **Statement**: all reads, validation, decision, and the write happen inside one `_acquire_state_lock "$dest"` / `_release_state_lock "$dest"` critical section (ABS-003 lock — `${dest}.lock`, keyed on the destination **string**; since each op passes one hardcoded constant path, the key is unambiguous by construction). The write uses a same-directory `$dest.$$.tmp` + `mv`-after-validate (EXT-001). No append/merge is lost, no file left partial. The writer **reuses** the lock helpers (never a bespoke `.lock`, op-specific lock, or `rm -rf lock_dir`) and **never** calls `locked_update_file` from inside its own lock (deadlock — EXT-001).
- **Boundary**: ABS-003
- **Violated when**: validation/decision-read occurs outside the lock, locking is re-derived, `locked_update_file` is wrapped in a pre-lock, two writes race and one is lost, or a crash leaves invalid JSON.
- **Enforcement**: writer routes read-validate-decide-write through `_acquire_state_lock`; concurrency test (RS-008) — set `CORRECTLESS_LOCK_TIMEOUT` high, fire N concurrent appends capturing each exit code, assert (a) valid JSON throughout, (b) `count(entries) == count(exit-0-success invocations)`, (c) each success contributed exactly one entry, (d) any non-zero printed the FAILED token. (Assert no-lost-update, NOT a fixed N — a legitimately-contended fail-loud makes a fixed count flaky and would contradict INV-003.)
- **Guards against**: AP-020 (lost-update)
- **Test approach**: integration
- **Risk**: high

### INV-008: Calibration schema pinned to the /cverify producer shape (AP-031 dormant)
- **Type**: must
- **Category**: data-integrity
- **Statement**: the required-field list in INV-002 is the exact `calibration_entries[]` shape from `skills/cverify/SKILL.md` "Write Calibration Entry". Since `intensity-calibration.json` is gitignored (no committed real artifact), this is the AP-031 **dormant** case: spec format-pinning is the sole guard. The test fixture is a **typed** entry (integers/enum strings — NOT a verbatim copy of the producer's placeholder-string template, whose numeric fields are documented as strings), with each field cross-referenced line-by-line to the SKILL.md block via a content-pairing drift test (PAT-015).
- **Boundary**: BND-001
- **Violated when**: the schema and the producer shape diverge, or a "verbatim" fixture with wrong-typed placeholder values is used.
- **Enforcement**: field list cross-referenced to SKILL.md (PAT-015 drift test); typed fixture.
- **Guards against**: AP-031
- **Test approach**: unit

### INV-009: pat001 set-created-at is present-null-only and single-file; baselines-write is key-merge (fixes #192/#226, EXT-002)
- **Type**: must
- **Category**: data-integrity
- **Statement**: `pat001-set-created-at` sets `created_at_commit` on `pat001-measurement-due.json` **only when the field is present and literally JSON `null`** (`has("created_at_commit") and .created_at_commit == null`), never when absent, and never on any other file. Absent-field or present-non-null → **intended no-op** (exit 0 + `no change: <reason>`, no bytes rewritten). `baselines-write` sets/replaces exactly one `baselines["<model>|<version>"]` key, **preserving all other keys + `schema_version`**; a `schema_version` mismatch → **fail-loud** (EXT-002). A corrupt/wrong-root-type/unparseable target for either op → **fail-loud** (non-zero, INV-003), never a spurious write. `/cdocs` no longer blanket-scans; `/cverify`/`/cdocs`/`/cmodelupgrade` accept the SHA (40- or 64-hex — RS-012) as discrete argv.
- **Boundary**: BND-001
- **Violated when**: pat001 writes into a file lacking the field (#192), overwrites a non-null value, touches any other file (#226), silently succeeds on a corrupt target; or baselines-write drops other keys / clobbers on schema mismatch.
- **Enforcement**: `has(...) and (... == null)` guard on the hardcoded pat001 destination; key-merge jq (`.baselines[$key]=$val`) preserving siblings + `schema_version` guard for baselines; tests cover pat001 {absent→no-op/exit0, present-null→set/exit0, present-non-null→no-op/exit0, corrupt→fail}, "no other meta file touched" (mtime/content of siblings unchanged — the #226 guard), and baselines {new key added, existing key replaced with siblings preserved, schema mismatch→fail}.
- **Guards against**: AP-031, silent cross-feature corruption
- **Test approach**: unit + integration
- **Risk**: high

### INV-010: Bounded input, symlink-refusing destination (fail-closed realpath, creation-order safe)
- **Type**: must
- **Category**: resource-lifecycle (writer robustness inside the AP-040 boundary — not a security perimeter)
- **Statement**: (a) the calibration/baselines stdin JSON is **byte**-capped (counted with `wc -c` / `LC_ALL=C`, NOT `${#var}` which counts characters — RS-017) before parsing; rejected above the ceiling (OQ-002 = 64 KB). Payload is passed to jq via stdin/`--rawfile`/temp-file, **never on argv** (`--argjson "$payload"` would put it on the command line — ARG_MAX/AP-039 risk; RS-011); `$(cat)` capture is avoided (NUL-truncation) in favor of a temp file. (b) Before ANY `mkdir -p`/temp-creation/write, the writer lstat/`realpath`-checks the destination AND its nearest existing parents under `.correctless/meta/` for symlinks, and re-checks under the lock immediately before `mv` (EXT-005 creation-order); resolution uses `realpath`/`readlink -f` behind a **fail-closed `_realpath_tool_available` probe** (PAT-020; precedent `prune-scan.sh`) — never the lexical `canonicalize_path`, and fail-loud when neither tool exists. The resolved real path must remain inside the repo's `.correctless/meta/`.
- **Boundary**: BND-001
- **Violated when**: stdin above the cap is parsed, the payload transits argv, `${#var}` is used for the byte cap, `canonicalize_path` is used for the symlink verdict, the check runs after mkdir/temp creation, or a write follows a symlinked meta path/parent out of `.correctless/meta/`.
- **Enforcement**: `wc -c` byte guard before jq; `_realpath_tool_available` fail-closed probe + `test -h` on destination + nearest existing parents BEFORE mkdir/temp, re-check before rename; tests for oversize stdin (reject), symlinked target (refuse), symlinked parent-dir (refuse), realpath-tool-absent (fail-loud, probe stubbed unavailable), and NUL-byte stdin (no silent truncation).
- **Guards against**: DoS, symlink-redirect write, AP-039
- **Test approach**: unit
- **Risk**: medium

## Prohibitions

### PRH-001: Never mutate existing calibration/baseline entries
- **Statement**: `calibration-append` never edits/reorders/deletes any pre-existing entry (deep-equal + order-preserved). `baselines-write` never drops or rewrites a baseline key other than the one it targets.
- **Detection**: structural test comparing prior entries/keys by JSON value across an append/merge.
- **Consequence**: corrupting historical calibration/baseline data poisons `/cspec` recommendations, `/cmetrics`, `/cmodelupgrade` reports.

### PRH-002: Skills never fall back to Write/Edit on a protected meta file
- **Statement**: on a writer failure, `/cverify`/`/cdocs`/`/cmodelupgrade` must not retry via Write/Edit (SFG-blocked, would silently fail) — they report the failure and move on. SFG blocking the Edit/Write is the real enforcement; the grep/allowed-tools check is documentation (AP-008-limited tripwire).
- **Detection**: grep all three SKILL.md for `Write(`/`Edit` targeting the meta paths; allowed-tools cross-check.
- **Consequence**: reintroduces the silent no-op #189/#192 describe.

### PRH-003: Never lift SFG protection on the target meta files
- **Statement**: `intensity-calibration.json`, `pat001-measurement-due.json`, `model-baselines.json` stay in DEFAULTS; this feature only ADDS the writer path to DEFAULTS, never removes their protection.
- **Detection**: `tests/test-sensitive-file-guard.sh` asserts all three remain Edit/Write-blocked.
- **Consequence**: an unprotected meta file could be rewritten by an injected agent Edit/Write.

### PRH-004: Writer never reports success after an attempted-but-unlanded write
- **Statement**: no code path exits 0 after a write was *attempted* and did not land as valid JSON. An intended INV-009 no-op is distinct — exit 0 + `no change`, no bytes rewritten.
- **Detection**: INV-003 failure-injection tests + the exit-code table.
- **Consequence**: silent-telemetry-failure recurrence.

### PRH-005: Destination never derived from input
- **Statement**: each operation's destination file is a hardcoded constant selected by the operation name; never taken from stdin/argv. Unknown op → fail-loud, no default write path (DD-005). Combined with INV-010's symlink check on that hardcoded path.
- **Detection**: writer source review + test that a hostile stdin/argv payload cannot redirect the write.
- **Consequence**: arbitrary file write.

### PRH-006: Bespoke locking is prohibited; reuse the ABS-003 lock helpers
- **Statement**: `meta-record.sh` must acquire/release via `_acquire_state_lock`/`_release_state_lock`; it must not invent a lock file, op-specific lock, or `rm -rf` the lock dir, and must not wrap `locked_update_file` in a pre-lock (deadlock).
- **Detection**: source review + a test asserting the writer sources `lib.sh` and references `_acquire_state_lock`; grep for a bespoke `.lock`/`rm -rf`/`locked_update_file` call.
- **Consequence**: lost updates or deletion of another process's live lock (EXT-001).

## Boundary Conditions

### BND-001: Meta-write input and target initialization
- **Boundary**: ABS-045 (SFG) / TB-001 (skill→script argv)
- **Input from**: `/cverify`, `/cdocs`, `/cmodelupgrade` (semi-trusted same-tool skills) — a JSON object on stdin (calibration/baselines, size-capped per INV-010) or a `<sha>` argv (pat001).
- **Validation required**: valid JSON + required-field schema (calibration, INV-002); well-formed 40-or-64-hex SHA as discrete argv (pat001/baselines-key, INV-004/RS-012); destination resolves inside `.correctless/meta/` and is not a symlink (INV-010).
- **Target initialization**:
  - calibration: absent OR **zero-byte** file (`[ ! -s ]`, RS-010) → **create** `{"calibration_entries":[]}` then append (the create/mkdir happens AFTER the INV-010 parent-symlink check — EXT-005); root not an object / `calibration_entries` not an array → **fail-loud**.
  - pat001: the skill invokes the op ONLY when the file **exists and carries a present-null `created_at_commit`** — absence-by-design (non-dogfood projects) is a silent skip in `/cdocs`, NOT a writer call (EXT-004). If invoked on a missing/non-object/unparseable target the writer **fails-loud** (corrupt case only); it never creates the file.
  - baselines: absent → **create** `{"schema_version":1,"baselines":{}}` then key-merge; root not an object / `baselines` not an object / `schema_version` mismatch → **fail-loud** (preserve real-but-wrong data; EXT-002).
- **Failure mode**: fail-closed — reject with non-zero exit + FAILED token, write nothing.

## STRIDE Analysis

### STRIDE for the SFG write-protection boundary (ABS-045)
- **Spoofing**: n/a (local script, no identity).
- **Tampering**: a malformed/hostile *entry* corrupting a dataset → schema/guard validation under lock (INV-002, INV-009) + deep-equal append / key-merge (INV-001, PRH-001) contain it. Tampering with the *writer script or meta file via arbitrary Bash* is an accepted non-goal (AP-040) — SFG blocks only agent Edit/Write (INV-005).
- **Repudiation**: calibration entries carry `timestamp` + `feature_slug`; pat001/baselines ops emit a provenance line (file+key/sha+outcome) so the mutation is observable.
- **Info disclosure**: meta data is local + gitignored, low sensitivity; no secrets written.
- **DoS**: stdin byte-cap counted with `wc -c` (INV-010) + lock stale-recovery (reused helpers) + payload-not-on-argv (ARG_MAX, RS-011); each op is one bounded write.
- **Elevation of privilege**: destination hardcoded per operation (PRH-005) + symlink-refused with creation-order-safe fail-closed realpath (INV-010) — the Bash-invoked writer cannot be turned into an arbitrary-path or symlink-redirected write.

## Environment Assumptions
- **EA-001**: SFG post-`sfg-edit-write-only` rescope does NOT inspect Bash — the writer *works* because it's Bash-invoked, AND SFG therefore *cannot* protect the meta files/writer against Bash (the honest capability limit — PMB-020/AP-040). Refs ABS-045.
- **EA-002**: `lib.sh` `_acquire_state_lock`/`_release_state_lock`, `branch_slug`, `canonicalize_path` (lexical use only) available at both `scripts/` and `.correctless/scripts/` (PAT-006). If wrong: writer fails loud (INV-003), never silent.
- **EA-003**: `jq` present; filters are **jq-1.7-safe** — every bound expression parenthesized (`(EXPR OP VAL) as $x`) per PMB-001/PAT-010, tested across the jq-1.7/1.8 CI matrix. Absent jq → writer fails loud.
- **EA-004** (RS-003/EXT-005): `realpath` OR `readlink -f` available for the INV-010 symlink verdict; probed fail-closed via `_realpath_tool_available` (PAT-020). Absent both → writer fails loud (never a lexical fallback). This is a NEW environment dependency the symlink leg introduces.

## Design Decisions
- **DD-001** (enforcement level): advisory fail-loud writer + mechanical-token surfacing (INV-003), **no** hard phase-transition gate. Calibration/pat001/baselines reads are dormant-tolerant; the silent-telemetry risk is closed by fail-loud + the `meta-record: FAILED` token the skills echo, not by blocking a phase. (User, 2026-07-04.)
- **DD-002** (scope): generalize the AP-037 class (mechanism + structural closure); close **all three** current instances (calibration + pat001 + model-baselines) so the class test has zero unbacked protected meta files. (User decision, 2026-07-04: widen scope to /cmodelupgrade.)
- **DD-003** (derivation split): the calling skill computes the entry/value; the writer is a thin sanctioned mutation primitive that validates + locks (via reused helpers) + writes the tri-state body. Mirrors ABS-030.
- **DD-004** (calibration dedup): pure append — duplicate `feature_slug` allowed; consumers average + cap at 50.
- **DD-005** (single general writer vs per-artifact scripts): one `scripts/meta-record.sh` dispatching per-operation, each with a hardcoded destination. The codex #21/EXT blast-radius concern is mitigated by strict per-operation dispatch (unknown op → fail-loud), PRH-005 destination-hardcoding, and — critically — `baselines-write` being a **key-merge that preserves siblings**, not a whole-file overwrite (EXT-002).
- **DD-006** (input channel): stdin (size-capped, temp-file not `$(cat)`) for calibration/baselines JSON; a positional `<sha>` argv for pat001, shell-safe (INV-004/010).
- **DD-007** (registry location + runtime posture): the writer registry (`scripts/sanctioned-meta-writers.tsv`) lives **outside** `.correctless/meta/` (avoids SFG-circularity) and is a **CI/test-only artifact the writer does NOT runtime-read** (RS-004/EXT) — the writer hardcodes its per-op destinations (PRH-005), so it needs no runtime registry; only the INV-006 class-closure test reads the TSV. This removes the install/sync-propagation blocker (a `.tsv` doesn't match the `*.sh` globs) and the self-referential-trust concern.
- **DD-008** (lock reuse — EXT-001): reuse `_acquire_state_lock`/`_release_state_lock`; hand-roll only the tri-state read-validate-decide-atomic-rename body. Never re-derive locking; never wrap `locked_update_file` (deadlock). (Codex round 2, 2026-07-04.)

## Open Questions
- *(All resolved. Codex round-2 refinements folded: lock-helper reuse (DD-008), baselines key-merge (EXT-002), /cmodelupgrade test/ABS ripple (EXT-003, in scope), /cdocs absent-file guard (EXT-004, BND-001), symlink creation-order (EXT-005, INV-010).)*
- **OQ-002 (resolved)**: calibration/baselines stdin byte ceiling = **64 KB**, counted with `wc -c`/`LC_ALL=C`, payload passed via temp-file/stdin (never argv). A calibration entry with `file_paths_touched[]` is ≪ 64 KB; well under the ~130 KB ARG_MAX ceiling even if a future path moves it toward argv.
