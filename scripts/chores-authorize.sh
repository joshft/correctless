#!/usr/bin/env bash
# Correctless — sanctioned writer for the /cchores protected-file affordance
# authorization marker (cchores-protected-affordance spec, PRH-003 v2 / ABS-049).
#
# The marker `.correctless/artifacts/chores-protected-authorized.json` is the
# branch- AND file-scoped authorization that sensitive-file-guard.sh consults to
# conditionally allow an Edit/Write to an `# affordance`-tagged DEFAULTS path.
# This script is the SOLE cooperative-loop write path to that marker (INV-014);
# the marker + this writer (three forms) are in SFG DEFAULTS so a naive agent
# Edit/Write to either is blocked. SFG does NOT inspect Bash, so an out-of-band
# Bash write is the accepted AP-040 residual — "sole writer" means the sanctioned
# path, not a security perimeter (PMB-020).
#
# Subcommands:
#   write --issue <N> [--allowed-paths <p[,p...]>]...   mint the marker (INV-001)
#   clear                                               remove the marker (idempotent, INV-005)
#   check                                               0 if a marker binds the current branch, else non-zero
#   check-capability <installed-hook-path>              behavioral probe (INV-012)
#
# `write` REFUSES (non-zero, no marker) unless invoked with an explicit
# `--issue <N>` whose <N> matches the current `chore/issue-<N>-*` branch (INV-001
# structural leg — relocated from prompt-level into tested bash). It binds the
# marker to a per-run `run_id` sourced from (or seeded into) the chore-run
# manifest (INV-005), so a leaked marker from a crashed run is inert AGAINST A
# LATER /cchores RUN (the next run mints a fresh run_id / clear rotates the old
# one out). The narrower crash-window residual — a manual/injected edit on the
# SAME branch after do_write and before the next run's do_clear, while marker and
# manifest still share a run_id — is an ACCEPTED residual (like the OQ-005
# in-tree-write residual): SFG is a cooperative-loop guardrail (AP-040/PMB-020),
# affordance paths are non-security infra, and any resulting PR is never-merged +
# human-reviewed. A TTL bound (OQ-003) stays deferred.

set -uo pipefail

MARKER_REL=".correctless/artifacts/chores-protected-authorized.json"

# ---------------------------------------------------------------------------
# Source lib.sh for branch_slug() (QA-004): the run manifest filename MUST be
# derived the SAME way as the rest of /cchores (ABS-043,
# chore-run-{branch_slug}.json) — via lib.sh branch_slug() (6-char md5 suffix),
# NOT a hand-rolled '/'->'-' slug. This is the single point of manifest-path
# derivation for the writer; hooks/sensitive-file-guard.sh derives the same way
# (a structural test asserts writer/hook agree with branch_slug()).
# ---------------------------------------------------------------------------
_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$_SCRIPT_DIR/lib.sh" ]; then
  # shellcheck source=/dev/null
  . "$_SCRIPT_DIR/lib.sh"
fi

# ---------------------------------------------------------------------------
# Resolve the repo root of the working tree we are operating on. Guarded so a
# non-repo cwd yields a clean failure, never a stray 128.
# ---------------------------------------------------------------------------
_repo_root() {
  git -C . rev-parse --show-toplevel 2>/dev/null || true
}

_current_branch() {
  git -C . rev-parse --abbrev-ref HEAD 2>/dev/null || true
}

# _manifest_path <root> <branch> — the chore-run manifest path, filename derived
# via lib.sh branch_slug() to match ABS-043 (QA-004). Falls back to the legacy
# '/'->'-' slug only if branch_slug() is somehow unavailable (defensive; the
# lib.sh source above should always define it).
_manifest_path() { # $1 root  $2 branch
  local slug
  if declare -f branch_slug >/dev/null 2>&1; then
    slug="$(branch_slug "$2" 2>/dev/null || true)"
  fi
  [ -n "${slug:-}" ] || slug="${2//\//-}"
  printf '%s/.correctless/artifacts/chore-run-%s.json' "$1" "$slug"
}

# ===========================================================================
# write
# ===========================================================================
do_write() {
  local issue="" ; local -a allowed=()
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --issue)
        issue="${2:-}"; shift 2 || { echo "chores-authorize: --issue requires a value" >&2; return 2; } ;;
      --issue=*)
        issue="${1#--issue=}"; shift ;;
      --allowed-paths)
        [ -n "${2:-}" ] || { echo "chores-authorize: --allowed-paths requires a value" >&2; return 2; }
        # Split on commas AND whitespace into individual paths.
        local _ap
        IFS=', ' read -r -a _ap <<< "$2"
        allowed+=( "${_ap[@]}" )
        shift 2 ;;
      --allowed-paths=*)
        local _v="${1#--allowed-paths=}" _ap2
        IFS=', ' read -r -a _ap2 <<< "$_v"
        allowed+=( "${_ap2[@]}" )
        shift ;;
      *)
        echo "chores-authorize: unknown write argument '$1'" >&2; return 2 ;;
    esac
  done

  # INV-001 structural leg (a): refuse without an explicit numeric --issue.
  case "$issue" in
    ''|*[!0-9]*)
      echo "chores-authorize: write refuses — an explicit numeric --issue <N> is required (no marker minted)" >&2
      return 2 ;;
  esac

  local root branch
  root="$(_repo_root)"
  branch="$(_current_branch)"
  if [ -z "$root" ] || [ -z "$branch" ] || [ "$branch" = "HEAD" ]; then
    echo "chores-authorize: write refuses — not on a resolvable chore branch (no marker minted)" >&2
    return 2
  fi

  # INV-001 structural leg (b): the current branch MUST be chore/issue-<N>-*.
  case "$branch" in
    chore/issue-"$issue"-*) : ;;
    *)
      echo "chores-authorize: write refuses — issue $issue does not match current branch '$branch' (expected chore/issue-$issue-*; no marker minted)" >&2
      return 2 ;;
  esac

  command -v jq >/dev/null 2>&1 || { echo "chores-authorize: jq not found" >&2; return 2; }

  mkdir -p "$root/.correctless/artifacts" 2>/dev/null || true

  # Per-run identity (INV-005 / QA-003): ALWAYS mint a FRESH run_id — NEVER reuse
  # a persisted manifest's run_id. Reusing it defeats the staleness backstop: on a
  # deterministic chore/issue-N-slug branch the manifest survives branch
  # delete/reset (it is gitignored), so a leaked marker from run N could match run
  # N+1 if the run_id were inherited (AP-040 capability-honesty). A genuine per-run
  # nonce means a leaked marker is inert AGAINST A LATER /cchores RUN. (Honest
  # scope, MA-011: the run_id nonce does NOT close the crash-window case — a
  # manual/injected edit on the same branch AFTER do_write and BEFORE the next
  # run's do_clear, while marker+manifest still share a run_id, is an ACCEPTED
  # residual; the affordance is a cooperative-loop guardrail, never-merged +
  # human-reviewed.)
  #
  # The manifest filename now matches /cchores's REAL run manifest (ABS-043,
  # chore-run-{branch_slug}.json). To avoid CLOBBERING that manifest's other
  # fields (selected_issue/status/...) written by /cchores's INV-007 first action,
  # the fresh run_id is MERGED in (preserving existing keys), never overwritten.
  local manifest run_id
  manifest="$(_manifest_path "$root" "$branch")"
  run_id="RUN-${issue}-$(date +%s)-$$-${RANDOM}"
  if [ -f "$manifest" ]; then
    local _tmp
    _tmp="$(mktemp "${manifest}.XXXXXX" 2>/dev/null || mktemp 2>/dev/null || true)"
    if [ -n "$_tmp" ] && jq --arg r "$run_id" '. + {run_id:$r}' "$manifest" > "$_tmp" 2>/dev/null; then
      mv "$_tmp" "$manifest" 2>/dev/null \
        || { rm -f "$_tmp" 2>/dev/null || true; echo "chores-authorize: could not update run manifest '$manifest' — check permissions/disk, then re-run /cchores $issue (no marker minted)" >&2; return 2; }
    else
      # MA-008: name the artifact path AND a concrete recovery (the manifest is
      # gitignored, so removing it is safe and re-derivable by the next run).
      rm -f "$_tmp" 2>/dev/null || true
      echo "chores-authorize: existing run manifest '$manifest' is unparsable — remove it (gitignored) and re-run /cchores $issue (refusing, fail-closed; no marker minted)" >&2
      return 2
    fi
  else
    jq -n --arg r "$run_id" '{run_id:$r,schema_version:1}' > "$manifest" 2>/dev/null \
      || { echo "chores-authorize: could not write run manifest '$manifest' — check permissions/disk, then re-run /cchores $issue (no marker minted)" >&2; return 2; }
  fi

  # Build the allowed_paths JSON array (may be empty).
  local ap_json="[]"
  if [ "${#allowed[@]}" -gt 0 ]; then
    ap_json="$(printf '%s\n' "${allowed[@]}" | jq -R . | jq -s 'map(select(length>0))')" || ap_json="[]"
  fi

  local now marker
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  marker="$root/$MARKER_REL"
  jq -n --arg b "$branch" --argjson i "$issue" --arg r "$run_id" \
        --argjson ap "$ap_json" --arg at "$now" \
    '{branch:$b,issue:$i,run_id:$r,allowed_paths:$ap,authorized_at:$at}' \
    > "$marker" 2>/dev/null \
    || { echo "chores-authorize: could not write marker '$marker' — check permissions/disk, then re-run /cchores $issue (no marker minted)" >&2; return 2; }

  echo "chores-authorize: authorized issue $issue on $branch (run_id=$run_id, ${#allowed[@]} path(s))"
  return 0
}

# ===========================================================================
# clear (idempotent) — remove the marker AND rotate the run_id out of the run
# manifest (QA-003). Rotating (deleting only the .run_id field, preserving any
# /cchores INV-007 fields) at run start guarantees a leaked marker's run_id from a
# prior run on the SAME deterministic branch name cannot be inherited by a later
# run: the next do_write mints a fresh run_id, and until it does the manifest has
# no run_id for a stale marker to match. We rotate rather than delete the whole
# file so /cchores's real run manifest (selected_issue/status/...) survives.
# ===========================================================================
do_clear() {
  local root marker branch manifest
  root="$(_repo_root)"
  branch="$(_current_branch)"
  if [ -n "$root" ]; then
    marker="$root/$MARKER_REL"
  else
    marker="$MARKER_REL"
  fi
  rm -f "$marker" 2>/dev/null || true

  # Rotate the run_id out of the manifest (best-effort, never fatal).
  if [ -n "$root" ] && [ -n "$branch" ] && [ "$branch" != "HEAD" ] \
     && command -v jq >/dev/null 2>&1; then
    manifest="$(_manifest_path "$root" "$branch")"
    if [ -f "$manifest" ]; then
      local _tmp
      _tmp="$(mktemp "${manifest}.XXXXXX" 2>/dev/null || mktemp 2>/dev/null || true)"
      if [ -n "$_tmp" ] && jq 'del(.run_id)' "$manifest" > "$_tmp" 2>/dev/null; then
        mv "$_tmp" "$manifest" 2>/dev/null || rm -f "$_tmp" 2>/dev/null || true
      else
        rm -f "$_tmp" 2>/dev/null || true
      fi
    fi
  fi
  return 0
}

# ===========================================================================
# check — 0 if a marker binds the current branch, else non-zero
# ===========================================================================
do_check() {
  local root branch marker
  root="$(_repo_root)"; branch="$(_current_branch)"
  [ -n "$root" ] && [ -n "$branch" ] || return 1
  marker="$root/$MARKER_REL"
  [ -f "$marker" ] || return 1
  command -v jq >/dev/null 2>&1 || return 1
  local m_branch
  m_branch="$(jq -r '.branch // empty' "$marker" 2>/dev/null || true)"
  [ "$m_branch" = "$branch" ] || return 1
  return 0
}

# ===========================================================================
# check-capability <installed-hook-path> — coded behavioral probe (INV-012).
# Feeds the target hook a known-good marker+branch fixture over a throwaway git
# repo and asserts it ACTUALLY allows an affordance-eligible write. A sentinel-
# less / stubbed / merge-broken hook fails the probe and we degrade to v1 with a
# `bash setup` remediation (composes with check_install_freshness, ABS-022).
# ===========================================================================
do_check_capability() {
  local hook="${1:-}"
  if [ -z "$hook" ] || [ ! -f "$hook" ]; then
    echo "chores-authorize: hook not found at '${hook:-<none>}' — affordance unavailable; run 'bash setup' to install the current hooks/scripts" >&2
    return 3
  fi
  command -v jq >/dev/null 2>&1 || { echo "chores-authorize: jq not found — cannot probe capability" >&2; return 3; }
  command -v git >/dev/null 2>&1 || { echo "chores-authorize: git not found — cannot probe capability" >&2; return 3; }

  local probe
  probe="$(mktemp -d)" || { echo "chores-authorize: cannot create probe dir" >&2; return 3; }
  # shellcheck disable=SC2064
  trap "rm -rf '$probe'" RETURN

  local pbranch="chore/issue-1-capability-probe"
  (
    cd "$probe" || exit 1
    git init -q \
      && git config user.email probe@example.com \
      && git config user.name probe \
      && git checkout -q -b "$pbranch" \
      && mkdir -p scripts .correctless/artifacts \
      && : > scripts/prune-scan.sh \
      && git add -A \
      && git commit -q -m probe
  ) >/dev/null 2>&1 || { echo "chores-authorize: probe git fixture failed — run 'bash setup'" >&2; return 4; }

  local run_id="PROBE-$$-${RANDOM}"
  # Manifest filename derived the SAME way as the hook (branch_slug, QA-004) so
  # the probe's hook read finds it.
  local pslug pmanifest
  if declare -f branch_slug >/dev/null 2>&1; then
    pslug="$(branch_slug "$pbranch" 2>/dev/null || true)"
  fi
  [ -n "${pslug:-}" ] || pslug="${pbranch//\//-}"
  pmanifest="$probe/.correctless/artifacts/chore-run-${pslug}.json"
  jq -n --arg r "$run_id" '{run_id:$r,schema_version:1}' \
    > "$pmanifest" 2>/dev/null
  jq -n --arg b "$pbranch" --argjson i 1 --arg r "$run_id" \
        --argjson ap '["scripts/prune-scan.sh"]' --arg at "1970-01-01T00:00:00Z" \
    '{branch:$b,issue:$i,run_id:$r,allowed_paths:$ap,authorized_at:$at}' \
    > "$probe/$MARKER_REL" 2>/dev/null

  local edit_json ec=0
  edit_json="$(jq -nc '{tool_name:"Edit",tool_input:{file_path:"scripts/prune-scan.sh",old_string:"a",new_string:"b"}}')"
  ( cd "$probe" && printf '%s' "$edit_json" | bash "$hook" >/dev/null 2>&1 ) || ec=$?

  if [ "$ec" -eq 0 ]; then
    return 0
  fi
  echo "chores-authorize: installed hook is not affordance-capable (probe write was BLOCKED, exit $ec) — run 'bash setup' to refresh the installed hooks/scripts" >&2
  return 4
}

# ===========================================================================
# Dispatch
# ===========================================================================
OP="${1:-}"
shift || true
case "$OP" in
  write)             do_write "$@" ;;
  clear)             do_clear "$@" ;;
  check)             do_check "$@" ;;
  check-capability)  do_check_capability "$@" ;;
  "")                echo "chores-authorize: no subcommand (expected write|clear|check|check-capability)" >&2; exit 2 ;;
  *)                 echo "chores-authorize: unknown subcommand '$OP'" >&2; exit 2 ;;
esac
