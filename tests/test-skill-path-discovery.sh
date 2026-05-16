#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091,SC2086
# Correctless — Skill Path Discovery Tests
# Enforces the skill-path-discovery spec rules R-001..R-006.
# Verifies that skills referencing workflow artifacts include explicit
# path discovery instructions rather than vague "Read the spec" prose.
#
# Run from repo root: bash tests/test-skill-path-discovery.sh

source "$(dirname "${BASH_SOURCE[0]}")/test-helpers.sh"

echo "Correctless Skill Path Discovery Tests"
echo "======================================="

# skill_body() is provided by test-helpers.sh
# Uses herestrings (<<<) instead of pipes to avoid SIGPIPE with pipefail
# when grep -q exits early on large skill files.

# ============================================================================
# R-001 [unit]: /creview-spec step 2 has workflow-advance.sh status call
# ============================================================================

section "R-001: /creview-spec path discovery"

CREVIEW_SPEC_SKILL="$REPO_DIR/skills/creview-spec/SKILL.md"

if [ ! -f "$CREVIEW_SPEC_SKILL" ]; then
  fail "R-001(a)" "skills/creview-spec/SKILL.md not found"
else
  body="$(skill_body "$CREVIEW_SPEC_SKILL")"

  # Tests R-001 [unit]: step 2 must reference workflow-advance.sh status
  if grep -qF "workflow-advance.sh status" <<< "$body"; then
    pass "R-001(a)" "/creview-spec mentions workflow-advance.sh status"
  else
    fail "R-001(a)" "/creview-spec missing workflow-advance.sh status call"
  fi

  # Tests R-001 [unit]: step 2 must reference Spec: line of status output
  if grep -qiE "spec.*line.*status|path.*shown.*status|Spec:.*line" <<< "$body"; then
    pass "R-001(b)" "/creview-spec references Spec: line from status output"
  else
    fail "R-001(b)" "/creview-spec missing reference to Spec: line from status output"
  fi

  # Tests R-001 [unit]: old vague "Read the spec artifact." without path qualifier
  # must be replaced with the explicit path discovery instruction
  if grep -qF "Read the spec artifact." <<< "$body" \
     && ! grep -qF "workflow-advance.sh status" <<< "$body"; then
    fail "R-001(c)" "/creview-spec still has vague 'Read the spec artifact.' without path discovery"
  else
    pass "R-001(c)" "/creview-spec has path discovery or no longer has bare 'Read the spec artifact.'"
  fi
fi

# ============================================================================
# R-002 [unit]: /cverify step 2 has explicit path from workflow-advance.sh
# ============================================================================

section "R-002: /cverify path discovery"

CVERIFY_SKILL="$REPO_DIR/skills/cverify/SKILL.md"

if [ ! -f "$CVERIFY_SKILL" ]; then
  fail "R-002(a)" "skills/cverify/SKILL.md not found"
else
  body="$(skill_body "$CVERIFY_SKILL")"

  # Tests R-002 [unit]: must reference workflow-advance.sh status as canonical source
  if grep -qF "workflow-advance.sh status" <<< "$body"; then
    pass "R-002(a)" "/cverify mentions workflow-advance.sh status"
  else
    fail "R-002(a)" "/cverify missing workflow-advance.sh status reference"
  fi

  # Tests R-002 [unit]: the vague "from workflow state or .correctless/specs/" fallback
  # in step 2 should be removed — only the status output is canonical
  if grep -qF "from workflow state or" <<< "$body"; then
    fail "R-002(b)" "/cverify still has vague 'from workflow state or ...' fallback in step 2"
  else
    pass "R-002(b)" "/cverify removed vague fallback text from step 2"
  fi
fi

# ============================================================================
# R-003 [unit]: /cpostmortem step 3 has path discovery with fallback
# ============================================================================

section "R-003: /cpostmortem path discovery"

CPOSTMORTEM_SKILL="$REPO_DIR/skills/cpostmortem/SKILL.md"

if [ ! -f "$CPOSTMORTEM_SKILL" ]; then
  fail "R-003(a)" "skills/cpostmortem/SKILL.md not found"
else
  body="$(skill_body "$CPOSTMORTEM_SKILL")"

  # Tests R-003 [unit]: must reference workflow-advance.sh status for active workflows
  if grep -qF "workflow-advance.sh status" <<< "$body"; then
    pass "R-003(a)" "/cpostmortem mentions workflow-advance.sh status"
  else
    fail "R-003(a)" "/cpostmortem missing workflow-advance.sh status reference"
  fi

  # Tests R-003 [unit]: must have fallback to .correctless/specs/ for post-merge postmortems
  if grep -qF ".correctless/specs/" <<< "$body"; then
    pass "R-003(b)" "/cpostmortem has .correctless/specs/ fallback for post-merge case"
  else
    fail "R-003(b)" "/cpostmortem missing .correctless/specs/ fallback"
  fi

  # Tests R-003 [unit]: the verification report path pattern must be present
  if grep -qF ".correctless/verification/" <<< "$body"; then
    pass "R-003(c)" "/cpostmortem has verification report path pattern"
  else
    fail "R-003(c)" "/cpostmortem missing verification report path pattern"
  fi
fi

# ============================================================================
# R-004 [unit]: /csummary has workflow-advance.sh status call
# ============================================================================

section "R-004: /csummary path discovery"

CSUMMARY_SKILL="$REPO_DIR/skills/csummary/SKILL.md"

if [ ! -f "$CSUMMARY_SKILL" ]; then
  fail "R-004(a)" "skills/csummary/SKILL.md not found"
else
  body="$(skill_body "$CSUMMARY_SKILL")"

  # Tests R-004 [unit]: must include workflow-advance.sh status call
  if grep -qF "workflow-advance.sh status" <<< "$body"; then
    pass "R-004(a)" "/csummary mentions workflow-advance.sh status"
  else
    fail "R-004(a)" "/csummary missing workflow-advance.sh status call"
  fi

  # Tests R-004 [unit]: must have fallback for when no active workflow exists
  if grep -qF ".correctless/specs/" <<< "$body"; then
    pass "R-004(b)" "/csummary has .correctless/specs/ fallback for no-workflow case"
  else
    fail "R-004(b)" "/csummary missing .correctless/specs/ fallback for no-workflow case"
  fi
fi

# ============================================================================
# R-005 [unit]: Structural guard — MUST_HAVE skills have path discovery tokens
# Note: The structural guard itself is added to test-architecture-drift.sh.
# This test verifies the guard function exists there and covers the right
# skills. The actual enforcement runs as part of the drift test suite.
# ============================================================================

section "R-005: Structural guard in test-architecture-drift.sh"

DRIFT_TEST="$REPO_DIR/tests/test-architecture-drift.sh"

if [ ! -f "$DRIFT_TEST" ]; then
  fail "R-005(a)" "tests/test-architecture-drift.sh not found"
else
  # Tests R-005 [unit]: drift test must contain the path discovery guard function
  if grep -qF "check_path_discovery_guard" "$DRIFT_TEST"; then
    pass "R-005(a)" "test-architecture-drift.sh contains check_path_discovery_guard function"
  else
    fail "R-005(a)" "test-architecture-drift.sh missing check_path_discovery_guard function"
  fi

  # Tests R-005 [unit]: MUST_HAVE list must include all 8 required skills
  must_have_skills="creview-spec creview ctdd cverify cpostmortem csummary cdocs cmodel"
  for skill in $must_have_skills; do
    if grep -qE "MUST_HAVE_DISCOVERY.*$skill|$skill.*MUST_HAVE_DISCOVERY|must_have_discovery.*$skill|\"$skill\"" "$DRIFT_TEST"; then
      pass "R-005(b)-$skill" "$skill is in MUST_HAVE_DISCOVERY list"
    else
      fail "R-005(b)-$skill" "$skill missing from MUST_HAVE_DISCOVERY list"
    fi
  done

  # Tests R-005 [unit]: EXCLUDED list must exist
  if grep -qF "EXCLUDED_FROM_DISCOVERY" "$DRIFT_TEST"; then
    pass "R-005(c)" "EXCLUDED_FROM_DISCOVERY list exists"
  else
    fail "R-005(c)" "EXCLUDED_FROM_DISCOVERY list missing"
  fi

  # Tests R-005 [unit]: guard function must be defined AND invoked
  guard_count="$(grep -cF "check_path_discovery_guard" "$DRIFT_TEST")" || guard_count=0
  if [ "$guard_count" -ge 2 ]; then
    pass "R-005(d)" "check_path_discovery_guard is defined and invoked ($guard_count occurrences)"
  else
    fail "R-005(d)" "check_path_discovery_guard not properly defined and invoked (only $guard_count occurrence)"
  fi

  # Tests R-005 [unit]: error message for unclassified skills must be present
  if grep -qF "not classified in path-discovery guard" "$DRIFT_TEST"; then
    pass "R-005(e)" "unclassified skill error message is present"
  else
    fail "R-005(e)" "unclassified skill error message missing"
  fi
fi

# ============================================================================
# R-005 functional: verify the guard actually works by checking all current
# skills are classified (the structural guard in drift test passes)
# ============================================================================

section "R-005 functional: all skills classified"

# Enumerate all skill directories
all_skills=""
for skill_dir in "$REPO_DIR"/skills/*/; do
  [ -d "$skill_dir" ] || continue
  skill_name="$(basename "$skill_dir")"
  # Skip _shared — it's not a skill
  [ "$skill_name" = "_shared" ] && continue
  all_skills="$all_skills $skill_name"
done

# The MUST_HAVE list
must_have="creview-spec creview ctdd cverify cpostmortem csummary cdocs cmodel cmodelupgrade"

# The EXCLUDED list from the spec
excluded="crelease cupdate-arch carchitect csetup chelp cstatus cquick cexplain cdebug crefactor ccontribute cmaintain cpr-review credteam caudit cdevadv cauto cwtf cmetrics cspec cdashboard ctriage"

for skill in $all_skills; do
  in_must=0
  in_excluded=0
  for m in $must_have; do
    [ "$skill" = "$m" ] && in_must=1 && break
  done
  for e in $excluded; do
    [ "$skill" = "$e" ] && in_excluded=1 && break
  done
  if [ "$in_must" = "1" ] || [ "$in_excluded" = "1" ]; then
    pass "R-005(f)-$skill" "skill $skill is classified"
  else
    fail "R-005(f)-$skill" "skill $skill not in MUST_HAVE or EXCLUDED list — add to one"
  fi
done

# ============================================================================
# R-005 enforcement: MUST_HAVE skills actually contain at least one discovery token
# ============================================================================

section "R-005 enforcement: MUST_HAVE skills have discovery tokens"

discovery_tokens="workflow-advance\.sh status|spec_file|path from workflow|\.correctless/specs/"

for skill in $must_have; do
  skill_file="$REPO_DIR/skills/$skill/SKILL.md"
  if [ ! -f "$skill_file" ]; then
    fail "R-005(g)-$skill" "skill file not found: $skill_file"
    continue
  fi
  body="$(skill_body "$skill_file")"
  if grep -qE "$discovery_tokens" <<< "$body"; then
    pass "R-005(g)-$skill" "$skill has at least one path discovery token"
  else
    fail "R-005(g)-$skill" "$skill missing all path discovery tokens"
  fi
done

# ============================================================================
# R-006 [unit]: sync is clean after edits
# ============================================================================

section "R-006: sync clean"

# Run sync and verify that the distribution copies are byte-equal to sources.
# We can't use git diff because the distribution files may be newly synced
# (uncommitted). Instead, run sync.sh then compare a synced skill file
# against its source to confirm the sync propagated correctly.
bash "$REPO_DIR/sync.sh" >/dev/null 2>&1
sync_ok=1
for skill_dir in "$REPO_DIR"/skills/*/; do
  [ -d "$skill_dir" ] || continue
  skill_name="$(basename "$skill_dir")"
  src="$REPO_DIR/skills/$skill_name/SKILL.md"
  dst="$REPO_DIR/correctless/skills/$skill_name/SKILL.md"
  [ -f "$src" ] || continue
  [ -f "$dst" ] || { sync_ok=0; break; }
  if ! diff -q "$src" "$dst" >/dev/null 2>&1; then
    sync_ok=0
    break
  fi
done
if [ "$sync_ok" = "1" ]; then
  pass "R-006" "distribution skill files match source after sync"
else
  fail "R-006" "distribution out of sync with source files"
fi

# ============================================================================
# Summary
# ============================================================================

summary "Skill Path Discovery Tests"
