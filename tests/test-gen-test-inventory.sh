#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091,SC2086,SC2016,SC2317,SC2015,SC2034
# Correctless — Generated Test-Count Artifact + Generator Tests
# Feature: agent-context-count-sync (#219, Option 2)
# Spec: .correctless/specs/agent-context-count-sync.md
#
# Covers the GENERATOR + ARTIFACT + R-006(c) matrix cluster:
#   INV-001 (deterministic/idempotent artifact), INV-002 (shared count command
#   — pinned repo-root, pinned universe, parity), INV-003 (generator contract:
#   consumer guard, atomic write, tri-state fail-loud), INV-004 (R-006(c)
#   validation matrix), BND-001/002/003, PRH-001/003/004.
#
# RED expectation: scripts/gen-test-inventory.sh and tests/test-inventory.json
# do NOT exist yet, so every generator-dependent assertion FAILs with a
# controlled `FAIL:` line (never a harness crash). The wiring/SFG/allowed-tools
# rules live in tests/test-test-inventory-wiring.sh.
#
# Run from repo root: bash tests/test-gen-test-inventory.sh

source "$(dirname "${BASH_SOURCE[0]}")/test-helpers.sh"

echo "Generated Test-Count Artifact + Generator Tests (#219)"
echo "==========================================="

GEN="$REPO_DIR/scripts/gen-test-inventory.sh"
CONSUMER="$REPO_DIR/tests/test-ap031-fixture-divergence.sh"
ARTIFACT="$REPO_DIR/tests/test-inventory.json"

gen_present() { [ -f "$GEN" ]; }
have_git() { command -v git >/dev/null 2>&1; }

# Scratch root for all fixtures; cleaned on any exit.
TMPROOT="$(mktemp -d)"
cleanup() { git worktree prune >/dev/null 2>&1 || true; rm -rf "$TMPROOT" 2>/dev/null || true; }
trap cleanup EXIT

# --- portable helpers -------------------------------------------------------
_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  else shasum -a 256 "$1" | awk '{print $1}'; fi
}
_inode() { stat -c %i "$1" 2>/dev/null || stat -f %i "$1" 2>/dev/null; }
_mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null; }

# Independent count oracle — mirrors the spec-pinned command (INV-002 property 3:
# `git ls-files --cached -z -- 'tests/test*.sh'`, direct children only). Used
# ONLY as a test oracle to cross-check the generator; the generator/R-006(c)
# never call this. Source: spec INV-002 property 3.
_oracle_count() {
  ( cd "$1" && git ls-files --cached -z -- 'tests/test*.sh' 2>/dev/null ) \
    | tr '\0' '\n' | awk -F/ 'NF==2 && $0 != ""' | grep -c . | tr -d ' '
}

# Spec-pinned artifact validation predicate (INV-004 / BND-002). Returns 0 iff
# schema_version==1 AND test_file_count is a non-negative integer.
# Source: spec INV-004 (line ~250) — `jq -e '.test_file_count | (type=="number"
# and . >= 0 and floor == .)'` plus `.schema_version == 1`.
_validate_artifact() {
  local f="$1"
  jq -e '.schema_version == 1' "$f" >/dev/null 2>&1 || return 1
  jq -e '.test_file_count | (type=="number" and . >= 0 and floor == .)' "$f" >/dev/null 2>&1 || return 1
  return 0
}

# Build a self-contained git fixture with a copied generator.
#   $1 = fixture dir   $2 = number of extra test files
#   $3 = "with_consumer" | "no_consumer"
# Creates a decoy .correctless/tests/test-decoy.sh that the INSTALLED-form
# resolver must NOT count (proves root = scriptdir/../.. targets project tests/).
build_fixture() {
  local dir="$1" n="$2" consumer="$3" i=0
  mkdir -p "$dir/tests" "$dir/scripts" "$dir/.correctless/scripts" "$dir/.correctless/tests"
  cp "$GEN" "$dir/scripts/gen-test-inventory.sh"
  cp "$GEN" "$dir/.correctless/scripts/gen-test-inventory.sh"
  chmod +x "$dir/scripts/gen-test-inventory.sh" "$dir/.correctless/scripts/gen-test-inventory.sh"
  if [ "$consumer" = "with_consumer" ]; then
    printf '#\n' > "$dir/tests/test-ap031-fixture-divergence.sh"
  fi
  for i in $(seq 1 "$n"); do printf '#\n' > "$dir/tests/test-fx$i.sh"; done
  printf '#\n' > "$dir/.correctless/tests/test-decoy.sh"
  ( cd "$dir" \
    && git init -q >/dev/null 2>&1 \
    && git config user.email t@t && git config user.name t \
    && git add -A && git commit -qm init >/dev/null 2>&1 )
}

# Run the SHIPPED R-006(c) block (extracted from the consumer, $rc_block) against
# a fixture repo whose REPO_DIR is $1. pass/fail are shadowed so the suite
# counters are untouched; echoes `RC:PASS:`/`RC:FAIL:` + the message. The
# authority of the behavioral matrix comes from the shipped block itself — NOT
# from the local _validate_artifact copy — so weakening R-006(c)'s predicate
# (dropping schema_version==1, floor==., the jq -e fail-closed guard, or the
# remediation string) is CAUGHT here.
_run_real_rc() {
  local repo="$1" tmp
  tmp="$(mktemp "$TMPROOT/rc.XXXXXX")"
  {
    echo 'pass() { echo "RC:PASS:$2"; }'
    echo 'fail() { echo "RC:FAIL:$2"; }'
    printf 'REPO_DIR=%q\n' "$repo"
    printf '%s\n' "$rc_block"
  } > "$tmp"
  bash "$tmp" 2>&1
  rm -f "$tmp"
}

# Assert the shipped R-006(c) block FAILs fail-closed AND emits the exact
# copy-pasteable remediation for a given fixture state. $3 (optional) = a dir to
# prepend to PATH (used to shadow jq with a broken stub).
_assert_real_rc_fails() {
  local id="$1" repo="$2" pathpre="${3:-}" res
  if [ -n "$pathpre" ]; then
    res="$(PATH="$pathpre:$PATH" _run_real_rc "$repo" 2>&1)"
  else
    res="$(_run_real_rc "$repo" 2>&1)"
  fi
  if grep -q 'RC:FAIL:' <<< "$res" && grep -qF 'bash scripts/gen-test-inventory.sh write' <<< "$res"; then
    pass "$id" "shipped R-006(c) fails closed WITH copy-pasteable remediation"
  else
    fail "$id" "shipped R-006(c) did NOT fail-closed-with-remediation (got: $res)"
  fi
}

# ============================================================================
# INV-001 [unit]: deterministic, idempotent, byte-pinned artifact.
# write twice -> (a) sha256 identical, (b) inode unchanged, (c) mtime unchanged,
# (d) 2nd run prints a `no change` token. Content equality ALONE is insufficient
# (a `mktemp && mv`-every-call writer churns inode/mtime and must FAIL here).
# ============================================================================

section "INV-001: deterministic idempotent artifact (double-run)"

if ! gen_present; then
  fail "INV-001(a)" "scripts/gen-test-inventory.sh missing (RED: not yet implemented)"
  fail "INV-001(b)" "scripts/gen-test-inventory.sh missing (RED)"
  fail "INV-001(c)" "scripts/gen-test-inventory.sh missing (RED)"
  fail "INV-001(d)" "scripts/gen-test-inventory.sh missing (RED)"
  fail "PRH-004(a)" "scripts/gen-test-inventory.sh missing (RED)"
elif ! have_git; then
  skip "INV-001(a)" "git unavailable"
else
  FX1="$TMPROOT/inv001"
  build_fixture "$FX1" 3 with_consumer
  ART1="$FX1/tests/test-inventory.json"
  # Settle: first write brings the artifact current.
  ( cd "$FX1" && bash scripts/gen-test-inventory.sh write ) >/dev/null 2>&1
  if [ ! -f "$ART1" ]; then
    fail "INV-001(a)" "write did not produce tests/test-inventory.json"
    fail "INV-001(b)" "artifact absent after write"
    fail "INV-001(c)" "artifact absent after write"
    fail "INV-001(d)" "artifact absent after write"
    fail "PRH-004(a)" "artifact absent after write"
  else
    sha_1="$(_sha256 "$ART1")"; ino_1="$(_inode "$ART1")"; mt_1="$(_mtime "$ART1")"
    out2="$( ( cd "$FX1" && bash scripts/gen-test-inventory.sh write ) 2>&1 )"
    sha_2="$(_sha256 "$ART1")"; ino_2="$(_inode "$ART1")"; mt_2="$(_mtime "$ART1")"

    [ "$sha_1" = "$sha_2" ] \
      && pass "INV-001(a)" "artifact sha256 identical across re-runs" \
      || fail "INV-001(a)" "artifact sha256 changed on idempotent re-run ($sha_1 -> $sha_2)"

    [ -n "$ino_1" ] && [ "$ino_1" = "$ino_2" ] \
      && pass "INV-001(b)" "artifact inode unchanged on no-op re-run (no mktemp+mv churn)" \
      || fail "INV-001(b)" "artifact inode changed on no-op re-run ($ino_1 -> $ino_2) — churn writer"

    [ -n "$mt_1" ] && [ "$mt_1" = "$mt_2" ] \
      && pass "INV-001(c)" "artifact mtime unchanged on no-op re-run (no bytes rewritten)" \
      || fail "INV-001(c)" "artifact mtime changed on no-op re-run ($mt_1 -> $mt_2) — bytes rewritten"

    grep -qi "no change" <<< "$out2" \
      && pass "INV-001(d)" "2nd write prints a 'no change' token" \
      || fail "INV-001(d)" "2nd write did not print a 'no change' token (got: $out2)"

    # PRH-004: artifact carries no timestamp/date field.
    if grep -qiE '"(timestamp|date|generated_at|updated_at|created_at|mtime)"' "$ART1"; then
      fail "PRH-004(a)" "artifact contains a nondeterministic timestamp/date field"
    else
      pass "PRH-004(a)" "artifact carries no timestamp/date field (deterministic)"
    fi
  fi
fi

# ============================================================================
# INV-002 [unit] structural: R-006(c) obtains "actual" ONLY from the shared
# `gen-test-inventory.sh count` command (positive) and re-implements NO other
# counting primitive (negative — no find / wc -l / grep -c / ls-pipe / ${#arr}).
# ============================================================================

section "INV-002: shared count command — R-006(c) structural (positive + negative)"

# Extract the sentinel-delimited R-006(c) block from the consumer file.
rc_block="$(awk '
  /--- R-006\(c\) BLOCK START/{found=1}
  found{print}
  /--- R-006\(c\) BLOCK END/{exit}
' "$CONSUMER")"

if [ -z "$rc_block" ]; then
  fail "INV-002(a)" "could not locate R-006(c) sentinel block in $CONSUMER"
  fail "INV-002(b)" "could not locate R-006(c) sentinel block in $CONSUMER"
else
  # Positive: the block calls the shared count command.
  if grep -qE "gen-test-inventory\.sh count" <<< "$rc_block"; then
    pass "INV-002(a)" "R-006(c) block obtains actual via 'gen-test-inventory.sh count'"
  else
    fail "INV-002(a)" "R-006(c) block does not call 'gen-test-inventory.sh count' for actual"
  fi
  # Negative: no other counting primitive computing "actual". Strip full-line
  # comments first so the explanatory comment (which names the banned primitives)
  # does not self-trigger — only executable code is inspected.
  rc_code="$(grep -vE '^[[:space:]]*#' <<< "$rc_block")"
  if grep -qE "(^|[^A-Za-z_-])find |wc -l|grep -c|ls [^=]*\||\$\{#[A-Za-z_]" <<< "$rc_code"; then
    fail "INV-002(b)" "R-006(c) code re-implements a counting primitive (find/wc -l/grep -c/ls-pipe/\${#arr}) — writer/consumer drift (PRH-003)"
  else
    pass "INV-002(b)" "R-006(c) code contains no other counting primitive for actual (PRH-003)"
  fi
fi

# ============================================================================
# INV-002 [integration]: repo-root resolution across FOUR contexts + index
# universe. Resolution is from ${BASH_SOURCE[0]} script dir (two-layout case
# split), NOT $PWD and NOT `git rev-parse --show-toplevel`.
# ============================================================================

section "INV-002: repo-root resolution (4 contexts) + index universe"

if ! gen_present; then
  fail "INV-002(ctx-i)"   "scripts/gen-test-inventory.sh missing (RED)"
  fail "INV-002(ctx-ii)"  "scripts/gen-test-inventory.sh missing (RED)"
  fail "INV-002(ctx-iii)" "scripts/gen-test-inventory.sh missing (RED)"
  fail "INV-002(ctx-iv)"  "scripts/gen-test-inventory.sh missing (RED)"
  fail "INV-002(univ-a)"  "scripts/gen-test-inventory.sh missing (RED)"
  fail "INV-002(univ-b)"  "scripts/gen-test-inventory.sh missing (RED)"
  fail "INV-002(univ-c)"  "scripts/gen-test-inventory.sh missing (RED)"
elif ! have_git; then
  skip "INV-002(ctx-i)" "git unavailable"
else
  FX2="$TMPROOT/inv002"
  build_fixture "$FX2" 3 with_consumer   # tests/: fx1,fx2,fx3 + consumer = 4
  oracle="$(_oracle_count "$FX2")"

  # (i) normal CWD in-repo, source form.
  c_i="$( ( cd "$FX2" && bash scripts/gen-test-inventory.sh count ) 2>/dev/null | tr -d ' ' )"
  [ "$c_i" = "$oracle" ] \
    && pass "INV-002(ctx-i)" "count from in-repo CWD == oracle ($oracle)" \
    || fail "INV-002(ctx-i)" "count from in-repo CWD ($c_i) != oracle ($oracle)"

  # (ii) non-repo CWD (/tmp) invoked by absolute path — must NOT rely on $PWD.
  c_ii="$( ( cd /tmp && bash "$FX2/scripts/gen-test-inventory.sh" count ) 2>/dev/null | tr -d ' ' )"
  [ "$c_ii" = "$oracle" ] \
    && pass "INV-002(ctx-ii)" "count from /tmp via absolute path == oracle ($oracle) — not \$PWD-derived" \
    || fail "INV-002(ctx-ii)" "count from /tmp ($c_ii) != oracle ($oracle) — resolver leaned on \$PWD"

  # (iii) /ctdd-style probe worktree.
  WT="$TMPROOT/inv002-wt"
  if ( cd "$FX2" && git worktree add -q "$WT" HEAD ) >/dev/null 2>&1; then
    c_iii="$( ( cd "$WT" && bash scripts/gen-test-inventory.sh count ) 2>/dev/null | tr -d ' ' )"
    [ "$c_iii" = "$oracle" ] \
      && pass "INV-002(ctx-iii)" "count from probe worktree == oracle ($oracle) — not git-toplevel-dependent" \
      || fail "INV-002(ctx-iii)" "count from probe worktree ($c_iii) != oracle ($oracle)"
  else
    fail "INV-002(ctx-iii)" "git worktree add failed — cannot exercise probe-worktree resolution"
  fi

  # (iv) installed .correctless/scripts path -> root = scriptdir/../.. -> project
  # tests/ (NOT .correctless/tests/, which holds the decoy).
  c_iv="$( bash "$FX2/.correctless/scripts/gen-test-inventory.sh" count 2>/dev/null | tr -d ' ' )"
  [ "$c_iv" = "$oracle" ] \
    && pass "INV-002(ctx-iv)" "installed-form count == oracle ($oracle) — targets project tests/, not .correctless/tests/" \
    || fail "INV-002(ctx-iv)" "installed-form count ($c_iv) != oracle ($oracle) — resolved wrong tests/ dir"

  # Universe = git index. (a) baseline parity already covered; assert integer.
  if printf '%s' "$c_i" | grep -qE '^[0-9]+$'; then
    pass "INV-002(univ-a)" "count returns a bare integer over the index universe ($c_i)"
  else
    fail "INV-002(univ-a)" "count did not return a bare integer (got '$c_i')"
  fi

  # (b) an UNTRACKED scratch tests/test-scratch.sh must NOT change count.
  printf '#\n' > "$FX2/tests/test-scratch-$$.sh"
  c_untracked="$( ( cd "$FX2" && bash scripts/gen-test-inventory.sh count ) 2>/dev/null | tr -d ' ' )"
  rm -f "$FX2/tests/test-scratch-$$.sh"
  [ "$c_untracked" = "$oracle" ] \
    && pass "INV-002(univ-b)" "untracked scratch tests/test-*.sh does NOT perturb count (index universe)" \
    || fail "INV-002(univ-b)" "untracked scratch changed count ($oracle -> $c_untracked) — working-tree universe, CI skew"

  # (c) staging a net-new test increments the index count by exactly one.
  printf '#\n' > "$FX2/tests/test-staged-new.sh"
  ( cd "$FX2" && git add tests/test-staged-new.sh ) >/dev/null 2>&1
  c_staged="$( ( cd "$FX2" && bash scripts/gen-test-inventory.sh count ) 2>/dev/null | tr -d ' ' )"
  [ "$c_staged" = "$(( oracle + 1 ))" ] \
    && pass "INV-002(univ-c)" "staged net-new test increments count to $(( oracle + 1 ))" \
    || fail "INV-002(univ-c)" "staged net-new test did not increment count (got '$c_staged', want $(( oracle + 1 )))"
fi

# ============================================================================
# INV-003 [unit]: generator contract — consumer guard, atomic glob-safe write,
# tri-state fail-loud, count prints only the integer.
# ============================================================================

section "INV-003: generator contract (consumer guard / atomic / tri-state)"

# --- generator-side consumer guard (EXT-006) ---
if ! gen_present; then
  fail "INV-003(guard-write)" "scripts/gen-test-inventory.sh missing (RED)"
  fail "INV-003(guard-count)" "scripts/gen-test-inventory.sh missing (RED)"
elif ! have_git; then
  skip "INV-003(guard-write)" "git unavailable"
else
  FXNC="$TMPROOT/inv003-noconsumer"
  build_fixture "$FXNC" 3 no_consumer   # marker absent
  gw_out="$( ( cd "$FXNC" && bash scripts/gen-test-inventory.sh write ) 2>&1 )"; gw_rc=$?
  if [ "$gw_rc" -eq 0 ] && grep -qi "no consumer" <<< "$gw_out" && [ ! -f "$FXNC/tests/test-inventory.json" ]; then
    pass "INV-003(guard-write)" "write no-ops (exit 0, 'no consumer — skipped', nothing written) when marker absent"
  else
    fail "INV-003(guard-write)" "write did not no-op on absent consumer marker (rc=$gw_rc, out=$gw_out, artifact-present=$( [ -f "$FXNC/tests/test-inventory.json" ] && echo yes || echo no ))"
  fi
  gc_out="$( ( cd "$FXNC" && bash scripts/gen-test-inventory.sh count ) 2>&1 )"; gc_rc=$?
  if [ "$gc_rc" -eq 0 ] && grep -qi "no consumer" <<< "$gc_out"; then
    pass "INV-003(guard-count)" "count no-ops (exit 0, 'no consumer — skipped') when marker absent"
  else
    fail "INV-003(guard-count)" "count did not no-op on absent consumer marker (rc=$gc_rc, out=$gc_out)"
  fi
fi

# --- atomic write structural (mktemp+mv, glob-safe temp name, trap) ---
if ! gen_present; then
  fail "INV-003(atomic-a)" "scripts/gen-test-inventory.sh missing (RED)"
  fail "INV-003(atomic-b)" "scripts/gen-test-inventory.sh missing (RED)"
  fail "INV-003(atomic-c)" "scripts/gen-test-inventory.sh missing (RED)"
else
  if grep -qE "mktemp" "$GEN" && grep -qE "\bmv\b" "$GEN"; then
    pass "INV-003(atomic-a)" "generator uses mktemp + mv for atomic write"
  else
    fail "INV-003(atomic-a)" "generator missing mktemp/mv atomic-write pattern"
  fi
  # temp name must be a dotfile / non-test*.sh so it cannot self-inflate the count.
  if grep -qE "\.test-inventory\.json\.tmp|\.tmp\.|/\.[A-Za-z]" "$GEN"; then
    pass "INV-003(atomic-b)" "generator temp name is glob-safe (dotfile, cannot match test*.sh)"
  else
    fail "INV-003(atomic-b)" "generator temp name may match the test*.sh count glob (self-inflation risk RS-011)"
  fi
  if grep -qE "trap" "$GEN"; then
    pass "INV-003(atomic-c)" "generator installs a trap to clean up the temp on any exit path"
  else
    fail "INV-003(atomic-c)" "generator missing trap-based temp cleanup"
  fi
fi

# --- tri-state exit / fail-loud ---
if ! gen_present; then
  fail "INV-003(tri-change)"  "scripts/gen-test-inventory.sh missing (RED)"
  fail "INV-003(tri-nochg)"   "scripts/gen-test-inventory.sh missing (RED)"
  fail "INV-003(tri-fail)"    "scripts/gen-test-inventory.sh missing (RED)"
  fail "INV-003(count-only)"  "scripts/gen-test-inventory.sh missing (RED)"
elif ! have_git; then
  skip "INV-003(tri-change)" "git unavailable"
else
  FXT="$TMPROOT/inv003-tri"
  build_fixture "$FXT" 2 with_consumer
  ARTT="$FXT/tests/test-inventory.json"

  # change: first write (artifact absent) -> exit 0 + success line (not 'no change').
  ch_out="$( ( cd "$FXT" && bash scripts/gen-test-inventory.sh write ) 2>&1 )"; ch_rc=$?
  if [ "$ch_rc" -eq 0 ] && [ -f "$ARTT" ] && ! grep -qi "no change" <<< "$ch_out"; then
    pass "INV-003(tri-change)" "write on change -> exit 0 + success line + artifact created"
  else
    fail "INV-003(tri-change)" "write on change did not report success (rc=$ch_rc, out=$ch_out)"
  fi

  # no change: second write -> exit 0 + 'no change'.
  nc_out="$( ( cd "$FXT" && bash scripts/gen-test-inventory.sh write ) 2>&1 )"; nc_rc=$?
  if [ "$nc_rc" -eq 0 ] && grep -qi "no change" <<< "$nc_out"; then
    pass "INV-003(tri-nochg)" "write when current -> exit 0 + 'no change'"
  else
    fail "INV-003(tri-nochg)" "write when current did not report 'no change' (rc=$nc_rc, out=$nc_out)"
  fi

  # fail-loud: force write failure via an unwritable tests/ dir. Skip as root.
  if [ "$(id -u 2>/dev/null || echo 0)" = "0" ]; then
    skip "INV-003(tri-fail)" "running as root — cannot make dir unwritable"
  else
    sha_before="$(_sha256 "$ARTT")"
    chmod a-w "$FXT/tests"
    f_out="$( ( cd "$FXT" && bash scripts/gen-test-inventory.sh write ) 2>&1 )"; f_rc=$?
    chmod u+w "$FXT/tests"
    sha_after="$(_sha256 "$ARTT")"
    tmp_leftover="$(find "$FXT/tests" -maxdepth 1 -name '*.tmp*' -o -name '.test-inventory.json.tmp*' 2>/dev/null | grep -c . | tr -d ' ')"
    if [ "$f_rc" -ne 0 ] && grep -q "gen-test-inventory: FAILED" <<< "$f_out" \
       && [ "$sha_before" = "$sha_after" ] && [ "${tmp_leftover:-0}" = "0" ]; then
      pass "INV-003(tri-fail)" "forced write failure -> non-zero + 'gen-test-inventory: FAILED' + unchanged target + no surviving temp"
    else
      fail "INV-003(tri-fail)" "forced write failure not fail-loud (rc=$f_rc, out=$f_out, target-changed=$( [ "$sha_before" = "$sha_after" ] && echo no || echo yes ), temp-leftover=${tmp_leftover:-?})"
    fi
  fi

  # count prints ONLY the integer (single line, bare number).
  co_out="$( ( cd "$FXT" && bash scripts/gen-test-inventory.sh count ) 2>/dev/null )"
  co_lines="$(printf '%s\n' "$co_out" | grep -c .)"
  if printf '%s' "$co_out" | grep -qE '^[0-9]+$' && [ "$co_lines" -eq 1 ]; then
    pass "INV-003(count-only)" "count prints only a bare integer to stdout ($co_out)"
  else
    fail "INV-003(count-only)" "count printed extra text or multiple lines (got: $co_out)"
  fi
fi

# --- tri-state fail-loud on git FAILURE, not just tool ABSENCE (QA-001) ---
# A git failure (ROOT not a repo / corrupt-locked index / missing .git) must
# NOT collapse the count pipeline into a valid-looking '0'. Build a fixture with
# the consumer marker + a generator copy but NO `git init` (never a repo), so
# `git ls-files` fails. write -> non-zero + FAILED token on stdout + NO artifact;
# count -> non-zero + does NOT print a bare '0'. Regression for the `2>/dev/null`
# + no-pipefail swallow that let do_write emit test_file_count:0 with exit 0.
if ! gen_present; then
  fail "INV-003(tri-fail-git)"        "scripts/gen-test-inventory.sh missing (RED)"
  fail "INV-003(tri-fail-git-count)"  "scripts/gen-test-inventory.sh missing (RED)"
elif ! have_git; then
  skip "INV-003(tri-fail-git)"        "git unavailable"
  skip "INV-003(tri-fail-git-count)"  "git unavailable"
else
  FXG="$TMPROOT/inv003-nogit"
  mkdir -p "$FXG/tests" "$FXG/scripts"
  cp "$GEN" "$FXG/scripts/gen-test-inventory.sh"; chmod +x "$FXG/scripts/gen-test-inventory.sh"
  printf '#\n' > "$FXG/tests/test-ap031-fixture-divergence.sh"   # consumer marker present
  printf '#\n' > "$FXG/tests/test-fx1.sh"
  # NOTE: deliberately NO `git init` — this dir is not a git repository.
  ARTG="$FXG/tests/test-inventory.json"

  gfw_out="$( ( cd "$FXG" && bash scripts/gen-test-inventory.sh write ) 2>/dev/null )"; gfw_rc=$?
  if [ "$gfw_rc" -ne 0 ] && grep -q "gen-test-inventory: FAILED" <<< "$gfw_out" \
     && [ ! -f "$ARTG" ]; then
    pass "INV-003(tri-fail-git)" "write on git failure -> non-zero + FAILED token (stdout) + no artifact written (not a silent 0)"
  else
    fail "INV-003(tri-fail-git)" "write on git failure not fail-loud (rc=$gfw_rc, stdout=$gfw_out, artifact-present=$( [ -f "$ARTG" ] && echo yes || echo no ))"
  fi

  gfc_out="$( ( cd "$FXG" && bash scripts/gen-test-inventory.sh count ) 2>/dev/null )"; gfc_rc=$?
  if [ "$gfc_rc" -ne 0 ] && [ "$(printf '%s' "$gfc_out" | tr -d ' ')" != "0" ]; then
    pass "INV-003(tri-fail-git-count)" "count on git failure -> non-zero + does NOT print a bare '0' (stdout=$gfc_out)"
  else
    fail "INV-003(tri-fail-git-count)" "count on git failure printed '0' or exited 0 (rc=$gfc_rc, stdout=$gfc_out)"
  fi
fi

# ============================================================================
# INV-004 [unit+integration]: R-006(c) validation matrix over the spec-pinned
# predicate. current->PASS (generator-produced fixture), malformed shapes each
# ->FAIL fail-closed, jq-absent->fail-closed.
# ============================================================================

section "INV-004: R-006(c) validation matrix (pinned predicate)"

if ! command -v jq >/dev/null 2>&1; then
  fail "INV-004(matrix)" "jq unavailable — cannot exercise validation predicate"
else
  MX="$TMPROOT/inv004"; mkdir -p "$MX"
  printf '%s' '{"schema_version":1,"test_file_count":5}'   > "$MX/valid.json"
  printf '%s' '{oops not json'                              > "$MX/badjson.json"
  printf '%s' '{"schema_version":1}'                        > "$MX/nocount.json"
  printf '%s' '{"schema_version":1,"test_file_count":"5"}'  > "$MX/strcount.json"
  printf '%s' '{"schema_version":1,"test_file_count":3.5}'  > "$MX/fraccount.json"
  printf '%s' '{"test_file_count":5}'                       > "$MX/noschema.json"
  printf '%s' '{"schema_version":2,"test_file_count":5}'    > "$MX/wrongschema.json"

  _validate_artifact "$MX/valid.json"       && pass "INV-004(valid)"       "well-formed artifact passes validation" || fail "INV-004(valid)" "well-formed artifact rejected"
  _validate_artifact "$MX/badjson.json"     && fail "INV-004(badjson)"     "invalid JSON accepted (should fail-closed)" || pass "INV-004(badjson)" "invalid JSON fails closed"
  _validate_artifact "$MX/nocount.json"     && fail "INV-004(nocount)"     "missing test_file_count accepted" || pass "INV-004(nocount)" "missing test_file_count fails closed"
  _validate_artifact "$MX/strcount.json"    && fail "INV-004(strcount)"    "string-typed count \"5\" accepted" || pass "INV-004(strcount)" "string-typed count fails closed"
  _validate_artifact "$MX/fraccount.json"   && fail "INV-004(fraccount)"   "fractional count 3.5 accepted (bare | numbers gap EXT-009)" || pass "INV-004(fraccount)" "fractional count 3.5 fails closed (floor==.)"
  _validate_artifact "$MX/noschema.json"    && fail "INV-004(noschema)"    "schema_version absent accepted" || pass "INV-004(noschema)" "schema_version absent fails closed"
  _validate_artifact "$MX/wrongschema.json" && fail "INV-004(wrongschema)" "schema_version != 1 accepted" || pass "INV-004(wrongschema)" "schema_version != 1 fails closed"

  # jq-absent -> fail-closed (never a silent bash integer-expr success).
  mkdir -p "$MX/nojq"; printf '#!/bin/sh\nexit 127\n' > "$MX/nojq/jq"; chmod +x "$MX/nojq/jq"
  if PATH="$MX/nojq:$PATH" _validate_artifact "$MX/valid.json"; then
    fail "INV-004(jq-absent)" "validation passed with jq unavailable (should fail-closed like PAT-001)"
  else
    pass "INV-004(jq-absent)" "validation fails closed when jq is unavailable/broken"
  fi
fi

# INV-004: current->PASS using a GENERATOR-PRODUCED pass fixture (kills PMB-010).
if ! gen_present; then
  fail "INV-004(passfix)" "scripts/gen-test-inventory.sh missing (RED)"
elif ! have_git || ! command -v jq >/dev/null 2>&1; then
  skip "INV-004(passfix)" "git or jq unavailable"
else
  FXP="$TMPROOT/inv004-pass"
  build_fixture "$FXP" 4 with_consumer
  ( cd "$FXP" && bash scripts/gen-test-inventory.sh write ) >/dev/null 2>&1
  ARTP="$FXP/tests/test-inventory.json"
  gc="$( ( cd "$FXP" && bash scripts/gen-test-inventory.sh count ) 2>/dev/null | tr -d ' ' )"
  if [ -f "$ARTP" ] && _validate_artifact "$ARTP" \
     && [ "$(jq -r '.test_file_count' "$ARTP" 2>/dev/null)" = "$gc" ]; then
    pass "INV-004(passfix)" "generator-produced artifact passes validation AND count parity ($gc)"
  else
    fail "INV-004(passfix)" "generator-produced artifact failed validation/parity"
  fi
fi

# INV-004 / BND-001: real consumer with the artifact ABSENT -> R-006(c) FAILs
# with the copy-pasteable remediation containing `bash scripts/gen-test-inventory.sh write`.
section "INV-004 / BND-001: real-consumer remediation legibility"
rc_out="$( bash "$CONSUMER" 2>&1 | grep -E 'R-006\(c\)' | grep -i 'FAIL' || true )"
if [ -n "$rc_out" ] && grep -qF "bash scripts/gen-test-inventory.sh write" <<< "$rc_out"; then
  pass "BND-001(remed)" "R-006(c) fails closed with copy-pasteable 'bash scripts/gen-test-inventory.sh write' remediation"
else
  # In GREEN (artifact present + fresh) R-006(c) PASSes and no remediation is shown.
  if bash "$CONSUMER" >/dev/null 2>&1; then
    skip "BND-001(remed)" "R-006(c) currently PASSes (artifact present + fresh) — remediation path not exercised"
  else
    fail "BND-001(remed)" "R-006(c) failed without the pinned remediation string (got: $rc_out)"
  fi
fi
# Structural: R-006(c) block wires the remediation on the mismatch/malformed branches.
remed_refs="$(grep -cF "bash scripts/gen-test-inventory.sh write" <<< "$rc_block")"
if [ "${remed_refs:-0}" -ge 1 ]; then
  pass "INV-004(remed-wired)" "R-006(c) block wires the copy-pasteable remediation string ($remed_refs refs)"
else
  fail "INV-004(remed-wired)" "R-006(c) block does not wire the remediation string"
fi

# ============================================================================
# B1(1) / B2 STRUCTURAL PIN [unit]: bind the SHIPPED R-006(c) block to the exact
# spec-pinned predicates + remediation, so a GREEN implementer who weakens
# R-006(c)'s own validation (drops schema_version==1 / floor==. / the jq -e
# fail-closed guard) or drops $REMEDIATION from the mismatch/malformed branches
# is CAUGHT — the local _validate_artifact copy cannot mask that.
# ============================================================================

section "INV-004: shipped R-006(c) predicate + remediation pin (structural)"

if [ -z "$rc_block" ]; then
  fail "INV-004(pin-schema)"          "R-006(c) sentinel block not found in $CONSUMER"
  fail "INV-004(pin-integer)"         "R-006(c) sentinel block not found"
  fail "INV-004(pin-jqe)"             "R-006(c) sentinel block not found"
  fail "INV-004(pin-remed-mismatch)"  "R-006(c) sentinel block not found"
  fail "INV-004(pin-remed-malformed)" "R-006(c) sentinel block not found"
else
  grep -qF 'schema_version == 1' <<< "$rc_block" \
    && pass "INV-004(pin-schema)" "R-006(c) pins 'schema_version == 1'" \
    || fail "INV-004(pin-schema)" "R-006(c) dropped the 'schema_version == 1' predicate"

  grep -qF 'type=="number" and . >= 0 and floor == .' <<< "$rc_block" \
    && pass "INV-004(pin-integer)" "R-006(c) pins the non-negative-integer guard (floor==. rejects 3.5, EXT-009)" \
    || fail "INV-004(pin-integer)" "R-006(c) dropped the 'type==\"number\" and . >= 0 and floor == .' integer guard"

  grep -qF 'jq -e' <<< "$rc_block" \
    && pass "INV-004(pin-jqe)" "R-006(c) validates via 'jq -e' (fail-closed on parse/tool failure)" \
    || fail "INV-004(pin-jqe)" "R-006(c) does not validate via 'jq -e' — parse failures may not fail closed"

  # Remediation must be wired on the highest-frequency mismatch path (RS-009)...
  grep -qE '!= actual.*REMEDIATION' <<< "$rc_block" \
    && pass "INV-004(pin-remed-mismatch)" "R-006(c) wires \$REMEDIATION on the stale-mismatch branch" \
    || fail "INV-004(pin-remed-mismatch)" "R-006(c) mismatch branch does not reference \$REMEDIATION"

  # ...and on the malformed-artifact path.
  grep -qE 'malformed.*REMEDIATION' <<< "$rc_block" \
    && pass "INV-004(pin-remed-malformed)" "R-006(c) wires \$REMEDIATION on the malformed branch" \
    || fail "INV-004(pin-remed-malformed)" "R-006(c) malformed branch does not reference \$REMEDIATION"
fi

# ============================================================================
# B1(2) / B2 BEHAVIORAL MATRIX [integration]: drive the ACTUAL shipped R-006(c)
# block (via $rc_block, NOT _validate_artifact) against each corrupted artifact
# in a real fixture repo, asserting each FAILs fail-closed AND emits the exact
# copy-pasteable `bash scripts/gen-test-inventory.sh write` remediation. Covers
# every failure branch (spec: "Each failure message asserted to contain the
# copy-pasteable remediation"): missing, invalid JSON, missing test_file_count,
# string "5", fractional 3.5, absent schema_version, schema_version != 1,
# jq-unusable, AND a stale count MISMATCH (highest-frequency, RS-009).
# ============================================================================

section "INV-004: shipped R-006(c) failure matrix (behavioral, real consumer)"

_real_matrix_ids="real-missing real-badjson real-nocount real-strcount real-fraccount real-noschema real-wrongschema real-jqbroken real-mismatch"

if ! gen_present; then
  for _id in $_real_matrix_ids; do
    fail "INV-004($_id)" "scripts/gen-test-inventory.sh missing (RED) — shipped R-006(c) matrix cannot run"
  done
elif ! have_git || ! command -v jq >/dev/null 2>&1; then
  for _id in $_real_matrix_ids; do skip "INV-004($_id)" "git or jq unavailable"; done
else
  FXR="$TMPROOT/inv004-real"
  build_fixture "$FXR" 2 with_consumer   # gen count over the index = 2 fx + consumer = 3
  ARTR="$FXR/tests/test-inventory.json"
  gcR="$( ( cd "$FXR" && bash scripts/gen-test-inventory.sh count ) 2>/dev/null | tr -d ' ' )"

  # missing: no artifact present yet.
  rm -f "$ARTR"
  _assert_real_rc_fails "INV-004(real-missing)" "$FXR"

  # malformed shapes.
  printf '%s' '{oops not json'                             > "$ARTR"; _assert_real_rc_fails "INV-004(real-badjson)"     "$FXR"
  printf '%s' '{"schema_version":1}'                       > "$ARTR"; _assert_real_rc_fails "INV-004(real-nocount)"     "$FXR"
  printf '%s' '{"schema_version":1,"test_file_count":"5"}' > "$ARTR"; _assert_real_rc_fails "INV-004(real-strcount)"    "$FXR"
  printf '%s' '{"schema_version":1,"test_file_count":3.5}' > "$ARTR"; _assert_real_rc_fails "INV-004(real-fraccount)"   "$FXR"
  printf '%s' '{"test_file_count":5}'                      > "$ARTR"; _assert_real_rc_fails "INV-004(real-noschema)"    "$FXR"
  printf '%s' '{"schema_version":2,"test_file_count":5}'   > "$ARTR"; _assert_real_rc_fails "INV-004(real-wrongschema)" "$FXR"

  # jq-unusable: a WELL-FORMED, CURRENT artifact must still fail-closed when jq
  # is broken (proves R-006(c) never silently falls through to a bash compare).
  mkdir -p "$FXR/nojq"; printf '#!/bin/sh\nexit 127\n' > "$FXR/nojq/jq"; chmod +x "$FXR/nojq/jq"
  printf '%s' "{\"schema_version\":1,\"test_file_count\":${gcR:-0}}" > "$ARTR"
  _assert_real_rc_fails "INV-004(real-jqbroken)" "$FXR" "$FXR/nojq"

  # stale count MISMATCH: well-formed but count != actual (index universe).
  printf '%s' "{\"schema_version\":1,\"test_file_count\":$(( ${gcR:-0} + 7 ))}" > "$ARTR"
  _assert_real_rc_fails "INV-004(real-mismatch)" "$FXR"
fi

# ============================================================================
# BND-002: enumerated malformed set — same integer validation (covered above);
# assert the pinned floor==. guard specifically rejects fractional (EXT-009).
# ============================================================================

section "BND-002: enumerated malformed artifact set"
if ! command -v jq >/dev/null 2>&1; then
  fail "BND-002(floor)" "jq unavailable"
else
  # A bare `| numbers` would ACCEPT 3.5; the pinned predicate must REJECT it.
  if jq -e '3.5 | (type=="number" and . >= 0 and floor == .)' >/dev/null 2>&1 <<< 'null'; then
    fail "BND-002(floor)" "pinned predicate wrongly accepts 3.5"
  else
    pass "BND-002(floor)" "pinned predicate rejects fractional 3.5 (floor==. guard, EXT-009)"
  fi
fi

# ============================================================================
# BND-003: count decrement — deleting a test yields test_file_count == N-1 and
# R-006(c) parity holds (index universe, exact write in both directions).
# ============================================================================

section "BND-003: count decrement (test file deleted)"
if ! gen_present; then
  fail "BND-003(a)" "scripts/gen-test-inventory.sh missing (RED)"
elif ! have_git || ! command -v jq >/dev/null 2>&1; then
  skip "BND-003(a)" "git or jq unavailable"
else
  FXD="$TMPROOT/bnd003"
  build_fixture "$FXD" 3 with_consumer   # tests/: fx1,fx2,fx3 + consumer = 4
  n0="$(_oracle_count "$FXD")"
  # Delete one test file and stage the deletion.
  ( cd "$FXD" && git rm -q tests/test-fx3.sh ) >/dev/null 2>&1
  ( cd "$FXD" && bash scripts/gen-test-inventory.sh write ) >/dev/null 2>&1
  ARTD="$FXD/tests/test-inventory.json"
  n1="$(jq -r '.test_file_count' "$ARTD" 2>/dev/null || echo x)"
  gc1="$( ( cd "$FXD" && bash scripts/gen-test-inventory.sh count ) 2>/dev/null | tr -d ' ' )"
  if [ "$n1" = "$(( n0 - 1 ))" ] && [ "$n1" = "$gc1" ]; then
    pass "BND-003(a)" "deletion syncs count down to N-1 ($n1) with R-006(c) parity"
  else
    fail "BND-003(a)" "deletion did not sync down (artifact=$n1, count=$gc1, want $(( n0 - 1 )))"
  fi
fi

# ============================================================================
# PRH-001 [unit]: artifact must be tracked + PR-reaching (real repo).
# ============================================================================

section "PRH-001: artifact tracked + PR-reaching (real repo)"
if ! have_git; then
  skip "PRH-001(tracked)" "git unavailable"
else
  if ( cd "$REPO_DIR" && git ls-files --error-unmatch tests/test-inventory.json ) >/dev/null 2>&1; then
    pass "PRH-001(tracked)" "tests/test-inventory.json is tracked"
  else
    fail "PRH-001(tracked)" "tests/test-inventory.json is NOT tracked (git ls-files --error-unmatch failed)"
  fi
  if ( cd "$REPO_DIR" && git check-ignore -q tests/test-inventory.json ) >/dev/null 2>&1; then
    fail "PRH-001(notignored)" "tests/test-inventory.json is gitignored — CI R-006(c) can't see it"
  else
    pass "PRH-001(notignored)" "tests/test-inventory.json is not gitignored"
  fi
fi
# path is not under a /cchores-stripped or gitignored prefix.
art_rel="tests/test-inventory.json"
case "$art_rel" in
  .correctless/meta/*|.correctless/artifacts/*|.correctless/scripts/*|.correctless/hooks/*)
    fail "PRH-001(prefix)" "artifact lives under a stripped/gitignored prefix" ;;
  *)
    pass "PRH-001(prefix)" "artifact path is not under any stripped/gitignored prefix" ;;
esac

# ============================================================================
# Summary
# ============================================================================

summary "Generated Test-Count Artifact + Generator Tests (#219)"
