#!/usr/bin/env bash
# HOOK_TYPE: PostToolUse
# HOOK_MATCHER: Agent
# Correctless — PostToolUse hook for Agent tool token tracking
# Appends one JSONL entry per Agent completion to token-log-{branch-slug}.jsonl
#
# PAT-005 PostToolUse conventions (NOT PAT-001 PreToolUse):
#   - No strict error modes (would abort on any failure, violating fail-open)
#   - Dependency check exits 0 if missing (fail-open, NOT exit 2)
#   - Every operation guarded with || exit 0 or || true
#   - Must ALWAYS exit 0
#
# TB-003: tool_response.result is NEVER extracted or processed.
#   The .result field contains arbitrary LLM-generated text that could include
#   shell metacharacters. Extracting it would enable prompt injection attacks.
#   Only structured numeric/metadata fields are extracted from tool_response.
#   No variable named result or RESULT is declared anywhere in this hook.
#
# tool_input.description is extracted via @sh safe quoting. The risk is
# lower than .result because: (1) it is a short controlled-length field authored
# by the orchestrator, not arbitrary subagent output, (2) @sh produces
# POSIX-quoted strings that neutralize shell metacharacters.

# ============================================
# Parse stdin JSON (single jq bulk call)
# ============================================

INPUT="$(cat)" || exit 0

# Fail-open: jq required for JSON parsing (PAT-005: PostToolUse exits 0, never blocks)
command -v jq >/dev/null 2>&1 || exit 0; eval "$(echo "$INPUT" | jq -r '
  @sh "TOOL_NAME=\(.tool_name // "")",
  @sh "INPUT_TOKENS=\(.tool_response.usage.input_tokens // 0)",
  @sh "OUTPUT_TOKENS=\(.tool_response.usage.output_tokens // 0)",
  @sh "TOTAL_COST_USD=\(.tool_response.total_cost_usd // 0)",
  @sh "DURATION_MS=\(.tool_response.duration_ms // 0)",
  @sh "AGENT_DESCRIPTION=\(.tool_input.description // "")",
  @sh "AGENT_TYPE=\(.tool_input.subagent_type // "")"
' 2>/dev/null)" || exit 0

# ============================================
# Fast-path: only process Agent tool (R-001)
# ============================================

[ "$TOOL_NAME" = "Agent" ] || exit 0

# ============================================
# Source lib.sh for branch_slug (R-011 / ABS-001)
# ============================================

_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" 2>/dev/null && pwd || true)"
if [ -n "$_LIB_DIR" ] && [ -f "$_LIB_DIR/lib.sh" ]; then
  source "$_LIB_DIR/lib.sh" || exit 0
elif [ -f ".correctless/scripts/lib.sh" ]; then
  source ".correctless/scripts/lib.sh" || exit 0
else
  exit 0
fi
unset _LIB_DIR

# ============================================
# Compute paths using branch_slug
# ============================================

_slug="$(branch_slug 2>/dev/null)" || exit 0
[ -n "$_slug" ] || exit 0
_artifacts="$(artifacts_dir 2>/dev/null)" || exit 0
[ -n "$_artifacts" ] || exit 0
STATE_FILE="${_artifacts}/workflow-state-${_slug}.json"
TOKEN_LOG="${_artifacts}/token-log-${_slug}.jsonl"

# ============================================
# Timestamp (ISO 8601)
# ============================================

TIMESTAMP="$(date -u +%FT%TZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)" || true

# ============================================
# Read state file and extract phase for skill mapping
# ============================================

_STATE_CONTENT="$(cat "$STATE_FILE" 2>/dev/null || echo '{}')" || _STATE_CONTENT='{}'

# Extract phase without an additional jq call (keeps total at 2 per R-007).
# Uses bash builtins on our own well-formed state JSON. Falls back to "none".
_PHASE="none"
[[ "$_STATE_CONTENT" =~ \"phase\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]] && _PHASE="${BASH_REMATCH[1]}" || true

# ============================================
# Phase-to-skill mapping (R-001, R-003)
# Hook-private: not in lib.sh per ABS-001 single-consumer exception.
# ============================================

case "$_PHASE" in
  spec)                                          SKILL_VAL="cspec"    ;;
  model)                                         SKILL_VAL="cmodel"   ;;
  review|review-spec)                            SKILL_VAL="creview"  ;;
  tdd-tests|tdd-impl|tdd-qa|tdd-verify|tdd-audit)  SKILL_VAL="ctdd"    ;;
  done|verified)                                 SKILL_VAL="cverify"  ;;
  documented)                                    SKILL_VAL="cdocs"    ;;
  audit)                                         SKILL_VAL="caudit"   ;;
  *)                                             SKILL_VAL="unknown"  ;;
esac

# ============================================
# Append JSONL entry (R-005)
# ============================================

mkdir -p "$_artifacts" 2>/dev/null || exit 0

# Construct JSONL entry with skill field (R-002: passed via --arg)
echo "$_STATE_CONTENT" | jq -c \
  --arg ts "$TIMESTAMP" \
  --arg branch "$_slug" \
  --arg skill "$SKILL_VAL" \
  --arg desc "$AGENT_DESCRIPTION" \
  --arg type "$AGENT_TYPE" \
  --argjson in "$INPUT_TOKENS" \
  --argjson out "$OUTPUT_TOKENS" \
  --argjson cost "$TOTAL_COST_USD" \
  --argjson dur "$DURATION_MS" \
  '{
    timestamp: $ts,
    branch: $branch,
    phase: (.phase // "none"),
    feature: (.task // "unknown"),
    skill: $skill,
    agent_description: $desc,
    agent_type: $type,
    input_tokens: $in,
    output_tokens: $out,
    total_tokens: ($in + $out),
    total_cost_usd: $cost,
    duration_ms: $dur
  }' >> "$TOKEN_LOG" 2>/dev/null || exit 0

exit 0
