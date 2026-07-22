from __future__ import annotations

import asyncio
from datetime import datetime, timedelta, timezone
from time import perf_counter
from typing import Any

from app.application.mt5_protection import BlockStateSync, EACommunicationLayer
from app.database import SessionLocal
from app.infrastructure.persistence.block_repository import BlockRepository
from app.models import GuardrailSetting, TradingAccount
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
        self._last_live_poll_at_by_account: dict[int, datetime] = {}
        self._last_incremental_sync_at_by_account: dict[int, datetime] = {}
        self._last_reconcile_at_by_account: dict[int, datetime] = {}
        self._live_poll_interval = timedelta(seconds=0.50)
        self._incremental_sync_interval = timedelta(seconds=1.00)
        self._reconcile_interval = timedelta(seconds=30.0)
        self._last_live_poll_result_by_account: dict[int, dict[str, Any]] = {}
        self._last_incremental_sync_result_by_account: dict[int, dict[str, Any]] = {}
        self._last_reconcile_result_by_account: dict[int, dict[str, Any]] = {}
        self._last_block_audit_key_by_account: dict[int, str] = {}
        self._last_block_file_written_audit_key_by_account: dict[int, str] = {}
        self._ea_layer = EACommunicationLayer()
        self.last_result: dict[str, Any] = {
            "running": False,
            "accounts": {},
        }

    async def run_forever(self) -> None:
        self.last_result["running"] = True
        loops = [
            asyncio.create_task(
                self._run_interval_loop(self.enforce_once, self._poll_seconds),
                name="mt5-enforcement-loop",
            ),
            asyncio.create_task(
                self._run_interval_loop(self.poll_live_accounts_once, self._poll_seconds),
                name="mt5-live-polling-loop",
            ),
            asyncio.create_task(
                self._run_interval_loop(
                    self.sync_incremental_accounts_once,
                    max(self._poll_seconds, 0.25),
                ),
                name="mt5-incremental-sync-loop",
            ),
            asyncio.create_task(
                self._run_interval_loop(
                    self.reconcile_history_accounts_once,
                    max(self._poll_seconds, 1.0),
                ),
                name="mt5-history-reconciliation-loop",
            ),
        ]
        try:
            await asyncio.gather(*loops)
        except asyncio.CancelledError:
            for task in loops:
                task.cancel()
            await asyncio.gather(*loops, return_exceptions=True)
            self.last_result["running"] = False
            raise
        except Exception:
            for task in loops:
                task.cancel()
            await asyncio.gather(*loops, return_exceptions=True)
            self.last_result["running"] = False
            raise

    async def _run_interval_loop(self, func, interval_seconds: float) -> None:
        while True:
            await asyncio.to_thread(func)
            await asyncio.sleep(interval_seconds)

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

    def get_ea_status(self):
        return self._ea_layer.read_ea_status()

    def get_ea_diagnostics(self, account_id: int | None = None) -> dict[str, Any]:
        if hasattr(self._ea_layer, "diagnostics"):
            return self._ea_layer.diagnostics(account_id=account_id)
        return EACommunicationLayer().diagnostics(account_id=account_id)

    def protection_status(self, account_id: int | None = None) -> dict[str, Any]:
        ea_status = self.get_ea_status()
        accounts = self.last_result.get("accounts", {}) if isinstance(self.last_result, dict) else {}
        any_blocked = any(bool(result.get("blocked")) for result in accounts.values())
        any_sync_error = any(
            not bool((result.get("block_file_sync") or {}).get("synced", True))
            for result in accounts.values()
        )
        any_latency_slow = any(
            (result.get("latency") or {}).get("within_target") is False
            for result in accounts.values()
        )
        running = bool(self.last_result.get("running")) if isinstance(self.last_result, dict) else False

        if not running:
            level = "OFF"
            reason = "backend_blocker_not_running"
        elif not ea_status.connected:
            level = "DEGRADED"
            reason = "ea_offline_or_stale"
        elif any_sync_error:
            level = "DEGRADED"
            reason = "block_file_sync_error"
        elif any_latency_slow:
            level = "DEGRADED"
            reason = "backend_latency_over_500ms"
        elif any_blocked:
            level = "FULL"
            reason = "blocked_and_enforced"
        else:
            level = "FULL"
            reason = "ready"

        diagnostic_account_id = account_id if account_id is not None else ea_status.account_id
        if diagnostic_account_id is None and accounts:
            try:
                diagnostic_account_id = int(next(iter(accounts.keys())))
            except (TypeError, ValueError, StopIteration):
                diagnostic_account_id = None

        return {
            "level": level,
            "reason": reason,
            "backend_blocker_running": running,
            "ea": {
                "connected": ea_status.connected,
                "stale": ea_status.stale,
                "last_heartbeat": ea_status.last_heartbeat.isoformat()
                if ea_status.last_heartbeat
                else None,
                "version": ea_status.version,
                "account_id": ea_status.account_id,
                "error": ea_status.error,
            },
            "diagnostics": self.get_ea_diagnostics(account_id=diagnostic_account_id),
            "accounts": accounts,
            "last_checked_at": self.last_result.get("checked_at")
            if isinstance(self.last_result, dict)
            else None,
        }

    def reset_runtime(self, account_id: int | None = None) -> None:
        if account_id is None:
            self._blocked_since_by_account.clear()
            self._last_live_poll_at_by_account.clear()
            self._last_incremental_sync_at_by_account.clear()
            self._last_reconcile_at_by_account.clear()
            self._last_live_poll_result_by_account.clear()
            self._last_incremental_sync_result_by_account.clear()
            self._last_reconcile_result_by_account.clear()
            self._last_block_audit_key_by_account.clear()
            self._last_block_file_written_audit_key_by_account.clear()
            self.last_result = {
                "running": False,
                "accounts": {},
            }
            return

        self._blocked_since_by_account.pop(account_id, None)
        self._last_live_poll_at_by_account.pop(account_id, None)
        self._last_incremental_sync_at_by_account.pop(account_id, None)
        self._last_reconcile_at_by_account.pop(account_id, None)
        self._last_live_poll_result_by_account.pop(account_id, None)
        self._last_incremental_sync_result_by_account.pop(account_id, None)
        self._last_reconcile_result_by_account.pop(account_id, None)
        self._last_block_audit_key_by_account.pop(account_id, None)
        self._last_block_file_written_audit_key_by_account.pop(account_id, None)
        self.last_result.setdefault("accounts", {}).pop(str(account_id), None)

    def _enforce_account(self, db, account_id: int) -> dict[str, Any]:
        started = perf_counter()
        login_guard = self._current_login_guard(db, account_id)
        if login_guard is not None:
            return {
                "blocked": False,
                "allowed": False,
                "trade_blocking_enabled": False,
                "reasons": [],
                "floating_pnl": None,
                "open_position_count": 0,
                "sync": self._cached_sync_result(account_id),
                "live_poll": self._cached_live_poll_result(account_id),
                "reconciliation": self._cached_reconcile_result(account_id),
                "block_file_sync": {
                    "attempted": False,
                    "synced": False,
                    "reason": login_guard["reason"],
                },
                "latency": self._latency_payload(started, positions_ms=0),
                "mt5_action": None,
                **login_guard,
            }
        open_positions, floating_pnl, positions_ms = self._read_positions_fast()
        active_block_status = self._active_block_fast_path(db, account_id)
        if active_block_status is not None:
            return self._blocked_response(
                db,
                account_id,
                block_status=active_block_status,
                floating_pnl=floating_pnl,
                open_positions=open_positions,
                sync_result={
                    "attempted": False,
                    "synced": False,
                    "reason": "fast_path_existing_block",
                },
                started=started,
                positions_ms=positions_ms,
            )
        block_status = GuardrailService(db).trade_block_status(
            account_id,
            floating_pnl=floating_pnl,
            open_positions=open_positions,
        )
        if block_status["blocked"]:
            return self._blocked_response(
                db,
                account_id,
                block_status=block_status,
                floating_pnl=floating_pnl,
                open_positions=open_positions,
                sync_result={
                    "attempted": False,
                    "synced": False,
                    "reason": "fast_path_active_block",
                },
                started=started,
                positions_ms=positions_ms,
            )

        sync_result = self._cached_sync_result(account_id)
        if sync_result.get("synced") and (sync_result.get("source") == "incremental_deal_sync"):
            block_status = GuardrailService(db).trade_block_status(
                account_id,
                floating_pnl=floating_pnl,
                open_positions=open_positions,
            )
            if block_status["blocked"]:
                return self._blocked_response(
                    db,
                    account_id,
                    block_status=block_status,
                    floating_pnl=floating_pnl,
                    open_positions=open_positions,
                    sync_result=sync_result,
                    started=started,
                    positions_ms=positions_ms,
                )

        block_file_sync = self._sync_block_file(db, account_id, blocked=False)
        self._blocked_since_by_account.pop(account_id, None)
        self._last_block_file_written_audit_key_by_account.pop(account_id, None)
        return {
            "blocked": False,
            "allowed": True,
            "trade_blocking_enabled": block_status["trade_blocking_enabled"],
            "reasons": block_status["reasons"],
            "floating_pnl": floating_pnl,
            "open_position_count": len(open_positions),
            "sync": sync_result,
            "live_poll": self._cached_live_poll_result(account_id),
            "reconciliation": self._cached_reconcile_result(account_id),
            "block_file_sync": block_file_sync,
            "latency": self._latency_payload(started, positions_ms=positions_ms),
            "mt5_action": None,
        }

    def _read_positions_fast(self) -> tuple[list[dict[str, Any]], float | None, int]:
        started = perf_counter()
        try:
            if hasattr(self._mt5_service, "positions"):
                open_positions = self._mt5_service.positions()
                floating_pnl = round(
                    sum(float(position.get("profit") or 0) for position in open_positions),
                    2,
                )
            else:
                open_positions = []
                floating_pnl = self._mt5_service.floating_pnl()
            return open_positions, floating_pnl, int((perf_counter() - started) * 1000)
        except RuntimeError:
            return [], None, int((perf_counter() - started) * 1000)

    def _current_login_guard(self, db, account_id: int) -> dict[str, Any] | None:
        account = db.get(TradingAccount, account_id)
        if account is None:
            return {
                "reason": "account_not_found",
                "account_id": account_id,
                "mt5_login": None,
                "account_login": None,
            }
        try:
            mt5_account = self._mt5_service.account()
        except RuntimeError as exc:
            return {
                "reason": "mt5_account_unavailable",
                "account_id": account_id,
                "account_login": account.login,
                "mt5_login": None,
                "error": str(exc),
            }
        mt5_login = str(mt5_account.get("login") or "")
        if mt5_login and str(account.login) != mt5_login:
            return {
                "reason": "mt5_login_mismatch",
                "account_id": account_id,
                "account_login": account.login,
                "mt5_login": mt5_login,
            }
        return None

    def _blocked_response(
        self,
        db,
        account_id: int,
        *,
        block_status: dict[str, Any],
        floating_pnl: float | None,
        open_positions: list[dict[str, Any]],
        sync_result: dict[str, Any],
        started: float,
        positions_ms: int,
    ) -> dict[str, Any]:
        block_file_sync_started = perf_counter()
        blocked_since = self._blocked_since_by_account.setdefault(
            account_id,
            datetime.now(timezone.utc),
        )
        block_state = block_status.get("block_state") or {}
        block_key = str(block_state.get("blocked_at") or blocked_since.isoformat())
        self._record_block_timing_events(
            account_id=account_id,
            block_status=block_status,
            block_key=block_key,
        )
        block_file_sync = self._sync_block_file(db, account_id, blocked=True)
        block_file_sync_ms = int((perf_counter() - block_file_sync_started) * 1000)
        if block_file_sync.get("synced") and (
            self._last_block_file_written_audit_key_by_account.get(account_id)
            != block_key
        ):
            self._ea_layer.append_backend_timing_event(
                event_type="block_file_written",
                account_id=account_id,
                metadata={
                    "block_key": block_key,
                    "block_file_path": self._ea_layer.diagnostics(account_id=account_id).get(
                        "block_file_path"
                    ),
                },
            )
            self._last_block_file_written_audit_key_by_account[account_id] = block_key
        watchdog_started = perf_counter()
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
        watchdog_ms = int((perf_counter() - watchdog_started) * 1000)

        return {
            "blocked": True,
            "allowed": False,
            "trade_blocking_enabled": True,
            "blocked_since": blocked_since.isoformat(),
            "reasons": block_status["reasons"],
            "floating_pnl": floating_pnl,
            "open_position_count": len(open_positions),
            "sync": sync_result,
            "block_file_sync": block_file_sync,
            "watchdog_summary": self._watchdog_summary(mt5_action),
            "latency": self._latency_payload(
                started,
                positions_ms=positions_ms,
                block_file_sync_ms=block_file_sync_ms,
                watchdog_ms=watchdog_ms,
            ),
            "mt5_action": mt5_action,
        }

    def _latency_payload(
        self,
        started: float,
        *,
        positions_ms: int,
        block_file_sync_ms: int | None = None,
        watchdog_ms: int | None = None,
    ) -> dict[str, Any]:
        total_ms = int((perf_counter() - started) * 1000)
        return {
            "total_ms": total_ms,
            "positions_ms": positions_ms,
            "block_file_sync_ms": block_file_sync_ms,
            "watchdog_ms": watchdog_ms,
            "target_ms": 500,
            "within_target": total_ms <= 500,
        }

    def _watchdog_summary(self, mt5_action: dict[str, Any]) -> dict[str, Any]:
        deleted_orders = mt5_action.get("deleted_orders") or []
        closed_positions = mt5_action.get("closed_positions") or []
        failed_actions = mt5_action.get("failed_actions") or []
        return {
            "attempted": True,
            "deleted_order_count": len(deleted_orders),
            "closed_position_count": len(closed_positions),
            "failed_action_count": len(failed_actions),
            "ok": not bool(mt5_action.get("error")) and len(failed_actions) == 0,
            "error": mt5_action.get("error"),
        }

    def _sync_block_file(self, db, account_id: int, *, blocked: bool) -> dict[str, Any]:
        try:
            if blocked:
                result = BlockStateSync(db, ea_layer=self._ea_layer).sync_account(account_id)
                return {"attempted": True, **result}
            cleared = self._ea_layer.clear_block_state(account_id)
            return {
                "attempted": True,
                "account_id": account_id,
                "synced": cleared,
                "blocked": False,
                "block_type": None,
            }
        except Exception as exc:
            return {
                "attempted": True,
                "account_id": account_id,
                "synced": False,
                "error": str(exc),
            }

    def _sync_account_if_due(self, db, account_id: int) -> dict[str, Any]:
        return self._cached_sync_result(account_id)

    def _active_block_fast_path(self, db, account_id: int) -> dict[str, Any] | None:
        settings = (
            db.query(GuardrailSetting)
            .filter(GuardrailSetting.account_id == account_id)
            .order_by(GuardrailSetting.id.desc())
            .first()
        )
        if settings is None or not settings.enabled:
            return None
        nested = dict(settings.settings or {})
        if not bool(nested.get("trade_blocking_enabled", False)):
            return None

        block = BlockRepository(db).get_active_block(account_id)
        if block is None:
            return None

        reasons = [
            {
                "rule_code": code,
                "severity": "critical",
                "message": f"Active block remains in effect for rule {code}.",
                "payload": block.payload,
            }
            for code in block.triggered_by
        ]
        return {
            "blocked": True,
            "allowed": False,
            "trade_blocking_enabled": True,
            "reasons": reasons,
            "block_state": {
                "active": True,
                "block_type": block.block_type.value,
                "remaining_seconds": block.remaining_seconds(),
                "triggered_by": list(block.triggered_by),
                "expires_at": block.expires_at.isoformat() if block.expires_at else None,
                "blocked_at": block.blocked_at.isoformat() if block.blocked_at else None,
            },
        }

    def _record_block_timing_events(
        self,
        *,
        account_id: int,
        block_status: dict[str, Any],
        block_key: str,
    ) -> None:
        if not block_key:
            return
        if self._last_block_audit_key_by_account.get(account_id) == block_key:
            return
        block_state = block_status.get("block_state") or {}
        blocked_at = block_state.get("blocked_at")
        occurred_at = None
        if blocked_at:
            try:
                occurred_at = datetime.fromisoformat(str(blocked_at))
            except ValueError:
                occurred_at = None
        rule_reasons = block_status.get("reasons") or []
        metadata = {
            "block_key": block_key,
            "triggered_by": [
                reason.get("rule_code")
                for reason in rule_reasons
                if isinstance(reason, dict) and reason.get("rule_code")
            ],
            "reason_count": len(rule_reasons),
        }
        self._ea_layer.append_backend_timing_event(
            event_type="rule_detected",
            account_id=account_id,
            occurred_at=occurred_at,
            metadata=metadata,
        )
        self._ea_layer.append_backend_timing_event(
            event_type="block_persisted",
            account_id=account_id,
            occurred_at=occurred_at,
            metadata=metadata,
        )
        self._last_block_audit_key_by_account[account_id] = block_key

    def poll_live_accounts_once(self) -> dict[str, Any]:
        return self._run_background_cycle(
            self._poll_live_account_if_due,
            self._last_live_poll_result_by_account,
        )

    def sync_incremental_accounts_once(self) -> dict[str, Any]:
        return self._run_background_cycle(
            self._sync_incremental_account_if_due,
            self._last_incremental_sync_result_by_account,
        )

    def reconcile_history_accounts_once(self) -> dict[str, Any]:
        return self._run_background_cycle(
            self._reconcile_account_if_due,
            self._last_reconcile_result_by_account,
        )

    def _run_background_cycle(self, runner, cache: dict[int, dict[str, Any]]) -> dict[str, Any]:
        result: dict[str, Any] = {
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
                account_result = runner(db, account.id)
                resolved_account_id = account_result.get("account_id") or account.id
                cache[int(resolved_account_id)] = account_result
                result["accounts"][str(resolved_account_id)] = account_result
        return result

    def _poll_live_account_if_due(self, db, account_id: int) -> dict[str, Any]:
        now = datetime.now(timezone.utc)
        last_run_at = self._last_live_poll_at_by_account.get(account_id)
        if last_run_at is not None and now - last_run_at < self._live_poll_interval:
            return {
                "attempted": False,
                "synced": False,
                "source": "live_account_polling",
                "reason": "interval_not_elapsed",
                "last_sync_at": last_run_at.isoformat(),
            }

        try:
            sync_result = Mt5SyncService(db, self._mt5_service).import_live_state(
                Mt5SyncRequest(
                    account_id=account_id,
                    include_positions=True,
                    include_orders=True,
                    include_deals=False,
                )
            )
            self._last_live_poll_at_by_account[account_id] = now
            return {
                "attempted": True,
                "synced": True,
                "source": "live_account_polling",
                "account_id": sync_result.account_id,
                "snapshot_saved": sync_result.snapshot.saved,
                "positions_saved": sync_result.positions.saved if sync_result.positions else 0,
                "orders_saved": sync_result.orders.saved if sync_result.orders else 0,
                "last_sync_at": now.isoformat(),
            }
        except RuntimeError as exc:
            return {
                "attempted": True,
                "synced": False,
                "source": "live_account_polling",
                "error": str(exc),
            }

    def _sync_incremental_account_if_due(self, db, account_id: int) -> dict[str, Any]:
        now = datetime.now(timezone.utc)
        last_sync_at = self._last_incremental_sync_at_by_account.get(account_id)
        if last_sync_at is not None and now - last_sync_at < self._incremental_sync_interval:
            return {
                "attempted": False,
                "synced": False,
                "source": "incremental_deal_sync",
                "reason": "interval_not_elapsed",
                "last_sync_at": last_sync_at.isoformat(),
            }

        try:
            sync_result = Mt5SyncService(db, self._mt5_service).import_incremental_deals(
                account_id=account_id,
                history_days=3,
                overlap_minutes=5,
            )
            normalized = self._normalize_account(db, sync_result.account_id)
            self._last_incremental_sync_at_by_account[account_id] = now
            return {
                "attempted": True,
                "synced": True,
                "source": "incremental_deal_sync",
                "account_id": sync_result.account_id,
                "date_from": sync_result.date_from.isoformat(),
                "date_to": sync_result.date_to.isoformat(),
                "deals_saved": sync_result.deals.saved if sync_result.deals else 0,
                "deals_skipped": sync_result.deals.skipped if sync_result.deals else 0,
                "normalized": normalized.model_dump(),
                "last_sync_at": now.isoformat(),
            }
        except Exception as exc:
            return {
                "attempted": True,
                "synced": False,
                "source": "incremental_deal_sync",
                "error": str(exc),
            }

    def _reconcile_account_if_due(self, db, account_id: int) -> dict[str, Any]:
        now = datetime.now(timezone.utc)
        last_run_at = self._last_reconcile_at_by_account.get(account_id)
        if last_run_at is not None and now - last_run_at < self._reconcile_interval:
            return {
                "attempted": False,
                "synced": False,
                "source": "slow_history_reconciliation",
                "reason": "interval_not_elapsed",
                "last_sync_at": last_run_at.isoformat(),
            }

        try:
            sync_result = Mt5SyncService(db, self._mt5_service).import_raw(
                Mt5SyncRequest(
                    account_id=account_id,
                    history_days=30,
                    include_positions=True,
                    include_orders=True,
                    include_deals=True,
                )
            )
            normalized = self._normalize_account(db, sync_result.account_id)
            self._last_reconcile_at_by_account[account_id] = now
            return {
                "attempted": True,
                "synced": True,
                "source": "slow_history_reconciliation",
                "account_id": sync_result.account_id,
                "date_from": sync_result.date_from.isoformat(),
                "date_to": sync_result.date_to.isoformat(),
                "deals_saved": sync_result.deals.saved if sync_result.deals else 0,
                "deals_skipped": sync_result.deals.skipped if sync_result.deals else 0,
                "normalized": normalized.model_dump(),
                "last_sync_at": now.isoformat(),
            }
        except Exception as exc:
            return {
                "attempted": True,
                "synced": False,
                "source": "slow_history_reconciliation",
                "error": str(exc),
            }

    def _normalize_account(self, db, account_id: int):
        return NormalizationService(db).sync_account(account_id)

    def _cached_sync_result(self, account_id: int) -> dict[str, Any]:
        return self._last_incremental_sync_result_by_account.get(
            account_id,
            {
                "attempted": False,
                "synced": False,
                "source": "incremental_deal_sync",
                "reason": "background_sync_not_run_yet",
            },
        )

    def _cached_live_poll_result(self, account_id: int) -> dict[str, Any]:
        return self._last_live_poll_result_by_account.get(
            account_id,
            {
                "attempted": False,
                "synced": False,
                "source": "live_account_polling",
                "reason": "background_poll_not_run_yet",
            },
        )

    def _cached_reconcile_result(self, account_id: int) -> dict[str, Any]:
        return self._last_reconcile_result_by_account.get(
            account_id,
            {
                "attempted": False,
                "synced": False,
                "source": "slow_history_reconciliation",
                "reason": "background_reconciliation_not_run_yet",
            },
        )
