#!/usr/bin/env bash
# Correctless — Harness Fingerprint Test Helpers
# Feature-specific helpers for harness-fingerprint-r2-hardening
# (NOT in shared tests/test-helpers.sh — Finding #8 amendment requires a
#  feature-specific file to keep the helper out of the shared blast radius)
#
# Spec: .correctless/specs/harness-fingerprint-r2-hardening.md
#   INV-010, BND-003

# ---------------------------------------------------------------------------
# make_test_harness_script <version> <workdir>
# ---------------------------------------------------------------------------
# Copies the production scripts/harness-fingerprint.sh into $workdir under a
# destination filename that does NOT match the protected pattern
# `*/scripts/harness-fingerprint.sh` (BND-003), substitutes the
# `HARNESS_VERSION=N` constant via sed, validates the substitution, and echoes
# the destination path on stdout.
#
# Usage:
#   helper_path="$(make_test_harness_script 42 "$workdir")"
#   bash "$helper_path" check ...
make_test_harness_script() {
  local version="$1"
  local workdir="$2"

  if [ -z "$version" ] || ! [[ "$version" =~ ^[0-9]+$ ]]; then
    echo "make_test_harness_script: version must be a non-negative integer (got: '$version')" >&2
    return 1
  fi
  if [ -z "$workdir" ] || [ ! -d "$workdir" ]; then
    echo "make_test_harness_script: workdir does not exist (got: '$workdir')" >&2
    return 1
  fi
  # Boundary check: workdir must be under $WORK_BASE (BND-003 fail-loud)
  if [ -n "${WORK_BASE-}" ]; then
    case "$workdir" in
      "$WORK_BASE"/*|"$WORK_BASE") ;;
      *)
        echo "make_test_harness_script: workdir '$workdir' not under WORK_BASE='$WORK_BASE'" >&2
        return 1
        ;;
    esac
  fi

  # Resolve the production script — caller's REPO_DIR is the canonical anchor.
  local repo_dir="${REPO_DIR-}"
  if [ -z "$repo_dir" ]; then
    repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  fi
  local src="$repo_dir/scripts/harness-fingerprint.sh"
  if [ ! -f "$src" ]; then
    echo "make_test_harness_script: production script not found at $src" >&2
    return 1
  fi

  # Destination filename: harness-fp-test-XXXXXX.sh (BND-003 — no `scripts/`
  # parent component, so the destination path does NOT match the protected
  # pattern in DEFAULTS). mktemp avoids BASHPID collisions when the helper
  # is called multiple times from the same shell.
  local dst
  dst="$(mktemp "$workdir/harness-fp-test-XXXXXX.sh")" || { echo "make_test_harness_script: mktemp failed" >&2; return 1; }
  if ! sed -E 's/^HARNESS_VERSION=.*$/HARNESS_VERSION='"$version"'/' "$src" > "$dst"; then
    echo "make_test_harness_script: sed substitution failed" >&2
    rm -f "$dst"
    return 1
  fi

  # Validate substitution actually took effect (prevents silent BSD-sed
  # divergence per EA-002).
  if ! grep -qE "^HARNESS_VERSION=$version\$" "$dst"; then
    echo "make_test_harness_script: substitution validation failed (HARNESS_VERSION=$version not found in $dst)" >&2
    rm -f "$dst"
    return 1
  fi

  # Co-locate the production lib.sh next to the destination so SCRIPT_DIR/lib.sh
  # resolves to the canonical (under-test) copy. Without this, the harness
  # script falls back to .correctless/scripts/lib.sh which is the previously
  # installed (potentially stale) copy and may diverge from the source under
  # test — masking real failures or producing spurious ones.
  local lib_src="$repo_dir/scripts/lib.sh"
  if [ -f "$lib_src" ]; then
    cp "$lib_src" "$workdir/lib.sh" || true
  fi

  printf '%s\n' "$dst"
}
