---
title: Home
layout: default
nav_order: 1
permalink: /
---

<div class="hero" markdown="1">

# Correctless

<p class="tagline">Correctness-oriented development workflow for <a href="https://docs.anthropic.com/en/docs/claude-code">Claude Code</a></p>
<p class="stats">29 skills &middot; 8 hooks &middot; 3 intensity levels &middot; enforced TDD with agent separation</p>

</div>

---

## The Problem

AI coding agents are fast but unreliable. They skip tests, grade their own work, silently drop edge cases, and ship bugs that pass CI but fail in production. The speed advantage disappears when you spend hours debugging what the agent "completed."

## The Solution

Correctless enforces a structured workflow where **no agent grades its own work**. Separate agents write specs, review specs, write tests, implement code, and audit quality. Hooks gate every file operation — you can't write source code during the test phase, and you can't skip review.

```mermaid
graph LR
    S["/cspec<br/>Write spec"] --> R["/creview<br/>Skeptical review"]
    R --> T["/ctdd<br/>RED → GREEN → QA"]
    T --> V["/cverify<br/>Verification"]
    V --> D["/cdocs<br/>Documentation"]
    D --> M["Merge"]

    style S fill:#4caf50,color:#fff
    style R fill:#9c27b0,color:#fff
    style T fill:#ff9800,color:#fff
    style V fill:#2196f3,color:#fff
    style D fill:#607d8b,color:#fff
    style M fill:#2196f3,color:#fff
```

At **high+ intensity**, the pipeline expands with 6-agent adversarial spec review, architecture maintenance, and convergence auditing.

---

| | |
|:--|:--|
| **Agent Separation** | **Phase Gating** |
| Every phase uses a different agent. The test writer doesn't implement. The implementer doesn't review. The reviewer didn't write the spec. | Hooks block file operations that violate the current phase. During RED, you can only write tests. During QA, everything is blocked. No shortcuts. |
| **Configurable Intensity** | **Self-Improving** |
| Standard (~15 min/feature) covers core TDD. High adds adversarial review and convergence auditing. Critical adds formal modeling. | Post-merge bugs feed back as antipatterns. QA findings calibrate intensity. The workflow learns from its mistakes. |

---

## Quick Start

```bash
# Install the plugin
git clone https://github.com/joshft/correctless.git \
  ~/.claude/plugins/correctless

# In your project directory, run setup
/csetup

# Start building a feature
/cspec "Add user authentication"
```

[Getting Started](getting-started){: .btn .btn-primary .mr-2 }
[View on GitHub](https://github.com/joshft/correctless){: .btn }

---

## Skills at a Glance

| Category | Skills | What they do |
|:---------|:-------|:-------------|
| [Core Workflow](skills/core-workflow) | `/csetup` `/cspec` `/creview` `/ctdd` `/cverify` `/cdocs` `/carchitect` `/cauto` `/crelease` | The spec-to-merge pipeline |
| [Code Quality](skills/code-quality) | `/cquick` `/crefactor` `/cdebug` `/cpr-review` `/cexplain` | Fixes, refactoring, and exploration outside the pipeline |
| [Observability](skills/observability) | `/cstatus` `/chelp` `/csummary` `/cmetrics` `/cwtf` | See what's happening and what the workflow caught |
| [High+ Intensity](skills/high-intensity) | `/cmodel` `/creview-spec` `/caudit` `/cupdate-arch` `/cpostmortem` `/cdevadv` `/credteam` `/cmodelupgrade` | Adversarial review, formal modeling, convergence auditing |
| [Open Source](skills/open-source) | `/ccontribute` `/cmaintain` | Contributing to and maintaining OSS projects |
