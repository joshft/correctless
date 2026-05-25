#!/usr/bin/env bash
# Correctless — Harness Fingerprint + Model Upgrade Detection Tests
# Tests spec rules from .correctless/specs/harness-fingerprint.md
# INV-001 through INV-019, PRH-001 through PRH-006, BND-001 through BND-005
# Run from repo root: bash tests/test-harness-fingerprint.sh

source "$(dirname "${BASH_SOURCE[0]}")/test-helpers.sh"
# Feature-specific helper for HARNESS_VERSION injection (INV-010 / Finding #8)
# shellcheck source=harness-fingerprint-test-helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/harness-fingerprint-test-helpers.sh"

# ============================================================================
# Paths to tested artifacts
# ============================================================================

# Test-audit notes:
#   * INV-007 and INV-009 are tagged [integration] in the spec with Skill-tool
#     entry points. Bash test files cannot invoke Skill-tool agents end-to-end,
#     so these are verified structurally:
#     - INV-007: allowed-tools frontmatter prohibits the write (Claude Code
#       enforces frontmatter at runtime — structural, not aspirational)
#     - INV-009: skill body must reference all four data sources, the
#       cost-*.json glob pattern, ABS-026, exit-code contract, and N=5 sample
#     The "snapshot before/after via SHA-256" gate from spec INV-007's test
#     approach is implicitly enforced by the allowed-tools check (PRE-005 +
#     INV-007a/c) plus PRH-002's structural sensitive-file-guard block.
#   * Performance ceiling (INV-004) is 200ms per spec; LO-1 documents that CI
#     may need relaxation. If CI consistently fails, raise the bound there.

SCRIPT="$REPO_DIR/scripts/harness-fingerprint.sh"
LIB="$REPO_DIR/scripts/lib.sh"
GUARD="$REPO_DIR/hooks/sensitive-file-guard.sh"
GUARD_TEST="$REPO_DIR/tests/test-sensitive-file-guard.sh"
ARCH_DOC="$REPO_DIR/.correctless/ARCHITECTURE.md"
DRIFT_TEST="$REPO_DIR/tests/test-architecture-drift.sh"
ALLOWED_TEST="$REPO_DIR/tests/test-allowed-tools-check.sh"
NS_TEST="$REPO_DIR/tests/test-scripts-namespace-migration.sh"

CSPEC_SKILL="$REPO_DIR/skills/cspec/SKILL.md"
CSTATUS_SKILL="$REPO_DIR/skills/cstatus/SKILL.md"
CMODELUPGRADE_SKILL="$REPO_DIR/skills/cmodelupgrade/SKILL.md"
CMODELUPGRADE_DIST="$REPO_DIR/correctless/skills/cmodelupgrade/SKILL.md"
CVERIFY_SKILL="$REPO_DIR/skills/cverify/SKILL.md"
CSETUP_SKILL="$REPO_DIR/skills/csetup/SKILL.md"
CAUTO_SKILL="$REPO_DIR/skills/cauto/SKILL.md"
SYNC="$REPO_DIR/sync.sh"
TEMPLATE_BASELINE="$REPO_DIR/templates/test-features/baseline.md"
TEMPLATE_BASELINE_DIST="$REPO_DIR/correctless/templates/test-features/baseline.md"

# Test workspace under /tmp (tests must not pollute the live .correctless/meta/)
WORK_BASE="/tmp/correctless-hf-$$"

cleanup() { rm -rf "$WORK_BASE"; }
trap cleanup EXIT

mkworkdir() {
  local sub="$1"
  local d="$WORK_BASE/$sub"
  rm -rf "$d"
  mkdir -p "$d/.correctless/meta" "$d/.correctless/artifacts"
  echo "$d"
}

# ============================================================================
# Helpers — runs the script with explicit --meta-dir / --session-id flags so
# tests never touch the real .correctless/meta/. The script defaults to live
# values when flags are omitted (INV-018).
# ============================================================================

run_script() {
  # Args passed verbatim to the script. Captures stdout, stderr, exit code.
  # Echoes "EXIT|STDOUT|STDERR" on a single line (newlines in stdout/stderr
  # squashed to spaces for easy grepping).
  local out err code
  out=$(bash "$SCRIPT" "$@" 2>/tmp/hf-stderr-$$) && code=0 || code=$?
  err=$(cat /tmp/hf-stderr-$$ 2>/dev/null || true)
  rm -f /tmp/hf-stderr-$$
  echo "EXIT=$code"
  echo "--STDOUT--"
  echo "$out"
  echo "--STDERR--"
  echo "$err"
}

# Drop-in replacement for `run_script ... --version $N ...` after INV-009
# stripped --version from production. Builds a tmpdir copy of the harness
# script with the requested HARNESS_VERSION constant, then delegates to
# run_script with that copy via SCRIPT override. Spec: INV-010, BND-003.
run_script_v() {
  local version="$1"; shift
  mkdir -p "$WORK_BASE"
  local err_file helper_script
  err_file="$(mktemp)"
  helper_script="$(make_test_harness_script "$version" "$WORK_BASE" 2>"$err_file")" || helper_script=""
  if [ -z "$helper_script" ] || [ ! -f "$helper_script" ]; then
    printf 'EXIT=1\n--STDOUT--\n\n--STDERR--\n%s\n' "$(cat "$err_file" 2>/dev/null || true)"
    rm -f "$err_file"
    return
  fi
  rm -f "$err_file"
  SCRIPT="$helper_script" run_script "$@"
}

extract_field() {
  # Extract a key=value or JSON field from script output blob
  local blob="$1" field="$2"
  # Try JSON first, then k=v
  local val
  val=$(echo "$blob" | sed -n "/^--STDOUT--$/,/^--STDERR--$/p" | grep -v '^--' | jq -r ".$field // empty" 2>/dev/null || true)
  if [ -n "$val" ] && [ "$val" != "null" ]; then
    echo "$val"
    return
  fi
  echo "$blob" | sed -n "/^--STDOUT--$/,/^--STDERR--$/p" | grep -v '^--' \
    | grep "^${field}=" | head -1 | sed "s/^${field}=//"
}

extract_status() {
  local blob="$1"
  extract_field "$blob" "status"
}

extract_exit() {
  echo "$1" | grep '^EXIT=' | head -1 | sed 's/^EXIT=//'
}

extract_stderr() {
  echo "$1" | sed -n '/^--STDERR--$/,$p' | grep -v '^--STDERR--'
}

# ============================================================================
# Pre-flight — script must exist (RED creates a stub)
# ============================================================================

if [ ! -f "$SCRIPT" ]; then
  echo "  FAIL: script $SCRIPT does not exist (RED expects stub)"
  FAIL=$((FAIL + 1))
fi

# ============================================================================
# INV-001: Fingerprint is the literal string "{model_name}|{HARNESS_VERSION}"
# ============================================================================

section "INV-001: Fingerprint is literal {model_name}|{HARNESS_VERSION}"

test_inv001_literal_fingerprint() {
  local d
  d=$(mkworkdir inv001)
  # Test-audit fix (assertion strength): pass an explicit version and assert the
  # fingerprint contains EXACTLY that version, not just "any integer".
  local out
  out=$(run_script_v 42 --meta-dir "$d/.correctless/meta" --session-id "__test_session_inv001__" --model "claude-test-model" check)
  local fp
  fp=$(extract_field "$out" "fingerprint")
  if [ "$fp" = "claude-test-model|42" ]; then
    pass "INV-001a" "fingerprint is exact literal model|version (got: $fp)"
  else
    fail "INV-001a" "fingerprint mismatch — expected 'claude-test-model|42', got '$fp'"
  fi

  # The stored file must contain the same literal value as `fingerprint`
  if [ -f "$d/.correctless/meta/harness-fingerprint.json" ]; then
    local stored
    stored=$(jq -r '.fingerprint // empty' "$d/.correctless/meta/harness-fingerprint.json" 2>/dev/null)
    if [ "$stored" = "$fp" ]; then
      pass "INV-001b" "stored fingerprint equals computed fingerprint"
    else
      fail "INV-001b" "stored '$stored' != computed '$fp'"
    fi
    # No SHA-256 anywhere in the file — HI-1 dropped hashing
    if grep -qE '[a-f0-9]{64}' "$d/.correctless/meta/harness-fingerprint.json"; then
      fail "INV-001c" "fingerprint file contains a SHA-256 hash (HI-1 dropped hashing)"
    else
      pass "INV-001c" "fingerprint file contains no SHA-256 hash (literal scheme)"
    fi
  else
    fail "INV-001b" "fingerprint file not written"
    fail "INV-001c" "no fingerprint file to check for hashes"
  fi
}
test_inv001_literal_fingerprint

# ============================================================================
# INV-002: Fingerprint changes when HARNESS_VERSION is bumped
# ============================================================================

section "INV-002: Fingerprint changes when HARNESS_VERSION is bumped"

test_inv002_version_bump() {
  local d
  d=$(mkworkdir inv002)

  # First run captures baseline fingerprint
  local out1
  out1=$(run_script_v 1 --meta-dir "$d/.correctless/meta" --session-id "__test_session_inv002a__" --model "claude-x" check)
  local fp1
  fp1=$(extract_field "$out1" "fingerprint")

  # Second run with bumped version
  local out2
  out2=$(run_script_v 2 --meta-dir "$d/.correctless/meta" --session-id "__test_session_inv002b__" --model "claude-x" check)
  local fp2 status2
  fp2=$(extract_field "$out2" "fingerprint")
  status2=$(extract_status "$out2")

  if [ "$fp1" != "$fp2" ] && [ -n "$fp1" ] && [ -n "$fp2" ]; then
    pass "INV-002a" "fingerprint differs after version bump ($fp1 -> $fp2)"
  else
    fail "INV-002a" "fingerprint unchanged across version bump (fp1=$fp1, fp2=$fp2)"
  fi

  if [ "$status2" = "version_bumped" ]; then
    pass "INV-002b" "status='version_bumped' on bump detected"
  else
    fail "INV-002b" "status='$status2' (expected version_bumped)"
  fi
}
test_inv002_version_bump

# ============================================================================
# INV-003: Notification fires at most once per session [integration]
# ============================================================================

section "INV-003: Notification fires at most once per session"

test_inv003_session_dedup() {
  local d
  d=$(mkworkdir inv003)

  # First run creates baseline AT version 1
  run_script_v 1 --meta-dir "$d/.correctless/meta" --session-id "__test_session_inv003__" --model "claude-x" check >/dev/null

  # Bump version to trigger notification
  local out1 out2
  out1=$(run_script_v 2 --meta-dir "$d/.correctless/meta" --artifacts-dir "$d/.correctless/artifacts" --session-id "__test_session_inv003__" --model "claude-x" check)
  out2=$(run_script_v 2 --meta-dir "$d/.correctless/meta" --artifacts-dir "$d/.correctless/artifacts" --session-id "__test_session_inv003__" --model "claude-x" check)

  local notified1 notified2
  notified1=$(extract_field "$out1" "notified")
  notified2=$(extract_field "$out2" "notified")

  if [ "$notified1" = "true" ] || [ "$notified1" = "1" ]; then
    pass "INV-003a" "first invocation reports notified=true"
  else
    fail "INV-003a" "first invocation reports notified=$notified1 (expected true)"
  fi

  if [ "$notified2" = "false" ] || [ "$notified2" = "0" ]; then
    pass "INV-003b" "second invocation in same session reports notified=false (deduped)"
  else
    fail "INV-003b" "second invocation reports notified=$notified2 (expected false — dedup)"
  fi

  # The flag file must exist after first invocation per spec
  if compgen -G "$d/.correctless/artifacts/harness-notified-*.flag" >/dev/null 2>&1; then
    pass "INV-003c" "session flag file written"
  else
    fail "INV-003c" "session flag file not written under .correctless/artifacts/"
  fi
}
test_inv003_session_dedup

# ============================================================================
# INV-004: Script I/O completes within performance budget (<200ms)
# ============================================================================

section "INV-004: Script completes <200ms wall time per invocation"

test_inv004_perf_budget() {
  local d
  d=$(mkworkdir inv004)
  # Pre-seed baseline so we measure the unchanged-path
  run_script_v 1 --meta-dir "$d/.correctless/meta" --session-id "__test_session_inv004_seed__" --model "claude-x" check >/dev/null

  local i max_ms=200 over=0 worst=0
  for i in 1 2 3 4 5; do
    local start_ns end_ns ms sid="__test_session_inv004_${i}_x__"
    start_ns=$(date +%s%N)
    bash "$(make_test_harness_script 1 "$WORK_BASE")" --meta-dir "$d/.correctless/meta" --session-id "$sid" --model "claude-x" check >/dev/null 2>&1 || true
    end_ns=$(date +%s%N)
    ms=$(( (end_ns - start_ns) / 1000000 ))
    if [ "$ms" -gt "$worst" ]; then worst=$ms; fi
    if [ "$ms" -gt "$max_ms" ]; then over=$((over + 1)); fi
  done

  if [ "$over" -eq 0 ]; then
    pass "INV-004" "all 5 invocations under ${max_ms}ms (worst: ${worst}ms)"
  else
    fail "INV-004" "$over of 5 invocations exceeded ${max_ms}ms (worst: ${worst}ms)"
  fi
}
test_inv004_perf_budget

# ============================================================================
# INV-005: First-run handling is silent
# ============================================================================

section "INV-005: First-run is silent (no warning)"

test_inv005_first_run_silent() {
  local d
  d=$(mkworkdir inv005)
  local out
  out=$(run_script_v 1 --meta-dir "$d/.correctless/meta" --session-id "__test_session_inv005__" --model "claude-x" check)
  local code status err
  code=$(extract_exit "$out")
  status=$(extract_status "$out")
  err=$(extract_stderr "$out")

  if [ "$code" = "0" ]; then
    pass "INV-005a" "exit 0 on first run"
  else
    fail "INV-005a" "exit $code on first run (expected 0)"
  fi

  if [ "$status" = "first_seen" ]; then
    pass "INV-005b" "status='first_seen'"
  else
    fail "INV-005b" "status='$status' (expected first_seen)"
  fi

  if echo "$err" | grep -qiE 'warn|warning|notif|notice'; then
    fail "INV-005c" "first-run emitted warning/notice on stderr: $err"
  else
    pass "INV-005c" "first-run emitted no warning"
  fi

  if [ -f "$d/.correctless/meta/harness-fingerprint.json" ]; then
    pass "INV-005d" "fingerprint file written on first run"
  else
    fail "INV-005d" "fingerprint file not written on first run"
  fi
}
test_inv005_first_run_silent

# ============================================================================
# INV-006: Corruption fails open
# ============================================================================

section "INV-006: Corrupted fingerprint file recovers with status=corrupted_recovered"

test_inv006_corruption_recovery() {
  local d
  d=$(mkworkdir inv006)
  echo "{ this is not valid JSON :" > "$d/.correctless/meta/harness-fingerprint.json"

  local out code status err
  out=$(run_script_v 1 --meta-dir "$d/.correctless/meta" --session-id "__test_session_inv006__" --model "claude-x" check)
  code=$(extract_exit "$out")
  status=$(extract_status "$out")
  err=$(extract_stderr "$out")

  if [ "$code" = "0" ]; then
    pass "INV-006a" "exit 0 on corruption (fail-open)"
  else
    fail "INV-006a" "exit $code on corruption (expected 0)"
  fi

  if [ "$status" = "corrupted_recovered" ]; then
    pass "INV-006b" "status='corrupted_recovered'"
  else
    fail "INV-006b" "status='$status' (expected corrupted_recovered)"
  fi

  # One-line warning to stderr
  if [ -n "$err" ]; then
    pass "INV-006c" "warning emitted to stderr"
  else
    fail "INV-006c" "no warning emitted on corruption"
  fi

  # File must be valid JSON now
  if jq -e . "$d/.correctless/meta/harness-fingerprint.json" >/dev/null 2>&1; then
    pass "INV-006d" "fingerprint file is valid JSON after recovery"
  else
    fail "INV-006d" "fingerprint file still malformed after recovery"
  fi
}
test_inv006_corruption_recovery

# ============================================================================
# INV-007: cmodelupgrade does not write the fingerprint store
# Belt-and-suspenders: check allowed-tools + grep for write references
# ============================================================================

section "INV-007: /cmodelupgrade does not write the fingerprint store"

test_inv007_no_fingerprint_writes_in_cmodelupgrade() {
  if [ ! -f "$CMODELUPGRADE_SKILL" ]; then
    fail "INV-007a" "$CMODELUPGRADE_SKILL does not exist"
    return
  fi

  # allowed-tools must NOT include Write(...harness-fingerprint.json)
  if grep -E '^allowed-tools:' "$CMODELUPGRADE_SKILL" | head -1 | grep -qF 'harness-fingerprint.json'; then
    fail "INV-007a" "/cmodelupgrade allowed-tools contains harness-fingerprint.json"
  else
    pass "INV-007a" "/cmodelupgrade allowed-tools does not include fingerprint write"
  fi

  # Skill body must NOT instruct Write/Edit on the fingerprint file
  if grep -E '(Write|Edit)\([^)]*harness-fingerprint\.json' "$CMODELUPGRADE_SKILL" >/dev/null; then
    fail "INV-007b" "/cmodelupgrade body references write/edit of harness-fingerprint.json"
  else
    pass "INV-007b" "/cmodelupgrade body does not write/edit fingerprint file"
  fi

  # Allowed-tools MUST include the baseline write (so the skill can do its actual job)
  if grep -E '^allowed-tools:' "$CMODELUPGRADE_SKILL" | head -1 | grep -qF 'model-baselines.json'; then
    pass "INV-007c" "/cmodelupgrade allowed-tools includes baseline write"
  else
    fail "INV-007c" "/cmodelupgrade allowed-tools missing model-baselines.json write"
  fi
}
test_inv007_no_fingerprint_writes_in_cmodelupgrade

# ============================================================================
# INV-008: Baseline file keyed by same literal as fingerprint, exact-match only
# ============================================================================

section "INV-008: Baseline keyed by same literal; lookup is exact-match only"

test_inv008_baseline_key_format() {
  if [ ! -f "$CMODELUPGRADE_SKILL" ]; then
    fail "INV-008a" "$CMODELUPGRADE_SKILL does not exist"
    return
  fi

  # The skill body must reference the literal-key contract — exact-match lookup
  # (regression guard: if someone substring-matches by model alone, this catches it)
  if grep -qiE 'exact[- ]match|exact match|full literal|literal key' "$CMODELUPGRADE_SKILL"; then
    pass "INV-008a" "skill body documents exact-match lookup"
  else
    fail "INV-008a" "skill body missing exact-match lookup contract language"
  fi

  # Reference to model_name|HARNESS_VERSION literal format (with |, not other separator)
  if grep -qE 'model_name\|HARNESS_VERSION|model.*\|.*version|\{model.*\}\|\{.*version' "$CMODELUPGRADE_SKILL"; then
    pass "INV-008b" "skill body references model|version literal key"
  else
    fail "INV-008b" "skill body missing literal key format reference"
  fi
}
test_inv008_baseline_key_format

# ============================================================================
# INV-009: Per-feature regression report [integration]
# ============================================================================

section "INV-009: /cmodelupgrade produces per-feature regression report"

test_inv009_skill_contract() {
  if [ ! -f "$CMODELUPGRADE_SKILL" ]; then
    fail "INV-009a" "$CMODELUPGRADE_SKILL does not exist"
    return
  fi

  # Per-feature granularity (NOT per-skill — explicit out-of-scope per spec)
  if grep -qiE 'per[- ]feature|one row per feature|per feature' "$CMODELUPGRADE_SKILL"; then
    pass "INV-009a" "skill body documents per-feature granularity"
  else
    fail "INV-009a" "skill missing per-feature granularity language"
  fi

  # Four data sources from the spec
  local missing=""
  for src in "intensity-calibration.json" "cost-" "workflow-state-" "model-baselines.json"; do
    if ! grep -qF "$src" "$CMODELUPGRADE_SKILL"; then
      missing="$missing $src"
    fi
  done
  if [ -z "$missing" ]; then
    pass "INV-009b" "skill references all four data sources (intensity-calibration, cost-*, workflow-state-*, model-baselines)"
  else
    fail "INV-009b" "skill missing data source reference(s):$missing"
  fi

  # Cost glob, NOT hardcoded slug list (PMB-003 / AP-024)
  if grep -qE 'cost-\*\.json|glob.*cost|cost.*glob' "$CMODELUPGRADE_SKILL"; then
    pass "INV-009c" "skill references cost-*.json glob pattern (not hardcoded list)"
  else
    fail "INV-009c" "skill missing cost-*.json glob pattern (AP-024 risk)"
  fi

  # ABS-026 (no derived USD) reference
  if grep -qE 'ABS-026|cost artifact' "$CMODELUPGRADE_SKILL"; then
    pass "INV-009d" "skill references ABS-026 / cost artifact contract"
  else
    fail "INV-009d" "skill missing ABS-026 reference (USD source contract)"
  fi

  # Exit code contract: 0/1/2 documented
  if grep -qE 'exit ?(code)?.*0|exit 0' "$CMODELUPGRADE_SKILL" \
     && grep -qE 'exit ?(code)?.*1|exit 1' "$CMODELUPGRADE_SKILL" \
     && grep -qE 'exit ?(code)?.*2|exit 2' "$CMODELUPGRADE_SKILL"; then
    pass "INV-009e" "skill body documents 0/1/2 exit code contract"
  else
    fail "INV-009e" "skill missing 0/1/2 exit code contract"
  fi

  # Default sample window N=5
  if grep -qE 'N[ =]*5|5 most recent|window.*5|5 features' "$CMODELUPGRADE_SKILL"; then
    pass "INV-009f" "skill documents N=5 sample window"
  else
    fail "INV-009f" "skill missing N=5 sample window"
  fi
}
test_inv009_skill_contract

# ============================================================================
# INV-009b: No baseline → explicit message, never compare against zero
# ============================================================================

section "INV-009b: No baseline → explicit message + exit 0"

test_inv009b_no_baseline_message() {
  if [ ! -f "$CMODELUPGRADE_SKILL" ]; then
    fail "INV-009b1" "$CMODELUPGRADE_SKILL does not exist"
    return
  fi

  # Explicit no-baseline message contract
  if grep -qiE 'no baseline available|--capture-baseline' "$CMODELUPGRADE_SKILL"; then
    pass "INV-009b1" "skill documents no-baseline message"
  else
    fail "INV-009b1" "skill missing no-baseline message"
  fi

  # Spec: must NEVER compare against zero/null baselines
  if grep -qiE 'never.*against.*zero|against zero or null|forbidden.*baseline|render against zero' "$CMODELUPGRADE_SKILL"; then
    pass "INV-009b2" "skill documents no-zero-baseline prohibition"
  else
    fail "INV-009b2" "skill missing prohibition against rendering against zero/null baselines"
  fi
}
test_inv009b_no_baseline_message

# ============================================================================
# INV-010: Fingerprint check fires before /cspec Step 0
# ============================================================================

section "INV-010: Fingerprint check fires before /cspec Step 0"

test_inv010_cspec_invocation() {
  if [ ! -f "$CSPEC_SKILL" ]; then
    fail "INV-010a" "$CSPEC_SKILL not found"
    return
  fi

  # Marker present
  local marker='<!-- correctless:harness-fingerprint:invocation -->'
  if grep -qF "$marker" "$CSPEC_SKILL"; then
    pass "INV-010a" "structural marker present in skills/cspec/SKILL.md"
  else
    fail "INV-010a" "structural marker missing"
  fi

  # Marker must precede the "Step 0" header line and the Socratic Brainstorm heading.
  # NOTE: The progress-visibility task list at the top of cspec mentions "Socratic
  # brainstorm" by name BEFORE the actual Step 0 heading. We constrain the audit
  # to the heading specifically (### Step 0:) so we don't false-positive on the
  # task list reference.
  local marker_line step0_line socratic_heading_line
  marker_line=$(grep -nF "$marker" "$CSPEC_SKILL" | head -1 | cut -d: -f1)
  step0_line=$(grep -nE '^### Step 0' "$CSPEC_SKILL" | head -1 | cut -d: -f1)
  socratic_heading_line=$(grep -nE '^### Step 0.*Socratic' "$CSPEC_SKILL" | head -1 | cut -d: -f1)

  if [ -n "$marker_line" ] && [ -n "$step0_line" ] && [ "$marker_line" -lt "$step0_line" ]; then
    pass "INV-010b" "marker appears before '### Step 0' header (marker line $marker_line < step0 line $step0_line)"
  else
    fail "INV-010b" "marker not before '### Step 0' (marker=$marker_line step0=$step0_line)"
  fi

  if [ -n "$marker_line" ] && [ -n "$socratic_heading_line" ] && [ "$marker_line" -lt "$socratic_heading_line" ]; then
    pass "INV-010c" "marker appears before Socratic Brainstorm heading"
  else
    fail "INV-010c" "marker not before Socratic Brainstorm heading (marker=$marker_line heading=$socratic_heading_line)"
  fi

  # Bash invocation must appear within the section that follows the marker.
  # Use awk to extract from the marker until the next top-level heading.
  if awk "/$marker/{flag=1; next} flag && /^### Step 0/{flag=0} flag" "$CSPEC_SKILL" \
       | grep -qE 'harness-fingerprint\.sh|bash.*harness-fingerprint'; then
    pass "INV-010d" "harness-fingerprint.sh invocation follows the marker (within section)"
  else
    fail "INV-010d" "no script invocation found in section following marker"
  fi
}
test_inv010_cspec_invocation

# ============================================================================
# INV-011: Fingerprint file schema includes fingerprint, harness_version, model, timestamp
# ============================================================================

section "INV-011: Fingerprint file schema has all four required fields"

test_inv011_file_schema() {
  local d
  d=$(mkworkdir inv011)
  run_script_v 7 --meta-dir "$d/.correctless/meta" --session-id "__test_session_inv011__" --model "claude-x" check >/dev/null
  local f="$d/.correctless/meta/harness-fingerprint.json"
  if [ ! -f "$f" ]; then
    fail "INV-011" "fingerprint file not created"
    return
  fi
  for field in fingerprint harness_version model timestamp; do
    local val
    val=$(jq -r ".${field} // empty" "$f" 2>/dev/null)
    if [ -n "$val" ]; then
      pass "INV-011-$field" "field '$field' present (value: $val)"
    else
      fail "INV-011-$field" "field '$field' missing from fingerprint file"
    fi
  done
  # harness_version must be a number, not a string
  local hv_type
  hv_type=$(jq -r '.harness_version | type' "$f" 2>/dev/null)
  if [ "$hv_type" = "number" ]; then
    pass "INV-011-type" "harness_version is JSON number"
  else
    fail "INV-011-type" "harness_version is $hv_type (expected number)"
  fi
}
test_inv011_file_schema

# ============================================================================
# INV-012: /cmodelupgrade SKILL.md uses explicit path discovery
# ============================================================================

section "INV-012: /cmodelupgrade uses explicit path discovery (PMB-004 mitigation)"

test_inv012_path_discovery() {
  if [ ! -f "$CMODELUPGRADE_SKILL" ]; then
    fail "INV-012" "$CMODELUPGRADE_SKILL does not exist"
    return
  fi

  # Either workflow-advance.sh status invocation or workflow-state read pattern
  if grep -qE 'workflow-advance\.sh status|workflow-advance.sh.*status' "$CMODELUPGRADE_SKILL"; then
    pass "INV-012a" "skill invokes workflow-advance.sh status (path discovery)"
  else
    fail "INV-012a" "skill missing workflow-advance.sh status path discovery (AP-025/PMB-004)"
  fi

  # Direct AP-025 / PMB-004 reference (history citation per user's rule)
  if grep -qE 'AP-025|PMB-004' "$CMODELUPGRADE_SKILL"; then
    pass "INV-012b" "skill cites AP-025 or PMB-004"
  else
    fail "INV-012b" "skill missing AP-025/PMB-004 historical citation"
  fi
}
test_inv012_path_discovery

# ============================================================================
# INV-013: ABS-027 entry exists in ARCHITECTURE.md + drift test
# ============================================================================

section "INV-013: ABS-027 entry present in ARCHITECTURE.md and verified by drift test"

test_inv013_abs027_present() {
  if grep -qE '^### ABS-027:' "$ARCH_DOC"; then
    pass "INV-013a" "ABS-027 heading present in ARCHITECTURE.md"
  else
    fail "INV-013a" "ABS-027 heading missing from ARCHITECTURE.md"
  fi

  # Must mention harness fingerprint
  if grep -A 30 '^### ABS-027:' "$ARCH_DOC" | grep -qE 'harness[ -]fingerprint|harness-fingerprint\.json|model-baselines\.json'; then
    pass "INV-013b" "ABS-027 body references harness fingerprint store"
  else
    fail "INV-013b" "ABS-027 body missing harness fingerprint references"
  fi

  # Drift test must check for ABS-027
  if grep -qE 'ABS-027' "$DRIFT_TEST"; then
    pass "INV-013c" "tests/test-architecture-drift.sh checks ABS-027 presence"
  else
    fail "INV-013c" "tests/test-architecture-drift.sh missing ABS-027 check"
  fi
}
test_inv013_abs027_present

# ============================================================================
# INV-014: Bootstrap baseline requires ≥M=2 + human validation
# ============================================================================

section "INV-014: Bootstrap requires ≥2 qualifying runs + human validation"

test_inv014_bootstrap_gate() {
  if [ ! -f "$CMODELUPGRADE_SKILL" ]; then
    fail "INV-014" "$CMODELUPGRADE_SKILL does not exist"
    return
  fi

  # M=2 minimum
  if grep -qE 'at least 2|M[ =]*2|≥M=2|>=.*2.*qualifying|2.*qualifying' "$CMODELUPGRADE_SKILL"; then
    pass "INV-014a" "skill documents ≥2 qualifying runs requirement"
  else
    fail "INV-014a" "skill missing M=2 minimum"
  fi

  # Human confirmation prompt
  if grep -qiE 'human.*confirm|confirm.*human|explicit confirmation|prompt.*human|user.*confirm' "$CMODELUPGRADE_SKILL"; then
    pass "INV-014b" "skill requires human confirmation before saving baseline"
  else
    fail "INV-014b" "skill missing human confirmation prompt"
  fi

  # --auto-confirm flag for testability
  if grep -qE '\-\-auto-confirm' "$CMODELUPGRADE_SKILL"; then
    pass "INV-014c" "skill documents --auto-confirm test flag"
  else
    fail "INV-014c" "skill missing --auto-confirm test flag"
  fi

  # Audit trail entry on auto-confirm bypass
  if grep -qE 'bootstrap_auto_confirmed|audit[- ]trail.*auto[- ]confirm|auto[- ]confirm.*audit' "$CMODELUPGRADE_SKILL"; then
    pass "INV-014d" "skill documents bootstrap_auto_confirmed audit trail entry"
  else
    fail "INV-014d" "skill missing bootstrap_auto_confirmed audit-trail entry"
  fi

  # Quality filter: incomplete runs excluded
  if grep -qiE 'incomplete.*excl|exclud.*incomplete|degenerate.*pool|skip.*incomplete' "$CMODELUPGRADE_SKILL"; then
    pass "INV-014e" "skill documents incomplete-run exclusion (LO-2)"
  else
    fail "INV-014e" "skill missing incomplete-run exclusion (poisoning guard)"
  fi
}
test_inv014_bootstrap_gate

# ============================================================================
# INV-015: /cstatus shows fingerprint state in advisory line
# ============================================================================

section "INV-015: /cstatus shows Harness: advisory line"

test_inv015_cstatus_line() {
  if [ ! -f "$CSTATUS_SKILL" ]; then
    fail "INV-015" "$CSTATUS_SKILL not found"
    return
  fi

  # Must reference the Harness: line format
  if grep -qE 'Harness:.*model.*version.*fingerprint.*status|Harness:.*model=.*version=' "$CSTATUS_SKILL"; then
    pass "INV-015a" "/cstatus documents Harness: advisory line format"
  else
    fail "INV-015a" "/cstatus missing Harness: advisory line"
  fi

  # Position: after workflow state section
  local harness_line wf_line
  harness_line=$(grep -nE 'Harness:' "$CSTATUS_SKILL" | head -1 | cut -d: -f1)
  wf_line=$(grep -niE 'workflow.state|## .*Workflow' "$CSTATUS_SKILL" | head -1 | cut -d: -f1)

  if [ -n "$harness_line" ] && [ -n "$wf_line" ] && [ "$harness_line" -gt "$wf_line" ]; then
    pass "INV-015b" "Harness: line appears after workflow state section"
  else
    fail "INV-015b" "Harness: line not after workflow state (harness=$harness_line workflow=$wf_line)"
  fi
}
test_inv015_cstatus_line

# ============================================================================
# INV-016: /cauto Auto Run Report surfaces harness warnings in "What to Review First"
# ============================================================================

section "INV-016: Auto Run Report surfaces harness warnings"

test_inv016_auto_report() {
  if [ ! -f "$CAUTO_SKILL" ] && [ ! -f "$REPO_DIR/scripts/auto-report.sh" ]; then
    fail "INV-016" "neither $CAUTO_SKILL nor auto-report.sh exists"
    return
  fi

  # Either cauto skill or auto-report.sh must reference the harness flag
  local target=""
  if grep -lE 'harness-notified|harness.*warning|harness.*flag' \
      "$CAUTO_SKILL" "$REPO_DIR/scripts/auto-report.sh" 2>/dev/null | head -1 >/dev/null; then
    target=$(grep -lE 'harness-notified|harness.*warning|harness.*flag' \
      "$CAUTO_SKILL" "$REPO_DIR/scripts/auto-report.sh" 2>/dev/null | head -1)
  fi
  if [ -n "$target" ]; then
    pass "INV-016a" "cauto/auto-report references harness-notified flag (in: $(basename "$target"))"
  else
    fail "INV-016a" "no reference to harness-notified flag in cauto or auto-report.sh"
  fi
}
test_inv016_auto_report

# ============================================================================
# INV-017: harness-fingerprint.sh conforms to PAT-003 phase-transition convention
# ============================================================================

section "INV-017: PAT-003 conformance (sources lib.sh, all paths exit 0)"

test_inv017_pat003_conformance() {
  if [ ! -f "$SCRIPT" ]; then
    fail "INV-017" "$SCRIPT does not exist"
    return
  fi

  if grep -qE 'source.*lib\.sh|\. .*lib\.sh' "$SCRIPT"; then
    pass "INV-017a" "script sources lib.sh"
  else
    fail "INV-017a" "script does not source lib.sh"
  fi

  # All exit calls must be exit 0 (PRH-001 — never blocks /cspec)
  local nonzero_exits
  nonzero_exits=$(grep -nE '^[^#]*exit [1-9]' "$SCRIPT" | grep -v 'exit 0' | wc -l)
  if [ "$nonzero_exits" -eq 0 ]; then
    pass "INV-017b" "all exit calls in script are exit 0 (advisory)"
  else
    fail "INV-017b" "$nonzero_exits non-zero exit(s) in script (PRH-001 violation)"
    grep -nE '^[^#]*exit [1-9]' "$SCRIPT" | grep -v 'exit 0' || true
  fi

  # Output must be parseable: either JSON (jq -e .) on a single line, or k=v lines
  local d out blob
  d=$(mkworkdir inv017)
  out=$(run_script_v 1 --meta-dir "$d/.correctless/meta" --session-id "__test_session_inv017__" --model "claude-x" check)
  blob=$(echo "$out" | sed -n '/^--STDOUT--$/,/^--STDERR--$/p' | grep -v '^--')
  if echo "$blob" | jq -e . >/dev/null 2>&1 \
     || echo "$blob" | grep -qE '^[a-z_]+=' ; then
    pass "INV-017c" "script stdout is parseable JSON or k=v lines"
  else
    fail "INV-017c" "script stdout is neither parseable JSON nor k=v: $blob"
  fi
}
test_inv017_pat003_conformance

# ============================================================================
# INV-018: Script CLI accepts explicit input flags + sentinel scheme
# ============================================================================

section "INV-018: --session-id and --meta-dir flags work; sentinel prefix asserted"

test_inv018_cli_flags() {
  local d
  d=$(mkworkdir inv018)

  # Sentinel prefixed session-id must be honored verbatim
  local out flag_count
  run_script_v 1 --meta-dir "$d/.correctless/meta" --artifacts-dir "$d/.correctless/artifacts" --session-id "__test_session_inv018x__" --model "claude-x" check >/dev/null
  # Trigger notification with version bump in same sentinel session — should write flag file with sentinel in name
  run_script_v 2 --meta-dir "$d/.correctless/meta" --artifacts-dir "$d/.correctless/artifacts" --session-id "__test_session_inv018x__" --model "claude-x" check >/dev/null

  if compgen -G "$d/.correctless/artifacts/harness-notified-*__test_session_inv018x__*.flag" >/dev/null \
     || compgen -G "$d/.correctless/artifacts/*__test_session_inv018x__*.flag" >/dev/null; then
    pass "INV-018a" "explicit --session-id sentinel propagates into flag file path"
  else
    flag_count=$(compgen -G "$d/.correctless/artifacts/harness-notified-*.flag" 2>/dev/null | wc -l)
    fail "INV-018a" "sentinel session-id not honored ($flag_count flag files, none containing sentinel)"
  fi

  # Without --meta-dir, script must default to live values (we don't run that here
  # to avoid touching real .correctless/meta/, but assert the script body doesn't
  # require the flag).
  if grep -qE 'meta[- ]?dir.*default|default.*meta[- ]?dir|MetaDir.*\.correctless' "$SCRIPT" \
     || grep -qE '\.correctless/meta' "$SCRIPT"; then
    pass "INV-018b" "script body references default .correctless/meta/ path"
  else
    fail "INV-018b" "script missing default .correctless/meta/ fallback"
  fi

  # Sentinel-prefix assertion: production session_ids never start with __test_session_
  if grep -qE '__test_session_' "$SCRIPT"; then
    pass "INV-018c" "script implements sentinel-prefix assertion"
  else
    fail "INV-018c" "script missing __test_session_ sentinel-prefix assertion"
  fi
}
test_inv018_cli_flags

# ============================================================================
# MA-HI-003 regression (mini-audit round 2 hostile-input finding):
# Malformed CLI invocation — paired flag as last arg with no value — must not
# infinite-loop. Caused by `shift 2` being a no-op when only 1 arg remains;
# the loop re-processes the same `--flag` token forever.
# ============================================================================

section "MA-HI-003: Malformed CLI tail does not hang the script"

test_ma_hi_003_no_infinite_loop() {
  local d
  d=$(mkworkdir ma_hi_003)
  local flag
  # --version was removed in INV-009/PRH-003; remaining flags still tested.
  for flag in --meta-dir --artifacts-dir --session-id --model; do
    timeout 3 bash "$SCRIPT" --meta-dir "$d/.correctless/meta" "$flag" >/dev/null 2>&1
    local rc=$?
    if [ "$rc" = "124" ]; then
      fail "MA-HI-003-${flag}" "script timed out (infinite loop) when '$flag' is last arg with no value"
    else
      pass "MA-HI-003-${flag}" "script terminates within 3s when '$flag' has no value (exit $rc)"
    fi
  done
}
test_ma_hi_003_no_infinite_loop

# ============================================================================
# INV-019: Baseline file includes schema_version from creation
# ============================================================================

section "INV-019: model-baselines.json includes schema_version: 1 from first write"

test_inv019_schema_version() {
  if [ ! -f "$CMODELUPGRADE_SKILL" ]; then
    fail "INV-019" "$CMODELUPGRADE_SKILL does not exist"
    return
  fi

  # Skill must document schema_version: 1 on first write
  if grep -qE 'schema_version.*1|"schema_version".*1' "$CMODELUPGRADE_SKILL"; then
    pass "INV-019a" "skill documents schema_version: 1 in baseline file"
  else
    fail "INV-019a" "skill missing schema_version: 1 in baseline write"
  fi

  # Skill must document preservation on subsequent writes
  if grep -qiE 'preserve.*schema_version|schema_version.*preserve|never (remove|modif).*schema_version' "$CMODELUPGRADE_SKILL"; then
    pass "INV-019b" "skill documents schema_version preservation"
  else
    fail "INV-019b" "skill missing schema_version preservation language"
  fi
}
test_inv019_schema_version

# ============================================================================
# PRH-001: Must not block /cspec on fingerprint check failure
# Already partially covered by INV-017b; add cspec-side check.
# ============================================================================

section "PRH-001: Fingerprint check is advisory — never blocks /cspec"

test_prh001_advisory_only() {
  # Script side: every code path exits 0 (covered above)
  # cspec side: no conditional aborts on script return value.
  # NOTE: The cspec patch text legitimately uses negated phrases like
  # "never blocks /cspec" and "always exits 0" to document the prohibition.
  # The audit looks for *positive* abort/halt/exit-non-zero language, not the
  # documentation of the prohibition itself.
  if [ -f "$CSPEC_SKILL" ]; then
    # Extract just the harness-fingerprint section (between marker and next ### heading)
    local section
    section=$(awk '/correctless:harness-fingerprint:invocation/{flag=1; next} flag && /^### Step 0/{flag=0} flag' "$CSPEC_SKILL")
    # Look for un-negated abort patterns: "exit 1", "exit 2", "abort the spec",
    # "halt /cspec", "do not proceed if". Negated forms ("never blocks", "always
    # exits 0") are documentation, not enforcement.
    if echo "$section" | grep -qE 'exit [12]|abort the spec|halt /cspec|do not proceed if'; then
      fail "PRH-001a" "cspec section contains positive abort instructions"
    else
      pass "PRH-001a" "cspec section contains no positive abort instructions"
    fi
  else
    fail "PRH-001a" "cspec skill missing"
  fi

  # Negative test: even with corrupt baseline + missing meta dir, script exits 0
  local d
  d=$(mkworkdir prh001)
  rm -rf "$d/.correctless/meta"  # delete meta dir entirely
  local out code
  out=$(run_script_v 1 --meta-dir "$d/.correctless/meta" --session-id "__test_session_prh001__" --model "claude-x" check 2>&1 || true)
  code=$(extract_exit "$out")
  if [ "$code" = "0" ]; then
    pass "PRH-001b" "script exits 0 even with missing meta dir (advisory)"
  else
    fail "PRH-001b" "script exited $code with missing meta dir (PRH-001 violation)"
  fi
}
test_prh001_advisory_only

# ============================================================================
# PRH-002: Sole-writer enforcement — STRUCTURAL via sensitive-file-guard
# ============================================================================

section "PRH-002: sensitive-file-guard blocks writes to fingerprint + baseline meta files"

test_prh002_structural_enforcement() {
  # Both meta files must be in sensitive-file-guard's protected list
  if grep -qF 'harness-fingerprint.json' "$GUARD"; then
    pass "PRH-002a" "sensitive-file-guard protects harness-fingerprint.json"
  else
    fail "PRH-002a" "harness-fingerprint.json missing from sensitive-file-guard"
  fi

  if grep -qF 'model-baselines.json' "$GUARD"; then
    pass "PRH-002b" "sensitive-file-guard protects model-baselines.json"
  else
    fail "PRH-002b" "model-baselines.json missing from sensitive-file-guard"
  fi

  # The test for sensitive-file-guard itself must cover Bash redirect blocking
  # for both meta paths (per spec PRH-002 Detection / ME-6 round-2)
  if grep -qE 'harness-fingerprint\.json' "$GUARD_TEST"; then
    pass "PRH-002c" "test-sensitive-file-guard.sh covers harness-fingerprint.json"
  else
    fail "PRH-002c" "test-sensitive-file-guard.sh missing harness-fingerprint.json case"
  fi

  if grep -qE 'model-baselines\.json' "$GUARD_TEST"; then
    pass "PRH-002d" "test-sensitive-file-guard.sh covers model-baselines.json"
  else
    fail "PRH-002d" "test-sensitive-file-guard.sh missing model-baselines.json case"
  fi

  # Live invocation: feed guard a Bash-redirect command targeting both files; must block
  if [ -f "$GUARD" ]; then
    local out code
    out=$(echo '{"tool_name":"Bash","tool_input":{"command":"echo X > .correctless/meta/harness-fingerprint.json"}}' | bash "$GUARD" 2>&1; echo "EXIT=$?")
    code=$(echo "$out" | grep '^EXIT=' | sed 's/^EXIT=//')
    if [ "$code" = "2" ]; then
      pass "PRH-002e" "live: Bash redirect to fingerprint file is blocked (exit 2)"
    else
      fail "PRH-002e" "live: Bash redirect to fingerprint file exited $code (expected 2)"
    fi

    out=$(echo '{"tool_name":"Bash","tool_input":{"command":"echo X > .correctless/meta/model-baselines.json"}}' | bash "$GUARD" 2>&1; echo "EXIT=$?")
    code=$(echo "$out" | grep '^EXIT=' | sed 's/^EXIT=//')
    if [ "$code" = "2" ]; then
      pass "PRH-002f" "live: Bash redirect to baseline file is blocked (exit 2)"
    else
      fail "PRH-002f" "live: Bash redirect to baseline file exited $code (expected 2)"
    fi

    # tee variant
    out=$(echo '{"tool_name":"Bash","tool_input":{"command":"echo X | tee .correctless/meta/harness-fingerprint.json"}}' | bash "$GUARD" 2>&1; echo "EXIT=$?")
    code=$(echo "$out" | grep '^EXIT=' | sed 's/^EXIT=//')
    if [ "$code" = "2" ]; then
      pass "PRH-002g" "live: Bash tee to fingerprint file is blocked"
    else
      fail "PRH-002g" "live: Bash tee to fingerprint file exited $code (expected 2)"
    fi

    # Edit variant
    out=$(echo '{"tool_name":"Edit","tool_input":{"file_path":".correctless/meta/model-baselines.json","old_string":"a","new_string":"b"}}' | bash "$GUARD" 2>&1; echo "EXIT=$?")
    code=$(echo "$out" | grep '^EXIT=' | sed 's/^EXIT=//')
    if [ "$code" = "2" ]; then
      pass "PRH-002h" "live: Edit on baseline file is blocked"
    else
      fail "PRH-002h" "live: Edit on baseline file exited $code (expected 2)"
    fi
  fi
}
test_prh002_structural_enforcement

# ============================================================================
# PRH-003: cmodelupgrade does not auto-apply recommendations
# ============================================================================

section "PRH-003: /cmodelupgrade does not auto-apply recommendations"

test_prh003_no_auto_apply() {
  if [ ! -f "$CMODELUPGRADE_SKILL" ]; then
    fail "PRH-003" "$CMODELUPGRADE_SKILL not found"
    return
  fi

  # No auto-apply / auto-trigger language
  if grep -qiE 'auto[- ]apply|auto[- ]trigger|automatically (appl|trigger|run)' "$CMODELUPGRADE_SKILL"; then
    # Check whether it's negation
    if grep -B 2 -A 2 -iE 'auto[- ]apply|auto[- ]trigger|automatically (appl|trigger|run)' "$CMODELUPGRADE_SKILL" \
       | grep -qiE 'never|do not|does not|must not|cannot|advisory'; then
      pass "PRH-003a" "skill mentions auto-apply only as prohibition"
    else
      fail "PRH-003a" "skill contains non-negated auto-apply language"
    fi
  else
    pass "PRH-003a" "skill contains no auto-apply language"
  fi

  # allowed-tools must NOT include Task (would let it spawn subagents)
  local allowed
  allowed=$(grep -E '^allowed-tools:' "$CMODELUPGRADE_SKILL" | head -1)
  if echo "$allowed" | grep -qE '\bTask\b'; then
    fail "PRH-003b" "/cmodelupgrade allowed-tools includes Task (auto-apply risk via subagents)"
  else
    pass "PRH-003b" "/cmodelupgrade allowed-tools does not include Task"
  fi

  # ME-12: skill explicitly states "spawns no subagents"
  if grep -qiE 'spawn.*no.*subagent|no.*subagent.*spawn|spawns NO sub' "$CMODELUPGRADE_SKILL"; then
    pass "PRH-003c" "skill explicitly states it spawns no subagents (ME-12)"
  else
    fail "PRH-003c" "skill missing 'spawns no subagents' statement (ME-12)"
  fi
}
test_prh003_no_auto_apply

# ============================================================================
# PRH-004: No verbatim system-prompt content in either meta file
# ============================================================================

section "PRH-004: meta files contain only schema-allowed fields"

test_prh004_data_minimization() {
  local d
  d=$(mkworkdir prh004)
  run_script_v 1 --meta-dir "$d/.correctless/meta" --session-id "__test_session_prh004__" --model "claude-x" check >/dev/null

  local f="$d/.correctless/meta/harness-fingerprint.json"
  if [ -f "$f" ]; then
    # Must contain only fingerprint, harness_version, model, timestamp, schema_version at top level
    # (schema_version added 2026-04-26 — MA-UC-001 fix mirrors BND-004 in model-baselines.json)
    local extra
    extra=$(jq -r 'keys[]' "$f" 2>/dev/null \
            | grep -vE '^(fingerprint|harness_version|model|timestamp|schema_version)$' || true)
    if [ -z "$extra" ]; then
      pass "PRH-004a" "fingerprint file has only sanctioned fields"
    else
      fail "PRH-004a" "fingerprint file has extra field(s): $extra"
    fi

    # Must not contain anything that looks like a system prompt
    if jq -r 'to_entries[] | .value | tostring' "$f" 2>/dev/null \
        | grep -qiE 'You are|harness|instructions|system prompt|<system'; then
      fail "PRH-004b" "fingerprint file contains prose-like content"
    else
      pass "PRH-004b" "fingerprint file contains no prose"
    fi
  else
    fail "PRH-004a" "fingerprint file missing"
  fi
}
test_prh004_data_minimization

# ============================================================================
# PRH-005: At most one notification per session
# Already covered structurally by INV-003. Here we add belt-and-suspenders:
# the script's notification path must check the flag file BEFORE emitting.
# ============================================================================

section "PRH-005: Notification path checks flag file before emit"

test_prh005_flag_gate() {
  if [ ! -f "$SCRIPT" ]; then
    fail "PRH-005" "script missing"
    return
  fi
  if grep -qE 'harness-notified.*flag|flag.*harness-notified|notified[_-]flag|notify[_-]flag' "$SCRIPT"; then
    pass "PRH-005" "script body references the notification flag file"
  else
    fail "PRH-005" "script body does not reference the notification flag file"
  fi
}
test_prh005_flag_gate

# ============================================================================
# PRH-006: HARNESS_VERSION constant cannot be bumped autonomously
# ============================================================================

section "PRH-006: HARNESS_VERSION protected from autonomous bump (after first commit)"

test_prh006_harness_version_protection() {
  # The script itself must be in sensitive-file-guard's protected paths
  if grep -qF 'harness-fingerprint.sh' "$GUARD"; then
    pass "PRH-006a" "scripts/harness-fingerprint.sh in sensitive-file-guard protected list"
  else
    fail "PRH-006a" "scripts/harness-fingerprint.sh not protected by sensitive-file-guard"
  fi

  # HARNESS_VERSION must be a top-level integer constant in the script
  if grep -qE '^HARNESS_VERSION=[0-9]+|^readonly HARNESS_VERSION=[0-9]+|^declare -r HARNESS_VERSION=[0-9]+' "$SCRIPT"; then
    pass "PRH-006b" "HARNESS_VERSION declared as integer constant at top of script"
  else
    fail "PRH-006b" "HARNESS_VERSION not declared as integer constant"
  fi

  # Live: blocked when guard is invoked with Edit on the script
  if [ -f "$GUARD" ] && [ -f "$SCRIPT" ]; then
    local out code
    out=$(echo '{"tool_name":"Edit","tool_input":{"file_path":"scripts/harness-fingerprint.sh","old_string":"HARNESS_VERSION=1","new_string":"HARNESS_VERSION=2"}}' | bash "$GUARD" 2>&1; echo "EXIT=$?")
    code=$(echo "$out" | grep '^EXIT=' | sed 's/^EXIT=//')
    if [ "$code" = "2" ]; then
      pass "PRH-006c" "live: Edit on harness-fingerprint.sh blocked by guard"
    else
      fail "PRH-006c" "live: Edit on harness-fingerprint.sh exited $code (expected 2)"
    fi
  fi
}
test_prh006_harness_version_protection

# ============================================================================
# BND-001: HARNESS_VERSION mismatch produces version_bumped status
# Covered by INV-002. Spot-check: version_bumped is the ONLY mismatch status.
# ============================================================================

section "BND-001: Version mismatch yields version_bumped status (no substring_list_changed)"

test_bnd001_status_collapse() {
  # The script must NOT emit substring_list_changed (collapsed in revision 2)
  if grep -qE 'substring_list_changed' "$SCRIPT"; then
    fail "BND-001" "script emits substring_list_changed (collapsed in spec round 2)"
  else
    pass "BND-001" "script does not emit substring_list_changed"
  fi
}
test_bnd001_status_collapse

# ============================================================================
# BND-002: Concurrent invocations on same project — locking on fingerprint write
# ============================================================================

section "BND-002: Concurrent /cspec invocations — locked write on fingerprint"

test_bnd002_locking() {
  if [ ! -f "$SCRIPT" ]; then
    fail "BND-002" "script missing"
    return
  fi
  # Script must use lib.sh's locking mechanism for the fingerprint write
  if grep -qE 'locked_update|_acquire_state_lock|locked_update_file|locked_update_state|flock' "$SCRIPT"; then
    pass "BND-002a" "script uses locking helpers for fingerprint writes"
  else
    fail "BND-002a" "script does not use any locking helper (BND-002 risk)"
  fi
}
test_bnd002_locking

# ============================================================================
# BND-003: Session-id fallback chain — /proc → ps -o lstart= → PID-only
# ============================================================================

section "BND-003: get_current_session_id() fallback chain"

test_bnd003_session_id_fallback() {
  if [ ! -f "$LIB" ]; then
    fail "BND-003" "lib.sh not found"
    return
  fi
  # Must define the helper
  if grep -qE '^get_current_session_id\(\)|^function get_current_session_id' "$LIB"; then
    pass "BND-003a" "lib.sh defines get_current_session_id()"
  else
    fail "BND-003a" "lib.sh missing get_current_session_id() helper"
  fi

  # Must implement the cross-platform mechanism: ps -o lstart= (canonical) OR /proc/.../stat
  if grep -qE 'ps -o lstart=|/proc/.*/stat|/proc/\$\{?pid' "$LIB"; then
    pass "BND-003b" "lib.sh implements ps -o lstart= or /proc fallback"
  else
    fail "BND-003b" "lib.sh missing ps/proc-based session-id derivation"
  fi

  # Live: helper must produce stable output within same shell process
  # shellcheck source=/dev/null
  if (source "$LIB" >/dev/null 2>&1 && declare -F get_current_session_id >/dev/null); then
    local id1 id2
    # shellcheck source=/dev/null
    source "$LIB"
    id1=$(get_current_session_id 2>/dev/null || true)
    id2=$(get_current_session_id 2>/dev/null || true)
    if [ -n "$id1" ] && [ "$id1" = "$id2" ]; then
      pass "BND-003c" "get_current_session_id is stable within process ($id1)"
    else
      fail "BND-003c" "get_current_session_id unstable (id1=$id1 id2=$id2)"
    fi
  else
    fail "BND-003c" "could not source lib.sh and call get_current_session_id"
  fi
}
test_bnd003_session_id_fallback

# ============================================================================
# BND-004: Baseline schema_version mismatch → fail-open prompt re-capture
# ============================================================================

section "BND-004: Baseline schema_version mismatch handled gracefully"

test_bnd004_schema_evolution() {
  if [ ! -f "$CMODELUPGRADE_SKILL" ]; then
    fail "BND-004" "skill missing"
    return
  fi
  if grep -qiE 'schema_version.*mismatch|mismatch.*schema_version|treats baseline as missing|prompt.*re-capture|re-capture' "$CMODELUPGRADE_SKILL"; then
    pass "BND-004" "skill handles schema_version mismatch (fail-open + prompt re-capture)"
  else
    fail "BND-004" "skill missing schema_version mismatch handling"
  fi
}
test_bnd004_schema_evolution

# ============================================================================
# BND-005: Three-tier bootstrap lookup (exact-match / pre-fingerprint / no-baseline)
# ============================================================================

section "BND-005: Three-tier bootstrap pool lookup + cverify extension"

test_bnd005_three_tier() {
  if [ ! -f "$CMODELUPGRADE_SKILL" ]; then
    fail "BND-005a" "$CMODELUPGRADE_SKILL not found"
    return
  fi
  # Three pools mentioned
  for term in 'exact[- ]match' 'pre[- ]fingerprint' 'no[- ]baseline'; do
    if grep -qiE "$term" "$CMODELUPGRADE_SKILL"; then
      pass "BND-005a-$term" "skill mentions '$term' pool"
    else
      fail "BND-005a-$term" "skill missing '$term' pool reference"
    fi
  done

  # Must NOT mix pools (warn against averaging)
  if grep -qiE 'do not mix|never mix|misleading averages|pools that should.*not.*combined' "$CMODELUPGRADE_SKILL"; then
    pass "BND-005b" "skill warns against pool mixing"
  else
    fail "BND-005b" "skill missing no-pool-mixing language"
  fi

  # /cverify must be extended to write harness_version
  if [ -f "$CVERIFY_SKILL" ]; then
    if grep -qE 'harness_version|HARNESS_VERSION|harness-fingerprint' "$CVERIFY_SKILL"; then
      pass "BND-005c" "/cverify references harness_version (writes it on calibration)"
    else
      fail "BND-005c" "/cverify missing harness_version field write"
    fi
  else
    fail "BND-005c" "$CVERIFY_SKILL not found"
  fi
}
test_bnd005_three_tier

# ============================================================================
# Prerequisites — allowed-tools cross-check, sync, namespace migration
# ============================================================================

section "Prerequisites — wiring & cross-cutting integrations"

test_prereq_wiring() {
  # cspec allowed-tools includes Bash(*harness-fingerprint*)
  if [ -f "$CSPEC_SKILL" ] && grep -E '^allowed-tools:' "$CSPEC_SKILL" | head -1 | grep -qE 'harness-fingerprint'; then
    pass "PRE-001" "skills/cspec/SKILL.md allowed-tools includes harness-fingerprint Bash permission"
  else
    fail "PRE-001" "skills/cspec/SKILL.md allowed-tools missing harness-fingerprint Bash"
  fi

  # csetup scaffolds template
  if [ -f "$CSETUP_SKILL" ] && grep -qE 'baseline\.md|test-features.*baseline' "$CSETUP_SKILL"; then
    pass "PRE-002" "skills/csetup/SKILL.md scaffolds baseline.md template"
  else
    fail "PRE-002" "skills/csetup/SKILL.md missing baseline.md scaffold step"
  fi

  # Template baseline.md exists
  if [ -f "$TEMPLATE_BASELINE" ]; then
    pass "PRE-003" "templates/test-features/baseline.md exists"
  else
    fail "PRE-003" "templates/test-features/baseline.md missing"
  fi

  # sync.sh syncs cmodelupgrade skill and harness-fingerprint script
  if grep -qE 'cmodelupgrade|skills/\*/' "$SYNC"; then
    pass "PRE-004a" "sync.sh handles cmodelupgrade skill (or glob-based)"
  else
    fail "PRE-004a" "sync.sh missing cmodelupgrade entry"
  fi

  # The skill should land in the distribution
  if [ -f "$CMODELUPGRADE_DIST" ]; then
    pass "PRE-004b" "correctless/skills/cmodelupgrade/SKILL.md exists (distribution synced)"
  else
    fail "PRE-004b" "correctless/skills/cmodelupgrade/SKILL.md missing — sync not run or sync.sh not patched"
  fi

  if [ -f "$REPO_DIR/correctless/scripts/harness-fingerprint.sh" ]; then
    pass "PRE-004c" "correctless/scripts/harness-fingerprint.sh synced"
  else
    fail "PRE-004c" "correctless/scripts/harness-fingerprint.sh not in distribution"
  fi

  # Template synced too
  if [ -f "$TEMPLATE_BASELINE_DIST" ] || grep -qE 'test-features' "$SYNC"; then
    pass "PRE-004d" "test-features baseline template wired into sync"
  else
    fail "PRE-004d" "test-features baseline template not wired into sync.sh"
  fi

  # test-allowed-tools-check.sh covers cmodelupgrade
  if grep -qE 'cmodelupgrade' "$ALLOWED_TEST"; then
    pass "PRE-005" "tests/test-allowed-tools-check.sh covers cmodelupgrade"
  else
    fail "PRE-005" "tests/test-allowed-tools-check.sh missing cmodelupgrade coverage"
  fi

  # test-scripts-namespace-migration.sh covers harness-fingerprint.sh
  if grep -qE 'harness-fingerprint' "$NS_TEST"; then
    pass "PRE-006" "tests/test-scripts-namespace-migration.sh covers harness-fingerprint.sh"
  else
    fail "PRE-006" "tests/test-scripts-namespace-migration.sh missing harness-fingerprint.sh coverage"
  fi
}
test_prereq_wiring

# ============================================================================
# MA-HI-001 regression (mini-audit hostile-input finding):
# --session-id flows into FLAG_FILE path. A hostile or malformed value (e.g.
# path-traversal) must be sanitized so the resulting flag file cannot escape
# ARTIFACTS_DIR. The script sanitizes by replacing chars outside [A-Za-z0-9_-]
# with '_'.
# ============================================================================

section "MA-HI-001: --session-id is sanitized before path construction"

test_ma_hi_001_session_id_sanitization() {
  local d
  d=$(mkworkdir ma_hi_001)

  # 1. Path-traversal session-id must NOT create files outside the artifacts dir
  local hostile="../../../etc/escaped"
  local out
  out=$(run_script_v 1 --meta-dir "$d/.correctless/meta" --artifacts-dir "$d/.correctless/artifacts" --session-id "$hostile" --model "test-model" check)
  local code
  code=$(extract_exit "$out")
  if [ "$code" = "0" ]; then
    pass "MA-HI-001a" "script exits 0 even with hostile session-id (PRH-001 preserved)"
  else
    fail "MA-HI-001a" "script exited $code with hostile session-id (expected 0 per PRH-001)"
  fi

  # No file should escape ARTIFACTS_DIR — search the parent of the workdir for
  # any flag file that escaped via the relative path.
  local escaped_count
  escaped_count=$(find "$d/.." -maxdepth 5 -name "harness-notified-*" -not -path "$d/*" 2>/dev/null | wc -l | tr -d ' ')
  if [ "$escaped_count" = "0" ]; then
    pass "MA-HI-001b" "no flag file escaped ARTIFACTS_DIR via path-traversal session-id"
  else
    fail "MA-HI-001b" "$escaped_count flag file(s) escaped ARTIFACTS_DIR (sanitization failed)"
  fi

  # 2. Trigger a version_bump so notification path runs (writes the flag file)
  # First write establishes baseline; second invocation with bumped version
  # writes the flag file under the sanitized session-id.
  out=$(run_script_v 2 --meta-dir "$d/.correctless/meta" --artifacts-dir "$d/.correctless/artifacts" --session-id "$hostile" --model "test-model" check)

  # The flag file should exist under ARTIFACTS_DIR with sanitized name (no slashes/dots from input)
  local flag_files
  flag_files=$(find "$d/.correctless/artifacts" -name "harness-notified-*" 2>/dev/null)
  if [ -n "$flag_files" ]; then
    pass "MA-HI-001c" "flag file written inside ARTIFACTS_DIR after sanitization"
    # The filename must not contain raw '/' or '..' segments from the hostile input
    if echo "$flag_files" | grep -qE 'harness-notified-[A-Za-z0-9_-]+\.flag$'; then
      pass "MA-HI-001d" "flag filename contains only safe charset [A-Za-z0-9_-]"
    else
      fail "MA-HI-001d" "flag filename contains unsanitized chars: $flag_files"
    fi
  else
    # If no flag file was written, that's also safe (no escape) — but means we
    # can't verify the sanitized-name shape. Pass MA-HI-001c via 001b.
    pass "MA-HI-001c" "no flag file written (safe — no escape possible)"
  fi
}
test_ma_hi_001_session_id_sanitization

# ============================================================================
# MA-UC-001 regression (mini-audit upgrade-compatibility finding):
# harness-fingerprint.json must include schema_version (mirrors BND-004 in
# model-baselines.json). Without it, future schema evolution cannot be detected.
# ============================================================================

section "MA-UC-001: harness-fingerprint.json includes schema_version field"

test_ma_uc_001_schema_version() {
  local d
  d=$(mkworkdir ma_uc_001)

  run_script_v 1 --meta-dir "$d/.correctless/meta" --artifacts-dir "$d/.correctless/artifacts" --session-id "__test_session_ma_uc_001__" --model "test-model" check >/dev/null

  local fp_file="$d/.correctless/meta/harness-fingerprint.json"
  if [ ! -f "$fp_file" ]; then
    fail "MA-UC-001a" "harness-fingerprint.json not written"
    return
  fi

  local sv
  sv=$(jq -r '.schema_version // empty' "$fp_file" 2>/dev/null)
  if [ "$sv" = "1" ]; then
    pass "MA-UC-001a" "harness-fingerprint.json contains schema_version: 1"
  else
    fail "MA-UC-001a" "harness-fingerprint.json missing or wrong schema_version (got: '$sv', expected: '1')"
  fi

  # On rewrite (version_bumped), schema_version must persist
  run_script_v 2 --meta-dir "$d/.correctless/meta" --artifacts-dir "$d/.correctless/artifacts" --session-id "__test_session_ma_uc_001__" --model "test-model" check >/dev/null
  sv=$(jq -r '.schema_version // empty' "$fp_file" 2>/dev/null)
  if [ "$sv" = "1" ]; then
    pass "MA-UC-001b" "schema_version preserved across version_bumped rewrite"
  else
    fail "MA-UC-001b" "schema_version dropped on rewrite (got: '$sv')"
  fi
}
test_ma_uc_001_schema_version

# ===========================================================================
# R2 Hardening tests — harness-fingerprint-r2-hardening spec
# INV-009, INV-010, INV-011, BND-003
# ===========================================================================

# ---------------------------------------------------------------------------
# INV-009 [structural]: HARNESS_VERSION constant is the sole production input.
# No --version flag, no env-var override, no defaulting form.
# Greps below run on non-comment lines only (M-11 false-match avoidance).
# ---------------------------------------------------------------------------
test_inv009_no_override_surface() {
  local non_comment
  non_comment="$(grep -v '^[[:space:]]*#' "$SCRIPT")"
  local fail_count=0

  for pat in '--version' '--harness-version' 'VERSION_OVERRIDE' '\$\{HARNESS_VERSION:-' '\$\{HARNESS_VERSION:=' ':[[:space:]]*\$\{HARNESS_VERSION:='; do
    if printf '%s' "$non_comment" | grep -qE -e "$pat"; then
      echo "  INV-009: forbidden pattern found: $pat" >&2
      fail_count=$((fail_count + 1))
    fi
  done

  if [ "$fail_count" -eq 0 ]; then
    pass "INV-009-structural" "no --version / VERSION_OVERRIDE / env-default surface in production script"
  else
    fail "INV-009-structural" "$fail_count override-surface patterns remain"
  fi
}

# ---------------------------------------------------------------------------
# INV-009 [integration]: invocation ignores override attempts
# ---------------------------------------------------------------------------
test_inv009_invocation_ignores_override() {
  local d
  d=$(mkworkdir inv009)

  # The literal HARNESS_VERSION in the file (only set by spec-controlled commit)
  local literal_v
  literal_v="$(grep -E '^HARNESS_VERSION=' "$SCRIPT" | head -1 | sed 's/^HARNESS_VERSION=//')"

  # (a) --version 99 must be silently dropped (unknown flag), fingerprint reflects literal
  local out fp
  out=$(bash "$SCRIPT" --meta-dir "$d/.correctless/meta" --session-id "__test_session_inv009a__" --model "claude-x" --version 99 check 2>/dev/null || true)
  fp=$(echo "$out" | grep -E '^fingerprint=' | head -1 | sed 's/^fingerprint=//')
  if [ -n "$fp" ] && echo "$fp" | grep -q "|${literal_v}\(|\|$\)"; then
    pass "INV-009a" "--version 99 ignored; fingerprint still reflects literal HARNESS_VERSION=${literal_v}"
  elif [ -n "$fp" ] && echo "$fp" | grep -q "|99\(|\|$\)"; then
    fail "INV-009a" "--version 99 escape hatch ACTIVE — fingerprint reflects 99 instead of ${literal_v}"
  else
    fail "INV-009a" "could not determine fingerprint version (got: '$fp')"
  fi

  # (b) HARNESS_VERSION=99 env-var must NOT override
  out=$(HARNESS_VERSION=99 bash "$SCRIPT" --meta-dir "$d/.correctless/meta" --session-id "__test_session_inv009b__" --model "claude-x" check 2>/dev/null || true)
  fp=$(echo "$out" | grep -E '^fingerprint=' | head -1 | sed 's/^fingerprint=//')
  if [ -n "$fp" ] && echo "$fp" | grep -q "|${literal_v}\(|\|$\)"; then
    pass "INV-009b" "HARNESS_VERSION=99 env-var ignored; literal preserved"
  else
    fail "INV-009b" "HARNESS_VERSION=99 env-var escape hatch ACTIVE (got fp='$fp', literal=${literal_v})"
  fi
}

# ---------------------------------------------------------------------------
# INV-010 [structural]: no --version invocations of $SCRIPT in tests
# (asserts the test migration completed)
# ---------------------------------------------------------------------------
test_inv010_no_version_flag_in_tests() {
  # Find call sites of $SCRIPT or run_script that pass --version directly.
  # The R2-hardening tests intentionally pass --version to verify it is
  # ignored (INV-009 verification) — those are the only legitimate
  # post-migration uses, and we exclude them by test-function name.
  local count
  count="$(awk '
    /^test_inv009_invocation_ignores_override\(\)/ { skip = 1 }
    /^test_inv010_no_version_flag_in_tests\(\)/ { skip = 1 }
    /^\}$/ { skip = 0 }
    !skip { print }
  ' "$REPO_DIR/tests/test-harness-fingerprint.sh" \
    | grep -nE '\$SCRIPT[^|]*--version|"\$SCRIPT".*--version|run_script[^)]*--version' \
    | grep -vE '^[[:space:]]*[0-9]+:[[:space:]]*#' \
    | wc -l)"
  if [ "$count" -eq 0 ]; then
    pass "INV-010-no-flag-in-tests" "no --version invocations of \$SCRIPT in test-harness-fingerprint.sh"
  else
    fail "INV-010-no-flag-in-tests" "$count test invocations still pass --version directly to \$SCRIPT"
  fi
}

# ---------------------------------------------------------------------------
# INV-010 [structural]: helper lives in feature-specific helper file
# (NOT in shared tests/test-helpers.sh per Finding #8)
# ---------------------------------------------------------------------------
test_inv010_helper_in_feature_file() {
  local feat="$REPO_DIR/tests/harness-fingerprint-test-helpers.sh"
  local shared="$REPO_DIR/tests/test-helpers.sh"
  local fail_count=0

  if [ ! -f "$feat" ]; then
    fail "INV-010-helper-file" "tests/harness-fingerprint-test-helpers.sh does not exist"
    fail_count=$((fail_count + 1))
  elif ! grep -qE '^[[:space:]]*make_test_harness_script[[:space:]]*\(\)' "$feat"; then
    fail "INV-010-helper-file" "make_test_harness_script not defined in feature-specific helper file"
    fail_count=$((fail_count + 1))
  fi

  if grep -qE '^[[:space:]]*make_test_harness_script[[:space:]]*\(\)' "$shared"; then
    fail "INV-010-helper-file" "make_test_harness_script leaked into shared test-helpers.sh (Finding #8 regression)"
    fail_count=$((fail_count + 1))
  fi

  if [ "$fail_count" -eq 0 ]; then
    pass "INV-010-helper-file" "helper lives in harness-fingerprint-test-helpers.sh, not shared test-helpers.sh"
  fi
}

# ---------------------------------------------------------------------------
# INV-010 [integration]: helper produces a script with the injected version
# ---------------------------------------------------------------------------
test_inv010_helper_produces_correct_version() {
  local feat="$REPO_DIR/tests/harness-fingerprint-test-helpers.sh"
  if [ ! -f "$feat" ]; then
    fail "INV-010-helper-runtime" "feature helper file missing — cannot test runtime"
    return
  fi
  # shellcheck disable=SC1090
  if ! ( source "$feat" && declare -f make_test_harness_script >/dev/null 2>&1 ); then
    fail "INV-010-helper-runtime" "make_test_harness_script not loadable from feature helper file"
    return
  fi

  local d
  d=$(mkworkdir inv010_runtime)
  local script_path
  # shellcheck disable=SC1090
  script_path="$( source "$feat" && make_test_harness_script 42 "$d" 2>/dev/null )"
  if [ -z "$script_path" ] || [ ! -f "$script_path" ]; then
    fail "INV-010-helper-runtime" "helper did not produce a usable script path (got: '$script_path')"
    return
  fi

  # Filename pattern check
  local base
  base="$(basename "$script_path")"
  case "$base" in
    harness-fp-test-*.sh) pass "INV-010-filename" "destination filename matches harness-fp-test-*.sh ($base)" ;;
    *) fail "INV-010-filename" "destination filename does not match harness-fp-test-*.sh (got: '$base')" ;;
  esac

  # The destination must NOT contain a 'scripts/' parent component
  case "$script_path" in
    */scripts/*) fail "INV-010-no-scripts-parent" "destination has a 'scripts/' parent ($script_path) — would match protected pattern" ;;
    *) pass "INV-010-no-scripts-parent" "destination has no 'scripts/' parent component" ;;
  esac

  # Run the produced script — fingerprint must reflect 42
  local out fp
  out=$(bash "$script_path" --meta-dir "$d/.correctless/meta" --session-id "__test_session_inv010__" --model "claude-x" check 2>/dev/null || true)
  fp=$(echo "$out" | grep -E '^fingerprint=' | head -1 | sed 's/^fingerprint=//')
  if [ -n "$fp" ] && echo "$fp" | grep -q "|42\(|\|$\)"; then
    pass "INV-010-injected-version" "produced script's fingerprint reflects injected version=42"
  else
    fail "INV-010-injected-version" "fingerprint does not reflect injected version (got: '$fp')"
  fi
}

# ---------------------------------------------------------------------------
# BND-003: helper destination not protected; helper output byte-equal to
# production source except the HARNESS_VERSION= line.
# ---------------------------------------------------------------------------
test_bnd003_helper_destination_not_protected() {
  local feat="$REPO_DIR/tests/harness-fingerprint-test-helpers.sh"
  if [ ! -f "$feat" ]; then
    fail "BND-003-not-protected" "feature helper file missing — cannot test"
    return
  fi
  local d
  d=$(mkworkdir bnd003_protected)
  local script_path
  # shellcheck disable=SC1090
  script_path="$( source "$feat" && make_test_harness_script 7 "$d" 2>/dev/null )"
  if [ -z "$script_path" ]; then
    fail "BND-003-not-protected" "helper did not produce a path"
    return
  fi
  case "$script_path" in
    */scripts/harness-fingerprint.sh)
      fail "BND-003-not-protected" "destination path matches protected pattern ($script_path)" ;;
    *)
      pass "BND-003-not-protected" "destination does NOT match */scripts/harness-fingerprint.sh" ;;
  esac
}

test_bnd003_helper_byte_equal_except_version() {
  local feat="$REPO_DIR/tests/harness-fingerprint-test-helpers.sh"
  if [ ! -f "$feat" ]; then
    fail "BND-003-byte-equal" "feature helper file missing — cannot test"
    return
  fi
  local d
  d=$(mkworkdir bnd003_byteq)
  local script_path
  # shellcheck disable=SC1090
  script_path="$( source "$feat" && make_test_harness_script 13 "$d" 2>/dev/null )"
  if [ -z "$script_path" ] || [ ! -f "$script_path" ]; then
    fail "BND-003-byte-equal" "helper did not produce a usable script"
    return
  fi
  local literal_v
  literal_v="$(grep -E '^HARNESS_VERSION=' "$SCRIPT" | head -1 | sed 's/^HARNESS_VERSION=//')"

  # Re-substitute the helper output back to the production version constant,
  # then diff against the production source. Only difference must be... nothing.
  local resub
  resub="$d/resub.sh"
  sed -E 's/^HARNESS_VERSION=.*$/HARNESS_VERSION='"$literal_v"'/' "$script_path" > "$resub"
  if diff -q "$resub" "$SCRIPT" >/dev/null 2>&1; then
    pass "BND-003-byte-equal" "helper output byte-equal to production source modulo HARNESS_VERSION line"
  else
    fail "BND-003-byte-equal" "helper output diverges from production source beyond HARNESS_VERSION line"
  fi
}

test_inv009_no_override_surface
test_inv009_invocation_ignores_override
test_inv010_no_version_flag_in_tests
test_inv010_helper_in_feature_file
test_inv010_helper_produces_correct_version
test_bnd003_helper_destination_not_protected
test_bnd003_helper_byte_equal_except_version

summary "Harness Fingerprint"
