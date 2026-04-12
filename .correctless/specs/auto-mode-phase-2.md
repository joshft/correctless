# Spec: Auto Mode Phase 2

## Metadata
- **Created**: 2026-04-11T22:00:00Z
- **Status**: reviewed
- **Impacts**: semi-auto-mode
- **Branch**: auto-mode-phase2
- **Research**: null
- **Recommended-intensity**: high
- **Intensity**: high
- **Intensity reason**: touches skills/cauto/SKILL.md (orchestrator skill), hooks/ path signal, keywords: trust boundary (TB-004 orchestrator autonomy)
- **Override**: none

## Context

Auto Mode Phase 2 extends the existing `/cauto` semi-auto orchestrator with a policy-driven decision engine that resolves most runtime decisions without human intervention. The human still writes the spec and approves the review (Phase 3 handles autonomous spec/review). Phase 2 adds: a tiered decision architecture (Tier 0 policy engine, Tier 1 worker self-resolution, Tier 2 ephemeral decision agents, Tier 3 lightweight supervisor, Tier 4 hard stop), structured decision requests (DR-xxx format), a decision record artifact, an Auto Run Report, hard stop/resume, and budget enforcement. The supervisor interface uses structured message-in/message-out to support future Factory mode without rewriting the communication layer.

## Scope

**In scope:**
- Decision policy engine (`.correctless/config/auto-policy.json`) with mechanical Tier 0 evaluation
- Tier 1 worker self-resolution with mandatory logging
- Tier 2 ephemeral decision agents with structured DR-xxx requests and responses
- Tier 3 supervisor agent with message-based interface (activates on escalation + phase transitions)
- Tier 4 hard stop with structured decision request for human
- Decision record artifact (`.correctless/artifacts/decision-record-{slug}.md`)
- Auto Run Report generation on completion or pause
- Budget enforcement (token + time limits with warn/hard-stop thresholds)
- Hard stop recovery and `/cauto resume` flow
- Extension of `auto-policy.json` scaffolding via `/csetup`

**Not in scope:**
- Autonomous spec writing (Phase 3)
- Autonomous spec review (Phase 3)
- Factory mode (supervisor on remote machine, worker queue, parallel execution)
- Notification channels (Telegram, Discord, webhooks) — budget warnings activate the supervisor but do not alert the human in real-time; the human discovers warnings via the Auto Run Report after the fact
- Policy learning / calibration from past decisions
- Auto-merge to main
- Parallel skill execution
- Custom pipeline ordering

## Complexity Budget
- **Estimated LOC**: ~1200-1800
- **Files touched**: ~15-18
- **New abstractions**: ~7 (decision record ABS-011, intent summary ABS-012, auto run report ABS-013, pending-decision checkpoint ABS-014, cauto-lock ABS-015, auto-policy config ABS-016, DR-xxx contract ABS-017 — formal ABS entries created during `/cupdate-arch` phase)
- **Trust boundaries touched**: 1 (TB-004 orchestrator autonomy — extends, does not create new)
- **Risk surface delta**: medium

## Prerequisites

- Add `Task` to `/cauto`'s `allowed-tools` frontmatter — required for spawning Tier 2/3 agents via `Task(subagent_type="correctless:{name}")`
- Create `agents/supervisor.md` per ABS-010 — supervisor agent must be a plugin agent, not an inline prompt
- Create `agents/decision-agent.md` per ABS-010 — Tier 2 decision agent must be a plugin agent, tools pinned to `Read, Grep, Glob` only (no Write, no Bash, no Task)

## Auto-Policy Schema

Tier 0 policy evaluation requires a defined schema. The file at `.correctless/config/auto-policy.json` uses this structure:

```json
{
  "review_dispositions": {
    "security": "fix",
    "availability": "add_rule",
    "testability": "fix",
    "scope_expansion": "defer",
    "performance": "tier2_decide",
    "default": "tier2_decide"
  },
  "qa_dispositions": {
    "critical": "fix",
    "high": "fix",
    "medium": { "fix_under_loc": 50, "defer_over_loc": true },
    "low": "defer_to_report"
  },
  "spec_update": {
    "max_autonomous_revisions": 2,
    "on_third_revision": "escalate_supervisor",
    "on_fundamental_restructure": "hard_stop"
  },
  "drift": {
    "clear_violation": "fix",
    "ambiguous": "log_as_debt",
    "intentional_divergence": "tier2_decide"
  },
  "security": {
    "never_relax_autonomously": true
  },
  "budget": {
    "max_tokens": 2000000,
    "warn_at_percent": 75,
    "hard_stop_at_percent": 100
  },
  "time": {
    "max_duration_hours": 8,
    "warn_at_hours": 6
  },
  "ambiguity_policy": "conservative",
  "hard_stops": [
    "security_constraint_conflict",
    "spec_requires_fundamental_restructure",
    "budget_exceeded",
    "time_exceeded",
    "supervisor_uncertain",
    "3_or_more_spec_revisions"
  ]
}
```

**Category vocabulary (controlled):** `security`, `availability`, `testability`, `scope_expansion`, `performance`, `architecture`, `observability`, `technical_debt`. DR-xxx `category` must use one of these values. Unrecognized categories route to Tier 1+ (no crash).

**Disposition vocabulary:** `fix`, `defer`, `defer_to_report`, `add_rule`, `tier2_decide`, `escalate_supervisor`, `hard_stop`, `log_as_debt`. Policy rules map categories to dispositions.

**Matching order:** First-match-wins. The orchestrator evaluates the DR-xxx `category` against policy sections in order: `review_dispositions` (if phase is review), `qa_dispositions` (if phase is QA), `drift` (if phase is verify), `spec_update` (if decision involves spec changes). If no section matches the current phase+category, the result is "no match" → route to Tier 1+.

**Malformed JSON handling:** If auto-policy.json fails to parse as valid JSON (jq exits non-zero), the orchestrator logs a warning: "auto-policy.json is malformed — treating as empty." All decisions route to Tier 1+. The hardcoded security floor (`security.never_relax_autonomously`) still applies even when the file is malformed — it is enforced in orchestrator code, not read from the file.

**`ambiguity_policy` values:** `conservative` (default — make the safer assumption, tag as ASSUMPTION), `pause` (hard stop on first unresolvable ambiguity), `best_judgment` (supervisor makes its best call based on project context).

## Invariants

### INV-001: Policy evaluation is deterministic and dual-pass
- **Type**: must
- **Category**: functional
- **Statement**: Given the same DR-xxx structured decision request and the same auto-policy.json config, Tier 0 policy evaluation must always produce the same disposition. No LLM reasoning is involved in Tier 0 — it is pure config-driven conditional logic applied by the orchestrator using the first-match-wins algorithm defined in the Auto-Policy Schema section. Tier 0 evaluates twice per decision lifecycle: (1) **pre-routing** — when a decision is first surfaced, Tier 0 checks for a matching policy; if matched, the decision resolves immediately without agent involvement; if unmatched, the decision routes to Tier 1+. (2) **post-Tier-2 validation** — after a Tier 2 agent returns its decision, Tier 0 re-evaluates to check for policy contradictions (see INV-012).
- **Boundary**: TB-004
- **Violated when**: Tier 0 produces different dispositions for identical inputs, an LLM agent is spawned for a Tier 0 decision, or the post-Tier-2 validation pass is skipped
- **Guards against**: null
- **Test approach**: unit
- **Risk**: high
- **Implemented in**: (GREEN phase)

### INV-002: Every autonomous decision logged to decision record with per-tier cardinality
- **Type**: must
- **Category**: data-integrity
- **Statement**: Every tier invocation must produce a DD-xxx entry in `.correctless/artifacts/decision-record-{slug}.md`. Per-tier rules: (a) Tier 0 match → DD-xxx with disposition and matching policy rule. (b) Tier 0 no-match → DD-xxx with disposition "routing" and reason "no matching policy." (c) Tier 0 post-Tier-2 validation → DD-xxx with validation result (pass or conflict). (d) Tier 1 self-resolution or escalation → DD-xxx each. (e) Tier 2 every invocation → DD-xxx. (f) Tier 3 every activation → DD-xxx. Each entry must contain: decision ID (DD-xxx), tier (0-3 or "human" or "system"), category, summary, disposition, reasoning, and timestamp. **Cardinality verification mechanism:** The independent counter is the audit trail (R-011), not the decision record itself. Post-pipeline check: DD-xxx count in the decision record must equal the count of `decision_routed` events (all tiers) + `supervisor_activated` events in the audit trail JSONL + 1 (DD-000 intent creation). This avoids circular self-verification — the audit trail is the mechanical counter, the decision record is the high-level artifact.
- **Boundary**: ABS-007
- **Violated when**: A tier invocation occurs without a corresponding DD-xxx entry, or a DD-xxx entry is missing any required field, or post-pipeline cardinality check (decision record vs audit trail) fails
- **Guards against**: null
- **Test approach**: integration
- **Risk**: critical
- **Implemented in**: (GREEN phase)

### INV-003: Structured decision request format
- **Type**: must
- **Category**: functional
- **Statement**: Every decision request routed beyond Tier 0 must use the DR-xxx structured JSON format containing: `decision_id`, `requesting_agent`, `phase`, `category` (from controlled vocabulary), `summary`, `severity` (if applicable), `options` (array with id + description + loc_estimate where applicable), `relevant_rules` (array of R-xxx/INV-xxx IDs), `relevant_policies` (array of policy paths), and `prior_decisions` (array of DD-xxx references containing summary + disposition only — not full reasoning, to maintain Tier 2 minimal context per INV-006). The orchestrator validates the DR-xxx structure before routing — malformed requests are fail-closed (logged as error, escalated to Tier 3).
- **Boundary**: TB-004
- **Violated when**: A decision is routed to Tier 1/2/3 without a structured DR-xxx, or the DR-xxx is missing required fields, or a malformed DR-xxx is silently dropped
- **Guards against**: null
- **Test approach**: unit
- **Risk**: high
- **Implemented in**: (GREEN phase)

### INV-004: Supervisor message interface
- **Type**: must
- **Category**: functional
- **Statement**: The supervisor agent receives a structured input message containing: `activation_type` (escalation | phase_transition | budget_warning), `intent_summary` (string, written once at pipeline start, ≤500 words), `decision_request` (DR-xxx if escalation, null otherwise), `phase_summary` ({phase, files_changed, loc_delta, rules_count}), `decision_record_recent` (last 5 DD-xxx entries), and `budget_status` ({used_tokens, limit_tokens, percent, elapsed_hours, limit_hours}). The supervisor returns a structured response containing: `decision` (approve | reject | hard_stop — `redirect` is NOT a valid terminal decision, see INV-007), `reasoning` (string, logged to decision record), and `flags` (array of strings — concerns for human review). The same message contract must work in-process (Auto mode) and over-the-wire (future Factory mode).
- **Boundary**: TB-004
- **Violated when**: The supervisor receives unstructured prose instead of the defined message format, or the supervisor's response is unstructured, or the contract changes in a way that breaks remote invocation
- **Guards against**: null
- **Test approach**: integration
- **Risk**: high
- **Implemented in**: (GREEN phase)

### INV-005: Tier routing follows escalation hierarchy
- **Type**: must
- **Category**: functional
- **Statement**: Decision routing must follow the tier hierarchy. Tier 0 (policy) is always evaluated first for every decision; it produces either a disposition (decision resolved) or "no match" (decision routes upward). When Tier 0 produces "no match," the decision routes to Tier 1 (worker self-resolution) for within-domain decisions. If the worker cannot self-resolve (cross-domain, security-relevant, or outside delegated authority), it routes to Tier 2 (decision agent). If Tier 2 cannot resolve (cross-phase coherence, conflicting precedents, or budget concerns), it escalates to Tier 3 (supervisor). If the supervisor cannot make a terminal decision (approve, reject, or hard_stop), it escalates to Tier 4 (hard stop) — see INV-007. No tier above the lowest applicable tier may be skipped — Tier 2 cannot route directly to Tier 4 without Tier 3 evaluation; Tier 1 cannot route directly to Tier 3 without Tier 2 evaluation.
- **Boundary**: TB-004
- **Violated when**: A decision bypasses a tier above the lowest applicable (e.g., Tier 1 → Tier 3 bypassing Tier 2, or Tier 2 → Tier 4 bypassing Tier 3)
- **Guards against**: null
- **Test approach**: integration
- **Risk**: high
- **Implemented in**: (GREEN phase)

### INV-006: Tier 2 decision agents get minimal context via template with structural enforcement
- **Type**: must
- **Category**: functional
- **Statement**: Each Tier 2 decision agent is spawned with `context: fork` and receives only: the DR-xxx decision request, the relevant spec excerpt(s) referenced by `relevant_rules`, the matching policy section from auto-policy.json, and the DD-xxx summaries referenced by `prior_decisions` (summary + disposition only, not full reasoning — per INV-003). The agent does NOT receive the full conversation history, the full spec, the full codebase context, or previous Tier 2 agent outputs. Each Tier 2 agent terminates after returning its decision — no state persists between Tier 2 invocations. **Structural enforcement:** (1) Tier 2 agent's `allowed-tools` in `agents/decision-agent.md` must be `Read, Grep, Glob` only — no Write, no Bash, no Task. The orchestrator is the sole writer. (2) Tier 2 prompts are constructed from the template in `agents/decision-agent.md` that explicitly enumerates allowed context fields; adding fields requires a spec change. (3) Static test: grep orchestrator's Tier 2 invocation code for forbidden context injection patterns (full spec reads, conversation history references).
- **Boundary**: TB-004
- **Violated when**: A Tier 2 agent receives full conversation history, accumulates state across invocations, persists after returning its decision, receives context fields not enumerated in the agent template, or has Write/Bash/Task in its allowed-tools
- **Guards against**: AP-013
- **Test approach**: integration
- **Risk**: medium
- **Implemented in**: (GREEN phase)

### INV-007: Supervisor activates only on escalation and phase transitions; redirect = hard_stop
- **Type**: must
- **Category**: resource-lifecycle
- **Statement**: The supervisor agent activates only when: (a) Tier 2 escalates a decision it cannot resolve, (b) the state machine completes a major phase transition (GREEN→QA, QA→done, done→verified, verified→documented), or (c) a budget/time warning threshold is crossed. The supervisor does NOT activate on Tier 0 decisions, Tier 1 self-resolutions, successful Tier 2 resolutions, individual tool calls, test runs, or file edits. **Redirect handling:** If the supervisor returns `decision: redirect`, the orchestrator treats it as `hard_stop` — Tier 3 could not make a terminal decision, so Tier 4 takes over. Valid terminal supervisor decisions are: `approve`, `reject`, `hard_stop`. **Hard cap:** the supervisor may activate no more than 20 times per pipeline run. The activation counter is stored in the workflow state file via `workflow-advance.sh` (persists across crashes/resumes). At activation 21, the orchestrator triggers Tier 4 hard stop with reason "supervisor activation cap exceeded."
- **Boundary**: TB-004
- **Violated when**: The supervisor activates for a Tier 0 or Tier 1 decision, activates on every tool call, exceeds 20 activations without triggering hard stop, or `redirect` is treated as a valid terminal decision
- **Guards against**: null
- **Test approach**: integration
- **Risk**: medium
- **Implemented in**: (GREEN phase)

### INV-008: Budget enforcement with warn and hard-stop thresholds; check before and after each skill
- **Type**: must
- **Category**: resource-lifecycle
- **Statement**: The orchestrator tracks token consumption (from `.correctless/artifacts/token-log-{slug}.jsonl`) and elapsed wall-clock time. Budget is checked **before each skill invocation and after each skill completion**. Before spawning a Tier 2 agent, if remaining token budget is < 5%, escalate to Tier 3 (supervisor) with `activation_type: budget_warning` instead of spawning Tier 2. When consumption reaches the `warn_at_percent` threshold (default 75%) for tokens or the `warn_at_hours` threshold (default 6) for time, the orchestrator activates the supervisor with `activation_type: budget_warning`. When consumption reaches `hard_stop_at_percent` (default 100%) for tokens or `max_duration_hours` (default 8) for time, the orchestrator triggers Tier 4 hard stop unconditionally — this is non-negotiable even if the supervisor recommends continuing. **Degraded mode (see BND-002):** when the token log is missing or unreadable, token-based budget enforcement is disabled; time-based budget enforcement remains active as a backstop.
- **Boundary**: TB-004
- **Violated when**: The orchestrator exceeds the token or time budget without triggering hard stop, the hard stop at 100% is overridable by the supervisor, budget is not checked before/after skill invocations, or the orchestrator crashes when the token log is missing instead of degrading to time-only enforcement
- **Guards against**: null
- **Test approach**: unit
- **Risk**: critical
- **Implemented in**: (GREEN phase)

### INV-009: Auto Run Report generated on completion or pause
- **Type**: must
- **Category**: functional
- **Statement**: When the pipeline completes (all skills finished) or hard-stops (Tier 4), the orchestrator writes an Auto Run Report to `.correctless/artifacts/auto-report-{slug}.md`. The report must contain: feature name, branch, start/end timestamps, duration, token cost, status (COMPLETE | PAUSED | BUDGET_EXCEEDED | TIME_EXCEEDED), decision record summary (count per tier), decisions requiring human review (ASSUMPTION-tagged + supervisor-flagged + hedging-scan candidates per INV-011), spec summary (rules count, review findings addressed, spec revisions), implementation summary (files modified, LOC added/removed, tests written, QA rounds, QA findings fixed/deferred), verification summary (rule coverage, dependency changes, drift findings), and a "What to Review First" prioritized list.
- **Boundary**: null
- **Violated when**: The pipeline ends without producing a report, or the report is missing any required section
- **Guards against**: null
- **Test approach**: integration
- **Risk**: medium
- **Implemented in**: (GREEN phase)

### INV-010: Hard stop produces structured decision request for human; priority ordering
- **Type**: must
- **Category**: functional
- **Statement**: When Tier 4 hard stop fires, the orchestrator writes a structured decision request to the escalation file (`.correctless/artifacts/escalation-{slug}.md`, extending ABS-007). The decision request includes: the phase where work stopped, the specific decision or condition that triggered the hard stop, numbered options with a recommendation, and a resume command (`/cauto resume "decision"`). All pipeline progress is preserved — no work is lost on hard stop. **Multiple simultaneous hard-stop conditions:** If multiple conditions are true, the orchestrator uses this priority ordering: (1) integrity violations (INV-016 decision record, INV-013 intent tampered, INV-018 policy tampered), (2) security (R-006 CLAUDE.md, PRH-001), (3) budget/time exceeded (INV-008), (4) supervisor cap exceeded (INV-007), (5) other escalations (INV-012 policy conflict, R-005 attempt threshold). Write the highest-priority reason to the escalation file. Log all active conditions to the decision record as a DD-xxx entry with tier "system" and category "hard_stop_multiplex."
- **Boundary**: ABS-007
- **Violated when**: A hard stop drops pipeline state, or the escalation file lacks a resume command, or the human cannot resume from the hard stop point, or multiple hard-stop conditions are not logged
- **Guards against**: null
- **Test approach**: integration
- **Risk**: high
- **Implemented in**: (GREEN phase)

### INV-011: Decision record tags assumptions prominently; post-pipeline hedging scan
- **Type**: must
- **Category**: data-integrity
- **Statement**: When the orchestrator or any tier makes a conservative assumption due to ambiguity in the spec or requirements (per the `ambiguity_policy` setting), the DD-xxx entry must include an `ASSUMPTION` tag. The Auto Run Report (INV-009) must list all ASSUMPTION-tagged decisions in the "Decisions Requiring Human Review" section. **Post-pipeline hedging scan:** After pipeline completion, the orchestrator scans all DD-xxx entries for hedging language ("assume," "likely," "probably," "default to," "conservative") in entries that lack the ASSUMPTION tag. Candidates are flagged in the Auto Run Report as "Potential untagged assumptions" for human review.
- **Boundary**: null
- **Violated when**: An assumption is made without tagging the DD-xxx entry, the Auto Run Report omits ASSUMPTION-tagged decisions, or the post-pipeline hedging scan is skipped
- **Guards against**: null
- **Test approach**: unit
- **Risk**: medium
- **Implemented in**: (GREEN phase)

### INV-012: Tier 0 validates Tier 2 decisions against policy (post-Tier-2 pass)
- **Type**: must
- **Category**: functional
- **Statement**: After a Tier 2 decision agent returns its decision, the orchestrator runs a second Tier 0 evaluation pass (see INV-001 dual-pass) to validate the response against the applicable policy rules in auto-policy.json. This is the same deterministic policy evaluation as the pre-routing pass — no LLM reasoning involved. If the Tier 2 decision contradicts a policy (e.g., Tier 2 says "fix" but policy says "defer" for that category), the orchestrator logs the conflict and escalates to Tier 3 (supervisor) rather than silently applying either.
- **Boundary**: TB-004
- **Violated when**: A Tier 2 decision that contradicts policy is applied without supervisor review, or the conflict is silently resolved by the orchestrator without logging
- **Guards against**: null
- **Test approach**: unit
- **Risk**: high
- **Implemented in**: (GREEN phase)

### INV-013: Intent summary written once, never modified, with enforcement
- **Type**: must
- **Category**: data-integrity
- **Statement**: At pipeline startup, the orchestrator writes an intent summary (≤500 words) derived from the approved spec to a separate file at `.correctless/artifacts/intent-{slug}.md`. The decision record's DD-000 entry (tier "system") references the intent file path. The intent summary captures: what the human wants, key constraints, explicit risk acceptances. This summary is passed to the supervisor on every activation. The intent summary is immutable after creation — no agent at any tier may modify it during the run. **Enforcement:** (1) the intent summary file is written to a sensitive-file-guard-protected path, preventing LLM writes after creation; (2) the orchestrator computes a SHA-256 hash of the intent summary at creation and stores it in the workflow state file via `workflow-advance.sh`; (3) on each supervisor activation AND on `/cauto resume`, the orchestrator re-hashes the current intent file and compares against the stored hash — mismatch triggers Tier 4 hard stop with reason "intent summary tampered."
- **Boundary**: TB-004
- **Violated when**: The intent summary is modified after initial creation, the hash check is skipped on supervisor activation or resume, or the hash mismatch does not trigger hard stop
- **Guards against**: null
- **Test approach**: integration
- **Risk**: medium
- **Implemented in**: (GREEN phase)

### INV-014: auto-policy.json scaffolded by /csetup
- **Type**: must
- **Category**: functional
- **Statement**: `/csetup` must scaffold a default `.correctless/config/auto-policy.json` during project initialization using the schema defined in the Auto-Policy Schema section. The scaffold contains all policy categories with conservative defaults. If the file already exists, `/csetup` must not overwrite it (idempotency, per PAT-008). The sensitive-file-guard must protect auto-policy.json from LLM writes.
- **Boundary**: TB-001
- **Violated when**: `/csetup` overwrites an existing auto-policy.json, or the file is unprotected by the sensitive-file-guard, or a new project has no auto-policy.json after setup
- **Guards against**: AP-004
- **Test approach**: integration
- **Risk**: medium
- **Implemented in**: (GREEN phase)

### INV-015: Resume from hard stop preserves full pipeline state; verify integrity on resume
- **Type**: must
- **Category**: functional
- **Statement**: When the human resumes from a Tier 4 hard stop via `/cauto resume "decision"`, the orchestrator: (1) re-hashes the intent summary and compares against the stored hash — mismatch → hard stop (INV-013), (2) re-hashes auto-policy.json and compares against the stored hash — mismatch → hard stop (INV-018), (3) reads the escalation file, (4) parses the human's response — tries option number first, falls back to LLM interpretation if not a number, (5) applies the human's decision to the decision record as a DD-xxx entry with tier "human", (6) resumes the pipeline from the exact phase where it paused, skipping completed skills. The existing R-016 resumption logic (phase consistency check, artifact existence check) applies. A stale escalation file (phase mismatch) triggers a fresh pipeline start, not a crash.
- **Boundary**: ABS-007
- **Violated when**: Resume re-runs completed skills, the human's decision is not logged, integrity checks are skipped on resume, or a stale escalation file causes a crash instead of a fresh start
- **Guards against**: null
- **Test approach**: integration
- **Risk**: high
- **Implemented in**: (GREEN phase)

### INV-016: Decision record is append-only; size tracked in workflow state
- **Type**: must-not
- **Category**: data-integrity
- **Statement**: The decision record file (`.correctless/artifacts/decision-record-{slug}.md`) is only appended to, never modified or truncated. The orchestrator is the sole writer (extending the ABS-007 pattern — agents return structured responses; the orchestrator appends to the file). Before each append, the orchestrator verifies the current file size is greater than or equal to the size recorded at the previous append. The previous size is stored in the workflow state file via `workflow-advance.sh` (persists across crashes/resumes). If the file has shrunk (indicating truncation or overwrite), the orchestrator triggers Tier 4 hard stop with reason "decision record integrity violation." **Accepted risk:** The decision record is not protected by the sensitive-file-guard (the orchestrator needs Write permission to `.correctless/artifacts/*`). The three-layer defense is: (a) scoped allowed-tools (only `/cauto` has this Write permission), (b) append-only with size-regression check, (c) size persisted in workflow state across crashes.
- **Boundary**: ABS-007
- **Atomicity note**: The size recorded in workflow state is updated atomically after each append completes (post-flush). On resume, the stored size is compared to actual file size; equality or growth is valid, shrinkage is the violation. The update order (append → flush → update stored size) prevents false positives from a crash between append and state write.
- **Violated when**: The decision record is modified in place, truncated, or overwritten, or a size regression is not detected
- **Guards against**: null
- **Test approach**: unit
- **Risk**: critical
- **Implemented in**: (GREEN phase)

### INV-017: Orchestrator checkpoints pending state before Tier 2 invocation
- **Type**: must
- **Category**: functional
- **Statement**: Before spawning a Tier 2 decision agent, the orchestrator writes a checkpoint to `.correctless/artifacts/pending-decision-{slug}.json` containing: the DR-xxx being evaluated, the current tier (2), the requesting skill, and the pipeline phase. If the orchestrator hits context limits or crashes mid-Tier-2, the resumption logic (INV-015, R-016) reads the checkpoint on restart. If a pending decision checkpoint exists on resume: (a) check if a corresponding DD-xxx entry exists in the decision record — if yes, the Tier 2 agent completed and the checkpoint is stale, delete it and continue; (b) if no DD-xxx entry exists, re-invoke Tier 2 with the same DR-xxx (Tier 2 is idempotent per INV-006 — fresh context each time). The checkpoint file is deleted after the decision is logged.
- **Boundary**: TB-004
- **Violated when**: A Tier 2 agent is spawned without a checkpoint, or the checkpoint is not cleaned up after decision logging, or a crash mid-Tier-2 leaves the pipeline in an unrecoverable state
- **Guards against**: null
- **Test approach**: integration
- **Risk**: high
- **Implemented in**: (GREEN phase)

### INV-018: Policy integrity verified via hash
- **Type**: must
- **Category**: data-integrity
- **Statement**: At pipeline startup, the orchestrator computes a SHA-256 hash of `.correctless/config/auto-policy.json` and stores it in the workflow state file via `workflow-advance.sh`. On each Tier 0 evaluation (both pre-routing and post-Tier-2 passes), the orchestrator re-hashes auto-policy.json and compares against the stored hash. Mismatch triggers Tier 4 hard stop with reason "policy modified during run." This prevents policy mutations mid-pipeline (e.g., human edit, git merge from main) from breaking Tier 0 dual-pass determinism (INV-001).
- **Boundary**: TB-004
- **Violated when**: Policy hash is not verified before Tier 0 evaluation, a hash mismatch does not trigger hard stop, or the hash is not checked on resume
- **Guards against**: null
- **Test approach**: unit
- **Risk**: high
- **Implemented in**: (GREEN phase)

## Prohibitions

### PRH-001: Never relax security constraints autonomously
- **Statement**: No agent at any tier (0-3) may make a decision that weakens a security constraint from the spec. Security-related decisions that would relax a constraint must always route to Tier 4 (hard stop). The `security.never_relax_autonomously` policy is hardcoded in orchestrator code — it cannot be set to `false` in auto-policy.json and is enforced even when the policy file is malformed or missing. **Three-layer detection:** (a) **Category gate:** decisions with `category: "security"` always route to Tier 4 for relaxation. (b) **Keyword scan:** the policy validator scans the DR-xxx `summary` and `reasoning` fields for security-relevant terms (auth, credential, encrypt, token, secret, permission, access control, trust boundary, identity, authorization, login, verification, access level, privilege) and flags mismatches where terms are present but `category` is non-security, escalating to Tier 3 for reclassification. (c) **Structural guard:** any decision whose `options` include removing or downgrading existing checks, constraints, validations, or tests must escalate to Tier 3 regardless of category — this is category-independent and harder to reframe around than keywords. **Residual risk accepted:** defense-in-depth means the supervisor (Tier 3) is the backstop. No single layer is foolproof; together they raise the bar significantly.
- **Tier 3 reclassification action**: When the keyword scan or structural guard escalates to Tier 3 for reclassification, the supervisor evaluates whether the decision is genuinely security-relevant. If yes → supervisor returns `decision: hard_stop` (security relaxation requires human). If the supervisor determines it's a genuine false positive (e.g., logging enhancement that mentions "auth" but doesn't relax constraints) → supervisor returns `decision: approve` with reasoning documenting why. The supervisor does NOT reclassify and route back through Tier 0 — that would create a potential loop. The supervisor makes a terminal decision: hard_stop or approve.
- **Detection**: grep auto-policy.json parsing for hardcoded security enforcement; test security keyword mismatch triggers Tier 3; test structural guard catches remove/downgrade decisions; test that hardcoded floor applies when policy file is malformed; test that Tier 3 reclassification produces terminal decision (hard_stop or approve), not re-routing
- **Consequence**: Silent security degradation in autonomous runs

### PRH-002: Never merge to main in auto mode
- **Statement**: Auto mode completes on a feature branch. The orchestrator must never run `git merge`, `git push` to main/master, or `gh pr merge`. The human reviews and merges.
- **Detection**: grep SKILL.md for merge/push commands; test that pipeline completion leaves the branch unmerged
- **Consequence**: Untested code lands on main without human review

### PRH-003: Never delete tests autonomously
- **Statement**: Auto mode may add tests and (with logging) modify tests, but must never delete test files or remove test functions. If a skill determines a test should be deleted, it must escalate to the human.
- **Detection**: post-skill diff check for deleted test files or removed test functions
- **Consequence**: Test coverage silently degrades during autonomous runs

### PRH-004: Never override the workflow gate
- **Statement**: Auto mode must never use `workflow-advance.sh override`. If the gate blocks an operation, the orchestrator routes to the appropriate decision tier. The override mechanism is reserved for human-interactive use only.
- **Detection**: grep SKILL.md for `override` command usage; test that gate blocks trigger tier routing, not overrides
- **Consequence**: Gate violations go undetected, bypassing the phase discipline

### PRH-005: Supervisor must not accumulate state across activations
- **Statement**: Each supervisor activation is invoked with `context: fork` (enforced in `/cauto` logic, not by human discipline). The supervisor receives only the defined message fields per `agents/supervisor.md` template: activation_type, intent_summary, decision_request, phase_summary, decision_record_recent, budget_status. The supervisor must not receive prior supervisor responses, full conversation history, or accumulated context. Each activation is independent.
- **Detection**: supervisor invoked with `context: fork` each time (static check of `/cauto` SKILL.md); `agents/supervisor.md` must not reference "remember," "prior activation," "earlier discussion," or similar terms; functional test: invoke supervisor twice with different decision requests, verify second response doesn't reference first
- **Consequence**: Context degradation across long runs — supervisor decisions become unreliable

## Boundary Conditions

### BND-001: Empty or malformed auto-policy.json
- **Boundary**: TB-004
- **Input from**: human-edited config file
- **Validation required**: If auto-policy.json is absent, empty, or fails to parse as valid JSON: all Tier 0 evaluations return "no matching policy" and decisions route to Tier 1+. The hardcoded security floor still applies. The orchestrator must not crash. Log a one-time warning: "auto-policy.json is absent/malformed — all decisions will route to Tier 1+."
- **Failure mode**: fail-open (route to higher tier, never drop a decision); security floor remains fail-closed

### BND-002: Budget tracking with missing token log
- **Boundary**: ABS-006
- **Input from**: token-tracking hook output
- **Validation required**: If token-log JSONL is missing or empty, budget tracking defaults to "unknown" — budget warnings and hard stops based on token count are disabled. Time-based budget (elapsed hours) still enforces. Log a warning: "Token log not found — token budget enforcement disabled, time budget still active."
- **Failure mode**: fail-open for token budget, active for time budget

### BND-003: Malformed DR-xxx from worker
- **Boundary**: TB-004
- **Input from**: LLM-generated decision request
- **Validation required**: Validate DR-xxx JSON structure before routing. Missing required fields or invalid types cause the orchestrator to log the malformed request, tag it as an error DD-xxx entry, and escalate to Tier 3 (supervisor) with context about the malformed request.
- **Failure mode**: fail-closed (escalate, never drop silently)

### BND-004: Supervisor returns unexpected response
- **Boundary**: TB-004
- **Input from**: Tier 3 supervisor agent
- **Validation required**: Validate supervisor response contains `decision`, `reasoning`, and `flags` fields. If `decision` is not one of the allowed values (approve, reject, hard_stop), or is `redirect`, treat as hard_stop and log the unexpected response.
- **Failure mode**: fail-closed (default to hard_stop on unrecognized or redirect supervisor response)

### BND-005: Decision record file grows large
- **Boundary**: filesystem
- **Input from**: accumulated DD-xxx entries over a long run
- **Validation required**: No hard cap on decision record size in Phase 2, but the Auto Run Report summarizes by tier count rather than reproducing all entries. Supervisor reads only the last 5 entries per activation (INV-004), not the full record. **Phase 3/Factory note:** overnight runs will produce larger records. At that point: pagination in Auto Run Report generation, supervisor's "last 5 entries" query must remain O(5) not O(N), and a soft cap (e.g., 10,000 DD-xxx entries or 10 MB). Not enforced in Phase 2 but called out for Phase 3.
- **Failure mode**: not applicable — natural bounds from pipeline duration in Phase 2

### BND-006: Concurrent /cauto invocations on same branch
- **Boundary**: TB-004
- **Input from**: human accidentally starts two /cauto runs
- **Validation required**: At pipeline startup, the orchestrator creates a lockfile at `.correctless/artifacts/cauto-lock-{slug}`. If the lockfile already exists and contains a PID that is still running, the second invocation aborts with: "Another /cauto run is active on this branch." Lockfile deleted on pipeline completion, hard stop, or escalation. Stale lockfiles (PID no longer running) are automatically cleaned up. **Corrupted lockfile:** If the lockfile exists but does not contain a parseable PID, the orchestrator refuses to start with message: "Lockfile corrupted; delete `.correctless/artifacts/cauto-lock-{slug}` manually if no /cauto run is active." This matches the fail-closed posture — never assume a corrupted lockfile is stale. **Factory note:** PID-based stale detection assumes single-machine execution. Factory mode requires hostname + PID or a distributed lock.
- **Failure mode**: fail-closed (refuse to start, never interleave; corrupted lockfile = refuse, not auto-clean)

## STRIDE Analysis

### STRIDE for TB-004: LLM orchestrator autonomy boundary

- **Spoofing**: A Tier 2 decision agent could claim to be the supervisor in its response. Mitigated by: the orchestrator validates which tier produced the response based on invocation context, not self-reported identity.
- **Tampering**: An agent could modify the decision record to hide a previous decision. Mitigated by: decision record is append-only with size-regression detection stored in workflow state (INV-016); the orchestrator is the sole writer; Tier 2 agents have no Write permission (INV-006). Policy and intent integrity verified via hash (INV-013, INV-018).
- **Repudiation**: An agent could make a decision without logging it. Mitigated by: INV-002 requires every tier invocation produces a DD-xxx entry with post-pipeline cardinality check. The Auto Run Report counts decisions per tier.
- **Information Disclosure**: Decision requests contain spec excerpts and prior decisions. Mitigated by: Tier 2 agents receive minimal context via template (INV-006) with structural enforcement (Read/Grep/Glob only). Prior decisions include summary + disposition only, not full reasoning. Supervisor receives only summaries.
- **Denial of Service**: A Tier 2 agent could loop indefinitely. Mitigated by: budget enforcement checks before/after each skill (INV-008) with 5% Tier 2 threshold. Supervisor cap at 20 activations (INV-007). Redirect = hard_stop prevents escalation loops.
- **Elevation of Privilege**: A Tier 1 worker could self-resolve a security decision. Mitigated by: three-layer security detection (PRH-001) — category gate, keyword scan with expanded vocabulary, and structural guard for remove/downgrade decisions. The supervisor is the backstop, not a single keyword list.

## Environment Assumptions

- **EA-001**: Claude Code `context: fork` provides genuine context isolation — the spawned agent does not share memory with the caller. Consequence if wrong: Tier 2 agents accumulate state, violating INV-006 and PRH-005. — refs ENV-007
- **EA-002**: The token-tracking PostToolUse hook (ABS-006) fires for Agent tool completions reliably enough for budget tracking. Consequence if wrong: budget enforcement (INV-008) under-counts tokens. Time-based budget provides a backstop. — refs ABS-006
- **EA-003**: `jq` 1.7+ is available for parsing auto-policy.json and decision requests. All jq filters must use `--arg` for user-controlled values (AP-010) and explicit parenthesization for `as $var` bindings (PAT-010). Consequence if wrong: Tier 0 policy evaluation fails. — refs ENV-002
- **EA-004**: SHA-256 hashing tool is available on PATH. The implementation tries `sha256sum`, `shasum -a 256`, `openssl dgst -sha256` in order, uses the first available. `/csetup` probes for hash tool availability during project initialization and warns: "No SHA-256 tool found — intent and policy hash enforcement (INV-013, INV-018) will be disabled. Install sha256sum, shasum, or openssl to enable integrity checks." If no hash tool is found at pipeline startup, hash enforcement degrades gracefully: intent and policy integrity checks are skipped (not fail-closed), time-based budget enforcement remains active. Consequence if wrong: integrity enforcement is absent, relying on sensitive-file-guard as sole protection.

## Workflow State Extensions

Phase 2 adds these fields to the workflow state file (`.correctless/artifacts/workflow-state-{branch-slug}.json`), written exclusively via `workflow-advance.sh` (PAT-004):

| Field | Type | Written by | Read by | Purpose |
|-------|------|-----------|---------|---------|
| `supervisor_activation_count` | integer | orchestrator (incremented before each supervisor invocation) | orchestrator (cap check per INV-007) | Hard cap at 20 activations |
| `decision_record_size` | integer (bytes) | orchestrator (updated after each append post-flush) | orchestrator on resume (INV-016 size-regression baseline) | Append-only integrity check |
| `intent_hash` | string (SHA-256 hex) | orchestrator (at pipeline startup) | orchestrator on supervisor activation + resume (INV-013) | Intent immutability enforcement |
| `policy_hash` | string (SHA-256 hex) | orchestrator (at pipeline startup) | orchestrator on each Tier 0 evaluation + resume (INV-018) | Policy integrity during run |
| `pipeline_start_time` | string (ISO 8601) | orchestrator (at pipeline startup) | orchestrator (elapsed time computation for INV-008) | Time-based budget enforcement |

These fields are additive — they do not modify existing workflow state schema fields. `workflow-advance.sh` needs new subcommands or an extension mechanism to write these fields atomically.

## Audit Trail Extensions

Phase 2 adds these event types to the R-011 audit trail schema (`.correctless/artifacts/audit-trail-{slug}.jsonl`):

- `decision_routed` — logged when a decision is routed to a tier. Fields: `tier` (0-4), `decision_id` (DR-xxx), `disposition` (for Tier 0 matches), `routing_reason` (for Tier 0 no-match).
- `supervisor_activated` — logged on each supervisor activation. Fields: `activation_type`, `activation_count` (1-20), `trigger` (escalation source or phase transition name).
- `budget_warning` — logged when a budget threshold is crossed. Fields: `budget_type` (tokens | time), `current_value`, `threshold`, `percent`.

## Design Decisions

- **Structural enforcement over prompt-level instruction**: Invariants that protect against adversarial or accidental violation must have structural enforcement, not prompt-level instruction. "The agent is told to do X" is not an enforcement mechanism — it's a hope. Acceptable enforcement mechanisms are: allowed-tools restrictions, file permissions (via sensitive-file-guard), pre/post-condition checks in orchestrator code, cryptographic verification (hashes), static test assertions in CI, or tool-pinning in plugin agent frontmatter.
- **Decision record as separate markdown file** (not JSONL): The decision record's primary audience is the human reviewing in the morning. Markdown with DD-xxx entries is scannable. The JSONL audit trail continues to log machine events.
- **auto-policy.json as separate config** (not preferences.md or workflow-config.json): Policy evaluation is mechanical (Tier 0). JSON is directly parseable. `preferences.md` stays for human judgment calls; `auto-policy.json` for deterministic policy rules.
- **Supervisor as message-in/message-out agent** (not local file reader): Same contract works in-process (Auto mode) and over-the-wire (future Factory mode). No rewrite needed when Factory ships.
- **Orchestrator stays in /cauto SKILL.md** (not workflow-advance.sh): The state machine stays lean (phase gate only). `/cauto` handles decision routing, budget tracking, supervisor coordination, and report generation.
- **Hardcoded security policy floor**: `security.never_relax_autonomously` is enforced in orchestrator code, not read from auto-policy.json. Cannot be set to false. Applies even when policy file is malformed or missing.
- **Supervisor activation budget**: Typical: 5-10 activations over 2-hour run. Hard cap: 20. Set 2x above expected upper bound. Tunable based on empirical data from early Phase 2 runs.
- **Intent summary lives in a separate file**: Enables sensitive-file-guard protection and hash-based integrity verification. DD-000 references the file path.
- **Budget warnings don't notify the human in real-time**: Phase 2 has no notification channels. Supervisor handles budget warnings; human reviews in Auto Run Report. Factory mode adds notifications.
- **Checkpoint before Tier 2 invocation**: Orchestrator writes pending-decision checkpoint, not Tier 2 agent. Re-invocation on crash is idempotent (INV-006 — fresh context each time).
- **Decision record protection — accepted risk**: Decision record cannot be sensitive-file-guard protected because orchestrator needs Write permission. Three-layer defense: scoped allowed-tools, append-only with size-regression in workflow state, and sole-writer pattern.
- **Supervisor sees orchestrator's view, not raw agent output**: The supervisor's `decision_record_recent` field shows the last 5 DD-xxx entries as logged by the orchestrator, not as returned by Tier 2 agents. If the orchestrator's post-Tier-2 validation (INV-012) modified the disposition (e.g., flagged a policy conflict), the supervisor sees the validated result. This is the correct design — the supervisor should see the orchestrator's view of the world, not raw Tier 2 output that may have been overridden. Do not "fix" this by changing what the supervisor sees.

## Resolved Questions

- **OQ-001 (resolved)**: `/cauto resume "decision"` tries option number first, falls back to LLM interpretation. Reflected in INV-015.
- **OQ-002 (resolved)**: Intent summary stored as separate file at `.correctless/artifacts/intent-{slug}.md`, referenced from DD-000. Reflected in INV-013.
- **OQ-003 (resolved)**: Orchestrator checkpoints pending DR-xxx before Tier 2 invocation; re-invokes idempotently on crash. Reflected in INV-017.
