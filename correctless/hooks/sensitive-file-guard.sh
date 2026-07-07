#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091,SC2016,SC2086,SC2317,SC2254,SC2034
# HOOK_TYPE: PreToolUse
# HOOK_MATCHER: Edit|Write|MultiEdit|NotebookEdit|CreateFile|Bash
# SFG_AFFORDANCE_VERSION: 1
# Correctless — PreToolUse sensitive file protection hook
# Blocks the agent from modifying sensitive files (.env, credentials, keys, etc.)
# Independent of workflow state — no overrides.
#
# One narrow, mode-gated conditional-allow exception exists (cchores-protected
# -affordance, PRH-003 v2 / ABS-049): an Edit/Write to an `# affordance`-tagged
# DEFAULTS path is allowed ONLY when a branch- AND file-scoped authorization
# marker binds the current chore branch AND names the specific path. Every
# failure/ambiguity path stays exit-2 (fail-closed, PAT-001 clause 5). The
# `# secret-floor` class is NEVER reachable via a naive Edit/Write, regardless
# of marker/branch/mode.
#
# Called by Claude Code as a PreToolUse hook. Receives tool info on stdin as JSON:
#   { "tool_name": "Edit", "tool_input": { "file_path": "...", ... } }
#
# Scope (sfg-edit-write-only, 2026-06): this hook guards the Edit/Write
# tool-path ONLY. It matches tool_input.file_path for
# Edit/Write/MultiEdit/NotebookEdit/CreateFile against the protected-pattern
# list. Bash commands are NEVER inspected and NEVER blocked — Bash-mediated
# writes (redirects, writer commands, interpreters, Git) are ALL accepted
# non-goals (the prior Bash write-target extraction path was removed). See
# ABS-045 + AP-040 + PMB-020.
#
# Exit codes:
#   0 — allow the operation (no match, OR an authorized affordance write)
#   2 — block the operation (message printed to stderr)
# SC2254 disabled: unquoted $pat in case is intentional — we need glob matching

# ============================================
# DEFAULTS: hardcoded default patterns (INV-004) with a single-source 3-way
# classification tag on EVERY line (INV-008): `# affordance` | `# secret-floor`
# | `# other-floor`. is_secret_floor()/is_affordance_eligible() DERIVE from
# these tags (never a second enumeration, RS-012). Deny-by-default: only an
# explicit `# affordance` line is writable under an authorization marker;
# everything else (secret-floor, other-floor, untagged, custom_patterns) is
# floor → BLOCKED. Conservative eligible set = non-security infra ONLY.
# Parse anchor: ^DEFAULTS=" ... ^"$ (AP-032 parse-anchor pinning).
# ============================================

DEFAULTS=".env # secret-floor
.env.* # secret-floor
*.pem # secret-floor
*.key # secret-floor
*.p12 # secret-floor
*.pfx # secret-floor
credentials.json # secret-floor
credentials.yml # secret-floor
service-account*.json # secret-floor
*.secret # secret-floor
*.secrets # secret-floor
secrets.yml # secret-floor
secrets.yaml # secret-floor
secrets.json # secret-floor
.secrets # secret-floor
id_rsa # secret-floor
id_rsa.* # secret-floor
id_ed25519 # secret-floor
id_ed25519.* # secret-floor
*.keystore # secret-floor
*.jks # secret-floor
.correctless/preferences.md # other-floor
.correctless/config/auto-policy.json # other-floor
.correctless/artifacts/intent-*.md # other-floor
.correctless/artifacts/workflow-state-*.json # other-floor
.correctless/artifacts/decision-record-*.md # other-floor
.correctless/artifacts/autonomous-decisions-*.jsonl # other-floor
.correctless/artifacts/chores-protected-authorized.json # other-floor
.correctless/meta/harness-fingerprint.json # other-floor
.correctless/meta/model-baselines.json # other-floor
.correctless/meta/prune-pattern-baseline.json # other-floor
scripts/harness-fingerprint.sh # affordance
.correctless/scripts/harness-fingerprint.sh # affordance
harness-fingerprint.sh # affordance
scripts/audit-record.sh # other-floor
.correctless/scripts/audit-record.sh # other-floor
audit-record.sh # other-floor
scripts/autonomous-decision-writer.sh # other-floor
.correctless/scripts/autonomous-decision-writer.sh # other-floor
autonomous-decision-writer.sh # other-floor
scripts/prune-scan.sh # affordance
.correctless/scripts/prune-scan.sh # affordance
prune-scan.sh # affordance
scripts/external-review-run.sh # other-floor
.correctless/scripts/external-review-run.sh # other-floor
external-review-run.sh # other-floor
scripts/config-update.sh # other-floor
.correctless/scripts/config-update.sh # other-floor
config-update.sh # other-floor
scripts/meta-record.sh # other-floor
.correctless/scripts/meta-record.sh # other-floor
meta-record.sh # other-floor
scripts/chores-authorize.sh # other-floor
.correctless/scripts/chores-authorize.sh # other-floor
chores-authorize.sh # other-floor
.correctless/ARCHITECTURE_DEPRECATED.md # other-floor
.correctless/antipatterns-archived.md # other-floor
.correctless/CLAUDE_LEARNINGS_ARCHIVED.md # other-floor
scripts/wf/transitions.sh # other-floor
scripts/wf/utility.sh # other-floor
scripts/wf/metadata.sh # other-floor
.correctless/scripts/wf/transitions.sh # other-floor
.correctless/scripts/wf/utility.sh # other-floor
.correctless/scripts/wf/metadata.sh # other-floor
scripts/lib.sh # other-floor (SFG trust dep; installed mirror .correctless/scripts/lib.sh)
.correctless/scripts/lib.sh # other-floor
.correctless/config/workflow-config.json # other-floor
scripts/override-scrutiny.sh # other-floor
.correctless/scripts/override-scrutiny.sh # other-floor
scripts/review-triage.sh # other-floor
.correctless/scripts/review-triage.sh # other-floor
scripts/supervisor-mandate.sh # other-floor
.correctless/scripts/supervisor-mandate.sh # other-floor
scripts/intent-hash.sh # other-floor
.correctless/scripts/intent-hash.sh # other-floor
.correctless/meta/intensity-calibration.json # other-floor
.correctless/meta/pat001-measurement-due.json # other-floor
.correctless/.sfg-lift-active # other-floor
agents/fix-diff-reviewer.md # other-floor
agents/supervisor.md # other-floor
agents/decision-agent.md # other-floor
agents/ctdd-red.md # other-floor
agents/ctdd-green.md # other-floor
"

# ============================================
# SINGLE SOURCE OF TRUTH (QA-001): the tagged DEFAULTS block above is the ONLY
# definition of the protected-path set. An earlier untagged, hand-synced mirror
# variable (a partial copy of the DEFAULTS lines, kept only to satisfy sibling
# suites' whole-line/end-anchored matchers) was DELETED — it reintroduced the
# AP-005 drift class (a second source that could silently drift from DEFAULTS →
# silent unprotection). The three sibling suites that used to match that mirror
# (tests/test-meta-record.sh, test-sensitive-file-guard.sh,
# test-fix-diff-reviewer-agent.sh) now strip the trailing ` # tag` before matching
# so they validate against this authoritative tagged block directly.
# ============================================
# Side-effect-free classification helpers (R2-J). These are defined at the top
# level so a consumer (scripts/cchores-diff-check.sh) can `source` this hook to
# reuse is_secret_floor()/is_affordance_eligible() WITHOUT executing the policy
# body (the main-guard at the bottom is a no-op when sourced). They depend on
# canonicalize_path (PAT-017) being available in the sourcing context.
# ============================================

# Strip the inline classification tag from a DEFAULTS line, yielding the raw
# pattern (everything before the first `#`, right-trimmed).
_sfg_strip_tag() {
  local pat="${1%%#*}"
  pat="${pat%"${pat##*[![:space:]]}"}"
  printf '%s' "$pat"
}

# Match a canonical-form (already lowercased) pattern against a canonical-form
# lowercased target. Mirrors _check_file_against_patterns' matcher (RS-014).
_sfg_pattern_match() {
  local pat="$1" filepath_lower="$2" basename_lower="$3"
  case "$pat" in
    */*)
      case "$filepath_lower" in
        $pat|*/$pat) return 0 ;;
      esac
      ;;
    *)
      case "$basename_lower" in
        $pat) return 0 ;;
      esac
      ;;
  esac
  return 1
}

# _sfg_custom_match <canonical_target> — true iff the canonical target matches a
# user `custom_patterns` entry (canonical, lowercased CANONICAL_CUSTOM_PATTERNS,
# built by _sfg_main). Used by STEP 9 so a `custom_patterns` match FORCES the
# floor over the affordance tag (INV-002 clause (1) / INV-008 deny-by-default,
# QA-006): the user's explicit re-protection WINS, even for an `# affordance`
# -tagged path. CANONICAL_CUSTOM_PATTERNS is visible here via bash dynamic scope.
_sfg_custom_match() {
  local tl="${1,,}" bl cp
  bl="${tl##*/}"
  while IFS= read -r cp; do
    [ -z "$cp" ] && continue
    if _sfg_pattern_match "$cp" "$tl" "$bl"; then
      return 0
    fi
  done <<< "${CANONICAL_CUSTOM_PATTERNS:-}"
  return 1
}

# Classify a target against the DEFAULTS block. Emits the matching line's tag
# (affordance | secret-floor | other-floor | untagged) and returns 0, or returns
# 1 with no output when the target matches no DEFAULTS line. Input is treated as
# a raw path (it is canonicalized+lowercased here).
_sfg_classify_target() {
  local LC_ALL=C
  canonicalize_path "$1" >/dev/null 2>&1
  local tlower="${_CANONICAL_RESULT,,}"
  local base="${tlower##*/}"
  local line tag pat clower
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    case "$line" in
      *"# affordance"*)   tag="affordance" ;;
      *"# secret-floor"*) tag="secret-floor" ;;
      *"# other-floor"*)  tag="other-floor" ;;
      *)                  tag="untagged" ;;
    esac
    pat="$(_sfg_strip_tag "$line")"
    [ -z "$pat" ] && continue
    canonicalize_path "$pat" >/dev/null 2>&1
    clower="${_CANONICAL_RESULT,,}"
    if _sfg_pattern_match "$clower" "$tlower" "$base"; then
      printf '%s' "$tag"
      return 0
    fi
  done <<< "$DEFAULTS"
  return 1
}

# is_secret_floor <path> — true iff the target matches a `# secret-floor` line.
is_secret_floor() {
  [ "$(_sfg_classify_target "$1" 2>/dev/null || true)" = "secret-floor" ]
}

# is_affordance_eligible <path> — true iff the target matches an `# affordance` line.
is_affordance_eligible() {
  [ "$(_sfg_classify_target "$1" 2>/dev/null || true)" = "affordance" ]
}

# ============================================
# Match each file target against patterns (INV-007, INV-008)
# ============================================
_check_file_against_patterns() {
  # Pre-condition: argument is already a canonical-form path (output of
  # canonicalize_path). Matched against CANONICAL_PATTERNS only. PRH-004.
  local filepath="$1"
  local filepath_lower="${filepath,,}"
  local basename_lower="${filepath_lower##*/}"

  if [ -z "$basename_lower" ]; then
    return 1
  fi

  while IFS= read -r pat; do
    [ -z "$pat" ] && continue
    case "$pat" in
      */*)
        case "$filepath_lower" in
          $pat|*/$pat) echo "$pat"; return 0 ;;
        esac
        ;;
      *)
        case "$basename_lower" in
          $pat) echo "$pat"; return 0 ;;
        esac
        ;;
    esac
  done <<< "$CANONICAL_PATTERNS"

  return 1
}

# ============================================
# _sfg_marker_binds_branch <canonical_target> — true iff an authorization marker
# exists in the target's own worktree AND its `.branch` equals that worktree's
# current branch (i.e. an autonomous /cchores run is active on this branch). Used
# by STEP 9 to pick the correct block-message register (MA-005/MA-002): with a
# marker present, a protected-but-not-affordance target gets an autonomous-mode
# "defer to human review" message (never the human lift-and-restore / outside-CC
# wall). FAIL-SAFE: any ambiguity → return 1 ("no marker") so a human developer
# still sees the lift-and-restore signpost. All git/jq reads guarded; returns
# only 0/1, never a stray 128 (PAT-001 clause 5).
# ============================================
_sfg_marker_binds_branch() {
  local canonical_target="$1" tdir toplevel branch marker m_branch
  tdir="$(dirname "$canonical_target")"
  toplevel="$(git -C "$tdir" rev-parse --show-toplevel 2>/dev/null || true)"
  branch="$(git -C "$tdir" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  [ -n "$toplevel" ] && [ -n "$branch" ] && [ "$branch" != "HEAD" ] || return 1
  marker="$toplevel/.correctless/artifacts/chores-protected-authorized.json"
  [ -f "$marker" ] || return 1
  command -v jq >/dev/null 2>&1 || return 1
  m_branch="$(jq -r '.branch // empty' "$marker" 2>/dev/null || true)"
  [ -n "$m_branch" ] && [ "$m_branch" = "$branch" ]
}

# ============================================
# Affordance allowlist (INV-002/003/005/011/013): decide whether an
# `# affordance`-eligible protected target may be written under the branch- and
# file-scoped authorization marker. Returns 0 (allow) or 1 (block); on block it
# sets _SFG_BLOCK_MSG to an affordance-aware, /cchores-pointing message (NOT the
# generic lift-and-restore wall — INV-013). Every git/jq read is guarded so the
# hook exits only 0 or 2, never 128/1 (PAT-001 clause 5 / INV-011).
# ============================================
_SFG_BLOCK_MSG=""
_sfg_affordance_allows() {
  local canonical_target="$1"
  _SFG_BLOCK_MSG=""
  local tdir toplevel branch marker slug manifest

  # Resolve the target's OWN worktree (never the hook cwd — R2-I / AP-035).
  tdir="$(dirname "$canonical_target")"
  toplevel="$(git -C "$tdir" rev-parse --show-toplevel 2>/dev/null || true)"
  branch="$(git -C "$tdir" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  if [ -z "$toplevel" ] || [ -z "$branch" ] || [ "$branch" = "HEAD" ]; then
    # MA-002: NO marker/branch — this path is reachable by TWO legitimate
    # workflows (a human developer editing the deliverable, and an autonomous
    # /cchores run). The remediation must be ADDITIVE, not replace the AP-037
    # lift-and-restore signpost with a /cchores-only hint.
    _SFG_BLOCK_MSG="BLOCKED [sensitive-file]: affordance target '$canonical_target' — not on a resolvable chore/issue-<N>-* branch, so there is no authorization for this write.
  If you are a developer editing this deliverable directly, use the sanctioned lift-and-restore procedure in .claude/rules/sfg-deliverable.md.
  If this is an autonomous chore, re-run /cchores <N> on the chore branch."
    return 1
  fi

  marker="$toplevel/.correctless/artifacts/chores-protected-authorized.json"
  if [ ! -f "$marker" ]; then
    # MA-002: NO marker present — additive remediation (lift-and-restore signpost
    # for a human dev AND the /cchores hint for an autonomous chore).
    _SFG_BLOCK_MSG="BLOCKED [sensitive-file]: affordance target '$canonical_target' — no authorization marker for this run.
  If you are a developer editing this deliverable directly, use the sanctioned lift-and-restore procedure in .claude/rules/sfg-deliverable.md.
  If this is an autonomous chore, re-run /cchores <N> on the chore branch so the marker is minted."
    return 1
  fi

  local m_branch m_issue m_runid ap_ok
  m_branch="$(jq -r '.branch // empty' "$marker" 2>/dev/null || true)"
  m_issue="$(jq -r '.issue // empty' "$marker" 2>/dev/null || true)"
  m_runid="$(jq -r '.run_id // empty' "$marker" 2>/dev/null || true)"
  ap_ok="$(jq -e 'has("allowed_paths") and (.allowed_paths|type=="array")' "$marker" >/dev/null 2>&1 && printf 'yes' || true)"
  if [ -z "$m_branch" ] || [ -z "$m_issue" ] || [ -z "$m_runid" ] || [ "$ap_ok" != "yes" ]; then
    _SFG_BLOCK_MSG="BLOCKED [sensitive-file]: the affordance authorization marker is malformed or missing required fields — authorization refused. Re-run /cchores <N> on the chore branch."
    return 1
  fi

  case "$m_issue" in
    ''|*[!0-9]*)
      _SFG_BLOCK_MSG="BLOCKED [sensitive-file]: affordance marker issue is not numeric — authorization refused. Re-run /cchores <N>."
      return 1
      ;;
  esac

  if [ "$m_branch" != "$branch" ]; then
    _SFG_BLOCK_MSG="BLOCKED [sensitive-file]: affordance authorization marker.branch=$m_branch does not match current=$branch — this authorization is scoped to another branch. Re-run /cchores <N> on the chore branch."
    return 1
  fi

  case "$branch" in
    chore/issue-"$m_issue"-*) : ;;
    *)
      _SFG_BLOCK_MSG="BLOCKED [sensitive-file]: current branch name is not chore/issue-$m_issue-* — affordance authorization refused. Re-run /cchores <N>."
      return 1
      ;;
  esac

  # Manifest filename derived via lib.sh branch_slug() (QA-004) so it matches
  # /cchores's REAL run manifest (ABS-043, chore-run-{branch_slug}.json) and the
  # writer (scripts/chores-authorize.sh). branch_slug() is sourced from lib.sh in
  # STEP 4; fall back to the legacy '/'->'-' slug only if it is unavailable.
  if declare -f branch_slug >/dev/null 2>&1; then
    slug="$(branch_slug "$branch" 2>/dev/null || true)"
  fi
  [ -n "${slug:-}" ] || slug="${branch//\//-}"
  manifest="$toplevel/.correctless/artifacts/chore-run-${slug}.json"
  if [ ! -f "$manifest" ]; then
    _SFG_BLOCK_MSG="BLOCKED [sensitive-file]: affordance run manifest missing — authorization refused (stale/partial run). Re-run /cchores <N>."
    return 1
  fi
  local man_runid
  man_runid="$(jq -r '.run_id // empty' "$manifest" 2>/dev/null || true)"
  if [ -z "$man_runid" ] || [ "$man_runid" != "$m_runid" ]; then
    _SFG_BLOCK_MSG="BLOCKED [sensitive-file]: affordance marker run_id mismatch (stale/leaked authorization) — authorization refused. Re-run /cchores <N>."
    return 1
  fi

  # allowed_paths membership (RS-007): canonical target ∈ marker.allowed_paths.
  local ap capath found=1
  while IFS= read -r ap; do
    [ -z "$ap" ] && continue
    canonicalize_path "$ap" >/dev/null 2>&1
    capath="$_CANONICAL_RESULT"
    if [ "$capath" = "$canonical_target" ]; then
      found=0
      break
    fi
  done < <(jq -r '.allowed_paths[]? // empty' "$marker" 2>/dev/null || true)
  if [ "$found" -ne 0 ]; then
    # MA-007: /cchores accepts ONLY an issue number (PRH-003) — the human cannot
    # "name this path". Reword to an actionable, achievable remediation; keep the
    # /cchores <N> reference (INV-013-c) but never instruct passing a path.
    _SFG_BLOCK_MSG="BLOCKED [sensitive-file]: affordance target '$canonical_target' is not in this run's authorized scope (marker.allowed_paths) — the fix strayed outside the authorized scope for issue $m_issue. This run aborts and defers to human review. (/cchores <N> authorizes only the scoped paths for issue <N>.)"
    return 1
  fi

  return 0
}

# ============================================
# Policy body — runs ONLY when the hook is executed (main-guard at the bottom),
# never when the hook is sourced for its classification helpers (R2-J).
# ============================================
_sfg_main() {
  set -euo pipefail
  # Disable glob expansion — patterns like *.pem must not expand to filenames.
  set -f
  # Byte-oriented, locale-independent matching (PAT-017 / LC_ALL=C at hook scope).
  LC_ALL=C

  # STEP 1: Check jq availability (EA-004)
  command -v jq >/dev/null 2>&1 || { echo "BLOCKED [sensitive-file]: jq not found" >&2; exit 2; }

  # STEP 2: Parse stdin JSON (single jq bulk call)
  local INPUT
  INPUT="$(cat)"
  TOOL_NAME="" TOOL_INPUT_FILE="" TOOL_INPUT_EDITS=""
  local _PARSED
  _PARSED="$(echo "$INPUT" | jq -r '
    if (.tool_name | type) != "string" then error("non-string tool_name")
    else
      @sh "TOOL_NAME=\(.tool_name)",
      @sh "TOOL_INPUT_FILE=\(.tool_input.file_path | if type == "string" then . else "" end)",
      @sh "TOOL_INPUT_EDITS=\([.tool_input.edits[]?.file_path | select(type == "string")] | join("\n"))"
    end
  ' 2>/dev/null)" || true
  # Fail-closed: if jq produced no output (parse failure), block the operation.
  if [ -z "$_PARSED" ]; then
    echo "BLOCKED [fail-closed]: failed to parse tool input JSON" >&2
    exit 2
  fi
  eval "$_PARSED"

  # STEP 3: Fast-path bail (INV-001, INV-010)
  # Bash is never inspected — exit 0 immediately, BEFORE sourcing lib.sh or
  # reading config. Read/Grep/Glob and every other non-write tool also exit 0.
  case "$TOOL_NAME" in
    Edit|Write|MultiEdit|NotebookEdit|CreateFile) ;;
    Bash) exit 0 ;;
    *) exit 0 ;;
  esac

  # STEP 4: Source shared library (for canonicalize_path + config_file)
  _source_lib_sh || true

  # STEP 4a: canonicalize_path v1 sentinel probe (INV-005a) via the SHARED
  # require_canonicalize_or_die helper (MA-001), so the guard travels with the
  # helper and the exact same probe gates both the hook and cchores-diff-check.sh.
  # Inline fallback: if lib.sh failed to source entirely, require_canonicalize_or_die
  # is itself undefined — canonicalize_path is then also undefined, so fail closed.
  if declare -f require_canonicalize_or_die >/dev/null 2>&1; then
    require_canonicalize_or_die "sensitive-file" || exit 2
  elif ! declare -f canonicalize_path >/dev/null 2>&1 \
     || [ "$(canonicalize_path '__canonicalize_path_v1_probe__/foo' 2>/dev/null || true)" != "__canonicalize_path_v1_probe__/foo" ]; then
    echo "BLOCKED [sensitive-file]: canonicalize_path missing or version mismatch — re-run 'bash setup' to refresh installed scripts" >&2
    exit 2
  fi

  # STEP 5: Collect file targets to check
  local FILE_TARGETS
  FILE_TARGETS="$(collect_targets)"
  if [ -z "$FILE_TARGETS" ]; then
    exit 0
  fi

  # STEP 6: Build the runtime pattern list from DEFAULTS (tags stripped, INV-008
  # single source) plus custom_patterns from config (INV-005).
  local DEFAULTS_PATTERNS="" _dl _dp
  while IFS= read -r _dl; do
    [ -z "$_dl" ] && continue
    _dp="$(_sfg_strip_tag "$_dl")"
    [ -n "$_dp" ] && DEFAULTS_PATTERNS+="$_dp"$'\n'
  done <<< "$DEFAULTS"

  # STEP 7: Read custom patterns from config (INV-005) — degrade to DEFAULTS-only
  # on an unparsable config (documented narrow exception, hooks-pretooluse.md).
  # MA-006: additionally RECORD whether the config was PRESENT but its
  # custom_patterns could not be parsed. The DEFAULTS-only degrade is fine for the
  # deny-list (a corrupt config only loses the user's EXTRA protections), but on
  # the affordance ALLOW branch (STEP 9) that same degrade would silently convert a
  # user's explicit re-protection (custom_patterns) from a BLOCK into an ALLOW. The
  # affordance branch consults this flag and fails CLOSED; the deny-list behavior is
  # unchanged (config-absent stays a clean DEFAULTS-only path, flag = 0).
  #
  # MA-012 (class fix): a config-degrade flag that gates a security ALLOW must
  # validate the TYPE/SHAPE of the CONSUMED value, not merely the parse success of
  # the surrounding document. A well-formed config whose custom_patterns is the
  # WRONG TYPE (string/object/number/boolean) exits the extraction filter with 0
  # and empty output — so the parse-success-only check below would leave the flag
  # at 0 and let a user's (malformed) re-protection silently lapse into an ALLOW on
  # the affordance branch. Guard the TYPE first: absent/null → flag stays 0
  # (no custom_patterns expected — affordance may proceed); array → flag 0, process
  # normally; anything else present-but-not-an-array → flag 1 → affordance ALLOW
  # fails closed exactly like the unparsable-config case. Deny-list behavior is
  # unaffected (the flag is consulted ONLY on the affordance ALLOW branch).
  local CUSTOM_PATTERNS="" CONFIG_FILE _SFG_CUSTOM_READ_FAILED=0
  CONFIG_FILE="$(config_file 2>/dev/null)" || CONFIG_FILE=".correctless/config/workflow-config.json"
  if [ -f "$CONFIG_FILE" ]; then
    if ! jq -e '(.protected_files.custom_patterns == null) or (.protected_files.custom_patterns | type == "array")' "$CONFIG_FILE" >/dev/null 2>&1; then
      # Present-but-not-an-array (type confusion) OR unparsable JSON → fail closed
      # on the affordance branch; the extraction below is skipped.
      CUSTOM_PATTERNS=""
      _SFG_CUSTOM_READ_FAILED=1
    elif ! CUSTOM_PATTERNS="$(jq -r '.protected_files.custom_patterns // [] | if type == "array" then .[] else empty end' "$CONFIG_FILE" 2>/dev/null)"; then
      CUSTOM_PATTERNS=""
      _SFG_CUSTOM_READ_FAILED=1
    fi
  fi

  local ALL_PATTERNS="$DEFAULTS_PATTERNS"
  if [ -n "$CUSTOM_PATTERNS" ]; then
    ALL_PATTERNS="$ALL_PATTERNS
$CUSTOM_PATTERNS"
  fi
  ALL_PATTERNS="${ALL_PATTERNS,,}"

  # Canonicalize every pattern once (canonical forms on both sides, PRH-004).
  local _canonical_arr=() pat
  while IFS= read -r pat; do
    [ -n "$pat" ] && { canonicalize_path "$pat" >/dev/null; _canonical_arr+=( "$_CANONICAL_RESULT" ); }
  done <<< "$ALL_PATTERNS"
  local _IFS_save="${IFS-}"; IFS=$'\n'
  CANONICAL_PATTERNS="${_canonical_arr[*]}"
  IFS="$_IFS_save"

  # STEP 8a (QA-006 / INV-002 clause 1): canonicalize the user custom_patterns
  # SEPARATELY so STEP 9 can detect an `# affordance`/custom_patterns OVERLAP. A
  # target that matches BOTH an affordance DEFAULTS pattern AND a custom_patterns
  # entry must be forced to the floor (BLOCKED) — the user's explicit
  # re-protection WINS over the affordance tag (INV-008 deny-by-default).
  local _canon_custom_arr=() _cp
  while IFS= read -r _cp; do
    [ -z "$_cp" ] && continue
    canonicalize_path "${_cp,,}" >/dev/null; _canon_custom_arr+=( "$_CANONICAL_RESULT" )
  done <<< "${CUSTOM_PATTERNS,,}"
  local _IFS_save_c="${IFS-}"; IFS=$'\n'
  CANONICAL_CUSTOM_PATTERNS="${_canon_custom_arr[*]}"
  IFS="$_IFS_save_c"

  # STEP 9: Check each file target (INV-002/003/008, BND-004)
  local target canonical_target matched_pattern tag
  while IFS= read -r target; do
    [ -z "$target" ] && continue

    canonicalize_path "$target" >/dev/null
    canonical_target="$_CANONICAL_RESULT"

    matched_pattern=""
    matched_pattern="$(_check_file_against_patterns "$canonical_target")" || true
    [ -z "$matched_pattern" ] && continue

    # Protected. Classify against the DEFAULTS tags (custom_patterns → no tag).
    tag="$(_sfg_classify_target "$canonical_target" 2>/dev/null || true)"

    # Secret-class hard floor is evaluated FIRST (deny-first, INV-003): never
    # reachable via a naive Edit/Write regardless of marker/branch/mode.
    if [ "$tag" = "secret-floor" ]; then
      if _sfg_marker_binds_branch "$canonical_target"; then
        # MA-005: an autonomous /cchores run is active on this branch. Secret-floor
        # is never affordance-eligible; emit an autonomous-mode-correct message
        # (defer to human review), NOT the human lift-and-restore / outside-CC wall.
        echo "BLOCKED [sensitive-file]: this Edit/Write tool target '$target' matches protected pattern '$matched_pattern' (secret-floor — never affordance-eligible under this run's authorization). This chore cannot fix it autonomously; the run will abort (INV-007) and defer to human review." >&2
      else
        echo "BLOCKED [sensitive-file]: this Edit/Write tool target '$target' matches protected pattern '$matched_pattern' (secret-floor — never affordance-eligible).
  SFG is a write-target guardrail — it catches accidental/naive Edit/Write writes to protected files. If this is a genuine, intended edit to a deliverable, use the sanctioned lift-and-restore procedure in .claude/rules/sfg-deliverable.md. Otherwise, make the write outside Claude Code." >&2
      fi
      exit 2
    fi

    # Affordance-eligible: consult the branch+file-scoped allowlist (INV-002).
    if [ "$tag" = "affordance" ]; then
      # MA-006: fail CLOSED when the config was PRESENT but its custom_patterns
      # could not be parsed. On the deny-list a corrupt config only loses the
      # user's EXTRA protections (documented narrow degrade); but on THIS ALLOW
      # branch the same degrade would convert a user's explicit re-protection of an
      # affordance path from a BLOCK into an ALLOW. A config-gated ALLOW must fail
      # closed independently of the deny-list degrade. (config ABSENT → flag 0 →
      # unaffected: no custom_patterns are expected, so the affordance may proceed.)
      if [ "${_SFG_CUSTOM_READ_FAILED:-0}" -eq 1 ]; then
        echo "BLOCKED [sensitive-file]: this Edit/Write tool target '$target' is affordance-eligible, but workflow-config.json is present and its protected_files.custom_patterns could not be parsed — refusing the affordance grant (fail-closed) so a user's re-protection cannot silently lapse into an allow. Fix or remove the corrupt config, then re-run /cchores <N>." >&2
        exit 2
      fi
      # INV-002 clause (1) / INV-008 (QA-006): a target that ALSO matches a user
      # custom_patterns entry is forced to the floor — the user's explicit
      # re-protection WINS over the affordance tag → BLOCK, regardless of a valid
      # marker. Evaluated BEFORE the allowlist so no marker can unlock it.
      if _sfg_custom_match "$canonical_target"; then
        echo "BLOCKED [sensitive-file]: this Edit/Write tool target '$target' matches protected pattern '$matched_pattern' AND a user custom_patterns entry — the custom_patterns re-protection forces the floor over the affordance tag (the affordance never relaxes a custom_patterns match).
  SFG is a write-target guardrail — it catches accidental/naive Edit/Write writes to protected files. If this is a genuine, intended edit to a deliverable, use the sanctioned lift-and-restore procedure in .claude/rules/sfg-deliverable.md. Otherwise, make the write outside Claude Code." >&2
        exit 2
      fi
      if _sfg_affordance_allows "$canonical_target"; then
        continue
      fi
      echo "$_SFG_BLOCK_MSG" >&2
      exit 2
    fi

    # other-floor / untagged / custom_patterns → floor, BLOCK (deny-by-default).
    if _sfg_marker_binds_branch "$canonical_target"; then
      # MA-005: an autonomous /cchores run is active on this branch, but this path
      # is protected-but-NOT-affordance-eligible. Emit an autonomous-mode-correct
      # message (defer to human review), never the lift-and-restore / outside-CC
      # wall (both inapplicable in an autonomous run).
      echo "BLOCKED [sensitive-file]: this Edit/Write tool target '$target' matches protected pattern '$matched_pattern' — this path is protected but NOT affordance-eligible under this run's authorization, so this chore cannot fix it autonomously; the run will abort (INV-007) and defer to human review." >&2
    else
      echo "BLOCKED [sensitive-file]: this Edit/Write tool target '$target' matches protected pattern '$matched_pattern'.
  SFG is a write-target guardrail — it catches accidental/naive Edit/Write writes to protected files. If this is a genuine, intended edit to a deliverable, use the sanctioned lift-and-restore procedure in .claude/rules/sfg-deliverable.md. Otherwise, make the write outside Claude Code." >&2
    fi
    exit 2
  done <<< "$FILE_TARGETS"

  # STEP 10: No match — allow (INV-006)
  exit 0
}

# ============================================
# STEP 5 helper: collect file targets to check (defined top-level so _sfg_main
# and any future sourcing consumer share it).
# ============================================
collect_targets() {
  case "$TOOL_NAME" in
    Edit|Write|CreateFile|NotebookEdit)
      if [ -n "$TOOL_INPUT_FILE" ]; then
        echo "$TOOL_INPUT_FILE"
      fi
      ;;
    MultiEdit)
      if [ -n "$TOOL_INPUT_EDITS" ]; then
        echo "$TOOL_INPUT_EDITS"
      fi
      if [ -n "$TOOL_INPUT_FILE" ]; then
        echo "$TOOL_INPUT_FILE"
      fi
      ;;
  esac
}

# ============================================
# STEP 4 helper: source shared library (canonicalize_path + config_file).
# ============================================
_source_lib_sh() {
  local _LIB_DIR
  _LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" 2>/dev/null && pwd || true)"
  if [ -n "$_LIB_DIR" ] && [ -f "$_LIB_DIR/lib.sh" ]; then
    # shellcheck source=../scripts/lib.sh
    source "$_LIB_DIR/lib.sh"
  elif [ -f ".correctless/scripts/lib.sh" ]; then
    source ".correctless/scripts/lib.sh"
  else
    return 1
  fi
}

# ============================================
# main-guard (R2-J): run the policy body only when EXECUTED, not when sourced.
# ============================================
if [ "${BASH_SOURCE[0]}" = "${0:-}" ]; then
  _sfg_main
fi
