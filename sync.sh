#!/usr/bin/env bash
# Sync source files → single correctless/ plugin directory
# Run after editing files in the source directories (skills/, hooks/, templates/, helpers/)
# to propagate changes to correctless/

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

CHECK_ONLY=false
if [ "${1:-}" = "--check" ]; then
  CHECK_ONLY=true
fi

info() { echo "  ✓ $*"; }

DIRTY=false

# Helper: copy or check a single file
sync_file() {
  local src="$1" dst="$2"
  if [ "$CHECK_ONLY" = true ]; then
    if ! diff -q "$src" "$dst" >/dev/null 2>&1; then
      DIRTY=true
    fi
  else
    cp "$src" "$dst"
  fi
}

# Helper: copy or check directory contents recursively
sync_dir() {
  local src="$1" dst="$2"
  if [ "$CHECK_ONLY" = true ]; then
    if ! diff -rq "$src/" "$dst/" >/dev/null 2>&1; then
      DIRTY=true
    fi
  else
    cp -r "$src/"* "$dst/"
  fi
}

if [ "$CHECK_ONLY" = false ]; then
  echo ""
  echo "Syncing source → correctless/"
  echo "==============================="
  echo ""
fi

# --- Hooks ---
# Hooks are copied with one transformation: lines starting with `# Rule: `
# are stripped. These are dogfood rule-pointer comments (INV-021) that
# source-file agents use to find the canonical rule body, but user
# distributions installed from correctless/ must not ship dangling
# references to upstream-only paths. The pattern intentionally does NOT
# mention the upstream rule path literally — INV-024 forbids any .claude/
# reference in sync.sh. Matching `# Rule: ` is narrow enough: no other
# hook has a line starting with that prefix.
for hook in hooks/*.sh; do
  [ -f "$hook" ] || continue
  dst="correctless/hooks/$(basename "$hook")"
  if [ "$CHECK_ONLY" = true ]; then
    diff -q <(sed '/^# Rule: /d' "$hook") "$dst" >/dev/null 2>&1 || DIRTY=true
  else
    sed '/^# Rule: /d' "$hook" > "$dst"
  fi
done
# JSON hook configs (agent hooks like import-guard.json)
for hook_json in hooks/*.json; do
  [ -f "$hook_json" ] || continue
  sync_file "$hook_json" "correctless/hooks/$(basename "$hook_json")"
done
[ "$CHECK_ONLY" = false ] && info "Hooks → correctless/"

# --- Setup script ---
sync_file setup correctless/setup
if [ "$CHECK_ONLY" = false ]; then
  chmod +x correctless/setup
  info "Setup script → correctless/"
fi

# --- All templates (common + high-intensity) ---
for tmpl in templates/*.md templates/*.json; do
  [ -f "$tmpl" ] || continue
  sync_file "$tmpl" "correctless/templates/$(basename "$tmpl")"
done
sync_dir "templates/invariants" "correctless/templates/invariants"
[ "$CHECK_ONLY" = false ] && info "Templates → correctless/"

# --- Scripts (phase-transition scripts) ---
if [ "$CHECK_ONLY" = false ]; then
  mkdir -p "correctless/scripts"
fi
for script in scripts/*.sh; do
  [ -f "$script" ] || continue
  sync_file "$script" "correctless/scripts/$(basename "$script")"
done
# Sync scripts/wf/ subdirectory (workflow-advance decomposition modules)
if [ -d "scripts/wf" ]; then
  if [ "$CHECK_ONLY" = false ]; then
    mkdir -p "correctless/scripts/wf"
  fi
  for wf_module in scripts/wf/*.sh; do
    [ -f "$wf_module" ] || continue
    sync_file "$wf_module" "correctless/scripts/wf/$(basename "$wf_module")"
  done
fi
[ "$CHECK_ONLY" = false ] && info "Scripts → correctless/"

# --- Helpers (PBT guides) ---
sync_dir "helpers" "correctless/helpers"
[ "$CHECK_ONLY" = false ] && info "PBT helpers → correctless/"

# --- Agents (plugin sub-agents) ---
if [ "$CHECK_ONLY" = false ]; then
  mkdir -p "correctless/agents"
fi
for agent in agents/*.md; do
  [ -f "$agent" ] || continue
  sync_file "$agent" "correctless/agents/$(basename "$agent")"
done
[ "$CHECK_ONLY" = false ] && info "Agents → correctless/"

# --- Operator rule files (downstream backstop propagation, CS-020) ---
# Propagate the SFG lift-and-restore operator rule (sfg-deliverable.md) so
# installed projects receive the AP-037 procedure and can run the final-state
# backstop. The cmd_done gate itself ships downstream via the scripts/wf/
# propagation above (the named downstream backstop floor). The upstream rule
# path is assembled from parts to honor INV-024 (no literal upstream-rule path
# in a non-comment sync.sh line).
RULES_SRC_DIR=".$(printf 'claude')/rules"
if [ "$CHECK_ONLY" = false ]; then
  mkdir -p "correctless/rules"
fi
if [ -f "$RULES_SRC_DIR/sfg-deliverable.md" ]; then
  sync_file "$RULES_SRC_DIR/sfg-deliverable.md" "correctless/rules/sfg-deliverable.md"
fi
[ "$CHECK_ONLY" = false ] && info "Operator rules → correctless/"

# --- Shared skill constraints ---
if [ "$CHECK_ONLY" = false ]; then
  mkdir -p "correctless/skills/_shared"
fi
sync_file "skills/_shared/constraints.md" "correctless/skills/_shared/constraints.md"
[ "$CHECK_ONLY" = false ] && info "Shared constraints → correctless/"

# --- All skills (glob-based per AP-024) ---
for skill_dir in skills/*/; do
  [ -d "$skill_dir" ] || continue
  skill="$(basename "$skill_dir")"
  [ "$skill" = "_shared" ] && continue
  if [ "$CHECK_ONLY" = false ]; then
    mkdir -p "correctless/skills/$skill"
  fi
  sync_file "skills/$skill/SKILL.md" "correctless/skills/$skill/SKILL.md"
done
if [ "$CHECK_ONLY" = false ]; then
skill_count=$(find skills -mindepth 1 -maxdepth 1 -type d ! -name '_shared' | wc -l | tr -d ' ')
[ "$CHECK_ONLY" = false ] && info "All skills ($skill_count) → correctless/"
fi

# --- test-features templates (harness-fingerprint baseline) ---
if [ "$CHECK_ONLY" = false ]; then
  mkdir -p "correctless/templates/test-features"
fi
if [ -f "templates/test-features/baseline.md" ]; then
  sync_file "templates/test-features/baseline.md" "correctless/templates/test-features/baseline.md"
fi
[ "$CHECK_ONLY" = false ] && info "test-features templates → correctless/"

if [ "$CHECK_ONLY" = true ]; then
  # Skills: check for stale directories and count mismatch
  if [ -d "correctless/skills" ]; then
    for dist_skill_dir in correctless/skills/*/; do
      [ -d "$dist_skill_dir" ] || continue
      if [ ! -d "skills/$(basename "$dist_skill_dir")" ]; then
        DIRTY=true
      fi
    done
    src_count="$(ls -d skills/*/ 2>/dev/null | wc -l)"
    dist_count="$(ls -d correctless/skills/*/ 2>/dev/null | wc -l)"
    if [ "$src_count" != "$dist_count" ]; then
      DIRTY=true
    fi
  fi

  # Hooks, scripts, and scripts/wf: check for stale .sh files
  for dir in hooks scripts scripts/wf; do
    if [ -d "correctless/$dir" ]; then
      for dist_file in "correctless/$dir"/*.sh; do
        [ -f "$dist_file" ] || continue
        if [ ! -f "$dir/$(basename "$dist_file")" ]; then
          DIRTY=true
        fi
      done
    fi
  done

  # Templates: check for stale .md and .json files
  if [ -d "correctless/templates" ]; then
    for dist_tmpl in correctless/templates/*.md correctless/templates/*.json; do
      [ -f "$dist_tmpl" ] || continue
      if [ ! -f "templates/$(basename "$dist_tmpl")" ]; then
        DIRTY=true
      fi
    done
  fi

  # Hooks: check for stale .json files (agent hooks like import-guard.json)
  if [ -d "correctless/hooks" ]; then
    for dist_json in correctless/hooks/*.json; do
      [ -f "$dist_json" ] || continue
      if [ ! -f "hooks/$(basename "$dist_json")" ]; then
        DIRTY=true
      fi
    done
  fi
  # Hooks: check for missing .json files (source has it, dist doesn't)
  if [ -d "hooks" ]; then
    for src_json in hooks/*.json; do
      [ -f "$src_json" ] || continue
      if [ ! -f "correctless/hooks/$(basename "$src_json")" ]; then
        DIRTY=true
      fi
    done
  fi

  # Agents: check for stale .md files in both directions.
  # Loop kept as 'for dir in agents' (single-item today) to keep the
  # stale-file scan structure symmetric with the hooks/scripts loop above
  # and to make it cheap to add a second agent directory later without
  # restructuring — see INV-008(b) in tests/test-fix-diff-reviewer-agent.sh
  # which expects a 'for dir in ... agents' shape here.
  # shellcheck disable=SC2043
  for dir in agents; do
    if [ -d "correctless/$dir" ]; then
      for dist_file in "correctless/$dir"/*.md; do
        [ -f "$dist_file" ] || continue
        if [ ! -f "$dir/$(basename "$dist_file")" ]; then
          DIRTY=true
        fi
      done
    fi
    if [ -d "$dir" ]; then
      for src_file in "$dir"/*.md; do
        [ -f "$src_file" ] || continue
        if [ ! -f "correctless/$dir/$(basename "$src_file")" ]; then
          DIRTY=true
        fi
      done
    fi
  done

  # Rules: check for stale .md files (operator rule files propagated to dist).
  RULES_SRC_DIR_CHK=".$(printf 'claude')/rules"
  if [ -d "correctless/rules" ]; then
    for dist_rule in correctless/rules/*.md; do
      [ -f "$dist_rule" ] || continue
      if [ ! -f "$RULES_SRC_DIR_CHK/$(basename "$dist_rule")" ]; then
        DIRTY=true
      fi
    done
  fi

  # Check for stale top-level items in correctless/ not present in source
  for dist_item in correctless/*/; do
    [ -d "$dist_item" ] || continue
    local_item="$(basename "$dist_item")"
    # Expected top-level dirs: skills hooks templates helpers scripts rules agents
    case "$local_item" in
      skills|hooks|templates|helpers|scripts|rules|agents) ;; # expected — already checked via sync_file/sync_dir
      *) DIRTY=true ;; # unexpected directory in distribution
    esac
  done

  # Check for stale top-level files in correctless/ (only 'setup' expected)
  for dist_file in correctless/*; do
    [ -f "$dist_file" ] || continue
    local_file="$(basename "$dist_file")"
    case "$local_file" in
      setup) ;; # expected — already checked via sync_file
      *) DIRTY=true ;; # unexpected file in distribution
    esac
  done

  if [ "$DIRTY" = true ]; then
    exit 1
  fi
  exit 0
fi

echo ""
echo "Done. Verify with: git diff --stat"
echo ""
