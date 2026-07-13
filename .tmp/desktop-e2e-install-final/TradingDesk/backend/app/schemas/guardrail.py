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


class PreTradeValidationRequest(BaseModel):
    account_id: int = Field(ge=1)
    symbol: str | None = None
    direction: Literal["buy", "sell"] | None = None
    volume: float | None = Field(default=None, gt=0)
    requested_at: datetime | None = None
    source: str = "mt5_ea"
    client_order_id: str | None = None
    metadata: dict | None = None


class PreTradeValidationResponse(BaseModel):
    account_id: int
    allowed: bool
    blocked: bool
    decision: Literal["ALLOW", "DENY"]
    reason: str | None = None
    trade_blocking_enabled: bool
    reasons: list[dict]
    block_state: dict
    checked_at: datetime
    request: dict


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

