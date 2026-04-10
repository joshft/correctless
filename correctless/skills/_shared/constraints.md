# Shared Skill Constraints

These constraints apply to every skill that references this file. They are universal — not skill-specific.

## Skill Boundary

- **Never auto-invoke the next skill.** Tell the human what comes next and let them decide when to run it. The boundary between skills is the human's decision point.

## Evidence Standard

- **Evidence before claims.** Never say "tests pass" or "checks out" without running the command fresh in this message and showing the output. "Should pass" is not evidence.
- **All files written inside the project directory.** Never /tmp.

## Context Management

- **Context is a reliability constraint.** Above 70%, warn and recommend /compact. Above 85%, stop — instruction adherence degrades and the orchestrator cannot be trusted to produce accurate results. Specific thresholds and recovery instructions may be defined per-skill.

## Effective Intensity Computation

Compute effective intensity as `max(project_intensity, feature_intensity)` using the ordering `standard < high < critical`.

1. **Read project intensity**: Read `workflow.intensity` from `.correctless/config/workflow-config.json`. If the field is absent, default to `standard`.
2. **Read feature intensity**: Run `.correctless/hooks/workflow-advance.sh status` and look for the `Intensity:` line. If the Intensity line is absent in the status output (feature_intensity is absent), use the project intensity alone.
3. **Compute effective intensity**: Take the max of project_intensity and feature_intensity.

**Fallback chain**: feature_intensity -> workflow.intensity -> standard. If both feature_intensity and `workflow.intensity` are absent, the effective intensity defaults to `standard`. If there is no active workflow state (no state file), effective intensity falls back to `workflow.intensity` from config, then to `standard`. The skill still runs — it does not require active workflow state.

## Token Tracking

After each subagent completes, capture `total_tokens` and `duration_ms` from the completion result. Append an entry to `.correctless/artifacts/token-log-{slug}.jsonl` (derive slug from the workflow state or spec file). The PostToolUse hook (`hooks/token-tracking.sh`) handles this mechanically for Agent tool completions — the prompt-based instruction below is a fallback for skills that spawn subagents in contexts where the hook may not fire:

```json
{
  "timestamp": "ISO",
  "branch": "{branch-slug}",
  "phase": "{phase}",
  "skill": "{skill-name}",
  "feature": "{feature-name}",
  "agent_description": "{agent-description}",
  "agent_type": "{agent-type}",
  "input_tokens": N,
  "output_tokens": N,
  "total_tokens": N,
  "total_cost_usd": N,
  "duration_ms": N
}
```

If the file doesn't exist, create it with the first entry. `/cmetrics` aggregates from raw entries — no totals field needed.

## MCP Degradation (Serena)

**Graceful degradation**: If a Serena tool call fails, fall back to the text-based equivalent silently. Do not abort, do not retry, do not warn the user mid-operation. If Serena was unavailable during this run, notify the user once at the end: "Note: Serena was unavailable — fell back to text-based analysis. If this persists, check that the Serena MCP server is running (`uvx serena-mcp-server`)." Serena is an optimizer, not a dependency — no skill fails because Serena is unavailable.

## Project Preferences

If `.correctless/preferences.md` exists, read it and apply project preferences. This file contains codified judgment calls for autonomous decisions (QA finding triage, documentation scope, commit granularity, escalation sensitivity, PR creation mode). When the file is absent, use built-in defaults. Preferences from `.correctless/preferences.md` apply to all pipeline skills — each skill should check for and respect these preferences where relevant.

## MCP Degradation (Context7)

When Context7 is unavailable, fall back to web search. If Context7 was unavailable during this run, notify the user once at the end.
