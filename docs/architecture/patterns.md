# Architecture — Patterns

> Fragment of [.correctless/ARCHITECTURE.md](../../.correctless/ARCHITECTURE.md). Entry headings are indexed in the root document; full bodies live here.

### PAT-002: Separate concerns in hooks
- **Pattern**: One hook per concern
- **Rule**: Each hook handles exactly one responsibility. workflow-gate.sh = phase gating, sensitive-file-guard.sh = file protection, auto-format.sh = formatting, audit-trail.sh = logging. Never merge hooks — they compose via Claude Code's hook runner.
- **Violated when**: A hook is modified to handle a second unrelated concern, or two hooks share runtime state
- **Test**: PRH-004 in sensitive-file-guard spec (architectural review — verify separate files exist)

### PAT-003: Phase-transition scripts
- **Pattern**: Scripts invoked by skills at phase boundaries (not by the Claude Code hook runner)
- **Rule**: Phase-transition scripts: (1) live in scripts/, not hooks/, (2) accept CLI arguments (not stdin JSON), (3) output structured data to stdout, (4) exit 0 always (informational), (5) source scripts/lib.sh for shared utilities
- **Violated when**: A phase-transition script is placed in hooks/, receives stdin JSON, or uses exit codes to gate workflow
- **Test**: R-016 in antipattern-scan tests (script location and conventions)

### PAT-004: Data budget for historical context
- **Pattern**: Skills reading historical artifacts must cap total files read
- **Rule**: (1) Define a max file count budget (default 10 files), (2) sort eligible files by most recent filename, (3) read files until budget reached, skip remaining
- **Violated when**: A skill reads all historical artifacts without a file count check
- **Test**: R-010 in shift-left-review tests (budget instruction presence)

### PAT-005: PostToolUse hook conventions
- **Pattern**: Standard structure for all PostToolUse hooks
- **Rule**: Every PostToolUse hook must: (1) NO `set -euo pipefail` (would cause early abort, violating fail-open), (2) `command -v jq` check with `exit 0` if missing (fail-open, NOT exit 2 like PreToolUse), (3) bulk-parse stdin with single `eval` + `jq -r @sh`, (4) fast-path `exit 0` for non-relevant tools BEFORE any I/O, (5) guard each operation with `|| exit 0` or `|| true`, (6) must ALWAYS exit 0 — PostToolUse hooks are advisory, never gating
- **Violated when**: A PostToolUse hook uses `set -e`, exits non-zero, or fails to guard an operation with `|| exit 0`
- **Test**: R-009 in token-tracking tests (6 static assertions), R-010 (5 fail-open runtime assertions)

### PAT-007: Conditional update path testing (guards AP-002)
- **Pattern**: Testing conditional update paths (migration, upgrade, config changes)
- **Rule**: When a feature has conditional logic based on existing state (e.g., "if config exists, update it; else create it"), both the create and update paths must be tested. The update path is the more dangerous one — it modifies existing state. Test the update path by creating the pre-condition state, running the feature, and verifying the post-condition.
- **Violated when**: Only the create path is tested, and the update path silently corrupts existing data
- **Test**: Per-feature tests that exercise both paths (e.g., R-013 idempotency test in semi-auto-mode)

### PAT-008: Idempotent migration testing (guards AP-004)
- **Pattern**: Testing idempotent operations (setup, scaffolding, migration)
- **Rule**: Idempotent operations must be tested by running them twice. The first run creates state, the second run must leave it unchanged. Test by: (1) run operation, (2) capture state, (3) run operation again, (4) compare state. Any difference is a bug.
- **Violated when**: An idempotent operation silently overwrites user-modified state on re-run
- **Test**: Per-feature idempotency tests (e.g., R-013 setup re-run preserves user markers)

### PAT-006: Hook self-description via metadata headers
- **Pattern**: Compile-time hook metadata convention
- **Rule**: Every hook in `hooks/` that should be auto-registered as a PreToolUse or PostToolUse hook must contain `# HOOK_TYPE: {PreToolUse|PostToolUse}` and `# HOOK_MATCHER: {pipe-separated tool list}` in the first 10 lines. Files without these headers (workflow-advance.sh, statusline.sh) are excluded from auto-registration and handled as hardcoded special cases. Adding a new hook requires only: (1) create the .sh file with headers, (2) no setup code change needed.
- **Violated when**: A new hook is added to hooks/ without metadata headers and is silently not registered, or an existing hook's HOOK_MATCHER drifts from the desired matcher
- **Test**: INV-002 in test-ci-hook-wiring.sh (format validation), QA-002 (matcher drift detection)

### PAT-009: Orchestrator skill conventions
- **Pattern**: Skills that invoke other skills in sequence (meta-skills)
- **Rule**: Orchestrator skills must: (1) use `context: fork` only if single-turn (runs to completion without user input); multi-turn orchestrators with escalation/approval points must NOT use fork (AP-027 / PMB-006), (2) invoke each sub-skill in a fresh context (via Task or equivalent), (3) implement escalation and resumption (R-005, R-016 pattern), (4) emit progress via audit trail entries (R-011 schema), (5) preserve the shared constraint "Never auto-invoke the next skill" — the orchestrator invokes skills; skills do not auto-continue. The orchestrator is the caller, not a constraint modifier.
- **Guards against**: Uncontrolled skill chaining, context exhaustion, missing escalation paths
- **Violated when**: A multi-turn orchestrator uses `context: fork` (user follow-ups route to the main conversation, not back to the fork), an orchestrator modifies shared constraints, or lacks an escalation mechanism
- **Test**: R-007 in semi-auto-mode tests (constraint preservation), R-001 (fork isolation), R-005 (escalation)

### PAT-010: jq `as $var` bindings must be explicitly parenthesized
- **Pattern**: Operator precedence of `as` bindings differs between jq versions
- **Rule**: When binding with `as $var` after any operator (`+`, `-`, `//`, etc.), always wrap the expression in explicit parens: `(EXPR OP VAL) as $var | rest`. Never write `EXPR OP VAL as $var | rest` without parens.
- **Why**: jq 1.8+ parses `(.spec_updates // 0) + 1 as $count | rest` as `((.spec_updates // 0) + 1) as $count | rest`. jq 1.7 (Ubuntu 24.04 default) parses it as `(.spec_updates // 0) + (1 as $count | rest)` — binding `as` to the right-hand operand only. The resulting `0 + object` evaluates at runtime and crashes. Local development with jq 1.8 passes; CI with jq 1.7 fails silently (hook returns non-zero, state unchanged, no visible error).
- **Violated when**: A jq filter contains `EXPR OP VALUE as $var` without surrounding parens on the expression being bound
- **Test**: Static grep check — any `) + ` or `) // ` followed by ` as \$` on the same or next line without enclosing parens is suspect. Runtime: CI runs on jq 1.7 (Ubuntu 24.04), so precedence bugs surface as test failures.

### PAT-011: SHA-256 hash verification chain
- **Pattern**: Immutable artifacts verified via hash-on-create → hash-on-use
- **Rule**: Compute SHA-256 at creation, store hash in workflow state, re-hash and compare before each use. Mismatch → hard stop. Fallback chain: sha256sum → shasum -a 256 → openssl dgst -sha256. No hash tool available → graceful degradation (skip checks), not crash.
- **Violated when**: Artifact accessed without hash check, hash mismatch silently ignored, or missing hash tool causes crash
- **Test**: test-auto-policy.sh (INV-018), test-auto-report.sh (INV-013) — hash compute, tamper detection, enforcement through routing

### PAT-012: Wiring tests over keyword tests (guards AP-003)
- **Pattern**: Tests for integration rules must exercise the real system path
- **Rule**: Tests tagged [integration] must call actual functions/endpoints, not grep for keywords in file content. A test that passes because a keyword appears in a comment is not verifying behavior.
- **Violated when**: An [integration] rule is tested only via file_contains/grep on a skill or agent file
- **Test**: Test audit BLOCKING finding for any [integration] rule with only keyword-presence tests

### PAT-013: Doc-update invariant on refactoring (guards AP-005)
- **Pattern**: Every refactoring that renames or deletes components must include doc updates
- **Rule**: /cdocs must grep all .md files for terms that were renamed/deleted. Stale references are BLOCKING. Every refactoring spec must include a doc-update invariant listing the old names to search for.
- **Violated when**: Code is refactored but docs still reference old names, deleted files, or removed components
- **Test**: /cdocs staleness check; per-feature grep for old names in .md files

### PAT-014: Scanner tag conventions (`# scanner: security`, `# scanner: library`)
- **Pattern**: In-file metadata tags that classify scripts for scanner behavior
- **Rule**: Scripts in `scripts/` can be tagged in their first 5 lines with `# scanner: security` (include in dead-code scanning even if filename doesn't match the security-script patterns in R-004) or `# scanner: library` (exclude from dead-code scanning if referenced by a `skills/*/SKILL.md` file). Tags affect `check_dead_security_calls()` only — they do not influence portability or other scanner checks. A `# scanner: library` tag is not a blanket escape hatch: a library-tagged script that is unreferenced by any skill file is still scanned.
- **Violated when**: A security-critical script outside the R-004 filename patterns is added without a `# scanner: security` tag, causing dead functions to go undetected; or a `# scanner: library` tag is added to suppress findings on a script that has no skill consumer
- **Test**: R-004 in scanner-expansion spec (tag detection logic), R-007 integration fixture (c) and (d)/(e) in test-antipattern-scan.sh

### PAT-015: Content-pairing drift tests (guards AP-005 dual-source drift)
- **Pattern**: When two artifacts must stay in sync (e.g., a scanner pattern ID and a skill prompt check), a drift test asserts both are present and reference each other
- **Rule**: For each pair of artifacts that form a dual-source-of-truth (scanner detection + skill prompt advisory), write a test that asserts: (1) the skill prompt contains the anchor phrase, (2) the scanner contains the pattern ID, (3) the skill prompt contains the literal pattern ID string. If any assertion fails, the pairing has drifted. This is a structural alternative to AP-005 doc-update reviews — the test catches drift mechanically rather than relying on human review. The same pattern applies to writer-side/auditor-side directive pairs: the AP-031 producer-to-artifact reference table is duplicated verbatim between `agents/ctdd-red.md` (writer-side real-fixture directive) and `skills/ctdd/SKILL.md` check 11 (auditor-side fixture provenance check) — both copies must stay in sync.
- **Violated when**: A new scanner pattern ID is added with a corresponding skill audit check, but no content-pairing drift test links them; or one side of a pair is updated without the other
- **Test**: SE-R-009 in test-test-evasion-antipatterns.sh (checks 5/6/7 ↔ AP-016/017/018), SE-R-009 in test-antipattern-scan.sh (check 8 ↔ dead-security-fn), tests/test-ap031-fixture-divergence.sh (ctdd check 11 ↔ agents/ctdd-red.md producer-to-artifact table — check-11 side pinned via R-003 producer-mapping assertions; ctdd-red side currently unpinned, a known partial-coverage gap noted in the ap031 verification advisory — extending R-004's keyword contract to pin the ctdd-red copy would complete the pairing)

### PAT-016: Glob over directory contents — never enumerate (guards AP-024)
- **Pattern**: When installing or processing all files of a single type from a directory, use a glob pattern (`for f in dir/*.sh`) — never a hardcoded enumerated list
- **Rule**: Code that iterates "all files of type X in directory Y" must use a shell glob over Y, not a hardcoded list of filenames. A structural test must verify the count of installed/processed files matches the count of source files. Adding a new file in the source directory must fail the test if the file is not picked up downstream. The structural count-match test is mandatory — a glob alone without the test only catches some failure modes.
- **Why**: PMB-003 — `setup` installed hooks via glob (correct) but installed scripts via a hardcoded 2-file list. The list was correct when written (PR #30, only 2 scripts existed) and silently went stale across 5 PRs that added scripts. 16 of 18 scripts were never installed on user projects. The failure was silent — hooks worked (they source lib.sh from the manifest), but features needing other scripts (cost tracking, dashboard, entrypoints, auto-mode) silently degraded with no error. The test for script installation inherited the same 2-file assumption and passed every time.
- **Guards against**: AP-024
- **Violated when**: a new file in a source directory is silently dropped because the consumer enumerated instead of globbing; an enumerated list grows over time without a count-match test catching the drift; an interpreter list, command allowlist, or similar enumerated security-relevant array goes stale
- **Test**: structural test that compares glob count to consumer's effective list count; CI integration check via `tests/test-scripts-namespace-migration.sh` (and equivalent per-feature where the pattern repeats)

### PAT-018: Structural enforcement over prompt-level instruction
- **Pattern**: Invariants enforced by structural mechanisms rather than prompt-level instructions
- **Rule**: When a spec invariant claims a property (sole writer, phase gating, file protection, immutability), prefer structural enforcement over prompt-level instruction. Acceptable structural mechanisms: allowed-tools restrictions, file permissions via sensitive-file-guard, phase-transition gate preconditions, cryptographic hash verification, static test assertions in CI, tool-pinning in plugin agent frontmatter. Use "prompt-level" as the explicit fallback only when no structural mechanism applies — this makes the choice conscious rather than a default.
- **Violated when**: An invariant states a property but relies solely on prompt-level instruction when a structural enforcement mechanism is available; or the spec author does not explicitly choose between structural and prompt-level enforcement
- **Guards against**: The class of review findings where an invariant claims a property but enforcement is prompt-level only — the invariant holds only as long as the agent follows instructions, with no mechanical backstop
- **Test**: R-001 through R-008 in `tests/test-structural-enforcement-pat.sh`; Design Contract Checker in `/creview-spec` flags invariants with missing or prompt-level-only `Enforcement:` fields

### PAT-019: Dormant-signal graceful degradation
- **Pattern**: Optional data sources degrade to no-op when absent — no error, no warning, no behavioral change
- **Rule**: When a skill reads an optional data source (ARCHITECTURE.md entries, antipatterns.md, qa-findings-*.json, calibration files, drift-debt.json, deferred-findings.json), absence of the file or absence of relevant entries within the file must produce dormant behavior: the signal contributes nothing to the output, no error is raised, no warning is shown, and the skill proceeds normally. The dormant check must happen before any processing of the data source — not as error handling after a failed read. Skill prompts must state the dormant condition explicitly (e.g., "When no TB-xxx entries exist, this step is dormant — no error, no warning").
- **Why**: Correctless skills run on projects at all stages of adoption. A project that hasn't run `/carchitect` yet has no ARCHITECTURE.md entries. A project that hasn't run `/caudit` yet has no qa-findings files. Skills that error or warn on missing optional data punish new users and create noise for projects that don't use every feature. The pattern appears in 15+ locations across `/cspec` (intensity detection, TB matching, pattern detection, calibration), `/caudit` (architecture adherence checker), `/cstatus` (measurement gate, deferred findings backlog), `/cmetrics` (deferred findings trend), `/cauto` (backlog sweep), and `/cdocs` (dormant-gate baseline).
- **Violated when**: A skill errors, warns, or changes behavior when an optional data source is absent; or a skill reads an optional file without first checking whether it exists or has relevant entries; or a new optional data source is added without explicit dormant-condition documentation in the skill prompt
- **Guards against**: Adoption friction from features that assume a fully-configured project; false warnings that train users to ignore skill output; cascading failures when one optional feature's data is missing
- **Test**: Dormant behavior is tested per-feature (e.g., R-002 dormant checks in `tests/test-intensity-detection.sh`, R-004 in `tests/test-carchitect-phase3.sh`). No single cross-cutting test — each feature's test suite verifies its own dormant conditions.

### PAT-020: Fail-closed realpath probe before canonicalization-dependent security checks
- **Pattern**: Security-critical canonicalization that requires the OS-level path resolver must probe for the resolver upfront and fail-closed when unavailable — never silently fall back to a lexical-only normalizer for security-equivalence decisions
- **Rule**: When a script's security posture depends on canonical-path comparison against a sensitive directory (symlink target resolution, path-traversal detection, "is this file actually inside DIR X" decisions), the script must (1) probe for `realpath` (preferred) or `readlink -f` (fallback) at scan-entry / function-entry via a small `_realpath_tool_available` helper; (2) exit non-zero with a stderr advisory naming the missing tool and the affected security check when neither is available; (3) NEVER fall back to PAT-017's `canonicalize_path` (lexical-only) for the OS-level resolution — `canonicalize_path` correctly normalizes path syntax but cannot follow symlink targets. The lexical normalizer and the OS resolver are not interchangeable for security-equivalence: lexical normalization of `.correctless/artifacts/foo.json` whose actual inode is `/etc/passwd` returns the lexical input unchanged. Probe-at-entry is structural enforcement; the alternative — wrapping every comparison in a runtime resolver check — is prompt-level enforcement (PAT-018 violation).
- **Why**: MA2-001 in the prune-scan-slug-aware mini-audit round 2 found that the original implementation silently fell back to lexical canonicalization when `realpath`/`readlink -f` were unavailable. The scanner would then accept a symlink whose lexical path was under `.correctless/artifacts/` even though its actual target escaped the directory. The class also covers any future security script that processes user-controllable file paths under a "must be under DIR X" precondition.
- **Violated when**: A security script's canonical-path comparison silently degrades to lexical-only normalization on missing `realpath`/`readlink -f`; the probe happens after first use instead of at scan-entry; the script uses `canonicalize_path` (PAT-017) for symlink resolution instead of path-syntax normalization
- **Guards against**: Symlink traversal where the lexical path passes the prefix check but the inode escapes the directory; AP-022 class (dead-code-in-security-paths) for the realpath probe being defined but never gating the security check
- **Test**: `tests/test-prune-scan-slug-aware.sh` (INV-010-a/stderr/c/d — symlink/traversal/hardlink fixtures + `_realpath_tool_available` probe). Future security-critical scripts adopting canonical-path comparison must add a parallel structural test asserting the probe fires at entry and fail-closed activates when the resolver is absent.
