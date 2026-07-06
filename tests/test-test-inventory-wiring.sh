#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091,SC2086,SC2016,SC2317,SC2015,SC2034
# Correctless — test-inventory.json Wiring / SFG / Distribution / allowed-tools
# Feature: agent-context-count-sync (#219, Option 2)
# Spec: .correctless/specs/agent-context-count-sync.md
#
# Covers the WIRING + INVARIANT-PRESERVATION cluster:
#   INV-005 / PRH-002 (INV-010 unchanged; artifact unprotected + PR-staged),
#   INV-006 (consumer-scoped, ordered, exit-checked regeneration wiring),
#   INV-007 (AGENT_CONTEXT figure informational + structurally un-scraped),
#   INV-008 (distribution parity), INV-009 (allowed-tools coverage + Group B).
#
# RED expectation: the generator, its distribution mirror, and the skill wiring
# do NOT exist yet, so the wiring/mirror/allowed-tools assertions FAIL with
# controlled `FAIL:` lines. The INV-010-unchanged and SFG-allows guards are
# regression guards that PASS now and must stay green.
#
# Run from repo root: bash tests/test-test-inventory-wiring.sh

source "$(dirname "${BASH_SOURCE[0]}")/test-helpers.sh"

echo "test-inventory.json Wiring / SFG / Distribution Tests (#219)"
echo "==========================================="

SFG_HOOK="$REPO_DIR/hooks/sensitive-file-guard.sh"
GEN="$REPO_DIR/scripts/gen-test-inventory.sh"
GEN_MIRROR="$REPO_DIR/correctless/scripts/gen-test-inventory.sh"
CCHORES="$REPO_DIR/skills/cchores/SKILL.md"
CTDD="$REPO_DIR/skills/ctdd/SKILL.md"
CDOCS="$REPO_DIR/skills/cdocs/SKILL.md"
ARTIFACT="tests/test-inventory.json"
THIS_BASENAME="test-test-inventory-wiring.sh"

gen_present() { [ -f "$GEN" ]; }
have_git() { command -v git >/dev/null 2>&1; }

TMPROOT="$(mktemp -d)"
cleanup() { git worktree prune >/dev/null 2>&1 || true; rm -rf "$TMPROOT" 2>/dev/null || true; }
trap cleanup EXIT

# Run the REAL sensitive-file-guard hook against an Edit targeting $1; echo exit code.
run_sfg() {
  local path="$1"
  printf '{"tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$path" \
    | bash "$SFG_HOOK" >/dev/null 2>&1
  echo "$?"
}

# Build a git fixture with a copied generator + committed artifact for the
# INV-006 mechanism repro. $1=dir $2=extra-test-count.
build_fixture() {
  local dir="$1" n="$2" i=0
  mkdir -p "$dir/tests" "$dir/scripts"
  cp "$GEN" "$dir/scripts/gen-test-inventory.sh"; chmod +x "$dir/scripts/gen-test-inventory.sh"
  printf '#\n' > "$dir/tests/test-ap031-fixture-divergence.sh"   # consumer marker
  for i in $(seq 1 "$n"); do printf '#\n' > "$dir/tests/test-fx$i.sh"; done
  ( cd "$dir" && git init -q >/dev/null 2>&1 \
      && git config user.email t@t && git config user.name t \
      && git add -A && git commit -qm init >/dev/null 2>&1 )
}

# Emulate the R-006(c) mechanism (artifact count vs shared count) WITHOUT the
# LLM. Returns 0 (PASS) when they match. Source: spec INV-004 (== over index).
rc_mechanism() { # $1 = fixture dir
  local art actual
  art="$(jq -r '.test_file_count' "$1/tests/test-inventory.json" 2>/dev/null || echo x)"
  actual="$( ( cd "$1" && bash scripts/gen-test-inventory.sh count ) 2>/dev/null | tr -d ' ' )"
  [ -n "$art" ] && [ "$art" = "$actual" ]
}

# ============================================================================
# INV-005 [integration] / PRH-002: INV-010 unchanged; artifact unprotected.
# ============================================================================

section "INV-005 / PRH-002: INV-010 unchanged; artifact unprotected + tracked"

# (a) cchores INV-010 shared-doc ban text present/unchanged (four prose docs).
inv010_ok=1
for _d in ".correctless/ARCHITECTURE.md" ".correctless/AGENT_CONTEXT.md" "CLAUDE.md" "README.md"; do
  grep -qF "$_d" "$CCHORES" || inv010_ok=0
done
if [ "$inv010_ok" -eq 1 ]; then
  pass "INV-005(a)" "cchores INV-010 shared-doc ban lists all four prose docs (unchanged)"
else
  fail "INV-005(a)" "cchores INV-010 shared-doc ban text is missing one of the four prose docs"
fi

# (b) SFG effective protected set: the REAL hook does NOT block the artifact,
# but DOES block a known DEFAULTS entry (.env) as a control. Exercises the
# resolved effective set (DEFAULTS + custom_patterns), not just DEFAULTS-list
# absence (EXT-010).
# DECISION: control is `.env` (a genuine SFG DEFAULTS entry), NOT
# `.correctless/AGENT_CONTEXT.md` as the task text suggested — AGENT_CONTEXT.md
# is protected by the /cchores INV-010 SKILL invariant (a diff allowlist), NOT
# by the SFG hook (it is absent from SFG DEFAULTS). The AGENT_CONTEXT INV-010
# boundary is exercised structurally in PRH-002 below, per spec RS-016.
art_exit="$(run_sfg "$ARTIFACT")"
env_exit="$(run_sfg ".env")"
if [ "$art_exit" = "0" ]; then
  pass "INV-005(b-allow)" "SFG hook allows Edit/Write to $ARTIFACT (exit 0 — not in effective protected set)"
else
  fail "INV-005(b-allow)" "SFG hook blocked $ARTIFACT (exit $art_exit) — artifact must stay unprotected (EXT-010)"
fi
if [ "$env_exit" = "2" ]; then
  pass "INV-005(b-control)" "SFG hook control: .env is blocked (exit 2) — protected set is live"
else
  fail "INV-005(b-control)" "SFG hook did not block .env control (exit $env_exit) — hook not exercising protection"
fi

# (c) artifact is tracked and not gitignored (PR-reaching).
if ! have_git; then
  skip "INV-005(c)" "git unavailable"
else
  if ( cd "$REPO_DIR" && git ls-files --error-unmatch "$ARTIFACT" ) >/dev/null 2>&1 \
     && ! ( cd "$REPO_DIR" && git check-ignore -q "$ARTIFACT" ) >/dev/null 2>&1; then
    pass "INV-005(c)" "$ARTIFACT is tracked and not gitignored (PR-staged)"
  else
    fail "INV-005(c)" "$ARTIFACT is not tracked / is gitignored — cannot reach the chore PR (PRH-001)"
  fi
fi

# PRH-002: behavioral INV-010 allowlist boundary via the SKILL.md diff-allowlist
# structure (the INV-010 logic is not independently invocable). A stage set
# containing AGENT_CONTEXT.md must still abort; the artifact must NOT be listed
# as an aborting path.
allowlist_block="$(awk '
  /^## Scoped commit \+ push/{found=1}
  found && /^## / && !/^## Scoped commit \+ push/{exit}
  found{print}
' "$CCHORES")"
# Fall back to the INV-010 section if the scoped-commit block lacks the ban.
if ! grep -qF "AGENT_CONTEXT.md" <<< "$allowlist_block"; then
  allowlist_block="$(awk '
    /^## INV-010/{found=1}
    found && /^## / && !/^## INV-010/{exit}
    found{print}
  ' "$CCHORES")"
fi
if grep -qF "AGENT_CONTEXT.md" <<< "$allowlist_block" && ! grep -qF "test-inventory.json" <<< "$allowlist_block"; then
  pass "PRH-002(boundary)" "INV-010 diff-allowlist aborts on AGENT_CONTEXT.md; the artifact is NOT an aborting path"
else
  fail "PRH-002(boundary)" "INV-010 diff-allowlist boundary changed — AGENT_CONTEXT.md abort missing or artifact wrongly banned"
fi

# ============================================================================
# INV-006 [integration]: consumer-scoped, ORDERED, exit-checked wiring.
# ============================================================================

section "INV-006: mechanism repro — staging order is load-bearing (EXT-001)"

if ! gen_present; then
  fail "INV-006(order-pos)" "scripts/gen-test-inventory.sh missing (RED)"
  fail "INV-006(order-neg)" "scripts/gen-test-inventory.sh missing (RED)"
  fail "INV-006(consumer-absent)" "scripts/gen-test-inventory.sh missing (RED)"
elif ! have_git || ! command -v jq >/dev/null 2>&1; then
  skip "INV-006(order-pos)" "git or jq unavailable"
else
  # POSITIVE arm: committed artifact at N -> STAGE net-new test -> regen ->
  # STAGE artifact -> R-006(c) mechanism PASSes.
  FXP="$TMPROOT/inv006-pos"
  build_fixture "$FXP" 3
  ( cd "$FXP" && bash scripts/gen-test-inventory.sh write && git add tests/test-inventory.json \
      && git commit -qm artifact ) >/dev/null 2>&1
  printf '#\n' > "$FXP/tests/test-zzz.sh"
  ( cd "$FXP" && git add tests/test-zzz.sh ) >/dev/null 2>&1          # stage NEW test first
  ( cd "$FXP" && bash scripts/gen-test-inventory.sh write ) >/dev/null 2>&1   # then regen
  ( cd "$FXP" && git add tests/test-inventory.json ) >/dev/null 2>&1  # then stage artifact
  if rc_mechanism "$FXP"; then
    pass "INV-006(order-pos)" "stage tests -> regen -> stage artifact keeps R-006(c) green"
  else
    fail "INV-006(order-pos)" "correct staging order did not keep R-006(c) green"
  fi

  # NEGATIVE arm: regen BEFORE staging the new test -> index count stale ->
  # R-006(c) mechanism FAILs (proves ordering is load-bearing).
  FXN="$TMPROOT/inv006-neg"
  build_fixture "$FXN" 3
  ( cd "$FXN" && bash scripts/gen-test-inventory.sh write && git add tests/test-inventory.json \
      && git commit -qm artifact ) >/dev/null 2>&1
  printf '#\n' > "$FXN/tests/test-zzz.sh"
  ( cd "$FXN" && bash scripts/gen-test-inventory.sh write ) >/dev/null 2>&1   # regen BEFORE staging
  ( cd "$FXN" && git add tests/test-zzz.sh ) >/dev/null 2>&1                  # stage new test AFTER
  if rc_mechanism "$FXN"; then
    fail "INV-006(order-neg)" "regen-before-stage did NOT break R-006(c) — ordering not load-bearing"
  else
    pass "INV-006(order-neg)" "regen-before-stage breaks R-006(c) (EXT-001 ordering is load-bearing)"
  fi

  # consumer-absent no-op: without the marker, wiring is a graceful no-op.
  FXC="$TMPROOT/inv006-noconsumer"
  mkdir -p "$FXC/tests" "$FXC/scripts"
  cp "$GEN" "$FXC/scripts/gen-test-inventory.sh"; chmod +x "$FXC/scripts/gen-test-inventory.sh"
  printf '#\n' > "$FXC/tests/test-fx1.sh"   # NO consumer marker
  ( cd "$FXC" && git init -q >/dev/null 2>&1 && git config user.email t@t && git config user.name t \
      && git add -A && git commit -qm init ) >/dev/null 2>&1
  ca_out="$( ( cd "$FXC" && bash scripts/gen-test-inventory.sh write ) 2>&1 )"; ca_rc=$?
  if [ "$ca_rc" -eq 0 ] && [ ! -f "$FXC/tests/test-inventory.json" ]; then
    pass "INV-006(consumer-absent)" "wiring no-ops on a non-consumer repo (nothing created, exit 0)"
  else
    fail "INV-006(consumer-absent)" "generator did not no-op on non-consumer repo (rc=$ca_rc, artifact-created=$( [ -f "$FXC/tests/test-inventory.json" ] && echo yes || echo no ))"
  fi
fi

# INV-006 block-scoped skill-prose wiring (stage -> regen -> stage-artifact).
section "INV-006: skill-prose staging/regeneration wiring (block-scoped)"

# /cchores: the scoped-commit block must invoke the generator and order
# test-file staging BEFORE regen and artifact staging AFTER (EXT-001/002/008).
cchores_block="$(awk '
  /^## Scoped commit \+ push/{found=1}
  found && /^## / && !/^## Scoped commit \+ push/{exit}
  found{print}
' "$CCHORES")"
if grep -qF "gen-test-inventory.sh" <<< "$cchores_block"; then
  # ordering: generator line must sit between a test-file `git add` and the
  # artifact `git add`.
  gen_line="$(grep -nF "gen-test-inventory.sh" <<< "$cchores_block" | head -1 | cut -d: -f1)"
  addtest_line="$(grep -niE "git add.*test.*\.sh|stage.*test" <<< "$cchores_block" | head -1 | cut -d: -f1)"
  addart_line="$(grep -niF "git add" <<< "$cchores_block" | grep -iF "test-inventory.json" | head -1 | cut -d: -f1)"
  if [ -n "$gen_line" ] && [ -n "$addtest_line" ] && [ -n "$addart_line" ] \
     && [ "$addtest_line" -lt "$gen_line" ] && [ "$gen_line" -lt "$addart_line" ]; then
    pass "INV-006(cchores-order)" "cchores stages tests before regen and stages the artifact after (EXT-001/002)"
  else
    fail "INV-006(cchores-order)" "cchores staging order not pinned (test-add=$addtest_line, gen=$gen_line, artifact-add=$addart_line)"
  fi
else
  fail "INV-006(cchores-order)" "cchores Scoped commit block does not invoke gen-test-inventory.sh (wiring absent — RED)"
fi

# /ctdd and /cdocs must document the stage -> regen -> stage-artifact wiring.
if grep -qF "gen-test-inventory.sh" "$CTDD"; then
  pass "INV-006(ctdd-wiring)" "ctdd documents gen-test-inventory.sh regeneration wiring"
else
  fail "INV-006(ctdd-wiring)" "ctdd missing gen-test-inventory.sh wiring (RED)"
fi
if grep -qF "gen-test-inventory.sh" "$CDOCS"; then
  pass "INV-006(cdocs-wiring)" "cdocs documents gen-test-inventory.sh regeneration wiring"
else
  fail "INV-006(cdocs-wiring)" "cdocs missing gen-test-inventory.sh wiring (RED)"
fi

# Source-form fallback (QA-002): each wiring snippet must invoke BOTH the
# installed form (`bash .correctless/scripts/gen-test-inventory.sh`) AND the bare
# source form (`bash scripts/gen-test-inventory.sh`), so /cchores does not abort
# on the correctless dev repo where .correctless/scripts/ is absent pre-setup. A
# future edit dropping the source-form fallback fails this. The `bash ` prefix
# disambiguates the bare source form from the `.correctless/…` substring.
for _sk in "cchores:$CCHORES" "ctdd:$CTDD" "cdocs:$CDOCS"; do
  _name="${_sk%%:*}"; _file="${_sk#*:}"
  if grep -qF "bash .correctless/scripts/gen-test-inventory.sh" "$_file" \
     && grep -qF "bash scripts/gen-test-inventory.sh" "$_file"; then
    pass "INV-006(source-fallback-$_name)" "$_name wiring invokes BOTH installed + bare source-form generator (fallback present)"
  else
    fail "INV-006(source-fallback-$_name)" "$_name wiring missing the bare source-form fallback (bash scripts/gen-test-inventory.sh) — /cchores would abort pre-install (QA-002)"
  fi
done

# INV-006 guard-scoping (MA-M1): in /ctdd and /cdocs the `git add tests/test-*.sh`
# must sit INSIDE the `if [ -f tests/test-ap031-fixture-divergence.sh ]` consumer
# guard (block-scoped, like INV-006(cchores-order)). Placed BEFORE the guard it
# would hard-fail (`fatal: pathspec did not match`, exit 128) on a downstream
# repo lacking matching tests/test-*.sh. The generator invocation still runs
# AFTER the staging (stage -> regen -> stage-artifact order preserved).
for _sk in "ctdd:$CTDD" "cdocs:$CDOCS"; do
  _name="${_sk%%:*}"; _file="${_sk#*:}"
  guard_ln="$(grep -nF 'if [ -f tests/test-ap031-fixture-divergence.sh ]; then' "$_file" | head -1 | cut -d: -f1)"
  addtest_ln="$(grep -nE 'git add tests/test-\*\.sh' "$_file" | head -1 | cut -d: -f1)"
  gen_ln="$(grep -nF 'gen-test-inventory.sh write' "$_file" | head -1 | cut -d: -f1)"
  if [ -n "$guard_ln" ] && [ -n "$addtest_ln" ] && [ -n "$gen_ln" ] \
     && [ "$addtest_ln" -gt "$guard_ln" ] && [ "$addtest_ln" -lt "$gen_ln" ]; then
    pass "INV-006(guard-scopes-testadd-$_name)" "$_name stages tests INSIDE the guard, before regen (guard=$guard_ln < add=$addtest_ln < gen=$gen_ln — MA-M1)"
  else
    fail "INV-006(guard-scopes-testadd-$_name)" "$_name 'git add tests/test-*.sh' not scoped inside the guard before regen (guard=$guard_ln add=$addtest_ln gen=$gen_ln)"
  fi
done

# ============================================================================
# INV-007 [unit] structural: no file under tests/ scrapes the AGENT_CONTEXT.md
# Tests-row count. (Becomes true once R-006(c) is repointed to the artifact —
# done in this RED changeset; DECISION: this guard is GREEN post-repoint, and
# the wiring file overall stays RED via the assertions above.)
# ============================================================================

section "INV-007: no test scrapes the AGENT_CONTEXT.md test-count (structural)"

scrape_hits=""
for _f in "$REPO_DIR"/tests/test*.sh; do
  case "${_f##*/}" in "$THIS_BASENAME") continue ;; esac
  _h="$(grep -nE 'AGENT_CONTEXT' "$_f" 2>/dev/null | grep -iE 'test files?|test scripts?' | grep -E '[0-9]|grep -o|documented_count|wc -l' || true)"
  [ -n "$_h" ] && scrape_hits="${scrape_hits}${_f}: ${_h}"$'\n'
done
if [ -z "$scrape_hits" ]; then
  pass "INV-007(no-scrape)" "no tests/ file greps/extracts the AGENT_CONTEXT.md test-count row"
else
  fail "INV-007(no-scrape)" "a tests/ file still scrapes the AGENT_CONTEXT.md test count: $scrape_hits"
fi

# INV-007 positive (MA-H2): the AGENT_CONTEXT.md Tests row must be CONVERTED to
# the informational form — its count starts with `~` (NO leading bare digit, so
# prune-scan's digit-anchored extractor skips it) AND it carries a
# tests/test-inventory.json authoritative-source pointer. An unconverted/stale
# exact figure ("108 test files") FAILS here — this is the positive complement
# to the negative no-scrape property above.
AGENT_CTX="$REPO_DIR/.correctless/AGENT_CONTEXT.md"
if [ ! -f "$AGENT_CTX" ]; then
  fail "INV-007(row-converted)" ".correctless/AGENT_CONTEXT.md not found"
else
  tests_row="$(grep -E '^\| *Tests *\|' "$AGENT_CTX" | head -1)"
  # count field = 4th pipe-delimited column ($1 is empty, before the first pipe).
  count_field="$(printf '%s' "$tests_row" | awk -F'|' '{print $4}' | sed 's/^[[:space:]]*//')"
  if printf '%s' "$count_field" | grep -qE '^~' \
     && grep -qF 'test-inventory.json' <<< "$tests_row"; then
    pass "INV-007(row-converted)" "AGENT_CONTEXT Tests row is informational (~-prefixed count + test-inventory.json pointer)"
  else
    fail "INV-007(row-converted)" "AGENT_CONTEXT Tests row not converted (count_field='$count_field' — needs ~-prefix AND test-inventory.json pointer)"
  fi
fi

# ============================================================================
# INV-008 [integration]: distribution parity — producer mirrored; tests/ not.
# ============================================================================

section "INV-008: distribution parity"

if [ -f "$GEN_MIRROR" ]; then
  if [ -f "$GEN" ] && diff -q "$GEN" "$GEN_MIRROR" >/dev/null 2>&1; then
    pass "INV-008(mirror)" "correctless/scripts/gen-test-inventory.sh mirrors the source (identical)"
  else
    fail "INV-008(mirror)" "generator mirror diverges from source (run sync.sh)"
  fi
else
  fail "INV-008(mirror)" "correctless/scripts/gen-test-inventory.sh missing (mirror absent — RED)"
fi

# sync --check must be green (informational-but-required parity gate).
sync_script="$REPO_DIR/sync.sh"
if [ -f "$sync_script" ]; then
  if ( cd "$REPO_DIR" && bash "$sync_script" --check ) >/dev/null 2>&1; then
    pass "INV-008(sync-check)" "sync.sh --check is green"
  else
    fail "INV-008(sync-check)" "sync.sh --check is red (source/mirror drift)"
  fi
else
  skip "INV-008(sync-check)" "sync.sh not found"
fi

# tests/ is NOT mirrored: no correctless/tests copy of the artifact or consumer.
if [ ! -f "$REPO_DIR/correctless/tests/test-inventory.json" ] \
   && [ ! -f "$REPO_DIR/correctless/tests/test-ap031-fixture-divergence.sh" ]; then
  pass "INV-008(no-dist-tests)" "no correctless/tests copy of the artifact or R-006(c) consumer (tests/ not mirrored)"
else
  fail "INV-008(no-dist-tests)" "a correctless/tests copy of the artifact or consumer exists — tests/ must not be mirrored"
fi

# ============================================================================
# INV-009 [unit]: allowed-tools coverage + unchanged Group B + new-test naming.
# ============================================================================

section "INV-009: allowed-tools coverage + Group B + new-test naming"

# allowed-tools must cover the generator invocation for each wiring skill —
# via Bash(*) OR both the installed (.correctless/scripts/...) and source
# (scripts/...) globs (glob-covers-invocation, not presence-only).
check_allowed_tools() {
  local id="$1" file="$2" at
  at="$(get_frontmatter_field "$file" "allowed-tools" 2>/dev/null || true)"
  if grep -qF 'Bash(*)' <<< "$at"; then
    pass "$id" "allowed-tools has Bash(*) — covers the generator invocation"
    return
  fi
  local has_installed=0 has_source=0
  grep -qF ".correctless/scripts/gen-test-inventory.sh" <<< "$at" && has_installed=1
  grep -qE '[( ]scripts/gen-test-inventory\.sh' <<< "$at" && has_source=1
  if [ "$has_installed" -eq 1 ] && [ "$has_source" -eq 1 ]; then
    pass "$id" "allowed-tools covers both installed + source generator globs"
  else
    fail "$id" "allowed-tools missing generator glob (installed=$has_installed source=$has_source — RED)"
  fi
}
check_allowed_tools "INV-009(cchores-at)" "$CCHORES"
check_allowed_tools "INV-009(ctdd-at)"    "$CTDD"
check_allowed_tools "INV-009(cdocs-at)"   "$CDOCS"

# INV-009 Enforcement (spec): glob-COVERS-invocation, not presence-only. Extract
# each `bash ...gen-test-inventory.sh ...` invocation from the SKILL.md prose and
# assert each is covered by at least one declared allowed-tools Bash(...) glob. A
# prose invocation whose path/flags fall outside every declared glob FAILs. In
# RED (no prose invocation yet) this is dormant and SKIPs; it activates in GREEN
# and catches an invocation the allowed-tools globs do not cover.
covers_invocation() {
  local id="$1" file="$2" at
  at="$(get_frontmatter_field "$file" "allowed-tools" 2>/dev/null || true)"
  local -a globs=() invs=()
  mapfile -t globs < <(grep -oE 'Bash\([^)]*\)' <<< "$at" | sed -E 's/^Bash\(//; s/\)$//')
  mapfile -t invs < <(grep -oE 'bash [[:alnum:]_./ -]*gen-test-inventory\.sh[[:alnum:]_. -]*' "$file" \
                        | sed -E 's/[[:space:]]+$//' | sort -u)
  if [ "${#invs[@]}" -eq 0 ]; then
    skip "$id" "no prose gen-test-inventory.sh invocation yet (dormant — activates in GREEN)"
    return
  fi
  local inv g pfx covered uncovered=0 bad=""
  for inv in "${invs[@]}"; do
    [ -z "$inv" ] && continue
    covered=0
    for g in "${globs[@]:-}"; do
      [ -z "$g" ] && continue
      if [ "$g" = "*" ]; then covered=1; break; fi
      case "$g" in
        *\*) pfx="${g%\*}"; case "$inv" in "$pfx"*) covered=1; break;; esac ;;
        *)   [ "$g" = "$inv" ] && { covered=1; break; } ;;
      esac
    done
    [ "$covered" -eq 0 ] && { uncovered=1; bad="${bad}[${inv}]"; }
  done
  if [ "$uncovered" -eq 0 ]; then
    pass "$id" "every prose gen-test-inventory.sh invocation is covered by a declared Bash(...) glob (${#invs[@]})"
  else
    fail "$id" "uncovered prose invocation(s) not matched by any allowed-tools glob: $bad"
  fi
}
covers_invocation "INV-009(cchores-covers)" "$CCHORES"
covers_invocation "INV-009(ctdd-covers)"    "$CTDD"
covers_invocation "INV-009(cdocs-covers)"   "$CDOCS"

# cchores disallowed-tools == exactly the 4-item Group B set, UNCHANGED.
cchores_dis="$(get_frontmatter_field "$CCHORES" "disallowed-tools" 2>/dev/null || true)"
norm_dis="$(printf '%s' "$cchores_dis" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -v '^$' | sort | tr '\n' ',' )"
if [ "$norm_dis" = "CreateFile,Edit,MultiEdit,NotebookEdit," ]; then
  pass "INV-009(groupB)" "cchores disallowed-tools == exactly Group B (Edit, MultiEdit, NotebookEdit, CreateFile)"
else
  fail "INV-009(groupB)" "cchores disallowed-tools changed from Group B (got: '$cchores_dis')"
fi

# any new test script this feature adds matches tests/test-*.sh.
naming_ok=1
for _nf in "$REPO_DIR/tests/test-gen-test-inventory.sh" "$REPO_DIR/tests/test-test-inventory-wiring.sh"; do
  case "${_nf##*/}" in test-*.sh) ;; *) naming_ok=0 ;; esac
done
if [ "$naming_ok" -eq 1 ]; then
  pass "INV-009(naming)" "new test scripts match tests/test-*.sh (picked up by commands.test + CI glob)"
else
  fail "INV-009(naming)" "a new test script does not match tests/test-*.sh"
fi

# ============================================================================
# Summary
# ============================================================================

summary "test-inventory.json Wiring / SFG / Distribution Tests (#219)"
