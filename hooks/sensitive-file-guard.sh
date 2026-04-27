#!/usr/bin/env bash
# shellcheck disable=SC2254
# HOOK_TYPE: PreToolUse
# HOOK_MATCHER: Edit|Write|MultiEdit|NotebookEdit|CreateFile|Bash
# Rule: .claude/rules/hooks-pretooluse.md (PAT-001 — fail-closed posture)
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

# Strip leading/trailing shell quotes from extracted tokens (QA-006)
_strip_quotes() {
  local s="$1"
  s="${s#\"}"; s="${s%\"}"
  s="${s#\'}"; s="${s%\'}"
  echo "$s"
}

# Extract file targets from Bash commands (INV-002)
# Must handle extensionless files like .env, id_rsa
_extract_bash_targets() {
  local cmd="$COMMAND"

  # Tokenize command on whitespace and shell metacharacters
  # shellcheck disable=SC2141
  local IFS=$' \t\n;|&()`'
  # shellcheck disable=SC2206
  local -a tokens=($cmd)
  local i=0 tok

  while [ $i -lt ${#tokens[@]} ]; do
    tok="${tokens[$i]}"
    case "$tok" in
      # Redirect: extract the NEXT token as target
      ">"|">>")
        local next_i=$((i + 1))
        if [ $next_i -lt ${#tokens[@]} ]; then
          _strip_quotes "${tokens[$next_i]}"
          i=$((i + 2)); continue
        fi
        ;;
      # cp/mv: emit all non-flag arguments
      cp|mv)
        i=$((i + 1))
        while [ $i -lt ${#tokens[@]} ]; do
          case "${tokens[$i]}" in
            -*) ;;  # skip flags
            *) _strip_quotes "${tokens[$i]}" ;;
          esac
          i=$((i + 1))
        done
        continue
        ;;
      # rm/rmdir/unlink: emit all non-flag arguments
      rm|rmdir|unlink)
        i=$((i + 1))
        while [ $i -lt ${#tokens[@]} ]; do
          case "${tokens[$i]}" in
            -*) ;;  # skip flags
            *) _strip_quotes "${tokens[$i]}" ;;
          esac
          i=$((i + 1))
        done
        continue
        ;;
      # tee: emit all non-flag arguments
      tee)
        i=$((i + 1))
        while [ $i -lt ${#tokens[@]} ]; do
          case "${tokens[$i]}" in
            -*) ;;
            *) _strip_quotes "${tokens[$i]}" ;;
          esac
          i=$((i + 1))
        done
        continue
        ;;
      # curl -o / --output: emit output file
      curl)
        i=$((i + 1))
        while [ $i -lt ${#tokens[@]} ]; do
          case "${tokens[$i]}" in
            -o)
              local next_i=$((i + 1))
              if [ $next_i -lt ${#tokens[@]} ]; then
                _strip_quotes "${tokens[$next_i]}"
                i=$((i + 2)); continue
              fi
              ;;
            -o*)
              # Combined short option: -oFILENAME (M4 fix)
              _strip_quotes "${tokens[$i]#-o}"
              ;;
            --output)
              local next_i=$((i + 1))
              if [ $next_i -lt ${#tokens[@]} ]; then
                _strip_quotes "${tokens[$next_i]}"
                i=$((i + 2)); continue
              fi
              ;;
            --output=*)
              _strip_quotes "${tokens[$i]#--output=}"
              ;;
          esac
          i=$((i + 1))
        done
        continue
        ;;
      # wget -O / --output-document: emit output file
      wget)
        i=$((i + 1))
        while [ $i -lt ${#tokens[@]} ]; do
          case "${tokens[$i]}" in
            -O)
              local next_i=$((i + 1))
              if [ $next_i -lt ${#tokens[@]} ]; then
                _strip_quotes "${tokens[$next_i]}"
                i=$((i + 2)); continue
              fi
              ;;
            --output-document)
              # Long option with space-separated value (M4 fix)
              local next_i=$((i + 1))
              if [ $next_i -lt ${#tokens[@]} ]; then
                _strip_quotes "${tokens[$next_i]}"
                i=$((i + 2)); continue
              fi
              ;;
            --output-document=*)
              _strip_quotes "${tokens[$i]#--output-document=}"
              ;;
          esac
          i=$((i + 1))
        done
        continue
        ;;
      # ln: emit last argument (LINK_NAME)
      ln)
        i=$((i + 1))
        local ln_last=""
        while [ $i -lt ${#tokens[@]} ]; do
          case "${tokens[$i]}" in
            -*) ;;  # skip flags
            *) ln_last="${tokens[$i]}" ;;
          esac
          i=$((i + 1))
        done
        if [ -n "$ln_last" ]; then
          _strip_quotes "$ln_last"
        fi
        continue
        ;;
      # sed -i: skip expression, emit file arguments
      sed)
        if [[ "$cmd" =~ sed[[:space:]]+-i ]]; then
          i=$((i + 1))
          # Skip -i flag
          [[ "${tokens[$i]:-}" == -i* ]] && i=$((i + 1))
          # Skip substitution expression (s/.../ or y/.../)
          case "${tokens[$i]:-}" in
            s/*|s\\*|y/*) i=$((i + 1)) ;;
          esac
          # Remaining tokens are file arguments
          while [ $i -lt ${#tokens[@]} ]; do
            case "${tokens[$i]}" in
              -*) ;;
              *) _strip_quotes "${tokens[$i]}" ;;
            esac
            i=$((i + 1))
          done
          continue
        fi
        ;;
      # touch/chmod/chown/chgrp/mkdir: emit all non-flag arguments (R6 fix)
      touch|chmod|chown|chgrp|mkdir)
        i=$((i + 1))
        while [ $i -lt ${#tokens[@]} ]; do
          case "${tokens[$i]}" in
            -*) ;;
            *) _strip_quotes "${tokens[$i]}" ;;
          esac
          i=$((i + 1))
        done
        continue
        ;;
      # tar: emit all non-flag arguments (archive and extracted files)
      tar)
        i=$((i + 1))
        while [ $i -lt ${#tokens[@]} ]; do
          case "${tokens[$i]}" in
            -*) ;;
            *) _strip_quotes "${tokens[$i]}" ;;
          esac
          i=$((i + 1))
        done
        continue
        ;;
      # unzip/7z/cpio/ar: emit all non-flag arguments (R6 fix)
      unzip|7z|cpio|ar)
        i=$((i + 1))
        while [ $i -lt ${#tokens[@]} ]; do
          case "${tokens[$i]}" in
            -*) ;;
            *) _strip_quotes "${tokens[$i]}" ;;
          esac
          i=$((i + 1))
        done
        continue
        ;;
      # scp/sftp: emit all non-flag arguments (R6 fix)
      scp|sftp)
        i=$((i + 1))
        while [ $i -lt ${#tokens[@]} ]; do
          case "${tokens[$i]}" in
            -*) ;;
            *) _strip_quotes "${tokens[$i]}" ;;
          esac
          i=$((i + 1))
        done
        continue
        ;;
      # git write subcommands: emit all non-flag arguments after the subcommand
      git)
        if [[ "$cmd" =~ git[[:space:]]+(checkout|restore|reset|stash|clean|apply|am|merge|rebase|cherry-pick) ]]; then
          i=$((i + 2))  # skip 'git' and the subcommand
          while [ $i -lt ${#tokens[@]} ]; do
            case "${tokens[$i]}" in
              -*) ;;
              *) _strip_quotes "${tokens[$i]}" ;;
            esac
            i=$((i + 1))
          done
          continue
        fi
        ;;
      # python/node/ruby: generic interpreters that could write to any file
      # Over-extract all non-flag tokens as potential targets (downstream matching filters)
      python|python3|node|ruby)
        i=$((i + 1))
        while [ $i -lt ${#tokens[@]} ]; do
          case "${tokens[$i]}" in
            -*) ;;
            *) _strip_quotes "${tokens[$i]}" ;;
          esac
          i=$((i + 1))
        done
        continue
        ;;
    esac
    i=$((i + 1))
  done

  # Also catch inline redirects like "cat x>.env" (no space before >)
  # Use a while loop to capture ALL matches, not just the first (QA-001)
  local remainder="$cmd"
  while [[ "$remainder" =~ \>{1,2}([^[:space:]\;\|]+) ]]; do
    _strip_quotes "${BASH_REMATCH[1]}"
    remainder="${remainder#*${BASH_REMATCH[0]}}"
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

# ============================================
# STEP 8: Match each file target against patterns (INV-007)
# ============================================

_check_file_against_patterns() {
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
  done <<< "$ALL_PATTERNS"

  return 1
}

# ============================================
# STEP 9: Check each file target (INV-001, INV-002, BND-004)
# ============================================

while IFS= read -r target; do
  [ -z "$target" ] && continue

  matched_pattern=""
  matched_pattern="$(_check_file_against_patterns "$target")" || true

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
