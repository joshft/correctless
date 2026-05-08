# Spec: carchitect Phase 5 — Architecture Maintenance Loop

## Metadata
- **Created**: 2026-05-07T22:15:00Z
- **Status**: approved
- **Impacts**: carchitect-phase-4-review (complementarity notes), carchitect-phase2-spec-awareness (cverify uses same data source), carchitect-phase-3-audit (caudit adherence checker uses same data source)
- **Branch**: feature/carchitect-phase5-maintenance-loop
- **Research**: null
- **Recommended-intensity**: high
- **Intensity**: high
- **Intensity reason**: touches 3 workflow skills (/cverify, /cdocs, /cupdate-arch), modifies the verification report format, affects the /cauto pipeline indirectly; project intensity is high
- **Override**: none

## Context

Phase 4 (just merged) added mechanical compliance checking at PR review time — the Architecture Compliance Agent checks whether a PR diff violates existing ARCHITECTURE.md entries. But if entries silently go stale (renamed paths in `Enforced at`, deleted test files, outdated consumers), the compliance agent either misses real violations or flags false positives. Phase 5 closes the maintenance loop by making the three post-implementation skills actively maintain ARCHITECTURE.md entries: `/cverify` detects stale entries, `/cdocs` updates them, and `/cupdate-arch` validates the full document. Currently `/cverify` has 4 lines of generic architecture prose, `/cdocs` only suggests new entries, and `/cupdate-arch` only scans for undocumented patterns — none detects when a feature invalidates an existing entry.

## Scope

**In scope:**
- `/cverify` Section 3 rewrite: replace 4-line generic prose with structured entry-by-entry adherence checking
- `/cdocs` Section 5 expansion: detect existing-entry staleness before suggesting new entries
- `/cupdate-arch` new step: validate existing entries before scanning for undocumented ones
- Drift-debt integration: all three skills read and surface `drift-debt.json` open items
- Complementarity notes: distinguish each skill's architecture lens from the Phase 4 compliance agent
- Dormant-signal degradation for all new architecture checks (PAT-019)

**Out of scope:**
- New agents — no Architecture Maintenance Agent; checks are embedded in existing skill prompts
- Changes to `/carchitect` (the entry creation skill) or to the Phase 4 Architecture Compliance Agent
- Changes to `drift-debt.json` schema — the existing format already accepts ABS/PAT/TB/ENV IDs in `rule_id`
- Changes to ARCHITECTURE.md structure itself
- Entrypoints YAML (ABS-023) — maintained by `/carchitect`, separate concern
- Changes to `/cauto` pipeline flow — the three modified skills are already in the pipeline

## Complexity Budget
- **Estimated LOC**: ~250 (prompt changes across 3 SKILL.md files + test file + docs)
- **Files touched**: ~7 (3 SKILL.md files, 1 test file, 2-3 docs files)
- **New abstractions**: 0
- **Trust boundaries touched**: 0
- **Risk surface delta**: low

## Rules

### R-001 [unit]: /cverify architecture adherence section replaces generic prose
The existing 4-line architecture prose in `/cverify` Section 3 ("Architecture Compliance and Prohibitions") is replaced with structured entry-by-entry adherence checking instructions. The new section must instruct the agent to:
  (a) extract all ABS-xxx, PAT-xxx, TB-xxx, ENV-xxx entries from `.correctless/ARCHITECTURE.md`,
  (b) get the list of files changed by the feature via `git diff {default_branch}...HEAD --name-only`,
  (c) identify **affected entries** — entries whose `Enforced at`, `Test`, or consumer/path references overlap with changed files,
  (d) for each affected entry: verify `Enforced at` paths exist on disk, verify `Test` paths exist and reference the entry ID, check whether the `Invariant` text conflicts with what the feature changed,
  (e) report findings with severity: path-missing = HIGH, test-ID-missing = MEDIUM, invariant-conflict = MEDIUM, consumers-incomplete = LOW. These severity labels are advisory for /cdocs prioritization — they do not gate /cverify advancement. /cverify always advances to the next phase regardless of architecture adherence findings. Enforcement: prompt-level (non-blocking advisory per PRH-002).

Path extraction guidance: extract file paths by stripping parenthetical annotations (e.g., `scripts/lib.sh (source)` → `scripts/lib.sh`) and backtick formatting. Skip entries that reference non-file entities (e.g., `setup`, function names without file paths). When an entry uses wildcards (e.g., `hooks/*.sh`), verify at least one matching file exists via glob.

The original 4 lines of generic prose ("Does the implementation follow the patterns?" etc.) must not appear in the replacement section.

### R-002 [unit]: /cverify drift-debt surfacing
The new Section 3 includes instructions to read `.correctless/meta/drift-debt.json` and surface open items whose `rule_id`, `description`, or `spec_id` references an architecture entry ID (ABS/PAT/TB/ENV) OR whose `description` references files changed by the feature. Each relevant drift-debt item is included in the verification report. Dormant when `drift-debt.json` is absent, empty, or has no open items (PAT-019).

### R-003 [unit]: /cverify verification report architecture section
The verification report template in `/cverify` includes an "Architecture Adherence" section. The section uses this format contract so /cdocs can reliably parse it:
- Heading: `## Architecture Adherence`
- Per-entry lines: `- {entry-ID}: {status} — {one-line description}` where status is `valid`, `stale`, or `path-missing`
- Drift-debt sub-section: `### Drift Debt` with one line per surfaced item
- Summary line: `{N} entries checked, {M} stale, {K} drift-debt items`
This section appears in the report template shown in the skill file.

### R-004 [unit]: /cdocs existing-entry staleness detection
`/cdocs` Section 5 (".correctless/ARCHITECTURE.md") is expanded to check whether existing ARCHITECTURE.md entries need updating BEFORE suggesting new entries. The instructions must direct the agent to: (a) read the verification report's "Architecture Adherence" section (if it exists) for pre-computed findings, (b) for each entry whose `Enforced at` paths were modified by the feature, check if the entry text still reflects current code, (c) present stale entries to the human one at a time with numbered options:
```
  1. Update (recommended) — modify this entry to reflect current code
  2. Skip — entry is still accurate despite the path change
  3. Log as drift debt — create DRIFT-NNN entry for future resolution

  Or type your own: ___
```

### R-005 [unit]: /cdocs drift-debt resolution prompting
`/cdocs` Section 5 includes instructions to read `.correctless/meta/drift-debt.json` and surface open items. For each open drift-debt item, present the human with resolution options:
```
  1. Resolve now (recommended) — update the affected entry
  2. Keep as debt — defer to a future feature
  3. Close — mark as resolved (the drift was intentional)

  Or type your own: ___
```
Resolved or closed items are updated in `drift-debt.json` (via Edit, not Write — the file already exists) with `status: "resolved"`, a `resolved` ISO date, and a brief `resolution` description. Dormant when `drift-debt.json` is absent or has no open items (PAT-019).

### R-006 [unit]: /cupdate-arch existing-entry validation step
`/cupdate-arch` adds a "Validate Existing Entries" step before the current "Scan for Undocumented Entries" step. For each ARCHITECTURE.md entry, the step checks: (a) `Enforced at` paths exist on disk, (b) `Test` paths exist and reference the entry ID, (c) `Enforced at` paths include all files that actually reference the abstraction as producers or consumers. Entries with broken paths or missing test references are presented to the human one at a time with options:
```
  1. Fix (recommended) — update the entry to reflect current paths
  2. Delete — remove the entry (it's no longer relevant)
  3. Skip — investigate later

  Or type your own: ___
```

### R-007 [unit]: /cupdate-arch drift-debt incorporation
`/cupdate-arch` reads `.correctless/meta/drift-debt.json` and surfaces open items as candidates for entry updates or new entries. Open drift-debt items are presented alongside the "Validate Existing Entries" findings. Dormant when absent or empty (PAT-019).

### R-008 [unit]: Complementarity notes across skills
Each of the three modified skills' architecture sections includes a note explaining what the other skills' architecture checks do:
- `/cverify`: "The Architecture Compliance Agent (Phase 4) checks whether PR diffs violate entries. This section checks the inverse: whether entries need updating after implementation. /cdocs acts on these findings. /cupdate-arch does comprehensive validation."
- `/cdocs`: "/cverify detects stale entries and includes them in the verification report. This section acts on those findings and surfaces drift-debt. /cupdate-arch handles comprehensive entry validation beyond the current feature."
- `/cupdate-arch`: "/cverify detects feature-scoped staleness. /cdocs updates entries for the current feature. This skill validates ALL entries, not just those affected by a single feature."

### R-009 [unit]: Dormant-signal graceful degradation (PAT-019)
All three skills' architecture maintenance instructions include explicit dormant conditions:
- No ARCHITECTURE.md entries: the architecture check is dormant — no error, no warning
- No `drift-debt.json`: drift-debt surfacing is dormant
- No verification report (for /cdocs reading /cverify's output): /cdocs runs its own staleness detection instead of relying on the report
- Empty `Enforced at` or `Test` fields in an entry: skip that entry's path validation

### R-010 [unit]: Phase 4 compliance agent complementarity
The `/cverify` architecture section includes a note distinguishing its maintenance lens ("do entries need updating?") from the Phase 4 Architecture Compliance Agent's violation lens ("does code violate entries?"). The section does NOT duplicate the Phase 4 check types (pattern compliance, abstraction invariant checking, trust boundary enforcement, new pattern introduction). These remain the compliance agent's domain.

### R-011 [unit]: Docs update
`docs/skills/cverify.md`, `docs/skills/cdocs.md`, and `docs/skills/cupdate-arch.md` are updated to describe the architecture maintenance checks added by this feature.

### R-012 [unit]: Test file
`tests/test-carchitect-phase5.sh` exists, covers all rules (R-001 through R-011), and is registered in `workflow-config.json` `commands.test` and `.github/workflows/ci.yml`.

## Prohibitions

### PRH-001: No new agents
- **Statement**: This feature must not introduce a new agent file in `agents/`. The architecture maintenance checks are embedded in existing skill prompts, not delegated to a standalone agent.
- **Detection**: `ls agents/` before and after — no new files.
- **Consequence**: A new agent would need ABS-010 wiring, sync.sh propagation, and test coverage — unnecessary complexity for prompt-level skill modifications.

### PRH-002: /cverify architecture findings are not BLOCKING
- **Statement**: /cverify architecture adherence findings (stale entries, path-missing, consumers-incomplete) must NOT be classified as BLOCKING findings that prevent the feature from advancing. They are reported in the verification report for /cdocs to act on.
- **Detection**: grep /cverify SKILL.md for "BLOCKING" near the architecture adherence section — the word must not appear in that section's finding classification.
- **Consequence**: Making these BLOCKING would force developers to update ARCHITECTURE.md before advancing past /cverify, but /cdocs (which runs after /cverify) is the natural place for entry updates. BLOCKING would create a redundant fix cycle.

### PRH-003: No duplication of Phase 4 check types
- **Statement**: The /cverify architecture section must not include instructions for pattern compliance, abstraction invariant checking, trust boundary enforcement, or new pattern introduction detection. These are the Phase 4 Architecture Compliance Agent's check types and would create overlapping, potentially contradictory findings.
- **Detection**: grep the /cverify architecture section for "pattern compliance", "trust boundary enforcement", "new pattern introduction" — must not appear.
- **Consequence**: Duplicated check types would produce redundant findings during /cauto pipeline runs and confuse maintainers about which skill owns which check.

## Boundary Conditions

### BND-001: Large ARCHITECTURE.md
- **Boundary**: Entry count scaling
- **Input from**: .correctless/ARCHITECTURE.md
- **Validation required**: The /cverify adherence check iterates over extracted entries. With 29+ ABS, 19+ PAT, 6+ TB, and 9+ ENV entries (63+ total as of today), the check must not attempt to validate every entry — only affected entries (those whose paths overlap with changed files).
- **Failure mode**: Performance degradation if all entries are validated regardless of overlap. Mitigation: the overlap filter is the first step, not a post-filter.

### BND-002: drift-debt.json with many open items
- **Boundary**: drift-debt surfacing
- **Input from**: .correctless/meta/drift-debt.json
- **Validation required**: If drift-debt has many open items (10+), all three skills present only items relevant to the current context, not the full list.
- **Failure mode**: Information overload — presenting 10+ drift-debt items to the human during a feature's /cdocs run is unhelpful. Mitigation: filter by relevance to changed files.

## Open Questions

- **OQ-001**: Should `/cupdate-arch` validate entrypoints YAML (ABS-023) in addition to top-level entries? Currently scoped out — `/carchitect` owns entrypoints. But if entrypoints go stale, `/cupdate-arch` is the natural place to catch it. Deferred to Phase 6 (opportunistic integration).

- **OQ-002**: Should the architecture adherence findings feed back into the Phase 4 compliance agent? E.g., if /cverify finds an entry is stale, should the compliance agent skip it in future PR reviews? This would require a "stale" marker mechanism in ARCHITECTURE.md. Deferred — the manual update path (/cdocs fixes the entry) is simpler.
