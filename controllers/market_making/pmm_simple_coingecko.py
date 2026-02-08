import time
from decimal import Decimal
from typing import List, Optional

import aiohttp
from pydantic import Field

from hummingbot.data_feed.candles_feed.data_types import CandlesConfig
from hummingbot.data_feed.coin_gecko_data_feed.coin_gecko_constants import COOLOFF_AFTER_BAN

from .pmm_simple import PMMSimpleConfig, PMMSimpleController


class PMMSimpleCoinGeckoConfig(PMMSimpleConfig):
    """
    PMM Simple controller that uses CoinGecko as the reference price source instead of the connector mid price.

    Notes:
    - CoinGecko token ids are NOT symbols. Example: "solana" (id) vs "SOL" (symbol).
    - The public API is aggressively rate-limited. Keep refresh intervals >= 10s, preferably 30s+.
    """

    controller_name: str = "pmm_simple_coingecko"
    # As this controller is a simple version of the PMM, we are not using the candles feed
    candles_config: List[CandlesConfig] = Field(default=[])

    coin_gecko_token_id: str = Field(
        default="solana",
        json_schema_extra={
            "prompt": "CoinGecko token id to use as reference price (e.g., solana): ",
            "prompt_on_new": True,
            "is_updatable": True,
        },
    )
    coin_gecko_denominator_token_id: Optional[str] = Field(
        default="",
        json_schema_extra={
            "prompt": "Optional CoinGecko token id to use as denominator (reference_price = token_price / denom_price). Leave empty to disable: ",
            "prompt_on_new": True,
            "is_updatable": True,
        },
    )
    coin_gecko_vs_currency: str = Field(
        default="usd",
        json_schema_extra={
            "prompt": "CoinGecko vs currency (e.g., usd): ",
            "prompt_on_new": True,
            "is_updatable": True,
        },
    )
    coin_gecko_price_refresh_interval: float = Field(
        default=30.0,
        gt=0,
        json_schema_extra={
            "prompt": "CoinGecko price refresh interval in seconds (e.g., 30): ",
            "prompt_on_new": True,
            "is_updatable": True,
        },
    )
    coin_gecko_request_timeout: float = Field(
        default=10.0,
        gt=0,
        json_schema_extra={
            "prompt": "CoinGecko request timeout in seconds (e.g., 10): ",
            "prompt_on_new": True,
            "is_updatable": True,
        },
    )


class PMMSimpleCoinGeckoController(PMMSimpleController):
    _COINGECKO_SIMPLE_PRICE_URL = "https://api.coingecko.com/api/v3/simple/price"

    def __init__(self, config: PMMSimpleCoinGeckoConfig, *args, **kwargs):
        super().__init__(config, *args, **kwargs)
        self.config = config

        # Cache to avoid hammering CoinGecko (update_processed_data is called ~1Hz).
        self._cached_reference_price: Optional[Decimal] = None
        self._last_fetch_attempt_ts: float = 0.0  # monotonic seconds
        self._last_fetch_success_ts: float = 0.0  # monotonic seconds
        self._cooloff_until_ts: float = 0.0  # monotonic seconds (only used after HTTP 429)

    async def update_processed_data(self):
        now = time.monotonic()

        # Attempt to refresh price at most once per interval. Note: we enforce the interval even before the first
        # successful fetch to avoid 1Hz retry loops (update_processed_data is called ~1Hz).
        if (now >= self._cooloff_until_ts and
                (self._last_fetch_attempt_ts == 0.0 or
                 now - self._last_fetch_attempt_ts >= self.config.coin_gecko_price_refresh_interval)):
            self._last_fetch_attempt_ts = now
            try:
                fetched = await self._fetch_reference_price_from_coingecko()
            except Exception as e:
                denom = (self.config.coin_gecko_denominator_token_id or "").strip().lower()
                if "HTTP 429" in str(e):
                    # CoinGecko public API is very limited; after a 429, back off to avoid retry loops.
                    self._cooloff_until_ts = max(self._cooloff_until_ts, now + COOLOFF_AFTER_BAN)
                self.logger().warning(
                    f"CoinGecko fetch failed (token_id={self.config.coin_gecko_token_id}, "
                    f"denom_token_id={denom or None}, vs={self.config.coin_gecko_vs_currency}). "
                    f"Using cached price. Error: {e}"
                )
            else:
                self._cached_reference_price = fetched
                self._last_fetch_success_ts = now

        reference_price = self._cached_reference_price or Decimal("0")
        self.processed_data = {
            "reference_price": reference_price,
            "spread_multiplier": Decimal("1"),
            "coingecko_last_success_age": Decimal(str(now - self._last_fetch_success_ts)) if self._last_fetch_success_ts else None,
        }

    def create_actions_proposal(self):
        """
        Skip placing/rebalancing orders until a valid reference price is available.
        """
        reference_price = self.processed_data.get("reference_price")
        if reference_price is None or Decimal(reference_price) <= Decimal("0"):
            return []
        return super().create_actions_proposal()

    async def _fetch_reference_price_from_coingecko(self) -> Decimal:
        token_id = (self.config.coin_gecko_token_id or "").strip().lower()
        denom_token_id = (self.config.coin_gecko_denominator_token_id or "").strip().lower()
        vs_currency = (self.config.coin_gecko_vs_currency or "").strip().lower()
        if not token_id:
            raise ValueError("coin_gecko_token_id must be set")
        if not vs_currency:
            raise ValueError("coin_gecko_vs_currency must be set")

        token_ids = [token_id] + ([denom_token_id] if denom_token_id else [])

        timeout = aiohttp.ClientTimeout(total=self.config.coin_gecko_request_timeout)
        async with aiohttp.ClientSession(timeout=timeout) as session:
            async with session.get(
                self._COINGECKO_SIMPLE_PRICE_URL,
                params={"ids": ",".join(token_ids), "vs_currencies": vs_currency},
            ) as resp:
                if resp.status != 200:
                    # Keep response body short in logs (CoinGecko often returns verbose JSON).
                    body = (await resp.text())[:300]
                    raise RuntimeError(f"HTTP {resp.status}: {body}")
                data = await resp.json()

        try:
            raw_price = data[token_id][vs_currency]
        except Exception as e:
            raise KeyError(
                f"Unexpected CoinGecko response shape for token_id={token_id}, vs={vs_currency}: {data}"
            ) from e

        price = Decimal(str(raw_price))
        if price <= Decimal("0"):
            raise ValueError(f"Invalid CoinGecko price returned: {raw_price}")

        if denom_token_id:
            try:
                raw_denom_price = data[denom_token_id][vs_currency]
            except Exception as e:
                raise KeyError(
                    f"Unexpected CoinGecko response shape for denom_token_id={denom_token_id}, vs={vs_currency}: {data}"
                ) from e
            denom_price = Decimal(str(raw_denom_price))
            if denom_price <= Decimal("0"):
                raise ValueError(f"Invalid CoinGecko denominator price returned: {raw_denom_price}")
            price = price / denom_price

        return price
