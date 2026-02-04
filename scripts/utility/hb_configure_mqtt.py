import os
from pathlib import Path

try:
    import yaml
except Exception as exc:  # pragma: no cover - utility script
    raise SystemExit(f"Missing PyYAML. Activate the hummingbot conda env first. Error: {exc}")


def _get_env_or_existing(env_key: str, existing, default):
    val = os.environ.get(env_key)
    if val is not None and val != "":
        return val
    if existing is not None:
        return existing
    return default


def main() -> None:
    conf_path = Path("conf/conf_client.yml")
    conf_path.parent.mkdir(parents=True, exist_ok=True)

    data = {}
    if conf_path.exists():
        loaded = yaml.safe_load(conf_path.read_text())
        if isinstance(loaded, dict):
            data = loaded

    mqtt_bridge = data.get("mqtt_bridge")
    if not isinstance(mqtt_bridge, dict):
        mqtt_bridge = {}

    host = _get_env_or_existing("MQTT_HOST", mqtt_bridge.get("mqtt_host"), "localhost")
    port_raw = _get_env_or_existing("MQTT_PORT", mqtt_bridge.get("mqtt_port"), "1883")
    try:
        port = int(port_raw)
    except (TypeError, ValueError):
        raise SystemExit(f"Invalid MQTT_PORT value: {port_raw}")

    mqtt_bridge["mqtt_host"] = host
    mqtt_bridge["mqtt_port"] = port
    mqtt_bridge["mqtt_autostart"] = True
    data["mqtt_bridge"] = mqtt_bridge

    data["instance_id"] = _get_env_or_existing("HB_INSTANCE_ID", data.get("instance_id"), "lambdaplex-testbot")

    conf_path.write_text(yaml.safe_dump(data, sort_keys=False))
    print(f"Wrote {conf_path} with mqtt_bridge + instance_id")


if __name__ == "__main__":
    main()
