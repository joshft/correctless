#!/usr/bin/env bash
# Correctless — workflow-aware statusline for Claude Code
# 4 sections separated by ' │ ':
#   1. Repo state: {dir}/ {branch} {N dirty}
#   2. Model/context/tokens: {model} {N%} {in} : {out} (in:out)
#   3. Session stats: {duration} ${cost} +N/-N
#   4. Workflow: ⚙ {task} · {PHASE} R{n} · {time} {warnings}
# Designed to be fast (<50ms) — bulk jq calls minimize process spawns

input=$(cat)

# QA-R1-016: Check jq availability (consistent with other hooks)
command -v jq >/dev/null 2>&1 || { echo ""; exit 0; }

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

# --- Helper: phase name → display label (tdd-impl → GREEN, etc.) ---
# Used by both the phase indicator and the cost breakdown display.
phase_display_name() {
  case "$1" in
    tdd-tests)  echo "RED" ;;
    tdd-impl)   echo "GREEN" ;;
    tdd-qa)     echo "QA" ;;
    tdd-verify) echo "VERIFY" ;;
    *)          echo "$1" ;;
  esac
}

# --- Helper: format a decimal cost if non-zero, empty otherwise ---
# Usage: fmt_cost_nonzero "12.50" → "12.50", fmt_cost_nonzero "0" → ""
fmt_cost_nonzero() {
  awk -v c="$1" 'BEGIN { if (c+0 == 0) exit 1; printf "%.2f", c }' 2>/dev/null
}

# --- Section 1: Repo state ---

sec1=""

# QA-009: Guard against null or missing workspace.current_dir
if [ -z "$DIR" ] || [ "$DIR" = "null" ]; then
  branch=""
else

sec1+="${DIR##*/}/"

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
if [ "$CURRENT_TOKENS" != "null" ] && [ -n "$CURRENT_TOKENS" ] && [[ "$CURRENT_TOKENS" =~ ^[0-9]+$ ]] && [ "$CONTEXT_SIZE" != "null" ] && [ "$CONTEXT_SIZE" != "" ] && [ "$CONTEXT_SIZE" -gt 0 ] 2>/dev/null; then
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
  cost_fmt=$(awk -v cost="$COST" 'BEGIN { v=(cost+0); if(v==0) exit 1; printf "%.2f", v }') && {
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
  # Source shared library for branch_slug() (ABS-001)
  if [ -z "${_LIBS_LOADED:-}" ]; then
    _LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" 2>/dev/null && pwd || true)"
    if [ -n "$_LIB_DIR" ] && [ -f "$_LIB_DIR/lib.sh" ]; then
      source "$_LIB_DIR/lib.sh"; _LIBS_LOADED=1
    elif [ -f ".correctless/scripts/lib.sh" ]; then
      source ".correctless/scripts/lib.sh"; _LIBS_LOADED=1
    fi
  fi

  if command -v branch_slug >/dev/null 2>&1; then
    _slug="$(branch_slug 2>/dev/null)" || _slug=""
  else
    _slug=""  # lib.sh not available — skip workflow section
  fi
  STATE_FILE=".correctless/artifacts/workflow-state-${_slug}.json"

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
      task_display="$TASK"
      if [ "${#TASK}" -gt 20 ]; then
        task_display="${TASK:0:20}…"
      fi

      # Color-coded phase
      _phase_label="$(phase_display_name "$PHASE")"
      phase_display=""
      case "$PHASE" in
        spec|review|review-spec|model)
          phase_display=$(printf "${CYAN}%s${NC}" "$_phase_label") ;;
        tdd-tests)
          phase_display=$(printf "${RED}%s${NC}" "$_phase_label") ;;
        tdd-impl)
          phase_display=$(printf "${GREEN}%s${NC}" "$_phase_label") ;;
        tdd-qa|tdd-verify)
          phase_display=$(printf "${YELLOW}%s${NC}" "$_phase_label") ;;
        audit)
          phase_display=$(printf "${ORANGE}%s${NC}" "$_phase_label") ;;
        *)
          phase_display=$(printf "${GRAY}%s${NC}" "$_phase_label") ;;
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

      # --- Feature cost from cache (R-001 through R-010) ---
      cost_display=""
      COST_CACHE_FILE=".correctless/artifacts/cost-cache-${_slug}.json"
      COST_LOCK_FILE=".correctless/artifacts/cost-cache.lock"
      CACHE_MAX_AGE=30  # seconds — hardcoded for v1 (R-010)

      if [ -f "$COST_CACHE_FILE" ]; then
        # Single jq call to extract both fields (R-002, R-008)
        eval "$(jq -r '
          @sh "FEATURE_COST=\(.total_cost_usd // 0)",
          @sh "PHASE_COST=\(.current_phase_cost_usd // 0)"
        ' "$COST_CACHE_FILE" 2>/dev/null)" 2>/dev/null || true

        # Build cost display (R-001, R-004)
        cost_fmt=$(fmt_cost_nonzero "${FEATURE_COST:-0}") && {
          cost_display=" · \$${cost_fmt}"
          # Add phase cost if non-zero (R-004)
          phase_cost_fmt=$(fmt_cost_nonzero "${PHASE_COST:-0}") && {
            cost_display+=" (\$${phase_cost_fmt} in $(phase_display_name "$PHASE"))"
          }
        }

        # Staleness check for background refresh (R-002, R-003)
        # Default to stale; override only when we can determine the real age
        cache_age=$((CACHE_MAX_AGE + 1))
        cache_mtime=$(stat -c %Y "$COST_CACHE_FILE" 2>/dev/null || stat -f %m "$COST_CACHE_FILE" 2>/dev/null || echo "")
        if [ -n "$cache_mtime" ]; then
          cache_age=$((NOW_EPOCH - cache_mtime))
        else
          # Fallback: parse computed_at from cache JSON (R-002)
          computed_at_str=$(jq -r '.computed_at // empty' "$COST_CACHE_FILE" 2>/dev/null || echo "")
          computed_epoch=""
          if [ -n "$computed_at_str" ]; then
            computed_epoch=$(date -d "$computed_at_str" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$computed_at_str" +%s 2>/dev/null || echo "")
          fi
          if [ -n "$computed_epoch" ]; then
            cache_age=$((NOW_EPOCH - computed_epoch))
          fi
        fi
      else
        cache_age=$((CACHE_MAX_AGE + 1))  # No cache file — treat as stale (R-001: omit cost)
      fi

      # Background refresh when stale (R-003)
      if [ "${cache_age:-0}" -gt "$CACHE_MAX_AGE" ]; then
        # Check lock file — only one background computation at a time
        _spawn_refresh=true
        if [ -f "$COST_LOCK_FILE" ]; then
          _lock_pid=$(cat "$COST_LOCK_FILE" 2>/dev/null || echo "")
          if [ -n "$_lock_pid" ] && kill -0 "$_lock_pid" 2>/dev/null; then
            _spawn_refresh=false  # Already running
          else
            rm -f "$COST_LOCK_FILE"  # Stale lock — auto-clean
          fi
        fi

        if [ "$_spawn_refresh" = true ]; then
          # Resolve compute-session-cost.sh path
          _COST_SCRIPT=""
          if [ -n "${_LIB_DIR:-}" ] && [ -f "${_LIB_DIR}/compute-session-cost.sh" ]; then
            _COST_SCRIPT="${_LIB_DIR}/compute-session-cost.sh"
          elif [ -f ".correctless/scripts/compute-session-cost.sh" ]; then
            _COST_SCRIPT=".correctless/scripts/compute-session-cost.sh"
          fi

          if [ -n "$_COST_SCRIPT" ]; then
            # Spawn background refresh (R-003): atomic write via temp + mv
            (
              trap 'rm -f "'"$COST_LOCK_FILE"'"' EXIT
              _tmp_cache=$(mktemp ".correctless/artifacts/cost-cache-tmp-XXXXXX")
              bash "$_COST_SCRIPT" --cache --phase "$PHASE" "$branch" > "$_tmp_cache" 2>/dev/null
              mv "$_tmp_cache" "$COST_CACHE_FILE" 2>/dev/null || rm -f "$_tmp_cache"
            ) &
            # Write lock file BEFORE disown, containing the background PID (R-003)
            echo "$!" > "$COST_LOCK_FILE" 2>/dev/null || true
            disown 2>/dev/null || true
          fi
        fi
      fi

      sec4="⚙ ${task_display} · ${phase_display}${qa_display}${time_display}${cost_display}${warnings}"
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
