from __future__ import annotations

import hashlib
import json
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET
from datetime import datetime, time, timezone
from zoneinfo import ZoneInfo

from app.schemas.news import EconomicEventIn


class ForexFactoryService:
    _URLS = {
        "last": "https://nfs.faireconomy.media/ff_calendar_lastweek.xml",
        "this": "https://nfs.faireconomy.media/ff_calendar_thisweek.xml",
        "next": "https://nfs.faireconomy.media/ff_calendar_nextweek.xml",
    }
    _JSON_URLS = {
        "last": "https://nfs.faireconomy.media/ff_calendar_lastweek.json",
        "this": "https://nfs.faireconomy.media/ff_calendar_thisweek.json",
        "next": "https://nfs.faireconomy.media/ff_calendar_nextweek.json",
    }

    def fetch_events(self, weeks: list[str]) -> list[EconomicEventIn]:
        events: list[EconomicEventIn] = []
        for week in dict.fromkeys(weeks):
            if week not in self._URLS:
                continue
            events.extend(self._fetch_week(week))
        return events

    def _fetch_week(self, week: str) -> list[EconomicEventIn]:
        json_payload = self._fetch_payload(
            self._JSON_URLS[week],
            "application/json,text/json,*/*",
        )
        if json_payload:
            return self._events_from_json(json_payload, week)

        xml_payload = self._fetch_payload(
            self._URLS[week],
            "application/xml,text/xml,*/*",
        )
        if not xml_payload:
            return []

        root = ET.fromstring(xml_payload)
        return [
            event
            for event_node in root.findall(".//event")
            if (event := self._event_from_xml(event_node, week)) is not None
        ]

    def _fetch_payload(self, url: str, accept: str) -> bytes | None:
        request = urllib.request.Request(
            url,
            headers={
                "User-Agent": (
                    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                    "AppleWebKit/537.36 (KHTML, like Gecko) "
                    "Chrome/125.0 Safari/537.36"
                ),
                "Accept": accept,
            },
        )
        try:
            with urllib.request.urlopen(request, timeout=20) as response:
                return response.read()
        except urllib.error.HTTPError as exc:
            if exc.code in {404, 429}:
                return None
            raise
        except urllib.error.URLError:
            return None

    def _events_from_json(self, payload: bytes, week: str) -> list[EconomicEventIn]:
        raw_events = json.loads(payload.decode("utf-8-sig"))
        return [
            event
            for raw_event in raw_events
            if (event := self._event_from_json(raw_event, week)) is not None
        ]

    def _event_from_json(
        self,
        data: dict,
        week: str,
    ) -> EconomicEventIn | None:
        title = str(data.get("title") or "").strip()
        currency = str(data.get("country") or data.get("currency") or "").strip()
        date_text = str(data.get("date") or "").strip()
        if not title or not currency or not date_text:
            return None

        event_time = self._parse_json_event_time(date_text)
        external_id = self._external_id(week, date_text, "", currency, title)
        impact = self._normalize_impact(str(data.get("impact") or ""))

        return EconomicEventIn(
            source="forexfactory",
            external_event_id=external_id,
            event_time=event_time,
            currency=currency,
            impact=impact,
            title=title,
            actual=self._empty_to_none(str(data.get("actual") or "").strip()),
            forecast=self._empty_to_none(str(data.get("forecast") or "").strip()),
            previous=self._empty_to_none(str(data.get("previous") or "").strip()),
            raw_payload={"provider": "forexfactory", "week": week, **data},
        )

    def _event_from_xml(
        self,
        node: ET.Element,
        week: str,
    ) -> EconomicEventIn | None:
        title = self._text(node, "title")
        currency = self._text(node, "country")
        date_text = self._text(node, "date")
        time_text = self._text(node, "time")
        if not title or not currency or not date_text:
            return None

        event_time = self._parse_event_time(date_text, time_text)
        external_id = self._external_id(week, date_text, time_text, currency, title)
        impact = self._normalize_impact(self._text(node, "impact"))

        return EconomicEventIn(
            source="forexfactory",
            external_event_id=external_id,
            event_time=event_time,
            currency=currency,
            impact=impact,
            title=title,
            actual=self._empty_to_none(self._text(node, "actual")),
            forecast=self._empty_to_none(self._text(node, "forecast")),
            previous=self._empty_to_none(self._text(node, "previous")),
            raw_payload={
                "provider": "forexfactory",
                "week": week,
                "date": date_text,
                "time": time_text,
                "impact": self._text(node, "impact"),
            },
        )

    def _parse_event_time(self, date_text: str, time_text: str) -> datetime:
        event_date = datetime.strptime(date_text.strip(), "%m-%d-%Y").date()
        normalized_time = (time_text or "").strip().lower().replace(" ", "")
        event_time = time(0, 0)

        if normalized_time and normalized_time not in {
            "allday",
            "tentative",
            "day1",
            "day2",
            "day3",
        }:
            try:
                event_time = datetime.strptime(normalized_time, "%I:%M%p").time()
            except ValueError:
                event_time = time(0, 0)

        local_dt = datetime.combine(
            event_date,
            event_time,
            tzinfo=ZoneInfo("America/New_York"),
        )
        return local_dt.astimezone(timezone.utc)

    def _parse_json_event_time(self, date_text: str) -> datetime:
        normalized = date_text.strip().replace("Z", "+00:00")
        parsed = datetime.fromisoformat(normalized)
        if parsed.tzinfo is None:
            parsed = parsed.replace(tzinfo=ZoneInfo("America/New_York"))
        return parsed.astimezone(timezone.utc)

    def _external_id(
        self,
        week: str,
        date_text: str,
        time_text: str,
        currency: str,
        title: str,
    ) -> str:
        key = "|".join([week, date_text, time_text, currency.upper(), title])
        digest = hashlib.sha1(key.encode("utf-8")).hexdigest()[:20]
        return f"ff-{digest}"

    def _normalize_impact(self, value: str) -> str:
        normalized = value.strip().lower()
        if normalized in {"high", "medium", "low", "holiday"}:
            return normalized
        if normalized == "med":
            return "medium"
        return "unknown"

    def _text(self, node: ET.Element, name: str) -> str:
        value = node.findtext(name)
        return "" if value is None else value.strip()

    def _empty_to_none(self, value: str) -> str | None:
        return value if value else None
