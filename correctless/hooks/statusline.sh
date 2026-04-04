#!/usr/bin/env bash
# Correctless — workflow-aware statusline for Claude Code
# 4 sections separated by ' │ ':
#   1. Repo state: {dir}/ {branch} {N dirty}
#   2. Model/context/tokens: {model} {N%} {in} : {out} (in:out)
#   3. Session stats: {duration} ${cost} +N/-N
#   4. Workflow: ⚙ {task} · {PHASE} R{n} · {time} {warnings}
# Designed to be fast (<50ms) — bulk jq calls minimize process spawns

input=$(cat)

# Colors (all use \033 format for source consistency)
ORANGE='\033[38;5;214m'
GRAY='\033[2m'
RED='\033[31m'
GREEN='\033[38;5;42m'
YELLOW='\033[38;5;226m'
CYAN='\033[38;5;81m'
NC='\033[0m'

# --- Parse all JSON fields in a single jq call ---

eval "$(echo "$input" | jq -r '
  @sh "DIR=\(.workspace.current_dir)",
  @sh "MODEL=\(.model.display_name)",
  @sh "STYLE=\(.output_style.name)",
  @sh "CONTEXT_SIZE=\(.context_window.context_window_size)",
  @sh "CURRENT_TOKENS=\(
    if .context_window.current_usage != null then
      (.context_window.current_usage |
        (.input_tokens // 0) + (.cache_creation_input_tokens // 0) + (.cache_read_input_tokens // 0))
    else null end
  )",
  @sh "COST=\(.cost.total_cost_usd)",
  @sh "LINES_ADD=\(.cost.total_lines_added)",
  @sh "LINES_REM=\(.cost.total_lines_removed)",
  @sh "TOTAL_IN=\(.context_window.total_input_tokens)",
  @sh "TOTAL_OUT=\(.context_window.total_output_tokens)",
  @sh "DURATION_MS=\(.total_duration_ms)"
' 2>/dev/null)"

# --- Helper: format token count ---
# <1000 → integer, 1000-999999 → N.Nk, 1000000+ → N.NM
fmt_tokens() {
  local n="$1"
  [[ "$n" =~ ^[0-9]+$ ]] || { echo "$n"; return; }
  if [ "$n" -lt 1000 ]; then
    echo "$n"
  elif [ "$n" -lt 1000000 ]; then
    # N.Nk — truncate to 1 decimal (not round) to avoid 999999→1000.0k
    awk "BEGIN { v = int($n / 100) / 10; printf \"%.1fk\", v }"
  else
    awk "BEGIN { v = int($n / 100000) / 10; printf \"%.1fM\", v }"
  fi
}

# --- Helper: format duration ms → Nm or Nh Nm ---
fmt_duration() {
  local ms="$1"
  [[ "$ms" =~ ^[0-9]+$ ]] || { echo ""; return; }
  local total_min=$(( ms / 60000 ))
  if [ "$total_min" -lt 60 ]; then
    echo "${total_min}m"
  else
    local h=$(( total_min / 60 ))
    local m=$(( total_min % 60 ))
    echo "${h}h ${m}m"
  fi
}

# --- Section 1: Repo state ---

sec1=""

# QA-009: Guard against null or missing workspace.current_dir
if [ -z "$DIR" ] || [ "$DIR" = "null" ]; then
  branch=""
else

sec1+="$(basename "$DIR")/"

# Git branch
cd "$DIR" 2>/dev/null || true
branch=$(git --no-optional-locks rev-parse --abbrev-ref HEAD 2>/dev/null)

if [ -n "$branch" ]; then
  sec1+=$(printf " ${GRAY}%s${NC}" "$branch")

  # Dirty file count (bash arithmetic strips whitespace from wc -l, avoids tr subprocess)
  dirty_count=$(git --no-optional-locks status --porcelain 2>/dev/null | wc -l)
  dirty_count=$((dirty_count + 0))
  if [ "$dirty_count" -gt 0 ] 2>/dev/null; then
    sec1+=$(printf " ${ORANGE}%s dirty${NC}" "$dirty_count")
  fi
fi

fi  # end QA-009 null DIR guard

# --- Section 2: Model/context/tokens ---

sec2=""

# Model name — QA-011: skip if null or empty
if [ -n "$MODEL" ] && [ "$MODEL" != "null" ]; then
  sec2+=$(printf "${ORANGE}%s${NC}" "$MODEL")
fi

# Output style (if not default)
if [ "$STYLE" != "null" ] && [ "$STYLE" != "default" ]; then
  sec2+=$(printf " ${GRAY}[%s]${NC}" "$STYLE")
fi

# Context window percentage — guard against null/0/missing (R-017)
ctx=''
if [ "$CURRENT_TOKENS" != "null" ] && [ -n "$CURRENT_TOKENS" ] && [ "$CONTEXT_SIZE" != "null" ] && [ "$CONTEXT_SIZE" != "" ] && [ "$CONTEXT_SIZE" -gt 0 ] 2>/dev/null; then
  PERCENT_USED=$((CURRENT_TOKENS * 100 / CONTEXT_SIZE))
  if [ "$PERCENT_USED" -lt 40 ]; then
    ctx=$(printf "${GREEN}%d%%${NC}" "$PERCENT_USED")
  elif [ "$PERCENT_USED" -lt 70 ]; then
    ctx=$(printf "${YELLOW}%d%%${NC}" "$PERCENT_USED")
  else
    ctx=$(printf "${RED}%d%%${NC}" "$PERCENT_USED")
  fi
fi

if [ -n "$ctx" ]; then
  sec2+=$(printf " %s" "$ctx")
fi

# Token counts: {in} : {out} (in:out)
# QA-010: Also guard against empty strings
if [ -n "$TOTAL_IN" ] && [ "$TOTAL_IN" != "null" ] && [ -n "$TOTAL_OUT" ] && [ "$TOTAL_OUT" != "null" ]; then
  # Check both are not zero
  if [ "$TOTAL_IN" != "0" ] || [ "$TOTAL_OUT" != "0" ]; then
    fmt_in=$(fmt_tokens "$TOTAL_IN")
    fmt_out=$(fmt_tokens "$TOTAL_OUT")
    sec2+=" ${fmt_in} : ${fmt_out} (in:out)"
  fi
fi

# --- Section 3: Session stats ---

sec3=""

# Duration
if [ "$DURATION_MS" != "null" ] && [ "$DURATION_MS" != "0" ] && [ -n "$DURATION_MS" ] 2>/dev/null; then
  sec3+="$(fmt_duration "$DURATION_MS")"
fi

# Cost (rounded to 2 decimal places) — single awk: format + zero-check combined
# QA-002: Handle both "0" and "0.0" by using awk numeric comparison
if [ "$COST" != "null" ] && [ -n "$COST" ]; then
  cost_fmt=$(awk "BEGIN { v=($COST+0); if(v==0) exit 1; printf \"%.2f\", v }") && {
    if [ -n "$sec3" ]; then sec3+=" "; fi
    sec3+="\$${cost_fmt}"
  }
fi

# Lines delta
if [ "$LINES_ADD" != "null" ] && [ "$LINES_REM" != "null" ]; then
  if [ "${LINES_ADD:-0}" != "0" ] || [ "${LINES_REM:-0}" != "0" ]; then
    if [ -n "$sec3" ]; then sec3+=" "; fi
    sec3+=$(printf "${GREEN}+%s${NC}/${RED}-%s${NC}" "${LINES_ADD}" "${LINES_REM}")
  fi
fi

# --- Section 4: Workflow ---

sec4=""
NOW_EPOCH=$(date +%s)
if [ -n "$branch" ] && [ -d ".correctless/artifacts" ]; then
  slug="${branch//[^a-zA-Z0-9]/-}"
  slug="${slug:0:80}"
  raw_hash="$(printf '%s' "$branch" | (md5sum 2>/dev/null || md5))"
  STATE_FILE=".correctless/artifacts/workflow-state-${slug}-${raw_hash:0:6}.json"

  if [ -f "$STATE_FILE" ]; then
    eval "$(jq -r '
      @sh "PHASE=\(.phase // empty)",
      @sh "QA_ROUNDS=\(.qa_rounds // 0)",
      @sh "TASK=\(.task // empty)",
      @sh "PHASE_ENTERED=\(.phase_entered_at // empty)",
      @sh "OVERRIDE_REMAINING=\(.override.remaining_calls // empty)",
      @sh "SPEC_UPDATES=\(.spec_updates // 0)"
    ' "$STATE_FILE" 2>/dev/null)"

    if [ -n "$PHASE" ]; then
      # Task name (truncate to 20 chars + ellipsis)
      # QA-008: Use cut -c for character-aware truncation (multibyte safe)
      task_display="$TASK"
      if [ "${#TASK}" -gt 20 ]; then
        task_display="$(printf '%s' "$TASK" | cut -c1-20)…"
      fi

      # Color-coded phase
      phase_display=""
      case "$PHASE" in
        spec|review|review-spec|model)
          phase_display=$(printf "${CYAN}%s${NC}" "$PHASE") ;;
        tdd-tests)
          phase_display=$(printf "${RED}RED${NC}") ;;
        tdd-impl)
          phase_display=$(printf "${GREEN}GREEN${NC}") ;;
        tdd-qa)
          phase_display=$(printf "${YELLOW}QA${NC}") ;;
        tdd-verify)
          phase_display=$(printf "${YELLOW}VERIFY${NC}") ;;
        done|verified|documented)
          phase_display=$(printf "${GRAY}%s${NC}" "$PHASE") ;;
        audit)
          phase_display=$(printf "${ORANGE}AUDIT${NC}") ;;
        *)
          phase_display=$(printf "${GRAY}%s${NC}" "$PHASE") ;;
      esac

      # QA rounds
      qa_display=""
      if [ "$QA_ROUNDS" != "0" ] && [ "$QA_ROUNDS" != "null" ] && [ -n "$QA_ROUNDS" ]; then
        qa_display=" R${QA_ROUNDS}"
      fi

      # Time in phase
      time_display=""
      if [ -n "$PHASE_ENTERED" ]; then
        entered_epoch=$(date -d "$PHASE_ENTERED" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$PHASE_ENTERED" +%s 2>/dev/null || echo "")
        if [ -n "$entered_epoch" ]; then
          now_epoch=$NOW_EPOCH
          elapsed_ms=$(( (now_epoch - entered_epoch) * 1000 ))
          # QA-003: Only show time if >= 60000ms (1 minute) to avoid misleading "0m"
          if [ "$elapsed_ms" -ge 60000 ]; then
            time_display=" · $(fmt_duration "$elapsed_ms")"
          fi
        fi
      fi

      # Warnings
      warnings=""
      if [ -n "$OVERRIDE_REMAINING" ] && [ "$OVERRIDE_REMAINING" != "0" ]; then
        warnings+=" ⚠override(${OVERRIDE_REMAINING})"
      fi
      if [ "$SPEC_UPDATES" -ge 2 ] 2>/dev/null; then
        warnings+=" ⚠spec×${SPEC_UPDATES}"
      fi

      sec4="⚙ ${task_display} · ${phase_display}${qa_display}${time_display}${warnings}"
    fi
  fi
fi

# --- Assemble sections with ' │ ' separator ---

sections=()
[ -n "$sec1" ] && sections+=("$sec1")
[ -n "$sec2" ] && sections+=("$sec2")
[ -n "$sec3" ] && sections+=("$sec3")
[ -n "$sec4" ] && sections+=("$sec4")

output=""
for i in "${!sections[@]}"; do
  if [ "$i" -gt 0 ]; then
    output+=" │ "
  fi
  output+="${sections[$i]}"
done

echo "$output"
