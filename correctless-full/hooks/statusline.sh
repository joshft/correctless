#!/usr/bin/env bash
# Correctless — workflow-aware statusline for Claude Code
# Shows: directory, branch, model, context %, workflow phase, QA rounds, cost, lines delta
# Designed to be fast (<50ms) — one jq call on a tiny state file

input=$(cat)

# Colors
ORANGE='\033[38;5;214m'
GRAY='\033[2m'
RED='\033[31m'
GREEN='\x1b[38;5;42m'
YELLOW='\x1b[38;5;226m'
CYAN='\x1b[38;5;81m'
NC='\033[0m'

# Icons
GIT=''

# --- Standard info (same as default statusline) ---

DIR="$(echo "$input" | jq -r '.workspace.current_dir')"
MODEL="$(echo "$input" | jq -r '.model.display_name')"
STYLE="$(echo "$input" | jq -r '.output_style.name')"
USAGE="$(echo "$input" | jq '.context_window.current_usage')"
CONTEXT_SIZE="$(echo "$input" | jq -r '.context_window.context_window_size')"
COST="$(echo "$input" | jq -r '.cost.total_cost_usd')"
LINES_ADD="$(echo "$input" | jq -r '.cost.total_lines_added')"
LINES_REM="$(echo "$input" | jq -r '.cost.total_lines_removed')"

# Context window
ctx=''
PERCENT_USED=0
if [ "$USAGE" != "null" ]; then
  CURRENT_TOKENS=$(echo "$USAGE" | jq '.input_tokens + .cache_creation_input_tokens + .cache_read_input_tokens')
  PERCENT_USED=$((CURRENT_TOKENS * 100 / CONTEXT_SIZE))
  if [ "$PERCENT_USED" -lt 40 ]; then
    ctx=$(printf "${GREEN}%d%%${NC}" "$PERCENT_USED")
  elif [ "$PERCENT_USED" -lt 70 ]; then
    ctx=$(printf "${YELLOW}%d%%${NC}" "$PERCENT_USED")
  else
    ctx=$(printf "${RED}%d%%${NC}" "$PERCENT_USED")
  fi
fi

# Git branch
cd "$DIR" 2>/dev/null || true
branch=$(git --no-optional-locks rev-parse --abbrev-ref HEAD 2>/dev/null)

# --- Workflow state (Correctless-specific) ---

workflow=''
if [ -n "$branch" ] && [ -d ".claude/artifacts" ]; then
  # Compute branch slug (same algorithm as workflow-gate.sh)
  slug="$(echo "$branch" | sed 's/[^a-zA-Z0-9]/-/g' | cut -c1-80)"
  hash="$(printf '%s' "$branch" | (md5sum 2>/dev/null || md5) | cut -c1-6)"
  STATE_FILE=".claude/artifacts/workflow-state-${slug}-${hash}.json"

  if [ -f "$STATE_FILE" ]; then
    PHASE="$(jq -r '.phase // empty' "$STATE_FILE" 2>/dev/null)"
    QA_ROUNDS="$(jq -r '.qa_rounds // 0' "$STATE_FILE" 2>/dev/null)"

    if [ -n "$PHASE" ]; then
      # Color-code the phase
      case "$PHASE" in
        spec|review|review-spec|model)
          workflow=$(printf "${CYAN}%s${NC}" "$PHASE") ;;
        tdd-tests)
          workflow=$(printf "${RED}RED${NC}") ;;
        tdd-impl)
          workflow=$(printf "${GREEN}GREEN${NC}") ;;
        tdd-qa)
          workflow=$(printf "${YELLOW}QA${NC}") ;;
        tdd-verify)
          workflow=$(printf "${YELLOW}VERIFY${NC}") ;;
        done|verified|documented)
          workflow=$(printf "${GRAY}%s${NC}" "$PHASE") ;;
        audit)
          workflow=$(printf "${ORANGE}AUDIT${NC}") ;;
        *)
          workflow=$(printf "${GRAY}%s${NC}" "$PHASE") ;;
      esac

      # Add QA round count if in TDD phases
      if [ "$QA_ROUNDS" != "0" ] && [ "$QA_ROUNDS" != "null" ]; then
        workflow="${workflow}$(printf "${GRAY}:R%s${NC}" "$QA_ROUNDS")"
      fi
    fi
  fi
fi

# --- Assemble output ---

output=""

# Directory
output+="$(basename "$DIR")/"

# Git branch
if [ -n "$branch" ]; then
  output+=$(printf " ${GRAY}%s${NC}" "${GIT}$branch")
fi

# Model
output+=$(printf " ${ORANGE}%s${NC}" "$MODEL")

# Output style (if not default)
if [ "$STYLE" != "null" ] && [ "$STYLE" != "default" ]; then
  output+=$(printf " ${GRAY}[%s]${NC}" "$STYLE")
fi

# Context %
if [ -n "$ctx" ]; then
  output+=$(printf " %s" "$ctx")
fi

# Workflow phase
if [ -n "$workflow" ]; then
  output+=$(printf " %s" "$workflow")
fi

# Cost
if [ "$COST" != "null" ] && [ "$COST" != "0" ]; then
  output+=$(printf " ${GRAY}\$%s${NC}" "$COST")
fi

# Lines delta
if [ "$LINES_ADD" != "null" ] && [ "$LINES_REM" != "null" ]; then
  if [ "${LINES_ADD:-0}" != "0" ] || [ "${LINES_REM:-0}" != "0" ]; then
    output+=$(printf " ${GREEN}+%s${NC}${RED}/-%s${NC}" "${LINES_ADD}" "${LINES_REM}")
  fi
fi

echo "$output"
