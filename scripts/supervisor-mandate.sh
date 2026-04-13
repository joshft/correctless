#!/usr/bin/env bash
# Correctless — Supervisor mandate expansion for Auto Mode Phase 3
# Handles mandate context building, citation validation, hard limits,
# dependency guards, and configurable mandate levels.

# No set -euo pipefail — this file is sourced by other scripts

# Source lib.sh for shared utilities.
# Source at top level (not inside functions) to avoid RETURN trap interaction.
_SUPERVISOR_MANDATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)"
if [ -n "$_SUPERVISOR_MANDATE_DIR" ] && [ -f "$_SUPERVISOR_MANDATE_DIR/lib.sh" ]; then
  # shellcheck source=lib.sh
  source "$_SUPERVISOR_MANDATE_DIR/lib.sh"
fi
unset _SUPERVISOR_MANDATE_DIR

# ---------------------------------------------------------------------------
# build_mandate_context — build enriched context for supervisor activation
# ---------------------------------------------------------------------------
# Usage: build_mandate_context PREFERENCES_FILE DECISION_RECORD_FILE SPEC_FILE STATE_FILE
# Outputs JSON with: preferences, decision_patterns, spec_scope
# decision_patterns schema: {"categories":{...},"total_decisions":N,"tier_distribution":{...}}
build_mandate_context() {
  local _preferences_file="$1"
  local _decision_record_file="$2"
  local _spec_file="$3"
  local _state_file="$4"

  # Build preferences
  local preferences="{}"
  if [ -f "$_preferences_file" ]; then
    # Read preferences from markdown file
    local mandate_level="conservative"
    mandate_level="$(grep -i 'supervisor_mandate' "$_preferences_file" 2>/dev/null | sed 's/.*:[[:space:]]*//' | tr -d '[:space:]')" || true
    [ -z "$mandate_level" ] && mandate_level="conservative"
    preferences="$(jq -n --arg ml "$mandate_level" '{"supervisor_mandate": $ml}')" || preferences="{}"
  fi

  # Build decision_patterns from decision record
  local decision_patterns='{"categories":{},"total_decisions":0,"tier_distribution":{"tier0":0,"tier1":0,"tier2":0,"tier3":0}}'
  if [ -f "$_decision_record_file" ]; then
    # Parse DD-xxx entries from decision record markdown
    # Extract tier and category and disposition from structured entries
    local total=0 tier0=0 tier1=0 tier2=0 tier3=0
    local categories_json="{}"
    local _current_category=""

    while IFS= read -r line; do
      case "$line" in
        "### DD-"*)
          total=$((total + 1))
          _current_category=""
          ;;
        *"**Tier**:"*)
          local tier_val
          tier_val="$(echo "$line" | sed 's/.*Tier[^:]*:[[:space:]]*//' | tr -d '[:space:]')"
          case "$tier_val" in
            0) tier0=$((tier0 + 1)) ;;
            1) tier1=$((tier1 + 1)) ;;
            2) tier2=$((tier2 + 1)) ;;
            3) tier3=$((tier3 + 1)) ;;
          esac
          ;;
        *"**Category**:"*)
          local cat_val
          cat_val="$(echo "$line" | sed 's/.*Category[^:]*:[[:space:]]*//' | tr -d '[:space:]')"
          _current_category="$cat_val"
          ;;
        *"**Disposition**:"*)
          local disp_val
          disp_val="$(echo "$line" | sed 's/.*Disposition[^:]*:[[:space:]]*//' | tr -d '[:space:]')"
          if [ -n "${_current_category:-}" ]; then
            categories_json="$(echo "$categories_json" | jq \
              --arg cat "$_current_category" --arg disp "$disp_val" '
              .[$cat] //= {} | .[$cat][$disp] = ((.[$cat][$disp] // 0) + 1)
            ' 2>/dev/null)" || true
          fi
          ;;
      esac
    done < "$_decision_record_file"

    # R2-F7: validate categories_json is valid JSON before --argjson
    echo "$categories_json" | jq -e '.' >/dev/null 2>&1 || categories_json="{}"

    decision_patterns="$(jq -n \
      --argjson cats "$categories_json" \
      --argjson total "$total" \
      --argjson t0 "$tier0" \
      --argjson t1 "$tier1" \
      --argjson t2 "$tier2" \
      --argjson t3 "$tier3" \
      '{
        categories: $cats,
        total_decisions: $total,
        tier_distribution: {tier0: $t0, tier1: $t1, tier2: $t2, tier3: $t3}
      }')" || true
  fi

  # Build spec_scope — extract scope section from spec
  local spec_scope=""
  if [ -f "$_spec_file" ]; then
    # Extract content under ## Scope heading until the next ## heading
    # QA-010: stop at ANY next ## heading, not just non-S headings
    spec_scope="$(awk '/^## Scope$/{found=1; next} /^## /{if(found) exit} found' "$_spec_file" 2>/dev/null | head -20)" || true
  fi

  # Assemble the full context (R2-F7: fallback if jq fails)
  jq -n \
    --argjson prefs "$preferences" \
    --argjson dp "$decision_patterns" \
    --arg scope "$spec_scope" \
    '{
      preferences: $prefs,
      decision_patterns: $dp,
      spec_scope: $scope
    }' 2>/dev/null || {
    echo "WARNING: build_mandate_context jq assembly failed, using empty context" >&2
    echo '{"preferences":{},"decision_patterns":{},"spec_scope":""}'
  }

  return 0
}

# ---------------------------------------------------------------------------
# validate_spec_citation — verify cited spec section exists
# ---------------------------------------------------------------------------
# Usage: validate_spec_citation SPEC_FILE CITATION
# Returns 0 if citation found in spec, 1 if not.
validate_spec_citation() {
  local _spec_file="$1"
  local _citation="$2"

  [ -f "$_spec_file" ] || return 1
  [ -n "$_citation" ] || return 1

  # Grep spec for the citation text (heading or INV-xxx ID)
  if grep -qF "$_citation" "$_spec_file" 2>/dev/null; then
    return 0
  fi

  return 1
}

# ---------------------------------------------------------------------------
# check_hard_limits — check if decision hits non-negotiable hard limits
# ---------------------------------------------------------------------------
# Usage: check_hard_limits DR_JSON SPEC_FILE
# Outputs "hard_stop" if decision matches hard limit, "route" otherwise.
# Hard limits: unspecced deps, security relaxation, budget/time exceeded,
# intent tampered, policy tampered, CLAUDE.md mods, spec restructure.
check_hard_limits() {
  local _dr_json="$1"
  local _spec_file="$2"

  local category summary
  category="$(echo "$_dr_json" | jq -r '.category // ""' 2>/dev/null)" || category=""
  summary="$(echo "$_dr_json" | jq -r '.summary // ""' 2>/dev/null)" || summary=""

  case "$category" in
    # Categories that are always hard_stop regardless of content
    dependency|budget|intent|policy|spec-restructure)
      echo "hard_stop"
      ;;

    # Security: relaxation is hard_stop, improvement routes normally
    security)
      local summary_lower="${summary,,}"
      if echo "$summary_lower" | grep -qiE '(remove|disable|skip|relax|downgrade|reduce|weaken|bypass|drop|delete|loosen)'; then
        echo "hard_stop"
      else
        echo "route"
      fi
      ;;

    # Configuration: CLAUDE.md modifications are hard_stop, others route
    configuration)
      if echo "$summary" | grep -qF "CLAUDE.md"; then
        echo "hard_stop"
      else
        echo "route"
      fi
      ;;

    # All other categories — route to supervisor
    *)
      echo "route"
      ;;
  esac

  return 0
}

# ---------------------------------------------------------------------------
# check_dependency_specced — check if a dependency is mentioned in the spec
# ---------------------------------------------------------------------------
# Usage: check_dependency_specced DEP_NAME SPEC_FILE
# Outputs "specced" if mentioned, "unspecced" if not.
check_dependency_specced() {
  local _dep_name="$1"
  local _spec_file="$2"

  [ -f "$_spec_file" ] || { echo "unspecced"; return 0; }
  [ -n "$_dep_name" ] || { echo "unspecced"; return 0; }

  # Case-insensitive literal search for the dependency name in the spec
  # Uses -F for literal matching — dep names like "c++", "node.js" contain regex metacharacters
  if grep -qFi "$_dep_name" "$_spec_file" 2>/dev/null; then
    echo "specced"
  else
    echo "unspecced"
  fi

  return 0
}

# ---------------------------------------------------------------------------
# get_mandate_level — read supervisor mandate level from preferences
# ---------------------------------------------------------------------------
# Usage: get_mandate_level PREFERENCES_FILE
# Outputs "conservative" | "moderate" | "aggressive"
# Default: "conservative" when field absent or file missing.
get_mandate_level() {
  local _preferences_file="$1"

  # Default to conservative when file is missing
  if [ ! -f "$_preferences_file" ]; then
    echo "conservative"
    return 0
  fi

  # Read supervisor_mandate from preferences
  local level
  level="$(grep -i 'supervisor_mandate' "$_preferences_file" 2>/dev/null | sed 's/.*:[[:space:]]*//' | tr -d '[:space:]')" || true

  case "$level" in
    conservative|moderate|aggressive)
      echo "$level"
      ;;
    *)
      # Default to conservative for unrecognized or missing value
      echo "conservative"
      ;;
  esac

  return 0
}

# ---------------------------------------------------------------------------
# validate_mandate_decision — enforce citation at conservative level
# ---------------------------------------------------------------------------
# Usage: validate_mandate_decision SUPERVISOR_RESPONSE MANDATE_LEVEL SPEC_FILE
# Returns 0 if valid, 1 if override to hard_stop needed.
# At conservative level, architectural decisions must cite a spec section.
validate_mandate_decision() {
  local _supervisor_response="$1"
  local _mandate_level="$2"
  local _spec_file="$3"

  # At moderate/aggressive: no additional validation
  case "$_mandate_level" in
    moderate|aggressive)
      return 0
      ;;
  esac

  # At conservative level: check reasoning for spec citation
  local reasoning
  reasoning="$(echo "$_supervisor_response" | jq -r '.reasoning // ""' 2>/dev/null)" || reasoning=""

  # Look for spec citations (INV-xxx, heading references)
  # Extract potential citations: INV-NNN patterns or "## Section" references
  local found_citation="no"

  # Check for INV-xxx citations
  local inv_refs
  inv_refs="$(echo "$reasoning" | grep -oE 'INV-[0-9]+' 2>/dev/null)" || true
  if [ -n "$inv_refs" ]; then
    while IFS= read -r inv; do
      [ -n "$inv" ] || continue
      if validate_spec_citation "$_spec_file" "$inv"; then
        found_citation="yes"
        break
      fi
    done <<< "$inv_refs"
  fi

  # Check for heading citations (## Something)
  if [ "$found_citation" = "no" ]; then
    local heading_refs
    heading_refs="$(echo "$reasoning" | grep -oE '##+ [A-Za-z].*' 2>/dev/null)" || true
    if [ -n "$heading_refs" ]; then
      while IFS= read -r heading; do
        [ -n "$heading" ] || continue
        if validate_spec_citation "$_spec_file" "$heading"; then
          found_citation="yes"
          break
        fi
      done <<< "$heading_refs"
    fi
  fi

  if [ "$found_citation" = "yes" ]; then
    return 0
  else
    # Conservative level: missing citation → override to hard_stop
    return 1
  fi
}
