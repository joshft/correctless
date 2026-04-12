#!/usr/bin/env bash
# Correctless — Intent summary management with hash enforcement
# Creates, verifies, and hashes the immutable intent summary.

# No set -euo pipefail — this file is sourced by other scripts

# ---------------------------------------------------------------------------
# intent_hash — compute SHA-256 hash of intent file
# ---------------------------------------------------------------------------
# Usage: intent_hash INTENT_FILE
# Tries sha256sum, shasum -a 256, openssl dgst -sha256 in order (EA-004).
intent_hash() {
  local intent_file="$1"

  [ -f "$intent_file" ] || return 1

  local hash=""

  if command -v sha256sum >/dev/null 2>&1; then
    hash="$(sha256sum "$intent_file" 2>/dev/null | cut -d' ' -f1)"
  elif command -v shasum >/dev/null 2>&1; then
    hash="$(shasum -a 256 "$intent_file" 2>/dev/null | cut -d' ' -f1)"
  elif command -v openssl >/dev/null 2>&1; then
    hash="$(openssl dgst -sha256 "$intent_file" 2>/dev/null | sed 's/^.*= //')"
  fi

  if [ -n "$hash" ]; then
    echo "$hash"
    return 0
  fi

  return 1
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
