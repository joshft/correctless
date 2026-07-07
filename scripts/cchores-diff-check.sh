#!/usr/bin/env bash
# Correctless — /cchores mode-aware SFG diff/pre-selection gate
# (cchores-protected-affordance spec, INV-006 / INV-007 / INV-009 leg a).
#
# Two coded gates, deterministic (mode + scope are explicit ARGUMENTS, never
# inferred from ambient orchestrator state — R2-H):
#
#   1. Diff / pre-selection gate:
#        printf '%s\n' <changed-files> | cchores-diff-check.sh \
#            --mode explicit|no-arg --allowed-paths <file>
#      Emits `ok` (exit 0) or `abort: <reason>` (exit NON-ZERO, code 2) on
#      stdout. The gate is UNIFORMLY FAIL-CLOSED (QA-005): EVERY abort path
#      returns non-zero so a consumer wired to `$?` fails closed, matching
#      do_check_classification. The `abort:`/`ok` stdout token is retained for
#      legibility, but the exit code is authoritative.
#      Authority split (R2-D): the `# secret-floor` leg (a) and the
#      shared-project-doc leg (b) are marker-INDEPENDENT and abort even when the
#      path is listed in allowed_paths; the out-of-scope leg (c) reads
#      allowed_paths and is a guardrail against naive scope-creep only.
#
#   2. Classification-immutability gate (INV-009 leg a):
#        cchores-diff-check.sh --check-classification --base <hook> --head <hook>
#      Re-extracts the DEFAULTS `# affordance`/`# secret-floor`/`# other-floor`
#      classification from both versions via the SAME anchored parser as INV-008
#      and asserts set-equality; FAILS CLOSED (abort, non-zero) on a
#      moved/absent/duplicated `^DEFAULTS="`…`^"$` anchor.
#
# The secret-floor axis reuses the hook's side-effect-free is_secret_floor()
# (sourced, single source of truth — RS-012), never a re-enumeration.

set -uo pipefail
set -f

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Resolve + source lib.sh (canonicalize_path) and the hook (is_secret_floor /
# is_affordance_eligible / _sfg_classify_target). The hook's main-guard makes
# sourcing a no-op for the policy body.
# ---------------------------------------------------------------------------
if [ -f "$SCRIPT_DIR/lib.sh" ]; then
  # shellcheck source=/dev/null
  . "$SCRIPT_DIR/lib.sh"
fi
_HOOK=""
for _cand in "$SCRIPT_DIR/../hooks/sensitive-file-guard.sh" "$SCRIPT_DIR/../../hooks/sensitive-file-guard.sh"; do
  [ -f "$_cand" ] && { _HOOK="$_cand"; break; }
done
if [ -n "$_HOOK" ]; then
  # shellcheck source=/dev/null
  . "$_HOOK"
fi

# ---------------------------------------------------------------------------
# MA-001: fail-CLOSED capability probe. This script reuses is_secret_floor()
# (sourced from the hook) and canonicalize_path (sourced from lib.sh). If lib.sh
# is absent/stale so canonicalize_path is undefined, _canon() and is_secret_floor()
# return empty and EVERY gate leg of do_diff_check silently PASSES (fails OPEN) —
# including the authoritative secret-floor + shared-doc legs that have NO SFG
# runtime backstop. Run the SAME v1 sentinel probe the hook uses in STEP 4a and
# abort NON-ZERO on absence/version mismatch, before any gate can run.
# Inline fallback: if lib.sh failed to source entirely, require_canonicalize_or_die
# is itself undefined — canonicalize_path is then also undefined, so fail closed.
# NOTE: this is a STARTUP capability failure (before any gate verdict), so the
# message is prefixed `cchores-diff-check:` and exits non-zero — NOT the
# `abort:`/`ok` gate-verdict token (which QA-005-a lints for a paired non-zero
# return inside the gate functions). The exit code is authoritative; a
# $?-wired consumer fails closed.
if declare -f require_canonicalize_or_die >/dev/null 2>&1; then
  require_canonicalize_or_die "cchores-diff-check" || {
    echo "cchores-diff-check: canonicalize_path unavailable — cannot classify paths; every gate leg would fail OPEN. Re-run 'bash setup' to refresh installed scripts (fail-closed)." >&2
    exit 3
  }
elif ! declare -f canonicalize_path >/dev/null 2>&1 \
     || [ "$(canonicalize_path '__canonicalize_path_v1_probe__/foo' 2>/dev/null || true)" != "__canonicalize_path_v1_probe__/foo" ]; then
  echo "cchores-diff-check: canonicalize_path missing or version mismatch — cannot classify paths; every gate leg would fail OPEN. Re-run 'bash setup' to refresh installed scripts (fail-closed)." >&2
  exit 3
fi

# Shared project-doc surface — a /cchores scope concern (stays, not relaxed).
SHARED_DOCS='.correctless/ARCHITECTURE.md
.correctless/AGENT_CONTEXT.md
CLAUDE.md
README.md
.correctless/antipatterns.md'

_canon() { canonicalize_path "$1" >/dev/null 2>&1; printf '%s' "$_CANONICAL_RESULT"; }

_is_shared_doc() {
  local t="$1" d cd
  while IFS= read -r d; do
    [ -z "$d" ] && continue
    cd="$(_canon "$d")"
    [ "$cd" = "$t" ] && return 0
  done <<< "$SHARED_DOCS"
  return 1
}

# _is_protected <canonical> — true if the target matches ANY DEFAULTS pattern
# (any tag). Used for the no-arg "any protected path" and leg-c scope checks.
_is_protected() {
  _sfg_classify_target "$1" >/dev/null 2>&1
}

# ===========================================================================
# Classification-immutability extractor (INV-008 anchored parser, fail-closed).
# ===========================================================================
_extract_classification() { # $1 file -> sorted "pattern\ttag"; return 3 if unrecoverable
  local out rc
  out="$(awk '
    BEGIN { opens=0; closed=0; infl=0 }
    {
      if ($0 ~ /^DEFAULTS="/) {
        opens++
        infl=1
        rest=$0; sub(/^DEFAULTS="/,"",rest)
        if (rest ~ /"$/) { sub(/"$/,"",rest); closed=1; infl=0; emit(rest); next }
        emit(rest)
        next
      }
      if (infl && $0 ~ /^"$/) { closed=1; infl=0; next }
      if (infl) emit($0)
    }
    function emit(l,   pat,tag) {
      if (l == "") return
      if (l ~ /#[[:space:]]*affordance/) tag="affordance"
      else if (l ~ /#[[:space:]]*secret-floor/) tag="secret-floor"
      else if (l ~ /#[[:space:]]*other-floor/) tag="other-floor"
      else tag="untagged"
      pat=l; sub(/[[:space:]]*#.*$/,"",pat)
      if (pat != "") print pat "\t" tag
    }
    END { if (opens != 1 || closed != 1) exit 3 }
  ' "$1")"
  rc=$?
  [ "$rc" -ne 0 ] && return 3
  printf '%s\n' "$out" | sort
  return 0
}

do_check_classification() {
  local base="" head=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --base) base="${2:-}"; shift 2 ;;
      --head) head="${2:-}"; shift 2 ;;
      *) shift ;;
    esac
  done
  if [ -z "$base" ] || [ -z "$head" ] || [ ! -f "$base" ] || [ ! -f "$head" ]; then
    echo "abort: --check-classification requires readable --base and --head hook files (fail-closed)"
    return 3
  fi
  local base_set head_set brc hrc
  base_set="$(_extract_classification "$base")"; brc=$?
  head_set="$(_extract_classification "$head")"; hrc=$?
  if [ "$brc" -ne 0 ] || [ "$hrc" -ne 0 ]; then
    echo "abort: DEFAULTS classification region unrecoverable (moved/absent/duplicated ^DEFAULTS=\"...^\"\$ anchor) — fail-closed (INV-009 leg a)"
    return 3
  fi
  if [ "$base_set" != "$head_set" ]; then
    echo "abort: DEFAULTS classification changed between base and head — floor-immutability violated (INV-009 leg a); defer to human review"
    return 3
  fi
  echo "ok: DEFAULTS classification unchanged"
  return 0
}

# ===========================================================================
# Diff / pre-selection gate.
# ===========================================================================
do_diff_check() {
  local mode="" ap_file=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --mode) mode="${2:-}"; shift 2 ;;
      --mode=*) mode="${1#--mode=}"; shift ;;
      --allowed-paths) ap_file="${2:-}"; shift 2 ;;
      --allowed-paths=*) ap_file="${1#--allowed-paths=}"; shift ;;
      *) echo "abort: unknown argument '$1'"; return 2 ;;
    esac
  done

  case "$mode" in
    explicit|no-arg) ;;
    *) echo "abort: --mode must be explicit|no-arg (got '${mode:-<none>}')"; return 2 ;;
  esac

  # Build the canonical allowed-paths set (may be empty → no scope constraint,
  # i.e. the pre-selection form of the check — INV-006).
  local allowed_nonempty=0 allowed_set=""
  if [ -n "$ap_file" ] && [ -f "$ap_file" ]; then
    local _l cl
    while IFS= read -r _l; do
      [ -z "$_l" ] && continue
      cl="$(_canon "$_l")"
      allowed_set+="$cl"$'\n'
      allowed_nonempty=1
    done < "$ap_file"
  fi

  local f cf
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    cf="$(_canon "$f")"

    # Leg (a): secret-floor is marker-INDEPENDENT and authoritative.
    if is_secret_floor "$cf"; then
      echo "abort: diff touches a # secret-floor path '$f' — never affordance-eligible (INV-007 leg a). Aborting; no PR."
      return 2
    fi
    # Leg (b): shared project docs are marker-INDEPENDENT and authoritative.
    if _is_shared_doc "$cf"; then
      echo "abort: diff touches a shared project-doc '$f' — a chore fix must not edit project docs (INV-007 leg b). Aborting; no PR."
      return 2
    fi

    if [ "$mode" = "no-arg" ]; then
      if _is_protected "$cf"; then
        echo "abort: no-arg mode — protected path '$f' aborts at pre-selection (v1 PRH-003 unchanged)"
        return 2
      fi
      continue
    fi

    # explicit mode, leg (c): scope check only when allowed_paths is provided
    # (the post-cdebug form). Empty allowed_paths = pre-selection (no scope gate).
    if [ "$allowed_nonempty" -eq 1 ] && _is_protected "$cf"; then
      if ! printf '%s' "$allowed_set" | grep -qxF "$cf"; then
        echo "abort: explicit mode — protected path '$f' is not in this run's authorized scope (marker.allowed_paths) (INV-007 leg c). Aborting; no PR."
        return 2
      fi
    fi
  done

  echo "ok"
  return 0
}

# ===========================================================================
# Dispatch
# ===========================================================================
if [ "${1:-}" = "--check-classification" ]; then
  shift
  do_check_classification "$@"
  exit $?
fi
do_diff_check "$@"
exit $?
