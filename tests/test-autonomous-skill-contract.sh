#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091,SC2086
# Correctless — Autonomous Skill Contract test suite
# Tests spec rules R-001 through R-014 from
# .correctless/specs/autonomous-skill-contract.md
#
# RED phase: these tests MUST FAIL — implementation does not exist yet.
# Run from repo root: bash tests/test-autonomous-skill-contract.sh

source "$(dirname "${BASH_SOURCE[0]}")/test-helpers.sh"

# ============================================================================
# Constants
# ============================================================================

SKILLS_DIR="$REPO_DIR/skills"
CAUTO_SKILL="$SKILLS_DIR/cauto/SKILL.md"

# ============================================================================
# Helpers (extract_frontmatter, get_frontmatter_field, parse_tools_list
# are provided by test-helpers.sh)
# ============================================================================

has_section() {
  local file="$1" heading="$2"
  grep -q "^## ${heading}" "$file" 2>/dev/null
}

# Get all distribution SKILL.md files via glob (R-010: no hardcoded count)
get_distribution_skills() {
  local skill_files
  skill_files=()
  for f in "$SKILLS_DIR"/*/SKILL.md; do
    [ -f "$f" ] && skill_files+=("$f")
  done
  echo "${skill_files[@]}"
}

# ============================================================================
# R-001 [unit]: Every SKILL.md must have interaction_mode in frontmatter
# ============================================================================

section "R-001: interaction_mode frontmatter field"

skill_count=0
skill_with_mode=0
skill_without_mode=""

for skill_file in $SKILLS_DIR/*/SKILL.md; do
  [ -f "$skill_file" ] || continue
  skill_name=$(basename "$(dirname "$skill_file")")

  # Skip _shared — not a skill
  [ "$skill_name" = "_shared" ] && continue

  skill_count=$((skill_count + 1))

  mode=$(get_frontmatter_field "$skill_file" "interaction_mode")
  if [ -n "$mode" ]; then
    # Validate the value is one of the three allowed values
    case "$mode" in
      autonomous|interactive|hybrid)
        skill_with_mode=$((skill_with_mode + 1))
        ;;
      *)
        fail "R-001" "$skill_name has invalid interaction_mode value: $mode (must be autonomous, interactive, or hybrid)"
        ;;
    esac
  else
    skill_without_mode="${skill_without_mode}${skill_name} "
  fi
done

if [ "$skill_with_mode" -eq "$skill_count" ] && [ "$skill_count" -gt 0 ]; then
  pass "R-001" "All $skill_count distribution SKILL.md files have valid interaction_mode"
else
  fail "R-001" "$((skill_count - skill_with_mode))/$skill_count skills missing interaction_mode: ${skill_without_mode}"
fi

# ============================================================================
# R-002 [unit]: autonomous skills must have ## Autonomous Defaults section
# ============================================================================

section "R-002: autonomous skills have Autonomous Defaults section"

r002_checked=0
r002_passed=0

for skill_file in $SKILLS_DIR/*/SKILL.md; do
  [ -f "$skill_file" ] || continue
  skill_name=$(basename "$(dirname "$skill_file")")
  [ "$skill_name" = "_shared" ] && continue

  mode=$(get_frontmatter_field "$skill_file" "interaction_mode")
  [ "$mode" = "autonomous" ] || continue

  r002_checked=$((r002_checked + 1))

  if has_section "$skill_file" "Autonomous Defaults"; then
    # Check that the section has at least one AD-xxx entry
    ad_count=$(grep -c 'AD-[0-9]\{3\}' "$skill_file" 2>/dev/null || echo 0)
    if [ "$ad_count" -gt 0 ]; then
      pass "R-002" "$skill_name has Autonomous Defaults section with $ad_count AD-xxx entries"
      r002_passed=$((r002_passed + 1))
    else
      fail "R-002" "$skill_name has Autonomous Defaults section but no AD-xxx entries"
    fi
  else
    fail "R-002" "$skill_name (interaction_mode: autonomous) missing ## Autonomous Defaults section"
  fi
done

if [ "$r002_checked" -eq 0 ]; then
  fail "R-002" "No skills with interaction_mode: autonomous found (expected at least one)"
fi

# ============================================================================
# R-003 [unit]: interactive skills must NOT have ## Autonomous Defaults
# ============================================================================

section "R-003: interactive skills have no Autonomous Defaults section"

r003_checked=0

for skill_file in $SKILLS_DIR/*/SKILL.md; do
  [ -f "$skill_file" ] || continue
  skill_name=$(basename "$(dirname "$skill_file")")
  [ "$skill_name" = "_shared" ] && continue

  mode=$(get_frontmatter_field "$skill_file" "interaction_mode")
  [ "$mode" = "interactive" ] || continue

  r003_checked=$((r003_checked + 1))

  if has_section "$skill_file" "Autonomous Defaults"; then
    fail "R-003" "$skill_name (interaction_mode: interactive) must NOT have ## Autonomous Defaults section"
  else
    pass "R-003" "$skill_name does not have Autonomous Defaults section"
  fi
done

if [ "$r003_checked" -eq 0 ]; then
  fail "R-003" "No skills with interaction_mode: interactive found (expected at least one)"
fi

# ============================================================================
# R-004 [unit]: hybrid skills have Autonomous Defaults AND escalate: always
# ============================================================================

section "R-004: hybrid skills have Autonomous Defaults with escalate: always"

r004_checked=0

for skill_file in $SKILLS_DIR/*/SKILL.md; do
  [ -f "$skill_file" ] || continue
  skill_name=$(basename "$(dirname "$skill_file")")
  [ "$skill_name" = "_shared" ] && continue

  mode=$(get_frontmatter_field "$skill_file" "interaction_mode")
  [ "$mode" = "hybrid" ] || continue

  r004_checked=$((r004_checked + 1))

  if ! has_section "$skill_file" "Autonomous Defaults"; then
    fail "R-004" "$skill_name (interaction_mode: hybrid) missing ## Autonomous Defaults section"
    continue
  fi

  # Check for at least one escalate: always marker
  escalate_count=$(grep -c 'escalate: always' "$skill_file" 2>/dev/null || echo 0)
  if [ "$escalate_count" -gt 0 ]; then
    pass "R-004" "$skill_name has Autonomous Defaults with $escalate_count escalate: always entries"
  else
    fail "R-004" "$skill_name (interaction_mode: hybrid) has Autonomous Defaults but no escalate: always entries"
  fi
done

if [ "$r004_checked" -eq 0 ]; then
  # hybrid skills are expected but not required to exist; skip is informational
  skip "R-004" "No skills with interaction_mode: hybrid found"
fi

# ============================================================================
# R-005 [integration]: /cauto dispatch includes mode: autonomous
# ============================================================================

section "R-005: /cauto dispatch includes mode: autonomous"

# R-005: cauto SKILL.md must document that Task prompt includes mode: autonomous
if grep -q 'mode: autonomous' "$CAUTO_SKILL" 2>/dev/null; then
  pass "R-005a" "cauto SKILL.md references 'mode: autonomous'"
else
  fail "R-005a" "cauto SKILL.md does not reference 'mode: autonomous'"
fi

# R-005: must specify first 10 lines constraint
if grep -qi 'first 10 lines\|first ten lines' "$CAUTO_SKILL" 2>/dev/null; then
  pass "R-005b" "cauto specifies mode: autonomous in first 10 lines of Task prompt"
else
  fail "R-005b" "cauto does not specify first-10-lines placement for mode: autonomous"
fi

# R-005: must document fail-open behavior (absent = interactive)
if grep -qi 'fail.open\|absent.*interactive\|not present.*interactive' "$CAUTO_SKILL" 2>/dev/null; then
  pass "R-005c" "cauto documents fail-open behavior for mode detection"
else
  fail "R-005c" "cauto does not document fail-open behavior for mode: autonomous detection"
fi

# ============================================================================
# R-006 [unit]: /cauto is sole writer of autonomous-decisions JSONL (ABS-030)
# ============================================================================

section "R-006: ABS-030 sole-writer contract for autonomous-decisions JSONL"

# R-006a: cauto must reference autonomous-decisions JSONL
if grep -q 'autonomous-decisions-' "$CAUTO_SKILL" 2>/dev/null; then
  pass "R-006a" "cauto references autonomous-decisions-{branch_slug}.jsonl"
else
  fail "R-006a" "cauto does not reference autonomous-decisions JSONL"
fi

# R-006b: cauto must document the JSONL entry schema (skill, decision_id, etc.)
r006_fields=0
for field in "skill" "decision_id" "default_applied" "rationale" "timestamp" "escalation_deferred"; do
  if grep -q "$field" "$CAUTO_SKILL" 2>/dev/null; then
    r006_fields=$((r006_fields + 1))
  fi
done

if [ "$r006_fields" -ge 5 ]; then
  pass "R-006b" "cauto documents JSONL entry schema ($r006_fields/6 required fields found)"
else
  fail "R-006b" "cauto missing JSONL entry schema fields ($r006_fields/6 found)"
fi

# R-006c: cauto must mention sole writer / sole-writer / ABS-030
if grep -qi 'sole.writer\|ABS-030' "$CAUTO_SKILL" 2>/dev/null; then
  pass "R-006c" "cauto references sole-writer contract or ABS-030"
else
  fail "R-006c" "cauto does not reference sole-writer or ABS-030 for autonomous-decisions JSONL"
fi

# R-006d-cchores [positive]: cchores is allowlisted (like cauto) NOT by a blanket
# exemption but because it is verified to write only THROUGH
# autonomous-decision-writer.sh. A blanket `continue` would let cchores hold a
# direct-write to autonomous-decisions (its allowed-tools include
# `Write(.correctless/artifacts/*)`) without detection — the AP-022 dead-exemption
# shape. So before exempting it from the loop's negative check below, assert the
# POSITIVE write-through contract here: cchores SKILL.md (a) REFERENCES
# autonomous-decision-writer.sh, AND (b) contains NO direct-write pattern to an
# autonomous-decisions artifact (no Write(...autonomous-decisions...), no
# >>/>/tee redirect to autonomous-decisions-*). Mirrors cauto's R-006c/R-006e
# positive contract. Assertions use here-strings (not printf|grep) per #186/AP-033.
CCHORES_SKILL_FILE="$SKILLS_DIR/cchores/SKILL.md"
if [ -f "$CCHORES_SKILL_FILE" ]; then
  CCHORES_BODY="$(cat "$CCHORES_SKILL_FILE")"

  # (a) must reference the sole-writer script
  if grep -qF 'autonomous-decision-writer.sh' <<<"$CCHORES_BODY"; then
    pass "R-006d-cchores-1" "cchores references autonomous-decision-writer.sh (writes THROUGH the sole writer)"
  else
    fail "R-006d-cchores-1" "cchores does NOT reference autonomous-decision-writer.sh (allowlist exemption unjustified)"
  fi

  # (b) must NOT contain any direct-write to autonomous-decisions: neither a
  # Write(...autonomous-decisions...) tool reference, nor a >>/>/tee redirect to
  # an autonomous-decisions-* file. The writer-script invocation
  # (autonomous-decision-writer.sh) is the legitimate path and is excluded.
  cchores_directwrite=""
  # Tool-level direct write: Write(...autonomous-decisions...)
  if grep -qiE 'Write\([^)]*autonomous-decisions' <<<"$CCHORES_BODY"; then
    cchores_directwrite="${cchores_directwrite}Write(autonomous-decisions) "
  fi
  # Redirect/tee to an autonomous-decisions-* file (NOT the writer script).
  # Exclude lines mentioning the writer script so the legitimate invocation
  # (which may pipe into the script) is not misflagged.
  while IFS= read -r _adline; do
    [ -n "$_adline" ] || continue
    case "$_adline" in
      *autonomous-decision-writer*) continue ;;  # the legitimate writer path
    esac
    if grep -qiE '(>>|>|tee)[[:space:]]*[^|]*autonomous-decisions-' <<<"$_adline"; then
      cchores_directwrite="${cchores_directwrite}redirect "
    fi
  done < <(grep -niE 'autonomous-decisions-' <<<"$CCHORES_BODY")

  if [ -z "$cchores_directwrite" ]; then
    pass "R-006d-cchores-2" "cchores has NO direct-write to autonomous-decisions (no Write(...), no >>/>/tee redirect — write-through only)"
  else
    fail "R-006d-cchores-2" "cchores contains a direct-write to autonomous-decisions: $cchores_directwrite(must write only THROUGH autonomous-decision-writer.sh)"
  fi
else
  fail "R-006d-cchores-1" "skills/cchores/SKILL.md not found (cannot verify write-through contract)"
  fail "R-006d-cchores-2" "skills/cchores/SKILL.md not found (cannot verify direct-write absence)"
fi

# R-006d: Skills must NOT write to autonomous-decisions JSONL directly
r006_violators=""
for skill_file in $SKILLS_DIR/*/SKILL.md; do
  [ -f "$skill_file" ] || continue
  skill_name=$(basename "$(dirname "$skill_file")")
  [ "$skill_name" = "_shared" ] && continue
  [ "$skill_name" = "cauto" ] && continue
  # cchores is an authorized invoker of autonomous-decision-writer.sh (ABS-030
  # revised, R-006d allowlist). It is NOT blanket-exempted: the positive
  # write-through contract is asserted in R-006d-cchores-1/2 ABOVE. The loop skip
  # here only prevents the negative-check from double-flagging the same skill the
  # positive block already verified.
  [ "$skill_name" = "cchores" ] && continue

  if grep -q 'autonomous-decisions-' "$skill_file" 2>/dev/null; then
    # Check if it's a write reference vs a read reference
    if grep -qi 'write.*autonomous-decisions\|append.*autonomous-decisions\|Write.*autonomous-decisions' "$skill_file" 2>/dev/null; then
      r006_violators="${r006_violators}${skill_name} "
    fi
  fi
done

if [ -z "$r006_violators" ]; then
  pass "R-006d" "No non-cauto skills write to autonomous-decisions JSONL (cchores write-through verified separately)"
else
  fail "R-006d" "Skills writing to autonomous-decisions JSONL: $r006_violators"
fi

# R-006e: Verify JSONL growth check is documented in cauto
if grep -qi 'verif.*JSONL.*growth\|JSONL.*growth.*verif\|verify.*growth\|growth.*after.*skill' "$CAUTO_SKILL" 2>/dev/null; then
  pass "R-006e" "cauto documents JSONL growth verification after each skill invocation"
else
  fail "R-006e" "cauto does not document JSONL growth verification"
fi

# ============================================================================
# R-007 [integration]: End-of-pipeline summary with autonomous decisions
# ============================================================================

section "R-007: end-of-pipeline autonomous decisions summary"

# R-007a: cauto must present decisions summary before PR creation
if grep -qi 'autonomous.*decision.*summary\|decision.*summary.*before.*PR\|present.*summary' "$CAUTO_SKILL" 2>/dev/null; then
  pass "R-007a" "cauto documents autonomous decisions summary before PR creation"
else
  fail "R-007a" "cauto does not document autonomous decisions summary"
fi

# R-007b: must group decisions by skill
if grep -qi 'group.*by.*skill\|groups.*decisions.*skill' "$CAUTO_SKILL" 2>/dev/null; then
  pass "R-007b" "cauto groups autonomous decisions by skill"
else
  fail "R-007b" "cauto does not specify grouping decisions by skill"
fi

# R-007c: must have separate Deferred Escalations heading
if grep -qi 'Deferred Escalations\|deferred.*escalation.*heading' "$CAUTO_SKILL" 2>/dev/null; then
  pass "R-007c" "cauto has Deferred Escalations section in summary"
else
  fail "R-007c" "cauto does not have Deferred Escalations heading in summary"
fi

# ============================================================================
# R-008 [unit]: Interactive mode shows (default) annotations
# ============================================================================

section "R-008: interactive mode (default) annotations"

# R-008: Skills with autonomous or hybrid modes must document (default) annotation
# convention for interactive use. The annotation is the UX convention described in
# R-008: In interactive mode, skills show defaults as "(default)" annotations.
# This is prompt-level enforcement (spec: "no structural mechanism available").
# We verify cauto documents the convention for dispatched skills — the actual
# annotation is an LLM output convention, not a file artifact we can test.

r008_found=false

# Check that cauto's Autonomous Mode Dispatch section or AD sections reference
# the default annotation convention — this is the dispatch-side documentation
if grep -qi 'mode: autonomous.*not present\|runs interactively\|fail-open' "$CAUTO_SKILL" 2>/dev/null; then
  r008_found=true
fi

# Check that at least one hybrid skill's Decision Points or Autonomous Defaults
# section contains numbered options with "(recommended)" pattern (the interactive
# option format that would carry "(default)" at runtime)
for skill_file in $SKILLS_DIR/*/SKILL.md; do
  [ -f "$skill_file" ] || continue
  skill_name=$(basename "$(dirname "$skill_file")")
  [ "$skill_name" = "_shared" ] && continue

  mode=$(get_frontmatter_field "$skill_file" "interaction_mode")
  if [ "$mode" = "hybrid" ]; then
    if grep -q '(recommended)' "$skill_file" 2>/dev/null; then
      r008_found=true
      break
    fi
  fi
done

if $r008_found; then
  pass "R-008" "Prompt-level: cauto documents interactive fallback; skills have (recommended) option pattern"
else
  fail "R-008" "Missing interactive-mode default annotation convention documentation"
fi

# ============================================================================
# R-009 [unit]: context: fork + interaction_mode: interactive is forbidden
# ============================================================================

section "R-009: context: fork incompatible with interaction_mode: interactive"

r009_violations=""

for skill_file in $SKILLS_DIR/*/SKILL.md; do
  [ -f "$skill_file" ] || continue
  skill_name=$(basename "$(dirname "$skill_file")")
  [ "$skill_name" = "_shared" ] && continue

  fm=$(extract_frontmatter "$skill_file")
  has_fork=$(echo "$fm" | grep -c 'context: fork' || true)
  mode=$(get_frontmatter_field "$skill_file" "interaction_mode")

  if [ "$has_fork" -gt 0 ] && [ "$mode" = "interactive" ]; then
    r009_violations="${r009_violations}${skill_name} "
  fi
done

if [ -z "$r009_violations" ]; then
  # Also check that the rule is at least relevant — at least one fork skill exists
  fork_count=0
  for skill_file in $SKILLS_DIR/*/SKILL.md; do
    [ -f "$skill_file" ] || continue
    fm=$(extract_frontmatter "$skill_file")
    if echo "$fm" | grep -q 'context: fork'; then
      fork_count=$((fork_count + 1))
    fi
  done

  if [ "$fork_count" -gt 0 ]; then
    # Need to also verify those fork skills have a valid interaction_mode set
    fork_with_mode=0
    for skill_file in $SKILLS_DIR/*/SKILL.md; do
      [ -f "$skill_file" ] || continue
      fm=$(extract_frontmatter "$skill_file")
      if echo "$fm" | grep -q 'context: fork'; then
        mode=$(get_frontmatter_field "$skill_file" "interaction_mode")
        if [ -n "$mode" ] && [ "$mode" != "interactive" ]; then
          fork_with_mode=$((fork_with_mode + 1))
        fi
      fi
    done

    if [ "$fork_with_mode" -eq "$fork_count" ]; then
      pass "R-009" "All $fork_count context: fork skills have non-interactive interaction_mode"
    else
      fail "R-009" "$((fork_count - fork_with_mode))/$fork_count fork skills missing or have invalid interaction_mode"
    fi
  else
    skip "R-009" "No context: fork skills found"
  fi
else
  fail "R-009" "Skills with context: fork AND interaction_mode: interactive (AP-027 violation): $r009_violations"
fi

# ============================================================================
# R-010 [unit]: Structural test uses glob, no hardcoded count
# ============================================================================

section "R-010: structural test with glob discovery (no hardcoded skill count)"

# R-010: This IS the structural test — it discovers all SKILL.md files via glob
# and verifies each has a valid interaction_mode. The test itself must NOT
# hardcode the expected count (AP-024).

discovered_count=0
valid_count=0
invalid_skills=""

for skill_file in "$SKILLS_DIR"/*/SKILL.md; do
  [ -f "$skill_file" ] || continue
  skill_name=$(basename "$(dirname "$skill_file")")
  [ "$skill_name" = "_shared" ] && continue

  discovered_count=$((discovered_count + 1))

  mode=$(get_frontmatter_field "$skill_file" "interaction_mode")
  case "$mode" in
    autonomous|interactive|hybrid)
      valid_count=$((valid_count + 1))
      ;;
    "")
      invalid_skills="${invalid_skills}${skill_name}(missing) "
      ;;
    *)
      invalid_skills="${invalid_skills}${skill_name}(invalid:$mode) "
      ;;
  esac
done

if [ "$discovered_count" -eq 0 ]; then
  fail "R-010" "No SKILL.md files discovered via glob (expected skills/*/SKILL.md)"
elif [ "$valid_count" -eq "$discovered_count" ]; then
  pass "R-010" "All $discovered_count discovered skills have valid interaction_mode"
else
  fail "R-010" "$((discovered_count - valid_count))/$discovered_count skills have invalid/missing interaction_mode: $invalid_skills"
fi

# ============================================================================
# R-011 [unit]: hybrid + fork deferred-escalation machinery
# ============================================================================

section "R-011: hybrid + fork deferred-escalation"

r011_checked=0

for skill_file in $SKILLS_DIR/*/SKILL.md; do
  [ -f "$skill_file" ] || continue
  skill_name=$(basename "$(dirname "$skill_file")")
  [ "$skill_name" = "_shared" ] && continue

  fm=$(extract_frontmatter "$skill_file")
  has_fork=$(echo "$fm" | grep -c 'context: fork' || true)
  mode=$(get_frontmatter_field "$skill_file" "interaction_mode")

  # Only check hybrid + fork skills
  [ "$has_fork" -gt 0 ] && [ "$mode" = "hybrid" ] || continue

  r011_checked=$((r011_checked + 1))

  # Must have escalation_deferred mentioned in Autonomous Defaults section
  if grep -qi 'escalation_deferred\|escalation.*deferred' "$skill_file" 2>/dev/null; then
    pass "R-011a" "$skill_name documents deferred escalation in autonomous defaults"
  else
    fail "R-011a" "$skill_name (hybrid + fork) does not document deferred escalation"
  fi

  # Must have at least one escalate: always entry with a default
  if grep -q 'escalate: always' "$skill_file" 2>/dev/null; then
    pass "R-011b" "$skill_name has escalate: always decision points"
  else
    fail "R-011b" "$skill_name (hybrid + fork) missing escalate: always entries"
  fi
done

if [ "$r011_checked" -eq 0 ]; then
  # No hybrid+fork skills is valid — skip is informational
  skip "R-011" "No hybrid + fork skills found (test will activate when hybrid + fork skills exist)"
fi

# ============================================================================
# R-012 [unit]: Structural test for hybrid + fork deferred-escalation markers
# ============================================================================

section "R-012: structural test for hybrid + fork deferred-escalation"

r012_checked=0
r012_failed=0

for skill_file in "$SKILLS_DIR"/*/SKILL.md; do
  [ -f "$skill_file" ] || continue
  skill_name=$(basename "$(dirname "$skill_file")")
  [ "$skill_name" = "_shared" ] && continue

  fm=$(extract_frontmatter "$skill_file")
  has_fork=$(echo "$fm" | grep -c 'context: fork' || true)
  mode=$(get_frontmatter_field "$skill_file" "interaction_mode")

  # Only check hybrid + fork skills
  [ "$has_fork" -gt 0 ] && [ "$mode" = "hybrid" ] || continue

  r012_checked=$((r012_checked + 1))

  # Must have ## Autonomous Defaults section
  if ! has_section "$skill_file" "Autonomous Defaults"; then
    fail "R-012a" "$skill_name (hybrid + fork) missing ## Autonomous Defaults section"
    r012_failed=$((r012_failed + 1))
    continue
  fi

  # Must have at least one escalate: always with a documented default
  escalate_count=$(grep -c 'escalate: always' "$skill_file" 2>/dev/null || echo 0)
  if [ "$escalate_count" -gt 0 ]; then
    pass "R-012" "$skill_name has $escalate_count escalate: always entries in Autonomous Defaults"
  else
    fail "R-012" "$skill_name (hybrid + fork) has Autonomous Defaults but no escalate: always entries"
    r012_failed=$((r012_failed + 1))
  fi
done

if [ "$r012_checked" -eq 0 ]; then
  skip "R-012" "No hybrid + fork skills found (structural test will activate when they exist)"
fi

# ============================================================================
# R-013 [integration]: Deferred escalation confirmation gate before PR
# ============================================================================

section "R-013: deferred escalation confirmation gate"

# R-013a: cauto must document confirmation prompt for deferred escalations
if grep -qi 'deferred.*escalation.*confirm\|confirm.*deferred.*escalation\|confirmation.*prompt.*deferred\|deferred.*escalation.*gate' "$CAUTO_SKILL" 2>/dev/null; then
  pass "R-013a" "cauto documents deferred escalation confirmation gate"
else
  fail "R-013a" "cauto does not document deferred escalation confirmation gate before PR"
fi

# R-013b: must specify that normal autonomous decisions are NOT gating
if grep -qi 'informational.*not.*gate\|not.*gate.*normal\|normal.*decision.*informational\|non-deferred.*informational' "$CAUTO_SKILL" 2>/dev/null; then
  pass "R-013b" "cauto specifies normal autonomous decisions are informational (non-gating)"
else
  fail "R-013b" "cauto does not specify that normal autonomous decisions are non-gating"
fi

# R-013c: must specify human must confirm before PR creation proceeds
if grep -qi 'human must confirm\|human.*confirm.*before.*PR\|confirm.*proceed.*PR\|acknowledge.*before.*PR\|must acknowledge.*deferred' "$CAUTO_SKILL" 2>/dev/null; then
  pass "R-013c" "cauto requires human confirmation before PR creation"
else
  fail "R-013c" "cauto does not require human confirmation for deferred escalations before PR"
fi

# ============================================================================
# R-014 [unit]: AD-UNLISTED fallback for unknown decision points
# ============================================================================

section "R-014: AD-UNLISTED fallback"

# R-014a: cauto must document the AD-UNLISTED fallback
if grep -q 'AD-UNLISTED' "$CAUTO_SKILL" 2>/dev/null; then
  pass "R-014a" "cauto documents AD-UNLISTED fallback"
else
  fail "R-014a" "cauto does not document AD-UNLISTED fallback for unknown decision points"
fi

# R-014b: AD-UNLISTED must result in escalation_deferred: true
if grep -qi 'AD-UNLISTED.*escalation_deferred.*true\|AD-UNLISTED.*deferred\|unlisted.*escalation_deferred' "$CAUTO_SKILL" 2>/dev/null; then
  pass "R-014b" "AD-UNLISTED decisions are marked escalation_deferred: true"
else
  fail "R-014b" "AD-UNLISTED decisions not marked as escalation_deferred: true"
fi

# R-014c: AD-UNLISTED must be highlighted separately in the summary
if grep -qi 'unlisted.*highlight\|highlight.*unlisted\|unlisted.*separate\|unlisted.*Deferred Escalation' "$CAUTO_SKILL" 2>/dev/null; then
  pass "R-014c" "AD-UNLISTED decisions are highlighted separately in pipeline summary"
else
  fail "R-014c" "AD-UNLISTED decisions not highlighted separately in summary"
fi

# ============================================================================
# Cross-cutting: ABS-030 in ARCHITECTURE.md
# ============================================================================

section "Cross-cutting: ABS-030 architecture entry"

ARCH_FILE="$REPO_DIR/.correctless/ARCHITECTURE.md"

if [ -f "$ARCH_FILE" ]; then
  if grep -q 'ABS-030' "$ARCH_FILE" 2>/dev/null; then
    pass "ABS-030" "ARCHITECTURE.md has ABS-030 entry"
  else
    fail "ABS-030" "ARCHITECTURE.md missing ABS-030 (autonomous decisions JSONL contract)"
  fi

  # ABS-030 must reference autonomous-decisions
  if grep -q 'autonomous-decisions' "$ARCH_FILE" 2>/dev/null; then
    pass "ABS-030-ref" "ABS-030 references autonomous-decisions artifact"
  else
    fail "ABS-030-ref" "ABS-030 does not reference autonomous-decisions artifact"
  fi
else
  fail "ABS-030" "ARCHITECTURE.md not found"
fi

# ============================================================================
# Cross-cutting: sensitive-file-guard protects autonomous-decisions JSONL
# ============================================================================

section "Cross-cutting: sensitive-file-guard protection"

SFG="$REPO_DIR/hooks/sensitive-file-guard.sh"

if [ -f "$SFG" ]; then
  if grep -q 'autonomous-decisions' "$SFG" 2>/dev/null; then
    pass "SFG-001" "sensitive-file-guard protects autonomous-decisions JSONL"
  else
    fail "SFG-001" "sensitive-file-guard does not protect autonomous-decisions JSONL"
  fi
else
  fail "SFG-001" "sensitive-file-guard.sh not found"
fi

# ============================================================================
# Cross-cutting: writer script exists and is protected by SFG
# ============================================================================

section "Cross-cutting: writer script"

WRITER_SCRIPT="$REPO_DIR/scripts/autonomous-decision-writer.sh"

if [ -f "$WRITER_SCRIPT" ]; then
  pass "WRITER-001" "autonomous-decision-writer.sh exists"
  if [ -x "$WRITER_SCRIPT" ]; then
    pass "WRITER-002" "autonomous-decision-writer.sh is executable"
  else
    fail "WRITER-002" "autonomous-decision-writer.sh is not executable"
  fi
else
  fail "WRITER-001" "autonomous-decision-writer.sh not found"
  fail "WRITER-002" "autonomous-decision-writer.sh not found (skip)"
fi

if [ -f "$SFG" ]; then
  if grep -q 'autonomous-decision-writer' "$SFG" 2>/dev/null; then
    pass "WRITER-003" "sensitive-file-guard protects writer script from modification"
  else
    fail "WRITER-003" "sensitive-file-guard does not protect autonomous-decision-writer.sh"
  fi
fi

if [ -f "$CAUTO_SKILL" ]; then
  if grep -q 'autonomous-decision-writer\.sh' "$CAUTO_SKILL" 2>/dev/null; then
    pass "WRITER-004" "cauto references writer script"
  else
    fail "WRITER-004" "cauto does not reference autonomous-decision-writer.sh"
  fi
fi

# ============================================================================
# Cross-cutting: hybrid skills have structured output format reference
# ============================================================================

section "Cross-cutting: output format reference in hybrid skills"

hybrid_format_missing=0
for skill_file in $SKILLS_DIR/*/SKILL.md; do
  [ -f "$skill_file" ] || continue
  skill_name=$(basename "$(dirname "$skill_file")")
  [ "$skill_name" = "_shared" ] && continue
  [ "$skill_name" = "cauto" ] && continue

  mode=$(get_frontmatter_field "$skill_file" "interaction_mode")
  if [ "$mode" = "hybrid" ]; then
    if ! grep -q 'AUTONOMOUS_DECISIONS_START' "$skill_file" 2>/dev/null; then
      hybrid_format_missing=$((hybrid_format_missing + 1))
      fail "FORMAT-$skill_name" "$skill_name hybrid skill missing AUTONOMOUS_DECISIONS format reference"
    fi
  fi
done

if [ "$hybrid_format_missing" -eq 0 ]; then
  pass "FORMAT-001" "All non-cauto hybrid skills have AUTONOMOUS_DECISIONS format reference"
fi

# ============================================================================
# Summary
# ============================================================================

summary "Autonomous Skill Contract"
