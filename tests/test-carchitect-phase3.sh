#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091,SC2016,SC2086
# Correctless — /carchitect Phase 3 Architecture Adherence Auditor Tests
#
# Enforces the carchitect-phase-3-audit spec rules (R-001..R-011).
# Tests are structural — they verify prompt text in skills/caudit/SKILL.md
# and docs/skills/caudit.md. All rules are prompt-level enforcement;
# tests verify the mechanical envelope: required prompt phrases, agent
# role table entries, instruction references, and section headings.
#
# Run from repo root: bash tests/test-carchitect-phase3.sh

source "$(dirname "${BASH_SOURCE[0]}")/test-helpers.sh"
set -f

# ============================================================================
# File paths
# ============================================================================

CAUDIT_SKILL="skills/caudit/SKILL.md"
CAUDIT_DIST="correctless/skills/caudit/SKILL.md"
CAUDIT_DOCS="docs/skills/caudit.md"

# ============================================================================
# R-001 [unit]: Architecture Adherence Checker role in all three preset tables
# ============================================================================

section "R-001: Architecture Adherence Checker role in all three presets"

# R-001a: QA Olympics preset table contains Architecture Adherence Checker row
if awk '/### QA Olympics/,/### (Hacker|Performance|Custom)/' "$CAUDIT_SKILL" | grep -qi 'Architecture Adherence Checker'; then
  pass "R-001a" "QA preset table contains Architecture Adherence Checker role"
else
  fail "R-001a" "QA preset table missing Architecture Adherence Checker role"
fi

# R-001b: Hacker Olympics preset table contains Architecture Adherence Checker row
if awk '/### Hacker Olympics/,/### (Performance|Custom|$)/' "$CAUDIT_SKILL" | grep -qi 'Architecture Adherence Checker'; then
  pass "R-001b" "Hacker preset table contains Architecture Adherence Checker role"
else
  fail "R-001b" "Hacker preset table missing Architecture Adherence Checker role"
fi

# R-001c: Performance Olympics preset table contains Architecture Adherence Checker row
if awk '/### Performance Olympics/,/### (Custom|$)/' "$CAUDIT_SKILL" | grep -qi 'Architecture Adherence Checker'; then
  pass "R-001c" "Performance preset table contains Architecture Adherence Checker role"
else
  fail "R-001c" "Performance preset table missing Architecture Adherence Checker role"
fi

# R-001d: QA preset lens contains hostile framing about pattern violations
if awk '/### QA Olympics/,/### (Hacker|Performance|Custom)/' "$CAUDIT_SKILL" | grep -qi 'pattern.*violated\|violated.*pattern'; then
  pass "R-001d" "QA preset Architecture Adherence Checker has pattern-violation lens"
else
  fail "R-001d" "QA preset Architecture Adherence Checker missing pattern-violation lens"
fi

# R-001e: Hacker preset lens contains hostile framing about trust boundary crossings
if awk '/### Hacker Olympics/,/### (Performance|Custom|$)/' "$CAUDIT_SKILL" | grep -qi 'trust boundary.*unguarded\|unguarded.*crossing'; then
  pass "R-001e" "Hacker preset Architecture Adherence Checker has trust-boundary lens"
else
  fail "R-001e" "Hacker preset Architecture Adherence Checker missing trust-boundary lens"
fi

# R-001f: Perf preset lens contains hostile framing about layer convention shortcuts
if awk '/### Performance Olympics/,/### (Custom|$)/' "$CAUDIT_SKILL" | grep -qi 'layer convention.*performance\|performance.*shortcut'; then
  pass "R-001f" "Perf preset Architecture Adherence Checker has layer-shortcut lens"
else
  fail "R-001f" "Perf preset Architecture Adherence Checker missing layer-shortcut lens"
fi

# ============================================================================
# R-002 [unit]: Agent prompt instructs reading ARCHITECTURE.md and extracting
#               PAT-xxx, ABS-xxx, TB-xxx entries
# ============================================================================

section "R-002: Agent prompt extracts PAT/ABS/TB entries from ARCHITECTURE.md"

# R-002a: Prompt instructs the Architecture Adherence Checker to read ARCHITECTURE.md
# and mechanically extract entries — must be in the adherence checker context, not
# just the general agent context list
if grep -qi 'mechanically extract PAT-xxx' "$CAUDIT_SKILL"; then
  pass "R-002a" "caudit SKILL.md instructs adherence checker to read and extract from ARCHITECTURE.md"
else
  fail "R-002a" "caudit SKILL.md missing adherence checker ARCHITECTURE.md extraction instruction"
fi

# R-002b: Prompt instructs extracting PAT-xxx entries and checking pattern Rules
if grep -qi 'extract.*PAT-xxx.*entries\|PAT-xxx.*entries.*check\|PAT-xxx.*Rule.*codebase' "$CAUDIT_SKILL"; then
  pass "R-002b" "caudit SKILL.md instructs extracting and checking PAT-xxx entries"
else
  fail "R-002b" "caudit SKILL.md missing PAT-xxx entry extraction/checking instruction"
fi

# R-002c: Prompt instructs extracting ABS-xxx entries and checking Invariants
if grep -qi 'extract.*ABS-xxx.*entries\|ABS-xxx.*entries.*check\|ABS-xxx.*Invariant.*codebase' "$CAUDIT_SKILL"; then
  pass "R-002c" "caudit SKILL.md instructs extracting and checking ABS-xxx entries"
else
  fail "R-002c" "caudit SKILL.md missing ABS-xxx entry extraction/checking instruction"
fi

# R-002d: Prompt instructs extracting TB-xxx entries and checking Invariants
if grep -qi 'extract.*TB-xxx.*entries\|TB-xxx.*entries.*check\|TB-xxx.*Invariant.*codebase' "$CAUDIT_SKILL"; then
  pass "R-002d" "caudit SKILL.md instructs extracting and checking TB-xxx entries"
else
  fail "R-002d" "caudit SKILL.md missing TB-xxx entry extraction/checking instruction"
fi

# R-002e: Prompt instructs checking layer conventions for dependency direction violations
if grep -qi 'layer convention.*dependency direction\|dependency direction.*violation\|layer.*convention.*violation' "$CAUDIT_SKILL"; then
  pass "R-002e" "caudit SKILL.md instructs checking layer convention dependency direction"
else
  fail "R-002e" "caudit SKILL.md missing layer convention dependency direction check"
fi

# R-002f: Prompt instructs detecting undocumented patterns (3+ files, no PAT-xxx)
if grep -qi 'undocumented pattern.*3.*files\|3.*files.*no PAT-xxx\|undocumented.*pattern.*no PAT' "$CAUDIT_SKILL"; then
  pass "R-002f" "caudit SKILL.md instructs detecting undocumented patterns in 3+ files"
else
  fail "R-002f" "caudit SKILL.md missing undocumented pattern detection instruction"
fi

# R-002g: Prompt instructs following See-links for index-only PAT entries
# The instruction spans multiple lines — check for the two key phrases separately
if grep -qi 'index-only entries' "$CAUDIT_SKILL" && grep -qi 'See-link' "$CAUDIT_SKILL"; then
  pass "R-002g" "caudit SKILL.md instructs following See-links for index-only entries"
else
  fail "R-002g" "caudit SKILL.md missing See-link follow instruction for index-only entries"
fi

# R-002h: Prompt mentions ARCHITECTURE.md as trusted data source (TB-005 reference)
if grep -qi 'trusted data source\|human-authored.*sensitive-file-guard\|TB-005' "$CAUDIT_SKILL"; then
  pass "R-002h" "caudit SKILL.md treats ARCHITECTURE.md as trusted data source"
else
  fail "R-002h" "caudit SKILL.md missing trusted data source reference for ARCHITECTURE.md"
fi

# ============================================================================
# R-003 [unit]: Intentional exception handling for TB-xxx sub-entries
# ============================================================================

section "R-003: TB-xxx sub-entry exception handling"

# R-003a: Prompt instructs checking sub-entries before submitting TB violations
if grep -qi 'sub-entry\|sub-entries\|TB-.*sub-entry\|scoped exception' "$CAUDIT_SKILL"; then
  pass "R-003a" "caudit SKILL.md references TB sub-entries for exception handling"
else
  fail "R-003a" "caudit SKILL.md missing TB sub-entry exception handling"
fi

# R-003b: Prompt describes the TB-NNNx sub-entry pattern (e.g., TB-001a)
if grep -qi 'TB-NNN.*lowercase\|TB-.*lowercase letter suffix\|TB-\d\{3\}[a-z]\|TB-xxx.*sub-entry.*pattern' "$CAUDIT_SKILL"; then
  pass "R-003b" "caudit SKILL.md describes TB-NNNx sub-entry identification pattern"
else
  fail "R-003b" "caudit SKILL.md missing TB-NNNx sub-entry pattern description"
fi

# R-003c: Prompt instructs classifying matching sub-entry exceptions as false positives
# Must specifically reference TB sub-entries + false positive in same context
if grep -qi 'known exception.*not a violation\|scoped exception.*do not submit\|sub-entry.*false positive\|documented.*exception.*false positive' "$CAUDIT_SKILL"; then
  pass "R-003c" "caudit SKILL.md instructs classifying sub-entry exceptions as false positives"
else
  fail "R-003c" "caudit SKILL.md missing false positive classification for sub-entry exceptions"
fi

# ============================================================================
# R-004 [unit]: Dormant-signal fallback when ARCHITECTURE.md is missing/empty
# ============================================================================

section "R-004: Dormant-signal fallback for missing ARCHITECTURE.md"

# R-004a: Prompt includes fallback for missing ARCHITECTURE.md
if grep -qi 'ARCHITECTURE.md does not exist\|ARCHITECTURE.md.*does not exist\|no architecture entries found' "$CAUDIT_SKILL"; then
  pass "R-004a" "caudit SKILL.md includes dormant-signal fallback for missing ARCHITECTURE.md"
else
  fail "R-004a" "caudit SKILL.md missing dormant-signal fallback for ARCHITECTURE.md"
fi

# R-004b: Prompt includes fallback for placeholder markers
if grep -qi 'placeholder.*markers\|PROJECT_NAME.*PLACEHOLDER\|{PROJECT_NAME}.*{PLACEHOLDER}' "$CAUDIT_SKILL"; then
  pass "R-004b" "caudit SKILL.md includes fallback for placeholder markers"
else
  fail "R-004b" "caudit SKILL.md missing placeholder marker fallback"
fi

# R-004c: Prompt instructs submitting zero findings when dormant
if grep -qi 'zero findings.*this lens\|submit zero findings\|architecture adherence.*skipped' "$CAUDIT_SKILL"; then
  pass "R-004c" "caudit SKILL.md instructs zero findings when dormant"
else
  fail "R-004c" "caudit SKILL.md missing zero-findings-when-dormant instruction"
fi

# R-004d: Prompt prohibits inferring architecture when dormant
if grep -qi 'do not.*infer.*architecture\|not.*infer architecture.*codebase\|carchitect.*job' "$CAUDIT_SKILL"; then
  pass "R-004d" "caudit SKILL.md prohibits inferring architecture when dormant"
else
  fail "R-004d" "caudit SKILL.md missing prohibition on inferring architecture"
fi

# ============================================================================
# R-005 [unit]: Staleness warning when ARCHITECTURE.md is 30+ days old
# ============================================================================

section "R-005: Staleness warning for ARCHITECTURE.md"

# R-005a: Prompt includes staleness check using git log date comparison
if grep -qi 'staleness.*warning\|stale.*ARCHITECTURE.md\|30.*days.*before\|last-modified date' "$CAUDIT_SKILL"; then
  pass "R-005a" "caudit SKILL.md includes staleness warning instruction"
else
  fail "R-005a" "caudit SKILL.md missing staleness warning instruction"
fi

# R-005b: Prompt references git log for ARCHITECTURE.md date
if grep -qi 'git log.*ARCHITECTURE.md\|ARCHITECTURE.md.*git log\|git log -1.*format.*ai.*ARCHITECTURE' "$CAUDIT_SKILL"; then
  pass "R-005b" "caudit SKILL.md references git log for ARCHITECTURE.md date check"
else
  fail "R-005b" "caudit SKILL.md missing git log date check for ARCHITECTURE.md"
fi

# R-005c: Prompt specifies SUSPICIOUS-tier for the staleness finding
if grep -qi 'SUSPICIOUS-tier finding' "$CAUDIT_SKILL"; then
  pass "R-005c" "caudit SKILL.md specifies SUSPICIOUS tier for staleness finding"
else
  fail "R-005c" "caudit SKILL.md missing SUSPICIOUS tier for staleness finding"
fi

# R-005d: Prompt suggests running /cupdate-arch for staleness
if grep -qi 'cupdate-arch.*stale\|stale.*cupdate-arch\|Consider running /cupdate-arch' "$CAUDIT_SKILL"; then
  pass "R-005d" "caudit SKILL.md suggests /cupdate-arch for staleness"
else
  fail "R-005d" "caudit SKILL.md missing /cupdate-arch suggestion for staleness"
fi

# ============================================================================
# R-006 [unit]: architecture_ref field in findings
# ============================================================================

section "R-006: architecture_ref field in findings"

# R-006a: Prompt requires architecture_ref field for adherence checker findings
if grep -qi 'architecture_ref.*field\|architecture_ref.*PAT-xxx\|architecture_ref.*ABS-xxx\|architecture_ref.*TB-xxx' "$CAUDIT_SKILL"; then
  pass "R-006a" "caudit SKILL.md requires architecture_ref field in findings"
else
  fail "R-006a" "caudit SKILL.md missing architecture_ref field requirement"
fi

# R-006b: architecture_ref is described as PAT-xxx, ABS-xxx, or TB-xxx identifier
if grep -qi 'architecture_ref.*PAT.*ABS.*TB\|PAT-xxx.*ABS-xxx.*TB-xxx.*architecture_ref' "$CAUDIT_SKILL"; then
  pass "R-006b" "caudit SKILL.md describes architecture_ref value as PAT/ABS/TB identifier"
else
  fail "R-006b" "caudit SKILL.md missing architecture_ref value description"
fi

# R-006c: architecture_ref field appears in the Findings Artifacts JSON schema example
if awk '/## Findings Artifacts/,/^## [^F]/' "$CAUDIT_SKILL" | grep -qi 'architecture_ref'; then
  pass "R-006c" "architecture_ref field appears in Findings Artifacts JSON example"
else
  fail "R-006c" "architecture_ref field missing from Findings Artifacts JSON example"
fi

# R-006d: architecture_ref can be null for undocumented-pattern findings
if grep -qi 'architecture_ref.*null.*undocumented\|null.*undocumented.*pattern\|null for undocumented-pattern' "$CAUDIT_SKILL"; then
  pass "R-006d" "caudit SKILL.md allows null architecture_ref for undocumented patterns"
else
  fail "R-006d" "caudit SKILL.md missing null-for-undocumented-patterns clause"
fi

# ============================================================================
# R-007 [unit]: Four check types mapping to roadmap capabilities
# ============================================================================

section "R-007: Four check types for architecture adherence"

# R-007a: Pattern compliance check type (PAT-xxx)
if grep -qi 'pattern compliance.*PAT-xxx\|PAT-xxx.*pattern compliance\|Pattern compliance' "$CAUDIT_SKILL"; then
  pass "R-007a" "caudit SKILL.md defines pattern compliance check type (PAT-xxx)"
else
  fail "R-007a" "caudit SKILL.md missing pattern compliance check type"
fi

# R-007b: Abstraction invariant check type (ABS-xxx)
if grep -qi 'abstraction invariant.*ABS-xxx\|ABS-xxx.*abstraction invariant\|Abstraction invariant' "$CAUDIT_SKILL"; then
  pass "R-007b" "caudit SKILL.md defines abstraction invariant check type (ABS-xxx)"
else
  fail "R-007b" "caudit SKILL.md missing abstraction invariant check type"
fi

# R-007c: Trust boundary enforcement check type (TB-xxx)
if grep -qi 'trust boundary enforcement.*TB-xxx\|TB-xxx.*trust boundary enforcement\|Trust boundary enforcement' "$CAUDIT_SKILL"; then
  pass "R-007c" "caudit SKILL.md defines trust boundary enforcement check type (TB-xxx)"
else
  fail "R-007c" "caudit SKILL.md missing trust boundary enforcement check type"
fi

# R-007d: Undocumented pattern detection check type
if grep -qi 'undocumented pattern detection\|Undocumented pattern detection' "$CAUDIT_SKILL"; then
  pass "R-007d" "caudit SKILL.md defines undocumented pattern detection check type"
else
  fail "R-007d" "caudit SKILL.md missing undocumented pattern detection check type"
fi

# R-007e: Undocumented pattern calibration — distinguishes project-specific from standard idioms
if grep -qi 'project-specific convention\|standard language idiom\|standard library usage\|framework convention.*NOT' "$CAUDIT_SKILL"; then
  pass "R-007e" "caudit SKILL.md includes undocumented pattern calibration criteria"
else
  fail "R-007e" "caudit SKILL.md missing undocumented pattern calibration criteria"
fi

# R-007f: Undocumented pattern findings are informational
if grep -qi 'undocumented.*informational\|informational.*undocumented\|candidates for PAT-xxx' "$CAUDIT_SKILL"; then
  pass "R-007f" "caudit SKILL.md marks undocumented pattern findings as informational"
else
  fail "R-007f" "caudit SKILL.md missing informational designation for undocumented patterns"
fi

# ============================================================================
# R-008 [unit]: Agent count updates for each preset
# ============================================================================

section "R-008: Agent count updated for each preset"

# R-008a: QA preset agent count range updated to "spawn 5-7"
if grep -qi 'spawn 5-7 based on project' "$CAUDIT_SKILL"; then
  pass "R-008a" "QA preset agent count updated to spawn 5-7"
else
  fail "R-008a" "QA preset agent count not updated to spawn 5-7"
fi

# R-008b: Hacker preset table has Architecture Adherence Checker row (count increases by 1)
if awk '/### Hacker Olympics/,/### (Performance|Custom|$)/' "$CAUDIT_SKILL" | grep -c 'Architecture Adherence Checker' | grep -q '[1-9]'; then
  pass "R-008b" "Hacker preset table includes Architecture Adherence Checker (count +1)"
else
  fail "R-008b" "Hacker preset table missing Architecture Adherence Checker row"
fi

# R-008c: Performance preset table has Architecture Adherence Checker row (count increases by 1)
if awk '/### Performance Olympics/,/### (Custom|$)/' "$CAUDIT_SKILL" | grep -c 'Architecture Adherence Checker' | grep -q '[1-9]'; then
  pass "R-008c" "Performance preset table includes Architecture Adherence Checker (count +1)"
else
  fail "R-008c" "Performance preset table missing Architecture Adherence Checker row"
fi

# ============================================================================
# R-009 [unit]: Architecture Adherence Checker has read-only tool access
# ============================================================================

section "R-009: Architecture Adherence Checker has read-only tool access"

# R-009a: Agent is described as having Read, Grep, Glob, Bash access
if grep -qi 'Architecture Adherence Checker.*Read.*Grep\|adherence.*Read.*Grep.*Glob\|read-only auditor' "$CAUDIT_SKILL"; then
  pass "R-009a" "caudit SKILL.md specifies read-only tools for Architecture Adherence Checker"
else
  fail "R-009a" "caudit SKILL.md missing read-only tool specification for adherence checker"
fi

# R-009b: Agent explicitly lacks Write or Edit access
if grep -qi 'not.*Write.*Edit.*adherence\|adherence.*no.*Write\|read-only.*auditor.*adherence\|does NOT have Write or Edit' "$CAUDIT_SKILL"; then
  pass "R-009b" "caudit SKILL.md explicitly denies Write/Edit for adherence checker"
else
  fail "R-009b" "caudit SKILL.md missing explicit Write/Edit denial for adherence checker"
fi

# ============================================================================
# R-010 [unit]: Regression Hunter context includes architecture_ref from prior runs
# ============================================================================

section "R-010: Regression Hunter context includes architecture adherence findings"

# R-010a: Regression Hunter context list mentions architecture adherence findings
if grep -qi 'previous.*audit.*architecture adherence findings\|architecture adherence findings.*previous\|architecture adherence.*prior\|prior.*architecture adherence' "$CAUDIT_SKILL"; then
  pass "R-010a" "Regression Hunter context references architecture adherence findings"
else
  fail "R-010a" "Regression Hunter context missing architecture adherence findings reference"
fi

# R-010b: Regression Hunter context references architecture_ref field in round-JSON files
if grep -qi 'architecture_ref.*fields.*audit-.*round\|architecture_ref.*audit-.*round-.*json\|architecture_ref.*fields in' "$CAUDIT_SKILL"; then
  pass "R-010b" "Regression Hunter context references architecture_ref in round-JSON"
else
  fail "R-010b" "Regression Hunter context missing architecture_ref round-JSON reference"
fi

# R-010c: Instruction states architecture_ref field is additive / handles absence gracefully
if grep -qi 'architecture_ref.*additive\|additive.*architecture_ref\|handle.*absence.*gracefully\|missing.*architecture_ref.*null' "$CAUDIT_SKILL"; then
  pass "R-010c" "caudit SKILL.md specifies architecture_ref is additive with graceful absence"
else
  fail "R-010c" "caudit SKILL.md missing additive/graceful-absence clause for architecture_ref"
fi

# ============================================================================
# R-011 [unit]: docs/skills/caudit.md updated with Architecture Adherence Checker
# ============================================================================

section "R-011: caudit docs updated"

# R-011a: caudit docs mention Architecture Adherence Checker role
if grep -qi 'Architecture Adherence Checker' "$CAUDIT_DOCS"; then
  pass "R-011a" "caudit docs mention Architecture Adherence Checker role"
else
  fail "R-011a" "caudit docs missing Architecture Adherence Checker mention"
fi

# R-011b: caudit docs describe the four check types
if grep -qi 'pattern compliance\|abstraction invariant\|trust boundary enforcement\|undocumented pattern' "$CAUDIT_DOCS"; then
  pass "R-011b" "caudit docs describe architecture adherence check types"
else
  fail "R-011b" "caudit docs missing architecture adherence check types"
fi

# R-011c: caudit docs describe dormant-signal fallback
if grep -qi 'dormant.*ARCHITECTURE\|ARCHITECTURE.*not exist.*skip\|no.*architecture.*entries.*skip\|architecture adherence.*skipped' "$CAUDIT_DOCS"; then
  pass "R-011c" "caudit docs describe dormant-signal fallback"
else
  fail "R-011c" "caudit docs missing dormant-signal fallback description"
fi

# R-011d: caudit docs describe staleness warning
if grep -qi 'stale.*ARCHITECTURE\|staleness.*warning\|30.*days.*stale\|ARCHITECTURE.*stale' "$CAUDIT_DOCS"; then
  pass "R-011d" "caudit docs describe staleness warning"
else
  fail "R-011d" "caudit docs missing staleness warning description"
fi

# ============================================================================
# Sync parity: source and distribution files match
# ============================================================================

section "Sync parity: source and distribution match"

if [ -f "$CAUDIT_DIST" ]; then
  if diff -q "$CAUDIT_SKILL" "$CAUDIT_DIST" > /dev/null 2>&1; then
    pass "SYNC-001" "caudit source and distribution match"
  else
    fail "SYNC-001" "caudit source and distribution differ — run sync.sh"
  fi
else
  skip "SYNC-001" "caudit distribution file not found"
fi

# ============================================================================
# Summary
# ============================================================================

summary "carchitect-phase3-audit-adherence"
