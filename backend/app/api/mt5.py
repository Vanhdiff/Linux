from datetime import datetime
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, Request, status
from sqlalchemy.orm import Session

from app.database import get_db
from app.schemas.mt5 import (
    Mt5AccountInfoResponse,
    Mt5BootstrapResult,
    Mt5ConnectRequest,
    Mt5ConnectResponse,
    Mt5ConnectionStatus,
    Mt5SyncRequest,
    Mt5SyncResult,
)
from app.services.guardrail_service import GuardrailService
from app.services.mt5_service import Mt5Service
from app.services.mt5_sync_service import Mt5SyncService
from app.services.normalize_service import NormalizationService


router = APIRouter(prefix="/mt5", tags=["mt5"])
mt5_service = Mt5Service()


@router.get("/status", response_model=Mt5ConnectionStatus)
def mt5_status():
    try:
        return mt5_service.status()
    except RuntimeError as exc:
        return Mt5ConnectionStatus(
            connected=False,
            mode="read_only",
            message=str(exc),
        )


@router.get("/trade-blocker/status")
def mt5_trade_blocker_status(request: Request):
    blocker = getattr(request.app.state, "mt5_trade_blocker", None)
    if blocker is None:
        return {"running": False, "accounts": {}}
    return blocker.last_result


@router.post("/trade-blocker/enforce-once")
def mt5_trade_blocker_enforce_once(request: Request):
    blocker = getattr(request.app.state, "mt5_trade_blocker", None)
    if blocker is None:
        return {"running": False, "accounts": {}}
    return blocker.enforce_once()


@router.post("/connect", response_model=Mt5ConnectResponse)
def mt5_connect(payload: Mt5ConnectRequest | None = None):
    try:
        return mt5_service.connect(payload)
    except RuntimeError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=str(exc),
        ) from exc


@router.post("/bootstrap", response_model=Mt5BootstrapResult)
def mt5_bootstrap(
    db: Annotated[Session, Depends(get_db)],
    payload: Mt5SyncRequest | None = None,
):
    try:
        sync_result = Mt5SyncService(db, mt5_service).import_raw(
            payload or Mt5SyncRequest(history_days=90)
        )
        normalized = NormalizationService(db).sync_account(sync_result.account_id)
        GuardrailService(db).status(sync_result.account_id)
        return Mt5BootstrapResult(
            connected=True,
            account_id=sync_result.account_id,
            account_login=sync_result.account_login,
            message="MT5 account is ready.",
            sync=sync_result,
            normalized=normalized.model_dump(),
        )
    except RuntimeError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=str(exc),
        ) from exc


@router.post("/sync", response_model=Mt5SyncResult)
def mt5_sync(
    db: Annotated[Session, Depends(get_db)],
    payload: Mt5SyncRequest | None = None,
):
    return _import_raw_from_mt5(db, payload)


@router.post("/import-raw", response_model=Mt5SyncResult)
def mt5_import_raw(
    db: Annotated[Session, Depends(get_db)],
    payload: Mt5SyncRequest | None = None,
):
    return _import_raw_from_mt5(db, payload)


def _import_raw_from_mt5(
    db: Session,
    payload: Mt5SyncRequest | None,
) -> Mt5SyncResult:
    try:
        return Mt5SyncService(db, mt5_service).import_raw(payload)
    except RuntimeError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=str(exc),
        ) from exc


@router.get("/account", response_model=Mt5AccountInfoResponse)
def mt5_account():
    try:
        return Mt5AccountInfoResponse(
            connected=True,
            account_info=mt5_service.account(),
        )
    except RuntimeError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=str(exc),
        ) from exc


@router.get("/account-info", response_model=Mt5AccountInfoResponse)
def mt5_account_info():
    try:
        return Mt5AccountInfoResponse(
            connected=True,
            account_info=mt5_service.account_info(),
        )
    except RuntimeError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=str(exc),
        ) from exc


@router.get("/positions")
def mt5_positions():
    try:
        positions = mt5_service.positions()
        return {"count": len(positions), "positions": positions}
    except RuntimeError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=str(exc),
        ) from exc


@router.get("/orders")
def mt5_orders():
    try:
        orders = mt5_service.orders()
        return {"count": len(orders), "orders": orders}
    except RuntimeError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=str(exc),
        ) from exc


@router.get("/history")
def mt5_history(
    history_days: Annotated[int, Query(ge=1, le=3650)] = 30,
    date_from: Annotated[datetime | None, Query()] = None,
    date_to: Annotated[datetime | None, Query()] = None,
):
    try:
        deals = mt5_service.history(
            date_from=date_from,
            date_to=date_to,
            history_days=history_days,
        )
        return {
            "count": len(deals),
            "history_days": history_days,
            "deals": deals,
        }
    except RuntimeError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=str(exc),
        ) from exc


@router.get("/symbols")
def mt5_symbols(
    group: Annotated[str | None, Query()] = None,
    limit: Annotated[int | None, Query(ge=1, le=5000)] = 200,
):
    try:
        symbols = mt5_service.symbols(group=group, limit=limit)
        return {"count": len(symbols), "symbols": symbols}
    except RuntimeError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=str(exc),
        ) from exc



