#!/usr/bin/env bash
# Correctless — Pruning Scanner
# Detects staleness candidates across 9 categories, outputs JSON to stdout.
#
# Usage: prune-scan.sh --category <category> --base <path> [--branches-file <path>]
# Categories: architecture, antipatterns, claude-md, artifacts, deferred, counts, crossrefs, specs, driftdebt
#
# Each candidate: { id, category, reason, risk, dead_refs, live_refs, bulk_warning }
# Per INV-002: deterministic, sources scripts/lib.sh, per-category error handling.

set -euo pipefail

# ============================================
# STEP 1: Parse arguments
# ============================================

CATEGORY=""
BASE_DIR=""
BRANCHES_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --category) CATEGORY="$2"; shift 2 ;;
    --base) BASE_DIR="$2"; shift 2 ;;
    --branches-file) BRANCHES_FILE="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; shift ;;
  esac
done

if [ -z "$BASE_DIR" ]; then
  BASE_DIR="$(pwd)"
fi

# ============================================
# STEP 2: Source lib.sh for shared utilities
# ============================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/lib.sh" ]; then
  # shellcheck source=lib.sh
  source "$SCRIPT_DIR/lib.sh"
elif [ -f "$BASE_DIR/scripts/lib.sh" ]; then
  # shellcheck source=lib.sh
  source "$BASE_DIR/scripts/lib.sh"
fi

# ============================================
# STEP 3: Helper functions
# ============================================

# Emit a JSON candidate object
emit_candidate() {
  local id="$1" category="$2" reason="$3" risk="$4"
  local dead_refs_json="$5" live_refs_json="$6" bulk_warning="$7"
  printf '{"id":%s,"category":%s,"reason":%s,"risk":%s,"dead_refs":%s,"live_refs":%s,"bulk_warning":%s}' \
    "$(jq -n --arg v "$id" '$v')" \
    "$(jq -n --arg v "$category" '$v')" \
    "$(jq -n --arg v "$reason" '$v')" \
    "$(jq -n --arg v "$risk" '$v')" \
    "$dead_refs_json" \
    "$live_refs_json" \
    "$bulk_warning"
}

# Convert a bash array of paths to a JSON array (single jq call)
paths_to_json_array() {
  if [ $# -eq 0 ]; then
    echo "[]"
    return
  fi
  printf '%s\n' "$@" | jq -R . | jq -sc .
}

# Check if a file path exists relative to BASE_DIR
file_exists() {
  local path="$1"
  [ -e "$BASE_DIR/$path" ]
}

# Output a JSON array from a bash array of JSON candidate objects.
# With bulk_warning support: pass total_entries as 2nd arg for >50% threshold.
emit_candidates_array() {
  local -n _cands="$1"
  local total_entries="${2:-0}"

  if [ ${#_cands[@]} -eq 0 ]; then
    echo "[]"
    return
  fi

  # Compute bulk_warning (BND-002)
  local bulk=false
  if [ "$total_entries" -gt 0 ]; then
    local pct=$(( (${#_cands[@]} * 100) / total_entries ))
    if [ "$pct" -gt 50 ]; then
      bulk=true
    fi
  fi

  local result="["
  local first=true
  for c in "${_cands[@]}"; do
    if [ "$first" = true ]; then
      first=false
    else
      result+=","
    fi
    result+="$(echo "$c" | jq --argjson bw "$bulk" '.bulk_warning = $bw')"
  done
  result+="]"
  echo "$result"
}

# Simple JSON array output without bulk_warning computation.
# Usage: emit_simple_array array_name
emit_simple_array() {
  local -n _items="$1"
  if [ ${#_items[@]} -eq 0 ]; then
    echo "[]"
    return
  fi
  local IFS=","
  echo "[${_items[*]}]"
}

# Classify a newline-delimited list of paths into dead_paths and live_paths arrays.
# Caller must declare: local dead_paths=() live_paths=()
classify_paths() {
  local paths="$1"
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    if file_exists "$p"; then
      live_paths+=("$p")
    else
      dead_paths+=("$p")
    fi
  done <<< "$paths"
}

# Load branch names from --branches-file or git.
# Outputs one branch name per line.
load_branches() {
  if [ -n "$BRANCHES_FILE" ] && [ -f "$BRANCHES_FILE" ]; then
    sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/^\* //' "$BRANCHES_FILE"
  else
    (cd "$BASE_DIR" && git branch -a 2>/dev/null | sed 's/^[[:space:]]*//;s/^\* //;s|remotes/origin/||') || \
    (cd "$BASE_DIR" && git branch 2>/dev/null | sed 's/^[[:space:]]*//;s/^\* //') || \
    true
  fi
}

# Extract file paths from a text block using spec-defined rules (INV-003)
# Outputs one path per line
extract_file_paths() {
  local text="$1"

  # Rule 1: backtick-quoted code spans matching file path patterns
  # Note: dash must be last in character class to avoid range interpretation
  echo "$text" | grep -oE '`[a-zA-Z0-9_./+-]+\.(sh|md|json|py|ts|js|yml|yaml)`' | sed 's/^`//;s/`$//' || true

  # Rule 2: Enforced at fields — comma-separated entries parsed as filepath (optional role)
  # Handles both backtick-quoted and bare paths: `scripts/lib.sh` (writer) OR scripts/lib.sh (writer)
  echo "$text" | grep -E '^- \*\*Enforced at\*\*:' | sed 's/^- \*\*Enforced at\*\*:[[:space:]]*//' | tr ',' '\n' | while read -r entry; do
    # Strip leading/trailing whitespace
    entry="$(echo "$entry" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [ -z "$entry" ] && continue
    # Try backtick-quoted first
    local bt_path
    bt_path="$(echo "$entry" | grep -oE '`[a-zA-Z0-9_./+-]+\.(sh|md|json|py|ts|js|yml|yaml)`' | sed 's/^`//;s/`$//')" || true
    if [ -n "$bt_path" ]; then
      echo "$bt_path"
    else
      # Bare path: strip role annotation in parens, take the path part
      local bare_path
      bare_path="$(echo "$entry" | sed 's/[[:space:]]*(.*)//' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
      # Validate it looks like a file path
      if echo "$bare_path" | grep -qE '^[a-zA-Z0-9_./-]+\.(sh|md|json|py|ts|js|yml|yaml)$'; then
        echo "$bare_path"
      fi
    fi
  done

  # Rule 3: Test fields — extract backtick-quoted paths
  echo "$text" | grep -E '^- \*\*Test\*\*:' | grep -oE '`[a-zA-Z0-9_./+-]+\.(sh|md|json|py|ts|js|yml|yaml)`' | sed 's/^`//;s/`$//' || true

  # Rule 4: See-link paths — format: See `path/to/file`.
  echo "$text" | grep -oE 'See `[a-zA-Z0-9_./+-]+\.(sh|md|json|py|ts|js|yml|yaml)`' | sed 's/See `//;s/`$//' || true

  # Rule 5: bare paths in Violated when fields
  echo "$text" | grep -E '^- \*\*Violated when\*\*:' | grep -oE '[a-zA-Z0-9_./+-]+\.(sh|md|json|py|ts|js)' || true
}

# ============================================
# STEP 4: Category scanners
# ============================================

# ---- architecture ----
scan_architecture() {
  local arch_file="$BASE_DIR/.correctless/ARCHITECTURE.md"
  if [ ! -f "$arch_file" ]; then
    echo "[]"
    return
  fi

  local candidates=()
  local total_entries=0
  local current_id=""
  local current_text=""
  local in_entry=false
  # Parse entries at ### level (ABS/PAT/TB/ENV); sub-entries (####) are part of the parent
  while IFS= read -r line; do
    if [[ "$line" =~ ^###[[:space:]]+(ABS|PAT|TB|ENV)-([0-9]+[a-z]?):.* ]]; then
      local new_id="${BASH_REMATCH[1]}-${BASH_REMATCH[2]}"

      if [ -n "$current_id" ] && [ "$in_entry" = true ]; then
        _process_arch_entry "$current_id" "$current_text"
      fi
      current_id="$new_id"
      current_text="$line"
      in_entry=true
      total_entries=$((total_entries + 1))
    elif [[ "$line" =~ ^####[[:space:]]+(ABS|PAT|TB|ENV)-([0-9]+[a-z]):.* ]]; then
      # Sub-entry (#### level) — append to current parent entry's text
      if [ "$in_entry" = true ]; then
        current_text+=$'\n'"$line"
      fi
    elif [[ "$line" =~ ^###[[:space:]] ]] && [ "$in_entry" = true ]; then
      # A different ### heading that's not ABS/PAT/TB/ENV — process current and reset
      _process_arch_entry "$current_id" "$current_text"
      current_id=""
      current_text=""
      in_entry=false
    elif [ "$in_entry" = true ]; then
      current_text+=$'\n'"$line"
    fi
  done < "$arch_file"

  # Process last entry
  if [ -n "$current_id" ] && [ "$in_entry" = true ]; then
    _process_arch_entry "$current_id" "$current_text"
  fi

  emit_candidates_array candidates "$total_entries"
}

_process_arch_entry() {
  local entry_id="$1"
  local entry_text="$2"

  local paths
  paths="$(extract_file_paths "$entry_text" | sort -u)"
  [ -z "$paths" ] && return

  local dead_paths=() live_paths=()
  classify_paths "$paths"

  # Entry is a candidate only when ALL paths are dead (PRH-003)
  if [ ${#live_paths[@]} -eq 0 ] && [ ${#dead_paths[@]} -gt 0 ]; then
    local candidate
    candidate="$(emit_candidate "$entry_id" "architecture" "All referenced files are dead" "medium" \
      "$(paths_to_json_array "${dead_paths[@]}")" "[]" "false")"
    candidates+=("$candidate")
  fi
}

# ---- antipatterns ----
scan_antipatterns() {
  local ap_file="$BASE_DIR/.correctless/antipatterns.md"
  if [ ! -f "$ap_file" ]; then
    echo "[]"
    return
  fi

  # Class-level title keywords (INV-011) — used by _process_ap_entry via bash dynamic scoping
  # shellcheck disable=SC2034
  local class_keywords="interpolation|injection|drift|silent|phantom"

  local candidates=()
  local total_entries=0
  local current_id=""
  local current_title=""
  local current_text=""
  local in_entry=false

  while IFS= read -r line; do
    if [[ "$line" =~ ^###[[:space:]]+(AP-[0-9]+):.* ]]; then
      # Process previous entry
      if [ -n "$current_id" ] && [ "$in_entry" = true ]; then
        _process_ap_entry "$current_id" "$current_title" "$current_text"
      fi
      current_id="${BASH_REMATCH[1]}"
      current_title="$line"
      current_text="$line"
      in_entry=true
      total_entries=$((total_entries + 1))
    elif [[ "$line" =~ ^###[[:space:]] ]] && [ "$in_entry" = true ]; then
      _process_ap_entry "$current_id" "$current_title" "$current_text"
      current_id=""
      current_title=""
      current_text=""
      in_entry=false
    elif [ "$in_entry" = true ]; then
      current_text+=$'\n'"$line"
    fi
  done < "$ap_file"

  # Process last entry
  if [ -n "$current_id" ] && [ "$in_entry" = true ]; then
    _process_ap_entry "$current_id" "$current_title" "$current_text"
  fi

  emit_candidates_array candidates "$total_entries"
}

_process_ap_entry() {
  local entry_id="$1"
  local entry_title="$2"
  local entry_text="$3"

  # Class-level antipatterns are never candidates (INV-011)
  echo "$entry_title" | grep -qiE "$class_keywords" && return

  local paths
  paths="$(extract_file_paths "$entry_text" | sort -u)"
  [ -z "$paths" ] && return

  local dead_paths=() live_paths=()
  classify_paths "$paths"

  if [ ${#live_paths[@]} -eq 0 ] && [ ${#dead_paths[@]} -gt 0 ]; then
    local candidate
    candidate="$(emit_candidate "$entry_id" "antipatterns" "All referenced files are dead" "medium" \
      "$(paths_to_json_array "${dead_paths[@]}")" "[]" "false")"
    candidates+=("$candidate")
  fi
}

# ---- claude-md ----
scan_claude_md() {
  local claude_file="$BASE_DIR/CLAUDE.md"
  if [ ! -f "$claude_file" ]; then
    echo "[]"
    return
  fi

  local candidates=()
  local total_entries=0
  local current_id=""
  local current_title=""
  local current_text=""
  local in_learnings=false
  local in_entry=false

  while IFS= read -r line; do
    # Detect the Correctless Learnings section
    if [[ "$line" =~ ^##[[:space:]]Correctless[[:space:]]Learnings ]]; then
      in_learnings=true
      continue
    fi

    # Exit learnings section on next ## heading (not ###)
    if [ "$in_learnings" = true ] && [[ "$line" =~ ^##[[:space:]] ]] && ! [[ "$line" =~ ^###[[:space:]] ]]; then
      # Process last entry before leaving section
      if [ -n "$current_id" ] && [ "$in_entry" = true ]; then
        _process_claude_entry "$current_id" "$current_title" "$current_text"
      fi
      in_learnings=false
      in_entry=false
      continue
    fi

    if [ "$in_learnings" = false ]; then
      continue
    fi

    # Detect learning entries by ### heading pattern
    if [[ "$line" =~ ^###[[:space:]]([0-9]{4}-[0-9]{2}-[0-9]{2})[[:space:]]—[[:space:]](.*) ]]; then
      # Process previous entry
      if [ -n "$current_id" ] && [ "$in_entry" = true ]; then
        _process_claude_entry "$current_id" "$current_title" "$current_text"
      fi
      current_id="${BASH_REMATCH[1]}"
      current_title="${BASH_REMATCH[2]}"
      current_text="$line"
      in_entry=true
      total_entries=$((total_entries + 1))
    elif [ "$in_entry" = true ]; then
      current_text+=$'\n'"$line"
    fi
  done < "$claude_file"

  # Process last entry
  if [ -n "$current_id" ] && [ "$in_entry" = true ]; then
    _process_claude_entry "$current_id" "$current_title" "$current_text"
  fi

  emit_simple_array candidates
}

_process_claude_entry() {
  local entry_date="$1"
  local entry_title="$2"
  local entry_text="$3"

  # Class-level learnings are never candidates (INV-008)
  echo "$entry_title" | grep -qE "Convention confirmed|Convention introduced|Postmortem" && return

  local paths
  paths="$(echo "$entry_text" | grep -oE '`[a-zA-Z_./-]+\.(sh|md|json|py|ts|js|yml|yaml)`' | sed 's/^`//;s/`$//' | sort -u)" || true
  [ -z "$paths" ] && return

  local dead_paths=() live_paths=()
  classify_paths "$paths"

  if [ ${#live_paths[@]} -eq 0 ] && [ ${#dead_paths[@]} -gt 0 ]; then
    local candidate
    candidate="$(emit_candidate "$entry_date — $entry_title" "claude-md" "All referenced files are dead" "high" \
      "$(paths_to_json_array "${dead_paths[@]}")" "[]" "false")"
    candidates+=("$candidate")
  fi
}

# ---- artifacts ----
scan_artifacts() {
  local artifacts_dir="$BASE_DIR/.correctless/artifacts"
  if [ ! -d "$artifacts_dir" ]; then
    echo "[]"
    return
  fi

  local branches
  branches="$(load_branches)"

  # Compute slugs for all branches
  local branch_slugs=()
  while IFS= read -r branch; do
    [ -z "$branch" ] && continue
    [[ "$branch" == *"HEAD"* ]] && continue
    local slug
    slug="$(branch_slug "$branch" 2>/dev/null)" || continue
    branch_slugs+=("$slug")
  done <<< "$branches"

  # Check each artifact file
  local candidates=()
  local artifact_patterns="workflow-state-*.json token-log-*.jsonl qa-findings-*.json audit-trail-*.jsonl pipeline-manifest-*.json autonomous-decisions-*.jsonl escalation-*.json adherence-*.json"

  for artifact in "$artifacts_dir"/*; do
    [ -f "$artifact" ] || continue
    local fname
    fname="$(basename "$artifact")"

    # Only check files that look like branch-scoped artifacts
    local is_branch_scoped=false
    for pattern in $artifact_patterns; do
      # shellcheck disable=SC2254
      case "$fname" in
        $pattern) is_branch_scoped=true; break ;;
      esac
    done

    [ "$is_branch_scoped" = true ] || continue

    # Check if any branch slug appears in the filename
    local found=false
    for slug in "${branch_slugs[@]}"; do
      if [[ "$fname" == *"$slug"* ]]; then
        found=true
        break
      fi
    done

    if [ "$found" = false ]; then
      local candidate
      candidate="$(emit_candidate "$fname" "artifacts" "Artifact for deleted/unknown branch" "low" \
        "$(paths_to_json_array ".correctless/artifacts/$fname")" "[]" "false")"
      candidates+=("$candidate")
    fi
  done

  emit_simple_array candidates
}

# ---- deferred ----
scan_deferred() {
  local def_file="$BASE_DIR/.correctless/meta/deferred-findings.json"
  if [ ! -f "$def_file" ]; then
    echo "[]"
    return
  fi

  local findings
  findings="$(jq -c '.[] | select(.status == "open")' "$def_file" 2>/dev/null)" || { echo "[]"; return; }

  local candidates=()
  while IFS= read -r finding; do
    [ -z "$finding" ] && continue
    local fid source_file
    fid="$(echo "$finding" | jq -r '.id' 2>/dev/null)"
    source_file="$(echo "$finding" | jq -r '.source_file // empty' 2>/dev/null)"

    [ -z "$source_file" ] && continue

    if ! file_exists "$source_file"; then
      local candidate
      candidate="$(emit_candidate "$fid" "deferred" "Source review artifact deleted" "medium" \
        "$(paths_to_json_array "$source_file")" "[]" "false")"
      candidates+=("$candidate")
    fi
  done <<< "$findings"

  emit_simple_array candidates
}

# ---- counts ----
scan_counts() {
  local agent_ctx="$BASE_DIR/.correctless/AGENT_CONTEXT.md"
  if [ ! -f "$agent_ctx" ]; then
    echo "[]"
    return
  fi

  local candidates=()

  # Count actual files
  local actual_tests actual_scripts actual_skills actual_agents
  actual_tests="$(find "$BASE_DIR/tests" -name 'test-*.sh' 2>/dev/null | wc -l | tr -d ' ')" || actual_tests=0
  actual_scripts="$(find "$BASE_DIR/scripts" -name '*.sh' 2>/dev/null | wc -l | tr -d ' ')" || actual_scripts=0
  actual_skills="$(find "$BASE_DIR/skills" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')" || actual_skills=0
  actual_agents="$(find "$BASE_DIR/agents" -name '*.md' 2>/dev/null | wc -l | tr -d ' ')" || actual_agents=0

  local content
  content="$(cat "$agent_ctx")"

  # Extract stated counts using label-anchored matching (INV-006)
  # Check each resource type: label, stated count, actual count
  local label stated actual
  for label in skills tests scripts agents; do
    stated="$(echo "$content" | grep -oE "[0-9]+ ${label%s}" | head -1 | grep -oE '[0-9]+')" || stated=""
    case "$label" in
      skills)  actual="$actual_skills" ;;
      tests)   actual="$actual_tests" ;;
      scripts) actual="$actual_scripts" ;;
      agents)  actual="$actual_agents" ;;
    esac
    if [ -n "$stated" ] && [ "$stated" != "$actual" ]; then
      local candidate
      candidate="$(emit_candidate "${label}-count" "counts" "Stated $stated ${label} but found $actual" "low" "[]" "[]" "false")"
      candidates+=("$candidate")
    fi
  done

  emit_simple_array candidates
}

# ---- crossrefs ----
scan_crossrefs() {
  local arch_file="$BASE_DIR/.correctless/ARCHITECTURE.md"
  if [ ! -f "$arch_file" ]; then
    echo "[]"
    return
  fi

  local candidates=()
  local current_id=""
  local current_text=""
  local in_entry=false

  while IFS= read -r line; do
    if [[ "$line" =~ ^###[[:space:]]+(ABS|PAT|TB|ENV)-([0-9]+[a-z]?):.* ]]; then
      if [ -n "$current_id" ] && [ "$in_entry" = true ]; then
        _process_crossref_entry "$current_id" "$current_text"
      fi
      current_id="${BASH_REMATCH[1]}-${BASH_REMATCH[2]}"
      current_text="$line"
      in_entry=true
    elif [[ "$line" =~ ^####[[:space:]]+(ABS|PAT|TB|ENV)-([0-9]+[a-z]):.* ]]; then
      if [ "$in_entry" = true ]; then
        current_text+=$'\n'"$line"
      fi
    elif [[ "$line" =~ ^###[[:space:]] ]] && [ "$in_entry" = true ]; then
      _process_crossref_entry "$current_id" "$current_text"
      current_id=""
      current_text=""
      in_entry=false
    elif [ "$in_entry" = true ]; then
      current_text+=$'\n'"$line"
    fi
  done < "$arch_file"

  if [ -n "$current_id" ] && [ "$in_entry" = true ]; then
    _process_crossref_entry "$current_id" "$current_text"
  fi

  emit_simple_array candidates
}

_process_crossref_entry() {
  local entry_id="$1"
  local entry_text="$2"

  local paths
  paths="$(extract_file_paths "$entry_text" | sort -u)"
  [ -z "$paths" ] && return

  local dead_paths=() live_paths=()
  classify_paths "$paths"

  # Cross-ref: entry has BOTH live and dead paths — stale cross-ref, not archive candidate
  if [ ${#live_paths[@]} -gt 0 ] && [ ${#dead_paths[@]} -gt 0 ]; then
    local candidate
    candidate="$(emit_candidate "$entry_id" "crossrefs" "Stale cross-references to deleted files" "medium" \
      "$(paths_to_json_array "${dead_paths[@]}")" "$(paths_to_json_array "${live_paths[@]}")" "false")"
    candidates+=("$candidate")
  fi
}

# ---- specs ----
scan_specs() {
  local specs_dir="$BASE_DIR/.correctless/specs"
  if [ ! -d "$specs_dir" ]; then
    echo "[]"
    return
  fi

  local branches
  branches="$(load_branches)"

  local now_epoch
  now_epoch="$(date +%s)"
  local thirty_days=$((30 * 86400))
  local ninety_days=$((90 * 86400))

  local candidates=()

  for spec_file in "$specs_dir"/*.md; do
    [ -f "$spec_file" ] || continue
    local spec_name
    spec_name="$(basename "$spec_file" .md)"

    # Skip archived specs
    [ -d "$specs_dir/archived" ] && [ -f "$specs_dir/archived/$spec_name.md" ] && continue

    # Extract branch from spec metadata
    local spec_branch=""
    spec_branch="$(grep -E '^\- \*\*Branch\*\*:' "$spec_file" 2>/dev/null | sed 's/.*: //' | tr -d ' ')" || true
    [ -z "$spec_branch" ] && continue

    # Check if branch still exists
    local branch_exists=false
    while IFS= read -r b; do
      b="$(echo "$b" | tr -d ' ')"
      [ -z "$b" ] && continue
      if [ "$b" = "$spec_branch" ]; then
        branch_exists=true
        break
      fi
    done <<< "$branches"

    # If branch still exists, not a candidate (INV-009)
    [ "$branch_exists" = true ] && continue

    # Branch is gone — try to find merge date
    # Priority 1: git log search for branch name in commit messages
    local merge_date_str=""
    merge_date_str="$(cd "$BASE_DIR" && git log --all --grep="$spec_branch" --format='%ci' 2>/dev/null | head -1)" || true

    # Priority 2: fall back to workflow state started_at
    if [ -z "$merge_date_str" ]; then
      # Look for workflow state file
      local state_files
      state_files="$(find "$BASE_DIR/.correctless/artifacts" -name "workflow-state-*" -type f 2>/dev/null)" || true
      while IFS= read -r sf; do
        [ -z "$sf" ] && continue
        local sf_task
        sf_task="$(jq -r '.task // empty' "$sf" 2>/dev/null)" || continue
        if [ "$sf_task" = "$spec_name" ]; then
          merge_date_str="$(jq -r '.started_at // empty' "$sf" 2>/dev/null)" || true
          break
        fi
      done <<< "$state_files"
    fi

    # Priority 3: if no date, skip (fail-closed per INV-009)
    if [ -z "$merge_date_str" ]; then
      continue
    fi

    # Parse merge date to epoch
    local merge_epoch
    merge_epoch="$(date -d "$merge_date_str" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$merge_date_str" +%s 2>/dev/null || date -j -f "%Y-%m-%d %H:%M:%S %z" "$merge_date_str" +%s 2>/dev/null)" || continue

    local age=$((now_epoch - merge_epoch))

    if [ "$age" -ge "$thirty_days" ]; then
      local risk="medium"
      if [ "$age" -ge "$ninety_days" ]; then
        risk="low"  # 90+ days = auto-execute in autonomous mode
      fi

      local candidate
      candidate="$(emit_candidate "$spec_name" "specs" "Spec for merged branch ($spec_branch), ${age} seconds post-merge" "$risk" \
        "$(paths_to_json_array ".correctless/specs/$spec_name.md")" "[]" "false")"
      candidates+=("$candidate")
    fi
  done

  emit_simple_array candidates
}

# ---- driftdebt ----
scan_driftdebt() {
  local debt_file="$BASE_DIR/.correctless/meta/drift-debt.json"
  if [ ! -f "$debt_file" ]; then
    echo "[]"
    return
  fi

  local now_epoch
  now_epoch="$(date +%s)"
  local ninety_days=$((90 * 86400))

  local candidates=()

  local entries
  entries="$(jq -c '.[]' "$debt_file" 2>/dev/null)" || { echo "[]"; return; }

  while IFS= read -r entry; do
    [ -z "$entry" ] && continue
    local status eid resolved_at created_at
    status="$(echo "$entry" | jq -r '.status // empty')"
    eid="$(echo "$entry" | jq -r '.id // empty')"

    # Only flag resolved or wont-fix entries (INV-014)
    if [ "$status" != "resolved" ] && [ "$status" != "wont-fix" ]; then
      continue
    fi

    # Use resolved_at if available, else created_at
    resolved_at="$(echo "$entry" | jq -r '.resolved_at // empty')"
    created_at="$(echo "$entry" | jq -r '.created_at // empty')"
    local date_str="${resolved_at:-$created_at}"
    [ -z "$date_str" ] && continue

    local entry_epoch
    entry_epoch="$(date -d "$date_str" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$date_str" +%s 2>/dev/null)" || continue

    local age=$((now_epoch - entry_epoch))
    if [ "$age" -ge "$ninety_days" ]; then
      local candidate
      candidate="$(emit_candidate "$eid" "driftdebt" "Resolved/wont-fix drift debt older than 90 days" "low" "[]" "[]" "false")"
      candidates+=("$candidate")
    fi
  done <<< "$entries"

  emit_simple_array candidates
}

# ============================================
# STEP 5: Dispatch to category scanner
# ============================================

case "${CATEGORY}" in
  architecture) scan_architecture ;;
  antipatterns) scan_antipatterns ;;
  claude-md) scan_claude_md ;;
  artifacts) scan_artifacts ;;
  deferred) scan_deferred ;;
  counts) scan_counts ;;
  crossrefs) scan_crossrefs ;;
  specs) scan_specs ;;
  driftdebt) scan_driftdebt ;;
  *)
    echo "[]"
    ;;
esac
