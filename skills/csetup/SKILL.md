---
name: csetup
description: Initialize Correctless and run a project health check. Detects stack, configures workflow, bootstraps docs, checks security/quality/CI/testing hygiene, and offers to fix gaps.
allowed-tools: Bash, Read, Write, Glob, Grep, WebSearch, WebFetch
---

# /csetup — Initialize Correctless

You are the onboarding agent. Your job is to get a project from zero to ready-to-use in one interactive conversation. Don't just run a script and dump output — guide the human through each decision.

**For existing projects:** Tell the user upfront: "Setting up on an existing project takes a few minutes — I need to scan your codebase to learn your conventions, architecture, and tooling. Larger projects take longer. I'll show you what I find as I go."

## Progress Visibility (MANDATORY)

Setup on existing projects takes several minutes. The user must see progress throughout.

**Before starting**, create a task list:
1. Detect project (language, test runner, package manager)
2. Run setup script
3. Review config interactively
4. Discover architecture and populate ARCHITECTURE.md
5. Mine conventions
6. Bootstrap AGENT_CONTEXT.md
7. Health check (17 items across security, quality, testing, CI, docs, git)
8. Source control configuration

**Between each step**, print a 1-line status: "Project detected — {language} with {test runner}. Running setup script..." During the health check, announce each category as it completes: "Security checks done — {N}/{M} passing. Running code quality checks..."

Mark each task complete as it finishes.

## Step 1: Detect the Project

Scan the project root silently. Then present findings conversationally:

- Language (from manifest files: go.mod, package.json, Cargo.toml, pyproject.toml)
- Test runner and commands
- Package manager (npm, pnpm, yarn, pip, cargo)
- Existing config (if `.claude/workflow-config.json` already exists)

Present: "I see a TypeScript project using pnpm with vitest. Does that look right, or should I adjust anything?"

If something looks wrong, let the human correct it before proceeding.

## Step 2: Run the Setup Script

Find and run the setup script to do the mechanical work (create directories, register hooks, generate config template):

```bash
for dir in \
  ~/.claude/plugins/cache/correctless/correctless/*/ \
  ~/.claude/plugins/cache/correctless/correctless-lite/*/ \
  .claude/skills/workflow/; do
  if [ -f "${dir}setup" ]; then
    "${dir}setup"
    break
  fi
done

# If no setup script found, tell the human
echo "Could not find Correctless setup script. Provide the install path or run setup manually."
```

## Step 3: Review Config Interactively

Read the generated `.claude/workflow-config.json`. Instead of telling the human to "review it," walk through the key fields:

- "Test command is set to `npm test` — is that correct?"
- "Lint command is `npm run lint` — do you have a lint script, or should I change this?"
- "Coverage command is `npm test -- --coverage` — does your test runner support this flag?"

Fix any issues the human flags.

**Full mode only**: if the config has `workflow.intensity`, ask about intensity:
- "Intensity is set to `standard`. For context: `low` skips STRIDE and uses fewer QA rounds, `high` adds fail-closed mode, `critical` requires formal modeling. Want to change it?"

## Step 4: Discover and Bootstrap ARCHITECTURE.md

Read `.claude/workflow-config.json` field `setup.architecture_state` to determine mode:
- `template` or `missing` → **full bootstrap**: scan the codebase and populate from scratch
- `existing` → **merge mode**: scan, compare with existing content, propose only additions
- `null` or field absent (older config, or jq was missing at setup time) → **detect manually**: check if ARCHITECTURE.md exists and contains real content (no `{PLACEHOLDER}` or `{PROJECT_NAME}` markers). If real content, use merge mode. If template/missing, use full bootstrap.

**For existing projects, tell the user:** "Your project already has an ARCHITECTURE.md. I'll scan the codebase and suggest Correctless-specific sections to add alongside your existing content. This may take a moment — I'm learning your project."

### Scanning Protocol

Run these scans in parallel where possible:

**1. Directory structure scan:**
- Glob for structural directories: `src/*/`, `lib/*/`, `internal/*/`, `pkg/*/`, `app/*/`, `packages/*/`, `cmd/*/`
- For each candidate directory, read the directory listing and any index/barrel file to determine its purpose
- Look for architectural layers: `controllers/`, `services/`, `repositories/`, `middleware/`, `models/`, `handlers/`, `routes/`, `utils/`, `hooks/`, `components/`

**2. Pattern mining scan** (grep for these signals):
- **Validation**: zod, joi, yup, class-validator, pydantic, validator imports — note WHERE validation happens (route handlers? middleware? service layer?)
- **Error handling**: custom error classes (`extends Error`, `class.*Error`), error middleware, centralized error handlers
- **Database access**: ORM imports (prisma, sequelize, typeorm, sqlalchemy, gorm, diesel) — is access centralized or scattered?
- **Auth**: JWT, session, OAuth, auth middleware — how does auth flow through the request lifecycle?
- **Config**: `process.env`, `os.Getenv`, `os.environ` — centralized config module or scattered env reads?
- **Logging**: logger imports, `console.log` vs structured logging (winston, pino, slog, logrus)
- **State management**: Redux, Zustand, Context, signals, stores
- **API patterns**: Express/Fastify routes, gin/echo handlers, Flask/Django views — how are routes organized?

**3. Test infrastructure scan:**
- Where are test files? Co-located with source, or separate directories?
- Test utilities/helpers: `test/utils/`, `test/fixtures/`, `test/factories/`
- Mock patterns: jest.mock, vitest.mock, httptest, unittest.mock, gomock
- Configuration: jest.config, vitest.config, pytest.ini, conftest.py

### Full Bootstrap Mode (template/missing)

Populate the entire ARCHITECTURE.md from scan results:
1. **Key Components table**: one row per significant directory/module discovered
2. **Design Patterns** (PAT-xxx format): one entry per detected pattern
3. **Conventions**: naming, file organization, import patterns discovered
4. Present the complete draft: "Here's what I found in your codebase. Review and correct anything that's wrong."
5. Write approved version

### Merge Mode (existing)

Read the existing ARCHITECTURE.md fully. Then:
1. **Compare scan results against what's already documented.** If the existing doc already describes the repository pattern in prose and you find Prisma repos in `src/db/repos/`, don't add a second section — instead note: "Your existing docs already cover database access patterns. I'd add a Correctless-structured ID (PAT-001) to your existing section for reference by other skills. Here's how that would look."
2. **Identify missing Correctless sections**: Design Patterns with PAT-xxx numbering, Conventions, Trust Boundaries (Full mode). Propose each as an addition that respects the user's existing structure — don't impose the template's format on top of it.
3. **Never delete or rewrite existing content.** Only append new sections or annotate existing ones.
4. Present each proposed addition separately for approval.

## Step 5: Mine and Capture Conventions

**Don't ask the user to describe conventions from memory. Mine the codebase first, then confirm.** Describing your own conventions from memory is hard — you forget things, you describe what you wish the conventions were rather than what they are. Being shown what the codebase actually does and saying "yes that's right" or "no, that's a mistake we should fix" is fast and accurate.

### Convention Mining Scan

Before asking the user anything, scan the codebase for implicit conventions:

**1. Naming conventions:**
- Sample 20 source files: are they `camelCase.ts`, `kebab-case.ts`, `snake_case.ts`, `PascalCase.ts`?
- Check directory naming: singular (`model/`) vs plural (`models/`)
- Check exported function/class naming: camelCase vs snake_case vs PascalCase

**Surface inconsistencies as findings:** If 18/20 files use camelCase but 2 use kebab-case, that's a convention with violations: "18/20 files use camelCase naming. 2 files deviate: `old-utils.ts`, `legacy-helper.ts`. Is camelCase the convention? If so, these are cleanup candidates."

**2. Import/module conventions:**
- Barrel files (`index.ts`, `__init__.py`, `mod.rs`): used consistently?
- Path aliases (`@/`, `~/`, `#`) in tsconfig.json or package.json
- Import ordering: eslint rules or visible grouping pattern?

**3. Error handling conventions:**
- Custom error classes: centralized or scattered?
- Error response shapes in API handlers: consistent format? If half the routes return `{ error: "message" }` and half return `{ error: { code: "X", message: "Y" } }`, surface it: "I see two different error response formats in your API routes. Want to pick one as the convention?"
- Error logging: structured vs console, consistent vs ad-hoc

**4. Testing conventions:**
- Co-located tests (same directory as source) vs separate test directories
- Test utilities/helpers: shared fixtures, factories, builders
- Mock patterns: what's mocked, what uses real implementations
- Naming: `describe/it` nesting, "should..." vs "when..." conventions

**5. Git conventions:**
- Run `git log --oneline -30`: detect conventional commits, Jira prefixes, ticket numbers, capitalization, tense
- Check for `.commitlintrc`, `commitlint.config.js`

**6. Configuration:**
- `.editorconfig` (indentation, line endings)
- Prettier/biome/eslint configs for formatting rules
- tsconfig.json strictness settings

### Present Mining Results

Present findings as a categorized summary: "I scanned your codebase and found these conventions:" with one section per category. For each finding, ask: "Is this intentional? Should I document it?"

**Anti-conventions are valuable too.** If you find inconsistent patterns (two error formats, mixed naming styles, different test approaches in different directories), surface them explicitly: "I see two different patterns for X. Want to pick one as the convention? I'll add it to ARCHITECTURE.md and future specs will enforce it." This turns convention capture into a mini-audit for free.

### Then Ask for Undocumented Conventions

After presenting mining results, follow up:

```
Those are the conventions I detected from code. Are there additional ones not visible in the codebase?

Things like:
- Architecture decisions that aren't reflected in file structure
- "Never do X" rules that everyone just knows
- API versioning or pagination standards
- Database migration patterns
- Deployment conventions

You can paste a doc, point me to a file, or describe them.
```

### Where conventions go

Different conventions go to different files because different agents read them at different times:

| Convention type | Goes in | Why there |
|----------------|---------|-----------|
| Architecture patterns (service layer, repository, middleware, data flow) | `ARCHITECTURE.md` — Design Patterns section | Spec agents write specs that compose with these. Verify/audit agents check compliance. |
| Coding style (naming, formatting, import ordering, comments) | `CLAUDE.md` | Read at start of every session. Always in context. |
| Error handling (propagation, logging, response format, retry policy) | `ARCHITECTURE.md` — Design Patterns section | These are architectural decisions. Spec agents need them to write correct invariants. |
| Testing conventions (what to mock, naming, fixtures, frameworks) | `CLAUDE.md` | Test agents read CLAUDE.md before writing tests. |
| API conventions (versioning, pagination, error shapes, auth) | `ARCHITECTURE.md` — Design Patterns, with summary in `AGENT_CONTEXT.md` | Spec agents need these to write rules matching existing API behavior. |
| Git/workflow conventions (branch naming, commit messages, PR templates) | `CLAUDE.md` | Affects how the agent interacts with git throughout the workflow. |
| Project prohibitions (never use X, never call Y directly, never store Z) | `ARCHITECTURE.md` — Prohibitions section | Become formal prohibitions in Full mode. Review agent checks against these in Lite. |

### How to process conventions

**If the user pastes a document or points to a file:**
1. Read the source material
2. Classify each convention by type
3. Draft entries for each destination file
4. Present each entry one at a time: "I'd put this in ARCHITECTURE.md under Design Patterns. Look right?"
5. Write approved entries

**If the user describes them conversationally:**
1. Capture each convention
2. Ask clarifying questions if ambiguous ("When you say 'repository pattern' — does all database access go through repo structs, or just queries?")
3. Classify, draft, present, write

**If the user skips:**
Fine. After the first 2-3 features, suggest formalizing patterns that have appeared consistently across specs: "I've seen the service → repository → database pattern in 3 specs. Want me to add it to ARCHITECTURE.md?"

### Examples

**User says:** "All database queries go through repo structs in `internal/repo/`. Never raw SQL in handlers."

**ARCHITECTURE.md** gets:
```markdown
### PAT-001: Repository Pattern
- All database access through repository structs in `internal/repo/`
- Never import database packages from HTTP handlers or service layer
- Each entity gets its own repo file: `internal/repo/user.go`
- Repos accept and return domain types, not database row types
```

**CLAUDE.md** gets:
```markdown
## Database Access
All database queries go through repository structs in `internal/repo/`.
Never use raw SQL or import database packages outside the repo layer.
```

---

**User says:** "Error responses always look like `{"error": {"code": "INVALID_INPUT", "message": "...", "details": [...]}}`"

**ARCHITECTURE.md** gets a PAT-xxx entry. **AGENT_CONTEXT.md** Quick Reference gets the format.

---

**User says:** "Never use console.log. Use the logger from src/lib/logger.ts."

**CLAUDE.md** gets the convention. In Full mode, this also becomes a prohibition pattern that `/cverify` checks.

## Step 6: Bootstrap AGENT_CONTEXT.md

Read `.claude/workflow-config.json` field `setup.agent_context_state` to determine mode:
- `template` or `missing` → draft a populated version from scratch
- `existing` → read existing content, propose only missing Correctless sections (Quick Reference table with commands, Common Pitfalls if absent)
- `null` or field absent → detect manually: check if AGENT_CONTEXT.md exists and contains real content (no `{PLACEHOLDER}` markers). If real content, use merge mode. If template/missing, use full bootstrap.

For template/missing, populate based on:
- Codebase scan results from Step 4
- ARCHITECTURE.md entries just created
- Conventions captured in Step 5
- Config file (test/lint/build commands)
- Recent git history (`git log --oneline -20` — skip if no commits exist yet)

For existing files: read fully, identify what's already covered, propose only additions. Never replace existing content.

Present the draft (or proposed additions) for approval. Write after approval.

## Step 7: Project Health Check

Run a comprehensive health check and present a health card. This applies to both Lite and Full — project hygiene is the same regardless of workflow mode.

### Detect Existing Tooling First

Before running the 17 checks, scan for existing tool configurations. This changes how findings are reported — acknowledge what exists rather than suggesting duplicates.

**Hook systems:**
- Check for: `.husky/` directory, `husky` in package.json, `.lintstagedrc*` or `lint-staged` in package.json, `.pre-commit-config.yaml`, `lefthook.yml`
- If ANY hook system exists: the "Pre-commit hooks" check should acknowledge it. Correctless hooks are Claude Code PreToolUse hooks (registered in `.claude/settings.json`), not git hooks — they coexist without conflict. Note: "Found: husky + lint-staged. Correctless hooks are separate (they gate Claude's file operations, not git commits). No conflict. Consider adding gitleaks to your lint-staged config for secret scanning if not present."

**CI enrichment:**
- When CI files are found, actually read them. Grep for: test commands, lint commands, coverage steps, security scanning, dependency scanning.
- Map CI coverage to health check items. If CI runs `npm test -- --coverage`, mark coverage as `Found (via CI)`.

**Coverage config detection:**
- Check for: `jest.config.*` with `coverageThreshold`, `.coveragerc`, `.nycrc`, `pyproject.toml [tool.coverage]`, `tarpaulin.toml`, `vitest.config.*` coverage settings

**Test pattern validation:**
- Glob for test files broadly: `**/*.test.*`, `**/*.spec.*`, `**/*_test.*`, `**/test_*.*`, `__tests__/**/*`, `tests/**/*`
- Compare found files against `workflow-config.json`'s `patterns.test_file`
- If files exist that don't match the config pattern: "Found 23 test files in `__tests__/` but your config only matches `*.test.ts`. The workflow gate may misclassify these. Want me to update the test pattern?" This prevents frustration during the first `/ctdd` run.

### Health Check Status Vocabulary

Use richer status values than binary pass/fail:
- `Found` — detected and correctly configured
- `Found (via CI)` — not a local tool but CI handles it
- `Found (equivalent)` — using a different tool that serves the same purpose (e.g., husky instead of pre-commit)
- `Missing` — not found, recommend adding
- `Partial` — found but incomplete (e.g., linter exists but no config)
- `N/A` — not applicable to this project type

The score denominator should subtract N/A items: a Go project with 15 applicable checks scoring 12/15 is more meaningful than 12/17.

### Security

**Dependency vulnerability scanning:**
- Check for: `.github/dependabot.yml`, `.snyk`, `socket.yml`, Renovate config (`renovate.json`, `.renovaterc`), npm audit in CI
- If missing: offer to generate a Dependabot config tailored to the project's package ecosystem

**Secret scanning:**
- Check for: `.pre-commit-config.yaml` with gitleaks or truffleHog hook, git-secrets config
- If missing: the primary recommendation is the gitleaks pre-commit hook (see pre-commit section below). This catches secrets BEFORE they enter the repo. GitHub's built-in scanning is a good second layer but it's reactive — it notifies after the secret is already committed.

**Secrets in source (ALWAYS check this):**
- Grep tracked files for patterns: `sk-live-`, `sk_live_`, `AKIA`, `-----BEGIN (RSA|EC|OPENSSH) PRIVATE KEY-----`, password/secret/token assignments that aren't env vars, connection strings with embedded credentials, `sk-ant-` (Anthropic), `sk-proj-` (OpenAI), `ghp_`/`ghs_`/`github_pat_` (GitHub tokens), `xox[baprs]-` (Slack), `SG\.` (SendGrid)
- Report findings with file:line — these are "fix now" urgency
- This catches the most common vibe-coding mistake: hardcoding a Stripe key or DB password during development

**If secrets are found, explain secrets management to the user.** Many developers who hardcode secrets have never heard of secrets management. Don't just say "use environment variables" — explain the options, starting with free and simple:

Present this guide (adapt to their stack):

**Level 1 — Environment variables (free, start here):**
Move secrets out of source code into a `.env` file. The app reads them via `process.env.STRIPE_KEY` (Node), `os.Getenv("STRIPE_KEY")` (Go), `os.environ["STRIPE_KEY"]` (Python). The `.env` file goes in `.gitignore` so it's never committed. Create a `.env.example` with placeholder values so other developers know which variables are needed. Offer to do this migration for them — move each hardcoded secret to `.env`, replace with env var reference, add `.env` to `.gitignore`, generate `.env.example`.

**Level 2 — Platform secrets (free with most hosts):**
Most deployment platforms have built-in secret management:
- **Vercel/Netlify/Railway/Render**: environment variables in the dashboard (encrypted at rest, injected at deploy)
- **GitHub Actions**: repository secrets for CI (`${{ secrets.STRIPE_KEY }}`)
- **Docker**: `docker secret` or env files not baked into the image
- **Fly.io/Heroku**: `fly secrets set` / `heroku config:set`

These are free, require zero infrastructure, and are the right answer for most projects. The secret never touches source code or git history.

**Level 3 — Secret scanning prevention (free):**
Even after moving to env vars, prevent future accidents:
- **GitHub secret scanning**: free for public repos, catches known secret patterns on push
- **git-secrets** (AWS, free): pre-commit hook that blocks commits containing secret patterns
- **pre-commit framework** with `detect-secrets` hook: scans staged files before commit

Offer to set up one of these.

**Level 4 — Dedicated secret managers (for teams/production):**
Only mention these if the project looks like it has production infrastructure:
- **Infisical** (open source, free tier): centralized secrets with rotation, audit logs, injected at runtime
- **Doppler** (free for individuals): syncs secrets across environments
- **SOPS** (free, Mozilla): encrypts secret files so they CAN be committed (encrypted values in git, decrypted at deploy)
- **1Password CLI / Bitwarden Secrets Manager**: if they already use a password manager

Don't mention HashiCorp Vault, AWS Secrets Manager, or GCP Secret Manager unless the project is clearly enterprise-scale — these are overkill for most projects and cost money.

**If secrets are already in git history:** warn the user that removing them from source isn't enough — they're still in git history. Anyone who clones the repo can find them with `git log -p`.

Two things must happen:

1. **Rotate the secret (most important).** Generate a new API key / password / token from the provider's dashboard and revoke the old one. No amount of history scrubbing helps if the old key is already compromised. Walk the user through where to rotate each secret found (e.g., "Go to Stripe Dashboard → Developers → API Keys → Roll Key").

2. **Scrub git history.** Offer to do this for the user. Use `git filter-repo` (preferred) or `BFG Repo-Cleaner`:

```bash
# Install git-filter-repo if needed
pip install git-filter-repo

# Remove the file(s) that contained secrets from all history
git filter-repo --invert-paths --path src/config.ts --force

# OR replace specific strings across all history
git filter-repo --replace-text <(echo 'sk-live-ACTUAL_KEY_HERE==>REDACTED') --force
```

After scrubbing:
- Force push: `git push --force-with-lease`
- Tell all collaborators to re-clone (their local copies still have the old history)
- If the repo was ever public, assume the secret was scraped — rotation is non-negotiable

Offer to handle the full process: identify which files/strings to scrub, run the filter, verify the secret is gone from history, and remind the user to force push and rotate.

**Gitignore coverage:**
- Check `.gitignore` includes: `.env`, `.env.*`, credential files, private keys, OS files (`.DS_Store`, `Thumbs.db`), IDE configs
- Offer to add missing entries

### Code Quality

**Linter:**
- Check for: eslint config, golangci-lint config, pylint/ruff/flake8, clippy
- If missing: offer to generate a starter config for the detected framework
- If present: run lint command and report if it passes

**Formatter:**
- Check for: prettier config, gofmt (built-in), black/ruff format, rustfmt
- If missing: offer to set up the standard formatter

**Type checking:**
- TypeScript: is `strict: true` in tsconfig.json? If not, flag it
- Python: mypy/pyright configured?
- Go: does `go vet` pass?
- If strict mode off: explain what it catches, offer to enable (warn about error flood)

**Pre-commit hooks (via [pre-commit.com](https://pre-commit.com) framework):**

Pre-commit hooks catch problems BEFORE they enter the repo. A health check finding "2 hardcoded secrets" is already too late — they're in git history. A pre-commit hook rejects the commit before the secret ever lands.

- Check for: `.pre-commit-config.yaml` in project root
- If missing: offer to generate one tailored to the project's stack

**Be opinionated.** Don't ask the user to pick hooks. Detect the stack and generate the right config. The user can remove what they don't want.

**Core hooks (every project, regardless of language):**
```yaml
repos:
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v5.0.0
    hooks:
      - id: trailing-whitespace
      - id: end-of-file-fixer
      - id: check-yaml
      - id: check-json
      - id: check-merge-conflict
      - id: check-added-large-files
        args: ['--maxkb=500']
      - id: detect-private-key
      - id: check-case-conflict

  # Secret scanning — the most important hook
  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.22.1
    hooks:
      - id: gitleaks

  # Typos in code and docs
  - repo: https://github.com/crate-ci/typos
    rev: v1.28.4
    hooks:
      - id: typos
```

**Language-specific hooks (added based on detected stack):**

Go:
```yaml
  - repo: https://github.com/dnephin/pre-commit-golang
    rev: v0.5.1
    hooks:
      - id: go-fmt
      - id: go-vet
```

Python:
```yaml
  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: v0.8.6
    hooks:
      - id: ruff
        args: [--fix]
      - id: ruff-format
```

TypeScript/JavaScript:
```yaml
  - repo: https://github.com/biomejs/pre-commit
    rev: v0.6.1
    hooks:
      - id: biome-check
        additional_dependencies: ["@biomejs/biome@1.9.0"]
```
(If project already uses eslint+prettier, use husky+lint-staged for JS hooks and layer pre-commit on top for secrets/universal hooks.)

Rust:
```yaml
  - repo: local
    hooks:
      - id: cargo-fmt
        name: cargo fmt
        entry: cargo fmt --
        language: system
        types: [rust]
```

Shell scripts:
```yaml
  - repo: https://github.com/shellcheck-py/shellcheck-py
    rev: v0.10.0.1
    hooks:
      - id: shellcheck
```

Conventional commits (if detected/configured):
```yaml
  - repo: https://github.com/commitizen-tools/commitizen
    rev: v4.1.1
    hooks:
      - id: commitizen
```

**After generating the config:**
1. Write `.pre-commit-config.yaml`
2. Run `pre-commit install` to activate hooks
3. Run `pre-commit run --all-files` once — this surfaces existing issues (trailing whitespace, formatting, maybe a private key in a fixture). Fixing these in one commit establishes a clean baseline.

**Relationship to CI:** Add `pre-commit run --all-files` as the first step in the generated CI workflow. This catches any commits that bypassed local hooks via `git commit --no-verify`.

### Testing

**Test runner:**
- Check for test config and test files
- If zero tests: flag prominently — "This project has zero tests. Correctless will help you write them, but the current state is high-risk."
- If tests exist: run them and report pass/fail count

**Coverage:**
- Check for coverage config in test runner or CI
- If missing: offer to add coverage reporting (even without threshold — knowing the number matters)

**Race detector (Go):**
- Check for `-race` flag in test commands
- If missing: offer to add `go test -race ./...`

### CI/CD

**CI pipeline:**
- Check for: `.github/workflows/`, `.gitlab-ci.yml`, `Jenkinsfile`, `.circleci/`, `bitbucket-pipelines.yml`
- If missing: offer to generate a GitHub Actions workflow with: `pre-commit run --all-files` (first step), install, lint, type-check, test, build

**CI on PRs:**
- If CI exists: does it trigger on pull requests? Check trigger config.
- If only on push to main: flag — issues should be caught on the PR

**Branch protection:**
- Check if branch protection is configured (GitHub API or `.github/settings.yml`)
- If not: recommend, provide direct link to settings. Can't set this programmatically.

### Documentation

**README:**
- Check if README.md exists and has content beyond framework boilerplate
- If boilerplate: flag — "Your README is the default framework template"

**.env.example:**
- If .env exists but .env.example doesn't: offer to generate from .env with values redacted
- Critical for onboarding — without it, developers don't know which env vars are needed

**LICENSE:**
- If missing: note it. Don't generate — the license choice is the human's.

### Git Hygiene

**.gitignore completeness:**
- Check against known list for the stack
- Flag missing entries, offer to add

**Committed artifacts:**
- Check if tracked: `node_modules/`, `dist/`, `build/`, `.next/`, `__pycache__/`, vendor/ (unless Go vendor mode), binary files
- If found: flag with removal instructions

**Lock file:**
- Check if lock file is committed (package-lock.json, yarn.lock, pnpm-lock.yaml, go.sum, Cargo.lock)
- If not committed: flag — should be committed for reproducible installs

**Large files:**
- Quick scan for files >5MB that might be accidentally committed
- If found: suggest git-lfs or .gitignore

### Present the Health Card

Format the results as a health card using the status vocabulary above:

```
Project Health Check — {project-name} ({language}/{framework})

Security:
  {✓/✗/—} Dependency scanning: {Found|Found (via CI)|Missing|N/A}
  {✓/✗/—} Secret scanning: {Found|Found (equivalent: husky+gitleaks)|Missing}
  {✓/✗/—} No secrets in source: {Found: clean|FOUND: N secrets — fix now}
  {✓/✗/—} .gitignore covers sensitive files: {Found|Partial|Missing}

Code Quality:
  {✓/✗/—} Linter: {Found: eslint|Found (via CI)|Missing}
  {✓/✗/—} Formatter: {Found: prettier|Missing}
  {✓/✗/—} Type checking: {Found: strict|Partial: not strict|N/A}
  {✓/✗/—} Pre-commit hooks: {Found: pre-commit|Found (equivalent: husky)|Missing}

Testing:
  {✓/✗/—} Test runner: {Found: jest (47 tests)|Missing: zero tests}
  {✓/✗/—} Coverage reporting: {Found (via CI)|Partial: no threshold|Missing}

CI/CD:
  {✓/✗/—} CI pipeline: {Found: GitHub Actions (runs tests, lint)|Missing}
  {✓/✗/—} Branch protection: {Found|Missing}

Documentation:
  {✓/✗/—} README: {Found|Partial: boilerplate|Missing}
  {✓/✗/—} .env.example: {Found|Missing|N/A: no .env}

Git Hygiene:
  {✓/✗/—} .gitignore complete: {Found|Partial}
  {✓/✗/—} No committed build artifacts: {Found: clean|FOUND: node_modules/ tracked}
  {✓/✗/—} Lock file committed: {Found|Missing}

Score: X/Y checks passing (Y = applicable checks, excluding N/A)
```

### Prioritize and Offer Fixes

Group issues by urgency:

1. **Fix now** (security): hardcoded secrets, missing .gitignore for .env, committed credentials
2. **Fix soon** (quality): no linter, no CI, no tests, committed build artifacts
3. **Recommended** (hygiene): no pre-commit hooks, no coverage, no .env.example, no LICENSE

For each issue: explain what it is (one sentence), why it matters (one sentence), and offer to generate the fix. The human picks which fixes to apply.

**What to generate when asked:**

| Fix | Generated file | Tailored to |
|-----|---------------|-------------|
| Dependabot config | `.github/dependabot.yml` | Package ecosystems detected |
| CI workflow | `.github/workflows/ci.yml` | Language, test runner, linter, build command, `pre-commit run --all-files` as first step |
| Pre-commit config | `.pre-commit-config.yaml` | Core hooks (gitleaks, typos, file hygiene) + language-specific hooks |
| Coverage config | Updated test script + CI step | Test runner detected |
| .env.example | `.env.example` with redacted values | Current .env file |
| .gitignore additions | Updated `.gitignore` | Stack-specific entries |
| Linter config | `.eslintrc.*` or equivalent | Framework detected |
| Formatter config | `.prettierrc` or equivalent | Language detected |

Every generated file includes: `# Generated by Correctless /csetup — review and customize as needed`

After applying fixes, re-run the health card to show progress.

## Step 8: Source Control Configuration

Detect and configure source control preferences. Check what's already configured before asking.

**Auto-detect first:**
- Git remote: GitHub, GitLab, Bitbucket? (determines CLI tool and PR template location)
- CLI tools: is `gh` or `glab` in PATH?
- Existing PR template: `.github/pull_request_template.md` or equivalent?
- Existing commit convention: scan recent commits for patterns (conventional commits, Jira prefixes)
- Default branch name: main vs master vs other
- Branch protection: check if configured (via `gh` if available)

**Present detected values, then ask what's missing:**

```
Source Control — detected:
  ✓ Remote: GitHub
  ✓ Default branch: main
  ✓ gh CLI: installed
  ✓ Commit style: conventional commits (detected from history)
  ✗ PR template: none found → I can generate one
  ✗ Branch protection: not configured → recommend enabling

Branching strategy: [feature branches / trunk-based]?
Merge strategy: [squash / merge / rebase]?
```

**Where answers go:**

| Setting | Stored in | Read by |
|---------|-----------|---------|
| Branching strategy | `workflow-config.json` | `workflow-advance.sh init`, `/caudit` |
| Merge strategy | `workflow-config.json` (`workflow.merge_strategy`) | `/ctdd done`, `/caudit` |
| PR CLI tool | `CLAUDE.md` | Every session |
| Commit format | `CLAUDE.md` | Every session |
| PR template | `.github/pull_request_template.md` | Agent pre-fills on PR creation |

**If no PR template exists**, offer to generate one with Correctless sections:
```markdown
## Description
<!-- What does this change do? -->

## Spec
<!-- Link: docs/specs/xxx.md -->

## Testing
<!-- Coverage? All rules covered? -->

## Checklist
- [ ] Tests pass
- [ ] Spec rules covered
- [ ] /cverify passed
- [ ] Documentation updated
```

**Commit format goes to CLAUDE.md.** If conventional commits:
```markdown
## Commit Messages
Use conventional commits: feat:, fix:, test:, docs:, refactor:, chore:
During TDD: test(feature): ..., feat(feature): ..., fix(feature): per QA finding
During audit: fix(audit-qa-r2): finding-id — description
```

## Step 9: First Feature Guidance

End with clear next steps:

"You're set up. Here's how to use it:

1. Create a feature branch: `git checkout -b feature/my-feature`
2. Run `/cspec` to write a spec for what you're building
3. The workflow guides you from there: spec → review → tests → implementation → QA → verify → docs

Current commands available: `/csetup`, `/cspec`, `/creview`, `/ctdd`, `/cverify`, `/cdocs`, `/crefactor`, `/cpr-review`, `/ccontribute`, `/cstatus`, `/csummary`, `/cmetrics`, `/cdebug`, `/chelp`
Check workflow state anytime: `.claude/hooks/workflow-advance.sh status`

Want to start a feature now?"

If the human says yes, ask what they want to build and hand off to the spec flow.

## Subsequent Runs

When `/csetup` is run on a project that's already configured:

1. Re-run all health checks
2. Show what improved since last run, what's new, what's still missing
3. Only offer to fix new or unresolved issues — don't re-prompt for things already declined
4. Re-detect tools (mutation testing, Alloy, external model CLIs) and offer to enable newly found ones

## Claude Code Feature Integration

### Task Lists
See "Progress Visibility" section above — task creation and narration are mandatory.

## If Something Goes Wrong

- **Setup is idempotent** — the bash script skips files that already exist and never overwrites user-edited content. Re-running is safe.
- **The interactive skill (Steps 3-9) asks before writing.** If interrupted, re-run. Already-completed steps (config review, health check) will re-run but won't overwrite previous choices.
- **If the health check is wrong**: The health check reads your project state at that moment. If you've fixed something, re-run `/csetup` to get an updated health card.

## Constraints

- **Be conversational, not transactional.** Don't dump a wall of config at the human.
- **Ask permission before writing.** "Can I update ARCHITECTURE.md with these entries?"
- **One decision at a time.** Don't ask 10 questions in one message.
- **Accept defaults gracefully.** If the human says "looks fine" to the config review, move on — don't force them to confirm every field.
- **Don't be preachy about the health card.** Present facts, offer fixes, let the human decide. A project with 5/17 checks passing isn't "bad" — it might be an early prototype.
- **One exception: hardcoded secrets are always urgent.** Flag them prominently regardless of project context.
- **All generated files inside the project directory.** Never /tmp.
