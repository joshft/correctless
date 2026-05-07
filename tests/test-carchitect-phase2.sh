#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091,SC2016,SC2086
# Correctless — /carchitect Phase 2 Structural Tests
#
# Enforces the carchitect-phase2-spec-awareness spec rules (R-001..R-012).
# Tests are structural — they verify prompt text in skills/cspec/SKILL.md
# and skills/creview-spec/SKILL.md. All rules are prompt-level enforcement;
# tests verify the mechanical envelope: required prompt phrases, section
# headings, and instruction references.
#
# Run from repo root: bash tests/test-carchitect-phase2.sh

source "$(dirname "${BASH_SOURCE[0]}")/test-helpers.sh"
set -f

# ============================================================================
# File paths
# ============================================================================

CSPEC_SKILL="skills/cspec/SKILL.md"
CSPEC_DIST="correctless/skills/cspec/SKILL.md"
CREVIEW_SPEC_SKILL="skills/creview-spec/SKILL.md"
CREVIEW_SPEC_DIST="correctless/skills/creview-spec/SKILL.md"

# ============================================================================
# R-001 [unit]: /cspec Step 1 (high+) includes TB-xxx scope matching substep
# ============================================================================

section "R-001: /cspec Step 1 includes TB-xxx scope matching"

# R-001a: cspec SKILL.md contains a TB-xxx scope matching instruction
if grep -qi 'TB-xxx scope matching\|TB.*scope.*match' "$CSPEC_SKILL"; then
  pass "R-001a" "cspec SKILL.md contains TB-xxx scope matching instruction"
else
  fail "R-001a" "cspec SKILL.md missing TB-xxx scope matching instruction"
fi

# R-001b: The instruction references extracting/scanning TB-xxx entries by heading pattern
if grep -qi 'extracts.*TB-xxx entries\|scanning for.*TB-.*heading\|extract all TB-xxx' "$CSPEC_SKILL"; then
  pass "R-001b" "cspec SKILL.md references extracting TB-xxx entries by heading pattern"
else
  fail "R-001b" "cspec SKILL.md missing TB-xxx entry extraction reference"
fi

# R-001c: The instruction references the heading pattern ### TB-\d{3}:
if grep -q 'TB-.*heading\|### TB-' "$CSPEC_SKILL"; then
  pass "R-001c" "cspec SKILL.md references TB heading pattern"
else
  fail "R-001c" "cspec SKILL.md missing TB heading pattern reference"
fi

# R-001d: The instruction specifies high+ intensity gate for TB matching
if grep -qi 'high.*intensity.*TB\|TB.*high.*intensity\|At high.*TB' "$CSPEC_SKILL"; then
  pass "R-001d" "cspec SKILL.md gates TB matching at high+ intensity"
else
  fail "R-001d" "cspec SKILL.md missing high+ intensity gate for TB matching"
fi

# ============================================================================
# R-002 [unit]: TB-xxx matching produces list for spec author confirmation
# ============================================================================

section "R-002: TB matching produces list for human confirmation"

# R-002a: Instruction mentions presenting relevant TBs to the spec author
if grep -qi 'relevant.*TB.*present\|present.*relevant.*TB\|confirm.*TB\|TB.*confirm' "$CSPEC_SKILL"; then
  pass "R-002a" "cspec SKILL.md instructs presenting relevant TBs for confirmation"
else
  fail "R-002a" "cspec SKILL.md missing TB presentation/confirmation instruction"
fi

# R-002b: Instruction mentions showing TB name, boundary description, and invariant
if grep -qi 'TB.*name.*boundary.*description\|TB.*name.*description.*invariant\|each TB.*name.*invariant' "$CSPEC_SKILL"; then
  pass "R-002b" "cspec SKILL.md instructs showing TB name/description/invariant"
else
  fail "R-002b" "cspec SKILL.md missing TB name/description/invariant display instruction"
fi

# R-002c: Instruction mentions human confirms or corrects the TB list specifically
if grep -qi 'spec author confirms or corrects.*TB\|confirms or corrects the.*list.*before\|spec author.*confirm.*correct.*TB' "$CSPEC_SKILL"; then
  pass "R-002c" "cspec SKILL.md instructs human to confirm or correct TB list"
else
  fail "R-002c" "cspec SKILL.md missing human correction instruction for TB list"
fi

# ============================================================================
# R-003 [unit]: Per-TB security questions from documented invariant
# ============================================================================

section "R-003: Per-TB security questions from documented invariant"

# R-003a: Instruction references generating security questions per confirmed TB
if grep -qi 'security question.*TB\|TB.*security question\|per.*TB.*question\|question.*derived.*TB' "$CSPEC_SKILL"; then
  pass "R-003a" "cspec SKILL.md instructs generating security questions per TB"
else
  fail "R-003a" "cspec SKILL.md missing per-TB security question instruction"
fi

# R-003b: Instruction references TB's invariant and "violated when" field
if grep -qi 'violated when.*field\|invariant.*violated.*when\|TB.*invariant.*violated' "$CSPEC_SKILL"; then
  pass "R-003b" "cspec SKILL.md references TB invariant and violated-when field"
else
  fail "R-003b" "cspec SKILL.md missing TB invariant/violated-when reference"
fi

# R-003c: Instruction says questions derive from TB, not generic keywords
if grep -qi 'not.*generic.*keyword\|not from generic\|derived from.*TB.*invariant\|from that TB' "$CSPEC_SKILL"; then
  pass "R-003c" "cspec SKILL.md specifies questions derive from TB, not keywords"
else
  fail "R-003c" "cspec SKILL.md missing non-generic-keyword derivation instruction"
fi

# ============================================================================
# R-004 [unit]: STRIDE runs per confirmed TB-xxx, not per inferred boundary
# ============================================================================

section "R-004: STRIDE runs per confirmed TB-xxx"

# R-004a: STRIDE section references running per confirmed relevant TB-xxx
if grep -qi 'STRIDE.*per.*TB\|per.*TB.*STRIDE\|STRIDE.*confirmed.*TB\|STRIDE for TB-xxx' "$CSPEC_SKILL"; then
  pass "R-004a" "cspec SKILL.md instructs STRIDE per confirmed TB-xxx"
else
  fail "R-004a" "cspec SKILL.md missing per-TB STRIDE instruction"
fi

# R-004b: STRIDE section header format references TB-xxx ID
if grep -q 'STRIDE.*TB-xxx\|TB-xxx.*STRIDE\|### STRIDE for TB-' "$CSPEC_SKILL"; then
  pass "R-004b" "cspec SKILL.md STRIDE section references TB-xxx in headers"
else
  fail "R-004b" "cspec SKILL.md STRIDE section missing TB-xxx header reference"
fi

# R-004c: STRIDE instruction says "not per inferred boundary"
if grep -qi 'not per inferred boundary\|not.*inferred.*boundary\|confirmed relevant TB.*not.*inferred' "$CSPEC_SKILL"; then
  pass "R-004c" "cspec SKILL.md distinguishes confirmed TB from inferred boundary"
else
  fail "R-004c" "cspec SKILL.md missing confirmed-vs-inferred boundary distinction"
fi

# ============================================================================
# R-005 [unit]: Warning when TB-xxx overlaps scope but no invariant references it
# ============================================================================

section "R-005: Warning when TB-xxx overlaps but no invariant references it"

# R-005a: Warning text contains the specific advisory message
if grep -qi 'overlaps.*scope.*but no invariant\|TB-xxx.*overlaps.*scope.*no invariant\|overlaps with this feature' "$CSPEC_SKILL"; then
  pass "R-005a" "cspec SKILL.md contains TB overlap warning instruction"
else
  fail "R-005a" "cspec SKILL.md missing TB overlap warning instruction"
fi

# R-005b: Warning asks whether the omission is intentional
if grep -qi 'is this intentional\|intentional' "$CSPEC_SKILL"; then
  pass "R-005b" "cspec SKILL.md asks whether TB omission is intentional"
else
  fail "R-005b" "cspec SKILL.md missing intentionality question for TB omission"
fi

# ============================================================================
# R-006 [unit]: Pattern detection extracts PAT-xxx and checks for new conventions
# ============================================================================

section "R-006: Pattern detection extracts PAT-xxx entries"

# R-006a: Instruction references pattern detection substep in Step 3
if grep -qi 'pattern detection.*substep\|pattern detection.*PAT-xxx\|pattern detection.*Step 3' "$CSPEC_SKILL"; then
  pass "R-006a" "cspec SKILL.md contains pattern detection instruction"
else
  fail "R-006a" "cspec SKILL.md missing pattern detection instruction"
fi

# R-006b: Instruction references extracting PAT-xxx entries from ARCHITECTURE.md
if grep -qi 'PAT-xxx.*ARCHITECTURE.md\|extract.*PAT-.*entries\|scan.*PAT-\|PAT-.*heading' "$CSPEC_SKILL"; then
  pass "R-006b" "cspec SKILL.md references extracting PAT-xxx entries"
else
  fail "R-006b" "cspec SKILL.md missing PAT-xxx entry extraction reference"
fi

# R-006c: The instruction references the heading pattern ### PAT-\d{3}:
if grep -q '### PAT-' "$CSPEC_SKILL"; then
  pass "R-006c" "cspec SKILL.md references PAT heading pattern"
else
  fail "R-006c" "cspec SKILL.md missing PAT heading pattern reference"
fi

# R-006d: Pattern detection applies at all intensities (not gated to high+)
if grep -qi 'all intensities.*pattern\|pattern.*all intensities\|At all intensities.*pattern detect' "$CSPEC_SKILL"; then
  pass "R-006d" "cspec SKILL.md specifies pattern detection at all intensities"
else
  fail "R-006d" "cspec SKILL.md missing all-intensity scope for pattern detection"
fi

# ============================================================================
# R-007 [unit]: Present potential new pattern to spec author
# ============================================================================

section "R-007: Present potential new pattern to spec author"

# R-007a: Instruction references presenting new pattern to human
if grep -qi 'introduces a convention\|new.*pattern.*present\|not covered by.*PAT\|No existing PAT-xxx covers' "$CSPEC_SKILL"; then
  pass "R-007a" "cspec SKILL.md instructs presenting new pattern to human"
else
  fail "R-007a" "cspec SKILL.md missing new-pattern presentation instruction"
fi

# R-007b: Instruction suggests flagging for /cupdate-arch
if grep -qi 'cupdate-arch.*after\|flag.*cupdate-arch\|/cupdate-arch' "$CSPEC_SKILL"; then
  pass "R-007b" "cspec SKILL.md suggests flagging for /cupdate-arch"
else
  fail "R-007b" "cspec SKILL.md missing /cupdate-arch flagging suggestion"
fi

# ============================================================================
# R-008 [unit]: Pattern composition check at high+ intensity
# ============================================================================

section "R-008: Pattern composition check at high+"

# R-008a: Instruction references pattern composition check
if grep -qi 'pattern composition\|composition check\|compose.*existing.*PAT\|contradict.*PAT\|conflict.*PAT\|duplicate.*PAT' "$CSPEC_SKILL"; then
  pass "R-008a" "cspec SKILL.md contains pattern composition check instruction"
else
  fail "R-008a" "cspec SKILL.md missing pattern composition check instruction"
fi

# R-008b: Instruction gates composition check at high+ intensity
if grep -qi 'high.*intensity.*composition\|composition.*high.*intensity\|At high.*composition\|high.*pattern composition' "$CSPEC_SKILL"; then
  pass "R-008b" "cspec SKILL.md gates composition check at high+ intensity"
else
  fail "R-008b" "cspec SKILL.md missing high+ intensity gate for composition check"
fi

# R-008c: Instruction says to cite the specific conflicting PAT-xxx ID
if grep -qi 'citing.*PAT\|cite.*PAT.*ID\|specific PAT-xxx\|PAT-xxx ID.*conflict' "$CSPEC_SKILL"; then
  pass "R-008c" "cspec SKILL.md instructs citing specific PAT-xxx in conflicts"
else
  fail "R-008c" "cspec SKILL.md missing instruction to cite PAT-xxx ID in conflicts"
fi

# ============================================================================
# R-009 [unit]: /creview-spec Design Contract Checker cross-references TB-xxx
# ============================================================================

section "R-009: Design Contract Checker cross-references TB-xxx"

# R-009a: creview-spec Design Contract Checker prompt includes TB cross-reference
if grep -qi 'TB-xxx.*cross-reference\|cross-reference.*TB\|TB.*coverage.*spec\|spec.*TB.*coverage' "$CREVIEW_SPEC_SKILL"; then
  pass "R-009a" "creview-spec Design Contract Checker includes TB cross-reference"
else
  fail "R-009a" "creview-spec Design Contract Checker missing TB cross-reference"
fi

# R-009b: Design Contract Checker checks for relevant but unreferenced TB-xxx
if grep -qi 'relevant.*TB.*not reference\|TB.*spec does not reference\|flag.*TB.*not.*reference' "$CREVIEW_SPEC_SKILL"; then
  pass "R-009b" "Design Contract Checker flags unreferenced relevant TB-xxx"
else
  fail "R-009b" "Design Contract Checker missing unreferenced TB-xxx check"
fi

# ============================================================================
# R-010 [unit]: TB matching uses file-scope overlap as primary strategy
# ============================================================================

section "R-010: TB matching uses file-scope overlap as primary strategy"

# R-010a: Instruction references file-scope overlap
if grep -qi 'file-scope overlap\|file scope.*overlap\|file.*scope.*primary' "$CSPEC_SKILL"; then
  pass "R-010a" "cspec SKILL.md references file-scope overlap strategy"
else
  fail "R-010a" "cspec SKILL.md missing file-scope overlap strategy reference"
fi

# R-010b: Instruction mentions fallback to keyword matching when no file refs exist
if grep -qi 'fallback.*keyword\|keyword.*fallback\|fall.*back.*keyword' "$CSPEC_SKILL"; then
  pass "R-010b" "cspec SKILL.md mentions keyword fallback strategy"
else
  fail "R-010b" "cspec SKILL.md missing keyword fallback strategy"
fi

# R-010c: Instruction specifies when fallback triggers — no file path references
if grep -qi 'does not contain file path\|no file path reference\|without.*file path\|not contain file.*path' "$CSPEC_SKILL"; then
  pass "R-010c" "cspec SKILL.md specifies keyword fallback trigger condition"
else
  fail "R-010c" "cspec SKILL.md missing keyword fallback trigger condition"
fi

# ============================================================================
# R-011 [unit]: Dormant TB matching when no TB-xxx entries exist
# ============================================================================

section "R-011: Dormant TB matching when no TB-xxx entries"

# R-011a: Instruction describes dormant TB matching when no TB-xxx headings exist
if grep -qi 'no TB-xxx entries.*in ARCHITECTURE.*dormant\|no headings matching.*TB.*dormant\|TB matching step is dormant' "$CSPEC_SKILL"; then
  pass "R-011a" "cspec SKILL.md describes dormant behavior when no TB entries"
else
  fail "R-011a" "cspec SKILL.md missing dormant TB matching behavior"
fi

# R-011b: Instruction says TB matching proceeds without TB-grounded questions
if grep -qi 'without TB-grounded questions\|proceeds without TB\|cspec proceeds without TB' "$CSPEC_SKILL"; then
  pass "R-011b" "cspec SKILL.md specifies proceeding without TB-grounded questions"
else
  fail "R-011b" "cspec SKILL.md missing proceed-without-TB-questions instruction"
fi

# R-011c: Missing section headers treated same as empty sections
if grep -qi 'Missing section headers.*treated.*identically\|missing.*headers.*treated.*empty\|identically to empty sections' "$CSPEC_SKILL"; then
  pass "R-011c" "cspec SKILL.md treats missing headers same as empty sections"
else
  fail "R-011c" "cspec SKILL.md missing missing-headers-equals-empty-sections clause"
fi

# ============================================================================
# R-012 [unit]: Dormant pattern detection when no PAT-xxx entries exist
# ============================================================================

section "R-012: Dormant pattern detection when no PAT-xxx entries"

# R-012a: Instruction describes dormant behavior when no PAT-xxx entries
if grep -qi 'no PAT-xxx.*dormant\|dormant.*no PAT\|no.*PAT.*entries.*dormant\|no headings matching.*PAT' "$CSPEC_SKILL"; then
  pass "R-012a" "cspec SKILL.md describes dormant behavior when no PAT entries"
else
  fail "R-012a" "cspec SKILL.md missing dormant PAT detection behavior"
fi

# R-012b: Pattern detection and composition checking both dormant
if grep -qi 'pattern detection.*composition.*dormant\|composition.*checking.*dormant\|detection and composition.*dormant' "$CSPEC_SKILL"; then
  pass "R-012b" "cspec SKILL.md specifies both pattern detection and composition dormant"
else
  fail "R-012b" "cspec SKILL.md missing combined dormant clause for detection+composition"
fi

# ============================================================================
# Sync parity: source and distribution files match
# ============================================================================

section "Sync parity: source and distribution match"

if [ -f "$CSPEC_DIST" ]; then
  if diff -q "$CSPEC_SKILL" "$CSPEC_DIST" > /dev/null 2>&1; then
    pass "SYNC-001" "cspec source and distribution match"
  else
    fail "SYNC-001" "cspec source and distribution differ — run sync.sh"
  fi
else
  skip "SYNC-001" "cspec distribution file not found"
fi

if [ -f "$CREVIEW_SPEC_DIST" ]; then
  if diff -q "$CREVIEW_SPEC_SKILL" "$CREVIEW_SPEC_DIST" > /dev/null 2>&1; then
    pass "SYNC-002" "creview-spec source and distribution match"
  else
    fail "SYNC-002" "creview-spec source and distribution differ — run sync.sh"
  fi
else
  skip "SYNC-002" "creview-spec distribution file not found"
fi

# ============================================================================
# Summary
# ============================================================================

summary "carchitect-phase2-spec-awareness"
