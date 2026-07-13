from datetime import datetime, timezone
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, Request, status
from sqlalchemy.orm import Session

from app.application.mt5_demo_harness import Mt5DemoHarnessService
from app.application.mt5_ea_installer import Mt5EAInstallerService
from app.application.mt5_protection import EACommunicationLayer
from app.application.mt5_setup_manager import Mt5EASetupRepairService
from app.database import get_db
from app.schemas.mt5 import (
    Mt5AccountInfoResponse,
    Mt5BootstrapResult,
    Mt5ConnectRequest,
    Mt5ConnectResponse,
    Mt5EACommandRequest,
    Mt5EAConfigWriteRequest,
    Mt5EARepairRequest,
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


@router.get("/protection/status")
def mt5_protection_status(
    request: Request,
    account_id: Annotated[int | None, Query()] = None,
):
    blocker = getattr(request.app.state, "mt5_trade_blocker", None)
    if blocker is None or not hasattr(blocker, "protection_status"):
        return {
            "level": "OFF",
            "reason": "MT5 block enforcer is not running",
            "backend_blocker_running": False,
            "ea": {
                "connected": False,
                "stale": False,
                "last_heartbeat": None,
                "version": "",
                "account_id": None,
                "error": "MT5 block enforcer is not running",
            },
            "diagnostics": EACommunicationLayer().diagnostics(account_id=account_id),
            "accounts": {},
            "last_checked_at": None,
        }
    return blocker.protection_status(account_id=account_id)


@router.get("/ea/status")
def mt5_ea_status(
    request: Request,
    account_id: Annotated[int | None, Query()] = None,
):
    blocker = getattr(request.app.state, "mt5_trade_blocker", None)
    if blocker is None or not hasattr(blocker, "get_ea_status"):
        diagnostics = EACommunicationLayer().diagnostics(account_id=account_id)
        return {
            "connected": False,
            "last_heartbeat": None,
            "version": "",
            "account_id": None,
            "error": "MT5 block enforcer is not running",
            "stale": False,
            "diagnostics": diagnostics,
        }
    status_obj = blocker.get_ea_status()
    diagnostics_account_id = account_id if account_id is not None else status_obj.account_id
    return {
        "connected": status_obj.connected,
        "last_heartbeat": status_obj.last_heartbeat.isoformat() if status_obj.last_heartbeat else None,
        "version": status_obj.version,
        "account_id": status_obj.account_id,
        "error": status_obj.error,
        "stale": getattr(status_obj, "stale", False),
        "diagnostics": blocker.get_ea_diagnostics(account_id=diagnostics_account_id),
    }


@router.get("/ea/install/status")
def mt5_ea_install_status():
    return Mt5EAInstallerService().status()


@router.post("/ea/install")
def mt5_ea_install(
    terminal_id: Annotated[str | None, Query()] = None,
    compile_after_install: Annotated[bool, Query()] = True,
):
    return Mt5EAInstallerService().install(
        terminal_id=terminal_id,
        compile_after_install=compile_after_install,
    )


@router.post("/ea/compile")
def mt5_ea_compile(terminal_id: Annotated[str | None, Query()] = None):
    return Mt5EAInstallerService().compile(terminal_id=terminal_id)


@router.post("/ea/repair")
def mt5_ea_repair(payload: Mt5EARepairRequest | None = None):
    request_payload = payload or Mt5EARepairRequest()
    return Mt5EASetupRepairService().repair(
        account_id=request_payload.account_id,
        terminal_id=request_payload.terminal_id,
        backend_base_url=request_payload.backend_base_url,
        compile_after_install=request_payload.compile_after_install,
    )


@router.get("/ea/config")
def mt5_ea_config():
    layer = EACommunicationLayer()
    return {
        "config": layer.read_ea_config(),
        "diagnostics": layer.diagnostics(),
    }


@router.post("/ea/config")
def mt5_ea_config_write(payload: Mt5EAConfigWriteRequest):
    layer = EACommunicationLayer()
    updates = payload.model_dump(
        exclude_none=True,
        exclude={"account_id", "backend_base_url"},
    )
    config = layer.write_ea_config(
        account_id=payload.account_id,
        backend_base_url=payload.backend_base_url,
        updates=updates,
    )
    return {
        "written": True,
        "config": config,
        "diagnostics": layer.diagnostics(account_id=payload.account_id),
    }


@router.get("/ea/command")
def mt5_ea_command():
    layer = EACommunicationLayer()
    return {
        "command": layer.read_ea_command(),
        "diagnostics": layer.diagnostics(),
    }


@router.post("/ea/command")
def mt5_ea_command_queue(payload: Mt5EACommandRequest):
    layer = EACommunicationLayer()
    command = layer.queue_ea_command(
        command_type=payload.command_type,
        account_id=payload.account_id,
        payload=payload.payload,
        command_id=payload.command_id,
    )
    return {
        "queued": True,
        "command": command,
        "diagnostics": layer.diagnostics(account_id=payload.account_id),
    }


@router.delete("/ea/command")
def mt5_ea_command_clear():
    layer = EACommunicationLayer()
    cleared = layer.clear_ea_command()
    return {
        "cleared": cleared,
        "diagnostics": layer.diagnostics(),
    }


@router.get("/ea/setup/report")
def mt5_ea_setup_report(
    request: Request,
    account_id: Annotated[int | None, Query()] = None,
):
    installer_status = Mt5EAInstallerService().status()
    blocker = getattr(request.app.state, "mt5_trade_blocker", None)
    if blocker is not None and hasattr(blocker, "protection_status"):
        protection_status = blocker.protection_status(account_id=account_id)
        ea = protection_status.get("ea", {})
        diagnostics = protection_status.get("diagnostics", {})
    else:
        ea_layer = EACommunicationLayer()
        ea_status = ea_layer.read_ea_status()
        diagnostics = ea_layer.diagnostics(account_id=account_id)
        ea = {
            "connected": ea_status.connected,
            "stale": ea_status.stale,
            "last_heartbeat": ea_status.last_heartbeat.isoformat()
            if ea_status.last_heartbeat
            else None,
            "version": ea_status.version,
            "account_id": ea_status.account_id,
            "error": ea_status.error,
        }
        protection_status = {
            "level": "OFF",
            "reason": "MT5 block enforcer is not running",
            "backend_blocker_running": False,
            "ea": ea,
            "diagnostics": diagnostics,
            "accounts": {},
            "last_checked_at": None,
        }

    return {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "account_id": account_id,
        "installer": installer_status,
        "ea": ea,
        "protection": protection_status,
        "diagnostics": diagnostics,
        "ready": (
            installer_status.get("terminal_count", 0) > 0
            and installer_status.get("installed_count", 0) > 0
            and installer_status.get("compiled_count", 0) > 0
            and bool(ea.get("connected"))
            and not bool(ea.get("stale"))
        ),
    }


@router.get("/demo-harness/report")
def mt5_demo_harness_report(
    request: Request,
    account_id: Annotated[int | None, Query()] = None,
):
    blocker = getattr(request.app.state, "mt5_trade_blocker", None)
    resolved_account_id = account_id
    if resolved_account_id is None and blocker is not None and hasattr(blocker, "get_ea_status"):
        resolved_account_id = blocker.get_ea_status().account_id
    if resolved_account_id is None:
        resolved_account_id = 1
    return Mt5DemoHarnessService().report(
        account_id=resolved_account_id,
        blocker=blocker,
    )


@router.post("/ea/open-experts")
def mt5_ea_open_experts(terminal_id: Annotated[str | None, Query()] = None):
    return Mt5EAInstallerService().open_experts_folder(terminal_id=terminal_id)


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



