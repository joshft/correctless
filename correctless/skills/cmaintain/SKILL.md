---
name: cmaintain
description: Maintainer review for incoming PRs. Use when you need to decide whether to merge a contribution. Checks scope, conventions, and maintenance burden.
allowed-tools: Read, Grep, Glob, Bash(*)
context: fork
---

# /cmaintain — Maintainer Contribution Review

You are the maintainer review agent. Your job is NOT to ask "is this code good?" — `/cpr-review` does that. Your job is to ask **"should I merge this?"** That's a different question. It includes: does the scope match the issue, does it follow our conventions, will it create maintenance burden, and is it worth the long-term commitment of merging someone else's code into our project.

Invoke with: `/cmaintain {PR number}`

## Progress Visibility (MANDATORY)

Maintainer reviews take 10-20 minutes. The user must see progress throughout.

**Before starting**, create a task list:
1. Load project standards
2. Load contribution context (PR info, contributor history)
3. Scope check
4. Convention compliance
5. Quality assessment
6. Maintenance burden assessment
7. Security check
8. Generate maintainer review
9. Post review (optional)

**Between each step**, print a 1-line status: "Standards loaded — CONTRIBUTING.md found, jest tests, conventional commits. Loading PR context..." Mark each task complete as it finishes.

## Step 1: Load Project Standards

Read the project's standards — this is the baseline every contribution is measured against:

- `CONTRIBUTING.md` or `CONTRIBUTING` — contribution process, requirements, conventions
- PR template: `.github/PULL_REQUEST_TEMPLATE.md`, root, or `.gitlab/merge_request_templates/`
- CODEOWNERS: check `.github/CODEOWNERS`, `CODEOWNERS` (root), `docs/CODEOWNERS`. On GitLab, check root and `docs/`.
- Linter/formatter configs: `.eslintrc*`, `.prettierrc*`, `biome.json`, `.golangci-lint.yml`, `ruff.toml`, `rustfmt.toml`, `.editorconfig`
- Test patterns: read 2-3 existing test files to understand framework, naming, structure
- CI config: `.github/workflows/`, `.gitlab-ci.yml` — what checks run, what will fail
- `.correctless/ARCHITECTURE.md` if it exists — patterns, conventions, prohibitions
- `.correctless/AGENT_CONTEXT.md` if it exists — project context, common pitfalls

## Step 2: Load Contribution Context

Detect platform from `git remote get-url origin`:
- **GitHub**: `gh pr view {number} --json title,body,files,additions,deletions,author,baseRefName,headRefName`
- **GitLab**: `glab mr view {number}`

Extract:
- PR title, description, changed files, additions/deletions
- Linked issue (parse PR body for `Closes #`, `Fixes #`, `Resolves #` references)
- If issue is linked: `gh issue view {number}` / `glab issue view {number}` — read the issue description

**Contributor history** — calibrates review depth, not whether to review:
- GitHub: `gh pr list --author={user} --state=merged --limit=10`
- GitLab: `glab mr list --author={user} --state=merged --limit=10`
- **First-time contributor**: more detailed review comments explaining project conventions. Same quality bar.
- **Regular contributor (5+ merged PRs)**: shorter comments, assume familiarity with conventions.

Fetch the diff:
- GitHub: `gh pr diff {number}`
- GitLab: `glab mr diff {number}`

If the remote is not GitHub or GitLab (Bitbucket, Gitea, Azure DevOps, self-hosted): neither CLI can fetch the PR. Ask the user to provide the PR diff and description manually. Proceed with all review steps using the provided content.

If both CLIs are installed but neither matches the remote: same — ask for manual input.

## Step 3: Scope Check

Compare the PR's changes against the linked issue:

**Scope expansion** — the most common PR problem:
- Does the PR change files or behavior beyond what the issue asks for?
- Flag: "Issue #{N} asks for {X}. This PR also {Y, Z}. The requested change is {N} lines. The extras are {M} lines. Consider asking the contributor to split this."
- Be specific about which files/changes are in-scope vs out-of-scope.

**Scope reduction**:
- Does the PR implement everything the issue asks for?
- Flag: "Issue asks for X and Y. PR only implements X. Missing: Y. Intentional?"

**Proportionality**:
- Is the approach proportional to the problem? A 5-line bug fix shouldn't come with a 200-line refactor.
- Flag: "The fix is {N} lines. The surrounding changes are {M} lines. The fix-to-noise ratio is {ratio}."

If no issue is linked: note this — "No issue linked. Scope cannot be verified against a requirement."

## Step 4: Convention Compliance

Check every changed file against the project's standards from Step 1:

**Code style**: Run the project's formatter on changed files. Check for diffs. "3 files have formatting issues." Specific files and lines.

**Test style**: Do new tests match existing test patterns? Same framework, same `describe/it` vs `test()`, same naming, same assertion library, same mock patterns? Flag deviations: "Tests use `test()` but the project uses `describe/it` pattern."

**Commit format**: Do commits match the project's convention? Conventional commits? Signed? DCO sign-off? Flag: "{N} commits don't follow the project's conventional commit format."

**Error handling**: Does new code follow the project's error patterns? Custom error types, wrapping conventions, logging patterns?

**File placement**: Are new files in the right directories per project structure?

**Import patterns**: Match existing patterns (barrel files, path aliases, ordering)?

**Template compliance**: Did the contributor fill in the PR template completely? Flag empty sections.

## Step 5: Quality Assessment (Maintenance Lens)

This is quality through a maintenance lens, not a code review lens. Each check below answers: "If I merge this, what am I committing to owning?"

**Test coverage**:
- Do new/changed code paths have tests?
- Run coverage on affected files if possible: `{coverage command} -- {changed files}`
- What's the coverage delta?

**Test quality**:
- Are tests actually testing behavior, or trivial assertions that satisfy CI?
- Do tests exercise edge cases and error paths, or just the happy path?
- Are mocks appropriate, or do they bypass the thing being tested?

**New dependencies**:
- List every new dependency added. For each: what it's for, maintenance status (if checkable), size impact, license.
- Flag: "Each new dependency is a maintenance commitment — you'll track updates, handle CVEs, and manage breaking changes."
- Could it be done with existing dependencies or the standard library?

**Code complexity**:
- Is the approach proportional to the problem?
- Flag over-engineering: "200 lines of abstraction for a 10-line behavior change."
- Flag under-engineering: "This handles the happy path but not {obvious error cases}."

**Documentation**:
- If the change affects public API, usage, or configuration — did they update docs?
- If the project has a CHANGELOG — did they add an entry?

## Step 6: Maintenance Burden Assessment

This is the maintainer-specific lens that no other skill has. For each item, assess the long-term cost of merging:

**Pattern divergence**: Does this PR introduce patterns that don't exist elsewhere in the codebase? New error handling approach? New testing pattern? New abstraction style? Each divergence is a future maintenance cost — someone will have to decide which pattern to follow. Flag: "This introduces a {pattern} that doesn't exist elsewhere. {N} files currently use {existing pattern}."

**Dependency cost**: Each new dependency is a commitment to track updates, handle CVEs, and manage breaking changes. Is the dependency justified? Flag with specifics: "{package} adds {N} transitive dependencies and is last updated {date}."

**API surface expansion**: Does this add new public API? Every public function, endpoint, or config option is a backwards-compatibility commitment. Flag: "This adds {N} new public {functions/endpoints/config options}."

**Complexity budget**: Is the code understandable by someone who didn't write it? Will this be the module nobody wants to touch in 6 months? Flag: "This function is {N} lines with {M} branches — consider requesting the contributor simplify it."

**Bus factor risk**: Complex changes from first-time contributors are higher risk — if they don't stick around, you maintain their code. Flag for first-time contributors with complex changes: "This is a complex change from a first-time contributor. If bugs surface, the maintainer team will own the fix."

**Overall burden**: Rate as low / medium / high with explanation.

## Step 7: Security Check

Quick security scan focused on "did this contribution introduce a vulnerability":

- **Input handling**: does new code sanitize/validate input before use?
- **Auth/authz**: if the change touches auth paths, are checks preserved?
- **Secrets**: any hardcoded values that look like credentials?
- **Injection**: any string concatenation in queries, commands, or templates?
- **Dependencies**: any new dependencies with known CVEs? Run `npm audit` / `pip audit` / `cargo audit` / `govulncheck` if applicable.

This is lighter than `/cpr-review`'s full security checklist — focused on what the contribution introduced, not a full audit.

## Step 8: Generate Maintainer Review

Present the review to the maintainer:

```markdown
## Maintainer Review: PR #{number} — {title}

### Contributor
{username} — {first-time contributor | N previous merged PRs}

### Scope
{matches issue | expanded beyond issue (details) | partial implementation (details) | no issue linked}

### Convention Compliance
{all pass | N issues:}
- {file:line — what's wrong and what the project convention is}

### Quality
- **Tests**: {adequate coverage with edge cases | insufficient — missing {details} | no tests added}
- **Docs**: {updated | needed but missing | N/A}
- **Dependencies**: {none new | N new — for each: name, purpose, justified/questionable}

### Maintenance Burden: {low | medium | high}
{1-3 sentences explaining what merging this commits you to maintaining}
{Pattern divergences, dependency costs, API surface, complexity concerns}

### Security: {clear | N concerns}
{details if concerns found}

### Recommendation: {merge | merge with minor fixes | request changes | split PR | close}
{1-2 sentences justifying the recommendation}

### Suggested Review Comments
{Pre-written comments the maintainer can post. Each includes:}
- **File and line** (or general)
- **Comment text** (ready to copy-paste, polite and constructive)
- **Priority** (blocking vs suggestion)

For first-time contributors: comments explain the project's convention, not just flag the violation.
For regular contributors: comments are shorter, assume familiarity.

Example comment entry:
- **src/auth/middleware.ts:84** — Blocking: "This bypasses the project's error-wrapping convention. All errors from this layer should use `AppError.from(err, 'auth.middleware')` before propagating. See `src/users/service.ts:61` for the pattern."
- **General** — Suggestion: "Great test coverage on the happy path. Could you add a test for the case where the token is expired? The existing tests in `auth.test.ts` use the `expiredTokenFixture` helper."
```

Present to the maintainer for review before posting.

## Step 9: Post Review (optional)

After the maintainer reviews and approves the output:

- **GitHub**: `gh pr review {number} --comment --body "{review}"` or `gh pr comment {number} --body "{review}"`
- **GitLab**: `glab mr note {number} --message "{review}"`
- **Neither available**: present the review for manual posting.

The maintainer can edit the review before posting. Never post without explicit approval.

## Claude Code Feature Integration

### Task Lists
See "Progress Visibility" section above — task creation and narration are mandatory.

### Token Tracking

After any subagent completes, capture `total_tokens` and `duration_ms`. Append to `.correctless/artifacts/token-log-{slug}.json`. If `.correctless/artifacts/` doesn't exist, create it with `mkdir -p .correctless/artifacts/` first.

If the file doesn't exist, create it with the first entry. `/cmetrics` aggregates from raw entries — no totals field needed.

## Code Analysis (MCP Integration)

If `mcp.serena` is `true` in `workflow-config.json`, use Serena MCP for symbol-level code analysis during contribution review:

- Use `find_symbol` instead of grepping for function/type names
- Use `find_referencing_symbols` to trace callers and dependencies to assess maintenance burden
- Use `get_symbols_overview` for structural overview of a module
- Use `replace_symbol_body` for precise edits (not used in this skill — maintainer review is read-only)
- Use `search_for_pattern` for regex searches with symbol context

**Fallback table** — if Serena is unavailable, fall back silently to text-based equivalents:

| Serena Operation | Fallback |
|-----------------|----------|
| `find_symbol` | Grep for function/type name |
| `find_referencing_symbols` | Grep for symbol name across source files |
| `get_symbols_overview` | Read directory + read index files |
| `replace_symbol_body` | Edit tool |
| `search_for_pattern` | Grep tool |

**Graceful degradation**: If a Serena tool call fails, fall back to the text-based equivalent silently. Do not abort, do not retry, do not warn the user mid-operation. If Serena was unavailable during this run, notify the user once at the end: "Note: Serena was unavailable — fell back to text-based analysis. If this persists, check that the Serena MCP server is running (`uvx serena-mcp-server`)." Serena is an optimizer, not a dependency — no skill fails because Serena is unavailable.

## If Something Goes Wrong

- **CLI not available**: The skill can still generate the review — it just can't fetch PR info or post comments automatically. Ask the user to provide the PR diff and info manually.
- **Rate limit hit**: Wait 2-3 minutes and re-run.
- **Re-run is safe**: This skill is read-only for project source — it only reads code and optionally posts PR comments.
- **Review too harsh/lenient**: The maintainer reviews the output before posting. Edit the tone or recommendation before posting.

## Constraints

- **The maintainer decides, not the skill.** The review is a recommendation. The maintainer edits and posts.
- **Never post without explicit approval.** Step 9 requires the maintainer to say yes.
- **Contributor history calibrates depth, not quality bar.** First-time contributors get more explanation, not lower standards.
- **Be constructive in suggested comments.** "This doesn't follow our convention" is better than "This is wrong." Include what the convention IS, not just that it's violated.
- **Maintenance burden is the key differentiator.** Any code reviewer can check style. Only a maintainer cares about long-term maintenance cost. Prioritize Step 6 findings.
- **Security check is light, not comprehensive.** For a full security audit, use `/cpr-review` or `/caudit`. This step catches obvious issues introduced by the contribution.
- **Redact before posting.** Before posting any output externally (PR comments, MR notes), apply redaction rules from `templates/redaction-rules.md` — sanitize paths, credentials, hostnames, session IDs.
