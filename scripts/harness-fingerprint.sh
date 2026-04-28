#!/usr/bin/env bash
# Correctless — Harness Fingerprint script (PAT-003 phase-transition convention)
# Spec: .correctless/specs/harness-fingerprint.md
#
# Computes a deterministic fingerprint from the current model identifier and
# a manually-bumped HARNESS_VERSION constant. Compares against a stored value
# and emits a status code. The mechanism is strictly advisory — every code
# path returns exit 0 (PRH-001). Notifications are session-deduplicated via a
# per-session flag file (INV-003 / PRH-005).
#
# CLI:
#   harness-fingerprint.sh check
#     [--meta-dir PATH]       (default: .correctless/meta)
#     [--artifacts-dir PATH]  (default: .correctless/artifacts)
#     [--session-id ID]       (default: get_current_session_id from lib.sh)
#     [--model NAME]          (default: from CLAUDE_CODE_MODEL env, then "unknown")
#
# NOTE: --version was removed in harness-fingerprint-r2-hardening (INV-009 /
# PRH-003 — closes AUTH-R2-001). Tests inject specific HARNESS_VERSION values
# via tests/harness-fingerprint-test-helpers.sh's make_test_harness_script —
# never via a runtime flag.
#
# Output (k=v lines on stdout):
#   fingerprint=...
#   status=first_seen|unchanged|version_bumped|corrupted_recovered
#   model=...
#   harness_version=...
#   notified=true|false
#
# All exit paths return 0.

# ============================================================================
# HARNESS_VERSION — INTEGER CONSTANT (PRH-006)
#
# Bumped manually by the maintainer when an Anthropic harness update is
# observed (see OQ-006 in spec for heuristic). Bumping this value triggers a
# version_bumped signal on the next /cspec invocation in any open session.
# DO NOT bump autonomously — sensitive-file-guard protects this script from
# autonomous Edit/Write once committed.
# ============================================================================
HARNESS_VERSION=1

# ============================================================================
# STEP 1: Source lib.sh (INV-017a)
# ============================================================================

set -uo pipefail  # NOT -e — we want to never exit non-zero
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source lib.sh from script directory or .correctless/scripts/
if [ -f "$SCRIPT_DIR/lib.sh" ]; then
  # shellcheck source=lib.sh
  source "$SCRIPT_DIR/lib.sh"
elif [ -f ".correctless/scripts/lib.sh" ]; then
  # shellcheck disable=SC1091
  source ".correctless/scripts/lib.sh"
else
  echo "warning: harness-fingerprint.sh — lib.sh not found, using minimal fallbacks" >&2
  get_current_session_id() { echo "pid$$"; }
  locked_update_file() {
    local target="$1" filter="$2"; shift 2
    local tmp="${target}.$$.tmp"
    if [ -f "$target" ]; then
      jq "$@" "$filter" "$target" > "$tmp" 2>/dev/null && mv "$tmp" "$target" || { rm -f "$tmp"; return 1; }
    else
      jq -n "$@" "$filter" > "$tmp" 2>/dev/null && mv "$tmp" "$target" || { rm -f "$tmp"; return 1; }
    fi
  }
fi

# ============================================================================
# STEP 2: Parse flags (INV-018 — explicit testability flags)
# ============================================================================

CMD=""
META_DIR=""
ARTIFACTS_DIR=""
SESSION_ID=""
MODEL=""

# Guarded `shift 2` for paired flags: if a flag is the last arg with no value,
# we still need to consume the flag itself (single shift) and continue —
# otherwise `shift 2` on a 1-arg tail is a no-op in some bash builds, looping
# forever on the same `--flag` token. Always shift 1 explicitly first.
while [ $# -gt 0 ]; do
  case "$1" in
    --meta-dir)        META_DIR="${2:-}"; shift; [ $# -gt 0 ] && shift ;;
    --artifacts-dir)   ARTIFACTS_DIR="${2:-}"; shift; [ $# -gt 0 ] && shift ;;
    --session-id)      SESSION_ID="${2:-}"; shift; [ $# -gt 0 ] && shift ;;
    --model)           MODEL="${2:-}"; shift; [ $# -gt 0 ] && shift ;;
    check|help)        CMD="$1"; shift ;;
    -h|--help)         CMD="help"; shift ;;
    *)                 shift ;;  # ignore unknown flags — fail-open per INV-009 / PRH-003
  esac
done

[ -z "$CMD" ] && CMD="check"

if [ "$CMD" = "help" ]; then
  echo "Usage: harness-fingerprint.sh check [--meta-dir PATH] [--artifacts-dir PATH] [--session-id ID] [--model NAME]"
  exit 0
fi

# ============================================================================
# STEP 3: Resolve effective inputs (INV-018 — defaults to live values)
# ============================================================================

# meta-dir / artifacts-dir defaults — relative paths (cwd-anchored fallback)
if [ -z "$META_DIR" ]; then
  META_DIR=".correctless/meta"
fi
if [ -z "$ARTIFACTS_DIR" ]; then
  ARTIFACTS_DIR=".correctless/artifacts"
fi
mkdir -p "$META_DIR" "$ARTIFACTS_DIR" 2>/dev/null || true

# Session-id sentinel scheme (INV-018 / ME-8): production session-ids must
# never start with the test-only prefix __test_session_. If the explicit flag
# was passed, use it verbatim; otherwise derive via lib.sh.
if [ -z "$SESSION_ID" ]; then
  SESSION_ID="$(get_current_session_id 2>/dev/null || echo "pid$$")"
  # Sentinel-prefix assertion: production never uses __test_session_
  case "$SESSION_ID" in
    __test_session_*)
      echo "warning: harness-fingerprint.sh — derived session-id starts with test sentinel; this should not happen in production" >&2
      SESSION_ID="pid$$_invalid_sentinel"
      ;;
  esac
fi

# MA-HI-001: SESSION_ID flows into FLAG_FILE path (line below). Replace any
# character outside [A-Za-z0-9_-] with `_` so a hostile or malformed value
# (e.g. "../../../etc/passwd") cannot escape ARTIFACTS_DIR via path traversal.
# Empty result is replaced with a stable fallback so the path remains valid.
SESSION_ID="$(printf '%s' "$SESSION_ID" | tr -c 'A-Za-z0-9_-' '_')"
[ -z "$SESSION_ID" ] && SESSION_ID="pid$$_empty_after_sanitize"

# Model name — prefer explicit flag, then env, then CLAUDE_MODEL, then "unknown"
if [ -z "$MODEL" ]; then
  MODEL="${CLAUDE_CODE_MODEL:-${CLAUDE_MODEL:-${ANTHROPIC_MODEL:-unknown}}}"
fi

# Effective version — HARNESS_VERSION is the sole production input (INV-009).
EFFECTIVE_VERSION="$HARNESS_VERSION"

# ============================================================================
# STEP 4: Compute literal fingerprint (INV-001 — no hashing)
# ============================================================================

FINGERPRINT="${MODEL}|${EFFECTIVE_VERSION}"
FP_FILE="$META_DIR/harness-fingerprint.json"
FLAG_FILE="$ARTIFACTS_DIR/harness-notified-${SESSION_ID}.flag"

# ============================================================================
# STEP 5: Compare against stored value
# ============================================================================

STATUS=""       # first_seen | unchanged | version_bumped | corrupted_recovered
NOTIFIED="false"
TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

if [ ! -f "$FP_FILE" ]; then
  STATUS="first_seen"
elif ! jq -e . "$FP_FILE" >/dev/null 2>&1; then
  # Corruption (INV-006)
  echo "warning: harness-fingerprint store at $FP_FILE was corrupted — overwriting" >&2
  STATUS="corrupted_recovered"
else
  STORED_FP="$(jq -r '.fingerprint // empty' "$FP_FILE" 2>/dev/null)"
  if [ "$STORED_FP" = "$FINGERPRINT" ]; then
    STATUS="unchanged"
  else
    STATUS="version_bumped"
  fi
fi

# ============================================================================
# STEP 6: Notification dedup (INV-003 / PRH-005)
# ============================================================================

if [ "$STATUS" = "version_bumped" ]; then
  if [ -f "$FLAG_FILE" ]; then
    NOTIFIED="false"  # already notified this session
  else
    NOTIFIED="true"
    # Write flag file (best-effort; non-fatal)
    : > "$FLAG_FILE" 2>/dev/null || true
  fi
fi

# ============================================================================
# STEP 7: Write/update fingerprint store under lock (INV-011, BND-002)
# ============================================================================

if [ "$STATUS" = "first_seen" ] || [ "$STATUS" = "version_bumped" ] || [ "$STATUS" = "corrupted_recovered" ]; then
  # For corrupted_recovered, delete the corrupt file BEFORE the locked write
  # so locked_update_file's "no input" branch produces valid JSON from {} rather
  # than failing on the unparsable existing content.
  if [ "$STATUS" = "corrupted_recovered" ]; then
    rm -f "$FP_FILE"
  fi
  # MA-UC-001: schema_version mirrors BND-004 in model-baselines.json so the
  # two meta files share an evolution mechanism. Bump only when the on-disk
  # shape changes incompatibly; readers ignore unknown future fields.
  if ! locked_update_file "$FP_FILE" \
      '. = {schema_version: 1, fingerprint: $fp, harness_version: ($hv | tonumber), model: $m, timestamp: $ts}' \
      --arg fp "$FINGERPRINT" \
      --arg hv "$EFFECTIVE_VERSION" \
      --arg m "$MODEL" \
      --arg ts "$TIMESTAMP" 2>/dev/null; then
    echo "warning: harness-fingerprint.sh — could not write $FP_FILE (continuing)" >&2
  fi
fi

# ============================================================================
# STEP 8: Emit structured stdout (INV-017c — k=v parseable)
# ============================================================================

echo "fingerprint=${FINGERPRINT}"
echo "status=${STATUS}"
echo "model=${MODEL}"
echo "harness_version=${EFFECTIVE_VERSION}"
echo "notified=${NOTIFIED}"

# PRH-001 — always exit 0
exit 0
