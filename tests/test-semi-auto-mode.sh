#!/usr/bin/env bash
# Correctless — Semi-Auto Mode test suite
# Tests spec rules R-001 through R-019 plus prerequisites from
# .correctless/specs/semi-auto-mode.md
# RED phase: these tests MUST FAIL — implementation does not exist yet.
# Run from repo root: bash tests/test-semi-auto-mode.sh

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0

# ============================================
# Helpers (matching project test conventions)
# ============================================

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
  if echo "$actual" | grep -qF "$expected"; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (expected output to contain '$expected')"
    FAIL=$((FAIL + 1))
  fi
}

assert_not_contains() {
  local desc="$1" unexpected="$2" actual="$3"
  if ! echo "$actual" | grep -qF "$unexpected"; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (expected output NOT to contain '$unexpected')"
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

file_not_contains() {
  local file="$1" pattern="$2" desc="$3"
  if grep -q "$pattern" "$file" 2>/dev/null; then
    echo "  FAIL: $desc (pattern '$pattern' should NOT be in $file)"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
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

assert_file_exists() {
  local desc="$1" path="$2"
  if [ -f "$path" ]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (file '$path' does not exist)"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_not_exists() {
  local desc="$1" path="$2"
  if [ ! -f "$path" ]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (file '$path' should not exist)"
    FAIL=$((FAIL + 1))
  fi
}

# Run sensitive-file-guard hook with JSON on stdin, capture exit code and stderr
run_sfg_hook() {
  local json_input="$1"
  local exit_code
  exit_code=0
  echo "$json_input" | bash "$REPO_DIR/hooks/sensitive-file-guard.sh" 2>/dev/null >/dev/null || exit_code=$?
  echo "$exit_code"
}

# ============================================
# R-001 [integration]: /cauto skill invokes skills in exact order
#   and spawns each as a sub-agent for fresh context
# ============================================

test_r001_cauto_skill_order_and_sub_agents() {
  echo ""
  echo "=== R-001: /cauto skill order and sub-agent dispatch ==="

  local skill_file="$REPO_DIR/skills/cauto/SKILL.md"

  # R-001: cauto SKILL.md must exist
  assert_file_exists "R-001: cauto SKILL.md exists" "$skill_file"

  # R-001: cauto must list skills in order: ctdd, simplify, cverify, cupdate-arch, cdocs
  file_contains_i "$skill_file" "ctdd.*simplify.*cverify.*cupdate-arch.*cdocs\|ctdd.*cverify.*cupdate-arch.*cdocs" \
    "R-001: cauto lists skills in pipeline order (ctdd -> simplify -> cverify -> cupdate-arch -> cdocs)"

  # R-001: cauto must document sub-agent dispatch for pipeline skills
  file_contains_i "$skill_file" "sub-agent\|sub_agent\|spawns.*agent" \
    "R-001: cauto documents sub-agent dispatch for pipeline skills"

  # R-001: cauto must instruct creating a commit before simplify ("TDD complete")
  file_contains_i "$skill_file" "commit.*TDD.*complete\|TDD complete.*commit\|commit.*before.*simplify" \
    "R-001: cauto creates commit before simplify (TDD complete revert point)"
}

# ============================================
# R-002 [integration]: /cauto phase gate — review or review-spec only
# ============================================

test_r002_cauto_phase_gate() {
  echo ""
  echo "=== R-002: /cauto phase gate ==="

  local skill_file="$REPO_DIR/skills/cauto/SKILL.md"

  # R-002: cauto must check workflow phase
  file_contains_i "$skill_file" "review.*phase\|phase.*review\|review-spec" \
    "R-002: cauto checks for review/review-spec phase"

  # R-002: cauto must require review (standard) or review-spec (high+)
  file_contains_i "$skill_file" "review-spec\|review.*standard.*review-spec.*high" \
    "R-002: cauto requires review (standard) or review-spec (high+)"

  # R-002: cauto must produce an error for wrong phase
  file_contains_i "$skill_file" "error.*phase\|required.*phase\|must.*be.*review\|only.*invocable.*review" \
    "R-002: cauto produces error for wrong phase"

  # R-002: cauto must contain an explicit phase gate that checks workflow state
  file_contains_i "$skill_file" "workflow.*state\|read.*phase\|current.*phase\|check.*phase" \
    "R-002: cauto contains explicit phase gate (checks workflow state)"

  # R-002: cauto must list both review and review-spec as valid phases
  file_contains "$skill_file" "review" \
    "R-002: cauto mentions review as valid phase"
  file_contains "$skill_file" "review-spec" \
    "R-002: cauto mentions review-spec as valid phase"

  # STRUCTURAL ONLY — cauto is an LLM skill, cannot be mechanically invoked.
  # The SKILL.md must instruct checking phase and refusing for spec, tdd-tests, done
  file_contains_i "$skill_file" "spec.*refuse\|spec.*abort\|not.*valid.*spec\|refuse.*spec\|spec.*not.*allowed\|only.*review\|must.*be.*review" \
    "R-002: cauto refuses to run in spec phase"
}

# ============================================
# R-003 [integration]: /cauto reads preferences.md with fallback
# ============================================

test_r003_cauto_reads_preferences() {
  echo ""
  echo "=== R-003: /cauto reads preferences.md ==="

  local skill_file="$REPO_DIR/skills/cauto/SKILL.md"

  # R-003: cauto must reference preferences.md for reading
  file_contains "$skill_file" "preferences.md" \
    "R-003: cauto SKILL.md references preferences.md"

  # R-003: cauto must contain a Read instruction targeting preferences.md
  file_contains_i "$skill_file" "Read.*preferences.md\|read.*preferences.md\|Read.*\.correctless/preferences" \
    "R-003: cauto has Read instruction for preferences.md"

  # R-003: cauto must contain a fallback clause for missing preferences.md
  file_contains_i "$skill_file" "does not exist.*default\|missing.*default\|fallback.*default\|not.*exist.*proceed\|absent.*default" \
    "R-003: cauto has fallback for missing preferences.md"

  # R-003: cauto must not abort when preferences.md is absent
  file_contains_i "$skill_file" "proceed.*without\|proceed.*default\|not.*fail\|not.*abort" \
    "R-003: cauto proceeds with defaults when preferences.md absent"
}

# ============================================
# R-004 [unit]: preferences.md template has all 5 categories
# ============================================

test_r004_preferences_template_categories() {
  echo ""
  echo "=== R-004: preferences.md template categories ==="

  # The template should exist in templates/ for setup to scaffold from
  local template="$REPO_DIR/templates/preferences.md"

  assert_file_exists "R-004: preferences.md template exists" "$template"

  # R-004a: QA finding triage
  file_contains_i "$template" "qa.*finding.*triage\|qa.*triage\|finding.*triage\|severity.*auto.fix" \
    "R-004a: template has QA finding triage category"

  # R-004b: Documentation scope
  file_contains_i "$template" "documentation.*scope\|doc.*scope\|include.*exclude.*doc" \
    "R-004b: template has documentation scope category"

  # R-004c: Commit granularity
  file_contains_i "$template" "commit.*granularity\|commit.*structure\|how.*structure.*commit" \
    "R-004c: template has commit granularity category"

  # R-004d: Escalation sensitivity
  file_contains_i "$template" "escalation.*sensitivity\|escalation.*threshold\|architectural.*decision.*human" \
    "R-004d: template has escalation sensitivity category"

  # R-004e: PR creation preference
  file_contains_i "$template" "pr.*creation\|pr_creation\|pull.*request.*creation" \
    "R-004e: template has PR creation preference category"

  # R-004: Template should have sensible defaults
  file_contains_i "$template" "default\|recommended" \
    "R-004: template contains sensible defaults"
}

# ============================================
# R-005 [integration]: Escalation file format with YAML frontmatter
# ============================================

test_r005_escalation_file_format() {
  echo ""
  echo "=== R-005: Escalation file format ==="

  local skill_file="$REPO_DIR/skills/cauto/SKILL.md"

  # R-005: cauto must reference escalation file path
  file_contains_i "$skill_file" "escalation.*branch_slug\|escalation-.*\.md\|artifacts/escalation" \
    "R-005: cauto references escalation file path"

  # R-005: escalation uses YAML frontmatter
  file_contains_i "$skill_file" "YAML.*frontmatter\|frontmatter.*YAML\|---.*escalation" \
    "R-005: escalation file uses YAML frontmatter"

  # R-005: required frontmatter fields
  file_contains "$skill_file" "completed_skills" \
    "R-005: escalation frontmatter includes completed_skills"

  file_contains "$skill_file" "failed_skill" \
    "R-005: escalation frontmatter includes failed_skill"

  file_contains "$skill_file" "failed_at_phase" \
    "R-005: escalation frontmatter includes failed_at_phase"

  file_contains "$skill_file" "failed_at_substep" \
    "R-005: escalation frontmatter includes failed_at_substep"

  file_contains "$skill_file" "attempts_before_escalation" \
    "R-005: escalation frontmatter includes attempts_before_escalation"

  file_contains "$skill_file" "pipeline_config" \
    "R-005: escalation frontmatter includes pipeline_config"

  # R-005: attempt thresholds by intensity — standard=3, high=2, critical=2
  # Patterns require the intensity name and threshold to appear in a structured
  # mapping context (e.g. "standard: 3", "standard=3", "standard | 3",
  # "standard.*threshold.*3") to avoid incidental co-occurrence matches.
  file_contains_i "$skill_file" "standard[[:space:]]*[:=|][[:space:]]*3\|standard.*threshold.*3\|standard.*attempt.*3\|3.*attempt.*standard" \
    "R-005: standard intensity threshold is 3 attempts"

  file_contains_i "$skill_file" "high[[:space:]]*[:=|][[:space:]]*2\|high.*threshold.*2\|high.*attempt.*2\|2.*attempt.*high" \
    "R-005: high intensity threshold is 2 attempts"

  file_contains_i "$skill_file" "critical[[:space:]]*[:=|][[:space:]]*2\|critical.*threshold.*2\|critical.*attempt.*2\|2.*attempt.*critical" \
    "R-005: critical intensity threshold is 2 attempts"
}

# ============================================
# R-006 [integration]: Architectural decision escalation heuristics
# ============================================

test_r006_architectural_escalation() {
  echo ""
  echo "=== R-006: Architectural decision escalation ==="

  local skill_file="$REPO_DIR/skills/cauto/SKILL.md"

  # R-006a: adding ABS-xxx or TB-xxx
  file_contains_i "$skill_file" "ABS-.*entry\|TB-.*entry\|new.*ABS\|new.*TB" \
    "R-006a: escalate when adding new ABS-xxx or TB-xxx entry"

  # R-006b: gate blocks ARCHITECTURE.md write
  file_contains_i "$skill_file" "gate.*block.*ARCHITECTURE\|ARCHITECTURE.*gate.*block\|gate-blocked.*ARCHITECTURE" \
    "R-006b: escalate when gate blocks ARCHITECTURE.md write"

  # R-006c: spec rule unsatisfiable without spec change
  file_contains_i "$skill_file" "spec.*cannot.*satisfied\|spec.*change\|spec.*contradict\|unsatisfi" \
    "R-006c: escalate when spec rule requires spec change"

  # R-006d: new dependency required
  file_contains_i "$skill_file" "new.*dependency\|dependency.*not.*project\|dependency.*required" \
    "R-006d: escalate when new dependency is required"

  # R-006e: modifying CLAUDE.md
  file_contains_i "$skill_file" "CLAUDE.md.*escalat\|modif.*CLAUDE.md.*human\|CLAUDE.md.*approval" \
    "R-006e: escalate when modifying CLAUDE.md"

  # R-006: mechanical backstop is R-005
  file_contains_i "$skill_file" "backstop\|R-005.*catch\|failure.*threshold.*catch" \
    "R-006: mechanical backstop via R-005 failure threshold"
}

# ============================================
# R-007 [unit]: "Never auto-invoke" constraint preserved
# ============================================

test_r007_never_auto_invoke_preserved() {
  echo ""
  echo "=== R-007: Never auto-invoke constraint preserved ==="

  local constraints="$REPO_DIR/skills/_shared/constraints.md"
  local skill_file="$REPO_DIR/skills/cauto/SKILL.md"

  # R-007: constraints.md still has "Never auto-invoke"
  file_contains "$constraints" "Never auto-invoke" \
    "R-007: constraints.md contains 'Never auto-invoke'"

  # R-007: cauto does NOT modify constraints.md
  file_not_contains "$skill_file" "modify.*constraints\|edit.*constraints\|write.*constraints\|change.*constraints" \
    "R-007: cauto does not modify constraints.md"

  # R-007: cauto does NOT contain instructions to remove auto-invoke boundary
  file_not_contains "$skill_file" "remove.*auto-invoke\|disable.*auto-invoke\|override.*auto-invoke" \
    "R-007: cauto does not remove auto-invoke boundary"

  # R-007: cauto is the orchestrator that invokes skills — skills don't auto-continue
  file_contains_i "$skill_file" "orchestrat\|invoke.*skill\|orchestrator.*invoke" \
    "R-007: cauto is the orchestrator that invokes skills"
}

# ============================================
# R-008 [integration]: PR creation options
# ============================================

test_r008_pr_creation_options() {
  echo ""
  echo "=== R-008: PR creation options ==="

  local skill_file="$REPO_DIR/skills/cauto/SKILL.md"

  # R-008: gh option (default)
  file_contains_i "$skill_file" "gh.*pr.*create\|pr_creation.*gh\|gh.*default" \
    "R-008: gh PR creation option (default)"

  # R-008: skip option
  file_contains_i "$skill_file" "pr_creation.*skip\|skip.*no.*PR\|skip.*PR" \
    "R-008: skip PR creation option"

  # R-008: custom command option
  file_contains_i "$skill_file" "custom.*command\|custom.*PR.*command\|pr_creation.*custom" \
    "R-008: custom PR command option"

  # R-008: TB-001b reference
  file_contains "$skill_file" "TB-001b" \
    "R-008: references TB-001b trust model for custom commands"

  # R-008: PR body includes required sections (one assertion per section)
  file_contains_i "$skill_file" "summary.*section\|summary.*auto-generated\|summary.*spec.*implementation" \
    "R-008: PR body includes summary section"

  file_contains_i "$skill_file" "test.*plan" \
    "R-008: PR body includes test plan section"

  file_contains_i "$skill_file" "QA.*finding" \
    "R-008: PR body includes QA findings summary"

  file_contains_i "$skill_file" "verification.*status\|verification.*result" \
    "R-008: PR body includes verification status"

  # R-008: PR title derived from spec task name
  file_contains_i "$skill_file" "title.*spec.*task\|task.*name.*title\|title.*derived.*spec" \
    "R-008: PR title derived from spec task name"
}

# ============================================
# R-009 [unit]: Intensity-aware pipeline
# ============================================

test_r009_intensity_pipeline() {
  echo ""
  echo "=== R-009: Intensity-aware pipeline ==="

  local skill_file="$REPO_DIR/skills/cauto/SKILL.md"
  local cupdate_skill="$REPO_DIR/skills/cupdate-arch/SKILL.md"

  # R-009: cauto references effective intensity computation
  file_contains_i "$skill_file" "effective.*intensity\|intensity.*computation\|max.*project.*feature" \
    "R-009: cauto references effective intensity computation"

  # R-009: cauto documents cupdate-arch gate at standard intensity
  file_contains_i "$skill_file" "cupdate-arch.*skip.*standard\|standard.*skip.*cupdate-arch\|cupdate-arch.*high.*intensity" \
    "R-009: cauto skips cupdate-arch at standard intensity"

  # R-009: cupdate-arch has its own intensity gate independent of cauto
  file_contains_i "$cupdate_skill" "intensity.*gate\|intensity.*threshold\|requires.*high" \
    "R-009: cupdate-arch has independent intensity gate"
}

# ============================================
# R-010 [integration]: Workflow state machine transitions
# ============================================

test_r010_workflow_transitions() {
  echo ""
  echo "=== R-010: Workflow state machine transitions ==="

  local skill_file="$REPO_DIR/skills/cauto/SKILL.md"

  # R-010: cauto uses workflow-advance.sh for transitions (not direct state writes)
  file_contains_i "$skill_file" "workflow-advance\|workflow-advance.sh" \
    "R-010: cauto uses workflow-advance.sh for transitions"

  # R-010: uses actual phase names
  file_contains "$skill_file" "tdd-tests" \
    "R-010: cauto uses tdd-tests phase name"

  file_contains "$skill_file" "tdd-impl" \
    "R-010: cauto uses tdd-impl phase name"

  file_contains "$skill_file" "tdd-qa" \
    "R-010: cauto uses tdd-qa phase name"

  # R-010: cauto must NOT write to state file directly
  file_not_contains "$skill_file" "jq.*workflow-state\|Write.*workflow-state\|echo.*workflow-state" \
    "R-010: cauto does not write state file directly"

  # R-010: verified phase
  file_contains "$skill_file" "verified" \
    "R-010: cauto uses verified phase name"

  # R-010: done phase
  file_contains "$skill_file" "done" \
    "R-010: cauto uses done phase name"

  # R-010: final phase after successful run is documented
  file_contains "$skill_file" "documented" \
    "R-010: cauto documents final 'documented' phase"

  # R-010: phase ordering — tdd-tests before tdd-impl before tdd-qa before done before verified before documented
  local skill_content
  skill_content="$(cat "$skill_file" 2>/dev/null)"
  local pos_tdd_tests pos_tdd_impl pos_tdd_qa pos_done pos_verified pos_documented
  pos_tdd_tests="$(echo "$skill_content" | grep -n "tdd-tests" | head -1 | cut -d: -f1)"
  pos_tdd_impl="$(echo "$skill_content" | grep -n "tdd-impl" | head -1 | cut -d: -f1)"
  pos_tdd_qa="$(echo "$skill_content" | grep -n "tdd-qa" | head -1 | cut -d: -f1)"
  pos_done="$(echo "$skill_content" | grep -nw 'done' | head -1 | cut -d: -f1)"
  pos_verified="$(echo "$skill_content" | grep -n "verified" | head -1 | cut -d: -f1)"
  pos_documented="$(echo "$skill_content" | grep -n "documented" | head -1 | cut -d: -f1)"

  local order_ok="yes"
  if [ -z "$pos_tdd_tests" ] || [ -z "$pos_tdd_impl" ] || [ -z "$pos_tdd_qa" ] || \
     [ -z "$pos_done" ] || [ -z "$pos_verified" ] || [ -z "$pos_documented" ]; then
    order_ok="no"
  elif [ "$pos_tdd_tests" -ge "$pos_tdd_impl" ] || [ "$pos_tdd_impl" -ge "$pos_tdd_qa" ] || \
       [ "$pos_tdd_qa" -ge "$pos_done" ] || [ "$pos_done" -ge "$pos_verified" ] || \
       [ "$pos_verified" -ge "$pos_documented" ]; then
    order_ok="no"
  fi
  assert_eq "R-010: phases appear in correct order (tdd-tests < tdd-impl < tdd-qa < done < verified < documented)" "yes" "$order_ok"
}

# ============================================
# R-011 [integration]: Audit trail orchestration entries
# ============================================

test_r011_audit_trail_entries() {
  echo ""
  echo "=== R-011: Audit trail orchestration entries ==="

  local skill_file="$REPO_DIR/skills/cauto/SKILL.md"

  # R-011: cauto references audit trail JSONL
  file_contains_i "$skill_file" "audit-trail.*jsonl\|audit.*trail.*jsonl\|audit-trail-" \
    "R-011: cauto references audit trail JSONL"

  # R-011: all 7 orchestration event types
  file_contains "$skill_file" "skill_started" \
    "R-011: audit trail type skill_started"

  file_contains "$skill_file" "skill_completed" \
    "R-011: audit trail type skill_completed"

  file_contains "$skill_file" "preference_applied" \
    "R-011: audit trail type preference_applied"

  file_contains "$skill_file" "escalation_triggered" \
    "R-011: audit trail type escalation_triggered"

  file_contains "$skill_file" "simplify_reverted" \
    "R-011: audit trail type simplify_reverted"

  file_contains "$skill_file" "pipeline_completed" \
    "R-011: audit trail type pipeline_completed"

  file_contains "$skill_file" "pipeline_failed" \
    "R-011: audit trail type pipeline_failed"

  # R-011: required fields
  file_contains_i "$skill_file" "timestamp.*ISO\|ISO.*timestamp\|ISO 8601" \
    "R-011: audit trail entries include ISO timestamp"

  file_contains "$skill_file" "elapsed_ms" \
    "R-011: audit trail entries include elapsed_ms"
}

# ============================================
# R-012 [integration]: /simplify outside trust model
# ============================================

test_r012_simplify_trust_model() {
  echo ""
  echo "=== R-012: /simplify outside trust model ==="

  local skill_file="$REPO_DIR/skills/cauto/SKILL.md"

  # R-012: cauto documents simplify as outside Correctless trust model
  file_contains_i "$skill_file" "simplify.*outside.*trust\|trust.*model.*simplify\|untrusted.*simplify" \
    "R-012: cauto documents simplify as outside trust model"

  # R-012: simplify has no SKILL.md
  file_contains_i "$skill_file" "no.*SKILL.md\|no.*allowed-tools\|no.*context.*fork\|built-in" \
    "R-012: cauto notes simplify has no SKILL.md/allowed-tools/context:fork"

  # R-012: simplify runs after ctdd (phase done), before cverify
  file_contains_i "$skill_file" "simplify.*after.*ctdd\|simplify.*done.*phase\|done.*simplify.*cverify" \
    "R-012: simplify runs after ctdd (done phase) before cverify"

  # R-012: simplify does not have its own workflow-advance.sh transition
  file_contains_i "$skill_file" "no.*transition.*simplify\|simplify.*no.*workflow\|no.*phase.*simplify" \
    "R-012: simplify has no workflow-advance.sh transition"
}

# ============================================
# R-013 [unit]: /csetup scaffolds preferences.md
# ============================================

test_r013_setup_scaffolds_preferences() {
  echo ""
  echo "=== R-013: /csetup scaffolds preferences.md ==="

  local setup_script="$REPO_DIR/setup"

  # R-013: setup script references preferences.md
  file_contains "$setup_script" "preferences.md" \
    "R-013: setup script references preferences.md"

  # R-013: setup creates preferences.md idempotently (create_if_missing pattern)
  file_contains_i "$setup_script" "create_if_missing.*preferences\|preferences.*create_if_missing" \
    "R-013: setup uses create_if_missing for preferences.md"

  # R-013: Integration test — run setup, verify preferences.md created
  local test_dir="$REPO_DIR/tests/tmp/semi-auto-r013-$$"
  rm -rf "$test_dir"
  mkdir -p "$test_dir"
  cd "$test_dir" || return

  # Initialize a git repo (setup requires it)
  git init -q
  git branch -M main
  echo "init" > README.md
  git add -A && git commit -q -m "init"

  # Install correctless from source
  mkdir -p .claude/skills/workflow
  cp -r "$REPO_DIR/hooks" .claude/skills/workflow/
  cp -r "$REPO_DIR/templates" .claude/skills/workflow/
  cp -r "$REPO_DIR/scripts" .claude/skills/workflow/
  cp -r "$REPO_DIR/skills" .claude/skills/workflow/
  cp "$REPO_DIR/setup" .claude/skills/workflow/

  # Run setup
  bash .claude/skills/workflow/setup > /dev/null 2>&1 || true

  # Check preferences.md was created
  assert_file_exists "R-013: setup creates preferences.md" \
    "$test_dir/.correctless/preferences.md"

  # R-013: Verify scaffolded file contains the 5 preference category headers from R-004
  local prefs_file="$test_dir/.correctless/preferences.md"
  if [ -f "$prefs_file" ]; then
    file_contains_i "$prefs_file" "qa.*finding.*triage\|qa.*triage\|finding.*triage\|severity.*auto.fix" \
      "R-013: scaffolded preferences.md has QA finding triage category"

    file_contains_i "$prefs_file" "documentation.*scope\|doc.*scope\|include.*exclude.*doc" \
      "R-013: scaffolded preferences.md has documentation scope category"

    file_contains_i "$prefs_file" "commit.*granularity\|commit.*structure\|how.*structure.*commit" \
      "R-013: scaffolded preferences.md has commit granularity category"

    file_contains_i "$prefs_file" "escalation.*sensitivity\|escalation.*threshold\|architectural.*decision.*human" \
      "R-013: scaffolded preferences.md has escalation sensitivity category"

    file_contains_i "$prefs_file" "pr.*creation\|pr_creation\|pull.*request.*creation" \
      "R-013: scaffolded preferences.md has PR creation preference category"
  else
    echo "  FAIL: R-013: cannot verify template content — preferences.md not created"
    FAIL=$((FAIL + 5))
  fi

  # R-013: Idempotency — write a marker, run setup again, verify marker preserved
  if [ -f "$test_dir/.correctless/preferences.md" ]; then
    echo "# USER_MARKER_DO_NOT_OVERWRITE" >> "$test_dir/.correctless/preferences.md"
    bash .claude/skills/workflow/setup > /dev/null 2>&1 || true
    local has_marker="no"
    grep -q "USER_MARKER_DO_NOT_OVERWRITE" "$test_dir/.correctless/preferences.md" 2>/dev/null && has_marker="yes"
    assert_eq "R-013: setup does not overwrite existing preferences.md" "yes" "$has_marker"
  else
    echo "  FAIL: R-013: cannot test idempotency — preferences.md not created"
    FAIL=$((FAIL + 1))
  fi

  cd "$REPO_DIR" || return
  rm -rf "$test_dir"
}

# ============================================
# R-014 [advisory]: Progress updates between skills
# ============================================

test_r014_progress_updates() {
  echo ""
  echo "=== R-014: Progress updates (advisory) ==="

  local skill_file="$REPO_DIR/skills/cauto/SKILL.md"

  # R-014: tagged [advisory] not [unit] in the spec — verify cauto mentions progress
  file_contains_i "$skill_file" "progress\|status.*update\|emit.*progress" \
    "R-014: cauto mentions progress updates"

  # R-014: progress is via audit trail entries (R-011 elapsed_ms)
  file_contains_i "$skill_file" "audit.*trail.*elapsed\|elapsed_ms.*progress\|progress.*audit" \
    "R-014: progress observable via audit trail (advisory)"
}

# ============================================
# R-015 [integration]: Commit-before-simplify, revert on failure
# ============================================

test_r015_commit_and_revert() {
  echo ""
  echo "=== R-015: Commit-before-simplify and revert ==="

  local skill_file="$REPO_DIR/skills/cauto/SKILL.md"

  # R-015: commit before simplify
  file_contains_i "$skill_file" "commit.*before.*simplify\|commit.*TDD.*complete\|revert.*point" \
    "R-015: cauto commits before simplify (revert point)"

  # R-015: git reset --hard HEAD for revert
  file_contains "$skill_file" "git reset --hard" \
    "R-015: cauto uses git reset --hard HEAD for revert"

  # R-015: check diff for .correctless/ modifications -> revert
  file_contains_i "$skill_file" "\.correctless.*revert\|revert.*\.correctless\|diff.*\.correctless.*reject\|\.correctless.*path.*reject" \
    "R-015: cauto rejects .correctless/ modifications from simplify"

  # R-015: re-run tests after simplify, revert if fail
  file_contains_i "$skill_file" "test.*fail.*revert\|revert.*test.*fail\|re-run.*test.*simplif" \
    "R-015: cauto re-runs tests after simplify and reverts on failure"

  # R-015: revert logged as simplify_reverted in audit trail (R-011)
  file_contains "$skill_file" "simplify_reverted" \
    "R-015: revert decisions logged as simplify_reverted"

  # R-015: revert does NOT escalate
  file_contains_i "$skill_file" "not.*escalat.*revert\|revert.*not.*escalat\|without.*escalat.*simplif\|continue.*without.*simplif" \
    "R-015: simplify revert does not escalate"
}

# ============================================
# R-016 [integration]: Pipeline resumption from escalation file
# ============================================

test_r016_pipeline_resumption() {
  echo ""
  echo "=== R-016: Pipeline resumption ==="

  local skill_file="$REPO_DIR/skills/cauto/SKILL.md"

  # R-016: cauto checks for existing escalation file
  file_contains_i "$skill_file" "check.*escalation.*file\|existing.*escalation\|escalation.*exist\|escalation.*present" \
    "R-016: cauto checks for existing escalation file on startup"

  # R-016: parses YAML frontmatter from escalation file
  file_contains_i "$skill_file" "parse.*YAML\|YAML.*frontmatter.*escalation\|frontmatter.*parse" \
    "R-016: cauto parses YAML frontmatter from escalation file"

  # R-016: phase consistency check
  file_contains_i "$skill_file" "failed_at_phase.*match\|phase.*consist\|phase.*current.*match" \
    "R-016: cauto checks phase consistency for resumption"

  # R-016: artifact verification (tests pass, verification report)
  file_contains_i "$skill_file" "artifact.*verif\|tests.*pass.*artifact\|completed.*skill.*artifact" \
    "R-016: cauto verifies completed skill artifacts still valid"

  # R-016: resume from failed skill if checks pass
  file_contains_i "$skill_file" "resume.*failed.*skill\|resume.*from\|skip.*completed" \
    "R-016: cauto resumes from failed skill"

  # R-016: delete stale escalation and start fresh if checks fail
  file_contains_i "$skill_file" "stale.*escalation.*delete\|delete.*stale\|start.*fresh\|clean.*escalation" \
    "R-016: cauto deletes stale escalation and starts fresh"
}

# ============================================
# R-017 [integration]: Spec-update escalation
# ============================================

test_r017_spec_update_escalation() {
  echo ""
  echo "=== R-017: Spec-update escalation ==="

  local skill_file="$REPO_DIR/skills/cauto/SKILL.md"

  # R-017: detect spec-update trigger during TDD
  file_contains_i "$skill_file" "spec-update\|spec.*update.*trigger\|spec.*wrong.*during.*TDD" \
    "R-017: cauto detects spec-update trigger during TDD"

  # R-017: escalation identifies the problematic rule
  file_contains_i "$skill_file" "which.*spec.*rule\|unsatisfiable.*rule\|problematic.*rule\|rule.*unsatisf" \
    "R-017: escalation identifies problematic spec rule"

  # R-017: resets phase to spec
  file_contains_i "$skill_file" "reset.*phase.*spec\|phase.*spec.*reset\|phase.*back.*spec" \
    "R-017: spec-update resets phase to spec"

  # R-017: pipeline halts on spec-update
  file_contains_i "$skill_file" "halt.*spec.*update\|stop.*spec.*update\|pipeline.*halt\|escalat.*spec.*update" \
    "R-017: pipeline halts on spec-update"
}

# ============================================
# R-018 [integration]: Upfront gh availability check
# ============================================

test_r018_gh_availability_check() {
  echo ""
  echo "=== R-018: Upfront gh availability check ==="

  local skill_file="$REPO_DIR/skills/cauto/SKILL.md"

  # R-018: check gh availability before pipeline starts
  file_contains_i "$skill_file" "command.*gh\|gh.*install\|gh.*not.*found\|check.*gh.*avail\|verify.*gh" \
    "R-018: cauto checks gh availability before pipeline"

  # R-018: fail fast with actionable message
  file_contains_i "$skill_file" "pr_creation.*skip\|install.*gh\|gh CLI.*not.*install\|fail.*fast.*gh" \
    "R-018: cauto fails fast with actionable message about gh"

  # R-018: check runs before any skill invocation
  file_contains_i "$skill_file" "before.*skill\|before.*pipeline\|startup.*check\|upfront.*check" \
    "R-018: gh check runs before any skill invocation"
}

# ============================================
# R-019 [unit]: preferences.md in sensitive-file-guard
# ============================================

test_r019_preferences_in_sensitive_guard() {
  echo ""
  echo "=== R-019: preferences.md in sensitive-file-guard ==="

  local hook="$REPO_DIR/hooks/sensitive-file-guard.sh"

  # R-019: sensitive-file-guard must list .correctless/preferences.md in protected patterns
  file_contains_i "$hook" ".correctless/preferences.md" \
    "R-019: sensitive-file-guard lists .correctless/preferences.md in protected patterns"

  # R-019: Integration test — hook blocks Write to .correctless/preferences.md
  local test_dir="$REPO_DIR/tests/tmp/semi-auto-r019-$$"
  rm -rf "$test_dir"
  mkdir -p "$test_dir/.correctless/config"

  # Create a minimal config
  echo '{}' > "$test_dir/.correctless/config/workflow-config.json"

  cd "$test_dir" || return

  local result
  result="$(run_sfg_hook '{"tool_name":"Write","tool_input":{"file_path":".correctless/preferences.md","content":"test"}}')"
  assert_eq "R-019: Write to .correctless/preferences.md is blocked" "2" "$result"

  # R-019: hook blocks Edit to .correctless/preferences.md
  result="$(run_sfg_hook '{"tool_name":"Edit","tool_input":{"file_path":".correctless/preferences.md","old_string":"a","new_string":"b"}}')"
  assert_eq "R-019: Edit to .correctless/preferences.md is blocked" "2" "$result"

  # R-019: hook blocks Bash writes to .correctless/preferences.md
  result="$(run_sfg_hook '{"tool_name":"Bash","tool_input":{"command":"cat data > .correctless/preferences.md"}}')"
  assert_eq "R-019: Bash redirect to .correctless/preferences.md is blocked" "2" "$result"

  # R-019: negative test — docs/preferences.md should NOT be blocked (path-qualified pattern)
  result="$(run_sfg_hook '{"tool_name":"Write","tool_input":{"file_path":"docs/preferences.md","content":"test"}}')"
  assert_eq "R-019: Write to docs/preferences.md is NOT blocked" "0" "$result"

  cd "$REPO_DIR" || return
  rm -rf "$test_dir"
}

# ============================================
# PRE-001: is_full_mode() must consult feature_intensity
# ============================================

test_pre001_is_full_mode_feature_intensity() {
  echo ""
  echo "=== PRE-001: is_full_mode() consults feature_intensity ==="

  local hook="$REPO_DIR/hooks/workflow-advance.sh"

  # PRE-001: is_full_mode must reference CONFIG_FILE (existing behavior)
  file_contains "$hook" "CONFIG_FILE" \
    "PRE-001: is_full_mode references CONFIG_FILE"

  # PRE-001: is_full_mode must also read the state file for feature_intensity
  # Currently it only reads from CONFIG_FILE — it must also consult STATE_FILE
  # Extract the is_full_mode function body and check for state file reference
  local func_body
  func_body="$(sed -n '/^is_full_mode()/,/^}/p' "$hook" 2>/dev/null)"
  assert_contains "PRE-001: is_full_mode reads from state file" "STATE_FILE" "$func_body"

  # PRE-001: is_full_mode must reference feature_intensity field
  assert_contains "PRE-001: is_full_mode references feature_intensity" "feature_intensity" "$func_body"

  # PRE-001: is_full_mode must compute effective intensity as max(project, feature)
  file_contains_i "$hook" "max.*intensity\|effective.*intensity\|feature_intensity" \
    "PRE-001: is_full_mode computes effective intensity"
}

# ============================================
# PRE-002: multi-turn skills must NOT have context: fork (PMB-006)
# ============================================

test_pre002_no_fork_on_multi_turn_skills() {
  echo ""
  echo "=== PRE-002: multi-turn skills must not have context: fork ==="

  # Multi-turn skills need user interaction mid-execution. context: fork runs
  # them as sub-agents that complete after first output, breaking the interaction.
  # See PMB-006 and AP-027.
  local multi_turn_skills="carchitect caudit cauto cdebug cdocs cmaintain cmodel crefactor creview creview-spec ctdd cupdate-arch"

  for skill in $multi_turn_skills; do
    local skill_file="$REPO_DIR/skills/$skill/SKILL.md"
    if [ ! -f "$skill_file" ]; then
      fail "PRE-002: $skill SKILL.md exists" "File not found: $skill_file"
      continue
    fi
    local fm
    fm="$(sed -n '/^---$/,/^---$/p' "$skill_file" 2>/dev/null)"
    if echo "$fm" | grep -q 'context: fork'; then
      fail "PRE-002: $skill must not have context: fork" \
        "Multi-turn skill $skill has context: fork — this breaks direct user invocation (PMB-006)"
    else
      pass "PRE-002: $skill does not have context: fork"
    fi
  done
}

# ============================================
# PRE-003: ARCHITECTURE.md has new entries
# ============================================

test_pre003_architecture_entries() {
  echo ""
  echo "=== PRE-003: ARCHITECTURE.md has new entries ==="

  local arch="$REPO_DIR/.correctless/ARCHITECTURE.md"

  # PRE-003: TB-004 — LLM orchestrator autonomy boundary
  file_contains "$arch" "TB-004" \
    "PRE-003: ARCHITECTURE.md has TB-004 (LLM orchestrator autonomy boundary)"

  # PRE-003: TB-001b — Custom PR command exception
  file_contains "$arch" "TB-001b" \
    "PRE-003: ARCHITECTURE.md has TB-001b (custom PR command exception)"

  # PRE-003: ABS-007 — Escalation file contract
  file_contains "$arch" "ABS-007" \
    "PRE-003: ARCHITECTURE.md has ABS-007 (escalation file contract)"

  # PRE-003: ABS-008 — preferences.md contract
  file_contains "$arch" "ABS-008" \
    "PRE-003: ARCHITECTURE.md has ABS-008 (preferences.md contract)"

  # PRE-003: ENV-003 — gh CLI optional dependency (check for the semi-auto version)
  # Note: there is already an ENV-003 about filesystem timestamps — the spec may
  # need a different ID or the existing one may need amendment.
  # We check for the gh CLI content specifically.
  file_contains_i "$arch" "gh.*CLI\|gh.*optional.*dependency\|gh.*pr_creation" \
    "PRE-003: ARCHITECTURE.md has ENV entry for gh CLI dependency"
}

# ============================================
# PRE-004: PAT-007 and PAT-008 in ARCHITECTURE.md
# ============================================

test_pre004_new_patterns() {
  echo ""
  echo "=== PRE-004: PAT-007 and PAT-008 in ARCHITECTURE.md ==="

  local arch="$REPO_DIR/.correctless/ARCHITECTURE.md"

  # PRE-004: PAT-007 — Conditional update path testing
  file_contains "$arch" "PAT-007" \
    "PRE-004: ARCHITECTURE.md has PAT-007 (conditional update path testing)"

  # PRE-004: PAT-008 — Idempotent migration testing
  file_contains "$arch" "PAT-008" \
    "PRE-004: ARCHITECTURE.md has PAT-008 (idempotent migration testing)"
}

# ============================================
# PRE-005: Shared constraints include preference reading
# ============================================

test_pre005_shared_constraints_preferences() {
  echo ""
  echo "=== PRE-005: Shared constraints include preference reading ==="

  local constraints="$REPO_DIR/skills/_shared/constraints.md"

  # PRE-005: constraints.md must include preference reading instruction
  file_contains_i "$constraints" "preferences.md" \
    "PRE-005: constraints.md references preferences.md"

  file_contains_i "$constraints" "preferences.*exist.*read\|read.*preferences\|project.*preferences\|\.correctless/preferences" \
    "PRE-005: constraints.md instructs reading preferences.md when it exists"
}

# ============================================
# PRE-006: preferences.md in sensitive-file-guard built-in list
# ============================================

test_pre006_preferences_in_guard_defaults() {
  echo ""
  echo "=== PRE-006: preferences.md in sensitive-file-guard DEFAULTS ==="

  local hook="$REPO_DIR/hooks/sensitive-file-guard.sh"

  # PRE-006: .correctless/preferences.md must be in the DEFAULTS section (hardcoded built-in list)
  # Extract the DEFAULTS block and check
  local defaults_block
  defaults_block="$(sed -n '/^DEFAULTS=/,/^"/p' "$hook" 2>/dev/null)"
  assert_contains "PRE-006: .correctless/preferences.md in DEFAULTS built-in list" ".correctless/preferences.md" "$defaults_block"
}

# ============================================
# PRE-007: sync.sh includes cauto skill
# ============================================

test_pre007_sync_includes_cauto() {
  echo ""
  echo "=== PRE-007: sync.sh includes cauto skill ==="

  local sync="$REPO_DIR/sync.sh"

  # PRE-007: sync.sh skill list must include cauto
  file_contains "$sync" "cauto" \
    "PRE-007: sync.sh skill list includes cauto"
}

# ============================================
# QA-001 class fix: skill count matches AGENT_CONTEXT.md
# ============================================

test_qa001_skill_count_matches_docs() {
  echo ""
  echo "=== QA-001: Skill count matches AGENT_CONTEXT.md ==="

  local actual_count
  actual_count=0
  for d in "$REPO_DIR/skills"/*/; do
    [ -d "$d" ] || continue
    case "$(basename "$d")" in _shared) continue ;; esac
    actual_count=$((actual_count + 1))
  done

  local doc_count
  doc_count="$(grep -Eo '[0-9]+ skill' "$REPO_DIR/.correctless/AGENT_CONTEXT.md" | head -1 | grep -Eo '[0-9]+')"

  assert_eq "QA-001: actual skill count ($actual_count) matches AGENT_CONTEXT.md ($doc_count)" "$actual_count" "$doc_count"
}

# ============================================
# QA-002: is_full_mode() behavioral tests
# ============================================

test_qa002_is_full_mode_behavioral() {
  echo ""
  echo "=== QA-002: is_full_mode() behavioral tests ==="

  local test_dir="/tmp/correctless-is-full-mode-test-$$"

  # Helper: set up a minimal test project and return is_full_mode exit code
  # Args: $1=project_intensity (empty for none), $2=feature_intensity (empty for none), $3=create_state_file (yes/no)
  _run_is_full_mode() {
    local project_intensity="$1" feature_intensity="$2" create_state="${3:-yes}"

    rm -rf "$test_dir"
    mkdir -p "$test_dir/.correctless/config" "$test_dir/.correctless/artifacts"

    # Minimal config file
    if [ -n "$project_intensity" ]; then
      echo "{\"workflow\":{\"intensity\":\"$project_intensity\"}}" > "$test_dir/.correctless/config/workflow-config.json"
    else
      echo '{}' > "$test_dir/.correctless/config/workflow-config.json"
    fi

    # Create a mock state file with known branch slug
    if [ "$create_state" = "yes" ] && [ -n "$feature_intensity" ]; then
      echo "{\"phase\":\"review\",\"feature_intensity\":\"$feature_intensity\"}" > "$test_dir/.correctless/artifacts/workflow-state-test-branch.json"
    fi

    # Write a self-contained test script that defines the needed functions and calls is_full_mode.
    # This avoids sourcing workflow-advance.sh directly (which has set -euo pipefail and git calls).
    cat > "$test_dir/test-is-full-mode.sh" << SCRIPTEOF
#!/usr/bin/env bash
CONFIG_FILE="$test_dir/.correctless/config/workflow-config.json"
ARTIFACTS_DIR="$test_dir/.correctless/artifacts"

state_file() { echo "$test_dir/.correctless/artifacts/workflow-state-test-branch.json"; }
read_config_field() { jq -r "\$1 // empty" "\$CONFIG_FILE" 2>/dev/null; }

$(sed -n '/^is_full_mode()/,/^}/p' "$REPO_DIR/hooks/workflow-advance.sh")

is_full_mode
SCRIPTEOF
    chmod +x "$test_dir/test-is-full-mode.sh"

    local exit_code
    bash "$test_dir/test-is-full-mode.sh" 2>/dev/null && exit_code=0 || exit_code=$?
    echo "$exit_code"
  }

  # Test 1: project=standard + feature=high → is_full_mode returns 0 (true)
  local result
  result="$(_run_is_full_mode "standard" "high" "yes")"
  assert_eq "QA-002: project=standard + feature=high → is_full_mode returns 0" "0" "$result"

  # Test 2: project=standard + feature=standard → is_full_mode returns 1 (false)
  result="$(_run_is_full_mode "standard" "standard" "yes")"
  assert_eq "QA-002: project=standard + feature=standard → is_full_mode returns 1" "1" "$result"

  # Test 3: project=high + feature=standard → is_full_mode returns 0 (true)
  result="$(_run_is_full_mode "high" "standard" "yes")"
  assert_eq "QA-002: project=high + feature=standard → is_full_mode returns 0" "0" "$result"

  # Test 4: project=standard + no state file → is_full_mode returns 1 (false)
  result="$(_run_is_full_mode "standard" "" "no")"
  assert_eq "QA-002: project=standard + no state file → is_full_mode returns 1" "1" "$result"

  # Test 5: project=empty + feature=critical → is_full_mode returns 0 (true)
  result="$(_run_is_full_mode "" "critical" "yes")"
  assert_eq "QA-002: project=empty + feature=critical → is_full_mode returns 0" "0" "$result"

  rm -rf "$test_dir"
}

# ============================================
# UX-R-001 [unit]: Flexible phase entry — accepts any active phase
# Tests spec rule R-001 from auto-ux-improvements.md
# ============================================

test_ux_r001_flexible_phase_entry() {
  echo ""
  echo "=== UX-R-001: Flexible phase entry ==="

  local skill_file="$REPO_DIR/skills/cauto/SKILL.md"

  # UX-R-001: SKILL.md must contain the phase-to-step mapping
  file_contains_i "$skill_file" "phase.*step.*mapping\|phase-to-step\|remaining.*pipeline.*steps" \
    "UX-R-001: SKILL.md contains phase-to-step mapping"

  # UX-R-001: review/review-spec maps to full pipeline (ctdd through PR)
  file_contains_i "$skill_file" "review.*full.*pipeline\|review.*ctdd.*through\|review-spec.*full" \
    "UX-R-001: review/review-spec maps to full pipeline"

  # UX-R-001: tdd phases resume from ctdd
  file_contains_i "$skill_file" "tdd-tests.*resume.*ctdd\|tdd-impl.*resume.*ctdd\|tdd-qa.*resume.*ctdd" \
    "UX-R-001: tdd phases resume from ctdd"

  # UX-R-001: done maps to simplify through PR
  file_contains_i "$skill_file" "done.*simplify" \
    "UX-R-001: done phase maps to simplify through PR"

  # UX-R-001: verified maps to cupdate-arch (if high+) through PR
  file_contains_i "$skill_file" "verified.*cupdate-arch\|verified.*high" \
    "UX-R-001: verified phase maps to cupdate-arch (if high+) through PR"

  # UX-R-001: documented maps to consolidation/PR only
  file_contains_i "$skill_file" "documented.*PR.*only\|documented.*Consolidation" \
    "UX-R-001: documented phase maps to PR only"

  # UX-R-001: spec and model phases are rejected
  file_contains_i "$skill_file" "spec.*reject\|model.*reject\|spec.*before.*pipeline" \
    "UX-R-001: spec and model phases are rejected"

  # UX-R-001: spec rejection message mentions /creview
  file_contains_i "$skill_file" "creview.*first\|Run.*creview" \
    "UX-R-001: spec rejection message mentions /creview"

  # UX-R-001: mid-TDD resume delegated to /ctdd
  file_contains_i "$skill_file" "delegate.*ctdd\|trusts.*ctdd\|ctdd.*handle.*internal" \
    "UX-R-001: mid-TDD resume delegated to /ctdd"
}

# ============================================
# UX-R-002 [unit]: Artifact validation for skipped phases
# Tests spec rule R-002 from auto-ux-improvements.md
# ============================================

test_ux_r002_artifact_validation() {
  echo ""
  echo "=== UX-R-002: Artifact validation for skipped phases ==="

  local skill_file="$REPO_DIR/skills/cauto/SKILL.md"

  # UX-R-002: validation only for phases being skipped, not current phase
  file_contains_i "$skill_file" "validation.*skip\|already.*completed.*validate\|behind.*current.*phase" \
    "UX-R-002: validation applies to skipped phases only"

  # UX-R-002: ctdd validation = test suite passes
  file_contains_i "$skill_file" "ctdd.*complete.*test.*suite\|test.*suite.*pass" \
    "UX-R-002: ctdd validation checks test suite passes"

  # UX-R-002: test timeout configurable via commands.test_timeout
  file_contains_i "$skill_file" "test_timeout\|timeout.*configurable\|300.*second" \
    "UX-R-002: test timeout configurable via commands.test_timeout"

  # UX-R-002: cverify validation = verification report exists
  file_contains_i "$skill_file" "verification.*report.*exist\|{task-slug}-verification" \
    "UX-R-002: cverify validation checks verification report exists"

  # UX-R-002: simplify, cupdate-arch, cdocs need no validation
  file_contains_i "$skill_file" "no.*validation.*needed\|optional.*step\|advisory" \
    "UX-R-002: optional steps need no validation"

  # UX-R-002: validation failure triggers re-run of that phase
  file_contains_i "$skill_file" "validation.*fail.*re-run\|re-run.*phase" \
    "UX-R-002: validation failure triggers phase re-run"

  # UX-R-002: 2 consecutive failures skip validation
  file_contains_i "$skill_file" "2.*consecutive.*fail.*skip\|2.*consecutive.*proceed" \
    "UX-R-002: 2 consecutive validation failures skips validation"

  # UX-R-002: validation failure logged as artifact_validation_failed
  file_contains "$skill_file" "artifact_validation_failed" \
    "UX-R-002: validation failure logged as artifact_validation_failed"
}

# ============================================
# UX-R-003 [unit]: Scoped commit consolidation before PR (F-001)
# Tests spec rule R-003 from auto-ux-improvements.md
# ============================================

test_ux_r003_scoped_commit_consolidation() {
  echo ""
  echo "=== UX-R-003: Scoped commit consolidation ==="

  local skill_file="$REPO_DIR/skills/cauto/SKILL.md"

  # UX-R-003: consolidation step between cdocs and PR
  file_contains_i "$skill_file" "consolidation.*cdocs.*PR\|cdocs.*consolidation\|consolidation.*step" \
    "UX-R-003: consolidation step between cdocs and PR"

  # UX-R-003: uses git diff main...HEAD --name-only
  file_contains "$skill_file" "git diff main...HEAD --name-only" \
    "UX-R-003: uses git diff main...HEAD --name-only"

  # UX-R-003: explicit pipeline output paths listed
  file_contains_i "$skill_file" "explicit.*path.*list\|pipeline.*output.*path" \
    "UX-R-003: explicit pipeline output paths listed"

  # UX-R-003: specific paths in the explicit list
  file_contains "$skill_file" ".correctless/verification/{task-slug}-verification.md" \
    "UX-R-003: explicit list includes verification report"
  file_contains "$skill_file" ".correctless/ARCHITECTURE.md" \
    "UX-R-003: explicit list includes ARCHITECTURE.md"
  file_contains "$skill_file" ".correctless/AGENT_CONTEXT.md" \
    "UX-R-003: explicit list includes AGENT_CONTEXT.md"
  file_contains "$skill_file" "README.md" \
    "UX-R-003: explicit list includes README.md"
  file_contains "$skill_file" "CONTRIBUTING.md" \
    "UX-R-003: explicit list includes CONTRIBUTING.md"
  file_contains "$skill_file" "docs/workflow-history.md" \
    "UX-R-003: explicit list includes docs/workflow-history.md"
  file_contains_i "$skill_file" "docs/features/" \
    "UX-R-003: explicit list includes docs/features/"

  # UX-R-003: unknown untracked files never staged
  file_contains_i "$skill_file" "untracked.*never.*staged\|unknown.*untracked.*never" \
    "UX-R-003: unknown untracked files never staged"

  # UX-R-003: belt-and-suspenders unstage .correctless/artifacts/
  file_contains "$skill_file" "git reset HEAD .correctless/artifacts/" \
    "UX-R-003: belt-and-suspenders unstage .correctless/artifacts/"

  # UX-R-003: commit message convention
  file_contains "$skill_file" "Add pipeline artifacts for {task-slug}" \
    "UX-R-003: commit message is 'Add pipeline artifacts for {task-slug}'"

  # UX-R-003: push derives remote name from branch config
  file_contains_i "$skill_file" "git config.*branch.*remote\|derive.*remote" \
    "UX-R-003: push derives remote name from branch config"

  # UX-R-003: fresh branch uses --set-upstream
  file_contains_i "$skill_file" "set-upstream" \
    "UX-R-003: fresh branch uses --set-upstream"

  # UX-R-003: no remote configured aborts
  file_contains "$skill_file" "No git remote configured" \
    "UX-R-003: aborts if no git remote configured"

  # UX-R-003: protected branch guard
  file_contains_i "$skill_file" "main.*master.*develop.*release\|must not push.*main" \
    "UX-R-003: protected branch guard for main/master/develop/release"

  # UX-R-003: no-op when nothing to commit
  file_contains_i "$skill_file" "no.*uncommitted.*skip\|no-op" \
    "UX-R-003: no-op when no uncommitted changes"

  # UX-R-003: push failure preserves commit, skips PR
  file_contains_i "$skill_file" "push.*fail.*abort\|local.*commit.*preserved" \
    "UX-R-003: push failure preserves local commit, skips PR"
}

# ============================================
# UX-R-004 [unit]: Structured end-of-pipeline summary
# Tests spec rule R-004 from auto-ux-improvements.md
# ============================================

test_ux_r004_pipeline_summary() {
  echo ""
  echo "=== UX-R-004: Structured end-of-pipeline summary ==="

  local skill_file="$REPO_DIR/skills/cauto/SKILL.md"

  # UX-R-004: summary has three sections
  file_contains_i "$skill_file" "Findings.*Decisions" \
    "UX-R-004: summary has Findings & Decisions section"

  file_contains_i "$skill_file" "Phase.*Breakdown" \
    "UX-R-004: summary has Phase Breakdown section"

  file_contains "$skill_file" "Artifacts" \
    "UX-R-004: summary has Artifacts section"

  # UX-R-004: findings include dispositions
  file_contains_i "$skill_file" "disposition.*fixed.*deferred.*accepted\|finding.*disposition" \
    "UX-R-004: findings include dispositions (fixed/deferred/accepted)"

  # UX-R-004: deferred items shown with reason
  file_contains_i "$skill_file" "deferred.*reason\|deferred.*items.*reason" \
    "UX-R-004: deferred items shown with reason"

  # UX-R-004: Phase Breakdown columns: step name, duration, token count, result
  file_contains_i "$skill_file" "step.*name.*duration.*token.*result\|duration.*token.*count.*result" \
    "UX-R-004: Phase Breakdown table has step name, duration, token count, result"

  # UX-R-004: duration from skill_started/skill_completed elapsed_ms
  file_contains_i "$skill_file" "skill_completed.*elapsed_ms.*skill_started\|last.*skill_completed.*first.*skill_started" \
    "UX-R-004: duration from skill_started/skill_completed elapsed_ms"

  # UX-R-004: incomplete phases detected
  file_contains_i "$skill_file" "skill_started.*without.*skill_completed\|never.*completed.*incomplete" \
    "UX-R-004: incomplete phases detected"

  # UX-R-004: Artifacts section lists file paths
  file_contains_i "$skill_file" "file.*path.*spec.*verification\|spec.*verification.*report.*QA" \
    "UX-R-004: Artifacts section lists key file paths"

  # UX-R-004: truncation at >20 severity-bearing items
  file_contains_i "$skill_file" "more.*than.*20\|truncation.*20\|20.*items" \
    "UX-R-004: truncation at >20 severity-bearing items"

  # UX-R-004: HIGH/CRITICAL always shown inline
  file_contains_i "$skill_file" "HIGH.*CRITICAL.*always.*shown\|always.*shown.*inline" \
    "UX-R-004: HIGH/CRITICAL always shown inline"

  # UX-R-004: deferred items always shown inline
  file_contains_i "$skill_file" "deferred.*always.*shown\|deferred.*inline" \
    "UX-R-004: deferred items always shown inline"

  # UX-R-004: override activity always shown inline
  file_contains_i "$skill_file" "override.*activity.*shown\|override.*always" \
    "UX-R-004: override activity always shown inline"

  # UX-R-004: non-severity sources always shown inline
  file_contains_i "$skill_file" "non-severity.*inline\|non-severity.*always" \
    "UX-R-004: non-severity sources always shown inline"

  # UX-R-004: count-and-reference summary for truncated items
  file_contains_i "$skill_file" "count.*reference.*summary\|see.*qa-findings.*full" \
    "UX-R-004: count-and-reference summary for truncated items"

  # UX-R-004: orchestrator logs skill events for all steps including /simplify
  file_contains_i "$skill_file" "orchestrator.*log.*all.*step\|including.*simplify" \
    "UX-R-004: orchestrator logs skill events for all steps including /simplify"
}

# ============================================
# UX-R-005 [unit]: New audit trail event type artifact_validation_failed
# Tests spec rule R-005 from auto-ux-improvements.md
# ============================================

test_ux_r005_artifact_validation_event() {
  echo ""
  echo "=== UX-R-005: artifact_validation_failed event type ==="

  local skill_file="$REPO_DIR/skills/cauto/SKILL.md"

  # UX-R-005: artifact_validation_failed event type in audit trail section
  file_contains "$skill_file" "artifact_validation_failed" \
    "UX-R-005: SKILL.md contains artifact_validation_failed event type"

  # UX-R-005: event includes phase, expected_artifact, validation_error fields
  file_contains_i "$skill_file" "artifact_validation_failed.*phase\|phase.*expected_artifact.*validation_error" \
    "UX-R-005: artifact_validation_failed event includes phase field"

  file_contains "$skill_file" "expected_artifact" \
    "UX-R-005: artifact_validation_failed event includes expected_artifact field"

  file_contains "$skill_file" "validation_error" \
    "UX-R-005: artifact_validation_failed event includes validation_error field"

  # UX-R-005: event type count is now 8 (was 7)
  # The SKILL.md declares "one of the 8 event types" in the audit trail section
  file_contains "$skill_file" "one of the 8 event types" \
    "UX-R-005: audit trail declares 8 event types"
}

# ============================================
# UX-R-006 [unit]: Summary reads from multiple data sources
# Tests spec rule R-006 from auto-ux-improvements.md
# ============================================

test_ux_r006_summary_data_sources() {
  echo ""
  echo "=== UX-R-006: Summary data sources ==="

  local skill_file="$REPO_DIR/skills/cauto/SKILL.md"

  # UX-R-006: each data source file is referenced by name
  file_contains "$skill_file" "qa-findings-{task-slug}.json" \
    "UX-R-006(a): reads QA findings JSON"

  file_contains "$skill_file" "{task-slug}-verification.md" \
    "UX-R-006(b): reads verification report"

  file_contains "$skill_file" "review-decisions-{task-slug}.json" \
    "UX-R-006(c): reads review decisions JSON"

  file_contains "$skill_file" "override-log-{branch-slug}.json" \
    "UX-R-006(d): reads override log JSON"

  file_contains "$skill_file" "audit-trail-{branch-slug}.jsonl" \
    "UX-R-006(e): reads audit trail JSONL"

  # UX-R-006: missing source files are omitted, not errors
  file_contains_i "$skill_file" "source.*doesn.*exist.*omit\|not.*exist.*omit" \
    "UX-R-006: missing source files are omitted, not errors"

  # UX-R-006: documents task-slug vs branch-slug distinction
  file_contains_i "$skill_file" "task-slug.*branch-slug.*different\|different.*values" \
    "UX-R-006: documents task-slug vs branch-slug distinction"
}

# ============================================
# UX-R-007 [unit]: Phase Breakdown uses skill names
# Tests spec rule R-007 from auto-ux-improvements.md
# ============================================

test_ux_r007_phase_breakdown_skill_names() {
  echo ""
  echo "=== UX-R-007: Phase Breakdown uses skill names ==="

  local skill_file="$REPO_DIR/skills/cauto/SKILL.md"

  # UX-R-007: Phase Breakdown uses skill names as row identifiers
  file_contains_i "$skill_file" "skill.*name.*row\|row.*identifier.*skill\|skill.*name.*identifier" \
    "UX-R-007: Phase Breakdown uses skill names as row identifiers"

  # UX-R-007: explicitly states not using phase names for rows
  file_contains_i "$skill_file" "not.*workflow.*phase.*name\|not.*phase.*name" \
    "UX-R-007: explicitly states not using phase names for rows"

  # UX-R-007: duration from last skill_completed minus first skill_started
  file_contains_i "$skill_file" "last.*skill_completed.*first.*skill_started\|skill_completed.*elapsed_ms.*skill_started" \
    "UX-R-007: duration computed from audit trail entries"

  # UX-R-007: multiple attempts span covered
  file_contains_i "$skill_file" "multiple.*attempts.*span\|covers.*all.*attempts" \
    "UX-R-007: multiple attempts/retries span covered"

  # UX-R-007: token count from token-log JSONL
  file_contains "$skill_file" "token-log-{branch-slug}.jsonl" \
    "UX-R-007: token count from token-log JSONL"

  # UX-R-007: missing token log shows dash
  file_contains_i "$skill_file" "token.*log.*doesn.*exist.*—\|no.*entries.*—" \
    "UX-R-007: missing token log shows dash"
}

# ============================================
# Runner
# ============================================

echo "============================================="
echo "Semi-Auto Mode Test Suite"
echo "============================================="

# Rules
test_r001_cauto_skill_order_and_sub_agents
test_r002_cauto_phase_gate
test_r003_cauto_reads_preferences
test_r004_preferences_template_categories
test_r005_escalation_file_format
test_r006_architectural_escalation
test_r007_never_auto_invoke_preserved
test_r008_pr_creation_options
test_r009_intensity_pipeline
test_r010_workflow_transitions
test_r011_audit_trail_entries
test_r012_simplify_trust_model
test_r013_setup_scaffolds_preferences
test_r014_progress_updates
test_r015_commit_and_revert
test_r016_pipeline_resumption
test_r017_spec_update_escalation
test_r018_gh_availability_check
test_r019_preferences_in_sensitive_guard

# Prerequisites
test_pre001_is_full_mode_feature_intensity
test_pre002_no_fork_on_multi_turn_skills
test_pre003_architecture_entries
test_pre004_new_patterns
test_pre005_shared_constraints_preferences
test_pre006_preferences_in_guard_defaults
test_pre007_sync_includes_cauto

# QA class fixes
test_qa001_skill_count_matches_docs
test_qa002_is_full_mode_behavioral

# UX improvements (auto-ux-improvements spec)
test_ux_r001_flexible_phase_entry
test_ux_r002_artifact_validation
test_ux_r003_scoped_commit_consolidation
test_ux_r004_pipeline_summary
test_ux_r005_artifact_validation_event
test_ux_r006_summary_data_sources
test_ux_r007_phase_breakdown_skill_names

echo ""
echo "============================================="
echo "Results: $PASS passed, $FAIL failed"
echo ""

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
