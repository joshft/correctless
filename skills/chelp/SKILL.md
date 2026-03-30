---
name: chelp
description: Quick help — shows the workflow pipeline, available commands, and current status.
allowed-tools: Read, Bash(*)
---

# /chelp — Correctless Quick Help

Show the user the workflow pipeline, available commands, and current status. Keep output under 50 lines.

## Behavior

### 1. Detect Mode

Check if `.claude/workflow-config.json` exists. If not → not set up yet. If it exists, read it: if `workflow.intensity` is set → Full mode. Otherwise → Lite mode.

### 2. Show Pipeline

**If not set up:**
"Correctless isn't configured yet. Run `/csetup` to get started."

**Lite mode:**
```
Correctless Lite — Workflow Pipeline:
  /cspec → /creview → /ctdd [RED → test audit → GREEN → /simplify → QA] → /cverify → /cdocs → merge
```

**Full mode:**
```
Correctless Full — Workflow Pipeline:
  /cspec → /cmodel → /creview-spec → /ctdd [RED → test audit → GREEN → /simplify → QA] → /cverify → /cupdate-arch → /cdocs → /caudit → merge
```

### 3. Show Commands

**Lite commands:**
```
Feature workflow:
  /cspec        Write a feature spec with testable rules
  /creview      Skeptical review + security checklist (~3 min)
  /ctdd         Enforced TDD: tests → implement → QA
  /cverify      Verify implementation matches spec
  /cdocs        Update documentation

Other:
  /crefactor    Structured refactoring (tests must pass before + after)
  /cpr-review   Review someone else's PR
  /cdebug       Structured bug investigation
  /cpostmortem  Post-merge bug analysis (when bugs escape to production)
  /cstatus      Where am I? What's next?
  /csummary     What did the workflow catch this feature?
  /cmetrics     Project-wide health dashboard
  /csetup       Re-run setup / health check
  /chelp        This help
```

**Full mode — add these:**
```
Full mode additions:
  /cmodel       Formal Alloy modeling
  /creview-spec Adversarial 4-agent review (~15 min, critical features)
  /caudit       Olympics audit (QA/Hacker/Performance)
  /cupdate-arch Update ARCHITECTURE.md
  /cdevadv      Devil's advocate — challenge assumptions
  /credteam     Live red team assessment
```

### 4. Show Current Status

Run: `.claude/hooks/workflow-advance.sh status 2>/dev/null`

If active workflow: show the phase and next action.
If no active workflow: "No active workflow. Start one: `git checkout -b feature/my-feature` then `/cspec`."

### 5. Quick Reference

```
Quick reference:
  Start a feature    → /cspec
  Review a PR        → /cpr-review {number}
  Fix a bug          → /cdebug
  Refactor safely    → /crefactor
  Check status       → /cstatus
  Project health     → /cmetrics
```

## Constraints

- **Keep it short.** This is a quick reference, not a tutorial.
- **Read-only.** Don't modify anything.
- **Mode-aware.** Only show commands relevant to the user's mode.

## If Something Goes Wrong

- This skill is read-only. Re-run anytime safely.
