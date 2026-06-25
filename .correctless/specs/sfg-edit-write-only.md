# Spec: Reduce sensitive-file-guard to Edit/Write-tool-path only (remove the Bash extraction path)

## Metadata
- **Created**: 2026-06-25T16:20:38Z
- **Status**: draft
- **Impacts**: ABS-045 (narrows further), ABS-029/030/035/038/040/041/042 (Class-A — surviving `cmd_*` leg), **ABS-027 (Class-B — SFG's Bash-block WAS its structural leg; amended to Edit/Write-only, INV-009)**, semi-auto-mode R-019 (Class-B — `preferences.md`), the 2026-04-26 + 2026-04-30 CLAUDE.md conventions (amended), AGENT_CONTEXT.md Hooks row, README, CHANGELOG, `.claude/rules/hooks-pretooluse.md` (extraction-path carve-out removed; DEFAULTS-only-on-config-failure narrow exception documented — F4), `docs/skills/cmodelupgrade.md`, `docs/features/harness-fingerprint.md`. Tests impacted (Test Corpus Migration): `test-sfg-rescope.sh` (delete), `test-sensitive-file-guard.sh`, `test-harness-fingerprint.sh`, `test-semi-auto-mode.sh`, `test-hook-sync.sh`, `test-architecture-drift.sh` (verify).
- **Branch**: feature/sfg-edit-write-only
- **Research**: null
- **Recommended-intensity**: high
- **Intensity**: high
- **Intensity reason**: file-path signal (`hooks/sensitive-file-guard.sh`) + security category (removes a protection leg from sole-writer contracts)
- **Override**: none

## Context

The 2026-06 SFG re-scope (#205) right-sized `hooks/sensitive-file-guard.sh` from a perimeter to a write-target-only guardrail, but kept a large, fragile **Bash write-target extraction path** (`_extract_bash_targets` + ~8 masking/parsing helpers + an O(n^2)-bounding length cap). That path was the source of ~90% of the re-scope's complexity and ~10 of its defects (quote/comment/backslash masking, three O(n^2) iterations, operator-enumeration drift). Per PMB-020/AP-040, SFG is a guardrail/speedbump, and the Bash-redirect leg of that guardrail has **low expected value**: an agent that *accidentally* writes a protected file via `> .env` (rather than via the Edit/Write tool) is rare, and the form is trivially evaded (interpreter, directory naming). The cost — code complexity, maintenance, and false-positive friction on reads/invocations — outweighs that value.

This feature deletes the entire Bash extraction path and reduces SFG to a **pure Edit/Write tool-path guard**: it matches `tool_input.file_path` for `Edit`/`Write`/`MultiEdit`/`NotebookEdit`/`CreateFile` against the protected-pattern list, and does nothing for `Bash`. This keeps the one cheap, genuinely-useful protection (catching the agent directly Write-ing `.env`/`*.pem`/a state file) and removes the rest. Net: ~600-line hook to ~30-40-line hook, near-zero friction.

## Scope

**In scope — `hooks/sensitive-file-guard.sh` (+ mirror via `sync.sh`):**
- Fast-path `exit 0` for `Bash` in STEP 3 (before loading lib.sh/config) — the hook no longer inspects Bash commands at all.
- DELETE `_extract_bash_targets` and every helper it uses that is now dead: `_strip_quotes`, `_excise_process_subs`, `_mask_quoted_operators`, `_mask_opaque_operands`, `_segment_command`, `_extract_writer_dests`, `_extract_inplace_operand`, `_redirect_op_suffix`, `_emit_dest`, and the `_SFG_LENGTH_CAP` block.
- Remove the `Bash) _extract_bash_targets` arm from `collect_targets` (only the Edit/Write tool arms remain).
- The hook no longer calls `_has_write_pattern`. (`_source_lib_sh` is still needed for `canonicalize_path` + `config_file` on the Edit/Write path; keep it and the canonicalize_path v1 sentinel probe.)
- Update the BLOCKED message to drop any Bash-write framing (it now only ever fires on an Edit/Write tool target).

**In scope — documentation coherence sweep:**
- `.correctless/ARCHITECTURE.md`: narrow ABS-045 to "Edit/Write/MultiEdit/NotebookEdit/CreateFile tool-path only; Bash-mediated writes (redirects, writer commands, interpreters, git) are ALL accepted non-goals." Update the SFG clause in ABS-029/030/035/038/040/041/042 (Class-A — surviving `cmd_*` leg). **Amend ABS-027 (Class-B): drop "blocks Edit/Write AND Bash redirects via `_has_write_pattern`" → "structural on the Edit/Write tool-path; Bash-mediated writes are accepted non-goals (advisory fingerprint, residual accepted)" (INV-009).**
- `docs/skills/cmodelupgrade.md` (~L80) and `docs/features/harness-fingerprint.md` (~L82): sweep the SFG-Bash-protection claims to the Edit/Write-tool-path framing (F3).
- `CLAUDE.md`: amend the 2026-04-26 "structurally-enforced sole-writer" convention (it currently requires the hook to block BOTH Edit/Write AND Bash redirects via `_has_write_pattern`) — the Bash-redirect requirement is removed; the structural leg is the content-based `cmd_*` gate. Amend the 2026-04-30 convention similarly.
- `.correctless/AGENT_CONTEXT.md`: rewrite the Hooks-row SFG description (Edit/Write tool-path guard only).
- `README.md` / `CHANGELOG.md`: announce the further reduction.
- `.claude/rules/hooks-pretooluse.md`: the clause-5 *extraction-path* carve-out (added by #205) is removed along with the extraction path — SFG once again has no fail-open path (the Edit/Write path is straightforwardly fail-closed-on-parse-failure). Update PAT-001's carve-out section.

**Out of scope (explicit non-goals):**
- `scripts/lib.sh` `_has_write_pattern` and `get_target_file` are **NOT removed** — `hooks/workflow-gate.sh` consumes `_has_write_pattern` independently. SFG simply stops calling it. lib.sh is unchanged.
- The `DEFAULTS` protected-pattern list and `custom_patterns` config are unchanged — *which* files are protected is unaffected; only the Bash-command detection is removed.
- `workflow-gate.sh` behavior is unaffected.
- `redact-secrets.sh` is unaffected.

## Complexity Budget
- **Estimated LOC**: **minus ~550 net** (delete the extraction path + helpers; the hook drops from ~600 to ~30-40 lines).
- **Files touched**: `hooks/sensitive-file-guard.sh` (+ mirror), `tests/test-sensitive-file-guard.sh` (remove Bash corpus), DELETE `tests/test-sfg-rescope.sh`, `.correctless/ARCHITECTURE.md`, `CLAUDE.md`, `.correctless/AGENT_CONTEXT.md`, `README.md`, `CHANGELOG.md`, `.claude/rules/hooks-pretooluse.md`.
- **New abstractions**: 0 (this is a deletion).
- **Risk surface delta**: this is a **strict reduction in what SFG blocks** — every Bash command that the re-scoped hook would have blocked now passes. The only regression risk is in the OTHER direction: (a) accidentally breaking the surviving Edit/Write tool-path match (caught by the unchanged Edit/Write corpus, INV-002), or (b) a sole-writer contract that *actually depended* on SFG's Bash-redirect leg as its only protection (the security residual below — the review focus).

## Invariants

> **Test approach**: hook-integration — drive the full hook via a stdin JSON envelope through `run_hook_capture`, assert the exit code (0 = allow, 2 = block).

### INV-001: Bash commands are never inspected and never blocked
- **Type**: must
- **Category**: functional
- **Statement**: For `tool_name == "Bash"`, the hook MUST `exit 0` immediately (fast-path in STEP 3, before sourcing lib.sh or reading config), regardless of the command content. No Bash command can ever be blocked by SFG. `_has_write_pattern` is not called on the Bash path.
- **Violated when**: any `{"tool_name":"Bash",...}` envelope produces exit 2 (e.g. `echo x > .env`, `tee .env`, `cp x .env` — all now ALLOWED).
- **Enforcement**: CI test assertion (a corpus of former-must-block Bash commands now all exit 0) + structural test that the hook contains no `_extract_bash_targets` / masking helpers.

### INV-002: Edit/Write/MultiEdit/NotebookEdit/CreateFile tool-path blocking is UNCHANGED
- **Type**: must
- **Category**: functional / security
- **Statement**: For `Edit`, `Write`, `MultiEdit`, `NotebookEdit`, `CreateFile`, the `tool_input.file_path` (and MultiEdit `edits[].file_path`) MUST still be matched against the canonicalized `DEFAULTS`/`custom_patterns` patterns exactly as today, and a match MUST exit 2. This is the retained value of the hook.
- **Violated when**: an `Edit`/`Write` to a protected path (`.env`, `*.pem`, a `.correctless/` state file) is allowed.
- **Enforcement**: the ENTIRE existing Edit/Write corpus in `tests/test-sensitive-file-guard.sh` MUST pass unchanged (this is the MUST-PASS-UNCHANGED set).

### INV-003: Canonical-form matching is preserved on the Edit/Write path
- **Type**: must
- **Category**: security
- **Statement**: Every Edit/Write `file_path` MUST still pass through `canonicalize_path` (PAT-017) before matching, and matching compares canonical target against canonical patterns. Traversal-encoded targets (`subdir/../.env`) still block.
- **Enforcement**: existing canonical-matching tests stay green.

### INV-004: lib.sh and workflow-gate are unaffected
- **Type**: must-not
- **Category**: functional
- **Statement**: This feature MUST NOT modify `scripts/lib.sh` (`_has_write_pattern`/`get_target_file`/`canonicalize_path` unchanged) and MUST NOT change `hooks/workflow-gate.sh`. `workflow-gate.sh`'s use of `_has_write_pattern` is independent and continues.
- **Enforcement**: golden-hash on `_has_write_pattern`/`get_target_file` bodies stays green + `tests/test-workflow-gate.sh` passes unchanged.

### INV-005: The Bash extraction code is fully removed (no dead code)
- **Type**: must-not
- **Category**: maintainability / AP-022
- **Statement**: `_extract_bash_targets`, `_strip_quotes`, `_excise_process_subs`, `_mask_quoted_operators`, `_mask_opaque_operands`, `_segment_command`, `_extract_writer_dests`, `_extract_inplace_operand`, `_redirect_op_suffix`, `_emit_dest`, and the `_SFG_LENGTH_CAP` block MUST NOT exist in the hook after this feature. Extraction is not "disabled-but-present" — it is deleted.
- **Enforcement**: structural test greps the hook and asserts none of these symbols are defined.

### INV-006: Input-parse failure still fails closed
- **Type**: must
- **Category**: security
- **Statement**: A malformed/unparseable stdin JSON envelope MUST still exit 2 (fail-closed), for all tools including Bash (the fast-path exit-0 for Bash applies only AFTER a successful parse establishes `tool_name == Bash`). Note: with extraction gone, the input-parse path is the ONLY fail-closed path remaining, and PAT-001 clause 5 applies to it cleanly (no carve-out needed).
- **Enforcement**: malformed-JSON test stays green; PAT-001 clause-5 carve-out for the extraction path is REMOVED from the rule file (INV-008/doc).

### INV-007: Documentation describes an Edit/Write-tool-path guard (doc coherence)
- **Type**: must
- **Category**: documentation
- **Statement**: After this feature, no **current-state** doc may claim SFG inspects or blocks Bash commands, redirects, or writer commands. The grep corpus is `.correctless/ARCHITECTURE.md`, `CLAUDE.md`, `.correctless/AGENT_CONTEXT.md`, `README.md`, and **all of `docs/skills/*` and `docs/features/*`** — explicitly including `docs/skills/cmodelupgrade.md` and `docs/features/harness-fingerprint.md` (both still claim SFG Bash protection — F3). ABS-045 is narrowed to the Edit/Write tool-path; the consuming ABS entries (029/030/035/038/040/041/042) drop the "direct redirect/writer-command destinations" clause; **ABS-027 drops "blocks ... Bash redirects via `_has_write_pattern`" and states structural enforcement is Edit/Write-tool-path only (INV-009)**. The 2026-04-26 and 2026-04-30 CLAUDE.md conventions are amended.
- **Exclusion**: the append-only historical journals (`docs/dev-journal.md`, `docs/workflow-history.md`) are EXCLUDED from the grep — they record past states (including the #205 entries describing the then-current Bash extraction) and are not current claims, exactly as the CLAUDE.md PMB-ledger is excluded by #205's INV-012. The grep must scope them out.
- **Enforcement**: CI grep test over the corpus above (journals excluded) for stale "SFG blocks Bash/redirect/writer" claims.

### INV-008: PAT-001 extraction-path carve-out removed; remaining non-strict path documented narrowly (F4)
- **Type**: must
- **Category**: security / documentation
- **Statement**: `.claude/rules/hooks-pretooluse.md`'s clause-5 carve-out (added by #205 for the *extraction* path's fail-open) MUST be removed — the extraction path is deleted, so that carve-out no longer describes anything. The rule file MUST NOT claim SFG has "no fail-open path", because a pre-existing narrower behavior remains on the Edit/Write path: `custom_patterns` are read with `… 2>/dev/null || CUSTOM_PATTERNS=""` (hook ~L917), so a present-but-unparsable `workflow-config.json` silently degrades to **DEFAULTS-only** matching (built-in protected patterns still enforced; user-added `custom_patterns` lapse). This is unchanged by this feature. Disposition (chosen): **document it as a narrow, named exception** in the rule file — "SFG degrades to DEFAULTS-only (never fully open) when `custom_patterns` config is unparsable; DEFAULTS remain enforced" — rather than hardening it to a hard exit-2 (hardening would block *all* edits on a corrupt config, a usability regression; see OQ-003).
- **Enforcement**: CI test asserts (a) the extraction-path carve-out subsection is gone, and (b) the rule file documents the DEFAULTS-only-on-config-failure narrow exception (so the claim is honest).

### INV-009: ABS-027 / semi-auto R-019 contracts amended to Edit/Write-tool-path-only enforcement
- **Type**: must
- **Category**: security / documentation (Class-B residual, see Security Residual)
- **Statement**: `.correctless/ARCHITECTURE.md` ABS-027's Invariant MUST be amended to drop "sensitive-file-guard blocks Edit/Write AND Bash redirects via `_has_write_pattern`" and instead state: "Sole-writer enforcement is structural on the **Edit/Write tool-path** (sensitive-file-guard); Bash-mediated writes are accepted non-goals (AP-040) — the fingerprint is advisory (PRH-001), so the residual is accepted." The semi-auto-mode R-019 contract (and any other ABS/convention asserting an SFG Bash-redirect leg for a protected file) MUST be amended the same way. No protected file may retain a documented claim of Bash-redirect structural protection after this feature.
- **Violated when**: any ABS/convention/test still asserts SFG blocks a Bash redirect/writer to a protected path.
- **Enforcement**: CI grep (shared with INV-007) + the inverted test assertions (Test Corpus Migration).

## Prohibitions

### PRH-001: Never re-introduce Bash-command inspection
- The hook MUST NOT parse, tokenize, or extract write targets from `tool_input.command`. The fast-path for Bash is unconditional exit 0.

### PRH-002: Never allow a previously-blocked Edit/Write target
- The reduction MUST NOT make any Edit/Write/MultiEdit target previously blocked now pass. The entire existing Edit/Write corpus is the MUST-PASS-UNCHANGED set.

### PRH-003: Never modify lib.sh `_has_write_pattern` / `get_target_file`
- They survive for `workflow-gate.sh` (INV-004, golden-hash pinned).

## Security Residual Analysis (the review focus — CORRECTED after review round 1)

Removing SFG's Bash-redirect leg means a direct `echo x > <protected>` / `tee <protected>` / `cp x <protected>` Bash command is **no longer blocked**. **Review round 1 falsified the original "redundant secondary leg" claim** — for at least three contracts SFG's Bash-block was a *real* structural leg with NO content-hash/`cmd_*` replacement. The contracts split into two classes:

**Class A — surviving structural leg (downgrade is genuinely a no-op for integrity):**
- **Script-written, phase-transition-gated state** (`workflow-state-*`, `autonomous-decisions-*`, audit-record outputs, intensity-calibration): these sole-writers write via a script's internal `printf >> "$dst"` (never an agent-side redirect), and their structural integrity leg is the content-equality `cmd_*` phase-transition gate (2026-04-30 convention). SFG's Bash-block was genuinely redundant here. **Accepted — no integrity change.**

**Class B — SFG's Bash-block WAS the structural leg (real downgrade, explicitly accepted):**
- **`harness-fingerprint.json` / `model-baselines.json` (ABS-027)**: `.correctless/ARCHITECTURE.md` ABS-027 states verbatim — "Sole-writer enforcement is structural (sensitive-file-guard blocks Edit/Write AND Bash redirects via `_has_write_pattern`), not advisory." There is **no content-hash/`cmd_*` gate** behind these files; SFG's Bash-block *was* the structural enforcement against out-of-band writes. `tests/test-harness-fingerprint.sh` (PRH-002e) asserts the live Bash-redirect block.
- **`preferences.md` (semi-auto-mode R-019)**: `tests/test-semi-auto-mode.sh` asserts SFG blocks both `Edit` AND `Bash` writes to `.correctless/preferences.md`. No other structural leg.

**Disposition for Class B: accept the residual downgrade (NO replacement gate).** After this feature, structural enforcement for these files narrows to the **Edit/Write tool-path only**; a Bash-mediated write to them becomes an accepted non-goal (like every other Bash write). Justification: (1) the harness fingerprint is **advisory** — ABS-027/PRH-001 say it "never blocks any skill," so forging it only suppresses a `/cmodelupgrade` nudge; model-baselines is a measurement file; `preferences.md` is owner-scaffolded (TB-001a) and the Edit/Write leg survives. (2) The Bash-redirect leg was always trivially evadable (interpreter/directory — PMB-020), so its structural value was a speedbump, not a boundary. (3) A replacement `cmd_*` gate is disproportionate — these are not phase-transition artifacts and have no natural transition to gate at. **The contracts are amended (INV-009) to state structural enforcement is Edit/Write-tool-path only.** This is a deliberate, documented security downgrade — surfaced prominently so it can be rejected in favor of keeping protection (which would mean retaining some Bash parsing, contradicting the simplification's premise).

**The convention text**: the 2026-04-26 convention's literal requirement ("verify the hook blocks BOTH Edit/Write AND Bash redirects") and ABS-027's "blocks ... Bash redirects" become false and MUST be amended, or they mislead the next sole-writer feature into assuming a Bash-redirect guard that no longer exists (AP-026/AP-036 advisory-prose-drift hazard).

**OQ-001 — RESOLVED**: the contracts whose ONLY structural leg was SFG's Bash-block are `harness-fingerprint.json`, `model-baselines.json` (ABS-027), and `preferences.md` (semi-auto R-019). Resolution = accept the residual (Class B above) + amend the contracts/tests/docs (INV-009, expanded test migration). No replacement gate is added.

## STRIDE (TB-001: agent-proposed action -> file write)
- **Tampering (write to a protected file)**: mitigated ONLY on the Edit/Write tool path now. Bash-mediated writes (redirect, writer command, interpreter, git) are ALL accepted non-goals. This is a deliberate, documented reduction — the guardrail catches the naive Edit/Write tool call, nothing else. A cooperative-loop PreToolUse hook cannot stop a motivated agent or injection regardless (PMB-020); the Edit/Write guard remains as cheap insurance against the agent's own careless tool call.
- **Denial of service**: the prior over-extraction/O(n^2) self-DoS is fully eliminated (no Bash inspection at all).
- Spoofing / Repudiation / Information-disclosure / EoP: unchanged / out of scope (redact-secrets owns egress).

## Test Corpus Migration (expanded after review — F2)

A repo-wide grep (`tool_name":"Bash"` near a protected path, plus `_has_write_pattern` callers) identified every test asserting the old SFG Bash contract. Explicit disposition per file:

- **DELETE** `tests/test-sfg-rescope.sh` — tests the removed Bash extraction path in its entirety (INV-001..020 of #205 are all Bash-extraction invariants). Nothing survives.
- **`tests/test-sensitive-file-guard.sh`**:
  - **MUST-PASS-UNCHANGED**: the entire Edit/Write/MultiEdit corpus, the malformed-JSON fail-closed test, the canonical-matching tests.
  - **MUST-INVERT**: every Bash assertion expecting exit 2 (the migrated `> .env`/`tee`/`cp`/`sed -i`/etc. must-block corpus) flips to exit 0.
  - **ADD**: a structural test (INV-005) that the hook defines none of the deleted extraction helpers; a representative "Bash is never blocked" corpus (INV-001).
- **`tests/test-harness-fingerprint.sh`** (F2): **MUST-INVERT** the `PRH-002e` live-Bash-redirect assertions for `harness-fingerprint.json` and `model-baselines.json` (exit 2 → exit 0). KEEP the Edit/Write block assertions for those files (INV-002 path survives). Update the PRH-002e label/comment to reflect Edit/Write-tool-path-only enforcement (ties to INV-009).
- **`tests/test-semi-auto-mode.sh`** (F2): **MUST-INVERT** the `R-019` "Bash redirect to `.correctless/preferences.md` is blocked" assertion (exit 2 → exit 0). KEEP the R-019 Edit-block and the `docs/preferences.md`-not-blocked negative test.
- **`tests/test-hook-sync.sh`** (F2): **MUST-UPDATE** the assertion that `sensitive-file-guard.sh` calls `_has_write_pattern` — after this feature SFG no longer calls it (only `workflow-gate.sh` does). The shared-function test must assert `_has_write_pattern` is called by `workflow-gate.sh` and is NO LONGER required in `sensitive-file-guard.sh` (and the hook-sync/ABS-001 drift checks must not flag SFG for not calling it).
- **`tests/test-architecture-drift.sh`** (verify): if it asserts ABS-027's "blocks Edit/Write AND Bash redirects" text verbatim, update to match the INV-009 amendment. (Disposition confirmed during RED by reading the actual assertion.)
- **`tests/test-cprune.sh`** (verify): grep match is likely an SFG-protected-path-list reference unrelated to Bash behavior — confirm during RED; update only if it asserts SFG Bash blocking.
- **OUT OF SCOPE (unchanged)**: `tests/test-workflow-gate.sh`, `tests/test-gate-path-exceptions.sh` — these test `workflow-gate.sh`'s independent `_has_write_pattern` use, which this feature does not touch. They MUST stay green unchanged (INV-004).

## Environment Assumptions
- **EA-001**: `canonicalize_path` (PAT-017) and `config_file` remain the only lib.sh functions SFG depends on (both on the Edit/Write path). The canonicalize_path v1 sentinel probe is retained.
- **EA-002**: bash >= 4.0 floor unchanged (the surviving code uses `${var,,}` lowercasing + `[[ =~ ]]`).

## Design Decisions
- **DD-1**: Fast-path `exit 0` for Bash inside the hook (STEP 3), rather than removing `Bash` from the hook matcher in settings — keeps the change self-contained to the hook file (no settings/registration coupling); the per-Bash-invocation cost is one jq parse then exit, negligible. (Optional follow-up: also drop `Bash` from the registered matcher for zero invocation overhead.)
- **DD-2**: Keep `_has_write_pattern` in lib.sh (workflow-gate consumer) — SFG just stops calling it (DD chosen for INV-004).
- **DD-3**: Delete rather than feature-flag the extraction path (no dead code — INV-005 / AP-022).

## Open Questions
- **OQ-001** — **RESOLVED** (see Security Residual): Class-B contracts (`harness-fingerprint.json`, `model-baselines.json`, `preferences.md`) had SFG's Bash-block as their only structural leg → residual accepted + contracts amended (INV-009), no replacement gate.
- **OQ-002**: Should `Bash` also be dropped from the registered hook matcher (settings.json / plugin hooks config) as a follow-up, for zero invocation overhead? (DD-1 defers this.)
- **OQ-003** (F4): Should the `custom_patterns` config-parse path be hardened to a hard exit-2 (fail-closed) when `workflow-config.json` exists but is unparsable, instead of degrading to DEFAULTS-only? Pro: strict PAT-001 clause-5. Con: a corrupt config would then block ALL Edit/Write (even to non-protected files) until fixed — a usability regression. This spec chooses the documented narrow exception (INV-008); hardening is a separate, deliberate decision deferred here.
