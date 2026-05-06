#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091,SC2016,SC2086
# Correctless — Structural Enforcement PAT Tests
#
# Enforces the structural-enforcement-pat spec rules (R-001..R-008).
# All rules are [unit] — structural grep-based content checks.
#
# Run from repo root: bash tests/test-structural-enforcement-pat.sh

source "$(dirname "${BASH_SOURCE[0]}")/test-helpers.sh"
set -f

# ============================================================================
# File paths
# ============================================================================

ARCH_FILE=".correctless/ARCHITECTURE.md"
CSPEC_SKILL="skills/cspec/SKILL.md"
CREVIEW_SPEC_SKILL="skills/creview-spec/SKILL.md"
SPEC_FULL="templates/spec-full.md"
SYNC_SH="sync.sh"

# ============================================================================
# R-001 [unit]: PAT-018 entry exists in ARCHITECTURE.md
# ============================================================================

section "R-001: PAT-018 entry exists in ARCHITECTURE.md"

# R-001a: PAT-018 heading exists
if grep -q '### PAT-018:' "$ARCH_FILE"; then
  pass "R-001a" "PAT-018 heading exists in ARCHITECTURE.md"
else
  fail "R-001a" "PAT-018 heading not found in ARCHITECTURE.md"
fi

# R-001b: Title contains "Structural enforcement over prompt-level instruction"
if grep -q 'PAT-018.*[Ss]tructural enforcement over prompt.level instruction' "$ARCH_FILE"; then
  pass "R-001b" "PAT-018 title matches expected text"
else
  fail "R-001b" "PAT-018 title does not contain 'Structural enforcement over prompt-level instruction'"
fi

# Helper: extract PAT-018 section body (handles being last ### before a ## heading)
PAT018_BODY=$(awk '/^### PAT-018:/{found=1} found && /^##[#]? [A-Z]/ && !/^### PAT-018:/{exit} found{print}' "$ARCH_FILE")

# R-001c: PAT-018 has a Rule field
if echo "$PAT018_BODY" | grep -q '^\- \*\*Rule\*\*:'; then
  pass "R-001c" "PAT-018 has a Rule field"
else
  fail "R-001c" "PAT-018 missing Rule field"
fi

# R-001d: PAT-018 has a Violated-when field
if echo "$PAT018_BODY" | grep -q '^\- \*\*Violated when\*\*:'; then
  pass "R-001d" "PAT-018 has a Violated-when field"
else
  fail "R-001d" "PAT-018 missing Violated-when field"
fi

# R-001e: PAT-018 has a Guards-against field
if echo "$PAT018_BODY" | grep -q '^\- \*\*Guards against\*\*:'; then
  pass "R-001e" "PAT-018 has a Guards-against field"
else
  fail "R-001e" "PAT-018 missing Guards-against field"
fi

# R-001f: PAT-018 has a Test field
if echo "$PAT018_BODY" | grep -q '^\- \*\*Test\*\*:'; then
  pass "R-001f" "PAT-018 has a Test field"
else
  fail "R-001f" "PAT-018 missing Test field"
fi

# ============================================================================
# R-002 [unit]: PAT-018 Rule field lists acceptable enforcement mechanisms
# ============================================================================

section "R-002: PAT-018 Rule field lists enforcement mechanisms"

# Reuse PAT018_BODY extracted above

# R-002a: allowed-tools restrictions
if echo "$PAT018_BODY" | grep -qi 'allowed.tools'; then
  pass "R-002a" "PAT-018 Rule mentions allowed-tools restrictions"
else
  fail "R-002a" "PAT-018 Rule does not mention allowed-tools restrictions"
fi

# R-002b: file permissions / sensitive-file-guard
if echo "$PAT018_BODY" | grep -qi 'sensitive.file.guard\|file permissions'; then
  pass "R-002b" "PAT-018 Rule mentions sensitive-file-guard / file permissions"
else
  fail "R-002b" "PAT-018 Rule does not mention sensitive-file-guard / file permissions"
fi

# R-002c: phase-transition gate preconditions
if echo "$PAT018_BODY" | grep -qi 'phase.transition.*gate\|gate.*precondition'; then
  pass "R-002c" "PAT-018 Rule mentions phase-transition gate preconditions"
else
  fail "R-002c" "PAT-018 Rule does not mention phase-transition gate preconditions"
fi

# R-002d: cryptographic verification / hashes
if echo "$PAT018_BODY" | grep -qi 'hash\|cryptographic'; then
  pass "R-002d" "PAT-018 Rule mentions cryptographic verification / hashes"
else
  fail "R-002d" "PAT-018 Rule does not mention cryptographic verification / hashes"
fi

# R-002e: static test assertions / CI
if echo "$PAT018_BODY" | grep -qi 'CI\|static test\|test assertion'; then
  pass "R-002e" "PAT-018 Rule mentions static test assertions in CI"
else
  fail "R-002e" "PAT-018 Rule does not mention static test assertions in CI"
fi

# R-002f: tool-pinning in plugin agent frontmatter
if echo "$PAT018_BODY" | grep -qi 'tool.pinning\|agent.*frontmatter\|plugin agent'; then
  pass "R-002f" "PAT-018 Rule mentions tool-pinning in plugin agent frontmatter"
else
  fail "R-002f" "PAT-018 Rule does not mention tool-pinning in plugin agent frontmatter"
fi

# ============================================================================
# R-003 [unit]: PAT-018 Guards-against references prompt-level-only class
# ============================================================================

section "R-003: PAT-018 Guards-against references prompt-level-only class"

# R-003a: Guards-against field references the class of findings where enforcement is prompt-level only
if echo "$PAT018_BODY" | grep -i 'Guards against' | grep -qi 'prompt.level'; then
  pass "R-003a" "PAT-018 Guards-against references prompt-level enforcement class"
else
  fail "R-003a" "PAT-018 Guards-against does not reference prompt-level enforcement class"
fi

# ============================================================================
# R-004 [unit]: cspec INV template includes Enforcement field
# ============================================================================

section "R-004: cspec INV template includes Enforcement field"

# R-004a: Enforcement field exists in the high+ intensity INV template
# The field should appear between "Violated when" and "Guards against"
if grep -q '\*\*Enforcement\*\*:' "$CSPEC_SKILL"; then
  pass "R-004a" "Enforcement field exists in cspec SKILL.md INV template"
else
  fail "R-004a" "Enforcement field not found in cspec SKILL.md INV template"
fi

# R-004b: Enforcement field appears after Violated-when and before Guards-against
# Extract the INV template section and check field ordering
INV_TEMPLATE=$(awk '/^### INV-001:/,/^### INV-002:|^## /' "$CSPEC_SKILL" | head -n -1)
VIOLATED_LINE=$(echo "$INV_TEMPLATE" | grep -n 'Violated when' | head -1 | cut -d: -f1)
ENFORCEMENT_LINE=$(echo "$INV_TEMPLATE" | grep -n 'Enforcement' | head -1 | cut -d: -f1)
GUARDS_LINE=$(echo "$INV_TEMPLATE" | grep -n 'Guards against' | head -1 | cut -d: -f1)

if [ -n "$VIOLATED_LINE" ] && [ -n "$ENFORCEMENT_LINE" ] && [ -n "$GUARDS_LINE" ]; then
  if [ "$VIOLATED_LINE" -lt "$ENFORCEMENT_LINE" ] && [ "$ENFORCEMENT_LINE" -lt "$GUARDS_LINE" ]; then
    pass "R-004b" "Enforcement field is between Violated-when and Guards-against"
  else
    fail "R-004b" "Enforcement field is not in the correct position (after Violated-when, before Guards-against)"
  fi
else
  fail "R-004b" "Could not find all three fields (Violated-when, Enforcement, Guards-against) in INV template"
fi

# ============================================================================
# R-005 [unit]: Enforcement field guidance lists PAT-018 mechanisms
# ============================================================================

section "R-005: Enforcement field guidance lists acceptable mechanisms"

# Extract the Enforcement field line from cspec SKILL.md for mechanism checks
ENFORCEMENT_LINE_CONTENT=$(grep '\*\*Enforcement\*\*:' "$CSPEC_SKILL")

# Check each mechanism category is listed in the Enforcement field guidance
check_enforcement_mechanism() {
  local id="$1" pattern="$2" label="$3"
  if echo "$ENFORCEMENT_LINE_CONTENT" | grep -qi "$pattern"; then
    pass "$id" "Enforcement guidance mentions $label"
  else
    fail "$id" "Enforcement guidance does not mention $label"
  fi
}

check_enforcement_mechanism "R-005a" 'allowed.tools'                       "allowed-tools"
check_enforcement_mechanism "R-005b" 'sensitive.file.guard'                "sensitive-file-guard"
check_enforcement_mechanism "R-005c" 'gate precondition'                   "gate precondition"
check_enforcement_mechanism "R-005d" 'hash verification'                   "hash verification"
check_enforcement_mechanism "R-005e" 'CI test assertion'                   "CI test assertion"
check_enforcement_mechanism "R-005f" 'tool.pinning\|agent tool.pinning'    "agent tool-pinning"
check_enforcement_mechanism "R-005g" 'prompt.level'                        "prompt-level as fallback"

# ============================================================================
# R-006 [unit]: creview-spec Design Contract Checker flags missing Enforcement
# ============================================================================

section "R-006: creview-spec Design Contract Checker flags missing Enforcement"

# R-006a: Design Contract Checker prompt mentions Enforcement field
DESIGN_CHECKER=$(awk '/^### 4\. Design Contract Checker/,/^### 5/' "$CREVIEW_SPEC_SKILL")
if echo "$DESIGN_CHECKER" | grep -qi 'Enforcement'; then
  pass "R-006a" "Design Contract Checker prompt mentions Enforcement field"
else
  fail "R-006a" "Design Contract Checker prompt does not mention Enforcement field"
fi

# R-006b: Design Contract Checker flags invariants where Enforcement is prompt-level or absent
if echo "$DESIGN_CHECKER" | grep -qi 'prompt.level\|absent'; then
  pass "R-006b" "Design Contract Checker flags prompt-level or absent Enforcement"
else
  fail "R-006b" "Design Contract Checker does not flag prompt-level or absent Enforcement"
fi

# R-006c: Design Contract Checker suggests structural mechanism from PAT-018
if echo "$DESIGN_CHECKER" | grep -qi 'PAT-018\|structural.*mechanism\|suggest.*structural'; then
  pass "R-006c" "Design Contract Checker references PAT-018 or suggests structural mechanism"
else
  fail "R-006c" "Design Contract Checker does not reference PAT-018 or suggest structural mechanism"
fi

# ============================================================================
# R-007 [unit]: spec-full.md template includes Enforcement field
# ============================================================================

section "R-007: spec-full.md template includes Enforcement field"

# R-007a: Enforcement field exists in the INV-xxx block of spec-full.md
if grep -q '\*\*Enforcement\*\*:' "$SPEC_FULL"; then
  pass "R-007a" "Enforcement field exists in spec-full.md INV-xxx template"
else
  fail "R-007a" "Enforcement field not found in spec-full.md INV-xxx template"
fi

# R-007b: Enforcement field position matches cspec SKILL.md template
# (should appear between Violated-when and Guards-against — but spec-full.md
# may not have Guards-against; check it's after Violated-when at minimum)
SPEC_FULL_INV=$(awk '/^### INV-001:/,/^### INV-002:|^## /' "$SPEC_FULL" | head -n -1)
SF_VIOLATED_LINE=$(echo "$SPEC_FULL_INV" | grep -n 'Violated when' | head -1 | cut -d: -f1)
SF_ENFORCEMENT_LINE=$(echo "$SPEC_FULL_INV" | grep -n 'Enforcement' | head -1 | cut -d: -f1)

if [ -n "$SF_VIOLATED_LINE" ] && [ -n "$SF_ENFORCEMENT_LINE" ]; then
  if [ "$SF_VIOLATED_LINE" -lt "$SF_ENFORCEMENT_LINE" ]; then
    pass "R-007b" "Enforcement field appears after Violated-when in spec-full.md"
  else
    fail "R-007b" "Enforcement field does not appear after Violated-when in spec-full.md"
  fi
else
  fail "R-007b" "Could not find Violated-when and/or Enforcement in spec-full.md INV template"
fi

# ============================================================================
# R-008 [unit]: sync.sh propagates modified skill files
# ============================================================================

section "R-008: sync.sh propagates modified skill files"

# R-008a: sync.sh copies cspec skill
if grep -q 'cspec' "$SYNC_SH"; then
  pass "R-008a" "sync.sh references cspec skill"
else
  fail "R-008a" "sync.sh does not reference cspec skill"
fi

# R-008b: sync.sh copies creview-spec skill
if grep -q 'creview-spec' "$SYNC_SH"; then
  pass "R-008b" "sync.sh references creview-spec skill"
else
  fail "R-008b" "sync.sh does not reference creview-spec skill"
fi

# R-008c: sync.sh copies templates
if grep -q 'templates' "$SYNC_SH"; then
  pass "R-008c" "sync.sh references templates directory"
else
  fail "R-008c" "sync.sh does not reference templates directory"
fi

# ============================================================================
# Summary
# ============================================================================

summary "structural-enforcement-pat"
