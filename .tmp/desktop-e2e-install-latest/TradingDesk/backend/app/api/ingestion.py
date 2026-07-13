from typing import Annotated

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.database import get_db
from app.schemas.mt5 import (
    IngestResult,
    Mt5AccountSnapshotIn,
    Mt5CandlesIn,
    Mt5DealsIn,
    Mt5OrdersIn,
    Mt5PositionsIn,
)
from app.services.import_service import Mt5IngestionService


router = APIRouter(prefix="/ingest/mt5", tags=["mt5 ingestion"])


@router.post("/account-snapshot", response_model=IngestResult)
def ingest_account_snapshot(
    payload: Mt5AccountSnapshotIn,
    db: Annotated[Session, Depends(get_db)],
):
    return Mt5IngestionService(db).save_account_snapshot(payload)


@router.post("/deals", response_model=IngestResult)
def ingest_deals(payload: Mt5DealsIn, db: Annotated[Session, Depends(get_db)]):
    return Mt5IngestionService(db).save_deals(payload)


@router.post("/orders", response_model=IngestResult)
def ingest_orders(payload: Mt5OrdersIn, db: Annotated[Session, Depends(get_db)]):
    return Mt5IngestionService(db).save_orders(payload)


@router.post("/positions", response_model=IngestResult)
def ingest_positions(
    payload: Mt5PositionsIn,
    db: Annotated[Session, Depends(get_db)],
):
    return Mt5IngestionService(db).save_positions(payload)


@router.post("/candles", response_model=IngestResult)
def ingest_candles(payload: Mt5CandlesIn, db: Annotated[Session, Depends(get_db)]):
    return Mt5IngestionService(db).save_candles(payload)

