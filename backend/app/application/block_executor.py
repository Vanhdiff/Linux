"""
Block Executor - Orchestrates block execution.

Responsibilities:
- Receive BlockDecision
- Persist BlockState
- Trigger EventDispatcher
- Write Audit Log
- Notify Dashboard
- Prepare for MT5 enforcement

Does NOT:
- Evaluate rules
- Calculate risk
- Modify RuleEngine
- Call frontend directly
"""
import logging
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any, Callable

from app.application.block_decision_engine import BlockDecision
from app.domain.entities.block_state import BlockState as DomainBlockState
from app.domain.state_machine.states import BlockStateEnum
from app.infrastructure.persistence.block_repository import BlockRepository

logger = logging.getLogger(__name__)


# Event types for BlockExecutor
class BlockEventType:
    BLOCK_APPLIED = "block_applied"
    BLOCK_RESOLVED = "block_resolved"
    BLOCK_UPGRADED = "block_upgraded"
    BLOCK_EXPIRED = "block_expired"


@dataclass
class BlockEvent:
    """Event emitted when a block action occurs."""
    event_type: str
    account_id: int
    block_id: int | None = None
    block_type: str | None = None
    triggered_by: list[str] = field(default_factory=list)
    timestamp: datetime = field(default_factory=lambda: datetime.now(timezone.utc))
    metadata: dict = field(default_factory=dict)


class EventDispatcher:
    """
    Simple event dispatcher for block events.

    Allows registration of handlers that are called when events occur.
    """

    def __init__(self):
        self._handlers: dict[str, list[Callable[[BlockEvent], None]]] = {}

    def register(self, event_type: str, handler: Callable[[BlockEvent], None]) -> None:
        """Register a handler for an event type."""
        if event_type not in self._handlers:
            self._handlers[event_type] = []
        self._handlers[event_type].append(handler)

    def dispatch(self, event: BlockEvent) -> None:
        """Dispatch an event to all registered handlers."""
        handlers = self._handlers.get(event.event_type, [])
        for handler in handlers:
            try:
                handler(event)
            except Exception as e:
                logger.error(f"Error in event handler for {event.event_type}: {e}")


class AuditLogger:
    """
    Writes audit logs for block operations.

    Structured logging for compliance and debugging.
    """

    def __init__(self):
        self._logger = logging.getLogger("block_audit")

    def log_block_applied(
        self,
        account_id: int,
        block_id: int,
        block_type: str,
        triggered_by: list[str],
        is_upgrade: bool = False,
    ) -> None:
        """Log block application."""
        self._logger.info(
            "BLOCK_APPLIED",
            extra={
                "account_id": account_id,
                "block_id": block_id,
                "block_type": block_type,
                "triggered_by": triggered_by,
                "is_upgrade": is_upgrade,
                "action": "upgrade" if is_upgrade else "apply",
            },
        )

    def log_block_resolved(
        self,
        account_id: int,
        block_id: int,
        resolved_by: str,  # "manual" or "auto"
    ) -> None:
        """Log block resolution."""
        self._logger.info(
            "BLOCK_RESOLVED",
            extra={
                "account_id": account_id,
                "block_id": block_id,
                "resolved_by": resolved_by,
            },
        )

    def log_block_expired(
        self,
        account_id: int,
        block_id: int,
    ) -> None:
        """Log block expiration."""
        self._logger.info(
            "BLOCK_EXPIRED",
            extra={
                "account_id": account_id,
                "block_id": block_id,
            },
        )

    def log_enforcement_ready(
        self,
        account_id: int,
        block_id: int,
        block_type: str,
    ) -> None:
        """Log MT5 enforcement preparation."""
        self._logger.info(
            "ENFORCEMENT_READY",
            extra={
                "account_id": account_id,
                "block_id": block_id,
                "block_type": block_type,
            },
        )


@dataclass
class ExecutionResult:
    """Result of block execution."""
    success: bool
    block_id: int | None = None
    block_state: dict | None = None
    events_dispatched: list[str] = field(default_factory=list)
    error: str | None = None


class BlockExecutor:
    """
    Executes block decisions.

    Coordinates persistence, events, audit, and notifications.
    """

    def __init__(self, db_session: Any):
        """
        Initialize executor with database session.

        Args:
            db_session: SQLAlchemy session for persistence
        """
        self._db = db_session
        self._repo = BlockRepository(db_session)
        self._event_dispatcher = EventDispatcher()
        self._audit_logger = AuditLogger()
        self._mt5_prepared = False

    def execute(self, decision: BlockDecision) -> ExecutionResult:
        """
        Execute a block decision.

        Args:
            decision: BlockDecision from BlockDecisionEngine

        Returns:
            ExecutionResult with execution details
        """
        # If no block needed, return success without persisting
        if not decision.trade_blocked:
            return ExecutionResult(success=True)

        try:
            # Persist block state
            block = self._persist_block(decision)

            if block is None:
                return ExecutionResult(success=True)

            # Determine event type
            event_type = self._determine_event_type(decision)

            # Create and dispatch event
            event = BlockEvent(
                event_type=event_type,
                account_id=decision.block_state.account_id if decision.block_state else 0,
                block_id=block.id,
                block_type=block.block_type.value if hasattr(block.block_type, 'value') else block.block_type,
                triggered_by=block.triggered_by,
            )
            self._event_dispatcher.dispatch(event)

            # Write audit log
            self._write_audit_log(event, decision)

            # Notify dashboard
            self._notify_dashboard(decision)

            # Prepare for MT5 enforcement
            self._prepare_mt5_enforcement(decision, block)

            return ExecutionResult(
                success=True,
                block_id=block.id,
                block_state=self._block_to_dict(block),
                events_dispatched=[event_type],
            )

        except Exception as e:
            logger.error(f"Block execution failed: {e}")
            return ExecutionResult(
                success=False,
                error=str(e),
            )

    def _persist_block(self, decision: BlockDecision) -> DomainBlockState | None:
        """
        Persist block state to database.

        Args:
            decision: BlockDecision containing block state

        Returns:
            Persisted DomainBlockState or None
        """
        if decision.block_state is None:
            return None

        # Save via repository
        return self._repo.save(decision.block_state)

    def _determine_event_type(self, decision: BlockDecision) -> str:
        """Determine which event type to dispatch."""
        if decision.block_state is None:
            return ""

        # Check if this is an upgrade
        existing = self._repo.get_active_block(decision.block_state.account_id)
        if existing and existing.id != decision.block_state.id:
            return BlockEventType.BLOCK_UPGRADED

        return BlockEventType.BLOCK_APPLIED

    def _write_audit_log(self, event: BlockEvent, decision: BlockDecision) -> None:
        """Write audit log entry."""
        if event.event_type == BlockEventType.BLOCK_APPLIED:
            self._audit_logger.log_block_applied(
                account_id=event.account_id,
                block_id=event.block_id or 0,
                block_type=event.block_type or "",
                triggered_by=event.triggered_by,
            )
        elif event.event_type == BlockEventType.BLOCK_UPGRADED:
            self._audit_logger.log_block_applied(
                account_id=event.account_id,
                block_id=event.block_id or 0,
                block_type=event.block_type or "",
                triggered_by=event.triggered_by,
                is_upgrade=True,
            )

    def _notify_dashboard(self, decision: BlockDecision) -> None:
        """
        Notify dashboard of block state change.

        Note: This prepares data for the dashboard to consume.
        Actual notification depends on the frontend's polling mechanism.
        """
        # The dashboard polls /api/guardrails/block-state
        # This method can be extended to push updates via WebSocket
        # For now, we log that dashboard should refresh
        if decision.block_state:
            logger.info(
                f"Dashboard notification: account {decision.block_state.account_id} "
                f"block state changed to {decision.block_state.block_type}"
            )

    def _prepare_mt5_enforcement(
        self,
        decision: BlockDecision,
        block: DomainBlockState,
    ) -> None:
        """
        Prepare for MT5 trade enforcement.

        This updates state that the Mt5TradeBlocker will read.
        The actual blocking happens in the background MT5 blocker.
        """
        self._audit_logger.log_enforcement_ready(
            account_id=block.account_id,
            block_id=block.id,
            block_type=block.block_type.value if hasattr(block.block_type, 'value') else block.block_type,
        )
        self._mt5_prepared = True

    def _block_to_dict(self, block: DomainBlockState) -> dict:
        """Convert block to dictionary for response."""
        return {
            "id": block.id,
            "account_id": block.account_id,
            "block_type": block.block_type.value if hasattr(block.block_type, 'value') else block.block_type,
            "triggered_by": block.triggered_by,
            "blocked_at": block.blocked_at.isoformat() if block.blocked_at else None,
            "expires_at": block.expires_at.isoformat() if block.expires_at else None,
            "remaining_seconds": block.remaining_seconds(),
        }

    # ------------------------------------------------------------------
    # Event registration for external handlers
    # ------------------------------------------------------------------

    def on_block_applied(self, handler: Callable[[BlockEvent], None]) -> None:
        """Register handler for block applied events."""
        self._event_dispatcher.register(BlockEventType.BLOCK_APPLIED, handler)

    def on_block_resolved(self, handler: Callable[[BlockEvent], None]) -> None:
        """Register handler for block resolved events."""
        self._event_dispatcher.register(BlockEventType.BLOCK_RESOLVED, handler)

    def on_block_upgraded(self, handler: Callable[[BlockEvent], None]) -> None:
        """Register handler for block upgraded events."""
        self._event_dispatcher.register(BlockEventType.BLOCK_UPGRADED, handler)
