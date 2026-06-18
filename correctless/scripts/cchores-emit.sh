#!/usr/bin/env bash
# Correctless — /cchores outbound egress chokepoint (INV-013 / MA-S2).
#
# THE single coded chokepoint every outbound /cchores field MUST pass through
# before it reaches a public GitHub surface (PR title, PR body, issue comment,
# commit message, branch slug). Reads one field on STDIN, pipes it through the
# coded redactor `scripts/redact-secrets.sh`, then enforces a hard size cap, and
# emits the redacted+capped text on STDOUT.
#
# Why a wrapper and not "just call the redactor": the redactor's contract is
# redaction only. The egress contract is redaction AND a per-sink byte cap
# (INV-013: PR body <= 8192, comment <= 4096). Centralizing both in one coded
# helper means the SKILL cannot route a field around the cap or the redactor —
# there is exactly one egress path.
#
# FAIL-CLOSED (INV-013): if the redactor fails (missing pattern source, PCRE-only
# pattern, any non-zero exit), THIS script exits NON-ZERO and emits EMPTY stdout.
# It never passes a field through unredacted — a fail-OPEN egress would leak
# secrets to a public surface.
#
# Usage:
#   printf '%s' "$field" | cchores-emit.sh [--max-bytes N]
#   printf '%s' "$field" | cchores-emit.sh --sink pr-body
#   printf '%s' "$field" | cchores-emit.sh --sink comment
#
#   --max-bytes N   explicit byte cap (overrides --sink default).
#   --sink KIND     pr-body (8192) | comment (4096) | commit (4096) | title (256).
#   default cap     when neither is given: 4096 (the conservative INV-013 floor).
#
# When the redacted text exceeds the cap, it is truncated at the cap on a UTF-8
# safe boundary and an overflow notice is appended pointing at the local
# (gitignored) artifact — the truncation never re-introduces un-redacted bytes
# because truncation happens AFTER redaction.
#
# Shell discipline: fail-closed, so `set -euo pipefail`.

set -euo pipefail

# ============================================
# STEP 1: Resolve this script's location so the sibling redactor is found
#         regardless of the caller's cwd or install layout.
# ============================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REDACTOR="$SCRIPT_DIR/redact-secrets.sh"

if [ ! -f "$REDACTOR" ] || [ ! -x "$REDACTOR" ]; then
  echo "cchores-emit: redactor not found or not executable at '$REDACTOR' — failing closed" >&2
  exit 2
fi

# ============================================
# STEP 2: Parse args — --max-bytes N and/or --sink KIND.
# ============================================
MAX_BYTES=""
SINK=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --max-bytes)
      MAX_BYTES="${2:-}"
      shift 2 || { echo "cchores-emit: --max-bytes requires a value" >&2; exit 3; }
      ;;
    --max-bytes=*)
      MAX_BYTES="${1#--max-bytes=}"
      shift
      ;;
    --sink)
      SINK="${2:-}"
      shift 2 || { echo "cchores-emit: --sink requires a value" >&2; exit 3; }
      ;;
    --sink=*)
      SINK="${1#--sink=}"
      shift
      ;;
    *)
      echo "cchores-emit: unknown argument '$1'" >&2
      exit 3
      ;;
  esac
done

# Resolve the cap. Explicit --max-bytes wins; else map --sink to its INV-013
# default; else the conservative 4096 floor.
if [ -z "$MAX_BYTES" ]; then
  case "$SINK" in
    pr-body) MAX_BYTES=8192 ;;
    comment) MAX_BYTES=4096 ;;
    commit)  MAX_BYTES=4096 ;;
    title)   MAX_BYTES=256 ;;
    '')      MAX_BYTES=4096 ;;
    *)
      echo "cchores-emit: unknown --sink '$SINK' (expected pr-body|comment|commit|title)" >&2
      exit 3
      ;;
  esac
fi

# Validate the cap is a positive integer.
case "$MAX_BYTES" in
  ''|*[!0-9]*)
    echo "cchores-emit: --max-bytes must be a positive integer (got '$MAX_BYTES')" >&2
    exit 3
    ;;
esac
if [ "$MAX_BYTES" -le 0 ]; then
  echo "cchores-emit: --max-bytes must be > 0 (got '$MAX_BYTES')" >&2
  exit 3
fi

# ============================================
# STEP 3: Redact via the coded redactor. Fail closed on ANY redactor failure.
#   We capture stdout into a temp file so a redactor failure cannot leak partial
#   output to our stdout (we only emit after a clean exit 0).
# ============================================
REDACTED_FILE="$(mktemp)"
trap 'rm -f "$REDACTED_FILE"' EXIT

red_status=0
# `cat` forwards our stdin to the redactor verbatim (preserving embedded
# newlines). The redactor slurps the whole buffer (MA-S2 multiline-aware).
cat | bash "$REDACTOR" > "$REDACTED_FILE" 2>/dev/null || red_status=$?

if [ "$red_status" -ne 0 ]; then
  echo "cchores-emit: redactor exited $red_status — failing closed (no output emitted)" >&2
  exit 4
fi

# ============================================
# STEP 4: Enforce the byte cap on the REDACTED text. Truncation happens AFTER
#   redaction, so it can never re-expose a secret. If truncated, append an
#   overflow notice pointing at the (gitignored, local) artifact.
# ============================================
byte_len="$(wc -c < "$REDACTED_FILE" | tr -d ' ')"

if [ "$byte_len" -le "$MAX_BYTES" ]; then
  cat "$REDACTED_FILE"
  exit 0
fi

# Over cap: reserve room for the overflow notice so the FINAL emitted body still
# fits within MAX_BYTES.
NOTICE=$'\n\n[truncated — full content in the local (gitignored) chore artifact]'
notice_len="${#NOTICE}"
keep=$(( MAX_BYTES - notice_len ))
if [ "$keep" -lt 0 ]; then
  keep=0
fi

# `head -c` truncates on a byte boundary. A multi-byte UTF-8 char split at the
# boundary would yield an invalid tail byte; trim any trailing partial UTF-8
# continuation bytes (0x80-0xBF) with a perl pass when perl is available.
head -c "$keep" "$REDACTED_FILE" > "${REDACTED_FILE}.cap"
if command -v perl >/dev/null 2>&1; then
  perl -0777 -pe 's/[\x80-\xBF]+\z//' "${REDACTED_FILE}.cap" > "${REDACTED_FILE}.cap2" \
    && mv "${REDACTED_FILE}.cap2" "${REDACTED_FILE}.cap"
fi

cat "${REDACTED_FILE}.cap"
printf '%s' "$NOTICE"
rm -f "${REDACTED_FILE}.cap"
exit 0
