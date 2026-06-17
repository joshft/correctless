#!/usr/bin/env bash
# Correctless — Allowed-Tools Cross-Check (AP-008 structural prevention)
# Verifies that cspec Step 5a exists and that no existing spec instructs
# a skill to write to a path or run a command not in its allowed-tools.
# Run from repo root: bash tests/test-allowed-tools-check.sh

source "$(dirname "${BASH_SOURCE[0]}")/test-helpers.sh"

# ============================================
# Part 1: cspec SKILL.md has Step 5a
# ============================================

echo ""
echo "=== cspec Step 5a: Allowed-Tools Cross-Check ==="

cspec="$REPO_DIR/skills/cspec/SKILL.md"

# Step 5a section exists
if grep -q "Step 5a" "$cspec" 2>/dev/null; then
  pass "AP-008-01" "cspec has Step 5a section"
else
  fail "AP-008-01" "cspec missing Step 5a section"
fi

# Step 5a references AP-008
if grep -q "AP-008" "$cspec" 2>/dev/null; then
  pass "AP-008-02" "cspec Step 5a references AP-008"
else
  fail "AP-008-02" "cspec Step 5a does not reference AP-008"
fi

# Step 5a mentions allowed-tools cross-check
if grep -qi "allowed.tools.*cross.check\|cross.check.*allowed.tools\|allowed-tools.*frontmatter" "$cspec" 2>/dev/null; then
  pass "AP-008-03" "cspec Step 5a describes allowed-tools cross-check"
else
  fail "AP-008-03" "cspec Step 5a missing allowed-tools cross-check description"
fi

# Step 5a mentions Write() and Bash() patterns
if grep -qi "Write(" "$cspec" 2>/dev/null && grep -qi "Bash(" "$cspec" 2>/dev/null; then
  pass "AP-008-04" "cspec Step 5a covers both Write() and Bash() permissions"
else
  fail "AP-008-04" "cspec Step 5a missing Write() or Bash() coverage"
fi

# Step 5a mentions skipping unrestricted skills
if grep -qi 'Bash(\*)\|Write(\*)\|unrestricted' "$cspec" 2>/dev/null; then
  pass "AP-008-05" "cspec Step 5a handles unrestricted permissions"
else
  fail "AP-008-05" "cspec Step 5a missing unrestricted permission handling"
fi

# ============================================
# Part 2: Structural check — every skill's
# allowed-tools includes Write() for paths
# the skill is instructed to write to
# ============================================

echo ""
echo "=== Structural: skill allowed-tools coverage ==="

# HF-007: cmodelupgrade-specific allowed-tools constraints (harness-fingerprint INV-007 / PRH-003)
cmodelupgrade="$REPO_DIR/skills/cmodelupgrade/SKILL.md"
if [ -f "$cmodelupgrade" ]; then
  allowed_cmu="$(sed -n 's/^allowed-tools: //p' "$cmodelupgrade" 2>/dev/null)"
  if echo "$allowed_cmu" | grep -qF 'model-baselines.json'; then
    pass "HF-007-cmu-1" "cmodelupgrade allowed-tools includes Write(model-baselines.json)"
  else
    fail "HF-007-cmu-1" "cmodelupgrade allowed-tools missing Write(model-baselines.json)"
  fi
  if echo "$allowed_cmu" | grep -qF 'harness-fingerprint.json'; then
    fail "HF-007-cmu-2" "cmodelupgrade allowed-tools must NOT include Write(harness-fingerprint.json) per INV-007"
  else
    pass "HF-007-cmu-2" "cmodelupgrade allowed-tools correctly excludes harness-fingerprint write"
  fi
  if echo "$allowed_cmu" | grep -qE '\bTask\b'; then
    fail "HF-007-cmu-3" "cmodelupgrade allowed-tools must NOT include Task per PRH-003"
  else
    pass "HF-007-cmu-3" "cmodelupgrade allowed-tools correctly excludes Task (no subagent spawning)"
  fi
else
  fail "HF-007-cmu-0" "cmodelupgrade SKILL.md does not exist"
fi

echo ""
echo "=== Structural: per-skill body checks (existing) ===
"

# For each skill, extract allowed-tools and check that key Write() paths
# mentioned in the skill body are covered by the frontmatter
skills_dir="$REPO_DIR/skills"
structural_issues=0

for skill_dir in "$skills_dir"/*/; do
  skill_file="$skill_dir/SKILL.md"
  [ -f "$skill_file" ] || continue

  skill_name="$(basename "$skill_dir")"

  # Extract allowed-tools line
  allowed="$(sed -n 's/^allowed-tools: //p' "$skill_file" 2>/dev/null)"
  [ -z "$allowed" ] && continue

  # Skip unrestricted skills (have Write(*) or bare Write without parens)
  if echo "$allowed" | grep -qE '(^|, )Write(\(\*\))?($|,)'; then
    continue  # unrestricted Write
  fi

  # Check: if the skill body mentions writing to .correctless/meta/ paths,
  # verify Write(.correctless/meta/*) or specific path is in allowed-tools
  # (This catches the exact AP-008 pattern from intensity-calibration)
  if grep -qi "write.*\.correctless/meta/\|\.correctless/meta/.*write\|calibration.*entry\|write.*calibration" "$skill_file" 2>/dev/null; then
    if echo "$allowed" | grep -qF "Write(.correctless/meta/"; then
      : # covered
    elif echo "$allowed" | grep -qF "Write(.correctless/artifacts/*)"; then
      : # broad coverage
    else
      # Check if it mentions writing but is actually read-only (e.g., cspec reads calibration)
      # Only flag if the skill has explicit write instructions (not just "read")
      if grep -qi "write.*calibration.*entry\|append.*calibration\|create.*calibration" "$skill_file" 2>/dev/null; then
        fail "AP-008-structural" "$skill_name writes to .correctless/meta/ but allowed-tools missing Write(.correctless/meta/*)"
        structural_issues=$((structural_issues + 1))
      fi
    fi
  fi

  # Check: if the skill body mentions running jq, verify Bash(jq*) is in allowed-tools
  # Skip unrestricted Bash (have Bash(*) or bare Bash without parens)
  if echo "$allowed" | grep -qE '(^|, )Bash(\(\*\))?($|,)'; then
    continue
  fi
  if grep -q '```bash' "$skill_file" 2>/dev/null; then
    # Extract commands from bash code blocks
    if grep -qi "^jq \|^jq$\| jq " "$skill_file" 2>/dev/null; then
      # Accept Bash(jq*) or any Bash() pattern that covers the specific jq target
      # e.g. Bash(*cross-feature-intel*) covers jq reads of cross-feature-intel.json
      if echo "$allowed" | grep -qE 'Bash\((jq|\*[a-z])'; then
        : # covered by Bash(jq*) or a targeted Bash(*...*) pattern
      else
        fail "AP-008-structural" "$skill_name has jq commands but allowed-tools missing Bash(jq*) or targeted pattern"
        structural_issues=$((structural_issues + 1))
      fi
    fi
  fi
done

if [ "$structural_issues" -eq 0 ]; then
  pass "AP-008-structural" "all skills' allowed-tools cover their Write/Bash instructions"
fi

# ============================================
# Part 3: Check that Write(.correctless/ARCHITECTURE.md)
# is present for skills instructed to write to it
# (AP-008 instance from auto-recurring-patterns)
# ============================================

echo ""
echo "=== Structural: ARCHITECTURE.md write permissions ==="

for skill_dir in "$skills_dir"/*/; do
  skill_file="$skill_dir/SKILL.md"
  [ -f "$skill_file" ] || continue

  skill_name="$(basename "$skill_dir")"
  allowed="$(sed -n 's/^allowed-tools: //p' "$skill_file" 2>/dev/null)"
  [ -z "$allowed" ] && continue

  # Skip unrestricted (Write(*) or bare Write)
  if echo "$allowed" | grep -qE '(^|, )Write(\(\*\))?($|,)'; then
    continue
  fi

  # If skill mentions writing to ARCHITECTURE.md (exclude blockquoted agent
  # prompt lines starting with > — those describe subagent reads, not skill writes)
  if grep -v '^>' "$skill_file" 2>/dev/null | grep -qi "write.*ARCHITECTURE\.md\|ARCHITECTURE\.md.*write\|add.*ARCHITECTURE\.md\|append.*ARCHITECTURE"; then
    if echo "$allowed" | grep -qF "Write(.correctless/ARCHITECTURE.md)"; then
      pass "AP-008-arch" "$skill_name has Write(.correctless/ARCHITECTURE.md)"
    else
      fail "AP-008-arch" "$skill_name writes to ARCHITECTURE.md but missing Write(.correctless/ARCHITECTURE.md)"
    fi
  fi
done

# ============================================
# cross-model-spec-review INV-013 / AP-008:
#   creview-spec allowed-tools MUST contain Bash(*external-review-run.sh*)
#   creview-spec allowed-tools MUST NOT contain Write(...external-review-history.json...)
#     (the direct history Write grant is REMOVED so the producer is sole writer — RS-001)
#   csetup allowed-tools MUST contain Bash(*config-update.sh*)  (RS-019)
# ============================================

echo ""
echo "=== INV-013 (cross-model-spec-review): producer reachable; direct history Write removed ==="

creview_spec="$REPO_DIR/skills/creview-spec/SKILL.md"
csetup_skill="$REPO_DIR/skills/csetup/SKILL.md"

creview_allowed="$(grep -m1 '^allowed-tools:' "$creview_spec" 2>/dev/null || true)"
csetup_allowed="$(grep -m1 '^allowed-tools:' "$csetup_skill" 2>/dev/null || true)"

# Presence: Bash grant for the producer.
if echo "$creview_allowed" | grep -qF 'external-review-run.sh'; then
  pass "INV-013-01" "creview-spec allowed-tools includes Bash(*external-review-run.sh*)"
else
  fail "INV-013-01" "creview-spec allowed-tools must include Bash(*external-review-run.sh*)"
fi

# Negative assertion: the direct history Write grant must be REMOVED (RS-001).
if echo "$creview_allowed" | grep -qF 'external-review-history.json'; then
  fail "INV-013-02" "creview-spec must NOT grant Write(...external-review-history.json...) — producer is sole writer (RS-001)"
else
  pass "INV-013-02" "creview-spec no longer grants direct Write to external-review-history.json"
fi

# csetup must grant Bash(*config-update.sh*) (RS-019).
if echo "$csetup_allowed" | grep -qF 'config-update.sh'; then
  pass "INV-013-03" "csetup allowed-tools includes Bash(*config-update.sh*)"
else
  fail "INV-013-03" "csetup allowed-tools must include Bash(*config-update.sh*) (RS-019)"
fi

# ============================================
# Results
# ============================================

echo ""
echo "============================================="
echo "Results: $PASS passed, $FAIL failed"
echo "============================================="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
