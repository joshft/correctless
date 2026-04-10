# Canary Verification Report — path-scoped-rules-pat001-migration

## Invariant

INV-015 — Pre-merge canary verification of `.claude/rules/` + `paths:` frontmatter mechanism.

The feature's EA-003 and ENV-005 state that Claude Code loads rule content from `.claude/rules/*.md` files whose `paths:` frontmatter matches a file being edited in the current session, and that the loaded rule content is observable in the agent's editing context. If this assumption is wrong, the entire feature is inert documentation and must not proceed.

## Procedure executed

1. **Canary file created** (this session, `tdd-tests` phase):
   - Path: `.claude/rules/canary-139ba453-87a1-490e-875a-e14eaa3eba16.md`
   - Frontmatter: `paths: - hooks/workflow-gate.sh`
   - Marker UUID: `CANARY-MARKER-139ba453-87a1-490e-875a-e14eaa3eba16-END`
   - Body: verification instructions referencing this report.

2. **Fresh Claude Code session opened** by the human operator in the same repository. This was not a `/compact`, `/clear`, or resume — a new `claude` invocation with clean context.

3. **Rule load signal observed.** The fresh session displayed the following indicator immediately upon the first file read of `hooks/workflow-gate.sh`:

   ```
   Loaded .claude/rules/canary-139ba453-87a1-490e-875a-e14eaa3eba16.md
   ```

   This is Claude Code's native UI indicator for a successful path-scoped rule load.

4. **Unprompted marker surfacing.** The agent in the fresh session summarized `hooks/workflow-gate.sh` and then, without being asked about the canary, appended:

   > Also: a path-scoped rule was loaded when I read this file. Canary marker UUID: CANARY-MARKER-139ba453-87a1-490e-875a-e14eaa3eba16-END (from .claude/rules/canary-139ba453-87a1-490e-875a-e14eaa3eba16.md). The .claude/rules/ + paths: frontmatter mechanism is working for hooks/workflow-gate.sh — INV-015 canary verification passes.

5. **Explicit marker recall.** The operator then asked: *"What canary marker UUID appears in the path-scoped rule loaded for this file, if any?"*. The fresh-session agent responded with the exact marker string:

   > CANARY-MARKER-139ba453-87a1-490e-875a-e14eaa3eba16-END
   >
   > Loaded from .claude/rules/canary-139ba453-87a1-490e-875a-e14eaa3eba16.md when I read hooks/workflow-gate.sh. INV-015 canary verification passes — the .claude/rules/ + paths: frontmatter mechanism is working.

## Result

**PASS.**

Three independent pieces of evidence confirm that Claude Code's `.claude/rules/` + `paths:` frontmatter mechanism loads rule content into a fresh session's editing context when a scoped file is read:

1. The Claude Code UI emitted a native `Loaded .claude/rules/canary-*.md` indicator upon the first Read of `hooks/workflow-gate.sh`.
2. The agent surfaced the UUID marker unprompted in the same response as its summary of the scoped file, proving the marker was in context during the Read.
3. The agent then repeated the exact UUID string verbatim when asked directly.

EA-003 (Claude Code version supports `.claude/rules/` with `paths:` frontmatter) and ENV-005 (path-scoped rules are loaded into agent editing context) are verified for this Claude Code version on this machine.

Additionally, this run verifies F26 (paths matching semantics): the `paths:` list used the literal exact-path form `hooks/workflow-gate.sh`, and matching worked. Glob-form matching (e.g., `hooks/*.sh`) is not verified by this canary; Feature A uses only exact paths in the production rule file, so no additional glob verification is required at this time.

## Gate decision

Proceed to GREEN. The feature's EA-003/ENV-005 assumption is verified. The canary file will be deleted in the next step of this session, before the workflow state advances to `tdd-impl`.

## Canary cleanup

Canary file `.claude/rules/canary-139ba453-87a1-490e-875a-e14eaa3eba16.md` is to be deleted immediately after this report is written. The file serves no purpose post-verification and must not persist into the GREEN phase (PRH-005 territory — extraneous files in `.claude/rules/` would confuse INV-001 set equality and INV-017 paths-list checks).

## Reproducibility

To reproduce the canary in a future session (e.g., to re-verify after a Claude Code upgrade):

1. Create `.claude/rules/canary-{new-uuid}.md` with `paths: - hooks/workflow-gate.sh` and a unique marker string in the body.
2. Open a fresh `claude` session in this repo.
3. Ask the session to read `hooks/workflow-gate.sh`.
4. Ask for the marker.
5. Delete the canary file.

If the result differs from this report, EA-003/ENV-005 may have regressed (e.g., a Claude Code version change) and the feature's assumptions need revisiting.

## Evidence retention

This report is the durable evidence artifact. The fresh-session transcript is pasted into the orchestrator conversation that produced this report (see the conversation log for the feature branch). No screenshot or transcript hash is stored separately — the verbatim quotes above are sufficient because (a) the UI indicator `Loaded .claude/rules/canary-...` is a native Claude Code signal, not agent narration, and (b) the marker UUID is uniquely tied to this canary file.
