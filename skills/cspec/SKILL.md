---
name: cspec
description: Create a structured specification with testable invariants for a new feature. Researches current best practices before writing invariants. Adapts format to workflow intensity.
allowed-tools: Read, Grep, Glob, Edit, Bash(git log*), Bash(git diff*), Bash(git branch*), Bash(*workflow-advance.sh*), Write(.correctless/specs/*), Write(.correctless/artifacts/research/*), Write(.correctless/artifacts/token-log-*), Write(.correctless/ARCHITECTURE.md), Write(.correctless/AGENT_CONTEXT.md), WebSearch, WebFetch
---

# /cspec — Write a Feature Specification

You are the spec agent. Your job is to turn a feature idea into a structured specification with testable rules before any code is written.

## Detect Mode

Read `.correctless/config/workflow-config.json`. If it has `workflow.intensity` set (low/standard/high/critical), you're in **Full mode** — use the full invariant format. If it only has `workflow.min_qa_rounds` (no intensity field), you're in **Lite mode** — use the simple rules format.

## Progress Visibility (MANDATORY)

Spec writing takes 5-10 minutes of active work plus conversation time. The user must see progress throughout.

**Before starting**, create a task list:
1. Socratic brainstorm
2. Read context (.correctless/ARCHITECTURE.md, antipatterns, drift debt, QA findings)
3. Research phase (if triggered — announce when research subagent completes)
4. Draft spec
5. Load templates and check antipatterns
6. Present to human for review

**Between each phase**, print a 1-line status: "Brainstorm complete — refined scope to {summary}. Reading project context..." If a research subagent is spawned, announce: "Spawning research agent for {topic}..." and when it returns: "Research complete — {N} findings. Drafting spec..."

Mark each task complete as it finishes.

## Before You Start

**First-run check**: If `.correctless/ARCHITECTURE.md` contains `{PROJECT_NAME}` or `{PLACEHOLDER}` markers, or if `.correctless/config/workflow-config.json` does not exist, tell the user: "Correctless isn't fully set up yet. I can do a quick scan of your codebase right now to populate .correctless/ARCHITECTURE.md and .correctless/AGENT_CONTEXT.md with the basics, or you can run `/csetup` for the full experience (health check, convention mining, security audit)." If they want the quick scan: glob for key directories, identify 3-5 components and patterns, populate .correctless/ARCHITECTURE.md with real entries, then continue with the spec. This takes 30 seconds and dramatically improves spec quality.

1. Read `.correctless/AGENT_CONTEXT.md` for project context.
2. Read `.correctless/ARCHITECTURE.md` for design patterns and conventions.
3. Read `.correctless/antipatterns.md` for known bug classes.
4. **Full mode**: Read `.correctless/meta/drift-debt.json` for outstanding drift debt.
5. **Full mode**: Read `.correctless/meta/workflow-effectiveness.json` for phase effectiveness history.
6. Read `.correctless/artifacts/qa-findings-*.json` (if any exist) — patterns QA historically finds in this project.
7. Run `git log --oneline -20` to understand recent context.
8. Grep/glob relevant source code areas based on the feature description.

## Workflow State

Check current workflow state:
```bash
.correctless/hooks/workflow-advance.sh status
```

If no workflow is active, initialize one. Before calling `workflow-advance.sh init`, ask the user: **"Short name for this feature? (used in filenames, e.g., `auth-middleware`)"**. If the user provides a name, use it as the task description for `init`. If they say "auto" or don't provide one, use the first 3-4 words of the feature description.

```bash
.correctless/hooks/workflow-advance.sh init "task description"
```

This creates the state file and sets the phase to `spec`. If you're on `main` or `master`, tell the user to create a feature branch first.

## How to Write the Spec

### Step 0: Socratic Brainstorm

Before writing any rules, challenge the developer's assumptions about the feature. This is not optional — even a developer who "knows exactly what they want" benefits from 2-3 questions that reframe the problem.

Ask these questions, adapting to the developer's confidence level:

1. **"What problem does this solve? Not the feature — the problem."** Forces the developer to articulate the WHY, not just the WHAT. Often reveals that the feature as described doesn't actually solve the stated problem, or solves it partially.

2. **"Who uses this and what does their workflow look like?"** Reveals edge cases: what if the user is on mobile? What if they have slow internet? What if they're not the primary account holder?

3. **"What's the simplest version that would be useful? What can you cut?"** Prevents scope creep before the spec even starts. The developer often describes the ideal v2 feature when v1 would ship faster and validate assumptions.

4. **"What would make this feature actively harmful if it went wrong?"** Surfaces failure modes at a high level to inform scope. Step 1 will pin down the exact failure mode classification (fail-open/fail-closed/etc.) for each specific behavior — this question identifies WHICH failure modes exist, Step 1 classifies them. "If the payment double-charges" or "if the auth check fails open" — these become prohibitions in the spec.

5. **"Is there an existing pattern in the codebase that does something similar?"** Check .correctless/ARCHITECTURE.md and the codebase. If a similar pattern exists, the new feature should compose with it, not reinvent it.

**Proportionality:** If the developer clearly understands the domain and has a well-formed idea, this step takes 2-3 exchanges. If the idea is vague ("I want to add payments"), this step takes longer and does more work. Read the developer's confidence from their responses — a product security engineer describing a network proxy doesn't need five Socratic questions. A junior developer adding their first auth system does.

**Output:** Summarize the brainstorm in 2-3 sentences before moving to Step 1. This summary captures the refined scope, surfaced failure modes, and any assumptions that were challenged. Present it to the human: "Based on our discussion, here's what I understand: [summary]. Proceeding with this scope." This summary becomes the foundation for the spec's Context section. The brainstorm may change the scope, surface new requirements, or eliminate unnecessary complexity before a single rule is written.

### Step 1: Ask What They're Building

Using the refined understanding from the brainstorm, gather the specific details needed for the spec. Batch related questions — don't force unnecessary round trips.

Key questions:
- What is the feature? (functional description — refined by brainstorm)
- What does "correct" mean? (the answer becomes invariants/rules)
- What must this feature NEVER do? (the answer becomes prohibitions/rules)
- What happens when this fails? Present the failure mode options:

```
Failure mode:
  1. Fail-closed (recommended) — reject the operation, return error
  2. Fail-open — allow the operation, log the failure
  3. Passthrough — forward to the next handler unchanged
  4. Crash — terminate the process

  Or type your own: ___
```
- **Full mode, if `require_stride` is true**: What is the adversary model? Who is trying to break this?
- **Full mode**: What existing abstractions does this touch? (reference .correctless/ARCHITECTURE.md ABS-xxx entries)

### Step 2: Research Current State (when needed)

After understanding what the human wants to build, assess whether your training data might be stale for this feature. **Be honest about this.** Don't confidently spec based on potentially outdated knowledge.

**Spawn the research subagent when ANY of these signals are present:**

**Explicit signals:**
- The human mentions a specific library, framework, or protocol version ("use Passkeys," "integrate with Stripe's new Payment Element," "implement OAuth 2.1")
- The human asks "what's the best way to do X?" — they're unsure and want current guidance
- The human references something recent ("announced last month," "the new version supports Y")
- The feature involves security-sensitive integration (auth, payments, crypto, certificates) where stale guidance is dangerous

**Inferred signals (detect these yourself):**
- You're not confident about current best practices for this topic
- Your knowledge about a library or protocol feels incomplete or potentially outdated
- The feature involves a rapidly-evolving area (frontend frameworks, auth protocols, cloud APIs, AI/ML tooling)
- The feature builds on existing project dependencies that may have changed status since adoption

**When triggered, say:** "This involves [topic] which may have evolved since my training data. Let me research current best practices before writing the spec."

**Spawn a research subagent** (forked context) with this prompt:

> You are a research agent supporting the spec phase. Your job is to find CURRENT best practices, recent changes, and known issues for the topics you're given. The spec agent will use your findings to write accurate invariants grounded in today's reality, not stale training data.
>
> RESEARCH TOPIC: {topic from the feature description}
> CONTEXT: {feature description}
> PROJECT: {project type from .correctless/AGENT_CONTEXT.md}
>
> Search for:
> 1. Current official documentation for the libraries/protocols involved
> 2. Recent security advisories and CVEs (last 12 months)
> 3. Current recommended patterns and architecture guidance
> 4. Recent breaking changes or deprecations in relevant libraries
> 5. Production experience reports from teams using this in production
> 6. Reference implementations from library authors
> 7. Dependency health: for every major dependency this feature touches (new AND existing), check EOL status, maintenance activity, deprecation announcements. A dependency with no releases in 12+ months is a red flag even without a formal EOL announcement.
>
> For each finding:
> - Include the source URL
> - Note the date (recency matters)
> - Explain relevance to the planned feature
> - State the implication for spec rules — what should the spec include or avoid?
>
> BE SKEPTICAL of your own training data. If your training says "use foo()" but search reveals foo() was deprecated and replaced by bar(), report the current state. Your value is in finding what's NEW.
>
> DO NOT: summarize training data (the spec agent has it), report without sources, include tangents, make design recommendations (that's the spec agent's job).
>
> Produce a structured brief:
>
> ```markdown
> # Research Brief: {Topic}
> # Searched: {date}
>
> ## Current State
> {2-3 paragraph summary}
>
> ## Key Findings
> ### {Finding 1}
> - **Source**: {URL}
> - **Relevance**: {how this affects the spec}
> - **Implication for rules**: {what rules should reflect this}
>
> ## Recommended Patterns
> {Current best practice with sources}
>
> ## Things to Avoid
> {Deprecated patterns, insecure approaches — with sources}
>
> ## Version Pins
> {Specific versions recommended, with rationale}
>
> ## Dependency Health
> | Dependency | Version | Status | Last Release | Notes |
> |------------|---------|--------|--------------|-------|
> | library-x  | 4.2.1   | Active | 2026-02-15   | |
> | library-y  | 2.0.3   | Deprecated | 2025-08-01 | Use library-z instead |
>
> ## Open Questions
> {Things research couldn't resolve}
> ```

The research subagent should have `allowed-tools: WebSearch, WebFetch, Read, Grep`. It returns the brief as text to you (the cspec orchestrator).

After receiving the research subagent's output, **you** (the cspec agent) write the brief to `.correctless/artifacts/research/{task-slug}-research.md`. Then read the brief before drafting the spec. Reference findings in the spec's invariants where relevant.

**If no research signals are present** (straightforward feature using well-understood patterns), skip this step. Don't research for the sake of researching.

### Step 3: Draft the Spec

Before drafting, read the appropriate spec template file and use it as the skeleton:
- Lite mode: read `templates/spec-lite.md` from the Correctless plugin directory
- Full mode: read `templates/spec-full.md` from the Correctless plugin directory

Use the template as the skeleton — fill in the placeholders with the feature-specific content rather than reconstructing the format from these instructions.

Write the spec to `.correctless/specs/{task-slug}.md`.

**Lite mode** — use 5 sections (What, Rules with R-xxx IDs, Won't Do, Risks, Open Questions). Keep it simple.

**Full mode** — use the full format. **Artifact weight scales with intensity**:
- `low` intensity: Metadata, Context, Scope, Invariants, Prohibitions (5 sections)
- `standard`: add Boundary Conditions
- `high`/`critical`: all sections including Complexity Budget, STRIDE, Environment Assumptions, Design Decisions

**Full mode spec format:**

```markdown
# Spec: {Task Title}

## Metadata
- **Created**: ISO timestamp
- **Status**: draft | reviewed | approved
- **Impacts**: (other spec slugs whose invariants may be affected)
- **Branch**: feature branch name
- **Research**: (path to research brief if research was conducted, null otherwise)

## Context
What this feature does and why. One paragraph.

## Scope
What this covers and — critically — what it does NOT.

## Complexity Budget (standard+)
- **Estimated LOC**: ~X
- **Files touched**: ~Y
- **New abstractions**: N
- **Trust boundaries touched**: N (refs: TB-xxx)
- **Risk surface delta**: low | medium | high

## Invariants
### INV-001: {short name}
- **Type**: must | must-not
- **Category**: functional | security | concurrency | data-integrity | resource-lifecycle | parity
- **Statement**: {precise testable statement}
- **Boundary**: {ref TB-xxx or ABS-xxx}
- **Violated when**: {specific condition}
- **Guards against**: {AP-xxx or null}
- **Test approach**: unit | property-based | integration
- **Risk**: low | medium | high | critical
- **Implemented in**: {filled during GREEN phase}

## Prohibitions
### PRH-001: {short name}
- **Statement**: {what must never happen}
- **Detection**: {test, linter, grep}
- **Consequence**: {what goes wrong}

## Boundary Conditions (standard+)
### BND-001: {short name}
- **Boundary**: {ref TB-xxx}
- **Input from**: {untrusted source}
- **Validation required**: {what to check}
- **Failure mode**: {fail-open? fail-closed?}

## STRIDE Analysis (high+ with require_stride)
### STRIDE for TB-xxx: {boundary name}
- Spoofing / Tampering / Repudiation / Info Disclosure / DoS / Elevation of Privilege

## Environment Assumptions (high+)
- **EA-001**: {assumption} — refs ENV-xxx — {consequence if wrong}

## Open Questions
- **OQ-001**: {question} — {why it matters}
```

**Lite mode spec format:**

```markdown
# Spec: {Task Title}

## What
One paragraph.

## Rules
- **R-001** [unit]: {testable statement}
- **R-002** [integration]: {testable statement}
- **R-003** [unit]: {testable statement}

Test level guide:
- [unit] — logic, validation, transformation. Can test in isolation.
- [integration] — wiring, config reaching runtime, lifecycle, middleware chains,
  cross-component communication. Must test through the real system path.

If a rule involves connecting components (parsed config → handler, registered callback →
invoked on event, middleware added → actually runs in chain), it MUST be [integration].
A unit test with hand-constructed mocks will not catch missing wiring.

## Won't Do
- {out of scope}

## Risks
- {risk} — {mitigation or "accepted"}

For each identified risk, present the acceptance decision:

  1. Mitigate (recommended) — add a rule or guard that addresses the risk
  2. Accept — document why this risk is tolerable
  3. Defer — log for a future feature to address

  Or type your own: ___

## Open Questions
- {question}

### Packages Affected (monorepo only)
If `workflow-config.json` has `is_monorepo: true`, add a "Packages Affected" section to the spec listing which packages this feature touches. Rules should note which package they apply to if they're package-specific.
```

### Compliance Checks

If `workflow.compliance_checks` in `workflow-config.json` has entries with `phase: "spec"`, run them before presenting the spec. Report pass/fail results. If `blocking: true` and a check fails, warn the human: "Compliance check '{name}' failed — the spec may need to address this before proceeding." Do not refuse to present the spec, but make the failure prominent.

### Step 4: Load Invariant Templates (Full Mode)

In Full mode, check which invariant template categories apply to this feature. Search for templates in these locations (in order of priority — project-specific templates from `/cpostmortem` override shipped defaults):
1. `.claude/templates/invariants/` — project-specific templates created by `/cpostmortem`
2. The plugin's `templates/` directory — shipped with Correctless

Template categories:
- `concurrency.md` — if feature involves goroutines, channels, mutexes, shared state
- `resource-lifecycle.md` — if feature allocates resources
- `config-lifecycle.md` — if feature adds/modifies config fields
- `network-protocol.md` — if feature involves network, TLS, protocols
- `security-detection.md` — if feature involves detection rules or security decisions
- `data-integrity.md` — if feature transforms, stores, or transmits data

Walk through applicable template items with the human. Relevant items become draft invariants. Skip irrelevant items with a noted reason.

### Step 5: Check Antipatterns

For each AP-xxx entry in `.correctless/antipatterns.md`, ask: does this feature risk repeating this bug class? If yes, add a rule/invariant that prevents it (with `guards_against: AP-xxx` in Full mode).

### Step 6: Check Drift Debt (Full Mode)

Read `.correctless/meta/drift-debt.json`. If any open drift items involve files or abstractions this feature touches, surface them to the human.

### Step 7: Recommend Intensity (Full Mode)

After drafting the spec, recommend an intensity level:
- Touches a trust boundary → recommend `high` or `critical`
- Security-categorized invariants → recommend `high` or `critical`
- Concurrency invariants → recommend at least `standard`
- Pure functional change → `low` is fine

The recommendation is advisory — the human decides.

### Step 8: Present to Human

Walk through the rules/invariants with the human. Present them in small groups, ask for confirmation or correction. Open questions must be resolved before moving forward.

### Step 9: Advance State

Once the human approves the spec, advance to review. **Review is MANDATORY — never skip it, regardless of feature size.** The review always finds issues.

```bash
# Lite mode:
.correctless/hooks/workflow-advance.sh review

# Full mode (with formal modeling):
.correctless/hooks/workflow-advance.sh model

# Full mode (without formal modeling):
.correctless/hooks/workflow-advance.sh review-spec
```

After advancing, print the pipeline diagram showing progress:

Lite mode:
```
  ✓ spec → ▶ review → tdd → verify → docs → merge
```

Full mode (if advancing to model):
```
  ✓ spec → ▶ model → review → tdd → verify → arch → docs → audit → merge
```

Full mode (if advancing to review-spec, i.e. no formal model):
```
  ✓ spec → ▶ review → tdd → verify → arch → docs → audit → merge
```

After advancing, tell the human to run `/creview` (Lite) or `/creview-spec` (Full). Do NOT proceed to `/ctdd` yourself. The review must happen first.

## Claude Code Feature Integration

### Task Lists
See "Progress Visibility" section above — task creation and narration are mandatory.

### Token Tracking

After the research subagent completes (when triggered), capture `total_tokens` and `duration_ms` from the completion result. Append an entry to `.correctless/artifacts/token-log-{slug}.json` (derive slug from the task slug):

```json
{
  "skill": "cspec",
  "phase": "research",
  "agent_role": "research-agent",
  "total_tokens": N,
  "duration_ms": N,
  "timestamp": "ISO"
}
```

If the file doesn't exist, create it with the first entry. `/cmetrics` aggregates from raw entries — no totals field needed. Only logged when the research subagent is triggered.

### /btw
When presenting the spec for review, mention: "If you need to check something about the codebase without interrupting this review, use /btw."

### /export
After spec approval, suggest: "Consider exporting this conversation as a decision record: `/export .correctless/decisions/{task-slug}-spec.md` — captures why these specific rules were chosen."

## Code Analysis (MCP Integration)

### Serena — Symbol-Level Code Analysis

If `mcp.serena` is `true` in `workflow-config.json`, use Serena MCP for symbol-level code analysis during codebase exploration and pattern mining:

- Use `find_symbol` instead of grepping for function/type names
- Use `find_referencing_symbols` to trace callers and dependencies
- Use `get_symbols_overview` for structural overview of a module
- Use `replace_symbol_body` for precise edits (not used in this skill — spec writing is read-only)
- Use `search_for_pattern` for regex searches with symbol context

**Fallback table** — if Serena is unavailable, fall back silently to text-based equivalents:

| Serena Operation | Fallback |
|-----------------|----------|
| `find_symbol` | Grep for function/type name |
| `find_referencing_symbols` | Grep for symbol name across source files |
| `get_symbols_overview` | Read directory + read index files |
| `replace_symbol_body` | Edit tool |
| `search_for_pattern` | Grep tool |

**Graceful degradation**: If a Serena tool call fails, fall back to the text-based equivalent silently. Do not abort, do not retry, do not warn the user mid-operation. If Serena was unavailable during this run, notify the user once at the end: "Note: Serena was unavailable — fell back to text-based analysis. If this persists, check that the Serena MCP server is running (`uvx serena-mcp-server`)." Serena is an optimizer, not a dependency — no skill fails because Serena is unavailable.

### Context7 — Library Documentation

If `mcp.context7` is `true` in `workflow-config.json`, use Context7 for the research subagent's library documentation lookups:

- Use `resolve-library-id` to find the canonical ID for a library before fetching docs
- Use `get-library-docs` to retrieve current documentation and API references

When Context7 is unavailable, fall back to web search for library documentation. If Context7 was unavailable during this run, notify the user once at the end: "Note: Context7 was unavailable — fell back to web search for library docs."

## If Something Goes Wrong

- **Skill interrupted**: Re-run the skill. It reads the current state and resumes where possible.
- **Rate limit hit**: Wait 2-3 minutes and re-run. Workflow state persists between sessions.
- **Wrong output**: This skill doesn't modify workflow state until the final advance step. Re-run from scratch safely.
- **Stuck in a phase**: Run `/cstatus` to see where you are. Use `workflow-advance.sh override "reason"` if the gate is blocking legitimate work.

## Constraints

- **NEVER write code.** Not even test stubs. This skill produces a spec document, nothing else.
- **Every rule/invariant MUST be testable.** If you can't describe a test for it, rewrite it until you can or remove it.
- **If on main branch**, tell the user to create a feature branch first.
- **Do NOT produce a self-assessment.** You are biased toward your own spec. The review skill will assess it with fresh eyes.
- **Batch questions by theme** when the human clearly understands the domain. Reserve one-at-a-time for genuinely ambiguous answers.
- **Full mode**: NEVER skip STRIDE for features touching trust boundaries (unless `require_stride` is false).
- **NEVER skip the Socratic Brainstorm (Step 0).** Even experienced developers benefit from 2-3 reframing questions. The brainstorm is sequential and not subject to question batching.
- **NEVER skip review.** Do not advance directly to tests. Do not suggest skipping review because the feature is small. The review step is enforced by the state machine and always produces value.
- **Never auto-invoke the next skill.** Tell the human what comes next and let them decide when to run it. The boundary between skills is the human's decision point.
