from datetime import date, datetime
from typing import Any, Literal

from pydantic import AliasChoices, BaseModel, Field, model_validator


ImpactLevel = Literal["high", "medium", "low", "holiday", "unknown"]


class EconomicEventIn(BaseModel):
    source: str = "local"
    external_event_id: str = Field(validation_alias=AliasChoices("external_event_id", "id"))
    event_time: datetime = Field(validation_alias=AliasChoices("event_time", "time"))
    currency: str
    impact: ImpactLevel = "unknown"
    title: str = Field(validation_alias=AliasChoices("title", "event", "name"))
    actual: str | None = None
    forecast: str | None = None
    previous: str | None = None
    raw_payload: dict[str, Any] | None = None

    @model_validator(mode="before")
    @classmethod
    def _normalize_strings(cls, data):
        if not isinstance(data, dict):
            return data
        normalized = dict(data)
        if "currency" in normalized and normalized["currency"] is not None:
            normalized["currency"] = str(normalized["currency"]).upper()
        if "impact" in normalized and normalized["impact"] is not None:
            impact = str(normalized["impact"]).lower()
            impact_map = {
                "med": "medium",
                "medium impact": "medium",
                "high impact": "high",
                "low impact": "low",
            }
            normalized["impact"] = impact_map.get(impact, impact)
        return normalized


class EconomicEventsIn(BaseModel):
    source: str = "local"
    events: list[EconomicEventIn]


class ForexFactoryImportRequest(BaseModel):
    weeks: list[Literal["last", "this", "next"]] = Field(
        default_factory=lambda: ["this"]
    )


class TradingViewImportRequest(BaseModel):
    start_date: date = Field(validation_alias=AliasChoices("start_date", "start"))
    end_date: date = Field(validation_alias=AliasChoices("end_date", "end"))


class EconomicEventRead(BaseModel):
    id: int
    source: str
    external_event_id: str
    event_time: datetime
    currency: str
    impact: str
    title: str
    actual: str | None = None
    forecast: str | None = None
    previous: str | None = None

    model_config = {"from_attributes": True}


class NewsIngestResult(BaseModel):
    saved: int
    updated: int
    skipped: int = 0

