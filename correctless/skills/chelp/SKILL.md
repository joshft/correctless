---
name: chelp
description: Quick help — shows the workflow pipeline, available commands, and current status.
allowed-tools: Read, Bash(*)
---

# /chelp — Correctless Quick Help

Show the user the workflow pipeline, available commands, and current status. Keep output under 50 lines.

## Behavior

### 1. Detect Intensity

Check if `.correctless/config/workflow-config.json` exists. If not, the project is not set up yet. If it exists, read `workflow.intensity`: if present, use the configured value. If absent, default to `standard` intensity.

### 2. Show Pipeline

**If not set up:**
"Correctless isn't configured yet. Run `/csetup` to get started."

**At standard intensity:**
```
Correctless (standard intensity):

  /cspec → /creview → [ /ctdd ] → /cverify → /cdocs → merge
                          │
                    ┌─────┴─────┐
                   RED → GREEN → QA
                          │       │
                    test audit    │
                          └─ fix ◄┘
```

**At high+ intensity:**
```
Correctless (high intensity):

  /cspec → /creview-spec → [ /ctdd ] → /cverify → /cupdate-arch → /cdocs → /caudit → merge
                               │
                         ┌─────┴─────┐
                        RED → GREEN → QA
                               │       │
                         test audit    │
                               └─ fix ◄┘
```

**At critical+ intensity:**
```
Correctless (critical intensity):

  /cspec → /cmodel → /creview-spec → [ /ctdd ] → /cverify → /cupdate-arch → /cdocs → /caudit → merge
                                         │
                                   ┌─────┴─────┐
                                  RED → GREEN → QA
                                         │       │
                                   test audit    │
                                         └─ fix ◄┘
```

### 3. Show Commands

All 26 skills are always visible. Skills gated behind an intensity level are annotated with their minimum.

```
Feature workflow:
  /cspec         Write a feature spec with testable rules
  /creview       Skeptical review + security checklist (~3 min)
  /creview-spec  Adversarial 4-agent review (~15 min)              [high+]
  /cmodel        Formal Alloy modeling                             [critical+]
  /ctdd          Enforced TDD: tests → implement → QA
  /cverify       Verify implementation matches spec
  /cupdate-arch  Update .correctless/ARCHITECTURE.md               [high+]
  /cdocs         Update documentation
  /caudit        Olympics audit (QA/Hacker/Performance)            [high+]
  /cpostmortem   Post-merge bug analysis (when bugs escape)
  /cdevadv       Devil's advocate — challenge assumptions
  /credteam      Live red team assessment                          [critical+]

Other:
  /cquick        Quick fix with TDD — no spec/review for small changes
  /crefactor     Structured refactoring (tests must pass before + after)
  /cpr-review    Review someone else's PR
  /ccontribute   Contribute to someone else's project
  /cmaintain     Review contributions as a maintainer
  /cdebug        Structured bug investigation
  /cstatus       Where am I? What's next?
  /csummary      What did the workflow catch this feature?
  /cmetrics      Project-wide health dashboard
  /csetup        Re-run setup / health check
  /chelp         This help
  /cwtf          Audit the workflow — did agents follow instructions?
  /crelease      Version bumping, changelog, release tagging
  /cexplain      Guided codebase exploration with diagrams
```

### 4. Show Current Status

Run: `.correctless/hooks/workflow-advance.sh status 2>/dev/null`

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
  Contribute to OSS  → /ccontribute
  Review as maintainer → /cmaintain
  Project health     → /cmetrics
  Audit the workflow → /cwtf
```

## Constraints

- **Keep it short.** This is a quick reference, not a tutorial.
- **Read-only.** Don't modify anything.
- **Intensity-aware.** Show all commands; annotate gated skills with their minimum intensity.

## If Something Goes Wrong

- This skill is read-only. Re-run anytime safely.
