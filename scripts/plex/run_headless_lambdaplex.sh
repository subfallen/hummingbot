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
  -h, --help             Show this help
Notes:
  Assumes scripts/plex/auth_setup_lambdaplex.py has already been run.

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

POSITIONAL=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--password)
      PASSWORD="$2"; shift 2 ;;
    -s|--strategy|--config-file-name)
      STRATEGY_FILE="$2"; shift 2 ;;
    --python)
      PYTHON_BIN="$2"; shift 2 ;;
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

PYTHONPATH=./ "$PYTHON_BIN" bin/hummingbot_quickstart.py \
  --config-password "$PASSWORD" \
  --config-file-name "$STRATEGY_FILE" \
  --headless
