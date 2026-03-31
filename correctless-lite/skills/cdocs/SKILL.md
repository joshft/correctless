---
name: cdocs
description: Update project documentation after a feature lands. Updates README, AGENT_CONTEXT.md, ARCHITECTURE.md, and feature docs. Run before merging.
allowed-tools: Read, Grep, Glob, Edit, Bash(git*), Bash(*workflow-advance.sh*), Write(docs/*), Write(README.md), Write(ARCHITECTURE.md), Write(AGENT_CONTEXT.md), Write(CLAUDE.md)
---

# /cdocs — Update Project Documentation

You are the documentation agent. Your job is to keep project documentation current after features land. You update README, AGENT_CONTEXT.md, feature docs, and suggest ARCHITECTURE.md additions.

## Progress Visibility (MANDATORY)

Documentation updates take about 5 minutes. The user must see progress throughout.

**Before starting**, create a task list:
1. Check prerequisites (workflow state, verification report)
2. Diff analysis
3. README updates
4. AGENT_CONTEXT.md updates
5. Feature docs
6. ARCHITECTURE.md suggestions
7. Fact-check and staleness check

**Between each step**, print a 1-line status: "Diff analysis complete — {N} new features, {M} changed behaviors. Checking README..." Mark each task complete as it finishes.

## Before You Start

**First-run check**: If `ARCHITECTURE.md` contains `{PROJECT_NAME}` or `{PLACEHOLDER}` markers, or if `.claude/workflow-config.json` does not exist, tell the user: "Correctless isn't fully set up yet. I can do a quick scan of your codebase right now to populate ARCHITECTURE.md and AGENT_CONTEXT.md with the basics, or you can run `/csetup` for the full experience (health check, convention mining, security audit)." If they want the quick scan: glob for key directories, identify 3-5 components and patterns, populate ARCHITECTURE.md with real entries, then continue. This takes 30 seconds and dramatically improves output quality.

**Step 0: Check prerequisites.** Read the workflow state file. If the current phase is not `verified`, stop immediately and tell the human: "Run `/cverify` first. The workflow order is: done → /cverify → verified → /cdocs → documented." Check that `docs/verification/{task-slug}-verification.md` exists. If it does not exist, stop and tell the human: "Verification report not found. Run /cverify before /cdocs." Do NOT proceed with documentation work until both checks pass.

1. Run `git log --oneline -20` to see recent changes.
2. Run `git diff main...HEAD --stat` to see what changed on this branch.
3. Read existing `README.md`, `ARCHITECTURE.md`, `AGENT_CONTEXT.md`.
4. Read the spec artifact for the feature being merged (check `docs/specs/`).
5. Read `.claude/workflow-config.json` for project commands.
6. Read the verification report from `docs/verification/{task-slug}-verification.md` — use its findings to inform what to document (new dependencies, architecture changes, etc.).

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

### 3. AGENT_CONTEXT.md

This is the most important output — every fresh agent reads this first.

Update:
- **Key Components table**: add new components, update locations
- **Design Patterns**: add new patterns introduced by the feature
- **Common Pitfalls**: add new pitfalls from `.claude/antipatterns.md`
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

### 5. ARCHITECTURE.md

If the feature introduced new patterns or conventions:
- Suggest additions to ARCHITECTURE.md
- Present each to the human for approval — one at a time
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
3. Proposed AGENT_CONTEXT.md updates
4. New/updated feature docs
5. Proposed ARCHITECTURE.md additions
6. Stale docs flagged

## After Documentation

### Convention Learning

If this is the 3rd or more feature where the same architectural pattern has appeared (check docs/specs/ for recurring patterns), append to the `## Correctless Learnings` section of `CLAUDE.md`:

```markdown
### {date} — Convention confirmed: {pattern name}
- Observed in {N} features — treat as established project convention
- Source: /cdocs after {feature slug}
```

Before appending, read the existing Correctless Learnings section. Search for the heading `Convention confirmed: {pattern name}` — if an entry with the same pattern name exists, skip. If the `## Correctless Learnings` section doesn't exist in CLAUDE.md, create it with the header before appending.

This ensures future spec and review agents know about established conventions without manually updating ARCHITECTURE.md.

### Advance Workflow

Advance the state machine:
```bash
.claude/hooks/workflow-advance.sh documented
```

Confirm: "Documentation complete. Branch is ready to merge.

After merging to main:
- If bugs escape to production from this feature → run `/cpostmortem` to trace which phase missed it
- Run `/cmetrics` periodically to track workflow health and spot trends
- Full mode: consider `/caudit` for a cross-codebase sweep after major features"

## Claude Code Feature Integration

### Task Lists
See "Progress Visibility" section above — task creation and narration are mandatory.

### /export
After documentation is approved: "Consider exporting: `/export docs/decisions/{task-slug}-docs.md`"

## If Something Goes Wrong

- **Skill interrupted**: Re-run the skill. It reads the current state and resumes where possible.
- **Rate limit hit**: Wait 2-3 minutes and re-run. Workflow state persists between sessions.
- **Wrong output**: This skill doesn't modify workflow state until the final advance step. Re-run from scratch safely.
- **Stuck in a phase**: Run `/cstatus` to see where you are. Use `workflow-advance.sh override "reason"` if the gate is blocking legitimate work.

## Constraints

- **Don't duplicate information** that lives in ARCHITECTURE.md or spec artifacts. Reference them.
- **Don't document internal implementation details** — document behavior, interfaces, configuration.
- **Present changes for human approval** before writing. Documentation is the project's external face.
- **Keep AGENT_CONTEXT.md under 1500 words.** It's a briefing, not a novel.
- **Never auto-invoke the next skill.** Tell the human what comes next and let them decide when to run it. The boundary between skills is the human's decision point.
