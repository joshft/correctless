#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091,SC2016,SC2086
# Correctless — Adversarial Probe Framework Tests
# Enforces the adversarial-probe-framework spec invariants INV-001 through INV-014,
# PRH-001 through PRH-003, and BND-001 through BND-003.
#
# Run from repo root: bash tests/test-adversarial-probes.sh
#
# These are structural grep tests — they verify SKILL.md content declares
# the required probe round behavior. The probe round is internal orchestration
# (no workflow-advance.sh call, no new phase), so enforcement is via SKILL.md
# content presence checks.

source "$(dirname "${BASH_SOURCE[0]}")/test-helpers.sh"

# ============================================================================
# Constants — file paths
# ============================================================================

CTDD_SKILL="skills/ctdd/SKILL.md"
CTDD_DIST="correctless/skills/ctdd/SKILL.md"
CAUTO_SKILL="skills/cauto/SKILL.md"
CAUTO_DIST="correctless/skills/cauto/SKILL.md"

# ============================================================================
# Precondition — skill files exist
# ============================================================================

section "Preconditions"

if [ ! -f "$CTDD_SKILL" ]; then
  echo "FATAL: $CTDD_SKILL not found" >&2
  exit 2
fi

if [ ! -f "$CAUTO_SKILL" ]; then
  echo "FATAL: $CAUTO_SKILL not found" >&2
  exit 2
fi

pass "PRE-001" "ctdd SKILL.md exists"
pass "PRE-002" "cauto SKILL.md exists"

# ============================================================================
# Helper — extract probe round section from ctdd SKILL.md
# The probe round section should appear between QA and Mini-Audit.
# We look for a heading containing "Probe" between the QA phase and Mini-Audit.
# ============================================================================

# Get the body (strip YAML frontmatter)
CTDD_BODY="$(skill_body "$CTDD_SKILL")"

# ============================================================================
# INV-001: Probe round intensity gate
# The probe round MUST run at high+ intensity and MUST NOT run at standard.
# At high intensity: mutation and config-fuzz only.
# At critical intensity: all five probe types.
# ============================================================================

section "INV-001: Probe round intensity gate"

if echo "$CTDD_BODY" | grep -qi "probe.*high.*intensity\|high.*intensity.*probe\|probe round.*high"; then
  pass "INV-001a" "Probe round references high intensity requirement"
else
  fail "INV-001a" "Probe round does not reference high intensity requirement"
fi

if echo "$CTDD_BODY" | grep -qi "standard.*skip\|not.*run.*standard\|standard.*no.*probe\|MUST NOT.*standard"; then
  pass "INV-001b" "Probe round excluded at standard intensity"
else
  fail "INV-001b" "Probe round not excluded at standard intensity"
fi

if echo "$CTDD_BODY" | grep -qi "mutation.*config.*fuzz\|mutation.*fuzz\|config-fuzz"; then
  pass "INV-001c" "High intensity probe types listed (mutation, config-fuzz)"
else
  fail "INV-001c" "High intensity probe types not listed"
fi

if echo "$CTDD_BODY" | grep -qi "critical.*dependency.*sabotage\|critical.*permission.*strip\|critical.*rollback"; then
  pass "INV-001d" "Critical-only probe types referenced"
else
  fail "INV-001d" "Critical-only probe types not referenced"
fi

# ============================================================================
# INV-002: Worktree isolation
# Every probe agent MUST be spawned with isolation: "worktree" on Agent tool.
# ============================================================================

section "INV-002: Worktree isolation"

if echo "$CTDD_BODY" | grep -q 'isolation.*worktree\|isolation: "worktree"\|isolation:.*"worktree"'; then
  pass "INV-002a" "Worktree isolation keyword present in probe section"
else
  fail "INV-002a" "Worktree isolation keyword missing from probe section"
fi

# Must specifically reference Agent tool for probe/worktree dispatch (not generic agent refs)
if echo "$CTDD_BODY" | grep -qi "probe.*Agent tool\|Agent tool.*probe\|Agent tool.*worktree.*isolation\|spawn.*Agent.*isolation"; then
  pass "INV-002b" "Agent tool referenced for probe dispatch"
else
  fail "INV-002b" "Agent tool not referenced for probe dispatch"
fi

# ============================================================================
# INV-003: Time budget controls probe count
# Interactive: prompt user. Autonomous: 15 min high, 30 min critical.
# Budget formula: floor(budget_minutes * 60 / duration_estimate)
# ============================================================================

section "INV-003: Time budget"

if echo "$CTDD_BODY" | grep -qi "time budget\|budget.*minutes\|budget_minutes"; then
  pass "INV-003a" "Time budget concept present"
else
  fail "INV-003a" "Time budget concept missing"
fi

if echo "$CTDD_BODY" | grep -q "duration_estimate\|test_duration_estimate"; then
  pass "INV-003b" "Duration estimate referenced in budget formula"
else
  fail "INV-003b" "Duration estimate not referenced in budget formula"
fi

if echo "$CTDD_BODY" | grep -q "15.*minutes\|15 min"; then
  pass "INV-003c" "Autonomous default budget (15 min high) present"
else
  fail "INV-003c" "Autonomous default budget (15 min high) missing"
fi

# ============================================================================
# INV-004: Mutation probe semantics
# One mutation per worktree, semantically meaningful, uses commands.test.
# ============================================================================

section "INV-004: Mutation probe semantics"

if echo "$CTDD_BODY" | grep -qi "one.*mutation.*per.*worktree\|exactly one.*modification\|single.*mutation"; then
  pass "INV-004a" "Single mutation per worktree constraint present"
else
  fail "INV-004a" "Single mutation per worktree constraint missing"
fi

# Match mutation-specific terminology that would appear in the probe section
if echo "$CTDD_BODY" | grep -qi "operator swap.*guard removal\|operator.*swap.*boundary.*change\|mutation.*operator.*swap"; then
  pass "INV-004b" "Mutation types described (operator swap, guard removal, etc.)"
else
  fail "INV-004b" "Mutation types not described"
fi

# Must reference commands.test specifically in the probe context (run test suite in worktree)
if echo "$CTDD_BODY" | grep -qi "probe.*commands\.test\|worktree.*commands\.test\|run.*commands\.test.*worktree\|mutation.*test.*command"; then
  pass "INV-004c" "Probe uses commands.test from config"
else
  fail "INV-004c" "Probe does not reference commands.test in probe context"
fi

# ============================================================================
# INV-005: Config/input fuzz probe semantics
# Targets input surfaces in changed files, generates edge-case inputs.
# ============================================================================

section "INV-005: Config/input fuzz probe semantics"

if echo "$CTDD_BODY" | grep -qi "input.*surface\|config.*fuzz\|edge-case.*input\|fuzz.*input"; then
  pass "INV-005a" "Config-fuzz probe targets input surfaces"
else
  fail "INV-005a" "Config-fuzz probe input surface targeting missing"
fi

# Must mention several edge-case types together (not just "null" in isolation)
if echo "$CTDD_BODY" | grep -qi "empty.*string.*null\|malformed.*structure\|unicode.*edge\|edge-case.*input"; then
  pass "INV-005b" "Edge-case input types described"
else
  fail "INV-005b" "Edge-case input types not described"
fi

# ============================================================================
# INV-006: Critical-only probes gate
# Dependency sabotage, permission stripping, rollback simulation at critical only.
# ============================================================================

section "INV-006: Critical-only probes gate"

if echo "$CTDD_BODY" | grep -qi "dependency.*sabotage"; then
  pass "INV-006a" "Dependency sabotage probe type defined"
else
  fail "INV-006a" "Dependency sabotage probe type missing"
fi

if echo "$CTDD_BODY" | grep -qi "permission.*strip"; then
  pass "INV-006b" "Permission stripping probe type defined"
else
  fail "INV-006b" "Permission stripping probe type missing"
fi

if echo "$CTDD_BODY" | grep -qi "rollback.*simulation"; then
  pass "INV-006c" "Rollback simulation probe type defined"
else
  fail "INV-006c" "Rollback simulation probe type missing"
fi

# Must specifically mention critical-only in context of probes (not findings or severity)
if echo "$CTDD_BODY" | grep -qi "critical.*intensity.*probe\|critical.*only.*probe\|probe.*critical.*only\|critical.*only.*activate"; then
  pass "INV-006d" "Critical-only gate for these probe types"
else
  fail "INV-006d" "Critical-only gate not stated"
fi

# ============================================================================
# INV-007: Surviving-probe test generation
# Test-gen agent gets spec + probe description + target file, NOT worktree path.
# ============================================================================

section "INV-007: Surviving-probe test generation"

if echo "$CTDD_BODY" | grep -qi "test.*generation\|generate.*test.*survivor\|killing test\|test.*kill.*mutant"; then
  pass "INV-007a" "Test generation for survivors mentioned"
else
  fail "INV-007a" "Test generation for survivors not mentioned"
fi

if echo "$CTDD_BODY" | grep -qi "MUST NOT.*worktree path\|not.*receive.*worktree\|without.*worktree path"; then
  pass "INV-007b" "Test-gen agent explicitly excluded from worktree path"
else
  fail "INV-007b" "Test-gen agent worktree path exclusion not stated"
fi

if echo "$CTDD_BODY" | grep -qi "one attempt\|single attempt\|generation fails.*finding"; then
  pass "INV-007c" "Single attempt for test generation (no convergence loop)"
else
  fail "INV-007c" "Single attempt constraint not stated"
fi

# ============================================================================
# INV-008: Probe results artifact (incremental writes)
# File at .correctless/artifacts/probe-results-{branch-slug}.json
# Schema with schema_version, probes array, incremental writes.
# ============================================================================

section "INV-008: Probe results artifact"

if echo "$CTDD_BODY" | grep -q "probe-results-.*\.json\|probe-results.*branch.*json"; then
  pass "INV-008a" "Probe results artifact path defined"
else
  fail "INV-008a" "Probe results artifact path not defined"
fi

if echo "$CTDD_BODY" | grep -q "schema_version"; then
  pass "INV-008b" "Schema version field present"
else
  fail "INV-008b" "Schema version field not present"
fi

if echo "$CTDD_BODY" | grep -qi "incremental\|as each probe completes\|write.*incrementally"; then
  pass "INV-008c" "Incremental write instruction present"
else
  fail "INV-008c" "Incremental write instruction missing"
fi

if echo "$CTDD_BODY" | grep -q '"outcome"\|outcome.*killed\|survived\|timed_out'; then
  pass "INV-008d" "Probe outcome enum values present (killed/survived/timed_out)"
else
  fail "INV-008d" "Probe outcome enum values missing"
fi

# ============================================================================
# INV-009: Pipeline position and test-gen phase
# Probe round after QA, before mini-audit. No workflow-advance.sh call.
# Test-gen commits deferred to tdd-audit phase.
# ============================================================================

section "INV-009: Pipeline position"

# Verify probe section appears between QA completion and Mini-Audit heading
QA_LINE=$(echo "$CTDD_BODY" | grep -n "no BLOCKING findings" | tail -1 | cut -d: -f1)
MINI_AUDIT_LINE=$(echo "$CTDD_BODY" | grep -n "## Phase: Mini-Audit" | head -1 | cut -d: -f1)
PROBE_LINE=$(echo "$CTDD_BODY" | grep -ni "probe round\|## .*Probe" | head -1 | cut -d: -f1)

if [ -n "$PROBE_LINE" ] && [ -n "$QA_LINE" ] && [ -n "$MINI_AUDIT_LINE" ]; then
  if [ "$PROBE_LINE" -gt "$QA_LINE" ] && [ "$PROBE_LINE" -lt "$MINI_AUDIT_LINE" ]; then
    pass "INV-009a" "Probe section positioned between QA and mini-audit"
  else
    fail "INV-009a" "Probe section NOT between QA and mini-audit (probe:$PROBE_LINE qa:$QA_LINE mini:$MINI_AUDIT_LINE)"
  fi
else
  fail "INV-009a" "Could not locate probe, QA-done, or mini-audit section markers"
fi

# Must specifically document probe round as internal orchestration (no phase transition)
if echo "$CTDD_BODY" | grep -qi "probe.*internal orchestration\|probe.*not.*pipeline step\|probe.*no.*phase transition\|probe.*does not.*workflow-advance"; then
  pass "INV-009b" "Probe round documented as internal orchestration (no phase transition)"
else
  fail "INV-009b" "Probe round not documented as internal orchestration"
fi

if echo "$CTDD_BODY" | grep -qi "tdd-audit.*commit\|deferred.*tdd-audit\|commit.*during.*mini-audit\|test-gen.*deferred"; then
  pass "INV-009c" "Test-gen commits deferred to tdd-audit phase"
else
  fail "INV-009c" "Test-gen commit deferral not stated"
fi

# ============================================================================
# INV-010: Parallel probe dispatch
# "Dispatch all probes in a single message"
# ============================================================================

section "INV-010: Parallel probe dispatch"

# Must specifically mention probes dispatched in parallel/single message
if echo "$CTDD_BODY" | grep -qi "probes.*single message\|probes.*parallel\|dispatch.*probes.*parallel\|all probes.*single message"; then
  pass "INV-010" "Parallel dispatch instruction present"
else
  fail "INV-010" "Parallel dispatch instruction missing"
fi

# ============================================================================
# INV-011: Probe targets from feature diff (base branch derived)
# Uses git symbolic-ref refs/remotes/origin/HEAD, not hardcoded "main"
# ============================================================================

section "INV-011: Base branch derivation"

if echo "$CTDD_BODY" | grep -q "git symbolic-ref\|symbolic-ref.*refs/remotes/origin/HEAD"; then
  pass "INV-011a" "Base branch derived via git symbolic-ref"
else
  fail "INV-011a" "Base branch derivation via git symbolic-ref missing"
fi

# Must specifically mention probe targets from changed files (not generic mini-audit diff usage)
if echo "$CTDD_BODY" | grep -qi "probe.*changed.*files\|probe.*target.*diff\|mutation.*target.*changed\|target.*files.*changed.*branch"; then
  pass "INV-011b" "Probes target changed files from feature diff"
else
  fail "INV-011b" "Probe targeting of changed files not stated"
fi

# ============================================================================
# INV-012: Progress visibility during probe round
# Must announce start, per-probe completion, and summary.
# ============================================================================

section "INV-012: Progress visibility"

if echo "$CTDD_BODY" | grep -qi "Spawning.*probes\|spawning.*probe"; then
  pass "INV-012a" "Probe round start announcement pattern present"
else
  fail "INV-012a" "Probe round start announcement pattern missing"
fi

if echo "$CTDD_BODY" | grep -qi "Probe.*complete\|probe.*killed\|probe.*survived"; then
  pass "INV-012b" "Per-probe completion announcement pattern present"
else
  fail "INV-012b" "Per-probe completion announcement pattern missing"
fi

# Must specifically announce probe round completion with kill/survive stats
if echo "$CTDD_BODY" | grep -qi "Probe round complete\|probe.*complete.*killed.*survived\|probes.*killed.*survived"; then
  pass "INV-012c" "Probe round summary announcement pattern present"
else
  fail "INV-012c" "Probe round summary announcement pattern missing"
fi

# ============================================================================
# INV-013: ABS-010 exception for inline probe prompts
# Must document the exception with rationale.
# ============================================================================

section "INV-013: ABS-010 exception"

if echo "$CTDD_BODY" | grep -qi "ABS-010.*exception\|exception.*ABS-010"; then
  pass "INV-013a" "ABS-010 exception documented"
else
  fail "INV-013a" "ABS-010 exception not documented"
fi

if echo "$CTDD_BODY" | grep -qi "Agent tool.*isolation.*worktree\|worktree.*requires.*Agent\|isolation.*worktree.*Agent tool\|Agent.*required.*isolation"; then
  pass "INV-013b" "ABS-010 exception rationale present (Agent tool required for worktree)"
else
  fail "INV-013b" "ABS-010 exception rationale missing"
fi

# ============================================================================
# INV-014: TB-004c allowlist modification for probe results
# cauto SKILL.md Step 8.1 must include probe-results path.
# Step 8.2 must exclude probe results from unstaging.
# ============================================================================

section "INV-014: TB-004c allowlist (cauto SKILL.md)"

CAUTO_BODY="$(skill_body "$CAUTO_SKILL")"

if echo "$CAUTO_BODY" | grep -q "probe-results"; then
  pass "INV-014a" "Probe results path in cauto Step 8.1 allowlist"
else
  fail "INV-014a" "Probe results path NOT in cauto Step 8.1 allowlist"
fi

if echo "$CAUTO_BODY" | grep -qi "probe-results.*exception\|exclude.*probe-results\|except.*probe-results\|probe-results.*exclude"; then
  pass "INV-014b" "Step 8.2 excludes probe results from unstaging"
else
  fail "INV-014b" "Step 8.2 does not exclude probe results from unstaging"
fi

# ============================================================================
# PRH-001: No probe modifications in main working tree
# All modifications in isolated worktrees only.
# ============================================================================

section "PRH-001: No main tree modifications"

if echo "$CTDD_BODY" | grep -qi "never.*modify.*main.*tree\|main.*tree.*untouched\|exclusively.*worktree\|worktree.*only"; then
  pass "PRH-001" "Main working tree protection stated"
else
  fail "PRH-001" "Main working tree protection not stated"
fi

# ============================================================================
# PRH-002: No probe round at standard intensity
# ============================================================================

section "PRH-002: No probe at standard"

# Already partially tested by INV-001b, but PRH-002 requires explicit prohibition
if echo "$CTDD_BODY" | grep -qi "MUST NOT.*standard\|never.*standard.*intensity.*probe\|skip.*probe.*standard\|standard.*skip.*probe"; then
  pass "PRH-002" "Explicit prohibition of probe round at standard intensity"
else
  fail "PRH-002" "No explicit prohibition of probe round at standard intensity"
fi

# ============================================================================
# PRH-003: Probe round must not block pipeline on failure
# Failure -> continue to mini-audit. Advisory only.
# ============================================================================

section "PRH-003: Non-blocking on failure"

# Must specifically mention probe failure -> continue to mini-audit (not generic "advisory")
if echo "$CTDD_BODY" | grep -qi "probe.*fail.*continue\|probe.*advisory\|probe.*non-blocking\|probe.*fallback\|probe.*infrastructure.*fail"; then
  pass "PRH-003" "Probe round failure fallback to mini-audit present"
else
  fail "PRH-003" "Probe round failure fallback not stated"
fi

# ============================================================================
# BND-001: Empty diff
# Skip probe round with message when no changed files.
# ============================================================================

section "BND-001: Empty diff boundary"

if echo "$CTDD_BODY" | grep -qi "no.*changed.*files.*skip\|empty.*diff.*skip\|skip.*probe.*no.*changed"; then
  pass "BND-001" "Empty diff skip behavior documented"
else
  fail "BND-001" "Empty diff skip behavior not documented"
fi

# ============================================================================
# BND-002: Budget yields zero or one probe
# Zero: skip. One: warn.
# ============================================================================

section "BND-002: Budget boundary"

if echo "$CTDD_BODY" | grep -qi "budget.*zero.*skip\|budget.*small\|zero.*probe.*skip\|0.*skip"; then
  pass "BND-002a" "Zero-probe budget skip behavior documented"
else
  fail "BND-002a" "Zero-probe budget skip behavior not documented"
fi

if echo "$CTDD_BODY" | grep -qi "1.*probe.*warn\|single.*probe.*warn\|one.*probe.*warn\|budget.*1.*warn"; then
  pass "BND-002b" "Single-probe budget warning documented"
else
  fail "BND-002b" "Single-probe budget warning not documented"
fi

# ============================================================================
# BND-003: Worktree creation failure
# Report and continue to mini-audit.
# ============================================================================

section "BND-003: Worktree creation failure"

if echo "$CTDD_BODY" | grep -qi "worktree.*fail\|worktree.*creation.*fail\|fail.*worktree"; then
  pass "BND-003" "Worktree creation failure handling documented"
else
  fail "BND-003" "Worktree creation failure handling not documented"
fi

# ============================================================================
# Autonomous defaults: AD-004, AD-005, AD-006 in canonical section
# Must appear in the ## Autonomous Defaults section of ctdd SKILL.md.
# ============================================================================

section "Autonomous Defaults (AD-004/005/006)"

# Extract the Autonomous Defaults section
AD_SECTION=$(echo "$CTDD_BODY" | sed -n '/^## Autonomous Defaults/,/^## /p' | head -n -1)

if echo "$AD_SECTION" | grep -q "AD-004"; then
  pass "AD-004" "AD-004 (time budget default) in Autonomous Defaults section"
else
  fail "AD-004" "AD-004 missing from Autonomous Defaults section"
fi

if echo "$AD_SECTION" | grep -q "AD-005"; then
  pass "AD-005" "AD-005 (probe failure fallback) in Autonomous Defaults section"
else
  fail "AD-005" "AD-005 missing from Autonomous Defaults section"
fi

if echo "$AD_SECTION" | grep -q "AD-006"; then
  pass "AD-006" "AD-006 (test-gen auto-commit) in Autonomous Defaults section"
else
  fail "AD-006" "AD-006 missing from Autonomous Defaults section"
fi

# ============================================================================
# Distribution copy sync — ctdd
# The distribution copy at correctless/skills/ctdd/SKILL.md must match.
# ============================================================================

section "Distribution copy sync"

if [ -f "$CTDD_DIST" ]; then
  if diff -q "$CTDD_SKILL" "$CTDD_DIST" >/dev/null 2>&1; then
    pass "SYNC-001" "ctdd SKILL.md distribution copy in sync"
  else
    fail "SYNC-001" "ctdd SKILL.md distribution copy OUT OF SYNC"
  fi
else
  skip "SYNC-001" "ctdd distribution copy not present (correctless/skills/ctdd/SKILL.md)"
fi

if [ -f "$CAUTO_DIST" ]; then
  if diff -q "$CAUTO_SKILL" "$CAUTO_DIST" >/dev/null 2>&1; then
    pass "SYNC-002" "cauto SKILL.md distribution copy in sync"
  else
    fail "SYNC-002" "cauto SKILL.md distribution copy OUT OF SYNC"
  fi
else
  skip "SYNC-002" "cauto distribution copy not present (correctless/skills/cauto/SKILL.md)"
fi

# ============================================================================
# Pipeline diagram update — probe appears in the narrated pipeline
# The Progress Visibility or pipeline description should mention probe.
# ============================================================================

section "Pipeline references"

if echo "$CTDD_BODY" | grep -qi "RED.*GREEN.*QA.*probe\|QA.*probe.*mini-audit\|probe.*mini-audit"; then
  pass "PIPE-001" "Probe round referenced in pipeline progression"
else
  fail "PIPE-001" "Probe round not referenced in pipeline progression"
fi

# ============================================================================
# Summary
# ============================================================================

summary "Adversarial Probe Framework"
