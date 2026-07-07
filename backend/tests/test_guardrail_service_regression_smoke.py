"""Regression smoke tests for GuardrailService status flow.

Run directly without extra dependencies:
    installer\python-runtime\python.exe backend\tests\test_guardrail_service_regression_smoke.py
"""
from datetime import datetime, timezone
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


def build_session(login: str = "guardrail-regression-1"):
    engine = create_engine(
        "sqlite:///:memory:",
        connect_args={"check_same_thread": False},
    )
    Base.metadata.create_all(bind=engine)
    SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
    session = SessionLocal()
    account = TradingAccount(
        name="Guardrail Regression Account",
        broker="Test Broker",
        server="Test Server",
        login=login,
        currency="USD",
        timezone="UTC",
        is_active=True,
    )
    session.add(account)
    session.commit()
    session.refresh(account)
    return session, account.id


def add_closed_trade(session, account_id: int, suffix: int = 1) -> None:
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
        source_deal_ids=[suffix],
    )
    session.add(trade)
    session.commit()


def check_by_code(status: dict, rule_code: str) -> dict:
    for check in status["checks"]:
        if check["rule_code"] == rule_code:
            return check
    raise AssertionError(f"Missing check: {rule_code}")


def test_default_status_is_clear_and_read_only() -> None:
    session, account_id = build_session("guardrail-regression-default")
    try:
        service = GuardrailService(session)

        status = service.status(account_id)

        assert status["account_id"] == account_id
        assert status["mode"] == "local_read_only"
        assert status["trade_blocking_enabled"] is False
        assert status["trade_blocked"] is False
        assert status["trade_block"]["blocked"] is False
        assert status["block_state"]["active"] is False
        assert status["status"] == "clear"
        assert status["summary"]["triggered_count"] == 0
        assert status["guardrail_lock"]["reason"] == "editable"
    finally:
        session.close()


def test_disabled_guardrail_status_never_blocks() -> None:
    session, account_id = build_session("guardrail-regression-disabled")
    try:
        service = GuardrailService(session)
        settings = service._get_or_create_settings(account_id)
        settings.enabled = False
        session.commit()

        status = service.status(account_id)

        assert status["enabled"] is False
        assert status["status"] == "disabled"
        assert status["trade_blocked"] is False
        assert status["trade_block"]["reasons"] == []
        assert status["checks"] == []
        assert status["block_state"]["active"] is False
    finally:
        session.close()


def test_max_trades_with_trade_blocking_creates_block_and_pretrade_denies() -> None:
    session, account_id = build_session("guardrail-regression-block")
    try:
        service = GuardrailService(session)
        service.patch_settings(
            account_id,
            GuardrailSettingsPatch(
                max_trades_per_day=1,
                settings={"trade_blocking_enabled": True},
            ),
        )
        add_closed_trade(session, account_id)

        status = service.status(account_id)
        pretrade = service.trade_block_status(account_id)
        max_trades_check = check_by_code(status, "too_many_trades_today")

        assert max_trades_check["triggered"] is True
        assert status["mode"] == "mt5_enforcement"
        assert status["trade_blocking_enabled"] is True
        assert status["trade_blocked"] is True
        assert status["trade_block"]["blocked"] is True
        assert status["trade_block"]["reason_count"] >= 1
        assert any(
            reason["rule_code"] == "too_many_trades_today"
            for reason in status["trade_block"]["reasons"]
        )
        assert status["block_state"]["active"] is True
        assert status["block_state"]["block_type"] == "full_day"
        assert status["status"] == "blocked"
        assert status["guardrail_lock"]["effective_today_locked"] is True
        assert status["guardrail_lock"]["reason"] == "blocked_until_next_trading_day"

        assert pretrade["allowed"] is False
        assert pretrade["blocked"] is True
        assert pretrade["block_state"]["active"] is True
    finally:
        session.close()


if __name__ == "__main__":
    test_default_status_is_clear_and_read_only()
    test_disabled_guardrail_status_never_blocks()
    test_max_trades_with_trade_blocking_creates_block_and_pretrade_denies()
    print("test_guardrail_service_regression_smoke: PASS")
