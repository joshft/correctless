# Spec: Harness-Fingerprint R2 Hardening

## Metadata
- **Created**: 2026-04-27
- **Status**: draft (post-/creview-spec amendments applied 2026-04-27)
- **Impacts**: harness-fingerprint (supersedes INV-018 testability surface for `--version`), sensitive-file-protection (refactors `_extract_bash_targets` and adds canonicalize_path normalizer), workflow-gate (consumes shared `_has_write_pattern` extended by INV-013 — see Finding #2 amendment)
- **Branch**: audit/harness-fingerprint
- **Research**: null (problem space well-understood from R2 audit transcripts; no external library guidance needed)
- **Recommended-intensity**: high
- **Intensity**: high
- **Intensity reason**: file path signal (hooks/sensitive-file-guard.sh, scripts/harness-fingerprint.sh — both security-critical), keyword signal (auth, security, bypass, fail-closed), antipattern overlap (AP-019 fail-open fallback, AP-022 dead code in security paths, AP-024 hardcoded enumeration)
- **Override**: none
- **Review amendments**: 15 BLOCKING findings accepted from `/creview-spec` (artifact: `.correctless/artifacts/review-spec-findings-harness-fingerprint-r2-hardening.md`). 1 HIGH finding deferred to follow-up spec (Finding #9 — `--session-id`/`--meta-dir` sentinel-prefix gating; same threat class as AUTH-R2-001 but warrants deliberate scoping, not bolt-on). MEDIUM/LOW findings deferred to `/cverify` for post-implementation re-evaluation.

## Context

Three architectural redesigns rolled into one feature, all driven by the R2 audit of the harness-fingerprint R1 fix batch (which had a 71% defect rate). The R2 round caught ~32 unique findings across 8 specialist agents. Rather than iterate on the R1 patches (the failure mode PMB-002 documented), we are reconstructing the three load-bearing pieces from a cleaner architectural base, with the R2 findings as input.

The unifying principle: **close the bug *class*, not the instances.** Each of the three pieces had instance-level fixes in R1 that the next R2 specialist round routed around. Class-level invariants (verified by property-based testing where applicable, by structural greps where possible, and by integration where neither suffices) close the round-on-round leakage that made the R1 batch wasteful.

## Scope

### In scope

1. **`canonicalize_path` in `scripts/lib.sh`** — a new pure-bash function. Pure-bash segment-stack walker. No external commands. Total over arbitrary byte sequences. Glob characters pass through as literal bytes. Operates on bytes only (`LC_ALL=C` enforcement per EA-004). Used by `hooks/sensitive-file-guard.sh` to normalize paths before pattern matching.

2. **`hooks/sensitive-file-guard.sh` refactor** — delete the per-command dispatch in `_extract_bash_targets`; over-extract every non-flag token when `_has_write_pattern` flags a write. Extend `_has_write_pattern` to flag interpreter chains (`bash -c`, `perl -e`, `python -c`, `/usr/bin/env perl`, etc.) so the bypass class R2 enumerated cannot recur. Pipe every target and every protected pattern through `canonicalize_path` before reaching `_check_file_against_patterns`. The matcher sees only canonical forms.

3. **`scripts/harness-fingerprint.sh` `--version` removal** — strip the `--version` flag and the `VERSION_OVERRIDE` variable from the shipped script. Leave `HARNESS_VERSION=N` as the only production input. Test-side injection moves to a `tests/harness-fingerprint-test-helpers.sh` helper (`make_test_harness_script`) that copies the script to a tmpdir under `$WORK_BASE`, substitutes the constant via `sed`, and writes to a destination filename `harness-fp-test-${BASHPID}.sh` (NOT under `scripts/` — the destination must not match the protected pattern). `tests/test-harness-fingerprint.sh` sources the new helper file. The other two testability flags (`--meta-dir`, `--session-id`) stay for now — see "Deferred follow-up" below.

4. **New rule file `.claude/rules/canonicalize-path.md`** — applies the path-scoped rule loading mechanism (ABS-009) to scripts/lib.sh. Body documents the canonicalize_path security invariants (INV-001 through INV-004) so any agent editing lib.sh sees them in context. Paths frontmatter: `[scripts/lib.sh]`. This is a Feature B usage of ABS-009 (PAT-001 was the first dogfood; this is the second).

5. **Setup upgrade-detection (INV-014)** — `setup` greps the existing `scripts/harness-fingerprint.sh` for `VERSION_OVERRIDE` before installation. If found (pre-R2 install), force-reinstall the script with a clear log line referencing INV-009/PRH-003. This closes the upgrade-path break Finding #7 surfaced.

### Out of scope

- The remaining R2 findings on M-1 (chmod), M-5 (schema migration), M-9 (jq idiom), M-10 (artifacts_dir), H-1 (MODEL sanitization corruption), H-4 (stale flag), H-6 (dup flag), L-2/L-3/L-5 cleanup. These will be addressed in separate, smaller commits after this redesign lands and the R2 architectural decisions are settled.
- Any change to `audit-trail.sh`, `auto-format.sh`, or `token-tracking.sh`. (Note: `workflow-gate.sh` IS implicitly in scope as a *consumer* of the extended `_has_write_pattern` per Finding #2 — but we make no functional change to workflow-gate.sh itself; the regression-test addition lives in tests/test-workflow-gate.sh.)
- Any change to skill files (no `allowed-tools` updates required for this feature — see Step 5a check below).
- Any change to ABS-027 (harness fingerprint store contract). The store schema and writer enforcement remain as-is.

### Deferred follow-up (NOT in this spec)

- **`--session-id` and `--meta-dir` sentinel-prefix gating** (Finding #9 from /creview-spec). Same threat class as AUTH-R2-001: a caller can pass `--session-id "valid_session_already_seen"` to suppress the version_bumped notification dedup. The eventual fix is the same pattern as `--version` removal (strip from production, test via tmpdir+sed) but applied to two more flags. This requires deliberate scoping work — not a bolt-on review-finding amendment. Tracked as a follow-up spec to land after this one.

## Complexity Budget

- **Estimated LOC**: ~330 (canonicalize_path ~80, sensitive-file-guard refactor ~100, harness-fingerprint.sh strip ~20, harness-fingerprint-test-helpers.sh ~30, test migration ~60, setup upgrade-detection ~15, .claude/rules/canonicalize-path.md ~25)
- **Files touched**: 10 (scripts/lib.sh, hooks/sensitive-file-guard.sh, scripts/harness-fingerprint.sh, tests/harness-fingerprint-test-helpers.sh [new], tests/test-canonicalize-path.sh [new], tests/test-harness-fingerprint.sh, tests/test-workflow-gate.sh [INV-013a regression test], tests/test-architecture-drift.sh [paths: list update for new rule file], setup, .claude/rules/canonicalize-path.md [new])
- **New abstractions**: 2 (canonicalize_path as a lib.sh function — not a new ABS-xxx since lib.sh is covered by ABS-001; the new rule file is a Feature B usage of ABS-009 — not a new ABS itself)
- **Trust boundaries touched**: PreToolUse fail-closed posture (PAT-001 / `.claude/rules/hooks-pretooluse.md`), HARNESS_VERSION protection (PRH-006 in original harness-fingerprint spec), and a new canonicalize_path security boundary (governed by the new `.claude/rules/canonicalize-path.md`)
- **Risk surface delta**: medium-high. Two of three pieces directly affect the security posture of a fail-closed hook. Mitigation: every invariant below has a structural or property-based test with a named target test file/function/grep pattern (see "Structural Test Map" appendix); the migration sequence (INV-011) is designed to fail loudly rather than silently degrade; setup has a documented upgrade-detection step (INV-014) to prevent the lib.sh ↔ guard upgrade-dependency break.

## Invariants

### INV-001: canonicalize_path is total over arbitrary byte sequences
- **Type**: must
- **Category**: functional
- **Statement**: For any input string (including empty, whitespace-only, glob-character-containing, traversal-sequence-containing), `canonicalize_path` produces a single line of stdout and returns exit code 0 within the performance bound (INV-012). The function never hangs, never errors, never produces multi-line output.
- **Boundary**: refs PAT-001 (PreToolUse hook fail-closed posture)
- **Violated when**: any input causes canonicalize_path to hang past the 2s test-fixture timeout, exit non-zero, or emit multi-line output
- **Guards against**: AP-022-class (dead-code-in-security-paths) by ensuring the function cannot fail silently and produce no output that the matcher would treat as "no match"
- **Test approach**: property-based — fuzz corpus with the following pinned characteristics (per Finding #5 amendment): (a) seed `RANDOM=42`, (b) corpus size 1000 inputs, (c) length distribution uniform over `[0, 1024]` bytes, (d) byte alphabet membership requirement: each of `*`, `?`, `[`, `]`, `/`, `.`, ` `, `\t`, `\n`, `$`, `` ` ``, `(`, `{` MUST appear in at least 50 inputs (10% threshold), (e) on failure, hex-dump the failing input via `xxd` and include in the test failure message for replay. Each invocation under a 2s timeout; assert exit 0 + single-line stdout. Target test: `tests/test-canonicalize-path.sh` `test_inv001_totality`.
- **Risk**: critical
- **Implemented in**: scripts/lib.sh (filled during GREEN)

### INV-001a: canonicalize_path empty-output-on-non-empty-input fails closed
- **Type**: must-not
- **Category**: security
- **Statement**: For any non-empty, non-whitespace-only input, `canonicalize_path` MUST NOT emit empty stdout while returning exit code 0. Empty output on non-empty input is a failure mode that bypasses the matcher (the matcher would receive an empty target string and skip pattern comparison). The function's contract: non-empty input → non-empty output; empty/whitespace-only input → output equals `.` (the canonical empty-relative form, also non-empty).
- **Boundary**: refs PAT-001 (HP-3: PreToolUse fail-open via clause-5 violation pattern, 7+ PRs / 4 days persistence in QA-R1-005)
- **Violated when**: any non-empty input produces empty stdout AND exit 0; the implementation has any code path that prints nothing for non-empty input
- **Guards against**: HP-3 (the historical pattern of clause-5 fail-open violations) — empty output on non-empty input is the silent variant of the PreToolUse fail-open class
- **Test approach**: property-based — using the same fuzz corpus as INV-001, assert that for every input where `[ -n "$input" ]` after whitespace trim, the output is non-empty. Additionally, structural grep on canonicalize_path body for any code path that writes nothing in a non-error condition. Target test: `tests/test-canonicalize-path.sh` `test_inv001a_no_empty_output_on_nonempty_input`.
- **Risk**: critical

### INV-002: canonicalize_path output contains no `//`, `.` segments, `..` segments (absolute), or trailing `/`
- **Type**: must
- **Category**: functional
- **Statement**: Output never contains `//`, never contains a `.` path segment, never contains a `..` path segment when the input is an absolute path, and never has a trailing `/` (except when the entire output is exactly `/`).
- **Boundary**: refs PAT-001
- **Violated when**: output contains `//`, contains a `/./` sequence, contains a `/..` sequence on absolute-path output, or ends with `/` while not equal to `/`
- **Guards against**: canonicalization mismatch — the bypass class where `subdir/../.env` and `.env` would canonicalize to different forms and slip past pattern matching
- **Test approach**: property-based — same fuzz corpus as INV-001 (with INV-001's pinned seed and characteristics); assert each output against the constraints. Target test: `tests/test-canonicalize-path.sh` `test_inv002_output_shape`.
- **Risk**: critical

### INV-002a: Only ASCII `.` (0x2E) is treated as a path-segment dot
- **Type**: must
- **Category**: security
- **Statement**: `canonicalize_path` treats only the literal byte 0x2E (ASCII `.`) as a path-segment dot for the `.` and `..` recognition. Unicode dot lookalikes — including U+2024 ONE DOT LEADER (UTF-8: `0xE2 0x80 0xA4`), U+FF0E FULLWIDTH FULL STOP (UTF-8: `0xEF 0xBC 0x8E`), and U+2026 HORIZONTAL ELLIPSIS — are treated as ordinary path bytes that pass through the segment stack literally (per INV-004's no-shell-expansion contract). The function operates on bytes only; locale-dependent character semantics are explicitly out of scope (see EA-004).
- **Boundary**: refs PAT-001
- **Violated when**: any non-ASCII byte sequence is treated as a `.` or `..` segment; the function's behavior depends on `LC_*` locale environment variables
- **Guards against**: Unicode-lookalike traversal bypass (Finding #12) — `subdir/U+2024U+2024/.env` would resolve to `subdir/../.env` if non-ASCII dots were honored, then canonicalize differently than `.env` and slip past pattern matching
- **Test approach**: integration — fixture inputs containing each Unicode dot lookalike (U+2024, U+FF0E, U+2026); assert the lookalike survives canonicalization as ordinary bytes (not collapsed). Target test: `tests/test-canonicalize-path.sh` `test_inv002a_ascii_only_dot_recognition`.
- **Risk**: high

### INV-003: canonicalize_path is idempotent
- **Type**: must
- **Category**: functional
- **Statement**: For any input `x`, `canonicalize_path(canonicalize_path(x))` equals `canonicalize_path(x)`.
- **Violated when**: any fuzz input produces different output on the second pass
- **Test approach**: property-based — same fuzz corpus; run canonicalize_path twice; assert equality
- **Risk**: high

### INV-004: canonicalize_path never expands shell metacharacters
- **Type**: must-not
- **Category**: security
- **Statement**: Glob characters (`*`, `?`, `[`, `]`), parameter-expansion sigils (`$`), command-substitution sigils (`` ` ``, `$(`), and brace-expansion sigils (`{`, `}`) appearing in the input pass through to the output as literal bytes. The function never performs pathname expansion, command substitution, parameter expansion, or globbing on the input string. The function never reads filesystem state.
- **Boundary**: refs PAT-001 (no shell expansion inside a fail-closed gate's input handling)
- **Violated when**: an input containing `*` produces output without that `*` (suggesting glob expansion against the cwd); an input containing `$(date)` produces a date string in the output (suggesting command substitution); the function strace-shows any open() against filesystem paths derived from input bytes
- **Guards against**: AP-022 / R2 finding "canonicalize_path glob substitution loses prefix" + "canonicalize_path infinite loop on `[...]/../`"
- **Test approach**: property-based + structural — fuzz with inputs containing every shell metacharacter; assert literal characters survive; structural grep of canonicalize_path body for `eval`, unquoted `$`, command substitution patterns (`$(`, backtick), `glob` invocations, `compgen`, `extglob`
- **Risk**: critical

### INV-005: canonicalize_path is the sole normalizer in the sensitive-file-guard pre-match pipeline [integration]
- **Type**: must
- **Category**: data-integrity
- **Statement**: In `hooks/sensitive-file-guard.sh`, every file target (whether sourced from `tool_input.file_path`, MultiEdit edits, or extracted Bash command targets) and every protected pattern (DEFAULTS literal + `custom_patterns` from config) passes through `canonicalize_path` before reaching `_check_file_against_patterns`. The matcher receives only canonical forms.
- **Boundary**: refs PAT-001
- **Violated when**: any code path in sensitive-file-guard.sh calls `_check_file_against_patterns` with a string that did not pass through `canonicalize_path` first; any direct comparison between a raw target and a raw pattern reappears
- **Guards against**: pipeline-disagreement bypass class (canonicalize-output-differs-from-matcher-expectation)
- **Test approach**: structural (grep) + integration. Structural: target test `tests/test-sensitive-file-guard.sh` `test_inv005_canonical_only_at_matcher`, grep pattern `_check_file_against_patterns` in `hooks/sensitive-file-guard.sh` — every call site's preceding 5 lines must reference `canonicalize_path` (the test scans the file body with `awk` to enforce). Integration: target test `test_inv005_traversal_encoded_blocks`, submits path-traversal-encoded sensitive files (`subdir/../.env`, `./foo/../.env`, `subdir//.env`) via Edit and via Bash redirect and asserts the hook blocks every form.
- **Risk**: critical

### INV-005a: sensitive-file-guard verifies canonicalize_path is defined before use
- **Type**: must
- **Category**: resource-lifecycle
- **Statement**: At source-time, `hooks/sensitive-file-guard.sh` (after sourcing lib.sh) verifies that the `canonicalize_path` function is defined AND that the function's sentinel-version probe returns the expected value. The probe: a hardcoded call `canonicalize_path "__canonicalize_path_v1_probe__/foo"` whose expected output is `__canonicalize_path_v1_probe__/foo` (idempotent on a non-traversal input). If the function is undefined, the probe call errors, or the output differs from the expected value, the guard MUST exit 2 with a clear remediation message: `"BLOCKED [sensitive-file]: canonicalize_path missing or version mismatch — re-run 'bash setup' to refresh installed scripts"`. This closes the lib.sh ↔ guard upgrade-dependency gap surfaced as Finding #14.
- **Boundary**: refs PAT-001 + EA-001 (lib.sh sole-source contract)
- **Violated when**: the guard runs without verifying canonicalize_path is defined; the verification uses a different sentinel that doesn't catch a body-changed-but-still-named-canonicalize_path scenario; the failure message lacks the explicit `bash setup` remediation
- **Guards against**: silent guard breakage on partial upgrade (new guard + old lib.sh = `canonicalize_path: command not found` → set -e exit 2 with cryptic message → user has no idea why every Edit is blocked)
- **Test approach**: integration — fixture that copies new sensitive-file-guard.sh + old lib.sh (without canonicalize_path) to a tmpdir and invokes the guard; assert exit 2 with the exact remediation string in stderr. Target test: `tests/test-sensitive-file-guard.sh` `test_inv005a_canonicalize_version_probe`.
- **Risk**: high

### INV-006: Write-tool extractor over-extracts on every command `_has_write_pattern` flags [integration]
- **Type**: must
- **Category**: security
- **Statement**: When `_has_write_pattern` returns true for a Bash command, `_extract_bash_targets` emits every non-flag token from the command (after strip-quotes), in addition to redirect targets parsed from `>`, `>>`, `1>`, `2>`, `&>`. There is no per-command dispatch — the same uniform extraction logic runs for `cp`, `perl -i`, `php`, `vim -e`, `base64 -d | sh`, `ed`, and any other writer present or future. The extractor's job is to produce candidates; the matcher's job is to filter.
- **Boundary**: refs PAT-001
- **Violated when**: a Bash command containing a sensitive path token is allowed by sensitive-file-guard because `_extract_bash_targets` returned no targets for that command; the per-command `case` dispatch reappears in any form (whether named `cp|mv|rm` or generalized as `case "$tok" in known_writers)`)
- **Guards against**: the entire R2 bypass enumeration — perl (-pi, -ni, -lpi), perl without -i, ln -s symlink redirects, vim/nvim/ed Ex mode, base64 -d | sh, php -r, lua, tclsh, Rscript, nim, comma-adjacent path tokens in interpreter -e/-c arguments
- **Test approach**: integration + structural. Target tests: `tests/test-sensitive-file-guard.sh` `test_inv006_over_extract_blocks_bypasses` (integration) and `test_inv006_no_per_command_dispatch` (structural). Integration: fixture table of 12 Bash commands (one per R2 bypass mechanism) targeting `.env` or `.correctless/meta/harness-fingerprint.json`; assert sensitive-file-guard blocks every one. Structural: grep `_extract_bash_targets` body in `hooks/sensitive-file-guard.sh` for any `case "$tok" in <name>)` matching the disallowed list (see INV-006a for the literal list).
- **Risk**: critical

### INV-006a: Disallowed per-command branches in `_extract_bash_targets` enumerated explicitly
- **Type**: must-not
- **Category**: security
- **Statement**: After the refactor, `_extract_bash_targets` MUST NOT contain `case` branches matching any of the following command-name tokens (each was a per-command dispatch arm in the pre-R2 implementation): `cp`, `mv`, `rm`, `rmdir`, `unlink`, `tee`, `curl`, `wget`, `sed`, `perl`, `touch`, `chmod`, `chown`, `chgrp`, `tar`, `unzip`, `7z`, `cpio`, `ar`, `scp`, `sftp`, `mkdir`, `git`, `python`, `python3`, `node`, `ruby`, `ln`. The only acceptable `case` branches in the function body are: (a) the redirect-token extraction `case "$tok" in ">"|">>"|"1>"|"2>"|"&>")` (one branch covering all 5 redirect operators per Finding #15), (b) the process-substitution branch `case "$tok" in ">("*|"<("*)` (per INV-007a), (c) the default `*)` branch that emits the token as a candidate (the over-extraction default). No other branches. The enumeration is the literal disallowed list; the structural test asserts each disallowed string does not appear in the function body.
- **Boundary**: refs PAT-001
- **Violated when**: any of the 28 enumerated command-name tokens appears in a `case` branch in `_extract_bash_targets`; new write-tool branches are added in any future PR
- **Guards against**: the dispatch-resurrection bypass class (Finding #13) — the spec author leaving "just one branch for git" or similar oversight, satisfying the naive grep but violating spec intent
- **Test approach**: structural — exact grep for each of the 28 disallowed tokens in `_extract_bash_targets` body. Target test: `tests/test-sensitive-file-guard.sh` `test_inv006a_disallowed_branches_enumerated`. The test reads the function body via awk (between function open `_extract_bash_targets()` and the matching close `}`), then for each disallowed token in the literal list, asserts no matching `case "$tok" in <token>)` pattern.
- **Risk**: critical

### INV-007: Redirect detection covers `>`, `>>`, numbered FDs, and inline forms [integration]
- **Type**: must
- **Category**: security
- **Statement**: The over-extractor identifies the target of `>`, `>>`, `1>`, `2>`, `&>` redirects whether the operator is whitespace-separated (`cmd > file`) or inline-attached (`cmd>file`, `cmd>>file`, `cmd2>file`). The targets are emitted as candidates alongside positional tokens. **Implementation form (per Finding #15 disambiguation)**: the function uses two complementary mechanisms — (a) a `case` branch in the token loop matching all 5 redirect operators as standalone tokens (whitespace-separated forms), AND (b) a regex pass at the end of the function with extended pattern `(>{1,2}|[12]>|&>)([^[:space:]\;\|]+)` that catches inline-attached forms within a single token. Both mechanisms run; targets from both are emitted. No other token-loop branches exist (per INV-006a).
- **Boundary**: refs PAT-001
- **Violated when**: any reasonable shell redirect form fails to surface its target as a candidate; tests for the unhandled forms are missing or skipped; the implementation has only one of the two mechanisms (e.g., regex-only would miss tokens that arrived pre-tokenized)
- **Test approach**: integration + unit. Target tests: `tests/test-sensitive-file-guard.sh` `test_inv007_redirect_extraction_unit` (fixture table with one row per redirect-form variant) and `test_inv007_redirect_blocks_integration` (submits `cat /etc/hostname > .env`, `cat /etc/hostname>.env`, `cat /etc/hostname 2> .env`, `cat /etc/hostname &> .env` via Bash; asserts hook blocks each).
- **Risk**: high

### INV-007a: Process substitution `>(...)` and `<(...)` trigger sub-tokenization [integration]
- **Type**: must
- **Category**: security
- **Statement**: When `_extract_bash_targets` encounters a token starting with `>(` or `<(` (process substitution), it sub-tokenizes the contents inside the parens (stripping the leading `>(` or `<(` and the trailing `)`) and emits each contained token as a candidate. This handles bypasses like `cat /etc/hostname > >(cat > .env)` where the outer redirect target is `>(cat` (a single logical token to bash) and the inner write `> .env` is hidden. The sub-tokenization uses the same IFS as the outer extraction; it does NOT recurse further (a doubly-nested `>(cmd >(cmd2 > .env))` is one level of sub-tokenization only — by INV-006a's "no per-command dispatch", recursion would itself be a banned mechanism).
- **Boundary**: refs PAT-001
- **Violated when**: a token starting with `>(` or `<(` is emitted whole without sub-tokenization; the implementation recurses into doubly-nested process substitutions
- **Guards against**: process-substitution write-target bypass (Finding #4) that defeats both the outer extractor (the inner write looks like one token) and the redirect dedup
- **Test approach**: integration — submit `cat /etc/hostname > >(cat > .env)` and `tee >(grep foo > .env) >/dev/null` via Bash; assert the hook blocks both. Additionally a unit test on `_extract_bash_targets` with the literal command string asserting `.env` appears in the emitted candidates. Target test: `tests/test-sensitive-file-guard.sh` `test_inv007a_process_substitution_blocks`.
- **Risk**: high

### INV-008: Pattern matching uses canonical forms on both sides
- **Type**: must
- **Category**: data-integrity
- **Statement**: Both target paths and protected patterns are passed through `canonicalize_path` before bash `case` glob comparison. Patterns containing literal glob characters (`*.pem`, `*.key`, `secrets.*`) survive canonicalization with their glob metacharacters preserved as literal bytes (per INV-004), and the bash `case` statement at match time interprets those bytes as glob metacharacters. Trailing-slash, double-slash, and dot-segment differences between target and pattern are eliminated by the symmetric canonicalization.
- **Violated when**: a pattern is matched against a non-canonical target, or a target is matched against a non-canonical pattern, or canonicalization on the pattern side strips the literal glob characters
- **Test approach**: integration — pattern `*.pem` matches `./certs/key.pem`, `certs//key.pem`, `subdir/../certs/key.pem`; pattern `.correctless/meta/harness-fingerprint.json` matches `./.correctless/meta/harness-fingerprint.json` and `subdir/../.correctless/meta/harness-fingerprint.json`; pattern `id_rsa` (basename) matches `./.ssh/id_rsa` and `~/.ssh/id_rsa` (after canonicalize, `.ssh/id_rsa`)
- **Risk**: critical

### INV-009: HARNESS_VERSION constant is the sole production input
- **Type**: must
- **Category**: security
- **Statement**: The shipped `scripts/harness-fingerprint.sh` has no command-line flag, no environment variable, and no other input mechanism that overrides the `HARNESS_VERSION` integer constant. The constant is set by literal bash assignment (`HARNESS_VERSION=N`, where `N` is an integer literal) on a single line near the top of the file.
- **Boundary**: refs PRH-006 (original harness-fingerprint spec) and ABS-027 (harness fingerprint store contract)
- **Violated when**: the script accepts `--version`, `-v`, `--harness-version`, or any other flag that affects the fingerprint computation; the script reads `HARNESS_VERSION`, `CORRECTLESS_HARNESS_VERSION`, or any environment variable that overrides the constant; the constant is computed dynamically from any source (env, file, command output)
- **Guards against**: AUTH-R2-001 — `--version` flag as the autonomous-bump escape hatch via legitimate confused deputy. The flag was added for testability (INV-018 in the original spec) but is also the exact mechanism an autonomous agent would use to suppress notification.
- **Test approach**: structural (grep) + integration. Structural target: `tests/test-harness-fingerprint.sh` `test_inv009_no_override_surface`. Grep patterns (each must return zero matches against `scripts/harness-fingerprint.sh`, with the grep restricted to non-comment lines via `grep -v '^[[:space:]]*#'` to avoid the M-11 false-match): `--version`, `--harness-version`, `VERSION_OVERRIDE`, `\$\{HARNESS_VERSION:-`, `\$\{HARNESS_VERSION:=`, `:[[:space:]]*\$\{HARNESS_VERSION:=`. Integration target: `test_inv009_invocation_ignores_override`. Two integration cases: (a) `bash scripts/harness-fingerprint.sh check --version 99` — assert exit 0 (unknown flag is silently dropped per existing fail-open arg-parse) AND fingerprint output reflects the literal constant from the file, NOT 99; (b) `HARNESS_VERSION=99 bash scripts/harness-fingerprint.sh check` — assert same.
- **Risk**: critical

### INV-010: Test injection of HARNESS_VERSION uses tmpdir copy with sed substitution (Finding #1 + #8 amended)
- **Type**: must
- **Category**: functional (test-only)
- **Statement**: Tests that need to inject a specific HARNESS_VERSION value invoke a helper `make_test_harness_script` in **`tests/harness-fingerprint-test-helpers.sh`** (a feature-specific helper file, NOT shared `tests/test-helpers.sh` — per Finding #8 amendment). `tests/test-harness-fingerprint.sh` sources this new helper file alongside `test-helpers.sh`. The helper copies `scripts/harness-fingerprint.sh` to a destination at `$workdir/harness-fp-test-${BASHPID}.sh` (per Finding #1 amendment — the destination filename is `harness-fp-test-${BASHPID}.sh` and the destination has NO `scripts/` parent component, so the destination path does NOT match the protected pattern `*/scripts/harness-fingerprint.sh` in DEFAULTS and the helper's own `cp` is not blocked by sensitive-file-guard). It substitutes the `HARNESS_VERSION=N` line via `sed -E 's/^HARNESS_VERSION=.*$/HARNESS_VERSION='"$version"'/'`, validates the substitution succeeded (greps the result for `^HARNESS_VERSION=$version$`), and returns the tmpdir-script path on stdout. Tests invoke `bash "$(make_test_harness_script $version $workdir)" check ...` instead of `bash "$SCRIPT" --version $version check ...`. The production script is never modified; the helper writes only inside `$workdir` (which must be a path under `$WORK_BASE`, validated by the helper).
- **Violated when**: a test invokes the production script with a flag that affects fingerprint computation; the helper modifies the production script in place; the helper writes outside its supplied `$workdir`; the helper produces a script that doesn't actually contain the injected version (validation grep fails); the helper's destination path matches the `*/scripts/harness-fingerprint.sh` protected pattern (Finding #1 regression); the helper is added to shared `tests/test-helpers.sh` instead of the feature-specific file (Finding #8 regression)
- **Test approach**: structural (grep) + integration. Structural targets: `tests/test-harness-fingerprint.sh` `test_inv010_no_version_flag_in_tests` (grep for `--version` invocations of `$SCRIPT` — must find zero post-migration), and `tests/test-harness-fingerprint.sh` `test_inv010_helper_in_feature_file` (assert the helper exists in `tests/harness-fingerprint-test-helpers.sh` and NOT in `tests/test-helpers.sh`). Integration target: `test_inv010_helper_produces_correct_version` — calls `make_test_harness_script 42 "$d"`, runs the resulting script with `check`, asserts the `fingerprint=` line contains `|42` and the resulting filename matches `harness-fp-test-*.sh` under `$d`.
- **Risk**: medium

### INV-011: --version removal breaks tests loudly during migration (transient invariant)
- **Type**: must (transient — applies during this PR only)
- **Category**: functional
- **Statement**: After the production script change but before the test migration, the existing test suite must FAIL with an error indicating the flag is no longer recognized. Silent test pass during migration is forbidden. Per Decision 3 (resolved during /cspec), the migration ships as **two separate commits** so the production change and the test migration are independently revertable:

  **Commit 1 — Production change (remove --version)**
  1. Remove `--version` flag handling and `VERSION_OVERRIDE` from `scripts/harness-fingerprint.sh`
  2. Run the test suite — verify it fails with a clear error
  3. Capture the failing output in the commit message body (and again in the PR description) as evidence of "loud failure"
  4. Commit. The repository is intentionally in a tests-failing state at this commit boundary on the audit branch — that is the loud-failure signal.

  **Commit 2 — Test migration (helper + tests)**
  1. Add `make_test_harness_script` to `tests/test-helpers.sh`
  2. Migrate every `--version` invocation in `tests/test-harness-fingerprint.sh` to the helper
  3. Run the test suite — verify it passes
  4. Commit. After this commit the branch is green again.

  Why two commits: if the test helper approach doesn't work, commit 2 can be reverted without re-adding `--version` to production (which would re-open AUTH-R2-001). Squashing the two would couple the production-security decision and the test-infrastructure decision in a single revertable unit, which is exactly what the user rejected during /cspec Decision 3.

  **PR-description capture (Finding #10 amendment)**: the project uses GitHub squash-merge (`merge_strategy: squash` in workflow-config.json), so the two-commit boundary disappears at merge. The loud-failure evidence MUST therefore be captured in **two places**, not one: (a) the commit 1 message body (preserved on the audit branch for the duration of the PR; lost on squash), AND (b) the PR description's "Loud-failure evidence" section (survives squash; visible to reviewers and to the post-merge audit trail). The reviewer process check before merge approval: "Does the PR description contain the captured failing-test output from commit 1?" — failure to find it is a BLOCKING review finding.
- **Violated when**: tests silently pass after flag removal because a fast-path or default value masks the missing override; the migration is squashed into a single commit; the loud-failure output is not captured in the commit message body of commit 1; the loud-failure output is not captured in the PR description (will be invisible after squash merge — Finding #10)
- **Test approach**: process — verified manually mid-PR by running the test suite after commit 1 and confirming the captured failing output appears in BOTH the commit 1 message body AND the PR description "Loud-failure evidence" section
- **Risk**: medium

### INV-012: canonicalize_path performance bound
- **Type**: must
- **Category**: resource-lifecycle
- **Statement**: A single `canonicalize_path` invocation on a path of up to 1024 bytes completes in under 50ms on the CI baseline (Ubuntu 24.04, bash 5.1). Pure-bash implementation with no fork/exec — no `$(...)`, no backticks, no external command invocations inside the function body.
- **Violated when**: a single invocation exceeds 100ms on the CI baseline; the implementation forks an external process via `$(...)`, backticks, or pipe
- **Test approach**: performance + structural — time 100 invocations of canonicalize_path on a 1024-byte path with mixed traversal/glob characters; assert mean wall time < 50ms; structural grep of canonicalize_path body for `$(`, backticks, `|` (pipe), explicit external command invocations (must find none)
- **Risk**: medium

### INV-013: `_has_write_pattern` flags interpreter chains [integration]
- **Type**: must
- **Category**: security
- **Statement**: When a Bash command contains an interpreter token (`bash`, `sh`, `zsh`, `dash`, `perl`, `python`, `python3`, `ruby`, `php`, `lua`, `tclsh`, `Rscript`, `nim`, `node`) followed (anywhere in the same command) by an evaluation flag (`-c`, `-e`, `-r`, `-E`, `-pe`, `-ne`, `-pi`, `-ni`, `-lpi`, `--execute`), `_has_write_pattern` returns true. The over-extractor (per INV-006) then processes the entire command. This makes interpreter chains visible to the guard rather than silently bypassed. **Basename matching (Finding #3 amendment)**: the interpreter token is matched on its filename basename, not the full path token. `/usr/bin/env perl`, `/usr/bin/python3`, `/opt/local/bin/ruby` all match the corresponding basename entry. The implementation strips any leading directory component before comparing against the literal interpreter list.
- **Boundary**: refs PAT-001
- **Violated when**: a Bash command of the form `interpreter -c "writer cmd targeting protected file"` returns false from `_has_write_pattern` and the protected file edit goes through; new interpreters are added to the project's documented stack without being added to the list; the implementation matches on full-path tokens only and misses pathed invocations like `/usr/bin/env perl` (Finding #3 regression)
- **Guards against**: R2 finding "bash -c \"perl -e ...\" interpreter chains", "perl combined flags (-pi, -ni, -lpi)", "perl without -i (writes via open(F,'>file'))", "php / lua / tclsh / Rscript / nim not in interpreter list", "base64 -d | sh encoded payloads", and "pathed interpreter invocations (e.g., /usr/bin/env perl)" (Finding #3)
- **Test approach**: integration — fixture table covering every interpreter+flag combination in the statement (14 interpreters × 11 flags = 154 combinations, sample 30 representative pairs) AND each interpreter in pathed form (`/usr/bin/env perl -e ...`, `/usr/bin/python3 -c ...`, `/opt/local/bin/ruby -e ...`). Assert `_has_write_pattern` returns true for each; assert sensitive-file-guard blocks each when the inner command targets `.env` or another protected file. Target test: `tests/test-sensitive-file-guard.sh` `test_inv013_interpreter_chains_blocked`.
- **Risk**: critical

### INV-013a: workflow-gate.sh consumes the same extended `_has_write_pattern` — regression test required (Finding #2)
- **Type**: must
- **Category**: functional
- **Statement**: Per ABS-001, `_has_write_pattern` lives in `scripts/lib.sh` and is consumed by both `hooks/sensitive-file-guard.sh` AND `hooks/workflow-gate.sh`. Extending the function (per INV-013) to flag interpreter chains expands the set of Bash commands that workflow-gate.sh treats as "write" — which means more commands get phase-gated during RED. This is intentional (the strict definition of "write" should be uniform across hooks), but it creates a regression risk: a previously-allowed RED-phase command (e.g., `bash -c 'echo "test setup"'`) becomes blocked. A regression test in `tests/test-workflow-gate.sh` MUST verify the expected RED-phase behavior on the expanded write-set: at least 5 representative interpreter-chain invocations are tested in the RED phase, and the test asserts the documented expected disposition (blocked or allowed depending on phase) for each.
- **Boundary**: refs ABS-001 + PAT-001
- **Violated when**: `tests/test-workflow-gate.sh` lacks a test exercising the extended `_has_write_pattern` interpreter-chain coverage; a workflow-gate behavior regression on RED-phase commands ships unnoticed
- **Test approach**: integration — target test: `tests/test-workflow-gate.sh` `test_inv013a_workflow_gate_consumes_extended_pattern`. Sets up a workflow-state RED phase, submits 5 interpreter-chain commands (e.g., `bash -c 'echo x'`, `python3 -c 'print(1)'`, `perl -e 'print 1'`), asserts each returns the documented expected disposition (RED phase blocks all writes including these expanded ones). The test also greps `scripts/lib.sh` to verify `_has_write_pattern` is the single shared source (no local redefinition in workflow-gate.sh).
- **Risk**: medium

### INV-014: setup detects pre-R2 install of harness-fingerprint.sh and force-reinstalls (Finding #7)
- **Type**: must
- **Category**: resource-lifecycle
- **Statement**: The `setup` script's installation step for `scripts/harness-fingerprint.sh` greps the existing installed file (if present) for the literal string `VERSION_OVERRIDE`. If found (indicating a pre-R2 installation containing the now-removed `--version` flag handling), setup MUST: (a) emit a one-line stderr notice referencing INV-009/PRH-003 ("Detected pre-R2 harness-fingerprint.sh — re-installing per /cspec harness-fingerprint-r2-hardening INV-014"), (b) force-reinstall the new script (overwriting the existing installation), (c) update the install manifest entry. This closes the upgrade-path break Finding #7 surfaced: without this step, an upgraded user has new tests + old script + new sensitive-file-guard, which results in `make_test_harness_script: command not found` (because the new tests reference the new helper) and no clear remediation.
- **Boundary**: refs ABS-022 (install manifest) + PRH-006 (HARNESS_VERSION protection)
- **Violated when**: setup silently overwrites the existing script without the detection grep; setup detects `VERSION_OVERRIDE` but does NOT reinstall (silent skip); setup emits no notice on the upgrade reinstall; the install manifest is not updated after the force-reinstall
- **Guards against**: silent upgrade break (Finding #7) — pre-R2 user runs `bash setup` to upgrade Correctless, sensitive-file-guard now blocks the cp because of the protected pattern, the upgrade fails partway, and the user is left with an inconsistent install
- **Test approach**: integration — fixture creates a tmpdir with a fake pre-R2 `scripts/harness-fingerprint.sh` containing `VERSION_OVERRIDE=`, runs `setup --target $tmpdir`, asserts: (a) stderr contains the notice string, (b) the post-install file at `$tmpdir/.correctless/scripts/harness-fingerprint.sh` does NOT contain `VERSION_OVERRIDE`, (c) the install manifest reflects the new file's hash. Target test: `tests/test-stale-hook-detection.sh` `test_inv014_pre_r2_force_reinstall` (the test file already covers install-manifest concerns; add this case there).
- **Risk**: high

## Prohibitions

### PRH-001: No regex-based path normalization in the pre-match pipeline
- **Statement**: The R1 fix attempt used regex-based path normalization (variations of `s|/[^/]+/\.\./|/|g`). This approach is forbidden anywhere in `scripts/lib.sh` or `hooks/sensitive-file-guard.sh`. It is incomplete (resolves one `..` per pass), corrupts paths containing glob characters when used unquoted, and has been observed to infinite-loop on bracket-and-`..` combinations. `canonicalize_path`'s segment-stack design is the only sanctioned normalizer.
- **Detection**: structural grep — target test `tests/test-canonicalize-path.sh` `test_prh001_no_regex_normalization`. Scans `scripts/lib.sh` and `hooks/sensitive-file-guard.sh` for the literal patterns `s|/` (basic regex form), `s\|/` (escaped form), and `s/[^/]\\+/\\.\\.\\//` (POSIX basic-regex variant). Each must return zero matches.
- **Consequence**: reintroduces the entire R2 finding class against canonicalize_path

### PRH-002: No per-command dispatch in `_extract_bash_targets`
- **Statement**: The current dispatch has explicit `case` branches for `cp`, `mv`, `rm`, `tee`, `curl`, `sed`, `perl`, `touch`, `chmod`, `tar`, `unzip`, `scp`, `git`, `python`, `node`, `ruby`. Every branch is a maintenance burden and every uncovered command is a bypass. The dispatch is forbidden — the extractor's only branches are: (a) redirect-target extraction (one branch matching all 5 redirect operators), (b) process-substitution branch (per INV-007a), (c) over-extract every non-flag token (the default branch).
- **Detection**: covered by INV-006a's structural test (`tests/test-sensitive-file-guard.sh` `test_inv006a_disallowed_branches_enumerated`) — the test enumerates 28 disallowed command-name tokens and asserts none appears as a `case` branch in the `_extract_bash_targets` body.
- **Consequence**: reintroduces the bypass surface R2 enumerated

### PRH-003: No `--version` flag, no env-var override, no escape hatch on the fingerprint constant
- **Statement**: The shipped `scripts/harness-fingerprint.sh` exposes no input mechanism that lets a caller override `HARNESS_VERSION`. No `--version`, no `--harness-version`, no env var (`HARNESS_VERSION`, `CORRECTLESS_HARNESS_VERSION`), no `: ${HARNESS_VERSION:=N}` defaulting form, no config file lookup, no compute-from-anything-else. The only way to change the fingerprint is to commit a change to the literal `HARNESS_VERSION=N` line, which is gated by sensitive-file-guard (PRH-006 in the original harness-fingerprint spec, structurally enforced via ABS-027).
- **Detection**: covered by INV-009's structural + integration tests (`tests/test-harness-fingerprint.sh` `test_inv009_no_override_surface` and `test_inv009_invocation_ignores_override`).
- **Consequence**: AUTH-R2-001 returns — autonomous agent can suppress notification by invoking the script with override

### PRH-004: `canonicalize_path` output is the only form `_check_file_against_patterns` ever sees
- **Statement**: The pipeline-disagreement failure mode (canonicalize-output-differs-from-matcher-expectation) is the bypass class the user explicitly called out during brainstorm. `canonicalize_path` produces the canonical form and nothing else may reach `_check_file_against_patterns`. Both arguments — target and pattern — must be the output of canonicalize_path applied at most one call site upstream.
- **Detection**: covered by INV-005's structural test (`tests/test-sensitive-file-guard.sh` `test_inv005_canonical_only_at_matcher`) — the test scans the function body via awk to verify every `_check_file_against_patterns` call site is preceded by a `canonicalize_path` reference within 5 lines.
- **Consequence**: re-opens the canonicalization-mismatch bypass class; defeats the entire INV-005 + INV-008 design

### PRH-005: No `_extract_bash_targets` recursion into quoted strings
- **Statement**: The over-extractor tokenizes the outer command on the existing IFS (`$' \t\n;|&()` `` ` ``). It does NOT recursively parse the contents of `-c`, `-e`, `-r`, etc. arguments as nested commands. Recursive parsing would invite quote-escaping bugs and double-tokenization edge cases. The defense for interpreter chains is in `_has_write_pattern` (INV-013) flagging the outer command, then the over-extractor pulling out the path-like tokens that survive the outer tokenization (which is sufficient — the protected filename appearing anywhere in the command's tokens triggers the match). NB: process-substitution sub-tokenization (INV-007a) is a single-level operation on the contents of `>(...)` / `<(...)` literal tokens — it is not recursion into `-c`/`-e`/`-r` argument contents and does not violate this prohibition.
- **Detection**: structural grep — target test `tests/test-sensitive-file-guard.sh` `test_prh005_no_extractor_recursion`. Scans `_extract_bash_targets` body (via awk between `_extract_bash_targets()` and the matching close `}`) for: (a) `_extract_bash_targets` (a recursive call would contain the function name in its own body), (b) `eval` (inner-command-string evaluation), (c) `local IFS=` after the function's first IFS declaration (nested IFS shifts). Each must return zero matches in the function body.
- **Consequence**: the extractor grows complex enough to harbor its own bypass class (the failure mode that produced the original per-command dispatch)

## Boundary Conditions

### BND-001: Untrusted Bash command from agent → write-pattern detection → over-extract → canonical match
- **Boundary**: PreToolUse hook decision boundary (the implicit boundary at every `case "$TOOL_NAME" in Bash)` branch in `hooks/sensitive-file-guard.sh`)
- **Input from**: agent-supplied `tool_input.command` (Bash) or `tool_input.file_path` / `tool_input.edits[].file_path` (Edit/Write/MultiEdit)
- **Validation required**: every extracted target passes through `canonicalize_path` (INV-005); the matcher receives canonical forms only (PRH-004)
- **Failure mode**: fail-closed — if `canonicalize_path` exits non-zero on any target (which INV-001 says cannot happen, but defense-in-depth), the hook treats the operation as "unknown — could be sensitive" and exits 2 to block
- **Test**: integration tests in tests/test-sensitive-file-guard.sh covering each path-traversal-encoded form

### BND-002: Untrusted Bash command → interpreter-chain detection
- **Boundary**: PreToolUse hook decision boundary (the same boundary as BND-001, focused on `_has_write_pattern`'s coverage)
- **Input from**: agent-supplied `tool_input.command` (Bash)
- **Validation required**: `_has_write_pattern` returns true for any command containing an interpreter+evaluation-flag pair (INV-013); this expands the set of commands that flow into the over-extractor
- **Failure mode**: fail-closed — over-extraction blocks legitimate-but-noisy commands (e.g., `bash -c 'echo .env exists'` would be flagged because `bash -c` is in the interpreter set and `.env` is a token). Acceptable per Q2 brainstorm: noisy-but-correct beats silently-bypassed. The user's escape hatch is `protected_files.custom_patterns` exclusion in workflow-config.json or direct file edit outside Claude Code (already documented in the existing BLOCKED message).
- **Test**: integration tests covering each interpreter+flag combination

### BND-003: Test workspace tmpdir → harness-fingerprint script copy (Finding #1 amendment)
- **Boundary**: test infrastructure boundary (between production script and test fixtures)
- **Input from**: `make_test_harness_script $version $workdir` invocation parameters (test-controlled)
- **Validation required**: helper writes only under `$workdir` (must be a path under the test's `$WORK_BASE`, validated by the helper); helper substitutes only the `HARNESS_VERSION=` line, leaving the rest of the script byte-equal to the production source; **destination filename is `harness-fp-test-${BASHPID}.sh` and the destination has no `scripts/` parent component, so the path does NOT match the protected pattern `*/scripts/harness-fingerprint.sh` in DEFAULTS — this is the Finding #1 fix**
- **Failure mode**: fail-loud — if `$workdir` does not exist, is not under `$WORK_BASE`, or `$version` is non-integer, the helper exits non-zero and tests fail visibly
- **Test**: integration — `tests/test-harness-fingerprint.sh` `test_bnd003_helper_destination_not_protected` asserts the resulting destination path does not match `*/scripts/harness-fingerprint.sh` (literal pattern check); `tests/test-harness-fingerprint.sh` `test_bnd003_helper_byte_equal_except_version` runs `diff` between the helper output and the production source after re-substituting back to the production version, asserting the only difference is the `HARNESS_VERSION=` line

## STRIDE Analysis

For the implicit trust boundary at the PreToolUse hook decision (`hooks/sensitive-file-guard.sh` deciding whether an agent-supplied tool_input touches a protected path):

### Spoofing
- **Threat**: Agent crafts a Bash command whose tokens look benign but write to a sensitive file via a writer the extractor doesn't recognize (perl -i, ed, php -r, base64 | sh).
- **Mitigation**: INV-006 (over-extract on every flagged write) + INV-013 (`_has_write_pattern` flags interpreter chains) close this entire class. The extractor's job is no longer "recognize the writer"; it's "given that something might write, dump every path-like token."

### Tampering
- **Threat 1**: Agent attempts to bump HARNESS_VERSION via `--version` flag, suppressing the next `version_bumped` notification and hiding from `/cmodelupgrade` review.
- **Mitigation 1**: INV-009 / PRH-003 (no override surface in production script). Agent's only path to changing the fingerprint is `Edit scripts/harness-fingerprint.sh`, which sensitive-file-guard already blocks via ABS-027 (sole-writer enforcement).
- **Threat 2**: Agent submits a path-traversal-encoded write (`Edit subdir/../scripts/harness-fingerprint.sh`) to bypass the literal-path match in the guard.
- **Mitigation 2**: INV-005 + INV-008 + PRH-004 (canonical-on-both-sides). The guard sees the canonicalized form of the target and matches it against the canonicalized form of the protected pattern; traversal-encoded targets resolve to the canonical sensitive path before matching.

### Repudiation
- N/A — the hook is local, stateless, and produces no audit trail of its own. Audit-trail.sh (PostToolUse) records what was attempted; this hook just decides allow/block.

### Information Disclosure
- N/A — the hook reads tool input and pattern data; it does not produce output that could leak information beyond the BLOCKED stderr message (which contains the matched pattern name and target path, both already visible to the agent).

### Denial of Service
- **Threat 1**: `canonicalize_path` infinite loop on tricky input (the R1 regex bug — `[abc]/../foo` infinite-looped because the regex normalization removed the first `..` segment then the bracket interfered with re-matching).
- **Mitigation 1**: INV-001 (totality + 2s test timeout) + INV-012 (50ms perf bound + structural grep for fork/exec patterns). The segment-stack walker iterates over a finite list of segments — the loop bound is the segment count, not regex retries.
- **Threat 2**: Over-extraction blocks legitimate Bash commands that happen to mention a sensitive filename in their text (e.g., `bash -c 'grep .env src/config.js'`).
- **Mitigation 2**: Accepted. BND-002 documents this as the noisy-but-correct failure mode the user explicitly chose during brainstorm. The workflow already has an escape hatch (`protected_files.custom_patterns` exclusion or direct file edit).

### Elevation of Privilege
- **Threat 1**: Agent uses canonicalization-mismatch to bypass guard.
- **Mitigation 1**: INV-005 / INV-008 / PRH-004 (canonical-on-both-sides).
- **Threat 2**: Agent uses unparsed write tool.
- **Mitigation 2**: INV-006 / INV-013 / PRH-002 (over-extract + interpreter-chain detection).
- **Threat 3**: Agent autonomously bumps HARNESS_VERSION, suppressing model-upgrade notification.
- **Mitigation 3**: INV-009 / PRH-003 + ABS-027 (no override + sole-writer enforcement).

## Environment Assumptions

### EA-001: Bash 4+ for canonicalize_path
- **Assumption**: `canonicalize_path` uses `local -a` arrays, `unset 'arr[idx]'` element removal, `${var:0:1}` substring, and `local IFS=` override semantics. All require Bash 4.0+.
- **Refs**: ENV-001 (existing — Bash 4+ project-wide assumption)
- **Consequence if wrong**: silent failures on macOS default Bash 3.2 — array element removal and re-index would behave unpredictably. ENV-001 already documents that users must install Bash 4+ via Homebrew.

### EA-002: POSIX `sed` for test helper
- **Assumption**: `make_test_harness_script` uses `sed` to substitute the `HARNESS_VERSION=N` line. The substitution uses POSIX-portable `sed -E` with `^HARNESS_VERSION=` anchor; no GNU-only extensions.
- **Refs**: ENV-006 (existing — POSIX-portable external tools)
- **Consequence if wrong**: helper fails on macOS BSD sed, but the failure is loud (non-zero exit), and tests fail visibly per BND-003 fail-loud posture.

### EA-003: Performance baseline reflects CI environment
- **Assumption**: INV-012's 50ms wall-clock bound is measured on the CI baseline (Ubuntu 24.04, bash 5.1, no I/O contention). Local developer machines may vary; the structural anti-fork-exec assertion is the load-bearing check, the wall-clock measurement is the secondary signal.
- **Consequence if wrong**: a CI flake might exceed the 50ms bound on a noisy CI runner. Mitigation: the test asserts mean over 100 invocations, not p99, and the structural grep cannot flake.

### EA-004: canonicalize_path operates on bytes, not characters (Finding #12)
- **Assumption**: `canonicalize_path` runs in a `LC_ALL=C` byte-oriented locale at all internal comparison points. Bash `${var:0:1}` and the bash `case` statement are locale-dependent in their default behavior (with UTF-8 locales, `${var:0:1}` may return a multibyte character, not a single byte). To preserve the byte-level semantics required by INV-002a (only ASCII `.` is treated as a path-segment dot) and INV-004 (literal byte preservation for glob characters), `canonicalize_path` must explicitly set `LC_ALL=C` either at function entry or globally in `lib.sh`.
- **Refs**: ENV-006 (POSIX-portable external tools — extends to byte-level locale assumptions inside the function)
- **Consequence if wrong**: Unicode dot lookalikes (U+2024 ONE DOT LEADER, U+FF0E FULLWIDTH FULL STOP) are treated as `.` in the segment-stack check on systems with UTF-8 locale and bash configured for character-level operations. This is the Finding #12 bypass class: `subdir/U+2024U+2024/.env` becomes `subdir/../.env` after canonicalization, then resolves to `.env` and slips past pattern matching that compared against the literal-byte pattern.
- **Test**: covered by INV-002a's integration test (Unicode lookalikes survive canonicalization as ordinary bytes); additionally, structural grep on `canonicalize_path` body for `LC_ALL=C` or `LC_COLLATE=C` setting (must find at least one).

## Open Questions

All six open questions resolved during /cspec Step 8 presentation (2026-04-27). Resolutions captured below; /creview-spec may revisit any of them if adversarial review surfaces new concerns.

- **OQ-001 [RESOLVED]**: `canonicalize_path` strips trailing slash always (except when the entire output is `/`). Pattern matching does not require directory-vs-file intent.

- **OQ-002 [RESOLVED]**: Process-substitution write targets `>(...)` are out of scope. The outer-command match already catches the typical case (`tee >(grep foo) > .env` matches outer `tee`). Re-evaluate if a real bypass appears.

- **OQ-003 [RESOLVED]**: Two commits, not squash. Commit 1 = production `--version` removal (tests failing on the branch at this commit, with failing output captured in commit message body). Commit 2 = test helper introduction + test migration (tests green). This keeps the production-security decision and the test-infrastructure decision independently revertable. INV-011 has been updated to specify this sequence explicitly.

- **OQ-004 [RESOLVED]**: Over-extraction noise on `bash -c 'grep .env src/config.js'` is accepted. False positives are disputable (use `protected_files.custom_patterns` exclusion); false negatives are bypasses (unacceptable). The dispatch-deletion architecture explicitly forbids precision/security tradeoff carve-outs.

- **OQ-005 [RESOLVED]**: Update the original harness-fingerprint spec's INV-018 during this PR's `/cdocs` phase to drop `--version` from the listed flags. Leaving a spec referencing a flag we just removed is exactly the drift `/cverify` exists to catch.

- **OQ-006 [RESOLVED]**: Defer `workflow.intensity_signals.keywords` update for `bypass`/`traversal`/`canonicalize`. This spec already triggered `high` correctly; adding keywords is scope creep with no immediate value.

## Approved Architecture Updates (deferred to /cdocs)

Promotion approvals captured during /cspec Step 8 — to be applied during this PR's `/cdocs` (or `/cupdate-arch`) phase, not in this spec's GREEN. Recorded here so the architecture-update phase picks them up without losing context.

### Promote AP-024 → PAT-016 (approved)
- **Trigger**: 16 missing scripts across 5 features (auto-mode-phase-2, auto-mode-phase-3, carchitect, project-dashboard, session-cost-analysis). Highest promotion-eligible impact.
- **Relevance to this spec**: INV-013's interpreter list is itself an instance of the AP-024 pattern (a manual list that grows stale). Promoting AP-024 to PAT-016 makes the structural count-match test mandatory for new enumerated lists going forward, including INV-013's interpreter list.
- **Draft entry to add to `.correctless/ARCHITECTURE.md` after `### PAT-015`**:

```markdown
### PAT-016: Glob over directory contents — never enumerate (guards AP-024)
- **Pattern**: When installing or processing all files of a single type from a directory, use a glob pattern (`for f in dir/*.sh`) — never a hardcoded enumerated list
- **Rule**: Code that iterates "all files of type X in directory Y" must use a shell glob over Y, not a hardcoded list of filenames. A structural test must verify the count of installed/processed files matches the count of source files. Adding a new file in the source directory must fail the test if the file is not picked up downstream. The structural count-match test is mandatory — a glob alone without the test only catches some failure modes.
- **Why**: PMB-003 — `setup` installed hooks via glob (correct) but installed scripts via a hardcoded 2-file list. The list was correct when written (PR #30, only 2 scripts existed) and silently went stale across 5 PRs that added scripts. 16 of 18 scripts were never installed on user projects. The failure was silent — hooks worked (they source lib.sh from the manifest), but features needing other scripts (cost tracking, dashboard, entrypoints, auto-mode) silently degraded with no error. The test for script installation inherited the same 2-file assumption and passed every time.
- **Guards against**: AP-024
- **Violated when**: a new file in a source directory is silently dropped because the consumer enumerated instead of globbing; an enumerated list grows over time without a count-match test catching the drift; an interpreter list, command allowlist, or similar enumerated security-relevant array goes stale
- **Test**: structural test that compares glob count to consumer's effective list count; CI integration check via `tests/test-scripts-namespace-migration.sh` (and equivalent per-feature where the pattern repeats)
```

### Skip AP-007 → PAT-017 (rejected, with reasoning)
- The user rejected this promotion candidate during /cspec Step 8 with a meta-principle: **PAT entries must be mechanically grep-testable, not testing-philosophy.** "Every integration test calls setup_test_project" is testable; "asserts preconditions before postconditions" is not (requires understanding what the precondition is). AP-007 needs another instance or two before the pattern sharpens to something mechanically detectable.
- This decision is recorded as guidance for future /cspec promotion checks: prefer rejection when the proposed PAT/ABS would require human judgment to detect a violation. Promotion is for catching drift mechanically.

### Update test-architecture-drift.sh paths-coverage list (Finding #11 amendment)
- **Trigger**: Finding #11 — PAT-001's `.claude/rules/hooks-pretooluse.md` covers PreToolUse hooks only; the new security-critical `canonicalize_path` lives in `scripts/lib.sh` and would not have the PAT-001 rule body load when an agent edits it.
- **Resolution chosen**: Option (b) from Finding #11 — create a NEW rule file `.claude/rules/canonicalize-path.md` with `paths: [scripts/lib.sh]` frontmatter. Body documents the canonicalize_path security invariants (INV-001 through INV-004, INV-002a, EA-004) so any agent editing lib.sh sees them in context. This is a Feature B usage of ABS-009 (PAT-001 was the first dogfood; this is the second).
- **Architecture-drift test update needed**: `tests/test-architecture-drift.sh` currently has invariants (INV-001..005, INV-017, INV-019, INV-021, INV-027) covering the `hooks-pretooluse.md` rule file's `paths:` list. Equivalent invariants must be added for `canonicalize-path.md`: (a) the rule file exists with non-empty body, (b) frontmatter `paths:` is set-equal to `[scripts/lib.sh]`, (c) any See-link from ARCHITECTURE.md to the rule file resolves, (d) the in-file pointer comment in `scripts/lib.sh` references the rule file (per ABS-009 INV-021).
- **Index entry to add to `.correctless/ARCHITECTURE.md` Patterns section after PAT-016 (per ABS-009 convention — full body lives in the rule file, ARCHITECTURE.md gets only the See-link)**:

```markdown
### PAT-017: canonicalize_path security invariants
See `.claude/rules/canonicalize-path.md`.
```

### --session-id and --meta-dir threat-model gap (deferred to follow-up spec)
- **Trigger**: Finding #9 from /creview-spec — same threat class as AUTH-R2-001 (`--session-id "valid_session_already_seen"` suppresses the version_bumped notification dedup). Recommended fix is sentinel-prefix gating (`--internal-test` prefix assertion in production, similar to ABS-027's existing `__test_session_*` sentinel).
- **Decision**: deferred to a follow-up spec, not bolted onto this one. The user's reasoning (verbatim from /creview-spec Decision 2): "Apply the same pattern to `--session-id` and `--meta-dir` if you want — but that's a decision to make deliberately, not to accept as a review finding amendment mid-flow. The threat is real (same class as AUTH-R2-001) but the fix needs its own thought, not a bolt-on."
- **Recorded as**: open work item for the next /cspec on this surface area. Not a drift item (the gap is documented and accepted with a planned follow-up).
