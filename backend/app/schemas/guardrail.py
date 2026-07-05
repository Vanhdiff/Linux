from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field


RuleSeverity = Literal["info", "warning", "critical"]


class GuardrailSettingsPatch(BaseModel):
    max_daily_loss: float | None = Field(default=None, ge=0)
    max_trades_per_day: int | None = Field(default=None, ge=1)
    max_risk_per_trade: float | None = Field(default=None, ge=0)
    block_high_impact_news: bool | None = None
    trading_window_start: str | None = None
    trading_window_end: str | None = None
    enabled: bool | None = None
    settings: dict | None = None


class GuardrailSettingsRead(BaseModel):
    id: int
    account_id: int
    max_daily_loss: float | None = None
    max_trades_per_day: int | None = None
    max_risk_per_trade: float | None = None
    block_high_impact_news: bool
    trading_window_start: str | None = None
    trading_window_end: str | None = None
    enabled: bool
    settings: dict | None = None

    model_config = {"from_attributes": True}


class RuleBreakRead(BaseModel):
    id: int
    account_id: int
    trade_id: int | None = None
    rule_code: str
    severity: RuleSeverity
    message: str
    detected_at: datetime
    resolved_at: datetime | None = None
    payload: dict | None = None

    model_config = {"from_attributes": True}

