# Spec: carchitect Phase 4 — Mechanical Architecture Checks in PR Review

## Metadata
- **Task**: carchitect phase 4 review checks
- **Recommended-intensity**: high
- **Intensity**: high
- **Intensity reason**: file path signal (skills/cpr-review/ in skills/); project floor (workflow.intensity = high)
- **Override**: none

## What

A new plugin sub-agent — "Architecture Compliance Agent" — spawned by `/cpr-review` during its Step 3 (Architecture Compliance). The agent mechanically extracts PAT-xxx, ABS-xxx, and TB-xxx entries from `.correctless/ARCHITECTURE.md` and checks the PR diff against each entry's documented invariant/rule. Findings integrate into `/cpr-review`'s severity-grouped output. This is the review-time complement to Phase 3's audit-time architecture checking — catching violations before merge rather than after implementation. Phase 3 checks the full codebase post-implementation; Phase 4 checks only the PR diff pre-merge.

## Rules

- **R-001** [unit]: `/cpr-review` spawns an Architecture Compliance Agent as a sub-agent during Step 3 (Architecture Compliance). The agent is spawned after Step 2 (Read Project Context) and runs in parallel with Steps 4–8 (security checklist, test coverage, antipattern check, convention compliance, spec alignment). The main agent collects the sub-agent's findings before presenting the final severity-grouped output in "Present Findings." The agent is spawned at all intensity levels — architecture compliance is not gated by intensity.

- **R-002** [unit]: The Architecture Compliance Agent lives at `agents/architecture-compliance-reviewer.md` as a plugin sub-agent per ABS-010 (plugin-agent file contract). The frontmatter specifies `name: architecture-compliance-reviewer`, `tools: Read, Grep, Glob` (read-only — no Write, Edit, or Bash), and `model:` inherits from the parent. `/cpr-review` invokes it via `Task(subagent_type="correctless:architecture-compliance-reviewer")`. The agent's system prompt body includes all extraction and checking instructions from R-003 through R-008.

- **R-003** [unit]: The agent prompt instructs mechanical extraction and diff-scoped checking. The agent must:
  1. Read `.correctless/ARCHITECTURE.md` and extract all PAT-xxx entries, checking each pattern's Rule against the files in the PR diff. For index-only entries (entries containing only a See-link to `.claude/rules/*.md`), follow the link and read the referenced rule file to obtain the full rule body. If the rule file does not exist, skip the entry and note it as a broken reference.
  2. Extract all ABS-xxx entries and check each abstraction's Invariant against the PR diff — focusing on whether the diff introduces a new writer to a sole-writer abstraction, adds a consumer without handling the documented contract, or violates the "Violated when" condition.
  3. Extract all TB-xxx entries and check each trust boundary's Invariant against the PR diff — focusing on whether the diff crosses a trust boundary without the documented validation, introduces a new trust boundary crossing, or weakens an existing boundary guard.

  The agent checks only files present in the PR diff. It reads non-diff files for context (e.g., to understand an import chain) but findings must reference diff files only. ARCHITECTURE.md is treated as a trusted data source — human-authored and protected by workflow-gate phase restrictions (Write/Edit blocked outside spec/implementation phases). The trust model here is stronger than TB-005's agent-to-agent handoff: ARCHITECTURE.md is a human-curated document read by a mechanical checker, not an agent draft consumed by a downstream agent. The agent reads entry text as structured data for codebase checking, not as instructions to execute.

- **R-004** [unit]: The agent prompt instructs handling of intentional exceptions. When checking TB-xxx entries, the agent must also read sub-entries and treat them as documented scoped exceptions. Sub-entries are identified by the pattern `TB-\d{3}[a-z]` where the numeric portion matches the parent entry (e.g., TB-001a and TB-001b are sub-entries of TB-001; TB-010 is NOT a sub-entry of TB-001). A finding that matches a documented scoped exception must not be submitted. The prompt must include: "Before submitting a trust boundary violation, check whether any TB-xxx sub-entry documents this as an intentional scoped exception. If so, do not submit — it is a known exception, not a violation."

- **R-005** [unit]: The agent prompt includes a dormant-signal fallback (PAT-019): "If ARCHITECTURE.md does not exist, contains only placeholder markers (`{PROJECT_NAME}`, `{PLACEHOLDER}`), or has no PAT-xxx/ABS-xxx/TB-xxx entries, return: 'No architecture entries found — architecture compliance checks skipped.' Submit zero findings. Do not attempt to infer architecture from the codebase — that is `/carchitect`'s job."

- **R-006** [unit]: The parent `/cpr-review` skill computes ARCHITECTURE.md staleness before spawning the agent (via `git log -1 --format='%ai' .correctless/ARCHITECTURE.md` and `git log -1 --format='%ai'`). If the last-modified date is more than 30 days before the most recent source commit, `/cpr-review` prepends a LOW-severity finding directly (not delegated to the agent): "ARCHITECTURE.md may be stale — last updated {date}, most recent source commit {date}. Architecture findings below may be false positives due to doc drift. Consider running /cupdate-arch." This is a single warning, not per-entry. The staleness computation lives in the parent because the agent has no Bash tool access (R-002: tools are Read, Grep, Glob only). The staleness warning uses LOW severity (not SUSPICIOUS as in Phase 3) because `/cpr-review` uses CRITICAL/HIGH/MEDIUM/LOW severity, not the BLOCKING/NON-BLOCKING/SUSPICIOUS tiers of `/caudit`.

- **R-007** [unit]: The agent prompt categorizes findings into four check types:
  1. **Pattern compliance** (PAT-xxx): does the PR diff follow documented patterns?
  2. **Abstraction invariant** (ABS-xxx): does the PR diff maintain documented abstraction invariants? (sole-writer violations, contract breaches)
  3. **Trust boundary enforcement** (TB-xxx): does the PR diff enforce documented trust boundary invariants?
  4. **New pattern introduction**: does the PR diff introduce a structural or dependency pattern not documented in any PAT-xxx entry? Calibration: "A reportable new pattern is a project-specific convention that a new contributor would need to learn — not standard language idioms, standard library usage, or framework conventions. Only flag patterns that appear structurally in the diff (new file organization, new import patterns, new error handling conventions), not one-off implementation choices." New-pattern findings are informational (LOW severity) — they surface candidates for PAT-xxx entries or questions for the PR author about whether this is an intentional convention.

- **R-008** [unit]: Each finding from the Architecture Compliance Agent includes: (1) severity classification (CRITICAL/HIGH/MEDIUM/LOW) consistent with `/cpr-review`'s output format, (2) an `architecture_ref` identifying the specific PAT-xxx, ABS-xxx, or TB-xxx entry violated (or `null` for new-pattern findings), (3) file path and line reference within the PR diff, (4) one-sentence description, (5) one-sentence "why it matters", (6) suggested fix. TB-xxx violations default to at least HIGH severity (security-critical). PAT-xxx and ABS-xxx violations default to MEDIUM. New-pattern findings default to LOW. The agent may raise severity based on the specific violation.

- **R-009** [unit]: The `/cpr-review` SKILL.md is updated: (1) Step 3 (Architecture Compliance) is replaced with spawning the Architecture Compliance Agent and collecting its results — the existing 5 bullet points of prose architecture checking are removed, (2) `Task(correctless:architecture-compliance-reviewer)` is added to `/cpr-review`'s `allowed-tools` frontmatter, (3) the task list in "Progress Visibility" is updated to reflect "Spawn architecture compliance agent" instead of inline architecture check, (4) the "Present Findings" step merges the agent's severity-classified findings into the main output alongside findings from Steps 4–8.

- **R-010** [unit]: The existing high+ intensity "Trust Boundary Analysis" and "Drift Detection" checks in `/cpr-review`'s Full Mode Additional Checks section remain unchanged. These are semantic checks (does the PR cross boundaries without proper validation? is drift intentional or accidental?) that complement the agent's mechanical checks (does the PR violate a documented TB-xxx invariant?). The agent performs mechanical extraction and checking; the Full Mode checks perform semantic analysis. Both may produce findings for the same code — this is expected and not deduplicated, because mechanical and semantic violations are different classes. A note is added to both sections: "The Architecture Compliance Agent handles mechanical TB-xxx/PAT-xxx checking. This section adds semantic analysis beyond what mechanical extraction can catch."

- **R-011** [unit]: The agent is NOT spawned for dependency bump PRs. When `/cpr-review` detects a dependency bump PR (Step 2 in the existing SKILL.md), it switches to the dep-specific lens and skips Steps 3–8. The Architecture Compliance Agent is part of Step 3 and is therefore skipped for dep bumps — no special handling needed.

- **R-012** [unit]: `sync.sh` is updated to propagate the new `agents/architecture-compliance-reviewer.md` to `correctless/agents/architecture-compliance-reviewer.md`. The existing agent propagation pattern in sync.sh handles this — verify the agent file is included in the propagation glob.

- **R-013** [unit]: `docs/skills/cpr-review.md` is updated to describe the Architecture Compliance Agent: what it checks (PAT-xxx pattern compliance, ABS-xxx abstraction invariants, TB-xxx trust boundary enforcement, new pattern detection), the dormant-signal fallback (projects without ARCHITECTURE.md entries get zero findings), and the staleness warning.

- **R-014** [unit]: ABS-010's consumer list in `.correctless/ARCHITECTURE.md` is updated to add `skills/cpr-review/SKILL.md` as a consumer of the `architecture-compliance-reviewer` agent. This maintains the ABS-010 contract that every plugin agent's consumers are documented.

- **R-015** [unit]: A test file `tests/test-carchitect-phase4.sh` is created with coverage for: (1) agent frontmatter validation — `agents/architecture-compliance-reviewer.md` has correct `name`, `tools` (Read, Grep, Glob only), and `model` fields, (2) distribution parity — `sync.sh` propagates the agent file, (3) prompt content assertions — the agent body contains required instruction keywords for extraction (PAT-xxx, ABS-xxx, TB-xxx), dormant-signal fallback (PAT-019), sub-entry exception handling (TB-xxx sub-entry pattern), check type categorization (four types), and finding format fields (severity, architecture_ref, file path, description, why-it-matters, suggested fix), (4) no inline architecture prompt in `skills/cpr-review/SKILL.md` — the Step 3 section delegates to the agent, not inline prose, (5) `Task(correctless:architecture-compliance-reviewer)` appears in `/cpr-review`'s `allowed-tools` frontmatter, (6) staleness computation references appear in `/cpr-review` SKILL.md (not in the agent prompt, per R-006). The test file is added to `commands.test` in `workflow-config.json`.

## Won't Do

- Modifying ARCHITECTURE.md entries (this agent reads them, doesn't write them — that's `/cupdate-arch`)
- Modifying the Phase 3 Architecture Adherence Checker in `/caudit` (that is a separate agent for post-implementation auditing)
- Adding architecture checking to `/creview` or `/creview-spec` (those review specs, not code; Phase 2 already added architecture awareness to spec review)
- Automated architecture entry creation from new-pattern findings (the agent flags them, the PR author or reviewer decides)
- Deduplication between the mechanical agent and the semantic Full Mode checks (they catch different things — mechanical violations vs intent violations)
- Moving existing `/cpr-review` checks (Steps 4–8) to sub-agents (only Step 3 is delegated to a sub-agent in this feature)

## Risks

- **False positive noise on PR reviews**: The agent flags code that follows a pattern correctly but happens to touch a file covered by a PAT-xxx or ABS-xxx entry. Mitigation: R-003 scopes checking to the PR diff only, and R-004 handles documented exceptions. R-007 calibration limits new-pattern detection to structural patterns, not one-off choices.

  1. Mitigate (recommended) — R-003 diff-scoping + R-004 exception handling + R-007 calibration
  2. Accept — some noise is the cost of mechanical coverage
  3. Defer — wait for Phase 3 to prove the approach in /caudit first

- **Stale ARCHITECTURE.md produces false positives**: If the architecture doc is outdated, the agent flags correct code as violations. Mitigation: R-006 has the parent `/cpr-review` skill compute staleness and add a LOW-severity warning when ARCHITECTURE.md hasn't been updated in 30+ days.

  1. Mitigate (recommended) — R-006 staleness warning
  2. Accept — users who keep ARCHITECTURE.md current won't see this
  3. Defer — address when `/cupdate-arch` is improved

- **Keyword-presence testing limitation (AP-003 class)**: The agent prompt is in `agents/architecture-compliance-reviewer.md`. Tests verify the prompt text contains required instructions; they cannot verify the LLM follows them at runtime. This is the standard testing limitation for agent prompt modifications.

  1. Accept — same limitation as all other prompt-level rules in correctless

  Enforcement: prompt-level (inherent — no structural mechanism exists for LLM agent PR review behavior).

- **Agent context budget**: ARCHITECTURE.md can be large (the correctless one is ~9000 words). Combined with the PR diff, the agent may hit context limits. Mitigation: the agent prompt instructs reading ARCHITECTURE.md first (primary input), then targeted reads of diff files based on which entries are relevant.

  1. Mitigate (recommended) — instruct agent to read ARCHITECTURE.md first, then targeted diff reads
  2. Accept — most projects have smaller ARCHITECTURE.md files

## Open Questions

- None
