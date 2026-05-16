#!/usr/bin/env bash
# Correctless — Deferred Findings Backlog test suite
# Tests spec rules INV-001 through INV-012, PRH-001 through PRH-003,
# BND-001 through BND-003 from
# .correctless/specs/deferred-findings-backlog.md
#
# RED phase: these tests MUST FAIL — implementation does not exist yet.
# Run from repo root: bash tests/test-deferred-findings-backlog.sh

source "$(dirname "${BASH_SOURCE[0]}")/test-helpers.sh"

# ============================================================================
# Constants
# ============================================================================

SKILLS_DIR="$REPO_DIR/skills"
SCRIPTS_DIR="$REPO_DIR/scripts"
SYNC_SCRIPT="$REPO_DIR/sync.sh"
CREVIEW_SPEC_SKILL="$SKILLS_DIR/creview-spec/SKILL.md"
CREVIEW_SKILL="$SKILLS_DIR/creview/SKILL.md"
CAUTO_SKILL="$SKILLS_DIR/cauto/SKILL.md"
CSTATUS_SKILL="$SKILLS_DIR/cstatus/SKILL.md"
CMETRICS_SKILL="$SKILLS_DIR/cmetrics/SKILL.md"
CTRIAGE_SKILL="$SKILLS_DIR/ctriage/SKILL.md"
CHELP_SKILL="$SKILLS_DIR/chelp/SKILL.md"
SYNC_DEFERRED="$SCRIPTS_DIR/sync-deferred-backlog.sh"
WORKFLOW_ADVANCE="$REPO_DIR/hooks/workflow-advance.sh"

# Test workspace
WORK_BASE="/tmp/correctless-dfb-$$"
cleanup() { rm -rf "$WORK_BASE"; }
trap cleanup EXIT

mkworkdir() {
  local sub="$1"
  local d="$WORK_BASE/$sub"
  rm -rf "$d"
  mkdir -p "$d"
  echo "$d"
}

# ============================================================================
# INV-001 [unit]: Backlog file schema validation
# ============================================================================

section "INV-001: Backlog file schema"

# INV-001a: sync script validates schema and rejects missing required fields
inv001_dir=$(mkworkdir inv001a)
mkdir -p "$inv001_dir/.correctless/meta"

# Create a valid backlog file
cat > "$inv001_dir/.correctless/meta/deferred-findings.json" << 'FIXTURE'
{
  "schema_version": 1,
  "findings": [
    {
      "id": "DF-001",
      "source_file": ".correctless/artifacts/review-spec-findings-foo.md",
      "finding_id": "RS-004",
      "feature": "foo",
      "severity": "MEDIUM",
      "description": "Test finding",
      "category": "test",
      "status": "open",
      "deferred_at": "2026-05-01T12:00:00Z",
      "resolved_at": null,
      "resolution": null
    }
  ]
}
FIXTURE

# Test that the sync script can read and validate a well-formed file
if [ -x "$SYNC_DEFERRED" ] && bash "$SYNC_DEFERRED" --validate "$inv001_dir/.correctless/meta/deferred-findings.json" 2>/dev/null; then
  pass "INV-001a" "sync script validates well-formed backlog file"
else
  fail "INV-001a" "sync script cannot validate backlog file (script missing or validation failed)"
fi

# INV-001b: schema requires all fields — reject entry with missing 'category'
cat > "$inv001_dir/.correctless/meta/deferred-findings-bad.json" << 'FIXTURE'
{
  "schema_version": 1,
  "findings": [
    {
      "id": "DF-001",
      "source_file": ".correctless/artifacts/review-spec-findings-foo.md",
      "finding_id": "RS-004",
      "feature": "foo",
      "severity": "MEDIUM",
      "description": "Test finding",
      "status": "open",
      "deferred_at": "2026-05-01T12:00:00Z",
      "resolved_at": null,
      "resolution": null
    }
  ]
}
FIXTURE

if [ -x "$SYNC_DEFERRED" ] && ! bash "$SYNC_DEFERRED" --validate "$inv001_dir/.correctless/meta/deferred-findings-bad.json" 2>/dev/null; then
  pass "INV-001b" "sync script rejects entry missing required field 'category'"
else
  fail "INV-001b" "sync script did not reject entry with missing 'category' field"
fi

# INV-001c: ID format — must be zero-padded DF-NNN
cat > "$inv001_dir/.correctless/meta/deferred-findings-badid.json" << 'FIXTURE'
{
  "schema_version": 1,
  "findings": [
    {
      "id": "DF-1",
      "source_file": ".correctless/artifacts/review-spec-findings-foo.md",
      "finding_id": "RS-004",
      "feature": "foo",
      "severity": "MEDIUM",
      "description": "Test finding",
      "category": "test",
      "status": "open",
      "deferred_at": "2026-05-01T12:00:00Z",
      "resolved_at": null,
      "resolution": null
    }
  ]
}
FIXTURE

if [ -x "$SYNC_DEFERRED" ] && ! bash "$SYNC_DEFERRED" --validate "$inv001_dir/.correctless/meta/deferred-findings-badid.json" 2>/dev/null; then
  pass "INV-001c" "sync script rejects non-zero-padded ID format (DF-1)"
else
  fail "INV-001c" "sync script did not reject non-zero-padded ID DF-1"
fi

# INV-001d: severity enum — reject HIGH severity
cat > "$inv001_dir/.correctless/meta/deferred-findings-highsev.json" << 'FIXTURE'
{
  "schema_version": 1,
  "findings": [
    {
      "id": "DF-001",
      "source_file": ".correctless/artifacts/review-spec-findings-foo.md",
      "finding_id": "RS-004",
      "feature": "foo",
      "severity": "HIGH",
      "description": "Test finding",
      "category": "test",
      "status": "open",
      "deferred_at": "2026-05-01T12:00:00Z",
      "resolved_at": null,
      "resolution": null
    }
  ]
}
FIXTURE

if [ -x "$SYNC_DEFERRED" ] && ! bash "$SYNC_DEFERRED" --validate "$inv001_dir/.correctless/meta/deferred-findings-highsev.json" 2>/dev/null; then
  pass "INV-001d" "sync script rejects HIGH severity (PRH-003)"
else
  fail "INV-001d" "sync script did not reject HIGH severity entry"
fi

# INV-001e: status enum — reject invalid status
cat > "$inv001_dir/.correctless/meta/deferred-findings-badstatus.json" << 'FIXTURE'
{
  "schema_version": 1,
  "findings": [
    {
      "id": "DF-001",
      "source_file": ".correctless/artifacts/review-spec-findings-foo.md",
      "finding_id": "RS-004",
      "feature": "foo",
      "severity": "MEDIUM",
      "description": "Test finding",
      "category": "test",
      "status": "deleted",
      "deferred_at": "2026-05-01T12:00:00Z",
      "resolved_at": null,
      "resolution": null
    }
  ]
}
FIXTURE

if [ -x "$SYNC_DEFERRED" ] && ! bash "$SYNC_DEFERRED" --validate "$inv001_dir/.correctless/meta/deferred-findings-badstatus.json" 2>/dev/null; then
  pass "INV-001e" "sync script rejects invalid status 'deleted'"
else
  fail "INV-001e" "sync script did not reject invalid status value"
fi

# INV-001f: duplicate IDs rejected
cat > "$inv001_dir/.correctless/meta/deferred-findings-dupid.json" << 'FIXTURE'
{
  "schema_version": 1,
  "findings": [
    {
      "id": "DF-001",
      "source_file": ".correctless/artifacts/review-spec-findings-foo.md",
      "finding_id": "RS-004",
      "feature": "foo",
      "severity": "MEDIUM",
      "description": "First finding",
      "category": "test",
      "status": "open",
      "deferred_at": "2026-05-01T12:00:00Z",
      "resolved_at": null,
      "resolution": null
    },
    {
      "id": "DF-001",
      "source_file": ".correctless/artifacts/review-spec-findings-bar.md",
      "finding_id": "RS-005",
      "feature": "bar",
      "severity": "LOW",
      "description": "Duplicate ID finding",
      "category": "test",
      "status": "open",
      "deferred_at": "2026-05-02T12:00:00Z",
      "resolved_at": null,
      "resolution": null
    }
  ]
}
FIXTURE

if [ -x "$SYNC_DEFERRED" ] && ! bash "$SYNC_DEFERRED" --validate "$inv001_dir/.correctless/meta/deferred-findings-dupid.json" 2>/dev/null; then
  pass "INV-001f" "sync script rejects duplicate IDs"
else
  fail "INV-001f" "sync script did not reject duplicate IDs"
fi

# ============================================================================
# INV-002a [unit]: Review skills reference backlog write path (structural)
# ============================================================================

section "INV-002a: Review skills reference backlog write path"

# INV-002a-1: /creview-spec SKILL.md contains the backlog path
if grep -qF '.correctless/meta/deferred-findings.json' "$CREVIEW_SPEC_SKILL"; then
  pass "INV-002a-1" "/creview-spec references .correctless/meta/deferred-findings.json"
else
  fail "INV-002a-1" "/creview-spec missing backlog path reference"
fi

# INV-002a-2: /creview-spec allowed-tools includes Write() for backlog
if grep -q 'Write(.correctless/meta/deferred-findings.json)' "$CREVIEW_SPEC_SKILL"; then
  pass "INV-002a-2" "/creview-spec allowed-tools includes Write for backlog"
else
  fail "INV-002a-2" "/creview-spec allowed-tools missing Write(.correctless/meta/deferred-findings.json)"
fi

# INV-002a-3: /creview-spec has DF- ID assignment instruction near backlog path
# Within 20 lines of a body reference (skip frontmatter line)
found_df_near_path=false
while IFS=: read -r lnum _; do
  start_line=$((lnum > 20 ? lnum - 20 : 1))
  end_line=$((lnum + 20))
  if sed -n "${start_line},${end_line}p" "$CREVIEW_SPEC_SKILL" | grep -qF 'DF-'; then
    found_df_near_path=true
    break
  fi
done < <(grep -n '.correctless/meta/deferred-findings.json' "$CREVIEW_SPEC_SKILL")

if [ "$found_df_near_path" = true ]; then
  pass "INV-002a-3" "/creview-spec has DF- ID instruction within 20 lines of backlog path"
else
  fail "INV-002a-3" "/creview-spec missing DF- ID assignment instruction near backlog path"
fi

# INV-002a-4: /creview SKILL.md contains the backlog path
if grep -qF '.correctless/meta/deferred-findings.json' "$CREVIEW_SKILL"; then
  pass "INV-002a-4" "/creview references .correctless/meta/deferred-findings.json"
else
  fail "INV-002a-4" "/creview missing backlog path reference"
fi

# INV-002a-5: /creview allowed-tools includes Write() for backlog
if grep -q 'Write(.correctless/meta/deferred-findings.json)' "$CREVIEW_SKILL"; then
  pass "INV-002a-5" "/creview allowed-tools includes Write for backlog"
else
  fail "INV-002a-5" "/creview allowed-tools missing Write(.correctless/meta/deferred-findings.json)"
fi

# INV-002a-6: /creview has DF- ID assignment instruction near backlog path
found_df_near_path=false
while IFS=: read -r lnum _; do
  start_line=$((lnum > 20 ? lnum - 20 : 1))
  end_line=$((lnum + 20))
  if sed -n "${start_line},${end_line}p" "$CREVIEW_SKILL" | grep -qF 'DF-'; then
    found_df_near_path=true
    break
  fi
done < <(grep -n '.correctless/meta/deferred-findings.json' "$CREVIEW_SKILL")

if [ "$found_df_near_path" = true ]; then
  pass "INV-002a-6" "/creview has DF- ID instruction within 20 lines of backlog path"
else
  fail "INV-002a-6" "/creview missing DF- ID assignment instruction near backlog path"
fi

# ============================================================================
# INV-003 [unit]: Backlog file creation on first write
# ============================================================================

section "INV-003: Backlog file creation on first write"

# Test that the sync script creates the meta directory and file if absent
inv003_dir=$(mkworkdir inv003)
# Intentionally do NOT create .correctless/meta/

# Create a minimal review artifact with a pending finding
mkdir -p "$inv003_dir/.correctless/artifacts"
cat > "$inv003_dir/.correctless/artifacts/review-spec-findings-test-feature.md" << 'ARTIFACT'
# Review Spec Findings: test-feature

## RS-001: Missing edge case
- **Severity**: NON-BLOCKING
- **Status**: pending
- **Description**: Missing null check in parser
ARTIFACT

if [ -x "$SYNC_DEFERRED" ]; then
  output=$(bash "$SYNC_DEFERRED" "$inv003_dir" 2>&1) || true
  if [ -f "$inv003_dir/.correctless/meta/deferred-findings.json" ]; then
    # Verify schema wrapper
    if jq -e '.findings | type == "array"' "$inv003_dir/.correctless/meta/deferred-findings.json" >/dev/null 2>&1 && \
       jq -e '.schema_version == 1' "$inv003_dir/.correctless/meta/deferred-findings.json" >/dev/null 2>&1; then
      pass "INV-003a" "sync script creates backlog file with schema wrapper when missing"
    else
      fail "INV-003a" "sync script created file but schema wrapper is missing or invalid"
    fi
  else
    fail "INV-003a" "sync script did not create backlog file when directory was missing"
  fi
else
  fail "INV-003a" "sync script does not exist at $SYNC_DEFERRED"
fi

# ============================================================================
# INV-004 [unit]: /cauto backlog sweep
# ============================================================================

section "INV-004: /cauto backlog sweep"

# INV-004a: cauto SKILL.md references backlog sweep
if grep -qi 'backlog.*sweep\|deferred.*findings.*sweep\|sweep.*backlog\|deferred-findings' "$CAUTO_SKILL"; then
  pass "INV-004a" "/cauto references backlog sweep"
else
  fail "INV-004a" "/cauto missing backlog sweep reference"
fi

# INV-004b: cauto sweep is between cdocs and consolidation
# Check that the Step 7.5 (backlog sweep) section appears between Step 7 (cdocs) and Step 8 (consolidation)
# Use section headings for precise ordering
cauto_body=$(skill_body "$CAUTO_SKILL")
step7_line=$(echo "$cauto_body" | grep -n '### Step 7:.*cdocs\|### Step 7:.*Invoke' | head -1 | cut -d: -f1)
sweep_line=$(echo "$cauto_body" | grep -n '### Step 7.5:.*[Bb]acklog\|### Step 7.5' | head -1 | cut -d: -f1)
step8_line=$(echo "$cauto_body" | grep -n '### Step 8:.*[Cc]onsolidation' | head -1 | cut -d: -f1)

if [ -n "$step7_line" ] && [ -n "$sweep_line" ] && [ -n "$step8_line" ]; then
  if [ "$step7_line" -lt "$sweep_line" ] && [ "$sweep_line" -lt "$step8_line" ]; then
    pass "INV-004b" "/cauto backlog sweep appears between cdocs and consolidation"
  else
    fail "INV-004b" "/cauto backlog sweep is not between cdocs and consolidation (step7=$step7_line, sweep=$sweep_line, step8=$step8_line)"
  fi
else
  fail "INV-004b" "/cauto missing one of: step 7 heading, step 7.5 heading, or step 8 heading"
fi

# INV-004c: cauto references the backlog file path
if grep -qF '.correctless/meta/deferred-findings.json' "$CAUTO_SKILL"; then
  pass "INV-004c" "/cauto references the backlog file path"
else
  fail "INV-004c" "/cauto missing .correctless/meta/deferred-findings.json reference"
fi

# INV-004d: sweep is described as non-blocking
if grep -qi 'non.block\|no-op\|fail.*non.block\|sweep.*fail.*non.block' "$CAUTO_SKILL"; then
  pass "INV-004d" "/cauto sweep described as non-blocking"
else
  fail "INV-004d" "/cauto sweep not described as non-blocking on failure"
fi

# ============================================================================
# INV-005 [unit]: /cstatus backlog visibility
# ============================================================================

section "INV-005: /cstatus backlog visibility"

# INV-005a: cstatus references deferred findings
if grep -qF '.correctless/meta/deferred-findings.json' "$CSTATUS_SKILL" || \
   grep -qF 'deferred-findings.json' "$CSTATUS_SKILL"; then
  pass "INV-005a" "/cstatus references deferred-findings.json"
else
  fail "INV-005a" "/cstatus missing deferred-findings.json reference"
fi

# INV-005b: cstatus includes severity breakdown (MEDIUM/LOW/ADVISORY)
if grep -qi 'severity.*breakdown\|MEDIUM.*LOW.*ADVISORY\|severity.*distribution' "$CSTATUS_SKILL"; then
  pass "INV-005b" "/cstatus includes severity breakdown"
else
  fail "INV-005b" "/cstatus missing severity breakdown instruction"
fi

# INV-005c: cstatus omits section when zero findings (dormant per PAT-019)
if grep -qi 'omit.*zero\|zero.*omit\|dormant\|no.*0.*findings\|no.*noise' "$CSTATUS_SKILL"; then
  pass "INV-005c" "/cstatus omits backlog section when zero findings"
else
  fail "INV-005c" "/cstatus missing zero-findings omission instruction"
fi

# INV-005d: cstatus suggests sync script when drift detected
if grep -qi 'sync-deferred-backlog\|sync.*deferred\|re-sync' "$CSTATUS_SKILL"; then
  pass "INV-005d" "/cstatus suggests sync script for drift detection"
else
  fail "INV-005d" "/cstatus missing sync script suggestion for drift detection"
fi

# ============================================================================
# INV-006 [unit]: /cstatus threshold suggestion
# ============================================================================

section "INV-006: /cstatus threshold suggestion"

# INV-006a: cstatus has threshold of 20
if grep -q '20' "$CSTATUS_SKILL" && grep -qi 'threshold\|exceed\|more than' "$CSTATUS_SKILL"; then
  pass "INV-006a" "/cstatus references threshold of 20"
else
  fail "INV-006a" "/cstatus missing threshold of 20 for backlog warning"
fi

# INV-006b: cstatus suggests /ctriage when threshold exceeded
if grep -qF '/ctriage' "$CSTATUS_SKILL"; then
  pass "INV-006b" "/cstatus suggests /ctriage when threshold exceeded"
else
  fail "INV-006b" "/cstatus missing /ctriage suggestion"
fi

# ============================================================================
# INV-007 [unit]: /cmetrics backlog trend
# ============================================================================

section "INV-007: /cmetrics backlog trend"

# INV-007a: cmetrics references deferred findings
if grep -qF '.correctless/meta/deferred-findings.json' "$CMETRICS_SKILL" || \
   grep -qF 'deferred-findings.json' "$CMETRICS_SKILL"; then
  pass "INV-007a" "/cmetrics references deferred-findings.json"
else
  fail "INV-007a" "/cmetrics missing deferred-findings.json reference"
fi

# INV-007b: cmetrics includes severity breakdown
if grep -qi 'severity.*breakdown\|severity.*distribution' "$CMETRICS_SKILL"; then
  pass "INV-007b" "/cmetrics includes severity breakdown"
else
  fail "INV-007b" "/cmetrics missing severity breakdown instruction"
fi

# INV-007c: cmetrics includes oldest open finding metric
if grep -qi 'oldest.*open\|oldest.*finding' "$CMETRICS_SKILL"; then
  pass "INV-007c" "/cmetrics includes oldest open finding metric"
else
  fail "INV-007c" "/cmetrics missing oldest open finding metric"
fi

# INV-007d: cmetrics includes 30-day trend (added/resolved)
if grep -qi '30.day\|30 day\|thirty.day\|last.*month' "$CMETRICS_SKILL"; then
  pass "INV-007d" "/cmetrics includes 30-day trend"
else
  fail "INV-007d" "/cmetrics missing 30-day trend data"
fi

# INV-007e: cmetrics shows "No deferred findings data" when file absent
if grep -qi 'no deferred findings\|no.*backlog.*data\|deferred findings data' "$CMETRICS_SKILL"; then
  pass "INV-007e" "/cmetrics handles absent backlog file"
else
  fail "INV-007e" "/cmetrics missing handler for absent backlog file"
fi

# ============================================================================
# INV-008 [unit]: /ctriage skill structure
# ============================================================================

section "INV-008: /ctriage skill structure"

# INV-008a: ctriage skill file exists
if [ -f "$CTRIAGE_SKILL" ]; then
  pass "INV-008a" "/ctriage SKILL.md exists"
else
  fail "INV-008a" "/ctriage SKILL.md does not exist at $CTRIAGE_SKILL"
fi

# INV-008b: ctriage has proper frontmatter with name
if [ -f "$CTRIAGE_SKILL" ]; then
  triage_name=$(get_frontmatter_field "$CTRIAGE_SKILL" "name")
  if [ "$triage_name" = "ctriage" ]; then
    pass "INV-008b" "/ctriage has correct name in frontmatter"
  else
    fail "INV-008b" "/ctriage has wrong name in frontmatter: '$triage_name'"
  fi
else
  fail "INV-008b" "/ctriage SKILL.md does not exist — cannot check frontmatter"
fi

# INV-008c: ctriage includes Write() for backlog in allowed-tools
if [ -f "$CTRIAGE_SKILL" ] && grep -q 'Write(.correctless/meta/deferred-findings.json)' "$CTRIAGE_SKILL"; then
  pass "INV-008c" "/ctriage allowed-tools includes Write for backlog"
else
  fail "INV-008c" "/ctriage missing Write(.correctless/meta/deferred-findings.json) in allowed-tools"
fi

# INV-008d: ctriage includes Read() for backlog in allowed-tools
if [ -f "$CTRIAGE_SKILL" ] && grep -q 'Read(.correctless/meta/deferred-findings.json)' "$CTRIAGE_SKILL"; then
  pass "INV-008d" "/ctriage allowed-tools includes Read for backlog"
else
  fail "INV-008d" "/ctriage missing Read(.correctless/meta/deferred-findings.json) in allowed-tools"
fi

# INV-008e: ctriage presents findings one at a time (wizard-style)
if [ -f "$CTRIAGE_SKILL" ] && grep -qi 'one at a time\|one-at-a-time\|wizard' "$CTRIAGE_SKILL"; then
  pass "INV-008e" "/ctriage presents findings one at a time"
else
  fail "INV-008e" "/ctriage missing wizard-style / one-at-a-time instruction"
fi

# INV-008f: ctriage has progress counter
if [ -f "$CTRIAGE_SKILL" ] && grep -qi 'Finding.*N.*of.*M\|progress.*counter\|N of M' "$CTRIAGE_SKILL"; then
  pass "INV-008f" "/ctriage has progress counter"
else
  fail "INV-008f" "/ctriage missing progress counter (Finding N of M)"
fi

# INV-008g: ctriage offers all four disposition options
four_dispositions=0
if [ -f "$CTRIAGE_SKILL" ]; then
  grep -qi 'fix now\|Fix now' "$CTRIAGE_SKILL" && four_dispositions=$((four_dispositions + 1))
  grep -qi 'keep open\|Keep open' "$CTRIAGE_SKILL" && four_dispositions=$((four_dispositions + 1))
  grep -qi "won.*t fix\|wont.fix\|Won.*t fix\|Wont.fix" "$CTRIAGE_SKILL" && four_dispositions=$((four_dispositions + 1))
  grep -qi 're.prioritize\|Re.prioritize\|reprioritize' "$CTRIAGE_SKILL" && four_dispositions=$((four_dispositions + 1))
fi

if [ "$four_dispositions" -ge 4 ]; then
  pass "INV-008g" "/ctriage offers all 4 disposition options"
else
  fail "INV-008g" "/ctriage only has $four_dispositions of 4 disposition options"
fi

# INV-008h: ctriage does NOT use context: fork (AP-027)
if [ -f "$CTRIAGE_SKILL" ]; then
  fm_context=$(get_frontmatter_field "$CTRIAGE_SKILL" "context" 2>/dev/null || true)
  if [ "$fm_context" = "fork" ]; then
    fail "INV-008h" "/ctriage uses context: fork (violates AP-027)"
  else
    pass "INV-008h" "/ctriage does not use context: fork"
  fi
else
  fail "INV-008h" "/ctriage SKILL.md does not exist — cannot check context field"
fi

# INV-008i: ctriage writes incrementally (not batch at end)
if [ -f "$CTRIAGE_SKILL" ] && grep -qi 'incremental\|after each disposition\|each finding.*write\|write.*each\|not batch' "$CTRIAGE_SKILL"; then
  pass "INV-008i" "/ctriage writes incrementally after each disposition"
else
  fail "INV-008i" "/ctriage missing incremental write instruction"
fi

# INV-008j: ctriage has interaction_mode (required by autonomous-skill-contract)
if [ -f "$CTRIAGE_SKILL" ]; then
  triage_mode=$(get_frontmatter_field "$CTRIAGE_SKILL" "interaction_mode" 2>/dev/null || true)
  if [ -n "$triage_mode" ]; then
    pass "INV-008j" "/ctriage has interaction_mode: $triage_mode"
  else
    fail "INV-008j" "/ctriage missing interaction_mode in frontmatter"
  fi
else
  fail "INV-008j" "/ctriage SKILL.md does not exist — cannot check interaction_mode"
fi

# ============================================================================
# INV-009 [unit]: Backlog sync script
# ============================================================================

section "INV-009: Backlog sync script"

# INV-009a: sync script exists
if [ -f "$SYNC_DEFERRED" ]; then
  pass "INV-009a" "sync-deferred-backlog.sh exists"
else
  fail "INV-009a" "sync-deferred-backlog.sh does not exist at $SYNC_DEFERRED"
fi

# INV-009b: sync script reads review-spec-findings artifacts
if [ -f "$SYNC_DEFERRED" ] && grep -q 'review-spec-findings' "$SYNC_DEFERRED"; then
  pass "INV-009b" "sync script reads review-spec-findings artifacts"
else
  fail "INV-009b" "sync script missing review-spec-findings artifact pattern"
fi

# INV-009c: sync script reads review-findings artifacts
if [ -f "$SYNC_DEFERRED" ] && grep -q 'review-findings' "$SYNC_DEFERRED"; then
  pass "INV-009c" "sync script reads review-findings artifacts"
else
  fail "INV-009c" "sync script missing review-findings artifact pattern"
fi

# INV-009d: sync script checks artifacts/reviews/ directory
if [ -f "$SYNC_DEFERRED" ] && grep -q 'artifacts/reviews/' "$SYNC_DEFERRED"; then
  pass "INV-009d" "sync script checks artifacts/reviews/ directory"
else
  fail "INV-009d" "sync script missing artifacts/reviews/ directory check"
fi

# INV-009e: sync script is idempotent — running twice does not create duplicates
inv009e_dir=$(mkworkdir inv009e)
mkdir -p "$inv009e_dir/.correctless/artifacts"

cat > "$inv009e_dir/.correctless/artifacts/review-spec-findings-idem-test.md" << 'ARTIFACT'
# Review Spec Findings: idem-test

## RS-001: Test dedup finding
- **Severity**: NON-BLOCKING
- **Status**: pending
- **Description**: This is a test finding for dedup
ARTIFACT

if [ -x "$SYNC_DEFERRED" ]; then
  # Run once
  bash "$SYNC_DEFERRED" "$inv009e_dir" 2>/dev/null
  count1=$(jq '.findings | length' "$inv009e_dir/.correctless/meta/deferred-findings.json" 2>/dev/null || echo 0)

  # Run again — same artifacts, should not duplicate
  bash "$SYNC_DEFERRED" "$inv009e_dir" 2>/dev/null
  count2=$(jq '.findings | length' "$inv009e_dir/.correctless/meta/deferred-findings.json" 2>/dev/null || echo 0)

  if [ "$count1" = "$count2" ] && [ "$count1" -gt 0 ]; then
    pass "INV-009e" "sync script is idempotent (count=$count1 after both runs)"
  else
    fail "INV-009e" "sync script not idempotent (first=$count1, second=$count2)"
  fi
else
  fail "INV-009e" "sync script not executable or missing"
fi

# INV-009f: sync script auto-assigns DF-NNN IDs
if [ -x "$SYNC_DEFERRED" ]; then
  inv009f_dir=$(mkworkdir inv009f)
  mkdir -p "$inv009f_dir/.correctless/artifacts"

  cat > "$inv009f_dir/.correctless/artifacts/review-spec-findings-id-test.md" << 'ARTIFACT'
# Review Spec Findings: id-test

## RS-001: First finding
- **Severity**: NON-BLOCKING
- **Status**: pending
- **Description**: First test finding

## RS-002: Second finding
- **Severity**: NON-BLOCKING
- **Status**: pending
- **Description**: Second test finding
ARTIFACT

  bash "$SYNC_DEFERRED" "$inv009f_dir" 2>/dev/null
  if [ -f "$inv009f_dir/.correctless/meta/deferred-findings.json" ]; then
    id1=$(jq -r '.findings[0].id' "$inv009f_dir/.correctless/meta/deferred-findings.json" 2>/dev/null)
    id2=$(jq -r '.findings[1].id' "$inv009f_dir/.correctless/meta/deferred-findings.json" 2>/dev/null)

    # Both IDs should match DF-NNN format
    if echo "$id1" | grep -qE '^DF-[0-9]{3}$' && echo "$id2" | grep -qE '^DF-[0-9]{3}$' && [ "$id1" != "$id2" ]; then
      pass "INV-009f" "sync script assigns unique DF-NNN IDs ($id1, $id2)"
    else
      fail "INV-009f" "sync script IDs not in DF-NNN format or not unique (got $id1, $id2)"
    fi
  else
    fail "INV-009f" "sync script did not create backlog file"
  fi
else
  fail "INV-009f" "sync script not executable or missing"
fi

# INV-009g: sync script extracts finding_id from artifact
if [ -x "$SYNC_DEFERRED" ]; then
  inv009g_dir=$(mkworkdir inv009g)
  mkdir -p "$inv009g_dir/.correctless/artifacts"

  cat > "$inv009g_dir/.correctless/artifacts/review-spec-findings-findid-test.md" << 'ARTIFACT'
# Review Spec Findings: findid-test

## RS-042: A specific finding
- **Severity**: NON-BLOCKING
- **Status**: pending
- **Description**: Finding with known ID
ARTIFACT

  bash "$SYNC_DEFERRED" "$inv009g_dir" 2>/dev/null
  if [ -f "$inv009g_dir/.correctless/meta/deferred-findings.json" ]; then
    finding_id=$(jq -r '.findings[0].finding_id' "$inv009g_dir/.correctless/meta/deferred-findings.json" 2>/dev/null)
    if [ "$finding_id" = "RS-042" ]; then
      pass "INV-009g" "sync script extracts original finding_id (RS-042)"
    else
      fail "INV-009g" "sync script finding_id wrong (expected RS-042, got $finding_id)"
    fi
  else
    fail "INV-009g" "sync script did not create backlog file"
  fi
else
  fail "INV-009g" "sync script not executable or missing"
fi

# INV-009h: sync script maps severity correctly
# NON-BLOCKING → MEDIUM, LOW → LOW, INFORMATIONAL → ADVISORY
if [ -x "$SYNC_DEFERRED" ]; then
  inv009h_dir=$(mkworkdir inv009h)
  mkdir -p "$inv009h_dir/.correctless/artifacts"

  cat > "$inv009h_dir/.correctless/artifacts/review-spec-findings-sev-test.md" << 'ARTIFACT'
# Review Spec Findings: sev-test

## RS-001: Non-blocking finding
- **Severity**: NON-BLOCKING
- **Status**: pending
- **Description**: Should map to MEDIUM
ARTIFACT

  bash "$SYNC_DEFERRED" "$inv009h_dir" 2>/dev/null
  if [ -f "$inv009h_dir/.correctless/meta/deferred-findings.json" ]; then
    sev=$(jq -r '.findings[0].severity' "$inv009h_dir/.correctless/meta/deferred-findings.json" 2>/dev/null)
    if [ "$sev" = "MEDIUM" ]; then
      pass "INV-009h" "sync script maps NON-BLOCKING → MEDIUM"
    else
      fail "INV-009h" "sync script severity mapping wrong (expected MEDIUM, got $sev)"
    fi
  else
    fail "INV-009h" "sync script did not create backlog file"
  fi
else
  fail "INV-009h" "sync script not executable or missing"
fi

# INV-009i: sync script skips BLOCKING/HIGH findings
if [ -x "$SYNC_DEFERRED" ]; then
  inv009i_dir=$(mkworkdir inv009i)
  mkdir -p "$inv009i_dir/.correctless/artifacts"

  cat > "$inv009i_dir/.correctless/artifacts/review-spec-findings-skip-test.md" << 'ARTIFACT'
# Review Spec Findings: skip-test

## RS-001: Blocking finding should be skipped
- **Severity**: BLOCKING
- **Status**: pending
- **Description**: This should NOT enter the backlog

## RS-002: Non-blocking finding should be included
- **Severity**: NON-BLOCKING
- **Status**: pending
- **Description**: This should enter the backlog
ARTIFACT

  bash "$SYNC_DEFERRED" "$inv009i_dir" 2>/dev/null
  if [ -f "$inv009i_dir/.correctless/meta/deferred-findings.json" ]; then
    count=$(jq '.findings | length' "$inv009i_dir/.correctless/meta/deferred-findings.json" 2>/dev/null)
    if [ "$count" = "1" ]; then
      pass "INV-009i" "sync script skips BLOCKING findings (1 of 2 imported)"
    else
      fail "INV-009i" "sync script imported wrong count (expected 1, got $count)"
    fi
  else
    fail "INV-009i" "sync script did not create backlog file"
  fi
else
  fail "INV-009i" "sync script not executable or missing"
fi

# INV-009j: sync script outputs count of findings imported
if [ -x "$SYNC_DEFERRED" ]; then
  inv009j_dir=$(mkworkdir inv009j)
  mkdir -p "$inv009j_dir/.correctless/artifacts"

  cat > "$inv009j_dir/.correctless/artifacts/review-spec-findings-count-test.md" << 'ARTIFACT'
# Review Spec Findings: count-test

## RS-001: Count test finding
- **Severity**: NON-BLOCKING
- **Status**: pending
- **Description**: Finding for count output test
ARTIFACT

  output=$(bash "$SYNC_DEFERRED" "$inv009j_dir" 2>&1)
  if echo "$output" | grep -qiE '[0-9]+.*import|import.*[0-9]+|[0-9]+.*sync|sync.*[0-9]+|[0-9]+.*finding'; then
    pass "INV-009j" "sync script outputs import count"
  else
    fail "INV-009j" "sync script does not output import count (output: $output)"
  fi
else
  fail "INV-009j" "sync script not executable or missing"
fi

# ============================================================================
# INV-010 [unit]: Won't-fix items persist with rationale
# ============================================================================

section "INV-010: Won't-fix items persist with rationale"

# INV-010a: Schema validation rejects wont-fix with empty resolution
inv010_dir=$(mkworkdir inv010a)
mkdir -p "$inv010_dir/.correctless/meta"

cat > "$inv010_dir/.correctless/meta/deferred-findings-wontfix-bad.json" << 'FIXTURE'
{
  "schema_version": 1,
  "findings": [
    {
      "id": "DF-001",
      "source_file": ".correctless/artifacts/review-spec-findings-foo.md",
      "finding_id": "RS-004",
      "feature": "foo",
      "severity": "MEDIUM",
      "description": "Test finding",
      "category": "test",
      "status": "wont-fix",
      "deferred_at": "2026-05-01T12:00:00Z",
      "resolved_at": "2026-05-02T12:00:00Z",
      "resolution": null
    }
  ]
}
FIXTURE

if [ -x "$SYNC_DEFERRED" ] && ! bash "$SYNC_DEFERRED" --validate "$inv010_dir/.correctless/meta/deferred-findings-wontfix-bad.json" 2>/dev/null; then
  pass "INV-010a" "validates wont-fix requires non-empty resolution"
else
  fail "INV-010a" "did not reject wont-fix with null resolution"
fi

# INV-010b: Schema validation accepts wont-fix with resolution
cat > "$inv010_dir/.correctless/meta/deferred-findings-wontfix-good.json" << 'FIXTURE'
{
  "schema_version": 1,
  "findings": [
    {
      "id": "DF-001",
      "source_file": ".correctless/artifacts/review-spec-findings-foo.md",
      "finding_id": "RS-004",
      "feature": "foo",
      "severity": "MEDIUM",
      "description": "Test finding",
      "category": "test",
      "status": "wont-fix",
      "deferred_at": "2026-05-01T12:00:00Z",
      "resolved_at": "2026-05-02T12:00:00Z",
      "resolution": "Accepted as known limitation"
    }
  ]
}
FIXTURE

if [ -x "$SYNC_DEFERRED" ] && bash "$SYNC_DEFERRED" --validate "$inv010_dir/.correctless/meta/deferred-findings-wontfix-good.json" 2>/dev/null; then
  pass "INV-010b" "validates wont-fix with non-empty resolution is accepted"
else
  fail "INV-010b" "rejected valid wont-fix entry with resolution"
fi

# ============================================================================
# INV-011 [unit]: Distribution sync
# ============================================================================

section "INV-011: Distribution sync"

# INV-011a: sync.sh includes ctriage skill
if grep -q 'ctriage' "$SYNC_SCRIPT"; then
  pass "INV-011a" "sync.sh includes ctriage skill"
else
  fail "INV-011a" "sync.sh missing ctriage in skill list"
fi

# INV-011b: sync.sh includes sync-deferred-backlog.sh (via glob — scripts are globbed)
# Scripts are synced via glob (for script in scripts/*.sh), so as long as the file
# exists at scripts/sync-deferred-backlog.sh it will be picked up
if [ -f "$SYNC_DEFERRED" ]; then
  # Verify the glob pattern in sync.sh would pick it up
  if grep -q 'scripts/\*\.sh' "$SYNC_SCRIPT"; then
    pass "INV-011b" "sync.sh uses glob for scripts (will pick up sync-deferred-backlog.sh)"
  else
    fail "INV-011b" "sync.sh does not glob scripts/*.sh — new script won't be synced"
  fi
else
  fail "INV-011b" "sync-deferred-backlog.sh does not exist"
fi

# INV-011c: skill count is updated (30 → 31)
if grep -q '31' "$SYNC_SCRIPT" && grep -qi 'all.*31\|31.*skill' "$SYNC_SCRIPT"; then
  pass "INV-011c" "sync.sh skill count updated to 31"
else
  fail "INV-011c" "sync.sh still has old skill count (not 31)"
fi

# INV-011d: distribution ctriage exists
dist_ctriage="$REPO_DIR/correctless/skills/ctriage/SKILL.md"
if [ -f "$dist_ctriage" ]; then
  pass "INV-011d" "distribution ctriage skill exists"
else
  fail "INV-011d" "distribution ctriage skill does not exist at $dist_ctriage"
fi

# ============================================================================
# INV-012 [unit]: Backlog file in allowed-tools for all writers
# ============================================================================

section "INV-012: Backlog file in allowed-tools for all writers"

# INV-012a: creview-spec has Write() for backlog in allowed-tools frontmatter
allowed_tools_creview_spec=$(get_frontmatter_field "$CREVIEW_SPEC_SKILL" "allowed-tools" 2>/dev/null || true)
if echo "$allowed_tools_creview_spec" | grep -qF 'Write(.correctless/meta/deferred-findings.json)'; then
  pass "INV-012a" "/creview-spec allowed-tools frontmatter includes Write for backlog"
else
  fail "INV-012a" "/creview-spec allowed-tools frontmatter missing Write(.correctless/meta/deferred-findings.json)"
fi

# INV-012b: creview has Write() for backlog in allowed-tools frontmatter
allowed_tools_creview=$(get_frontmatter_field "$CREVIEW_SKILL" "allowed-tools" 2>/dev/null || true)
if echo "$allowed_tools_creview" | grep -qF 'Write(.correctless/meta/deferred-findings.json)'; then
  pass "INV-012b" "/creview allowed-tools frontmatter includes Write for backlog"
else
  fail "INV-012b" "/creview allowed-tools frontmatter missing Write(.correctless/meta/deferred-findings.json)"
fi

# INV-012c: ctriage has Write() for backlog in allowed-tools frontmatter
if [ -f "$CTRIAGE_SKILL" ]; then
  allowed_tools_ctriage=$(get_frontmatter_field "$CTRIAGE_SKILL" "allowed-tools" 2>/dev/null || true)
  if echo "$allowed_tools_ctriage" | grep -qF 'Write(.correctless/meta/deferred-findings.json)'; then
    pass "INV-012c" "/ctriage allowed-tools frontmatter includes Write for backlog"
  else
    fail "INV-012c" "/ctriage allowed-tools frontmatter missing Write(.correctless/meta/deferred-findings.json)"
  fi
else
  fail "INV-012c" "/ctriage SKILL.md does not exist — cannot check allowed-tools"
fi

# INV-012d: ctriage has Read() for backlog in allowed-tools frontmatter
if [ -f "$CTRIAGE_SKILL" ]; then
  if echo "$allowed_tools_ctriage" | grep -qF 'Read(.correctless/meta/deferred-findings.json)'; then
    pass "INV-012d" "/ctriage allowed-tools frontmatter includes Read for backlog"
  else
    fail "INV-012d" "/ctriage allowed-tools frontmatter missing Read(.correctless/meta/deferred-findings.json)"
  fi
else
  fail "INV-012d" "/ctriage SKILL.md does not exist — cannot check allowed-tools"
fi

# ============================================================================
# PRH-001 [unit]: No gate enforcement
# ============================================================================

section "PRH-001: No gate enforcement"

# PRH-001a: workflow-advance.sh does not reference deferred-findings
if ! grep -q 'deferred-findings' "$WORKFLOW_ADVANCE"; then
  pass "PRH-001a" "workflow-advance.sh does not reference deferred-findings (no gate enforcement)"
else
  fail "PRH-001a" "workflow-advance.sh references deferred-findings — potential gate enforcement violation"
fi

# ============================================================================
# PRH-002 [unit]: No deletion of won't-fix items
# ============================================================================

section "PRH-002: No deletion of won't-fix items"

# PRH-002a: ctriage skill instructs to never delete wont-fix
if [ -f "$CTRIAGE_SKILL" ] && grep -qi "never.*delete\|never.*remove\|won.*t.fix.*remain\|persist.*wont.fix\|permanent" "$CTRIAGE_SKILL"; then
  pass "PRH-002a" "/ctriage instructs to never delete wont-fix items"
else
  fail "PRH-002a" "/ctriage missing instruction to never delete wont-fix items"
fi

# PRH-002b: sync script does not remove wont-fix entries on re-sync
if [ -x "$SYNC_DEFERRED" ]; then
  inv_prh002_dir=$(mkworkdir prh002)
  mkdir -p "$inv_prh002_dir/.correctless/meta" "$inv_prh002_dir/.correctless/artifacts"

  # Pre-seed a wont-fix entry in the backlog
  cat > "$inv_prh002_dir/.correctless/meta/deferred-findings.json" << 'FIXTURE'
{
  "schema_version": 1,
  "findings": [
    {
      "id": "DF-001",
      "source_file": ".correctless/artifacts/review-spec-findings-old.md",
      "finding_id": "RS-001",
      "feature": "old-feature",
      "severity": "MEDIUM",
      "description": "Deliberately marked wont-fix",
      "category": "test",
      "status": "wont-fix",
      "deferred_at": "2026-04-01T12:00:00Z",
      "resolved_at": "2026-04-02T12:00:00Z",
      "resolution": "Accepted as known limitation"
    }
  ]
}
FIXTURE

  # Create a new artifact
  cat > "$inv_prh002_dir/.correctless/artifacts/review-spec-findings-new.md" << 'ARTIFACT'
# Review Spec Findings: new-feature

## RS-010: New finding
- **Severity**: NON-BLOCKING
- **Status**: pending
- **Description**: New finding for re-sync test
ARTIFACT

  bash "$SYNC_DEFERRED" "$inv_prh002_dir" 2>/dev/null
  wontfix_count=$(jq '[.findings[] | select(.status == "wont-fix")] | length' "$inv_prh002_dir/.correctless/meta/deferred-findings.json" 2>/dev/null || echo 0)

  if [ "$wontfix_count" -ge 1 ]; then
    pass "PRH-002b" "sync script preserves wont-fix entries on re-sync"
  else
    fail "PRH-002b" "sync script removed wont-fix entries (count=$wontfix_count)"
  fi
else
  fail "PRH-002b" "sync script not executable or missing"
fi

# ============================================================================
# PRH-003 [unit]: No HIGH/CRITICAL findings in backlog
# ============================================================================

section "PRH-003: No HIGH/CRITICAL findings in backlog"

# PRH-003a: tested via INV-001d (schema rejects HIGH severity)
# PRH-003b: tested via INV-009i (sync script skips BLOCKING findings)

# PRH-003c: sync script skips HIGH severity findings
if [ -x "$SYNC_DEFERRED" ]; then
  inv_prh003_dir=$(mkworkdir prh003c)
  mkdir -p "$inv_prh003_dir/.correctless/artifacts"

  cat > "$inv_prh003_dir/.correctless/artifacts/review-spec-findings-high-test.md" << 'ARTIFACT'
# Review Spec Findings: high-test

## RS-001: HIGH severity finding
- **Severity**: HIGH
- **Status**: pending
- **Description**: This HIGH finding should be skipped
ARTIFACT

  bash "$SYNC_DEFERRED" "$inv_prh003_dir" 2>/dev/null
  if [ -f "$inv_prh003_dir/.correctless/meta/deferred-findings.json" ]; then
    count=$(jq '.findings | length' "$inv_prh003_dir/.correctless/meta/deferred-findings.json" 2>/dev/null)
    if [ "$count" = "0" ]; then
      pass "PRH-003c" "sync script skips HIGH severity findings"
    else
      fail "PRH-003c" "sync script imported HIGH severity finding (count=$count)"
    fi
  else
    # File might not be created if no findings were imported — that's also acceptable
    pass "PRH-003c" "sync script skips HIGH severity findings (no backlog file created)"
  fi
else
  fail "PRH-003c" "sync script not executable or missing"
fi

# ============================================================================
# BND-002 [unit]: Malformed backlog file handling
# ============================================================================

section "BND-002: Malformed backlog file handling"

# BND-002a: sync script handles corrupt JSON gracefully for consumers
if [ -x "$SYNC_DEFERRED" ]; then
  bnd002_dir=$(mkworkdir bnd002a)
  mkdir -p "$bnd002_dir/.correctless/meta" "$bnd002_dir/.correctless/artifacts"

  # Write malformed JSON
  echo "NOT JSON AT ALL" > "$bnd002_dir/.correctless/meta/deferred-findings.json"

  cat > "$bnd002_dir/.correctless/artifacts/review-spec-findings-bnd002.md" << 'ARTIFACT'
# Review Spec Findings: bnd002

## RS-001: Finding for malformed test
- **Severity**: NON-BLOCKING
- **Status**: pending
- **Description**: Test finding for malformed file handling
ARTIFACT

  # Writer should fail-closed on corrupt file
  output=$(bash "$SYNC_DEFERRED" "$bnd002_dir" 2>&1)
  exit_code=$?
  if [ "$exit_code" -ne 0 ]; then
    pass "BND-002a" "sync script fails-closed on corrupt backlog file (exit=$exit_code)"
  else
    fail "BND-002a" "sync script should fail-closed on corrupt backlog file (exit=0)"
  fi
else
  fail "BND-002a" "sync script not executable or missing"
fi

# ============================================================================
# Cascade checks: chelp skill count, AGENT_CONTEXT skill count
# ============================================================================

section "Cascade: skill count updates"

# chelp skill count should reference 31
if grep -q '31' "$CHELP_SKILL"; then
  pass "CASCADE-001" "/chelp references skill count 31"
else
  fail "CASCADE-001" "/chelp still has old skill count (not 31)"
fi

# AGENT_CONTEXT skill count should reference 31
agent_ctx="$REPO_DIR/.correctless/AGENT_CONTEXT.md"
if grep -q '31 skill' "$agent_ctx"; then
  pass "CASCADE-002" "AGENT_CONTEXT.md references 31 skills"
else
  fail "CASCADE-002" "AGENT_CONTEXT.md still has old skill count (not 31 skills)"
fi

# ============================================================================
# Summary
# ============================================================================

summary "Deferred Findings Backlog"
