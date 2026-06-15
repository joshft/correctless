#!/usr/bin/env bash
# Correctless — Final-state SFG-lift sentinel detection (INV-012a).
#
# Purpose: backstop that the AP-037 lift-and-restore protocol completed
# before push. Fails when .correctless/.sfg-lift-active exists in the tree,
# regardless of any other state.
#
# Invoked from:
#   - CI workflow (single line: `bash scripts/check-no-pending-sfg-lift.sh`)
#   - /cauto Step 8 consolidation (pre-push gate)
#   - operator pre-push (documented at .claude/rules/sfg-deliverable.md)
#
# Lives OUTSIDE the tests/test-*.sh glob — deliberately not in commands.test —
# so iteration during lift state is not blocked by this gate.
#
# Exit codes:
#   0  — no sentinel present, push is safe
#   2  — sentinel present, push is blocked

set -uo pipefail

SENTINEL=".correctless/.sfg-lift-active"

if [ ! -e "$SENTINEL" ]; then
  exit 0
fi

# Sentinel present — emit a multi-line remediation message naming AP-037
# and the restore-step procedure, then exit 2.
cat >&2 <<EOF
FAIL: ${SENTINEL} exists.
A SFG lift commit is in the tree and the restore commit has not landed.
Required: restore agents/fix-diff-reviewer.md to the DEFAULTS list in
  hooks/sensitive-file-guard.sh AND correctless/hooks/sensitive-file-guard.sh,
  delete ${SENTINEL}, run bash sync.sh, and commit. This must land before push.
See AP-037 (PMB-017) and .claude/rules/sfg-deliverable.md for the lift-and-restore
procedure documenting why iteration on SFG-protected deliverables uses a sentinel-mediated
lift, and what the restore commit must contain.
EOF
exit 2
