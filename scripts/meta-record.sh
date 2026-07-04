#!/usr/bin/env bash
# Correctless — Sanctioned sole-writer for SFG-protected .correctless/meta/*.json
# Spec: .correctless/specs/calibration-writer.md (INV-001..010, PRH-001..006, BND-001)
#
# Closes the AP-037 class for .correctless/meta/*.json: SFG blocks the naive
# agent Edit/Write to these files, and this Bash-invoked writer is the sanctioned
# (cooperative-loop) write path. It is NOT a security perimeter — SFG does not
# inspect Bash, so a motivated out-of-band Bash write is an accepted non-goal
# (AP-040 / PMB-020). The realpath/symlink guards here are writer robustness
# inside that boundary, not a perimeter.
#
# Operations (each with a HARDCODED destination — PRH-005):
#   calibration-append                 append one object to intensity-calibration.json:calibration_entries[] (stdin JSON)
#   pat001-set-created-at <sha>        set created_at_commit on pat001-measurement-due.json ONLY when present-null
#   baselines-write <model|version>    key-merge one baseline into model-baselines.json (stdin JSON value)
#
# Locking: REUSES the ABS-003 helpers _acquire_state_lock / _release_state_lock
# from lib.sh (PRH-006). It does NOT invent a bespoke lock, never deletes a lock
# directory directly, and never wraps the two-state locked update helper from
# lib.sh (which cannot express this tri-state exit contract, and would deadlock
# inside our own critical section — EXT-001 / DD-008).
#
# Exit-code contract (spec Exit-code semantics table):
#   0 + success line            write applied
#   0 + "no change: <reason>"   intended no-op — NO bytes rewritten (EXT-001)
#   non-zero + FAILED token     rejected/failed (attempted-but-unlanded write)
# The mechanical stdout token on failure is exactly:
#   meta-record: FAILED <file>: <reason>
# which the calling skills echo verbatim so failures are provably surfaced
# (RS-005 / INV-003). NEVER exit 0 after an attempted-but-unlanded write (PRH-004).

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Reuse the canonical lock helpers (PAT-006 dual location: scripts/ + .correctless/scripts/).
if [ -f "$SCRIPT_DIR/lib.sh" ]; then
  # shellcheck source=/dev/null
  . "$SCRIPT_DIR/lib.sh"
else
  printf 'meta-record: FAILED -: cannot source lib.sh (canonical helpers unavailable)\n'
  printf 'meta-record: FAILED -: cannot source lib.sh (canonical helpers unavailable)\n' >&2
  exit 1
fi

MAX_BYTES=65536
META_DIR=".correctless/meta"

# Hardcoded per-operation destinations (PRH-005). Selected by operation name,
# NEVER derived from stdin/argv.
CAL_DEST="$META_DIR/intensity-calibration.json"
PAT_DEST="$META_DIR/pat001-measurement-due.json"
BASE_DEST="$META_DIR/model-baselines.json"

# ---------------------------------------------------------------------------
# Lifecycle: release the lock if held, remove temps. Uses rm -f only (never a
# recursive delete — the lock directory is owned by the ABS-003 helpers).
# ---------------------------------------------------------------------------
LOCK_HELD=""
TMP_OUT=""
TMP_IN=""
_cleanup() {
  # Idempotent: may run twice — once from the INT/TERM trap's explicit call,
  # once from the EXIT trap that fires on the subsequent `exit 130`. Each
  # removal is guarded, so a second invocation on already-gone temps/lock is a
  # safe no-op. _release_state_lock is holder-checked, so a second release is
  # a no-op once the lock is gone.
  [ -n "$LOCK_HELD" ] && _release_state_lock "$LOCK_HELD"
  [ -n "$TMP_OUT" ] && rm -f "$TMP_OUT" 2>/dev/null
  [ -n "$TMP_IN" ] && rm -f "$TMP_IN" 2>/dev/null
  return 0
}
# `_cleanup` ends with `return 0` (no exit), so on a bare INT/TERM trap bash
# would run cleanup and then RESUME the script with a released lock. Split the
# traps so a signal terminates deterministically after cleanup.
trap _cleanup EXIT
trap '_cleanup; exit 130' INT TERM

# _fail <dest> <reason> — emit the mechanical FAILED token (stdout) + a stderr
# diagnostic naming the file, then exit non-zero. The trap releases the lock.
_fail() {
  local d="$1" r="$2"
  printf 'meta-record: FAILED %s: %s\n' "$d" "$r"
  printf 'meta-record: FAILED %s: %s\n' "$d" "$r" >&2
  exit 1
}

# ---------------------------------------------------------------------------
# Fail-closed realpath tool probe (PAT-020; precedent scripts/prune-scan.sh).
# The symlink verdict uses realpath/readlink -f ONLY — never the lexical
# canonicalize_path. When neither tool exists, callers fail loud (EA-004).
# ---------------------------------------------------------------------------
_realpath_tool_available() {
  if command -v realpath >/dev/null 2>&1; then
    return 0
  fi
  if command -v readlink >/dev/null 2>&1 && readlink -f / >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

_realpath_resolve() {
  local p="$1"
  if command -v realpath >/dev/null 2>&1; then
    realpath "$p" 2>/dev/null
  else
    readlink -f "$p" 2>/dev/null
  fi
}

# _verify_dest <dest> — INV-010 destination safety, BEFORE any mkdir/temp/write.
#   return 0  safe
#   return 1  a component is a symlink, or the resolved path is outside META_DIR
#   return 3  realpath/readlink tool absent (fail-closed — caller fails loud)
_verify_dest() {
  local path="$1"
  _realpath_tool_available || return 3
  local comp
  for comp in ".correctless" "$META_DIR" "$path"; do
    if [ -h "$comp" ]; then
      return 1
    fi
  done
  local cwd_real base_real check
  cwd_real="$(_realpath_resolve ".")" || return 1
  if [ -e "$META_DIR" ]; then check="$META_DIR"; else check=".correctless"; fi
  base_real="$(_realpath_resolve "$check")" || return 1
  [ -n "$cwd_real" ] || return 1
  [ -n "$base_real" ] || return 1
  case "$base_real/" in
    "$cwd_real"/*) : ;;
    *) return 1 ;;
  esac
  return 0
}

# _guard_dest <dest> — run the shared INV-010 checks; fail loud on refusal.
_guard_dest() {
  local path="$1" vr
  _verify_dest "$path"; vr=$?
  if [ "$vr" -eq 3 ]; then
    _fail "$path" "no realpath or readlink -f tool available — cannot verify destination symlink status"
  elif [ "$vr" -ne 0 ]; then
    _fail "$path" "destination or a parent directory is a symlink or resolves outside $META_DIR"
  fi
}

# _capture_stdin <dest> — buffer stdin to a temp file (redirect: NUL-safe, no
# $(cat) capture), then enforce the byte ceiling counted with wc -c / LC_ALL=C
# (NOT ${#var}, which counts characters). Payload never transits argv (AP-039).
_capture_stdin() {
  local path="$1"
  TMP_IN="$(mktemp "${TMPDIR:-/tmp}/mr-in-XXXXXX")" || _fail "$path" "cannot create input temp file"
  # MA-M1: bound the INGEST — never buffer an unbounded stream to disk. Read at
  # most MAX_BYTES+1 bytes; the wc -c check below rejects the truncated overflow.
  head -c "$((MAX_BYTES + 1))" > "$TMP_IN"
  local bytes
  bytes="$(LC_ALL=C wc -c < "$TMP_IN" | tr -d '[:space:]')"
  if [ -z "$bytes" ] || ! [ "$bytes" -ge 0 ] 2>/dev/null; then
    _fail "$path" "could not measure input size"
  fi
  if [ "$bytes" -gt "$MAX_BYTES" ]; then
    _fail "$path" "input exceeds ${MAX_BYTES}-byte ceiling (got $bytes)"
  fi
}

# ===========================================================================
# Operation: calibration-append  (INV-001, INV-002, INV-007, INV-008, BND-001)
# ===========================================================================
do_calibration_append() {
  local dest="$CAL_DEST"
  # MA-L2/INV-010: verify the destination (symlink/containment) BEFORE creating
  # any temp or capturing stdin (creation-order safe).
  _guard_dest "$dest"
  _capture_stdin "$dest"
  mkdir -p "$META_DIR" 2>/dev/null

  _acquire_state_lock "$dest" || _fail "$dest" "could not acquire state lock"
  LOCK_HELD="$dest"

  # Decision read + validation live INSIDE the lock (no TOCTOU window — INV-002).
  local base_is_file=0
  if [ -s "$dest" ]; then
    if ! jq -e 'type=="object" and (.calibration_entries|type=="array")' "$dest" >/dev/null 2>&1; then
      _fail "$dest" "existing file is not a valid {\"calibration_entries\":[...]} object"
    fi
    base_is_file=1
  fi

  # Required-field / type validation. Unknown extra fields are PERMISSIVE
  # (accepted + preserved — INV-002/RS-007). Enums pinned to /cverify (INV-008).
  # QA-003: require EXACTLY ONE JSON document on stdin. With a per-value `jq -e`
  # check plus a `--slurpfile` append, two concatenated objects would BOTH
  # validate and BOTH append (silent multi-append). Slurp (-s) and pin
  # length==1, then apply the required-field/type schema to the single document
  # (.[0]). Unknown extra fields stay PERMISSIVE (accepted + preserved, INV-002).
  # jq-1.7-safe: no `as`-bindings; every bound expression is parenthesized.
  if ! jq -e -s '
      def isint: type=="number" and (. == (.|floor));
      def isnn:  isint and . >= 0;
      def isenum: type=="string" and (. == "standard" or . == "high" or . == "critical");
      (length==1)
      and (.[0]|
        (type=="object")
        and (has("feature_slug") and (.feature_slug|type=="string"))
        and (has("recommended_intensity") and (.recommended_intensity|isenum))
        and (has("actual_intensity") and (.actual_intensity|isenum))
        and (has("actual_qa_rounds") and (.actual_qa_rounds|isnn))
        and (has("actual_findings_count") and (.actual_findings_count|isnn))
        and (has("actual_spec_updates") and (.actual_spec_updates|isnn))
        and (has("actual_tokens") and (.actual_tokens|isnn))
        and (has("file_paths_touched") and (.file_paths_touched|type=="array")
             and (all(.file_paths_touched[]; type=="string")))
        and (has("timestamp") and (.timestamp|type=="string"))
        and (if has("actual_cost_usd") then (.actual_cost_usd|type=="number") else true end)
        and (if has("harness_version") then (.harness_version|isint) else true end)
        and (if has("fix_rounds_triggered") then (.fix_rounds_triggered|isint) else true end)
      )
    ' "$TMP_IN" >/dev/null 2>&1; then
    _fail "$dest" "entry failed schema validation (missing/wrong-typed required field, bad enum, non-JSON, or not exactly one JSON document)"
  fi

  # Transform to a same-dir temp; validate; atomic rename (crash-safe, EXT-001).
  # Payload read from the temp FILE via --slurpfile (never argv — AP-039).
  TMP_OUT="${dest}.$$.tmp"
  if [ "$base_is_file" -eq 1 ]; then
    jq --slurpfile e "$TMP_IN" '.calibration_entries += [$e[0]]' "$dest" > "$TMP_OUT" 2>/dev/null \
      || _fail "$dest" "append transform failed"
  else
    jq -n --slurpfile e "$TMP_IN" '{calibration_entries: [$e[0]]}' > "$TMP_OUT" 2>/dev/null \
      || _fail "$dest" "seed+append transform failed"
  fi
  jq -e . "$TMP_OUT" >/dev/null 2>&1 || _fail "$dest" "post-transform output is not valid JSON"

  # MA-M6/EXT-005: re-run the FULL destination check (parents + leaf +
  # containment) under the lock immediately before the rename — identical to the
  # initial _guard_dest, not a leaf-only [ -h ] re-check.
  _guard_dest "$dest"
  mv "$TMP_OUT" "$dest" || _fail "$dest" "atomic rename failed"
  TMP_OUT=""
  _release_state_lock "$dest"; LOCK_HELD=""
  printf 'meta-record: appended calibration entry to %s\n' "$dest"
  return 0
}

# ===========================================================================
# Operation: pat001-set-created-at <sha>   (INV-009 — present-null-only, #192/#226)
# ===========================================================================
do_pat001() {
  local dest="$PAT_DEST"
  local sha="${1:-}"
  # SHA is discrete argv — 40- or 64-hex (RS-012). Reject anything else (a
  # hostile argv can never be interpreted as a shell metacharacter payload —
  # it is validated, never eval'd, and only ever passed to jq via --arg).
  if ! [[ "$sha" =~ ^[0-9a-f]{40}$ ]] && ! [[ "$sha" =~ ^[0-9a-f]{64}$ ]]; then
    _fail "$dest" "invalid SHA argument (expected 40- or 64-hex)"
  fi
  _guard_dest "$dest"

  _acquire_state_lock "$dest" || _fail "$dest" "could not acquire state lock"
  LOCK_HELD="$dest"

  # The writer NEVER creates pat001 — /cdocs only invokes when it exists (EXT-004).
  if [ ! -f "$dest" ]; then
    _fail "$dest" "target does not exist (writer never creates pat001-measurement-due.json)"
  fi
  if ! jq -e 'type=="object"' "$dest" >/dev/null 2>&1; then
    _fail "$dest" "target is corrupt or not a JSON object"
  fi

  # Present-null-only guard: set ONLY when the field is present and literally null.
  # MA-L3: distinguish jq exit 1 (predicate false -> intended no-op) from jq exit
  # >=2 (runtime error -> fail-loud); a decision-read error must never be swallowed
  # into a silent no-op.
  jq -e 'has("created_at_commit") and .created_at_commit == null' "$dest" >/dev/null 2>&1
  local dread_rc=$?
  if [ "$dread_rc" -ge 2 ]; then
    _fail "$dest" "decision-read failed (jq runtime error rc=$dread_rc on created_at_commit)"
  fi
  if [ "$dread_rc" -eq 0 ]; then
    TMP_OUT="${dest}.$$.tmp"
    jq --arg sha "$sha" '.created_at_commit = $sha' "$dest" > "$TMP_OUT" 2>/dev/null \
      || _fail "$dest" "set-created-at transform failed"
    jq -e . "$TMP_OUT" >/dev/null 2>&1 || _fail "$dest" "post-transform output is not valid JSON"
    # MA-M6/EXT-005: full destination re-check under the lock immediately before
    # rename — identical to the initial _guard_dest, not a leaf-only [ -h ].
    _guard_dest "$dest"
    mv "$TMP_OUT" "$dest" || _fail "$dest" "atomic rename failed"
    TMP_OUT=""
    _release_state_lock "$dest"; LOCK_HELD=""
    printf 'meta-record: set created_at_commit on %s\n' "$dest"
    return 0
  fi

  # Absent field OR present-non-null -> intended no-op (exit 0, no bytes rewritten).
  _release_state_lock "$dest"; LOCK_HELD=""
  printf 'no change: created_at_commit is absent or already set on %s\n' "$dest"
  return 0
}

# ===========================================================================
# Operation: baselines-write <model|version>   (INV-009 / EXT-002 — key-merge)
# ===========================================================================
do_baselines() {
  local dest="$BASE_DEST"
  local key="${1:-}"
  if [ -z "$key" ]; then
    _fail "$dest" "missing baseline key (expected <model>|<version>)"
  fi
  # MA-L2/INV-010: verify the destination BEFORE creating any temp/capturing stdin.
  _guard_dest "$dest"
  _capture_stdin "$dest"
  mkdir -p "$META_DIR" 2>/dev/null

  _acquire_state_lock "$dest" || _fail "$dest" "could not acquire state lock"
  LOCK_HELD="$dest"

  # Validate the incoming value is EXACTLY ONE JSON object (under the lock).
  # MA-M2/QA-003: reject a multi-document stdin — never silently slurp-and-drop
  # extras. Mirror calibration's exactly-one-document guard; the key-merge below
  # consumes only $v[0].
  if ! jq -e -s '(length==1) and (.[0]|type=="object")' "$TMP_IN" >/dev/null 2>&1; then
    _fail "$dest" "baseline value on stdin is not exactly one JSON object (or multiple documents given)"
  fi

  TMP_OUT="${dest}.$$.tmp"
  if [ -s "$dest" ]; then
    # Preserve all sibling keys + top-level schema_version; reject a mismatch
    # (fail-loud, never clobber real-but-wrong data — EXT-002).
    if ! jq -e 'type=="object" and (.baselines|type=="object") and (.schema_version==1)' "$dest" >/dev/null 2>&1; then
      _fail "$dest" "existing baselines root is corrupt or schema_version != 1 (mismatch)"
    fi
    jq --slurpfile v "$TMP_IN" --arg k "$key" '.baselines[$k] = ($v[0])' "$dest" > "$TMP_OUT" 2>/dev/null \
      || _fail "$dest" "key-merge transform failed"
  else
    jq -n --slurpfile v "$TMP_IN" --arg k "$key" '{schema_version: 1, baselines: {($k): ($v[0])}}' > "$TMP_OUT" 2>/dev/null \
      || _fail "$dest" "baseline create+merge transform failed"
  fi
  jq -e . "$TMP_OUT" >/dev/null 2>&1 || _fail "$dest" "post-transform output is not valid JSON"

  # MA-M6/EXT-005: re-run the FULL destination check (parents + leaf +
  # containment) under the lock immediately before the rename — identical to the
  # initial _guard_dest, not a leaf-only [ -h ] re-check.
  _guard_dest "$dest"
  mv "$TMP_OUT" "$dest" || _fail "$dest" "atomic rename failed"
  TMP_OUT=""
  _release_state_lock "$dest"; LOCK_HELD=""
  printf 'meta-record: merged baseline %s into %s\n' "$key" "$dest"
  return 0
}

# ---------------------------------------------------------------------------
# Dispatch — unknown op fails loud with NO default write path (PRH-005/DD-005).
# ---------------------------------------------------------------------------
OP="${1:-}"
shift || true
case "$OP" in
  calibration-append)     do_calibration_append "$@" ;;
  pat001-set-created-at)  do_pat001 "$@" ;;
  baselines-write)        do_baselines "$@" ;;
  "" )                    _fail "-" "no operation given (expected calibration-append | pat001-set-created-at | baselines-write)" ;;
  *)                      _fail "$OP" "unknown operation" ;;
esac
