# Spec: Skill Path Discovery

## Metadata
- **Task**: skill-path-discovery
- **Recommended-intensity**: high
- **Intensity**: high
- **Intensity reason**: file path signal (skills/) triggers high; project floor enforces high
- **Override**: none

## What

Fix 4 skills that reference workflow artifacts ("Read the spec artifact") without specifying how to discover the artifact's path. PMB-004 proved this causes `/creview-spec` to fail on non-correctless projects in fresh sessions — the agent hallucinates wrong paths. Add explicit path discovery to all 4 skills and a structural guard in `test-architecture-drift.sh` that catches future skills missing path discovery.

## Rules

- **R-001** [unit]: `/creview-spec` SKILL.md step 2 ("Read the spec artifact") is replaced with: "Check current workflow state: `bash .correctless/hooks/workflow-advance.sh status`. Read the spec artifact at the path shown in the `Spec:` line of the status output." This matches the pattern used by `/ctdd` (line 117) and `/creview` (line 74).

- **R-002** [unit]: `/cverify` SKILL.md step 2 ("Read the spec artifact (from workflow state or `.correctless/specs/`)") is replaced with: "Read the spec artifact (path from `workflow-advance.sh status` output, `Spec:` line)." The vague "from workflow state or .correctless/specs/" fallback is removed — the status output is the canonical source.

- **R-003** [unit]: `/cpostmortem` SKILL.md step 3 ("Identify the spec artifact for the feature where the bug was introduced") is updated to include explicit path discovery: "Identify the spec artifact for the feature. If the feature has an active workflow, read the path from `workflow-advance.sh status`. If no active workflow exists (post-merge postmortem), search `.correctless/specs/` by slug." Step 2 line "Read the spec and verification report (if they exist)" is updated to: "Read the spec (path from step 3) and verification report at `.correctless/verification/{task-slug}-verification.md` (if they exist)."

- **R-004** [unit]: `/csummary` SKILL.md already says "Read the workflow state file to get the task name, spec path, and branch" — but doesn't include a `workflow-advance.sh status` call. Updated to: "Run `bash .correctless/hooks/workflow-advance.sh status` to get the task name, spec path, and branch. If no active workflow, ask the human which feature to summarize and search `.correctless/specs/` by slug."

- **R-005** [unit]: A structural guard in `tests/test-architecture-drift.sh` maintains an explicit list of skills that MUST have spec path discovery. The list is: `creview-spec`, `creview`, `ctdd`, `cverify`, `cpostmortem`, `csummary`, `cdocs`, `cmodel`. For each skill in the list, the test verifies the skill's SKILL.md contains at least one of: `workflow-advance.sh status`, `spec_file`, `path from workflow`, or `.correctless/specs/`. If a skill is added to `skills/` that is not in the list, the test fails with a message: "Skill {name} not classified in path-discovery guard — add to MUST_HAVE_DISCOVERY or EXCLUDED_FROM_DISCOVERY list." This forces the author to classify every new skill. The excluded list contains skills that don't need single-spec discovery (e.g., `crelease`, `cupdate-arch`, `carchitect`, `csetup`, `chelp`, `cstatus`, `cquick`, `cexplain`, `cdebug`, `crefactor`, `ccontribute`, `cmaintain`, `cpr-review`, `credteam`, `caudit`, `cdevadv`, `cauto`, `cwtf`, `cmetrics`, `crelease`).

- **R-006** [unit]: All 4 skill changes are synced to the `correctless/` distribution via `sync.sh`. The distribution copies are byte-equal to the source files after sync.

## Won't Do

- **Adding `workflow-advance.sh status` to skills that don't need the spec path** — `/cupdate-arch`, `/carchitect`, `/crelease` read specs by directory scan, not by workflow state. They don't need single-spec discovery.
- **Changing the workflow-advance.sh status output format** — the existing format is fine, just underused.
- **Adding a shared "discover spec path" function to lib.sh** — overkill for a text instruction in 4 skill files.
- **Regex-based structural guard for spec references** — the regex approach (`Read.*the.*spec`) false-positives on 10+ skills. An explicit list is testable, maintainable, and caught by the registration guard.
- **Verification report discovery guard** — every skill mentioning "verification report" already contains `.correctless/verification/`. The guard would never fire (zero discrimination power).

## Risks

- **Explicit list goes stale** — a new skill is added without being classified.
  1. Mitigate — R-005's test fails when any skill is not in either the MUST_HAVE or EXCLUDED list, forcing classification. Same pattern as REG-001 (test registration guard).

## Open Questions

None.
