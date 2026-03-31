# Correctless Documentation

Correctness-oriented development workflow for [Claude Code](https://docs.anthropic.com/en/docs/claude-code). 23 skills, 4 hooks, enforced TDD with agent separation.

[README](https://github.com/joshft/correctless) | [Quick Start](https://github.com/joshft/correctless#quick-start) | [Changelog](https://github.com/joshft/correctless/blob/main/CHANGELOG.md)

## Skills

### Core Workflow
- [/csetup](skills/csetup.md) — Project health check + workflow setup
- [/cspec](skills/cspec.md) — Feature spec with testable rules
- [/creview](skills/creview.md) — Skeptical review + security checklist
- [/ctdd](skills/ctdd.md) — Enforced TDD: RED → test audit → GREEN → QA
- [/cverify](skills/cverify.md) — Verify implementation matches spec
- [/cdocs](skills/cdocs.md) — Update documentation

### Code Quality
- [/crefactor](skills/crefactor.md) — Structured refactoring
- [/cdebug](skills/cdebug.md) — Bug investigation with git bisect
- [/cpr-review](skills/cpr-review.md) — Multi-lens PR review

### Open Source
- [/ccontribute](skills/ccontribute.md) — Contribute to someone else's project
- [/cmaintain](skills/cmaintain.md) — Maintainer review for contributions

### Observability
- [/cstatus](skills/cstatus.md) — Current phase + next steps
- [/chelp](skills/chelp.md) — Quick reference
- [/csummary](skills/csummary.md) — What the workflow caught
- [/cmetrics](skills/cmetrics.md) — Token ROI + session analytics
- [/cwtf](skills/cwtf.md) — Workflow accountability

### Full Mode Only
- [/cmodel](skills/cmodel.md) — Alloy formal modeling
- [/creview-spec](skills/creview-spec.md) — 4-agent adversarial review
- [/caudit](skills/caudit.md) — Olympics convergence audit
- [/cupdate-arch](skills/cupdate-arch.md) — Maintain ARCHITECTURE.md
- [/cpostmortem](skills/cpostmortem.md) — Post-merge bug analysis
- [/cdevadv](skills/cdevadv.md) — Devil's advocate
- [/credteam](skills/credteam.md) — Live red team assessment
