"""Audit tests for MT5 data mapping and guardrail field usage.

Run directly:
    installer\python-runtime\python.exe backend\tests\test_mt5_data_correctness_audit.py
"""
from datetime import date, datetime, time, timezone
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / "backend" / ".deps"), str(ROOT / "backend")]

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from app.database import Base
from app.models import AccountSnapshot, NormalizedTrade, RawDeal, TradingAccount
from app.schemas.mt5 import Mt5AccountSnapshotIn, Mt5DealsIn, Mt5PositionsIn
from app.schemas.mt5 import Mt5SyncRequest
from app.schemas.guardrail import GuardrailSettingsPatch
from app.services.import_service import Mt5IngestionService
from app.services.mt5_sync_service import Mt5SyncService
from app.services.normalize_service import NormalizationService
from app.services.guardrail_service import GuardrailService
from app.services.view_model_service import ViewModelService


TARGET_DATE = date(2026, 7, 8)


def build_session():
    engine = create_engine(
        "sqlite:///:memory:",
        connect_args={"check_same_thread": False},
    )
    Base.metadata.create_all(bind=engine)
    SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
    session = SessionLocal()
    account = TradingAccount(
        name="MT5 Audit Account",
        broker="Pepperstone Demo",
        server="Pepperstone-Demo",
        login="61552390",
        currency="USD",
        timezone="UTC",
        is_active=True,
    )
    session.add(account)
    session.commit()
    session.refresh(account)
    return session, account.id


def test_account_snapshot_maps_mt5_fields_exactly() -> None:
    session, account_id = build_session()
    try:
        ingestion = Mt5IngestionService(session)
        ingestion.save_account_snapshot(
            Mt5AccountSnapshotIn(
                account_id=account_id,
                captured_at=datetime(2026, 7, 8, 0, 0, tzinfo=timezone.utc),
                snapshot={
                    "balance": 48267.76,
                    "equity": 48084.36,
                    "margin": 1568.63,
                    "margin_free": 46515.73,
                    "margin_level": 3065.37,
                    "profit": -183.40,
                },
            )
        )
        snapshot = session.query(__import__("app.models", fromlist=["AccountSnapshot"]).AccountSnapshot).one()

        assert snapshot.balance == 48267.76
        assert snapshot.equity == 48084.36
        assert snapshot.margin == 1568.63
        assert snapshot.free_margin == 46515.73
        assert snapshot.margin_level == 3065.37
        assert snapshot.profit == -183.40
    finally:
        session.close()


class FakeMt5Service:
    def __init__(self, login: str) -> None:
        self.login = login

    def account(self, payload=None) -> dict:
        return {
            "login": self.login,
            "name": "Switched Demo",
            "company": "Pepperstone Demo",
            "server": "Pepperstone-Demo",
            "currency": "USD",
            "balance": 88437.81,
            "equity": 88437.81,
            "margin": 0,
            "margin_free": 88437.81,
            "margin_level": None,
            "profit": 0,
        }

    def positions(self, payload=None) -> list[dict]:
        return []

    def orders(self, payload=None) -> list[dict]:
        return []

    def history(self, *, date_from=None, date_to=None, history_days=30, payload=None) -> list[dict]:
        return [
            {
                "external_deal_id": "switched-close-1",
                "external_order_id": "switched-order-1",
                "position_id": "switched-position-1",
                "symbol": "EURUSD",
                "direction": "buy",
                "entry_type": "out",
                "volume": 1.0,
                "price": 1.1,
                "profit": 0.0,
                "commission": 0.0,
                "swap": 0.0,
                "time": datetime.now(timezone.utc),
                "comment": "switched account",
            }
        ]


def test_mt5_login_switch_does_not_overwrite_previous_account() -> None:
    session, previous_account_id = build_session()
    try:
        previous = session.get(TradingAccount, previous_account_id)
        assert previous is not None
        previous_login = previous.login

        result = Mt5SyncService(
            session,
            mt5_service=FakeMt5Service("8843781"),
        ).import_live_state(
            Mt5SyncRequest(
                account_id=previous_account_id,
                include_positions=True,
                include_orders=True,
                include_deals=False,
            )
        )

        session.refresh(previous)
        switched = session.get(TradingAccount, result.account_id)

        assert result.account_id != previous_account_id
        assert previous.login == previous_login
        assert previous.is_active is False
        assert switched is not None
        assert switched.login == "8843781"
        assert switched.is_active is True
    finally:
        session.close()


def test_incremental_sync_uses_resolved_mt5_account_after_login_switch() -> None:
    session, previous_account_id = build_session()
    try:
        previous = session.get(TradingAccount, previous_account_id)
        assert previous is not None
        previous_login = previous.login

        result = Mt5SyncService(
            session,
            mt5_service=FakeMt5Service("8843782"),
        ).import_incremental_deals(
            account_id=previous_account_id,
            history_days=3,
            overlap_minutes=5,
        )

        session.refresh(previous)
        switched = session.get(TradingAccount, result.account_id)
        old_deals = session.query(RawDeal).filter(
            RawDeal.account_id == previous_account_id
        ).all()
        new_deals = session.query(RawDeal).filter(
            RawDeal.account_id == result.account_id
        ).all()

        assert result.account_id != previous_account_id
        assert previous.login == previous_login
        assert previous.is_active is False
        assert switched is not None
        assert switched.login == "8843782"
        assert switched.is_active is True
        assert old_deals == []
        assert len(new_deals) == 1
    finally:
        session.close()


def test_guardrail_account_value_does_not_fallback_to_other_account_snapshot() -> None:
    session, account_id = build_session()
    try:
        other = TradingAccount(
            name="Other Account",
            broker="Pepperstone Demo",
            server="Pepperstone-Demo",
            login="999999",
            currency="USD",
            timezone="UTC",
            is_active=True,
        )
        session.add(other)
        session.commit()
        session.refresh(other)
        session.add(
            AccountSnapshot(
                account_id=other.id,
                captured_at=datetime(2026, 7, 8, 0, 0, tzinfo=timezone.utc),
                balance=999999,
                equity=999999,
                margin=0,
                free_margin=999999,
                margin_level=None,
                profit=0,
                raw_payload={},
            )
        )
        session.commit()

        service = GuardrailService(session)
        service.patch_settings(
            account_id,
            GuardrailSettingsPatch(
                max_risk_per_trade=123,
                settings={
                    "trade_blocking_enabled": True,
                    "fixed_risk_percent": 1,
                },
            ),
        )
        status = service.status(account_id, trade_date=TARGET_DATE)
        by_code = {check["rule_code"]: check for check in status["checks"]}

        assert by_code["risk_too_high"]["payload"]["max_risk_per_trade"] == 123
    finally:
        session.close()


def test_empty_position_import_clears_latest_live_positions() -> None:
    session, account_id = build_session()
    try:
        ingestion = Mt5IngestionService(session)
        ingestion.save_positions(
            Mt5PositionsIn(
                account_id=account_id,
                captured_at=datetime(2026, 7, 8, 8, 0, tzinfo=timezone.utc),
                positions=[
                    {
                        "external_position_id": "open-1",
                        "symbol": "BTCUSD",
                        "direction": "buy",
                        "volume": 1,
                        "open_price": 100,
                        "current_price": 90,
                        "profit": -100,
                        "time": datetime(2026, 7, 8, 7, 55, tzinfo=timezone.utc),
                    },
                    {
                        "external_position_id": "open-2",
                        "symbol": "BTCUSD",
                        "direction": "buy",
                        "volume": 1,
                        "open_price": 100,
                        "current_price": 80,
                        "profit": -200,
                        "time": datetime(2026, 7, 8, 7, 56, tzinfo=timezone.utc),
                    },
                ],
            )
        )
        ingestion.save_positions(
            Mt5PositionsIn(
                account_id=account_id,
                captured_at=datetime(2026, 7, 8, 8, 1, tzinfo=timezone.utc),
                positions=[],
            )
        )

        service = GuardrailService(session)
        status = service.status(account_id, trade_date=TARGET_DATE)
        live_state = ViewModelService(session).live_state(account_id)
        by_code = {check["rule_code"]: check for check in status["checks"]}

        assert by_code["max_daily_loss_reached"]["payload"]["floating_pnl"] == 0
        assert by_code["live_averaging_loss"]["payload"]["violation_count"] == 0
        assert live_state["positions"]["open_position_count"] == 0
        assert live_state["positions"]["floating_pnl"] == 0
    finally:
        session.close()


def test_deal_ingestion_and_normalization_use_profit_commission_swap_correctly() -> None:
    session, account_id = build_session()
    try:
        ingestion = Mt5IngestionService(session)
        opened_at = datetime.combine(TARGET_DATE, time(hour=7, minute=13, second=46), tzinfo=timezone.utc)
        closed_at = datetime.combine(TARGET_DATE, time(hour=7, minute=14, second=30), tzinfo=timezone.utc)
        ingestion.save_deals(
            Mt5DealsIn(
                account_id=account_id,
                deals=[
                    {
                        "external_deal_id": "open-1",
                        "external_order_id": "order-1",
                        "position_id": "pos-1",
                        "symbol": "BTCUSD",
                        "direction": "sell",
                        "entry_type": "in",
                        "volume": 10.0,
                        "price": 62745.21,
                        "profit": 0.0,
                        "commission": -1.25,
                        "swap": 0.0,
                        "time": opened_at,
                        "comment": "entry",
                    },
                    {
                        "external_deal_id": "close-1",
                        "external_order_id": "order-2",
                        "position_id": "pos-1",
                        "symbol": "BTCUSD",
                        "direction": "sell",
                        "entry_type": "out",
                        "volume": 10.0,
                        "price": 62763.55,
                        "profit": -183.40,
                        "commission": -1.25,
                        "swap": -0.10,
                        "time": closed_at,
                        "comment": "exit",
                    },
                ],
            )
        )
        result = NormalizationService(session).sync_account(account_id)
        trade = session.query(__import__("app.models", fromlist=["NormalizedTrade"]).NormalizedTrade).one()
        raw_deals = session.query(RawDeal).order_by(RawDeal.deal_time.asc()).all()

        assert result.created == 1
        assert len(raw_deals) == 2
        assert raw_deals[0].profit == 0.0
        assert raw_deals[1].profit == -183.40
        assert trade.symbol == "BTCUSD"
        assert trade.direction == "sell"
        assert trade.volume == 10.0
        assert trade.entry_price == 62745.21
        assert trade.exit_price == 62763.55
        assert trade.gross_pnl == -183.40
        assert trade.commission == -2.50
        assert trade.swap == -0.10
        assert trade.net_pnl == -186.0
        assert trade.profit == -183.40
        assert trade.net_profit == -186.0
    finally:
        session.close()


def test_guardrail_daily_loss_and_profit_use_correct_signs_and_messages() -> None:
    session, account_id = build_session()
    try:
        service = GuardrailService(session)
        service.patch_settings(
            account_id,
            GuardrailSettingsPatch(
                max_daily_loss=3000,
                settings={
                    "trade_blocking_enabled": True,
                    "max_daily_profit": 5000,
                    "block_max_daily_loss": True,
                    "block_max_daily_profit": True,
                },
            ),
        )
        # One losing trade and floating loss, but total loss is far below 3000.
        ingestion = Mt5IngestionService(session)
        ingestion.save_account_snapshot(
            Mt5AccountSnapshotIn(
                account_id=account_id,
                captured_at=datetime.combine(TARGET_DATE, time.min, tzinfo=timezone.utc),
                snapshot={"balance": 50000, "equity": 50000, "margin": 0, "free_margin": 50000, "profit": 0},
            )
        )
        ingestion.save_deals(
            Mt5DealsIn(
                account_id=account_id,
                deals=[
                    {
                        "external_deal_id": "open-loss",
                        "position_id": "loss-pos",
                        "symbol": "BTCUSD",
                        "direction": "sell",
                        "entry_type": "in",
                        "volume": 10,
                        "price": 62745.21,
                        "profit": 0,
                        "commission": 0,
                        "swap": 0,
                        "time": datetime.combine(TARGET_DATE, time(hour=7), tzinfo=timezone.utc),
                    },
                    {
                        "external_deal_id": "close-loss",
                        "position_id": "loss-pos",
                        "symbol": "BTCUSD",
                        "direction": "sell",
                        "entry_type": "out",
                        "volume": 10,
                        "price": 62763.55,
                        "profit": -628.5,
                        "commission": 0,
                        "swap": 0,
                        "time": datetime.combine(TARGET_DATE, time(hour=7, minute=5), tzinfo=timezone.utc),
                    },
                ],
            )
        )
        NormalizationService(session).sync_account(account_id)

        status = service.status(account_id, trade_date=TARGET_DATE, floating_pnl=-407.8)
        by_code = {check["rule_code"]: check for check in status["checks"]}
        loss = by_code["max_daily_loss_reached"]
        profit = by_code["max_daily_profit_reached"]

        assert loss["payload"]["closed_pnl"] == -628.5
        assert loss["payload"]["floating_pnl"] == -407.8
        assert loss["payload"]["effective_pnl"] == -1036.3
        assert loss["payload"]["max_daily_loss"] == 3000
        assert loss["triggered"] is False
        assert "has not reached" in loss["message"]

        assert profit["payload"]["net_pnl"] == -628.5
        assert profit["payload"]["max_daily_profit"] == 5000
        assert profit["triggered"] is False
        assert "has not reached" in profit["message"]
    finally:
        session.close()


def test_normalization_repairs_duplicate_source_deal_rows() -> None:
    session, account_id = build_session()
    try:
        ingestion = Mt5IngestionService(session)
        ingestion.save_deals(
            Mt5DealsIn(
                account_id=account_id,
                deals=[
                    {
                        "external_deal_id": "dup-open",
                        "position_id": "dup-pos",
                        "symbol": "EURUSD",
                        "direction": "buy",
                        "entry_type": "in",
                        "volume": 1,
                        "price": 1.10,
                        "profit": 0,
                        "commission": 0,
                        "swap": 0,
                        "time": datetime.combine(
                            TARGET_DATE,
                            time(hour=9),
                            tzinfo=timezone.utc,
                        ),
                    },
                    {
                        "external_deal_id": "dup-close",
                        "position_id": "dup-pos",
                        "symbol": "EURUSD",
                        "direction": "buy",
                        "entry_type": "out",
                        "volume": 1,
                        "price": 1.11,
                        "profit": 100,
                        "commission": 0,
                        "swap": 0,
                        "time": datetime.combine(
                            TARGET_DATE,
                            time(hour=9, minute=5),
                            tzinfo=timezone.utc,
                        ),
                    },
                ],
            )
        )
        duplicate_payload = {
            "account_id": account_id,
            "symbol": "EURUSD",
            "direction": "buy",
            "side": "buy",
            "volume": 1,
            "opened_at": datetime.combine(
                TARGET_DATE,
                time(hour=9),
                tzinfo=timezone.utc,
            ),
            "open_time": datetime.combine(
                TARGET_DATE,
                time(hour=9),
                tzinfo=timezone.utc,
            ),
            "closed_at": datetime.combine(
                TARGET_DATE,
                time(hour=9, minute=5),
                tzinfo=timezone.utc,
            ),
            "close_time": datetime.combine(
                TARGET_DATE,
                time(hour=9, minute=5),
                tzinfo=timezone.utc,
            ),
            "entry_price": 1.10,
            "open_price": 1.10,
            "exit_price": 1.11,
            "close_price": 1.11,
            "commission": 0,
            "swap": 0,
            "gross_pnl": 100,
            "profit": 100,
            "net_pnl": 100,
            "net_profit": 100,
            "status": "closed",
            "source_deal_ids": ["dup-close", "dup-open"],
        }
        session.add(NormalizedTrade(**duplicate_payload))
        session.add(NormalizedTrade(**duplicate_payload))
        session.commit()

        result = NormalizationService(session).sync_account(account_id)

        rows = (
            session.query(NormalizedTrade)
            .filter(
                NormalizedTrade.account_id == account_id,
                NormalizedTrade.source_deal_ids == ["dup-close", "dup-open"],
            )
            .all()
        )
        assert result.updated == 1
        assert len(rows) == 1
        assert rows[0].net_pnl == 100
    finally:
        session.close()


if __name__ == "__main__":
    test_account_snapshot_maps_mt5_fields_exactly()
    test_mt5_login_switch_does_not_overwrite_previous_account()
    test_incremental_sync_uses_resolved_mt5_account_after_login_switch()
    test_guardrail_account_value_does_not_fallback_to_other_account_snapshot()
    test_empty_position_import_clears_latest_live_positions()
    test_deal_ingestion_and_normalization_use_profit_commission_swap_correctly()
    test_guardrail_daily_loss_and_profit_use_correct_signs_and_messages()
    print("test_mt5_data_correctness_audit: PASS")
