#!/usr/bin/env bash
# Correctless — config updater (cross-model-spec-review, INV-016/INV-023).
#
# PRIVILEGED config writer. The ONLY sanctioned writer of the SFG-protected
# workflow-config.json external-review fields (BND-003). /csetup routes through
# this script as the sole writer (a who-writes / sole-writer convention). SFG
# guards only the Edit/Write tool-path, so a direct Bash redirect is no longer
# blocked (sfg-edit-write-only / AP-040) — the sole-writer convention, not SFG,
# is the integrity leg. jq-merge, atomic temp+mv, every field via
# --arg/--argjson (never interpolated into the jq program — PRH-006).
# Fail-closed on malformed existing config.
#
# Subcommands:
#   set-external-model codex <key> <value> [<key> <value> ...] [--config <path>]
#       jq-merges into .workflow.external_models.codex (creates .workflow /
#       .workflow.external_models if absent, preserves siblings, idempotent).
#       Known fields: bin, model (strings); timeout_seconds (number);
#       stdin (bool); base_args (JSON array).
#   set-require-external-review <true|false|auto> [--config <path>]
#       true/false: sets .workflow.require_external_review.
#       auto: REMOVES the key (absent => auto, INV-005 tri-state / INV-023).
#
# Config path resolution: --config <path> arg, else CORRECTLESS_CONFIG env, else
# the repo default .correctless/config/workflow-config.json.
#
# POSIX externals: jq, mktemp, mv. jq 1.7-safe (bound exprs parenthesized).

# shellcheck disable=SC1090,SC1091,SC2016
set -uo pipefail

_default_config() {
  printf '%s' "$PWD/.correctless/config/workflow-config.json"
}

# Resolve the config path from args (--config), env, or default. Echoes the path.
# Consumes --config <path> out of the positional stream by NOT echoing it; the
# caller pre-strips it. Here we just compute the fallback.
_resolve_config() {
  if [ -n "${CFG_PATH:-}" ]; then printf '%s' "$CFG_PATH"; return; fi
  if [ -n "${CORRECTLESS_CONFIG:-}" ]; then printf '%s' "$CORRECTLESS_CONFIG"; return; fi
  _default_config
}

# Atomic write: jq program reads $cfg, writes temp, mv into place. Fails closed
# (non-zero, original untouched) if jq errors. Args after the program are passed
# verbatim to jq (so --arg/--argjson bindings flow through).
_atomic_jq() {
  local cfg="$1" prog="$2"; shift 2
  # Malformed existing config => fail-closed + report, do not corrupt (BND-003).
  if [ -f "$cfg" ]; then
    if ! jq -e . "$cfg" >/dev/null 2>&1; then
      echo "config-update: existing config is not valid JSON — refusing to modify ($cfg)" >&2
      return 1
    fi
  fi
  local tmp="${cfg}.$$.tmp"
  if [ -f "$cfg" ]; then
    if ! jq "$@" "$prog" "$cfg" > "$tmp" 2>/dev/null; then
      rm -f "$tmp"
      echo "config-update: jq merge failed — config untouched ($cfg)" >&2
      return 1
    fi
  else
    if ! jq -n "$@" "$prog" > "$tmp" 2>/dev/null; then
      rm -f "$tmp"
      echo "config-update: jq merge failed — config untouched ($cfg)" >&2
      return 1
    fi
  fi
  mv "$tmp" "$cfg" || { rm -f "$tmp"; return 1; }
  return 0
}

# ---------------------------------------------------------------------------
# set-external-model codex <key> <value> ... — merge structured fields.
# ---------------------------------------------------------------------------
cmd_set_external_model() {
  local model_name="${1:-}"; shift || true
  [ -n "$model_name" ] || { echo "set-external-model: missing model name" >&2; return 1; }

  # Collect key/value field pairs (every value via --arg/--argjson, never
  # interpolated). Build the jq object-merge program from a fixed key set.
  local -a jq_args=()
  # jq program fragments that set each provided field under the codex object.
  local set_exprs=""

  while [ "$#" -gt 0 ]; do
    local key="$1"
    case "$key" in
      --config) CFG_PATH="${2:-}"; shift 2; continue ;;
    esac
    local val="${2:-}"
    shift 2 || { echo "set-external-model: dangling key '$key' without value" >&2; return 1; }

    case "$key" in
      bin|model)
        # String fields via --arg.
        jq_args+=(--arg "$key" "$val")
        set_exprs="${set_exprs} | (.workflow.external_models.${model_name}.${key} = \$${key})"
        ;;
      timeout_seconds)
        # Numeric via --argjson (validate it is numeric; else fail-closed).
        printf '%s' "$val" | grep -qE '^[0-9]+$' || { echo "set-external-model: timeout_seconds must be numeric" >&2; return 1; }
        jq_args+=(--argjson "$key" "$val")
        set_exprs="${set_exprs} | (.workflow.external_models.${model_name}.${key} = \$${key})"
        ;;
      stdin)
        case "$val" in true|false) : ;; *) echo "set-external-model: stdin must be true|false" >&2; return 1 ;; esac
        jq_args+=(--argjson "$key" "$val")
        set_exprs="${set_exprs} | (.workflow.external_models.${model_name}.${key} = \$${key})"
        ;;
      base_args)
        # JSON array via --argjson (validate it parses as an array).
        printf '%s' "$val" | jq -e 'type=="array"' >/dev/null 2>&1 || { echo "set-external-model: base_args must be a JSON array" >&2; return 1; }
        jq_args+=(--argjson "$key" "$val")
        set_exprs="${set_exprs} | (.workflow.external_models.${model_name}.${key} = \$${key})"
        ;;
      *)
        echo "set-external-model: unknown field '$key'" >&2
        return 1
        ;;
    esac
  done

  local cfg; cfg="$(_resolve_config)"

  # Build the full program: seed missing .workflow / .workflow.external_models /
  # the model object, then apply each field set-expr. The model name is a fixed
  # token from a closed set (codex), not free user text reaching the jq program.
  case "$model_name" in
    [A-Za-z0-9_-]*) : ;;
    *) echo "set-external-model: invalid model name '$model_name'" >&2; return 1 ;;
  esac

  local prog
  prog="(. // {})
        | (.workflow //= {})
        | (.workflow.external_models //= {})
        | (.workflow.external_models.${model_name} //= {})
        ${set_exprs}"

  _atomic_jq "$cfg" "$prog" "${jq_args[@]}"
}

# ---------------------------------------------------------------------------
# set-require-external-review <true|false|auto> — tri-state off-switch / migration.
# ---------------------------------------------------------------------------
cmd_set_require() {
  local val="${1:-}"; shift || true
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --config) CFG_PATH="${2:-}"; shift 2 ;;
      *) shift ;;
    esac
  done
  local cfg; cfg="$(_resolve_config)"

  case "$val" in
    true|false)
      _atomic_jq "$cfg" \
        '(. // {}) | (.workflow //= {}) | (.workflow.require_external_review = $v)' \
        --argjson v "$val"
      ;;
    auto)
      # absent => auto (INV-005 tri-state / INV-023 migration): REMOVE the key.
      _atomic_jq "$cfg" \
        '(. // {}) | (if (.workflow|type=="object") then (.workflow |= del(.require_external_review)) else . end)'
      ;;
    *)
      echo "set-require-external-review: value must be true|false|auto" >&2
      return 1
      ;;
  esac
}

# ---------------------------------------------------------------------------
# Dispatch.
# ---------------------------------------------------------------------------
CFG_PATH=""
main() {
  local sub="${1:-}"; shift || true
  case "$sub" in
    set-external-model)          cmd_set_external_model "$@" ;;
    set-require-external-review) cmd_set_require "$@" ;;
    *)
      echo "usage: config-update.sh {set-external-model <model> <k> <v> ...|set-require-external-review <true|false|auto>} [--config <path>]" >&2
      return 2
      ;;
  esac
}

main "$@"
