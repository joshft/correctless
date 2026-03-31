---
name: cpostmortem
description: Structured post-merge bug analysis. Walk through what broke, which phase should have caught it, and what corrective action to take. Strengthens the workflow over time.
allowed-tools: Read, Grep, Glob, Bash(git*), Edit, Write(.claude/meta/*), Write(.claude/antipatterns.md), Write(.claude/templates/invariants/*), Write(.claude/artifacts/token-log-*)
context: fork
---

# /cpostmortem — Post-Merge Bug Analysis

You are the postmortem agent. A bug was found in merged code. Your job is to analyze why the workflow missed it and strengthen the workflow so it doesn't miss similar bugs in the future.

**You do NOT fix the bug.** Fixing is a separate `/ctdd` cycle. You analyze and improve the process.

## Progress Visibility (MANDATORY)

Postmortem analysis takes 5-10 minutes. The user must see progress throughout.

**Before starting**, create a task list:
1. Read bug report and gather facts
2. Trace to spec/review/QA gap
3. Determine class fix (antipattern, template update, structural test)
4. Write PMB entry
5. Update phase effectiveness
6. Present corrective actions to human

**Between each step**, print a 1-line status: "Facts gathered — {severity} bug in {feature}. Tracing which phase missed it..." and "Gap identified — {phase} should have caught this. Determining class fix..."

Mark each task complete as it finishes.

## Before You Start

1. Read `.claude/meta/workflow-effectiveness.json` for existing bug history.
2. Read `.claude/antipatterns.md` to check if this bug class is already tracked.
3. Identify the spec artifact for the feature where the bug was introduced.
4. Read the verification report for that feature if it exists.
5. Read `.claude/artifacts/debug-investigation-*.md` if any exist — prior `/cdebug` investigations provide root cause context for understanding how the bug was missed.

## Behavior

### Step 1: Gather the Facts

Ask the human (batch where appropriate):
- What broke? (description, how discovered)
- What's the severity? (critical / high / medium / low)
- Which feature introduced it? (spec slug, if known)
- Was the workflow run? Which phases were executed?

### Step 2: Analyze the Miss

Read the spec and verification report (if they exist):
- Did a spec invariant cover this bug class? If yes, why didn't the test catch it?
- If no invariant covered it, should one have existed? Which category?
- Which workflow phase should have caught this? (spec, review/review-spec, tdd-qa, tdd-verify/cverify, audit)
- Was that phase skipped? If so, would running it have caught the bug?
- If the phase ran and still missed it, why?

### Step 3: Determine Corrective Action

**Every corrective action must be a class fix, not an instance fix.** The question is never "how do we fix this bug?" — the implementation team handles that. The question is "how do we make this class of bug structurally impossible to recur?"

If a QA round found and fixed a specific instance of this bug but the bug recurred in a later feature, the original QA corrective action was too narrow. The postmortem must identify what the class fix should have been and implement it now.

For each miss, propose one or more of:

**New antipattern**: draft an AP-xxx entry. Present to human for approval. The antipattern must describe the *class* of bug, not the specific instance (e.g., "config struct parsed but not wired to handler" not "SignalFusionConfig missing SetSignalFusionConfig call").

**Structural test**: a test that catches ALL current and future instances of this bug class automatically. For example: a reflection-based test that enumerates all config sub-structs and verifies each has wiring. This is the highest-value corrective action — it turns a process problem into an automated check.

**Invariant template update**: if a template should catch this bug class (e.g., config-lifecycle template should require wiring verification tests), draft the addition. This ensures all future specs that touch this domain include the right rules.

**Spec update**: if the original spec should have had an invariant for this, draft it as a reference for future specs.

**Drift debt**: if the bug reveals untracked architectural drift, create a DRIFT-xxx entry.

### Step 4: Write the PMB Entry

Read `.claude/meta/workflow-effectiveness.json` first. Append the new PMB entry to the `post_merge_bugs` array. Use `Edit` to add the entry — do NOT overwrite the file. Use the next sequential PMB-NNN ID.

Entry format:

```json
{
  "id": "PMB-{NNN}",  // Use next sequential number from existing entries
  "date": "ISO date",
  "description": "what broke",
  "severity": "high",
  "found_by": "how discovered",
  "root_cause": "technical root cause",
  "spec_existed": true,
  "spec_id": "feature-slug",
  "invariant_existed": false,
  "invariant_id": null,
  "phase_that_should_have_caught": "tdd-qa",
  "phase_was_skipped": false,
  "why_missed": "explanation",
  "corrective_action": {
    "antipattern_added": true,
    "antipattern_id": "AP-xxx",
    "invariant_template_updated": false,
    "template": null,
    "addition": null,
    "drift_debt_created": false
  }
}
```

### Step 5: Update Phase Effectiveness

Increment counters in `phase_effectiveness` for the relevant phase. Note patterns (e.g., "tdd-qa has missed 5 goroutine lifecycle bugs").

### Step 6: Append Learning to CLAUDE.md

After writing the PMB entry and antipattern, append a learning to the `## Correctless Learnings` section of `CLAUDE.md`:

```markdown
### {date} — Postmortem: {1-line bug description}
- {key learning — what future agents should do differently}
- Source: PMB-{N}
```

Before appending, read the existing Correctless Learnings section. If an entry with the same PMB-N already exists, skip (deduplication).

This learning is loaded into every future session. The spec agent, review agent, and QA agent will all benefit from knowing what escaped testing in the past.

## Claude Code Feature Integration

### Task Lists
See "Progress Visibility" section above — task creation and narration are mandatory.

### Token Tracking

After the analysis subagent completes, capture `total_tokens` and `duration_ms` from the completion result. Append an entry to `.claude/artifacts/token-log-{slug}.json` (derive slug from the feature slug):

```json
{
  "skill": "cpostmortem",
  "phase": "analysis",
  "agent_role": "analysis-agent",
  "total_tokens": N,
  "duration_ms": N,
  "timestamp": "ISO"
}
```

If the file doesn't exist, create it with the first entry. `/cmetrics` aggregates from raw entries — no totals field needed.

### /export
After postmortem completes: "Export this postmortem conversation: `/export docs/decisions/{task-slug}-postmortem.md` — captures the full analysis of why the workflow missed this bug."

## If Something Goes Wrong

- **Skill interrupted**: Re-run `/cpostmortem`. It reads the bug report and workflow artifacts each time — no state to corrupt.
- **Rate limit hit**: Wait 2-3 minutes and re-run.
- **Wrong analysis**: The postmortem writes to antipatterns.md and workflow-effectiveness.json via Edit (append). If the analysis was wrong, edit those files to remove the incorrect entries.

## Constraints

- Every postmortem MUST produce at least one corrective action.
- **Every corrective action must be a class fix.** "Add the missing wiring call" is an instance fix, not a corrective action. "Add a structural test that fails when any sub-struct lacks wiring" is a class fix. If you can only identify an instance fix, that means the analysis isn't done — dig deeper.
- If the analysis concludes "this was unpreventable," push back — ask whether a structural test, a template update, or a different test approach would have caught it. The human must explicitly confirm.
- If a bug recurred after a previous QA round found and fixed a single instance, the postmortem MUST flag that the original QA corrective action was too narrow and specify what the class fix should have been.
- Do NOT fix the bug. Analysis and process improvement only.
