"""Smoke tests for guardrail settings lock behavior.

Run directly without extra dependencies:
    installer\python-runtime\python.exe backend\tests\test_settings_lock_smoke.py
"""
from datetime import datetime, timedelta, timezone
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / "backend" / ".deps"), str(ROOT / "backend")]

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from app.database import Base
from app.models import NormalizedTrade, TradingAccount
from app.schemas.guardrail import GuardrailSettingsPatch
from app.services.guardrail_service import GuardrailService


def build_session():
    engine = create_engine(
        "sqlite:///:memory:",
        connect_args={"check_same_thread": False},
    )
    Base.metadata.create_all(bind=engine)
    SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
    session = SessionLocal()
    account = TradingAccount(
        name="Settings Lock Smoke Account",
        broker="Test Broker",
        server="Test Server",
        login="settings-lock-smoke-1",
        currency="USD",
        timezone="UTC",
        is_active=True,
    )
    session.add(account)
    session.commit()
    session.refresh(account)
    return session, account.id


def add_trade_for_today(session, account_id: int) -> None:
    now = datetime.now(timezone.utc)
    trade = NormalizedTrade(
        account_id=account_id,
        symbol="EURUSD",
        direction="buy",
        side="buy",
        volume=0.1,
        opened_at=now,
        closed_at=now,
        open_time=now,
        close_time=now,
        entry_price=1.1,
        exit_price=1.2,
        gross_pnl=10.0,
        net_pnl=10.0,
        status="closed",
        source_deal_ids=[],
    )
    session.add(trade)
    session.commit()


def test_settings_apply_immediately_before_first_trade() -> None:
    session, account_id = build_session()
    try:
        service = GuardrailService(session)
        settings = service.patch_settings(
            account_id,
            GuardrailSettingsPatch(
                max_trades_per_day=2,
                settings={"trade_blocking_enabled": True},
            ),
        )

        assert settings.max_trades_per_day == 2
        assert settings.settings["trade_blocking_enabled"] is True
        assert "pending_update" not in settings.settings
    finally:
        session.close()


def test_settings_patch_after_trade_is_scheduled_for_next_day() -> None:
    session, account_id = build_session()
    try:
        service = GuardrailService(session)
        original = service.patch_settings(
            account_id,
            GuardrailSettingsPatch(max_trades_per_day=5),
        )
        add_trade_for_today(session, account_id)

        updated = service.patch_settings(
            account_id,
            GuardrailSettingsPatch(
                max_trades_per_day=1,
                settings={"trade_blocking_enabled": True},
            ),
        )
        pending = updated.settings.get("pending_update")

        assert original.max_trades_per_day == 5
        assert updated.max_trades_per_day == 5
        assert pending is not None
        assert pending["effective_date"] == (service._today() + timedelta(days=1)).isoformat()
        assert pending["changes"]["max_trades_per_day"] == 1
        assert pending["changes"]["settings"]["trade_blocking_enabled"] is True
    finally:
        session.close()


def test_pending_update_rolls_over_when_effective_date_arrives() -> None:
    session, account_id = build_session()
    try:
        service = GuardrailService(session)
        settings = service.patch_settings(
            account_id,
            GuardrailSettingsPatch(max_trades_per_day=5),
        )
        service._schedule_settings_for_next_day(
            settings,
            {
                "max_trades_per_day": 1,
                "settings": {"trade_blocking_enabled": True},
            },
            service._today(),
        )
        session.commit()

        rolled = service._get_or_create_settings(account_id)

        assert rolled.max_trades_per_day == 1
        assert rolled.settings["trade_blocking_enabled"] is True
        assert "pending_update" not in rolled.settings
    finally:
        session.close()


def test_guardrail_lock_payload_reports_editable_pending_and_blocked_states() -> None:
    session, account_id = build_session()
    try:
        service = GuardrailService(session)
        settings = service._get_or_create_settings(account_id)
        service._schedule_settings_for_next_day(
            settings,
            {"max_trades_per_day": 1},
            service._today() + timedelta(days=1),
        )
        session.commit()

        editable = service._guardrail_lock_payload(False, 0, settings, service._today())
        trade_locked = service._guardrail_lock_payload(False, 1, settings, service._today())
        block_locked = service._guardrail_lock_payload(True, 0, settings, service._today())

        assert editable["effective_today_locked"] is False
        assert editable["reason"] == "editable"
        assert editable["pending_update"] is not None
        assert editable["pending_update"]["active_for_date"] is False

        assert trade_locked["effective_today_locked"] is True
        assert trade_locked["tighten_only"] is True
        assert trade_locked["reason"] == "next_day_pending_only"

        assert block_locked["effective_today_locked"] is True
        assert block_locked["reason"] == "blocked_until_next_trading_day"
    finally:
        session.close()


if __name__ == "__main__":
    test_settings_apply_immediately_before_first_trade()
    test_settings_patch_after_trade_is_scheduled_for_next_day()
    test_pending_update_rolls_over_when_effective_date_arrives()
    test_guardrail_lock_payload_reports_editable_pending_and_blocked_states()
    print("test_settings_lock_smoke: PASS")
