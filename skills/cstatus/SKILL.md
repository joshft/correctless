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
- Does `ARCHITECTURE.md` exist and not contain `{PROJECT_NAME}` or `{PLACEHOLDER}` template markers? (Note: a minimal ARCHITECTURE.md with "This project is in early development" is valid — it means `/csetup` ran on a greenfield project and intentionally deferred architecture docs.)

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

**When displaying the current phase, calculate and show the time spent in this phase.** Read `phase_entered_at` from the state file, compute the duration as `now - phase_entered_at`, and display in human-readable format:
- Under 60 minutes: '{N} minutes' (e.g., '12 minutes')
- 1-24 hours: '{N} hours' (e.g., '2 hours')
- Over 24 hours: '{N} days' (e.g., '1 day')

Format: 'Phase: {phase} ({duration})'

Proactive warnings at thresholds:
- After more than 1 hour in a phase: 'This phase has been active for {duration}. If you are stuck, try re-running the skill for this phase.'
- After more than 24 hours: 'This workflow has been in {phase} for {duration}. The workflow may be stalled — re-run the skill or use `workflow-advance.sh override` if needed.'

**If workflow is active, show a pipeline diagram with the current phase marked.** Use `▶` to indicate the active phase. For Lite mode:

```
  spec → review → [ tdd ] → verify → docs → merge
                     │
               ┌─────┴─────┐
              RED → GREEN → QA
                     │       │
               test audit    │
                     └─ fix ◄┘
```

For Full mode, include the extra steps:

```
  spec → model → review → [ tdd ] → verify → arch → docs → audit → merge
                             │
                       ┌─────┴─────┐
                      RED → GREEN → QA
                             │       │
                       test audit    │
                             └─ fix ◄┘
```

Mark the current phase with `▶` and show it in the diagram. For TDD sub-phases (tdd-tests, tdd-impl, tdd-qa), mark the specific position inside the TDD box.

**Then show phase-specific guidance:**

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
| `documented` | "All steps complete. Options: create PR (`gh pr create`), merge locally, keep branch, or discard. After merging: `/cpostmortem` if bugs escape, `/cmetrics` for health, `/caudit` for sweep (Full)." |
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
  /ccontribute    Contribute to an open source project
  /cmaintain      Maintainer review for incoming contributions
  /cdebug         Structured bug investigation
  /csetup         Re-run setup / validate configuration
  /chelp          Quick help — workflow pipeline and commands
  /cwtf           Workflow accountability — did agents do their job?

State management:
  .claude/hooks/workflow-advance.sh status      Current phase
  .claude/hooks/workflow-advance.sh status-all   All active workflows
  .claude/hooks/workflow-advance.sh diagnose "file"   Why a file is blocked
  .claude/hooks/workflow-advance.sh override "reason"  Temporarily bypass gate
```

Read `.claude/workflow-config.json`. If `workflow.intensity` is set, also show Full mode commands: `/cmodel`, `/creview-spec`, `/caudit`, `/cupdate-arch`, `/cpostmortem`, `/cdevadv`, `/credteam`

### 5. Detect Problems

After showing phase and commands, proactively check for issues:

**Stale workflow**: If >24 hours in a phase, this is already handled by the time-in-phase display in section 3 above — do not repeat the warning here. Only check for stale workflows if section 3 did not already display a >24h warning (e.g., if phase_entered_at was missing or unparsable).

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
