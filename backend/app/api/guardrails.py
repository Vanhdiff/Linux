from datetime import date
from typing import Annotated

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.database import get_db
from app.schemas.guardrail import (
    GuardrailSettingsPatch,
    GuardrailSettingsRead,
    RuleBreakRead,
)
from app.services.guardrail_service import GuardrailService


router = APIRouter(prefix="/guardrails", tags=["guardrails"])


@router.get("/status")
def status(
    db: Annotated[Session, Depends(get_db)],
    account_id: Annotated[int, Query(ge=1)],
    trade_date: Annotated[date | None, Query(alias="date")] = None,
):
    return GuardrailService(db).status(account_id, trade_date)


@router.get("/trade-block")
def trade_block_status(
    db: Annotated[Session, Depends(get_db)],
    account_id: Annotated[int, Query(ge=1)],
    trade_date: Annotated[date | None, Query(alias="date")] = None,
):
    return GuardrailService(db).trade_block_status(account_id, trade_date)


@router.patch("/settings", response_model=GuardrailSettingsRead)
def patch_settings(
    payload: GuardrailSettingsPatch,
    db: Annotated[Session, Depends(get_db)],
    account_id: Annotated[int, Query(ge=1)],
):
    return GuardrailService(db).patch_settings(account_id, payload)


@router.get("/rule-breaks", response_model=list[RuleBreakRead])
def rule_breaks(
    db: Annotated[Session, Depends(get_db)],
    account_id: Annotated[int, Query(ge=1)],
    include_resolved: bool = False,
):
    return GuardrailService(db).rule_breaks(account_id, include_resolved)

