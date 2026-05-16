#!/usr/bin/env bash
# ============================================================================
# sync-deferred-backlog.sh — Deferred findings backlog sync + validation
#
# Dual-purpose script:
#   1. Seed/re-sync: import pending findings from review artifacts into
#      .correctless/meta/deferred-findings.json
#   2. Validate: check a backlog file against the INV-001 schema
#
# Usage:
#   bash scripts/sync-deferred-backlog.sh [PROJECT_ROOT]
#   bash scripts/sync-deferred-backlog.sh --validate FILE
#
# The PROJECT_ROOT defaults to the current directory.
# ============================================================================

set -euo pipefail

# ============================================================================
# Validation mode
# ============================================================================

if [ "${1:-}" = "--validate" ]; then
  file="${2:-}"
  if [ -z "$file" ] || [ ! -f "$file" ]; then
    echo "Error: --validate requires a file path" >&2
    exit 1
  fi

  # Parse JSON
  if ! jq -e '.' "$file" >/dev/null 2>&1; then
    echo "Error: file is not valid JSON" >&2
    exit 1
  fi

  # schema_version must be 1
  if ! jq -e '.schema_version == 1' "$file" >/dev/null 2>&1; then
    echo "Error: schema_version must be 1" >&2
    exit 1
  fi

  # findings must be an array
  if ! jq -e '.findings | type == "array"' "$file" >/dev/null 2>&1; then
    echo "Error: .findings must be an array" >&2
    exit 1
  fi

  # Validate each finding entry
  errors=$(jq -r '
    .findings | to_entries[] |
    .key as $idx |
    .value as $f |
    (
      # Required fields check
      (if ($f | has("id","source_file","finding_id","feature","severity","description","category","status","deferred_at","resolved_at","resolution") | not) then
        "Entry \($idx): missing required field(s)"
      else empty end),

      # ID format: DF-NNN (zero-padded, 3 digits)
      (if ($f.id | test("^DF-[0-9]{3}$") | not) then
        "Entry \($idx): id must be zero-padded DF-NNN format (got \($f.id))"
      else empty end),

      # Severity enum: MEDIUM, LOW, ADVISORY only (PRH-003: no HIGH/CRITICAL)
      (if ($f.severity | IN("MEDIUM","LOW","ADVISORY") | not) then
        "Entry \($idx): severity must be MEDIUM, LOW, or ADVISORY (got \($f.severity))"
      else empty end),

      # Status enum: open, in-progress, resolved, wont-fix
      (if ($f.status | IN("open","in-progress","resolved","wont-fix") | not) then
        "Entry \($idx): status must be open, in-progress, resolved, or wont-fix (got \($f.status))"
      else empty end),

      # wont-fix requires non-empty resolution (INV-010)
      (if ($f.status == "wont-fix" and ($f.resolution == null or $f.resolution == "")) then
        "Entry \($idx): wont-fix status requires non-empty resolution"
      else empty end)
    )
  ' "$file" 2>/dev/null || echo "Error: jq validation failed")

  # Check duplicate IDs
  dup_ids=$(jq -r '[.findings[].id] | group_by(.) | map(select(length > 1)) | .[0][0] // empty' "$file" 2>/dev/null)

  if [ -n "$dup_ids" ]; then
    errors="${errors}${errors:+$'\n'}Duplicate id: $dup_ids"
  fi

  if [ -n "$errors" ]; then
    echo "Validation errors:" >&2
    echo "$errors" >&2
    exit 1
  fi

  echo "Validation passed"
  exit 0
fi

# ============================================================================
# Sync mode — import pending findings from review artifacts
# ============================================================================

PROJECT_ROOT="${1:-.}"

BACKLOG_FILE="$PROJECT_ROOT/.correctless/meta/deferred-findings.json"
ARTIFACTS_DIR="$PROJECT_ROOT/.correctless/artifacts"

# ============================================================================
# STEP 1: Ensure backlog file exists with schema wrapper (INV-003)
# ============================================================================

if [ -f "$BACKLOG_FILE" ]; then
  # Validate existing file is parseable — fail-closed for writers (BND-002)
  if ! jq -e '.findings | type == "array"' "$BACKLOG_FILE" >/dev/null 2>&1; then
    echo "Error: existing backlog file is corrupt — refusing to write (BND-002)" >&2
    exit 1
  fi

  # Validate no HIGH/CRITICAL in existing file (PRH-003)
  bad_sev=$(jq -r '[.findings[] | select(.severity == "HIGH" or .severity == "CRITICAL")] | length' "$BACKLOG_FILE" 2>/dev/null)
  if [ "${bad_sev:-0}" -gt 0 ]; then
    echo "Error: existing backlog file contains HIGH/CRITICAL entries — corrupt (PRH-003)" >&2
    exit 1
  fi
else
  mkdir -p "$(dirname "$BACKLOG_FILE")"
  echo '{"schema_version": 1, "findings": []}' > "$BACKLOG_FILE"
fi

# ============================================================================
# STEP 2: Collect existing dedup keys (source_file + finding_id)
# ============================================================================

existing_keys=$(jq -r '.findings[] | "\(.source_file)|\(.finding_id)"' "$BACKLOG_FILE" 2>/dev/null || true)

# Get the highest existing DF-NNN ID number
next_id=$(jq -r '[.findings[].id | ltrimstr("DF-") | tonumber] | max // 0' "$BACKLOG_FILE" 2>/dev/null || echo 0)

# ============================================================================
# STEP 3: Scan review artifacts for pending findings
# ============================================================================

imported=0
new_findings="[]"

scan_artifact() {
  local artifact_file="$1"
  local rel_path="${artifact_file#"$PROJECT_ROOT"/}"

  # Extract findings — look for heading patterns like ## RS-001: ... followed by
  # severity and status lines
  local in_finding=false
  local current_id=""
  local current_desc=""
  local current_severity=""
  local current_status=""
  local current_feature=""
  local finding_ordinal=0

  # Extract feature from filename: review-spec-findings-SLUG.md or review-findings-SLUG.md
  current_feature=$(basename "$artifact_file" .md | sed 's/^review-spec-findings-//;s/^review-findings-//')

  while IFS= read -r line; do
    # Match heading: ## RS-001: or ## Finding RS-001: (with optional word prefix)
    if echo "$line" | grep -qE '^##[[:space:]]+(Finding[[:space:]]+)?[A-Z]+-[0-9]+:'; then
      # If we were in a finding, process the previous one
      if [ "$in_finding" = true ] && [ -n "$current_id" ]; then
        process_finding "$rel_path" "$current_id" "$current_desc" "$current_severity" "$current_status" "$current_feature"
      fi

      in_finding=true
      finding_ordinal=$((finding_ordinal + 1))
      # Extract finding ID (first LETTERS-NNN pattern)
      current_id=$(echo "$line" | grep -oE '[A-Z]+-[0-9]+' | head -1)
      # Extract description (everything after the ID and colon, with optional Finding prefix)
      current_desc=$(echo "$line" | sed 's/^##[[:space:]]*\(Finding[[:space:]]*\)\{0,1\}[A-Z]*-[0-9]*:[[:space:]]*//')
      current_severity=""
      current_status=""
    elif echo "$line" | grep -qE '^##[[:space:]]'; then
      # Non-finding heading — process previous if any
      if [ "$in_finding" = true ] && [ -n "$current_id" ]; then
        process_finding "$rel_path" "$current_id" "$current_desc" "$current_severity" "$current_status" "$current_feature"
      fi
      in_finding=false
      current_id=""
    elif [ "$in_finding" = true ]; then
      # Extract severity
      if echo "$line" | grep -qi 'severity'; then
        current_severity=$(echo "$line" | grep -oE '(BLOCKING|HIGH|NON-BLOCKING|MEDIUM|LOW|INFORMATIONAL|ADVISORY)' | head -1)
      fi
      # Extract status
      if echo "$line" | grep -qi 'status'; then
        local extracted_status
        extracted_status=$(echo "$line" | grep -oiE '(pending|open|resolved|wont-fix|accepted)' | head -1 | tr '[:upper:]' '[:lower:]')
        if [ -n "$extracted_status" ]; then
          current_status="$extracted_status"
        fi
      fi
    fi
  done < "$artifact_file"

  # Process last finding if any
  if [ "$in_finding" = true ] && [ -n "$current_id" ]; then
    process_finding "$rel_path" "$current_id" "$current_desc" "$current_severity" "$current_status" "$current_feature"
  fi
}

process_finding() {
  local source_file="$1"
  local finding_id="$2"
  local description="$3"
  local severity="$4"
  local status="$5"
  local feature="$6"

  # Only import pending findings
  if [ "$status" != "pending" ]; then
    return
  fi

  # Map severity — skip BLOCKING and HIGH (PRH-003)
  local mapped_severity=""
  case "$severity" in
    BLOCKING|HIGH)
      return  # Skip — must be fixed in review
      ;;
    NON-BLOCKING)
      mapped_severity="MEDIUM"
      ;;
    MEDIUM)
      mapped_severity="MEDIUM"
      ;;
    LOW)
      mapped_severity="LOW"
      ;;
    INFORMATIONAL)
      mapped_severity="ADVISORY"
      ;;
    ADVISORY)
      mapped_severity="ADVISORY"
      ;;
    *)
      mapped_severity="MEDIUM"
      echo "Warning: unknown severity '$severity' for $finding_id in $source_file — mapped to MEDIUM" >&2
      ;;
  esac

  # Dedup check (source_file + finding_id)
  local key="${source_file}|${finding_id}"
  if echo "$existing_keys" | grep -qF "$key"; then
    return  # Already in backlog
  fi

  # Auto-assign ID
  next_id=$((next_id + 1))
  local df_id
  df_id=$(printf "DF-%03d" "$next_id")

  # Build the finding JSON
  local timestamp
  timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

  new_findings=$(echo "$new_findings" | jq \
    --arg id "$df_id" \
    --arg source_file "$source_file" \
    --arg finding_id "$finding_id" \
    --arg feature "$feature" \
    --arg severity "$mapped_severity" \
    --arg description "$description" \
    --arg category "review" \
    --arg deferred_at "$timestamp" \
    '. + [{
      id: $id,
      source_file: $source_file,
      finding_id: $finding_id,
      feature: $feature,
      severity: $severity,
      description: $description,
      category: $category,
      status: "open",
      deferred_at: $deferred_at,
      resolved_at: null,
      resolution: null
    }]')

  # Add to existing keys for dedup within this run
  existing_keys="${existing_keys}${existing_keys:+$'\n'}${key}"
  imported=$((imported + 1))
}

# ============================================================================
# STEP 4: Scan all review artifact files
# ============================================================================

# review-spec-findings-*.md in artifacts/
for f in "$ARTIFACTS_DIR"/review-spec-findings-*.md; do
  [ -f "$f" ] || continue
  scan_artifact "$f"
done

# review-findings-*.md in artifacts/
for f in "$ARTIFACTS_DIR"/review-findings-*.md; do
  [ -f "$f" ] || continue
  scan_artifact "$f"
done

# review-findings-*.md in artifacts/reviews/
for f in "$ARTIFACTS_DIR"/reviews/review-findings-*.md; do
  [ -f "$f" ] || continue
  scan_artifact "$f"
done

# ============================================================================
# STEP 5: Merge new findings into backlog
# ============================================================================

if [ "$imported" -gt 0 ]; then
  jq --argjson new "$new_findings" '.findings += $new' "$BACKLOG_FILE" > "$BACKLOG_FILE.tmp"
  mv "$BACKLOG_FILE.tmp" "$BACKLOG_FILE"
fi

echo "Synced $imported finding(s) to backlog"
