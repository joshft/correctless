#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091,SC2016,SC2086
# Correctless — /carchitect Phase 4 Architecture Compliance in PR Review Tests
#
# Enforces the carchitect-phase-4-review spec rules (R-001..R-015).
# Tests are structural — they verify prompt text in agents/architecture-compliance-reviewer.md,
# skills/cpr-review/SKILL.md, and docs/skills/cpr-review.md. All rules are prompt-level
# enforcement; tests verify the mechanical envelope: required prompt phrases, agent
# frontmatter, distribution parity, and allowed-tools references.
#
# Run from repo root: bash tests/test-carchitect-phase4.sh

source "$(dirname "${BASH_SOURCE[0]}")/test-helpers.sh"
set -f

# ============================================================================
# File paths
# ============================================================================

AGENT_FILE="agents/architecture-compliance-reviewer.md"
AGENT_DIST="correctless/agents/architecture-compliance-reviewer.md"
PR_REVIEW_SKILL="skills/cpr-review/SKILL.md"
PR_REVIEW_DIST="correctless/skills/cpr-review/SKILL.md"
PR_REVIEW_DOCS="docs/skills/cpr-review.md"
# ABS-010 body moved to the abstractions fragment (index+body-out fragmentation);
# both consumers below check ABS-010 body content, so read the fragment.
ARCHITECTURE_MD="docs/architecture/abstractions.md"
WORKFLOW_CONFIG=".correctless/config/workflow-config.json"

# ============================================================================
# R-001 [unit]: /cpr-review spawns Architecture Compliance Agent in Step 3,
#               parallel with Steps 4-8, collected before Present Findings,
#               spawned at all intensity levels
# ============================================================================

section "R-001: /cpr-review spawns Architecture Compliance Agent in Step 3"

# R-001a: Step 3 in SKILL.md references spawning the architecture compliance agent
if grep -qi 'architecture compliance.*agent\|spawn.*architecture.*compliance\|architecture-compliance-reviewer' "$PR_REVIEW_SKILL"; then
  pass "R-001a" "SKILL.md Step 3 references architecture compliance agent"
else
  fail "R-001a" "SKILL.md Step 3 missing architecture compliance agent reference"
fi

# R-001b: Agent runs in parallel with Steps 4-8 (parallel keyword in Step 3 context)
if grep -qi 'parallel.*steps\|parallel.*4.*8\|parallel.*security\|runs in parallel' "$PR_REVIEW_SKILL"; then
  pass "R-001b" "SKILL.md indicates agent runs in parallel with Steps 4-8"
else
  fail "R-001b" "SKILL.md missing parallel execution with Steps 4-8"
fi

# R-001c: Agent results collected before Present Findings
if grep -qi 'collect.*agent.*findings\|collect.*architecture.*compliance.*findings\|merge.*agent.*findings\|agent.*findings.*present' "$PR_REVIEW_SKILL"; then
  pass "R-001c" "SKILL.md collects agent findings before Present Findings"
else
  fail "R-001c" "SKILL.md missing agent findings collection before Present Findings"
fi

# R-001d: Agent spawned at all intensity levels (not gated by intensity)
# Verify there is NO intensity gate on the agent spawn — it should NOT be inside a
# "Full Mode" or "high+ intensity" section. Check that the Step 3 section does not
# condition agent spawn on intensity.
if grep -qi 'all intensity levels\|not gated by intensity\|architecture compliance is not.*intensity' "$PR_REVIEW_SKILL"; then
  pass "R-001d" "SKILL.md confirms agent spawned at all intensity levels"
else
  fail "R-001d" "SKILL.md missing confirmation that agent spawned at all intensity levels"
fi

# ============================================================================
# R-002 [unit]: Agent file exists with correct frontmatter
# ============================================================================

section "R-002: Agent file and frontmatter"

# R-002a: Agent file exists
if [ -f "$AGENT_FILE" ]; then
  pass "R-002a" "Agent file exists at $AGENT_FILE"
else
  fail "R-002a" "Agent file missing: $AGENT_FILE"
fi

# R-002b: Frontmatter name field is correct
if [ -f "$AGENT_FILE" ] && head -10 "$AGENT_FILE" | grep -q '^name: architecture-compliance-reviewer$'; then
  pass "R-002b" "Agent frontmatter name is architecture-compliance-reviewer"
else
  fail "R-002b" "Agent frontmatter name missing or incorrect"
fi

# R-002c: Frontmatter tools field is Read, Grep, Glob only
if [ -f "$AGENT_FILE" ] && head -10 "$AGENT_FILE" | grep -q '^tools: Read, Grep, Glob$'; then
  pass "R-002c" "Agent frontmatter tools: Read, Grep, Glob"
else
  fail "R-002c" "Agent frontmatter tools missing or not Read, Grep, Glob"
fi

# R-002d: Frontmatter tools do NOT include Write, Edit, or Bash
if [ -f "$AGENT_FILE" ] && head -10 "$AGENT_FILE" | grep -qi 'tools:.*\(Write\|Edit\|Bash\)'; then
  fail "R-002d" "Agent frontmatter tools include forbidden Write/Edit/Bash"
else
  if [ -f "$AGENT_FILE" ]; then
    pass "R-002d" "Agent frontmatter tools exclude Write/Edit/Bash"
  else
    fail "R-002d" "Agent file missing — cannot verify tool exclusion"
  fi
fi

# R-002e: Frontmatter model field is inherit
if [ -f "$AGENT_FILE" ] && head -10 "$AGENT_FILE" | grep -q '^model: inherit$'; then
  pass "R-002e" "Agent frontmatter model: inherit"
else
  fail "R-002e" "Agent frontmatter model missing or not inherit"
fi

# R-002f: SKILL.md invokes via Task(correctless:architecture-compliance-reviewer)
if grep -q 'Task.*correctless:architecture-compliance-reviewer' "$PR_REVIEW_SKILL"; then
  pass "R-002f" "SKILL.md invokes agent via Task(correctless:architecture-compliance-reviewer)"
else
  fail "R-002f" "SKILL.md missing Task(correctless:architecture-compliance-reviewer) invocation"
fi

# ============================================================================
# R-003 [unit]: Agent prompt instructs extraction of PAT/ABS/TB entries,
#               diff-scoped checking, See-link following, trust model
# ============================================================================

section "R-003: Agent prompt extraction and diff-scoped checking"

# R-003a: Agent prompt instructs extracting PAT-xxx entries
if [ -f "$AGENT_FILE" ] && grep -qi 'PAT-xxx' "$AGENT_FILE"; then
  pass "R-003a" "Agent prompt references PAT-xxx entries"
else
  fail "R-003a" "Agent prompt missing PAT-xxx entry reference"
fi

# R-003b: Agent prompt instructs extracting ABS-xxx entries
if [ -f "$AGENT_FILE" ] && grep -qi 'ABS-xxx' "$AGENT_FILE"; then
  pass "R-003b" "Agent prompt references ABS-xxx entries"
else
  fail "R-003b" "Agent prompt missing ABS-xxx entry reference"
fi

# R-003c: Agent prompt instructs extracting TB-xxx entries
if [ -f "$AGENT_FILE" ] && grep -qi 'TB-xxx' "$AGENT_FILE"; then
  pass "R-003c" "Agent prompt references TB-xxx entries"
else
  fail "R-003c" "Agent prompt missing TB-xxx entry reference"
fi

# R-003d: Agent prompt instructs diff-scoped checking (findings reference diff files only)
if [ -f "$AGENT_FILE" ] && grep -qi 'PR diff\|diff.*files\|files.*present.*in.*diff\|diff-scoped' "$AGENT_FILE"; then
  pass "R-003d" "Agent prompt instructs diff-scoped checking"
else
  fail "R-003d" "Agent prompt missing diff-scoped checking instruction"
fi

# R-003e: Agent prompt instructs following See-links for index-only entries
if [ -f "$AGENT_FILE" ] && grep -qi 'See-link\|index-only' "$AGENT_FILE"; then
  pass "R-003e" "Agent prompt instructs following See-links for index-only entries"
else
  fail "R-003e" "Agent prompt missing See-link / index-only instruction"
fi

# R-003f: Agent prompt treats ARCHITECTURE.md as trusted data source
if [ -f "$AGENT_FILE" ] && grep -qi 'trusted data source\|human-authored\|human-curated' "$AGENT_FILE"; then
  pass "R-003f" "Agent prompt treats ARCHITECTURE.md as trusted data source"
else
  fail "R-003f" "Agent prompt missing trusted data source treatment for ARCHITECTURE.md"
fi

# R-003g: Agent trust model references workflow-gate (NOT sensitive-file-guard or TB-005)
if [ -f "$AGENT_FILE" ] && grep -qi 'workflow-gate\|phase restrictions' "$AGENT_FILE"; then
  pass "R-003g" "Agent trust model references workflow-gate or phase restrictions"
else
  fail "R-003g" "Agent trust model missing workflow-gate / phase restrictions reference"
fi

# R-003h: Agent trust model does NOT reference sensitive-file-guard as protection
if [ -f "$AGENT_FILE" ] && grep -qi 'sensitive-file-guard' "$AGENT_FILE"; then
  fail "R-003h" "Agent trust model incorrectly references sensitive-file-guard"
else
  if [ -f "$AGENT_FILE" ]; then
    pass "R-003h" "Agent trust model correctly omits sensitive-file-guard"
  else
    fail "R-003h" "Agent file missing — cannot verify trust model"
  fi
fi

# R-003i: Agent trust model does NOT reference TB-005 as protection mechanism
if [ -f "$AGENT_FILE" ] && grep -qi 'TB-005' "$AGENT_FILE"; then
  fail "R-003i" "Agent trust model incorrectly references TB-005"
else
  if [ -f "$AGENT_FILE" ]; then
    pass "R-003i" "Agent trust model correctly omits TB-005"
  else
    fail "R-003i" "Agent file missing — cannot verify TB-005 exclusion"
  fi
fi

# ============================================================================
# R-004 [unit]: Sub-entry exception handling (TB-NNNx pattern)
# ============================================================================

section "R-004: TB-xxx sub-entry exception handling"

# R-004a: Agent prompt references sub-entries for TB exception handling
if [ -f "$AGENT_FILE" ] && grep -qi 'sub-entry\|sub-entries\|scoped exception' "$AGENT_FILE"; then
  pass "R-004a" "Agent prompt references TB sub-entries for exception handling"
else
  fail "R-004a" "Agent prompt missing TB sub-entry exception handling"
fi

# R-004b: Agent prompt describes the TB-NNNx sub-entry identification pattern
if [ -f "$AGENT_FILE" ] && grep -qi 'TB-.*[0-9].*[a-z]\|TB-NNN\|TB-001a\|numeric.*portion.*parent' "$AGENT_FILE"; then
  pass "R-004b" "Agent prompt describes TB-NNNx sub-entry identification pattern"
else
  fail "R-004b" "Agent prompt missing TB-NNNx sub-entry pattern description"
fi

# R-004c: Agent prompt instructs not submitting findings that match documented exceptions
if [ -f "$AGENT_FILE" ] && grep -qi 'do not submit\|known exception.*not a violation\|not a violation.*known exception' "$AGENT_FILE"; then
  pass "R-004c" "Agent prompt instructs suppressing findings matching sub-entry exceptions"
else
  fail "R-004c" "Agent prompt missing instruction to suppress sub-entry exception findings"
fi

# ============================================================================
# R-005 [unit]: Dormant-signal fallback (PAT-019)
# ============================================================================

section "R-005: Dormant-signal fallback for missing ARCHITECTURE.md"

# R-005a: Agent prompt includes fallback for missing ARCHITECTURE.md
if [ -f "$AGENT_FILE" ] && grep -qi 'does not exist\|no.*architecture.*entries.*found\|architecture compliance.*skipped' "$AGENT_FILE"; then
  pass "R-005a" "Agent prompt includes dormant-signal fallback for missing ARCHITECTURE.md"
else
  fail "R-005a" "Agent prompt missing dormant-signal fallback for ARCHITECTURE.md"
fi

# R-005b: Agent prompt includes fallback for placeholder markers
if [ -f "$AGENT_FILE" ] && grep -qi 'placeholder.*markers\|PROJECT_NAME.*PLACEHOLDER\|{PROJECT_NAME}\|{PLACEHOLDER}' "$AGENT_FILE"; then
  pass "R-005b" "Agent prompt includes fallback for placeholder markers"
else
  fail "R-005b" "Agent prompt missing placeholder marker fallback"
fi

# R-005c: Agent prompt instructs zero findings when dormant
if [ -f "$AGENT_FILE" ] && grep -qi 'zero findings\|submit zero\|0 findings' "$AGENT_FILE"; then
  pass "R-005c" "Agent prompt instructs zero findings when dormant"
else
  fail "R-005c" "Agent prompt missing zero-findings-when-dormant instruction"
fi

# R-005d: Agent prompt prohibits inferring architecture when dormant
if [ -f "$AGENT_FILE" ] && grep -qi 'do not.*infer.*architecture\|not.*infer architecture\|carchitect.*job' "$AGENT_FILE"; then
  pass "R-005d" "Agent prompt prohibits inferring architecture when dormant"
else
  fail "R-005d" "Agent prompt missing prohibition on inferring architecture"
fi

# ============================================================================
# R-006 [unit]: Staleness computed by PARENT /cpr-review (not agent)
# ============================================================================

section "R-006: Staleness computed by parent /cpr-review"

# R-006a: SKILL.md contains staleness computation reference (git log for ARCHITECTURE.md)
if grep -qi 'git log.*ARCHITECTURE.md\|staleness.*ARCHITECTURE\|stale.*ARCHITECTURE' "$PR_REVIEW_SKILL"; then
  pass "R-006a" "SKILL.md contains staleness computation for ARCHITECTURE.md"
else
  fail "R-006a" "SKILL.md missing staleness computation for ARCHITECTURE.md"
fi

# R-006b: SKILL.md references git log for date comparison
if grep -qi "git log -1.*format.*ai.*ARCHITECTURE\|git log.*--format.*ARCHITECTURE" "$PR_REVIEW_SKILL"; then
  pass "R-006b" "SKILL.md references git log for ARCHITECTURE.md date"
else
  fail "R-006b" "SKILL.md missing git log date reference for ARCHITECTURE.md"
fi

# R-006c: Staleness warning uses LOW severity (not SUSPICIOUS)
if grep -qi 'LOW.*severity.*stale\|LOW-severity.*stale\|staleness.*LOW' "$PR_REVIEW_SKILL"; then
  pass "R-006c" "SKILL.md uses LOW severity for staleness warning"
else
  fail "R-006c" "SKILL.md missing LOW severity for staleness warning"
fi

# R-006d: Staleness suggests running /cupdate-arch
if grep -qi 'cupdate-arch.*stale\|stale.*cupdate-arch\|Consider running /cupdate-arch\|running.*/cupdate-arch' "$PR_REVIEW_SKILL"; then
  pass "R-006d" "SKILL.md suggests /cupdate-arch for staleness"
else
  fail "R-006d" "SKILL.md missing /cupdate-arch suggestion for staleness"
fi

# R-006e: Agent file does NOT contain git log references (agent has no Bash)
if [ -f "$AGENT_FILE" ] && grep -qi 'git log' "$AGENT_FILE"; then
  fail "R-006e" "Agent file incorrectly contains git log reference (agent has no Bash)"
else
  if [ -f "$AGENT_FILE" ]; then
    pass "R-006e" "Agent file correctly omits git log references"
  else
    fail "R-006e" "Agent file missing — cannot verify git log absence"
  fi
fi

# R-006f: Staleness computation is in SKILL.md, not delegated to agent
if grep -qi '30.*days\|staleness.*before.*spawn\|staleness.*prepends' "$PR_REVIEW_SKILL"; then
  pass "R-006f" "SKILL.md handles staleness computation before agent spawn"
else
  fail "R-006f" "SKILL.md missing 30-day staleness threshold"
fi

# ============================================================================
# R-007 [unit]: Four check types with calibration
# ============================================================================

section "R-007: Four check types in agent prompt"

# R-007a: Pattern compliance check type (PAT-xxx)
if [ -f "$AGENT_FILE" ] && grep -qi 'pattern compliance\|Pattern compliance' "$AGENT_FILE"; then
  pass "R-007a" "Agent prompt defines pattern compliance check type"
else
  fail "R-007a" "Agent prompt missing pattern compliance check type"
fi

# R-007b: Abstraction invariant check type (ABS-xxx)
if [ -f "$AGENT_FILE" ] && grep -qi 'abstraction invariant\|Abstraction invariant' "$AGENT_FILE"; then
  pass "R-007b" "Agent prompt defines abstraction invariant check type"
else
  fail "R-007b" "Agent prompt missing abstraction invariant check type"
fi

# R-007c: Trust boundary enforcement check type (TB-xxx)
if [ -f "$AGENT_FILE" ] && grep -qi 'trust boundary enforcement\|Trust boundary enforcement' "$AGENT_FILE"; then
  pass "R-007c" "Agent prompt defines trust boundary enforcement check type"
else
  fail "R-007c" "Agent prompt missing trust boundary enforcement check type"
fi

# R-007d: New pattern introduction check type
if [ -f "$AGENT_FILE" ] && grep -qi 'new pattern introduction\|New pattern introduction\|new pattern.*detection' "$AGENT_FILE"; then
  pass "R-007d" "Agent prompt defines new pattern introduction check type"
else
  fail "R-007d" "Agent prompt missing new pattern introduction check type"
fi

# R-007e: New pattern calibration — project-specific vs standard idioms
if [ -f "$AGENT_FILE" ] && grep -qi 'project-specific convention\|standard language idiom\|standard library usage\|framework convention' "$AGENT_FILE"; then
  pass "R-007e" "Agent prompt includes new pattern calibration criteria"
else
  fail "R-007e" "Agent prompt missing new pattern calibration criteria"
fi

# R-007f: New pattern findings are informational / LOW severity
if [ -f "$AGENT_FILE" ] && grep -qi 'informational.*LOW\|LOW.*severity.*new.pattern\|new.pattern.*LOW\|informational' "$AGENT_FILE"; then
  pass "R-007f" "Agent prompt marks new pattern findings as informational / LOW"
else
  fail "R-007f" "Agent prompt missing informational/LOW designation for new pattern findings"
fi

# ============================================================================
# R-008 [unit]: Finding format fields and default severities
# ============================================================================

section "R-008: Finding format and default severities"

# R-008a: Finding includes severity field
if [ -f "$AGENT_FILE" ] && grep -qi 'severity.*CRITICAL.*HIGH.*MEDIUM.*LOW\|CRITICAL.*HIGH.*MEDIUM.*LOW' "$AGENT_FILE"; then
  pass "R-008a" "Agent prompt specifies severity classification (CRITICAL/HIGH/MEDIUM/LOW)"
else
  fail "R-008a" "Agent prompt missing severity classification"
fi

# R-008b: Finding includes architecture_ref field
if [ -f "$AGENT_FILE" ] && grep -qi 'architecture_ref' "$AGENT_FILE"; then
  pass "R-008b" "Agent prompt specifies architecture_ref field in findings"
else
  fail "R-008b" "Agent prompt missing architecture_ref field"
fi

# R-008c: Finding includes file path reference
if [ -f "$AGENT_FILE" ] && grep -qi 'file path.*line\|file.*line reference\|file path and line' "$AGENT_FILE"; then
  pass "R-008c" "Agent prompt specifies file path and line reference in findings"
else
  fail "R-008c" "Agent prompt missing file path/line reference in findings"
fi

# R-008d: Finding includes description field
if [ -f "$AGENT_FILE" ] && grep -qi 'one-sentence description\|description.*violation\|description.*finding' "$AGENT_FILE"; then
  pass "R-008d" "Agent prompt specifies description in findings"
else
  fail "R-008d" "Agent prompt missing description in findings"
fi

# R-008e: Finding includes why-it-matters field
if [ -f "$AGENT_FILE" ] && grep -qi 'why it matters\|why-it-matters' "$AGENT_FILE"; then
  pass "R-008e" "Agent prompt specifies why-it-matters in findings"
else
  fail "R-008e" "Agent prompt missing why-it-matters in findings"
fi

# R-008f: Finding includes suggested fix field
if [ -f "$AGENT_FILE" ] && grep -qi 'suggested fix' "$AGENT_FILE"; then
  pass "R-008f" "Agent prompt specifies suggested fix in findings"
else
  fail "R-008f" "Agent prompt missing suggested fix in findings"
fi

# R-008g: TB-xxx violations default to at least HIGH severity
if [ -f "$AGENT_FILE" ] && grep -qi 'TB-xxx.*HIGH\|TB.*violation.*HIGH\|trust boundary.*HIGH\|TB.*default.*HIGH' "$AGENT_FILE"; then
  pass "R-008g" "Agent prompt sets TB-xxx violations to at least HIGH severity"
else
  fail "R-008g" "Agent prompt missing HIGH default severity for TB-xxx violations"
fi

# R-008h: PAT-xxx and ABS-xxx violations default to MEDIUM
if [ -f "$AGENT_FILE" ] && grep -qi 'PAT-xxx.*MEDIUM\|ABS-xxx.*MEDIUM\|PAT.*ABS.*default.*MEDIUM\|MEDIUM.*PAT.*ABS' "$AGENT_FILE"; then
  pass "R-008h" "Agent prompt sets PAT-xxx/ABS-xxx violations to MEDIUM default"
else
  fail "R-008h" "Agent prompt missing MEDIUM default severity for PAT-xxx/ABS-xxx"
fi

# R-008i: architecture_ref is null for new-pattern findings
if [ -f "$AGENT_FILE" ] && grep -qi 'null.*new.pattern\|new.pattern.*null\|architecture_ref.*null' "$AGENT_FILE"; then
  pass "R-008i" "Agent prompt allows null architecture_ref for new-pattern findings"
else
  fail "R-008i" "Agent prompt missing null architecture_ref for new-pattern findings"
fi

# ============================================================================
# R-009 [unit]: SKILL.md updated — Step 3 delegates to agent, allowed-tools,
#               Progress Visibility updated
# ============================================================================

section "R-009: SKILL.md updated for agent delegation"

# R-009a: Task(correctless:architecture-compliance-reviewer) in allowed-tools frontmatter
if head -10 "$PR_REVIEW_SKILL" | grep -q 'architecture-compliance-reviewer'; then
  pass "R-009a" "SKILL.md allowed-tools includes architecture-compliance-reviewer"
else
  fail "R-009a" "SKILL.md allowed-tools missing architecture-compliance-reviewer"
fi

# R-009b: Step 3 no longer has inline prose architecture checking (5 bullet points removed)
# The old Step 3 had "Pattern violations", "Convention violations", "Prohibition violations",
# "New patterns", "Component boundaries" as inline bullet points. These should be gone.
if grep -qi 'Pattern violations.*Do changes follow\|Convention violations.*Naming\|Prohibition violations.*Does the PR\|New patterns.*Does the PR introduce\|Component boundaries.*Do changes respect' "$PR_REVIEW_SKILL"; then
  fail "R-009b" "SKILL.md Step 3 still contains inline prose architecture checking"
else
  pass "R-009b" "SKILL.md Step 3 inline prose architecture checking removed"
fi

# R-009c: Progress Visibility task list references agent spawn instead of inline check
if grep -qi 'Spawn architecture.*agent\|spawn.*architecture compliance agent\|Architecture compliance agent' "$PR_REVIEW_SKILL"; then
  pass "R-009c" "Progress Visibility references agent spawn"
else
  fail "R-009c" "Progress Visibility missing agent spawn reference"
fi

# ============================================================================
# R-010 [unit]: Full Mode trust boundary + drift sections complementarity note
# ============================================================================

section "R-010: Full Mode complementarity note"

# R-010a: Trust Boundary Analysis section still exists in Full Mode
if grep -qi '### Trust Boundary Analysis' "$PR_REVIEW_SKILL"; then
  pass "R-010a" "Full Mode Trust Boundary Analysis section exists"
else
  fail "R-010a" "Full Mode Trust Boundary Analysis section missing"
fi

# R-010b: Drift Detection section still exists in Full Mode
if grep -qi '### Drift Detection' "$PR_REVIEW_SKILL"; then
  pass "R-010b" "Full Mode Drift Detection section exists"
else
  fail "R-010b" "Full Mode Drift Detection section missing"
fi

# R-010c: Complementarity note added referencing the agent
if grep -qi 'Architecture Compliance Agent.*mechanical\|mechanical.*TB-xxx.*PAT-xxx\|mechanical.*extraction.*checking\|agent.*mechanical.*checking\|semantic analysis beyond.*mechanical' "$PR_REVIEW_SKILL"; then
  pass "R-010c" "Complementarity note references agent's mechanical checking"
else
  fail "R-010c" "Complementarity note missing in Full Mode sections"
fi

# ============================================================================
# R-011 [unit]: Dep bump skips agent (agent is part of Step 3, dep bumps skip 3-8)
# ============================================================================

section "R-011: Dep bump PR skips agent via existing Step 3-8 skip"

# R-011a: Existing dep bump logic skips Steps 3-8 (or 3-9) — this implies agent is skipped
if grep -qi 'skip.*Steps 3.*8\|skip Steps 3-9\|replaces.*standard.*code review.*Steps 3' "$PR_REVIEW_SKILL"; then
  pass "R-011a" "Dep bump logic skips Steps 3-8/3-9 (agent inherently skipped)"
else
  fail "R-011a" "Dep bump skip logic for Steps 3-8 not found in SKILL.md"
fi

# ============================================================================
# R-012 [unit]: sync.sh propagates agent file via agents/*.md glob
# ============================================================================

section "R-012: sync.sh propagates agent file"

# R-012a: sync.sh has an agents/*.md glob loop
if grep -q 'agents/\*.md' sync.sh; then
  pass "R-012a" "sync.sh has agents/*.md propagation glob"
else
  fail "R-012a" "sync.sh missing agents/*.md propagation glob"
fi

# R-012b: Distribution copy exists (after sync)
if [ -f "$AGENT_DIST" ]; then
  pass "R-012b" "Distribution copy exists at $AGENT_DIST"
else
  fail "R-012b" "Distribution copy missing: $AGENT_DIST"
fi

# R-012c: Distribution copy matches source (if both exist)
if [ -f "$AGENT_FILE" ] && [ -f "$AGENT_DIST" ]; then
  if diff -q "$AGENT_FILE" "$AGENT_DIST" > /dev/null 2>&1; then
    pass "R-012c" "Agent source and distribution match"
  else
    fail "R-012c" "Agent source and distribution differ — run sync.sh"
  fi
else
  skip "R-012c" "Agent source or distribution missing — cannot verify parity"
fi

# R-012d: SKILL.md distribution parity
if [ -f "$PR_REVIEW_DIST" ]; then
  if diff -q "$PR_REVIEW_SKILL" "$PR_REVIEW_DIST" > /dev/null 2>&1; then
    pass "R-012d" "cpr-review SKILL.md source and distribution match"
  else
    fail "R-012d" "cpr-review SKILL.md source and distribution differ — run sync.sh"
  fi
else
  skip "R-012d" "cpr-review distribution SKILL.md not found"
fi

# ============================================================================
# R-013 [unit]: docs/skills/cpr-review.md updated with agent description
# ============================================================================

section "R-013: PR review docs updated"

# R-013a: Docs mention Architecture Compliance Agent
if grep -qi 'Architecture Compliance Agent\|architecture-compliance-reviewer\|architecture compliance.*agent' "$PR_REVIEW_DOCS"; then
  pass "R-013a" "PR review docs mention Architecture Compliance Agent"
else
  fail "R-013a" "PR review docs missing Architecture Compliance Agent mention"
fi

# R-013b: Docs describe the check types
if grep -qi 'pattern compliance\|abstraction invariant\|trust boundary enforcement\|new pattern' "$PR_REVIEW_DOCS"; then
  pass "R-013b" "PR review docs describe architecture check types"
else
  fail "R-013b" "PR review docs missing architecture check types"
fi

# R-013c: Docs describe dormant-signal fallback
if grep -qi 'dormant.*ARCHITECTURE\|ARCHITECTURE.*not exist.*skip\|no.*architecture.*entries.*skip\|zero findings' "$PR_REVIEW_DOCS"; then
  pass "R-013c" "PR review docs describe dormant-signal fallback"
else
  fail "R-013c" "PR review docs missing dormant-signal fallback description"
fi

# R-013d: Docs describe staleness warning
if grep -qi 'stale.*ARCHITECTURE\|staleness.*warning\|30.*days.*stale\|ARCHITECTURE.*stale' "$PR_REVIEW_DOCS"; then
  pass "R-013d" "PR review docs describe staleness warning"
else
  fail "R-013d" "PR review docs missing staleness warning description"
fi

# ============================================================================
# R-014 [unit]: ABS-010 consumer list includes skills/cpr-review/SKILL.md
# ============================================================================

section "R-014: ABS-010 consumer list updated"

# R-014a: ABS-010 in ARCHITECTURE.md lists cpr-review as consumer
if grep -A5 'ABS-010' "$ARCHITECTURE_MD" | grep -qi 'cpr-review\|skills/cpr-review/SKILL.md'; then
  pass "R-014a" "ABS-010 consumer list includes cpr-review"
else
  fail "R-014a" "ABS-010 consumer list missing cpr-review"
fi

# R-014b: ABS-010 consumer list references architecture-compliance-reviewer agent
if grep -A5 'ABS-010' "$ARCHITECTURE_MD" | grep -qi 'architecture-compliance-reviewer'; then
  pass "R-014b" "ABS-010 consumer list references architecture-compliance-reviewer"
else
  fail "R-014b" "ABS-010 consumer list missing architecture-compliance-reviewer reference"
fi

# ============================================================================
# R-015 [unit]: This test file exists and is in commands.test
# ============================================================================

section "R-015: Test file in commands.test"

# R-015a: This test file exists
if [ -f "tests/test-carchitect-phase4.sh" ]; then
  pass "R-015a" "Test file tests/test-carchitect-phase4.sh exists"
else
  fail "R-015a" "Test file tests/test-carchitect-phase4.sh missing"
fi

# R-015b: Test file is discoverable by commands.test in workflow-config.json
# DA-002: commands.test now uses glob-based discovery (test-*.sh)
if grep -q 'test-carchitect-phase4.sh' "$WORKFLOW_CONFIG" || jq -r '.commands.test // ""' "$WORKFLOW_CONFIG" 2>/dev/null | grep -qE 'test-\*\.sh'; then
  pass "R-015b" "test-carchitect-phase4.sh discoverable by commands.test"
else
  fail "R-015b" "test-carchitect-phase4.sh not registered in commands.test"
fi

# ============================================================================
# Summary
# ============================================================================

summary "carchitect-phase4-review-checks"
