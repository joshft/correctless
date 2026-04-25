#!/usr/bin/env bash
# Correctless — Session Cost Analysis
#
# Reads Claude Code session transcripts from ~/.claude/projects/ and computes
# per-feature USD cost. Outputs JSON to stdout and writes a cost artifact to
# .correctless/artifacts/cost-{branch-slug}.json.
#
# Usage: bash scripts/compute-session-cost.sh [branch-name]
#   If branch-name is omitted, derives from current git branch.
#
# Requires: jq 1.7+ (ENV-002), bash 4+ (ENV-001)
# Sources: scripts/lib.sh for branch_slug() and artifacts_dir()

set -euo pipefail

# ============================================================================
# STEP 1: Setup — source lib, resolve paths
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$SCRIPT_DIR/lib.sh"

# error_json — emit a zero-cost JSON envelope with an error message and exit 0.
# Used for all graceful-degradation paths so callers always get valid JSON.
error_json() {
  local msg="$1"
  echo "{\"error\":\"$msg\",\"total_cost_usd\":0,\"total_input_tokens\":0,\"total_output_tokens\":0,\"total_cache_write_tokens\":0,\"total_cache_read_tokens\":0,\"by_phase\":[],\"by_subagent\":[],\"pricing_used\":{},\"model_breakdown\":[],\"unknown_models\":[],\"warnings\":[],\"sessions\":[]}"
  exit 0
}

# ============================================================================
# STEP 2: Parse flags and determine target branch
# ============================================================================

CACHE_MODE=false
CACHE_PHASE=""

# Parse flags before positional args
while [ $# -gt 0 ]; do
  case "$1" in
    --cache)
      CACHE_MODE=true
      shift
      ;;
    --phase)
      CACHE_PHASE="${2:-}"
      shift 2
      ;;
    -*)
      # Unknown flag — skip
      shift
      ;;
    *)
      break
      ;;
  esac
done

TARGET_BRANCH="${1:-}"
if [ -z "$TARGET_BRANCH" ]; then
  TARGET_BRANCH="$(git branch --show-current 2>/dev/null)" || true
  if [ -z "$TARGET_BRANCH" ]; then
    error_json "no branch specified and not in a git repository"
  fi
fi

# Derive branch slug for artifact naming
BRANCH_SLUG=$(branch_slug "$TARGET_BRANCH")

# ============================================================================
# STEP 3: Read config
# ============================================================================

CONFIG_FILE="$(config_file)"
CONFIG_SESSION_DIR=""
CONFIG_PRICING="{}"

if [ -f "$CONFIG_FILE" ]; then
  CONFIG_SESSION_DIR=$(jq -r '.workflow.session_dir // ""' "$CONFIG_FILE" 2>/dev/null || echo "")
  CONFIG_PRICING=$(jq -r '.workflow.pricing // {}' "$CONFIG_FILE" 2>/dev/null || echo "{}")
fi

# ============================================================================
# STEP 4: Validate and resolve session directory
# ============================================================================

SESSION_DIR=""

if [ -n "$CONFIG_SESSION_DIR" ]; then
  # Config override path — validate per R-002
  if [[ "$CONFIG_SESSION_DIR" != /* ]]; then
    error_json "workflow.session_dir must be an absolute path"
  fi
  if [ ! -d "$CONFIG_SESSION_DIR" ]; then
    error_json "workflow.session_dir does not exist"
  fi
  local_home="${HOME:-}"
  if [[ "$CONFIG_SESSION_DIR" != "$local_home/.claude/"* ]]; then
    error_json "workflow.session_dir must be under ~/.claude/"
  fi
  SESSION_DIR="$CONFIG_SESSION_DIR"
else
  # Candidate derivation: repo_root | tr '/' '-'
  local_repo_root="$(repo_root)"
  candidate_slug="$(echo "$local_repo_root" | tr '/' '-' | sed 's/^-//')"
  candidate_dir="${HOME:-}/.claude/projects/$candidate_slug"
  if [ -d "$candidate_dir" ]; then
    SESSION_DIR="$candidate_dir"
  else
    error_json "session directory not found — set workflow.session_dir in workflow-config.json"
  fi
fi

# ============================================================================
# STEP 5: Validate pricing config (R-006)
# ============================================================================

# Validate config pricing — all values must be positive, max $500/M
if [ "$CONFIG_PRICING" != "{}" ] && [ "$CONFIG_PRICING" != "null" ]; then
  pricing_error=$(echo "$CONFIG_PRICING" | jq -r '
    [to_entries[] | .value | to_entries[] |
      if (.value | type) != "number" then "non-numeric pricing value: \(.key)=\(.value)"
      elif .value < 0 then "negative pricing value: \(.key)=\(.value)"
      elif .value > 500 then "pricing exceeds $500/M ceiling: \(.key)=\(.value)"
      else empty end
    ] | if length > 0 then .[0] else empty end
  ' 2>/dev/null || echo "")

  if [ -n "$pricing_error" ]; then
    error_json "invalid pricing: $pricing_error"
  fi
fi

# ============================================================================
# STEP 6: Define default pricing (per million tokens) — R-006
# ============================================================================

# Hardcoded defaults for models observed in real transcripts
# Values are USD per million tokens
DEFAULT_PRICING='{
  "claude-opus-4-6": {"input": 15, "cache_write": 18.75, "cache_read": 1.50, "output": 75},
  "claude-sonnet-4-6": {"input": 3, "cache_write": 3.75, "cache_read": 0.30, "output": 15},
  "claude-haiku-4-5-20251001": {"input": 0.80, "cache_write": 1.00, "cache_read": 0.08, "output": 4}
}'

# Merge config pricing over defaults (config wins for matching model IDs)
EFFECTIVE_PRICING=$(echo "$DEFAULT_PRICING" | jq --argjson override "$CONFIG_PRICING" '
  . * $override
' 2>/dev/null)

# Median model for unknown models = Sonnet (middle tier)
MEDIAN_MODEL="claude-sonnet-4-6"

# ============================================================================
# STEP 7: Discover and scan session transcripts (R-002, R-013)
# ============================================================================

MATCHING_SESSIONS=()

# shellcheck disable=SC2044
if compgen -G "$SESSION_DIR/*.jsonl" >/dev/null 2>&1; then
  for jsonl_file in "$SESSION_DIR"/*.jsonl; do
    [ -f "$jsonl_file" ] || continue
    # Check if any entry has matching gitBranch (early exit per R-013)
    if jq -R 'try (fromjson | select(.gitBranch == "'"$TARGET_BRANCH"'")) catch empty' "$jsonl_file" 2>/dev/null | head -1 | grep -q '.'; then
      # Extract session ID from filename
      local_session_id="$(basename "$jsonl_file" .jsonl)"
      MATCHING_SESSIONS+=("$local_session_id")
    fi
  done
fi

# No matching sessions — exit gracefully (R-011)
if [ ${#MATCHING_SESSIONS[@]} -eq 0 ]; then
  echo '{"branch":"'"$TARGET_BRANCH"'","feature":"","computed_at":"'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'","sessions":[],"total_cost_usd":0,"total_input_tokens":0,"total_output_tokens":0,"total_cache_write_tokens":0,"total_cache_read_tokens":0,"by_phase":[],"by_subagent":[{"description":"orchestrator","agent_type":"parent","cost_usd":0,"tokens":0,"turns":0}],"pricing_used":{},"model_breakdown":[],"unknown_models":[],"warnings":[]}'
  exit 0
fi

# ============================================================================
# STEP 8: Read audit trail for phase attribution (R-004)
# ============================================================================

ARTIFACT_DIR="$(artifacts_dir)"
AUDIT_TRAIL_FILE="$ARTIFACT_DIR/audit-trail-${BRANCH_SLUG}.jsonl"

PHASE_TRANSITIONS="[]"
if [ -f "$AUDIT_TRAIL_FILE" ]; then
  # Extract phase transitions — each entry where phase differs from previous
  PHASE_TRANSITIONS=$(jq -R 'try (fromjson | {phase: .phase, timestamp: .timestamp}) catch empty' "$AUDIT_TRAIL_FILE" 2>/dev/null | jq -n '
    [inputs] | reduce .[] as $entry (
      {transitions: [], last_phase: null};
      if $entry.phase != .last_phase then
        .transitions += [$entry] | .last_phase = $entry.phase
      else . end
    ) | .transitions
  ' 2>/dev/null || echo "[]")
fi

# ============================================================================
# STEP 9: Process all matching transcripts (R-003, R-004, R-012, R-013)
# ============================================================================

# Collect all entries from parent + subagent transcripts
ALL_ENTRIES_FILE=$(mktemp)
SUBAGENT_META_FILE=$(mktemp)
# shellcheck disable=SC2064
trap "rm -f '$ALL_ENTRIES_FILE' '$SUBAGENT_META_FILE'" EXIT

for session_id in "${MATCHING_SESSIONS[@]}"; do
  session_jsonl="$SESSION_DIR/$session_id.jsonl"

  # Parent transcript
  if [ -f "$session_jsonl" ]; then
    jq -R 'try (fromjson | select(.gitBranch == "'"$TARGET_BRANCH"'" and .type == "assistant") |
      {
        msg_id: .message.id,
        model: (.message.model // "unknown"),
        input_tokens: (.message.usage.input_tokens // null),
        output_tokens: (.message.usage.output_tokens // null),
        cache_write: (.message.usage.cache_creation_input_tokens // 0),
        cache_read: (.message.usage.cache_read_input_tokens // 0),
        timestamp: .timestamp,
        source: "parent",
        session: "'"$session_id"'"
      }) catch empty' "$session_jsonl" >> "$ALL_ENTRIES_FILE" 2>/dev/null || true
  fi

  # Subagent transcripts (R-012)
  local_subagent_dir="$SESSION_DIR/$session_id/subagents"
  if [ -d "$local_subagent_dir" ]; then
    # Process agent-*.jsonl (pipeline subagents)
    for agent_jsonl in "$local_subagent_dir"/agent-*.jsonl; do
      [ -f "$agent_jsonl" ] || continue
      local_agent_basename="$(basename "$agent_jsonl" .jsonl)"
      local_meta_file="$local_subagent_dir/${local_agent_basename}.meta.json"

      # Read meta.json for description and type
      local_agent_desc="unknown"
      local_agent_type="unknown"
      if [ -f "$local_meta_file" ]; then
        local_agent_desc=$(jq -r '.description // "unknown"' "$local_meta_file" 2>/dev/null || echo "unknown")
        local_agent_type=$(jq -r '.type // "unknown"' "$local_meta_file" 2>/dev/null || echo "unknown")
      fi
      echo "{\"agent_basename\":\"$local_agent_basename\",\"description\":\"$local_agent_desc\",\"agent_type\":\"$local_agent_type\",\"session\":\"$session_id\"}" >> "$SUBAGENT_META_FILE"

      jq -R 'try (fromjson | select(.type == "assistant") |
        {
          msg_id: .message.id,
          model: (.message.model // "unknown"),
          input_tokens: (.message.usage.input_tokens // null),
          output_tokens: (.message.usage.output_tokens // null),
          cache_write: (.message.usage.cache_creation_input_tokens // 0),
          cache_read: (.message.usage.cache_read_input_tokens // 0),
          timestamp: .timestamp,
          source: "agent:'"$local_agent_basename"'",
          session: "'"$session_id"'"
        }) catch empty' "$agent_jsonl" >> "$ALL_ENTRIES_FILE" 2>/dev/null || true
    done

    # Process infrastructure subagents (compact-*, aside_question-*, etc.)
    # These are included in totals but excluded from by_subagent (R-012)
    for infra_jsonl in "$local_subagent_dir"/*.jsonl; do
      [ -f "$infra_jsonl" ] || continue
      local_infra_basename="$(basename "$infra_jsonl" .jsonl)"
      # Skip agent-*.jsonl (already processed above)
      case "$local_infra_basename" in
        agent-*) continue ;;
      esac

      jq -R 'try (fromjson | select(.type == "assistant") |
        {
          msg_id: .message.id,
          model: (.message.model // "unknown"),
          input_tokens: (.message.usage.input_tokens // null),
          output_tokens: (.message.usage.output_tokens // null),
          cache_write: (.message.usage.cache_creation_input_tokens // 0),
          cache_read: (.message.usage.cache_read_input_tokens // 0),
          timestamp: .timestamp,
          source: "infra:'"$local_infra_basename"'",
          session: "'"$session_id"'"
        }) catch empty' "$infra_jsonl" >> "$ALL_ENTRIES_FILE" 2>/dev/null || true
    done
  fi
done

# ============================================================================
# STEP 10: Deduplicate by message.id (R-003) and compute cost
# ============================================================================

# Build the final result using jq
# PAT-010: wrap as-bindings in explicit parens for jq 1.7 compatibility
RESULT=$(jq -n --argjson pricing "$EFFECTIVE_PRICING" --argjson transitions "$PHASE_TRANSITIONS" --arg branch "$TARGET_BRANCH" --arg median "$MEDIAN_MODEL" '
  [inputs] |
  # Step 1: Deduplicate — keep last entry per message.id (R-003)
  group_by(.msg_id) | [.[] | last] |

  # Step 2: Separate entries with/without usage (R-003 warning)
  [.[] | select(.input_tokens != null)] as $valid |
  [.[] | select(.input_tokens == null)] as $no_usage |

  # Step 3: Build pricing lookup — per-token (divide per-million by 1000000)
  ($pricing | to_entries | map({
    key: .key,
    value: {
      input: (.value.input / 1000000),
      output: (.value.output / 1000000),
      cache_write: (.value.cache_write / 1000000),
      cache_read: (.value.cache_read / 1000000)
    }
  }) | from_entries) as $per_token_pricing |

  # Median pricing for unknown models
  ($per_token_pricing[$median] // {input: 0.000003, output: 0.000015, cache_write: 0.00000375, cache_read: 0.0000003}) as $median_pricing |

  # Step 4: Collect unknown models
  ([$valid[].model] | unique | [.[] | select(. as $m | $pricing | has($m) | not)]) as $unknown_models |

  # Step 5: Compute per-entry cost
  [$valid[] | (
    ($per_token_pricing[.model] // $median_pricing) as $p |
    {
      model: .model,
      input_tokens: .input_tokens,
      output_tokens: .output_tokens,
      cache_write: .cache_write,
      cache_read: .cache_read,
      cost: (((.input_tokens * $p.input) + (.cache_write * $p.cache_write) + (.cache_read * $p.cache_read) + (.output_tokens * $p.output)) * 1000000 | round | . / 1000000),
      timestamp: .timestamp,
      source: .source,
      session: .session
    }
  )] as $costed |

  # Step 6: Phase attribution (R-004)
  (if ($transitions | length) == 0 then
    # No audit trail — all unattributed
    [$costed[] | . + {phase: "unattributed"}]
  else
    ($transitions | sort_by(.timestamp)) as $sorted_transitions |
    [$costed[] | . as $entry |
      if $entry.timestamp < $sorted_transitions[0].timestamp then
        . + {phase: "pre-workflow"}
      else
        # Find the last transition before or at this timestamp
        ([$sorted_transitions[] | select(.timestamp <= $entry.timestamp)] | last // null) as $match |
        if $match != null then . + {phase: $match.phase}
        else . + {phase: "pre-workflow"}
        end
      end
    ]
  end) as $phased |

  # Step 7: Aggregate by_phase
  ($phased | group_by(.phase) | [.[] | {
    phase: .[0].phase,
    cost_usd: (([.[].cost] | add // 0) * 1000000 | round | . / 1000000),
    input_tokens: ([.[].input_tokens] | add // 0),
    output_tokens: ([.[].output_tokens] | add // 0),
    cache_write_tokens: ([.[].cache_write] | add // 0),
    cache_read_tokens: ([.[].cache_read] | add // 0),
    turns: length
  }]) as $by_phase |

  # Step 8: Aggregate by_subagent (R-012)
  # Parent + infra entries go to "orchestrator"; agent:* entries go to their agent
  ($phased | group_by(
    if (.source | startswith("agent:")) then .source else "parent" end
  ) | [.[] | {
    source_key: (if .[0].source | startswith("agent:") then .[0].source else "parent" end),
    cost_usd: (([.[].cost] | add // 0) * 1000000 | round | . / 1000000),
    tokens: (([.[].input_tokens] | add // 0) + ([.[].output_tokens] | add // 0)),
    turns: length
  }]) as $by_source |

  # Step 9: Model breakdown
  ($phased | group_by(.model) | [.[] | {
    model: .[0].model,
    cost_usd: (([.[].cost] | add // 0) * 1000000 | round | . / 1000000),
    turns: length
  }]) as $model_breakdown |

  # Step 10: Totals
  (([$phased[].cost] | add // 0) * 1000000 | round | . / 1000000) as $total_cost |
  ([$phased[].input_tokens] | add // 0) as $total_input |
  ([$phased[].output_tokens] | add // 0) as $total_output |
  ([$phased[].cache_write] | add // 0) as $total_cache_write |
  ([$phased[].cache_read] | add // 0) as $total_cache_read |

  # Step 11: Sessions list
  ([$phased[].session] | unique) as $session_list |

  # Step 12: Warnings
  ([$no_usage[] | "unrecognized transcript format in session \(.session)"] | unique) as $usage_warnings |

  # Build output
  {
    branch: $branch,
    feature: ($branch | gsub("^.*/"; "")),
    computed_at: (now | strftime("%Y-%m-%dT%H:%M:%SZ")),
    sessions: $session_list,
    total_cost_usd: $total_cost,
    total_input_tokens: $total_input,
    total_output_tokens: $total_output,
    total_cache_write_tokens: $total_cache_write,
    total_cache_read_tokens: $total_cache_read,
    by_phase: $by_phase,
    by_subagent: (
      [$by_source[] |
        if .source_key == "parent" then
          {description: "orchestrator", agent_type: "parent", cost_usd: .cost_usd, tokens: .tokens, turns: .turns}
        else
          {description: (.source_key | gsub("^agent:"; "")), agent_type: "unknown", cost_usd: .cost_usd, tokens: .tokens, turns: .turns}
        end
      ]
    ),
    pricing_used: $pricing,
    model_breakdown: $model_breakdown,
    unknown_models: $unknown_models,
    warnings: $usage_warnings
  }
' "$ALL_ENTRIES_FILE" 2>/dev/null)

# ============================================================================
# STEP 11: Enrich by_subagent with meta.json data (R-012)
# ============================================================================

if [ -s "$SUBAGENT_META_FILE" ]; then
  SUBAGENT_META=$(jq -n '[inputs]' "$SUBAGENT_META_FILE" 2>/dev/null || echo "[]")
  RESULT=$(echo "$RESULT" | jq --argjson meta "$SUBAGENT_META" '
    .by_subagent = [.by_subagent[] |
      if .description != "orchestrator" then
        (.description) as $agent_base |
        ($meta[] | select(.agent_basename == $agent_base) // null) as $m |
        if $m != null then
          .description = $m.description | .agent_type = $m.agent_type
        else . end
      else . end
    ]
  ' 2>/dev/null || echo "$RESULT")
fi

# ============================================================================
# STEP 12: Write artifact and output (R-001)
# ============================================================================

if [ "$CACHE_MODE" = true ]; then
  # --cache mode: output lightweight JSON to stdout (caller handles file placement)
  # Extract: total_cost_usd, by_phase, computed_at, current_phase_cost_usd
  echo "$RESULT" | jq --arg phase "$CACHE_PHASE" '{
    total_cost_usd: .total_cost_usd,
    by_phase: .by_phase,
    computed_at: .computed_at,
    current_phase_cost_usd: (
      if ($phase | length) > 0 then
        ([.by_phase[] | select(.phase == $phase) | .cost_usd] | add // 0)
      else 0 end
    )
  }' 2>/dev/null
  # No artifact file written in --cache mode
else
  mkdir -p "$ARTIFACT_DIR"
  ARTIFACT_PATH="$ARTIFACT_DIR/cost-${BRANCH_SLUG}.json"
  echo "$RESULT" | jq '.' > "$ARTIFACT_PATH" 2>/dev/null || true

  # Output to stdout
  echo "$RESULT"
fi
