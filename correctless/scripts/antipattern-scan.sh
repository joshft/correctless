#!/usr/bin/env bash
# Correctless — AI Antipattern Scanner
# Phase-transition script (NOT a hook). Invoked by /ctdd and /cverify.
# Scans files changed on current branch for common AI-generated code antipatterns.
# Outputs findings as JSON to stdout.
#
# Usage: bash scripts/antipattern-scan.sh [base-branch]
#   base-branch: Branch to diff against (default: main)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
CONFIG_FILE="$REPO_ROOT/.correctless/config/workflow-config.json"

# ============================================
# Global state
# ============================================

declare -a FINDINGS=()
declare -a ERRORS=()
declare -A FILE_FINDING_COUNTS=()
declare -A FILE_CAPPED=()
declare -A SEEN_FINDINGS=()
MAX_FINDINGS_PER_FILE=20

FINDING_COUNTER=0

# ============================================
# Pattern metadata lookup table
# ============================================

declare -A PATTERN_META=(
    ["empty-catch"]="high|Empty catch block swallows errors|error-handling"
    ["bare-except"]="high|Bare except or swallowed exception|error-handling"
    ["empty-error-handle"]="high|Empty error handling block|error-handling"
    ["error-suppression"]="high|Error suppression with || true or || :|error-handling"
    ["console-debug"]="medium|Debug logging left in production code|debug-logging"
    ["debug-print"]="medium|Debug print statement left in production code|debug-logging"
    ["debug-echo"]="low|Debug echo statement in script|debug-logging"
    ["excessive-any"]="medium|Excessive use of 'any' type|type-safety"
    ["excessive-unwrap"]="medium|Excessive use of unwrap()|error-handling"
    ["trivial-assertion"]="low|Trivial assertion that always passes|testing"
    ["placeholder"]="high|Placeholder credential or value left in code|security"
    ["todo-comment"]="low|TODO/FIXME/HACK comment left in code|code-quality"
    ["todo-macro"]="low|todo!() macro left in code|code-quality"
    ["jq-slurp-jsonl"]="high|jq -s (slurp) on JSONL file — malformed lines cause total parse failure (AP-014)|data-integrity"
)

# ============================================
# Configuration
# ============================================

load_config() {
  local -a exclude_paths=()
  exclude_paths+=("vendor/" "node_modules/" "generated/" "dist/")

  if [ -f "$CONFIG_FILE" ] && command -v jq >/dev/null 2>&1; then
    local config_excludes
    config_excludes="$(jq -r '.antipattern_scan.exclude_paths // [] | .[]' "$CONFIG_FILE" 2>/dev/null || true)"
    while IFS= read -r p; do
      [ -n "$p" ] && exclude_paths+=("$p")
    done <<< "$config_excludes"
  fi

  EXCLUDE_PATHS=("${exclude_paths[@]}")
}

load_test_patterns() {
  TEST_FILE_PATTERN=""
  if [ -f "$CONFIG_FILE" ] && command -v jq >/dev/null 2>&1; then
    TEST_FILE_PATTERN="$(jq -r '.patterns.test_file // ""' "$CONFIG_FILE" 2>/dev/null || true)"
  fi
}

# ============================================
# Test file detection (R-012)
# ============================================

is_test_file() {
  local filepath="$1"
  local basename
  basename="$(basename "$filepath")"

  if [ -n "$TEST_FILE_PATTERN" ]; then
    # shellcheck disable=SC2254
    case "$basename" in
      $TEST_FILE_PATTERN) return 0 ;;
    esac
    return 1
  fi

  case "$basename" in
    *.test.*|*.spec.*) return 0 ;;
    test_*.py) return 0 ;;
    *_test.go) return 0 ;;
    *_test.rs) return 0 ;;
  esac

  case "$filepath" in
    *__tests__/*|tests/*|*/tests/*) return 0 ;;
  esac

  return 1
}

# ============================================
# Exclude path filtering (R-010)
# ============================================

is_excluded() {
  local filepath="$1"
  for excl in "${EXCLUDE_PATHS[@]}"; do
    case "$filepath" in
      "$excl"*) return 0 ;;
    esac
  done
  return 1
}

# ============================================
# File detection (R-001)
# ============================================

get_changed_files() {
  local base="$1"
  local current_branch
  current_branch="$(git branch --show-current 2>/dev/null || true)"

  if [ -n "$current_branch" ] && [ "$current_branch" = "$base" ]; then
    echo "note: on default branch ($base), nothing to scan" >&2
    return 1
  fi

  if [ -z "$current_branch" ]; then
    echo "warning: detached HEAD, falling back to all tracked files" >&2
    local files
    files="$(git ls-files 2>/dev/null || true)"
    if [ -n "$files" ]; then
      echo "$files"
    fi
    return 0
  fi

  local files
  if files="$(git diff --name-only "$base"...HEAD 2>/dev/null)" && [ -n "$files" ]; then
    echo "$files"
    return 0
  fi

  echo "warning: git diff $base...HEAD failed, falling back to HEAD diff" >&2
  if files="$(git diff --name-only HEAD 2>/dev/null)" && [ -n "$files" ]; then
    echo "$files"
    return 0
  fi

  echo "warning: git diff HEAD failed, falling back to all tracked files" >&2
  files="$(git ls-files 2>/dev/null || true)"
  if [ -n "$files" ]; then
    echo "$files"
    return 0
  fi

  return 0
}

# ============================================
# Finding construction (R-003)
# ============================================

add_finding() {
  local pattern="$1" file line description severity category

  if [ $# -eq 3 ]; then
    # Lookup-table call: pattern file line
    file="$2"; line="$3"
    local meta="${PATTERN_META[$pattern]:-}"
    if [ -z "$meta" ]; then
      add_error "Unknown pattern '$pattern' — no metadata in PATTERN_META"
      return 0
    fi
    IFS='|' read -r severity description category <<< "$meta"
  else
    add_error "add_finding called with unexpected $# arguments (expected 3)"
    return 0
  fi

  # Dedup via associative array (avoids O(n^2) scan)
  local dedup_key="$file:$line:$pattern"
  if [ "${SEEN_FINDINGS[$dedup_key]+_}" ]; then
    return 0
  fi
  SEEN_FINDINGS[$dedup_key]=1

  # Per-file cap (R-010)
  local current_count="${FILE_FINDING_COUNTS[$file]:-0}"
  if [ "$current_count" -ge "$MAX_FINDINGS_PER_FILE" ]; then
    FILE_CAPPED[$file]=$(( ${FILE_CAPPED[$file]:-0} + 1 ))
    return 0
  fi
  FILE_FINDING_COUNTS[$file]=$((current_count + 1))

  FINDING_COUNTER=$((FINDING_COUNTER + 1))
  local id
  printf -v id 'AP-%03d' "$FINDING_COUNTER"

  # Store as unit-separator-delimited record — converted to JSON in emit_json
  # Using ASCII unit separator (\x1f) instead of tab to prevent corruption
  # from filenames containing tabs (QA-015)
  local us=$'\x1f'
  FINDINGS+=("${id}${us}${pattern}${us}${severity}${us}${file}${us}${line}${us}${description}${us}${category}")
}

add_error() {
  local msg="$1"
  ERRORS+=("$msg")
}

# ============================================
# Shared helpers for language checks
# ============================================

check_multiline_empty_block() {
  local file="$1" open_regex="$2" pattern_id="$3"
  local close_regex='^[[:space:]]*\}[[:space:]]*$'

  local prev_num=0 has_prev=false
  while IFS= read -r raw_line; do
    local cur_num cur_content
    cur_num="${raw_line%%:*}"
    cur_content="${raw_line#*:}"

    if [ "$has_prev" = true ]; then
      if [[ "$cur_content" =~ ^[[:space:]]*\}[[:space:]]*$ ]]; then
        if [ "$cur_num" -eq $((prev_num + 1)) ]; then
          add_finding "$pattern_id" "$file" "$prev_num"
        fi
      fi
      has_prev=false
      prev_num=0
    fi

    if [[ "$cur_content" =~ $open_regex ]]; then
      has_prev=true
      prev_num="$cur_num"
    fi
  done < <(grep -nE "($open_regex|$close_regex)" "$file" 2>/dev/null || true)
}

check_debug_prints() {
  local file="$1" is_test="$2" regex="$3" pattern_id="$4"
  if [ "$is_test" = false ]; then
    while IFS=: read -r line_num _; do
      [ -n "$line_num" ] && add_finding "$pattern_id" "$file" "$line_num"
    done < <(grep -nE "$regex" "$file" 2>/dev/null || true)
  fi
}

check_todo_comments() {
  local file="$1" comment_regex="$2"
  while IFS=: read -r line_num _; do
    [ -n "$line_num" ] && add_finding "todo-comment" "$file" "$line_num"
  done < <(grep -nE "$comment_regex" "$file" 2>/dev/null || true)
}

# ============================================
# Language-specific checks
# ============================================

# --- JS/TS checks (R-004) ---

check_js_ts() {
  local file="$1"
  local is_test=false
  is_test_file "$file" && is_test=true

  # (a) Empty catch blocks — single-line
  while IFS=: read -r line_num _; do
    [ -n "$line_num" ] && add_finding "empty-catch" "$file" "$line_num"
  done < <(grep -nE 'catch[[:space:]]*(\([^)]*\))?[[:space:]]*\{[[:space:]]*\}' "$file" 2>/dev/null || true)

  # (a) Multi-line empty catch
  check_multiline_empty_block "$file" 'catch[[:space:]]*(\([^)]*\))?[[:space:]]*\{[[:space:]]*$' "empty-catch"

  # (b) console.log / console.debug in non-test files
  check_debug_prints "$file" "$is_test" 'console\.(log|debug)\(' "console-debug"

  # (c) as any / : any count > 3
  local any_count
  any_count=$(grep -oE '(: any|as any)([^[:alnum:]_]|$)' "$file" 2>/dev/null | wc -l || true)
  any_count=${any_count:-0}
  if [ "$any_count" -gt 3 ]; then
    local first_line
    first_line="$(grep -nE '(: any|as any)([^[:alnum:]_]|$)' "$file" 2>/dev/null | head -1 | cut -d: -f1)"
    if [ -n "$first_line" ]; then
      add_finding "excessive-any" "$file" "$first_line"
    fi
  fi

  # (d) Trivial assertions in test files only
  if [ "$is_test" = true ]; then
    while IFS=: read -r line_num _; do
      [ -n "$line_num" ] && add_finding "trivial-assertion" "$file" "$line_num"
    done < <(grep -nE 'expect\((true|1)\)(\.toBe\((true|1)\))?' "$file" 2>/dev/null || true)
  fi
}

# --- Python checks (R-005) ---

check_python() {
  local file="$1"
  local is_test=false
  is_test_file "$file" && is_test=true

  # (a) Bare except / except Exception: pass / except Exception as e: pass
  while IFS=: read -r line_num _; do
    [ -n "$line_num" ] && add_finding "bare-except" "$file" "$line_num"
  done < <(grep -nE '^[[:space:]]*(except[[:space:]]*:|except[[:space:]][[:space:]]*Exception([[:space:]][[:space:]]*as[[:space:]][[:space:]]*[[:alnum:]_]+)?[[:space:]]*:[[:space:]]*pass)' "$file" 2>/dev/null || true)

  # (b) print() in non-test
  check_debug_prints "$file" "$is_test" '(^|[^a-zA-Z_])print\(' "debug-print"

  # (c) TODO / FIXME / HACK
  check_todo_comments "$file" '#[[:space:]]*(TODO|FIXME|HACK)'
}

# --- Go checks (R-006) ---

check_go() {
  local file="$1"
  local is_test=false
  is_test_file "$file" && is_test=true

  # (a) Empty error handling — single-line
  while IFS=: read -r line_num _; do
    [ -n "$line_num" ] && add_finding "empty-error-handle" "$file" "$line_num"
  done < <(grep -nE 'if[[:space:]][[:space:]]*err[[:space:]]*!=[[:space:]]*nil[[:space:]]*\{[[:space:]]*\}' "$file" 2>/dev/null || true)

  # (a) Multi-line empty error handling
  check_multiline_empty_block "$file" 'if[[:space:]][[:space:]]*err[[:space:]]*!=[[:space:]]*nil[[:space:]]*\{[[:space:]]*$' "empty-error-handle"

  # (b) fmt.Println / fmt.Printf in non-test
  check_debug_prints "$file" "$is_test" 'fmt\.(Println|Printf)\(' "debug-print"

  # (c) TODO / FIXME / HACK
  check_todo_comments "$file" '//[[:space:]]*(TODO|FIXME|HACK)'
}

# --- Shell checks (R-007) ---

check_shell() {
  local file="$1"
  local is_test=false
  is_test_file "$file" && is_test=true

  # (a) || true / || : after non-allowlisted commands
  while IFS=: read -r line_num line_content; do
    [ -n "$line_num" ] || continue

    local allowed=false
    case "$line_content" in
      *cd\ *|*cd$'\t'*) allowed=true ;;
      *command\ -v*|*command$'\t'-v*) allowed=true ;;
      *which\ *|*which$'\t'*) allowed=true ;;
      *pushd\ *|*pushd$'\t'*) allowed=true ;;
      *popd\ *|*popd$'\t'*|*popd\|*) allowed=true ;;
    esac
    # Pipeline tail exemptions: | wc, | grep -c, | grep -q
    case "$line_content" in
      *\|\ wc*|*\|wc*) allowed=true ;;
      *\|\ grep\ -c*|*\|grep\ -c*) allowed=true ;;
      *\|\ grep\ -q*|*\|grep\ -q*) allowed=true ;;
    esac

    if [ "$allowed" = false ]; then
      add_finding "error-suppression" "$file" "$line_num"
    fi
  done < <(grep -nE '\|\|[[:space:]]*(true|:)[[:space:]]*$' "$file" 2>/dev/null || true)

  # (b) echo statements in non-test files
  if [ "$is_test" = false ]; then
    local -a exempt_ranges=()
    local in_func="" func_start=0 brace_depth=0
    local line_idx=0
    while IFS= read -r fline; do
      line_idx=$((line_idx + 1))
      if [[ "$fline" =~ ^[[:space:]]*(info|warn|error|debug|usage|die)[[:space:]]*\(\)[[:space:]]*\{ ]]; then
        in_func="yes"
        func_start=$line_idx
        brace_depth=1
      elif [ -n "$in_func" ]; then
        # Count all opening and closing braces on the line
        local opens closes
        opens=$(echo "$fline" | grep -o '{' | wc -l)
        closes=$(echo "$fline" | grep -o '}' | wc -l)
        brace_depth=$((brace_depth + opens - closes))
        if [ "$brace_depth" -le 0 ]; then
          exempt_ranges+=("$func_start-$line_idx")
          in_func=""
          brace_depth=0
        fi
      fi
    done < "$file"

    while IFS=: read -r line_num line_content; do
      [ -n "$line_num" ] || continue

      # Check if line is inside an exempt function
      local in_exempt=false
      for range in "${exempt_ranges[@]}"; do
        local rstart="${range%-*}"
        local rend="${range#*-}"
        if [ "$line_num" -ge "$rstart" ] && [ "$line_num" -le "$rend" ]; then
          in_exempt=true
          break
        fi
      done
      [ "$in_exempt" = true ] && continue

      # Check exempt patterns via bash matching
      case "$line_content" in
        *'echo ">>>'*|*"echo '>>>"*) continue ;;
        *'echo "==='*|*"echo '==="*) continue ;;
        *'echo "  PASS:'*|*"echo '  PASS:"*) continue ;;
        *'echo "  FAIL:'*|*"echo '  FAIL:"*) continue ;;
        *'echo ""'*|*"echo ''"*) continue ;;
      esac

      add_finding "debug-echo" "$file" "$line_num"
    done < <(grep -nE '^[[:space:]]*echo[[:space:]]' "$file" 2>/dev/null || true)
  fi

  # (c) TODO / FIXME / HACK
  check_todo_comments "$file" '#[[:space:]]*(TODO|FIXME|HACK)'

  # (d) AP-014: jq -s / jq --slurp on JSONL — malformed lines cause total parse failure
  # JSONL consumers must use jq -R with try/catch, never jq -s (ABS-006)
  while IFS=: read -r line_num _; do
    [ -n "$line_num" ] || continue
    add_finding "jq-slurp-jsonl" "$file" "$line_num"
  done < <(grep -nE 'jq[[:space:]]+(--slurp|-s[[:space:]])' "$file" 2>/dev/null || true)
}

# --- Rust checks (R-008) ---

check_rust() {
  local file="$1"
  local is_test=false
  is_test_file "$file" && is_test=true

  # (a) unwrap() count > 3 in non-test
  if [ "$is_test" = false ]; then
    local unwrap_count
    unwrap_count=$(grep -oE '\.unwrap\(\)' "$file" 2>/dev/null | wc -l || true)
    unwrap_count=${unwrap_count:-0}
    if [ "$unwrap_count" -gt 3 ]; then
      local first_line
      first_line="$(grep -nE '\.unwrap\(\)' "$file" 2>/dev/null | head -1 | cut -d: -f1)"
      if [ -n "$first_line" ]; then
        add_finding "excessive-unwrap" "$file" "$first_line"
      fi
    fi
  fi

  # (b) println! / dbg! in non-test
  check_debug_prints "$file" "$is_test" '(println!|dbg!)\(' "debug-print"

  # (c) todo!() macro
  while IFS=: read -r line_num _; do
    [ -n "$line_num" ] && add_finding "todo-macro" "$file" "$line_num"
  done < <(grep -nE 'todo!\(' "$file" 2>/dev/null || true)
}

# ============================================
# Universal placeholder check (R-018)
# ============================================

check_placeholders() {
  local file="$1"
  local ext="${file##*.}"
  ext="${ext,,}"

  while IFS=: read -r line_num line_content; do
    [ -n "$line_num" ] || continue

    case "$ext" in
      js|ts|tsx|jsx|mjs|cjs|mts|cts|go|rs)
        if [[ "$line_content" =~ ^[[:space:]]*// ]]; then
          continue
        fi
        ;;
      py|sh|yml|yaml|toml|cfg|ini|env)
        if [[ "$line_content" =~ ^[[:space:]]*# ]]; then
          continue
        fi
        ;;
    esac

    add_finding "placeholder" "$file" "$line_num"
  done < <(grep -InE '(your-api-key|changeme|REPLACE_ME|yourdomain\.com|localhost:([^0-9]|$))' "$file" 2>/dev/null || true)
}

# ============================================
# Extension routing (R-002)
# ============================================

route_by_extension() {
  local file="$1"
  local ext="${file##*.}"
  ext="${ext,,}"

  case "$ext" in
    js|ts|tsx|jsx|mjs|cjs|mts|cts)
      check_js_ts "$file"
      ;;
    py)
      check_python "$file"
      ;;
    go)
      check_go "$file"
      ;;
    sh)
      check_shell "$file"
      ;;
    rs)
      check_rust "$file"
      ;;
  esac
}

# ============================================
# JSON output (R-003)
# ============================================

emit_json() {
  local result_json

  if [ ${#FINDINGS[@]} -gt 0 ]; then
    # Convert unit-separator-delimited records to JSON in a single jq invocation
    # Uses ASCII unit separator (\u001f) instead of tab to prevent field corruption
    # from filenames containing tabs (QA-015)
    local raw_data
    raw_data="$(IFS=$'\n'; echo "${FINDINGS[*]}")"

    local items_json
    items_json="$(echo "$raw_data" | jq -R 'split("\u001f") | {id: .[0], pattern: .[1], severity: .[2], file: .[3], line: (.[4] | tonumber? // 0), description: .[5], category: .[6]}' | jq -s '.')" || items_json="[]"

    result_json="$(jq -n --argjson f "$items_json" '{findings: $f}')"
  else
    result_json="$(jq -n '{findings: []}')"
  fi

  # Build summaries for capped files in a single pass
  if [ ${#FILE_CAPPED[@]} -gt 0 ]; then
    local -a summary_strings=()
    for file in "${!FILE_CAPPED[@]}"; do
      summary_strings+=("+${FILE_CAPPED[$file]} more in $file")
    done
    local summaries_json
    summaries_json="$(jq -n '$ARGS.positional' --args "${summary_strings[@]}")"
    result_json="$(echo "$result_json" | jq --argjson s "$summaries_json" '. + {summaries: $s}')"
  fi

  if [ ${#ERRORS[@]} -gt 0 ]; then
    local errors_json
    # Use jq --args to pass each error as a separate argument, avoiding
    # newline-splitting corruption when messages contain newlines (QA-016)
    errors_json="$(jq -n '$ARGS.positional' --args "${ERRORS[@]}")"
    result_json="$(echo "$result_json" | jq --argjson e "$errors_json" '. + {errors: $e}')"
  fi

  echo "$result_json"
}

# ============================================
# Main
# ============================================

main() {
  local base="${1:-main}"

  if ! command -v jq >/dev/null 2>&1; then
    echo '{"findings":[],"errors":["jq not installed — scanner cannot run"]}'
    exit 0
  fi

  load_config
  load_test_patterns

  local changed_files
  if ! changed_files="$(get_changed_files "$base")"; then
    jq -n '{findings: []}'
    exit 0
  fi

  if [ -z "$changed_files" ]; then
    echo "Deterministic scan found 0 antipatterns" >&2
    jq -n '{findings: []}'
    exit 0
  fi

  while IFS= read -r file; do
    [ -z "$file" ] && continue

    if is_excluded "$file"; then
      continue
    fi

    # Broken symlink check must come before -e (which follows symlinks)
    if [ -L "$file" ] && [ ! -e "$file" ]; then
      add_error "Failed to scan $file: broken symlink"
      continue
    fi

    if [ ! -e "$file" ]; then
      add_error "Failed to scan $file: file not found (deleted?)"
      continue
    fi

    if [ ! -r "$file" ]; then
      add_error "Failed to scan $file: not readable"
      continue
    fi

    if [ ! -s "$file" ]; then
      continue
    fi

    if ! grep -Iq . "$file" 2>/dev/null; then
      add_error "Failed to scan $file: binary file"
      continue
    fi

    route_by_extension "$file"
    check_placeholders "$file"

  done <<< "$changed_files"

  local output
  output="$(emit_json)"

  local finding_count
  finding_count="$(echo "$output" | jq '.findings | length')"

  echo "Deterministic scan found $finding_count antipatterns" >&2

  local artifact_dir="$REPO_ROOT/.correctless/artifacts"
  if [ -d "$artifact_dir" ]; then
    local slug
    if slug="$(branch_slug 2>/dev/null)"; then
      echo "$output" > "$artifact_dir/antipattern-findings-${slug}.json"
    fi
  fi

  echo "$output"
}

main "$@"
