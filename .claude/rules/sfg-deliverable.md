# SFG deliverable: lift-and-restore procedure (AP-037)

## When this rule applies

This rule loads when you edit `hooks/sensitive-file-guard.sh` (SFG) or any file
listed in the SFG `DEFAULTS` list. Two current deliverables are themselves in
DEFAULTS and therefore use this lift-and-restore affordance whenever a feature
develops them:

- `agents/fix-diff-reviewer.md` (the original AP-037 instance).
- `scripts/meta-record.sh` (the sanctioned sole-writer for `.correctless/meta/*.json`,
  ABS-047 — added to DEFAULTS by the calibration-writer feature, MA-M7). Its
  three DEFAULTS forms (`scripts/meta-record.sh`, `.correctless/scripts/meta-record.sh`,
  and the bare `meta-record.sh`) are all removed on lift and restored together.
- `scripts/chores-authorize.sh` (the sanctioned sole-writer for the /cchores
  protected-file affordance marker, ABS-049 — added to DEFAULTS by the
  cchores-protected-affordance feature, R2-L / EA-004). Its three DEFAULTS forms
  (`scripts/chores-authorize.sh`, `.correctless/scripts/chores-authorize.sh`, and
  the bare `chores-authorize.sh`) are all removed on lift and restored together.
  Developing it uses the generalized `lift-active:<path>` sentinel
  (`echo "lift-active: scripts/chores-authorize.sh" > .correctless/.sfg-lift-active`).

The `sensitive-file-guard.sh` hook (SFG) has no per-file allowlist primitive:
`custom_patterns` only ADDS protection, never excepts a default. When an
SFG-protected file IS a feature's primary deliverable, every TDD/QA/audit
fix-round that touches it triggers a block. This is the **AP-037** class:
*the protected asset is the deliverable — the guard has no legitimate-edit
affordance.*

## Lift-and-restore procedure

1. **Lift commit (start of iteration).** Remove the deliverable's exact line from
   the SFG `DEFAULTS` list (in both `hooks/sensitive-file-guard.sh` and the
   synced mirror `correctless/hooks/sensitive-file-guard.sh`) AND, in the SAME
   commit, ADD the sentinel file:

   ```sh
   # Historical form (fix-diff-reviewer): a feature name.
   echo "lift-active: <feature-name>" > .correctless/.sfg-lift-active
   # Generalized form (MA-M7): name the lifted deliverable PATH so the backstop
   # checks THAT path rather than the hardcoded fix-diff-reviewer default. Use
   # this when lifting a non-fix-diff-reviewer deliverable, e.g. meta-record.sh:
   #   echo "lift-active: scripts/meta-record.sh" > .correctless/.sfg-lift-active
   ```

   The sentinel `.correctless/.sfg-lift-active` is itself in SFG DEFAULTS, so the
   guard's own disable-switch is guarded against agent writes. When the
   `lift-active:` value contains a slash it is treated as the lifted deliverable
   path; a slash-free value falls back to the fix-diff-reviewer default
   (backward-compatible — see `scripts/check-no-pending-sfg-lift.sh`).

2. **Iterate freely.** While the sentinel is present, the
   `tests/test-fix-diff-reviewer-agent.sh` lift-state assertion SKIPs (so
   `commands.test` and /cauto consolidation are not blocked).

3. **Restore commit (before push).** Restore the exact DEFAULTS line
   (`agents/fix-diff-reviewer.md`), run `bash sync.sh`, and REMOVE the sentinel
   in the same commit:

   ```sh
   git rm -f .correctless/.sfg-lift-active && bash sync.sh
   ```

## Mandatory pre-push step

Before pushing, run the final-state backstop manually:

- From the source tree:    `bash scripts/check-no-pending-sfg-lift.sh`
- From an installed project: `bash .correctless/scripts/check-no-pending-sfg-lift.sh`

The script FAILS (non-zero) when `.correctless/.sfg-lift-active` is still in the
tree and the lifted deliverable's path (read from the sentinel's `lift-active:`
line when it names a path, else `agents/fix-diff-reviewer.md`) is still in SFG
DEFAULTS. It NO-OPs (exit 0) when that path is no longer in DEFAULTS (RS-028
self-deactivation).

The same backstop runs in CI as the dedicated `sfg-lift-check` job and in
`/cauto` Step 8 before push, and the `cmd_done` workflow-advance gate refuses the
`done` transition while the sentinel is present.

## Sentinel lifecycle (summary)

- **ADD** `.correctless/.sfg-lift-active` in the lift commit.
- **REMOVE** it in the restore commit.
- Both are real tree changes — the sentinel cannot be local-only and silently
  bypass the gate.

See AP-037 in `.correctless/antipatterns.md` and ABS-041 in
`.correctless/ARCHITECTURE.md`.
