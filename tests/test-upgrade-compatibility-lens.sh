#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091,SC2016,SC2086
# Correctless — Upgrade Compatibility Lens Structural Tests
#
# Enforces the upgrade-compatibility-lens spec rules (R-001..R-008).
# Tests are structural — they verify keyword presence and structural
# properties of skill files. All tests are [unit] — keyword/structural
# checks on the skill files themselves.
#
# Run from repo root: bash tests/test-upgrade-compatibility-lens.sh

source "$(dirname "${BASH_SOURCE[0]}")/test-helpers.sh"
set -f

# ============================================================================
# File paths
# ============================================================================

CREVIEW_SPEC_SKILL="skills/creview-spec/SKILL.md"
CTDD_SKILL="skills/ctdd/SKILL.md"

# ============================================================================
# R-001 [unit]: creview-spec SKILL.md has Upgrade Compatibility Auditor
# ============================================================================

section "R-001: creview-spec has Upgrade Compatibility Auditor agent"

# R-001a: The upgrade compatibility agent prompt exists in creview-spec
if grep -qi 'Upgrade Compatibility Auditor' "$CREVIEW_SPEC_SKILL"; then
  pass "R-001a" "Upgrade Compatibility Auditor agent present in creview-spec SKILL.md"
else
  fail "R-001a" "Upgrade Compatibility Auditor agent not found in creview-spec SKILL.md"
fi

# R-001b: The 5-item checklist is present — check for key phrases from the checklist
# Item 1: "propagate" and "installation mechanism"
if grep -qi 'installation mechanism' "$CREVIEW_SPEC_SKILL"; then
  pass "R-001b" "Checklist item 1 (installation mechanism) present in creview-spec"
else
  fail "R-001b" "Checklist item 1 (installation mechanism) not found in creview-spec"
fi

# R-001c: Item 2: "config keys" and "defaults"
if grep -qi 'config keys' "$CREVIEW_SPEC_SKILL" && grep -qi 'defaults' "$CREVIEW_SPEC_SKILL"; then
  pass "R-001c" "Checklist item 2 (config keys / defaults) present in creview-spec"
else
  fail "R-001c" "Checklist item 2 (config keys / defaults) not found in creview-spec"
fi

# R-001d: Item 3: "backward compatibility"
if grep -qi 'backward compatibility' "$CREVIEW_SPEC_SKILL"; then
  pass "R-001d" "Checklist item 3 (backward compatibility) present in creview-spec"
else
  fail "R-001d" "Checklist item 3 (backward compatibility) not found in creview-spec"
fi

# R-001e: Item 4: "migration path"
if grep -qi 'migration path' "$CREVIEW_SPEC_SKILL"; then
  pass "R-001e" "Checklist item 4 (migration path) present in creview-spec"
else
  fail "R-001e" "Checklist item 4 (migration path) not found in creview-spec"
fi

# R-001f: Item 5: "graceful degradation"
if grep -qi 'graceful degradation' "$CREVIEW_SPEC_SKILL"; then
  pass "R-001f" "Checklist item 5 (graceful degradation) present in creview-spec"
else
  fail "R-001f" "Checklist item 5 (graceful degradation) not found in creview-spec"
fi

# R-001g: The prompt mentions "upgrade user" experience outcomes (error, silent degradation, crash)
if grep -qi 'upgrade.*user' "$CREVIEW_SPEC_SKILL" || grep -qi 'prior version' "$CREVIEW_SPEC_SKILL"; then
  pass "R-001g" "Upgrade user scenario framing present in creview-spec"
else
  fail "R-001g" "Upgrade user scenario framing not found in creview-spec"
fi

# ============================================================================
# R-002 [unit]: ctdd SKILL.md has upgrade compatibility mini-audit agent
# ============================================================================

section "R-002: ctdd has upgrade compatibility mini-audit agent"

# R-002a: The upgrade compatibility agent prompt exists in ctdd SKILL.md
if grep -qi 'upgrade compatibility' "$CTDD_SKILL"; then
  pass "R-002a" "Upgrade compatibility agent referenced in ctdd SKILL.md"
else
  fail "R-002a" "Upgrade compatibility agent not found in ctdd SKILL.md"
fi

# R-002b: The 5-item checklist is present — check for key phrase "install/setup mechanism"
if grep -qi 'install.*setup.*mechanism\|setup.*mechanism' "$CTDD_SKILL"; then
  pass "R-002b" "Checklist item 1 (install/setup mechanism) present in ctdd"
else
  fail "R-002b" "Checklist item 1 (install/setup mechanism) not found in ctdd"
fi

# R-002c: Item 2: "fallback defaults"
if grep -qi 'fallback defaults' "$CTDD_SKILL"; then
  pass "R-002c" "Checklist item 2 (fallback defaults) present in ctdd"
else
  fail "R-002c" "Checklist item 2 (fallback defaults) not found in ctdd"
fi

# R-002d: Item 3: "version markers" or "graceful parsing"
if grep -qi 'version markers\|graceful parsing' "$CTDD_SKILL"; then
  pass "R-002d" "Checklist item 3 (version markers / graceful parsing) present in ctdd"
else
  fail "R-002d" "Checklist item 3 (version markers / graceful parsing) not found in ctdd"
fi

# R-002e: Item 4: "migration paths" (removed/renamed files)
if grep -qi 'migration path' "$CTDD_SKILL"; then
  pass "R-002e" "Checklist item 4 (migration paths) present in ctdd"
else
  fail "R-002e" "Checklist item 4 (migration paths) not found in ctdd"
fi

# R-002f: Item 5: "degrade gracefully"
if grep -qi 'degrade gracefully' "$CTDD_SKILL"; then
  pass "R-002f" "Checklist item 5 (degrade gracefully) present in ctdd"
else
  fail "R-002f" "Checklist item 5 (degrade gracefully) not found in ctdd"
fi

# R-002g: The upgrade agent prompt describes checking implementation via diff
# The spec says: "mechanically check the implementation (git diff against base branch)"
# This must be in the upgrade agent section, distinct from the pre-existing git diff
# reference in Agent Context and Tools
if grep -qi 'mechanically check the implementation' "$CTDD_SKILL"; then
  pass "R-002g" "Mini-audit upgrade agent describes mechanical implementation check"
else
  fail "R-002g" "Mini-audit upgrade agent mechanical check description not found"
fi

# R-002h: The upgrade compatibility agent is described as a 4th specialist
# (alongside cross-component, hostile-input, resource-bounds)
if grep -qi '4th.*specialist\|fourth.*specialist\|4.*specialist agent\|four specialist' "$CTDD_SKILL"; then
  pass "R-002h" "Upgrade compatibility described as 4th specialist in ctdd"
else
  fail "R-002h" "Upgrade compatibility not described as 4th specialist in ctdd"
fi

# ============================================================================
# R-003 [unit]: LENS value "upgrade-compatibility" in finding format
# ============================================================================

section "R-003: LENS value upgrade-compatibility in finding format"

# R-003a: The LENS enum line includes upgrade-compatibility
if grep -q 'upgrade-compatibility' "$CTDD_SKILL"; then
  pass "R-003a" "upgrade-compatibility value present in ctdd SKILL.md"
else
  fail "R-003a" "upgrade-compatibility value not found in ctdd SKILL.md"
fi

# R-003b: The LENS line lists all four values together
if grep -qE 'cross-component.*hostile-input.*resource-bounds.*upgrade-compatibility|cross-component.*hostile-input.*upgrade-compatibility.*resource-bounds|upgrade-compatibility.*cross-component|LENS.*upgrade-compatibility' "$CTDD_SKILL"; then
  pass "R-003b" "upgrade-compatibility appears alongside other LENS values"
else
  fail "R-003b" "upgrade-compatibility not alongside other LENS values in finding format"
fi

# ============================================================================
# R-004 [unit]: Both prompts contain AP-024 and PMB-003
# ============================================================================

section "R-004: Both prompts reference AP-024 and PMB-003"

# R-004a: creview-spec contains AP-024
if grep -q 'AP-024' "$CREVIEW_SPEC_SKILL"; then
  pass "R-004a" "AP-024 present in creview-spec SKILL.md"
else
  fail "R-004a" "AP-024 not found in creview-spec SKILL.md"
fi

# R-004b: creview-spec contains PMB-003
if grep -q 'PMB-003' "$CREVIEW_SPEC_SKILL"; then
  pass "R-004b" "PMB-003 present in creview-spec SKILL.md"
else
  fail "R-004b" "PMB-003 not found in creview-spec SKILL.md"
fi

# R-004c: ctdd contains AP-024
if grep -q 'AP-024' "$CTDD_SKILL"; then
  pass "R-004c" "AP-024 present in ctdd SKILL.md"
else
  fail "R-004c" "AP-024 not found in ctdd SKILL.md"
fi

# R-004d: ctdd contains PMB-003
if grep -q 'PMB-003' "$CTDD_SKILL"; then
  pass "R-004d" "PMB-003 present in ctdd SKILL.md"
else
  fail "R-004d" "PMB-003 not found in ctdd SKILL.md"
fi

# ============================================================================
# R-005 [unit]: ctdd says "4 specialist agents" in mini-audit announcements
# ============================================================================

section "R-005: ctdd mini-audit agent count updated to 4"

# R-005a: Progress announcement says 4 specialist agents
if grep -qE 'spawning 4 specialist agents|4 specialist agents' "$CTDD_SKILL"; then
  pass "R-005a" "Progress announcement references 4 specialist agents"
else
  fail "R-005a" "Progress announcement does not reference 4 specialist agents"
fi

# R-005b: "Each mini-audit round spawns four specialist agents" (or "4 specialist agents")
if grep -qE 'spawns four specialist agents|spawns 4 specialist agents' "$CTDD_SKILL"; then
  pass "R-005b" "Agent prompt section references four/4 specialist agents"
else
  fail "R-005b" "Agent prompt section still references three/3 specialist agents"
fi

# R-005c: The agent_role enum includes upgrade-compatibility
if grep -qE 'agent_role.*upgrade-compatibility' "$CTDD_SKILL"; then
  pass "R-005c" "agent_role enum includes upgrade-compatibility in ctdd SKILL.md"
else
  fail "R-005c" "agent_role enum does not include upgrade-compatibility in ctdd SKILL.md"
fi

# R-005d: The progress announcement lists upgrade-compatibility as a lens name
if grep -qi 'cross-component.*hostile.input.*resource.bounds.*upgrade.compatibility\|upgrade.compatibility.*cross-component' "$CTDD_SKILL"; then
  pass "R-005d" "Progress announcement lists upgrade compatibility as a lens"
else
  fail "R-005d" "Progress announcement does not list upgrade compatibility as a lens"
fi

# ============================================================================
# R-006 [unit]: creview-spec count references updated from 4 to 5
# ============================================================================

section "R-006: creview-spec agent count updated to 5"

# R-006a: "Spawns 5 adversarial agents" (was 4)
if grep -qE 'Spawns 5 adversarial agents' "$CREVIEW_SPEC_SKILL"; then
  pass "R-006a" "'Spawns 5 adversarial agents' present in creview-spec"
else
  fail "R-006a" "'Spawns 5 adversarial agents' not found (still says 4?)"
fi

# R-006b: "Spawning 5 adversarial agents in parallel" (was 4)
if grep -qE 'Spawning 5 adversarial agents in parallel' "$CREVIEW_SPEC_SKILL"; then
  pass "R-006b" "'Spawning 5 adversarial agents in parallel' present"
else
  fail "R-006b" "'Spawning 5 adversarial agents in parallel' not found (still says 4?)"
fi

# R-006c: "spawn all five" at high/critical (was "spawn all four")
if grep -qi 'spawn all five' "$CREVIEW_SPEC_SKILL"; then
  pass "R-006c" "'spawn all five' at high+ intensity present"
else
  fail "R-006c" "'spawn all five' not found (still says 'spawn all four'?)"
fi

# R-006d: Upgrade Compatibility Auditor appears as a numbered task list item
if grep -qE '^\s*[0-9]+\.\s*Upgrade Compatibility' "$CREVIEW_SPEC_SKILL"; then
  pass "R-006d" "Upgrade Compatibility Auditor in numbered task list"
else
  fail "R-006d" "Upgrade Compatibility Auditor not in numbered task list"
fi

# R-006e: "Present to Human" category list has upgrade compatibility findings
if grep -qi 'upgrade.compatibility.*finding\|upgrade.*finding' "$CREVIEW_SPEC_SKILL"; then
  pass "R-006e" "Upgrade compatibility findings in Present to Human category list"
else
  fail "R-006e" "Upgrade compatibility findings not in Present to Human categories"
fi

# R-006f: checkpoint completed_phases JSON includes upgrade-compatibility
if grep -qE 'completed_phases.*upgrade-compatibility' "$CREVIEW_SPEC_SKILL"; then
  pass "R-006f" "upgrade-compatibility in checkpoint completed_phases"
else
  fail "R-006f" "upgrade-compatibility not in checkpoint completed_phases JSON"
fi

# R-006g: token tracking agent_role includes upgrade-compatibility
if grep -qE 'agent_role.*upgrade-compatibility' "$CREVIEW_SPEC_SKILL"; then
  pass "R-006g" "agent_role includes upgrade-compatibility in creview-spec"
else
  fail "R-006g" "agent_role does not include upgrade-compatibility in creview-spec"
fi

# R-006h: Standard intensity still says 3 agents (upgrade not spawned at standard)
if grep -qi 'standard.*3\|standard.*spawn.*3\|add red team' "$CREVIEW_SPEC_SKILL"; then
  pass "R-006h" "Standard intensity still references 3 agents"
else
  fail "R-006h" "Standard intensity agent count unclear"
fi

# ============================================================================
# R-007 [unit]: Token tracking agent_role conventions
# ============================================================================

section "R-007: Token tracking agent_role includes upgrade-compatibility"

# R-007a: Mini-audit token tracking agent_role includes upgrade-compatibility in ctdd
if grep -qE 'agent_role.*upgrade-compatibility' "$CTDD_SKILL"; then
  pass "R-007a" "Mini-audit token tracking has upgrade-compatibility agent_role"
else
  fail "R-007a" "Mini-audit token tracking missing upgrade-compatibility agent_role"
fi

# R-007b: The general agent_role enum also includes upgrade-compatibility
# (the one in the main Token Tracking section, not just the mini-audit one)
if grep -qE 'agent_role.*test-writer.*upgrade-compatibility|agent_role.*resource-bounds.*upgrade-compatibility' "$CTDD_SKILL"; then
  pass "R-007b" "General agent_role enum includes upgrade-compatibility"
else
  fail "R-007b" "General agent_role enum missing upgrade-compatibility"
fi

# ============================================================================
# R-008 [unit]: Mini-audit intensity table rounds unchanged
# ============================================================================

section "R-008: Mini-audit rounds table unchanged (1/2/3)"

# R-008a: Intensity table mini-audit row still shows 1|2|3
if sed -n '/^## Intensity Configuration/,/^## [^I]/p' "$CTDD_SKILL" | grep -qi 'Mini.audit' && \
   sed -n '/^## Intensity Configuration/,/^## [^I]/p' "$CTDD_SKILL" | grep -qE '1.*2.*3'; then
  pass "R-008a" "Intensity table still shows standard=1, high=2, critical=3"
else
  fail "R-008a" "Intensity table mini-audit rounds may have changed"
fi

# R-008b: "No Convergence" section still says fixed rounds
if grep -qi 'No Convergence' "$CTDD_SKILL" && grep -qi 'fixed.*round\|fixed.cost' "$CTDD_SKILL"; then
  pass "R-008b" "No-convergence constraint still present"
else
  fail "R-008b" "No-convergence constraint may have been changed"
fi

# R-008c: The "fixed rounds per intensity level (standard=1, high=2, critical=3)" text is intact
if grep -qE 'standard=1.*high=2.*critical=3|standard.*1.*high.*2.*critical.*3' "$CTDD_SKILL"; then
  pass "R-008c" "Fixed rounds (1/2/3) text intact"
else
  fail "R-008c" "Fixed rounds text may have changed"
fi

# ============================================================================
# Summary
# ============================================================================

summary "Upgrade Compatibility Lens"
