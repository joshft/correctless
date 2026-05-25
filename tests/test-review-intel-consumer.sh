#!/usr/bin/env bash
# Correctless — Review Intelligence Consumer test suite
# Tests spec rules INV-001 through INV-011, PRH-001 through PRH-002,
# BND-001 through BND-003 from
# .correctless/specs/review-intelligence-consumer.md
#
# RED phase: these tests MUST FAIL — implementation does not exist yet.
# Run from repo root: bash tests/test-review-intel-consumer.sh

source "$(dirname "${BASH_SOURCE[0]}")/test-helpers.sh"

# ============================================================================
# Constants
# ============================================================================

SCRIPTS_DIR="$REPO_DIR/scripts"
SKILLS_DIR="$REPO_DIR/skills"
INTEL_SCRIPT="$SCRIPTS_DIR/cross-feature-intel.sh"
CREVIEW_SPEC_SKILL="$SKILLS_DIR/creview-spec/SKILL.md"
CREVIEW_SKILL="$SKILLS_DIR/creview/SKILL.md"
CSTATUS_SKILL="$SKILLS_DIR/cstatus/SKILL.md"
ARCHITECTURE_DOC="$REPO_DIR/.correctless/ARCHITECTURE.md"

# Agent definition files
AGENT_RED_TEAM="$REPO_DIR/agents/review-spec-red-team.md"
AGENT_ASSUMPTIONS="$REPO_DIR/agents/review-spec-assumptions.md"
AGENT_TESTABILITY="$REPO_DIR/agents/review-spec-testability.md"
AGENT_DESIGN_CONTRACT="$REPO_DIR/agents/review-spec-design-contract.md"
AGENT_UPGRADE_COMPAT="$REPO_DIR/agents/review-spec-upgrade-compat.md"
AGENT_UX="$REPO_DIR/agents/review-spec-ux.md"

# Test workspace
WORK_BASE="/tmp/correctless-ric-$$"
cleanup() { rm -rf "$WORK_BASE"; }
trap cleanup EXIT

mkworkdir() {
  local sub="$1"
  local d="$WORK_BASE/$sub"
  rm -rf "$d"
  mkdir -p "$d"
  echo "$d"
}

# Helper: run cross-feature-intel.sh with --base and optional extra args
run_intel() {
  local base="$1"; shift
  bash "$INTEL_SCRIPT" --base "$base/.correctless" "$@" 2>&1
}

# Helper: create a fixture directory with data source directories
setup_fixture_dirs() {
  local base="$1"
  mkdir -p "$base/.correctless/meta/overrides"
  mkdir -p "$base/.correctless/artifacts/devadv"
}

# Helper: write a brief fixture with entries at various occurrence counts
write_brief_fixture() {
  local filepath="$1"
  local dir
  dir=$(dirname "$filepath")
  mkdir -p "$dir"
  cat > "$filepath" << 'FIXTURE'
{
  "schema_version": 1,
  "generated_at": "2026-05-22T10:00:00Z",
  "scope": [],
  "truncated_count": 0,
  "warnings": [],
  "sections": {
    "deferred_findings": [
      {
        "id": "DF-001",
        "date": "2026-05-20",
        "summary": "Missing validation on auth endpoint",
        "file_refs": [],
        "severity": "HIGH",
        "source": "deferred-findings.json",
        "occurrences": 5
      },
      {
        "id": "DF-002",
        "date": "2026-05-18",
        "summary": "Stale CDN reference",
        "file_refs": [],
        "severity": "MEDIUM",
        "source": "deferred-findings.json",
        "occurrences": 2
      }
    ],
    "devadv_themes": [
      {
        "id": "DA-001",
        "date": "2026-05-15",
        "summary": "Complexity outpacing maintainer",
        "file_refs": [],
        "severity": "HIGH",
        "source": "report-2026-05-15.md",
        "occurrences": 3
      }
    ],
    "override_patterns": [],
    "lens_recommendations": [],
    "debug_clusters": [],
    "phase_effectiveness": []
  }
}
FIXTURE
}

# Helper: write a brief fixture with NO occurrences field (pre-tracking era)
write_brief_fixture_no_occurrences() {
  local filepath="$1"
  local dir
  dir=$(dirname "$filepath")
  mkdir -p "$dir"
  cat > "$filepath" << 'FIXTURE'
{
  "schema_version": 1,
  "generated_at": "2026-05-22T10:00:00Z",
  "scope": [],
  "truncated_count": 0,
  "warnings": [],
  "sections": {
    "deferred_findings": [
      {
        "id": "DF-001",
        "date": "2026-05-20",
        "summary": "Missing validation on auth endpoint",
        "file_refs": [],
        "severity": "HIGH",
        "source": "deferred-findings.json"
      }
    ],
    "devadv_themes": [],
    "override_patterns": [],
    "lens_recommendations": [],
    "debug_clusters": [],
    "phase_effectiveness": []
  }
}
FIXTURE
}

# Helper: write deferred findings fixture for behavioral tests
write_deferred_findings() {
  local base="$1"
  mkdir -p "$base/.correctless/meta"
  cat > "$base/.correctless/meta/deferred-findings.json" << 'FIXTURE'
{
  "schema_version": 1,
  "findings": [
    {
      "id": "DF-001",
      "source_file": ".correctless/artifacts/review-spec-findings-foo.md",
      "finding_id": "RS-001",
      "feature": "foo",
      "severity": "HIGH",
      "description": "Missing validation on auth endpoint",
      "category": "review",
      "status": "open",
      "deferred_at": "2026-05-20T12:00:00Z",
      "resolved_at": null,
      "resolution": null
    },
    {
      "id": "DF-002",
      "source_file": ".correctless/artifacts/review-spec-findings-bar.md",
      "finding_id": "RS-002",
      "feature": "bar",
      "severity": "MEDIUM",
      "description": "Stale CDN reference in dashboard",
      "category": "review",
      "status": "open",
      "deferred_at": "2026-05-18T10:00:00Z",
      "resolved_at": null,
      "resolution": null
    }
  ]
}
FIXTURE
}

# ============================================================================
# INV-001: Review orchestrators read the intelligence brief file
# ============================================================================

section "INV-001: Review orchestrators read the intelligence brief file"

# Tests INV-001 [unit]: /creview-spec SKILL.md contains a jq read of cross-feature-intel.json
if grep -q 'cross-feature-intel\.json' "$CREVIEW_SPEC_SKILL" \
   && grep -q 'jq' "$CREVIEW_SPEC_SKILL" \
   && grep -q 'cross-feature-intel\.json' <(grep -A2 'jq\|Bash(' "$CREVIEW_SPEC_SKILL"); then
  pass "INV-001a" "/creview-spec has jq-based read of cross-feature-intel.json"
else
  fail "INV-001a" "/creview-spec must have jq-based read of cross-feature-intel.json"
fi

# Tests INV-001 [unit]: /creview SKILL.md contains a jq read of cross-feature-intel.json
if grep -q 'cross-feature-intel\.json' "$CREVIEW_SKILL" \
   && grep -q 'jq' "$CREVIEW_SKILL" \
   && grep -q 'cross-feature-intel\.json' <(grep -A2 'jq\|Bash(' "$CREVIEW_SKILL"); then
  pass "INV-001b" "/creview has jq-based read of cross-feature-intel.json"
else
  fail "INV-001b" "/creview must have jq-based read of cross-feature-intel.json"
fi

# Tests INV-001 [unit]: both skills reference occurrences >= 3 filter
if grep -q 'occurrences.*3\|occurrences >= 3\|\.occurrences.*>= *3' "$CREVIEW_SPEC_SKILL"; then
  pass "INV-001c" "/creview-spec has occurrences >= 3 filter"
else
  fail "INV-001c" "/creview-spec must have occurrences >= 3 filter"
fi

if grep -q 'occurrences.*3\|occurrences >= 3\|\.occurrences.*>= *3' "$CREVIEW_SKILL"; then
  pass "INV-001d" "/creview has occurrences >= 3 filter"
else
  fail "INV-001d" "/creview must have occurrences >= 3 filter"
fi

# ============================================================================
# INV-002: 3-occurrence threshold dampener (script-side --min-occurrences)
# ============================================================================

section "INV-002: 3-occurrence threshold dampener"

# Tests INV-002 [unit]: script accepts --min-occurrences flag
if grep -q '\-\-min-occurrences' "$INTEL_SCRIPT"; then
  pass "INV-002a" "Script accepts --min-occurrences flag"
else
  fail "INV-002a" "Script must accept --min-occurrences flag"
fi

# Tests INV-002 [behavioral]: --min-occurrences filters stdout, not on-disk file
# Strategy: run twice to get occurrences=2, then check that --min-occurrences 3
# filters those entries out while --min-occurrences 1 keeps them
wd=$(mkworkdir "inv002-filter")
setup_fixture_dirs "$wd"
write_deferred_findings "$wd"

# Run the script twice to build occurrence counts to 2
run_intel "$wd" > /dev/null 2>&1   # run 1: occurrences=1
run_intel "$wd" > /dev/null 2>&1   # run 2: occurrences=2

# Check disk state: entries should have occurrences=2
disk_occ=$(jq '[.sections | to_entries[] | .value[] | .occurrences // 0] | max // 0' "$wd/.correctless/meta/cross-feature-intel.json" 2>/dev/null)

# Run with --min-occurrences 99: entries at 3 (incremented by this run) still < 99
filtered_high=$(run_intel "$wd" --min-occurrences 99 2>&1)
high_count=$(echo "$filtered_high" | jq '[.sections | to_entries[] | .value[] | select(true)] | length' 2>/dev/null)

# Run with --min-occurrences 1: all entries at 5 (incremented again) should pass
filtered_low=$(run_intel "$wd" --min-occurrences 1 2>&1)
low_count=$(echo "$filtered_low" | jq '[.sections | to_entries[] | .value[] | select(true)] | length' 2>/dev/null)

if [ "$high_count" = "0" ] && [ "$low_count" -gt 0 ] 2>/dev/null; then
  pass "INV-002b" "--min-occurrences filters stdout to entries >= N"
else
  fail "INV-002b" "--min-occurrences must filter stdout to entries >= N (high_count=$high_count, low_count=$low_count, disk_occ=$disk_occ)"
fi

# Verify the on-disk file still has ALL entries regardless of --min-occurrences
if [ -f "$wd/.correctless/meta/cross-feature-intel.json" ]; then
  ondisk_total=$(jq '[.sections | to_entries[] | .value | length] | add // 0' "$wd/.correctless/meta/cross-feature-intel.json" 2>/dev/null)
  if [ "$ondisk_total" -gt 0 ] 2>/dev/null; then
    pass "INV-002b2" "On-disk file retains all entries regardless of --min-occurrences"
  else
    fail "INV-002b2" "On-disk file must retain all entries (found $ondisk_total)"
  fi
else
  fail "INV-002b2" "On-disk brief file must exist after --min-occurrences run"
fi

# Tests INV-002 [behavioral]: entries missing occurrences field treated as below threshold
wd2=$(mkworkdir "inv002-missing-occ")
setup_fixture_dirs "$wd2"
write_deferred_findings "$wd2"
write_brief_fixture_no_occurrences "$wd2/.correctless/meta/cross-feature-intel.json"

# The consumer-side filter (in review skills) treats missing occurrences as 0 (below threshold)
# We test the script-side: --min-occurrences should exclude entries without occurrences field
# First regenerate so the script processes the brief (adding occurrence tracking)
run_intel "$wd2" > /dev/null 2>&1
# Then filter with --min-occurrences 3
filtered_no_occ=$(bash "$INTEL_SCRIPT" --base "$wd2/.correctless" --min-occurrences 3 2>&1)
if echo "$filtered_no_occ" | jq -e '.' >/dev/null 2>&1; then
  # After one regeneration from pre-occurrence era, entries should be at occurrences=1
  # So --min-occurrences 3 should produce empty sections
  non_empty=$(echo "$filtered_no_occ" | jq '[.sections | to_entries[] | .value[] | select(true)] | length' 2>/dev/null)
  if [ "$non_empty" = "0" ] 2>/dev/null; then
    pass "INV-002c" "Entries seeded from pre-occurrence era excluded by --min-occurrences 3"
  else
    fail "INV-002c" "Entries seeded from pre-occurrence era must be excluded by --min-occurrences 3 (found $non_empty)"
  fi
else
  fail "INV-002c" "Script must produce valid JSON even with --min-occurrences on migrated data"
fi

# ============================================================================
# INV-003: Agents never see the brief
# ============================================================================

section "INV-003: Agents never see the brief"

# Tests INV-003 [unit]: No agent definition file references cross-feature-intel
agent_files=(
  "$AGENT_RED_TEAM"
  "$AGENT_ASSUMPTIONS"
  "$AGENT_TESTABILITY"
  "$AGENT_DESIGN_CONTRACT"
  "$AGENT_UPGRADE_COMPAT"
  "$AGENT_UX"
)

all_clean=true
for agent_file in "${agent_files[@]}"; do
  if [ -f "$agent_file" ] && grep -q 'cross-feature-intel' "$agent_file"; then
    fail "INV-003a" "Agent $(basename "$agent_file") must NOT reference cross-feature-intel"
    all_clean=false
  fi
done
if [ "$all_clean" = true ]; then
  pass "INV-003a" "No review agent definition files reference cross-feature-intel"
fi

# Tests INV-003 [unit]: Task() invocations in creview-spec do NOT pass brief data
# Get the agent spawn sections (Step 1) and check they don't include cross-feature-intel
agent_spawn_section=$(sed -n '/## Step 1: Spawn Agent Team/,/## Step 2/p' "$CREVIEW_SPEC_SKILL")
if echo "$agent_spawn_section" | grep -q 'cross-feature-intel'; then
  fail "INV-003b" "creview-spec agent spawn section must NOT reference cross-feature-intel"
else
  pass "INV-003b" "creview-spec agent spawn section does not reference cross-feature-intel"
fi

# Tests INV-003 [unit]: The brief reference appears ONLY in orchestrator synthesis sections
# In creview-spec: should be in Historical Pattern Integration or a new intel section, NOT in Step 1
if grep -q 'cross-feature-intel' "$CREVIEW_SPEC_SKILL"; then
  # It should be in a synthesis/historical section, not in the agent spawn section
  in_synthesis=$(sed -n '/Historical Pattern Integration\|Intelligence Brief\|Step 2: Collect/,/## Step [34]/p' "$CREVIEW_SPEC_SKILL" | grep -c 'cross-feature-intel' || true)
  in_agents=$(echo "$agent_spawn_section" | grep -c 'cross-feature-intel' || true)
  if [ "$in_synthesis" -gt 0 ] && [ "$in_agents" = "0" ]; then
    pass "INV-003c" "creview-spec: cross-feature-intel referenced only in orchestrator synthesis"
  else
    fail "INV-003c" "creview-spec: cross-feature-intel must be only in orchestrator synthesis (synthesis=$in_synthesis, agents=$in_agents)"
  fi
else
  fail "INV-003c" "creview-spec must reference cross-feature-intel (in orchestrator synthesis)"
fi

# Tests INV-003 [unit]: Boundary is TB-003 + TB-005
# The spec says INV-003 boundary is both TB-003 and TB-005
# Verify ARCHITECTURE.md TB-003 and TB-005 are both referenced
if grep -q 'TB-003' "$CREVIEW_SPEC_SKILL" || grep -q 'TB-003' "$ARCHITECTURE_DOC"; then
  pass "INV-003d" "TB-003 referenced in architecture or skill"
else
  fail "INV-003d" "INV-003 boundary must reference TB-003"
fi

# ============================================================================
# INV-004: Brief data supplements, not replaces, existing historical data
# ============================================================================

section "INV-004: Brief data supplements existing historical data"

# Tests INV-004 [unit]: creview-spec still references qa-findings AND cross-feature-intel
if grep -q 'qa-findings' "$CREVIEW_SPEC_SKILL" && grep -q 'cross-feature-intel' "$CREVIEW_SPEC_SKILL"; then
  pass "INV-004a" "creview-spec references both qa-findings and cross-feature-intel"
else
  fail "INV-004a" "creview-spec must reference both qa-findings and cross-feature-intel (supplementary)"
fi

# Tests INV-004 [unit]: creview still references qa-findings AND cross-feature-intel
if grep -q 'qa-findings' "$CREVIEW_SKILL" && grep -q 'cross-feature-intel' "$CREVIEW_SKILL"; then
  pass "INV-004b" "creview references both qa-findings and cross-feature-intel"
else
  fail "INV-004b" "creview must reference both qa-findings and cross-feature-intel (supplementary)"
fi

# ============================================================================
# INV-005: Anti-anchoring directive in review synthesis
# ============================================================================

section "INV-005: Anti-anchoring directive in review synthesis"

# Tests INV-005 [unit]: creview-spec has a review-context anti-anchoring directive for brief data
# Must specifically reference the intelligence brief, not just the historical pattern section
# Note: "Weight" may be bold-formatted as **Weight** in markdown
if grep -q 'Weight.*contradicts.*agent\|Dismiss.*independently found' "$CREVIEW_SPEC_SKILL"; then
  pass "INV-005a" "creview-spec has review-context anti-anchoring directive"
else
  fail "INV-005a" "creview-spec must have review-context anti-anchoring directive for brief data"
fi

if grep -q 'Weight.*contradicts.*agent\|Dismiss.*independently found' "$CREVIEW_SKILL"; then
  pass "INV-005b" "creview has review-context anti-anchoring directive"
else
  fail "INV-005b" "creview must have review-context anti-anchoring directive for brief data"
fi

# Tests INV-005 [unit]: directive includes review-specific calibration (not copied from cspec)
# The spec says: "Weight when a historical pattern contradicts an agent's conclusion"
# and "Dismiss when agents independently found the same issue"
if grep -q 'contradicts.*agent\|agent.*conclusion\|independently found' "$CREVIEW_SPEC_SKILL"; then
  pass "INV-005c" "creview-spec has review-adapted calibration examples"
else
  fail "INV-005c" "creview-spec must have review-adapted calibration examples (not copied from cspec)"
fi

if grep -q 'contradicts.*agent\|agent.*conclusion\|independently found' "$CREVIEW_SKILL"; then
  pass "INV-005d" "creview has review-adapted calibration examples"
else
  fail "INV-005d" "creview must have review-adapted calibration examples (not copied from cspec)"
fi

# Tests INV-005 [unit]: directive appears BEFORE brief data reference
# Line number comparison: review-context anti-anchoring line must come before the brief jq read
# Use the review-specific directive text (not the generic historical pattern "anchoring" text)
anchoring_line_spec=$(grep -n 'Weight.*contradicts.*agent\|Dismiss.*independently found' "$CREVIEW_SPEC_SKILL" | head -1 | cut -d: -f1)
brief_data_line_spec=$(grep -n 'cross-feature-intel\.json' "$CREVIEW_SPEC_SKILL" | grep -v 'allowed-tools' | head -1 | cut -d: -f1)
if [ -n "$anchoring_line_spec" ] && [ -n "$brief_data_line_spec" ] && [ "$anchoring_line_spec" -lt "$brief_data_line_spec" ] 2>/dev/null; then
  pass "INV-005e" "creview-spec: anti-anchoring directive appears before brief data"
else
  fail "INV-005e" "creview-spec: anti-anchoring directive must appear before brief data (anchoring=$anchoring_line_spec, data=$brief_data_line_spec)"
fi

anchoring_line_rev=$(grep -n 'Weight.*contradicts.*agent\|Dismiss.*independently found' "$CREVIEW_SKILL" | head -1 | cut -d: -f1)
brief_data_line_rev=$(grep -n 'cross-feature-intel\.json' "$CREVIEW_SKILL" | grep -v 'allowed-tools' | head -1 | cut -d: -f1)
if [ -n "$anchoring_line_rev" ] && [ -n "$brief_data_line_rev" ] && [ "$anchoring_line_rev" -lt "$brief_data_line_rev" ] 2>/dev/null; then
  pass "INV-005f" "creview: anti-anchoring directive appears before brief data"
else
  fail "INV-005f" "creview: anti-anchoring directive must appear before brief data (anchoring=$anchoring_line_rev, data=$brief_data_line_rev)"
fi

# ============================================================================
# INV-006: Dormant degradation when brief is absent
# ============================================================================

section "INV-006: Dormant degradation when brief is absent"

# Tests INV-006 [unit]: creview-spec describes dormant behavior for missing brief
if grep -q 'absent\|missing\|does not exist\|dormant' "$CREVIEW_SPEC_SKILL" \
   && grep -q 'cross-feature-intel' "$CREVIEW_SPEC_SKILL"; then
  # Must mention proceeding without brief data, no error
  if grep -q 'no error\|proceed\|dormant\|without brief\|graceful' "$CREVIEW_SPEC_SKILL"; then
    pass "INV-006a" "creview-spec describes dormant degradation for missing brief"
  else
    fail "INV-006a" "creview-spec must describe dormant degradation (proceed without brief, no error)"
  fi
else
  fail "INV-006a" "creview-spec must describe dormant behavior when brief is absent"
fi

# Tests INV-006 [unit]: creview describes dormant behavior for missing brief
if grep -q 'absent\|missing\|does not exist\|dormant' "$CREVIEW_SKILL" \
   && grep -q 'cross-feature-intel' "$CREVIEW_SKILL"; then
  if grep -q 'no error\|proceed\|dormant\|without brief\|graceful' "$CREVIEW_SKILL"; then
    pass "INV-006b" "creview describes dormant degradation for missing brief"
  else
    fail "INV-006b" "creview must describe dormant degradation (proceed without brief, no error)"
  fi
else
  fail "INV-006b" "creview must describe dormant behavior when brief is absent"
fi

# Tests INV-006 [unit]: informational note for cold-start (all entries below threshold)
if grep -q 'accumulating\|entries accumulating\|need.*cycles\|cold.start' "$CREVIEW_SPEC_SKILL"; then
  pass "INV-006c" "creview-spec has cold-start informational note"
else
  fail "INV-006c" "creview-spec must have cold-start informational note (entries accumulating)"
fi

if grep -q 'accumulating\|entries accumulating\|need.*cycles\|cold.start' "$CREVIEW_SKILL"; then
  pass "INV-006d" "creview has cold-start informational note"
else
  fail "INV-006d" "creview must have cold-start informational note (entries accumulating)"
fi

# ============================================================================
# INV-007: Occurrence tracking persists across regenerations
# ============================================================================

section "INV-007: Occurrence tracking persists across regenerations"

# Tests INV-007 [unit]: script references locked_update_file
if grep -q 'locked_update_file' "$INTEL_SCRIPT"; then
  pass "INV-007a" "Script uses locked_update_file for read-modify-write"
else
  fail "INV-007a" "Script must use locked_update_file() for read-modify-write cycle"
fi

# Tests INV-007 [unit]: script has occurrences field handling
if grep -q 'occurrences' "$INTEL_SCRIPT"; then
  pass "INV-007b" "Script references occurrences field"
else
  fail "INV-007b" "Script must track occurrences field per entry"
fi

# Tests INV-007 [unit]: script has _dormant_counts handling
if grep -q '_dormant_counts' "$INTEL_SCRIPT"; then
  pass "INV-007c" "Script references _dormant_counts"
else
  fail "INV-007c" "Script must maintain _dormant_counts for entries that leave the brief"
fi

# Tests INV-007 [behavioral]: occurrence counts increment across regenerations
wd3=$(mkworkdir "inv007-incr")
setup_fixture_dirs "$wd3"
write_deferred_findings "$wd3"

# Generate brief twice with same data
run_intel "$wd3" > /dev/null 2>&1
first_run_occ=$(jq '[.sections | to_entries[] | .value[] | .occurrences // 0] | add // 0' "$wd3/.correctless/meta/cross-feature-intel.json" 2>/dev/null)

run_intel "$wd3" > /dev/null 2>&1
second_run_occ=$(jq '[.sections | to_entries[] | .value[] | .occurrences // 0] | add // 0' "$wd3/.correctless/meta/cross-feature-intel.json" 2>/dev/null)

if [ -n "$first_run_occ" ] && [ -n "$second_run_occ" ] && [ "$second_run_occ" -gt "$first_run_occ" ] 2>/dev/null; then
  pass "INV-007d" "Occurrence counts increment across regenerations"
else
  fail "INV-007d" "Occurrence counts must increment across regenerations (first=$first_run_occ, second=$second_run_occ)"
fi

# Tests INV-007 [behavioral]: _dormant_counts eviction at 90 days
# Must specifically reference dormant eviction, not just the recency filter
if grep -q '_dormant_counts' "$INTEL_SCRIPT" && grep -q 'dormant.*evict\|evict.*dormant\|dormant.*stale\|dormant.*90\|dormant.*STALENESS' "$INTEL_SCRIPT"; then
  pass "INV-007e" "_dormant_counts has 90-day eviction"
else
  fail "INV-007e" "_dormant_counts must evict entries older than 90 days"
fi

# Tests INV-007 [unit]: _dormant_counts has 100-entry cap
if grep -q '100\|dormant.*cap\|_dormant.*100' "$INTEL_SCRIPT"; then
  pass "INV-007f" "_dormant_counts has 100-entry cap"
else
  fail "INV-007f" "_dormant_counts must be capped at 100 entries"
fi

# Tests INV-007 [behavioral]: entries without occurrences field treated as 0
wd4=$(mkworkdir "inv007-seed")
setup_fixture_dirs "$wd4"
write_deferred_findings "$wd4"
# Create a pre-existing brief without occurrences fields
write_brief_fixture_no_occurrences "$wd4/.correctless/meta/cross-feature-intel.json"

run_intel "$wd4" > /dev/null 2>&1
seeded_occ=$(jq '[.sections | to_entries[] | .value[] | .occurrences // 0] | min // 0' "$wd4/.correctless/meta/cross-feature-intel.json" 2>/dev/null)

# Pre-occurrence entries should be seeded at 1 (treated as 0 + increment to 1)
if [ "$seeded_occ" = "1" ] 2>/dev/null; then
  pass "INV-007g" "Pre-occurrence entries seeded to occurrences=1"
else
  fail "INV-007g" "Pre-occurrence entries must be seeded to occurrences=1 (got $seeded_occ)"
fi

# ============================================================================
# INV-008: Allowed-tools updated for both review skills
# ============================================================================

section "INV-008: Allowed-tools updated for both review skills"

# Tests INV-008 [unit]: creview-spec allowed-tools includes cross-feature-intel read glob
creview_spec_tools=$(head -10 "$CREVIEW_SPEC_SKILL")
if echo "$creview_spec_tools" | grep -q 'Bash(jq\*cross-feature-intel.json\*)'; then
  pass "INV-008a" "creview-spec allowed-tools includes narrowed Bash(jq*cross-feature-intel.json*)"
else
  fail "INV-008a" "creview-spec allowed-tools must include Bash(jq*cross-feature-intel.json*)"
fi

# Tests INV-008 [unit]: creview allowed-tools includes cross-feature-intel read glob
creview_tools=$(head -10 "$CREVIEW_SKILL")
if echo "$creview_tools" | grep -q 'Bash(jq\*cross-feature-intel.json\*)'; then
  pass "INV-008b" "creview allowed-tools includes narrowed Bash(jq*cross-feature-intel.json*)"
else
  fail "INV-008b" "creview allowed-tools must include Bash(jq*cross-feature-intel.json*)"
fi

# ============================================================================
# INV-009: ABS-037 consumer list and statefulness update
# ============================================================================

section "INV-009: ABS-037 consumer list and statefulness update"

# Tests INV-009 [unit]: ABS-037 lists /creview-spec and /creview as consumers
# Use a tighter range: ABS-037 to the next ### heading (any kind, not just ABS)
abs037_section=$(sed -n '/### ABS-037/,/^### [A-Z]/{ /^### [A-Z]/!p; /### ABS-037/p; }' "$ARCHITECTURE_DOC")

if echo "$abs037_section" | grep -q 'creview-spec' && echo "$abs037_section" | grep -q 'creview[^-]'; then
  pass "INV-009a" "ABS-037 lists both review skills as consumers"
else
  fail "INV-009a" "ABS-037 must list /creview-spec and /creview as consumers"
fi

# Tests INV-009 [unit]: ABS-037 replaced "idempotent" with "stateful"
if echo "$abs037_section" | grep -qi 'idempotent'; then
  fail "INV-009b" "ABS-037 still contains 'idempotent' — must be replaced with 'stateful'"
else
  if echo "$abs037_section" | grep -qi 'stateful'; then
    pass "INV-009b" "ABS-037 replaced idempotent with stateful"
  else
    fail "INV-009b" "ABS-037 must contain 'stateful' (occurrence counts accumulate)"
  fi
fi

# Tests INV-009 [unit]: ABS-037 Enforced at includes both review skill paths
if echo "$abs037_section" | grep -q 'skills/creview-spec/SKILL.md' && echo "$abs037_section" | grep -q 'skills/creview/SKILL.md'; then
  pass "INV-009c" "ABS-037 Enforced at includes both review skill paths"
else
  fail "INV-009c" "ABS-037 Enforced at must include skills/creview-spec/SKILL.md and skills/creview/SKILL.md"
fi

# Tests INV-009 [unit]: ABS-037 notes review skills as pure consumers (not regeneration triggers)
if echo "$abs037_section" | grep -q 'consumer\|read.*only\|pure consumer\|not.*regeneration'; then
  pass "INV-009d" "ABS-037 notes review skills as consumers (not triggers)"
else
  fail "INV-009d" "ABS-037 must note review skills as pure consumers, not regeneration triggers"
fi

# Tests INV-009 [unit]: TB-003 lists both review skills
tb003_section=$(sed -n '/### TB-003/,/### TB-00[0-9]/p' "$ARCHITECTURE_DOC")

if echo "$tb003_section" | grep -q 'creview-spec' && echo "$tb003_section" | grep -q 'creview[^-]'; then
  pass "INV-009e" "TB-003 lists both review skills"
else
  fail "INV-009e" "TB-003 must list /creview-spec and /creview as anti-anchoring directive consumers"
fi

# ============================================================================
# INV-010: /cstatus reports threshold proximity
# ============================================================================

section "INV-010: /cstatus reports threshold proximity"

# Tests INV-010 [unit]: cstatus section 6c mentions threshold proximity / occurrence breakdown
if grep -q 'threshold proximity\|occurrence.*count\|entries at.*occurrences\|occurrence.*breakdown\|occurrence-level' "$CSTATUS_SKILL"; then
  pass "INV-010a" "cstatus reports threshold proximity"
else
  fail "INV-010a" "cstatus section 6c must report threshold proximity (occurrence-level breakdown)"
fi

# Tests INV-010 [unit]: cstatus mentions both below-threshold and above-threshold counts
if grep -q 'below.*threshold\|above.*threshold\|at.*[0-9].*occurrences\|entries at' "$CSTATUS_SKILL"; then
  pass "INV-010b" "cstatus reports entries at various occurrence levels"
else
  fail "INV-010b" "cstatus must report entries at various occurrence levels relative to threshold"
fi

# ============================================================================
# INV-011: Review findings artifact records intelligence consumption
# ============================================================================

section "INV-011: Review findings artifact records intelligence consumption"

# Tests INV-011 [unit]: creview-spec has intelligence consumption metadata in artifact-write section
if grep -q 'Intelligence brief.*consumed\|Intelligence brief.*dormant\|intelligence.*consumed\|intelligence.*dormant' "$CREVIEW_SPEC_SKILL"; then
  pass "INV-011a" "creview-spec has intelligence consumption metadata line"
else
  fail "INV-011a" "creview-spec must include intelligence consumption metadata in findings artifact"
fi

# Tests INV-011 [unit]: creview has intelligence consumption metadata in artifact-write section
if grep -q 'Intelligence brief.*consumed\|Intelligence brief.*dormant\|intelligence.*consumed\|intelligence.*dormant' "$CREVIEW_SKILL"; then
  pass "INV-011b" "creview has intelligence consumption metadata line"
else
  fail "INV-011b" "creview must include intelligence consumption metadata in findings artifact"
fi

# Tests INV-011 [unit]: metadata distinguishes consumed vs dormant
if grep -q 'consumed.*entries\|consumed.*(.*entries' "$CREVIEW_SPEC_SKILL" \
   && grep -q 'dormant.*absent\|dormant.*malformed\|dormant.*below' "$CREVIEW_SPEC_SKILL"; then
  pass "INV-011c" "creview-spec distinguishes consumed vs dormant in metadata"
else
  fail "INV-011c" "creview-spec must distinguish 'consumed (N entries)' vs 'dormant (reason)'"
fi

if grep -q 'consumed.*entries\|consumed.*(.*entries' "$CREVIEW_SKILL" \
   && grep -q 'dormant.*absent\|dormant.*malformed\|dormant.*below' "$CREVIEW_SKILL"; then
  pass "INV-011d" "creview distinguishes consumed vs dormant in metadata"
else
  fail "INV-011d" "creview must distinguish 'consumed (N entries)' vs 'dormant (reason)'"
fi

# ============================================================================
# PRH-001: Brief data must not enter agent prompts
# ============================================================================

section "PRH-001: Brief data must not enter agent prompts"

# Tests PRH-001 [unit]: no agent definition file has cross-feature-intel in system prompt
prh001_clean=true
for agent_file in "${agent_files[@]}"; do
  if [ -f "$agent_file" ]; then
    # Check body (after frontmatter) for cross-feature-intel references
    body=$(sed -n '/^---$/,/^---$/d; p' "$agent_file" | tail -n +2)
    if echo "$body" | grep -q 'cross-feature-intel'; then
      fail "PRH-001a" "Agent $(basename "$agent_file") body must NOT reference cross-feature-intel"
      prh001_clean=false
    fi
  fi
done
if [ "$prh001_clean" = true ]; then
  pass "PRH-001a" "No agent definition bodies reference cross-feature-intel"
fi

# Tests PRH-001 [unit]: standard preamble does not reference cross-feature-intel
preamble_section=$(sed -n '/Standard preamble/,/###/p' "$CREVIEW_SPEC_SKILL")
if echo "$preamble_section" | grep -q 'cross-feature-intel'; then
  fail "PRH-001b" "Standard preamble must NOT reference cross-feature-intel"
else
  pass "PRH-001b" "Standard preamble does not reference cross-feature-intel"
fi

# ============================================================================
# PRH-002: Review skills must not invoke the intelligence script
# ============================================================================

section "PRH-002: Review skills must not invoke the intelligence script"

# Tests PRH-002 [unit]: creview-spec does NOT reference cross-feature-intel.sh (the script)
if grep -q 'cross-feature-intel\.sh' "$CREVIEW_SPEC_SKILL"; then
  fail "PRH-002a" "creview-spec must NOT reference cross-feature-intel.sh (the script)"
else
  pass "PRH-002a" "creview-spec does not reference the script (only the file)"
fi

# Tests PRH-002 [unit]: creview does NOT reference cross-feature-intel.sh (the script)
if grep -q 'cross-feature-intel\.sh' "$CREVIEW_SKILL"; then
  fail "PRH-002b" "creview must NOT reference cross-feature-intel.sh (the script)"
else
  pass "PRH-002b" "creview does not reference the script (only the file)"
fi

# Tests PRH-002 [unit]: creview-spec DOES reference cross-feature-intel.json (the file) via jq
if grep -q 'cross-feature-intel\.json' "$CREVIEW_SPEC_SKILL"; then
  pass "PRH-002c" "creview-spec references cross-feature-intel.json (the file)"
else
  fail "PRH-002c" "creview-spec must reference cross-feature-intel.json for jq-based reading"
fi

# Tests PRH-002 [unit]: creview DOES reference cross-feature-intel.json (the file) via jq
if grep -q 'cross-feature-intel\.json' "$CREVIEW_SKILL"; then
  pass "PRH-002d" "creview references cross-feature-intel.json (the file)"
else
  fail "PRH-002d" "creview must reference cross-feature-intel.json for jq-based reading"
fi

# ============================================================================
# BND-001: All entries below threshold
# ============================================================================

section "BND-001: All entries below threshold"

# Tests BND-001 [behavioral]: all entries below threshold produces valid empty-filtered JSON
wd5=$(mkworkdir "bnd001")
setup_fixture_dirs "$wd5"
write_deferred_findings "$wd5"

# Generate brief (first run, all entries at occurrences=1)
run_intel "$wd5" > /dev/null 2>&1

# Filter with --min-occurrences 3, expect all sections empty
bnd001_output=$(bash "$INTEL_SCRIPT" --base "$wd5/.correctless" --min-occurrences 3 2>&1)
if echo "$bnd001_output" | jq -e '.' >/dev/null 2>&1; then
  total_entries=$(echo "$bnd001_output" | jq '[.sections | to_entries[] | .value | length] | add // 0' 2>/dev/null)
  if [ "$total_entries" = "0" ] 2>/dev/null; then
    pass "BND-001a" "All entries below threshold produces empty filtered output"
  else
    fail "BND-001a" "All entries below threshold must produce empty sections (found $total_entries entries)"
  fi
else
  fail "BND-001a" "Script must produce valid JSON even when all entries below threshold"
fi

# Tests BND-001 [behavioral]: valid JSON structure even with empty sections
if echo "$bnd001_output" | jq -e '.sections.deferred_findings | type == "array"' >/dev/null 2>&1; then
  pass "BND-001b" "Empty sections are still valid JSON arrays"
else
  fail "BND-001b" "Empty sections must be valid JSON arrays, not null"
fi

# ============================================================================
# BND-002: First-ever brief generation and pre-occurrence-tracking migration
# ============================================================================

section "BND-002: First-ever brief generation"

# Tests BND-002 [behavioral]: no existing brief file, all entries start at occurrences=1
wd6=$(mkworkdir "bnd002-fresh")
setup_fixture_dirs "$wd6"
write_deferred_findings "$wd6"

# Ensure no prior brief exists
rm -f "$wd6/.correctless/meta/cross-feature-intel.json"

run_intel "$wd6" > /dev/null 2>&1

if [ -f "$wd6/.correctless/meta/cross-feature-intel.json" ]; then
  # All entries should have occurrences=1
  min_occ=$(jq '[.sections | to_entries[] | .value[] | .occurrences // 0] | min // 0' "$wd6/.correctless/meta/cross-feature-intel.json" 2>/dev/null)
  max_occ=$(jq '[.sections | to_entries[] | .value[] | .occurrences // 0] | max // 0' "$wd6/.correctless/meta/cross-feature-intel.json" 2>/dev/null)
  if [ "$min_occ" = "1" ] && [ "$max_occ" = "1" ] 2>/dev/null; then
    pass "BND-002a" "First-ever generation: all entries at occurrences=1"
  else
    fail "BND-002a" "First-ever generation must set all entries to occurrences=1 (min=$min_occ, max=$max_occ)"
  fi
else
  fail "BND-002a" "Script must write brief file on first generation"
fi

# Tests BND-002 [behavioral]: existing brief without occurrences field migrates correctly
wd7=$(mkworkdir "bnd002-migrate")
setup_fixture_dirs "$wd7"
write_deferred_findings "$wd7"
write_brief_fixture_no_occurrences "$wd7/.correctless/meta/cross-feature-intel.json"

run_intel "$wd7" > /dev/null 2>&1

if [ -f "$wd7/.correctless/meta/cross-feature-intel.json" ]; then
  # Entries from pre-occurrence era should now have occurrences=1
  has_occ=$(jq '[.sections | to_entries[] | .value[] | has("occurrences")] | all' "$wd7/.correctless/meta/cross-feature-intel.json" 2>/dev/null)
  if [ "$has_occ" = "true" ]; then
    pass "BND-002b" "Migration: pre-occurrence entries now have occurrences field"
  else
    fail "BND-002b" "Migration must add occurrences field to pre-occurrence entries"
  fi
else
  fail "BND-002b" "Brief file must exist after migration run"
fi

# Tests BND-002 [behavioral]: _dormant_counts section created empty on first run
if [ -f "$wd6/.correctless/meta/cross-feature-intel.json" ]; then
  has_dormant=$(jq 'has("_dormant_counts")' "$wd6/.correctless/meta/cross-feature-intel.json" 2>/dev/null)
  if [ "$has_dormant" = "true" ]; then
    dormant_count=$(jq '._dormant_counts | length' "$wd6/.correctless/meta/cross-feature-intel.json" 2>/dev/null)
    if [ "$dormant_count" = "0" ] 2>/dev/null; then
      pass "BND-002c" "First run creates empty _dormant_counts"
    else
      fail "BND-002c" "First run must create empty _dormant_counts (found $dormant_count entries)"
    fi
  else
    fail "BND-002c" "First run must create _dormant_counts section"
  fi
else
  fail "BND-002c" "Brief file must exist for _dormant_counts check"
fi

# ============================================================================
# BND-003: Entry leaves and re-enters the brief
# ============================================================================

section "BND-003: Entry leaves and re-enters the brief"

# Tests BND-003 [behavioral]: entry count preserved via _dormant_counts
wd8=$(mkworkdir "bnd003-reenter")
setup_fixture_dirs "$wd8"
write_deferred_findings "$wd8"

# Generate brief: entry gets occurrences=1
run_intel "$wd8" > /dev/null 2>&1
# Second run: occurrences=2
run_intel "$wd8" > /dev/null 2>&1

# Remove the deferred findings so entry drops out
rm -f "$wd8/.correctless/meta/deferred-findings.json"
# Regenerate: entry should move to _dormant_counts with count=2
run_intel "$wd8" > /dev/null 2>&1

# Check _dormant_counts has the entry
if [ -f "$wd8/.correctless/meta/cross-feature-intel.json" ]; then
  dormant_has_df001=$(jq '._dormant_counts | has("DF-001") // false' "$wd8/.correctless/meta/cross-feature-intel.json" 2>/dev/null)
  if [ "$dormant_has_df001" = "true" ]; then
    dormant_count_df001=$(jq '._dormant_counts["DF-001"]' "$wd8/.correctless/meta/cross-feature-intel.json" 2>/dev/null)
    if [ "$dormant_count_df001" = "2" ] 2>/dev/null; then
      pass "BND-003a" "Entry moved to _dormant_counts with preserved count"
    else
      fail "BND-003a" "Entry in _dormant_counts must have preserved count=2 (got $dormant_count_df001)"
    fi
  else
    fail "BND-003a" "Entry must move to _dormant_counts when it leaves the brief"
  fi
else
  fail "BND-003a" "Brief file must exist after regeneration"
fi

# Re-add the deferred findings and regenerate: entry should resume with count=3
write_deferred_findings "$wd8"
run_intel "$wd8" > /dev/null 2>&1

if [ -f "$wd8/.correctless/meta/cross-feature-intel.json" ]; then
  resumed_occ=$(jq '[.sections.deferred_findings[] | select(.id == "DF-001") | .occurrences] | .[0] // 0' "$wd8/.correctless/meta/cross-feature-intel.json" 2>/dev/null)
  if [ "$resumed_occ" = "3" ] 2>/dev/null; then
    pass "BND-003b" "Re-entered entry resumes with incremented count (dormant+1)"
  else
    fail "BND-003b" "Re-entered entry must resume with count from _dormant_counts+1 (expected 3, got $resumed_occ)"
  fi
else
  fail "BND-003b" "Brief file must exist after re-entry"
fi

# Tests BND-003 [behavioral]: corruption cases — _dormant_counts key missing, null, wrong type
wd9=$(mkworkdir "bnd003-corrupt")
setup_fixture_dirs "$wd9"
write_deferred_findings "$wd9"

# Write a brief with corrupted _dormant_counts (string instead of integer)
mkdir -p "$wd9/.correctless/meta"
cat > "$wd9/.correctless/meta/cross-feature-intel.json" << 'CORRUPT'
{
  "schema_version": 1,
  "generated_at": "2026-05-22T10:00:00Z",
  "scope": [],
  "truncated_count": 0,
  "warnings": [],
  "sections": {
    "deferred_findings": [
      {
        "id": "DF-001",
        "date": "2026-05-20",
        "summary": "Missing validation",
        "file_refs": [],
        "severity": "HIGH",
        "source": "deferred-findings.json",
        "occurrences": 5
      }
    ],
    "devadv_themes": [],
    "override_patterns": [],
    "lens_recommendations": [],
    "debug_clusters": [],
    "phase_effectiveness": []
  },
  "_dormant_counts": {
    "DF-099": "not-a-number",
    "DF-100": null
  }
}
CORRUPT

# Script should handle corrupted _dormant_counts gracefully (fail-open: restart at 1)
run_intel "$wd9" > /dev/null 2>&1
if [ $? -eq 0 ] 2>/dev/null; then
  pass "BND-003c" "Script handles corrupted _dormant_counts gracefully (no crash)"
else
  fail "BND-003c" "Script must handle corrupted _dormant_counts without crashing"
fi

# ============================================================================
# Summary
# ============================================================================

summary "review-intel-consumer"
