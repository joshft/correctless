#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091,SC2016,SC2086
# Correctless — QA Severity Calibration Tests
#
# Enforces the qa-severity-calibration spec rules (INV-001..INV-013, PRH-001..PRH-002).
# Tests are structural — they verify prompt content in SKILL.md files,
# orchestrator instructions, schema documentation, antipattern entries,
# and learning entries.
#
# Run from repo root: bash tests/test-qa-severity-calibration.sh

source "$(dirname "${BASH_SOURCE[0]}")/test-helpers.sh"
set -f

# ============================================================================
# File paths
# ============================================================================

CTDD_SKILL="skills/ctdd/SKILL.md"
CVERIFY_SKILL="skills/cverify/SKILL.md"
CMETRICS_SKILL="skills/cmetrics/SKILL.md"
ANTIPATTERNS=".correctless/antipatterns.md"
CLAUDE_MD="CLAUDE.md"
ARCHITECTURE=".correctless/ARCHITECTURE.md"

# ============================================================================
# Helper: extract QA agent prompt section from ctdd SKILL.md
# The QA agent prompt is the blockquoted section starting with
# "You are the QA agent" inside "## Phase: QA (tdd-qa)"
# ============================================================================

qa_agent_section() {
  awk '
    /^## Phase: QA \(tdd-qa\)/    { in_qa=1; next }
    in_qa && /^## /               { exit }
    in_qa                         { print }
  ' "$CTDD_SKILL"
}

# ============================================================================
# Helper: extract mini-audit agent prompt section from ctdd SKILL.md
# The mini-audit prompts are inside "## Phase: Mini-Audit (tdd-audit)"
# ============================================================================

mini_audit_section() {
  awk '
    /^## Phase: Mini-Audit \(tdd-audit\)/ { in_ma=1; next }
    in_ma && /^## [^#]/                    { exit }
    in_ma                                  { print }
  ' "$CTDD_SKILL"
}

# ============================================================================
# INV-001 [unit]: QA prompt contains severity calibration examples
# ============================================================================

section "INV-001: QA prompt contains severity calibration examples"

QA_SECTION="$(qa_agent_section)"

# INV-001a: BLOCKING calibration example — silent data corruption
if echo "$QA_SECTION" | grep -qi 'silent.*data.*corrupt\|data.*corrupt.*silent\|corrupt.*silent'; then
  pass "INV-001a" "QA prompt has BLOCKING calibration: silent data corruption"
else
  fail "INV-001a" "QA prompt missing BLOCKING calibration: silent data corruption"
fi

# INV-001b: BLOCKING calibration example — security bypass
if echo "$QA_SECTION" | grep -qi 'security.*bypass\|bypass.*security'; then
  pass "INV-001b" "QA prompt has BLOCKING calibration: security bypass"
else
  fail "INV-001b" "QA prompt missing BLOCKING calibration: security bypass"
fi

# INV-001c: BLOCKING calibration example — resource leak
if echo "$QA_SECTION" | grep -qi 'resource.*leak\|leak.*resource\|file.*handle.*leak\|connection.*leak\|goroutine.*leak'; then
  pass "INV-001c" "QA prompt has BLOCKING calibration: resource leak"
else
  fail "INV-001c" "QA prompt missing BLOCKING calibration: resource leak"
fi

# INV-001d: BLOCKING calibration example — mock gap hiding wiring failure
# Must appear in a calibration section, not just the existing mock-gap-analysis instruction
if echo "$QA_SECTION" | grep -qi 'BLOCKING.*mock.*gap.*wiring\|mock.*gap.*hid.*wiring.*BLOCKING'; then
  pass "INV-001d" "QA prompt has BLOCKING calibration: mock gap hiding wiring failure"
else
  fail "INV-001d" "QA prompt missing BLOCKING calibration: mock gap hiding wiring failure"
fi

# INV-001e: BLOCKING calibration example — test-routing (AP-016)
if echo "$QA_SECTION" | grep -qi 'test.routing\|AP-016'; then
  pass "INV-001e" "QA prompt has BLOCKING calibration: test-routing (AP-016)"
else
  fail "INV-001e" "QA prompt missing BLOCKING calibration: test-routing (AP-016)"
fi

# INV-001f: NON-BLOCKING calibration example — missing docs
if echo "$QA_SECTION" | grep -qi 'missing.*doc\|doc.*missing\|documentation.*absent'; then
  pass "INV-001f" "QA prompt has NON-BLOCKING calibration: missing docs"
else
  fail "INV-001f" "QA prompt missing NON-BLOCKING calibration: missing docs"
fi

# INV-001g: NON-BLOCKING calibration example — suboptimal error messages
if echo "$QA_SECTION" | grep -qi 'suboptimal.*error.*message\|error.*message.*suboptimal\|poor.*error.*message\|unhelpful.*error'; then
  pass "INV-001g" "QA prompt has NON-BLOCKING calibration: suboptimal error messages"
else
  fail "INV-001g" "QA prompt missing NON-BLOCKING calibration: suboptimal error messages"
fi

# INV-001h: NON-BLOCKING calibration example — style inconsistency
if echo "$QA_SECTION" | grep -qi 'style.*inconsistenc\|inconsistenc.*style\|naming.*inconsistenc\|formatting.*inconsistenc'; then
  pass "INV-001h" "QA prompt has NON-BLOCKING calibration: style inconsistency"
else
  fail "INV-001h" "QA prompt missing NON-BLOCKING calibration: style inconsistency"
fi

# ============================================================================
# INV-002 [unit]: QA prompt includes aggressive default directive
# ============================================================================

section "INV-002: QA prompt includes aggressive default directive"

# INV-002a: The directive text exists
if echo "$QA_SECTION" | grep -qi 'when in doubt.*rate BLOCKING\|when in doubt.*BLOCKING'; then
  pass "INV-002a" "QA prompt contains 'When in doubt, rate BLOCKING' directive"
else
  fail "INV-002a" "QA prompt missing 'When in doubt, rate BLOCKING' directive"
fi

# INV-002b: The directive is visually prominent (blockquote, bold, or its own paragraph)
# Check that it's on its own line or in a blockquote or bold
if echo "$QA_SECTION" | grep -E '^\*\*.*[Ww]hen in doubt.*BLOCKING|^>.*[Ww]hen in doubt.*BLOCKING|^[Ww]hen in doubt.*BLOCKING'; then
  pass "INV-002b" "Aggressive default directive is visually prominent"
else
  fail "INV-002b" "Aggressive default directive is not visually prominent (buried in paragraph)"
fi

# INV-002c: Cost-asymmetry rationale is present
if echo "$QA_SECTION" | grep -qi 'disputed.*BLOCKING.*cost.*one.*turn\|BLOCKING.*costs.*one.*conversation\|shipped.*bug.*costs.*postmortem\|cost.*asymmetr'; then
  pass "INV-002c" "Cost-asymmetry rationale is present near directive"
else
  fail "INV-002c" "Cost-asymmetry rationale missing — directive exists without justification"
fi

# ============================================================================
# INV-003 [unit]: Mini-audit prompts contain severity calibration examples
# ============================================================================

section "INV-003: Mini-audit prompts contain severity calibration examples"

MA_SECTION="$(mini_audit_section)"

# INV-003a: CRITICAL/HIGH calibration — silent data corruption
# Must appear in a calibration section (header mentions CRITICAL/HIGH + examples mention data corruption)
MA_HAS_CALIBRATION_SECTION=$(echo "$MA_SECTION" | grep -c 'Severity Calibration')
if [ "$MA_HAS_CALIBRATION_SECTION" -gt 0 ] && echo "$MA_SECTION" | grep -qi 'Silent data corruption'; then
  pass "INV-003a" "Mini-audit prompt has CRITICAL/HIGH calibration: silent data corruption"
else
  fail "INV-003a" "Mini-audit prompt missing CRITICAL/HIGH calibration: silent data corruption"
fi

# INV-003b: CRITICAL/HIGH calibration — security bypass
# Must be in the calibration section
if [ "$MA_HAS_CALIBRATION_SECTION" -gt 0 ] && echo "$MA_SECTION" | grep -qi 'Security bypass'; then
  pass "INV-003b" "Mini-audit prompt has CRITICAL/HIGH calibration: security bypass"
else
  fail "INV-003b" "Mini-audit prompt missing CRITICAL/HIGH calibration: security bypass"
fi

# INV-003c: CRITICAL/HIGH calibration — resource leak
# Must be in the calibration section
if [ "$MA_HAS_CALIBRATION_SECTION" -gt 0 ] && echo "$MA_SECTION" | grep -qi 'Resource leak'; then
  pass "INV-003c" "Mini-audit prompt has CRITICAL/HIGH calibration: resource leak"
else
  fail "INV-003c" "Mini-audit prompt missing CRITICAL/HIGH calibration: resource leak"
fi

# INV-003d: CRITICAL/HIGH calibration — trust boundary violation
if echo "$MA_SECTION" | grep -qi 'trust.*boundary.*violat\|violat.*trust.*boundary'; then
  pass "INV-003d" "Mini-audit prompt has CRITICAL/HIGH calibration: trust boundary violation"
else
  fail "INV-003d" "Mini-audit prompt missing CRITICAL/HIGH calibration: trust boundary violation"
fi

# INV-003e: CRITICAL/HIGH calibration — data loss
if echo "$MA_SECTION" | grep -qi 'data.*loss\|loss.*data'; then
  pass "INV-003e" "Mini-audit prompt has CRITICAL/HIGH calibration: data loss"
else
  fail "INV-003e" "Mini-audit prompt missing CRITICAL/HIGH calibration: data loss"
fi

# INV-003f: MEDIUM/LOW calibration — missing docs
if echo "$MA_SECTION" | grep -qi 'missing.*doc\|doc.*missing'; then
  pass "INV-003f" "Mini-audit prompt has MEDIUM/LOW calibration: missing docs"
else
  fail "INV-003f" "Mini-audit prompt missing MEDIUM/LOW calibration: missing docs"
fi

# INV-003g: MEDIUM/LOW calibration — suboptimal naming
if echo "$MA_SECTION" | grep -qi 'suboptimal.*naming\|naming.*suboptimal\|poor.*naming\|naming.*inconsistent'; then
  pass "INV-003g" "Mini-audit prompt has MEDIUM/LOW calibration: suboptimal naming"
else
  fail "INV-003g" "Mini-audit prompt missing MEDIUM/LOW calibration: suboptimal naming"
fi

# INV-003h: MEDIUM/LOW calibration — minor performance inefficiency
if echo "$MA_SECTION" | grep -qi 'performance.*inefficien\|minor.*performance\|inefficien.*performance'; then
  pass "INV-003h" "Mini-audit prompt has MEDIUM/LOW calibration: minor performance inefficiency"
else
  fail "INV-003h" "Mini-audit prompt missing MEDIUM/LOW calibration: minor performance inefficiency"
fi

# ============================================================================
# INV-004 [unit]: Mini-audit prompts include aggressive default directive
# ============================================================================

section "INV-004: Mini-audit prompts include aggressive default directive"

# INV-004a: The directive text exists
if echo "$MA_SECTION" | grep -qi 'when in doubt.*rate HIGH\|when in doubt.*HIGH'; then
  pass "INV-004a" "Mini-audit prompt contains 'When in doubt, rate HIGH' directive"
else
  fail "INV-004a" "Mini-audit prompt missing 'When in doubt, rate HIGH' directive"
fi

# INV-004b: The directive is visually prominent
if echo "$MA_SECTION" | grep -E '^\*\*.*[Ww]hen in doubt.*HIGH|^>.*[Ww]hen in doubt.*HIGH|^[Ww]hen in doubt.*HIGH'; then
  pass "INV-004b" "Mini-audit aggressive default directive is visually prominent"
else
  fail "INV-004b" "Mini-audit aggressive default directive is not visually prominent"
fi

# INV-004c: Cost-asymmetry rationale is present
if echo "$MA_SECTION" | grep -qi 'cost.*asymmetr\|disputed.*HIGH.*cost\|HIGH.*costs.*one.*conversation\|shipped.*bug.*costs.*postmortem'; then
  pass "INV-004c" "Mini-audit cost-asymmetry rationale is present"
else
  fail "INV-004c" "Mini-audit cost-asymmetry rationale missing"
fi

# ============================================================================
# INV-005 [unit]: Orchestrator severity floor check after QA
# ============================================================================

section "INV-005: Orchestrator severity floor check after QA"

# INV-005a: Severity floor check keyword list exists in QA section
# The canonical list: corrupt, silent, bypass, leak, security, data loss, zero value, uninitialized
if echo "$QA_SECTION" | grep -qi 'severity.*floor\|floor.*check'; then
  pass "INV-005a" "Severity floor check concept exists in QA section"
else
  fail "INV-005a" "Severity floor check missing from QA section"
fi

# INV-005b: Canonical keyword list is defined
# Check for the specific keywords named in the spec
FLOOR_KEYWORDS_FOUND=0
for kw in "corrupt" "silent" "bypass" "leak" "security" "data.loss" "zero.value" "uninitialized"; do
  if echo "$QA_SECTION" | grep -qi "$kw"; then
    FLOOR_KEYWORDS_FOUND=$((FLOOR_KEYWORDS_FOUND + 1))
  fi
done
if [ "$FLOOR_KEYWORDS_FOUND" -ge 6 ]; then
  pass "INV-005b" "At least 6/8 canonical floor check keywords present ($FLOOR_KEYWORDS_FOUND/8)"
else
  fail "INV-005b" "Only $FLOOR_KEYWORDS_FOUND/8 canonical floor check keywords found (need >= 6)"
fi

# INV-005c: Floor check warns user and presents re-rating options
# Must be in the context of a severity floor check, not just existing disposition
if echo "$QA_SECTION" | grep -qi 'floor.*check.*upgrade.*BLOCKING\|floor.*re-rat\|floor.*confirm.*NON-BLOCKING\|severity.*floor.*warn'; then
  pass "INV-005c" "Floor check presents re-rating options"
else
  fail "INV-005c" "Floor check missing re-rating options"
fi

# INV-005d: Floor check is labeled as secondary safety net
if echo "$QA_SECTION" | grep -qi 'secondary.*safety.*net\|safety.*net\|not.*primary.*fix\|primary.*fix.*calibration'; then
  pass "INV-005d" "Floor check labeled as secondary safety net"
else
  fail "INV-005d" "Floor check not labeled as secondary safety net"
fi

# ============================================================================
# INV-006 [unit]: Orchestrator severity floor check after mini-audit
# ============================================================================

section "INV-006: Orchestrator severity floor check after mini-audit"

# INV-006a: Severity floor check exists in mini-audit section
if echo "$MA_SECTION" | grep -qi 'severity.*floor\|floor.*check'; then
  pass "INV-006a" "Severity floor check exists in mini-audit section"
else
  fail "INV-006a" "Severity floor check missing from mini-audit section"
fi

# INV-006b: Mini-audit floor check references the QA-defined canonical list (not duplicating)
# It should say something like "same keyword list" or "canonical list" rather than re-listing
if echo "$MA_SECTION" | grep -qi 'canonical.*keyword\|same.*keyword.*list\|keyword.*list.*defined\|defined.*above\|defined.*in.*QA\|canonical.*list'; then
  pass "INV-006b" "Mini-audit floor check references canonical list (not duplicating)"
else
  fail "INV-006b" "Mini-audit floor check duplicates keywords or doesn't reference canonical list"
fi

# INV-006c: Mini-audit floor check presents upgrade to CRITICAL/HIGH options
if echo "$MA_SECTION" | grep -qi 'upgrade.*CRITICAL\|upgrade.*HIGH\|re-rat'; then
  pass "INV-006c" "Mini-audit floor check presents upgrade to CRITICAL/HIGH options"
else
  fail "INV-006c" "Mini-audit floor check missing upgrade to CRITICAL/HIGH options"
fi

# ============================================================================
# INV-007 [unit]: Severity floor check is documented as brittle
# ============================================================================

section "INV-007: Severity floor check is documented as brittle"

# INV-007a: False negatives caveat documented
if grep -qi 'false.*negative\|evasion\|avoid.*trigger.*word\|agent.*describe.*soft' "$CTDD_SKILL"; then
  pass "INV-007a" "False negatives caveat documented for floor check"
else
  fail "INV-007a" "False negatives caveat missing — floor check not documented as brittle"
fi

# INV-007b: False positives caveat documented
if grep -qi 'false.*positive\|positive.*context\|leak.*mitigation\|security.*configuration.*proper' "$CTDD_SKILL"; then
  pass "INV-007b" "False positives caveat documented for floor check"
else
  fail "INV-007b" "False positives caveat missing — floor check presented as reliable"
fi

# INV-007c: Primary fix is calibration examples (not the floor check)
if grep -qi 'calibration.*primary\|primary.*fix.*calibration\|cheap.*safety.*net\|secondary.*safety' "$CTDD_SKILL"; then
  pass "INV-007c" "Floor check documented as secondary — calibration is primary fix"
else
  fail "INV-007c" "Floor check framing doesn't identify calibration examples as primary fix"
fi

# ============================================================================
# INV-008 [unit]: Non-blocking finding disposition flow
# ============================================================================

section "INV-008: Non-blocking finding disposition flow"

# INV-008a: Disposition flow for NON-BLOCKING findings exists
if echo "$QA_SECTION" | grep -qi 'NON-BLOCKING.*disposition\|disposition.*NON-BLOCKING\|present.*NON-BLOCKING.*finding\|each NON-BLOCKING'; then
  pass "INV-008a" "Non-blocking disposition flow exists in QA section"
else
  fail "INV-008a" "Non-blocking disposition flow missing from QA section"
fi

# INV-008b: Disposition options include Fix now, Accept, Upgrade to BLOCKING
if echo "$QA_SECTION" | grep -qi 'Fix now' && \
   echo "$QA_SECTION" | grep -qi 'Accept' && \
   echo "$QA_SECTION" | grep -qi 'Upgrade.*BLOCKING\|upgrade.*BLOCKING'; then
  pass "INV-008b" "Disposition options present: Fix now, Accept, Upgrade to BLOCKING"
else
  fail "INV-008b" "Disposition options incomplete (need: Fix now, Accept, Upgrade to BLOCKING)"
fi

# INV-008c: Status field extended to include 'accepted'
if grep -qi '"status".*open.*fixed.*accepted\|status.*open|fixed|accepted\|open.*fixed.*accepted' "$CTDD_SKILL"; then
  pass "INV-008c" "Status field extended to include 'accepted'"
else
  fail "INV-008c" "Status field not extended to include 'accepted'"
fi

# INV-008d: No open NON-BLOCKING findings when advancing past QA
if echo "$QA_SECTION" | grep -qi 'no.*finding.*remain.*open\|no.*open.*finding.*advanc\|status.*open.*advanc\|must.*not.*advance.*open'; then
  pass "INV-008d" "Instruction prevents advancing past QA with open NON-BLOCKING findings"
else
  fail "INV-008d" "Missing instruction to prevent advancing with open NON-BLOCKING findings"
fi

# INV-008e: Backward compatibility note for 'accepted' status
if grep -qi 'backward.*compat\|unknown.*status.*open\|treat.*unknown.*open' "$CTDD_SKILL"; then
  pass "INV-008e" "Backward compatibility note for 'accepted' status present"
else
  fail "INV-008e" "Backward compatibility note for 'accepted' status missing"
fi

# ============================================================================
# INV-009 [unit]: Non-blocking mini-audit finding disposition flow
# ============================================================================

section "INV-009: Non-blocking mini-audit finding disposition flow"

# INV-009a: Disposition flow for MEDIUM/LOW mini-audit findings exists
# Must describe a disposition process (Fix now / Accept / Upgrade) for MEDIUM/LOW
# The existing "advisory" mention is not a disposition flow
if echo "$MA_SECTION" | grep -qi 'MEDIUM.*LOW.*disposition.*Fix.*Accept\|present.*each.*MEDIUM.*LOW\|each.*MEDIUM.*LOW.*finding.*disposition'; then
  pass "INV-009a" "Mini-audit disposition flow for MEDIUM/LOW exists"
else
  fail "INV-009a" "Mini-audit disposition flow for MEDIUM/LOW missing"
fi

# INV-009b: Disposition options include Fix now, Accept, Upgrade to HIGH
if echo "$MA_SECTION" | grep -qi 'Fix now' && \
   echo "$MA_SECTION" | grep -qi 'Accept' && \
   echo "$MA_SECTION" | grep -qi 'Upgrade.*HIGH\|upgrade.*HIGH'; then
  pass "INV-009b" "Mini-audit disposition options present: Fix now, Accept, Upgrade to HIGH"
else
  fail "INV-009b" "Mini-audit disposition options incomplete"
fi

# INV-009c: No open findings when advancing past mini-audit
if echo "$MA_SECTION" | grep -qi 'no.*finding.*remain.*open\|no.*open.*finding.*advanc\|status.*open.*done\|must.*not.*advance.*open'; then
  pass "INV-009c" "Instruction prevents advancing past mini-audit with open findings"
else
  fail "INV-009c" "Missing instruction to prevent advancing past mini-audit with open findings"
fi

# INV-009d: Same 'accepted' status mechanism as QA
# Must mention status: accepted in the context of mini-audit disposition
if echo "$MA_SECTION" | grep -qi 'status.*accepted.*mini-audit\|mini-audit.*status.*accepted\|disposition.*accepted.*status\|finding.*status.*accepted'; then
  pass "INV-009d" "Mini-audit disposition uses 'accepted' status"
else
  fail "INV-009d" "Mini-audit disposition missing 'accepted' status"
fi

# ============================================================================
# INV-010 [unit]: AP-028 antipattern entry exists
# ============================================================================

section "INV-010: AP-028 antipattern entry exists"

# INV-010a: AP-028 exists in antipatterns.md
if grep -q 'AP-028' "$ANTIPATTERNS"; then
  pass "INV-010a" "AP-028 exists in antipatterns.md"
else
  fail "INV-010a" "AP-028 missing from antipatterns.md"
fi

# INV-010b: AP-028 title references uncalibrated severity gate
if grep -qi 'AP-028.*[Uu]ncalibrated.*severity\|AP-028.*severity.*uncalibrated' "$ANTIPATTERNS"; then
  pass "INV-010b" "AP-028 title references uncalibrated severity gate"
else
  fail "INV-010b" "AP-028 title does not reference uncalibrated severity gate"
fi

# INV-010c: AP-028 has required fields (What went wrong, How to catch it, Frequency)
AP028_SECTION=$(awk '/### AP-028/,0' "$ANTIPATTERNS" | head -20)
if echo "$AP028_SECTION" | grep -qi 'What went wrong' && \
   echo "$AP028_SECTION" | grep -qi 'How to catch it' && \
   echo "$AP028_SECTION" | grep -qi 'Frequency'; then
  pass "INV-010c" "AP-028 has all required fields"
else
  fail "INV-010c" "AP-028 missing required fields (need: What went wrong, How to catch it, Frequency)"
fi

# ============================================================================
# INV-011 [unit]: PMB-007 learning entry exists
# ============================================================================

section "INV-011: PMB-007 learning entry exists"

# INV-011a: PMB-007 exists in CLAUDE.md
if grep -q 'PMB-007' "$CLAUDE_MD"; then
  pass "INV-011a" "PMB-007 exists in CLAUDE.md"
else
  fail "INV-011a" "PMB-007 missing from CLAUDE.md"
fi

# INV-011b: PMB-007 is in the Correctless Learnings section
LEARNINGS_SECTION=$(awk '/## Correctless Learnings/,/^## [^C]/' "$CLAUDE_MD")
if echo "$LEARNINGS_SECTION" | grep -q 'PMB-007'; then
  pass "INV-011b" "PMB-007 is in Correctless Learnings section"
else
  fail "INV-011b" "PMB-007 is not in Correctless Learnings section"
fi

# INV-011c: PMB-007 mentions severity calibration or uncalibrated severity
if grep -qi 'PMB-007.*severity\|PMB-007.*calibrat' "$CLAUDE_MD" || \
   (echo "$LEARNINGS_SECTION" | grep -A5 'PMB-007' | grep -qi 'severity\|calibrat'); then
  pass "INV-011c" "PMB-007 references severity calibration"
else
  fail "INV-011c" "PMB-007 does not reference severity calibration"
fi

# ============================================================================
# INV-012 [unit]: Calibration examples match across source and distribution
# ============================================================================

section "INV-012: Source and distribution match (sync.sh --check)"

# INV-012a: sync.sh --check passes for ctdd
if bash sync.sh --check 2>&1 | grep -qi 'in sync\|no drift\|clean\|identical\|up to date\|OK' || \
   bash sync.sh --check 2>&1; [ $? -eq 0 ]; then
  pass "INV-012a" "sync.sh --check passes (source and distribution in sync)"
else
  fail "INV-012a" "sync.sh --check fails (source and distribution out of sync)"
fi

# ============================================================================
# INV-013 [unit]: Fix-round loop activation tracking
# ============================================================================

section "INV-013: Fix-round loop activation tracking"

# Read cverify skill file
CVERIFY_CONTENT="$(cat "$CVERIFY_SKILL")"

# INV-013a: fix_rounds_triggered field documented in cverify calibration schema
if grep -qi 'fix_rounds_triggered' <<< "$CVERIFY_CONTENT"; then
  pass "INV-013a" "fix_rounds_triggered field in cverify calibration schema"
else
  fail "INV-013a" "fix_rounds_triggered field missing from cverify calibration schema"
fi

# INV-013b: cmetrics warns when fix_rounds_triggered is 0 across 3+ high+ features
CMETRICS_CONTENT="$(cat "$CMETRICS_SKILL")"
if grep -qi 'fix_rounds_triggered' <<< "$CMETRICS_CONTENT"; then
  pass "INV-013b" "cmetrics references fix_rounds_triggered"
else
  fail "INV-013b" "cmetrics does not reference fix_rounds_triggered"
fi

# INV-013c: cmetrics warning mentions 3+ consecutive high+ features
if grep -qi 'fix.*round.*loop.*not.*fired\|fix_rounds_triggered.*0.*3\|3.*consecutive.*high\|never.*fire' <<< "$CMETRICS_CONTENT"; then
  pass "INV-013c" "cmetrics warning for 0 fix rounds across 3+ high+ features"
else
  fail "INV-013c" "cmetrics missing warning for 0 fix rounds across 3+ features"
fi

# INV-013d: cmetrics listed as consumer of ABS-005 in ARCHITECTURE.md.
# ABS-005 body moved to the abstractions fragment (index+body-out fragmentation);
# heading stays in root.
if grep -q 'ABS-005' "$ARCHITECTURE" && \
   awk '/### ABS-005/,/### ABS-006/' "docs/architecture/abstractions.md" | grep -qi 'cmetrics'; then
  pass "INV-013d" "cmetrics listed as consumer of ABS-005 in ARCHITECTURE.md"
else
  fail "INV-013d" "cmetrics not listed as consumer of ABS-005 in ARCHITECTURE.md"
fi

# INV-013e: fix_rounds_triggered derivation formula documented in cverify
if grep -qi 'qa_rounds.*-.*1\|qa_rounds.*minus\|max.*0.*qa_rounds\|mini_audit_fix_rounds' <<< "$CVERIFY_CONTENT"; then
  pass "INV-013e" "fix_rounds_triggered derivation formula documented in cverify"
else
  fail "INV-013e" "fix_rounds_triggered derivation formula missing from cverify"
fi

# ============================================================================
# PRH-001 [unit]: No severity taxonomy changes
# ============================================================================

section "PRH-001: No severity taxonomy changes"

# PRH-001a: QA severity levels unchanged (BLOCKING|NON-BLOCKING|UNCERTAIN)
if echo "$QA_SECTION" | grep -q 'BLOCKING|NON-BLOCKING|UNCERTAIN'; then
  pass "PRH-001a" "QA severity taxonomy preserved: BLOCKING|NON-BLOCKING|UNCERTAIN"
else
  fail "PRH-001a" "QA severity taxonomy altered"
fi

# PRH-001b: Mini-audit severity levels unchanged (CRITICAL|HIGH|MEDIUM|LOW|UNCERTAIN)
if echo "$MA_SECTION" | grep -q 'CRITICAL|HIGH|MEDIUM|LOW|UNCERTAIN'; then
  pass "PRH-001b" "Mini-audit severity taxonomy preserved: CRITICAL|HIGH|MEDIUM|LOW|UNCERTAIN"
fi

# ============================================================================
# PRH-002 [unit]: No automated severity override
# ============================================================================

section "PRH-002: No automated severity override"

# PRH-002a: No auto-upgrade instruction in orchestrator
# The floor check must WARN and PRESENT options, not auto-upgrade
if grep -qi 'automatically.*upgrade.*severity\|auto.*upgrade.*finding\|auto.*re-rate' "$CTDD_SKILL"; then
  fail "PRH-002a" "Orchestrator contains automatic severity upgrade instruction"
else
  pass "PRH-002a" "No automatic severity override found in orchestrator instructions"
fi

# ============================================================================
# BND-004 [unit]: /cauto semi-auto mode disposition
# ============================================================================

section "BND-004: /cauto semi-auto mode disposition"

# BND-004a: ctdd skill mentions auto-acceptance for pipeline context
if grep -qi 'auto-accept.*pipeline\|pipeline.*auto-accept\|cauto.*auto-accept\|auto-accepted-pipeline' "$CTDD_SKILL"; then
  pass "BND-004a" "Auto-acceptance for /cauto pipeline context documented"
else
  fail "BND-004a" "Auto-acceptance for /cauto pipeline context not documented"
fi

# ============================================================================
# Summary
# ============================================================================

summary "QA Severity Calibration"
