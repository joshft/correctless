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

# ---------------------------------------------------------------------------
# INV-020 (cross-model-spec-review): ABS-041 lift-and-restore generalized to N
# deliverables. The sentinel records the SET of lifted paths as `lifted: <path>`
# lines. When such lines are present, check EACH recorded path independently:
# a recorded-lifted path that is ABSENT from SFG DEFAULTS is un-restored -> FAIL,
# even if a sibling deliverable HAS been restored. This prevents the single-
# deliverable self-deactivation (RS-028) from falsely passing when one of several
# lifted deliverables is restored while another is still un-restored.
# ---------------------------------------------------------------------------
# `|| true`: no `lifted:` lines is the legacy single-deliverable case, not an
# error — must not trip `set -e` (the pipeline returns grep's nonzero on no match).
LIFTED_PATHS="$(grep -E '^lifted:[[:space:]]*' "$SENTINEL" 2>/dev/null | sed -E 's/^lifted:[[:space:]]*//' || true)"

if [ -n "$LIFTED_PATHS" ]; then
  unrestored=""
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    # A lifted deliverable is RESTORED when its exact path is back in SFG DEFAULTS.
    if [ ! -f "$SFG" ] || ! grep -Fq "$p" "$SFG"; then
      unrestored="${unrestored}${p} "
    fi
  done <<EOF
$LIFTED_PATHS
EOF

  if [ -n "${unrestored// /}" ]; then
    {
      echo "FAIL: $SENTINEL exists with un-restored lifted deliverable(s): ${unrestored}"
      echo "An SFG lift commit is in the tree and the restore commit has not landed (AP-037 lift-and-restore)."
      echo "Sentinel lifecycle: the lift commit ADDS $SENTINEL + 'lifted:' lines; the restore commit re-adds each DEFAULTS line and REMOVES the sentinel."
      echo "Required: restore each listed path's exact DEFAULTS line in $SFG, run bash sync.sh, then remove the sentinel."
      echo "  git rm -f $SENTINEL && bash sync.sh && git add $SFG"
      echo "See .claude/rules/sfg-deliverable.md."
    } >&2
    exit 1
  fi
  # All recorded-lifted paths restored, but the sentinel is still present.
  {
    echo "FAIL: $SENTINEL exists though all recorded-lifted deliverables are restored."
    echo "Remove the stale sentinel: git rm -f $SENTINEL"
    echo "See .claude/rules/sfg-deliverable.md."
  } >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Legacy single-deliverable path (no `lifted:` lines in the sentinel).
# RS-028 self-deactivation: if the protected agent path is no longer in SFG
# DEFAULTS, this backstop is obsolete — NO-OP rather than fail forever.
# ---------------------------------------------------------------------------
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
