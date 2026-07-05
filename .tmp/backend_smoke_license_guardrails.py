from __future__ import annotations

import os
import asyncio
import json
from datetime import datetime, timedelta, timezone
from pathlib import Path
from types import SimpleNamespace
from urllib.parse import urlencode


ROOT = Path(__file__).resolve().parents[1]
DB_PATH = ROOT / ".tmp" / f"backend_smoke_license_guardrails_{os.getpid()}.db"
if DB_PATH.exists():
    DB_PATH.unlink()
DB_PATH.parent.mkdir(parents=True, exist_ok=True)
DB_PATH.touch()
os.environ["DATABASE_URL"] = f"sqlite:///{DB_PATH.as_posix()}"


from app.database import SessionLocal, init_db  # noqa: E402
from app.main import create_app  # noqa: E402
from app.models import NormalizedTrade  # noqa: E402
from app.services.mt5_service import Mt5Service  # noqa: E402
from app.services.mt5_trade_blocker import Mt5TradeBlocker  # noqa: E402


class FakeBlockerMt5Service:
    def market_snapshot(self, **kwargs):
        now = datetime.now(timezone.utc).replace(tzinfo=None)
        date_from = kwargs.get("date_from") or (now - timedelta(days=3))
        date_to = kwargs.get("date_to") or now
        return {
            "account_info": {
                "login": "SMOKE-001",
                "name": "Smoke 001",
                "company": "Pepperstone",
                "server": "Demo",
                "currency": "USD",
                "balance": 10000,
                "equity": 9975,
                "margin": 0,
                "free_margin": 9975,
                "profit": -25,
            },
            "positions": [],
            "orders": [],
            "deals": [
                {
                    "external_deal_id": "smoke-open",
                    "external_order_id": "smoke-order",
                    "symbol": "EURUSD",
                    "direction": "buy",
                    "entry_type": "in",
                    "volume": 0.1,
                    "price": 1.1,
                    "profit": 0,
                    "commission": 0,
                    "swap": 0,
                    "time": (now - timedelta(hours=2)).isoformat(),
                    "comment": "open",
                },
                {
                    "external_deal_id": "smoke-close",
                    "external_order_id": "smoke-order",
                    "symbol": "EURUSD",
                    "direction": "sell",
                    "entry_type": "out",
                    "volume": 0.1,
                    "price": 1.09,
                    "profit": -150,
                    "commission": 0,
                    "swap": 0,
                    "time": now.isoformat(),
                    "comment": "close",
                },
            ],
            "date_from": date_from,
            "date_to": date_to,
        }

    def floating_pnl(self) -> float:
        return -25.0

    def enforce_trade_block(self, *, blocked_since, payload=None):
        return {
            "blocked_since": blocked_since.isoformat(),
            "mode": "strict_close_all",
            "deleted_orders": [{"order": 7001}],
            "closed_positions": [{"position": 9001}],
            "failed_actions": [],
        }


class FakeMt5Module:
    TRADE_ACTION_REMOVE = 1
    TRADE_ACTION_DEAL = 2
    POSITION_TYPE_BUY = 0
    ORDER_TYPE_SELL = 1
    ORDER_TYPE_BUY = 0
    ORDER_TIME_GTC = 0
    ORDER_FILLING_IOC = 10
    ORDER_FILLING_FOK = 11
    ORDER_FILLING_RETURN = 12
    TRADE_RETCODE_DONE = 10009
    TRADE_RETCODE_DONE_PARTIAL = 10010
    TRADE_RETCODE_PLACED = 10008

    def __init__(self):
        self.requests = []

    def initialize(self, **_kwargs):
        return True

    def shutdown(self):
        return None

    def last_error(self):
        return (0, "ok")

    def orders_get(self):
        return [SimpleNamespace(ticket=7001, symbol="EURUSD")]

    def positions_get(self):
        return [
            SimpleNamespace(
                ticket=9001,
                symbol="EURUSD",
                volume=0.10,
                type=self.POSITION_TYPE_BUY,
                time=1710000000,
            )
        ]

    def symbol_info_tick(self, _symbol):
        return SimpleNamespace(bid=1.1000, ask=1.1002)

    def order_send(self, request):
        self.requests.append(dict(request))
        return SimpleNamespace(retcode=self.TRADE_RETCODE_DONE, comment="done")


class FakeMt5Service(Mt5Service):
    def __init__(self, fake_module):
        self.fake_module = fake_module

    def _load_mt5(self):
        return self.fake_module


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


async def asgi_request(app, method: str, path: str, *, query=None, json_body=None):
    body = b""
    headers = []
    if json_body is not None:
        body = json.dumps(json_body).encode("utf-8")
        headers.append((b"content-type", b"application/json"))
    query_string = urlencode(query or {}, doseq=True).encode("ascii")
    scope = {
        "type": "http",
        "asgi": {"version": "3.0"},
        "http_version": "1.1",
        "method": method,
        "scheme": "http",
        "path": path,
        "raw_path": path.encode("ascii"),
        "query_string": query_string,
        "headers": headers,
        "client": ("127.0.0.1", 12345),
        "server": ("127.0.0.1", 8000),
    }
    sent_request = False
    messages = []

    async def receive():
        nonlocal sent_request
        if not sent_request:
            sent_request = True
            return {"type": "http.request", "body": body, "more_body": False}
        return {"type": "http.disconnect"}

    async def send(message):
        messages.append(message)

    await app(scope, receive, send)
    status = next(message["status"] for message in messages if message["type"] == "http.response.start")
    response_body = b"".join(
        message.get("body", b"")
        for message in messages
        if message["type"] == "http.response.body"
    )
    parsed = json.loads(response_body.decode("utf-8")) if response_body else None
    return status, parsed, response_body.decode("utf-8", errors="replace")


async def main() -> None:
    init_db()
    app = create_app()

    health_status, _, health_text = await asgi_request(app, "GET", "/health")
    require(health_status == 200, f"health failed: {health_status} {health_text}")

    blocked_status, blocked_json, blocked_text = await asgi_request(app, "GET", "/api/accounts")
    require(blocked_status == 403, f"license gate did not block: {blocked_status}")
    require(blocked_json["detail"] == "License activation required", blocked_text)

    license_status, license_json, license_text = await asgi_request(
        app,
        "POST",
        "/api/license",
        json_body={"license_key": "OFFLINE-123456789012"},
    )
    require(license_status == 201, license_text)
    require(license_json["is_active"] is True, license_text)

    account_status, account_json, account_text = await asgi_request(
        app,
        "POST",
        "/api/accounts",
        json_body={
            "name": "Smoke Account",
            "broker": "Smoke Broker",
            "server": "Demo",
            "login": "SMOKE-001",
            "currency": "USD",
        },
    )
    require(account_status in (200, 201), account_text)
    account_id = account_json["id"]

    settings_status, _, settings_text = await asgi_request(
        app,
        "PATCH",
        "/api/guardrails/settings",
        query={"account_id": account_id},
        json_body={
            "max_daily_loss": 100,
            "max_trades_per_day": 1,
            "max_risk_per_trade": 300,
            "block_high_impact_news": False,
            "enabled": True,
            "settings": {
                "trade_blocking_enabled": True,
                "block_max_daily_loss": True,
                "block_max_trades_per_day": True,
                "block_max_daily_profit": True,
                "max_daily_profit": 999999,
                "fixed_risk_percent": 0,
            },
        },
    )
    require(settings_status == 200, settings_text)

    target_date = (datetime.utcnow() + timedelta(hours=7)).date()
    closed_at = datetime.combine(target_date, datetime.min.time()) + timedelta(hours=12)
    opened_at = closed_at - timedelta(hours=2)

    with SessionLocal() as db:
        db.add(
            NormalizedTrade(
                account_id=account_id,
                symbol="EURUSD",
                direction="buy",
                side="buy",
                volume=0.1,
                opened_at=opened_at,
                open_time=opened_at,
                closed_at=closed_at,
                close_time=closed_at,
                entry_price=1.1,
                open_price=1.1,
                exit_price=1.09,
                close_price=1.09,
                commission=0,
                swap=0,
                gross_pnl=-150,
                profit=-150,
                net_pnl=-150,
                net_profit=-150,
                risk_amount=50,
                status="closed",
                source_deal_ids=["smoke"],
            )
        )
        db.commit()

    trade_block_status, trade_block_json, trade_block_text = await asgi_request(
        app,
        "GET",
        "/api/guardrails/trade-block",
        query={"account_id": account_id},
    )
    require(trade_block_status == 200, trade_block_text)
    require(trade_block_json["blocked"] is True, trade_block_text)
    reason_codes = {item["rule_code"] for item in trade_block_json["reasons"]}
    require("max_daily_loss_reached" in reason_codes, trade_block_text)
    require("too_many_trades_today" in reason_codes, trade_block_text)

    app.state.mt5_trade_blocker = Mt5TradeBlocker(
        mt5_service=FakeBlockerMt5Service(),
        poll_seconds=999,
    )
    enforced_status, enforced_json, enforced_text = await asgi_request(
        app,
        "POST",
        "/api/mt5/trade-blocker/enforce-once",
    )
    require(enforced_status == 200, enforced_text)
    account_enforced = enforced_json["accounts"][str(account_id)]
    require(account_enforced["blocked"] is True, enforced_text)
    require(account_enforced["mt5_action"]["deleted_orders"], enforced_text)
    require(account_enforced["mt5_action"]["closed_positions"], enforced_text)

    fake_mt5 = FakeMt5Module()
    mt5_result = FakeMt5Service(fake_mt5).enforce_trade_block(
        blocked_since=datetime.now(timezone.utc)
    )
    require(len(mt5_result["deleted_orders"]) == 1, str(mt5_result))
    require(len(mt5_result["closed_positions"]) == 1, str(mt5_result))
    request_actions = [request["action"] for request in fake_mt5.requests]
    require(FakeMt5Module.TRADE_ACTION_REMOVE in request_actions, str(fake_mt5.requests))
    require(FakeMt5Module.TRADE_ACTION_DEAL in request_actions, str(fake_mt5.requests))

    print("backend smoke/license/guardrails/mt5 enforcement: OK")


if __name__ == "__main__":
    asyncio.run(main())
