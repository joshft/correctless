#!/usr/bin/env bash
# ============================================
# extract-entrypoints.sh — Extract entrypoints YAML from ARCHITECTURE.md
# ============================================
#
# Reads between the correctless:entrypoints:start and
# correctless:entrypoints:end marker comments, strips the code fence,
# and validates the result is parseable YAML.
#
# Fallback chain for YAML validation:
#   yq → python3 with PyYAML → exit 1
#
# The script does NOT validate enum membership or field semantics —
# that is the writer's responsibility (R-004 in the carchitect spec).
# Extraction is dumb and fast; validation is at write time.
#
# Usage: bash scripts/extract-entrypoints.sh [path-to-architecture.md]
# Default path: .correctless/ARCHITECTURE.md
#
# Exit 0: success (valid YAML on stdout)
# Exit 1: markers not found, YAML invalid, or no parser available

set -euo pipefail

# ============================================
# STEP 1: Determine input file
# ============================================

ARCH_FILE="${1:-.correctless/ARCHITECTURE.md}"

# ============================================
# STEP 2: Extract content between markers
# ============================================

START_MARKER="correctless:entrypoints:start"
END_MARKER="correctless:entrypoints:end"

# sed will fail naturally if the file doesn't exist (set -e catches it).
# Marker checks provide specific error messages rather than opaque sed output.
if ! grep -q "$START_MARKER" "$ARCH_FILE" 2>/dev/null; then
  echo "Error: Start marker '$START_MARKER' not found in ${ARCH_FILE}" >&2
  exit 1
fi

if ! grep -q "$END_MARKER" "$ARCH_FILE"; then
  echo "Error: End marker '$END_MARKER' not found in $ARCH_FILE" >&2
  exit 1
fi

_extracted=$(sed -n "/$START_MARKER/,/$END_MARKER/p" "$ARCH_FILE" \
  | grep -v "$START_MARKER" \
  | grep -v "$END_MARKER" \
  | grep -v '^[[:space:]]*```')

if [ -z "$_extracted" ]; then
  echo "Error: No content between entrypoints markers" >&2
  exit 1
fi

# ============================================
# STEP 3: Validate YAML via fallback chain
# ============================================

_validate_yaml() {
  local yaml_content="$1"

  # Try yq first
  if command -v yq >/dev/null 2>&1; then
    if echo "$yaml_content" | yq '.' >/dev/null 2>&1; then
      return 0
    else
      echo "Error: YAML validation failed (yq)" >&2
      return 1
    fi
  fi

  # Try python3 with PyYAML
  if command -v python3 >/dev/null 2>&1; then
    if echo "$yaml_content" | python3 -c 'import yaml; yaml.safe_load(open("/dev/stdin").read())' 2>/dev/null; then
      return 0
    else
      echo "Error: YAML validation failed (python3 + PyYAML)" >&2
      return 1
    fi
  fi

  # Neither available
  echo "Error: Neither yq nor python3 with PyYAML available." >&2
  return 1
}

if ! _validate_yaml "$_extracted"; then
  exit 1
fi

# ============================================
# STEP 4: Output valid YAML to stdout
# ============================================

printf '%s\n' "$_extracted"
