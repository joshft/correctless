#!/usr/bin/env bash
# Correctless — calm reset prompts test suite
# Tests spec rules R-001 through R-011 from
# docs/specs/add-calm-reset-prompts-to-orchestrators.md
# Run from repo root: bash test-calm-resets.sh

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASS=0
FAIL=0

# ---------------------------------------------------------------------------
# Helpers (matching test-crelease.sh style)
# ---------------------------------------------------------------------------

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (expected '$expected', got '$actual')"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local desc="$1" expected="$2" actual="$3"
  if echo "$actual" | grep -q "$expected"; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (expected output to contain '$expected')"
    FAIL=$((FAIL + 1))
  fi
}

# Check if a file contains a pattern (returns 0 if found)
file_contains() {
  grep -qi "$2" "$1" 2>/dev/null
}

# Check if a file does NOT contain a pattern (returns 0 if not found)
file_not_contains() {
  ! grep -qi "$2" "$1" 2>/dev/null
}

# Extract reset sections from a SKILL.md file into a temp file.
# Captures text between known reset section headers and the next ### or ## header.
# Usage: extract_reset_sections <skill_file> <output_file>
extract_reset_sections() {
  local skill_file="$1" output_file="$2"
  true > "$output_file"
  local in_section=false
  while IFS= read -r line; do
    # Check if this line is a known reset section header
    if echo "$line" | grep -qE '^### (GREEN Phase Calm Reset|Fix Round Calm Reset|QA Fix Round Calm Reset|Reset Escalation|Divergence Calm Reset|Reset Escalation and Tracking)'; then
      in_section=true
      echo "$line" >> "$output_file"
      continue
    fi
    # If we hit another header, stop capturing
    if $in_section && echo "$line" | grep -qE '^#{2,3} '; then
      in_section=false
      continue
    fi
    if $in_section; then
      echo "$line" >> "$output_file"
    fi
  done < "$skill_file"
}

# Check that a pattern does NOT appear in reset sections of a file
# Usage: reset_section_not_contains <skill_file> <pattern>
reset_section_not_contains() {
  local skill_file="$1" pattern="$2"
  local tmpfile
  tmpfile=$(mktemp)
  extract_reset_sections "$skill_file" "$tmpfile"
  local result
  if ! grep -qi "$pattern" "$tmpfile" 2>/dev/null; then
    result=0
  else
    result=1
  fi
  rm -f "$tmpfile"
  return $result
}

# ---------------------------------------------------------------------------
# Skill file paths
# ---------------------------------------------------------------------------

CTDD_SKILL="$REPO_DIR/skills/ctdd/SKILL.md"
CAUDIT_SKILL="$REPO_DIR/skills/caudit/SKILL.md"

LITE_CTDD="$REPO_DIR/correctless-lite/skills/ctdd/SKILL.md"
FULL_CTDD="$REPO_DIR/correctless-full/skills/ctdd/SKILL.md"
FULL_CAUDIT="$REPO_DIR/correctless-full/skills/caudit/SKILL.md"

# ---------------------------------------------------------------------------
# Test: R-001 — ctdd GREEN phase reset prompt
# ---------------------------------------------------------------------------

test_r001_green_phase_reset() {
  echo ""
  echo "=== R-001: ctdd GREEN phase reset prompt ==="

  local skill="$CTDD_SKILL"

  # R-001(a): stop building on previous failed approaches
  file_contains "$skill" "stop.*build.*previous\|stop.*failed.*approach\|abandon.*previous" \
    && local has_stop="true" || local has_stop="false"
  assert_eq "R-001a: ctdd GREEN reset tells agent to stop building on failed approaches" "true" "$has_stop"

  # R-001(b): re-read the spec rule and failing test output
  file_contains "$skill" "re-read.*spec\|re-read.*test" \
    && local has_reread="true" || local has_reread="false"
  assert_eq "R-001b: ctdd GREEN reset instructs to re-read spec and test" "true" "$has_reread"

  # R-001(c): "what is the test ACTUALLY checking"
  file_contains "$skill" "what is the test ACTUALLY checking" \
    && local has_question="true" || local has_question="false"
  assert_eq "R-001c: ctdd GREEN reset asks 'what is the test ACTUALLY checking'" "true" "$has_question"

  # R-001(d): no time pressure
  file_contains "$skill" "no time pressure\|no rush\|there is no rush\|there's no rush" \
    && local has_calm="true" || local has_calm="false"
  assert_eq "R-001d: ctdd GREEN reset states no time pressure" "true" "$has_calm"

  # R-001: trigger threshold — 3 consecutive failures
  file_contains "$skill" "3.*consecutive.*fail\|3.*failed.*attempt\|attempt.*count.*reach.*3\|3 or more.*fail" \
    && local has_threshold="true" || local has_threshold="false"
  assert_eq "R-001: ctdd GREEN reset triggers on 3+ consecutive failures" "true" "$has_threshold"

  # R-001: tracked by orchestrator, not a new state file
  file_contains "$skill" "working memory\|conversation context\|orchestrator.*track\|track.*attempt" \
    && local has_tracking="true" || local has_tracking="false"
  assert_eq "R-001: attempt count tracked by orchestrator context" "true" "$has_tracking"

  # R-001: GREEN-context discriminator — this header only appears in the GREEN section, not fix round
  file_contains "$skill" "GREEN Phase Calm Reset" \
    && local has_green_header="true" || local has_green_header="false"
  assert_eq "R-001: ctdd has 'GREEN Phase Calm Reset' section header" "true" "$has_green_header"
}

# ---------------------------------------------------------------------------
# Test: R-002 — ctdd QA fix round reset (recurring BLOCKINGs)
# ---------------------------------------------------------------------------

test_r002_qa_fix_round_reset() {
  echo ""
  echo "=== R-002: ctdd QA fix round reset (recurring BLOCKINGs) ==="

  local skill="$CTDD_SKILL"

  # R-002(a): reframe QA findings as descriptions of desired behavior, not criticism
  file_contains "$skill" "description.*desired behavior\|not criticism\|desired behavior.*not criticism\|behavior.*not.*criticism" \
    && local has_reframe="true" || local has_reframe="false"
  assert_eq "R-002a: ctdd fix round reset reframes findings as behavior descriptions" "true" "$has_reframe"

  # R-002(b): re-read instance_fix and class_fix from findings JSON
  file_contains "$skill" "re-read.*instance_fix\|re-read.*class_fix\|instance_fix.*class_fix\|re-read.*finding.*JSON\|re-read.*findings" \
    && local has_reread="true" || local has_reread="false"
  assert_eq "R-002b: ctdd fix round reset instructs re-read of instance_fix/class_fix" "true" "$has_reread"

  # R-002(c): do not re-attempt the same approach
  file_contains "$skill" "not re-attempt.*same\|different approach\|do not.*same approach\|don't.*same approach" \
    && local has_different="true" || local has_different="false"
  assert_eq "R-002c: ctdd fix round reset says not to re-attempt same approach" "true" "$has_different"

  # R-002: trigger — recurring BLOCKINGs across QA rounds
  # Must mention recurring BLOCKINGs in reset-specific context (not the existing "prevents recurrence" line)
  file_contains "$skill" "recurring BLOCKING\|BLOCKING.*didn't stick\|BLOCKING findings.*after.*previous fix\|2.*BLOCKING.*reset" \
    && local has_trigger="true" || local has_trigger="false"
  assert_eq "R-002: trigger mentions recurring BLOCKINGs across QA rounds" "true" "$has_trigger"
}

# ---------------------------------------------------------------------------
# Test: R-003 — caudit divergence reset
# ---------------------------------------------------------------------------

test_r003_caudit_divergence_reset() {
  echo ""
  echo "=== R-003: caudit divergence reset ==="

  local skill="$CAUDIT_SKILL"

  # R-003(a): divergence means fixes introducing new issues — reset-specific language
  # The existing caudit mentions "Divergence" in a brief check, but the reset prompt must be
  # a full instruction paragraph, not just "check if fixes introduced regressions"
  file_contains "$skill" "divergence.*reset prompt\|reset.*diverge\|calm.*diverge\|diverging.*instead of converging" \
    && local has_diverge="true" || local has_diverge="false"
  assert_eq "R-003a: caudit has divergence reset prompt (not just existing check)" "true" "$has_diverge"

  # R-003(b): re-read original findings before the fix attempt
  file_contains "$skill" "re-read.*original.*finding\|re-read.*findings.*before" \
    && local has_reread="true" || local has_reread="false"
  assert_eq "R-003b: caudit divergence reset instructs re-read of original findings" "true" "$has_reread"

  # R-003(c): make smaller, more isolated changes
  file_contains "$skill" "smaller.*isolated\|isolated.*change\|smaller.*change\|more isolated" \
    && local has_smaller="true" || local has_smaller="false"
  assert_eq "R-003c: caudit divergence reset instructs smaller isolated changes" "true" "$has_smaller"

  # R-003: trigger — more findings than previous round (in reset context)
  file_contains "$skill" "reset.*more findings\|more findings.*reset\|reset.*diverge\|diverge.*reset.*prompt\|round.*more.*finding.*reset" \
    && local has_trigger="true" || local has_trigger="false"
  assert_eq "R-003: caudit divergence trigger in reset context" "true" "$has_trigger"
}

# ---------------------------------------------------------------------------
# Test: R-004 — human escalation in every reset
# ---------------------------------------------------------------------------

test_r004_human_escalation() {
  echo ""
  echo "=== R-004: human escalation in every reset prompt ==="

  local ctdd="$CTDD_SKILL"
  local caudit="$CAUDIT_SKILL"

  # R-004: ctdd must include human escalation in reset context
  file_contains "$ctdd" "reset.*ask the human\|reset.*human.*guidance\|still stuck.*ask the human\|stuck.*ask.*human.*guidance" \
    && local ctdd_human="true" || local ctdd_human="false"
  assert_eq "R-004: ctdd reset includes human escalation option" "true" "$ctdd_human"

  # R-004: caudit must include human escalation in a reset prompt context
  # Existing caudit mentions "escalate to human" for oscillation, but the reset prompt
  # must specifically say "ask the human for guidance" near reset language
  file_contains "$caudit" "reset.*ask the human\|reset.*human.*guidance\|still stuck.*ask the human" \
    && local caudit_human="true" || local caudit_human="false"
  assert_eq "R-004: caudit reset includes human escalation option" "true" "$caudit_human"

  # R-004: the exact phrasing per spec — "stop and ask the human for guidance"
  file_contains "$ctdd" "stop and ask the human for guidance\|ask the human for guidance" \
    && local ctdd_exact="true" || local ctdd_exact="false"
  assert_eq "R-004: ctdd uses 'ask the human for guidance' phrasing" "true" "$ctdd_exact"

  # caudit: the exact phrasing must appear in a reset context (not just oscillation handling)
  file_contains "$caudit" "still stuck.*ask the human for guidance\|reset.*ask the human for guidance" \
    && local caudit_exact="true" || local caudit_exact="false"
  assert_eq "R-004: caudit uses 'ask the human for guidance' near reset context" "true" "$caudit_exact"

  # R-004: count-based — ctdd has 3 trigger points (GREEN, fix round, QA recurring), each needs escalation
  local ctdd_escalation_count
  ctdd_escalation_count=$(grep -ci 'ask the human for guidance' "$ctdd" 2>/dev/null || echo 0)
  assert_eq "R-004: ctdd has >= 3 human escalation phrases" "true" \
    "$([ "$ctdd_escalation_count" -ge 3 ] && echo true || echo false)"

  # R-004: count-based — caudit has 1 trigger point (divergence), needs escalation
  local caudit_escalation_count
  caudit_escalation_count=$(grep -ci 'ask the human for guidance' "$caudit" 2>/dev/null || echo 0)
  assert_eq "R-004: caudit has >= 1 human escalation phrase" "true" \
    "$([ "$caudit_escalation_count" -ge 1 ] && echo true || echo false)"
}

# ---------------------------------------------------------------------------
# Test: R-005 — concrete re-read action in every reset
# ---------------------------------------------------------------------------

test_r005_concrete_reread() {
  echo ""
  echo "=== R-005: concrete re-read action in every reset ==="

  local ctdd="$CTDD_SKILL"
  local caudit="$CAUDIT_SKILL"

  # R-005: ctdd must have re-read instructions in reset context
  file_contains "$ctdd" "reset.*re-read\|re-read.*spec.*fresh\|re-read.*test.*fresh\|re-read.*finding.*fresh" \
    && local ctdd_reread="true" || local ctdd_reread="false"
  assert_eq "R-005: ctdd contains 're-read' action in reset context" "true" "$ctdd_reread"

  # R-005: caudit must have re-read instructions in a reset prompt context
  # Existing caudit mentions "re-read" in agent crash recovery, so look for reset-specific re-read
  file_contains "$caudit" "reset.*re-read\|re-read.*original.*finding\|re-read.*before.*fix" \
    && local caudit_reread="true" || local caudit_reread="false"
  assert_eq "R-005: caudit contains 're-read' action in reset prompts" "true" "$caudit_reread"

  # R-005: ctdd re-read targets specific artifacts (spec, test, finding, error)
  file_contains "$ctdd" "re-read.*spec\|re-read.*test\|re-read.*finding\|re-read.*error" \
    && local ctdd_specific="true" || local ctdd_specific="false"
  assert_eq "R-005: ctdd re-read targets a specific artifact" "true" "$ctdd_specific"

  # R-005: caudit re-read targets specific artifacts in reset context
  file_contains "$caudit" "re-read.*original.*finding\|re-read.*finding.*before\|reset.*re-read" \
    && local caudit_specific="true" || local caudit_specific="false"
  assert_eq "R-005: caudit re-read targets a specific artifact in reset" "true" "$caudit_specific"

  # R-005: count-based — ctdd has 3 trigger points (GREEN, fix round, QA recurring), each needs re-read
  local ctdd_reread_count
  ctdd_reread_count=$(grep -c 're-read\|Re-read\|reread' "$ctdd" 2>/dev/null || echo 0)
  assert_eq "R-005: ctdd has >= 3 re-read directives" "true" \
    "$([ "$ctdd_reread_count" -ge 3 ] && echo true || echo false)"

  # R-005: count-based — caudit has 1 trigger point (divergence), needs re-read
  local caudit_reread_count
  caudit_reread_count=$(grep -c 're-read\|Re-read\|reread' "$caudit" 2>/dev/null || echo 0)
  assert_eq "R-005: caudit has >= 1 re-read directive" "true" \
    "$([ "$caudit_reread_count" -ge 1 ] && echo true || echo false)"
}

# ---------------------------------------------------------------------------
# Test: R-006 — prohibited shortcut words in reset prompts
# ---------------------------------------------------------------------------

test_r006_no_shortcuts() {
  echo ""
  echo "=== R-006: prohibited shortcut words ==="

  local ctdd="$CTDD_SKILL"
  local caudit="$CAUDIT_SKILL"

  # R-006: whole-file checks for words that don't appear anywhere
  file_not_contains "$ctdd" "simpler approach" \
    && local ctdd_no_simpler="true" || local ctdd_no_simpler="false"
  assert_eq "R-006: ctdd does not contain 'simpler approach'" "true" "$ctdd_no_simpler"

  file_not_contains "$caudit" "simpler approach" \
    && local caudit_no_simpler="true" || local caudit_no_simpler="false"
  assert_eq "R-006: caudit does not contain 'simpler approach'" "true" "$caudit_no_simpler"

  file_not_contains "$ctdd" "good enough" \
    && local ctdd_no_good="true" || local ctdd_no_good="false"
  assert_eq "R-006: ctdd does not contain 'good enough'" "true" "$ctdd_no_good"

  file_not_contains "$caudit" "good enough" \
    && local caudit_no_good="true" || local caudit_no_good="false"
  assert_eq "R-006: caudit does not contain 'good enough'" "true" "$caudit_no_good"

  file_not_contains "$ctdd" "workaround" \
    && local ctdd_no_workaround="true" || local ctdd_no_workaround="false"
  assert_eq "R-006: ctdd does not contain 'workaround'" "true" "$ctdd_no_workaround"

  file_not_contains "$caudit" "workaround" \
    && local caudit_no_workaround="true" || local caudit_no_workaround="false"
  assert_eq "R-006: caudit does not contain 'workaround'" "true" "$caudit_no_workaround"

  # R-006: section-scoped checks for words that may appear in non-reset text
  # These 3 words can legitimately appear elsewhere, so check only reset sections
  reset_section_not_contains "$ctdd" "skip" \
    && local ctdd_no_skip="true" || local ctdd_no_skip="false"
  assert_eq "R-006: ctdd reset sections do not contain 'skip'" "true" "$ctdd_no_skip"

  reset_section_not_contains "$caudit" "skip" \
    && local caudit_no_skip="true" || local caudit_no_skip="false"
  assert_eq "R-006: caudit reset sections do not contain 'skip'" "true" "$caudit_no_skip"

  reset_section_not_contains "$ctdd" "partial" \
    && local ctdd_no_partial="true" || local ctdd_no_partial="false"
  assert_eq "R-006: ctdd reset sections do not contain 'partial'" "true" "$ctdd_no_partial"

  reset_section_not_contains "$caudit" "partial" \
    && local caudit_no_partial="true" || local caudit_no_partial="false"
  assert_eq "R-006: caudit reset sections do not contain 'partial'" "true" "$caudit_no_partial"

  reset_section_not_contains "$ctdd" "approximate" \
    && local ctdd_no_approx="true" || local ctdd_no_approx="false"
  assert_eq "R-006: ctdd reset sections do not contain 'approximate'" "true" "$ctdd_no_approx"

  reset_section_not_contains "$caudit" "approximate" \
    && local caudit_no_approx="true" || local caudit_no_approx="false"
  assert_eq "R-006: caudit reset sections do not contain 'approximate'" "true" "$caudit_no_approx"

  # R-006 positive: reset prompts exist and redirect to correctness (not shortcuts)
  file_contains "$ctdd" "calm.*reset\|reset prompt\|reset.*re-read\|redirect.*correctness" \
    && local ctdd_correctness="true" || local ctdd_correctness="false"
  assert_eq "R-006: ctdd reset redirects to correctness (reset text exists)" "true" "$ctdd_correctness"

  file_contains "$caudit" "reset.*correct\|redirect.*correct\|reset.*re-read\|calm.*reset" \
    && local caudit_correctness="true" || local caudit_correctness="false"
  assert_eq "R-006: caudit reset redirects to correctness (reset text exists)" "true" "$caudit_correctness"
}

# ---------------------------------------------------------------------------
# Test: R-007 — trigger thresholds stated in SKILL.md
# ---------------------------------------------------------------------------

test_r007_trigger_thresholds() {
  echo ""
  echo "=== R-007: trigger thresholds stated in SKILL.md ==="

  local ctdd="$CTDD_SKILL"
  local caudit="$CAUDIT_SKILL"

  # R-007: ctdd GREEN phase — 3+ consecutive failures
  file_contains "$ctdd" "3.*consecutive.*fail\|3.*failed.*attempt\|3 or more.*consecutive" \
    && local ctdd_green_threshold="true" || local ctdd_green_threshold="false"
  assert_eq "R-007: ctdd states GREEN phase threshold (3+ consecutive failures)" "true" "$ctdd_green_threshold"

  # R-007: ctdd fix round — 3+ consecutive failures within fix phase (R-011)
  file_contains "$ctdd" "3.*consecutive.*fail.*fix\|fix.*3.*consecutive\|fix.*phase.*3.*fail" \
    && local ctdd_fix_threshold="true" || local ctdd_fix_threshold="false"
  assert_eq "R-007: ctdd states fix round threshold (3+ consecutive failures)" "true" "$ctdd_fix_threshold"

  # R-007: ctdd QA fix round — 2+ BLOCKING after previous fix round in reset context
  # Existing ctdd mentions "BLOCKING" in QA agent instructions, so look for reset-specific threshold
  file_contains "$ctdd" "2.*BLOCKING.*reset\|2.*BLOCKING.*recurring\|recurring.*2.*BLOCKING\|reset.*2.*BLOCKING" \
    && local ctdd_qa_threshold="true" || local ctdd_qa_threshold="false"
  assert_eq "R-007: ctdd states QA fix round threshold (2+ BLOCKING) in reset context" "true" "$ctdd_qa_threshold"

  # R-007: caudit — finding count comparison (divergence)
  file_contains "$caudit" "more findings.*previous\|finding.*count.*>.*previous\|findings_count.*>.*findings_count" \
    && local caudit_threshold="true" || local caudit_threshold="false"
  assert_eq "R-007: caudit states divergence threshold (finding count comparison)" "true" "$caudit_threshold"

  # R-007: thresholds are not configurable — hardcoded in instruction text
  file_not_contains "$ctdd" "configurable.*threshold\|threshold.*config\|reset_threshold" \
    && local not_configurable="true" || local not_configurable="false"
  assert_eq "R-007: thresholds are not configurable (no config references)" "true" "$not_configurable"

  # R-007 positive: thresholds are stated as literal numbers in SKILL.md (not variables)
  # The number "3" should appear near "consecutive" and "fail" for GREEN/fix thresholds
  file_contains "$ctdd" "3.*consecutive\|consecutive.*3" \
    && local has_literal="true" || local has_literal="false"
  assert_eq "R-007: threshold is a literal number (3 near consecutive)" "true" "$has_literal"
}

# ---------------------------------------------------------------------------
# Test: R-008 — one reset per trigger, then escalate
# ---------------------------------------------------------------------------

test_r008_reset_cap_and_escalation() {
  echo ""
  echo "=== R-008: one reset per trigger, then escalate ==="

  local ctdd="$CTDD_SKILL"

  # R-008: at most once per trigger point per phase
  file_contains "$ctdd" "once.*per.*trigger\|once.*per.*phase\|at most once.*trigger\|at most once.*per.*phase\|no stacking" \
    && local has_cap="true" || local has_cap="false"
  assert_eq "R-008: ctdd states resets fire at most once per trigger per phase" "true" "$has_cap"

  # R-008: escalation includes attempts made
  file_contains "$ctdd" "attempts.*made\|how many attempts\|attempt.*count.*summary\|number of attempts" \
    && local has_attempts="true" || local has_attempts="false"
  assert_eq "R-008: escalation includes how many attempts were made" "true" "$has_attempts"

  # R-008: escalation includes approaches tried
  file_contains "$ctdd" "approaches tried\|summary.*approach\|what was tried\|approaches.*attempted" \
    && local has_approaches="true" || local has_approaches="false"
  assert_eq "R-008: escalation includes approaches tried" "true" "$has_approaches"

  # R-008: escalation message co-occurrence — all four components must appear in the SKILL.md
  # (attempts made, approaches tried, current error, human ask) — verified individually but
  # with escalation-specific context to avoid matching unrelated content
  file_contains "$ctdd" "escalat.*current error\|escalat.*failing test\|reset.*current error\|reset.*failing test" \
    && local has_error="true" || local has_error="false"
  assert_eq "R-008: escalation includes current error or failing test" "true" "$has_error"

  # R-008: escalation mentions /cdebug in the reset escalation context
  file_contains "$ctdd" "escalat.*/cdebug\|/cdebug.*reset.*escalat\|reset.*escalat.*/cdebug\|attempt.*fail.*/cdebug" \
    && local has_cdebug="true" || local has_cdebug="false"
  assert_eq "R-008: reset escalation mentions /cdebug option" "true" "$has_cdebug"

  # R-008: explicit ask for human guidance in the reset escalation
  file_contains "$ctdd" "reset.*ask.*human\|escalat.*ask.*human.*guidance\|still stuck.*ask the human" \
    && local has_ask="true" || local has_ask="false"
  assert_eq "R-008: reset escalation asks for human guidance" "true" "$has_ask"

  # R-008: caudit — at most once per round
  local caudit="$CAUDIT_SKILL"

  file_contains "$caudit" "at most once.*per.*round\|once.*per.*round" \
    && local caudit_cap="true" || local caudit_cap="false"
  assert_eq "R-008: caudit states resets fire at most once per round" "true" "$caudit_cap"

  # R-008: caudit — escalation includes human guidance
  file_contains "$caudit" "escalat.*human\|human.*guidance\|escalat.*guidance" \
    && local caudit_escalate="true" || local caudit_escalate="false"
  assert_eq "R-008: caudit escalation includes human guidance" "true" "$caudit_escalate"
}

# ---------------------------------------------------------------------------
# Test: R-009 — no new files or state
# ---------------------------------------------------------------------------

test_r009_no_new_state() {
  echo ""
  echo "=== R-009: no new files or state ==="

  local ctdd="$CTDD_SKILL"
  local caudit="$CAUDIT_SKILL"

  # R-009: ctdd tracks attempt counts in working memory / conversation context
  # Must specifically mention tracking attempt counts this way, not just "context" in general
  file_contains "$ctdd" "working memory\|conversation context.*attempt\|attempt.*conversation context\|track.*attempt.*context\|attempt.*count.*orchestrator" \
    && local ctdd_context="true" || local ctdd_context="false"
  assert_eq "R-009: ctdd tracks attempt counts in orchestrator context" "true" "$ctdd_context"

  # R-009: caudit tracks state in working memory / conversation context
  file_contains "$caudit" "working memory\|conversation context.*track\|track.*conversation context\|finding.*count.*orchestrator.*context" \
    && local caudit_context="true" || local caudit_context="false"
  assert_eq "R-009: caudit tracks state in orchestrator context" "true" "$caudit_context"

  # R-009: reset prompts should not reference creating new files for tracking
  # Check that no "reset" instruction tells the agent to create a state file
  file_not_contains "$ctdd" "create.*reset.*state\|write.*reset.*file\|persist.*reset.*count\|new.*file.*reset.*track" \
    && local ctdd_no_files="true" || local ctdd_no_files="false"
  assert_eq "R-009: ctdd resets do not create new state files" "true" "$ctdd_no_files"

  file_not_contains "$caudit" "create.*reset.*state\|write.*reset.*file\|persist.*reset.*count\|new.*file.*reset.*track" \
    && local caudit_no_files="true" || local caudit_no_files="false"
  assert_eq "R-009: caudit resets do not create new state files" "true" "$caudit_no_files"
}

# ---------------------------------------------------------------------------
# Test: R-010 — sync propagation to both distributions
# ---------------------------------------------------------------------------

test_r010_sync_propagation() {
  echo ""
  echo "=== R-010: sync propagation to both distributions ==="

  # R-010: lite ctdd SKILL.md exists
  assert_eq "R-010: correctless-lite/skills/ctdd/SKILL.md exists" "true" \
    "$([ -f "$LITE_CTDD" ] && echo true || echo false)"

  # R-010: full ctdd SKILL.md exists
  assert_eq "R-010: correctless-full/skills/ctdd/SKILL.md exists" "true" \
    "$([ -f "$FULL_CTDD" ] && echo true || echo false)"

  # R-010: full caudit SKILL.md exists (caudit is Full-only)
  assert_eq "R-010: correctless-full/skills/caudit/SKILL.md exists" "true" \
    "$([ -f "$FULL_CAUDIT" ] && echo true || echo false)"

  # R-010: lite ctdd contains reset-related keywords after sync
  file_contains "$LITE_CTDD" "reset prompt\|calm reset\|reset.*fire\|consecutive.*fail.*reset" \
    && local lite_ctdd_reset="true" || local lite_ctdd_reset="false"
  assert_eq "R-010: lite ctdd SKILL.md contains reset keywords" "true" "$lite_ctdd_reset"

  # R-010: full ctdd contains reset-related keywords after sync
  file_contains "$FULL_CTDD" "reset prompt\|calm reset\|reset.*fire\|consecutive.*fail.*reset" \
    && local full_ctdd_reset="true" || local full_ctdd_reset="false"
  assert_eq "R-010: full ctdd SKILL.md contains reset keywords" "true" "$full_ctdd_reset"

  # R-010: full caudit contains reset-related keywords after sync
  file_contains "$FULL_CAUDIT" "reset prompt\|calm reset\|reset.*fire\|diverge.*reset\|divergence.*reset" \
    && local full_caudit_reset="true" || local full_caudit_reset="false"
  assert_eq "R-010: full caudit SKILL.md contains reset keywords" "true" "$full_caudit_reset"

  # R-010: the "re-read" keyword propagated to distributions
  file_contains "$LITE_CTDD" "re-read" \
    && local lite_reread="true" || local lite_reread="false"
  assert_eq "R-010: lite ctdd SKILL.md contains 're-read' after sync" "true" "$lite_reread"

  file_contains "$FULL_CTDD" "re-read" \
    && local full_reread="true" || local full_reread="false"
  assert_eq "R-010: full ctdd SKILL.md contains 're-read' after sync" "true" "$full_reread"

  # R-010: sync.sh --check exits 0 when source and distribution are in sync
  bash "$REPO_DIR/sync.sh" --check 2>/dev/null \
    && local sync_clean="true" || local sync_clean="false"
  assert_eq "R-010: sync.sh --check passes (source and dist in sync)" "true" "$sync_clean"

  # R-010 negative: skills that are NOT ctdd or caudit must NOT contain calm reset text
  local negative_ok="true"
  for skill_dir in "$REPO_DIR"/correctless-lite/skills/*/; do
    local skill_name
    skill_name="$(basename "$skill_dir")"
    [ "$skill_name" = "ctdd" ] && continue
    [ "$skill_name" = "caudit" ] && continue
    local skill_file="$skill_dir/SKILL.md"
    [ -f "$skill_file" ] || continue
    if grep -qi 'calm reset\|calm.*reset.*prompt' "$skill_file" 2>/dev/null; then
      echo "    NOTE: $skill_name SKILL.md unexpectedly contains calm reset text"
      negative_ok="false"
    fi
  done
  assert_eq "R-010: non-ctdd/caudit lite skills do not contain calm reset text" "true" "$negative_ok"
}

# ---------------------------------------------------------------------------
# Test: R-011 — fix-round-specific reset (distinct from R-001)
# ---------------------------------------------------------------------------

test_r011_fix_round_reset() {
  echo ""
  echo "=== R-011: fix-round-specific reset (distinct from R-001 GREEN) ==="

  local skill="$CTDD_SKILL"

  # R-011: fix phase / fix round context for reset
  file_contains "$skill" "fix.*phase.*reset\|fix round.*reset\|reset.*fix.*phase\|fix.*reset prompt" \
    && local has_fix_context="true" || local has_fix_context="false"
  assert_eq "R-011: ctdd has fix-round-specific reset prompt" "true" "$has_fix_context"

  # R-011(a): stop building on previous failed approaches (in fix context — distinct from R-001)
  file_contains "$skill" "fix.*stop.*failed\|fix.*abandon.*previous\|fix.*stop.*build" \
    && local has_stop="true" || local has_stop="false"
  assert_eq "R-011a: fix round reset tells agent to stop building on failed approaches" "true" "$has_stop"

  # R-011(b): re-read instance_fix and class_fix from findings JSON
  file_contains "$skill" "re-read.*instance_fix\|re-read.*class_fix\|instance_fix.*class_fix" \
    && local has_reread_fix="true" || local has_reread_fix="false"
  assert_eq "R-011b: fix round reset instructs re-read of instance_fix/class_fix" "true" "$has_reread_fix"

  # R-011(c): "what is the finding ACTUALLY describing"
  file_contains "$skill" "what is the finding ACTUALLY describing" \
    && local has_question="true" || local has_question="false"
  assert_eq "R-011c: fix round reset asks 'what is the finding ACTUALLY describing'" "true" "$has_question"

  # R-011(d): no time pressure (in fix context — distinct from R-001)
  file_contains "$skill" "fix.*no rush\|fix.*no time pressure\|fix.*there is no rush" \
    && local has_calm="true" || local has_calm="false"
  assert_eq "R-011d: fix round reset states no time pressure" "true" "$has_calm"

  # R-011: trigger — 3+ consecutive failures within a single fix round
  file_contains "$skill" "3.*consecutive.*fail.*fix\|fix.*3.*consecutive\|3.*fail.*fix.*phase" \
    && local has_threshold="true" || local has_threshold="false"
  assert_eq "R-011: fix round reset triggers on 3+ consecutive failures" "true" "$has_threshold"
}

# ---------------------------------------------------------------------------
# Test: Structural — SKILL.md files maintain expected structure
# ---------------------------------------------------------------------------

test_structural() {
  echo ""
  echo "=== Structural: SKILL.md files maintain expected structure ==="

  local ctdd="$CTDD_SKILL"
  local caudit="$CAUDIT_SKILL"

  # ctdd should have grown with reset additions (baseline ~479 lines)
  local ctdd_lines
  ctdd_lines="$(wc -l < "$ctdd" 2>/dev/null || echo 0)"
  assert_eq "Structural: ctdd SKILL.md has grown from baseline (~479 → 500+)" "true" \
    "$([ "$ctdd_lines" -ge 500 ] && echo true || echo false)"

  # caudit should have grown with reset additions (baseline ~488 lines)
  local caudit_lines
  caudit_lines="$(wc -l < "$caudit" 2>/dev/null || echo 0)"
  assert_eq "Structural: caudit SKILL.md has grown from baseline (~488 → 510+)" "true" \
    "$([ "$caudit_lines" -ge 510 ] && echo true || echo false)"

  # ctdd still has core phase headers
  file_contains "$ctdd" "## Phase: RED" \
    && local has_red="true" || local has_red="false"
  assert_eq "Structural: ctdd still has '## Phase: RED' header" "true" "$has_red"

  file_contains "$ctdd" "## Phase: GREEN" \
    && local has_green="true" || local has_green="false"
  assert_eq "Structural: ctdd still has '## Phase: GREEN' header" "true" "$has_green"

  file_contains "$ctdd" "## Phase: QA" \
    && local has_qa="true" || local has_qa="false"
  assert_eq "Structural: ctdd still has '## Phase: QA' header" "true" "$has_qa"

  # caudit still has core structure
  file_contains "$caudit" "## The Loop" \
    && local has_loop="true" || local has_loop="false"
  assert_eq "Structural: caudit still has '## The Loop' header" "true" "$has_loop"

  file_contains "$caudit" "## Convergence" \
    && local has_conv="true" || local has_conv="false"
  assert_eq "Structural: caudit still has '## Convergence' header" "true" "$has_conv"
}

# ---------------------------------------------------------------------------
# Runner
# ---------------------------------------------------------------------------

echo "================================="
echo "Calm Reset Prompts — Test Suite"
echo "================================="

test_r001_green_phase_reset
test_r002_qa_fix_round_reset
test_r003_caudit_divergence_reset
test_r004_human_escalation
test_r005_concrete_reread
test_r006_no_shortcuts
test_r007_trigger_thresholds
test_r008_reset_cap_and_escalation
test_r009_no_new_state
test_r010_sync_propagation
test_r011_fix_round_reset
test_structural

echo ""
echo "================================="
echo "Results: $PASS passed, $FAIL failed"
echo ""

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
