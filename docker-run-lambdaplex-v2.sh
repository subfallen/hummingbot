#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 6 ]]; then
  echo "Usage: ./docker-run-lambdaplex-v2.sh \\" >&2
  echo "  <image:tag> \\" >&2
  echo "  <hb_password> \\" >&2
  echo "  <lambdaplex_api_key> \\" >&2
  echo "  <ed25519_private_key_pem_file> \\" >&2
  echo "  <script_py_in_scripts_dir> \\" >&2
  echo "  <script_conf_yml_in_conf_scripts_dir>" >&2
  echo >&2
  echo "Example:" >&2
  echo "  ./docker-run-lambdaplex-v2.sh \\" >&2
  echo "    us-docker.pkg.dev/<project>/<repo>/hummingbot-lambdaplex:0.1.2 \\" >&2
  echo "    abc123 \\" >&2
  echo "    lp_... \\" >&2
  echo "    conf/keys/lambdaplex_private_key.pem \\" >&2
  echo "    v2_with_controllers.py \\" >&2
  echo "    conf_v2_with_controllers.yml" >&2
  exit 2
fi

IMAGE_TAG="$1"
HB_PASSWORD="$2"
LAMBDAPLEX_API_KEY="$3"
PRIVATE_KEY_FILE="$4"
SCRIPT_PY="$5"
SCRIPT_CONF_YML="$6"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! docker info >/dev/null 2>&1; then
  echo "Docker daemon not available. Start Docker Desktop and retry." >&2
  exit 2
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
  -v "${ROOT_DIR}/conf/conf_client.docker.yml:/home/hummingbot/conf/conf_client.yml:ro" \
  -v "${PRIVATE_KEY_FILE}:/tmp/lambdaplex_private_key.pem:ro" \
  -e PASSWORD="${HB_PASSWORD}" \
  -e API_KEY="${LAMBDAPLEX_API_KEY}" \
  "${IMAGE_TAG}" \
  bash -lc 'set -euo pipefail; conda activate hummingbot >/dev/null; export PRIVATE_KEY="$(cat /tmp/lambdaplex_private_key.pem)"; python scripts/plex/auth_setup_lambdaplex.py'

NAME="hummingbot-lambdaplex-v2"
if docker ps -a --format '{{.Names}}' | grep -qx "$NAME"; then
  echo "Container already exists: $NAME" >&2
  echo "Remove it first: docker rm -f $NAME" >&2
  exit 2
fi

echo "2/2 Starting headless Hummingbot container: $NAME"
docker run -d --name "$NAME" \
  -v "${ROOT_DIR}/conf:/home/hummingbot/conf" \
  -v "${ROOT_DIR}/conf/conf_client.docker.yml:/home/hummingbot/conf/conf_client.yml:ro" \
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
