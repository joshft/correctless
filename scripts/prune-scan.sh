#!/usr/bin/env bash
# Correctless — Pruning Scanner
# Detects staleness candidates across 9 categories, outputs JSON to stdout.
#
# Usage: prune-scan.sh --category <category> --base <path> [--branches-file <path>] [--update-baseline]
# Categories: architecture, antipatterns, claude-md, artifacts, deferred, counts, crossrefs, specs, driftdebt
#
# Each candidate: { id, category, reason, risk, slug_type, match_method, dead_refs, live_refs, bulk_warning }
# Per INV-002: deterministic, sources scripts/lib.sh, per-category error handling.

set -euo pipefail

# ============================================
# STEP 1: Parse arguments
# ============================================

CATEGORY=""
BASE_DIR=""
BRANCHES_FILE=""
UPDATE_BASELINE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --category) [ $# -ge 2 ] || { echo "Error: --category requires a value" >&2; exit 1; }; CATEGORY="$2"; shift 2 ;;
    --base) [ $# -ge 2 ] || { echo "Error: --base requires a value" >&2; exit 1; }; BASE_DIR="$2"; shift 2 ;;
    --branches-file) [ $# -ge 2 ] || { echo "Error: --branches-file requires a value" >&2; exit 1; }; BRANCHES_FILE="$2"; shift 2 ;;
    --update-baseline) UPDATE_BASELINE=true; shift ;;
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

# Emit a JSON candidate object (with slug_type and match_method per INV-016)
emit_candidate() {
  local id="$1" category="$2" reason="$3" risk="$4"
  local dead_refs_json="$5" live_refs_json="$6" bulk_warning="$7"
  local slug_type="${8:-unclassified}" match_method="${9:-exact-token}"
  printf '{"id":%s,"category":%s,"reason":%s,"risk":%s,"slug_type":%s,"match_method":%s,"dead_refs":%s,"live_refs":%s,"bulk_warning":%s}' \
    "$(jq -n --arg v "$id" '$v')" \
    "$(jq -n --arg v "$category" '$v')" \
    "$(jq -n --arg v "$reason" '$v')" \
    "$(jq -n --arg v "$risk" '$v')" \
    "$(jq -n --arg v "$slug_type" '$v')" \
    "$(jq -n --arg v "$match_method" '$v')" \
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

# ============================================
# STEP 3a: Slug-type classification (INV-001)
# ============================================
# Sole writer: this function. Single definition required.
# Returns one of: branch-slug | task-slug | session-slug | unclassified
_classify_artifact_pattern() {
  local pattern="$1"
  case "$pattern" in
    workflow-state-*.json) echo "branch-slug" ;;
    token-log-*.jsonl) echo "branch-slug" ;;
    audit-trail-*.jsonl) echo "branch-slug" ;;
    pipeline-manifest-*.json) echo "branch-slug" ;;
    autonomous-decisions-*.jsonl) echo "branch-slug" ;;
    escalation-*.md) echo "branch-slug" ;;
    adherence-*.json) echo "branch-slug" ;;
    antipattern-findings-*.json) echo "branch-slug" ;;
    cost-cache-*.json) echo "branch-slug" ;;
    cost-*.json) echo "branch-slug" ;;
    review-decisions-*.json) echo "branch-slug" ;;
    lens-recommendations-*.json) echo "branch-slug" ;;
    probe-results-*.json) echo "branch-slug" ;;
    wtf-report-*.md) echo "branch-slug" ;;
    coverage-baseline-*.out) echo "branch-slug" ;;
    cprune-lock-*-*) echo "branch-slug" ;;
    chore-run-*.json) echo "branch-slug" ;;
    chore-abort-*.md) echo "branch-slug" ;;
    chore-report-*.md) echo "branch-slug" ;;
    qa-findings-*.json) echo "task-slug" ;;
    harness-notified-*.flag) echo "session-slug" ;;
    *) echo "unclassified" ;;
  esac
}

# Extract slug component from a filename given pattern.
# Returns the slug as a delimited token (per INV-005). Empty if no match.
# Implementation: strip the literal prefix before * and the literal suffix after *.
_extract_slug_token() {
  local fname="$1" pattern="$2"
  # Replace single glob * with capture marker
  local prefix="${pattern%%\**}"
  local rest="${pattern#"$prefix"}"
  rest="${rest#\*}"
  # rest is the suffix (may contain another *, e.g. "-*" for cprune-lock-*-*)
  # For cprune-lock-*-*, prefix="cprune-lock-", rest="-*"
  # For audit-trail-*.jsonl, prefix="audit-trail-", rest=".jsonl"
  # Strip leading-prefix and trailing-suffix from fname; what remains is the slug span
  local mid="${fname#"$prefix"}"
  # If rest still contains *, split on the literal portion before the next *
  case "$rest" in
    *\**)
      # Two-glob pattern (e.g., cprune-lock-*-*): need to grab the part before the last delim
      # The slug is everything up to the final lit-segment
      # For cprune-lock-feature-foo-abc123: mid="feature-foo-abc123"
      # We want the full mid (whole slug)
      echo "$mid"
      ;;
    *)
      # Single-glob pattern: strip trailing suffix
      local slug="${mid%"$rest"}"
      echo "$slug"
      ;;
  esac
}

# MA-001 fix: Escape ALL bash ERE metacharacters in a slug for safe regex interpolation.
# Bash ERE metachars: \ . [ ] ^ $ * + ? ( ) { } |
# Order matters: backslash MUST be escaped first to avoid double-escaping.
# Implementation uses sed with each metachar handled explicitly via character class.
_escape_ere_metachars() {
  local input="$1"
  # Escape order: backslash first, then all other metachars.
  # Using sed with character class [...] for the simple ones, plus separate
  # passes for ] and \ (which have special handling inside [...]).
  printf '%s' "$input" | sed -e 's/\\/\\\\/g' -e 's/[.[^$*+?(){}|]/\\&/g' -e 's/\]/\\]/g'
}

# Delimited-token match: does $fname contain $slug as a delimited token?
# Delimiters: '-', '.', start/end of string.
# Per INV-005 / PRH-002: no substring matching.
#
# MA-001 fix (v4): Escape ALL bash ERE metachars in the slug (not just '.').
# A slug containing '*', '[', '(', etc. would otherwise be interpreted as a
# regex pattern, leading to either over-match (data-loss vector via false
# protection bypass) or under-match (data-loss via false positive emission).
# Defense-in-depth: scan_artifacts entry-point validates slugs against
# [a-zA-Z0-9._-]+ BEFORE this function is invoked, so metachar slugs should
# never reach here. This escape is a belt-and-suspenders safeguard.
_slug_matches_filename() {
  local slug="$1" fname="$2"
  local escaped_slug
  escaped_slug="$(_escape_ere_metachars "$slug")"
  # Bash regex with character class [-.] — hyphen first to avoid range op
  # Anchor: (start | [-.])  slug  ([-.] | end)
  [[ "$fname" =~ (^|[-.])${escaped_slug}([-.]|$) ]]
}

# MA-001 fix (v4): Slug-validation gate. Reject slugs containing chars
# outside the safe set [a-zA-Z0-9._-]. Returns 0 if valid, 1 if invalid.
# Called from scan_artifacts after building live_task_slugs / stale_task_slugs.
_slug_is_safe() {
  local slug="$1"
  [[ "$slug" =~ ^[a-zA-Z0-9._-]+$ ]]
}

# Verify branch_slug helper is defined (INV-009).
_verify_branch_slug_available() {
  if ! command -v branch_slug >/dev/null 2>&1; then
    echo "# prune-scan: branch_slug helper unavailable (lib.sh sourcing failed or incomplete) — cannot compute safety belt; aborting" >&2
    exit 1
  fi
}

# Verify BASE_DIR is a git work tree (EA-001 extended).
_verify_git_base_dir() {
  if ! (cd "$BASE_DIR" 2>/dev/null && git rev-parse --is-inside-work-tree >/dev/null 2>&1); then
    echo "# prune-scan: BASE_DIR '$BASE_DIR' is not a git work tree — aborting" >&2
    exit 1
  fi
}

# Validate --branches-file lines per INV-015.
_validate_branches_file() {
  [ -z "$BRANCHES_FILE" ] && return 0
  [ ! -f "$BRANCHES_FILE" ] && return 0
  local lineno=0 line
  while IFS= read -r line; do
    lineno=$((lineno + 1))
    # Strip leading "* " prefix and whitespace
    line="${line## }"
    line="${line## \* }"
    line="${line## \*}"
    line="$(printf '%s' "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/^\* //')"
    [ -z "$line" ] && continue
    if ! [[ "$line" =~ ^[a-zA-Z0-9/_.-]+$ ]]; then
      echo "# prune-scan: --branches-file line $lineno is invalid (must match [a-zA-Z0-9/_.-]+): '$line'" >&2
      exit 1
    fi
  done < "$BRANCHES_FILE"
}

# Canonical path containment check (INV-010).
# Returns 0 if canonical path is under BASE_DIR/.correctless/artifacts/, 1 otherwise.
_is_under_artifacts_dir() {
  local path="$1"
  local base_canon
  base_canon="$(canonicalize_path "$BASE_DIR/.correctless/artifacts" 2>/dev/null || echo "")"
  local path_canon
  path_canon="$(canonicalize_path "$path" 2>/dev/null || echo "")"
  [ -z "$base_canon" ] && return 1
  [ -z "$path_canon" ] && return 1
  case "$path_canon" in
    "$base_canon"/*) return 0 ;;
    *) return 1 ;;
  esac
}

# MA2-001 fix (v5): realpath-based containment check WITHOUT silent lexical
# fallback. Resolves parent-component symlinks (which lexical canonicalize_path
# misses). Returns:
#   0 — path is under artifacts_dir (verified by realpath/readlink -f)
#   1 — path escapes artifacts_dir (verified by realpath/readlink -f)
#   2 — neither realpath nor readlink -f available; caller MUST fail-closed
#       (no silent lexical fallback — MA2-001 in mini-audit round 2 flagged
#       the v4 fallback as v3-equivalent vulnerability).
#
# The v4 implementation fell back to _is_under_artifacts_dir on missing tools.
# That fallback was lexical-only and could not detect parent-component symlinks,
# meaning a stripped-down container or busybox environment silently degraded
# to no parent-symlink protection. v5 fails closed instead.
_is_under_artifacts_dir_realpath() {
  local path="$1" artifacts_dir="$2"
  local path_real artifacts_real
  if command -v realpath >/dev/null 2>&1; then
    path_real="$(realpath "$path" 2>/dev/null || echo "")"
    artifacts_real="$(realpath "$artifacts_dir" 2>/dev/null || echo "")"
  elif command -v readlink >/dev/null 2>&1 && readlink -f / >/dev/null 2>&1; then
    path_real="$(readlink -f "$path" 2>/dev/null || echo "")"
    artifacts_real="$(readlink -f "$artifacts_dir" 2>/dev/null || echo "")"
  else
    # MA2-001 fix (v5): NO silent lexical fallback. Return 2 to signal
    # "tool unavailable" — caller must fail-closed at the category level.
    return 2
  fi
  [ -z "$path_real" ] && return 1
  [ -z "$artifacts_real" ] && return 1
  case "$path_real" in
    "$artifacts_real"/*) return 0 ;;
    "$artifacts_real") return 0 ;;
    *) return 1 ;;
  esac
}

# MA2-001 fix (v5): once-per-scan probe for realpath/readlink -f availability.
# Called at scan_artifacts entry before the per-artifact loop. If neither tool
# is available, fail-closed for the entire artifacts category immediately —
# no point entering the loop only to abort on the first artifact.
# Returns 0 if either tool is available, 1 otherwise.
_realpath_tool_available() {
  if command -v realpath >/dev/null 2>&1; then
    return 0
  fi
  if command -v readlink >/dev/null 2>&1 && readlink -f / >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

# MA2-002 fix (v5): content-based identity for a workflow-state file.
# Replaces v4's mtime fence (which conflated content changes with non-content
# operations like git checkout/touch that bump mtime without changing content,
# and missed atomic-rename overwrites that preserve mtime).
#
# Identity tuple selection (first available):
#   1. .started_at (jq) — ABS-029 precedent; stable identity field
#   2. .task + "|" + .branch — composite identity when started_at missing
#   3. sha256_hash_file — final fallback when both fields missing
#
# Outputs the identity string to stdout, or empty on failure. Stderr advisory
# on sha256 fallback failure (no tool available); caller must fail-closed for
# that specific file.
_workflow_state_identity() {
  local ws="$1"
  [ -f "$ws" ] || { echo ""; return 1; }

  local started_at task branch
  started_at="$(jq -r '.started_at // empty' "$ws" 2>/dev/null || echo "")"
  if [ -n "$started_at" ] && [ "$started_at" != "null" ]; then
    echo "started_at:$started_at"
    return 0
  fi

  task="$(jq -r '.task // empty' "$ws" 2>/dev/null || echo "")"
  branch="$(jq -r '.branch // empty' "$ws" 2>/dev/null || echo "")"
  if [ -n "$task" ] && [ -n "$branch" ] && [ "$task" != "null" ] && [ "$branch" != "null" ]; then
    echo "composite:$task|$branch"
    return 0
  fi

  # Final fallback: file content sha256. Uses lib.sh sha256_hash_file helper.
  if command -v sha256_hash_file >/dev/null 2>&1; then
    local hash
    hash="$(sha256_hash_file "$ws" 2>/dev/null || echo "")"
    if [ -n "$hash" ]; then
      echo "sha256:$hash"
      return 0
    fi
  fi

  # No identity could be derived. Caller must fail-closed for this file.
  echo ""
  return 1
}

# Extract file paths from a text block using spec-defined rules (INV-003)
# Outputs one path per line
extract_file_paths() {
  local text="$1"

  # Rule 1: backtick-quoted code spans matching file path patterns
  echo "$text" | grep -oE '`[a-zA-Z0-9_./+-]+\.(sh|md|json|py|ts|js|yml|yaml)`' | sed 's/^`//;s/`$//' || true

  # Rule 2: Enforced at fields — comma-separated entries parsed as filepath (optional role)
  echo "$text" | grep -E '^- \*\*Enforced at\*\*:' | sed 's/^- \*\*Enforced at\*\*:[[:space:]]*//' | tr ',' '\n' | while read -r entry; do
    entry="$(echo "$entry" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [ -z "$entry" ] && continue
    local bt_path
    bt_path="$(echo "$entry" | grep -oE '`[a-zA-Z0-9_./+-]+\.(sh|md|json|py|ts|js|yml|yaml)`' | sed 's/^`//;s/`$//')" || true
    if [ -n "$bt_path" ]; then
      echo "$bt_path"
    else
      local bare_path
      bare_path="$(echo "$entry" | sed 's/[[:space:]]*(.*)//' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
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
# A project's architecture is "fragmented" (index+body-out) only when the root
# ARCHITECTURE.md actually carries the index See-links into docs/architecture/ —
# NOT merely because a docs/architecture/ directory exists. A monolithic target
# repo (correctless runs on other repos) may keep unrelated docs there (ADRs, C4
# diagrams); detecting the marker rather than the directory keeps the monolithic
# root scan intact on those repos (QA H-1).
_arch_is_fragmented() {
  local arch_file="$BASE_DIR/.correctless/ARCHITECTURE.md"
  [ -f "$arch_file" ] && grep -q 'See \[docs/architecture/' "$arch_file" &&
    compgen -G "$BASE_DIR/docs/architecture/*.md" >/dev/null 2>&1
}

# Emit architecture entry content for scanning. When fragmented, scan the
# fragment bodies ONLY — the root is then a pure index (heading + See-link) with
# no scannable file references. Scanning root + fragments would double-count each
# entry in total_entries and cap the BND-002 bulk-warning ratio at 50%, silently
# disabling that safety valve. The exempt PAT-001/PAT-017 .claude/rules refs are
# covered by tests/test-architecture-drift.sh (PAT-001(a)/PAT-017(a)). Otherwise
# scan the monolithic root ARCHITECTURE.md.
_emit_arch_scan_content() {
  local arch_file="$BASE_DIR/.correctless/ARCHITECTURE.md"
  if _arch_is_fragmented; then
    cat "$BASE_DIR"/docs/architecture/*.md
  elif [ -f "$arch_file" ]; then
    cat "$arch_file"
  fi
}

_arch_has_scan_sources() {
  [ -f "$BASE_DIR/.correctless/ARCHITECTURE.md" ]
}

scan_architecture() {
  if ! _arch_has_scan_sources; then
    echo "[]"
    return
  fi

  local candidates=()
  local total_entries=0
  local current_id=""
  local current_text=""
  local in_entry=false
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
      if [ "$in_entry" = true ]; then
        current_text+=$'\n'"$line"
      fi
    elif [[ "$line" =~ ^###[[:space:]] ]] && [ "$in_entry" = true ]; then
      _process_arch_entry "$current_id" "$current_text"
      current_id=""
      current_text=""
      in_entry=false
    elif [ "$in_entry" = true ]; then
      current_text+=$'\n'"$line"
    fi
  done < <(_emit_arch_scan_content)

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

  if [ ${#live_paths[@]} -eq 0 ] && [ ${#dead_paths[@]} -gt 0 ]; then
    local candidate
    candidate="$(emit_candidate "$entry_id" "architecture" "All referenced files are dead" "medium" \
      "$(paths_to_json_array "${dead_paths[@]}")" "[]" "false" "unclassified" "exact-token")"
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

  # shellcheck disable=SC2034
  local class_keywords="interpolation|injection|drift|silent|phantom|persist"

  local candidates=()
  local total_entries=0
  local current_id=""
  local current_title=""
  local current_text=""
  local in_entry=false

  while IFS= read -r line; do
    if [[ "$line" =~ ^###[[:space:]]+(AP-[0-9]+):.* ]]; then
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

  if [ -n "$current_id" ] && [ "$in_entry" = true ]; then
    _process_ap_entry "$current_id" "$current_title" "$current_text"
  fi

  emit_candidates_array candidates "$total_entries"
}

_process_ap_entry() {
  local entry_id="$1"
  local entry_title="$2"
  local entry_text="$3"

  echo "$entry_title" | grep -qiE "$class_keywords" && return

  local paths
  paths="$(extract_file_paths "$entry_text" | sort -u)"
  [ -z "$paths" ] && return

  local dead_paths=() live_paths=()
  classify_paths "$paths"

  if [ ${#live_paths[@]} -eq 0 ] && [ ${#dead_paths[@]} -gt 0 ]; then
    local candidate
    candidate="$(emit_candidate "$entry_id" "antipatterns" "All referenced files are dead" "medium" \
      "$(paths_to_json_array "${dead_paths[@]}")" "[]" "false" "unclassified" "exact-token")"
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
    if [[ "$line" =~ ^##[[:space:]]Correctless[[:space:]]Learnings ]]; then
      in_learnings=true
      continue
    fi

    if [ "$in_learnings" = true ] && [[ "$line" =~ ^##[[:space:]] ]] && ! [[ "$line" =~ ^###[[:space:]] ]]; then
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

    if [[ "$line" =~ ^###[[:space:]]([0-9]{4}-[0-9]{2}-[0-9]{2})[[:space:]]—[[:space:]](.*) ]]; then
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

  if [ -n "$current_id" ] && [ "$in_entry" = true ]; then
    _process_claude_entry "$current_id" "$current_title" "$current_text"
  fi

  emit_simple_array candidates
}

_process_claude_entry() {
  local entry_date="$1"
  local entry_title="$2"
  local entry_text="$3"

  echo "$entry_title" | grep -qE "Convention confirmed|Convention introduced|Postmortem" && return

  local paths
  paths="$(echo "$entry_text" | grep -oE '`[a-zA-Z_./-]+\.(sh|md|json|py|ts|js|yml|yaml)`' | sed 's/^`//;s/`$//' | sort -u)" || true
  [ -z "$paths" ] && return

  local dead_paths=() live_paths=()
  classify_paths "$paths"

  if [ ${#live_paths[@]} -eq 0 ] && [ ${#dead_paths[@]} -gt 0 ]; then
    local candidate
    candidate="$(emit_candidate "$entry_date — $entry_title" "claude-md" "All referenced files are dead" "high" \
      "$(paths_to_json_array "${dead_paths[@]}")" "[]" "false" "unclassified" "exact-token")"
    candidates+=("$candidate")
  fi
}

# ============================================
# STEP 4a: ARTIFACTS scanner — wrapped object output
# ============================================

# ---- artifacts ----
# Returns wrapped JSON object:
# {
#   candidates: [...],
#   skipped_unclassified: [{pattern, count}],
#   protection_set: {live_branches, live_branch_slugs, live_task_slugs, live_session_ids, source_workflow_state_files},
#   protection_status: {task_slug: ok|fail-closed, reason: <string|null>}
# }
#
# MA2-004 fix (v5): scan_artifacts enables `set -f` (noglob) at entry and
# restores prior state at every return point. The body iterates several
# unquoted pattern lists ($artifact_patterns) where a cwd containing a
# matching file (e.g., user invokes from `.correctless/artifacts/`) would
# trigger pathname expansion and misroute the iteration. Save/restore is
# preferred over subshell wrapping because the function has multiple early
# returns that would need to be converted to `exit` (and would interact
# poorly with the parent `set -e`).
scan_artifacts() {
  # MA2-004 fix (v5): save current `-f` (noglob) state and enable it.
  # Restored before EACH return point below via _restore_noglob.
  local _f_was_set=true
  case $- in
    *f*) _f_was_set=true ;;
    *) _f_was_set=false ;;
  esac
  set -f

  # Helper closure for restoring noglob state. Called before every return.
  _restore_noglob() {
    [ "$_f_was_set" = false ] && set +f
  }

  # EA-001 + INV-009 + INV-015 — fail-closed gates BEFORE the dir-existence
  # short-circuit (per spec INV-009: "before any scan_artifacts invocation").
  # The order matters: branch_slug availability and branches-file validation
  # must run even when the artifacts dir is missing, otherwise lib.sh sourcing
  # failures and malicious --branches-file inputs silently emit empty success.
  _verify_git_base_dir
  _verify_branch_slug_available
  _validate_branches_file

  local artifacts_dir="$BASE_DIR/.correctless/artifacts"
  if [ ! -d "$artifacts_dir" ]; then
    _restore_noglob
    _emit_wrapped_empty
    return
  fi

  # MA-005 fix (v4): artifacts-dir-itself symlink check. If .correctless/artifacts/
  # is a symlink, autonomous /cprune could mass-delete files in the link target
  # (e.g., /etc or $HOME) via basename passthrough. Fail-closed BEFORE iterating.
  # PAT-017 lexical canonicalize_path does not resolve parent symlinks, so this
  # entry-point guard is load-bearing.
  if [ -L "$artifacts_dir" ]; then
    echo "# prune-scan: .correctless/artifacts/ is a symlink — aborting artifacts category (fail-closed)" >&2
    _restore_noglob
    _emit_wrapped_empty "fail-closed" "artifacts-dir-is-symlink"
    return
  fi

  # MA2-001 fix (v5): probe for realpath/readlink -f BEFORE entering the per-
  # artifact loop. If neither tool is available, the parent-symlink-escape
  # protection from _is_under_artifacts_dir_realpath cannot function. v4
  # silently fell back to lexical-only, which is a v3-equivalent vulnerability.
  # v5 fails closed at the category level — no silent degradation.
  if ! _realpath_tool_available; then
    echo "# prune-scan: realpath/readlink -f unavailable — parent-symlink escape protection DEGRADED. Aborting artifacts category (fail-closed)." >&2
    _restore_noglob
    _emit_wrapped_empty "fail-closed" "realpath-unavailable"
    return
  fi

  # ===== Single source of truth for patterns (INV-006) =====
  local artifact_patterns="workflow-state-*.json token-log-*.jsonl audit-trail-*.jsonl pipeline-manifest-*.json autonomous-decisions-*.jsonl escalation-*.md adherence-*.json antipattern-findings-*.json cost-cache-*.json cost-*.json review-decisions-*.json lens-recommendations-*.json probe-results-*.json wtf-report-*.md coverage-baseline-*.out cprune-lock-*-* chore-run-*.json chore-abort-*.md chore-report-*.md qa-findings-*.json harness-notified-*.flag"

  # ===== Step 1: load live branches and compute live-branch-slug set =====
  local branches branch_arr
  branches="$(load_branches)"
  local -a branch_arr=()
  while IFS= read -r branch; do
    [ -z "$branch" ] && continue
    [[ "$branch" == *"HEAD"* ]] && continue
    branch_arr+=("$branch")
  done <<< "$branches"

  # F-001 fix: if load_branches yielded nothing (silent `|| true` swallowing
  # git errors, an empty --branches-file, or a git repo with no branches yet),
  # the live-branch-slug set would be empty and EVERY branch-slug artifact
  # would emit as a deletion candidate at low risk. Fail-closed here BEFORE
  # the slug-computation loop so the artifacts category is skipped entirely.
  if [ ${#branch_arr[@]} -eq 0 ]; then
    echo "# prune-scan: live branch set is empty (load_branches returned no branches) — aborting artifacts category (fail-closed)" >&2
    _restore_noglob
    _emit_wrapped_empty "fail-closed" "no-live-branches"
    return
  fi

  local -a live_branch_slugs=()
  local b
  for b in "${branch_arr[@]}"; do
    local slug
    if ! slug="$(branch_slug "$b" 2>/dev/null)"; then
      echo "# prune-scan: branch_slug failed for '$b' — aborting artifacts category (fail-closed)" >&2
      _restore_noglob
      _emit_wrapped_empty "fail-closed" "branch-slug-failure"
      return
    fi
    [ -z "$slug" ] && continue
    live_branch_slugs+=("$slug")
  done

  # MA2-002 fix (v5): content-based identity fence — snapshot workflow-state
  # IDENTITIES at scan start. Replaces v4's mtime-based fence (which conflated
  # content changes with non-content operations and could miss atomic-rename
  # overwrites that preserve mtime — see PMB-005 mtime-drift learnings).
  # ABS-029 established string-equality on a stable identity field as the
  # robust pattern; we adopt it here.
  #
  # Identity selection (per _workflow_state_identity):
  #   .started_at (primary) → .task+|+.branch (fallback) → sha256 (final)
  #
  # If a workflow-state file cannot produce an identity (no started_at, no
  # task+branch, AND no sha256 tool), fail-closed for the entire category.
  declare -A _initial_identities=()
  local _ws_file
  while IFS= read -r _ws_file; do
    [ -z "$_ws_file" ] && continue
    local _ident
    _ident="$(_workflow_state_identity "$_ws_file" 2>/dev/null || echo "")"
    if [ -z "$_ident" ]; then
      echo "# prune-scan: unable to derive content identity for '$_ws_file' (no started_at/task+branch, no sha256 tool) — aborting artifacts category (fail-closed)" >&2
      _restore_noglob
      _emit_wrapped_empty "fail-closed" "identity-unavailable"
      return
    fi
    _initial_identities["$_ws_file"]="$_ident"
  done < <(find "$artifacts_dir" -maxdepth 1 -name 'workflow-state-*.json' -type f 2>/dev/null)

  # ===== Step 2: build live-task-slug set and stale-task-slug set + fail-closed gates =====
  # Source files referenced for protection_set
  local -a workflow_state_files=()
  while IFS= read -r ws; do
    [ -z "$ws" ] && continue
    workflow_state_files+=("$ws")
  done < <(find "$artifacts_dir" -maxdepth 1 -name 'workflow-state-*.json' -type f 2>/dev/null)

  local -a live_task_slugs=()
  local -a stale_task_slugs=()
  local -a stale_workflow_state_files=()
  local task_protection_status="ok"
  local task_protection_reason=""

  if [ ${#workflow_state_files[@]} -eq 0 ]; then
    task_protection_status="fail-closed"
    task_protection_reason="no-workflow-state"
    echo "# prune-scan: task-slug protection unavailable (no-workflow-state); skipping task-slug patterns" >&2
  else
    local ws
    for ws in "${workflow_state_files[@]}"; do
      # jq parse — fail-closed at category level on any parse failure (INV-014)
      local spec_file branch_name
      if ! spec_file="$(jq -r '.spec_file // empty' "$ws" 2>/dev/null)"; then
        echo "# prune-scan: workflow-state $ws parse failure — aborting artifacts scan (fail-closed). Re-run after concurrent writes complete." >&2
        task_protection_status="fail-closed"
        task_protection_reason="parse-failure"
        live_task_slugs=()
        stale_task_slugs=()
        break
      fi
      if ! branch_name="$(jq -r '.branch // empty' "$ws" 2>/dev/null)"; then
        echo "# prune-scan: workflow-state $ws parse failure — aborting artifacts scan (fail-closed). Re-run after concurrent writes complete." >&2
        task_protection_status="fail-closed"
        task_protection_reason="parse-failure"
        live_task_slugs=()
        stale_task_slugs=()
        break
      fi
      # If jq succeeded but spec_file is empty/null → INV-004a fail-closed
      if [ -z "$spec_file" ] || [ "$spec_file" = "null" ]; then
        echo "# prune-scan: task-slug protection unavailable (incomplete-spec_file: $ws); skipping task-slug patterns" >&2
        task_protection_status="fail-closed"
        task_protection_reason="incomplete-spec_file"
        live_task_slugs=()
        stale_task_slugs=()
        break
      fi
      # Derive task slug from spec_file basename (no .task fallback per EA-003)
      local task_slug
      task_slug="$(basename "$spec_file" .md)"
      [ -z "$task_slug" ] && continue
      # F-003 fix: previously this compared the *slug* of the workflow-state's
      # branch against each live-branch-slug, recomputing `branch_slug
      # "$branch_name" 2>/dev/null` per iteration. The 2>/dev/null swallowed
      # md5sum/md5 failures, silently misclassifying every workflow-state as
      # stale and turning live qa-findings into deletion candidates. Compare
      # branch *names* directly against the loaded branch_arr instead — this
      # eliminates the second branch_slug invocation entirely.
      local is_live=false live_b
      for live_b in "${branch_arr[@]}"; do
        if [ "$live_b" = "$branch_name" ]; then
          is_live=true
          break
        fi
      done
      if [ "$is_live" = true ]; then
        live_task_slugs+=("$task_slug")
      else
        stale_task_slugs+=("$task_slug")
        stale_workflow_state_files+=("$(basename "$ws")")
      fi
    done
  fi

  # MA-001 fix (v4): Defense-in-depth slug-validation gate. After building both
  # task-slug sets, validate each slug against [a-zA-Z0-9._-]+. Any slug
  # containing shell/regex metacharacters (originating from a producer-controlled
  # spec_file basename) triggers fail-closed. This complements _escape_ere_metachars
  # in _slug_matches_filename — if a malformed slug somehow propagates past
  # validation, the escape function is the last line of defense.
  if [ "$task_protection_status" = "ok" ]; then
    local _bad_slug=""
    local _s
    for _s in "${live_task_slugs[@]}" "${stale_task_slugs[@]}"; do
      if ! _slug_is_safe "$_s"; then
        _bad_slug="$_s"
        break
      fi
    done
    if [ -n "$_bad_slug" ]; then
      echo "# prune-scan: task slug '$_bad_slug' contains characters outside [a-zA-Z0-9._-] — aborting artifacts category (fail-closed). Check workflow-state .spec_file values for shell metacharacters." >&2
      _restore_noglob
      _emit_wrapped_empty "fail-closed" "task-slug-invalid-chars"
      return
    fi
  fi

  # ===== Step 3: baseline manifest check (INV-011) =====
  # MA-003 fix (v4): Validate baseline JSON shape. Corrupt baseline previously
  # appeared as "no patterns known" (silent over-medium emission). Now an
  # advisory is emitted and baseline_present is explicitly set false.
  local baseline_file="$BASE_DIR/.correctless/meta/prune-pattern-baseline.json"
  local -a known_patterns=()
  local baseline_present=true
  if [ -f "$baseline_file" ]; then
    if jq -e '.patterns | type == "array"' "$baseline_file" >/dev/null 2>&1; then
      while IFS= read -r p; do
        [ -z "$p" ] && continue
        known_patterns+=("$p")
      done < <(jq -r '.patterns[]? // empty' "$baseline_file" 2>/dev/null)
    else
      # Corrupt or wrong-shape baseline — emit advisory and degrade observably.
      echo "# prune-scan: baseline manifest at $baseline_file failed parse — proceeding as no-baseline (medium-risk on all candidates). Inspect file and re-run with --update-baseline after review." >&2
      baseline_present=false
    fi
  else
    baseline_present=false
    echo "# prune-scan: no baseline manifest — first run, emitting at medium risk" >&2
  fi

  # ===== Step 4: scan files =====
  local -a candidates=()
  declare -A skipped_unclassified=()
  declare -A pattern_is_new=()

  # Tag each pattern as new or known (relative to baseline)
  local pat
  local _pattern_count=0
  for pat in $artifact_patterns; do
    _pattern_count=$((_pattern_count + 1))
    local is_new=true
    if [ "$baseline_present" = true ]; then
      local kp
      for kp in "${known_patterns[@]}"; do
        if [ "$kp" = "$pat" ]; then
          is_new=false
          break
        fi
      done
    fi
    pattern_is_new["$pat"]="$is_new"
  done

  # MA-002 fix (v4): assert pattern_is_new is populated for every pattern.
  # Mismatch indicates a structural bug (associative array population failure,
  # word-splitting glitch, etc). Fail-closed rather than silently default-to-new.
  if [ "${#pattern_is_new[@]}" -ne "$_pattern_count" ]; then
    echo "# prune-scan: internal assertion failed — pattern_is_new map size (${#pattern_is_new[@]}) != pattern count ($_pattern_count) — aborting artifacts category (fail-closed)" >&2
    _restore_noglob
    _emit_wrapped_empty "fail-closed" "pattern-is-new-size-mismatch"
    return
  fi

  # MA-002 fix (v4): explicit-existence-check helper.
  # Returns "true" if pattern is new (or missing — fail-safe), "false" if known.
  # Emits stderr advisory on miss (which indicates a bug — every pattern in
  # artifact_patterns should have been populated above).
  _pattern_is_new_safe() {
    local p="$1"
    if [ "${pattern_is_new[$p]+x}" = "x" ]; then
      echo "${pattern_is_new[$p]}"
    else
      echo "# prune-scan: internal — pattern_is_new lookup miss for '$p' (treating as new, fail-safe)" >&2
      echo "true"
    fi
  }

  # First pass: determine each artifact's matching pattern and classify candidates.
  # MA2-004 fix (v5): enumerate via `find` (binary, glob-free) instead of
  # `for artifact in "$artifacts_dir"/*` — the latter requires globbing, which
  # is disabled by the entry-point `set -f` guard. `find` produces NUL- or
  # newline-delimited paths regardless of noglob state.
  local artifact
  local _artifact_list
  _artifact_list="$(find "$artifacts_dir" -maxdepth 1 -mindepth 1 \( -type f -o -type l \) -print 2>/dev/null || true)"
  while IFS= read -r artifact; do
    [ -z "$artifact" ] && continue
    # INV-010 — reject symlinks BEFORE -f test (symlinks to existing files would pass -f)
    if [ -L "$artifact" ]; then
      echo "# prune-scan: rejecting symlink '$artifact' (INV-010)" >&2
      continue
    fi
    [ -f "$artifact" ] || continue

    # INV-010 — canonical path containment (lexical, fast path)
    if ! _is_under_artifacts_dir "$artifact"; then
      echo "# prune-scan: rejecting '$artifact' (canonicalize_path escapes artifacts dir)" >&2
      continue
    fi

    # MA-005 fix (v4) / MA2-001 fix (v5): realpath-based containment — catches
    # parent-component symlinks that PAT-017 lexical canonicalize_path misses.
    # Per MA2-001, return code 2 (tool unavailable) is impossible here because
    # we probed at scan entry and fail-closed if neither tool present. Treat
    # any non-zero return as "escapes artifacts dir" — defensive, since 2 is
    # already impossible by construction.
    if ! _is_under_artifacts_dir_realpath "$artifact" "$artifacts_dir"; then
      echo "# prune-scan: rejecting '$artifact' (realpath escapes artifacts dir — parent symlink detected)" >&2
      continue
    fi

    local fname
    fname="$(basename "$artifact")"

    # Determine matching pattern (first match wins)
    local matched_pattern=""
    for pat in $artifact_patterns; do
      # shellcheck disable=SC2254
      case "$fname" in
        $pat) matched_pattern="$pat"; break ;;
      esac
    done

    [ -z "$matched_pattern" ] && continue

    # Classify
    local slug_type
    slug_type="$(_classify_artifact_pattern "$matched_pattern")"

    # INV-002 — unclassified → skip + record (with INV-007 stderr advisory on first encounter)
    if [ "$slug_type" = "unclassified" ]; then
      local prev_count="${skipped_unclassified[$matched_pattern]:-0}"
      if [ "$prev_count" -eq 0 ]; then
        echo "# prune-scan: skipping unclassified pattern '$matched_pattern' (INV-007 — add a classification entry in _classify_artifact_pattern to flag stale files)" >&2
      fi
      skipped_unclassified["$matched_pattern"]=$((prev_count + 1))
      continue
    fi

    # INV-001 / PRH-001: session-slug is NEVER live-prunable → skip entirely
    if [ "$slug_type" = "session-slug" ]; then
      continue
    fi

    # Determine slug-type-specific logic
    case "$slug_type" in
      branch-slug)
        # Check if any live branch slug matches as delimited token
        local found=false
        local s
        for s in "${live_branch_slugs[@]}"; do
          if _slug_matches_filename "$s" "$fname"; then
            found=true
            break
          fi
        done
        if [ "$found" = false ]; then
          # Stale — emit candidate
          # MA-002 fix (v4): use explicit-existence helper instead of :-true default.
          local _is_new
          _is_new="$(_pattern_is_new_safe "$matched_pattern")"
          local risk="low"
          if [ "$baseline_present" = false ] || [ "$_is_new" = "true" ]; then
            risk="medium"
          fi
          local reason="Artifact for deleted/unknown branch"
          if [ "$baseline_present" = false ]; then
            reason="Newly added pattern '$matched_pattern' — first scan after upgrade; review before deletion"
          elif [ "$_is_new" = "true" ]; then
            reason="Newly added pattern '$matched_pattern' — first scan after upgrade; review before deletion"
          fi
          local cand
          cand="$(emit_candidate "$fname" "artifacts" "$reason" "$risk" \
            "$(paths_to_json_array ".correctless/artifacts/$fname")" "[]" "false" \
            "branch-slug" "exact-token")"
          candidates+=("$cand")
        fi
        ;;
      task-slug)
        # Skip entirely if fail-closed
        [ "$task_protection_status" = "fail-closed" ] && continue
        # Check if any live task slug matches as delimited token
        local found=false
        local s
        for s in "${live_task_slugs[@]}"; do
          if _slug_matches_filename "$s" "$fname"; then
            found=true
            break
          fi
        done
        if [ "$found" = false ]; then
          # Is it in the stale set? Need to verify atomic group (INV-018).
          local in_stale=false
          local s2
          for s2 in "${stale_task_slugs[@]}"; do
            if _slug_matches_filename "$s2" "$fname"; then
              in_stale=true
              break
            fi
          done
          if [ "$in_stale" = false ]; then
            # Not live, not in stale → treat as legitimate orphan
            continue
          fi
          # MA-002 fix (v4): use explicit-existence helper instead of :-true default.
          local _is_new
          _is_new="$(_pattern_is_new_safe "$matched_pattern")"
          local risk="low"
          if [ "$baseline_present" = false ] || [ "$_is_new" = "true" ]; then
            risk="medium"
          fi
          local reason="Artifact for unknown task slug"
          if [ "$baseline_present" = false ]; then
            reason="Newly added pattern '$matched_pattern' — first scan after upgrade; review before deletion"
          elif [ "$_is_new" = "true" ]; then
            reason="Newly added pattern '$matched_pattern' — first scan after upgrade; review before deletion"
          fi
          local cand
          cand="$(emit_candidate "$fname" "artifacts" "$reason" "$risk" \
            "$(paths_to_json_array ".correctless/artifacts/$fname")" "[]" "false" \
            "task-slug" "exact-token")"
          candidates+=("$cand")
        fi
        ;;
    esac
  done <<< "$_artifact_list"

  # F-002 fix — INV-018 atomic group enforcement.
  #
  # Spec INV-018 (3-case contract):
  #   (a) live-branch ws + matching qa-findings → live-task-slug set protects;
  #       neither emitted. Handled by the live-task-slug protection above.
  #   (b) stale-branch ws + matching qa-findings → BOTH appear in candidates
  #       (atomic group satisfied). No-op here.
  #   (c) stale-branch ws alone (no dependents) → only ws in candidates.
  #       Legitimate; keep ws alone.
  #
  # The failure mode this gate prevents: a prior /cprune run already deleted
  # the workflow-state but left a dependent qa-findings behind. On the next
  # scan, ws is absent (no candidate emitted for it) but the qa-findings is
  # still flagged. That orphan can never be paired with its workflow-state
  # again, so emitting it alone violates the atomic contract — drop it.
  #
  # Index candidates once (slug_type + id) to avoid O(N*M) jq invocations.
  if [ ${#stale_workflow_state_files[@]} -gt 0 ] && [ ${#candidates[@]} -gt 0 ]; then
    # Parse all candidates' id+slug_type into parallel arrays.
    local -a _cand_ids=() _cand_slug_types=()
    local _ci
    for _ci in "${candidates[@]}"; do
      _cand_ids+=("$(echo "$_ci" | jq -r '.id // empty' 2>/dev/null || true)")
      _cand_slug_types+=("$(echo "$_ci" | jq -r '.slug_type // empty' 2>/dev/null || true)")
    done

    # Compute the set of candidate-indices to DROP.
    declare -A _drop_idx=()
    local _i _j _n=${#stale_workflow_state_files[@]}
    for ((_i=0; _i<_n; _i++)); do
      local _stale_ws="${stale_workflow_state_files[$_i]}"
      # Arrays may diverge when workflow-state files lack .spec_file (older schema):
      # stale_workflow_state_files has the file, stale_task_slugs has no entry.
      # Skip atomic-group enforcement for files without derivable task slugs.
      local _stale_ts="${stale_task_slugs[$_i]:-}"
      [ -z "$_stale_ts" ] && continue

      # ws-candidate present? Match by exact id equality on the branch-slug entry.
      local _ws_present=false
      local _cands_len=${#_cand_ids[@]}
      for ((_j=0; _j<_cands_len; _j++)); do
        if [ "${_cand_slug_types[$_j]}" = "branch-slug" ] && [ "${_cand_ids[$_j]}" = "$_stale_ws" ]; then
          _ws_present=true
          break
        fi
      done

      # Collect dep-candidate indices for this stale task slug.
      local -a _dep_idxs=()
      for ((_j=0; _j<_cands_len; _j++)); do
        if [ "${_cand_slug_types[$_j]}" = "task-slug" ]; then
          if _slug_matches_filename "$_stale_ts" "${_cand_ids[$_j]}"; then
            _dep_idxs+=("$_j")
          fi
        fi
      done

      # Atomic enforcement:
      #   ws absent && deps present → drop deps (orphaned)
      #   ws present && deps present → keep both (atomic group satisfied)
      #   ws present && deps absent → keep ws (case c — alone is legitimate)
      #   ws absent && deps absent → nothing to do
      if [ "$_ws_present" = false ] && [ ${#_dep_idxs[@]} -gt 0 ]; then
        local _di
        for _di in "${_dep_idxs[@]}"; do
          _drop_idx["$_di"]=1
        done
        echo "# prune-scan: INV-018 atomic group: dropping ${#_dep_idxs[@]} orphaned task-slug candidate(s) for stale task '$_stale_ts' (workflow-state '$_stale_ws' already absent from candidates — likely deleted in a prior run)" >&2
      fi
    done

    # Filter candidates by index.
    if [ ${#_drop_idx[@]} -gt 0 ]; then
      local -a cleaned_candidates=()
      local _k _klen=${#candidates[@]}
      for ((_k=0; _k<_klen; _k++)); do
        if [ -z "${_drop_idx[$_k]:-}" ]; then
          cleaned_candidates+=("${candidates[$_k]}")
        fi
      done
      candidates=("${cleaned_candidates[@]}")
    fi
    unset _drop_idx
  fi

  # MA2-002 fix (v5): re-snapshot workflow-state IDENTITIES at scan end.
  # Replaces v4's mtime re-snapshot. Content-based identity catches the cases
  # mtime missed (atomic-rename preserving mtime) and ignores the cases mtime
  # falsely flagged (touch / git checkout / status query bumping mtime without
  # content change). See ABS-029 precedent and PMB-005 mtime-drift learnings.
  declare -A _final_identities=()
  while IFS= read -r _ws_file; do
    [ -z "$_ws_file" ] && continue
    local _ident
    _ident="$(_workflow_state_identity "$_ws_file" 2>/dev/null || echo "")"
    # If identity derivation fails at re-snapshot time, that itself indicates
    # the file changed in a way that breaks identity extraction — fail-closed.
    if [ -z "$_ident" ]; then
      echo "# prune-scan: unable to derive content identity for '$_ws_file' at scan-end (file appeared mid-scan or became unreadable) — aborting artifacts category (fail-closed)" >&2
      _restore_noglob
      _emit_wrapped_empty "fail-closed" "workflow-state-race-detected"
      return
    fi
    _final_identities["$_ws_file"]="$_ident"
  done < <(find "$artifacts_dir" -maxdepth 1 -name 'workflow-state-*.json' -type f 2>/dev/null)

  # Compare initial and final identities (content-based, not mtime).
  local _race_detected=false
  local _race_reason=""
  local _k
  # Detect content-identity changes on shared files + files that disappeared.
  for _k in "${!_initial_identities[@]}"; do
    if [ -z "${_final_identities[$_k]+x}" ]; then
      _race_detected=true
      _race_reason="workflow-state '$_k' disappeared during scan"
      break
    fi
    if [ "${_initial_identities[$_k]}" != "${_final_identities[$_k]}" ]; then
      _race_detected=true
      _race_reason="workflow-state '$_k' content identity changed during scan (${_initial_identities[$_k]} → ${_final_identities[$_k]})"
      break
    fi
  done
  # Detect files that appeared during the scan.
  if [ "$_race_detected" = false ]; then
    for _k in "${!_final_identities[@]}"; do
      if [ -z "${_initial_identities[$_k]+x}" ]; then
        _race_detected=true
        _race_reason="workflow-state '$_k' appeared during scan"
        break
      fi
    done
  fi

  if [ "$_race_detected" = true ]; then
    echo "# prune-scan: cross-worktree race detected — $_race_reason — aborting artifacts category (fail-closed). Re-run after concurrent /cauto operations complete." >&2
    _restore_noglob
    _emit_wrapped_empty "fail-closed" "workflow-state-race-detected"
    return
  fi

  # ===== Step 5: emit wrapped output =====
  local cands_json
  if [ ${#candidates[@]} -eq 0 ]; then
    cands_json="[]"
  else
    local IFS=","
    cands_json="[${candidates[*]}]"
    unset IFS
  fi

  # skipped_unclassified array
  local skipped_json="["
  local first_sk=true
  local pat
  for pat in "${!skipped_unclassified[@]}"; do
    if [ "$first_sk" = true ]; then first_sk=false; else skipped_json+=","; fi
    skipped_json+="$(jq -nc --arg p "$pat" --argjson c "${skipped_unclassified[$pat]}" '{pattern: $p, count: $c}')"
  done
  skipped_json+="]"

  # protection_set
  local lb_json lbs_json lts_json sws_json
  lb_json="$(paths_to_json_array "${branch_arr[@]}")"
  lbs_json="$(paths_to_json_array "${live_branch_slugs[@]}")"
  lts_json="$(paths_to_json_array "${live_task_slugs[@]}")"
  sws_json="$(paths_to_json_array "${workflow_state_files[@]}")"

  # protection_status
  local ps_json
  ps_json="$(jq -nc --arg s "$task_protection_status" --arg r "$task_protection_reason" \
    '{task_slug: $s, reason: (if $r == "" then null else $r end)}')"

  jq -nc \
    --argjson c "$cands_json" \
    --argjson s "$skipped_json" \
    --argjson lb "$lb_json" \
    --argjson lbs "$lbs_json" \
    --argjson lts "$lts_json" \
    --argjson sws "$sws_json" \
    --argjson ps "$ps_json" \
    --argjson lsi "[]" \
    '{
      candidates: $c,
      skipped_unclassified: $s,
      protection_set: {
        live_branches: $lb,
        live_branch_slugs: $lbs,
        live_task_slugs: $lts,
        live_session_ids: $lsi,
        source_workflow_state_files: $sws
      },
      protection_status: $ps
    }'

  # ===== Step 6: --update-baseline (explicit only; INV-011) =====
  if [ "$UPDATE_BASELINE" = true ]; then
    mkdir -p "$BASE_DIR/.correctless/meta"
    local cp_json
    cp_json="$(printf '%s\n' $artifact_patterns | jq -R . | jq -sc .)"
    echo "{\"patterns\": $cp_json}" > "$baseline_file"
  fi

  # MA2-004 fix (v5): restore noglob state on the success path.
  _restore_noglob
}

_emit_wrapped_empty() {
  local task_status="${1:-ok}" reason="${2:-}"
  jq -nc \
    --arg ts "$task_status" \
    --arg r "$reason" \
    '{
      candidates: [],
      skipped_unclassified: [],
      protection_set: {
        live_branches: [],
        live_branch_slugs: [],
        live_task_slugs: [],
        live_session_ids: [],
        source_workflow_state_files: []
      },
      protection_status: {
        task_slug: $ts,
        reason: (if $r == "" then null else $r end)
      }
    }'
}

# ---- deferred ----
scan_deferred() {
  local def_file="$BASE_DIR/.correctless/meta/deferred-findings.json"
  if [ ! -f "$def_file" ]; then
    echo "[]"
    return
  fi

  local findings
  findings="$(jq -c '.findings[] | select(.status == "open")' "$def_file" 2>/dev/null)" || { echo "[]"; return; }

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
        "$(paths_to_json_array "$source_file")" "[]" "false" "unclassified" "exact-token")"
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

  local actual_tests actual_scripts actual_skills actual_agents
  actual_tests="$(find "$BASE_DIR/tests" -name 'test-*.sh' 2>/dev/null | wc -l | tr -d ' ')" || actual_tests=0
  # "shared scripts" = top-level scripts/*.sh only; scripts/wf/ modules are
  # described separately in the stats-table prose, not in the shared total (#161).
  actual_scripts="$(find "$BASE_DIR/scripts" -maxdepth 1 -name '*.sh' 2>/dev/null | wc -l | tr -d ' ')" || actual_scripts=0
  # Skill dirs exclude the project's underscore-prefixed helper convention
  # (skills/_shared is not a skill) (#161 Bug A).
  actual_skills="$(find "$BASE_DIR/skills" -mindepth 1 -maxdepth 1 -type d -not -name '_*' 2>/dev/null | wc -l | tr -d ' ')" || actual_skills=0
  actual_agents="$(find "$BASE_DIR/agents" -name '*.md' 2>/dev/null | wc -l | tr -d ' ')" || actual_agents=0

  local content
  content="$(cat "$agent_ctx")"

  local label stated actual
  for label in skills tests scripts agents; do
    # Anchor the stated count to the AGENT_CONTEXT.md stats-table row for this
    # component: `| {Label} | <location> | {N} <unit> ... |`. The number must be
    # the FIRST token of the purpose (3rd) cell. This rejects prose digits such
    # as the "003" in "PAT-003 script" (#161 / PMB-016 Bug B); rows with no
    # leading count (e.g. the Agents row) yield empty -> skipped.
    stated="$(printf '%s\n' "$content" \
      | grep -oiE "^\|[[:space:]]*${label}[[:space:]]*\|[^|]*\|[[:space:]]*[0-9]+" \
      | head -1 | grep -oE '[0-9]+$')" || stated=""
    case "$label" in
      skills)  actual="$actual_skills" ;;
      tests)   actual="$actual_tests" ;;
      scripts) actual="$actual_scripts" ;;
      agents)  actual="$actual_agents" ;;
    esac
    if [ -n "$stated" ] && [ "$stated" != "$actual" ]; then
      local candidate
      candidate="$(emit_candidate "${label}-count" "counts" "Stated $stated ${label} but found $actual" "low" "[]" "[]" "false" "unclassified" "exact-token")"
      candidates+=("$candidate")
    fi
  done

  emit_simple_array candidates
}

# ---- crossrefs ----
scan_crossrefs() {
  if ! _arch_has_scan_sources; then
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
  done < <(_emit_arch_scan_content)

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

  if [ ${#live_paths[@]} -gt 0 ] && [ ${#dead_paths[@]} -gt 0 ]; then
    local candidate
    candidate="$(emit_candidate "$entry_id" "crossrefs" "Stale cross-references to deleted files" "medium" \
      "$(paths_to_json_array "${dead_paths[@]}")" "$(paths_to_json_array "${live_paths[@]}")" "false" "unclassified" "exact-token")"
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

    [ -d "$specs_dir/archived" ] && [ -f "$specs_dir/archived/$spec_name.md" ] && continue

    local spec_branch=""
    spec_branch="$(grep -E '^\- \*\*Branch\*\*:' "$spec_file" 2>/dev/null | sed 's/.*: //' | tr -d ' ')" || true
    [ -z "$spec_branch" ] && continue

    local branch_exists=false
    while IFS= read -r b; do
      b="$(echo "$b" | tr -d ' ')"
      [ -z "$b" ] && continue
      if [ "$b" = "$spec_branch" ]; then
        branch_exists=true
        break
      fi
    done <<< "$branches"

    [ "$branch_exists" = true ] && continue

    local merge_date_str=""
    merge_date_str="$(cd "$BASE_DIR" && git log --all --grep="$spec_branch" --format='%ci' 2>/dev/null | head -1)" || true

    if [ -z "$merge_date_str" ]; then
      local state_files
      state_files="$(find "$BASE_DIR/.correctless/artifacts" -name "workflow-state-*.json" -type f 2>/dev/null)" || true
      while IFS= read -r sf; do
        [ -z "$sf" ] && continue
        local sf_task=""
        # INV-014 — no silent || continue on jq failure; assign empty and let comparison fail naturally
        if ! sf_task="$(jq -r '.task // empty' "$sf" 2>/dev/null)"; then
          echo "# prune-scan: workflow-state $sf parse failure in scan_specs — skipping this file (specs category only; not category-aborting)" >&2
          sf_task=""
        fi
        if [ -n "$sf_task" ] && [ "$sf_task" = "$spec_name" ]; then
          merge_date_str="$(jq -r '.started_at // empty' "$sf" 2>/dev/null)" || true
          break
        fi
      done <<< "$state_files"
    fi

    if [ -z "$merge_date_str" ]; then
      continue
    fi

    local merge_epoch
    merge_epoch="$(date -d "$merge_date_str" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$merge_date_str" +%s 2>/dev/null || date -j -f "%Y-%m-%d %H:%M:%S %z" "$merge_date_str" +%s 2>/dev/null)" || continue

    local age=$((now_epoch - merge_epoch))

    if [ "$age" -ge "$thirty_days" ]; then
      local risk="medium"
      if [ "$age" -ge "$ninety_days" ]; then
        risk="low"
      fi

      local candidate
      candidate="$(emit_candidate "$spec_name" "specs" "Spec for merged branch ($spec_branch), ${age} seconds post-merge" "$risk" \
        "$(paths_to_json_array ".correctless/specs/$spec_name.md")" "[]" "false" "unclassified" "exact-token")"
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
  entries="$(jq -c '.drift_debt[]' "$debt_file" 2>/dev/null)" || { echo "[]"; return; }

  while IFS= read -r entry; do
    [ -z "$entry" ] && continue
    local status eid resolved_at created_at
    status="$(echo "$entry" | jq -r '.status // empty')"
    eid="$(echo "$entry" | jq -r '.id // empty')"

    if [ "$status" != "resolved" ] && [ "$status" != "wont-fix" ]; then
      continue
    fi

    resolved_at="$(echo "$entry" | jq -r '(.resolved_at // .resolved_date // .resolved) // empty')"
    created_at="$(echo "$entry" | jq -r '(.created_at // .detected) // empty')"
    local date_str="${resolved_at:-$created_at}"
    [ -z "$date_str" ] && continue

    local entry_epoch
    entry_epoch="$(date -d "$date_str" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$date_str" +%s 2>/dev/null)" || continue

    local age=$((now_epoch - entry_epoch))
    if [ "$age" -ge "$ninety_days" ]; then
      local candidate
      candidate="$(emit_candidate "$eid" "driftdebt" "Resolved/wont-fix drift debt older than 90 days" "low" "[]" "[]" "false" "unclassified" "exact-token")"
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
  __noop__) : ;;
  *)
    echo "[]"
    ;;
esac
