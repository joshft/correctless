# Hacker Olympics Findings — Correctless

## Run: 2026-04-04
### Round 1 (6 agents: Injection, Config Manipulation, Auth/AuthZ, Encoding, Regression Hunter, CI/CD)
| ID | Severity | Tier | Title | Status | Fixed in |
|----|----------|------|-------|--------|----------|
| HACK-001 | critical | confirmed | eval of config-sourced test/coverage commands | deferred | architectural |
| HACK-002 | critical | confirmed | get_target_file() extension whitelist omits .sh/.json/.md | fixed | 5b0a6d0 |
| HACK-003 | critical | confirmed | Write pattern bypassed via &&/;/$() command chaining | fixed | 5b0a6d0 |
| HACK-004 | high | confirmed | curl/wget/dd/perl/patch not in write pattern list | fixed | 5b0a6d0 |
| HACK-005 | high | confirmed | Config unprotected via Bash during TDD phases | fixed | 5b0a6d0 |
| HACK-006 | high | confirmed | State file rm via Bash bypasses all gating | fixed | 5b0a6d0 |
| HACK-007 | high | confirmed | source_file pattern erasure defeats classification | fixed | 5b0a6d0 |
| HACK-008 | high | confirmed | Case-folding bypass: uppercase extensions evade gate | fixed | 5b0a6d0 |
| HACK-009 | high | confirmed | Misleading SHA comment on actions/checkout (v6.0.2 nonexistent) | fixed | 5b0a6d0 |
| HACK-010 | high | probable | No integrity check on plugin distribution | deferred | architectural |
| HACK-011 | medium | confirmed | Override renewal before expiry (28 calls from 3 grants) | fixed | 5b0a6d0 |
| HACK-012 | medium | confirmed | min_qa_rounds:0 bypasses Full QA minimum | fixed | 5b0a6d0 |
| HACK-013 | medium | probable | read_package_config $field jq injection | fixed | 5b0a6d0 |
| HACK-014 | medium | confirmed | Dot-prefix path normalization bypass | fixed | 5b0a6d0 |
| HACK-015 | medium | confirmed | Gitleaks baseline missing — scanner non-functional | fixed | 5b0a6d0 |
| HACK-016 | medium | probable | CODEOWNERS gap on workflow-config.json | fixed | 5b0a6d0 |
| HACK-017 | medium | probable | Three pre-commit hooks on mutable tags | fixed | 5b0a6d0 |
| HACK-018 | low | confirmed | MultiEdit bypass in fail-closed path | fixed | 5b0a6d0 |
| HACK-019 | low | confirmed | IFS unset vs restore in fail-closed loop | fixed | 5b0a6d0 |
| HACK-020 | low | suspicious | .correctless/artifacts/ not gitignored | fixed | 5b0a6d0 |

### Round 2
| ID | Severity | Tier | Title | Status | Fixed in |
|----|----------|------|-------|--------|----------|
| HACK-R2-001 | high | confirmed | Backtick subshell bypass (missing from IFS) | fixed | 5d3b5c8 |
| HACK-R2-002 | medium | confirmed | read_package_config field validation not anchored | fixed | 5d3b5c8 |
| HACK-R2-003 | low | confirmed | ln not in write command list | fixed | 5d3b5c8 |
| HACK-R2-004 | low | confirmed | 2>/dev/null false positive in redirect detection | fixed | 5d3b5c8 |

### Round 3
Zero critical/high findings. Converged.

Remaining theoretical gaps (LOW/MEDIUM, outside primary threat model):
- base64-encoded command bypass (requires adversarial LLM)
- sponge (moreutils) not in command list
- Leading redirect truncation (> at position 0)
- git checkout/restore not in command list
- Unlisted file extensions in Bash path extraction

### Regression tests
Gate hardening tested via existing test suites (1,517 tests, 0 failures).

## Recurring Patterns
- **Bash command parsing is inherently incomplete**: static analysis of shell command strings cannot prevent all write operations. The gate should be understood as a "seatbelt" for structured LLM workflow enforcement, not a security boundary against an adversarial actor. ARCHITECTURE.md already documents this.
- **Config as eval sink**: test commands must be shell commands, creating an inherent tension between configurability and safety. The mitigation (protecting config in all active phases) reduces the attack window but does not eliminate the class.
- **Extension/command allowlists drift**: every new language, tool, or file type requires updating multiple allowlists. These will drift over time.
