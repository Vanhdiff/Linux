from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from app.database import get_db
from app.models import NormalizedTrade, TradeJournal
from app.schemas.trade_schema import (
    NormalizeResult,
    TradeJournalPatch,
    TradeJournalRead,
    TradeRead,
)
from app.services.normalize_service import NormalizationService


router = APIRouter(prefix="/trades", tags=["trades"])


@router.get("", response_model=list[TradeRead])
def list_trades(
    db: Annotated[Session, Depends(get_db)],
    account_id: Annotated[int | None, Query()] = None,
):
    query = db.query(NormalizedTrade).order_by(NormalizedTrade.opened_at.desc())
    if account_id is not None:
        query = query.filter(NormalizedTrade.account_id == account_id)
    return query.all()


@router.post("/sync-normalized", response_model=NormalizeResult)
def sync_normalized_trades(
    account_id: Annotated[int, Query(ge=1)],
    db: Annotated[Session, Depends(get_db)],
):
    return NormalizationService(db).sync_account(account_id)


@router.post("/normalize", response_model=NormalizeResult)
def normalize_trades(
    account_id: Annotated[int, Query(ge=1)],
    db: Annotated[Session, Depends(get_db)],
):
    return NormalizationService(db).sync_account(account_id)


@router.get("/{trade_id}", response_model=TradeRead)
def get_trade(trade_id: int, db: Annotated[Session, Depends(get_db)]):
    trade = db.get(NormalizedTrade, trade_id)
    if trade is None:
        raise HTTPException(status_code=404, detail="Trade not found")
    return trade


@router.patch("/{trade_id}/journal", response_model=TradeJournalRead)
def patch_trade_journal(
    trade_id: int,
    payload: TradeJournalPatch,
    db: Annotated[Session, Depends(get_db)],
):
    trade = db.get(NormalizedTrade, trade_id)
    if trade is None:
        raise HTTPException(status_code=404, detail="Trade not found")

    journal = (
        db.query(TradeJournal)
        .filter(TradeJournal.trade_id == trade_id)
        .one_or_none()
    )
    if journal is None:
        journal = TradeJournal(
            trade_id=trade_id,
            notes="",
            review_status="pending",
        )
        db.add(journal)

    for key, value in payload.model_dump(exclude_unset=True).items():
        setattr(journal, key, value)

    db.commit()
    db.refresh(journal)
    return journal

