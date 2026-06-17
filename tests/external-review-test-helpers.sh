#!/usr/bin/env bash
# Correctless — Shared test helper for cross-model-spec-review (INV-018).
# STUB:TDD — this is a TEST helper (fixtures + fake-codex seam), not production
# implementation logic. The marker is present only to satisfy the RED-phase
# workflow gate for a tests/ file whose basename does not match the test*.sh
# auto-run glob. No production behavior lives here.
#
# Provides make_fake_codex: generates a deterministic, offline `codex`
# executable so all behavioral tests for scripts/external-review-run.sh run
# WITHOUT a network call. The fake binary's basename is literally `codex` so the
# producer's INV-017 realpath/charset validation accepts it.
#
# The fake codex:
#   - reads (and discards / captures) stdin (the spec body — INV-003/INV-012)
#   - writes a caller-supplied JSON to the path following --output-last-message
#   - emits a caller-supplied JSONL stream to stdout when --json is present
#   - echoes its full argv to a caller-supplied capture file (INV-015 seam)
#   - exits with a caller-supplied code (INV-006 failure-mode replay)
#
# Deterministic run_id seams (RS-008): RNG (CORRECTLESS_TEST_RUNID_HEX) and clock
# (CORRECTLESS_TEST_RUNID_CLOCK) injection points are documented here and consumed
# by the producer when present, so collision-reroll tests are reproducible.
#
# POSIX-portable; Bash 4+ permitted. Sourced by the external-review test files.

# shellcheck disable=SC2034,SC1090,SC1091

# make_fake_codex <dir> <output-json-file|OMIT> <jsonl-file|/dev/null> <exit-code> [argv-capture] [stdin-capture]
# Echoes the absolute path to the generated `codex` binary on stdout.
make_fake_codex() {
  local dir="$1" out_src="$2" jsonl_src="$3" exit_code="$4"
  local argv_capture="${5:-/dev/null}" stdin_capture="${6:-/dev/null}"
  mkdir -p "$dir"
  local bin="$dir/codex"
  cat > "$bin" <<EOF
#!/usr/bin/env bash
# Deterministic offline fake codex (test seam, INV-018). No network.
set -u

# --- INV-015 argv capture seam -------------------------------------------
printf '%s\n' "\$@" >> "$argv_capture" 2>/dev/null || true

# --- locate --output-last-message target ---------------------------------
_msg_target=""
_has_json=0
_prev=""
for _a in "\$@"; do
  case "\$_prev" in
    --output-last-message) _msg_target="\$_a" ;;
  esac
  [ "\$_a" = "--json" ] && _has_json=1
  _prev="\$_a"
done

# --- consume / capture stdin (the spec body) -----------------------------
if [ "$stdin_capture" != "/dev/null" ]; then
  cat > "$stdin_capture" 2>/dev/null || true
else
  cat >/dev/null 2>&1 || true
fi

# --- write the schema deliverable to the message file --------------------
if [ -n "\$_msg_target" ] && [ "$out_src" != "OMIT" ]; then
  cat "$out_src" > "\$_msg_target" 2>/dev/null || true
fi

# --- emit the --json usage stream on stdout ------------------------------
if [ "\$_has_json" -eq 1 ] && [ "$jsonl_src" != "/dev/null" ]; then
  cat "$jsonl_src" 2>/dev/null || true
fi

exit $exit_code
EOF
  chmod +x "$bin"
  printf '%s' "$bin"
}

# write_codex_config <config-path> <bin>
# Seeds a workflow-config.json with a structured external_models.codex entry
# whose bin points at the fake. base_args is the producer-expected safe set.
write_codex_config() {
  local cfg="$1" bin="$2"
  mkdir -p "$(dirname "$cfg")"
  jq -n --arg bin "$bin" '{
    workflow: {
      intensity: "high",
      external_models: {
        codex: {
          bin: $bin,
          base_args: ["exec","--sandbox","read-only","--ephemeral","--json"],
          model: "gpt-5.5-codex",
          timeout_seconds: 120,
          stdin: true
        }
      }
    }
  }' > "$cfg"
}

# Real codex 0.139.0 fixture paths.
# Source: tests/fixtures/external-review/codex-output-last-message.json
real_codex_output_fixture() {
  printf '%s' "$REPO_DIR/tests/fixtures/external-review/codex-output-last-message.json"
}

# Source: tests/fixtures/external-review/codex-json-stream.jsonl
real_codex_jsonl_fixture() {
  printf '%s' "$REPO_DIR/tests/fixtures/external-review/codex-json-stream.jsonl"
}
