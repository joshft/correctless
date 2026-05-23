#!/usr/bin/env bash
# Correctless — Cross-Feature Intelligence Aggregation
# Reads 6 data sources and produces a JSON brief for /cspec brainstorm.
# PAT-003: lives in scripts/, accepts CLI arguments, outputs JSON to stdout, exits 0 always.
#
# Usage:
#   bash scripts/cross-feature-intel.sh --base .correctless [--scope "file1.sh,file2.sh"]
#
# Data sources:
#   1. .correctless/meta/deferred-findings.json     — open deferred review findings
#   2. .correctless/artifacts/devadv/report-*.md     — Devil's Advocate reports
#   3. .correctless/meta/overrides/*.json            — override history
#   4. .correctless/artifacts/lens-recommendations-*.json — lens recommendation artifacts
#   5. .correctless/artifacts/debug-investigation-*.md — debug investigations
#   6. .correctless/meta/workflow-effectiveness.json  — phase effectiveness history
#
# ABS-037: This script is the sole writer of .correctless/meta/cross-feature-intel.json

# Source shared utilities (lib.sh)
_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
if [ -f "$_SCRIPT_DIR/lib.sh" ]; then
  # shellcheck source=lib.sh
  source "$_SCRIPT_DIR/lib.sh"
fi

# ============================================================================
# EA-001: jq availability check
# ============================================================================

if ! command -v jq >/dev/null 2>&1; then
  echo '{"error": "jq not found"}'
  exit 0
fi

# ============================================================================
# CLI argument parsing (PAT-003: CLI arguments, not stdin JSON)
# ============================================================================

BASE_DIR=""
SCOPE_ARG=""

while [ $# -gt 0 ]; do
  case "$1" in
    --base)
      BASE_DIR="$2"
      shift 2
      ;;
    --scope)
      SCOPE_ARG="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

if [ -z "$BASE_DIR" ]; then
  BASE_DIR=".correctless"
fi

# ============================================================================
# Date arithmetic helpers (EA-003: GNU-first-BSD-fallback)
# ============================================================================

# Convert ISO-8601 date string to epoch seconds
_date_to_epoch() {
  local datestr="$1"
  local epoch=""

  # GNU date -d
  epoch="$(date -d "$datestr" +%s 2>/dev/null)" \
    || epoch="$(date -jf "%Y-%m-%dT%H:%M:%SZ" "$datestr" +%s 2>/dev/null)" \
    || epoch="$(date -jf "%Y-%m-%d" "$datestr" +%s 2>/dev/null)" \
    || epoch=""

  echo "$epoch"
}

# Get file mtime as epoch seconds
_file_mtime_epoch() {
  local filepath="$1"
  local epoch=""

  # GNU stat -c '%Y'
  epoch="$(stat -c '%Y' "$filepath" 2>/dev/null)" \
    || epoch="$(stat -f '%m' "$filepath" 2>/dev/null)" \
    || epoch=""

  echo "$epoch"
}

# Current epoch
_now_epoch() {
  date +%s 2>/dev/null
}

# 90-day staleness threshold in seconds
STALENESS_THRESHOLD=$((90 * 24 * 60 * 60))

# Check if a date is within 90 days
_is_within_90_days() {
  local date_epoch="$1"
  local now_epoch
  now_epoch="$(_now_epoch)"

  if [ -z "$date_epoch" ] || [ -z "$now_epoch" ]; then
    # If we can't determine dates, include the entry (fail-open for advisory data)
    return 0
  fi

  local age=$(( now_epoch - date_epoch ))
  [ "$age" -le "$STALENESS_THRESHOLD" ]
}

# Truncate a string to max_len characters
_truncate() {
  local str="$1"
  local max_len="${2:-200}"
  if [ "${#str}" -gt "$max_len" ]; then
    echo "${str:0:$max_len}"
  else
    echo "$str"
  fi
}

# ============================================================================
# Scope filtering helpers
# ============================================================================

# Parse scope argument into an array
declare -a SCOPE_FILES=()
if [ -n "$SCOPE_ARG" ]; then
  IFS=',' read -ra SCOPE_FILES <<< "$SCOPE_ARG"
fi

# Check if any file_ref overlaps with scope (exact string equality after normalization)
_file_refs_overlap_scope() {
  local refs_json="$1"
  # If no scope set, include everything
  if [ ${#SCOPE_FILES[@]} -eq 0 ]; then
    return 0
  fi
  # If refs is empty array, include unconditionally (project-wide)
  local ref_count
  ref_count=$(echo "$refs_json" | jq 'length' 2>/dev/null)
  if [ "$ref_count" = "0" ] || [ -z "$ref_count" ]; then
    return 0
  fi
  # Check overlap
  local ref
  for ref in $(echo "$refs_json" | jq -r '.[]' 2>/dev/null); do
    for scope_file in "${SCOPE_FILES[@]}"; do
      if [ "$ref" = "$scope_file" ]; then
        return 0
      fi
    done
  done
  return 1
}

# ============================================================================
# Warnings accumulator
# ============================================================================
# Use a temp file because extraction functions run in subshells ($())
# which cannot modify the parent's array variables.

WARNINGS_FILE=$(mktemp "${TMPDIR:-/tmp}/cfi-warnings.XXXXXX")
_cleanup_warnings() { rm -f "$WARNINGS_FILE"; }
trap _cleanup_warnings EXIT

_add_warning() {
  echo "$1" >> "$WARNINGS_FILE"
}

# ============================================================================
# Source 1: Deferred findings (.correctless/meta/deferred-findings.json)
# ============================================================================

_extract_deferred_findings() {
  local src="$BASE_DIR/meta/deferred-findings.json"
  local entries="[]"

  if [ ! -f "$src" ]; then
    echo "$entries"
    return
  fi

  # Validate JSON
  if ! jq -e '.' "$src" >/dev/null 2>&1; then
    _add_warning "skipped corrupted deferred-findings.json: invalid JSON"
    echo "$entries"
    return
  fi

  # Extract open findings, map to brief format
  entries=$(jq -r --arg now_epoch "$(_now_epoch)" --arg threshold "$STALENESS_THRESHOLD" '
    [.findings[]
     | select(.status == "open")
     | {
         id: .id,
         date: .deferred_at,
         summary: (.description[:200]),
         file_refs: [],
         severity: .severity,
         source: "deferred-findings.json"
       }
    ]
  ' "$src" 2>/dev/null) || {
    _add_warning "error processing deferred-findings.json"
    entries="[]"
  }

  echo "$entries"
}

# ============================================================================
# Source 2: Devil's Advocate reports (.correctless/artifacts/devadv/report-*.md)
# ============================================================================

_extract_devadv_themes() {
  local devadv_dir="$BASE_DIR/artifacts/devadv"
  local entries="[]"

  if [ ! -d "$devadv_dir" ]; then
    echo "$entries"
    return
  fi

  local all_entries="["
  local first=true

  for report in "$devadv_dir"/report-*.md; do
    [ -f "$report" ] || continue

    local filename
    filename=$(basename "$report")

    # Parse date from filename: report-YYYY-MM-DD.md
    local file_date=""
    if [[ "$filename" =~ report-([0-9]{4}-[0-9]{2}-[0-9]{2})\.md$ ]]; then
      file_date="${BASH_REMATCH[1]}"
    else
      # Fallback to file mtime
      local mtime_epoch
      mtime_epoch=$(_file_mtime_epoch "$report")
      if [ -n "$mtime_epoch" ]; then
        file_date=$(date -d "@$mtime_epoch" +%Y-%m-%d 2>/dev/null) \
          || file_date=$(date -r "$mtime_epoch" +%Y-%m-%d 2>/dev/null) \
          || file_date="unknown"
      fi
    fi

    # Extract DA-NNN headings
    while IFS= read -r line; do
      if [[ "$line" =~ ^##[[:space:]]+(DA-[0-9]+):[[:space:]]*(.*) ]]; then
        local da_id="${BASH_REMATCH[1]}"
        local da_title="${BASH_REMATCH[2]}"
        local da_summary
        da_summary=$(_truncate "$da_title" 200)

        # Parse severity — handle both formats
        # Format 1 (inline): **Severity:** value
        # Format 2 (subsection): ### Severity\nvalue
        local severity="null"
        local da_section_content=""

        # Read lines after this DA heading until next ## heading
        local reading=false
        while IFS= read -r sline; do
          if [[ "$sline" =~ ^##[[:space:]] ]] && [ "$reading" = true ]; then
            break
          fi
          if [[ "$sline" == "$line" ]]; then
            reading=true
            continue
          fi
          if [ "$reading" = true ]; then
            da_section_content+="$sline"$'\n'
          fi
        done < "$report"

        # Try inline format: **Severity:** value
        local inline_sev
        inline_sev=$(echo "$da_section_content" | grep -o '\*\*Severity:\*\*[[:space:]]*[^ ]*' | head -1 | sed 's/\*\*Severity:\*\*[[:space:]]*//')
        if [ -n "$inline_sev" ]; then
          severity="$inline_sev"
        else
          # Try subsection format: ### Severity\nvalue
          local subsec_sev
          subsec_sev=$(echo "$da_section_content" | awk '/^### Severity/{getline; if(NF>0) print; exit}')
          if [ -n "$subsec_sev" ]; then
            severity="$subsec_sev"
          fi
        fi

        # Build JSON entry
        if [ "$first" = true ]; then
          first=false
        else
          all_entries+=","
        fi

        # Escape strings for JSON
        local json_summary
        json_summary=$(echo "$da_summary" | jq -Rs '.' 2>/dev/null)
        local json_severity
        if [ "$severity" = "null" ]; then
          json_severity="null"
        else
          json_severity=$(echo "$severity" | jq -Rs '.' 2>/dev/null)
        fi

        all_entries+="{\"id\":\"$da_id\",\"date\":\"$file_date\",\"summary\":$json_summary,\"file_refs\":[],\"severity\":$json_severity,\"source\":\"$filename\"}"
      fi
    done < "$report"
  done

  all_entries+="]"
  echo "$all_entries"
}

# ============================================================================
# Source 3: Override patterns (.correctless/meta/overrides/*.json)
# ============================================================================

_extract_override_patterns() {
  local overrides_dir="$BASE_DIR/meta/overrides"
  local entries="[]"

  if [ ! -d "$overrides_dir" ]; then
    echo "$entries"
    return
  fi

  # Collect all override reasons with their dates
  local all_reasons="["
  local first=true

  for override_file in "$overrides_dir"/*.json; do
    [ -f "$override_file" ] || continue

    if ! jq -e '.' "$override_file" >/dev/null 2>&1; then
      _add_warning "skipped corrupted $(basename "$override_file"): invalid JSON"
      continue
    fi

    local completed_at
    completed_at=$(jq -r '.completed_at // empty' "$override_file" 2>/dev/null)

    # Extract each override reason
    while IFS= read -r reason; do
      [ -z "$reason" ] && continue
      if [ "$first" = true ]; then
        first=false
      else
        all_reasons+=","
      fi
      local json_reason
      json_reason=$(echo "$reason" | jq -Rs '.' 2>/dev/null)
      all_reasons+="{\"reason\":$json_reason,\"date\":\"$completed_at\"}"
    done < <(jq -r '.overrides[].reason' "$override_file" 2>/dev/null)
  done

  all_reasons+="]"

  # Collapse by reason hash (first 8 chars of sha256)
  entries=$(echo "$all_reasons" | jq '
    group_by(.reason)
    | map({
        id: (.[0].reason | @base64 | .[0:8]),
        date: (sort_by(.date) | reverse | .[0].date),
        summary: (.[0].reason[:200]),
        file_refs: [],
        severity: null,
        source: "overrides",
        count: length
      })
  ' 2>/dev/null)

  # Fix id to be sha256 hash instead of base64
  # Use a jq-native approach: hash the reason string
  local final_entries="["
  local efirst=true

  while IFS= read -r entry_json; do
    [ -z "$entry_json" ] && continue
    local reason_text
    reason_text=$(echo "$entry_json" | jq -r '.summary' 2>/dev/null)
    local reason_hash
    reason_hash=$(echo -n "$reason_text" | sha256sum 2>/dev/null | head -c 8)
    if [ -z "$reason_hash" ]; then
      reason_hash=$(echo -n "$reason_text" | shasum -a 256 2>/dev/null | head -c 8)
    fi

    if [ "$efirst" = true ]; then
      efirst=false
    else
      final_entries+=","
    fi

    final_entries+=$(echo "$entry_json" | jq --arg id "$reason_hash" '.id = $id' 2>/dev/null)
  done < <(echo "$entries" | jq -c '.[]' 2>/dev/null)

  final_entries+="]"
  echo "$final_entries"
}

# ============================================================================
# Source 4: Lens recommendations (.correctless/artifacts/lens-recommendations-*.json)
# ============================================================================

_extract_lens_recommendations() {
  local artifacts_dir="$BASE_DIR/artifacts"
  local entries="[]"

  local all_lenses="["
  local first=true

  for lens_file in "$artifacts_dir"/lens-recommendations-*.json; do
    [ -f "$lens_file" ] || continue

    if ! jq -e '.' "$lens_file" >/dev/null 2>&1; then
      _add_warning "skipped corrupted $(basename "$lens_file"): invalid JSON"
      continue
    fi

    local file_mtime
    file_mtime=$(_file_mtime_epoch "$lens_file")
    local file_date=""
    if [ -n "$file_mtime" ]; then
      file_date=$(date -d "@$file_mtime" +%Y-%m-%d 2>/dev/null) \
        || file_date=$(date -r "$file_mtime" +%Y-%m-%d 2>/dev/null) \
        || file_date="unknown"
    fi

    while IFS= read -r lens_entry; do
      [ -z "$lens_entry" ] && continue
      local lens_name
      lens_name=$(echo "$lens_entry" | jq -r '.lens_name' 2>/dev/null)
      local rationale
      rationale=$(echo "$lens_entry" | jq -r '.rationale' 2>/dev/null)

      if [ "$first" = true ]; then
        first=false
      else
        all_lenses+=","
      fi

      local json_rationale
      json_rationale=$(echo "$rationale" | jq -Rs '.' 2>/dev/null)
      all_lenses+="{\"lens_name\":\"$lens_name\",\"rationale\":$json_rationale,\"date\":\"$file_date\"}"
    done < <(jq -c '.recommended_lenses[]' "$lens_file" 2>/dev/null)
  done

  all_lenses+="]"

  # Collapse by lens_name with count and promotion_candidate
  entries=$(echo "$all_lenses" | jq '
    group_by(.lens_name)
    | map({
        id: .[0].lens_name,
        date: (sort_by(.date) | reverse | .[0].date),
        summary: (.[0].rationale[:200]),
        file_refs: [],
        severity: null,
        source: "lens-recommendations",
        count: length,
        promotion_candidate: (length >= 3)
      })
    | map(if .promotion_candidate == false then del(.promotion_candidate) else . end)
  ' 2>/dev/null) || entries="[]"

  echo "$entries"
}

# ============================================================================
# Source 5: Debug investigations (.correctless/artifacts/debug-investigation-*.md)
# ============================================================================

_extract_debug_clusters() {
  local artifacts_dir="$BASE_DIR/artifacts"
  local entries="[]"

  local all_entries="["
  local first=true

  for debug_file in "$artifacts_dir"/debug-investigation-*.md; do
    [ -f "$debug_file" ] || continue

    local filename
    filename=$(basename "$debug_file")

    # Extract slug from filename: debug-investigation-SLUG.md
    local slug=""
    if [[ "$filename" =~ ^debug-investigation-(.+)\.md$ ]]; then
      slug="${BASH_REMATCH[1]}"
    fi

    # Get file mtime for date
    local file_mtime
    file_mtime=$(_file_mtime_epoch "$debug_file")
    local file_date=""
    if [ -n "$file_mtime" ]; then
      file_date=$(date -d "@$file_mtime" +%Y-%m-%d 2>/dev/null) \
        || file_date=$(date -r "$file_mtime" +%Y-%m-%d 2>/dev/null) \
        || file_date="unknown"
    fi

    # Extract Root Cause text (or first ## heading as fallback)
    local summary=""
    local in_root_cause=false
    local root_cause_text=""
    local first_heading_text=""
    local found_first_heading=false

    while IFS= read -r line; do
      # Track first ## heading as fallback
      if [[ "$line" =~ ^##[[:space:]] ]] && [ "$found_first_heading" = false ]; then
        found_first_heading=true
        first_heading_text="${line#\#\# }"
      fi

      # Look for Root Cause section
      if [[ "$line" =~ ^##[[:space:]]+Root[[:space:]]+Cause ]]; then
        in_root_cause=true
        continue
      fi

      if [ "$in_root_cause" = true ]; then
        if [[ "$line" =~ ^## ]]; then
          break
        fi
        if [ -n "$line" ] && [ -z "$root_cause_text" ]; then
          root_cause_text="$line"
        fi
      fi
    done < "$debug_file"

    if [ -n "$root_cause_text" ]; then
      summary=$(_truncate "$root_cause_text" 200)
    elif [ -n "$first_heading_text" ]; then
      summary=$(_truncate "$first_heading_text" 200)
    fi

    # Extract file_refs from Fix/Class Fix sections via regex
    # INV-012: regex (scripts/[^ )]+|hooks/[^ )]+|skills/[^ )]+|tests/[^ )]+|\.correctless/[^ )]+)
    local in_fix=false
    local fix_text=""

    while IFS= read -r line; do
      if [[ "$line" =~ ^##[[:space:]]+(Fix|Class[[:space:]]+Fix) ]]; then
        in_fix=true
        continue
      fi
      if [ "$in_fix" = true ]; then
        if [[ "$line" =~ ^## ]] && ! [[ "$line" =~ ^##[[:space:]]+(Fix|Class[[:space:]]+Fix) ]]; then
          # Don't break on "Class Fix" heading if we're reading "Fix"
          if ! [[ "$line" =~ ^##[[:space:]]+Class[[:space:]]+Fix ]]; then
            in_fix=false
          fi
        fi
        fix_text+="$line"$'\n'
      fi
    done < "$debug_file"

    # Extract paths matching project conventions
    local refs_array="["
    local refs_first=true
    while IFS= read -r ref; do
      [ -z "$ref" ] && continue
      if [ "$refs_first" = true ]; then
        refs_first=false
      else
        refs_array+=","
      fi
      refs_array+="\"$ref\""
    done < <(echo "$fix_text" | grep -oE '(scripts/[^ )]+|hooks/[^ )]+|skills/[^ )]+|tests/[^ )]+|\.correctless/[^ )]+)' 2>/dev/null | sort -u)
    refs_array+="]"

    if [ "$first" = true ]; then
      first=false
    else
      all_entries+=","
    fi

    local json_summary
    json_summary=$(echo "$summary" | jq -Rs '.' 2>/dev/null)

    all_entries+="{\"id\":\"$slug\",\"date\":\"$file_date\",\"summary\":$json_summary,\"file_refs\":$refs_array,\"severity\":null,\"source\":\"$filename\"}"
  done

  all_entries+="]"
  echo "$all_entries"
}

# ============================================================================
# Source 6: Phase effectiveness (.correctless/meta/workflow-effectiveness.json)
# ============================================================================

_extract_phase_effectiveness() {
  local src="$BASE_DIR/meta/workflow-effectiveness.json"
  local entries="[]"

  if [ ! -f "$src" ]; then
    echo "$entries"
    return
  fi

  if ! jq -e '.' "$src" >/dev/null 2>&1; then
    _add_warning "skipped corrupted workflow-effectiveness.json: invalid JSON"
    echo "$entries"
    return
  fi

  # Extract and collapse by phase_that_should_have_caught
  entries=$(jq '
    [.post_merge_bugs
     | group_by(.phase_that_should_have_caught)
     | .[]
     | {
         id: .[0].phase_that_should_have_caught,
         date: (sort_by(.date) | reverse | .[0].date),
         summary: (
           if length == 1 then
             "\(.[0].severity) bug missed by \(.[0].phase_that_should_have_caught) phase: \(.[0].description[:150])"
           else
             "\(length) bugs missed by \(.[0].phase_that_should_have_caught) phase (severities: \([.[].severity] | unique | join(", ")))"
           end
           | .[:200]
         ),
         file_refs: [],
         severity: (sort_by(.severity) | reverse | .[0].severity),
         source: "workflow-effectiveness.json",
         count: length
       }
    ]
  ' "$src" 2>/dev/null) || {
    _add_warning "error processing workflow-effectiveness.json"
    entries="[]"
  }

  echo "$entries"
}

# ============================================================================
# Aggregation: collect, filter, sort, cap
# ============================================================================

# Collect all sections
deferred_findings=$(_extract_deferred_findings)
devadv_themes=$(_extract_devadv_themes)
override_patterns=$(_extract_override_patterns)
lens_recommendations=$(_extract_lens_recommendations)
debug_clusters=$(_extract_debug_clusters)
phase_effectiveness=$(_extract_phase_effectiveness)

# ============================================================================
# INV-003: Recency filter — exclude entries older than 90 days
# ============================================================================

_filter_by_recency() {
  local section_json="$1"
  local now_epoch
  now_epoch=$(_now_epoch)

  echo "$section_json" | jq --arg now "$now_epoch" --arg threshold "$STALENESS_THRESHOLD" '
    map(
      select(
        (.date // "") as $d |
        if $d == "" or $d == "unknown" or $d == "null" then true
        else
          # Try to parse date — include if we cant parse (fail-open)
          ($d | split("T") | .[0]) as $date_part |
          if ($date_part | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$")) then
            # Use now_epoch and threshold for comparison
            # jq cant do epoch conversion natively, so we mark for shell filtering
            true
          else true
          end
        end
      )
    )
    | sort_by(.date) | reverse
  ' 2>/dev/null
}

# Shell-based recency filter (since jq can't do epoch math portably)
_shell_recency_filter() {
  local section_json="$1"
  local now_epoch
  now_epoch=$(_now_epoch)
  local filtered="["
  local first=true

  while IFS= read -r entry; do
    [ -z "$entry" ] && continue
    local entry_date
    entry_date=$(echo "$entry" | jq -r '.date // ""' 2>/dev/null)

    if [ -z "$entry_date" ] || [ "$entry_date" = "unknown" ] || [ "$entry_date" = "null" ]; then
      # Include entries without dates (fail-open for advisory data)
      if [ "$first" = true ]; then first=false; else filtered+=","; fi
      filtered+="$entry"
      continue
    fi

    local entry_epoch
    entry_epoch=$(_date_to_epoch "$entry_date")

    if [ -z "$entry_epoch" ]; then
      # Can't parse date — include (fail-open)
      if [ "$first" = true ]; then first=false; else filtered+=","; fi
      filtered+="$entry"
      continue
    fi

    local age=$(( now_epoch - entry_epoch ))
    if [ "$age" -le "$STALENESS_THRESHOLD" ]; then
      if [ "$first" = true ]; then first=false; else filtered+=","; fi
      filtered+="$entry"
    fi
  done < <(echo "$section_json" | jq -c '.[]' 2>/dev/null)

  filtered+="]"
  echo "$filtered"
}

# Sort by recency (newest first) within each section
_sort_by_recency() {
  local section_json="$1"
  echo "$section_json" | jq 'sort_by(.date) | reverse' 2>/dev/null
}

# Apply recency filter and sort to each section
deferred_findings=$(_shell_recency_filter "$deferred_findings")
deferred_findings=$(_sort_by_recency "$deferred_findings")

devadv_themes=$(_shell_recency_filter "$devadv_themes")
devadv_themes=$(_sort_by_recency "$devadv_themes")

override_patterns=$(_shell_recency_filter "$override_patterns")
override_patterns=$(_sort_by_recency "$override_patterns")

lens_recommendations=$(_shell_recency_filter "$lens_recommendations")
lens_recommendations=$(_sort_by_recency "$lens_recommendations")

debug_clusters=$(_shell_recency_filter "$debug_clusters")
debug_clusters=$(_sort_by_recency "$debug_clusters")

phase_effectiveness=$(_shell_recency_filter "$phase_effectiveness")
phase_effectiveness=$(_sort_by_recency "$phase_effectiveness")

# ============================================================================
# INV-002: File-scope filtering
# ============================================================================

_apply_scope_filter() {
  local section_json="$1"

  if [ ${#SCOPE_FILES[@]} -eq 0 ]; then
    # No scope — include everything
    echo "$section_json"
    return
  fi

  local filtered="["
  local first=true

  while IFS= read -r entry; do
    [ -z "$entry" ] && continue
    local refs
    refs=$(echo "$entry" | jq -c '.file_refs' 2>/dev/null)

    if _file_refs_overlap_scope "$refs"; then
      if [ "$first" = true ]; then first=false; else filtered+=","; fi
      filtered+="$entry"
    fi
  done < <(echo "$section_json" | jq -c '.[]' 2>/dev/null)

  filtered+="]"
  echo "$filtered"
}

deferred_findings=$(_apply_scope_filter "$deferred_findings")
devadv_themes=$(_apply_scope_filter "$devadv_themes")
override_patterns=$(_apply_scope_filter "$override_patterns")
lens_recommendations=$(_apply_scope_filter "$lens_recommendations")
debug_clusters=$(_apply_scope_filter "$debug_clusters")
phase_effectiveness=$(_apply_scope_filter "$phase_effectiveness")

# ============================================================================
# INV-004: Brief size cap (30 entries, per-section minimum)
# ============================================================================

_apply_cap() {
  local cap=30

  # Count total entries across all sections
  local df_count of_count dv_count lr_count dc_count pe_count total
  df_count=$(echo "$deferred_findings" | jq 'length' 2>/dev/null || echo 0)
  dv_count=$(echo "$devadv_themes" | jq 'length' 2>/dev/null || echo 0)
  of_count=$(echo "$override_patterns" | jq 'length' 2>/dev/null || echo 0)
  lr_count=$(echo "$lens_recommendations" | jq 'length' 2>/dev/null || echo 0)
  dc_count=$(echo "$debug_clusters" | jq 'length' 2>/dev/null || echo 0)
  pe_count=$(echo "$phase_effectiveness" | jq 'length' 2>/dev/null || echo 0)
  total=$(( df_count + dv_count + of_count + lr_count + dc_count + pe_count ))

  if [ "$total" -le "$cap" ]; then
    TRUNCATED_COUNT=0
    return
  fi

  TRUNCATED_COUNT=$(( total - cap ))

  # Per-section minimum: each non-empty section keeps at least 1 (its most recent)
  # Count non-empty sections
  local non_empty=0
  [ "$df_count" -gt 0 ] && non_empty=$((non_empty + 1))
  [ "$dv_count" -gt 0 ] && non_empty=$((non_empty + 1))
  [ "$of_count" -gt 0 ] && non_empty=$((non_empty + 1))
  [ "$lr_count" -gt 0 ] && non_empty=$((non_empty + 1))
  [ "$dc_count" -gt 0 ] && non_empty=$((non_empty + 1))
  [ "$pe_count" -gt 0 ] && non_empty=$((non_empty + 1))

  local remaining_slots=$(( cap - non_empty ))

  # Collect all entries with section tags for global sort, excluding the per-section minimums
  local global_pool="["
  local gfirst=true

  for section_pair in \
    "deferred_findings:$deferred_findings" \
    "devadv_themes:$devadv_themes" \
    "override_patterns:$override_patterns" \
    "lens_recommendations:$lens_recommendations" \
    "debug_clusters:$debug_clusters" \
    "phase_effectiveness:$phase_effectiveness"; do

    local section_name="${section_pair%%:*}"
    local section_data="${section_pair#*:}"
    local scount
    scount=$(echo "$section_data" | jq 'length' 2>/dev/null || echo 0)

    if [ "$scount" -le 1 ]; then
      continue  # Already at minimum, nothing to add to pool
    fi

    # Skip first entry (already reserved as minimum), add rest to pool
    while IFS= read -r entry; do
      [ -z "$entry" ] && continue
      if [ "$gfirst" = true ]; then gfirst=false; else global_pool+=","; fi
      global_pool+=$(echo "$entry" | jq --arg sec "$section_name" '. + {"_section": $sec}' 2>/dev/null)
    done < <(echo "$section_data" | jq -c '.[1:][]' 2>/dev/null)
  done

  global_pool+="]"

  # Sort pool by date (newest first) and take top remaining_slots
  local selected
  selected=$(echo "$global_pool" | jq --argjson slots "$remaining_slots" '
    sort_by(.date) | reverse | .[:$slots]
  ' 2>/dev/null)

  # Reconstruct sections: minimum (first entry) + selected entries for that section
  for section_name in deferred_findings devadv_themes override_patterns lens_recommendations debug_clusters phase_effectiveness; do
    local current_var="${section_name}"
    local current_data
    eval "current_data=\$$current_var"
    local scount
    scount=$(echo "$current_data" | jq 'length' 2>/dev/null || echo 0)

    if [ "$scount" -eq 0 ]; then
      continue
    fi

    # Get minimum (first/most recent entry)
    local minimum
    minimum=$(echo "$current_data" | jq -c '.[0]' 2>/dev/null)

    # Get selected entries for this section
    local section_selected
    section_selected=$(echo "$selected" | jq -c --arg sec "$section_name" '[.[] | select(._section == $sec) | del(._section)]' 2>/dev/null)

    # Combine: minimum + selected
    # shellcheck disable=SC2034
    combined=$(jq -n --argjson min "[$minimum]" --argjson sel "$section_selected" '$min + $sel | sort_by(.date) | reverse' 2>/dev/null)

    eval "$current_var=\$combined"
  done
}

TRUNCATED_COUNT=0
_apply_cap

# ============================================================================
# Build output JSON
# ============================================================================

# Build scope array for output
scope_json="[]"
if [ ${#SCOPE_FILES[@]} -gt 0 ]; then
  scope_json=$(printf '%s\n' "${SCOPE_FILES[@]}" | jq -R . | jq -s . 2>/dev/null) || scope_json="[]"
fi

# Build warnings array from temp file
warnings_json="[]"
if [ -s "$WARNINGS_FILE" ]; then
  warnings_json=$(jq -R . < "$WARNINGS_FILE" | jq -s . 2>/dev/null) || warnings_json="[]"
fi

# Build generated_at timestamp
generated_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "unknown")

# Assemble final JSON
jq -n \
  --argjson schema_version 1 \
  --arg generated_at "$generated_at" \
  --argjson scope "$scope_json" \
  --argjson truncated_count "$TRUNCATED_COUNT" \
  --argjson warnings "$warnings_json" \
  --argjson df "$deferred_findings" \
  --argjson dv "$devadv_themes" \
  --argjson op "$override_patterns" \
  --argjson lr "$lens_recommendations" \
  --argjson dc "$debug_clusters" \
  --argjson pe "$phase_effectiveness" \
  '{
    schema_version: $schema_version,
    generated_at: $generated_at,
    scope: $scope,
    truncated_count: $truncated_count,
    warnings: $warnings,
    sections: {
      deferred_findings: $df,
      devadv_themes: $dv,
      override_patterns: $op,
      lens_recommendations: $lr,
      debug_clusters: $dc,
      phase_effectiveness: $pe
    }
  }'

exit 0
