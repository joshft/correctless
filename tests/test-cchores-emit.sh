#!/usr/bin/env bash
# Correctless — /cchores egress chokepoint tests
# Tests the coded outbound chokepoint scripts/cchores-emit.sh (INV-013 / MA-S2).
#
# The chokepoint is the SINGLE coded path every outbound /cchores field passes
# through before reaching a public GitHub surface. It must:
#   - redact secrets (delegating to scripts/redact-secrets.sh),
#   - enforce a per-sink byte cap (INV-013: PR body <= 8192, comment <= 4096),
#   - FAIL CLOSED (non-zero exit + empty stdout) if the redactor fails.
#
# New assertions use here-strings (`grep -qF "$needle" <<<"$hay"`), never
# `printf | grep -q`, to avoid the #186 / AP-033 pipefail SIGPIPE flake.
#
# Run from repo root: bash tests/test-cchores-emit.sh

# shellcheck disable=SC1090,SC1091,SC2034

source "$(dirname "${BASH_SOURCE[0]}")/test-helpers.sh"

# ============================================
# SETUP: paths under test
# ============================================

EMITTER="$REPO_DIR/scripts/cchores-emit.sh"
REDACTOR="$REPO_DIR/scripts/redact-secrets.sh"
REDACTION_MARKER="<REDACTED>"

# Run the emitter with the given stdin and args; capture stdout/stderr/exit into
# globals E_OUT / E_ERR / E_CODE.
run_emitter() {
  local input="$1"; shift
  local tmp_out tmp_err
  tmp_out="$(mktemp)"
  tmp_err="$(mktemp)"
  printf '%s' "$input" | bash "$EMITTER" "$@" >"$tmp_out" 2>"$tmp_err"
  E_CODE=$?
  E_OUT="$(cat "$tmp_out")"
  E_ERR="$(cat "$tmp_err")"
  rm -f "$tmp_out" "$tmp_err"
  return $E_CODE
}

# ============================================
# Existence + API contract
# ============================================

section "cchores-emit: existence and executable bit"

if [ -f "$EMITTER" ]; then
  pass "EMIT-EXISTS" "scripts/cchores-emit.sh exists"
else
  fail "EMIT-EXISTS" "scripts/cchores-emit.sh not found"
fi

if [ -x "$EMITTER" ]; then
  pass "EMIT-EXEC" "scripts/cchores-emit.sh is executable"
else
  fail "EMIT-EXEC" "scripts/cchores-emit.sh is not executable (chmod +x)"
fi

# ============================================
# INV-013: redaction through the chokepoint
# ============================================

section "INV-013: secrets are redacted when routed through the chokepoint"

# Tests INV-013: a field containing a secret comes out redacted; no raw secret
# byte survives on stdout.
if [ -x "$EMITTER" ]; then
  SECRET_FIELD='Stack trace leaked AKIAIOSFODNN7EXAMPLE in the comment'  # gitleaks:allow
  RAW_SECRET='AKIAIOSFODNN7EXAMPLE'  # gitleaks:allow
  run_emitter "$SECRET_FIELD" --sink comment
  if [ "$E_CODE" -ne 0 ]; then
    fail "EMIT-REDACTS" "emitter exited $E_CODE on a valid field"
  elif grep -qF "$RAW_SECRET" <<<"$E_OUT"; then
    fail "EMIT-REDACTS" "FAILED: raw secret survived through the chokepoint: '$E_OUT'"
  elif grep -qF "$REDACTION_MARKER" <<<"$E_OUT"; then
    pass "EMIT-REDACTS" "secret redacted when routed through the chokepoint"
  else
    fail "EMIT-REDACTS" "no $REDACTION_MARKER in output: '$E_OUT'"
  fi
else
  fail "EMIT-REDACTS" "scripts/cchores-emit.sh not found"
fi

# Tests INV-013: clean text passes through unchanged, exit 0.
if [ -x "$EMITTER" ]; then
  CLEAN='A normal bug report describing a crash at line 42.'
  run_emitter "$CLEAN" --sink comment
  if [ "$E_CODE" -eq 0 ] && [ "$E_OUT" = "$CLEAN" ]; then
    pass "EMIT-CLEAN" "clean field passes through unchanged, exit 0"
  else
    fail "EMIT-CLEAN" "clean field not preserved (exit=$E_CODE, out='$E_OUT')"
  fi
else
  fail "EMIT-CLEAN" "scripts/cchores-emit.sh not found"
fi

# Tests INV-013 / MA-S2: a multi-line PEM block routed through the chokepoint is
# fully redacted (the chokepoint inherits the redactor's whole-buffer behavior).
if [ -x "$EMITTER" ]; then
  PEM=$'-----BEGIN RSA PRIVATE KEY-----\nMIIEpAIBAAKCAQEAabcdef0123456789ZZZZ\n-----END RSA PRIVATE KEY-----'  # gitleaks:allow
  run_emitter "$PEM" --sink pr-body
  if [ "$E_CODE" -eq 0 ] && ! grep -qF 'PRIVATE KEY' <<<"$E_OUT" && grep -qF "$REDACTION_MARKER" <<<"$E_OUT"; then
    pass "EMIT-PEM-MULTILINE" "multi-line PEM block fully redacted through the chokepoint"
  else
    fail "EMIT-PEM-MULTILINE" "PEM block not fully redacted (exit=$E_CODE, out='$E_OUT')"
  fi
else
  fail "EMIT-PEM-MULTILINE" "scripts/cchores-emit.sh not found"
fi

# ============================================
# INV-013: size cap enforcement (per sink)
# ============================================

section "INV-013: per-sink byte caps are enforced"

# Tests INV-013: an explicit --max-bytes cap truncates an over-cap body and the
# FINAL emitted body (including the overflow notice) fits within the cap.
if [ -x "$EMITTER" ]; then
  # 500 'a' chars of clean text, capped at 200 bytes.
  BIG="$(head -c 500 < /dev/zero | tr '\0' 'a')"
  run_emitter "$BIG" --max-bytes 200
  emitted_len="${#E_OUT}"
  if [ "$E_CODE" -eq 0 ] && [ "$emitted_len" -le 200 ] && [ "$emitted_len" -lt 500 ]; then
    pass "EMIT-CAP-MAXBYTES" "over-cap body truncated to <= 200 bytes (emitted $emitted_len)"
  else
    fail "EMIT-CAP-MAXBYTES" "cap not enforced (exit=$E_CODE, emitted=$emitted_len)"
  fi
else
  fail "EMIT-CAP-MAXBYTES" "scripts/cchores-emit.sh not found"
fi

# Tests INV-013: a truncated body carries the overflow notice pointing at the
# local artifact.
if [ -x "$EMITTER" ]; then
  BIG2="$(head -c 1000 < /dev/zero | tr '\0' 'b')"
  run_emitter "$BIG2" --max-bytes 300
  if grep -qF 'truncated' <<<"$E_OUT"; then
    pass "EMIT-CAP-NOTICE" "truncated body carries an overflow notice"
  else
    fail "EMIT-CAP-NOTICE" "truncated body missing overflow notice: '$E_OUT'"
  fi
else
  fail "EMIT-CAP-NOTICE" "scripts/cchores-emit.sh not found"
fi

# Tests INV-013: the comment sink defaults to a 4096-byte cap; a body just under
# the cap passes through whole.
if [ -x "$EMITTER" ]; then
  UNDER="$(head -c 4000 < /dev/zero | tr '\0' 'c')"
  run_emitter "$UNDER" --sink comment
  if [ "$E_CODE" -eq 0 ] && [ "${#E_OUT}" -eq 4000 ]; then
    pass "EMIT-COMMENT-CAP" "comment body under 4096 passes through whole (${#E_OUT} bytes)"
  else
    fail "EMIT-COMMENT-CAP" "comment-sink body altered unexpectedly (exit=$E_CODE, len=${#E_OUT})"
  fi
else
  fail "EMIT-COMMENT-CAP" "scripts/cchores-emit.sh not found"
fi

# Tests INV-013: truncation never re-introduces a secret — a secret near the
# start of an over-cap body stays redacted in the truncated output.
if [ -x "$EMITTER" ]; then
  PADDING="$(head -c 600 < /dev/zero | tr '\0' 'd')"
  SECRET_THEN_PAD="leak AKIAIOSFODNN7EXAMPLE then ${PADDING}"  # gitleaks:allow
  run_emitter "$SECRET_THEN_PAD" --max-bytes 300
  if [ "$E_CODE" -eq 0 ] && ! grep -qF 'AKIAIOSFODNN7EXAMPLE' <<<"$E_OUT"; then  # gitleaks:allow
    pass "EMIT-CAP-NO-SECRET-LEAK" "truncation does not re-expose a redacted secret"
  else
    fail "EMIT-CAP-NO-SECRET-LEAK" "secret leaked in truncated body (exit=$E_CODE, out='$E_OUT')"
  fi
else
  fail "EMIT-CAP-NO-SECRET-LEAK" "scripts/cchores-emit.sh not found"
fi

# ============================================
# INV-013: fail-closed when the redactor fails
# ============================================

section "INV-013: chokepoint fails closed when the redactor fails"

# Tests INV-013: when the redactor's pattern source is missing, the chokepoint
# exits NON-ZERO and emits EMPTY stdout — it must NOT pass the field through.
if [ -x "$EMITTER" ]; then
  MISSING_SRC="$(mktemp -u)/definitely-not-here.txt"
  tmp_out="$(mktemp)"; tmp_err="$(mktemp)"
  printf '%s' "AKIAIOSFODNN7EXAMPLE leaking" \
    | REDACT_PATTERN_SOURCE="$MISSING_SRC" bash "$EMITTER" --sink comment >"$tmp_out" 2>"$tmp_err"  # gitleaks:allow
  fc_code=$?
  fc_out="$(cat "$tmp_out")"
  rm -f "$tmp_out" "$tmp_err"
  if [ "$fc_code" -ne 0 ] && [ -z "$fc_out" ]; then
    pass "EMIT-FAILCLOSED" "missing redactor source: non-zero exit AND empty stdout"
  elif [ "$fc_code" -eq 0 ]; then
    fail "EMIT-FAILCLOSED" "FAILED OPEN: chokepoint exited 0 when the redactor failed"
  else
    fail "EMIT-FAILCLOSED" "non-zero exit but stdout NOT empty: '$fc_out' (would leak)"
  fi
else
  fail "EMIT-FAILCLOSED" "scripts/cchores-emit.sh not found"
fi

# Tests INV-013: fail-closed on a missing source must NEVER echo the input back.
if [ -x "$EMITTER" ]; then
  MISSING_SRC2="$(mktemp -u)/nope.txt"
  SENTINEL='AKIAIOSFODNN7EXAMPLE'  # gitleaks:allow
  tmp_out="$(mktemp)"
  printf '%s' "$SENTINEL" \
    | REDACT_PATTERN_SOURCE="$MISSING_SRC2" bash "$EMITTER" --sink comment >"$tmp_out" 2>/dev/null
  fc2_out="$(cat "$tmp_out")"
  rm -f "$tmp_out"
  if grep -qF "$SENTINEL" <<<"$fc2_out"; then
    fail "EMIT-FAILCLOSED-NOLEAK" "FAILED OPEN: raw secret reached stdout on redactor failure"
  else
    pass "EMIT-FAILCLOSED-NOLEAK" "redactor failure never echoes the input field"
  fi
else
  fail "EMIT-FAILCLOSED-NOLEAK" "scripts/cchores-emit.sh not found"
fi

# ============================================
# Argument validation
# ============================================

section "cchores-emit: argument validation"

# Tests: an unknown --sink is rejected (non-zero exit), never passed through.
if [ -x "$EMITTER" ]; then
  run_emitter "x" --sink bogus
  if [ "$E_CODE" -ne 0 ]; then
    pass "EMIT-BAD-SINK" "unknown --sink is rejected (exit $E_CODE)"
  else
    fail "EMIT-BAD-SINK" "unknown --sink should be rejected"
  fi
else
  fail "EMIT-BAD-SINK" "scripts/cchores-emit.sh not found"
fi

# Tests: a non-numeric --max-bytes is rejected.
if [ -x "$EMITTER" ]; then
  run_emitter "x" --max-bytes notanumber
  if [ "$E_CODE" -ne 0 ]; then
    pass "EMIT-BAD-MAXBYTES" "non-numeric --max-bytes is rejected (exit $E_CODE)"
  else
    fail "EMIT-BAD-MAXBYTES" "non-numeric --max-bytes should be rejected"
  fi
else
  fail "EMIT-BAD-MAXBYTES" "scripts/cchores-emit.sh not found"
fi

# ============================================
summary "test-cchores-emit"
