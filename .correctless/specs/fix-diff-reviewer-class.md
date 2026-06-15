# Spec: Fix-diff reviewer class-shaped bug lens

## Metadata
- **Created**: 2026-06-14T00:00:00Z
- **Status**: draft
- **Impacts**: `agents/fix-diff-reviewer.md` (lens addition + scope amendment + data-treatment prose extension for new fence), `correctless/agents/fix-diff-reviewer.md` (byte-equal mirror via sync.sh), `tests/test-fix-diff-reviewer-agent.sh` (new structural test function + denylist extension + SFG SKIP sentinel + cardinality checklist), `scripts/check-no-pending-sfg-lift.sh` (NEW dedicated companion test — non-skippable pre-push backstop for INV-012a), `tests/fixtures/fix-diff-class-shaped-*.diff` (3 new prompt-composition fixtures, ≥1 derived from real PR #124 / PMB-019 commit), `skills/caudit/SKILL.md` Step 6a (new `<UNTRUSTED_FINDING_DESCRIPTION>` fence emission in the per-round prompt-assembly block — NOT in pre-Step-6a prose), `hooks/sensitive-file-guard.sh` + `correctless/hooks/sensitive-file-guard.sh` (temporarily lifted during PR for AP-037 workaround; final state must be byte-equal to pre-PR), `.correctless/.sfg-lift-active` (NEW committed sentinel file — added by lift commit, removed by restore commit)
- **Branch**: feature/fix-diff-reviewer-class-shaped-bugs
- **Research**: null
- **Recommended-intensity**: high
- **Intensity**: high
- **Intensity reason**: project floor (workflow-config.json sets workflow.intensity=high); TB-005 boundary directly applies (fix-diff-reviewer is the read-only consumer side of intra-skill agent handoff)
- **Override**: none
- **Source issue**: github #175 part 6
- **Motivating postmortem**: PMB-019 / github #144 (ARG_MAX recurrence in `scripts/build-dashboard.sh`; PR #124's fix was scope-narrowed; same script, same class, one month later)

## Context

Add a **class-shaped bug detection lens** to the fix-diff-reviewer agent at `agents/fix-diff-reviewer.md`. When the bug under review is class-shaped — describes a pattern that could have multiple instances in the same file or module — the reviewer must grep for sibling instances before approving. The reviewer's existing pinned tool surface (Read, Grep, Glob) already supports this work; only the prompt direction was missing. PR #124 (2026-05-14) approved a fix at the outer `collect_artifacts` boundary in `scripts/build-dashboard.sh` and never checked the inner `read_file_json` helper using the same `--arg content "$content"` pattern. One month later, PMB-019 was the recurrence. The lens is preventive structure for the class of "same script, same shape, fixed at the wrong scope" failures.

## Scope

**In scope.** A new lens added to `agents/fix-diff-reviewer.md` between the existing "What to check for each hunk" list and the "Output contract" section. The lens uses a two-signal detection: **primary** is the diff content itself (the reviewer inspects diff text and surrounding hunk context for patterns that suggest a scope-narrowed instance fix), **refinement** is the round-level finding list passed via a new `<UNTRUSTED_FINDING_DESCRIPTION>` fence emitted in `/caudit` **Step 6a**'s per-round prompt-assembly block (between Step 6a's internal Step 3 and Step 5; the reviewer is invoked once per round, not per finding — verified against `skills/caudit/SKILL.md:183`). Either signal can trigger the lens; both together raise confidence. When triggered, the reviewer is instructed to grep the file under fix (and any sibling module within a **bounded scope: same directory + same language extension**, with an explicit deny-list for `.env*`, `.correctless/preferences*`, `.correctless/artifacts/autonomous-decisions-*`) for instances of the same pattern. Unaddressed siblings — when the diff does NOT include a machine-checkable `SIBLING-DEFERRED:` marker enumerating them with substantive rationale — become a HIGH finding routed through the existing JSON output contract.

The agent's existing "Data treatment (non-negotiable)" prose (`agents/fix-diff-reviewer.md:22-31`) is extended to enumerate the new fence by name OR rewritten with an explicit `<UNTRUSTED_*>` wildcard form. The OQ-006 "wildcard by construction" assumption was factually wrong (RS-003) — the new fence currently inherits no prompt-injection mitigation; this edit closes the gap.

A narrow scope amendment to the existing agent prose: the current "Out of scope: the unchanged codebase" line (`agents/fix-diff-reviewer.md:43`) gains a sibling-search exception clause **directly adjacent** (within 5 lines, no level-3 heading separating them) with explicit "EXCEPT" / "exception" linking language naming the bounded scope. The reviewer MAY grep unchanged code in the file under fix and **same-directory same-extension** sibling modules when (and only when) the lens is triggered, never `.env*` / `.correctless/preferences*` / `.correctless/artifacts/autonomous-decisions-*`. This is a narrow carve-out, not a broad re-scope.

**Marker-validity contract.** The `SIBLING-DEFERRED:` carve-out is honored ONLY when (a) the marker appears as a syntactic comment in the diff fence — never as text inside `<UNTRUSTED_FINDING_DESCRIPTION>` (closes RS-010 self-referential trust loop without requiring TB-005 extension), (b) the rationale prose is substantive (length floor + non-template), and (c) the marker is human-attributable. Markers added in the same commit as the scope-narrowed fix by an autonomous agent DO NOT fully suppress the finding — they DOWNGRADE severity to MEDIUM with the finding still emitted naming the unaddressed siblings (closes RS-008 self-excusing risk without requiring human-signing infrastructure). The agent prose explicitly names the autonomous-mode downgrade path.

**Multi-finding round handling (RS-006).** Per-round behavior is specified: the fence is emitted as a JSON-array form (`<UNTRUSTED_FINDING_DESCRIPTION>[{...},{...}]</UNTRUSTED_FINDING_DESCRIPTION>` — array of objects each with `id` + `description`) covering all in-round findings. Empty/whitespace-only descriptions are omitted from the array (treated identically to no description, RS-022). When the array would be empty, the entire fence is omitted (no empty fence emission). The reviewer's lens still degrades gracefully when the fence is absent — diff signal alone.

**Per-fence size bound (RS-007).** The per-description size is capped at 4 KB after which truncation appends a marker (`[truncated: N more bytes]`). The aggregate fence is capped at 16 KB; when the array would exceed this, individual descriptions are truncated proportionally before the array is dropped. A test fixture at the cap is required (≥1 description ≥4KB and an aggregate ≥16KB case). Closes the AP-039-shape inside the AP-039 fix.

**Prompt-composition test layer (RS-001, RS-014).** A new structural test layer adds **3 fixtures** at `tests/fixtures/fix-diff-class-shaped-{argmax,loop-var,error-handling}.diff` — at least one derived from `git show <PR-124-merge-commit>` to satisfy PAT-020 (real-fixture provenance). A new small helper `tests/helpers/build-caudit-prompt.sh` (~30 LOC) constructs the synthetic prompt body text by static concatenation of `<UNTRUSTED_RULES>` + new `<UNTRUSTED_FINDING_DESCRIPTION>` block + `<UNTRUSTED_DIFF>` per INV-011's schema; no LLM, no orchestrator invocation. The fixtures are passed through this helper, and the assertion is on the **resulting prompt's shape and content** — that the assembled prompt carries the trigger conditions and instructions the lens needs. The fixtures do NOT verify that the reviewer agent actually emits a HIGH finding (that would require a live `Task()` replay; the project's test runner has no deterministic agent replay surface). They verify (a) the prompt contains the `<UNTRUSTED_FINDING_DESCRIPTION>` fence in the canonical JSON-array form when the round has findings, (b) the prompt is well-formed when the fence is omitted (graceful-degradation path), (c) the prompt's diff content includes the marker-validity test cases (round-added marker, pre-existing marker, malformed marker, marker-in-string-literal) so the agent at inference time has the conditions to apply the INV-016 contract. R-010 records this as a known limitation; OQ-007 tracks the deterministic-replay surface as future infrastructure.

**Structural test in `tests/test-fix-diff-reviewer-agent.sh`** asserts the lens section exists, names the sibling-grep directive, defines the marker format (regex with optional `:line-number`), calibrates severity at HIGH, cites PMB-019, verifies the data-treatment prose covers the new fence, verifies fence emission is in Step 6a per-round prompt assembly with bounded scope, verifies the sub-assertion ID set is complete (cardinality checklist, RS-020), AND verifies the SFG hook's final state matches the pre-PR baseline with a SKIP path that activates when the committed sentinel file `.correctless/.sfg-lift-active` exists (closes RS-005 /cauto consolidation conflict). A **dedicated final-state check script** `scripts/check-no-pending-sfg-lift.sh` lives OUTSIDE the `tests/test-*.sh` glob (deliberately not in `commands.test`) and is invoked at the pre-push / CI / `/cauto` Step 8 consolidation gate. It fails unconditionally when the sentinel is present, providing the non-skippable final-state backstop (INV-012a). Both failure paths emit messages naming AP-037, the lift-and-restore procedure, and the sentinel-file lifecycle (closes RS-017). The distribution mirror at `correctless/agents/fix-diff-reviewer.md` is propagated by the existing `sync.sh` and remains byte-equal (ABS-010).

**Out of scope.** A scanner rule that detects the specific `--arg "$cat-of-file"` pattern at static-analysis time (that is issue #175 part 2, a separate deliverable). Migration of the existing 5 "What to check" items into per-lens sections (a documentation restructure with no behavioral change). Sourcing the keyword list from a config file (deferred — see OQ-001). A telemetry counter that validates the lens fires in practice (deferred — see OQ-002). A config kill switch for the lens (DF-027, deferred per RS-018). An ABS catalog entry for `<UNTRUSTED_*>` fences (DF-028, deferred per RS-019 — to be addressed in a separate /carchitect cycle). Extending TB-005 in ARCHITECTURE.md to model the self-referential trust loop (RS-010 closed via marker-validity contract above; the architectural model amendment is deferred). Any change to the reviewer's tool surface or to TB-005's read-only invariant.

## Complexity Budget

- **Estimated LOC**: ~320 (60 LOC agent prompt — lens body + data-treatment prose extension + bounded scope + marker-validity contract + round-added downgrade language; 140 LOC structural test — sub-assertions + cardinality checklist + SKIP sentinel + remediation message; 15 LOC dedicated pre-push test `scripts/check-no-pending-sfg-lift.sh`; 35 LOC /caudit Step 6a — fence emission with byte-accurate size-cap algorithm + JSON-array form; 50 LOC prompt-composition fixtures — 3 diffs + driver + assertions; 15 LOC sync/restore housekeeping; 5 LOC sentinel file lifecycle)
- **Files touched**: ~8 (`agents/fix-diff-reviewer.md`, `correctless/agents/fix-diff-reviewer.md` via sync, `tests/test-fix-diff-reviewer-agent.sh`, `scripts/check-no-pending-sfg-lift.sh` — NEW dedicated pre-push test, `tests/fixtures/fix-diff-class-shaped-*.diff` — 3 new files in a new fixtures subdirectory, `skills/caudit/SKILL.md` Step 6a, `hooks/sensitive-file-guard.sh` + `correctless/hooks/sensitive-file-guard.sh` lift + restore during PR — final state byte-equal to pre-PR, `.correctless/.sfg-lift-active` — NEW committed sentinel file added by lift commit and removed by restore commit)
- **New abstractions**: 0 (the lens is one section in an existing agent file; the new fence reuses the existing UNTRUSTED_* fence pattern; the SIBLING-DEFERRED marker is a syntax convention, not a new abstraction; the sentinel file is a flag, not a contract)
- **Trust boundaries touched**: 1 (TB-005 — the new fence carries TB-005 data: a prior reviewer round's finding description, untrusted by the consuming reviewer)
- **Risk surface delta**: medium — read-only reviewer prompt addition + functional fixtures + Step 6a fence emission with size cap + bounded sibling scope + marker-validity contract; SFG hook touched during PR but reset to baseline before push with sentinel-mediated SKIP path

## Invariants

### INV-001: Class-shaped bug detection section is present in the agent file
- **Type**: must
- **Category**: functional
- **Statement**: `agents/fix-diff-reviewer.md` contains a level-2 or level-3 heading matching the regex `^#{2,3}[[:space:]]+.*class-shaped` (case-insensitive). The section body is non-empty and appears before the "Output contract" section.
- **Boundary**: ABS-010 (Plugin-agent file contract)
- **Violated when**: the heading is absent, misspelled, demoted below the "No verbatim content" section, or the section body is empty
- **Enforcement**: CI test assertion in `tests/test-fix-diff-reviewer-agent.sh` (PAT-018 structural mechanism; PAT-015 content-pairing drift test)
- **Guards against**: AP-013 (inline subagent system prompts re-creeping in)
- **Test approach**: unit (structural grep against the agent file)
- **Risk**: medium — without the heading, the lens is silently absent on every fix-round
- **Implemented in**: (GREEN phase)

### INV-002: Two-signal detection — diff content primary, finding description refinement (prose layer)
- **Type**: must
- **Category**: functional
- **Statement**: The lens section instructs the reviewer to detect class-shape using two signals: **(a) primary — diff content**: examine the diff text and surrounding hunk context for patterns that suggest a scope-narrowed instance fix (substitution of pattern X with pattern Y at one site, single-occurrence error-handling additions, loop-variable scope fixes, etc.). The prose includes a non-exhaustive seed list of **code patterns** (not bug-description keywords) the reviewer can recognize in the diff — e.g., `--arg "$var"` substituted with `--rawfile`/`--slurpfile`, `2>/dev/null` additions at one error site, single-site `lock`/`unlock` pairs, etc. **(b) refinement — finding description**: when the `<UNTRUSTED_FINDING_DESCRIPTION>` fence is present (passed by /caudit step 6a in JSON-array form per INV-011), examine each finding's wording for class-shape indicators. Either signal can trigger the lens; both together raise confidence. The seed list is explicitly marked non-exhaustive in the prose. **This invariant is the prose-layer test — INV-013 adds a prompt-composition test layer that constructs synthetic /caudit Step 6a prompts from real fixtures and asserts the assembled text carries the trigger conditions, because substring-grep over the agent file alone cannot verify the assembled prompt is shaped correctly (RS-001).**
- **Boundary**: TB-005 (both signals are untrusted-data inputs; the reviewer applies its own semantic judgment over them)
- **Violated when**: only the seed list is present (no semantic test); only the semantic test is present (no anchoring patterns); the seed list is not marked non-exhaustive; the lens depends on `<UNTRUSTED_FINDING_DESCRIPTION>` being present (must degrade gracefully when absent per PAT-019)
- **Enforcement**: CI test assertion (heading + semantic-test phrase + seed-pattern phrase presence + non-exhaustive marker + graceful-degradation language for absent finding-description fence). **Composed with INV-013 prompt-composition tests** — INV-002 enforces prose composition, INV-013 enforces prompt-composition under real fixtures.
- **Guards against**: AP-024 (hardcoded list goes stale) — the harm mode where the keyword enumeration is class-incomplete by construction
- **Test approach**: unit (prose composition) — paired with INV-013 prompt-composition tests
- **Risk**: high — the harm mode the user flagged (keyword enumeration becoming class-incomplete) materializes silently
- **Implemented in**: (GREEN phase)

### INV-003: Reviewer must grep for sibling instances when the lens is triggered (proximity-anchored, anti-negative)
- **Type**: must
- **Category**: functional
- **Statement**: When the lens is triggered, the prose explicitly directs the reviewer to grep the file under fix and bounded sibling modules (INV-015 scope) for instances of the same pattern. The directive is a **positive imperative sentence** binding "grep" and "sibling" within a single line (≤120 chars), names at least two of the pinned tools `Read`/`Grep`/`Glob` on the same line, and is NOT a hedged or negative sentence.
- **Boundary**: TB-005
- **Violated when**: the sibling-grep step is absent; the directive does not name the tools; "sibling" appears without "grep" within the section body; the matched line begins with negation tokens (`Do NOT`, `never`, `avoid`, `should not`, `may skip`); the imperative is hedged ("you may consider", "if confident")
- **Enforcement**: CI test assertion — section body contains a single ≤120-char line matching `\b(grep|search) .{0,80}\b(sibling|other instances|same pattern)\b` (imperative form) AND the matched line names ≥2 of `{Read, Grep, Glob}` AND the matched line does NOT begin with any negation tokens (anti-negative substring test) AND no hedging modal verbs precede the imperative on that line. Closes RS-012.
- **Guards against**: AP-035 at the call-chain level (gate runs but does not look beyond the failing scope); RS-012 negation-bypass class
- **Test approach**: unit
- **Risk**: high — this directive is the actual behavior change; absence reduces the lens to a slogan
- **Implemented in**: (GREEN phase)

### INV-004: Enumeration carve-out — `SIBLING-DEFERRED:` marker in the diff (with non-exhaustive comment styles)
- **Type**: must
- **Category**: functional
- **Statement**: The lens body specifies a machine-checkable enumeration carve-out: when the diff contains one or more comment lines matching the regex `SIBLING-DEFERRED:\s+\S+(:\d+)?\s+[—-]\s+.+` (literal token `SIBLING-DEFERRED:`, then file-path with optional `:line-number`, separator, then rationale prose — the line-number is genuinely optional, parenthesized in the regex) AND the marker covers each sibling instance the reviewer identifies, AND the marker validity contract (INV-016) is satisfied, the reviewer approves the marker-covered siblings.

  The marker may live in **true syntactic comment forms used in the project's source files (non-exhaustive — examples: `#` (bash/Python/YAML/TOML), `//` (JS/TS/Go/C-family), `--` (SQL/Lua), `/* */` (C-family/CSS), `<!-- -->` (HTML/Markdown/XML), `;` (INI/Lisp/Assembly))**. Python triple-quoted strings (`"""..."""`) are NOT listed as a comment style — they are string literals (sometimes USED as docstrings) and listing them would collide with the marker-in-string-literal bypass class (RS-011 / INV-016d adversarial fixtures). Markers MUST be at the start of a true comment, not inside a string literal value. The prose explicitly states the comment-style list is non-exhaustive.
- **Boundary**: TB-005
- **Violated when**: the carve-out language is absent; the marker token is not pinned (e.g., the prose says "some comment naming siblings" instead of `SIBLING-DEFERRED:`); the regex requires `:line-number` (it must be optional per the prose); the marker does not require per-sibling coverage; the worked example is absent; the comment-style list is presented as closed/exhaustive; `"""` is listed as a comment style (collides with string-literal bypass); the syntactic-comment requirement is missing
- **Enforcement**: CI test assertion — the literal substring `SIBLING-DEFERRED:` appears in the section body; the regex with optional line-number group appears (literal `(:\d+)?` or equivalent); "per-sibling" or "each sibling" coverage language appears; a worked example appears inside a code fence within the section; the comment-style enumeration includes ≥6 styles including `<!-- -->` and `;` but excludes `"""`; "non-exhaustive" or "examples" prose appears within 5 lines of the comment-style enumeration; the prose names "true syntactic comment" or "start of a comment, not inside a string"
- **Guards against**: false positives blocking legitimate scope-limited fixes; AP-024 recurrence in the comment-style list (RS-015)
- **Test approach**: unit
- **Risk**: medium — without the carve-out, the lens generates noise on every disciplined scope-limited fix, undermining its adoption; without a pinned marker token, the carve-out drifts into "reviewer judgment"
- **Note on the marker shape**: pinning `SIBLING-DEFERRED:` as the carve-out token does itself create a small enumeration risk. Mitigation: minimal syntax + non-exhaustive comment styles + INV-016 marker validity contract. Future PRs amending the format must update both the agent prose and the test sub-assertion.
- **Implemented in**: (GREEN phase)

### INV-005: Calibrated HIGH severity for sibling-present findings (with worked-example contrast + aggressive default)
- **Type**: must
- **Category**: functional
- **Statement**: The lens explicitly calibrates the severity output with **a worked example for HIGH and a contrasting worked example for LOW** (RS-001 — abstract labels without contrast are uncalibrated per AP-028). The HIGH example names the conditions: sibling instances exist, are unaddressed, AND are not enumerated with marker-covered rationale. The LOW example names a conservative case for contrast. The section also includes an **aggressive-default directive** ("when in doubt, default to HIGH") matching the PMB-007 prevention pattern. Agent-authored same-commit markers downgrade to MEDIUM per INV-016, not LOW — the calibration explicitly excludes the downgrade case from the LOW examples.
- **Boundary**: TB-005
- **Violated when**: the section does not name `high` as the target severity; only a HIGH example is present (no contrast); the aggressive-default directive is missing; the calibration example is absent
- **Enforcement**: CI test assertion — section body contains ≥1 block matching `(HIGH|severity: high).{0,200}(because|when|example)` AND ≥1 block matching `(LOW|severity: low).{0,200}(because|when|example)` AND a sentence containing one of `(when in doubt|default to|err toward).{0,40}(HIGH|high)`. Composed with INV-013 prompt-composition tests that exercise prompt assembly.
- **Guards against**: AP-028 (uncalibrated severity gate — PMB-007's pattern of agents defaulting to low-friction ratings); RS-001 ceremonial-pass risk on severity calibration
- **Test approach**: unit (prose composition) — paired with INV-013 prompt-composition tests
- **Risk**: medium — without calibration, PMB-007 predicts the reviewer drifts to LOW and the gate degrades silently
- **Implemented in**: (GREEN phase)

### INV-006: Citation of PMB-019 / #144 / PR #124 motivating recurrence (word-boundary anchored)
- **Type**: must
- **Category**: functional
- **Statement**: The lens body cites at least one of `PMB-019`, GH `#144`, or PR `#124` as the motivating recurrence. The citation appears in narrative context (within 80 chars of one of `motivat`, `recurrence`, `prevent`, `ARG_MAX`, `sibling`, `class-shape`, `same shape`), not just as a stray identifier.
- **Boundary**: ABS-010
- **Violated when**: none of the three identifiers appears; the identifier appears only as a stray reference without narrative context
- **Enforcement**: CI test assertion — regex `\bPMB-019\b|\bGH ?#144\b|\bPR ?#124\b` (word-boundary anchored to prevent substring false-positives, RS-021), AND the matched line/context contains ≥1 narrative-context keyword from the list above
- **Guards against**: AP-005 (stale documentation after refactoring); RS-021 substring false-positive class
- **Test approach**: unit
- **Risk**: low — drift without citation does not directly cause bugs, but compounds the cost of evaluating future edits
- **Implemented in**: (GREEN phase)

### INV-007: Structural test enforces all testable invariants from this spec (with cardinality checklist) [integration]
- **Type**: must
- **Category**: functional
- **Statement**: `tests/test-fix-diff-reviewer-agent.sh` contains a check function (named `check_class_shaped_bug_detection` or close variant) that asserts each of INV-001, INV-002, INV-003, INV-004, INV-005, INV-006, INV-009, INV-010, INV-011, INV-012, INV-013, INV-014, INV-015, INV-016, AND INV-017 against the live `agents/fix-diff-reviewer.md`, `skills/caudit/SKILL.md` Step 6a, `hooks/sensitive-file-guard.sh`, `tests/fixtures/fix-diff-class-shaped-*.diff`, and `tests/test-fix-diff-reviewer-agent.sh` files as appropriate. The check function is invoked from the main runner block. Each sub-assertion is a separate PASS/FAIL line.

  **Cardinality checklist (RS-020).** The test contains a hardcoded `EXPECTED_SUB_ASSERTION_IDS` array listing the invariant IDs above (15 base IDs + `INV-012a` for the dedicated pre-push backstop = 16 entries); at the end of the check function it asserts that every ID in the array was exercised (touched by `pass`/`fail`) and that no extra sub-assertion IDs ran. Future PRs adding new invariants (INV-018, INV-019, ...) trigger this cardinality check until the array is updated — a small, low-overhead checklist rather than a spec parser. Closes PMB-013-shape cardinality drift at the test layer.

  (INV-008 is inherited from existing infrastructure and covered by its own existing check function.)
- **Boundary**: ABS-010 (the existing tests are the structural enforcement for the agent contract)
- **Violated when**: the check function is absent; the check function is defined but not called from the runner; any sub-assertion is missing; the cardinality checklist is missing OR the EXPECTED_SUB_ASSERTION_IDS array does not equal the set of testable invariants
- **Test approach**: integration — the test runs the actual structural assertions against the real agent file; entry is `bash tests/test-fix-diff-reviewer-agent.sh`; through is the existing helper functions in `tests/test-helpers.sh` (pass/fail/section); exit is a non-zero exit code on any failed sub-assertion and the failure lines name PMB-019 sub-checks
- **Integration contract**:
  - Entry: `bash tests/test-fix-diff-reviewer-agent.sh` (matches the test runner entrypoint per ABS-023 for the agent-test class)
  - Through: existing `pass`/`fail`/`section` helpers from `tests/test-helpers.sh`; the agent file is read via filesystem with no mocking; the test runs against the actual `agents/fix-diff-reviewer.md` not a fixture (except for INV-013, which uses dedicated `tests/fixtures/fix-diff-class-shaped-*.diff` fixtures)
  - Exit: exit code 0 when the lens section is correctly shaped AND all 15 sub-assertions are exercised; non-zero when any sub-assertion fails OR the cardinality checklist detects a missing/extra ID
- **Enforcement**: the test is itself the enforcement; CI runs it via `commands.test` (the project loops `tests/test-*.sh`); failure halts the test suite per the existing loop's `|| exit 1`. **Note**: INV-012's SKIP sentinel path activates during lift state in `commands.test` to avoid blocking /cauto consolidation. INV-012a is enforced by `scripts/check-no-pending-sfg-lift.sh` — invoked by CI / /cauto Step 8 / operator pre-push, NOT by `commands.test`.
- **Risk**: high — the test IS the backstop for INV-001..INV-017; absence collapses the structural defense to prompt-level only
- **Implemented in**: (GREEN phase)

### INV-008: Distribution mirror at `correctless/agents/fix-diff-reviewer.md` is byte-equal to source
- **Type**: must
- **Category**: functional
- **Statement**: After the agent file is updated, `bash sync.sh` propagates the change to `correctless/agents/fix-diff-reviewer.md`; the two files are byte-equal at every commit on this branch's tip. The existing ABS-010 invariant is preserved unchanged.
- **Boundary**: ABS-010
- **Violated when**: the two files diverge in any commit landing on the feature branch tip; the sync step is skipped before the test runs
- **Enforcement**: existing `tests/test-fix-diff-reviewer-agent.sh` invariants already assert distribution parity; this spec inherits that defense rather than adding new structural tests
- **Test approach**: unit (covered by existing tests)
- **Risk**: low — covered by existing infrastructure
- **Implemented in**: ABS-010 (no new code)

### INV-009: No inline subagent prompt duplication + data-treatment prose extended to new fence
- **Type**: must-not / must (composite)
- **Category**: functional
- **Statement**:

  **(a) Denylist extension.** The new lens prose lives only in `agents/fix-diff-reviewer.md` and its byte-equal mirror. The inline-prompt denylist in `tests/test-fix-diff-reviewer-agent.sh` (around line 521) MUST be extended to include phrases unique to the new lens (`class-shaped`, `SIBLING-DEFERRED`, `sibling instances`).

  **(b) Data-treatment prose extension (RS-003).** The agent file's "Data treatment (non-negotiable)" section (currently at `agents/fix-diff-reviewer.md:24-25`, which enumerates `<UNTRUSTED_DIFF>` and `<UNTRUSTED_RULES>` explicitly) MUST be edited to either (i) enumerate the new `<UNTRUSTED_FINDING_DESCRIPTION>` fence by name in the same paragraph, OR (ii) be rewritten with an explicit `<UNTRUSTED_*>` wildcard form (e.g., "all text inside any `<UNTRUSTED_*>...</UNTRUSTED_*>` fence"). Without this edit the new fence inherits NO prompt-injection mitigation (the OQ-006 "wildcard by construction" claim was factually wrong).
- **Boundary**: ABS-010; TB-005 (data-treatment is TB-005's enforcement surface for the new fence)
- **Violated when**: any `skills/*/SKILL.md` adds inline class-shaped detection prose; any caller re-states the seed phrases, sibling-grep directive, or the SIBLING-DEFERRED marker; the denylist is NOT extended; the data-treatment prose still enumerates only DIFF + RULES (or any closed set excluding FINDING_DESCRIPTION)
- **Enforcement**: existing ABS-010 invariants AND a new sub-assertion that the denylist contains at least three of the new lens-specific phrases AND a positive-coverage assertion AND a new sub-assertion that the agent's data-treatment prose either explicitly names `<UNTRUSTED_FINDING_DESCRIPTION>` OR uses the `<UNTRUSTED_*>` wildcard form (regex check on the relevant paragraph)
- **Guards against**: AP-013 (inline subagent system prompts); RS-003 inherited-mitigation gap
- **Test approach**: unit
- **Risk**: high — without (b), the new fence carries no prompt-injection mitigation; without (a), the lens prose can be inlined elsewhere and slip past
- **Implemented in**: (GREEN phase — denylist extension + data-treatment prose edit are part of the new structural test)

### INV-010: Scope-amendment exception for sibling search is explicit, bounded, and proximity-anchored
- **Type**: must
- **Category**: functional
- **Statement**: The existing agent prose at `agents/fix-diff-reviewer.md:43` declares "the unchanged codebase" out-of-scope. This invariant adds a NARROW exception: when the class-shaped lens is triggered, the reviewer MAY (and MUST) grep unchanged code in (a) the file under fix AND (b) same-directory same-extension sibling modules per INV-015 bounded scope. The exception is NOT a general re-scope.

  **Proximity anchor (RS-013).** The exception clause MUST appear within 5 lines of the original "Out of scope: the unchanged codebase" line, with the literal phrase "EXCEPT" or "exception" linking the two. No level-3 (`### `) heading may separate the original out-of-scope statement from the exception clause. This anchors the conflict resolution at agent inference time — an LLM reading top-down hits both immediately, not the conservative line first then the exception 80 lines later (PMB-014 conservative-reading-default class).

  The agent prose explicitly states "narrow exception for sibling search," names the bounded scope (`file under fix + same-directory same-extension sibling modules`), and explicitly REJECTS the broader re-interpretation ("not the entire codebase", "not `.env*`, `.correctless/preferences*`, `.correctless/artifacts/autonomous-decisions-*`" per INV-015).
- **Boundary**: ABS-010 (agent contract); TB-005 (the reviewer's read-only role)
- **Violated when**: the agent's "Out of scope: the unchanged codebase" line is left unchanged (silent contradiction with INV-003); the exception is stated without bounds (no scope-limit language); the exception is stated as "the codebase" or "the project" rather than "the file under fix + same-directory same-extension sibling modules"; the exception clause is >5 lines from the original out-of-scope line; a level-3 heading separates them
- **Enforcement**: CI test assertion — find the line matching `Out of scope.{0,60}unchanged codebase`, assert the next 5 lines contain `(EXCEPT|exception|carve-out|narrow exception)` AND `(sibling|file under fix)`, AND assert no `^### ` heading appears in those 5 lines. Composed with INV-013 prompt-composition tests (the assembled prompt carries the trigger conditions in a fixture whose diff exhibits the conflict-then-exception sequence the agent file declares).
- **Guards against**: PMB-014 conservative-reading-default; RS-013 prose-conflict-untested
- **Test approach**: unit (paired with INV-013 prompt-composition tests)
- **Risk**: high — without explicit scope amendment AND proximity anchor, the new lens contradicts the existing agent prose and an LLM reading both will pick the more conservative reading on every fix-round
- **Implemented in**: (GREEN phase)

### INV-011: /caudit Step 6a per-round Task invocation emits `<UNTRUSTED_FINDING_DESCRIPTION>` fence in JSON-array form
- **Type**: must
- **Category**: functional
- **Statement**: `skills/caudit/SKILL.md` **Step 6a** invokes the reviewer **once per round** on the unified diff (NOT per-finding — verified against `skills/caudit/SKILL.md:183`; there is no per-finding loop). Step 6a Step 4 (prompt assembly inside Step 6a, after Step 3 enumerates rules and before Step 5's size check) is amended to emit a new fenced section `<UNTRUSTED_FINDING_DESCRIPTION source="round-{N}-findings">` carrying the round-level finding list (the same list /caudit Step 1 produced when triaging specialist agents' findings — the orchestrator has this in hand at Step 6a invocation time).

  **Payload schema.** The fence body is a single JSON array of objects, each with two fields and no others. The `id` is the **upstream specialist-finding ID** (whatever the producing preset assigns — e.g., `HACK-003`, `QA-R1-007`, `PERF-12`, `AUDIT-001`). This is the ID of the originating finding the fix is addressing, NOT a fix-diff-reviewer output ID (the reviewer's own outputs use the `FD-NNN` prefix per the existing JSON output contract; the input fence and the output array are different ID spaces and must not be conflated):
  ```json
  [
    {"id":"HACK-003","description":"<finding description text>"},
    {"id":"QA-R1-007","description":"<finding description text>"}
  ]
  ```

  **Ordering.** Findings are ordered by ascending `id` using a deterministic comparator (lexicographic byte order on the `id` string). Mixed prefixes (`HACK-` and `QA-` in the same array) sort as their UTF-8 byte sequences would; the contract is reproducible-across-replays, not human-priority.

  **Filtering.** Findings whose `description` field is null, empty, or whitespace-only are OMITTED from the array (RS-022). Findings whose `id` appears in the round's resolved-by-prior-round-fix list (the orchestrator's existing dedup logic) are also omitted. Duplicate `id` values (if the round's finding list contains any) are deduplicated keeping the first occurrence.

  **Source of truth.** The orchestrator reads the round-level finding list from the round's audit-findings artifact written by `scripts/audit-record.sh` per ABS-029 (the sole-writer contract for audit findings). The exact path follows the existing convention: `.correctless/artifacts/findings/{preset}/audit-{preset}-{started_at}-round-{N}.json`. If the file is missing (synthetic invocation, checkpoint resumed without the round metadata, future caller that bypasses /caudit's round model, etc.), the fence is OMITTED entirely (no empty array, no placeholder) and the graceful-degradation contract (INV-002 + agent prose) covers the absence. The contract is structurally recoverable — the artifact is on disk per ABS-029, not only in-memory — but the implementation may also accept an in-memory variant if /caudit has the list bound at Step 6a invocation time (the artifact read is the fallback when in-memory binding is unavailable). The spec does NOT require in-memory; the implementation MAY use either source as long as the canonical JSON-array shape is preserved.

  **Fence placement.** Appended in Step 6a's prompt-assembly block after `<UNTRUSTED_RULES>` enumeration and before `<UNTRUSTED_DIFF>` (existing /caudit Step 6a numbering: between its internal Step 3 and Step 5; the new emission is its internal Step 4b). The spec MUST cross-reference the implementation's exact sub-step naming.

  **Graceful degradation.** The reviewer prose for the new lens states explicitly that detection MUST work when the fence is absent (PAT-019) using the diff signal alone. The reviewer parses the JSON array as data, not instructions.
- **Boundary**: TB-005 — the finding descriptions are prior-reviewer untrusted data; the fence carries TB-005-class content
- **Violated when**: the fence is emitted outside Step 6a (e.g., in /caudit pre-Step-6a prose); the reviewer prose treats fence presence as required (hard dependency); the fence is emitted as a singular description rather than JSON array; the array is emitted with non-canonical ordering (not ascending `id`) or extra fields beyond `id`/`description`; the fence is emitted empty rather than omitted when array would be empty; the reviewer's lens fails to fire when the fence is absent
- **Enforcement**: CI test assertion against `skills/caudit/SKILL.md` Step 6a prose (the literal fence name `<UNTRUSTED_FINDING_DESCRIPTION>` appears in Step 6a's prompt-assembly block) AND the JSON-array schema is pinned with literal `{"id":...,"description":...}` form in the prose AND ascending-id ordering is named AND empty/whitespace filtering is named AND empty-array omission is named AND against the agent prose (graceful-degradation with explicit "when absent, use diff signal alone")
- **Guards against**: PAT-019 violations; AP-026 (advisory-prose contract); RS-002 wrong-step placement; RS-006 multi-finding ambiguity; RS-022 empty-description unspecified
- **Test approach**: unit (paired with INV-013 prompt-composition fixtures that exercise the JSON-array form)
- **Risk**: high — without graceful degradation, every caller path without finding-list context fails to trigger the lens; without Step 6a placement, the fence is structurally unimplementable
- **Implemented in**: (GREEN phase)

### INV-012: Hook final-state check — `hooks/sensitive-file-guard.sh` returns to pre-PR baseline (with SKIP sentinel + remediation message)
- **Type**: must
- **Category**: functional
- **Statement**: After the lift-and-restore housekeeping is complete, `hooks/sensitive-file-guard.sh` AND `correctless/hooks/sensitive-file-guard.sh` (the sync.sh mirror) MUST both be byte-equal to their state at the merge-base of the PR. The entry `agents/fix-diff-reviewer.md` MUST be present in the DEFAULTS list of BOTH files at the end of the PR.

  **Sync target correction (RS-004).** `.claude/hooks/` is NOT a sync.sh target — it is a plugin-cache location populated by Claude Code's plugin loader from `correctless/`. The previous "three sync targets" framing was factually wrong. INV-012 enforces only the TWO sync targets (`hooks/` and `correctless/hooks/`). `.claude/hooks/sensitive-file-guard.sh` refreshes from `correctless/hooks/` on plugin reload — covered transitively.

  **SKIP sentinel path (RS-005) + final-state gate.** During iteration the lift state would deliberately fail `commands.test`, blocking `/cauto` consolidation (PMB-018 superset conflict). Resolution uses a **committed sentinel file** that signals iteration is active, paired with a **final/pre-push/CI-only check** that lives OUTSIDE the `commands.test` glob:

  - **Sentinel location**: `.correctless/.sfg-lift-active` — a committed file at the root of `.correctless/` (this path is NOT under any gitignored subdirectory; see `.gitignore:41-49` — gitignored subdirs are `artifacts/`, `decisions/`, `hooks/`, `scripts/`, `meta/`; the root and `specs/` / `ARCHITECTURE.md` / similar are tracked). The earlier draft placed the sentinel under `.correctless/artifacts/` which is gitignored — corrected.
  - **Sentinel content**: single line `lift-active: <feature-name>` (e.g., `lift-active: fix-diff-reviewer-class-shaped-bugs`). Plain text, ≤80 chars, no secrets.
  - **Lift commit** ADDS the sentinel file. **Restore commit** REMOVES it. Both are real tree changes; the sentinel cannot be local-only and silently bypass the gate.
  - **`tests/test-fix-diff-reviewer-agent.sh`**: when `.correctless/.sfg-lift-active` exists, SKIPs the lift-state assertion with the remediation message below. This is iteration ergonomics — operator-friendly, /cauto-friendly. The test runs in `commands.test` (the pre-commit/iteration glob) and SKIPs when the sentinel is present.
  - **Final-state gate (NOT in `commands.test`)**: a dedicated single-purpose script `scripts/check-no-pending-sfg-lift.sh` (deliberately NOT under `tests/` and NOT matching the `tests/test-*.sh` glob — so `commands.test` does NOT pick it up). It FAILS unconditionally when `.correctless/.sfg-lift-active` exists. This script is invoked from:
    - **CI** — added to the CI workflow that gates merge. Source: a single line in the CI config (e.g., a step that runs `bash scripts/check-no-pending-sfg-lift.sh` before merge).
    - **`/cauto` Step 8 consolidation (pre-push)** — `/cauto` invokes this script after the pipeline's test run and before push; failure aborts the push with the restore-step message.
    - **Operator pre-push** — operators running PR consolidation manually invoke `bash scripts/check-no-pending-sfg-lift.sh` before push (documented in the rule file `.claude/rules/sfg-deliverable.md`).
  - **Why this split actually works**: during iteration, only `commands.test` runs; the main test honors the SKIP path; `/cauto` consolidation passes through; the check script is NOT invoked. At the final/pre-push gate, the check script runs and fails if the sentinel is present, blocking push. Iteration is unblocked AND the lift state cannot ship.

  An explicit implementability note: this contract depends on `/cauto` and CI invoking `scripts/check-no-pending-sfg-lift.sh` at the consolidation/pre-push stage. If neither does so AND no operator runs it manually, the sentinel could theoretically ship. The risk surface is documented in R-014 (new); the rule file `.claude/rules/sfg-deliverable.md` is the affordance documentation; structural protection lives in the CI invocation. PMB-018's `commands.pre_push` (when populated) is the natural integration point; if `commands.pre_push` is absent, /cauto Step 8 prose must explicitly call the check.

  **Remediation message (RS-017).** When the lift-state assertion fails (sentinel absent BUT lift state active — i.e., agent path missing from DEFAULTS and no lift was declared), the failure line names AP-037 + procedure:

  > FAIL INV-012: agents/fix-diff-reviewer.md not in hooks/sensitive-file-guard.sh DEFAULTS.
  > AP-037 lift-and-restore detected without sentinel. To resume iteration:
  >   1. Write the sentinel: echo "lift-active: <feature>" > .correctless/.sfg-lift-active
  >   2. Commit the lift change with the sentinel ADD in the same commit.
  > Before pushing, restore the agent path to DEFAULTS and remove the sentinel
  >   in the restore commit. See .claude/rules/sfg-deliverable.md.

  When `scripts/check-no-pending-sfg-lift.sh` fails (sentinel still present at the pre-push gate), the message names the restore step:

  > FAIL: .correctless/.sfg-lift-active exists.
  > A SFG lift commit is in the tree and the restore commit has not landed.
  > Required: restore `agents/fix-diff-reviewer.md` to the DEFAULTS list in
  >   hooks/sensitive-file-guard.sh AND correctless/hooks/sensitive-file-guard.sh,
  >   delete .correctless/.sfg-lift-active, and commit. This must land before push.

  **INV-012a: final-state sentinel absence.** Formal name of the dedicated-script sub-assertion. The final-state backstop is INV-012a, lives at `scripts/check-no-pending-sfg-lift.sh`, and is invoked by CI / `/cauto` Step 8 / operator pre-push — NOT by `commands.test`. Distinct from INV-012's in-iteration SKIP path.
- **Boundary**: TB-001 (sensitive-file-guard); AP-037 (protected asset as deliverable)
- **Violated when**: the final commit on the PR does not restore the agent path to DEFAULTS in EITHER `hooks/` or `correctless/hooks/`; the lift commit is reverted/dropped but the entry is never re-added; the sentinel file `.correctless/.sfg-lift-active` is present in the tree at push time (the dedicated script catches this when invoked from CI/pre-push); the remediation messages are missing/uninformative; the sentinel is placed under a gitignored subdirectory (which would defeat the contract); the dedicated check script is placed under `tests/test-*.sh` (which would put it in `commands.test` and reintroduce the iteration-block contradiction)
- **Enforcement**:
  - **INV-012 (in-iteration)**: CI test assertion in `tests/test-fix-diff-reviewer-agent.sh` — at every `commands.test` run, grep `hooks/sensitive-file-guard.sh` AND `correctless/hooks/sensitive-file-guard.sh` for the exact full line `agents/fix-diff-reviewer.md` (using `grep -Fx` for full-line exact match per AP-032). When `.correctless/.sfg-lift-active` exists, SKIP with the remediation message.
  - **INV-012a (final-state)**: dedicated `scripts/check-no-pending-sfg-lift.sh` — NOT in `tests/`, NOT picked up by the `tests/test-*.sh` glob. Invoked by CI workflow + /cauto Step 8 + operator pre-push. Fails when sentinel present, regardless of any other state.
- **Guards against**: shipping the lift commit to main (silent erosion of SFG protection); RS-005 /cauto consolidation conflict; RS-004 wrong sync-target enumeration; RS-017 unactionable failure message; the prior draft's gitignored-sentinel + bypassable-SKIP combination
- **Test approach**: unit (structural grep + sentinel detection) + dedicated single-purpose test for pre-push
- **Risk**: medium — without the dedicated test, the SKIP path could let lift state ship via local consolidation; the two-test split closes this
- **Implemented in**: (GREEN phase)

### INV-013: Prompt-composition test layer — real fixtures verify the assembled prompt carries the lens conditions
- **Type**: must
- **Category**: functional
- **Statement**: The structural test layer is paired with a **prompt-composition test layer** that constructs a synthetic /caudit Step 6a prompt from real fixtures (via a small new helper, see below) and asserts the constructed text contains the conditions and instructions the lens needs to fire. Three fixtures live in a new `tests/fixtures/` directory:
  - `fix-diff-class-shaped-argmax.diff` — derived from `git show <PR-124-merge-commit>` (PMB-019 motivating recurrence). REAL provenance per PAT-020 (RS-014). One-hunk scope-narrowed fix in a file with ≥2 unaddressed `--arg "$content"` siblings.
  - `fix-diff-class-shaped-loop-var.diff` — synthetic; single-site loop-variable scope fix in a file with sibling loops.
  - `fix-diff-class-shaped-error-handling.diff` — synthetic; single-site `2>/dev/null` addition in a file with sibling error sites.

  The test layer adds a new shell helper `tests/helpers/build-caudit-prompt.sh` (sourced from `tests/test-fix-diff-reviewer-agent.sh` via the existing `tests/test-helpers.sh` import pattern). The helper accepts three inputs — a fixture diff file path, a finding-list JSON file path (may be `/dev/null` for the fence-absent case), and a path-scoped-rules array — and emits the **text** of a synthetic /caudit Step 6a prompt body to stdout. The helper is a static text constructor — it concatenates `<UNTRUSTED_RULES>` + the new `<UNTRUSTED_FINDING_DESCRIPTION>` block (when finding-list is provided) + `<UNTRUSTED_DIFF>` exactly as /caudit Step 6a's prose specifies. No LLM, no orchestrator invocation. The helper is small (~30 LOC) and mirrors INV-011's schema precisely.

  Each fixture is passed through `tests/helpers/build-caudit-prompt.sh` and the resulting assembled prompt text is asserted against the following expectations using existing extraction/assertion helpers from `tests/test-helpers.sh` (e.g., `assert_contains`, `assert_regex_match`, `extract_section`):
  - **(a) Fence presence in canonical form**: the assembled prompt includes the `<UNTRUSTED_FINDING_DESCRIPTION>` fence in the canonical JSON-array form (per INV-011 schema) when the round has a finding list, AND in the correct Step 6a sub-step position (between `<UNTRUSTED_RULES>` and `<UNTRUSTED_DIFF>`).
  - **(b) Fence-absent path**: with the finding list omitted (synthetic invocation), the assembled prompt contains only `<UNTRUSTED_RULES>` and `<UNTRUSTED_DIFF>` and is well-formed — verifying graceful-degradation composition.
  - **(c) Marker-validity test cases visible in the prompt**: the assembled prompt's diff content (inside `<UNTRUSTED_DIFF>`) includes a round-added SIBLING-DEFERRED marker (added as `+` line), a pre-existing SIBLING-DEFERRED marker (visible in file context but NOT in `+` lines), a malformed marker, and a marker-in-string-literal — so the reviewer at inference time has the cases needed to apply the INV-016 contract.
  - **(d) Size-cap composition**: a fixture with a 5KB description in the finding list triggers per-description truncation; the assembled prompt contains the `[truncated: N more bytes]` marker on that entry. A separate fixture with multiple findings exceeding the aggregate cap triggers proportional truncation; the assembled prompt's total byte size is ≤16 KB.

  **Explicit non-claim.** This invariant does NOT claim the reviewer agent actually emits a HIGH finding on these fixtures. That would require a live `Task(subagent_type="correctless:fix-diff-reviewer")` invocation with deterministic-replay infrastructure the test runner does not have. The invariant verifies the assembled prompt is shaped to give the reviewer the conditions and instructions the lens contract requires — necessary, not sufficient. Behavior-level verification is OQ-007 (deferred); R-010 records the limitation.
- **Boundary**: ABS-010 (agent contract); TB-005 (fence assembly is the data-treatment boundary)
- **Violated when**: fewer than 3 fixtures exist; no fixture is derived from a real PR commit (PAT-020 violation); fence-absent assertion missing; marker-validity case set incomplete (must include round-added + pre-existing + malformed + string-literal); size-cap assertions missing; the spec or test description claims the layer verifies reviewer behavior
- **Enforcement**: CI test assertion — the fixtures exist at the named paths; `tests/helpers/build-caudit-prompt.sh` exists and is sourced from the test file; each fixture is processed by the helper to produce a synthetic prompt text; each prompt is asserted against the expectations above using `assert_contains` / `assert_regex_match` from `tests/test-helpers.sh`. The PR-124-derived fixture must contain a commit-hash provenance comment at the top of the file referencing the source commit.
- **Guards against**: RS-001 ceremonial-pass risk on INV-002/005; RS-014 PAT-020 violation; AP-031/AP-032 fixture-format drift class; over-claiming behavior-level coverage from prose-shape assertions
- **Test approach**: integration (real fixture provenance + composition assertions)
- **Risk**: high — without the composition layer, the spec's structural defense collapses to prose-grep over the agent file
- **Implemented in**: (GREEN phase)

### INV-014: Per-fence size cap and truncation behavior (single emitted-bytes model)
- **Type**: must
- **Category**: functional (resource-lifecycle)
- **Statement**: `/caudit` Step 6a emission of `<UNTRUSTED_FINDING_DESCRIPTION>` enforces caps measured on a **single canonical surface — the bytes actually emitted into the prompt**. There is one measurement model: count the bytes that will appear in the assembled prompt text (post-JSON-escape, including all object syntax, key strings, commas, outer brackets, and any truncation markers). Truncation iterates until the emitted bytes fit. No second measurement model is used at any layer.

  **Per-entry cap**: the emitted JSON object for any single finding (`{"id":"<id>","description":"<escaped-description>"}`) MUST be ≤ 4096 bytes when measured as UTF-8 bytes in the final emitted text. The truncation algorithm:

  1. Build the candidate emitted object (escape the description, format as JSON).
  2. Measure its UTF-8 byte length in the emitted form.
  3. If `≤ 4096`: keep as-is.
  4. If `> 4096`: drop one codepoint from the END of the description (where a "codepoint boundary" means: do not split a multi-byte UTF-8 sequence, AND do not leave a partial JSON escape sequence like `\u00`), append `[truncated: N more bytes]` to the description (where N is the count of dropped raw-description bytes), re-escape, re-format, re-measure. Repeat. The loop terminates because each iteration strictly reduces description length; in the worst case the description becomes empty and the entry is `{"id":"<id>","description":"[truncated: NNNN more bytes]"}` (which is bounded by `len(id) + len(truncation marker) + JSON overhead` — always well under 4096 for any reasonable `id`).

  **Aggregate cap**: the emitted JSON array (`[<entry>,<entry>,...]`) MUST be ≤ 16384 bytes when measured as UTF-8 bytes in the final emitted form. The algorithm:

  1. Build the emitted array with all per-entry-capped entries.
  2. Measure UTF-8 byte length of the emitted array text.
  3. If `≤ 16384`: emit.
  4. If `> 16384`: compute per-entry shares proportionally based on current emitted-byte length; re-truncate each entry's description to fit its share using the same per-entry algorithm above; rebuild the emitted array; re-measure. Repeat at most 3 passes. If still over after 3 passes (which can happen with adversarial escape-byte distribution), drop the smallest-emitted-bytes entry from the array; retry the loop. The fence is NEVER omitted just for being large — only when the array would be empty (per INV-011 empty-array omission).
  5. Emit the final array surrounded by fence delimiters.

  **The model in one sentence**: build the emitted text, measure its UTF-8 bytes, truncate until the measurement is at or under cap. The cap applies to the emitted text only; raw description content size is not measured separately.

  **Documentation**: the truncation algorithm is documented in `skills/caudit/SKILL.md` Step 6a prose with the literal numeric caps AND the emitted-bytes model named explicitly ("the emitted JSON byte size", "measured on the final emitted text").
- **Boundary**: AP-039 (unbounded data through bounded medium); TB-005 (fence assembly)
- **Violated when**: no per-entry cap declared; no aggregate cap declared; truncation marker missing; the measurement model is split (e.g., "measure raw description, then escape and emit") — measurement must always be on the emitted bytes; the truncation does not preserve UTF-8 codepoint boundaries or JSON escape sequence boundaries; the algorithm has no termination bound; the size cap allows the prompt to push past /caudit's 100 KB hard ceiling (DD-010); the spec prose enumerates caps but Step 6a does not enforce them
- **Enforcement**: CI test assertion — Step 6a prose contains the literal numeric caps (4096 / 16384 emitted bytes); the emitted-bytes measurement model is named explicitly; a fixture with a 5KB description triggers per-entry truncation and the assembled prompt's emitted JSON object for that entry measures ≤ 4096 bytes; a separate fixture with 5 findings × 5KB descriptions triggers aggregate-level truncation and the assembled prompt's emitted JSON array measures ≤ 16384 bytes; a fixture with adversarial escape-byte distribution (one description full of double-quotes that double in emitted byte size after escaping) verifies the measurement is on the emitted form, not the raw form
- **Guards against**: AP-039 recurrence inside the AP-039 fix (RS-007); silent prompt-truncation at the 100 KB hard ceiling; the split-measurement-model class (measure raw, truncate raw, escape afterwards — produces post-escape sizes that exceed the cap)
- **Test approach**: unit (Step 6a prose) + integration (INV-013 size-cap fixtures including the escape-byte adversarial case)
- **Risk**: high — without a single consistent measurement model, the cap appears enforced but emitted bytes can silently exceed it; adversarial escape-heavy content slips past
- **Implemented in**: (GREEN phase)

### INV-015: Bounded sibling search scope with explicit sensitive-path deny-list
- **Type**: must
- **Category**: security
- **Statement**: The agent prose names the sibling-search scope as **same-directory same-language-extension** modules — bounded, not "obvious sibling" (the latter is judgment-based and widens to anything the reviewer chooses). The prose includes an explicit deny-list that the reviewer MUST NOT Read or Grep regardless of scope:
  - `.env`, `.env.*` (any environment file)
  - `.correctless/preferences*` (project preferences may contain authoring-mode info)
  - `.correctless/artifacts/autonomous-decisions-*` (autonomous decision logs)
  - `.git/objects/**` (raw git blobs)

  The deny-list is non-exhaustive ("examples include...") so it can be extended in future PRs without re-scoping.
- **Boundary**: TB-005 (read-only scope); TB-001 (sensitive-file boundary for the reviewer's Read tool)
- **Violated when**: the agent prose names "obvious sibling" without bounded scope; the deny-list is absent; the deny-list omits any of the four categories above; the deny-list is presented as exhaustive (closed enumeration shape per AP-024)
- **Enforcement**: CI test assertion — section body names "same-directory" AND "same-extension" (or equivalent bounded-scope phrasing) AND contains the literal substrings `.env`, `.correctless/preferences`, `.correctless/artifacts/autonomous-decisions`, and `.git/objects` within the deny-list paragraph AND contains "non-exhaustive" or "examples" within 5 lines of the deny-list
- **Guards against**: RS-009 reviewer Read-tool unbounded (sensitive-file exposure); AP-024 closed-enumeration shape
- **Test approach**: unit
- **Risk**: high — without bounded scope + deny-list, the new lens widens TB-005 to permit reading any filesystem-readable path including secrets
- **Implemented in**: (GREEN phase)

### INV-016: Marker-validity contract — diff-fence only, substantive rationale, round-added downgrade
- **Type**: must
- **Category**: security / functional
- **Statement**: The agent prose codifies the `SIBLING-DEFERRED:` marker validity contract:

  **(a) Diff-fence provenance (RS-010).** Markers are honored ONLY when they appear as syntactic comments in the diff (within `<UNTRUSTED_DIFF>`). Marker-shaped text inside `<UNTRUSTED_FINDING_DESCRIPTION>` (or any other fence) is NEVER honored — that text is prior-reviewer untrusted data, not a carve-out signal. This closes the self-referential trust loop without requiring TB-005 extension.

  **(b) Substantive rationale.** The marker's rationale prose MUST be substantive: minimum 30 characters AFTER the separator, NOT a template/boilerplate phrase. The agent prose names ≥3 reject-as-non-substantive examples: `covered by future PR`, `see notes`, `TODO` (without further context).

  **(c) Round-added markers downgrade (RS-008).** The reviewer detects whether a marker was added in the current round by looking at the diff content — markers appearing as `+` lines (additions) in `<UNTRUSTED_DIFF>` are round-added; markers visible only via `Read`/`Grep` of the file under fix but NOT present in the diff are pre-existing (predate the round). **Round-added markers DOWNGRADE the finding to MEDIUM** (the finding is still emitted, naming the unaddressed siblings explicitly). **Pre-existing markers fully suppress** for the siblings they cover.

  Rationale: this signal is detectable from the reviewer's existing tool surface (Read/Grep/Glob + the diff content already in `<UNTRUSTED_DIFF>`) WITHOUT any commit-author metadata. Commit-author email and `mode: autonomous` markers are NOT exposed to the reviewer — Step 6a passes `git diff <round-start>..HEAD` output only (no commit messages, no author info). An earlier draft of this invariant relied on author metadata; corrected per the round-diff-visibility model. Human supervision (the affordance the prior framing tried to preserve) becomes a `pre-existing-marker` workflow: a human signs off on the carve-out in a separate commit BEFORE the scope-narrowed fix commit lands; the reviewer sees that marker as pre-existing and honors full suppression.

  **(d) Adversarial fixtures (RS-011).** INV-013 prompt-composition fixtures include adversarial marker shapes: marker inside string literal, marker inside markdown code fence (wrong-language comment), marker-shaped text in finding description, round-added marker with substantive rationale, pre-existing marker (in pre-diff file content only). The fixtures verify the marker-validity contract is exercised — the assembled prompt's marker handling matches the agent prose contract.
- **Boundary**: TB-005 (data-treatment); ABS-010 (agent contract)
- **Violated when**: marker is honored from any fence other than `<UNTRUSTED_DIFF>`; rationale length floor is absent or <30 chars; the round-added vs pre-existing distinction is absent from the prose; the downgrade rule keys on author/email/`mode: autonomous` metadata (which the reviewer does not receive); adversarial fixtures are absent
- **Enforcement**: CI test assertion — section body names "diff fence only" or equivalent (rejecting marker provenance from FINDING_DESCRIPTION); names "30 characters" or equivalent length floor; names ≥3 reject-as-non-substantive examples; names "round-added" or "appears in the diff" as the downgrade signal with MEDIUM target severity; names "pre-existing" or "predates the round" as the full-suppression signal; INV-013 adversarial-marker fixtures exist (including the round-added vs pre-existing pair); NO author-metadata language appears in the marker-validity prose
- **Guards against**: RS-008 self-excusing risk (closed via round-added downgrade); RS-010 self-referential trust loop; RS-011 marker comment-parsing class; reviewer reaching for metadata it does not possess
- **Test approach**: unit (prose composition) + integration (INV-013 adversarial fixtures)
- **Risk**: high — without the contract, the carve-out is the least-friction bypass path
- **Implemented in**: (GREEN phase)

### INV-017: class_fix field shows verbatim marker example for user discoverability
- **Type**: must
- **Category**: ux / functional
- **Statement**: The lens prose directs the reviewer to include a verbatim sample marker line in the `class_fix` field of every triggering finding. The sample must be (a) syntactically valid per INV-004 regex, (b) annotated as an example (e.g., `Example marker: # SIBLING-DEFERRED: scripts/lib.sh:42 — covered by separate scope-widening PR`), (c) include both file:line and rationale prose. This makes the marker syntax discoverable at the moment of need — the operator sees the example inline in the HIGH finding rather than having to find it in agent prose.
- **Boundary**: TB-005 (reviewer output contract); ABS-010 (agent contract)
- **Violated when**: the lens prose does not name `class_fix` as the field containing the marker example; the example is not verbatim (e.g., "include a marker like" without a literal sample); the marker example is malformed
- **Enforcement**: CI test assertion — section body contains "class_fix" within 10 lines of "marker" AND contains a verbatim marker line matching the INV-004 regex within a code fence or quoted block AND the example contains "Example marker:" or equivalent annotation
- **Guards against**: RS-016 user discoverability gap
- **Test approach**: unit
- **Risk**: medium — without discoverability, the first hit on the new lens leaves the operator stuck
- **Implemented in**: (GREEN phase)

## Prohibitions

### PRH-001: No new tools added to the agent's frontmatter
- **Statement**: The lens addition does not grow the agent's `tools:` allowlist. The current allowlist `Read, Grep, Glob` remains exact. No `Bash`, no `Edit`, no `Write`, no `Task`.
- **Detection**: existing `tests/test-fix-diff-reviewer-agent.sh` `check_tools_set_equality` already asserts the tool set; spec inherits the defense
- **Consequence**: violates TB-005 read-only invariant; the reviewer gains a surface it has been explicitly designed not to have; AP-034 (shared mutable substrate across parallel adversarial subagents) becomes reachable

### PRH-002: No semantic detection without anchoring seed phrases, no seed phrases without semantic test
- **Statement**: The lens must NOT be implemented as a hardcoded keyword list alone (AP-024-shape, harm mode 2 in the brainstorm). The lens must NOT be implemented as a free-floating semantic instruction without anchoring phrases (provides the reviewer no grounding).
- **Detection**: INV-002's CI test asserts both the semantic-test phrase and the seed-list phrases AND the non-exhaustive marker are present
- **Consequence**: the keyword-only path produces a class-incomplete enumeration that silently misses new class shapes; the semantic-only path produces inconsistent rulings that depend on reviewer mood

### PRH-003: The seed keyword list must be explicitly marked non-exhaustive in the prose
- **Statement**: The seed list of trigger phrases (e.g., "overflow", "fail at scale", "exhaust", "race", "deadlock") must appear in the section body with explicit prose indicating it is non-exhaustive (e.g., "examples include", "non-exhaustive seed list", "extend when new class shapes are observed"). The list must NOT be presented as a closed enumeration.
- **Detection**: CI test asserts the phrase "non-exhaustive" or "examples" or "extend" appears within 10 lines of the seed-list phrases
- **Consequence**: a closed enumeration ratchets toward AP-024 — every new class shape becomes a maintenance edit, and missing maintenance edits silently miss bugs

### PRH-004: Lens must not write outside the existing JSON output contract
- **Statement**: The lens does not introduce a new output format, a new finding ID prefix, or a side-channel artifact. Findings continue to use the `FD-NNN` prefix and the existing object schema (id, severity, title, description, evidence, impact, location, instance_fix, class_fix).
- **Detection**: existing `tests/test-fix-diff-reviewer-agent.sh` Output-contract checks assert the schema; spec inherits the defense
- **Consequence**: a parallel output format would force orchestrator changes and fork the consumer contract; the reviewer's value comes from the orchestrator parsing its output with `jq -e .`

## Boundary Conditions

### BND-001: Small-diff case — class-shape is not bounded by diff size
- **Boundary**: ABS-010 (the reviewer's input is the diff via `<UNTRUSTED_DIFF>` fence)
- **Input from**: orchestrator-passed diff content (possibly minimal — one-hunk fix)
- **Validation required**: the lens fires on the diff content's code-pattern signal (INV-002 primary signal) and, when the `<UNTRUSTED_FINDING_DESCRIPTION>` fence is present, on the finding-description refinement signal — NOT on diff size and NOT on commit messages (commit messages are not in the reviewer's input). A one-hunk fix in a file with 12 untouched class-shaped sibling sites still triggers the lens on the diff signal alone.
- **Failure mode**: if the lens only fires when the diff is large or only when the finding-description fence carries a class-shape keyword, scope-narrowed instance fixes (the exact PMB-019 shape) sneak past — this would be regression-of-the-fix

### BND-002: SFG lift-and-restore with sentinel-mediated SKIP
- **Boundary**: TB-001 (sensitive-file-guard hook) and AP-037 (protected asset as deliverable)
- **Input from**: the diff includes "Lift SFG protection for X" / "Restore SFG protection for X" commits because the agent file is itself SFG-protected (AP-037 collision is real on this PR)
- **Validation required**:
  - **(a) Sentinel file (INV-012)**: the operator (or `/cauto` orchestration when implemented) writes `.correctless/.sfg-lift-active` (a committed file at the root of `.correctless/`, NOT under any gitignored subdirectory) AS PART OF the lift commit. During iteration, the structural test `tests/test-fix-diff-reviewer-agent.sh` (which IS in `commands.test`) SKIPs the lift-state assertion when the sentinel exists, with a remediation message naming AP-037 + procedure. The restore commit removes the sentinel. The dedicated final-state check `scripts/check-no-pending-sfg-lift.sh` (which is NOT in `commands.test`) is invoked by CI / `/cauto` Step 8 / operator pre-push — when the sentinel exists at the final gate, it fails, providing the non-skippable backstop (INV-012a). Closes RS-005 /cauto consolidation conflict AND the local-bypass-with-sentinel-present gap that the prior draft enabled, without reintroducing the iteration-blocked-by-final-state-check contradiction.
  - **(b) Lens-trigger scoping**: the lens is described as triggering on bug-fix commits, not on workflow-scaffolding commits. The agent prose names lift-and-restore as out-of-scope for the lens, OR the orchestrator's call to the reviewer (/caudit step 6a) already excludes scaffolding commits via the diff scope.
- **Failure mode**:
  - **Without sentinel**: the reviewer fires the lens on a "restore" commit and produces a HIGH finding for the lift — false positive noise on the prevention work itself, AND /cauto consolidation stalls because `commands.test` deliberately fails during lift.
  - **With sentinel but missing absence-check (INV-012a)**: the sentinel could remain on push, hiding the lift state — INV-012a's "no sentinel at push time" assertion closes this.

### BND-003: Multi-file fix — sibling-grep extends to bounded same-directory same-extension modules
- **Boundary**: ABS-010 (single agent file scope)
- **Input from**: fix may touch multiple files; class-shaped pattern may exist beyond just the touched files
- **Validation required**: the prose names "the file under fix AND same-directory same-language-extension sibling modules" (INV-015 bounded scope) so the reviewer does not interpret "grep the file" as literally one file, but ALSO does not widen to the entire codebase. The deny-list from INV-015 still applies inside the sibling scope.
- **Failure mode**: an ARG_MAX-shape bug fix in `scripts/build-dashboard.sh` that has a sibling in `scripts/cmetrics.sh` (same directory, same `.sh` extension) is approved because the reviewer only checked the named file — the recurrence-prevention degrades silently. Conversely, if the prose says "obvious sibling" without bounds (the prior wording), the scope is judgment-based and may widen unsafely.

## STRIDE Analysis

### STRIDE for TB-005: Intra-skill agent-to-agent handoff
- **Spoofing**: not applicable — the reviewer is invoked by a single orchestrator, no identity claim
- **Tampering**: prompt-injection in `<UNTRUSTED_DIFF>` OR `<UNTRUSTED_FINDING_DESCRIPTION>` content. The "Data treatment (non-negotiable)" section is **explicitly extended by INV-009(b)** to name the new fence by name OR use the `<UNTRUSTED_*>` wildcard form — the previous OQ-006 "wildcard by construction" claim was factually wrong (the existing prose enumerates DIFF + RULES explicitly). **Self-referential trust loop**: INV-016(a) names that SIBLING-DEFERRED markers are honored ONLY when they appear in `<UNTRUSTED_DIFF>`, never in `<UNTRUSTED_FINDING_DESCRIPTION>` — closes the round-N → round-N+1 amplification path without requiring TB-005 architectural extension. **Self-excusing**: INV-016(c) names the autonomous-mode downgrade — an agent that adds a marker in the same commit as the fix gets a MEDIUM finding (not full suppression). **Marker comment-parsing**: INV-013 adversarial fixtures exercise marker-in-string-literal and marker-in-wrong-language-comment cases through the prompt-composition layer. **Mitigation summary**: (a) data-treatment prose covers all `<UNTRUSTED_*>` fences via INV-009(b); (b) marker provenance is diff-fence-only via INV-016(a); (c) marker self-excusing is downgraded via INV-016(c); (d) finding-description text is data to weigh, not commands to execute (existing); (e) adversarial fixtures verify the composition layer matches the contract (INV-013).
- **Repudiation**: not applicable
- **Information disclosure**: existing "No verbatim content" prohibition continues to apply; **INV-015** adds explicit deny-list for `.env*`, `.correctless/preferences*`, `.correctless/artifacts/autonomous-decisions-*`, `.git/objects/**` — the sibling-search exception cannot widen the reviewer's Read scope to sensitive paths.
- **Denial of service**:
  - **Sibling-grep on large files**: bounded by `Read`/`Grep`/`Glob` per-call output limits; lens prose names same-directory same-extension as primary scope (not "the entire codebase").
  - **Fence payload blowup (AP-039 shape)**: **INV-014 closes** — per-description cap 4 KB, aggregate cap 16 KB, truncation marker. Verified by INV-013 size-cap fixture. The new fence cannot push the prompt past /caudit's 100 KB hard ceiling.
- **Elevation of privilege**: not applicable — no tool surface change (PRH-001)

## Environment Assumptions

### EA-001: ABS-010 propagation remains intact
- **Assumption**: `sync.sh` continues to propagate `agents/*.md` to `correctless/agents/*.md` byte-equal
- **Refs**: ABS-010, ENV-001 (sync.sh existing behavior)
- **Consequence if wrong**: the distribution copy diverges from source; downstream consumers of the plugin see a different reviewer prompt than the source repo

### EA-002: PMB-019 / #144 / PR #124 identifiers remain meaningful citations
- **Assumption**: the GitHub issue numbers and PMB IDs continue to resolve to recoverable context (GitHub does not delete the issues; `.correctless/meta/workflow-effectiveness.json` continues to host PMB-019)
- **Refs**: AP-005 (stale documentation)
- **Consequence if wrong**: the citation in INV-006 becomes a dangling reference, increasing the cost of evaluating future edits but not directly causing bugs

### EA-003: SFG over-match surface remains a known constraint
- **Assumption**: AP-037 / PMB-017 collision shape (SFG over-extracts on Bash command arguments and even path-argument invocations) remains a known, documented constraint that the implementation works around via lift-and-restore; the SFG hook is NOT changed by this feature
- **Refs**: AP-037, PMB-017, #159
- **Consequence if wrong**: if the SFG over-match surface is fixed concurrently (e.g., #171 part 4 lands first), the lift-and-restore step in BND-002 becomes unnecessary scaffolding; the agent file edits could go through Edit/Write directly. Spec language is robust to either outcome (BND-002 names the scaffolding case but doesn't require it)

### EA-004: The existing `check_inv*` test functions continue to enforce ABS-010
- **Assumption**: the existing `tests/test-fix-diff-reviewer-agent.sh` (2200+ lines) continues to enforce the ABS-010 invariants (distribution parity, frontmatter shape, no inline duplication, tool allowlist equality); this spec adds to that infrastructure rather than replacing it
- **Refs**: ABS-010
- **Consequence if wrong**: regressions in the existing tests would compromise the structural defense before this feature can stand on its own

## Open Questions

- **OQ-001**: Should the seed keyword list eventually move to a sourceable config file (e.g., `.correctless/config/class-shaped-keywords.txt`) so it can grow without editing the agent prompt? Out of scope for v1. Revisit when the seed list grows beyond ~15 entries or when a 2nd PMB shape requires extension.
- **OQ-002**: Should a counter track whether the lens fires in practice (e.g., `lens_fired_count` in `.correctless/meta/calibration.json` per audit round)? Out of scope for v1. Revisit if PMB-020 lands within 90 days with a class-shape the lens did not catch.
- **OQ-003**: Should `/creview-spec` Design Contract Checker also flag specs that introduce new reviewer lenses without a corresponding structural test? Out of scope for v1 — separate /carchitect cycle (issue #173 part 5 covers the meta-pattern).
- **OQ-004**: When AP-037 / PMB-017 is structurally resolved (e.g., #171 lands the allowlist primitive), should the lift-and-restore housekeeping be removed? Out of scope for v1 — INV-012 + INV-012a guarantee byte-equal restoration regardless.
- **OQ-005**: Should the `SIBLING-DEFERRED:` marker eventually be promoted to a project-wide convention with its own structural test? Out of scope for v1 — first-instance pattern; revisit if the marker is adopted in 2+ unrelated codepaths.
- **OQ-006**: ~~The `<UNTRUSTED_FINDING_DESCRIPTION>` fence inherits the existing "all `<UNTRUSTED_*>` fences" wildcard data-treatment prohibition.~~ **Closed and superseded** — the spec review (RS-003) verified the existing agent prose enumerates DIFF + RULES explicitly, NOT as a wildcard. INV-009 now explicitly requires the data-treatment prose to be edited to either enumerate the new fence by name OR be rewritten as `<UNTRUSTED_*>` wildcard. The original OQ-006 decision was factually wrong.
- **OQ-007**: Should the project's test runner gain a deterministic agent replay surface (e.g., recorded Task() invocations with golden-output assertions) so behavior-level reviewer tests can replace the prompt-assembly-composition tests in INV-013? Out of scope for v1 — large infrastructure addition. The INV-013 composition test layer is the closest available substitute. Revisit if (a) PMB-020 lands with a class-shape the lens missed AND (b) the prompt-composition layer cannot identify the gap retrospectively.
- **OQ-008**: ABS-xxx entry for `<UNTRUSTED_*>` fence catalog is deferred to DF-028 (RS-019). v1 closes the local inheritance gap via INV-009; the architecture-level abstraction is a separate /carchitect cycle.
- **OQ-009**: Config kill switch for the class-shaped lens (DF-027 / RS-018) is deferred. The SIBLING-DEFERRED carve-out is v1's false-positive mitigation; revisit if a real project hits a noise spiral.

## Risks

- **R-001** — False positives block legitimate fixes. **Mitigation**: INV-004 `SIBLING-DEFERRED:` machine-checkable carve-out + INV-016 marker-validity contract. **Accept after mitigation**.
- **R-002** — Seed list becomes class-incomplete enumeration. **Mitigation**: INV-002 two-signal detection + PRH-002/003 non-exhaustive marker + INV-013 prompt-composition fixtures verify the assembled prompt carries the trigger conditions for class shapes the seed list does not enumerate (the fixtures exercise novel shapes through the semantic-test path). **Accept after mitigation**.
- **R-003** — Reviewer is read-only — cannot enforce, can only surface. **Acknowledge.** Structurally true per TB-005; mitigation lives in the consumer (/caudit step 6a surfaces findings; human/orchestrator is the enforcement layer). **Accept as known limitation**.
- **R-004** — Prompt edit drift silently breaks the new section. **Mitigation**: INV-001..INV-017 enforced by INV-007 structural test (PAT-018) + cardinality checklist (RS-020 mitigated). The test fires on `bash tests/test-fix-diff-reviewer-agent.sh` in `commands.test`. **Accept after mitigation**.
- **R-005** — SFG-collision friction during implementation. **Mitigation**: lift-and-restore pattern with sentinel-mediated SKIP (INV-012). Final-state check ensures lift commits are reversed before push. **Accept** — known cost of editing protected files until #171 ships.
- **R-006** — The new test is itself class-shaped (sub-assertions enumeration). **Mitigation**: INV-007 cardinality checklist asserts `EXPECTED_SUB_ASSERTION_IDS` equals the set of testable invariants (15 base + INV-012a = 16); future PRs adding new invariants trigger the cardinality check until the array is updated. **Accept after mitigation** — RS-020 closes the cardinality gap.
- **R-007** — A future PMB lands whose class shape is NOT in the seed list AND is too novel for the semantic test to catch. **Mitigation**: seed list is non-exhaustive by design (PRH-003); INV-013 prompt-composition tests can be extended with new fixtures matching the missed shape. **Accept** — first-class class shapes by definition cannot be enumerated in advance.
- **R-008** — INV-012's final-state check creates iteration friction. **Mitigation (UPDATED)**: sentinel-mediated SKIP path (INV-012 + INV-012a) lets iteration commits pass while the sentinel exists; the absence of the sentinel at push time is the structural backstop. /cauto consolidation no longer stalls (RS-005 closed). **Accept after mitigation**.
- **R-009** — Consumer change to `/caudit` Step 6a (INV-011) introduces a new dependency. **Mitigation**: INV-002 + INV-011 explicitly require graceful degradation when the fence is absent (diff signal alone suffices), verified by INV-013 fence-absent fixture. **Accept after mitigation**.
- **R-010** — INV-013 prompt-composition tests assert that the assembled prompt carries the conditions for the lens to fire, NOT that the reviewer agent actually fires the lens (the project's test runner has no deterministic agent replay surface). **Mitigation**: composition assertions catch prompt-shape regressions; behavior-layer regressions are caught at /caudit invocation time during real audits; OQ-007 tracks the deterministic-replay surface as a future infrastructure addition. The spec is careful NOT to over-claim ("verify the lens fires") — the assertion is on prompt shape ("verify the prompt contains the conditions and instructions for the lens"). **Accept** — closest available substitute given runner constraints.
- **R-011** — `<UNTRUSTED_FINDING_DESCRIPTION>` content is unbounded by default. **Mitigation**: INV-014 per-fence size cap (4 KB per-description, 16 KB aggregate, truncation marker) with fixture verification. **Accept after mitigation**.
- **R-012** — Reviewer's Read tool surface is unbounded by Claude Code primitive; sibling-search exception could widen TB-005 to sensitive files. **Mitigation**: INV-015 bounded scope + explicit deny-list (.env, preferences, autonomous-decisions, .git/objects) named in agent prose. Not a structural enforcement (the deny-list is prose) but is the strongest available given no tool-allowlist scoping primitive. **Accept after mitigation** with known limitation.
- **R-013** — Marker provenance contract (INV-016) depends on the reviewer correctly distinguishing diff-fence markers from finding-description marker-shaped text. **Mitigation**: agent prose explicitly names the rule; INV-013 adversarial fixtures exercise the composition. Not a hard structural enforcement (LLM judgment is involved) but the spec defends in depth via INV-016(a) + INV-013 fixtures + INV-009 data-treatment prose extension. **Accept after mitigation**.
- **R-014** — INV-012a depends on CI / `/cauto` Step 8 / operator pre-push actually invoking `scripts/check-no-pending-sfg-lift.sh`. If none of those invokers exists or runs, the sentinel could theoretically ship to main. **Mitigation**: the rule file `.claude/rules/sfg-deliverable.md` documents the affordance; CI workflow inclusion is added as part of this PR's deliverable; `/cauto` Step 8 prose names the check (per PMB-018's `commands.pre_push` integration point when available, otherwise as inline prose). **Accept after mitigation** — operators not using /cauto + CI need to know to invoke the script manually. The trade-off (iteration unblocked vs. relying on invokers) is preferred over the alternative (iteration blocked by a non-skippable test in `commands.test`).

## Won't Do

- Restructure the existing "What to check for each hunk" list into per-lens sections (documentation-only refactor; no behavioral change; out of scope).
- Add a config file for the keyword seed list (OQ-001; deferred).
- Add a telemetry counter for lens firings (OQ-002; deferred).
- Add a config kill switch for the lens (DF-027 / RS-018; deferred — SIBLING-DEFERRED carve-out is v1's primary false-positive mitigation).
- Add an ABS-xxx entry for the `<UNTRUSTED_*>` fence catalog (DF-028 / RS-019; deferred to a separate /carchitect cycle — v1 closes the local inheritance gap via INV-009).
- Extend TB-005 in ARCHITECTURE.md to model the self-referential trust loop. **Closed via marker-validity contract (INV-016a — markers honored only from diff fence)** rather than architectural extension — the prose-level contract is the v1 mitigation; architectural extension is deferred.
- Modify `/caudit` orchestration around the reviewer BEYOND adding the new `<UNTRUSTED_FINDING_DESCRIPTION>` fence in Step 6a (INV-011). The invocation path, the Task subagent_type, the 100 KB cap, the parse-fence behavior, the round-abort-on-malformed-JSON semantics, and the `<UNTRUSTED_RULES>` / `<UNTRUSTED_DIFF>` fence semantics are all unchanged.
- Add a deterministic agent replay surface to the test runner (OQ-007; large infrastructure addition; deferred). INV-013 prompt-composition tests asserts prompt-composition as the closest available substitute.
- Modify the SFG hook to allowlist this agent file (AP-037 / #171 part 3 is a separate feature; this spec works around the constraint via lift-and-restore with sentinel SKIP).
- Change the reviewer's tool surface (PRH-001).
- Require human-signing on SIBLING-DEFERRED markers (per user disposition on RS-008 — autonomous-mode downgrade in INV-016c is the v1 mitigation; signing infrastructure is too heavy for the leverage).

## Packages Affected

Not a monorepo. Single package.
