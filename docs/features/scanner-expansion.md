# Scanner Expansion

Expands `scripts/antipattern-scan.sh` with grep portability checks and dead-code-in-security-paths detection. Mechanical prevention of two recurring bug classes that documentation-only enforcement failed to stop.

## What It Detects

### Grep Portability (AP-001 enforcement)

| Pattern ID | Severity | What It Catches |
|-----------|----------|-----------------|
| `gnu-grep-p` | high | `grep -P` and `--perl-regexp` in .sh files |
| `gnu-grep-ext` | medium | `\s`, `\w`, `\d` in grep patterns (GNU extensions, not POSIX ERE) |
| `gnu-grep-ext-low` | low | `\b` in grep patterns (more portable but still non-POSIX) |

**POSIX exclusion suppression**: If the same line contains the POSIX equivalent (`[[:space:]]` for `\s`, `[[:alnum:]]` for `\w`, `[[:digit:]]` for `\d`, `grep -w` for `\b`), the finding is suppressed. This is line-scoped -- a line using both a non-POSIX extension AND a POSIX class for a different purpose will be a false negative.

**Scope**: Only grep patterns in `.sh` files. `\s`/`\w`/`\d` in sed, awk, or perl contexts are out of scope.

### Dead Code in Security Paths (AP-022 enforcement)

| Pattern ID | Severity | What It Catches |
|-----------|----------|-----------------|
| `dead-security-fn` | high | Functions in security scripts with zero production callers |

**Security scripts** are identified by:
- Filename patterns in `scripts/`: `workflow-*.sh`, `*-gate.sh`, `*-guard.sh`, `audit-*.sh`, `review-*.sh`, `override-*.sh`, `*-scrutiny.sh`, `*-mandate.sh`, `*-crosscheck.sh`, `cauto-lock.sh`, `intent-hash.sh`, `auto-policy.sh`, `decision-*.sh`, `security-scan.sh`, `budget-check.sh`
- Explicit `# scanner: security` tag in the first 5 lines

**Excluded from scanning**:
- Scripts tagged `# scanner: library` (called by LLM skill orchestrators, not bash). However, library-tagged scripts not referenced by any `skills/*/SKILL.md` are still flagged.
- Functions with `_default_` prefix or `pluggable`/`callback` comment on the definition line (R-005)
- `hooks/` directory (self-contained entry points invoked by Claude Code's hook runner)

**Production files** (where callers are checked): `hooks/`, `scripts/`, `setup`, `bin/`

## How It Works with /ctdd

Check 8 in the test audit prompt ("Production call chain") complements the scanner:
- **Scanner** catches the mechanical case: function has zero production callers
- **Check 8** catches the semantic case: function is called but from the wrong entry point (e.g., test calls guard directly instead of through the entry point the spec names)

## Configuration

### Scanner Tags

Add to the first 5 lines of a script:
- `# scanner: security` -- include this script in dead-code scanning
- `# scanner: library` -- exclude from dead-code scanning (for scripts called by LLM orchestrators)

See PAT-014 in `.correctless/ARCHITECTURE.md`.

## Known Limitations

- **No sed/awk/perl portability scanning** -- only grep patterns checked
- **Static grep-based caller detection** -- variable dispatch (`$fn_name "$args"`) not detected. Use `_default_` prefix or pluggable comment for known dynamic dispatch.
- **No transitive dead code detection** -- if function A calls function B in the same file, and A has no external callers, B appears healthy. The test audit check 8 is the backstop.
- **No reachability analysis** -- callers inside unreachable branches count as callers

## Spec Reference

Full spec: `.correctless/specs/scanner-expansion.md` (11 rules)
