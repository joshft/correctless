# Spec: Re-scope sensitive-file-guard from perimeter to write-target-only guardrail

## Metadata
- **Created**: 2026-06-20T02:05:00Z
- **Reviewed**: 2026-06-24 (/creview-spec — 6 agents; 24 findings; 4 BLOCKING resolved into this revision)
- **Status**: reviewed
- **Impacts**: documentation-coherence sweep is IN SCOPE (RS-002). Touches the framing of ABS-029, ABS-030, ABS-035, ABS-038, ABS-040, ABS-041, ABS-042; the 2026-04-30 "gate-enforced phase-transition artifact contract" and 2026-04-26 "sole-writer for meta files" conventions in `CLAUDE.md`; the AGENT_CONTEXT.md Hooks row; and `.claude/rules/hooks-pretooluse.md` (PAT-001 clause-5 carve-out). No CODE impact on shared `_has_write_pattern` or `workflow-gate.sh`.
- **Branch**: feature/sfg-rescope
- **Research**: null
- **Recommended-intensity**: high
- **Intensity**: high
- **Intensity reason**: file-path signal (`hooks/sensitive-file-guard.sh`) + keyword signal ("injection", "security"); project floor high
- **Override**: none

## Context

`hooks/sensitive-file-guard.sh` (SFG) is a Claude Code **PreToolUse hook**. It was specced and hardened across 5+ features as a security **perimeter** — "structurally impossible out-of-band writes", fail-closed-on-everything, and a deliberately over-extracting Bash target extractor that flags *every* non-flag token as a candidate write target. Per **PMB-020 / AP-040**, that framing is a category error: a cooperative-loop PreToolUse hook can only ever be a **guardrail/speedbump** that catches *accidental* and *naively-injected* out-of-band writes — it is trivially evaded (name the directory not the file, route through an interpreter, use any ungated tool), so it cannot be a perimeter, and correctless is a development-workflow tool, not a security product.

The cost of the mismatch is paid entirely in false-positive friction: `_extract_bash_targets` over-extracts every token once `_has_write_pattern` fires, and `_has_write_pattern` fires on `2>/dev/null` and bare interpreter use — i.e. constantly. In a single `/cchores` dogfood session (2026-06-19) SFG produced **6 false blocks**, every one a read / invocation / restore (`jq` config read, `[ -f ]` presence check, `git checkout -- scripts/lib.sh` to recover a setup-deleted file, `ls`, `bash harness-fingerprint.sh check 2>/dev/null`), **zero** write attacks. (The 2026-06-24 /creview-spec session reproduced the friction live: SFG blocked **9** more reads/invocations/sources — `jq` config read, `[ -f …external-review-run.sh ]`, `source scripts/lib.sh` — while reviewing the very spec that fixes it.) This feature right-sizes SFG to a guardrail by making it block only **actual write destinations**.

## Scope

**In scope — `hooks/sensitive-file-guard.sh`:**
- Rewrite `_extract_bash_targets` so it extracts only genuine write destinations from a Bash command, never invocation arguments, read inputs, or incidental tokens.
- Apply the rewrite while preserving the existing canonicalize-and-match downstream (`canonicalize_path` on both sides — PRH-004 / PAT-017) and the Edit/Write/MultiEdit precise-target path.
- Update the BLOCKED message (hook L375-376) to the guardrail framing (INV-014 / RS-011).

**In scope — documentation coherence sweep (RS-002, decided 2026-06-24 "fold doc sweep into this feature"):**
- `.claude/rules/hooks-pretooluse.md` (PAT-001): add a clause-5 carve-out documenting the extraction-path fail-open (INV-007/INV-008) — required for the loosening to be "loud and reviewable" (INV-013 / RS-003).
- `.correctless/ARCHITECTURE.md`: scope down the SFG enforcement clause in ABS-029, ABS-030, ABS-035, ABS-038, ABS-040, ABS-041, ABS-042 to "protects tool-target writes + direct redirect/writer-command destinations; interpreter/git-mediated out-of-band writes are accepted non-goals (AP-040)"; add a new ABS entry for the guardrail capability boundary (INV-012 / RS-019).
- `CLAUDE.md`: amend the 2026-04-30 and 2026-04-26 sole-writer conventions so future specs rely on SFG only for Edit/Write + direct redirect/`tee`/`cp`/`mv`/`sed -i` blocking, and add a `cmd_*` phase-transition gate if they need protection against interpreter/git-mediated writes.
- `.correctless/AGENT_CONTEXT.md`: rewrite the Hooks-row SFG description (drop "every non-flag token is a candidate" / "flags interpreter+eval-flag chains"; describe it as a write-target guardrail).
- `README.md`: re-frame the SFG description (currently "Secret protection" / "fail-closed, no overrides" at ~L276/L298) as a write-target guardrail; "fail-closed" now applies to the input-parse path (INV-008), not the extraction path (CX-003).
- `docs/skills/*`: sweep the user-facing skill docs that describe SFG enforcement — at minimum `docs/skills/cmodelupgrade.md` (~L80 still says SFG blocks Edit/Write and Bash redirects as *structural enforcement*); grep `docs/skills/` for SFG references and scope each to the guardrail framing (CX-003).
- `CHANGELOG.md`: one entry announcing the re-scope so the loosening is loud at upgrade time (INV-015 / RS-010).

**Out of scope** (explicit non-goals):
- The shared `_has_write_pattern` and `get_target_file` in `scripts/lib.sh` are **not** changed — `workflow-gate.sh` consumes `_has_write_pattern` and must be unaffected (decision 1.1). `_has_write_pattern` remains the cheap pre-filter; precision now lives in extraction. (`_has_write_pattern` is an intentionally-broad pre-filter that over-fires relative to what is actually blocked — see INV-016; do not "fix" its over-firing.)
- The `DEFAULTS` protected-pattern list and the `custom_patterns` config mechanism are **not** changed — *which* files are protected is a separate concern from read-vs-write discrimination (#196 notes the +68 DEFAULTS as a follow-up).
- The **lift-and-restore apparatus** (AP-037 sentinel, `check-no-pending-sfg-lift.sh`, `cmd_done` gate) for **Edit/Write to deliverables** stays in place and remains friction — INV-009 deliberately does not touch the Edit/Write path, so this Bash-only re-scope does not retire that ceremony (RS-012; see OQ-004).
- `redact-secrets.sh` is a separate mechanism with its own privacy justification — untouched.
- Defending against obfuscated / interpreter-mediated / git-mediated writes is an **accepted non-goal** — that is perimeter work the enforcement layer cannot deliver (see STRIDE).
- **Exotic write forms fail open** (decided 2026-06-24 "cover common naive forms, fail-open the exotic"): `cp -t/--target-directory` and `install -t` (destination-relocating flags), `install -d` (multi-destination directory-create mode), `ln` one-argument form, **all process substitution payloads (`>(…)`/`<(…)`) — CX-002**, and destinations containing IFS bytes (spaces) are **accepted fail-open gaps** — documented in INV-002/INV-003/INV-005 and EA-001, not handled. They are uncommon and the guardrail (not perimeter) framing accepts them.

## Complexity Budget
- **Estimated LOC**: ~80 net (rewrite one hook function; update one message) + doc edits across 7 files
- **Files touched**: `hooks/sensitive-file-guard.sh` + its mirror `correctless/hooks/sensitive-file-guard.sh` (via `sync.sh`) + `tests/test-sensitive-file-guard.sh` + `.claude/rules/hooks-pretooluse.md` + `.correctless/ARCHITECTURE.md` + `CLAUDE.md` + `.correctless/AGENT_CONTEXT.md` + `README.md` + `docs/skills/*` (SFG-referencing pages, e.g. `cmodelupgrade.md`) + `CHANGELOG.md`
- **New abstractions**: 1 (ABS-xxx guardrail capability boundary, doc-only)
- **Trust boundaries touched**: 1 (TB-001 — agent-proposed command → file write)
- **Risk surface delta**: this change is a **re-targeting, not a strict relaxation** (RS-007). It is *more permissive on incidental/read/invocation tokens* but **intentionally newly-blocks** previously-allowed accidental-write forms the old extractor missed (e.g. `dd of=.env`: old extractor emitted token `of=.env` → no match → allowed; new extractor emits `.env` → blocked). It is therefore NOT a strict superset relationship, and regression risk is **two-sided**: (a) a real write to a protected path flips to allow (caught by the Half-B still-blocked corpus, INV-017), and (b) a positional misparse newly blocks a legitimate op (caught by the Half-A newly-allowed corpus, INV-017). The "strictly more permissive" theorem is replaced by a witnessed monotonicity property (INV-017), not an asserted one.

## Invariants

> **Test approach (applies to every INV below)**: **hook-integration** — drive the full hook via a stdin JSON envelope (`{"tool_name":"Bash","tool_input":{"command":"…"}}`) and assert the process exit code (0 = allow, 2 = block), using the existing `run_hook_capture` harness. **Function-level calls to `_extract_bash_targets` are forbidden** — they bypass the `_has_write_pattern` pre-filter (hook L87) and prove nothing about the deployed gate (RS-006).

### INV-001: Reads, invocations, and incidental tokens are never write targets
- **Type**: must-not
- **Category**: functional
- **Statement**: For a Bash command, `_extract_bash_targets` MUST NOT emit any token that is a command name, an invoked script path, a read-input argument, a flag, or an option value. Only genuine write destinations (INV-002, INV-003) are emitted. A command whose only protected-path reference is a non-destination token resolves to an empty target set → allowed.
- **Violated when**: `bash .correctless/scripts/lib.sh` (invocation), `jq '.' .correctless/config/workflow-config.json` (read), `ls scripts/lib.sh`, `source scripts/lib.sh`, or `cat .env` produce a non-empty target set and the command is blocked. (Note: `jq`/`ls`/`cat`/`source` are gated OUT by `_has_write_pattern` before extraction; `bash <script>` reaches extraction and must still emit empty — include at least one fixture that *reaches* extraction.)
- **Enforcement**: CI test assertion (hook-integration)
- **Guards against**: AP-040

### INV-002: Redirect destinations ARE write targets (except sink devices)
- **Type**: must
- **Category**: functional
- **Statement**: `_extract_bash_targets` MUST emit the target of every output redirect operator — `>`, `>>`, `>|`, `1>`, `2>`, `&>`, `&>>`, `&>|`, `>&`, and the **inline-attached (glued) forms** (`cmd>file`, `cmd2>file`, `cmd&>file`) — EXCEPT when the target is (a) a sink device (INV-006), or (b) a process-substitution operand `>(…)`/`<(…)` (CX-006 — opaque/fail-open per INV-005; `echo x > >(tee .env)` is allowed). The whitespace-separated and glued forms are distinct code paths; both MUST be covered by fixtures (the glued form is NOT subsumed by the token loop because IFS does not split `>` from an adjacent non-operator token). (`&>>` is the append-both variant of `&>` — discovered missing from the operator accept-set + glued regex in mini-audit R1 (MA-002); `>>` was handled but `&>>` was not.)
- **Violated when**: `echo x > .env`, `cmd 2>> credentials.json`, `echo x >| .env`, `make 2>.correctless/meta/x`, or `echo x>.env` (glued) is allowed (under-extraction).
- **Enforcement**: CI test assertion (hook-integration)
- **Guards against**: AP-040

### INV-003: Writer-command destinations ARE write targets
- **Type**: must
- **Category**: functional
- **Statement**: `_extract_bash_targets` MUST emit the write-destination argument(s) of these writer commands:
  - `tee` / `tee -a` — every argument **not** beginning with `-` is a destination (a `-`-leading token is treated as a flag and skipped). This means `tee -- .env` and `tee --output-error=warn .env` BOTH block `.env` (the `--` / `--output-error=…` tokens are skipped as flags, `.env` is a destination) — resolving OQ-002 toward blocking the realistic cases. A dash-leading filename after `--` (`tee -- -weird.env`) fails open (exotic, accepted). `... | tee a b` emits both `a` and `b`.
  - `cp`, `mv`, `install`, `ln` — the **final non-flag positional argument *within the command segment*** is the destination (no-flag-relocation form only). Earlier (source) arguments are NOT emitted — they are reads (INV-001; see RS-016). **Positional detection MUST operate per command-segment (INV-020): a writer's "final positional argument" is computed within its own segment and never crosses an unquoted `;`/`|`/`&&`/`||`/`&` boundary.** Without segmentation, `cp src dest; cat .env` would falsely emit `.env` (cross-segment), and `cp src .env; echo ok` would falsely emit `ok` (CX-001).
  - `sed -i` / `perl -i` (in-place edit) — the file operand after the script. `perl -i` ALWAYS writes its operand regardless of the script body, so it is a writer here and is **excluded from INV-005's opaque list** (RS-001). **In-scope forms are bounded by the frozen prefilter (CX-013, INV-016)**: `_has_write_pattern` (lib.sh L491-492, frozen by INV-011) matches only the *immediate* shapes `sed[[:space:]]+-i` and `perl[[:space:]]+-i`. Therefore the extractor blocks `sed -i … .env`, `sed -i.bak … .env` (the `-i` prefix matches), and `perl -i … .env` / `perl -i -pe … .env`. Forms with a flag **between** the command and `-i` — `sed -E -i … .env`, `perl -0777 -i … .env` — do NOT fire the prefilter (so extraction never runs) and are **accepted fail-open**; BSD `sed -i '' …` (empty-suffix separate token) and multi-file `sed -i s/// a b` are also accepted fail-open (exotic). Blocking any of these would require unfreezing the prefilter, which INV-011 forbids — so INV-016 (firing ⊇ emit) is what makes the in-scope set exactly the prefilter-detected set.
  - `dd of=…` — the value of the `of=` token, scanned position-independently **across all tokens within the `dd` command segment only** (INV-020; CX-012); `if=` (input) is a read and MUST NOT be emitted. So `dd if=x of=out; printf of=.env` allows (the second `of=.env` is a `printf` arg in a different segment, not `dd`'s), and `dd if=x of=.env; echo ok` blocks.
  - `truncate` — the file operand (resolves OQ-001 toward inclusion: `truncate -s0 .env` silently empties a protected file; RS-021).
- **Accepted fail-open gaps** (decided 2026-06-24): `cp -t/--target-directory DIR`, `install -t DIR`, `install -d DIR…`, `ln` one-arg form, and destinations containing IFS bytes — these relocate or pluralize the destination in ways pure word-splitting cannot recover; they fail open per INV-007 and are documented here, not handled.
- **Violated when**: `tee .env`, `cp x .env`, `mv x .env`, `sed -i s/a/b/ .env`, `perl -i -pe 's/a/b/' .env`, `dd if=/dev/zero of=.env`, or `truncate -s0 .env` is allowed.
- **Enforcement**: CI test assertion (hook-integration)
- **Guards against**: AP-040

### INV-004: git working-tree commands are not write targets
- **Type**: must
- **Category**: functional
- **Statement**: A `git` subcommand that mutates the working tree (`checkout`, `restore`, `reset`, `stash`, `clean`, `apply`, `am`, `merge`, `rebase`, `cherry-pick`) MUST NOT cause its path arguments to be extracted as write targets. `git checkout -- <protected>` is allowed.
- **Violated when**: `git checkout HEAD -- scripts/lib.sh` or `git restore .env` is blocked.
- **Enforcement**: CI test assertion (hook-integration)
- **Guards against**: AP-040
- **Rationale**: version-control restores are not naive accidental clobbers; they are explicitly allowed per #196 acceptance.

### INV-005: Interpreter+eval chains are not write targets
- **Type**: must
- **Category**: functional
- **Statement**: An interpreter+eval chain (`bash -c "..."`, `sh -c`, `perl -e/-pe/-ne` **when no `-i` is present**, `python -c`, `node -e`, `ruby -e`, `base64 -d`, here-strings `<<<`) MUST NOT have the contents of its eval/string **operand** parsed for redirect or writer-destination targets. **Process substitution operands (`>(…)` and `<(…)`) are ALSO opaque at every level — the existing single-level sub-tokenization (hook L173-186) MUST be removed (CX-002):** `echo x > >(tee .env)` fails open (allowed) — a process-substitution write is exotic, not a naive accidental clobber, and parsing it contradicts INV-007's "only the top-level redirect/writer branches emit." **Implementation pin (CX-006): deleting the L173-186 branch is NOT sufficient, because the current IFS (`;|&()`, hook L153) splits on `(` and `)` and shatters `>(tee .env)` into bare tokens (`tee`, `.env`) that the redirect/writer branches would then mishandle.** The extractor MUST either (a) remove `(`/`)` from the extraction IFS AND excise `>(…)`/`<(…)` spans (balanced-paren or first-`)`-after-`>(` ) from the command string before tokenizing, or (b) strip those spans up front. A fixture MUST assert `echo x > >(tee .env)` allows AND that the shattered `.env` token is not independently emitted. Opacity is scoped to the eval/string/process-sub operand ONLY — redirects and writer-destinations appearing *outside* the opaque operand are still extracted (e.g. `cat <<< x > .env` MUST still block `.env`; the trailing `> .env` is outside the here-string operand).
- **Violated when**: `bash -c "echo x > .env"` is blocked (redirect inside the eval payload — opaque), OR `cat <<< x > .env` is allowed (redirect outside the here-string operand — must block).
- **Enforcement**: CI test assertion (hook-integration)
- **Guards against**: AP-040
- **Rationale**: an agent writing via `python -c "open('.env','w')"` is a perimeter threat the guardrail cannot and does not defend against (decision 3.1; accepted non-goal — see STRIDE Tampering). `perl -i` is NOT opaque (it is a writer — INV-003); only `perl -e/-pe/-ne` without `-i` is opaque (RS-001).

### INV-006: Sink devices are excluded from extraction
- **Type**: must-not
- **Category**: functional
- **Statement**: `/dev/null`, `/dev/stdout`, `/dev/stderr`, and `/dev/fd/*` MUST NOT be emitted as write targets even when they are redirect destinations.
- **Violated when**: `cmd > /dev/null`, `cmd 2>/dev/null`, or `cmd >/dev/fd/3` emits the device path.
- **Enforcement**: CI test assertion (hook-integration)
- **Guards against**: null

### INV-007: Ambiguity fails open (guardrail posture) — structurally guaranteed
- **Type**: must
- **Category**: security
- **Statement**: Extraction is **destination-driven**: a token is emitted ONLY by the redirect branch (INV-002) or the writer-command branch (INV-003). Any command not matching those forms — including unresolvable/dynamic destinations (`bash -c "$dynamic"`, `echo x > "${f}"`, a trailing bare `>` with no following token) and the accepted-fail-open exotic forms (INV-002/003) — yields the empty set (allow). The extractor never blocks on uncertainty. **The structural property (no unconditional token-emit branch — PRH-001) is the proof that this holds for all inputs; the ambiguity corpus is a witness set, not a proof.** This is the deliberate, reviewable loosening of PAT-001 clause-5 for the *extraction* path — narrowed to extraction ambiguity only (INV-008 is the boundary), and documented in `.claude/rules/hooks-pretooluse.md` (INV-013).
- **Violated when**: a command with write-ish syntax but no resolvable destination is blocked, OR (structural) the extractor contains a path that emits a token outside the redirect/writer branches.
- **Enforcement**: CI test assertion (witness corpus) + structural test (PRH-001) + the `.claude/rules/hooks-pretooluse.md` carve-out (INV-013)
- **Guards against**: AP-040

### INV-008: Hook-input parse failure still fails closed
- **Type**: must
- **Category**: security
- **Statement**: A malformed or unparsable stdin JSON envelope (the hook's own input contract) MUST still exit 2 (fail-closed), unchanged from current behavior. INV-007's fail-open applies ONLY to write-destination ambiguity *within a successfully-parsed Bash command* — never to a failure to parse the hook's input. A JSON-valid envelope whose `tool_input.command` is unparsable-as-shell is INV-007 regime (allow), proving the boundary sits at the JSON layer, not the shell layer.
- **Violated when**: malformed stdin JSON exits 0.
- **Enforcement**: CI test assertion (preserves PAT-001 clause 5 for the input contract)
- **Guards against**: null

### INV-009: Edit/Write/MultiEdit target blocking is unchanged
- **Type**: must
- **Category**: functional
- **Statement**: For `Edit`, `Write`, `MultiEdit`, `NotebookEdit`, `CreateFile`, the `tool_input.file_path` (and MultiEdit edits[].file_path) IS the write target and MUST continue to be matched against patterns exactly as today. This feature changes only the Bash extraction path.
- **Violated when**: an `Edit` to `.env` is allowed after this change.
- **Enforcement**: CI test assertion (existing Edit/Write test corpus must still pass — PRH-003)
- **Guards against**: AP-022 (the guard must still fire on real writes — not become dead code)

### INV-010: Canonical-form matching is preserved
- **Type**: must
- **Category**: security
- **Statement**: Every emitted write target MUST still pass through `canonicalize_path` before matching, and matching MUST still compare canonical target against canonical patterns (PRH-004 / PAT-017). The re-scope changes *what* is extracted, never the canonicalization or the matcher. A newly-rewritten writer-command destination in traversal-encoded form (e.g. `cp x subdir/../.env`) MUST still block.
- **Violated when**: an emitted target is compared raw, or `canonicalize_path` is bypassed (canonicalization-mismatch bypass class returns).
- **Enforcement**: structural test `test_inv005_canonical_only_at_matcher` (call-site adjacency) stays GREEN + behavioral `test_inv008_canonical_pattern_matching` stays GREEN + ≥1 new traversal-encoded writer-destination fixture
- **Guards against**: null

### INV-011: `_has_write_pattern` and workflow-gate are unaffected
- **Type**: must-not
- **Category**: functional
- **Statement**: This feature MUST NOT modify `_has_write_pattern` or `get_target_file` in `scripts/lib.sh`, and MUST NOT change `workflow-gate.sh` behavior.
- **Violated when**: the `_has_write_pattern` or `get_target_file` function bodies change (golden-hash mismatch), or `tests/test-workflow-gate.sh` fails.
- **Enforcement**: golden-hash assertion on the awk-extracted `_has_write_pattern` and `get_target_file` function bodies (robust where a path-grep over a squash-merged diff is not — RS-017) + `tests/test-workflow-gate.sh` unchanged-pass
- **Guards against**: null

### INV-012: SFG documentation describes a guardrail, not a perimeter (doc coherence)
- **Type**: must
- **Category**: documentation
- **Statement**: After this feature, no `.correctless/ARCHITECTURE.md` entry, `CLAUDE.md` convention, `AGENT_CONTEXT.md` row, `README.md` section, or `docs/skills/*` page may assert that SFG structurally blocks interpreter-mediated or git-mediated out-of-band writes, or frame SFG as "Secret protection"/"perimeter"/"fail-closed (on everything)" (CX-003 adds README.md + docs/skills/* to the grep corpus). **The sweep covers EVERY SFG reference in the corpus, not only the named ABS entries (CX-014)** — generic claims like "prevents LLM writes" (ARCHITECTURE.md ~L22) and "Protected by sensitive-file-guard" (~L202) are in scope. Generic "protects"/"prevents" language is permitted ONLY when it does not assert perimeter / structural-impossibility / interpreter-git coverage — i.e. it must be read as tool-target + direct-write guardrail behavior. Where ambiguous, the entry must be scoped explicitly (e.g. "guards Edit/Write and direct redirect writes"). The SFG enforcement clause of ABS-029/030/035/038/040/041/042 MUST be scoped to "tool-target + direct redirect/writer-command destinations; interpreter/git-mediated out-of-band writes are accepted non-goals (AP-040)". A new ABS entry MUST capture the guardrail capability boundary as the single authoritative target; consuming entries See-link it. **ABS-030 is the most exposed** — SFG redirect-block was its only structural leg (no `cmd_*` gate backs the autonomous-decisions JSONL); its clause MUST be scoped down explicitly (or its R-013 JSONL-growth check elevated to the structural leg).
- **Violated when**: any consuming entry still claims SFG perimeter/structural coverage of interpreter/git writes after merge.
- **Enforcement**: CI test assertion (grep the ARCHITECTURE.md / CLAUDE.md / AGENT_CONTEXT.md / README.md / docs/skills/* corpus for SFG + perimeter language) — single grep corpus shared with PRH-002 (CX-003 enforcement now matches the CX-003 statement)
- **Guards against**: AP-040 (regenerating one layer up)

### INV-013: PAT-001 clause-5 carve-out is documented in the rule file
- **Type**: must
- **Category**: security / documentation
- **Statement**: `.claude/rules/hooks-pretooluse.md` MUST document the clause-5 carve-out: the SFG *extraction* path fails OPEN on write-destination ambiguity (INV-007), while the *input-parse* path (INV-008) and all OTHER PreToolUse hooks retain strict fail-closed. The carve-out cites PMB-020 / AP-040 and the date. Without this the shipped hook contradicts its own governing rule file (which loads into editing context whenever an agent opens the hook), making the loosening silent rather than "loud and reviewable".
- **Violated when**: the hook ships fail-open extraction while the rule file still states "no carve-outs, no environment-gated exceptions" with no documented exception.
- **Enforcement**: CI test assertion (rule file contains the carve-out subsection referencing INV-007/INV-008 and PMB-020)
- **Guards against**: null

### INV-014: The BLOCKED message reflects the guardrail framing
- **Type**: must
- **Category**: UX
- **Statement**: The hook's BLOCKED message MUST describe a genuine write to a protected file and point to the sanctioned recovery path. It MUST NOT suggest "add an exclusion to `custom_patterns` if this file is not actually sensitive" for a DEFAULTS entry (no allowlist primitive exists for DEFAULTS — PMB-017). For a deliverable edit it points to `.claude/rules/sfg-deliverable.md` (lift-and-restore).
- **Violated when**: the message still tells the user a real-write block "might not be sensitive — exclude it via custom_patterns".
- **Enforcement**: CI test assertion (block-message content check)
- **Guards against**: AP-040 (encoding the abolished perimeter mental model in the user-facing string)

### INV-015: The re-scope is announced at upgrade time
- **Type**: must
- **Category**: UX / upgrade
- **Statement**: A user-visible signal (a `CHANGELOG.md` entry) MUST announce that SFG was re-scoped to write-targets-only and some previously-blocked Bash reads/invocations are now allowed. "Strictly more permissive ⇒ no signal needed" is a false inference for a guardrail users reason about; PAT-001's "loud and reviewable" applies at upgrade time, not just spec time. (The setup UX-004 advisory counts DEFAULTS-line delta = 0 here, so it will not fire — the CHANGELOG entry is the signal.)
- **Violated when**: the feature merges with no changelog/release note about the behavior change.
- **Enforcement**: review-time + CHANGELOG entry present
- **Guards against**: silent-loosening-between-versions

### INV-016: Pre-filter firing-set is a superset of the extractor emit-set
- **Type**: must
- **Category**: security (implementation-pinning, PMB-013 class)
- **Statement**: The hook invokes `_extract_bash_targets` ONLY after `_has_write_pattern` returns 0 (hook L87). Therefore every command form INV-002/INV-003 require to be **blocked** MUST first be in `_has_write_pattern`'s firing set (`firing-set ⊇ emit-set`). This is an implementation-level invariant the spec pins explicitly (not a semantic one) — per PMB-013, a semantic invariant without implementation-level pinning leaks through every phase. Every redirect operator in INV-002 (including `>|`, `&>`, glued forms) and every writer command in INV-003 MUST be verified to actually fire `_has_write_pattern` (the `&>` coverage of the lib.sh L472 regex is suspect and must be tested).
- **Violated when**: a hook-integration test feeds an INV-002/003 must-block form and the hook exits 0 because `_has_write_pattern` returned 1 before extraction ran.
- **Enforcement**: CI test assertion (hook-integration — the INV-002/003 block corpus driven through the full hook, which exercises the pre-filter)
- **Guards against**: AP-022 (a must-block form silently skipped by the pre-filter)

### INV-017: Permissive monotonicity is witnessed in both directions
- **Type**: must
- **Category**: functional (replaces the "strictly more permissive" theorem)
- **Statement**: The change is a re-targeting, not a strict relaxation (see Complexity Budget). Two witness corpora pin both regression directions:
  - **Half-A (newly-allowed)**: the 6 real 2026-06-19 `/cchores` dogfood false-blocks plus the 9 from the 2026-06-24 /creview-spec session, sourced per the AP-031 real-fixture convention (`# Source:` citation), each → exit 0. This proves the friction is gone and catches a positional misparse that would newly block a legitimate op.
  - **Half-B (still-blocked)**: the full INV-002/INV-003 write corpus → exit 2. If any Half-B fixture flips to exit 0, the re-targeting broke a real guard. Monotonicity is witnessed by Half-B staying GREEN; it is NOT provable in general.
- **Violated when**: a Half-A command blocks, or a Half-B command allows.
- **Enforcement**: CI test assertion (both corpora, hook-integration)
- **Guards against**: AP-040 (friction return) + AP-022 (silent guard breakage)

### INV-018: Protected DEFAULTS paths still block as Bash redirect/writer destinations
- **Type**: must
- **Category**: security
- **Statement**: Each DEFAULTS **pattern class** — full-path literal (`scripts/lib.sh`), basename literal (`credentials.json`), and glob (`*.pem`, `.env.*`, `id_rsa.*`) — when materialized as a concrete `>`/`>>`/`tee`/`cp`/`mv`/`sed -i` destination, MUST still exit 2. INV-009 covers only the Edit/Write tool-target path; the actual sole-writer enforcement surface for ABS-029/030/038/040 is the Bash redirect/writer-command path, and this invariant re-asserts it survives the rewrite. (CX-005: the statement is aligned with its sampling enforcement — "representative coverage across pattern classes", not literally "every path" — and a structural check asserts no DEFAULTS pattern class is left uncovered, so a new class can't silently escape the corpus.)
- **Violated when**: `echo x >> .correctless/meta/harness-fingerprint.json` (full-path), `tee credentials.json` (basename), or `cp x secret.pem` (glob) is allowed; OR a DEFAULTS pattern class has no representative fixture.
- **Enforcement**: CI test assertion (hook-integration — one representative concrete destination per DEFAULTS pattern class, across redirect + writer forms) + a structural test that every DEFAULTS pattern class maps to ≥1 fixture
- **Guards against**: AP-022 (dead-code-in-security-paths for the sole-writer contracts)

### INV-019: The hook sets LC_ALL=C at hook scope (enforced, not just assumed)
- **Type**: must
- **Category**: security (determinism)
- **Statement**: `sensitive-file-guard.sh` MUST set `LC_ALL=C` at hook scope (alongside `set -euo pipefail` / `set -f`, hook L18-21), so the extractor's tokenization, `${,,}` lowercasing (L331), and `[[ =~ ]]`/`case` matching (L193) are byte-oriented and locale-independent. EA-004 stated this as an assumption; this invariant makes it a tested MUST (CX-004) — extraction happens BEFORE `canonicalize_path`'s internal `LC_ALL=C`, so the hook-scope setting is what makes block decisions reproducible across the agent's locale.
- **Violated when**: the hook has no hook-scope `LC_ALL=C`, OR a fixture with a non-ASCII destination produces a locale-dependent block/allow decision.
- **Enforcement**: structural test (grep the hook for `LC_ALL=C` at hook scope, before `collect_targets`) is the PRIMARY, always-runs assertion. The behavioral cross-locale fixture **discovers** an available UTF-8 locale at runtime (`locale -a | grep -iE 'utf-?8'`, accepting any spelling — `en_US.utf8`, `C.UTF-8`, etc.) and asserts the same exit code under it as under `LC_ALL=C`; if `locale -a` lists no UTF-8 locale (minimal CI images), the behavioral portion **SKIPs with an explicit message** (never hard-codes `en_US.UTF-8`, never fails on its absence — CX-010).
- **Guards against**: non-reproducible (locale-dependent) block decisions

### INV-020: Positional writer detection operates per command-segment
- **Type**: must
- **Category**: functional (implementation-pinning, PMB-013 class)
- **Statement**: Before applying **any** INV-003 writer-command argument logic — `cp`/`mv`/`install`/`ln` final-arg, **`tee` all-args, `sed -i`/`perl -i` operand, `truncate` operand**, and `dd of=` scan — the extractor MUST segment the command on unquoted command separators — `;`, `|` (but not `||`-internal), `&&`, `||`, and a **bare background `&`** — so a writer's destination is computed **within its own segment** and never crosses a separator. (CX-011: segmentation applies to the full INV-003 writer set, not just the positional cp/mv subset — every arg-scanning branch can otherwise overrun the erased `;`/`|`/`&` boundaries.) The current boundary-erasing IFS (`;|&()`, hook L153) destroys these boundaries, so positional logic over the flat token array is wrong in BOTH directions (CX-001): a cross-segment read becomes a false destination, and a real destination becomes a missed read.
  **Redirect/separator disambiguation (CX-007)**: the segmenter MUST NOT treat an `&` that is part of a redirect operator (`&>`, `&>|`, `>&`, or glued `cmd&>file`) as a segment boundary — only a bare background `&` (and `&&`) is a separator. An `&` immediately followed by `>`, or a `>` immediately followed by `&`, is a redirect, not a split point. Redirect detection (INV-002) is token-local and runs independently; the segmentation serves positional writer detection only and MUST NOT break redirect extraction.
- **Violated when**: `cp src dest; cat .env` blocks (cross-segment false emit); `cp src .env; echo ok` allows (missed write); `tee out; cat .env` blocks (tee branch overruns the `;`); `tee .env; echo ok` allows (missed); `truncate -s0 out; cat .env` blocks (truncate overruns); `echo x &> .env` allows (the `&>` redirect was split on `&` and lost); or `echo x&>.env` (glued) allows.
- **Enforcement**: CI test assertion (hook-integration) — the compound-command fixtures across the writer set: `cp src dest; cat .env` (allow), `cp src .env; echo ok` (block), `tee out; cat .env` (allow), `tee .env; echo ok` (block), `truncate -s0 out; cat .env` (allow), `mv a b | tee .env` (block via tee; `b` not wrongly emitted), AND `echo x &> .env` + `echo x&>.env` (both block — `&>` survives segmentation as a redirect)
- **Guards against**: AP-040 (false block) + AP-022 (missed real write)

## Prohibitions

### PRH-001: Never reintroduce extract-every-token (behavior-primary, grep-as-tripwire)
- **Statement**: The `*) _strip_quotes "$tok"` default branch that emits every non-flag token MUST NOT exist in the rewritten `_extract_bash_targets`. Extraction is destination-driven (allowlist of write forms), never token-driven.
- **Detection (behavior is the proof)**: the read/invocation/restore/no-new-block corpora (INV-001, INV-017 Half-A) assert exit 0 — if an unconditional token-emit branch existed, those commands would over-extract and block. **The structural grep is a labeled TRIPWIRE only**, not the proof: extract the `case "$tok"` block and assert its `*)` arm (if any) contains no emit of `$tok` (only `;;`/`:`/comments). Per PMB-016/AP-036, structural greps over code are tripwires, never contracts (resolves OQ-003 toward behavior-primary).
- **Consequence**: the over-extraction friction (AP-040) returns.

### PRH-002: Never weaken the guardrail framing back to perimeter (mechanical tripwire)
- **Statement**: SFG documentation, comments, and any future spec touching it MUST describe it as a guardrail/speedbump for accidental and naively-injected writes — never as a security boundary, "structurally impossible," or injection containment.
- **Detection (mechanical)**: a structural test greps the hook header/comments AND the `.correctless/ARCHITECTURE.md`/`CLAUDE.md`/`AGENT_CONTEXT.md`/`README.md`/`docs/skills/*` SFG clauses for re-introduced perimeter language (`structurally impossible`, `prevent injection`, `Secret protection`, `Category: security` on the redirect/extraction path) tied to SFG. This converts PRH-002 from prompt-level/review-time (PAT-018 violation) to a CI assertion, mirroring the PRH-001 tripwire (RS-018). The /cspec Step 0 + /creview-spec mechanism-capability lens remain the review-time backstop.
- **Consequence**: AP-040 recurs (the premise regenerates the over-extraction).

### PRH-003: Never allow a previously-blocked Edit/Write target
- **Statement**: The change must not make any Edit/Write/MultiEdit target previously blocked now pass. The Bash extraction re-scope must not leak into the tool-target path.
- **Detection**: the full existing `tests/test-sensitive-file-guard.sh` Edit/Write corpus must pass unchanged (this is the MUST-PASS-UNCHANGED set — distinct from the Bash corpus migration below).
- **Consequence**: a genuine accidental file edit escapes the guardrail.

## Test Corpus Migration (RS-004)

The existing `tests/test-sensitive-file-guard.sh` contains ~40 **Bash** assertions that must INVERT or be rewritten. PRH-003's "existing tests pass unchanged" applies to the **Edit/Write tool-path only** — NOT the Bash corpus. The RED/GREEN phases have explicit spec authority to change these:

- **MUST-INVERT** — `test_inv013_interpreter_chains_blocked` (L1468, ~19 assertions): every `bash -c`/`python -c`/`node -e`/`perl -e`/`/usr/bin/env python3 -c` row flips from exit 2 → exit 0 (INV-005).
- **MUST-SPLIT** — `test_inv006_over_extract_blocks_bypasses` (L1300): eval-payload rows (`perl -e "system(q{cat > .env})"`, `bash -c "…"`) flip to exit 0 (INV-005); `perl -i … .env` rows STAY exit 2 (INV-003). Do not delete wholesale.
- **MUST-REWRITE** — `test_inv006a_disallowed_branches_enumerated` (L1342): currently bans `cp)`/`mv)`/`tee)`/`sed)`/`perl)` case branches; INV-003 now REQUIRES those branches. Replace the ban with the PRH-001 behavior-primary corpus + the labeled `*)`-arm tripwire.
- **MUST-PASS-UNCHANGED** — all Edit/Write tests, `test_da003_fail_closed_on_jq_failure` (L1014, INV-008), `test_inv005_canonical_only_at_matcher` (L1166, INV-010), `test_inv008_canonical_pattern_matching` (L1437, INV-010).
- **RS-016 decision** — `cp .env backup` ALLOWS post-rescope (source read; SFG is a write guard, not an egress guard — `redact-secrets.sh` owns egress). The existing `test_inv002`/`test_bnd004` assertion that `cp .env backup.txt` → exit 2 (because `.env` is the *source*) MUST be inverted to exit 0. Document the decision in the test.

## Boundary Conditions

### BND-001: Untrusted Bash command → write-target extraction
- **Boundary**: TB-001 (agent-proposed command string → file write)
- **Input from**: the agent's proposed `tool_input.command` (untrusted, may be injection-influenced)
- **Validation required**: identify write destinations by allowlisted write *forms* (redirects, writer commands); treat everything else as non-destination.
- **Failure mode**: fail-open on extraction ambiguity (INV-007); fail-closed on hook-input parse failure (INV-008).

## STRIDE Analysis (TB-001: agent-proposed command → file write)

This section is the mechanism-capability honesty record (PMB-020). The enforcement layer is a cooperative-loop PreToolUse hook = **guardrail**, not perimeter.

- **Spoofing** — N/A (no identity assertion at this boundary).
- **Tampering (write to a protected file)** — *Partially* mitigated, by design. The guardrail catches the **accidental / naive** write: a direct redirect (`> .env`, `>| .env`, glued `2>.env`), a `cp`/`mv`/`tee`/`sed -i`/`perl -i`/`dd of=`/`truncate` to a protected path, an `Edit`/`Write` tool call. It does **NOT** mitigate the **deliberate/obfuscated** write: `bash -c`, `python -c`, base64-decoded paths, `git` restores, `cp -t`/`install -d` flag-relocation, or naming the directory instead of the file. These are explicit accepted non-goals (INV-004, INV-005, INV-002/003 fail-open gaps) — a PreToolUse hook structurally cannot stop them, and pretending otherwise is the AP-040 error.
- **Repudiation** — out of scope (audit-trail.sh covers logging).
- **Information disclosure** — out of scope for SFG; `redact-secrets.sh` is the egress mechanism. (Hence RS-016: a protected file as a *source* read is not SFG's concern.)
- **Denial of service** — the prior over-extraction was a self-inflicted *availability* DoS on the developing agent (6+9 false blocks across two sessions). This feature removes it.
- **Elevation of privilege** — N/A.

**Capability statement**: SFG after this change defends against accidental and naive out-of-band writes to a known protected-file list, via the Edit/Write tool path and the direct redirect/writer-command Bash path. It does not, and cannot, defend against a motivated agent or a crafted injection that intends to write a protected file. **Fail-open residual asymmetry (RS-015)**: this residual is *light* for the credential subset of DEFAULTS (`.env`/`*.pem` — the agent never writes them) but *heavier* for the autonomously-written `.correctless/` state-file subset (workflow-state, baselines, decision records), where a silent accidental clobber corrupts a sole-writer's downstream consumer (the PMB-005/011/016 class). That heavier residual is accepted and owned here for the state-file subset, not papered over.

## Environment Assumptions
- **EA-001**: Bash word-splitting with `set -f` (no glob expansion) recovers *tokens* but NOT *argument roles*. Destination detection for the common writer commands is handled via per-command positional/flag logic the extractor encodes explicitly; IFS-splitting alone is insufficient. **Positional writer detection requires command-segment boundaries that the current boundary-erasing IFS (`;|&()`) destroys — so the extractor MUST segment on unquoted `;`/`|`/`&&`/`||`/`&` BEFORE applying positional logic (INV-020), rather than relying on the flat token array.** Forms that pure word-splitting still cannot recover — `cp -t`/`install -t`/`install -d` (flag-relocated/pluralized destinations), `ln` one-arg, and destinations containing IFS bytes (spaces) — fail OPEN per INV-007 and are accepted non-goals. Consequence if wrong on the *handled* forms: a write form is wrongly tokenized; mitigated by fail-open on the permissive side and by INV-002/003/017/018/020 fixtures on the blocking side.
- **EA-002**: `canonicalize_path` (PAT-017) remains the sole normalizer and is unchanged — consequence if wrong: canonicalization-mismatch bypass (out of scope here; preserved by INV-010). Matching is **lexical** (canonicalize_path cannot follow symlinks — PAT-020); a write through a symlink/hardlink to a protected file is not detected — accepted per the guardrail non-goal (RS-024).
- **EA-003**: `_has_write_pattern` (frozen, INV-011) still fires on the pervasive `2>/dev/null` idiom and bare interpreter use, so every such command pays the full source-lib + sentinel-probe + tokenize + extract path before returning empty. The per-invocation cost is accepted; no false block results (RS-022). The fail-open direction (INV-007) means a hypothetical extraction bug here fails *permissive* and silent — caught only by the INV-017 corpora.
- **EA-004 (locale)**: the extractor, `${,,}` lowercasing, and all `[[ =~ ]]`/`case` matching in `sensitive-file-guard.sh` assume byte-oriented (`LC_ALL=C`) semantics for determinism. **Promoted to a tested MUST in INV-019 (CX-004)** — extraction happens BEFORE `canonicalize_path`'s internal `LC_ALL=C`, in whatever locale the agent's env carries. Consequence if wrong: tokenization/lowercasing/regex matching of non-ASCII destinations varies with the agent's locale, making block decisions non-reproducible (RS-013).
- **EA-005 (bash floor)**: `sensitive-file-guard.sh` requires bash ≥ 4.0 (`${var,,}`, `local -a` slicing, `[[ =~ ]]`/`BASH_REMATCH`, here-strings, process substitution). macOS default bash 3.2 is unsupported (`${ALL_PATTERNS,,}` is a syntax error → abort under `set -e`). The hook's internal *use* of `<<<` is a separate concern from INV-005's treatment of `<<<` as an opaque *input* to ignore — they must not be conflated (RS-014).

## Design Decisions
- **DD-1 (blast radius)**: SFG-local rewrite of `_extract_bash_targets` only; shared `_has_write_pattern` untouched (chosen 1.1).
- **DD-2 (write-destination set)**: redirects (incl. `>|`, glued forms, minus sink devices) + `tee`/`cp`/`mv`/`install`/`ln`/`sed -i`/`perl -i`/`dd of=`/`truncate` destinations; exotic flag-relocated forms fail open (chosen 2.1 + 2026-06-24 "common naive forms, fail-open exotic").
- **DD-3 (git + interpreter chains)**: git working-tree commands allowed; interpreter+eval operands opaque/allowed; `perl -i` is a writer not opaque (chosen 3.1 + RS-001).
- **DD-4 (ambiguity posture)**: fail-open on extraction ambiguity, structurally guaranteed by destination-driven extraction; fail-closed retained only for hook-input parse failure (chosen 4.1).
- **DD-5 (doc scope)**: documentation-coherence sweep folded into this feature (chosen 2026-06-24).
- **DD-6 (OQ-001)**: `truncate` included as a writer; `rm`/`shred`/`chmod`/`chown` excluded (chosen 2026-06-24).
- **DD-7 (RS-016)**: `cp <protected> <dest>` source-read ALLOWS — SFG is a write guard, not an egress guard (chosen 2026-06-24).

## Open Questions
- ~~**OQ-002**~~: **RESOLVED 2026-06-24 (CX-009)** — `tee` destinations = every non-`-`-leading arg; `--` and `--output-error=…` are skipped as flags so `tee -- .env` / `tee --output-error=warn .env` BLOCK; dash-leading filenames after `--` fail open. See INV-003.
- **OQ-004**: Is the Edit/Write-to-deliverable lift-and-restore ceremony (out of scope here, RS-012) the *real* friction users feel, such that a Bash-only re-scope under-delivers on the "remove friction" headline? Track for a possible follow-up that extends the guardrail framing to the Edit/Write deliverable path (interacts with AP-037 / #196).
