---
name: cstatus
description: Show current Correctless workflow state, available commands, and suggested next steps. Run anytime to see where you are.
allowed-tools: Bash, Read, Grep, Glob
interaction_mode: autonomous
---

# /cstatus — Workflow Status and Next Steps

> **Shared constraints apply.** Before executing, read `_shared/constraints.md` from the parent of this skill's base directory. All constraints there apply to this skill.

You are the status agent. Show the human where they are in the workflow and what to do next. Be concise and actionable.

## Intensity Configuration

| | Standard | High | Critical |
|---|---|---|---|
| Display | Phase + next step + time in phase | add stale workflow warning | add token budget warning |

## Effective Intensity

Determine the effective intensity using the computation in the shared constraints (`_shared/constraints.md`).

## Behavior

### Intensity-Aware Status Display

- At standard intensity: show phase, next step, and time in phase.
- At high intensity: additionally show stale workflow warning when a phase exceeds its expected duration.
- At critical intensity: additionally show token budget warning to alert when context usage is approaching limits.

### 1. Check Setup

First, verify Correctless is set up in this project:
- Does `.correctless/config/workflow-config.json` exist?
- Does `.correctless/hooks/workflow-gate.sh` exist?
- Does `.correctless/ARCHITECTURE.md` exist and not contain `{PROJECT_NAME}` or `{PLACEHOLDER}` template markers? (Note: a minimal .correctless/ARCHITECTURE.md with "This project is in early development" is valid — it means `/csetup` ran on a greenfield project and intentionally deferred architecture docs.)

If not set up: "Correctless isn't configured in this project yet. Run `/csetup` to get started."

### 2. Check Current Workflow State

Run:
```bash
.correctless/hooks/workflow-advance.sh status 2>/dev/null
```

If no active workflow, also run:
```bash
.correctless/hooks/workflow-advance.sh status-all 2>/dev/null
```

### 3. Present Status

**If no active workflow on current branch:**

"No active workflow on `{branch}`. You can:
- Start a new feature: `git checkout -b feature/my-feature` then `/cspec`
- Check other branches: {show status-all output if there are active workflows elsewhere}"

**When displaying the current phase, calculate and show the time spent in this phase.** Read `phase_entered_at` from the state file, compute the duration as `now - phase_entered_at`, and display in human-readable format:
- Under 60 minutes: '{N} minutes' (e.g., '12 minutes')
- 1-24 hours: '{N} hours' (e.g., '2 hours')
- Over 24 hours: '{N} days' (e.g., '1 day')

Format: 'Phase: {phase} ({duration})'

Proactive warnings at thresholds:
- After more than 1 hour in a phase: 'This phase has been active for {duration}. If you are stuck, try re-running the skill for this phase.'
- After more than 24 hours: 'This workflow has been in {phase} for {duration}. The workflow may be stalled — re-run the skill or use `workflow-advance.sh override` if needed.'

**If workflow is active, show a pipeline diagram with the current phase marked.** Use `▶` to indicate the active phase. At standard intensity:

```
  spec → review → [ tdd ] → verify → docs → merge
                     │
               ┌─────┴─────┐
              RED → GREEN → QA
                     │       │
               test audit    │
                     └─ fix ◄┘
```

At high+ intensity, include the extra steps:

```
  spec → model → review → [ tdd ] → verify → arch → docs → audit → merge
                             │
                       ┌─────┴─────┐
                      RED → GREEN → QA
                             │       │
                       test audit    │
                             └─ fix ◄┘
```

Mark the current phase with `▶` and show it in the diagram. For TDD sub-phases (tdd-tests, tdd-impl, tdd-qa), mark the specific position inside the TDD box.

**Then show phase-specific guidance:**

| Phase | Show |
|-------|------|
| `spec` | "Writing the spec. When done, the human approves and you run `/creview` (at standard intensity) or `/creview-spec` (at high+ intensity)." |
| `review` / `review-spec` | "Run `/creview` (at standard intensity) or `/creview-spec` (at high+ intensity) to review the spec. After review and approval, run `/ctdd` to start writing tests." |
| `model` | "Formal modeling phase. Run `/cmodel` to generate the Alloy model." |
| `tdd-tests` | "RED phase — writing tests. Source files are blocked (except stubs with STUB:TDD). When tests exist and fail, advance with `workflow-advance.sh impl`." |
| `tdd-impl` | "GREEN phase — implementing. Make the tests pass. When done, advance with `workflow-advance.sh qa`." |
| `tdd-qa` | "QA review — edits blocked. If issues found: `workflow-advance.sh fix`. If a bug is hard to understand, try `/cdebug`. If clean: `workflow-advance.sh done` (at standard intensity) or `workflow-advance.sh verify-phase` (at high+ intensity)." |
| `tdd-verify` | "Final verification — edits blocked. If checks pass: `workflow-advance.sh done`." |
| `done` | "TDD complete. MANDATORY: run `/cverify` next (it advances the state automatically)." |
| `verified` | "Verification complete. MANDATORY: run `/cdocs` next (it advances the state automatically)." |
| `documented` | "All steps complete. Options: create PR (`gh pr create`), merge locally, keep branch, or discard. After merging: `/cpostmortem` if bugs escape, `/cmetrics` for health, `/caudit` for sweep (at high+ intensity)." |
| `audit` | "Audit in progress. Run `/caudit` to continue the convergence loop." |

### 3a. Harness fingerprint advisory line

After the phase-specific guidance in section 3 and before showing available commands in section 4, emit a single advisory line about the harness fingerprint state. This sits between the workflow state section and the intensity calibration section (per harness-fingerprint spec INV-015).

Read `.correctless/meta/harness-fingerprint.json` if it exists. Compute the short form:

- If the file is missing: `Harness: model=unknown version=? fingerprint=00000000 status=new`
- If present and valid JSON: `Harness: model={X} version={Y} fingerprint={hash[:8]} status=ok`
- If `status=version_bumped` was reported by the most recent `harness-fingerprint.sh check` (read from `.correctless/artifacts/harness-notified-*.flag` presence in current session): `Harness: model={X} version={Y} fingerprint={hash[:8]} status=version-bumped`

The format is fixed: `Harness: model=\S+ version=\d+ fingerprint=[0-9a-f]{8} status=(ok|new|version-bumped)`. The `fingerprint` short form is the first 8 hex characters of `sha256(fingerprint)` for compact display only — the literal fingerprint stored in the meta file is `{model_name}|{HARNESS_VERSION}` without hashing (INV-001).

This line is advisory — never block, never error. If the file is malformed or unreadable, emit `Harness: model=unknown version=? fingerprint=00000000 status=ok` and continue silently.

### 4. Show Available Commands

Based on the current state:

```
Available commands:
  /cspec          Start a new feature spec
  /creview        Skeptical spec review
  /ctdd           Enforced TDD workflow
  /cverify        Post-implementation verification
  /cdocs          Update documentation
  /cstatus        This command — show status and next steps
  /csummary       Feature summary — what the workflow caught
  /cmetrics       Project-wide metrics dashboard
  /crefactor      Structured refactoring with behavioral equivalence
  /cpr-review     Multi-lens PR review
  /ccontribute    Contribute to an open source project
  /cmaintain      Maintainer review for incoming contributions
  /cdebug         Structured bug investigation
  /csetup         Re-run setup / validate configuration
  /chelp          Quick help — workflow pipeline and commands
  /cwtf           Workflow accountability — did agents do their job?
  /cquick         Lightweight TDD — quick-start without full spec
  /crelease       Versioning and changelog management
  /cexplain       Guided codebase exploration
  /cauto          Semi-auto pipeline — orchestrates ctdd through PR
  /cmodelupgrade  Harness regression report (after model upgrade or version_bumped advisory)
  /carchitect     Architecture definition — reverse-engineer or greenfield
  /cdashboard     HTML project dashboard — metrics + artifact browser
  /ctriage        Bulk triage deferred findings backlog
  /cprune         Documentation and artifact pruning

State management:
  .correctless/hooks/workflow-advance.sh status      Current phase
  .correctless/hooks/workflow-advance.sh status-all   All active workflows
  .correctless/hooks/workflow-advance.sh diagnose "file"   Why a file is blocked
  .correctless/hooks/workflow-advance.sh override "reason"  Temporarily bypass gate
```

Read `.correctless/config/workflow-config.json`. If `workflow.intensity` is set to high+ or above, also highlight intensity-gated commands: `/cmodel`, `/creview-spec`, `/caudit`, `/cupdate-arch`, `/cpostmortem`, `/cdevadv`, `/credteam`

### 5. Install Freshness

Check install freshness and display as a single status line:

```bash
source .correctless/scripts/lib.sh
output="$(check_install_freshness "$(pwd)/.correctless" 2>/dev/null)"
```

Parse the output and display one line:
- If all lines are `ok:*`: **"Install: current"**
- If any line is `source_ahead:*`: **"Install: STALE — {N} source files changed since last setup (run setup)"** where N is the count of `source_ahead` lines.
- If any line is `modified:*` or `missing:*` (without `source_ahead`): **"Install: STALE ({N} files differ — run setup)"** where N is the count of `modified` + `missing` lines.
- If output is `no_manifest`: **"Install: unknown (no manifest — run setup)"**

This is a single line in the status output, not a separate section.

### 6. Detect Problems

After showing phase and commands, proactively check for issues:

**Stale workflow**: If >24 hours in a phase, this is already handled by the time-in-phase display in section 3 above — do not repeat the warning here. Only check for stale workflows if section 3 did not already display a >24h warning (e.g., if phase_entered_at was missing or unparsable).

**Empty docs**: Check if .correctless/ARCHITECTURE.md contains `{PROJECT_NAME}` or `{PLACEHOLDER}` markers, or if .correctless/AGENT_CONTEXT.md contains `{PROJECT_NAME}` or `{PLACEHOLDERS}`. If either is still the template: ".correctless/ARCHITECTURE.md / .correctless/AGENT_CONTEXT.md is still the default template. Run `/csetup` to populate it from your codebase — this significantly improves spec and review quality."

**Override usage**: Read `override_count` from the state file. If ≥2: "You've used {N} overrides on this workflow. If the gate keeps blocking legitimate edits, the workflow config or file patterns may need adjustment. Run `workflow-advance.sh diagnose 'yourfile.ts'` to understand why."

**Measurement-overdue check (path-scoped-rules-pat001 dogfood, INV-016 / MG-003)**: If `.correctless/meta/pat001-measurement-due.json` exists, inspect it:

1. Read `due_at_pr_count` (an integer, typically 3) and `created_at_commit` (a commit SHA or null).
2. If `created_at_commit` is null, the feature has merged but the measurement baseline commit was never recorded — emit a one-line advisory: "pat001-measurement-due.json exists but `created_at_commit` is null; /cdocs or /cverify should fill it at merge time." Then stop this check.
3. Otherwise, count hook-touching merged PRs since `created_at_commit`. A hook-touching PR is any PR whose merge commit modifies a file under `hooks/*.sh`. Use: `git log --merges --name-only "$created_at_commit"..HEAD -- 'hooks/*.sh' | grep -c '^hooks/' || true` — adapt if the local git log shape is different.
4. If the hook-touching PR count is `>= due_at_pr_count` AND `.correctless/verification/path-scoped-rules-pat001-measurement.md` does NOT exist, emit a warning banner (prominently, above the standard status block):

   > WARNING — Measurement overdue: path-scoped-rules-pat001 — run measurement gate per MG-003 or roll back per PRH-002.

   Include a one-line pointer: "See `.correctless/specs/path-scoped-rules-pat001.md` MG-003 for the procedure, and PRH-002 for the rollback steps."
5. If the measurement report already exists at `.correctless/verification/path-scoped-rules-pat001-measurement.md`, suppress the warning — the gate has been evaluated.
6. If the meta file is missing, this check is a no-op. Do not create it.

This check is dormant by design: it fires only when the post-merge measurement window has elapsed and the human has not yet run the gate. It is the only merge-time-enforceable signal for MG-003 (the measurement gate is evaluated post-merge via git archaeology, not at PR time).

**No active workflow**: "No active workflow on this branch. You can edit freely — the gate only blocks during active workflows. To start a structured workflow: `git checkout -b feature/my-feature` then `/cspec`."

### 6a. Incomplete Pipeline Detection (R-009)

Check for a pipeline manifest at `.correctless/artifacts/pipeline-manifest-{branch_slug}.json` (derive `branch_slug` via `workflow-advance.sh status` output or `scripts/lib.sh`). If the manifest exists and `status` is not `"complete"`, report:

> **Incomplete pipeline detected.** Last completed step: {last_completed}. Missing steps: {list}. Expected end phase: {expected_end_phase}, current phase: {current_phase}. Run `/cauto` to resume.

If the manifest does not exist or `status` is `"complete"`, produce no output for this section (dormant — PAT-019).

The workflow state is authoritative — the manifest report is a diagnostic signal, not an override of workflow state.

### 6b. Deferred Findings Backlog

Read `.correctless/meta/deferred-findings.json` if it exists. Show the following:

- **Total open findings count** and **severity breakdown** (MEDIUM/LOW/ADVISORY counts)
- When open findings exceed 20: "Consider running `/ctriage` to review the deferred findings backlog."

**When the file does not exist or has zero open findings, omit this section entirely** (dormant per PAT-019 — no "0 findings" noise).

**Drift detection**: If review artifacts (`.correctless/artifacts/review-spec-findings-*.md` or `.correctless/artifacts/review-findings-*.md` or `.correctless/artifacts/reviews/review-findings-*.md`) contain "pending" findings not present in the backlog, suggest: "Review artifacts contain pending findings not in the backlog. Run `bash scripts/sync-deferred-backlog.sh` to re-sync."

### 6c. Cross-Feature Intelligence Health

Check the state of the cross-feature intelligence brief and its data sources. Three states:

1. **No data**: When `.correctless/meta/cross-feature-intel.json` does not exist AND no data sources have content (no deferred findings, no devadv reports, no overrides, no lens recommendations, no debug investigations, no workflow effectiveness data), display: "No cross-feature intelligence available yet — data accumulates as features complete review, audit, or debug phases."

2. **Stale**: When the brief exists but is older than 7 days (based on file mtime), display brief age, entry count per section, and remediation: "Cross-feature intelligence brief is {N} days old. Will refresh on next /cspec run, or run: bash .correctless/scripts/cross-feature-intel.sh"

3. **Current**: When the brief exists and is less than 7 days old, display brief age and entry count per section.

**Threshold proximity reporting**: When the brief exists (states 2 or 3), report threshold proximity for entries — the occurrence-level breakdown showing how many entries are at each count below the threshold. For example: "5 entries at 2/3 occurrences, 3 entries at 1/3, 2 entries above threshold." This provides diagnostic visibility for users investigating why intelligence is not surfacing in reviews. Read occurrence counts via `jq '[.sections | to_entries[] | .value[] | .occurrences // 0]' .correctless/meta/cross-feature-intel.json`.

**Dormant when the script itself (`scripts/cross-feature-intel.sh` or `.correctless/scripts/cross-feature-intel.sh`) does not exist** — pre-upgrade projects should see no intelligence health output (PAT-019). When the script does not exist, omit this section entirely.

### 7. Health Check (if requested)

If the human asks "is everything set up correctly?" or similar, validate:
- Hooks registered in `.claude/settings.json`
- Config file valid JSON with required fields
- Hook scripts exist and are executable at `.correctless/hooks/`
- .correctless/ARCHITECTURE.md has content (not template)
- .correctless/AGENT_CONTEXT.md has content (not template)

Report any issues with fix instructions.

## Pruning Recommended Signal (INV-013)

Run a lightweight staleness check using `scripts/prune-scan.sh` (or `.correctless/scripts/prune-scan.sh`). If the scanner script does not exist (file does not exist at either path), this section is dormant per PAT-019 — no error, no warning, no output.

When the scanner is available, check two categories:
1. Orphaned artifacts: `bash scripts/prune-scan.sh --category artifacts --base .` — count results
2. Architecture staleness: `bash scripts/prune-scan.sh --category architecture --base .` — count results

Surface the signal when either: (a) more than 10 orphaned artifact files exist, or (b) more than 3 architecture entries have all-dead file references.

Signal text: "Pruning recommended: {N} orphaned artifacts, {M} stale architecture entries. Run `/cprune` to clean up."

## Autonomous Defaults

- **AD-001**: Display scope — show full pipeline status with next steps (default). No human input required; this skill runs to completion autonomously.

## If Something Goes Wrong

- `/cstatus` is read-only — it reads workflow state and project files but modifies nothing. Re-run anytime safely.
- If status looks wrong, check that `.correctless/config/workflow-config.json` exists and the hook scripts are installed at `.correctless/hooks/`.

## Constraints

- **Keep it short.** Status should be a quick glance, not a wall of text.
- **Always suggest the next action.** Don't just show state — tell them what to do.
- **Don't modify anything.** This is read-only.
