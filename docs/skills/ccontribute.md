# /ccontribute — Open Source Contribution

> Learn a target project's conventions first, then generate a PR that looks like a regular contributor wrote it.

## When to Use

- Contributing a bug fix, feature, or docs update to an open source project.
- Submitting code to a friend's project, a work monorepo owned by another team, or any repo you do not own.
- You want to maximize the chance of your PR being merged on the first review.
- **Not for:** Working on your own project (use `/ctdd`), or reviewing someone else's PR (use `/cpr-review` or `/cmaintain`).

## How It Fits in the Workflow

This skill is standalone. It does not require an active Correctless workflow in the target project. It learns the target project's conventions from scratch each time, so it works on any codebase. After running, you have a ready-to-submit PR that matches what maintainers expect.

## What It Does

- Scans the target project for conventions: `CONTRIBUTING.md`, PR templates, CODEOWNERS, linter/formatter configs, test patterns, CI config, commit format, and recently merged PRs.
- Reads the issue (if provided) and traces the relevant code paths to understand the change area.
- Plans the change and presents it for approval before writing code.
- **Implements using the cardinal rule: match, don't improve.** Uses their code style, their test framework, their error handling, their abstractions. Touches only files needed for the change.
- Runs all pre-flight checks the CI would run (linter, formatter, tests, build, commit format, DCO/sign-off).

## Example

```
User: /ccontribute 87

[1/7] Learning project conventions...
      Learned conventions — conventional commits, jest tests co-located,
      eslint + prettier, DCO sign-off required.

[2/7] Understanding the change...
      Issue #87: "Login form does not show error on invalid email format"
      2 files affected (src/components/LoginForm.tsx, src/components/__tests__/LoginForm.test.tsx),
      owned by @maintainer-a.

[3/7] Planning the change...
      Plan: Add client-side email validation to LoginForm, matching the existing
      validation pattern in RegistrationForm.tsx. Add 2 test cases using their
      describe/it + React Testing Library pattern.

      Any maintainer preferences you know that aren't documented?

User: They prefer small PRs, one concern each.

[4/7] Implementing (matching their patterns)...
[5/7] Pre-flight checks: 4/4 passing.
[6/7] Generating PR...
      PR created: "fix: show validation error for invalid email format (#87)"
[7/7] Self-review before submitting:
      - Tests added: yes (2 cases, matching LoginForm.test.tsx style)
      - Docs update: not needed (no public API change)
      - Scope: 2 files, matches plan exactly
```

## What It Reads / Writes

| Reads | Writes |
|-------|--------|
| `CONTRIBUTING.md`, PR templates | New/modified source files |
| CODEOWNERS | New/modified test files |
| Linter, formatter, CI configs | PR via `gh pr create` or `glab mr create` |
| 2-3 existing test files in the change area | |
| 5 recently merged PRs (for calibration) | |
| Linked issue (via `gh issue view`) | |

## Lite vs Full

Same in both modes. This skill operates on the target project's conventions, not the Correctless workflow intensity.

## Common Issues

- **No push access**: The skill detects this and tells you to fork first (`gh repo fork`). Push to your fork, not upstream.
- **Pre-flight checks fail**: The skill reports failures with explanations. Common causes: formatter violations (run their formatter), commit format mismatch (amend the message), missing DCO sign-off (`git commit -s`).
- **Scope creep warning**: If implementation touches files not in the plan, the skill stops and asks before proceeding. Unplanned files should go in a separate PR.
- **CLA bot blocks PR**: This happens after PR creation. Follow the bot's instructions (usually click a link or reply with a specific comment).
