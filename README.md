# Correctless

Composable [Claude Code](https://docs.anthropic.com/en/docs/claude-code) skills that enforce a correctness-oriented development workflow. Spec before you code. Test before you implement. Never let an agent grade its own work.

## The Problem

AI coding assistants are fast but sloppy. They write code that works for the happy path, skip edge cases, and silently introduce bugs that don't surface until production. The same model that wrote the code will review it and say "looks good" — because it's confirming its own decisions.

Correctless fixes this by structuring the workflow so that **every phase is executed by a different agent with a different lens**:

- The **spec agent** asks "what does correct mean?" and researches current best practices before any code exists
- The **review agent** reads the spec cold and checks for security gaps, unstated assumptions, and untestable rules
- The **test agent** writes tests from the spec without knowing the implementation plan
- The **test auditor** checks whether those tests would actually catch bugs or just pass against mocks
- The **implementation agent** makes the tests pass without having written them
- The **QA agent** hunts for bugs with neither the test author's nor the implementer's blind spots
- The **verification agent** checks spec-to-code correspondence without insider knowledge
- The **Olympics agents** find systemic bugs across the whole codebase with hostile specialized lenses
- The **red team agent** proves whether defenses hold against a live attacker with a specific objective
- The **devil's advocate** challenges whether the architecture and assumptions are fundamentally wrong

Same model, same weights — but the framing determines what the agent finds.

## Two Versions

### Correctless Lite

For web apps, APIs, CLI tools, and everyday development. Lightweight specs, enforced TDD with agent separation, automatic security checklist, project health check.

```
/cspec → /creview → /ctdd [RED → test audit → GREEN → /simplify → QA] → /cverify → /cdocs
```

`/simplify` is a built-in Claude Code skill that runs between implementation and QA to clean up code quality issues before the QA agent reviews.

**~10-15 minutes of overhead per feature.** You get: specs before code with current best practice research, a skeptical review that auto-checks for OWASP vulnerabilities, enforced TDD with test quality audit, living documentation, and a project health check that catches hardcoded secrets, missing CI, and security gaps on first run.

[Full spec &rarr;](correctless-lite.md)

### Correctless (Full)

For security-critical infrastructure, network proxies, financial systems, and anything where a bug is a vulnerability. Formal modeling, multi-agent adversarial review, convergence-based Olympics auditing, live red team assessment, devil's advocate analysis.

```
/cspec → /cmodel → /creview-spec → /ctdd [RED → test audit → GREEN → /simplify → QA] → /cverify → /cupdate-arch → /cdocs → /caudit
```

**~1-2 hours of overhead per feature — but the code that ships is tested, reviewed, and has had its assumptions challenged.** Everything in Lite plus: formal Alloy modeling, STRIDE threat analysis, multi-agent adversarial spec review, mutation testing, drift debt tracking, postmortem feedback loops, Olympics audit system (QA/Hacker/Performance presets with bounty/penalty economics), live red team penetration testing, and devil's advocate assumption challenges.

[Full spec &rarr;](correctless.md)

### Which One?

| Building... | Use |
|-------------|-----|
| A SaaS dashboard, API, CLI tool, content site | **Lite** |
| Something that handles user auth or payments | **Lite**, upgrade to Full when scope grows |
| A network proxy, security tool, or infrastructure | **Full** |
| A prototype or exploration | Neither — just code |

You can upgrade from Lite to Full incrementally. Existing specs, antipatterns, and architecture docs carry over.

**Put another way:** Lite is like having someone next to you going through a checklist to make sure your project has some sanity. Full is like taking your Claude Max subscription tokens, setting them on fire, collecting the ash, and using it to create a tiny diamond.

## How It Works

### 1. Project Health Check

On first run, `/csetup` scans your project for baseline hygiene: hardcoded secrets in source code, missing CI pipeline, no linter, no tests, committed build artifacts, missing .env.example. Produces a health card with 17 checks across security, code quality, testing, CI/CD, documentation, and git hygiene. For every gap, offers to generate the fix. If it finds hardcoded secrets, it walks you through secrets management from zero (env vars → platform secrets → scanning prevention → dedicated managers) and offers to scrub them from git history.

### 2. Spec Before Code

Every feature starts with a spec that defines what "correct" means — testable rules, not vague goals. The spec agent reads your architecture docs, known bug patterns, and QA findings history. When the feature involves libraries or protocols that may have changed since training data, a **research subagent** searches the web for current docs, CVEs, deprecations, and dependency health before invariants are written.

### 3. Skeptical Review with Security Checklist

A fresh agent that didn't write the spec reads it cold. In Lite, this includes an **automatic security checklist** that fires based on what the spec touches — auth, user input, data storage, payments, APIs, multi-tenant. It checks for the vulnerabilities that 58% of vibe-coded apps ship with: missing CSRF, missing security headers, SSRF, broken access control, SQL injection, XSS, missing database RLS, client-side secret exposure. Findings are proposed as spec rules, not lectures. In Full, this is a four-agent adversarial team.

### 4. Enforced TDD with Test Audit

Hooks block source code edits until tests exist. The test agent writes from the spec's perspective. Before implementation begins, a **test auditor** checks whether the tests would actually catch bugs — flagging mock gaps where tests bypass real wiring, missing integration tests for component connection rules, and weak assertions. A separate implementation agent makes the tests pass. A third QA agent reviews both — every finding requires both an instance fix AND a class fix to prevent the bug category from recurring.

### 5. Enforced Post-TDD Pipeline

The state machine enforces: done → verified (requires verification report) → documented → ready to merge. No step is skippable. `/cverify` writes a verification report, drift debt entries, and checks QA class fixes. `/cdocs` reads the verification report and updates documentation. You cannot say "ready to merge" until both have run.

### 6. The Compounding Effect

After each feature merge, Correctless learns:
- **Antipatterns** capture bugs that escaped testing — every future `/cspec` and `/creview` checks new features against them
- **QA findings** accumulate — `/cspec` tailors rules to avoid recurrent bugs in the same code areas
- **Workflow effectiveness** tracks which phases catch what — the review agent pushes harder on historically weak areas
- **Templates** get refined from postmortems — invariant templates evolve to catch the bug classes your project actually hits

Six months in, the workflow knows your project's failure modes better than any individual developer. The bug escape rate drops because every escaped bug makes the workflow smarter.

## Quick Start

### Via Plugin Marketplace (recommended)

```
/plugin marketplace add joshft/correctless
/plugin install correctless-lite          # or: /plugin install correctless
/csetup
```

### Via Git Clone (alternative)

```bash
git clone https://github.com/joshft/correctless.git .claude/skills/workflow
.claude/skills/workflow/setup
/csetup
```

Lite mode by default. To enable Full: add `"intensity": "standard"` (or `"high"` / `"critical"`) to `.claude/workflow-config.json` and re-run setup.

### After Install

```
git checkout -b feature/my-feature
/cspec
```

### Updating

**Plugin:** Claude Code's `plugin update` doesn't always pull latest. To update reliably:
```
/plugin uninstall correctless
/plugin marketplace remove correctless
/plugin marketplace add joshft/correctless
/plugin install correctless
```
Then restart Claude Code.

**Git clone:** `cd .claude/skills/workflow && git pull && ./setup`

## Commands

### Lite (12 skills)

```
/csetup       Project health check + workflow setup
/cspec        Feature spec with testable rules + research agent
/creview      Skeptical review + automatic security checklist
/ctdd         Enforced TDD: RED → test audit → GREEN → /simplify → QA
/cverify      Verify implementation matches spec, write verification report
/cdocs        Update documentation (reads verification report)
/crefactor    Structured refactoring with behavioral equivalence enforcement
/cpr-review   Multi-lens PR review (architecture, security, tests, dep bumps)
/cstatus      Show current phase and next steps
/csummary     Feature summary — what the workflow caught
/cmetrics     Project-wide metrics dashboard + health analysis
/cdebug       Structured bug investigation with TDD fix
```

### Full (19 skills — includes all Lite skills)

```
/csetup       Health check + workflow setup + intensity selection
/cspec        Typed invariants, STRIDE, invariant templates, research agent
/creview      Quick single-pass review + security checklist (~3 min)
/cmodel       Alloy formal modeling
/creview-spec Multi-agent adversarial review, 4 agents (~15 min, use for critical features)
/ctdd         TDD + test audit + /simplify + mutation testing + tdd-verify phase
/cverify      Mutation testing, drift detection, cross-spec impact
/caudit       Olympics audit (QA/Hacker/Performance presets, bounty/penalty)
/cupdate-arch Maintain ARCHITECTURE.md
/cdocs        Mermaid diagrams, fact-checking subagent
/cpostmortem  Post-merge bug analysis, class fixes
/cdevadv      Devil's advocate — challenge assumptions (theme/signals/layers)
/credteam     Live red team assessment against running system
/crefactor    Structured refactoring + mutation testing, cross-spec impact
/cpr-review   Multi-lens PR review + concurrency, trust boundaries, dep bumps
/cstatus      Show current phase and next steps
/csummary     Feature summary — what the workflow caught
/cmetrics     Project-wide metrics dashboard, health analysis, and ROI
/cdebug       Structured bug investigation with escalation
```

### Built-in Claude Code Skills in the Workflow

Correctless integrates with built-in Claude Code skills at specific points:

| Built-in Skill | Where it runs | Purpose |
|----------------|---------------|---------|
| `/simplify` | Between GREEN and QA in `/ctdd` | Three parallel agents review for code reuse, quality, and efficiency. Cleans up the implementation before the QA agent reviews, reducing noise in QA findings. |

### State Management

Check your current workflow status with `/cstatus`. For advanced debugging:

```bash
.claude/hooks/workflow-advance.sh diagnose "file" # Why a file is blocked
.claude/hooks/workflow-advance.sh override "why"  # Temporary gate bypass (10 tool calls)
.claude/hooks/workflow-advance.sh spec-update "why"  # Spec was wrong mid-TDD
.claude/hooks/workflow-advance.sh reset           # Nuclear — remove all state
```

### Quick Fixes During an Active Workflow

If you need to fix a typo or tweak config while a workflow is active and the gate is blocking you:

```bash
.claude/hooks/workflow-advance.sh override "quick bugfix: fixing typo in error message"
```

This bypasses the gate for 10 tool calls. Use for: typos, config tweaks, one-line fixes. Don't use for: features, refactors, or anything that should have tests.

When no workflow is active, the gate allows all edits freely — no override needed.

## Language Support

| Language | Test Runner | Mutation Tool | PBT Library |
|----------|-------------|---------------|-------------|
| Go | `go test` | go-mutesting | rapid |
| TypeScript | jest/vitest | Stryker | fast-check |
| Python | pytest | mutmut | hypothesis |
| Rust | cargo test | cargo-mutants | proptest |

Mutation testing, property-based testing, and PBT helpers are Full-only. Lite works with any language that has a test runner.

## Comparison

| | Lite | Full |
|---|------|------|
| Skills | 12 | 19 |
| Spec format | 5 sections, simple rules | 12+ sections, typed invariants |
| Spec research | Current best practices, dependency health | Same |
| Review | Single-pass + auto security checklist | 4-agent adversarial team |
| Security checklist | CSRF, headers, SSRF, RLS, IDOR, XSS, SQLi | Same + STRIDE threat modeling |
| TDD enforcement | Hooks + agent separation + test audit | Same + mutation testing |
| Post-TDD pipeline | done → verified → documented (enforced) | Same + tdd-verify phase |
| QA findings | Instance fix + class fix required | Same |
| Formal modeling | No | Alloy (optional) |
| Convergence audit | No | Olympics (QA/Hacker/Perf presets, bounty/penalty) |
| Red team | No | Live adversarial assessment |
| Devil's advocate | No | Challenges assumptions (theme/signals/layers) |
| Postmortem | No | Structured bug analysis, class fixes |
| Feedback loop | Antipatterns (manual) | Antipatterns + QA findings + drift debt + workflow effectiveness + templates |
| Project health check | 17 checks + secrets management guide | Same |
| Bug investigation | Structured debugging + TDD fix | Same + escalation to architectural review |
| Overhead per feature | ~10-15 min | ~1-2 hours |

## Requirements

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI
- A **Claude Max subscription** ($100/mo or $200/mo plan). Correctless spawns multiple agents per feature — a spec review alone can use 4+ parallel agents, and the TDD workflow spawns separate agents for test writing, implementation, and QA. The standard Pro plan will hit rate limits quickly. The $200/mo Max plan is recommended, especially for Full mode.
- A project with a test runner

Optional (Full only):
- [Alloy Analyzer](https://alloytools.org/) for formal modeling
- Mutation testing tool for your language
- External model CLIs (Codex, Gemini) for cross-checking
- Isolated environment (Docker/VPS) for red team assessments

## Glossary

| Term | Meaning |
|------|---------|
| **Agent separation** | Each workflow phase runs in a fresh Claude session. The test writer doesn't know the implementation plan; the QA agent didn't write the tests. Same model, different mindsets — prevents confirmation bias. |
| **Instance fix** | Fix the one bug here and now. |
| **Class fix** | Fix the entire category of this bug — add a structural test that prevents recurrence. |
| **Convergence** | Run multiple audit rounds until findings stabilize (no new critical/high issues). |
| **Drift** | Code that no longer matches documented architecture. Detected by `/cverify`, tracked in drift-debt.json. |
| **Antipattern** | A known bug class from your project's history. Stored in `.claude/antipatterns.md`, checked by every future spec and review. |

## Status

**Early release.** Both Lite and Full implementations are functional. Setup, hooks, state machine, and all skill prompts are complete and tested. Real-world usage will surface rough edges — file issues as you find them.

## License

MIT
