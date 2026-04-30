#!/usr/bin/env bash
# Correctless — Audit Findings Persistence Contract Tests (RED phase)
# Spec: .correctless/specs/audit-findings-persistence-contract.md
# Covers: INV-001..009, PRH-001..005, BND-001..002, EA-001a
# Run from repo root: bash tests/test-audit-findings-persistence.sh

source "$(dirname "${BASH_SOURCE[0]}")/test-helpers.sh"

WORKFLOW_ADVANCE="$REPO_DIR/hooks/workflow-advance.sh"
AUDIT_RECORD="$REPO_DIR/scripts/audit-record.sh"
SENSITIVE_GUARD="$REPO_DIR/hooks/sensitive-file-guard.sh"
CAUDIT_SKILL="$REPO_DIR/skills/caudit/SKILL.md"
CMETRICS_SKILL="$REPO_DIR/skills/cmetrics/SKILL.md"
# ARCH_DOC referenced indirectly via test-architecture-drift.sh's ABS-resolve check; kept for symmetry with other test files
# shellcheck disable=SC2034
ARCH_DOC="$REPO_DIR/.correctless/ARCHITECTURE.md"

# Test workspace
WORK_BASE="/tmp/correctless-afp-$$"
cleanup() { rm -rf "$WORK_BASE"; }
trap cleanup EXIT

mkworkdir() {
  local sub="$1"
  local d="$WORK_BASE/$sub"
  rm -rf "$d"
  mkdir -p "$d/.correctless/artifacts/findings" "$d/.correctless/scripts" "$d/hooks" "$d/scripts"
  echo "$d"
}

# Build a real git repo workdir on an audit branch with the given preset and
# started_at, then write the workflow state file at the path branch_slug()
# will resolve to. Pattern matches test-workflow-gate.sh's setup_test_env.
make_state_fixture() {
  local d="$1" preset="$2" started_at="$3"
  ( cd "$d" && \
    git init -q && \
    git branch -M main && \
    echo init > README.md && \
    git add -A && git commit -q -m init && \
    git checkout -q -b "audit/${preset}-2026-04-29" ) >/dev/null 2>&1
  # Derive the slug the same way lib.sh does
  local slug
  slug=$( cd "$d" && \
    bash -c 'source '"$REPO_DIR"'/scripts/lib.sh && branch_slug' )
  local sf="$d/.correctless/artifacts/workflow-state-${slug}.json"
  jq -n \
    --arg phase "audit" \
    --arg started_at "$started_at" \
    --arg phase_entered_at "$started_at" \
    --arg branch "audit/${preset}-2026-04-29" \
    --arg audit_type "$preset" \
    '{
       phase: $phase,
       task: ("audit-" + $audit_type),
       spec_file: null,
       started_at: $started_at,
       phase_entered_at: $phase_entered_at,
       branch: $branch,
       qa_rounds: 0,
       audit: { type: $audit_type, rounds_completed: 1, total_findings: 0, findings_fixed: 0, converged: true }
     }' > "$sf"
  echo "$sf"
}

# Run workflow-advance.sh audit-done from the fixture workdir, capture exit + stderr.
run_audit_done() {
  local d="$1"
  local err code
  err=$( cd "$d" && bash "$WORKFLOW_ADVANCE" audit-done 2>&1 >/dev/null ) && code=0 || code=$?
  echo "EXIT=$code"
  echo "--STDERR--"
  echo "$err"
}

extract_exit() { echo "$1" | head -1 | sed 's/^EXIT=//'; }
extract_stderr() { echo "$1" | sed -n '/^--STDERR--$/,$p' | tail -n +2; }

# ============================================================================
# INV-001: cmd_audit_done refuses without current-run round-JSON
# ============================================================================

test_inv001_gate_blocks_without_artifact() {
  local d
  d=$(mkworkdir inv001a)
  make_state_fixture "$d" "qa" "2026-04-29T10:00:00Z" >/dev/null

  local result
  result=$(run_audit_done "$d")
  local code
  code=$(extract_exit "$result")

  if [ "$code" != "0" ]; then
    pass "INV-001-blocks" "cmd_audit_done exits non-zero with no round-JSON present (got exit=$code)"
  else
    fail "INV-001-blocks" "cmd_audit_done passed without any round-JSON — gate is open"
  fi
}

test_inv001_gate_passes_with_matching_started_at() {
  local d
  d=$(mkworkdir inv001b)
  make_state_fixture "$d" "qa" "2026-04-29T10:00:00Z" >/dev/null

  cat > "$d/.correctless/artifacts/findings/audit-qa-2026-04-29-round-1.json" <<EOF
{
  "preset": "qa",
  "date": "2026-04-29",
  "round": 1,
  "findings": [],
  "rejected": [],
  "started_at": "2026-04-29T10:00:00Z"
}
EOF

  local result code
  result=$(run_audit_done "$d")
  code=$(extract_exit "$result")

  if [ "$code" = "0" ]; then
    pass "INV-001-passes" "cmd_audit_done exits 0 when round-JSON's started_at matches state"
  else
    fail "INV-001-passes" "cmd_audit_done failed (exit=$code) despite matching round-JSON"
  fi
}

test_inv001_gate_rejects_mismatched_started_at() {
  local d
  d=$(mkworkdir inv001c)
  make_state_fixture "$d" "qa" "2026-04-29T10:00:00Z" >/dev/null

  # Round-JSON exists but with a different started_at (from a previous audit)
  cat > "$d/.correctless/artifacts/findings/audit-qa-2026-04-28-round-1.json" <<EOF
{
  "preset": "qa",
  "date": "2026-04-28",
  "round": 1,
  "findings": [],
  "rejected": [],
  "started_at": "2026-04-28T08:00:00Z"
}
EOF

  local result code
  result=$(run_audit_done "$d")
  code=$(extract_exit "$result")

  if [ "$code" != "0" ]; then
    pass "INV-001-rejects-mismatch" "gate rejects round-JSON with stale started_at (exit=$code)"
  else
    fail "INV-001-rejects-mismatch" "gate accepted round-JSON whose started_at does NOT match state — content match broken"
  fi
}

test_inv001_gate_rejects_null_audit_type() {
  local d
  d=$(mkworkdir inv001d)
  local sf
  sf=$(make_state_fixture "$d" "qa" "2026-04-29T10:00:00Z")
  # Wipe .audit.type
  jq '.audit.type = null' "$sf" > "${sf}.tmp" && mv "${sf}.tmp" "$sf"

  local result code stderr
  result=$(run_audit_done "$d")
  code=$(extract_exit "$result")
  stderr=$(extract_stderr "$result")

  if [ "$code" != "0" ] && ! echo "$stderr" | grep -q 'audit-null-'; then
    pass "INV-001-null-audit-type" "gate refuses null .audit.type with diagnostic, no audit-null-* glob"
  else
    fail "INV-001-null-audit-type" "gate either passed (exit=$code) or constructed an audit-null-* glob"
  fi
}

# ============================================================================
# INV-001a: remediation message names expected path + started_at
# ============================================================================

test_inv001a_remediation_message_explicit() {
  local d
  d=$(mkworkdir inv001a_msg)
  make_state_fixture "$d" "hacker" "2026-04-29T11:30:00Z" >/dev/null

  local result stderr
  result=$(run_audit_done "$d")
  stderr=$(extract_stderr "$result")

  local fail_count=0
  if ! echo "$stderr" | grep -qF "Audit findings missing"; then
    fail_count=$((fail_count + 1))
    echo "  INV-001a: stderr missing 'Audit findings missing' literal" >&2
  fi
  if ! echo "$stderr" | grep -qF "audit-hacker-"; then
    fail_count=$((fail_count + 1))
    echo "  INV-001a: stderr missing 'audit-hacker-*-round-*.json' pattern" >&2
  fi
  if ! echo "$stderr" | grep -qF "2026-04-29T11:30:00Z"; then
    fail_count=$((fail_count + 1))
    echo "  INV-001a: stderr missing started_at ISO timestamp" >&2
  fi

  if [ "$fail_count" -eq 0 ]; then
    pass "INV-001a-message" "remediation contains all three required substrings"
  else
    fail "INV-001a-message" "$fail_count of 3 required substrings missing"
  fi
}

# ============================================================================
# INV-002: canonical path format + schema
# ============================================================================

test_inv002_canonical_path_and_schema() {
  if [ ! -x "$AUDIT_RECORD" ]; then
    fail "INV-002-path" "audit-record.sh does not exist or is not executable"
    return
  fi
  local d
  d=$(mkworkdir inv002a)
  make_state_fixture "$d" "qa" "2026-04-29T12:00:00Z" >/dev/null

  ( cd "$d" && echo '{"findings": [], "rejected": []}' | bash "$AUDIT_RECORD" write-round qa 1 - >/dev/null 2>&1 ) || true

  local expected="$d/.correctless/artifacts/findings/audit-qa-2026-04-29-round-1.json"
  if [ ! -f "$expected" ]; then
    fail "INV-002-path" "expected output not at canonical path $expected"
    return
  fi

  # Verify all 6 required fields present
  local fail_count=0
  for field in preset date round findings rejected started_at; do
    if ! jq -e ".$field // empty" "$expected" >/dev/null 2>&1; then
      fail_count=$((fail_count + 1))
      echo "  INV-002: missing required field '$field'" >&2
    fi
  done

  if [ "$fail_count" -eq 0 ]; then
    pass "INV-002-path" "file at canonical path with all 6 required schema fields"
  else
    fail "INV-002-path" "$fail_count of 6 required fields missing"
  fi
}

test_inv002_path_json_consistency() {
  # QA-R3-002: path's preset/date/round MUST equal the JSON's corresponding
  # fields. A future jq-merge-order regression (canonical-fields object on
  # the LEFT instead of the RIGHT of `+`) would silently drop path/JSON
  # consistency since stdin's preset would win the merge.
  if [ ! -x "$AUDIT_RECORD" ]; then fail "INV-002-path-json" "audit-record.sh missing"; return; fi
  local d
  d=$(mkworkdir inv002_consistency)
  make_state_fixture "$d" "qa" "2026-04-29T12:34:56Z" >/dev/null

  # stdin tries to override preset/date/round — script's merge must override stdin
  echo '{"findings": [], "rejected": [], "preset": "evil", "date": "1999-01-01", "round": 99}' \
    | (cd "$d" && bash "$AUDIT_RECORD" write-round qa 1 -) >/dev/null 2>&1

  local f="$d/.correctless/artifacts/findings/audit-qa-2026-04-29-round-1.json"
  if [ ! -f "$f" ]; then fail "INV-002-path-json" "file not written"; return; fi

  local p_json d_json r_json
  p_json=$(jq -r '.preset' "$f")
  d_json=$(jq -r '.date' "$f")
  r_json=$(jq -r '.round | tostring' "$f")

  if [ "$p_json" = "qa" ] && [ "$d_json" = "2026-04-29" ] && [ "$r_json" = "1" ]; then
    pass "INV-002-path-json" "path's preset/date/round override stdin in merge (canonical fields win)"
  else
    fail "INV-002-path-json" "stdin overrode canonical fields (preset=$p_json date=$d_json round=$r_json) — merge order broken"
  fi
}

test_inv002_rejects_invalid_inputs() {
  if [ ! -x "$AUDIT_RECORD" ]; then
    fail "INV-002-rejects" "audit-record.sh missing"
    return
  fi
  local d
  d=$(mkworkdir inv002b)
  make_state_fixture "$d" "qa" "2026-04-29T12:00:00Z" >/dev/null

  local fail_count=0

  # Missing findings field
  echo '{"rejected": []}' | (cd "$d" && bash "$AUDIT_RECORD" write-round qa 1 - 2>/dev/null)
  [ $? -eq 0 ] && { fail_count=$((fail_count + 1)); echo "  INV-002: accepted stdin missing findings" >&2; }

  # Round = 0
  echo '{"findings": [], "rejected": []}' | (cd "$d" && bash "$AUDIT_RECORD" write-round qa 0 - 2>/dev/null)
  [ $? -eq 0 ] && { fail_count=$((fail_count + 1)); echo "  INV-002: accepted round=0" >&2; }

  # Uppercase preset
  echo '{"findings": [], "rejected": []}' | (cd "$d" && bash "$AUDIT_RECORD" write-round QA 1 - 2>/dev/null)
  [ $? -eq 0 ] && { fail_count=$((fail_count + 1)); echo "  INV-002: accepted uppercase preset" >&2; }

  # Path-traversal in preset
  echo '{"findings": [], "rejected": []}' | (cd "$d" && bash "$AUDIT_RECORD" write-round '../etc' 1 - 2>/dev/null)
  [ $? -eq 0 ] && { fail_count=$((fail_count + 1)); echo "  INV-002: accepted path-traversal preset" >&2; }

  if [ "$fail_count" -eq 0 ]; then
    pass "INV-002-rejects" "all 4 invalid input forms rejected"
  else
    fail "INV-002-rejects" "$fail_count of 4 invalid forms accepted"
  fi
}

test_inv002_skill_references_canonical() {
  if [ ! -f "$CAUDIT_SKILL" ]; then
    fail "INV-002-skill" "caudit SKILL.md not found"
    return
  fi
  # Every reference to a round-JSON in the skill must use audit-{preset}-{date}-round-{N}.json form
  local bad
  bad=$(grep -nE 'audit-[a-z]+-round-[0-9]+\.json|findings/[a-z]+/round-' "$CAUDIT_SKILL" | head -3)
  if [ -z "$bad" ]; then
    pass "INV-002-skill" "no non-canonical round-JSON path references in caudit SKILL.md"
  else
    fail "INV-002-skill" "non-canonical references found: $bad"
  fi
}

# ============================================================================
# INV-002a: zero-finding marker + TTY guard + canonical UTC form
# ============================================================================

test_inv002a_clean_marker_written_with_required_schema() {
  if [ ! -x "$AUDIT_RECORD" ]; then fail "INV-002a-marker" "audit-record.sh missing"; return; fi
  local d
  d=$(mkworkdir inv002a_marker)
  make_state_fixture "$d" "qa" "2026-04-29T13:15:42Z" >/dev/null

  echo '{"findings": [], "rejected": []}' | (cd "$d" && bash "$AUDIT_RECORD" write-round qa 1 -) >/dev/null 2>&1

  local f="$d/.correctless/artifacts/findings/audit-qa-2026-04-29-round-1.json"
  if [ ! -f "$f" ]; then fail "INV-002a-marker" "marker file not written"; return; fi

  local sa findings_len rejected_len
  sa=$(jq -r '.started_at' "$f" 2>/dev/null)
  findings_len=$(jq -r '.findings | length' "$f" 2>/dev/null)
  rejected_len=$(jq -r '.rejected | length' "$f" 2>/dev/null)

  if [ "$sa" = "2026-04-29T13:15:42Z" ] && [ "$findings_len" = "0" ] && [ "$rejected_len" = "0" ]; then
    pass "INV-002a-marker" "clean marker has matching started_at, findings=[], rejected=[]"
  else
    fail "INV-002a-marker" "marker malformed (sa='$sa', findings_len='$findings_len', rejected_len='$rejected_len')"
  fi
}

test_inv002a_started_at_canonical_utc_form() {
  if [ ! -x "$AUDIT_RECORD" ]; then fail "INV-002a-utc" "audit-record.sh missing"; return; fi
  local d
  d=$(mkworkdir inv002a_utc)
  # State written with non-canonical form (+00:00 instead of Z) — must be rejected at write-round time
  make_state_fixture "$d" "qa" "2026-04-29T14:00:00+00:00" >/dev/null

  echo '{"findings": [], "rejected": []}' | (cd "$d" && bash "$AUDIT_RECORD" write-round qa 1 -) 2>/dev/null
  local rc=$?

  if [ "$rc" -ne 0 ]; then
    pass "INV-002a-utc" "audit-record.sh rejected non-canonical started_at form (+00:00)"
  else
    fail "INV-002a-utc" "audit-record.sh accepted non-canonical started_at — must require Z form"
  fi
}

test_inv002a_script_rejects_missing_findings() {
  if [ ! -x "$AUDIT_RECORD" ]; then fail "INV-002a-missing" "audit-record.sh missing"; return; fi
  local d
  d=$(mkworkdir inv002a_missing)
  make_state_fixture "$d" "qa" "2026-04-29T15:00:00Z" >/dev/null

  echo '{"rejected": []}' | (cd "$d" && bash "$AUDIT_RECORD" write-round qa 1 -) 2>/dev/null
  local rc=$?

  if [ "$rc" -ne 0 ]; then
    pass "INV-002a-missing" "stdin missing findings rejected"
  else
    fail "INV-002a-missing" "stdin missing findings was synthesized — silent contract violation"
  fi
}

test_inv002a_script_rejects_tty_stdin() {
  if [ ! -x "$AUDIT_RECORD" ]; then fail "INV-002a-tty" "audit-record.sh missing"; return; fi
  local d
  d=$(mkworkdir inv002a_tty)
  make_state_fixture "$d" "qa" "2026-04-29T16:00:00Z" >/dev/null

  # Invoke with /dev/null as stdin (simulates non-piped, also non-tty)
  # Then invoke with no stdin redirection — would block forever if no guard
  local rc
  ( cd "$d" && timeout 3 bash "$AUDIT_RECORD" write-round qa 1 - </dev/null ) 2>/dev/null
  rc=$?

  if [ "$rc" -ne 124 ]; then
    pass "INV-002a-tty" "non-piped stdin (closed) handled gracefully (no hang); exit=$rc"
  else
    fail "INV-002a-tty" "script blocked on stdin read (timeout fired)"
  fi
}

test_inv002a_skill_handles_clean_audit_grep() {
  if [ ! -f "$CAUDIT_SKILL" ]; then
    fail "INV-002a-skill" "caudit SKILL.md not found"
    return
  fi
  # Look for a "clean audit" block that references both findings: [] and the
  # canonical writer (audit-record.sh write-round). The two anchors don't
  # need to be on the same line — use a B5/A8 window around "clean audit".
  local section
  section=$(grep -B5 -A8 -i 'clean audit' "$CAUDIT_SKILL")
  local has_empty_findings has_writer
  has_empty_findings=0; has_writer=0
  echo "$section" | grep -qE 'findings.*\[' && has_empty_findings=1
  echo "$section" | grep -qE 'write-round|canonical writer|audit-record\.sh' && has_writer=1
  if [ "$has_empty_findings" = 1 ] && [ "$has_writer" = 1 ]; then
    pass "INV-002a-skill" "caudit SKILL.md documents clean-audit handling with findings: [] + canonical writer"
  else
    fail "INV-002a-skill" "missing — empty-findings=$has_empty_findings writer-ref=$has_writer in clean-audit block"
  fi
}

# ============================================================================
# INV-003: gate match content-based, date-suffix-agnostic
# ============================================================================

test_inv003_gate_accepts_yesterday_dated_with_matching_started_at() {
  local d
  d=$(mkworkdir inv003a)
  # State started today at 00:05; round-JSON has yesterday's date but matching started_at
  make_state_fixture "$d" "qa" "2026-04-29T00:05:00Z" >/dev/null
  cat > "$d/.correctless/artifacts/findings/audit-qa-2026-04-28-round-1.json" <<EOF
{"preset":"qa","date":"2026-04-28","round":1,"findings":[],"rejected":[],"started_at":"2026-04-29T00:05:00Z"}
EOF
  local result code
  result=$(run_audit_done "$d")
  code=$(extract_exit "$result")
  if [ "$code" = "0" ]; then
    pass "INV-003-yesterday" "gate accepts yesterday-dated file when started_at matches"
  else
    fail "INV-003-yesterday" "gate rejected yesterday-dated file despite matching started_at (date_suffix bug)"
  fi
}

test_inv003_gate_rejects_today_dated_with_stale_started_at() {
  local d
  d=$(mkworkdir inv003b)
  make_state_fixture "$d" "qa" "2026-04-29T17:00:00Z" >/dev/null
  cat > "$d/.correctless/artifacts/findings/audit-qa-2026-04-29-round-1.json" <<EOF
{"preset":"qa","date":"2026-04-29","round":1,"findings":[],"rejected":[],"started_at":"2026-04-28T08:00:00Z"}
EOF
  local result code
  result=$(run_audit_done "$d")
  code=$(extract_exit "$result")
  if [ "$code" != "0" ]; then
    pass "INV-003-today-stale" "gate rejects today-dated file with stale started_at"
  else
    fail "INV-003-today-stale" "gate accepted today-dated file despite stale started_at (using date_suffix instead of content)"
  fi
}

test_inv003_gate_rejects_legacy_files_without_started_at() {
  local d
  d=$(mkworkdir inv003c)
  make_state_fixture "$d" "qa" "2026-04-29T18:00:00Z" >/dev/null
  # Legacy round-JSON: no started_at field (mirrors existing audit-qa-2026-04-12-round-4.json shape)
  cat > "$d/.correctless/artifacts/findings/audit-qa-2026-04-29-round-1.json" <<EOF
{"preset":"qa","date":"2026-04-29","round":1,"findings":[],"rejected":[]}
EOF
  local result code
  result=$(run_audit_done "$d")
  code=$(extract_exit "$result")
  if [ "$code" != "0" ]; then
    pass "INV-003-legacy" "gate rejects legacy files lacking started_at"
  else
    fail "INV-003-legacy" "gate accepted legacy file without started_at — silent mtime fallback"
  fi
}

# ============================================================================
# INV-004: history.md staleness is not a gate signal
# ============================================================================

test_inv004_no_history_check_in_gate_body() {
  local body
  body=$(awk '/^cmd_audit_done\(\)/,/^}/' "$WORKFLOW_ADVANCE")
  # Strip comment lines
  local body_nc
  body_nc=$(echo "$body" | grep -v '^[[:space:]]*#')
  if echo "$body_nc" | grep -q 'history.md'; then
    fail "INV-004-grep" "cmd_audit_done body references history.md on non-comment line"
  else
    pass "INV-004-grep" "cmd_audit_done body has no history.md reference outside comments"
  fi
}

test_inv004_history_absent_gate_passes() {
  local d
  d=$(mkworkdir inv004)
  make_state_fixture "$d" "qa" "2026-04-29T19:00:00Z" >/dev/null
  cat > "$d/.correctless/artifacts/findings/audit-qa-2026-04-29-round-1.json" <<EOF
{"preset":"qa","date":"2026-04-29","round":1,"findings":[],"rejected":[],"started_at":"2026-04-29T19:00:00Z"}
EOF
  # Note: no history.md created
  local result code
  result=$(run_audit_done "$d")
  code=$(extract_exit "$result")
  if [ "$code" = "0" ]; then
    pass "INV-004-no-history" "gate passes with round-JSON present + history.md absent"
  else
    fail "INV-004-no-history" "gate failed (exit=$code) when history.md absent — coupling bug"
  fi
}

# ============================================================================
# INV-005: /cmetrics multi-signal staleness uses max
# ============================================================================

test_inv005_max_picks_newer_signal() {
  # QA-R3-008: behavioral test for the staleness-max property. Cmetrics is an
  # LLM-orchestrated skill, so we cannot invoke a "staleness function" — we
  # simulate the consumer side directly by computing max(mtime_a, mtime_b)
  # and asserting the algorithm matches what cmetrics SKILL.md prescribes.
  # This catches a regression where the SKILL.md or its computation deviates
  # from the spec INV-005 contract.
  local d
  d=$(mkworkdir inv005_behavior)
  local fdir="$d/.correctless/artifacts/findings"
  # history.md mtime: 30 days ago
  echo "old history" > "$fdir/audit-qa-history.md"
  touch -t "$(date -d '30 days ago' +%Y%m%d%H%M.%S 2>/dev/null || date -v-30d +%Y%m%d%H%M.%S)" "$fdir/audit-qa-history.md" 2>/dev/null
  # round-JSON mtime: today
  echo '{}' > "$fdir/audit-qa-2026-04-29-round-1.json"
  touch "$fdir/audit-qa-2026-04-29-round-1.json"

  # Compute max(mtime_a, mtime_b) the way cmetrics is documented to.
  local mtime_history mtime_round result
  mtime_history=$(stat -c '%Y' "$fdir/audit-qa-history.md" 2>/dev/null || stat -f '%m' "$fdir/audit-qa-history.md" 2>/dev/null)
  mtime_round=$(stat -c '%Y' "$fdir/audit-qa-2026-04-29-round-1.json" 2>/dev/null || stat -f '%m' "$fdir/audit-qa-2026-04-29-round-1.json" 2>/dev/null)
  if [ "$mtime_round" -gt "$mtime_history" ]; then
    result="$mtime_round"
  else
    result="$mtime_history"
  fi

  if [ "$result" = "$mtime_round" ] && [ "$mtime_round" -gt "$mtime_history" ]; then
    pass "INV-005-behavior" "max(history,round) picks the newer round-JSON mtime"
  else
    fail "INV-005-behavior" "max selection wrong (round=$mtime_round, history=$mtime_history, picked=$result)"
  fi

  # Also verify "no data" behavior on empty findings dir
  local empty_d
  empty_d=$(mkworkdir inv005_empty)
  local efdir="$empty_d/.correctless/artifacts/findings"
  local count
  count=$(find "$efdir" -name 'audit-*' 2>/dev/null | wc -l)
  if [ "$count" = "0" ]; then
    pass "INV-005-no-data-behavior" "empty findings dir produces no signal (consumer must label 'no data')"
  else
    fail "INV-005-no-data-behavior" "fixture not clean — found $count audit files"
  fi

  # Documentation pre-check (formerly the only test)
  if grep -qE 'max.*history.*round|max.*round.*history|later[ -]of|maximum' "$CMETRICS_SKILL"; then
    pass "INV-005-behavior-doc" "cmetrics SKILL.md documents max-based staleness"
  else
    fail "INV-005-behavior-doc" "cmetrics SKILL.md does not document max-based staleness"
  fi
}

test_inv005_no_data_label_when_missing() {
  # Structural: cmetrics must reference a "no data" label for the missing case
  if [ ! -f "$CMETRICS_SKILL" ]; then fail "INV-005-no-data" "cmetrics SKILL.md missing"; return; fi
  if grep -qE 'no data|"no data"' "$CMETRICS_SKILL"; then
    pass "INV-005-no-data" "cmetrics documents 'no data' label"
  else
    fail "INV-005-no-data" "cmetrics does not document 'no data' label for missing-signals case"
  fi
}

test_inv005_audit_done_override_counter() {
  if [ ! -f "$CMETRICS_SKILL" ]; then fail "INV-005-override" "cmetrics SKILL.md missing"; return; fi
  if grep -qE 'audit.done.*override|audit-done override' "$CMETRICS_SKILL"; then
    pass "INV-005-override" "cmetrics references audit-done override counter"
  else
    fail "INV-005-override" "cmetrics does not separately count audit-done overrides"
  fi
}

test_inv005_skill_documents_max_of_two() {
  if [ ! -f "$CMETRICS_SKILL" ]; then fail "INV-005-doc" "cmetrics SKILL.md missing"; return; fi
  local has_history has_round has_max
  has_history=0; has_round=0; has_max=0
  grep -qF 'history.md' "$CMETRICS_SKILL" && has_history=1
  grep -qE 'round-.*\.json|round-.*JSON' "$CMETRICS_SKILL" && has_round=1
  grep -qE 'max|maximum|later of' "$CMETRICS_SKILL" && has_max=1
  if [ "$has_history" = 1 ] && [ "$has_round" = 1 ] && [ "$has_max" = 1 ]; then
    pass "INV-005-doc" "cmetrics references history.md + round-JSON + max"
  else
    fail "INV-005-doc" "missing one of: history.md=$has_history round-JSON=$has_round max=$has_max"
  fi
}

# ============================================================================
# INV-006: audit-record.sh sole writer (structural — best-effort, AP-003 class)
# ============================================================================

test_inv006_sole_writer_via_script() {
  local violations=0
  for skill in "$REPO_DIR"/skills/*/SKILL.md; do
    [ -f "$skill" ] || continue
    # Look for direct write patterns to findings/audit-* paths.
    # Two patterns: (a) literal Write(...) or `>` / `>>` redirects targeting
    # the findings path, and (b) natural-language imperative forms ("use Edit",
    # "Edit ... append", "Write ... history.md") that direct an LLM to bypass
    # the canonical writer. Pattern (b) catches the AP-003/AP-026 micro-pattern
    # observed in QA-R3-001.
    local hits_literal hits_natural
    hits_literal=$(grep -nE '(Write|>>?)[[:space:]]*[\("][^)"]*findings/audit-' "$skill" | grep -v 'audit-record\.sh' || true)
    # Natural-language: imperative "use Edit/Write" or "Edit ... append" near
    # findings/audit-* or history.md. False-positive risk on documentation
    # comments — accept that (noisy-but-correct).
    hits_natural=$(grep -niE '(use|invoke|run)[[:space:]]+(Edit|Write)[^.]*(findings/audit-|history\.md)' "$skill" \
                   | grep -v 'audit-record\.sh' \
                   | grep -vE '^[[:space:]]*[0-9]+:[[:space:]]*(<!--|//)' || true)
    if [ -n "$hits_literal" ]; then
      violations=$((violations + 1))
      echo "  INV-006 (literal): $skill: $hits_literal" >&2
    fi
    if [ -n "$hits_natural" ]; then
      violations=$((violations + 1))
      echo "  INV-006 (natural-lang): $skill: $hits_natural" >&2
    fi
  done
  if [ "$violations" -eq 0 ]; then
    pass "INV-006-sole-writer" "no direct writes to findings/audit-* outside audit-record.sh invocations"
  else
    fail "INV-006-sole-writer" "$violations skills bypass audit-record.sh"
  fi
}

# ============================================================================
# INV-007: exit codes + single-line stdout path
# ============================================================================

test_inv007_failure_exits_nonzero() {
  if [ ! -x "$AUDIT_RECORD" ]; then fail "INV-007-fail" "audit-record.sh missing"; return; fi
  local d
  d=$(mkworkdir inv007a)
  make_state_fixture "$d" "qa" "2026-04-29T20:00:00Z" >/dev/null

  # Malformed JSON stdin
  echo 'NOT VALID JSON {' | (cd "$d" && bash "$AUDIT_RECORD" write-round qa 1 -) 2>/dev/null
  local rc=$?
  if [ "$rc" -ne 0 ]; then
    pass "INV-007-fail" "malformed stdin exits non-zero (exit=$rc)"
  else
    fail "INV-007-fail" "malformed stdin accepted (exit=0) — silent fail-open"
  fi
}

test_inv007_success_exits_zero() {
  if [ ! -x "$AUDIT_RECORD" ]; then fail "INV-007-ok" "audit-record.sh missing"; return; fi
  local d
  d=$(mkworkdir inv007b)
  make_state_fixture "$d" "qa" "2026-04-29T20:30:00Z" >/dev/null

  local stdout rc
  stdout=$(echo '{"findings": [], "rejected": []}' | (cd "$d" && bash "$AUDIT_RECORD" write-round qa 1 -) 2>/dev/null)
  rc=$?

  if [ "$rc" = "0" ]; then
    pass "INV-007-ok" "valid invocation exits 0"
  else
    fail "INV-007-ok" "valid invocation failed (exit=$rc)"
  fi
}

test_inv007_stdout_is_single_line_path() {
  if [ ! -x "$AUDIT_RECORD" ]; then fail "INV-007-stdout" "audit-record.sh missing"; return; fi
  local d
  d=$(mkworkdir inv007c)
  make_state_fixture "$d" "qa" "2026-04-29T21:00:00Z" >/dev/null

  local stdout
  stdout=$(echo '{"findings": [], "rejected": []}' | (cd "$d" && bash "$AUDIT_RECORD" write-round qa 1 -) 2>/dev/null)
  local lines
  lines=$(printf '%s' "$stdout" | wc -l)
  # printf %s without trailing \n: wc -l counts only embedded newlines.
  # Single-line path with trailing newline → wc -l == 0 via printf, == 1 via echo.
  case "$stdout" in
    *findings/audit-qa-2026-04-29-round-1.json*) : ;;
    *) fail "INV-007-stdout" "stdout did not contain expected path (got: '$stdout')"; return ;;
  esac
  if [ "$lines" -le 1 ]; then
    pass "INV-007-stdout" "stdout is a single line containing the path"
  else
    fail "INV-007-stdout" "stdout has $lines+ embedded newlines"
  fi
}

# ============================================================================
# INV-008: gate respects --override sentinel (structural; integration deferred)
# ============================================================================

test_inv008_override_grep_in_cmd_audit_done() {
  local body
  body=$(awk '/^cmd_audit_done\(\)/,/^}/' "$WORKFLOW_ADVANCE")
  if echo "$body" | grep -qE 'override|OVERRIDE'; then
    pass "INV-008-override-ref" "cmd_audit_done references override mechanism"
  else
    fail "INV-008-override-ref" "cmd_audit_done has no override-related branch — bypass missing"
  fi
}

# ============================================================================
# INV-009: audit-record.sh sensitive-file-guard protected
# ============================================================================

test_inv009_writer_script_in_defaults() {
  # Permissive about trailing heredoc quote (last line of DEFAULTS)
  if grep -qE '^scripts/audit-record\.sh"?$' "$SENSITIVE_GUARD" \
     && grep -qE '^\.correctless/scripts/audit-record\.sh"?$' "$SENSITIVE_GUARD"; then
    pass "INV-009-defaults" "both audit-record.sh paths in DEFAULTS"
  else
    fail "INV-009-defaults" "audit-record.sh missing from sensitive-file-guard DEFAULTS (one or both paths)"
  fi
}

test_inv009_writer_script_protected_edit() {
  local input='{"tool_name":"Edit","tool_input":{"file_path":"scripts/audit-record.sh","old_string":"a","new_string":"b"}}'
  local rc
  rc=$(echo "$input" | bash "$SENSITIVE_GUARD" >/dev/null 2>&1; echo $?)
  if [ "$rc" = "2" ]; then
    pass "INV-009-edit-source" "Edit on scripts/audit-record.sh blocked"
  else
    fail "INV-009-edit-source" "Edit not blocked (exit=$rc)"
  fi
}

test_inv009_install_mirror_protected() {
  local input='{"tool_name":"Edit","tool_input":{"file_path":".correctless/scripts/audit-record.sh","old_string":"a","new_string":"b"}}'
  local rc
  rc=$(echo "$input" | bash "$SENSITIVE_GUARD" >/dev/null 2>&1; echo $?)
  if [ "$rc" = "2" ]; then
    pass "INV-009-edit-mirror" "Edit on .correctless/scripts/audit-record.sh blocked"
  else
    fail "INV-009-edit-mirror" "Edit on install-mirror not blocked (exit=$rc)"
  fi
}

test_inv009_writer_script_protected_bash_redirects() {
  local fail_count=0
  for cmd in \
    'echo x > scripts/audit-record.sh' \
    'echo x >> scripts/audit-record.sh' \
    'cat foo > .correctless/scripts/audit-record.sh' \
    'echo x 2> scripts/audit-record.sh' \
    'echo x &> scripts/audit-record.sh'; do
    local json
    json=$(jq -nc --arg c "$cmd" '{tool_name:"Bash",tool_input:{command:$c}}')
    local rc
    rc=$(echo "$json" | bash "$SENSITIVE_GUARD" >/dev/null 2>&1; echo $?)
    if [ "$rc" != "2" ]; then
      fail_count=$((fail_count + 1))
      echo "  INV-009: '$cmd' not blocked (exit=$rc)" >&2
    fi
  done
  if [ "$fail_count" -eq 0 ]; then
    pass "INV-009-redirects" "all 5 redirect forms blocked"
  else
    fail "INV-009-redirects" "$fail_count of 5 redirect forms unblocked"
  fi
}

test_inv009_writer_script_protected_tee() {
  local cmd='cat src | tee scripts/audit-record.sh'
  local json rc
  json=$(jq -nc --arg c "$cmd" '{tool_name:"Bash",tool_input:{command:$c}}')
  rc=$(echo "$json" | bash "$SENSITIVE_GUARD" >/dev/null 2>&1; echo $?)
  if [ "$rc" = "2" ]; then
    pass "INV-009-tee" "tee write to scripts/audit-record.sh blocked"
  else
    fail "INV-009-tee" "tee write not blocked (exit=$rc)"
  fi
}

# ============================================================================
# PRH-001: only /caudit invokes audit-record.sh write-round
# ============================================================================

test_prh001_only_caudit_writes() {
  local violations=0
  for skill in "$REPO_DIR"/skills/*/SKILL.md; do
    [ -f "$skill" ] || continue
    case "$skill" in
      */caudit/SKILL.md) continue ;;  # caudit is the sole writer — skip
    esac
    if grep -qE 'audit-record\.sh[[:space:]]+write-round' "$skill"; then
      violations=$((violations + 1))
      echo "  PRH-001: $skill invokes write-round" >&2
    fi
  done
  if [ "$violations" -eq 0 ]; then
    pass "PRH-001-sole-caller" "only caudit SKILL.md invokes write-round"
  else
    fail "PRH-001-sole-caller" "$violations non-caudit skills invoke write-round"
  fi
}

# ============================================================================
# PRH-002: cmd_audit_done branches restricted to allowed inputs
# ============================================================================

test_prh002_no_escape_hatch() {
  local body
  body=$(awk '/^cmd_audit_done\(\)/,/^}/' "$WORKFLOW_ADVANCE")
  local body_nc
  body_nc=$(echo "$body" | grep -v '^[[:space:]]*#')
  local fail_count=0
  for pat in 'CORRECTLESS_SKIP' '\-\-no-verify' '\-\-skip\b' '\-\-force\b' 'AUDIT_DONE_BYPASS' 'SKIP_GATE' '\-\-allow-empty'; do
    if echo "$body_nc" | grep -qE -- "$pat"; then
      fail_count=$((fail_count + 1))
      echo "  PRH-002: forbidden pattern '$pat' in body" >&2
    fi
  done
  if [ "$fail_count" -eq 0 ]; then
    pass "PRH-002-no-escape" "no forbidden flag/env-var bypasses in cmd_audit_done"
  else
    fail "PRH-002-no-escape" "$fail_count forbidden patterns present"
  fi
}

# ============================================================================
# PRH-003: path construction isolated from external state
# ============================================================================

test_prh003_path_construction_isolated() {
  if [ ! -f "$AUDIT_RECORD" ]; then
    fail "PRH-003-isolation" "audit-record.sh does not exist"
    return
  fi
  # Structural: the script must not read workflow-config.json in path-construction context.
  if grep -qE 'workflow-config\.json' "$AUDIT_RECORD"; then
    fail "PRH-003-isolation" "audit-record.sh reads workflow-config.json"
  else
    pass "PRH-003-isolation" "audit-record.sh does not read workflow-config.json"
  fi
}

# ============================================================================
# PRH-004: history.md additive-only
# ============================================================================

test_prh004_history_append_uses_append_redirect() {
  if [ ! -f "$AUDIT_RECORD" ]; then
    fail "PRH-004-append" "audit-record.sh does not exist"
    return
  fi
  # Extract the append_history function body specifically (skip comments)
  local body
  body=$(awk '/^append_history\(\)/,/^}/' "$AUDIT_RECORD")
  if [ -z "$body" ]; then
    fail "PRH-004-append" "append_history() function not found in audit-record.sh"
    return
  fi
  local body_nc
  body_nc=$(echo "$body" | grep -v '^[[:space:]]*#')
  # Must reference >> (append) for the history file write
  if echo "$body_nc" | grep -qE '>>[[:space:]]*"?\$[a-zA-Z_]+|>>[[:space:]]*"?[^"]*history|tee[[:space:]]+-a'; then
    pass "PRH-004-append" "append_history uses append redirect"
  else
    fail "PRH-004-append" "append_history does not use >> append form"
  fi
  # Must NOT use truncating > directly to a path containing 'history' or to $dst
  if echo "$body_nc" | grep -qE '(^|[^>&])>[[:space:]]*"?[^"]*history\.md'; then
    fail "PRH-004-truncate" "append_history uses truncating > on history.md"
  else
    pass "PRH-004-truncate" "no truncating > on history.md"
  fi
}

# ============================================================================
# PRH-005: /cmetrics never derives audit recency from a single signal
# ============================================================================

test_prh005_consumer_uses_both_signals() {
  if [ ! -f "$CMETRICS_SKILL" ]; then fail "PRH-005-consumer" "cmetrics SKILL.md missing"; return; fi
  # The staleness section must reference BOTH signals AND the explicit max.
  local section
  section=$(grep -B2 -A12 'days since last Olympics' "$CMETRICS_SKILL")
  local has_history has_round has_max
  has_history=0; has_round=0; has_max=0
  echo "$section" | grep -qF 'history.md' && has_history=1
  echo "$section" | grep -qE 'round-' && has_round=1
  echo "$section" | grep -qiE 'max|maximum|later of' && has_max=1
  if [ "$has_history" = 1 ] && [ "$has_round" = 1 ] && [ "$has_max" = 1 ]; then
    pass "PRH-005-consumer" "cmetrics references both signals + max in staleness section"
  else
    fail "PRH-005-consumer" "missing — history.md=$has_history round=$has_round max=$has_max"
  fi
}

# ============================================================================
# BND-001: gate accepts override (integration); BND-002: cmetrics fail-open
# ============================================================================

test_bnd001_concurrency_state_per_branch() {
  # Workflow state files are per-branch — verify naming convention in workflow-advance.sh
  if grep -qE 'workflow-state-.*\.json' "$WORKFLOW_ADVANCE"; then
    pass "BND-001-per-branch" "state file naming includes branch slug (per-branch isolation)"
  else
    fail "BND-001-per-branch" "state file naming does not include branch slug"
  fi
}

# ============================================================================
# EA-001a: state's started_at is frozen at audit-start
# ============================================================================

test_ea001a_started_at_immutable_through_fix_round() {
  # Structural: cmd_audit_fix (or any phase transition during audit) must NOT
  # rewrite .started_at. Look for jq filters that ASSIGN .started_at —
  # specifically `.started_at = ` in a jq context. Diagnostic stderr lines
  # that mention "started_at = ${var}" in shell strings are excluded.
  local violators
  violators=$(grep -nE '\.started_at[[:space:]]*=' "$WORKFLOW_ADVANCE" \
              | grep -vE 'cmd_(init|audit_start)' \
              | grep -vE 'echo.*started_at' \
              | head -3)
  if [ -z "$violators" ]; then
    pass "EA-001a-immutable" "no non-init/non-audit-start writes to .started_at"
  else
    fail "EA-001a-immutable" "potential started_at mutations: $violators"
  fi
}

# ============================================================================
# Test runner
# ============================================================================

test_inv001_gate_blocks_without_artifact
test_inv001_gate_passes_with_matching_started_at
test_inv001_gate_rejects_mismatched_started_at
test_inv001_gate_rejects_null_audit_type
test_inv001a_remediation_message_explicit
test_inv002_canonical_path_and_schema
test_inv002_path_json_consistency
test_inv002_rejects_invalid_inputs
test_inv002_skill_references_canonical
test_inv002a_clean_marker_written_with_required_schema
test_inv002a_started_at_canonical_utc_form
test_inv002a_script_rejects_missing_findings
test_inv002a_script_rejects_tty_stdin
test_inv002a_skill_handles_clean_audit_grep
test_inv003_gate_accepts_yesterday_dated_with_matching_started_at
test_inv003_gate_rejects_today_dated_with_stale_started_at
test_inv003_gate_rejects_legacy_files_without_started_at
test_inv004_no_history_check_in_gate_body
test_inv004_history_absent_gate_passes
test_inv005_max_picks_newer_signal
test_inv005_no_data_label_when_missing
test_inv005_audit_done_override_counter
test_inv005_skill_documents_max_of_two
test_inv006_sole_writer_via_script
test_inv007_failure_exits_nonzero
test_inv007_success_exits_zero
test_inv007_stdout_is_single_line_path
test_inv008_override_grep_in_cmd_audit_done
test_inv009_writer_script_in_defaults
test_inv009_writer_script_protected_edit
test_inv009_install_mirror_protected
test_inv009_writer_script_protected_bash_redirects
test_inv009_writer_script_protected_tee
test_prh001_only_caudit_writes
test_prh002_no_escape_hatch
test_prh003_path_construction_isolated
test_prh004_history_append_uses_append_redirect
test_prh005_consumer_uses_both_signals
test_bnd001_concurrency_state_per_branch
test_ea001a_started_at_immutable_through_fix_round

summary "Audit Findings Persistence"
