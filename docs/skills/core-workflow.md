---
title: Core Workflow
parent: Skills
nav_order: 1
has_children: true
---

# Core Workflow

The spec-to-merge pipeline. These skills enforce a linear progression: write a spec, review it, implement with TDD, verify, document, and merge. Each step uses a separate agent — no agent grades its own work.

The state machine in `hooks/workflow-advance.sh` enforces the ordering. You cannot skip phases or go backwards.

| Skill | Purpose |
|:------|:--------|
| [/csetup](csetup) | Project health check and workflow setup |
| [/cspec](cspec) | Write a feature spec with testable rules |
| [/creview](creview) | Skeptical spec review with security checklist |
| [/ctdd](ctdd) | Enforced TDD: RED, test audit, GREEN, QA |
| [/cverify](cverify) | Verify implementation covers every spec rule |
| [/cdocs](cdocs) | Update documentation for changes |
| [/carchitect](carchitect) | Define and maintain architecture documentation |
| [/cauto](cauto) | Semi-autonomous pipeline orchestrator |
| [/crelease](crelease) | Version bumping, changelog, release tagging |
