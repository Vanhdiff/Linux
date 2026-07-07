"""
Guardrail Response Builder.

Builds API response payloads for GuardrailService without evaluating rules,
querying the database, or mutating block state.
"""
from __future__ import annotations

from datetime import date
from typing import Any, Callable


class GuardrailResponseBuilder:
    """Pure response builder for guardrail status payloads."""

    def __init__(
        self,
        *,
        trade_block_payload: Callable[[bool, list[dict]], dict],
        guardrail_lock_payload: Callable[[bool, int, Any, date | None], dict],
        settings_payload: Callable[[Any, date | None], dict],
        scorecard_payload: Callable[..., dict],
    ) -> None:
        self._trade_block_payload = trade_block_payload
        self._guardrail_lock_payload = guardrail_lock_payload
        self._settings_payload = settings_payload
        self._scorecard_payload = scorecard_payload

    def build_disabled_status(
        self,
        *,
        account_id: int,
        target_date: date,
        settings: Any,
        trades: list[Any],
        opened_trades: list[Any],
        trade_count: int,
        floating_pnl: float,
        open_positions: list[dict],
    ) -> dict:
        return {
            "account_id": account_id,
            "mode": "local_read_only",
            "trade_blocking_enabled": False,
            "trade_blocked": False,
            "trade_block": self._trade_block_payload(False, []),
            "block_state": {
                "active": False,
                "block_type": None,
                "remaining_seconds": 0,
            },
            "enabled": False,
            "date": target_date.isoformat(),
            "status": "disabled",
            "summary": {
                "triggered_count": 0,
                "critical_count": 0,
                "warning_count": 0,
            },
            "guardrail_lock": self._guardrail_lock_payload(
                False,
                trade_count,
                settings,
                target_date,
            ),
            "settings": self._settings_payload(settings, target_date),
            "checks": [],
            "scorecard": self._scorecard_payload(
                settings,
                trades,
                opened_trades,
                target_date,
                [],
                trade_count=trade_count,
                floating_pnl=floating_pnl,
                open_positions=open_positions,
            ),
        }

    def build_status(
        self,
        *,
        account_id: int,
        target_date: date,
        settings: Any,
        trades: list[Any],
        opened_trades: list[Any],
        checks: list[dict],
        active_breaks: list[dict],
        trade_count: int,
        floating_pnl: float,
        open_positions: list[dict],
        trade_blocking_enabled: bool,
        trade_blocked: bool,
        trade_block_reasons: list[dict],
        block_state: dict,
    ) -> dict:
        return {
            "account_id": account_id,
            "mode": "mt5_enforcement" if trade_blocking_enabled else "local_read_only",
            "trade_blocking_enabled": trade_blocking_enabled,
            "trade_blocked": trade_blocked,
            "trade_block": self._trade_block_payload(
                trade_blocking_enabled,
                trade_block_reasons,
            ),
            "block_state": block_state,
            "enabled": settings.enabled,
            "date": target_date.isoformat(),
            "status": "blocked" if trade_blocked else ("warning" if active_breaks else "clear"),
            "summary": {
                "triggered_count": len(active_breaks),
                "critical_count": len(
                    [item for item in active_breaks if item["severity"] == "critical"]
                ),
                "warning_count": len(
                    [item for item in active_breaks if item["severity"] == "warning"]
                ),
            },
            "guardrail_lock": self._guardrail_lock_payload(
                trade_blocked,
                trade_count,
                settings,
                target_date,
            ),
            "settings": self._settings_payload(settings, target_date),
            "checks": checks,
            "scorecard": self._scorecard_payload(
                settings,
                trades,
                opened_trades,
                target_date,
                checks,
                trade_count=trade_count,
                floating_pnl=floating_pnl,
                open_positions=open_positions,
            ),
        }

    def build_trade_block_status(
        self,
        *,
        status: dict,
        floating_pnl: float | None,
    ) -> dict:
        block_state = status.get("block_state", {})
        return {
            "account_id": status["account_id"],
            "date": status["date"],
            "allowed": not status["trade_blocked"],
            "blocked": status["trade_blocked"],
            "trade_blocking_enabled": status["trade_blocking_enabled"],
            "reasons": status["trade_block"]["reasons"],
            "block_state": block_state,
            "floating_pnl": floating_pnl,
        }
