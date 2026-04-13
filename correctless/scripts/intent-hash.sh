#!/usr/bin/env bash
# Correctless — Intent summary management with hash enforcement
# Creates, verifies, and hashes the immutable intent summary.

# No set -euo pipefail — this file is sourced by other scripts

# Source lib.sh for shared utilities (sha256_hash_file).
# Source at top level (not inside functions) to avoid RETURN trap interaction.
_INTENT_HASH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)"
if [ -n "$_INTENT_HASH_DIR" ] && [ -f "$_INTENT_HASH_DIR/lib.sh" ]; then
  # shellcheck source=lib.sh
  source "$_INTENT_HASH_DIR/lib.sh"
fi
unset _INTENT_HASH_DIR

# ---------------------------------------------------------------------------
# intent_hash — compute SHA-256 hash of intent file
# ---------------------------------------------------------------------------
# Usage: intent_hash INTENT_FILE
# Delegates to sha256_hash_file in lib.sh for the cross-platform fallback chain.
intent_hash() {
  sha256_hash_file "$1"
}

# ---------------------------------------------------------------------------
# intent_create — write intent summary file and return its hash
# ---------------------------------------------------------------------------
# Usage: intent_create INTENT_FILE CONTENT
# Returns: SHA-256 hash of the created file on stdout (INV-013).
intent_create() {
  local intent_file="$1"
  local content="$2"

  # Write content to file
  mkdir -p "$(dirname "$intent_file")"
  echo "$content" > "$intent_file" || return 1

  # Compute and return hash
  intent_hash "$intent_file"
}

# ---------------------------------------------------------------------------
# intent_verify — verify intent file matches stored hash
# ---------------------------------------------------------------------------
# Usage: intent_verify INTENT_FILE STORED_HASH
# Returns: 0 if match, 1 if mismatch (triggers hard stop per INV-013)
intent_verify() {
  local intent_file="$1"
  local stored_hash="$2"

  [ -f "$intent_file" ] || return 1

  local current_hash
  current_hash="$(intent_hash "$intent_file")" || return 1

  if [ "$current_hash" = "$stored_hash" ]; then
    return 0
  else
    echo "ERROR: Intent summary tampered — hash mismatch" >&2
    return 1
  fi
}
