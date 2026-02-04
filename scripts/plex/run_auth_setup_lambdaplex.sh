#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/plex/run_auth_setup_lambdaplex.sh [options]
  scripts/plex/run_auth_setup_lambdaplex.sh PASSWORD API_KEY PRIVATE_KEY

Notes:
  This runs scripts/plex/auth_setup_lambdaplex.py to write encrypted connector config.

Required (via flags, env vars, or positional args):
  -p, --password         Hummingbot config password (env: PASSWORD)
  -k, --api-key          Lambdaplex API key (env: API_KEY)
  --private-key          Lambdaplex private key (PEM or base64 PKCS#8) (env: PRIVATE_KEY)
  --private-key-file     Path to private key file (PEM or one-line with \n)

Optional:
  --python               Python executable to use (default: python)
  -h, --help             Show this help

Examples:
  PASSWORD=... API_KEY=... PRIVATE_KEY=... \
    scripts/plex/run_auth_setup_lambdaplex.sh

  scripts/plex/run_auth_setup_lambdaplex.sh "$PASSWORD" "$API_KEY" "$PRIVATE_KEY"

  scripts/plex/run_auth_setup_lambdaplex.sh \
    -p "$PASSWORD" -k "$API_KEY" --private-key-file conf/keys/lambdaplex_private_key.pem
USAGE
}

PYTHON_BIN="python"
PASSWORD="${PASSWORD:-}"
API_KEY="${API_KEY:-}"
PRIVATE_KEY="${PRIVATE_KEY:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

POSITIONAL=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--password)
      PASSWORD="$2"; shift 2 ;;
    -k|--api-key)
      API_KEY="$2"; shift 2 ;;
    --private-key)
      PRIVATE_KEY="$2"; shift 2 ;;
    --private-key-file)
      key_path="$2"
      if [[ "$key_path" != /* ]]; then
        key_path="${ROOT_DIR}/${key_path}"
      fi
      if [[ ! -f "$key_path" ]]; then
        echo "Private key file not found: $key_path" >&2
        exit 2
      fi
      PRIVATE_KEY="$(cat "$key_path")"
      shift 2 ;;
    --python)
      PYTHON_BIN="$2"; shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    --)
      shift; POSITIONAL+=("$@"); break ;;
    -* )
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
  if [[ -z "$API_KEY" && ${#POSITIONAL[@]} -ge 2 ]]; then
    API_KEY="${POSITIONAL[1]}"
  fi
  if [[ -z "$PRIVATE_KEY" && ${#POSITIONAL[@]} -ge 3 ]]; then
    PRIVATE_KEY="${POSITIONAL[2]}"
  fi
  if [[ ${#POSITIONAL[@]} -gt 3 ]]; then
    echo "Too many positional arguments." >&2
    usage
    exit 2
  fi
fi

# If PRIVATE_KEY points to a file, read it
if [[ -n "$PRIVATE_KEY" && -f "$PRIVATE_KEY" ]]; then
  PRIVATE_KEY="$(cat "$PRIVATE_KEY")"
elif [[ -n "$PRIVATE_KEY" && -f "${ROOT_DIR}/${PRIVATE_KEY}" ]]; then
  PRIVATE_KEY="$(cat "${ROOT_DIR}/${PRIVATE_KEY}")"
fi

if [[ -z "$PASSWORD" ]]; then
  echo "Missing PASSWORD (use -p/--password or env PASSWORD)" >&2
  exit 2
fi
if [[ -z "$API_KEY" ]]; then
  echo "Missing API_KEY (use -k/--api-key or env API_KEY)" >&2
  exit 2
fi
if [[ -z "$PRIVATE_KEY" ]]; then
  echo "Missing PRIVATE_KEY (use --private-key/--private-key-file or env PRIVATE_KEY)" >&2
  exit 2
fi

cd "$ROOT_DIR"
PASSWORD="$PASSWORD" API_KEY="$API_KEY" PRIVATE_KEY="$PRIVATE_KEY" \
  PYTHONPATH="$ROOT_DIR" "$PYTHON_BIN" scripts/plex/auth_setup_lambdaplex.py
