#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${STACK_ENV_FILE:-$SCRIPT_DIR/.env}"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing env file: $ENV_FILE" >&2
  echo "Copy .env.example to .env before running the stack." >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

export OPENCLAW_STATE_DIR="${OPENCLAW_STATE_DIR:-$SCRIPT_DIR/state/openclaw}"
export OPENCLAW_WORKSPACE_DIR="${OPENCLAW_WORKSPACE_DIR:-$SCRIPT_DIR/workspace}"
export RUNTIME_STATE_DIR="${RUNTIME_STATE_DIR:-$SCRIPT_DIR/state/runtime}"
export OPENCLAW_CONFIG_TEMPLATE="${OPENCLAW_CONFIG_TEMPLATE:-$SCRIPT_DIR/openclaw.json}"

mkdir -p \
  "$OPENCLAW_STATE_DIR" \
  "$OPENCLAW_WORKSPACE_DIR" \
  "$RUNTIME_STATE_DIR"

if [[ -z "${CLAWCONTROL_RUNTIME_NPM_SPEC:-}" ]]; then
  echo "CLAWCONTROL_RUNTIME_NPM_SPEC must be set in $ENV_FILE" >&2
  exit 1
fi

seed_openclaw_config() {
  if [[ ! -f "$OPENCLAW_CONFIG_TEMPLATE" ]]; then
    return 0
  fi

  local config_path="$OPENCLAW_STATE_DIR/openclaw.json"
  if [[ -f "$config_path" ]]; then
    return 0
  fi

  OPENCLAW_CONFIG_PATH="$config_path" node -e '
    const fs = require("fs");
    const templatePath = process.env.OPENCLAW_CONFIG_TEMPLATE;
    const outputPath = process.env.OPENCLAW_CONFIG_PATH;
    const replacements = {
      OPENCLAW_GATEWAY_TOKEN: process.env.OPENCLAW_GATEWAY_TOKEN || "",
      OPENCLAW_GATEWAY_PORT: process.env.OPENCLAW_GATEWAY_PORT || "18799",
      OPENCLAW_BROWSER_UI_PORT: process.env.OPENCLAW_BROWSER_UI_PORT || "18801",
    };

    let output = fs.readFileSync(templatePath, "utf8");
    for (const [key, value] of Object.entries(replacements)) {
      output = output.replaceAll("${" + key + "}", value);
    }
    fs.writeFileSync(outputPath, output);
  '
}

compose() {
  docker compose --env-file "$ENV_FILE" -f "$SCRIPT_DIR/docker-compose.yml" "$@"
}

pull_openclaw_image() {
  docker pull "${OPENCLAW_IMAGE:?OPENCLAW_IMAGE must be set}"
}

build_runtime() {
  compose build --pull runtime
}

ensure_runtime_built() {
  if ! docker image inspect "${CLAWCONTROL_RUNTIME_IMAGE:-clawcontrol-runtime:docker-example}" >/dev/null 2>&1; then
    build_runtime
  fi
}

start_stack() {
  local force_recreate="${1:-0}"
  if [[ "$force_recreate" -eq 1 ]]; then
    compose up -d --force-recreate openclaw-gateway runtime
  else
    compose up -d openclaw-gateway runtime
  fi
}

shell_into() {
  local service="$1"
  if compose exec "$service" bash >/dev/null 2>&1; then
    compose exec "$service" bash
  else
    compose exec "$service" sh
  fi
}

approve_pending_devices() {
  local pending_json
  pending_json="$(
    compose exec -T openclaw-gateway \
      node openclaw.mjs devices list \
      --json
  )"

  local request_ids=()
  local request_id
  while IFS= read -r request_id; do
    [[ -n "$request_id" ]] || continue
    request_ids+=("$request_id")
  done < <(
    printf '%s' "$pending_json" | node -e '
      const fs = require("fs");
      const raw = fs.readFileSync(0, "utf8");
      const parsed = JSON.parse(raw);
      const pending = Array.isArray(parsed.pending) ? parsed.pending : [];
      for (const entry of pending) {
        if (typeof entry?.requestId === "string" && entry.requestId) {
          console.log(entry.requestId);
        }
      }
    '
  )

  if [[ "${#request_ids[@]}" -eq 0 ]]; then
    echo "No pending OpenClaw devices to approve."
    return 0
  fi

  for request_id in "${request_ids[@]}"; do
    echo "Approving pending device request: $request_id"
    compose exec -T openclaw-gateway \
      node openclaw.mjs devices approve "$request_id" \
      --json
  done
}

usage() {
  cat <<'EOF'
Usage: ./stack.sh <command> [args]

Commands:
  build-runtime          Build the runtime image from the published npm package
  pull-openclaw          Pull the configured OpenClaw image tag or digest
  up [--build]           Start the OpenClaw gateway and runtime services
  down                   Stop the stack
  restart [--build]      Restart the stack
  ps                     Show container status
  logs [service]         Follow logs for all services or one service
  shell-openclaw         Open a shell in the OpenClaw gateway container
  shell-runtime          Open a shell in the runtime container
  approve-pending        Approve all pending OpenClaw device requests
  oc <args...>           Run an OpenClaw CLI command in the helper container
  onboard [args...]      Shortcut for: oc onboard ...
  pair <PAIRING_CODE>    Pair the runtime using the runtime container
  runtime <args...>      Run arbitrary runtime CLI args in a one-off container
  config                 Render the resolved docker compose config

Examples:
  ./stack.sh up --build
  ./stack.sh onboard
  ./stack.sh pair ABCD-1234 --name "Docker Runtime"
  ./stack.sh approve-pending
  ./stack.sh runtime runtime status
EOF
}

seed_openclaw_config

command="${1:-}"
if [[ -z "$command" ]]; then
  usage
  exit 1
fi
shift || true

case "$command" in
  build-runtime)
    build_runtime
    ;;
  pull-openclaw)
    pull_openclaw_image
    ;;
  up)
    force_recreate=0
    if [[ "${1:-}" == "--build" ]]; then
      shift
      pull_openclaw_image
      build_runtime
      force_recreate=1
    else
      ensure_runtime_built
    fi
    start_stack "$force_recreate"
    ;;
  down)
    compose down
    ;;
  restart)
    rebuild=0
    if [[ "${1:-}" == "--build" ]]; then
      shift
      rebuild=1
    fi
    compose down
    if [[ "$rebuild" -eq 1 ]]; then
      pull_openclaw_image
      build_runtime
    else
      ensure_runtime_built
    fi
    start_stack 0
    ;;
  ps)
    compose ps
    ;;
  logs)
    if [[ $# -gt 0 ]]; then
      compose logs -f "$@"
    else
      compose logs -f
    fi
    ;;
  shell-openclaw)
    shell_into openclaw-gateway
    ;;
  shell-runtime)
    shell_into runtime
    ;;
  approve-pending)
    approve_pending_devices
    ;;
  oc)
    compose run --rm openclaw-cli "$@"
    ;;
  onboard)
    compose run --rm openclaw-cli onboard "$@"
    ;;
  pair)
    compose run --rm --no-deps runtime runtime pair "$@"
    ;;
  runtime)
    compose run --rm --no-deps runtime "$@"
    ;;
  config)
    compose config
    ;;
  *)
    usage
    exit 1
    ;;
esac
