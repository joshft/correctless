
## Correctless

This project uses Correctless for structured development.
Read .correctless/AGENT_CONTEXT.md before starting any work.
Available commands: /csetup, /cspec, /creview, /cmodel, /creview-spec, /ctdd, /cverify, /caudit, /cupdate-arch, /cdocs, /cpostmortem, /cdevadv, /credteam, /crefactor, /cpr-review, /ccontribute, /cmaintain, /cstatus, /csummary, /cmetrics, /cdebug, /chelp, /cwtf, /cquick, /crelease, /cexplain, /cauto, /carchitect

## GitHub Operations

Use `gh` for GitHub operations (PRs, issues, checks).

## Commit Messages

Imperative mood, capitalized, no conventional commits prefix. Explain *why* when non-obvious.
Examples: "Add mermaid diagrams to README for visual comprehension", "Fix shellcheck directive placement — must be before first statement"

## Script Comments

When writing bash scripts, make section headers visually distinct from inline comments.

**For saved scripts** — use banner comments so the human can scan the flow:
```bash
# ============================================
# STEP 1: Backup current state before migration
# ============================================
cp -r src/auth src/auth.bak
git stash

# ============================================
# STEP 2: Run schema migration
# ============================================
cd packages/api && npx prisma migrate deploy

# skip if no pending migrations
if [ $? -eq 0 ]; then
  echo "Migration complete"
fi
```

**For interactive scripts** — use echo prefixes so the terminal output is the summary:
```bash
echo ">>> Step 1: Backup current state before migration"
cp -r src/auth src/auth.bak
git stash

echo ">>> Step 2: Run schema migration"
cd packages/api && npx prisma migrate deploy
```

Banner comments for scripts reviewed as files. Echo prefixes for scripts watched in real time. Inline `#` comments stay normal — only section headers get the visual treatment.

## Post-Merge Routine

After a PR is merged on GitHub, run this sequence to sync local state:

```bash
git checkout main
git fetch --prune
git reset --hard origin/main
git branch -d <merged-branch>        # delete local branch
```

GitHub squash-merges PRs, so the local branch history will diverge from main. `reset --hard origin/main` is safe here because the PR was just merged — origin/main has everything. Do not attempt `git pull --rebase` after a squash merge; it creates conflicts with the pre-squash commits.

## Correctless Learnings

### 2026-04-02 — Convention confirmed: Serena MCP silent fallback
- Observed in 5+ features — treat as established project convention
- Every skill with Serena integration must: (1) check `mcp.serena` config flag, (2) include the standard 6-tool fallback table, (3) state "optimizer, not a dependency", (4) fall back silently (no abort, no retry, no mid-operation warnings), (5) notify once at session end if unavailable
- Source: /cdocs after add-cexplain-skill-for-guided-codebase-exploration

### 2026-04-05 — Convention confirmed: PreToolUse hook structure
- Observed in 3 features (workflow-gate.sh, sensitive-file-guard.sh, auto-format.sh uses PostToolUse variant) — treat as established project convention
- Every PreToolUse hook must: (1) `set -euo pipefail` + `set -f`, (2) check `command -v jq` with fail-closed exit 2, (3) bulk-parse stdin with single `eval` + `jq -r @sh`, (4) fast-path `exit 0` for non-relevant tools BEFORE loading config, (5) exit 0 to allow, exit 2 to block. See `.claude/rules/hooks-pretooluse.md`.
- Source: /cdocs after sensitive-file-protection

### 2026-04-07 — Convention confirmed: PostToolUse hook structure (PAT-005)
- Observed in 3 features (audit-trail.sh, auto-format.sh, token-tracking.sh) — treat as established project convention
- Every PostToolUse hook must: (1) NO `set -euo pipefail` (fail-open, not fail-closed), (2) `command -v jq` with `exit 0` if missing (NOT exit 2), (3) bulk-parse stdin with `eval` + `jq -r @sh`, (4) fast-path `exit 0` for non-relevant tools BEFORE any I/O, (5) guard each operation with `|| exit 0`, (6) ALWAYS exit 0 — advisory, never gating. Contrast with PAT-001 (PreToolUse: fail-closed, exit 2 to block — See `.claude/rules/hooks-pretooluse.md`).
- Source: /cdocs after token-tracking

### 2026-04-05 — Audit pattern: Hook allowlist/extension drift (RESOLVED)
- **Structurally resolved** by feature/hook-sync-enforcement (2026-04-08): `_has_write_pattern()` and `get_target_file()` extracted into scripts/lib.sh (ABS-001). All consuming hooks source the shared functions — drift is structurally impossible.
- Original issue: write-command lists and file extension regexes duplicated across workflow-gate.sh, sensitive-file-guard.sh, and audit-trail.sh. Caught by 3 consecutive audits.
- Source: /caudit qa, resolved by /cdocs after hook-sync-enforcement

### 2026-04-10 — Postmortem: jq 1.7 vs 1.8 operator precedence for `as` bindings
- jq 1.8 silently fixed `(EXPR // 0) + 1 as $count | rest` precedence; jq 1.7 still parses it as `0 + (1 as $count | rest)` and fails at runtime. Local dev (jq 1.8) passes, CI (Ubuntu 24.04, jq 1.7) fails. When writing jq filters, always wrap the expression being bound in explicit parens: `((EXPR OP VAL)) as $var | rest`. See PAT-010 in .correctless/ARCHITECTURE.md and AP-011 in antipatterns.md. Fix: CI matrix across jq versions.
- Source: PMB-001

### 2026-04-10 — Postmortem: Audit fix rounds are untested code
- QA Olympics audit ran 3 rounds where each round introduced at least one regression that the next round had to catch. Fix commits bypass the TDD discipline of the main workflow — they're batched into one commit per round without test suite verification or diff-focused review. The convergence loop works eventually but wastes rounds. Class fix: /caudit must run the full test suite and spawn a fix-diff review agent after each fix round commit, before advancing. See AP-012.
- Source: PMB-002

### 2026-04-10 — Convention introduced: rules-canonical / ARCHITECTURE.md index
- **Provisional convention under measurement.** First dogfood prototype: PAT-001 was migrated from its full-body form in the architecture doc to a path-scoped rule file at `.claude/rules/hooks-pretooluse.md`.
- Post-migration, `.correctless/ARCHITECTURE.md` contains only a 2-line index entry (heading + See-link) for the migrated pattern. The rule body loads into agent context when Claude Code opens `hooks/workflow-gate.sh` or `hooks/sensitive-file-guard.sh`.
- **Why**: duplication invites drift (AP-005 has recurred repeatedly); a single canonical location enforced by a structural drift test (`tests/test-architecture-drift.sh`) makes drift structurally impossible rather than merely unlikely. The migration is also a prevention bet — the rule body is now loaded into editing context for the exact files it governs, which should reduce the persistence window of fail-closed violations observed in the ≥7-PR baseline (QA-R1-004/005).
- **Measurement gate**: this is an experiment, not a settled convention. The gate (MG-001 prevention signal + MG-002 safety-net persistence ceiling) evaluates after 3 hook-touching PRs via `.correctless/meta/pat001-measurement-due.json` and the dormant `/cstatus` check. If the gate fails, execute PRH-002 rollback (restore full PAT-001 body to ARCHITECTURE.md, delete rule file, revert CLAUDE.md/README changes, drop ABS-009/ENV-005/ENV-006, remove this learning entry) — leaving `tests/test-architecture-drift.sh` in place as inert infrastructure for a future retry.
- **Scope discipline**: only PAT-001 was migrated in this feature. PAT-002..PAT-010 remain full-body in ARCHITECTURE.md (PRH-004). New PAT entries default to ARCHITECTURE.md full-body form until the measurement gate passes (see OQ-005 in the spec). Future PAT migrations (PAT-005 is the next candidate) reuse the drift test verbatim under FUTURE-002. The `InstructionsLoaded` hook that would give MG-001 a direct runtime signal is Feature B (FUTURE-001), deferred.
- Source: /cspec after path-scoped-rules-pat001

### 2026-04-11 — Postmortem: Plugin-agent tool allowlist + strict JSON parse gate are load-bearing together
- Observed during VP-001/VP-002 for fix-diff-reviewer-migration. A simulation run of the fix-diff reviewer via `Task(subagent_type="general-purpose")` — same system prompt, same fixtures — produced prose-wrapped JSON on r1 ("Key observations: ... [JSON array]"). A real `/caudit` invocation would have hit `jq -e .` parse failure and triggered PRH-003 fail-closed. The real plugin agent invoked via `Task(subagent_type="correctless:fix-diff-reviewer")` — same system prompt but with tools pinned to `{Read, Grep, Glob}` — produced pure JSON across all three fixture replays.
- **Inference**: INV-017 (`jq -e .` parse gate) and PRH-002 (pinned tool allowlist) are load-bearing *together*, not independently. A reviewer with a broad tool set is more likely to "explain" its findings in prose because the broader tool surface invites more elaborate reasoning patterns; a reviewer with Read/Grep/Glob only stays inside its narrow output contract.
- **Design implication for future plugin agents**: narrow tool allowlist is part of the output-contract enforcement story, not just a security/least-privilege concern. When writing a new plugin agent in `agents/*.md`, the tool pinning is doing two jobs — it limits blast radius AND it shapes the agent's response style toward the pinned contract. Don't broaden the allowlist just for convenience.
- Source: /cdocs after fix-diff-reviewer-migration (evidence in `.correctless/verification/fix-diff-reviewer-migration-replay-simulation.md`)
