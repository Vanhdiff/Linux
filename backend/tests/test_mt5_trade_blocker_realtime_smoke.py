"""Smoke tests for realtime MT5 trade blocker file sync.

Run directly:
    installer\python-runtime\python.exe backend\tests\test_mt5_trade_blocker_realtime_smoke.py
"""
from datetime import datetime, timezone
from pathlib import Path
import json
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / "backend" / ".deps"), str(ROOT / "backend")]

from sqlalchemy import create_engine
from sqlalchemy.exc import OperationalError
from sqlalchemy.orm import sessionmaker

from app.application.mt5_protection import EACommunicationLayer
from app.database import Base
from app.models import NormalizedTrade, RawDeal, TradingAccount
from app.schemas.guardrail import GuardrailSettingsPatch
from app.services.guardrail_service import GuardrailService
from app.services.mt5_trade_blocker import Mt5TradeBlocker


class FakeMt5Service:
    def account(self, payload=None):
        return {
            "login": "realtime-blocker",
            "name": "Realtime Blocker Account",
            "company": "Test Broker",
            "server": "Test Server",
            "currency": "USD",
            "balance": 1000,
            "equity": 1000,
            "margin": 0,
            "free_margin": 1000,
            "profit": 0,
        }

    def positions(self, payload=None):
        return []

    def orders(self, payload=None):
        return []

    def history(self, *, date_from=None, date_to=None, history_days=30, payload=None):
        return [
            {
                "external_deal_id": "9001",
                "external_order_id": "8001",
                "symbol": "BTCUSD",
                "direction": "buy",
                "entry_type": "out",
                "volume": 1.0,
                "price": 63050,
                "profit": 12.0,
                "commission": -1.0,
                "swap": 0.0,
                "time": datetime.now(timezone.utc).isoformat(),
                "comment": "incremental",
                "position_id": "pos-1",
            }
        ]

    def enforce_trade_block(self, *, blocked_since):
        return {
            "deleted_orders": [101],
            "closed_positions": [202],
            "failed_actions": [],
            "blocked_since": blocked_since.isoformat(),
        }


class MismatchedMt5Service(FakeMt5Service):
    def account(self, payload=None):
        data = super().account(payload)
        data["login"] = "different-live-account"
        return data


class NoopBlocker(Mt5TradeBlocker):
    def _sync_account_if_due(self, db, account_id: int):
        return {"attempted": False, "synced": False, "reason": "test_skip_raw_mt5_sync"}


class FailingSyncBlocker(Mt5TradeBlocker):
    def _sync_account_if_due(self, db, account_id: int):
        raise AssertionError("Fast-path blocked enforcement must not wait for raw MT5 sync")


class LockedNormalizationBlocker(Mt5TradeBlocker):
    def _normalize_account(self, db, account_id: int):
        raise OperationalError("update normalized_trades", {}, Exception("database is locked"))


def build_session():
    engine = create_engine(
        "sqlite:///:memory:",
        connect_args={"check_same_thread": False},
    )
    Base.metadata.create_all(bind=engine)
    SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
    session = SessionLocal()
    account = TradingAccount(
        name="Realtime Blocker Account",
        broker="Test Broker",
        server="Test Server",
        login="realtime-blocker",
        currency="USD",
        timezone="UTC",
        is_active=True,
    )
    session.add(account)
    session.commit()
    session.refresh(account)
    return session, account.id


def add_closed_trade(session, account_id: int):
    now = datetime.now(timezone.utc)
    trade = NormalizedTrade(
        account_id=account_id,
        symbol="BTCUSD",
        direction="buy",
        side="buy",
        volume=1.0,
        opened_at=now,
        closed_at=now,
        open_time=now,
        close_time=now,
        entry_price=63000,
        exit_price=63010,
        open_price=63000,
        close_price=63010,
        stop_loss=62900,
        take_profit=63200,
        risk_amount=25,
        gross_pnl=10,
        net_pnl=10,
        status="closed",
        source_deal_ids=[1],
    )
    session.add(trade)
    session.commit()


def test_blocker_writes_block_file_immediately_when_blocked() -> None:
    session, account_id = build_session()
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
        with tempfile.TemporaryDirectory() as tmp:
            blocker = NoopBlocker(mt5_service=FakeMt5Service(), poll_seconds=0.05)
            blocker._ea_layer = EACommunicationLayer(Path(tmp))

            result = blocker._enforce_account(session, account_id)
            payload = json.loads((Path(tmp) / f"block_{account_id}.json").read_text())

            assert result["blocked"] is True
            assert result["allowed"] is False
            assert result["block_file_sync"]["attempted"] is True
            assert result["block_file_sync"]["synced"] is True
            assert result["watchdog_summary"]["attempted"] is True
            assert result["watchdog_summary"]["deleted_order_count"] == 1
            assert result["watchdog_summary"]["closed_position_count"] == 1
            assert result["watchdog_summary"]["failed_action_count"] == 0
            assert result["watchdog_summary"]["ok"] is True
            assert payload["blocked"] is True
            assert payload["block_type"] == "full_day"
            assert "too_many_trades_today" in payload["triggered_by"]
    finally:
        session.close()


def test_blocker_skips_enforcement_when_mt5_login_does_not_match_account() -> None:
    session, account_id = build_session()
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
        with tempfile.TemporaryDirectory() as tmp:
            blocker = NoopBlocker(
                mt5_service=MismatchedMt5Service(),
                poll_seconds=0.05,
            )
            blocker._ea_layer = EACommunicationLayer(Path(tmp))

            result = blocker._enforce_account(session, account_id)

            assert result["blocked"] is False
            assert result["allowed"] is False
            assert result["reason"] == "mt5_login_mismatch"
            assert result["account_login"] == "realtime-blocker"
            assert result["mt5_login"] == "different-live-account"
            assert result["block_file_sync"]["attempted"] is False
            assert not (Path(tmp) / f"block_{account_id}.json").exists()
    finally:
        session.close()


def test_blocked_fast_path_skips_raw_sync_and_reports_under_target() -> None:
    session, account_id = build_session()
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
        with tempfile.TemporaryDirectory() as tmp:
            blocker = FailingSyncBlocker(mt5_service=FakeMt5Service(), poll_seconds=0.05)
            blocker._ea_layer = EACommunicationLayer(Path(tmp))

            result = blocker._enforce_account(session, account_id)

            assert result["blocked"] is True
            assert result["sync"]["reason"] == "fast_path_active_block"
            assert result["latency"]["target_ms"] == 500
            assert result["latency"]["within_target"] is True
            assert result["latency"]["block_file_sync_ms"] is not None
            assert result["latency"]["watchdog_ms"] is not None
    finally:
        session.close()


def test_existing_active_block_uses_fast_path_without_full_rule_recompute() -> None:
    session, account_id = build_session()
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
        service.trade_block_status(account_id, floating_pnl=0, open_positions=[])

        with tempfile.TemporaryDirectory() as tmp:
            blocker = NoopBlocker(mt5_service=FakeMt5Service(), poll_seconds=0.05)
            blocker._ea_layer = EACommunicationLayer(Path(tmp))

            result = blocker._enforce_account(session, account_id)

            assert result["blocked"] is True
            assert result["sync"]["reason"] == "fast_path_existing_block"
            assert result["latency"]["within_target"] is True
            assert result["block_file_sync"]["synced"] is True
    finally:
        session.close()


def test_blocker_clears_block_file_when_not_blocked() -> None:
    session, account_id = build_session()
    try:
        with tempfile.TemporaryDirectory() as tmp:
            blocker = NoopBlocker(mt5_service=FakeMt5Service(), poll_seconds=0.05)
            blocker._ea_layer = EACommunicationLayer(Path(tmp))

            result = blocker._enforce_account(session, account_id)
            payload = json.loads((Path(tmp) / f"block_{account_id}.json").read_text())

            assert result["blocked"] is False
            assert result["block_file_sync"]["attempted"] is True
            assert result["block_file_sync"]["synced"] is True
            assert payload["blocked"] is False
    finally:
        session.close()


def test_non_blocked_enforcement_uses_cached_background_sync_status() -> None:
    session, account_id = build_session()
    try:
        with tempfile.TemporaryDirectory() as tmp:
            blocker = Mt5TradeBlocker(mt5_service=FakeMt5Service(), poll_seconds=0.05)
            blocker._ea_layer = EACommunicationLayer(Path(tmp))
            blocker._last_incremental_sync_result_by_account[account_id] = {
                "attempted": True,
                "synced": True,
                "source": "incremental_deal_sync",
                "reason": "background_sync_complete",
                "last_sync_at": datetime.now(timezone.utc).isoformat(),
            }

            result = blocker._enforce_account(session, account_id)

            assert result["blocked"] is False
            assert result["allowed"] is True
            assert result["sync"]["source"] == "incremental_deal_sync"
            assert result["sync"]["reason"] == "background_sync_complete"
            assert result["live_poll"]["reason"] == "background_poll_not_run_yet"
            assert result["reconciliation"]["reason"] == "background_reconciliation_not_run_yet"
            assert result["latency"]["within_target"] is True
    finally:
        session.close()


def test_incremental_sync_imports_recent_deals_and_normalizes() -> None:
    session, account_id = build_session()
    try:
        blocker = Mt5TradeBlocker(mt5_service=FakeMt5Service(), poll_seconds=0.05)

        result = blocker._sync_incremental_account_if_due(session, account_id)
        raw_deals = session.query(RawDeal).filter(RawDeal.account_id == account_id).all()

        assert result["attempted"] is True
        assert result["synced"] is True
        assert result["source"] == "incremental_deal_sync"
        assert result["deals_saved"] >= 1
        assert result["normalized"]["account_id"] == account_id
        assert len(raw_deals) >= 1
    finally:
        session.close()


def test_incremental_sync_accepts_naive_last_deal_time_from_sqlite() -> None:
    session, account_id = build_session()
    try:
        add_closed_trade(session, account_id)
        session.add(
            RawDeal(
                account_id=account_id,
                external_deal_id="existing-1",
                external_order_id="existing-order-1",
                symbol="BTCUSD",
                direction="buy",
                entry_type="out",
                volume=1.0,
                price=63050,
                profit=12.0,
                commission=-1.0,
                swap=0.0,
                deal_time=datetime.now(),
                comment="naive-sqlite",
                raw_payload={},
            )
        )
        session.commit()
        blocker = Mt5TradeBlocker(mt5_service=FakeMt5Service(), poll_seconds=0.05)

        result = blocker._sync_incremental_account_if_due(session, account_id)

        assert result["attempted"] is True
        assert result["synced"] is True
        assert result["source"] == "incremental_deal_sync"
    finally:
        session.close()


def test_incremental_sync_survives_database_contention() -> None:
    session, account_id = build_session()
    try:
        blocker = LockedNormalizationBlocker(mt5_service=FakeMt5Service(), poll_seconds=0.05)

        result = blocker._sync_incremental_account_if_due(session, account_id)

        assert result["attempted"] is True
        assert result["synced"] is False
        assert result["source"] == "incremental_deal_sync"
        assert "database is locked" in result["error"]
    finally:
        session.close()


if __name__ == "__main__":
    test_blocker_writes_block_file_immediately_when_blocked()
    test_blocker_skips_enforcement_when_mt5_login_does_not_match_account()
    test_blocked_fast_path_skips_raw_sync_and_reports_under_target()
    test_existing_active_block_uses_fast_path_without_full_rule_recompute()
    test_blocker_clears_block_file_when_not_blocked()
    test_non_blocked_enforcement_uses_cached_background_sync_status()
    test_incremental_sync_imports_recent_deals_and_normalizes()
    test_incremental_sync_accepts_naive_last_deal_time_from_sqlite()
    test_incremental_sync_survives_database_contention()
    print("test_mt5_trade_blocker_realtime_smoke: PASS")
