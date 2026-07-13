from __future__ import annotations

import json
import urllib.parse
import urllib.request
from datetime import date, datetime, time, timezone

from app.schemas.news import EconomicEventIn


class TradingViewCalendarService:
    _URL = "https://economic-calendar.tradingview.com/events"

    def fetch_events(
        self,
        start_date: date,
        end_date: date,
    ) -> list[EconomicEventIn]:
        start = datetime.combine(start_date, time.min, tzinfo=timezone.utc)
        end = datetime.combine(end_date, time.max, tzinfo=timezone.utc)
        params = urllib.parse.urlencode(
            {
                "from": start.isoformat().replace("+00:00", "Z"),
                "to": end.isoformat().replace("+00:00", "Z"),
            }
        )
        request = urllib.request.Request(
            f"{self._URL}?{params}",
            headers={
                "User-Agent": (
                    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                    "AppleWebKit/537.36 (KHTML, like Gecko) "
                    "Chrome/125.0 Safari/537.36"
                ),
                "Origin": "https://www.tradingview.com",
                "Referer": "https://www.tradingview.com/",
                "Accept": "application/json",
            },
        )
        with urllib.request.urlopen(request, timeout=25) as response:
            payload = json.loads(response.read().decode("utf-8"))

        return [
            event
            for raw_event in payload.get("result", [])
            if (event := self._event_from_json(raw_event)) is not None
        ]

    def _event_from_json(self, data: dict) -> EconomicEventIn | None:
        event_id = str(data.get("id") or "").strip()
        title = str(data.get("title") or "").strip()
        currency = str(data.get("currency") or data.get("country") or "").strip()
        date_text = str(data.get("date") or "").strip()
        if not event_id or not title or not currency or not date_text:
            return None

        event_time = self._parse_event_time(date_text)
        return EconomicEventIn(
            source="tradingview",
            external_event_id=f"tv-{event_id}-{event_time.date().isoformat()}",
            event_time=event_time,
            currency=currency,
            impact=self._impact_from_importance(data),
            title=title,
            actual=self._value(data.get("actual")),
            forecast=self._value(data.get("forecast")),
            previous=self._value(data.get("previous")),
            raw_payload={"provider": "tradingview", **data},
        )

    def _parse_event_time(self, value: str) -> datetime:
        normalized = value.strip().replace("Z", "+00:00")
        parsed = datetime.fromisoformat(normalized)
        if parsed.tzinfo is None:
            return parsed.replace(tzinfo=timezone.utc)
        return parsed.astimezone(timezone.utc)

    def _impact_from_importance(self, data: dict) -> str:
        importance = data.get("importance")
        category = str(data.get("category") or "").lower()
        indicator = str(data.get("indicator") or "").lower()
        if category == "gov" and "holiday" in indicator:
            return "holiday"
        if importance == 1:
            return "high"
        if importance == 0:
            return "medium"
        if importance == -1:
            return "low"
        return "unknown"

    def _value(self, value: object) -> str | None:
        if value is None:
            return None
        text = str(value).strip()
        return text or None
