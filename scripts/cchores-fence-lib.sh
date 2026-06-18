#!/usr/bin/env bash
# Correctless — shared nonce-fence primitives (INV-009 chokepoint library)
#
# This is the SHARED home for the per-invocation nonce-fence primitives that the
# /cchores ingress chokepoint (scripts/cchores-fence-issue.sh) and the /caudit
# prompt producer (scripts/build-caudit-prompt.sh) both depend on.
#
# Why a separate file rather than lib.sh: `scripts/lib.sh` is SFG-protected
# (sensitive-file-guard DEFAULTS). The MA-S1 fix requires a reusable, CLI-driven
# ingress chokepoint for /cchores issue bodies, and the nonce-fence primitives
# (`_gen_nonce` + `_neutralize_fences`) were previously INTERNAL to
# build-caudit-prompt.sh with no public CLI. Hoisting them here gives both
# producers a single canonical definition WITHOUT touching the SFG-protected
# lib.sh (AP-037 / PMB-017 lift-and-restore friction avoided by construction).
#
# These two functions are byte-for-byte the same contract as the originals in
# build-caudit-prompt.sh — moving them here is a pure refactor with no behavior
# change. build-caudit-prompt.sh continues to define its own copies (it is the
# INSTALLED Step 6a producer and must remain self-contained for the installed
# `.correctless/scripts/` path), so this library is the canonical SOURCE that
# the cchores chokepoint sources; the caudit producer's copies stay in lockstep
# and are guarded by the existing CS-013..CS-018 regression suite.
#
# POSIX externals: head, od, tr, date, sed. sha256sum optional (fallback path).
# Bash 4+ permitted.

# ---------------------------------------------------------------------------
# _gen_nonce — 128-bit hex nonce shared by all fences in one invocation.
# ---------------------------------------------------------------------------
# /dev/urandom is the primary source; a time+pid+RANDOM fallback keeps the
# function working where /dev/urandom is unavailable (still unforgeable by
# untrusted content, which cannot observe wall-clock+pid at emit time and cannot
# predict the value).
_gen_nonce() {
  local n=""
  n="$(head -c16 /dev/urandom 2>/dev/null | od -An -tx1 2>/dev/null | tr -d ' \n')"
  if [ -z "$n" ]; then
    # Fallback: combine epoch-nanoseconds, pid, and RANDOM (still per-invocation
    # and not derivable from the untrusted payload).
    n="$(date +%s%N 2>/dev/null)$$${RANDOM:-0}${RANDOM:-0}"
    # Hash-shape it to a hex-ish token; sha256sum when present, else raw digits.
    if command -v sha256sum >/dev/null 2>&1; then
      n="$(printf '%s' "$n" | sha256sum 2>/dev/null | cut -c1-32)"
    fi
  fi
  printf '%s' "$n"
}

# ---------------------------------------------------------------------------
# _neutralize_fences — break literal fence/framing tokens inside untrusted text.
# ---------------------------------------------------------------------------
# Defense-in-depth: even with a nonce, a nonce-unaware reader must not be
# confused by a forged `</UNTRUSTED_...>` / `<PRE_PR_BASE_MARKERS>` token sitting
# inside untrusted content. We insert a zero-width space (U+200B, UTF-8
# E2 80 8B) immediately after the opening `<` of any fence-like token, so the
# token is no longer a literal fence delimiter but remains human-readable.
#
# The `UNTRUSTED_` prefix rules COVER the `<UNTRUSTED_ISSUE`/`</UNTRUSTED_ISSUE`
# fence shape used by the /cchores ingress chokepoint — this is precisely why
# the chokepoint chose that token family (the neutralizer already breaks it, so
# a hostile body cannot forge the close delimiter).
#
# We ALSO break the authoritative framing markers `TRUSTED FRAMING` and bare
# `nonce=` so a forged framing line inside untrusted content can never survive
# verbatim.
_ZWSP=$'\xe2\x80\x8b'
_neutralize_fences() {
  # Reads stdin, writes neutralized text to stdout.
  sed -e "s|</\\(UNTRUSTED_\\)|<${_ZWSP}/\\1|g" \
      -e "s|<\\(UNTRUSTED_\\)|<${_ZWSP}\\1|g" \
      -e "s|</\\(PRE_PR_BASE_MARKERS\\)|<${_ZWSP}/\\1|g" \
      -e "s|<\\(PRE_PR_BASE_MARKERS\\)|<${_ZWSP}\\1|g" \
      -e "s|TRUSTED FRAMING|TRUSTED${_ZWSP} FRAMING|g" \
      -e "s|nonce=|nonce${_ZWSP}=|g"
}
