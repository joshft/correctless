
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
