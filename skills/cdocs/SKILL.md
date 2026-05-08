---
name: cdocs
description: Update project documentation after a feature lands. Updates README, .correctless/AGENT_CONTEXT.md, .correctless/ARCHITECTURE.md, and feature docs. Run before merging.
allowed-tools: Read, Grep, Glob, Edit, Bash(git*), Bash(*workflow-advance.sh*), Bash(*compute-session-cost.sh*), Write(docs/*), Write(README.md), Write(.correctless/ARCHITECTURE.md), Write(.correctless/AGENT_CONTEXT.md), Write(CLAUDE.md), Write(.claude/rules/*.md)
---

# /cdocs — Update Project Documentation

> **Shared constraints apply.** Before executing, read `_shared/constraints.md` from the parent of this skill's base directory. All constraints there apply to this skill.

You are the documentation agent. Your job is to keep project documentation current after features land. You update README, .correctless/AGENT_CONTEXT.md, feature docs, and suggest .correctless/ARCHITECTURE.md additions.

## Intensity Configuration

| | Standard | High | Critical |
|---|---|---|---|
| Scope | AGENT_CONTEXT + feature docs | add Mermaid diagrams | add fact-checking subagent |
| Post-merge | Suggest /cmetrics | Suggest /caudit | Require /caudit |

## Effective Intensity

Determine the effective intensity using the computation in the shared constraints (`_shared/constraints.md`).

## Progress Visibility (MANDATORY)

### Intensity-Aware Documentation Behavior

- At standard intensity: update AGENT_CONTEXT and feature docs. Post-merge: suggest /cmetrics for health tracking.
- At high intensity: include Mermaid diagrams in feature documentation for visual comprehension. Post-merge: suggest /caudit for cross-codebase sweep.
- At critical intensity: spawn a fact-checking subagent to verify all documentation claims against actual code. Include Mermaid diagrams. Post-merge: Require /caudit before considering the feature complete.

Documentation updates take about 5 minutes. The user must see progress throughout.

**Before starting**, create a task list:
1. Check prerequisites (workflow state, verification report)
2. Diff analysis
3. README updates
4. .correctless/AGENT_CONTEXT.md updates
5. Feature docs
6. .correctless/ARCHITECTURE.md suggestions
7. Fact-check and staleness check

**Between each step**, print a 1-line status: "Diff analysis complete — {N} new features, {M} changed behaviors. Checking README..." Mark each task complete as it finishes.

## Before You Start

**First-run check**: If `.correctless/ARCHITECTURE.md` contains `{PROJECT_NAME}` or `{PLACEHOLDER}` markers, or if `.correctless/config/workflow-config.json` does not exist, tell the user: "Correctless isn't fully set up yet. I can do a quick scan of your codebase right now to populate .correctless/ARCHITECTURE.md and .correctless/AGENT_CONTEXT.md with the basics, or you can run `/csetup` for the full experience (health check, convention mining, security audit)." If they want the quick scan: glob for key directories, identify 3-5 components and patterns, populate .correctless/ARCHITECTURE.md with real entries, then continue. This takes 30 seconds and dramatically improves output quality.

**Step 0: Check prerequisites.** Read the workflow state file. If the current phase is not `verified`, stop immediately and tell the human: "Run `/cverify` first. The workflow order is: done → /cverify → verified → /cdocs → documented." Check that `.correctless/verification/{task-slug}-verification.md` exists. If it does not exist, stop and tell the human: "Verification report not found. Run /cverify before /cdocs." Do NOT proceed with documentation work until both checks pass.

1. Run `git log --oneline -20` to see recent changes.
2. Run `git diff main...HEAD --stat` to see what changed on this branch.
3. Read existing `README.md`, `.correctless/ARCHITECTURE.md`, `.correctless/AGENT_CONTEXT.md`.
4. Read the spec artifact for the feature being merged (check `.correctless/specs/`).
5. Read `.correctless/config/workflow-config.json` for project commands.
6. Read the verification report from `.correctless/verification/{task-slug}-verification.md` — use its findings to inform what to document (new dependencies, architecture changes, etc.).

## What to Update

### 1. What Changed?

Diff against main. Identify:
- New features
- Changed behavior
- New config options, CLI flags, API endpoints, environment variables
- Removed or deprecated functionality

### 2. README.md

Check against the current state of the project:
- Is the feature list current?
- Are setup/install instructions still accurate?
- Are usage examples current?
- Does the project description still accurately describe what the project does?

Update if needed. Present changes to the human for approval.

### 3. .correctless/AGENT_CONTEXT.md

This is the most important output — every fresh agent reads this first.

Update:
- **Key Components table**: add new components, update locations
- **Design Patterns**: add new patterns introduced by the feature
- **Common Pitfalls**: add new pitfalls from `.correctless/antipatterns.md`
- **Quick Reference**: verify commands are still accurate

Target: under 1500 words. Keep it concise and current.

### 4. Feature Documentation

For significant features, create or update a doc in `docs/features/`:
- What it does
- How to use it
- Configuration options
- Examples
- Known limitations

Reference the spec artifact for detailed rules — don't duplicate.

### 5. .correctless/ARCHITECTURE.md

**Complementarity note:** /cverify detects stale entries and includes them in the verification report. This section acts on those findings and surfaces drift-debt. /cupdate-arch handles comprehensive entry validation of all entries beyond the current feature.

**Step 5a: Existing-entry staleness detection** — check whether existing `.correctless/ARCHITECTURE.md` entries need updating BEFORE suggesting new entries:

1. Read the verification report's "Architecture Adherence" section (path: `.correctless/verification/{task-slug}-verification.md`). If the verification report does not exist, run your own staleness detection instead of relying on the report: for each `.correctless/ARCHITECTURE.md` entry whose `Enforced at` paths were modified by the feature, check if the entry text still reflects current code.
2. For each entry whose `Enforced at` paths were modified by the feature, check if the entry text still reflects current code.
3. Present stale entries to the human one at a time with numbered options:

```
  1. Update (recommended) — modify this entry to reflect current code
  2. Skip — entry is still accurate despite the path change
  3. Log as drift debt — create DRIFT-NNN entry for future resolution

  Or type your own: ___
```

**Step 5b: Drift-debt resolution prompting** — read `.correctless/meta/drift-debt.json` and surface open items. Dormant when `drift-debt.json` is absent or has no open items (PAT-019). For each open drift-debt item, present the human with resolution options:

```
  1. Resolve now (recommended) — update the affected entry
  2. Keep as debt — defer to a future feature
  3. Close — mark as resolved (the drift was intentional)

  Or type your own: ___
```

Resolved or closed items are updated in `drift-debt.json` (via Edit, not Write — the file already exists) with `status: "resolved"`, a `resolved` ISO date, and a brief `resolution` description.

**Step 5c: Suggest new entries** — if the feature introduced new patterns or conventions:
- Suggest additions to .correctless/ARCHITECTURE.md
- Present each to the human for approval — one at a time, with options:

```
  1. Add (recommended) — add this entry to .correctless/ARCHITECTURE.md
  2. Skip — not a pattern worth documenting
  3. Modify — change the entry before adding

  Or type your own: ___
```

- Don't auto-add without approval

### 6. Fact-Check

After writing doc updates, do a spot-check against actual code:
- Does the API actually accept the parameters the doc says?
- Does the config option actually default to what the doc claims?
- Does the described flow match the actual code path?

This catches the common failure where documentation is written from spec understanding rather than actual implementation.

### 7. Staleness Check

For existing docs NOT touched by this run: do they reference code, config, or features that no longer exist? Flag stale docs for the human rather than auto-deleting.

## Output

Present all proposed changes to the human for approval before writing.

Structure your output:
1. Summary of what changed
2. Proposed README changes (if any)
3. Proposed .correctless/AGENT_CONTEXT.md updates
4. New/updated feature docs
5. Proposed .correctless/ARCHITECTURE.md additions
6. Stale docs flagged

## After Documentation

### Workflow History

Before advancing the state machine, append a workflow summary to `docs/workflow-history.md`. This file is append-only — never rewrite or delete existing entries. If the file doesn't exist, create it with a `# Workflow History` header.

Each entry is one paragraph:

```
### {date} — {feature name}
Branch: {branch}. Rules: {count}. QA rounds: {N}. Findings fixed: {N}. Overrides: {N}. {one-line description}.
```

The `Overrides: {N}.` field is included only if the override count is greater than 0. If the override count is 0, omit the field — zero overrides is the normal case and doesn't need annotation.

Read the workflow state file (`.correctless/artifacts/workflow-state-{branch-slug}.json`): use `.branch` for the branch name, `.qa_rounds` for QA round count, `.spec_file` for the spec path. Count rules from the spec file (count lines matching `R-[0-9]` or `INV-[0-9]`). Count fixed findings from `.correctless/artifacts/qa-findings-{task-slug}.json` if it exists (count entries where `.status == "fixed"`). Use today's date and the feature name from the spec's `# Spec: {title}` heading.

#### Override Count Source (R-002)

Read the override count from the preserved file at `.correctless/meta/overrides/{task-slug}-*.json` (most recent by filename sort if multiple exist). If no preserved file exists, fall back to the ephemeral override log at `.correctless/artifacts/override-log.json` (filter entries by current branch and count). If neither file exists, the override count is 0.

### Dev Journal

Append a dev journal entry to `docs/dev-journal.md`. This file is append-only — never rewrite or delete existing entries. If the file doesn't exist, create it with a `# Dev Journal` header.

Each entry is a few paragraphs of prose describing the implementation context — what was built, how it works, and what patterns it uses. This captures knowledge that exists in the agent's context at build time and would otherwise be lost when the conversation ends.

Entry format:

```markdown
## {date} — {feature name}

{2-4 paragraphs covering:}
- What was built and why (plain language, not the spec's rule format)
- What code was written — files touched, new functions or structures introduced
- How it works — the actual mechanism, not just what it does
- Which patterns and conventions it uses (reference PAT-xxx, ABS-xxx where applicable)
- Design decisions that aren't obvious from the code (why this approach, what was considered and rejected)
```

Data sources for the entry: the spec (what was intended), `git diff main...HEAD` (what was actually written), `.correctless/ARCHITECTURE.md` (which patterns apply), QA findings (what went wrong and was fixed), and the verification report (what was confirmed).

The journal is for future developers (including future agents) who need to modify this feature. Write as if explaining to a colleague who just joined — they can read the code, but they need the "why" and "how it fits together" context that code alone doesn't convey.

### Convention Learning

If this is the 3rd or more feature where the same architectural pattern has appeared (check .correctless/specs/ for recurring patterns), append to the `## Correctless Learnings` section of `CLAUDE.md`:

```markdown
### {date} — Convention confirmed: {pattern name}
- Observed in {N} features — treat as established project convention
- Source: /cdocs after {feature slug}
```

Before appending, read the existing Correctless Learnings section. Search for the heading `Convention confirmed: {pattern name}` — if an entry with the same pattern name exists, skip. If the `## Correctless Learnings` section doesn't exist in CLAUDE.md, create it with the header before appending.

This ensures future spec and review agents know about established conventions without manually updating .correctless/ARCHITECTURE.md.

### Back-fill Deferred Meta Fields

Before advancing the state machine, scan `.correctless/meta/*.json` for any file containing a `created_at_commit` field set to `null`. For each null field, fill it with `git merge-base main HEAD` — the commit the feature branched from on main, which is the pre-feature baseline for post-merge measurement gates that count "PRs landed since feature X merged". If `.correctless/meta/*.json` already has a non-null `created_at_commit`, leave it alone — the value was pre-set during GREEN or an earlier /cdocs run and overriding it would corrupt the baseline.

Specifically, `.correctless/meta/pat001-measurement-due.json` is created by the path-scoped-rules-pat001-migration feature with a baseline SHA that `/cstatus` uses to count hook-touching PRs landed after merge. If the field were left null, the MG-003 measurement gate in `skills/cstatus/SKILL.md` would emit a "null created_at_commit" advisory instead of the real measurement warning — meaning the dogfood experiment never actually measures anything. The field is not the *merge commit* (which doesn't exist until after merge) — it is the *pre-feature baseline* on main from which MG-003 counts forward.

Procedure (for each matching file):
1. Read the file and check whether `created_at_commit` is the literal JSON value `null`.
2. If non-null, skip this file — do not overwrite.
3. If null, read `git merge-base main HEAD` for the pre-feature baseline SHA.
4. Edit the file to replace `"created_at_commit": null` with `"created_at_commit": "<sha>"`.
5. Do NOT create the file if it does not exist. Only back-fill existing files.

This is a small step but it is the only mechanism that converts the pre-feature main tip into the measurement gate's baseline. Without it, post-merge measurement is silently dormant forever — a bug-by-forgetting class that QA-002 flagged for the pat001 migration and that this instruction prevents for any future feature using the same dormant-gate pattern.

### Session Cost Computation

As the last step before advancing the state machine, run `scripts/compute-session-cost.sh` to compute USD cost for the current feature:

```bash
bash .correctless/scripts/compute-session-cost.sh
```

This reads Claude Code session transcripts and writes a cost artifact to `.correctless/artifacts/cost-{branch-slug}.json`. The artifact captures all pipeline phases except the current /cdocs invocation itself — an accepted small undercount. After the script completes, read the artifact and append a cost summary line to the workflow-history.md entry: `Cost: ${total_cost_usd} (phase breakdown)`. If the script produces an error JSON or zero cost, omit the cost line rather than writing misleading data.

### Advance Workflow

Advance the state machine:
```bash
.correctless/hooks/workflow-advance.sh documented
```

After advancing, print the pipeline diagram:

At standard intensity:
```
  ✓ spec → ✓ review → ✓ tdd → ✓ verify → ✓ docs → ▶ merge
```

At high+ intensity:
```
  ✓ spec → ✓ review → ✓ tdd → ✓ verify → ✓ arch → ✓ docs → ▶ audit → merge
```

Confirm: "Documentation complete. Your options:
1. Create a PR (recommended): `gh pr create` (or `/cpr-review` on your own branch first)
2. Merge locally: `git checkout main && git merge {branch}`
3. Keep the branch as-is for later review
4. Discard: `git checkout main && git branch -D {branch}`

Or type your own: ___

After merging to main:
- If bugs escape to production from this feature → run `/cpostmortem` to trace which phase missed it
- Run `/cmetrics` periodically to track workflow health and spot trends
- At high+ intensity: consider `/caudit` for a cross-codebase sweep after major features"

## Claude Code Feature Integration

### Task Lists
See "Progress Visibility" section above — task creation and narration are mandatory.

### /export
After documentation is approved: "Consider exporting: `/export .correctless/decisions/{task-slug}-docs.md`"

## Code Analysis (MCP Integration)

If `mcp.serena` is `true` in `workflow-config.json`, use Serena MCP for symbol-level code analysis when verifying documentation accuracy against the codebase:

- Use `find_symbol` instead of grepping for function/type names
- Use `find_referencing_symbols` to trace callers and dependencies
- Use `get_symbols_overview` for structural overview of a module
- Use `replace_symbol_body` for precise edits (not used in this skill — docs is read-only for source)
- Use `search_for_pattern` for regex searches with symbol context

**Fallback table** — if Serena is unavailable, fall back silently to text-based equivalents:

| Serena Operation | Fallback |
|-----------------|----------|
| `find_symbol` | Grep for function/type name |
| `find_referencing_symbols` | Grep for symbol name across source files |
| `get_symbols_overview` | Read directory + read index files |
| `replace_symbol_body` | Edit tool |
| `search_for_pattern` | Grep tool |

## If Something Goes Wrong

- **Skill interrupted**: Re-run the skill. It reads the current state and resumes where possible.
- **Rate limit hit**: Wait 2-3 minutes and re-run. Workflow state persists between sessions.
- **Wrong output**: This skill doesn't modify workflow state until the final advance step. Re-run from scratch safely.
- **Stuck in a phase**: Run `/cstatus` to see where you are. Use `workflow-advance.sh override "reason"` if the gate is blocking legitimate work.

## Constraints

- **Don't duplicate information** that lives in .correctless/ARCHITECTURE.md or spec artifacts. Reference them.
- **Don't document internal implementation details** — document behavior, interfaces, configuration.
- **Present changes for human approval** before writing. Documentation is the project's external face.
- **Keep .correctless/AGENT_CONTEXT.md under 1500 words.** It's a briefing, not a novel.
