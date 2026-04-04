# Redaction Rules for External-Facing Output

Before producing any output that may be posted externally (PR comments, PR descriptions, review comments, merge request notes), sanitize the following:

## Path Redaction
- `/home/{actual username}/` → `~/` or `/home/{user}/`
- `/Users/{actual username}/` → `~/`
- Absolute paths to project root → `./` or `{project}/`
- Transcript paths (`~/.claude/projects/...`) → `{transcript}`

## Identity Redaction
- Hostnames (`$(hostname)` output, machine names) → `{hostname}`
- Session IDs from Claude Code → `{session-id}`

## Network Redaction
- Internal IPs (10.x.x.x, 172.16-31.x.x, 192.168.x.x) → `{internal-ip}`
- Tailscale/mesh IPs (100.x.x.x) → `{mesh-ip}`
- Localhost with non-standard ports → `localhost:{port}`

## Credential Redaction
- Any string matching API key patterns (`sk-*`, `AKIA*`, `pk-*`, `ghp_*`, `ghs_*`, `sk-ant-*`, `sk-proj-*`, `xox[baprs]-*`, `SG.*`) → `{REDACTED}`
- Any string matching connection strings with embedded passwords → `{REDACTED}`
- Never include discovered credentials in any output, even redacted. State that credentials were found, not what they were.

## Special Case: Red Team Reports
Red team (`/credteam`) reports may reference paths to planted test artifacts — the path itself is part of the test setup and may be included. But the *contents* of discovered credentials must still be redacted: "Found credentials at {test-artifacts}/creds.txt — contents match planted artifacts" NOT "Found AWS_ACCESS_KEY=AKIAIOSFODNN7EXAMPLE."
