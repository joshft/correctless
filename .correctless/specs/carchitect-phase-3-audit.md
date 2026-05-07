# Spec: carchitect Phase 3 — Architecture Adherence Auditor

## Metadata
- **Task**: carchitect phase 3 audit adherence
- **Recommended-intensity**: high
- **Intensity**: high
- **Intensity reason**: file path signal (skills/caudit/ in skills/); project floor (workflow.intensity = high)
- **Override**: none

## What

A new specialist agent role — "Architecture Adherence Checker" — added to all three `/caudit` presets (QA, Hacker, Performance). The agent reads `.correctless/ARCHITECTURE.md` and mechanically checks the implementation against documented architecture: PAT-xxx pattern compliance, ABS-xxx abstraction invariant adherence, layer convention violations, dependency direction violations, TB-xxx trust boundary constraint enforcement, and drift between the documented architecture and what the code actually does. This is Phase 3 of the /carchitect roadmap — the architecture document produced in Phase 0 and consumed by specs (Phase 2) now also drives auditing.

This agent provides semantic architecture adherence checking during audit — it catches "you implemented the pattern correctly but your approach undermines the abstraction's intent." Factory/Overcorrect provides mechanical conformance validation post-phase — it catches "you imported the wrong package." They are complementary: mechanical checks catch structural violations, this agent catches intent violations.

## Rules

- **R-001** [unit]: The `/caudit` skill file (`skills/caudit/SKILL.md`) adds an "Architecture Adherence Checker" agent role to each of the three preset tables (QA Olympics, Hacker Olympics, Performance Olympics). The role appears in the agent role table for each preset with:
  - **Role**: Architecture Adherence Checker
  - **Lens**: a hostile framing appropriate to each preset's domain (QA: "Every documented pattern is violated somewhere"; Hacker: "Every trust boundary has an unguarded crossing"; Perf: "Every layer convention hides a performance shortcut")
  - **What it looks for**: description appropriate to each preset

- **R-002** [unit]: The Architecture Adherence Checker agent prompt template in `/caudit` includes instructions to read `.correctless/ARCHITECTURE.md` and mechanically extract PAT-xxx, ABS-xxx, and TB-xxx entries. For each entry, the agent must check the codebase against the entry's documented invariant/rule and "Violated when" condition. The prompt must instruct the agent to:
  1. Extract all PAT-xxx entries and check each pattern's Rule against the codebase. For index-only entries (entries containing only a See-link to `.claude/rules/*.md`), the agent must follow the link and read the referenced rule file to obtain the full rule body. If the rule file does not exist, skip the entry and note it as a broken reference.
  2. Extract all ABS-xxx entries and check each abstraction's Invariant against the codebase
  3. Extract all TB-xxx entries and check each trust boundary's Invariant against the codebase
  4. Check layer conventions (if documented) for dependency direction violations
  5. Detect undocumented patterns — code conventions that appear in 3+ files but have no PAT-xxx entry

  ARCHITECTURE.md is treated as a trusted data source (human-authored, sensitive-file-guard protected — see TB-005). The agent reads entry text as structured data for codebase checking, not as instructions to execute.

- **R-003** [unit]: The agent prompt instructs the Architecture Adherence Checker to handle intentional exceptions. When checking TB-xxx entries, the agent must also read sub-entries and treat them as documented scoped exceptions. Sub-entries are identified by the pattern `TB-\d{3}[a-z]` where the numeric portion matches the parent entry (e.g., TB-001a and TB-001b are sub-entries of TB-001; TB-004a and TB-004c are sub-entries of TB-004; TB-010 is NOT a sub-entry of TB-001). A finding that matches a documented scoped exception must be classified as a false positive by the agent, not submitted. The prompt must include: "Before submitting a trust boundary violation, check whether any TB-xxx sub-entry (identified by the pattern TB-NNNx where NNN matches the parent and x is a lowercase letter suffix) documents this as an intentional scoped exception. If so, do not submit — it is a known exception, not a violation."

- **R-004** [unit]: The agent prompt includes a dormant-signal fallback: "If ARCHITECTURE.md does not exist, contains only placeholder markers (`{PROJECT_NAME}`, `{PLACEHOLDER}`), or has no PAT-xxx/ABS-xxx/TB-xxx entries, report: 'No architecture entries found — architecture adherence checks skipped.' Submit zero findings for this lens. Do not attempt to infer architecture from the codebase — that is `/carchitect`'s job."

- **R-005** [unit]: The agent prompt includes a staleness warning instruction: "If ARCHITECTURE.md's last-modified date (from `git log -1 --format='%ai' .correctless/ARCHITECTURE.md`) is more than 30 days before the most recent source commit (`git log -1 --format='%ai'`), prepend a SUSPICIOUS-tier finding: 'ARCHITECTURE.md may be stale — last updated {date}, most recent source commit {date}. Architecture adherence findings below may be false positives due to doc drift. Consider running /cupdate-arch.' This is a single warning, not per-entry. Note: the 30-day heuristic is a coarse proxy. A more precise staleness check would count source commits to architectural paths since the last ARCHITECTURE.md update. The simple date comparison is good enough for v1 — the finding is SUSPICIOUS tier (advisory, not blocking)."

- **R-006** [unit]: Each finding from the Architecture Adherence Checker must include an `architecture_ref` field containing the specific PAT-xxx, ABS-xxx, or TB-xxx identifier that was violated (or `null` for undocumented-pattern findings). This field is in addition to the standard `invariant_ref` field (which references spec INV-xxx/R-xxx rules). The triage agent uses `architecture_ref` for deduplication against prior runs — the same architecture entry violated in the same file is the same finding even if the description text differs. The `architecture_ref` field must also appear in the findings JSON schema example in the Findings Artifacts section of SKILL.md, with value `"PAT-xxx, ABS-xxx, or TB-xxx, or null for undocumented-pattern findings"`.

- **R-007** [unit]: The agent prompt categorizes findings into four check types, each mapping to one of the roadmap's four capabilities:
  1. **Pattern compliance** (PAT-xxx): does the code follow documented patterns? (layer convention adherence)
  2. **Abstraction invariant** (ABS-xxx): does the code maintain documented abstraction invariants? (dependency direction violations — an abstraction's sole-writer contract is a dependency direction)
  3. **Trust boundary enforcement** (TB-xxx): does the code enforce documented trust boundary invariants? (anti-pattern presence in code — trust boundary violations are the security-critical subset)
  4. **Undocumented pattern detection**: are there project-specific code conventions in 3+ files with no PAT-xxx entry? (pattern drift detection — the architecture doc drifted behind the code). Calibration: "A documentable pattern is a project-specific convention that a new contributor would need to learn — structural patterns (all handlers follow X shape), dependency patterns (all database access goes through Y), error handling patterns (all errors are wrapped with Z). Standard language idioms, standard library usage, and framework conventions are NOT project-specific patterns and should not be flagged." Undocumented-pattern findings are informational — they surface candidates for PAT-xxx entries. The human decides whether to run `/cupdate-arch` to formalize them.

- **R-008** [unit]: The QA preset spawns the Architecture Adherence Checker alongside its existing agents (Concurrency Specialist, Error Handling Auditor, etc.). The Hacker preset spawns it alongside its existing agents (Auth/AuthZ Attacker, Injection Specialist, etc.). The Performance preset spawns it alongside its existing agents (Allocation Hunter, Algorithmic Complexity Auditor, etc.). The total agent count per preset increases by 1. QA: update from "spawn 4-6 based on project" to "spawn 5-7 based on project". Hacker and Perf: no range text to update (they use exact role lists) — just add one row to their agent roles tables.

- **R-009** [unit]: The Architecture Adherence Checker agent has the same tool access as other specialist agents (Read, Grep, Glob, Bash for git commands and tests). It does NOT have Write or Edit access — it is a read-only auditor, consistent with all other specialist agents during the finding-submission phase.

- **R-010** [unit]: The Regression Hunter's context list is updated to include architecture adherence findings from prior runs. The existing context (`antipatterns.md`, `audit-{preset}-history.md`, `qa-findings-*.json`) is supplemented with: "Check previous audit runs' architecture adherence findings (look for `architecture_ref` fields in `.correctless/artifacts/findings/audit-*-round-*.json`) for recurring architecture violations." The `architecture_ref` field is additive — prior round-JSON files without this field are valid. Consumers must handle its absence gracefully (treat missing `architecture_ref` as null).

- **R-011** [unit]: The `docs/skills/caudit.md` user-facing documentation is updated to describe the Architecture Adherence Checker role, its four check types, the dormant-signal fallback, and the staleness warning.

## Won't Do

- Modifying ARCHITECTURE.md entries (this agent reads them, doesn't write them — that's `/cupdate-arch`)
- Automated architecture entry creation from undocumented patterns (the agent flags them, the human decides)
- Changing the triage agent's logic (the existing triage dedup/validation works; `architecture_ref` is an additive field)
- Adding a new "Architecture" preset (the agent composes into existing presets, not a standalone run)
- Modifying `/carchitect` or `/cupdate-arch` (those are separate skills; robustness improvements are out of scope)
- Modifying the fix-diff-reviewer or fix verification loop (the adherence checker participates in the finding loop like any other agent)
- Moving caudit specialist agent prompts to `agents/*.md` (ABS-010 migration) — this is existing debt that applies to all caudit agents, not specific to this feature

## Risks

- **False positive flood from intentional exceptions**: The agent flags code that deliberately deviates from a pattern or trust boundary. Mitigation: R-003 requires the agent to check sub-entries (TB-xxxN) for documented exceptions before submitting. The triage agent provides a second filter. Residual risk: undocumented-but-intentional exceptions will surface as findings. This is arguably a feature — they should be documented.

  1. Mitigate (recommended) — R-003 handles documented exceptions; undocumented exceptions surface for documentation
  2. Accept — some noise is the cost of coverage
  3. Defer — wait for ARCHITECTURE.md to be more complete

- **Stale ARCHITECTURE.md produces false positives**: If the architecture doc is outdated, the agent flags correct code as violations. Mitigation: R-005 adds a staleness warning when ARCHITECTURE.md hasn't been updated in 30+ days. The warning is a single SUSPICIOUS finding at the top of the results, not a blocker.

  1. Mitigate (recommended) — R-005 staleness warning + user mentioned `/cupdate-arch` robustness as a separate concern
  2. Accept — users who keep ARCHITECTURE.md current won't see this
  3. Defer — address when `/cupdate-arch` is improved

- **Keyword-presence testing limitation (AP-003 class)**: All rules are prompt-level instructions in SKILL.md. Tests verify the instruction text is present; they cannot verify the LLM follows instructions at runtime. This is the standard testing limitation for skill prompt modifications.

  1. Accept — same limitation as all other prompt-level rules in correctless

  Enforcement: prompt-level (inherent — no structural mechanism exists for LLM agent audit behavior).

- **Agent context budget**: ARCHITECTURE.md can be large (the correctless one is 400+ lines). Combined with the source code scope, the agent may hit context limits and degrade. Mitigation: the agent prompt should instruct reading ARCHITECTURE.md first (it's the primary input), then scoping source reads based on what it found.

  1. Mitigate (recommended) — instruct agent to read ARCHITECTURE.md first, then targeted source reads
  2. Accept — large ARCHITECTURE.md is rare; most projects are smaller

## Open Questions

- None
