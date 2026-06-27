# Spec: Reduce sensitive-file-guard to Edit/Write-tool-path only (remove the Bash extraction path)

## Metadata
- **Created**: 2026-06-25T16:20:38Z
- **Reviewed**: 2026-06-25/26 (round 1 human/codex: 4 findings; round 2 /creview-spec 6 agents: 13 findings; round 3 human/codex: 4 findings incl. the Tier-1/2/3 residual correction — the accepted residual is the WHOLE non-`cmd_*`-gated DEFAULTS set, not 3 files. All incorporated; direction confirmed sound across all rounds.)
- **Status**: reviewed
- **Impacts**: ABS-045 (narrows further). **Tier 1 (forge detected at a `cmd_*` gate — true no-op): ABS-029, ABS-041.** **Tier 2 (SFG-was-a-real-leg, surviving leg is who-writes/code-structure, NOT runtime write-prevention — accepted residual): ABS-030, ABS-035, ABS-038, ABS-040, ABS-042.** **Tier 3 (SFG-was-the-leg, named: ABS-027 harness-fingerprint/model-baselines, semi-auto R-019 preferences.md).** All Tier-2/3 amended to Edit/Write-only (INV-009) — see corrected Security Residual. the 2026-04-26 + 2026-04-30 CLAUDE.md conventions (amended), AGENT_CONTEXT.md Hooks row, README, CHANGELOG, `.claude/rules/hooks-pretooluse.md` (extraction-path carve-out removed; DEFAULTS-only-on-config-failure narrow exception documented — F4), `docs/skills/cmodelupgrade.md`, `docs/features/harness-fingerprint.md`. Tests impacted (Test Corpus Migration): `test-sfg-rescope.sh` (delete), `test-sensitive-file-guard.sh`, `test-harness-fingerprint.sh`, `test-semi-auto-mode.sh`, `test-hook-sync.sh`, `test-architecture-drift.sh` (verify).
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
- `.correctless/ARCHITECTURE.md`: narrow ABS-045 to "Edit/Write/MultiEdit/NotebookEdit/CreateFile tool-path only; Bash-mediated writes (redirects, writer commands, interpreters, git) are ALL accepted non-goals." Update the SFG clause in ABS-029/030/035/038/040/041/042 (drop the Bash-redirect claim; name the ACTUAL surviving leg per entry — only ABS-029/041 have a `cmd_*` gate; ABS-030/035/038/040/042 are accepted residuals per the corrected Security Residual). **Amend ABS-027: drop "blocks Edit/Write AND Bash redirects via `_has_write_pattern`" → "structural on the Edit/Write tool-path; Bash-mediated writes are accepted non-goals (advisory fingerprint, residual accepted)" (INV-009).**
- `docs/skills/cmodelupgrade.md` (~L80) and `docs/features/harness-fingerprint.md` (~L82): sweep the SFG-Bash-protection claims to the Edit/Write-tool-path framing (F3).
- `CLAUDE.md`: amend the 2026-04-26 "structurally-enforced sole-writer" convention (it currently requires the hook to block BOTH Edit/Write AND Bash redirects via `_has_write_pattern`) — the Bash-redirect requirement is removed; the structural leg is the content-based `cmd_*` gate. Amend the 2026-04-30 convention similarly.
- `.correctless/AGENT_CONTEXT.md`: rewrite the Hooks-row SFG description (Edit/Write tool-path guard only).
- `README.md` / `CHANGELOG.md`: announce the further reduction.
- `.claude/rules/hooks-pretooluse.md`: the clause-5 *extraction-path* carve-out (added by #205) is removed along with the extraction path. Per INV-008 (and R2-round-3/finding-4): do NOT claim "SFG once again has no fail-open path" — the pre-existing `custom_patterns` config-parse degradation (DEFAULTS-only fallback, hook ~L919) survives on the Edit/Write path. The rule-file edit replaces the extraction carve-out with the honest narrow exception: "SFG degrades to DEFAULTS-only (never fully open) when `custom_patterns` config is unparsable; the stdin-input-parse path stays strict fail-closed (exit 2)."

**Out of scope (explicit non-goals):**
- `scripts/lib.sh` `_has_write_pattern` and `get_target_file` are **NOT removed** — `hooks/workflow-gate.sh` consumes `_has_write_pattern` independently. SFG simply stops calling it. lib.sh is unchanged.
- The `DEFAULTS` protected-pattern list and `custom_patterns` config are unchanged — *which* files are protected is unaffected; only the Bash-command detection is removed.
- `workflow-gate.sh` behavior is unaffected.
- `redact-secrets.sh` is unaffected.

## Complexity Budget
- **Estimated LOC**: **minus ~550 net** (delete the extraction path + helpers; the hook drops from ~600 to ~30-40 lines).
- **Files touched**: `hooks/sensitive-file-guard.sh` (+ mirror), `tests/test-sensitive-file-guard.sh` (remove Bash corpus), DELETE `tests/test-sfg-rescope.sh`, `.correctless/ARCHITECTURE.md` (ABS-045-body/027/012/016/TB-001b + 029/030/035/038/040/041/042), `CLAUDE.md`, `.correctless/AGENT_CONTEXT.md` (Hooks-row + L40 + test count), `README.md`, `CHANGELOG.md`, `.claude/rules/hooks-pretooluse.md`, **`CONTRIBUTING.md`** (test-count 103→102 — R2/RS-005 fail-the-suite), **`docs/standard-workflow.md`** (R2/RS-007), **`docs/skills/cmodelupgrade.md`**, **`docs/features/harness-fingerprint.md`**, **`.claude/rules/sfg-deliverable.md`** (verify). Tests inverted/updated: `test-harness-fingerprint.sh` (PRH-002e/f/g), `test-semi-auto-mode.sh` (R-019), `test-hook-sync.sh` (INV-005 caller + test_qa002 Bash-write).
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
- **Enforcement** (R2/RS-010 — re-grounded): the `_has_write_pattern`/`get_target_file` golden-hash test lived in `tests/test-sfg-rescope.sh`, which this feature DELETES. So enforcement is: (a) the behavioral characterization corpus in `tests/test-hook-sync.sh` (:745-827, :156-268) + `tests/test-workflow-gate.sh` — both transit `_has_write_pattern` and prove lib.sh behavior is unchanged — stays green; AND (b) `git diff scripts/lib.sh` is empty (the feature touches no lib.sh line). Do NOT cite a golden-hash mechanism that won't exist post-delete. (Optional: relocate the golden-hash assertion into `tests/test-hook-sync.sh` if a hash pin is wanted.)

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

### INV-007: Documentation describes an Edit/Write-tool-path guard (doc coherence) — PINNED reject-list (review R2)
- **Type**: must
- **Category**: documentation
- **Statement**: After this feature, no **current-state** doc may claim SFG inspects or blocks Bash commands, redirects, or writer commands.
- **Grep corpus**: `.correctless/ARCHITECTURE.md`, `CLAUDE.md`, `.correctless/AGENT_CONTEXT.md`, `README.md`, **all of `docs/**` MINUS the named journals** (R2/RS-007: `docs/standard-workflow.md:134` is a current-state doc OUTSIDE a `docs/skills`+`docs/features`-only corpus — widen to `docs/**`), and `.claude/rules/sfg-deliverable.md` (cited by the BLOCKED message, loaded into agent context).
- **PINNED reject-substrings (R2/RS-003 — the grep is keyed on these literals, normalized for space/hyphen, NOT on "blocks Bash")**: `direct redirect/writer-command`, `direct-redirect` (AGENT_CONTEXT:40 hyphenated variant), `direct Bash write-destination`, `blocks Edit/Write AND Bash redirects`, `blocks ... Bash redirects via _has_write_pattern`, and the README extraction-path phrasings `write-target extraction path` / `fails open on ambiguity`. After the sweep: **zero matches** of these in the corpus.
- **FULL enumerated amend set (R2/RS-001/RS-002 — do NOT rely on the grep alone; targeted-edit each)**: ABS-045 **entire body** (Capability :457, Accepted-non-goals :458, Posture :459, Enforced-at :460, Test :462 — the latter two also carry DELETED `_extract_bash_targets` + `tests/test-sfg-rescope.sh` references that MUST be stripped), ABS-027 (:307), **ABS-012 (:202)**, **ABS-016 (:230)**, **TB-001b (:22)**, ABS-029/030/035/038/040/041/042, AGENT_CONTEXT.md Hooks-row (:15, purge the `_extract_bash_targets` paragraph) AND the design-pattern bullet (:40, hyphenated `direct-redirect`), README.md (:298 table row + :283/:276 mermaid framing), docs/skills/cmodelupgrade.md (:80), docs/features/harness-fingerprint.md (:82 + :130 HF-002 ref), docs/standard-workflow.md (:134).
- **Exclusion**: whole-file exclude `docs/dev-journal.md`, `docs/workflow-history.md`, `.correctless/ARCHITECTURE_DEPRECATED.md`, `.correctless/antipatterns-archived.md`; within `CLAUDE.md`, scope the amend assertion to the two named convention blocks (2026-04-26, 2026-04-30) and EXCLUDE the `### YYYY-MM-DD — Postmortem` PMB-ledger entries (append-only history quoting SFG, like #205's INV-012 carve-out).
- **Dangling-reference assertion (R2/RS-002, scoped per R2-round-3/finding-2)**: zero occurrences of `test-sfg-rescope` or `_extract_bash_targets` in the **current-state surfaces only** — `hooks/**`, `tests/**`, `.correctless/ARCHITECTURE.md`, `CLAUDE.md`, `.correctless/AGENT_CONTEXT.md`, `README.md`, `CONTRIBUTING.md`, `docs/**` (minus journals), `.claude/rules/**`. EXCLUDE `.correctless/specs/**` (this spec AND historical specs like `harness-fingerprint-r2-hardening.md` legitimately name these symbols as historical/design records — same rationale as the journal exclusion), `.correctless/artifacts/**`, `.correctless/verification/**`, and the archives. Without this scoping the assertion self-fails on the spec corpus.
- **Enforcement**: CI grep test over the corpus (reject-substrings absent; enumerated entries edited; dangling refs zero).

### INV-008: PAT-001 extraction-path carve-out removed; remaining non-strict path documented narrowly (F4)
- **Type**: must
- **Category**: security / documentation
- **Statement**: `.claude/rules/hooks-pretooluse.md`'s clause-5 carve-out (added by #205 for the *extraction* path's fail-open) MUST be removed — the extraction path is deleted, so that carve-out no longer describes anything. The rule file MUST NOT claim SFG has "no fail-open path", because a pre-existing narrower behavior remains on the Edit/Write path: `custom_patterns` are read with `… 2>/dev/null || CUSTOM_PATTERNS=""` (hook ~L917), so a present-but-unparsable `workflow-config.json` silently degrades to **DEFAULTS-only** matching (built-in protected patterns still enforced; user-added `custom_patterns` lapse). This is unchanged by this feature. Disposition (chosen): **document it as a narrow, named exception** in the rule file — "SFG degrades to DEFAULTS-only (never fully open) when `custom_patterns` config is unparsable; DEFAULTS remain enforced" — rather than hardening it to a hard exit-2 (hardening would block *all* edits on a corrupt config, a usability regression; see OQ-003).
- **Enforcement**: CI test asserts (a) the extraction-path carve-out subsection is gone, and (b) the rule file documents the DEFAULTS-only-on-config-failure narrow exception (so the claim is honest).

### INV-009: ABS-027 + ABS-012/016 + TB-001b + R-019 + the CLAUDE.md conventions amended to Edit/Write-tool-path-only
- **Type**: must
- **Category**: security / documentation (Class-B residual, see Security Residual)
- **Statement**: The following MUST be amended to drop any "blocks Bash redirects / direct redirect/writer-command" SFG claim and state structural enforcement is **Edit/Write-tool-path only; Bash-mediated writes are accepted non-goals (AP-040)**:
  - **ABS-027** (Invariant :307 — drop "blocks Edit/Write AND Bash redirects via `_has_write_pattern`"; the `via _has_write_pattern` phrasing was already stale post-#205). Add the residual note: "fingerprint is advisory (PRH-001), residual accepted."
  - **ABS-012** (:202) and **ABS-016** (:230) — both carry the "direct redirect/writer-command paths" clause (they keep their SHA-256 structural leg — Class-A integrity-wise — but the *prose* is false). R2/RS-001: explicitly enumerated (ABS-045:456 lists them as SFG-governed).
  - **TB-001b** (:22) — the architecture home of the `preferences.md` SFG claim ("direct redirect/writer-command writes to `preferences.md`"). R2/RS-009: re-frame to Edit/Write-tool-path only.
  - **semi-auto-mode R-019** test contract (per Test Corpus Migration).
- **Convention amendment with POSITIVE replacement (R2/RS-008 — not prose-deletion only)**: the 2026-04-26 + 2026-04-30 CLAUDE.md conventions MUST be rewritten to state the structural leg is "Edit/Write tool-path (sensitive-file-guard) + the content-based `cmd_*` phase-transition gate" and MUST drop the steps instructing future specs to "verify the hook blocks BOTH Edit/Write AND Bash redirects" / "add a structural test covering both block paths." Enforcement is two-sided: the INV-007 grep asserts the stale string is ABSENT, AND a positive assertion that the amended convention NAMES the `cmd_*` gate as the structural leg (so the next sole-writer feature reads the corrected contract — closes the AP-026/AP-036 prose-drift this feature is ironically about).
- **Durable downgrade marker (R2/RS-005-design-contract)**: append a one-line note to ABS-027 and ABS-045 — "Bash-redirect structural leg removed 2026-06 by sfg-edit-write-only; residual accepted (advisory/owner-scaffolded files, surviving Edit/Write leg)" — enforced as a required-PRESENT string by the INV-007 test, so the deliberate removal is a recorded reviewed decision, not silent.
- **Violated when**: any enumerated entry/convention still asserts SFG blocks a Bash redirect/writer to a protected path, or the downgrade marker is absent.
- **Enforcement**: CI grep (shared with INV-007, reject-list + required-present markers) + the inverted test assertions (Test Corpus Migration).

### INV-010: BLOCKED message + CHANGELOG reflect Edit/Write-only, honestly (R2/RS-012)
- **Type**: must
- **Category**: UX / documentation
- **Statement**: (a) The hook's BLOCKED message (hook ~L995-996) MUST drop Bash-write framing (it only ever fires on an Edit/Write tool target) — re-word "this command writes to" to tool-target framing and keep an actionable recovery path; the message must NOT say "command". (b) The `CHANGELOG.md` entry MUST frame this as a security **downgrade** (not merely "simplification"): state plainly that SFG no longer guards ANY Bash write to a protected file, name the Class-B files (`harness-fingerprint.json`/`model-baselines.json`/`preferences.md`) whose only structural Bash leg is removed, and add the existing-user note "custom_patterns continue to guard the Edit/Write tool-path; they no longer guard Bash redirects/writer commands." The #205 CHANGELOG entry that still lists SFG blocking "output redirects/writer commands" MUST be corrected (it becomes false).
- **Violated when**: the fired message says "command" / mentions Bash; or the CHANGELOG frames the change as a pure simplification without the downgrade + Class-B disclosure.
- **Enforcement**: a message-content test (asserts the Edit/Write framing, absence of "command") + review-time CHANGELOG check (the existing prefix-only test at `test-sensitive-file-guard.sh:441` does not cover the body, so add a body assertion).

## Prohibitions

### PRH-001: Never re-introduce Bash-command inspection
- The hook MUST NOT parse, tokenize, or extract write targets from `tool_input.command`. The fast-path for Bash is unconditional exit 0.

### PRH-002: Never allow a previously-blocked Edit/Write target
- The reduction MUST NOT make any Edit/Write/MultiEdit target previously blocked now pass. The entire existing Edit/Write corpus is the MUST-PASS-UNCHANGED set.

### PRH-003: Never modify lib.sh `_has_write_pattern` / `get_target_file`
- They survive for `workflow-gate.sh` (INV-004, golden-hash pinned).

## Security Residual Analysis (the review focus — CORRECTED after review round 1)

Removing SFG's Bash-redirect leg means a direct `echo x > <protected>` / `tee <protected>` / `cp x <protected>` Bash command is **no longer blocked**. **Review round 1 falsified the original "redundant secondary leg" claim** — for at least three contracts SFG's Bash-block was a *real* structural leg with NO content-hash/`cmd_*` replacement. The contracts split into two classes:

**Tier 1 — a `cmd_*`/content gate DETECTS a forge (downgrade is genuinely a no-op for integrity):** ONLY these have a content-equality phase-transition gate that catches a forged Bash write at the next transition:
- **ABS-029** (audit-record: `cmd_audit_done` content-gate) and **ABS-041** (sfg-lift: `cmd_done` gate + HEAD-SHA test-success sentinel). A Bash forge is detected at the transition by content mismatch. SFG's Bash-block was genuinely redundant for *detection*. **Accepted — no integrity change.**

**Tier 2 — SFG's Bash-block WAS a real structural leg; the surviving leg is WHO-writes / code-structure, NOT runtime out-of-band-write prevention OR detection (R2-round-3/finding-1 — the spec previously misclassified these as Class-A `cmd_*`-gated):** removing SFG's Bash-block leaves a runtime out-of-band Bash redirect to these files **unguarded AND undetected** until a downstream consumer notices corruption:
- **ABS-030** (`autonomous-decisions-*.jsonl`): #205 already established "SFG redirect-block was its only structural leg — no `cmd_*` gate backs the JSONL." Surviving leg: the R-013 JSONL-growth check (advisory, post-hoc). No content gate.
- **ABS-035** (`scripts/wf/*` dispatcher modules): surviving leg is the **structural tests** (`test-workflow-advance-decomp.sh`) — *test-time*, not runtime; they catch a malformed module on the next CI run, not at write time. (:372)
- **ABS-038** (archive files): surviving leg is the `/cprune`-is-sole-writer **convention** (prose) — no runtime gate. (:397)
- **ABS-040** (`prune-pattern-baseline.json`): surviving leg is the `prune-scan.sh --update-baseline` sole-writer + the autonomous-no-update structural assertion — about *who/how*, not preventing a raw redirect. (:413)
- **ABS-042** (external-review history/output): **explicitly chose invocation-coupling over the ABS-029 `cmd_*` gate** (:430). Surviving leg is invocation-coupling + ABS-003 lock — does not stop a raw redirect.

**Tier 3 — SFG's Bash-block WAS the structural leg, named explicitly (these were already in the spec):**
- **`harness-fingerprint.json` / `model-baselines.json` (ABS-027)**: `.correctless/ARCHITECTURE.md` ABS-027 states verbatim — "Sole-writer enforcement is structural (sensitive-file-guard blocks Edit/Write AND Bash redirects via `_has_write_pattern`), not advisory." There is **no content-hash/`cmd_*` gate** behind these files; SFG's Bash-block *was* the structural enforcement against out-of-band writes. `tests/test-harness-fingerprint.sh` (PRH-002e) asserts the live Bash-redirect block.
- **`preferences.md` (semi-auto-mode R-019 + TB-001b)**: `tests/test-semi-auto-mode.sh` asserts SFG blocks both `Edit` AND `Bash` writes to `.correctless/preferences.md`. **Highest-consequence Class-B file (R2/RS-009)**: `preferences.md`'s `pr_creation: custom` value feeds a shell **`eval`** in `/cauto` Step 9 (TB-001b) — forging it is RCE-adjacent, not a nudge. TB-001b's trust model explicitly cites SFG's "direct redirect/writer-command writes to `preferences.md`" — that clause becomes false. **Why the residual is still accepted**: (1) the surviving Edit/Write leg blocks the agent's *direct tool-call* forge; (2) per PMB-020/AP-040 the Bash leg was always evadable — a motivated injection could already forge it via `bash -c 'printf … > prefs'` (interpreter opacity) pre-#205, so this feature only adds the *naive literal redirect* form to an already-open obfuscated route; (3) `preferences.md` is owner-scaffolded (TB-001a) and human-approved. **Note**: `preferences.md` is a DEFAULTS entry, so the custom_patterns config-degradation (INV-008) does NOT drop its Edit/Write protection. TB-001b's prose MUST be amended (INV-009).

**Disposition for Tiers 2 AND 3: accept the residual downgrade (NO replacement gate).** For EVERY DEFAULTS-protected sole-writer/state file WITHOUT a `cmd_*` content gate (all of Tier 2 + Tier 3 — ABS-030/035/038/040/042 + ABS-027 + preferences.md), structural enforcement narrows to the **Edit/Write tool-path only**; a runtime out-of-band Bash redirect/writer to them becomes an accepted non-goal, **unguarded and (absent a content gate) undetected**. Justification holds across all of them: (1) the realistic *accidental* case is an Edit/Write tool call, still guarded by the surviving leg; (2) the Bash-redirect leg was always trivially evadable via an interpreter (PMB-020/AP-040) — a motivated agent/injection could already forge any of these via `bash -c 'printf … > file'` pre-#205, so this feature only adds the *naive literal redirect* form to an already-open obfuscated route; (3) these are dev-workflow state files (advisory fingerprints, measurement baselines, decision logs, module code, archives), not a security product's secrets; (4) the highest-consequence files have defense-in-depth on the WHO axis even without SFG — `preferences.md`→eval is owner-scaffolded + human-approved (TB-001a), ABS-042 external-review→codex is invocation-coupled. (5) A replacement `cmd_*` gate is disproportionate — most are not phase-transition artifacts with a natural transition to gate at. **All these contracts are amended (INV-009) to state structural enforcement is Edit/Write-tool-path only, with the durable downgrade marker.** This is a deliberate, documented, BROAD security downgrade (the whole non-`cmd_*`-gated DEFAULTS set, not three files) — surfaced prominently so it can be rejected in favor of keeping protection (which would mean retaining Bash parsing, contradicting the simplification).

**The convention text**: the 2026-04-26 convention's requirement ("verify the hook blocks BOTH Edit/Write AND Bash redirects") and the per-entry "blocks ... Bash redirects" claims become false and MUST be amended, or they mislead the next sole-writer feature into assuming a Bash-redirect guard that no longer exists (AP-026/AP-036 advisory-prose-drift hazard).

**OQ-001 — RESOLVED (corrected R2-round-3)**: the accepted residual is NOT three files — it is the ENTIRE non-`cmd_*`-gated DEFAULTS set: Tier 2 (ABS-030/035/038/040/042) + Tier 3 (ABS-027 harness-fingerprint/model-baselines, preferences.md). Only ABS-029 and ABS-041 (Tier 1) retain a forge-detecting `cmd_*` gate. Resolution = accept the residual + amend EVERY affected contract/test/doc (INV-007/INV-009 enumerate them) + the durable downgrade marker. No replacement gate is added.

## STRIDE (TB-001: agent-proposed action -> file write)
- **Tampering (write to a protected file)**: mitigated ONLY on the Edit/Write tool path now. Bash-mediated writes (redirect, writer command, interpreter, git) are ALL accepted non-goals. This is a deliberate, documented reduction — the guardrail catches the naive Edit/Write tool call, nothing else. A cooperative-loop PreToolUse hook cannot stop a motivated agent or injection regardless (PMB-020); the Edit/Write guard remains as cheap insurance against the agent's own careless tool call.
- **Denial of service**: the prior over-extraction/O(n^2) self-DoS is fully eliminated (no Bash inspection at all).
- Spoofing / Repudiation / Information-disclosure / EoP: unchanged / out of scope (redact-secrets owns egress).

## Test Corpus Migration (expanded after review — F2)

A repo-wide grep (`tool_name":"Bash"` near a protected path, plus `_has_write_pattern` callers) identified every test asserting the old SFG Bash contract. Explicit disposition per file:

- **DELETE** `tests/test-sfg-rescope.sh` — tests the removed Bash extraction path in its entirety (INV-001..020 of #205 are all Bash-extraction invariants). Nothing survives.
- **`tests/test-sensitive-file-guard.sh`** (expanded R2-round-3/finding-3):
  - **MUST-PASS-UNCHANGED**: the entire Edit/Write/MultiEdit corpus, the malformed-JSON fail-closed test (`test_da003`), the canonical-matching tests, and the INV-005a canonicalize-sentinel-probe test (the probe survives on the Edit/Write path).
  - **MUST-DELETE (structural tests that awk the `_extract_bash_targets` BODY — they hard-FAIL when the function is absent)**: `test_prh001*` (:1387 — `awk '/^_extract_bash_targets.../' ; if [ -z "$body" ]; then fail`) and `test_prh005*` (:1591 — same body extraction). These cannot be "inverted"; the function they inspect is gone. Delete them (PRH-001's intent — "no token-driven extraction" — is now trivially true since there is no extractor; INV-005's "no helper defined" structural grep replaces them).
  - **MUST-INVERT (every Bash assertion expecting exit 2 → exit 0)**: the redirect-block corpus (`test_inv007_redirect_blocks*` :1419), the `perl -i`/`sed -i` "STAY blocked" cases (:1563), the `> .env`/`tee`/`cp`/`mv` direct-block corpus (:166-201), the chained-redirect (:775), quoted forms (:982/:986), traversal redirects (:1247), and the `cp .env backup` source-read (already exit 0 — keep). RED precondition: each chosen command must exit 2 against the #205 hook (else the inversion proves nothing — RS-001-testability).
  - **ADD**: the INV-005 structural test (hook defines none of the 10 deleted helpers + `_SFG_LENGTH_CAP` + the `COMMAND=`/`${#COMMAND}`/`if [ "$TOOL_NAME" = "Bash" ]` Bash-branch); a representative "Bash is never blocked" corpus (INV-001) drawn from the inverted exit-2 commands; the INV-010 BLOCKED-message body assertion.
- **`tests/test-harness-fingerprint.sh`** (F2 + R2/RS-006): **MUST-INVERT all THREE** live-Bash assertions (exit 2 → exit 0): PRH-002e (:1012 redirect→fingerprint), PRH-002f (:1020 redirect→baseline), **PRH-002g (:1029 `tee`→fingerprint)** — the spec previously named only e/f. KEEP the Edit-block assertion (:1037+) at exit 2. **KEEP the filename strings**: PRH-002c/d (:997/:1003) grep that `test-sensitive-file-guard.sh` *mentions* `harness-fingerprint.json`/`model-baselines.json` — the retained Edit/Write assertions must preserve those strings.
- **`tests/test-semi-auto-mode.sh`** (F2): **MUST-INVERT** `:816-817` (`cat data > .correctless/preferences.md` exit 2 → exit 0). KEEP `:808-813` (Edit block), `:820-821` (`docs/preferences.md` not blocked), and `test_pre006` (preferences.md in DEFAULTS — stays green, DEFAULTS unchanged).
- **`tests/test-hook-sync.sh`** (F2 + R2/RS-004 — TWO fail-the-suite assertions): (a) **MUST-INVERT `:454-461`** (`sfg_calls_fn -gt 0 → PASS` becomes `-eq 0`: SFG no longer calls `_has_write_pattern`); KEEP `:444-452` (workflow-gate still calls it) and `:422-430` (neither hook DEFINES it locally). (b) **MUST-UPDATE `test_qa002` :716-728** — it includes a `Bash-write: cp a.ts b.ts` case asserting exit 2 "without lib.sh (INV-005a fail-closed)"; after the Bash fast-path-exit-0 a Bash command never reaches the lib.sh-missing branch → exit 0 → SUITE FAIL. Remove/invert the Bash-write case from test_qa002 (keep the Edit/Write fail-closed cases). KEEP `:693`-region INV-005a canonicalize-sentinel test green (the probe survives on the Edit/Write path).
- **`tests/test-architecture-drift.sh`** (R2/RS-013 — RESOLVED, not "verify"): ABS-027 checks (:1615-1625) assert only the heading + `harness-fingerprint` ref, NOT the Bash sentence — **no ABS-027-text change**. BUT the count check (:1926-1936) compares `CONTRIBUTING.md` "N test files" vs `find tests`; deleting `test-sfg-rescope.sh` makes actual=102 — handled by the CONTRIBUTING decrement below.
- **`tests/test-cprune.sh`** (R2/RS-013 — RESOLVED): `:1128-1134` are DEFAULTS-membership checks unrelated to Bash — **no change** (DEFAULTS unchanged).
- **`CONTRIBUTING.md`** (R2/RS-005 — FAIL-THE-SUITE): currently claims "103 test files" (:23). Deleting `test-sfg-rescope.sh` drops actual to 102 → `test-architecture-drift` AP-005(tests) FAILS. **MUST decrement 103 → 102** in lockstep with the deletion. (Re-check `.correctless/AGENT_CONTEXT.md` for a pinned test count too — #205 bumped it 102→103; this feature reverses it.)
- **OUT OF SCOPE (unchanged)**: `tests/test-workflow-gate.sh`, `tests/test-gate-path-exceptions.sh` — they test `workflow-gate.sh`'s independent `_has_write_pattern` use (untouched). MUST stay green (INV-004).

## Environment Assumptions
- **EA-001** (R2/RS-011 — completed): the surviving Edit/Write path depends on these lib.sh functions: `config_file` (which **transitively calls `repo_root`** — name it so a future lib.sh refactor doesn't drop `repo_root` assuming SFG no longer needs it), `canonicalize_path` (PAT-017 — called at the matcher AND at the v1 sentinel probe, hook:105, which is RETAINED). `_has_write_pattern` is NO LONGER a dependency (its only call site, the Bash branch, is deleted). Cleanup note: the hook's `set -f` (glob-disable for `*.pem` matching) and hook-scope `LC_ALL=C` (byte-oriented matching) are STILL required on the Edit/Write path, but the inline rationale comment (~L23-26, "Extraction runs BEFORE canonicalize_path's LC_ALL=C") references the deleted extraction path and MUST be rewritten — keep the directives, fix the rationale.
- **EA-002**: bash >= 4.0 floor unchanged (the surviving code uses `${var,,}` lowercasing + `[[ =~ ]]`).

## Design Decisions
- **DD-1**: Fast-path `exit 0` for Bash inside the hook (STEP 3), rather than removing `Bash` from the hook matcher in settings — keeps the change self-contained to the hook file (no settings/registration coupling); the per-Bash-invocation cost is one jq parse then exit, negligible. (Optional follow-up: also drop `Bash` from the registered matcher for zero invocation overhead.)
- **DD-2**: Keep `_has_write_pattern` in lib.sh (workflow-gate consumer) — SFG just stops calling it (DD chosen for INV-004).
- **DD-3**: Delete rather than feature-flag the extraction path (no dead code — INV-005 / AP-022).

## Open Questions
- **OQ-001** — **RESOLVED** (see Security Residual): Class-B contracts (`harness-fingerprint.json`, `model-baselines.json`, `preferences.md`) had SFG's Bash-block as their only structural leg → residual accepted + contracts amended (INV-009), no replacement gate.
- **OQ-002**: Should `Bash` also be dropped from the registered hook matcher (settings.json / plugin hooks config) as a follow-up, for zero invocation overhead? (DD-1 defers this.)
- **OQ-003** (F4): Should the `custom_patterns` config-parse path be hardened to a hard exit-2 (fail-closed) when `workflow-config.json` exists but is unparsable, instead of degrading to DEFAULTS-only? Pro: strict PAT-001 clause-5. Con: a corrupt config would then block ALL Edit/Write (even to non-protected files) until fixed — a usability regression. This spec chooses the documented narrow exception (INV-008); hardening is a separate, deliberate decision deferred here.
