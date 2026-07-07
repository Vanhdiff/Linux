from datetime import date, datetime, timedelta, timezone
from typing import Any

from fastapi import HTTPException
from sqlalchemy.orm import Session

from app.models import BlockState, TradingAccount

FULL_DAY_CODES = {
    "max_daily_loss_reached",
    "too_many_trades_today",
}

TEMPORARY_CODES = {
    "high_impact_news_window",
    "revenge_trading_pattern",
    "consecutive_losses_pause_active",
    "cooling_off_active",
    "live_averaging_loss",
    "live_martingale",
    "risk_too_high",
}

# How long a temporary block lasts (default in minutes)
TEMPORARY_BLOCK_MINUTES = 60


class BlockStateService:
    def __init__(self, db: Session) -> None:
        self._db = db

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def get_active_block(self, account_id: int) -> BlockState | None:
        """Return the currently active (non-resolved) block for this account, or None."""
        now = datetime.now(timezone.utc)
        block = (
            self._db.query(BlockState)
            .filter(
                BlockState.account_id == account_id,
                BlockState.resolved_at.is_(None),
            )
            .order_by(BlockState.blocked_at.desc(), BlockState.id.desc())
            .first()
        )
        if block is None:
            return None

        # If expires_at is in the past, auto-resolve it
        if block.expires_at is not None and now >= block.expires_at:
            self._resolve_block(block, auto_resolved=True)
            return None

        return block

    def apply_block(
        self,
        account_id: int,
        triggered_checks: list[dict],
    ) -> BlockState | None:
        """Given triggered check results, decide block type and persist it.

        Returns the newly created BlockState, or None if no block should be applied.
        """
        self._ensure_account(account_id)
        triggered_codes = {c["rule_code"] for c in triggered_checks}

        if not triggered_codes:
            return None

        # Determine block type: full-day codes take precedence
        has_full_day = bool(triggered_codes & FULL_DAY_CODES)
        block_type = "full_day" if has_full_day else "temporary"

        # Only create a new block if there isn't already an active one
        existing = self.get_active_block(account_id)
        if existing is not None:
            # If existing is temporary but a full-day code just fired, upgrade it
            if existing.block_type == "temporary" and has_full_day:
                existing.block_type = "full_day"
                existing.expires_at = self._full_day_expiry(account_id)
                existing.triggered_by = list(triggered_codes)
                existing.payload = {
                    "upgraded_at": datetime.now(timezone.utc).isoformat(),
                    "checks": triggered_checks,
                }
                self._db.commit()
                self._db.refresh(existing)
                return existing
            # Otherwise the existing block is still in effect
            return existing

        now = datetime.now(timezone.utc)

        # Compute expiry
        if block_type == "full_day":
            expires_at = self._full_day_expiry(account_id)
        else:
            expires_at = now + timedelta(minutes=TEMPORARY_BLOCK_MINUTES)

        block = BlockState(
            account_id=account_id,
            block_type=block_type,
            triggered_by=list(triggered_codes),
            blocked_at=now,
            expires_at=expires_at,
            resolved_at=None,
            auto_resolved=False,
            payload={"checks": triggered_checks},
        )
        self._db.add(block)
        self._db.commit()
        self._db.refresh(block)
        return block

    def resolve_block(self, account_id: int) -> dict[str, Any]:
        """Manually resolve the active block for this account."""
        block = self.get_active_block(account_id)
        if block is None:
            return {"resolved": False, "reason": "no_active_block"}
        self._resolve_block(block, auto_resolved=False)
        return {
            "resolved": True,
            "block_type": block.block_type,
            "blocked_at": block.blocked_at.isoformat(),
        }

    def resolve_expired_blocks(self, account_id: int) -> list[dict[str, Any]]:
        """Check and auto-resolve all expired blocks for this account."""
        now = datetime.now(timezone.utc)
        expired = (
            self._db.query(BlockState)
            .filter(
                BlockState.account_id == account_id,
                BlockState.resolved_at.is_(None),
                BlockState.expires_at.isnot(None),
                BlockState.expires_at <= now,
            )
            .all()
        )
        results = []
        for block in expired:
            self._resolve_block(block, auto_resolved=True)
            results.append({
                "id": block.id,
                "block_type": block.block_type,
                "resolved_at": block.resolved_at.isoformat(),
            })
        return results

    def block_history(
        self,
        account_id: int,
        limit: int = 20,
    ) -> list[dict[str, Any]]:
        """Return a history of block states, most recent first."""
        blocks = (
            self._db.query(BlockState)
            .filter(BlockState.account_id == account_id)
            .order_by(BlockState.blocked_at.desc(), BlockState.id.desc())
            .limit(limit)
            .all()
        )
        return [self._block_payload(b) for b in blocks]

    def block_status(self, account_id: int) -> dict[str, Any]:
        """Return a lightweight block status payload for the frontend."""
        active = self.get_active_block(account_id)
        if active is None:
            return {
                "account_id": account_id,
                "active": False,
                "block_type": None,
                "blocked_at": None,
                "expires_at": None,
                "remaining_seconds": 0,
                "triggered_by": [],
                "full_day_block": False,
            }

        remaining = self._remaining_seconds(active)
        return {
            "account_id": account_id,
            "active": True,
            "block_type": active.block_type,
            "blocked_at": active.blocked_at.isoformat(),
            "expires_at": active.expires_at.isoformat() if active.expires_at else None,
            "remaining_seconds": remaining,
            "triggered_by": active.triggered_by or [],
            "full_day_block": active.block_type == "full_day",
        }

    # ------------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------------

    def _resolve_block(self, block: BlockState, auto_resolved: bool) -> None:
        block.resolved_at = datetime.now(timezone.utc)
        block.auto_resolved = auto_resolved
        self._db.commit()
        self._db.refresh(block)

    def _full_day_expiry(self, account_id: int) -> datetime:
        """Expires at the start of the next trading day (00:00 UTC+7 next day)."""
        now = datetime.now(timezone.utc)
        # Convert to UTC+7 "local" time for trading day boundary
        local_now = now + timedelta(hours=7)
        next_midnight_local = datetime(
            local_now.year, local_now.month, local_now.day,
        ) + timedelta(days=1)
        # Convert back to UTC
        return next_midnight_local - timedelta(hours=7)

    def _remaining_seconds(self, block: BlockState) -> int:
        if block.expires_at is None:
            return 0
        delta = block.expires_at - datetime.now(timezone.utc)
        return max(0, int(delta.total_seconds()))

    def _block_payload(self, block: BlockState) -> dict[str, Any]:
        return {
            "id": block.id,
            "account_id": block.account_id,
            "block_type": block.block_type,
            "triggered_by": block.triggered_by or [],
            "blocked_at": block.blocked_at.isoformat(),
            "expires_at": block.expires_at.isoformat() if block.expires_at else None,
            "resolved_at": block.resolved_at.isoformat() if block.resolved_at else None,
            "auto_resolved": block.auto_resolved,
            "remaining_seconds": self._remaining_seconds(block)
            if block.resolved_at is None
            else 0,
        }

    def _ensure_account(self, account_id: int) -> TradingAccount:
        account = self._db.get(TradingAccount, account_id)
        if account is None:
            raise HTTPException(status_code=404, detail="Account not found")
        return account
