from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from app.database import get_db
from app.models import NormalizedTrade, TradeJournal
from app.schemas.trade_schema import TradeJournalRead, TradeJournalWrite


router = APIRouter(prefix="/journals", tags=["journals"])


@router.get("", response_model=list[TradeJournalRead])
def list_journals(
    db: Annotated[Session, Depends(get_db)],
    account_id: Annotated[int | None, Query(ge=1)] = None,
):
    query = db.query(TradeJournal).join(NormalizedTrade)
    if account_id is not None:
        query = query.filter(NormalizedTrade.account_id == account_id)
    return query.order_by(NormalizedTrade.opened_at.desc()).all()


@router.get("/trades/{trade_id}", response_model=TradeJournalRead)
def get_trade_journal(trade_id: int, db: Annotated[Session, Depends(get_db)]):
    journal = (
        db.query(TradeJournal)
        .filter(TradeJournal.trade_id == trade_id)
        .one_or_none()
    )
    if journal is None:
        raise HTTPException(status_code=404, detail="Journal not found")
    return journal


@router.put("/trades/{trade_id}", response_model=TradeJournalRead)
def upsert_trade_journal(
    trade_id: int,
    payload: TradeJournalWrite,
    db: Annotated[Session, Depends(get_db)],
):
    trade = db.get(NormalizedTrade, trade_id)
    if trade is None:
        raise HTTPException(status_code=404, detail="Trade not found")

    values = payload.model_dump()
    journal = (
        db.query(TradeJournal)
        .filter(TradeJournal.trade_id == trade_id)
        .one_or_none()
    )

    if journal is None:
        journal = TradeJournal(trade_id=trade_id, **values)
        db.add(journal)
    else:
        for key, value in values.items():
            setattr(journal, key, value)

    db.commit()
    db.refresh(journal)
    return journal

