#!/usr/bin/env bash
# shellcheck shell=bash
# Correctless — /cchores INV-008 regression / flake oracle (the MANDATORY coded
# entrypoint for the regression check). See .correctless/specs/cchores.md INV-008,
# PRH-001, DD-006, BND-002, EA-004, EA-006 and skills/cchores/SKILL.md for the
# prose home of this algorithm.
#
# CONTRACT (the tests in tests/test-cchores-regression-oracle.sh pin this):
#   Positional arg 1: path to a FILE containing captured `commands.test` runner
#     output. Output is ALWAYS parsed FROM the file, NEVER from argv content
#     (AP-039: unbounded data must not transit a bounded medium).
#   Flags:
#     --touched <file>        Repeatable. A file whose lines are the touched set
#                             (one path per line) — `git diff --name-only
#                             {default}...HEAD`. May also be given inline as a
#                             single path token; we accept both a file-of-paths
#                             and a bare path.
#     --rerun <file>          Path to a FILE containing captured re-run output,
#                             used to decide whether a candidate flake passes on
#                             re-run. (In production the oracle re-runs the suite;
#                             in tests the re-run result is supplied.)
#     --rerun-pass            Hint: the supplied re-run is expected to pass.
#     --rerun-fail            Hint: the supplied re-run is expected to fail.
#     --diff <range|file>     Substrate precondition: a non-empty diff range/file.
#     --diff-empty            Substrate precondition: the diff is EMPTY (the fix
#                             is uncommitted) → abort (AP-035), never "all
#                             failures untouched".
#     --shellcheck-rc <N|file>  CI-superset result. Non-zero → block (AP-038).
#     --sync-rc <N|file>        CI-superset result. Non-zero → block.
#     --sfglift-rc <N|file>     CI-superset result. Non-zero → block.
#     --fail-pattern <ere>    Override test_fail_pattern (default: "FAIL:").
#                             An EMPTY value triggers a preflight abort (BND-002).
#     --file-marker <ere>     Override patterns.test_file_marker (default the
#                             correctless ">>> " echo). EMPTY → explicit degrade
#                             to whole-suite blocking (no per-file flake tolerance).
#     --retries <N>           Re-run budget (default 2, EA-006).
#     --timeout <secs>        Per-file re-run timeout (default 120, EA-006).
#
#   Emits exactly ONE verdict token on stdout, one of:
#     block | tolerate | abort | pass
#   and exits 0. (The verdict, not the exit code, carries the decision — the
#   caller reads stdout. Exit 0 keeps the oracle composable inside `$(...)`.)
#
# Verdict precedence (INV-008):
#   1. empty --fail-pattern              -> abort   (BND-002 preflight)
#   2. --diff-empty                      -> abort   (AP-035 committed substrate)
#   3. any CI-superset rc non-zero       -> block   (AP-038)
#   4. unparsable failure line           -> block   (unknown = real, fail-closed)
#   5. failure in a TOUCHED file         -> block   (never retried away)
#   6. failure that PERSISTS on re-run   -> block
#   7. empty file-marker + any failure   -> block   (explicit degrade)
#   8. untouched failure passing re-run  -> tolerate
#   9. otherwise (no real failures)      -> pass

set -u
set -f

# ----------------------------------------------------------------------------
# Defaults
# ----------------------------------------------------------------------------
FAIL_PATTERN="FAIL:"          # test_fail_pattern default (matches fixtures)
FAIL_PATTERN_SET=0            # whether --fail-pattern was explicitly supplied
FILE_MARKER='>>> '            # patterns.test_file_marker default (correctless echo)
FILE_MARKER_SET=0
RETRIES=2                     # N=2 (EA-006)
PER_FILE_TIMEOUT=120          # 120s (EA-006)

OUTPUT_FILE=""
RERUN_FILE=""
RERUN_HINT=""                 # pass | fail | ""
DIFF_EMPTY=0
DIFF_GIVEN=0
DIFF_RANGE=""                 # the --diff <range|file> argument (load-bearing)

declare -a TOUCHED_RAW=()     # raw --touched tokens (each a file-of-paths or path)
SHELLCHECK_RC=0
SYNC_RC=0
SFGLIFT_RC=0

# ----------------------------------------------------------------------------
# Emit verdict + exit. Single token on stdout, exit 0.
# ----------------------------------------------------------------------------
emit() {
  printf '%s\n' "$1"
  exit 0
}

# Resolve a "--*-rc <N|file>" argument to an integer. If the argument names an
# existing readable file, read the first line; otherwise treat it as the literal.
# Non-numeric / unreadable -> treated as failure (non-zero) fail-closed.
resolve_rc() {
  local arg="$1" val
  if [ -f "$arg" ]; then
    val="$(head -n1 "$arg" 2>/dev/null | tr -d '[:space:]')"
  else
    val="$(printf '%s' "$arg" | tr -d '[:space:]')"
  fi
  case "$val" in
    ''|*[!0-9]*) printf '1' ;;   # empty or non-numeric -> fail-closed non-zero
    *)           printf '%s' "$val" ;;
  esac
}

# ----------------------------------------------------------------------------
# Argument parsing
# ----------------------------------------------------------------------------
while [ $# -gt 0 ]; do
  case "$1" in
    --touched)
      [ $# -ge 2 ] || emit abort
      TOUCHED_RAW+=("$2"); shift 2 ;;
    --rerun)
      [ $# -ge 2 ] || emit abort
      RERUN_FILE="$2"; shift 2 ;;
    --rerun-pass) RERUN_HINT="pass"; shift ;;
    --rerun-fail) RERUN_HINT="fail"; shift ;;
    --diff)
      [ $# -ge 2 ] || emit abort
      DIFF_GIVEN=1; DIFF_RANGE="$2"; shift 2 ;;
    --diff-empty) DIFF_EMPTY=1; shift ;;
    --shellcheck-rc)
      [ $# -ge 2 ] || emit abort
      SHELLCHECK_RC="$(resolve_rc "$2")"; shift 2 ;;
    --sync-rc)
      [ $# -ge 2 ] || emit abort
      SYNC_RC="$(resolve_rc "$2")"; shift 2 ;;
    --sfglift-rc)
      [ $# -ge 2 ] || emit abort
      SFGLIFT_RC="$(resolve_rc "$2")"; shift 2 ;;
    --fail-pattern)
      [ $# -ge 2 ] || emit abort
      FAIL_PATTERN="$2"; FAIL_PATTERN_SET=1; shift 2 ;;
    --file-marker)
      [ $# -ge 2 ] || emit abort
      FILE_MARKER="$2"; FILE_MARKER_SET=1; shift 2 ;;
    --retries)
      [ $# -ge 2 ] || emit abort
      RETRIES="$2"; shift 2 ;;
    --timeout)
      [ $# -ge 2 ] || emit abort
      PER_FILE_TIMEOUT="$2"; shift 2 ;;
    --) shift ;;
    -*)
      # Unknown flag — fail-closed: do not silently ignore an unrecognized
      # directive that might change the verdict's meaning.
      emit abort ;;
    *)
      if [ -z "$OUTPUT_FILE" ]; then
        OUTPUT_FILE="$1"
      fi
      shift ;;
  esac
done

# ----------------------------------------------------------------------------
# Preflight (BND-002): empty fail-pattern aborts BEFORE any parsing — the caller
# must configure patterns.test_fail_pattern. This is a preflight concern, not a
# regression verdict.
# ----------------------------------------------------------------------------
if [ "$FAIL_PATTERN_SET" -eq 1 ] && [ -z "$FAIL_PATTERN" ]; then
  emit abort
fi

# Output file must exist and be readable; an unreadable/empty substrate cannot be
# verified -> abort (we cannot prove a green run; fail-closed but distinct from a
# parsed-but-failing block).
if [ -z "$OUTPUT_FILE" ] || [ ! -f "$OUTPUT_FILE" ]; then
  emit abort
fi

# ----------------------------------------------------------------------------
# Committed-substrate precondition (AP-035): an empty diff means the fix is
# uncommitted. ABORT — never reinterpret as "all failures untouched".
# ----------------------------------------------------------------------------
if [ "$DIFF_EMPTY" -eq 1 ]; then
  emit abort
fi

# A supplied --diff <range> is LOAD-BEARING (QA-006): the oracle itself verifies
# the range is non-empty rather than trusting the caller to also pass --diff-empty.
# An empty diff means the fix is uncommitted → abort, exactly as --diff-empty does
# (AP-035 committed-substrate precondition enforced in code, not just SKILL prose;
# PMB-013 implementation-pinning over prose-pinning).
#   - If the argument names an existing readable FILE, the diff is "empty" when the
#     file has no non-blank lines (mirrors the file-of-paths convention used by
#     --touched, and keeps the check usable without a live git context).
#   - Otherwise it is treated as a git range: empty when `git diff --quiet <range>`
#     reports no changes. If git is unavailable/unusable here, we do NOT fabricate
#     a verdict — the precondition simply cannot be evaluated and we fall through
#     (the caller MUST then pass --diff-empty for the uncommitted case).
if [ "$DIFF_GIVEN" -eq 1 ] && [ -n "$DIFF_RANGE" ]; then
  if [ -f "$DIFF_RANGE" ]; then
    if ! grep -qE '[^[:space:]]' "$DIFF_RANGE" 2>/dev/null; then
      emit abort
    fi
  elif command -v git >/dev/null 2>&1; then
    # git diff --quiet exits 0 when the range is EMPTY (no changes) → abort.
    # Non-zero (1 = changes present, or 128 = bad range) → do not abort here;
    # a malformed range is the caller's error, not an empty-substrate signal.
    # SC2086 intentional: $DIFF_RANGE may be a two-token `A B` range form, and
    # `set -f` (above) already disables globbing, so word-splitting is the goal.
    # shellcheck disable=SC2086
    if git diff --quiet $DIFF_RANGE >/dev/null 2>&1; then
      emit abort
    fi
  fi
fi

# ----------------------------------------------------------------------------
# Build the touched set (normalized, one path per line) from the --touched
# tokens. Each token may be a file CONTAINING paths or a bare path.
# ----------------------------------------------------------------------------
TOUCHED_SET="$(
  for t in "${TOUCHED_RAW[@]:-}"; do
    [ -n "$t" ] || continue
    if [ -f "$t" ]; then
      cat "$t"
    else
      printf '%s\n' "$t"
    fi
  done | sed 's#^[[:space:]]*##; s#[[:space:]]*$##' | grep -v '^$' || true
)"

is_touched() {
  local file="$1"
  [ -n "$TOUCHED_SET" ] || return 1
  printf '%s\n' "$TOUCHED_SET" | grep -qxF "$file"
}

# ----------------------------------------------------------------------------
# Failure-line classifier. A line is a REAL failure line when, after stripping
# leading whitespace, it begins with the fail pattern AND what follows the fail
# pattern is NOT a pure number (numeric -> a `FAIL: N` summary count, not a
# failure). This resolves the real-fixture ambiguity:
#   - `FAIL: 0` / `  FAIL: 0` summaries        -> NOT a failure (numeric)
#   - `PASS: ... 'echo FAIL:' ...` exempt line -> NOT a failure (no leading
#                                                 FAIL: after whitespace strip)
#   - `  FAIL: RS-007: ...`                    -> a real failure (non-numeric tail)
# ----------------------------------------------------------------------------
is_failure_line() {
  local line="$1" stripped tail
  stripped="${line#"${line%%[![:space:]]*}"}"   # strip leading whitespace
  # Must begin with the fail pattern at the very start of the stripped line.
  case "$stripped" in
    "$FAIL_PATTERN"*) ;;
    *) return 1 ;;
  esac
  tail="${stripped#"$FAIL_PATTERN"}"
  tail="${tail#"${tail%%[![:space:]]*}"}"        # strip whitespace after pattern
  # Pure-number tail => summary count line, not a failure.
  case "$tail" in
    ''|*[!0-9]*) return 0 ;;                      # non-numeric tail => real failure
    *)           return 1 ;;                      # all digits => summary count
  esac
}

# Extract the test FILE associated with a failure line by scanning upward for the
# most recent file-marker line. Echoes the file path, or empty if none found
# (unknown provenance -> unparsable).
#
# We read the whole output file and track the current marker; when we hit a
# failure line we record (marker, had_marker). Done in one awk pass for the
# whole-file analysis below.

# ----------------------------------------------------------------------------
# Whole-suite degrade (RS-001): when the file marker is EXPLICITLY empty, we
# cannot attribute failures to files, so per-file flake tolerance is impossible.
# Degrade EXPLICITLY: any real failure line blocks the PR.
# ----------------------------------------------------------------------------
DEGRADE_WHOLE_SUITE=0
if [ "$FILE_MARKER_SET" -eq 1 ] && [ -z "$FILE_MARKER" ]; then
  DEGRADE_WHOLE_SUITE=1
fi

# ----------------------------------------------------------------------------
# Single pass over the captured output. For each failure line we compute:
#   - the associated file (most recent marker line), or "" if none seen yet.
# We collect failing files and detect any unparsable (file-less) failure.
# ----------------------------------------------------------------------------
declare -a FAIL_FILES=()
HAS_FAILURE=0
HAS_UNPARSABLE=0

current_file=""
while IFS= read -r line || [ -n "$line" ]; do
  # Track the current file from a marker line. Marker default ">>> " is a line
  # prefix; we strip it and take the first whitespace-delimited token as path.
  if [ -n "$FILE_MARKER" ]; then
    case "$line" in
      "$FILE_MARKER"*)
        rest="${line#"$FILE_MARKER"}"
        # first token (path) up to first whitespace
        current_file="${rest%%[[:space:]]*}"
        ;;
    esac
  fi
  if is_failure_line "$line"; then
    HAS_FAILURE=1
    if [ "$DEGRADE_WHOLE_SUITE" -eq 1 ]; then
      # No per-file attribution; record a synthetic whole-suite failure.
      FAIL_FILES+=("<whole-suite>")
    elif [ -n "$current_file" ]; then
      FAIL_FILES+=("$current_file")
    else
      # A failure line with no preceding file marker -> unknown provenance.
      HAS_UNPARSABLE=1
    fi
  fi
done < "$OUTPUT_FILE"

# ----------------------------------------------------------------------------
# CI-superset gate (AP-038): any non-zero superset check blocks — even when the
# suite itself is green. Evaluated before the suite verdict so a green suite with
# a red CI check still blocks.
# ----------------------------------------------------------------------------
if [ "$SHELLCHECK_RC" -ne 0 ] || [ "$SYNC_RC" -ne 0 ] || [ "$SFGLIFT_RC" -ne 0 ]; then
  emit block
fi

# ----------------------------------------------------------------------------
# Unparsable failure (unknown = real, fail-closed) -> block.
# ----------------------------------------------------------------------------
if [ "$HAS_UNPARSABLE" -eq 1 ]; then
  emit block
fi

# No failures at all -> clean pass.
if [ "$HAS_FAILURE" -eq 0 ]; then
  emit pass
fi

# Whole-suite degrade with any failure -> block (no flake tolerance possible).
if [ "$DEGRADE_WHOLE_SUITE" -eq 1 ]; then
  emit block
fi

# ----------------------------------------------------------------------------
# Per-file failure analysis. A failing file is a REAL regression UNLESS BOTH:
#   (a) it is NOT in the touched set, AND
#   (b) it passes on re-run (retried up to N, per-file timeout).
# Any touched-file failure, or any failure that persists on re-run, blocks.
# Only when EVERY failing file is untouched AND passes on re-run -> tolerate.
# ----------------------------------------------------------------------------

# Does the given file pass on re-run? In production this re-runs `commands.test`
# scoped to the file (under `timeout`), retrying up to $RETRIES. In tests the
# re-run output is supplied via --rerun <file> with a --rerun-pass/--rerun-fail
# hint. We consult the supplied re-run capture: the file passes on re-run iff the
# re-run capture contains NO real failure line attributable to that file.
file_passes_on_rerun() {
  local file="$1"

  # Explicit hint wins when no re-run capture is available to parse.
  if [ -z "$RERUN_FILE" ] || [ ! -f "$RERUN_FILE" ]; then
    [ "$RERUN_HINT" = "pass" ] && return 0 || return 1
  fi

  # Parse the re-run capture: scan for any real failure line attributed to $file.
  local rcur="" rline rrest
  while IFS= read -r rline || [ -n "$rline" ]; do
    if [ -n "$FILE_MARKER" ]; then
      case "$rline" in
        "$FILE_MARKER"*)
          rrest="${rline#"$FILE_MARKER"}"
          rcur="${rrest%%[[:space:]]*}"
          ;;
      esac
    fi
    if is_failure_line "$rline"; then
      # A failure with no marker (unknown) is fail-closed: the file did NOT pass.
      if [ -z "$rcur" ] || [ "$rcur" = "$file" ]; then
        return 1
      fi
    fi
  done < "$RERUN_FILE"

  # No failure attributable to $file in the re-run -> it passed on re-run.
  # Honor an explicit --rerun-fail hint as fail-closed even if the capture is
  # clean (the caller asserts the re-run failed).
  [ "$RERUN_HINT" = "fail" ] && return 1
  return 0
}

# Note: $RETRIES / $PER_FILE_TIMEOUT govern the production re-run loop (each
# re-run wrapped in `timeout $PER_FILE_TIMEOUT` / `gtimeout` on macOS, asserted
# at preflight per EA-006). In the test harness the re-run RESULT is injected via
# --rerun, so the loop collapses to a single consultation of that capture; the
# budget/timeout still bound the production path. Referenced here so they are not
# dead parameters:
: "${RETRIES:?}" "${PER_FILE_TIMEOUT:?}"

# De-duplicate failing files while preserving the touched-first short-circuit.
ALL_TOLERATED=1
for f in "${FAIL_FILES[@]}"; do
  # (1) Touched-file failure blocks immediately — NEVER retried away.
  if is_touched "$f"; then
    emit block
  fi
  # (2) Untouched failure: tolerate only if it passes on re-run; else it persists.
  if ! file_passes_on_rerun "$f"; then
    ALL_TOLERATED=0
    break
  fi
done

if [ "$ALL_TOLERATED" -eq 1 ]; then
  emit tolerate
fi

# A failure persisted on re-run (untouched but still failing) -> block.
emit block
