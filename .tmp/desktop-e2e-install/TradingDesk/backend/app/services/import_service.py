from datetime import datetime, timezone
from typing import Any

from fastapi import HTTPException
from sqlalchemy import delete
from sqlalchemy.orm import Session

from app.models import (
    AccountSnapshot,
    RawCandle,
    RawDeal,
    RawMt5Import,
    RawOrder,
    RawPosition,
    TradingAccount,
)
from app.schemas.mt5 import (
    IngestResult,
    Mt5AccountSnapshotIn,
    Mt5CandlesIn,
    Mt5DealsIn,
    Mt5OrdersIn,
    Mt5PositionsIn,
)


class Mt5IngestionService:
    def __init__(self, db: Session) -> None:
        self._db = db

    def save_account_snapshot(self, payload: Mt5AccountSnapshotIn) -> IngestResult:
        self._ensure_account(payload.account_id)
        imported = self._create_import(
            account_id=payload.account_id,
            import_type="account_snapshot",
            payload=payload.model_dump(mode="json"),
        )
        snapshot = payload.snapshot
        row = AccountSnapshot(
            account_id=payload.account_id,
            captured_at=payload.captured_at or _now(),
            balance=_float(snapshot, "balance"),
            equity=_float(snapshot, "equity"),
            margin=_float(snapshot, "margin"),
            free_margin=_float(snapshot, "free_margin", "margin_free"),
            margin_level=_optional_float(snapshot, "margin_level"),
            profit=_float(snapshot, "profit"),
            raw_payload=_json_safe(snapshot),
        )
        self._db.add(row)
        self._db.commit()
        return IngestResult(import_id=imported.id, saved=1)

    def save_deals(self, payload: Mt5DealsIn) -> IngestResult:
        self._ensure_account(payload.account_id)
        imported = self._create_import(
            account_id=payload.account_id,
            import_type="deals",
            payload=payload.model_dump(mode="json"),
        )
        saved = 0
        skipped = 0
        for item in payload.deals:
            external_deal_id = _string(item, "external_deal_id", "deal", "ticket", "id")
            if not external_deal_id:
                skipped += 1
                continue
            values = {
                "raw_import_id": imported.id,
                "external_order_id": _optional_string(
                    item,
                    "external_order_id",
                    "order",
                    "order_id",
                ),
                "symbol": _string(item, "symbol"),
                "direction": _optional_string(item, "direction", "type"),
                "entry_type": _optional_string(item, "entry_type", "entry"),
                "volume": _float(item, "volume"),
                "price": _optional_float(item, "price"),
                "profit": _float(item, "profit"),
                "commission": _float(item, "commission"),
                "swap": _float(item, "swap"),
                "deal_time": _datetime(item, "time", "deal_time", "created_at"),
                "comment": _string(item, "comment"),
                "raw_payload": _json_safe(item),
            }
            existing = self._raw_deal(payload.account_id, external_deal_id)
            if existing is not None:
                for key, value in values.items():
                    setattr(existing, key, value)
                skipped += 1
                continue
            self._db.add(
                RawDeal(
                    account_id=payload.account_id,
                    external_deal_id=external_deal_id,
                    **values,
                )
            )
            saved += 1
        self._db.commit()
        return IngestResult(import_id=imported.id, saved=saved, skipped=skipped)

    def prune_deals(
        self,
        account_id: int,
        date_from: datetime,
        date_to: datetime,
        external_deal_ids: set[str],
    ) -> int:
        self._ensure_account(account_id)
        query = (
            delete(RawDeal)
            .where(RawDeal.account_id == account_id)
            .where(RawDeal.deal_time >= date_from)
            .where(RawDeal.deal_time <= date_to)
        )
        if external_deal_ids:
            query = query.where(RawDeal.external_deal_id.not_in(external_deal_ids))
        result = self._db.execute(query)
        self._db.commit()
        return int(result.rowcount or 0)

    def save_orders(self, payload: Mt5OrdersIn) -> IngestResult:
        self._ensure_account(payload.account_id)
        imported = self._create_import(
            account_id=payload.account_id,
            import_type="orders",
            payload=payload.model_dump(mode="json"),
        )
        saved = 0
        skipped = 0
        for item in payload.orders:
            external_order_id = _string(item, "external_order_id", "order", "ticket", "id")
            if not external_order_id:
                skipped += 1
                continue
            if self._raw_order_exists(payload.account_id, external_order_id):
                skipped += 1
                continue
            self._db.add(
                RawOrder(
                    account_id=payload.account_id,
                    raw_import_id=imported.id,
                    external_order_id=external_order_id,
                    symbol=_string(item, "symbol"),
                    order_type=_string(item, "order_type", "type"),
                    volume_initial=_float(item, "volume_initial", "volume"),
                    volume_current=_float(item, "volume_current", "volume"),
                    price_open=_optional_float(item, "price_open", "open_price", "price"),
                    stop_loss=_optional_float(item, "stop_loss", "sl"),
                    take_profit=_optional_float(item, "take_profit", "tp"),
                    order_time=_optional_datetime(item, "time", "order_time"),
                    state=_string(item, "state", "status"),
                    comment=_string(item, "comment"),
                    raw_payload=_json_safe(item),
                )
            )
            saved += 1
        self._db.commit()
        return IngestResult(import_id=imported.id, saved=saved, skipped=skipped)

    def save_positions(self, payload: Mt5PositionsIn) -> IngestResult:
        self._ensure_account(payload.account_id)
        imported = self._create_import(
            account_id=payload.account_id,
            import_type="positions",
            payload=payload.model_dump(mode="json"),
        )
        captured_at = payload.captured_at or _now()
        saved = 0
        skipped = 0
        for item in payload.positions:
            external_position_id = _string(
                item,
                "external_position_id",
                "position",
                "ticket",
                "id",
            )
            if not external_position_id:
                skipped += 1
                continue
            self._db.add(
                RawPosition(
                    account_id=payload.account_id,
                    raw_import_id=imported.id,
                    external_position_id=external_position_id,
                    symbol=_string(item, "symbol"),
                    direction=_string(item, "direction", "type"),
                    volume=_float(item, "volume"),
                    open_price=_optional_float(item, "open_price", "price_open"),
                    current_price=_optional_float(item, "current_price", "price_current"),
                    stop_loss=_optional_float(item, "stop_loss", "sl"),
                    take_profit=_optional_float(item, "take_profit", "tp"),
                    profit=_float(item, "profit"),
                    swap=_float(item, "swap"),
                    commission=_float(item, "commission"),
                    opened_at=_optional_datetime(item, "opened_at", "time"),
                    captured_at=captured_at,
                    raw_payload=_json_safe(item),
                )
            )
            saved += 1
        self._db.commit()
        return IngestResult(import_id=imported.id, saved=saved, skipped=skipped)

    def save_candles(self, payload: Mt5CandlesIn) -> IngestResult:
        self._ensure_account(payload.account_id)
        imported = self._create_import(
            account_id=payload.account_id,
            import_type="candles",
            payload=payload.model_dump(mode="json"),
        )
        saved = 0
        skipped = 0
        for item in payload.candles:
            candle_time = _datetime(item, "time", "candle_time")
            if self._raw_candle_exists(
                payload.account_id,
                payload.symbol,
                payload.timeframe,
                candle_time,
            ):
                skipped += 1
                continue
            self._db.add(
                RawCandle(
                    account_id=payload.account_id,
                    raw_import_id=imported.id,
                    symbol=payload.symbol.upper(),
                    timeframe=payload.timeframe.upper(),
                    candle_time=candle_time,
                    open=_float(item, "open"),
                    high=_float(item, "high"),
                    low=_float(item, "low"),
                    close=_float(item, "close"),
                    tick_volume=int(_float(item, "tick_volume", "volume")),
                    raw_payload=_json_safe(item),
                )
            )
            saved += 1
        self._db.commit()
        return IngestResult(import_id=imported.id, saved=saved, skipped=skipped)

    def _ensure_account(self, account_id: int) -> TradingAccount:
        account = self._db.get(TradingAccount, account_id)
        if account is None:
            raise HTTPException(status_code=404, detail="Account not found")
        return account

    def _create_import(
        self,
        *,
        account_id: int,
        import_type: str,
        payload: dict[str, Any],
    ) -> RawMt5Import:
        imported = RawMt5Import(
            account_id=account_id,
            import_type=import_type,
            payload=payload,
        )
        self._db.add(imported)
        self._db.flush()
        return imported

    def _raw_deal_exists(self, account_id: int, external_deal_id: str) -> bool:
        return self._raw_deal(account_id, external_deal_id) is not None

    def _raw_deal(self, account_id: int, external_deal_id: str) -> RawDeal | None:
        return (
            self._db.query(RawDeal)
            .filter(
                RawDeal.account_id == account_id,
                RawDeal.external_deal_id == external_deal_id,
            )
            .one_or_none()
        )

    def _raw_order_exists(self, account_id: int, external_order_id: str) -> bool:
        return (
            self._db.query(RawOrder.id)
            .filter(
                RawOrder.account_id == account_id,
                RawOrder.external_order_id == external_order_id,
            )
            .first()
            is not None
        )

    def _raw_candle_exists(
        self,
        account_id: int,
        symbol: str,
        timeframe: str,
        candle_time: datetime,
    ) -> bool:
        return (
            self._db.query(RawCandle.id)
            .filter(
                RawCandle.account_id == account_id,
                RawCandle.symbol == symbol.upper(),
                RawCandle.timeframe == timeframe.upper(),
                RawCandle.candle_time == candle_time,
            )
            .first()
            is not None
        )


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _json_safe(value: Any) -> Any:
    if isinstance(value, datetime):
        return value.isoformat()
    if isinstance(value, dict):
        return {key: _json_safe(item) for key, item in value.items()}
    if isinstance(value, list):
        return [_json_safe(item) for item in value]
    if isinstance(value, tuple):
        return [_json_safe(item) for item in value]
    return value


def _value(item: dict[str, Any], *keys: str) -> Any:
    for key in keys:
        if key in item and item[key] is not None:
            return item[key]
    return None


def _string(item: dict[str, Any], *keys: str) -> str:
    value = _value(item, *keys)
    return "" if value is None else str(value)


def _optional_string(item: dict[str, Any], *keys: str) -> str | None:
    value = _string(item, *keys)
    return value or None


def _float(item: dict[str, Any], *keys: str) -> float:
    value = _value(item, *keys)
    if value in (None, ""):
        return 0.0
    return float(value)


def _optional_float(item: dict[str, Any], *keys: str) -> float | None:
    value = _value(item, *keys)
    if value in (None, ""):
        return None
    return float(value)


def _datetime(item: dict[str, Any], *keys: str) -> datetime:
    value = _value(item, *keys)
    if value in (None, ""):
        return _now()
    if isinstance(value, datetime):
        return value
    if isinstance(value, int | float):
        return datetime.fromtimestamp(value, tz=timezone.utc)
    return datetime.fromisoformat(str(value))


def _optional_datetime(item: dict[str, Any], *keys: str) -> datetime | None:
    value = _value(item, *keys)
    if value in (None, ""):
        return None
    return _datetime(item, *keys)

