---
name: cpr-review
description: Multi-lens PR review. Checks architecture compliance, security, test coverage, antipatterns, spec alignment, and (Full mode) concurrency, trust boundaries, dependency risk, cross-spec impact, drift, and performance.
allowed-tools: Read, Grep, Glob, Bash(gh*), Bash(glab*), Bash(git*), Bash(*test*), Bash(*lint*), Bash(*audit*), Bash(govulncheck*)
---

# /cpr-review — Multi-Lens PR Review

You are the PR review agent. You review incoming pull requests using multiple focused lenses — each check has a single concern and is more thorough in its domain than a human reviewer doing one pass trying to catch everything.

Invoke with: `/cpr-review {PR number or URL}`

## Progress Visibility (MANDATORY)

PR reviews take 5-15 minutes depending on PR size and mode. The user must see progress throughout.

**Before starting**, create a task list:
1. Fetch PR info and diff
2. Detect dependency bump (may switch to dep-specific lens)
3. Read project context
4. Architecture compliance check
5. Security checklist
6. Test coverage analysis
7. Antipattern check
8. Convention compliance
9. Spec alignment (if spec linked)
10. (Full mode) Concurrency analysis
11. (Full mode) Trust boundary analysis
12. (Full mode) Cross-spec impact
13. (Full mode) Drift detection
14. (Full mode) Performance implications
15. (Full mode) Dependency risk
16. Present findings

**Between each check**, print a 1-line status: "Architecture compliance complete — {N} findings. Running security checklist..." Mark each task complete as it finishes.

## Step 1: Fetch PR Info

Detect platform from git remote:
```bash
remote_url="$(git remote get-url origin 2>/dev/null)"
```
- Contains `github.com` or `github.` → use `gh`
- Contains `gitlab.com` or `gitlab.` → use `glab`

Fetch PR details:
- GitHub: `gh pr view {number} --json title,body,files,additions,deletions,baseRefName,headRefName`
- GitLab: `glab mr view {number}`

Fetch the diff:
- GitHub: `gh pr diff {number}`
- GitLab: `glab mr diff {number}`

If neither CLI is available: "Install `gh` (GitHub) or `glab` (GitLab) to use /cpr-review. Or provide the diff manually."

**Parse the PR body** for spec references: look for links to `docs/specs/*.md` or mentions of spec files.

### Detect Dependency Bump PRs

After fetching PR info, check if this is a dependency bump:
- PR author is `dependabot[bot]`, `renovate[bot]`, `renovate-bot`, or similar
- OR: the only changed files are dependency manifests (package.json, go.mod, Cargo.toml, requirements.txt, pyproject.toml, Gemfile, pnpm-lock.yaml, yarn.lock, go.sum, Cargo.lock)
- OR: PR title matches patterns like "Bump X from Y to Z", "Update X to Z", "chore(deps): ..."

**If dependency bump detected**, skip the standard code review (Steps 2-8) entirely and run the dependency-specific lens instead:

**Priority order** (most reliable signal first):

**1. Test verification (definitive):**
Run the project's test suite. If tests pass, the bump is likely safe. If tests fail, the failures point directly to affected usage patterns. Report: "Tests: {all pass / N failures}" with the specific failing test names and files.

**2. Usage pattern analysis (high signal):**
Grep the project for imports/usage of the bumped dependency. Check whether deprecated APIs are used. Flag affected files: "Found {N} files importing {package}. {M} use APIs deprecated in the new version: {list}."

**3. Changelog review (context):**
Extract the dependency name and version range from the diff. If GitHub-hosted: `gh api repos/{owner}/{repo}/releases` to fetch release notes. Otherwise search for CHANGELOG.md or release notes. Summarize breaking changes and notable fixes.

**4. CVE check (if security update):**
Read the PR body for CVE references. Assess severity and whether the project's usage is affected by the specific vulnerability.

**5. Breaking changes assessment:**
Compare old and new major/minor versions. Major version bump: "Major version bump — likely breaking changes. Review migration guide." Check changelog for "BREAKING" entries.

**6. Transitive impact:**
For package.json bumps, check if the lockfile changes affect other packages. For go.mod, check indirect dependency changes.

**Output for dep bumps** (replaces standard review format):

```markdown
## Dependency Review: {package} {old} → {new}

### Update Type: {security patch / minor update / major upgrade}

### Test Result
{all pass / N failures in {files}}

### Project Usage
{N files import this dependency}
{M use deprecated APIs: {list with file:line references}}

### CVE (if applicable)
{ID, severity, affected versions, whether project usage is affected}

### Breaking Changes
{from changelog, or "none found"}

### Recommendation
{merge / merge after fixing deprecated API usage / needs migration work / block — tests fail}
```

The recommendation should be primarily driven by test results, not changelog reading. If tests pass and no deprecated APIs are used, recommend merge. If tests fail, the failures ARE the review.

**This replaces the standard review flow for dep bumps** — don't run architecture compliance, security checklist, etc. Those are for code changes, not version bumps.

## Step 2: Read Project Context

Read these files to understand the project's standards:
1. `ARCHITECTURE.md` — design patterns, conventions, trust boundaries, prohibitions
2. `AGENT_CONTEXT.md` — project context, key components, common pitfalls
3. `.claude/antipatterns.md` — known bug classes
4. `.claude/workflow-config.json` — project settings, test patterns
5. If a spec is referenced: read the spec for rule alignment

## Step 3: Architecture Compliance

Check every changed file against ARCHITECTURE.md:

- **Pattern violations**: Do changes follow documented design patterns (PAT-xxx)? If a new database query bypasses the repository layer, flag it.
- **Convention violations**: Naming, file organization, import patterns — does the PR follow what's documented?
- **Prohibition violations**: Does the PR do anything listed in the Prohibitions section? (e.g., "Never import database packages from HTTP handlers")
- **New patterns**: Does the PR introduce a pattern not documented in ARCHITECTURE.md? If so, it's either a good addition that should be documented or drift that should be questioned.
- **Component boundaries**: Do changes respect the component boundaries in the Key Components table? Cross-boundary imports that aren't documented are a smell.

For each finding: cite the specific ARCHITECTURE.md entry (PAT-xxx, prohibition, convention) being violated.

## Step 4: Security Checklist

Run a security checklist against the PR diff, auto-fired based on what the PR touches. This covers the most common vulnerability classes — for the full comprehensive checklist, see `/creview`. Check the diff for:

**If PR touches auth/session code:**
- Password hashing (bcrypt cost ≥ 10, never MD5/SHA for passwords)
- Session management (secure, httpOnly, sameSite cookies)
- Token expiration and rotation
- Auth bypass paths (middleware ordering — the #1 Express.js auth bypass, missing checks on new endpoints)
- Fail-closed on auth failure (deny by default, not allow by default)
- Security logging for authentication events, failed logins, privilege changes

**If PR touches user input handling:**
- Input validation at API boundary (not just client-side)
- SQL injection (parameterized queries, no string concatenation)
- XSS (output encoding, sanitization)
- Path traversal in file operations
- SSRF in URL handling (block private IPs: 127.0.0.0/8, 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, `file://`, non-HTTP schemes)
- Mass assignment / over-posting
- Open redirect (user-controlled redirect URLs must be validated against allowlist)
- Unsafe deserialization (never deserialize untrusted input with pickle, eval, unserialize)

**If PR touches data storage:**
- Sensitive data encryption at rest
- PII handling and logging (no passwords/tokens in logs)
- Database RLS / tenant isolation (multi-tenant apps, fail-closed on tenant isolation failure)
- TOCTOU in authorization checks (check-then-act patterns where state can change between check and action)

**If PR touches APIs/endpoints:**
- CSRF protection on state-changing operations
- Rate limiting on auth endpoints
- Security headers (HSTS, X-Content-Type-Options, X-Frame-Options, Content-Security-Policy)
- CORS configuration (not wildcard `*` with credentials)
- Authorization checks (not just authentication)

**If PR touches third-party integrations:**
- API keys in env vars, not in source (check for hardcoded keys)
- Webhook signature validation (Stripe, GitHub, etc.)
- Distinction between publishable and secret keys

**If PR adds dependencies:**
- Check for known CVEs: `npm audit`, `pip audit`, `cargo audit`, `govulncheck`
- Flag new dependencies for manual review of maintenance status — the agent cannot access package registries directly

## Step 5: Test Coverage Analysis

Analyze the PR diff against test files:

- **New code without tests**: Identify functions, endpoints, or classes added in the PR that have no corresponding test.
- **Changed behavior without updated tests**: If a function's behavior changed, did the tests change too? Unchanged tests might pass by accident.
- **Mock gaps**: If tests exist, do they mock dependencies that should be tested via integration? A test that mocks the database doesn't prove the query works.
- **Missing edge cases**: Based on the code logic (conditionals, error paths, boundary values), are the obvious edge cases tested?
- **Test quality**: Are assertions meaningful? A test that calls a function and asserts `true` proves nothing.

**Report test coverage as**: "X/Y new functions have tests. Z edge cases identified but untested."

## Step 6: Antipattern Check

Read `.claude/antipatterns.md`. For each entry (AP-xxx):
- Does the PR introduce or repeat this known bug class?
- If yes, cite the specific antipattern and the code location.

This is the compounding value of Correctless — bugs caught once get added to the antipattern registry, and every future PR review checks against them.

## Step 7: Convention Compliance

Check the PR against documented conventions in ARCHITECTURE.md and CLAUDE.md:
- Naming conventions (files, functions, variables)
- Error handling patterns (consistent error shapes, proper propagation)
- Import ordering and module boundaries
- Logging conventions
- Comment and documentation standards

Only flag violations of **documented** conventions, not personal preferences.

## Step 8: Spec Alignment (if spec exists)

If the PR references a spec in `docs/specs/`:
- Read the spec rules
- For each rule: does the PR implementation satisfy it?
- For each rule: is there a test that would fail if the rule were violated?
- Flag uncovered rules and weak tests

If no spec is referenced, skip this step.

## Full Mode Additional Checks

Read `.claude/workflow-config.json`. If `workflow.intensity` is set (any value: `"low"`, `"standard"`, `"high"`, or `"critical"`), you are in Full mode — run these additional checks.

### Concurrency Analysis
- Does the PR introduce shared mutable state?
- Are there potential race conditions? (concurrent access to maps, slices, global state)
- Lock ordering: if multiple locks are acquired, is the order consistent?
- Channel usage: can channels deadlock? Is there proper cleanup?

### Trust Boundary Analysis
- Does the PR modify trust boundaries documented in ARCHITECTURE.md?
- Do changes cross trust boundaries without proper validation?
- Is data from less-trusted sources sanitized before reaching more-trusted components?

### Cross-Spec Impact
- Read all specs in `docs/specs/`. Do the PR's changes potentially violate invariants from OTHER specs?
- Example: a PR that changes the auth middleware might break invariants from the payments spec that assumes authenticated users.

### Drift Detection
- Do changes match the documented architecture, or are they introducing architectural drift?
- If drift is detected: is it intentional evolution (document it) or accidental erosion (fix it)?
- Check `.claude/meta/drift-debt.json` for existing drift in the same area.

### Performance Implications
- N+1 query patterns in new database access
- Unbounded loops or recursion on user-controlled input
- Missing pagination on list endpoints
- Cache invalidation issues (new writes without cache busting)
- Large payload handling (streaming vs buffering)

### Dependency Risk
- New dependencies: maintenance status, license compatibility, transitive dependency count
- Known vulnerabilities in new or updated packages
- Dependency size impact (bundle size for frontend, binary size for backend)

## Present Findings

Group findings by severity:

```markdown
## PR Review: #{number} — {title}

### CRITICAL ({N})
{Findings that would cause security vulnerabilities, data loss, or crashes}

### HIGH ({N})
{Findings that would cause bugs, incorrect behavior, or untested paths}

### MEDIUM ({N})
{Architecture drift, convention violations, missing edge case tests}

### LOW ({N})
{Style issues, documentation gaps, minor improvements}

### What Looks Good
{At least 1 item. Note what the PR does well with file references where applicable.
Look for: thorough test coverage with edge cases, correct use of documented patterns,
clean security implementation, good error handling, clear naming. If the PR is genuinely
poor, note the best aspect even if minor — "Tests exist for the happy path" is honest.}
```

**For each finding**, include:
- File and line reference
- What's wrong (1 sentence)
- Why it matters (1 sentence)
- Suggested fix (concrete, not vague)

## Post to PR (optional)

After presenting findings, offer: "Want me to post these findings as a PR comment?"

If yes:
- GitHub: `gh pr comment {number} --body "{findings}"`
- GitLab: `glab mr note {number} --message "{findings}"`

If there are 5 or more findings, format the comment as a collapsible details section:
```markdown
<details>
<summary>Correctless Review: {N} findings ({C} critical, {H} high)</summary>

{full findings}

</details>
```

## Claude Code Feature Integration

### Task Lists
See "Progress Visibility" section above — task creation and narration are mandatory.

### /btw
When reviewing PRs with more than 10 changed files or 300+ lines of diff, remind after reading context (before starting checks): "Use /btw to check something about the codebase without interrupting this review."

## Constraints

- **Read-only for project files.** This skill reads code and posts comments — it does not modify source.
- **Only flag documented violations.** Don't invent conventions the project doesn't have. Check ARCHITECTURE.md, CLAUDE.md, antipatterns.
- **Be specific with findings.** "Security issue" is useless. "SQL injection in `src/routes/search.ts:42` — user input concatenated into query string" is actionable.
- **Include "What Looks Good."** A review that only complains erodes trust. Note what the PR does well.
- **Don't duplicate CI.** If CI already runs linting, don't re-report lint errors. Focus on what CI can't catch: architecture, security logic, spec alignment.
- **Respect the PR scope.** Don't flag pre-existing issues in unchanged code. Only review what the PR changes.
