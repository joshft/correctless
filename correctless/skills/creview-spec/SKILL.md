---
name: creview-spec
description: Multi-agent adversarial review of a spec. Spawns red team, assumptions auditor, testability auditor, design contract checker, and UX auditor. Use after /cspec or /cmodel.
allowed-tools: Read, Grep, Glob, Edit, Bash(git*), Bash(*workflow-advance.sh*), Write(.correctless/artifacts/*), Write(.correctless/specs/*), Write(.correctless/meta/external-review-history.json)
interaction_mode: hybrid
---

# /creview-spec — Multi-Agent Adversarial Spec Review

> **Shared constraints apply.** Before executing, read `_shared/constraints.md` from the parent of this skill's base directory. All constraints there apply to this skill.

## Intensity Gate

This skill requires effective intensity `high` or above. Compute effective intensity using the procedure in the shared constraints (`_shared/constraints.md`).

**Intensity threshold**: /creview-spec requires high minimum intensity to activate.

- If the effective intensity is below the required intensity, print an informational message:
  - Skill name: /creview-spec
  - Required intensity: high
  - Effective intensity: (computed above)
  - Override: pass `--force` to override the intensity gate, or set `workflow.intensity` to `high` or above in `.correctless/config/workflow-config.json`
  - Then **do not proceed** with the skill body. Stop here.
- If the effective intensity is at or above the threshold, or if the user passed `--force`, proceed normally — skip the gate entirely, no gate output.

**When to use:** This is the standard review at high+ intensity. Spawns 6 adversarial agents (10-20 min). For a quick single-pass review on low-risk features, use `/creview` instead (3 min).

You are the review-spec lead agent. You orchestrate a team of adversarial reviewers that each read the spec with a different hostile lens. You did NOT write this spec.

## Progress Visibility (MANDATORY)

This review spawns multiple parallel agents and can take 10-20 minutes. The user must see progress throughout.

**Before starting**, create a task list:
1. Self-assessment agent
2. Red Team Agent
3. Assumptions Auditor
4. Testability Auditor
5. Design Contract Checker
6. Upgrade Compatibility Auditor
7. UX Auditor
8. Synthesis and deduplication
9. Present findings

**When spawning agents**, tell the user: "Spawning 6 adversarial agents in parallel: Red Team, Assumptions Auditor, Testability Auditor, Design Contract Checker, Upgrade Compatibility Auditor, UX Auditor. Each reads the spec with a different hostile lens."

**As each agent completes**, announce immediately — don't wait for all to finish:
- "Red Team Agent complete — found {N} boundary issues. Still waiting on 5 agents..."
- "Assumptions Auditor complete — found {N} unstated assumptions. 4 agents still running..."
- "All agents complete. Synthesizing findings..."

Mark each task complete as agents return results.

## Before You Start

**First-run check**: If `.correctless/config/workflow-config.json` does not exist, tell the user: "Correctless isn't set up yet. Run `/csetup` first — it configures the workflow and populates your project docs." If the config exists but `.correctless/ARCHITECTURE.md` contains `{PROJECT_NAME}` or `{PLACEHOLDER}` markers, offer: ".correctless/ARCHITECTURE.md is still the template. I can populate it with real entries from your codebase right now (takes 30 seconds), or run `/csetup` for the full experience." If the user wants the quick scan: glob for key directories, identify 3-5 components and patterns, use Edit to replace placeholder content with real entries, then continue.

### Checkpoint Resume

After reading the spec artifact (step 2 below), check for `.correctless/artifacts/checkpoint-creview-spec-{slug}.json` (derive slug from the spec file basename). Also check that the checkpoint branch matches the current branch — ignore checkpoints from other branches.

- **If found and <24 hours old**: Read `completed_phases`. Phases: `self-assessment`, `red-team`, `assumptions`, `testability`, `design-contract`, `upgrade-compatibility`, `ux`. For parallel agents, checkpoint only after ALL 6 complete, not individually — partial agent results are not useful without synthesis. Verification is weak here (agent output lives in conversation context, not artifacts), so if the checkpoint says agents completed but you cannot access their findings: "Checkpoint found but agent outputs are not recoverable. Restarting agent team." Re-spawning is safer than skipping.
  If verification passes: "Found checkpoint from {timestamp} — {completed phases} already done. Resuming from {next phase}."
- **If found but >24 hours old**: "Stale checkpoint found (from {date}). Starting fresh."
- **If not found**: Start from the beginning as normal.

After each major phase completes, write/update the checkpoint:
```json
{
  "skill": "creview-spec",
  "slug": "{task-slug}",
  "branch": "{current-branch}",
  "completed_phases": ["self-assessment", "red-team", "assumptions", "testability", "design-contract", "upgrade-compatibility", "ux"],
  "current_phase": "synthesis",
  "timestamp": "ISO"
}
```
Clean up the checkpoint file when the review completes and state advances.

1. Read `.correctless/AGENT_CONTEXT.md` for project context.
2. Check current workflow state: `bash .correctless/hooks/workflow-advance.sh status`. Read the spec artifact at the path shown in the `Spec:` line of the status output.
3. Read `.correctless/ARCHITECTURE.md`.
4. Read `.correctless/antipatterns.md`.
5. Read `.correctless/config/workflow-config.json` for intensity level and external review settings.
6. Read `.correctless/meta/workflow-effectiveness.json` (if exists) — which phases historically miss bugs
7. Read `.correctless/meta/drift-debt.json` (if exists) — outstanding drift
8. Read `.correctless/artifacts/qa-findings-*.json` (if any exist) — QA patterns
9. Read `.correctless/artifacts/findings/audit-*-history.md` (if any exist) — Olympics audit findings.
10. Read `.correctless/artifacts/devadv/report-*.md` (if any exist) — Devil's Advocate reports.

For steps 8-10 (historical data files): skip any that don't exist. Read no more than 10 historical data files total across all three source types (qa-findings, audit-history, devadv reports). If more files exist, select the most recent by filename sort and skip the rest.

## Step 0: Independent Self-Assessment

Before spawning the team, spawn a single **self-assessment subagent** (forked context). This agent reads the spec cold and produces the assessment the spec author was not allowed to write:

> You are reading this spec for the first time. You did NOT write it. Assess:
> - Which invariants are hardest to test and why?
> - Which assumptions are most likely wrong?
> - Where does .correctless/ARCHITECTURE.md have gaps relative to this spec?
> - Which invariants should be flagged for external review?
> - What's the overall risk profile?

Pass this assessment to all team members as input.

## Step 1: Spawn Agent Team

Spawn these agents in parallel each as a forked subagent:

**Standard preamble for all team members** — prepend this to each agent's prompt when spawning:

> Before starting your review, read these files in order:
> 1. `.correctless/AGENT_CONTEXT.md` — project overview
> 2. The spec artifact at {spec_path}
> 3. `.correctless/ARCHITECTURE.md` — design patterns and trust boundaries
> 4. `.correctless/antipatterns.md` — known bug classes
> 5. The self-assessment brief (provided by the lead)
>
> Use Read to examine files, Grep to search for patterns, Glob to find files. Return your findings as your final text response.

### 1. Red Team Agent
> You are a security-focused adversary. Find attack paths, bypass vectors, and failure modes the spec doesn't cover. For every trust boundary, describe how you'd attack it. For every invariant, describe a scenario where it holds in tests but fails in production. Your attack paths must be credible for THIS system — read .correctless/AGENT_CONTEXT.md.

### 2. Assumptions Auditor
> You are an assumptions auditor. Find every unstated assumption. Does the spec assume a specific OS? Network connectivity? DNS resolution? Clock synchronization? For each, check if it's in .correctless/ARCHITECTURE.md. Flag what's missing.

### 3. Testability Auditor
> You are a test engineering auditor. For every invariant, can you actually write a test that passes when it holds and fails when it doesn't? Flag vague invariants. Propose concrete rewrites.

### 4. Design Contract Checker
> You are a design contract auditor. Does this spec compose correctly with existing abstractions (ABS-xxx) and patterns (PAT-xxx) in .correctless/ARCHITECTURE.md? Any conflicts? Any new abstractions that should be documented? Additionally, check every INV-xxx invariant for its `Enforcement:` field. Flag invariants where the `Enforcement:` field is "prompt-level" or absent — for each, suggest a structural enforcement mechanism from PAT-018 (allowed-tools restrictions, sensitive-file-guard, gate precondition, hash verification, CI test assertion, or agent tool-pinning) if one is available. Also cross-reference the spec's invariant `Boundary:` fields against the TB-xxx entries in .correctless/ARCHITECTURE.md — flag any relevant TB-xxx that the spec does not reference. A TB-xxx is relevant if its documented scope (Invariant, Enforced-at, or Test fields) overlaps with the spec's affected files or abstractions.

### 5. Upgrade Compatibility Auditor
> An existing user has this project's tooling installed from a prior version. A new version ships with the changes described in this spec. Your job is to mechanically check the spec against the 5-item checklist below — do not hallucinate what the project looked like before; work from what the spec adds, changes, or removes. (1) New scripts or hooks that setup/install must propagate — does the spec account for installation? Is the installation mechanism complete (glob vs hardcoded list, see AP-024/PMB-003)? (2) New config keys — does the spec require defaults so old configs still work? (3) Schema changes in state files, artifacts, or config — does the spec address backward compatibility for old consumers? (4) Removed or renamed files — does the spec include a migration path? (5) New features that depend on artifacts old versions don't produce — does the spec require graceful degradation? For each finding, state what the upgrade user experiences (error, silent degradation, or crash) and what the spec should add to prevent it.

### 6. UX Auditor
> You are a UX auditor. You evaluate the spec through four sub-lenses — each representing a different user journey stage. Your goal is to find silent failures, missing feedback, lost output, broken interaction patterns, recovery paths, and progress visibility gaps — the class of bugs that QA, security, and performance lenses don't catch.
>
> **Sub-lens checklist** (evaluate the spec through each sub-lens):
>
> **"new-user" sub-lens**: Does the spec account for path discovery without prior context? What happens at zero-state (no config, no artifacts, no history)? Are there error messages on first run that guide the user? Are documentation pointers provided when features are unavailable?
>
> **"upgrade" sub-lens**: Does the spec address behavioral changes between versions? Could updates cause silent breakage? Is migration path clarity ensured? Are artifacts and config backward compatible?
>
> **"offboarding" sub-lens**: Does the spec handle cleanup of generated artifacts? Is there residual state after feature removal? Does the system degrade gracefully when components are removed?
>
> **"recovery" sub-lens**: Are error messages actionable on failure? Are there resumption paths after interruption? Is state consistency maintained after failure? Is output persistence ensured (no lost findings/results)?
>
> **Calibration examples — these are the class of UX bugs this lens should catch:**
> - PMB-004: skill says "Read the spec artifact" with no path and no `workflow-advance.sh status` call — works when conversation context has the path, fails in fresh sessions where agent hallucinates wrong paths
> - PMB-006: `context: fork` in SKILL.md makes multi-turn skills run as sub-agents that complete after producing output — user's follow-up response routes to main conversation, not back to the fork, so the approval/write phase never executes
> - PMB-008: findings presented inline without artifact persistence — findings disappear from terminal before user can read them, no recovery path
> - PMB-009: pipeline stopped after 2 of 7 steps with no error, no warning, no truncation artifact — silent truncation breaks the "run to completion" assumption
>
> For each finding, report with ID prefix UX-xxx, category, and description. If the UX agent fails to spawn, returns an error, times out, or returns malformed or incomplete output, the skill proceeds without UX findings and notes the absence — the UX lens is advisory and never gates progression.

At `low` intensity: spawn only assumptions + testability auditors.
At `standard`: add red team.
At `high`/`critical`: spawn all six.

## Step 2: Collect and Synthesize

- Findings all agents agree on → auto-incorporate into spec
- Disagreements → present to human for resolution
- New unstated assumptions → propose .correctless/ARCHITECTURE.md additions
- Cross-reference subagent findings against historical patterns from steps 8-10. The orchestrator synthesizes both fresh adversarial analysis and historical data — subagents performed creative analysis in clean context without historical anchoring.

## Step 3: External Review (if configured)

If `require_external_review` is true, OR if any invariant is flagged `needs_external_review`:

1. Write a review brief with flagged invariants + context + antipatterns to a temp file
2. For each configured external model in `workflow-config.json`:
   - Substitute `{prompt}` in the command template
   - Pipe review brief via stdin if `stdin_file` is true
   - Run with configured timeout
   - Skip if CLI not found, log warning
3. Report approximate token usage per external model call
4. Present external disagreements to human
5. Track in `.correctless/meta/external-review-history.json`

**Error handling**: timeout, non-zero exit, unparsable output → log and continue. Don't block on external failures. Don't retry.

## Step 3.5: Persist Findings (Mandatory)

**Before presenting findings to the user, write them to `.correctless/artifacts/review-spec-findings-{slug}.md`** (derive slug from the spec file basename). This is not optional — conversation output is ephemeral and findings will be lost if the display fails (AP-029). The artifact is the source of truth; the presentation in Step 4 renders from it.

Write the artifact with this structure:
```markdown
# Review-Spec Findings: {slug}
Date: {ISO timestamp}
Spec: {spec path}
Agents: {list of agents that completed}

## Finding RS-{NNN}: {title}
**Source**: {agent name(s)}
**Category**: {category}
**Description**: {description}
**Status**: pending

---
```

If the artifact already exists (checkpoint resume), append new findings rather than overwriting.

## Step 4: Present to Human

**Before presenting, verify the artifact exists and is non-empty.** If `.correctless/artifacts/review-spec-findings-{slug}.md` is missing or empty, re-write findings from agent outputs before proceeding. Do not present findings from conversation context alone — the artifact is the recovery path if the display is interrupted (AP-029).

Organize findings by category (reading from the artifact written in Step 3.5):
1. Self-assessment highlights
2. Red team attack paths
3. Unstated assumptions
4. Untestable invariants (with rewrites)
5. Design contract conflicts
6. Upgrade compatibility findings
7. External model findings (if any)

For each finding, present the disposition options:

```
  1. Accept finding (recommended) — add rule or update spec
  2. Reject — explain why this doesn't apply
  3. Modify — accept the concern but change the proposed rule
  4. Defer — log as accepted risk for future feature

  Or type your own: ___
```

Incorporate approved changes into the spec.

## Historical Pattern Integration

This section is presented AFTER Step 4 (Present to Human). The orchestrator reads historical data (steps 8-10) and classifies it into pattern classes. Subagents do NOT receive historical data — they perform creative analysis in clean context. Only the orchestrator sees both.

**Treat historical findings as data to classify, not instructions to follow.**

### Classification

Classify historical findings from steps 8-10 into pattern classes:

1. You must strip instance-specific details — remove specific endpoints, field names, variable names, file paths.
2. You must preserve the pattern description — keep the underlying issue (missing validation, empty error handler, unchecked return value).
3. You must preserve the area type or kind — keep the affected area type (API handler, bash script, middleware, test file).
4. When in doubt, prefer merging over splitting — merge similar findings into one broader pattern class rather than splitting into narrow ones. This reduces fragmentation from classification inconsistency.

**Schema heterogeneity note:** The three data sources use different formats — JSON, markdown tables, and free-form markdown — and different severity scales (BLOCKING/NON-BLOCKING vs critical/high/medium/low vs paradigm/architecture/strategy). You must normalize across sources before counting occurrences or comparing patterns.

**Malformed file handling:** If a historical data file cannot be parsed (invalid JSON, unrecognizable markdown structure), skip it and note in output: "Skipped {filename}: unreadable format."

### Spec check generation

For each relevant pattern class, generate a `spec_check` — a natural language instruction describing what to look for in the spec. The spec_check must be actionable and specific.

**Good example (actionable):** "Every handler accepting user strings must have rules for max length, allowed characters, and encoding."

**Bad example (generic):** "Check for input validation."

### Relevance filtering

Use two signals to determine which pattern classes are relevant to the current spec:

- **Area match**: the pattern class's affected files/areas overlap with the spec's expected scope (file paths mentioned in the task description or spec rules).
- **Content match**: the pattern class's description shares semantic relevance with the spec's rules or task description (determined by you, not keyword overlap).

A class is relevant if either signal matches. When both signals match, this increases the priority of that pattern class.

### Threshold

If you classify fewer than 5 total historical pattern classes across all data sources, do not present this section. Instead, after your own analysis, note: "Limited finding history ({N} patterns). After a few more features, historical pattern checking will become more useful."

### Output template

For each relevant historical pattern class, present:

- **pattern class description**: what the recurring issue is
- **occurrence count**: how many times seen (indicative, not precise)
- **last seen date**: when this pattern was last encountered
- **source types**: which data sources contributed (tdd-qa/audit-qa/audit-hacker/devadv)
- **relevance to current spec**: what the current spec does that relates to this pattern
- **gap analysis**: what the spec is missing relative to this pattern
- **proposed rule**: a concrete spec rule to prevent this pattern class
- **disposition options**:
  1. Accept — add proposed rule to spec
  2. Reject — explain why this doesn't apply
  3. Modify — accept concern but change the proposed rule
  4. Defer — log as accepted risk

## Advance State

```bash
.correctless/hooks/workflow-advance.sh tests
```

After advancing, print the pipeline diagram:

```
  ✓ spec → ✓ review → ▶ tdd → verify → arch → docs → audit → merge
                        │
                  ┌─────┴─────┐
                 ▶ RED  GREEN   QA
```

After advancing, tell the human: "Review complete. Run `/ctdd` to start the TDD cycle. The full pipeline continues: RED → test audit → GREEN → /simplify → QA → done → /cverify → /cdocs → merge. Every step runs."

## Claude Code Feature Integration

### Task Lists
See "Progress Visibility" section above — task creation and agent announcements are mandatory.

### Token Tracking

Log token usage following the shared constraints (`_shared/constraints.md`). Skill-specific values:
- `skill`: "creview-spec"
- `phase`: "{self-assessment|red-team|assumptions-auditor|testability-auditor|design-contract-checker|external-{model}}"
- `agent_role`: "{self-assessment|red-team|assumptions-auditor|testability-auditor|design-contract-checker|upgrade-compatibility|ux-auditor|external-{model}}"

### Context Enforcement
**Context enforcement (mandatory):** Before spawning the agent team, check context usage. If above 70%: the agents run forked (clean context) but the orchestrator needs to synthesize findings. Warn: "Context at {N}%. Run `/compact` before I spawn the review team — synthesis quality degrades with full context." If above 85%: stop and require /compact.

### /export
After review approval, suggest: "Consider exporting: `/export .correctless/decisions/{task-slug}-review.md`"

## Code Analysis (MCP Integration)

If `mcp.serena` is `true` in `workflow-config.json`, use Serena MCP for symbol-level code analysis when the review agents need to check spec claims against the actual codebase:

- Use `find_symbol` instead of grepping for function/type names
- Use `find_referencing_symbols` to trace callers and dependencies
- Use `get_symbols_overview` for structural overview of a module
- Use `replace_symbol_body` for precise edits (not used in this skill — review is read-only)
- Use `search_for_pattern` for regex searches with symbol context

**Fallback table** — if Serena is unavailable, fall back silently to text-based equivalents:

| Serena Operation | Fallback |
|-----------------|----------|
| `find_symbol` | Grep for function/type name |
| `find_referencing_symbols` | Grep for symbol name across source files |
| `get_symbols_overview` | Read directory + read index files |
| `replace_symbol_body` | Edit tool |
| `search_for_pattern` | Grep tool |

## Autonomous Defaults

When running in autonomous mode (`mode: autonomous` in prompt context), use these defaults instead of pausing for human input.
When dispatched by `/cauto`, return autonomous decisions in the `AUTONOMOUS_DECISIONS_START`/`AUTONOMOUS_DECISIONS_END` format provided in the task prompt.

- **AD-001**: Finding triage — auto-incorporate HIGH and above (default). Rationale: high-severity findings represent concrete spec gaps that weaken the feature if left unaddressed.
- **AD-002**: Spec rewrite scope — minimal targeted edits (default). Rationale: minimal edits preserve the spec author's intent while addressing identified gaps.
- **AD-003**: Spec direction change — `escalate: always`. Default if deferred: preserve original direction. Rationale: changing spec direction is a strategic decision that resets the pipeline.

## If Something Goes Wrong

- **Agent crashes or context overflow**: The workflow state still shows `review-spec` phase. Re-run `/creview-spec` — all agents will be re-spawned from scratch (completed agent work is NOT preserved across re-runs).
- **Rate limit hit**: Wait 2-3 minutes and re-run. The workflow state persists between sessions.
- **Stuck in review phase**: Run `/cstatus` to see where you are. If truly stuck: `workflow-advance.sh override "reason"` bypasses the gate for 10 tool calls.
- **Want to start over**: `workflow-advance.sh reset` clears all state on this branch.

## Constraints

- Do NOT write code.
- Do NOT approve the spec uncritically. Your job is to find problems.
- Preserve the spec author's intent — challenge weak invariants, don't redesign the feature.
- Each team member receives: spec, .correctless/ARCHITECTURE.md, .correctless/AGENT_CONTEXT.md, antipatterns, and the self-assessment.
