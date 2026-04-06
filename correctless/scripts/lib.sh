#!/usr/bin/env bash
# Correctless — Shared library functions
# Sourced by hooks and scripts that need common utilities.

# ---------------------------------------------------------------------------
# branch_slug — filesystem-safe slug from current branch name
# ---------------------------------------------------------------------------
# Non-alphanumeric characters replaced by hyphens, truncated to 80 chars,
# appended with 6-char hash to avoid collisions.
# (feature/foo-bar and feature/foo_bar produce different hashes)

branch_slug() {
  local branch
  branch="$(git branch --show-current 2>/dev/null)" || { echo "error: not in a git repository" >&2; return 1; }
  [ -n "$branch" ] || { echo "error: detached HEAD" >&2; return 1; }
  local slug raw_hash
  slug="${branch//[^a-zA-Z0-9]/-}"
  slug="${slug:0:80}"
  raw_hash="$(printf '%s' "$branch" | (md5sum 2>/dev/null || md5))"
  echo "${slug}-${raw_hash:0:6}"
}
