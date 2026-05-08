#!/usr/bin/env bash
# Correctless — Autonomous decision JSONL writer (ABS-030)
# Sole writer for .correctless/artifacts/autonomous-decisions-{branch_slug}.jsonl
#
# Spec: .correctless/specs/autonomous-skill-contract.md
#   R-006 (sole-writer contract), ABS-030
#
# Subcommands:
#   append <skill-name> <json-line>   Append one decision entry
#   read                              Read all entries (stdout)
#   path                              Print JSONL path (stdout)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/lib.sh" ]; then
  # shellcheck source=lib.sh
  source "$SCRIPT_DIR/lib.sh"
elif [ -f ".correctless/scripts/lib.sh" ]; then
  # shellcheck disable=SC1091
  source ".correctless/scripts/lib.sh"
fi

_jsonl_path() {
  local slug=""
  if command -v branch_slug >/dev/null 2>&1; then
    slug="$(branch_slug 2>/dev/null)" || slug=""
  fi
  if [ -z "$slug" ]; then
    echo "autonomous-decision-writer.sh: cannot derive branch_slug" >&2
    return 2
  fi
  echo ".correctless/artifacts/autonomous-decisions-${slug}.jsonl"
}

cmd_append() {
  local skill="${1:-}" json_line="${2:-}"
  if [ -z "$skill" ] || [ -z "$json_line" ]; then
    echo "autonomous-decision-writer.sh append: usage: append <skill-name> <json-line>" >&2
    return 2
  fi

  if ! echo "$json_line" | jq -e . >/dev/null 2>&1; then
    echo "autonomous-decision-writer.sh append: invalid JSON" >&2
    return 2
  fi

  local dst
  dst="$(_jsonl_path)" || return 2
  local dst_dir
  dst_dir="$(dirname "$dst")"
  mkdir -p "$dst_dir" || return 2

  local merged
  merged=$(echo "$json_line" | jq -c --arg skill "$skill" '. + {skill: $skill}')
  printf '%s\n' "$merged" >> "$dst"
  return 0
}

cmd_read() {
  local dst
  dst="$(_jsonl_path)" || return 2
  if [ -f "$dst" ]; then
    cat "$dst"
  fi
  return 0
}

cmd_path() {
  _jsonl_path
}

case "${1:-}" in
  append)       shift; cmd_append "$@" ;;
  read)         cmd_read ;;
  path)         cmd_path ;;
  -h|--help|help|"")
    echo "Usage: autonomous-decision-writer.sh {append|read|path} ..."
    echo "  append <skill-name> <json-line>"
    echo "  read"
    echo "  path"
    exit 0
    ;;
  *)
    echo "autonomous-decision-writer.sh: unknown subcommand '$1'" >&2
    exit 2
    ;;
esac
