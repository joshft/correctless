# Spec: AI Antipattern Scan

## Metadata
- **Task**: antipattern scan
- **Intensity**: high
- **Intensity reason**: project floor (workflow.intensity=high)
- **Override**: none

## What

A deterministic scan script that detects common AI-generated code antipatterns (empty catch blocks, placeholder values, debug logging, trivial assertions, etc.) before the QA agent runs. It scans files changed on the current branch, routes checks by file extension, and outputs findings in QA-format JSON. Runs at two phase transitions: before QA in `/ctdd` and during `/cverify`. The QA agent receives deterministic findings as context so it focuses on semantic issues instead of rediscovering mechanical problems. A separate prompt checklist (~20 semantic patterns) is added to the QA agent, `/creview`, and `/cverify` prompts.

## Rules

- **R-001** [integration]: The script `scripts/antipattern-scan.sh` must accept a base branch argument (default `main`), compute the list of changed files via `git diff --name-only {base}...HEAD`, and run language-appropriate checks on each file based on its extension. If the diff fails (detached HEAD, shallow clone, missing base branch), fall back to scanning all tracked files matching supported extensions, and emit a warning line to stderr. If currently on the default branch (main/master), exit early with `{"findings": []}` and a stderr note.

- **R-002** [unit]: File extension routing must map extensions to check sets: `.js`/`.ts`/`.tsx`/`.jsx`/`.mjs`/`.cjs`/`.mts`/`.cts` → JS/TS checks, `.py` → Python checks, `.go` → Go checks, `.rs` → Rust checks, `.sh` → Shell checks. Files with unrecognized extensions (including `.java`/`.kt`) are skipped silently. Extension matching is case-insensitive (`${ext,,}`).

- **R-003** [integration]: The script must output findings as JSON to stdout in the format: `{"findings": [{"id": "AP-001", "severity": "medium", "pattern": "empty-catch", "file": "src/main.ts", "line": 42, "description": "Empty catch block swallows errors", "category": "error-handling"}]}`. Empty findings produce `{"findings": []}`. All JSON must be constructed via `jq` — never string concatenation. Description fields are hardcoded per pattern ID, never derived from file content. File paths and line numbers are the only values sourced from grep output. This prevents JSON injection via adversarial file content (see TB-002).

- **R-004** [unit]: JS/TS checks must detect at minimum: (a) empty catch blocks `catch {` or `catch(e) {` with no statements, (b) `console.log`/`console.debug` in non-test files, (c) `as any` or `: any` more than 3 times per file, (d) `expect(true)` / `expect(1).toBe(1)` trivial assertions in test files, (e) placeholder strings matching `your-api-key|changeme|REPLACE_ME|yourdomain\.com|localhost:` in non-test non-comment lines.

- **R-005** [unit]: Python checks must detect at minimum: (a) bare `except:` or `except Exception: pass`, (b) `print()` calls in non-test files, (c) `# TODO`/`# FIXME`/`# HACK` comments, (d) placeholder strings (same patterns as R-004e).

- **R-006** [unit]: Go checks must detect at minimum: (a) `if err != nil { }` empty error handling, (b) `fmt.Println`/`fmt.Printf` in non-test files, (c) `// TODO`/`// FIXME`/`// HACK` comments, (d) placeholder strings.

- **R-007** [unit]: Shell checks must detect at minimum: (a) `|| true` or `|| :` after commands NOT in this allowlist: `cd`, `command -v`, `which`, `pushd`, `popd`, and pipeline tails ending in `| wc`, `| grep -c`, `| grep -q` — all other `|| true` patterns are flagged, (b) `echo` statements in non-test files that do NOT match any of these exempt patterns: `echo ">>> ..."` (step prefix), `echo "=== ..."` (section header), `echo "  PASS:"`/`echo "  FAIL:"` (test output), `echo ""` (blank line), or `echo` inside functions named `info`/`warn`/`error`/`debug`/`usage`/`die` — all other `echo` calls flagged at severity LOW, (c) `# TODO`/`# FIXME`/`# HACK` comments, (d) placeholder strings.

- **R-008** [unit]: Rust checks must detect at minimum: (a) `unwrap()` calls in non-test files (more than 3 per file), (b) `println!`/`dbg!` in non-test files, (c) `todo!()` macro, (d) placeholder strings.

- **R-009** [integration]: The script must exit 0 and produce valid JSON under all conditions, including: (1) no changed files, (2) binary files in the change set, (3) files deleted between `git diff` and scan, (4) empty files, (5) broken symlinks, (6) file paths containing spaces or special characters. If any individual file scan errors, the script must skip that file, log it to the `"errors"` array, and continue: `{"findings": [...], "errors": ["Failed to scan foo.ts: binary file"]}`. This distinguishes "zero findings" from "scanner crashed." The consuming skill (`/ctdd`, `/cverify`) must validate that stdout is non-empty valid JSON before treating it as findings — empty or invalid output means the scanner itself failed and must be reported as an error, not "zero findings."

- **R-010** [integration]: When invoked from `/ctdd` before QA, the script's JSON output must be written to `.correctless/artifacts/antipattern-findings-{slug}.json` (where `{slug}` is the branch name with non-alphanumeric characters replaced by `-`) and the finding count must be announced to the QA agent prompt: "Deterministic scan found {N} antipatterns. These are already identified — focus on semantic issues." Maximum 20 findings per file; additional findings for that file are summarized as "+{N} more in {file}". Files under `vendor/`, `node_modules/`, `generated/`, `dist/`, or paths matching `antipattern_scan.exclude_paths` from workflow-config.json are excluded from scanning.

- **R-011** [integration]: When invoked from `/cverify`, findings must appear in the verification report under a "## Antipattern Scan" section with a table of findings.

- **R-012** [unit]: Test files are identified by the project's `patterns.test_file` from `workflow-config.json` if available, falling back to language-specific conventions: `*.test.*`, `*.spec.*`, `test_*.py`, `*_test.go`, `*_test.rs`, `__tests__/*`, `tests/*`. Fallback patterns match against the basename (not the full path) for suffix patterns, and against the relative path for directory patterns. Checks that only apply to non-test files (debug logging, print statements) must skip test files. Checks that only apply to test files (trivial assertions) must skip non-test files.

- **R-013** [unit]: Each check must report the file path, line number, pattern ID, severity (low/medium/high), a one-line description, and a category. Complete severity mapping:
  - **high**: empty catch/except/error blocks (R-004a, R-005a, R-006a, R-007a), placeholder strings (R-004e, R-005d, R-006d, R-007d, R-008d)
  - **medium**: debug logging (R-004b, R-005b, R-006b, R-008b), excessive `any` (R-004c), excessive `unwrap()` (R-008a)
  - **low**: debug echo (R-007b), TODO/FIXME/HACK comments (R-005c, R-006c, R-007c, R-008c), trivial assertions (R-004d), `todo!()` macro (R-008c)

- **R-014** [integration]: A semantic checklist of AI antipatterns (patterns not detectable by grep) must be defined in a single canonical file at `.correctless/checklists/ai-antipatterns.md`. The `/ctdd` QA agent prompt, the `/creview` agent prompt, and the `/cverify` smell check section must reference this file by path. The checklist covers at minimum: disconnected middleware, scope creep, over-abstraction, mock-testing-the-mock, happy-path-only testing, silently removed safety guards. Skills reference the canonical file — they do not duplicate the checklist content.

- **R-015** [unit]: All grep invocations must use POSIX-compatible flags only (`-E`, `-c`, `-q`, `-o`, `-A`, `-B`, `-I`, `-n`). Multi-line patterns (e.g., empty catch blocks spanning lines) use `grep -A1` with post-processing. `-P` (PCRE) and `-z` (NUL delimiter) are prohibited. Bash built-in pattern matching (`[[ =~ ]]`, `case`) may be used as alternatives.

- **R-016** [integration]: The script lives at `scripts/antipattern-scan.sh`, NOT in `hooks/`. It is a phase-transition script (invoked by skills via `Bash()`), not a Claude Code hook (no stdin JSON, no exit 0/2 protocol, not triggered by the hook runner). It follows the conventions for phase-transition scripts (see PAT-003 in ARCHITECTURE.md after this feature lands), not PAT-001 hook conventions. The `sync.sh` deployment pipeline must include the `scripts/` directory.

- **R-017** [integration]: The scanner's JSON output constitutes a trust boundary (TB-002): untrusted file content → structured JSON → LLM agent context. Mitigations: hardcoded descriptions per pattern ID (R-003), only file paths and line numbers sourced from grep, no file content interpolated into JSON structure. The QA agent prompt must note findings are heuristic, not authoritative.

- **R-018** [unit]: Placeholder credential detection (`your-api-key|changeme|REPLACE_ME|yourdomain\.com|localhost:`) must run on ALL text files regardless of extension — not just files routed to a language check set. This catches placeholder values in `.yml`, `.yaml`, `.json`, `.toml`, `.env`, `.cfg`, `.ini`, `.xml`, and other config files where hardcoded credentials are most commonly left behind. Binary files (detected via `grep -I`) are skipped.

- **R-019** [unit]: The `branch_slug()` function must be extracted into a shared helper file (`scripts/lib.sh` or similar) sourced by both `hooks/workflow-advance.sh` and `scripts/antipattern-scan.sh`. The slug computation (`${branch//[^a-zA-Z0-9]/-}`) must have a single definition to prevent drift between artifact filenames. Other shared utilities (if any) should be co-located in the same helper.

## Won't Do

- **AST-based detection** — grep/regex only for v1. AST (ast-grep/tree-sitter) is a v2 enhancement.
- **Blocking workflow transitions** — the scan is informational. It feeds context to QA, never blocks.
- **Per-edit hook** — runs at phase transitions only, not PostToolUse.
- **Hallucinated package detection** — requires a package allowlist (~5k entries). Defer to v2 or adopt vibecop.
- **Auto-fixing** — the scan reports, the QA agent or human fixes.
- **Language detection from config** — file extension routing only, no `project.language` dependency.

## Risks

- **False positives on debug logging in scripts with intentional echo output** — the shell check for `echo` debug statements will have false positives in scripts that use echo for user output. Mitigated by the explicit exemption list in R-007(b): step prefixes, section headers, test output, blank lines, and echo inside named utility functions. Remaining false positives flagged at LOW severity — informational, not blocking.
- **Grep limitations on multi-line patterns** — empty catch blocks that span multiple lines (opening brace on one line, closing on next) may not be caught by single-line grep. Mitigated by using `grep -A1` with post-processing (R-015 prohibits `-P` and `-z` for portability). Accepted risk for v1 — some multi-line patterns will be missed.
- **JSON injection via adversarial file content** — if a scanned file contains strings that look like JSON structure, naive string concatenation could corrupt the output. Mitigated by R-003 (jq-only JSON construction, hardcoded descriptions, no file content interpolation) and R-017 (TB-002 trust boundary).

## Open Questions

None — scope is clear from brainstorm and research.
