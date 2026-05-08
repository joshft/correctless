#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091,SC2016,SC2086
# Correctless — /carchitect Phase 5 Architecture Maintenance Loop Tests
#
# Enforces the carchitect-phase-5-maintenance spec rules (R-001..R-012).
# Tests are structural — they verify prompt text in skills/cverify/SKILL.md,
# skills/cdocs/SKILL.md, and skills/cupdate-arch/SKILL.md. All rules are
# prompt-level enforcement; tests verify the mechanical envelope: required
# prompt phrases, section structure, format contracts, and doc references.
#
# Run from repo root: bash tests/test-carchitect-phase5.sh

source "$(dirname "${BASH_SOURCE[0]}")/test-helpers.sh"
set -f

# ============================================================================
# File paths
# ============================================================================

CVERIFY_SKILL="skills/cverify/SKILL.md"
CDOCS_SKILL="skills/cdocs/SKILL.md"
CUPDATE_ARCH_SKILL="skills/cupdate-arch/SKILL.md"
CVERIFY_DOCS="docs/skills/cverify.md"
CDOCS_DOCS="docs/skills/cdocs.md"
CUPDATE_ARCH_DOCS="docs/skills/cupdate-arch.md"
WORKFLOW_CONFIG=".correctless/config/workflow-config.json"

# ============================================================================
# R-001 [unit]: /cverify architecture adherence section replaces generic prose
# ============================================================================

section "R-001: /cverify architecture adherence section replaces generic prose"

# R-001a: Section 3 instructs extracting ABS-xxx, PAT-xxx, TB-xxx, ENV-xxx entries
if grep -qi 'ABS-xxx.*PAT-xxx.*TB-xxx.*ENV-xxx\|extract.*ABS.*PAT.*TB.*ENV\|ABS-xxx, PAT-xxx, TB-xxx, ENV-xxx' "$CVERIFY_SKILL"; then
  pass "R-001a" "Section 3 instructs extracting all four entry types"
else
  fail "R-001a" "Section 3 missing instruction to extract ABS/PAT/TB/ENV entries"
fi

# R-001b: Section 3 instructs using git diff to get changed files
if grep -qi 'git diff.*default_branch.*HEAD.*name-only\|git diff.*--name-only' "$CVERIFY_SKILL"; then
  pass "R-001b" "Section 3 instructs git diff for changed files"
else
  fail "R-001b" "Section 3 missing git diff instruction for changed files"
fi

# R-001c: Section 3 instructs identifying affected entries via path overlap
if grep -qi 'affected entries\|overlap.*changed files\|Enforced at.*paths.*modified\|paths.*overlap' "$CVERIFY_SKILL"; then
  pass "R-001c" "Section 3 instructs identifying affected entries via path overlap"
else
  fail "R-001c" "Section 3 missing affected-entry identification instruction"
fi

# R-001d: Section 3 instructs verifying Enforced at paths exist on disk
if grep -qi 'Enforced at.*paths.*exist\|verify.*Enforced at.*exist\|Enforced at.*on disk' "$CVERIFY_SKILL"; then
  pass "R-001d" "Section 3 instructs verifying Enforced at paths exist on disk"
else
  fail "R-001d" "Section 3 missing Enforced at path verification"
fi

# R-001e: Section 3 instructs verifying Test paths exist and reference entry ID
if grep -qi 'Test.*paths.*exist.*reference.*entry.*ID\|Test.*reference.*entry ID\|verify.*Test.*paths.*exist' "$CVERIFY_SKILL"; then
  pass "R-001e" "Section 3 instructs verifying Test paths reference entry ID"
else
  fail "R-001e" "Section 3 missing Test path verification instruction"
fi

# R-001f: Section 3 instructs checking Invariant text conflicts
if grep -qi 'Invariant.*text.*conflict\|Invariant.*conflict.*feature\|invariant.*conflicts.*changed' "$CVERIFY_SKILL"; then
  pass "R-001f" "Section 3 instructs checking Invariant text conflicts"
else
  fail "R-001f" "Section 3 missing Invariant conflict checking instruction"
fi

# R-001g: Section 3 specifies severity labels: path-missing=HIGH, test-ID-missing=MEDIUM,
#          invariant-conflict=MEDIUM, consumers-incomplete=LOW
if grep -qi 'path-missing.*HIGH' "$CVERIFY_SKILL"; then
  pass "R-001g-1" "path-missing severity is HIGH"
else
  fail "R-001g-1" "path-missing severity not specified as HIGH"
fi

if grep -qi 'test-ID-missing.*MEDIUM\|test.*missing.*MEDIUM' "$CVERIFY_SKILL"; then
  pass "R-001g-2" "test-ID-missing severity is MEDIUM"
else
  fail "R-001g-2" "test-ID-missing severity not specified as MEDIUM"
fi

if grep -qi 'invariant-conflict.*MEDIUM\|invariant.*conflict.*MEDIUM' "$CVERIFY_SKILL"; then
  pass "R-001g-3" "invariant-conflict severity is MEDIUM"
else
  fail "R-001g-3" "invariant-conflict severity not specified as MEDIUM"
fi

if grep -qi 'consumers-incomplete.*LOW\|consumers.*incomplete.*LOW' "$CVERIFY_SKILL"; then
  pass "R-001g-4" "consumers-incomplete severity is LOW"
else
  fail "R-001g-4" "consumers-incomplete severity not specified as LOW"
fi

# R-001h: Severity labels are advisory, not blocking (PRH-002)
if grep -qi 'advisory.*not.*gate\|advisory.*prioritization\|do not gate.*cverify\|non-blocking advisory' "$CVERIFY_SKILL"; then
  pass "R-001h" "Severity labels are advisory (non-blocking)"
else
  fail "R-001h" "Missing statement that severity labels are advisory/non-blocking"
fi

# R-001i: Path extraction guidance — strip parenthetical annotations and backtick formatting
if grep -qi 'strip.*parenthetical\|parenthetical annotations\|backtick formatting' "$CVERIFY_SKILL"; then
  pass "R-001i" "Path extraction guidance present (parenthetical/backtick)"
else
  fail "R-001i" "Missing path extraction guidance for parenthetical/backtick"
fi

# R-001j: Original 4 lines of generic prose must NOT appear
# The old section had "Does the implementation follow the patterns?" etc.
if grep -qi 'Does the implementation follow the patterns\|Error handling, validation, state management, naming conventions' "$CVERIFY_SKILL"; then
  fail "R-001j" "Old generic architecture prose still present in Section 3"
else
  pass "R-001j" "Old generic architecture prose removed from Section 3"
fi

# ============================================================================
# R-002 [unit]: /cverify drift-debt surfacing
# ============================================================================

section "R-002: /cverify drift-debt surfacing"

# R-002a: Section 3 instructs reading drift-debt.json
if grep -qi 'drift-debt.json' "$CVERIFY_SKILL"; then
  pass "R-002a" "Section 3 references drift-debt.json"
else
  fail "R-002a" "Section 3 missing drift-debt.json reference"
fi

# R-002b: drift-debt items surfaced when rule_id/description/spec_id references architecture entry
if grep -qi 'rule_id.*description.*spec_id.*architecture\|references.*architecture.*entry\|ABS.*PAT.*TB.*ENV.*drift-debt\|drift-debt.*ABS.*PAT.*TB.*ENV' "$CVERIFY_SKILL"; then
  pass "R-002b" "drift-debt items filtered by architecture entry reference"
else
  fail "R-002b" "Missing filter for drift-debt items by architecture entry"
fi

# R-002c: drift-debt items surfaced when description references changed files
if grep -qi 'drift-debt.*changed files\|description.*references.*files.*changed\|files changed.*drift-debt' "$CVERIFY_SKILL"; then
  pass "R-002c" "drift-debt items filtered by changed files reference"
else
  fail "R-002c" "Missing filter for drift-debt items by changed files"
fi

# R-002d: Dormant when drift-debt.json absent/empty/no open items (PAT-019)
if grep -qi 'drift-debt.*absent\|drift-debt.*empty\|drift-debt.*no open\|drift-debt.*dormant\|PAT-019.*drift-debt\|drift-debt.*PAT-019' "$CVERIFY_SKILL"; then
  pass "R-002d" "drift-debt surfacing is dormant when absent/empty (PAT-019)"
else
  fail "R-002d" "Missing dormant condition for drift-debt.json (PAT-019)"
fi

# ============================================================================
# R-003 [unit]: /cverify verification report architecture section
# ============================================================================

section "R-003: /cverify verification report architecture section"

# R-003a: Report template includes "## Architecture Adherence" heading
if grep -q '## Architecture Adherence' "$CVERIFY_SKILL"; then
  pass "R-003a" "Report template includes '## Architecture Adherence' heading"
else
  fail "R-003a" "Report template missing '## Architecture Adherence' heading"
fi

# R-003b: Per-entry line format: - {entry-ID}: {status} — {description}
if grep -qi '{entry-ID}.*{status}.*{.*description}\|entry-ID.*status.*description\|valid.*stale.*path-missing' "$CVERIFY_SKILL"; then
  pass "R-003b" "Report template includes per-entry line format"
else
  fail "R-003b" "Report template missing per-entry line format"
fi

# R-003c: Status values include valid, stale, path-missing
if grep -q 'valid' "$CVERIFY_SKILL" && grep -q 'stale' "$CVERIFY_SKILL" && grep -q 'path-missing' "$CVERIFY_SKILL"; then
  pass "R-003c" "Report template includes valid/stale/path-missing statuses"
else
  fail "R-003c" "Report template missing valid/stale/path-missing statuses"
fi

# R-003d: Drift Debt sub-section heading
if grep -q '### Drift Debt' "$CVERIFY_SKILL"; then
  pass "R-003d" "Report template includes '### Drift Debt' sub-section"
else
  fail "R-003d" "Report template missing '### Drift Debt' sub-section"
fi

# R-003e: Summary line format: {N} entries checked, {M} stale, {K} drift-debt items
if grep -qi 'entries checked.*stale.*drift-debt items\|{N} entries checked' "$CVERIFY_SKILL"; then
  pass "R-003e" "Report template includes summary line format"
else
  fail "R-003e" "Report template missing summary line format"
fi

# ============================================================================
# R-004 [unit]: /cdocs existing-entry staleness detection
# ============================================================================

section "R-004: /cdocs existing-entry staleness detection"

# R-004a: Section 5 instructs reading verification report's Architecture Adherence section
if grep -qi 'verification report.*Architecture Adherence\|Architecture Adherence.*verification report\|read.*verification report.*architecture\|Architecture Adherence.*section' "$CDOCS_SKILL"; then
  pass "R-004a" "Section 5 instructs reading verification report Architecture Adherence"
else
  fail "R-004a" "Section 5 missing verification report Architecture Adherence reference"
fi

# R-004b: Section 5 checks Enforced at paths modified by feature
if grep -qi 'Enforced at.*paths.*modified\|Enforced at.*modified.*feature\|paths.*modified.*feature' "$CDOCS_SKILL"; then
  pass "R-004b" "Section 5 checks Enforced at paths modified by feature"
else
  fail "R-004b" "Section 5 missing Enforced at path modification check"
fi

# R-004c: Section 5 presents stale entries one at a time with numbered options
if grep -qi 'one at a time\|one entry at a time\|present.*stale.*entries.*numbered' "$CDOCS_SKILL"; then
  pass "R-004c" "Section 5 presents stale entries one at a time"
else
  fail "R-004c" "Section 5 missing one-at-a-time presentation of stale entries"
fi

# R-004d: Disposition options include Update, Skip, Log as drift debt
if grep -q 'Update' "$CDOCS_SKILL" && grep -q 'Skip' "$CDOCS_SKILL" && grep -qi 'drift debt\|Log as drift debt' "$CDOCS_SKILL"; then
  pass "R-004d" "Disposition options include Update/Skip/Log as drift debt"
else
  fail "R-004d" "Disposition options missing Update/Skip/Log as drift debt"
fi

# R-004e: Staleness detection comes BEFORE suggesting new entries
# The spec says "check whether existing entries need updating BEFORE suggesting new entries"
# Match the step headings, not prose descriptions
STALE_LINE=$(skill_body "$CDOCS_SKILL" | grep -n 'staleness detection\|Existing-entry staleness' | head -1 | grep -o '^[0-9]*')
NEW_LINE=$(skill_body "$CDOCS_SKILL" | grep -n 'Suggest new entries\|Step 5c.*Suggest\|suggest new entries' | head -1 | grep -o '^[0-9]*')
if [ -n "$STALE_LINE" ] && [ -n "$NEW_LINE" ] && [ "$STALE_LINE" -lt "$NEW_LINE" ]; then
  pass "R-004e" "Staleness detection appears before new-entry suggestions"
else
  fail "R-004e" "Staleness detection does not appear before new-entry suggestions (stale=$STALE_LINE, new=$NEW_LINE)"
fi

# ============================================================================
# R-005 [unit]: /cdocs drift-debt resolution prompting
# ============================================================================

section "R-005: /cdocs drift-debt resolution prompting"

# R-005a: Section 5 instructs reading drift-debt.json
if grep -qi 'drift-debt.json' "$CDOCS_SKILL"; then
  pass "R-005a" "Section 5 references drift-debt.json"
else
  fail "R-005a" "Section 5 missing drift-debt.json reference"
fi

# R-005b: Disposition options include Resolve now, Keep as debt, Close
if grep -qi 'Resolve now' "$CDOCS_SKILL" && grep -qi 'Keep as debt' "$CDOCS_SKILL" && grep -qi 'Close' "$CDOCS_SKILL"; then
  pass "R-005b" "Disposition options include Resolve now/Keep as debt/Close"
else
  fail "R-005b" "Missing drift-debt resolution disposition options"
fi

# R-005c: Resolved items updated with status "resolved", resolved date, resolution description
if grep -qi 'status.*resolved\|resolved.*ISO.*date\|resolution.*description' "$CDOCS_SKILL"; then
  pass "R-005c" "Resolved items updated with status/date/resolution"
else
  fail "R-005c" "Missing resolved item update fields"
fi

# R-005d: Uses Edit not Write for drift-debt.json updates
if grep -qi 'via Edit.*not Write\|Edit, not Write\|Edit.*not.*Write' "$CDOCS_SKILL"; then
  pass "R-005d" "drift-debt.json updates use Edit not Write"
else
  fail "R-005d" "Missing Edit-not-Write instruction for drift-debt.json"
fi

# R-005e: Dormant when drift-debt.json absent or no open items (PAT-019)
if grep -qi 'drift-debt.*absent\|drift-debt.*dormant\|drift-debt.*no open\|PAT-019.*drift-debt\|drift-debt.*PAT-019' "$CDOCS_SKILL"; then
  pass "R-005e" "drift-debt resolution dormant when absent/no open items (PAT-019)"
else
  fail "R-005e" "Missing dormant condition for drift-debt resolution (PAT-019)"
fi

# ============================================================================
# R-006 [unit]: /cupdate-arch existing-entry validation step
# ============================================================================

section "R-006: /cupdate-arch existing-entry validation step"

# R-006a: Validate Existing Entries step exists before Scan for Undocumented
# Check that "Validate Existing Entries" or similar appears before "Scan for Undocumented"
if grep -qi 'Validate Existing Entries\|validate existing entries\|Validate.*existing.*entries' "$CUPDATE_ARCH_SKILL"; then
  pass "R-006a" "Validate Existing Entries step exists"
else
  fail "R-006a" "Missing Validate Existing Entries step"
fi

# R-006b: Validate step checks Enforced at paths exist on disk
if grep -qi 'Enforced at.*paths.*exist\|Enforced at.*exist.*on disk\|verify.*Enforced at.*disk' "$CUPDATE_ARCH_SKILL"; then
  pass "R-006b" "Validate step checks Enforced at paths on disk"
else
  fail "R-006b" "Validate step missing Enforced at path existence check"
fi

# R-006c: Validate step checks Test paths exist and reference entry ID
if grep -qi 'Test.*paths.*exist.*reference.*entry\|Test.*reference.*entry ID\|Test.*paths.*reference' "$CUPDATE_ARCH_SKILL"; then
  pass "R-006c" "Validate step checks Test paths reference entry ID"
else
  fail "R-006c" "Validate step missing Test path reference check"
fi

# R-006d: Validate step checks Enforced at includes all producers/consumers
if grep -qi 'producers.*consumers\|all files.*reference.*abstraction\|Enforced at.*includes all' "$CUPDATE_ARCH_SKILL"; then
  pass "R-006d" "Validate step checks Enforced at includes all producers/consumers"
else
  fail "R-006d" "Validate step missing producer/consumer completeness check"
fi

# R-006e: Entries with broken paths presented one at a time with options
if grep -qi 'one at a time\|one entry at a time\|present.*entries.*numbered\|present.*entry.*options' "$CUPDATE_ARCH_SKILL"; then
  pass "R-006e" "Broken entries presented one at a time"
else
  fail "R-006e" "Missing one-at-a-time presentation for broken entries"
fi

# R-006f: Disposition options include Fix, Delete, Skip
if grep -q 'Fix' "$CUPDATE_ARCH_SKILL" && grep -q 'Delete' "$CUPDATE_ARCH_SKILL" && grep -q 'Skip' "$CUPDATE_ARCH_SKILL"; then
  pass "R-006f" "Disposition options include Fix/Delete/Skip"
else
  fail "R-006f" "Missing Fix/Delete/Skip disposition options"
fi

# R-006g: Validate step appears BEFORE Scan for Undocumented step
VALIDATE_LINE=$(skill_body "$CUPDATE_ARCH_SKILL" | grep -n -i 'Validate Existing\|validate existing' | head -1 | grep -o '^[0-9]*')
SCAN_LINE=$(skill_body "$CUPDATE_ARCH_SKILL" | grep -n -i 'Scan for Undocumented\|scan for undocumented\|Scan.*Undocumented' | head -1 | grep -o '^[0-9]*')
if [ -n "$VALIDATE_LINE" ] && [ -n "$SCAN_LINE" ] && [ "$VALIDATE_LINE" -lt "$SCAN_LINE" ]; then
  pass "R-006g" "Validate Existing Entries appears before Scan for Undocumented"
else
  fail "R-006g" "Validate Existing Entries does not appear before Scan for Undocumented"
fi

# ============================================================================
# R-007 [unit]: /cupdate-arch drift-debt incorporation
# ============================================================================

section "R-007: /cupdate-arch drift-debt incorporation"

# R-007a: cupdate-arch reads drift-debt.json
if grep -qi 'drift-debt.json' "$CUPDATE_ARCH_SKILL"; then
  pass "R-007a" "cupdate-arch references drift-debt.json"
else
  fail "R-007a" "cupdate-arch missing drift-debt.json reference"
fi

# R-007b: Open drift-debt items surfaced as candidates
if grep -qi 'drift-debt.*candidates\|drift-debt.*alongside\|open.*drift-debt.*items\|drift-debt.*entry updates' "$CUPDATE_ARCH_SKILL"; then
  pass "R-007b" "drift-debt items surfaced as candidates for updates"
else
  fail "R-007b" "Missing drift-debt item surfacing in cupdate-arch"
fi

# R-007c: Dormant when absent or empty (PAT-019)
if grep -qi 'drift-debt.*absent\|drift-debt.*empty\|drift-debt.*dormant\|PAT-019.*drift-debt\|drift-debt.*PAT-019' "$CUPDATE_ARCH_SKILL"; then
  pass "R-007c" "drift-debt incorporation dormant when absent/empty (PAT-019)"
else
  fail "R-007c" "Missing dormant condition for drift-debt incorporation (PAT-019)"
fi

# ============================================================================
# R-008 [unit]: Complementarity notes across skills
# ============================================================================

section "R-008: Complementarity notes across skills"

# R-008a: /cverify complementarity note — references Architecture Compliance Agent (Phase 4)
if grep -qi 'Architecture Compliance Agent\|Phase 4.*check\|compliance.*agent' "$CVERIFY_SKILL"; then
  pass "R-008a" "cverify complementarity note references Phase 4 agent"
else
  fail "R-008a" "cverify missing Phase 4 agent reference in complementarity note"
fi

# R-008b: /cverify complementarity note — mentions /cdocs acts on findings
if grep -qi 'cdocs.*acts.*findings\|cdocs.*acts on\|cdocs.*updates.*entries' "$CVERIFY_SKILL"; then
  pass "R-008b" "cverify complementarity note references /cdocs acting on findings"
else
  fail "R-008b" "cverify missing /cdocs reference in complementarity note"
fi

# R-008c: /cverify complementarity note — mentions /cupdate-arch comprehensive validation
if grep -qi 'cupdate-arch.*comprehensive\|cupdate-arch.*validates\|cupdate-arch.*validation' "$CVERIFY_SKILL"; then
  pass "R-008c" "cverify complementarity note references /cupdate-arch validation"
else
  fail "R-008c" "cverify missing /cupdate-arch reference in complementarity note"
fi

# R-008d: /cdocs complementarity note — references /cverify stale detection
if grep -qi 'cverify.*detect.*stale\|cverify.*stale.*entries\|cverify.*staleness' "$CDOCS_SKILL"; then
  pass "R-008d" "cdocs complementarity note references /cverify stale detection"
else
  fail "R-008d" "cdocs missing /cverify stale detection reference"
fi

# R-008e: /cdocs complementarity note — references /cupdate-arch beyond current feature
if grep -qi 'cupdate-arch.*beyond.*current\|cupdate-arch.*comprehensive.*validation\|cupdate-arch.*all entries' "$CDOCS_SKILL"; then
  pass "R-008e" "cdocs complementarity note references /cupdate-arch beyond current feature"
else
  fail "R-008e" "cdocs missing /cupdate-arch beyond-current-feature reference"
fi

# R-008f: /cupdate-arch complementarity note — references /cverify feature-scoped staleness
if grep -qi 'cverify.*feature-scoped\|cverify.*feature.*staleness\|cverify.*detects.*feature' "$CUPDATE_ARCH_SKILL"; then
  pass "R-008f" "cupdate-arch complementarity note references /cverify feature-scoped"
else
  fail "R-008f" "cupdate-arch missing /cverify feature-scoped reference"
fi

# R-008g: /cupdate-arch complementarity note — references /cdocs updates for current feature
if grep -qi 'cdocs.*current feature\|cdocs.*updates.*entries.*current\|cdocs.*updates entries' "$CUPDATE_ARCH_SKILL"; then
  pass "R-008g" "cupdate-arch complementarity note references /cdocs current-feature updates"
else
  fail "R-008g" "cupdate-arch missing /cdocs current-feature reference"
fi

# R-008h: /cupdate-arch complementarity note — states it validates ALL entries
if grep -qi 'ALL entries\|validates ALL\|all entries.*not just' "$CUPDATE_ARCH_SKILL"; then
  pass "R-008h" "cupdate-arch complementarity note states ALL entries validation"
else
  fail "R-008h" "cupdate-arch missing ALL entries validation statement"
fi

# ============================================================================
# R-009 [unit]: Dormant-signal graceful degradation (PAT-019)
# ============================================================================

section "R-009: Dormant-signal graceful degradation (PAT-019)"

# R-009a: /cverify — no ARCHITECTURE.md entries → dormant
if grep -qi 'no.*ARCHITECTURE.*entries.*dormant\|ARCHITECTURE.*no entries.*dormant\|no entries.*architecture.*check.*dormant\|no.*entries.*check.*dormant' "$CVERIFY_SKILL"; then
  pass "R-009a" "cverify: no ARCHITECTURE.md entries → dormant"
else
  fail "R-009a" "cverify missing dormant condition for no ARCHITECTURE.md entries"
fi

# R-009b: /cverify — no drift-debt.json → dormant (covered by R-002d)
# Already tested in R-002d, but verify it's in the architecture section context
pass "R-009b" "cverify: no drift-debt.json → dormant (verified in R-002d)"

# R-009c: /cdocs — no verification report → runs own staleness detection
if grep -qi 'no verification report\|verification report.*not exist\|runs.*own.*staleness\|own staleness detection\|instead of relying on.*report' "$CDOCS_SKILL"; then
  pass "R-009c" "cdocs: no verification report → runs own staleness detection"
else
  fail "R-009c" "cdocs missing fallback for missing verification report"
fi

# R-009d: /cdocs — no drift-debt.json → dormant (covered by R-005e)
pass "R-009d" "cdocs: no drift-debt.json → dormant (verified in R-005e)"

# R-009e: /cupdate-arch — empty Enforced at or Test fields → skip entry validation
if grep -qi 'empty.*Enforced at.*skip\|empty.*Test.*skip\|Enforced at.*empty.*skip\|Test.*empty.*skip' "$CUPDATE_ARCH_SKILL"; then
  pass "R-009e" "cupdate-arch: empty Enforced at/Test → skip entry validation"
else
  fail "R-009e" "cupdate-arch missing skip for empty Enforced at/Test fields"
fi

# R-009f: /cupdate-arch — no drift-debt.json → dormant (covered by R-007c)
pass "R-009f" "cupdate-arch: no drift-debt.json → dormant (verified in R-007c)"

# ============================================================================
# R-010 [unit]: Phase 4 compliance agent complementarity
# ============================================================================

section "R-010: Phase 4 compliance agent complementarity distinction"

# R-010a: /cverify distinguishes maintenance lens from violation lens
if grep -qi 'entries need updating\|maintenance lens\|do entries need updating\|inverse.*whether entries' "$CVERIFY_SKILL"; then
  pass "R-010a" "cverify distinguishes maintenance lens (entries need updating)"
else
  fail "R-010a" "cverify missing maintenance-lens distinction"
fi

# R-010b: /cverify does NOT duplicate Phase 4 check types — pattern compliance
R010_SECTION=$(skill_body "$CVERIFY_SKILL" | sed -n '/^### .*Architecture Adherence/,/^### [0-9]\|^## /p')
if [ -z "$R010_SECTION" ]; then
  fail "R-010b" "Architecture Adherence section not found — cannot check Phase 4 exclusion"
elif echo "$R010_SECTION" | grep -qi 'pattern compliance'; then
  fail "R-010b" "cverify Architecture Adherence section duplicates Phase 4 'pattern compliance'"
else
  pass "R-010b" "cverify does not duplicate Phase 4 pattern compliance check"
fi

# R-010c: /cverify does NOT duplicate Phase 4 check types — trust boundary enforcement
if [ -z "$R010_SECTION" ]; then
  fail "R-010c" "Architecture Adherence section not found — cannot check Phase 4 exclusion"
elif echo "$R010_SECTION" | grep -qi 'trust boundary enforcement'; then
  fail "R-010c" "cverify Architecture Adherence section duplicates Phase 4 'trust boundary enforcement'"
else
  pass "R-010c" "cverify does not duplicate Phase 4 trust boundary enforcement"
fi

# R-010d: /cverify does NOT duplicate Phase 4 check types — new pattern introduction
if [ -z "$R010_SECTION" ]; then
  fail "R-010d" "Architecture Adherence section not found — cannot check Phase 4 exclusion"
elif echo "$R010_SECTION" | grep -qi 'new pattern introduction'; then
  fail "R-010d" "cverify Architecture Adherence section duplicates Phase 4 'new pattern introduction'"
else
  pass "R-010d" "cverify does not duplicate Phase 4 new pattern introduction"
fi

# ============================================================================
# R-011 [unit]: Docs updates
# ============================================================================

section "R-011: Docs updates for architecture maintenance"

# R-011a: cverify docs mention architecture adherence/maintenance checking
if grep -qi 'architecture adherence\|architecture maintenance\|entry.*staleness\|stale.*entries\|entry-by-entry' "$CVERIFY_DOCS"; then
  pass "R-011a" "cverify docs mention architecture adherence checking"
else
  fail "R-011a" "cverify docs missing architecture adherence description"
fi

# R-011b: cverify docs mention drift-debt surfacing
if grep -qi 'drift.debt\|drift-debt' "$CVERIFY_DOCS"; then
  pass "R-011b" "cverify docs mention drift-debt surfacing"
else
  fail "R-011b" "cverify docs missing drift-debt description"
fi

# R-011c: cdocs docs mention existing-entry staleness detection
if grep -qi 'existing.*entry.*staleness\|stale.*entries\|staleness.*detection\|existing-entry' "$CDOCS_DOCS"; then
  pass "R-011c" "cdocs docs mention existing-entry staleness detection"
else
  fail "R-011c" "cdocs docs missing existing-entry staleness description"
fi

# R-011d: cdocs docs mention drift-debt resolution
if grep -qi 'drift.debt.*resolution\|resolve.*drift.debt\|drift-debt' "$CDOCS_DOCS"; then
  pass "R-011d" "cdocs docs mention drift-debt resolution"
else
  fail "R-011d" "cdocs docs missing drift-debt resolution description"
fi

# R-011e: cupdate-arch docs mention existing-entry validation
if grep -qi 'existing.*entry.*validation\|validate.*existing\|existing-entry\|Validate Existing' "$CUPDATE_ARCH_DOCS"; then
  pass "R-011e" "cupdate-arch docs mention existing-entry validation"
else
  fail "R-011e" "cupdate-arch docs missing existing-entry validation description"
fi

# R-011f: cupdate-arch docs mention drift-debt incorporation
if grep -qi 'drift.debt.*incorporation\|drift-debt.*candidates\|drift-debt' "$CUPDATE_ARCH_DOCS"; then
  pass "R-011f" "cupdate-arch docs mention drift-debt incorporation"
else
  fail "R-011f" "cupdate-arch docs missing drift-debt incorporation description"
fi

# ============================================================================
# R-012 [unit]: Test file exists and is registered
# ============================================================================

section "R-012: Test file in commands.test and CI"

# R-012a: This test file exists
if [ -f "tests/test-carchitect-phase5.sh" ]; then
  pass "R-012a" "Test file tests/test-carchitect-phase5.sh exists"
else
  fail "R-012a" "Test file tests/test-carchitect-phase5.sh missing"
fi

# R-012b: Test file is registered in commands.test in workflow-config.json
if grep -q 'test-carchitect-phase5.sh' "$WORKFLOW_CONFIG"; then
  pass "R-012b" "test-carchitect-phase5.sh registered in commands.test"
else
  fail "R-012b" "test-carchitect-phase5.sh not registered in commands.test"
fi

# R-012c: Test file is registered in .github/workflows/ci.yml
if grep -q 'test-carchitect-phase5.sh' ".github/workflows/ci.yml"; then
  pass "R-012c" "test-carchitect-phase5.sh registered in CI workflow"
else
  fail "R-012c" "test-carchitect-phase5.sh not registered in CI workflow"
fi

# ============================================================================
# PRH-002: /cverify architecture findings are NOT blocking
# ============================================================================

section "PRH-002: /cverify architecture findings not blocking"

# PRH-002a: The Architecture Adherence section (not the old Section 3) does NOT classify
# findings as BLOCKING. Extract only the "Architecture Adherence" section by heading.
# Exclude lines containing "non-blocking" since that's the OPPOSITE of blocking.
ARCH_SECTION=$(skill_body "$CVERIFY_SKILL" | sed -n '/^### .*Architecture Adherence/,/^### [0-9]\|^## /p')
ARCH_BLOCKING=$(echo "$ARCH_SECTION" | grep -iv 'non-blocking' | grep -qi 'BLOCKING.*finding\|finding.*BLOCKING\|classified.*BLOCKING' && echo "yes" || echo "no")
if [ -z "$ARCH_SECTION" ]; then
  fail "PRH-002a" "Architecture Adherence section not found — cannot verify non-BLOCKING"
elif [ "$ARCH_BLOCKING" = "yes" ]; then
  fail "PRH-002a" "Architecture Adherence section classifies findings as BLOCKING"
else
  pass "PRH-002a" "Architecture Adherence section does not use BLOCKING classification"
fi

# ============================================================================
# PRH-003: No duplication of Phase 4 check types
# ============================================================================

section "PRH-003: No duplication of Phase 4 check types in architecture section"

# PRH-003a: "pattern compliance" does not appear in the Architecture Adherence section
# Extract the section fresh for these checks
PRH3_SECTION=$(skill_body "$CVERIFY_SKILL" | sed -n '/^### .*Architecture Adherence/,/^### [0-9]\|^## /p')
if [ -z "$PRH3_SECTION" ]; then
  fail "PRH-003a" "Architecture Adherence section not found — cannot verify exclusion"
elif echo "$PRH3_SECTION" | grep -qi 'pattern compliance'; then
  fail "PRH-003a" "Phase 4 'pattern compliance' duplicated in Architecture Adherence section"
else
  pass "PRH-003a" "'pattern compliance' absent from Architecture Adherence section"
fi

# PRH-003b: "trust boundary enforcement" does not appear
if [ -z "$PRH3_SECTION" ]; then
  fail "PRH-003b" "Architecture Adherence section not found — cannot verify exclusion"
elif echo "$PRH3_SECTION" | grep -qi 'trust boundary enforcement'; then
  fail "PRH-003b" "Phase 4 'trust boundary enforcement' duplicated in Architecture Adherence section"
else
  pass "PRH-003b" "'trust boundary enforcement' absent from Architecture Adherence section"
fi

# PRH-003c: "new pattern introduction" does not appear
if [ -z "$PRH3_SECTION" ]; then
  fail "PRH-003c" "Architecture Adherence section not found — cannot verify exclusion"
elif echo "$PRH3_SECTION" | grep -qi 'new pattern introduction'; then
  fail "PRH-003c" "Phase 4 'new pattern introduction' duplicated in Architecture Adherence section"
else
  pass "PRH-003c" "'new pattern introduction' absent from Architecture Adherence section"
fi

# ============================================================================
# Summary
# ============================================================================

summary "carchitect-phase5-maintenance-loop-checks"
