import os
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path


ROOT = Path(r"E:\Tradingapp\epp_tr-desktop")
DB_PATH = ROOT / ".tmp" / "discipline_rules_smoke.db"
DB_PATH.parent.mkdir(parents=True, exist_ok=True)
if DB_PATH.exists():
    DB_PATH.unlink()
DB_PATH.touch()

sys.path.insert(0, str(ROOT / "backend" / ".deps"))
sys.path.insert(0, str(ROOT / "backend"))
os.environ["DATABASE_URL"] = f"sqlite:///{DB_PATH.as_posix()}"

from app.database import Base, SessionLocal, engine  # noqa: E402
from app.models import (  # noqa: E402
    AccountSnapshot,
    GuardrailSetting,
    NormalizedTrade,
    RawDeal,
    TradingAccount,
)
from app.services.guardrail_service import GuardrailService  # noqa: E402


Base.metadata.create_all(bind=engine)


def assert_true(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def utc(value: datetime) -> datetime:
    return value.replace(tzinfo=None)


def now_utc() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None, microsecond=0)


def add_account(db, login: str) -> TradingAccount:
    account = TradingAccount(
        name=login,
        broker="Pepperstone",
        server="Demo",
        login=login,
        currency="USD",
        is_active=True,
    )
    db.add(account)
    db.flush()
    settings = GuardrailSetting(
        account_id=account.id,
        max_daily_loss=1000,
        max_trades_per_day=2,
        max_risk_per_trade=300,
        block_high_impact_news=True,
        enabled=True,
        settings={
            "trade_blocking_enabled": True,
            "block_max_trades_per_day": True,
            "block_max_daily_loss": True,
            "fixed_risk_percent": 0.5,
            "loss_streak_block_count": 3,
            "loss_streak_block_minutes": 30,
            "cooling_off_after_loss_minutes": 15,
            "martingale_volume_multiplier": 1.5,
        },
    )
    db.add(settings)
    db.flush()
    return account


with SessionLocal() as db:
    service = GuardrailService(db)
    today = service._today()
    day_start = utc(datetime.combine(today, datetime.min.time()))
    morning = day_start + timedelta(hours=9)

    # Case 1: daily loss uses closed + floating, and max trades counts raw DEAL_ENTRY_IN
    account = add_account(db, "RULE-SMOKE-001")
    db.add(
        AccountSnapshot(
            account_id=account.id,
            captured_at=day_start - timedelta(minutes=1),
            balance=30000,
            equity=30000,
            margin=0,
            free_margin=30000,
            margin_level=None,
            profit=0,
            raw_payload={},
        )
    )
    db.add_all(
        [
            RawDeal(
                account_id=account.id,
                external_deal_id="deal-open-1",
                external_order_id="order-1",
                symbol="EURUSD",
                direction="buy",
                entry_type="in",
                volume=1.0,
                price=1.1,
                profit=0,
                commission=0,
                swap=0,
                deal_time=morning,
                comment="open",
                raw_payload={"entry": "in"},
            ),
            RawDeal(
                account_id=account.id,
                external_deal_id="deal-open-2",
                external_order_id="order-2",
                symbol="GBPUSD",
                direction="sell",
                entry_type="in",
                volume=1.0,
                price=1.2,
                profit=0,
                commission=0,
                swap=0,
                deal_time=morning + timedelta(minutes=30),
                comment="open",
                raw_payload={"entry": "in"},
            ),
        ]
    )
    db.add(
        NormalizedTrade(
            account_id=account.id,
            symbol="EURUSD",
            direction="buy",
            side="buy",
            volume=1.0,
            opened_at=morning,
            open_time=morning,
            closed_at=morning + timedelta(minutes=20),
            close_time=morning + timedelta(minutes=20),
            entry_price=1.1,
            open_price=1.1,
            exit_price=1.09,
            close_price=1.09,
            stop_loss=1.095,
            take_profit=None,
            commission=-5,
            swap=-2,
            gross_pnl=-600,
            profit=-600,
            net_pnl=-607,
            net_profit=-607,
            duration_seconds=1200,
            entry_reason="manual",
            exit_reason="manual close",
            risk_amount=150,
            r_multiple=-4.04,
            setup_tag="manual",
            session="asia",
            status="closed",
            source_deal_ids=["deal-open-1"],
        )
    )
    db.commit()

    status = service.status(
        account.id,
        trade_date=today,
        floating_pnl=200,
        open_positions=[
            {
                "symbol": "GBPUSD",
                "direction": "sell",
                "volume": 1.0,
                "profit": 200,
                "opened_at": (morning + timedelta(minutes=30)).isoformat(),
                "external_position_id": "position-2",
            }
        ],
    )
    check_map = {item["rule_code"]: item for item in status["checks"]}
    assert_true(
        check_map["max_daily_loss_reached"]["triggered"] is False,
        "Positive floating PnL should offset closed loss in daily loss check",
    )
    assert_true(
        check_map["too_many_trades_today"]["triggered"] is True,
        "Two entry deals with max 2 should trigger full-day max trades block",
    )

    # Case 2: revenge, cooling off, risk missing SL, martingale
    account2 = add_account(db, "RULE-SMOKE-002")
    db.add(
        AccountSnapshot(
            account_id=account2.id,
            captured_at=day_start - timedelta(minutes=1),
            balance=30000,
            equity=30000,
            margin=0,
            free_margin=30000,
            margin_level=None,
            profit=0,
            raw_payload={},
        )
    )
    current_utc = now_utc()
    loss_open = current_utc - timedelta(minutes=12)
    loss_close = current_utc - timedelta(minutes=10)
    fast_reentry = current_utc - timedelta(minutes=2)

    db.add_all(
        [
            RawDeal(
                account_id=account2.id,
                external_deal_id="loss-open",
                external_order_id="loss-order",
                symbol="USDJPY",
                direction="buy",
                entry_type="in",
                volume=1.0,
                price=160.0,
                profit=0,
                commission=0,
                swap=0,
                deal_time=loss_open,
                comment="open",
                raw_payload={"entry": "in"},
            ),
            RawDeal(
                account_id=account2.id,
                external_deal_id="loss-close",
                external_order_id="loss-order",
                symbol="USDJPY",
                direction="buy",
                entry_type="out",
                volume=1.0,
                price=159.5,
                profit=-100,
                commission=-2,
                swap=0,
                deal_time=loss_close,
                comment="stopped",
                raw_payload={"reason": "sl", "entry": "out"},
            ),
            RawDeal(
                account_id=account2.id,
                external_deal_id="reentry-open",
                external_order_id="reentry-order",
                symbol="USDJPY",
                direction="buy",
                entry_type="in",
                volume=2.0,
                price=159.6,
                profit=0,
                commission=0,
                swap=0,
                deal_time=fast_reentry,
                comment="open",
                raw_payload={"entry": "in"},
            ),
        ]
    )
    db.add_all(
        [
            NormalizedTrade(
                account_id=account2.id,
                symbol="USDJPY",
                direction="buy",
                side="buy",
                volume=1.0,
                opened_at=loss_open,
                open_time=loss_open,
                closed_at=loss_close,
                close_time=loss_close,
                entry_price=160.0,
                open_price=160.0,
                exit_price=159.5,
                close_price=159.5,
                stop_loss=159.5,
                take_profit=None,
                commission=-2,
                swap=0,
                gross_pnl=-100,
                profit=-100,
                net_pnl=-102,
                net_profit=-102,
                duration_seconds=300,
                entry_reason="manual",
                exit_reason="stopped",
                risk_amount=200,
                r_multiple=-0.51,
                setup_tag="manual",
                session="asia",
                status="closed",
                source_deal_ids=["loss-open", "loss-close"],
            ),
            NormalizedTrade(
                account_id=account2.id,
                symbol="USDJPY",
                direction="buy",
                side="buy",
                volume=2.0,
                opened_at=fast_reentry,
                open_time=fast_reentry,
                closed_at=None,
                close_time=None,
                entry_price=159.6,
                open_price=159.6,
                exit_price=None,
                close_price=None,
                stop_loss=None,
                take_profit=None,
                commission=0,
                swap=0,
                gross_pnl=0,
                profit=0,
                net_pnl=0,
                net_profit=0,
                duration_seconds=None,
                entry_reason="manual",
                exit_reason=None,
                risk_amount=None,
                r_multiple=None,
                setup_tag="manual",
                session="asia",
                status="open",
                source_deal_ids=["reentry-open"],
            ),
        ]
    )
    db.commit()

    status2 = service.status(
        account2.id,
        trade_date=today,
        open_positions=[
            {
                "symbol": "USDJPY",
                "direction": "buy",
                "volume": 1.0,
                "profit": -50,
                "opened_at": loss_open.isoformat(),
                "external_position_id": "anchor-loss",
            },
            {
                "symbol": "USDJPY",
                "direction": "buy",
                "volume": 2.0,
                "profit": -5,
                "opened_at": fast_reentry.isoformat(),
                "external_position_id": "martingale-live",
            },
        ],
        floating_pnl=-55,
    )
    check_map2 = {item["rule_code"]: item for item in status2["checks"]}
    assert_true(check_map2["revenge_trading_pattern"]["triggered"] is True, "Fast reentry after a loss should trigger revenge trade")
    assert_true(check_map2["cooling_off_active"]["triggered"] is True, "Stop-loss cooldown should be active after SL then fast reentry")
    assert_true(check_map2["risk_too_high"]["triggered"] is True, "Missing SL / missing risk amount should fail risk per trade")
    assert_true(check_map2["live_averaging_loss"]["triggered"] is True, "Adding same-direction live position while losing should trigger averaging loss")
    assert_true(check_map2["live_martingale"]["triggered"] is True, "Larger live position after a losing one should trigger live martingale")

print("discipline_rules_smoke: PASS")
