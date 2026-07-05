import os
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path


ROOT = Path(r"E:\Tradingapp\epp_tr-desktop")
DB_PATH = ROOT / ".tmp" / "max_trades_block_smoke.db"
if DB_PATH.exists():
    DB_PATH.unlink()
DB_PATH.parent.mkdir(parents=True, exist_ok=True)
DB_PATH.touch()

sys.path.insert(0, str(ROOT / "backend" / ".deps"))
sys.path.insert(0, str(ROOT / "backend"))
os.environ["DATABASE_URL"] = f"sqlite:///{DB_PATH.as_posix()}"

from app.database import Base, engine, SessionLocal  # noqa: E402
from app.models import GuardrailSetting, RawDeal, TradingAccount  # noqa: E402
from app.schemas.guardrail import GuardrailSettingsPatch  # noqa: E402
from app.services.guardrail_service import GuardrailService  # noqa: E402


Base.metadata.create_all(bind=engine)


def assert_true(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def utc_now() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None, microsecond=0)


with SessionLocal() as db:
    account = TradingAccount(
        name="Smoke Account",
        broker="Pepperstone",
        server="Demo",
        login="SMOKE-OPEN-001",
        currency="USD",
        is_active=True,
    )
    db.add(account)
    db.flush()

    settings = GuardrailSetting(
        account_id=account.id,
        max_daily_loss=3000,
        max_trades_per_day=1,
        max_risk_per_trade=300,
        block_high_impact_news=True,
        enabled=True,
        settings={
            "trade_blocking_enabled": True,
            "block_max_trades_per_day": True,
        },
    )
    db.add(settings)
    db.commit()

    now = utc_now()

    db.add(
        RawDeal(
            account_id=account.id,
            external_deal_id="deal-1",
            external_order_id="order-1",
            symbol="USDJPY",
            direction="buy",
            entry_type="in",
            volume=1.0,
            price=160.992,
            profit=0,
            commission=0,
            swap=0,
            deal_time=now,
            comment="open",
            raw_payload={"entry": "in"},
        )
    )
    db.commit()

    service = GuardrailService(db)
    status_from_open_trade = service.status(account.id, trade_date=service._today())
    assert_true(
        status_from_open_trade["trade_blocked"] is True,
        "Raw entry deal should count toward max trades block",
    )
    assert_true(
        any(
            item["rule_code"] == "too_many_trades_today" and item["triggered"]
            for item in status_from_open_trade["checks"]
        ),
        "too_many_trades_today should be triggered for raw entry deal",
    )
    assert_true(
        status_from_open_trade["guardrail_lock"]["trade_count"] == 1,
        "Guardrail lock should count raw entry deal",
    )

    patch = GuardrailSettingsPatch(max_daily_loss=2500)
    service.patch_settings(account.id, patch)
    db.refresh(settings)
    pending_update = (settings.settings or {}).get("pending_update") or {}
    assert_true(
        pending_update.get("effective_date") is not None,
        "Raw entry deal should lock same-day guardrail edits into pending update",
    )

with SessionLocal() as db:
    account = TradingAccount(
        name="Live Position Account",
        broker="Pepperstone",
        server="Demo",
        login="SMOKE-LIVE-001",
        currency="USD",
        is_active=True,
    )
    db.add(account)
    db.flush()

    settings = GuardrailSetting(
        account_id=account.id,
        max_daily_loss=3000,
        max_trades_per_day=1,
        max_risk_per_trade=300,
        block_high_impact_news=True,
        enabled=True,
        settings={
            "trade_blocking_enabled": True,
            "block_max_trades_per_day": True,
        },
    )
    db.add(settings)
    db.commit()

    now = utc_now()
    live_position = {
        "symbol": "EURUSD",
        "direction": "buy",
        "volume": 0.5,
        "profit": -8.7,
        "opened_at": now.isoformat(),
        "external_position_id": "position-1",
    }

    service = GuardrailService(db)
    status_from_live_position = service.status(
        account.id,
        trade_date=service._today(),
        open_positions=[live_position],
        floating_pnl=-8.7,
    )
    assert_true(
        status_from_live_position["trade_blocked"] is True,
        "Live MT5 position should count toward max trades block",
    )
    assert_true(
        status_from_live_position["guardrail_lock"]["trade_count"] == 1,
        "Guardrail lock should count live MT5 position",
    )

print("max_trades_block_smoke: PASS")
