from collections import defaultdict
from dataclasses import dataclass
from datetime import date, datetime, time, timedelta

from fastapi import HTTPException
from sqlalchemy.orm import Session

from app.models import (
    AccountSnapshot,
    GuardrailSetting,
    NormalizedTrade,
    RawDeal,
    TradingAccount,
)
from app.schemas.trade import NormalizeResult


@dataclass(frozen=True)
class _TradeGroup:
    key: str
    deals: list[RawDeal]


class NormalizationService:
    def __init__(self, db: Session) -> None:
        self._db = db

    def sync_account(self, account_id: int) -> NormalizeResult:
        account = self._db.get(TradingAccount, account_id)
        if account is None:
            raise HTTPException(status_code=404, detail="Account not found")

        raw_deals = (
            self._db.query(RawDeal)
            .filter(RawDeal.account_id == account_id)
            .order_by(RawDeal.deal_time.asc(), RawDeal.id.asc())
            .all()
        )

        created = 0
        updated = 0
        skipped = 0
        current_source_keys: set[tuple[str, ...]] = set()

        for group in self._group_deals(raw_deals):
            normalized = self._build_normalized_trade(account_id, group)
            if normalized is None:
                skipped += len(group.deals)
                continue
            current_source_keys.add(self._source_key(normalized["source_deal_ids"]))

            existing = self._existing_normalized_trade(
                account_id,
                normalized["source_deal_ids"],
            )

            if existing is None:
                self._db.add(NormalizedTrade(**normalized))
                created += 1
            else:
                for key, value in normalized.items():
                    setattr(existing, key, value)
                updated += 1

        deleted = self._delete_stale_normalized_trades(
            account_id,
            current_source_keys,
        )
        self._db.commit()
        return NormalizeResult(
            account_id=account_id,
            created=created,
            updated=updated,
            skipped=skipped + deleted,
        )

    def _existing_normalized_trade(
        self,
        account_id: int,
        source_deal_ids: list,
    ) -> NormalizedTrade | None:
        matches = (
            self._db.query(NormalizedTrade)
            .filter(
                NormalizedTrade.account_id == account_id,
                NormalizedTrade.source_deal_ids == source_deal_ids,
            )
            .order_by(NormalizedTrade.id.desc())
            .all()
        )
        if not matches:
            return None

        keeper = next((trade for trade in matches if trade.journal is not None), matches[0])
        for duplicate in matches:
            if duplicate.id != keeper.id:
                self._db.delete(duplicate)
        return keeper

    def _delete_stale_normalized_trades(
        self,
        account_id: int,
        current_source_keys: set[tuple[str, ...]],
    ) -> int:
        stale_count = 0
        existing_trades = (
            self._db.query(NormalizedTrade)
            .filter(NormalizedTrade.account_id == account_id)
            .all()
        )
        for trade in existing_trades:
            if self._source_key(trade.source_deal_ids or []) not in current_source_keys:
                self._db.delete(trade)
                stale_count += 1
        return stale_count

    def _source_key(self, source_deal_ids: list) -> tuple[str, ...]:
        return tuple(sorted(str(item) for item in source_deal_ids if str(item)))

    def _group_deals(self, deals: list[RawDeal]) -> list[_TradeGroup]:
        grouped: dict[str, list[RawDeal]] = defaultdict(list)

        for deal in deals:
            if self._is_balance_operation(deal):
                continue
            key = self._group_key(deal)
            grouped[key].append(deal)

        return [
            _TradeGroup(key=key, deals=group_deals)
            for key, group_deals in grouped.items()
        ]

    def _build_normalized_trade(
        self,
        account_id: int,
        group: _TradeGroup,
    ) -> dict | None:
        deals = sorted(group.deals, key=lambda deal: (deal.deal_time, deal.id))
        if not deals:
            return None

        open_deals = [deal for deal in deals if self._is_open_deal(deal)]
        close_deals = [
            deal
            for deal in deals
            if not self._is_open_deal(deal) and self._is_close_deal(deal)
        ]

        if not close_deals and not open_deals:
            return None

        entry_candidates = open_deals or deals[:1]
        exit_candidates = close_deals or deals[-1:]
        source_deal_ids = [deal.external_deal_id for deal in deals]
        direction = self._direction(entry_candidates[0])
        volume = sum(abs(deal.volume) for deal in close_deals) or max(
            abs(deal.volume) for deal in deals
        )
        gross_pnl = sum(deal.profit for deal in deals)
        commission = sum(deal.commission for deal in deals)
        swap = sum(deal.swap for deal in deals)
        net_pnl = gross_pnl + commission + swap
        opened_at = entry_candidates[0].deal_time
        closed_at = close_deals[-1].deal_time if close_deals else None
        risk_amount = self._estimate_risk_amount(
            account_id,
            entry_candidates,
            opened_at,
        )
        entry_price = self._weighted_price(entry_candidates)
        exit_price = self._weighted_price(exit_candidates)
        duration_seconds = (
            int((closed_at - opened_at).total_seconds()) if closed_at else None
        )
        entry_reason = self._comment(entry_candidates)
        exit_reason = self._comment(close_deals)
        stop_loss = self._first_payload_float(entry_candidates + close_deals, "sl", "stop_loss")
        take_profit = self._first_payload_float(entry_candidates + close_deals, "tp", "take_profit")

        return {
            "account_id": account_id,
            "symbol": deals[0].symbol,
            "direction": direction,
            "side": direction,
            "volume": volume,
            "opened_at": opened_at,
            "open_time": opened_at,
            "closed_at": closed_at,
            "close_time": closed_at,
            "entry_price": entry_price,
            "open_price": entry_price,
            "exit_price": exit_price,
            "close_price": exit_price,
            "stop_loss": stop_loss,
            "take_profit": take_profit,
            "commission": commission,
            "swap": swap,
            "gross_pnl": gross_pnl,
            "profit": gross_pnl,
            "net_pnl": net_pnl,
            "net_profit": net_pnl,
            "duration_seconds": duration_seconds,
            "entry_reason": entry_reason,
            "exit_reason": exit_reason,
            "risk_amount": risk_amount,
            "r_multiple": round(net_pnl / risk_amount, 4) if risk_amount else None,
            "setup_tag": entry_reason,
            "session": self._session(opened_at),
            "status": self._status(net_pnl, closed_at),
            "source_deal_ids": source_deal_ids,
        }

    def _group_key(self, deal: RawDeal) -> str:
        position_id = self._position_id(deal)
        if position_id:
            return f"position:{position_id}"
        return f"{deal.symbol}:{self._direction(deal)}:{deal.deal_time.date().isoformat()}"

    def _is_balance_operation(self, deal: RawDeal) -> bool:
        text = f"{deal.symbol} {deal.entry_type} {deal.comment}".lower()
        return any(
            keyword in text
            for keyword in ("balance", "deposit", "withdraw", "credit")
        ) or not deal.symbol

    def _is_open_deal(self, deal: RawDeal) -> bool:
        value = (deal.entry_type or "").lower()
        return value in {"in", "entry_in", "open", "0"}

    def _is_close_deal(self, deal: RawDeal) -> bool:
        value = (deal.entry_type or "").lower()
        if value in {"out", "entry_out", "close", "1", "inout"}:
            return True
        return deal.profit != 0 or deal.commission != 0 or deal.swap != 0

    def _direction(self, deal: RawDeal) -> str:
        value = (deal.direction or "").lower()
        return "sell" if "sell" in value else "buy"

    def _weighted_price(self, deals: list[RawDeal]) -> float | None:
        priced_deals = [
            deal for deal in deals if deal.price is not None and abs(deal.volume) > 0
        ]
        if not priced_deals:
            return None
        total_volume = sum(abs(deal.volume) for deal in priced_deals)
        if total_volume == 0:
            return None
        return round(
            sum((deal.price or 0) * abs(deal.volume) for deal in priced_deals)
            / total_volume,
            8,
        )

    def _estimate_risk_amount(
        self,
        account_id: int,
        deals: list[RawDeal],
        opened_at: datetime,
    ) -> float | None:
        fixed_risk = self._fixed_risk_amount(account_id, opened_at.date())
        if fixed_risk is not None and fixed_risk > 0:
            return fixed_risk

        total_volume = sum(abs(deal.volume) for deal in deals)
        if total_volume <= 0:
            return None
        symbol = deals[0].symbol.upper()
        if "XAU" in symbol:
            return round(total_volume * 150, 2)
        if "JPY" in symbol:
            return round(total_volume * 80, 2)
        return round(total_volume * 100, 2)

    def _fixed_risk_amount(self, account_id: int, trade_date: date) -> float | None:
        settings = (
            self._db.query(GuardrailSetting)
            .filter(GuardrailSetting.account_id == account_id)
            .order_by(GuardrailSetting.id.desc())
            .first()
        )
        if settings is None:
            return None

        config = settings.settings or {}
        try:
            fixed_risk_percent = float(config.get("fixed_risk_percent") or 0)
        except (TypeError, ValueError):
            fixed_risk_percent = 0
        if fixed_risk_percent <= 0:
            return settings.max_risk_per_trade

        account_value = self._daily_start_account_value(account_id, trade_date)
        if account_value <= 0:
            return settings.max_risk_per_trade
        return round(account_value * fixed_risk_percent / 100, 2)

    def _daily_start_account_value(self, account_id: int, target_date: date) -> float:
        day_start_utc = datetime.combine(target_date, time.min) - timedelta(hours=7)
        day_end_utc = day_start_utc + timedelta(days=1)

        snapshot = (
            self._db.query(AccountSnapshot)
            .filter(
                AccountSnapshot.account_id == account_id,
                AccountSnapshot.captured_at <= day_start_utc,
            )
            .order_by(AccountSnapshot.captured_at.desc(), AccountSnapshot.id.desc())
            .first()
        )
        if snapshot is not None:
            return self._snapshot_account_value(snapshot)

        snapshot = (
            self._db.query(AccountSnapshot)
            .filter(
                AccountSnapshot.account_id == account_id,
                AccountSnapshot.captured_at >= day_start_utc,
                AccountSnapshot.captured_at < day_end_utc,
            )
            .order_by(AccountSnapshot.captured_at.asc(), AccountSnapshot.id.asc())
            .first()
        )
        if snapshot is not None:
            return self._snapshot_account_value(snapshot)

        snapshot = (
            self._db.query(AccountSnapshot)
            .filter(AccountSnapshot.account_id == account_id)
            .order_by(AccountSnapshot.captured_at.desc(), AccountSnapshot.id.desc())
            .first()
        )
        if snapshot is None:
            return 0
        return self._snapshot_account_value(snapshot)

    def _snapshot_account_value(self, snapshot: AccountSnapshot) -> float:
        return snapshot.balance or snapshot.equity or 0

    def _setup_tag(self, deals: list[RawDeal]) -> str | None:
        return self._comment(deals)

    def _comment(self, deals: list[RawDeal]) -> str | None:
        for deal in deals:
            comment = deal.comment.strip()
            if comment:
                return comment[:80]
        return None

    def _first_payload_float(
        self,
        deals: list[RawDeal],
        *keys: str,
    ) -> float | None:
        for deal in deals:
            payload = deal.raw_payload or {}
            for key in keys:
                value = payload.get(key)
                if value in (None, ""):
                    continue
                try:
                    return float(value)
                except (TypeError, ValueError):
                    continue
        return None

    def _position_id(self, deal: RawDeal) -> str | None:
        payload = deal.raw_payload or {}
        value = (
            payload.get("position_id")
            or payload.get("position")
            or payload.get("external_position_id")
        )
        if value in (None, "", 0, "0"):
            return None
        return str(value)

    def _session(self, opened_at: datetime) -> str:
        hour = opened_at.hour
        if 0 <= hour < 7:
            return "Asia"
        if 7 <= hour < 13:
            return "London"
        if 13 <= hour < 21:
            return "New York"
        return "After-hours"

    def _status(self, net_pnl: float, closed_at: datetime | None) -> str:
        if closed_at is None:
            return "open"
        if abs(net_pnl) < 0.000001:
            return "breakeven"
        return "closed"

