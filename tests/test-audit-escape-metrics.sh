#!/usr/bin/env bash
# Correctless — Audit Escape Metrics Tests
# Spec: .correctless/specs/audit-escape-metrics.md
# Covers: R-001..R-010, INV-001..INV-004, PRH-001..PRH-002, BND-001..BND-002
# Run from repo root: bash tests/test-audit-escape-metrics.sh

source "$(dirname "${BASH_SOURCE[0]}")/test-helpers.sh"

AUDIT_RECORD="$REPO_DIR/scripts/audit-record.sh"
DASHBOARD_SCRIPT="$REPO_DIR/scripts/generate-dashboard.sh"
CMETRICS_SKILL="$REPO_DIR/skills/cmetrics/SKILL.md"
CAUDIT_SKILL="$REPO_DIR/skills/caudit/SKILL.md"
WORKFLOW_ADVANCE="$REPO_DIR/hooks/workflow-advance.sh"

# Test workspace
WORK_BASE="/tmp/correctless-aem-$$"
cleanup() { rm -rf "$WORK_BASE"; }
trap cleanup EXIT

mkworkdir() {
  local sub="$1"
  local d="$WORK_BASE/$sub"
  rm -rf "$d"
  mkdir -p "$d/.correctless/artifacts/findings" "$d/.correctless/scripts" \
           "$d/.correctless/config" "$d/hooks" "$d/scripts" "$d/docs"
  echo "$d"
}

# Build a real git repo workdir on an audit branch with the given preset and
# started_at, then write the workflow state file.
make_state_fixture() {
  local d="$1" preset="$2" started_at="$3"
  ( cd "$d" && \
    git init -q && \
    git branch -M main && \
    echo init > README.md && \
    git add -A && git commit -q -m init && \
    git checkout -q -b "audit/${preset}-2026-05-08" ) >/dev/null 2>&1
  local slug
  slug=$( cd "$d" && \
    bash -c 'source '"$REPO_DIR"'/scripts/lib.sh && branch_slug' )
  local sf="$d/.correctless/artifacts/workflow-state-${slug}.json"
  jq -n \
    --arg phase "audit" \
    --arg started_at "$started_at" \
    --arg phase_entered_at "$started_at" \
    --arg branch "audit/${preset}-2026-05-08" \
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

# ============================================================================
# R-001 [unit]: audit-record.sh write-round accepts escape_type field
# ============================================================================

section "R-001: escape_type field acceptance and validation"

# Tests R-001: escape_type is accepted in findings entries
test_r001_escape_type_accepted() {
  local d
  d=$(mkworkdir r001a)
  make_state_fixture "$d" "qa" "2026-05-08T10:00:00Z" >/dev/null

  local payload='{"findings": [{"id": "QA-001", "severity": "high", "escape_type": "implementation"}], "rejected": []}'
  local result
  result=$( cd "$d" && echo "$payload" | bash "$AUDIT_RECORD" write-round qa 1 - 2>&1 ) && code=0 || code=$?

  if [ "$code" = "0" ]; then
    pass "R-001-accept" "audit-record.sh write-round accepts findings with escape_type field"
  else
    fail "R-001-accept" "write-round rejected findings with escape_type (exit=$code): $result"
  fi
}

# Tests R-001: escape_type null or absent is accepted (defaults to unclassified)
test_r001_escape_type_absent() {
  local d
  d=$(mkworkdir r001b)
  make_state_fixture "$d" "qa" "2026-05-08T10:00:00Z" >/dev/null

  local payload='{"findings": [{"id": "QA-001", "severity": "high"}], "rejected": []}'
  local result
  result=$( cd "$d" && echo "$payload" | bash "$AUDIT_RECORD" write-round qa 1 - 2>&1 ) && code=0 || code=$?

  if [ "$code" = "0" ]; then
    pass "R-001-absent" "write-round accepts findings without escape_type"
  else
    fail "R-001-absent" "write-round rejected findings without escape_type (exit=$code)"
  fi
}

# Tests R-001: escape_type null explicitly is accepted
test_r001_escape_type_null() {
  local d
  d=$(mkworkdir r001c)
  make_state_fixture "$d" "qa" "2026-05-08T10:00:00Z" >/dev/null

  local payload='{"findings": [{"id": "QA-001", "severity": "high", "escape_type": null}], "rejected": []}'
  local result
  result=$( cd "$d" && echo "$payload" | bash "$AUDIT_RECORD" write-round qa 1 - 2>&1 ) && code=0 || code=$?

  if [ "$code" = "0" ]; then
    pass "R-001-null" "write-round accepts findings with escape_type: null"
  else
    fail "R-001-null" "write-round rejected escape_type: null (exit=$code)"
  fi
}

# Tests R-001: all three valid escape_type values accepted
test_r001_all_valid_values() {
  local d
  d=$(mkworkdir r001d)
  make_state_fixture "$d" "qa" "2026-05-08T10:00:00Z" >/dev/null

  local payload
  payload=$(jq -n '{
    findings: [
      {id: "QA-001", severity: "high", escape_type: "implementation"},
      {id: "QA-002", severity: "medium", escape_type: "spec"},
      {id: "QA-003", severity: "low", escape_type: "non-escape"}
    ],
    rejected: []
  }')
  local result
  result=$( cd "$d" && echo "$payload" | bash "$AUDIT_RECORD" write-round qa 1 - 2>&1 ) && code=0 || code=$?

  if [ "$code" = "0" ]; then
    pass "R-001-all-valid" "write-round accepts all three valid escape_type values"
  else
    fail "R-001-all-valid" "write-round rejected valid escape_type values (exit=$code)"
  fi
}

test_r001_escape_type_accepted
test_r001_escape_type_absent
test_r001_escape_type_null
test_r001_all_valid_values

# ============================================================================
# INV-002: escape_type vocabulary is closed — invalid values rejected
# ============================================================================

section "INV-002: escape_type vocabulary validation"

# Tests INV-002: invalid escape_type value is rejected with exit 1
test_inv002_invalid_escape_type_rejected() {
  local d
  d=$(mkworkdir inv002a)
  make_state_fixture "$d" "qa" "2026-05-08T10:00:00Z" >/dev/null

  local payload='{"findings": [{"id": "QA-001", "severity": "high", "escape_type": "bogus-value"}], "rejected": []}'
  local result
  result=$( cd "$d" && echo "$payload" | bash "$AUDIT_RECORD" write-round qa 1 - 2>&1 ) && code=0 || code=$?

  if [ "$code" != "0" ]; then
    pass "INV-002-reject" "write-round rejects invalid escape_type value (exit=$code)"
  else
    fail "INV-002-reject" "write-round accepted invalid escape_type 'bogus-value' — vocabulary check missing"
  fi
}

# Tests INV-002: entire payload rejected if ANY entry has invalid escape_type
test_inv002_whole_payload_rejected() {
  local d
  d=$(mkworkdir inv002b)
  make_state_fixture "$d" "qa" "2026-05-08T10:00:00Z" >/dev/null

  local payload
  payload=$(jq -n '{
    findings: [
      {id: "QA-001", severity: "high", escape_type: "implementation"},
      {id: "QA-002", severity: "medium", escape_type: "invalid-type"}
    ],
    rejected: []
  }')
  local result
  result=$( cd "$d" && echo "$payload" | bash "$AUDIT_RECORD" write-round qa 1 - 2>&1 ) && code=0 || code=$?

  if [ "$code" != "0" ]; then
    pass "INV-002-whole-reject" "entire payload rejected when one entry has invalid escape_type"
  else
    fail "INV-002-whole-reject" "payload accepted despite containing invalid escape_type entry"
  fi

  # Also verify no output file was written
  local expected="$d/.correctless/artifacts/findings/audit-qa-2026-05-08-round-1.json"
  if [ ! -f "$expected" ]; then
    pass "INV-002-no-file" "no round-JSON written on rejection"
  else
    fail "INV-002-no-file" "round-JSON was written despite rejection"
  fi
}

# Tests INV-002: error message is clear about the invalid value
test_inv002_error_message() {
  local d
  d=$(mkworkdir inv002c)
  make_state_fixture "$d" "qa" "2026-05-08T10:00:00Z" >/dev/null

  local payload='{"findings": [{"id": "QA-001", "severity": "high", "escape_type": "typo-value"}], "rejected": []}'
  local result stderr
  result=$( cd "$d" && echo "$payload" | bash "$AUDIT_RECORD" write-round qa 1 - 2>&1 >/dev/null ) && code=0 || code=$?
  stderr="$result"

  if echo "$stderr" | grep -qi "escape_type"; then
    pass "INV-002-errmsg" "error message references escape_type"
  else
    fail "INV-002-errmsg" "error message does not mention escape_type"
  fi
}

test_inv002_invalid_escape_type_rejected
test_inv002_whole_payload_rejected
test_inv002_error_message

# ============================================================================
# INV-001: escape_type field is additive and optional — consumers don't fail
# ============================================================================

section "INV-001: escape_type optional — consumers handle absent field"

# Tests INV-001: round-JSON without escape_type is valid for existing consumers
test_inv001_round_json_without_escape_type() {
  local d
  d=$(mkworkdir inv001a)
  make_state_fixture "$d" "qa" "2026-05-08T10:00:00Z" >/dev/null

  # Write a round-JSON without escape_type (pre-feature format)
  local payload='{"findings": [{"id": "QA-001", "severity": "high", "description": "test"}], "rejected": []}'
  local result
  result=$( cd "$d" && echo "$payload" | bash "$AUDIT_RECORD" write-round qa 1 - 2>&1 ) && code=0 || code=$?

  if [ "$code" = "0" ]; then
    pass "INV-001-no-escape-type" "round-JSON without escape_type is valid"
  else
    fail "INV-001-no-escape-type" "round-JSON without escape_type rejected (exit=$code)"
  fi
}

# Tests INV-001: mixed findings — some with escape_type, some without
test_inv001_mixed_findings() {
  local d
  d=$(mkworkdir inv001b)
  make_state_fixture "$d" "qa" "2026-05-08T10:00:00Z" >/dev/null

  local payload
  payload=$(jq -n '{
    findings: [
      {id: "QA-001", severity: "high", escape_type: "implementation"},
      {id: "QA-002", severity: "medium"},
      {id: "QA-003", severity: "low", escape_type: null}
    ],
    rejected: []
  }')
  local result
  result=$( cd "$d" && echo "$payload" | bash "$AUDIT_RECORD" write-round qa 1 - 2>&1 ) && code=0 || code=$?

  if [ "$code" = "0" ]; then
    pass "INV-001-mixed" "mixed findings (with/without/null escape_type) all accepted"
  else
    fail "INV-001-mixed" "mixed findings rejected (exit=$code)"
  fi
}

test_inv001_round_json_without_escape_type
test_inv001_mixed_findings

# ============================================================================
# R-002 [unit]: /cmetrics escape counts per audit cycle
# ============================================================================

section "R-002: cmetrics escape count computation"

# Tests R-002: cmetrics SKILL.md references escape count computation
test_r002_cmetrics_escape_count_section() {
  if ! grep -qi "escape.*count\|escape.*metric" "$CMETRICS_SKILL"; then
    fail "R-002-section" "cmetrics SKILL.md has no escape count/metrics section"
  else
    pass "R-002-section" "cmetrics SKILL.md references escape metrics"
  fi
}

# Tests R-002: escape count excludes info severity findings
test_r002_info_excluded_from_escape_count() {
  if ! grep -qi "info.*not counted\|info.*excluded\|severity.*info.*0\|info.*=.*0" "$CMETRICS_SKILL"; then
    fail "R-002-info-excluded" "cmetrics SKILL.md does not mention info exclusion from escape counts"
  else
    pass "R-002-info-excluded" "cmetrics SKILL.md mentions info findings excluded from escape counts"
  fi
}

# Tests R-002: cmetrics reads round-JSON from .correctless/artifacts/findings/
test_r002_reads_round_json() {
  if ! grep -q "artifacts/findings" "$CMETRICS_SKILL"; then
    fail "R-002-reads-findings" "cmetrics SKILL.md does not reference artifacts/findings directory"
  else
    pass "R-002-reads-findings" "cmetrics SKILL.md references artifacts/findings directory"
  fi
}

# Tests R-002: audit cycle is grouped by preset and date
test_r002_cycle_grouping() {
  if ! grep -qi "preset.*date\|audit.*cycle\|same.*preset.*date" "$CMETRICS_SKILL"; then
    fail "R-002-cycle-group" "cmetrics SKILL.md does not mention grouping by preset and date"
  else
    pass "R-002-cycle-group" "cmetrics SKILL.md mentions audit cycle grouping"
  fi
}

test_r002_cmetrics_escape_count_section
test_r002_info_excluded_from_escape_count
test_r002_reads_round_json
test_r002_cycle_grouping

# ============================================================================
# R-003 [unit]: severity-weighted escape score
# ============================================================================

section "R-003: severity-weighted escape score"

# Tests R-003: cmetrics defines weight mapping critical=5, high=3, medium=2, low=1, info=0
test_r003_weight_mapping() {
  local body
  body=$(skill_body "$CMETRICS_SKILL")

  local fail_count=0
  grep -qi "critical.*5\|critical.*=.*5" <<< "$body" || fail_count=$((fail_count + 1))
  grep -qi "high.*3\|high.*=.*3" <<< "$body" || fail_count=$((fail_count + 1))
  grep -qi "medium.*2\|medium.*=.*2" <<< "$body" || fail_count=$((fail_count + 1))
  grep -qi "low.*1\|low.*=.*1" <<< "$body" || fail_count=$((fail_count + 1))
  grep -qi "info.*0\|info.*=.*0" <<< "$body" || fail_count=$((fail_count + 1))

  if [ "$fail_count" -eq 0 ]; then
    pass "R-003-weights" "cmetrics defines all 5 severity weights"
  else
    fail "R-003-weights" "$fail_count of 5 severity weight mappings missing from cmetrics"
  fi
}

# Tests R-003 / INV-003: case-insensitive severity matching mentioned
test_r003_case_insensitive() {
  local body
  body=$(skill_body "$CMETRICS_SKILL")

  if grep -qi "case.insensitive\|lowercase\|normalize.*case" <<< "$body"; then
    pass "R-003-case" "cmetrics mentions case-insensitive severity matching"
  else
    fail "R-003-case" "cmetrics does not mention case-insensitive severity"
  fi
}

test_r003_weight_mapping
test_r003_case_insensitive

# ============================================================================
# R-004 [unit]: escape breakdown by root cause
# ============================================================================

section "R-004: root cause breakdown"

# Tests R-004: cmetrics reports implementation vs spec vs unclassified breakdown
test_r004_root_cause_breakdown() {
  local body
  body=$(skill_body "$CMETRICS_SKILL")

  local fail_count=0
  grep -qi "implementation.*escape\|escape.*implementation" <<< "$body" || fail_count=$((fail_count + 1))
  grep -qi "spec.*escape\|escape.*spec" <<< "$body" || fail_count=$((fail_count + 1))
  grep -qi "unclassified" <<< "$body" || fail_count=$((fail_count + 1))

  if [ "$fail_count" -eq 0 ]; then
    pass "R-004-breakdown" "cmetrics references all three root cause categories"
  else
    fail "R-004-breakdown" "$fail_count of 3 root cause categories missing from cmetrics"
  fi
}

# Tests R-004: breakdown uses escape_type field from round-JSON
test_r004_uses_escape_type_field() {
  local body
  body=$(skill_body "$CMETRICS_SKILL")

  if grep -qi "escape_type" <<< "$body"; then
    pass "R-004-field" "cmetrics references escape_type field"
  else
    fail "R-004-field" "cmetrics does not reference escape_type field"
  fi
}

test_r004_root_cause_breakdown
test_r004_uses_escape_type_field

# ============================================================================
# R-005 [unit]: three-gate escape rate breakdown
# ============================================================================

section "R-005: three-gate escape rate"

# Tests R-005: cmetrics shows per-feature, audit, and production escape gates
test_r005_three_gates() {
  local body
  body=$(skill_body "$CMETRICS_SKILL")

  local fail_count=0
  grep -qi "per.feature.*escape\|per-feature.*escape" <<< "$body" || fail_count=$((fail_count + 1))
  grep -qi "audit.*escape" <<< "$body" || fail_count=$((fail_count + 1))
  grep -qi "production.*escape" <<< "$body" || fail_count=$((fail_count + 1))

  if [ "$fail_count" -eq 0 ]; then
    pass "R-005-gates" "cmetrics defines all three escape gates"
  else
    fail "R-005-gates" "$fail_count of 3 escape gates missing from cmetrics"
  fi
}

# Tests R-005: per-feature escapes derived from qa-findings BLOCKING count
test_r005_per_feature_from_qa_findings() {
  local body
  body=$(skill_body "$CMETRICS_SKILL")

  if grep -qi "qa-findings.*BLOCKING\|BLOCKING.*qa-findings\|per-feature.*qa-findings\|qa-findings.*per.feature" <<< "$body"; then
    pass "R-005-qa-source" "cmetrics derives per-feature escapes from qa-findings BLOCKING count"
  else
    fail "R-005-qa-source" "cmetrics does not link per-feature escapes to qa-findings BLOCKING"
  fi
}

# Tests R-005: production escapes from workflow-effectiveness.json unchanged
test_r005_production_source() {
  local body
  body=$(skill_body "$CMETRICS_SKILL")

  if grep -qi "post_merge_bugs\|workflow-effectiveness" <<< "$body"; then
    pass "R-005-prod-source" "cmetrics still uses workflow-effectiveness.json for production escapes"
  else
    fail "R-005-prod-source" "cmetrics missing reference to workflow-effectiveness.json"
  fi
}

test_r005_three_gates
test_r005_per_feature_from_qa_findings
test_r005_production_source

# ============================================================================
# R-006 [unit]: escape trends across audit cycles
# ============================================================================

section "R-006: escape trend tracking"

# Tests R-006: cmetrics computes trend (improving/stable/regressing)
test_r006_trend_categories() {
  local body
  body=$(skill_body "$CMETRICS_SKILL")

  local fail_count=0
  grep -qi "improving" <<< "$body" || fail_count=$((fail_count + 1))
  grep -qi "stable" <<< "$body" || fail_count=$((fail_count + 1))
  grep -qi "regressing" <<< "$body" || fail_count=$((fail_count + 1))

  if [ "$fail_count" -eq 0 ]; then
    pass "R-006-trends" "cmetrics defines all three trend categories"
  else
    fail "R-006-trends" "$fail_count of 3 trend categories missing from cmetrics"
  fi
}

# Tests R-006: 20% threshold for stable vs regressing
test_r006_threshold() {
  local body
  body=$(skill_body "$CMETRICS_SKILL")

  if grep -qi "20%\|20 *percent" <<< "$body"; then
    pass "R-006-threshold" "cmetrics mentions 20% threshold for trend classification"
  else
    fail "R-006-threshold" "cmetrics missing 20% threshold for trend"
  fi
}

# Tests R-006 / BND-002: insufficient data handling
test_r006_insufficient_data() {
  local body
  body=$(skill_body "$CMETRICS_SKILL")

  if grep -qi "insufficient.*data.*trend\|fewer.*than.*2.*cycle" <<< "$body"; then
    pass "R-006-insufficient" "cmetrics handles insufficient data for trend computation"
  else
    fail "R-006-insufficient" "cmetrics missing insufficient data handling for trends"
  fi
}

test_r006_trend_categories
test_r006_threshold
test_r006_insufficient_data

# ============================================================================
# R-007 [unit]: severity distribution per audit cycle
# ============================================================================

section "R-007: severity distribution"

# Tests R-007: cmetrics reports severity distribution table
test_r007_severity_distribution() {
  local body
  body=$(skill_body "$CMETRICS_SKILL")

  if grep -qi "severity.*distribution\|distribution.*severity" <<< "$body"; then
    pass "R-007-distribution" "cmetrics references severity distribution"
  else
    fail "R-007-distribution" "cmetrics missing severity distribution section"
  fi
}

# Tests R-007: distribution shift from previous cycle
test_r007_shift() {
  local body
  body=$(skill_body "$CMETRICS_SKILL")

  if grep -qi "shift.*previous\|previous.*cycle\|distribution.*shift" <<< "$body"; then
    pass "R-007-shift" "cmetrics mentions distribution shift from previous cycle"
  else
    fail "R-007-shift" "cmetrics missing distribution shift comparison"
  fi
}

test_r007_severity_distribution
test_r007_shift

# ============================================================================
# R-008 [unit]: dormant escape metrics follow PAT-019
# ============================================================================

section "R-008: dormant behavior when no round-JSON exists"

# Tests R-008 / INV-004: escape metrics section omitted when no audit data
test_r008_dormant() {
  local body
  body=$(skill_body "$CMETRICS_SKILL")

  if grep -qi "dormant\|omit.*no.*round\|no.*audit.*data.*skip\|PAT-019" <<< "$body"; then
    pass "R-008-dormant" "cmetrics mentions dormant behavior for escape metrics"
  else
    fail "R-008-dormant" "cmetrics missing dormant behavior specification for escape metrics"
  fi
}

test_r008_dormant

# ============================================================================
# R-009 [unit]: dashboard escape metrics section reads cmetrics artifact
# ============================================================================

section "R-009: dashboard escape metrics section"

# Tests R-009: generate-dashboard.sh references escape metrics or metrics artifact
test_r009_dashboard_reads_metrics() {
  if grep -qi "escape.*metric\|metrics-.*\.md\|escape.*section" "$DASHBOARD_SCRIPT"; then
    pass "R-009-dashboard" "generate-dashboard.sh references escape metrics"
  else
    fail "R-009-dashboard" "generate-dashboard.sh has no escape metrics section"
  fi
}

# Tests R-009: dashboard dormant when no metrics artifact
test_r009_dashboard_dormant() {
  if grep -qi "dormant\|no.*metrics\|omit\|skip.*metric" "$DASHBOARD_SCRIPT"; then
    pass "R-009-dormant" "generate-dashboard.sh handles missing metrics gracefully"
  else
    fail "R-009-dormant" "generate-dashboard.sh missing dormant handling for escape metrics"
  fi
}

test_r009_dashboard_reads_metrics
test_r009_dashboard_dormant

# ============================================================================
# R-010 [unit]: /caudit specialist agent includes escape_type
# ============================================================================

section "R-010: caudit escape_type classification"

# Tests R-010: caudit SKILL.md references escape_type in agent finding submission
test_r010_caudit_escape_type() {
  local body
  body=$(skill_body "$CAUDIT_SKILL")

  if grep -qi "escape_type" <<< "$body"; then
    pass "R-010-escape-type" "caudit SKILL.md references escape_type"
  else
    fail "R-010-escape-type" "caudit SKILL.md does not mention escape_type"
  fi
}

# Tests R-010: caudit references implementation/spec/non-escape values
test_r010_classification_values() {
  local body
  body=$(skill_body "$CAUDIT_SKILL")

  local fail_count=0
  grep -qi "implementation" <<< "$body" || fail_count=$((fail_count + 1))
  grep -qi "non-escape\|non.escape" <<< "$body" || fail_count=$((fail_count + 1))

  if [ "$fail_count" -eq 0 ]; then
    pass "R-010-values" "caudit references escape_type classification values"
  else
    fail "R-010-values" "$fail_count of 2 escape_type values missing from caudit"
  fi
}

# Tests R-010: triage agent validates escape_type classification
test_r010_triage_validates() {
  local body
  body=$(skill_body "$CAUDIT_SKILL")

  if grep -qi "triage.*escape_type\|escape_type.*triage\|validate.*classification\|triage.*validate" <<< "$body"; then
    pass "R-010-triage" "caudit mentions triage validation of escape_type"
  else
    fail "R-010-triage" "caudit missing triage agent escape_type validation"
  fi
}

# Tests R-010: classification is per-finding at submission time
test_r010_per_finding() {
  local body
  body=$(skill_body "$CAUDIT_SKILL")

  if grep -qi "per.finding\|per finding\|submission.*time\|distributed.*across" <<< "$body"; then
    pass "R-010-per-finding" "caudit specifies per-finding classification"
  else
    fail "R-010-per-finding" "caudit missing per-finding classification requirement"
  fi
}

test_r010_caudit_escape_type
test_r010_classification_values
test_r010_triage_validates
test_r010_per_finding

# ============================================================================
# PRH-001: escape_type must not gate phase transitions
# ============================================================================

section "PRH-001: escape_type not in workflow-advance.sh"

# Tests PRH-001: workflow-advance.sh has no reference to escape_type
test_prh001_no_escape_type_in_gate() {
  if grep -q "escape_type" "$WORKFLOW_ADVANCE"; then
    fail "PRH-001-gate" "workflow-advance.sh references escape_type — PRH-001 violated"
  else
    pass "PRH-001-gate" "workflow-advance.sh has zero references to escape_type"
  fi
}

test_prh001_no_escape_type_in_gate

# ============================================================================
# PRH-002: escape metrics must not feed into intensity auto-adjustment
# ============================================================================

section "PRH-002: escape data not in intensity signals"

# Tests PRH-002: cspec SKILL.md intensity section has no escape references
test_prh002_no_escape_in_cspec() {
  local cspec_skill="$REPO_DIR/skills/cspec/SKILL.md"
  if [ ! -f "$cspec_skill" ]; then
    skip "PRH-002-cspec" "cspec SKILL.md not found"
    return
  fi

  # Look for escape references in the intensity detection / signal context
  local body
  body=$(skill_body "$cspec_skill")

  # Extract the intensity section (rough heuristic: between "intensity" headers)
  if grep -qi "intensity.*escape\|escape.*intensity\|escape.*signal\|escape.*auto.adjust" <<< "$body"; then
    fail "PRH-002-cspec" "cspec intensity section references escape data"
  else
    pass "PRH-002-cspec" "cspec intensity section has no escape references"
  fi
}

# Tests PRH-002: intensity-calibration.json schema has no escape fields
test_prh002_no_escape_in_calibration() {
  local cal_file="$REPO_DIR/.correctless/meta/intensity-calibration.json"
  if [ ! -f "$cal_file" ]; then
    skip "PRH-002-cal" "intensity-calibration.json not found"
    return
  fi

  if grep -qi "escape" "$cal_file"; then
    fail "PRH-002-cal" "intensity-calibration.json contains escape references"
  else
    pass "PRH-002-cal" "intensity-calibration.json has no escape references"
  fi
}

test_prh002_no_escape_in_cspec
test_prh002_no_escape_in_calibration

# ============================================================================
# BND-001: mixed-vintage round-JSON files (pre/post escape_type)
# ============================================================================

section "BND-001: mixed-vintage round-JSON compatibility"

# Tests BND-001: write-round succeeds for payloads without escape_type
# (backward compatibility — pre-feature format)
test_bnd001_pre_feature_format() {
  local d
  d=$(mkworkdir bnd001a)
  make_state_fixture "$d" "qa" "2026-05-08T10:00:00Z" >/dev/null

  local payload='{"findings": [{"id": "QA-001", "severity": "critical", "tier": "confirmed", "agent": "concurrency"}], "rejected": []}'
  local result
  result=$( cd "$d" && echo "$payload" | bash "$AUDIT_RECORD" write-round qa 1 - 2>&1 ) && code=0 || code=$?

  if [ "$code" = "0" ]; then
    pass "BND-001-pre-feature" "pre-feature round-JSON format accepted"
  else
    fail "BND-001-pre-feature" "pre-feature format rejected (exit=$code)"
  fi
}

# Tests BND-001: escape_type field preserved in output when provided
test_bnd001_escape_type_preserved() {
  local d
  d=$(mkworkdir bnd001b)
  make_state_fixture "$d" "qa" "2026-05-08T10:00:00Z" >/dev/null

  local payload='{"findings": [{"id": "QA-001", "severity": "high", "escape_type": "spec"}], "rejected": []}'
  ( cd "$d" && echo "$payload" | bash "$AUDIT_RECORD" write-round qa 1 - >/dev/null 2>&1 ) || true

  local outfile="$d/.correctless/artifacts/findings/audit-qa-2026-05-08-round-1.json"
  if [ -f "$outfile" ]; then
    local et
    et=$(jq -r '.findings[0].escape_type // "MISSING"' "$outfile")
    if [ "$et" = "spec" ]; then
      pass "BND-001-preserved" "escape_type field preserved in output"
    else
      fail "BND-001-preserved" "escape_type not preserved (got: $et)"
    fi
  else
    fail "BND-001-preserved" "output file not found"
  fi
}

test_bnd001_pre_feature_format
test_bnd001_escape_type_preserved

# ============================================================================
# INV-003: severity weight mapping is deterministic
# ============================================================================

section "INV-003: deterministic severity weights"

# Tests INV-003: weight values are explicitly documented in cmetrics
test_inv003_explicit_weights() {
  local body
  body=$(skill_body "$CMETRICS_SKILL")

  # Verify each weight appears exactly with its expected numeric value
  local ok=true
  grep -qi "critical.*5" <<< "$body" || ok=false
  grep -qi "high.*3" <<< "$body" || ok=false
  grep -qi "medium.*2" <<< "$body" || ok=false
  grep -qi "low.*1" <<< "$body" || ok=false

  if [ "$ok" = "true" ]; then
    pass "INV-003-explicit" "all severity weights explicitly documented"
  else
    fail "INV-003-explicit" "some severity weights missing from cmetrics"
  fi
}

test_inv003_explicit_weights

# ============================================================================
# INV-004: dormant escape metrics follow PAT-019
# ============================================================================

section "INV-004: escape metrics dormant behavior"

# Tests INV-004: cmetrics omits section when no round-JSON (not error)
test_inv004_no_error_on_empty() {
  local body
  body=$(skill_body "$CMETRICS_SKILL")

  # Must say no error/warning when no data
  if grep -qi "no.*error\|no.*warning\|omit.*entirely\|dormant\|PAT-019" <<< "$body"; then
    pass "INV-004-dormant" "cmetrics specifies dormant behavior (no error on empty)"
  else
    fail "INV-004-dormant" "cmetrics missing dormant specification"
  fi
}

test_inv004_no_error_on_empty

# ============================================================================
# Summary
# ============================================================================

summary "Audit Escape Metrics"
