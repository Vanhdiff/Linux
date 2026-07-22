"""
Guardrail Data Collector.

Collects database-backed guardrail input data. It does not evaluate rules,
mutate block state, or build API responses.
"""
from __future__ import annotations

from datetime import date, datetime, time, timedelta
from typing import Any, Callable

from app.models import NormalizedTrade, RawDeal, RawMt5Import, RawPosition, RuleBreak


class GuardrailDataCollector:
    """Database read helper for guardrail status inputs."""

    def __init__(
        self,
        db_session: Any,
        *,
        trade_entry_signature: Callable[..., tuple[str, str, int, float]],
        deal_direction: Callable[[RawDeal], str],
        is_open_deal: Callable[[RawDeal], bool],
        position_opened_at: Callable[[dict], datetime | None],
        position_volume: Callable[[dict], float],
        position_profit: Callable[[dict], float],
    ) -> None:
        self._db = db_session
        self._trade_entry_signature = trade_entry_signature
        self._deal_direction = deal_direction
        self._is_open_deal = is_open_deal
        self._position_opened_at = position_opened_at
        self._position_volume = position_volume
        self._position_profit = position_profit

    def trading_day_bounds(self, target_date: date) -> tuple[datetime, datetime]:
        # MT5 datetimes are persisted and rendered in the app using the same
        # naive wall-clock values, so daily rule checks must use that same
        # trading-day boundary instead of shifting again for UTC+7.
        start = datetime.combine(target_date, time.min)
        return start, start + timedelta(days=1)

    def trades_for_day(
        self,
        account_id: int,
        target_date: date,
    ) -> list[NormalizedTrade]:
        start, end = self.trading_day_bounds(target_date)
        return (
            self._db.query(NormalizedTrade)
            .filter(
                NormalizedTrade.account_id == account_id,
                NormalizedTrade.closed_at >= start,
                NormalizedTrade.closed_at < end,
                NormalizedTrade.status.in_(["closed", "breakeven"]),
            )
            .order_by(NormalizedTrade.closed_at.asc(), NormalizedTrade.id.asc())
            .all()
        )

    def trades_opened_for_day(
        self,
        account_id: int,
        target_date: date,
    ) -> list[NormalizedTrade]:
        start, end = self.trading_day_bounds(target_date)
        return (
            self._db.query(NormalizedTrade)
            .filter(
                NormalizedTrade.account_id == account_id,
                NormalizedTrade.opened_at >= start,
                NormalizedTrade.opened_at < end,
            )
            .order_by(NormalizedTrade.opened_at.asc(), NormalizedTrade.id.asc())
            .all()
        )

    def trade_entry_count(
        self,
        account_id: int,
        target_date: date,
        open_positions: list[dict] | None = None,
    ) -> int:
        start, end = self.trading_day_bounds(target_date)
        entry_deals = (
            self._db.query(RawDeal)
            .filter(
                RawDeal.account_id == account_id,
                RawDeal.deal_time >= start,
                RawDeal.deal_time < end,
            )
            .order_by(RawDeal.deal_time.asc(), RawDeal.id.asc())
            .all()
        )
        opened_trades = self.trades_opened_for_day(account_id, target_date)

        trade_keys = {
            self._trade_entry_signature(
                symbol=deal.symbol,
                direction=self._deal_direction(deal),
                opened_at=deal.deal_time,
                volume=deal.volume,
            )
            for deal in entry_deals
            if self._is_open_deal(deal)
        }

        for trade in opened_trades:
            trade_keys.add(
                self._trade_entry_signature(
                    symbol=trade.symbol,
                    direction=trade.direction,
                    opened_at=trade.opened_at,
                    volume=trade.volume,
                )
            )

        live_positions = (
            open_positions
            if open_positions is not None
            else self.latest_open_positions(account_id)
        )
        for position in live_positions:
            opened_at = self._position_opened_at(position)
            if opened_at is None or opened_at < start or opened_at >= end:
                continue
            trade_keys.add(
                self._trade_entry_signature(
                    symbol=str(position.get("symbol") or ""),
                    direction=str(position.get("direction") or ""),
                    opened_at=opened_at,
                    volume=self._position_volume(position),
                )
            )

        return len(trade_keys)

    def latest_open_positions(self, account_id: int) -> list[dict]:
        latest_import = (
            self._db.query(RawMt5Import)
            .filter(
                RawMt5Import.account_id == account_id,
                RawMt5Import.import_type == "positions",
            )
            .order_by(RawMt5Import.imported_at.desc(), RawMt5Import.id.desc())
            .first()
        )
        if latest_import is None:
            return []
        positions = (
            self._db.query(RawPosition)
            .filter(
                RawPosition.account_id == account_id,
                RawPosition.raw_import_id == latest_import.id,
            )
            .order_by(RawPosition.opened_at.asc(), RawPosition.id.asc())
            .all()
        )
        return [
            {
                "external_position_id": position.external_position_id,
                "symbol": position.symbol,
                "direction": position.direction,
                "volume": position.volume,
                "profit": position.profit,
                "opened_at": position.opened_at,
                "open_price": position.open_price,
                "current_price": position.current_price,
                "stop_loss": position.stop_loss,
                "take_profit": position.take_profit,
                "captured_at": position.captured_at,
            }
            for position in positions
        ]

    def floating_pnl_from_positions(self, positions: list[dict]) -> float:
        return round(sum(self._position_profit(position) for position in positions), 2)

    def open_rule_breaks(self, account_id: int) -> list[RuleBreak]:
        return (
            self._db.query(RuleBreak)
            .filter(
                RuleBreak.account_id == account_id,
                RuleBreak.resolved_at.is_(None),
            )
            .order_by(RuleBreak.detected_at.desc(), RuleBreak.id.desc())
            .all()
        )
