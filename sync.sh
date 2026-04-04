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
for hook in workflow-gate.sh workflow-advance.sh statusline.sh audit-trail.sh; do
  sync_file "hooks/$hook" "correctless/hooks/$hook"
done
[ "$CHECK_ONLY" = false ] && info "Hooks → correctless/"

# --- Setup script ---
sync_file setup correctless/setup
if [ "$CHECK_ONLY" = false ]; then
  chmod +x correctless/setup
  info "Setup script → correctless/"
fi

# --- All templates (common + high-intensity) ---
for tmpl in ARCHITECTURE.md AGENT_CONTEXT.md antipatterns.md workflow-config.json redaction-rules.md workflow-config-full.json workflow-effectiveness.json drift-debt.json external-review-history.json spec-lite.md spec-full.md; do
  sync_file "templates/$tmpl" "correctless/templates/$tmpl"
done
sync_dir "templates/invariants" "correctless/templates/invariants"
[ "$CHECK_ONLY" = false ] && info "Templates → correctless/"

# --- Helpers (PBT guides) ---
sync_dir "helpers" "correctless/helpers"
[ "$CHECK_ONLY" = false ] && info "PBT helpers → correctless/"

# --- All 26 skills ---
for skill in csetup cspec cmodel creview creview-spec ctdd cverify caudit cupdate-arch cdocs cpostmortem cdevadv credteam crefactor cpr-review ccontribute cmaintain cstatus csummary cmetrics cdebug chelp cwtf cquick crelease cexplain; do
  if [ "$CHECK_ONLY" = false ]; then
    mkdir -p "correctless/skills/$skill"
  fi
  sync_file "skills/$skill/SKILL.md" "correctless/skills/$skill/SKILL.md"
done
[ "$CHECK_ONLY" = false ] && info "All skills (26) → correctless/"

if [ "$CHECK_ONLY" = true ]; then
  # Check for stale skill directories in correctless/skills/ not present in source
  if [ -d "correctless/skills" ]; then
    for dist_skill_dir in correctless/skills/*/; do
      [ -d "$dist_skill_dir" ] || continue
      local_skill="$(basename "$dist_skill_dir")"
      if [ ! -d "skills/$local_skill" ]; then
        DIRTY=true
      fi
    done
    # Check skill count matches
    src_count="$(ls -d skills/*/ 2>/dev/null | wc -l)"
    dist_count="$(ls -d correctless/skills/*/ 2>/dev/null | wc -l)"
    if [ "$src_count" != "$dist_count" ]; then
      DIRTY=true
    fi
  fi

  # Check for stale top-level items in correctless/ not present in source
  for dist_item in correctless/*/; do
    [ -d "$dist_item" ] || continue
    local_item="$(basename "$dist_item")"
    # Expected top-level dirs: skills, hooks, templates, helpers
    case "$local_item" in
      skills|hooks|templates|helpers) ;; # expected — already checked via sync_file/sync_dir
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
