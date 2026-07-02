---
name: cwtf
description: Audit the workflow itself. Use when you suspect agents shortcut or after a bug escapes despite the workflow running. Checks phase execution, rule coverage, and agent thoroughness.
allowed-tools: Read, Grep, Glob, Write(.correctless/artifacts/wtf-*), Bash(git*), Bash(jq*), Bash(find*), Bash(grep*)
disallowed-tools: Edit, MultiEdit, NotebookEdit, CreateFile
interaction_mode: autonomous
---

# /cwtf — Workflow Accountability

> **Shared constraints apply.** Before executing, read `_shared/constraints.md` from the parent of this skill's base directory. All constraints there apply to this skill.

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

Derive the task-slug from the workflow state's `.spec_file` field: extract the basename and strip the `.md` extension. For example, if `spec_file` is `.correctless/specs/statusline-live-cost.md`, the task-slug is `statusline-live-cost`. This is the canonical slug used by all artifact filenames.

Read these data sources (skip any that don't exist):

1. **Workflow state** — `.correctless/artifacts/workflow-state-{slug}-{hash}.json`
2. **Spec file** — path from `.spec_file` field (relative to repo root — prepend repo root for Read tool)
3. **QA findings** — `.correctless/artifacts/qa-findings-{task-slug}.json`
4. **Test edit log** — `.correctless/artifacts/tdd-test-edits.log`
5. **Audit trail** — `.correctless/artifacts/audit-trail-{slug}-{hash}.jsonl`
6. **Override log** — `.correctless/artifacts/override-log.json`
7. **Verification report** — `.correctless/verification/{task-slug}-verification.md`
8. **Session-meta** — `find ~/.claude/usage-data/session-meta/ -name '*.json'` filtered by `project_path` matching repo root
9. **Conversation JSONL** (optional, for deep analysis) — find the session file at `~/.claude/projects/`. List directories with `find ~/.claude/projects/ -maxdepth 2 -name '*.jsonl'`, identify the correct file by matching the project path pattern in the directory name and selecting the most recent file. This file can be very large — use targeted `jq` queries, never read it entirely.

If no workflow state file exists: "No active or completed workflow on this branch. Nothing to analyze."

Extract the spec rules: grep the spec file for `R-xxx` or `INV-xxx` identifiers. Count them — this is the baseline for coverage checks.

## Step 2: Phase Execution Verification

Check whether all mandatory phases executed:

**At standard intensity**: spec → review → tdd-tests → tdd-impl → tdd-qa → done → verified → documented
**At high+ intensity**: spec → review-spec (or model → review-spec) → tdd-tests → tdd-impl → tdd-qa → (tdd-verify →) done → verified → documented

**Primary source for phase history: the audit trail.** The workflow state's `phase_entered_at` field only contains the MOST RECENT transition timestamp — it cannot prove earlier phases ran. Instead, extract distinct phase values from the audit trail: `jq -r '.phase' .correctless/artifacts/audit-trail-{slug}-{hash}.jsonl | sort -u`. This shows every phase that had tool activity. If no audit trail exists, fall back to the current `phase` field as a minimum marker and note: "No audit trail — can only verify current phase, not history."

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

## Step 5.5: Lens Auditability (INV-010)

Check whether the mini-audit ran the right lenses for this feature. The LENS field is an open enum — handle unknown lens values gracefully from recommended lenses.

**Dormant (PAT-019)**: When the lens recommendation artifact for the current branch does not exist (`.correctless/artifacts/lens-recommendations-{branch_slug}.json`), skip all lens auditability checks with no error and no warning. Only perform these checks when the artifact exists.

When the artifact exists, check:

**(a) Recommended lenses none ran**: If the `recommended_lenses` array is non-empty but the `outcomes` field shows no recommended lenses with `ran: true`, warn: "Review recommended {N} lenses but mini-audit ran none — was the recommendation ignored?"

**(b) CRITICAL finding lens not executed**: For each recommended lens linked to a CRITICAL review finding (check `source_finding` and look up its severity), if the lens has `ran: false` in outcomes, warn: "Lens {lens_name} recommended due to CRITICAL finding {source_finding}: {source_finding_summary} was not executed." The `source_finding_summary` field provides the display text without requiring cross-artifact lookup.

**(c) Lens selection rationale**: Report the full lens selection from the artifact — which lenses were recommended, which were selected (ran), and which were excluded (budget exceeded or other reason from `failure_reason`).

## Step 5.6: Rule-Load Observability (InstructionsLoaded)

This step presents **direct rule-load evidence** so you can judge, for yourself, whether a `.claude/rules/*.md` rule (for example `hooks-pretooluse.md`) was actually loaded into agent editing context around the hook edits in this workflow. It is a plain-language, side-by-side view of two local logs — it draws **no** conclusion and emits **no** verdict. The human classifies.

**Two sources:**

1. **Rule-load events** — `.correctless/meta/instructions-loaded.jsonl` (the InstructionsLoaded telemetry log). Each line records a rule file that was loaded, with `trigger_file_path` (the file whose open triggered the load) and a timestamp.
2. **Hook-edit entries** — the target workflow/branch's `audit-trail-*.jsonl`. Locate it by globbing `audit-trail-*.jsonl` for the target branch (edits made off-workflow do not appear in the audit trail — note this caveat when the picture looks thin).

**How to group (RS-027):** do **not** filter rule-loads by the session running `/cwtf` — `/cwtf` usually analyzes a *past* workflow, so the invoking session is not the session that made the edits. Instead, derive the set of edit-session ids from the **target workflow's hook-edit entries** (audit-trail lines whose `.file` is under `hooks/`), then present rule-loads **grouped per edit-session**. A hook-edit with no `session_id` (pre-instrumentation) is shown in an **unattributed** group; rule-loads are not attributed to it. Sessions that appear in the rule-load log but never made a hook-edit are intentionally excluded.

**Consumer contract:** both logs are read line-by-line with the project JSONL consumer contract — `jq -R 'fromjson? ...'` (try/catch, skip malformed lines), **never** slurping the whole file into a variable/argv, and never a single-shot slurp of all lines. Hook-edit times are read as `.ts // .timestamp` (RS-030) because the audit-trail file is mixed-shape: the audit hook writes `ts`, `/cauto` writes `timestamp` to the same file. Uses only `/cwtf`'s existing `Bash(jq*)`/`Bash(grep*)`/`Bash(find*)` tools — no new helper script.

**Liveness (INV-016):** always print the denominators the presentation worked from (how many rule-load events, how many with null `rule_file`, how many hook-edit entries, across how many edit-sessions, and when the log was last written) so a dead or field-drifted channel is visible rather than silently producing an empty picture.

**Dormant / field-drift (INV-009):** if the log is absent or empty, print a single non-alarming advisory explaining it populates the first time a `.claude/rules/*.md`-scoped file is opened and requires harness ≥2.1.69, then continue. If the log is present but **every** `rule_file` is null, surface a field-drift note ("all with null rule_file — possible harness field drift").

Run this presentation block (inputs: `IL_LOG` = the instructions-loaded.jsonl path; `AUDIT_TRAIL` = the target branch's audit-trail-*.jsonl path):

<!-- cwtf:rule-load-extract:start -->
```bash
# Inputs (env): IL_LOG = instructions-loaded.jsonl ; AUDIT_TRAIL = target branch audit-trail-*.jsonl
IL_LOG="${IL_LOG:-.correctless/meta/instructions-loaded.jsonl}"
AUDIT_TRAIL="${AUDIT_TRAIL:-}"

# Every jq over IL_LOG / AUDIT_TRAIL guards with `fromjson? | objects` (MA-001):
# bare `fromjson?` only catches fromjson's own parse error, so a VALID-but-non-object
# line (5, "x", [1,2]) or a mistyped field ({"file":5}) would raise a downstream
# `.field`/`test`/`startswith` runtime error that `?` does NOT catch — and on jq 1.7
# (CI) that aborts the whole stream, truncating evidence and breaking liveness.
# `objects` drops any non-object line so a forged/torn/scalar/mistyped line is
# skipped, never fatal, on jq 1.7 AND 1.8. Fields used in matching are also coerced
# (`(.file // "") | tostring`) so a non-string field can never error.
#
# Hook-edit filter (MA-002 / MA-R2-002): match ONLY the real Correctless hook roots —
# `hooks/...` at the repo root (source tree) or `.correctless/hooks/...` (installed,
# anywhere in the path). This deliberately EXCLUDES src/hooks/ (React), .git/hooks/,
# node_modules/**/hooks/, app/hooks/ and the legacy Claude hooks dir so a downstream
# project's unrelated "hooks" directory is never miscounted as a Correctless hook edit.
# A write-tool gate (.tool in Edit|Write|MultiEdit|NotebookEdit|CreateFile|Bash)
# further excludes Read/Grep of hook files, which audit-trail.sh ALSO records with a
# .file (MA-CC-03). Bash IS included: a hook edited via a Bash redirect/writer command
# is a real edit, recorded as tool:"Bash" with the write target in .file by
# get_target_file (a plain read like `cat hooks/x` has no write target, so no .file
# under a hook root, so it is not counted). The predicate is byte-identical at all
# three sites (the hook_edits count,
# the edit_sessions derivation, and the per-session render) so counts and grouping
# stay consistent. Non-hook audit-trail entries (/cauto orchestration events, /caudit
# records) still fail the test and are excluded.

# --- Resolve the hook-edit source (MA-004 / MA-R2-001) ----------------------
# Distinguish "audit-trail path not resolved" from "resolved, zero hook edits".
# audit_autoresolved=1 marks a fallback pick (provenance: name the file in output,
# do NOT claim it authoritatively describes "the target workflow").
audit_located=1
audit_autoresolved=0
if [ -z "$AUDIT_TRAIL" ] || [ ! -f "$AUDIT_TRAIL" ]; then
  # Not passed / missing: locate THIS branch's audit trail ONLY (MA-R2-001). NEVER
  # fall back to another branch's trail — a cross-branch lexicographic pick can mask a
  # dead channel or misattribute another workflow's edits. Scope the glob to the
  # current branch slug (Bash(git*) is granted); the trailing '*' matches the -{hash}
  # suffix. This is a scoped lexicographic pick within THIS branch's trails, NOT an
  # mtime/most-recent pick.
  br="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)" || true
  slug="$(printf '%s' "$br" | tr '/' '-')"
  if [ -n "$slug" ]; then
    AUDIT_TRAIL="$(find .correctless/artifacts -maxdepth 1 -name "audit-trail-${slug}*.jsonl" -type f 2>/dev/null | sort | tail -1)"
  else
    AUDIT_TRAIL=""
  fi
  if [ -n "$AUDIT_TRAIL" ] && [ -f "$AUDIT_TRAIL" ]; then
    audit_autoresolved=1
  else
    audit_located=0
  fi
fi

# --- Hook-edit denominators + edit-session ids (computed FIRST, MA-003) ------
hook_edits=0
edit_sessions=""
if [ "$audit_located" -eq 1 ]; then
  # hook-edit entries = write-tool ops whose .file is under a real Correctless hook
  # root (MA-002 / MA-R2-002 / MA-CC-03); time read as .ts // .timestamp (RS-030).
  hook_edits="$(jq -R 'fromjson? | objects | select(((.file // "") | tostring | (test("^hooks/") or test("(^|/)\\.correctless/hooks/"))) and ((.tool // "") | tostring | test("^(Edit|Write|MultiEdit|NotebookEdit|CreateFile|Bash)$"))) | 1' "$AUDIT_TRAIL" 2>/dev/null | grep -c .)" || true
  # edit-session ids (missing/null/empty session_id -> unattributed), de-duplicated.
  # `// "unattributed"` alone does NOT catch "" (jq // only catches null/false), so
  # empty-string sessions are folded into unattributed explicitly (QA-001 / INV-015).
  edit_sessions="$(jq -Rr 'fromjson? | objects | select(((.file // "") | tostring | (test("^hooks/") or test("(^|/)\\.correctless/hooks/"))) and ((.tool // "") | tostring | test("^(Edit|Write|MultiEdit|NotebookEdit|CreateFile|Bash)$"))) | (.session_id // "" | if . == "" then "unattributed" else . end)' "$AUDIT_TRAIL" 2>/dev/null | sort -u)"
fi
edit_session_count="$(printf '%s\n' "$edit_sessions" | grep -c .)" || true

# --- Rule-load denominators (try/catch consumer contract; never whole-file slurp)
rule_loads="$(jq -R 'fromjson? | objects | 1' "$IL_LOG" 2>/dev/null | grep -c .)" || true
null_rules="$(jq -R 'fromjson? | objects | select(.rule_file == null) | 1' "$IL_LOG" 2>/dev/null | grep -c .)" || true
# MA-005: -Rr so the timestamp prints raw (unquoted) in the liveness line.
last_written="$(jq -Rr 'fromjson? | objects | (.ts // .timestamp) // empty' "$IL_LOG" 2>/dev/null | tail -1)"

# --- Attributed rule-loads (reconciliation, MA-R2-003 / MA-011) --------------
# attributed = rule-loads whose session_id matches a REAL (non-unattributed) edit-
# session. Computed ONCE here and reused by BOTH the liveness denominator (so read K
# reconciles as attributed + other + null) AND the drift note below (MA-006). When
# there is no real edit-session to match against, attributed is 0 by construction.
real_edit_sessions="$(printf '%s\n' "$edit_sessions" | grep -v '^unattributed$' | grep -v '^$')"
if [ -z "$real_edit_sessions" ]; then
  attributed=0
else
  attributed="$(jq -Rr 'fromjson? | objects | (.session_id // "" | if . == "" then "unattributed" else . end)' "$IL_LOG" 2>/dev/null | grep -Fxf <(printf '%s\n' "$real_edit_sessions") 2>/dev/null | grep -c .)" || true
fi

# --- Dormant vs dead channel (MA-003 / MA-R2-003) ---------------------------
# hook_edits is already computed. Empty/absent IL_LOG is benign ONLY when no hook
# edits happened; if hook edits happened with zero rule-loads the channel may be
# dead (hook not registered, harness too old to emit InstructionsLoaded, or not
# firing), not merely quiet.
if [ ! -s "$IL_LOG" ]; then
  if [ "${hook_edits:-0}" -eq 0 ]; then
    echo "no direct rule-load signal yet — the InstructionsLoaded log populates the first time a .claude/rules/*.md-scoped file is opened; requires harness >=2.1.69 AND that /csetup has registered the InstructionsLoaded hook in this project's settings.json (re-run /csetup if you recently upgraded)"
  else
    echo "WARNING: ${hook_edits} hook-edit(s) occurred but zero rule-load events were recorded — the channel may be dead (hook not registered, harness <2.1.69 which does not emit InstructionsLoaded, or not firing), not merely quiet."
  fi
elif [ "${rule_loads:-0}" -eq 0 ]; then
  # MA-008(a): the file has bytes but nothing parses as an object.
  echo "log present but 0 parseable JSONL lines — possible corruption or torn writes; treat as no signal"
fi

# --- Liveness denominators (INV-016 / DA-004 / MA-011) ----------------------
if [ "$audit_located" -eq 1 ]; then
  # read K reconciles: attributed (to this workflow's real edit-sessions) + other
  # (rule-loads from unrelated sessions) + null rule_file (MA-011).
  rl_breakdown="read ${rule_loads} rule-load event(s) (${attributed} attributed to this workflow's edit-sessions, $(( rule_loads - attributed )) from other sessions, ${null_rules} with null rule_file)"
  if [ "$audit_autoresolved" -eq 1 ]; then
    # MA-R2-001 provenance: source was auto-resolved by fallback — name it, do NOT
    # assert it authoritatively describes "the target workflow".
    echo "Liveness: ${rl_breakdown} and ${hook_edits} hook-edit entries across ${edit_session_count} edit-session(s) (hook-edit source auto-resolved to ${AUDIT_TRAIL##*/}; verify it matches the workflow you are auditing); log last written ${last_written:-never}"
  else
    echo "Liveness: ${rl_breakdown} and ${hook_edits} hook-edit entries across ${edit_session_count} edit-session(s) for the target workflow; log last written ${last_written:-never}"
  fi
else
  # MA-004: no source located — do NOT report "0 hook-edit entries" as if measured.
  echo "Liveness: read ${rule_loads} rule-load event(s) (${null_rules} with null rule_file); hook-edit source not located (audit-trail-*.jsonl not found) — hook-edit attribution unavailable; log last written ${last_written:-never}"
fi

# --- Field-drift note (INV-009 / MA-008b / MA-R2-004) -----------------------
if [ "${rule_loads:-0}" -gt 0 ] && [ "${rule_loads}" = "${null_rules}" ]; then
  echo "${rule_loads} rule-load events, all with null rule_file — possible harness field drift; treat the rule-load evidence as unreliable"
elif [ "${rule_loads:-0}" -gt 0 ] && [ "$(( null_rules * 2 ))" -ge "${rule_loads}" ]; then
  echo "high null-rule ratio (${null_rules}/${rule_loads}) — possible harness field drift; treat the rule-load evidence as unreliable"
fi

# --- Raw evidence grouped by the TARGET workflow's edit-session ids (RS-027) --
printf '%s\n' "$edit_sessions" | while IFS= read -r sess; do
  [ -z "$sess" ] && continue
  echo "=== edit-session: ${sess} ==="
  # MA-007: the unattributed group predates session_id instrumentation.
  if [ "$sess" = "unattributed" ]; then
    echo "  these edits predate session_id instrumentation — rule-loads cannot be attributed to them; absence of rule-loads here is NOT evidence the rule was unloaded."
  fi
  jq -Rr --arg s "$sess" 'fromjson? | objects
     | select(((.file // "") | tostring | (test("^hooks/") or test("(^|/)\\.correctless/hooks/"))) and ((.tool // "") | tostring | test("^(Edit|Write|MultiEdit|NotebookEdit|CreateFile|Bash)$")))
     | select((.session_id // "" | if . == "" then "unattributed" else . end) == $s)
     | "  hook-edit: \(.file) at \((.ts // .timestamp) // "?")"' "$AUDIT_TRAIL" 2>/dev/null
  # Rule-loads are only attributed to real (non-unattributed) sessions. The key is
  # normalized identically so a null/empty-session rule-load can never match a real
  # $s, and the "unattributed" group never claims any rule-load (QA-001 / INV-015).
  if [ "$sess" != "unattributed" ]; then
    jq -Rr --arg s "$sess" 'fromjson? | objects
       | select((.session_id // "" | if . == "" then "unattributed" else . end) == $s)
       | "  rule-load: \(.rule_file // "(null)") (trigger_file_path \(.trigger_file_path // "?")) at \(.ts // "?")"' "$IL_LOG" 2>/dev/null
  fi
done

# --- Unmatched rule-load sessions (MA-006 / EA-005 / MA-R2-004 / MA-010) -----
# Surface the DISTINCT rule-load session_ids so a human can spot session_id format
# drift. Fire ONLY when there was at least one real (non-unattributed) edit-session to
# match against — when real_edit_sessions is empty (all edits pre-instrumentation),
# attributed==0 is BENIGN and the unattributed-group header already explains it, so
# the drift note is suppressed to avoid a false "session_id format drift" alarm.
if [ "${rule_loads:-0}" -gt 0 ] && [ -n "$real_edit_sessions" ] && [ "${attributed:-0}" -eq 0 ]; then
  rl_sess_seen="$(jq -Rr 'fromjson? | objects | (.session_id // "(null)")' "$IL_LOG" 2>/dev/null | sort -u | grep . | tr '\n' ' ')" || true
  echo "note: ${rule_loads} rule-load event(s) exist but none matched an edit-session_id — possible session_id format drift across events (EA-005); rule-load session_ids seen: ${rl_sess_seen}"
fi

exit 0
```
<!-- cwtf:rule-load-extract:end -->

Present the block's output as-is under a "Rule-load evidence" heading. Do **not** compute or state whether a rule "was" or "was not" in context for a given edit — show the timestamps side by side and let the reader judge.

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

**Persist before presenting (AP-029).** Before displaying the report to the user, write it to `.correctless/artifacts/wtf-report-{branch-slug}.md` where branch-slug is derived from `branch_slug()`. This is the recovery path if the terminal display is interrupted or context is compacted.

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

## Autonomous Defaults

- **AD-001**: Analysis scope — analyze all available data sources for accountability report (default). No human input required; this skill runs to completion autonomously.

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
