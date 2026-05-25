# Spec: Documentation and Artifact Pruning Skill

## Metadata
- **Created**: 2026-05-24T00:15:00Z
- **Status**: draft
- **Impacts**: cauto, cupdate-arch
- **Branch**: feature/cprune-skill
- **Research**: null
- **Recommended-intensity**: high
- **Intensity**: high
- **Intensity reason**: touches ARCHITECTURE.md (hooks/ path pattern), references TB-003 (LLM-generated data moving between docs), antipattern history overlap (AP-005 stale docs — 5 recurrences)
- **Override**: none

## Context

Active documentation (ARCHITECTURE.md, antipatterns.md, CLAUDE.md learnings) and ephemeral artifacts (workflow state files, token logs, QA findings, audit trails) accumulate without any removal mechanism. After 71 features and 57 days, the project has 37 ABS entries, 31 AP entries, 72 specs, and 373 artifact files. Entries whose referenced files have been deleted waste agent context tokens and anchor agents on outdated information. This skill adds `/cprune` — a periodic pruning skill that detects stale entries and orphaned artifacts, archives documentation entries (never deletes), and cleans ephemeral artifacts for branches that no longer exist.

## Scope

**In scope:**
- New skill `skills/cprune/SKILL.md` with two modes: autonomous (low-risk only) and interactive (full report + human confirmation)
- Scanner script `scripts/prune-scan.sh` that mechanically detects staleness candidates
- Archive files: `.correctless/ARCHITECTURE_DEPRECATED.md`, `.correctless/antipatterns-archived.md`
- Integration with `/cauto` pipeline at the `/cupdate-arch` step (autonomous mode)
- Integration with `/cstatus` for pruning-recommended signals
- 9 scan categories: architecture entries, antipatterns, CLAUDE.md learnings, orphaned artifacts, stale deferred findings, AGENT_CONTEXT.md count drift, cross-reference consistency, completed specs, drift debt
- SKILL.md frontmatter: `interaction_mode: hybrid` (autonomous for /cauto, interactive for direct invocation), no `context: fork` (interactive mode is multi-turn per AP-027)
- Archive destination for CLAUDE.md learnings: `.correctless/CLAUDE_LEARNINGS_ARCHIVED.md`
- Persist-before-present: write scan results to `.correctless/artifacts/prune-report-{date}.md` before interactive presentation (AP-029)
- `allowed-tools`: `Read`, `Grep`, `Glob`, `Bash(scripts/prune-scan.sh*)`, `Bash(git*)`, `Bash(sed*)`, `Bash(mkdir*)`, `Write(.correctless/ARCHITECTURE.md)`, `Write(.correctless/antipatterns.md)`, `Write(.correctless/AGENT_CONTEXT.md)`, `Write(.correctless/ARCHITECTURE_DEPRECATED.md)`, `Write(.correctless/antipatterns-archived.md)`, `Write(.correctless/CLAUDE_LEARNINGS_ARCHIVED.md)`, `Write(.correctless/meta/drift-debt.json)`, `Write(.correctless/specs/archived/*)`, `Write(.correctless/artifacts/prune-report-*.md)`, `Edit(.correctless/ARCHITECTURE.md)`, `Edit(.correctless/antipatterns.md)`, `Edit(.correctless/AGENT_CONTEXT.md)`, `Edit(CLAUDE.md)`. Note: `Write(CLAUDE.md)` is intentionally excluded — even interactive mode uses `Edit` for targeted changes

**Out of scope:**
- Pruning skills themselves (skills/ directory structure is stable)
- Pruning agent definitions (agents/*.md)
- Pruning hooks (hooks/ directory is structurally tested)
- Automated CLAUDE.md editing in autonomous mode (too high-risk)
- Pruning committed files (only gitignored/ephemeral artifacts are auto-cleaned)

## Complexity Budget
- **Estimated LOC**: ~500 (scanner script ~250, SKILL.md ~150, tests ~300, archive scaffolding ~20)
- **Files touched**: ~15 (new: skills/cprune/SKILL.md, scripts/prune-scan.sh, tests/test-cprune.sh, .correctless/ARCHITECTURE_DEPRECATED.md, .correctless/antipatterns-archived.md, .correctless/CLAUDE_LEARNINGS_ARCHIVED.md; modified: skills/cauto/SKILL.md, skills/cstatus/SKILL.md, hooks/sensitive-file-guard.sh, .correctless/ARCHITECTURE.md, .correctless/AGENT_CONTEXT.md, CONTRIBUTING.md, sync.sh, skills/chelp/SKILL.md). Note: this feature changes the skill count from 31 to 32 — update all hardcoded "31 skill" references (AGENT_CONTEXT.md x2, README.md x2, CONTRIBUTING.md, docs/skills/index.md, chelp SKILL.md, sync.sh comment, test assertions in tests/test-deferred-findings-backlog.sh)
- **New abstractions**: 1 (ABS-038: archive file contract)
- **Trust boundaries touched**: 1 (TB-003 adjacent — LLM-generated documentation moved between files by a tool that an LLM agent invokes; archive files become a new data source that future features might read)
- **Risk surface delta**: low

## Invariants

### INV-001: Two execution modes
- **Type**: must
- **Category**: functional
- **Statement**: `/cprune` must support two execution modes: (1) **autonomous** — invoked during `/cauto` pipeline at the `/cupdate-arch` step, auto-executes low-risk actions only (orphaned artifact cleanup, AGENT_CONTEXT.md count corrections), logs actions to audit trail, does not pause for confirmation; (2) **interactive** — invoked directly by the user outside a workflow, produces a formatted pruning report with all candidates across all 8 categories, presents each category to the user for disposition before executing any changes.
- **Violated when**: autonomous mode pauses for confirmation, interactive mode auto-executes high-risk actions, or the skill fails to detect which mode it's in
- **Enforcement**: CI test assertion (grep SKILL.md for mode detection logic and autonomous/interactive branching)
- **Test approach**: unit
- **Risk**: medium

### INV-002: Scanner script detects staleness mechanically
- **Type**: must
- **Category**: functional
- **Statement**: `scripts/prune-scan.sh` must accept a `--category` flag (one of: `architecture`, `antipatterns`, `claude-md`, `artifacts`, `deferred`, `counts`, `crossrefs`, `specs`, `driftdebt`) and a `--base` flag for the project root. It sources `scripts/lib.sh` (per ABS-001) for `branch_slug()` and shared utilities. It outputs a JSON array of candidates to stdout. Each candidate has fields: `id` (entry ID or file path), `category` (scan category), `reason` (why it's stale), `risk` (low/medium/high), `dead_refs` (array of file paths that don't exist), `live_refs` (array of file paths that still exist), `bulk_warning` (boolean, true when >50% of entries in the category are candidates — used by BND-002). The script is deterministic — same filesystem + git state produces the same output. Per-category error handling: if a category's data source is missing or unparsable (e.g., jq fails on malformed JSON), that category outputs an empty array and logs a warning to stderr — other categories still run.
- **Violated when**: the script produces non-JSON output, omits the `risk` field, or includes candidates whose referenced files all still exist
- **Enforcement**: CI test assertion (behavioral test with fixture directories)
- **Test approach**: behavioral
- **Risk**: medium

### INV-003: Architecture entry staleness detection
- **Type**: must
- **Category**: functional
- **Statement**: For each ABS-xxx, PAT-xxx, TB-xxx, and ENV-xxx entry in `.correctless/ARCHITECTURE.md`, the scanner extracts file paths using these rules: (1) backtick-quoted code spans matching file path patterns (e.g., `` `scripts/lib.sh` ``), (2) comma-separated entries in `Enforced at` fields parsed as `filepath (optional role)` — strip the role annotation, (3) comma-separated entries in `Test` fields, (4) See-link paths in index-only entries (format: `See \`path/to/file\`.`) — the scanner checks whether the referenced rule file exists, (5) bare paths in `Violated when` fields matching `[a-zA-Z_./-]+\.(sh|md|json|py|ts|js)`. Paths not matching any of these patterns are ignored (prefer false negatives over false positives). Entry boundaries are level-3 headings (`### {TYPE}-{NNN}:`); level-4 sub-entries (`#### {TYPE}-{NNNa}:`) are part of the parent — all references across parent and sub-entries are considered together. An entry is a staleness candidate when ALL extracted file paths are dead (no file exists at any referenced path). Entries with at least one live reference are not candidates. Entries with no extractable file path references at all (pure prose) are not candidates. At least one behavioral test must use a verbatim copy of a real ARCHITECTURE.md entry from the repo (per AP-031).
- **Violated when**: an entry with live file references is flagged as stale, or an entry with all dead references is not flagged
- **Enforcement**: CI test assertion (fixture ARCHITECTURE.md with known dead/live entries)
- **Test approach**: behavioral
- **Risk**: medium

### INV-004: Archive-not-delete for documentation entries
- **Type**: must
- **Category**: data-integrity
- **Statement**: When a documentation entry (ABS-xxx, PAT-xxx, TB-xxx, ENV-xxx, AP-xxx, CLAUDE.md learning) is pruned, it must be moved to the corresponding archive file: `.correctless/ARCHITECTURE_DEPRECATED.md` for architecture entries (ABS/PAT/TB/ENV), `.correctless/antipatterns-archived.md` for antipatterns (AP-xxx), `.correctless/CLAUDE_LEARNINGS_ARCHIVED.md` for CLAUDE.md learnings. The archived entry retains its original ID, full text, and gains an `Archived` field with the date and reason. The archive write MUST complete before the source removal — if the archive write fails, the source entry is preserved unchanged. This ordering ensures that a crash or interruption never results in entry loss. Archive files are committed to the repo (not gitignored).
- **Violated when**: a pruned entry is deleted without being written to the archive, or the archive entry lacks the original ID/text, or the archive file is gitignored, or the source entry is removed before the archive write completes
- **Enforcement**: CI test assertion (verify archive file exists after pruning, verify entry content matches)
- **Test approach**: behavioral
- **Risk**: low

### INV-005: Orphaned artifact cleanup
- **Type**: must
- **Category**: resource-lifecycle
- **Statement**: The scanner identifies artifact files in `.correctless/artifacts/` whose branch slug does not correspond to any branch in `git branch -a` (local + remote). The scanner uses `branch_slug()` from `scripts/lib.sh` (ABS-001) to compute slugs for each branch from `git branch -a`, then compares against slugs extracted from artifact filenames. Artifacts using `task_slug`-based filenames (AP-009 — the project has two slug conventions) are excluded from orphaned detection unless the scanner can reliably reverse-map them. Orphaned artifacts include: workflow state files, token logs, QA findings, audit trails, pipeline manifests, autonomous decision logs, escalation files, and adherence files. These are classified as `risk: low` because they are ephemeral gitignored files for branches that no longer exist. In autonomous mode, orphaned artifacts are deleted (not archived — they are ephemeral, not documentation).
- **Violated when**: artifacts for existing branches are deleted, or artifacts for deleted branches are retained in autonomous mode without logging
- **Enforcement**: CI test assertion (fixture artifacts with known branch slugs; the scanner accepts an optional `--branches-file` argument pointing to a file containing one branch name per line for testing — when absent, runs `git branch -a`)
- **Test approach**: behavioral
- **Risk**: low

### INV-006: AGENT_CONTEXT.md count verification
- **Type**: must
- **Category**: parity
- **Statement**: The scanner verifies counts in `.correctless/AGENT_CONTEXT.md` by comparing stated values against filesystem reality: test file count (`find tests -name 'test-*.sh' | wc -l`), script count (`find scripts -name '*.sh' | wc -l`), skill count (`find skills -mindepth 1 -maxdepth 1 -type d | wc -l`), agent count (`find agents -name '*.md' | wc -l`). Mismatches are classified as `risk: low`. In autonomous mode, mismatches are auto-corrected via `sed` substitution on the specific count value. In interactive mode, mismatches are reported with current vs stated values.
- **Violated when**: the scanner reports a mismatch that doesn't exist, or auto-correction changes the wrong number in the file. The sed substitution must match the count WITH its label (e.g., `31 skills` → `32 skills`), not the bare number — AGENT_CONTEXT.md has multiple numbers in prose and a bare number replacement could match the wrong occurrence.
- **Enforcement**: CI test assertion (fixture AGENT_CONTEXT.md with known wrong counts, including a fixture where the count value appears elsewhere in the file to verify label-anchored matching)
- **Test approach**: behavioral
- **Risk**: low

### INV-007: Cross-reference consistency check
- **Type**: must
- **Category**: data-integrity
- **Statement**: The scanner checks that `Enforced at` and `Violated when` fields in ARCHITECTURE.md entries reference files/skills that exist. For each ABS-xxx entry, extract skill paths from the `Enforced at` field (e.g., `skills/cspec/SKILL.md (consumer)`) and verify the skill directory exists. An entry with stale cross-references but live primary file references is flagged as `risk: medium` (needs cross-ref update, not archiving).
- **Violated when**: stale cross-references are not detected, or a stale cross-reference causes the entry to be archived when only the cross-ref needs updating
- **Enforcement**: CI test assertion (fixture with known stale cross-refs)
- **Test approach**: behavioral
- **Risk**: medium

### INV-008: CLAUDE.md learning staleness detection
- **Type**: must
- **Category**: functional
- **Statement**: The scanner extracts file paths, spec slugs, and feature references from each learning entry in CLAUDE.md's "Correctless Learnings" section. A learning is a staleness candidate when ALL referenced files/specs are dead AND the learning references a specific feature or convention that no longer exists in the codebase. Learnings that describe general principles (no file references) are never candidates. Class-level detection uses the entry title (the `### YYYY-MM-DD —` heading line): titles containing "Convention confirmed", "Convention introduced", or "Postmortem" are class-level and excluded from staleness detection regardless of file reference status — the class transcends the instance. Bare keywords like "always" or "never" in the body text are NOT class indicators (they appear in virtually every entry). CLAUDE.md pruning is `risk: high` — never auto-executed, always requires interactive confirmation. Archive destination: `.correctless/CLAUDE_LEARNINGS_ARCHIVED.md`.
- **Violated when**: a general-principle learning or a class-level learning (Convention/Postmortem) is flagged as stale, or CLAUDE.md is modified in autonomous mode
- **Enforcement**: CI test assertion (grep SKILL.md for autonomous-mode CLAUDE.md exclusion)
- **Test approach**: unit
- **Risk**: high

### INV-009: Completed spec archiving
- **Type**: must
- **Category**: resource-lifecycle
- **Statement**: Specs in `.correctless/specs/` whose corresponding workflow state shows phase `done`, `verified`, or `documented`, AND whose branch has been merged (not in `git branch -a`), AND whose merge date is 30+ days ago are candidates for archiving to `.correctless/specs/archived/` (created via `mkdir -p` if absent). Merge date derivation priority: (1) `git log --all --grep="feature/{spec-slug}" --format=%ci | head -1` (search for branch name, not spec slug — squash-merge commit messages typically contain the branch name), (2) fall back to the workflow state file's `started_at` timestamp as a lower bound, (3) if neither is available, the spec is NOT a candidate (fail-closed — do not archive without a confirmed merge date). The 30-day grace period allows post-merge reference. Spec archiving is `risk: medium` — auto-executed in autonomous mode only for specs 90+ days post-merge, interactive confirmation for 30-90 day specs.
- **Violated when**: a spec for an unmerged branch is archived, a spec less than 30 days post-merge is archived, or a spec whose merge date cannot be determined is archived
- **Enforcement**: CI test assertion (fixture specs with known merge dates)
- **Test approach**: behavioral
- **Risk**: medium

### INV-010: Stale deferred findings detection
- **Type**: must
- **Category**: functional
- **Statement**: The scanner reads `.correctless/meta/deferred-findings.json` and checks each finding with `status: "open"` by verifying the `source_file` field (the review artifact path) against the filesystem. Findings where `source_file` points to a deleted review artifact are staleness candidates. These are classified as `risk: medium` because the finding may describe a pattern that outlives the specific review artifact. `/cprune` is read-only for deferred findings — it reports stale findings but does NOT write status changes. Users should run `/ctriage` to update the status of stale findings to `wont-fix` with resolution "stale — source review artifact deleted." This keeps `/cprune` as a scanner/reporter and avoids adding a 5th writer to ABS-033.
- **Violated when**: a finding with a live source_file is flagged, or /cprune writes to deferred-findings.json
- **Enforcement**: CI test assertion (fixture deferred-findings.json with known dead/live source_file paths; structural test that SKILL.md does not include `Write(.correctless/meta/deferred-findings.json)` in allowed-tools)
- **Test approach**: behavioral
- **Risk**: medium

### INV-011: Antipattern staleness detection
- **Type**: must
- **Category**: functional
- **Statement**: For each AP-xxx entry in `.correctless/antipatterns.md`, the scanner extracts file paths from "How to catch it" and "Frequency" sections. An antipattern is a staleness candidate when ALL referenced test files, scripts, and scanner patterns are dead. Antipatterns describing general classes (e.g., AP-010 "String interpolation of user input into jq filter strings") are never candidates even if specific file references are dead — the class transcends the instance. Class-level detection uses the entry title line (`### AP-xxx:` heading) only, not the body text: titles describing abstract patterns (containing words like "interpolation", "injection", "drift", "silent", "phantom") are class indicators. The body text is NOT checked for keywords — common English words ("every", "always", "never") appear in virtually every AP entry and would make the heuristic a no-op. Test fixture: include an entry with "All" in the body (e.g., "All 65 tests passed") that IS instance-level and SHOULD be flagged when its refs are dead.
- **Violated when**: a class-level antipattern is flagged as stale, or an instance-level antipattern with all dead references is not flagged
- **Enforcement**: CI test assertion (fixture antipatterns with class vs instance entries)
- **Test approach**: behavioral
- **Risk**: medium

### INV-012: /cauto integration — intensity-aware placement
- **Type**: must
- **Category**: functional
- **Statement**: `/cauto` must invoke `/cprune` in autonomous mode as an internal orchestration action (not a canonical pipeline step — excluded from the ABS-031 step name enum, same pattern as Step 7.5 backlog sweep). Integration points vary by intensity: at **high+ intensity**, `/cprune` runs after the `/cupdate-arch` step (Step 6); at **standard intensity**, `/cprune` runs after `/cverify` (Step 5) — since `/cupdate-arch` is skipped at standard, orphaned artifacts and count corrections would otherwise never run. The invocation passes `mode: autonomous` in the Task prompt. `/cprune` executes low-risk actions (orphaned artifact cleanup, count corrections, 90+ day spec archiving) and returns a summary of actions taken. The summary is included in the `/cauto` pipeline summary under a "Pruning" heading. `/cprune` failure is non-blocking — if it fails, the pipeline continues and logs the failure.
- **Violated when**: `/cauto` does not invoke `/cprune` at any intensity, or `/cprune` failure blocks the pipeline, or autonomous mode executes high-risk actions
- **Enforcement**: CI test assertion (grep cauto SKILL.md for cprune invocation at both intensity integration points; verify cprune is NOT in the canonical step name enum)
- **Test approach**: unit
- **Risk**: low

### INV-013: /cstatus pruning-recommended signal
- **Type**: must
- **Category**: functional
- **Statement**: `/cstatus` must run a lightweight staleness check (orphaned artifact count + architecture entry dead-ref count) and surface a "pruning recommended" signal when either: (a) more than 10 orphaned artifact files exist for deleted branches, or (b) more than 3 architecture entries have all-dead file references. The signal text: "Pruning recommended: {N} orphaned artifacts, {M} stale architecture entries. Run `/cprune` to clean up." When `scripts/prune-scan.sh` is not installed (file does not exist at `.correctless/scripts/prune-scan.sh`), this section is dormant per PAT-019 — no error, no warning, no output.
- **Violated when**: the signal fires when conditions are not met, or does not fire when conditions are met, or /cstatus errors when the scanner script is unavailable
- **Enforcement**: CI test assertion (grep cstatus SKILL.md for pruning signal text and threshold values)
- **Test approach**: unit
- **Risk**: low

### INV-014: Drift debt pruning
- **Type**: must
- **Category**: resource-lifecycle
- **Statement**: The scanner checks `.correctless/meta/drift-debt.json` for entries with `status: "resolved"` or `status: "wont-fix"` that are older than 90 days. These are candidates for removal from the active file (resolved debt has served its purpose). In autonomous mode, resolved/wont-fix entries older than 90 days are removed. The removed entries are preserved in the git history (the file is committed).
- **Violated when**: open drift debt entries are removed, or resolved entries less than 90 days old are removed
- **Enforcement**: CI test assertion (fixture drift-debt.json with known dates and statuses)
- **Test approach**: behavioral
- **Risk**: low

### INV-015: Persist-before-present for interactive report (AP-029)
- **Type**: must
- **Category**: data-integrity
- **Statement**: In interactive mode, `/cprune` must write scan results to `.correctless/artifacts/prune-report-{date}.md` BEFORE presenting them to the user. The artifact is the recovery path if the terminal display is interrupted (AP-029/PMB-008). The interactive presentation renders from the artifact, not from in-memory scan results.
- **Enforcement**: CI test assertion (grep SKILL.md for artifact write before presentation)
- **Test approach**: unit
- **Risk**: low

### INV-016: SFG protection for scanner and archive files
- **Type**: must
- **Category**: security
- **Statement**: The following paths must be added to `hooks/sensitive-file-guard.sh` DEFAULTS: `scripts/prune-scan.sh`, `.correctless/scripts/prune-scan.sh`, `.correctless/ARCHITECTURE_DEPRECATED.md`, `.correctless/antipatterns-archived.md`, `.correctless/CLAUDE_LEARNINGS_ARCHIVED.md`. This prevents LLM agents from modifying the scanner's staleness detection logic (which could make live entries look stale) or writing directly to archive files (which could inject fabricated entries with high IDs, blocking future ID allocation per OQ-001).
- **Enforcement**: CI test assertion (grep sensitive-file-guard.sh DEFAULTS for all 5 paths)
- **Test approach**: unit
- **Risk**: medium
- **Guards against**: AP-022 (dead code in security paths)

### INV-017: TB-004c consolidation allowlist update
- **Type**: must
- **Category**: pipeline integration
- **Statement**: The `/cauto` consolidation step (Step 8.1) staging allowlist must include `.correctless/ARCHITECTURE_DEPRECATED.md`, `.correctless/antipatterns-archived.md`, and `.correctless/CLAUDE_LEARNINGS_ARCHIVED.md`. Without these paths, archive changes made during the `/cauto` pipeline are never committed — they appear to work but are lost on next checkout.
- **Enforcement**: CI test assertion (grep cauto SKILL.md Step 8.1 for archive file paths)
- **Test approach**: unit
- **Risk**: medium

### INV-018: Interactive report format and progress visibility
- **Type**: must
- **Category**: functional
- **Statement**: Interactive mode must display progress between categories ("Scanning {category}... found {N} candidates.") and present each category with: (a) category name and candidate count, (b) per-candidate fields: ID, reason, risk level, dead_refs count, (c) confirmation prompt showing the archive destination path (e.g., "Archive ABS-017 to .correctless/ARCHITECTURE_DEPRECATED.md?"), (d) disposition options per category: 1. Execute all (recommended for low-risk), 2. Review individually, 3. Skip this category. Un-archiving is manual — the skill documents this: "To un-archive, copy the entry back from the archive file to the source file."
- **Enforcement**: CI test assertion (grep SKILL.md for progress output, disposition options, archive destination in confirmation)
- **Test approach**: unit
- **Risk**: low

### INV-019: sync.sh skill list update
- **Type**: must
- **Category**: installation
- **Statement**: `sync.sh` must include `cprune` in its skill list (line 130) and update the "All 31 skills" comment to "All 32 skills". Without this, the distribution at `correctless/skills/cprune/` is never created and the Claude Code plugin cannot discover `/cprune`.
- **Enforcement**: CI test assertion (grep sync.sh for cprune in skill list)
- **Test approach**: unit
- **Risk**: low
- **Guards against**: AP-024 (hardcoded file list)

## Prohibitions

### PRH-001: Never permanently delete documentation entries
- **Statement**: Documentation entries (ABS-xxx, PAT-xxx, TB-xxx, ENV-xxx, AP-xxx, CLAUDE.md learnings) must never be deleted. They must always be moved to the corresponding archive file with their original content preserved. The only exception is ephemeral artifacts (token logs, audit trails, workflow state files, pipeline manifests) which are deleted, not archived.
- **Detection**: CI test assertion (grep SKILL.md and prune-scan.sh for archive-write-before-remove ordering)
- **Consequence**: permanent loss of architectural history — the project loses the ability to understand why a pattern existed

### PRH-002: Never modify CLAUDE.md in autonomous mode
- **Statement**: In autonomous mode (`mode: autonomous`), `/cprune` must never read, modify, or suggest changes to CLAUDE.md. CLAUDE.md pruning is interactive-only. The risk of auto-pruning a learning that still has conceptual value is too high — CLAUDE.md is loaded into every conversation context.
- **Detection**: CI test assertion (grep SKILL.md for autonomous-mode CLAUDE.md exclusion)
- **Consequence**: auto-pruning a valid learning silently degrades every future conversation's context quality

### PRH-003: Never archive entries with live file references
- **Statement**: An entry must never be archived if any of its referenced file paths still exist on the filesystem. The "all-dead" criterion is the minimum threshold for staleness candidacy.
- **Detection**: CI test assertion (behavioral test — create entry with one live ref and one dead ref, verify not flagged)
- **Consequence**: archiving a live entry removes documentation for code that still exists, causing AP-005 (stale docs)

### PRH-004: /cprune is read-only for deferred findings
- **Statement**: `/cprune` must never write to `.correctless/meta/deferred-findings.json`. It reports stale deferred findings but does not modify their status. Users run `/ctriage` to update stale findings. This keeps `/cprune` as a scanner/reporter and avoids adding a 5th writer to ABS-033.
- **Detection**: structural test — verify `/cprune` SKILL.md `allowed-tools` does not include `Write(.correctless/meta/deferred-findings.json)`
- **Consequence**: adding a 5th writer to the multi-writer ABS-033 contract without updating the contract creates an invisible write path

## Boundary Conditions

### BND-001: Empty archive files
- **Boundary**: INV-004
- **Input from**: first-ever prune with no prior archive files
- **Validation required**: archive files are created with a header comment explaining their purpose before the first entry is appended
- **Failure mode**: fail-closed — if the archive file cannot be created, the prune operation for that category is skipped with a warning

### BND-002: All entries are stale
- **Boundary**: INV-003
- **Input from**: project where all ARCHITECTURE.md entries reference deleted files
- **Validation required**: the scanner sets `bulk_warning: true` in its JSON output when >50% of entries in a category are candidates. In **interactive mode**, the skill warns "All entries are staleness candidates — this likely indicates a major refactor. Review carefully before archiving." In **autonomous mode**, the skill does NOT switch to interactive mode (which would deadlock the /cauto pipeline per PMB-006). Instead, it skips the high-candidate category with a log entry "{X}% of {category} entries flagged — deferred to interactive /cprune" and includes the count in the autonomous return summary. Surface via `/cstatus` as a recommendation.
- **Failure mode**: autonomous — skip and log; interactive — warn and proceed with per-entry confirmation

### BND-003: No git remote
- **Boundary**: INV-005
- **Input from**: local-only repo with no remote configured
- **Validation required**: orphaned artifact detection falls back to local branches only (`git branch` without `-r`). Warning: "No remote configured — orphaned artifact detection is local-only."
- **Failure mode**: fail-open — artifacts are only cleaned for branches confirmed absent locally

### BND-004: Concurrent /cprune invocations
- **Boundary**: INV-012
- **Input from**: user runs /cprune interactive while /cauto is also running /cprune autonomous
- **Validation required**: /cprune uses its own lockfile (same `cauto-lock.sh` pattern but with a different lock path — `.correctless/artifacts/cprune-lock-{slug}`) to prevent concurrent /cprune invocations. The /cauto pipeline lock already prevents concurrent /cauto runs — the separate /cprune lock prevents only concurrent interactive /cprune invocations. When /cauto invokes /cprune, /cauto's lock is already held (no deadlock risk because they are separate lockfiles).
- **Failure mode**: fail-closed — second /cprune invocation refuses with "Another /cprune is running"

## STRIDE Analysis

### STRIDE for archive file integrity
- **Spoofing**: Archive files are committed to git. No spoofing concern beyond standard git integrity.
- **Tampering**: Archive files could be edited to remove entries. Mitigated by: git history preserves all changes. The archive is a convenience, not a security control.
- **Repudiation**: No concern — the archive provides attribution via git blame.
- **Information Disclosure**: Archive files may contain security-relevant patterns (e.g., archived TB-xxx entries). Mitigated by: the entries were already in ARCHITECTURE.md (committed, public).
- **Denial of Service**: A malicious archive file could grow unboundedly. Mitigated by: entries only enter the archive via the prune skill, which has a finite input set.
- **Elevation of Privilege**: No concern — the archive is documentation, not executable.

## Environment Assumptions

- **EA-001**: `git branch -a` returns all local and remote branches — if the remote is unreachable, only local branches are checked (BND-003 fallback). Refs parent ENV-004 (gh CLI optional).
- **EA-002**: `jq` is available for JSON parsing of deferred-findings.json and drift-debt.json. Refs parent ENV-002.

## Design Decisions

### DD-001: Archive-not-delete for documentation
Documentation entries may have conceptual value beyond their code references. An archived ABS-xxx entry explains why a pattern was introduced, which informs future architectural decisions even if the specific code is gone. Git history preserves the entry regardless, but browsing git log for "why did we have ABS-017?" is friction. The archive file is a browsable index.

### DD-002: Two-mode design over single-mode
Autonomous mode enables /cauto integration without pipeline stalls. Interactive mode provides the full report with human judgment. The risk classification (low/medium/high) determines which actions auto-execute. This avoids a false choice between "always interactive" (can't integrate with /cauto) and "always autonomous" (too risky for documentation).

### DD-003: Risk classification drives mode behavior
- **Low risk**: orphaned artifacts, count corrections, resolved drift debt > 90 days, specs > 90 days post-merge. Auto-execute in autonomous mode.
- **Medium risk**: architecture entries, antipatterns, deferred findings, specs 30-90 days post-merge, cross-reference fixes. Interactive confirmation required.
- **High risk**: CLAUDE.md learnings. Interactive-only, never autonomous.

### DD-004: Scanner script as separate tool from skill
The scanner script (`scripts/prune-scan.sh`) is a standalone tool that produces JSON output. The skill (`skills/cprune/SKILL.md`) orchestrates the scanner, formats the report, and handles the interactive/autonomous branching. This separation enables: (a) the scanner to be used by `/cstatus` for lightweight threshold checks without loading the full skill, (b) testing the scanner independently with fixture directories.

### DD-005: Intensity-aware integration point
At high+ intensity, `/cprune` runs after the `/cupdate-arch` step — architecture docs are being updated anyway, so pruning alongside ensures docs are both accurate (cupdate-arch) and lean (cprune). At standard intensity, `/cupdate-arch` is skipped entirely, so `/cprune` runs after `/cverify` instead — orphaned artifacts and count corrections are low-risk, high-value cleanup that benefits all intensity levels. `/cprune` is an internal orchestration action (like Step 7.5 backlog sweep), not a canonical pipeline step — excluded from the ABS-031 step name enum.

## ABS-038: Archive file contract

- **What**: Three archive files — `.correctless/ARCHITECTURE_DEPRECATED.md` (architecture entries), `.correctless/antipatterns-archived.md` (antipatterns), `.correctless/CLAUDE_LEARNINGS_ARCHIVED.md` (CLAUDE.md learnings). Committed to the repo (not gitignored). Each file has a header comment explaining its purpose, created on first use (BND-001).
- **Sole writer**: `/cprune` (via the SKILL.md orchestrator, not the scanner script — the scanner only detects candidates, the skill executes the archive operations).
- **Consumers**: none currently. Future features that read archived entries must apply TB-003 mitigation (anti-anchoring directive or UNTRUSTED fence) if the data enters agent reasoning context.
- **Invariant**: Only `/cprune` writes to archive files. Archived entries retain their original IDs (OQ-001). New entries in the active file must increment past the highest ID ever used (active + archived). Skills that create new ABS/PAT/TB/AP entries (`/cupdate-arch`, `/cspec`, `/cdocs`) must check the archive files for the highest existing ID. Archive files are SFG-protected (INV-016).
- **Enforced at**: `skills/cprune/SKILL.md` (writer), `hooks/sensitive-file-guard.sh` (SFG protection), `tests/test-cprune.sh` (behavioral tests)
- **Violated when**: a tool other than `/cprune` writes to an archive file; an archived entry's ID is reused for a new active entry; an archive file is gitignored; a consumer reads archived entries without TB-003 mitigation
- **Test**: `tests/test-cprune.sh` — INV-004, INV-016, BND-001
- **Guards against**: AP-005 (stale docs — the archive preserves context), AP-022 (dead code in security paths — SFG protection)

## Autonomous Defaults

When running in autonomous mode (`mode: autonomous` in prompt context), use these defaults:

- **AD-001**: Category selection — scan all 9 categories. For each category, execute only `risk: low` candidates. Skip categories where `bulk_warning: true` (BND-002 safety valve). Rationale: low-risk actions (orphaned artifacts, count corrections) are safe for autonomous execution.
- **AD-002**: Deferred findings — report only (read-only per PRH-004). Include stale finding count in return summary. Rationale: /cprune is a scanner, not a writer for deferred findings.
- **AD-003**: Archive operations — auto-execute for specs 90+ days post-merge. Skip architecture/antipattern/CLAUDE.md archiving (medium/high risk). Rationale: old specs are the lowest-risk documentation to archive.

## Interactive Report Format

When running in interactive mode, the skill must:

1. Write scan results to `.correctless/artifacts/prune-report-{date}.md` (INV-015)
2. Display progress: "Scanning {category}... found {N} candidates."
3. For each category with candidates, present:
   - Category name and total candidate count
   - Per-candidate: ID, reason, risk level, dead_refs count
   - Confirmation prompt showing archive destination: "Archive {ID} to {destination}?"
   - Disposition options: 1. Execute all, 2. Review individually, 3. Skip this category
4. After each category's disposition is confirmed, execute immediately (not batched at end)
5. Final summary: total actions taken, files modified, archive destination paths

## Open Questions

- ~~**OQ-001**~~: **Resolved** — archived entries retain their original IDs. If ABS-017 gets archived and someone later creates a new ABS-017, every cross-reference becomes ambiguous. The archive is a retirement home, not a recycling center. Retained IDs also mean `grep "ABS-017"` finds both the archive entry and any remaining stale references — making cleanup easy. New entries must increment past the highest ID ever used (active + archived).
- **OQ-002**: Should `/cprune` produce a metrics entry (pruning stats over time) for `/cmetrics` to consume? Deferred — can be added later without spec changes.
