from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, Request, status
from sqlalchemy.orm import Session

from app.database import get_db
from app.schemas.mt5 import Mt5SyncRequest
from app.services.mt5_sync_service import Mt5SyncService
from app.services.normalize_service import NormalizationService
from app.services.view_model_service import ViewModelService


router = APIRouter(prefix="/dashboard", tags=["dashboard"])


@router.get("")
def dashboard(
    db: Annotated[Session, Depends(get_db)],
    account_id: Annotated[int | None, Query(ge=1)] = None,
    refresh_mt5: Annotated[bool, Query()] = False,
    history_days: Annotated[int, Query(ge=1, le=3650)] = 30,
    period: Annotated[str, Query(pattern="^(day|week|month)$")] = "day",
):
    dashboard_account_id = account_id
    if refresh_mt5:
        try:
            imported = Mt5SyncService(db).import_raw(
                Mt5SyncRequest(account_id=account_id, history_days=history_days)
            )
            NormalizationService(db).sync_account(imported.account_id)
            dashboard_account_id = imported.account_id
        except RuntimeError as exc:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail=str(exc),
            ) from exc

    return ViewModelService(db).dashboard(dashboard_account_id, period=period)


@router.get("/live-state")
def dashboard_live_state(
    request: Request,
    db: Annotated[Session, Depends(get_db)],
    account_id: Annotated[int | None, Query(ge=1)] = None,
):
    payload = ViewModelService(db).live_state(account_id)
    blocker = getattr(request.app.state, "mt5_trade_blocker", None)
    if blocker is None:
        payload["protection"] = {
            "backend_blocker_running": False,
            "blocked": bool(payload.get("block_state", {}).get("active")),
            "reasons": [],
            "live_poll": {
                "attempted": False,
                "synced": False,
                "source": "live_account_polling",
                "reason": "mt5_trade_blocker_not_running",
            },
            "incremental_sync": {
                "attempted": False,
                "synced": False,
                "source": "incremental_deal_sync",
                "reason": "mt5_trade_blocker_not_running",
            },
            "latency": None,
            "last_checked_at": None,
        }
        return payload

    accounts = blocker.last_result.get("accounts", {}) if isinstance(blocker.last_result, dict) else {}
    account_state = accounts.get(str(account_id), {}) if account_id is not None else {}
    payload["protection"] = {
        "backend_blocker_running": bool(
            blocker.last_result.get("running")
            if isinstance(blocker.last_result, dict)
            else False
        ),
        "blocked": bool(account_state.get("blocked") or payload.get("block_state", {}).get("active")),
        "reasons": account_state.get("reasons", []),
        "live_poll": (
            account_state.get("live_poll") or blocker._cached_live_poll_result(account_id)
            if account_id is not None
            else None
        ),
        "incremental_sync": (
            account_state.get("sync") or blocker._cached_sync_result(account_id)
            if account_id is not None
            else None
        ),
        "latency": account_state.get("latency"),
        "last_checked_at": blocker.last_result.get("checked_at")
        if isinstance(blocker.last_result, dict)
        else None,
    }
    return payload

