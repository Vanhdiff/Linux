from datetime import date, datetime

from sqlalchemy import (
    Boolean,
    Date,
    DateTime,
    Float,
    ForeignKey,
    Integer,
    JSON,
    String,
    Text,
    UniqueConstraint,
    func,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


class TimestampMixin:
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
    )


class TradingAccount(TimestampMixin, Base):
    __tablename__ = "trading_accounts"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    name: Mapped[str] = mapped_column(String(120), default="Main account")
    broker: Mapped[str] = mapped_column(String(120), default="")
    server: Mapped[str] = mapped_column(String(120), default="")
    login: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    currency: Mapped[str] = mapped_column(String(12), default="USD")
    timezone: Mapped[str] = mapped_column(String(64), default="UTC")
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)

    snapshots: Mapped[list["AccountSnapshot"]] = relationship(
        back_populates="account",
        cascade="all, delete-orphan",
    )
    raw_imports: Mapped[list["RawMt5Import"]] = relationship(
        back_populates="account",
        cascade="all, delete-orphan",
    )
    normalized_trades: Mapped[list["NormalizedTrade"]] = relationship(
        back_populates="account",
        cascade="all, delete-orphan",
    )
    guardrail_settings: Mapped[list["GuardrailSetting"]] = relationship(
        back_populates="account",
        cascade="all, delete-orphan",
    )


class AccountSnapshot(TimestampMixin, Base):
    __tablename__ = "account_snapshots"

    id: Mapped[int] = mapped_column(primary_key=True)
    account_id: Mapped[int] = mapped_column(
        ForeignKey("trading_accounts.id"),
        index=True,
    )
    captured_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
    balance: Mapped[float] = mapped_column(Float, default=0)
    equity: Mapped[float] = mapped_column(Float, default=0)
    margin: Mapped[float] = mapped_column(Float, default=0)
    free_margin: Mapped[float] = mapped_column(Float, default=0)
    margin_level: Mapped[float | None] = mapped_column(Float)
    profit: Mapped[float] = mapped_column(Float, default=0)
    raw_payload: Mapped[dict | None] = mapped_column(JSON)

    account: Mapped[TradingAccount] = relationship(back_populates="snapshots")


class RawMt5Import(TimestampMixin, Base):
    __tablename__ = "raw_mt5_imports"

    id: Mapped[int] = mapped_column(primary_key=True)
    account_id: Mapped[int] = mapped_column(
        ForeignKey("trading_accounts.id"),
        index=True,
    )
    source: Mapped[str] = mapped_column(String(40), default="mt5")
    import_type: Mapped[str] = mapped_column(String(40), index=True)
    imported_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        index=True,
    )
    checksum: Mapped[str | None] = mapped_column(String(128), index=True)
    payload: Mapped[dict] = mapped_column(JSON)

    account: Mapped[TradingAccount] = relationship(back_populates="raw_imports")
    deals: Mapped[list["RawDeal"]] = relationship(
        back_populates="raw_import",
        cascade="all, delete-orphan",
    )
    orders: Mapped[list["RawOrder"]] = relationship(
        back_populates="raw_import",
        cascade="all, delete-orphan",
    )
    positions: Mapped[list["RawPosition"]] = relationship(
        back_populates="raw_import",
        cascade="all, delete-orphan",
    )
    candles: Mapped[list["RawCandle"]] = relationship(
        back_populates="raw_import",
        cascade="all, delete-orphan",
    )


class RawDeal(TimestampMixin, Base):
    __tablename__ = "raw_deals"
    __table_args__ = (
        UniqueConstraint("account_id", "external_deal_id", name="uq_raw_deal"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    account_id: Mapped[int] = mapped_column(
        ForeignKey("trading_accounts.id"),
        index=True,
    )
    raw_import_id: Mapped[int | None] = mapped_column(ForeignKey("raw_mt5_imports.id"))
    external_deal_id: Mapped[str] = mapped_column(String(80), index=True)
    external_order_id: Mapped[str | None] = mapped_column(String(80), index=True)
    symbol: Mapped[str] = mapped_column(String(32), index=True)
    direction: Mapped[str | None] = mapped_column(String(12))
    entry_type: Mapped[str | None] = mapped_column(String(40))
    volume: Mapped[float] = mapped_column(Float, default=0)
    price: Mapped[float | None] = mapped_column(Float)
    profit: Mapped[float] = mapped_column(Float, default=0)
    commission: Mapped[float] = mapped_column(Float, default=0)
    swap: Mapped[float] = mapped_column(Float, default=0)
    deal_time: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
    comment: Mapped[str] = mapped_column(Text, default="")
    raw_payload: Mapped[dict] = mapped_column(JSON)

    raw_import: Mapped[RawMt5Import | None] = relationship(back_populates="deals")


class RawOrder(TimestampMixin, Base):
    __tablename__ = "raw_orders"
    __table_args__ = (
        UniqueConstraint("account_id", "external_order_id", name="uq_raw_order"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    account_id: Mapped[int] = mapped_column(
        ForeignKey("trading_accounts.id"),
        index=True,
    )
    raw_import_id: Mapped[int | None] = mapped_column(ForeignKey("raw_mt5_imports.id"))
    external_order_id: Mapped[str] = mapped_column(String(80), index=True)
    symbol: Mapped[str] = mapped_column(String(32), index=True)
    order_type: Mapped[str] = mapped_column(String(40), default="")
    volume_initial: Mapped[float] = mapped_column(Float, default=0)
    volume_current: Mapped[float] = mapped_column(Float, default=0)
    price_open: Mapped[float | None] = mapped_column(Float)
    stop_loss: Mapped[float | None] = mapped_column(Float)
    take_profit: Mapped[float | None] = mapped_column(Float)
    order_time: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    state: Mapped[str] = mapped_column(String(40), default="")
    comment: Mapped[str] = mapped_column(Text, default="")
    raw_payload: Mapped[dict] = mapped_column(JSON)

    raw_import: Mapped[RawMt5Import | None] = relationship(back_populates="orders")


class RawPosition(TimestampMixin, Base):
    __tablename__ = "raw_positions"

    id: Mapped[int] = mapped_column(primary_key=True)
    account_id: Mapped[int] = mapped_column(
        ForeignKey("trading_accounts.id"),
        index=True,
    )
    raw_import_id: Mapped[int | None] = mapped_column(ForeignKey("raw_mt5_imports.id"))
    external_position_id: Mapped[str] = mapped_column(String(80), index=True)
    symbol: Mapped[str] = mapped_column(String(32), index=True)
    direction: Mapped[str] = mapped_column(String(12))
    volume: Mapped[float] = mapped_column(Float, default=0)
    open_price: Mapped[float | None] = mapped_column(Float)
    current_price: Mapped[float | None] = mapped_column(Float)
    stop_loss: Mapped[float | None] = mapped_column(Float)
    take_profit: Mapped[float | None] = mapped_column(Float)
    profit: Mapped[float] = mapped_column(Float, default=0)
    swap: Mapped[float] = mapped_column(Float, default=0)
    commission: Mapped[float] = mapped_column(Float, default=0)
    opened_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    captured_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
    raw_payload: Mapped[dict] = mapped_column(JSON)

    raw_import: Mapped[RawMt5Import | None] = relationship(back_populates="positions")


class RawCandle(TimestampMixin, Base):
    __tablename__ = "raw_candles"
    __table_args__ = (
        UniqueConstraint(
            "account_id",
            "symbol",
            "timeframe",
            "candle_time",
            name="uq_raw_candle",
        ),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    account_id: Mapped[int] = mapped_column(
        ForeignKey("trading_accounts.id"),
        index=True,
    )
    raw_import_id: Mapped[int | None] = mapped_column(ForeignKey("raw_mt5_imports.id"))
    symbol: Mapped[str] = mapped_column(String(32), index=True)
    timeframe: Mapped[str] = mapped_column(String(12), index=True)
    candle_time: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
    open: Mapped[float] = mapped_column(Float)
    high: Mapped[float] = mapped_column(Float)
    low: Mapped[float] = mapped_column(Float)
    close: Mapped[float] = mapped_column(Float)
    tick_volume: Mapped[int] = mapped_column(Integer, default=0)
    raw_payload: Mapped[dict] = mapped_column(JSON)

    raw_import: Mapped[RawMt5Import | None] = relationship(back_populates="candles")


class NormalizedTrade(TimestampMixin, Base):
    __tablename__ = "normalized_trades"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    account_id: Mapped[int] = mapped_column(
        ForeignKey("trading_accounts.id"),
        index=True,
    )
    symbol: Mapped[str] = mapped_column(String(32), index=True)
    direction: Mapped[str] = mapped_column(String(8))
    side: Mapped[str | None] = mapped_column(String(8), index=True)
    volume: Mapped[float] = mapped_column(Float)
    opened_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
    open_time: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), index=True)
    closed_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        index=True,
    )
    close_time: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), index=True)
    entry_price: Mapped[float | None] = mapped_column(Float)
    open_price: Mapped[float | None] = mapped_column(Float)
    exit_price: Mapped[float | None] = mapped_column(Float)
    close_price: Mapped[float | None] = mapped_column(Float)
    stop_loss: Mapped[float | None] = mapped_column(Float)
    take_profit: Mapped[float | None] = mapped_column(Float)
    commission: Mapped[float] = mapped_column(Float, default=0)
    swap: Mapped[float] = mapped_column(Float, default=0)
    gross_pnl: Mapped[float] = mapped_column(Float, default=0)
    profit: Mapped[float | None] = mapped_column(Float)
    net_pnl: Mapped[float] = mapped_column(Float, default=0)
    net_profit: Mapped[float | None] = mapped_column(Float)
    duration_seconds: Mapped[int | None] = mapped_column(Integer)
    entry_reason: Mapped[str | None] = mapped_column(String(255))
    exit_reason: Mapped[str | None] = mapped_column(String(255))
    risk_amount: Mapped[float | None] = mapped_column(Float)
    r_multiple: Mapped[float | None] = mapped_column(Float)
    setup_tag: Mapped[str | None] = mapped_column(String(80), index=True)
    session: Mapped[str | None] = mapped_column(String(40), index=True)
    status: Mapped[str] = mapped_column(String(20), default="open", index=True)
    source_deal_ids: Mapped[list | None] = mapped_column(JSON)

    account: Mapped[TradingAccount] = relationship(back_populates="normalized_trades")
    journal: Mapped["TradeJournal | None"] = relationship(
        back_populates="trade",
        cascade="all, delete-orphan",
    )
    rule_breaks: Mapped[list["RuleBreak"]] = relationship(
        back_populates="trade",
        cascade="all, delete-orphan",
    )


class TradeJournal(TimestampMixin, Base):
    __tablename__ = "trade_journals"

    id: Mapped[int] = mapped_column(primary_key=True)
    trade_id: Mapped[int] = mapped_column(
        ForeignKey("normalized_trades.id"),
        unique=True,
        index=True,
    )
    setup: Mapped[str | None] = mapped_column(String(120), index=True)
    mistakes: Mapped[list | None] = mapped_column(JSON)
    emotion_before: Mapped[str | None] = mapped_column(String(80))
    emotion_after: Mapped[str | None] = mapped_column(String(80))
    followed_plan: Mapped[bool | None] = mapped_column(Boolean)
    notes: Mapped[str] = mapped_column(Text, default="")
    screenshot_refs: Mapped[list | None] = mapped_column(JSON)
    review_status: Mapped[str] = mapped_column(String(40), default="pending")
    reviewed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    trade: Mapped[NormalizedTrade] = relationship(back_populates="journal")


class NotebookNote(TimestampMixin, Base):
    __tablename__ = "notebook_notes"

    id: Mapped[int] = mapped_column(primary_key=True)
    account_id: Mapped[int | None] = mapped_column(
        ForeignKey("trading_accounts.id"),
        index=True,
    )
    title: Mapped[str] = mapped_column(String(180), index=True)
    template: Mapped[str] = mapped_column(String(120), default="Blank Note")
    plan: Mapped[str] = mapped_column(Text, default="")
    note: Mapped[str] = mapped_column(Text, default="")
    pinned: Mapped[bool] = mapped_column(Boolean, default=False, index=True)
    saved: Mapped[bool] = mapped_column(Boolean, default=True)
    icon_key: Mapped[str] = mapped_column(String(80), default="edit_note")
    accent_key: Mapped[str] = mapped_column(String(80), default="primary")
    tasks: Mapped[list | None] = mapped_column(JSON)

    account: Mapped[TradingAccount | None] = relationship()


class DailyAnalytics(TimestampMixin, Base):
    __tablename__ = "daily_analytics"
    __table_args__ = (
        UniqueConstraint("account_id", "trade_date", name="uq_daily_analytics"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    account_id: Mapped[int] = mapped_column(
        ForeignKey("trading_accounts.id"),
        index=True,
    )
    trade_date: Mapped[date] = mapped_column(Date, index=True)
    net_pnl: Mapped[float] = mapped_column(Float, default=0)
    gross_pnl: Mapped[float] = mapped_column(Float, default=0)
    trade_count: Mapped[int] = mapped_column(Integer, default=0)
    win_count: Mapped[int] = mapped_column(Integer, default=0)
    loss_count: Mapped[int] = mapped_column(Integer, default=0)
    win_rate: Mapped[float] = mapped_column(Float, default=0)
    profit_factor: Mapped[float] = mapped_column(Float, default=0)
    max_drawdown: Mapped[float] = mapped_column(Float, default=0)
    avg_r: Mapped[float] = mapped_column(Float, default=0)
    risk_total: Mapped[float] = mapped_column(Float, default=0)
    metrics: Mapped[dict | None] = mapped_column(JSON)


class GuardrailSetting(TimestampMixin, Base):
    __tablename__ = "guardrail_settings"

    id: Mapped[int] = mapped_column(primary_key=True)
    account_id: Mapped[int] = mapped_column(
        ForeignKey("trading_accounts.id"),
        index=True,
    )
    max_daily_loss: Mapped[float | None] = mapped_column(Float)
    max_trades_per_day: Mapped[int | None] = mapped_column(Integer)
    max_risk_per_trade: Mapped[float | None] = mapped_column(Float)
    block_high_impact_news: Mapped[bool] = mapped_column(Boolean, default=True)
    trading_window_start: Mapped[str | None] = mapped_column(String(16))
    trading_window_end: Mapped[str | None] = mapped_column(String(16))
    enabled: Mapped[bool] = mapped_column(Boolean, default=True)
    settings: Mapped[dict | None] = mapped_column(JSON)

    account: Mapped[TradingAccount] = relationship(back_populates="guardrail_settings")


class License(TimestampMixin, Base):
    __tablename__ = "licenses"

    id: Mapped[int] = mapped_column(primary_key=True)
    license_key: Mapped[str] = mapped_column(String(128), unique=True, index=True)
    provider: Mapped[str] = mapped_column(String(32), default="offline")
    owner_email: Mapped[str | None] = mapped_column(String(255), index=True)
    device_id: Mapped[str | None] = mapped_column(String(255), index=True)
    is_active: Mapped[bool] = mapped_column(Boolean, default=False)
    activated_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    expires_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    last_validated_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class AiChatUsage(TimestampMixin, Base):
    __tablename__ = "ai_chat_usage"
    __table_args__ = (
        UniqueConstraint("license_key", "usage_date", name="uq_ai_chat_usage_day"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    license_key: Mapped[str] = mapped_column(String(128), index=True)
    usage_date: Mapped[date] = mapped_column(Date, index=True)
    question_count: Mapped[int] = mapped_column(Integer, default=0)


class RuleBreak(TimestampMixin, Base):
    __tablename__ = "rule_breaks"

    id: Mapped[int] = mapped_column(primary_key=True)
    account_id: Mapped[int] = mapped_column(
        ForeignKey("trading_accounts.id"),
        index=True,
    )
    trade_id: Mapped[int | None] = mapped_column(ForeignKey("normalized_trades.id"))
    rule_code: Mapped[str] = mapped_column(String(80), index=True)
    severity: Mapped[str] = mapped_column(String(20), default="warning")
    message: Mapped[str] = mapped_column(Text, default="")
    detected_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        index=True,
    )
    resolved_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    payload: Mapped[dict | None] = mapped_column(JSON)

    trade: Mapped[NormalizedTrade | None] = relationship(back_populates="rule_breaks")


class EconomicEvent(TimestampMixin, Base):
    __tablename__ = "economic_events"
    __table_args__ = (
        UniqueConstraint("source", "external_event_id", name="uq_economic_event"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    source: Mapped[str] = mapped_column(String(40), index=True)
    external_event_id: Mapped[str] = mapped_column(String(120), index=True)
    event_time: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
    currency: Mapped[str] = mapped_column(String(12), index=True)
    impact: Mapped[str] = mapped_column(String(20), index=True)
    title: Mapped[str] = mapped_column(String(255))
    actual: Mapped[str | None] = mapped_column(String(80))
    forecast: Mapped[str | None] = mapped_column(String(80))
    previous: Mapped[str | None] = mapped_column(String(80))
    raw_payload: Mapped[dict | None] = mapped_column(JSON)

