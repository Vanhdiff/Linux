"""
Block Repository - Database access layer for BlockState.

This repository encapsulates all database operations for block states,
providing a clean interface between the domain layer and the database.
"""
import logging
from datetime import datetime, timezone
from typing import Optional

from sqlalchemy.orm import Session

from app.models import BlockState as BlockStateModel
from app.domain.entities.block_state import (
    BlockState as DomainBlockState,
    BlockStatus,
    BlockType,
)

logger = logging.getLogger(__name__)


class BlockRepository:
    """
    Repository for BlockState domain entity.

    Handles all database operations and converts between
    domain entities and database models.
    """

    def __init__(self, db: Session):
        """Initialize repository with database session."""
        self._db = db

    def get_active_block(self, account_id: int) -> Optional[DomainBlockState]:
        """
        Get the currently active block for an account.

        Args:
            account_id: Trading account ID

        Returns:
            Domain BlockState if active block exists, None otherwise
        """
        now = datetime.now(timezone.utc)

        db_block = (
            self._db.query(BlockStateModel)
            .filter(
                BlockStateModel.account_id == account_id,
                BlockStateModel.resolved_at.is_(None),
            )
            .order_by(BlockStateModel.blocked_at.desc(), BlockStateModel.id.desc())
            .first()
        )

        if db_block is None:
            return None

        # Check if expired - if so, auto-resolve
        expires_at = self._to_utc(db_block.expires_at)
        if expires_at is not None and now >= expires_at:
            self._resolve_block(db_block, auto_resolved=True)
            return None

        return self._to_domain(db_block)

    def get_active_blocks(self) -> list[DomainBlockState]:
        """
        Get all active blocks across all accounts.

        Returns:
            List of domain BlockState entities
        """
        now = datetime.now(timezone.utc)

        blocks = (
            self._db.query(BlockStateModel)
            .filter(
                BlockStateModel.resolved_at.is_(None),
                BlockStateModel.expires_at.is_(None) | (BlockStateModel.expires_at > now),
            )
            .all()
        )

        return [self._to_domain(b) for b in blocks]

    def get_by_id(self, block_id: int) -> Optional[DomainBlockState]:
        """
        Get a block by its ID.

        Args:
            block_id: Block ID

        Returns:
            Domain BlockState if found, None otherwise
        """
        db_block = self._db.get(BlockStateModel, block_id)
        if db_block is None:
            return None
        return self._to_domain(db_block)

    def save(self, block: DomainBlockState) -> DomainBlockState:
        """
        Save a block (create or update).

        Args:
            block: Domain BlockState to save

        Returns:
            Saved domain BlockState with updated fields
        """
        if block.id is None:
            # Create new
            db_block = self._to_db_model(block)
            self._db.add(db_block)
            self._db.commit()
            self._db.refresh(db_block)
            return self._to_domain(db_block)
        else:
            # Update existing
            db_block = self._db.get(BlockStateModel, block.id)
            if db_block:
                db_block.account_id = block.account_id
                db_block.block_type = self._coerce_block_type_value(block.block_type)
                db_block.triggered_by = list(block.triggered_by)
                db_block.blocked_at = block.blocked_at
                db_block.expires_at = block.expires_at
                db_block.resolved_at = block.resolved_at
                db_block.auto_resolved = block.resolved_by == "auto" if block.resolved_by else False
                db_block.payload = dict(block.payload)
                self._db.commit()
                self._db.refresh(db_block)
                return self._to_domain(db_block)

        # If not found, create new
        db_block = self._to_db_model(block)
        self._db.add(db_block)
        self._db.commit()
        self._db.refresh(db_block)
        return self._to_domain(db_block)

    def resolve_block(self, account_id: int, manually: bool = False) -> bool:
        """
        Resolve the active block for an account.

        Args:
            account_id: Trading account ID
            manually: True if manually resolved, False if auto-resolved

        Returns:
            True if block was resolved, False if no active block
        """
        block = self.get_active_block(account_id)
        if block is None:
            return False

        db_block = self._db.get(BlockStateModel, block.id)
        if db_block:
            self._resolve_block(db_block, auto_resolved=not manually)
            return True

        return False

    def get_block_history(
        self,
        account_id: int,
        limit: int = 20
    ) -> list[DomainBlockState]:
        """
        Get block history for an account.

        Args:
            account_id: Trading account ID
            limit: Maximum number of records to return

        Returns:
            List of domain BlockState entities (most recent first)
        """
        blocks = (
            self._db.query(BlockStateModel)
            .filter(BlockStateModel.account_id == account_id)
            .order_by(BlockStateModel.blocked_at.desc())
            .limit(limit)
            .all()
        )

        return [self._to_domain(b) for b in blocks]

    def restore_active_blocks(self, account_id: int | None = None) -> list[DomainBlockState]:
        """
        Restore all active blocks after application restart.

        This is called on startup to restore block state.
        Blocks that have expired since restart will be auto-resolved.

        Returns:
            List of still-active domain BlockState entities
        """
        now = datetime.now(timezone.utc)

        query = self._db.query(BlockStateModel).filter(BlockStateModel.resolved_at.is_(None))
        if account_id is not None:
            query = query.filter(BlockStateModel.account_id == account_id)

        active_blocks = query.filter(
            BlockStateModel.expires_at.is_(None) | (BlockStateModel.expires_at > now)
        ).all()

        logger.info(f"Restored {len(active_blocks)} active blocks after restart")

        return [self._to_domain(b) for b in active_blocks]

    def cleanup_expired_blocks(self, account_id: int | None = None) -> list[DomainBlockState]:
        """
        Resolve all expired blocks for an account or the full database.

        Returns the blocks that were resolved during cleanup.
        """
        expired_blocks = self.get_expired_blocks(account_id=account_id)
        cleaned: list[DomainBlockState] = []
        for block in expired_blocks:
            db_block = self._db.get(BlockStateModel, block.id)
            if db_block is None:
                continue
            self._resolve_block(db_block, auto_resolved=True)
            cleaned.append(self._to_domain(db_block))
        if cleaned:
            logger.info("Resolved %s expired blocks during cleanup", len(cleaned))
        return cleaned

    def get_expired_blocks(self, account_id: int | None = None) -> list[DomainBlockState]:
        """
        Get all blocks that have expired but haven't been resolved.

        Args:
            account_id: Optional account filter.
        """
        now = datetime.now(timezone.utc)
        query = self._db.query(BlockStateModel).filter(
            BlockStateModel.resolved_at.is_(None),
            BlockStateModel.expires_at.isnot(None),
            BlockStateModel.expires_at <= now,
        )
        if account_id is not None:
            query = query.filter(BlockStateModel.account_id == account_id)
        blocks = query.all()
        return [self._to_domain(b) for b in blocks]

    def count_active_blocks(self) -> int:
        """
        Count the number of active blocks.

        Returns:
            Number of active blocks
        """
        now = datetime.now(timezone.utc)

        return (
            self._db.query(BlockStateModel)
            .filter(
                BlockStateModel.resolved_at.is_(None),
                BlockStateModel.expires_at.is_(None) | (BlockStateModel.expires_at > now),
            )
            .count()
        )

    # ------------------------------------------------------------------
    # Private helpers
    # ------------------------------------------------------------------

    def _to_domain(self, db_model: BlockStateModel) -> DomainBlockState:
        """Convert database model to domain entity."""
        return DomainBlockState(
            id=db_model.id,
            account_id=db_model.account_id,
            block_type=self._coerce_block_type(db_model.block_type),
            status=self._coerce_status(db_model.resolved_at, db_model.payload, db_model.auto_resolved),
            triggered_by=list(db_model.triggered_by or []),
            blocked_at=self._to_utc(db_model.blocked_at) or datetime.now(timezone.utc),
            expires_at=self._to_utc(db_model.expires_at),
            resolved_at=self._to_utc(db_model.resolved_at),
            resolved_by=self._resolved_by(db_model.resolved_at, db_model.payload, db_model.auto_resolved),
            payload=dict(db_model.payload or {}),
        )

    def _to_db_model(self, domain: DomainBlockState) -> BlockStateModel:
        """Convert domain entity to database model."""
        return BlockStateModel(
            id=domain.id,
            account_id=domain.account_id,
            block_type=self._coerce_block_type_value(domain.block_type),
            triggered_by=list(domain.triggered_by),
            blocked_at=domain.blocked_at,
            expires_at=domain.expires_at,
            resolved_at=domain.resolved_at,
            auto_resolved=domain.resolved_by == "auto" if domain.resolved_by else False,
            payload=dict(domain.payload),
        )

    def _resolve_block(self, db_model: BlockStateModel, auto_resolved: bool = True) -> None:
        """Resolve a database model block."""
        db_model.resolved_at = datetime.now(timezone.utc)
        db_model.auto_resolved = auto_resolved
        if auto_resolved:
            payload = dict(db_model.payload or {})
            payload.setdefault("resolved_by", "auto")
            db_model.payload = payload
        self._db.commit()
        logger.info(
            f"Resolved block {db_model.id} for account {db_model.account_id} "
            f"(auto_resolved={auto_resolved})"
        )

    def _coerce_block_type(self, value: object) -> BlockType:
        raw_value = value.value if hasattr(value, "value") else value
        text = str(raw_value or "").strip().lower()
        if text in {"full_day", "full-day", "full day"}:
            return BlockType.FULL_DAY
        return BlockType.TEMPORARY

    def _coerce_block_type_value(self, value: object) -> str:
        raw_value = value.value if hasattr(value, "value") else value
        text = str(raw_value or "").strip().lower()
        if text in {"full_day", "full-day", "full day"}:
            return "full_day"
        return "temporary"

    def _coerce_status(
        self,
        resolved_at: datetime | None,
        payload: dict | None,
        auto_resolved: bool,
    ) -> BlockStatus:
        payload_state = str((payload or {}).get("state") or "").strip().lower()
        if payload_state == BlockStatus.ARCHIVED.value:
            return BlockStatus.ARCHIVED
        if resolved_at is not None:
            return BlockStatus.RESOLVED
        if auto_resolved:
            return BlockStatus.RESOLVED
        return BlockStatus.ACTIVE

    def _resolved_by(
        self,
        resolved_at: datetime | None,
        payload: dict | None,
        auto_resolved: bool,
    ) -> str | None:
        payload = payload or {}
        if str(payload.get("state") or "").strip().lower() == "archived":
            return "archive"
        if auto_resolved:
            return "auto"
        if resolved_at is not None:
            return str(payload.get("resolved_by") or "manual")
        return None

    def _to_utc(self, value: datetime | None) -> datetime | None:
        if value is None:
            return None
        if value.tzinfo is None:
            return value.replace(tzinfo=timezone.utc)
        return value.astimezone(timezone.utc)
