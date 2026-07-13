from datetime import date
from typing import Annotated

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.database import get_db
from app.services.view_model_service import ViewModelService


router = APIRouter(prefix="/journal", tags=["journal"])


@router.get("/calendar")
def calendar_view(
    db: Annotated[Session, Depends(get_db)],
    month: Annotated[str, Query(pattern=r"^\d{4}-\d{2}$")],
    account_id: Annotated[int | None, Query(ge=1)] = None,
):
    return ViewModelService(db).journal_calendar(account_id, month)


@router.get("/day")
def day_view(
    db: Annotated[Session, Depends(get_db)],
    trade_date: Annotated[date, Query(alias="date")],
    account_id: Annotated[int | None, Query(ge=1)] = None,
):
    return ViewModelService(db).journal_day(account_id, trade_date)


@router.get("/month-summary")
def month_summary(
    db: Annotated[Session, Depends(get_db)],
    month: Annotated[str, Query(pattern=r"^\d{4}-\d{2}$")],
    account_id: Annotated[int | None, Query(ge=1)] = None,
):
    return ViewModelService(db).journal_month_summary(account_id, month)

