# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 2.0.x   | :white_check_mark: |
| < 2.0   | :x:                |

## Reporting a Vulnerability

If you discover a security vulnerability in Correctless, please report it responsibly:

1. **Do NOT open a public GitHub issue** for security vulnerabilities.
2. Email: jft.inbox@gmail.com with subject line `[SECURITY] Correctless: <brief description>`
3. Include:
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact
   - Suggested fix (if any)

You should receive a response within 48 hours. We will work with you to understand the issue and coordinate disclosure.

## Security Considerations

Correctless is a set of Claude Code skill prompts and bash hooks. Key security considerations:

- **Hooks execute shell commands** — the workflow gate and audit trail hooks run as bash scripts. They are registered in `.claude/settings.json` and execute with the user's permissions.
- **No network access** — hooks do not make network requests. Skills may use `WebSearch`/`WebFetch` for research but only when explicitly configured.
- **No credential storage** — Correctless does not store or transmit credentials. The health check detects hardcoded secrets and helps remove them.
- **Output redaction** — external-facing skills (PR review, contribution, maintainer review) redact paths, credentials, and hostnames before posting to GitHub/GitLab.
- **Red team assessments** (`/credteam`) require an isolated environment — the skill verifies isolation before executing.

## Scope

The following are NOT security vulnerabilities in Correctless:
- The workflow gate can be bypassed via `workflow-advance.sh override` — this is intentional and logged
- Bash write commands that bypass the gate's pattern detection — this is a known limitation documented in the defense-in-depth section of the README
- Skills that spawn subagents inherit the user's permissions — this is by design
