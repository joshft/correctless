---
name: cspec
description: Create a structured specification with testable invariants for a new feature. Researches current best practices before writing invariants. Adapts format to workflow intensity.
allowed-tools: Read, Grep, Glob, Edit, Bash(git log*), Bash(git diff*), Bash(git branch*), Bash(*workflow-advance.sh*), Bash(*harness-fingerprint*), Write(.correctless/specs/*), Write(.correctless/artifacts/research/*), Write(.correctless/artifacts/token-log-*), Write(.correctless/ARCHITECTURE.md), Write(.correctless/AGENT_CONTEXT.md), Write(.claude/rules/*.md), WebSearch, WebFetch
---

# /cspec — Write a Feature Specification

> **Shared constraints apply.** Before executing, read `_shared/constraints.md` from the parent of this skill's base directory. All constraints there apply to this skill.

You are the spec agent. Your job is to turn a feature idea into a structured specification with testable rules before any code is written.

## Intensity Configuration

| | Standard | High | Critical |
|---|---|---|---|
| Sections | 5 + typed rules | 12 + invariants | 12 + all templates |
| Research agent | If needed | Always (security) | Always |
| STRIDE | No | Yes | Yes |
| Question depth | Socratic | Adversarial | Exhaustive |

## Effective Intensity

Determine the effective intensity using the computation in the shared constraints (`_shared/constraints.md`).

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
4. **At high+ intensity**: Read `.correctless/meta/drift-debt.json` for outstanding drift debt.
5. **At high+ intensity**: Read `.correctless/meta/workflow-effectiveness.json` for phase effectiveness history.
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

<!-- correctless:harness-fingerprint:invocation -->
### Step -1: Harness fingerprint check (advisory, runs before Step 0)

Before any Socratic brainstorm runs, invoke the harness fingerprint check. This compares the current `{model_name}+HARNESS_VERSION}` against the stored value in `.correctless/meta/harness-fingerprint.json` and emits a one-line advisory if a version bump is detected.

```bash
bash .correctless/scripts/harness-fingerprint.sh check 2>/dev/null || true
```

The script is **strictly advisory** (PRH-001 of the harness-fingerprint spec) — it always exits 0 and never blocks /cspec. If the output reports `status=version_bumped` AND `notified=true`, surface the line `Harness has changed (model={X} version={Y}). Run /cmodelupgrade to compare metrics against baseline.` to the user one time per session. Then continue immediately to Step 0 below regardless of the script's output.

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
- **At high+ intensity, if `require_stride` is true**: What is the adversary model? Who is trying to break this?
- **At high+ intensity**: What existing abstractions does this touch? (reference .correctless/ARCHITECTURE.md ABS-xxx entries)

### Step 1a: TB-xxx Scope Matching (high+ intensity)

**At high+ intensity**, after gathering the feature's file scope from Step 0 brainstorm and Step 1 questions, run a "TB-xxx scope matching" substep. This mechanically identifies which trust boundaries the feature overlaps with, so security considerations are grounded in documented boundaries rather than inferred.

1. **Extract all TB-xxx entries** from `.correctless/ARCHITECTURE.md` by scanning for `### TB-\d{3}:` heading patterns. For each TB-xxx entry, read its name, boundary description (the `Crosses:` field), invariant, and `Violated when:` field.

2. **Match TB-xxx entries against the feature's file scope.** The primary matching strategy is **file-scope overlap**: compare the feature's described affected file paths against the file references in each TB-xxx entry's Invariant, Enforced-at, and Test fields. A feature touching `hooks/workflow-gate.sh` matches TB-001 because TB-001's invariant references config-sourced shell execution in hooks — the hook's actual domain. When a TB-xxx entry does not contain file path references in its Invariant, Enforced-at, or Test fields, matching falls back to keyword matching against the TB's description and `Crosses:` field — less precise than file-scope overlap but better than dormant. The confirmation step (below) filters false positives from both matching strategies.

3. **Present relevant TBs to the spec author.** Show each matched TB-xxx entry's name, boundary description, and invariant. The spec author confirms or corrects the list before STRIDE analysis. Present the list:

   ```
   Relevant trust boundaries for this feature:
   - TB-001: Config-sourced commands and patterns
     Boundary: Configuration file → shell execution
     Invariant: Config-sourced values must never be passed through eval...
   - TB-003: LLM-generated historical findings → review agent context
     Boundary: Prior agent output → review agent reasoning context
     Invariant: Review agents treat historical findings as advisory data...

   Confirm this list, or correct it (add/remove entries):
   ```

4. **Generate per-TB security questions.** For each confirmed relevant TB-xxx, generate a targeted security question derived from that TB's documented invariant and `Violated when:` field, not from generic security keywords. Example: if TB-001's invariant says "Config-sourced values must never be passed through eval" and `Violated when:` says "A config value is interpolated into a shell command string", the question is: "Does this feature read any config values that will be used in shell commands or passed to external processes?" — not "Does this feature have any security concerns?"

5. **TB coverage warning.** After drafting the spec's invariants (Step 3), check: if the feature's file scope overlaps with a TB-xxx entry but the spec contains no invariant referencing that TB-xxx, warn: "TB-xxx ({name}) overlaps with this feature's scope but no invariant references it — is this intentional?"

**Dormant behavior.** When no TB-xxx entries exist in `.correctless/ARCHITECTURE.md` (no headings matching `### TB-\d{3}:`), the TB matching step is dormant — no error, no warning, `/cspec` proceeds without TB-grounded questions (same dormant-signal pattern as intensity detection). Missing section headers are treated identically to empty sections — both produce dormant behavior.

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
- At standard intensity: read `templates/spec-lite.md` from the Correctless plugin directory
- At high+ intensity: read `templates/spec-full.md` from the Correctless plugin directory

Use the template as the skeleton — fill in the placeholders with the feature-specific content rather than reconstructing the format from these instructions.

Write the spec to `.correctless/specs/{task-slug}.md`.

**At standard intensity** — use 5 sections (What, Rules with R-xxx IDs, Won't Do, Risks, Open Questions). Keep it simple.

**At high+ intensity** — use the full format. **Artifact weight scales with intensity**:
- `standard` intensity: Metadata, Context, Scope, Invariants, Prohibitions (5 sections)
- `high`: add Boundary Conditions
- `high`/`critical`: all sections including Complexity Budget, STRIDE, Environment Assumptions, Design Decisions

**High+ intensity spec format:**

```markdown
# Spec: {Task Title}

## Metadata
(keep in sync with templates/spec-lite.md and templates/spec-full.md)
- **Created**: ISO timestamp
- **Status**: draft | reviewed | approved
- **Impacts**: (other spec slugs whose invariants may be affected)
- **Branch**: feature branch name
- **Research**: (path to research brief if research was conducted, null otherwise)
- **Intensity**: (standard|high|critical)
- **Recommended-intensity**: (standard|high|critical)
- **Intensity reason**: (triggering signals or "user override")
- **Override**: (none|raised|lowered)

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
- **Enforcement**: {structural mechanism from PAT-018: allowed-tools restrictions | sensitive-file-guard | gate precondition | hash verification | CI test assertion | agent tool-pinning | prompt-level (fallback when no structural mechanism applies)}
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
STRIDE analysis runs per confirmed relevant TB-xxx entry from Step 1a, not per inferred boundary. Each STRIDE section header references the specific TB-xxx ID.
### STRIDE for TB-xxx: {boundary name}
- Spoofing / Tampering / Repudiation / Info Disclosure / DoS / Elevation of Privilege

## Environment Assumptions (high+)
- **EA-001**: {assumption} — refs ENV-xxx — {consequence if wrong}

## Open Questions
- **OQ-001**: {question} — {why it matters}
```

**Standard intensity spec format:**

```markdown
# Spec: {Task Title}

## Metadata
(keep in sync with templates/spec-lite.md and templates/spec-full.md)
- **Task**: {feature name}
- **Intensity**: {standard|high|critical}
- **Recommended-intensity**: {standard|high|critical}
- **Intensity reason**: {triggering signals or "user override"}
- **Override**: {none|raised|lowered}

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

### Intensity-Aware Spec Writing

- At standard intensity: use `templates/spec-lite.md`, 5-section format, Socratic brainstorm. Research agent runs if needed based on signal detection.
- At high intensity: use `templates/spec-full.md`, 12 sections including invariants. Research agent always runs for security-relevant topics. STRIDE analysis required for features touching trust boundaries.
- At critical intensity: all templates loaded, exhaustive question depth (refuse vague answers). Research agent always runs regardless of topic.

### Step 3a: Pattern Detection and Composition Check

**Pattern detection substep (at all intensities).** After drafting the spec rules in Step 3, extract all PAT-xxx entries from `.correctless/ARCHITECTURE.md` by scanning for `### PAT-\d{3}:` heading patterns. For each spec rule, check whether it introduces a convention not covered by an existing PAT-xxx entry. A "convention" is a repeated structural pattern — how files are organized, how hooks compose, how state flows between skills, how artifacts are named.

When pattern detection identifies a potential new pattern not covered by any existing PAT-xxx, present it to the spec author: "This rule introduces a convention ({description}). No existing PAT-xxx covers this. Flag for `/cupdate-arch` after implementation?" The human decides whether the pattern warrants a PAT entry.

**Pattern composition check (at high+ intensity).** For each potential new pattern identified by pattern detection above, check it against existing PAT-xxx entries and warn if it contradicts or duplicates an existing pattern, citing the specific PAT-xxx ID and the conflict. Example: "R-005 introduces direct state file writes, which contradicts PAT-004 (Branch-scoped state — workflow-advance.sh is the only writer)." If pattern detection finds no new patterns, the composition check has nothing to check.

**Dormant behavior.** When no PAT-xxx entries exist in `.correctless/ARCHITECTURE.md` (no headings matching `### PAT-\d{3}:`), pattern detection and composition checking are dormant — no error, no warning. Missing section headers are treated identically to empty sections — both produce dormant behavior.

### Step 4: Load Invariant Templates (Full Mode)

At high+ intensity, check which invariant template categories apply to this feature. Search for templates in these locations (in order of priority — project-specific templates from `/cpostmortem` override shipped defaults):
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

### Step 4a: Integration Test Contracts

For each rule tagged `[integration]`, define an integration test contract with Entry/Through/Exit constraints. This step requires ABS-023 (entrypoints YAML contract) and ABS-024 (Entry/Through/Exit contract format) from `.correctless/ARCHITECTURE.md`.

**Prerequisite check**: Before writing integration test contracts, check whether `.correctless/ARCHITECTURE.md` exists and contains entrypoints (the `<!-- correctless:entrypoints:start -->` / `<!-- correctless:entrypoints:end -->` markers exist and the block is non-empty). If the file does not exist or no entrypoints are defined: "ARCHITECTURE.md has no entrypoints defined. Integration test contracts require entrypoints to derive Entry fields. Run `/carchitect` to define them, or skip integration contracts for this spec." If the user chooses to skip, `[integration]` rules are written without Entry/Through/Exit blocks — the existing behavior. The spec agent does NOT attempt to infer entrypoints from the codebase during spec writing.

**Entrypoint matching**: Read the entrypoints YAML from `.correctless/ARCHITECTURE.md` (via `scripts/extract-entrypoints.sh` or by reading the fenced YAML directly). For each `[integration]` rule, match it to an entrypoint whose `scope` globs overlap with the rule's affected files, and use that entrypoint's `test_via` field as the Entry value. The spec agent infers affected files from the rule's description text, the feature scope in the spec's What section, and files referenced by other rules in the same spec. This is LLM judgment — the human confirms or corrects during spec review.

If no entrypoint matches: "No matching entrypoint for R-xxx — the Entry field is unresolved. Consider adding an entrypoint via `/carchitect`."

**Multi-entrypoint split**: If a rule's scope spans multiple entrypoints, split the rule into one `[integration]` rule per entrypoint, each with its own Entry/Through/Exit contract sharing the same Exit constraint. Present the split to the human: "R-003 spans 3 entrypoints — splitting into R-003, R-004, R-005 with separate contracts." Split rules use sequential IDs (the standard R-NNN format), not suffixed IDs. A comment on each split rule notes the original: "(split from original R-003 — HTTP path)" so the lineage is traceable. Subsequent rules are renumbered.

For each `[integration]` rule, append an Entry/Through/Exit block:

```
- **R-003** [integration]: Config values reach the runtime handler
  Entry: httptest.NewServer(handler) — real server, real middleware chain
  Through: request passes through auth middleware and config-injection middleware; auth middleware and ConfigService must NOT be mocked, must be exercised
  Exit: response body contains the config-sourced value; no mock of ConfigService
```

The three fields are:
- **Entry**: which entrypoint the test must use (derived from `.correctless/ARCHITECTURE.md` `test_via` field for the matching entrypoint)
- **Through**: which components must be exercised on the real path, and which must NOT be mocked. The "must not mock" list is the critical constraint — it tells the TDD agent what it is not allowed to fake.
- **Exit**: what observable behavior must hold at the end of the test. Must be expressible as a test assertion without accessing internal state.

**Exit field guidance**: The Exit field specifies observable behavior, not implementation details. Positive example (observable assertion): "response body contains the config-sourced value." Negative example (implementation-detail assertion): "Function Y was called" — this tests implementation, not behavior.

**Unit rules excluded**: Rules tagged `[unit]` do NOT get Entry/Through/Exit blocks. The contract format applies only to `[integration]` rules. Unit rules continue to be written as they are today.

### Step 5: Check Antipatterns

For each AP-xxx entry in `.correctless/antipatterns.md`, ask: does this feature risk repeating this bug class? If yes, add a rule/invariant that prevents it (with `guards_against: AP-xxx` at high+ intensity).

### Step 5a: Allowed-Tools Cross-Check (AP-008)

After drafting the spec, cross-check every file write and shell command the spec instructs a skill to perform against that skill's `allowed-tools` frontmatter. This is a mechanical check, not a judgment call.

For each invariant or instruction in the spec that says a skill should write to a path or run a command:
1. Identify the target skill (e.g., "cverify outputs to `.correctless/meta/calibration.json`" → skill is cverify)
2. Read the target skill's SKILL.md frontmatter (`allowed-tools` line)
3. For file writes: verify a matching `Write(path)` entry exists (glob matching — `Write(.correctless/artifacts/*)` covers `Write(.correctless/artifacts/foo.json)`)
4. For shell commands: verify a matching `Bash(pattern)` entry exists (glob matching — `Bash(jq*)` covers `jq -R ...`)

If a match is missing, add it to the spec as a prerequisite: "Prerequisite: add `Write(path)` to {skill}'s allowed-tools frontmatter" or "Prerequisite: add `Bash(pattern)` to {skill}'s allowed-tools." This ensures the implementation agent knows to update the frontmatter.

Skip this check for skills with `Bash(*)` or `Write(*)` (unrestricted permissions) — they can do anything.

### Step 5b: Antipattern Promotion Check

After the relevance check above, run the promotion check as a separate concern. The promotion check fires regardless of relevance to the current feature — an antipattern that appeared across 5 features but is irrelevant to the current feature still qualifies for promotion to `.correctless/ARCHITECTURE.md`.

For each AP-xxx entry, parse the Frequency field (format: "N findings across M features"). If the frequency indicates 3 or more features, and the AP-xxx is NOT already referenced in `.correctless/ARCHITECTURE.md` (deduplication — search for the literal `AP-xxx` string in `.correctless/ARCHITECTURE.md`), suggest promotion to a `.correctless/ARCHITECTURE.md` entry.

**Draft the promotion entry:** Draft a PAT-xxx or ABS-xxx skeleton (choose PAT-xxx for process/convention patterns, ABS-xxx for code-level invariants). The draft must include:
- Use "How to catch it" from the antipattern to pre-populate the Rule/Invariant field
- Use "What went wrong" from the antipattern to inform the Violated-when field
- The promotion draft must include a `Guards against: AP-xxx` field referencing the antipattern ID
- Include a Test field describing how the architectural entry would be verified

**Cap:** Present at most 2 promotion suggestions per invocation. After the 2nd suggestion, stop evaluating further antipatterns for promotion — defer all remaining qualifying candidates to the next run.

**Graceful handling:** If an entry has a missing Frequency field or malformed Frequency value (not matching "N findings across M features"), skip that entry — no promotion suggestion, no error.

**Structured promotion decision:** Present each promotion suggestion with numbered options:
1. Add to `.correctless/ARCHITECTURE.md` (recommended) — write the drafted PAT-xxx or ABS-xxx entry
2. Skip — this antipattern doesn't warrant an architecture entry
3. Modify the draft before adding
4. Defer to a future feature

Or type your own: ___ (promotion decisions require explicit human input)

The human must approve before writing to `.correctless/ARCHITECTURE.md` — never auto-write.

### Step 6: Check Drift Debt (Full Mode)

Read `.correctless/meta/drift-debt.json`. If any open drift items involve files or abstractions this feature touches, surface them to the human.

### Step 7: Run Intensity Detection

Before presenting the spec, run the Intensity Detection process described below. This is NOT gated by Full Mode or any config setting.

1. Evaluate all four detection signals against the feature scope (file paths, keywords, trust boundaries, antipattern/QA history).
2. Apply the signal-to-intensity mapping to determine the recommended level.
3. Check the humility qualifier (project maturity from workflow-history.md).
4. Check project floor from `workflow.intensity` config (R-009).
5. Check `workflow.allow_intensity_downgrade` config (R-008).
6. Record the recommendation with triggering signals for presentation in Step 8.

See the **Intensity Detection** section below for the full signal definitions, mapping rules, and configuration options.

### Step 7b: Intensity Calibration (Post-Signal Modifier)

After the 4-signal highest-wins evaluation in Step 7, apply the intensity calibration modifier. Calibration is NOT a 5th signal and is not an additional signal in the signal hierarchy — it is a post-signal modifier that runs after the signal evaluation completes. Calibration can only raise the result; it never lowers the result below what the 4 signals produced.

**Read calibration data (read-only):** Read `.correctless/meta/intensity-calibration.json` if it exists. This file is read-only for `/cspec` — never write, modify, or delete calibration entries. Only `/cverify` writes calibration entries.

**Graceful handling:** If the calibration file does not exist or contains zero entries, the calibration signal is dormant — proceed without calibration input. No error, no warning, no change to the recommendation. This follows the same dormant signal pattern as antipattern/QA history signals. Skip calibration and proceed normally.

**Recency window:** Read at most the 50 most recent entries (sorted by timestamp, newest first). Entries beyond 50 are ignored — this caps file read size and naturally de-escalates as recent features at elevated intensity run clean. Ignore older entries beyond the limit of 50.

**File path overlap:** For each file path in the current feature's scope, find calibration entries whose `file_paths_touched` have any overlap (at least one file path in common). In active mode, filter overlapping entries to those whose `recommended_intensity` matches the current feature's recommended intensity — evaluate thresholds against what the system suggested at the same level. In passive mode, include all overlapping entries regardless of `recommended_intensity`. Compute the arithmetic mean of `actual_qa_rounds` and `actual_findings_count` across the resulting entries.

**Token-aware calibration (actual_tokens):** Also read `actual_tokens` from each overlapping calibration entry. Compute the arithmetic mean of `actual_tokens` only across entries where `actual_tokens` is present and greater than 0 — entries without `actual_tokens` (or with `actual_tokens: 0`) are excluded from the token-specific arithmetic. Entries without `actual_tokens` still participate in QA rounds and BLOCKING findings arithmetic unchanged — they are only excluded from the token average. This prevents legacy entries written before this feature from diluting the token signal. No error or warning for legacy entries missing `actual_tokens`.

**Read calibration mode:** Read `intensity_calibration_mode` from `workflow-config.json` (under `workflow`). If absent from config, default to `passive`.

**Mode behaviors:**

- **Passive mode:** Show advisory text with full calibration arithmetic during Step 8 presentation. List the overlapping entries with their feature slugs and values, show the sum, count, and average for QA rounds and BLOCKING findings (all overlapping entries), and for actual_tokens (sum, count, and average computed only across entries with token data per the token-aware calibration rules above). State the threshold comparison (threshold: 3 QA rounds or 8 BLOCKING findings or 200,000 tokens). Include an example showing actual_tokens calibration data. Include override context: "In {K} of {N} cases, the user overrode the recommendation." The user sees the math, not just the conclusion — show the intermediate calculation. No automatic adjustment.

- **Active mode:** If overlapping calibration entries show average `actual_qa_rounds` >= 3, or average `actual_findings_count` >= 8, or average `actual_tokens` >= 200,000, auto-raise the recommendation by one level (standard to high, high to critical). In active mode, evaluate at the `recommended_intensity` (not `actual_intensity`) — learn from what the system suggested, not what was used after override. Show the same calibration arithmetic as passive mode but note "auto-raised from {old} to {new} based on calibration data." Calibration can only raise, never lower.

- **Hybrid mode:** Behave as passive until 5+ total calibration entries exist (global count of all entries, not per-path), then switch to active behavior.

**Calibration arithmetic display (INV-012):** When calibration data produces advisory text (passive) or an auto-raise (active), show the intermediate calculation so the user can see the math:
1. List overlapping entries with feature slugs and values
2. Show the sum, count, and average for QA rounds, BLOCKING findings, and actual_tokens
3. State the threshold comparison (>= 3 rounds or >= 8 findings or >= 200,000 threshold for actual_tokens)
4. Show the number of overlapping entries and their average calibration values

Example passive advisory with actual_tokens calibration example:
```
Calibration: 3 prior features touching these paths averaged 3.7 QA rounds, 6 BLOCKING findings, and 145,000 actual_tokens at recommended_intensity=standard.
  - feature-a: 4 rounds, 8 findings, 180,000 tokens
  - feature-b: 3 rounds, 5 findings, 120,000 tokens
  - feature-c: 4 rounds, 5 findings, 135,000 tokens
Sum: 11 rounds, 18 findings, 435,000 tokens. Count: 3 entries (3 with token data). Average: 3.7 rounds, 6.0 findings, 145,000 actual_tokens.
Threshold: 3 rounds or 8 findings or 200,000 tokens. Average rounds (3.7) exceeds threshold (3).
In 1 of 3 cases, the user overrode the recommendation.
Consider high intensity.
```

### Step 8: Present to Human

Walk through the rules/invariants with the human. Present them in small groups, ask for confirmation or correction. Open questions must be resolved before moving forward.

**Recommended-intensity field (Step 8):** During Step 8, write the `Recommended-intensity` field to the spec's `## Metadata` section. The `Recommended-intensity` field stores the pre-override system recommendation — the level that intensity detection (Step 7 + calibration) produced before the user sees override options. The `Intensity` field continues to store the post-override (approved) level. Both fields appear in the Metadata section: `Recommended-intensity` records what the system suggested, `Intensity` records what was approved after the user's decision. This distinction enables the calibration loop — `/cverify` reads both fields to measure recommendation accuracy.

### Step 9: Advance State

Once the human approves the spec, advance to review. **Review is MANDATORY — never skip it, regardless of feature size.** The review always finds issues.

```bash
# At standard intensity:
.correctless/hooks/workflow-advance.sh review

# At high+ intensity (with formal modeling):
.correctless/hooks/workflow-advance.sh model

# At high+ intensity (without formal modeling):
.correctless/hooks/workflow-advance.sh review-spec
```

After advancing, print the pipeline diagram showing progress:

At standard intensity:
```
  ✓ spec → ▶ review → tdd → verify → docs → merge
```

At high+ intensity (if advancing to model):
```
  ✓ spec → ▶ model → review → tdd → verify → arch → docs → audit → merge
```

At high+ intensity (if advancing to review-spec, i.e. no formal model):
```
  ✓ spec → ▶ review → tdd → verify → arch → docs → audit → merge
```

After advancing, tell the human to run `/creview` (at standard intensity) or `/creview-spec` (at high+ intensity). Do NOT proceed to `/ctdd` yourself. The review must happen first.

## Claude Code Feature Integration

### Task Lists
See "Progress Visibility" section above — task creation and narration are mandatory.

### Token Tracking

Log token usage following the shared constraints (`_shared/constraints.md`). Only logged when the research subagent is triggered. Skill-specific values:
- `skill`: "cspec"
- `phase`: "research"
- `agent_role`: "research-agent"

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

### Context7 — Library Documentation

If `mcp.context7` is `true` in `workflow-config.json`, use Context7 for the research subagent's library documentation lookups:

- Use `resolve-library-id` to find the canonical ID for a library before fetching docs
- Use `get-library-docs` to retrieve current documentation and API references

## Intensity Detection

Per-feature intensity detection evaluates four signals to recommend an intensity level (standard, high, or critical) for the current feature. It runs for all projects regardless of whether `workflow.intensity` is set in config.

### Detection Signals

The detection uses four signals. Each signal is evaluated independently against the feature's scope (affected files, spec content, feature description):

1. **File path patterns signal**: If any affected file paths match `hooks/`, security-related skills, or setup scripts, the recommended intensity is at least `high`.

2. **Keyword matching signal**: Scan the spec and feature description for security-sensitive keywords.
   - Keywords producing at least `high`: auth, credential, payment, encrypt, token, secret, session, certificate, CSRF, injection
   - Keywords producing `critical`: trust boundary, adversary, threat model, penetration

3. **Trust boundary signal (TB-xxx)**: If the spec references TB-xxx identifiers from `.correctless/ARCHITECTURE.md`, the recommended intensity is at least `high`. If `.correctless/ARCHITECTURE.md` contains no TB-xxx entries, this signal is dormant.

4. **Antipattern/QA history signal**: Check whether the feature's affected files overlap with known antipatterns or historical QA findings.
   - If 2 or more antipattern matches overlap with the feature scope in `.correctless/antipatterns.md`, recommend at least `high`.
   - If 3 or more historical QA findings (from `qa-findings-*.json` files) reference specs in the same area, recommend at least `high`.
   - When `antipatterns.md` does not exist, the antipattern signal is dormant.
   - When no `qa-findings-*.json` files exist, the QA history signal is dormant.

A dormant signal does not contribute to the recommendation — it is not an error condition.

### Signal-to-Intensity Mapping

| Signal | Condition | Minimum Intensity |
|--------|-----------|-------------------|
| File path | Matches `hooks/`, security skills, setup | high |
| Keyword | auth, credential, payment, encrypt, token, secret, session, certificate, CSRF, injection | high |
| Keyword | trust boundary, adversary, threat model, penetration | critical |
| TB-xxx ref | Spec references TB-xxx from `.correctless/ARCHITECTURE.md` | high |
| Antipattern | 2+ antipattern matches overlap with feature scope | high |
| QA history | 3+ QA findings in affected area | high |

When multiple signals fire, the final recommendation is the **highest intensity level** among all triggered signals (highest-wins). The ordering is: `standard < high < critical`. If no signals trigger, the default recommendation is `standard` (or the project floor, whichever is higher).

### Humility Qualifier

Count `###` headers in `docs/workflow-history.md` to determine project maturity. If the file does not exist, the count is 0.

- **Fewer than 5 completed features**: Include a humility qualifier in the recommendation — language indicating "low confidence due to limited project history." The detection has insufficient calibration data and should say so explicitly.
- **5 or more completed features**: State the recommendation confidence without the qualifier — the detection has enough history to be reliable.

### Project Floor (R-009)

When `workflow.intensity` is set, it acts as a floor — detection can recommend higher but never lower than the configured project-level intensity. When `workflow.intensity` is absent, `standard` is the baseline.

If `workflow.intensity` contains a value not in the detection vocabulary (`standard`/`high`/`critical`) — such as `low` — treat it as `standard` for floor comparison purposes. The detection vocabulary only uses three levels; any unrecognized value maps to the lowest detection level.

### Downgrade Policy (R-008)

Check `workflow.allow_intensity_downgrade` in `workflow-config.json`:
- If `false`: the user cannot lower the intensity below the recommended level. They can still raise it.
- If absent or `true`: the user can override in both directions (raise or lower).

### Configurable Signals (R-010)

Detection signals are configurable via an optional `workflow.intensity_signals` object in `workflow-config.json`. The `intensity_signals` object supports `path_patterns` and `keywords` arrays. If absent, the built-in defaults from the mapping table above are used. If present, the object overrides signal mappings using this structure:

```json
{
  "workflow": {
    "intensity_signals": {
      "path_patterns": [{"glob": "hooks/*", "intensity": "high"}],
      "keywords": [{"word": "auth", "intensity": "high"}],
      "keyword_floor": "high",
      "path_floor": "high"
    }
  }
}
```

`keyword_floor` and `path_floor` set the minimum intensity level for any keyword or path pattern match, respectively.

Valid intensity values are: `standard`, `high`, `critical`. If `intensity_signals` is present but malformed (missing expected keys, invalid values, wrong types), fall back to the built-in defaults and log a one-line warning to the user about the malformed config.

### Spec Metadata (R-005)

Every spec produced by `/cspec` includes a `## Metadata` section at the top containing at minimum:
- **Task** (feature name)
- **Intensity** (the approved level: standard/high/critical)
- **Intensity reason** (which signals triggered the recommendation, or "user override" if overridden)
- **Override** field (none, raised, or lowered — indicating whether the user changed the recommendation)

### Writing Intensity to State (R-006)

After the user approves the intensity, write `feature_intensity` to the workflow state file. Call `workflow-advance.sh set-intensity` during Step 8 after the user approves the intensity, before advancing the workflow in Step 9.

```bash
.correctless/hooks/workflow-advance.sh set-intensity "level"
```

Do NOT write directly to the state file via jq. Only workflow-advance.sh is the state file writer (PAT-004).

### Presentation in Step 8

Present the intensity recommendation as the **first item in Step 8** (human presentation), before walking through the rules. The presentation includes:

1. The recommended intensity level
2. The signals that triggered the recommendation (with specific file paths or keywords found)
3. The humility qualifier if applicable (fewer than 5 completed features)
4. Numbered options for the user:
   1. Accept [level] (recommended)
   2. Raise to [higher level]
   3. Lower to [lower level]
   4. Override with custom level

Mark the recommended option with "(recommended)".

If `workflow.allow_intensity_downgrade` is `false`, omit the "lower" option and note that downgrading is disabled by project config.

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
- **At high+ intensity**: NEVER skip STRIDE for features touching trust boundaries (unless `require_stride` is false).
- **NEVER skip the Socratic Brainstorm (Step 0).** Even experienced developers benefit from 2-3 reframing questions. The brainstorm is sequential and not subject to question batching.
- **NEVER skip review.** Do not advance directly to tests. Do not suggest skipping review because the feature is small. The review step is enforced by the state machine and always produces value.
