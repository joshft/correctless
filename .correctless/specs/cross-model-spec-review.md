# Spec: Cross-Model Spec Review via codex

## Metadata
- **Created**: 2026-06-16T18:40:00Z
- **Status**: draft (revised: codex rounds 1–3 + Claude 6-agent /creview-spec applied)
- **Impacts**: creview-spec, csetup, cstatus
- **Branch**: feature/cross-model-spec-review
- **Research**: null
- **Intensity**: high
- **Recommended-intensity**: high
- **Intensity reason**: project floor `high`; new trust boundary (external model output → Claude synthesis); external egress to OpenAI; injection surface (untrusted external LLM output); config-as-trust-input
- **Override**: none
- **Review-rounds**: codex 1–3 (19 findings) + Claude /creview-spec (30 findings, RS-001–RS-030) all applied. Scope: keep-whole.

## Context
Activates the dormant external-review path in `/creview-spec` with codex (GPT-5.5) as a first-class
adversarial reviewer that reads the whole spec alongside Claude's six agents, returns structured findings,
and records every run so acceptance-rate is measurable. A coded producer invokes codex read-only, captures
schema-constrained JSON to a file, and records the run. The dual-perspective value was demonstrated on this
very spec: codex's 3 rounds (19 findings) and Claude's 6 agents (30 findings) were complementary — the four
deepest issues (nonce-fence weakness vs the repo's own `build-caudit-prompt.sh` precedent, the live `Write`
grant, the single-deliverable lift machinery, the unbounded return path) required repo-convention knowledge
codex lacks; codex independently surfaced the install/sync (PMB-003) and config-tampering classes.

Mechanism verified by smoke test (codex 0.139.0): `codex exec --sandbox read-only --output-schema <f>
--output-last-message <f> --json --ephemeral -` returns clean schema JSON to the file, writes the file even
under read-only, and emits usage events on `--json`.

## Scope
**In scope:** producer `scripts/external-review-run.sh` (builds argv, invokes codex, validates output, records
the run; embeds the findings schema; subcommands `record`/`set-disposition`/`pending`); config updater
`scripts/config-update.sh`; `/creview-spec` Step 3 full rewrite; `/csetup` codex detection + config-update +
egress disclosure; `external-review-history.json` real writes + disposition back-fill; upgrade migration;
`workflow-config` full template; `cstatus` activation advisory; **ABS-042 + TB-008 + TB-001c** in
ARCHITECTURE.md; ABS-041 lift-and-restore generalized to N deliverables.

**Prerequisites (AP-008):** `creview-spec` allowed-tools — ADD `Bash(*external-review-run.sh*)`, **REMOVE**
`Write(.correctless/meta/external-review-history.json)` (RS-001). `csetup` allowed-tools — ADD
`Bash(*config-update.sh*)` (RS-019). AGENT_CONTEXT.md scripts count **27→29 (+2)** (RS-019).

**Out of scope:** porting correctless under other harnesses; cross-model **audit**; gemini/non-codex models
(schema generic, only codex activated/tested); wiring into `/creview` (standard); structural read-scope
path-exclusion for codex (full read-only repo scope is the author's accepted egress model — RS-011/INV-014).

## Complexity Budget
- **Estimated LOC**: ~750 (producer + embedded schema + nonce-fence ~280, config-update.sh ~110, creview-spec/csetup rewrites, template, tests ~250)
- **Files touched**: ~14 (producer, config-update.sh, 2 test files, 3 skills, full template, history template, SFG DEFAULTS, check-no-pending-sfg-lift.sh, hooks/workflow-advance.sh _done_phase_gate, ARCHITECTURE.md, AGENT_CONTEXT.md)
- **New abstractions**: 2 (ABS-042 sole-writer producer; TB-008 external-output boundary)
- **Trust boundaries touched**: 4 (TB-008 new; TB-001/TB-001c config→shell; TB-003 findings→synthesis; TB-007 untrusted-external analog)
- **Risk surface delta**: high — external egress + cross-vendor LLM injection boundary + a config-writing privileged script; bounded by nonce-fence, read-only, fail-open, true-allowlist, auto-off-when-absent.

## Invariants

### INV-001: codex-enforced structured output against the embedded schema
- **Type**: must · **Category**: data-integrity · **Risk**: high · **Test**: integration
- **Statement**: Invoked with `--output-schema <tmp>` (the findings JSON Schema embedded in the producer, written to a temp path **under `.correctless/artifacts/`** so a read-only-sandboxed codex with `--cd` repo-root can read it — RS-023) and `--output-last-message <file>`. The deliverable is the schema JSON in `<file>`, never stdout. Schema requires `{findings:[{id, title, severity, category, location, description}]}`, `severity ∈ {BLOCKING,HIGH,MEDIUM,LOW}`. A `trap … EXIT` removes the temp schema.
- **Enforcement**: schema embedded in the SFG-protected producer (propagates with the `.sh`, RS-001-class PMB-003 fix); structural test asserts argv contains both flags + schema path + the producer reads only the message file (negative fixture: prose on stdout, JSON in file → file wins).
- **Guards**: AP-026, PMB-011/016, PMB-003

### INV-002: parse-gate + bound + namespace + coerce
- **Type**: must · **Category**: data-integrity · **Risk**: high · **Test**: integration
- **Statement**: Before use, the output file is `jq -e .`-validated AND shape-checked: required fields present; **findings-array length capped and per-field byte-capped** (RS-007); each `finding.id` matched to `^EXT-[0-9]+$` and **namespaced so it can never collide with Claude's `RS-NNN`** (RS-007); `severity` out-of-enum values **coerced from known synonyms** (`CRITICAL→BLOCKING`, case-folded) and only the *offending finding* dropped-with-note on irrecoverable mismatch — never the whole payload (RS-021); `title/description/location` neutralized for the nonce-fence delimiter before any use (INV-009). On parse/shape failure: discard external findings, write a history record with `status:"unparsable"` (INV-007), Claude's review unaffected.
- **Enforcement**: producer parse-gate; behavioral tests feed malformed JSON, 10MB array, an `RS-001` id, a traversal `location`, an out-of-enum severity, and a fence-delimiter-bearing description — each handled per the rule.
- **Guards**: AP-026, AP-039

### INV-003: no project-artifact-sized data on argv (outbound)
- **Type**: must-not · **Category**: resource-lifecycle · **Risk**: high · **Test**: integration
- **Statement**: No artifact-sized data (spec body, ARCHITECTURE.md ~130KB+, antipatterns.md) on the codex argv. Spec via **stdin** (`-`); larger context via **read-only repo reads** (`--cd`). Argv carries only the short instruction + flags.
- **Enforcement**: producer pipes brief on stdin; structural test + `antipattern-scan.sh` arg-from-file rule over the producer; ≥200KB stdin scale-fixture asserts no ARG_MAX.
- **Guards**: AP-039 (PMB-019)

### INV-004: read-only sandbox bounds WRITES only — not reads or egress
- **Type**: must · **Category**: security · **Risk**: high · **Test**: integration
- **Statement**: Invoked `--sandbox read-only`. The working tree is unchanged except the designated output file under gitignored `.correctless/artifacts/`. **Read-only provides NO egress containment** (RS-011): codex has network (it calls OpenAI) and full repo read scope, so a compromised/injected codex can read and exfiltrate secrets — the egress boundary is INV-014's disclosure + the INV-005 gate, NOT the sandbox. The spec states this explicitly so "read-only" is not mistaken for "contained."
- **Enforcement**: structural test asserts `--sandbox read-only` + none of the banned flags; behavioral test asserts `git status` parity over tracked AND untracked files (no new files under the repo except the designated output path) — RS-011. The read-only *guarantee about codex itself* is an EA, not a test (the stub can't prove it).
- **Guards**: PMB-014, PMB-015

### INV-005: tri-state activation; template ships absent; Step 3 fully replaced
- **Type**: must · **Category**: functional · **Risk**: high · **Test**: integration
- **Statement**: Built from `.workflow.external_models.codex` (not skill-hardcoded — INV-015). `.workflow.require_external_review` tri-state: `true`=force on, `false`=force off, **absent/null=auto** (runs at high+ effective intensity when a codex entry exists AND `command -v codex` succeeds). The **template ships `require_external_review` ABSENT** (the round-1 `false` is removed — RS-005) and `external_models:{}`. The dormant Step 3 prose (`{prompt}` substitution) is **fully replaced** — no `{prompt}` or `codex exec` literal remains in the skill (RS-028); a hand-added legacy `{prompt}` entry is rejected fail-closed by INV-017, not shell-executed.
- **Enforcement**: structural tests assert the template does NOT contain `"require_external_review": false` AND contains no `{prompt}`/`codex exec` literal in `creview-spec`; behavioral test over the tri-state × intensity × codex-presence × entry-presence matrix (decisive cells enumerated: absent+high+present+entry⇒run; absent+high+absent⇒skip; absent+standard⇒skip; false+high⇒skip; **true+standard ⇒ runs** [force-on overrides the high+ floor — resolved]).
- **Guards**: AP-025; dormancy-by-default (round-1 #1, RS-005)

### INV-006: graceful degradation — failure never blocks; status distinguished
- **Type**: must · **Category**: functional · **Risk**: high · **Test**: integration
- **Statement**: `command -v codex` upfront. Absent / timeout (`timeout "$timeout_seconds"`) / non-zero / empty / unparsable → skip with a surfaced note, proceed Claude-only, no retry, no abort. The run-record `status` **distinguishes** `skipped` (codex absent) from `error` (present but failed: quota/network/non-zero) so an operator can tell cross-model review silently stopped (RS-024).
- **Enforcement**: behavioral tests for each failure mode (all require the INV-018 stub) assert Claude-only completion and the correct `status`.
- **Guards**: silent-blocking; silent-telemetry-failure

### INV-007: sole-writer run-record — coupled, seeded, locked, run_id-keyed
- **Type**: must · **Category**: data-integrity · **Risk**: high · **Test**: integration
- **Statement**: The producer writes into the top-level `{"reviews":[…]}` wrapper in the **same execution** as the codex call (`record`). **If the history file is absent, the producer self-seeds `{"reviews":[]}`** (decoupled from the setup install gate — RS-009). Record: `{run_id, spec_slug, model, codex_version, timestamp, status, findings:[{id, severity, disposition:null}]}`. Failed runs recorded too. `run_id = {spec_slug}-{compact-UTC-ISO}-{4-hex}` with collision re-roll. **The append uses the ABS-003 `locked_update_file` pattern** (not raw jq-to-file) so concurrent runs don't lose records (RS-012). The **`--output-last-message` file path embeds the full run_id** (`.correctless/artifacts/external-review-{run_id}.json`) so concurrent runs never collide/TOCTOU (RS-013). Producer is **sole writer**; `/creview-spec` never writes the file (INV-013 removes the grant).
- **Enforcement**: structural test the producer sources `lib.sh` locking + self-seeds; behavioral test a successful run appends exactly one well-formed record, a failed run appends a `status:error` record, concurrent runs preserve both.
- **Guards**: AP-026, PMB-005, ABS-003

### INV-008: disposition back-fill, attribution, pending surfacing
- **Type**: must · **Category**: parity · **Risk**: medium · **Test**: integration
- **Statement**: Dispositions written back **through the producer** (`set-disposition <run_id> <finding_id> <disp>`), enum `accepted|rejected|modified|deferred|duplicate`; unknown run_id/finding_id or out-of-enum → non-destructive failure. codex findings are **written into the Step 3.5 `review-spec-findings-{slug}.md` artifact before Step 4** (AP-029 persist-before-present — RS-017) and **attributed `Source: codex (external)`**; dedup-merged findings carry both sources (RS-017). The producer's `pending` subcommand lists `completed` runs with null-disposition findings and is **surfaced at the START of `/creview-spec` (and in `/cstatus`)** to catch stale un-adjudicated prior-session runs (RS-027).
- **Enforcement**: structural test the 5-value enum; behavioral tests for set-disposition round-trip, negative keys, `pending` listing; structural test codex findings appear in the Step 3.5 artifact with attribution.
- **Guards**: silent-telemetry-failure, AP-029

### INV-009: nonce-delimited fence + neutralization (injection defense)
- **Type**: must · **Category**: security · **Risk**: high · **Test**: integration
- **Statement**: codex output enters Claude's synthesis wrapped in a **per-invocation nonce-delimited fence** and neutralized — adopting `scripts/build-caudit-prompt.sh`'s pattern VERBATIM, not a static fence (RS-002). Specifically: a fresh 128-bit nonce in BOTH open/close delimiters (`<UNTRUSTED_EXTERNAL_REVIEW nonce="…">`…`</UNTRUSTED_EXTERNAL_REVIEW nonce="…">`); `_neutralize_fences`-style neutralization of any literal fence token, `nonce=`, and framing markers in EVERY untrusted field (`id/title/description/location/category`); treated as advisory data, never instructions; surfaced only via the Step 4 human-disposition gate (PRH-003).
- **Enforcement**: reuse the existing `build-caudit-prompt.sh` functions (do not re-derive); structural test feeds a finding whose `description` contains `</UNTRUSTED_EXTERNAL_REVIEW>` + a forged `SYSTEM:`/framing line and asserts the emitted synthesis prompt neutralizes it (the nonce-escape IS mechanically testable). The semantic "treats as data" property is enforced by the nonce-fence + PRH-003 gate, not an automated test.
- **Guards**: prompt-injection (multi-hop codex→synthesis→spec), PMB-014

### INV-010: ephemeral/SFG-safe paths; three-form DEFAULTS; config via updater
- **Type**: must · **Category**: resource-lifecycle · **Risk**: medium · **Test**: unit
- **Statement**: Output + temp-schema files under gitignored `.correctless/artifacts/` (never consolidation-staged), paths not colliding with SFG DEFAULTS patterns. History at `.correctless/meta/`. BOTH privileged writers (`external-review-run.sh`, `config-update.sh`) added to SFG DEFAULTS **in all three path forms** (`scripts/X.sh`, `.correctless/scripts/X.sh`, bare `X.sh` — RS-029), in the final commit, with the **generalized** ABS-041 lift-and-restore affordance (INV-020). `/csetup`'s write of the SFG-protected `workflow-config.json` is via `config-update.sh` (no-direct-redirect), never the agent Edit tool.
- **Enforcement**: structural tests on output path (artifacts/, gitignored, not SFG-matched); three-form DEFAULTS entries + `tests/test-sensitive-file-guard.sh` block-both-paths coverage; behavioral test SFG allows `Bash(config-update.sh …)` but blocks direct Edit/redirect to the config (RS-016 live-guard).
- **Guards**: AP-037 (PMB-017), AP-022

### INV-011: external cost from the (untrusted) --json usage event
- **Type**: must · **Category**: functional · **Risk**: low · **Test**: unit
- **Statement**: Cost parsed from the **`--json` JSONL usage event** (stable), not human stdout. The `--json` stream is **also untrusted codex output** — the usage value is `jq -e`-parsed and numeric-bounded; any anomaly → "unavailable" (RS-022). Absent event → "external cost not tracked this run; does not affect the review" (reassuring, not alarming — RS-030). `/creview-spec` surfaces approximate cost.
- **Enforcement**: producer reads the `--json` usage event with bound-checking; test asserts a cost line when present, the reassuring "unavailable" text when absent/malformed. Exact event JSON path pinned post-RED-capture (INV-021).
- **Guards**: silent external-cost accrual; fragile-stdout-parse

### INV-012: whole-spec payload, not flagged-subset
- **Type**: must · **Category**: functional · **Risk**: medium · **Test**: integration
- **Statement**: codex receives the ENTIRE spec on stdin (+ hybrid read-only repo), never a `needs_external_review`-flagged subset.
- **Enforcement**: structural test captures the stub's stdin and asserts it contains the full spec body AND that a flagged + an unflagged invariant both appear (negative regression to subset).

### INV-013: producer reachable; direct history Write removed; csetup grant
- **Type**: must · **Category**: functional · **Risk**: high · **Test**: unit
- **Statement**: `creview-spec` allowed-tools includes `Bash(*external-review-run.sh*)` and **does NOT include `Write(*external-review-history.json*)`** — the existing grant is REMOVED so the producer is genuinely sole-writer (RS-001). `csetup` allowed-tools includes `Bash(*config-update.sh*)` (RS-019).
- **Enforcement**: AP-008 cross-check asserting BOTH the *presence* of the Bash grants AND the *absence* of the direct history Write from `creview-spec` frontmatter (negative assertion); a test asserts the csetup grant.
- **Guards**: AP-008, AP-022

### INV-014: egress disclosed (prompt-level), sensitive categories named
- **Type**: must · **Category**: security · **Risk**: medium · **Test**: unit
- **Statement**: codex reads the full repo read-only. `/csetup` discloses **once** that the whole repo context — **explicitly including any secrets, `.env`, and git history present** (RS-030) — may be sent to OpenAI. Per-run send-time visibility is provided by INV-022. The egress is the documented, auto-off-when-codex-absent boundary.
- **Enforcement**: prompt-level (no structural mechanism can force a human to read a disclosure — labeled per PAT-018); section-aware test asserts the enumerated disclosure text appears in the csetup codex-detection block.
- **Guards**: undisclosed-egress

### INV-015: structured codex entry, executed without a shell
- **Type**: must · **Category**: security · **Risk**: high · **Test**: integration
- **Statement**: `.workflow.external_models.codex` is a structured object `{bin, base_args:[...], model, timeout_seconds, stdin:true}`. The producer builds an **argv array** and execs codex **without a shell** (no `eval`/`sh -c`/`bash -c`/backticks/string-interpolation of config values). The prompt is on stdin (INV-003), never argv.
- **Enforcement**: structural test the producer builds an argv array, contains no eval-family over config strings; `antipattern-scan.sh` shell-injection rule; argv-capture seam (fake-codex `printf '%s\n' "$@"` — INV-018) so the test inspects the real constructed array.
- **Guards**: config→shell injection (TB-001/TB-001c)

### INV-016: config updater merges without clobbering; handles missing keys; jq-arg-safe
- **Type**: must · **Category**: data-integrity · **Risk**: high · **Test**: integration
- **Statement**: `config-update.sh set-external-model codex <fields…>` jq-merges into `.workflow.external_models.codex`, **creating `.workflow`/`.workflow.external_models` if absent** (RS-016 upgrade case), preserving all other keys, atomic temp+mv, idempotent. **Every field passed via `jq --arg/--argjson`**, never interpolated into the jq program (RS-016 injection). SFG-permitted (no-direct-redirect), itself in SFG DEFAULTS (INV-010).
- **Enforcement**: AP-004 state matrix (clean / other-model present / pre-existing-codex / **missing `external_models` key**); idempotency; jq-injection test (`model='"} | .workflow={}'` → siblings survive); malformed config → fail-closed + report (BND-003/OQ-006).
- **Guards**: config clobber, AP-022, TB-001c

### INV-017: config-sourced argv validation (closed allowlist, all fields)
- **Type**: must · **Category**: security · **Risk**: high · **Test**: integration
- **Statement**: Before invoking, the producer validates the WHOLE config-sourced invocation as a **closed allowlist**, fail-closed (skip + `status:skipped`) on any violation: `bin` **realpath-resolved** to a system `codex` (reject relative paths, repo-internal paths, `node_modules/.bin`, symlinks to non-codex — basename-only is insufficient, RS-006); every `base_args` token on a known-safe allowlist **with its argument-shape** (`--sandbox`∈{read-only}; `--cd`∈{repo-root, realpath-confined — reject `/`, `..`-escape}; `--output-schema`/`--output-last-message`/`--json`/`--ephemeral`/`-` permitted with producer-controlled values); **unknown-but-not-explicitly-banned flags rejected** (`--proxy` etc. — RS-006); `model` charset `^[A-Za-z0-9._-]+$`, single argv element, never split/concatenated; `timeout_seconds` numeric and **clamped ≤300s** (RS-026). Flags-with-arguments parsed pairwise.
- **Enforcement**: behavioral tests reject `bin:/bin/sh`, a symlinked bin, `--cd /`, an unknown `--proxy`, a banned `--sandbox danger-full-access`, `model:"x --add-dir /"`, `timeout_seconds:86400` — each fail-closed.
- **Guards**: config-tampering escalation (RS-006), AP-024 (allowlist not denylist), AP-032

### INV-018: codex binary injectable (test stub seam)
- **Type**: must · **Category**: testability · **Risk**: high · **Test**: integration
- **Statement**: The producer resolves the codex executable from config `bin` (not a hardcoded `codex` on PATH), reconciled with INV-005/006's `command -v codex` so the same fixture satisfies both. A shared `tests/external-review-test-helpers.sh::make_fake_codex` generates a `$tmpdir/codex` (basename literally `codex` to satisfy INV-017) that reads stdin, writes a caller-supplied JSON to the `--output-last-message` path, emits caller-supplied JSONL on `--json`, echoes its argv (`printf '%s\n' "$@"`) for INV-015 capture, and exits with a caller-supplied code — enabling deterministic offline replay of all INV-006 failure modes. Deterministic seams: `run_id` RNG/clock injectable for collision tests (RS-008).
- **Enforcement**: structural test the producer reads `bin` from config and never invokes a bare `codex`; the helper exists and all behavioral tests use it (no network).
- **Guards**: untestable-integration, AP-031

### INV-019: bound + neutralize the codex-output RETURN path
- **Type**: must · **Category**: security · **Risk**: high · **Test**: integration
- **Statement**: The codex-output → producer/jq/synthesis direction is bounded (the inverse of INV-003): cap findings-array length + per-field bytes (reuse `_neutralize_and_cap_to_file`); **all codex-output field content routed to jq via `--rawfile`/stdin, never `--arg`** (ARG_MAX-in-reverse, RS-007); strip NUL + control/terminal-escape chars before any value reaches the history file or the human's terminal; `location` treated as **opaque display text, never resolved as a filesystem path** (or canonicalized + repo-confined) — RS-007.
- **Enforcement**: behavioral tests feed a 200KB description, a 10^4-finding array, NUL/escape-laden fields, and a `../../etc/passwd` location — each bounded/neutralized/non-resolved.
- **Guards**: AP-039-reverse, path-traversal

### INV-020: ABS-041 lift-and-restore generalized to N deliverables
- **Type**: must · **Category**: data-integrity · **Risk**: high · **Test**: integration
- **Statement**: The lift-and-restore backstop is generalized from the single hardcoded `agents/fix-diff-reviewer.md` to **all SFG-DEFAULTS deliverables under active lift** (RS-003): `scripts/check-no-pending-sfg-lift.sh` and the `_done_phase_gate` sentinel record the **set** of lifted paths; self-deactivation (RS-028 pattern) checks each lifted path's restoration independently, so lifting `external-review-run.sh` while `fix-diff-reviewer.md` is restored does NOT falsely self-deactivate. (Alternatively, if the new files are created entirely fresh and protected only in the final commit with no intermediate lift, the spec may scope them out of the lift contract — but the generalization is required the first time any is edited under protection.)
- **Enforcement**: multi-deliverable structural test: lift A, restore B, assert the backstop still FAILS (A un-restored); restore A, assert it passes.
- **Guards**: AP-037, AP-036

### INV-021: real-fixture capture; EA-004/OQ-005 as RED gates
- **Type**: must · **Category**: testability · **Risk**: high · **Test**: integration
- **Statement**: RED **captures and commits** one real codex 0.139.0 `--output-last-message` JSON and one real `--json` JSONL stream as canonical fixtures (with `# Source:` provenance, PAT-020), resolving EA-004 and OQ-005 as **blocking RED gates** before INV-001/002/011 are claimed satisfied: the smoke must prove `--json` + `--output-last-message` compose in one call (OQ-005) and pin the exact usage-event JSON path (EA-004). If composition fails, the design splits and the spec is revised before GREEN.
- **Enforcement**: fixtures present in the repo with provenance; a drift test pins the producer's jq usage-path string to the committed real fixture's actual field path.
- **Guards**: AP-031, PMB-010

### INV-022: consolidated external-review status surface
- **Type**: must · **Category**: ux · **Risk**: medium · **Test**: unit
- **Statement**: Every high+ `/creview-spec` run with codex configured surfaces an **external-review status block** in BOTH live output and the persisted `review-spec-findings-{slug}.md` artifact: `{ran | skipped(reason) | error(reason)}`, **what egressed** (a per-run send-time one-liner before the call: "Sending full repo context to codex (OpenAI)…" — RS-017), approx cost (INV-011), and **how to disable** (`require_external_review:false`). A progress line is shown while codex runs (consistent with the mandatory progress contract — RS-017). This single block closes the silent-downgrade, attribution, send-time-notice, and off-switch-discovery gaps.
- **Enforcement**: structural tests the status block appears in the artifact for ran/skipped/error; the send-time egress line precedes the call; the disable hint is present.
- **Guards**: silent-downgrade, AP-029

### INV-023: upgrade activation + migration of pre-existing force-off
- **Type**: must · **Category**: upgrade-compat · **Risk**: high · **Test**: integration
- **Statement**: Existing projects carry an explicit `require_external_review:false` from the old template, which under tri-state means force-off forever. On `/csetup` re-run (the documented upgrade activation path), if a pre-existing **old-default** `false` is detected, `/csetup` surfaces a decision to migrate it to absent/auto (with the INV-014 disclosure) — `config-update.sh` gains a `set-require-external-review <true|false|auto>` subcommand for this (which also serves as the **off-switch**, RS-017). `/cstatus` (and the start of `/creview-spec`) emits a one-time advisory when codex is on PATH but `external_models` is empty: "codex detected — run /csetup to enable cross-model spec review" (RS-010), so the feature is discoverable rather than invisibly dormant.
- **Enforcement**: behavioral test: seed an old-default `false` config, run the migration path, assert the offered flip; advisory-text test; `set-require-external-review` round-trip.
- **Guards**: upgrade-dormancy (RS-010), AP-025

## Prohibitions
- **PRH-001** no unsafe sandbox (`workspace-write`/`danger-full-access`/`--dangerously-bypass-*`/`--add-dir`) — from template default OR tampered config (INV-017 runtime reject). Detection: argv + template grep + INV-017 behavioral.
- **PRH-002** no artifact bodies on argv — **both directions** (outbound INV-003, return-path INV-019). Detection: antipattern-scan arg-from-file + scale fixtures.
- **PRH-003** no auto-incorporation — a codex finding never edits the spec without the Step 4 human gate. Detection: structural — the disposition gate exists and the skill grants no tool path for a finding to write the spec.
- **PRH-004** never block on external failure (incl. a clamped timeout, RS-026). Detection: behavioral failure-mode suite.
- **PRH-005** no shell execution of the codex command — argv array only. Detection: antipattern-scan shell-injection.
- **PRH-006** config updater must not clobber — jq-merge, atomic, `--arg`-safe. Detection: populated-config + jq-injection tests.
- **PRH-007** codex output never resolved as a filesystem path or shell token; codex finding ids never in Claude's `RS-` namespace. Detection: INV-019/INV-002 tests.

## Boundary Conditions
- **BND-001** codex output → synthesis: untrusted; `jq -e` + schema-shape + nonce-fence neutralize (INV-002/009); fail-open discard.
- **BND-002** external_models config → argv: structured object; argv-array no-eval (INV-015/PRH-005); closed-allowlist validation (INV-017); fail-open skip.
- **BND-003** /csetup → active config write: only via `config-update.sh` jq-merge (INV-016); fail-closed on malformed existing config; never agent Edit.
- **BND-004** codex `--json` stream → cost: untrusted; `jq -e` + numeric-bound (INV-011); "unavailable" on anomaly.

## STRIDE (TB-008: codex output → Claude synthesis → spec)
- **Spoofing**: forged framing/instruction in a finding field → INV-009 nonce-fence + neutralization (not a static fence) + INV-001 schema.
- **Tampering**: tree mutation → INV-004 read-only + PRH-001; config→shell → INV-015/PRH-005; config-flag/bin/model tampering → INV-017; config clobber → INV-016/PRH-006.
- **Repudiation**: no trace → INV-007 coupled, locked, sole-writer record.
- **Information disclosure**: full-repo egress to OpenAI (incl. secrets) — read-only does NOT contain this (INV-004); boundary is INV-005 gate (auto-off when absent) + INV-014 disclosure + INV-022 per-run notice. Author-accepted for this repo; disclosed for downstream.
- **DoS**: codex hangs/floods → INV-006 clamped timeout + fail-open; INV-003/INV-019 bound both argv directions; output is one run_id-keyed file.
- **Elevation of privilege**: findings gain spec-edit authority → PRH-003 human gate + INV-009 advisory.

## Environment Assumptions
- **EA-001** codex `exec` supports `--sandbox read-only/--output-schema/--output-last-message/--json/--ephemeral/-`. Verified codex 0.139.0. Semantic drift (sandbox/output-format meaning changing while flags stay valid) is NOT caught by INV-006 flag-absence; `codex_version` is captured into each run-record (INV-007) so drift is observable. Flag-name drift → INV-015 config edit + INV-006 skip.
- **EA-002** codex pre-authenticated; **and** the OpenAI account has quota/credits + valid key (RS-024) — exhaustion → `status:error` (INV-006), not silent zero.
- **EA-003** `--output-last-message` writes under read-only (verified).
- **EA-004** `--json` carries a stable usage event — **RED gate (INV-021)**, not an assumption; INV-011 falls back to "unavailable" if absent.
- **EA-005** jq 1.7+ (ENV-002) for the producer + config-update.sh; PMB-001 precedence — bound expressions wrapped in explicit parens (PAT-010); **CI jq 1.7.1/1.8.1 matrix** over both new scripts (AP-011, RS-014).
- **EA-006** network reachability to OpenAI + DNS/TLS/clock valid (RS-024) — a present-but-unreachable codex burns the (clamped) timeout once then skips.
- **EA-007** Bash 4+ (ENV-001) for `local -a` argv arrays + `[[ =~ ]]`; POSIX-portable grep/sed/awk (ENV-006) in the producer + structural tests (RS-025) — else silent macOS failure / false-negative structural tests.
- **EA-008** wall clock correct + non-back-stepping for `run_id` identity (RS-024) — collision re-roll covers same-second; `set-disposition` keys on the exact run_id string.

## Architecture Additions (draft bodies for ARCHITECTURE.md)
- **TB-008: External model output → Claude review synthesis → spec.** Crosses: codex (external LLM, own network + full read-only repo scope, cross-vendor/cross-process) → producer → Claude synthesis → spec. Stronger than TB-007 (web content via write-free agent): codex output is *shaped like review findings* (the form the orchestrator acts on) AND the reviewer binary is config-selected (TB-001c) AND egresses the repo. Invariant: nonce-fence + neutralization (INV-009), schema + parse-gate + bounds (INV-001/002/019), advisory-only + human gate (PRH-003), sole-writer record (INV-007). Violated when: static fence; unbounded return path; config-tampering selects a binary/flags; findings auto-incorporate. The TB-007 /cauto "acknowledged gap" does NOT apply (external review is /creview-spec-only).
- **ABS-042: Sole-writer external-review producer.** `external-review-run.sh` is the sole writer of `external-review-history.json` and the codex output file; invocation-coupled (`record` in the same exec as the codex call), locked (ABS-003), self-seeding. **Deviation note (RS-020):** chooses invocation-coupling over the ABS-029 `cmd_*` phase-transition gate — justified because no phase transition depends on the history file; `pending` is the surfacing mechanism. Documented explicitly per PAT-018, like ABS-033 documents its deviation.
- **TB-001c: Structured external-tool config → argv (no eval).** A third config→shell exception class (beyond TB-001a/b eval'd commands): a structured object selecting a binary + argv array, executed without a shell, gated by bin-realpath + closed flag-allowlist (INV-015/017). Cites TB-001a's must-flag convention (honored). First config input treated as untrusted-against-tampering rather than owner-trusted. TB-003 (findings→synthesis) places codex on the "external untrusted → structural fence" side. **Drop the TB-005 over-citation** (intra-Claude handoff ≠ cross-vendor egress).

## Design Decisions
- Nonce-fence reuse (RS-002): INV-009 reuses `build-caudit-prompt.sh` functions verbatim — the repo already solved this exact threat; re-deriving a weaker static fence was the gap.
- Sole-writer producer (ABS-042) with invocation-coupling + ABS-003 locking + self-seed; deviation from ABS-029 gate justified above.
- Closed allowlist over denylist (RS-006): INV-017 enumerates safe; denylists rot against a moving external CLI (AP-024).
- Keep-whole scope (user decision): core + activation (config-update.sh, /csetup, migration) + UX status surface shipped together; ABS-041 generalized to N deliverables to support it.
- Embedded schema (RS-001-class): propagates with the `.sh`, dodging the PMB-003 `scripts/*.json` install gap.
- Full-repo egress accepted by author (RS-011): read-only ≠ egress containment, stated explicitly; structural exclusion deferred (downstream affordance).

## Open Questions
- **OQ-001** large-spec stdin: pin truncate-with-marker vs skip-with-note (truncation degrades the adequacy read) — resolve in RED.
- **OQ-002** codex-vs-Claude dedup key (title / area+severity / spec-rule ref) — resolve in RED so the synthesis test is concrete.
- **OQ-005** `--json` + `--output-last-message` composition — **promoted to RED gate (INV-021)**.
- **OQ-006** `config-update.sh` on malformed config + monorepo (`is_monorepo:true`) — fail-closed + report (BND-003); confirm monorepo path in RED.
- **OQ-007** read-only-sandbox readability of the temp schema under `.correctless/artifacts/` with `--cd` repo-root — confirm in the INV-021 smoke (RS-023).
