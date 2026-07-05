#!/usr/bin/env bash
# Correctless — audit-trail.sh session-identity field tests
# Spec: .correctless/specs/instructionsloaded-hook.md — INV-015
#
# INV-015: hooks/audit-trail.sh extracts the harness stdin `session_id` (the
# SAME documented field the InstructionsLoaded hook reads — NOT lib.sh's
# PID-based get_current_session_id) and includes it in every entry alongside
# the existing ts, phase, tool, file, branch fields. Additive + backward-compatible.
#
# RED phase: audit-trail.sh does not yet extract session_id, so the entry it
# emits will lack the field and INV-015a/b MUST FAIL.
#
# Run from repo root: bash tests/test-audit-trail.sh

# shellcheck disable=SC1090,SC1091,SC2016
source "$(dirname "${BASH_SOURCE[0]}")/test-helpers.sh"

echo "audit-trail.sh Session-Field Tests (INV-015)"
echo "============================================"

AUDIT_HOOK="$REPO_DIR/hooks/audit-trail.sh"
LIB_SH="$REPO_DIR/scripts/lib.sh"
FIXTURES="$REPO_DIR/tests/fixtures"

ENV_DIRS=()
cleanup_envs() { local d; for d in "${ENV_DIRS[@]:-}"; do [ -n "$d" ] && rm -rf "$d"; done; }
trap cleanup_envs EXIT

# Build a temp git project with the audit-trail runtime layout, run the hook
# once with a payload carrying session_id, and return the produced entry.
run_audit_with_session() {  # $1 = session_id value ; prints last audit-trail line
  local sid="$1"
  local d; d="$(mktemp -d "/tmp/correctless-audit-XXXXXX")"
  ENV_DIRS+=("$d")
  mkdir -p "$d/hooks" "$d/scripts" "$d/.correctless/artifacts" "$d/.correctless/config"
  cp "$AUDIT_HOOK" "$d/hooks/audit-trail.sh" 2>/dev/null || return 1
  cp "$LIB_SH" "$d/scripts/lib.sh" 2>/dev/null || return 1
  (
    cd "$d" || exit 1
    git init -q 2>/dev/null
    git checkout -b feature/il-audit-test -q 2>/dev/null || git branch -M feature/il-audit-test 2>/dev/null
    # Compute the branch slug the hook will use, then seed a matching state file.
    # shellcheck disable=SC1091
    slug="$(source scripts/lib.sh 2>/dev/null; branch_slug 2>/dev/null)"
    [ -n "$slug" ] || slug="unknown"
    printf '{"phase":"tdd-impl","task":"il-audit"}\n' > ".correctless/artifacts/workflow-state-${slug}.json"
    printf '{"patterns":{"test_file":"tests/test-*.sh","source_file":"hooks/*.sh"},"workflow":{"intensity":"low"}}\n' > ".correctless/config/workflow-config.json"
    payload="$(jq -nc --arg s "$sid" '{tool_name:"Edit", tool_input:{file_path:"hooks/foo.sh"}, session_id:$s}')"
    printf '%s' "$payload" | bash hooks/audit-trail.sh >/dev/null 2>&1 || true
  )
  local trail
  trail="$(ls "$d"/.correctless/artifacts/audit-trail-*.jsonl 2>/dev/null | head -1)"
  [ -n "$trail" ] && tail -1 "$trail" || printf ''
}

# ============================================================================
# INV-015a: entry includes session_id sourced from the harness stdin field
# ============================================================================
section "INV-015a: audit entry carries harness session_id"

if [ ! -f "$AUDIT_HOOK" ]; then
  fail "INV-015a" "hooks/audit-trail.sh not found"
else
  line="$(run_audit_with_session "sess-abc-123")"
  if [ -n "$line" ] && printf '%s' "$line" | jq -e . >/dev/null 2>&1; then
    got="$(printf '%s' "$line" | jq -r '.session_id // "<<absent>>"' 2>/dev/null)"
    if [ "$got" = "sess-abc-123" ]; then
      pass "INV-015a" "audit entry session_id == harness stdin session_id"
    else
      fail "INV-015a" "audit entry session_id is '$got' (want 'sess-abc-123' from stdin)"
    fi
    # existing fields retained (backward-compatible additive change)
    keep_ok=true
    for f in ts phase tool file branch; do
      printf '%s' "$line" | jq -e "has(\"$f\")" >/dev/null 2>&1 || keep_ok=false
    done
    if [ "$keep_ok" = true ]; then pass "INV-015b" "existing fields ts/phase/tool/file/branch retained"; else fail "INV-015b" "an existing audit field was dropped"; fi
  else
    fail "INV-015a" "no valid audit entry produced (RED: session field / run absent)"
    fail "INV-015b" "no audit entry to inspect for retained fields"
  fi
fi

# ============================================================================
# audit-trail ts FORMAT: the FRESHLY-EMITTED entry's .ts must be ISO-8601
# (date -u +%FT%TZ) — the SAME format hooks/instructions-loaded.sh emits and the
# /cwtf `.ts // .timestamp` join + /cmetrics staleness math depend on. The
# INV-015a/b checks above assert .ts PRESENCE only, and the AP-031 fixture checks
# below read a STATIC file — neither would catch a mutant that changes the live
# emission to epoch (date +%s -> "1751..."). This runs the hook and locks the
# generated format, mirroring test-instructions-loaded.sh's INV-003-ts regex.
# ============================================================================
section "audit-trail ts format: fresh entry .ts is ISO-8601"

if [ -f "$AUDIT_HOOK" ]; then
  ts_line="$(run_audit_with_session "sess-ts-check")"
  if [ -n "$ts_line" ] && printf '%s' "$ts_line" | jq -e . >/dev/null 2>&1; then
    fresh_ts="$(printf '%s' "$ts_line" | jq -r '.ts' 2>/dev/null)"
    if printf '%s' "$fresh_ts" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'; then
      pass "INV-015-ts" "fresh audit entry .ts matches ISO-8601 ^YYYY-MM-DDTHH:MM:SSZ\$ (date -u +%FT%TZ)"
    else
      fail "INV-015-ts" "audit entry .ts '$fresh_ts' is not ISO-8601 — epoch/format drift breaks /cwtf join + /cmetrics staleness"
    fi
  else
    fail "INV-015-ts" "no valid audit entry produced to inspect .ts"
  fi
else
  fail "INV-015-ts" "hooks/audit-trail.sh not found"
fi

# ============================================================================
# INV-015c: empty/null session_id is shown as such (never treated as a match)
# ============================================================================
section "INV-015c: empty session_id shown as-is"

if [ -f "$AUDIT_HOOK" ]; then
  line="$(run_audit_with_session "")"
  if [ -n "$line" ] && printf '%s' "$line" | jq -e 'has("session_id")' >/dev/null 2>&1; then
    val="$(printf '%s' "$line" | jq -r '.session_id' 2>/dev/null)"
    if [ "$val" = "" ] || [ "$val" = "null" ]; then
      pass "INV-015c" "empty stdin session_id surfaced as empty/null"
    else
      fail "INV-015c" "empty session_id was rewritten to '$val'"
    fi
    # QA-001 / INV-015: canonical-empty->null. An empty stdin session_id MUST be
    # emitted as JSON null (not ""), matching hooks/instructions-loaded.sh. This
    # is the producer half of the guarantee that a "" session can never form its
    # own /cwtf group or match a real session — it collapses to the same shape as
    # a genuinely absent session.
    if printf '%s' "$line" | jq -e '.session_id == null' >/dev/null 2>&1; then
      pass "INV-015c-null" "empty stdin session_id normalized to JSON null (not empty string)"
    else
      _stype="$(printf '%s' "$line" | jq -r '.session_id | type' 2>/dev/null)"
      fail "INV-015c-null" "empty session_id emitted as JSON $_stype, want null (canonical-empty->null)"
    fi
  else
    fail "INV-015c" "entry lacks session_id field for empty-session case (RED)"
    fail "INV-015c-null" "no audit entry to inspect for canonical-empty->null"
  fi
else
  fail "INV-015c" "hooks/audit-trail.sh not found"
  fail "INV-015c-null" "hooks/audit-trail.sh not found"
fi

# ============================================================================
# INV-015d: session_id sourced from stdin, NOT lib.sh get_current_session_id
# (grep guard — the field must be extracted alongside the other stdin fields)
# ============================================================================
section "INV-015d: session_id source is stdin, not PID-based"

if [ -f "$AUDIT_HOOK" ]; then
  if grep -qE 'session_id.*\\\(\.session_id|\.session_id' "$AUDIT_HOOK"; then
    pass "INV-015d-src" "audit-trail extracts .session_id from stdin"
  else
    fail "INV-015d-src" "audit-trail does not extract stdin .session_id (INV-015)"
  fi
  if grep -q 'get_current_session_id' "$AUDIT_HOOK"; then
    fail "INV-015d-nopid" "audit-trail uses lib.sh get_current_session_id (PID-based — forbidden source)"
  else
    pass "INV-015d-nopid" "audit-trail does not use PID-based get_current_session_id"
  fi
else
  fail "INV-015d-src" "hooks/audit-trail.sh not found"
  fail "INV-015d-nopid" "hooks/audit-trail.sh not found"
fi

# ============================================================================
# INV-015 (AP-031): presentation parsing tested against a REAL audit-trail
# entry (verbatim repo copy), not a hand-authored fixture.
# Source: .correctless/artifacts/audit-trail-*.jsonl (verbatim lines)
# ============================================================================
section "INV-015 AP-031: parse real audit-trail fixture"

AUDIT_REAL="$FIXTURES/audit-trail-real.jsonl"
if [ -f "$AUDIT_REAL" ]; then
  bad="$(jq -Rc 'fromjson? // empty' "$AUDIT_REAL" 2>/dev/null | grep -c . )"
  total="$(grep -c . "$AUDIT_REAL")"
  if [ "$bad" = "$total" ] && [ "$total" -ge 3 ]; then
    pass "INV-015-real" "real audit-trail fixture parses via try/catch consumer contract"
  else
    fail "INV-015-real" "real audit-trail fixture did not fully parse ($bad/$total)"
  fi
  # .ts // .timestamp resolves on the real mixed-shape lines
  resolved="$(jq -R 'fromjson? | (.ts // .timestamp) // empty' "$AUDIT_REAL" 2>/dev/null | grep -c .)"
  if [ "$resolved" -ge 3 ]; then pass "INV-015-real-time" ".ts // .timestamp resolves on real entries"; else fail "INV-015-real-time" ".ts // .timestamp resolved on $resolved real entries"; fi
else
  fail "INV-015-real" "audit-trail-real.jsonl fixture missing"
  fail "INV-015-real-time" "audit-trail-real.jsonl fixture missing"
fi

# ############################################################################
# #244 (narrowed) — file-repo attribution for audit-trail.sh
# Spec: .correctless/specs/hook-repo-root-for.md  (Rules R-001..R-008)
#
# audit-trail.sh must attribute each recorded event to the EDITED FILE's own git
# repo F (resolved via a local `_resolve_file_repo`), NOT the hook's cwd. These
# tests use REAL `git init` fixtures throughout (AP-031 / spec R-3: never a
# hand-rolled `.git`). They MUST all FAIL against the current cwd-based hook.
# ############################################################################

echo ""
echo "audit-trail.sh File-Repo Attribution Tests (#244 — R-001..R-008)"
echo "================================================================"

# --- Shared fixture harness -------------------------------------------------
# One installed copy of the hook + lib.sh (the hook sources ../scripts/lib.sh
# relative to its own BASH_SOURCE, so it resolves lib.sh regardless of cwd).
HARNESS="$(mktemp -d "/tmp/correctless-atrepo-XXXXXX")"
ENV_DIRS+=("$HARNESS")
mkdir -p "$HARNESS/hooks" "$HARNESS/scripts"
cp "$AUDIT_HOOK" "$HARNESS/hooks/audit-trail.sh" 2>/dev/null || true
cp "$LIB_SH" "$HARNESS/scripts/lib.sh" 2>/dev/null || true
HOOK_UNDER_TEST="$HARNESS/hooks/audit-trail.sh"
RUN_ERR="$HARNESS/last-stderr"

# repo_slug PATH — the branch slug a repo's branch maps to (matches what the
# migrated hook derives from `git -C F branch --show-current` + branch_slug).
repo_slug() { ( cd "$1" 2>/dev/null && source "$LIB_SH" 2>/dev/null; branch_slug 2>/dev/null ); }

# mk_repo PATH BRANCH ARTIFACTS(yes/no) [INTENSITY=low] [COMMIT=no]
# Creates a REAL git repo (AP-031). With ARTIFACTS=yes, seeds a
# .correctless/artifacts/workflow-state-<slug>.json + a workflow-config.json.
mk_repo() {
  local path="$1" branch="$2" arts="$3" inten="${4:-low}" commit="${5:-no}"
  mkdir -p "$path"
  (
    cd "$path" || exit 1
    git init -q 2>/dev/null
    git config user.email "t@example.com" 2>/dev/null
    git config user.name "tester" 2>/dev/null
    git checkout -b "$branch" -q 2>/dev/null || git branch -M "$branch" 2>/dev/null
    if [ "$commit" = yes ]; then
      echo seed > seed.txt; git add seed.txt 2>/dev/null; git commit -qm seed 2>/dev/null
    fi
  )
  if [ "$arts" = yes ]; then
    mkdir -p "$path/.correctless/artifacts" "$path/.correctless/config"
    local slug; slug="$(repo_slug "$path")"
    printf '{"phase":"tdd-impl","task":"x"}\n' > "$path/.correctless/artifacts/workflow-state-${slug}.json"
    printf '{"patterns":{"test_file":"tests/test-*.sh","source_file":"hooks/*.sh"},"workflow":{"intensity":"%s"}}\n' \
      "$inten" > "$path/.correctless/config/workflow-config.json"
  fi
}

trail_file()     { echo "$1/.correctless/artifacts/audit-trail-$(repo_slug "$1").jsonl"; }
adherence_file() { echo "$1/.correctless/artifacts/adherence-state-$(repo_slug "$1").json"; }
count_lines()    { local f="$1"; if [ -f "$f" ]; then grep -c . "$f" 2>/dev/null || true; else echo 0; fi; }
inode_of()       { stat -c '%i' "$1" 2>/dev/null || stat -f '%i' "$1" 2>/dev/null || echo "NOINODE"; }
seed_trail()     { local tf; tf="$(trail_file "$1")"; mkdir -p "$(dirname "$tf")"
                   printf '{"ts":"x","phase":"p","tool":"Edit","file":"seed","branch":"%s"}\n' "$2" > "$tf"; }

# run_hook CWD PAYLOAD — runs the hook with a controlled cwd; sets RC + RUN_ERR.
run_hook() {
  ( cd "$1" 2>/dev/null && printf '%s' "$2" | bash "$HOOK_UNDER_TEST" >/dev/null 2>"$RUN_ERR" )
  RC=$?
}
payload_edit()      { jq -nc --arg f "$1" '{tool_name:"Edit",tool_input:{file_path:$f}}'; }
payload_bash()      { jq -nc --arg c "$1" '{tool_name:"Bash",tool_input:{command:$c}}'; }
payload_multiedit() { jq -nc '{tool_name:"MultiEdit",tool_input:{edits:[$ARGS.positional[]|{file_path:.}]}}' --args "$@"; }

# fresh per-test root under /tmp (outside any git repo)
new_root() { local d; d="$(mktemp -d "/tmp/correctless-atroot-XXXXXX")"; ENV_DIRS+=("$d"); echo "$d"; }

# ============================================================================
# R-001 [unit]: local `_resolve_file_repo <path>` resolver
#   - two REAL git repos A,B: resolving "$B/f" while cwd is A prints B + rc 0
#   - a /tmp-style non-repo path prints nothing + rc 1
#   - a nonexistent leaf under B resolves via nearest existing ancestor
# The resolver is defined inside audit-trail.sh (R-008). We extract the function
# body from the hook source and exercise it functionally. RED: the function does
# not exist yet, so extraction is empty and every assertion fails.
# ============================================================================
section "R-001: _resolve_file_repo resolves the edited file's repo (functional)"

# Extract a shell function definition (fn() { ... } closed by a col-0 `}`).
extract_fn() {
  awk -v fn="$2" '
    index($0, fn "() {") == 1 { grab=1 }
    grab { print }
    grab && $0 == "}" { exit }
  ' "$1"
}

R1_ROOT="$(new_root)"; R1_A="$R1_ROOT/A"; R1_B="$R1_ROOT/B"; R1_NOGIT="$R1_ROOT/nogit"
mk_repo "$R1_A" feature/repo-a no
mk_repo "$R1_B" feature/repo-b no
mkdir -p "$R1_NOGIT"   # NOT a git repo

fn_src="$(extract_fn "$AUDIT_HOOK" "_resolve_file_repo")"
if [ -z "$fn_src" ]; then
  fail "R-001-in-repo"     "_resolve_file_repo not defined in audit-trail.sh (RED)"
  fail "R-001-non-repo"    "_resolve_file_repo not defined in audit-trail.sh (RED)"
  fail "R-001-nearest"     "_resolve_file_repo not defined in audit-trail.sh (RED)"
else
  eval "$fn_src"
  expect_B="$( cd "$R1_B" && git rev-parse --show-toplevel 2>/dev/null )"

  # in-repo: cwd is A, path is in B -> prints B (proves it does NOT use cwd), rc 0
  out="$( cd "$R1_A" && _resolve_file_repo "$R1_B/f" )"; rc=$?
  if [ "$rc" = 0 ] && [ "$out" = "$expect_B" ]; then
    pass "R-001-in-repo" "resolves \$B/f to B's root while cwd is A (rc 0)"
  else
    fail "R-001-in-repo" "got '$out' rc=$rc, want '$expect_B' rc=0"
  fi

  # non-repo: prints nothing + rc 1 (the distinction attribution needs to no-op)
  if git -C "$R1_NOGIT" rev-parse --show-toplevel >/dev/null 2>&1; then
    skip "R-001-non-repo" "tmp dir unexpectedly inside a git repo"
  else
    out="$( _resolve_file_repo "$R1_NOGIT/f" )"; rc=$?
    if [ "$rc" = 1 ] && [ -z "$out" ]; then
      pass "R-001-non-repo" "non-repo path prints nothing + rc 1"
    else
      fail "R-001-non-repo" "got '$out' rc=$rc, want empty rc=1"
    fi
  fi

  # nearest-existing-ancestor: a nonexistent deep leaf under B still resolves to B
  out="$( _resolve_file_repo "$R1_B/no/such/deep/leaf" )"; rc=$?
  if [ "$rc" = 0 ] && [ "$out" = "$expect_B" ]; then
    pass "R-001-nearest" "nonexistent leaf resolves via nearest existing ancestor (B)"
  else
    fail "R-001-nearest" "got '$out' rc=$rc, want '$expect_B' rc=0"
  fi
fi

# ============================================================================
# R-002 [integration]: attribute every .correctless/artifacts/ derivation to F.
# 3-cell matrix over real repos A,B (cwd is always A):
#   cell1 (A-has, B-none) -> no-op; A's trail line-count unchanged
#   cell2 (A-none, B-has) -> lands under B (today's :12 cwd bail DROPS this)
#   cell3 (A-has, B-has)  -> under B, A untouched; record .branch carries B's
# Plus a full-mode ADHERENCE cell: the adherence-state file lands under B.
# ============================================================================
section "R-002 cell1: A-has, B-none -> no-op, A trail unchanged"
R2_R="$(new_root)"; R2A="$R2_R/A"; R2B="$R2_R/B"
mk_repo "$R2A" feature/repo-a yes            # A: artifacts + state
mk_repo "$R2B" feature/repo-b no             # B: real repo, NO artifacts
seed_trail "$R2A" feature/repo-a             # pre-existing A record -> before=1
before="$(count_lines "$(trail_file "$R2A")")"
run_hook "$R2A" "$(payload_edit "$R2B/f")"
after="$(count_lines "$(trail_file "$R2A")")"
if [ "$before" = 1 ] && [ "$after" = 1 ] && [ "$RC" = 0 ]; then
  pass "R-002-cell1" "editing B/f (B has no workflow) is a no-op; A trail unchanged ($before->$after)"
else
  fail "R-002-cell1" "A trail changed $before->$after (rc=$RC) — file-in-B misattributed to cwd/A"
fi

section "R-002 cell2: A-none, B-has -> record lands under B (:12 drop today)"
R2b_R="$(new_root)"; R2bA="$R2b_R/A"; R2bB="$R2b_R/B"
mk_repo "$R2bA" feature/repo-a no            # A: NO artifacts (cwd bail today)
mk_repo "$R2bB" feature/repo-b yes           # B: artifacts + state
run_hook "$R2bA" "$(payload_edit "$R2bB/f")"
cB="$(count_lines "$(trail_file "$R2bB")")"
if [ "$cB" = 1 ]; then
  br="$(jq -r '.branch' "$(trail_file "$R2bB")" 2>/dev/null | tail -1)"
  if [ "$br" = "feature/repo-b" ]; then
    pass "R-002-cell2" "record lands under B with .branch=feature/repo-b (cwd-A has no artifacts)"
  else
    fail "R-002-cell2" "record under B but .branch='$br' (want feature/repo-b, not cwd/A's)"
  fi
else
  fail "R-002-cell2" "B trail has $cB records (want 1) — cwd bail silently dropped the event"
fi

section "R-002 cell3: A-has, B-has -> under B, A untouched, .branch is B's"
R2c_R="$(new_root)"; R2cA="$R2c_R/A"; R2cB="$R2c_R/B"
mk_repo "$R2cA" feature/repo-a yes
mk_repo "$R2cB" feature/repo-b yes
seed_trail "$R2cA" feature/repo-a            # A before=1
run_hook "$R2cA" "$(payload_edit "$R2cB/f")"
cA="$(count_lines "$(trail_file "$R2cA")")"
cB="$(count_lines "$(trail_file "$R2cB")")"
brB="$(jq -r '.branch' "$(trail_file "$R2cB")" 2>/dev/null | tail -1)"
if [ "$cB" = 1 ] && [ "$cA" = 1 ] && [ "$brB" = "feature/repo-b" ]; then
  pass "R-002-cell3" "record under B (.branch=feature/repo-b); A untouched (A=$cA B=$cB)"
else
  fail "R-002-cell3" "A=$cA (want 1) B=$cB (want 1) B.branch='$brB' (want feature/repo-b)"
fi

# QA-003: A=low / B=high (NOT both-high) so the cell distinguishes config-read-
# from-F from config-read-from-cwd. If the hook read IS_FULL from cwd/A (low), it
# would be lite-mode and create NO adherence anywhere; a full-mode adherence file
# under B can only appear if intensity was read from F=B (high).
section "R-002 adherence: full-mode config read from F (B=high), not cwd (A=low)"
R2d_R="$(new_root)"; R2dA="$R2d_R/A"; R2dB="$R2d_R/B"
mk_repo "$R2dA" feature/repo-a yes low       # cwd A: LOW intensity (lite-mode)
mk_repo "$R2dB" feature/repo-b yes high      # B: HIGH intensity (full-mode)
run_hook "$R2dA" "$(payload_edit "$R2dB/foo.sh")"
adhB="$(adherence_file "$R2dB")"; adhA="$(adherence_file "$R2dA")"
if [ -s "$adhB" ] && [ ! -e "$adhA" ]; then
  pass "R-002-adh" "full-mode adherence under B (config intensity read from F=high, not cwd/A=low)"
else
  fail "R-002-adh" "adherence misattributed (B exists=$([ -s "$adhB" ] && echo y || echo n), A exists=$([ -e "$adhA" ] && echo y || echo n)) — config read from cwd not F"
fi

# ============================================================================
# R-003 [integration]: branch from `git -C F branch --show-current`, guarded
# against the empty->cwd leak. A detached-HEAD B file must NOT attribute under
# cwd/A's slug. B HAS artifacts+state so the early no-artifacts bail is NOT the
# reason for the no-op — the empty-branch guard is (branch_slug treats an empty
# arg identically to no arg and falls back to the CWD branch: lib.sh:105).
# ============================================================================
section "R-003: detached-HEAD B does not attribute under cwd/A's slug (guard)"
R3_R="$(new_root)"; R3A="$R3_R/A"; R3B="$R3_R/B"
mk_repo "$R3A" feature/repo-a yes            # cwd repo: artifacts + state
mk_repo "$R3B" feature/repo-b yes low yes    # B: artifacts + a commit, then detach
( cd "$R3B" && git checkout --detach -q 2>/dev/null || git checkout -q "$(git rev-parse HEAD)" 2>/dev/null )
seed_trail "$R3A" feature/repo-a             # A before=1
det="$( cd "$R3B" && git branch --show-current 2>/dev/null )"   # should be empty
run_hook "$R3A" "$(payload_edit "$R3B/f")"
after="$(count_lines "$(trail_file "$R3A")")"
bcount="$(count_lines "$(trail_file "$R3B")")"
if [ -z "$det" ] && [ "$after" = 1 ]; then
  pass "R-003" "detached B (empty branch) -> no attribution under cwd/A (A trail stayed 1)"
else
  fail "R-003" "A trail=$after (want 1); detached-branch='$det' — empty->cwd leak or cwd bug"
fi
# QA-002: the no-op contract is 'write NOTHING anywhere'. B HAS artifacts+state,
# so the earlier assertion (A unchanged) does not cover B as a candidate sink. A
# hypothetical impl that wrote a fallback record under B would pass R-003 above
# but fail here. Pin the second half of the no-op contract: B's trail is empty.
if [ "$bcount" = 0 ]; then
  pass "R-003-noleak" "detached B wrote NOTHING under B either (no-op writes at no sink)"
else
  fail "R-003-noleak" "B trail=$bcount (want 0) — detached-HEAD run wrote a record under B"
fi

# ============================================================================
# R-004 [integration]: same-TARGET guarantee for cwd==F (not string equality).
# Editing the SAME repo-R file first from cwd==R (the "today" target) and then
# from a DIFFERENT cwd must append to the SAME trail file (same inode). Asserts
# same-target by inode + append, never string equality.
# RED: the second run (cwd!=R) does not reach R's trail on the cwd-based hook.
# ============================================================================
section "R-004: cwd==F and cwd!=F hit the SAME trail inode (same-target)"
R4_R="$(new_root)"; R4R="$R4_R/R"; R4O="$R4_R/O"
mk_repo "$R4R" feature/repo-r yes            # R: the edited file's repo
mk_repo "$R4O" feature/repo-o no             # O: some other cwd, no artifacts
tfR="$(trail_file "$R4R")"
run_hook "$R4R" "$(payload_edit "$R4R/hooks/foo.sh")"   # run1: cwd==F (baseline)
c1="$(count_lines "$tfR")"; i1="$(inode_of "$tfR")"
run_hook "$R4O" "$(payload_edit "$R4R/hooks/foo.sh")"   # run2: cwd!=F, same file
c2="$(count_lines "$tfR")"; i2="$(inode_of "$tfR")"
if [ "$c1" = 1 ] && [ "$c2" = 2 ] && [ "$i1" = "$i2" ] && [ "$i1" != "NOINODE" ]; then
  pass "R-004" "both runs append to R's trail; same inode (same-target, not string-eq)"
else
  fail "R-004" "run1 count=$c1 inode=$i1; run2 count=$c2 inode=$i2 (want 1,2,equal) — cwd!=F missed R's target"
fi

# ============================================================================
# R-005 [integration]: PostToolUse fail-open preserved.
#   a) corrupt state file under F -> exit 0 (preservation)
#   b) git unavailable/failing -> exit 0, no error output (preservation)
#   c) file in NO git repo (resolver rc 1) -> exit 0 AND no misattribution to
#      the active cwd workflow (genuinely RED: today's hook logs it under cwd/A)
# ============================================================================
section "R-005a: corrupt state file -> exit 0"
R5a_R="$(new_root)"; R5aR="$R5a_R/R"
mk_repo "$R5aR" feature/repo-r yes
printf '{not valid json' > "$R5aR/.correctless/artifacts/workflow-state-$(repo_slug "$R5aR").json"
run_hook "$R5aR" "$(payload_edit "$R5aR/hooks/foo.sh")"
if [ "$RC" = 0 ]; then pass "R-005a" "corrupt state -> exit 0 (fail-open)"; else fail "R-005a" "exit $RC on corrupt state (want 0)"; fi

section "R-005b: git unavailable/failing -> exit 0, no error output"
R5b_R="$(new_root)"; R5bR="$R5b_R/R"; R5bBIN="$R5b_R/bin"
mk_repo "$R5bR" feature/repo-r yes
mkdir -p "$R5bBIN"; printf '#!/bin/sh\nexit 127\n' > "$R5bBIN/git"; chmod +x "$R5bBIN/git"
R5b_PAYLOAD="$(payload_edit "$R5bR/hooks/foo.sh")"
( cd "$R5bR" 2>/dev/null && printf '%s' "$R5b_PAYLOAD" | PATH="$R5bBIN:$PATH" bash "$HOOK_UNDER_TEST" >/dev/null 2>"$RUN_ERR" )
rc_nogit=$?
if [ "$rc_nogit" = 0 ] && [ ! -s "$RUN_ERR" ]; then
  pass "R-005b" "git failing -> exit 0, no stderr (degrades, never errors)"
else
  fail "R-005b" "exit $rc_nogit / stderr=$( [ -s "$RUN_ERR" ] && echo present || echo empty ) (want 0/empty)"
fi

section "R-005c: file in no git repo -> exit 0 AND no misattribution to cwd/A"
R5c_R="$(new_root)"; R5cA="$R5c_R/A"; R5cNOGIT="$R5c_R/nogit"
mk_repo "$R5cA" feature/repo-a yes           # active cwd workflow
mkdir -p "$R5cNOGIT"                         # NOT a git repo
seed_trail "$R5cA" feature/repo-a            # A before=1
run_hook "$R5cA" "$(payload_edit "$R5cNOGIT/f")"
after="$(count_lines "$(trail_file "$R5cA")")"
if [ "$RC" = 0 ] && [ "$after" = 1 ]; then
  pass "R-005c" "no-repo file -> exit 0, no misattribution to cwd/A (A stayed 1)"
else
  fail "R-005c" "rc=$RC A trail=$after (want 0/1) — no-repo file logged under cwd/A"
fi

# ============================================================================
# R-006 [integration]: cross-repo MultiEdit attributes per target, order kept.
# edits = [A/a1, A/a2, B/b1] -> A-trail exactly 2 (a1 then a2), B-trail exactly 1.
# RED: cwd-based hook writes all three under cwd/A (A=3, B=0).
# ============================================================================
section "R-006: cross-repo MultiEdit -> A gets 2 (ordered), B gets 1"
R6_R="$(new_root)"; R6A="$R6_R/A"; R6B="$R6_R/B"
mk_repo "$R6A" feature/repo-a yes
mk_repo "$R6B" feature/repo-b yes
run_hook "$R6A" "$(payload_multiedit "$R6A/a1" "$R6A/a2" "$R6B/b1")"
tfA="$(trail_file "$R6A")"; tfB="$(trail_file "$R6B")"
cA="$(count_lines "$tfA")"; cB="$(count_lines "$tfB")"
orderA="$(jq -r '.file' "$tfA" 2>/dev/null | tr '\n' '|')"
fileB="$(jq -r '.file' "$tfB" 2>/dev/null | tail -1)"
if [ "$cA" = 2 ] && [ "$cB" = 1 ] && [ "$orderA" = "$R6A/a1|$R6A/a2|" ] && [ "$fileB" = "$R6B/b1" ]; then
  pass "R-006" "A=2 in input order, B=1; no cross-repo leakage"
else
  fail "R-006" "A=$cA (want 2, order '$orderA') B=$cB (want 1, file '$fileB') — MultiEdit not grouped per repo"
fi

# ============================================================================
# R-006-nested [integration] (QA-001 regression): NESTED repo / submodule.
# A REAL nested git repo lives at P/sub inside parent repo P. A MultiEdit touches
# the PARENT file (P/pfile) FIRST, then the NESTED file (P/sub/nfile). The old
# prefix-cache resolved P first, then matched P/sub/nfile against "$P"/* and
# misattributed it to P — silent wrong-repo attribution, the exact class this
# feature eliminates and the R-1 mitigation forbids. Each file MUST land in its
# OWN repo's trail: P gets exactly pfile, P/sub gets exactly nfile.
# ============================================================================
section "R-006-nested: parent-first MultiEdit — nested-repo file lands in ITS OWN trail"
R6n_R="$(new_root)"; R6nP="$R6n_R/P"; R6nSUB="$R6n_R/P/sub"
mk_repo "$R6nP" feature/parent yes           # parent repo P: real git init + artifacts
mk_repo "$R6nSUB" feature/nested yes         # REAL nested git init at P/sub + artifacts
# Parent file FIRST, nested file SECOND — the ordering that made the prefix cache
# attribute the nested file to the parent.
run_hook "$R6nP" "$(payload_multiedit "$R6nP/pfile" "$R6nSUB/nfile")"
tfP="$(trail_file "$R6nP")"; tfSUB="$(trail_file "$R6nSUB")"
cP="$(count_lines "$tfP")"; cSUB="$(count_lines "$tfSUB")"
fileP="$(jq -r '.file' "$tfP" 2>/dev/null | tail -1)"
fileSUB="$(jq -r '.file' "$tfSUB" 2>/dev/null | tail -1)"
if [ "$cP" = 1 ] && [ "$cSUB" = 1 ] && [ "$fileP" = "$R6nP/pfile" ] && [ "$fileSUB" = "$R6nSUB/nfile" ]; then
  pass "R-006-nested" "parent file -> P trail (1); nested file -> P/sub trail (1); no parent-misattribution"
else
  fail "R-006-nested" "P=$cP (want 1, file '$fileP') P/sub=$cSUB (want 1, file '$fileSUB') — nested file misattributed to parent"
fi

# ============================================================================
# R-007 [integration]: Bash-target attribution matches Edit-target.
# A Bash write whose get_target_file resolves into $B/foo.sh attributes under B,
# same as an Edit to $B/foo.sh. RED: cwd-based hook logs the Bash write under A.
# ============================================================================
section "R-007: Bash write to \$B/foo.sh attributes under B (== Edit)"
R7_R="$(new_root)"; R7A="$R7_R/A"; R7B="$R7_R/B"
mk_repo "$R7A" feature/repo-a yes
mk_repo "$R7B" feature/repo-b yes
run_hook "$R7A" "$(payload_bash "touch $R7B/foo.sh")"
tfB="$(trail_file "$R7B")"
cB="$(count_lines "$tfB")"
bfile="$(jq -r '.file' "$tfB" 2>/dev/null | tail -1)"
btool="$(jq -r '.tool' "$tfB" 2>/dev/null | tail -1)"
if [ "$cB" = 1 ] && [ "$bfile" = "$R7B/foo.sh" ] && [ "$btool" = "Bash" ]; then
  # cross-check: an Edit to the same path attributes under B identically
  R7B2="$R7_R/B2"; mk_repo "$R7B2" feature/repo-b yes
  run_hook "$R7A" "$(payload_edit "$R7B2/foo.sh")"
  eEdit="$(jq -r '.file' "$(trail_file "$R7B2")" 2>/dev/null | tail -1)"
  if [ "$eEdit" = "$R7B2/foo.sh" ]; then
    pass "R-007" "Bash write to \$B/foo.sh attributes under B, consistent with Edit"
  else
    fail "R-007" "Bash attributed under B but Edit did not (edit file='$eEdit')"
  fi
else
  fail "R-007" "B trail count=$cB file='$bfile' tool='$btool' — Bash target logged under cwd/A"
fi

# ============================================================================
# R-008: resolver lives in audit-trail.sh (not lib.sh), and audit-trail.sh is
# ABSENT from sensitive-file-guard.sh DEFAULTS (single-unprotected-file edit).
# ============================================================================
section "R-008: _resolve_file_repo local to audit-trail.sh; hook not SFG-protected"
if grep -Eq '^_resolve_file_repo\(\)[[:space:]]*\{' "$AUDIT_HOOK"; then
  pass "R-008-local" "_resolve_file_repo defined local to audit-trail.sh"
else
  fail "R-008-local" "_resolve_file_repo not defined in audit-trail.sh (RED)"
fi
# audit-trail.sh must NOT be a lib.sh function (R-008: local, not shared)
if grep -Eq '^_resolve_file_repo\(\)[[:space:]]*\{' "$LIB_SH"; then
  fail "R-008-notlib" "_resolve_file_repo leaked into lib.sh (R-008 says keep it local to the hook)"
else
  pass "R-008-notlib" "_resolve_file_repo is NOT in lib.sh (avoids AP-037 self-guard)"
fi
# single-file-edit property: audit-trail.sh is not in SFG DEFAULTS
SFG_HOOK="$REPO_DIR/hooks/sensitive-file-guard.sh"
if [ -f "$SFG_HOOK" ] && grep -q 'audit-trail\.sh' "$SFG_HOOK"; then
  fail "R-008-unprotected" "audit-trail.sh appears in sensitive-file-guard.sh (breaks single-file-edit property)"
else
  pass "R-008-unprotected" "audit-trail.sh absent from SFG DEFAULTS (single unprotected file edited)"
fi

# ============================================================================
# R-006-newline [integration] (MA-001, hostile-input): a single file_path whose
# value embeds a NEWLINE that names a SECOND real repo must NOT forge a phantom
# cross-repo audit record. The fan-out splits FILES on newlines (the in-band
# separator), so a crafted `file_path = "$A/real\n$B/forged"` would otherwise be
# read-split into two paths, each resolved and logged separately — silently
# forging a record into B's trail (cross-repo misattribution, the exact class
# this feature eliminates). Both A and B are REAL git repos WITH artifacts+state
# (they WOULD each log a genuine edit), so a leak would be observable. The tainted
# single path is skipped as a clean fail-open no-op: no record forged anywhere.
# Real `git init` fixtures only (AP-031); the newline is a LITERAL newline inside
# the JSON string value (jq --arg preserves it).
# ============================================================================
section "R-006-newline: newline-embedded file_path forges no cross-repo record (MA-001)"
R6nl_R="$(new_root)"; R6nlA="$R6nl_R/A"; R6nlB="$R6nl_R/B"
mk_repo "$R6nlA" feature/repo-a yes           # A: real repo, artifacts+state (would log)
mk_repo "$R6nlB" feature/repo-b yes           # B: real sibling repo, artifacts+state
# file_path is ONE JSON string carrying a literal newline that embeds B's real path.
R6nl_FP="$R6nlA/real"$'\n'"$R6nlB/forged"
R6nl_PAYLOAD="$(jq -nc --arg fp "$R6nl_FP" '{tool_name:"Write",tool_input:{file_path:$fp},session_id:"s"}')"
run_hook "$R6nlA" "$R6nl_PAYLOAD"
cA_nl="$(count_lines "$(trail_file "$R6nlA")")"
cB_nl="$(count_lines "$(trail_file "$R6nlB")")"
if [ "$RC" = 0 ] && [ "$cA_nl" = 0 ] && [ "$cB_nl" = 0 ]; then
  pass "R-006-newline" "newline-tainted file_path skipped as no-op; no forged record (A=$cA_nl B=$cB_nl, rc=$RC)"
else
  fail "R-006-newline" "A trail=$cA_nl B trail=$cB_nl (want 0/0), rc=$RC — newline injection forged a cross-repo record"
fi

# ============================================================================
# R-248 [integration]: REAL-shape single-file MultiEdit is logged.
# Issue #248: a REAL Claude Code MultiEdit call carries its single target at the
# TOP-LEVEL `.tool_input.file_path`; its `edits[]` entries hold only
# {old_string, new_string} — there is NO per-edit `.file_path`. The hook builds
# FILES from `.tool_input.edits[]?.file_path`, which is EMPTY for the real shape,
# so `[ -n "$FILES" ] || exit 0` bails and the MultiEdit is NEVER logged.
# Expected: a MultiEdit is attributed to `.tool_input.file_path`, like Edit/Write.
#
# NOTE: deliberately does NOT use payload_multiedit() (line 259) — that helper
# builds the SYNTHETIC {edits:[{file_path:...}]} shape that MASKS this bug. We
# construct the REAL top-level-file_path shape by hand with jq -nc.
# RED: fails today (FILES empty -> hook bails, trail stays 0).
# GREEN: passes once the MultiEdit branch reads top-level .tool_input.file_path.
# ============================================================================
section "R-248: real-shape single-file MultiEdit is logged (top-level file_path)"
R248_R="$(new_root)"; R248="$R248_R/R"
mk_repo "$R248" feature/repo-r yes            # real git repo + artifacts + state
tf248="$(trail_file "$R248")"
before248="$(count_lines "$tf248")"           # expect 0 (no trail yet)
# REAL MultiEdit shape: single target at TOP-LEVEL .tool_input.file_path; the
# edits[] entries carry ONLY {old_string,new_string} — NO per-edit file_path.
R248_TARGET="$R248/hooks/foo.sh"
R248_PAYLOAD="$(jq -nc --arg f "$R248_TARGET" \
  '{tool_name:"MultiEdit",tool_input:{file_path:$f,edits:[{old_string:"a",new_string:"b"}]},session_id:"s"}')"
run_hook "$R248" "$R248_PAYLOAD"
after248="$(count_lines "$tf248")"
file248="$(jq -r '.file' "$tf248" 2>/dev/null | tail -1)"
if [ "$before248" = 0 ] && [ "$after248" = 1 ] && [ "$RC" = 0 ] && [ "$file248" = "$R248_TARGET" ]; then
  pass "R-248" "real-shape MultiEdit logged 1 record attributed to top-level file_path ($before248->$after248)"
else
  fail "R-248" "trail $before248->$after248 (want 0->1), rc=$RC, .file='$file248' (want '$R248_TARGET') — real MultiEdit dropped (FILES empty, hook bailed)"
fi

summary "test-audit-trail"
