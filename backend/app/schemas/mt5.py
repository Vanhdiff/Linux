from __future__ import annotations

from datetime import datetime
from typing import Any

from pydantic import BaseModel, Field


class Mt5ConnectionStatus(BaseModel):
    connected: bool
    mode: str
    message: str


class Mt5AccountInfoResponse(BaseModel):
    connected: bool
    account_info: dict[str, Any]


class Mt5ConnectRequest(BaseModel):
    path: str | None = None
    login: int | None = None
    password: str | None = None
    server: str | None = None
    timeout: int | None = None
    portable: bool | None = None


class Mt5ConnectResponse(BaseModel):
    connected: bool
    mode: str
    message: str
    account_info: dict[str, Any] | None = None
    terminal_info: dict[str, Any] | None = None


class Mt5SyncRequest(Mt5ConnectRequest):
    account_id: int | None = None
    history_days: int = Field(default=30, ge=1, le=3650)
    date_from: datetime | None = None
    date_to: datetime | None = None
    include_positions: bool = True
    include_orders: bool = True
    include_deals: bool = True


class Mt5SyncResult(BaseModel):
    account_id: int
    account_login: str
    snapshot: IngestResult
    positions: IngestResult | None = None
    orders: IngestResult | None = None
    deals: IngestResult | None = None
    date_from: datetime
    date_to: datetime


class Mt5BootstrapResult(BaseModel):
    connected: bool
    account_id: int
    account_login: str
    message: str
    sync: Mt5SyncResult
    normalized: dict[str, Any]


class Mt5AccountSnapshot(BaseModel):
    login: str
    server: str
    currency: str
    balance: float
    equity: float
    margin: float
    free_margin: float
    profit: float


class IngestResult(BaseModel):
    import_id: int
    saved: int
    skipped: int = 0


class Mt5AccountSnapshotIn(BaseModel):
    account_id: int
    captured_at: datetime | None = None
    snapshot: dict[str, Any]


class Mt5DealsIn(BaseModel):
    account_id: int
    deals: list[dict[str, Any]]


class Mt5OrdersIn(BaseModel):
    account_id: int
    orders: list[dict[str, Any]]


class Mt5PositionsIn(BaseModel):
    account_id: int
    captured_at: datetime | None = None
    positions: list[dict[str, Any]]


class Mt5CandlesIn(BaseModel):
    account_id: int
    symbol: str
    timeframe: str
    candles: list[dict[str, Any]]

