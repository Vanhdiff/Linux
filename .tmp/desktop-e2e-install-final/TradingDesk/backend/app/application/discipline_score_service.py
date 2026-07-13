"""
Discipline Score Service.

Owns the top-level scorecard assembly for guardrail status. Detailed row
calculations can be migrated here incrementally while keeping API payloads
stable.
"""
from __future__ import annotations

from datetime import date
from typing import Any, Callable


class DisciplineScoreService:
    """Builds the guardrail scorecard payload without mutating state."""

    def __init__(
        self,
        *,
        setting_enabled: Callable[[Any, str, bool], bool],
        performance_score_rows: Callable[[list[Any]], dict],
        discipline_score_rows: Callable[..., dict],
        consistency_score_rows: Callable[[Any, list[Any], date], dict],
    ) -> None:
        self._setting_enabled = setting_enabled
        self._performance_score_rows = performance_score_rows
        self._discipline_score_rows = discipline_score_rows
        self._consistency_score_rows = consistency_score_rows

    def build_scorecard(
        self,
        settings: Any,
        trades: list[Any],
        opened_trades: list[Any],
        target_date: date,
        checks: list[dict],
        *,
        trade_count: int,
        floating_pnl: float | None = None,
        open_positions: list[dict] | None = None,
    ) -> dict:
        check_map = {check["rule_code"]: check for check in checks}
        trade_blocking_enabled = self._setting_enabled(
            settings,
            "trade_blocking_enabled",
            False,
        )
        categories = [
            self._performance_score_rows(trades),
            self._discipline_score_rows(
                settings,
                trades,
                opened_trades,
                target_date,
                check_map,
                trade_count=trade_count,
                trade_blocking_enabled=trade_blocking_enabled,
                open_positions=open_positions,
            ),
            self._consistency_score_rows(settings, trades, target_date),
        ]
        total_points = round(sum(category["earned_points"] for category in categories), 2)
        max_points = round(sum(category["max_points"] for category in categories), 2)
        return {
            "date": target_date.isoformat(),
            "trade_blocking_enabled": trade_blocking_enabled,
            "floating_pnl": round(floating_pnl or 0, 2),
            "total_points": total_points,
            "max_points": max_points,
            "percent": round((total_points / max_points) * 100, 2) if max_points > 0 else 0,
            "categories": categories,
        }
