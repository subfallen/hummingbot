#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/plex/run_docker_lambdaplex.sh <command> [options]

Commands:
  up             Build (optional) and start EMQX + Hummingbot (detached by default)
  down           Stop and remove containers
  logs           Tail logs (default: hummingbot)
  ps             Show container status
  exec           Exec into a running container (default: hummingbot)
  auth-setup     Run scripts/plex/auth_setup_lambdaplex.py inside the container to (re)encrypt credentials

Options (common):
  -f, --compose-file     Compose file to use (default: docker-compose.mac.yml if present, else docker-compose.yml)
  --build                Build image before running the command
  -h, --help             Show this help

Options (Hummingbot quickstart, used by `up`):
  -p, --password         Hummingbot config password (sets CONFIG_PASSWORD)
  --script               Script name in /home/hummingbot/scripts (sets CONFIG_FILE_NAME; default: v2_with_controllers.py)
  --script-conf          Script config in conf/scripts (sets SCRIPT_CONFIG; default: conf_v2_with_controllers.yml)
  --headless             true|false (sets HEADLESS_MODE; default: true)

Options (Lambdaplex dev env overrides, used by `up`):
  --rest-url             Sets LAMBDAPLEX_REST_URL (e.g. http://host.docker.internal:9393/api/)
  --wss-url              Sets LAMBDAPLEX_WSS_URL (e.g. ws://host.docker.internal:9393/api/{}/ws)
  --api-version          Sets LAMBDAPLEX_API_VERSION (default: v1)

Options (used by `auth-setup`):
  -k, --api-key           Lambdaplex API key (sets API_KEY)
  --private-key           Lambdaplex private key (PEM or base64 PKCS#8 Ed25519) (sets PRIVATE_KEY)
  --private-key-file      Path to private key file (PEM or base64; newlines will be escaped as \n)

Examples:
  # Start dockerized bot against local dev Lambdaplex running on your Mac
  scripts/plex/run_docker_lambdaplex.sh up \
    -p 'abc123' \
    --rest-url 'http://host.docker.internal:9393/api/' \
    --wss-url 'ws://host.docker.internal:9393/api/{}/ws'

  # Re-encrypt connector secrets (writes conf/connectors/lambdaplex.yml)
  scripts/plex/run_docker_lambdaplex.sh auth-setup \
    -p 'abc123' -k 'lp_...' --private-key-file conf/keys/lambdaplex_private_key.pem
USAGE
}

die() { echo "$*" >&2; exit 2; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

default_compose_file() {
  if [[ -f "${ROOT_DIR}/docker-compose.mac.yml" ]]; then
    echo "${ROOT_DIR}/docker-compose.mac.yml"
  else
    echo "${ROOT_DIR}/docker-compose.yml"
  fi
}

escape_key_file_newlines() {
  # Turn a multiline PEM into a single line with literal "\n" so it can be passed safely via env vars.
  local key_path="$1"
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$key_path" <<'PY'
from pathlib import Path
import sys
data = Path(sys.argv[1]).read_text()
data = data.replace("\r\n", "\n").replace("\r", "\n").rstrip("\n")
print(data.replace("\n", "\\n"))
PY
    return 0
  fi
  if command -v python >/dev/null 2>&1; then
    python - "$key_path" <<'PY'
from pathlib import Path
import sys
data = Path(sys.argv[1]).read_text()
data = data.replace("\r\n", "\n").replace("\r", "\n").rstrip("\n")
print(data.replace("\n", "\\n"))
PY
    return 0
  fi
  # POSIX-ish fallback
  awk '{printf "%s\\n", $0}' "$key_path" | sed 's/\\n$//'
}

command="${1:-}"
if [[ -z "$command" ]]; then
  usage
  exit 2
fi
if [[ "$command" == "-h" || "$command" == "--help" || "$command" == "help" ]]; then
  usage
  exit 0
fi
shift

COMPOSE_FILE="$(default_compose_file)"
BUILD="false"

# quickstart defaults
CONFIG_PASSWORD="${CONFIG_PASSWORD:-}"
CONFIG_FILE_NAME="${CONFIG_FILE_NAME:-v2_with_controllers.py}"
SCRIPT_CONFIG="${SCRIPT_CONFIG:-conf_v2_with_controllers.yml}"
HEADLESS_MODE="${HEADLESS_MODE:-true}"

# lambdaplex endpoint overrides (optional)
LAMBDAPLEX_REST_URL="${LAMBDAPLEX_REST_URL:-}"
LAMBDAPLEX_WSS_URL="${LAMBDAPLEX_WSS_URL:-}"
LAMBDAPLEX_API_VERSION="${LAMBDAPLEX_API_VERSION:-v1}"

# auth-setup args
API_KEY="${API_KEY:-}"
PRIVATE_KEY="${PRIVATE_KEY:-}"

LOGS_SERVICE="hummingbot"
EXEC_SERVICE="hummingbot"
EXEC_CMD=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -f|--compose-file)
      COMPOSE_FILE="$2"; shift 2 ;;
    --build)
      BUILD="true"; shift ;;
    -p|--password)
      CONFIG_PASSWORD="$2"
      shift 2 ;;
    --script|--config-file-name)
      CONFIG_FILE_NAME="$2"; shift 2 ;;
    --script-conf|--script-config)
      SCRIPT_CONFIG="$2"; shift 2 ;;
    --headless)
      HEADLESS_MODE="$2"; shift 2 ;;
    --rest-url)
      LAMBDAPLEX_REST_URL="$2"; shift 2 ;;
    --wss-url)
      LAMBDAPLEX_WSS_URL="$2"; shift 2 ;;
    --api-version)
      LAMBDAPLEX_API_VERSION="$2"; shift 2 ;;
    -k|--api-key)
      API_KEY="$2"; shift 2 ;;
    --private-key)
      PRIVATE_KEY="$2"; shift 2 ;;
    --private-key-file)
      key_path="$2"
      if [[ "$key_path" != /* ]]; then
        key_path="${ROOT_DIR}/${key_path}"
      fi
      [[ -f "$key_path" ]] || die "Private key file not found: $key_path"
      PRIVATE_KEY="$(escape_key_file_newlines "$key_path")"
      shift 2 ;;
    --service)
      LOGS_SERVICE="$2"
      EXEC_SERVICE="$2"
      shift 2 ;;
    --)
      shift
      EXEC_CMD=("$@")
      break ;;
    -h|--help)
      usage; exit 0 ;;
    -*)
      die "Unknown option: $1" ;;
    *)
      # For `exec`, allow: scripts/... exec -- <cmd...>
      EXEC_CMD+=("$1"); shift ;;
  esac
done

if [[ "$COMPOSE_FILE" != /* ]]; then
  COMPOSE_FILE="${ROOT_DIR}/${COMPOSE_FILE}"
fi
[[ -f "$COMPOSE_FILE" ]] || die "Compose file not found: $COMPOSE_FILE"

dc=(docker compose -f "$COMPOSE_FILE")

if ! docker info >/dev/null 2>&1; then
  die "Docker daemon not available. Start Docker Desktop (macOS) or the docker service (Linux) and retry."
fi

case "$command" in
  up)
    [[ -n "$CONFIG_PASSWORD" ]] || die "Missing -p/--password (CONFIG_PASSWORD)."
    if [[ "$BUILD" == "true" ]]; then
      CONFIG_PASSWORD="$CONFIG_PASSWORD" \
      CONFIG_FILE_NAME="$CONFIG_FILE_NAME" \
      SCRIPT_CONFIG="$SCRIPT_CONFIG" \
      HEADLESS_MODE="$HEADLESS_MODE" \
      LAMBDAPLEX_REST_URL="$LAMBDAPLEX_REST_URL" \
      LAMBDAPLEX_WSS_URL="$LAMBDAPLEX_WSS_URL" \
      LAMBDAPLEX_API_VERSION="$LAMBDAPLEX_API_VERSION" \
        "${dc[@]}" up --build -d
    else
      CONFIG_PASSWORD="$CONFIG_PASSWORD" \
      CONFIG_FILE_NAME="$CONFIG_FILE_NAME" \
      SCRIPT_CONFIG="$SCRIPT_CONFIG" \
      HEADLESS_MODE="$HEADLESS_MODE" \
      LAMBDAPLEX_REST_URL="$LAMBDAPLEX_REST_URL" \
      LAMBDAPLEX_WSS_URL="$LAMBDAPLEX_WSS_URL" \
      LAMBDAPLEX_API_VERSION="$LAMBDAPLEX_API_VERSION" \
        "${dc[@]}" up -d
    fi
    ;;

  down)
    "${dc[@]}" down
    ;;

  logs)
    "${dc[@]}" logs -f "$LOGS_SERVICE"
    ;;

  ps)
    "${dc[@]}" ps
    ;;

  exec)
    if [[ ${#EXEC_CMD[@]} -eq 0 ]]; then
      EXEC_CMD=("bash")
    fi
    "${dc[@]}" exec "$EXEC_SERVICE" "${EXEC_CMD[@]}"
    ;;

  auth-setup)
    [[ -n "$CONFIG_PASSWORD" ]] || die "Missing -p/--password."
    [[ -n "$API_KEY" ]] || die "Missing -k/--api-key (API_KEY)."
    [[ -n "$PRIVATE_KEY" ]] || die "Missing --private-key or --private-key-file (PRIVATE_KEY)."

    run_args=(run --rm --no-deps)
    if [[ "$BUILD" == "true" ]]; then
      run_args+=(--build)
    fi
    "${dc[@]}" "${run_args[@]}" \
      -e PASSWORD="$CONFIG_PASSWORD" \
      -e API_KEY="$API_KEY" \
      -e PRIVATE_KEY="$PRIVATE_KEY" \
      hummingbot bash -lc "conda activate hummingbot && python scripts/plex/auth_setup_lambdaplex.py"
    ;;

  *)
    die "Unknown command: $command"
    ;;
esac
