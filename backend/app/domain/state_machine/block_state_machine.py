"""
Block State Machine implementation.

This is a pure state machine with no side effects.
It determines the appropriate state based on violations and existing blocks.
"""
from datetime import datetime, timedelta, timezone
from typing import Optional

from app.domain.entities.block_state import (
    BlockState,
    BlockType,
    UTC_OFFSET_HOURS,
)
from app.domain.state_machine.states import (
    BlockStateEnum,
    is_terminal_state,
    is_valid_transition,
    get_blocking_states,
)


# Rules that cause full-day blocks (kept in sync with rule_violation.py)
FULL_DAY_CODES = {
    "max_daily_loss_reached",
    "too_many_trades_today",
    "max_daily_profit_reached",
}


class BlockStateMachine:
    """
    Pure state machine for block lifecycle.

    No side effects - just state transitions and calculations.
    """

    def __init__(self, config: Optional[dict] = None):
        """
        Initialize the state machine.

        Args:
            config: Optional configuration dict with keys:
                - temporary_block_minutes: Duration of temporary blocks
                - cooldown_minutes: Duration of cooldown period
                - utc_offset_hours: UTC offset for trading day
        """
        self._config = config or {}
        self._temporary_minutes = self._config.get("temporary_block_minutes", 60)
        self._utc_offset = self._config.get("utc_offset_hours", UTC_OFFSET_HOURS)

    def determine_state(
        self,
        violations: list[str],
        existing_block: Optional[BlockState] = None
    ) -> BlockStateEnum:
        """
        Determine the appropriate state based on violations and existing block.

        Args:
            violations: List of triggered rule codes
            existing_block: Current active block (if any)

        Returns:
            The appropriate BlockStateEnum
        """
        if existing_block is not None:
            current_state = existing_block.current_state()
            if is_terminal_state(current_state):
                return current_state
            if existing_block.is_expired():
                return BlockStateEnum.RESOLVED
            if existing_block.is_active():
                if existing_block.is_full_day():
                    return BlockStateEnum.FULL_DAY_BLOCK
                if existing_block.is_temporary():
                    return BlockStateEnum.TEMPORARY_BLOCK

        if not violations:
            return BlockStateEnum.NORMAL

        full_day_violations = [v for v in violations if v in FULL_DAY_CODES]
        if full_day_violations:
            return BlockStateEnum.FULL_DAY_BLOCK

        return BlockStateEnum.WARNING

    def calculate_expiry(
        self,
        state: BlockStateEnum
    ) -> Optional[datetime]:
        """
        Calculate expiry time for a given state.

        Args:
            state: The block state

        Returns:
            Expiry datetime or None if no expiry (e.g., resolved)
        """
        now = datetime.now(timezone.utc)

        if state == BlockStateEnum.TEMPORARY_BLOCK:
            return now + timedelta(minutes=self._temporary_minutes)

        if state == BlockStateEnum.FULL_DAY_BLOCK:
            return self._next_trading_day_start()

        return None

    def _next_trading_day_start(self) -> datetime:
        """
        Get start of next trading day (00:00 local time).

        Local time is assumed to be UTC+7.
        """
        now = datetime.now(timezone.utc)
        # Convert to local time
        local_now = now + timedelta(hours=self._utc_offset)
        # Get next midnight
        next_day = local_now.date() + timedelta(days=1)
        # Convert back to UTC
        return datetime.combine(next_day, datetime.min.time(), tzinfo=timezone.utc) - timedelta(hours=self._utc_offset)

    def can_transition(
        self,
        from_state: BlockStateEnum,
        to_state: BlockStateEnum
    ) -> bool:
        """
        Check if transition is valid.

        Args:
            from_state: Current state
            to_state: Target state

        Returns:
            True if transition is allowed
        """
        return is_valid_transition(from_state, to_state)

    def create_block_state(
        self,
        account_id: int,
        state: BlockStateEnum,
        triggered_by: list[str]
    ) -> BlockState:
        """
        Create a BlockState entity from a state.

        Args:
            account_id: Trading account ID
            state: The block state
            triggered_by: List of rule codes that triggered the block

        Returns:
            New BlockState entity
        """
        if state not in {
            BlockStateEnum.TEMPORARY_BLOCK,
            BlockStateEnum.FULL_DAY_BLOCK,
        }:
            raise ValueError(f"Cannot create persistent block state from {state.value}")

        block_type = (
            BlockType.FULL_DAY
            if state == BlockStateEnum.FULL_DAY_BLOCK
            else BlockType.TEMPORARY
        )

        expires_at = self.calculate_expiry(state)

        return BlockState(
            account_id=account_id,
            block_type=block_type,
            triggered_by=triggered_by,
            blocked_at=datetime.now(timezone.utc),
            expires_at=expires_at,
        )

    def is_blocking(self, state: BlockStateEnum) -> bool:
        """
        Check if a state blocks trading.

        Args:
            state: The state to check

        Returns:
            True if trading is blocked in this state
        """
        return state in get_blocking_states()

    def get_block_description(self, state: BlockStateEnum) -> str:
        """
        Get human-readable description of a state.

        Args:
            state: The state

        Returns:
            Description string
        """
        descriptions = {
            BlockStateEnum.NORMAL: "Trading allowed",
            BlockStateEnum.WARNING: "Warning - rules triggered",
            BlockStateEnum.TEMPORARY_BLOCK: "Trading temporarily blocked",
            BlockStateEnum.FULL_DAY_BLOCK: "Trading blocked for the day",
            BlockStateEnum.RESOLVED: "Block resolved",
            BlockStateEnum.ARCHIVED: "Block archived",
        }
        return descriptions.get(state, "Unknown state")

    def transition(
        self,
        from_state: BlockStateEnum,
        to_state: BlockStateEnum,
    ) -> BlockStateEnum:
        """Validate and return the requested state transition."""
        if not self.can_transition(from_state, to_state):
            raise ValueError(f"Invalid block state transition: {from_state.value} -> {to_state.value}")
        return to_state
