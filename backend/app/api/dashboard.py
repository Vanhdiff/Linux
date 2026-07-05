from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, status
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

