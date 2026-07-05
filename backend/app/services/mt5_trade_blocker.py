from __future__ import annotations

import asyncio
from datetime import datetime, timedelta, timezone
from typing import Any

from app.database import SessionLocal
from app.models import TradingAccount
from app.services.guardrail_service import GuardrailService
from app.services.mt5_service import Mt5Service
from app.services.mt5_sync_service import Mt5SyncService
from app.services.normalize_service import NormalizationService
from app.schemas.mt5 import Mt5SyncRequest


class Mt5TradeBlocker:
    def __init__(
        self,
        mt5_service: Mt5Service | None = None,
        poll_seconds: float = 0.10,
    ) -> None:
        self._mt5_service = mt5_service or Mt5Service()
        self._poll_seconds = poll_seconds
        self._blocked_since_by_account: dict[int, datetime] = {}
        self._last_sync_at_by_account: dict[int, datetime] = {}
        self._sync_interval = timedelta(seconds=2)
        self.last_result: dict[str, Any] = {
            "running": False,
            "accounts": {},
        }

    async def run_forever(self) -> None:
        self.last_result["running"] = True
        try:
            while True:
                await asyncio.to_thread(self.enforce_once)
                await asyncio.sleep(self._poll_seconds)
        except asyncio.CancelledError:
            self.last_result["running"] = False
            raise

    def enforce_once(self) -> dict[str, Any]:
        result: dict[str, Any] = {
            "running": True,
            "checked_at": datetime.now(timezone.utc).isoformat(),
            "accounts": {},
        }
        with SessionLocal() as db:
            accounts = (
                db.query(TradingAccount)
                .filter(TradingAccount.is_active.is_(True))
                .order_by(TradingAccount.id.asc())
                .all()
            )
            for account in accounts:
                account_result = self._enforce_account(db, account.id)
                result["accounts"][str(account.id)] = account_result
        self.last_result = result
        return result

    def reset_runtime(self, account_id: int | None = None) -> None:
        if account_id is None:
            self._blocked_since_by_account.clear()
            self._last_sync_at_by_account.clear()
            self.last_result = {
                "running": False,
                "accounts": {},
            }
            return

        self._blocked_since_by_account.pop(account_id, None)
        self._last_sync_at_by_account.pop(account_id, None)
        self.last_result.setdefault("accounts", {}).pop(str(account_id), None)

    def _enforce_account(self, db, account_id: int) -> dict[str, Any]:
        sync_result = self._sync_account_if_due(db, account_id)
        floating_pnl = None
        open_positions = []
        try:
            if hasattr(self._mt5_service, "positions"):
                open_positions = self._mt5_service.positions()
                floating_pnl = round(
                    sum(float(position.get("profit") or 0) for position in open_positions),
                    2,
                )
            else:
                floating_pnl = self._mt5_service.floating_pnl()
        except RuntimeError:
            open_positions = []
            floating_pnl = None

        block_status = GuardrailService(db).trade_block_status(
            account_id,
            floating_pnl=floating_pnl,
            open_positions=open_positions,
        )
        if not block_status["blocked"]:
            self._blocked_since_by_account.pop(account_id, None)
            return {
                "blocked": False,
                "allowed": True,
                "trade_blocking_enabled": block_status["trade_blocking_enabled"],
                "reasons": block_status["reasons"],
                "floating_pnl": floating_pnl,
                "open_position_count": len(open_positions),
                "sync": sync_result,
                "mt5_action": None,
            }

        blocked_since = self._blocked_since_by_account.setdefault(
            account_id,
            datetime.now(timezone.utc),
        )
        try:
            mt5_action = self._mt5_service.enforce_trade_block(
                blocked_since=blocked_since,
            )
        except RuntimeError as exc:
            mt5_action = {
                "error": str(exc),
                "deleted_orders": [],
                "closed_positions": [],
                "failed_actions": [],
            }

        return {
            "blocked": True,
            "allowed": False,
            "trade_blocking_enabled": True,
            "blocked_since": blocked_since.isoformat(),
            "reasons": block_status["reasons"],
            "floating_pnl": floating_pnl,
            "open_position_count": len(open_positions),
            "sync": sync_result,
            "mt5_action": mt5_action,
        }

    def _sync_account_if_due(self, db, account_id: int) -> dict[str, Any]:
        now = datetime.now(timezone.utc)
        last_sync_at = self._last_sync_at_by_account.get(account_id)
        if last_sync_at is not None and now - last_sync_at < self._sync_interval:
            return {
                "attempted": False,
                "synced": False,
                "reason": "interval_not_elapsed",
                "last_sync_at": last_sync_at.isoformat(),
            }

        try:
            sync_result = Mt5SyncService(db, self._mt5_service).import_raw(
                Mt5SyncRequest(
                    account_id=account_id,
                    history_days=3,
                    include_positions=True,
                    include_orders=True,
                    include_deals=True,
                )
            )
            normalized = NormalizationService(db).sync_account(sync_result.account_id)
            self._last_sync_at_by_account[account_id] = now
            return {
                "attempted": True,
                "synced": True,
                "account_id": sync_result.account_id,
                "date_from": sync_result.date_from.isoformat(),
                "date_to": sync_result.date_to.isoformat(),
                "normalized": normalized.model_dump(),
                "last_sync_at": now.isoformat(),
            }
        except RuntimeError as exc:
            return {
                "attempted": True,
                "synced": False,
                "error": str(exc),
            }
