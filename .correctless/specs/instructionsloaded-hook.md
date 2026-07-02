# Spec: InstructionsLoaded hook — direct rule-load observability for PAT-001 (Feature B / FUTURE-001)

## Metadata
- **Created**: 2026-07-01T09:24:52Z
- **Status**: reviewed
- **Impacts**: path-scoped-rules-pat001 (upgrades its MG-001 signal from indirect proxy to direct *observation*; does NOT re-open its accepted gate). Enables FUTURE-002. Adds a backward-compatible `session_id` field to `hooks/audit-trail.sh` output (display-alignment aid).
- **Branch**: feature/instructionsloaded-pat001-measurement-gate
- **Research**: none (harness contract verified directly against code.claude.com/docs/en/hooks + raw CHANGELOG on 2026-07-01; see memory reference-cc-feature-verification-2026-07)
- **Recommended-intensity**: high
- **Intensity**: high
- **Intensity reason**: file-path signal — touches `hooks/` (new hook + audit-trail change) and `setup` (register_hooks) and amends security-adjacent abstraction ABS-004
- **Override**: none
- **Review**: round 1 + round 2 (external) + round 3 (multi-agent /creview-spec, 2026-07-01). Round 3 reshaped the feature from an automated MG-001/MG-002 classifier to a human-judged observability log — see Review History and DD-007.

## Context

This is **Feature B (FUTURE-001)** from the `path-scoped-rules-pat001` spec: an `InstructionsLoaded` hook that records, to a local gitignored JSONL log, each time a `.claude/rules/*.md` rule file is loaded into agent editing context — plus a `/cwtf` section that **presents** that log (rule-load events, with timestamps) alongside the hook-edit entries from `audit-trail`, so a human investigating a clause-5 hook-rule violation can *see* whether the `hooks-pretooluse.md` rule was in context around the edit and **classify it themselves**. The `InstructionsLoaded` hook was verified to exist in Claude Code since 2.1.69 (installed harness 2.1.185). **This does not re-litigate the PAT-001 measurement gate** — that gate already fired and was accepted on 2026-04-14 (`prevention_observed`, qualified, via indirect git-archaeology proxy). This feature *upgrades the signal* from that indirect proxy to direct runtime observation, exactly as the 2026-04-14 report's "Continued monitoring" section anticipated ("a signal upgrade, not a prerequisite").

**Round-3 reshaping (DD-007):** the earlier draft built an automated correlator that classified each hook edit as MG-001 vs MG-002 by joining the rule-load log to audit-trail on `session_id` + whole-second `ts`-ordering + path match. Multi-agent review found ~8 CRITICAL/HIGH findings that were all failure modes of that one fragile cross-file join, every one biasing the verdict optimistic (the DA-004 "flying blind" class — demonstrated live when cross-model codex review turned out to have silently skipped every run on this machine). Because this is an advisory, forward-looking signal on an already-accepted gate, the join's risk is not worth its value. The feature is scoped down to **raw observability the human interprets** — no machine verdict (PRH-005). This matches `/cwtf`'s "present findings with context, not judgment" ethos and the project's "no build-pipeline complexity for runtime problems" preference.

## Scope

**In scope:**
- New fail-open telemetry hook `hooks/instructions-loaded.sh` (+ synced `correctless/hooks/` mirror via `sync.sh`).
- Update `hooks/audit-trail.sh` (+ mirror + tests) to include `session_id` in each entry — a **display-alignment aid** so `/cwtf` can show rule-loads next to hook-edits for the same session (INV-015). Backward-compatible JSONL field addition. Consumers are a mix (RS-028): **filename-only** (`scripts/wf/utility.sh`, `scripts/prune-scan.sh`) and **content-parsing** (`scripts/compute-session-cost.sh:185-199` extracts `.phase`/`.timestamp`; `/cmetrics`, `/csummary` read entries). All extract specific fields via `jq`, so an *additive* `session_id` field is backward-compatible — but the claim is "additive-safe," NOT "no consumer parses content." The new ABS entry (RS-024e) must enumerate the real producers/consumers and the mixed record shapes.
- Amend `setup`'s `register_hooks()` + ABS-004 to recognize `HOOK_TYPE: InstructionsLoaded` through a **generalized (glob-driven) type→timeout mechanism** — covering **all** registration seams: fresh-install emission, existing-settings detection/update, matcher-drift repair, invalid-settings regeneration, and the `correctless/setup` mirror via `sync.sh` (INV-013). This is a **refactor** of the current hardcoded 2-type dispatch, not a one-line branch (INV-007, RS-003).
- A new `/cwtf` section that **reads and presents** `.correctless/meta/instructions-loaded.jsonl` (rule-load events) and the session's `audit-trail` hook-edit entries, with plain-language framing and a **liveness line**, then persists the presentation into the existing `/cwtf` report artifact (AP-029). Read via `/cwtf`'s existing `Bash(jq*)`/`Bash(grep*)`/`Bash(find*)` tools — **no new helper script and no new Bash grant** (DD-008). The human classifies; the section emits **no** MG-001/MG-002 verdict (PRH-005).
- Local JSONL log at `.correctless/meta/instructions-loaded.jsonl` (gitignored runtime telemetry) + `.gitignore` entry.
- New `ENV-012` entry in `.correctless/ARCHITECTURE.md` (InstructionsLoaded hook availability). Reconcile the `ENV-005` reference (round-1 wording called it "canary-only"; ENV-005 is actually "path-scoped rule loading" — update only if the direct signal changes its text).
- New `ABS-006`-modeled ABS entry for the audit-trail JSONL producer/consumer contract (its schema now has a downstream reader) — see RS-024(e).
- Tests: hook behavior, registration wiring + widened `test-ci-hook-wiring.sh` grammar (INV-007), audit-trail session-field test, `/cwtf` presentation/dormant tests, and a **real captured payload fixture** (AP-031 / INV-012).
- Doc-count updates: hook/test counts in `.correctless/AGENT_CONTEXT.md` and `CONTRIBUTING.md`.

**Out of scope (Won't Do):**
- **Any automated MG-001/MG-002 classification / cross-file correlator** (PRH-005 / DD-007). The human reads the evidence and classifies. No `ts`-ordering verdict, no session machine-join, no correlate helper script.
- Re-running or modifying the 2026-04-14 measurement report — no historical rule-load events exist to measure; forward-looking only (PRH-003).
- Making any gate or phase transition *depend* on the log — advisory; consumers degrade to dormant when it is absent (PRH-004).
- Adding the log to `sensitive-file-guard.sh` DEFAULTS — per-session telemetry, not a security asset; protecting it manufactures AP-037 edit friction against an AP-040 non-threat (PRH-002).
- Migrating additional PAT entries (FUTURE-002) or generating user-project rules (FUTURE-003).

## Complexity Budget
- **Estimated LOC** (re-baselined per RS-003): ~55 (hook) + **~60–90 (register_hooks refactor: collapse the hardcoded 2-arm `case` at `setup:483-490`, the fresh-install `hooks:{PreToolUse,PostToolUse}` object at `setup:571-572`, and the 4 duplicated timeout literals at `setup:533/542/681/699` into one glob-driven type→timeout map spanning all 5 seams)** + ~6 (audit-trail session field) + `/cwtf` section (read+present, no helper) + ~1 (.gitignore) + tests (~2 new files, ~3 updated).
- **Files touched**: ~13 (instructions-loaded hook ×2 mirror, audit-trail ×2 mirror, setup ×1 + mirror, .gitignore, cwtf SKILL.md, ARCHITECTURE.md ABS-004/ENV-012/new-ABS/ENV-005, AGENT_CONTEXT.md, CONTRIBUTING.md, tests ×3). **No correlate script** (DD-007/DD-008).
- **New abstractions**: 1 new ABS (audit-trail JSONL producer/consumer contract, ABS-006-modeled) + **amends ABS-004** (two-type → generalized type set — RS-002); adds one advisory telemetry artifact.
- **Trust boundaries touched**: 1 (harness→hook stdin). No TB currently documents this boundary though 5 hooks already consume it; this spec adds **TB-010 (Claude Code harness → hook stdin JSON)** and references it from BND-001/INV-004 (RS-024f), rather than mislabeling the analogy as TB-003.
- **Risk surface delta**: low (advisory hook + human-judged presentation; the fragile automated join was removed in round 3). The residual surface is the `register_hooks` refactor and the ABS-004 amendment.

## Invariants

### INV-001: Hook is fail-open
- **Type**: must
- **Category**: functional
- **Statement**: `hooks/instructions-loaded.sh` never exits non-zero and never blocks. Missing `jq` → exit 0. Malformed/empty stdin → exit 0. Missing/unwritable `.correctless/meta/` → best-effort `mkdir -p` then exit 0 either way (RS-024d). Missing/old `scripts/lib.sh` or absent `canonicalize_path` function → exit 0 with **no log** (RS-031): the hook must NOT fall back to un-canonicalized prefix matching, which would reintroduce the traversal risk INV-002 guards; a missing canonicalizer means the scope decision can't be made safely, so skip silently (fail-open, observability-only). No `set -euo pipefail`; but `set -f` + `LC_ALL=C` at hook scope to stop path-field glob/word-splitting (house pattern, QA-R1-006, `audit-trail.sh:129-131` — RS-024a). (Correct posture because InstructionsLoaded exit codes are ignored by the harness — EA-003.)
- **Violated when**: any code path exits non-zero; `set -e`-style strict mode is present; or `set -f` is absent.
- **Enforcement**: CI test (empty stdin, malformed JSON, missing-jq simulation, unwritable meta-dir, **missing lib.sh / absent canonicalize_path** → assert exit 0 and no log written) + grep assertion that `set -f` is present and `set -e` is absent.
- **Guards against**: dead-behavior (PRH-001); path-field glob expansion.
- **Test approach**: unit

### INV-002: Fast-path scope — rule-file loads only, with defined path resolution
- **Type**: must
- **Category**: functional
- **Statement**: The hook appends a JSONL entry only when the event is a `.claude/rules/*.md` load — determined by: (a) the documented `file_path` field, **canonicalized via `canonicalize_path` (PAT-017) and then prefix-checked against `.claude/rules/`** (substring/suffix matching is prohibited — AP-032 / RS-011; if `canonicalize_path`/`lib.sh` is unavailable the hook skips with no log per INV-001 / RS-031, never an un-canonicalized match), OR (b) `file_path` is absent/malformed AND `load_reason == path_glob_match` (the future-compat/malformed defensive case, INV-005). CLAUDE.md loads, non-rule-file loads, path-traversal payloads (`.claude/rules/../../etc/x`), and absent-`file_path` events under any *other* load reason produce no entry.
- **Violated when**: a CLAUDE.md load, a traversal payload that canonicalizes outside `.claude/rules/`, an unrelated event, or an absent-`file_path` event under a non-`path_glob_match` reason writes a log line.
- **Enforcement**: CI test with fixtures: rule-file load (writes), CLAUDE.md load (no write), `.claude/rules/../evil.md` traversal (no write), absent-`file_path` + path_glob_match (writes null), absent-`file_path` + session_start (no write).
- **Test approach**: unit

### INV-003: JSONL entry schema
- **Type**: must
- **Category**: data-integrity
- **Statement**: Each appended line is a single valid JSON object with fields `ts` (ISO-8601 UTC, **byte-identical format to `audit-trail.sh:86`'s `date -u +%FT%TZ`** so the two logs display comparably — RS-005/RS-024i), `session_id` (from the payload's documented field; string or null), `rule_file` (from the payload's documented `file_path`, canonicalized; string or null), `trigger_file_path` (for `path_glob_match`, the file whose open triggered the load; string or null), `load_reason` (the matcher value), and `cwd`. **No `transcript_path`** (unused home-path disclosure surface — RS-024b).
- **Violated when**: a line fails `jq -e .`; any required field is absent; the `ts` does not match `^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$`; or a `transcript_path` field is present.
- **Enforcement**: CI test (`jq -e .` per line + field presence + `ts` regex + absence of `transcript_path`).
- **Test approach**: unit

### INV-004: Safe extraction AND safe serialization of harness input
- **Type**: must
- **Category**: security
- **Statement**: Every value read from stdin JSON is extracted safely (no stdin-derived value is `eval`'d or used as an unquoted path). The log line is **constructed with `jq -nc --arg`/`--argjson` (JSON-encoded), never `printf`/`echo` string interpolation** — so a `file_path`/`trigger_file_path`/`cwd` value containing a newline or JSON metacharacters produces exactly one well-formed line, never an injected second record (RS-020). Follows the `token-tracking.sh` precedent (`:112-135`) and TB-010.
- **Violated when**: a stdin value reaches a command line unquoted; any `eval` consumes an unsanitized field; or the log line is assembled by string interpolation rather than `jq -n`.
- **Enforcement**: CI test — (a) payload with shell metacharacters in `file_path` → logged literally, no command execution; (b) payload with an embedded newline in a field → exactly one JSONL line emitted; (c) grep assertion the log line is built via `jq -n`, not `printf`/`echo` of interpolated JSON.
- **Guards against**: shell injection + log-record forgery via a crafted harness payload (BND-001 / TB-010).
- **Test approach**: unit

### INV-005: Absent/malformed loaded-path — null logging for observability
- **Type**: must
- **Category**: functional
- **Statement**: The loaded-file path is normally the documented `file_path`. If it is absent or malformed (future-compat / harness-schema drift), the hook logs an entry with `rule_file: null` **only if** `load_reason == path_glob_match`; under any other reason it drops the event. Null-path entries are recorded for observability and surfaced by the INV-016 liveness line as a possible field-drift signal (a high null-ratio is a diagnostic, not silently ignored — RS-008/UX-001). The hook always exits 0.
- **Violated when**: an absent-`file_path` event under a non-`path_glob_match` reason is logged; or an absent-`file_path` `path_glob_match` event crashes / exits non-zero.
- **Enforcement**: CI test for both missing-path branches + assertion that the INV-016 liveness output counts null entries.
- **Guards against**: uncontracted-harness-default class (memory: project_uncontracted_model_defaults_antipattern).
- **Test approach**: unit

### INV-006: Registration emits the InstructionsLoaded entry [integration]
- **Type**: must
- **Category**: functional
- **Enforcement**: CI integration test — run `register_hooks()` against a temp project and parse the emitted `settings.json`.
- **Statement**: After `register_hooks()` runs, the generated `settings.json` contains an `InstructionsLoaded` hook entry of `type: command` pointing at `.correctless/hooks/instructions-loaded.sh`, with the timeout **field and value the EA-004 disposition selected** (the CI test asserts the concrete field+value chosen). This invariant covers *emission* only; whether the harness *honors* the field is recorded from a live registration in the verification report (EA-004), not asserted by CI (RS-015).
- **Violated when**: the hook installs but is not registered; is registered under the wrong event/type; or emits a timeout field/value differing from the EA-004 disposition.
- **Test approach**: integration
- **Integration contract**:
  Entry: run `setup`'s `register_hooks()` against a temp project (the existing `test-ci-hook-wiring.sh` harness)
  Through: real header parsing + real settings.json emission — not mocked
  Exit: parsed `settings.json` has an `InstructionsLoaded` array whose command path ends in `instructions-loaded.sh`, `type == "command"`, matcher == `*` (RS-026), timeout field == EA-004 disposition value; no stubbed settings writer

### INV-007: HOOK_TYPE header, generalized type→timeout mechanism, widened test grammar
- **Type**: must
- **Category**: functional
- **Enforcement**: CI test (register_hooks handles all three types via the generalized mechanism, not a per-type `case` arm) + ABS-004 drift coverage + the widened `test-ci-hook-wiring.sh` assertions.
- **Statement**: The hook carries `# HOOK_TYPE: InstructionsLoaded` and a `# HOOK_MATCHER: *` header in its first 10 lines. **The matcher MUST be `*` (fire on every load reason)** so DD-003's "log all `.claude/rules/*.md` loads" actually holds (RS-026): InstructionsLoaded matchers filter by load *reason* (`session_start`, `nested_traversal`, `path_glob_match`, `include`, `compact` — Claude Code hooks docs), so a reason-specific matcher such as `path_glob_match` would silently miss rule-file loads that occur under other reasons while still passing most direct hook tests. `register_hooks()` must emit that matcher, and a test must assert the **registered** InstructionsLoaded matcher value equals `*`. INV-002's scope filter (rule-file-only) is what narrows the `*`-matched firehose down to rule loads — matcher breadth + INV-002 filter together satisfy DD-003. `register_hooks()` is **refactored** so the new type flows through a single generalized type→timeout mapping (RS-003): the current hardcoded 2-arm `case` (`setup:483-490`, no default), the fresh-install object literal `hooks:{PreToolUse:$pre,PostToolUse:$post}` (`setup:571-572`), and the 4 duplicated timeout literals (`setup:533/542/681/699`) are replaced so adding a type requires **no** new hardcoded registration statement and **no** duplicated literal. `tests/test-ci-hook-wiring.sh` is widened at **every** pinned site (cite by function + anchor, not absolute line — they have drifted): add `instructions-loaded.sh` to the `auto_hooks` array (~`:191`) so the new hook is actually iterated; accept `InstructionsLoaded` in **both** HOOK_TYPE sites (the `grep -qE` regex ~`:208` **and** the equality gate ~`:218`); widen the HOOK_MATCHER grammar (~`:235`, and the second occurrence in `test_inv005` ~`:403`) from `^[A-Za-z]+(\|[A-Za-z]+)*$` (which rejects underscores and `*`) to admit the load-reason vocabulary and wildcard, e.g. `^([A-Za-z_]+|\*)(\|([A-Za-z_]+|\*))*$`.
- **Violated when**: the hook is registered via a bespoke hardcoded statement or a third `case` arm instead of the generalized mechanism; a timeout literal is duplicated; the `auto_hooks` array omits the new hook; any grammar site still rejects the new type/matcher; or the registered/header matcher is anything other than `*` (RS-026).
- **Guards against**: AP-024 (hardcoded list instead of glob), PMB-003 (stale hardcoded registration).
- **Test approach**: unit

### INV-008: /cwtf presents rule-load + hook-edit evidence read-only, JSONL-safe, no verdict [integration]
- **Type**: must
- **Category**: functional
- **Enforcement**: CI integration test — invoke the `/cwtf` presentation path over a log fixture + a real audit-trail fixture; assert read-only, JSONL-safe parsing, plain-language framing, and absence of any MG-001/MG-002 string.
- **Statement**: The `/cwtf` section reads `.correctless/meta/instructions-loaded.jsonl` (rule-load events) and the **target workflow/branch's** hook-edit entries from `audit-trail`'s per-branch JSONL, and **presents them raw** — rule-loads with timestamps + `trigger_file_path`, alongside hook-edits with timestamps — with plain-language framing. **Timestamp normalization (RS-030):** the audit-trail file is mixed-shape — the `audit-trail.sh` hook writes edit entries with `ts` (`hooks/audit-trail.sh:104`) while `/cauto` writes orchestration entries with `timestamp` (`skills/cauto/SKILL.md:534`) to the *same* file. `/cwtf` selects hook-edit entries (those with a `file` field under `hooks/`) and reads their time as `.ts // .timestamp`; the presentation and the new ABS (RS-024e) must handle both record shapes, and the test must cover both a `ts`-shaped and a `timestamp`-shaped entry ("`hooks-pretooluse.md` was loaded at HH:MM:SS; your `hooks/` edits were at …; you judge whether the rule was in context"). It emits **no automated classification** (PRH-005). **Session selection (RS-027):** the section must NOT filter rule-loads by "the current session" — `/cwtf` analyzes the most recent *or a past* workflow (`skills/cwtf/SKILL.md:15`), so the session running `/cwtf` is generally NOT the session that made the hook edits. Instead, derive the set of `session_id`s from the **target workflow/branch's hook-edit audit-trail entries**, then present rule-load events belonging to those session_ids, **grouped per session** (each edit-session shown with its matching rule-loads). If an edit entry has no session_id (pre-instrumentation) it is shown in an "unattributed" group. Both JSONL reads use the project consumer contract (`jq -R 'try(fromjson) catch empty'`, skip malformed lines, never `jq -s`; stream/bounded read, never slurp the whole log into a variable/argv — ABS-006 / AP-014 / RS-012). The section reads via `/cwtf`'s existing `Bash(jq*)`/`Bash(grep*)`/`Bash(find*)` tools; **no new helper script, no new Bash grant** (DD-008). Audit-trail edits are located by globbing `audit-trail-*.jsonl` for the target branch (RS-010, display-accuracy); edits made off-workflow do not appear in audit-trail and the section notes this caveat (RS-022).
- **Violated when**: the section emits any MG-001/MG-002 verdict; filters rule-loads by the `/cwtf`-invoking session instead of the target workflow's edit sessions (RS-027); reads only `.ts` (dropping `timestamp`-shaped entries) or only `.timestamp` (dropping hook `ts` entries) instead of `.ts // .timestamp` (RS-030); uses `jq -s` or slurps the whole log; fails on a malformed line; introduces a new helper script or Bash grant; or reads the wrong/one audit-trail file.
- **Test approach**: integration
- **Integration contract**:
  Entry: invoke the `/cwtf` presentation over a rule-load log fixture + a real audit-trail fixture (verbatim repo copy, AP-031) where the edit-session_id differs from the invoking session (RS-027)
  Through: real JSONL parse (try/catch, skip-malformed) of both sources; session_ids derived from the target workflow's hook-edit entries; per-branch audit-trail glob
  Exit: rule-loads grouped by the edit-session(s) (NOT the invoking session), raw evidence rendered with plain-language framing, a malformed line skipped (not fatal), and no MG-001/MG-002 token anywhere in the output

### INV-009: Presentation is dormant when the log is absent, and distinguishes empty from all-null
- **Type**: must
- **Category**: functional
- **Statement**: If `.correctless/meta/instructions-loaded.jsonl` is absent or empty, the `/cwtf` section emits a single advisory line that explains *why* and is not alarming ("no direct rule-load signal yet — the InstructionsLoaded log populates the first time a `.claude/rules/*.md`-scoped file is opened; requires harness ≥2.1.69") and continues (exit 0). If the log is present but **every** `rule_file` is null (INV-005), it additionally surfaces "N rule-load events, all with null rule_file — possible harness field drift; treat the rule-load evidence as unreliable" (RS-008/UX-001). If the correlated script/section prerequisites are missing it degrades (dormant), never errors.
- **Violated when**: absence of the log produces an error/non-zero exit; or a present-but-all-null log is presented as if healthy.
- **Enforcement**: CI test (no log → advisory line, exit 0; all-null log → field-drift note).
- **Guards against**: dormant-signal convention; DA-004 silent-telemetry class.
- **Test approach**: unit

### INV-010: Log is gitignored runtime telemetry
- **Type**: must
- **Category**: functional
- **Statement**: `.correctless/meta/instructions-loaded.jsonl` is matched by `.gitignore` and never tracked. (The audit-trail path is already gitignored; INV-015's field addition adds no new tracked-path exposure.)
- **Violated when**: `git check-ignore` does not match the path, or the file is committed.
- **Enforcement**: CI test (`git check-ignore` assertion for the instructions-loaded path).
- **Test approach**: unit

### INV-011: Append-only, O(1) writes (behavioral, bounded medium)
- **Type**: must
- **Category**: resource-lifecycle
- **Statement**: The hook only appends (`>>`) one line per event; it never reads the whole log into a variable or argv (no ARG_MAX exposure — AP-039), and never rewrites/truncates existing content.
- **Violated when**: the hook reads the full file, or rewrites the file in place.
- **Enforcement**: **Behavioral** CI test (RS-019) — pre-seed the log with N known lines, run the hook once, assert (a) file grew by exactly one line, (b) the first N lines are byte-identical, (c) the appended line is valid JSON. Grep for whole-file reads as a secondary tripwire.
- **Guards against**: AP-039 (unbounded data through bounded medium).
- **Test approach**: unit

### INV-012a: Real captured payload fixture — mechanical half (AP-031)
- **Type**: must
- **Category**: functional
- **Statement**: At least one hook test fixture is a real `InstructionsLoaded` payload captured from the live harness (≥2.1.69) per DD-004. The CI-enforceable assertions: the fixture passes `jq -e .`, contains **(at least)** the required documented keys (`file_path`, `trigger_file_path`, `load_reason`, `session_id`) — assert *presence*, not exact-key equality, since real harness payloads also carry common fields (`cwd`, `hook_event_name`, `transcript_path`) and may add future ones (RS-029) — and **round-trips** — piping it through `hooks/instructions-loaded.sh` yields exactly one line satisfying the full INV-003 schema (this is the high-value check: it verifies the hook handles the real shape, the actual AP-031 regression). Optionally SHA-256-pin the fixture in the DD-004 record.
- **Violated when**: the fixture lacks a documented key, or does not round-trip to a valid INV-003 entry.
- **Enforcement**: CI test (key presence + round-trip through the hook).
- **Test approach**: unit

### INV-012b: Real captured payload — provenance attestation (verification report, NOT CI)
- **Type**: must
- **Category**: process
- **Statement**: Genuine harness-origin of the INV-012a fixture (harness version ≥2.1.69, capture date, capture method per DD-004) is human-attested in `.correctless/verification/`. **CI cannot prove a fixture is harness-captured vs hand-authored** — only that it matches the schema and round-trips (INV-012a). The spec states this explicitly so no invariant over-claims CI enforcement (RS-014).
- **Violated when**: the verification report omits the provenance attestation.
- **Enforcement**: verification-report gate (reviewed at /cverify), not a CI assertion.
- **Test approach**: manual/attestation

### INV-013: Setup registration covers every seam [integration]
- **Type**: must
- **Category**: functional
- **Enforcement**: CI integration test running `register_hooks()` across each seam + `sync.sh --check` mirror parity.
- **Statement**: The `InstructionsLoaded` registration is emitted by **all** of `register_hooks()`'s code paths — fresh-install emission (`setup:568`), existing-settings detection/update (`setup:670-704`, which currently loops only `pre_hooks`/`post_hooks`), matcher-drift repair (`setup:617-638`), and invalid-settings regeneration (`setup:586-592`) — and the `correctless/setup` mirror stays byte-equal via `sync.sh`. Each seam is a **distinct** test assertion with its own fixture (RS-016).
- **Violated when**: any one path emits Pre/Post but omits InstructionsLoaded; drift repair or regeneration drops it; or the mirror diverges.
- **Test approach**: integration
- **Integration contract**:
  Entry: run `register_hooks()` against a temp project in four states — fresh; pre-existing settings.json without the entry; settings.json with a drifted InstructionsLoaded matcher; invalid settings.json
  Through: real fresh, existing-update, drift-repair, and regeneration paths each exercised; `sync.sh` mirror parity checked
  Exit: all four states yield an InstructionsLoaded entry; `correctless/setup` byte-equal to `setup`

### INV-014: Source ↔ distribution mirror parity
- **Type**: must
- **Category**: functional
- **Statement**: `hooks/instructions-loaded.sh` and the modified `hooks/audit-trail.sh` show **no `sync.sh --check` drift** against their `correctless/` mirrors (hooks are mirrored modulo the documented `# Rule:`-line strip at `sync.sh:58-66`; `setup` is mirrored verbatim). Reworded from "byte-equal" because a raw `cmp` would false-fail on any hook carrying a `# Rule:` line (RS-024c).
- **Violated when**: `sync.sh --check` reports drift for any of them.
- **Enforcement**: `sync.sh --check` in CI/pre-commit + structural test that uses the same strip transform (never a raw `cmp`).
- **Test approach**: unit

### INV-015: audit-trail session-identity field (display-alignment aid)
- **Type**: must
- **Category**: data-integrity
- **Statement**: `hooks/audit-trail.sh` extracts the harness `session_id` from stdin (the same documented field the InstructionsLoaded hook reads — same source, so the two logs display comparably; RS-004) and includes it in every entry alongside the existing `ts, phase, tool, file, branch`. This is a **display aid** for the INV-008 side-by-side presentation, **not** a machine-join key (PRH-005). Empty/null `session_id` is shown as such, never treated as a match. The addition is backward-compatible because it is *additive* and every consumer extracts specific fields via `jq` — including content-parsing consumers (`compute-session-cost.sh` reads `.phase`/`.timestamp`; `/cmetrics`, `/csummary`), not only filename-only ones (RS-028). The `/cwtf` presentation's parsing is tested against a **real audit-trail entry (verbatim repo copy), not hand-authored** (AP-031).
- **Violated when**: audit-trail omits `session_id`; derives it from a different source than the InstructionsLoaded hook (e.g. `lib.sh` PID-based `get_current_session_id`); an existing field is renamed/removed; or the presentation is tested only against a hand-authored audit-trail fixture.
- **Enforcement**: CI test (audit-trail entry contains `session_id` from the harness stdin field) + AP-031 real-fixture assertion.
- **Guards against**: AP-031; display misalignment.
- **Test approach**: unit

### INV-016: Liveness / self-diagnostic line
- **Type**: must
- **Category**: functional
- **Statement**: The `/cwtf` section always prints the denominators it worked from — e.g. "read K rule-load events (J with null rule_file) and M hook-edit entries across N edit-session(s) for the target workflow; log last written {ts}" — so a dead channel (M or K = 0 while work was done in `hooks/`) or a field-drifted channel (high null-ratio) is **visible** rather than silently producing an empty/negative picture (RS-008 / DA-004). Optionally a `/cstatus` indicator surfaces "InstructionsLoaded log last written {ts}".
- **Violated when**: the section presents rule-load evidence without surfacing the counts/liveness, so an empty or all-null channel is indistinguishable from a healthy-but-quiet one.
- **Enforcement**: CI test asserting the denominator/liveness line is present for empty, all-null, and populated logs.
- **Guards against**: DA-004 silent-telemetry-failure (the class demonstrated live by the codex external-review silent-skip).
- **Test approach**: unit

## Prohibitions

### PRH-001: Hook must not block or exit non-zero
- **Statement**: The hook must never block, prompt, or exit non-zero. Exit codes are ignored by the harness for InstructionsLoaded (EA-003), so any non-zero exit is dead behavior.
- **Detection**: CI test asserts exit 0 across empty/malformed/valid/missing-field/unwritable-dir inputs.
- **Consequence**: dead code masquerading as control flow.

### PRH-002: Do not add the log to sensitive-file-guard DEFAULTS
- **Statement**: `.correctless/meta/instructions-loaded.jsonl` must NOT be added to `sensitive-file-guard.sh` DEFAULTS.
- **Detection**: grep SFG DEFAULTS for the path (must be absent).
- **Consequence**: AP-037 edit-friction against an AP-040 non-threat.

### PRH-003: Do not re-open or rewrite the accepted measurement
- **Statement**: This feature must not modify `.correctless/verification/path-scoped-rules-pat001-measurement.md` nor change `.correctless/meta/pat001-measurement-due.json`'s recorded result; the gate stays accepted.
- **Detection**: both files unchanged in the diff; `/cstatus` measurement-overdue check stays suppressed.
- **Consequence**: re-litigating a closed, correctly-decided experiment.

### PRH-004: No gate/phase-transition may depend on the log
- **Statement**: No `cmd_*` phase-transition gate, and no phase transition, may require or read the jsonl log. Advisory only.
- **Detection**: grep `hooks/workflow-advance.sh`, `hooks/*.sh`, and `scripts/wf/*.sh` for the log path (must be absent — RS-testability broadened the scope beyond workflow-advance.sh).
- **Consequence**: a forward-looking advisory signal becoming a hard dependency.

### PRH-005: No automated MG-001/MG-002 classification
- **Statement**: The `/cwtf` section must present rule-load and hook-edit evidence for **human** classification and must NOT compute or emit an automated MG-001 vs MG-002 verdict, nor any cross-file `session_id`+`ts`-ordering machine join. (Encodes the round-3 scope-down — DD-007 — so a future implementer does not silently re-add the fragile classifier the review rejected.)
- **Detection**: grep the `/cwtf` section + any new code for "MG-001"/"MG-002" verdict emission and for a `ts <= edit.ts` correlation join (must be absent).
- **Consequence**: reintroduces the ~8 CRITICAL/HIGH cross-file-join failure modes (RS-004/005/006/007/009/010/011) and the optimistic-bias silent-telemetry class.

## Boundary Conditions

### BND-001: Harness payload → hook stdin (TB-010)
- **Boundary**: Claude Code harness → `instructions-loaded.sh` stdin (**TB-010**, added by this spec — semi-trusted structured input; `file_path`/`trigger_file_path` may reflect repo contents)
- **Validation required**: parse via `jq`; construct the log line with `jq -n` (INV-004); canonicalize + prefix-check paths (INV-002); treat paths as data (never eval/unquoted); tolerate absent `file_path` (INV-005); `set -f` + `LC_ALL=C`
- **Failure mode**: fail-open — best-effort log, always exit 0

### BND-002: Log growth + bounded consumer
- **Boundary**: append-only file; `/cwtf` bounded reader
- **Validation required**: hook does O(1) append only (INV-011); `/cwtf` reads streaming/bounded (never slurp whole file — INV-008), tolerant of a large log; trimming delegated to `/cprune` (DD-005)
- **Failure mode**: accepted linear growth (gitignored, local)

## STRIDE Analysis

### STRIDE for harness→hook stdin boundary (BND-001 / TB-010)
- **Spoofing**: N/A — no identity assertion; hook only records.
- **Tampering**: crafted `file_path`/`trigger_file_path` with shell metacharacters → neutralized by safe extraction + `jq -n` serialization (INV-004); logged literally, never executed, and cannot inject a second record.
- **Repudiation**: entries carry `ts` + `session_id` for after-the-fact human review.
- **Information disclosure**: log holds `cwd`/`session_id`/rule paths only — local + gitignored (INV-010); `transcript_path` deliberately dropped (RS-024b); no secrets extracted.
- **Denial of service**: oversized payload handled by `jq`; hook is exit-ignored + O(1)-append; `/cwtf` reads bounded (INV-008).
- **Elevation of privilege**: none — hook performs no privileged action and cannot block (EA-003). **Log-record forgery is possible** (the log is agent-writable via Bash redirect and deliberately not SFG-protected — PRH-002); because there is **no automated verdict** (PRH-005), a forged line only misleads a human reading raw evidence with the liveness counts in view — accepted residual for an advisory dogfood signal (consistent with PMB-020: this is a guardrail, not a security boundary). No new Bash grant is added to `/cwtf` (DD-008), so the earlier round-2 `Bash(...*)` compound-command concern (RS-021) does not arise.

## Environment Assumptions
- **EA-001**: The `InstructionsLoaded` hook event exists and fires in Claude Code ≥2.1.69 (verified 2026-07-01 on 2.1.185). — refs new **ENV-012**. **If wrong**: hook never fires, log stays empty, presentation dormant (INV-009) — degrades gracefully.
- **EA-002**: The payload names the loaded file in the documented `file_path` field, carries `session_id`, and `path_glob_match` events carry `trigger_file_path`. **Firing model (RS-006):** opening a `.claude/rules/`-scoped file mid-session emits a fresh `path_glob_match` load naming that file — this is the property that makes per-edit observation meaningful. Confirmed empirically by the INV-012a live capture, which **must confirm the firing model, not merely the field names** (DD-004). The `load_reason` literal is treated as an uncontracted harness default (may be renamed on upgrade → INV-016 liveness surfaces the resulting all-null/empty state). **If the firing model is session-batched instead of per-open**: the log still shows the rule was in context for the session, but cannot tie a load to a specific later edit; the human interprets accordingly (advisory, non-breaking).
- **EA-003**: For `InstructionsLoaded`, the harness ignores the hook's exit code (documented). — **If wrong**: only makes fail-open stricter.
- **EA-004**: The settings.json hook timeout field/units honored by the harness. Default emission matches the existing convention (`timeout_ms`, `setup:532`); docs describe timeout in seconds. **Disposition (required)**: verify the emitted field against a live registration during TDD (INV-006). If the harness does not honor `timeout_ms` for InstructionsLoaded, switch to the docs-compliant `timeout` (seconds) — accepting a per-type field difference — rather than shipping an ignored timeout. **Note a latent unknown:** `timeout_ms` may already be silently ignored for existing Pre/Post hooks; record the finding. Outcome recorded in the verification report.
- **EA-005**: The harness emits the same `session_id` value/format across `InstructionsLoaded` and `PostToolUse` events within a session. This is now a **display-alignment** aid, not a load-bearing machine join (DD-007) — **if false**, the side-by-side `/cwtf` view may not line up by session, but both session_ids are shown for the human to judge (advisory, non-breaking).
- **EA-006**: The log lives on a local filesystem where `>>` append of a ~150-byte line is atomic (POSIX O_APPEND ≤ PIPE_BUF). On NFS/large lines a torn line is possible — mitigated by the INV-008 skip-malformed consumer contract (RS-013).

## Design Decisions (confirmed with maintainer 2026-07-01)
- **DD-001 (registration)** — amend `register_hooks()`/ABS-004 for `HOOK_TYPE: InstructionsLoaded` via a generalized (glob-driven) type→timeout mechanism (not a hardcoded arm). Rationale: glob-not-enumerate convention (AP-024/PMB-003). **Confirmed.**
- **DD-002 (log location)** — local, gitignored `.correctless/meta/instructions-loaded.jsonl`. **Confirmed.**
- **DD-003 (log scope)** — log all `.claude/rules/*.md` loads (future-proofs FUTURE-002); `/cwtf` presents the relevant file. **Confirmed.**
- **DD-004 (real-payload capture)** — capture the INV-012a fixture during TDD by temporarily registering a stdin-dump command hook on the live 2.1.185 harness, opening/editing a `.claude/rules/`-scoped hook file to trigger a `path_glob_match` load, and saving the emitted JSON. **Must confirm the firing model (per-open vs session-batched) and the field names** (EA-002). **Confirmed.**
- **DD-005 (log cap)** — accept unbounded linear growth at the hook (O(1) append, gitignored, local); trimming delegated to `/cprune`. **Confirmed.**
- **DD-006 (audit-trail as display source)** — use `audit-trail`'s session-tagged JSONL (INV-015) as the hook-edit source for the `/cwtf` **side-by-side display** (git has no session identity), **not** as a machine-join substrate. **Reframed in round 3.**
- **DD-007 (observability, not classifier)** — the feature presents raw rule-load + hook-edit evidence for **human** classification; it does NOT compute an automated MG-001/MG-002 verdict (PRH-005). Rationale: the automated cross-file join concentrated ~8 CRITICAL/HIGH review findings, all biasing optimistic, for an advisory signal on an already-accepted gate; the value did not justify the surface (the DA-004 class was demonstrated live by the codex external-review silent-skip). Matches `/cwtf`'s "context not judgment" ethos. **Confirmed round 3 (RS-025).**
- **DD-008 (no new helper / no new Bash grant)** — `/cwtf` reads and presents the two logs via its existing `Bash(jq*)`/`Bash(grep*)`/`Bash(find*)` tools; no correlate helper script and no `Bash(...correlate.sh*)` grant are added. Rationale: without an automated join there is nothing for a helper to compute; this dissolves the round-2 read-only-posture / compound-command concern (RS-021). **Confirmed round 3.**

## Open Questions
- None blocking. Round-1/2/3 review items are resolved into DD-001..DD-008, INV-001..INV-016, PRH-005, TB-010, ENV-012, EA-005/006. Two items are verified during TDD rather than at spec time (both captured as EAs): the real `file_path`/`trigger_file_path` shape **and the firing model** (EA-002 / INV-012a capture / DD-004), and the timeout field/units the harness honors (EA-004 / INV-006, with a mandatory disposition).

## Review History
- **Round 1 (external, 2026-07-01)** — 7 findings folded in (OQ→DD promotion; setup seam; helper; INV-002/005 reconcile; EA-004 timeout; test grammar; ENV/doc counts).
- **Round 2 (external, 2026-07-01)** — 5 findings folded in (session-tagged producer; correlation ordering/context; allowed-tools scope; documented schema; timeout disposition).
- **Round 3 (multi-agent /creview-spec, 2026-07-01)** — 6 adversarial agents + self-assessment, 25 findings. Codex cross-model review **skipped** (validator bug — bare `bin:"codex"` resolved cwd-relative, plus npm-global `codex.js`/node_modules rejection; commented on GitHub #199). Key outcomes:
  - **RS-025 (premise, maintainer decision)** → scope down from an automated MG-001/MG-002 classifier to a human-judged observability log (DD-007/PRH-005). Dissolved RS-005 (ts-ordering), RS-007 (optimistic bias), RS-009 (upgrade misclassification).
  - **Log-shape (maintainer decision)** → keep audit-trail `session_id` (INV-015) + `/cwtf` shows edits alongside as a **display aid**; RS-004/010/022 retained as low-severity display-accuracy concerns (same-source session_id, per-branch globbing, off-workflow caveat).
  - **Mechanical BLOCKERS folded**: RS-001 ENV-007→**ENV-012**; RS-002 **ABS-004 amended** (explicit new invariant wording); RS-003 **register_hooks refactor** + honest Complexity Budget; RS-017 **test grammar** (all pinned sites, underscore/`*` matcher, `auto_hooks` array).
  - **Hook hardening folded**: RS-012 JSONL consumer contract (INV-008); RS-013 append-atomicity (EA-006); RS-014 INV-012 split (INV-012a/b); RS-019 behavioral append test (INV-011); RS-020 `jq -n` serialization (INV-004); RS-024a `set -f`; RS-024b drop `transcript_path`; RS-024c INV-014 wording; RS-024d meta-dir creation; RS-024i ts-format assertion (INV-003).
  - **Registration/testability folded**: RS-015 timeout split (INV-006/EA-004); RS-016 all seams (INV-013); RS-018 Enforcement fields added to INV-006/008/013.
  - **Silent-failure folded**: RS-008 liveness signal (**INV-016**) + present-but-all-null branch (INV-009).
  - **Structure folded**: RS-024e new ABS for audit-trail JSONL; RS-024f **TB-010** for harness→hook stdin; RS-024g ENV-005 reconcile; RS-011 canonicalize_path resolution (INV-002).
  - **Dissolved by scope-down**: RS-021 (no new Bash grant — DD-008), INV-008-as-correlator and the correlate helper script (replaced by the presentation invariant), DD-006 reframed.
  - Full findings + dispositions: `.correctless/artifacts/review-spec-findings-instructionsloaded-hook.md`.
- **Round 4 (external, 2026-07-01)** — 4 findings on the reshaped spec, all verified against the tree and folded in:
  - **RS-026 (HIGH)** → pin `HOOK_MATCHER: *` (INV-007 + INV-006 exit): InstructionsLoaded matchers filter by load *reason*, so DD-003's "log all rule loads" requires `*`, not a reason-specific matcher; the registered matcher is asserted.
  - **RS-027 (HIGH)** → `/cwtf` session selection (INV-008): `/cwtf` analyzes the most recent *or a past* workflow (`skills/cwtf/SKILL.md:15`), so rule-loads must be grouped by the **target workflow's edit-session_ids**, never filtered by the invoking session.
  - **RS-028 (MEDIUM)** → audit-trail consumer claim corrected (Scope + INV-015): `compute-session-cost.sh:185-199` (and `/cmetrics`, `/csummary`) parse audit-trail *content*; the field addition is "additive-safe," not "no consumer parses content." New ABS must list real producers/consumers.
  - **RS-029 (LOW)** → INV-012a asserts required-key *presence* + round-trip, not exact top-level-key equality (real payloads carry `cwd`/`hook_event_name`/etc.).
- **Round 5 (external, 2026-07-01)** — 2 findings on the reshaped spec, both verified and folded in:
  - **RS-030 (MEDIUM)** → mixed audit-trail timestamp shapes (INV-008 + new ABS): the hook writes `ts` (`hooks/audit-trail.sh:104`), `/cauto` writes `timestamp` (`skills/cauto/SKILL.md:534`) to the same file; `/cwtf` must read `.ts // .timestamp` and the test must cover both record shapes.
  - **RS-031 (LOW)** → `canonicalize_path`/`lib.sh` unavailable (INV-001 + INV-002): fail-open hook must exit 0 with no log (no un-canonicalized fallback, which would reintroduce the INV-002 traversal risk); added to the fail-open test matrix.
