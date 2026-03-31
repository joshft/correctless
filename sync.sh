#!/usr/bin/env bash
# Sync source files → both plugin directories
# Run after editing files in the source directories (skills/, hooks/, templates/, helpers/)
# to propagate changes to correctless-lite/ and correctless-full/

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

info() { echo "  ✓ $*"; }

echo ""
echo "Syncing source → plugins"
echo "========================"
echo ""

# --- Hooks (shared by both) ---
cp hooks/workflow-gate.sh correctless-lite/hooks/workflow-gate.sh
cp hooks/workflow-gate.sh correctless-full/hooks/workflow-gate.sh
cp hooks/workflow-advance.sh correctless-lite/hooks/workflow-advance.sh
cp hooks/workflow-advance.sh correctless-full/hooks/workflow-advance.sh
info "Hooks → both plugins"

# --- Setup script (shared) ---
cp setup correctless-lite/setup
cp setup correctless-full/setup
chmod +x correctless-lite/setup correctless-full/setup
info "Setup script → both plugins"

# --- Shared templates ---
for tmpl in ARCHITECTURE.md AGENT_CONTEXT.md antipatterns.md workflow-config.json redaction-rules.md; do
  cp "templates/$tmpl" "correctless-lite/templates/$tmpl"
  cp "templates/$tmpl" "correctless-full/templates/$tmpl"
done
info "Common templates → both plugins"

# --- Full-only templates ---
for tmpl in workflow-config-full.json workflow-effectiveness.json drift-debt.json external-review-history.json; do
  cp "templates/$tmpl" "correctless-full/templates/$tmpl"
done
cp -r templates/invariants/* correctless-full/templates/invariants/
info "Full-only templates → correctless-full"

# --- Full-only helpers ---
cp -r helpers/* correctless-full/helpers/
info "PBT helpers → correctless-full"

# --- Lite skills ---
for skill in csetup cspec creview ctdd cverify cdocs crefactor cpr-review ccontribute cmaintain cstatus csummary cmetrics cdebug chelp cwtf; do
  mkdir -p "correctless-lite/skills/$skill"
  cp "skills/$skill/SKILL.md" "correctless-lite/skills/$skill/SKILL.md"
done
info "Lite skills (16) → correctless-lite"

# --- Full skills (all) ---
for skill in csetup cspec cmodel creview creview-spec ctdd cverify caudit cupdate-arch cdocs cpostmortem cdevadv credteam crefactor cpr-review ccontribute cmaintain cstatus csummary cmetrics cdebug chelp cwtf; do
  mkdir -p "correctless-full/skills/$skill"
  cp "skills/$skill/SKILL.md" "correctless-full/skills/$skill/SKILL.md"
done
info "Full skills (23) → correctless-full"

echo ""
echo "Done. Verify with: git diff --stat"
echo ""
