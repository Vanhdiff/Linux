"""Backtest scenarios for Block Trade system.

This is a replay-style regression suite using in-memory SQLite. It does not
modify the real user database.

Run directly:
    installer\python-runtime\python.exe backend\tests\test_block_trade_backtest_scenarios.py
"""
from datetime import date, datetime, time, timedelta, timezone
from pathlib import Path
import json
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / "backend" / ".deps"), str(ROOT / "backend")]

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from app.application.mt5_protection import EACommunicationLayer, BlockStateSync
from app.database import Base
from app.infrastructure.persistence.block_repository import BlockRepository
from app.models import AccountSnapshot, NormalizedTrade, TradingAccount
from app.schemas.guardrail import GuardrailSettingsPatch, PreTradeValidationRequest
from app.services.guardrail_service import GuardrailService


TARGET_DATE = date(2026, 7, 7)


def build_session(login: str):
    engine = create_engine(
        "sqlite:///:memory:",
        connect_args={"check_same_thread": False},
    )
    Base.metadata.create_all(bind=engine)
    SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
    session = SessionLocal()
    account = TradingAccount(
        name=f"Backtest {login}",
        broker="Backtest Broker",
        server="Backtest Server",
        login=login,
        currency="USD",
        timezone="UTC",
        is_active=True,
    )
    session.add(account)
    session.commit()
    session.refresh(account)
    return session, account.id


def add_snapshot(session, account_id: int, balance: float = 10000.0) -> None:
    snapshot = AccountSnapshot(
        account_id=account_id,
        captured_at=datetime.combine(TARGET_DATE, time(hour=0, minute=1)),
        balance=balance,
        equity=balance,
        margin=0,
        free_margin=balance,
        margin_level=None,
        profit=0,
        raw_payload={},
    )
    session.add(snapshot)
    session.commit()


def add_closed_trade(
    session,
    account_id: int,
    idx: int,
    *,
    pnl: float = 10.0,
    opened_offset_minutes: int | None = None,
) -> None:
    trade_date = getattr(add_closed_trade, "target_date_override", TARGET_DATE)
    opened_at = datetime.combine(
        trade_date,
        time(hour=9, minute=0),
    ) + timedelta(minutes=opened_offset_minutes if opened_offset_minutes is not None else idx)
    closed_at = opened_at + timedelta(seconds=30)
    trade = NormalizedTrade(
        account_id=account_id,
        symbol="BTCUSD",
        direction="buy" if idx % 2 == 0 else "sell",
        side="buy" if idx % 2 == 0 else "sell",
        volume=10.0,
        opened_at=opened_at,
        closed_at=closed_at,
        open_time=opened_at,
        close_time=closed_at,
        entry_price=63000.0,
        exit_price=63010.0,
        open_price=63000.0,
        close_price=63010.0,
        stop_loss=62900.0,
        take_profit=63200.0,
        risk_amount=25.0,
        gross_pnl=pnl,
        net_pnl=pnl,
        status="closed",
        source_deal_ids=[idx],
    )
    session.add(trade)
    session.commit()


def rule(status: dict, code: str) -> dict:
    for item in status["checks"]:
        if item["rule_code"] == code:
            return item
    raise AssertionError(f"missing rule {code}")


def configure_blocking(service: GuardrailService, account_id: int, **kwargs) -> None:
    settings = {
        "trade_blocking_enabled": True,
        "block_max_trades_per_day": True,
        "block_max_daily_loss": True,
        "block_max_daily_profit": True,
    }
    settings.update(kwargs.pop("settings", {}))
    service.patch_settings(
        account_id,
        GuardrailSettingsPatch(
            max_trades_per_day=kwargs.pop("max_trades_per_day", 3),
            max_daily_loss=kwargs.pop("max_daily_loss", 3000.0),
            settings=settings,
            **kwargs,
        ),
    )


def assert_blocked(status: dict, block_type: str = "full_day") -> None:
    assert status["trade_blocking_enabled"] is True
    assert status["trade_blocked"] is True
    assert status["trade_block"]["blocked"] is True
    assert status["block_state"]["active"] is True
    assert status["block_state"]["block_type"] == block_type


def test_backtest_no_violation_allows_trade() -> None:
    session, account_id = build_session("bt-clear")
    try:
        add_snapshot(session, account_id)
        service = GuardrailService(session)
        configure_blocking(service, account_id, max_trades_per_day=3)
        add_closed_trade(session, account_id, 1)
        add_closed_trade(session, account_id, 2)

        status = service.status(account_id, trade_date=TARGET_DATE, floating_pnl=0)
        pretrade = service.pre_trade_validate(PreTradeValidationRequest(account_id=account_id))

        assert rule(status, "too_many_trades_today")["triggered"] is False
        assert status["trade_blocked"] is False
        assert status["block_state"]["active"] is False
        assert pretrade["decision"] == "ALLOW"
    finally:
        session.close()


def test_backtest_reaching_max_trades_blocks_full_day() -> None:
    session, account_id = build_session("bt-max-trades")
    try:
        add_snapshot(session, account_id)
        service = GuardrailService(session)
        configure_blocking(service, account_id, max_trades_per_day=3)
        for idx in range(1, 4):
            add_closed_trade(session, account_id, idx)

        status = service.status(account_id, trade_date=TARGET_DATE, floating_pnl=0)
        pretrade = service.pre_trade_validate(PreTradeValidationRequest(account_id=account_id))

        assert rule(status, "too_many_trades_today")["triggered"] is True
        assert rule(status, "too_many_trades_today")["payload"]["trade_count"] == 3
        assert_blocked(status, "full_day")
        assert pretrade["decision"] == "DENY"
    finally:
        session.close()


def test_backtest_exceeding_max_trades_stays_blocked() -> None:
    session, account_id = build_session("bt-over-max")
    try:
        add_snapshot(session, account_id)
        service = GuardrailService(session)
        configure_blocking(service, account_id, max_trades_per_day=3)
        for idx in range(1, 5):
            add_closed_trade(session, account_id, idx)

        status = service.status(account_id, trade_date=TARGET_DATE, floating_pnl=0)

        assert rule(status, "too_many_trades_today")["payload"]["trade_count"] == 4
        assert_blocked(status, "full_day")
    finally:
        session.close()


def test_backtest_blocking_disabled_reports_but_allows() -> None:
    session, account_id = build_session("bt-disabled")
    try:
        add_snapshot(session, account_id)
        service = GuardrailService(session)
        service.patch_settings(
            account_id,
            GuardrailSettingsPatch(
                max_trades_per_day=3,
                settings={
                    "trade_blocking_enabled": False,
                    "block_max_trades_per_day": True,
                },
            ),
        )
        for idx in range(1, 5):
            add_closed_trade(session, account_id, idx)

        status = service.status(account_id, trade_date=TARGET_DATE, floating_pnl=0)
        pretrade = service.pre_trade_validate(PreTradeValidationRequest(account_id=account_id))

        assert rule(status, "too_many_trades_today")["triggered"] is True
        assert status["trade_blocking_enabled"] is False
        assert status["trade_blocked"] is False
        assert status["trade_block"]["disabled_reason"] == "trade_blocking_disabled"
        assert pretrade["decision"] == "ALLOW"
    finally:
        session.close()


def test_backtest_settings_change_after_trade_is_pending_not_immediate() -> None:
    session, account_id = build_session("bt-pending")
    try:
        add_snapshot(session, account_id)
        service = GuardrailService(session)
        configure_blocking(service, account_id, max_trades_per_day=5)
        today = service._today()
        add_closed_trade.target_date_override = today
        try:
            add_closed_trade(session, account_id, 1)
        finally:
            delattr(add_closed_trade, "target_date_override")
        service.patch_settings(account_id, GuardrailSettingsPatch(max_trades_per_day=1))

        status = service.status(account_id, trade_date=today, floating_pnl=0)

        assert status["settings"]["max_trades_per_day"] == 5
        assert status["settings"]["settings"]["pending_update"] is not None
        assert status["guardrail_lock"]["pending_update"] is not None
        assert rule(status, "too_many_trades_today")["triggered"] is False
        assert status["trade_blocked"] is False
    finally:
        session.close()


def test_backtest_daily_loss_blocks_full_day() -> None:
    session, account_id = build_session("bt-loss")
    try:
        add_snapshot(session, account_id, balance=10000)
        service = GuardrailService(session)
        configure_blocking(service, account_id, max_trades_per_day=99, max_daily_loss=100)
        add_closed_trade(session, account_id, 1, pnl=-120)

        status = service.status(account_id, trade_date=TARGET_DATE, floating_pnl=0)

        assert rule(status, "max_daily_loss_reached")["triggered"] is True
        assert_blocked(status, "full_day")
    finally:
        session.close()


def test_backtest_temporary_risk_block_is_not_downgraded_after_full_day() -> None:
    session, account_id = build_session("bt-no-downgrade")
    try:
        add_snapshot(session, account_id)
        service = GuardrailService(session)
        configure_blocking(service, account_id, max_trades_per_day=1)
        add_closed_trade(session, account_id, 1)
        first = service.status(account_id, trade_date=TARGET_DATE, floating_pnl=0)
        assert_blocked(first, "full_day")

        second = service.status(account_id, trade_date=TARGET_DATE, floating_pnl=0)
        assert_blocked(second, "full_day")
    finally:
        session.close()


def test_backtest_mt5_file_sync_reflects_active_block() -> None:
    session, account_id = build_session("bt-mt5-sync")
    try:
        add_snapshot(session, account_id)
        service = GuardrailService(session)
        configure_blocking(service, account_id, max_trades_per_day=1)
        add_closed_trade(session, account_id, 1)
        status = service.status(account_id, trade_date=TARGET_DATE, floating_pnl=0)
        assert_blocked(status, "full_day")

        with tempfile.TemporaryDirectory() as tmp:
            sync = BlockStateSync(session, ea_layer=EACommunicationLayer(Path(tmp)))
            result = sync.sync_account(account_id)
            payload = json.loads((Path(tmp) / f"block_{account_id}.json").read_text())

        assert result["synced"] is True
        assert result["blocked"] is True
        assert payload["blocked"] is True
        assert payload["block_type"] == "full_day"
        assert "too_many_trades_today" in payload["triggered_by"]
    finally:
        session.close()


def test_backtest_repository_has_one_active_block_after_repeated_status_calls() -> None:
    session, account_id = build_session("bt-idempotent")
    try:
        add_snapshot(session, account_id)
        service = GuardrailService(session)
        configure_blocking(service, account_id, max_trades_per_day=1)
        add_closed_trade(session, account_id, 1)

        service.status(account_id, trade_date=TARGET_DATE, floating_pnl=0)
        service.status(account_id, trade_date=TARGET_DATE, floating_pnl=0)
        service.status(account_id, trade_date=TARGET_DATE, floating_pnl=0)

        repo = BlockRepository(session)
        history = repo.get_block_history(account_id, limit=10)
        active = [item for item in history if item.is_active()]

        assert len(active) == 1
        assert active[0].block_type.value == "full_day"
    finally:
        session.close()


if __name__ == "__main__":
    test_backtest_no_violation_allows_trade()
    test_backtest_reaching_max_trades_blocks_full_day()
    test_backtest_exceeding_max_trades_stays_blocked()
    test_backtest_blocking_disabled_reports_but_allows()
    test_backtest_settings_change_after_trade_is_pending_not_immediate()
    test_backtest_daily_loss_blocks_full_day()
    test_backtest_temporary_risk_block_is_not_downgraded_after_full_day()
    test_backtest_mt5_file_sync_reflects_active_block()
    test_backtest_repository_has_one_active_block_after_repeated_status_calls()
    print("test_block_trade_backtest_scenarios: PASS")
