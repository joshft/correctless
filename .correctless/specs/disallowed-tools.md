# Spec: Add disallowed-tools to read-only and artifact-only skills

## Metadata
- **Task**: disallowed-tools
- **Recommended-intensity**: high
- **Intensity**: high
- **Intensity reason**: project floor (workflow.intensity = high)
- **Override**: none

## What

Add `disallowed-tools` frontmatter to 12 skills that should never edit source files. Claude Code v2.1.150 supports `disallowed-tools` in skill frontmatter — it structurally removes listed tools from the model while the skill is active. This is an application of PAT-018 (structural enforcement over prompt-level instruction): replacing prompt-level "do not edit" constraints with harness-enforced tool removal. It provides defense-in-depth alongside `allowed-tools` (which already excludes these tools via whitelist) and documents write-prohibition intent explicitly in the frontmatter.

Two groups:
- **Group A** (write-nothing skills): `/chelp`, `/cstatus`, `/cdashboard` — add `disallowed-tools: Edit, Write, MultiEdit, NotebookEdit, CreateFile`
- **Group B** (artifact-only skills): `/cexplain`, `/cwtf`, `/cmetrics`, `/csummary`, `/cpr-review`, `/cmaintain`, `/cmodel`, `/cmodelupgrade`, `/ctriage` — add `disallowed-tools: Edit, MultiEdit, NotebookEdit, CreateFile`

## Rules

- **R-001** [unit]: Each Group A skill's SKILL.md frontmatter contains `disallowed-tools: Edit, Write, MultiEdit, NotebookEdit, CreateFile`
- **R-002** [unit]: Each Group B skill's SKILL.md frontmatter contains `disallowed-tools: Edit, MultiEdit, NotebookEdit, CreateFile`
- **R-003** [unit]: The `disallowed-tools` line appears in the YAML frontmatter block (between `---` delimiters), not in the skill body
- **R-004** [unit]: Distribution copies in `correctless/skills/*/SKILL.md` match source copies after `sync.sh` runs
- **R-005** [unit]: For each skill in Group A and Group B, the set of tool basenames in `disallowed-tools` must be disjoint from the set of tool basenames in `allowed-tools`. Specifically: Group B skills must NOT disallow Write (they need it for artifacts). Tool basenames are extracted by stripping sub-pattern scoping (e.g., `Write(.correctless/artifacts/wtf-*)` yields basename `Write`)
- **R-006** [unit]: AGENT_CONTEXT.md's Design Patterns section or Skills component row contains a sentence describing `disallowed-tools` and its defense-in-depth relationship with `allowed-tools` (PAT-018 application)
- **R-007** [unit]: A structural drift test enumerates all skills, partitions them by `allowed-tools` content, and verifies: (a) every skill with `disallowed-tools` is in the correct group, (b) every skill whose `allowed-tools` does not include Edit must either have `disallowed-tools` or be explicitly excluded with a documented reason. Unclassified skills are a test failure

## Won't Do

- Adding `disallowed-tools` to skills that use Edit/Write for legitimate purposes (e.g., `/creview` edits specs, `/ctdd` writes tests)
- Removing any existing `allowed-tools` entries — this feature adds a second layer, not a replacement
- Testing runtime enforcement behavior — that's Claude Code's responsibility, not ours
- Adding `disallowed-tools` to agent files (`agents/*.md`) — agents use `allowed-tools` only; `disallowed-tools` is a skill-level feature

## Risks

- **allowed-tools + disallowed-tools interaction undefined**: If Claude Code ignores `disallowed-tools` when `allowed-tools` is present, the feature adds zero enforcement. Mitigation: the feature still documents intent in frontmatter even if runtime enforcement is redundant. Accepted — defense-in-depth is the explicit goal.
- **Future skill edits forget to update disallowed-tools**: A PR that adds Edit to a Group B skill's `allowed-tools` might forget to remove it from `disallowed-tools`, creating a conflict. Mitigation: R-005 test catches conflicts structurally. R-007 drift test catches new skills that escape classification.
- **Claude Code version dependency**: `disallowed-tools` requires Claude Code v2.1.150+. On older versions, the frontmatter key is silently ignored — no crash, no error, no enforcement. The existing `allowed-tools` whitelist remains the sole enforcement layer. Mark for ENV-011 in ARCHITECTURE.md during /cupdate-arch.

## Open Questions

- None — scope is clear.
