---
name: cwtf
description: Audit the workflow itself. Use when you suspect agents shortcut or after a bug escapes despite the workflow running. Checks phase execution, rule coverage, and agent thoroughness.
allowed-tools: Read, Grep, Glob, Bash(git*), Bash(jq*), Bash(find*), Bash(grep*)
---

# /cwtf — Workflow Accountability

Every other skill watches the code. This skill watches the agents watching the code. It answers: **"Did the workflow actually do what the skill instructions said it should do?"**

Invoke with: `/cwtf` (analyzes the most recent or current workflow) or `/cwtf {phase}` (analyzes a specific phase)

## Important: Not Punitive

This report identifies gaps, not blame. "QA checked 4 of 6 rules" is a fact, not an accusation. The QA agent may have had good reason — context overflow, rate limiting, or the 2 unchecked rules were trivially satisfied by the implementation. Present findings with context, not judgment. Let the user decide what matters.

Frame gaps as: "R-003 was not checked during QA. This may indicate context overflow, rate limiting, or that the agent prioritized higher-risk rules." NOT: "The QA agent FAILED to check R-003."

## Progress Visibility (MANDATORY)

Accountability analysis takes 5-10 minutes. The user must see progress throughout.

**Before starting**, create a task list:
1. Load workflow state and spec
2. Check phase execution
3. Analyze rule coverage
4. Check agent thoroughness (QA)
5. Check agent thoroughness (review)
6. Detect deviations
7. Generate verdict

**Between each step**, print a 1-line status: "Phase execution verified — all 7 phases ran. Checking rule coverage..." Mark each task complete as it finishes.

## Step 1: Load Context

Derive the branch slug and hash using the same formula as other hooks (`sed + md5sum/md5`). Determine the repo root with `git rev-parse --show-toplevel` — prepend this to all relative paths for the Read tool.

Derive the task-slug from the workflow state's `.task` field: lowercase, non-alphanumeric characters replaced with `-`, consecutive dashes collapsed, leading/trailing dashes removed. This differs from the branch slug.

Read these data sources (skip any that don't exist):

1. **Workflow state** — `.claude/artifacts/workflow-state-{slug}-{hash}.json`
2. **Spec file** — path from `.spec_file` field (relative to repo root — prepend repo root for Read tool)
3. **QA findings** — `.claude/artifacts/qa-findings-{task-slug}.json`
4. **Test edit log** — `.claude/artifacts/tdd-test-edits.log`
5. **Audit trail** — `.claude/artifacts/audit-trail-{slug}-{hash}.jsonl`
6. **Override log** — `.claude/artifacts/override-log.json`
7. **Verification report** — `docs/verification/{task-slug}-verification.md`
8. **Session-meta** — `find ~/.claude/usage-data/session-meta/ -name '*.json'` filtered by `project_path` matching repo root
9. **Conversation JSONL** (optional, for deep analysis) — find the session file at `~/.claude/projects/`. List directories with `find ~/.claude/projects/ -maxdepth 2 -name '*.jsonl'`, identify the correct file by matching the project path pattern in the directory name and selecting the most recent file. This file can be very large — use targeted `jq` queries, never read it entirely.

If no workflow state file exists: "No active or completed workflow on this branch. Nothing to analyze."

Extract the spec rules: grep the spec file for `R-xxx` or `INV-xxx` identifiers. Count them — this is the baseline for coverage checks.

## Step 2: Phase Execution Verification

Check whether all mandatory phases executed:

**For Lite**: spec → review → tdd-tests → tdd-impl → tdd-qa → done → verified → documented
**For Full**: spec → review-spec (or model → review-spec) → tdd-tests → tdd-impl → tdd-qa → (tdd-verify →) done → verified → documented

**Primary source for phase history: the audit trail.** The workflow state's `phase_entered_at` field only contains the MOST RECENT transition timestamp — it cannot prove earlier phases ran. Instead, extract distinct phase values from the audit trail: `jq -r '.phase' .claude/artifacts/audit-trail-{slug}-{hash}.jsonl | sort -u`. This shows every phase that had tool activity. If no audit trail exists, fall back to the current `phase` field as a minimum marker and note: "No audit trail — can only verify current phase, not history."

Also check:
- Were overrides used? (check override log for entries during this workflow)
- How many spec updates happened? (from `spec_update_history` — many updates suggests the spec was undercooked)

Report: "All {N} phases executed" or "Phase {X} was skipped via override: '{reason}'"

## Step 3: Rule Coverage

For each spec rule (R-xxx or INV-xxx):

1. **Test exists?** Grep test files for the rule ID (e.g., `Tests R-001`, `R-001`). Use the `patterns.test_file` from `workflow-config.json` to find test files.
2. **Integration tag?** If the rule is tagged `[integration]`, check whether the test uses real wiring or mocks.
3. **QA checked?** Search the QA findings artifact for mentions of this rule ID.
4. **Verification status?** If the verification report exists, check its rule coverage table.

Output as a table:
```
| Rule | Test | QA Checked | Verify Status |
|------|------|-----------|---------------|
| R-001 | auth.test.ts:42 | Yes | covered |
| R-002 | — | NO | UNCOVERED |
```

**Recommended action for gaps**: "R-002 has no test. Run `/ctdd` from the tests phase to add coverage, or run `/cverify` to confirm this is a known gap."

## Step 4: Agent Thoroughness — QA

The most valuable analysis. Assess QA coverage and depth:

**Rule mention count**: Search the QA findings artifact AND the conversation JSONL for mentions of each rule ID. Count: "QA mentioned {N} of {M} spec rules." Missing rules are listed.

**Token budget indicator** (best-effort): Find the most recent session-meta entry matching this project's path. Report its total `output_tokens`. If multiple prior sessions exist for the project, compute a rough average and compare: "This session used {N}k tokens ({X}% of project average)." A session at 30% of average likely shortcut. Note: identifying which session corresponds to QA specifically is imprecise — this is a rough signal, not a measurement. If session-meta is unavailable, skip this metric.

**File coverage** (if audit trail exists): From the audit trail, which files had Read operations during the tdd-qa phase? Compare against files modified during tdd-impl. "QA read {N} of {M} files modified during implementation." Missing files are listed.

**Recommended action**: "QA did not check R-003 or R-005. Consider: re-run QA with `workflow-advance.sh fix` then `workflow-advance.sh qa`, or manually verify these rules are satisfied."

## Step 5: Agent Thoroughness — Review

Check whether the review agent was thorough:

**Security checklist coverage**: If the spec touches auth, user input, data storage, or APIs, the security checklist should have fired. Search conversation JSONL for security-related terms (CSRF, XSS, injection, auth bypass, SSRF, RLS, CORS, HSTS). Count how many categories were checked vs how many were applicable.

**Antipattern check**: Did the review mention any antipattern IDs (AP-xxx)? If the project has antipatterns.md with entries, the review should have checked against them.

**Recommended action**: "Review did not check for CSRF despite the spec touching API endpoints. Run `/creview` again or verify CSRF protection manually."

## Step 6: Deviation Detection

Cross-reference what happened against what should have happened:

**Source files modified during QA**: The audit trail should show no Edit/Write operations on source files during `tdd-qa` phase. If it does: "Source file {file} was modified during QA phase at {timestamp}. This is a gate bypass — the QA agent should be read-only."

**Test files modified during GREEN without logging**: Compare audit trail (test file edits during `tdd-impl`) against the test-edit log. If the audit trail shows a test edit that the log doesn't mention: "Test file {file} was edited during GREEN at {timestamp} but not logged in tdd-test-edits.log."

**Overrides**: List all overrides with their reasons and when they occurred relative to the workflow timeline.

**Spec updates**: If `spec_updates > 0`, list each update with its reason. Multiple updates suggest the spec wasn't thorough enough.

**Recommended action per deviation**: specific, not vague. "Source file edited during QA — check if this was a legitimate fix round (should have used `workflow-advance.sh fix` first) or a gate bypass."

## Step 7: Generate Verdict

Assess the overall workflow quality:

- **THOROUGH** — all phases ran, all rules have coverage, QA checked all rules, review ran security checklist, no deviations
- **ADEQUATE** — all phases ran, most rules covered, minor gaps in QA/review thoroughness that don't affect correctness
- **INCOMPLETE** — phases ran but significant rule coverage gaps, QA missed multiple rules, or review skipped applicable security checks
- **SHORTCUT** — phases skipped via override, QA used far below average tokens, multiple rules unchecked, or source files modified during QA

**Precedence rule**: If any SHORTCUT criterion is met (phase skip via override, source edit during QA, token usage far below average), the verdict cannot be higher than SHORTCUT regardless of other positive signals. A single gate bypass dominates all other indicators.

The verdict is a judgment call within those constraints. Explain the reasoning. Users can disagree.

## Output Format

```markdown
## Workflow Accountability Report

### Workflow: {task name}
**Branch:** {branch}
**Phases completed:** {list}
**QA rounds:** {N}
**Overrides used:** {N}

### Phase Execution: {PASS | {N} issues}
{details}

### Rule Coverage: {N}/{M} rules covered
| Rule | Test | QA Checked | Verify Status |
|------|------|-----------|---------------|
| R-001 | auth.test.ts:42 | Yes | covered |
| R-002 | — | NO | UNCOVERED |

### Agent Thoroughness
**QA**: Checked {N}/{M} rules. Token usage: {N}k ({X}% of average).
- {Missing rules with recommended actions}

**Review**: {N}/{M} security checks applied.
- {Skipped checks with recommended actions}

### Deviations ({N} found)
{Each deviation with timestamp, evidence, and recommended action}

### Verdict: {THOROUGH | ADEQUATE | INCOMPLETE | SHORTCUT}
{2-3 sentences explaining the assessment and what, if anything, should be done about it.}
```

## Claude Code Feature Integration

### Task Lists
See "Progress Visibility" section above — task creation and narration are mandatory.

## Code Analysis (MCP Integration)

If `mcp.serena` is `true` in `workflow-config.json`, use Serena MCP for symbol-level code analysis during thoroughness checking — particularly call-graph-based analysis:

- Use `find_symbol` instead of grepping for function/type names
- Use `find_referencing_symbols` to trace callers and dependencies for call-graph completeness
- Use `get_symbols_overview` for structural overview of a module
- Use `replace_symbol_body` for precise edits (not used in this skill — wtf is read-only)
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

## If Something Goes Wrong

- This skill is read-only. Re-run anytime safely.
- **Conversation JSONL too large**: Use targeted `grep` and `jq` queries on the JSONL file. Search for specific rule IDs, tool names, or phase-related keywords. Never read the entire file into memory.
- **Audit trail missing**: The skill still works from qa-findings + verification report, but agent thoroughness analysis will be less detailed. Note: "Audit trail not available — thoroughness analysis based on artifacts only."
- **No session-meta match**: Token budget comparison unavailable. Note it and skip that metric.

## Constraints

- **Read-only.** Never modify workflow state, findings, source code, or any artifact.
- **Not punitive.** Frame gaps as observations with context, not accusations. Include possible reasons for each gap.
- **Recommended actions.** Every gap should suggest a specific next step — not auto-fix, just point the user at the right command.
- **Targeted JSONL queries.** The conversation JSONL can be megabytes. Use `grep` for rule IDs, `jq` for structured extraction. Never `cat` the entire file.
- **Verdict is honest.** SHORTCUT is a valid assessment. Don't soften it to ADEQUATE if the evidence shows shortcuts. But explain why.
- **Redact if sharing.** If this output will be shared externally, apply redaction rules from `templates/redaction-rules.md` first.
