"""
Block Decision Engine - Application service for deciding block state.

This engine receives RuleEvaluationResult and decides the appropriate
block state (NORMAL, WARNING, TEMPORARY_BLOCK, FULL_DAY_BLOCK).
"""
from dataclasses import dataclass
from typing import Any, Optional

from app.domain.entities.block_state import (
    BlockState,
)
from app.domain.services.rule_engine import RuleEvaluationResult
from app.domain.state_machine.block_state_machine import BlockStateMachine
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
    action: str = "none"


class BlockDecisionEngine:
    """
    Decision engine for block states.

    Responsibilities:
    - Receive RuleEvaluationResult
    - Decide appropriate block state
    - Build the next in-memory block state
    - NEVER: persist, evaluate rules, call UI
    """

    def __init__(self, db_session: Any):
        """
        Initialize the decision engine.

        Args:
            db_session: Database session for persistence
        """
        self._repo = BlockRepository(db_session)
        self._state_machine = BlockStateMachine()

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
        state = self._state_machine.determine_state(triggered_codes, existing_block)

        # Check if trade should be blocked
        trade_blocked = trade_blocking_enabled and len(blocking_reasons) > 0

        # Build the next block state if needed. Persistence belongs to BlockExecutor.
        block_state = None
        action = "none"
        if trade_blocked and state in (BlockStateEnum.TEMPORARY_BLOCK, BlockStateEnum.FULL_DAY_BLOCK):
            block_state, action = self._build_next_block_state(
                account_id=rule_result.account_id,
                state=state,
                reasons=blocking_reasons,
                existing_block=existing_block,
            )

        return BlockDecision(
            state=state,
            trade_blocked=trade_blocked,
            reasons=blocking_reasons,
            block_state=block_state,
            action=action,
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

            # Include rules that can block. Some full-day business rules are
            # intentionally warning severity for UI display, but still become
            # blocking when GuardrailService has selected them as block reasons.
            if rule_code in FULL_DAY_BLOCK_CODES or rule_code in TEMPORARY_BLOCK_CODES:
                reasons.append({
                    "rule_code": rule_code,
                    "severity": severity,
                    "message": check.get("message", ""),
                    "payload": check.get("payload", {}),
                })

        return reasons

    def _build_next_block_state(
        self,
        *,
        account_id: int,
        state: BlockStateEnum,
        reasons: list[dict],
        existing_block: Optional[BlockState],
    ) -> tuple[BlockState, str]:
        """Build the next block state without persisting it."""
        triggered_by = [r["rule_code"] for r in reasons]

        if existing_block and existing_block.is_active():
            existing_block.triggered_by = triggered_by
            existing_block.payload = {
                **dict(existing_block.payload or {}),
                "reasons": reasons,
            }

            if state == BlockStateEnum.FULL_DAY_BLOCK and existing_block.is_temporary():
                existing_block.upgrade_to_full_day(
                    expires_at=self._state_machine.calculate_expiry(
                        state,
                        triggered_by=triggered_by,
                    ),
                    triggered_by=triggered_by,
                )
                existing_block.payload["reasons"] = reasons
                return existing_block, "upgrade"

            if state == BlockStateEnum.TEMPORARY_BLOCK and existing_block.is_full_day():
                return existing_block, "none"

            existing_block.expires_at = self._state_machine.calculate_expiry(
                state,
                triggered_by=triggered_by,
            )
            return existing_block, "refresh"

        new_block = self._state_machine.create_block_state(
            account_id=account_id,
            state=state,
            triggered_by=triggered_by,
        )
        new_block.payload = {"reasons": reasons}
        return new_block, "create"

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
                "triggered_by": [],
            }

        return {
            "active": True,
            "block_type": block.block_type.value if hasattr(block.block_type, 'value') else block.block_type,
            "remaining_seconds": block.remaining_seconds(),
            "triggered_by": list(block.triggered_by or []),
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
