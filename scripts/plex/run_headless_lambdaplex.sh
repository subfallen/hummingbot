#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/plex/run_headless_lambdaplex.sh [options]
  scripts/plex/run_headless_lambdaplex.sh PASSWORD STRATEGY_FILE

Required (via flags, env vars, or positional args):
  -p, --password         Hummingbot config password (env: PASSWORD)
  -s, --strategy         Strategy config filename (env: STRATEGY_FILE)

Optional:
  --python               Python executable to use (default: python)
  --mqtt-host            Override MQTT host for preflight (env: MQTT_HOST)
  --mqtt-port            Override MQTT port for preflight (env: MQTT_PORT)
  --instance-id          Override Hummingbot instance_id (env: HB_INSTANCE_ID)
  --rest-url             Override Lambdaplex REST base URL (env: LAMBDAPLEX_REST_URL)
  --wss-url              Override Lambdaplex WS base URL (env: LAMBDAPLEX_WSS_URL)
  --rate-oracle          Override rate oracle source (default: coin_gecko)
  --reset-db             Delete the strategy DB before starting
  -h, --help             Show this help
Notes:
  Assumes scripts/plex/auth_setup_lambdaplex.py has already been run.
  MQTT preflight behavior can be controlled via MQTT_PREFLIGHT=warn|fail|skip (default: warn).

Examples:
  PASSWORD=... STRATEGY_FILE=pure_mm.yml \
    scripts/plex/run_headless_lambdaplex.sh

  scripts/plex/run_headless_lambdaplex.sh "$PASSWORD" pure_mm.yml

  scripts/plex/run_headless_lambdaplex.sh \
    -p "$PASSWORD" \
    -s pure_mm.yml
USAGE
}

PYTHON_BIN="python"
PASSWORD="${PASSWORD:-}"
STRATEGY_FILE="${STRATEGY_FILE:-}"
MQTT_PREFLIGHT="${MQTT_PREFLIGHT:-warn}"
MQTT_HOST_OVERRIDE=""
MQTT_PORT_OVERRIDE=""
HB_INSTANCE_ID_OVERRIDE=""
LAMBDAPLEX_REST_URL_OVERRIDE=""
LAMBDAPLEX_WSS_URL_OVERRIDE=""
RATE_ORACLE_OVERRIDE="${RATE_ORACLE_OVERRIDE:-coin_gecko}"
RESET_DB="false"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

POSITIONAL=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--password)
      PASSWORD="$2"; shift 2 ;;
    -s|--strategy|--config-file-name)
      STRATEGY_FILE="$2"; shift 2 ;;
    --python)
      PYTHON_BIN="$2"; shift 2 ;;
    --mqtt-host)
      MQTT_HOST_OVERRIDE="$2"; shift 2 ;;
    --mqtt-port)
      MQTT_PORT_OVERRIDE="$2"; shift 2 ;;
    --instance-id)
      HB_INSTANCE_ID_OVERRIDE="$2"; shift 2 ;;
    --rest-url)
      LAMBDAPLEX_REST_URL_OVERRIDE="$2"; shift 2 ;;
    --wss-url)
      LAMBDAPLEX_WSS_URL_OVERRIDE="$2"; shift 2 ;;
    --rate-oracle)
      RATE_ORACLE_OVERRIDE="$2"; shift 2 ;;
    --reset-db)
      RESET_DB="true"; shift ;;
    -h|--help)
      usage; exit 0 ;;
    --)
      shift; POSITIONAL+=("$@"); break ;;
    -*)
      echo "Unknown option: $1" >&2
      usage
      exit 2 ;;
    *)
      POSITIONAL+=("$1"); shift ;;
  esac
 done

# Fill missing values from positional args if provided
if [[ ${#POSITIONAL[@]} -gt 0 ]]; then
  if [[ -z "$PASSWORD" && ${#POSITIONAL[@]} -ge 1 ]]; then
    PASSWORD="${POSITIONAL[0]}"
  fi
  if [[ -z "$STRATEGY_FILE" && ${#POSITIONAL[@]} -ge 2 ]]; then
    STRATEGY_FILE="${POSITIONAL[1]}"
  fi
  if [[ ${#POSITIONAL[@]} -gt 2 ]]; then
    echo "Too many positional arguments." >&2
    usage
    exit 2
  fi
fi

if [[ -z "$PASSWORD" ]]; then
  echo "Missing PASSWORD (use -p/--password or env PASSWORD)" >&2
  exit 2
fi
if [[ -z "$STRATEGY_FILE" ]]; then
  echo "Missing STRATEGY_FILE (use -s/--strategy or env STRATEGY_FILE)" >&2
  exit 2
fi

if [[ "$RESET_DB" == "true" ]]; then
  db_base="${STRATEGY_FILE}"
  db_base="${db_base%.yml}"
  db_base="${db_base%.py}"
  db_path="$ROOT_DIR/data/${db_base}.sqlite"
  rm -f "$db_path" "$db_path-wal" "$db_path-shm"
fi

cd "$ROOT_DIR"

set +e
read -r mqtt_host mqtt_port hb_instance_id < <(
  HB_MQTT_HOST_OVERRIDE="$MQTT_HOST_OVERRIDE" \
  HB_MQTT_PORT_OVERRIDE="$MQTT_PORT_OVERRIDE" \
  HB_INSTANCE_ID_OVERRIDE="$HB_INSTANCE_ID_OVERRIDE" \
  HB_RATE_ORACLE_OVERRIDE="$RATE_ORACLE_OVERRIDE" \
  "$PYTHON_BIN" - <<'PY'
import os
import sys
from pathlib import Path

try:
    import yaml
except Exception as exc:  # pragma: no cover - utility script
    raise SystemExit(f"Missing PyYAML. Activate the hummingbot conda env first. Error: {exc}")

def pick(override, env_key, existing, default):
    if override not in (None, ""):
        return override
    env_val = os.environ.get(env_key)
    if env_val not in (None, ""):
        return env_val
    if existing not in (None, ""):
        return existing
    return default

conf_path = Path("conf/conf_client.yml")
conf_path.parent.mkdir(parents=True, exist_ok=True)

data = {}
if conf_path.exists():
    loaded = yaml.safe_load(conf_path.read_text()) or {}
    if isinstance(loaded, dict):
        data = loaded

mqtt = data.get("mqtt_bridge") or {}
host = pick(os.environ.get("HB_MQTT_HOST_OVERRIDE"), "MQTT_HOST", mqtt.get("mqtt_host"), "localhost")
port_raw = pick(os.environ.get("HB_MQTT_PORT_OVERRIDE"), "MQTT_PORT", mqtt.get("mqtt_port"), "1883")
try:
    port = int(port_raw)
except (TypeError, ValueError):
    raise SystemExit(f"Invalid MQTT_PORT value: {port_raw}")

mqtt["mqtt_host"] = host
mqtt["mqtt_port"] = port
mqtt["mqtt_autostart"] = True
data["mqtt_bridge"] = mqtt

instance_id = pick(os.environ.get("HB_INSTANCE_ID_OVERRIDE"), "HB_INSTANCE_ID", data.get("instance_id"), "lambdaplex-testbot")
data["instance_id"] = instance_id

rate_oracle = os.environ.get("HB_RATE_ORACLE_OVERRIDE") or os.environ.get("RATE_ORACLE_OVERRIDE") or "coin_gecko"
data["rate_oracle_source"] = {"name": rate_oracle}

conf_path.write_text(yaml.safe_dump(data, sort_keys=False))
print(f"{host} {port} {instance_id}")
PY
)
rc=$?
set -e
if [[ $rc -ne 0 ]]; then
  exit $rc
fi

if [[ "$MQTT_PREFLIGHT" != "skip" ]]; then
  set +e
  HB_MQTT_HOST="$mqtt_host" HB_MQTT_PORT="$mqtt_port" "$PYTHON_BIN" - <<'PY'
import os
import socket
import sys

host = os.environ["HB_MQTT_HOST"]
port = int(os.environ["HB_MQTT_PORT"])

s = socket.socket()
s.settimeout(2)
try:
    s.connect((host, port))
    print(f"MQTT preflight OK: {host}:{port}")
    sys.exit(0)
except Exception as e:
    print(f"MQTT preflight FAILED: {host}:{port} -> {e!r}")
    sys.exit(1)
finally:
    s.close()
PY
  rc=$?
  set -e
  if [[ $rc -ne 0 ]]; then
    if [[ "$MQTT_PREFLIGHT" == "fail" ]]; then
      exit $rc
    else
      echo "Warning: MQTT preflight failed; continuing. Set MQTT_PREFLIGHT=fail to abort." >&2
    fi
  fi
fi

if [[ -n "$LAMBDAPLEX_REST_URL_OVERRIDE" ]]; then
  export LAMBDAPLEX_REST_URL="$LAMBDAPLEX_REST_URL_OVERRIDE"
fi
if [[ -n "$LAMBDAPLEX_WSS_URL_OVERRIDE" ]]; then
  export LAMBDAPLEX_WSS_URL="$LAMBDAPLEX_WSS_URL_OVERRIDE"
fi

PYTHONPATH="$ROOT_DIR" "$PYTHON_BIN" bin/hummingbot_quickstart.py \
  --config-password "$PASSWORD" \
  --config-file-name "$STRATEGY_FILE" \
  --headless
