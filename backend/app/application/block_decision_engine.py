"""
Block Decision Engine - Application service for deciding block state.

This engine receives RuleEvaluationResult and decides the appropriate
block state (NORMAL, WARNING, TEMPORARY_BLOCK, FULL_DAY_BLOCK).
It handles persistence via BlockRepository.
"""
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any, Optional

from app.domain.entities.block_state import (
    BlockState,
    BlockType,
    calculate_full_day_expiry,
    calculate_temporary_expiry,
)
from app.domain.services.rule_engine import RuleEvaluationResult
from app.domain.state_machine.states import BlockStateEnum
from app.infrastructure.persistence.block_repository import BlockRepository


# Rules that cause full-day blocks
FULL_DAY_BLOCK_CODES = {
    "max_daily_loss_reached",
    "too_many_trades_today",
    "max_daily_profit_reached",
}

# Rules that cause temporary blocks
TEMPORARY_BLOCK_CODES = {
    "high_impact_news_window",
    "revenge_trading_pattern",
    "consecutive_losses_pause_active",
    "cooling_off_active",
    "live_averaging_loss",
    "live_martingale",
    "risk_too_high",
}


@dataclass
class BlockDecision:
    """
    Result of block decision process.

    Contains the decision state and any block that was applied.
    """
    state: BlockStateEnum
    trade_blocked: bool
    reasons: list[dict]
    block_state: Optional[BlockState] = None


class BlockDecisionEngine:
    """
    Decision engine for block states.

    Responsibilities:
    - Receive RuleEvaluationResult
    - Decide appropriate block state
    - Apply block via BlockRepository
    - NEVER: evaluate rules, call UI

    This class requires database access for persistence.
    """

    def __init__(self, db_session: Any):
        """
        Initialize the decision engine.

        Args:
            db_session: Database session for persistence
        """
        self._repo = BlockRepository(db_session)

    def decide(
        self,
        rule_result: RuleEvaluationResult,
        trade_blocking_enabled: bool = True,
    ) -> BlockDecision:
        """
        Decide block state based on rule evaluation results.

        Args:
            rule_result: Result from RuleEngine
            trade_blocking_enabled: Whether trade blocking is enabled

        Returns:
            BlockDecision with state and any applied block
        """
        # Get triggered rules
        triggered_codes = rule_result.triggered_rule_codes

        # Get existing active block
        existing_block = self._repo.get_active_block(rule_result.account_id)

        # Determine blocking reasons (rules that should block trading)
        blocking_reasons = self._get_blocking_reasons(rule_result.checks)

        # Determine block state
        state = self._determine_state(triggered_codes, existing_block)

        # Check if trade should be blocked
        trade_blocked = trade_blocking_enabled and len(blocking_reasons) > 0

        # Apply block if needed
        block_state = None
        if trade_blocked and state in (BlockStateEnum.TEMPORARY_BLOCK, BlockStateEnum.FULL_DAY_BLOCK):
            # Check if we need to upgrade existing block
            block_state = self._apply_block(
                rule_result.account_id,
                state,
                blocking_reasons,
                existing_block,
            )

        return BlockDecision(
            state=state,
            trade_blocked=trade_blocked,
            reasons=blocking_reasons,
            block_state=block_state,
        )

    def _get_blocking_reasons(self, checks: list[dict]) -> list[dict]:
        """
        Extract blocking reasons from rule checks.

        Args:
            checks: List of check results from RuleEngine

        Returns:
            List of blocking reasons
        """
        reasons = []
        for check in checks:
            if not check.get("triggered"):
                continue

            rule_code = check.get("rule_code", "")
            severity = check.get("severity", "warning")

            # Only include critical severity for blocking
            if severity != "critical":
                continue

            # Only include rules that can block
            if rule_code in FULL_DAY_BLOCK_CODES or rule_code in TEMPORARY_BLOCK_CODES:
                reasons.append({
                    "rule_code": rule_code,
                    "severity": severity,
                    "message": check.get("message", ""),
                    "payload": check.get("payload", {}),
                })

        return reasons

    def _determine_state(
        self,
        triggered_codes: list[str],
        existing_block: Optional[BlockState],
    ) -> BlockStateEnum:
        """
        Determine the appropriate state based on violations.

        Args:
            triggered_codes: List of triggered rule codes
            existing_block: Existing active block (if any)

        Returns:
            Appropriate BlockStateEnum
        """
        # If there's an existing block, maintain its type
        if existing_block and existing_block.is_active():
            if existing_block.is_full_day():
                return BlockStateEnum.FULL_DAY_BLOCK
            return BlockStateEnum.TEMPORARY_BLOCK

        # No existing block - determine new state
        if not triggered_codes:
            # Check for any warnings
            return BlockStateEnum.NORMAL

        # Check for full-day violations
        full_day_violations = [
            code for code in triggered_codes
            if code in FULL_DAY_BLOCK_CODES
        ]

        if full_day_violations:
            return BlockStateEnum.FULL_DAY_BLOCK

        # Check for temporary violations
        temp_violations = [
            code for code in triggered_codes
            if code in TEMPORARY_BLOCK_CODES
        ]

        if temp_violations:
            return BlockStateEnum.TEMPORARY_BLOCK

        # Check for warnings (non-blocking)
        return BlockStateEnum.WARNING

    def _apply_block(
        self,
        account_id: int,
        state: BlockStateEnum,
        reasons: list[dict],
        existing_block: Optional[BlockState],
    ) -> BlockState:
        """
        Apply or update block state in database.

        Args:
            account_id: Trading account ID
            state: Block state to apply
            reasons: List of blocking reasons
            existing_block: Existing block (if any)

        Returns:
            Applied BlockState
        """
        # Determine block type
        block_type = (
            BlockType.FULL_DAY
            if state == BlockStateEnum.FULL_DAY_BLOCK
            else BlockType.TEMPORARY
        )

        # Calculate expiry
        if state == BlockStateEnum.FULL_DAY_BLOCK:
            expires_at = calculate_full_day_expiry()
        else:
            expires_at = calculate_temporary_expiry()

        # Get triggered by list
        triggered_by = [r["rule_code"] for r in reasons]

        # Check if we should upgrade existing block
        if existing_block and existing_block.is_active():
            # Upgrade to full-day if current is temporary
            if state == BlockStateEnum.FULL_DAY_BLOCK and existing_block.is_temporary():
                upgraded = existing_block.upgrade_to_full_day(
                    expires_at=expires_at,
                    triggered_by=triggered_by,
                )
                return self._repo.save(upgraded)
            elif state == BlockStateEnum.TEMPORARY_BLOCK and existing_block.is_full_day():
                # Keep full-day, don't downgrade
                return existing_block
            else:
                # Same type, update expiry and reasons
                existing_block.triggered_by = triggered_by
                if state == BlockStateEnum.TEMPORARY_BLOCK:
                    existing_block.expires_at = calculate_temporary_expiry()
                return self._repo.save(existing_block)

        # Create new block
        new_block = BlockState(
            account_id=account_id,
            block_type=block_type,
            triggered_by=triggered_by,
            blocked_at=datetime.now(timezone.utc),
            expires_at=expires_at,
        )

        return self._repo.save(new_block)

    def get_block_state(self, account_id: int) -> dict:
        """
        Get current block state for an account.

        Args:
            account_id: Trading account ID

        Returns:
            Dict with block state info
        """
        block = self._repo.get_active_block(account_id)

        if block is None or not block.is_active():
            return {
                "active": False,
                "block_type": None,
                "remaining_seconds": 0,
            }

        return {
            "active": True,
            "block_type": block.block_type.value if hasattr(block.block_type, 'value') else block.block_type,
            "remaining_seconds": block.remaining_seconds(),
            "expires_at": block.expires_at.isoformat() if block.expires_at else None,
            "blocked_at": block.blocked_at.isoformat() if block.blocked_at else None,
        }

    def resolve_block(self, account_id: int) -> dict:
        """
        Manually resolve block for an account.

        Args:
            account_id: Trading account ID

        Returns:
            Result dict
        """
        success = self._repo.resolve_block(account_id, manually=True)
        return {
            "success": success,
            "account_id": account_id,
            "message": "Block resolved" if success else "No active block to resolve",
        }
