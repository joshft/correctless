#!/usr/bin/env bash
# Correctless — PostToolUse audit trail
# Records every file modification with workflow phase context.
# MUST be fast (<100ms). Capture and append, nothing else.
# Consumed by: /csummary, /cmetrics, future /cwtf

# Fast-path bail: if no .claude/artifacts/ directory, exit immediately.
# This is the most common case (no Correctless project) and costs ~0ms.
[ -d ".claude/artifacts" ] || exit 0

# Read input
INPUT="$(cat)"
TOOL_NAME="$(echo "$INPUT" | jq -r '.tool_name // empty')"

# Fast-path bail: no tool name = malformed input
[ -n "$TOOL_NAME" ] || exit 0

# Extract target file(s) — MultiEdit may have multiple
FILES=""
case "$TOOL_NAME" in
  Bash)
    FILES="$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null | grep -oE '[^ ]+\.(go|ts|tsx|js|jsx|py|rs|java|rb|cpp|c|h)' | head -1)" || true
    ;;
  MultiEdit)
    FILES="$(echo "$INPUT" | jq -r '.tool_input.edits[]?.file_path // empty' 2>/dev/null)"
    ;;
  *)
    FILES="$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)"
    ;;
esac

# Compute branch slug and find state file
branch="$(git --no-optional-locks branch --show-current 2>/dev/null)" || exit 0
[ -n "$branch" ] || exit 0

slug="$(echo "$branch" | sed 's/[^a-zA-Z0-9]/-/g' | cut -c1-80)"
hash="$(printf '%s' "$branch" | (md5sum 2>/dev/null || md5) | cut -c1-6)"
STATE_FILE=".claude/artifacts/workflow-state-${slug}-${hash}.json"

# Fast-path bail: no state file = no active workflow = nothing to audit
[ -f "$STATE_FILE" ] || exit 0

# Read phase from state file
PHASE="$(jq -r '.phase // "unknown"' "$STATE_FILE" 2>/dev/null)"

# Append to audit trail (JSONL — one line per entry, append-only)
TRAIL=".claude/artifacts/audit-trail-${slug}-${hash}.jsonl"
TS="$(date -u +%FT%TZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)"

# Write one entry per file (MultiEdit may have multiple). Use jq for safe JSON encoding.
echo "$FILES" | while IFS= read -r f; do
  [ -z "$f" ] && continue
  jq -nc --arg ts "$TS" --arg phase "$PHASE" --arg tool "$TOOL_NAME" --arg file "$f" --arg branch "$branch" \
    '{ts:$ts,phase:$phase,tool:$tool,file:$file,branch:$branch}' >> "$TRAIL" 2>/dev/null
done

# Never fail — audit trail errors must not slow down the workflow
exit 0
