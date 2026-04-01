# Spec: Structured Decision UX

## What

Replace open-ended questions with numbered options across all Correctless skills. Every time the user needs to make a choice, present 2-4 numbered options with the recommended option first, marked "(recommended)", and an escape hatch "Or type your own: ___". This is a universal UX constraint added to the spec templates and applied to every skill that asks the user to decide something.

## Rules

### Universal Constraint

- **R-001** [unit]: Both `templates/spec-lite.md` and `templates/spec-full.md` contain a "Decision Points" section with the structured decision format: numbered options, recommended first, 2-4 options max, "Or type your own" escape hatch.

- **R-002** [unit]: The `/cquick` SKILL.md contains the "Decision Points" constraint (as the newest skill, it sets the pattern for future skills).

### Per-Skill Decision Points

Skills that ask the user to choose something must contain structured option patterns. Each rule verifies the SKILL.md has numbered options (grep for `1.` followed by `2.` in decision contexts) rather than open-ended questions.

- **R-003** [unit]: `/csetup` SKILL.md contains structured options for all three of: MCP selection (both/Serena/Context7/skip), branching strategy (feature branches/trunk-based), and merge strategy (squash/merge/rebase). Test must verify all three decision points exist.

- **R-004** [unit]: `/cspec` SKILL.md contains structured options for: failure mode decisions (fail-open/fail-closed/passthrough/crash) and risk acceptance (accept/mitigate/defer).

- **R-005** [unit]: `/creview` SKILL.md contains structured options for: finding disposition (accept finding/reject/modify/defer).

- **R-006** [unit]: `/ctdd` SKILL.md contains structured options for: QA finding response (fix now/accept risk/dispute) and test edit approval (approve/reject/modify).

- **R-007** [unit]: `/cverify` SKILL.md contains structured options for: drift handling (fix/log as debt/accept as intentional).

- **R-008** [unit]: `/cdocs` SKILL.md contains structured options for: architecture entry approval (add/skip/modify) and post-merge action (create PR/merge locally/keep branch/discard).

- **R-009** [unit]: `/crefactor` SKILL.md contains structured options for: test change approval (approve behavioral change/reject/split into separate PR).

- **R-010** [unit]: `/caudit` SKILL.md contains structured options for: finding triage (fix now/defer/dispute) and convergence decision (continue to next round/stop here).

### Skills That Don't Need Changes

- **R-011** [unit]: Read-only skills (`/chelp`, `/cstatus`, `/csummary`, `/cmetrics`, `/cwtf`) do not contain numbered decision option blocks (no `1.` + `(recommended)` pattern) because they don't present user decisions. This is a positive structural check, not a grep for open-ended questions.

- **R-012** [unit]: `/creview-spec` SKILL.md contains structured options for: finding disposition (accept finding/reject/modify/defer) — same pattern as `/creview`.

## Won't Do

- Changing the AskUserQuestion tool behavior — that's a Claude Code feature, not a Correctless feature. The structured format is in the skill prompt text, not in tool parameters.
- Adding options to every possible question — only decision points where the user is choosing between discrete alternatives. Socratic brainstorm questions in `/cspec` remain open-ended because they're exploratory, not decisional.
- Standardizing the exact option text across skills — each skill's options are domain-specific. The format is standardized, the content is not.

## Risks

- Skills with many decision points (`/csetup` has ~8) could become verbose if every decision gets a full options block. Mitigation: batch related decisions where possible ("Branching: feature branches. Merge: squash. Look right, or change something?").
- The "Or type your own" escape hatch means the agent still needs to handle free-form input gracefully. Not a new requirement — agents already handle this.

## Open Questions

- None.
