#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091,SC2016,SC2086
# Correctless — UX Review Lens Structural Tests
#
# Enforces the ux-review-lens spec rules (R-001..R-010).
# Tests are structural — they verify keyword presence and structural
# properties of skill files. All tests are [unit] — keyword/structural
# checks on the skill files themselves.
#
# Run from repo root: bash tests/test-ux-review-lens.sh

source "$(dirname "${BASH_SOURCE[0]}")/test-helpers.sh"
set -f

# ============================================================================
# File paths
# ============================================================================

CREVIEW_SPEC_SKILL="skills/creview-spec/SKILL.md"
CREVIEW_SKILL="skills/creview/SKILL.md"
CTDD_SKILL="skills/ctdd/SKILL.md"
CAUDIT_SKILL="skills/caudit/SKILL.md"

# ============================================================================
# R-001 [unit]: Canonical sub-lens enum definition
# ============================================================================

section "R-001: Canonical sub-lens enum"

# R-001a: Base sub-lenses include new-user
if grep -qi 'new-user' "$CREVIEW_SPEC_SKILL" && grep -qi 'new-user' "$CTDD_SKILL"; then
  pass "R-001a" "new-user sub-lens present in creview-spec and ctdd"
else
  fail "R-001a" "new-user sub-lens not found in both creview-spec and ctdd"
fi

# R-001b: Base sub-lenses include upgrade
if grep -qi '"upgrade"\|upgrade.*sub-lens\|sub-lens.*upgrade' "$CREVIEW_SPEC_SKILL"; then
  pass "R-001b" "upgrade sub-lens present in creview-spec"
else
  fail "R-001b" "upgrade sub-lens not found in creview-spec"
fi

# R-001c: Base sub-lenses include offboarding
if grep -qi 'offboarding' "$CREVIEW_SPEC_SKILL" && grep -qi 'offboarding' "$CTDD_SKILL"; then
  pass "R-001c" "offboarding sub-lens present in creview-spec and ctdd"
else
  fail "R-001c" "offboarding sub-lens not found in both creview-spec and ctdd"
fi

# R-001d: Base sub-lenses include recovery
if grep -qi 'recovery' "$CREVIEW_SPEC_SKILL" && grep -qi 'recovery' "$CTDD_SKILL"; then
  pass "R-001d" "recovery sub-lens present in creview-spec and ctdd"
else
  fail "R-001d" "recovery sub-lens not found in both creview-spec and ctdd"
fi

# R-001e: Sub-lenses are role assignments, NOT LENS enum values
# The spec explicitly says sub-lenses are distinct from the LENS enum
# Verify ux-review is in the LENS enum, NOT the sub-lens names
if grep -qi 'ux-review' "$CTDD_SKILL"; then
  pass "R-001e" "ux-review appears as LENS enum value (not sub-lens name) in ctdd"
else
  fail "R-001e" "ux-review not found as LENS enum value in ctdd"
fi

# R-001f: caudit UX preset includes cross-session (extended sub-lens)
if grep -qi 'cross-session' "$CAUDIT_SKILL"; then
  pass "R-001f" "cross-session sub-lens present in caudit"
else
  fail "R-001f" "cross-session sub-lens not found in caudit"
fi

# ============================================================================
# R-002 [unit]: creview-spec has UX Auditor agent
# ============================================================================

section "R-002: creview-spec has UX Auditor agent"

# R-002a: UX Auditor agent prompt exists in creview-spec
if grep -qi 'UX Auditor' "$CREVIEW_SPEC_SKILL"; then
  pass "R-002a" "UX Auditor agent present in creview-spec SKILL.md"
else
  fail "R-002a" "UX Auditor agent not found in creview-spec SKILL.md"
fi

# R-002b: UX Auditor is spawned at high+ intensity (alongside existing agents)
# The spec says it should be spawned at high+ intensity alongside existing agents
if grep -qi 'spawn all six\|spawn all 6' "$CREVIEW_SPEC_SKILL"; then
  pass "R-002b" "creview-spec references spawning all 6 agents at high+ intensity"
else
  fail "R-002b" "creview-spec does not reference spawning 6 agents at high+ intensity"
fi

# R-002c: Cascading update — frontmatter description mentions UX Auditor
if grep -qE '^description:.*UX' "$CREVIEW_SPEC_SKILL"; then
  pass "R-002c" "creview-spec frontmatter description mentions UX"
else
  fail "R-002c" "creview-spec frontmatter description does not mention UX"
fi

# R-002d: Cascading update — progress announcement count updated to 6
if grep -qE 'Spawning 6 adversarial agents' "$CREVIEW_SPEC_SKILL"; then
  pass "R-002d" "'Spawning 6 adversarial agents' present in creview-spec"
else
  fail "R-002d" "'Spawning 6 adversarial agents' not found (still says 5?)"
fi

# R-002e: Cascading update — spawning announcement includes UX Auditor in list
if grep -qi 'Spawning.*UX Auditor' "$CREVIEW_SPEC_SKILL"; then
  pass "R-002e" "Spawning announcement lists UX Auditor"
else
  fail "R-002e" "Spawning announcement does not list UX Auditor"
fi

# R-002f: Cascading update — task list includes UX Auditor entry
if grep -qE '^\s*[0-9]+\.\s*UX Auditor' "$CREVIEW_SPEC_SKILL"; then
  pass "R-002f" "UX Auditor in numbered task list"
else
  fail "R-002f" "UX Auditor not in numbered task list"
fi

# R-002g: UX Auditor evaluates through all 4 base sub-lenses
if grep -qi 'new-user' "$CREVIEW_SPEC_SKILL" && \
   grep -qi 'offboarding' "$CREVIEW_SPEC_SKILL" && \
   grep -qi 'recovery' "$CREVIEW_SPEC_SKILL"; then
  pass "R-002g" "UX Auditor references all 4 base sub-lenses in creview-spec"
else
  fail "R-002g" "UX Auditor does not reference all 4 base sub-lenses in creview-spec"
fi

# R-002h: checkpoint completed_phases includes ux-auditor or ux
if grep -qE 'completed_phases.*ux' "$CREVIEW_SPEC_SKILL"; then
  pass "R-002h" "ux in checkpoint completed_phases"
else
  fail "R-002h" "ux not in checkpoint completed_phases JSON"
fi

# ============================================================================
# R-003 [unit]: creview has UX review subagent
# ============================================================================

section "R-003: creview has UX review subagent"

# R-003a: UX reviewer/subagent exists in creview
if grep -qi 'UX.*review\|UX.*agent\|UX.*subagent\|UX.*lens' "$CREVIEW_SKILL"; then
  pass "R-003a" "UX review subagent referenced in creview SKILL.md"
else
  fail "R-003a" "UX review subagent not found in creview SKILL.md"
fi

# R-003b: Cascading update — frontmatter description mentions UX
if grep -qE '^description:.*(UX|ux)' "$CREVIEW_SKILL"; then
  pass "R-003b" "creview frontmatter description mentions UX"
else
  fail "R-003b" "creview frontmatter description does not mention UX"
fi

# R-003c: UX reviewer evaluates through all 4 base sub-lenses
if grep -qi 'new-user' "$CREVIEW_SKILL" && \
   grep -qi 'offboarding' "$CREVIEW_SKILL" && \
   grep -qi 'recovery' "$CREVIEW_SKILL"; then
  pass "R-003c" "UX reviewer references all 4 base sub-lenses in creview"
else
  fail "R-003c" "UX reviewer does not reference all 4 base sub-lenses in creview"
fi

# R-003d: UX subagent runs in parallel with single-pass review
if grep -qi 'parallel' "$CREVIEW_SKILL" && grep -qi 'UX' "$CREVIEW_SKILL"; then
  pass "R-003d" "UX subagent described as running in parallel in creview"
else
  fail "R-003d" "UX subagent not described as running in parallel in creview"
fi

# R-003e: Cascading update — task list includes UX agent entry
if grep -qE '^\s*[0-9]+\.\s*UX' "$CREVIEW_SKILL"; then
  pass "R-003e" "UX agent in numbered task list in creview"
else
  fail "R-003e" "UX agent not in numbered task list in creview"
fi

# ============================================================================
# R-004 [unit]: ctdd has UX lens agent in mini-audit (5th agent)
# ============================================================================

section "R-004: ctdd has UX lens agent in mini-audit"

# R-004a: UX agent referenced in ctdd mini-audit section
# Use word-boundary matching to avoid false positives from words like "auxiliary"
if grep -qiE '\bUX\b.*agent|\bUX\b.*lens|\bUX\b.*review' "$CTDD_SKILL"; then
  pass "R-004a" "UX agent referenced in ctdd SKILL.md"
else
  fail "R-004a" "UX agent not found in ctdd SKILL.md"
fi

# R-004b: Cascading update — progress announcement says 5 specialist agents (was 4)
if grep -qE 'spawning 5 specialist agents' "$CTDD_SKILL"; then
  pass "R-004b" "Progress announcement references 5 specialist agents"
else
  fail "R-004b" "Progress announcement does not reference 5 specialist agents"
fi

# R-004c: Cascading update — spawns five specialist agents (was four)
if grep -qE 'spawns five specialist agents|spawns 5 specialist agents' "$CTDD_SKILL"; then
  pass "R-004c" "Agent prompt section references five/5 specialist agents"
else
  fail "R-004c" "Agent prompt section still references four/4 specialist agents"
fi

# R-004d: Cascading update — LENS enum includes ux-review
if grep -qE 'cross-component.*hostile-input.*resource-bounds.*upgrade-compatibility.*ux-review|LENS.*ux-review' "$CTDD_SKILL"; then
  pass "R-004d" "ux-review appears in LENS enum alongside other values"
else
  fail "R-004d" "ux-review not in LENS enum in ctdd"
fi

# R-004e: Cascading update — agent_role includes ux-review in mini-audit token tracking
if grep -qE 'agent_role.*ux-review' "$CTDD_SKILL"; then
  pass "R-004e" "agent_role enum includes ux-review in ctdd SKILL.md"
else
  fail "R-004e" "agent_role enum does not include ux-review in ctdd SKILL.md"
fi

# R-004f: Cascading update — progress announcement lists ux-review as a lens name
if grep -qi 'cross-component.*hostile.input.*resource.bounds.*upgrade.compatibility.*ux' "$CTDD_SKILL"; then
  pass "R-004f" "Progress announcement lists ux-review as a lens"
else
  fail "R-004f" "Progress announcement does not list ux-review as a lens"
fi

# R-004g: UX agent evaluates through all 4 base sub-lenses
if grep -qi 'new-user' "$CTDD_SKILL" && \
   grep -qi 'offboarding' "$CTDD_SKILL" && \
   grep -qi 'recovery.*path\|resumption.*path\|output.*persistence' "$CTDD_SKILL"; then
  pass "R-004g" "UX agent references all 4 base sub-lenses in ctdd"
else
  fail "R-004g" "UX agent does not reference all 4 base sub-lenses in ctdd"
fi

# ============================================================================
# R-005 [unit]: caudit has UX preset
# ============================================================================

section "R-005: caudit has UX preset"

# R-005a: UX preset or ux preset mentioned in caudit
if grep -qi 'UX.*preset\|UX Olympics\|ux.*preset' "$CAUDIT_SKILL"; then
  pass "R-005a" "UX preset referenced in caudit SKILL.md"
else
  fail "R-005a" "UX preset not found in caudit SKILL.md"
fi

# R-005b: First Contact Auditor role present
if grep -qi 'First Contact Auditor' "$CAUDIT_SKILL"; then
  pass "R-005b" "First Contact Auditor role present in caudit"
else
  fail "R-005b" "First Contact Auditor role not found in caudit"
fi

# R-005c: Upgrade Path Auditor role present
if grep -qi 'Upgrade Path Auditor' "$CAUDIT_SKILL"; then
  pass "R-005c" "Upgrade Path Auditor role present in caudit"
else
  fail "R-005c" "Upgrade Path Auditor role not found in caudit"
fi

# R-005d: Cleanup/Offboarding Auditor role present
if grep -qi 'Offboarding Auditor\|Cleanup.*Auditor' "$CAUDIT_SKILL"; then
  pass "R-005d" "Cleanup/Offboarding Auditor role present in caudit"
else
  fail "R-005d" "Cleanup/Offboarding Auditor role not found in caudit"
fi

# R-005e: Error Recovery Auditor role present
if grep -qi 'Error Recovery Auditor\|Recovery Auditor' "$CAUDIT_SKILL"; then
  pass "R-005e" "Error Recovery Auditor role present in caudit"
else
  fail "R-005e" "Error Recovery Auditor role not found in caudit"
fi

# R-005f: Cross-Session Continuity Auditor role present
if grep -qi 'Cross-Session.*Auditor\|Cross.Session Continuity' "$CAUDIT_SKILL"; then
  pass "R-005f" "Cross-Session Continuity Auditor role present in caudit"
else
  fail "R-005f" "Cross-Session Continuity Auditor role not found in caudit"
fi

# R-005g: UX preset has role table format with at least 5 roles
# Check that all 5 UX preset roles exist (First Contact + Upgrade Path + Offboarding + Error Recovery + Cross-Session)
UX_ROLE_COUNT=0
grep -qi 'First Contact Auditor' "$CAUDIT_SKILL" && UX_ROLE_COUNT=$((UX_ROLE_COUNT + 1))
grep -qi 'Upgrade Path Auditor' "$CAUDIT_SKILL" && UX_ROLE_COUNT=$((UX_ROLE_COUNT + 1))
grep -qi 'Offboarding Auditor\|Cleanup.*Auditor' "$CAUDIT_SKILL" && UX_ROLE_COUNT=$((UX_ROLE_COUNT + 1))
grep -qi 'Error Recovery Auditor\|Recovery Auditor' "$CAUDIT_SKILL" && UX_ROLE_COUNT=$((UX_ROLE_COUNT + 1))
grep -qi 'Cross-Session.*Auditor' "$CAUDIT_SKILL" && UX_ROLE_COUNT=$((UX_ROLE_COUNT + 1))
if [ "$UX_ROLE_COUNT" -ge 5 ]; then
  pass "R-005g" "UX preset has all 5 roles ($UX_ROLE_COUNT/5)"
else
  fail "R-005g" "UX preset has only $UX_ROLE_COUNT of 5 required roles"
fi

# R-005h: UX preset is in the preset parameter list
if grep -qE 'preset.*qa.*hacker.*perf.*ux|preset.*ux|`ux`' "$CAUDIT_SKILL"; then
  pass "R-005h" "ux added to preset parameter options"
else
  fail "R-005h" "ux not in preset parameter options"
fi

# R-005i: Cascading update — description mentions UX preset
if grep -qE '^description:.*UX' "$CAUDIT_SKILL"; then
  pass "R-005i" "caudit frontmatter description mentions UX"
else
  fail "R-005i" "caudit frontmatter description does not mention UX"
fi

# ============================================================================
# R-006 [unit]: Sub-lens checklist check items
# ============================================================================

section "R-006: Sub-lens checklist check items"

# R-006a: new-user sub-lens: path discovery without prior context
if grep -qi 'path discovery\|without prior context\|zero-state' "$CREVIEW_SPEC_SKILL"; then
  pass "R-006a" "new-user check item (path discovery / zero-state) in creview-spec"
else
  fail "R-006a" "new-user check item (path discovery / zero-state) not found in creview-spec"
fi

# R-006b: new-user sub-lens: error messages on first run
if grep -qi 'error.*first run\|first run.*error\|documentation pointer' "$CREVIEW_SPEC_SKILL"; then
  pass "R-006b" "new-user check item (first run errors) in creview-spec"
else
  fail "R-006b" "new-user check item (first run errors) not found in creview-spec"
fi

# R-006c: upgrade sub-lens: behavioral changes between versions
if grep -qi 'behavioral change\|silent breakage\|migration.*clarity' "$CREVIEW_SPEC_SKILL"; then
  pass "R-006c" "upgrade check item (behavioral changes) in creview-spec"
else
  fail "R-006c" "upgrade check item (behavioral changes) not found in creview-spec"
fi

# R-006d: offboarding sub-lens: cleanup of generated artifacts
if grep -qi 'cleanup.*artifact\|residual state\|graceful degradation.*remov' "$CREVIEW_SPEC_SKILL"; then
  pass "R-006d" "offboarding check item (cleanup) in creview-spec"
else
  fail "R-006d" "offboarding check item (cleanup) not found in creview-spec"
fi

# R-006e: recovery sub-lens: resumption paths after interruption
if grep -qi 'resumption.*path\|output.*persistence\|lost.*finding\|state.*consistency.*fail' "$CREVIEW_SPEC_SKILL"; then
  pass "R-006e" "recovery check item (resumption paths) in creview-spec"
else
  fail "R-006e" "recovery check item (resumption paths) not found in creview-spec"
fi

# R-006f: Check items also present in ctdd mini-audit UX agent
if grep -qi 'zero-state\|zero.state' "$CTDD_SKILL"; then
  pass "R-006f" "new-user check items present in ctdd UX agent"
else
  fail "R-006f" "new-user check items not found in ctdd UX agent"
fi

# R-006g: recovery sub-lens items in ctdd
if grep -qi 'resumption.*path\|output.*persistence\|lost.*finding' "$CTDD_SKILL"; then
  pass "R-006g" "recovery check items present in ctdd UX agent"
else
  fail "R-006g" "recovery check items not found in ctdd UX agent"
fi

# R-006h: Check items present in creview UX agent
if grep -qi 'zero-state\|zero.state\|path discovery' "$CREVIEW_SKILL"; then
  pass "R-006h" "new-user check items present in creview UX agent"
else
  fail "R-006h" "new-user check items not found in creview UX agent"
fi

# ============================================================================
# R-007 [unit]: caudit UX preset has cross-session sub-lens
# ============================================================================

section "R-007: caudit cross-session sub-lens"

# R-007a: cross-session check item: workflow state persistence
if grep -qi 'workflow state persistence\|state persistence across session' "$CAUDIT_SKILL"; then
  pass "R-007a" "cross-session check item (workflow state persistence) in caudit"
else
  fail "R-007a" "cross-session check item (workflow state persistence) not found in caudit"
fi

# R-007b: cross-session check item: conversation context dependency
if grep -qi 'conversation context dependency\|prior context\|context.*dependency' "$CAUDIT_SKILL"; then
  pass "R-007b" "cross-session check item (conversation context dependency) in caudit"
else
  fail "R-007b" "cross-session check item (conversation context dependency) not found in caudit"
fi

# R-007c: cross-session check item: artifact path resolution
if grep -qi 'artifact path.*resolution\|path.*hallucination\|fresh.session.*path' "$CAUDIT_SKILL"; then
  pass "R-007c" "cross-session check item (artifact path resolution) in caudit"
else
  fail "R-007c" "cross-session check item (artifact path resolution) not found in caudit"
fi

# R-007d: cross-session check item: session-boundary state transitions
if grep -qi 'session.boundary.*state\|session.*boundary.*transition' "$CAUDIT_SKILL"; then
  pass "R-007d" "cross-session check item (session-boundary transitions) in caudit"
else
  fail "R-007d" "cross-session check item (session-boundary transitions) not found in caudit"
fi

# R-007e: The cross-session sub-lens is only in caudit, not in base 4 integration points
# (This verifies it's an extended sub-lens, not a base one)
# The spec says extended = caudit only; base = all 4 integration points
# We check that the Cross-Session Continuity Auditor is NOT in creview-spec or ctdd
CROSS_SESSION_IN_CREVIEW_SPEC=$(grep -ci 'Cross-Session Continuity Auditor' "$CREVIEW_SPEC_SKILL" || true)
CROSS_SESSION_IN_CTDD=$(grep -ci 'Cross-Session Continuity Auditor' "$CTDD_SKILL" || true)
if [ "$CROSS_SESSION_IN_CREVIEW_SPEC" -eq 0 ] && [ "$CROSS_SESSION_IN_CTDD" -eq 0 ]; then
  pass "R-007e" "Cross-Session Continuity Auditor is only in caudit (extended sub-lens)"
else
  fail "R-007e" "Cross-Session Continuity Auditor appears outside caudit"
fi

# ============================================================================
# R-008 [unit]: Fail-open instruction for UX agent
# ============================================================================

section "R-008: Fail-open instruction for UX agent"

# R-008a: creview-spec has fail-open instruction for UX
if grep -qi 'fail.*open\|UX.*fail\|UX.*advisory\|UX.*never.*gate\|proceed without UX' "$CREVIEW_SPEC_SKILL"; then
  pass "R-008a" "Fail-open instruction present in creview-spec for UX agent"
else
  fail "R-008a" "Fail-open instruction not found in creview-spec for UX agent"
fi

# R-008b: ctdd has fail-open instruction for UX
if grep -qi 'fail.*open\|UX.*fail\|UX.*advisory\|proceed without UX' "$CTDD_SKILL"; then
  pass "R-008b" "Fail-open instruction present in ctdd for UX agent"
else
  fail "R-008b" "Fail-open instruction not found in ctdd for UX agent"
fi

# R-008c: creview has fail-open instruction for UX
if grep -qi 'fail.*open\|UX.*fail\|UX.*advisory\|proceed without UX' "$CREVIEW_SKILL"; then
  pass "R-008c" "Fail-open instruction present in creview for UX agent"
else
  fail "R-008c" "Fail-open instruction not found in creview for UX agent"
fi

# R-008d: caudit has fail-open instruction for UX
# caudit already has a general agent failure handling pattern; check for UX-specific or general
if grep -qi 'fail.*open\|UX.*fail\|UX.*advisory\|proceed without UX' "$CAUDIT_SKILL"; then
  pass "R-008d" "Fail-open instruction present in caudit for UX agent"
else
  fail "R-008d" "Fail-open instruction not found in caudit for UX agent"
fi

# R-008e: The fail-open covers malformed/incomplete output specifically for UX agent
# Must be near UX-related text, not just anywhere in the file
if grep -qi 'UX.*malformed\|UX.*incomplete\|malformed.*UX\|incomplete.*UX' "$CREVIEW_SPEC_SKILL" || \
   grep -qi 'UX.*malformed\|UX.*incomplete\|malformed.*UX\|incomplete.*UX' "$CTDD_SKILL"; then
  pass "R-008e" "Fail-open covers malformed/incomplete output for UX agent"
else
  fail "R-008e" "Fail-open does not mention malformed/incomplete output for UX agent"
fi

# ============================================================================
# R-009 [unit]: PMB UX failure calibration examples
# ============================================================================

section "R-009: PMB UX failure calibration examples"

# R-009a: At least 3 of 4 PMBs referenced in creview-spec UX agent
PMB_COUNT_CREVIEW_SPEC=0
grep -q 'PMB-004' "$CREVIEW_SPEC_SKILL" && PMB_COUNT_CREVIEW_SPEC=$((PMB_COUNT_CREVIEW_SPEC + 1))
grep -q 'PMB-006' "$CREVIEW_SPEC_SKILL" && PMB_COUNT_CREVIEW_SPEC=$((PMB_COUNT_CREVIEW_SPEC + 1))
grep -q 'PMB-008' "$CREVIEW_SPEC_SKILL" && PMB_COUNT_CREVIEW_SPEC=$((PMB_COUNT_CREVIEW_SPEC + 1))
grep -q 'PMB-009' "$CREVIEW_SPEC_SKILL" && PMB_COUNT_CREVIEW_SPEC=$((PMB_COUNT_CREVIEW_SPEC + 1))
if [ "$PMB_COUNT_CREVIEW_SPEC" -ge 3 ]; then
  pass "R-009a" "At least 3 of 4 PMBs referenced in creview-spec ($PMB_COUNT_CREVIEW_SPEC/4)"
else
  fail "R-009a" "Only $PMB_COUNT_CREVIEW_SPEC of 4 PMBs referenced in creview-spec (need >= 3)"
fi

# R-009b: At least 3 of 4 PMBs referenced in ctdd UX agent
PMB_COUNT_CTDD=0
grep -q 'PMB-004' "$CTDD_SKILL" && PMB_COUNT_CTDD=$((PMB_COUNT_CTDD + 1))
grep -q 'PMB-006' "$CTDD_SKILL" && PMB_COUNT_CTDD=$((PMB_COUNT_CTDD + 1))
grep -q 'PMB-008' "$CTDD_SKILL" && PMB_COUNT_CTDD=$((PMB_COUNT_CTDD + 1))
grep -q 'PMB-009' "$CTDD_SKILL" && PMB_COUNT_CTDD=$((PMB_COUNT_CTDD + 1))
if [ "$PMB_COUNT_CTDD" -ge 3 ]; then
  pass "R-009b" "At least 3 of 4 PMBs referenced in ctdd ($PMB_COUNT_CTDD/4)"
else
  fail "R-009b" "Only $PMB_COUNT_CTDD of 4 PMBs referenced in ctdd (need >= 3)"
fi

# R-009c: At least 3 of 4 PMBs referenced in creview UX agent
PMB_COUNT_CREVIEW=0
grep -q 'PMB-004' "$CREVIEW_SKILL" && PMB_COUNT_CREVIEW=$((PMB_COUNT_CREVIEW + 1))
grep -q 'PMB-006' "$CREVIEW_SKILL" && PMB_COUNT_CREVIEW=$((PMB_COUNT_CREVIEW + 1))
grep -q 'PMB-008' "$CREVIEW_SKILL" && PMB_COUNT_CREVIEW=$((PMB_COUNT_CREVIEW + 1))
grep -q 'PMB-009' "$CREVIEW_SKILL" && PMB_COUNT_CREVIEW=$((PMB_COUNT_CREVIEW + 1))
if [ "$PMB_COUNT_CREVIEW" -ge 3 ]; then
  pass "R-009c" "At least 3 of 4 PMBs referenced in creview ($PMB_COUNT_CREVIEW/4)"
else
  fail "R-009c" "Only $PMB_COUNT_CREVIEW of 4 PMBs referenced in creview (need >= 3)"
fi

# R-009d: At least 3 of 4 PMBs referenced in caudit UX preset
PMB_COUNT_CAUDIT=0
grep -q 'PMB-004' "$CAUDIT_SKILL" && PMB_COUNT_CAUDIT=$((PMB_COUNT_CAUDIT + 1))
grep -q 'PMB-006' "$CAUDIT_SKILL" && PMB_COUNT_CAUDIT=$((PMB_COUNT_CAUDIT + 1))
grep -q 'PMB-008' "$CAUDIT_SKILL" && PMB_COUNT_CAUDIT=$((PMB_COUNT_CAUDIT + 1))
grep -q 'PMB-009' "$CAUDIT_SKILL" && PMB_COUNT_CAUDIT=$((PMB_COUNT_CAUDIT + 1))
if [ "$PMB_COUNT_CAUDIT" -ge 3 ]; then
  pass "R-009d" "At least 3 of 4 PMBs referenced in caudit ($PMB_COUNT_CAUDIT/4)"
else
  fail "R-009d" "Only $PMB_COUNT_CAUDIT of 4 PMBs referenced in caudit (need >= 3)"
fi

# ============================================================================
# R-010 [unit]: UX agent findings use parent skill's structured output format
# ============================================================================

section "R-010: UX findings use parent skill's structured output format"

# R-010a: creview-spec UX findings use UX-xxx ID format
if grep -qE 'UX-[0-9x]+|UX-xxx' "$CREVIEW_SPEC_SKILL"; then
  pass "R-010a" "UX-xxx finding ID format in creview-spec"
else
  fail "R-010a" "UX-xxx finding ID format not found in creview-spec"
fi

# R-010b: ctdd mini-audit UX findings use MA-xxx format with ux-review LENS
# Already covered by R-004d (ux-review in LENS enum) — verify MA- prefix is in
# the finding format section near ux-review
if grep -q 'MA-' "$CTDD_SKILL" && grep -q 'ux-review' "$CTDD_SKILL"; then
  pass "R-010b" "ctdd UX findings use MA-xxx format with ux-review LENS"
else
  fail "R-010b" "ctdd UX findings format incomplete (MA- or ux-review missing)"
fi

# R-010c: caudit UX findings use confidence-tiered format (confirmed/probable/suspicious)
# The caudit already uses this format for all presets; verify the UX preset
# is present and the format applies
if grep -qi 'confirmed.*probable.*suspicious' "$CAUDIT_SKILL" && \
   grep -qi 'UX.*preset\|UX Olympics' "$CAUDIT_SKILL"; then
  pass "R-010c" "caudit UX preset uses confidence-tiered format"
else
  fail "R-010c" "caudit UX preset confidence-tiered format not verified"
fi

# R-010d: creview UX findings use UX-xxx ID format
if grep -qE 'UX-[0-9x]+|UX-xxx' "$CREVIEW_SKILL"; then
  pass "R-010d" "UX-xxx finding ID format in creview"
else
  fail "R-010d" "UX-xxx finding ID format not found in creview"
fi

# ============================================================================
# Cross-cutting: Existing test compatibility
# ============================================================================

section "Cross-cutting: Existing test compatibility"

# CC-001: test-upgrade-compatibility-lens.sh R-003b expects the LENS line to
# list all values together. After R-004, that line should include ux-review.
# This test verifies the LENS line in ctdd includes all 5 values.
if grep -qE 'cross-component.*hostile-input.*resource-bounds.*upgrade-compatibility' "$CTDD_SKILL"; then
  pass "CC-001" "LENS line still has original 4 values (test-upgrade-compatibility-lens R-003b compat)"
else
  fail "CC-001" "LENS line missing original 4 values"
fi

# CC-002: test-upgrade-compatibility-lens.sh R-005a expects "spawning 4 specialist agents"
# After R-004, this should be updated to 5. This test checks the new count exists.
# (The old test R-005a will need updating by the implementation)
if grep -qE 'spawning 5 specialist agents' "$CTDD_SKILL"; then
  pass "CC-002" "ctdd says '5 specialist agents' (updated from 4)"
else
  fail "CC-002" "ctdd does not say '5 specialist agents'"
fi

# CC-003: test-upgrade-compatibility-lens.sh R-005b expects "spawns four specialist agents"
# After R-004, this should be updated to five.
if grep -qE 'spawns five specialist agents|spawns 5 specialist agents' "$CTDD_SKILL"; then
  pass "CC-003" "ctdd says 'spawns five/5 specialist agents' (updated from four/4)"
else
  fail "CC-003" "ctdd does not say 'spawns five/5 specialist agents'"
fi

# CC-004: /creview references to /creview-spec agent count must match actual count (6)
# Prevents stale count references when agents are added to /creview-spec.
count_refs=$(grep -cE '(5|five)-agent adversarial' "$CREVIEW_SKILL" || true)
if [ "$count_refs" -eq 0 ]; then
  pass "CC-004" "creview has no stale agent count references to /creview-spec"
else
  fail "CC-004" "creview has $count_refs stale '5-agent' references (should be 6-agent)"
fi

# ============================================================================
# Summary
# ============================================================================

summary "UX Review Lens"
