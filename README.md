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

Same model — but the framing determines what the agent finds.

## Two Versions

### Correctless Lite

For web apps, APIs, CLI tools, and everyday development.

```
/cspec → /creview → /ctdd [RED → test audit → GREEN → /simplify → QA] → /cverify → /cdocs
```

**~10-15 minutes per feature** (after initial setup). You get: specs before code with current best practice research, a skeptical review with automatic OWASP security checklist, enforced TDD with test quality audit, verification, and living documentation. First run includes a 17-point project health check that catches hardcoded secrets, missing CI, and security gaps.

[Full spec &rarr;](correctless-lite.md)

### Correctless (Full)

For security-critical infrastructure, financial systems, and anything where a bug is a vulnerability.

```
/cspec → /cmodel → /creview-spec → /ctdd [RED → test audit → GREEN → /simplify → QA] → /cverify → /cupdate-arch → /cdocs → /caudit
```

**~1-2 hours per feature — but the code that ships is tested, reviewed, and has had its assumptions challenged.** Everything in Lite plus: formal Alloy modeling, STRIDE threat analysis, 4-agent adversarial spec review, mutation testing, drift debt tracking, postmortem feedback loops, convergence-based audit system, live red team assessment, and devil's advocate analysis.

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

## Quick Start

You need [Claude Code](https://docs.anthropic.com/en/docs/claude-code) and a Claude Max subscription ($100-200/mo). Not sure which version? See [Which One?](#which-one) above.

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

**Plugin:** Claude Code's `plugin update` doesn't always pull latest. To update reliably (replace `correctless` with `correctless-lite` if you installed Lite):
```
/plugin uninstall correctless              # or: correctless-lite
/plugin marketplace remove correctless
/plugin marketplace add joshft/correctless
/plugin install correctless                # or: correctless-lite
```
Then restart Claude Code.

**Git clone:** `cd .claude/skills/workflow && git pull && ./setup`

## How It Works

### 1. Project Health Check

On first run, [`/csetup`](docs/skills/csetup.md) scans your project for baseline hygiene: hardcoded secrets, missing CI, no linter, no tests, committed build artifacts. Produces a health card with 17 checks across security, code quality, testing, CI/CD, documentation, and git hygiene. For existing projects, it mines your codebase for conventions and architecture patterns before asking you to describe them.

### 2. Spec Before Code

Every feature starts with a spec ([`/cspec`](docs/skills/cspec.md)) that defines what "correct" means — testable rules, not vague goals. The spec agent reads your architecture docs, known bug patterns, and QA findings history. When the feature involves libraries or protocols that may have changed, a **research subagent** searches the web for current docs, CVEs, and deprecations before rules are written.

### 3. Skeptical Review with Security Checklist

A fresh agent ([`/creview`](docs/skills/creview.md)) that didn't write the spec reads it cold. This includes an **automatic security checklist** that fires based on what the spec touches — auth, user input, data storage, payments, APIs, multi-tenant. It checks for the vulnerabilities that vibe-coded apps ship with: missing CSRF, SSRF, broken access control, SQL injection, XSS, missing database RLS. In Full, [`/creview-spec`](docs/skills/creview-spec.md) runs a four-agent adversarial team instead.

### 4. Enforced TDD with Test Audit

[`/ctdd`](docs/skills/ctdd.md) enforces agent separation: the test agent writes tests from the spec, a test auditor checks test quality, a separate implementation agent makes them pass, and a QA agent reviews both. Hooks block source code edits until tests exist. Every QA finding requires both an instance fix AND a class fix.

### 5. Verification and Documentation

[`/cverify`](docs/skills/cverify.md) checks that the implementation actually satisfies the spec — not just the test cases. [`/cdocs`](docs/skills/cdocs.md) updates documentation from the verification report. The state machine enforces both steps before merge.

### 6. The Compounding Effect

After each feature, Correctless learns:
- **Antipatterns** capture escaped bugs — every future spec and review checks against them
- **QA findings** accumulate — specs get tailored to avoid recurrent bugs
- **CLAUDE.md learnings** compound — postmortems, confirmed conventions, and audit patterns are appended to CLAUDE.md and loaded into every future session automatically
- **Workflow effectiveness** tracks which phases catch what — weak phases get pushed harder

Six months in, the workflow knows your project's failure modes better than any individual developer.

## Skills

### Core Workflow

| Skill | When to Use | Description |
|-------|------------|-------------|
| [`/csetup`](docs/skills/csetup.md) | First run, or re-run for health check | Project detection, convention mining, 17-point health check |
| [`/cspec`](docs/skills/cspec.md) | Starting a new feature | Write testable rules with research agent |
| [`/creview`](docs/skills/creview.md) | After /cspec | Skeptical review + OWASP security checklist (~3 min) |
| [`/ctdd`](docs/skills/ctdd.md) | After review approves spec | RED → test audit → GREEN → /simplify → QA |
| [`/cverify`](docs/skills/cverify.md) | After /ctdd completes | Verify implementation matches spec |
| [`/cdocs`](docs/skills/cdocs.md) | After /cverify | Update README, AGENT_CONTEXT, feature docs |

### Code Quality

| Skill | When to Use | Description |
|-------|------------|-------------|
| [`/crefactor`](docs/skills/crefactor.md) | Restructuring without changing behavior | Characterization tests, behavioral equivalence, agent separation |
| [`/cdebug`](docs/skills/cdebug.md) | Stuck on a bug | Root cause → hypothesis → bisect → TDD fix → class fix |
| [`/cpr-review`](docs/skills/cpr-review.md) | Someone opens a PR against your project | Architecture, security, tests, antipatterns, dep bumps |

### Open Source

| Skill | When to Use | Description |
|-------|------------|-------------|
| [`/ccontribute`](docs/skills/ccontribute.md) | Contributing to someone else's project | Learn conventions, match patterns, pre-flight, generate PR |
| [`/cmaintain`](docs/skills/cmaintain.md) | Reviewing an incoming contribution | Scope, conventions, maintenance burden, pre-written comments |

### Observability

| Skill | When to Use | Description |
|-------|------------|-------------|
| [`/cstatus`](docs/skills/cstatus.md) | Anytime | Current phase, next steps, problem detection |
| [`/chelp`](docs/skills/chelp.md) | First time or need a quick reference | Workflow pipeline, all commands |
| [`/csummary`](docs/skills/csummary.md) | After a feature or mid-feature | What the workflow caught, by phase |
| [`/cmetrics`](docs/skills/cmetrics.md) | Monthly or for ROI analysis | Token cost, bugs caught, session analytics, trends |
| [`/cwtf`](docs/skills/cwtf.md) | When you suspect agents shortcut | Did agents actually follow instructions? |

### Full Mode Only

| Skill | When to Use | Description |
|-------|------------|-------------|
| [`/cmodel`](docs/skills/cmodel.md) | Security-critical specs with state machines | Alloy formal modeling |
| [`/creview-spec`](docs/skills/creview-spec.md) | Critical features (~15 min) | 4-agent adversarial spec review |
| [`/caudit`](docs/skills/caudit.md) | After major features or periodically | Olympics QA/Hacker/Performance convergence audit |
| [`/cupdate-arch`](docs/skills/cupdate-arch.md) | After features land | Keep ARCHITECTURE.md current |
| [`/cpostmortem`](docs/skills/cpostmortem.md) | When bugs escape to production | Trace which phase missed it, strengthen workflow |
| [`/cdevadv`](docs/skills/cdevadv.md) | Quarterly or when assumptions feel stale | Challenge architecture and strategy |
| [`/credteam`](docs/skills/credteam.md) | Security assessment (isolated env required) | Live adversarial penetration testing |

## Platform Integration

Correctless hooks into Claude Code's infrastructure for real-time feedback and long-term learning.

### Statusline

The Correctless statusline shows your workflow state at a glance — no commands needed:
```
project/  feature/auth  Opus  34%  RED  QA:R0  $0.42  +87/-12
```
Workflow phase (color-coded), QA round count, session cost, lines delta, context usage with red warning at 70%. Installed during `/csetup`.

### Real-Time Adherence Feedback

A PostToolUse hook monitors every file modification and alerts you immediately:
- `⚠ tdd-qa: Source file modified — middleware.ts (this phase should be read-only)`
- `📝 GREEN: Test file edited — auth.test.ts (should be logged in test-edit-log)`
- `🔍 QA: Read middleware.ts (3 of 7 modified files reviewed)` (Full mode)

### Session Analytics

[`/cmetrics`](docs/skills/cmetrics.md) reads Claude Code's session-meta and facets data for exact token costs, outcome rates, friction analysis, and a **Correctless vs Freeform** comparison table — measured evidence that the workflow helps.

### Compounding Learning

After postmortems, feature completions, and audits, learnings are appended to CLAUDE.md and loaded into every future session automatically. The spec agent just *knows* that "auth features in this project need middleware ordering checks" without being told.

### Git Integration (opt-in)

- **Git trailers** in commit messages: `Spec:`, `Rules-covered:`, `Verified-by:` — queryable via `git log --format='%(trailers:key=Spec)'`
- **Git notes** attaching verification summaries to commits
- **Git bisect** in [`/cdebug`](docs/skills/cdebug.md) for automated regression finding

### Output Redaction

External-facing skills ([`/cpr-review`](docs/skills/cpr-review.md), [`/ccontribute`](docs/skills/ccontribute.md), [`/cmaintain`](docs/skills/cmaintain.md)) automatically redact paths, credentials, hostnames, and session IDs before posting to GitHub/GitLab.

## State Management

Check your workflow status with [`/cstatus`](docs/skills/cstatus.md) or the statusline. For advanced debugging:

```bash
.claude/hooks/workflow-advance.sh diagnose "file" # Why a file is blocked
.claude/hooks/workflow-advance.sh override "why"  # Temporary gate bypass (10 tool calls)
.claude/hooks/workflow-advance.sh spec-update "why"  # Spec was wrong mid-TDD
.claude/hooks/workflow-advance.sh reset           # Nuclear — remove all state
```

### Quick Fixes During an Active Workflow

If you need to fix a typo while a workflow is active and the gate is blocking you:

```bash
.claude/hooks/workflow-advance.sh override "quick bugfix: fixing typo in error message"
```

This bypasses the gate for 10 tool calls. Use for: typos, config tweaks, one-line fixes. When no workflow is active, the gate allows all edits freely.

## Comparison

| | Lite | Full |
|---|------|------|
| Skills | 16 | 23 |
| Spec format | 5 sections, simple rules | 12+ sections, typed invariants |
| Spec research | Current best practices, dependency health | Same |
| Review | Single-pass + auto security checklist | 4-agent adversarial team |
| Security checklist | CSRF, headers, SSRF, RLS, IDOR, XSS, SQLi | Same + STRIDE threat modeling |
| TDD enforcement | Hooks + agent separation + test audit | Same + mutation testing |
| Post-TDD pipeline | done → verified → documented (enforced) | Same + tdd-verify phase |
| QA findings | Instance fix + class fix required | Same |
| Formal modeling | No | Alloy (optional) |
| Convergence audit | No | Olympics (QA/Hacker/Perf presets) |
| Red team | No | Live adversarial assessment |
| Devil's advocate | No | Challenges assumptions |
| Postmortem | No | Structured bug analysis |
| Feedback loop | Antipatterns + CLAUDE.md learning | Same + drift debt + workflow effectiveness + templates |
| Overhead per feature | ~10-15 min | ~1-2 hours |

## Language Support

| Language | Test Runner | Mutation Tool | PBT Library |
|----------|-------------|---------------|-------------|
| Go | `go test` | go-mutesting | rapid |
| TypeScript | jest/vitest | Stryker | fast-check |
| Python | pytest | mutmut | hypothesis |
| Rust | cargo test | cargo-mutants | proptest |

Mutation testing and PBT helpers are Full-only. Lite works with any language that has a test runner.

## Requirements

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI
- A **Claude Max subscription** ($100/mo or $200/mo plan). Correctless spawns multiple agents per feature — the $200/mo Max plan is recommended, especially for Full mode.
- A project with a test runner

Optional (Full only):
- [Alloy Analyzer](https://alloytools.org/) for formal modeling
- Mutation testing tool for your language
- Isolated environment (Docker/VPS) for red team assessments

## Glossary

| Term | Meaning |
|------|---------|
| **Agent separation** | Each workflow phase runs in a fresh Claude session. The test writer doesn't know the implementation plan; the QA agent didn't write the tests. Prevents confirmation bias. |
| **Instance fix** | Fix the one bug here and now. |
| **Class fix** | Fix the entire category of this bug — add a structural test that prevents recurrence. |
| **Convergence** | Run multiple audit rounds until findings stabilize (no new critical/high issues). |
| **Drift** | Code that no longer matches documented architecture. Detected by `/cverify`, tracked in drift-debt.json. |
| **Antipattern** | A known bug class from your project's history. Stored in `.claude/antipatterns.md`, checked by every future spec and review. |
| **Spec** | A document defining what "correct" means for a feature: testable rules, edge cases, security assumptions. A spec that can't be tested is incomplete. |
| **Invariant** | A rule that must always be true: "auth tokens expire after 24 hours." Specs are lists of invariants. |
| **Mutation testing** | Introduce small bugs into code and check if tests catch them. If a test passes with a mutation, that test is weak. Full mode only. |
| **STRIDE** | Threat modeling framework: Spoofing, Tampering, Repudiation, Information Disclosure, Denial of Service, Elevation of Privilege. |
| **RED / GREEN** | TDD phases. RED = write tests that fail. GREEN = write code to make tests pass. |

## Status

**Early release.** 23 skills (16 Lite, 23 Full), 57 automated tests, 4 hooks (gate, state machine, statusline, audit trail). Real-world usage ongoing — file issues as you find them.

## License

MIT
