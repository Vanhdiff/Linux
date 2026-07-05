import os
import sys
from datetime import datetime, timedelta
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DB_PATH = ROOT / ".tmp" / f"guardrail_real_data_rules_{os.getpid()}.db"
os.environ["DATABASE_URL"] = f"sqlite:///{DB_PATH.as_posix()}"
sys.path.insert(0, str(ROOT / "backend"))
sys.path.insert(0, str(ROOT / "backend" / ".deps"))

from app.database import SessionLocal, init_db  # noqa: E402
from app.models import (  # noqa: E402
    AccountSnapshot,
    EconomicEvent,
    GuardrailSetting,
    NormalizedTrade,
    RawPosition,
    TradingAccount,
)
from app.services.guardrail_service import GuardrailService  # noqa: E402


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def add_trade(db, account_id, *, opened_at, closed_at, pnl, r, exit_reason, volume=1.0):
    db.add(
        NormalizedTrade(
            account_id=account_id,
            symbol="XAUUSD",
            direction="buy",
            side="buy",
            volume=volume,
            opened_at=opened_at,
            open_time=opened_at,
            closed_at=closed_at,
            close_time=closed_at,
            entry_price=2300,
            open_price=2300,
            exit_price=2295 if pnl < 0 else 2310,
            close_price=2295 if pnl < 0 else 2310,
            stop_loss=2295,
            take_profit=2310,
            commission=0,
            swap=0,
            gross_pnl=pnl,
            profit=pnl,
            net_pnl=pnl,
            net_profit=pnl,
            duration_seconds=int((closed_at - opened_at).total_seconds()),
            entry_reason="setup",
            exit_reason=exit_reason,
            risk_amount=abs(pnl / r) if r else 100,
            r_multiple=r,
            setup_tag="setup",
            session="London",
            status="closed",
            source_deal_ids=[f"{account_id}-{closed_at.timestamp()}"],
        )
    )


init_db()
now = datetime.utcnow()
today = (now + timedelta(hours=7)).date()

with SessionLocal() as db:
    account = TradingAccount(
        name="Rule smoke",
        broker="MT5",
        server="Demo",
        login="real-data-smoke",
        currency="USD",
        is_active=True,
    )
    db.add(account)
    db.commit()
    db.refresh(account)

    db.add(
        AccountSnapshot(
            account_id=account.id,
            captured_at=datetime.combine(today, datetime.min.time()) - timedelta(hours=7),
            balance=10_000,
            equity=10_000,
            margin=0,
            free_margin=10_000,
            margin_level=0,
            profit=0,
            raw_payload={},
        )
    )
    db.add(
        GuardrailSetting(
            account_id=account.id,
            max_daily_loss=500,
            max_trades_per_day=10,
            max_risk_per_trade=100,
            block_high_impact_news=True,
            trading_window_start="UTC+7 07:00",
            trading_window_end="UTC+7 23:00",
            enabled=True,
            settings={
                "trade_blocking_enabled": True,
                "block_max_trades_per_day": True,
                "block_max_daily_loss": True,
                "block_max_daily_profit": False,
                "max_daily_profit": 5000,
                "fixed_risk_percent": 0.5,
                "news_block_mode": "Before only",
                "news_window_minutes_before": 20,
                "news_window_minutes_after": 20,
                "loss_streak_block_count": 3,
                "loss_streak_block_minutes": 30,
                "cooling_off_after_loss_minutes": 15,
                "martingale_volume_multiplier": 1.5,
            },
        )
    )

    last_sl_closed = now - timedelta(minutes=5)
    add_trade(
        db,
        account.id,
        opened_at=last_sl_closed - timedelta(minutes=3),
        closed_at=last_sl_closed,
        pnl=-100,
        r=-1.0,
        exit_reason="sl",
    )
    add_trade(
        db,
        account.id,
        opened_at=now - timedelta(hours=1),
        closed_at=now - timedelta(minutes=55),
        pnl=80,
        r=1.6,
        exit_reason="tp",
    )
    db.add(
        EconomicEvent(
            event_time=now + timedelta(minutes=10),
            currency="USD",
            impact="high",
            title="High impact before-only event",
            actual=None,
            forecast=None,
            previous=None,
            source="smoke",
            external_event_id="before-event",
        )
    )
    db.add(
        EconomicEvent(
            event_time=now - timedelta(minutes=10),
            currency="USD",
            impact="high",
            title="Past event ignored by before-only",
            actual=None,
            forecast=None,
            previous=None,
            source="smoke",
            external_event_id="past-event",
        )
    )
    captured_at = now - timedelta(seconds=10)
    db.add_all(
        [
            RawPosition(
                account_id=account.id,
                raw_import_id=None,
                external_position_id="p1",
                symbol="XAUUSD",
                direction="buy",
                volume=1.0,
                open_price=2300,
                current_price=2298,
                stop_loss=2295,
                take_profit=2310,
                profit=-40,
                swap=0,
                commission=0,
                opened_at=now - timedelta(minutes=4),
                captured_at=captured_at,
                raw_payload={},
            ),
            RawPosition(
                account_id=account.id,
                raw_import_id=None,
                external_position_id="p2",
                symbol="XAUUSD",
                direction="buy",
                volume=2.0,
                open_price=2298,
                current_price=2299,
                stop_loss=2295,
                take_profit=2310,
                profit=5,
                swap=0,
                commission=0,
                opened_at=now - timedelta(minutes=2),
                captured_at=captured_at,
                raw_payload={},
            ),
        ]
    )
    db.commit()

    open_positions = [
        {
            "external_position_id": "p1",
            "symbol": "XAUUSD",
            "direction": "buy",
            "volume": 1.0,
            "profit": -40,
            "opened_at": int((now - timedelta(minutes=4)).timestamp()),
        },
        {
            "external_position_id": "p2",
            "symbol": "XAUUSD",
            "direction": "buy",
            "volume": 2.0,
            "profit": 5,
            "opened_at": int((now - timedelta(minutes=2)).timestamp()),
        },
    ]

    status = GuardrailService(db).status(
        account.id,
        today,
        floating_pnl=-35,
        open_positions=open_positions,
    )
    codes = {item["rule_code"] for item in status["trade_block"]["reasons"]}
    require("high_impact_news_window" in codes, codes)
    require("cooling_off_active" in codes, codes)
    require("live_averaging_loss" in codes, codes)
    require("live_martingale" in codes, codes)

    news = next(item for item in status["checks"] if item["rule_code"] == "high_impact_news_window")
    require(news["payload"]["news_block_mode"] == "Before only", news)
    require(len(news["payload"]["event_ids"]) == 1, news)

    discipline = next(
        item for item in status["scorecard"]["categories"] if item["code"] == "discipline"
    )
    row_map = {item["code"]: item for item in discipline["rows"]}
    require(row_map["cooling_off"]["passed"] is False, row_map)
    require(row_map["no_averaging_loss"]["passed"] is False, row_map)
    require(row_map["no_martingale"]["passed"] is False, row_map)

    fallback_status = GuardrailService(db).status(account.id, today)
    fallback_codes = {
        item["rule_code"] for item in fallback_status["trade_block"]["reasons"]
    }
    require("live_averaging_loss" in fallback_codes, fallback_codes)
    require("live_martingale" in fallback_codes, fallback_codes)
    require(fallback_status["scorecard"]["floating_pnl"] == -35, fallback_status)

print("guardrail real-data rules smoke: UTC+7/news/live-position rules OK")
