"""
Domain entity for BlockState.

This is the core domain model for the Block Trade feature.
It contains pure business logic and is independent of database or API concerns.
"""
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from enum import Enum
from typing import Optional, TYPE_CHECKING

if TYPE_CHECKING:
    from app.domain.state_machine.states import BlockStateEnum


class BlockType(str, Enum):
    """Type of block - determines duration and resolution rules."""
    TEMPORARY = "temporary"
    FULL_DAY = "full_day"


class BlockStatus(str, Enum):
    """Status of the block."""
    ACTIVE = "active"
    RESOLVED = "resolved"
    ARCHIVED = "archived"


# Configuration constants
TEMPORARY_BLOCK_MINUTES = 60
FULL_DAY_CODES = {
    "max_daily_loss_reached",
    "too_many_trades_today",
}
UTC_OFFSET_HOURS = 7  # Assume UTC+7 for trading day


@dataclass
class BlockState:
    """
    Domain entity representing a block state for a trading account.

    This is a clean domain model independent of database or ORM.
    """
    id: Optional[int] = None
    account_id: int = 0
    block_type: BlockType = BlockType.TEMPORARY
    status: BlockStatus = BlockStatus.ACTIVE
    triggered_by: list[str] = field(default_factory=list)
    blocked_at: datetime = field(default_factory=lambda: datetime.now(timezone.utc))
    expires_at: Optional[datetime] = None
    resolved_at: Optional[datetime] = None
    resolved_by: Optional[str] = None  # "auto" or "manual"
    payload: dict = field(default_factory=dict)

    def is_active(self) -> bool:
        """Check if block is currently active."""
        return self.status == BlockStatus.ACTIVE

    def is_resolved(self) -> bool:
        """Check if block has already been resolved."""
        return self.status == BlockStatus.RESOLVED

    def is_archived(self) -> bool:
        """Check if block has been archived."""
        return self.status == BlockStatus.ARCHIVED

    def current_state(self) -> "BlockStateEnum":
        """Return the block lifecycle state used by the state machine."""
        from app.domain.state_machine.states import BlockStateEnum

        payload_state = str(self.payload.get("state") or "").upper()
        if self.is_archived() or payload_state == BlockStateEnum.ARCHIVED.value:
            return BlockStateEnum.ARCHIVED
        if self.is_resolved() or self.resolved_at is not None:
            return BlockStateEnum.RESOLVED
        if not self.is_active():
            return BlockStateEnum.RESOLVED
        if payload_state in {
            BlockStateEnum.NORMAL.value,
            BlockStateEnum.WARNING.value,
            BlockStateEnum.TEMPORARY_BLOCK.value,
            BlockStateEnum.FULL_DAY_BLOCK.value,
            BlockStateEnum.RESOLVED.value,
        }:
            return BlockStateEnum(payload_state)
        if self.is_full_day():
            return BlockStateEnum.FULL_DAY_BLOCK
        if self.is_temporary():
            return BlockStateEnum.TEMPORARY_BLOCK
        return BlockStateEnum.NORMAL

    def is_expired(self) -> bool:
        """Check if block has expired based on expires_at."""
        if not self.is_active() or self.expires_at is None:
            return False
        return self._to_utc(datetime.now(timezone.utc)) >= self._to_utc(self.expires_at)

    def is_full_day(self) -> bool:
        """Check if this is a full-day block."""
        return self.block_type == BlockType.FULL_DAY

    def is_temporary(self) -> bool:
        """Check if this is a temporary block."""
        return self.block_type == BlockType.TEMPORARY

    def upgrade_to_full_day(
        self,
        expires_at: datetime,
        triggered_by: list[str] | None = None,
    ) -> None:
        """Upgrade a temporary block to full day."""
        if self.block_type == BlockType.TEMPORARY:
            self.block_type = BlockType.FULL_DAY
        self.expires_at = expires_at
        if triggered_by is not None:
            self.triggered_by = list(triggered_by)
        self.payload = dict(self.payload)
        self.payload["upgraded_to_full_day"] = True

    def resolve(self, manually: bool = False) -> None:
        """Resolve the block."""
        self.status = BlockStatus.RESOLVED
        self.resolved_at = datetime.now(timezone.utc)
        self.resolved_by = "manual" if manually else "auto"
        self.payload = dict(self.payload)
        self.payload["resolved_by"] = self.resolved_by

    def archive(self) -> None:
        """Archive the block after it has been resolved."""
        self.status = BlockStatus.ARCHIVED
        if self.resolved_at is None:
            self.resolved_at = datetime.now(timezone.utc)
        self.resolved_by = "archive"
        self.payload = dict(self.payload)
        self.payload["state"] = "archived"
        self.payload["archived_at"] = datetime.now(timezone.utc).isoformat()

    def can_resolve_manually(self) -> bool:
        """Full-day blocks cannot be manually resolved before expiry."""
        return self.is_active() and self.block_type != BlockType.FULL_DAY

    def remaining_seconds(self) -> int:
        """Calculate remaining seconds until block expires."""
        if not self.is_active() or self.expires_at is None:
            return 0
        delta = self._to_utc(self.expires_at) - self._to_utc(datetime.now(timezone.utc))
        return max(0, int(delta.total_seconds()))

    def to_dict(self) -> dict:
        """Convert to dictionary for serialization."""
        return {
            "id": self.id,
            "account_id": self.account_id,
            "block_type": self.block_type.value,
            "status": self.status.value,
            "state": self.current_state().value,
            "triggered_by": self.triggered_by,
            "blocked_at": self.blocked_at.isoformat() if self.blocked_at else None,
            "expires_at": self.expires_at.isoformat() if self.expires_at else None,
            "resolved_at": self.resolved_at.isoformat() if self.resolved_at else None,
            "resolved_by": self.resolved_by,
            "payload": self.payload,
        }

    @classmethod
    def from_db_model(cls, db_model: "BlockStateDb") -> "BlockState":
        """Create domain entity from database model."""
        payload = dict(db_model.payload or {})
        status = cls._coerce_status(db_model.resolved_at, payload)
        return cls(
            id=db_model.id,
            account_id=db_model.account_id,
            block_type=cls._coerce_block_type(db_model.block_type),
            status=status,
            triggered_by=db_model.triggered_by or [],
            blocked_at=cls._to_utc(db_model.blocked_at) or datetime.now(timezone.utc),
            expires_at=cls._to_utc(db_model.expires_at),
            resolved_at=cls._to_utc(db_model.resolved_at),
            resolved_by=cls._resolved_by(db_model.auto_resolved, payload, status),
            payload=payload,
        )

    @staticmethod
    def _coerce_block_type(value: object) -> BlockType:
        text = str(value or "").strip().lower()
        if text in {"full_day", "full-day", "full day"}:
            return BlockType.FULL_DAY
        return BlockType.TEMPORARY

    @classmethod
    def _coerce_status(
        cls,
        resolved_at: datetime | None,
        payload: dict,
    ) -> BlockStatus:
        payload_state = str(payload.get("state") or "").strip().lower()
        if payload_state == BlockStatus.ARCHIVED.value:
            return BlockStatus.ARCHIVED
        if resolved_at is not None:
            return BlockStatus.RESOLVED
        if payload_state == BlockStatus.RESOLVED.value:
            return BlockStatus.RESOLVED
        return BlockStatus.ACTIVE

    @classmethod
    def _resolved_by(
        cls,
        auto_resolved: bool,
        payload: dict,
        status: BlockStatus,
    ) -> str | None:
        if status == BlockStatus.ARCHIVED:
            return "archive"
        if auto_resolved:
            return "auto"
        if status == BlockStatus.RESOLVED:
            return str(payload.get("resolved_by") or "manual")
        return None

    @staticmethod
    def _to_utc(value: datetime | None) -> datetime | None:
        if value is None:
            return None
        if value.tzinfo is None:
            return value.replace(tzinfo=timezone.utc)
        return value.astimezone(timezone.utc)


def calculate_full_day_expiry() -> datetime:
    """
    Calculate expiry time for full-day block.
    Returns start of next trading day (00:00 local time = UTC+7).
    """
    now = datetime.now(timezone.utc)
    # Convert to UTC+7 "local" time for trading day boundary
    local_now = now + timedelta(hours=UTC_OFFSET_HOURS)
    next_midnight_local = datetime(
        local_now.year, local_now.month, local_now.day,
    ) + timedelta(days=1)
    # Convert back to UTC
    return next_midnight_local - timedelta(hours=UTC_OFFSET_HOURS)


def calculate_temporary_expiry() -> datetime:
    """Calculate expiry time for temporary block."""
    return datetime.now(timezone.utc) + timedelta(minutes=TEMPORARY_BLOCK_MINUTES)


# Type alias for database model to avoid circular imports
BlockStateDb = "app.models.BlockState"
