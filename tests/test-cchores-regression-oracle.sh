#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091,SC2016,SC2034,SC2086
# Correctless — /cchores INV-008 Regression-Oracle tests (RED phase)
#
# Tests ONE rule from .correctless/specs/cchores.md: INV-008 (Regression check —
# pinned flake algorithm, portable, committed-fix substrate, CI-superset).
# Supporting clauses: PRH-001, DD-006, BND-002, EA-004, EA-006, AP-031/033/035/038/039.
#
# RED phase: these tests MUST FAIL — the deliverables do not exist yet:
#   skills/cchores/SKILL.md            (the prose home of the regression-oracle algorithm)
#   scripts/cchores-regression-oracle.sh  (the MANDATORY coded oracle entrypoint)
#
# Test shape:
#   - PRIMARY / BEHAVIORAL (coded oracle — MANDATORY): the INV-008 verdict logic
#     is driven through ONE pinned, coded entrypoint — scripts/cchores-regression-oracle.sh
#     — NOT a list of optional candidate names. This is a deliberate test-audit-
#     driven PROMOTION of the spec's "MAY be extracted" to "MUST be extracted"
#     for testability (PAT-018 structural-over-prompt; AP-026 advisory-prose-is-
#     not-a-contract). Verdict logic that has no structural prose anchor (touched-
#     file-never-retried, unknown=real fail-closed) is carried HERE, by asserting
#     the exact verdict token the oracle emits for each fixture. The helper is
#     absent in RED → the PRE existence assertion and every ORC behavioral test
#     FAIL. GREEN MUST create scripts/cchores-regression-oracle.sh implementing
#     the verdict contract (see assert_oracle_verdict below).
#   - SECONDARY / STRUCTURAL (backstop): the regression-oracle algorithm's prose
#     home is SKILL.md. We assert the SKILL documents EACH INV-008 clause with the
#     EXACT thresholds (committed-fix precondition, empty-diff abort, test_file_marker
#     degrade, test_fail_pattern preflight abort, file-not-argv capture, N=2 retry,
#     120s timeout, touched-file-never-retried, unknown=real fail-closed, CI-superset
#     list). These remain a backstop — the ORC behavioral block is now the PRIMARY
#     INV-008 test. These FAIL now because SKILL.md is absent.
#
# Fixtures (AP-031 real + AP-033 constructed-realistic):
#   - F-REAL  : verbatim real `commands.test` output from THIS repo (all-green,
#               exit 0). Cited # Source below. Contains the `FAIL: 0` summary
#               lines and the `echo FAIL:` exempt line — the unparsable/ambiguous
#               hazard the oracle must NOT mistake for a real failure.
#   - F-SIGPIPE: constructed-but-realistic #186 SIGPIPE roaming-flake shape
#               (EA-004/AP-033). Appears in a DIFFERENT file across runs.
#
# Run from repo root: bash tests/test-cchores-regression-oracle.sh

source "$(dirname "${BASH_SOURCE[0]}")/test-helpers.sh"
set -f

# ============================================================================
# Deliverable paths (all ABSENT in RED — assertions FAIL until GREEN)
# ============================================================================

SKILL="$REPO_DIR/skills/cchores/SKILL.md"
SKILL_MIRROR="$REPO_DIR/correctless/skills/cchores/SKILL.md"

# The INV-008 verdict logic MUST be extracted into ONE pinned, coded helper for
# behavioral testing (test-audit-driven promotion of the spec's "MAY" to "MUST";
# PAT-018 / AP-026). GREEN MUST create exactly this path — no candidate fallbacks.
ORACLE="$REPO_DIR/scripts/cchores-regression-oracle.sh"

REAL_FIXTURE="$REPO_DIR/tests/fixtures/cchores-real-test-output.txt"

# Cached skill text (empty if absent — every grep then FAILs, the RED state).
SKILL_SRC=""
[ -f "$SKILL" ] && SKILL_SRC="$(cat "$SKILL")"

# ----------------------------------------------------------------------------
# Local assertion helpers (2-arg id/desc signature, matching test-helpers.sh)
# ----------------------------------------------------------------------------

# Assert SKILL text matches an ERE (case-insensitive). FAILs when SKILL absent.
assert_skill() {
  local id="$1" desc="$2" pattern="$3"
  if [ -n "$SKILL_SRC" ] && grep -qiE "$pattern" <<<"$SKILL_SRC"; then
    pass "$id" "$desc"
  else
    fail "$id" "$desc (no SKILL.md match for /$pattern/)"
  fi
}

# Assert SKILL text matches BOTH EREs somewhere (co-occurrence, not adjacency).
assert_skill_both() {
  local id="$1" desc="$2" pat_a="$3" pat_b="$4"
  if [ -n "$SKILL_SRC" ] \
     && grep -qiE "$pat_a" <<<"$SKILL_SRC" \
     && grep -qiE "$pat_b" <<<"$SKILL_SRC"; then
    pass "$id" "$desc"
  else
    fail "$id" "$desc (SKILL.md missing one of /$pat_a/ , /$pat_b/)"
  fi
}

assert_file_exists() {
  local id="$1" desc="$2" path="$3"
  if [ -f "$path" ]; then
    pass "$id" "$desc"
  else
    fail "$id" "$desc (missing: $path)"
  fi
}

# Drive a captured-output FILE through the PINNED oracle and assert the verdict
# token. Contract (GREEN MUST honor) — the oracle at $ORACLE:
#   - reads the runner output from a FILE path argument (NEVER via argv content —
#     AP-039); the output file is positional arg 1.
#   - accepts the flags: --touched <file>, --rerun-pass|--rerun-fail (or
#     --rerun <file>), --diff <range/file> | --diff-empty,
#     --shellcheck-rc <N|file>, --sync-rc <N|file>, --sfglift-rc <N|file>.
#   - emits a SINGLE verdict token on stdout — one of: block | tolerate | abort |
#     pass — and exits 0.
# We assert by grepping stdout for the expected verdict word, fail-closed: if the
# helper is absent (RED) OR the verdict word is missing, the test FAILS.
assert_oracle_verdict() {
  local id="$1" desc="$2" expected="$3" outfile="$4"; shift 4
  if [ ! -x "$ORACLE" ]; then
    fail "$id" "$desc (pinned oracle absent/non-exec: $ORACLE — RED; GREEN must create it)"
    return
  fi
  local got
  got="$(bash "$ORACLE" "$outfile" "$@" 2>/dev/null || true)"
  if grep -qiw "$expected" <<<"$got"; then
    pass "$id" "$desc"
  else
    fail "$id" "$desc (expected verdict '$expected', got: $(printf '%s' "$got" | tr '\n' ' ' | head -c 120))"
  fi
}

# ============================================================================
# Fixtures — written to a tmp dir; captured runner output lives in FILES
# (AP-039: the oracle parses FROM a file, never from argv content).
# ============================================================================

FIXDIR="$(mktemp -d)"
trap 'rm -rf "$FIXDIR"' EXIT

# --- F-REAL : verbatim real `commands.test` output (all-green, exit 0) --------
# Source: tests/fixtures/cchores-real-test-output.txt
# A copy of the repo's real test runner output. 94 `>>> file` markers, all green.
# Contains `FAIL: 0` summary lines (e.g. baseline L579/L772) and the exempt line
# `PASS: B-09: 'echo FAIL:' not flagged` — the ambiguity the oracle must resolve:
# a bare `test_fail_pattern: "FAIL:"` matches these but they are NOT real failures.
F_REAL="$FIXDIR/f-real.txt"
if [ -f "$REAL_FIXTURE" ]; then
  cp "$REAL_FIXTURE" "$F_REAL"
else
  : > "$F_REAL"   # absent → behavioral real-fixture tests still FAIL (RED)
fi

# --- F-SIGPIPE : constructed-but-realistic #186 SIGPIPE roaming-flake shape ---
# CONSTRUCTED FIXTURE (not a verbatim capture). Models EA-004/AP-033: the #186
# SIGPIPE flake roams — it surfaces in a DIFFERENT test file across runs. Here it
# lands in an UNTOUCHED file and passes on re-run → must be TOLERATED, not blocked.
# Shape mirrors a real pipefail-SIGPIPE line: the suite emits a `FAIL:` line whose
# cause is `141` (128+SIGPIPE) inside a `<cmd> | grep -q` pipeline.
F_SIGPIPE="$FIXDIR/f-sigpipe.txt"
cat > "$F_SIGPIPE" <<'EOF'
>>> tests/test-canonicalize-path.sh
  PASS: CP-001: canonicalize resolves ..
>>> tests/test-prune-scan-slug-aware.sh
  FAIL: PSA-014: pattern scan (exit 141 — broken pipe in `prune-scan.sh | grep -q`)
>>> tests/test-workflow-gate.sh
  PASS: WG-001: gate allows on approved spec
FAIL: 1
EOF
# Re-run of the same UNTOUCHED file passes (the roam moved on) — used by the
# "tolerate" behavioral test as the N=2 re-run substrate.
F_SIGPIPE_RERUN="$FIXDIR/f-sigpipe-rerun.txt"
cat > "$F_SIGPIPE_RERUN" <<'EOF'
>>> tests/test-prune-scan-slug-aware.sh
  PASS: PSA-014: pattern scan
FAIL: 0
EOF

# --- F-PERSIST : a persistent real failure (blocks; never a flake) -----------
F_PERSIST="$FIXDIR/f-persist.txt"
cat > "$F_PERSIST" <<'EOF'
>>> tests/test-redact-secrets.sh
  FAIL: RS-007: AWS access key id not redacted
FAIL: 1
EOF

# --- F-TOUCHED : a failure in a TOUCHED file (blocks — never retried away) ----
F_TOUCHED="$FIXDIR/f-touched.txt"
cat > "$F_TOUCHED" <<'EOF'
>>> tests/test-cchores.sh
  FAIL: INV-008c: oracle degrade-mode notice missing
FAIL: 1
EOF
# The touched set (git diff --name-only {default}...HEAD), post-commit form.
TOUCHED_SET="$FIXDIR/touched.txt"
cat > "$TOUCHED_SET" <<'EOF'
skills/cchores/SKILL.md
tests/test-cchores.sh
EOF

# --- F-UNPARSABLE : output the oracle cannot parse (blocks, fail-closed) ------
# A `FAIL:`-matching line with NO recoverable `>>> file` association — unknown
# provenance. INV-008: unknown = real, fail-closed → BLOCK.
F_UNPARSABLE="$FIXDIR/f-unparsable.txt"
cat > "$F_UNPARSABLE" <<'EOF'
some interleaved runner noise without a file marker
  FAIL: (no file context) assertion blew up mid-stream
EOF

# --- F-DIFF-EMPTY : a --diff <range|file> argument that resolves to an EMPTY diff
# Models QA-006: the committed-substrate precondition (AP-035) is enforced in the
# CODED oracle, not just SKILL prose. A --diff arg naming a file with no non-blank
# lines is an empty diff → the oracle must ABORT exactly like --diff-empty does,
# WITHOUT the caller having to also pass --diff-empty.
F_DIFF_EMPTY_FILE="$FIXDIR/diff-empty.txt"
: > "$F_DIFF_EMPTY_FILE"   # zero-length → empty diff

# --- F-CI : the suite is GREEN but a CI-superset check is RED -----------------
# (shellcheck / sync.sh --check / check-no-pending-sfg-lift.sh). Models AP-038:
# INV-008 green must still BLOCK when the CI superset is red.
F_CI_GREEN_SUITE="$F_REAL"   # suite itself green
CI_SHELLCHECK_RC="$FIXDIR/ci-shellcheck.rc"; echo "1" > "$CI_SHELLCHECK_RC"
CI_SYNC_RC="$FIXDIR/ci-sync.rc";             echo "0" > "$CI_SYNC_RC"
CI_SFGLIFT_RC="$FIXDIR/ci-sfglift.rc";       echo "0" > "$CI_SFGLIFT_RC"

# ============================================================================
# PRE — deliverables exist? (the RED anchor)
# ============================================================================
section "Preconditions (RED anchor — all FAIL until GREEN)"

# Tests INV-008 [structural]: the algorithm's prose home must exist.
assert_file_exists "PRE-001" "skills/cchores/SKILL.md exists (regression-oracle prose home)" "$SKILL"
assert_file_exists "PRE-002" "correctless/skills/cchores/SKILL.md mirror exists" "$SKILL_MIRROR"

# Tests INV-008 [behavioral, MANDATORY]: the pinned coded oracle entrypoint must
# exist AND be executable. This is the test-audit-driven promotion of the spec's
# "MAY be extracted" to "MUST be extracted" (PAT-018 / AP-026) — mirrors the
# redactor's INV013-EXISTS contract. The ORC behavioral block below drives every
# fixture through THIS exact path; GREEN MUST create it. Absent in RED → FAIL.
if [ -f "$ORACLE" ] && [ -x "$ORACLE" ]; then
  pass "ORACLE-EXISTS" "scripts/cchores-regression-oracle.sh exists and is executable (pinned INV-008 oracle entrypoint)"
else
  fail "ORACLE-EXISTS" "pinned INV-008 oracle missing or non-executable: $ORACLE (GREEN must create scripts/cchores-regression-oracle.sh)"
fi

# Tests AP-031: the real-output fixture must be present and be a real capture.
assert_file_exists "PRE-003" "real commands.test fixture present (AP-031 real-fixture)" "$REAL_FIXTURE"
# DECISION: assert the fixture truly is the repo's runner output by checking it
# carries the `>>> file` echo shape AND a `FAIL: 0` summary AND the `echo FAIL:`
# exempt line — the three properties that make it the ambiguity testbed. Spec
# INV-008 line: "does NOT silently hard-fit correctless's `>>> {file}` echo".
if [ -f "$REAL_FIXTURE" ] \
   && grep -q '^>>> tests/' "$REAL_FIXTURE" \
   && grep -q 'FAIL: 0' "$REAL_FIXTURE" \
   && grep -q "echo FAIL:" "$REAL_FIXTURE"; then
  pass "PRE-004" "real fixture carries >>> echo + 'FAIL: 0' summary + 'echo FAIL:' exempt (ambiguity testbed)"
else
  fail "PRE-004" "real fixture missing the >>> / 'FAIL: 0' / 'echo FAIL:' ambiguity shape"
fi

# ============================================================================
# INV-008 clause 1 — committed-fix substrate precondition (AP-035 / RS-009)
# ============================================================================
section "INV-008.1: committed-fix substrate precondition (AP-035)"

# Tests INV-008 [structural]: oracle runs ONLY after the fix is committed.
assert_skill_both "INV-008-1a" "SKILL documents oracle runs only after the fix is committed to the chore branch" \
  "only after the fix is committed|after the fix is committed|committed[ -]fix" \
  "git diff [^\n]*\.\.\.HEAD"

# Tests INV-008 [structural]: empty diff = ABORT (never "all failures untouched").
assert_skill "INV-008-1b" "SKILL pins empty-diff = ABORT (committed-substrate precondition)" \
  "empty diff[^a-z]*=?[^a-z]*abort|empty[ -]diff.*abort|diff .*non-empty"

# Tests INV-008 [structural / AP-035]: the empty-diff path must NOT degrade to
# "all failures untouched" (the failure mode the spec explicitly bans).
assert_skill "INV-008-1c" "SKILL bans the 'all failures untouched' interpretation of an empty diff" \
  "never .*all failures untouched|not .*all failures untouched|all failures untouched"

# ============================================================================
# INV-008 clause 2 — test_file_marker config field + explicit degrade
# ============================================================================
section "INV-008.2: patterns.test_file_marker + explicit degrade (RS-001)"

# Tests INV-008 [structural]: failing FILES extracted via test_fail_pattern AND
# the NEW patterns.test_file_marker (default empty).
assert_skill_both "INV-008-2a" "SKILL extracts failing files via test_fail_pattern AND patterns.test_file_marker" \
  "test_fail_pattern" \
  "patterns\.test_file_marker|test_file_marker"

# Tests INV-008 [structural]: when test_file_marker is EMPTY, degrade EXPLICITLY
# to "any persistent suite failure blocks the PR" (no per-file flake tolerance).
assert_skill "INV-008-2b" "SKILL degrades to whole-suite-blocking when test_file_marker is empty" \
  "marker is empty|empty.*marker|degrade[s]? .*(whole|any persistent|suite).*block"

# Tests INV-008 [structural]: the degrade path must be ANNOUNCED in the run report.
assert_skill "INV-008-2c" "SKILL says the degrade is announced in the run report" \
  "(run report|report).*(degrade|whole[ -]suite|no per-file)|degrade.*report"

# Tests INV-008 [structural / AP-031]: must NOT silently hard-fit the `>>> {file}`
# echo. The whole point of the configurable marker is to avoid hard-coding it.
assert_skill "INV-008-2d" "SKILL does NOT silently hard-fit correctless's '>>> {file}' echo" \
  ">>> ?\{?file\}?|does not .*hard-?fit|not .*hard-?fit"

# ============================================================================
# INV-008 clause 3 — empty test_fail_pattern → PREFLIGHT abort (BND-002)
# ============================================================================
section "INV-008.3: empty test_fail_pattern → preflight abort (BND-002)"

# Tests INV-008/BND-002 [structural]: empty test_fail_pattern aborts at PREFLIGHT
# (not after burning a /cdebug cycle), with a "configure patterns.test_fail_pattern"
# message.
assert_skill_both "INV-008-3a" "SKILL aborts at preflight when test_fail_pattern is empty, before /cdebug" \
  "preflight|BND-002" \
  "test_fail_pattern"

assert_skill "INV-008-3b" "SKILL emits a 'configure patterns.test_fail_pattern' remediation message" \
  "configure .*test_fail_pattern|set .*test_fail_pattern"

assert_skill "INV-008-3c" "SKILL pins that the abort is BEFORE burning a /cdebug cycle" \
  "before .*(burning|running|a /?cdebug)|not after .*cdebug|preflight"

# ============================================================================
# INV-008 clause 4 — runner output captured to FILE, parsed from FILE (AP-039)
# ============================================================================
section "INV-008.4: file-passthrough capture, never argv (AP-039)"

# Tests INV-008 [structural / AP-039]: runner output captured to a FILE and parsed
# FROM the file, never via argv (unbounded-through-bounded-medium).
assert_skill "INV-008-4a" "SKILL captures runner output to a file and parses from the file (not argv)" \
  "captured? .*to a file|parse[d]? from (the|a) file|output .*to a file"

assert_skill "INV-008-4b" "SKILL explicitly bans passing runner output via argv (AP-039)" \
  "never .*argv|not .*argv|AP-039"

# ============================================================================
# INV-008 clause 5 — per-file flake rule: NOT-touched AND passes-on-rerun
# N=2 retries, 120s per-file timeout (EA-006)
# ============================================================================
section "INV-008.5: flake tolerance — N=2, 120s, touched-set guard (EA-006)"

# Tests INV-008 [structural]: a failing file is a REAL regression UNLESS BOTH
# (a) NOT in the touched set, AND (b) passes on re-run.
assert_skill "INV-008-5a" "SKILL requires BOTH (not-touched) AND (passes-on-rerun) to tolerate a flake" \
  "both|and.*passes on re-?run|not in the touched set.*passes"

# Tests INV-008 [structural]: touched set = git diff --name-only {default}...HEAD,
# which post-commit includes formerly-untracked files.
assert_skill_both "INV-008-5b" "SKILL defines touched set via git diff --name-only and notes post-commit untracked inclusion" \
  "git diff --name-only [^\n]*\.\.\.HEAD" \
  "untracked|formerly[ -]untracked|post-?commit"

# Tests INV-008 [structural]: retried up to N=2.
assert_skill "INV-008-5c" "SKILL pins retry budget N=2" \
  "N ?= ?2|up to 2|2 (re-?tries|re-?runs)|twice"

# Tests INV-008 [structural / EA-006]: per-file timeout of 120s.
assert_skill "INV-008-5d" "SKILL pins per-file timeout of 120s" \
  "120 ?s|120 ?seconds|timeout .*120"

# Tests INV-008/EA-006 [structural]: timeout(1)/gtimeout availability asserted at preflight.
assert_skill_both "INV-008-5e" "SKILL asserts timeout(1)/gtimeout availability at preflight (EA-006)" \
  "timeout|gtimeout" \
  "preflight|BND-002|EA-006"

# ============================================================================
# INV-008 clause 6 — BLOCK rules: persist | touched | unparsable (fail-closed)
# ============================================================================
section "INV-008.6: block rules — persist / touched / unparsable=fail-closed"

# Tests INV-008/PRH-001 [structural]: any failure that PERSISTS blocks.
assert_skill "INV-008-6a" "SKILL blocks the PR on a persistent failure" \
  "persist(s|ent)?.*block|block.*persist"

# Tests INV-008 [structural]: a TOUCHED-file failure blocks — never retried away.
assert_skill "INV-008-6b" "SKILL blocks a touched-file failure and never retries it away" \
  "touched.*(block|never retried)|never retried .*touched|touched-?file failure"

# Tests INV-008 [structural]: unparsable output → unknown = real → fail-closed → block.
assert_skill_both "INV-008-6c" "SKILL treats unparsable output as real (unknown=real, fail-closed) and blocks" \
  "unparse?able|cannot be parsed|unknown" \
  "fail[ -]closed|unknown ?= ?real|real, fail-?closed"

# ============================================================================
# INV-008 clause 7 — CI-superset pre-PR gate (AP-038 / DD-006)
# ============================================================================
section "INV-008.7: CI-superset pre-PR gate (AP-038 / DD-006)"

# Tests INV-008/DD-006 [structural]: pre-PR gate is a CI SUPERSET.
assert_skill "INV-008-7a" "SKILL declares the pre-PR gate is a CI superset (DD-006)" \
  "CI superset|superset.*CI|CI[ -]superset"

# Tests INV-008 [structural]: before gh pr create, also run shellcheck.
assert_skill_both "INV-008-7b" "SKILL runs shellcheck before gh pr create" \
  "shellcheck" \
  "gh pr create|before .*PR"

# Tests INV-008 [structural]: also run sync.sh --check.
assert_skill "INV-008-7c" "SKILL runs sync.sh --check in the CI-superset gate" \
  "sync\.sh --check"

# Tests INV-008 [structural]: also run check-no-pending-sfg-lift.sh.
assert_skill "INV-008-7d" "SKILL runs check-no-pending-sfg-lift.sh in the CI-superset gate" \
  "check-no-pending-sfg-lift\.sh"

# Tests INV-008/PRH-001 [structural]: any non-zero in the superset blocks the PR.
assert_skill "INV-008-7e" "SKILL blocks the PR on any non-zero CI-superset check" \
  "any non-?zero.*block|non-?zero.*(blocks|aborts) the PR|blocks the PR"

# ============================================================================
# PRH-001 — never PR an unverified / regressing / CI-dirty / empty-diff fix
# ============================================================================
section "PRH-001: no PR on unverified / regressing / CI-dirty / empty-diff fix"

# Tests PRH-001 [structural]: the prohibition enumerates ALL block triggers.
assert_skill "PRH-001a" "SKILL documents PRH-001: no PR while a real regression stands" \
  "no PR.*(regress|unverified|CI[ -]dirty)|regress.*no PR"

assert_skill "PRH-001b" "SKILL ties the empty-diff / uncommitted fix to a no-PR prohibition" \
  "uncommitted|empty[ -]diff.*(no PR|abort)|no PR.*empty"

# ============================================================================
# PRIMARY — drive the six/seven canonical fixtures through the PINNED coded
# oracle (scripts/cchores-regression-oracle.sh). All FAIL in RED (helper absent).
# GREEN MUST create exactly that path. This is now the PRIMARY INV-008 test; the
# SKILL prose greps above are a SECONDARY structural backstop. Verdict contract:
# stdout contains exactly one of  block | tolerate | abort | pass .
# This block carries the verdict-logic clauses with no structural prose anchor
# (touched-file-never-retried → ORC-iii; unknown=real fail-closed → ORC-iv).
# ============================================================================
section "INV-008 behavioral (PRIMARY): fixtures through the pinned coded oracle"

# (i) Tests INV-008 [behavioral]: persistent failure → BLOCK.
assert_oracle_verdict "ORC-i"  "persistent failure blocks the PR" \
  "block" "$F_PERSIST" --touched "$TOUCHED_SET"

# (ii) Tests INV-008/EA-004 [behavioral]: untouched-file #186 SIGPIPE flake that
# passes on re-run → TOLERATE. (Constructed-realistic SIGPIPE shape.)
assert_oracle_verdict "ORC-ii" "untouched SIGPIPE flake that passes on re-run is tolerated" \
  "tolerate" "$F_SIGPIPE" --touched "$TOUCHED_SET" --rerun-pass --rerun "$F_SIGPIPE_RERUN"

# (iii) Tests INV-008 [behavioral]: touched-file failure → BLOCK (never retried).
assert_oracle_verdict "ORC-iii" "touched-file failure blocks (never retried away)" \
  "block" "$F_TOUCHED" --touched "$TOUCHED_SET"

# (iv) Tests INV-008 [behavioral]: unparsable output → BLOCK (unknown=real, fail-closed).
assert_oracle_verdict "ORC-iv" "unparsable output blocks (fail-closed)" \
  "block" "$F_UNPARSABLE" --touched "$TOUCHED_SET"

# (v) Tests INV-008/AP-035 [behavioral]: empty diff → ABORT (never "all untouched").
assert_oracle_verdict "ORC-v" "empty diff aborts the run (committed-substrate precondition)" \
  "abort" "$F_REAL" --touched "$TOUCHED_SET" --diff-empty

# (vi) Tests INV-008/AP-038 [behavioral]: suite green but a CI-superset check red → BLOCK.
assert_oracle_verdict "ORC-vi" "CI-superset failure blocks even when the suite is green" \
  "block" "$F_CI_GREEN_SUITE" --touched "$TOUCHED_SET" \
  --shellcheck-rc "$CI_SHELLCHECK_RC" --sync-rc "$CI_SYNC_RC" --sfglift-rc "$CI_SFGLIFT_RC"

# (vii) Tests INV-008/AP-031 [behavioral]: the VERBATIM real fixture (all-green,
# exit 0) with a non-empty diff and NO CI-superset failure → no block. The oracle
# must NOT mistake the `FAIL: 0` summary lines or the `echo FAIL:` exempt line for
# a real failure. Verdict must be a clean pass-through (not "block"/"abort").
# DECISION: assert the verdict is literally "pass" or "clean" rather than merely
# "not block" — a stricter contract that catches an oracle that silently swallows
# everything. GREEN picks the token; the spec implies a green run proceeds to PR.
if [ -x "$ORACLE" ] && [ -s "$F_REAL" ]; then
  got="$(bash "$ORACLE" "$F_REAL" --touched "$TOUCHED_SET" --diff "$TOUCHED_SET" 2>/dev/null || true)"
  if grep -qiwE "pass|clean|proceed|ok" <<<"$got"; then
    pass "ORC-vii" "verbatim all-green real fixture yields a clean verdict (FAIL: 0 / echo FAIL: not mistaken for failure)"
  else
    fail "ORC-vii" "real all-green fixture not recognized as clean (got: $(printf '%s' "$got" | tr '\n' ' ' | head -c 80))"
  fi
else
  fail "ORC-vii" "verbatim real-fixture behavioral test: pinned oracle absent ($ORACLE) — RED"
fi

# (viii) Tests INV-008/AP-035/QA-006 [behavioral]: a --diff <range> that resolves
# to an EMPTY diff aborts the run — the committed-substrate precondition is now
# enforced in the CODED oracle, not only in SKILL prose. The caller supplies a
# --diff argument naming an empty (zero-line) file; the oracle must ABORT WITHOUT
# the caller also passing --diff-empty. This is the class-fix guard for QA-006:
# without the coded check, --diff was dead (DIFF_GIVEN set but never read) and a
# verbatim green fixture would yield a clean verdict instead of abort.
assert_oracle_verdict "ORC-viii" "empty --diff <range> aborts (committed-substrate enforced in code, not prose)" \
  "abort" "$F_REAL" --touched "$TOUCHED_SET" --diff "$F_DIFF_EMPTY_FILE"

# (ix) Tests INV-008/AP-035/QA-006 [behavioral]: same precondition against a REAL
# git range known to be empty. Build a throwaway repo with a single commit, then
# pass a self-range (HEAD...HEAD) which has no changes → abort. Skips cleanly when
# git is unavailable so the suite stays portable.
if command -v git >/dev/null 2>&1; then
  GITREPO="$(mktemp -d)"
  (
    cd "$GITREPO" || exit 1
    git init -q
    git config user.email t@t.t
    git config user.name t
    : > seed.txt
    git add seed.txt
    git commit -q -m seed
  ) >/dev/null 2>&1
  EMPTY_RANGE_REPO_OUT="$FIXDIR/diff-empty-range-out.txt"
  cp "$F_REAL" "$EMPTY_RANGE_REPO_OUT"
  got_er="$(cd "$GITREPO" && bash "$ORACLE" "$EMPTY_RANGE_REPO_OUT" --touched "$TOUCHED_SET" --diff "HEAD...HEAD" 2>/dev/null || true)"
  if grep -qiw "abort" <<<"$got_er"; then
    pass "ORC-ix" "empty real git range (HEAD...HEAD) aborts the run"
  else
    fail "ORC-ix" "empty real git range did not abort (got: $(printf '%s' "$got_er" | tr '\n' ' ' | head -c 80))"
  fi
  rm -rf "$GITREPO"
else
  pass "ORC-ix" "git unavailable — empty-real-range abort test skipped (portable degrade)"
fi

# ============================================================================
# Summary
# ============================================================================
summary "test-cchores-regression-oracle"
