#!/usr/bin/env bash
# Correctless — Cross-Feature Intelligence Layer test suite
# Tests spec rules INV-001 through INV-016, PRH-001 through PRH-003,
# BND-001 through BND-003 from
# .correctless/specs/cross-feature-intelligence.md
#
# RED phase: these tests MUST FAIL — implementation does not exist yet.
# Run from repo root: bash tests/test-cross-feature-intel.sh

source "$(dirname "${BASH_SOURCE[0]}")/test-helpers.sh"

# ============================================================================
# Constants
# ============================================================================

SCRIPTS_DIR="$REPO_DIR/scripts"
SKILLS_DIR="$REPO_DIR/skills"
INTEL_SCRIPT="$SCRIPTS_DIR/cross-feature-intel.sh"
CSPEC_SKILL="$SKILLS_DIR/cspec/SKILL.md"
CSTATUS_SKILL="$SKILLS_DIR/cstatus/SKILL.md"
SETUP_SCRIPT="$REPO_DIR/setup"
SYNC_SCRIPT="$REPO_DIR/sync.sh"
WORKFLOW_ADVANCE="$REPO_DIR/hooks/workflow-advance.sh"

# Test workspace
WORK_BASE="/tmp/correctless-cfi-$$"
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
# Usage: run_intel <base_dir> [extra_args...]
run_intel() {
  local base="$1"; shift
  bash "$INTEL_SCRIPT" --base "$base/.correctless" "$@" 2>&1
}

# Helper: create a fixture directory with all 6 data source directories
setup_fixture_dirs() {
  local base="$1"
  mkdir -p "$base/.correctless/meta/overrides"
  mkdir -p "$base/.correctless/artifacts/devadv"
}

# Helper: write a valid deferred-findings fixture
write_deferred_findings() {
  local base="$1"
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
      "status": "resolved",
      "deferred_at": "2026-05-18T10:00:00Z",
      "resolved_at": "2026-05-19T10:00:00Z",
      "resolution": "Fixed in PR #100"
    },
    {
      "id": "DF-003",
      "source_file": ".correctless/artifacts/review-spec-findings-baz.md",
      "finding_id": "RS-003",
      "feature": "baz",
      "severity": "LOW",
      "description": "Test fixture does not match real format",
      "category": "review",
      "status": "open",
      "deferred_at": "2026-05-15T08:00:00Z",
      "resolved_at": null,
      "resolution": null
    }
  ]
}
FIXTURE
}

# Helper: write a devadv report with inline severity format (older style)
write_devadv_report_inline() {
  local base="$1"
  local date="${2:-2026-05-10}"
  cat > "$base/.correctless/artifacts/devadv/report-${date}.md" << FIXTURE
# Devil's Advocate Report — ${date}
**Date:** ${date} | **Mode:** layers | **Passes:** 4

## DA-001: TB-001 Violated by Design
**Severity:** architecture

### The Consensus
Test runner trusts hook scripts.

### Recommended Action
Accept as risk.

## DA-002: Branch Slug Duplication
**Severity:** medium

### The Consensus
Branch slug derived 4 times.

### Recommended Action
Extract to lib.sh.
FIXTURE
}

# Helper: write a devadv report with subsection severity format (newer style)
write_devadv_report_subsection() {
  local base="$1"
  local date="${2:-2026-05-16}"
  cat > "$base/.correctless/artifacts/devadv/report-${date}.md" << FIXTURE
# Devil's Advocate Report — ${date}

Mode: Signals (explorer scan + deep dive)

## DA-003: Tests Verify Prose Not Effectiveness

### Severity
architecture

### The Consensus
Tests provide high confidence.

### Recommended Action
Add behavioral tests.

## DA-004: Token Measurement Never Worked

### Severity
high

### The Consensus
Token tracking was designed correctly.

### Recommended Action
Act on it.
FIXTURE
}

# Helper: write override fixtures
write_overrides() {
  local base="$1"
  cat > "$base/.correctless/meta/overrides/feature-a-20260510.json" << 'FIXTURE'
{
  "task_slug": "feature-a",
  "branch": "feature/feature-a",
  "completed_at": "2026-05-10T14:00:00Z",
  "override_count": 2,
  "overrides": [
    {
      "phase": "tdd-impl",
      "reason": "Pre-existing test failure unrelated to feature",
      "timestamp": "2026-05-10T13:00:00Z",
      "branch": "feature/feature-a"
    },
    {
      "phase": "tdd-impl",
      "reason": "Pre-existing test failure unrelated to feature",
      "timestamp": "2026-05-10T13:30:00Z",
      "branch": "feature/feature-a"
    }
  ]
}
FIXTURE

  cat > "$base/.correctless/meta/overrides/feature-b-20260512.json" << 'FIXTURE'
{
  "task_slug": "feature-b",
  "branch": "feature/feature-b",
  "completed_at": "2026-05-12T16:00:00Z",
  "override_count": 1,
  "overrides": [
    {
      "phase": "tdd-qa",
      "reason": "Flaky integration test timeout",
      "timestamp": "2026-05-12T15:00:00Z",
      "branch": "feature/feature-b"
    }
  ]
}
FIXTURE
}

# Helper: write debug investigation fixture
write_debug_investigation() {
  local base="$1"
  cat > "$base/.correctless/artifacts/debug-investigation-statusline.md" << 'FIXTURE'
# Debug Investigation: Statusline not showing after /csetup

## Reproduction
settings.json after setup has PreToolUse gate hook but no statusLine entry.

## Root Cause
`register_hooks()` line 352: if grep checks only for workflow-gate and returns early.

## Fix
Changed early-return check in hooks/workflow-gate.sh to check all 4 components.

## Class Fix
Added 4 test assertions in tests/test-core.sh covering partial setup scenarios.
FIXTURE
}

# Helper: write workflow-effectiveness fixture (verbatim subset of real data per INV-016/AP-031)
write_workflow_effectiveness() {
  local base="$1"
  cat > "$base/.correctless/meta/workflow-effectiveness.json" << 'FIXTURE'
{
  "post_merge_bugs": [
    {
      "id": "PMB-001",
      "date": "@@DATE_PMB001@@",
      "description": "jq 1.7 vs 1.8 operator precedence for `as $var` bindings",
      "severity": "medium",
      "found_by": "GitHub Actions CI",
      "root_cause": "jq version differences",
      "spec_existed": false,
      "spec_id": null,
      "invariant_existed": false,
      "invariant_id": null,
      "phase_that_should_have_caught": "audit",
      "phase_was_skipped": false,
      "why_missed": "Agents verified against local jq version",
      "corrective_action": {
        "antipattern_added": true,
        "antipattern_id": "AP-011"
      }
    },
    {
      "id": "PMB-003",
      "date": "@@DATE_PMB003@@",
      "description": "Hardcoded file list in setup silently skips new scripts",
      "severity": "medium",
      "found_by": "Manual discovery",
      "root_cause": "Setup used 2-file list instead of glob",
      "spec_existed": false,
      "spec_id": null,
      "invariant_existed": false,
      "invariant_id": null,
      "phase_that_should_have_caught": "spec",
      "phase_was_skipped": false,
      "why_missed": "No upgrade compatibility lens existed",
      "corrective_action": {
        "antipattern_added": true,
        "antipattern_id": "AP-024"
      }
    },
    {
      "id": "PMB-005",
      "date": "@@DATE_PMB005@@",
      "description": "caudit findings persistence is advisory prose not gate-enforced",
      "severity": "high",
      "found_by": "Manual discovery during cmetrics",
      "root_cause": "cmd_audit_done had no artifact precondition",
      "spec_existed": false,
      "spec_id": null,
      "invariant_existed": false,
      "invariant_id": null,
      "phase_that_should_have_caught": "spec",
      "phase_was_skipped": false,
      "why_missed": "Sole-writer claims were advisory only",
      "corrective_action": {
        "antipattern_added": true,
        "antipattern_id": "AP-026"
      }
    }
  ]
}
FIXTURE
  # Dates are generated relative to today so these fixture entries stay inside
  # the intel script's 90-day recency window. They were previously hardcoded
  # absolute dates (2026-04-10/-21/-27); PMB-001's 2026-04-10 crossed 90 days
  # on ~2026-07-09, silently reddening INV-016e (audit entry filtered out) —
  # the classic bound-drift/AP-024 class. Relative dates never drift.
  sed -i \
    -e "s/@@DATE_PMB001@@/$(date -d '30 days ago' +%Y-%m-%d)/" \
    -e "s/@@DATE_PMB003@@/$(date -d '20 days ago' +%Y-%m-%d)/" \
    -e "s/@@DATE_PMB005@@/$(date -d '10 days ago' +%Y-%m-%d)/" \
    "$base/.correctless/meta/workflow-effectiveness.json"
}

# Helper: write lens recommendation fixtures
write_lens_recommendations() {
  local base="$1"
  cat > "$base/.correctless/artifacts/lens-recommendations-feature-a.json" << 'FIXTURE'
{
  "recommended_lenses": [
    {"lens_name": "hostile-input", "rationale": "Feature accepts user config input"},
    {"lens_name": "upgrade-compatibility", "rationale": "Changes setup script behavior"}
  ]
}
FIXTURE
  # Touch to set known mtime
  touch -t 202605100000 "$base/.correctless/artifacts/lens-recommendations-feature-a.json" 2>/dev/null || true

  cat > "$base/.correctless/artifacts/lens-recommendations-feature-b.json" << 'FIXTURE'
{
  "recommended_lenses": [
    {"lens_name": "hostile-input", "rationale": "Parses untrusted markdown input"},
    {"lens_name": "resource-bounds", "rationale": "Allocates file handles for each source"}
  ]
}
FIXTURE
  touch -t 202605120000 "$base/.correctless/artifacts/lens-recommendations-feature-b.json" 2>/dev/null || true

  cat > "$base/.correctless/artifacts/lens-recommendations-feature-c.json" << 'FIXTURE'
{
  "recommended_lenses": [
    {"lens_name": "hostile-input", "rationale": "Third occurrence of hostile-input recommendation"}
  ]
}
FIXTURE
  touch -t 202605150000 "$base/.correctless/artifacts/lens-recommendations-feature-c.json" 2>/dev/null || true
}


# ============================================================================
# INV-001 [unit]: Script reads 6 data sources
# ============================================================================

section "INV-001: Aggregation script reads 6 data sources"

# INV-001a: Script file exists and is executable
if [ -x "$INTEL_SCRIPT" ]; then
  pass "INV-001a" "cross-feature-intel.sh exists and is executable"
else
  fail "INV-001a" "cross-feature-intel.sh does not exist or is not executable"
fi

# INV-001b: Script references all 6 source paths
if [ -f "$INTEL_SCRIPT" ]; then
  missing_sources=()
  grep -q "deferred-findings.json" "$INTEL_SCRIPT" || missing_sources+=("deferred-findings")
  grep -q "devadv/report-" "$INTEL_SCRIPT" || missing_sources+=("devadv-reports")
  grep -q "overrides/" "$INTEL_SCRIPT" || missing_sources+=("overrides")
  grep -q "lens-recommendations-" "$INTEL_SCRIPT" || missing_sources+=("lens-recommendations")
  grep -q "debug-investigation-" "$INTEL_SCRIPT" || missing_sources+=("debug-investigations")
  grep -q "workflow-effectiveness.json" "$INTEL_SCRIPT" || missing_sources+=("workflow-effectiveness")

  if [ ${#missing_sources[@]} -eq 0 ]; then
    pass "INV-001b" "script references all 6 source paths"
  else
    fail "INV-001b" "script missing source references: ${missing_sources[*]}"
  fi
else
  fail "INV-001b" "script does not exist — cannot check source references"
fi

# INV-001c: Script does not error on missing sources (each is optional)
inv001c_dir=$(mkworkdir inv001c)
setup_fixture_dirs "$inv001c_dir"
# Empty dirs, no source files at all
if [ -x "$INTEL_SCRIPT" ]; then
  output=$(run_intel "$inv001c_dir")
  rc=$?
  if [ $rc -eq 0 ] && echo "$output" | jq -e '.sections' >/dev/null 2>&1; then
    pass "INV-001c" "script handles all missing sources gracefully (exit 0, valid JSON)"
  else
    fail "INV-001c" "script failed or produced invalid JSON when all sources are missing (rc=$rc)"
  fi
else
  fail "INV-001c" "script not executable — cannot test missing sources"
fi

# INV-001d: Script produces output with all 6 sections when all sources present
inv001d_dir=$(mkworkdir inv001d)
setup_fixture_dirs "$inv001d_dir"
write_deferred_findings "$inv001d_dir"
write_devadv_report_inline "$inv001d_dir" "2026-05-10"
write_overrides "$inv001d_dir"
write_lens_recommendations "$inv001d_dir"
write_debug_investigation "$inv001d_dir"
write_workflow_effectiveness "$inv001d_dir"

if [ -x "$INTEL_SCRIPT" ]; then
  output=$(run_intel "$inv001d_dir")
  rc=$?
  if [ $rc -eq 0 ]; then
    section_count=$(echo "$output" | jq -r '.sections | keys | length' 2>/dev/null)
    if [ "$section_count" = "6" ]; then
      pass "INV-001d" "script produces all 6 sections when all sources present"
    else
      fail "INV-001d" "expected 6 sections, got $section_count"
    fi
  else
    fail "INV-001d" "script exited non-zero ($rc) with all sources present"
  fi
else
  fail "INV-001d" "script not executable"
fi


# ============================================================================
# INV-002 [unit]: File-scope filtering
# ============================================================================

section "INV-002: File-scope filtering"

# INV-002a: --scope filters entries with file_refs
inv002a_dir=$(mkworkdir inv002a)
setup_fixture_dirs "$inv002a_dir"
write_debug_investigation "$inv002a_dir"

if [ -x "$INTEL_SCRIPT" ]; then
  # With scope matching the debug investigation's file refs
  output=$(run_intel "$inv002a_dir" --scope "hooks/workflow-gate.sh,tests/test-core.sh")
  debug_count=$(echo "$output" | jq -r '.sections.debug_clusters | length' 2>/dev/null)
  if [ "$debug_count" -gt 0 ] 2>/dev/null; then
    pass "INV-002a" "entries with matching file_refs included when scope overlaps"
  else
    fail "INV-002a" "expected debug_clusters entries when scope overlaps file_refs (got $debug_count)"
  fi
else
  fail "INV-002a" "script not executable"
fi

# INV-002b: Entries without file_refs included unconditionally
inv002b_dir=$(mkworkdir inv002b)
setup_fixture_dirs "$inv002b_dir"
write_deferred_findings "$inv002b_dir"

if [ -x "$INTEL_SCRIPT" ]; then
  output=$(run_intel "$inv002b_dir" --scope "some/unrelated/file.sh")
  df_count=$(echo "$output" | jq -r '.sections.deferred_findings | length' 2>/dev/null)
  if [ "$df_count" -gt 0 ] 2>/dev/null; then
    pass "INV-002b" "entries without file_refs included unconditionally"
  else
    fail "INV-002b" "deferred_findings (no file_refs) excluded when --scope set ($df_count)"
  fi
else
  fail "INV-002b" "script not executable"
fi

# INV-002c: Without --scope, all entries included (unfiltered mode)
inv002c_dir=$(mkworkdir inv002c)
setup_fixture_dirs "$inv002c_dir"
write_deferred_findings "$inv002c_dir"
write_debug_investigation "$inv002c_dir"

if [ -x "$INTEL_SCRIPT" ]; then
  output=$(run_intel "$inv002c_dir")
  df_count=$(echo "$output" | jq -r '.sections.deferred_findings | length' 2>/dev/null)
  debug_count=$(echo "$output" | jq -r '.sections.debug_clusters | length' 2>/dev/null)
  if [ "$df_count" -gt 0 ] 2>/dev/null && [ "$debug_count" -gt 0 ] 2>/dev/null; then
    pass "INV-002c" "all entries included when --scope is omitted"
  else
    fail "INV-002c" "entries missing in unfiltered mode (df=$df_count, debug=$debug_count)"
  fi
else
  fail "INV-002c" "script not executable"
fi

# INV-002d: Entries with non-overlapping file_refs excluded
inv002d_dir=$(mkworkdir inv002d)
setup_fixture_dirs "$inv002d_dir"
write_debug_investigation "$inv002d_dir"

if [ -x "$INTEL_SCRIPT" ]; then
  output=$(run_intel "$inv002d_dir" --scope "totally/unrelated/path.py")
  debug_count=$(echo "$output" | jq -r '.sections.debug_clusters | length' 2>/dev/null)
  if [ "$debug_count" = "0" ] 2>/dev/null; then
    pass "INV-002d" "entries with non-overlapping file_refs excluded"
  else
    fail "INV-002d" "expected 0 debug_clusters for non-overlapping scope (got $debug_count)"
  fi
else
  fail "INV-002d" "script not executable"
fi


# ============================================================================
# INV-003 [unit]: Recency weighting and staleness exclusion
# ============================================================================

section "INV-003: Recency weighting and staleness exclusion"

# INV-003a: Entries older than 90 days excluded
inv003a_dir=$(mkworkdir inv003a)
setup_fixture_dirs "$inv003a_dir"
# Create a deferred finding from 100 days ago
cat > "$inv003a_dir/.correctless/meta/deferred-findings.json" << 'FIXTURE'
{
  "schema_version": 1,
  "findings": [
    {
      "id": "DF-001",
      "source_file": ".correctless/artifacts/review-spec-findings-old.md",
      "finding_id": "RS-001",
      "feature": "old-feature",
      "severity": "HIGH",
      "description": "Ancient finding from 100 days ago",
      "category": "review",
      "status": "open",
      "deferred_at": "2026-02-10T12:00:00Z",
      "resolved_at": null,
      "resolution": null
    },
    {
      "id": "DF-002",
      "source_file": ".correctless/artifacts/review-spec-findings-recent.md",
      "finding_id": "RS-002",
      "feature": "recent-feature",
      "severity": "MEDIUM",
      "description": "Recent finding from 10 days ago",
      "category": "review",
      "status": "open",
      "deferred_at": "2026-05-12T12:00:00Z",
      "resolved_at": null,
      "resolution": null
    }
  ]
}
FIXTURE

if [ -x "$INTEL_SCRIPT" ]; then
  output=$(run_intel "$inv003a_dir")
  old_present=$(echo "$output" | jq -r '.sections.deferred_findings[] | select(.id == "DF-001")' 2>/dev/null)
  recent_present=$(echo "$output" | jq -r '.sections.deferred_findings[] | select(.id == "DF-002")' 2>/dev/null)
  if [ -z "$old_present" ] && [ -n "$recent_present" ]; then
    pass "INV-003a" "entries older than 90 days excluded, recent entries retained"
  else
    fail "INV-003a" "staleness filter not working (old present: $([ -n "$old_present" ] && echo yes || echo no), recent present: $([ -n "$recent_present" ] && echo yes || echo no))"
  fi
else
  fail "INV-003a" "script not executable"
fi

# INV-003b: Entries sorted by recency within sections (newest first)
inv003b_dir=$(mkworkdir inv003b)
setup_fixture_dirs "$inv003b_dir"
cat > "$inv003b_dir/.correctless/meta/deferred-findings.json" << 'FIXTURE'
{
  "schema_version": 1,
  "findings": [
    {
      "id": "DF-001",
      "source_file": ".correctless/artifacts/review-spec-findings-a.md",
      "finding_id": "RS-001",
      "feature": "a",
      "severity": "HIGH",
      "description": "Older finding",
      "category": "review",
      "status": "open",
      "deferred_at": "2026-04-01T12:00:00Z",
      "resolved_at": null,
      "resolution": null
    },
    {
      "id": "DF-002",
      "source_file": ".correctless/artifacts/review-spec-findings-b.md",
      "finding_id": "RS-002",
      "feature": "b",
      "severity": "MEDIUM",
      "description": "Newer finding",
      "category": "review",
      "status": "open",
      "deferred_at": "2026-05-20T12:00:00Z",
      "resolved_at": null,
      "resolution": null
    }
  ]
}
FIXTURE

if [ -x "$INTEL_SCRIPT" ]; then
  output=$(run_intel "$inv003b_dir")
  first_id=$(echo "$output" | jq -r '.sections.deferred_findings[0].id' 2>/dev/null)
  if [ "$first_id" = "DF-002" ]; then
    pass "INV-003b" "entries sorted newest first within sections"
  else
    fail "INV-003b" "expected newest first (DF-002), got $first_id"
  fi
else
  fail "INV-003b" "script not executable"
fi


# ============================================================================
# INV-004 [unit]: Brief size cap with per-section minimum
# ============================================================================

section "INV-004: Brief size cap (30 entries, per-section minimum)"

# INV-004a: Total entries capped at 30
inv004a_dir=$(mkworkdir inv004a)
setup_fixture_dirs "$inv004a_dir"
# Create 35 deferred findings (all open, all recent)
findings_json='{"schema_version":1,"findings":['
for i in $(seq 1 35); do
  [ $i -gt 1 ] && findings_json+=","
  findings_json+="{\"id\":\"DF-$(printf '%03d' "$i")\",\"source_file\":\".correctless/artifacts/f.md\",\"finding_id\":\"RS-001\",\"feature\":\"feat-$i\",\"severity\":\"MEDIUM\",\"description\":\"Finding number $i\",\"category\":\"review\",\"status\":\"open\",\"deferred_at\":\"2026-05-$(printf '%02d' $((i % 28 + 1)))T12:00:00Z\",\"resolved_at\":null,\"resolution\":null}"
done
findings_json+=']}'
echo "$findings_json" > "$inv004a_dir/.correctless/meta/deferred-findings.json"

if [ -x "$INTEL_SCRIPT" ]; then
  output=$(run_intel "$inv004a_dir")
  total_entries=$(echo "$output" | jq '[.sections[] | length] | add' 2>/dev/null)
  truncated=$(echo "$output" | jq -r '.truncated_count' 2>/dev/null)
  if [ "$total_entries" -le 30 ] 2>/dev/null && [ "$truncated" -gt 0 ] 2>/dev/null; then
    pass "INV-004a" "total entries capped at 30 (got $total_entries), truncated_count=$truncated"
  else
    fail "INV-004a" "cap not enforced (total=$total_entries, truncated=$truncated)"
  fi
else
  fail "INV-004a" "script not executable"
fi

# INV-004b: Per-section minimum — each non-empty section retains at least 1 entry
inv004b_dir=$(mkworkdir inv004b)
setup_fixture_dirs "$inv004b_dir"
# 28 deferred findings + 1 devadv + 1 override + 1 debug
findings_json='{"schema_version":1,"findings":['
for i in $(seq 1 28); do
  [ $i -gt 1 ] && findings_json+=","
  findings_json+="{\"id\":\"DF-$(printf '%03d' "$i")\",\"source_file\":\".correctless/artifacts/f.md\",\"finding_id\":\"RS-001\",\"feature\":\"feat-$i\",\"severity\":\"MEDIUM\",\"description\":\"Finding $i\",\"category\":\"review\",\"status\":\"open\",\"deferred_at\":\"2026-05-$(printf '%02d' $((i % 28 + 1)))T12:00:00Z\",\"resolved_at\":null,\"resolution\":null}"
done
findings_json+=']}'
echo "$findings_json" > "$inv004b_dir/.correctless/meta/deferred-findings.json"
write_devadv_report_inline "$inv004b_dir" "2026-05-01"
write_debug_investigation "$inv004b_dir"

if [ -x "$INTEL_SCRIPT" ]; then
  output=$(run_intel "$inv004b_dir")
  devadv_count=$(echo "$output" | jq '.sections.devadv_themes | length' 2>/dev/null)
  debug_count=$(echo "$output" | jq '.sections.debug_clusters | length' 2>/dev/null)
  total=$(echo "$output" | jq '[.sections[] | length] | add' 2>/dev/null)
  if [ "$devadv_count" -ge 1 ] 2>/dev/null && [ "$debug_count" -ge 1 ] 2>/dev/null && [ "$total" -le 30 ] 2>/dev/null; then
    pass "INV-004b" "per-section minimum preserved (devadv=$devadv_count, debug=$debug_count, total=$total)"
  else
    fail "INV-004b" "per-section minimum violated (devadv=$devadv_count, debug=$debug_count, total=$total)"
  fi
else
  fail "INV-004b" "script not executable"
fi


# ============================================================================
# INV-005 [unit]: Output schema
# ============================================================================

section "INV-005: Output schema"

# INV-005a: Output is valid JSON with all required top-level fields
inv005a_dir=$(mkworkdir inv005a)
setup_fixture_dirs "$inv005a_dir"
write_deferred_findings "$inv005a_dir"

if [ -x "$INTEL_SCRIPT" ]; then
  output=$(run_intel "$inv005a_dir")
  schema_ok=true
  echo "$output" | jq -e '.schema_version == 1' >/dev/null 2>&1 || schema_ok=false
  echo "$output" | jq -e '.generated_at' >/dev/null 2>&1 || schema_ok=false
  echo "$output" | jq -e '.scope' >/dev/null 2>&1 || schema_ok=false
  echo "$output" | jq -e '.truncated_count >= 0' >/dev/null 2>&1 || schema_ok=false
  echo "$output" | jq -e '.warnings | type == "array"' >/dev/null 2>&1 || schema_ok=false
  echo "$output" | jq -e '.sections' >/dev/null 2>&1 || schema_ok=false

  if $schema_ok; then
    pass "INV-005a" "output has all required top-level fields"
  else
    fail "INV-005a" "output missing required top-level fields"
  fi
else
  fail "INV-005a" "script not executable"
fi

# INV-005b: Each section entry has required fields (source, date, summary, file_refs, severity, id)
if [ -x "$INTEL_SCRIPT" ]; then
  # Reuse output from inv005a
  entry_ok=true
  echo "$output" | jq -e '.sections.deferred_findings[0].source' >/dev/null 2>&1 || entry_ok=false
  echo "$output" | jq -e '.sections.deferred_findings[0].date' >/dev/null 2>&1 || entry_ok=false
  echo "$output" | jq -e '.sections.deferred_findings[0].summary' >/dev/null 2>&1 || entry_ok=false
  echo "$output" | jq -e '.sections.deferred_findings[0].file_refs | type == "array"' >/dev/null 2>&1 || entry_ok=false
  echo "$output" | jq -e '.sections.deferred_findings[0] | has("severity")' >/dev/null 2>&1 || entry_ok=false
  echo "$output" | jq -e '.sections.deferred_findings[0].id' >/dev/null 2>&1 || entry_ok=false

  if $entry_ok; then
    pass "INV-005b" "section entries have all required fields"
  else
    fail "INV-005b" "section entries missing required fields"
  fi
else
  fail "INV-005b" "script not executable"
fi

# INV-005c: Entry summary truncated to 200 chars max
inv005c_dir=$(mkworkdir inv005c)
setup_fixture_dirs "$inv005c_dir"
long_desc=$(python3 -c "print('X' * 300)" 2>/dev/null || head -c 300 < /dev/zero | tr '\0' 'X')
cat > "$inv005c_dir/.correctless/meta/deferred-findings.json" << FIXTURE
{
  "schema_version": 1,
  "findings": [
    {
      "id": "DF-001",
      "source_file": ".correctless/artifacts/f.md",
      "finding_id": "RS-001",
      "feature": "long",
      "severity": "MEDIUM",
      "description": "${long_desc}",
      "category": "review",
      "status": "open",
      "deferred_at": "2026-05-20T12:00:00Z",
      "resolved_at": null,
      "resolution": null
    }
  ]
}
FIXTURE

if [ -x "$INTEL_SCRIPT" ]; then
  output=$(run_intel "$inv005c_dir")
  summary_len=$(echo "$output" | jq -r '.sections.deferred_findings[0].summary | length' 2>/dev/null)
  if [ "$summary_len" -le 200 ] 2>/dev/null; then
    pass "INV-005c" "entry summary truncated to 200 chars (got $summary_len)"
  else
    fail "INV-005c" "entry summary exceeds 200 chars (got $summary_len)"
  fi
else
  fail "INV-005c" "script not executable"
fi

# INV-005d: All 6 section keys present in output
if [ -x "$INTEL_SCRIPT" ]; then
  inv005d_dir=$(mkworkdir inv005d)
  setup_fixture_dirs "$inv005d_dir"
  output=$(run_intel "$inv005d_dir")
  sections_ok=true
  for section in deferred_findings devadv_themes override_patterns lens_recommendations debug_clusters phase_effectiveness; do
    echo "$output" | jq -e ".sections.$section | type == \"array\"" >/dev/null 2>&1 || sections_ok=false
  done
  if $sections_ok; then
    pass "INV-005d" "all 6 section keys present (including empty arrays)"
  else
    fail "INV-005d" "missing section keys in output"
  fi
else
  fail "INV-005d" "script not executable"
fi

# INV-005e: Warnings array populated for malformed sources
inv005e_dir=$(mkworkdir inv005e)
setup_fixture_dirs "$inv005e_dir"
echo "NOT VALID JSON{{{" > "$inv005e_dir/.correctless/meta/deferred-findings.json"

if [ -x "$INTEL_SCRIPT" ]; then
  output=$(run_intel "$inv005e_dir")
  warning_count=$(echo "$output" | jq '.warnings | length' 2>/dev/null)
  if [ "$warning_count" -gt 0 ] 2>/dev/null; then
    pass "INV-005e" "warnings populated for malformed sources ($warning_count warnings)"
  else
    fail "INV-005e" "no warnings for malformed source file"
  fi
else
  fail "INV-005e" "script not executable"
fi


# ============================================================================
# INV-006 [unit]: /cspec reads brief after first brainstorm exchange
# ============================================================================

section "INV-006: /cspec reads brief after brainstorm"

# INV-006a: cspec SKILL.md references cross-feature-intel.sh invocation
if grep -q "cross-feature-intel.sh" "$CSPEC_SKILL" 2>/dev/null; then
  pass "INV-006a" "cspec SKILL.md references cross-feature-intel.sh"
else
  fail "INV-006a" "cspec SKILL.md does not reference cross-feature-intel.sh"
fi

# INV-006b: cspec SKILL.md includes --scope argument in invocation
if grep -q "\-\-scope" "$CSPEC_SKILL" 2>/dev/null; then
  pass "INV-006b" "cspec SKILL.md includes --scope argument"
else
  fail "INV-006b" "cspec SKILL.md does not include --scope argument"
fi

# INV-006c: cspec allowed-tools includes Bash(*cross-feature-intel*) pattern
if grep -qE "Bash\(\*cross-feature-intel\*\)" "$CSPEC_SKILL" 2>/dev/null; then
  pass "INV-006c" "cspec allowed-tools includes cross-feature-intel Bash pattern"
else
  fail "INV-006c" "cspec allowed-tools missing cross-feature-intel Bash pattern (RS-004)"
fi

# INV-006d: Invocation does NOT use 2>/dev/null (stderr warnings must be captured)
if grep -q "cross-feature-intel" "$CSPEC_SKILL" 2>/dev/null; then
  if ! grep "cross-feature-intel" "$CSPEC_SKILL" | grep -q "2>/dev/null"; then
    pass "INV-006d" "cspec does not suppress stderr from cross-feature-intel invocation"
  else
    fail "INV-006d" "cspec uses 2>/dev/null on cross-feature-intel invocation"
  fi
else
  fail "INV-006d" "cspec does not reference cross-feature-intel at all"
fi

# INV-006e: Presentation includes "context, not constraints" framing
if grep -q "context, not constraints" "$CSPEC_SKILL" 2>/dev/null; then
  pass "INV-006e" "cspec includes 'context, not constraints' framing"
else
  fail "INV-006e" "cspec missing 'context, not constraints' framing"
fi

# INV-006f: Presentation includes truncation note when truncated_count > 0
if grep -qE "truncated_count|older entries excluded" "$CSPEC_SKILL" 2>/dev/null; then
  pass "INV-006f" "cspec references truncation count in presentation"
else
  fail "INV-006f" "cspec missing truncation count presentation logic"
fi


# ============================================================================
# INV-007 [unit]: Anti-anchoring directive with calibration
# ============================================================================

section "INV-007: Anti-anchoring directive"

# INV-007a: Anti-anchoring directive text present in cspec SKILL.md
if grep -q "advisory context from prior workflow runs" "$CSPEC_SKILL" 2>/dev/null; then
  pass "INV-007a" "anti-anchoring directive present in cspec"
else
  fail "INV-007a" "anti-anchoring directive missing from cspec"
fi

# INV-007b: Calibration examples present (when to weight highly, when to dismiss)
inv007b_ok=true
grep -q "Weight intelligence highly when" "$CSPEC_SKILL" 2>/dev/null || inv007b_ok=false
grep -q "Dismiss when" "$CSPEC_SKILL" 2>/dev/null || inv007b_ok=false
if $inv007b_ok; then
  pass "INV-007b" "calibration examples present (weight highly + dismiss)"
else
  fail "INV-007b" "calibration examples missing from cspec"
fi

# INV-007c: Anti-anchoring directive appears before Step 1 (brainstorm questions end at Step 1)
# The spec says the directive must appear "before the brainstorm questions" meaning it must be
# positioned in the flow between Step 0 and Step 1. We verify it appears before Step 1.
if [ -f "$CSPEC_SKILL" ]; then
  anchoring_line=$(grep -n "advisory context from prior workflow runs" "$CSPEC_SKILL" 2>/dev/null | head -1 | cut -d: -f1)
  step1_line=$(grep -n "### Step 1:" "$CSPEC_SKILL" 2>/dev/null | head -1 | cut -d: -f1)
  if [ -n "$anchoring_line" ] && [ -n "$step1_line" ] && [ "$anchoring_line" -lt "$step1_line" ] 2>/dev/null; then
    pass "INV-007c" "anti-anchoring directive appears before Step 1 (brainstorm section)"
  else
    fail "INV-007c" "anti-anchoring directive not positioned before Step 1 (anchoring=$anchoring_line, step1=$step1_line)"
  fi
else
  fail "INV-007c" "cspec SKILL.md not found"
fi


# ============================================================================
# INV-008 [unit]: Deferred findings extraction
# ============================================================================

section "INV-008: Deferred findings extraction"

inv008_dir=$(mkworkdir inv008)
setup_fixture_dirs "$inv008_dir"
write_deferred_findings "$inv008_dir"

if [ -x "$INTEL_SCRIPT" ]; then
  output=$(run_intel "$inv008_dir")

  # INV-008a: Only open findings extracted
  open_count=$(echo "$output" | jq '[.sections.deferred_findings[] | select(.id == "DF-001" or .id == "DF-003")] | length' 2>/dev/null)
  resolved_present=$(echo "$output" | jq '[.sections.deferred_findings[] | select(.id == "DF-002")] | length' 2>/dev/null)
  if [ "$open_count" = "2" ] && [ "$resolved_present" = "0" ]; then
    pass "INV-008a" "only open findings extracted, resolved excluded"
  else
    fail "INV-008a" "filtering wrong (open=$open_count, resolved_present=$resolved_present)"
  fi

  # INV-008b: Correct field mapping
  first_id=$(echo "$output" | jq -r '.sections.deferred_findings[0].id' 2>/dev/null)
  first_severity=$(echo "$output" | jq -r '.sections.deferred_findings[0].severity' 2>/dev/null)
  first_date=$(echo "$output" | jq -r '.sections.deferred_findings[0].date' 2>/dev/null)
  first_file_refs=$(echo "$output" | jq -r '.sections.deferred_findings[0].file_refs | length' 2>/dev/null)
  if [[ "$first_id" == DF-* ]] && [ -n "$first_severity" ] && [ -n "$first_date" ] && [ "$first_file_refs" = "0" ]; then
    pass "INV-008b" "deferred findings field mapping correct (id=$first_id, severity=$first_severity, empty file_refs)"
  else
    fail "INV-008b" "field mapping wrong (id=$first_id, severity=$first_severity, date=$first_date, file_refs=$first_file_refs)"
  fi
else
  fail "INV-008a" "script not executable"
  fail "INV-008b" "script not executable"
fi


# ============================================================================
# INV-009 [unit]: Devil's Advocate theme extraction
# ============================================================================

section "INV-009: DevAdv theme extraction"

inv009_dir=$(mkworkdir inv009)
setup_fixture_dirs "$inv009_dir"
write_devadv_report_inline "$inv009_dir" "2026-05-10"
write_devadv_report_subsection "$inv009_dir" "2026-05-16"

if [ -x "$INTEL_SCRIPT" ]; then
  output=$(run_intel "$inv009_dir")

  # INV-009a: DA-NNN headings extracted
  da_ids=$(echo "$output" | jq -r '.sections.devadv_themes[].id' 2>/dev/null | sort)
  expected_ids=$'DA-001\nDA-002\nDA-003\nDA-004'
  if [ "$da_ids" = "$expected_ids" ]; then
    pass "INV-009a" "all DA-NNN headings extracted from both report formats"
  else
    fail "INV-009a" "DA headings mismatch (got: $(echo "$da_ids" | tr '\n' ','))"
  fi

  # INV-009b: Inline severity format parsed correctly (older report)
  da001_severity=$(echo "$output" | jq -r '.sections.devadv_themes[] | select(.id == "DA-001") | .severity' 2>/dev/null)
  if [ "$da001_severity" = "architecture" ]; then
    pass "INV-009b" "inline severity format parsed (DA-001: $da001_severity)"
  else
    fail "INV-009b" "inline severity not parsed (expected architecture, got $da001_severity)"
  fi

  # INV-009c: Subsection severity format parsed correctly (newer report)
  da003_severity=$(echo "$output" | jq -r '.sections.devadv_themes[] | select(.id == "DA-003") | .severity' 2>/dev/null)
  if [ "$da003_severity" = "architecture" ]; then
    pass "INV-009c" "subsection severity format parsed (DA-003: $da003_severity)"
  else
    fail "INV-009c" "subsection severity not parsed (expected architecture, got $da003_severity)"
  fi

  # INV-009d: Date parsed from filename
  da001_date=$(echo "$output" | jq -r '.sections.devadv_themes[] | select(.id == "DA-001") | .date' 2>/dev/null)
  if [[ "$da001_date" == "2026-05-10"* ]]; then
    pass "INV-009d" "date parsed from filename ($da001_date)"
  else
    fail "INV-009d" "date not parsed from filename (got $da001_date)"
  fi

  # INV-009e: file_refs is empty (devadv is project-wide)
  da001_refs=$(echo "$output" | jq -r '.sections.devadv_themes[0].file_refs | length' 2>/dev/null)
  if [ "$da001_refs" = "0" ]; then
    pass "INV-009e" "devadv entries have empty file_refs"
  else
    fail "INV-009e" "devadv entries should have empty file_refs (got $da001_refs)"
  fi
else
  fail "INV-009a" "script not executable"
  fail "INV-009b" "script not executable"
  fail "INV-009c" "script not executable"
  fail "INV-009d" "script not executable"
  fail "INV-009e" "script not executable"
fi


# ============================================================================
# INV-010 [unit]: Override pattern extraction
# ============================================================================

section "INV-010: Override pattern extraction"

inv010_dir=$(mkworkdir inv010)
setup_fixture_dirs "$inv010_dir"
write_overrides "$inv010_dir"

if [ -x "$INTEL_SCRIPT" ]; then
  output=$(run_intel "$inv010_dir")

  # INV-010a: Override entries extracted
  override_count=$(echo "$output" | jq '.sections.override_patterns | length' 2>/dev/null)
  if [ "$override_count" -gt 0 ] 2>/dev/null; then
    pass "INV-010a" "override entries extracted ($override_count)"
  else
    fail "INV-010a" "no override entries extracted"
  fi

  # INV-010b: Duplicate reasons collapsed with count field
  # "Pre-existing test failure unrelated to feature" appears twice in feature-a
  collapsed_entry=$(echo "$output" | jq '.sections.override_patterns[] | select(.count > 1)' 2>/dev/null)
  if [ -n "$collapsed_entry" ]; then
    collapsed_count=$(echo "$collapsed_entry" | jq -r '.count' 2>/dev/null)
    pass "INV-010b" "duplicate override reasons collapsed (count=$collapsed_count)"
  else
    fail "INV-010b" "duplicate override reasons not collapsed"
  fi

  # INV-010c: Override id is hash of reason (first 8 chars of sha256)
  first_id=$(echo "$output" | jq -r '.sections.override_patterns[0].id' 2>/dev/null)
  if [[ "$first_id" =~ ^[a-f0-9]{8}$ ]]; then
    pass "INV-010c" "override id is 8-char hex hash ($first_id)"
  else
    fail "INV-010c" "override id not 8-char hex hash (got $first_id)"
  fi

  # INV-010d: file_refs is empty (overrides are workflow-level)
  first_refs=$(echo "$output" | jq -r '.sections.override_patterns[0].file_refs | length' 2>/dev/null)
  if [ "$first_refs" = "0" ]; then
    pass "INV-010d" "override entries have empty file_refs"
  else
    fail "INV-010d" "override entries should have empty file_refs (got $first_refs)"
  fi
else
  fail "INV-010a" "script not executable"
  fail "INV-010b" "script not executable"
  fail "INV-010c" "script not executable"
  fail "INV-010d" "script not executable"
fi


# ============================================================================
# INV-011 [unit]: Lens recommendation extraction
# ============================================================================

section "INV-011: Lens recommendation extraction"

inv011_dir=$(mkworkdir inv011)
setup_fixture_dirs "$inv011_dir"
write_lens_recommendations "$inv011_dir"

if [ -x "$INTEL_SCRIPT" ]; then
  output=$(run_intel "$inv011_dir")

  # INV-011a: Lens recommendations extracted
  lens_count=$(echo "$output" | jq '.sections.lens_recommendations | length' 2>/dev/null)
  if [ "$lens_count" -gt 0 ] 2>/dev/null; then
    pass "INV-011a" "lens recommendations extracted ($lens_count)"
  else
    fail "INV-011a" "no lens recommendations extracted"
  fi

  # INV-011b: Same lens_name collapsed with count
  hostile_entry=$(echo "$output" | jq '.sections.lens_recommendations[] | select(.id == "hostile-input")' 2>/dev/null)
  hostile_count=$(echo "$hostile_entry" | jq -r '.count' 2>/dev/null)
  if [ "$hostile_count" = "3" ]; then
    pass "INV-011b" "duplicate lens names collapsed (hostile-input count=$hostile_count)"
  else
    fail "INV-011b" "lens names not collapsed correctly (hostile-input count=$hostile_count)"
  fi

  # INV-011c: Count >= 3 flagged with promotion_candidate: true
  promotion=$(echo "$hostile_entry" | jq -r '.promotion_candidate' 2>/dev/null)
  if [ "$promotion" = "true" ]; then
    pass "INV-011c" "hostile-input (count=3) flagged as promotion_candidate"
  else
    fail "INV-011c" "hostile-input not flagged as promotion_candidate (got $promotion)"
  fi

  # INV-011d: Count < 3 NOT flagged with promotion_candidate
  other_entry=$(echo "$output" | jq '.sections.lens_recommendations[] | select(.id == "upgrade-compatibility")' 2>/dev/null)
  other_promotion=$(echo "$other_entry" | jq -r '.promotion_candidate // "absent"' 2>/dev/null)
  if [ "$other_promotion" != "true" ]; then
    pass "INV-011d" "upgrade-compatibility (count<3) not flagged as promotion_candidate"
  else
    fail "INV-011d" "upgrade-compatibility incorrectly flagged as promotion_candidate"
  fi
else
  fail "INV-011a" "script not executable"
  fail "INV-011b" "script not executable"
  fail "INV-011c" "script not executable"
  fail "INV-011d" "script not executable"
fi


# ============================================================================
# INV-012 [unit]: Debug investigation extraction
# ============================================================================

section "INV-012: Debug investigation extraction"

inv012_dir=$(mkworkdir inv012)
setup_fixture_dirs "$inv012_dir"
write_debug_investigation "$inv012_dir"

if [ -x "$INTEL_SCRIPT" ]; then
  output=$(run_intel "$inv012_dir")

  # INV-012a: Debug investigation extracted
  debug_count=$(echo "$output" | jq '.sections.debug_clusters | length' 2>/dev/null)
  if [ "$debug_count" -gt 0 ] 2>/dev/null; then
    pass "INV-012a" "debug investigation extracted ($debug_count)"
  else
    fail "INV-012a" "no debug investigation extracted"
  fi

  # INV-012b: ID is filename slug
  debug_id=$(echo "$output" | jq -r '.sections.debug_clusters[0].id' 2>/dev/null)
  if [ "$debug_id" = "statusline" ]; then
    pass "INV-012b" "debug id is filename slug ($debug_id)"
  else
    fail "INV-012b" "debug id not filename slug (expected 'statusline', got $debug_id)"
  fi

  # INV-012c: Summary from Root Cause heading
  debug_summary=$(echo "$output" | jq -r '.sections.debug_clusters[0].summary' 2>/dev/null)
  if echo "$debug_summary" | grep -qi "register_hooks\|early-return\|workflow-gate"; then
    pass "INV-012c" "debug summary extracted from Root Cause heading"
  else
    fail "INV-012c" "debug summary does not contain Root Cause content (got: $debug_summary)"
  fi

  # INV-012d: file_refs extracted from Fix/Class Fix sections via regex
  debug_refs=$(echo "$output" | jq -r '.sections.debug_clusters[0].file_refs[]' 2>/dev/null)
  if echo "$debug_refs" | grep -q "hooks/workflow-gate.sh\|tests/test-core.sh"; then
    pass "INV-012d" "file_refs extracted from Fix/Class Fix sections"
  else
    fail "INV-012d" "file_refs not extracted correctly (got: $debug_refs)"
  fi
else
  fail "INV-012a" "script not executable"
  fail "INV-012b" "script not executable"
  fail "INV-012c" "script not executable"
  fail "INV-012d" "script not executable"
fi


# ============================================================================
# INV-013 [unit]: Script is PAT-003 compliant
# ============================================================================

section "INV-013: PAT-003 compliance"

# INV-013a: Script lives in scripts/
if [ -f "$INTEL_SCRIPT" ]; then
  pass "INV-013a" "script lives in scripts/ directory"
else
  fail "INV-013a" "script not found in scripts/"
fi

# INV-013b: Script sources lib.sh
if [ -f "$INTEL_SCRIPT" ] && grep -q "source.*lib\.sh\|\..*lib\.sh" "$INTEL_SCRIPT" 2>/dev/null; then
  pass "INV-013b" "script sources lib.sh"
else
  fail "INV-013b" "script does not source lib.sh"
fi

# INV-013c: Script exits 0 always (informational)
if [ -x "$INTEL_SCRIPT" ]; then
  inv013c_dir=$(mkworkdir inv013c)
  setup_fixture_dirs "$inv013c_dir"
  bash "$INTEL_SCRIPT" --base "$inv013c_dir/.correctless" >/dev/null 2>&1
  rc=$?
  if [ $rc -eq 0 ]; then
    pass "INV-013c" "script exits 0"
  else
    fail "INV-013c" "script exits $rc (should always exit 0)"
  fi
else
  fail "INV-013c" "script not executable"
fi

# INV-013d: Script accepts CLI arguments (not stdin JSON)
if [ -f "$INTEL_SCRIPT" ] && grep -q "\-\-base\|\-\-scope" "$INTEL_SCRIPT" 2>/dev/null; then
  pass "INV-013d" "script accepts CLI arguments"
else
  fail "INV-013d" "script does not accept CLI arguments (--base, --scope)"
fi

# INV-013e: Script has proper shebang
if [ -f "$INTEL_SCRIPT" ]; then
  shebang=$(head -1 "$INTEL_SCRIPT")
  if [[ "$shebang" == "#!/usr/bin/env bash"* ]] || [[ "$shebang" == "#!/bin/bash"* ]]; then
    pass "INV-013e" "script has proper bash shebang"
  else
    fail "INV-013e" "script has wrong shebang: $shebang"
  fi
else
  fail "INV-013e" "script not found"
fi


# ============================================================================
# INV-014 [unit]: /cstatus intelligence health
# ============================================================================

section "INV-014: /cstatus intelligence health"

# INV-014a: cstatus SKILL.md references cross-feature-intel
if grep -q "cross-feature-intel\|Cross-Feature Intelligence" "$CSTATUS_SKILL" 2>/dev/null; then
  pass "INV-014a" "cstatus references cross-feature intelligence"
else
  fail "INV-014a" "cstatus does not reference cross-feature intelligence"
fi

# INV-014b: cstatus includes staleness threshold (7 days)
if grep -qE "7.day|seven.day|staleness" "$CSTATUS_SKILL" 2>/dev/null; then
  pass "INV-014b" "cstatus includes staleness threshold reference"
else
  fail "INV-014b" "cstatus missing staleness threshold reference"
fi

# INV-014c: cstatus includes "No data" state messaging
if grep -q "No cross-feature intelligence\|no.*intelligence.*available\|data accumulates" "$CSTATUS_SKILL" 2>/dev/null; then
  pass "INV-014c" "cstatus includes no-data state messaging"
else
  fail "INV-014c" "cstatus missing no-data state messaging"
fi

# INV-014d: cstatus includes remediation for stale brief
if grep -q "cross-feature-intel.sh\|will refresh" "$CSTATUS_SKILL" 2>/dev/null; then
  pass "INV-014d" "cstatus includes remediation for stale brief"
else
  fail "INV-014d" "cstatus missing remediation for stale brief"
fi


# ============================================================================
# INV-015 [unit]: Setup installs the script
# ============================================================================

section "INV-015: Setup installs the script"

# INV-015a: Setup glob pattern covers scripts/*.sh (includes cross-feature-intel.sh)
# The glob pattern `for script in "$SCRIPT_DIR"/scripts/*.sh` covers all scripts
if grep -qE 'scripts/\*\.sh' "$SETUP_SCRIPT" 2>/dev/null; then
  pass "INV-015a" "setup uses glob pattern that covers all scripts/*.sh"
else
  fail "INV-015a" "setup missing glob pattern for scripts/*.sh"
fi

# INV-015b: Script exists so the glob will find it
if [ -f "$INTEL_SCRIPT" ]; then
  pass "INV-015b" "cross-feature-intel.sh exists for glob-based install"
else
  fail "INV-015b" "cross-feature-intel.sh does not exist (glob install will skip it)"
fi

# INV-015c: Sync script propagates scripts to distribution
if grep -q "scripts/" "$SYNC_SCRIPT" 2>/dev/null; then
  pass "INV-015c" "sync.sh handles scripts directory"
else
  fail "INV-015c" "sync.sh missing scripts directory handling"
fi


# ============================================================================
# INV-016 [unit]: Phase effectiveness extraction
# ============================================================================

section "INV-016: Phase effectiveness extraction"

inv016_dir=$(mkworkdir inv016)
setup_fixture_dirs "$inv016_dir"
write_workflow_effectiveness "$inv016_dir"

if [ -x "$INTEL_SCRIPT" ]; then
  output=$(run_intel "$inv016_dir")

  # INV-016a: Phase effectiveness entries extracted
  pe_count=$(echo "$output" | jq '.sections.phase_effectiveness | length' 2>/dev/null)
  if [ "$pe_count" -gt 0 ] 2>/dev/null; then
    pass "INV-016a" "phase effectiveness entries extracted ($pe_count)"
  else
    fail "INV-016a" "no phase effectiveness entries extracted"
  fi

  # INV-016b: Entries collapsed by phase_that_should_have_caught
  # PMB-003 and PMB-005 both have phase_that_should_have_caught: "spec"
  spec_entry=$(echo "$output" | jq '.sections.phase_effectiveness[] | select(.id == "spec")' 2>/dev/null)
  spec_count=$(echo "$spec_entry" | jq -r '.count' 2>/dev/null)
  if [ "$spec_count" = "2" ]; then
    pass "INV-016b" "entries collapsed by phase (spec count=$spec_count)"
  else
    fail "INV-016b" "entries not collapsed by phase (spec count=$spec_count, expected 2)"
  fi

  # INV-016c: Summary includes severity and description
  spec_summary=$(echo "$spec_entry" | jq -r '.summary' 2>/dev/null)
  if echo "$spec_summary" | grep -qi "bug.*missed\|missed.*by.*spec\|phase"; then
    pass "INV-016c" "phase effectiveness summary includes severity/description info"
  else
    fail "INV-016c" "summary format wrong (got: $spec_summary)"
  fi

  # INV-016d: Uses real workflow-effectiveness.json field names (AP-031 guard)
  if [ -f "$INTEL_SCRIPT" ] && grep -q "phase_that_should_have_caught" "$INTEL_SCRIPT" 2>/dev/null; then
    pass "INV-016d" "script uses real field name 'phase_that_should_have_caught' (AP-031)"
  else
    fail "INV-016d" "script uses wrong field name (should be 'phase_that_should_have_caught' per AP-031)"
  fi

  # INV-016e: Audit entry extracted (PMB-001)
  audit_entry=$(echo "$output" | jq '.sections.phase_effectiveness[] | select(.id == "audit")' 2>/dev/null)
  if [ -n "$audit_entry" ]; then
    pass "INV-016e" "audit phase entry extracted from PMB-001"
  else
    fail "INV-016e" "audit phase entry not extracted"
  fi
else
  fail "INV-016a" "script not executable"
  fail "INV-016b" "script not executable"
  fail "INV-016c" "script not executable"
  fail "INV-016d" "script not executable"
  fail "INV-016e" "script not executable"
fi


# ============================================================================
# PRH-001: Intelligence brief must not gate any phase transition
# ============================================================================

section "PRH-001: Brief must not gate phase transitions"

# PRH-001a: workflow-advance.sh does not reference cross-feature-intel
if ! grep -q "cross-feature-intel" "$WORKFLOW_ADVANCE" 2>/dev/null; then
  pass "PRH-001a" "workflow-advance.sh does not reference cross-feature-intel"
else
  fail "PRH-001a" "workflow-advance.sh references cross-feature-intel (prohibited)"
fi

# PRH-001b: scripts/wf/*.sh do not reference cross-feature-intel
wf_refs=$(grep -rl "cross-feature-intel" "$REPO_DIR/scripts/wf/" 2>/dev/null)
if [ -z "$wf_refs" ]; then
  pass "PRH-001b" "scripts/wf/*.sh do not reference cross-feature-intel"
else
  fail "PRH-001b" "scripts/wf/ references cross-feature-intel: $wf_refs"
fi


# ============================================================================
# PRH-002: /cspec must not write to the brief
# ============================================================================

section "PRH-002: /cspec must not write to brief"

# PRH-002a: cspec SKILL.md does not write/append/create cross-feature-intel
# Exclude the allowed-tools frontmatter line (which legitimately contains both
# "cross-feature-intel" and "Write" on the same line for tool declarations)
if [ -f "$CSPEC_SKILL" ]; then
  write_refs=$(grep -n "cross-feature-intel" "$CSPEC_SKILL" 2>/dev/null \
    | grep -v "^[0-9]*:allowed-tools:" \
    | grep -iE "write.*cross-feature-intel\.json|append.*cross-feature-intel|create.*cross-feature-intel|echo.*>.*cross-feature-intel|cat.*>.*cross-feature-intel" || true)
  if [ -z "$write_refs" ]; then
    pass "PRH-002a" "cspec does not write to cross-feature-intel brief"
  else
    fail "PRH-002a" "cspec appears to write to cross-feature-intel: $write_refs"
  fi
else
  pass "PRH-002a" "cspec SKILL.md not yet modified (no write possible)"
fi


# ============================================================================
# PRH-003: Brief content must not be interpolated into spec rules
# ============================================================================

section "PRH-003: Brief content not interpolated into rules"

# PRH-003a: Anti-anchoring directive mentions "not constraints" or similar
if grep -q "context, not constraints\|not.*template.*invariants\|not.*copy.*into" "$CSPEC_SKILL" 2>/dev/null; then
  pass "PRH-003a" "anti-anchoring directive prevents interpolation"
else
  fail "PRH-003a" "missing interpolation prevention in anti-anchoring directive"
fi


# ============================================================================
# BND-001: Zero data sources have content
# ============================================================================

section "BND-001: Zero data sources"

bnd001_dir=$(mkworkdir bnd001)
setup_fixture_dirs "$bnd001_dir"
# All directories empty — no source files

if [ -x "$INTEL_SCRIPT" ]; then
  output=$(run_intel "$bnd001_dir")
  rc=$?

  # BND-001a: Valid JSON output
  if [ $rc -eq 0 ] && echo "$output" | jq -e '.' >/dev/null 2>&1; then
    pass "BND-001a" "valid JSON output with zero data sources"
  else
    fail "BND-001a" "invalid output with zero data sources (rc=$rc)"
  fi

  # BND-001b: All 6 sections are empty arrays
  all_empty=true
  for section in deferred_findings devadv_themes override_patterns lens_recommendations debug_clusters phase_effectiveness; do
    count=$(echo "$output" | jq ".sections.$section | length" 2>/dev/null)
    if [ "$count" != "0" ] 2>/dev/null; then
      all_empty=false
    fi
  done
  if $all_empty; then
    pass "BND-001b" "all 6 sections are empty arrays when no data sources exist"
  else
    fail "BND-001b" "some sections non-empty when no data sources exist"
  fi

  # BND-001c: warnings array is empty
  warning_count=$(echo "$output" | jq '.warnings | length' 2>/dev/null)
  if [ "$warning_count" = "0" ]; then
    pass "BND-001c" "warnings array empty when no data sources present"
  else
    fail "BND-001c" "unexpected warnings with no data sources ($warning_count)"
  fi
else
  fail "BND-001a" "script not executable"
  fail "BND-001b" "script not executable"
  fail "BND-001c" "script not executable"
fi


# ============================================================================
# BND-002: All entries filtered out by scope
# ============================================================================

section "BND-002: All entries filtered out by scope"

bnd002_dir=$(mkworkdir bnd002)
setup_fixture_dirs "$bnd002_dir"
write_debug_investigation "$bnd002_dir"
# Only debug investigations have file_refs — use a scope that doesn't match

if [ -x "$INTEL_SCRIPT" ]; then
  output=$(run_intel "$bnd002_dir" --scope "totally/different/path.go")
  debug_count=$(echo "$output" | jq '.sections.debug_clusters | length' 2>/dev/null)
  if [ "$debug_count" = "0" ]; then
    pass "BND-002" "entries with non-matching file_refs excluded by scope filter"
  else
    fail "BND-002" "debug_clusters should be empty for non-matching scope (got $debug_count)"
  fi
else
  fail "BND-002" "script not executable"
fi


# ============================================================================
# BND-003: Malformed source files
# ============================================================================

section "BND-003: Malformed source files"

bnd003_dir=$(mkworkdir bnd003)
setup_fixture_dirs "$bnd003_dir"
echo "THIS IS NOT JSON!!!" > "$bnd003_dir/.correctless/meta/deferred-findings.json"
write_devadv_report_inline "$bnd003_dir" "2026-05-10"

if [ -x "$INTEL_SCRIPT" ]; then
  output=$(run_intel "$bnd003_dir")
  rc=$?

  # BND-003a: Script does not crash on malformed input
  if [ $rc -eq 0 ]; then
    pass "BND-003a" "script exits 0 despite malformed deferred-findings.json"
  else
    fail "BND-003a" "script crashed on malformed input (rc=$rc)"
  fi

  # BND-003b: Warning added to warnings array
  warning_count=$(echo "$output" | jq '.warnings | length' 2>/dev/null)
  if [ "$warning_count" -gt 0 ] 2>/dev/null; then
    pass "BND-003b" "warning added for malformed source ($warning_count warnings)"
  else
    fail "BND-003b" "no warning added for malformed deferred-findings.json"
  fi

  # BND-003c: Other sources still processed (devadv should work)
  devadv_count=$(echo "$output" | jq '.sections.devadv_themes | length' 2>/dev/null)
  if [ "$devadv_count" -gt 0 ] 2>/dev/null; then
    pass "BND-003c" "other sources still processed after malformed source skipped"
  else
    fail "BND-003c" "other sources not processed after malformed source"
  fi

  # BND-003d: Warning text is descriptive
  warning_text=$(echo "$output" | jq -r '.warnings[0]' 2>/dev/null)
  if echo "$warning_text" | grep -qi "deferred-findings\|invalid\|corrupt\|malformed\|skip"; then
    pass "BND-003d" "warning text is descriptive ($warning_text)"
  else
    fail "BND-003d" "warning text not descriptive (got: $warning_text)"
  fi
else
  fail "BND-003a" "script not executable"
  fail "BND-003b" "script not executable"
  fail "BND-003c" "script not executable"
  fail "BND-003d" "script not executable"
fi


# ============================================================================
# EA-001: jq availability check
# ============================================================================

section "EA-001: jq availability"

# EA-001a: Script handles missing jq gracefully
if [ -f "$INTEL_SCRIPT" ]; then
  if grep -qE 'jq.*not found|command -v jq|which jq' "$INTEL_SCRIPT" 2>/dev/null; then
    pass "EA-001a" "script checks for jq availability"
  else
    fail "EA-001a" "script does not check for jq availability"
  fi
else
  fail "EA-001a" "script not found"
fi


# ============================================================================
# EA-003: Date arithmetic portability (GNU/BSD fallback)
# ============================================================================

section "EA-003: Date arithmetic portability"

# EA-003a: Script uses GNU-first-BSD-fallback for date conversion
if [ -f "$INTEL_SCRIPT" ]; then
  if grep -qE 'date -d|date -jf' "$INTEL_SCRIPT" 2>/dev/null; then
    pass "EA-003a" "script includes GNU/BSD date fallback pattern"
  else
    fail "EA-003a" "script missing GNU/BSD date fallback pattern"
  fi
else
  fail "EA-003a" "script not found"
fi

# EA-003b: Script uses GNU/BSD stat fallback for mtime
if [ -f "$INTEL_SCRIPT" ]; then
  if grep -qE "stat -c|stat -f" "$INTEL_SCRIPT" 2>/dev/null; then
    pass "EA-003b" "script includes GNU/BSD stat fallback pattern"
  else
    fail "EA-003b" "script missing GNU/BSD stat fallback pattern"
  fi
else
  fail "EA-003b" "script not found"
fi


# ============================================================================
# Integration: Full pipeline test with all data sources
# ============================================================================

section "Integration: Full pipeline with all data sources"

integ_dir=$(mkworkdir integration)
setup_fixture_dirs "$integ_dir"
write_deferred_findings "$integ_dir"
write_devadv_report_inline "$integ_dir" "2026-05-10"
write_devadv_report_subsection "$integ_dir" "2026-05-16"
write_overrides "$integ_dir"
write_lens_recommendations "$integ_dir"
write_debug_investigation "$integ_dir"
write_workflow_effectiveness "$integ_dir"

if [ -x "$INTEL_SCRIPT" ]; then
  output=$(run_intel "$integ_dir")
  rc=$?

  # Full pipeline produces valid JSON
  if [ $rc -eq 0 ] && echo "$output" | jq -e '.' >/dev/null 2>&1; then
    pass "INTEG-001" "full pipeline produces valid JSON with all sources"
  else
    fail "INTEG-001" "full pipeline failed (rc=$rc)"
  fi

  # All sections have entries
  all_populated=true
  for section in deferred_findings devadv_themes override_patterns lens_recommendations debug_clusters phase_effectiveness; do
    count=$(echo "$output" | jq ".sections.$section | length" 2>/dev/null)
    if [ "$count" = "0" ] 2>/dev/null; then
      all_populated=false
      fail "INTEG-002-$section" "section $section empty when source data exists"
    fi
  done
  if $all_populated; then
    pass "INTEG-002" "all 6 sections populated when source data exists"
  fi

  # Schema version is 1
  sv=$(echo "$output" | jq -r '.schema_version' 2>/dev/null)
  if [ "$sv" = "1" ]; then
    pass "INTEG-003" "schema_version is 1"
  else
    fail "INTEG-003" "schema_version wrong (got $sv)"
  fi

  # generated_at is a valid ISO timestamp
  gen_at=$(echo "$output" | jq -r '.generated_at' 2>/dev/null)
  if [[ "$gen_at" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T ]]; then
    pass "INTEG-004" "generated_at is valid ISO timestamp ($gen_at)"
  else
    fail "INTEG-004" "generated_at not valid ISO timestamp (got $gen_at)"
  fi
else
  fail "INTEG-001" "script not executable"
  fail "INTEG-002" "script not executable"
  fail "INTEG-003" "script not executable"
  fail "INTEG-004" "script not executable"
fi


# ============================================================================
# Summary
# ============================================================================

summary "cross-feature-intel"
