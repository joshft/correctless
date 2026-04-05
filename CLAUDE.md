
## Correctless Lite

This project uses Correctless Lite for structured development.
Read .correctless/AGENT_CONTEXT.md before starting any work.
Available commands: /csetup, /cspec, /creview, /ctdd, /cverify, /cdocs, /crefactor, /cpr-review, /cstatus, /csummary, /cmetrics, /cdebug, /chelp

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
- Every PreToolUse hook must: (1) `set -euo pipefail` + `set -f`, (2) check `command -v jq` with fail-closed exit 2, (3) bulk-parse stdin with single `eval` + `jq -r @sh`, (4) fast-path `exit 0` for non-relevant tools BEFORE loading config, (5) exit 0 to allow, exit 2 to block. See PAT-001 in .correctless/ARCHITECTURE.md.
- Source: /cdocs after sensitive-file-protection

### 2026-04-05 — Audit pattern: Hook allowlist/extension drift
- Recurs across 3 audit runs (QA 2026-04-03, Hacker 2026-04-04, QA 2026-04-05) — always check all hooks when adding commands or extensions to any one hook
- Write-command lists (_has_write_pattern), file extension regexes (get_target_file), and case normalization must stay synchronized across workflow-gate.sh, sensitive-file-guard.sh, and audit-trail.sh
- Source: /caudit qa
