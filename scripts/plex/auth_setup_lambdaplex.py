import os

from hummingbot.client.config.config_crypt import ETHKeyFileSecretManger, store_password_verification
from hummingbot.client.config.config_helpers import ClientConfigAdapter
from hummingbot.client.config.security import Security
from hummingbot.client.settings import AllConnectorSettings
from hummingbot.connector.exchange.lambdaplex.lambdaplex_utils import LambdaplexConfigMap


def auth_setup():
    """This function setups the login password for Hummingbot, as well as the credentials for the Lambdaplex connector.

    It assumes a clean installation of hummingbot.

    Once the auth setup is done, to run in headless mode, please ensure that the strategy config YAML file is in
    the `conf/strategies/` directory, then run
    ```
    conda activate hummingbot

    PYTHONPATH=./ python bin/quick_start.py --config-password {PASSWORD} --config-file-name {STRATEGY_FILE} --headless
    ```

    The simplest way of creating the strategy file is to run the GUI and go through the strategy creation process.
    I suggest using the pure_market_making strategy as a basis, and then use automated adversary traders to perform
    actions such as
    - drifting the mid-price to force the bot to re-position its orders,
    - partial fills of the bot's orders,
    - full-fills of an entire side of the bot's orders (e.g. all buy orders), etc.
    """
    hummingbot_password = os.environ["PASSWORD"]
    lambdaplex_api_key = os.environ["API_KEY"]
    lambdaplex_private_key = os.environ["PRIVATE_KEY"]

    # create password-verification file
    secrets_manager_cls = ETHKeyFileSecretManger
    secrets_manager = secrets_manager_cls(hummingbot_password)
    store_password_verification(secrets_manager)

    Security.login(secrets_manager=secrets_manager)

    # create lambdaplex credentials
    connector_config: LambdaplexConfigMap = ClientConfigAdapter(
        AllConnectorSettings.get_connector_config_keys("lambdaplex")
    )
    connector_config.lambdaplex_api_key = lambdaplex_api_key
    connector_config.lambdaplex_private_key = lambdaplex_private_key
    Security.update_secure_config(connector_config)

    print("success")


if __name__ == "__main__":
    auth_setup()
