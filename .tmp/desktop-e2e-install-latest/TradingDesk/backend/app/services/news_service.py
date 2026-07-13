import calendar
from datetime import date, datetime, time, timedelta, timezone

from sqlalchemy.orm import Session

from app.models import EconomicEvent
from app.schemas.news import EconomicEventIn, EconomicEventsIn, NewsIngestResult


class NewsService:
    def __init__(self, db: Session) -> None:
        self._db = db

    def ingest_events(self, payload: EconomicEventsIn) -> NewsIngestResult:
        saved = 0
        updated = 0
        skipped = 0

        for event in payload.events:
            source = event.source or payload.source
            if not event.external_event_id:
                skipped += 1
                continue

            existing = (
                self._db.query(EconomicEvent)
                .filter(
                    EconomicEvent.source == source,
                    EconomicEvent.external_event_id == event.external_event_id,
                )
                .one_or_none()
            )
            values = self._event_values(event, source)
            if existing is None:
                self._db.add(EconomicEvent(**values))
                saved += 1
            else:
                for key, value in values.items():
                    setattr(existing, key, value)
                updated += 1

        self._db.commit()
        return NewsIngestResult(saved=saved, updated=updated, skipped=skipped)

    def calendar_view(
        self,
        month: str,
        currencies: list[str] | None = None,
        impacts: list[str] | None = None,
    ) -> dict:
        start, end = self._month_bounds(month)
        events = self._events_between(start, end, currencies, impacts)
        grouped: dict[date, list[EconomicEvent]] = {}
        for event in events:
            grouped.setdefault(event.event_time.date(), []).append(event)

        days = []
        for day in range(1, calendar.monthrange(start.year, start.month)[1] + 1):
            event_date = date(start.year, start.month, day)
            day_events = grouped.get(event_date, [])
            days.append(
                {
                    "date": event_date.isoformat(),
                    "counts": self._impact_counts(day_events),
                    "events": [self._event_payload(event) for event in day_events],
                }
            )

        return {
            "source_priority": ["cache", "mt5_bridge", "online_provider"],
            "month": month,
            "days": days,
        }

    def range_view(
        self,
        start_date: date,
        end_date: date,
        currencies: list[str] | None = None,
        impacts: list[str] | None = None,
    ) -> dict:
        events = self._events_between(start_date, end_date, currencies, impacts)
        grouped: dict[date, list[EconomicEvent]] = {}
        for event in events:
            grouped.setdefault(event.event_time.date(), []).append(event)

        day_count = (end_date - start_date).days + 1
        days = []
        for offset in range(max(day_count, 0)):
            event_date = start_date + timedelta(days=offset)
            day_events = grouped.get(event_date, [])
            days.append(
                {
                    "date": event_date.isoformat(),
                    "counts": self._impact_counts(day_events),
                    "events": [self._event_payload(event) for event in day_events],
                }
            )

        return {
            "from": start_date.isoformat(),
            "to": end_date.isoformat(),
            "days": days,
        }

    def day_view(
        self,
        event_date: date,
        currencies: list[str] | None = None,
        impacts: list[str] | None = None,
    ) -> dict:
        events = self._events_between(event_date, event_date, currencies, impacts)
        return {
            "date": event_date.isoformat(),
            "counts": self._impact_counts(events),
            "events": [self._event_payload(event) for event in events],
        }

    def upcoming(
        self,
        hours: int = 72,
        currencies: list[str] | None = None,
        impacts: list[str] | None = None,
    ) -> dict:
        start = datetime.now(timezone.utc)
        end = start + timedelta(hours=hours)
        events = self._query_events(start, end, currencies, impacts)
        return {
            "from": start.isoformat(),
            "to": end.isoformat(),
            "events": [self._event_payload(event) for event in events],
        }

    def _event_values(self, event: EconomicEventIn, source: str) -> dict:
        raw_payload = event.raw_payload or event.model_dump(mode="json")
        return {
            "source": source,
            "external_event_id": event.external_event_id,
            "event_time": event.event_time,
            "currency": event.currency.upper(),
            "impact": event.impact,
            "title": event.title,
            "actual": event.actual,
            "forecast": event.forecast,
            "previous": event.previous,
            "raw_payload": raw_payload,
        }

    def _events_between(
        self,
        start_date: date,
        end_date: date,
        currencies: list[str] | None,
        impacts: list[str] | None,
    ) -> list[EconomicEvent]:
        start = datetime.combine(start_date, time.min)
        end = datetime.combine(end_date, time.max)
        return self._query_events(start, end, currencies, impacts)

    def _query_events(
        self,
        start: datetime,
        end: datetime,
        currencies: list[str] | None,
        impacts: list[str] | None,
    ) -> list[EconomicEvent]:
        query = self._db.query(EconomicEvent).filter(
            EconomicEvent.event_time >= start,
            EconomicEvent.event_time <= end,
        )
        currencies = self._normalize_filter_values(currencies)
        impacts = self._normalize_filter_values(impacts)
        if currencies:
            query = query.filter(
                EconomicEvent.currency.in_([currency.upper() for currency in currencies])
            )
        if impacts:
            query = query.filter(
                EconomicEvent.impact.in_([impact.lower() for impact in impacts])
            )
        return query.order_by(EconomicEvent.event_time.asc(), EconomicEvent.id.asc()).all()

    def _normalize_filter_values(self, values: list[str] | None) -> list[str]:
        if not values:
            return []
        normalized: list[str] = []
        for value in values:
            normalized.extend(
                item.strip() for item in value.split(",") if item.strip()
            )
        return normalized

    def _month_bounds(self, month: str) -> tuple[date, date]:
        year, month_number = (int(part) for part in month.split("-", maxsplit=1))
        last_day = calendar.monthrange(year, month_number)[1]
        return date(year, month_number, 1), date(year, month_number, last_day)

    def _impact_counts(self, events: list[EconomicEvent]) -> dict:
        counts = {"high": 0, "medium": 0, "low": 0, "holiday": 0, "unknown": 0}
        for event in events:
            impact = event.impact if event.impact in counts else "unknown"
            counts[impact] += 1
        return counts

    def _event_payload(self, event: EconomicEvent) -> dict:
        return {
            "id": event.id,
            "source": event.source,
            "external_event_id": event.external_event_id,
            "event_time": event.event_time.isoformat(),
            "currency": event.currency,
            "impact": event.impact,
            "title": event.title,
            "actual": event.actual,
            "forecast": event.forecast,
            "previous": event.previous,
        }

