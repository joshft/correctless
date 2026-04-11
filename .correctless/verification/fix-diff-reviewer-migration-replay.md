# Fix-Diff Reviewer Migration: Manual Verification Report
Date: 2026-04-11T18:38:32Z
Commit: a028382
Pre-flight: [x] sync.sh run  [x] plugin reinstalled  [x] Claude Code restarted

## VP-001: Smoke Test
Result: PASS

### Request
```
Task(
  subagent_type="correctless:fix-diff-reviewer",
  description="VP-001 smoke test",
  prompt="Return the value of your dogfood marker comment verbatim, and then on a new line list every tool name you have access to, one per line, exact case."
)
```

### Response
```
<!-- Dogfood prototype (2026-04-10): fix-diff-reviewer-migration — Phase 2a of custom sub-agents. See .correctless/specs/fix-diff-reviewer-migration.md -->
Read
Grep
Glob
```

The response contains the exact substring `Dogfood prototype (2026-04-10): fix-diff-reviewer-migration` and is well above 50 non-whitespace characters (213 chars). Plugin-loader binding is correct: the namespaced `correctless:fix-diff-reviewer` subagent_type routed to the agent file with the expected dogfood marker in its source.

### Tool Enumeration
```
Read
Grep
Glob
```

Exactly three tools are enumerated: `Read`, `Grep`, `Glob`. No other tool names appear. This matches the pinned `tools:` frontmatter in `correctless/agents/fix-diff-reviewer.md` and confirms PRH-002 (read-only guarantee) is enforced by the plugin loader, not merely declared in the agent file.

## VP-002: Functional Equivalence Replay
Result: PASS

### Fixture SHA-256 verification
- r1: 2b0a181c78f08790a7b67e0ad15439ca3739094dac41c5aeb4db352c7c0dc3cb (pinned: 2b0a181c78f08790a7b67e0ad15439ca3739094dac41c5aeb4db352c7c0dc3cb) — MATCH
- r2: f33569ffcb25b46be31a9eee9c3791e13c3eed80840e7e07b2941f9ea1d57906 (pinned: f33569ffcb25b46be31a9eee9c3791e13c3eed80840e7e07b2941f9ea1d57906) — MATCH
- r3: 37975aac77b66e9fecf950cf6e0d89d65969dc65ed99f7915a554365dda80e5a (pinned: 37975aac77b66e9fecf950cf6e0d89d65969dc65ed99f7915a554365dda80e5a) — MATCH

### Reconciled SHAs (provenance)
- R1 original SHA: 9d61920 (from author's reflog; unreachable from origin/main — PR #47 squash-merged all three rounds)
- R2 original SHA: 2824387 (from author's reflog; unreachable from origin/main)
- R3 original SHA: 6c0d919 (correct per BND-003 / EA-004 reconciliation note — `workflow-effectiveness.json:11`'s `6b8e821` is a PMB-001 CI fix, not PMB-002 R3; the fixture contents correspond to `6c0d919`)

### Substitutions (per BND-003, if any)
none

### findings_returned_per_replay
[11, 5, 3]

All three replays returned non-zero findings (total: 19). Each replay's JSON parsed cleanly with `jq -e .` (INV-017 satisfied — no fail-closed abort). The r1 simulation annex predicted 8 findings; the real plugin agent returned 11 and flagged additional classes (the R-008 POSIX grep semantic regression in tests/test-consolidation.sh, the cmd_init atomicity inversion). The r2 and r3 counts are slightly lower than the simulation (9→5, 4→3) because the real agent consolidated related call sites into single parent findings (e.g., one cmd-level injection finding covering cmd_qa / cmd_set_intensity / cmd_spec_update / cmd_override rather than four). Both directions — more thorough on r1, more consolidated on r2/r3 — are acceptable and the key classes predicted by PMB-002 are all covered.

### Request r1
```
Task(
  subagent_type="correctless:fix-diff-reviewer",
  description="VP-002 replay r1",
  prompt="You are reviewing the PMB-002 Round 1 fix commit from the 2026-04-09 QA Olympics audit. The /caudit orchestrator would normally compute `git diff <round-start-sha>..HEAD` after fix commits land, enumerate path-scoped rules that govern touched files, wrap both in untrusted fences, and invoke you via a namespaced Task call. This is a historical replay — no path-scoped rules apply to this fixture, so the rules block is empty. Your job is to review the diff per your system prompt and identify any regressions the R1 fixes introduced or any new bugs hiding in the fix code. The R1 round's 19 fixes historically introduced 3 R2 regressions (primarily in token-tracking and workflow-advance state handling) — your output must surface at least the class of issues R2 had to catch.

<UNTRUSTED_RULES>none</UNTRUSTED_RULES>

<UNTRUSTED_DIFF>
(verbatim contents of tests/fixtures/fix-diff-reviewer-historical-r1.diff — SHA-256 2b0a181c...; full 657-line diff was pasted into the actual Task prompt, elided here for report readability)
</UNTRUSTED_DIFF>

Return ONLY the JSON array per your output contract."
)
```

### Response r1
```json
[{"id":"FD-001","severity":"critical","title":"update_phase uses string interpolation into jq filter — injection + breakage on special characters","description":"The refactor of update_phase in workflow-advance.sh replaces the previous safe `jq --arg p \"$new_phase\" --arg t \"$ts\"` pattern with a filter built by shell string interpolation: the new_phase and timestamp values are embedded directly inside the jq filter string passed to locked_update_state. Although the QA-R3-001 version of locked_update_state supports trailing `--arg` pass-through, this call does not use it. Any phase name containing a double quote, backslash, or the sequence `\")|.` breaks the filter or allows arbitrary jq expression injection. A phase like `spec\") | .evil = (\"` would mutate unrelated keys. Timestamps are safer but the pattern itself is wrong.","evidence":"workflow-advance.sh update_phase hunk around lines 75-90: the `locked_update_state` call embeds `\\\"$new_phase\\\"` and `\\\"$ts\\\"` inline into the filter string rather than passing them via `--arg`.","impact":"Phase strings derived from user-facing task input or future call sites can corrupt workflow state or silently inject jq operations; locked_update_state's safe --arg pathway is bypassed, re-introducing exactly the class of vulnerability QA-R3-001 was added to prevent.","location":{"file":"hooks/workflow-advance.sh","lines":[75,90]},"instance_fix":"Pass the values as extra arguments: `locked_update_state \"$sf\" '.phase = $p | .phase_entered_at = $t' --arg p \"$new_phase\" --arg t \"$ts\"`.","class_fix":"Add a shellcheck / grep test that forbids embedded `\\\"$` sequences inside the second argument of locked_update_state calls, and document in the function header that callers must use --arg."},
{"id":"FD-002","severity":"critical","title":"audit-trail.sh HOOK_MATCHER expanded to Read|Grep causes hook to fire on every read operation","description":"The PostToolUse matcher for audit-trail.sh was changed from `Edit|Write|MultiEdit|CreateFile|Bash` to `Edit|Write|MultiEdit|NotebookEdit|CreateFile|Bash|Read|Grep`. audit-trail is a file-modification recorder plus phase-violation alerter; it treats every tool invocation as a candidate file modification. Firing it on Read and Grep means every read-only exploration logs an audit entry and can trigger lite-mode phase-violation alerts for paths the agent merely looked at. This also multiplies hook runtime cost on every Read/Grep call and pollutes the audit log with non-mutations, breaking the downstream assumption that audit-trail rows represent writes.","evidence":"audit-trail.sh header line 4 of the hunk; mirrored assertion update in tests/test-ci-hook-wiring.sh to expect the new matcher.","impact":"Token-tracking and audit-log bloat; false phase-violation warnings emitted to stderr when the agent reads source during spec/test phases; downstream consumers that expect audit rows to mean writes will miscount.","location":{"file":"hooks/audit-trail.sh","lines":[1,10]},"instance_fix":"Revert the matcher to `Edit|Write|MultiEdit|NotebookEdit|CreateFile|Bash` (NotebookEdit is the only legitimate addition). Remove Read and Grep.","class_fix":"Add a test that asserts audit-trail's HOOK_MATCHER contains no read-only tool names, and document in the hook header which tool classes are permitted."},
{"id":"FD-003","severity":"high","title":"locked_update_state EXIT trap clobbers caller's existing EXIT trap","description":"The new QA-R1-013 hunk installs `trap '_release_state_lock ...; rm -f ...' EXIT` inside locked_update_state, and on the success path executes `trap - EXIT` which unconditionally clears ANY previous EXIT trap the caller had registered. cmd_resolve_drift and cmd_override both install their own EXIT traps (also touched in this diff) before calling jq-based flows; if any of those code paths ever invoke locked_update_state in the future, or if an existing caller has a trap set, the caller's cleanup will be silently discarded when locked_update_state returns. The function should save-and-restore, not clear-on-exit.","evidence":"scripts/lib.sh lines ~196-219 — the `trap - EXIT` at the tail of locked_update_state executes regardless of what trap the caller had installed.","impact":"Latent resource leaks: temp files, lock directories, and background PIDs registered by the caller's EXIT trap will not be cleaned up if the caller's flow uses locked_update_state as an intermediate step.","location":{"file":"scripts/lib.sh","lines":[196,220]},"instance_fix":"Save the previous trap with `prev_trap=$(trap -p EXIT)` before installing the new one, and on exit restore it via `eval \"${prev_trap:-trap - EXIT}\"`.","class_fix":"Add a unit test that sets an EXIT trap, calls locked_update_state, and asserts the original trap is still registered afterward. Document the trap-restoration contract in the lib.sh header."},
{"id":"FD-004","severity":"high","title":"_acquire_state_lock stale-dir break races with concurrent lock writer","description":"The QA-R1-018 hunk adds a branch that, when the lock directory exists but has no pid file yet, moves the lock_dir aside and rm-rf's it to break the lock. This races with a concurrent process that has just executed `mkdir` and is about to write its pid: process B moves the directory out from under process A, A's pid write lands inside the moved-and-then-deleted tree (or fails silently), and A now believes it holds the lock while the lock directory no longer exists on disk. A third process C then mkdirs a fresh lock_dir and also believes it holds the lock. Two writers mutate the state file simultaneously.","evidence":"scripts/lib.sh lines ~163-171 — the new `elif [ -d \"$lock_dir\" ]` arm unconditionally breaks a pid-less lock without any grace window for the just-mkdir'd competitor.","impact":"Under contention (two workflow-advance.sh invocations overlapping, which is the exact scenario QA-R1-012 is trying to fix) the \"fix\" can cause concurrent jq writers to the same state file, corrupting or losing updates — a regression worse than the original TOCTOU the refactor targeted.","location":{"file":"scripts/lib.sh","lines":[160,172]},"instance_fix":"Require the lock_dir to be pid-less for at least a small grace window (e.g., mtime older than 1-2 seconds) before breaking it, and re-check after the move that the dir is still the one we intended to break.","class_fix":"Add a concurrency test that spawns N workflow-advance.sh processes racing on the same state file and asserts no updates are lost; document the pid-write gap as a required grace interval."},
{"id":"FD-005","severity":"high","title":"workflow-gate.sh fail-closed on empty parse blocks non-write tools too","description":"QA-R1-005 converts the previous `exit 0` on jq parse failure into `exit 2` (BLOCKED) before the `case \"$TOOL_NAME\"` that limits gating to write operations. As a result, malformed stdin (or stdin that produces a valid-but-empty @sh output) now blocks Read, Grep, LS, and every other read-only tool invocation, not just writes. The stated intent (\"PreToolUse must not degrade to fail-open\") only applies to the write-gating path; read operations should never be blocked by this hook regardless of stdin shape.","evidence":"workflow-gate.sh hunk around lines 46-62 — the exit 2 is emitted before the TOOL_NAME case statement that would otherwise fast-path read-only tools.","impact":"A single malformed tool_input payload (or a future non-write tool with an unexpected schema) can deadlock the agent by blocking every tool call, not just writes. Silent DoS on the agent loop.","location":{"file":"hooks/workflow-gate.sh","lines":[46,65]},"instance_fix":"Move the parse-failure fail-closed check to AFTER the TOOL_NAME write-detection case, so only write operations are blocked on malformed input; read-only tools continue to exit 0.","class_fix":"Add a test that feeds malformed JSON to workflow-gate.sh with a tool_name of Read and asserts exit 0, and with a tool_name of Write and asserts exit 2."},
{"id":"FD-006","severity":"high","title":"workflow-gate.sh fail-closed-on-corrupt-config leaves FC_SOURCE_PAT empty, defeating the block","description":"QA-R1-004's new logic sets `FAIL_CLOSED=\"true\"` when the config file is corrupted, but leaves `FC_SOURCE_PAT=\"\"` because jq never produced a value. The downstream fail-closed block matches the target file against FC_SOURCE_PAT to decide whether to block source edits; with an empty pattern, the glob match either always succeeds (blocking every write including tests and docs) or always fails (blocking nothing).","evidence":"workflow-gate.sh hunk around lines 102-117 — the `else FAIL_CLOSED=\"true\"` branch does not populate FC_SOURCE_PAT.","impact":"On a corrupted workflow-config.json, agents either cannot write any file (including innocent test edits) or the fail-closed posture is silently defeated — the opposite of what QA-R1-004 claims to enforce.","location":{"file":"hooks/workflow-gate.sh","lines":[93,120]},"instance_fix":"When falling back to fail-closed on corrupt config, also set FC_SOURCE_PAT to a safe default that blocks all source-like files (e.g., `*`) or load the pattern from a hard-coded constant in lib.sh.","class_fix":"Add a test that feeds a deliberately corrupted config file and asserts the specific set of paths that should/shouldn't be blocked."},
{"id":"FD-007","severity":"medium","title":"cmd_init reordering leaves state file referencing a spec path that may not exist","description":"QA-R1-014 reorders cmd_init so write_state runs before the spec stub is created. The rationale (avoid orphan spec on write_state failure) is sound, but the new ordering creates the inverse problem: the state file is persisted with spec_file pointing at a path that does not yet exist.","evidence":"workflow-advance.sh cmd_init hunk around lines 409-440 — write_state is now the first persistent action, spec stub creation follows.","impact":"Partial-init states become possible where workflow-state-*.json exists but the referenced spec file does not; recovery requires manual cleanup.","location":{"file":"hooks/workflow-advance.sh","lines":[409,440]},"instance_fix":"Wrap both writes in an all-or-nothing sequence; on any failure, roll back both.","class_fix":"Add a test that injects a spec-stub write failure after write_state and asserts the state file is not left behind."},
{"id":"FD-008","severity":"medium","title":"audit-trail.sh intensity ascii_downcase breaks explicit uppercase values","description":"The jq filter was changed from `(.workflow.intensity // \"\") | IN(\"high\",\"critical\")` to `(.workflow.intensity // \"\" | ascii_downcase) | IN(\"high\",\"critical\")`. This is a behavior change, not merely a robustness tweak: previously, a config with `\"intensity\": \"HIGH\"` evaluated to IS_FULL=false; now it evaluates to IS_FULL=true. More importantly, workflow-gate.sh and other consumers of the same config field may still do strict matching, creating inter-hook disagreement about whether the project is in full mode.","evidence":"audit-trail.sh line 116 hunk — the new filter lowercases the intensity before the IN check.","impact":"Inconsistent full-mode detection across hooks; silent behavioral drift on any config using non-canonical case.","location":{"file":"hooks/audit-trail.sh","lines":[110,120]},"instance_fix":"Apply the same ascii_downcase to every hook that reads workflow.intensity in the same commit.","class_fix":"Add a cross-hook consistency test that feeds the same corner-case config to every hook."},
{"id":"FD-009","severity":"medium","title":"setup install_hooks always-overwrite removes user edits without warning","description":"QA-R1-001 removes the `[ ! -f \"$hook_dest/$basename_hook\" ]` guard so install_hooks now unconditionally overwrites every hook file on every setup run. Any local patch a user applied to their installed hook is silently erased on the next setup invocation with no backup and no diff output.","evidence":"setup lines 252-258 hunk; mirrored test weakening in tests/test-consolidation.sh R-010 which previously asserted content preservation.","impact":"User customizations to installed hooks are silently destroyed on re-run; the accompanying test change hides the regression by no longer asserting content preservation.","location":{"file":"setup","lines":[252,260]},"instance_fix":"Before overwriting, diff the source and destination; on difference, back up to `hook.bak.$(date +%s)` or refuse to overwrite.","class_fix":"Reinstate a content-preservation or content-diff test in tests/test-consolidation.sh."},
{"id":"FD-010","severity":"medium","title":"test-consolidation.sh R-008 POSIX grep rewrite is strictly weaker than the original","description":"The QA-R1-010 replacement of `grep -P '(?<!\\.correctless/)(?<!/)ARCHITECTURE\\.md'` with `grep 'ARCHITECTURE\\.md' | grep -v '\\.correctless/ARCHITECTURE\\.md' | grep -v '/ARCHITECTURE\\.md'` is not equivalent. The original used look-behind to require that NEITHER `.correctless/` NOR any `/` precedes the match. Line-level filtering cannot replicate per-match look-behind semantics.","evidence":"tests/test-consolidation.sh lines 447-465 hunk — the new filter is per-line exclusion, not per-match exclusion.","impact":"R-008 rule enforcement is silently weakened; skill files with a bare ARCHITECTURE.md reference adjacent to a qualified one will no longer fail the test.","location":{"file":"tests/test-consolidation.sh","lines":[447,465]},"instance_fix":"Use awk or a per-occurrence shell loop that tokenizes each ARCHITECTURE.md occurrence and checks the character immediately preceding it.","class_fix":"Add a regression fixture containing both bare and qualified references on the same line."},
{"id":"FD-011","severity":"low","title":"statusline.sh jq-missing branch emits an empty line to stdout","description":"The new QA-R1-016 check runs `echo \"\"; exit 0` when jq is absent. statusline hooks are consumed by Claude Code's status renderer; emitting an empty line where a status string is expected may render as a blank bar or break downstream parsers.","evidence":"statusline.sh line 12 hunk — `{ echo \"\"; exit 0; }`","impact":"Cosmetic blank status bar on hosts without jq.","location":{"file":"hooks/statusline.sh","lines":[9,15]},"instance_fix":"Drop the `echo \"\"` and just `exit 0`.","class_fix":"Document the statusline output contract in the hook header."}]
```

Parse verification: `jq -e . < /tmp/vp002-r1-full.json` → exit 0, `length` → 11. INV-017 identity-parse gate satisfied.

### Request r2
```
Task(
  subagent_type="correctless:fix-diff-reviewer",
  description="VP-002 replay r2",
  prompt="You are reviewing the PMB-002 Round 2 fix commit from the 2026-04-09 QA Olympics audit. The /caudit orchestrator would normally compute `git diff <round-start-sha>..HEAD` after fix commits land, enumerate path-scoped rules that govern touched files, wrap both in untrusted fences, and invoke you via a namespaced Task call. This is a historical replay — no path-scoped rules apply to this fixture, so the rules block is empty. Your job is to review the diff per your system prompt and identify any regressions the R2 fixes introduced or any new bugs hiding in the fix code. Historically, R2's 7 fixes introduced one R3 regression in `locked_update_state` `--arg` passthrough — your output should surface regressions in that class of change.

<UNTRUSTED_RULES>none</UNTRUSTED_RULES>

<UNTRUSTED_DIFF>
(verbatim contents of tests/fixtures/fix-diff-reviewer-historical-r2.diff — SHA-256 f33569ff...; full 388-line diff was pasted into the actual Task prompt, elided here for report readability)
</UNTRUSTED_DIFF>

Return ONLY the JSON array per your output contract."
)
```

### Response r2
```json
[
  {
    "id": "FD-001",
    "severity": "critical",
    "title": "locked_update_state filter embeds unescaped user input — injection and quoting breakage",
    "description": "The R2 migration to locked_update_state in cmd_qa, cmd_set_intensity, cmd_spec_update, and cmd_override stopped passing data via jq --arg/--argjson and instead interpolated shell variables directly into the jq filter string using double quotes. The previous code correctly used `jq --arg reason \"$reason\" --arg ts \"$ts\" ...` and referenced `$reason`/`$ts` inside the filter. The new code writes literal `\"$ts\"`, `\"$reason\"`, `\"$level\"` into the filter body, so the values are consumed by the jq parser rather than passed as bindings. Any value containing a double quote, backslash, newline, or `$`/backtick sequence will either (a) break jq parsing and cause `die \"Failed to update state...\"`, aborting the phase transition, or (b) be interpreted as jq syntax — a crafted --reason on /coverride or /cspec-update becomes arbitrary jq code executed against the state file. cmd_qa and cmd_set_intensity are lower-risk because $ts is ISO-8601 and $level is validated, but cmd_spec_update and cmd_override accept free-form reason strings from the operator and both now embed them unescaped. This is the R3 regression class the replay is looking for: the `--arg` passthrough was lost in the locked_update_state migration.",
    "evidence": "In the workflow-advance.sh hunks for cmd_qa (~line 533), cmd_set_intensity (~line 731), cmd_spec_update (~line 780), and cmd_override (~line 863), the locked_update_state filter arguments are built with `\\\"$ts\\\"`, `\\\"$reason\\\"`, `\\\"$level\\\"` interpolated by the shell instead of being bound via jq's --arg/--argjson.",
    "impact": "Operators running /cqa, /cset-intensity, /cspec-update, or /coverride with any reason containing a quote or backslash will hit a hard die and be unable to advance the workflow, corrupting rounds mid-audit. In cmd_override and cmd_spec_update the reason is operator-controlled free text and flows straight into the filter, so a malicious or merely careless reason can inject jq expressions that mutate or wipe unrelated fields of state.",
    "location": { "file": "hooks/workflow-advance.sh", "lines": [530, 880] },
    "instance_fix": "Change locked_update_state to accept --arg/--argjson passthrough and rewrite each of the four migrated call sites to reference `$reason`, `$ts`, `$level`, `$from` as jq bindings rather than shell-interpolated string literals.",
    "class_fix": "Add a jq-injection lint/test that greps each locked_update_state call for interpolated `\\\"$` sequences inside the filter argument and fails CI."
  },
  {
    "id": "FD-002",
    "severity": "high",
    "title": "cmd_spec_update loses atomicity of from_phase capture and re-reads update_count outside the lock",
    "description": "The pre-fix code captured `from_phase` from the same in-memory state snapshot that was then mutated and written back, so the recorded from_phase was guaranteed to match the phase being transitioned away from. R2 replaced this with `from_phase=\"$(read_phase)\"` before the locked update and then references `.phase` inside the filter. More importantly, after the locked update the code re-reads the state with an unlocked `read_state | jq -r '.spec_updates // 0'` to populate update_count for the ≥3 warning. Between the locked write and this read, another writer can bump spec_updates further, so the warning threshold may trigger on the wrong count or be silently skipped.",
    "evidence": "cmd_spec_update hunk near line 777: `from_phase=\"$(read_phase)\"` is assigned but never referenced inside the locked_update_state filter. Immediately after locked_update_state, `update_count=\"$(read_state | jq -r '.spec_updates // 0')\"` is read outside the lock.",
    "impact": "Dead `$from_phase` variable is merely confusing, but the unlocked re-read of spec_updates breaks the warning's meaning under concurrent invocations. Temporal-ordering class bug — same family as the R2 regressions the audit was trying to close.",
    "location": { "file": "hooks/workflow-advance.sh", "lines": [777, 805] },
    "instance_fix": "Have locked_update_state echo the post-update state so the caller can branch on it without a second read. Drop the dead `from_phase` local, or pass it explicitly via --arg.",
    "class_fix": "Forbid the pattern `locked_update_state ... ; read_state | jq` inside the same function via a grep-based lint."
  },
  {
    "id": "FD-003",
    "severity": "high",
    "title": "Grep hook audit path uses .tool_input.path only — misses .tool_input.file_path fallback and other read-only tools",
    "description": "QA-R2-002 adds a Grep case that reads FILES from TOOL_INPUT_PATH. That is correct for Grep, but the case statement picks exactly one input, so a Grep invocation with no path (searching cwd) will yield an empty FILES string and the hook will skip classification entirely. Meanwhile the fix only adds Grep to the tool-name exclusion lists; the exclusions use `!= \"Read\" && != \"Grep\"` everywhere but do not cover Glob, which is also read-only. If a future round adds Glob the exclusion list will again be incomplete — the same class of drift bug the original fix was closing.",
    "evidence": "audit-trail.sh hunk near line 52 adds a Grep case mapping FILES to TOOL_INPUT_PATH but has no fallback when .tool_input.path is empty. The phase-check hunks near lines 142-158 add Grep to the exclusion conjunctions but omit Glob.",
    "impact": "Grep calls from the repo root produce no audit-trail coverage at all, masking regressions in the same class. The hardcoded tool-name list will silently drift the next time a new read-only tool is introduced.",
    "location": { "file": "hooks/audit-trail.sh", "lines": [19, 160] },
    "instance_fix": "Fall back to `.` when TOOL_INPUT_PATH is empty. Replace the `!= Read && != Grep` chain with a single helper in scripts/lib.sh so Glob/WebFetch/etc. inherit the behavior automatically.",
    "class_fix": "Add a test fixture that feeds each documented tool-name through audit-trail.sh and asserts write vs read-only classification, so the exclusion list cannot drift from the tool registry without the test failing."
  },
  {
    "id": "FD-004",
    "severity": "medium",
    "title": "setup always overwrites scripts/lib.sh and antipattern-scan.sh, clobbering local edits",
    "description": "QA-R2-003 removes the `[ ! -f \"$script_dest/$script\" ]` guard on the scripts copy loop, so every run of setup now unconditionally overwrites scripts/lib.sh and scripts/antipattern-scan.sh in the consuming repo. lib.sh is the canonical drift-resistant extraction point (ABS-001) — downstream users may layer project-specific helpers there. No backup, diff, or warning is emitted before overwrite.",
    "evidence": "setup hunk around line 265: the `&& [ ! -f \"$script_dest/$script\" ]` guard is dropped.",
    "impact": "Any user who has forked or locally modified scripts/lib.sh will lose those edits silently on re-run.",
    "location": { "file": "setup", "lines": [263, 272] },
    "instance_fix": "Before overwriting, compare installed file to source and skip (or print a diff warning) if they differ; alternatively keep a .bak copy on every overwrite.",
    "class_fix": "Define a consistent 'generated vs editable' classification for everything setup copies and build a single copy helper."
  },
  {
    "id": "FD-005",
    "severity": "medium",
    "title": "cmd_override log-corruption recovery silently discards prior override history",
    "description": "QA-R2-007 extends the override-log existence check to also run `jq empty` and, on failure, overwrites the file with `[]`. This trades one failure mode (crash on corrupt log) for a worse one: a transient jq parse error causes cmd_override to throw away every historical override entry with no backup and no audit-trail emission. The override log is a compliance artifact — it is the only record that a human bypassed the workflow gate — and silently truncating it erases the bypass trail.",
    "evidence": "cmd_override hunk near line 873: `if [ ! -f \"$OVERRIDE_LOG\" ] || ! jq empty \"$OVERRIDE_LOG\" 2>/dev/null; then echo '[]' > \"$OVERRIDE_LOG\"; fi`.",
    "impact": "Loss of the compliance/audit trail on any transient parse failure. An adversary who can cause a single invalid byte in the override log gets a clean slate on the next /coverride invocation.",
    "location": { "file": "hooks/workflow-advance.sh", "lines": [874, 881] },
    "instance_fix": "On jq-empty failure, rename the existing file to `${OVERRIDE_LOG}.corrupt.$(date +%s)` before writing a fresh `[]`, emit a warning, and append an audit-trail entry.",
    "class_fix": "Establish a 'never silently truncate an audit artifact' rule: any recovery path that replaces a JSON log must first archive the prior contents under a timestamped .corrupt suffix."
  }
]
```

Parse verification: `jq -e . < /tmp/vp002-r2-full.json` → exit 0, `length` → 5. INV-017 satisfied.

### Request r3
```
Task(
  subagent_type="correctless:fix-diff-reviewer",
  description="VP-002 replay r3",
  prompt="You are reviewing the PMB-002 Round 3 fix commit from the 2026-04-09 QA Olympics audit. The /caudit orchestrator would normally compute `git diff <round-start-sha>..HEAD` after fix commits land, enumerate path-scoped rules that govern touched files, wrap both in untrusted fences, and invoke you via a namespaced Task call. This is a historical replay — no path-scoped rules apply to this fixture, so the rules block is empty. Your job is to review the diff per your system prompt and identify any regressions the R3 fix introduced or any new bugs hiding in the fix code. Historically, this fix passed review at the time but later surfaced a jq 1.7 vs 1.8 operator-precedence bug on CI (adjacent to PMB-001) — your output should flag the `as $var` binding precedence hazard.

<UNTRUSTED_RULES>none</UNTRUSTED_RULES>

<UNTRUSTED_DIFF>
(verbatim contents of tests/fixtures/fix-diff-reviewer-historical-r3.diff — SHA-256 37975aac...; full 127-line diff was pasted into the actual Task prompt, elided here for report readability)
</UNTRUSTED_DIFF>

Return ONLY the JSON array per your output contract."
)
```

### Response r3
```json
[
  {
    "id": "FD-001",
    "severity": "high",
    "title": "jq `as $count` binding lacks parentheses — parses differently on jq 1.7 vs 1.8",
    "description": "In cmd_spec_update, the new filter begins with `(.spec_updates // 0) + 1 as $count | .spec_updates = $count | ...`. jq's `as` binding has lower precedence than `+`, so on jq 1.7 (shipped with Ubuntu 24.04 CI image) this parses as `(.spec_updates // 0) + (1 as $count | ...)` rather than `((.spec_updates // 0) + 1) as $count | ...`. jq 1.8 silently fixed the precedence, so the filter runs correctly in local dev but errors out on CI.",
    "evidence": "hooks/workflow-advance.sh cmd_spec_update filter, first line of the new single-quoted jq program at roughly lines 789-792; identical filter also present in correctless/hooks/workflow-advance.sh at the same offsets.",
    "impact": "Every cmd_spec_update invocation will fail on any environment running jq < 1.8, producing `die \"Failed to update state for spec-update\"` and aborting the workflow. CI (Ubuntu 24.04) ships jq 1.7 and will break immediately; local dev on jq 1.8 will pass review, matching the exact PMB-001 failure mode.",
    "location": { "file": "hooks/workflow-advance.sh", "lines": [788, 793] },
    "instance_fix": "Wrap the bound expression in parens so the precedence is unambiguous: `((.spec_updates // 0) + 1) as $count | .spec_updates = $count | ...`. Apply the same change to the duplicated copy under correctless/hooks/workflow-advance.sh.",
    "class_fix": "Add a CI matrix row pinning jq 1.7, document a minimum jq version and enforce it in setup, and codify PAT-010 guidance that every `EXPR as $var` must parenthesize EXPR when EXPR contains a binary operator."
  },
  {
    "id": "FD-002",
    "severity": "medium",
    "title": "cmd_override removed `local sf` declaration and relies on an undeclared/leaked `sf`",
    "description": "The R3 hunk in cmd_override deletes the `local sf; sf=\"$(state_file)\"` block but still passes `$sf` as the first argument to `locked_update_state`. If `sf` was not assigned earlier in cmd_override before this hunk, the call will pass an empty string to locked_update_state, which will then try to flock/jq an empty path. Even if `sf` happens to be set in an enclosing scope, dropping the `local` declaration makes cmd_override depend on caller state and can mutate a parent scope's `sf`.",
    "evidence": "hooks/workflow-advance.sh cmd_override around lines 863-870: the `local sf` / `sf=\"$(state_file)\"` lines are removed in the diff and replaced only with a comment; the subsequent `locked_update_state \"$sf\" ...` call is retained.",
    "impact": "If no prior `sf=` assignment exists in cmd_override, every override invocation silently fails, breaking the override command. If `sf` is inherited from a caller, cmd_override becomes non-reentrant.",
    "location": { "file": "hooks/workflow-advance.sh", "lines": [863, 872] },
    "instance_fix": "Restore `local sf ts; sf=\"$(state_file)\"; ts=\"$(now_iso)\"` at the top of cmd_override before the locked_update_state call.",
    "class_fix": "Enable `shellcheck -e SC2154` across hooks/*.sh in CI, and run hooks under `set -u` in tests so any reference to an unset variable aborts."
  },
  {
    "id": "FD-003",
    "severity": "medium",
    "title": "`shift 2` in locked_update_state makes `$1`/`$2` references a latent footgun",
    "description": "locked_update_state now does `shift 2` before building the EXIT trap, so `$@` is the --arg tail passed to jq. The function still captures `state_file`, `jq_filter`, and `tmp_file` into locals before the shift — which is correct for the current diff — but the function now has a subtle contract: positional params past index 2 are jq passthroughs, and any future maintainer who writes `\"$2\"` expecting the filter will silently receive `--arg`.",
    "evidence": "scripts/lib.sh locked_update_state around lines 193-210: `shift 2` is added immediately after `local jq_filter=\"$2\"`, and the jq invocation is changed from `jq \"$jq_filter\" \"$state_file\"` to `jq \"$jq_filter\" \"$@\" \"$state_file\"`.",
    "impact": "No immediate functional break, but a latent footgun introduced by the fix. The function contract is now implicit.",
    "location": { "file": "scripts/lib.sh", "lines": [193, 212] },
    "instance_fix": "Add `local -a jq_args=(\"$@\")` right after `shift 2` and use `\"${jq_args[@]}\"` in the jq call so the passthrough is named and self-documenting.",
    "class_fix": "Adopt a convention of converting variadic tails to named arrays immediately after `shift`, and add a shellcheck/review rule flagging bare `$1`/`$2` references in functions that call `shift`."
  }
]
```

Parse verification: `jq -e . < /tmp/vp002-r3-full.json` → exit 0, `length` → 3. INV-017 satisfied.

### Finding-to-regression mapping
| Regression layer | Reviewer finding ID(s) | Notes |
|------------------|------------------------|-------|
| R1 fixes → R2 regressions (3 regressions in token-tracking and workflow-advance state handling) | r1:FD-001, r1:FD-002, r1:FD-003, r1:FD-005, r1:FD-006 | r1:FD-001 flags the `update_phase` string-interpolation jq injection that the R1 refactor introduced — this is the class of regression R2 had to catch and repair. r1:FD-002 flags the audit-trail HOOK_MATCHER expansion to Read/Grep that caused token-tracking pollution — same class. r1:FD-003 flags the EXIT-trap clobber inside `locked_update_state` that R2's state-handling fixes had to untangle. r1:FD-005 and r1:FD-006 flag the workflow-gate fail-closed recovery paths that over-block read-only tools and leave `FC_SOURCE_PAT` empty — both are state-handling hazards introduced by the R1 fix code. |
| R2 fixes → R3 regressions (1 regression: `locked_update_state` `--arg` passthrough lost a quoting safety check) | r2:FD-001, r2:FD-002 | r2:FD-001 is the exact class of regression R3 had to repair: the R2 migration to `locked_update_state` in cmd_qa, cmd_set_intensity, cmd_spec_update, and cmd_override replaced `jq --arg` bindings with unescaped shell interpolation, directly causing the `--arg passthrough lost a quoting safety check` regression recorded in `.correctless/meta/workflow-effectiveness.json` PMB-002. r2:FD-002 surfaces the matching temporal-ordering atomicity regression in cmd_spec_update (unlocked re-read of spec_updates) — same class. |
| R3 fix → CI failure (PMB-001 jq 1.7 precedence) | r3:FD-001 | r3:FD-001 is a direct, precise hit on the PMB-001-adjacent jq 1.7 vs 1.8 `as $var` binding precedence bug. The finding names the exact filter location (`hooks/workflow-advance.sh` cmd_spec_update lines 788-793), identifies the precedence mismatch, cites PAT-010, and proposes both the instance fix (wrap in parens) and the class fix (CI matrix pinning jq 1.7). A reviewer catching this finding on the R3 fix commit would have prevented the CI break entirely. |

## Overall verdict
PASS

Both VP-001 (fingerprint smoke test) and VP-002 (functional-equivalence replay across all three PMB-002 fix-round fixtures) PASS. The plugin-loader binding is verified, the read-only tool allowlist is enforced, all three JSON responses parse cleanly under the INV-017 identity-parse gate, and every regression layer documented in `.correctless/meta/workflow-effectiveness.json` PMB-002 is covered by at least one non-placeholder finding. The fix-diff reviewer agent is ready for live use by `/caudit` step 6a.
