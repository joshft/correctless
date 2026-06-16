#!/usr/bin/env bash
# Correctless — SFG lift-and-restore final-state backstop (CS-012a / AP-037).
#
# Non-skippable final-state check. Deliberately lives OUTSIDE the
# tests/test-*.sh glob so `commands.test` does NOT run it (the SKIP sentinel
# path in tests/test-fix-diff-reviewer-agent.sh keeps /cauto consolidation
# unblocked during iteration). This script is invoked at the pre-push / CI /
# /cauto Step 8 gate, where it FAILS unconditionally if a lift sentinel is
# still in the tree.
#
# Self-deactivation (RS-028): if agents/fix-diff-reviewer.md is no longer in the
# SFG DEFAULTS list, the lift-and-restore contract no longer applies and this
# script NO-OPs (exit 0) — so a future #171-landed branch cannot turn it into
# permanently-passing dead code (AP-022).
set -euo pipefail

SENTINEL=".correctless/.sfg-lift-active"
SFG="hooks/sensitive-file-guard.sh"
DEFAULTS_LINE="agents/fix-diff-reviewer.md"

# No sentinel -> clean, nothing to restore.
[ -f "$SENTINEL" ] || exit 0

# RS-028 self-deactivation: if the protected agent path is no longer in SFG
# DEFAULTS, this backstop is obsolete — NO-OP rather than fail forever.
if [ ! -f "$SFG" ] || ! grep -Fq "$DEFAULTS_LINE" "$SFG"; then
  exit 0
fi

# Sentinel present AND agent path still guarded -> a lift commit is in the tree
# without its restore commit. FAIL with the remediation message.
{
  echo "FAIL: $SENTINEL exists."
  echo "A SFG lift commit is in the tree and the restore commit has not landed (AP-037 lift-and-restore)."
  echo "Sentinel lifecycle: the lift commit ADDS $SENTINEL; the restore commit REMOVES it."
  echo "Required: restore the exact DEFAULTS line '$DEFAULTS_LINE' in $SFG, then remove the sentinel."
  echo "Copy-pasteable restore:"
  echo "  git rm -f $SENTINEL && bash sync.sh && git add $SFG"
  echo "See .claude/rules/sfg-deliverable.md."
} >&2
exit 1
