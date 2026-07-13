from typing import Annotated

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.database import get_db
from app.services.analytics_service import AnalyticsService


router = APIRouter(prefix="/analytics", tags=["analytics"])


@router.get("/overview")
def overview(
    db: Annotated[Session, Depends(get_db)],
    account_id: Annotated[int | None, Query(ge=1)] = None,
):
    return AnalyticsService(db).overview(account_id)


@router.get("/daily")
def daily(
    db: Annotated[Session, Depends(get_db)],
    account_id: Annotated[int | None, Query(ge=1)] = None,
):
    return AnalyticsService(db).pnl_by_day(account_id)


@router.get("/daily-pnl")
def daily_pnl(
    db: Annotated[Session, Depends(get_db)],
    account_id: Annotated[int | None, Query(ge=1)] = None,
):
    return AnalyticsService(db).pnl_by_day(account_id)


@router.get("/drawdown")
def drawdown(
    db: Annotated[Session, Depends(get_db)],
    account_id: Annotated[int | None, Query(ge=1)] = None,
):
    return AnalyticsService(db).max_drawdown(account_id)


@router.get("/symbols")
def symbols(
    db: Annotated[Session, Depends(get_db)],
    account_id: Annotated[int | None, Query(ge=1)] = None,
):
    return AnalyticsService(db).symbols(account_id)


@router.get("/sessions")
def sessions(
    db: Annotated[Session, Depends(get_db)],
    account_id: Annotated[int | None, Query(ge=1)] = None,
):
    return AnalyticsService(db).sessions(account_id)


@router.get("/setups")
def setups(
    db: Annotated[Session, Depends(get_db)],
    account_id: Annotated[int | None, Query(ge=1)] = None,
):
    return AnalyticsService(db).setups(account_id)

