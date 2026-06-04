#!/usr/bin/env bash
# Correctless — Disallowed-Tools Frontmatter Tests
# Verifies R-001 through R-007 of the disallowed-tools spec:
#   R-001: Group A skills have disallowed-tools: Edit, Write, MultiEdit, NotebookEdit, CreateFile
#   R-002: Group B skills have disallowed-tools: Edit, MultiEdit, NotebookEdit, CreateFile
#   R-003: disallowed-tools line appears in YAML frontmatter block
#   R-004: Distribution copies match source copies after sync.sh
#   R-005: disallowed-tools set is disjoint from allowed-tools basenames
#   R-006: AGENT_CONTEXT.md describes disallowed-tools + defense-in-depth
#   R-007: Structural drift test partitions all skills and verifies classification
#
# Run from repo root: bash tests/test-disallowed-tools.sh

source "$(dirname "${BASH_SOURCE[0]}")/test-helpers.sh"

# ============================================================================
# Constants
# ============================================================================

SKILLS_DIR="$REPO_DIR/skills"
DIST_DIR="$REPO_DIR/correctless/skills"
AGENT_CONTEXT="$REPO_DIR/.correctless/AGENT_CONTEXT.md"

# Group A: write-nothing skills — disallow Edit, Write, MultiEdit, NotebookEdit, CreateFile
GROUP_A_SKILLS="chelp cstatus cdashboard"
GROUP_A_DISALLOWED="Edit, Write, MultiEdit, NotebookEdit, CreateFile"

# Group B: artifact-only skills — disallow Edit, MultiEdit, NotebookEdit, CreateFile (NOT Write)
GROUP_B_SKILLS="cexplain cwtf cmetrics csummary cpr-review cmaintain cmodel cmodelupgrade ctriage"
GROUP_B_DISALLOWED="Edit, MultiEdit, NotebookEdit, CreateFile"

# Skills that legitimately use Edit/Write and should NOT have disallowed-tools
EXEMPT_SKILLS="carchitect caudit cauto ccontribute cdebug cdevadv cdocs cpostmortem cprune cquick credteam crefactor crelease creview-spec creview csetup cspec ctdd cupdate-arch cverify"

# _shared is a directory but not a skill
SKIP_DIRS="_shared"

# ============================================================================
# Helpers
# ============================================================================

get_disallowed_tools() {
  local file="$1"
  get_frontmatter_field "$file" "disallowed-tools"
}

# Extract tool basename by stripping sub-pattern scoping
# e.g., "Write(.correctless/artifacts/wtf-*)" -> "Write"
strip_tool_scope() {
  local tool="$1"
  echo "$tool" | sed 's/([^)]*)//g' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

# Check whether a skill name is in a space-separated list
is_in_list() {
  local name="$1" list="$2"
  local item
  for item in $list; do
    [ "$item" = "$name" ] && return 0
  done
  return 1
}

# Verify a group of skills has the expected disallowed-tools value
check_group_disallowed() {
  local rule_prefix="$1" group_name="$2" expected="$3"
  shift 3
  local skills="$*"
  local skill skill_file actual

  for skill in $skills; do
    skill_file="$SKILLS_DIR/$skill/SKILL.md"
    if [ ! -f "$skill_file" ]; then
      fail "${rule_prefix}-$skill-exists" "$skill SKILL.md does not exist"
      continue
    fi

    actual="$(get_disallowed_tools "$skill_file")"
    if [ -z "$actual" ]; then
      fail "${rule_prefix}-$skill" "$skill missing disallowed-tools frontmatter"
    elif [ "$actual" = "$expected" ]; then
      pass "${rule_prefix}-$skill" "$skill has correct disallowed-tools for $group_name"
    else
      fail "${rule_prefix}-$skill" "$skill disallowed-tools is '$actual', expected '$expected'"
    fi
  done
}

# ============================================================================
# R-001: Group A skills have correct disallowed-tools
# ============================================================================

section "R-001: Group A disallowed-tools"
check_group_disallowed "R001" "Group A" "$GROUP_A_DISALLOWED" $GROUP_A_SKILLS

# ============================================================================
# R-002: Group B skills have correct disallowed-tools
# ============================================================================

section "R-002: Group B disallowed-tools"
check_group_disallowed "R002" "Group B" "$GROUP_B_DISALLOWED" $GROUP_B_SKILLS

# ============================================================================
# R-003: disallowed-tools appears in YAML frontmatter block, not body
# ============================================================================

section "R-003: disallowed-tools in frontmatter block"

ALL_DISALLOWED_SKILLS="$GROUP_A_SKILLS $GROUP_B_SKILLS"

for skill in $ALL_DISALLOWED_SKILLS; do
  skill_file="$SKILLS_DIR/$skill/SKILL.md"
  [ -f "$skill_file" ] || continue

  # Check frontmatter has it
  frontmatter="$(extract_frontmatter "$skill_file" 2>/dev/null)"
  if echo "$frontmatter" | grep -q "^disallowed-tools:"; then
    pass "R003-$skill-fm" "$skill has disallowed-tools in frontmatter"
  else
    fail "R003-$skill-fm" "$skill missing disallowed-tools in frontmatter block"
  fi

  # Check body does NOT have a standalone disallowed-tools: line that looks like frontmatter
  body="$(skill_body "$skill_file")"
  if echo "$body" | grep -q "^disallowed-tools:"; then
    fail "R003-$skill-body" "$skill has disallowed-tools: line in body (should be frontmatter only)"
  else
    pass "R003-$skill-body" "$skill has no disallowed-tools: line in body"
  fi
done

# ============================================================================
# R-004: Distribution copies match source after sync.sh
# ============================================================================

section "R-004: Distribution parity"

for skill in $ALL_DISALLOWED_SKILLS; do
  src="$SKILLS_DIR/$skill/SKILL.md"
  dst="$DIST_DIR/$skill/SKILL.md"

  if [ ! -f "$src" ]; then
    fail "R004-$skill-src" "$skill source SKILL.md missing"
    continue
  fi
  if [ ! -f "$dst" ]; then
    fail "R004-$skill-dst" "$skill distribution SKILL.md missing"
    continue
  fi

  # Compare source disallowed-tools with distribution copy
  src_disallowed="$(get_disallowed_tools "$src")"
  dst_disallowed="$(get_disallowed_tools "$dst")"

  if [ "$src_disallowed" = "$dst_disallowed" ]; then
    pass "R004-$skill" "$skill distribution matches source disallowed-tools"
  else
    fail "R004-$skill" "$skill distribution disallowed-tools mismatch: src='$src_disallowed' dst='$dst_disallowed'"
  fi
done

# ============================================================================
# R-005: disallowed-tools set disjoint from allowed-tools basenames
# ============================================================================

section "R-005: Disjoint allowed/disallowed tools"

for skill in $ALL_DISALLOWED_SKILLS; do
  skill_file="$SKILLS_DIR/$skill/SKILL.md"
  [ -f "$skill_file" ] || continue

  allowed_raw="$(get_frontmatter_field "$skill_file" "allowed-tools" 2>/dev/null || true)"
  disallowed_raw="$(get_disallowed_tools "$skill_file" 2>/dev/null || true)"

  if [ -z "$disallowed_raw" ]; then
    fail "R005-$skill-missing" "$skill has no disallowed-tools to check"
    continue
  fi

  # Check each disallowed tool does not appear in allowed-tools (by basename)
  overlap=""
  IFS=',' read -ra disallowed_arr <<< "$disallowed_raw"
  IFS=',' read -ra allowed_arr <<< "$allowed_raw"
  for dtool in "${disallowed_arr[@]}"; do
    dtool_clean="$(echo "$dtool" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [ -z "$dtool_clean" ] && continue
    for atool in "${allowed_arr[@]}"; do
      if [ "$(strip_tool_scope "$atool")" = "$dtool_clean" ]; then
        overlap="${overlap}${dtool_clean} "
      fi
    done
  done

  if [ -z "$overlap" ]; then
    pass "R005-$skill" "$skill allowed/disallowed tools are disjoint"
  else
    fail "R005-$skill" "$skill has overlap between allowed and disallowed: $overlap"
  fi
done

# R-005 addendum: Group B must NOT disallow Write (they need it for artifacts)
section "R-005: Group B does not disallow Write"

for skill in $GROUP_B_SKILLS; do
  skill_file="$SKILLS_DIR/$skill/SKILL.md"
  [ -f "$skill_file" ] || continue

  disallowed_raw="$(get_disallowed_tools "$skill_file" 2>/dev/null || true)"
  if [ -z "$disallowed_raw" ]; then
    fail "R005-$skill-nowrite-missing" "$skill has no disallowed-tools"
    continue
  fi

  if echo ", $disallowed_raw," | grep -q ", Write,"; then
    fail "R005-$skill-nowrite" "$skill (Group B) disallows Write — Group B needs Write for artifacts"
  else
    pass "R005-$skill-nowrite" "$skill (Group B) correctly does not disallow Write"
  fi
done

# ============================================================================
# R-006: AGENT_CONTEXT.md describes disallowed-tools
# ============================================================================

section "R-006: AGENT_CONTEXT.md disallowed-tools documentation"

if [ ! -f "$AGENT_CONTEXT" ]; then
  fail "R006-exists" "AGENT_CONTEXT.md does not exist"
else
  # Check for disallowed-tools mention
  if grep -qi "disallowed.tools" "$AGENT_CONTEXT"; then
    pass "R006-mention" "AGENT_CONTEXT.md mentions disallowed-tools"
  else
    fail "R006-mention" "AGENT_CONTEXT.md does not mention disallowed-tools"
  fi

  # Check for defense-in-depth relationship with allowed-tools
  if grep -qi "defense.in.depth\|defence.in.depth" "$AGENT_CONTEXT"; then
    pass "R006-depth" "AGENT_CONTEXT.md mentions defense-in-depth"
  else
    fail "R006-depth" "AGENT_CONTEXT.md does not mention defense-in-depth"
  fi

  # Check for PAT-018 reference
  if grep -q "PAT-018" "$AGENT_CONTEXT"; then
    pass "R006-pat018" "AGENT_CONTEXT.md references PAT-018"
  else
    fail "R006-pat018" "AGENT_CONTEXT.md does not reference PAT-018"
  fi
fi

# ============================================================================
# R-007: Structural drift test — partition all skills
# ============================================================================

section "R-007: Structural drift — all skills classified"

# Build expected sets
declare -A expected_group
for s in $GROUP_A_SKILLS; do expected_group[$s]="A"; done
for s in $GROUP_B_SKILLS; do expected_group[$s]="B"; done

for skill_dir in "$SKILLS_DIR"/*/; do
  [ -d "$skill_dir" ] || continue
  skill="$(basename "$skill_dir")"
  skill_file="$skill_dir/SKILL.md"

  is_in_list "$skill" "$SKIP_DIRS" && continue
  [ -f "$skill_file" ] || continue

  if [ -n "${expected_group[$skill]+x}" ]; then
    # Skill is in Group A or B — verify it has the correct disallowed-tools
    actual_disallowed="$(get_disallowed_tools "$skill_file" 2>/dev/null || true)"
    group="${expected_group[$skill]}"
    if [ "$group" = "A" ]; then
      expected="$GROUP_A_DISALLOWED"
    else
      expected="$GROUP_B_DISALLOWED"
    fi

    if [ "$actual_disallowed" = "$expected" ]; then
      pass "R007-$skill-classified" "$skill correctly classified as Group $group"
    else
      fail "R007-$skill-classified" "$skill classified as Group $group but disallowed-tools wrong: '$actual_disallowed'"
    fi
  elif is_in_list "$skill" "$EXEMPT_SKILLS"; then
    # Exempt skills should NOT have disallowed-tools (they need Edit/Write)
    actual_disallowed="$(get_disallowed_tools "$skill_file" 2>/dev/null || true)"
    if [ -n "$actual_disallowed" ]; then
      fail "R007-$skill-exempt" "$skill is exempt but has disallowed-tools: '$actual_disallowed'"
    else
      pass "R007-$skill-exempt" "$skill correctly exempt (no disallowed-tools)"
    fi
  else
    fail "R007-$skill-unclassified" "$skill is not in Group A, Group B, or exempt list"
  fi
done

# R-007b: skills whose allowed-tools lacks Edit should have disallowed-tools or be exempt
section "R-007b: Skills without Edit in allowed-tools must have disallowed-tools or be excluded"

for skill_dir in "$SKILLS_DIR"/*/; do
  [ -d "$skill_dir" ] || continue
  skill="$(basename "$skill_dir")"
  skill_file="$skill_dir/SKILL.md"

  is_in_list "$skill" "$SKIP_DIRS" && continue
  [ -f "$skill_file" ] || continue

  allowed_raw="$(get_frontmatter_field "$skill_file" "allowed-tools" 2>/dev/null || true)"
  [ -z "$allowed_raw" ] && continue

  # Check if allowed-tools includes Edit (with or without scope)
  has_edit=false
  IFS=',' read -ra atarr <<< "$allowed_raw"
  for atool in "${atarr[@]}"; do
    if [ "$(strip_tool_scope "$atool")" = "Edit" ]; then
      has_edit=true
      break
    fi
  done
  $has_edit && continue

  # No Edit in allowed-tools — should have disallowed-tools or be exempt
  actual_disallowed="$(get_disallowed_tools "$skill_file" 2>/dev/null || true)"
  if [ -n "$actual_disallowed" ]; then
    pass "R007b-$skill" "$skill lacks Edit in allowed-tools and has disallowed-tools"
  elif is_in_list "$skill" "$EXEMPT_SKILLS"; then
    pass "R007b-$skill" "$skill lacks Edit in allowed-tools, exempt (documented)"
  else
    fail "R007b-$skill" "$skill lacks Edit in allowed-tools but has no disallowed-tools and is not exempt"
  fi
done

# ============================================================================
# Results
# ============================================================================

summary "disallowed-tools"
