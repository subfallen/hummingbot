#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: ./docker-run-lambdaplex-v2.sh [--rm-image] [--client-conf <file>] [--mount-local-py] \\" >&2
  echo "  <image:tag> \\" >&2
  echo "  <hb_password> \\" >&2
  echo "  <lambdaplex_api_key> \\" >&2
  echo "  <ed25519_private_key_pem_file> \\" >&2
  echo "  <script_py_in_scripts_dir> \\" >&2
  echo "  <script_conf_yml_in_conf_scripts_dir>" >&2
  echo >&2
  echo "Options:" >&2
  echo "  --rm-image  Remove the local copy of <image:tag> before running (default: keep)" >&2
  echo "  --client-conf  Path to a conf_client*.yml file to mount into the container as conf/conf_client.yml" >&2
  echo "               Default: conf/conf_client.docker.local.yml if present, else conf/conf_client.docker.yml" >&2
  echo "  --mount-local-py  Bind-mount select Python sources from this repo into the container (dev workaround)" >&2
  echo >&2
  echo "Example:" >&2
  echo "  ./docker-run-lambdaplex-v2.sh --rm-image \\" >&2
  echo "    us-docker.pkg.dev/<project>/<repo>/hummingbot-lambdaplex:0.1.2 \\" >&2
  echo "    abc123 \\" >&2
  echo "    lp_... \\" >&2
  echo "    conf/keys/lambdaplex_private_key.pem \\" >&2
  echo "    v2_with_controllers.py \\" >&2
  echo "    conf_v2_with_controllers.yml" >&2
}

RM_IMAGE="false"
CLIENT_CONF_OVERRIDE=""
MOUNT_LOCAL_PY="false"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --rm-image|--remove-image)
      RM_IMAGE="true"
      shift
      ;;
    --client-conf)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --client-conf" >&2
        usage
        exit 2
      fi
      CLIENT_CONF_OVERRIDE="$2"
      shift 2
      ;;
    --mount-local-py|--local-py)
      MOUNT_LOCAL_PY="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "Unknown option: $1" >&2
      usage
      exit 2
      ;;
    *)
      break
      ;;
  esac
done

if [[ $# -ne 6 ]]; then
  usage
  exit 2
fi

IMAGE_TAG="$1"
HB_PASSWORD="$2"
LAMBDAPLEX_API_KEY="$3"
PRIVATE_KEY_FILE="$4"
SCRIPT_PY="$5"
SCRIPT_CONF_YML="$6"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAME="hummingbot-lambdaplex-v2"
DEFAULT_CLIENT_CONF="${ROOT_DIR}/conf/conf_client.docker.yml"
LOCAL_CLIENT_CONF="${ROOT_DIR}/conf/conf_client.docker.local.yml"
CLIENT_CONF="${DEFAULT_CLIENT_CONF}"
if [[ -n "${CLIENT_CONF_OVERRIDE}" ]]; then
  if [[ "${CLIENT_CONF_OVERRIDE}" != /* ]]; then
    CLIENT_CONF="${ROOT_DIR}/${CLIENT_CONF_OVERRIDE}"
  else
    CLIENT_CONF="${CLIENT_CONF_OVERRIDE}"
  fi
elif [[ -f "${LOCAL_CLIENT_CONF}" ]]; then
  CLIENT_CONF="${LOCAL_CLIENT_CONF}"
fi
if [[ ! -f "${CLIENT_CONF}" ]]; then
  echo "Client config not found: ${CLIENT_CONF}" >&2
  exit 2
fi

if ! docker info >/dev/null 2>&1; then
  echo "Docker daemon not available. Start Docker Desktop and retry." >&2
  exit 2
fi

if docker ps -a --format '{{.Names}}' | grep -qx "$NAME"; then
  echo "Removing existing container: $NAME"
  if ! docker rm -f "$NAME" >/dev/null; then
    echo "Failed to remove existing container: $NAME" >&2
    exit 2
  fi
fi

if [[ "$RM_IMAGE" == "true" ]] && docker image inspect "$IMAGE_TAG" >/dev/null 2>&1; then
  echo "Removing existing image: $IMAGE_TAG"
  if ! docker image rm -f "$IMAGE_TAG" >/dev/null 2>&1; then
    echo "Warning: failed to remove image (will continue): $IMAGE_TAG" >&2
  fi
fi

if [[ "$PRIVATE_KEY_FILE" != /* ]]; then
  PRIVATE_KEY_FILE="${ROOT_DIR}/${PRIVATE_KEY_FILE}"
fi
if [[ ! -f "$PRIVATE_KEY_FILE" ]]; then
  echo "Private key file not found: $PRIVATE_KEY_FILE" >&2
  exit 2
fi

if [[ ! -f "${ROOT_DIR}/scripts/${SCRIPT_PY}" ]]; then
  echo "Script not found on host (typo check): ${ROOT_DIR}/scripts/${SCRIPT_PY}" >&2
  exit 2
fi
if [[ ! -f "${ROOT_DIR}/conf/scripts/${SCRIPT_CONF_YML}" ]]; then
  echo "Script config not found on host (typo check): ${ROOT_DIR}/conf/scripts/${SCRIPT_CONF_YML}" >&2
  exit 2
fi

if [[ ! -f "${ROOT_DIR}/conf/conf_client.docker.yml" ]]; then
  echo "Missing ${ROOT_DIR}/conf/conf_client.docker.yml" >&2
  exit 2
fi

mkdir -p "${ROOT_DIR}/conf/connectors" "${ROOT_DIR}/logs" "${ROOT_DIR}/data"

echo "1/2 Writing encrypted Lambdaplex credentials to conf/connectors/lambdaplex.yml"
docker run --rm \
  -v "${ROOT_DIR}/conf:/home/hummingbot/conf" \
  -v "${CLIENT_CONF}:/home/hummingbot/conf/conf_client.yml:ro" \
  -v "${PRIVATE_KEY_FILE}:/tmp/lambdaplex_private_key.pem:ro" \
  -e PASSWORD="${HB_PASSWORD}" \
  -e API_KEY="${LAMBDAPLEX_API_KEY}" \
  "${IMAGE_TAG}" \
  bash -lc 'set -euo pipefail; conda activate hummingbot >/dev/null; export PYTHONPATH="/home/hummingbot${PYTHONPATH:+:$PYTHONPATH}"; export PRIVATE_KEY="$(cat /tmp/lambdaplex_private_key.pem)"; python scripts/plex/auth_setup_lambdaplex.py'

echo "2/2 Starting headless Hummingbot container: $NAME"
docker run -d --name "$NAME" \
  -v "${ROOT_DIR}/conf:/home/hummingbot/conf" \
  -v "${CLIENT_CONF}:/home/hummingbot/conf/conf_client.yml:ro" \
  -v "${ROOT_DIR}/logs:/home/hummingbot/logs" \
  -v "${ROOT_DIR}/data:/home/hummingbot/data" \
  -e CONFIG_PASSWORD="${HB_PASSWORD}" \
  -e CONFIG_FILE_NAME="${SCRIPT_PY}" \
  -e SCRIPT_CONFIG="${SCRIPT_CONF_YML}" \
  -e HEADLESS_MODE="true" \
  -e LAMBDAPLEX_REST_URL="http://host.docker.internal:9393/api/" \
  -e LAMBDAPLEX_WSS_URL="ws://host.docker.internal:9393/api/{}/ws" \
  -e LAMBDAPLEX_API_VERSION="v1" \
  "${IMAGE_TAG}" >/dev/null

echo "Started: $NAME"
echo "Tail logs: docker logs -f $NAME"
