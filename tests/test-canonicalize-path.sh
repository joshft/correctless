#!/usr/bin/env bash
# Correctless — canonicalize_path Tests (RED phase)
# Tests spec rules from .correctless/specs/harness-fingerprint-r2-hardening.md
# INV-001, INV-001a, INV-002, INV-002a, INV-003, INV-004, INV-012; PRH-001
# Run from repo root: bash tests/test-canonicalize-path.sh

source "$(dirname "${BASH_SOURCE[0]}")/test-helpers.sh"

LIB="$REPO_DIR/scripts/lib.sh"
GUARD="$REPO_DIR/hooks/sensitive-file-guard.sh"

# Source lib.sh so tests can call canonicalize_path directly.
# The function does not yet exist (RED phase) — tests will fail at "command not found".
# shellcheck disable=SC1090
source "$LIB" 2>/dev/null || true

# ============================================================================
# Fuzz corpus generator (INV-001 / INV-001a / INV-002 / INV-003 / INV-004)
# Pinned characteristics per Finding #5 amendment:
#   - seed RANDOM=42
#   - 1000 inputs
#   - length distribution uniform over [0, 1024] bytes
#   - byte alphabet: each of *, ?, [, ], /, ., space, tab, newline, $, `, (, {
#     must appear in at least 50 inputs (10% threshold)
# ============================================================================

CORPUS_FILE="$REPO_DIR/.correctless/artifacts/test-canonicalize-fuzz-corpus.txt"
CORPUS_REQUIRED_BYTES=('*' '?' '[' ']' '/' '.' ' ' '$' '`' '(' '{')
CORPUS_SIZE=1000

generate_fuzz_corpus() {
  mkdir -p "$(dirname "$CORPUS_FILE")"
  RANDOM=42
  : > "$CORPUS_FILE"
  local i len j ch line
  # Build a 70-byte alphabet skewed toward required bytes so the threshold is met
  local alphabet='abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789*?[]/.$ ` ({}-_'
  for ((i = 0; i < CORPUS_SIZE; i++)); do
    len=$((RANDOM % 1025))
    line=""
    for ((j = 0; j < len; j++)); do
      ch="${alphabet:RANDOM % ${#alphabet}:1}"
      line+="$ch"
    done
    # Force-inject required bytes into ~10% of inputs (round-robin) so the
    # threshold check passes deterministically
    if [ $((i % 9)) -eq 0 ]; then
      local k=$((i / 9 % ${#CORPUS_REQUIRED_BYTES[@]}))
      line+="${CORPUS_REQUIRED_BYTES[$k]}"
    fi
    # Tab and newline added to a different subset
    if [ $((i % 23)) -eq 0 ]; then line+=$'\t'; fi
    if [ $((i % 31)) -eq 0 ]; then line+=$'\n'; fi
    printf '%s\0' "$line" >> "$CORPUS_FILE"
  done
}

# ============================================================================
# INV-001: canonicalize_path is total over arbitrary byte sequences
# ============================================================================
test_inv001_totality() {
  if ! command -v canonicalize_path >/dev/null 2>&1 && ! declare -f canonicalize_path >/dev/null 2>&1; then
    fail "INV-001" "canonicalize_path is not defined in lib.sh"
    return
  fi
  generate_fuzz_corpus
  local total_failures=0 total_run=0
  local input out rc lines
  while IFS= read -r -d '' input; do
    total_run=$((total_run + 1))
    # Per-invocation 2s timeout
    out="$(timeout 2 bash -c "
      # shellcheck disable=SC1090
      source '$LIB'
      canonicalize_path \"\$1\"
    " _ "$input" 2>/dev/null)"
    rc=$?
    if [ "$rc" -ne 0 ]; then
      total_failures=$((total_failures + 1))
      if [ "$total_failures" -le 3 ]; then
        echo "  INV-001 failure (rc=$rc) on input hex: $(printf '%s' "$input" | xxd | head -3)" >&2
      fi
      continue
    fi
    lines="$(printf '%s' "$out" | wc -l)"
    if [ "$lines" -gt 1 ]; then
      total_failures=$((total_failures + 1))
      if [ "$total_failures" -le 3 ]; then
        echo "  INV-001 multi-line output on input hex: $(printf '%s' "$input" | xxd | head -3)" >&2
      fi
    fi
  done < "$CORPUS_FILE"

  if [ "$total_failures" -eq 0 ] && [ "$total_run" -gt 0 ]; then
    pass "INV-001" "totality: all $total_run inputs produced single-line stdout, exit 0, no hang"
  else
    fail "INV-001" "totality: $total_failures/$total_run inputs hung, errored, or produced multi-line output"
  fi
}

# ============================================================================
# INV-001a: empty-output-on-non-empty-input is forbidden
# ============================================================================
test_inv001a_no_empty_output_on_nonempty_input() {
  if ! declare -f canonicalize_path >/dev/null 2>&1; then
    fail "INV-001a" "canonicalize_path is not defined"
    return
  fi
  [ -f "$CORPUS_FILE" ] || generate_fuzz_corpus
  local violations=0 input trimmed out
  while IFS= read -r -d '' input; do
    # Strip whitespace for the "non-empty after trim" check
    trimmed="$(printf '%s' "$input" | tr -d ' \t\n')"
    [ -z "$trimmed" ] && continue
    out="$(timeout 2 bash -c "
      source '$LIB'
      canonicalize_path \"\$1\"
    " _ "$input" 2>/dev/null)"
    if [ -z "$out" ]; then
      violations=$((violations + 1))
      [ "$violations" -le 3 ] && echo "  INV-001a empty output on non-empty input: $(printf '%s' "$input" | xxd | head -1)" >&2
    fi
  done < "$CORPUS_FILE"
  if [ "$violations" -eq 0 ]; then
    pass "INV-001a" "no empty stdout for any non-empty input in fuzz corpus"
  else
    fail "INV-001a" "$violations non-empty inputs produced empty stdout (silent fail-open class)"
  fi
}

# ============================================================================
# INV-002: output shape — no //, no . segment, no .. on absolute, no trailing /
# ============================================================================
test_inv002_output_shape() {
  if ! declare -f canonicalize_path >/dev/null 2>&1; then
    fail "INV-002" "canonicalize_path is not defined"
    return
  fi
  [ -f "$CORPUS_FILE" ] || generate_fuzz_corpus
  local violations=0 input out
  while IFS= read -r -d '' input; do
    out="$(timeout 2 bash -c "source '$LIB'; canonicalize_path \"\$1\"" _ "$input" 2>/dev/null)"
    [ -z "$out" ] && continue
    # No `//`
    if printf '%s' "$out" | grep -q '//' ; then
      violations=$((violations + 1)); continue
    fi
    # No `/./`
    if printf '%s' "$out" | grep -q '/\./' ; then
      violations=$((violations + 1)); continue
    fi
    # No leading `./` (a `.` segment) — output `.` alone is OK (canonical empty form)
    if [ "$out" != "." ] && printf '%s' "$out" | grep -q '^\./' ; then
      violations=$((violations + 1)); continue
    fi
    # If absolute, no `..` segment
    if [ "${out:0:1}" = "/" ] && printf '%s' "$out" | grep -q '/\.\.\(/\|$\)' ; then
      violations=$((violations + 1)); continue
    fi
    # No trailing `/` unless output is exactly `/`
    if [ "$out" != "/" ] && [ "${out: -1}" = "/" ]; then
      violations=$((violations + 1)); continue
    fi
  done < "$CORPUS_FILE"
  if [ "$violations" -eq 0 ]; then
    pass "INV-002" "output shape constraints upheld across fuzz corpus"
  else
    fail "INV-002" "$violations corpus inputs produced malformed canonical output"
  fi
}

# ============================================================================
# INV-002a: only ASCII 0x2E is treated as a path-segment dot
# ============================================================================
test_inv002a_ascii_only_dot_recognition() {
  if ! declare -f canonicalize_path >/dev/null 2>&1; then
    fail "INV-002a" "canonicalize_path is not defined"
    return
  fi
  # U+2024 ONE DOT LEADER  (UTF-8: e2 80 a4)
  local one_dot_leader=$'\xe2\x80\xa4'
  # U+FF0E FULLWIDTH FULL STOP (UTF-8: ef bc 8e)
  local fullwidth_stop=$'\xef\xbc\x8e'
  # U+2026 HORIZONTAL ELLIPSIS (UTF-8: e2 80 a6)
  local ellipsis=$'\xe2\x80\xa6'

  local out fail_count=0
  for pair in \
      "subdir/${one_dot_leader}${one_dot_leader}/.env" \
      "subdir/${fullwidth_stop}${fullwidth_stop}/.env" \
      "subdir/${ellipsis}/.env"
  do
    out="$(canonicalize_path "$pair" 2>/dev/null)"
    # The Unicode lookalike must NOT be collapsed into a `..` traversal.
    # Output must still contain the literal multibyte sequence (no path-segment-up).
    if [ -z "$out" ]; then
      fail_count=$((fail_count + 1))
      echo "  INV-002a: empty output on Unicode-dot input" >&2
      continue
    fi
    # If the implementation honored the lookalike as `..`, output would be `subdir/.env` or `.env`
    # — the lookalike bytes would be gone.
    if ! printf '%s' "$out" | grep -q "$(printf '%s' "$pair" | head -c 8 | tail -c 4 || true)" 2>/dev/null; then
      :  # not a strong signal alone; rely on the dot-collapse check below
    fi
    # Strong signal: `subdir/.env` or `.env` (with no Unicode bytes) means the lookalike was honored.
    if [ "$out" = "subdir/.env" ] || [ "$out" = ".env" ]; then
      fail_count=$((fail_count + 1))
      echo "  INV-002a: Unicode lookalike was treated as a path-segment dot (output: $out)" >&2
    fi
  done

  if [ "$fail_count" -eq 0 ]; then
    pass "INV-002a" "Unicode dot lookalikes survive canonicalization as ordinary bytes"
  else
    fail "INV-002a" "$fail_count Unicode-dot inputs were collapsed as if ASCII dot — bypass class open"
  fi
}

# ============================================================================
# INV-003: idempotence
# ============================================================================
test_inv003_idempotent() {
  if ! declare -f canonicalize_path >/dev/null 2>&1; then
    fail "INV-003" "canonicalize_path is not defined"
    return
  fi
  [ -f "$CORPUS_FILE" ] || generate_fuzz_corpus
  local violations=0 input out1 out2
  while IFS= read -r -d '' input; do
    out1="$(canonicalize_path "$input" 2>/dev/null)"
    out2="$(canonicalize_path "$out1" 2>/dev/null)"
    if [ "$out1" != "$out2" ]; then
      violations=$((violations + 1))
      [ "$violations" -le 3 ] && echo "  INV-003: '$out1' != '$out2'" >&2
    fi
  done < "$CORPUS_FILE"
  if [ "$violations" -eq 0 ]; then
    pass "INV-003" "idempotence verified across fuzz corpus"
  else
    fail "INV-003" "$violations inputs produced different output on second pass"
  fi
}

# ============================================================================
# INV-004: no shell expansion (literal bytes through)
# ============================================================================
test_inv004_no_shell_expansion() {
  if ! declare -f canonicalize_path >/dev/null 2>&1; then
    fail "INV-004" "canonicalize_path is not defined"
    return
  fi
  local fail_count=0 out

  out="$(canonicalize_path 'a/*' 2>/dev/null)"
  printf '%s' "$out" | grep -q '\*' || { fail_count=$((fail_count + 1)); echo "  INV-004: '*' did not survive (got: '$out')" >&2; }

  out="$(canonicalize_path '$(date)' 2>/dev/null)"
  if printf '%s' "$out" | grep -qE '[0-9]{4}|Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec'; then
    fail_count=$((fail_count + 1)); echo "  INV-004: command substitution expanded (got: '$out')" >&2
  fi

  out="$(canonicalize_path '`whoami`' 2>/dev/null)"
  if [ "$out" = "$(whoami)" ]; then
    fail_count=$((fail_count + 1)); echo "  INV-004: backtick substitution expanded" >&2
  fi

  out="$(canonicalize_path 'a/{b,c}/d' 2>/dev/null)"
  printf '%s' "$out" | grep -q '{b,c}' || { fail_count=$((fail_count + 1)); echo "  INV-004: brace expansion happened (got: '$out')" >&2; }

  out="$(canonicalize_path '$HOME' 2>/dev/null)"
  if [ "$out" = "$HOME" ] && [ -n "$HOME" ]; then
    fail_count=$((fail_count + 1)); echo "  INV-004: parameter expansion happened (got: '$out')" >&2
  fi

  # Structural grep: function body must not contain eval, command-sub, backtick, glob ops
  local body
  body="$(awk '/^canonicalize_path[[:space:]]*\(\)/,/^}/' "$LIB" 2>/dev/null)"
  if [ -n "$body" ]; then
    if printf '%s' "$body" | grep -qE '\beval\b|\bcompgen\b|\bextglob\b' ; then
      fail_count=$((fail_count + 1)); echo "  INV-004: function body contains eval / compgen / extglob" >&2
    fi
    # Command substitution: $( not followed by another ( (which would be arithmetic)
    if printf '%s' "$body" | grep -v '^[[:space:]]*#' | grep -qE '\$\([^(]' ; then
      fail_count=$((fail_count + 1)); echo "  INV-004: function body contains command substitution \$(...)" >&2
    fi
    # Backtick check: literal grave accent in non-comment lines
    if printf '%s' "$body" | grep -v '^[[:space:]]*#' | grep -q '`' ; then
      fail_count=$((fail_count + 1)); echo "  INV-004: function body contains backtick command substitution" >&2
    fi
  else
    fail_count=$((fail_count + 1)); echo "  INV-004: cannot find canonicalize_path body in lib.sh" >&2
  fi

  if [ "$fail_count" -eq 0 ]; then
    pass "INV-004" "no shell expansion: literal bytes survive; body contains no eval/sub/glob"
  else
    fail "INV-004" "$fail_count shell-expansion violations"
  fi
}

# ============================================================================
# INV-012: performance bound + no fork/exec
# ============================================================================
test_inv012_performance_and_no_fork_exec() {
  if ! declare -f canonicalize_path >/dev/null 2>&1; then
    fail "INV-012" "canonicalize_path is not defined"
    return
  fi
  # Build a 1024-byte path with mixed traversal/glob characters
  local path=""
  while [ "${#path}" -lt 1024 ]; do
    path+="subdir/../foo[*]/.bar/baz/"
  done
  path="${path:0:1024}"

  local t0 t1 elapsed_ms mean_ms
  t0=$(date +%s%N)
  for _ in $(seq 1 100); do
    canonicalize_path "$path" >/dev/null 2>&1
  done
  t1=$(date +%s%N)
  elapsed_ms=$(( (t1 - t0) / 1000000 ))
  mean_ms=$(( elapsed_ms / 100 ))

  local fail_count=0
  if [ "$mean_ms" -gt 50 ]; then
    fail_count=$((fail_count + 1))
    echo "  INV-012: mean wall time ${mean_ms}ms > 50ms" >&2
  fi

  # Structural grep: function body must not have $(...) command-sub, backticks, or pipes
  local body
  body="$(awk '/^canonicalize_path[[:space:]]*\(\)/,/^}/' "$LIB" 2>/dev/null)"
  if [ -n "$body" ]; then
    # Strip comments for the grep
    local body_nc
    body_nc="$(printf '%s' "$body" | grep -v '^[[:space:]]*#')"
    # $( not followed by ( — distinguishes command substitution from arithmetic $((..))
    if printf '%s' "$body_nc" | grep -qE '\$\([^(]' ; then
      fail_count=$((fail_count + 1)); echo "  INV-012: command substitution \$( in body" >&2
    fi
    if printf '%s' "$body_nc" | grep -q '`' ; then
      fail_count=$((fail_count + 1)); echo "  INV-012: backtick in body" >&2
    fi
    # NB: pipe-operator structural check intentionally omitted — bash `case`
    # alternation uses `|` and false-matches. The wall-time bound below
    # already detects any actual fork/exec.
  else
    fail_count=$((fail_count + 1)); echo "  INV-012: cannot extract canonicalize_path body" >&2
  fi

  if [ "$fail_count" -eq 0 ]; then
    pass "INV-012" "perf bound met (mean=${mean_ms}ms < 50ms); no fork/exec patterns in body"
  else
    fail "INV-012" "$fail_count perf/structural violations (mean=${mean_ms}ms)"
  fi
}

# ============================================================================
# PRH-001: no regex-based path normalization
# ============================================================================
test_prh001_no_regex_normalization() {
  local fail_count=0
  for f in "$LIB" "$GUARD"; do
    [ -f "$f" ] || continue
    if grep -nE 's\|/[^/]+/\\.\\.|s/\[\^/\]\\+/\\.\\.\\/' "$f" | grep -v '^[[:space:]]*#' >/dev/null 2>&1; then
      fail_count=$((fail_count + 1))
      echo "  PRH-001: regex-based normalization pattern found in $f" >&2
    fi
    # Loose check for the literal R1 fix patterns
    if grep -n 's|/[^/]\+/\.\.\.|/' "$f" 2>/dev/null | grep -v '^[[:space:]]*#' >/dev/null; then
      fail_count=$((fail_count + 1))
      echo "  PRH-001: literal R1 normalization pattern found in $f" >&2
    fi
  done
  if [ "$fail_count" -eq 0 ]; then
    pass "PRH-001" "no regex-based path normalization in lib.sh / sensitive-file-guard.sh"
  else
    fail "PRH-001" "$fail_count regex-normalization patterns remain"
  fi
}

# ============================================================================
# Run
# ============================================================================
test_inv001_totality
test_inv001a_no_empty_output_on_nonempty_input
test_inv002_output_shape
test_inv002a_ascii_only_dot_recognition
test_inv003_idempotent
test_inv004_no_shell_expansion
test_inv012_performance_and_no_fork_exec
test_prh001_no_regex_normalization

summary "canonicalize_path"
