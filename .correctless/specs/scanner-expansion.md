# Spec: Scanner Expansion — Structural Enforcement for High-Recurrence Antipatterns

## Metadata
- **Task**: scanner-expansion
- **Recommended-intensity**: high
- **Intensity**: high
- **Intensity reason**: touches hooks/ (file path signal), guards security-boundary code (AP-001 portability affects all hooks), scanner is a phase-transition script invoked by /ctdd and /cverify
- **Override**: none

## What

Expand `scripts/antipattern-scan.sh` with two new detection categories and add a test audit check to `skills/ctdd/SKILL.md`. The goal: mechanical prevention of two recurring bug classes that documentation-only enforcement has failed to stop.

**Category 1 — AP-001 portability violations:** `grep -P`, `\s`, `\b` in grep patterns, and `\w`/`\d` in ERE mode. AP-001 has recurred 4+ times across 3 audits with 49+ occurrences found in the 2026-04-12 audit. The documentation says "don't use GNU extensions" but new code keeps introducing them.

**Category 2 — Dead-code-in-security-paths:** Functions defined in scripts with a security role (scripts that source lib.sh and handle state/overrides/triage/enforcement) that are never called from any production entry point. The 2026-04-12 audit found `check_override_retry` defined, unit-tested (47 tests), and never called from `cmd_override` — PRH-006 was structurally inert. This is distinct from AP-003 (keyword tests) — the tests are real and the function works, but the production call chain doesn't invoke it.

Both categories produce BLOCKING findings during `/cverify` antipattern scan and are surfaced in the `/ctdd` QA context.

## Rules

- **R-001** [unit]: `check_shell()` in antipattern-scan.sh includes a section (e) that detects `grep -P` in .sh files. Each match produces a finding with pattern ID `gnu-grep-p` and severity `high`.
- **R-002** [unit]: `check_shell()` includes a section (f) that detects `\s`, `\w`, `\d`, `\b` inside grep patterns in .sh files (excluding lines that also contain the corresponding POSIX equivalent: `\s`→`[[:space:]]`, `\w`→`[[:alnum:]]`, `\d`→`[[:digit:]]`, `\b`→`grep -w`). `\s`/`\w`/`\d` matches produce a finding with pattern ID `gnu-grep-ext` and severity `medium`; `\b` matches produce a finding with pattern ID `gnu-grep-ext-low` and severity `low` (more portable but still non-POSIX per AP-001). The exclusion is line-scoped: if the POSIX equivalent appears anywhere on the same line, the finding is suppressed. Known false-negative: a line using both a non-POSIX extension AND a POSIX class for a different extension (e.g., `[[:space:]]\w+`) is suppressed. R-002 only scans grep patterns — `\s`/`\w`/`\d` in sed, awk, or perl regex contexts are out of scope (zero current instances).
- **R-003** [unit]: The `PATTERN_META` lookup table in antipattern-scan.sh includes entries for `gnu-grep-p` (high, portability), `gnu-grep-ext` (medium, portability), `gnu-grep-ext-low` (low, portability — for `\b`), and `dead-security-fn` (high, security-enforcement) with the correct severity, description, and category fields.
- **R-004** [unit]: A new function `check_dead_security_calls()` exists in antipattern-scan.sh. It runs **once after the per-file loop** (not inside it), scanning **all security scripts in the repo** regardless of changed-file scope. **Security scripts** are defined mechanically: scripts in `scripts/` whose filename matches one of `workflow-*.sh`, `*-gate.sh`, `*-guard.sh`, `audit-*.sh`, `review-*.sh`, `override-*.sh`, `*-scrutiny.sh`, `*-mandate.sh`, `*-crosscheck.sh`, `cauto-lock.sh`, `intent-hash.sh`, `auto-policy.sh`, `decision-*.sh`, `security-scan.sh`, `budget-check.sh`, OR scripts explicitly tagged with `# scanner: security` in the first 5 lines. Scripts tagged `# scanner: library` are excluded from dead-call scanning — these are library scripts called by LLM skill orchestrators, not by bash code. However, a library-tagged script that is not referenced by any `skills/*/SKILL.md` file (grep for the script's basename) is still flagged — the tag is not a blanket escape hatch. For each function defined (matching both `name() {` and `function name {` syntax) in non-excluded security scripts, it checks whether any **production file** calls that function. **Production files** are files in `hooks/`, `scripts/`, `setup`, or `bin/` that do NOT match `tests/test-*.sh` or paths containing `/tests/`. Functions with zero production callers produce a finding with pattern ID `dead-security-fn` and severity `high`. Function caller detection uses `grep -rn` with fixed-string or POSIX ERE matching (no `-P`, no `\b`/`\s`/`\w`). Finding descriptions are hardcoded from PATTERN_META per TB-002 — the dead function's name is NOT included in the finding description, only the file path and line number. Hooks/ are excluded from security-script scanning — hooks are self-contained entry points invoked by Claude Code's hook runner, and their internal functions are exercised by their own test suites.
- **R-005** [unit]: `check_dead_security_calls()` excludes functions that are explicitly marked as "pluggable" or "callback" — function names starting with `_default_` or functions with a comment containing `pluggable` or `callback` on the definition line.
- **R-006**: Merged into R-003 (PATTERN_META entries for all new pattern IDs including `dead-security-fn`).
- **R-007** [integration]: When antipattern-scan.sh runs against a test fixture, the JSON output includes findings for all three new pattern IDs. The fixture must include: (a) a file with `grep -P` → produces `gnu-grep-p`, (b) a file with `\s` inside a grep pattern → produces `gnu-grep-ext`, (c) a security script (matching the R-004 path patterns) containing a function that IS called from a test file but NOT from any production file → produces `dead-security-fn`. Case (c) specifically tests the "called from test but not production" distinction — the canonical failure class from the 2026-04-12 audit.
- **R-008** [unit]: `skills/ctdd/SKILL.md` test audit prompt includes check 8: "Production call chain (dead-code-in-security-paths)" — for each security-critical invariant (PRH-xxx, INV-xxx with security category), the spec statement should name the production entry point (e.g., "enforced via `check_override_retry` called from `cmd_override`"). The test audit verifies the test exercises the full entry-point → guard chain, not just the guard function in isolation. A test that calls `check_override_retry` directly without going through `cmd_override` is a BLOCKING finding for invariants that specify the call chain. Detection: grep the spec for "called from" or "invoked by" patterns and verify the named entry point appears in the test's call path. **AP-003 acknowledgment**: This rule is an AP-003 instance — testable only by keyword presence in the prompt. The behavioral backstop is R-004 (scanner detection), which mechanically catches the same bug class. Defense in depth: the scanner is mechanical enforcement, check 8 is advisory.
- **R-009** [unit]: `tests/test-test-evasion-antipatterns.sh` includes a content-pairing drift test (following the pattern from test-evasion-antipatterns spec R-009). The test asserts ALL of: (1) `skills/ctdd/SKILL.md` audit blockquote contains a numbered check with anchor phrase "production call chain", (2) `scripts/antipattern-scan.sh` PATTERN_META contains key `dead-security-fn`, (3) `skills/ctdd/SKILL.md` audit blockquote contains the literal string `dead-security-fn`. If any assertion fails, the pairing has drifted.
- **R-010** [unit]: The existing AP-001 entry in antipatterns.md has its Frequency field updated to reflect the 2026-04-12 audit findings (was "5 findings across 2 features", now includes the 49+ occurrences from 5 test files). The `How to catch it` field is updated to reference the scanner enforcement: "Mechanically enforced by `scripts/antipattern-scan.sh` `check_shell()` sections (e) and (f), pattern IDs `gnu-grep-p` and `gnu-grep-ext`." (Follows AP-014's convention of documenting scanner enforcement in `How to catch it`.)
- **R-011** [unit]: A new antipattern entry AP-022 (or next available slot) is added to antipatterns.md for "Dead code in security paths." What went wrong: `check_override_retry` defined, unit-tested (47 tests passed), never called from `cmd_override` — PRH-006 structurally inert. How to catch it: "Mechanically enforced by `scripts/antipattern-scan.sh` `check_dead_security_calls()`, pattern ID `dead-security-fn`. Advisory: `skills/ctdd/SKILL.md` test audit check 8 (production call chain). When adding a new security script that doesn't match R-004 filename patterns, tag with `# scanner: security`." Frequency: 2 findings in 1 feature (qa-audit-2026-04-12 R4).

## Won't Do

- **Full POSIX portability scan** — only catching grep extensions, not sed -i, timeout, or other portability issues. Those are separate candidates.
- **Dynamic call graph analysis** — `check_dead_security_calls` uses static grep, not runtime tracing. May false-positive on variable dispatch (handled by R-005 exclusion) and may false-negative on eval-based calls. Static analysis is sufficient for this codebase.
- **AP-005 automated count verification** — stale README/CONTRIBUTING counts are a doc consistency issue better addressed by a drift test, not the scanner. Deferred.
- **`\s`/`\w`/`\d` in sed/awk/perl** — R-002 scans grep patterns only. The same extensions in sed, awk, and perl are equally non-portable but out of scope. Zero current instances in the codebase. Revisit if external dogfooding surfaces perl/sed patterns.
- **`setup` file (no .sh extension)** — not scanned by R-001/R-002 for portability (no extension → not routed to `check_shell()`). Included as a production caller source for R-004. Stable and well-tested; exclusion is bounded.

## Risks

- **`check_dead_security_calls` is expensive on large codebases**: For each function in security scripts, it greps all production files. In this codebase (~15 scripts, ~7 hooks), that's ~100 grep calls.
  1. Accept (recommended) — the codebase is small, scanner runs at phase transitions (not every edit)
  2. Mitigate — add a configurable skip flag

- **False negatives from variable dispatch**: Functions called via `$supervisor_fn "$args"` won't be detected as having callers since grep looks for the literal function name.
  1. Accept (recommended) — R-005 exclusion covers the known pluggable functions. New pluggable functions must be marked with the convention.
  2. Mitigate — also grep for the function name in variable assignments (`supervisor_fn=function_name`)

- **Transitive dead code**: R-004's flat grep finds direct callers but not transitively dead code. If function A is called by function B in the same file, and B itself has zero external callers, A appears healthy but is transitively dead. Example: `enforce_prh003()` called by `triage_findings_batch()` in the same file — if `triage_findings_batch` has no external callers, `enforce_prh003` is transitively inert. The test audit check (R-008) is the backstop for this class.
  1. Accept (recommended) — document the false-negative. Transitive analysis is a different project.
  2. Mitigate — add one-level transitive checking (out of scope)

- **Unreachable conditional branches**: R-004 detects absence of production callers via grep. It does NOT detect callers inside unreachable conditional branches (e.g., a function is called from `cmd_override` but the conditions to reach that branch are never satisfied). Reachability analysis is out of scope for the scanner; the test audit check (R-008) is the backstop for this class — it verifies tests exercise the full entry-point → guard chain, which would fail if the branch is unreachable.
  1. Accept (recommended) — scanner catches "never called," test audit catches "called but unreachable." Defense in depth.
  2. Mitigate — add branch coverage analysis (out of scope for this spec)

## Open Questions

- ~~**OQ-001**~~: Resolved — narrow scope, pinned mechanically via R-004's path-pattern definition.
