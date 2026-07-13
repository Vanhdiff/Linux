from datetime import datetime
from typing import Literal

from pydantic import AliasChoices, BaseModel, ConfigDict, Field, model_validator


TradeDirection = Literal["buy", "sell"]
TradeStatus = Literal["open", "closed", "breakeven"]
ReviewStatus = Literal["pending", "reviewed", "needs_review"]


class TradeRead(BaseModel):
    id: int
    account_id: int
    symbol: str
    direction: TradeDirection
    volume: float
    opened_at: datetime
    closed_at: datetime | None = None
    entry_price: float | None = None
    exit_price: float | None = None
    stop_loss: float | None = None
    take_profit: float | None = None
    commission: float
    swap: float
    gross_pnl: float
    net_pnl: float
    session: str | None = None
    risk_amount: float | None = None
    r_multiple: float | None = None
    status: TradeStatus

    model_config = {"from_attributes": True}


class NormalizeResult(BaseModel):
    account_id: int
    created: int
    updated: int
    skipped: int


class TradeJournalWrite(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    setup: str | None = Field(default=None, max_length=120)
    mistakes: list[str] | None = Field(
        default=None,
        validation_alias=AliasChoices("mistakes", "mistake"),
    )
    emotion_before: str | None = Field(default=None, max_length=80)
    emotion_after: str | None = Field(default=None, max_length=80)
    followed_plan: bool | None = None
    notes: str = Field(default="", validation_alias=AliasChoices("notes", "note"))
    screenshot_refs: list[str] | None = Field(
        default=None,
        validation_alias=AliasChoices("screenshot_refs", "screenshot", "screenshots"),
    )
    review_status: ReviewStatus = "pending"
    reviewed_at: datetime | None = None

    @model_validator(mode="before")
    @classmethod
    def _normalize_single_values(cls, data):
        if not isinstance(data, dict):
            return data
        normalized = dict(data)
        for key in ("mistake", "mistakes"):
            value = normalized.get(key)
            if isinstance(value, str):
                normalized[key] = [value]
        for key in ("screenshot", "screenshots", "screenshot_refs"):
            value = normalized.get(key)
            if isinstance(value, str):
                normalized[key] = [value]
        return normalized


class TradeJournalRead(TradeJournalWrite):
    id: int
    trade_id: int
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True, populate_by_name=True)


class TradeJournalPatch(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    setup: str | None = Field(default=None, max_length=120)
    mistakes: list[str] | None = Field(
        default=None,
        validation_alias=AliasChoices("mistakes", "mistake"),
    )
    emotion_before: str | None = Field(default=None, max_length=80)
    emotion_after: str | None = Field(default=None, max_length=80)
    followed_plan: bool | None = None
    notes: str | None = Field(default=None, validation_alias=AliasChoices("notes", "note"))
    screenshot_refs: list[str] | None = Field(
        default=None,
        validation_alias=AliasChoices("screenshot_refs", "screenshot", "screenshots"),
    )
    review_status: ReviewStatus | None = None
    reviewed_at: datetime | None = None

    @model_validator(mode="before")
    @classmethod
    def _normalize_single_values(cls, data):
        if not isinstance(data, dict):
            return data
        normalized = dict(data)
        for key in ("mistake", "mistakes"):
            value = normalized.get(key)
            if isinstance(value, str):
                normalized[key] = [value]
        for key in ("screenshot", "screenshots", "screenshot_refs"):
            value = normalized.get(key)
            if isinstance(value, str):
                normalized[key] = [value]
        return normalized

