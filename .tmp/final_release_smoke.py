from __future__ import annotations

import asyncio
import json
import os
from datetime import date, datetime, time, timedelta, timezone
from pathlib import Path
from urllib.parse import urlencode


ROOT = Path(__file__).resolve().parents[1]
DB_PATH = ROOT / ".tmp" / f"final_release_smoke_{os.getpid()}.db"
os.environ["DATABASE_URL"] = f"sqlite:///{DB_PATH.as_posix()}"


from app.database import SessionLocal, init_db  # noqa: E402
from app.main import create_app  # noqa: E402
from app.models import (  # noqa: E402
    AccountSnapshot,
    EconomicEvent,
    GuardrailSetting,
    NormalizedTrade,
    TradeJournal,
    TradingAccount,
)


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
    status = next(
        message["status"]
        for message in messages
        if message["type"] == "http.response.start"
    )
    response_body = b"".join(
        message.get("body", b"")
        for message in messages
        if message["type"] == "http.response.body"
    )
    parsed = json.loads(response_body.decode("utf-8")) if response_body else None
    return status, parsed, response_body.decode("utf-8", errors="replace")


def seed_core_data() -> int:
    now_utc = datetime.now(timezone.utc)
    today_local = (datetime.utcnow() + timedelta(hours=7)).date()
    month_start = date(today_local.year, today_local.month, 1)

    def local_to_utc(local_day: date, hour: int, minute: int = 0) -> datetime:
        local_dt = datetime.combine(local_day, time(hour, minute))
        return local_dt - timedelta(hours=7)

    with SessionLocal() as db:
        account = TradingAccount(
            name="Release Smoke",
            broker="Demo Broker",
            server="Demo-Server",
            login=f"REL-{os.getpid()}",
            currency="USD",
            timezone="UTC+7",
            is_active=True,
        )
        db.add(account)
        db.flush()

        db.add_all(
            [
                AccountSnapshot(
                    account_id=account.id,
                    captured_at=local_to_utc(today_local - timedelta(days=2), 8),
                    balance=10000,
                    equity=10000,
                    margin=300,
                    free_margin=9700,
                    margin_level=3333,
                    profit=0,
                    raw_payload={"seed": True},
                ),
                AccountSnapshot(
                    account_id=account.id,
                    captured_at=local_to_utc(today_local, 8),
                    balance=10320,
                    equity=10160,
                    margin=420,
                    free_margin=9740,
                    margin_level=2419,
                    profit=-160,
                    raw_payload={"seed": True},
                ),
            ]
        )

        trades = [
            NormalizedTrade(
                account_id=account.id,
                symbol="EURUSD",
                direction="buy",
                side="buy",
                volume=0.2,
                opened_at=local_to_utc(today_local - timedelta(days=2), 9),
                open_time=local_to_utc(today_local - timedelta(days=2), 9),
                closed_at=local_to_utc(today_local - timedelta(days=2), 10, 30),
                close_time=local_to_utc(today_local - timedelta(days=2), 10, 30),
                entry_price=1.1000,
                open_price=1.1000,
                exit_price=1.1040,
                close_price=1.1040,
                stop_loss=1.0980,
                take_profit=1.1060,
                commission=-2.0,
                swap=0.0,
                gross_pnl=80.0,
                profit=80.0,
                net_pnl=78.0,
                net_profit=78.0,
                duration_seconds=5400,
                entry_reason="pullback",
                exit_reason="tp",
                risk_amount=50.0,
                r_multiple=1.56,
                setup_tag="London Pullback",
                session="London",
                status="closed",
                source_deal_ids=["d1"],
            ),
            NormalizedTrade(
                account_id=account.id,
                symbol="GBPUSD",
                direction="sell",
                side="sell",
                volume=0.1,
                opened_at=local_to_utc(today_local - timedelta(days=1), 14),
                open_time=local_to_utc(today_local - timedelta(days=1), 14),
                closed_at=local_to_utc(today_local - timedelta(days=1), 15, 10),
                close_time=local_to_utc(today_local - timedelta(days=1), 15, 10),
                entry_price=1.2700,
                open_price=1.2700,
                exit_price=1.2745,
                close_price=1.2745,
                stop_loss=1.2730,
                take_profit=1.2640,
                commission=-1.5,
                swap=0.0,
                gross_pnl=-120.0,
                profit=-120.0,
                net_pnl=-121.5,
                net_profit=-121.5,
                duration_seconds=4200,
                entry_reason="breakout",
                exit_reason="sl",
                risk_amount=60.0,
                r_multiple=-2.025,
                setup_tag="NY Breakout",
                session="New York",
                status="closed",
                source_deal_ids=["d2"],
            ),
            NormalizedTrade(
                account_id=account.id,
                symbol="XAUUSD",
                direction="buy",
                side="buy",
                volume=0.05,
                opened_at=local_to_utc(today_local, 9, 15),
                open_time=local_to_utc(today_local, 9, 15),
                closed_at=local_to_utc(today_local, 10, 0),
                close_time=local_to_utc(today_local, 10, 0),
                entry_price=2330.0,
                open_price=2330.0,
                exit_price=2344.0,
                close_price=2344.0,
                stop_loss=2322.0,
                take_profit=2345.0,
                commission=-1.0,
                swap=0.0,
                gross_pnl=140.0,
                profit=140.0,
                net_pnl=139.0,
                net_profit=139.0,
                duration_seconds=2700,
                entry_reason="retest",
                exit_reason="tp",
                risk_amount=40.0,
                r_multiple=3.475,
                setup_tag="Asia Reversal",
                session="Asia",
                status="closed",
                source_deal_ids=["d3"],
            ),
            NormalizedTrade(
                account_id=account.id,
                symbol="USDJPY",
                direction="buy",
                side="buy",
                volume=0.1,
                opened_at=local_to_utc(today_local, 11, 30),
                open_time=local_to_utc(today_local, 11, 30),
                closed_at=local_to_utc(today_local, 12, 20),
                close_time=local_to_utc(today_local, 12, 20),
                entry_price=159.20,
                open_price=159.20,
                exit_price=158.40,
                close_price=158.40,
                stop_loss=158.70,
                take_profit=160.20,
                commission=-1.0,
                swap=0.0,
                gross_pnl=-80.0,
                profit=-80.0,
                net_pnl=-81.0,
                net_profit=-81.0,
                duration_seconds=3000,
                entry_reason="continuation",
                exit_reason="sl",
                risk_amount=45.0,
                r_multiple=-1.8,
                setup_tag="Trend Continuation",
                session="London",
                status="closed",
                source_deal_ids=["d4"],
            ),
        ]
        db.add_all(trades)
        db.flush()

        db.add_all(
            [
                TradeJournal(
                    trade_id=trades[0].id,
                    setup="London Pullback",
                    mistakes=["late entry"],
                    emotion_before="calm",
                    emotion_after="focused",
                    followed_plan=True,
                    notes="Clean execution.",
                    screenshot_refs=["chart-1.png"],
                    review_status="reviewed",
                    reviewed_at=now_utc,
                ),
                TradeJournal(
                    trade_id=trades[1].id,
                    setup="NY Breakout",
                    mistakes=["overtrading", "revenge"],
                    emotion_before="impatient",
                    emotion_after="frustrated",
                    followed_plan=False,
                    notes="Forced the setup.",
                    screenshot_refs=["chart-2.png"],
                    review_status="reviewed",
                    reviewed_at=now_utc,
                ),
            ]
        )

        db.add(
            GuardrailSetting(
                account_id=account.id,
                max_daily_loss=50.0,
                max_trades_per_day=2,
                max_risk_per_trade=100.0,
                block_high_impact_news=True,
                trading_window_start=None,
                trading_window_end=None,
                enabled=True,
                settings={
                    "trade_blocking_enabled": True,
                    "block_max_trades_per_day": True,
                    "block_max_daily_loss": True,
                    "block_max_daily_profit": True,
                    "max_daily_profit": 5000,
                    "fixed_risk_percent": 0.5,
                    "news_window_minutes_before": 30,
                    "news_window_minutes_after": 30,
                },
            )
        )

        db.add_all(
            [
                EconomicEvent(
                    source="seed",
                    external_event_id="news-1",
                    event_time=local_to_utc(today_local, 11, 50),
                    currency="USD",
                    impact="high",
                    title="US CPI",
                    actual=None,
                    forecast="3.2%",
                    previous="3.1%",
                    raw_payload={"seed": True},
                ),
                EconomicEvent(
                    source="seed",
                    external_event_id="news-2",
                    event_time=local_to_utc(month_start, 9, 0),
                    currency="EUR",
                    impact="medium",
                    title="ECB Speech",
                    actual=None,
                    forecast=None,
                    previous=None,
                    raw_payload={"seed": True},
                ),
            ]
        )

        db.commit()
        return account.id


async def activate_license(app) -> None:
    blocked_status, blocked_json, blocked_text = await asgi_request(app, "GET", "/api/accounts")
    require(blocked_status == 403, f"license gate failed: {blocked_status} {blocked_text}")
    require(blocked_json["detail"] == "License activation required", blocked_text)

    license_status, license_json, license_text = await asgi_request(
        app,
        "POST",
        "/api/license",
        json_body={"license_key": "OFFLINE-123456789012"},
    )
    require(license_status == 201, license_text)
    require(license_json["is_active"] is True, license_text)


async def main() -> None:
    init_db()
    app = create_app()
    account_id = seed_core_data()
    today_local = (datetime.utcnow() + timedelta(hours=7)).date()
    month_key = today_local.strftime("%Y-%m")

    await activate_license(app)

    health_status, _, _ = await asgi_request(app, "GET", "/health")
    require(health_status == 200, "health endpoint failed")

    overview_status, overview_json, overview_text = await asgi_request(
        app,
        "GET",
        "/api/analytics/overview",
        query={"account_id": account_id},
    )
    require(overview_status == 200, overview_text)
    require(overview_json["trade_count"] == 4, overview_text)
    require(overview_json["win_count"] == 2, overview_text)
    require(overview_json["loss_count"] == 2, overview_text)
    require(overview_json["symbols"], "analytics symbols empty")
    require(overview_json["sessions"], "analytics sessions empty")
    require(overview_json["setups"], "analytics setups empty")
    require(overview_json["mistake_frequency"], "analytics mistakes empty")

    dashboard_status, dashboard_json, dashboard_text = await asgi_request(
        app,
        "GET",
        "/api/dashboard",
        query={"account_id": account_id, "period": "month"},
    )
    require(dashboard_status == 200, dashboard_text)
    require(dashboard_json["analytics"]["trade_count"] == 4, dashboard_text)
    require(dashboard_json["recent_trades"], "dashboard recent_trades empty")
    require(dashboard_json["latest_snapshot"] is not None, "dashboard snapshot missing")
    require(dashboard_json["guardrail_settings"] is not None, "dashboard guardrails missing")

    journal_day_status, journal_day_json, journal_day_text = await asgi_request(
        app,
        "GET",
        "/api/journal/day",
        query={"account_id": account_id, "date": today_local.isoformat()},
    )
    require(journal_day_status == 200, journal_day_text)
    require(len(journal_day_json["trades"]) == 2, journal_day_text)
    require(journal_day_json["summary"]["trade_count"] == 2, journal_day_text)

    journal_calendar_status, journal_calendar_json, journal_calendar_text = await asgi_request(
        app,
        "GET",
        "/api/journal/calendar",
        query={"account_id": account_id, "month": month_key},
    )
    require(journal_calendar_status == 200, journal_calendar_text)
    require(journal_calendar_json["days"], "journal calendar days empty")

    journal_month_status, journal_month_json, journal_month_text = await asgi_request(
        app,
        "GET",
        "/api/journal/month-summary",
        query={"account_id": account_id, "month": month_key},
    )
    require(journal_month_status == 200, journal_month_text)
    require(journal_month_json["summary"]["trade_count"] == 4, journal_month_text)
    require(journal_month_json["weekly_breakdown"], "weekly breakdown empty")

    news_calendar_status, news_calendar_json, news_calendar_text = await asgi_request(
        app,
        "GET",
        "/api/news/calendar",
        query={"month": month_key},
    )
    require(news_calendar_status == 200, news_calendar_text)
    require(news_calendar_json["days"], "news calendar empty")

    news_day_status, news_day_json, news_day_text = await asgi_request(
        app,
        "GET",
        "/api/news/day",
        query={"date": today_local.isoformat()},
    )
    require(news_day_status == 200, news_day_text)
    require(news_day_json["counts"]["high"] >= 1, news_day_text)

    news_upcoming_status, news_upcoming_json, news_upcoming_text = await asgi_request(
        app,
        "GET",
        "/api/news/upcoming",
        query={"hours": 72},
    )
    require(news_upcoming_status == 200, news_upcoming_text)
    require(news_upcoming_json["events"], "news upcoming empty")

    guardrail_status, guardrail_json, guardrail_text = await asgi_request(
        app,
        "GET",
        "/api/guardrails/status",
        query={"account_id": account_id, "date": today_local.isoformat()},
    )
    require(guardrail_status == 200, guardrail_text)
    require(guardrail_json["trade_blocking_enabled"] is True, guardrail_text)
    require(guardrail_json["trade_blocked"] is True, guardrail_text)
    require(guardrail_json["checks"], "guardrail checks empty")

    trade_block_status, trade_block_json, trade_block_text = await asgi_request(
        app,
        "GET",
        "/api/guardrails/trade-block",
        query={"account_id": account_id, "date": today_local.isoformat()},
    )
    require(trade_block_status == 200, trade_block_text)
    require(trade_block_json["blocked"] is True, trade_block_text)
    require(trade_block_json["reasons"], "trade block reasons empty")

    print("final release smoke: analytics/dashboard/journal/news/guardrails/license OK")


if __name__ == "__main__":
    asyncio.run(main())
