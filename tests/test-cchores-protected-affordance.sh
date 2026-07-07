#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091,SC2016,SC2086,SC2317
# Correctless — /cchores Protected-File Affordance (PRH-003 v2) test suite
#
# Spec: .correctless/specs/cchores-protected-affordance.md
#
# RED phase: the deltas under test do NOT exist yet. This suite encodes EVERY
# invariant (INV-001..INV-015) and EVERY prohibition (PRH-001..PRH-003) as at
# least one failing assertion. The load-bearing RED assertions are the
# ALLOW-under-marker cells and the new-script/new-flag cells; several BLOCK cells
# are regression guards (they already pass today because everything in DEFAULTS
# is blocked) kept to prevent GREEN over-reach.
#
# Scripts not yet existing (tests fail cleanly on absence, no stubs needed):
#   - scripts/chores-authorize.sh   (write/clear/check/check-capability)
#   - scripts/cchores-diff-check.sh  (--mode + --allowed-paths + stdin)
# Script existing but missing new flags:
#   - scripts/cchores-emit.sh        (--guard-touched / --affordance-paths banner)
#
# AP-031 real-fixture note: the authorization-marker schema
#   {branch, issue, run_id, allowed_paths, authorized_at}
# is a NEW producer+consumer landing in the same PR, so no real committed
# artifact exists yet (it is gitignored under .correctless/artifacts/ anyway,
# .gitignore:42). The AP-031 real-fixture requirement is therefore DORMANT and
# spec format-pinning is the sole guard. INV-015 additionally requires piping the
# REAL `chores-authorize.sh write` output into the hook once the writer ships —
# encoded below (fails cleanly until the writer exists).
#   # Source: .correctless/specs/cchores-protected-affordance.md OQ-001 marker schema
#
# Run from repo root: bash tests/test-cchores-protected-affordance.sh

source "$(dirname "${BASH_SOURCE[0]}")/test-helpers.sh"

# QA-004: source lib.sh for branch_slug() so every fixture derives the run-manifest
# filename the SAME way the REAL producers do — scripts/chores-authorize.sh and
# hooks/sensitive-file-guard.sh both derive chore-run-{branch_slug}.json (ABS-043
# convention, 6-char md5 suffix). A hand-rolled '/'->'-' no-hash convention in the
# test would diverge from the producers (AP-031). chore_run_manifest() is the
# single point of manifest-path derivation for fixtures.
# shellcheck source=/dev/null
[ -f "$REPO_DIR/scripts/lib.sh" ] && . "$REPO_DIR/scripts/lib.sh"

chore_run_manifest() { # $1 repo  $2 branch -> absolute run-manifest path
  printf '%s/.correctless/artifacts/chore-run-%s.json' "$1" "$(branch_slug "$2")"
}

# ============================================================================
# Path constants (all SFG-protected paths are READ/EXECUTED only, never Edited)
# ============================================================================
HOOK="$REPO_DIR/hooks/sensitive-file-guard.sh"
HOOK_MIRROR="$REPO_DIR/correctless/hooks/sensitive-file-guard.sh"
CHORES_AUTH="$REPO_DIR/scripts/chores-authorize.sh"
DIFF_CHECK="$REPO_DIR/scripts/cchores-diff-check.sh"
EMIT="$REPO_DIR/scripts/cchores-emit.sh"
CCHORES_SKILL="$REPO_DIR/skills/cchores/SKILL.md"
CDEBUG_FIX="$REPO_DIR/agents/cdebug-fix.md"
ABSTRACTIONS="$REPO_DIR/docs/architecture/abstractions.md"
PAT001_RULE="$REPO_DIR/.claude/rules/hooks-pretooluse.md"
SFG_DELIVERABLE_RULE="$REPO_DIR/.claude/rules/sfg-deliverable.md"

# The fixed marker path (OQ-001). Under .correctless/artifacts/ (gitignored :42).
MARKER_REL=".correctless/artifacts/chores-protected-authorized.json"

cleanup_dirs=()
register_cleanup() { cleanup_dirs+=("$1"); }
# shellcheck disable=SC2154  # 'd' is the for-loop variable bound inside the single-quoted trap body
trap 'for d in "${cleanup_dirs[@]:-}"; do [ -n "$d" ] && rm -rf "$d"; done' EXIT

# ============================================================================
# Hook-driving helpers (mirror tests/test-sensitive-file-guard.sh conventions).
# run_sfg does NOT cd — callers use a subshell `( cd "$repo"; run_sfg ... )` so
# the hook's target-tree/cwd resolution keys off the fixture repo.
# Output: line 1 = exit code, remaining lines = stderr.
# ============================================================================
run_sfg() {
  local json="$1" ec out
  out="$(printf '%s' "$json" | bash "$HOOK" 2>&1 >/dev/null)" && ec=0 || ec=$?
  printf '%s\n%s' "$ec" "$out"
}
sfg_exit() { printf '%s' "$1" | head -1; }
sfg_err()  { printf '%s' "$1" | tail -n +2; }

edit_json() { # $1 = file path -> Edit tool JSON
  jq -nc --arg p "$1" '{tool_name:"Edit",tool_input:{file_path:$p,old_string:"a",new_string:"b"}}'
}

# ============================================================================
# INV-015 shared helper: setup_git_test_env — a single git-fixture builder used
# by every git-based cell (INV-002/003/005/009/011/012/015) so no test re-rolls
# a divergent fixture (F9). Creates a git repo, a chore/issue-<N>-<slug> branch,
# common source dirs, an initial commit.
#   $1 dir  $2 issue-number  $3 slug-suffix
# Emits the repo path on stdout.
# ============================================================================
setup_git_test_env() {
  local dir="$1" issue="$2" suffix="$3"
  local branch="chore/issue-${issue}-${suffix}"
  mkdir -p "$dir/.correctless/artifacts" "$dir/.correctless/config" \
           "$dir/.correctless/meta" "$dir/scripts" "$dir/hooks" "$dir/agents"
  (
    cd "$dir" \
      && git init -q \
      && git config user.email t@example.com \
      && git config user.name tester \
      && git checkout -q -b "$branch" \
      && : > scripts/.keep \
      && git add -A \
      && git commit -q -m init
  ) >/dev/null 2>&1 || true
  printf '%s' "$dir"
}

# QA-004: the run manifest is placed at chore-run-{branch_slug}.json — filename
# derived via lib.sh branch_slug() (the ABS-043 convention the writer + hook both
# use), NOT a hand-rolled '/'->'-' no-hash slug. chore_run_manifest() is the single
# derivation point. Spec INV-005 pins the run_id source as "the chore-run manifest".
write_marker_and_manifest() { # $1 repo $2 branch $3 issue $4 run_id $5 allowed_paths_json
  local repo="$1" branch="$2" issue="$3" rid="$4" ap="$5"
  jq -n --arg b "$branch" --argjson i "$issue" --arg r "$rid" \
        --argjson ap "$ap" --arg at "2026-07-06T10:00:00Z" \
    '{branch:$b,issue:$i,run_id:$r,allowed_paths:$ap,authorized_at:$at}' \
    > "$repo/$MARKER_REL" 2>/dev/null || true
  jq -n --arg r "$rid" '{run_id:$r,schema_version:1}' \
    > "$(chore_run_manifest "$repo" "$branch")" 2>/dev/null || true
}

# ============================================================================
# INV-001: Mode-gated activation (writer --issue contract)
# ============================================================================
section "INV-001: writer --issue contract + no-arg tripwire"

# --- INV-001-a [unit]: chores-authorize.sh write REFUSES without --issue (no
# marker written, non-zero exit). RED: script absent. ---
inv001_dir="$(mktemp -d)"; register_cleanup "$inv001_dir"
setup_git_test_env "$inv001_dir" 5 "widget" >/dev/null
if [ -f "$CHORES_AUTH" ]; then
  ec=0; ( cd "$inv001_dir" && bash "$CHORES_AUTH" write >/dev/null 2>&1 ) || ec=$?
  if [ "$ec" -ne 0 ] && [ ! -f "$inv001_dir/$MARKER_REL" ]; then
    pass "INV-001-a" "write with no --issue exits non-zero and mints no marker"
  else
    fail "INV-001-a" "write with no --issue must refuse (exit=$ec, marker present=$([ -f "$inv001_dir/$MARKER_REL" ] && echo yes || echo no))"
  fi
else
  fail "INV-001-a" "scripts/chores-authorize.sh not found (writer --issue contract unimplemented)"
fi

# --- INV-001-b [unit]: write --issue 9 on a chore/issue-5-* branch (issue ≠
# branch) refuses; no marker. RED: script absent. ---
if [ -f "$CHORES_AUTH" ]; then
  ec=0; ( cd "$inv001_dir" && bash "$CHORES_AUTH" write --issue 9 >/dev/null 2>&1 ) || ec=$?
  if [ "$ec" -ne 0 ] && [ ! -f "$inv001_dir/$MARKER_REL" ]; then
    pass "INV-001-b" "write --issue mismatching branch issue refuses, mints no marker"
  else
    fail "INV-001-b" "write --issue 9 on chore/issue-5-* must refuse (exit=$ec)"
  fi
else
  fail "INV-001-b" "scripts/chores-authorize.sh not found"
fi

# --- INV-001-c [unit]: write --issue 5 on the matching chore/issue-5-* branch
# succeeds and mints a marker. RED: script absent. ---
if [ -f "$CHORES_AUTH" ]; then
  ec=0; ( cd "$inv001_dir" && bash "$CHORES_AUTH" write --issue 5 --allowed-paths scripts/prune-scan.sh >/dev/null 2>&1 ) || ec=$?
  if [ "$ec" -eq 0 ] && [ -f "$inv001_dir/$MARKER_REL" ]; then
    pass "INV-001-c" "write --issue 5 on matching branch mints the marker"
  else
    fail "INV-001-c" "write --issue 5 on chore/issue-5-* should mint marker (exit=$ec)"
  fi
else
  fail "INV-001-c" "scripts/chores-authorize.sh not found"
fi

# --- INV-001-d [structural]: no-arg tripwire — SKILL.md must not invoke the
# marker writer on the no-arg/auto-select path (acknowledged prompt-level
# residual, tripwire only per spec). We require an explicit-issue mode guard
# around the writer invocation. ---
if [ -f "$CCHORES_SKILL" ]; then
  if grep -q 'chores-authorize.sh' "$CCHORES_SKILL" 2>/dev/null; then
    pass "INV-001-d" "cchores SKILL references chores-authorize.sh (writer wired)"
  else
    fail "INV-001-d" "cchores SKILL does not reference chores-authorize.sh (writer not wired)"
  fi
else
  fail "INV-001-d" "skills/cchores/SKILL.md not found"
fi

# ============================================================================
# INV-002: Branch- and file-scoped SFG allowlist (5-clause iff, integration)
# ============================================================================
section "INV-002: branch+file-scoped allowlist"

# Full-match ALLOW cell — the load-bearing RED assertion for the whole feature.
inv002_dir="$(mktemp -d)"; register_cleanup "$inv002_dir"
setup_git_test_env "$inv002_dir" 42 "fix-thing" >/dev/null
INV002_BRANCH="chore/issue-42-fix-thing"
write_marker_and_manifest "$inv002_dir" "$INV002_BRANCH" 42 "RUN-42-abc" '["scripts/prune-scan.sh"]'

# --- INV-002-a [integration]: valid marker + matching branch + run_id + path in
# allowed_paths + affordance-eligible (# affordance) target → ALLOWED (exit 0).
# RED: prune-scan.sh is in DEFAULTS untagged → blocked (exit 2) today. ---
res="$( cd "$inv002_dir" && run_sfg "$(edit_json scripts/prune-scan.sh)" )"
if [ "$(sfg_exit "$res")" = "0" ]; then
  pass "INV-002-a" "Edit to affordance-eligible scripts/prune-scan.sh ALLOWED under a valid full-match marker"
else
  fail "INV-002-a" "affordance-eligible target under a valid marker must be ALLOWED (got exit $(sfg_exit "$res"))"
fi

# --- INV-002-b [integration]: no marker → BLOCKED (regression guard). ---
inv002b_dir="$(mktemp -d)"; register_cleanup "$inv002b_dir"
setup_git_test_env "$inv002b_dir" 42 "fix-thing" >/dev/null
res="$( cd "$inv002b_dir" && run_sfg "$(edit_json scripts/prune-scan.sh)" )"
if [ "$(sfg_exit "$res")" = "2" ]; then
  pass "INV-002-b" "affordance-eligible target with NO marker is BLOCKED"
else
  fail "INV-002-b" "no-marker protected write must be BLOCKED (got exit $(sfg_exit "$res"))"
fi

# --- INV-002-c [integration]: marker.branch ≠ current branch → BLOCKED. ---
inv002c_dir="$(mktemp -d)"; register_cleanup "$inv002c_dir"
setup_git_test_env "$inv002c_dir" 42 "fix-thing" >/dev/null
write_marker_and_manifest "$inv002c_dir" "chore/issue-42-OTHER-branch" 42 "RUN-42-abc" '["scripts/prune-scan.sh"]'
res="$( cd "$inv002c_dir" && run_sfg "$(edit_json scripts/prune-scan.sh)" )"
if [ "$(sfg_exit "$res")" = "2" ]; then
  pass "INV-002-c" "marker.branch mismatch is BLOCKED"
else
  fail "INV-002-c" "branch-mismatched marker must be BLOCKED (got exit $(sfg_exit "$res"))"
fi

# --- INV-002-d [integration]: branch name issue ≠ marker.issue → BLOCKED.
# Marker names issue 42, but current branch is chore/issue-99-* . ---
inv002d_dir="$(mktemp -d)"; register_cleanup "$inv002d_dir"
setup_git_test_env "$inv002d_dir" 99 "fix-thing" >/dev/null
# Marker claims branch chore/issue-99-fix-thing but issue field = 42 (mismatch to the branch's numeric issue).
write_marker_and_manifest "$inv002d_dir" "chore/issue-99-fix-thing" 42 "RUN-99-abc" '["scripts/prune-scan.sh"]'
res="$( cd "$inv002d_dir" && run_sfg "$(edit_json scripts/prune-scan.sh)" )"
if [ "$(sfg_exit "$res")" = "2" ]; then
  pass "INV-002-d" "branch numeric issue ≠ marker.issue is BLOCKED"
else
  fail "INV-002-d" "branch/issue mismatch must be BLOCKED (got exit $(sfg_exit "$res"))"
fi

# --- INV-002-e [integration]: target ∉ marker.allowed_paths → BLOCKED. ---
inv002e_dir="$(mktemp -d)"; register_cleanup "$inv002e_dir"
setup_git_test_env "$inv002e_dir" 42 "fix-thing" >/dev/null
write_marker_and_manifest "$inv002e_dir" "chore/issue-42-fix-thing" 42 "RUN-42-abc" '["scripts/harness-fingerprint.sh"]'
res="$( cd "$inv002e_dir" && run_sfg "$(edit_json scripts/prune-scan.sh)" )"
if [ "$(sfg_exit "$res")" = "2" ]; then
  pass "INV-002-e" "target not in marker.allowed_paths is BLOCKED"
else
  fail "INV-002-e" "out-of-scope target must be BLOCKED (got exit $(sfg_exit "$res"))"
fi

# --- INV-002-f [integration]: custom_patterns match with a valid marker →
# BLOCKED (RS-021 — custom patterns never affordance-eligible). ---
inv002f_dir="$(mktemp -d)"; register_cleanup "$inv002f_dir"
setup_git_test_env "$inv002f_dir" 42 "fix-thing" >/dev/null
cat > "$inv002f_dir/.correctless/config/workflow-config.json" <<'CFG'
{ "protected_files": { "custom_patterns": ["src/special.conf"] } }
CFG
write_marker_and_manifest "$inv002f_dir" "chore/issue-42-fix-thing" 42 "RUN-42-abc" '["src/special.conf"]'
mkdir -p "$inv002f_dir/src"
res="$( cd "$inv002f_dir" && run_sfg "$(edit_json src/special.conf)" )"
if [ "$(sfg_exit "$res")" = "2" ]; then
  pass "INV-002-f" "custom_patterns match with a valid marker is BLOCKED"
else
  fail "INV-002-f" "custom_patterns target must never be allowed by the affordance (got exit $(sfg_exit "$res"))"
fi

# --- INV-002-i [integration, QA-006, clause-1 overlap]: an affordance-ELIGIBLE
# path (scripts/prune-scan.sh, `# affordance`) that is ALSO added to the fixture's
# custom_patterns, under a VALID full-match marker whose allowed_paths includes it
# → must STILL be BLOCKED. Proves custom_patterns forces the floor OVER the
# affordance tag (INV-002 clause (1) / INV-008: the user's explicit re-protection
# WINS). Distinct from INV-002-f, whose target is custom-only (not affordance). ---
inv002i_dir="$(mktemp -d)"; register_cleanup "$inv002i_dir"
setup_git_test_env "$inv002i_dir" 42 "fix-thing" >/dev/null
cat > "$inv002i_dir/.correctless/config/workflow-config.json" <<'CFG'
{ "protected_files": { "custom_patterns": ["scripts/prune-scan.sh"] } }
CFG
write_marker_and_manifest "$inv002i_dir" "chore/issue-42-fix-thing" 42 "RUN-42-abc" '["scripts/prune-scan.sh"]'
res="$( cd "$inv002i_dir" && run_sfg "$(edit_json scripts/prune-scan.sh)" )"
if [ "$(sfg_exit "$res")" = "2" ]; then
  pass "INV-002-i" "affordance-eligible path ALSO in custom_patterns is BLOCKED under a valid marker (custom_patterns > affordance tag)"
else
  fail "INV-002-i" "custom_patterns must force the floor over the affordance tag (got exit $(sfg_exit "$res"))"
fi

# --- INV-002-g [integration, AP-035]: target's worktree branch ≠ cwd branch →
# BLOCKED. cwd is on the chore branch with a valid marker; the Edit target lives
# in a SECOND worktree checked out to a different branch. A cwd-keyed check would
# wrongly allow; the target-tree-keyed check must BLOCK. ---
inv002g_dir="$(mktemp -d)"; register_cleanup "$inv002g_dir"
setup_git_test_env "$inv002g_dir" 42 "fix-thing" >/dev/null
write_marker_and_manifest "$inv002g_dir" "chore/issue-42-fix-thing" 42 "RUN-42-abc" '["scripts/prune-scan.sh"]'
WT_DIR="$inv002g_dir-wt"
register_cleanup "$WT_DIR"
wt_ok=false
( cd "$inv002g_dir" && git worktree add -q -b other-branch "$WT_DIR" >/dev/null 2>&1 ) && wt_ok=true
if $wt_ok; then
  mkdir -p "$WT_DIR/scripts"
  # Absolute target into the OTHER-branch worktree; run hook from the chore-branch cwd.
  res="$( cd "$inv002g_dir" && run_sfg "$(edit_json "$WT_DIR/scripts/prune-scan.sh")" )"
  if [ "$(sfg_exit "$res")" = "2" ]; then
    pass "INV-002-g" "target in a different-branch worktree is BLOCKED (target-tree keyed, AP-035)"
  else
    fail "INV-002-g" "cross-worktree/branch target must be BLOCKED (got exit $(sfg_exit "$res"))"
  fi
  ( cd "$inv002g_dir" && git worktree remove --force "$WT_DIR" >/dev/null 2>&1 ) || true
else
  fail "INV-002-g" "could not create a second git worktree for the AP-035 cell"
fi

# --- INV-002-h [integration, negative cell]: valid marker + matching branch +
# a NON-DEFAULTS path → normal exit 0 (allowlist irrelevant; no over-block). ---
res="$( cd "$inv002_dir" && run_sfg "$(edit_json src/app.ts)" )"
if [ "$(sfg_exit "$res")" = "0" ]; then
  pass "INV-002-h" "non-DEFAULTS path with a valid marker is a normal allow (no over-reach)"
else
  fail "INV-002-h" "non-protected path must exit 0 regardless of marker (got exit $(sfg_exit "$res"))"
fi

# ============================================================================
# INV-003: Secret-class hard floor (deny-first) — never allowed under a marker
# ============================================================================
section "INV-003: secret-class hard floor"

inv003_dir="$(mktemp -d)"; register_cleanup "$inv003_dir"
setup_git_test_env "$inv003_dir" 42 "fix-thing" >/dev/null
# Marker deliberately lists the secret paths in allowed_paths — the floor must
# still deny (deny-first, evaluated before the allowlist).
write_marker_and_manifest "$inv003_dir" "chore/issue-42-fix-thing" 42 "RUN-42-abc" \
  '[".env","credentials.json","id_rsa","secrets/../.env","foo/../id_rsa","ID_RSA"]'
mkdir -p "$inv003_dir/secrets" "$inv003_dir/foo"
for secret in ".env" "credentials.json" "id_rsa" "secrets/../.env" "foo/../id_rsa" "ID_RSA"; do
  res="$( cd "$inv003_dir" && run_sfg "$(edit_json "$secret")" )"
  if [ "$(sfg_exit "$res")" = "2" ]; then
    pass "INV-003:$secret" "secret-floor '$secret' BLOCKED even with a valid marker listing it"
  else
    fail "INV-003:$secret" "secret-floor '$secret' must NEVER be allowed (got exit $(sfg_exit "$res"))"
  fi
done

# --- INV-003-g [structural]: the hook defines a side-effect-free is_secret_floor
# derived from the INV-008 tags (deny-first check must be callable without the
# STEP-9 policy body). RED: no such function in the hook today. ---
if grep -qE '^[[:space:]]*is_secret_floor[[:space:]]*\(\)' "$HOOK" 2>/dev/null; then
  pass "INV-003-g" "hook defines a callable is_secret_floor() (deny-first, tag-derived)"
else
  fail "INV-003-g" "hook has no is_secret_floor() function (secret-floor-first check unimplemented)"
fi

# ============================================================================
# INV-004: Marker provenance (agent frontmatter allowlist + glob-coverage)
# ============================================================================
section "INV-004: marker provenance"

# glob-coverage helper (R2-O): now the SHARED, bare-verb-normalized glob_covers
# from test-helpers.sh (MA-010). A BARE `Write`/`Bash` grant is the maximal glob
# for that verb — the previous local helper (and the parenthesized-only greps in
# INV-004-a/d) were VACUOUS against agents/cdebug-fix.md's bare `Write`/`Bash`
# grants, producing a FALSE-GREEN "writer unreachable by /cdebug" (AP-022). The
# shared helper is used below; no local re-definition.

# --- INV-004-a [structural, HONEST]: the load-bearing marker-provenance closure
# is that the marker path is in SFG DEFAULTS tagged `# other-floor`, so a NAIVE
# Edit/Write to the marker — by ANY agent, /cdebug included — is BLOCKED by SFG
# (INV-004-e/INV-014). That is the property SFG actually enforces.
#
# HONEST FRAME (MA-010, AP-040): agents/cdebug-fix.md legitimately carries BARE
# `Bash` and `Write` grants (it is the fix agent — do NOT narrow them). A bare
# `Bash` DOES permit `bash chores-authorize.sh write`, so the writer IS
# Bash-reachable by an on-branch /cdebug. That Bash-reachability is a DISCLOSED,
# ACCEPTED AP-040 residual (SFG inspects no Bash), NOT something SFG closes — so
# we do NOT assert "the writer is unreachable by /cdebug" (that was the false
# green). We assert only the true naive-Edit/Write closure. ---
inv004a_block="$(extract_defaults_block "$HOOK")"
[ -z "$inv004a_block" ] && inv004a_block="$(sed -n '/^DEFAULTS="/,/"$/p' "$HOOK")"
inv004a_marker_line="$(printf '%s\n' "$inv004a_block" | grep -F "$MARKER_REL" || true)"
if [ -n "$inv004a_marker_line" ] && printf '%s' "$inv004a_marker_line" | grep -qE '#[[:space:]]*other-floor'; then
  pass "INV-004-a" "naive Edit/Write to the marker is closed via SFG DEFAULTS # other-floor membership (Bash-reachability by /cdebug is the disclosed AP-040 residual, not asserted closed)"
else
  fail "INV-004-a" "marker path not in DEFAULTS as # other-floor — the naive-Edit/Write provenance closure is missing"
fi

# --- INV-004-b [unit]: glob-coverage RED-proof fixture — the covering-grant
# detector must FLAG a Write(.correctless/artifacts/*) grant as covering the
# marker path (proves the test uses glob-coverage, not substring). ---
if glob_covers "Write(.correctless/artifacts/*)" "$MARKER_REL"; then
  pass "INV-004-b" "glob-coverage detector flags Write(.correctless/artifacts/*) as covering the marker"
else
  fail "INV-004-b" "glob-coverage detector failed to flag a covering Write grant"
fi
# Negative: a non-covering glob must NOT flag.
if glob_covers "Write(docs/*)" "$MARKER_REL"; then
  fail "INV-004-c" "glob-coverage detector false-positive on a non-covering grant"
else
  pass "INV-004-c" "glob-coverage detector does not flag a non-covering Write(docs/*) grant"
fi

# --- INV-004-d [structural, HONEST]: the writer (chores-authorize.sh, all three
# DEFAULTS forms) is in SFG DEFAULTS tagged `# other-floor`, so a naive Edit/Write
# to the WRITER is blocked (INV-014). The parenthesized-only `Write(...)` scan this
# cell used to run was VACUOUS against agents/cdebug-fix.md's bare `Write`/`Bash`
# grants (MA-010 false green — a bare Write covers Write(**), a bare Bash permits
# `bash chores-authorize.sh write`). We now assert the TRUE closure (writer ∈
# DEFAULTS # other-floor) and, using the shared bare-verb-normalized glob_covers,
# make the /cdebug Bash-reachability of the writer VISIBLE as the disclosed,
# accepted AP-040 residual rather than hiding it behind a parenthesized-only match.
# We do NOT assert the writer is unreachable by /cdebug (it is, via Bash). ---
inv004d_block="$(extract_defaults_block "$HOOK")"
[ -z "$inv004d_block" ] && inv004d_block="$(sed -n '/^DEFAULTS="/,/"$/p' "$HOOK")"
inv004d_miss=""
for form in "scripts/chores-authorize.sh" ".correctless/scripts/chores-authorize.sh" "chores-authorize.sh"; do
  line="$(printf '%s\n' "$inv004d_block" | grep -F "$form" | head -1 || true)"
  if [ -z "$line" ] || ! printf '%s' "$line" | grep -qE '#[[:space:]]*other-floor'; then
    inv004d_miss="$inv004d_miss $form"
  fi
done
# Informational: the shared helper flags cdebug-fix.md's bare grants as covering
# the writer invocation (the disclosed AP-040 residual). Not a fail condition —
# cdebug-fix.md legitimately needs bare Bash/Write.
inv004d_residual="none"
if [ -f "$CDEBUG_FIX" ]; then
  while IFS= read -r g; do
    g="$(printf '%s' "$g" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    [ -z "$g" ] && continue
    if glob_covers "$g" "bash scripts/chores-authorize.sh write"; then inv004d_residual="disclosed AP-040 (bare '$g')"; break; fi
  done < <(parse_tools_list "$CDEBUG_FIX" 2>/dev/null || true)
fi
if [ -z "$inv004d_miss" ]; then
  pass "INV-004-d" "writer (three forms) is in DEFAULTS # other-floor — naive Edit/Write to the writer is closed; /cdebug Bash-reachability of the writer = $inv004d_residual"
else
  fail "INV-004-d" "writer forms missing from DEFAULTS # other-floor:$inv004d_miss (naive-write closure incomplete)"
fi

# --- INV-004-e [structural, leg c]: the enforceable provenance leg — the marker
# path is in the hook DEFAULTS block AND classified never-affordance
# (# other-floor), so a naive /cdebug Edit/Write to the marker is BLOCKED
# (RS-002/RS-011). RED: the marker is not in DEFAULTS and the block is untagged. ---
inv004_block="$(extract_defaults_block "$HOOK")"
[ -z "$inv004_block" ] && inv004_block="$(sed -n '/^DEFAULTS="/,/"$/p' "$HOOK")"
marker_line="$(printf '%s\n' "$inv004_block" | grep -F "$MARKER_REL" || true)"
if [ -n "$marker_line" ] && printf '%s' "$marker_line" | grep -qE '#[[:space:]]*other-floor'; then
  pass "INV-004-e" "marker path is in DEFAULTS classified # other-floor (never self-authorizable)"
else
  fail "INV-004-e" "marker path missing from DEFAULTS or not tagged # other-floor (provenance leg c unimplemented)"
fi

# ============================================================================
# INV-005: Marker lifecycle — per-run identity, idempotent clear
# ============================================================================
section "INV-005: marker lifecycle (run_id binding + clear)"

# --- INV-005-a [integration]: marker.run_id ≠ current manifest run_id → BLOCKED
# (a leaked marker from a crashed run is inert). RED: needs run_id verification. ---
inv005_dir="$(mktemp -d)"; register_cleanup "$inv005_dir"
setup_git_test_env "$inv005_dir" 42 "fix-thing" >/dev/null
# Marker run_id = STALE-run; manifest run_id = FRESH-run → mismatch.
jq -n --arg b "chore/issue-42-fix-thing" --argjson i 42 --arg r "STALE-run" \
      --argjson ap '["scripts/prune-scan.sh"]' --arg at "2026-07-06T10:00:00Z" \
  '{branch:$b,issue:$i,run_id:$r,allowed_paths:$ap,authorized_at:$at}' \
  > "$inv005_dir/$MARKER_REL"
jq -n --arg r "FRESH-run" '{run_id:$r,schema_version:1}' \
  > "$(chore_run_manifest "$inv005_dir" "chore/issue-42-fix-thing")"
res="$( cd "$inv005_dir" && run_sfg "$(edit_json scripts/prune-scan.sh)" )"
if [ "$(sfg_exit "$res")" = "2" ]; then
  pass "INV-005-a" "marker.run_id ≠ current manifest run_id is BLOCKED"
else
  fail "INV-005-a" "run_id mismatch must BLOCK a leaked/stale marker (got exit $(sfg_exit "$res"))"
fi

# --- INV-005-b [unit]: chores-authorize.sh clear is idempotent — after clear the
# marker is absent, and clearing an already-absent marker still exits 0. ---
if [ -f "$CHORES_AUTH" ]; then
  echo '{}' > "$inv005_dir/$MARKER_REL"
  ec1=0; ( cd "$inv005_dir" && bash "$CHORES_AUTH" clear >/dev/null 2>&1 ) || ec1=$?
  ec2=0; ( cd "$inv005_dir" && bash "$CHORES_AUTH" clear >/dev/null 2>&1 ) || ec2=$?
  if [ ! -f "$inv005_dir/$MARKER_REL" ] && [ "$ec1" -eq 0 ] && [ "$ec2" -eq 0 ]; then
    pass "INV-005-b" "clear removes the marker and is idempotent (double-clear exits 0)"
  else
    fail "INV-005-b" "clear must be idempotent and remove the marker (ec1=$ec1 ec2=$ec2)"
  fi
else
  fail "INV-005-b" "scripts/chores-authorize.sh not found (clear subcommand unimplemented)"
fi

# ============================================================================
# INV-006: Mode-aware pre-selection SFG check (coded --mode axis)
# ============================================================================
section "INV-006: mode-aware pre-selection check"

# All four cells routed through the SAME coded cchores-diff-check.sh --mode helper
# (R2-Q). RED: script absent.
inv006_run() { # $1 mode  $2 changed-file  -> stdout of diff-check
  printf '%s\n' "$2" | bash "$DIFF_CHECK" --mode "$1" --allowed-paths /dev/null 2>/dev/null
}
if [ -f "$DIFF_CHECK" ]; then
  # explicit mode, infra path → NOT abort (ok)
  out="$(inv006_run explicit scripts/prune-scan.sh)"
  if printf '%s' "$out" | grep -qi '^ok'; then
    pass "INV-006-a" "explicit mode + infra path → ok (not aborted)"
  else
    fail "INV-006-a" "explicit-mode infra path should be ok (got: '$out')"
  fi
  # explicit mode, secret path → abort
  out="$(inv006_run explicit .env)"
  if printf '%s' "$out" | grep -qi '^abort'; then
    pass "INV-006-b" "explicit mode + secret-floor path → abort"
  else
    fail "INV-006-b" "explicit-mode secret path must abort (got: '$out')"
  fi
  # no-arg mode, infra path → abort (v1)
  out="$(inv006_run no-arg scripts/prune-scan.sh)"
  if printf '%s' "$out" | grep -qi '^abort'; then
    pass "INV-006-c" "no-arg mode + any protected path → abort (v1)"
  else
    fail "INV-006-c" "no-arg-mode protected path must abort (got: '$out')"
  fi
  # no-arg mode, secret path → abort
  out="$(inv006_run no-arg .env)"
  if printf '%s' "$out" | grep -qi '^abort'; then
    pass "INV-006-d" "no-arg mode + secret path → abort"
  else
    fail "INV-006-d" "no-arg-mode secret path must abort (got: '$out')"
  fi
else
  fail "INV-006-a" "scripts/cchores-diff-check.sh not found"
  fail "INV-006-b" "scripts/cchores-diff-check.sh not found"
  fail "INV-006-c" "scripts/cchores-diff-check.sh not found"
  fail "INV-006-d" "scripts/cchores-diff-check.sh not found"
fi

# ============================================================================
# INV-007: Mode-aware post-cdebug diff check (authoritative scope/floor gate)
# ============================================================================
section "INV-007: post-cdebug diff check"

# cchores-diff-check.sh takes changed files on STDIN + --mode + --allowed-paths.
diff_check() { # $1 mode  $2 allowed_paths_file  (files on stdin)
  bash "$DIFF_CHECK" --mode "$1" --allowed-paths "$2" 2>/dev/null
}
if [ -f "$DIFF_CHECK" ]; then
  ap_file="$(mktemp)"; register_cleanup "$ap_file"
  printf '%s\n' "scripts/prune-scan.sh" > "$ap_file"

  # explicit + in-scope affordance infra → ok
  out="$(printf '%s\n' "scripts/prune-scan.sh" | diff_check explicit "$ap_file")"
  if printf '%s' "$out" | grep -qi '^ok'; then
    pass "INV-007-a" "explicit + in-scope # affordance path → ok"
  else
    fail "INV-007-a" "explicit in-scope infra should be ok (got: '$out')"
  fi

  # explicit + secret-floor path (leg a, marker-independent) → abort
  out="$(printf '%s\n' "id_rsa" | diff_check explicit "$ap_file")"
  if printf '%s' "$out" | grep -qi '^abort'; then
    pass "INV-007-b" "explicit + # secret-floor path in diff → abort (leg a authoritative)"
  else
    fail "INV-007-b" "secret-floor in diff must abort (got: '$out')"
  fi

  # explicit + shared-project-doc (leg b) → abort
  out="$(printf '%s\n' ".correctless/ARCHITECTURE.md" | diff_check explicit "$ap_file")"
  if printf '%s' "$out" | grep -qi '^abort'; then
    pass "INV-007-c" "explicit + shared-project-doc in diff → abort (leg b authoritative)"
  else
    fail "INV-007-c" "shared-doc in diff must abort (got: '$out')"
  fi

  # explicit + out-of-scope protected infra (leg c) → abort
  out="$(printf '%s\n' "scripts/harness-fingerprint.sh" | diff_check explicit "$ap_file")"
  if printf '%s' "$out" | grep -qi '^abort'; then
    pass "INV-007-d" "explicit + out-of-scope infra (∉ allowed_paths) → abort (leg c guardrail)"
  else
    fail "INV-007-d" "out-of-scope infra in diff must abort (got: '$out')"
  fi

  # no-arg + any protected path → abort (v1)
  out="$(printf '%s\n' "scripts/prune-scan.sh" | diff_check no-arg "$ap_file")"
  if printf '%s' "$out" | grep -qi '^abort'; then
    pass "INV-007-e" "no-arg + any protected path in diff → abort (v1)"
  else
    fail "INV-007-e" "no-arg protected path in diff must abort (got: '$out')"
  fi

  # RS-022 cross-check: a benign-looking issue whose fix actually touches a floor
  # path is caught HERE (INV-007), not at INV-006.
  out="$(printf '%s\n' "src/app.ts" ".env" | diff_check explicit "$ap_file")"
  if printf '%s' "$out" | grep -qi '^abort'; then
    pass "INV-007-f" "floor path hidden among benign changes is caught at INV-007 (RS-022)"
  else
    fail "INV-007-f" "INV-007 must catch a floor path in a mixed diff (got: '$out')"
  fi

  # --- B2: authority split — legs (a)/(b) are marker-INDEPENDENT and authoritative
  # OVER marker.allowed_paths. A forged/over-broad allowed_paths that LISTS a
  # secret or a shared doc must NOT unlock it. These cells put the sensitive path
  # INSIDE --allowed-paths and still require abort, so a GREEN implementing ONLY
  # leg (c) ("abort iff protected ∉ allowed_paths") FAILS them. ---

  # INV-007-g [integration, leg a]: a secret-floor path LISTED in allowed_paths
  # → must STILL abort (secret floor is authoritative over allowed_paths).
  ap_secret="$(mktemp)"; register_cleanup "$ap_secret"
  printf '%s\n' "scripts/prune-scan.sh" "id_rsa" ".env" > "$ap_secret"
  out="$(printf '%s\n' "id_rsa" | diff_check explicit "$ap_secret")"
  if printf '%s' "$out" | grep -qi '^abort'; then
    pass "INV-007-g" "secret-floor path listed in --allowed-paths STILL aborts (leg a > allowed_paths)"
  else
    fail "INV-007-g" "a forged allowed_paths listing a secret must NOT unlock it (got: '$out')"
  fi

  # INV-007-h [integration, leg b]: a shared-project-doc path LISTED in
  # allowed_paths → must STILL abort (shared-doc leg is authoritative).
  ap_doc="$(mktemp)"; register_cleanup "$ap_doc"
  printf '%s\n' "scripts/prune-scan.sh" ".correctless/ARCHITECTURE.md" > "$ap_doc"
  out="$(printf '%s\n' ".correctless/ARCHITECTURE.md" | diff_check explicit "$ap_doc")"
  if printf '%s' "$out" | grep -qi '^abort'; then
    pass "INV-007-h" "shared-doc path listed in --allowed-paths STILL aborts (leg b > allowed_paths)"
  else
    fail "INV-007-h" "a forged allowed_paths listing a shared doc must NOT unlock it (got: '$out')"
  fi
else
  for c in a b c d e f g h; do fail "INV-007-$c" "scripts/cchores-diff-check.sh not found"; done
fi

# ============================================================================
# INV-008: DEFAULTS 3-way classification — single-source, deny-by-default
# ============================================================================
section "INV-008: DEFAULTS 3-way classification"

# Extract the DEFAULTS block from the ACTUAL hook between anchored delimiters
# ^DEFAULTS=" ... ^"$ (AP-032 parse-anchor pinning, RS-012).
# Advisory fix: the FIRST pattern sits on the opening `DEFAULTS=".env` line, so
# emit the remainder-after-DEFAULTS=" too (otherwise `.env`'s tag is never
# checked). Also emit any pattern on an inline-closing final line (`...md"`).
extract_defaults_block() { # $1 hook file
  awk '
    /^DEFAULTS="/ {
      infl=1
      line=$0; sub(/^DEFAULTS="/,"",line)
      if (line ~ /"$/) { sub(/"$/,"",line); if (line != "") print line; exit }
      if (line != "") print line
      next
    }
    infl && /^"$/ { exit }
    infl && /"$/ { l=$0; sub(/"$/,"",l); if (l != "") print l; exit }
    infl { print }
  ' "$1"
}

# --- INV-008-a [unit, structural]: every DEFAULTS line carries exactly one of
# the three tags (# affordance | # secret-floor | # other-floor). RED: today the
# block is untagged and has no ^"$ closing anchor line. ---
block="$(extract_defaults_block "$HOOK")"
if [ -z "$block" ]; then
  fail "INV-008-a" "DEFAULTS block not extractable via ^DEFAULTS\"...^\"$ anchors (closing anchor missing / untagged)"
else
  bad=0; total=0
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    total=$((total+1))
    n=0
    printf '%s' "$line" | grep -qE '#[[:space:]]*affordance' && n=$((n+1))
    printf '%s' "$line" | grep -qE '#[[:space:]]*secret-floor' && n=$((n+1))
    printf '%s' "$line" | grep -qE '#[[:space:]]*other-floor' && n=$((n+1))
    [ "$n" -eq 1 ] || bad=$((bad+1))
  done <<< "$block"
  if [ "$total" -gt 0 ] && [ "$bad" -eq 0 ]; then
    pass "INV-008-a" "every DEFAULTS line is tagged exactly once ($total lines)"
  else
    fail "INV-008-a" "$bad/$total DEFAULTS lines are not tagged exactly once (single-source classification missing)"
  fi
fi

# --- INV-008-a2 [unit, structural]: the opening-line pattern `.env` carries the
# `# secret-floor` tag (advisory-fix coverage — the extractor now emits the
# first pattern; assert its tag specifically). RED: .env is untagged today. ---
env_line="$(printf '%s\n' "$block" | grep -E '(^|[[:space:]])\.env([[:space:]]|$)' | head -1 || true)"
if [ -n "$env_line" ] && printf '%s' "$env_line" | grep -qE '#[[:space:]]*secret-floor'; then
  pass "INV-008-a2" ".env (opening DEFAULTS line) carries the # secret-floor tag"
else
  fail "INV-008-a2" ".env is not tagged # secret-floor (got line: '${env_line:-<none>}')"
fi

# --- INV-008-b [unit, structural]: no # affordance line looks secret-adjacent
# (keyword heuristic). ---
if [ -n "$block" ]; then
  offenders="$(printf '%s\n' "$block" | grep -E '#[[:space:]]*affordance' | grep -iE 'key|secret|credential|token|password|pem|rsa|ed25519|keystore' || true)"
  if [ -z "$offenders" ]; then
    pass "INV-008-b" "no # affordance line is secret-adjacent (keyword heuristic clean)"
  else
    fail "INV-008-b" "a # affordance line looks secret-adjacent: $offenders"
  fi
else
  fail "INV-008-b" "DEFAULTS block not extractable — cannot run keyword heuristic"
fi

# --- INV-008-c [unit, structural]: source↔mirror parity of the tagged block. ---
if [ -f "$HOOK_MIRROR" ]; then
  mblock="$(extract_defaults_block "$HOOK_MIRROR")"
  if [ -n "$block" ] && [ "$block" = "$mblock" ]; then
    pass "INV-008-c" "DEFAULTS tagged block is byte-identical across source and mirror"
  else
    fail "INV-008-c" "DEFAULTS block source↔mirror parity broken (or block empty)"
  fi
else
  fail "INV-008-c" "correctless/hooks/sensitive-file-guard.sh mirror not found"
fi

# --- INV-008-d [integration]: runtime deny-by-default. A security guard
# (override-scrutiny.sh) and lib.sh under the SAME valid marker → BLOCKED, while
# the affordance-eligible prune-scan.sh → ALLOWED (proves the partition is real,
# not a no-op and not over-reach). ---
inv008_dir="$(mktemp -d)"; register_cleanup "$inv008_dir"
setup_git_test_env "$inv008_dir" 42 "fix-thing" >/dev/null
write_marker_and_manifest "$inv008_dir" "chore/issue-42-fix-thing" 42 "RUN-42-abc" \
  '["scripts/prune-scan.sh","scripts/override-scrutiny.sh","scripts/lib.sh"]'
res="$( cd "$inv008_dir" && run_sfg "$(edit_json scripts/prune-scan.sh)" )"
[ "$(sfg_exit "$res")" = "0" ] \
  && pass "INV-008-d1" "affordance-eligible prune-scan.sh ALLOWED (not a no-op)" \
  || fail "INV-008-d1" "prune-scan.sh should be ALLOWED under a marker (got exit $(sfg_exit "$res"))"
res="$( cd "$inv008_dir" && run_sfg "$(edit_json scripts/override-scrutiny.sh)" )"
[ "$(sfg_exit "$res")" = "2" ] \
  && pass "INV-008-d2" "security guard override-scrutiny.sh BLOCKED even in allowed_paths (# other-floor)" \
  || fail "INV-008-d2" "override-scrutiny.sh must be BLOCKED (got exit $(sfg_exit "$res"))"
res="$( cd "$inv008_dir" && run_sfg "$(edit_json scripts/lib.sh)" )"
[ "$(sfg_exit "$res")" = "2" ] \
  && pass "INV-008-d3" "trust-dep lib.sh BLOCKED even in allowed_paths (# other-floor)" \
  || fail "INV-008-d3" "lib.sh must be BLOCKED (got exit $(sfg_exit "$res"))"

# --- INV-008-e [integration]: a fixture-injected UNTAGGED DEFAULTS line is
# BLOCKED at runtime (deny-by-default has a runtime instance, R2-P). We stage a
# copy of the hook with one extra untagged DEFAULTS line and drive it. ---
inv008e_dir="$(mktemp -d)"; register_cleanup "$inv008e_dir"
setup_git_test_env "$inv008e_dir" 42 "fix-thing" >/dev/null
write_marker_and_manifest "$inv008e_dir" "chore/issue-42-fix-thing" 42 "RUN-42-abc" '["scripts/new-untagged.sh"]'
mkdir -p "$inv008e_dir/scripts"
# Stage a hook copy beside a scripts/lib.sh so the copy can source lib.sh, with an
# extra untagged DEFAULTS line injected.
STAGE="$inv008e_dir/stage"
mkdir -p "$STAGE/hooks" "$STAGE/scripts"
if cp "$HOOK" "$STAGE/hooks/sensitive-file-guard.sh" 2>/dev/null \
   && cp "$REPO_DIR/scripts/lib.sh" "$STAGE/scripts/lib.sh" 2>/dev/null; then
  # Inject an untagged line right after DEFAULTS=" (portable awk rewrite).
  awk 'BEGIN{done=0} { print } /^DEFAULTS="/ && !done { print "scripts/new-untagged.sh"; done=1 }' \
    "$STAGE/hooks/sensitive-file-guard.sh" > "$STAGE/hooks/hook2.sh" 2>/dev/null \
    && mv "$STAGE/hooks/hook2.sh" "$STAGE/hooks/sensitive-file-guard.sh"
  ec=0
  out="$(printf '%s' "$(edit_json scripts/new-untagged.sh)" | ( cd "$inv008e_dir" && bash "$STAGE/hooks/sensitive-file-guard.sh" ) 2>&1 >/dev/null)" || ec=$?
  if [ "$ec" = "2" ]; then
    pass "INV-008-e" "an untagged DEFAULTS line is BLOCKED at runtime (deny-by-default, R2-P)"
  else
    fail "INV-008-e" "untagged DEFAULTS line must be treated as floor → BLOCK (got exit $ec)"
  fi
else
  fail "INV-008-e" "could not stage a hook+lib copy for the untagged-line runtime cell"
fi

# ============================================================================
# INV-009: Floor-immutability under the affordance (set-equality + trust-dep)
# ============================================================================
section "INV-009: floor immutability"

# Leg (a) uses the same anchored parser to compare base vs head tag classification
# and asserts set-equality; fails closed on a moved/absent anchor. We model the
# classification-set extractor the coded post-cdebug check must use.
classification_set() { # stdin = hook file content region -> sorted tag pairs
  awk '
    /^DEFAULTS="/ { infl=1; next }
    infl && /^"$/ { infl=0; next }
    infl {
      line=$0
      tag="UNTAGGED"
      if (line ~ /#[[:space:]]*affordance/)   tag="affordance"
      else if (line ~ /#[[:space:]]*secret-floor/) tag="secret-floor"
      else if (line ~ /#[[:space:]]*other-floor/)  tag="other-floor"
      # strip the trailing comment to get the pattern
      pat=line; sub(/[[:space:]]*#.*$/,"",pat)
      if (pat != "") print pat "\t" tag
    }
  ' "$1" | sort
}

# --- INV-009-a [unit, test-model]: a fix that changes a tag classification → the
# base/head classification sets differ → the post-cdebug check must abort. We
# assert the coded diff check surfaces the tag change. RED: cchores-diff-check.sh
# absent AND the classification helper needs the anchored/tagged block. ---
inv009_base="$(mktemp)"; register_cleanup "$inv009_base"
inv009_head="$(mktemp)"; register_cleanup "$inv009_head"
# Base: a minimal tagged block.
cat > "$inv009_base" <<'BASEHK'
DEFAULTS="scripts/prune-scan.sh # affordance
scripts/lib.sh # other-floor
.env # secret-floor
"
BASEHK
# Head: prune-scan.sh flipped to a floor-weakening tag change (affordance→…),
# and lib.sh flipped to affordance (weakening a trust dep).
cat > "$inv009_head" <<'HEADHK'
DEFAULTS="scripts/prune-scan.sh # affordance
scripts/lib.sh # affordance
.env # secret-floor
"
HEADHK
base_set="$(classification_set "$inv009_base")"
head_set="$(classification_set "$inv009_head")"
if [ "$base_set" != "$head_set" ]; then
  pass "INV-009-a" "classification-set extractor detects a tag change between base and head (drives abort)"
else
  fail "INV-009-a" "tag-change between base and head was not detected (set-equality leg broken)"
fi

# --- INV-009-b [unit, test-model]: fail-closed on a moved/absent anchor — if the
# closing ^"$ anchor is missing in either version, the extractor must yield an
# unusable/empty set so the check fails closed (abort), never silently equal. ---
inv009_bad="$(mktemp)"; register_cleanup "$inv009_bad"
printf 'DEFAULTS="scripts/prune-scan.sh # affordance\nNO CLOSING ANCHOR\n' > "$inv009_bad"
bad_set="$(classification_set "$inv009_bad")"
# With no closing anchor, awk keeps consuming to EOF; the "NO CLOSING ANCHOR"
# line has no tag → UNTAGGED. A robust head that differs from a clean base means
# the sets are NOT equal → abort. Assert the extracted set is non-equal to a
# clean base (fail-closed rather than accidental match).
if [ "$bad_set" != "$base_set" ]; then
  pass "INV-009-b" "a moved/absent closing anchor yields a non-matching set (fail-closed)"
else
  fail "INV-009-b" "moved-anchor version matched the clean base — would fail OPEN"
fi

# --- INV-009-c [integration]: leg (b) — lib.sh is never # affordance and is
# BLOCKED under a valid marker (corollary of INV-008 ineligibility). ---
if [ -n "$block" ]; then
  if printf '%s\n' "$block" | grep -E 'lib\.sh' | grep -qE '#[[:space:]]*affordance'; then
    fail "INV-009-c" "lib.sh is tagged # affordance — trust dependency must be # other-floor"
  else
    pass "INV-009-c" "lib.sh is never tagged # affordance (trust-dep closure)"
  fi
else
  fail "INV-009-c" "DEFAULTS block not extractable — cannot verify lib.sh tag"
fi

# --- INV-009-d [integration]: an Edit to lib.sh under a valid marker that even
# lists lib.sh in allowed_paths is BLOCKED by INV-002 (already covered by
# INV-008-d3; restated here as the INV-009 leg-b behavioral corollary). ---
res="$( cd "$inv008_dir" && run_sfg "$(edit_json scripts/lib.sh)" )"
[ "$(sfg_exit "$res")" = "2" ] \
  && pass "INV-009-d" "Edit to lib.sh under a valid marker is BLOCKED (leg b via INV-002)" \
  || fail "INV-009-d" "lib.sh Edit must be BLOCKED (got exit $(sfg_exit "$res"))"

# --- INV-009-e [structural]: the coded post-cdebug immutability check (leg a)
# must be wired — the /cchores post-cdebug step must re-extract and compare the
# DEFAULTS tag classification (set-equality, fail-closed on moved anchors). RED:
# the SKILL post-cdebug step has no classification-immutability wiring today.
# DECISION: asserted as a SKILL-wiring tripwire (implementation-tolerant); the
# extractor property itself is covered behaviorally by INV-009-a/b and the diff
# gate by INV-007. GREEN may host the check in cchores-diff-check.sh. ---
if [ -f "$CCHORES_SKILL" ] \
   && grep -qiE 'classification|# affordance|# secret-floor|# other-floor' "$CCHORES_SKILL" 2>/dev/null \
   && grep -qiE 'set-equal|immutab|floor.?immutab|re-extract' "$CCHORES_SKILL" 2>/dev/null; then
  pass "INV-009-e" "cchores post-cdebug step wires the DEFAULTS-classification immutability check (leg a)"
else
  fail "INV-009-e" "cchores post-cdebug step has no classification set-equality/immutability wiring (leg a unimplemented)"
fi

# --- B1: leg (a) must drive the REAL producer. INV-009 leg (a) wording: "the
# post-cdebug check re-extracts the tag classification (# affordance/# secret-floor/
# # other-floor sets) from both base-branch and head versions via the same INV-008
# anchored parser and asserts set-equality; fails closed if the anchor delimiters
# are absent/moved/duplicated in either version." The producer is the post-cdebug
# diff gate scripts/cchores-diff-check.sh. RED: the script does not exist, so
# these fail cleanly. INV-009-a/b above only exercise a TEST-LOCAL awk — these
# cells bind the property to the deliverable so a GREEN that never implements the
# set-equality gate cannot pass.
#
# DECISION: the spec does not pin the exact flags for the classification-
# immutability subcheck. Invoke the most spec-consistent entry point — the same
# post-cdebug diff gate — via `--check-classification --base <hook> --head <hook>`.
# GREEN may relocate/rename; a genuine leg-(a) implementation must expose SOME
# coded base/head classification comparison. Detection = an `abort` verdict on
# stdout OR a non-zero exit.
diff_check_classification() { # $1 base-hook  $2 head-hook  -> "exit:stdout"
  local ec out
  out="$(bash "$DIFF_CHECK" --check-classification --base "$1" --head "$2" 2>/dev/null)" && ec=0 || ec=$?
  printf '%s\n%s' "$ec" "$out"
}
classification_detected_abort() { # $1 captured "exit\nstdout" -> 0 if abort detected
  local ecl; ecl="$(printf '%s' "$1" | head -1)"
  local body; body="$(printf '%s' "$1" | tail -n +2)"
  [ "$ecl" != "0" ] && return 0
  printf '%s' "$body" | grep -qi 'abort' && return 0
  return 1
}

# INV-009-f [integration, leg a]: a head hook with ONE flipped classification tag
# (an `# other-floor` line changed to `# affordance`, weakening a trust dep) →
# the diff gate must ABORT.
b1_base="$(mktemp)"; register_cleanup "$b1_base"
b1_head="$(mktemp)"; register_cleanup "$b1_head"
cat > "$b1_base" <<'B1BASE'
DEFAULTS="scripts/prune-scan.sh # affordance
scripts/lib.sh # other-floor
.env # secret-floor
"
B1BASE
# Head: scripts/lib.sh flipped # other-floor -> # affordance (classification changed).
cat > "$b1_head" <<'B1HEAD'
DEFAULTS="scripts/prune-scan.sh # affordance
scripts/lib.sh # affordance
.env # secret-floor
"
B1HEAD
if [ -f "$DIFF_CHECK" ]; then
  cap="$(diff_check_classification "$b1_base" "$b1_head")"
  if classification_detected_abort "$cap"; then
    pass "INV-009-f" "flipped DEFAULTS classification tag (other-floor→affordance) → diff gate ABORTS (leg a)"
  else
    fail "INV-009-f" "a changed DEFAULTS classification must abort the post-cdebug gate (got: '$cap')"
  fi
else
  fail "INV-009-f" "scripts/cchores-diff-check.sh not found (leg-a set-equality producer unimplemented)"
fi

# INV-009-g [integration, leg a]: a head hook with a MOVED/DUPLICATED sentinel
# anchor (the closing ^"$ absent, so classification is unrecoverable) → the diff
# gate must FAIL CLOSED (abort), never silently treat the sets as equal.
b1_bad="$(mktemp)"; register_cleanup "$b1_bad"
cat > "$b1_bad" <<'B1BAD'
DEFAULTS="scripts/prune-scan.sh # affordance
scripts/lib.sh # other-floor
.env # secret-floor
DEFAULTS="duplicated-open-no-close
B1BAD
if [ -f "$DIFF_CHECK" ]; then
  cap="$(diff_check_classification "$b1_base" "$b1_bad")"
  if classification_detected_abort "$cap"; then
    pass "INV-009-g" "moved/duplicated DEFAULTS anchor in head → diff gate FAILS CLOSED (abort)"
  else
    fail "INV-009-g" "unrecoverable classification (moved anchor) must fail closed → abort (got: '$cap')"
  fi
else
  fail "INV-009-g" "scripts/cchores-diff-check.sh not found (leg-a fail-closed anchor check unimplemented)"
fi

# ============================================================================
# INV-010: Affordance-mode PR review banner (cchores-emit.sh flags)
# ============================================================================
section "INV-010: affordance-mode PR banner"

# --- INV-010-a [integration]: base banner present when --affordance-paths given.
# RED: cchores-emit.sh does not yet accept --affordance-paths / --guard-touched
# (unknown-argument exit 3 today). ---
if [ -f "$EMIT" ]; then
  out="$(printf 'PR body text' | bash "$EMIT" --sink pr-body --affordance-paths "scripts/prune-scan.sh" --issue 42 2>/dev/null || true)"
  if printf '%s' "$out" | grep -qiE 'authoriz|protected|affordance'; then
    pass "INV-010-a" "affordance-mode PR body carries a banner naming the protected path(s)/issue"
  else
    fail "INV-010-a" "affordance PR banner missing (cchores-emit --affordance-paths unimplemented)"
  fi

  # --- INV-010-b [integration]: escalated banner when the diff touches the guard
  # or its trust dependency (lib.sh). ---
  out="$(printf 'PR body text' | bash "$EMIT" --sink pr-body --affordance-paths "scripts/lib.sh" --guard-touched --issue 42 2>/dev/null || true)"
  if printf '%s' "$out" | grep -qiE 'extra care|guard that authorized|sensitive-file-guard'; then
    pass "INV-010-b" "guard/trust-dep edit escalates the banner to the extra-care form"
  else
    fail "INV-010-b" "escalated guard-self-edit banner missing (--guard-touched unimplemented)"
  fi

  # --- INV-010-c [integration]: no banner when the flag/paths are absent
  # (non-affordance PR). ---
  out="$(printf 'ordinary PR body' | bash "$EMIT" --sink pr-body 2>/dev/null || true)"
  if ! printf '%s' "$out" | grep -qiE 'authorized under|extra care|affordance'; then
    pass "INV-010-c" "ordinary (non-affordance) PR body carries no affordance banner"
  else
    fail "INV-010-c" "banner leaked onto a non-affordance PR body"
  fi
else
  fail "INV-010-a" "scripts/cchores-emit.sh not found"
  fail "INV-010-b" "scripts/cchores-emit.sh not found"
  fail "INV-010-c" "scripts/cchores-emit.sh not found"
fi

# ============================================================================
# INV-011: Marker/manifest parse fails closed (PAT-001 clause 5)
# ============================================================================
section "INV-011: fail-closed marker/manifest parse"

# Behavioral trigger enumeration: for each failure trigger, a protected
# affordance-eligible target + a PRESENT (but broken-in-some-way) marker must
# exit in {0,2} — specifically BLOCK (2), never 128/1.
inv011_run() { # $1 repo -> exit code of a prune-scan.sh Edit
  local res; res="$( cd "$1" && run_sfg "$(edit_json scripts/prune-scan.sh)" )"
  sfg_exit "$res"
}
assert_exit2() { # $1 id  $2 desc  $3 exit
  case "$3" in
    2) pass "$1" "$2 → exit 2 (fail-closed)";;
    0) fail "$1" "$2 → exit 0 (FAILED OPEN — must block)";;
    *) fail "$1" "$2 → exit $3 (must be 0 or 2, never 128/1)";;
  esac
}

# corrupt/truncated marker
inv011a="$(mktemp -d)"; register_cleanup "$inv011a"
setup_git_test_env "$inv011a" 42 "fix-thing" >/dev/null
printf '{ this is not json' > "$inv011a/$MARKER_REL"
jq -n --arg r "RUN" '{run_id:$r}' > "$(chore_run_manifest "$inv011a" "chore/issue-42-fix-thing")"
assert_exit2 "INV-011-a" "corrupt/truncated marker" "$(inv011_run "$inv011a")"

# marker missing a required field (allowed_paths)
inv011b="$(mktemp -d)"; register_cleanup "$inv011b"
setup_git_test_env "$inv011b" 42 "fix-thing" >/dev/null
jq -n --arg b "chore/issue-42-fix-thing" --argjson i 42 --arg r "RUN" \
  '{branch:$b,issue:$i,run_id:$r}' > "$inv011b/$MARKER_REL"
jq -n --arg r "RUN" '{run_id:$r}' > "$(chore_run_manifest "$inv011b" "chore/issue-42-fix-thing")"
assert_exit2 "INV-011-b" "marker missing allowed_paths field" "$(inv011_run "$inv011b")"

# marker with non-numeric issue
inv011c="$(mktemp -d)"; register_cleanup "$inv011c"
setup_git_test_env "$inv011c" 42 "fix-thing" >/dev/null
jq -n --arg b "chore/issue-42-fix-thing" --arg i "not-a-number" --arg r "RUN" \
  --argjson ap '["scripts/prune-scan.sh"]' \
  '{branch:$b,issue:$i,run_id:$r,allowed_paths:$ap}' > "$inv011c/$MARKER_REL"
jq -n --arg r "RUN" '{run_id:$r}' > "$(chore_run_manifest "$inv011c" "chore/issue-42-fix-thing")"
assert_exit2 "INV-011-c" "marker with non-numeric issue" "$(inv011_run "$inv011c")"

# missing manifest (run_id unreadable)
inv011d="$(mktemp -d)"; register_cleanup "$inv011d"
setup_git_test_env "$inv011d" 42 "fix-thing" >/dev/null
jq -n --arg b "chore/issue-42-fix-thing" --argjson i 42 --arg r "RUN" \
  --argjson ap '["scripts/prune-scan.sh"]' \
  '{branch:$b,issue:$i,run_id:$r,allowed_paths:$ap}' > "$inv011d/$MARKER_REL"
# (no chore-run manifest written)
assert_exit2 "INV-011-d" "missing run manifest" "$(inv011_run "$inv011d")"

# corrupt manifest
inv011e="$(mktemp -d)"; register_cleanup "$inv011e"
setup_git_test_env "$inv011e" 42 "fix-thing" >/dev/null
jq -n --arg b "chore/issue-42-fix-thing" --argjson i 42 --arg r "RUN" \
  --argjson ap '["scripts/prune-scan.sh"]' \
  '{branch:$b,issue:$i,run_id:$r,allowed_paths:$ap}' > "$inv011e/$MARKER_REL"
printf '{ broken' > "$(chore_run_manifest "$inv011e" "chore/issue-42-fix-thing")"
assert_exit2 "INV-011-e" "corrupt run manifest" "$(inv011_run "$inv011e")"

# non-repo cwd (git rev-parse fails)
inv011f="$(mktemp -d)"; register_cleanup "$inv011f"
mkdir -p "$inv011f/.correctless/artifacts" "$inv011f/scripts"
jq -n --arg b "chore/issue-42-fix-thing" --argjson i 42 --arg r "RUN" \
  --argjson ap '["scripts/prune-scan.sh"]' \
  '{branch:$b,issue:$i,run_id:$r,allowed_paths:$ap}' > "$inv011f/$MARKER_REL"
assert_exit2 "INV-011-f" "non-repo cwd (git rev-parse fails)" "$(inv011_run "$inv011f")"

# detached HEAD (no branch name)
inv011g="$(mktemp -d)"; register_cleanup "$inv011g"
setup_git_test_env "$inv011g" 42 "fix-thing" >/dev/null
( cd "$inv011g" && git commit -q --allow-empty -m second && git checkout -q "$(git rev-parse HEAD)" ) >/dev/null 2>&1 || true
write_marker_and_manifest "$inv011g" "chore/issue-42-fix-thing" 42 "RUN" '["scripts/prune-scan.sh"]'
assert_exit2 "INV-011-g" "detached HEAD" "$(inv011_run "$inv011g")"

# git binary failing (shim exits 127 → simulates absence)
inv011h="$(mktemp -d)"; register_cleanup "$inv011h"
setup_git_test_env "$inv011h" 42 "fix-thing" >/dev/null
write_marker_and_manifest "$inv011h" "chore/issue-42-fix-thing" 42 "RUN" '["scripts/prune-scan.sh"]'
SHIM="$inv011h/bin"; mkdir -p "$SHIM"
printf '#!/bin/sh\nexit 127\n' > "$SHIM/git"; chmod +x "$SHIM/git"
res="$( cd "$inv011h" && printf '%s' "$(edit_json scripts/prune-scan.sh)" | PATH="$SHIM:$PATH" bash "$HOOK" 2>&1 >/dev/null; echo ":EC:$?" )"
ec_h="$(printf '%s' "$res" | sed -n 's/.*:EC:\([0-9]*\).*/\1/p' | tail -1)"
assert_exit2 "INV-011-h" "git binary failing (shim 127)" "${ec_h:-999}"

# --- INV-011-i [structural]: guard-pattern lint tripwire — every git/jq
# invocation on the affordance path must be guard-suffixed. RED: no git usage in
# the hook yet (the affordance code does not exist), so the lint has nothing to
# assert AND the affordance path is absent. We require the hook to contain a
# guarded git read once shipped. ---
if grep -qE 'git[[:space:]]+-C' "$HOOK" 2>/dev/null; then
  # Every `git ...` line on the affordance path must carry a 2>/dev/null guard.
  unguarded="$(grep -nE '(^|[^A-Za-z])git[[:space:]]' "$HOOK" 2>/dev/null | grep -v '2>/dev/null' || true)"
  if [ -z "$unguarded" ]; then
    pass "INV-011-i" "all git invocations in the hook are guard-suffixed (2>/dev/null)"
  else
    fail "INV-011-i" "unguarded git invocation(s) in the hook: $unguarded"
  fi
else
  fail "INV-011-i" "hook contains no guarded 'git -C' read — affordance git path unimplemented"
fi

# ============================================================================
# INV-012: Skill↔hook capability handshake (coded behavioral probe)
# ============================================================================
section "INV-012: capability handshake probe"

# --- INV-012-a [integration]: chores-authorize.sh check-capability feeds the
# installed hook a known-good marker+branch fixture and asserts it ALLOWS an
# affordance write. Against a sentinel-less/stubbed hook it must return non-zero
# + a degrade reason naming `bash setup`. RED: script absent. ---
if [ -f "$CHORES_AUTH" ]; then
  # capable hook → exit 0
  ec=0; ( cd "$inv002_dir" && bash "$CHORES_AUTH" check-capability "$HOOK" >/dev/null 2>&1 ) || ec=$?
  if [ "$ec" -eq 0 ]; then
    pass "INV-012-a" "check-capability returns 0 against an affordance-capable hook"
  else
    fail "INV-012-a" "check-capability should pass against the real (capable) hook (exit=$ec)"
  fi

  # --- INV-012-b [integration]: a sentinel-less / non-affordance hook fixture →
  # degrade (non-zero) with a `bash setup` remediation. ---
  stub_hook="$(mktemp)"; register_cleanup "$stub_hook"
  printf '#!/usr/bin/env bash\nexit 2\n' > "$stub_hook"
  out="$( cd "$inv002_dir" && bash "$CHORES_AUTH" check-capability "$stub_hook" 2>&1 )"; ec=$?
  if [ "$ec" -ne 0 ] && printf '%s' "$out" | grep -qi 'setup'; then
    pass "INV-012-b" "check-capability degrades on a non-affordance hook and names 'bash setup'"
  else
    fail "INV-012-b" "non-affordance hook must degrade with a setup remediation (exit=$ec out='$out')"
  fi

  # --- INV-012-c [unit]: script deleted / absent path → clean non-zero (v1
  # abort), never a raw 'No such file' crash. ---
  out="$( cd "$inv002_dir" && bash "$CHORES_AUTH" check-capability /nonexistent/hook.sh 2>&1 )"; ec=$?
  if [ "$ec" -ne 0 ]; then
    pass "INV-012-c" "check-capability against an absent hook returns clean non-zero"
  else
    fail "INV-012-c" "absent hook path must yield a clean degrade (exit=$ec)"
  fi
else
  fail "INV-012-a" "scripts/chores-authorize.sh not found (check-capability unimplemented)"
  fail "INV-012-b" "scripts/chores-authorize.sh not found"
  fail "INV-012-c" "scripts/chores-authorize.sh not found"
fi

# ============================================================================
# INV-013: Legible affordance-failure messages (recovery UX)
# ============================================================================
section "INV-013: legible affordance-failure messages"

# A block caused by an affordance predicate failure must emit a distinct,
# affordance-aware message naming the failed leg AND the correct remediation
# (re-run /cchores <N>), NOT the generic lift-and-restore wall.

# --- INV-013-a [integration]: branch mismatch → the message must be genuinely
# affordance-aware (advisory tighten to the INV-013-c bar): it names the branch
# leg (marker.branch vs current) AND carries affordance/cchores context, AND is
# NOT the generic lift-and-restore wall. A bare 'branch' substring is not enough
# (the generic wall could coincidentally contain it). ---
res="$( cd "$inv002c_dir" && run_sfg "$(edit_json scripts/prune-scan.sh)" )"
err="$(sfg_err "$res")"
if printf '%s' "$err" | grep -qiE 'branch' \
   && printf '%s' "$err" | grep -qiE 'affordance|/cchores|marker|authoriz' \
   && ! printf '%s' "$err" | grep -qi 'lift-and-restore'; then
  pass "INV-013-a" "branch-mismatch block is affordance-aware (names branch leg + cchores/affordance context, not the generic wall)"
else
  fail "INV-013-a" "branch-mismatch block must be affordance-aware, name the branch leg, and avoid the generic lift-and-restore wall (got: '$err')"
fi

# --- INV-013-b [integration]: secret-floor block → message names 'secret-floor
# ... never affordance-eligible'. ---
res="$( cd "$inv003_dir" && run_sfg "$(edit_json id_rsa)" )"
err="$(sfg_err "$res")"
if printf '%s' "$err" | grep -qiE 'secret-floor|never affordance'; then
  pass "INV-013-b" "secret-floor block message names the secret-floor leg"
else
  fail "INV-013-b" "secret-floor block must name the floor leg (got: '$err')"
fi

# --- INV-013-c [integration]: out-of-scope path block → message names 'not in
# ... authorized scope' and points at re-run /cchores, NOT lift-and-restore. ---
res="$( cd "$inv002e_dir" && run_sfg "$(edit_json scripts/prune-scan.sh)" )"
err="$(sfg_err "$res")"
if printf '%s' "$err" | grep -qiE 'scope|authorized' \
   && printf '%s' "$err" | grep -qiE '/cchores'; then
  pass "INV-013-c" "out-of-scope block names the scope leg and points at re-run /cchores"
else
  fail "INV-013-c" "out-of-scope block must be affordance-aware with the /cchores remediation (got: '$err')"
fi

# --- INV-013-d [integration]: affordance-predicate block must NOT reuse the
# generic lift-and-restore wall for these failures. ---
if printf '%s' "$err" | grep -qi 'lift-and-restore'; then
  fail "INV-013-d" "affordance predicate failure emitted the generic lift-and-restore wall (misleading signpost)"
else
  pass "INV-013-d" "affordance predicate failure does not emit the generic lift-and-restore wall"
fi

# ============================================================================
# INV-014: Marker sole-writer + never-in-commit
# ============================================================================
section "INV-014: marker sole-writer"

# --- INV-014-a [structural]: the marker path + the writer (three forms) are in
# the hook DEFAULTS block. RED: absent today. ---
defaults_all="$(extract_defaults_block "$HOOK")"
[ -z "$defaults_all" ] && defaults_all="$(sed -n '/^DEFAULTS="/,/"$/p' "$HOOK")"
check_in_defaults() { printf '%s\n' "$defaults_all" | grep -qF "$1"; }
if check_in_defaults "$MARKER_REL"; then
  pass "INV-014-a1" "marker path is in SFG DEFAULTS"
else
  fail "INV-014-a1" "marker path $MARKER_REL missing from SFG DEFAULTS"
fi
miss=""
for form in "scripts/chores-authorize.sh" ".correctless/scripts/chores-authorize.sh" "chores-authorize.sh"; do
  check_in_defaults "$form" || miss="$miss $form"
done
if [ -z "$miss" ]; then
  pass "INV-014-a2" "chores-authorize.sh (all three forms) is in SFG DEFAULTS"
else
  fail "INV-014-a2" "chores-authorize.sh forms missing from DEFAULTS:$miss"
fi

# --- INV-014-b [structural]: the writer is registered in a
# scripts/sanctioned-*-writers.tsv registry against the marker path. ---
reg_hit=false
for tsv in "$REPO_DIR"/scripts/sanctioned-*-writers.tsv; do
  [ -f "$tsv" ] || continue
  if grep -q 'chores-authorize.sh' "$tsv" 2>/dev/null && grep -q "$MARKER_REL" "$tsv" 2>/dev/null; then
    reg_hit=true
  fi
done
if $reg_hit; then
  pass "INV-014-b" "chores-authorize.sh registered as the marker's sanctioned writer"
else
  fail "INV-014-b" "no sanctioned-*-writers.tsv registers chores-authorize.sh against the marker"
fi

# --- INV-014-c [structural]: SKILL.md excludes the marker via a disallowed-tools
# entry (allowed-tools globs have no exclusion syntax, R2-K). QA-002: PARSE the
# disallowed-tools frontmatter FIELD specifically (via get_frontmatter_field),
# never a whole-file grep — a whole-file grep would pass on a mere prose mention
# and give false assurance that the real frontmatter exclusion exists. ---
if [ -f "$CCHORES_SKILL" ]; then
  cchores_disallowed="$(get_frontmatter_field "$CCHORES_SKILL" "disallowed-tools" 2>/dev/null || true)"
  if printf '%s' "$cchores_disallowed" | grep -qF "Write($MARKER_REL)"; then
    pass "INV-014-c" "cchores SKILL disallowed-tools frontmatter field excludes Write($MARKER_REL)"
  else
    fail "INV-014-c" "cchores SKILL disallowed-tools frontmatter field missing Write($MARKER_REL) entry (got: '${cchores_disallowed:-<none>}')"
  fi
else
  fail "INV-014-c" "skills/cchores/SKILL.md not found"
fi

# --- INV-014-d [structural]: allowed-tools grants the writer (both forms) so the
# only cooperative write path to the marker is chores-authorize.sh. ---
if [ -f "$CCHORES_SKILL" ]; then
  if grep -qE 'Bash\(bash \.correctless/scripts/chores-authorize\.sh' "$CCHORES_SKILL" 2>/dev/null \
     && grep -qE 'Bash\(bash scripts/chores-authorize\.sh' "$CCHORES_SKILL" 2>/dev/null; then
    pass "INV-014-d" "cchores SKILL allowed-tools grants the writer (source + installed forms)"
  else
    fail "INV-014-d" "cchores SKILL allowed-tools missing chores-authorize.sh grants (AP-008 cross-check)"
  fi
else
  fail "INV-014-d" "skills/cchores/SKILL.md not found"
fi

# --- INV-014-e [structural]: marker never enters a commit — SKILL pins the
# marker cleanup to the git restore --staged .correctless/artifacts/ step
# (RS-024), NOT to any project's .gitignore shape. ---
if [ -f "$CCHORES_SKILL" ]; then
  if grep -qE 'git restore --staged .*\.correctless/artifacts' "$CCHORES_SKILL" 2>/dev/null; then
    pass "INV-014-e" "cchores SKILL strips the staged marker via git restore --staged .correctless/artifacts/"
  else
    fail "INV-014-e" "cchores SKILL missing the git restore --staged step for the marker (RS-024)"
  fi
else
  fail "INV-014-e" "skills/cchores/SKILL.md not found"
fi

# ============================================================================
# INV-015: Test-substrate fidelity (real writer↔reader, no-arg golden, parity)
# ============================================================================
section "INV-015: test-substrate fidelity"

# --- INV-015-a [integration]: pipe the REAL `chores-authorize.sh write` output
# into the REAL hook over a git fixture (writer↔reader format coupling). RED:
# writer absent. This is the AP-031 dormant-fixture cell — the marker is a new
# producer, so format-pinning + this real-coupling test are the guard. ---
inv015_dir="$(mktemp -d)"; register_cleanup "$inv015_dir"
setup_git_test_env "$inv015_dir" 7 "real-coupling" >/dev/null
if [ -f "$CHORES_AUTH" ]; then
  ( cd "$inv015_dir" && bash "$CHORES_AUTH" write --issue 7 --allowed-paths scripts/prune-scan.sh >/dev/null 2>&1 ) || true
  # The writer must have produced BOTH the marker and (per its lifecycle) a
  # manifest binding — then the real hook must ALLOW the scoped write.
  res="$( cd "$inv015_dir" && run_sfg "$(edit_json scripts/prune-scan.sh)" )"
  if [ -f "$inv015_dir/$MARKER_REL" ] && [ "$(sfg_exit "$res")" = "0" ]; then
    pass "INV-015-a" "real writer output feeds the real hook and yields an ALLOW (writer↔reader coupled)"
  else
    fail "INV-015-a" "real writer→hook coupling failed (marker present=$([ -f "$inv015_dir/$MARKER_REL" ] && echo yes || echo no), exit=$(sfg_exit "$res"))"
  fi
else
  fail "INV-015-a" "scripts/chores-authorize.sh not found (real writer↔reader coupling untestable)"
fi

# --- INV-015-b [integration]: marker schema is format-pinned to
# {branch, issue, run_id, allowed_paths, authorized_at}. If the writer exists,
# its real output must carry exactly those keys. ---
if [ -f "$CHORES_AUTH" ] && [ -f "$inv015_dir/$MARKER_REL" ]; then
  keys="$(jq -r 'keys | sort | join(",")' "$inv015_dir/$MARKER_REL" 2>/dev/null || echo "?")"
  if [ "$keys" = "allowed_paths,authorized_at,branch,issue,run_id" ]; then
    pass "INV-015-b" "real marker carries exactly the pinned schema keys"
  else
    fail "INV-015-b" "marker key set '$keys' ≠ pinned schema {branch,issue,run_id,allowed_paths,authorized_at}"
  fi
else
  fail "INV-015-b" "real marker not produced — schema pinning untestable (writer absent)"
fi

# --- INV-015-c [integration]: no-arg golden-output regression — the v1
# pre-selection abort output is produced by a CODED producer and matches a
# committed golden byte-for-byte (R2-R). RED: golden fixture + coded producer
# absent. ---
GOLDEN="$REPO_DIR/tests/fixtures/cchores-noarg-preselect-abort.golden"
if [ -f "$GOLDEN" ] && [ -f "$DIFF_CHECK" ]; then
  produced="$(printf '%s\n' "scripts/prune-scan.sh" | bash "$DIFF_CHECK" --mode no-arg --allowed-paths /dev/null 2>/dev/null || true)"
  if [ "$produced" = "$(cat "$GOLDEN")" ]; then
    pass "INV-015-c" "no-arg pre-selection abort output matches the committed golden byte-for-byte"
  else
    fail "INV-015-c" "no-arg golden mismatch (coded producer output diverged)"
  fi
else
  fail "INV-015-c" "no-arg golden fixture and/or coded producer absent (byte-for-byte regression untestable)"
fi

# --- INV-015-d [unit]: source-vs-installed script count parity
# count(scripts/*.sh) == count(correctless/scripts/*.sh) (AP-024/RS-025). ---
src_n="$(find "$REPO_DIR/scripts" -maxdepth 1 -name '*.sh' -type f 2>/dev/null | wc -l | tr -d ' ')"
dst_n="$(find "$REPO_DIR/correctless/scripts" -maxdepth 1 -name '*.sh' -type f 2>/dev/null | wc -l | tr -d ' ')"
if [ "$src_n" = "$dst_n" ] && [ "$src_n" != "0" ]; then
  pass "INV-015-d" "scripts/*.sh count ($src_n) == correctless/scripts/*.sh count ($dst_n)"
else
  fail "INV-015-d" "script count parity broken (src=$src_n dst=$dst_n) — chores-authorize.sh must sync"
fi

# --- INV-015-e [structural]: the shared setup_git_test_env helper is defined and
# used by this suite (F9 — no divergent ad-hoc fixtures). Self-check that the
# helper exists as a function. ---
if declare -f setup_git_test_env >/dev/null 2>&1; then
  pass "INV-015-e" "shared setup_git_test_env helper is defined and used by every git cell"
else
  fail "INV-015-e" "shared setup_git_test_env helper missing"
fi

# ============================================================================
# PRH-001: No affordance in no-arg mode
# ============================================================================
section "PRH-001: no affordance in no-arg mode"

# --- PRH-001-a [structural]: no marker-write on the no-arg path. The SKILL must
# guard the writer invocation behind explicit-issue mode. We require an
# explicit-issue conditional near the writer call. ---
if [ -f "$CCHORES_SKILL" ]; then
  # Heuristic tripwire: a marker write must be co-located with explicit-issue
  # language, never with the auto-select/no-arg path.
  if grep -qE 'chores-authorize.sh (write|.*write)' "$CCHORES_SKILL" 2>/dev/null \
     && grep -qiE 'explicit(-| )issue|/cchores <?N>?|explicit.*mode' "$CCHORES_SKILL" 2>/dev/null; then
    pass "PRH-001-a" "SKILL gates the marker writer behind explicit-issue mode"
  else
    fail "PRH-001-a" "SKILL does not visibly gate the marker writer behind explicit-issue mode"
  fi
else
  fail "PRH-001-a" "skills/cchores/SKILL.md not found"
fi

# --- PRH-001-b [integration]: a no-arg run with a protected target aborts at
# pre-selection (v1). Modeled via cchores-diff-check.sh --mode no-arg. ---
if [ -f "$DIFF_CHECK" ]; then
  out="$(printf '%s\n' "scripts/prune-scan.sh" | bash "$DIFF_CHECK" --mode no-arg --allowed-paths /dev/null 2>/dev/null || true)"
  if printf '%s' "$out" | grep -qi '^abort'; then
    pass "PRH-001-b" "no-arg mode aborts on any protected target (v1 PRH-003 unchanged)"
  else
    fail "PRH-001-b" "no-arg mode must abort on a protected target (got: '$out')"
  fi
else
  fail "PRH-001-b" "scripts/cchores-diff-check.sh not found"
fi

# ============================================================================
# PRH-002: Affordance never relaxes secret floor / custom_patterns / own guards
# ============================================================================
section "PRH-002: floor/custom/guards never relaxed"

# Secret floor (canonicalization-edge) blocked with a valid marker (subset of
# INV-003, restated as the prohibition surface).
res="$( cd "$inv003_dir" && run_sfg "$(edit_json 'secrets/../.env')" )"
[ "$(sfg_exit "$res")" = "2" ] \
  && pass "PRH-002-a" "canonicalization-edge secret 'secrets/../.env' BLOCKED with a valid marker" \
  || fail "PRH-002-a" "canonicalization-edge secret must be BLOCKED (got exit $(sfg_exit "$res"))"

# custom_patterns never writable under a marker (subset of INV-002-f).
res="$( cd "$inv002f_dir" && run_sfg "$(edit_json src/special.conf)" )"
[ "$(sfg_exit "$res")" = "2" ] \
  && pass "PRH-002-b" "custom_patterns path never writable under a marker" \
  || fail "PRH-002-b" "custom_patterns path must stay BLOCKED (got exit $(sfg_exit "$res"))"

# Own guard (override-scrutiny.sh) never writable under a marker (subset of INV-008-d2).
res="$( cd "$inv008_dir" && run_sfg "$(edit_json scripts/override-scrutiny.sh)" )"
[ "$(sfg_exit "$res")" = "2" ] \
  && pass "PRH-002-c" "security guard override-scrutiny.sh never writable under a marker" \
  || fail "PRH-002-c" "override-scrutiny.sh must stay BLOCKED (got exit $(sfg_exit "$res"))"

# ABS-045 doc must gain the conditional-allow framing + See-link ABS-047
# (documentation obligation load-bearing for the capability change).
if [ -f "$ABSTRACTIONS" ]; then
  abs045="$(awk '/^### ABS-045/{f=1} f{print} /^### ABS-04[6-9]/{if(f && !/^### ABS-045/)exit}' "$ABSTRACTIONS" 2>/dev/null)"
  if printf '%s' "$abs045" | grep -qiE 'conditional-allow' \
     && printf '%s' "$abs045" | grep -qi 'ABS-047'; then
    pass "PRH-002-d" "ABS-045 documents the conditional-allow carve-out and See-links ABS-047"
  else
    fail "PRH-002-d" "ABS-045 not updated for conditional-allow / missing ABS-047 See-link"
  fi
else
  fail "PRH-002-d" "docs/architecture/abstractions.md not found"
fi

# ============================================================================
# PRH-003: Never merge; ≤1 comment (inherited, restated)
# ============================================================================
section "PRH-003: never merge (inherited)"

# --- PRH-003-a [structural]: cchores allowed-tools must not grant a merge
# capability (no `gh pr merge` / `git merge` in allowed-tools). ---
if [ -f "$CCHORES_SKILL" ]; then
  al="$(get_frontmatter_field "$CCHORES_SKILL" "allowed-tools" 2>/dev/null || sed -n '/^allowed-tools:/,/^[a-z]/p' "$CCHORES_SKILL")"
  if printf '%s' "$al" | grep -qiE 'pr merge|git merge|gh pr merge'; then
    fail "PRH-003-a" "cchores allowed-tools appears to grant a merge capability"
  else
    pass "PRH-003-a" "cchores allowed-tools grants no merge capability (never-merge preserved)"
  fi
else
  fail "PRH-003-a" "skills/cchores/SKILL.md not found"
fi

# --- PRH-003-b [structural]: the second PAT-001 carve-out in
# hooks-pretooluse.md keeps every failure/ambiguity path exit-2 (R2-N) — the
# rule file must document the conditional-allow as gated on a fully-verified
# marker predicate and cross-link INV-011. ---
if [ -f "$PAT001_RULE" ]; then
  if grep -qiE 'conditional-allow|chores.*affordance|second carve-out' "$PAT001_RULE" 2>/dev/null; then
    pass "PRH-003-b" "hooks-pretooluse.md documents the second (conditional-allow) carve-out"
  else
    fail "PRH-003-b" "hooks-pretooluse.md missing the second carve-out (conditional-allow gated, INV-011 cross-link)"
  fi
else
  fail "PRH-003-b" ".claude/rules/hooks-pretooluse.md not found"
fi

# --- PRH-003-c [structural]: sfg-deliverable.md 'When this rule applies' gains
# chores-authorize.sh (three-form) as a new AP-037 deliverable (R2-L / EA-004). ---
if [ -f "$SFG_DELIVERABLE_RULE" ]; then
  if grep -q 'chores-authorize.sh' "$SFG_DELIVERABLE_RULE" 2>/dev/null; then
    pass "PRH-003-c" "sfg-deliverable.md enumerates chores-authorize.sh as an AP-037 deliverable"
  else
    fail "PRH-003-c" "sfg-deliverable.md 'When this rule applies' missing chores-authorize.sh (R2-L)"
  fi
else
  fail "PRH-003-c" ".claude/rules/sfg-deliverable.md not found"
fi

# ============================================================================
# QA-001: single source of truth for the protected-path set
# ============================================================================
section "QA-001: single-source protected set (no legacy mirror)"

# --- QA-001-a [structural]: the untagged _SFG_LEGACY_EXACT_LINE_MIRROR is GONE
# from both the source hook and its mirror — no second source of truth that could
# silently drift from the tagged DEFAULTS (AP-005 class). ---
qa001_ok=1; qa001_why=""
for f in "$HOOK" "$HOOK_MIRROR"; do
  if [ -f "$f" ]; then
    if grep -q '_SFG_LEGACY_EXACT_LINE_MIRROR' "$f" 2>/dev/null; then
      qa001_ok=0; qa001_why="${qa001_why}${f}:mirror present; "
    fi
  else
    qa001_ok=0; qa001_why="${qa001_why}${f} absent; "
  fi
done
if [ "$qa001_ok" -eq 1 ]; then
  pass "QA-001-a" "_SFG_LEGACY_EXACT_LINE_MIRROR deleted from source + mirror (single source of truth)"
else
  fail "QA-001-a" "a second protected-set source of truth persists: ${qa001_why}"
fi

# --- QA-001-b [structural]: the protected set is defined EXACTLY ONCE — a single
# ^DEFAULTS=" ... ^"$ block and no sibling top-level list variable holding paths.
# (grep -c prints "0" itself on no-match, so count lines instead of `|| echo 0`.) ---
if [ -f "$HOOK" ]; then
  defaults_opens="$(grep -E '^DEFAULTS="' "$HOOK" 2>/dev/null | wc -l | tr -d ' ')"
  # Any other top-level string var whose name ends in MIRROR/DEFAULTS would be a
  # second source of truth for the protected set.
  extra_lists="$(grep -E '^[A-Za-z_][A-Za-z0-9_]*(MIRROR|DEFAULTS)=' "$HOOK" 2>/dev/null | grep -vE '^DEFAULTS="' | wc -l | tr -d ' ')"
  if [ "$defaults_opens" = "1" ] && [ "$extra_lists" = "0" ]; then
    pass "QA-001-b" "protected set defined once (single tagged DEFAULTS block, no sibling list)"
  else
    fail "QA-001-b" "protected set not single-source (DEFAULTS opens=$defaults_opens, extra lists=$extra_lists)"
  fi
else
  fail "QA-001-b" "hooks/sensitive-file-guard.sh not found"
fi

# ============================================================================
# QA-003: run_id is a genuine per-run nonce (two-run replay, same branch)
# ============================================================================
section "QA-003: per-run nonce (two-run replay on the same branch)"

if [ -f "$CHORES_AUTH" ]; then
  qa003_dir="$(mktemp -d)"; register_cleanup "$qa003_dir"
  setup_git_test_env "$qa003_dir" 7 "widget" >/dev/null
  QA003_BRANCH="chore/issue-7-widget"
  qa003_manifest="$(chore_run_manifest "$qa003_dir" "$QA003_BRANCH")"

  # Run N: mint a marker+manifest, capture run_id_N and the leaked marker bytes.
  ( cd "$qa003_dir" && bash "$CHORES_AUTH" write --issue 7 --allowed-paths scripts/prune-scan.sh ) >/dev/null 2>&1
  rid1="$(jq -r '.run_id // empty' "$qa003_dir/$MARKER_REL" 2>/dev/null || true)"
  leaked_marker="$(cat "$qa003_dir/$MARKER_REL" 2>/dev/null || true)"

  # Run N+1 on the SAME branch WITHOUT clearing — do_write must mint a FRESH
  # run_id (never reuse the persisted manifest run_id).
  ( cd "$qa003_dir" && bash "$CHORES_AUTH" write --issue 7 --allowed-paths scripts/prune-scan.sh ) >/dev/null 2>&1
  rid2="$(jq -r '.run_id // empty' "$qa003_dir/$MARKER_REL" 2>/dev/null || true)"

  if [ -n "$rid1" ] && [ -n "$rid2" ] && [ "$rid1" != "$rid2" ]; then
    pass "QA-003-a" "consecutive writes on the same branch mint DISTINCT run_ids (fresh nonce, no reuse)"
  else
    fail "QA-003-a" "run_id was REUSED across runs on the same branch (rid1='$rid1' rid2='$rid2')"
  fi

  # Leaked-marker rejection: restore run N's marker (run_id_N) against the current
  # manifest (run_id_{N+1}). SFG must BLOCK the affordance write (run_id mismatch).
  printf '%s' "$leaked_marker" > "$qa003_dir/$MARKER_REL"
  res="$( cd "$qa003_dir" && run_sfg "$(edit_json scripts/prune-scan.sh)" )"
  if [ "$(sfg_exit "$res")" = "2" ]; then
    pass "QA-003-b" "a leaked marker from run N is REJECTED in run N+1 (run_id mismatch → BLOCK)"
  else
    fail "QA-003-b" "leaked run-N marker must be rejected in run N+1 (got exit $(sfg_exit "$res"))"
  fi

  # do_clear rotates run_id out of the manifest so no stale run_id can be inherited.
  ( cd "$qa003_dir" && bash "$CHORES_AUTH" clear ) >/dev/null 2>&1
  cleared_rid="$(jq -r '.run_id // empty' "$qa003_manifest" 2>/dev/null || true)"
  if [ -z "$cleared_rid" ]; then
    pass "QA-003-c" "clear rotates run_id out of the run manifest (stale run_id cannot be inherited)"
  else
    fail "QA-003-c" "clear left a run_id in the manifest ('$cleared_rid') — stale run_id could be inherited"
  fi
else
  fail "QA-003-a" "scripts/chores-authorize.sh not found"
  fail "QA-003-b" "scripts/chores-authorize.sh not found"
  fail "QA-003-c" "scripts/chores-authorize.sh not found"
fi

# ============================================================================
# QA-004: manifest filename derivation agrees with lib.sh branch_slug()
# (AP-031 real-producer for the manifest filename)
# ============================================================================
section "QA-004: manifest path derivation == branch_slug()"

if [ -f "$CHORES_AUTH" ]; then
  qa004_dir="$(mktemp -d)"; register_cleanup "$qa004_dir"
  setup_git_test_env "$qa004_dir" 12 "align" >/dev/null
  QA004_BRANCH="chore/issue-12-align"
  # The REAL writer must create the manifest at the branch_slug()-derived path
  # (with the 6-char md5 suffix), NOT the legacy '/'->'-' no-hash path.
  ( cd "$qa004_dir" && bash "$CHORES_AUTH" write --issue 12 --allowed-paths scripts/prune-scan.sh ) >/dev/null 2>&1
  expected_manifest="$(chore_run_manifest "$qa004_dir" "$QA004_BRANCH")"
  legacy_manifest="$qa004_dir/.correctless/artifacts/chore-run-${QA004_BRANCH//\//-}.json"
  if [ -f "$expected_manifest" ]; then
    pass "QA-004-a" "writer created the manifest at chore-run-{branch_slug}.json (agrees with branch_slug())"
  else
    fail "QA-004-a" "writer did not create the branch_slug()-derived manifest ($(basename "$expected_manifest"))"
  fi
  # The legacy no-hash name must NOT be what the writer used (unless it happens to
  # equal the branch_slug form, which it does not — branch_slug appends a hash).
  if [ "$expected_manifest" != "$legacy_manifest" ] && [ ! -f "$legacy_manifest" ]; then
    pass "QA-004-b" "writer did NOT use the legacy no-hash manifest name (divergence from convention closed)"
  else
    fail "QA-004-b" "writer used the legacy no-hash manifest name (branch_slug() alignment incomplete)"
  fi
  # The hook agrees: piping the REAL writer's marker into the hook ALLOWS the
  # affordance write, which requires the hook to read the SAME branch_slug manifest.
  res="$( cd "$qa004_dir" && run_sfg "$(edit_json scripts/prune-scan.sh)" )"
  if [ "$(sfg_exit "$res")" = "0" ]; then
    pass "QA-004-c" "hook reads the SAME branch_slug()-derived manifest as the writer (real writer↔hook agreement)"
  else
    fail "QA-004-c" "hook did not agree with the writer's manifest derivation (got exit $(sfg_exit "$res"))"
  fi
else
  for c in a b c; do fail "QA-004-$c" "scripts/chores-authorize.sh not found"; done
fi

# ============================================================================
# QA-005: uniform fail-closed gate contract in cchores-diff-check.sh
# ============================================================================
section "QA-005: every abort path returns non-zero (fail-closed)"

# --- QA-005-a [structural]: every `echo "abort..."` line in cchores-diff-check.sh
# is paired with a NON-ZERO return, so a consumer wired to $? fails closed. ---
if [ -f "$DIFF_CHECK" ]; then
  offending="$(awk '
    function ret_of(s,   t) { if (match(s,/return[[:space:]]+[0-9]+/)) { t=substr(s,RSTART,RLENGTH); gsub(/[^0-9]/,"",t); return t } return "" }
    /echo[^=]*"abort/ {
      r=ret_of($0)
      if (r != "") { if (r=="0") print NR": same-line return 0: "$0; next }
      inab=1; abln=NR; next
    }
    inab {
      r=ret_of($0)
      if (r != "") { if (r=="0") print abln": abort followed by return 0"; inab=0 }
    }
    END {}
  ' "$DIFF_CHECK")"
  if [ -z "$offending" ]; then
    pass "QA-005-a" "every abort path in cchores-diff-check.sh returns non-zero (fail-closed)"
  else
    fail "QA-005-a" "an abort path returns 0 (fails OPEN for a \$?-wired consumer): $offending"
  fi
else
  fail "QA-005-a" "scripts/cchores-diff-check.sh not found"
fi

# --- QA-005-b [behavioral]: the diff gate exits NON-ZERO on a secret-floor abort
# (consistent with do_check_classification), not just emitting an abort token. ---
if [ -f "$DIFF_CHECK" ]; then
  ap_qa005="$(mktemp)"; register_cleanup "$ap_qa005"
  printf '%s\n' "scripts/prune-scan.sh" > "$ap_qa005"
  ec_qa=0
  printf '%s\n' "id_rsa" | bash "$DIFF_CHECK" --mode explicit --allowed-paths "$ap_qa005" >/dev/null 2>&1 || ec_qa=$?
  if [ "$ec_qa" -ne 0 ]; then
    pass "QA-005-b" "secret-floor abort exits non-zero (exit=$ec_qa) — \$?-wired consumer fails closed"
  else
    fail "QA-005-b" "secret-floor abort exited 0 — a \$?-wired consumer would fail OPEN"
  fi
  # ok path still exits 0
  ec_ok=0
  printf '%s\n' "scripts/prune-scan.sh" | bash "$DIFF_CHECK" --mode explicit --allowed-paths "$ap_qa005" >/dev/null 2>&1 || ec_ok=$?
  if [ "$ec_ok" -eq 0 ]; then
    pass "QA-005-c" "the ok path still exits 0 (no over-broad failure)"
  else
    fail "QA-005-c" "ok path unexpectedly exited non-zero ($ec_ok)"
  fi
else
  fail "QA-005-b" "scripts/cchores-diff-check.sh not found"
  fail "QA-005-c" "scripts/cchores-diff-check.sh not found"
fi

# ============================================================================
# Mini-audit round 3 regressions (MA-001 .. MA-011)
# ============================================================================
section "MA-round-3: mini-audit fix regressions"

# --- MA-001 [integration]: cchores-diff-check.sh must FAIL CLOSED when
# canonicalize_path is unavailable (lib.sh stubbed). A pre-fix diff-check would
# emit `ok` exit 0 (fail OPEN) because _canon()/is_secret_floor() return empty and
# every gate leg passes. Stage the REAL diff-check + REAL hook + a STUB lib.sh with
# no canonicalize_path, and assert a non-zero abort (never a silent ok/pass). ---
ma001_stage="$(mktemp -d)"; register_cleanup "$ma001_stage"
mkdir -p "$ma001_stage/scripts" "$ma001_stage/hooks"
if cp "$DIFF_CHECK" "$ma001_stage/scripts/cchores-diff-check.sh" 2>/dev/null \
   && cp "$HOOK" "$ma001_stage/hooks/sensitive-file-guard.sh" 2>/dev/null; then
  cat > "$ma001_stage/scripts/lib.sh" <<'STUBLIB'
#!/usr/bin/env bash
# Stub lib.sh WITHOUT canonicalize_path / require_canonicalize_or_die — simulates
# an absent/stale install. branch_slug provided so unrelated paths don't explode.
branch_slug() { printf '%s' "${1//\//-}"; }
config_file() { printf '%s' ".correctless/config/workflow-config.json"; }
STUBLIB
  ma001_ec=0
  ma001_out="$(printf '%s\n' "scripts/prune-scan.sh" | bash "$ma001_stage/scripts/cchores-diff-check.sh" --mode explicit --allowed-paths /dev/null 2>&1)" || ma001_ec=$?
  # Discriminating assertion: the STARTUP probe exits specifically 3 with a
  # canonicalize_path + `bash setup` remediation — NOT the undefined pre-fix
  # behavior (a set -u unbound-var crash / a spurious shared-doc abort / a silent
  # ok). A pre-fix diff-check would never produce exit 3 with this message.
  if [ "$ma001_ec" -eq 3 ] \
     && printf '%s' "$ma001_out" | grep -qi 'canonicalize_path' \
     && printf '%s' "$ma001_out" | grep -qi 'bash setup' \
     && ! printf '%s' "$ma001_out" | grep -qi '^ok'; then
    pass "MA-001" "cchores-diff-check.sh startup probe fails closed (exit 3 + canonicalize_path/bash-setup remediation) when canonicalize_path is unavailable"
  else
    fail "MA-001" "diff-check did not fail closed via the startup probe (ec=$ma001_ec out='$ma001_out')"
  fi
else
  fail "MA-001" "could not stage diff-check + hook + stub lib for the fail-closed cell"
fi

# --- MA-002 [integration]: an affordance file blocked with NO marker on a
# NON-chore branch must emit an ADDITIVE message — BOTH the AP-037 lift-and-restore
# signpost (sfg-deliverable) AND the /cchores hint — never replace one with the
# other. ---
ma002_dir="$(mktemp -d)"; register_cleanup "$ma002_dir"
mkdir -p "$ma002_dir/.correctless/artifacts" "$ma002_dir/scripts"
(
  cd "$ma002_dir" \
    && git init -q \
    && git config user.email t@example.com \
    && git config user.name tester \
    && git checkout -q -b main \
    && : > scripts/.keep \
    && git add -A \
    && git commit -q -m init
) >/dev/null 2>&1 || true
res="$( cd "$ma002_dir" && run_sfg "$(edit_json scripts/prune-scan.sh)" )"
ma002_err="$(sfg_err "$res")"
if [ "$(sfg_exit "$res")" = "2" ] \
   && printf '%s' "$ma002_err" | grep -qi 'sfg-deliverable' \
   && printf '%s' "$ma002_err" | grep -qi '/cchores'; then
  pass "MA-002" "affordance file + no marker on a non-chore branch → additive message (lift-and-restore signpost AND /cchores hint)"
else
  fail "MA-002" "no-marker affordance block must be additive (exit=$(sfg_exit "$res") err='$ma002_err')"
fi

# --- MA-005 [integration]: a valid marker + an # other-floor target (scripts/lib.sh)
# → autonomous-mode-correct block message. It must NOT contain the human
# lift-and-restore / "outside Claude Code" wall, and MUST name the
# affordance/authorization + human-review path. Reuses inv008_dir (valid marker,
# allowed_paths includes lib.sh, branch chore/issue-42-fix-thing). ---
res="$( cd "$inv008_dir" && run_sfg "$(edit_json scripts/lib.sh)" )"
ma005_err="$(sfg_err "$res")"
if [ "$(sfg_exit "$res")" = "2" ] \
   && ! printf '%s' "$ma005_err" | grep -qi 'lift-and-restore' \
   && ! printf '%s' "$ma005_err" | grep -qi 'outside Claude Code' \
   && printf '%s' "$ma005_err" | grep -qiE 'affordance|authoriz' \
   && printf '%s' "$ma005_err" | grep -qi 'human review'; then
  pass "MA-005" "marker-present + # other-floor target → autonomous-mode message (no lift-and-restore / outside-CC; names authorization + human review)"
else
  fail "MA-005" "other-floor-under-marker block must be autonomous-aware, not the generic wall (err='$ma005_err')"
fi

# --- MA-006 [integration]: the affordance ALLOW path must fail CLOSED when the
# config is PRESENT but its custom_patterns are unparsable (a user's re-protection
# must not silently lapse into an allow). (a) corrupt config → BLOCK; (b) config
# ABSENT → still ALLOW. ---
ma006_dir="$(mktemp -d)"; register_cleanup "$ma006_dir"
setup_git_test_env "$ma006_dir" 42 "fix-thing" >/dev/null
write_marker_and_manifest "$ma006_dir" "chore/issue-42-fix-thing" 42 "RUN-42-abc" '["scripts/prune-scan.sh"]'
printf '{ this is not valid json' > "$ma006_dir/.correctless/config/workflow-config.json"
res="$( cd "$ma006_dir" && run_sfg "$(edit_json scripts/prune-scan.sh)" )"
if [ "$(sfg_exit "$res")" = "2" ]; then
  pass "MA-006-a" "affordance ALLOW fails CLOSED on a present-but-corrupt config (custom_patterns unparsable → BLOCK)"
else
  fail "MA-006-a" "corrupt config must force the floor on the affordance ALLOW branch (got exit $(sfg_exit "$res"))"
fi
# (b) config ABSENT (no file) → the affordance still ALLOWS (INV-002-a shape).
ma006b_dir="$(mktemp -d)"; register_cleanup "$ma006b_dir"
setup_git_test_env "$ma006b_dir" 42 "fix-thing" >/dev/null
write_marker_and_manifest "$ma006b_dir" "chore/issue-42-fix-thing" 42 "RUN-42-abc" '["scripts/prune-scan.sh"]'
res="$( cd "$ma006b_dir" && run_sfg "$(edit_json scripts/prune-scan.sh)" )"
if [ "$(sfg_exit "$res")" = "0" ]; then
  pass "MA-006-b" "config ABSENT + valid marker + affordance path still ALLOWS (degrade is config-present-only)"
else
  fail "MA-006-b" "config-absent must not block the affordance (got exit $(sfg_exit "$res"))"
fi

# --- MA-007 [structural+integration]: no SFG block message may instruct the human
# to "name this path" / pass a path / --allowed-paths to /cchores (PRH-003: /cchores
# accepts only an issue number). ---
ma007_bad="$(grep -nE '/cchores[^"]*naming this path|/cchores[^"]*--allowed-paths|Re-run /cchores <N> [^"]*\.(sh|md|json|ts)' "$HOOK" 2>/dev/null || true)"
res="$( cd "$inv002e_dir" && run_sfg "$(edit_json scripts/prune-scan.sh)" )"
ma007_err="$(sfg_err "$res")"
if [ -z "$ma007_bad" ] && ! printf '%s' "$ma007_err" | grep -qi 'naming this path'; then
  pass "MA-007" "no block message instructs an impossible '/cchores <N> naming this path' / path argument"
else
  fail "MA-007" "a block message instructs passing a path to /cchores (structural='$ma007_bad' err='$ma007_err')"
fi

# --- MA-008 [integration]: a fail-closed refuse on a corrupt run manifest must
# NAME the manifest path (+ recovery). ---
if [ -f "$CHORES_AUTH" ]; then
  ma008_dir="$(mktemp -d)"; register_cleanup "$ma008_dir"
  setup_git_test_env "$ma008_dir" 5 "widget" >/dev/null
  ma008_manifest="$(chore_run_manifest "$ma008_dir" "chore/issue-5-widget")"
  printf '{ broken manifest' > "$ma008_manifest"
  ma008_out="$( cd "$ma008_dir" && bash "$CHORES_AUTH" write --issue 5 --allowed-paths scripts/prune-scan.sh 2>&1 )"; ma008_ec=$?
  if [ "$ma008_ec" -ne 0 ] && printf '%s' "$ma008_out" | grep -qF "$(basename "$ma008_manifest")"; then
    pass "MA-008" "corrupt-manifest refuse names the manifest path + recovery (exit=$ma008_ec)"
  else
    fail "MA-008" "corrupt-manifest refuse must name the manifest path (exit=$ma008_ec out='$ma008_out')"
  fi
else
  fail "MA-008" "scripts/chores-authorize.sh not found"
fi

# --- MA-009 [structural]: the SKILL step-1 capability handshake must confirm
# .correctless/scripts/cchores-diff-check.sh exists (not just chores-authorize.sh)
# — the affordance's authoritative gates dispatch it. ---
if [ -f "$CCHORES_SKILL" ]; then
  # The handshake step names check-capability AND both dispatched scripts.
  if grep -q 'check-capability' "$CCHORES_SKILL" 2>/dev/null \
     && grep -qE '\.correctless/scripts/cchores-diff-check\.sh' "$CCHORES_SKILL" 2>/dev/null \
     && grep -qiE 'confirm .*cchores-diff-check\.sh|cchores-diff-check\.sh.* exist|both .*chores-authorize.*cchores-diff-check|complete set' "$CCHORES_SKILL" 2>/dev/null; then
    pass "MA-009" "SKILL step-1 handshake confirms cchores-diff-check.sh existence (complete dispatched-script set)"
  else
    fail "MA-009" "SKILL step-1 handshake does not confirm cchores-diff-check.sh existence"
  fi
else
  fail "MA-009" "skills/cchores/SKILL.md not found"
fi

# --- MA-010 [unit, helper]: the shared bare-verb-normalized glob_covers detects a
# BARE Write as covering the marker path and a BARE Bash as covering the writer
# invocation (the property the vacuous parenthesized-only INV-004-a/d greps
# missed). Negatives must NOT flag. ---
ma010_ok=1
glob_covers "Write" "$MARKER_REL" || ma010_ok=0                                  # bare Write covers marker
glob_covers "Bash" "bash scripts/chores-authorize.sh write --issue 5" || ma010_ok=0  # bare Bash covers writer cmd
glob_covers "Write(.correctless/artifacts/*)" "$MARKER_REL" || ma010_ok=0        # scoped covering glob
if glob_covers "Write(docs/*)" "$MARKER_REL"; then ma010_ok=0; fi                # non-covering must NOT flag
if glob_covers "Read" "$MARKER_REL"; then ma010_ok=0; fi                         # non-write verb must NOT flag
if [ "$ma010_ok" -eq 1 ]; then
  pass "MA-010" "shared glob_covers normalizes bare Write/Bash to their maximal glob (covers marker/writer); non-covering grants do not flag"
else
  fail "MA-010" "shared glob_covers bare-verb normalization incorrect (false green/red risk restored)"
fi

# --- MA-011 [structural, honesty]: the writer comment no longer claims
# UNCONDITIONAL inertness — it scopes the claim to 'a later /cchores run' and names
# the crash-window as an accepted residual. ---
if [ -f "$CHORES_AUTH" ]; then
  if ! grep -qiE 'always inert on a later run|leaked marker is always inert' "$CHORES_AUTH" 2>/dev/null \
     && grep -qiE 'crash-window' "$CHORES_AUTH" 2>/dev/null \
     && grep -qiE 'AGAINST A LATER /cchores RUN|against a later /cchores run' "$CHORES_AUTH" 2>/dev/null; then
    pass "MA-011" "writer comment scopes inertness to a later /cchores run and names the crash-window accepted residual"
  else
    fail "MA-011" "writer comment still over-claims unconditional inertness (or omits the crash-window residual)"
  fi
else
  fail "MA-011" "scripts/chores-authorize.sh not found"
fi

# --- MA-012 [integration, hostile-input]: config-degrade fail-closed must ALSO
# cover a TYPE-CONFUSED custom_patterns. A well-formed config whose
# protected_files.custom_patterns is a bare STRING (not an array), re-protecting an
# affordance path, parses cleanly (jq exits 0) yet extracts to empty — the STEP-7
# extraction filter alone leaves _SFG_CUSTOM_READ_FAILED=0, so the user's explicit
# (if malformed) re-protection would silently lapse into an ALLOW. The affordance
# ALLOW branch must fail CLOSED on present-but-not-an-array custom_patterns exactly
# like the unparsable-config case (MA-006-a). (a) string custom_patterns re-
# protecting an affordance path, under a VALID full-match marker naming that path →
# BLOCK. (b) custom_patterns ABSENT under the same valid marker → still ALLOW
# (proves the type check does not over-block). ---
ma012_dir="$(mktemp -d)"; register_cleanup "$ma012_dir"
setup_git_test_env "$ma012_dir" 42 "fix-thing" >/dev/null
write_marker_and_manifest "$ma012_dir" "chore/issue-42-fix-thing" 42 "RUN-42-abc" '["scripts/prune-scan.sh"]'
# Well-formed JSON, but custom_patterns is a bare string (wrong type) re-protecting
# the affordance path scripts/prune-scan.sh.
printf '{ "protected_files": { "custom_patterns": "scripts/prune-scan.sh" } }' \
  > "$ma012_dir/.correctless/config/workflow-config.json"
res="$( cd "$ma012_dir" && run_sfg "$(edit_json scripts/prune-scan.sh)" )"
if [ "$(sfg_exit "$res")" = "2" ]; then
  pass "MA-012-a" "affordance ALLOW fails CLOSED on a type-confused (string) custom_patterns → BLOCK (parse-success ≠ type-valid)"
else
  fail "MA-012-a" "type-confused custom_patterns must force the floor on the affordance ALLOW branch (got exit $(sfg_exit "$res"))"
fi
# (b) custom_patterns ABSENT (no config file) under the same valid marker → ALLOW.
ma012b_dir="$(mktemp -d)"; register_cleanup "$ma012b_dir"
setup_git_test_env "$ma012b_dir" 42 "fix-thing" >/dev/null
write_marker_and_manifest "$ma012b_dir" "chore/issue-42-fix-thing" 42 "RUN-42-abc" '["scripts/prune-scan.sh"]'
res="$( cd "$ma012b_dir" && run_sfg "$(edit_json scripts/prune-scan.sh)" )"
if [ "$(sfg_exit "$res")" = "0" ]; then
  pass "MA-012-b" "custom_patterns ABSENT + valid marker + affordance path still ALLOWS (type check does not over-block)"
else
  fail "MA-012-b" "absent custom_patterns must not block the affordance (got exit $(sfg_exit "$res"))"
fi

# ============================================================================
# Summary
# ============================================================================
summary "cchores protected-file affordance (PRH-003 v2)"
