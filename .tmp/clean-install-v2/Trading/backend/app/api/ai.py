from datetime import date
from typing import Annotated

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from app.database import get_db
from app.services.ai_service import AiCoachService


router = APIRouter(prefix="/ai", tags=["ai"])


class AiChatRequest(BaseModel):
    question: str = Field(min_length=1, max_length=900)


@router.get("/context")
def ai_context(
    db: Annotated[Session, Depends(get_db)],
    period: Annotated[str, Query(pattern="^(day|week|month)$")] = "day",
    account_id: Annotated[int | None, Query(ge=1)] = None,
    target_date: Annotated[date | None, Query(alias="date")] = None,
):
    return AiCoachService(db).context(account_id, period, target_date)


@router.post("/daily-review")
def daily_review(
    db: Annotated[Session, Depends(get_db)],
    account_id: Annotated[int | None, Query(ge=1)] = None,
    target_date: Annotated[date | None, Query(alias="date")] = None,
    language: Annotated[str, Query(pattern="^(en|vi)$")] = "en",
):
    return AiCoachService(db).daily_review(account_id, target_date, language)


@router.post("/weekly-review")
def weekly_review(
    db: Annotated[Session, Depends(get_db)],
    account_id: Annotated[int | None, Query(ge=1)] = None,
    target_date: Annotated[date | None, Query(alias="date")] = None,
    language: Annotated[str, Query(pattern="^(en|vi)$")] = "en",
):
    return AiCoachService(db).weekly_review(account_id, target_date, language)


@router.post("/monthly-review")
def monthly_review(
    db: Annotated[Session, Depends(get_db)],
    account_id: Annotated[int | None, Query(ge=1)] = None,
    target_date: Annotated[date | None, Query(alias="date")] = None,
    language: Annotated[str, Query(pattern="^(en|vi)$")] = "en",
):
    return AiCoachService(db).monthly_review(account_id, target_date, language)


@router.post("/trade-review/{trade_id}")
def trade_review(
    trade_id: int,
    db: Annotated[Session, Depends(get_db)],
    account_id: Annotated[int | None, Query(ge=1)] = None,
    language: Annotated[str, Query(pattern="^(en|vi)$")] = "en",
):
    return AiCoachService(db).trade_review(account_id, trade_id, language)


@router.post("/chat")
def ai_chat(
    payload: AiChatRequest,
    db: Annotated[Session, Depends(get_db)],
    account_id: Annotated[int | None, Query(ge=1)] = None,
    language: Annotated[str, Query(pattern="^(en|vi)$")] = "en",
):
    return AiCoachService(db).chat(account_id, payload.question, language)
