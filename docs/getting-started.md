---
title: Getting Started
nav_order: 2
---

# Getting Started

Correctless is a [Claude Code](https://docs.anthropic.com/en/docs/claude-code) plugin. It installs as a set of skills (slash commands), hooks (automatic enforcement), and scripts (shared utilities) into your project.

## Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI installed
- A git repository to work in
- A test runner for your language (Jest, pytest, go test, etc.)

## Installation

```bash
git clone https://github.com/joshft/correctless.git \
  ~/.claude/plugins/correctless
```

## Setup

In your project directory, run:

```
/csetup
```

This does a project health check and scaffolds the workflow:

1. **Detects your stack** — language, test runner, formatter, source/test patterns
2. **Creates `.correctless/`** — config, architecture doc, antipatterns file
3. **Registers hooks** — phase gating, sensitive file protection, audit trail
4. **Verifies everything works** — runs your test suite, checks hook installation

Setup is idempotent — safe to re-run after upgrades.

## Your First Feature

### 1. Create a feature branch

```bash
git checkout -b feature/my-feature
```

### 2. Write a spec

```
/cspec "Add rate limiting to the API"
```

The spec agent asks clarifying questions (what does "correct" mean? what should never happen? what's the failure mode?) and produces a spec with testable rules at `.correctless/specs/my-feature.md`.

### 3. Review the spec

```
/creview
```

A separate agent reads the spec cold, looking for unstated assumptions, untestable rules, missing edge cases, and security gaps. Findings become new rules or accepted risks.

### 4. Implement with TDD

```
/ctdd
```

This orchestrates the full pipeline:

- **RED** — a test agent writes failing tests from the spec rules
- **Test audit** — a separate agent checks test quality before implementation
- **GREEN** — an implementation agent makes the tests pass
- **QA** — an independent agent reviews the implementation against the spec

Each phase uses a different agent. Hooks enforce that source code can't be written during RED and nothing can be edited during QA.

### 5. Verify and document

```
/cverify    # Check implementation covers every spec rule
/cdocs      # Update documentation for the changes
```

### 6. Merge

Your feature is ready. The spec, tests, implementation, and docs are all in sync.

## Intensity Levels

Correctless has three intensity levels. Set the project default in `.correctless/config/workflow-config.json`:

| Level | Pipeline | Best for |
|:------|:---------|:---------|
| **Standard** | spec → review → TDD → verify → docs → merge | Most features (~15 min) |
| **High** | spec → 6-agent adversarial review → TDD (with mini-audit) → verify → architecture → docs → audit → merge | Security-sensitive or complex features |
| **Critical** | All of high + formal modeling (Alloy) | Trust boundaries, concurrency, data integrity |

You can also set intensity per-feature:

```bash
bash .correctless/hooks/workflow-advance.sh set-intensity high
```

## Key Concepts

### Agent Separation

The core principle: **no agent grades its own work**. The agent that writes tests doesn't implement. The agent that implements doesn't review. This prevents the common failure mode where an AI agent writes tests that pass its own implementation but miss real bugs.

### Phase Gating

Hooks intercept every file operation and check it against the current workflow phase. During RED (test writing), source file edits are blocked. During QA, all edits are blocked. This is structural enforcement — the agent can't bypass it.

### Antipattern Learning

When bugs escape to production, `/cpostmortem` analyzes what went wrong and adds the bug class to `.correctless/antipatterns.md`. Future spec reviews and QA phases read this file, making the workflow progressively better at catching the kinds of bugs your project actually encounters.

## What's Next

- [Standard Workflow Guide](standard-workflow) — detailed state machine, hook architecture, and data flow
- [Skills Reference](skills/core-workflow) — every skill documented
- [Design Rationale](design/correctless) — why Correctless works this way
