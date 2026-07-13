from __future__ import annotations

from sqlalchemy import delete
from sqlalchemy.orm import Session

from app.models import (
    AccountSnapshot,
    DailyAnalytics,
    EconomicEvent,
    GuardrailSetting,
    NormalizedTrade,
    RawCandle,
    RawDeal,
    RawMt5Import,
    RawOrder,
    RawPosition,
    RuleBreak,
    TradeJournal,
    TradingAccount,
)
from app.schemas.mt5 import Mt5SyncRequest
from app.services.mt5_sync_service import Mt5SyncService
from app.services.normalize_service import NormalizationService


class DeveloperResetService:
    def __init__(self, db: Session, mt5_service=None) -> None:
        self._db = db
        self._mt5_service = mt5_service

    def reset_environment(self, history_days: int = 90) -> dict:
        deleted = self._clear_local_trading_state()
        sync_result = Mt5SyncService(self._db, self._mt5_service).import_raw(
            Mt5SyncRequest(
                history_days=history_days,
                include_positions=True,
                include_orders=True,
                include_deals=True,
            )
        )
        normalized = NormalizationService(self._db).sync_account(sync_result.account_id)
        active_account = self._db.get(TradingAccount, sync_result.account_id)
        settings = (
            self._db.query(GuardrailSetting)
            .filter(GuardrailSetting.account_id == sync_result.account_id)
            .order_by(GuardrailSetting.id.desc())
            .first()
        )
        return {
            "reset": {
                "deleted": deleted,
                "cleared_tables": [key for key, value in deleted.items() if value > 0],
                "history_days": history_days,
            },
            "account": {
                "id": sync_result.account_id,
                "login": sync_result.account_login,
                "name": active_account.name if active_account is not None else None,
                "broker": active_account.broker if active_account is not None else None,
                "is_active": active_account.is_active if active_account is not None else True,
            },
            "guardrails_preserved": settings is not None,
            "sync": sync_result.model_dump(),
            "normalized": normalized.model_dump(),
            "daily_start_reset_mode": "current_snapshot_becomes_new_baseline",
        }

    def _clear_local_trading_state(self) -> dict[str, int]:
        deleted = {
            "trade_journals": self._delete_all(TradeJournal),
            "rule_breaks": self._delete_all(RuleBreak),
            "daily_analytics": self._delete_all(DailyAnalytics),
            "normalized_trades": self._delete_all(NormalizedTrade),
            "raw_positions": self._delete_all(RawPosition),
            "raw_orders": self._delete_all(RawOrder),
            "raw_deals": self._delete_all(RawDeal),
            "raw_candles": self._delete_all(RawCandle),
            "raw_mt5_imports": self._delete_all(RawMt5Import),
            "account_snapshots": self._delete_all(AccountSnapshot),
            "economic_events": self._delete_all(EconomicEvent),
        }
        self._db.commit()
        return deleted

    def _delete_all(self, model) -> int:
        result = self._db.execute(delete(model))
        return int(result.rowcount or 0)
