---
name: cstatus
description: Show current Correctless workflow state, available commands, and suggested next steps. Run anytime to see where you are.
allowed-tools: Bash, Read, Grep, Glob
---

# /cstatus — Workflow Status and Next Steps

You are the status agent. Show the human where they are in the workflow and what to do next. Be concise and actionable.

## Behavior

### 1. Check Setup

First, verify Correctless is set up in this project:
- Does `.claude/workflow-config.json` exist?
- Does `.claude/hooks/workflow-gate.sh` exist?
- Does `ARCHITECTURE.md` exist and have real content (not just the template)?

If not set up: "Correctless isn't configured in this project yet. Run `/csetup` to get started."

### 2. Check Current Workflow State

Run:
```bash
.claude/hooks/workflow-advance.sh status 2>/dev/null
```

If no active workflow, also run:
```bash
.claude/hooks/workflow-advance.sh status-all 2>/dev/null
```

### 3. Present Status

**If no active workflow on current branch:**

"No active workflow on `{branch}`. You can:
- Start a new feature: `git checkout -b feature/my-feature` then `/cspec`
- Check other branches: {show status-all output if there are active workflows elsewhere}"

**If workflow is active, show phase-specific guidance:**

| Phase | Show |
|-------|------|
| `spec` | "Writing the spec. When done, the human approves and you run `/creview` (Lite) or `/creview-spec` (Full)." |
| `review` / `review-spec` | "Run `/creview` (Lite) or `/creview-spec` (Full) to review the spec. After review and approval, run `/ctdd` to start writing tests." |
| `model` | "Formal modeling phase. Run `/cmodel` to generate the Alloy model." |
| `tdd-tests` | "RED phase — writing tests. Source files are blocked (except stubs with STUB:TDD). When tests exist and fail, advance with `workflow-advance.sh impl`." |
| `tdd-impl` | "GREEN phase — implementing. Make the tests pass. When done, advance with `workflow-advance.sh qa`." |
| `tdd-qa` | "QA review — edits blocked. If issues found: `workflow-advance.sh fix`. If a bug is hard to understand, try `/cdebug`. If clean: `workflow-advance.sh done` (Lite) or `workflow-advance.sh verify-phase` (Full)." |
| `tdd-verify` | "Final verification — edits blocked. If checks pass: `workflow-advance.sh done`." |
| `done` | "TDD complete. MANDATORY: run `/cverify` next (it advances the state automatically)." |
| `verified` | "Verification complete. MANDATORY: run `/cdocs` next (it advances the state automatically)." |
| `documented` | "All steps complete. Branch is ready to merge. After merging: run `/cpostmortem` if bugs escape, `/cmetrics` to track health." |
| `audit` | "Audit in progress. Run `/caudit` to continue the convergence loop." |

### 4. Show Available Commands

Based on the current state:

```
Available commands:
  /cspec          Start a new feature spec
  /creview        Skeptical spec review (Lite)
  /ctdd           Enforced TDD workflow
  /cverify        Post-implementation verification
  /cdocs          Update documentation
  /cstatus        This command — show status and next steps
  /csummary       Feature summary — what the workflow caught
  /cmetrics       Project-wide metrics dashboard
  /crefactor      Structured refactoring with behavioral equivalence
  /cpr-review     Multi-lens PR review
  /cdebug         Structured bug investigation
  /csetup         Re-run setup / validate configuration
  /chelp          Quick help — workflow pipeline and commands

State management:
  .claude/hooks/workflow-advance.sh status      Current phase
  .claude/hooks/workflow-advance.sh status-all   All active workflows
  .claude/hooks/workflow-advance.sh diagnose "file"   Why a file is blocked
  .claude/hooks/workflow-advance.sh override "reason"  Temporarily bypass gate
```

Read `.claude/workflow-config.json`. If `workflow.intensity` is set, also show Full mode commands: `/cmodel`, `/creview-spec`, `/caudit`, `/cupdate-arch`, `/cpostmortem`, `/cdevadv`, `/credteam`

### 5. Detect Problems

After showing phase and commands, proactively check for issues:

**Stale workflow**: Read `phase_entered_at` from the state file. Calculate how long the current phase has been active. If >24 hours: "This workflow has been in `{phase}` for {N} days. If you're stuck:
- Re-run the skill for this phase (e.g., `/ctdd` for tdd-impl, `/cverify` for done)
- If an agent crashed, the state machine is waiting for the next transition — re-running resumes
- If truly stuck: `workflow-advance.sh override 'resuming after stall'`"

**Empty docs**: Check if ARCHITECTURE.md contains `{PROJECT_NAME}` or `{PLACEHOLDER}` markers, or if AGENT_CONTEXT.md contains `{PROJECT_NAME}` or `{PLACEHOLDERS}`. If either is still the template: "ARCHITECTURE.md / AGENT_CONTEXT.md is still the default template. Run `/csetup` to populate it from your codebase — this significantly improves spec and review quality."

**Override usage**: Read `override_count` from the state file. If ≥2: "You've used {N} overrides on this workflow. If the gate keeps blocking legitimate edits, the workflow config or file patterns may need adjustment. Run `workflow-advance.sh diagnose 'yourfile.ts'` to understand why."

**No active workflow**: "No active workflow on this branch. You can edit freely — the gate only blocks during active workflows. To start a structured workflow: `git checkout -b feature/my-feature` then `/cspec`."

### 6. Health Check (if requested)

If the human asks "is everything set up correctly?" or similar, validate:
- Hooks registered in `.claude/settings.json`
- Config file valid JSON with required fields
- Hook scripts exist and are executable at `.claude/hooks/`
- ARCHITECTURE.md has content (not template)
- AGENT_CONTEXT.md has content (not template)

Report any issues with fix instructions.

## If Something Goes Wrong

- `/cstatus` is read-only — it reads workflow state and project files but modifies nothing. Re-run anytime safely.
- If status looks wrong, check that `.claude/workflow-config.json` exists and the hook scripts are installed at `.claude/hooks/`.

## Constraints

- **Keep it short.** Status should be a quick glance, not a wall of text.
- **Always suggest the next action.** Don't just show state — tell them what to do.
- **Don't modify anything.** This is read-only.
