#!/usr/bin/env bash
# shellcheck disable=SC2254
# HOOK_TYPE: PreToolUse
# HOOK_MATCHER: Edit|Write|MultiEdit|NotebookEdit|CreateFile|Bash
# Correctless — PreToolUse sensitive file protection hook
# Blocks the agent from modifying sensitive files (.env, credentials, keys, etc.)
# Independent of workflow state — no overrides, no phase exceptions.
#
# Called by Claude Code as a PreToolUse hook. Receives tool info on stdin as JSON:
#   { "tool_name": "Edit", "tool_input": { "file_path": "...", ... } }
#
# Exit codes:
#   0 — allow the operation
#   2 — block the operation (message printed to stderr)
# SC2254 disabled: unquoted $pat in case is intentional — we need glob matching

set -euo pipefail

# Disable glob expansion — patterns like *.pem must not expand to filenames
set -f

# ============================================
# STEP 1: Check jq availability (EA-004)
# ============================================

command -v jq >/dev/null 2>&1 || { echo "BLOCKED [sensitive-file]: jq not found" >&2; exit 2; }

# ============================================
# STEP 2: Parse stdin JSON (single jq bulk call)
# ============================================

INPUT="$(cat)"
TOOL_NAME="" TOOL_INPUT_FILE="" TOOL_INPUT_COMMAND="" TOOL_INPUT_EDITS=""
_PARSED="$(echo "$INPUT" | jq -r '
  @sh "TOOL_NAME=\(.tool_name // "")",
  @sh "TOOL_INPUT_FILE=\(.tool_input.file_path // "")",
  @sh "TOOL_INPUT_COMMAND=\(.tool_input.command // "")",
  @sh "TOOL_INPUT_EDITS=\([.tool_input.edits[]?.file_path // empty] | join("\n"))"
' 2>/dev/null)" || true
# Fail-closed: if jq produced no output (parse failure), block the operation (DA-003)
if [ -z "$_PARSED" ]; then
  echo "BLOCKED [fail-closed]: failed to parse tool input JSON" >&2
  exit 2
fi
eval "$_PARSED"

# ============================================
# STEP 3: Fast-path bail — only write tools (INV-010)
# ============================================

# Exit 0 immediately for Read, Grep, Glob, etc. — BEFORE loading config
case "$TOOL_NAME" in
  Edit|Write|MultiEdit|NotebookEdit|CreateFile) ;;
  Bash)
    if [ -z "$TOOL_INPUT_COMMAND" ]; then exit 0; fi
    ;;
  *)
    exit 0
    ;;
esac

# ============================================
# STEP 4: Source shared library and detect write patterns (INV-002, ABS-001)
# ============================================
# QA-002: lib.sh is required for Bash (fail-closed: write-pattern detection needed).
# For non-Bash tools (Edit/Write/MultiEdit), lib.sh is optional — config_file
# has its own fallback, and these tools don't need write-pattern detection.

_source_lib_sh() {
  local _LIB_DIR
  _LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" 2>/dev/null && pwd || true)"
  if [ -n "$_LIB_DIR" ] && [ -f "$_LIB_DIR/lib.sh" ]; then
    # shellcheck source=../scripts/lib.sh
    source "$_LIB_DIR/lib.sh"
  elif [ -f ".correctless/scripts/lib.sh" ]; then
    source ".correctless/scripts/lib.sh"
  else
    return 1
  fi
}

# For Bash, skip non-write commands (INV-003)
if [ "$TOOL_NAME" = "Bash" ]; then
  COMMAND="$TOOL_INPUT_COMMAND"
  _source_lib_sh || { echo "BLOCKED: lib.sh not found — required for write detection" >&2; exit 2; }
  if ! _has_write_pattern "$COMMAND"; then
    exit 0
  fi
else
  # Non-Bash write tools: source lib.sh for config_file() but don't block if missing
  _source_lib_sh || true
fi

# STEP 4a: canonicalize_path v1 sentinel probe (INV-005a) — catches partial
# upgrades where the new guard is paired with an old lib.sh missing the
# function or shipping a divergent implementation.

if ! declare -f canonicalize_path >/dev/null 2>&1 \
   || [ "$(canonicalize_path '__canonicalize_path_v1_probe__/foo' 2>/dev/null || true)" != "__canonicalize_path_v1_probe__/foo" ]; then
  echo "BLOCKED [sensitive-file]: canonicalize_path missing or version mismatch — re-run 'bash setup' to refresh installed scripts" >&2
  exit 2
fi

# ============================================
# STEP 5: Collect file targets to check
# ============================================

collect_targets() {
  case "$TOOL_NAME" in
    Edit|Write|CreateFile|NotebookEdit)
      if [ -n "$TOOL_INPUT_FILE" ]; then
        echo "$TOOL_INPUT_FILE"
      fi
      ;;
    MultiEdit)
      # Iterate all file paths from edits array
      if [ -n "$TOOL_INPUT_EDITS" ]; then
        echo "$TOOL_INPUT_EDITS"
      fi
      if [ -n "$TOOL_INPUT_FILE" ]; then
        echo "$TOOL_INPUT_FILE"
      fi
      ;;
    Bash)
      _extract_bash_targets
      ;;
  esac
}

# Strip shell-quote and interpreter-wrapper bytes iteratively from both ends.
# Required because IFS-splitting on `perl -e "system(q{cat > .env})"` yields
# tokens like `.env}` and `"system` — the matcher only sees the canonical
# path once wrappers are peeled. False-positive risk on legitimate paths
# containing these bytes is accepted per OQ-004.
_strip_quotes() {
  local s="$1" prev
  while :; do
    prev="$s"
    s="${s#[\"\'\{\(\[\\]}"
    s="${s%[\"\'\}\)\];,\\]}"
    [ "$s" = "$prev" ] && break
  done
  echo "$s"
}

# Extract file targets from a Bash command (INV-006, INV-007, INV-007a).
# Over-extracts every non-flag token plus every redirect target — no
# per-command dispatch (PRH-002).
_extract_bash_targets() {
  local cmd="$COMMAND"
  # shellcheck disable=SC2141
  local IFS=$' \t\n;|&()`'
  # Intentional word-split; set -f at top of hook prevents pathname
  # expansion of glob bytes inside the command.
  # shellcheck disable=SC2206
  local -a tokens=($cmd)
  local i=0 tok inner sub_tok

  while [ $i -lt ${#tokens[@]} ]; do
    tok="${tokens[$i]}"
    case "$tok" in
      ">"|">>"|"1>"|"2>"|"&>")
        # Whitespace-separated redirect (INV-007); next token is the target.
        if [ $((i + 1)) -lt ${#tokens[@]} ]; then
          _strip_quotes "${tokens[$((i + 1))]}"
          i=$((i + 2)); continue
        fi
        ;;
      -*)
        ;;
      *)
        # Process substitution (INV-007a) — single-level sub-tokenize.
        # `(` is special in case patterns, so prefix-check via substring.
        if [ "${tok:0:2}" = ">(" ] || [ "${tok:0:2}" = "<(" ]; then
          inner="${tok#?\(}"
          inner="${inner%\)}"
          for sub_tok in $inner; do
            case "$sub_tok" in
              -*) ;;
              *) _strip_quotes "$sub_tok" ;;
            esac
          done
        else
          _strip_quotes "$tok"
        fi
        ;;
    esac
    i=$((i + 1))
  done

  # Inline-attached redirects (INV-007) — `cmd>file`, `cmd2>file`, `cmd&>file`.
  local re='(>{1,2}|[12]>|&>)([^[:space:]\;\|]+)' rest="$cmd"
  while [[ "$rest" =~ $re ]]; do
    _strip_quotes "${BASH_REMATCH[2]}"
    rest="${rest#*${BASH_REMATCH[0]}}"
  done
}

FILE_TARGETS="$(collect_targets)"

# No targets -> nothing to check -> allow (BND-002)
if [ -z "$FILE_TARGETS" ]; then
  exit 0
fi

# ============================================
# STEP 6: Hardcoded default patterns (INV-004)
# ============================================

DEFAULTS=".env
.env.*
*.pem
*.key
*.p12
*.pfx
credentials.json
credentials.yml
service-account*.json
*.secret
*.secrets
secrets.yml
secrets.yaml
secrets.json
.secrets
id_rsa
id_rsa.*
id_ed25519
id_ed25519.*
*.keystore
*.jks
.correctless/preferences.md
.correctless/config/auto-policy.json
.correctless/artifacts/intent-*.md
.correctless/artifacts/workflow-state-*.json
.correctless/artifacts/decision-record-*.md
.correctless/meta/harness-fingerprint.json
.correctless/meta/model-baselines.json
scripts/harness-fingerprint.sh
.correctless/scripts/harness-fingerprint.sh"

# ============================================
# STEP 7: Read custom patterns from config (INV-005)
# ============================================

CUSTOM_PATTERNS=""

# Resolve config file path via lib.sh (falls back to relative if unavailable)
CONFIG_FILE="$(config_file 2>/dev/null)" || CONFIG_FILE=".correctless/config/workflow-config.json"

if [ -f "$CONFIG_FILE" ]; then
  # Read custom_patterns as newline-separated list; on failure, CUSTOM_PATTERNS stays empty
  CUSTOM_PATTERNS="$(jq -r '.protected_files.custom_patterns // [] | if type == "array" then .[] else empty end' "$CONFIG_FILE" 2>/dev/null)" || CUSTOM_PATTERNS=""
fi

# Combine defaults + custom into a single newline-separated list, pre-lowercased
ALL_PATTERNS="$DEFAULTS"
if [ -n "$CUSTOM_PATTERNS" ]; then
  ALL_PATTERNS="$ALL_PATTERNS
$CUSTOM_PATTERNS"
fi
# Pre-lowercase all patterns once (avoids per-file lowercasing in the match loop)
ALL_PATTERNS="${ALL_PATTERNS,,}"

# Canonicalize every pattern once (INV-005, INV-008, PRH-004 — canonical forms
# on both sides). Glob bytes (`*.pem`, `secrets.*`) survive per INV-004.
_canonical_arr=()
while IFS= read -r pat; do
  [ -n "$pat" ] && _canonical_arr+=( "$(canonicalize_path "$pat")" )
done <<< "$ALL_PATTERNS"
_IFS_save="${IFS-}"; IFS=$'\n'
CANONICAL_PATTERNS="${_canonical_arr[*]}"
IFS="$_IFS_save"

# ============================================
# STEP 8: Match each file target against patterns (INV-007, INV-008)
# ============================================

_check_file_against_patterns() {
  # Pre-condition: argument is already a canonical-form path (output of
  # canonicalize_path). Matched against CANONICAL_PATTERNS only. PRH-004.
  local filepath="$1"

  # Case-insensitive: lowercase the filepath (EA-002)
  local filepath_lower="${filepath,,}"
  local basename_lower="${filepath_lower##*/}"

  # Empty basename means no file to check
  if [ -z "$basename_lower" ]; then
    return 1
  fi

  while IFS= read -r pat; do
    [ -z "$pat" ] && continue
    case "$pat" in
      */*)
        # Full-path pattern: match against the full filepath
        # Require path separator boundary to avoid partial dir matches (QA-002)
        case "$filepath_lower" in
          $pat|*/$pat) echo "$pat"; return 0 ;;
        esac
        ;;
      *)
        # Basename pattern: match against basename only
        case "$basename_lower" in
          $pat) echo "$pat"; return 0 ;;
        esac
        ;;
    esac
  done <<< "$CANONICAL_PATTERNS"

  return 1
}

# ============================================
# STEP 9: Check each file target (INV-001, INV-002, BND-004, INV-005)
# ============================================

while IFS= read -r target; do
  [ -z "$target" ] && continue

  # Canonicalize the target before matching (INV-005, PRH-004).
  canonical_target="$(canonicalize_path "$target")"

  matched_pattern=""
  matched_pattern="$(_check_file_against_patterns "$canonical_target")" || true

  if [ -n "$matched_pattern" ]; then
    echo "BLOCKED [sensitive-file]: $target matches protected pattern '$matched_pattern'.
  Edit this file outside Claude Code, or add an exclusion to protected_files.custom_patterns in .correctless/config/workflow-config.json if this file is not actually sensitive." >&2
    exit 2
  fi
done <<< "$FILE_TARGETS"

# ============================================
# STEP 10: No match — allow (INV-006)
# ============================================

exit 0
