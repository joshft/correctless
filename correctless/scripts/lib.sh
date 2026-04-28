#!/usr/bin/env bash
# Correctless — Shared library functions
# Sourced by hooks and scripts that need common utilities.
#
# Security invariants for canonicalize_path are documented in
# .claude/rules/canonicalize-path.md (PAT-017, harness-fingerprint-r2-hardening
# INV-001..INV-004, INV-002a, INV-012, EA-004). Edit the rule file to update
# the contract; this comment is the in-file pointer required by ABS-009 INV-021.

# ---------------------------------------------------------------------------
# get_current_session_id — stable identifier for the current shell process
# ---------------------------------------------------------------------------
# Used by harness-fingerprint.sh and any future per-session dedup logic.
# Cross-platform: prefers `ps -o lstart=` (Linux/macOS/BSD), falls back to
# /proc/{pid}/stat (Linux), then to PID-only with a one-line warning.
#
# The output is a string that is stable WITHIN a single shell process and
# distinct between processes. It is NOT cryptographic — it's derived from
# pid + start time and used as a flag-file path component.
#
# BND-003 (harness-fingerprint spec):
#   - canonical: ps -o lstart= -p $$
#   - fallback 1: /proc/{pid}/stat field 22 (boot-relative starttime)
#   - fallback 2: PID-only + stderr warning
# Output is sanitized for filesystem safety (alnum + dash + underscore only).

get_current_session_id() {
  local pid="$$"
  local raw="" sid=""

  if command -v ps >/dev/null 2>&1; then
    raw="$(ps -o lstart= -p "$pid" 2>/dev/null | tr -s ' ' | sed 's/^ //;s/ $//')" || raw=""
  fi

  if [ -z "$raw" ] && [ -r "/proc/$pid/stat" ]; then
    # Field 22 of /proc/PID/stat is starttime (clock ticks since boot)
    raw="$(awk '{print $22}' "/proc/$pid/stat" 2>/dev/null)" || raw=""
  fi

  if [ -z "$raw" ]; then
    echo "warning: get_current_session_id falling back to PID-only (no ps, no /proc)" >&2
    sid="pid${pid}"
  else
    # Sanitize: alnum + dash + underscore only
    sid="pid${pid}_$(echo "$raw" | tr -c 'A-Za-z0-9_-' '_' | sed 's/_*$//')"
  fi

  echo "$sid"
}

# ---------------------------------------------------------------------------
# locked_update_file — generic locked read-modify-write for arbitrary file paths
# ---------------------------------------------------------------------------
# Mirrors locked_update_state but works for any file (not only state files).
# Used by harness-fingerprint.sh for the fingerprint store write
# (BND-002, ME-4 round-2 disposition).
# Usage: locked_update_file FILE_PATH JQ_FILTER [--arg key val ...]
# Behavior:
#   * Acquires lock at FILE_PATH.lock
#   * If FILE_PATH does not exist, treats input as the empty object {}
#   * Runs jq with filter, writes via temp file + atomic mv
#   * Releases lock via EXIT trap (matches locked_update_state)

locked_update_file() {
  local target_file="$1"
  local jq_filter="$2"
  shift 2
  local rc=0

  _acquire_state_lock "$target_file" || return 1
  # shellcheck disable=SC2064
  trap "$(printf '_release_state_lock %q; rm -f %q' "$target_file" "${target_file}.$$.tmp")" EXIT

  local tmp_file="${target_file}.$$.tmp"
  local jq_ok=0
  if [ -f "$target_file" ]; then
    jq "$@" "$jq_filter" "$target_file" > "$tmp_file" 2>/dev/null && jq_ok=1
  else
    # Missing file → seed jq with the empty object via -n so the filter has a
    # `.` to mutate. jq -n binds --arg/--argjson the same as the file form.
    jq -n "$@" "$jq_filter" > "$tmp_file" 2>/dev/null && jq_ok=1
  fi

  if [ "$jq_ok" = "1" ]; then
    mv "$tmp_file" "$target_file" || { rm -f "$tmp_file"; rc=1; }
  else
    rm -f "$tmp_file"
    rc=1
  fi

  _release_state_lock "$target_file"
  trap - EXIT
  return "$rc"
}

# ---------------------------------------------------------------------------
# branch_slug — filesystem-safe slug from current branch name
# ---------------------------------------------------------------------------
# Non-alphanumeric characters replaced by hyphens, truncated to 80 chars,
# appended with 6-char hash to avoid collisions.
# (feature/foo-bar and feature/foo_bar produce different hashes)

branch_slug() {
  local branch
  if [ -n "${1:-}" ]; then
    branch="$1"
  else
    branch="$(git branch --show-current 2>/dev/null)" || { echo "error: not in a git repository" >&2; return 1; }
    [ -n "$branch" ] || { echo "error: detached HEAD" >&2; return 1; }
  fi
  local slug raw_hash
  slug="${branch//[^a-zA-Z0-9]/-}"
  slug="${slug:0:80}"
  raw_hash="$(printf '%s' "$branch" | (md5sum 2>/dev/null || md5))"
  echo "${slug}-${raw_hash:0:6}"
}

# ---------------------------------------------------------------------------
# repo_root — absolute path to the git repository root (cached)
# ---------------------------------------------------------------------------

repo_root() {
  if [ -z "${_CORRECTLESS_REPO_ROOT:-}" ]; then
    _CORRECTLESS_REPO_ROOT="$(git --no-optional-locks rev-parse --show-toplevel 2>/dev/null || pwd)"
  fi
  echo "$_CORRECTLESS_REPO_ROOT"
}

# ---------------------------------------------------------------------------
# config_file — absolute path to workflow-config.json (cached)
# ---------------------------------------------------------------------------

config_file() {
  if [ -z "${_CORRECTLESS_CONFIG_FILE:-}" ]; then
    _CORRECTLESS_CONFIG_FILE="$(repo_root)/.correctless/config/workflow-config.json"
  fi
  echo "$_CORRECTLESS_CONFIG_FILE"
}

# ---------------------------------------------------------------------------
# artifacts_dir — absolute path to artifacts directory (cached)
# ---------------------------------------------------------------------------

artifacts_dir() {
  if [ -z "${_CORRECTLESS_ARTIFACTS_DIR:-}" ]; then
    _CORRECTLESS_ARTIFACTS_DIR="$(repo_root)/.correctless/artifacts"
  fi
  echo "$_CORRECTLESS_ARTIFACTS_DIR"
}

# ---------------------------------------------------------------------------
# classify_file — classify a relative path as test, source, or other
# ---------------------------------------------------------------------------
# Used by: workflow-gate.sh, audit-trail.sh
# Requires TEST_PATTERN and SOURCE_PATTERN globals to be set by the caller.
# Patterns are pipe-delimited globs (e.g., "*.test.ts|*.spec.ts|tests/*.rs").
# Patterns with "/" match against the full relative path; without "/" match basename only.

# shellcheck disable=SC2254  # Unquoted $pat in case is intentional — we need glob matching
classify_file() {
  local file="$1" bname
  # Normalize case — patterns are lowercase, filenames may not be (bash 4+ builtin)
  file="${file,,}"
  bname="${file##*/}"

  if [ -n "$TEST_PATTERN" ]; then
    local oldifs="$IFS"; IFS='|'
    for pat in $TEST_PATTERN; do
      IFS="$oldifs"
      case "$pat" in
        */*) case "$file" in $pat) echo "test"; return ;; esac ;;
        *)   case "$bname" in $pat) echo "test"; return ;; esac ;;
      esac
    done
    IFS="$oldifs"
  fi

  if [ -n "$SOURCE_PATTERN" ]; then
    local oldifs="$IFS"; IFS='|'
    for pat in $SOURCE_PATTERN; do
      IFS="$oldifs"
      case "$pat" in
        */*) case "$file" in $pat) echo "source"; return ;; esac ;;
        *)   case "$bname" in $pat) echo "source"; return ;; esac ;;
      esac
    done
    IFS="$oldifs"
  fi

  echo "other"
}

# ---------------------------------------------------------------------------
# read_patterns — set TEST_PATTERN and SOURCE_PATTERN from config
# ---------------------------------------------------------------------------
# Pre-positioned for Phase 2 hook decomposition. Not yet called by hooks
# (they use bulk jq calls for performance); available for future sub-handlers.
# Reads .patterns.test_file and .patterns.source_file from workflow-config.json.
# Sets them as globals for use with classify_file().

read_patterns() {
  local cf="${1:-$(config_file 2>/dev/null)}"
  [ -f "$cf" ] || return 1
  eval "$(jq -r '
    @sh "TEST_PATTERN=\(.patterns.test_file // "")",
    @sh "SOURCE_PATTERN=\(.patterns.source_file // "")"
  ' "$cf" 2>/dev/null)" || return 1
}

# ---------------------------------------------------------------------------
# read_intensity — output the project workflow intensity
# ---------------------------------------------------------------------------
# Pre-positioned for Phase 2 hook decomposition (see read_patterns note).
# Returns "standard", "high", or "critical". Defaults to "standard".

read_intensity() {
  local cf="${1:-$(config_file 2>/dev/null)}"
  [ -f "$cf" ] || { echo "standard"; return; }
  local val
  val="$(jq -r '.workflow.intensity // "standard"' "$cf" 2>/dev/null)" || val="standard"
  echo "$val"
}

# ---------------------------------------------------------------------------
# State file locking — atomic mkdir + PID-based stale detection
# ---------------------------------------------------------------------------
# Uses mkdir for portability (no flock dependency — works on macOS).
# Lock directory: ${state_file}.lock with a pid file inside.

# _acquire_state_lock — acquire a lock for the given state file
_acquire_state_lock() {
  local state_file="$1"
  [ -n "$state_file" ] || { echo "ERROR: _acquire_state_lock called with empty path" >&2; return 1; }
  local lock_dir="${state_file}.lock"
  local timeout="${CORRECTLESS_LOCK_TIMEOUT:-5}"
  [[ "$timeout" =~ ^[0-9]+$ ]] || timeout=5
  local deadline=$((SECONDS + timeout))

  while true; do
    if mkdir "$lock_dir" 2>/dev/null; then
      echo "$$" > "$lock_dir/pid" || { rm -rf "$lock_dir"; return 1; }
      return 0
    fi

    # Lock exists — check if holder is alive
    if [ -f "$lock_dir/pid" ]; then
      local holder_pid
      holder_pid="$(cat "$lock_dir/pid" 2>/dev/null)" || holder_pid=""
      if [ -n "$holder_pid" ] && ! kill -0 "$holder_pid" 2>/dev/null; then
        # Holder is dead — atomically claim stale lock via mv.
        # Only one process's mv succeeds; losers retry from the top.
        local break_dir="${lock_dir}.breaking.$$"
        if mv "$lock_dir" "$break_dir" 2>/dev/null; then
          rm -rf "$break_dir"
        fi
        continue
      fi
    elif [ -d "$lock_dir" ]; then
      # QA-R1-018: No pid file — lock was interrupted between mkdir and pid write.
      # Treat as stale and break it to prevent 5s timeout deadlock.
      local break_dir="${lock_dir}.breaking.$$"
      if mv "$lock_dir" "$break_dir" 2>/dev/null; then
        rm -rf "$break_dir"
      fi
      continue
    fi

    # Holder is alive or PID unknown — wait and retry
    if [ "$SECONDS" -ge "$deadline" ]; then
      echo "ERROR: Lock acquisition timeout after ${timeout}s for $state_file" >&2
      return 1
    fi
    sleep 0.1
  done
}

# _release_state_lock — release the lock for the given state file
_release_state_lock() {
  local state_file="$1"
  local lock_dir="${state_file}.lock"
  # Only release if we are the holder — prevents EXIT trap from deleting another process's lock
  if [ -f "$lock_dir/pid" ] && [ "$(cat "$lock_dir/pid" 2>/dev/null)" = "$$" ]; then
    rm -rf "$lock_dir"
  fi
}

# locked_update_state — read-modify-write a state file under lock
# Usage: locked_update_state STATE_FILE JQ_FILTER [--arg key val ...]
# QA-R3-001: Extra arguments after the filter are passed through to jq,
# enabling safe parameterization via --arg instead of string interpolation.
locked_update_state() {
  local state_file="$1"
  local jq_filter="$2"
  shift 2
  local rc=0

  _acquire_state_lock "$state_file" || return 1
  # QA-R1-013: EXIT trap ensures lock is released on abnormal termination
  # (e.g., hook runner kills the process at timeout between acquire and release)
  # shellcheck disable=SC2064
  trap "$(printf '_release_state_lock %q; rm -f %q' "$state_file" "${state_file}.$$.tmp")" EXIT

  local tmp_file="${state_file}.$$.tmp"
  # Extra args (e.g., --arg key val) must come BEFORE the filter for older jq (1.6)
  if jq "$@" "$jq_filter" "$state_file" > "$tmp_file" 2>/dev/null; then
    mv "$tmp_file" "$state_file" || { rm -f "$tmp_file"; rc=1; }
  else
    rm -f "$tmp_file"
    rc=1
  fi

  _release_state_lock "$state_file"
  trap - EXIT
  return "$rc"
}

# ---------------------------------------------------------------------------
# canonicalize_path — pure-bash path normalizer (segment-stack walker)
# ---------------------------------------------------------------------------
# Total over arbitrary byte sequences. No external commands; no fork/exec.
# Operates on bytes (LC_ALL=C). Glob characters and shell sigils pass through
# as literal bytes — never expanded. See .claude/rules/canonicalize-path.md.
#
# Contract:
#   * Empty / whitespace-only input → "."
#   * Non-empty input → non-empty single-line output (INV-001a)
#   * No `//`, no `.` segments, no `..` on absolute output, no trailing `/`
#     (except when the entire output is exactly `/`)
#   * Idempotent: canonicalize_path(canonicalize_path(x)) == canonicalize_path(x)
#   * Only ASCII 0x2E (`.`) is treated as a path-segment dot — Unicode
#     lookalikes pass through as ordinary bytes (INV-002a, EA-004)
#   * Newlines in input are normalized to `_` in output to satisfy the
#     single-line contract — paths with literal `\n` cannot legitimately
#     reach the matcher and any false positive is fail-safe.

canonicalize_path() {
  local LC_ALL=C
  local input="$1"

  if [ -z "$input" ]; then
    printf '%s\n' "."
    return 0
  fi

  # Whitespace-only input → "." (preserves non-empty-output contract)
  case "$input" in
    *[!$' \t\n']*) ;;
    *) printf '%s\n' "."; return 0 ;;
  esac

  # Absolute path?
  local absolute=0
  if [ "${input:0:1}" = "/" ]; then
    absolute=1
  fi

  # Save and disable globbing for the field-split. Glob expansion against the
  # cwd would let a hostile path like `*` smuggle filenames into the matcher.
  local f_was_set=1
  case $- in *f*) ;; *) f_was_set=0 ;; esac
  set -f

  local IFS_save="${IFS-}"
  local IFS='/'
  # shellcheck disable=SC2206
  local -a segs=( $input )
  IFS="$IFS_save"

  [ "$f_was_set" = 1 ] || set +f

  # Process segments through stack. Track top index instead of repacking the
  # array on every pop — avoids the O(n²) cost on paths with many `..`.
  local -a stack=()
  local top_idx=-1 seg
  for seg in "${segs[@]}"; do
    case "$seg" in
      ""|".")
        continue
        ;;
      "..")
        if [ "$top_idx" -ge 0 ]; then
          if [ "${stack[$top_idx]}" = ".." ]; then
            top_idx=$((top_idx + 1))
            stack[$top_idx]=".."
          else
            top_idx=$((top_idx - 1))
          fi
        elif [ "$absolute" = 0 ]; then
          top_idx=0
          stack[0]=".."
        fi
        ;;
      *)
        top_idx=$((top_idx + 1))
        stack[$top_idx]="$seg"
        ;;
    esac
  done

  if [ "$top_idx" -lt 0 ]; then
    [ "$absolute" = 1 ] && printf '%s\n' "/" || printf '%s\n' "."
    return 0
  fi

  # Pure-bash join via IFS expansion of "${arr[*]}".
  local out IFS_save2="${IFS-}"
  IFS='/'
  out="${stack[*]:0:top_idx+1}"
  IFS="$IFS_save2"
  [ "$absolute" = 1 ] && out="/$out"

  # Single-line contract (INV-001): newlines in input bytes become `_`.
  out="${out//$'\n'/_}"

  printf '%s\n' "$out"
}

# ---------------------------------------------------------------------------
# _has_write_pattern — detect write/destructive shell command patterns
# ---------------------------------------------------------------------------
# Returns 0 if the command contains a write pattern, 1 otherwise.
# Union of: redirect operators, write-command tokens (cp/mv/rm/tee/...),
# sed -i / perl -i, and interpreter+eval-flag chains (INV-013).

_has_write_pattern() {
  local cmd="$1"
  [[ "$cmd" =~ \>\>|[0-9]*\>[^\&] ]] && return 0

  # Single token scan — glob-disabled to keep `*.foo` literal — looking for
  # writers, sed -i / perl -i shapes, or interpreter+eval-flag chains.
  local f_was_set=1
  case $- in *f*) ;; *) f_was_set=0 ;; esac
  set -f
  # shellcheck disable=SC2141
  local IFS=$' \t\n;|&()`'
  local tok base has_interp=0 has_evalflag=0 rc=1
  for tok in $cmd; do
    case "$tok" in
      cp|mv|tee|install|rm|rmdir|unlink|dd|curl|wget|rsync|patch|truncate|shred|ln) rc=0; break ;;
      tar|unzip|7z|cpio|ar|touch|chmod|chown|chgrp|scp|sftp|mkdir) rc=0; break ;;
      ed|vim|vi|nvim|ex|view|nano|emacs) rc=0; break ;;
      python|python3|node|ruby) rc=0; break ;;
      git) [[ "$cmd" =~ git[[:space:]]+(checkout|restore|reset|stash|clean|apply|am|merge|rebase|cherry-pick) ]] && { rc=0; break; } ;;
      sed) [[ "$cmd" =~ sed[[:space:]]+-i ]] && { rc=0; break; } ;;
      perl) [[ "$cmd" =~ perl[[:space:]]+-i ]] && { rc=0; break; } ;;
    esac
    # Interpreter+evalflag detection (INV-013) — basename match strips
    # `/usr/bin/env perl` style paths down to their executable name.
    base="${tok##*/}"
    case "$base" in
      bash|sh|zsh|dash|perl|python|python3|ruby|php|lua|tclsh|Rscript|nim|node) has_interp=1 ;;
    esac
    case "$tok" in
      -c|-e|-r|-E|-pe|-ne|-pi|-ni|-lpi|--execute) has_evalflag=1 ;;
    esac
    if [ "$has_interp" = 1 ] && [ "$has_evalflag" = 1 ]; then
      rc=0; break
    fi
  done
  [ "$f_was_set" = 1 ] || set +f
  return "$rc"
}

# ---------------------------------------------------------------------------
# get_target_file — extract file paths with known extensions from a command
# ---------------------------------------------------------------------------
# Wraps the grep -oE call with the 25-extension regex pattern.
# Usage: FILES="$(get_target_file "$COMMAND")"

get_target_file() {
  local cmd="$1"
  echo "$cmd" | sed "s/['\"]//g" | tr ' \t' '\n\n' | grep -E '\.(go|ts|tsx|js|jsx|py|rs|java|rb|cpp|c|h|sh|json|md|yaml|yml|toml|cfg|ini|sql|css|html|vue|svelte)$'
}

# ---------------------------------------------------------------------------
# sha256_hash_file — compute SHA-256 hash of a file (cross-platform)
# ---------------------------------------------------------------------------
# Tries sha256sum, shasum -a 256, openssl dgst -sha256 in order.
# Usage: sha256_hash_file FILE_PATH
# Outputs the hex hash to stdout. Returns 1 if no tool available.

sha256_hash_file() {
  local file="$1"

  [ -f "$file" ] || return 1

  local hash=""

  if command -v sha256sum >/dev/null 2>&1; then
    hash="$(sha256sum "$file" 2>/dev/null | cut -d' ' -f1)"
  elif command -v shasum >/dev/null 2>&1; then
    hash="$(shasum -a 256 "$file" 2>/dev/null | cut -d' ' -f1)"
  elif command -v openssl >/dev/null 2>&1; then
    hash="$(openssl dgst -sha256 "$file" 2>/dev/null | sed 's/^.*= //')"
  fi

  if [ -n "$hash" ]; then
    echo "$hash"
    return 0
  fi

  return 1
}

# ---------------------------------------------------------------------------
# check_install_freshness — detect stale hooks by comparing installed files
#   against the install manifest and source files
# ---------------------------------------------------------------------------
# Usage: check_install_freshness CORRECTLESS_DIR
# CORRECTLESS_DIR is the absolute path to the .correctless/ directory.
# Reads .install-manifest.json from that directory.
# Outputs one line per file as status:relative/path to stdout.
# Statuses: ok, modified, missing, source_ahead, new_file, no_manifest

check_install_freshness() {
  local correctless_dir="$1"
  local manifest="$correctless_dir/.install-manifest.json"

  # No manifest — single-line output
  if [ ! -f "$manifest" ]; then
    echo "no_manifest"
    return 0
  fi

  # Bulk-parse manifest in a single jq call: source_dir + all file entries
  local manifest_data
  manifest_data="$(jq -r '
    (.source_dir // ""),
    (.files | to_entries[] | "\(.key)\t\(.value.installed_hash)\t\(.value.source_hash)")
  ' "$manifest" 2>/dev/null)" || { echo "no_manifest"; return 0; }

  # First line is source_dir, remaining lines are file entries
  local source_dir
  source_dir="$(echo "$manifest_data" | head -1)"
  local file_entries
  file_entries="$(echo "$manifest_data" | tail -n +2)"

  local source_dir_valid=false
  [ -n "$source_dir" ] && [ -d "$source_dir" ] && source_dir_valid=true

  # Track manifest files for new_file detection
  local -A manifest_files=()

  # Check each file
  while IFS=$'\t' read -r rel_path installed_hash_manifest source_hash_manifest; do
    [ -n "$rel_path" ] || continue
    manifest_files["$rel_path"]=1

    local installed_file="$correctless_dir/$rel_path"

    if [ ! -f "$installed_file" ]; then
      echo "missing:$rel_path"
      continue
    fi

    local current_installed_hash
    current_installed_hash="$(sha256_hash_file "$installed_file" 2>/dev/null)" || current_installed_hash=""

    if [ "$current_installed_hash" != "$installed_hash_manifest" ]; then
      echo "modified:$rel_path"
      continue
    fi

    # Source-ahead check (only if source_dir is accessible)
    if [ "$source_dir_valid" = true ]; then
      local source_file="$source_dir/$rel_path"
      if [ -f "$source_file" ]; then
        local current_source_hash
        current_source_hash="$(sha256_hash_file "$source_file" 2>/dev/null)" || current_source_hash=""
        if [ "$current_source_hash" != "$source_hash_manifest" ]; then
          echo "source_ahead:$rel_path"
          continue
        fi
      fi
    fi

    echo "ok:$rel_path"
  done <<< "$file_entries"

  # Scan for new files not in manifest
  for dir_prefix in hooks scripts; do
    local scan_dir="$correctless_dir/$dir_prefix"
    [ -d "$scan_dir" ] || continue
    for file in "$scan_dir"/*.sh; do
      [ -f "$file" ] || continue
      local rel
      rel="$dir_prefix/$(basename "$file")"
      [ -z "${manifest_files[$rel]+x}" ] && echo "new_file:$rel"
    done
  done
}
