#!/usr/bin/env bash
# Correctless — Generated test-count artifact writer/reader
# (the generated-count-artifact abstraction; architecture entry deferred to /cupdate-arch)
# Spec: .correctless/specs/agent-context-count-sync.md (#219, Option 2)
#
# Single shared count command for the R-006(c) gate and the AGENT_CONTEXT.md
# figure. Exposes two subcommands:
#   count   print the integer test-file count over the git INDEX (stdout only)
#   write   (re)generate tests/test-inventory.json atomically + idempotently
#
# The authoritative artifact is tests/test-inventory.json:
#   {"schema_version": 1, "test_file_count": N}
# byte-pinned via a fixed printf template (NOT jq pretty-print) so the bytes are
# identical across jq 1.7/1.8 and across platforms (INV-001 / PRH-004).
#
# DELIBERATE DEVIATION (INV-003 / INV-005): this borrows only the
# tri-state FAILED-token exit discipline from scripts/meta-record.sh. It is
# NOT a sanctioned sole-writer: no lock (single-file, last-write-wins is fine),
# NOT in SFG DEFAULTS, and ANY actor may write it (/ctdd, /cchores, /cdocs,
# humans, CI). Adding SFG protection or sole-writer enforcement re-introduces
# the #219 deadlock. A future audit must NOT "correct" the missing protection.
#
# Exit-code contract (INV-003):
#   0 + success line             the artifact was (re)written
#   0 + "no change" line         already current — NO bytes rewritten (idempotent)
#   0 + "no consumer — skipped"  the R-006(c) consumer marker is absent (no-op)
#   non-zero + "FAILED <reason>" any IO/tool failure (target left unchanged)
# `count` prints the integer to stdout ONLY, nothing else.

set -u

# ---------------------------------------------------------------------------
# Repo-root resolution — pinned two-layout resolver (INV-002 property 2).
# Resolve from the script's OWN ${BASH_SOURCE[0]} directory (NOT $PWD, NOT
# `git rev-parse --show-toplevel`), following symlinks to an absolute path:
#   source form     <root>/scripts/gen-test-inventory.sh              -> root = scriptdir/..
#   installed form  <root>/.correctless/scripts/gen-test-inventory.sh -> root = scriptdir/../..
# The installed form targets the PROJECT tests/, never .correctless/tests/.
# ---------------------------------------------------------------------------
_src="${BASH_SOURCE[0]}"
while [ -h "$_src" ]; do
  _d="$(cd -P "$(dirname "$_src")" >/dev/null 2>&1 && pwd)"
  _src="$(readlink "$_src")"
  case "$_src" in
    /*) ;;
    *)  _src="$_d/$_src" ;;
  esac
done
SCRIPT_DIR="$(cd -P "$(dirname "$_src")" >/dev/null 2>&1 && pwd)"
_PARENT="$(dirname "$SCRIPT_DIR")"
if [ "$(basename "$_PARENT")" = ".correctless" ]; then
  ROOT="$(dirname "$_PARENT")"       # installed: scriptdir/../..
else
  ROOT="$_PARENT"                    # source:    scriptdir/..
fi

TESTS_DIR="$ROOT/tests"
CONSUMER="$TESTS_DIR/test-ap031-fixture-divergence.sh"
TARGET="$TESTS_DIR/test-inventory.json"

# ---------------------------------------------------------------------------
# Temp lifecycle — a glob-safe DOTFILE temp in tests/ itself (same filesystem,
# so `mv` is a rename; the leading `.` means it can never match the `test*.sh`
# count glob and self-inflate the count — INV-003 / RS-011). The trap removes
# it on ANY exit path, so no orphan temp survives a failed write.
# ---------------------------------------------------------------------------
TMP=""
_cleanup() { [ -n "$TMP" ] && rm -f "$TMP" 2>/dev/null; return 0; }
trap _cleanup EXIT
trap '_cleanup; exit 130' INT TERM

# _fail <reason> — mechanical FAILED token on stdout (echoed verbatim by
# callers per INV-006), diagnostic on stderr, then exit non-zero. The trap
# removes any temp; the target is left byte-unchanged (never a truncated write).
_fail() {
  printf 'gen-test-inventory: FAILED %s\n' "$1"
  printf 'gen-test-inventory: FAILED %s\n' "$1" >&2
  exit 1
}

# ---------------------------------------------------------------------------
# Shared count command (INV-002 property 3): "actual" is computed over the
# committed/staged INDEX (never the working tree), so an untracked scratch
# tests/test-*.sh cannot perturb it and a clean CI checkout computes the same
# value. `git ls-files --cached` already includes staged additions — do NOT
# union a separate staged-adds list (EXT-004). Post-filter to DIRECT children
# of tests/ (reject any path with a second `/` — preserves -maxdepth 1
# semantics, EXT-005). LC_ALL=C forced internally (EA-003); any wc/grep count
# normalized with `tr -d ' '`. NUL-delimited so newline-in-filename can't
# miscount.
#
# INV-003 fail-loud (QA-001): a git FAILURE (ROOT not a repo, corrupt/locked
# index, missing .git) must NOT collapse to an empty pipe -> grep -c . -> a
# valid-looking '0'. Capture git under `set -o pipefail` and `_fail` on any
# non-zero git/cd exit BEFORE counting. A git SUCCESS with zero matches (exit 0,
# empty output) still yields a valid '0' — only a NON-ZERO git exit is a
# failure. Sets the global COUNT (callers must invoke this directly, NOT via
# `$(...)`, so `_fail`'s exit propagates to the top-level shell).
# ---------------------------------------------------------------------------
COUNT=""
_compute_count() {
  local raw
  # NUL->newline INSIDE the capture subshell (bash drops NULs on variable
  # capture), so git's exit status is observable via pipefail while the
  # newline-delimited direct-children filter below stays byte-identical.
  if ! raw="$( set -o pipefail
               cd "$ROOT" 2>/dev/null \
                 && LC_ALL=C git ls-files --cached -z -- 'tests/test*.sh' \
                    | tr '\0' '\n' )"; then
    _fail "git ls-files failed in $ROOT"
  fi
  COUNT="$( printf '%s\n' "$raw" \
              | awk -F/ 'NF==2 && $0 != ""' \
              | grep -c . \
              | tr -d ' ' )"
}

do_count() {
  command -v git >/dev/null 2>&1 || _fail "git not found (EA-001)"
  local n
  _compute_count          # sets COUNT (or _fail-exits on git failure); no $(...)
  n="$COUNT"
  case "$n" in
    ''|*[!0-9]*) _fail "count did not resolve to an integer (got '$n')" ;;
  esac
  printf '%s\n' "$n"
  return 0
}

do_write() {
  # EA-001 dependency validation — fail loud if a required tool is missing.
  command -v git    >/dev/null 2>&1 || _fail "git not found (EA-001)"
  command -v mktemp >/dev/null 2>&1 || _fail "mktemp not found (EA-001)"
  command -v mv     >/dev/null 2>&1 || _fail "mv not found (EA-001)"

  local n
  _compute_count          # sets COUNT (or _fail-exits on git failure); no $(...)
  n="$COUNT"
  case "$n" in
    ''|*[!0-9]*) _fail "count did not resolve to an integer (got '$n')" ;;
  esac

  # Byte-pinned canonical serialization (NOT jq) — fixed single trailing newline.
  local desired
  desired="$(printf '{"schema_version": 1, "test_file_count": %s}\n' "$n")"

  # Create the glob-safe dotfile temp in tests/ (same fs as the target).
  TMP="$(mktemp "$TESTS_DIR/.test-inventory.json.tmp.XXXXXX" 2>/dev/null)" \
    || _fail "cannot create temp file in $TESTS_DIR (unwritable?)"

  printf '%s\n' "$desired" > "$TMP" 2>/dev/null \
    || _fail "cannot write temp file $TMP"

  # Idempotent no-op: if the target already byte-matches, rewrite NOTHING
  # (preserve inode + mtime — INV-001). Remove the temp; never mv.
  if [ -f "$TARGET" ] && cmp -s "$TMP" "$TARGET"; then
    rm -f "$TMP"; TMP=""
    printf 'gen-test-inventory: no change (test_file_count=%s)\n' "$n"
    return 0
  fi

  # Real change: atomic same-fs rename onto the target.
  mv "$TMP" "$TARGET" 2>/dev/null || _fail "atomic rename onto $TARGET failed"
  TMP=""
  printf 'gen-test-inventory: wrote tests/test-inventory.json (test_file_count=%s)\n' "$n"
  return 0
}

# ---------------------------------------------------------------------------
# Generator-side consumer guard (INV-003 / EXT-006): BOTH write and count first
# verify the R-006(c) consumer marker exists. If absent, no-op (exit 0, emit the
# skip token, write nothing) — the structural backstop for RS-001 so a
# downstream `.correctless/scripts/gen-test-inventory.sh write` on a host project
# cannot create or stage an orphan artifact.
# ---------------------------------------------------------------------------
OP="${1:-}"
if [ ! -f "$CONSUMER" ]; then
  printf 'gen-test-inventory: no consumer — skipped\n'
  exit 0
fi

case "$OP" in
  count) do_count ;;
  write) do_write ;;
  "")    _fail "no subcommand given (expected: count | write)" ;;
  *)     _fail "unknown subcommand '$OP' (expected: count | write)" ;;
esac
