#!/usr/bin/env bash
# Correctless — Pipeline Completeness Verification test suite
# Tests spec rules R-001 through R-011 from
# .correctless/specs/pipeline-completeness-verification.md
# RED phase: these tests MUST FAIL — implementation does not exist yet.
# Run from repo root: bash tests/test-pipeline-completeness-verification.sh

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0

# ============================================
# Helpers (matching project test conventions)
# ============================================

assert_contains() {
  local desc="$1" expected="$2" actual="$3"
  if echo "$actual" | grep -qF "$expected"; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (expected output to contain '$expected')"
    FAIL=$((FAIL + 1))
  fi
}

file_contains() {
  local file="$1" pattern="$2" desc="$3"
  if grep -q "$pattern" "$file" 2>/dev/null; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (pattern '$pattern' not found in $file)"
    FAIL=$((FAIL + 1))
  fi
}

file_contains_i() {
  local file="$1" pattern="$2" desc="$3"
  if grep -qi "$pattern" "$file" 2>/dev/null; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (pattern '$pattern' not found case-insensitively in $file)"
    FAIL=$((FAIL + 1))
  fi
}

# ============================================
# R-001 [unit]: Pipeline manifest written as first action after phase gate
# ============================================

test_r001_pipeline_manifest_creation() {
  echo ""
  echo "=== R-001: Pipeline manifest written as first action after phase gate ==="

  local skill_file="$REPO_DIR/skills/cauto/SKILL.md"

  # R-001: SKILL.md must instruct writing a pipeline manifest
  file_contains_i "$skill_file" "pipeline.manifest\|pipeline-manifest" \
    "R-001: SKILL.md instructs writing a pipeline manifest"

  # R-001: manifest path uses branch_slug convention
  file_contains "$skill_file" "pipeline-manifest-{branch_slug}" \
    "R-001: manifest path uses {branch_slug} convention"

  # R-001: manifest path is under .correctless/artifacts/
  file_contains "$skill_file" ".correctless/artifacts/pipeline-manifest-" \
    "R-001: manifest path is under .correctless/artifacts/"

  # R-001: manifest written as FIRST action after phase gate (before any skill invocation)
  file_contains_i "$skill_file" "FIRST.*action.*manifest\|first.*action.*manifest\|manifest.*before.*skill.*invocation\|write.*manifest.*before" \
    "R-001: manifest written as first action after phase gate"

  # R-001: manifest contains expected_steps field
  file_contains "$skill_file" "expected_steps" \
    "R-001: manifest contains expected_steps field"

  # R-001: manifest contains expected_end_phase field
  file_contains "$skill_file" "expected_end_phase" \
    "R-001: manifest contains expected_end_phase field"

  # R-001: manifest contains completed_steps (initially empty)
  file_contains "$skill_file" "completed_steps" \
    "R-001: manifest contains completed_steps field"

  # R-001: manifest contains started_at (ISO 8601)
  file_contains "$skill_file" "started_at" \
    "R-001: manifest contains started_at field"

  # R-001: manifest contains branch field
  file_contains_i "$skill_file" "branch.*current branch name" \
    "R-001: manifest contains branch field with current branch name"

  # R-001: completed_steps initially empty
  file_contains_i "$skill_file" "completed_steps.*initially.*empty\|completed_steps.*empty" \
    "R-001: completed_steps is initially empty"
}

# ============================================
# R-002 [unit]: Append step to completed_steps after each step
# ============================================

test_r002_append_completed_steps() {
  echo ""
  echo "=== R-002: Append step name to completed_steps after each step ==="

  local skill_file="$REPO_DIR/skills/cauto/SKILL.md"

  # R-002: SKILL.md instructs appending current step to completed_steps
  file_contains_i "$skill_file" "append.*completed_steps\|completed_steps.*append" \
    "R-002: SKILL.md instructs appending to completed_steps"

  # R-002: append happens AFTER step completes but BEFORE next step
  file_contains_i "$skill_file" "AFTER.*step.*complete.*BEFORE.*next\|after.*step.*completes.*before.*next" \
    "R-002: append after step completes, before next step begins"
}

# ============================================
# R-003 [unit]: Write status:complete as final action
# ============================================

test_r003_status_complete_final_action() {
  echo ""
  echo "=== R-003: Write status:complete as final action ==="

  local skill_file="$REPO_DIR/skills/cauto/SKILL.md"

  # R-003: SKILL.md instructs writing status:complete
  file_contains_i "$skill_file" "status.*complete\|\"status\".*\"complete\"" \
    "R-003: SKILL.md instructs writing status:complete"

  # R-003: status:complete written as FINAL action after Step 10
  file_contains_i "$skill_file" "FINAL.*action.*status.*complete\|final.*action.*status.*complete\|FINAL.*action.*manifest\|final.*action.*manifest" \
    "R-003: status:complete written as final action"

  # R-003: absence of status:complete indicates truncation
  file_contains_i "$skill_file" "without.*status.*complete.*truncat\|truncat.*manifest.*status" \
    "R-003: manifest without status:complete indicates truncation"
}

# ============================================
# R-004 [unit]: Resumption check reads manifest and reports missed steps
# ============================================

test_r004_resumption_reads_manifest() {
  echo ""
  echo "=== R-004: Resumption check reads manifest and reports missed steps ==="

  local skill_file="$REPO_DIR/skills/cauto/SKILL.md"

  # R-004: resumption check reads existing pipeline manifest
  file_contains_i "$skill_file" "read.*pipeline.*manifest\|existing.*pipeline.*manifest\|manifest.*exist.*status.*not.*complete" \
    "R-004: resumption check reads existing pipeline manifest"

  # R-004: reports which steps were missed
  file_contains_i "$skill_file" "missing.*steps\|missed.*steps\|steps.*missed" \
    "R-004: reports which steps were missed"

  # R-004: report format includes truncation point
  file_contains_i "$skill_file" "truncated.*at.*step\|last_completed" \
    "R-004: report format includes truncation point"

  # R-004: workflow state is authoritative over manifest
  file_contains_i "$skill_file" "workflow.*state.*authoritative\|authoritative.*workflow\|manifest.*advisory" \
    "R-004: workflow state is authoritative over manifest"
}

# ============================================
# R-005 [unit]: Pipeline summary shows completeness line
# ============================================

test_r005_pipeline_summary_completeness() {
  echo ""
  echo "=== R-005: Pipeline summary shows completeness line ==="

  local skill_file="$REPO_DIR/skills/cauto/SKILL.md"

  # R-005: Step 10 pipeline summary includes completeness line
  file_contains_i "$skill_file" "Pipeline.*Completeness\|pipeline.*completeness" \
    "R-005: pipeline summary includes Pipeline Completeness line"

  # R-005: shows completed_count/expected_count format
  file_contains_i "$skill_file" "completed_count.*expected_count\|{completed_count}/{expected_count}" \
    "R-005: shows completed_count/expected_count format"

  # R-005: all steps complete shows "(all steps completed)"
  file_contains "$skill_file" "all steps completed" \
    "R-005: all steps complete shows (all steps completed)"

  # R-005: missing steps shows incomplete with list
  file_contains_i "$skill_file" "incomplete.*missing_steps\|incomplete.*missing" \
    "R-005: missing steps shows incomplete with list"
}

# ============================================
# R-006 [unit]: Manifest is ephemeral — not committed in consolidation
# ============================================

test_r006_manifest_ephemeral() {
  echo ""
  echo "=== R-006: Manifest is ephemeral — not committed ==="

  local skill_file="$REPO_DIR/skills/cauto/SKILL.md"

  # R-006: manifest is ephemeral artifact
  file_contains_i "$skill_file" "ephemeral.*manifest\|manifest.*ephemeral\|manifest.*not.*commit" \
    "R-006: manifest is documented as ephemeral"

  # R-006: manifest is under .correctless/artifacts/ which is excluded by Step 8.2
  # The Step 8.2 belt-and-suspenders guard already unstages .correctless/artifacts/
  # So the manifest is covered by the existing guard (with probe-results exception per INV-014)
  file_contains_i "$skill_file" "unstage.*artifact\|reset HEAD.*\\.correctless/artifacts\|\.correctless/artifacts/" \
    "R-006: Step 8.2 unstages .correctless/artifacts/ (covers manifest)"
}

# ============================================
# R-007 [unit]: SKILL.md description includes post-return auto-resume
# ============================================

test_r007_description_auto_resume() {
  echo ""
  echo "=== R-007: SKILL.md description includes post-return auto-resume ==="

  local skill_file="$REPO_DIR/skills/cauto/SKILL.md"

  # R-007: description field includes the auto-resume sentence
  # Extract the YAML frontmatter description line
  local desc_line
  desc_line="$(sed -n '/^---$/,/^---$/p' "$skill_file" | grep '^description:')"

  assert_contains "R-007: description includes auto-resume sentence" \
    "verify the workflow reached the expected end state" "$desc_line"
}

# ============================================
# R-008 [unit]: Manifest expected_steps reflects intensity-aware pipeline
# ============================================

test_r008_manifest_intensity_aware() {
  echo ""
  echo "=== R-008: Manifest expected_steps reflects intensity ==="

  local skill_file="$REPO_DIR/skills/cauto/SKILL.md"

  # R-008: manifest expected_steps reflects current intensity
  file_contains_i "$skill_file" "expected_steps.*intensity\|intensity.*expected_steps\|expected_steps.*reflect.*intensity" \
    "R-008: expected_steps reflects current intensity"

  # R-008: at standard intensity, cupdate-arch is excluded from expected_steps
  file_contains_i "$skill_file" "standard.*cupdate-arch.*skip\|standard.*exclude.*cupdate-arch\|cupdate-arch.*skip.*standard" \
    "R-008: standard intensity excludes cupdate-arch from expected_steps"

  # R-008: step list derived from canonical step name enum (R-010)
  file_contains_i "$skill_file" "expected_steps.*canonical\|canonical.*step.*name.*enum\|step.*name.*enum.*expected" \
    "R-008: step list derived from canonical step name enum"
}

# ============================================
# R-009 [unit]: /cstatus checks for pipeline manifest
# ============================================

test_r009_cstatus_checks_manifest() {
  echo ""
  echo "=== R-009: /cstatus checks for pipeline manifest ==="

  local cstatus_file="$REPO_DIR/skills/cstatus/SKILL.md"

  # R-009: cstatus references pipeline manifest path
  file_contains "$cstatus_file" "pipeline-manifest-" \
    "R-009: cstatus references pipeline-manifest path"

  # R-009: cstatus checks if manifest exists and status is not complete
  file_contains_i "$cstatus_file" "status.*not.*complete\|manifest.*exist.*status" \
    "R-009: cstatus checks manifest exists and status is not complete"

  # R-009: cstatus reports incomplete pipeline detected
  file_contains_i "$cstatus_file" "Incomplete.*pipeline.*detected\|incomplete.*pipeline" \
    "R-009: cstatus reports incomplete pipeline detected"

  # R-009: cstatus shows last completed step
  file_contains_i "$cstatus_file" "Last.*completed.*step\|last_completed" \
    "R-009: cstatus shows last completed step"

  # R-009: cstatus shows missing steps
  file_contains_i "$cstatus_file" "Missing.*steps\|missing.*steps" \
    "R-009: cstatus shows missing steps"

  # R-009: cstatus shows expected end phase and current phase
  file_contains_i "$cstatus_file" "expected.*end.*phase\|expected_end_phase.*current.*phase" \
    "R-009: cstatus shows expected end phase and current phase"

  # R-009: cstatus suggests running /cauto to resume
  file_contains_i "$cstatus_file" "Run.*cauto.*resume\|/cauto.*resume" \
    "R-009: cstatus suggests running /cauto to resume"

  # R-009: cstatus is dormant when manifest absent or status is complete (PAT-019)
  file_contains_i "$cstatus_file" "manifest.*no.*output\|manifest.*dormant\|manifest.*does not exist.*no\|manifest.*complete.*no.*output" \
    "R-009: cstatus dormant when manifest absent or complete"

  # R-009: workflow state is authoritative
  file_contains_i "$cstatus_file" "manifest.*workflow.*state.*authoritative\|manifest.*authoritative\|manifest.*diagnostic.*signal" \
    "R-009: cstatus notes workflow state is authoritative"
}

# ============================================
# R-010 [unit]: Canonical step name enum
# ============================================

test_r010_canonical_step_names() {
  echo ""
  echo "=== R-010: Canonical step name enum ==="

  local skill_file="$REPO_DIR/skills/cauto/SKILL.md"

  # R-010: SKILL.md defines canonical step name enum
  file_contains_i "$skill_file" "canonical.*step.*name\|step.*name.*enum" \
    "R-010: SKILL.md defines canonical step name enum"

  # R-010: high+ intensity enum includes all 7 steps
  file_contains "$skill_file" "ctdd" \
    "R-010: enum includes ctdd"
  file_contains "$skill_file" "simplify" \
    "R-010: enum includes simplify"
  file_contains "$skill_file" "cverify" \
    "R-010: enum includes cverify"
  file_contains "$skill_file" "cupdate-arch" \
    "R-010: enum includes cupdate-arch"
  file_contains "$skill_file" "cdocs" \
    "R-010: enum includes cdocs"
  file_contains "$skill_file" "consolidation" \
    "R-010: enum includes consolidation"

  # R-010: "pr" step name appears in the enum context
  # Need to verify "pr" appears as a step name, not just any occurrence
  file_contains_i "$skill_file" '"pr"' \
    "R-010: enum includes pr as a quoted step name"

  # R-010: standard intensity enum excludes cupdate-arch
  # The SKILL.md should show both enums — high+ with 7 steps, standard with 6
  file_contains_i "$skill_file" "standard.*intensity.*ctdd.*simplify.*cverify.*cdocs.*consolidation.*pr\|standard.*6\|standard.*without.*cupdate" \
    "R-010: standard intensity enum excludes cupdate-arch"

  # R-010: enum is single source of truth for expected_steps and completed_steps
  file_contains_i "$skill_file" "single.*source.*truth\|source.*truth.*expected_steps\|source.*truth.*completed_steps" \
    "R-010: enum is single source of truth for expected_steps and completed_steps"
}

# ============================================
# R-011 [unit]: ABS-031 entry in ARCHITECTURE.md
# ============================================

test_r011_abs031_architecture_entry() {
  echo ""
  echo "=== R-011: ABS-031 entry in ARCHITECTURE.md ==="

  # ABS-031 body moved to the abstractions fragment (index+body-out fragmentation);
  # every check below reads ABS-031 content, and the fragment carries heading + body.
  local arch="$REPO_DIR/docs/architecture/abstractions.md"

  # R-011: ARCHITECTURE.md has ABS-031
  file_contains "$arch" "ABS-031" \
    "R-011: ARCHITECTURE.md has ABS-031 entry"

  # R-011: ABS-031 mentions pipeline manifest
  file_contains_i "$arch" "ABS-031.*pipeline.*manifest\|pipeline.*manifest.*ABS-031\|pipeline-manifest" \
    "R-011: ABS-031 mentions pipeline manifest"

  # R-011: ABS-031 names /cauto as sole writer
  file_contains_i "$arch" "Sole writer.*cauto" \
    "R-011: ABS-031 names /cauto as sole writer"

  # R-011: ABS-031 names consumers: /cauto resumption and /cstatus
  file_contains_i "$arch" "Consumer.*cauto.*cstatus\|Consumer.*cstatus" \
    "R-011: ABS-031 names consumers"

  # R-011: ABS-031 notes manifest is ephemeral (not committed)
  file_contains_i "$arch" "ABS-031.*ephemeral\|pipeline.*manifest.*ephemeral\|ABS-031.*not.*committed" \
    "R-011: ABS-031 notes manifest is ephemeral"
}

# ============================================
# Runner
# ============================================

echo "============================================="
echo "Pipeline Completeness Verification Test Suite"
echo "============================================="

test_r001_pipeline_manifest_creation
test_r002_append_completed_steps
test_r003_status_complete_final_action
test_r004_resumption_reads_manifest
test_r005_pipeline_summary_completeness
test_r006_manifest_ephemeral
test_r007_description_auto_resume
test_r008_manifest_intensity_aware
test_r009_cstatus_checks_manifest
test_r010_canonical_step_names
test_r011_abs031_architecture_entry

echo ""
echo "============================================="
echo "Results: $PASS passed, $FAIL failed"
echo ""

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
