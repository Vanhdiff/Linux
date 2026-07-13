from datetime import datetime, timedelta, timezone

from fastapi import HTTPException
from sqlalchemy.orm import Session

from app.models import TradingAccount
from app.schemas.mt5 import (
    Mt5AccountSnapshotIn,
    Mt5DealsIn,
    Mt5OrdersIn,
    Mt5PositionsIn,
    Mt5SyncRequest,
    Mt5SyncResult,
)
from app.services.import_service import Mt5IngestionService
from app.services.mt5_service import Mt5Service


class Mt5SyncService:
    def __init__(self, db: Session, mt5_service: Mt5Service | None = None) -> None:
        self._db = db
        self._mt5_service = mt5_service or Mt5Service()

    def import_raw(self, payload: Mt5SyncRequest | None = None) -> Mt5SyncResult:
        payload = payload or Mt5SyncRequest()
        snapshot = self._mt5_service.market_snapshot(
            date_from=payload.date_from,
            date_to=payload.date_to,
            history_days=payload.history_days,
            payload=payload,
        )

        account = self._upsert_mt5_account(snapshot["account_info"], payload.account_id)
        ingestion = Mt5IngestionService(self._db)
        captured_at = datetime.now(timezone.utc)

        account_snapshot = ingestion.save_account_snapshot(
            Mt5AccountSnapshotIn(
                account_id=account.id,
                captured_at=captured_at,
                snapshot=snapshot["account_info"],
            )
        )
        positions = (
            ingestion.save_positions(
                Mt5PositionsIn(
                    account_id=account.id,
                    captured_at=captured_at,
                    positions=snapshot["positions"],
                )
            )
            if payload.include_positions
            else None
        )
        orders = (
            ingestion.save_orders(
                Mt5OrdersIn(account_id=account.id, orders=snapshot["orders"])
            )
            if payload.include_orders
            else None
        )
        deals = (
            ingestion.save_deals(Mt5DealsIn(account_id=account.id, deals=snapshot["deals"]))
            if payload.include_deals
            else None
        )
        if payload.include_deals:
            ingestion.prune_deals(
                account.id,
                snapshot["date_from"],
                snapshot["date_to"],
                {
                    str(item.get("external_deal_id") or item.get("deal") or item.get("ticket") or item.get("id") or "")
                    for item in snapshot["deals"]
                    if str(item.get("external_deal_id") or item.get("deal") or item.get("ticket") or item.get("id") or "")
                },
            )

        return Mt5SyncResult(
            account_id=account.id,
            account_login=account.login,
            snapshot=account_snapshot,
            positions=positions,
            orders=orders,
            deals=deals,
            date_from=snapshot["date_from"],
            date_to=snapshot["date_to"],
        )

    def import_live_state(self, payload: Mt5SyncRequest | None = None) -> Mt5SyncResult:
        payload = payload or Mt5SyncRequest(include_deals=False)
        account_info = self._mt5_service.account(payload)
        account = self._upsert_mt5_account(account_info, payload.account_id)
        ingestion = Mt5IngestionService(self._db)
        captured_at = datetime.now(timezone.utc)

        account_snapshot = ingestion.save_account_snapshot(
            Mt5AccountSnapshotIn(
                account_id=account.id,
                captured_at=captured_at,
                snapshot=account_info,
            )
        )
        positions = (
            ingestion.save_positions(
                Mt5PositionsIn(
                    account_id=account.id,
                    captured_at=captured_at,
                    positions=self._mt5_service.positions(payload),
                )
            )
            if payload.include_positions
            else None
        )
        orders = (
            ingestion.save_orders(
                Mt5OrdersIn(
                    account_id=account.id,
                    orders=self._mt5_service.orders(payload),
                )
            )
            if payload.include_orders
            else None
        )

        return Mt5SyncResult(
            account_id=account.id,
            account_login=account.login,
            snapshot=account_snapshot,
            positions=positions,
            orders=orders,
            deals=None,
            date_from=captured_at,
            date_to=captured_at,
        )

    def import_incremental_deals(
        self,
        *,
        account_id: int,
        history_days: int = 3,
        overlap_minutes: int = 5,
        payload: Mt5SyncRequest | None = None,
    ) -> Mt5SyncResult:
        base_payload = payload or Mt5SyncRequest(
            account_id=account_id,
            history_days=history_days,
            include_positions=True,
            include_orders=True,
            include_deals=True,
        )
        account = self._db.get(TradingAccount, account_id)
        if account is None:
            raise HTTPException(status_code=404, detail="Account not found")

        last_deal_time = self._latest_raw_deal_time(account_id)
        now = datetime.now(timezone.utc)
        date_from = (
            max(
                now - timedelta(days=history_days),
                last_deal_time - timedelta(minutes=overlap_minutes),
            )
            if last_deal_time is not None
            else now - timedelta(days=history_days)
        )
        date_to = now + timedelta(days=1)
        effective_payload = base_payload.model_copy(
            update={
                "account_id": account_id,
                "date_from": date_from,
                "date_to": date_to,
                "history_days": history_days,
                "include_positions": True,
                "include_orders": True,
                "include_deals": True,
            }
        )

        account_info = self._mt5_service.account(effective_payload)
        account = self._upsert_mt5_account(account_info, account_id)
        ingestion = Mt5IngestionService(self._db)
        captured_at = datetime.now(timezone.utc)
        deals_payload = self._mt5_service.history(
            date_from=date_from,
            date_to=date_to,
            history_days=history_days,
            payload=effective_payload,
        )

        account_snapshot = ingestion.save_account_snapshot(
            Mt5AccountSnapshotIn(
                account_id=account.id,
                captured_at=captured_at,
                snapshot=account_info,
            )
        )
        positions = ingestion.save_positions(
            Mt5PositionsIn(
                account_id=account.id,
                captured_at=captured_at,
                positions=self._mt5_service.positions(effective_payload),
            )
        )
        orders = ingestion.save_orders(
            Mt5OrdersIn(
                account_id=account.id,
                orders=self._mt5_service.orders(effective_payload),
            )
        )
        deals = ingestion.save_deals(
            Mt5DealsIn(account_id=account.id, deals=deals_payload)
        )
        ingestion.prune_deals(
            account.id,
            date_from,
            date_to,
            {
                str(
                    item.get("external_deal_id")
                    or item.get("deal")
                    or item.get("ticket")
                    or item.get("id")
                    or ""
                )
                for item in deals_payload
                if str(
                    item.get("external_deal_id")
                    or item.get("deal")
                    or item.get("ticket")
                    or item.get("id")
                    or ""
                )
            },
        )

        return Mt5SyncResult(
            account_id=account.id,
            account_login=account.login,
            snapshot=account_snapshot,
            positions=positions,
            orders=orders,
            deals=deals,
            date_from=date_from,
            date_to=date_to,
        )

    def _upsert_mt5_account(
        self,
        account_info: dict,
        account_id: int | None,
    ) -> TradingAccount:
        login = str(account_info.get("login") or "")
        if not login:
            raise HTTPException(status_code=422, detail="MT5 account login is missing")

        account = self._db.get(TradingAccount, account_id) if account_id is not None else None
        if account_id is not None and account is None:
            raise HTTPException(status_code=404, detail="Account not found")
        if account is None:
            account = (
                self._db.query(TradingAccount)
                .filter(TradingAccount.login == login)
                .one_or_none()
            )

        values = {
            "name": account_info.get("name") or "MT5 account",
            "broker": account_info.get("company") or "",
            "server": account_info.get("server") or "",
            "login": login,
            "currency": account_info.get("currency") or "USD",
        }
        if account is None:
            account = TradingAccount(**values)
            self._db.add(account)
        else:
            for key, value in values.items():
                setattr(account, key, value)

        self._db.flush()
        self._db.query(TradingAccount).filter(TradingAccount.id != account.id).update(
            {"is_active": False},
            synchronize_session=False,
        )
        account.is_active = True
        self._db.flush()
        return account

    def _latest_raw_deal_time(self, account_id: int) -> datetime | None:
        from app.models import RawDeal

        row = (
            self._db.query(RawDeal.deal_time)
            .filter(RawDeal.account_id == account_id)
            .order_by(RawDeal.deal_time.desc(), RawDeal.id.desc())
            .first()
        )
        if row is None:
            return None
        value = row[0]
        if value.tzinfo is None:
            return value.replace(tzinfo=timezone.utc)
        return value.astimezone(timezone.utc)
