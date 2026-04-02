#!/usr/bin/env bash
# Sync source files → both plugin directories
# Run after editing files in the source directories (skills/, hooks/, templates/, helpers/)
# to propagate changes to correctless-lite/ and correctless-full/

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

# Helper: copy or check a directory recursively
sync_dir() {
  local src="$1" dst="$2"
  if [ "$CHECK_ONLY" = true ]; then
    if ! diff -rq "$src" "$dst" >/dev/null 2>&1; then
      DIRTY=true
    fi
  else
    cp -r "$src" "$dst"
  fi
}

if [ "$CHECK_ONLY" = false ]; then
  echo ""
  echo "Syncing source → plugins"
  echo "========================"
  echo ""
fi

# --- Hooks (shared by both) ---
for hook in workflow-gate.sh workflow-advance.sh statusline.sh audit-trail.sh; do
  sync_file "hooks/$hook" "correctless-lite/hooks/$hook"
  sync_file "hooks/$hook" "correctless-full/hooks/$hook"
done
[ "$CHECK_ONLY" = false ] && info "Hooks → both plugins"

# --- Setup script (shared) ---
sync_file setup correctless-lite/setup
sync_file setup correctless-full/setup
if [ "$CHECK_ONLY" = false ]; then
  chmod +x correctless-lite/setup correctless-full/setup
  info "Setup script → both plugins"
fi

# --- Shared templates ---
for tmpl in ARCHITECTURE.md AGENT_CONTEXT.md antipatterns.md workflow-config.json redaction-rules.md; do
  sync_file "templates/$tmpl" "correctless-lite/templates/$tmpl"
  sync_file "templates/$tmpl" "correctless-full/templates/$tmpl"
done
[ "$CHECK_ONLY" = false ] && info "Common templates → both plugins"

# --- Full-only templates ---
for tmpl in workflow-config-full.json workflow-effectiveness.json drift-debt.json external-review-history.json; do
  sync_file "templates/$tmpl" "correctless-full/templates/$tmpl"
done
if [ "$CHECK_ONLY" = true ]; then
  sync_dir "templates/invariants/." "correctless-full/templates/invariants/."
else
  cp -r templates/invariants/* correctless-full/templates/invariants/
  info "Full-only templates → correctless-full"
fi

# --- Full-only helpers ---
if [ "$CHECK_ONLY" = true ]; then
  sync_dir "helpers/." "correctless-full/helpers/."
else
  cp -r helpers/* correctless-full/helpers/
  info "PBT helpers → correctless-full"
fi

# --- Lite skills: csetup cspec creview ctdd cverify cdocs crefactor cpr-review ccontribute cmaintain cstatus csummary cmetrics cdebug chelp cwtf cquick crelease ---
for skill in csetup cspec creview ctdd cverify cdocs crefactor cpr-review ccontribute cmaintain cstatus csummary cmetrics cdebug chelp cwtf cquick crelease; do
  if [ "$CHECK_ONLY" = false ]; then
    mkdir -p "correctless-lite/skills/$skill"
  fi
  sync_file "skills/$skill/SKILL.md" "correctless-lite/skills/$skill/SKILL.md"
done
[ "$CHECK_ONLY" = false ] && info "Lite skills (18) → correctless-lite"

# --- Full skills (all): csetup cspec cmodel creview creview-spec ctdd cverify caudit cupdate-arch cdocs cpostmortem cdevadv credteam crefactor cpr-review ccontribute cmaintain cstatus csummary cmetrics cdebug chelp cwtf cquick crelease ---
for skill in csetup cspec cmodel creview creview-spec ctdd cverify caudit cupdate-arch cdocs cpostmortem cdevadv credteam crefactor cpr-review ccontribute cmaintain cstatus csummary cmetrics cdebug chelp cwtf cquick crelease; do
  if [ "$CHECK_ONLY" = false ]; then
    mkdir -p "correctless-full/skills/$skill"
  fi
  sync_file "skills/$skill/SKILL.md" "correctless-full/skills/$skill/SKILL.md"
done
[ "$CHECK_ONLY" = false ] && info "Full skills (25) → correctless-full"

if [ "$CHECK_ONLY" = true ]; then
  if [ "$DIRTY" = true ]; then
    exit 1
  fi
  exit 0
fi

echo ""
echo "Done. Verify with: git diff --stat"
echo ""
