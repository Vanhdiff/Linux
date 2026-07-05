from datetime import date
from typing import Annotated

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.database import get_db
from app.schemas.news import (
    EconomicEventsIn,
    ForexFactoryImportRequest,
    NewsIngestResult,
    TradingViewImportRequest,
)
from app.services.forex_factory_service import ForexFactoryService
from app.services.news_service import NewsService
from app.services.trading_view_calendar_service import TradingViewCalendarService


router = APIRouter(prefix="/news", tags=["news"])
ingest_router = APIRouter(prefix="/ingest/news", tags=["news ingestion"])


@router.get("/calendar")
def calendar_view(
    db: Annotated[Session, Depends(get_db)],
    month: Annotated[str, Query(pattern=r"^\d{4}-\d{2}$")],
    currencies: Annotated[list[str] | None, Query()] = None,
    impacts: Annotated[list[str] | None, Query()] = None,
):
    return NewsService(db).calendar_view(month, currencies, impacts)


@router.get("/day")
def day_view(
    db: Annotated[Session, Depends(get_db)],
    event_date: Annotated[date, Query(alias="date")],
    currencies: Annotated[list[str] | None, Query()] = None,
    impacts: Annotated[list[str] | None, Query()] = None,
):
    return NewsService(db).day_view(event_date, currencies, impacts)


@router.get("/range")
def range_view(
    db: Annotated[Session, Depends(get_db)],
    start_date: Annotated[date, Query(alias="start")],
    end_date: Annotated[date, Query(alias="end")],
    currencies: Annotated[list[str] | None, Query()] = None,
    impacts: Annotated[list[str] | None, Query()] = None,
):
    return NewsService(db).range_view(start_date, end_date, currencies, impacts)


@router.get("/upcoming")
def upcoming(
    db: Annotated[Session, Depends(get_db)],
    hours: Annotated[int, Query(ge=1, le=720)] = 72,
    currencies: Annotated[list[str] | None, Query()] = None,
    impacts: Annotated[list[str] | None, Query()] = None,
):
    return NewsService(db).upcoming(hours, currencies, impacts)


@ingest_router.post("/events", response_model=NewsIngestResult)
def ingest_events(
    payload: EconomicEventsIn,
    db: Annotated[Session, Depends(get_db)],
):
    return NewsService(db).ingest_events(payload)


@ingest_router.post("/forexfactory", response_model=NewsIngestResult)
def import_forexfactory(
    db: Annotated[Session, Depends(get_db)],
    payload: ForexFactoryImportRequest | None = None,
):
    request = payload or ForexFactoryImportRequest()
    events = ForexFactoryService().fetch_events(request.weeks)
    return NewsService(db).ingest_events(
        EconomicEventsIn(source="forexfactory", events=events)
    )


@ingest_router.post("/tradingview", response_model=NewsIngestResult)
def import_tradingview(
    payload: TradingViewImportRequest,
    db: Annotated[Session, Depends(get_db)],
):
    events = TradingViewCalendarService().fetch_events(
        payload.start_date,
        payload.end_date,
    )
    return NewsService(db).ingest_events(
        EconomicEventsIn(source="tradingview", events=events)
    )

