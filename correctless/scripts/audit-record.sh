#!/usr/bin/env bash
# Correctless — Audit findings persistence script (PAT-003 / ABS-029)
# Sole writer for .correctless/artifacts/findings/audit-{preset}-{date}-round-{N}.json
# and audit-{preset}-history.md.
#
# Spec: .correctless/specs/audit-findings-persistence-contract.md
#   INV-002, INV-002a, INV-006, INV-007, PRH-001, PRH-003, PRH-004
#
# Subcommands:
#   write-round <preset> <round> <findings-file>|-
#   append-history <preset> <summary-file>|-

set -euo pipefail

# Source lib.sh for branch_slug() — needed to find the workflow state file
# whose started_at populates the round-JSON. lib.sh is the canonical source
# of branch_slug (PAT-006); we never reimplement it.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/lib.sh" ]; then
  # shellcheck source=lib.sh
  source "$SCRIPT_DIR/lib.sh"
elif [ -f ".correctless/scripts/lib.sh" ]; then
  # shellcheck disable=SC1091
  source ".correctless/scripts/lib.sh"
fi

# Locate the workflow state file via branch_slug. The path is derived from
# the current cwd's git branch — does NOT influence destination path
# construction (PRH-003 — the destination uses CLI args + state.started_at,
# not the state file's path).
#
# MA-001: NO mtime-based fallback. Picking the most recently modified state
# file across branches would let the writer attribute one branch's audit to
# another branch's started_at — exactly the cross-branch contamination the
# gate's content match exists to prevent. If branch_slug is unavailable or
# no matching state file exists, fail loudly.
_state_file() {
  local slug=""
  if command -v branch_slug >/dev/null 2>&1; then
    slug="$(branch_slug 2>/dev/null)" || slug=""
  fi
  if [ -z "$slug" ]; then
    return 1
  fi
  local sf=".correctless/artifacts/workflow-state-${slug}.json"
  if [ ! -f "$sf" ]; then
    return 1
  fi
  echo "$sf"
}

# INV-002: validate inputs against canonical patterns.
_validate_preset() {
  local preset="$1"
  case "$preset" in
    [a-z]*)  ;;
    *) return 1 ;;
  esac
  # Length 1-32, lowercase alphanumeric + hyphen
  case "$preset" in
    *[!a-z0-9-]*) return 1 ;;
  esac
  [ "${#preset}" -le 32 ] || return 1
  return 0
}

_validate_round() {
  local round="$1"
  case "$round" in
    ''|*[!0-9]*) return 1 ;;
  esac
  [ "$round" -ge 1 ] || return 1
  return 0
}

_validate_started_at() {
  # Canonical UTC form: YYYY-MM-DDTHH:MM:SSZ
  local ts="$1"
  case "$ts" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z) return 0 ;;
    *) return 1 ;;
  esac
}

write_round() {
  local preset="${1:-}" round="${2:-}" source="${3:-}"

  if [ -z "$preset" ] || [ -z "$round" ] || [ -z "$source" ]; then
    echo "audit-record.sh write-round: usage: write-round <preset> <round> <file>|-" >&2
    return 2
  fi
  _validate_preset "$preset" || { echo "audit-record.sh write-round: invalid preset '$preset' (must match ^[a-z][a-z0-9-]{0,31}$)" >&2; return 2; }
  _validate_round "$round" || { echo "audit-record.sh write-round: invalid round '$round' (must be positive integer)" >&2; return 2; }

  # Read findings input. QA-R3-007: TTY guard fires for any source that
  # ultimately reads stdin — `-`, `/dev/stdin`, `/proc/self/fd/0`, or
  # equivalent — not just `-`. Any aliased stdin source bypasses the guard
  # otherwise and the script blocks indefinitely on interactive use.
  local payload reads_stdin=0
  case "$source" in
    -|/dev/stdin|/proc/self/fd/0|/dev/fd/0) reads_stdin=1 ;;
  esac
  if [ "$reads_stdin" = 1 ]; then
    if [ -t 0 ]; then
      echo "audit-record.sh write-round: stdin must be piped; refusing to read from TTY" >&2
      return 2
    fi
    payload="$(cat)"
  elif [ -f "$source" ]; then
    payload="$(cat "$source")"
  else
    echo "audit-record.sh write-round: input file not found: $source" >&2
    return 2
  fi

  # Validate it's JSON with required findings field
  if ! echo "$payload" | jq -e . >/dev/null 2>&1; then
    echo "audit-record.sh write-round: JSON parse error on input" >&2
    return 2
  fi
  if ! echo "$payload" | jq -e 'has("findings") and (.findings | type) == "array"' >/dev/null 2>&1; then
    echo "audit-record.sh write-round: input missing required 'findings' array" >&2
    return 2
  fi
  # Spec INV-002a: rejected: [] is also required for the clean-marker form.
  # For non-clean rounds the spec is silent on rejected being optional, but
  # we synthesize an empty array if absent to keep the schema uniform.
  payload=$(echo "$payload" | jq 'if has("rejected") then . else . + {rejected: []} end')

  # Read started_at + date from workflow state
  local sf started_at date
  sf="$(_state_file)" || { echo "audit-record.sh write-round: cannot find workflow state file" >&2; return 2; }
  if [ ! -f "$sf" ]; then
    echo "audit-record.sh write-round: workflow state file not found: $sf" >&2
    return 2
  fi
  started_at=$(jq -r '.started_at // empty' "$sf")
  if [ -z "$started_at" ]; then
    echo "audit-record.sh write-round: workflow state has no .started_at" >&2
    return 2
  fi
  _validate_started_at "$started_at" || {
    echo "audit-record.sh write-round: state.started_at '$started_at' is not canonical UTC YYYY-MM-DDTHH:MM:SSZ" >&2
    return 2
  }
  date="${started_at%%T*}"
  case "$date" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
    *) echo "audit-record.sh write-round: derived date '$date' is malformed" >&2; return 2 ;;
  esac

  # Construct destination — PRH-003: only CLI args + hardcoded base + state.started_at-derived date
  local dst_dir=".correctless/artifacts/findings"
  local dst="${dst_dir}/audit-${preset}-${date}-round-${round}.json"
  mkdir -p "$dst_dir" || return 2

  # Merge with required fields
  local merged
  merged=$(echo "$payload" | jq \
    --arg preset "$preset" \
    --arg date "$date" \
    --arg started_at "$started_at" \
    --argjson round "$round" \
    '. + {preset: $preset, date: $date, round: $round, started_at: $started_at}')
  if [ -z "$merged" ]; then
    echo "audit-record.sh write-round: jq merge failed" >&2
    return 2
  fi

  # Write atomically via tmp + mv. QA-R4-005: trap cleans up the tmp file
  # if the script is killed between printf and mv.
  local tmp="${dst}.$$.tmp"
  # shellcheck disable=SC2064
  trap "rm -f '$tmp'" EXIT INT TERM HUP
  printf '%s\n' "$merged" > "$tmp" || { echo "audit-record.sh write-round: write failed" >&2; rm -f "$tmp"; trap - EXIT INT TERM HUP; return 2; }
  mv "$tmp" "$dst" || { echo "audit-record.sh write-round: atomic rename failed" >&2; rm -f "$tmp"; trap - EXIT INT TERM HUP; return 2; }
  trap - EXIT INT TERM HUP

  # Stdout: single-line absolute path.
  # QA-R3-003: $(pwd) reflects runtime state and could (rarely) contain a
  # newline; INV-007's single-line guarantee requires explicit stripping.
  local abs_dir abs_path
  abs_dir=$( cd "$(dirname "$dst")" && pwd | tr -d '\n' )
  abs_path="${abs_dir}/$(basename "$dst")"
  printf '%s\n' "$abs_path"
  return 0
}

append_history() {
  local preset="${1:-}" source="${2:-}"
  if [ -z "$preset" ] || [ -z "$source" ]; then
    echo "audit-record.sh append-history: usage: append-history <preset> <file>|-" >&2
    return 2
  fi
  _validate_preset "$preset" || { echo "audit-record.sh append-history: invalid preset '$preset'" >&2; return 2; }

  # QA-R3-007: TTY guard covers stdin aliases, not just literal `-`.
  local payload reads_stdin=0
  case "$source" in
    -|/dev/stdin|/proc/self/fd/0|/dev/fd/0) reads_stdin=1 ;;
  esac
  if [ "$reads_stdin" = 1 ]; then
    if [ -t 0 ]; then
      echo "audit-record.sh append-history: stdin must be piped; refusing to read from TTY" >&2
      return 2
    fi
    payload="$(cat)"
  elif [ -f "$source" ]; then
    payload="$(cat "$source")"
  else
    echo "audit-record.sh append-history: input file not found: $source" >&2
    return 2
  fi

  local dst_dir=".correctless/artifacts/findings"
  local dst="${dst_dir}/audit-${preset}-history.md"
  mkdir -p "$dst_dir" || return 2

  # Append-only with flock; fail-open on lock timeout (history is advisory).
  local lock="${dst}.lock"
  if command -v flock >/dev/null 2>&1; then
    {
      if flock -w 5 -x 200; then
        printf '%s\n' "$payload" >> "$dst"
      else
        echo "audit-record.sh append-history: flock timeout on $dst — history append skipped" >&2
        return 0
      fi
    } 200>"$lock" || true
  else
    printf '%s\n' "$payload" >> "$dst"
  fi
  return 0
}

case "${1:-}" in
  write-round)    shift; write_round "$@" ;;
  append-history) shift; append_history "$@" ;;
  -h|--help|help|"")
    echo "Usage: audit-record.sh {write-round|append-history} ..."
    echo "  write-round <preset> <round> <file>|-"
    echo "  append-history <preset> <file>|-"
    exit 0
    ;;
  *)
    echo "audit-record.sh: unknown subcommand '$1'" >&2
    exit 2
    ;;
esac
