# Lambdaplex Headless Workflow

This folder contains helper scripts to run Hummingbot headlessly with the Lambdaplex connector.

## Quick Start

1. Run auth setup (writes encrypted connector config):

```bash
# Option A: env vars
PASSWORD=... API_KEY=... PRIVATE_KEY=... \
  scripts/plex/run_auth_setup_lambdaplex.sh

# Option B: positional args
scripts/plex/run_auth_setup_lambdaplex.sh "$PASSWORD" "$API_KEY" "$PRIVATE_KEY"

# Option C: read private key from file
scripts/plex/run_auth_setup_lambdaplex.sh \
  -p "$PASSWORD" -k "$API_KEY" --private-key-file conf/keys/lambdaplex_private_key.pem
```

2. Run headless with a V1 strategy YAML in `conf/strategies/`:

```bash
PASSWORD=... STRATEGY_FILE=conf_lambdaplex_pmm_qa.yml \
  scripts/plex/run_headless_lambdaplex.sh

# Or positional args
scripts/plex/run_headless_lambdaplex.sh "$PASSWORD" conf_lambdaplex_pmm_qa.yml
```

By default the headless script sets the rate oracle source to `coin_gecko`. You can override with:

```bash
scripts/plex/run_headless_lambdaplex.sh \
  --rate-oracle binance \
  abc123 conf_lambdaplex_pmm_qa.yml
```

## Local Lambdaplex Environment Overrides

The connector defaults to production endpoints. For local/dev, set:

```bash
export LAMBDAPLEX_REST_URL="http://localhost:9393/api/"
export LAMBDAPLEX_WSS_URL="ws://localhost:9393/api/{}/ws"
# Optional if your local API version differs
# export LAMBDAPLEX_API_VERSION="v1"
```

You can also pass overrides directly to the headless script:

```bash
scripts/plex/run_headless_lambdaplex.sh \
  --rest-url "http://localhost:9393/api/" \
  --wss-url "ws://localhost:9393/api/{}/ws" \
  abc123 conf_lambdaplex_pmm_qa.yml
```

## Notes

- These scripts assume you have built the project and activated the `hummingbot` conda env.
- The headless runner uses `bin/hummingbot_quickstart.py` and requires `--config-password`.
- The auth setup writes encrypted secrets into `conf/connectors/lambdaplex.yml` and creates `conf/.password_verification`.
- Private keys must be unencrypted PKCS#8 Ed25519 (PEM or base64). Encrypted keys will not work.

## Keeping the Lambdaplex Branch Updated

If you want to keep your local `master` aligned with `petioptrv/feat/lambdaplex-connector`, use:

```bash
scripts/plex/update_lambdaplex.sh
```

Notes for teammates:
- The update script assumes a `petioptrv` remote exists. If you don’t have it yet, add it once:

```bash
git remote add petioptrv git@github.com:petioptrv/hummingbot.git
```

- The script fast‑forwards `master` locally. If you want the fork’s `origin/master` updated, run:

```bash
git push origin master
```

- For reproducibility in CI, prefer pinning to a commit SHA instead of tracking the moving branch head.

## Troubleshooting

- **Headless starts but MQTT shows repeated connection errors**
  Ensure a broker is running and reachable (default is `localhost:1883`).
  On some macOS setups, `localhost` resolves to IPv6 while mosquitto listens on IPv4 only.
  If so, run headless with `--mqtt-host 127.0.0.1`.
  The headless script writes MQTT settings into `conf/conf_client.yml` and runs an MQTT preflight check;
  set `MQTT_PREFLIGHT=fail` to abort on failure.
  You can override the preflight target with `--mqtt-host` and `--mqtt-port`.

- **`Invalid private key` or `not an Ed25519 private key`**
  The connector only accepts **unencrypted PKCS#8 Ed25519** keys.
  If you have an encrypted PEM, decrypt it first and pass the unencrypted PEM.

- **`Invalid password` on startup**
  The `PASSWORD` must match what was used by the auth setup. If you changed it,
  delete `conf/.password_verification` and re‑run auth setup.

- **Strategy file not found**
  `--config-file-name` expects only the filename, and the YAML must live in `conf/strategies/`.
