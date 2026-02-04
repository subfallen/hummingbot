# Lambdaplex Headless Workflow

This folder contains helper scripts to run Hummingbot headlessly with the Lambdaplex connector.

## Quick Start

1. Configure MQTT (recommended for headless monitoring):

```bash
# From repo root, inside the hummingbot conda env
python scripts/utility/hb_configure_mqtt.py
```

2. Run auth setup (writes encrypted connector config):

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

3. Run headless with a V1 strategy YAML in `conf/strategies/`:

```bash
PASSWORD=... STRATEGY_FILE=conf_lambdaplex_pmm_qa.yml \
  scripts/plex/run_headless_lambdaplex.sh

# Or positional args
scripts/plex/run_headless_lambdaplex.sh "$PASSWORD" conf_lambdaplex_pmm_qa.yml
```

## Notes

- These scripts assume you have built the project and activated the `hummingbot` conda env.
- The headless runner uses `bin/hummingbot_quickstart.py` and requires `--config-password`.
- The auth setup writes encrypted secrets into `conf/connectors/lambdaplex.yml` and creates `conf/.password_verification`.
- Private keys must be unencrypted PKCS#8 Ed25519 (PEM or base64). Encrypted keys will not work.
